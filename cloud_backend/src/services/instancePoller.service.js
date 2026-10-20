/**
 * GPU Instance Health-Check & Provisioning Poller Service
 * Monitors active GPU instances.
 * - Discovers public IP + mapped port from the Vast.ai instance list
 * - Polls GET http://{ip}:{port}/health every cycle while provisioning, about once a minute when ready
 * - Handles transitions: PROVISIONING -> DOWNLOADING_MODEL -> READY
 * - Provisioning timeout -> destroy, FAILED, refund
 * - Instance gone from Vast.ai (two checks) -> STOPPED, final charge settled
 * - Emits event-driven notifications to WebSocket subscribers
 */

import axios from 'axios';
import { GpuInstance } from '../models/GpuInstance.js';
import { instanceEvents, toWebSocketStatus } from './instanceEvents.js';
import { vastaiService, isConfirmedContractId } from './vastai.service.js';
import { billingService, ACTIVE_STATUSES, STOP_REASONS, isRunningOnVast } from './billing.service.js';
import { GPU_STATUS, GPU_PROVIDERS, LOG_LEVELS } from '../config/constants.js';

const READY_STATUSES = [GPU_STATUS.READY, GPU_STATUS.RUNNING];

// Human-friendly model labels for customer-facing progress updates
const MODEL_FRIENDLY_NAMES = {
  'minimax-h3': 'MiniMax-H3 Video+Audio',
  'minimaxai/minimax-h3': 'MiniMax-H3 Video+Audio',
  'flux-1-schnell': 'FLUX.1 Schnell',
  'black-forest-labs/flux.1-schnell': 'FLUX.1 Schnell',
  'flux-1-dev': 'FLUX.1 Dev',
  'black-forest-labs/flux.1-dev': 'FLUX.1 Dev',
  'sdxl-base-1.0': 'SDXL Base 1.0',
  'stabilityai/stable-diffusion-xl-base-1.0': 'SDXL Base 1.0',
  'qwen-image-2.1': 'Qwen-Image 2.1',
  'qwen/qwen-image-2.1': 'Qwen-Image 2.1',
  'wan-2.1-t2v-1.3b': 'Wan 2.1 T2V 1.3B',
  'wan-ai/wan2.1-t2v-1.3b-diffusers': 'Wan 2.1 T2V 1.3B',
  'wan-2.1-i2v-14b': 'Wan 2.1 I2V 14B',
  'wan-ai/wan2.1-i2v-14b-480p-diffusers': 'Wan 2.1 I2V 14B',
  'wan-2.2-animate-14b': 'Wan 2.2 Animate 14B',
  'wan-ai/wan2.2-animate-14b': 'Wan 2.2 Animate 14B',
  'realesrgan-x4plus': 'Real-ESRGAN 4x+',
  'amd/realesrgan-x4plus': 'Real-ESRGAN 4x+',
  'fashn-vton-1.5': 'FASHN VTON 1.5',
  'fashn-ai/fashn-vton-1.5': 'FASHN VTON 1.5',
  'breeze-tts-2': 'Breeze TTS 2',
  'breezeblue/breeze-tts-2': 'Breeze TTS 2',
  'chatterbox-tts': 'Chatterbox TTS',
  'resembleai/chatterbox': 'Chatterbox TTS',
  'z-image-turbo': 'Z-Image Turbo',
};

