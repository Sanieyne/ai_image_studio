/**
 * Model Catalog & Selection Service
 * Handles querying model catalogs, user selection management, and recommendation orchestration.
 */

import { ModelCatalog } from '../models/ModelCatalog.js';
import { User } from '../models/User.js';
import { recommendationService } from './recommendation.service.js';
import { ApiError } from '../utils/ApiError.js';

class ModelService {
  /**
   * Retrieve catalog models with optional filtering by mode and text search.
   * @param {Object} query
   * @param {string} [query.mode] - Filter by generation mode
   * @param {string} [query.search] - Search by displayName or modelId
   * @returns {Promise<Array>}
   */
  async getModels({ mode, search } = {}) {
    const filter = { isEnabled: true };

    if (mode) {
      filter.mode = mode.toLowerCase();
    }

    if (search) {
      const searchRegex = new RegExp(search.trim(), 'i');
      filter.$or = [{ displayName: searchRegex }, { modelId: searchRegex }];
    }

    return ModelCatalog.find(filter)
      .sort({ mode: 1, displayName: 1 })
      .lean();
  }

  /**
   * Find a specific model by modelId.
   * @param {string} modelId
   * @returns {Promise<Object>}
   */
  async getModelById(modelId) {
    if (!modelId) {
      throw ApiError.badRequest('Model identifier is required.');
    }

    const model = await ModelCatalog.findOne({
      modelId: modelId.toLowerCase().trim(),
      isEnabled: true,
    }).lean();

    if (!model) {
      throw ApiError.notFound(`Model not found with ID: ${modelId}`);
    }

    return model;
  }

  /**
   * Retrieve user's currently selected models and calculate real-time hardware recommendations.
   * @param {string} userId
   * @returns {Promise<Object>}
   */
  async getUserSelection(userId) {
    const user = await User.findById(userId).lean();
    if (!user) {
      throw ApiError.notFound('User not found.');
    }

    const selectedModels = user.selectedModels || [];
    if (selectedModels.length === 0) {
      return {
        selectedModelIds: [],
        recommendations: null,
      };
    }

    const recommendations = await recommendationService.calculateRequirements(selectedModels);

    return {
      selectedModelIds: selectedModels,
      recommendations,
    };
  }

  /**
   * Update user's selected models after verifying validity through recommendation engine.
   * @param {string} userId
   * @param {string[]} modelIds
   * @returns {Promise<Object>}
   */
  async updateUserSelection(userId, modelIds) {
    if (!Array.isArray(modelIds) || modelIds.length === 0) {
      throw ApiError.badRequest('modelIds must be a non-empty array of model IDs.');
    }

    const sanitizedIds = [...new Set(modelIds.map((id) => id.trim().toLowerCase()))];

    // Verify requirements and ensure all models exist & are enabled
    const recommendations = await recommendationService.calculateRequirements(sanitizedIds);

    const user = await User.findByIdAndUpdate(
      userId,
      { selectedModels: sanitizedIds },
      { new: true, runValidators: true }
    ).lean();

    if (!user) {
      throw ApiError.notFound('User not found.');
    }

    return {
      selectedModelIds: user.selectedModels,
      recommendations,
    };
  }

  /**
   * Remove a model from user's selectedModels list.
   * @param {string} userId
   * @param {string} modelId
   * @returns {Promise<Object>}
   */
  async removeFromSelection(userId, modelId) {
    if (!modelId) {
      throw ApiError.badRequest('Model identifier to remove is required.');
    }

    const targetId = modelId.trim().toLowerCase();
    const user = await User.findById(userId);
    if (!user) {
      throw ApiError.notFound('User not found.');
    }

    const currentSelection = user.selectedModels || [];
    const updatedSelection = currentSelection.filter((id) => id !== targetId);

    if (currentSelection.length === updatedSelection.length) {
      throw ApiError.badRequest(`Model "${targetId}" is not in user's selection.`);
    }

    user.selectedModels = updatedSelection;
    await user.save();

    let recommendations = null;
    if (updatedSelection.length > 0) {
      recommendations = await recommendationService.calculateRequirements(updatedSelection);
    }

    return {
      removedModelId: targetId,
      selectedModelIds: updatedSelection,
      recommendations,
    };
  }
}

export const modelService = new ModelService();
