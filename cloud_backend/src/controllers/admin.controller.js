/**
 * Admin Portal Controller
 * Comprehensive administrative operations: Fleet management, Users & Wallets,
 * VIP Licenses, Model Catalog, Generations Audit, Moderation, and Reports.
 */

import mongoose from 'mongoose';
import axios from 'axios';
import crypto from 'crypto';
import { asyncHandler } from '../utils/asyncHandler.js';
import { ApiError } from '../utils/ApiError.js';
import { User } from '../models/User.js';
import { GpuInstance } from '../models/GpuInstance.js';
import { Generation } from '../models/Generation.js';
import { Transaction } from '../models/Transaction.js';
import { License } from '../models/License.js';
import { ModelCatalog } from '../models/ModelCatalog.js';
import { PricingConfig } from '../models/PricingConfig.js';
import { Report } from '../models/Report.js';
import { ModerationLog } from '../models/ModerationLog.js';
import { storageService } from '../services/storage.service.js';
import { vastaiService, isConfirmedContractId } from '../services/vastai.service.js';
import { billingService, ACTIVE_STATUSES, STOP_REASONS } from '../services/billing.service.js';
import { pricingService } from '../services/pricing.service.js';
import {
  MODERATION_STATUS,
  GPU_STATUS,
  TRANSACTION_TYPES,
  ROLES,
  LOG_LEVELS,
} from '../config/constants.js';

/**
 * 1. PLATFORM OVERVIEW KPI DASHBOARD
 * GET /api/v1/admin/overview
 */
