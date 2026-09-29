/**
 * ModerationLog Mongoose Model
 * Immutable audit log tracking automated and manual moderation checks and decisions.
 */

import mongoose from 'mongoose';

const moderationLogSchema = new mongoose.Schema(
  {
    generationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Generation',
      required: [true, 'generationId is required'],
      index: true,
    },
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'userId is required'],
      index: true,
    },
    mediaType: {
      type: String,
      enum: ['image', 'video', 'audio'],
      required: true,
    },
    verdict: {
      type: String,
      enum: ['allow', 'review', 'block', 'approved', 'rejected'],
      required: true,
      index: true,
    },
    provider: {
      type: String,
      default: 'google-vision',
    },
    scores: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },
    reason: {
      type: String,
      default: '',
    },
    reviewedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    decision: {
      type: String,
      enum: ['approve', 'reject', 'remove_content', 'dismiss', null],
      default: null,
    },

  },
  {
    timestamps: true,
  }
);

export const ModerationLog = mongoose.model('ModerationLog', moderationLogSchema);
export default ModerationLog;
