/**
 * Vast.ai GPU Marketplace API Client
 * Interfaces directly with Vast.ai REST API for querying real-time GPU bundles, renting instances, and managing lifecycle.
 */

import axios from 'axios';
import { env } from '../config/env.js';
import { BANDWIDTH_COST_PER_GB, VASTAI_OFFERS_CACHE_TTL_MS } from '../config/constants.js';
import { ApiError } from '../utils/ApiError.js';

class VastaiService {
  constructor() {
    this.client = axios.create({
      baseURL: env.VASTAI_API_BASE || 'https://console.vast.ai/api/v0',
      timeout: 15000,
      headers: {
        'Content-Type': 'application/json',
        ...(env.VASTAI_API_KEY ? { Authorization: `Bearer ${env.VASTAI_API_KEY}` } : {}),
      },
    });

    // In-memory cache to prevent rate-limiting: Map<string, { timestamp: number, data: any }>
    this._cache = new Map();
  }

  /**
   * Helper to perform HTTP calls with exponential backoff on 429 rate-limiting.
   */
  async _requestWithRetry(fn, retries = 2, delayMs = 1000) {
    try {
      return await fn();
    } catch (error) {
      if (retries > 0 && (error.response?.status === 429 || error.code === 'ECONNABORTED')) {
        console.warn(`[Vast.ai] Rate limited (429) or timed out. Backing off ${delayMs}ms...`);
        await new Promise((resolve) => setTimeout(resolve, delayMs));
        return this._requestWithRetry(fn, retries - 1, delayMs * 2);
      }
      throw error;
    }
  }

  /**
   * Normalize raw Vast.ai offer payload into standardized camelCase format
   * @param {Object} raw - Raw Vast.ai bundle JSON
   * @param {number} totalModelSizeGB - Estimated disk footprint for download speed calculation
   * @returns {Object}
   */
  normalizeOffer(raw, totalModelSizeGB = 15) {
    const id = raw.id ?? raw.ask_contract_id ?? raw.bundleId;
    const vramGB = Math.round(((raw.gpu_ram || 24000) / 1000) * 10) / 10;
    const ramGB = Math.round(((raw.cpu_ram || 32000) / 1000) * 10) / 10;
    const diskGB = Math.round(raw.disk_space || 100);
    const dphTotal = Math.round((raw.dph_total || 0.44) * 1000) / 1000;
    const dphBase = Math.round((raw.dph_base || dphTotal) * 1000) / 1000;
    const storageCostPerHour = Math.max(0, Math.round((dphTotal - dphBase) * 1000) / 1000);
    const totalHourlyCost = dphTotal;
    const inetDown = Math.round(raw.inet_down || 250);
    const inetUp = Math.round(raw.inet_up || 100);

    // Calculate model download duration in minutes: Size in Mbits / Speed in Mbps / 60
    const downloadMinutes = inetDown > 0
      ? Math.round((((totalModelSizeGB || 15) * 8000) / inetDown / 60) * 10) / 10
      : 2.0;

    return {
      id: String(id),
      provider: 'vastai',
      gpuName: raw.gpu_name || 'NVIDIA GPU',
      vramGB,
      numGpus: raw.num_gpus || 1,
      totalFlops: raw.total_flops || 0,
      pricePerHour: dphTotal,
      dphBase,
      storageCostPerHour,
      bandwidthCostPerGB: BANDWIDTH_COST_PER_GB,
      totalHourlyCost,
      inetUp,
      inetDown,
      reliability: Math.round((raw.reliability2 != null ? raw.reliability2 : (raw.reliability || 0.98)) * 100) / 100,
      cudaVersion: raw.cuda_max_good || 12.4,
      driverVersion: raw.driver_version || '550.54.14',
      geolocation: raw.geolocation || 'North America (US-East)',
      directPortCount: raw.direct_port_count || 1,
      cpuCores: raw.cpu_cores_effective || raw.cpu_cores || 8,
      ramGB,
      diskGB,
      dlperf: Math.round((raw.dlperf || 28.5) * 10) / 10,
      verified: raw.verified ?? true,
      rentable: !(raw.rented ?? false),
      orderScore: raw.score || 0,
      estimatedDownloadTimeMinutes: downloadMinutes,
      rawOffer: raw,
    };
  }

