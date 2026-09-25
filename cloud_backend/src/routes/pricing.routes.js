/**
 * Pricing & Token Configuration Routes
 * /api/v1/pricing
 */

import { Router } from 'express';
import { getPricingConfig, updatePricingConfig } from '../controllers/pricing.controller.js';
import { protect, authorize } from '../middleware/auth.middleware.js';
import { ROLES } from '../config/constants.js';

const router = Router();

// Public / client route to fetch current server credit conversion rates
router.get('/config', getPricingConfig);

// Admin-managed route to update token value and markup percentage
router.put('/config', protect, authorize(ROLES.ADMIN), updatePricingConfig);

export default router;
