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
    provisioningLogs: {
      type: [logEntrySchema],
      default: [],
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

export const GpuInstance = mongoose.model('GpuInstance', gpuInstanceSchema);
