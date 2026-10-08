import { test, describe, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { startTestDb } from './helpers/db.js';
import { installFakeVast } from './helpers/fakeVast.js';
import { makeUser, makeInstance } from './helpers/factories.js';
import { BillingService, billingService, STOP_REASONS } from '../src/services/billing.service.js';
import { instanceEvents } from '../src/services/instanceEvents.js';
import { GpuInstance } from '../src/models/GpuInstance.js';
import { User } from '../src/models/User.js';
import { Transaction } from '../src/models/Transaction.js';
import { GPU_STATUS } from '../src/config/constants.js';

const T0 = new Date('2026-10-07T18:00:00Z');
const at = (seconds) => new Date(T0.getTime() + seconds * 1000);
const close = (a, b, eps = 1e-6) => assert.ok(Math.abs(a - b) < eps, `${a} != ${b}`);
const balance = async (user) => (await User.findById(user._id).lean()).credits;
const reload = (inst) => GpuInstance.findById(inst._id).lean();

describe('billing', () => {
  let db;
  let vast;
  let events;
  const onEvent = (e) => events.push(e);

  before(async () => { db = await startTestDb(); });
  after(async () => { await db.stop(); });
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

  test('charges seconds x rate for each cycle (36 credits/hr = 0.01/s)', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, { billedUntil: T0 });
    vast.addInstance(inst.providerInstanceId);

    const r1 = await billingService.runCycle(at(60));
    close(r1.charged, 0.6);
    const r2 = await billingService.runCycle(at(90));
    close(r2.charged, 0.3);

    close(await balance(user), 99.1);
    const fresh = await reload(inst);
    close(fresh.creditsCharged, 0.9);
    assert.equal(fresh.billedUntil.getTime(), at(90).getTime());

    // One ledger entry for the whole rental, updated each cycle.
    const entries = await Transaction.find({ user: user._id }).lean();
    assert.equal(entries.length, 1);
    assert.equal(entries[0].type, 'deduction');
    assert.equal(String(entries[0].gpuInstance), String(inst._id));
    close(entries[0].amount, -0.9);
    close(entries[0].balanceAfter, 99.1);
    assert.equal(entries[0].metadata.billedSeconds, 90);
    assert.equal(entries[0].metadata.gpuType, 'RTX 4060 Ti');
    assert.match(entries[0].description, /^GPU rental: RTX 4060 Ti, 2 min at 36 credits\/hr$/);
  });

  test('worked example: 28.9 credits/hr for 37 minutes, stopped 20 s later', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, { billedUntil: T0, pricing: { totalCreditsPerHour: 28.9 } });
    vast.addInstance(inst.providerInstanceId);

    // Each cycle charges (total owed so far) - (already charged):
    //   minute 1: round6(60 * 28.9 / 3600) = 0.481667
    //   minute 2: round6(120 * 28.9 / 3600) - 0.481667 = 0.963333 - 0.481667 = 0.481666
    // so the total after 37 cycles is round6(37 * 60 * 28.9 / 3600) = 17.821667, with no drift.
    for (let m = 1; m <= 37; m += 1) await billingService.runCycle(at(m * 60));
    let fresh = await reload(inst);
    close(fresh.creditsCharged, 17.821667);

    // Stopped 20 s into the next cycle: total = round6(2240 * 28.9 / 3600) = 17.982222.
    await billingService.finalizeInstance(inst._id, {
      status: GPU_STATUS.STOPPED,
      stopReason: STOP_REASONS.USER_STOPPED,
      until: at(37 * 60 + 20),
      refundIfNeverReady: true,
    });
    fresh = await reload(inst);
    close(fresh.creditsCharged, 17.982222);
    close(fresh.creditsRefunded, 0); // reached READY: no refund
    close(await balance(user), 100 - 17.982222);

    const [entry] = await Transaction.find({ user: user._id }).lean();
    close(entry.amount, -17.982222);
    assert.equal(entry.metadata.billedSeconds, 2240);
    assert.match(entry.description, /37 min at 28\.9 credits\/hr/);
  });

  test('charges are computed from total time, so rounding never drifts', async () => {
    const user = await makeUser(1000);
    const rate = 28.9;
    const inst = await makeInstance(user, { billedUntil: T0, pricing: { totalCreditsPerHour: rate } });
    vast.addInstance(inst.providerInstanceId);
    // 500 uneven cycles of 7 s: per-cycle rounding would drift; total-based charging cannot.
    for (let i = 1; i <= 500; i += 1) await billingService.runCycle(at(i * 7));
    const exact = Math.round(((3500 * rate) / 3600) * 1e6) / 1e6;
    close((await reload(inst)).creditsCharged, exact, 1e-9);
    close(await balance(user), 1000 - exact, 1e-9);
  });

  test('two billing workers never charge the same period twice', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, { billedUntil: T0 });
    vast.addInstance(inst.providerInstanceId);

    const workers = [new BillingService(), new BillingService(), new BillingService()];
    await Promise.all(workers.map((w) => w.runCycle(at(60))));
    await Promise.all(workers.map((w) => w.runCycle(at(120))));

    close((await reload(inst)).creditsCharged, 1.2);
    close(await balance(user), 98.8);
    assert.equal(await Transaction.countDocuments({ user: user._id }), 1);
    close((await Transaction.findOne({ user: user._id }).lean()).amount, -1.2);
  });

  test('an instance with no billedUntil starts billing when first seen, never back-charged', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, { billedUntil: null, startedAt: new Date('2026-10-06T00:00:00Z') });
    vast.addInstance(inst.providerInstanceId);

    const first = await billingService.runCycle(at(0));
    assert.equal(first.charged, 0);
    assert.equal((await reload(inst)).billedUntil.getTime(), at(0).getTime());
    close(await balance(user), 100);

    await billingService.runCycle(at(60));
    close(await balance(user), 99.4);
  });

  test('only contracts running on Vast.ai are charged; test, pending and missing ones never', async () => {
    const user = await makeUser(100);
    const live = await makeInstance(user, { providerInstanceId: '111', billedUntil: T0 });
    await makeInstance(user, { providerInstanceId: 'test-contract-1791101619182', billedUntil: T0 });
    await makeInstance(user, { providerInstanceId: 'pending-1791099211934', billedUntil: T0 });
    const gone = await makeInstance(user, { providerInstanceId: '54547010', billedUntil: T0 });
    const exited = await makeInstance(user, { providerInstanceId: '333', billedUntil: T0 });
    vast.addInstance('111');
    vast.addInstance('333', { actual_status: 'exited' });

    const r = await billingService.runCycle(at(60));
    close(r.charged, 0.6);
    assert.equal(r.instances, 1);
    close((await reload(live)).creditsCharged, 0.6);
    assert.equal((await reload(gone)).creditsCharged, 0);
    assert.equal((await reload(exited)).creditsCharged, 0);
    close(await balance(user), 99.4);
  });

  test('a failed Vast.ai listing skips the cycle; the time is charged on the next good one', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, { billedUntil: T0 });
    vast.addInstance(inst.providerInstanceId);

    vast.failList = true;
    const skipped = await billingService.runCycle(at(60));
    assert.equal(skipped.skipped, 'provider_unavailable');
    close(await balance(user), 100);

    vast.failList = false;
    await billingService.runCycle(at(120));
    close(await balance(user), 98.8);
  });

  test('at zero balance: charges what is left, destroys once, stops with insufficient_credits', async () => {
    const user = await makeUser(0.25);
    const inst = await makeInstance(user, { billedUntil: T0, holdsSlot: true });
    await User.updateOne({ _id: user._id }, { $set: { activeGpuInstances: 1 } });
    vast.addInstance(inst.providerInstanceId);

    await billingService.runCycle(at(60)); // due 0.6, only 0.25 left
    const fresh = await reload(inst);
    assert.equal(fresh.status, GPU_STATUS.STOPPED);
    assert.equal(fresh.stopReason, STOP_REASONS.INSUFFICIENT_CREDITS);
    close(fresh.creditsCharged, 0.25);
    assert.equal(await balance(user), 0);
    assert.deepEqual(vast.calls.destroy, [inst.providerInstanceId]);
    assert.equal(fresh.holdsSlot, false);
    assert.equal((await User.findById(user._id).lean()).activeGpuInstances, 0);
    assert.ok(events.some((e) => e.status === 'STOPPED' && e.details.reason === 'INSUFFICIENT_CREDITS'));

    // Later cycles leave it alone.
    await billingService.runCycle(at(120));
    assert.equal(vast.calls.destroy.length, 1);
  });

  test('if the destroy fails it stays billable and the stop is retried next cycle', async () => {
    const user = await makeUser(0.25);
    const inst = await makeInstance(user, { billedUntil: T0 });
    vast.addInstance(inst.providerInstanceId);
    vast.failDestroy = 1;

    await billingService.runCycle(at(60));
    let fresh = await reload(inst);
    assert.equal(fresh.status, GPU_STATUS.READY);
    assert.equal(fresh.pendingStopReason, STOP_REASONS.INSUFFICIENT_CREDITS);

    await billingService.runCycle(at(120));
    fresh = await reload(inst);
    assert.equal(fresh.status, GPU_STATUS.STOPPED);
    assert.equal(vast.calls.destroy.length, 2);
    close(fresh.creditsCharged, 0.25);
  });

  test('emits one low-balance warning when under 15 minutes of runtime remain', async () => {
    // 36 credits/hr: 15 min = 9 credits. Start at 9.5.
    const user = await makeUser(9.5);
    const inst = await makeInstance(user, { billedUntil: T0 });
    vast.addInstance(inst.providerInstanceId);

    await billingService.runCycle(at(60)); // 8.9 left
    await billingService.runCycle(at(120)); // 8.3 left
    const warnings = events.filter((e) => e.details?.billing?.lowBalance);
    assert.equal(warnings.length, 1);
    assert.equal(warnings[0].details.billing.minutesRemaining, 14);
  });

  test('failed provisioning refunds everything that was charged', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, {
      status: GPU_STATUS.PROVISIONING,
      billedUntil: T0,
      reachedReadyAt: null,
    });
    vast.addInstance(inst.providerInstanceId);
    await billingService.runCycle(at(60));
    await billingService.runCycle(at(120));
    close(await balance(user), 98.8);

    await billingService.finalizeInstance(inst._id, {
      status: GPU_STATUS.FAILED,
      stopReason: STOP_REASONS.PROVISIONING_TIMEOUT,
      until: at(150),
      refundIfNeverReady: true,
    });
    const fresh = await reload(inst);
    close(fresh.creditsCharged, 1.5);
    close(fresh.creditsRefunded, 1.5);
    close(await balance(user), 100);
    // One charge entry and one refund entry for the rental.
    const refund = await Transaction.findOne({ user: user._id, type: 'refund' }).lean();
    close(refund.amount, 1.5);
    assert.equal(String(refund.gpuInstance), String(inst._id));
    close((await Transaction.findOne({ user: user._id, type: 'deduction' }).lean()).amount, -1.5);
    assert.equal(await Transaction.countDocuments({ user: user._id }), 2);

    // Finalizing again changes nothing.
    assert.equal(await billingService.finalizeInstance(inst._id, { status: GPU_STATUS.FAILED, stopReason: 'x' }), null);
    close(await balance(user), 100);
  });

  test('instances that reached READY are not refunded when stopped', async () => {
    const user = await makeUser(100);
    const inst = await makeInstance(user, { billedUntil: T0, reachedReadyAt: T0 });
    vast.addInstance(inst.providerInstanceId);
    await billingService.runCycle(at(60));
    await billingService.finalizeInstance(inst._id, {
      status: GPU_STATUS.STOPPED,
      stopReason: STOP_REASONS.PROVIDER_GONE,
      until: at(90),
      refundIfNeverReady: true,
    });
    close(await balance(user), 99.1);
    assert.equal((await reload(inst)).creditsRefunded, 0);
  });

  test('running out of credits before READY is refunded in full', async () => {
    const user = await makeUser(0.25);
    const inst = await makeInstance(user, {
      status: GPU_STATUS.PROVISIONING,
      billedUntil: T0,
      reachedReadyAt: null,
    });
    vast.addInstance(inst.providerInstanceId);
    await billingService.runCycle(at(60));
    const fresh = await reload(inst);
    assert.equal(fresh.stopReason, STOP_REASONS.INSUFFICIENT_CREDITS);
    close(fresh.creditsRefunded, 0.25);
    close(await balance(user), 0.25);
  });

  test('ledger check: consistent rentals pass, a crash between writes is reported', async () => {
    const user = await makeUser(100);
    const a = await makeInstance(user, { providerInstanceId: '1001', billedUntil: T0 });
    const b = await makeInstance(user, { providerInstanceId: '1002', billedUntil: T0, reachedReadyAt: null });
    vast.addInstance('1001');
    vast.addInstance('1002');
    await billingService.runCycle(at(60));
    await billingService.finalizeInstance(b._id, {
      status: GPU_STATUS.FAILED,
      stopReason: STOP_REASONS.PROVISIONING_TIMEOUT,
      until: at(90),
      refundIfNeverReady: true,
    });
    assert.deepEqual(await billingService.checkLedger({ since: T0, settleMs: 0 }), []);

    // Simulate a crash after the instance record was updated but before the ledger write.
    await GpuInstance.updateOne({ _id: a._id }, { $inc: { creditsCharged: 0.6 } });
    const errors = [];
    const origError = console.error;
    console.error = (msg) => errors.push(String(msg));
    let mismatches;
    try {
      mismatches = await billingService.checkLedger({ since: T0, settleMs: 0 });
    } finally {
      console.error = origError;
    }
    assert.equal(mismatches.length, 1);
    assert.equal(mismatches[0].instanceId, String(a._id));
    assert.equal(mismatches[0].type, 'charge');
    close(mismatches[0].instance, 1.2);
    close(mismatches[0].ledger, 0.6);
    assert.ok(errors.some((e) => e.includes('LEDGER MISMATCH')));
  });

  test('concurrent first charges for one rental still create a single ledger entry', async () => {
    await Transaction.init(); // unique index on (gpuInstance, type)
    const user = await makeUser(100);
    const inst = await makeInstance(user, { billedUntil: T0 });
    const { creditService } = await import('../src/services/credit.service.js');
    await Promise.all(
      Array.from({ length: 5 }, () =>
        creditService.addToRentalEntry({
          userId: user._id,
          gpuInstanceId: inst._id,
          type: 'deduction',
          amount: -0.1,
          balanceAfter: 99,
          description: 'GPU rental',
          metadata: {},
        })
      )
    );
    const entries = await Transaction.find({ gpuInstance: inst._id }).lean();
    assert.equal(entries.length, 1);
    close(entries[0].amount, -0.5);
  });
});

describe('billing: records without billingStartedAt', () => {
  let db;
  let vast;
  before(async () => { db = await startTestDb(); });
  after(async () => { await db.stop(); });
  beforeEach(async () => { await db.clear(); vast = installFakeVast(); });
  afterEach(() => vast.restore());

  test('derives the start from what was already charged and keeps charging exactly', async () => {
    const user = await makeUser(100);
    // Billed 10 minutes at 36 credits/hr (6 credits) before billingStartedAt existed.
    const inst = await makeInstance(user, { billedUntil: at(600), creditsCharged: 6 });
    assert.equal((await reload(inst)).billingStartedAt, null);
    vast.addInstance(inst.providerInstanceId);
    await billingService.runCycle(at(660));
    const fresh = await reload(inst);
    assert.equal(fresh.billingStartedAt.getTime(), T0.getTime());
    close(fresh.creditsCharged, 6.6);
    close(await balance(user), 99.4);
  });
});
