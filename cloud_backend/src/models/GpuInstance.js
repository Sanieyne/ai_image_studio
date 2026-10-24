/**
 * GPU Instance Mongoose Model
 * Tracks cloud GPU lifecycle (Vast.ai, RunPod, Contabo), provisioning status, and connection endpoints.
 */

import mongoose from 'mongoose';
import { GPU_STATUS, GPU_PROVIDERS, LOG_LEVELS } from '../config/constants.js';

const logEntrySchema = new mongoose.Schema(
  {
    timestamp: {
      type: Date,
      default: Date.now,
    },
    message: {
      type: String,
      required: true,
    },
    level: {
      type: String,
      enum: Object.values(LOG_LEVELS),
      default: LOG_LEVELS.INFO,
    },
  },
  { _id: false }
);

const gpuInstanceSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'Owner user is required'],
      index: true,
    },
    provider: {
      type: String,
      enum: Object.values(GPU_PROVIDERS),
      required: [true, 'GPU provider is required'],
    },
    providerInstanceId: {
      type: String,
      required: [true, 'Provider instance ID is required'],
      index: true,
    },
    status: {
      type: String,
      enum: Object.values(GPU_STATUS),
      default: GPU_STATUS.PROVISIONING,
      index: true,
    },
    gpuType: {
      type: String,
      required: [true, 'GPU model/type is required'],
      trim: true,
    },
    vramGB: {
      type: Number,
      required: [true, 'VRAM capacity is required'],
      min: 1,
    },
    costPerHour: {
      type: Number,
      required: [true, 'Hourly cost is required'],
      min: 0,
    },
    sshHost: {
      type: String,
      default: null,
    },
    sshPort: {
      type: Number,
      default: null,
    },
    publicIp: {
      type: String,
      default: null,
    },
    pythonEngineUrl: {
      type: String,
      default: null,
    },
    modelsRequested: {
      type: [String],
      default: [],
    },
    vastOffer: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
    pricing: {
      dph_total: { type: Number, default: 0 },
      storageCost: { type: Number, default: 0 },
      bandwidthCost: { type: Number, default: 0 },
      totalPerHour: { type: Number, default: 0 },
      // Credits, from pricingService.priceOffer for the rented storage size.
      // Billing charges totalCreditsPerHour.
      storageGB: { type: Number, default: null },
      computeCreditsPerHour: { type: Number, default: null },
      storageCreditsPerGBMonth: { type: Number, default: null },
      storageCreditsPerHour: { type: Number, default: 0 },
      totalCreditsPerHour: { type: Number, default: 0 },
      bandwidthDownCreditsPerGB: { type: Number, default: null },
      bandwidthUpCreditsPerGB: { type: Number, default: null },
      markupPercentage: { type: Number, default: null },
      // Older names (= computeCreditsPerHour, bandwidthDownCreditsPerGB), read by app v0.2.0.
      creditsPerHour: { type: Number, default: 0 },
      bandwidthCreditsPerGB: { type: Number, default: 0 },
    },
    network: {
      inet_up: { type: Number, default: 0 },
      inet_down: { type: Number, default: 0 },
      reliability: { type: Number, default: 1.0 },
      geolocation: { type: String, default: 'Global' },
    },
    specs: {
      cudaVersion: { type: Number, default: 12.1 },
      driver: { type: String, default: null },
      directPortCount: { type: Number, default: 1 },
      cpuCores: { type: Number, default: 8 },
      ramGB: { type: Number, default: 32 },
      diskGB: { type: Number, default: 100 },
    },
    provisioningLogs: {
      type: [logEntrySchema],
      default: [],
    },
    // --- Billing (see services/billing.service.js) ---
    // Vast.ai confirmed the contract; billing starts here for new rentals.
    contractConfirmedAt: { type: Date, default: null },
    // Charged up to this moment. Advanced with a conditional update before each
    // charge, so a period can only be claimed once across backend processes.
    billedUntil: { type: Date, default: null },
    // Start of the billed time. Each charge is (total owed for billingStartedAt..until)
    // minus creditsCharged, so per-cycle rounding never accumulates.
    billingStartedAt: { type: Date, default: null },
    creditsCharged: { type: Number, default: 0 },
    bandwidthCreditsCharged: { type: Number, default: 0 },
    bandwidthDownGBBilled: { type: Number, default: 0 },
    bandwidthUpGBBilled: { type: Number, default: 0 },
    creditsRefunded: { type: Number, default: 0 },
    refundIssued: { type: Boolean, default: false },
    reachedReadyAt: { type: Date, default: null },
    stopReason: { type: String, default: null },
    // A stop the billing service could not complete (e.g. destroy failed); retried each cycle.
    pendingStopReason: { type: String, default: null },
    lowBalanceWarnedAt: { type: Date, default: null },
    // Provider presence tracking for the poller.
    lastSeenOnVastAt: { type: Date, default: null },
    vastMissCount: { type: Number, default: 0 },
    firstMissAt: { type: Date, default: null },
    // Whether this instance still holds one of the user's active-instance slots.
    holdsSlot: { type: Boolean, default: false },

    // Latest provisioning progress, as shown to the user (see instancePoller.service.js).
    progress: {
      stage: { type: String, default: null },
      message: { type: String, default: null },
      vastStatus: { type: String, default: null },
      vastStatusMessage: { type: String, default: null },
      portFound: { type: Boolean, default: false },
      engineReachable: { type: Boolean, default: false },
      failureReason: { type: String, default: null },
      models: {
        type: [{ _id: false, modelId: String, status: String, progressPercent: Number, error: String }],
        default: [],
      },
      updatedAt: { type: Date, default: null },
    },

    startedAt: {
      type: Date,
      default: null,
    },
    stoppedAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

gpuInstanceSchema.index({ user: 1, status: 1 });
gpuInstanceSchema.index({ status: 1 });

export const GpuInstance = mongoose.model('GpuInstance', gpuInstanceSchema);
