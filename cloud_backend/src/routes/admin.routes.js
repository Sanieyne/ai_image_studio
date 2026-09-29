/**
 * Admin Routes
 * Protected administrative operations requiring ADMIN role.
 */

import { Router } from 'express';
import { protect, authorize } from '../middleware/auth.middleware.js';
import { ROLES } from '../config/constants.js';
import {
  validate,
  adminModerationDecideSchema,
  resolveReportSchema,
} from '../middleware/validation.middleware.js';
import {
  getModerationQueue,
  decideModeration,
  getReports,
  resolveReport,
} from '../controllers/admin.controller.js';

const router = Router();

// Strict RBAC: All admin routes require authenticated session with ADMIN role
router.use(protect, authorize(ROLES.ADMIN));

router.get('/moderation/queue', getModerationQueue);
router.post('/moderation/:id/decide', validate(adminModerationDecideSchema), decideModeration);

router.get('/reports', getReports);
router.post('/reports/:id/resolve', validate(resolveReportSchema), resolveReport);

export default router;

