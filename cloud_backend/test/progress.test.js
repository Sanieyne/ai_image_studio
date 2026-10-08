import { test, describe, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import { startTestDb } from './helpers/db.js';
import { installFakeVast } from './helpers/fakeVast.js';
import { makeUser, makeInstance } from './helpers/factories.js';
import { InstancePollerService } from '../src/services/instancePoller.service.js';
import { instanceEvents } from '../src/services/instanceEvents.js';
import { instanceProgressView } from '../src/controllers/gpu.controller.js';
import { hostUnsupportedReason, vastaiService } from '../src/services/vastai.service.js';
import { gpuProviderService } from '../src/services/gpuProvider.service.js';
import { GpuInstance } from '../src/models/GpuInstance.js';
import { User } from '../src/models/User.js';
import { GPU_STATUS } from '../src/config/constants.js';

const reload = (inst) => GpuInstance.findById(inst._id).lean();

describe('provisioning progress', () => {
  let db;
  let vast;
  let engine;
  let engineUrl;
  let health;
  let events;
  const onEvent = (e) => events.push(e);

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
    events = [];
    instanceEvents.on('status_change', onEvent);
  });
  afterEach(() => {
    vast.restore();
    instanceEvents.off('status_change', onEvent);
  });

  const poller = () =>
    new InstancePollerService({ providerCheckIntervalMs: 0, newContractGraceMs: 0, provisioningListIntervalMs: 0 });
  const provisioning = (user, extra = {}) =>
    makeInstance(user, {
      status: GPU_STATUS.PROVISIONING,
      providerInstanceId: '700001',
      contractConfirmedAt: new Date(Date.now() - 90_000),
      startedAt: new Date(Date.now() - 90_000),
      billedUntil: new Date(Date.now() - 90_000),
      modelsRequested: ['realesrgan-x4plus'],
      ...extra,
    });

  test("relays Vast.ai's own status while the host starts, logging each step once", async () => {
    const user = await makeUser(100);
    const inst = await provisioning(user);
    vast.addInstance('700001', { actual_status: 'loading', status_msg: 'Pulling image layer 3/12' });

    const p = poller();
    await p.pollCycle();
    await p.pollCycle(); // nothing changed: no new log line, no new event
    let fresh = await reload(inst);
    assert.equal(fresh.progress.stage, 'starting');
    assert.equal(fresh.progress.vastStatus, 'loading');
    assert.equal(fresh.progress.vastStatusMessage, 'Pulling image layer 3/12');
    assert.match(fresh.progress.message, /starting the GPU \(loading: Pulling image layer 3\/12\)/);
    assert.equal(fresh.provisioningLogs.filter((l) => /Pulling image/.test(l.message)).length, 1);
    assert.equal(events.length, 1);
    const ev = events[0];
    assert.equal(ev.instanceId, String(inst._id));
    assert.equal(ev.details.progress.stage, 'starting');
    assert.ok(ev.details.elapsedSeconds >= 89, String(ev.details.elapsedSeconds));
    assert.equal(typeof ev.details.creditsCharged, 'number');

    // Running, but no port mapped yet.
    vast.addInstance('700001', { actual_status: 'running', status_msg: 'success, running pytorch' });
    await p.pollCycle();
    fresh = await reload(inst);
    assert.equal(fresh.progress.stage, 'waiting_for_port');
    assert.equal(events.at(-1).details.progress.stage, 'waiting_for_port');
  });

  test('port mapped but engine not answering: "installing and starting the engine"', async () => {
    const user = await makeUser(100);
    const inst = await provisioning(user, { pythonEngineUrl: 'http://127.0.0.1:9', publicIp: '127.0.0.1' });
    vast.addInstance('700001');
    await poller().pollCycle();
    const fresh = await reload(inst);
    assert.equal(fresh.progress.stage, 'engine_starting');
    assert.equal(fresh.progress.portFound, true);
    assert.equal(fresh.progress.engineReachable, false);
    assert.equal(fresh.status, GPU_STATUS.PROVISIONING);
  });

  test('per-model download progress is relayed', async () => {
    const user = await makeUser(100);
    const inst = await provisioning(user, { pythonEngineUrl: engineUrl });
    vast.addInstance('700001');
    health = { status: 'ok-standby', models: [{ modelId: 'realesrgan-x4plus', status: 'downloading', progressPercent: 45.2 }] };
    await poller().pollCycle();
    const fresh = await reload(inst);
    assert.equal(fresh.status, GPU_STATUS.DOWNLOADING_MODEL);
    assert.equal(fresh.progress.stage, 'downloading_models');
    assert.match(fresh.progress.message, /Downloading realesrgan-x4plus \(45%\) — 0 of 1 models ready/);
    assert.deepEqual(fresh.progress.models.map((m) => [m.modelId, m.status, m.progressPercent]), [
      ['realesrgan-x4plus', 'downloading', 45],
    ]);
    assert.ok(events.some((e) => e.details.progress?.models?.[0]?.progressPercent === 45));
  });

  test('engine self-test failure: stopped at once with the reason, refunded', async () => {
    const user = await makeUser(100);
    const inst = await provisioning(user, { pythonEngineUrl: engineUrl, creditsCharged: 1.5 });
    await User.updateOne({ _id: user._id }, { $inc: { credits: -1.5 } });
    vast.addInstance('700001');
    health = { status: 'failed', reason: 'GPU RTX 9090 (sm_130) is not supported by this torch build', models: [] };

    await poller().pollCycle();
    const fresh = await reload(inst);
    assert.equal(fresh.status, GPU_STATUS.FAILED);
    assert.equal(fresh.stopReason, 'engine_failed');
    assert.deepEqual(vast.calls.destroy, ['700001']);
    assert.match(fresh.progress.failureReason, /sm_130/);
    assert.ok(Math.abs(fresh.creditsRefunded - fresh.creditsCharged) < 1e-9);
    assert.ok(Math.abs((await User.findById(user._id).lean()).credits - 100) < 1e-6);
    const final = events.at(-1);
    assert.equal(final.status, 'FAILED');
    assert.equal(final.details.reason, 'ENGINE_FAILED');
    assert.match(final.details.message, /The engine could not start: GPU RTX 9090.*refunded/);
  });

  test('a selected model that fails to load stops the rental with that reason', async () => {
    const user = await makeUser(100);
    const inst = await provisioning(user, { pythonEngineUrl: engineUrl });
    vast.addInstance('700001');
    health = {
      status: 'ok-standby',
      models: [{ modelId: 'realesrgan-x4plus', status: 'failed', error: 'download failed; disk full' }],
    };
    await poller().pollCycle();
    const fresh = await reload(inst);
    assert.equal(fresh.status, GPU_STATUS.FAILED);
    assert.match(fresh.progress.failureReason, /Model realesrgan-x4plus could not be loaded: download failed; disk full/);
  });

  test('provisioning timeout names the last step reached', async () => {
    const user = await makeUser(100);
    const startedAt = new Date(Date.now() - 26 * 60_000);
    const inst = await provisioning(user, {
      startedAt,
      contractConfirmedAt: startedAt,
      billedUntil: startedAt,
      progress: { stage: 'engine_starting', message: 'The GPU is running. Installing and starting the engine' },
    });
    vast.addInstance('700001');
    await poller().pollCycle();
    const fresh = await reload(inst);
    assert.equal(fresh.status, GPU_STATUS.FAILED);
    assert.match(fresh.provisioningLogs.at(-1).message, /did not become ready within 25 minutes \(last step: The GPU is running/);
    assert.match(fresh.provisioningLogs.at(-1).message, /refunded/);
  });

  test('the instance view has progress, the last 20 log lines, elapsed time and credits', async () => {
    const user = await makeUser(100);
    const logs = Array.from({ length: 30 }, (_, i) => ({ message: `step ${i}`, level: 'info' }));
    const inst = await provisioning(user, {
      provisioningLogs: logs,
      creditsCharged: 0.42,
      progress: { stage: 'engine_starting', message: 'Installing', portFound: true },
      pricing: { totalCreditsPerHour: 4.62 },
    });
    const view = instanceProgressView(await reload(inst));
    assert.equal(view.provisioningLogs.length, 20);
    assert.equal(view.provisioningLogs[0].message, 'step 10');
    assert.equal(view.progress.stage, 'engine_starting');
    assert.ok(view.elapsedSeconds >= 89);
    assert.deepEqual(view.billing, { creditsCharged: 0.42, creditsRefunded: 0, creditsPerHour: 4.62, stopReason: null });
    assert.equal(view.holdsSlot, undefined);
  });
});

