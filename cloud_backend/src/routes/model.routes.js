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

const router = Router();

// Public catalog and matrix discovery
router.get('/', getModels);
router.get('/compatibility/matrix', getCompatibilityMatrix);

// Authenticated user model selection & cache management
router.get('/user/selection', protect, getUserSelection);
router.put('/user/selection', protect, updateUserSelection);
router.delete('/cache/:modelId', protect, removeFromSelection);

// Recommendations and storage calculations (publicly accessible for UI interactive previews)
router.post('/recommend', recommend);
router.post('/storage/estimate', estimateStorage);

// Specific model details (must be after explicit sub-paths)
router.get('/:modelId', getModelById);

export default router;
