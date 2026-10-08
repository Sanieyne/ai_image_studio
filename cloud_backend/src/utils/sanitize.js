/**
 * Client-Facing Response Sanitizers
 * Strips all internal raw USD, dollar metrics, and markup internals from client payloads.
 * Only server-authoritative credit rates leave the server for user clients.
 */

/**
 * Sanitize marketplace offer for client responses
 * @param {Object} offer
 * @returns {Object}
 */
export function sanitizeOfferForClient(offer) {
  if (!offer) return offer;
  const o = typeof offer.toObject === 'function' ? offer.toObject() : { ...offer };

  delete o.pricePerHour;
  delete o.dphBase;
  delete o.storageCostPerHour;
  delete o.storagePricePerGBHour;
  delete o.bandwidthCostPerGB;
  delete o.totalHourlyCost;
  delete o.rawStorageCostPerGBHour;
  delete o.creditsPerUsd;
  delete o.markupPercentage;
  delete o.estimatedMonthlyBandwidthCost;
  delete o.rawOffer;
  delete o._internal;

  return o;
}

/**
 * Sanitize GPU Instance for client responses
 * @param {Object} instance
 * @returns {Object}
 */
export function sanitizeInstanceForClient(instance) {
  if (!instance) return instance;
  const doc = typeof instance.toObject === 'function' ? instance.toObject() : { ...instance };

  delete doc.costPerHour;
  delete doc.creditsPerUsd;
  delete doc._internal;

  if (doc.pricing) {
    const p = doc.pricing;
    doc.pricing = {
      storageGB: p.storageGB,
      computeCreditsPerHour: p.computeCreditsPerHour ?? p.creditsPerHour,
      storageCreditsPerGBMonth: p.storageCreditsPerGBMonth,
      storageCreditsPerHour: p.storageCreditsPerHour,
      totalCreditsPerHour: p.totalCreditsPerHour,
      bandwidthDownCreditsPerGB: p.bandwidthDownCreditsPerGB ?? p.bandwidthCreditsPerGB,
      bandwidthUpCreditsPerGB: p.bandwidthUpCreditsPerGB,
      bandwidthBilling: 'usage',
      // Older names, read by app versions up to v0.2.0.
      creditsPerHour: p.creditsPerHour,
      bandwidthCreditsPerGB: p.bandwidthCreditsPerGB,
    };
  }

  if (doc.vastOffer) {
    doc.vastOffer = sanitizeOfferForClient(doc.vastOffer);
  }

  return doc;
}