describe('hosts the engine can run on', () => {
  test('older GPUs, old drivers and hosts without direct ports are refused', () => {
    assert.match(hostUnsupportedReason({ gpu_name: 'GTX 1080 Ti', compute_cap: 610, cuda_max_good: 12.8 }), /too old/);
    assert.match(hostUnsupportedReason({ compute_cap: 890, cuda_max_good: 12.4 }), /CUDA 12.4.*12.8/);
    assert.match(hostUnsupportedReason({ compute_cap: 890, cuda_max_good: 13, direct_port_count: 0 }), /port/);
    assert.equal(hostUnsupportedReason({ compute_cap: 750, cuda_max_good: 12.8, direct_port_count: 3 }), null);
    assert.equal(hostUnsupportedReason({ compute_cap: 1200, cuda_max_good: 13.0, direct_port_count: 99 }), null);
  });

  test('renting an unsupported offer fails before any contract is made', async () => {
    const db = await startTestDb();
    const vast = installFakeVast();
    try {
      vast.offer = vastaiService.normalizeOffer({
        id: 1, gpu_name: 'GTX 1080 Ti', compute_cap: 610, cuda_max_good: 12.8, direct_port_count: 5,
        dph_base: 0.1, storage_cost: 0.2, inet_down: 800, inet_down_cost: 0.001, inet_up_cost: 0.001,
      });
      const user = await makeUser(500);
      await assert.rejects(
        gpuProviderService.rentGPU({ userId: user._id, offerId: '1', storageGB: 50, selectedModelIds: [] }),
        /too old for the engine/
      );
      assert.equal(vast.calls.create.length, 0);
    } finally {
      vast.restore();
      await db.stop();
    }
  });
});

