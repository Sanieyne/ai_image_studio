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
  getRentalsStatus,
  destroyInstance,
  estimatePricing,
  getGpuSeries,
} from '../controllers/gpu.controller.js';
import { protect } from '../middleware/auth.middleware.js';
import { env } from '../config/env.js';
import { ApiError } from '../utils/ApiError.js';
import { GPU_PROVIDER_UNAVAILABLE_MESSAGE } from '../services/vastai.service.js';
import { publicReadLimiter } from '../middleware/rateLimiter.middleware.js';
import {
  validate,
  validateQuery,
  rentGpuSchema,
  estimatePricingSchema,
} from '../middleware/validation.middleware.js';

const router = Router();

// Whether rentals are open is answered even without a Vast.ai key.
router.get('/rentals/status', publicReadLimiter, getRentalsStatus);

// Without a Vast.ai key, production has no real GPU data to serve: answer 503
// instead of empty or simulated results.
router.use((req, res, next) => {
  if (env.isProduction && !env.VASTAI_API_KEY) {
    return next(ApiError.serviceUnavailable(GPU_PROVIDER_UNAVAILABLE_MESSAGE));
  }
  return next();
});

// Public marketplace browsing and pricing discovery (permissive browsing limiter)
router.get('/offers', publicReadLimiter, getOffers);
router.get('/series', publicReadLimiter, getGpuSeries);
router.get('/recommended', publicReadLimiter, getRecommended);
router.get('/pricing/estimate', publicReadLimiter, validateQuery(estimatePricingSchema), estimatePricing);
router.get('/offers/:offerId', publicReadLimiter, getOfferById);

// Authenticated instance provisioning and lifecycle management
router.post('/rent', protect, validate(rentGpuSchema), rent);
router.get('/instances/me', protect, getMyInstances);
router.get('/instances/:instanceId', protect, getInstanceById);
router.delete('/instances/:instanceId', protect, destroyInstance);

export default router;
