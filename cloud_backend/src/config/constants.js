/**
 * Application Constants
 * Single source of truth for enums, roles, and states across AI Image Studio Cloud Orchestrator.
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
