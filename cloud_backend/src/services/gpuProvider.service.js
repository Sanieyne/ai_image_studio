/**
 * GPU Provider Orchestration Service
 * Merges Vast.ai real-time marketplace availability with model sizing requirements,
 * calculates hardware fit scores, and manages user cloud instance deployments.
 */

import { vastaiService, isConfirmedContractId } from './vastai.service.js';
import { billingService, ACTIVE_STATUSES, STOP_REASONS } from './billing.service.js';
import { recommendationService } from './recommendation.service.js';
import { creditService } from './credit.service.js';
import { pricingService } from './pricing.service.js';
import { GpuInstance } from '../models/GpuInstance.js';
import {
  GPU_STATUS,
  GPU_PROVIDERS,
  BANDWIDTH_COST_PER_GB,
  STORAGE_MIN_GB,
  STORAGE_MAX_GB,
  MIN_INET_DOWN_FLOOR_MBPS,
  LOG_LEVELS,
} from '../config/constants.js';
import { ApiError } from '../utils/ApiError.js';
import { env } from '../config/env.js';

/** Every Vast.ai instance we create is labelled `cosmicgen-<GpuInstance id>`. */
export const INSTANCE_LABEL_PREFIX = 'cosmicgen-';

class GpuProviderService {
  /**
   * Search available GPUs on Vast.ai filtered and tailored to model selection
   * @param {Object} options
   * @returns {Promise<Object>}
   */
  async searchAvailableGPUs(options = {}) {
    const {
      selectedModelIds = [],
      minVramGB = 0,
      maxPricePerHour,
      minInetDown = MIN_INET_DOWN_FLOOR_MBPS,
      gpuName,
      verifiedOnly = true,
      limit = 250,
      orderBy = 'price',
    } = options;

    // Hard floor enforcement: client cannot request a speed floor below 400 Mbps
    const effectiveMinInetDown = Math.max(MIN_INET_DOWN_FLOOR_MBPS, Number(minInetDown) || 0);

    let requirements = null;
    let requiredVram = minVramGB;
    let requiredDisk = 30;
    let totalModelSizeGB = 15;

    // 1. Analyze selected model requirements if provided
    if (Array.isArray(selectedModelIds) && selectedModelIds.length > 0) {
      requirements = await recommendationService.calculateRequirements(selectedModelIds);
      requiredVram = Math.max(requiredVram, requirements.requirements.maxVramGB);
      requiredDisk = Math.max(requiredDisk, requirements.requirements.totalWithBufferGB);
      totalModelSizeGB = requirements.requirements.totalModelSizeGB;
    }

    // 2. Fetch live marketplace offers from Vast.ai with hard 400 Mbps floor
    const rawOffers = await vastaiService.searchOffers({
      minVramGB: requiredVram,
      minDiskGB: requiredDisk,
      minInetDown: effectiveMinInetDown,
      gpuName,
      verifiedOnly,
      limit: limit * 2, // Fetch slightly more for client-side filtering
      totalModelSizeGB,
    });

    // 3. Defense-in-depth: strictly exclude any offer below 400 Mbps and filter by maxPricePerHour
    let filteredOffers = rawOffers.filter((o) => (o.inetDown ?? 0) >= MIN_INET_DOWN_FLOOR_MBPS);
    if (maxPricePerHour != null && !isNaN(maxPricePerHour)) {
      filteredOffers = filteredOffers.filter((o) => o.pricePerHour <= Number(maxPricePerHour));
    }

    // 4. Enrich with intelligent headroom and fit classifications
    const enrichedOffers = filteredOffers.map((offer) => {
      const targetVram = requiredVram || 12;
      const headroom = Math.round((offer.vramGB - targetVram) * 10) / 10;
      let fit = 'minimum';
      let reason = `Meets minimum ${targetVram}GB VRAM threshold.`;

      if (headroom >= 8) {
        fit = 'optimal';
        reason = `Superb fit with ${headroom}GB VRAM headroom for multi-batch inference and 4K upscaling.`;
      } else if (headroom >= 2) {
        fit = 'tight';
        reason = `Balanced fit with ${headroom}GB VRAM headroom. Ideal for standard single-image generations.`;
      }

      const estimatedMonthlyBandwidthCost = Math.round(100 * BANDWIDTH_COST_PER_GB * 100) / 100;

      return {
        ...offer,
        headroomVramGB: headroom,
        fit,
        fitReason: reason,
        estimatedMonthlyBandwidthCost,
      };
    });

    // 5. Sorting
    enrichedOffers.sort((a, b) => {
      if (orderBy === 'dlperf') {
        return b.dlperf - a.dlperf;
      }
      if (orderBy === 'reliability') {
        return b.reliability - a.reliability;
      }
      return (a.totalCreditsPerHour ?? a.creditsPerHour) - (b.totalCreditsPerHour ?? b.creditsPerHour);
    });

    return {
      requirements: requirements?.requirements || {
        maxVramGB: requiredVram,
        totalWithBufferGB: requiredDisk,
        modelCount: selectedModelIds.length,
      },
      offers: enrichedOffers.slice(0, limit),
      count: Math.min(enrichedOffers.length, limit),
      totalAvailable: enrichedOffers.length,
      filters: {
        selectedModelIds,
        minVramGB: requiredVram,
        minDiskGB: requiredDisk,
        maxPricePerHour,
        minInetDown: effectiveMinInetDown,
      },
    };
  }

