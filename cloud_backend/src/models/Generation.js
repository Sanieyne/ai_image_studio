/**
 * Generation Mongoose Model
 * Represents a persisted generation artifact (image, video, or audio)
 * created by a user, stored in object/disk storage.
 */

import mongoose from 'mongoose';
import { storageService } from '../services/storage.service.js';
import { MODERATION_STATUS } from '../config/constants.js';

const generationSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'userId is required'],
      index: true,
    },
    mediaType: {
      type: String,
      enum: {
        values: ['image', 'video', 'audio'],
        message: 'mediaType must be image, video, or audio',
      },
      default: 'image',
      required: [true, 'mediaType is required'],
    },
    storageKey: {
      type: String,
      required: [true, 'storageKey is required'],
      trim: true,
    },
    prompt: {
      type: String,
      required: [true, 'prompt is required'],
      trim: true,
    },
    negativePrompt: {
      type: String,
      default: '',
      trim: true,
    },
    modelId: {
      type: String,
      required: [true, 'modelId is required'],
      trim: true,
    },
    settings: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },
    fileSizeBytes: {
      type: Number,
      default: 0,
      min: 0,
    },
    isPublic: {
      type: Boolean,
      default: false,
      index: true,
    },
    moderationStatus: {
      type: String,
      enum: Object.values(MODERATION_STATUS),
      default: MODERATION_STATUS.NOT_SUBMITTED,
      index: true,
    },
    publishedAt: {
      type: Date,
      default: null,
    },
    likesCount: {
      type: Number,
      default: 0,
      min: 0,
      index: true,
    },
    viewsCount: {
      type: Number,
      default: 0,
      min: 0,
    },
    reportsCount: {
      type: Number,
      default: 0,
      min: 0,
      index: true,
    },
  },
  {
    timestamps: true,
    toJSON: {
      virtuals: true,
      transform: (doc, ret) => {
        delete ret.__v;
        return ret;
      },
    },
    toObject: {
      virtuals: true,
    },
  }
);

// Compound indexes for gallery queries and admin reporting triage
generationSchema.index({ isPublic: 1, moderationStatus: 1, createdAt: -1 });
generationSchema.index({ isPublic: 1, moderationStatus: 1, likesCount: -1 });
generationSchema.index({ userId: 1, isPublic: 1, moderationStatus: 1, createdAt: -1 });
generationSchema.index({ reportsCount: -1, createdAt: -1 });

// Virtual for resolved public URL
generationSchema.virtual('url').get(function () {
  return storageService.getMediaUrl(this.storageKey);
});

export const Generation = mongoose.model('Generation', generationSchema);
export default Generation;

