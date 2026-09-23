/**
 * Authentication Routes
 * Endpoints for signup, signin, and token refresh.
 */

import { Router } from 'express';
import { register, login, refresh } from '../controllers/auth.controller.js';
import { validate, registerSchema, loginSchema, refreshSchema } from '../middleware/validation.middleware.js';
import { authLimiter } from '../middleware/rateLimiter.middleware.js';

const router = Router();

router.post('/register', authLimiter, validate(registerSchema), register);
router.post('/login', authLimiter, validate(loginSchema), login);
router.post('/refresh', validate(refreshSchema), refresh);

export default router;