export const getAdminOverview = asyncHandler(async (req, res) => {
  const now = new Date();
  const last24h = new Date(now.getTime() - 24 * 60 * 60 * 1000);

  const [
    totalUsers,
    activeUsers24h,
    vipSubscribers,
    activeInstances,
    totalGenerations,
    generations24h,
    pendingModeration,
    pendingReports,
    recentTransactions,
    recentGenerations,
  ] = await Promise.all([
    User.countDocuments({}),
    User.countDocuments({ updatedAt: { $gte: last24h } }),
    User.countDocuments({ subscriptionTier: { $in: ['pro', 'vip', 'starter'] }, subscriptionStatus: 'active' }),
    GpuInstance.find({ status: { $in: ACTIVE_STATUSES } })
      .populate('user', 'username email displayName credits')
      .sort({ createdAt: -1 })
      .lean(),
    Generation.countDocuments({}),
    Generation.countDocuments({ createdAt: { $gte: last24h } }),
    Generation.countDocuments({ moderationStatus: MODERATION_STATUS.PENDING_REVIEW }),
    Report.countDocuments({ status: 'pending' }),
    Transaction.find({})
      .populate('user', 'username email')
      .sort({ createdAt: -1 })
      .limit(10)
      .lean(),
    Generation.find({})
      .populate('userId', 'username email displayName')
      .sort({ createdAt: -1 })
      .limit(8)
      .lean(),
  ]);

  // Calculate hourly burn rates across active fleet
  let hourlyUsdBurn = 0;
  let hourlyCreditsBurn = 0;
  for (const inst of activeInstances) {
    hourlyUsdBurn += Number(inst.pricing?.totalPerHour || inst.costPerHour || 0);
    hourlyCreditsBurn += Number(inst.pricing?.totalCreditsPerHour || inst.pricing?.creditsPerHour || 0);
  }

  // Sum total credits currently held by all users
  const creditAgg = await User.aggregate([
    { $group: { _id: null, totalCreditsHeld: { $sum: '$credits' }, totalPurchased: { $sum: '$totalCreditsPurchased' }, totalUsed: { $sum: '$totalCreditsUsed' } } },
  ]);
  const creditStats = creditAgg[0] || { totalCreditsHeld: 0, totalPurchased: 0, totalUsed: 0 };

  // Rich time-series & breakdown analytics for professional dashboard
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const days = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date(now.getTime() - i * 24 * 60 * 60 * 1000);
    const dateStr = d.toISOString().split('T')[0];
    const label = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
    days.push({ date: dateStr, label });
  }

  const [
    mediaTypeAgg,
    modelDistAgg,
    dailyGenAgg,
    dailyTxAgg,
  ] = await Promise.all([
    Generation.aggregate([
      { $group: { _id: '$mediaType', count: { $sum: 1 } } }
    ]),
    Generation.aggregate([
      { $group: { _id: '$modelId', count: { $sum: 1 } } },
      { $sort: { count: -1 } },
      { $limit: 6 }
    ]),
    Generation.aggregate([
      { $match: { createdAt: { $gte: sevenDaysAgo } } },
      { $group: {
          _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt' } },
          total: { $sum: 1 },
          images: { $sum: { $cond: [{ $eq: ['$mediaType', 'image'] }, 1, 0] } },
          videos: { $sum: { $cond: [{ $eq: ['$mediaType', 'video'] }, 1, 0] } },
          audio: { $sum: { $cond: [{ $eq: ['$mediaType', 'audio'] }, 1, 0] } }
        }
      }
    ]),
    Transaction.aggregate([
      { $match: { createdAt: { $gte: sevenDaysAgo } } },
      { $group: {
          _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt' } },
          purchased: { $sum: { $cond: [{ $in: ['$type', ['purchase', 'topup', 'bonus', 'credit']] }, '$amount', 0] } },
          burned: { $sum: { $cond: [{ $in: ['$type', ['deduction', 'usage', 'debit']] }, '$amount', 0] } }
        }
      }
    ]),
  ]);

  const genMap = new Map(dailyGenAgg.map((x) => [x._id, x]));
  const txMap = new Map(dailyTxAgg.map((x) => [x._id, x]));

  const generationsTimeline = days.map((d) => {
    const entry = genMap.get(d.date) || {};
    return {
      date: d.date,
      label: d.label,
      total: entry.total || 0,
      images: entry.images || 0,
      videos: entry.videos || 0,
      audio: entry.audio || 0,
    };
  });

  const creditsTimeline = days.map((d) => {
    const entry = txMap.get(d.date) || {};
    return {
      date: d.date,
      label: d.label,
      purchased: Math.round((entry.purchased || 0) * 100) / 100,
      burned: Math.abs(Math.round((entry.burned || 0) * 100) / 100),
    };
  });

  const totalMedia = mediaTypeAgg.reduce((acc, curr) => acc + curr.count, 0) || 1;
  const mediaTypeDistribution = {
    image: mediaTypeAgg.find((m) => m._id === 'image')?.count || 0,
    video: mediaTypeAgg.find((m) => m._id === 'video')?.count || 0,
    audio: mediaTypeAgg.find((m) => m._id === 'audio')?.count || 0,
  };

  const modelDistribution = modelDistAgg.map((m) => ({
    modelId: m._id || 'unknown',
    count: m.count,
    percent: Math.round((m.count / totalMedia) * 1000) / 10,
  }));

  res.status(200).json({
    success: true,
    data: {
      kpis: {
        totalUsers,
        activeUsers24h,
        vipSubscribers,
        activeGpuCount: activeInstances.length,
        hourlyUsdBurn: Math.round(hourlyUsdBurn * 1000) / 1000,
        hourlyCreditsBurn: Math.round(hourlyCreditsBurn * 100) / 100,
        totalGenerations,
        generations24h,
        pendingModeration,
        pendingReports,
        totalCreditsHeld: Math.round(creditStats.totalCreditsHeld * 100) / 100,
        totalCreditsPurchased: Math.round(creditStats.totalPurchased * 100) / 100,
        totalCreditsUsed: Math.round(creditStats.totalUsed * 100) / 100,
      },
      analytics: {
        generationsTimeline,
        creditsTimeline,
        mediaTypeDistribution,
        modelDistribution,
      },
      activeInstances,
      recentTransactions,
      recentGenerations: recentGenerations.map((g) => ({
        ...g,
        url: g.storageKey ? storageService.getMediaUrl(g.storageKey) : null,
      })),
    },
  });
});

