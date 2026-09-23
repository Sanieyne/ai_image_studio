/**
 * Main API v1 Router
 * Mounts all sub-routers and provides system health check.
 */

import { Router } from 'express';
import authRoutes from './auth.routes.js';
import userRoutes from './user.routes.js';

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

export default router;
