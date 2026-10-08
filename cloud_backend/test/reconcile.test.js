import { test, describe, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { startTestDb } from './helpers/db.js';
import { installFakeVast } from './helpers/fakeVast.js';
import { makeUser, makeInstance } from './helpers/factories.js';
import { reconcileService } from '../src/services/reconcile.service.js';
import { classifyRecords } from '../scripts/cleanup_stale_gpu_instances.mjs';
import { User } from '../src/models/User.js';
import { GPU_STATUS } from '../src/config/constants.js';

const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const hoursAgo = (h) => Date.now() / 1000 - h * 3600;

describe('reconciliation', () => {
  let db;
  let vast;
  before(async () => { db = await startTestDb(); });
  after(async () => { await db.stop(); });
  beforeEach(async () => { await db.clear(); vast = installFakeVast(); });
  afterEach(() => vast.restore());

  test('reports labelled orphans older than 15 min; destroys only when enabled', async () => {
    const user = await makeUser(100);
    await makeInstance(user, { providerInstanceId: '500' }); // active record: not an orphan
    vast.addInstance('500', { label: 'cosmicgen-a', start_date: hoursAgo(2) });
    vast.addInstance('501', { label: 'cosmicgen-b', start_date: hoursAgo(2) }); // no record
    vast.addInstance('502', { label: 'cosmicgen-c', start_date: hoursAgo(0.1) }); // too young
    vast.addInstance('503', { label: 'someone-else', start_date: hoursAgo(2) }); // not ours
    await makeInstance(user, { providerInstanceId: '504', status: GPU_STATUS.FAILED });
    vast.addInstance('504', { label: 'cosmicgen-d', start_date: hoursAgo(1) }); // record is terminal

    const logged = await reconcileService.runOnce({ destroyOrphans: false });
    assert.deepEqual(logged.orphans.map((o) => o.contractId).sort(), ['501', '504']);
    assert.equal(vast.calls.destroy.length, 0);

    const destroyed = await reconcileService.runOnce({ destroyOrphans: true });
    assert.deepEqual(destroyed.destroyed.sort(), ['501', '504']);
  });

  test('lowers drifted slot counters to the slots actually held', async () => {
    const user = await makeUser(100, { activeGpuInstances: 2 });
    await makeInstance(user, { holdsSlot: true });
    const r = await reconcileService.runOnce({ destroyOrphans: false });
    assert.equal(r.slotFixes, 1);
    assert.equal((await User.findById(user._id).lean()).activeGpuInstances, 1);
  });
});

test('cleanup script classifies test, pending, missing and exited records as stale', () => {
  const records = [
    { _id: 'a', status: 'ready', providerInstanceId: '54547010' },
    { _id: 'b', status: 'ready', providerInstanceId: 'test-contract-1791101619182' },
    { _id: 'c', status: 'ready', providerInstanceId: 'pending-1791099211934' },
    { _id: 'd', status: 'ready', providerInstanceId: '777' },
    { _id: 'e', status: 'ready', providerInstanceId: '888' },
  ];
  const vastList = [{ id: 777, actual_status: 'running' }, { id: 888, actual_status: 'exited' }];
  const byId = Object.fromEntries(classifyRecords(records, vastList).map((r) => [r.record._id, r]));
  assert.equal(byId.a.stale, true);
  assert.match(byId.a.reason, /no longer exists/);
  assert.equal(byId.b.stale, true);
  assert.equal(byId.c.stale, true);
  assert.equal(byId.d.stale, false);
  assert.equal(byId.e.stale, true);
  assert.match(byId.e.reason, /exited/);
});

test('in production without a Vast.ai key, GPU endpoints answer 503 and sandbox paths are blocked', () => {
  const script = `
    const { default: request } = await import('supertest');
    const { createApp } = await import('./src/app.js');
    const { vastaiService } = await import('./src/services/vastai.service.js');
    const app = createApp();
    const out = {};
    for (const p of ['/api/v1/gpu/offers', '/api/v1/gpu/recommended', '/api/v1/gpu/rent']) {
      const res = p.endsWith('rent') ? await request(app).post(p).send({}) : await request(app).get(p);
      out[p] = res.status;
    }
    try { await vastaiService.createInstance('1', {}); out.create = 'no error'; } catch (e) { out.create = e.statusCode; }
    try { await vastaiService.destroyInstance('1'); out.destroy = 'no error'; } catch (e) { out.destroy = e.statusCode; }
    try { await vastaiService.listInstancesStrict(); out.list = 'no error'; } catch (e) { out.list = e.statusCode; }
    console.log(JSON.stringify(out));
  `;
  const r = spawnSync(process.execPath, ['--input-type=module', '-e', script], {
    cwd: backendRoot,
    env: {
      PATH: process.env.PATH,
      NODE_ENV: 'production',
      MONGODB_URI: 'mongodb://127.0.0.1:9/never-connect',
      JWT_ACCESS_SECRET: process.env.JWT_ACCESS_SECRET,
      JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET,
    },
    encoding: 'utf8',
    timeout: 30_000,
  });
  assert.equal(r.status, 0, r.stderr);
  const out = JSON.parse(r.stdout.trim().split('\n').pop());
  assert.deepEqual(out, {
    '/api/v1/gpu/offers': 503,
    '/api/v1/gpu/recommended': 503,
    '/api/v1/gpu/rent': 503,
    create: 503,
    destroy: 503,
    list: 503,
  });
});
