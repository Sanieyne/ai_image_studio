/**
 * User & Credits Routes
 * Endpoints for current user profile, credits balance, and paginated transaction history.
 */

import { Router } from 'express';
import { getMe, getCredits, getTransactions } from '../controllers/user.controller.js';
import { protect } from '../middleware/auth.middleware.js';

const router = Router();

// All user routes require authentication
router.use(protect);

router.get('/me', getMe);
router.get('/credits', getCredits);
router.get('/transactions', getTransactions);

export default router;