/**
 * 2. GPU FLEET MANAGEMENT
 * GET /api/v1/admin/fleet
 */
export const getAdminFleet = asyncHandler(async (req, res) => {
  const { status = 'active', limit = 50, page = 1 } = req.query;
  const numericLimit = Math.min(100, Math.max(1, parseInt(limit, 10)));
  const skip = (Math.max(1, parseInt(page, 10)) - 1) * numericLimit;

  const filter = {};
  if (status === 'active') {
    filter.status = { $in: ACTIVE_STATUSES };
  } else if (status !== 'all') {
    filter.status = status;
  }

  const [instances, total] = await Promise.all([
    GpuInstance.find(filter)
      .populate('user', 'username email displayName credits')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(numericLimit)
      .lean(),
    GpuInstance.countDocuments(filter),
  ]);

  // Probe live /health on active instances in parallel with a fast 2.5s timeout
  const enriched = await Promise.all(
    instances.map(async (inst) => {
      let liveHealth = null;
      if (ACTIVE_STATUSES.includes(inst.status) && inst.pythonEngineUrl) {
        try {
          const resp = await axios.get(`${inst.pythonEngineUrl.replace(/\/$/, '')}/health`, {
            timeout: 2500,
          });
          liveHealth = resp.data;
        } catch (err) {
          liveHealth = { status: 'unreachable', error: err.message };
        }
      }
      const startedAt = inst.contractConfirmedAt || inst.startedAt || inst.createdAt;
      const endedAt = inst.stoppedAt ? new Date(inst.stoppedAt) : new Date();
      const elapsedSeconds = startedAt ? Math.max(0, Math.round((endedAt - new Date(startedAt)) / 1000)) : 0;

      return {
        ...inst,
        elapsedSeconds,
        liveHealth,
      };
    })
  );

  res.status(200).json({
    success: true,
    data: enriched,
    pagination: {
      page: Number(page),
      limit: numericLimit,
      total,
      totalPages: Math.ceil(total / numericLimit),
    },
  });
});

/**
 * Terminate a GPU instance from Admin Portal
 * POST /api/v1/admin/fleet/:id/terminate
 */
export const terminateFleetInstance = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { refund = false, reason = 'Terminated by Administrator' } = req.body || {};

  const instance = await GpuInstance.findById(id);
  if (!instance) {
    throw ApiError.notFound('GPU instance not found');
  }

  if (isConfirmedContractId(instance.providerInstanceId)) {
    try {
      await vastaiService.destroyInstance(instance.providerInstanceId);
    } catch (err) {
      console.warn(`[Admin Terminate] Provider destroy warning for #${instance.providerInstanceId}: ${err.message}`);
    }
  }

  const stopped = await billingService.finalizeInstance(instance._id, {
    status: GPU_STATUS.STOPPED,
    stopReason: STOP_REASONS.USER_STOPPED,
    until: new Date(),
    refundIfNeverReady: Boolean(refund) || !instance.reachedReadyAt,
    message: reason,
    level: LOG_LEVELS.WARN,
    emitReason: 'ADMIN_STOPPED',
  });

  res.status(200).json({
    success: true,
    message: `Instance ${instance._id} (${instance.gpuType}) terminated successfully.`,
    data: stopped || (await GpuInstance.findById(id)),
  });
});

/**
 * Fetch detailed logs and live telemetry for a specific GPU instance
 * GET /api/v1/admin/fleet/:id/logs
 */
