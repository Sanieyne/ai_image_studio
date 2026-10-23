/**
 * Pricing & Token Configuration Mongoose Model
 * Stores global token-to-USD conversion rate, provider price markup percentage, and launch thresholds.
 * Allows administrators to dynamically update credit pricing and margins without restarting the server.
 */

import mongoose from 'mongoose';

const pricingConfigSchema = new mongoose.Schema(
  {
    // Number of credits per 1 USD (token value)
    tokenValue: {
      type: Number,
      required: [true, 'Token value (credits per USD) is required'],
      default: 100,
      min: [1, 'Token value must be at least 1 credit per USD'],
    },
    // Percentage markup added to raw provider costs (e.g. 25 = 25% markup)
    markupPercentage: {
      type: Number,
      required: [true, 'Markup percentage is required'],
      default: 25,
      min: [0, 'Markup percentage cannot be negative'],
      max: [500, 'Markup percentage cannot exceed 500%'],
    },
    // Minimum credits required on user account to launch an instance
    minLaunchCredits: {
      type: Number,
      default: 10,
      min: [0, 'Minimum launch credits cannot be negative'],
    },
    isActive: {
      type: Boolean,
      default: true,
      index: true,
    },
    updatedBy: {
      type: String,
      default: 'system',
    },
    notes: {
      type: String,
      default: 'Default production pricing policy (50 credits/USD, 25% markup)',
    },
  },
  {
    timestamps: true,
  }
);

// Helper virtual for markup multiplier (e.g., 25% -> 1.25)
pricingConfigSchema.virtual('markupMultiplier').get(function () {
  return 1 + (this.markupPercentage || 0) / 100;
});

pricingConfigSchema.set('toJSON', { virtuals: true });
pricingConfigSchema.set('toObject', { virtuals: true });

export const PricingConfig = mongoose.model('PricingConfig', pricingConfigSchema);
