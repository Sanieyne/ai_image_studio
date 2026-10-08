/**
 * Authentication Routes
 * Endpoints for signup, signin, token refresh, and logout.
 */

import { Router } from 'express';
import { register, login, refresh, logout, logoutAll } from '../controllers/auth.controller.js';
import { validate, registerSchema, loginSchema, refreshSchema } from '../middleware/validation.middleware.js';
import { authLimiter } from '../middleware/rateLimiter.middleware.js';
import { protect } from '../middleware/auth.middleware.js';

const router = Router();

router.post('/register', authLimiter, validate(registerSchema), register);
router.post('/login', authLimiter, validate(loginSchema), login);
router.post('/refresh', validate(refreshSchema), refresh);
router.post('/logout', validate(refreshSchema), logout);
router.post('/logout-all', protect, logoutAll);

export default router;