export const getFleetInstanceLogs = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const instance = await GpuInstance.findById(id)
    .populate('user', 'username email displayName')
    .lean();

  if (!instance) {
    throw ApiError.notFound('GPU instance not found');
  }

  let liveHealth = null;
  if (ACTIVE_STATUSES.includes(instance.status) && instance.pythonEngineUrl) {
    try {
      const resp = await axios.get(`${instance.pythonEngineUrl.replace(/\/$/, '')}/health`, {
        timeout: 3000,
      });
      liveHealth = resp.data;
    } catch (err) {
      liveHealth = { status: 'unreachable', error: err.message };
    }
  }

  res.status(200).json({
    success: true,
    data: {
      instanceId: instance._id,
      providerInstanceId: instance.providerInstanceId,
      gpuType: instance.gpuType,
      status: instance.status,
      publicIp: instance.publicIp,
      sshHost: instance.sshHost,
      sshPort: instance.sshPort,
      pythonEngineUrl: instance.pythonEngineUrl,
      progress: instance.progress,
      provisioningLogs: instance.provisioningLogs || [],
      liveHealth,
    },
  });
});

/**
 * 3. USER DIRECTORY & CREDIT WALLET MANAGEMENT
 * GET /api/v1/admin/users
 */
export const getAdminUsers = asyncHandler(async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit || '25', 10)));
  const skip = (page - 1) * limit;
  const { search = '', role, tier, isActive } = req.query;

  const filter = {};
  if (search.trim()) {
    const regex = new RegExp(search.trim(), 'i');
    filter.$or = [{ username: regex }, { email: regex }, { displayName: regex }, { gumroadLicenseKey: regex }];
  }
  if (role) filter.role = role;
  if (tier) filter.subscriptionTier = tier;
  if (isActive !== undefined && isActive !== '') {
    filter.isActive = isActive === 'true';
  }

  const [users, total] = await Promise.all([
    User.find(filter)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .lean(),
    User.countDocuments(filter),
  ]);

  res.status(200).json({
    success: true,
    data: users,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
      hasMore: page * limit < total,
    },
  });
});

/**
 * Adjust user credits (grant bonus or deduct credits) with immutable transaction log
 * POST /api/v1/admin/users/:id/credits
 */
export const adjustUserCredits = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { amount, reason = 'Administrative credit adjustment' } = req.body;

  const numericAmount = Number(amount);
  if (!Number.isFinite(numericAmount) || numericAmount === 0) {
    throw ApiError.badRequest('A non-zero numeric credit amount is required.');
  }

  const user = await User.findById(id);
  if (!user) {
    throw ApiError.notFound('User not found.');
  }

  const newBalance = Math.max(0, Math.round(((user.credits || 0) + numericAmount) * 100) / 100);
  const actualDelta = Math.round((newBalance - (user.credits || 0)) * 100) / 100;

  user.credits = newBalance;
  if (actualDelta > 0) {
    user.totalCreditsPurchased = (user.totalCreditsPurchased || 0) + actualDelta;
  }
  await user.save();

  const transaction = await Transaction.create({
    user: user._id,
    type: actualDelta >= 0 ? TRANSACTION_TYPES.BONUS : TRANSACTION_TYPES.DEDUCTION,
    amount: Math.abs(actualDelta),
    balanceAfter: user.credits,
    description: `[Admin] ${reason} (${actualDelta >= 0 ? '+' : ''}${actualDelta} credits)`,
    metadata: {
      adminId: req.user._id,
      adminEmail: req.user.email,
      reason,
      requestedDelta: numericAmount,
    },
  });

  res.status(200).json({
    success: true,
    message: `User credits adjusted by ${actualDelta >= 0 ? '+' : ''}${actualDelta}. New balance: ${user.credits}`,
    data: {
      user,
      transaction,
    },
  });
});

/**
 * Update user role, subscription tier, or account status
 * PATCH /api/v1/admin/users/:id
 */