  /**
   * Return specialized recommendations (cheapest, fastest, most reliable, balanced)
   * @param {string[]} modelIds
   * @returns {Promise<Object>}
   */
  async getRecommendedGPUsForSelection(modelIds = [], limit = 250) {
    const searchResult = await this.searchAvailableGPUs({
      selectedModelIds: modelIds,
      limit,
    });

    const { offers, requirements } = searchResult;
    if (offers.length === 0) {
      return {
        requirements,
        cheapestOffer: null,
        fastestOffer: null,
        mostReliableOffer: null,
        balancedOffer: null,
        allOffers: [],
      };
    }

    // 1. Cheapest offer
    const cheapestOffer = [...offers].sort((a, b) => a.totalHourlyCost - b.totalHourlyCost)[0];

    // 2. Fastest offer by dlperf compute score
    const fastestOffer = [...offers].sort((a, b) => b.dlperf - a.dlperf)[0];

    // 3. Most reliable offer (reliability >= 0.98 priority)
    const mostReliableOffer = [...offers]
      .filter((o) => o.reliability >= 0.95)
      .sort((a, b) => b.reliability - a.reliability || a.totalHourlyCost - b.totalHourlyCost)[0] || offers[0];

    // 4. Balanced offer (Optimal fit, competitive price, high speed)
    const balancedOffer =
      offers.find((o) => o.fit === 'optimal' && o.reliability >= 0.98) ||
      offers.find((o) => o.fit === 'tight') ||
      offers[0];

    return {
      requirements,
      cheapestOffer,
      fastestOffer,
      mostReliableOffer,
      balancedOffer,
      allOffers: offers,
    };
  }

