/**
 * Generation Routes
 * Handles user-saved generation CRUD endpoints under /api/v1/generations
 */

import { Router } from 'express';
import { protect } from '../middleware/auth.middleware.js';
import { validate, createGenerationSchema } from '../middleware/validation.middleware.js';
import {
  saveGeneration,
  getMyGenerations,
  getGenerationById,
  deleteGeneration,
  publishGeneration,
  unpublishGeneration,
} from '../controllers/generation.controller.js';

const router = Router();

// All generation routes require authentication
router.use(protect);

router.post('/', validate(createGenerationSchema), saveGeneration);
router.get('/me', getMyGenerations);
router.get('/:id', getGenerationById);
router.delete('/:id', deleteGeneration);
router.post('/:id/publish', publishGeneration);
router.post('/:id/unpublish', unpublishGeneration);

export default router;
