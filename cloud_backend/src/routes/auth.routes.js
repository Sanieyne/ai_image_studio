/**
 * Authentication Routes
 * Endpoints for signup, signin, token refresh, and logout.
 */

import { Router } from 'express';
import {
  register,
  login,
  refresh,
  logout,
  logoutAll,
  sendOtp,
  verifyOtp,
  forgotPassword,
  resetPassword,
} from '../controllers/auth.controller.js';
import {
  validate,
  registerSchema,
  loginSchema,
  refreshSchema,
  sendOtpSchema,
  verifyOtpSchema,
  resetPasswordSchema,
} from '../middleware/validation.middleware.js';
import { authLimiter, otpLimiter } from '../middleware/rateLimiter.middleware.js';
import { protect } from '../middleware/auth.middleware.js';

const router = Router();

router.post('/register', authLimiter, validate(registerSchema), register);
router.post('/login', authLimiter, validate(loginSchema), login);
router.post('/refresh', validate(refreshSchema), refresh);
router.post('/logout', validate(refreshSchema), logout);
router.post('/logout-all', protect, logoutAll);

// Email verification & OTP endpoints
router.post('/send-otp', otpLimiter, validate(sendOtpSchema), sendOtp);
router.post('/verify-otp', authLimiter, validate(verifyOtpSchema), verifyOtp);
router.post('/forgot-password', otpLimiter, validate(sendOtpSchema), forgotPassword);
router.post('/reset-password', authLimiter, validate(resetPasswordSchema), resetPassword);

export default router;
