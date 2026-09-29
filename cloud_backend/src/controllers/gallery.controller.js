/**
 * Gallery Controller
 * Public gallery feed, item details, author profile galleries,
 * and lightweight social features (likes, reports).
 */

import mongoose from 'mongoose';
import { asyncHandler } from '../utils/asyncHandler.js';
import { ApiError } from '../utils/ApiError.js';
import { Generation } from '../models/Generation.js';
import { User } from '../models/User.js';
import { Like } from '../models/Like.js';
import { Report } from '../models/Report.js';
import { storageService } from '../services/storage.service.js';
import { MODERATION_STATUS } from '../config/constants.js';

/**
 * Formats a Generation document into a safe public-facing gallery item.
 * Strips private user metadata, internal storage paths, and report counters.
 */
export function formatPublicPost(doc, userLikedPostIds = null) {
  let author = null;
  const userDoc = doc.userId;
  if (userDoc && typeof userDoc === 'object') {
    if (typeof userDoc.toPublicJSON === 'function') {
      author = userDoc.toPublicJSON();
    } else {
      author = {
        username: userDoc.username,
        displayName: userDoc.displayName || userDoc.username,
        avatarUrl: userDoc.avatarUrl || null,
        bio: userDoc.bio || '',
        createdAt: userDoc.createdAt,
      };
    }
  }

  let isLiked = false;
  if (userLikedPostIds && userLikedPostIds instanceof Set) {
    isLiked = userLikedPostIds.has(doc._id.toString());
  }

  return {
    _id: doc._id,
    mediaType: doc.mediaType,
    url: doc.url || storageService.getMediaUrl(doc.storageKey),
    prompt: doc.prompt,
    negativePrompt: doc.negativePrompt || '',
    modelId: doc.modelId,
    settings: doc.settings || {},
    likesCount: doc.likesCount || 0,
    viewsCount: doc.viewsCount || 0,
    publishedAt: doc.publishedAt,
    createdAt: doc.createdAt,
    author,
    isLiked,
  };
}

/**
 * Public feed of approved community generations.
 * GET /api/v1/gallery
 */
