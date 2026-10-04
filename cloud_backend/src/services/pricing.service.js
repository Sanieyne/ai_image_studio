/**
 * Dynamic Pricing & Token Conversion Engine
 * Single source of truth for token value (credits per USD) and markup percentage.
 * Provides real-time conversion for live offers, storage volumes, GPU hardware tiers, and admin controls.
 */

import mongoose from 'mongoose';
import { PricingConfig } from '../models/PricingConfig.js';
import {
  CREDITS_PER_USD,
  VASTAI_PRICE_MARKUP,
  STORAGE_MIN_GB,
  STORAGE_MAX_GB,
  STORAGE_RATE_PER_GB_MONTH,
  STORAGE_HOURS_PER_MONTH,
} from '../config/constants.js';

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
    const rawBandwidth = Number(raw.inet_down_cost || raw.bandwidthCostPerGB || 0.02);

    // Derive raw storage cost per GB per hour directly from the host offer
    let rawStoragePerGBHour;
    if (raw.storage_cost != null && !isNaN(Number(raw.storage_cost)) && Number(raw.storage_cost) > 0) {
      rawStoragePerGBHour = Number(raw.storage_cost);
    } else if (rawDphTotal > rawDphBase) {
      // Vast.ai default query bundles price storage at 100GB
      rawStoragePerGBHour = (rawDphTotal - rawDphBase) / 100;
    } else {
      rawStoragePerGBHour = 0.00015; // default fallback ($0.11/GB/mo)
    }

    const mult = this._cachedConfig.markupMultiplier || 1.25;
    const tokenVal = this._cachedConfig.tokenValue || 50;

    // 1. Marked-up USD rates (kept internal for billing & logs)
    const computePricePerHour = this.applyMarkup(rawDphBase, 4);
    const computeCreditsPerHour = this.usdToCredits(computePricePerHour, 1);

    const storagePricePerGBHour = this.applyMarkup(rawStoragePerGBHour, 6);
    const storageCreditsPerGBHour = Number((storagePricePerGBHour * tokenVal).toFixed(6));

    const defaultDiskGB = Number(raw.disk_space || 100);
    const storagePricePerHour = Math.round(storagePricePerGBHour * defaultDiskGB * 10000) / 10000;
    const storageCreditsPerHour = Math.round(storageCreditsPerGBHour * defaultDiskGB * 100) / 100;

    const totalHourlyCost = Math.round((computePricePerHour + storagePricePerHour) * 10000) / 10000;
    const totalCreditsPerHour = Math.round((computeCreditsPerHour + storageCreditsPerHour) * 10) / 10;

    const bandwidthCostPerGB = this.applyMarkup(rawBandwidth, 4);
    const bandwidthCreditsPerGB = this.usdToCredits(bandwidthCostPerGB, 2);

    return {
      // Server internal rates
      rawDphBase,
      rawDphTotal,
      rawStoragePerGBHour,
      computePricePerHour,
      storagePricePerGBHour,
      storagePricePerHour,
      bandwidthCostPerGB,
      totalHourlyCost,

      // Authoritative credits
      creditsPerHour: computeCreditsPerHour,
      storageCreditsPerHour,
      storageCreditsPerGBHour,
      totalCreditsPerHour,
      bandwidthCreditsPerGB,
      creditsPerUsd: tokenVal,
      markupPercentage: this._cachedConfig.markupPercentage,
    };
  }

  /**
   * Format GPU Tier pricing with server-computed credits (client-safe)
   * @param {Object} tier
   * @returns {Object}
   */
  formatTierPricing(tier = {}) {
    const basePrice = Number(tier.rawPricePerHour || tier.pricePerHour || 0.44);
    const markedUpPrice = this.applyMarkup(basePrice, 4);
    const creditsPerHour = this.usdToCredits(markedUpPrice, 1);

    const formatted = { ...tier, creditsPerHour };
    delete formatted.rawPricePerHour;
    delete formatted.pricePerHour;
    delete formatted.creditsPerUsd;
    delete formatted.markupPercentage;
    return formatted;
  }

  /**
   * Calculate storage credits dynamically for any continuous storageGB (10GB - 1000GB)
   * Uses the real per-offer Vast.ai rate when an offer is provided.
   * If no offer is provided, uses the baseline fallback rate.
   * @param {number|string} storageGB
   * @param {Object} [offer=null]
   * @returns {Object}
   */
  calculateStoragePricing(storageGB, offer = null) {
    const rawNum = typeof storageGB === 'string' ? parseFloat(storageGB.replace(/[^\d.]/g, '')) : Number(storageGB);
    const gb = Math.max(STORAGE_MIN_GB, Math.min(STORAGE_MAX_GB, Math.round(rawNum || 10)));
    const mult = this._cachedConfig.markupMultiplier || 1.25;
    const tokenVal = this._cachedConfig.tokenValue || 50;

    let storageCreditsPerGBHour;
    let storagePricePerGBHour;

    if (offer) {
      if (offer.storageCreditsPerGBHour != null && offer.storagePricePerGBHour != null) {
        storageCreditsPerGBHour = offer.storageCreditsPerGBHour;
        storagePricePerGBHour = offer.storagePricePerGBHour;
      } else {
        const rawOffer = offer.rawOffer || offer;
        let rawRate = Number(rawOffer.storage_cost);
        if (isNaN(rawRate) || rawRate <= 0) {
          const dphTotal = Number(rawOffer.dph_total || 0);
          const dphBase = Number(rawOffer.dph_base || 0);
          if (dphTotal > dphBase) {
            rawRate = (dphTotal - dphBase) / 100;
          } else {
            rawRate = 0.00015;
          }
        }
        storagePricePerGBHour = this.applyMarkup(rawRate, 6);
        storageCreditsPerGBHour = Number((storagePricePerGBHour * tokenVal).toFixed(6));
      }
    } else {
      // Baseline fallback rate when no offer is specified
      const rawPricePerMonth = gb * STORAGE_RATE_PER_GB_MONTH;
      const rawPricePerHour = rawPricePerMonth / STORAGE_HOURS_PER_MONTH;
      storagePricePerGBHour = (rawPricePerHour * mult) / gb;
      storageCreditsPerGBHour = Number((storagePricePerGBHour * tokenVal).toFixed(6));
    }

    const pricePerHour = Math.round(storagePricePerGBHour * gb * 10000) / 10000;
    const creditsPerHour = Math.round(storageCreditsPerGBHour * gb * 100) / 100;
    const creditsPerMonth = Math.round(creditsPerHour * 730);

    return {
      storageGB: gb,
      storageCreditsPerGBHour,
      creditsPerHour,
      creditsPerMonth,
      _internal: {
        storagePricePerGBHour,
        pricePerHour,
      },
    };
  }

  /**
   * Format Storage Plan pricing with continuous formula-based credits (client-safe)
   * Supports continuous numbers, legacy plan objects, and legacy plan ID strings ('30gb', etc.)
   * @param {Object|number|string} planOrGB
   * @returns {Object}
   */
  formatStoragePricing(planOrGB = {}) {
    let sizeGB = 50;
    let name = null;
    let id = null;

    if (typeof planOrGB === 'number') {
      sizeGB = planOrGB;
    } else if (typeof planOrGB === 'string') {
      const match = planOrGB.match(/\d+/);
      sizeGB = match ? parseInt(match[0], 10) : 50;
      id = planOrGB;
    } else if (typeof planOrGB === 'object' && planOrGB !== null) {
      sizeGB = Number(planOrGB.sizeGB || planOrGB.diskGB || 50);
      name = planOrGB.name;
      id = planOrGB.id;
    }

    const calculated = this.calculateStoragePricing(sizeGB);

    return {
      id: id || `${calculated.storageGB}gb`,
      name: name || `${calculated.storageGB}GB Storage`,
      sizeGB: calculated.storageGB,
      storageGB: calculated.storageGB,
      creditsPerHour: calculated.creditsPerHour,
      creditsPerMonth: calculated.creditsPerMonth,
    };
  }
}

export const pricingService = new PricingService();
