/**
 * Model Catalog & Recommendation Routes
 * /api/v1/models
 */

import { Router } from 'express';
import {
  getModels,
  getCompatibilityMatrix,
  getUserSelection,
  updateUserSelection,
  recommend,
  estimateStorage,
  removeFromSelection,
  getModelById,
} from '../controllers/model.controller.js';
import { protect } from '../middleware/auth.middleware.js';
import { publicReadLimiter } from '../middleware/rateLimiter.middleware.js';

const router = Router();

// Public catalog and matrix discovery (permissive browsing limiter)
router.get('/', publicReadLimiter, getModels);
router.get('/compatibility/matrix', publicReadLimiter, getCompatibilityMatrix);

// Authenticated user model selection & cache management
router.get('/user/selection', protect, getUserSelection);
router.put('/user/selection', protect, updateUserSelection);
router.delete('/cache/:modelId', protect, removeFromSelection);

// Recommendations and storage calculations (publicly accessible for UI interactive previews)
router.post('/recommend', publicReadLimiter, recommend);
router.post('/storage/estimate', publicReadLimiter, estimateStorage);

// Specific model details (must be after explicit sub-paths)
router.get('/:modelId', publicReadLimiter, getModelById);

export default router;
