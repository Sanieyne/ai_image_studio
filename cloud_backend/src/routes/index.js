/**
 * Main API v1 Router
 * Mounts all sub-routers and provides system health check.
 */

import { Router } from 'express';
import authRoutes from './auth.routes.js';
import userRoutes from './user.routes.js';
import modelRoutes from './model.routes.js';
import gpuRoutes from './gpu.routes.js';
import pricingRoutes from './pricing.routes.js';

const router = Router();

// Health check endpoint
router.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    service: 'ai-studio-cloud-orchestrator',
    timestamp: new Date().toISOString(),
  });
});

// Resource sub-routers
router.use('/auth', authRoutes);
router.use('/users', userRoutes);
router.use('/models', modelRoutes);
router.use('/gpu', gpuRoutes);
router.use('/pricing', pricingRoutes);

export default router;
