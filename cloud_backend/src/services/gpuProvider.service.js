/**
 * GPU Provider Orchestration Service
 * Merges Vast.ai real-time marketplace availability with model sizing requirements,
 * calculates hardware fit scores, and manages user cloud instance deployments.
 */

import { vastaiService, hostUnsupportedReason, isConfirmedContractId } from './vastai.service.js';
import { billingService, ACTIVE_STATUSES, STOP_REASONS } from './billing.service.js';
import { recommendationService } from './recommendation.service.js';
import { creditService } from './credit.service.js';
import { pricingService, DEFAULT_STORAGE_GB } from './pricing.service.js';
import { GpuInstance } from '../models/GpuInstance.js';
import {
  GPU_STATUS,
  GPU_PROVIDERS,
  STORAGE_MIN_GB,
  STORAGE_MAX_GB,
  MIN_INET_DOWN_FLOOR_MBPS,
  LOG_LEVELS,
} from '../config/constants.js';
import { ApiError } from '../utils/ApiError.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { env } from '../config/env.js';

/** Every Vast.ai instance we create is labelled `cosmicgen-<GpuInstance id>`. */
export const INSTANCE_LABEL_PREFIX = 'cosmicgen-';

const ONSTART_SCRIPT = fs.readFileSync(
  path.join(path.dirname(fileURLToPath(import.meta.url)), '../scripts/onstart.sh'),
  'utf8'
);

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
      storageGB = DEFAULT_STORAGE_GB,
    } = options;
    const pricingConfig = await pricingService.getConfig();

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

    // 3. Defense-in-depth: strictly exclude any offer below 400 Mbps and filter by maxPricePerHour.
    //    Prices are recomputed for the storage size the user picked.
    let filteredOffers = rawOffers
      .filter((o) => (o.inetDown ?? 0) >= MIN_INET_DOWN_FLOOR_MBPS)
      .map((o) => pricingService.repriceOffer(o, storageGB, pricingConfig));
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

      return {
        ...offer,
        headroomVramGB: headroom,
        fit,
        fitReason: reason,
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
      // Offers without a price go last.
      return (a.totalCreditsPerHour ?? Infinity) - (b.totalCreditsPerHour ?? Infinity);
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
        storageGB,
      },
    };
  }

  /**
   * Return specialized recommendations (cheapest, fastest, most reliable, balanced)
   * @param {string[]} modelIds
   * @returns {Promise<Object>}
   */
  async getRecommendedGPUsForSelection(modelIds = [], limit = 250, storageGB = DEFAULT_STORAGE_GB) {
    const searchResult = await this.searchAvailableGPUs({
      selectedModelIds: modelIds,
      limit,
      storageGB,
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
    const byTotal = (a, b) => (a.totalCreditsPerHour ?? Infinity) - (b.totalCreditsPerHour ?? Infinity);
    const cheapestOffer = [...offers].sort(byTotal)[0];

    // 2. Fastest offer by dlperf compute score
    const fastestOffer = [...offers].sort((a, b) => b.dlperf - a.dlperf)[0];

    // 3. Most reliable offer (reliability >= 0.98 priority)
    const mostReliableOffer = [...offers]
      .filter((o) => o.reliability >= 0.95)
      .sort((a, b) => b.reliability - a.reliability || byTotal(a, b))[0] || offers[0];

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

    const price = pricingService.repriceOffer(offer, numericStorage);
    const h = Number(hours);
    const r2 = (n) => Math.round(n * 100) / 100;
    if (!price.priceAvailable) {
      return {
        offerId: String(offer.id),
        gpuName: offer.gpuName,
        priceAvailable: false,
        hours: h,
        storageGB: numericStorage,
        bandwidthGB: Number(bandwidthGB),
        breakdown: { computeCredits: null, storageCredits: null, bandwidthCredits: null },
        totalCredits: null,
        creditsPerHour: null,
      };
    }

    // Same figures as the offer card and the Rent button: totalCreditsPerHour from priceOffer.
    // Bandwidth is billed by usage and is not part of the total; bandwidthCredits is only an
    // indication for `bandwidthGB` downloaded.
    return {
      offerId: String(offer.id),
      gpuName: offer.gpuName,
      priceAvailable: true,
      hours: h,
      storageGB: numericStorage,
      bandwidthGB: Number(bandwidthGB),
      computeCreditsPerHour: price.computeCreditsPerHour,
      storageCreditsPerGBMonth: price.storageCreditsPerGBMonth,
      storageCreditsPerHour: price.storageCreditsPerHour,
      totalCreditsPerHour: price.totalCreditsPerHour,
      bandwidthDownCreditsPerGB: price.bandwidthDownCreditsPerGB,
      bandwidthUpCreditsPerGB: price.bandwidthUpCreditsPerGB,
      bandwidthBilling: 'usage',
      breakdown: {
        computeCredits: r2(price.computeCreditsPerHour * h),
        storageCredits: r2(price.storageCreditsPerHour * h),
        bandwidthCredits:
          price.bandwidthDownCreditsPerGB == null ? null : r2(price.bandwidthDownCreditsPerGB * Number(bandwidthGB)),
      },
      totalCredits: r2(price.totalCreditsPerHour * h),
      creditsPerHour: price.totalCreditsPerHour,
    };
  }

  /**
   * Startup script for a rented instance: src/scripts/onstart.sh (engine package,
   * locked packages, self-test, engine on port 8000; failures reported on /health).
   */
  _generateOnstartScript() {
    return ONSTART_SCRIPT;
  }

  /**
   * Rent a GPU instance via Vast.ai and initialize internal tracking
   * @param {Object} params - { userId, offerId, storageGB, selectedModelIds }
   * @returns {Promise<Object>}
   */
  async rentGPU(params = {}) {
    const { userId, offerId, storageGB = 100, selectedModelIds = [] } = params;

    if (!userId) throw ApiError.unauthorized('User must be logged in to rent a cloud GPU.');
    if (!env.GPU_RENTALS_ENABLED) throw ApiError.serviceUnavailable(env.GPU_RENTALS_PAUSED_MESSAGE);
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
    // The engine image must run on this GPU and driver, and the engine port must be reachable.
    const unsupported = hostUnsupportedReason(offer.rawOffer || {});
    if (unsupported) throw ApiError.conflict(`${unsupported} Please choose another offer.`);

    // 2. Price for the chosen storage size: the same function as the offer card,
    //    the estimate and billing (which charges pricing.totalCreditsPerHour).
    const pricingConfig = await pricingService.getConfig();
    const price = pricingService.repriceOffer(offer, numericStorage, pricingConfig);
    if (!price.priceAvailable) {
      throw ApiError.conflict('Vast.ai did not report a complete price for this offer. Please choose another.');
    }
    const totalCreditsPerHour = price.totalCreditsPerHour;
    const totalHourlyCost = Math.round(price._internal.totalUsdPerHour * 1e6) / 1e6;

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
          dph_total: price._internal.dphBaseUsd,
          storageCost: price._internal.storageUsdPerHour,
          bandwidthCost: price._internal.bandwidthDownUsdPerGB,
          totalPerHour: totalHourlyCost,
          storageGB: numericStorage,
          computeCreditsPerHour: price.computeCreditsPerHour,
          storageCreditsPerGBMonth: price.storageCreditsPerGBMonth,
          storageCreditsPerHour: price.storageCreditsPerHour,
          totalCreditsPerHour,
          bandwidthDownCreditsPerGB: price.bandwidthDownCreditsPerGB,
          bandwidthUpCreditsPerGB: price.bandwidthUpCreditsPerGB,
          // Older field names, still read by app versions up to v0.2.0.
          creditsPerHour: price.computeCreditsPerHour,
          bandwidthCreditsPerGB: price.bandwidthDownCreditsPerGB,
          creditsPerUsd: price._internal.creditsPerUsd,
          markupPercentage: price._internal.markupPercentage,
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
      const onstartScript = this._generateOnstartScript();
      vastResult = await vastaiService.createInstance(offer.id, {
        label: `${INSTANCE_LABEL_PREFIX}${instance._id}`,
        disk: numericStorage,
        onstart: onstartScript,
        image: env.VASTAI_ENGINE_IMAGE,
        env: {
          AI_STUDIO_MODE: 'cloud',
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
        $set: {
          providerInstanceId: contractId,
          contractConfirmedAt: confirmedAt,
          billedUntil: confirmedAt,
          billingStartedAt: confirmedAt,
        },
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
      // Nothing usable before READY, so a stop before then is refunded in full.
      // TODO: once the app can send work to a rented GPU before every model is
      // ready, charge from the first generation instead of refunding.
      refundIfNeverReady: true,
      message: 'Instance manually terminated by user.',
      emitReason: 'USER_STOPPED',
    });
    return stopped || GpuInstance.findById(instance._id);
  }
}

export const gpuProviderService = new GpuProviderService();
