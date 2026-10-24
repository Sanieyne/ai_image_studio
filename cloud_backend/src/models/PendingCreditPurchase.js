/**
 * Pending Credit Purchase Model
 * Holds credit purchases from Gumroad where the purchaser email
 * did not match an existing app user at webhook arrival time.
 */

import mongoose from 'mongoose';

const pendingCreditPurchaseSchema = new mongoose.Schema(
  {
    email: {
      type: String,
      required: true,
      lowercase: true,
      trim: true,
      index: true,
    },
    saleId: {
      type: String,
      required: true,
      unique: true,
      trim: true,
    },
    orderId: {
      type: String,
      trim: true,
      index: true,
    },
    credits: {
      type: Number,
      required: true,
    },
    priceCents: {
      type: Number,
      required: true,
    },
    productName: {
      type: String,
      default: '',
    },
    permalink: {
      type: String,
      default: '',
    },
    isClaimed: {
      type: Boolean,
      default: false,
      index: true,
    },
    claimedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    claimedAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

export const PendingCreditPurchase = mongoose.model('PendingCreditPurchase', pendingCreditPurchaseSchema);
