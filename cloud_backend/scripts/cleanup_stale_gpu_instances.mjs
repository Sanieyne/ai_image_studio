/**
 * Close GpuInstance records that still look active but have nothing behind them.
 *
 * DRY-RUN BY DEFAULT: prints what it would change and writes nothing.
 *
 *   node scripts/cleanup_stale_gpu_instances.mjs           # report only
 *   node scripts/cleanup_stale_gpu_instances.mjs --apply   # mark stale records stopped
 *
 * A record in provisioning / downloading_model / ready / running is stale when:
 *   - its providerInstanceId is not a real Vast.ai contract id (test-, pending-, mock-, ...), or
 *   - its contract is not running on Vast.ai any more (missing or exited).
 *
 * Stale records are set to `stopped` with stopReason `stale_cleanup`. No credits are
 * charged or refunded, and nothing is destroyed on Vast.ai. A record that holds a rental
 * slot (created after billing was deployed) gives its slot back. If the Vast.ai listing fails,
 * the script stops without changing anything.
 */

import mongoose from 'mongoose';
import { env } from '../src/config/env.js';
import { describeMongoUri } from '../src/config/database.js';
import { GpuInstance } from '../src/models/GpuInstance.js';
import { vastaiService, isConfirmedContractId } from '../src/services/vastai.service.js';
import { ACTIVE_STATUSES, STOP_REASONS, isRunningOnVast, billingService } from '../src/services/billing.service.js';
import { LOG_LEVELS } from '../src/config/constants.js';

/**
 * Pure classification, exported for tests.
 * @param {Array} records - active GpuInstance records (lean)
 * @param {Array} vastList - Vast.ai instance list
 */
export function classifyRecords(records, vastList) {
  const running = new Set(vastList.filter(isRunningOnVast).map((v) => String(v.id)));
  const listed = new Set(vastList.map((v) => String(v.id)));
  return records.map((r) => {
    const id = r.providerInstanceId;
    let reason = null;
    if (!isConfirmedContractId(id)) reason = 'not a real Vast.ai contract (test/sandbox/pending)';
    else if (!listed.has(id)) reason = 'contract no longer exists on Vast.ai';
    else if (!running.has(id)) reason = 'contract exited on Vast.ai';
    return { record: r, stale: Boolean(reason), reason };
  });
}

async function main() {
  const apply = process.argv.includes('--apply');
  console.log(`Mode: ${apply ? 'APPLY' : 'DRY-RUN (no changes; pass --apply to write)'}`);
  console.log(`Database: ${describeMongoUri(env.MONGODB_URI)}`);

  if (!env.VASTAI_API_KEY) {
    throw new Error('VASTAI_API_KEY is not set; cannot tell which contracts exist. Nothing changed.');
  }
  const vastList = await vastaiService.listInstancesStrict();
  console.log(`Vast.ai instances on the account: ${vastList.length}`);

  await mongoose.connect(env.MONGODB_URI, { serverSelectionTimeoutMS: 5000 });
  try {
    const records = await GpuInstance.find({ status: { $in: ACTIVE_STATUSES } })
      .select('_id user status providerInstanceId gpuType createdAt')
      .lean();
    const rows = classifyRecords(records, vastList);

    console.log(`\nActive records: ${records.length}`);
    for (const { record: r, stale, reason } of rows) {
      console.log(
        `${stale ? 'STALE' : 'keep '}  ${r._id}  ${r.status.padEnd(17)} contract=${r.providerInstanceId}  ` +
          `${r.gpuType || ''}  created=${r.createdAt?.toISOString?.() || r.createdAt}${stale ? `  (${reason})` : ''}`
      );
    }
    const stale = rows.filter((x) => x.stale);
    console.log(`\nStale: ${stale.length}`);

    if (!apply || stale.length === 0) return;

    let changed = 0;
    for (const { record: r, reason } of stale) {
      const res = await GpuInstance.updateOne(
        { _id: r._id, status: { $in: ACTIVE_STATUSES } },
        {
          $set: { status: 'stopped', stopReason: STOP_REASONS.STALE_CLEANUP, stoppedAt: new Date() },
          $push: { provisioningLogs: { message: `[CLEANUP] Closed stale record: ${reason}.`, level: LOG_LEVELS.WARN } },
        }
      );
      changed += res.modifiedCount;
      // Records created after billing hold a rental slot; give it back.
      if (res.modifiedCount === 1) await billingService.releaseSlot(r._id);
    }
    console.log(`Marked stopped: ${changed}`);
  } finally {
    await mongoose.disconnect();
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  });
}
