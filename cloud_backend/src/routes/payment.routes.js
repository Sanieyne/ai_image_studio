/**
 * Payment & Subscription Routes
 * Webhook for Gumroad events and license key verification.
 */

import { Router } from 'express';
import {
  getPlans,
  handleGumroadWebhook,
  verifyLicenseKey,
} from '../controllers/payment.controller.js';
import { protect } from '../middleware/auth.middleware.js';

const router = Router();

// Public: list subscription plans & pricing
router.get('/plans', getPlans);

// Webhook: Gumroad calls this directly via POST
router.post('/gumroad-webhook', handleGumroadWebhook);

// Authenticated: user verifies their Gumroad license key
router.post('/verify-license', protect, verifyLicenseKey);

export default router;