  /**
   * Estimate comprehensive pricing for a given offer over a defined duration and bandwidth
   * @param {Object} params - { offer, storageGB, hours, bandwidthGB }
   * @returns {Object}
   */
  estimateCost(params = {}) {
    const {
      offer,
      storageGB = 100,
      hours = 1,
      bandwidthGB = 10,
    } = params;

    if (!offer) {
      throw ApiError.badRequest('Offer specification is required for pricing estimation.');
    }

    const numericStorage = Number(storageGB);
    if (isNaN(numericStorage) || numericStorage < STORAGE_MIN_GB || numericStorage > STORAGE_MAX_GB) {
      throw ApiError.badRequest(`storageGB must be between ${STORAGE_MIN_GB} and ${STORAGE_MAX_GB} GB.`);
    }

    // Compute storage pricing using the host's real rate
    const storagePricing = pricingService.calculateStoragePricing(numericStorage, offer);

    const computeCreditsPerHour = offer.creditsPerHour;
    const storageCreditsPerHour = storagePricing.creditsPerHour;
    const computeCredits = Math.round(computeCreditsPerHour * hours * 10) / 10;
    const storageCredits = Math.round(storageCreditsPerHour * hours * 100) / 100;

    const bandwidthCost = Math.round(bandwidthGB * (offer.bandwidthCostPerGB || BANDWIDTH_COST_PER_GB) * 1000) / 1000;
    const bandwidthCredits = pricingService.usdToCredits(bandwidthCost, 2);

    const totalCreditsPerHour = Math.round((computeCreditsPerHour + storageCreditsPerHour) * 100) / 100;
    const totalCredits = Math.round((computeCredits + storageCredits + bandwidthCredits) * 10) / 10;

    return {
      offerId: String(offer.id),
      gpuName: offer.gpuName,
      hours: Number(hours),
      storageGB: numericStorage,
      bandwidthGB: Number(bandwidthGB),
      breakdown: {
        computeCredits,
        storageCredits,
        bandwidthCredits,
      },
      totalCredits,
      creditsPerHour: totalCreditsPerHour,
    };
  }

