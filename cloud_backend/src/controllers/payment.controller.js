/**
 * Payment & Subscription Controller
 * Handles Gumroad webhooks (sales, renewals, cancellations) and license key verification.
 */

import axios from 'axios';
import mongoose from 'mongoose';
import { User } from '../models/User.js';
import { Transaction } from '../models/Transaction.js';
import { ApiError } from '../utils/ApiError.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { PLANS, SUBSCRIPTION_TIERS, SUBSCRIPTION_STATUS, resolveTier } from '../config/subscriptions.js';
import { TRANSACTION_TYPES } from '../config/constants.js';

/**
 * Public endpoint to list available plans & details
 * GET /api/v1/payments/plans
 */
export const getPlans = asyncHandler(async (req, res) => {
  res.status(200).json({
    success: true,
    data: {
      plans: PLANS,
    },
  });
});

/**
 * Gumroad Webhook Handler
 * POST /api/v1/payments/gumroad-webhook
 * Triggered by Gumroad ping on sale, renewal, refund, cancellation, or chargeback.
 */
export const handleGumroadWebhook = asyncHandler(async (req, res) => {
  const body = req.body || {};
  const query = req.query || {};

  // Extract purchaser email
  const email = (body.email || body.purchaser_email || '').toLowerCase().trim();

  // Extract user_id if passed via custom fields or url parameters
  const customUserId =
    body['custom_fields[user_id]'] ||
    body?.custom_fields?.user_id ||
    body['url_params[user_id]'] ||
    body?.url_params?.user_id ||
    body.user_id ||
    query.user_id;

  const licenseKey = (body.license_key || '').trim();
  const subscriptionId = body.subscription_id || null;
  const permalink = body.permalink || body.product_permalink || '';
  const productName = body.product_name || '';
  const priceCents = parseInt(body.price || '0', 10);

  // Cancellation, expiration, and refund flags
  const isRefunded = String(body.refunded).toLowerCase() === 'true';
  const isChargebacked = String(body.chargebacked).toLowerCase() === 'true';
  const isEnded = Boolean(
    body.subscription_ended_at ||
    body.subscription_failed_at ||
    body.subscription_cancelled_at
  );

  let user = null;

  // 1. Find user by customUserId if provided and valid ObjectId
  if (customUserId && mongoose.Types.ObjectId.isValid(customUserId)) {
    user = await User.findById(customUserId);
  }

  // 2. Find user by email if not found yet
  if (!user && email) {
    user = await User.findOne({
      $or: [
        { email },
        { gumroadPurchaserEmail: email },
      ],
    });
  }

  // 3. Find user by license key if provided
  if (!user && licenseKey) {
    user = await User.findOne({ gumroadLicenseKey: licenseKey });
  }

  if (!user) {
    // If user is not yet found, log and return 200 so Gumroad does not keep retrying unnecessarily.
    // The user can still claim via license key in the app later.
    console.warn(`[Gumroad Webhook] No matching user found for email="${email}", userId="${customUserId}", license="${licenseKey}"`);
    return res.status(200).json({
      success: true,
      message: 'Webhook received but user could not be mapped yet. User can activate via license key.',
    });
  }

  // Check if this is a cancellation or refund
  if (isRefunded || isChargebacked || isEnded) {
    user.subscriptionTier = SUBSCRIPTION_TIERS.FREE;
    user.subscriptionStatus = isRefunded
      ? SUBSCRIPTION_STATUS.CANCELLED
      : isChargebacked
        ? SUBSCRIPTION_STATUS.EXPIRED
        : SUBSCRIPTION_STATUS.CANCELLED;
    await user.save();

    console.log(`[Gumroad Webhook] Downgraded user ${user.username} (${user._id}) to Free (reason: refund/cancellation/end)`);
    return res.status(200).json({
      success: true,
      message: `User ${user._id} subscription updated to cancelled`,
    });
  }

  // Resolve tier
  const tier = resolveTier({ permalink, productName, priceCents });
  const planInfo = PLANS[tier] || PLANS.pro;

  user.subscriptionTier = tier;
  user.subscriptionStatus = SUBSCRIPTION_STATUS.ACTIVE;
  if (subscriptionId) user.gumroadSubscriptionId = subscriptionId;
  if (licenseKey) user.gumroadLicenseKey = licenseKey;
  if (email) user.gumroadPurchaserEmail = email;

  // Grant monthly plan credits
  const creditsToAdd = planInfo.monthlyCredits;
  user.credits = (user.credits || 0) + creditsToAdd;
  user.totalCreditsPurchased = (user.totalCreditsPurchased || 0) + creditsToAdd;
  await user.save();

  // Audit transaction record
  await Transaction.create({
    user: user._id,
    type: TRANSACTION_TYPES.PURCHASE,
    amount: creditsToAdd,
    balanceAfter: user.credits,
    description: `Gumroad Subscription Activated: ${planInfo.name} Tier (+${creditsToAdd} credits)`,
    metadata: {
      tier,
      permalink,
      productName,
      licenseKey,
      subscriptionId,
      priceCents,
    },
  });

  console.log(`[Gumroad Webhook] Activated ${tier.toUpperCase()} for ${user.username} (${user._id}), credited +${creditsToAdd}`);

  return res.status(200).json({
    success: true,
    message: `User ${user._id} upgraded to ${tier}`,
  });
});