export const updateAdminUser = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { role, isActive, subscriptionTier, subscriptionStatus, storageQuotaGB } = req.body;

  const user = await User.findById(id);
  if (!user) {
    throw ApiError.notFound('User not found');
  }

  if (role && Object.values(ROLES).includes(role)) {
    user.role = role;
  }
  if (typeof isActive === 'boolean') {
    user.isActive = isActive;
  }
  if (subscriptionTier && ['free', 'starter', 'pro', 'vip'].includes(subscriptionTier)) {
    user.subscriptionTier = subscriptionTier;
  }
  if (subscriptionStatus && ['none', 'active', 'cancelled', 'past_due', 'expired'].includes(subscriptionStatus)) {
    user.subscriptionStatus = subscriptionStatus;
  }
  if (storageQuotaGB !== undefined && Number.isFinite(Number(storageQuotaGB))) {
    user.storageQuotaGB = Math.max(1, Number(storageQuotaGB));
  }

  await user.save();

  res.status(200).json({
    success: true,
    message: `User ${user.username} updated successfully.`,
    data: user,
  });
});

/**
 * 4. VIP LICENSE KEYS GENERATOR & AUTHORITY
 * GET /api/v1/admin/licenses
 */
export const getAdminLicenses = asyncHandler(async (req, res) => {
  const licenses = await License.find({})
    .populate('createdBy', 'username email')
    .populate('redeemedBy.user', 'username email displayName')
    .sort({ createdAt: -1 })
    .lean();

  res.status(200).json({
    success: true,
    data: licenses,
  });
});

/**
 * Generate one or a batch of VIP/Promo license keys
 * POST /api/v1/admin/licenses/generate
 */
export const generateAdminLicenses = asyncHandler(async (req, res) => {
  const {
    customCode,
    prefix = 'COSMIC-VIP',
    count = 1,
    tier = 'vip',
    creditsGranted = 50,
    maxRedemptions = 1,
    expiresInDays = null,
    notes = '',
  } = req.body || {};

  const numToCreate = Math.min(50, Math.max(1, parseInt(count, 10) || 1));
  const expiresAt = expiresInDays ? new Date(Date.now() + Number(expiresInDays) * 86400000) : null;

  const created = [];

  if (customCode && String(customCode).trim()) {
    const cleanCode = String(customCode).trim().toUpperCase();
    const existing = await License.findOne({ code: cleanCode });
    if (existing) {
      throw ApiError.conflict(`License code "${cleanCode}" already exists.`);
    }
    const doc = await License.create({
      code: cleanCode,
      tier,
      creditsGranted: Math.max(0, Number(creditsGranted) || 0),
      maxRedemptions: Math.max(1, parseInt(maxRedemptions, 10) || 1),
      expiresAt,
      notes,
      createdBy: req.user._id,
    });
    created.push(doc);
  } else {
    const cleanPrefix = String(prefix).trim().toUpperCase().replace(/[^A-Z0-9-]/g, '') || 'COSMIC-VIP';
    for (let i = 0; i < numToCreate; i++) {
      const rand = crypto.randomBytes(3).toString('hex').toUpperCase();
      const code = `${cleanPrefix}-${rand}`;
      const doc = await License.create({
        code,
        tier,
        creditsGranted: Math.max(0, Number(creditsGranted) || 0),
        maxRedemptions: Math.max(1, parseInt(maxRedemptions, 10) || 1),
        expiresAt,
        notes,
        createdBy: req.user._id,
      });
      created.push(doc);
    }
  }

  res.status(201).json({
    success: true,
    message: `Generated ${created.length} license key(s).`,
    data: created,
  });
});

/**
 * Update or toggle a license key
 * PATCH /api/v1/admin/licenses/:id
 */
