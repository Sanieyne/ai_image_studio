import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { gpuProviderService } from '../src/services/gpuProvider.service.js';
import { vastaiService } from '../src/services/vastai.service.js';
import { recommendationService } from '../src/services/recommendation.service.js';

describe('download time estimates', () => {
  const originals = {};
  beforeEach(() => {
    originals.search = vastaiService.searchOffers;
    originals.req = recommendationService.calculateRequirements;
    // A cached offer normalized for another selection (15 GB default).
    vastaiService.searchOffers = async () => [
      vastaiService.normalizeOffer({
        id: 1, gpu_name: 'RTX 4060 Ti', gpu_ram: 16000, inet_down: 800, compute_cap: 890, cuda_max_good: 13,
        direct_port_count: 9, dph_base: 0.16, storage_cost: 0.2, inet_down_cost: 0.004, inet_up_cost: 0.004,
      }, 15),
    ];
    recommendationService.calculateRequirements = async () => ({
      requirements: { maxVramGB: 6, totalWithBufferGB: 9, totalModelSizeGB: 6 },
    });
  });
  afterEach(() => {
    vastaiService.searchOffers = originals.search;
    recommendationService.calculateRequirements = originals.req;
  });

  test('use the selected models\' size for every request, even from a cached offer', async () => {
    const { offers } = await gpuProviderService.searchAvailableGPUs({ selectedModelIds: ['realesrgan-x4plus'] });
    // 6 GB x 8000 Mbit/GB / 800 Mbps / 60 = 1.0 min
    assert.equal(offers[0].estimatedDownloadTimeMinutes, 1);
    assert.equal(offers[0].downloadSizeGB, 6);
  });

  test('are unknown (null) when no model is selected', async () => {
    const { offers } = await gpuProviderService.searchAvailableGPUs({ selectedModelIds: [] });
    assert.equal(offers[0].estimatedDownloadTimeMinutes, null);
  });
});
