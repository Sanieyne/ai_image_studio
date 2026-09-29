/**
 * Gallery Routes
 * Public browsing routes and authenticated social interactions (likes, reports).
 */

import { Router } from 'express';
import { protect, optionalProtect } from '../middleware/auth.middleware.js';
import { publicReadLimiter, reportLimiter } from '../middleware/rateLimiter.middleware.js';
import { validate, createReportSchema } from '../middleware/validation.middleware.js';
import {
  getGalleryFeed,
  getGalleryPostById,
  getUserGalleryPosts,
  likePost,
  unlikePost,
  reportPost,
} from '../controllers/gallery.controller.js';

const router = Router();

// Public gallery feed (permissive rate limiting for browsing)
router.get('/', publicReadLimiter, optionalProtect, getGalleryFeed);

// Public user profile gallery (must precede /:id to avoid route collision)
router.get('/user/:username', publicReadLimiter, optionalProtect, getUserGalleryPosts);

// Single gallery post detail
router.get('/:id', publicReadLimiter, optionalProtect, getGalleryPostById);

// Social endpoints (authenticated)
router.post('/:id/like', protect, likePost);
router.delete('/:id/like', protect, unlikePost);
router.post(
  '/:id/report',
  protect,
  reportLimiter,
  validate(createReportSchema),
  reportPost
);

export default router;