  /**
   * Generates dynamic onstart shell script for Vast.ai GPU instance.
   * - Configures workspace and logs
   * - Sets up python dependencies (boto3, requirements.txt)
   * - Pulls selected models from R2 via download_model.py
   * - Starts Python inference engine on port 8000
   */
  _generateOnstartScript({ selectedModelIds = [] } = {}) {
    return [
      '#!/bin/bash',
      'set -e',
      'LOG_FILE="/var/log/ai_studio_onstart.log"',
      'mkdir -p /var/log',
      'exec > >(tee -a "$LOG_FILE") 2>&1',
      '',
      'echo "=========================================================="',
      'echo "[$(date -u +\'%Y-%m-%d %H:%M:%S UTC\')] AI Studio GPU Instance OnStart Initializing"',
      'echo "=========================================================="',
      '',
      '# 1. Persist container environment variables for SSH and non-interactive subshells',
      'env | grep -E \'^(AI_STUDIO|R2_|PATH|CUDA|DEBIAN)\' >> /etc/environment 2>/dev/null || true',
      '',
      'echo "[STAGE 1/4] Preparing workspace and engine source..."',
      'mkdir -p /workspace',
      'cd /workspace',
      '',
      '# Bootstrap python dependencies for R2 transport',
      'export PIP_BREAK_SYSTEM_PACKAGES=1',
      'python3 -m pip install --no-cache-dir --break-system-packages boto3 botocore || true',
      '',
      '# Fetch python_engine package from R2 if not already present',
      'if [ ! -d "/workspace/python_engine" ] && [ ! -d "/root/projects/ai_image_studio/python_engine" ]; then',
      '  echo "Fetching python_engine package from Cloudflare R2..."',
      '  python3 -c "',
      'import os, boto3',
      's3 = boto3.client(\'s3\', endpoint_url=os.environ.get(\'R2_ENDPOINT\'),',
      '                  aws_access_key_id=os.environ.get(\'R2_ACCESS_KEY_ID\'),',
      '                  aws_secret_access_key=os.environ.get(\'R2_SECRET_ACCESS_KEY\'))',
      's3.download_file(os.environ.get(\'R2_BUCKET_NAME\', \'cosmic-gen\'), \'models/engine/python_engine.tar.gz\', \'/workspace/python_engine.tar.gz\')',
      '" 2>/dev/null || true',
      '  if [ -f "/workspace/python_engine.tar.gz" ]; then',
      '    mkdir -p /workspace/python_engine',
      '    tar -xzf /workspace/python_engine.tar.gz -C /workspace/python_engine/',
      '    rm -f /workspace/python_engine.tar.gz',
      '    echo "[OK] python_engine extracted into /workspace/python_engine"',
      '  fi',
      'fi',
      '',
      '# Locate and enter engine directory',
      'if [ -d "/workspace/python_engine" ]; then',
      '  cd /workspace/python_engine',
      'elif [ -d "/root/projects/ai_image_studio/python_engine" ]; then',
      '  cd /root/projects/ai_image_studio/python_engine',
      'fi',
      'echo "Current working directory: $(pwd)"',
      '',
      'echo "[STAGE 2/4] Installing Python engine dependencies..."',
      'if [ -z "$AI_STUDIO_SKIP_PIP" ] && [ -f "requirements.txt" ]; then',
      '  echo "Installing requirements from $(pwd)/requirements.txt..."',
      '  python3 -m pip install --no-cache-dir --break-system-packages -r requirements.txt || true',
      'else',
      '  echo "Skipping full pip install (AI_STUDIO_SKIP_PIP set or requirements.txt missing)."',
      'fi',
      '',
      'echo "[STAGE 3/4] Starting AI Studio Python Engine on port 8000..."',
      'export PORT=8000',
      'export HOST=0.0.0.0',
      'export AI_STUDIO_HOST="0.0.0.0"',
      'export AI_STUDIO_PORT="8000"',
      'if [ -f "app.py" ]; then',
      '  nohup python3 app.py > /var/log/ai_engine.log 2>&1 &',
      '  ENGINE_PID=$!',
      '  echo "[OK] Engine started with PID $ENGINE_PID (logging to /var/log/ai_engine.log)"',
      'elif [ -f "launcher.py" ]; then',
      '  nohup python3 launcher.py > /var/log/ai_engine.log 2>&1 &',
      '  ENGINE_PID=$!',
      '  echo "[OK] Launcher started with PID $ENGINE_PID"',
      'else',
      '  nohup python3 -m uvicorn api.main:app --host 0.0.0.0 --port 8000 > /var/log/ai_engine.log 2>&1 &',
      '  ENGINE_PID=$!',
      '  echo "[OK] Engine spawned via uvicorn with PID $ENGINE_PID"',
      'fi',
      '',
      '# Health check verification',
      'echo "Verifying engine startup on http://127.0.0.1:8000/health..."',
      'for i in $(seq 1 30); do',
      '  if curl -s http://127.0.0.1:8000/health > /dev/null 2>&1; then',
      '    echo "[OK] Engine is healthy and responding on port 8000!"',
      '    break',
      '  fi',
      '  sleep 2',
      'done',
      '',
      'echo "[STAGE 4/4] Model weights background lifecycle active..."',
      'echo "Active AI_STUDIO_SELECTED_MODELS: ${AI_STUDIO_SELECTED_MODELS}"',
      '',
      'echo "=========================================================="',
      'echo "[$(date -u +\'%Y-%m-%d %H:%M:%S UTC\')] Onstart Script Completed Successfully"',
      'echo "=========================================================="',
    ].join('\n');
  }