  /**
   * Search available GPU bundles on Vast.ai marketplace
   * @param {Object} filters
   * @returns {Promise<Array>}
   */
  async searchOffers(filters = {}) {
    const {
      minVramGB = 12,
      minRamGB = 16,
      minDiskGB = 30,
      minInetDown = 50,
      minInetUp,
      minReliability = 0.9,
      gpuName,
      verifiedOnly = true,
      rentableOnly = true,
      limit = 50,
      totalModelSizeGB = 15,
    } = filters;

    const cacheKey = JSON.stringify({
      minVramGB,
      minRamGB,
      minDiskGB,
      minInetDown,
      minReliability,
      gpuName,
      verifiedOnly,
      limit,
    });

    const cached = this._cache.get(cacheKey);
    if (cached && Date.now() - cached.timestamp < VASTAI_OFFERS_CACHE_TTL_MS) {
      return cached.data;
    }

    // Build Vast.ai query criteria at the top level
    const body = {
      num_gpus: { eq: 1 },
      order: [['dph_total', 'asc']],
      limit: Math.max(limit, 30),
    };

    if (rentableOnly) body.rented = { eq: false };
    if (verifiedOnly) body.verified = { eq: true };
    if (minVramGB && minVramGB > 0) body.gpu_ram = { gte: minVramGB * 1000 };
    if (minRamGB && minRamGB > 0) body.cpu_ram = { gte: minRamGB * 1000 };
    if (minDiskGB && minDiskGB > 0) body.disk_space = { gte: minDiskGB };
    if (minInetDown && minInetDown > 0) body.inet_down = { gte: minInetDown };
    if (minInetUp && minInetUp > 0) body.inet_up = { gte: minInetUp };
    if (minReliability && minReliability > 0) body.reliability2 = { gte: minReliability };
    if (gpuName) body.gpu_name = { eq: gpuName };

    try {
      const response = await this._requestWithRetry(() =>
        this.client.post('/bundles/', body)
      );

      const rawOffers = response.data?.offers || [];
      if (rawOffers.length > 0) {
        const normalized = rawOffers.map((o) => this.normalizeOffer(o, totalModelSizeGB));
        this._cache.set(cacheKey, { timestamp: Date.now(), data: normalized });
        return normalized;
      }

      // If strict reliability filter resulted in 0 offers, retry without reliability constraint
      if (body.reliability2) {
        delete body.reliability2;
        const retryRes = await this._requestWithRetry(() =>
          this.client.post('/bundles/', body)
        );
        const retryOffers = retryRes.data?.offers || [];
        if (retryOffers.length > 0) {
          const normalized = retryOffers.map((o) => this.normalizeOffer(o, totalModelSizeGB));
          this._cache.set(cacheKey, { timestamp: Date.now(), data: normalized });
          return normalized;
        }
      }

      console.warn('[Vast.ai] 0 offers from live API matching query. Serving sandbox offers.');
      const fallback = this._generateSandboxOffers(filters, totalModelSizeGB);
      return fallback;
    } catch (error) {
      console.warn(`[Vast.ai API Error] ${error.message}. Serving resilient sandbox offers.`);
      const fallback = this._generateSandboxOffers(filters, totalModelSizeGB);
      return fallback;
    }
  }

