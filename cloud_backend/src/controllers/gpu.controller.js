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

  const modelIdsList = selectedModelIds
    ? (Array.isArray(selectedModelIds) ? selectedModelIds : selectedModelIds.split(',').map((s) => s.trim()))
    : [];

  const result = await gpuProviderService.searchAvailableGPUs({
    selectedModelIds: modelIdsList,
    minVramGB: minVramGB ? Number(minVramGB) : 0,
    maxPricePerHour: maxPrice ? Number(maxPrice) : undefined,
    minInetDown: minInetDown ? Number(minInetDown) : 50,
    gpuName: gpuName || undefined,
    verifiedOnly: verified === 'false' ? false : true,
    limit: limit ? Math.min(100, Math.max(1, parseInt(limit, 10))) : 30,
    orderBy: orderBy || 'price',
  });

  res.status(200).json({
    success: true,
    count: result.count,
    data: result,
  });
});

/**
 * GET /api/v1/gpu/offers/:offerId
 * Fetch complete details for a specific Vast.ai offer.
 */
export const getOfferById = asyncHandler(async (req, res) => {
  const { offerId } = req.params;
  const offer = await vastaiService.getOffer(offerId);

  res.status(200).json({
    success: true,
    data: offer,
  });
});

/**
 * GET /api/v1/gpu/recommended
 * Return curated rankings (cheapest, fastest, most reliable, balanced) for selected models.
 */
export const getRecommended = asyncHandler(async (req, res) => {
  const { modelIds } = req.query;
  const modelIdsList = modelIds
    ? (Array.isArray(modelIds) ? modelIds : modelIds.split(',').map((s) => s.trim()))
    : ['sdxl-base-1.0'];

  const recommendations = await gpuProviderService.getRecommendedGPUsForSelection(modelIdsList);

  res.status(200).json({
    success: true,
    data: recommendations,
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

  const instance = await gpuProviderService.rentGPU({
    userId: req.user._id,
    offerId,
    storageGB: Number(storageGB) || 100,
    selectedModelIds,
  });

  res.status(201).json({
    success: true,
    message: `GPU instance launch initiated for ${instance.gpuType}.`,
    data: instance,
  });
});

/**
 * GET /api/v1/gpu/instances/me
 * Fetch authenticated user's active cloud GPU instances with live burn rates.
 */
export const getMyInstances = asyncHandler(async (req, res) => {
  const instances = await gpuProviderService.getUserInstances(req.user._id);

  const enriched = instances.map((instance) => ({
    ...instance,
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
      ...instance,
      liveMetrics,
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
    data: instance,
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

  const offer = await vastaiService.getOffer(offerId);
  const estimate = gpuProviderService.estimateCost({
    offer,
    storageGB: Number(storageGB),
    hours: Number(hours),
    bandwidthGB: Number(bandwidthGB),
  });

  res.status(200).json({
    success: true,
    data: estimate,
  });
});
