/**
 * Model Catalog Mongoose Model
 * Registry for supported AI diffusion/generation models, required VRAM, and download disk foot-print.
 */

import mongoose from 'mongoose';
import { MODEL_MODES } from '../config/constants.js';

const modelCatalogSchema = new mongoose.Schema(
  {
    modelId: {
      type: String,
      required: [true, 'Model identifier is required'],
      unique: true,
      trim: true,
      lowercase: true,
      index: true,
    },
    displayName: {
      type: String,
      required: [true, 'Display name is required'],
      trim: true,
    },
    mode: {
      type: String,
      enum: Object.values(MODEL_MODES),
      required: [true, 'Model generation mode is required'],
      index: true,
    },
    hfRepoId: {
      type: String,
      required: [true, 'HuggingFace repo ID is required'],
      trim: true,
    },
    sizeGB: {
      type: Number,
      required: [true, 'Model weight size in GB is required'],
      min: 0.1,
    },
    requiredVramGB: {
      type: Number,
      required: [true, 'Required VRAM in GB is required'],
      min: 1,
    },
    defaultSteps: {
      type: Number,
      default: 30,
    },
    defaultGuidance: {
      type: Number,
      default: 5.0,
    },
    isEnabled: {
      type: Boolean,
      default: true,
    },
  },
  {
    timestamps: true,
  }
);

export const ModelCatalog = mongoose.model('ModelCatalog', modelCatalogSchema);
