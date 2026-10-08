import { test, describe, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { startTestDb } from './helpers/db.js';
import { installFakeVast } from './helpers/fakeVast.js';
import { makeUser, makeInstance } from './helpers/factories.js';
import { InstancePollerService } from '../src/services/instancePoller.service.js';
import { GpuInstance } from '../src/models/GpuInstance.js';
import { User } from '../src/models/User.js';
import { GPU_STATUS } from '../src/config/constants.js';

const T0 = new Date('2026-10-07T18:00:00Z');
const at = (s) => new Date(T0.getTime() + s * 1000);
const reload = (inst) => GpuInstance.findById(inst._id).lean();

describe('instance poller', () => {
  let db;
  let vast;
  let engine;
  let engineUrl;
  let health = { models: [{ modelId: 'realesrgan-x4plus', status: 'ready' }], device: 'cuda' };

  before(async () => {
    db = await startTestDb();
    engine = http.createServer((req, res) => {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify(health));
    });
    await new Promise((r) => engine.listen(0, '127.0.0.1', r));
    engineUrl = `http://127.0.0.1:${engine.address().port}`;
  });
  after(async () => {
    engine.close();
    await db.stop();
  });
  beforeEach(async () => {
    await db.clear();
    vast = installFakeVast();
  });
  afterEach(() => vast.restore());

  const poller = () => new InstancePollerService({ providerCheckIntervalMs: 0, newContractGraceMs: 0 });

  test('READY/RUNNING instances are watched, with one Vast.ai listing per cycle', async () => {
    const user = await makeUser(100);
    for (const id of ['1', '2', '3']) {
      await makeInstance(user, { providerInstanceId: id, contractConfirmedAt: T0, billedUntil: T0 });
      vast.addInstance(id);
    }
    await poller().pollCycle(at(60));
    assert.equal(vast.calls.list, 1);
  });

  test('two misses at least a minute apart stop the instance and settle up to when it was last seen', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, {
      contractConfirmedAt: T0,
      billedUntil: at(60),
      lastSeenOnVastAt: at(90),
      reachedReadyAt: T0,
      holdsSlot: true,
    });
    await User.updateOne({ _id: user._id }, { $set: { activeGpuInstances: 1 } });
    const p = poller();

    await p.pollCycle(at(120)); // miss 1
    assert.equal((await reload(inst)).status, GPU_STATUS.READY);
    await p.pollCycle(at(150)); // miss 2, only 30 s later
    assert.equal((await reload(inst)).status, GPU_STATUS.READY);
    await p.pollCycle(at(185)); // miss 3, 65 s after the first
    const fresh = await reload(inst);
    assert.equal(fresh.status, GPU_STATUS.STOPPED);
    assert.equal(fresh.stopReason, 'provider_gone');
    // Charged 60 s -> 90 s (last seen) at 0.01/s, not up to the detection time.
    assert.ok(Math.abs(fresh.creditsCharged - 0.3) < 1e-6, String(fresh.creditsCharged));
    assert.equal((await User.findById(user._id).lean()).activeGpuInstances, 0);
  });

  test('a failed listing is not counted as a miss', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, { contractConfirmedAt: T0, billedUntil: T0 });
    vast.failList = true;
    const p = poller();
    for (const s of [60, 130, 200, 270]) await p.pollCycle(at(s));
    const fresh = await reload(inst);
    assert.equal(fresh.status, GPU_STATUS.READY);
    assert.equal(fresh.vastMissCount, 0);
  });

  test('an exited contract is destroyed, stopped, and refunded if it never became ready', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, {
      status: GPU_STATUS.PROVISIONING,
      contractConfirmedAt: T0,
      billedUntil: T0,
      startedAt: T0,
      creditsCharged: 0.6,
    });
    await User.updateOne({ _id: user._id }, { $inc: { credits: -0.6 } });
    vast.addInstance(inst.providerInstanceId, { actual_status: 'exited' });
    const p = poller();
    await p.pollCycle(at(60));
    await p.pollCycle(at(125));
    const fresh = await reload(inst);
    assert.equal(fresh.status, GPU_STATUS.STOPPED);
    assert.deepEqual(vast.calls.destroy, [inst.providerInstanceId]);
    assert.ok(Math.abs(fresh.creditsRefunded - 0.6) < 1e-9);
    assert.ok(Math.abs((await User.findById(user._id).lean()).credits - 100) < 1e-9);
  });

  test('provisioning timeout destroys, fails and refunds', async () => {
    const user = await makeUser(100);
    const startedAt = new Date(Date.now() - 26 * 60_000);
    const inst = await makeInstance(user, {
      status: GPU_STATUS.PROVISIONING,
      startedAt,
      contractConfirmedAt: startedAt,
      billedUntil: new Date(Date.now() - 60_000),
      creditsCharged: 15,
    });
    await User.updateOne({ _id: user._id }, { $inc: { credits: -15 } });
    vast.addInstance(inst.providerInstanceId);

    await poller().pollCycle(new Date());
    const fresh = await reload(inst);
    assert.equal(fresh.status, GPU_STATUS.FAILED);
    assert.equal(fresh.stopReason, 'provisioning_timeout');
    assert.deepEqual(vast.calls.destroy, [inst.providerInstanceId]);
    // The last minute is charged on settlement, then everything is refunded.
    assert.ok(Math.abs(fresh.creditsRefunded - fresh.creditsCharged) < 1e-9);
    assert.ok(Math.abs((await User.findById(user._id).lean()).credits - 100) < 1e-6);
  });

  test('a healthy engine moves the instance to READY and records reachedReadyAt', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, {
      status: GPU_STATUS.PROVISIONING,
      contractConfirmedAt: new Date(),
      billedUntil: new Date(),
      startedAt: new Date(),
      pythonEngineUrl: engineUrl,
    });
    vast.addInstance(inst.providerInstanceId);
    await poller().pollCycle(new Date());
    const fresh = await reload(inst);
    assert.equal(fresh.status, GPU_STATUS.READY);
    assert.ok(fresh.reachedReadyAt);
  });

  test('a stop made meanwhile is never overwritten by a health result', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, {
      status: GPU_STATUS.PROVISIONING,
      contractConfirmedAt: new Date(),
      billedUntil: new Date(),
      startedAt: new Date(),
      pythonEngineUrl: engineUrl,
    });
    vast.addInstance(inst.providerInstanceId);
    const p = poller();
    const doc = await GpuInstance.findById(inst._id); // the poller's stale in-memory copy
    await GpuInstance.updateOne({ _id: inst._id }, { $set: { status: GPU_STATUS.STOPPED } });
    await p.pollInstance(doc, { now: new Date() });
    assert.equal((await reload(inst)).status, GPU_STATUS.STOPPED);
  });

  test('the engine endpoint is discovered from the instance list', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, {
      status: GPU_STATUS.PROVISIONING,
      contractConfirmedAt: new Date(),
      billedUntil: new Date(),
      startedAt: new Date(),
    });
    vast.addInstance(inst.providerInstanceId, {
      public_ipaddr: '127.0.0.1',
      ports: { '8000/tcp': [{ HostPort: '9' }] }, // closed port: health check fails fast
    });
    await new InstancePollerService({ providerCheckIntervalMs: 60_000 }).pollCycle(new Date());
    assert.equal((await reload(inst)).pythonEngineUrl, 'http://127.0.0.1:9');
  });
});
