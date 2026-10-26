/**
 * License Mongoose Model
 * Manages VIP tester keys, promo codes, studio passes, credit grants, and redemption audit logs.
 */

import mongoose from 'mongoose';

const redemptionEntrySchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    email: {
      type: String,
      default: null,
    },
    redeemedAt: {
      type: Date,
      default: Date.now,
    },
  },
  { _id: false }
);

const licenseSchema = new mongoose.Schema(
  {
    code: {
      type: String,
      required: [true, 'License code is required'],
      unique: true,
      uppercase: true,
      trim: true,
      index: true,
    },
    tier: {
      type: String,
      enum: ['free', 'starter', 'pro', 'vip'],
      default: 'vip',
    },
    creditsGranted: {
      type: Number,
      default: 50,
      min: [0, 'Credits granted cannot be negative'],
    },
    maxRedemptions: {
      type: Number,
      default: 1,
      min: [1, 'Max redemptions must be at least 1'],
    },
    redemptionsCount: {
      type: Number,
      default: 0,
      min: 0,
    },
    redeemedBy: {
      type: [redemptionEntrySchema],
      default: [],
    },
    expiresAt: {
      type: Date,
      default: null,
    },
    isActive: {
      type: Boolean,
      default: true,
      index: true,
    },
    notes: {
      type: String,
      default: '',
      trim: true,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

export const License = mongoose.model('License', licenseSchema);
