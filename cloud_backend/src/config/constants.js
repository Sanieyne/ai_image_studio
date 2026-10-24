/**
 * Application Constants
 * Single source of truth for enums, roles, GPU tiers, and storage plans across AI Image Studio Cloud Orchestrator.
 */

export const ROLES = Object.freeze({
  USER: 'user',
  ADMIN: 'admin',
});

export const MODERATION_STATUS = Object.freeze({
  NOT_SUBMITTED: 'not_submitted',
  PENDING_REVIEW: 'pending_review',
  APPROVED: 'approved',
  REJECTED: 'rejected',
});

export const TRANSACTION_TYPES = Object.freeze({
  BONUS: 'bonus',
  PURCHASE: 'purchase',
  DEDUCTION: 'deduction',
  REFUND: 'refund',
});

export const GPU_STATUS = Object.freeze({
  PROVISIONING: 'provisioning',
  DOWNLOADING_MODEL: 'downloading_model',
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

// Pricing & Credits Policy: 100 credits per 1 USD (0.01 USD/credit), 25% markup on raw Vast.ai pricing (1.25x)
export const CREDITS_PER_USD = 100;
export const VASTAI_PRICE_MARKUP = 1.25;

// System overheads: generous base OS/PyTorch/CUDA overhead and headroom
export const BASE_OVERHEAD_GB = 25; // OS + Docker + PyTorch + CUDA + Diffusers + decompression cache
export const OUTPUT_BUFFER_PERCENT = 0.35; // 35% storage headroom for generated high-res media & checkpoints
export const EXTRA_FREE_HEADROOM_GB = 25; // 25 GB free buffer to guarantee complete reliability

// GPU Hardware Tiers for Cloud Provisioning (Raw provider baseline costs)
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

// Continuous Storage Volume Pricing Constants
export const STORAGE_MIN_GB = 10;
export const STORAGE_MAX_GB = 1000;
export const STORAGE_RATE_PER_GB_MONTH = 0.07; // $0.07 per GB per month linear baseline rate
export const STORAGE_HOURS_PER_MONTH = 730;

// Benchmark Storage Volume Presets (Retained for backward compatibility & UI presets)
export const STORAGE_PLANS = Object.freeze([
  { id: '10gb', sizeGB: 10, pricePerMonth: 0.70, name: 'Minimal 10GB' },
  { id: '30gb', sizeGB: 30, pricePerMonth: 2.10, name: 'Starter 30GB' },
  { id: '50gb', sizeGB: 50, pricePerMonth: 3.50, name: 'Creator 50GB' },
  { id: '100gb', sizeGB: 100, pricePerMonth: 7.00, name: 'Studio 100GB' },
  { id: '200gb', sizeGB: 200, pricePerMonth: 14.00, name: 'Pro 200GB' },
  { id: '500gb', sizeGB: 500, pricePerMonth: 35.00, name: 'Enterprise 500GB' },
  { id: '1000gb', sizeGB: 1000, pricePerMonth: 70.00, name: 'Max 1TB' },
]);

// Vast.ai Marketplace & Provisioning Constants (Raw baseline cost)
export const BANDWIDTH_COST_PER_GB = 0.02; // $0.02 per GB raw egress/ingress baseline
export const VASTAI_OFFERS_CACHE_TTL_MS = 30000; // 30s cache TTL to avoid rate limiting

export const VASTAI_GPU_NAME_MAP = Object.freeze({
  'RTX 3060': ['RTX 3060', 'GeForce RTX 3060', 'RTX 3060 Ti', 'RTX 3060 laptop'],
  'RTX 3070': ['RTX 3070', 'GeForce RTX 3070', 'RTX 3070 Ti'],
  'RTX 3080': ['RTX 3080', 'GeForce RTX 3080', 'RTX 3080 Ti'],
  'RTX 3090': ['RTX 3090', 'GeForce RTX 3090', 'RTX 3090 Ti'],
  'RTX 4060': ['RTX 4060', 'GeForce RTX 4060', 'RTX 4060 Ti'],
  'RTX 4070': ['RTX 4070', 'GeForce RTX 4070', 'RTX 4070 Ti', 'RTX 4070S Ti'],
  'RTX 4080': ['RTX 4080', 'GeForce RTX 4080', 'RTX 4080 Ti'],
  'RTX 4090': ['RTX 4090', 'GeForce RTX 4090'],
  'RTX 50-Series': ['RTX 5060', 'RTX 5060 Ti', 'RTX 5070', 'RTX 5070 Ti', 'RTX 5080', 'RTX 5090'],
  'A100': ['A100', 'A100-SXM4-40GB', 'A100-SXM4-80GB', 'A100-PCIE-40GB', 'A100-PCIE-80GB'],
  'H100': ['H100', 'H100 80GB HBM3', 'H100-PCIE-80GB'],
  'Datacenter/Pro': [
    'A4000', 'RTX A4000', 'A5000', 'RTX A5000', 'A6000', 'RTX A6000',
    '4000Ada', 'RTX 4000Ada', '5000Ada', 'RTX 5000Ada', '6000Ada', 'RTX 6000Ada',
    'Tesla V100', 'V100', 'Tesla P100', 'P100', 'A2000', 'RTX A2000', 'RTX 2080 Ti'
  ],
});

// Enforce a strict minimum 400 Mbps download speed floor for host reliability and rapid R2 weight streaming
export const MIN_INET_DOWN_FLOOR_MBPS = 400;



// What the engine image (torch 2.11, CUDA 12.8) can run: GPU architectures sm_75..sm_120
// (Turing to Blackwell; checked in the torch wheel) and hosts whose driver supports CUDA 12.8.
// Offers outside this are never shown or rented.
export const MIN_GPU_COMPUTE_CAP = 750; // Vast.ai compute_cap: 750 = sm_75
export const MIN_HOST_CUDA = 12.8; // Vast.ai cuda_max_good
