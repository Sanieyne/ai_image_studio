/**
 * Recommendation & Storage Sizing Engine
 * Computes exact VRAM requirements, disk overhead, recommended storage plans, and compatible GPU hardware tiers.
 */

import mongoose from 'mongoose';
import { ModelCatalog } from '../models/ModelCatalog.js';
import {
  GPU_TIERS,
  STORAGE_PLANS,
  STORAGE_MIN_GB,
  STORAGE_MAX_GB,
  BASE_OVERHEAD_GB,
  OUTPUT_BUFFER_PERCENT,
  EXTRA_FREE_HEADROOM_GB,
} from '../config/constants.js';
import { pricingService } from './pricing.service.js';
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

    // 1. Fetch models from catalog with static fallback for resilience
    let models = [];
    if (mongoose.connection?.readyState === 1) {
      try {
        models = await ModelCatalog.find({
          modelId: { $in: uniqueIds },
          isEnabled: true,
        }).maxTimeMS(2000).lean();
      } catch (e) {
        // Fallback to static catalog if DB query fails
      }
    }

    if (!models || models.length === 0) {
      const STATIC_CATALOG = [
        { modelId: 'qwen-image-2.1', displayName: 'Qwen-Image 2.1', sizeGB: 33, requiredVramGB: 16 },
        { modelId: 'flux-1-kontext-dev', displayName: 'FLUX.1 Kontext [dev]', sizeGB: 24, requiredVramGB: 24 },
        { modelId: 'sdxl-base-1.0', displayName: 'SDXL Base 1.0', sizeGB: 6.9, requiredVramGB: 12 },
        { modelId: 'z-image-turbo', displayName: 'Z-Image Turbo', sizeGB: 6.2, requiredVramGB: 12 },
        { modelId: 'wan-2.1-t2v-1.3b', displayName: 'Wan 2.1 T2V 1.3B', sizeGB: 3.5, requiredVramGB: 12 },
        { modelId: 'wan-2.1-i2v-14b', displayName: 'Wan 2.1 I2V 14B', sizeGB: 28, requiredVramGB: 24 },
        { modelId: 'wan-2.2-animate-14b', displayName: 'Wan 2.2 Animate 14B', sizeGB: 28, requiredVramGB: 24 },
        { modelId: 'minimax-h3', displayName: 'MiniMax-H3 Video+Audio', sizeGB: 33, requiredVramGB: 32 },
        { modelId: 'chatterbox-tts', displayName: 'Chatterbox TTS', sizeGB: 1.2, requiredVramGB: 4 },
        { modelId: 'breeze-tts-2', displayName: 'Breeze TTS 2', sizeGB: 4.8, requiredVramGB: 8 },
        { modelId: 'fashn-vton-1.5', displayName: 'FASHN VTON 1.5', sizeGB: 8.5, requiredVramGB: 16 },
        { modelId: 'real-esrgan-x4plus', displayName: 'Real-ESRGAN 4x+', sizeGB: 2.1, requiredVramGB: 6 },
      ];
      models = STATIC_CATALOG.filter((m) => uniqueIds.includes(m.modelId));
    }

    if (models.length === 0) {
      // Default to standard base model
      models = [{ modelId: 'sdxl-base-1.0', displayName: 'SDXL Base 1.0', sizeGB: 6.9, requiredVramGB: 12 }];
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

    // 5. Total disk requirement (Weights + 25GB OS/CUDA/Python + 35% Buffer + 25GB Free Headroom)
    const totalWithBufferGB =
      Math.round((totalModelSizeGB + BASE_OVERHEAD_GB + bufferGB + EXTRA_FREE_HEADROOM_GB) * 100) / 100;

    // 6. Continuous storage allocation (clamped to 80GB min - 1000GB max)
    const continuousStorageGB = Math.max(
      80,
      Math.min(STORAGE_MAX_GB, Math.ceil(totalWithBufferGB))
    );
    const storagePricing = pricingService.calculateStoragePricing(continuousStorageGB);
    const recommendedStorage = {
      id: `${continuousStorageGB}gb`,
      name: `${continuousStorageGB}GB Volume`,
      sizeGB: continuousStorageGB,
      storageGB: continuousStorageGB,
      fits: continuousStorageGB >= totalWithBufferGB,
      freeAfterGB: Math.max(0, Math.round((continuousStorageGB - totalWithBufferGB) * 100) / 100),
      creditsPerHour: storagePricing.creditsPerHour,
      creditsPerMonth: storagePricing.creditsPerMonth,
    };
    const allPlans = STORAGE_PLANS.map((plan) => pricingService.formatStoragePricing(plan));

    // 7. Compatible GPUs filtered by maxVramGB requirement and formatted with server credits
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

        const tierWithCredits = pricingService.formatTierPricing(gpu);

        return {
          ...tierWithCredits,
          canRun: true,
          headroomVramGB: headroom,
          fit,
          reason,
        };
      })
      .sort((a, b) => a.creditsPerHour - b.creditsPerHour);

    // 8. Generate intelligent warnings
    const warnings = [];

    if (totalWithBufferGB > STORAGE_MAX_GB) {
      warnings.push(
        `Selected models require ${totalWithBufferGB}GB storage which exceeds the maximum supported storage volume (${STORAGE_MAX_GB}GB). Please reduce model selection.`
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
      allPlans,
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
      gpuTiers: GPU_TIERS.map((gpu) => pricingService.formatTierPricing(gpu)),
      models: mappedModels,
    };
  }
}

export const recommendationService = new RecommendationService();
