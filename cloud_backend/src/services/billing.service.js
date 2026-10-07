/**
 * GPU Billing Service
 *
 * Charges users for rented GPU time, per second, in 60-second cycles.
 *
 * Rules:
 * - Only instances whose contract is listed on Vast.ai right now are charged.
 *   Test, sandbox and `pending-` records never are (isConfirmedContractId).
 * - New rentals are billed from contract confirmation (rentGPU sets billedUntil).
 *   An instance with no billedUntil (rented before billing existed) starts being
 *   billed when this service first sees it; earlier time is never charged.
 * - Each period is claimed with a conditional update on billedUntil before it is
 *   charged, so two backend processes can never charge the same period twice.
 * - When the balance can't cover a period, what's left is charged and the
 *   instance is destroyed. If the destroy fails, it stays billable and the stop
 *   is retried next cycle.
 * - Instances that never reach READY (failure, timeout, provider loss) are
 *   refunded everything they were charged.
 */

import { GpuInstance } from '../models/GpuInstance.js';
import { User } from '../models/User.js';
import { creditService } from './credit.service.js';
import { vastaiService, isConfirmedContractId } from './vastai.service.js';
import { instanceEvents, toWebSocketStatus } from './instanceEvents.js';
import { env } from '../config/env.js';
import { GPU_STATUS, GPU_PROVIDERS, LOG_LEVELS, TRANSACTION_TYPES } from '../config/constants.js';

export const ACTIVE_STATUSES = Object.freeze([
  GPU_STATUS.PROVISIONING,
  GPU_STATUS.DOWNLOADING_MODEL,
  GPU_STATUS.READY,
  GPU_STATUS.RUNNING,
]);

export const STOP_REASONS = Object.freeze({
  USER_STOPPED: 'user_stopped',
  INSUFFICIENT_CREDITS: 'insufficient_credits',
  PROVISIONING_TIMEOUT: 'provisioning_timeout',
  PROVISIONING_FAILED: 'provisioning_failed',
  PROVIDER_GONE: 'provider_gone',
  STALE_CLEANUP: 'stale_cleanup',
});

// Warn when less than this much runtime is left on the balance.
export const LOW_BALANCE_WINDOW_HOURS = 15 / 60;

const round6 = (n) => Math.round(n * 1e6) / 1e6;

/** Vast.ai lists stopped containers too; those are not "running" for billing. */
export function isRunningOnVast(vastInstance) {
  const state = vastInstance?.actual_status || vastInstance?.cur_state;
  return state !== 'exited' && state !== 'offline';
}

function emit(instance, dbStatus, details = {}) {
  instanceEvents.emit('status_change', {
    instanceId: String(instance._id),
    status: toWebSocketStatus(dbStatus),
    timestamp: new Date().toISOString(),
    details: { gpuType: instance.gpuType, ...details },
  });
}

export class BillingService {
  constructor() {
    this._timer = null;
    this._running = false;
  }

  start(intervalMs = env.BILLING_INTERVAL_MS) {
    if (this._timer) return;
    console.info(`[Billing] Starting GPU billing (interval: ${intervalMs / 1000}s).`);
    this._timer = setInterval(() => {
      this.runCycle().catch((err) => console.error('[Billing] Cycle error:', err.message));
    }, intervalMs);
  }

