/**
 * Generation Controller
 * Manages persisting media generations, user private generation history,
 * quota enforcement, and media deletion.
 */

import fs from 'fs/promises';
import path from 'path';
import { asyncHandler } from '../utils/asyncHandler.js';
import { ApiError } from '../utils/ApiError.js';
import { Generation } from '../models/Generation.js';
import { User } from '../models/User.js';
import { Like } from '../models/Like.js';
import { Report } from '../models/Report.js';
import { ModerationLog } from '../models/ModerationLog.js';
import { storageService } from '../services/storage.service.js';
import { moderationService } from '../services/moderation.service.js';
import { MODERATION_STATUS } from '../config/constants.js';
import { env } from '../config/env.js';

/**
 * Parses base64 string, stripping data URI prefix if present and identifying extension.
 */
function parseBase64Media(mediaBase64, userExt = '') {
  let cleanBase64 = mediaBase64;
  let detectedExt = (userExt || '').replace(/^\./, '').trim().toLowerCase();

  const dataUriMatch = mediaBase64.match(/^data:([A-Za-z0-9+/.-]+);base64,(.+)$/s);
  if (dataUriMatch) {
    const mime = dataUriMatch[1].toLowerCase();
    cleanBase64 = dataUriMatch[2];
    if (!detectedExt) {
      if (mime.includes('png')) detectedExt = 'png';
      else if (mime.includes('jpeg') || mime.includes('jpg')) detectedExt = 'jpg';
      else if (mime.includes('webp')) detectedExt = 'webp';
      else if (mime.includes('gif')) detectedExt = 'gif';
      else if (mime.includes('mp4')) detectedExt = 'mp4';
      else if (mime.includes('webm')) detectedExt = 'webm';
      else if (mime.includes('mp3')) detectedExt = 'mp3';
      else if (mime.includes('wav')) detectedExt = 'wav';
    }
  }

  // Strip whitespaces or newlines
  cleanBase64 = cleanBase64.replace(/\s+/g, '');
  const buffer = Buffer.from(cleanBase64, 'base64');
  return { buffer, detectedExt };
}

/**
 * Save a completed generation to disk storage and MongoDB.
 * POST /api/v1/generations
 */
export const saveGeneration = asyncHandler(async (req, res) => {
  const {
    mediaBase64,
    mediaType = 'image',
    extension = 'png',
    prompt,
    negativePrompt = '',
    modelId,
    settings = {},
  } = req.body;

  const { buffer, detectedExt } = parseBase64Media(mediaBase64, extension);

  if (!buffer || buffer.length === 0) {
    throw ApiError.badRequest('Invalid or empty media data provided');
  }

  const fileSizeBytes = buffer.length;
  const fileSizeGB = fileSizeBytes / (1024 * 1024 * 1024);

  // 1. Atomically check quota and reserve storage
  const user = await User.findOneAndUpdate(
    {
      _id: req.user._id,
      $expr: {
        $lte: [
          { $add: [{ $ifNull: ['$storageUsedGB', 0] }, fileSizeGB] },
          { $ifNull: ['$storageQuotaGB', 20] },
        ],
      },
    },
    {
      $inc: { storageUsedGB: fileSizeGB },
    },
    { returnDocument: 'after' }
  );

  if (!user) {
    const currentUser = await User.findById(req.user._id);
    if (!currentUser) {
      throw ApiError.notFound('User not found');
    }
    const currentUsedGB = currentUser.storageUsedGB || 0;
    const quotaGB = currentUser.storageQuotaGB || 20;
    throw ApiError.forbidden(
      `Storage quota exceeded. Used: ${currentUsedGB.toFixed(3)} GB / ${quotaGB} GB. Free up space or upgrade storage.`
    );
  }

  let uploadedStorageKey = null;

  try {
    // 2. Upload to storage service
    const uploadResult = await storageService.uploadMedia(buffer, {
      userId: user._id,
      mediaType,
      extension: detectedExt || extension,
    });
    uploadedStorageKey = uploadResult.storageKey;

    // 3. Persist generation record in MongoDB
    const generation = await Generation.create({
      userId: user._id,
      mediaType,
      storageKey: uploadedStorageKey,
      prompt,
      negativePrompt,
      modelId,
      settings,
      fileSizeBytes,
      isPublic: false,
    });

    res.status(201).json({
      success: true,
      message: 'Generation saved successfully',
      data: generation,
    });
  } catch (error) {
    // Rollback atomic storage reservation
    await User.findByIdAndUpdate(
      req.user._id,
      [
        {
          $set: {
            storageUsedGB: {
              $max: [0, { $subtract: [{ $ifNull: ['$storageUsedGB', 0] }, fileSizeGB] }],
            },
          },
        },
      ],
      { updatePipeline: true }
    ).catch(() => {});

    // Cleanup storage file if DB save failed
    if (uploadedStorageKey) {
      try {
        await storageService.deleteMedia(uploadedStorageKey);
      } catch (cleanupErr) {
        // Log silently
      }
    }
    throw error;
  }
});

/**
 * Retrieve paginated list of current user's saved generations.
 * GET /api/v1/generations/me
 */
export const getMyGenerations = asyncHandler(async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit || '20', 10)));
  const skip = (page - 1) * limit;

  const filter = { userId: req.user._id };
  if (req.query.mediaType) {
    filter.mediaType = req.query.mediaType;
  }

  const [generations, total] = await Promise.all([
    Generation.find(filter)
      .sort({ createdAt: -1 })
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
 * Retrieve a single generation by ID.
 * GET /api/v1/generations/:id
 */
export const getGenerationById = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const generation = await Generation.findById(id);

  if (!generation) {
    throw ApiError.notFound('Generation not found');
  }

  // Must be owner or admin (or public if future public gallery enabled)
  if (
    !generation.isPublic &&
    generation.userId.toString() !== req.user._id.toString() &&
    req.user.role !== 'admin'
  ) {
    throw ApiError.forbidden('You do not have permission to view this generation');
  }

  res.status(200).json({
    success: true,
    data: generation,
  });
});

