/**
 * GPU Reconciliation Job (every RECONCILE_INTERVAL_MS, default 10 min)
 *
 * - Orphans: Vast.ai instances labelled `cosmicgen-…` with no active GpuInstance
 *   record, older than 15 minutes. They cost us money and nobody is billed for
 *   them. Logged always; destroyed only when RECONCILE_DESTROY_ORPHANS=true.
 * - Slot counters: a user's activeGpuInstances can drift above the number of
 *   instances actually holding a slot (e.g. a crash between two writes). Such
 *   drift is corrected downwards; it would otherwise block the user from renting.
 */

import { GpuInstance } from '../models/GpuInstance.js';
import { User } from '../models/User.js';
import { vastaiService } from './vastai.service.js';
import { ACTIVE_STATUSES } from './billing.service.js';
import { INSTANCE_LABEL_PREFIX } from './gpuProvider.service.js';
import { env } from '../config/env.js';

export const ORPHAN_MIN_AGE_MS = 15 * 60 * 1000;

class ReconcileService {
  constructor() {
    this._timer = null;
    this._running = false;
  }

  start(intervalMs = env.RECONCILE_INTERVAL_MS) {
    if (this._timer) return;
    console.info(
      `[Reconcile] Starting (interval: ${intervalMs / 60000} min, destroy orphans: ${env.RECONCILE_DESTROY_ORPHANS}).`
    );
    this._timer = setInterval(() => {
      this.runOnce().catch((err) => console.error('[Reconcile] Run failed:', err.message));
    }, intervalMs);
  }

  stop() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = null;
    }
  }

  /**
   * @param {{ now?: Date, destroyOrphans?: boolean }} [options]
   * @returns {Promise<{ orphans: Array, destroyed: string[], slotFixes: number }>}
   */
  async runOnce({ now = new Date(), destroyOrphans = env.RECONCILE_DESTROY_ORPHANS } = {}) {
    if (this._running) return { orphans: [], destroyed: [], slotFixes: 0 };
    this._running = true;
    try {
      const orphans = await this.findOrphans(now);
      const destroyed = [];
      for (const orphan of orphans) {
        console.warn(
          `[Reconcile] ORPHAN Vast.ai #${orphan.contractId} (${orphan.label}, ${orphan.gpuName || 'GPU'}, ` +
            `up ${Math.round(orphan.ageMs / 60000)} min, record: ${orphan.recordStatus || 'none'}) ` +
            (destroyOrphans ? '-> destroying' : '-> not destroyed (RECONCILE_DESTROY_ORPHANS=false)')
        );
        if (!destroyOrphans) continue;
        try {
          await vastaiService.destroyInstance(orphan.contractId);
          destroyed.push(orphan.contractId);
        } catch (err) {
          console.error(`[Reconcile] Failed to destroy orphan #${orphan.contractId}: ${err.message}`);
        }
      }
      const slotFixes = await this.fixSlotCounters();
      return { orphans, destroyed, slotFixes };
    } finally {
      this._running = false;
    }
  }

  async findOrphans(now = new Date()) {
    let list;
    try {
      list = await vastaiService.listInstancesStrict();
    } catch (err) {
      console.error(`[Reconcile] Vast.ai listing failed: ${err.message}`);
      return [];
    }

    const ours = list.filter((v) => typeof v.label === 'string' && v.label.startsWith(INSTANCE_LABEL_PREFIX));
    const orphans = [];
    for (const v of ours) {
      const contractId = String(v.id);
      // Vast reports start_date in seconds since the epoch.
      const startedMs = v.start_date ? Number(v.start_date) * 1000 : null;
      const ageMs = startedMs ? now.getTime() - startedMs : Infinity;
      if (ageMs < ORPHAN_MIN_AGE_MS) continue;

      const record = await GpuInstance.findOne({ providerInstanceId: contractId }).select('status').lean();
      if (record && ACTIVE_STATUSES.includes(record.status)) continue;
      orphans.push({
        contractId,
        label: v.label,
        gpuName: v.gpu_name,
        ageMs,
        recordStatus: record?.status || null,
      });
    }
    return orphans;
  }

  /** Lower activeGpuInstances to the number of instances actually holding a slot. */
  async fixSlotCounters() {
    let fixes = 0;
    const users = await User.find({ activeGpuInstances: { $gt: 0 } }).select('_id activeGpuInstances').lean();
    for (const u of users) {
      const holding = await GpuInstance.countDocuments({ user: u._id, holdsSlot: true });
      if (u.activeGpuInstances > holding) {
        // Conditional on the value just read, so a concurrent rental is never undone.
        const res = await User.updateOne(
          { _id: u._id, activeGpuInstances: u.activeGpuInstances },
          { $set: { activeGpuInstances: holding } }
        );
        if (res.modifiedCount === 1) {
          fixes += 1;
          console.warn(`[Reconcile] User ${u._id} slot counter ${u.activeGpuInstances} -> ${holding}.`);
        }
      }
    }
    return fixes;
  }
}

export const reconcileService = new ReconcileService();
