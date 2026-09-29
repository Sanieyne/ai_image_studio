/**
 * Admin Moderation Controller
 * Administrative inspection and decisions for pending media moderation queue.
 */

import mongoose from 'mongoose';
import { asyncHandler } from '../utils/asyncHandler.js';
import { ApiError } from '../utils/ApiError.js';
import { Generation } from '../models/Generation.js';
import { Report } from '../models/Report.js';
import { ModerationLog } from '../models/ModerationLog.js';
import { storageService } from '../services/storage.service.js';
import { MODERATION_STATUS } from '../config/constants.js';


/**
 * List all generations held in manual review queue.
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
 * Make an administrative decision on a generation in the moderation queue.
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

  // Immutable audit log
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
 * List pending user reports ordered by parent Generation.reportsCount descending, then createdAt.
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

  // Attach resolved media URL to generation objects
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
 * Resolve a user report (dismiss or remove content).
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

      // Create ModerationLog audit trail
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

