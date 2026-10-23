/**
 * Cosmic-Gen License & Software Purchase Configuration
 * One-time software purchase: $35.00 USD (Lifetime License)
 * No free cloud credits included (0 credits).
 * Cloud credits can be topped up separately as needed ($1.00 = 100 credits).
 */

export const SUBSCRIPTION_TIERS = Object.freeze({
  FREE: 'free',
  PRO: 'pro',
});

export const SUBSCRIPTION_STATUS = Object.freeze({
  NONE: 'none',
  ACTIVE: 'active',
  CANCELLED: 'cancelled',
  PAST_DUE: 'past_due',
  EXPIRED: 'expired',
});

export const PLANS = Object.freeze({
  pro: {
    id: 'pro',
    name: 'Lifetime License',
    price: 35.00,
    priceCents: 3500,
    monthlyCredits: 0, // No credits bundled with software purchase
    badge: 'LIFETIME',
    permalink: process.env.GUMROAD_PRO_PERMALINK || 'cosmicgen-license',
    description: 'Lifetime Software License with full offline local AI generation & hardware access',
    features: [
      'One-time purchase ($35 USD) — Lifetime software ownership',
      'Zero subscription fees or recurring monthly charges',
      'Unlimited high-speed local generation (SDXL, SD 1.5, LoRAs)',
      '100% offline data privacy & local GPU acceleration',
      'Pay-as-you-go optional cloud credits top-up',
      'Hardware-encrypted license key verification',
    ],
  },
});

/**
 * Matches a Gumroad product or permalink to our tier.
 */
export function resolveTier({ permalink = '', productName = '', priceCents = 0 }) {
  return SUBSCRIPTION_TIERS.PRO;
}
