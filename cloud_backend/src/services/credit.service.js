/**
 * Credit & Ledger Service
 * Handles atomic credit deductions, additions, and transaction ledger records.
 */

import mongoose from 'mongoose';
import { User } from '../models/User.js';
import { Transaction } from '../models/Transaction.js';
import { ApiError } from '../utils/ApiError.js';
import { TRANSACTION_TYPES } from '../config/constants.js';

class CreditService {
  /**
   * Fetch current credit balance for a user
   * @param {string|mongoose.Types.ObjectId} userId
   * @param {mongoose.ClientSession} [session]
   * @returns {Promise<number>}
   */
  async getBalance(userId, session = null) {
    const query = User.findById(userId).select('credits');
    if (session) {
      query.session(session);
    }
    const user = await query;
    if (!user) {
      throw ApiError.notFound('User not found');
    }
    return user.credits;
  }

  /**
   * Check if user has at least the required credit balance
   * @param {string|mongoose.Types.ObjectId} userId
   * @param {number} amount
   * @param {mongoose.ClientSession} [session]
   * @returns {Promise<boolean>}
   */
  async hasEnough(userId, amount, session = null) {
    const currentBalance = await this.getBalance(userId, session);
    return currentBalance >= amount;
  }

  /**
   * Atomically add credits to a user account and append an immutable transaction record.
   * @param {string|mongoose.Types.ObjectId} userId
   * @param {number} amount - Positive credit amount
   * @param {string} type - bonus, purchase, refund
   * @param {string} description - Explanation of credit addition
   * @param {Object} [metadata={}] - Optional reference info
   * @param {mongoose.ClientSession} [externalSession=null]
   * @returns {Promise<{ user: Object, transaction: Object }>}
   */
  async addCredits(
    userId,
    amount,
    type = TRANSACTION_TYPES.PURCHASE,
    description = 'Credits added',
    metadata = {},
    externalSession = null
  ) {
    if (amount <= 0) {
      throw ApiError.badRequest('Credit amount to add must be greater than zero');
    }

    const executeOperation = async (session) => {
      const incFields = { credits: amount };
      if (type === TRANSACTION_TYPES.PURCHASE) {
        incFields.totalCreditsPurchased = amount;
      }

      const updatedUser = await User.findByIdAndUpdate(
        userId,
        { $inc: incFields },
        { new: true, session, runValidators: true }
      );

      if (!updatedUser) {
        throw ApiError.notFound('User not found');
      }

      const [transaction] = await Transaction.create(
        [
          {
            user: userId,
            type,
            amount,
            balanceAfter: updatedUser.credits,
            description,
            metadata,
          },
        ],
        { session }
      );

      return { user: updatedUser, transaction };
    };

    if (externalSession) {
      return executeOperation(externalSession);
    }

    const session = await mongoose.startSession();
    session.startTransaction();
    try {
      const result = await executeOperation(session);
      await session.commitTransaction();
      return result;
    } catch (error) {
      await session.abortTransaction();
      throw error;
    } finally {
      session.endSession();
    }
  }

  /**
   * Atomically deduct credits from a user account.
   * Throws 402 ApiError if user has insufficient credits.
   * @param {string|mongoose.Types.ObjectId} userId
   * @param {number} amount - Positive amount to deduct
   * @param {string} description - Reason for deduction
   * @param {Object} [metadata={}] - GPU instance ID, job ID, etc.
   * @param {mongoose.ClientSession} [externalSession=null]
   * @returns {Promise<{ user: Object, transaction: Object }>}
   */
  async deductCredits(
    userId,
    amount,
    description = 'GPU Compute Usage',
    metadata = {},
    externalSession = null
  ) {
    if (amount <= 0) {
      throw ApiError.badRequest('Deduction amount must be greater than zero');
    }

    const executeOperation = async (session) => {
      // Find user with session lock
      const user = await User.findById(userId).session(session);
      if (!user) {
        throw ApiError.notFound('User not found');
      }

      if (user.credits < amount) {
        throw ApiError.paymentRequired(
          `Insufficient credits: available ${user.credits.toFixed(2)}, required ${amount.toFixed(2)}.`
        );
      }

      user.credits = Math.round((user.credits - amount) * 1000) / 1000;
      user.totalCreditsUsed = Math.round((user.totalCreditsUsed + amount) * 1000) / 1000;
      await user.save({ session });

      const [transaction] = await Transaction.create(
        [
          {
            user: userId,
            type: TRANSACTION_TYPES.DEDUCTION,
            amount: -amount,
            balanceAfter: user.credits,
            description,
            metadata,
          },
        ],
        { session }
      );

      return { user, transaction };
    };

    if (externalSession) {
      return executeOperation(externalSession);
    }

    const session = await mongoose.startSession();
    session.startTransaction();
    try {
      const result = await executeOperation(session);
      await session.commitTransaction();
      return result;
    } catch (error) {
      await session.abortTransaction();
      throw error;
    } finally {
      session.endSession();
    }
  }
}

export const creditService = new CreditService();
