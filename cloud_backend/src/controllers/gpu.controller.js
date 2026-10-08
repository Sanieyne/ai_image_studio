/**
 * GPU Marketplace & Cloud Instance Controller
 * Handles Vast.ai offer searching, hardware recommendation, instance rental, and live pricing metrics.
 */

import { asyncHandler } from '../utils/asyncHandler.js';
import { gpuProviderService } from '../services/gpuProvider.service.js';
import { vastaiService } from '../services/vastai.service.js';
import { priceTrackerService } from '../services/priceTracker.service.js';
import { GpuInstance } from '../models/GpuInstance.js';
import { ApiError } from '../utils/ApiError.js';
import { env } from '../config/env.js';
import {
  STORAGE_MIN_GB,
  STORAGE_MAX_GB,
  VASTAI_GPU_NAME_MAP,
  MIN_INET_DOWN_FLOOR_MBPS,
} from '../config/constants.js';
import { sanitizeOfferForClient, sanitizeInstanceForClient } from '../utils/sanitize.js';
import { pricingService, DEFAULT_STORAGE_GB } from '../services/pricing.service.js';

/**
 * Storage size (GB) offer prices are computed for. Optional; defaults to
 * DEFAULT_STORAGE_GB, which is also what app versions up to v0.2.0 get.
 */
function parseStorageGB(value) {
  if (value === undefined || value === null || value === '') return DEFAULT_STORAGE_GB;
  const n = Number(value);
  if (!Number.isInteger(n) || n < STORAGE_MIN_GB || n > STORAGE_MAX_GB) {
    throw ApiError.badRequest(`storageGB must be an integer between ${STORAGE_MIN_GB} and ${STORAGE_MAX_GB} GB.`);
  }
  return n;
}

/**
 * GET /api/v1/gpu/offers
 * Search live Vast.ai marketplace offers tailored to VRAM and disk requirements.
 */
export const getOffers = asyncHandler(async (req, res) => {
  const {
    minVramGB,
    maxPrice,
    minInetDown,
    gpuName,
    verified,
    limit,
    selectedModelIds,
    orderBy,
  } = req.query;
  const storageGB = parseStorageGB(req.query.storageGB);

  const modelIdsList = selectedModelIds
    ? (Array.isArray(selectedModelIds) ? selectedModelIds : selectedModelIds.split(',').map((s) => s.trim()).filter(Boolean))
    : [];

  const result = await gpuProviderService.searchAvailableGPUs({
    selectedModelIds: modelIdsList,
    minVramGB: minVramGB ? Number(minVramGB) : 0,
    maxPricePerHour: maxPrice ? Number(maxPrice) : undefined,
    minInetDown: minInetDown ? Math.max(MIN_INET_DOWN_FLOOR_MBPS, Number(minInetDown)) : MIN_INET_DOWN_FLOOR_MBPS,
    gpuName: gpuName || undefined,
    verifiedOnly: verified === 'false' ? false : true,
    limit: limit ? Math.min(500, Math.max(1, parseInt(limit, 10))) : 250,
    orderBy: orderBy || 'price',
    storageGB,
  });

  const sanitizedOffers = (result.offers || []).map(sanitizeOfferForClient);

  res.status(200).json({
    success: true,
    count: sanitizedOffers.length,
    data: {
      ...result,
      offers: sanitizedOffers,
    },
  });
});

/**
 * GET /api/v1/gpu/offers/:offerId
 * Fetch complete details for a specific Vast.ai offer.
 */
export const getOfferById = asyncHandler(async (req, res) => {
  const { offerId } = req.params;
  const storageGB = parseStorageGB(req.query.storageGB);
  const offer = pricingService.repriceOffer(await vastaiService.getOffer(offerId), storageGB, await pricingService.getConfig());

  res.status(200).json({
    success: true,
    data: sanitizeOfferForClient(offer),
  });
});

/**
 * GET /api/v1/gpu/recommended
 * Return curated rankings (cheapest, fastest, most reliable, balanced) for selected models.
 */
