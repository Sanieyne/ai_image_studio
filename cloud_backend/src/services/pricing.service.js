/**
 * Dynamic Pricing & Token Conversion Engine
 * Single source of truth for token value (credits per USD) and markup percentage.
 * Provides real-time conversion for live offers, storage volumes, GPU hardware tiers, and admin controls.
 */

import mongoose from 'mongoose';
import { PricingConfig } from '../models/PricingConfig.js';
import { CREDITS_PER_USD, VASTAI_PRICE_MARKUP } from '../config/constants.js';

class PricingService {
  constructor() {
    this._cachedConfig = {
      tokenValue: CREDITS_PER_USD || 50,
      markupPercentage: 25,
      markupMultiplier: VASTAI_PRICE_MARKUP || 1.25,
      minLaunchCredits: 10,
      updatedAt: new Date(),
    };
    this._cacheTime = 0;
    this._cacheTtlMs = 15000; // 15 seconds cache
  }

  /**
   * Fetch active pricing configuration with in-memory caching and resilient DB fallback.
   * @returns {Promise<Object>}
   */
  async getConfig() {
    const now = Date.now();
    if (this._cacheTime && now - this._cacheTime < this._cacheTtlMs) {
      return this._cachedConfig;
    }

    try {
      if (mongoose.connection?.readyState === 1) {
        let configDoc = await PricingConfig.findOne({ isActive: true })
          .sort({ updatedAt: -1 })
          .maxTimeMS(2000)
          .lean();

        if (!configDoc) {
          // Initialize default configuration record
          const created = await PricingConfig.create({
            tokenValue: CREDITS_PER_USD || 50,
            markupPercentage: 25,
            minLaunchCredits: 10,
            notes: 'Default initial pricing configuration',
          });
          configDoc = created.toObject();
        }

        const markupPercentage = Number(configDoc.markupPercentage) || 25;
        this._cachedConfig = {
          id: String(configDoc._id),
          tokenValue: Number(configDoc.tokenValue) || 50,
          creditsPerUsd: Number(configDoc.tokenValue) || 50,
          markupPercentage,
          markupMultiplier: Math.round((1 + markupPercentage / 100) * 1000) / 1000,
          minLaunchCredits: Number(configDoc.minLaunchCredits) || 10,
          updatedBy: configDoc.updatedBy || 'system',
          notes: configDoc.notes,
          updatedAt: configDoc.updatedAt || new Date(),
        };
        this._cacheTime = now;
      }
    } catch (_) {
      // In case of transient DB timeout or error, keep utilizing last valid cache
    }

    return this._cachedConfig;
  }

  /**
   * Synchronous getter for current cached configuration
   */
  getCachedConfig() {
    return this._cachedConfig;
  }

  /**
   * Update pricing policy (Admin Management)
   * @param {Object} params - { tokenValue, markupPercentage, minLaunchCredits, updatedBy, notes }
   * @returns {Promise<Object>}
   */
  async updateConfig(params = {}) {
    const { tokenValue, markupPercentage, minLaunchCredits, updatedBy = 'admin', notes } = params;

    const updates = {};
    if (tokenValue !== undefined) {
      const val = Number(tokenValue);
      if (isNaN(val) || val <= 0) throw new Error('tokenValue must be a positive number');
      updates.tokenValue = val;
    }

    if (markupPercentage !== undefined) {
      const val = Number(markupPercentage);
      if (isNaN(val) || val < 0) throw new Error('markupPercentage cannot be negative');
      updates.markupPercentage = val;
    }

    if (minLaunchCredits !== undefined) {
      const val = Number(minLaunchCredits);
      if (isNaN(val) || val < 0) throw new Error('minLaunchCredits cannot be negative');
      updates.minLaunchCredits = val;
    }

    if (notes) updates.notes = String(notes);
    updates.updatedBy = String(updatedBy);
    updates.isActive = true;

    let updatedDoc;
    if (mongoose.connection?.readyState === 1) {
      updatedDoc = await PricingConfig.findOneAndUpdate(
        { isActive: true },
        { $set: updates },
        { new: true, upsert: true, setDefaultsOnInsert: true }
      ).lean();
    } else {
      updatedDoc = { ...this._cachedConfig, ...updates, updatedAt: new Date() };
    }

    const pct = Number(updatedDoc.markupPercentage ?? this._cachedConfig.markupPercentage);
    const tokenVal = Number(updatedDoc.tokenValue ?? this._cachedConfig.tokenValue);

    this._cachedConfig = {
      id: updatedDoc._id ? String(updatedDoc._id) : 'dynamic',
      tokenValue: tokenVal,
      creditsPerUsd: tokenVal,
      markupPercentage: pct,
      markupMultiplier: Math.round((1 + pct / 100) * 1000) / 1000,
      minLaunchCredits: Number(updatedDoc.minLaunchCredits ?? this._cachedConfig.minLaunchCredits),
      updatedBy: updatedDoc.updatedBy,
      notes: updatedDoc.notes,
      updatedAt: updatedDoc.updatedAt || new Date(),
    };
    this._cacheTime = Date.now();

    return this._cachedConfig;
  }

