/**
 * Pricing & Token Value Controller
 * Exposes endpoints for inspecting system credit conversion rates and administrative margin management.
 */

import { asyncHandler } from '../utils/asyncHandler.js';
import { pricingService } from '../services/pricing.service.js';

/**
 * GET /api/v1/pricing/config
 * Public/authenticated endpoint to fetch active token-to-USD rate and markup percentage.
 */
export const getPricingConfig = asyncHandler(async (req, res) => {
  const config = await pricingService.getConfig();

  res.status(200).json({
    success: true,
    data: config,
  });
});

/**
 * PUT /api/v1/pricing/config
 * Admin-only endpoint to update token value (credits per USD) and pricing markup percentage.
 */
export const updatePricingConfig = asyncHandler(async (req, res) => {
  const { tokenValue, markupPercentage, minLaunchCredits, notes } = req.body;

  const updated = await pricingService.updateConfig({
    tokenValue,
    markupPercentage,
    minLaunchCredits,
    notes,
    updatedBy: req.user?.username || 'admin',
  });

  res.status(200).json({
    success: true,
    message: 'System pricing configuration and token value updated successfully.',
    data: updated,
  });
});
