/**
 * Cosmic-Gen Subscription Plans & Gumroad Configuration
 */

export const SUBSCRIPTION_TIERS = Object.freeze({
  FREE: 'free',
  STARTER: 'starter',
  PRO: 'pro',
  VIP: 'vip',
});

export const SUBSCRIPTION_STATUS = Object.freeze({
  NONE: 'none',
  ACTIVE: 'active',
  CANCELLED: 'cancelled',
  PAST_DUE: 'past_due',
  EXPIRED: 'expired',
});

export const PLANS = Object.freeze({
  starter: {
    id: 'starter',
    name: 'Starter',
    price: 4.99,
    priceCents: 499,
    monthlyCredits: 100,
    badge: 'STARTER',
    permalink: process.env.GUMROAD_STARTER_PERMALINK || 'starter',
    description: 'Essential local generation with standard DeepFace webcam swap',
    features: [
      'Unlimited local image generation',
      'Standard DeepFace webcam swap (640×480)',
      '100 monthly Cloud GPU compute credits',
      '100% offline private processing',
      'Community support',
    ],
  },
  pro: {
    id: 'pro',
    name: 'Pro',
    price: 9.99,
    priceCents: 999,
    monthlyCredits: 500,
    badge: 'PRO',
    permalink: process.env.GUMROAD_PRO_PERMALINK || 'pro',
    description: 'For creators, streamers & power users requiring HD quality & fast turnaround',
    features: [
      'Unlimited high-speed local generation',
      'HD Live DeepFace Webcam streaming (1080p)',
      '4K Super-Resolution & Real-ESRGAN upscaling',
      '500 monthly Cloud GPU compute credits',
      'Turbo video generation (Wan 2.1 & MiniMax)',
      'Special PRO Member badge in studio UI',
    ],
  },
  vip: {
    id: 'vip',
    name: 'VIP',
    price: 19.99,
    priceCents: 1999,
    monthlyCredits: 2000,
    badge: 'VIP',
    permalink: process.env.GUMROAD_VIP_PERMALINK || 'vip',
    description: 'Ultimate studio tier with dedicated GPU resources and commercial rights',
    features: [
      'All Pro tier perks & capabilities included',
      'Ultra HD 4K Live DeepFace Webcam streaming',
      'Priority Dedicated Cloud GPU instances',
      '2,000 monthly Cloud GPU compute credits',
      'Commercial licensing & royalty-free output',
      'Exclusive glowing VIP Member badge & priority developer support',
    ],
  },
});

/**
 * Matches a Gumroad product or permalink to our subscription tier.
 */
export function resolveTier({ permalink = '', productName = '', priceCents = 0 }) {
  const normLink = String(permalink).toLowerCase();
  const normName = String(productName).toLowerCase();

  if (normLink.includes('vip') || normName.includes('vip') || priceCents >= 1500) {
    return SUBSCRIPTION_TIERS.VIP;
  }
  if (normLink.includes('starter') || normName.includes('starter') || (priceCents >= 400 && priceCents < 800)) {
    return SUBSCRIPTION_TIERS.STARTER;
  }
  if (normLink.includes('pro') || normName.includes('pro') || (priceCents >= 800 && priceCents < 1500)) {
    return SUBSCRIPTION_TIERS.PRO;
  }
  return SUBSCRIPTION_TIERS.PRO; // Default paid tier
}
