/**
 * GPU Instance Health-Check & Provisioning Poller Service
 * Monitors active GPU instances in PROVISIONING or DOWNLOADING_MODEL states.
 * - Discovers public IP + mapped port from Vast.ai API
 * - Polls GET http://{ip}:{port}/health every 6s
 * - Handles transitions: PROVISIONING -> DOWNLOADING_MODEL -> READY
 * - Handles 10-minute timeout -> FAILED with automatic Vast.ai instance termination
 * - Emits event-driven notifications to WebSocket subscribers
 */

import axios from 'axios';
import { EventEmitter } from 'events';
import { GpuInstance } from '../models/GpuInstance.js';
import { vastaiService } from './vastai.service.js';
import { GPU_STATUS, GPU_PROVIDERS, LOG_LEVELS } from '../config/constants.js';

export const instanceEvents = new EventEmitter();

/**
 * Standardize database status into WebSocket status string
 * @param {string} dbStatus
 * @returns {string}
 */
export function toWebSocketStatus(dbStatus) {
  switch (dbStatus?.toLowerCase()) {
    case 'provisioning':
      return 'PROVISIONING';
    case 'downloading_model':
      return 'DOWNLOADING_MODEL';
    case 'ready':
      return 'READY';
    case 'running':
      return 'READY';
    case 'failed':
      return 'FAILED';
    case 'stopped':
      return 'STOPPED';
    default:
      return (dbStatus || 'UNKNOWN').toUpperCase();
  }
}

