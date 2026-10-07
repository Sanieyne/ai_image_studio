import { test, describe, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { startTestDb } from './helpers/db.js';
import { installFakeVast } from './helpers/fakeVast.js';
import { makeUser } from './helpers/factories.js';
import { gpuProviderService } from '../src/services/gpuProvider.service.js';
import { vastaiService } from '../src/services/vastai.service.js';
import { GpuInstance } from '../src/models/GpuInstance.js';
import { User } from '../src/models/User.js';
import { GPU_STATUS } from '../src/config/constants.js';

const RAW_OFFER = {
  id: 52678380,
  gpu_name: 'RTX 4060 Ti',
  gpu_ram: 16380,
  num_gpus: 1,
  total_flops: 21.6,
  dph_total: 0.1617,
  dph_base: 0.1617,
  storage_cost: 0.1,
  inet_up: 693,
  inet_down: 736,
  inet_down_cost: 0.0098,
  reliability2: 0.99,
  cuda_max_good: 13,
  geolocation: 'Pennsylvania, US',
  direct_port_count: 99,
  cpu_cores_effective: 6,
  cpu_ram: 64400,
  disk_space: 314,
  verified: true,
  rentable: true,
};

const rentParams = (user, extra = {}) => ({
  userId: user._id,
  offerId: '52678380',
  storageGB: 50,
  selectedModelIds: ['realesrgan-x4plus'],
  ...extra,
});

describe('rentGPU', () => {
  let db;
  let vast;
  before(async () => { db = await startTestDb(); });
  after(async () => { await db.stop(); });
  beforeEach(async () => {
    await db.clear();
    vast = installFakeVast();
    vast.offer = vastaiService.normalizeOffer(RAW_OFFER);
  });
  afterEach(() => vast.restore());

  test('creates a labelled contract from offer.id and starts billing at confirmation', async () => {
    const user = await makeUser(500);
    const before = Date.now();
    // The request carries a different spelling of the id; the offer's own id is used.
    const inst = await gpuProviderService.rentGPU(rentParams(user, { offerId: ' 52678380 ' }));

    assert.equal(vast.calls.create.length, 1);
    assert.equal(String(vast.calls.create[0].offerId), String(vast.offer.id));
    assert.equal(vast.calls.create[0].config.label, `cosmicgen-${inst._id}`);
    assert.match(inst.providerInstanceId, /^\d+$/);
    assert.ok(inst.billedUntil.getTime() >= before);
    assert.equal(inst.billedUntil.getTime(), inst.contractConfirmedAt.getTime());
    assert.equal(inst.holdsSlot, true);
    assert.equal((await User.findById(user._id).lean()).activeGpuInstances, 1);
  });

  test('concurrent rent requests never exceed the per-user cap', async () => {
    const user = await makeUser(500);
    const results = await Promise.allSettled(
      Array.from({ length: 6 }, () => gpuProviderService.rentGPU(rentParams(user)))
    );
    const ok = results.filter((r) => r.status === 'fulfilled');
    const refused = results.filter((r) => r.status === 'rejected');
    assert.equal(ok.length, 1);
    assert.equal(refused.length, 5);
    assert.ok(refused.every((r) => r.reason.statusCode === 409), refused.map((r) => r.reason.message).join('; '));
    assert.equal(vast.calls.create.length, 1);
    assert.equal(await GpuInstance.countDocuments({ user: user._id }), 1);
    assert.equal((await User.findById(user._id).lean()).activeGpuInstances, 1);
  });

  test('a stopped instance frees the slot for the next rental', async () => {
    const user = await makeUser(500);
    const first = await gpuProviderService.rentGPU(rentParams(user));
    await gpuProviderService.terminateInstance(user._id, first._id);
    const second = await gpuProviderService.rentGPU(rentParams(user));
    assert.ok(second._id);
    assert.equal((await User.findById(user._id).lean()).activeGpuInstances, 1);
  });

  test('requires one hour of the offer (or minLaunchCredits) on the balance', async () => {
    const perHour = vast.offer.creditsPerHour; // compute only; storage adds to it
    const user = await makeUser(Math.max(1, perHour * 0.5));
    await assert.rejects(gpuProviderService.rentGPU(rentParams(user)), (err) => err.statusCode === 402);
    assert.equal(vast.calls.create.length, 0);
    assert.equal((await User.findById(user._id).lean()).activeGpuInstances, 0);
  });

  test('stopping during provisioning destroys the contract when it arrives, without charging', async () => {
    const user = await makeUser(500);
    let open;
    vast.createGate = new Promise((resolve) => { open = resolve; });

    const renting = gpuProviderService.rentGPU(rentParams(user));
    // Wait until the record exists, then stop it while the create call is still pending.
    let pending;
    for (let i = 0; i < 100 && !pending; i += 1) {
      pending = await GpuInstance.findOne({ user: user._id });
      if (!pending) await new Promise((r) => setTimeout(r, 10));
    }
    await gpuProviderService.terminateInstance(user._id, pending._id);
    open();
    const result = await renting;

    assert.equal(result.status, GPU_STATUS.STOPPED);
    assert.equal(vast.calls.destroy.length, 1);
    assert.equal(vast.calls.destroy[0], result.providerInstanceId);
    assert.equal(vast.instances.size, 0);
    assert.equal(result.creditsCharged, 0);
    assert.equal((await User.findById(user._id).lean()).credits, 500);
    assert.equal((await User.findById(user._id).lean()).activeGpuInstances, 0);
  });

  test('a failed create call marks the rental failed and frees the slot', async () => {
    const user = await makeUser(500);
    vastaiService.createInstance = async () => { throw new Error('host refused'); };
    await assert.rejects(gpuProviderService.rentGPU(rentParams(user)), /host refused/);
    const inst = await GpuInstance.findOne({ user: user._id }).lean();
    assert.equal(inst.status, GPU_STATUS.FAILED);
    assert.equal(inst.stopReason, 'provisioning_failed');
    assert.equal((await User.findById(user._id).lean()).activeGpuInstances, 0);
  });

  test('user stop settles the final charge up to the stop time', async () => {
    const user = await makeUser(500);
    const inst = await gpuProviderService.rentGPU(rentParams(user));
    // Pretend the contract was confirmed two minutes ago and the instance reached READY.
    const twoMinAgo = new Date(Date.now() - 120_000);
    await GpuInstance.updateOne(
      { _id: inst._id },
      { $set: { billedUntil: twoMinAgo, billingStartedAt: twoMinAgo, reachedReadyAt: twoMinAgo } }
    );

    const stopped = await gpuProviderService.terminateInstance(user._id, inst._id);
    const expected = (inst.pricing.totalCreditsPerHour * 120) / 3600;
    assert.equal(stopped.status, GPU_STATUS.STOPPED);
    assert.equal(stopped.stopReason, 'user_stopped');
    assert.ok(Math.abs(stopped.creditsCharged - expected) < expected * 0.02, `${stopped.creditsCharged} vs ${expected}`);
    assert.deepEqual(vast.calls.destroy, [inst.providerInstanceId]);
  });

  test('user stop before READY refunds everything charged', async () => {
    const user = await makeUser(500);
    const inst = await gpuProviderService.rentGPU(rentParams(user));
    const twoMinAgo = new Date(Date.now() - 120_000);
    await GpuInstance.updateOne(
      { _id: inst._id },
      { $set: { billedUntil: twoMinAgo, billingStartedAt: twoMinAgo, reachedReadyAt: null } }
    );

    const stopped = await gpuProviderService.terminateInstance(user._id, inst._id);
    assert.equal(stopped.stopReason, 'user_stopped');
    assert.ok(stopped.creditsCharged > 0);
    assert.ok(Math.abs(stopped.creditsRefunded - stopped.creditsCharged) < 1e-9);
    assert.ok(Math.abs((await User.findById(user._id).lean()).credits - 500) < 1e-9);
  });
});
