/**
 * Price Tracker & Real-Time Burn Rate Engine
 * Calculates instance hourly burn rates, live credit ticker consumption, and low balance warnings.
 */

import { GpuInstance } from '../models/GpuInstance.js';
import { User } from '../models/User.js';
import { ApiError } from '../utils/ApiError.js';

/** The rate billing charges: stored on the instance at rent time. Never estimated here. */
const rateOf = (instance) => instance.pricing?.totalCreditsPerHour ?? 0;

class PriceTrackerService {
  /**
   * Calculate granular burn rates across time granularities
   * @param {Object} instance - GpuInstance document or object
   * @returns {Object}
   */
  calculateBurnRate(instance) {
    const creditsPerHour = rateOf(instance);

    const creditsPerMinute = Math.round((creditsPerHour / 60) * 1000) / 1000;
    const creditsPerSecond = Math.round((creditsPerHour / 3600) * 100000) / 100000;
    const dailyCredits = Math.round(creditsPerHour * 24 * 10) / 10;
    const monthlyCredits = Math.round(creditsPerHour * 24 * 30 * 10) / 10;

    return {
      creditsPerHour,
      creditsPerMinute,
      creditsPerSecond,
      dailyCredits,
      monthlyCredits,
    };
  }

  /**
   * Track real-time credits consumed since instance launch for live UI ticker
   * @param {string} instanceId
   * @returns {Promise<Object>}
   */
  async trackPriceEat(instanceId) {
    const instance = await GpuInstance.findById(instanceId).lean();
    if (!instance) {
      throw ApiError.notFound(`GPU instance not found with ID: ${instanceId}`);
    }

    const user = await User.findById(instance.user).select('credits username email').lean();
    if (!user) {
      throw ApiError.notFound('Owner user not found.');
    }

    const startTime = (instance.startedAt || instance.createdAt || new Date()).getTime();
    const now = instance.stoppedAt ? new Date(instance.stoppedAt).getTime() : Date.now();
    const elapsedSeconds = Math.max(0, Math.floor((now - startTime) / 1000));
    const hoursElapsed = elapsedSeconds / 3600;

    const creditsRatePerHour = rateOf(instance);
    // Real ledger figures from billing, not an estimate from elapsed time.
    const creditsCharged = Math.round((instance.creditsCharged || 0) * 100) / 100;
    const creditsRefunded = Math.round((instance.creditsRefunded || 0) * 100) / 100;
    const creditsBurnedSoFar = Math.round((creditsCharged - creditsRefunded) * 100) / 100;

    const burnRate = this.calculateBurnRate(instance);
    const lowBalanceWarning = user.credits < creditsRatePerHour * 2;

    return {
      instanceId: String(instance._id),
      gpuType: instance.gpuType,
      status: instance.status,
      elapsedSeconds,
      hoursElapsed: Math.round(hoursElapsed * 100) / 100,
      creditsBurnedSoFar,
      creditsCharged,
      creditsRefunded,
      billedUntil: instance.billedUntil || null,
      currentBalance: user.credits,
      // Charges are already deducted from the balance.
      creditsRemaining: Math.max(0, Math.round(user.credits * 10) / 10),
      burnRate,
      lowBalanceWarning,
      warningMessage: lowBalanceWarning
        ? `Warning: Balance (${user.credits.toFixed(1)} credits) is below 2 hours of runtime for ${instance.gpuType}. Please recharge credits.`
        : null,
    };
  }

  /**
   * Check if user account is at risk of premature termination due to low balance
   * @param {string} userId
   * @param {Object} instance
   * @returns {Promise<Object>}
   */
  async checkLowBalance(userId, instance) {
    const user = await User.findById(userId).select('credits').lean();
    if (!user) return { isLow: false, credits: 0 };

    const creditsRatePerHour = rateOf(instance);
    const isLow = user.credits < creditsRatePerHour * 2;

    return {
      isLow,
      currentCredits: user.credits,
      creditsRatePerHour,
      hoursRemaining: creditsRatePerHour > 0 ? Math.round((user.credits / creditsRatePerHour) * 10) / 10 : 0,
      message: isLow
        ? `Your balance (${user.credits.toFixed(2)}) will deplete in less than 2 hours.`
        : 'Credit balance healthy.',
    };
  }
}

export const priceTrackerService = new PriceTrackerService();
