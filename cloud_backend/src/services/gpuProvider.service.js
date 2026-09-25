/**
 * GPU Provider Orchestration Service
 * Merges Vast.ai real-time marketplace availability with model sizing requirements,
 * calculates hardware fit scores, and manages user cloud instance deployments.
 */

import { vastaiService } from './vastai.service.js';
import { recommendationService } from './recommendation.service.js';
import { creditService } from './credit.service.js';
import { pricingService } from './pricing.service.js';
import { GpuInstance } from '../models/GpuInstance.js';
import { GPU_STATUS, GPU_PROVIDERS, BANDWIDTH_COST_PER_GB } from '../config/constants.js';
import { ApiError } from '../utils/ApiError.js';

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
      minInetDown = 50,
      gpuName,
      verifiedOnly = true,
      limit = 30,
      orderBy = 'price',
    } = options;

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

    // 2. Fetch live marketplace offers from Vast.ai
    const rawOffers = await vastaiService.searchOffers({
      minVramGB: requiredVram,
      minDiskGB: requiredDisk,
      minInetDown,
      gpuName,
      verifiedOnly,
      limit: limit * 2, // Fetch slightly more for client-side filtering
      totalModelSizeGB,
    });

    // 3. Filter by maxPricePerHour if set
    let filteredOffers = rawOffers;
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
      return a.totalHourlyCost - b.totalHourlyCost;
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
        minInetDown,
      },
    };
  }

  /**
   * Return specialized recommendations (cheapest, fastest, most reliable, balanced)
   * @param {string[]} modelIds
   * @returns {Promise<Object>}
   */
  async getRecommendedGPUsForSelection(modelIds = []) {
    const searchResult = await this.searchAvailableGPUs({
      selectedModelIds: modelIds,
      limit: 50,
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

    const computeCost = Math.round(offer.pricePerHour * hours * 1000) / 1000;
    const storageRatePerHour = (offer.storageCostPerHour / (offer.diskGB || 100)) * storageGB;
    const storageCost = Math.round(storageRatePerHour * hours * 1000) / 1000;
    const bandwidthCost = Math.round(bandwidthGB * (offer.bandwidthCostPerGB || BANDWIDTH_COST_PER_GB) * 1000) / 1000;
    const totalCost = Math.round((computeCost + storageCost + bandwidthCost) * 1000) / 1000;
    const costPerHour = Math.round((offer.pricePerHour + storageRatePerHour) * 1000) / 1000;

    // Server-computed authoritative credit values
    const computeCredits = pricingService.usdToCredits(computeCost, 1);
    const storageCredits = pricingService.usdToCredits(storageCost, 2);
    const bandwidthCredits = pricingService.usdToCredits(bandwidthCost, 2);
    const totalCredits = pricingService.usdToCredits(totalCost, 1);
    const creditsPerHour = pricingService.usdToCredits(costPerHour, 1);

    return {
      offerId: offer.id,
      gpuName: offer.gpuName,
      hours,
      storageGB,
      bandwidthGB,
      breakdown: {
        computeCost,
        storageCost,
        bandwidthCost,
        computeCredits,
        storageCredits,
        bandwidthCredits,
      },
      totalCost,
      costPerHour,
      totalCredits,
      creditsPerHour,
      creditsPerUsd: pricingService.getCachedConfig().tokenValue,
      markupPercentage: pricingService.getCachedConfig().markupPercentage,
    };
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

    // 1. Fetch offer details
    const offer = await vastaiService.getOffer(offerId);

    // 2. Compute minimum initial funding required in CREDITS (at least 1 hour total cost or minLaunchCredits)
    const minLaunch = pricingService.getCachedConfig().minLaunchCredits || 10;
    const initialCreditsRequired = Math.max(
      minLaunch,
      offer.totalCreditsPerHour ?? pricingService.usdToCredits(offer.totalHourlyCost, 1)
    );
    const hasSufficientCredits = await creditService.hasEnough(userId, initialCreditsRequired);

    if (!hasSufficientCredits) {
      throw ApiError.paymentRequired(
        `Insufficient credit balance. You need at least ${initialCreditsRequired} credits to launch this ${offer.gpuName} instance.`
      );
    }

    // 3. Create GpuInstance document in provisioning state
    const instance = await GpuInstance.create({
      user: userId,
      provider: GPU_PROVIDERS.VASTAI,
      providerInstanceId: `pending-${Date.now()}`,
      status: GPU_STATUS.PROVISIONING,
      gpuType: offer.gpuName,
      vramGB: offer.vramGB,
      costPerHour: offer.totalHourlyCost,
      modelsRequested: selectedModelIds,
      vastOffer: offer,
      pricing: {
        dph_total: offer.pricePerHour,
        storageCost: offer.storageCostPerHour,
        bandwidthCost: offer.bandwidthCostPerGB,
        totalPerHour: offer.totalHourlyCost,
        creditsPerHour: offer.creditsPerHour,
        totalCreditsPerHour: offer.totalCreditsPerHour,
        storageCreditsPerHour: offer.storageCreditsPerHour,
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
        diskGB: storageGB,
      },
      provisioningLogs: [
        { message: `Requested provisioning on Vast.ai for ${offer.gpuName} (${offer.id})` },
      ],
      startedAt: new Date(),
    });

    // 4. Trigger Vast.ai instance creation
    try {
      const vastResult = await vastaiService.createInstance(offerId, {
        disk: storageGB,
        env: {
          AI_STUDIO_USER_ID: String(userId),
          AI_STUDIO_INSTANCE_ID: String(instance._id),
          AI_STUDIO_SELECTED_MODELS: selectedModelIds.join(','),
        },
      });

      instance.providerInstanceId = String(vastResult.new_contract || vastResult.instanceId);
      instance.provisioningLogs.push({
        message: `Vast.ai contract established: #${instance.providerInstanceId}`,
      });
      await instance.save();

      return instance;
    } catch (error) {
      instance.status = GPU_STATUS.FAILED;
      instance.provisioningLogs.push({
        message: `Provisioning failed: ${error.message}`,
        level: 'error',
      });
      await instance.save();
      throw error;
    }
  }

  /**
   * Get active GPU instances for authenticated user
   * @param {string} userId
   * @returns {Promise<Array>}
   */
  async getUserInstances(userId) {
    return GpuInstance.find({
      user: userId,
      status: { $in: [GPU_STATUS.PROVISIONING, GPU_STATUS.READY, GPU_STATUS.RUNNING] },
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

    if (instance.status === GPU_STATUS.STOPPED) {
      return instance;
    }

    if (instance.providerInstanceId && !instance.providerInstanceId.startsWith('pending-')) {
      await vastaiService.destroyInstance(instance.providerInstanceId);
    }

    instance.status = GPU_STATUS.STOPPED;
    instance.stoppedAt = new Date();
    instance.provisioningLogs.push({ message: 'Instance manually terminated by user.' });
    await instance.save();

    return instance;
  }
}

export const gpuProviderService = new GpuProviderService();