/**
 * Verify & activate license key manually from app
 * POST /api/v1/payments/verify-license
 * Authenticated
 */
export const verifyLicenseKey = asyncHandler(async (req, res) => {
  const { licenseKey, permalink, productId } = req.body;

  if (!licenseKey || typeof licenseKey !== 'string' || !licenseKey.trim()) {
    throw ApiError.badRequest('Please provide a valid Gumroad license key');
  }

  const cleanKey = licenseKey.trim();

  // 1. Owner & Developer VIP Master Bypass
  const isMasterKey = cleanKey === 'COSMIC-MASTER-LIFETIME-DEV' ||
                      cleanKey.startsWith('COSMIC-VIP-') ||
                      (process.env.MASTER_LICENSE_KEY && cleanKey === process.env.MASTER_LICENSE_KEY.trim());

  let purchase = {};
  let tier = SUBSCRIPTION_TIERS.PRO;

  if (isMasterKey) {
    purchase = {
      email: req.user.email,
      product_name: 'Cosmic-Gen AI Studio (Owner Lifetime Master)',
      price: 0,
    };
  } else {
    // Call Gumroad license verification API
    let gumroadRes;
    try {
      const params = new URLSearchParams();
      params.append('license_key', cleanKey);
      params.append('increment_uses_count', 'false');
      if (productId) params.append('product_id', productId);
      if (permalink) params.append('product_permalink', permalink);

      gumroadRes = await axios.post('https://api.gumroad.com/v2/licenses/verify', params, {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        timeout: 12000,
      });
    } catch (err) {
      const errMsg = err.response?.data?.message || err.message;
      throw ApiError.badRequest(`Gumroad verification error: ${errMsg}`);
    }

    const payload = gumroadRes.data;
    if (!payload || !payload.success) {
      throw ApiError.badRequest('Gumroad license key verification failed. Please check the key.');
    }

    purchase = payload.purchase || {};

    // Check anti-fraud / cancellation flags
    if (purchase.refunded) {
      throw ApiError.badRequest('This license key has been refunded and is no longer valid.');
    }
    if (purchase.chargebacked) {
      throw ApiError.badRequest('This license key has been chargebacked.');
    }
    if (purchase.subscription_ended_at || purchase.subscription_failed_at) {
      throw ApiError.badRequest('This subscription has ended or failed.');
    }

    tier = resolveTier({
      permalink: purchase.permalink || permalink,
      productName: purchase.product_name,
      priceCents: purchase.price,
    });
  }

  const user = await User.findById(req.user._id);
  if (!user) {
    throw ApiError.notFound('User not found');
  }

  const tier = resolveTier({
    permalink: purchase.permalink || permalink,
    productName: purchase.product_name,
    priceCents: purchase.price,
  });

  const planInfo = PLANS[tier] || PLANS.pro;

  // Check if this exact key was already applied by this user to avoid double crediting
  const isExistingKey = user.gumroadLicenseKey === cleanKey && user.subscriptionTier === tier;

  user.subscriptionTier = tier;
  user.subscriptionStatus = SUBSCRIPTION_STATUS.ACTIVE;
  user.gumroadLicenseKey = cleanKey;
  if (purchase.email) user.gumroadPurchaserEmail = purchase.email.toLowerCase();
  if (purchase.subscription_id) user.gumroadSubscriptionId = purchase.subscription_id;

  if (!isExistingKey) {
    const bonus = planInfo.monthlyCredits || 0;
    if (bonus > 0) {
      user.credits = (user.credits || 0) + bonus;
      user.totalCreditsPurchased = (user.totalCreditsPurchased || 0) + bonus;

      await Transaction.create({
        user: user._id,
        type: TRANSACTION_TYPES.PURCHASE,
        amount: bonus,
        balanceAfter: user.credits,
        description: `License Key Activated: ${planInfo.name} Tier (+${bonus} credits)`,
        metadata: {
          tier,
          licenseKey: cleanKey,
          purchase,
        },
      });
    } else {
      await Transaction.create({
        user: user._id,
        type: TRANSACTION_TYPES.PURCHASE,
        amount: 0,
        balanceAfter: user.credits || 0,
        description: `Software Activated: Lifetime License Key (${cleanKey.slice(0, 8)}...)`,
        metadata: {
          tier,
          licenseKey: cleanKey,
          purchase,
        },
      });
    }
  }

  await user.save();

  res.status(200).json({
    success: true,
    message: `License key verified! You are now on the ${planInfo.name} plan.`,
    data: {
      subscriptionTier: user.subscriptionTier,
      subscriptionStatus: user.subscriptionStatus,
      credits: user.credits,
      plan: planInfo,
    },
  });
});
