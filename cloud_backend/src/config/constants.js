/**
 * Application Constants
 * Single source of truth for enums, roles, GPU tiers, and storage plans across AI Image Studio Cloud Orchestrator.
 */

export const ROLES = Object.freeze({
  USER: 'user',
  ADMIN: 'admin',
});

export const TRANSACTION_TYPES = Object.freeze({
  BONUS: 'bonus',
  PURCHASE: 'purchase',
  DEDUCTION: 'deduction',
  REFUND: 'refund',
});

export const GPU_STATUS = Object.freeze({
  PROVISIONING: 'provisioning',
  READY: 'ready',
  RUNNING: 'running',
  STOPPED: 'stopped',
  FAILED: 'failed',
});

export const GPU_PROVIDERS = Object.freeze({
  VASTAI: 'vastai',
  RUNPOD: 'runpod',
  CONTABO: 'contabo',
});

export const MODEL_MODES = Object.freeze({
  IMAGE: 'image',
  VIDEO: 'video',
  MOTION: 'motion',
  VOICE: 'voice',
  VTON: 'vton',
  ENHANCER: 'enhancer',
});

export const LOG_LEVELS = Object.freeze({
  INFO: 'info',
  WARN: 'warn',
  ERROR: 'error',
});

export const STORAGE_STATUS = Object.freeze({
  CREATING: 'creating',
  MOUNTED: 'mounted',
  UNMOUNTED: 'unmounted',
  DELETED: 'deleted',
});

// System overheads
export const BASE_OVERHEAD_GB = 7; // OS + Python virtualenv + Diffusers libraries
export const OUTPUT_BUFFER_PERCENT = 0.3; // 30% storage headroom for generated high-res media

// GPU Hardware Tiers for Cloud Provisioning
export const GPU_TIERS = Object.freeze([
  {
    id: 'rtx-3060-12gb',
    name: 'RTX 3060',
    vramGB: 12,
    ramGB: 32,
    pricePerHour: 0.22,
    tier: 'budget',
    tags: ['budget', 'sdxl', 'z-image', 'vton'],
  },
  {
    id: 'rtx-3090-24gb',
    name: 'RTX 3090',
    vramGB: 24,
    ramGB: 64,
    pricePerHour: 0.44,
    tier: 'balanced',
    tags: ['popular', 'flux', 'qwen', 'wan-1.3b'],
  },
  {
    id: 'rtx-4090-24gb',
    name: 'RTX 4090',
    vramGB: 24,
    ramGB: 64,
    pricePerHour: 0.62,
    tier: 'performance',
    tags: ['fast', 'flux', 'wan'],
  },
  {
    id: 'a100-40gb',
    name: 'A100 40GB',
    vramGB: 40,
    ramGB: 128,
    pricePerHour: 1.15,
    tier: 'pro',
    tags: ['wan-14b', 'minimax'],
  },
  {
    id: 'a100-80gb',
    name: 'A100 80GB',
    vramGB: 80,
    ramGB: 256,
    pricePerHour: 1.85,
    tier: 'enterprise',
    tags: ['all', 'minimax-h3'],
  },
]);

// Cloud Storage Volume Pricing Plans
export const STORAGE_PLANS = Object.freeze([
  { id: '30gb', sizeGB: 30, pricePerMonth: 3, name: 'Starter 30GB' },
  { id: '50gb', sizeGB: 50, pricePerMonth: 5, name: 'Creator 50GB' },
  { id: '100gb', sizeGB: 100, pricePerMonth: 9, name: 'Studio 100GB' },
  { id: '200gb', sizeGB: 200, pricePerMonth: 16, name: 'Pro 200GB' },
  { id: '500gb', sizeGB: 500, pricePerMonth: 35, name: 'Enterprise 500GB' },
]);

// Vast.ai Marketplace & Provisioning Constants
export const BANDWIDTH_COST_PER_GB = 0.02; // $0.02 per GB network egress/ingress fallback
export const VASTAI_OFFERS_CACHE_TTL_MS = 30000; // 30s cache TTL to avoid rate limiting

export const VASTAI_GPU_NAME_MAP = Object.freeze({
  'RTX 3060': ['RTX 3060', 'GeForce RTX 3060', 'RTX 3060 Ti'],
  'RTX 3090': ['RTX 3090', 'GeForce RTX 3090', 'RTX 3090 Ti'],
  'RTX 4090': ['RTX 4090', 'GeForce RTX 4090'],
  'A100': ['A100', 'A100-SXM4-40GB', 'A100-SXM4-80GB', 'A100-PCIE-40GB', 'A100-PCIE-80GB'],
  'H100': ['H100', 'H100 80GB HBM3', 'H100-PCIE-80GB'],
});

