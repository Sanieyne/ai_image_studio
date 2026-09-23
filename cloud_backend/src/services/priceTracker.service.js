/**
 * Price Tracker & Real-Time Burn Rate Engine
 * Calculates instance hourly burn rates, live credit ticker consumption, and low balance warnings.
 */

import { GpuInstance } from '../models/GpuInstance.js';
import { User } from '../models/User.js';
import { BANDWIDTH_COST_PER_GB } from '../config/constants.js';
import { ApiError } from '../utils/ApiError.js';

class PriceTrackerService {
  /**
   * Calculate granular burn rates across time granularities
   * @param {Object} instance - GpuInstance document or object
   * @returns {Object}
   */
  calculateBurnRate(instance) {
    const perHour = instance.pricing?.totalPerHour ?? instance.costPerHour ?? 0.44;
    const perMinute = Math.round((perHour / 60) * 10000) / 10000;
    const perSecond = Math.round((perHour / 3600) * 100000) / 100000;
    const daily = Math.round(perHour * 24 * 100) / 100;
    const monthly = Math.round(perHour * 24 * 30 * 100) / 100;

    const storageEstimate = Math.round(((instance.pricing?.storageCost || 0.02) * 24 * 30) * 100) / 100;
    const bandwidthEstimate = Math.round((100 * BANDWIDTH_COST_PER_GB) * 100) / 100;

    return {
      perHour,
      perMinute,
      perSecond,
      daily,
      monthly,
      storageEstimate,
      bandwidthEstimate,
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

    const ratePerHour = instance.pricing?.totalPerHour || instance.costPerHour || 0.44;
    const totalCostSoFar = Math.round(hoursElapsed * ratePerHour * 1000) / 1000;

    const burnRate = this.calculateBurnRate(instance);
    const lowBalanceWarning = user.credits < ratePerHour * 2;

    return {
      instanceId: String(instance._id),
      gpuType: instance.gpuType,
      status: instance.status,
      elapsedSeconds,
      hoursElapsed: Math.round(hoursElapsed * 100) / 100,
      totalCostSoFar,
      currentBalance: user.credits,
      creditsRemaining: Math.max(0, Math.round((user.credits - totalCostSoFar) * 1000) / 1000),
      burnRate,
      lowBalanceWarning,
      warningMessage: lowBalanceWarning
        ? `Warning: Balance (${user.credits.toFixed(2)}) is below 2 hours of runtime for ${instance.gpuType}. Please recharge credits.`
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

    const ratePerHour = instance.pricing?.totalPerHour || instance.costPerHour || 0.44;
    const isLow = user.credits < ratePerHour * 2;

    return {
      isLow,
      currentCredits: user.credits,
      ratePerHour,
      hoursRemaining: ratePerHour > 0 ? Math.round((user.credits / ratePerHour) * 10) / 10 : 0,
      message: isLow
        ? `Your balance (${user.credits.toFixed(2)}) will deplete in less than 2 hours.`
        : 'Credit balance healthy.',
    };
  }
}

export const priceTrackerService = new PriceTrackerService();