export const getGalleryFeed = asyncHandler(async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  // Hard cap limit at 50 to prevent unbounded memory queries
  const limit = Math.min(50, Math.max(1, parseInt(req.query.limit || '20', 10)));
  const skip = (page - 1) * limit;

  // Strict filter: must be public AND approved by moderation
  const filter = {
    isPublic: true,
    moderationStatus: MODERATION_STATUS.APPROVED,
  };

  if (req.query.mediaType) {
    filter.mediaType = req.query.mediaType;
  }
  if (req.query.modelId) {
    filter.modelId = req.query.modelId;
  }

  // Sort order: recent (default) or popular (likesCount)
  let sortOption = { publishedAt: -1, createdAt: -1, _id: -1 };
  if (req.query.sort === 'popular') {
    sortOption = { likesCount: -1, createdAt: -1, _id: -1 };
  }

  const [generations, total] = await Promise.all([
    Generation.find(filter)
      .populate('userId', 'username displayName avatarUrl bio createdAt isPublicProfile')
      .sort(sortOption)
      .skip(skip)
      .limit(limit),
    Generation.countDocuments(filter),
  ]);

  // If user is authenticated, query their like status on this page of posts
  let likedSet = new Set();
  if (req.user) {
    const postIds = generations.map((g) => g._id);
    const likes = await Like.find({
      userId: req.user._id,
      generationId: { $in: postIds },
    }).select('generationId');
    likedSet = new Set(likes.map((l) => l.generationId.toString()));
  }

  const data = generations.map((gen) => formatPublicPost(gen, likedSet));

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
 * Fetch a single public gallery post by ID and atomically increment viewsCount.
 * GET /api/v1/gallery/:id
 */
export const getGalleryPostById = asyncHandler(async (req, res) => {
  const { id } = req.params;

  if (!mongoose.Types.ObjectId.isValid(id)) {
    throw ApiError.notFound('Gallery post not found');
  }

  // Atomically increment viewsCount and fetch the document in one atomic query
  const generation = await Generation.findOneAndUpdate(
    {
      _id: id,
      isPublic: true,
      moderationStatus: MODERATION_STATUS.APPROVED,
    },
    { $inc: { viewsCount: 1 } },
    { returnDocument: 'after' }
  ).populate('userId', 'username displayName avatarUrl bio createdAt isPublicProfile');

  if (!generation) {
    throw ApiError.notFound('Gallery post not found');
  }

  let likedSet = new Set();
  if (req.user) {
    const exists = await Like.exists({
      userId: req.user._id,
      generationId: generation._id,
    });
    if (exists) {
      likedSet.add(generation._id.toString());
    }
  }

  res.status(200).json({
    success: true,
    data: formatPublicPost(generation, likedSet),
  });
});

/**
 * Paginated list of public posts created by a specific user.
 * GET /api/v1/gallery/user/:username
 */
export const getUserGalleryPosts = asyncHandler(async (req, res) => {
  const { username } = req.params;

  // Look up user; if not found or isPublicProfile is false, return 404
  const targetUser = await User.findOne({ username });
  if (!targetUser || targetUser.isPublicProfile === false) {
    throw ApiError.notFound('User not found or profile is private');
  }

  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = Math.min(50, Math.max(1, parseInt(req.query.limit || '20', 10)));
  const skip = (page - 1) * limit;

  const filter = {
    userId: targetUser._id,
    isPublic: true,
    moderationStatus: MODERATION_STATUS.APPROVED,
  };

  if (req.query.mediaType) {
    filter.mediaType = req.query.mediaType;
  }
  if (req.query.modelId) {
    filter.modelId = req.query.modelId;
  }

  let sortOption = { publishedAt: -1, createdAt: -1, _id: -1 };
  if (req.query.sort === 'popular') {
    sortOption = { likesCount: -1, createdAt: -1, _id: -1 };
  }

  const [generations, total] = await Promise.all([
    Generation.find(filter)
      .populate('userId', 'username displayName avatarUrl bio createdAt isPublicProfile')
      .sort(sortOption)
      .skip(skip)
      .limit(limit),
    Generation.countDocuments(filter),
  ]);

  let likedSet = new Set();
  if (req.user) {
    const postIds = generations.map((g) => g._id);
    const likes = await Like.find({
      userId: req.user._id,
      generationId: { $in: postIds },
    }).select('generationId');
    likedSet = new Set(likes.map((l) => l.generationId.toString()));
  }

  const data = generations.map((gen) => formatPublicPost(gen, likedSet));

  res.status(200).json({
    success: true,
    data,
    author: targetUser.toPublicJSON(),
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
 * Like a published gallery post.
 * POST /api/v1/gallery/:id/like
 */
export const likePost = asyncHandler(async (req, res) => {
  const { id } = req.params;

  if (!mongoose.Types.ObjectId.isValid(id)) {
    throw ApiError.notFound('Gallery post not found');
  }

  const generation = await Generation.findOne({
    _id: id,
    isPublic: true,
    moderationStatus: MODERATION_STATUS.APPROVED,
  });

  if (!generation) {
    throw ApiError.notFound('Gallery post not found');
  }

  // Create Like record, catching duplicate key error
  try {
    await Like.create({
      userId: req.user._id,
      generationId: generation._id,
    });
  } catch (err) {
    if (err.code === 11000) {
      throw ApiError.conflict('You have already liked this post');
    }
    throw err;
  }

  // Atomically increment likesCount
  const updated = await Generation.findByIdAndUpdate(
    generation._id,
    { $inc: { likesCount: 1 } },
    { returnDocument: 'after' }
  );

  res.status(200).json({
    success: true,
    message: 'Post liked successfully',
    data: {
      generationId: generation._id,
      likesCount: updated ? updated.likesCount : generation.likesCount + 1,
      isLiked: true,
    },
  });
});

/**
 * Unlike a published gallery post (idempotent).
 * DELETE /api/v1/gallery/:id/like
 */
export const unlikePost = asyncHandler(async (req, res) => {
  const { id } = req.params;

  if (!mongoose.Types.ObjectId.isValid(id)) {
    throw ApiError.notFound('Gallery post not found');
  }

  const generation = await Generation.findOne({
    _id: id,
    isPublic: true,
    moderationStatus: MODERATION_STATUS.APPROVED,
  });

  if (!generation) {
    throw ApiError.notFound('Gallery post not found');
  }

  const deletedLike = await Like.findOneAndDelete({
    userId: req.user._id,
    generationId: generation._id,
  });

  let currentLikesCount = generation.likesCount;
  if (deletedLike) {
    // Atomically decrement likesCount clamped to minimum 0
    const updated = await Generation.findOneAndUpdate(
      {
        _id: generation._id,
        likesCount: { $gt: 0 },
      },
      { $inc: { likesCount: -1 } },
      { returnDocument: 'after' }
    );

    currentLikesCount = updated ? updated.likesCount : 0;
  }


  res.status(200).json({
    success: true,
    message: 'Post unliked successfully',
    data: {
      generationId: generation._id,
      likesCount: currentLikesCount,
      isLiked: false,
    },
  });
});

/**
 * Submit a community moderation report on a gallery post.
 * POST /api/v1/gallery/:id/report
 */
export const reportPost = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { reason, details = '' } = req.body;

  if (!mongoose.Types.ObjectId.isValid(id)) {
    throw ApiError.notFound('Gallery post not found');
  }

  const generation = await Generation.findOne({
    _id: id,
    isPublic: true,
    moderationStatus: MODERATION_STATUS.APPROVED,
  });

  if (!generation) {
    throw ApiError.notFound('Gallery post not found');
  }

  // Create report document
  const report = await Report.create({
    userId: req.user._id,
    generationId: generation._id,
    reason,
    details: details || '',
    status: 'pending',
  });

  // Atomically increment generation reportsCount
  await Generation.findByIdAndUpdate(generation._id, {
    $inc: { reportsCount: 1 },
  });

  res.status(201).json({
    success: true,
    message: 'Report submitted successfully. Our moderation team will review this content.',
    data: {
      reportId: report._id,
      generationId: generation._id,
      status: report.status,
    },
  });
});
