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

/** Vast.ai prices storage per 30-day month. */
export const VAST_HOURS_PER_MONTH = 720;
/** Storage size used for offer prices when the client doesn't send one. */
export const DEFAULT_STORAGE_GB = 50;

const round = (n, decimals) => {
  const f = 10 ** decimals;
  return Math.round((n + Number.EPSILON) * f) / f;
};

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
   * The one pricing function for Vast.ai offers. Used for offer lists, the
   * estimate, rent and (via the stored totalCreditsPerHour) billing.
   *
   * Vast.ai units, checked against live offers on 8 Oct 2026:
   * - dph_base: compute $/hour.
   * - storage_cost: $/GB/month, with a 720-hour (30-day) month; for an offer
   *   searched with allocated_storage = G, dph_total - dph_base = storage_cost * G / 720.
   * - inet_down_cost / inet_up_cost: $/GB downloaded into / uploaded from the
   *   instance (internet_*_cost_per_tb = 1024 x these).
   *
   * credits = USD x (1 + markupPercentage / 100) x creditsPerUsd (both from PricingConfig).
   * Storage is priced for `storageGB` only, never the host's whole free disk.
   * Bandwidth is not part of the hourly total; it is billed by usage.
   *
   * @param {Object} raw - raw Vast.ai offer
   * @param {{ storageGB?: number, config?: Object }} [options]
   * @returns {Object} client fields (credits) plus `_internal` USD figures (never sent to clients).
   *   When Vast.ai did not report a needed field, priceAvailable is false and prices are null.
   */
  priceOffer(raw = {}, { storageGB = DEFAULT_STORAGE_GB, config = this._cachedConfig } = {}) {
    const gb = Math.round(Number(storageGB));
    const markupPercentage = Number(config.markupPercentage);
    const creditsPerUsd = Number(config.creditsPerUsd ?? config.tokenValue);
    const toCredits = (usd) => usd * (1 + markupPercentage / 100) * creditsPerUsd;
    const num = (v) => (v === null || v === undefined || v === '' ? NaN : Number(v));

    const dphBase = num(raw.dph_base);
    const storageCost = num(raw.storage_cost);
    const downCost = num(raw.inet_down_cost);
    const upCost = num(raw.inet_up_cost);

    const hourlyKnown =
      Number.isFinite(dphBase) && dphBase >= 0 && Number.isFinite(storageCost) && storageCost >= 0 &&
      Number.isFinite(gb) && gb > 0 && Number.isFinite(markupPercentage) && creditsPerUsd > 0;

    let compute = null;
    let storagePerHour = null;
    let total = null;
    let storagePerGBMonth = null;
    if (hourlyKnown) {
      compute = round(toCredits(dphBase), 2);
      storagePerGBMonth = round(toCredits(storageCost), 4);
      storagePerHour = round(toCredits((storageCost * gb) / VAST_HOURS_PER_MONTH), 2);
      // The components shown are the components summed: card, panel and billing agree to the cent.
      total = round(compute + storagePerHour, 2);
    }
    const perGB = (cost) => (Number.isFinite(cost) && cost >= 0 && creditsPerUsd > 0 ? round(toCredits(cost), 4) : null);

    return {
      priceAvailable: hourlyKnown,
      storageGB: gb,
      computeCreditsPerHour: compute,
      storageCreditsPerGBMonth: storagePerGBMonth,
      storageCreditsPerHour: storagePerHour,
      totalCreditsPerHour: total,
      bandwidthDownCreditsPerGB: perGB(downCost),
      bandwidthUpCreditsPerGB: perGB(upCost),
      bandwidthBilling: 'usage',
      // Names read by app versions up to v0.2.0.
      creditsPerHour: compute,
      bandwidthCreditsPerGB: perGB(downCost),
      _internal: {
        dphBaseUsd: Number.isFinite(dphBase) ? dphBase : null,
        storageUsdPerGBMonth: Number.isFinite(storageCost) ? storageCost : null,
        storageUsdPerHour: hourlyKnown ? (storageCost * gb) / VAST_HOURS_PER_MONTH : null,
        totalUsdPerHour: hourlyKnown ? dphBase + (storageCost * gb) / VAST_HOURS_PER_MONTH : null,
        bandwidthDownUsdPerGB: Number.isFinite(downCost) ? downCost : null,
        bandwidthUpUsdPerGB: Number.isFinite(upCost) ? upCost : null,
        markupPercentage,
        creditsPerUsd,
      },
    };
  }

  /**
   * A normalized offer with its prices recomputed for `storageGB`.
   * @param {Object} offer - from vastaiService.normalizeOffer (keeps rawOffer)
   * @param {number} storageGB
   */
  repriceOffer(offer, storageGB = DEFAULT_STORAGE_GB, config = this._cachedConfig) {
    if (!offer) return offer;
    return { ...offer, ...this.priceOffer(offer.rawOffer || {}, { storageGB, config }) };
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
   * Baseline storage credits for a storageGB (10GB - 1000GB) when no offer is
   * chosen yet (model recommendations). Offers are priced with priceOffer().
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
      throw new Error('calculateStoragePricing: price offers with priceOffer() instead.');
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
