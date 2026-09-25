/**
 * Price Tracker & Real-Time Burn Rate Engine
 * Calculates instance hourly burn rates, live credit ticker consumption, and low balance warnings.
 */

import { GpuInstance } from '../models/GpuInstance.js';
import { User } from '../models/User.js';
import { BANDWIDTH_COST_PER_GB } from '../config/constants.js';
import { pricingService } from './pricing.service.js';
import { ApiError } from '../utils/ApiError.js';

class PriceTrackerService {
  /**
   * Calculate granular burn rates across time granularities
   * @param {Object} instance - GpuInstance document or object
   * @returns {Object}
   */
  calculateBurnRate(instance) {
    const creditsPerHour =
      instance.pricing?.totalCreditsPerHour ??
      instance.pricing?.creditsPerHour ??
      pricingService.usdToCredits(instance.pricing?.totalPerHour ?? instance.costPerHour ?? 0.44, 1);

    const creditsPerMinute = Math.round((creditsPerHour / 60) * 1000) / 1000;
    const creditsPerSecond = Math.round((creditsPerHour / 3600) * 100000) / 100000;
    const dailyCredits = Math.round(creditsPerHour * 24 * 10) / 10;
    const monthlyCredits = Math.round(creditsPerHour * 24 * 30 * 10) / 10;

    const perHour = instance.pricing?.totalPerHour ?? instance.costPerHour ?? 0.44;
    const perMinute = Math.round((perHour / 60) * 10000) / 10000;
    const perSecond = Math.round((perHour / 3600) * 100000) / 100000;
    const daily = Math.round(perHour * 24 * 100) / 100;
    const monthly = Math.round(perHour * 24 * 30 * 100) / 100;

    const storageEstimate = Math.round(((instance.pricing?.storageCost || 0.02) * 24 * 30) * 100) / 100;
    const bandwidthEstimate = Math.round((100 * BANDWIDTH_COST_PER_GB) * 100) / 100;

    return {
      creditsPerHour,
      creditsPerMinute,
      creditsPerSecond,
      dailyCredits,
      monthlyCredits,
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

    const creditsRatePerHour =
      instance.pricing?.totalCreditsPerHour ??
      instance.pricing?.creditsPerHour ??
      pricingService.usdToCredits(ratePerHour, 1);
    const creditsBurnedSoFar = Math.round(hoursElapsed * creditsRatePerHour * 10) / 10;

    const burnRate = this.calculateBurnRate(instance);
    const lowBalanceWarning = user.credits < creditsRatePerHour * 2;

    return {
      instanceId: String(instance._id),
      gpuType: instance.gpuType,
      status: instance.status,
      elapsedSeconds,
      hoursElapsed: Math.round(hoursElapsed * 100) / 100,
      totalCostSoFar,
      creditsBurnedSoFar,
      currentBalance: user.credits,
      creditsRemaining: Math.max(0, Math.round((user.credits - creditsBurnedSoFar) * 10) / 10),
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

    const ratePerHour = instance.pricing?.totalPerHour || instance.costPerHour || 0.44;
    const creditsRatePerHour =
      instance.pricing?.totalCreditsPerHour ??
      instance.pricing?.creditsPerHour ??
      pricingService.usdToCredits(ratePerHour, 1);
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