  /**
   * Get single offer details by ID
   * @param {string|number} offerId
   * @returns {Promise<Object>}
   */
  async getOffer(offerId) {
    const all = await this.searchOffers({ limit: 100 });
    const found = all.find((o) => String(o.id) === String(offerId));
    if (found) return found;

    try {
      const response = await this._requestWithRetry(() =>
        this.client.get(`/bundles/${offerId}/`)
      );
      if (response.data) {
        return this.normalizeOffer(response.data);
      }
    } catch (e) {
      // Fallback
    }

    throw ApiError.notFound(`Vast.ai offer not found with ID: ${offerId}`);
  }

  /**
   * Provision and rent an on-demand GPU instance on Vast.ai
   * @param {string|number} offerId
   * @param {Object} config - { image, disk, env, label }
   * @returns {Promise<Object>}
   */
  async createInstance(offerId, config = {}) {
    const payload = {
      image: config.image || 'sanieyne/ai-image-studio:python-engine',
      disk: config.disk || 100,
      env: config.env || { AI_STUDIO_MODE: 'cloud' },
      onstart: config.onstart || '',
      runtype: 'ssh',
      label: config.label || 'ai-image-studio-instance',
    };

    try {
      if (!env.VASTAI_API_KEY) {
        // Return simulated contract ID in sandbox mode
        const mockContractId = Math.floor(1000000 + Math.random() * 9000000);
        return {
          success: true,
          new_contract: mockContractId,
          instanceId: String(mockContractId),
          status: 'provisioning',
          sandbox: true,
        };
      }

      const response = await this._requestWithRetry(() =>
        this.client.put(`/asks/${offerId}/`, payload)
      );

      return {
        success: true,
        new_contract: response.data?.new_contract,
        instanceId: String(response.data?.new_contract),
        raw: response.data,
      };
    } catch (error) {
      throw ApiError.badGateway(`Failed to launch Vast.ai instance: ${error.response?.data?.msg || error.message}`);
    }
  }

  /**
   * Terminate and destroy an active Vast.ai instance
   * @param {string|number} instanceId
   * @returns {Promise<Object>}
   */
  async destroyInstance(instanceId) {
    try {
      if (!env.VASTAI_API_KEY) {
        return { success: true, instanceId, status: 'stopped', sandbox: true };
      }

      const response = await this._requestWithRetry(() =>
        this.client.delete(`/instances/${instanceId}/`)
      );

      return {
        success: true,
        instanceId,
        data: response.data,
      };
    } catch (error) {
      throw ApiError.badGateway(`Failed to destroy Vast.ai instance: ${error.response?.data?.msg || error.message}`);
    }
  }

  /**
   * Retrieve active instances belonging to user account
   * @returns {Promise<Array>}
   */
  async getInstances() {
    try {
      if (!env.VASTAI_API_KEY) {
        return [];
      }

      const response = await this._requestWithRetry(() =>
        this.client.get('/instances/')
      );

      return response.data?.instances || [];
    } catch (error) {
      console.warn(`[Vast.ai] getInstances error: ${error.message}`);
      return [];
    }
  }

  /**
   * Fetch instance console logs
   * @param {string|number} instanceId
   * @returns {Promise<string>}
   */
  async getInstanceLogs(instanceId) {
    try {
      if (!env.VASTAI_API_KEY) {
        return '[Sandbox Log] Python Engine container initializing. PyTorch CUDA initialized.';
      }

      const response = await this._requestWithRetry(() =>
        this.client.get(`/instances/${instanceId}/logs`)
      );

      return response.data?.logs || '';
    } catch (error) {
      return `Failed to fetch logs: ${error.message}`;
    }
  }

