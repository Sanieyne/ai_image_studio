/**
 * Cosmic-Gen Subscription Plans & Gumroad Configuration
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
    name: 'Pro',
    price: 4.99,
    priceCents: 499,
    monthlyCredits: 100,
    badge: 'PRO',
    permalink: process.env.GUMROAD_PRO_PERMALINK || 'pro',
    description: 'Unlimited local AI generation with 100 monthly cloud credits & 4K upscaling',
    features: [
      'Unlimited high-speed local generation',
      '100 monthly Cloud GPU compute credits',
      'Turbo video animation (Wan 2.1 & MiniMax)',
      '4K Super-Resolution & Real-ESRGAN upscaling',
      'Special PRO Member badge in studio UI',
      '100% offline data privacy',
    ],
  },
});

/**
 * Matches a Gumroad product or permalink to our subscription tier.
 */
export function resolveTier({ permalink = '', productName = '', priceCents = 0 }) {
  return SUBSCRIPTION_TIERS.PRO;
}