export class InstancePollerService {
  constructor(options = {}) {
    this.intervalMs = options.intervalMs || 4000; // 4 seconds for responsive real-time streaming
    this.timeoutMs = options.timeoutMs || 10 * 60 * 1000; // 10 minutes
    this.healthTimeoutMs = options.healthTimeoutMs || 4000;
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
   * Execute single poll cycle across all active unready instances
   */
  async pollCycle() {
    if (this._isPolling) return;
    this._isPolling = true;

    try {
      const activeInstances = await GpuInstance.find({
        status: { $in: [GPU_STATUS.PROVISIONING, GPU_STATUS.DOWNLOADING_MODEL] },
      });

      if (activeInstances.length === 0) {
        return;
      }

      for (const instance of activeInstances) {
        try {
          await this.pollInstance(instance);
        } catch (instErr) {
          console.error(`[InstancePoller] Error checking instance ${instance._id}:`, instErr.message);
        }
      }
    } finally {
      this._isPolling = false;
    }
  }

  /**
   * Poll and update status for a single instance
   * @param {Object} instance - Mongoose GpuInstance document
   * @returns {Promise<Object>}
   */
  async pollInstance(instance) {
    const startedAt = instance.startedAt || instance.createdAt || new Date();
    const elapsedMs = Date.now() - new Date(startedAt).getTime();

    // Scale timeout dynamically: 20 min base, 40 min for large models (e.g. Qwen-Image 33GB, Flux, Minimax)
    const hasLargeModels = (instance.modelsRequested || []).some((m) =>
      ['qwen-image-2.1', 'flux-1-schnell', 'flux-1-dev', 'minimax-h3', 'sd3-medium'].includes(m)
    );
    const dynamicTimeoutMs = hasLargeModels ? 40 * 60 * 1000 : 25 * 60 * 1000;

    // 1. Timeout Check: If exceeded timeout ceiling, mark FAILED and auto-terminate
    if (elapsedMs > dynamicTimeoutMs) {
      console.warn(`[InstancePoller] Instance ${instance._id} (${instance.providerInstanceId}) timed out after ${Math.round(elapsedMs / 1000)}s.`);
      instance.status = GPU_STATUS.FAILED;
      instance.stoppedAt = new Date();
      instance.provisioningLogs.push({
        message: `[TIMEOUT] Provisioning exceeded timeout ceiling (${Math.round(dynamicTimeoutMs / 60000)} min) without reaching ready status.`,
        level: LOG_LEVELS.ERROR,
      });

      // Auto-terminate Vast.ai instance so the user is not billed for a dead machine
      if (
        instance.provider === GPU_PROVIDERS.VASTAI &&
        instance.providerInstanceId &&
        !instance.providerInstanceId.startsWith('pending-') &&
        !instance.providerInstanceId.startsWith('mock-')
      ) {
        try {
          console.info(`[InstancePoller] Auto-terminating Vast.ai contract #${instance.providerInstanceId} due to timeout...`);
          await vastaiService.destroyInstance(instance.providerInstanceId);
          instance.provisioningLogs.push({
            message: `[AUTO-TERMINATE] Vast.ai instance #${instance.providerInstanceId} automatically destroyed to prevent billing.`,
            level: LOG_LEVELS.INFO,
          });
        } catch (termErr) {
          console.error(`[InstancePoller] Auto-termination failed for contract #${instance.providerInstanceId}:`, termErr.message);
          instance.provisioningLogs.push({
            message: `[AUTO-TERMINATE] Failed to destroy Vast.ai instance: ${termErr.message}`,
            level: LOG_LEVELS.WARN,
          });
        }
      }

      await instance.save();
      this.emitStatusChange(instance, GPU_STATUS.FAILED, { reason: 'PROVISIONING_TIMEOUT' });
      return instance;
    }

    // 2. Discover Public IP and Mapped Port if not yet established
    if (
      !instance.pythonEngineUrl &&
      instance.provider === GPU_PROVIDERS.VASTAI &&
      instance.providerInstanceId &&
      !instance.providerInstanceId.startsWith('pending-')
    ) {
      try {
        const details = await vastaiService.getInstanceDetails(instance.providerInstanceId);
        if (details && details.publicIp && details.mappedPort) {
          instance.publicIp = details.publicIp;
          instance.pythonEngineUrl = `http://${details.publicIp}:${details.mappedPort}`;
          if (details.sshHost) instance.sshHost = details.sshHost;
          if (details.sshPort) instance.sshPort = details.sshPort;

          instance.provisioningLogs.push({
            message: `Discovered remote endpoint ${instance.pythonEngineUrl}`,
            level: LOG_LEVELS.INFO,
          });
          await instance.save();
          console.info(`[InstancePoller] Assigned endpoint for instance ${instance._id}: ${instance.pythonEngineUrl}`);
        }
      } catch (err) {
        // Non-fatal, retry next cycle
      }
    }

    // 3. Health check query if endpoint is known
    if (instance.pythonEngineUrl) {
      try {
        const res = await axios.get(`${instance.pythonEngineUrl}/health`, {
          timeout: this.healthTimeoutMs,
          validateStatus: (code) => code === 200,
        });

        const data = res.data;
        const models = Array.isArray(data?.models) ? data.models : [];
        const instIdStr = String(instance._id);

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

        if (allModelsReady) {
          // ALL models have reached ready state -> Transition to READY
          if (instance.status !== GPU_STATUS.READY) {
            const prev = instance.status;
            instance.status = GPU_STATUS.READY;
            instance.provisioningLogs.push({
              message: `Python engine confirmed READY. All ${models.length} model(s) ready. Active: ${data.current_model || 'ready'} on ${data.device || 'gpu'} (${data.device_name || 'cuda'})`,
              level: LOG_LEVELS.INFO,
            });
            await instance.save();
            console.info(`[InstancePoller] Instance ${instance._id} reached READY state (from ${prev}). All models ready.`);
            this._lastModelsSignature.set(instIdStr, modelsSig);
            this.emitStatusChange(instance, GPU_STATUS.READY, {
              device: data.device,
              deviceName: data.device_name,
              currentModel: data.current_model,
              models,
            });
          } else if (hasModelsChanged) {
            // Already READY, push any subtle telemetry or model changes
            this._lastModelsSignature.set(instIdStr, modelsSig);
            this.emitStatusChange(instance, GPU_STATUS.READY, {
              device: data.device,
              deviceName: data.device_name,
              currentModel: data.current_model,
              models,
            });
          }
        } else {
          // At least one model is still queued, downloading, or loading -> DOWNLOADING_MODEL
          if (instance.status !== GPU_STATUS.DOWNLOADING_MODEL) {
            const prev = instance.status;
            instance.status = GPU_STATUS.DOWNLOADING_MODEL;
            instance.provisioningLogs.push({
              message: `Python engine online. Model weights are downloading/loading into VRAM...`,
              level: LOG_LEVELS.INFO,
            });
            await instance.save();
            console.info(`[InstancePoller] Instance ${instance._id} entered DOWNLOADING_MODEL state (from ${prev}).`);
            this._lastModelsSignature.set(instIdStr, modelsSig);
            this.emitStatusChange(instance, GPU_STATUS.DOWNLOADING_MODEL, {
              device: data?.device,
              deviceName: data?.device_name,
              currentModel: data?.current_model,
              models,
            });
          } else if (hasModelsChanged) {
            // Already in DOWNLOADING_MODEL, relay progress increments as models download/load
            this._lastModelsSignature.set(instIdStr, modelsSig);
            this.emitStatusChange(instance, GPU_STATUS.DOWNLOADING_MODEL, {
              device: data?.device,
              deviceName: data?.device_name,
              currentModel: data?.current_model,
              models,
            });
          }
        }
      } catch (healthErr) {
        // Connection refused / timeout / container still booting -> stay in current status (PROVISIONING)
        // No status change emitted
      }
    }

    return instance;
  }

  /**
   * Broadcast status change to internal event bus
   * @param {Object} instance - Mongoose GpuInstance
   * @param {string} dbStatus - New database status
   * @param {Object} extraDetails - Additional telemetry details
   */
  emitStatusChange(instance, dbStatus, extraDetails = {}) {
    const status = toWebSocketStatus(dbStatus);
    const details = {
      gpuType: instance.gpuType,
      publicIp: instance.publicIp,
      pythonEngineUrl: instance.pythonEngineUrl,
      modelsRequested: instance.modelsRequested,
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