  /**
   * Apply percentage markup to raw USD cost
   * @param {number} rawUsd
   * @param {number} [decimals=4]
   * @returns {number}
   */
  applyMarkup(rawUsd, decimals = 4) {
    const mult = this._cachedConfig.markupMultiplier || 1.25;
    const factor = Math.pow(10, decimals);
    return Math.round((Number(rawUsd) || 0) * mult * factor) / factor;
  }

  /**
   * Convert marked-up USD amount to credits
   * @param {number} markedUpUsd
   * @param {number} [decimals=1]
   * @returns {number}
   */
  usdToCredits(markedUpUsd, decimals = 1) {
    const rate = this._cachedConfig.tokenValue || 50;
    const factor = Math.pow(10, decimals);
    return Math.round((Number(markedUpUsd) || 0) * rate * factor) / factor;
  }

  /**
   * Convert raw USD amount (applying markup first) directly to credits
   * @param {number} rawUsd
   * @param {number} [decimals=1]
   * @returns {number}
   */
  rawUsdToCredits(rawUsd, decimals = 1) {
    const markedUp = this.applyMarkup(rawUsd, 6);
    return this.usdToCredits(markedUp, decimals);
  }

  /**
   * Format complete pricing and credit metadata for a marketplace offer
   * @param {Object} raw
   * @returns {Object}
   */
  formatOfferPricing(raw = {}) {
    const rawDphTotal = Number(raw.dph_total || raw.pricePerHour || 0.44);
    const rawDphBase = Number(raw.dph_base || raw.dphBase || rawDphTotal);
    const rawStorage = Math.max(0, rawDphTotal - rawDphBase);
    const rawBandwidth = Number(raw.inet_down_cost || raw.bandwidthCostPerGB || 0.02);

    // 1. Marked up USD rates
    const dphTotal = this.applyMarkup(rawDphTotal, 4);
    const dphBase = this.applyMarkup(rawDphBase, 4);
    const storageCostPerHour = this.applyMarkup(rawStorage, 4);
    const bandwidthCostPerGB = this.applyMarkup(rawBandwidth, 4);
    const totalHourlyCost = dphTotal;

    // 2. Credits conversion (Server authoritative)
    const creditsPerHour = this.usdToCredits(dphTotal, 1);
    const totalCreditsPerHour = this.usdToCredits(totalHourlyCost, 1);
    const storageCreditsPerHour = this.usdToCredits(storageCostPerHour, 2);
    const bandwidthCreditsPerGB = this.usdToCredits(bandwidthCostPerGB, 2);

    return {
      pricePerHour: dphTotal,
      dphBase,
      storageCostPerHour,
      bandwidthCostPerGB,
      totalHourlyCost,
      creditsPerHour,
      totalCreditsPerHour,
      storageCreditsPerHour,
      bandwidthCreditsPerGB,
      creditsPerUsd: this._cachedConfig.tokenValue,
      markupPercentage: this._cachedConfig.markupPercentage,
    };
  }

  /**
   * Format GPU Tier pricing with server-computed credits
   * @param {Object} tier
   * @returns {Object}
   */
  formatTierPricing(tier = {}) {
    const basePrice = Number(tier.rawPricePerHour || tier.pricePerHour || 0.44);
    const markedUpPrice = this.applyMarkup(basePrice, 4);
    const creditsPerHour = this.usdToCredits(markedUpPrice, 1);

    return {
      ...tier,
      pricePerHour: markedUpPrice,
      creditsPerHour,
      creditsPerUsd: this._cachedConfig.tokenValue,
      markupPercentage: this._cachedConfig.markupPercentage,
    };
  }

  /**
   * Format Storage Plan pricing with server-computed credits
   * @param {Object} plan
   * @returns {Object}
   */
  formatStoragePricing(plan = {}) {
    const basePricePerMonth = Number(plan.rawPricePerMonth || plan.pricePerMonth || 5.0);
    const markedUpMonth = this.applyMarkup(basePricePerMonth, 2);
    const creditsPerMonth = this.usdToCredits(markedUpMonth, 0);
    const creditsPerHour = Math.round((creditsPerMonth / 720) * 100) / 100;

    return {
      ...plan,
      pricePerMonth: markedUpMonth,
      creditsPerMonth,
      creditsPerHour,
      creditsPerUsd: this._cachedConfig.tokenValue,
      markupPercentage: this._cachedConfig.markupPercentage,
    };
  }
}

export const pricingService = new PricingService();
