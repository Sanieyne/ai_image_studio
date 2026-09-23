/**
 * Model Catalog & Recommendation Controller
 * Endpoints for querying catalog, calculating GPU/Storage requirements, and managing user model selections.
 */

import { asyncHandler } from '../utils/asyncHandler.js';
import { modelService } from '../services/model.service.js';
import { recommendationService } from '../services/recommendation.service.js';
import { ApiError } from '../utils/ApiError.js';

/**
 * GET /api/v1/models
 * Query catalog models with optional filtering by mode and text search.
 */
export const getModels = asyncHandler(async (req, res) => {
  const { mode, search } = req.query;
  const models = await modelService.getModels({ mode, search });

  res.status(200).json({
    success: true,
    count: models.length,
    data: models,
  });
});

/**
 * GET /api/v1/models/compatibility/matrix
 * Returns hardware compatibility mapping across GPU tiers and catalog models.
 */
export const getCompatibilityMatrix = asyncHandler(async (req, res) => {
  const matrix = await recommendationService.getCompatibilityMatrix();

  res.status(200).json({
    success: true,
    data: matrix,
  });
});

/**
 * GET /api/v1/models/user/selection
 * Retrieve authenticated user's selected models and calculated requirements.
 */
export const getUserSelection = asyncHandler(async (req, res) => {
  const result = await modelService.getUserSelection(req.user._id);

  res.status(200).json({
    success: true,
    data: result,
  });
});

/**
 * PUT /api/v1/models/user/selection
 * Save updated model selection for authenticated user.
 */
export const updateUserSelection = asyncHandler(async (req, res) => {
  const { modelIds } = req.body;
  if (!modelIds || !Array.isArray(modelIds) || modelIds.length === 0) {
    throw ApiError.badRequest('modelIds array is required and must not be empty.');
  }

  const result = await modelService.updateUserSelection(req.user._id, modelIds);

  res.status(200).json({
    success: true,
    message: 'User model selection updated successfully.',
    data: result,
  });
});

/**
 * POST /api/v1/models/recommend
 * Calculate GPU & storage recommendations for an arbitrary list of model IDs.
 */
export const recommend = asyncHandler(async (req, res) => {
  const { modelIds } = req.body;
  if (!modelIds || !Array.isArray(modelIds) || modelIds.length === 0) {
    throw ApiError.badRequest('modelIds array is required.');
  }

  const result = await recommendationService.calculateRequirements(modelIds);

  res.status(200).json({
    success: true,
    data: result,
  });
});

/**
 * POST /api/v1/models/storage/estimate
 * Lightweight endpoint to estimate storage footprint and recommended volume plan.
 */
export const estimateStorage = asyncHandler(async (req, res) => {
  const { modelIds } = req.body;
  if (!modelIds || !Array.isArray(modelIds) || modelIds.length === 0) {
    throw ApiError.badRequest('modelIds array is required.');
  }

  const result = await recommendationService.calculateRequirements(modelIds);

  res.status(200).json({
    success: true,
    data: {
      requirements: result.requirements,
      recommendedStorage: result.recommendedStorage,
      warnings: result.warnings,
    },
  });
});

/**
 * DELETE /api/v1/models/cache/:modelId
 * Remove a model from user's selection (simulating volume cache eviction).
 */
export const removeFromSelection = asyncHandler(async (req, res) => {
  const { modelId } = req.params;
  const result = await modelService.removeFromSelection(req.user._id, modelId);

  res.status(200).json({
    success: true,
    message: `Model "${modelId}" removed from selection.`,
    data: result,
  });
});

/**
 * GET /api/v1/models/:modelId
 * Retrieve single model metadata.
 */
export const getModelById = asyncHandler(async (req, res) => {
  const { modelId } = req.params;
  const model = await modelService.getModelById(modelId);

  res.status(200).json({
    success: true,
    data: model,
  });
});