  /**
   * Generate high-fidelity realistic GPU marketplace bundles for sandbox and offline resilience
   */
  _generateSandboxOffers(filters, totalModelSizeGB = 15) {
    const rawTemplates = [
      {
        id: 1042918,
        gpu_name: 'RTX 3060',
        gpu_ram: 12000,
        num_gpus: 1,
        total_flops: 12.7,
        dph_total: 0.185,
        dph_base: 0.170,
        storage_cost: 0.00015,
        inet_up: 320,
        inet_down: 450,
        reliability2: 0.985,
        cuda_max_good: 12.4,
        driver_version: '550.54.14',
        geolocation: 'US (Virginia)',
        direct_port_count: 2,
        cpu_cores_effective: 8,
        cpu_ram: 32000,
        disk_space: 120,
        dlperf: 16.2,
        verified: true,
        rented: false,
      },
      {
        id: 1058294,
        gpu_name: 'RTX 3090',
        gpu_ram: 24000,
        num_gpus: 1,
        total_flops: 35.6,
        dph_total: 0.380,
        dph_base: 0.360,
        storage_cost: 0.00018,
        inet_up: 650,
        inet_down: 850,
        reliability2: 0.992,
        cuda_max_good: 12.4,
        driver_version: '550.54.14',
        geolocation: 'US (Oregon)',
        direct_port_count: 4,
        cpu_cores_effective: 16,
        cpu_ram: 64000,
        disk_space: 200,
        dlperf: 32.4,
        verified: true,
        rented: false,
      },
      {
        id: 1061129,
        gpu_name: 'RTX 3090',
        gpu_ram: 24000,
        num_gpus: 1,
        total_flops: 35.6,
        dph_total: 0.420,
        dph_base: 0.400,
        storage_cost: 0.00020,
        inet_up: 900,
        inet_down: 1200,
        reliability2: 0.998,
        cuda_max_good: 12.4,
        driver_version: '550.78.00',
        geolocation: 'Germany (Frankfurt)',
        direct_port_count: 5,
        cpu_cores_effective: 24,
        cpu_ram: 128000,
        disk_space: 250,
        dlperf: 34.1,
        verified: true,
        rented: false,
      },
      {
        id: 1074551,
        gpu_name: 'RTX 4090',
        gpu_ram: 24000,
        num_gpus: 1,
        total_flops: 82.6,
        dph_total: 0.580,
        dph_base: 0.550,
        storage_cost: 0.00022,
        inet_up: 1000,
        inet_down: 1500,
        reliability2: 0.995,
        cuda_max_good: 12.4,
        driver_version: '550.78.00',
        geolocation: 'US (California)',
        direct_port_count: 6,
        cpu_cores_effective: 32,
        cpu_ram: 128000,
        disk_space: 300,
        dlperf: 78.9,
        verified: true,
        rented: false,
      },
      {
        id: 1089201,
        gpu_name: 'A100-SXM4-40GB',
        gpu_ram: 40000,
        num_gpus: 1,
        total_flops: 77.9,
        dph_total: 1.050,
        dph_base: 1.000,
        storage_cost: 0.00025,
        inet_up: 2000,
        inet_down: 2500,
        reliability2: 0.999,
        cuda_max_good: 12.4,
        driver_version: '550.54.14',
        geolocation: 'Ireland (Dublin)',
        direct_port_count: 8,
        cpu_cores_effective: 48,
        cpu_ram: 256000,
        disk_space: 500,
        dlperf: 85.0,
        verified: true,
        rented: false,
      },
      {
        id: 1098412,
        gpu_name: 'A100-SXM4-80GB',
        gpu_ram: 80000,
        num_gpus: 1,
        total_flops: 155.8,
        dph_total: 1.680,
        dph_base: 1.600,
        storage_cost: 0.00030,
        inet_up: 3000,
        inet_down: 4000,
        reliability2: 0.999,
        cuda_max_good: 12.4,
        driver_version: '550.54.14',
        geolocation: 'US (Texas)',
        direct_port_count: 10,
        cpu_cores_effective: 64,
        cpu_ram: 512000,
        disk_space: 1000,
        dlperf: 140.0,
        verified: true,
        rented: false,
      },
    ];

    const minVram = filters.minVramGB || 12;
    return rawTemplates
      .filter((t) => (t.gpu_ram / 1000) >= minVram)
      .map((t) => this.normalizeOffer(t, totalModelSizeGB));
  }
}

export const vastaiService = new VastaiService();