export const getRecommended = asyncHandler(async (req, res) => {
  const { modelIds, limit } = req.query;
  const modelIdsList = modelIds != null
    ? (Array.isArray(modelIds)
        ? modelIds
        : modelIds.split(',').map((s) => s.trim()).filter(Boolean))
    : [];

  const effectiveLimit = limit ? Math.min(500, Math.max(1, parseInt(limit, 10))) : 250;
  const storageGB = parseStorageGB(req.query.storageGB);
  const recommendations = await gpuProviderService.getRecommendedGPUsForSelection(modelIdsList, effectiveLimit, storageGB);

  const sanitized = {
    requirements: recommendations.requirements,
    cheapestOffer: sanitizeOfferForClient(recommendations.cheapestOffer),
    fastestOffer: sanitizeOfferForClient(recommendations.fastestOffer),
    mostReliableOffer: sanitizeOfferForClient(recommendations.mostReliableOffer),
    balancedOffer: sanitizeOfferForClient(recommendations.balancedOffer),
    allOffers: (recommendations.allOffers || []).map(sanitizeOfferForClient),
  };

  res.status(200).json({
    success: true,
    data: sanitized,
  });
});

/**
 * POST /api/v1/gpu/rent
 * Rent a GPU instance via Vast.ai and register for billing tracking.
 */
export const rent = asyncHandler(async (req, res) => {
  const { offerId, storageGB = 100, selectedModelIds = [] } = req.body;

  if (!offerId) {
    throw ApiError.badRequest('offerId is required.');
  }

  const numericStorage = Number(storageGB);
  if (isNaN(numericStorage) || !Number.isInteger(numericStorage) || numericStorage < STORAGE_MIN_GB || numericStorage > STORAGE_MAX_GB) {
    throw ApiError.badRequest(`storageGB must be an integer between ${STORAGE_MIN_GB} and ${STORAGE_MAX_GB} GB.`);
  }

  const instance = await gpuProviderService.rentGPU({
    userId: req.user._id,
    offerId,
    storageGB: numericStorage,
    selectedModelIds,
  });

  res.status(201).json({
    success: true,
    message: `GPU instance launch initiated for ${instance.gpuType}.`,
    data: sanitizeInstanceForClient(instance),
  });
});

/**
 * GET /api/v1/gpu/instances/me
 * Fetch authenticated user's active cloud GPU instances with live burn rates.
 */
export const getMyInstances = asyncHandler(async (req, res) => {
  const instances = await gpuProviderService.getUserInstances(req.user._id);

  const enriched = instances.map((instance) => ({
    ...instanceProgressView(instance),
    burnRate: priceTrackerService.calculateBurnRate(instance),
  }));

  res.status(200).json({
    success: true,
    count: enriched.length,
    data: enriched,
  });
});

/**
 * GET /api/v1/gpu/instances/:instanceId
 * Fetch instance status with real-time credit consumption metrics.
 */
export const getInstanceById = asyncHandler(async (req, res) => {
  const { instanceId } = req.params;
  const instance = await GpuInstance.findOne({ _id: instanceId, user: req.user._id }).lean();

  if (!instance) {
    throw ApiError.notFound('GPU instance not found.');
  }

  const liveMetrics = await priceTrackerService.trackPriceEat(instanceId);
  res.status(200).json({
    success: true,
    data: {
      ...instanceProgressView(instance),
      liveMetrics,
    },
  });
});

/**
 * An instance as the provisioning screen needs it: current progress, the last
 * 20 log lines, elapsed time and credits charged / refunded so far.
 */
export function instanceProgressView(instance, now = new Date()) {
  const view = sanitizeInstanceForClient(instance);
  const logs = instance.provisioningLogs || [];
  const startedAt = instance.contractConfirmedAt || instance.startedAt || instance.createdAt;
  const endedAt = instance.stoppedAt ? new Date(instance.stoppedAt) : now;
  view.provisioningLogs = logs.slice(-20).map((l) => ({ timestamp: l.timestamp, level: l.level, message: l.message }));
  view.progress = instance.progress
    ? {
        stage: instance.progress.stage,
        message: instance.progress.message,
        vastStatus: instance.progress.vastStatus,
        vastStatusMessage: instance.progress.vastStatusMessage,
        portFound: Boolean(instance.progress.portFound),
        engineReachable: Boolean(instance.progress.engineReachable),
        failureReason: instance.progress.failureReason || null,
        models: instance.progress.models || [],
        updatedAt: instance.progress.updatedAt,
      }
    : null;
  view.elapsedSeconds = startedAt ? Math.max(0, Math.round((endedAt - new Date(startedAt)) / 1000)) : 0;
  view.billing = {
    creditsCharged: instance.creditsCharged || 0,
    creditsRefunded: instance.creditsRefunded || 0,
    creditsPerHour: instance.pricing?.totalCreditsPerHour ?? null,
    stopReason: instance.stopReason || null,
  };
  // Internal fields the app has no use for.
  delete view.pendingStopReason;
  delete view.holdsSlot;
  delete view.vastMissCount;
  delete view.firstMissAt;
  return view;
}