export const updateAdminLicense = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { isActive, maxRedemptions, creditsGranted, notes, expiresAt } = req.body;

  const license = await License.findById(id);
  if (!license) {
    throw ApiError.notFound('License not found');
  }

  if (typeof isActive === 'boolean') license.isActive = isActive;
  if (maxRedemptions !== undefined) license.maxRedemptions = Math.max(1, Number(maxRedemptions));
  if (creditsGranted !== undefined) license.creditsGranted = Math.max(0, Number(creditsGranted));
  if (notes !== undefined) license.notes = String(notes);
  if (expiresAt !== undefined) license.expiresAt = expiresAt ? new Date(expiresAt) : null;

  await license.save();

  res.status(200).json({
    success: true,
    message: `License ${license.code} updated.`,
    data: license,
  });
});

/**
 * Delete a license key
 * DELETE /api/v1/admin/licenses/:id
 */
export const deleteAdminLicense = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const license = await License.findByIdAndDelete(id);
  if (!license) {
    throw ApiError.notFound('License not found');
  }

  res.status(200).json({
    success: true,
    message: `License ${license.code} deleted.`,
  });
});

/**
 * 5. MODEL CATALOG & PRICING CONTROLLER
 * GET /api/v1/admin/models
 */
export const getAdminModels = asyncHandler(async (req, res) => {
  const [models, pricingConfig] = await Promise.all([
    ModelCatalog.find({}).sort({ mode: 1, displayName: 1 }).lean(),
    pricingService.getConfig(),
  ]);

  res.status(200).json({
    success: true,
    data: {
      models,
      pricingConfig,
    },
  });
});

/**
 * Update model catalog item or create new model entry
 * PUT /api/v1/admin/models/:id
 */
export const updateAdminModel = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { displayName, isEnabled, requiredVramGB, sizeGB, defaultSteps, defaultGuidance, mode, hfRepoId } = req.body;

  const query = mongoose.Types.ObjectId.isValid(id) ? { _id: id } : { modelId: id };
  const model = await ModelCatalog.findOne(query);
  if (!model) {
    throw ApiError.notFound('Model not found in catalog');
  }

  if (displayName !== undefined) model.displayName = displayName;
  if (typeof isEnabled === 'boolean') model.isEnabled = isEnabled;
  if (requiredVramGB !== undefined) model.requiredVramGB = Math.max(1, Number(requiredVramGB));
  if (sizeGB !== undefined) model.sizeGB = Math.max(0.1, Number(sizeGB));
  if (defaultSteps !== undefined) model.defaultSteps = Math.max(1, Number(defaultSteps));
  if (defaultGuidance !== undefined) model.defaultGuidance = Number(defaultGuidance);
  if (mode !== undefined) model.mode = mode;
  if (hfRepoId !== undefined) model.hfRepoId = hfRepoId;

  await model.save();

  res.status(200).json({
    success: true,
    message: `Model "${model.displayName}" updated successfully.`,
    data: model,
  });
});

/**
 * 6. GLOBAL GENERATIONS AUDIT & HOMEPAGE GALLERY CURATION
 * GET /api/v1/admin/generations
 */
export const getAdminGenerations = asyncHandler(async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit || '24', 10)));
  const skip = (page - 1) * limit;
  const { mediaType, modelId, moderationStatus, isPublic, search = '' } = req.query;

  const filter = {};
  if (mediaType) filter.mediaType = mediaType;
  if (modelId) filter.modelId = modelId;
  if (moderationStatus) filter.moderationStatus = moderationStatus;
  if (isPublic !== undefined && isPublic !== '') filter.isPublic = isPublic === 'true';
  if (search.trim()) {
    filter.prompt = new RegExp(search.trim(), 'i');
  }

  const [generations, total] = await Promise.all([
    Generation.find(filter)
      .populate('userId', 'username email displayName avatarUrl')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .lean(),
    Generation.countDocuments(filter),
  ]);

  const enriched = generations.map((gen) => ({
    ...gen,
    url: gen.storageKey ? storageService.getMediaUrl(gen.storageKey) : null,
  }));

  res.status(200).json({
    success: true,
    data: enriched,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
      hasMore: page * limit < total,
    },
  });
});

