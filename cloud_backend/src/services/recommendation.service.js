/**
 * Recommendation & Storage Sizing Engine
 * Computes exact VRAM requirements, disk overhead, recommended storage plans, and compatible GPU hardware tiers.
 */

import { ModelCatalog } from '../models/ModelCatalog.js';
import {
  GPU_TIERS,
  STORAGE_PLANS,
  BASE_OVERHEAD_GB,
  OUTPUT_BUFFER_PERCENT,
} from '../config/constants.js';
import { ApiError } from '../utils/ApiError.js';

class RecommendationService {
  /**
   * Calculate VRAM, storage footprint, warnings, and compatible GPUs for a set of selected models.
   * @param {string[]} modelIds - Array of model unique identifiers
   * @returns {Promise<Object>} Detailed requirements and hardware recommendations
   */
  async calculateRequirements(modelIds) {
    if (!Array.isArray(modelIds) || modelIds.length === 0) {
      throw ApiError.badRequest('At least one model must be selected to calculate requirements.');
    }

    // Deduplicate IDs
    const uniqueIds = [...new Set(modelIds.map((id) => id.trim().toLowerCase()))];

    // 1. Fetch models from catalog
    const models = await ModelCatalog.find({
      modelId: { $in: uniqueIds },
      isEnabled: true,
    }).lean();

    if (models.length !== uniqueIds.length) {
      const foundIds = new Set(models.map((m) => m.modelId));
      const missingIds = uniqueIds.filter((id) => !foundIds.has(id));
      throw ApiError.notFound(
        `One or more requested models are invalid or disabled: ${missingIds.join(', ')}`
      );
    }

    // 2. Sum model weights
    const totalModelSizeGB =
      Math.round(models.reduce((sum, m) => sum + m.sizeGB, 0) * 100) / 100;

    // 3. Max and Min VRAM
    const maxVramGB = Math.max(...models.map((m) => m.requiredVramGB));
    const minVramGB = Math.min(...models.map((m) => m.requiredVramGB));

    // 4. Output buffer (30% for generated media)
    const bufferGB =
      Math.round(totalModelSizeGB * OUTPUT_BUFFER_PERCENT * 100) / 100;

    // 5. Total disk requirement (Weights + 7GB OS/Python/Diffusers + 30% Output Buffer)
    const totalWithBufferGB =
      Math.round((totalModelSizeGB + BASE_OVERHEAD_GB + bufferGB) * 100) / 100;

    // 6. Find optimal storage plan
    const recommendedStorage =
      STORAGE_PLANS.find((plan) => plan.sizeGB >= totalWithBufferGB) ||
      STORAGE_PLANS[STORAGE_PLANS.length - 1];

    // 7. Compatible GPUs filtered by maxVramGB requirement
    const compatibleGPUs = GPU_TIERS.filter((gpu) => gpu.vramGB >= maxVramGB)
      .map((gpu) => {
        const headroom = gpu.vramGB - maxVramGB;
        let fit = 'minimum';
        let reason = `Minimum requirement satisfied for ${maxVramGB}GB model VRAM.`;

        if (headroom >= 8) {
          fit = 'optimal';
          reason = `Optimal performance with ${headroom}GB VRAM headroom for native 2K resolution & high-batch generation.`;
        } else if (headroom >= 2) {
          fit = 'tight';
          reason = `Balanced fit with ${headroom}GB VRAM headroom. Ideal for standard single-inference runs.`;
        }

        return {
          ...gpu,
          canRun: true,
          headroomVramGB: headroom,
          fit,
          reason,
        };
      })
      .sort((a, b) => a.pricePerHour - b.pricePerHour);

    // 8. Generate intelligent warnings
    const warnings = [];

    if (totalWithBufferGB > 30 && models.length > 2) {
      warnings.push(
        `Starter 30GB storage is insufficient (requires ${totalWithBufferGB}GB). Please upgrade your storage volume or delete unused models.`
      );
    }

    if (models.some((m) => m.sizeGB > 25)) {
      warnings.push(
        'Large AI models (>25GB weights) detected. We recommend high-throughput instances (e.g. RTX 4090 or A100) for faster initial download and loading.'
      );
    }

    if (compatibleGPUs.length === 0) {
      warnings.push(
        `Current model selection requires at least ${maxVramGB}GB VRAM. No standard single-GPU tier available. Contact enterprise support.`
      );
    }

    return {
      selectedModels: models.map((m) => ({
        modelId: m.modelId,
        displayName: m.displayName,
        mode: m.mode,
        sizeGB: m.sizeGB,
        requiredVramGB: m.requiredVramGB,
      })),
      requirements: {
        modelCount: models.length,
        totalModelSizeGB,
        baseOverheadGB: BASE_OVERHEAD_GB,
        bufferGB,
        totalWithBufferGB,
        maxVramGB,
        minVramGB,
      },
      recommendedStorage: {
        ...recommendedStorage,
        freeAfterGB:
          Math.max(
            0,
            Math.round((recommendedStorage.sizeGB - totalWithBufferGB) * 100) / 100
          ),
        fits: recommendedStorage.sizeGB >= totalWithBufferGB,
      },
      compatibleGPUs,
      warnings,
      allPlans: STORAGE_PLANS,
    };
  }

  /**
   * Returns compatibility matrix of all catalog models mapped to compatible GPU hardware tiers.
   * @returns {Promise<Object>}
   */
  async getCompatibilityMatrix() {
    const models = await ModelCatalog.find({ isEnabled: true }).sort({ mode: 1, displayName: 1 }).lean();

    const mappedModels = models.map((m) => ({
      modelId: m.modelId,
      displayName: m.displayName,
      mode: m.mode,
      sizeGB: m.sizeGB,
      requiredVramGB: m.requiredVramGB,
      compatibleGPUs: GPU_TIERS.filter((gpu) => gpu.vramGB >= m.requiredVramGB).map(
        (gpu) => gpu.id
      ),
    }));

    return {
      gpuTiers: GPU_TIERS,
      models: mappedModels,
    };
  }
}

export const recommendationService = new RecommendationService();