/**
 * GET /api/v1/gpu/rentals/status
 * Whether new rentals are open. The app keeps the marketplace browsable either way.
 */
export const getRentalsStatus = asyncHandler(async (req, res) => {
  res.status(200).json({
    success: true,
    data: {
      rentalsEnabled: env.GPU_RENTALS_ENABLED,
      message: env.GPU_RENTALS_ENABLED ? null : env.GPU_RENTALS_PAUSED_MESSAGE,
    },
  });
});

/**
 * DELETE /api/v1/gpu/instances/:instanceId
 * Terminate active cloud GPU instance and stop billing.
 */
export const destroyInstance = asyncHandler(async (req, res) => {
  const { instanceId } = req.params;
  const instance = await gpuProviderService.terminateInstance(req.user._id, instanceId);

  res.status(200).json({
    success: true,
    message: `GPU instance (${instance.gpuType}) stopped successfully.`,
    data: sanitizeInstanceForClient(instance),
  });
});

/**
 * GET /api/v1/gpu/pricing/estimate
 * Calculate projected costs for arbitrary hours, storage size, and bandwidth.
 */
export const estimatePricing = asyncHandler(async (req, res) => {
  const { offerId, storageGB = 100, hours = 1, bandwidthGB = 10 } = req.query;

  if (!offerId) {
    throw ApiError.badRequest('offerId query param is required.');
  }

  const numericStorage = Number(storageGB);
  if (isNaN(numericStorage) || !Number.isInteger(numericStorage) || numericStorage < STORAGE_MIN_GB || numericStorage > STORAGE_MAX_GB) {
    throw ApiError.badRequest(`storageGB must be an integer between ${STORAGE_MIN_GB} and ${STORAGE_MAX_GB} GB.`);
  }

  const offer = await vastaiService.getOffer(offerId);
  await pricingService.getConfig();
  const estimate = gpuProviderService.estimateCost({
    offer,
    storageGB: numericStorage,
    hours: Number(hours),
    bandwidthGB: Number(bandwidthGB),
  });

  res.status(200).json({
    success: true,
    data: estimate,
  });
});

/**
 * GET /api/v1/gpu/series
 * Expose series groupings derived from VASTAI_GPU_NAME_MAP for client categorization.
 */
export const getGpuSeries = asyncHandler(async (req, res) => {
  const seriesGroups = {
    'RTX 30-Series': [],
    'RTX 40-Series': [],
    'RTX 50-Series': [],
    'Datacenter': [],
  };

  for (const [canonical, aliases] of Object.entries(VASTAI_GPU_NAME_MAP)) {
    if (canonical.includes('A100') || canonical.includes('H100') || canonical.includes('Datacenter')) {
      seriesGroups['Datacenter'].push(...aliases);
    } else if (canonical.includes('30')) {
      seriesGroups['RTX 30-Series'].push(...aliases);
    } else if (canonical.includes('40')) {
      seriesGroups['RTX 40-Series'].push(...aliases);
    } else if (canonical.includes('50')) {
      seriesGroups['RTX 50-Series'].push(...aliases);
    } else {
      seriesGroups['Datacenter'].push(...aliases);
    }
  }

  // Deduplicate
  for (const key of Object.keys(seriesGroups)) {
    seriesGroups[key] = Array.from(new Set(seriesGroups[key]));
  }

  res.status(200).json({
    success: true,
    data: seriesGroups,
  });
});