/**
 * Pin or unpin a generation to the public homepage gallery
 * POST /api/v1/admin/generations/:id/pin
 */
export const togglePinGeneration = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { isPublic } = req.body || {};

  const generation = await Generation.findById(id);
  if (!generation) {
    throw ApiError.notFound('Generation not found');
  }

  const nextPublic = typeof isPublic === 'boolean' ? isPublic : !generation.isPublic;
  generation.isPublic = nextPublic;
  if (nextPublic) {
    generation.moderationStatus = MODERATION_STATUS.APPROVED;
    generation.publishedAt = generation.publishedAt || new Date();
  }

  await generation.save();

  res.status(200).json({
    success: true,
    message: nextPublic
      ? 'Generation pinned and published to the public gallery.'
      : 'Generation unpublished from the public gallery.',
    data: generation,
  });
});

/**
 * Delete a generation permanently
 * DELETE /api/v1/admin/generations/:id
 */
export const deleteAdminGeneration = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const generation = await Generation.findByIdAndDelete(id);
  if (!generation) {
    throw ApiError.notFound('Generation not found');
  }

  res.status(200).json({
    success: true,
    message: 'Generation deleted permanently.',
  });
});

/**
 * 7. GLOBAL TRANSACTIONS & CREDIT LEDGER
 * GET /api/v1/admin/transactions
 */
export const getAdminTransactions = asyncHandler(async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit || '30', 10)));
  const skip = (page - 1) * limit;
  const { type, userId } = req.query;

  const filter = {};
  if (type) filter.type = type;
  if (userId && mongoose.Types.ObjectId.isValid(userId)) filter.user = userId;

  const [transactions, total] = await Promise.all([
    Transaction.find(filter)
      .populate('user', 'username email displayName')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .lean(),
    Transaction.countDocuments(filter),
  ]);

  res.status(200).json({
    success: true,
    data: transactions,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
      hasMore: page * limit < total,
    },
  });
});

/**
 * 8. MODERATION QUEUE & REPORTS (EXISTING)
 * GET /api/v1/admin/moderation/queue
 */
export const getModerationQueue = asyncHandler(async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit || '20', 10)));
  const skip = (page - 1) * limit;

  const filter = { moderationStatus: MODERATION_STATUS.PENDING_REVIEW };

  const [generations, total] = await Promise.all([
    Generation.find(filter)
      .populate('userId', 'username displayName avatarUrl email')
      .sort({ updatedAt: -1 })
      .skip(skip)
      .limit(limit),
    Generation.countDocuments(filter),
  ]);

  res.status(200).json({
    success: true,
    data: generations,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
      hasMore: page * limit < total,
    },
  });
});

/**
 * POST /api/v1/admin/moderation/:id/decide
 */
export const decideModeration = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { decision, reason = '' } = req.body;

  const generation = await Generation.findById(id);
  if (!generation) {
    throw ApiError.notFound('Generation not found');
  }

  if (decision === 'approve') {
    generation.moderationStatus = MODERATION_STATUS.APPROVED;
    generation.isPublic = true;
    generation.publishedAt = generation.publishedAt || new Date();
  } else if (decision === 'reject') {
    generation.moderationStatus = MODERATION_STATUS.REJECTED;
    generation.isPublic = false;
  } else {
    throw ApiError.badRequest('Invalid decision. Must be "approve" or "reject".');
  }

  await generation.save();

  await ModerationLog.create({
    generationId: generation._id,
    userId: generation.userId,
    mediaType: generation.mediaType,
    verdict: decision === 'approve' ? 'approved' : 'rejected',
    provider: 'admin-manual',
    reviewedBy: req.user._id,
    decision,
    reason: reason || `Manual administrative decision: ${decision}`,
  });

  res.status(200).json({
    success: true,
    message: `Generation ${decision}d successfully by administrator`,
    data: generation,
  });
});