/**
 * Delete a generation record and remove underlying media file from storage.
 * DELETE /api/v1/generations/:id
 */
export const deleteGeneration = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const generation = await Generation.findById(id);

  if (!generation) {
    throw ApiError.notFound('Generation not found');
  }

  // Check ownership (or admin role)
  if (generation.userId.toString() !== req.user._id.toString() && req.user.role !== 'admin') {
    throw ApiError.forbidden('You do not have permission to delete this generation');
  }

  // 1. Delete file from storage
  await storageService.deleteMedia(generation.storageKey);

  // 2. Decrement user's storageUsedGB atomically without dropping below 0
  const freedGB = (generation.fileSizeBytes || 0) / (1024 * 1024 * 1024);
  await User.findByIdAndUpdate(
    generation.userId,
    [
      {
        $set: {
          storageUsedGB: {
            $max: [0, { $subtract: [{ $ifNull: ['$storageUsedGB', 0] }, freedGB] }],
          },
        },
      },
    ],
    { updatePipeline: true }
  );

  // 3. Delete document from MongoDB and cascade associated likes and reports
  await generation.deleteOne();
  await Like.deleteMany({ generationId: generation._id });
  await Report.deleteMany({ generationId: generation._id });

  res.status(200).json({
    success: true,
    message: 'Generation deleted successfully',
  });
});

/**
 * Publish a generation to the public gallery, gated by automated content moderation.
 * POST /api/v1/generations/:id/publish
 */
export const publishGeneration = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const generation = await Generation.findById(id);

  if (!generation) {
    throw ApiError.notFound('Generation not found');
  }

  // Confirm ownership
  if (generation.userId.toString() !== req.user._id.toString()) {
    throw ApiError.forbidden('You do not have permission to publish this generation');
  }

  // Already published and approved
  if (generation.isPublic && generation.moderationStatus === MODERATION_STATUS.APPROVED) {
    return res.status(200).json({
      success: true,
      message: 'Generation is already published',
      data: generation,
    });
  }

  // Locate media file on disk
  const diskPath = path.resolve(env.MEDIA_STORAGE_PATH, generation.storageKey);
  let buffer = null;
  try {
    buffer = await fs.readFile(diskPath);
  } catch (err) {
    throw ApiError.internal(`Underlying media file could not be read: ${err.message}`);
  }

  // Run automated moderation check
  let modResult = null;

  // Security gate: Header-based moderation test override is STRICTLY disabled in production.
  // It can only ever apply when NODE_ENV === 'test' AND an explicit server-side flag
  // ALLOW_TEST_MODERATION_OVERRIDE === 'true' is set in the server's own environment.
  // In production (and standard runtime), headers are completely ignored.
  const isTestOverridePermitted =
    !env.isProduction &&
    env.NODE_ENV === 'test' &&
    process.env.ALLOW_TEST_MODERATION_OVERRIDE === 'true';

  if (isTestOverridePermitted && req.headers['x-test-moderation-verdict']) {
    const verdict = req.headers['x-test-moderation-verdict'];
    if (['allow', 'review', 'block'].includes(verdict)) {
      modResult = {
        verdict,
        provider: 'google-vision-test-override',
        scores: { testOverride: true },
        reason: `Test simulated verdict: ${verdict}`,
      };
    }
  }

  // If not in explicit test mode with override, evaluate with actual moderation service
  if (!modResult) {
    modResult = await moderationService.checkMediaSafety({
      buffer,
      filePath: diskPath,
      mediaType: generation.mediaType,
    });
  }

  // Log every moderation decision to immutable audit trail
  await ModerationLog.create({
    generationId: generation._id,
    userId: req.user._id,
    mediaType: generation.mediaType,
    verdict: modResult.verdict,
    provider: modResult.provider,
    scores: modResult.scores,
    reason: modResult.reason || '',
  });

  if (modResult.verdict === 'allow') {
    generation.isPublic = true;
    generation.moderationStatus = MODERATION_STATUS.APPROVED;
    generation.publishedAt = new Date();
    await generation.save();

    return res.status(200).json({
      success: true,
      message: 'Generation approved and published to the gallery.',
      data: generation,
    });
  }

  if (modResult.verdict === 'review') {
    generation.isPublic = false;
    generation.moderationStatus = MODERATION_STATUS.PENDING_REVIEW;
    await generation.save();

    return res.status(202).json({
      success: true,
      message: 'Content has been submitted and is currently pending manual moderation review.',
      data: generation,
    });
  }

  if (modResult.verdict === 'block') {
    generation.isPublic = false;
    generation.moderationStatus = MODERATION_STATUS.REJECTED;
    await generation.save();

    return res.status(400).json({
      success: false,
      message: 'This generation cannot be published as it does not meet our community safety standards.',
      data: {
        id: generation._id,
        moderationStatus: generation.moderationStatus,
      },
    });
  }
});

/**
 * Unpublish a generation from the public gallery.
 * POST /api/v1/generations/:id/unpublish
 */
export const unpublishGeneration = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const generation = await Generation.findById(id);

  if (!generation) {
    throw ApiError.notFound('Generation not found');
  }

  // Confirm ownership
  if (generation.userId.toString() !== req.user._id.toString()) {
    throw ApiError.forbidden('You do not have permission to unpublish this generation');
  }

  generation.isPublic = false;
  await generation.save();

  res.status(200).json({
    success: true,
    message: 'Generation unpublished successfully.',
    data: generation,
  });
});

