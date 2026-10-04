/**
 * GPU Marketplace & Cloud Instance Routes
 * /api/v1/gpu
 */

import { Router } from 'express';
import {
  getOffers,
  getOfferById,
  getRecommended,
  rent,
  getMyInstances,
  getInstanceById,
  destroyInstance,
  estimatePricing,
} from '../controllers/gpu.controller.js';
import { protect } from '../middleware/auth.middleware.js';
import { publicReadLimiter } from '../middleware/rateLimiter.middleware.js';
import {
  validate,
  validateQuery,
  rentGpuSchema,
  estimatePricingSchema,
} from '../middleware/validation.middleware.js';

const router = Router();

// Public marketplace browsing and pricing discovery (permissive browsing limiter)
router.get('/offers', publicReadLimiter, getOffers);
router.get('/recommended', publicReadLimiter, getRecommended);
router.get('/pricing/estimate', publicReadLimiter, validateQuery(estimatePricingSchema), estimatePricing);
router.get('/offers/:offerId', publicReadLimiter, getOfferById);

// Authenticated instance provisioning and lifecycle management
router.post('/rent', protect, validate(rentGpuSchema), rent);
router.get('/instances/me', protect, getMyInstances);
router.get('/instances/:instanceId', protect, getInstanceById);
router.delete('/instances/:instanceId', protect, destroyInstance);

export default router;
