/**
 * Admin Portal Routes
 * Protected administrative operations requiring ADMIN role.
 * Base path: /api/v1/admin
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
  getAdminOverview,
  getAdminFleet,
  terminateFleetInstance,
  getFleetInstanceLogs,
  getAdminUsers,
  adjustUserCredits,
  updateAdminUser,
  getAdminLicenses,
  generateAdminLicenses,
  updateAdminLicense,
  deleteAdminLicense,
  getAdminModels,
  updateAdminModel,
  getAdminGenerations,
  togglePinGeneration,
  deleteAdminGeneration,
  getAdminTransactions,
  getModerationQueue,
  decideModeration,
  getReports,
  resolveReport,
} from '../controllers/admin.controller.js';
import {
  getMarketingStats,
  getMarketingPresets,
  previewMarketingCampaign,
  sendTestMarketingEmail,
  broadcastMarketingCampaign,
  getMarketingCampaignHistory,
} from '../controllers/marketingAdmin.controller.js';

const router = Router();

// Strict RBAC: All admin routes require authenticated session with ADMIN role
router.use(protect, authorize(ROLES.ADMIN));

// 1. Overview & KPIs
router.get('/overview', getAdminOverview);

// 2. GPU Fleet Management
router.get('/fleet', getAdminFleet);
router.post('/fleet/:id/terminate', terminateFleetInstance);
router.get('/fleet/:id/logs', getFleetInstanceLogs);

// 3. Users & Wallets
router.get('/users', getAdminUsers);
router.post('/users/:id/credits', adjustUserCredits);
router.patch('/users/:id', updateAdminUser);

// 4. VIP License Generator
router.get('/licenses', getAdminLicenses);
router.post('/licenses/generate', generateAdminLicenses);
router.patch('/licenses/:id', updateAdminLicense);
router.delete('/licenses/:id', deleteAdminLicense);

// 5. Model Catalog & Pricing
router.get('/models', getAdminModels);
router.put('/models/:id', updateAdminModel);

// 6. Generations & Gallery Curation
router.get('/generations', getAdminGenerations);
router.post('/generations/:id/pin', togglePinGeneration);
router.delete('/generations/:id', deleteAdminGeneration);

// 7. Transactions Ledger
router.get('/transactions', getAdminTransactions);

// 8. Moderation Queue & Reports
router.get('/moderation/queue', getModerationQueue);
router.post('/moderation/:id/decide', validate(adminModerationDecideSchema), decideModeration);
router.get('/reports', getReports);
router.post('/reports/:id/resolve', validate(resolveReportSchema), resolveReport);

// 9. Email Marketing Suite
router.get('/marketing/stats', getMarketingStats);
router.get('/marketing/presets', getMarketingPresets);
router.post('/marketing/preview', previewMarketingCampaign);
router.post('/marketing/send-test', sendTestMarketingEmail);
router.post('/marketing/broadcast', broadcastMarketingCampaign);
router.get('/marketing/history', getMarketingCampaignHistory);

export default router;