  /**
   * Rent a GPU instance via Vast.ai and initialize internal tracking
   * @param {Object} params - { userId, offerId, storageGB, selectedModelIds }
   * @returns {Promise<Object>}
   */
  async rentGPU(params = {}) {
    const { userId, offerId, storageGB = 100, selectedModelIds = [] } = params;

    if (!userId) throw ApiError.unauthorized('User must be logged in to rent a cloud GPU.');
    if (!offerId) throw ApiError.badRequest('Vast.ai offer ID is required.');

    const numericStorage = Number(storageGB);
    if (isNaN(numericStorage) || numericStorage < STORAGE_MIN_GB || numericStorage > STORAGE_MAX_GB) {
      throw ApiError.badRequest(`storageGB must be between ${STORAGE_MIN_GB} and ${STORAGE_MAX_GB} GB.`);
    }

    // 1. Fetch offer details
    const offer = await vastaiService.getOffer(offerId);

    // Defense-in-depth: independently re-verify the host meets the 400 Mbps download speed floor
    const hostInetDown = offer.inetDown ?? offer.rawOffer?.inet_down ?? 0;
    if (hostInetDown < MIN_INET_DOWN_FLOOR_MBPS) {
      throw ApiError.badRequest(
        `Host download speed (${hostInetDown} Mbps) does not meet the minimum required threshold of ${MIN_INET_DOWN_FLOOR_MBPS} Mbps for reliable model streaming. Please select another offer.`
      );
    }

    // 2. Compute live continuous storage pricing and initial funding required in CREDITS using the offer's real rate
    const storagePricing = pricingService.calculateStoragePricing(numericStorage, offer);
    const storagePricePerHour = storagePricing._internal?.pricePerHour || 0;
    const totalHourlyCost = Math.round(((offer.dphBase || offer.pricePerHour) + storagePricePerHour) * 1000) / 1000;
    const totalCreditsPerHour = Math.round((offer.creditsPerHour + storagePricing.creditsPerHour) * 10) / 10;

    const minLaunch = pricingService.getCachedConfig().minLaunchCredits || 10;
    const initialCreditsRequired = Math.max(
      minLaunch,
      totalCreditsPerHour
    );
    const hasSufficientCredits = await creditService.hasEnough(userId, initialCreditsRequired);

    if (!hasSufficientCredits) {
      throw ApiError.paymentRequired(
        `Insufficient credit balance. You need at least ${initialCreditsRequired} credits to launch this ${offer.gpuName} instance.`
      );
    }

    // 3. Reserve one of the user's active-instance slots (race-safe), then create
    //    the GpuInstance document in provisioning state holding that slot.
    const maxActive = env.GPU_MAX_ACTIVE_PER_USER;
    if (!(await billingService.acquireSlot(userId, maxActive))) {
      throw ApiError.conflict(
        maxActive === 1
          ? 'You already have an active cloud GPU. Stop it before renting another.'
          : `You already have ${maxActive} active cloud GPUs. Stop one before renting another.`
      );
    }

    let instance;
    try {
      instance = await GpuInstance.create({
        holdsSlot: true,
        user: userId,
        provider: GPU_PROVIDERS.VASTAI,
        providerInstanceId: `pending-${Date.now()}`,
        status: GPU_STATUS.PROVISIONING,
        gpuType: offer.gpuName,
        vramGB: offer.vramGB,
        costPerHour: totalHourlyCost,
        modelsRequested: selectedModelIds,
        vastOffer: offer,
        pricing: {
          dph_total: offer.pricePerHour,
          storageCost: storagePricePerHour,
          bandwidthCost: offer.bandwidthCostPerGB,
          totalPerHour: totalHourlyCost,
          creditsPerHour: offer.creditsPerHour,
          totalCreditsPerHour: totalCreditsPerHour,
          storageCreditsPerHour: storagePricing.creditsPerHour,
          bandwidthCreditsPerGB: offer.bandwidthCreditsPerGB,
          creditsPerUsd: pricingService.getCachedConfig().tokenValue,
        },
        network: {
          inet_up: offer.inetUp,
          inet_down: offer.inetDown,
          reliability: offer.reliability,
          geolocation: offer.geolocation,
        },
        specs: {
          cudaVersion: offer.cudaVersion,
          driver: offer.driverVersion,
          directPortCount: offer.directPortCount,
          cpuCores: offer.cpuCores,
          ramGB: offer.ramGB,
          diskGB: numericStorage,
        },
        provisioningLogs: [
          { message: `Requested provisioning on Vast.ai for ${offer.gpuName} (${offer.id})` },
        ],
        startedAt: new Date(),
      });
    } catch (createErr) {
      await billingService.releaseUnclaimedSlot(userId);
      throw createErr;
    }

    // 4. Trigger Vast.ai instance creation
    let vastResult;
    try {
      const onstartScript = this._generateOnstartScript({ selectedModelIds });
      vastResult = await vastaiService.createInstance(offer.id, {
        label: `${INSTANCE_LABEL_PREFIX}${instance._id}`,
        disk: numericStorage,
        onstart: onstartScript,
        env: {
          AI_STUDIO_USER_ID: String(userId),
          AI_STUDIO_INSTANCE_ID: String(instance._id),
          AI_STUDIO_SELECTED_MODELS: selectedModelIds.join(','),
          R2_ENDPOINT: env.R2_ENDPOINT,
          R2_BUCKET_NAME: env.R2_BUCKET_NAME,
          R2_ACCESS_KEY_ID: env.R2_READONLY_ACCESS_KEY_ID || env.R2_ACCESS_KEY_ID,
          R2_SECRET_ACCESS_KEY: env.R2_READONLY_SECRET_ACCESS_KEY || env.R2_SECRET_ACCESS_KEY,
          '-p 8000:8000': '1',
        },
      });

    } catch (error) {
      await billingService.finalizeInstance(instance._id, {
        status: GPU_STATUS.FAILED,
        stopReason: STOP_REASONS.PROVISIONING_FAILED,
        message: `Provisioning failed: ${error.message}`,
        level: LOG_LEVELS.ERROR,
        emitReason: 'PROVISIONING_FAILED',
      });
      throw error;
    }

    // 5. Contract confirmed: billing starts now. Conditional on the instance
    //    still provisioning: the user may have stopped it during the create call.
    const contractId = String(vastResult.new_contract || vastResult.instanceId);
    const confirmedAt = new Date();
    const confirmed = await GpuInstance.findOneAndUpdate(
      { _id: instance._id, status: GPU_STATUS.PROVISIONING },
      {
        $set: { providerInstanceId: contractId, contractConfirmedAt: confirmedAt, billedUntil: confirmedAt },
        $push: { provisioningLogs: { message: `Vast.ai contract established: #${contractId}` } },
      },
      { returnDocument: 'after' }
    );
    if (confirmed) return confirmed;

    // Stopped meanwhile: destroy the new contract right away. Nothing is billed.
    await GpuInstance.updateOne(
      { _id: instance._id },
      {
        $set: { providerInstanceId: contractId, contractConfirmedAt: confirmedAt },
        $push: { provisioningLogs: { message: `Vast.ai contract #${contractId} arrived after the instance was stopped; destroying it.`, level: LOG_LEVELS.WARN } },
      }
    );
    try {
      await vastaiService.destroyInstance(contractId);
    } catch (err) {
      // The reconciliation job reports (and optionally destroys) labelled orphans.
      console.error(`[GpuProvider] !!! Could not destroy late contract #${contractId} for stopped instance ${instance._id}: ${err.message}`);
    }
    return GpuInstance.findById(instance._id);
  }