/**
 * GET /api/v1/admin/reports
 */
export const getReports = asyncHandler(async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit || '20', 10)));
  const skip = (page - 1) * limit;

  const matchStage = { status: 'pending' };

  const pipeline = [
    { $match: matchStage },
    {
      $lookup: {
        from: 'generations',
        localField: 'generationId',
        foreignField: '_id',
        as: 'generation',
      },
    },
    { $unwind: { path: '$generation', preserveNullAndEmptyArrays: true } },
    {
      $lookup: {
        from: 'users',
        localField: 'userId',
        foreignField: '_id',
        as: 'reporter',
      },
    },
    { $unwind: { path: '$reporter', preserveNullAndEmptyArrays: true } },
    {
      $sort: {
        'generation.reportsCount': -1,
        createdAt: -1,
      },
    },
    {
      $project: {
        _id: 1,
        reason: 1,
        details: 1,
        status: 1,
        createdAt: 1,
        updatedAt: 1,
        generation: {
          _id: '$generation._id',
          mediaType: '$generation.mediaType',
          storageKey: '$generation.storageKey',
          prompt: '$generation.prompt',
          modelId: '$generation.modelId',
          isPublic: '$generation.isPublic',
          moderationStatus: '$generation.moderationStatus',
          reportsCount: '$generation.reportsCount',
          likesCount: '$generation.likesCount',
          viewsCount: '$generation.viewsCount',
          createdAt: '$generation.createdAt',
        },
        reporter: {
          _id: '$reporter._id',
          username: '$reporter.username',
          displayName: '$reporter.displayName',
          avatarUrl: '$reporter.avatarUrl',
        },
      },
    },
    { $skip: skip },
    { $limit: limit },
  ];

  const [reports, total] = await Promise.all([
    Report.aggregate(pipeline),
    Report.countDocuments(matchStage),
  ]);

  const data = reports.map((rep) => {
    if (rep.generation && rep.generation.storageKey) {
      rep.generation.url = storageService.getMediaUrl(rep.generation.storageKey);
    }
    return rep;
  });

  res.status(200).json({
    success: true,
    data,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
      hasMore: page * limit < total,
    },
  });
});

/**
 * POST /api/v1/admin/reports/:id/resolve
 */
export const resolveReport = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { action, reason = '' } = req.body;

  if (!mongoose.Types.ObjectId.isValid(id)) {
    throw ApiError.notFound('Report not found');
  }

  const report = await Report.findById(id);
  if (!report) {
    throw ApiError.notFound('Report not found');
  }

  if (action === 'dismiss') {
    report.status = 'dismissed';
    await report.save();

    return res.status(200).json({
      success: true,
      message: 'Report dismissed successfully',
      data: report,
    });
  }

  if (action === 'remove_content') {
    const generation = await Generation.findById(report.generationId);
    if (generation) {
      generation.isPublic = false;
      generation.moderationStatus = MODERATION_STATUS.REJECTED;
      await generation.save();

      await ModerationLog.create({
        generationId: generation._id,
        userId: generation.userId,
        mediaType: generation.mediaType,
        verdict: 'rejected',
        provider: 'admin-report-resolution',
        reviewedBy: req.user._id,
        decision: 'remove_content',
        reason: reason || `Removed by admin following report for ${report.reason}: ${report.details || 'No details'}`,
      });
    }

    report.status = 'reviewed';
    await report.save();

    return res.status(200).json({
      success: true,
      message: 'Content removed and report resolved successfully',
      data: {
        report,
        generation: generation
          ? {
              _id: generation._id,
              isPublic: generation.isPublic,
              moderationStatus: generation.moderationStatus,
            }
          : null,
      },
    });
  }

  throw ApiError.badRequest('Invalid action. Must be "dismiss" or "remove_content".');
});
