/**
 * Storage Volume Mongoose Model
 * Tracks user persistent cloud disk allocations, mount points, and used storage bytes.
 */

import mongoose from 'mongoose';
import { STORAGE_STATUS } from '../config/constants.js';

const storageVolumeSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'Owner user is required'],
      index: true,
    },
    volumeId: {
      type: String,
      required: [true, 'Volume ID is required'],
      unique: true,
      index: true,
    },
    sizeGB: {
      type: Number,
      required: [true, 'Volume size in GB is required'],
      min: 10,
      max: 1000,
    },
    usedGB: {
      type: Number,
      default: 0,
      min: 0,
    },
    mountPath: {
      type: String,
      default: null,
    },
    status: {
      type: String,
      enum: Object.values(STORAGE_STATUS),
      default: STORAGE_STATUS.CREATING,
      index: true,
    },
  },
  {
    timestamps: true,
  }
);

export const StorageVolume = mongoose.model('StorageVolume', storageVolumeSchema);
