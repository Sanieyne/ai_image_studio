/**
 * Credit & Ledger Service
 * Handles atomic credit deductions, additions, and transaction ledger records.
 */

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
   * Atomically add credits to a user account and append a ledger record.
   * @param {string|mongoose.Types.ObjectId} userId
   * @param {number} amount - Positive credit amount
   * @param {string} type - bonus, purchase, refund
   * @param {string} description - Explanation of credit addition
   * @param {Object} [metadata={}] - Optional reference info
   * @param {mongoose.ClientSession} [externalSession=null]
   * @param {{ recordTransaction?: boolean }} [options] false: the caller writes its own ledger entry
   * @returns {Promise<{ user: Object, transaction: Object|null }>}
   */
  async addCredits(
    userId,
    amount,
    type = TRANSACTION_TYPES.PURCHASE,
    description = 'Credits added',
    metadata = {},
    externalSession = null,
    { recordTransaction = true } = {}
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
        { returnDocument: 'after', ...(session ? { session } : {}), runValidators: true }
      );

      if (!updatedUser) {
        throw ApiError.notFound('User not found');
      }
      if (!recordTransaction) return { user: updatedUser, transaction: null };

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
        session ? { session } : {}
      );

      return { user: updatedUser, transaction };
    };

    // The balance change is one atomic $inc, correct with or without a
    // transaction. Callers that need it in a wider transaction pass their session.
    return executeOperation(externalSession);
  }

  /**
   * Atomically deduct credits from a user account.
   *
   * Each attempt is a single conditional update on the user document, so it is
   * safe without Mongo transactions and under concurrent callers.
   *
   * - Default: deduct exactly `amount`, or throw 402 if the balance is lower.
   * - `{ upTo: true }`: deduct `amount` or whatever is left, whichever is
   *   smaller; never throws for a low balance. Returns `charged` (may be 0).
   *
   * @param {string|mongoose.Types.ObjectId} userId
   * @param {number} amount - Positive amount to deduct
   * @param {string} description - Reason for deduction
   * @param {Object} [metadata={}] - GPU instance ID, job ID, etc.
   * @param {mongoose.ClientSession} [externalSession=null]
   * @param {{ upTo?: boolean, recordTransaction?: boolean }} [options]
   *   recordTransaction false: no ledger row; the caller writes its own (e.g. one row per GPU rental).
   * @returns {Promise<{ user: Object, transaction: Object|null, charged: number }>}
   */
  async deductCredits(
    userId,
    amount,
    description = 'GPU Compute Usage',
    metadata = {},
    externalSession = null,
    { upTo = false, recordTransaction = true } = {}
  ) {
    if (!(amount > 0)) {
      throw ApiError.badRequest('Deduction amount must be greater than zero');
    }
    const sessionOpt = externalSession ? { session: externalSession } : {};

    let updatedUser = null;
    let charged = 0;

    if (!upTo) {
      updatedUser = await User.findOneAndUpdate(
        { _id: userId, credits: { $gte: amount } },
        { $inc: { credits: -amount, totalCreditsUsed: amount } },
        { returnDocument: 'after', ...sessionOpt }
      );
      if (!updatedUser) {
        const exists = await User.findById(userId).select('credits').setOptions(sessionOpt);
        if (!exists) throw ApiError.notFound('User not found');
        throw ApiError.paymentRequired(
          `Insufficient credits: available ${exists.credits.toFixed(2)}, required ${amount.toFixed(2)}.`
        );
      }
      charged = amount;
    } else {
      // Charge min(amount, balance). The update is conditioned on the exact
      // balance just read, so a concurrent change makes it miss and retry.
      for (let attempt = 0; attempt < 8 && !updatedUser; attempt += 1) {
        const current = await User.findById(userId).select('credits').setOptions(sessionOpt);
        if (!current) throw ApiError.notFound('User not found');
        const balance = current.credits;
        const take = Math.min(amount, Math.max(0, balance));
        if (take <= 0) {
          return { user: current, transaction: null, charged: 0 };
        }
        // Taking the whole balance sets it to exactly 0 rather than relying on float subtraction.
        const update =
          take === balance
            ? { $set: { credits: 0 }, $inc: { totalCreditsUsed: take } }
            : { $inc: { credits: -take, totalCreditsUsed: take } };
        updatedUser = await User.findOneAndUpdate(
          { _id: userId, credits: balance },
          update,
          { returnDocument: 'after', ...sessionOpt }
        );
        if (updatedUser) charged = take;
      }
      if (!updatedUser) {
        throw ApiError.conflict('Could not charge credits due to concurrent balance updates. Will retry.');
      }
    }

    if (!recordTransaction) return { user: updatedUser, transaction: null, charged };

    const [transaction] = await Transaction.create(
      [
        {
          user: userId,
          type: TRANSACTION_TYPES.DEDUCTION,
          amount: -charged,
          balanceAfter: Math.max(0, updatedUser.credits),
          description,
          metadata,
        },
      ],
      sessionOpt
    );

    return { user: updatedUser, transaction, charged };
  }

  /**
   * Add `amount` to the single ledger entry of one GPU rental (one row per rental
   * and type, created on first use), so a running rental shows as one line in the
   * user's history instead of one per billing cycle.
   *
   * @param {Object} params
   * @param {*} params.userId
   * @param {*} params.gpuInstanceId
   * @param {string} params.type - TRANSACTION_TYPES.DEDUCTION or REFUND
   * @param {number} params.amount - signed change (negative for charges)
   * @param {number} params.balanceAfter
   * @param {string} params.description
   * @param {Object} params.metadata - replaces the entry's metadata (current totals)
   * @returns {Promise<Object>} the updated entry
   */
  async addToRentalEntry({ userId, gpuInstanceId, type, amount, balanceAfter, description, metadata }) {
    const filter = { user: userId, gpuInstance: gpuInstanceId, type };
    const update = {
      $inc: { amount },
      $set: { balanceAfter: Math.max(0, balanceAfter), description, metadata },
    };
    try {
      return await Transaction.findOneAndUpdate(filter, update, { upsert: true, returnDocument: 'after' });
    } catch (err) {
      // Two first writes raced on the unique index: the entry exists now.
      if (err?.code === 11000) {
        return Transaction.findOneAndUpdate(filter, update, { returnDocument: 'after' });
      }
      throw err;
    }
  }
}

export const creditService = new CreditService();
