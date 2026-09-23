/**
 * Transaction Mongoose Model
 * Immutable audit ledger for all credit grants, purchases, deductions, and refunds.
 */

import mongoose from 'mongoose';
import { TRANSACTION_TYPES } from '../config/constants.js';

const transactionSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'User reference is required'],
      index: true,
    },
    type: {
      type: String,
      enum: Object.values(TRANSACTION_TYPES),
      required: [true, 'Transaction type is required'],
    },
    amount: {
      type: Number,
      required: [true, 'Transaction amount is required'],
    },
    balanceAfter: {
      type: Number,
      required: [true, 'Balance after transaction is required'],
      min: [0, 'Balance after transaction cannot be negative'],
    },
    description: {
      type: String,
      required: [true, 'Transaction description is required'],
      trim: true,
    },
    metadata: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },
  },
  {
    timestamps: true,
  }
);

// Compound index for high-performance paginated queries per user ordered by newest first
transactionSchema.index({ user: 1, createdAt: -1 });

export const Transaction = mongoose.model('Transaction', transactionSchema);