  /**
   * Get active GPU instances for authenticated user
   * @param {string} userId
   * @returns {Promise<Array>}
   */
  async getUserInstances(userId) {
    return GpuInstance.find({
      user: userId,
      status: { $in: ACTIVE_STATUSES },
    })
      .sort({ createdAt: -1 })
      .lean();
  }

  /**
   * Terminate a user instance
   * @param {string} userId
   * @param {string} instanceId
   * @returns {Promise<Object>}
   */
  async terminateInstance(userId, instanceId) {
    const instance = await GpuInstance.findOne({ _id: instanceId, user: userId });
    if (!instance) {
      throw ApiError.notFound('GPU instance not found or unauthorized.');
    }

    if (!ACTIVE_STATUSES.includes(instance.status)) {
      return instance;
    }

    // Destroy first; if that fails the instance stays active (and billable) and the user can retry.
    if (isConfirmedContractId(instance.providerInstanceId)) {
      await vastaiService.destroyInstance(instance.providerInstanceId);
    }

    const stopped = await billingService.finalizeInstance(instance._id, {
      status: GPU_STATUS.STOPPED,
      stopReason: STOP_REASONS.USER_STOPPED,
      until: new Date(),
      message: 'Instance manually terminated by user.',
      emitReason: 'USER_STOPPED',
    });
    return stopped || GpuInstance.findById(instance._id);
  }
}

export const gpuProviderService = new GpuProviderService();
