import mongoose from 'mongoose';

/**
 * Marketing Campaign Log & Analytics Schema
 * Stores campaigns created and dispatched through the Admin Console.
 */
const marketingCampaignSchema = new mongoose.Schema(
  {
    subject: {
      type: String,
      required: true,
      trim: true,
    },
    type: {
      type: String,
      required: true,
      enum: ['digest', 'video', 'image', 'audio', 'custom'],
      default: 'digest',
    },
    sender: {
      type: String,
      default: 'Cosmic-Gen <marketing@cosmic-gen.com>',
    },
    badge: {
      type: String,
      trim: true,
    },
    headline: {
      type: String,
      trim: true,
    },
    subtitle: {
      type: String,
      trim: true,
    },
    bodyText: {
      type: String,
      trim: true,
    },
    options: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },
    targetAudience: {
      type: String,
      enum: ['all_users', 'verified_users', 'test_only', 'custom_list'],
      default: 'test_only',
    },
    recipientCount: {
      type: Number,
      default: 0,
    },
    recipients: [
      {
        type: String,
        trim: true,
      },
    ],
    status: {
      type: String,
      enum: ['draft', 'queued', 'sent', 'partial_failure', 'failed'],
      default: 'sent',
    },
    results: [
      {
        email: String,
        status: String, // 'sent', 'failed'
        messageId: String,
        error: String,
      },
    ],
    sentBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
    },
    sentByEmail: {
      type: String,
    },
    sentAt: {
      type: Date,
      default: Date.now,
    },
  },
  {
    timestamps: true,
  }
);

marketingCampaignSchema.index({ createdAt: -1 });
marketingCampaignSchema.index({ type: 1 });
marketingCampaignSchema.index({ status: 1 });

export const MarketingCampaign = mongoose.model('MarketingCampaign', marketingCampaignSchema);