  stop() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = null;
      console.info('[Billing] Stopped GPU billing.');
    }
  }

  /**
   * One billing pass over every active, confirmed instance.
   * @param {Date} [now]
   * @returns {Promise<{ skipped?: string, charged: number, instances: number }>}
   */
  async runCycle(now = new Date()) {
    if (this._running) return { skipped: 'busy', charged: 0, instances: 0 };
    this._running = true;
    try {
      const instances = await GpuInstance.find({
        provider: GPU_PROVIDERS.VASTAI,
        status: { $in: ACTIVE_STATUSES },
      })
        .select('_id providerInstanceId')
        .lean();
      const confirmed = instances.filter((i) => isConfirmedContractId(i.providerInstanceId));
      if (confirmed.length === 0) return { charged: 0, instances: 0 };

      let vastList;
      try {
        vastList = await vastaiService.listInstancesStrict();
      } catch (err) {
        // Time keeps accruing in billedUntil and is charged on the next good cycle.
        console.error(`[Billing] Vast.ai listing failed, skipping this cycle: ${err.message}`);
        return { skipped: 'provider_unavailable', charged: 0, instances: 0 };
      }
      const running = new Set(vastList.filter(isRunningOnVast).map((v) => String(v.id)));

      let total = 0;
      let billed = 0;
      for (const { _id, providerInstanceId } of confirmed) {
        // Not listed (or exited): never charge. The poller decides whether it is gone.
        if (!running.has(providerInstanceId)) continue;
        try {
          const result = await this.chargeInstance(_id, now);
          if (!result) continue;
          billed += 1;
          total += result.charged;
          await this._afterCharge(_id, result, now);
        } catch (err) {
          console.error(`[Billing] Failed to bill instance ${_id}: ${err.message}`);
        }
      }
      return { charged: round6(total), instances: billed };
    } finally {
      this._running = false;
    }
  }

  /**
   * Charge an instance for [billedUntil, until).
   * @param {*} instanceId
   * @param {Date} until
   * @param {{ final?: boolean }} [options] final: settling a stop; status is not required to be active.
   * @returns {Promise<null|{ charged: number, amount: number, seconds: number, rate: number, shortfall: boolean, balanceAfter: number|null, started?: boolean }>}
   */
  async chargeInstance(instanceId, until, { final = false } = {}) {
    const inst = await GpuInstance.findById(instanceId)
      .select('user status gpuType pricing billedUntil providerInstanceId')
      .lean();
    if (!inst || !isConfirmedContractId(inst.providerInstanceId)) return null;
    if (!final && !ACTIVE_STATUSES.includes(inst.status)) return null;

    if (!inst.billedUntil) {
      if (final) return null;
      // Predates billing: start the clock now, never back-charge.
      await GpuInstance.updateOne(
        { _id: instanceId, billedUntil: null },
        { $set: { billedUntil: until, lastSeenOnVastAt: until } }
      );
      return { charged: 0, amount: 0, seconds: 0, rate: 0, shortfall: false, balanceAfter: null, started: true };
    }

    const from = new Date(inst.billedUntil);
    if (until <= from) return null;

    const rate = inst.pricing?.totalCreditsPerHour;
    if (!(rate > 0)) {
      console.error(`[Billing] Instance ${instanceId} has no credits/hour rate; not charging.`);
      return null;
    }

    // Claim the period first. Only one caller can move billedUntil from `from`.
    const claimFilter = { _id: instanceId, billedUntil: from };
    if (!final) claimFilter.status = { $in: ACTIVE_STATUSES };
    const claimSet = final ? { billedUntil: until } : { billedUntil: until, lastSeenOnVastAt: until };
    const claimed = await GpuInstance.findOneAndUpdate(claimFilter, { $set: claimSet }, { returnDocument: 'after' });
    if (!claimed) return null;

    const seconds = (until.getTime() - from.getTime()) / 1000;
    const amount = round6((seconds * rate) / 3600);
    if (amount <= 0) {
      return { charged: 0, amount: 0, seconds, rate, shortfall: false, balanceAfter: null };
    }

    let result;
    try {
      result = await creditService.deductCredits(
        inst.user,
        amount,
        `GPU time: ${inst.gpuType || 'GPU'}, ${Math.round(seconds)} s at ${rate} credits/hr`,
        { gpuInstanceId: String(instanceId), from, until, seconds, creditsPerHour: rate },
        null,
        { upTo: true }
      );
    } catch (err) {
      // Release the claim so the period is charged on a later attempt.
      await GpuInstance.updateOne({ _id: instanceId, billedUntil: until }, { $set: { billedUntil: from } });
      throw err;
    }

    if (result.charged > 0) {
      const after = await GpuInstance.findOneAndUpdate(
        { _id: instanceId },
        { $inc: { creditsCharged: result.charged } },
        { returnDocument: 'after' }
      );
      // A charge that landed after a failed-provisioning refund is refunded too.
      if (after?.refundIssued) await this.refundOutstanding(instanceId);
    }

    return {
      charged: result.charged,
      amount,
      seconds,
      rate,
      shortfall: result.charged < amount - 1e-9,
      balanceAfter: result.user?.credits ?? null,
    };
  }

  async _afterCharge(instanceId, result, now) {
    const inst = await GpuInstance.findById(instanceId)
      .select('user gpuType status pendingStopReason lowBalanceWarnedAt creditsCharged pricing providerInstanceId')
      .lean();
    if (!inst || !ACTIVE_STATUSES.includes(inst.status)) return;

    if (result.shortfall || inst.pendingStopReason === STOP_REASONS.INSUFFICIENT_CREDITS) {
      await this.stopForInsufficientCredits(inst, now);
      return;
    }
    if (result.started || result.balanceAfter == null) return;

    const rate = result.rate;
    const lowThreshold = rate * LOW_BALANCE_WINDOW_HOURS;
    if (result.balanceAfter < lowThreshold) {
      if (!inst.lowBalanceWarnedAt) {
        await GpuInstance.updateOne({ _id: instanceId }, { $set: { lowBalanceWarnedAt: now } });
        emit(inst, inst.status, {
          billing: {
            lowBalance: true,
            balance: result.balanceAfter,
            creditsPerHour: rate,
            minutesRemaining: Math.floor((result.balanceAfter / rate) * 60),
            creditsCharged: inst.creditsCharged,
          },
        });
      }
    } else if (inst.lowBalanceWarnedAt) {
      // Topped up: warn again next time it runs low.
      await GpuInstance.updateOne({ _id: instanceId }, { $set: { lowBalanceWarnedAt: null } });
    }
  }

  /**
   * Out of credits: destroy the Vast.ai instance, then stop and settle.
   * If the destroy fails, the instance stays billable and this is retried.
   */
  async stopForInsufficientCredits(inst, now = new Date()) {
    try {
      await vastaiService.destroyInstance(inst.providerInstanceId);
    } catch (err) {
      console.error(
        `[Billing] !!! Could not destroy Vast.ai #${inst.providerInstanceId} (instance ${inst._id}) ` +
          `after credits ran out: ${err.message}. Still billable; retrying next cycle.`
      );
      await GpuInstance.updateOne(
        { _id: inst._id },
        {
          $set: { pendingStopReason: STOP_REASONS.INSUFFICIENT_CREDITS },
          $push: {
            provisioningLogs: {
              message: `[BILLING] Credits exhausted; destroy failed (${err.message}). Retrying.`,
              level: LOG_LEVELS.ERROR,
            },
          },
        }
      );
      return null;
    }
    return this.finalizeInstance(inst._id, {
      status: GPU_STATUS.STOPPED,
      stopReason: STOP_REASONS.INSUFFICIENT_CREDITS,
      until: now,
      message: '[BILLING] Credits exhausted. Instance destroyed.',
      emitReason: 'INSUFFICIENT_CREDITS',
    });
  }

  /**
   * Move an instance to a terminal status exactly once, then settle the final
   * charge, refund failed provisioning, and release the user's slot.
   * The caller destroys the Vast.ai instance first when needed.
   *
   * @param {*} instanceId
   * @param {{ status: string, stopReason: string, until?: Date, refundIfNeverReady?: boolean,
   *           message?: string, level?: string, emitReason?: string }} opts
   * @returns {Promise<Object|null>} the updated instance, or null if it was already terminal
   */
  async finalizeInstance(instanceId, opts) {
    const {
      status,
      stopReason,
      until = new Date(),
      refundIfNeverReady = false,
      message,
      level = LOG_LEVELS.INFO,
      emitReason,
    } = opts;
    const now = new Date();

    const update = {
      $set: { status, stopReason, stoppedAt: now, pendingStopReason: null },
    };
    if (message) update.$push = { provisioningLogs: { message, level } };
    const before = await GpuInstance.findOneAndUpdate(
      { _id: instanceId, status: { $in: ACTIVE_STATUSES } },
      update,
      { returnDocument: 'before' }
    );
    if (!before) return null;

    // Final charge up to `until` (never past it, never before billedUntil).
    if (before.billedUntil && until > before.billedUntil) {
      try {
        await this.chargeInstance(instanceId, until, { final: true });
      } catch (err) {
        console.error(`[Billing] Final settlement failed for ${instanceId}: ${err.message}`);
      }
    }

    if (refundIfNeverReady && !before.reachedReadyAt) {
      await GpuInstance.updateOne({ _id: instanceId }, { $set: { refundIssued: true } });
      await this.refundOutstanding(instanceId);
    }

    await this.releaseSlot(instanceId);

    const after = await GpuInstance.findById(instanceId);
    emit(after, status, {
      reason: emitReason || stopReason?.toUpperCase(),
      billing: { creditsCharged: after.creditsCharged, creditsRefunded: after.creditsRefunded },
    });
    return after;
  }

  /**
   * Refund whatever was charged and not yet refunded. Safe to call repeatedly
   * and concurrently: each refunded amount is claimed with a conditional $inc.
   */
  async refundOutstanding(instanceId) {
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const inst = await GpuInstance.findById(instanceId).select('user gpuType creditsCharged creditsRefunded').lean();
      if (!inst) return 0;
      const delta = round6((inst.creditsCharged || 0) - (inst.creditsRefunded || 0));
      if (delta <= 0) return 0;
      const claimed = await GpuInstance.updateOne(
        { _id: instanceId, creditsRefunded: inst.creditsRefunded || 0 },
        { $inc: { creditsRefunded: delta } }
      );
      if (claimed.modifiedCount !== 1) continue;
      try {
        await creditService.addCredits(
          inst.user,
          delta,
          TRANSACTION_TYPES.REFUND,
          `Refund: ${inst.gpuType || 'GPU'} instance never became ready`,
          { gpuInstanceId: String(instanceId) }
        );
        return delta;
      } catch (err) {
        await GpuInstance.updateOne({ _id: instanceId }, { $inc: { creditsRefunded: -delta } });
        console.error(`[Billing] !!! Refund of ${delta} credits for ${instanceId} failed: ${err.message}`);
        throw err;
      }
    }
    return 0;
  }

  /**
   * Reserve one of the user's active-instance slots. Race-safe: the counter is
   * only incremented while below the limit, in one conditional update.
   * @returns {Promise<boolean>}
   */
  async acquireSlot(userId, max = env.GPU_MAX_ACTIVE_PER_USER) {
    const updated = await User.findOneAndUpdate(
      {
        _id: userId,
        $or: [{ activeGpuInstances: { $lt: max } }, { activeGpuInstances: { $exists: false } }],
      },
      { $inc: { activeGpuInstances: 1 } },
      { returnDocument: 'after' }
    );
    return Boolean(updated);
  }

  /** Give back a slot reserved before an instance record existed. */
  async releaseUnclaimedSlot(userId) {
    await User.updateOne({ _id: userId, activeGpuInstances: { $gt: 0 } }, { $inc: { activeGpuInstances: -1 } });
  }

  /** Release the slot held by an instance, at most once. */
  async releaseSlot(instanceId) {
    const inst = await GpuInstance.findOneAndUpdate(
      { _id: instanceId, holdsSlot: true },
      { $set: { holdsSlot: false } },
      { returnDocument: 'before' }
    );
    if (inst) await this.releaseUnclaimedSlot(inst.user);
  }
}

export const billingService = new BillingService();