describe('startup script sent to rented instances', () => {
  const script = fs.readFileSync(new URL('../src/scripts/onstart.sh', import.meta.url), 'utf8');

  test('installs the locked set, runs the self-test, reports failures on /health', () => {
    assert.match(script, /requirements-cloud\.lock -c constraints-cloud\.txt/);
    assert.match(script, /self_test\.py --json/);
    assert.match(script, /"status": "failed", "reason": reason/);
    assert.match(script, /AI_STUDIO_REQUIRE_CUDA=1/);
  });

  test('never downloads from Hugging Face and no longer copies secrets into /etc/environment', () => {
    assert.match(script, /export HF_HUB_OFFLINE=1/);
    assert.match(script, /export AI_STUDIO_MODE=cloud/);
    assert.doesNotMatch(script, /\/etc\/environment/);
    assert.doesNotMatch(script, /^set -e\b/m);
  });

  test('rent sends that script with the engine image', async () => {
    const db = await startTestDb();
    const vast = installFakeVast();
    try {
      vast.offer = vastaiService.normalizeOffer({
        id: 2, gpu_name: 'RTX 4060 Ti', compute_cap: 890, cuda_max_good: 13, direct_port_count: 99,
        dph_base: 0.16, storage_cost: 0.2, inet_down: 800, inet_down_cost: 0.004, inet_up_cost: 0.004,
      });
      const user = await makeUser(500);
      await gpuProviderService.rentGPU({ userId: user._id, offerId: '2', storageGB: 50, selectedModelIds: ['realesrgan-x4plus'] });
      const { config } = vast.calls.create[0];
      assert.equal(config.onstart, script);
      assert.equal(config.image, 'pytorch/pytorch:2.11.0-cuda12.8-cudnn9-runtime');
      assert.equal(config.env.AI_STUDIO_MODE, 'cloud');
      assert.equal(config.env.AI_STUDIO_SELECTED_MODELS, 'realesrgan-x4plus');
    } finally {
      vast.restore();
      await db.stop();
    }
  });
});