function formatFriendlyModelName(modelId = '') {
  if (!modelId) return 'AI Model';
  if (MODEL_FRIENDLY_NAMES[modelId]) return MODEL_FRIENDLY_NAMES[modelId];
  const cleaned = modelId.split('/').pop() || modelId;
  return cleaned
    .replace(/[-_]/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

/** Sanitize raw Docker / apt / driver strings into friendly customer progress messages. */
function sanitizeVastProgressMessage(vastStatus, rawMsg = '') {
  const msg = (rawMsg || '').trim();
  const lower = msg.toLowerCase();

  const percentMatch = msg.match(/(\d{1,3})%/);
  const percent = percentMatch ? `${percentMatch[1]}%` : null;

  if (lower.includes('downloading') || lower.includes('pulling') || lower.includes('fetching') || lower.includes('extracting')) {
    return percent
      ? `Downloading AI container runtime (${percent})...`
      : 'Downloading AI container runtime image...';
  }

  if (lower.includes('libpam') || lower.includes('systemd') || lower.includes('setting up') || lower.includes('apt') || lower.includes('install')) {
    return 'Configuring system packages and CUDA runtime...';
  }

  if (lower.includes('dockerfile') || lower.includes('build definition') || lower.includes('transferring') || lower.includes('layer')) {
    return 'Preparing accelerated GPU container environment...';
  }

  if (lower.includes('ssl') || lower.includes('cert') || lower.includes('ssh')) {
    return 'Establishing secure connection channels...';
  }

  if (lower.includes('starting') || lower.includes('created') || lower.includes('allocat')) {
    return 'Allocating dedicated GPU server hardware...';
  }

  if (vastStatus === 'loading') {
    return percent
      ? `Loading GPU container environment (${percent})...`
      : 'Loading GPU container environment...';
  }

  if (vastStatus === 'running') {
    return 'GPU container online. Mapping high-speed communication ports...';
  }

  return 'Initializing GPU host instance...';
}

// Re-exported for existing importers (websocket/instanceStatus.ws.js).
export { instanceEvents, toWebSocketStatus };

export class InstancePollerService {
  constructor(options = {}) {
    this.intervalMs = options.intervalMs || 4000; // 4 seconds for responsive real-time streaming
    this.timeoutMs = options.timeoutMs || 10 * 60 * 1000; // 10 minutes
    this.healthTimeoutMs = options.healthTimeoutMs || 4000;
    // READY/RUNNING instances and Vast.ai presence are checked about once a minute.
    this.providerCheckIntervalMs = options.providerCheckIntervalMs ?? 60 * 1000;
    // An instance is "gone" after this many misses spanning at least minMissSpanMs.
    this.missesBeforeGone = options.missesBeforeGone ?? 2;
    this.minMissSpanMs = options.minMissSpanMs ?? 60 * 1000;
    // Newly confirmed contracts may take a moment to appear in Vast.ai's listing.
    this.newContractGraceMs = options.newContractGraceMs ?? 2 * 60 * 1000;
    this._lastProviderCheckAt = 0;
    // While instances are provisioning, Vast.ai is listed at most this often for progress.
    this.provisioningListIntervalMs = options.provisioningListIntervalMs ?? 10 * 1000;
    this._lastListAt = 0;
    this._progressSig = new Map();
    this._timer = null;
    this._isPolling = false;
    this._lastModelsSignature = new Map();
    this._lastKnownDetails = new Map();
  }

  /**
   * Start background polling daemon
   */
  start() {
    if (this._timer) return;
    console.info(`[InstancePoller] Starting background health poller (interval: ${this.intervalMs}ms, timeout: ${this.timeoutMs / 60000}m)...`);
    this._timer = setInterval(() => {
      this.pollCycle().catch((err) => {
        console.error('[InstancePoller] Poll cycle error:', err.message);
      });
    }, this.intervalMs);
  }

  /**
   * Stop background polling daemon
   */
  stop() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = null;
      console.info('[InstancePoller] Stopped background health poller.');
    }
  }

  /**
   * Execute a single poll cycle.
   * - PROVISIONING / DOWNLOADING_MODEL: every cycle (endpoint discovery, health, timeout).
   * - READY / RUNNING: about once a minute (presence on Vast.ai, health telemetry).
   * Vast.ai is listed once per cycle at most, and only when something needs it.
   */
  async pollCycle(now = new Date()) {
    if (this._isPolling) return;
    this._isPolling = true;

    try {
      const activeInstances = await GpuInstance.find({ status: { $in: ACTIVE_STATUSES } });
      if (activeInstances.length === 0) return;

      const dueForProviderCheck = now.getTime() - this._lastProviderCheckAt >= this.providerCheckIntervalMs;
      const due = activeInstances.filter(
        (i) => !READY_STATUSES.includes(i.status) || dueForProviderCheck
      );
      if (due.length === 0) return;

      const provisioningNeedsList =
        now.getTime() - this._lastListAt >= this.provisioningListIntervalMs &&
        due.some((i) => isConfirmedContractId(i.providerInstanceId) && !READY_STATUSES.includes(i.status));
      const needsList = dueForProviderCheck || provisioningNeedsList;
      let vastById = null;
      if (needsList && due.some((i) => isConfirmedContractId(i.providerInstanceId))) {
        try {
          const list = await vastaiService.listInstancesStrict();
          vastById = new Map(list.map((v) => [String(v.id), v]));
          this._lastListAt = now.getTime();
          if (dueForProviderCheck) this._lastProviderCheckAt = now.getTime();
        } catch (err) {
          // Unknown is not "gone": skip presence checks until the listing works again.
          console.error(`[InstancePoller] Vast.ai listing failed: ${err.message}`);
        }
      }

      for (const instance of due) {
        try {
          await this.pollInstance(instance, { vastById, checkPresence: Boolean(vastById) && dueForProviderCheck, now });
        } catch (instErr) {
          console.error(`[InstancePoller] Error checking instance ${instance._id}:`, instErr.message);
        }
      }
    } finally {
      this._isPolling = false;
    }
  }

  _timeoutMsFor(instance) {
    // Scale timeout dynamically: 25 min base, 40 min for large models (e.g. Qwen-Image 33GB, Flux, Minimax)
    const hasLargeModels = (instance.modelsRequested || []).some((m) =>
      ['qwen-image-2.1', 'flux-1-schnell', 'flux-1-dev', 'minimax-h3', 'sd3-medium'].includes(m)
    );
    return hasLargeModels ? 40 * 60 * 1000 : 25 * 60 * 1000;
  }

  /**
   * Poll and update status for a single instance.
   * Every status change is a conditional update, so a stop made meanwhile by
   * billing or by the user is never overwritten.
   * @param {Object} instance - Mongoose GpuInstance document
   * @param {{ vastById?: Map|null, checkPresence?: boolean, now?: Date }} [ctx]
   * @returns {Promise<Object>}
   */
  async pollInstance(instance, { vastById = null, checkPresence = false, now = new Date() } = {}) {
    const id = instance._id;
    const confirmed = isConfirmedContractId(instance.providerInstanceId);
    const vastEntry = confirmed && vastById ? vastById.get(instance.providerInstanceId) : undefined;

    // 1. Provisioning timeout (never-ready instances only): destroy, fail, refund.
    if (!READY_STATUSES.includes(instance.status)) {
      const startedAt = instance.startedAt || instance.createdAt || now;
      const elapsedMs = now.getTime() - new Date(startedAt).getTime();
      const timeoutMs = this._timeoutMsFor(instance);
      if (elapsedMs > timeoutMs) {
        console.warn(`[InstancePoller] Instance ${id} (${instance.providerInstanceId}) timed out after ${Math.round(elapsedMs / 1000)}s.`);
        if (confirmed && instance.provider === GPU_PROVIDERS.VASTAI) {
          try {
            await vastaiService.destroyInstance(instance.providerInstanceId);
          } catch (termErr) {
            // Keep it active so the destroy is retried next cycle; charges so far are refunded on failure.
            console.error(`[InstancePoller] Auto-termination failed for contract #${instance.providerInstanceId}: ${termErr.message}`);
            await GpuInstance.updateOne(
              { _id: id },
              {
                $set: { pendingStopReason: STOP_REASONS.PROVISIONING_TIMEOUT },
                $push: { provisioningLogs: { message: `[AUTO-TERMINATE] Destroy failed (${termErr.message}); retrying.`, level: LOG_LEVELS.WARN } },
              }
            );
            return instance;
          }
        }
        await billingService.finalizeInstance(id, {
          status: GPU_STATUS.FAILED,
          stopReason: STOP_REASONS.PROVISIONING_TIMEOUT,
          until: now,
          refundIfNeverReady: true,
          message:
            `The GPU did not become ready within ${Math.round(timeoutMs / 60000)} minutes` +
            (instance.progress?.message ? ` (last step: ${instance.progress.message})` : '') +
            '. The instance was stopped and everything charged was refunded.',
          level: LOG_LEVELS.ERROR,
          emitReason: 'PROVISIONING_TIMEOUT',
        });
        return instance;
      }
    }

    // 2. Presence on Vast.ai: two misses at least a minute apart mean it is gone.
    if (checkPresence && confirmed) {
      const present = vastEntry && isRunningOnVast(vastEntry);
      if (present) {
        if (instance.vastMissCount > 0 || !instance.lastSeenOnVastAt || now - instance.lastSeenOnVastAt > 30_000) {
          await GpuInstance.updateOne({ _id: id }, { $set: { lastSeenOnVastAt: now, vastMissCount: 0, firstMissAt: null } });
        }
      } else {
        const confirmedAt = instance.contractConfirmedAt || instance.startedAt || instance.createdAt;
        const graceOver = now - new Date(confirmedAt) > this.newContractGraceMs;
        if (graceOver) {
          await GpuInstance.updateOne({ _id: id, firstMissAt: null }, { $set: { firstMissAt: now } });
          const after = await GpuInstance.findOneAndUpdate(
            { _id: id },
            { $inc: { vastMissCount: 1 } },
            { returnDocument: 'after' }
          );
          if (after.vastMissCount >= this.missesBeforeGone && now - after.firstMissAt >= this.minMissSpanMs) {
            if (vastEntry) {
              // Listed but exited: destroy so its storage stops billing us.
              try { await vastaiService.destroyInstance(instance.providerInstanceId); } catch (err) {
                console.error(`[InstancePoller] Could not destroy exited contract #${instance.providerInstanceId}: ${err.message}`);
              }
            }
            await billingService.finalizeInstance(id, {
              status: GPU_STATUS.STOPPED,
              stopReason: STOP_REASONS.PROVIDER_GONE,
              until: after.lastSeenOnVastAt || after.billedUntil || now,
              refundIfNeverReady: true,
              message: vastEntry
                ? `Vast.ai instance #${instance.providerInstanceId} exited; stopped.`
                : `Vast.ai instance #${instance.providerInstanceId} no longer exists; stopped.`,
              level: LOG_LEVELS.WARN,
              emitReason: 'PROVIDER_GONE',
            });
            return instance;
          }
        }
      }
    }

    // 3. Discover public IP and mapped port if not yet established.
    if (!instance.pythonEngineUrl && vastEntry) {
      const endpoint = vastaiService.parseEndpoint(vastEntry);
      if (endpoint.publicIp && endpoint.mappedPort) {
        const pythonEngineUrl = `http://${endpoint.publicIp}:${endpoint.mappedPort}`;
        const updated = await GpuInstance.findOneAndUpdate(
          { _id: id, status: { $in: ACTIVE_STATUSES }, pythonEngineUrl: { $in: [null, ''] } },
          {
            $set: {
              publicIp: endpoint.publicIp,
              pythonEngineUrl,
              ...(endpoint.sshHost ? { sshHost: endpoint.sshHost } : {}),
              ...(endpoint.sshPort ? { sshPort: endpoint.sshPort } : {}),
            },
            $push: { provisioningLogs: { message: `Discovered remote endpoint ${pythonEngineUrl}`, level: LOG_LEVELS.INFO } },
          },
          { returnDocument: 'after' }
        );
        if (updated) {
          instance.publicIp = updated.publicIp;
          instance.pythonEngineUrl = updated.pythonEngineUrl;
          console.info(`[InstancePoller] Assigned endpoint for instance ${id}: ${pythonEngineUrl}`);
        }
      }
    }

    const vastFields = vastEntry
      ? {
          vastStatus: vastEntry.actual_status || vastEntry.cur_state || null,
          vastStatusMessage: (vastEntry.status_msg || '').trim().slice(0, 300) || null,
        }
      : {};

    // 4. Not reachable yet: report what the host is doing.
    if (!instance.pythonEngineUrl) {
      if (!READY_STATUSES.includes(instance.status)) {
        await this._recordProgress(instance, this._hostProgress(instance, confirmed, vastFields), now);
      }
      return instance;
    }

    // 5. Health check
    if (instance.pythonEngineUrl) {
      let data;
      try {
        const res = await axios.get(`${instance.pythonEngineUrl}/health`, {
          timeout: this.healthTimeoutMs,
          validateStatus: (code) => code === 200,
        });
        data = res.data;
      } catch (healthErr) {
        // Port mapped, engine not answering yet: downloading from R2 and starting.
        if (!READY_STATUSES.includes(instance.status)) {
          await this._recordProgress(instance, {
            ...vastFields,
            stage: 'engine_starting',
            message: 'Unpacking AI inference engine from Cloudflare R2 & initializing server...',
            portFound: true,
            engineReachable: false,
          }, now);
        }
        return instance;
      }

      const models = Array.isArray(data?.models) ? data.models : [];
      const instIdStr = String(id);

      // The engine reported it cannot start (self-test failed) or a selected model failed:
      // stop now with the reason instead of waiting for the timeout.
      if (!READY_STATUSES.includes(instance.status)) {
        const failedModel = models.find((m) => m.status === 'failed');
        if (data?.status === 'failed' || failedModel) {
          const reason =
            data?.status === 'failed'
              ? `The engine could not start: ${data.reason || 'unknown error'}`
              : `Model ${failedModel.modelId} could not be loaded: ${failedModel.error || 'unknown error'}`;
          await this._failEngine(instance, reason, now);
          return instance;
        }
      }

      await this._recordProgress(instance, {
        ...vastFields,
        portFound: true,
        engineReachable: true,
        models: models.map((m) => ({
          modelId: m.modelId,
          status: m.status,
          progressPercent: Math.round(Number(m.progressPercent) || 0),
          error: m.error || null,
        })),
        ...this._modelsProgress(models, data),
      }, now);

      // Instance reaches READY only when ALL requested models are ready.
      // If models list is available, require every entry to have status === 'ready'.
      // If no models list is provided, fall back to data.model_loaded.
      const allModelsReady =
        models.length > 0
          ? models.every((m) => m.status === 'ready')
          : Boolean(data?.model_loaded);

      // Build models signature to detect progress or status transitions
      const modelsSig = JSON.stringify(
        models.map((m) => [m.modelId, m.status, Math.floor(m.progressPercent || 0), m.loadedInVram])
      );
      const prevSig = this._lastModelsSignature.get(instIdStr);
      const hasModelsChanged = models.length > 0 && modelsSig !== prevSig;
      const telemetry = {
        device: data?.device,
        deviceName: data?.device_name,
        currentModel: data?.current_model,
        models,
      };

      if (allModelsReady) {
        if (!READY_STATUSES.includes(instance.status)) {
          const prev = instance.status;
          const moved = await GpuInstance.findOneAndUpdate(
            { _id: id, status: { $in: [GPU_STATUS.PROVISIONING, GPU_STATUS.DOWNLOADING_MODEL] } },
            {
              $set: { status: GPU_STATUS.READY, reachedReadyAt: now },
              $push: {
                provisioningLogs: {
                  message: `Python engine confirmed READY. All ${models.length} model(s) ready. Active: ${data.current_model || 'ready'} on ${data.device || 'gpu'} (${data.device_name || 'cuda'})`,
                  level: LOG_LEVELS.INFO,
                },
              },
            }
          );
          if (!moved) return instance;
          instance.status = GPU_STATUS.READY;
          console.info(`[InstancePoller] Instance ${id} reached READY state (from ${prev}). All models ready.`);
          this._lastModelsSignature.set(instIdStr, modelsSig);
          this.emitStatusChange(instance, GPU_STATUS.READY, telemetry);
        } else if (hasModelsChanged) {
          // Already READY, push any subtle telemetry or model changes
          this._lastModelsSignature.set(instIdStr, modelsSig);
          this.emitStatusChange(instance, instance.status, telemetry);
        }
      } else if (instance.status === GPU_STATUS.PROVISIONING) {
        // At least one model is still queued, downloading, or loading -> DOWNLOADING_MODEL
        const moved = await GpuInstance.findOneAndUpdate(
          { _id: id, status: GPU_STATUS.PROVISIONING },
          {
            $set: { status: GPU_STATUS.DOWNLOADING_MODEL },
            $push: { provisioningLogs: { message: 'Python engine online. Model weights are downloading/loading into VRAM...', level: LOG_LEVELS.INFO } },
          }
        );
        if (!moved) return instance;
        instance.status = GPU_STATUS.DOWNLOADING_MODEL;
        console.info(`[InstancePoller] Instance ${id} entered DOWNLOADING_MODEL state (from provisioning).`);
        this._lastModelsSignature.set(instIdStr, modelsSig);
        this.emitStatusChange(instance, GPU_STATUS.DOWNLOADING_MODEL, telemetry);
      } else if (hasModelsChanged) {
        // Relay progress increments as models download/load
        this._lastModelsSignature.set(instIdStr, modelsSig);
        this.emitStatusChange(instance, instance.status, telemetry);
      }
    }

    return instance;
  }

  /** Progress text before the engine port is known. */
  _hostProgress(instance, confirmed, vastFields) {
    if (!confirmed) {
      return { stage: 'requesting', message: 'Allocating dedicated GPU server hardware...' };
    }
    const { vastStatus, vastStatusMessage } = vastFields;
    if (!vastStatus) {
      return { stage: 'starting', message: 'GPU server allocated. Initializing runtime environment...' };
    }
    if (vastStatus !== 'running') {
      return {
        ...vastFields,
        stage: 'starting',
        message: sanitizeVastProgressMessage(vastStatus, vastStatusMessage),
      };
    }
    return { ...vastFields, stage: 'waiting_for_port', message: 'GPU container online. Mapping high-speed communication ports...' };
  }

  /** Stage and text once the engine answers. */
  _modelsProgress(models, data) {
    if (models.length === 0) {
      return { stage: 'ready', message: 'GPU inference engine ready! Opening Creative Studio...' };
    }
    if (models.every((m) => m.status === 'ready')) {
      return { stage: 'ready', message: 'GPU inference engine ready! Opening Creative Studio...' };
    }
    const current = models.find((m) => m.status !== 'ready') || models[0];
    const pct = Math.round(Number(current.progressPercent) || 0);
    const friendlyName = formatFriendlyModelName(current.modelId);
    const verb = {
      queued: 'Queued to stream',
      downloading: 'Streaming weights for',
      loading: 'Loading into high-speed GPU VRAM:',
      ready: 'Ready:',
    }[current.status] || 'Preparing';
    const done = models.filter((m) => m.status === 'ready').length;
    return {
      stage: 'downloading_models',
      message: `${verb} ${friendlyName}${current.status === 'downloading' ? ` (${pct}%)` : ''} — ${done} of ${models.length} models ready.`,
    };
  }

  /**
   * Store the latest progress (and log each new step once), then tell subscribers,
   * with elapsed time and credits charged so far. Unchanged progress is not re-sent.
   */
  async _recordProgress(instance, patch, now = new Date()) {
    const id = String(instance._id);
    const previous = instance.progress?.toObject ? instance.progress.toObject() : instance.progress || {};
    const progress = { ...previous, ...patch, updatedAt: now };
    const sig = JSON.stringify([
      progress.stage, progress.message, progress.vastStatus, progress.vastStatusMessage,
      progress.portFound, progress.engineReachable,
      (progress.models || []).map((m) => [m.modelId, m.status, m.progressPercent]),
    ]);
    const known = this._progressSig.get(id) ?? (previous.stage ? JSON.stringify([
      previous.stage, previous.message, previous.vastStatus, previous.vastStatusMessage,
      previous.portFound, previous.engineReachable,
      (previous.models || []).map((m) => [m.modelId, m.status, m.progressPercent]),
    ]) : null);
    if (sig === known) return;
    this._progressSig.set(id, sig);

    const update = { $set: { progress } };
    const newStep = progress.stage !== previous.stage || (progress.stage !== 'downloading_models' && progress.message !== previous.message);
    if (newStep && progress.message) {
      update.$push = { provisioningLogs: { message: progress.message, level: LOG_LEVELS.INFO } };
    }
    const saved = await GpuInstance.findOneAndUpdate(
      { _id: instance._id, status: { $in: ACTIVE_STATUSES } },
      update,
      { returnDocument: 'after' }
    );
    if (!saved) return;
    instance.progress = saved.progress;

    const startedAt = saved.contractConfirmedAt || saved.startedAt || saved.createdAt;
    this.emitStatusChange(saved, saved.status, {
      progress: {
        stage: progress.stage,
        message: progress.message,
        vastStatus: progress.vastStatus || null,
        vastStatusMessage: progress.vastStatusMessage || null,
        portFound: Boolean(progress.portFound),
        engineReachable: Boolean(progress.engineReachable),
        models: progress.models || [],
      },
      elapsedSeconds: Math.max(0, Math.round((now - new Date(startedAt)) / 1000)),
      creditsCharged: saved.creditsCharged || 0,
      creditsRefunded: saved.creditsRefunded || 0,
    });
  }

  /** The engine cannot start: destroy, fail, refund, and say why. */
  async _failEngine(instance, reason, now = new Date()) {
    const id = instance._id;
    console.warn(`[InstancePoller] Instance ${id} (${instance.providerInstanceId}) failed: ${reason}`);
    if (isConfirmedContractId(instance.providerInstanceId)) {
      try {
        await vastaiService.destroyInstance(instance.providerInstanceId);
      } catch (err) {
        console.error(`[InstancePoller] Destroy after engine failure failed for #${instance.providerInstanceId}: ${err.message}`);
        await GpuInstance.updateOne(
          { _id: id },
          {
            $set: { pendingStopReason: STOP_REASONS.ENGINE_FAILED, 'progress.failureReason': reason },
            $push: { provisioningLogs: { message: `${reason} Stopping the instance failed (${err.message}); retrying.`, level: LOG_LEVELS.WARN } },
          }
        );
        return;
      }
    }
    await GpuInstance.updateOne({ _id: id }, { $set: { 'progress.failureReason': reason, 'progress.stage': 'failed' } });
    await billingService.finalizeInstance(id, {
      status: GPU_STATUS.FAILED,
      stopReason: STOP_REASONS.ENGINE_FAILED,
      until: now,
      refundIfNeverReady: true,
      message: `${reason} The instance was stopped and everything charged was refunded.`,
      level: LOG_LEVELS.ERROR,
      emitReason: 'ENGINE_FAILED',
    });
  }

  /**
   * Broadcast status change to internal event bus
   * @param {Object} instance - Mongoose GpuInstance
   * @param {string} dbStatus - New database status
   * @param {Object} extraDetails - Additional telemetry details
   */
  emitStatusChange(instance, dbStatus, extraDetails = {}) {
    const status = toWebSocketStatus(dbStatus);
    const existingProgress = instance.progress?.toObject ? instance.progress.toObject() : instance.progress;
    const details = {
      gpuType: instance.gpuType,
      publicIp: instance.publicIp,
      pythonEngineUrl: instance.pythonEngineUrl,
      modelsRequested: instance.modelsRequested,
      ...(existingProgress ? { progress: existingProgress } : {}),
      ...extraDetails,
    };
    this._lastKnownDetails.set(String(instance._id), details);

    const payload = {
      instanceId: String(instance._id),
      status,
      timestamp: new Date().toISOString(),
      details,
    };

    instanceEvents.emit('status_change', payload);
  }

  getLastKnownDetails(instanceId) {
    return this._lastKnownDetails.get(String(instanceId)) || {};
  }
}

export const instancePollerService = new InstancePollerService();
