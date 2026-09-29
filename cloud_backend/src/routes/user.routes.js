/**
 * User & Credits Routes
 * Endpoints for current user profile, credits balance, and paginated transaction history.
 */

import { Router } from 'express';
import {
  getMe,
  getCredits,
  getTransactions,
  getPublicProfile,
  updateProfile,
} from '../controllers/user.controller.js';
import { protect } from '../middleware/auth.middleware.js';
import { publicReadLimiter } from '../middleware/rateLimiter.middleware.js';
import { validate, updateProfileSchema } from '../middleware/validation.middleware.js';

const router = Router();

// Public profile endpoint (unauthenticated, permissive browsing limiter)
router.get('/:username/public', publicReadLimiter, getPublicProfile);

// Authenticated user endpoints
router.use(protect);

router.get('/me', getMe);
router.patch('/me/profile', validate(updateProfileSchema, { stripUnknown: false }), updateProfile);
router.get('/credits', getCredits);
router.get('/transactions', getTransactions);

export default router;

