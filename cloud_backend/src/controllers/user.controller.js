/**
 * User & Account Controller
 * HTTP handlers for user profile, credit status, and paginated transaction history.
 */

import { asyncHandler } from '../utils/asyncHandler.js';
import { Transaction } from '../models/Transaction.js';
import { User } from '../models/User.js';
import { ApiError } from '../utils/ApiError.js';

export const getMe = asyncHandler(async (req, res) => {
  const user = await User.findById(req.user._id);
  if (!user) {
    throw ApiError.notFound('User not found');
  }

  res.status(200).json({
    success: true,
    data: user,
  });
});

export const getCredits = asyncHandler(async (req, res) => {
  const user = await User.findById(req.user._id).select(
    'credits totalCreditsPurchased totalCreditsUsed storageQuotaGB storageUsedGB'
  );

  if (!user) {
    throw ApiError.notFound('User not found');
  }

  res.status(200).json({
    success: true,
    data: {
      credits: user.credits,
      totalCreditsPurchased: user.totalCreditsPurchased,
      totalCreditsUsed: user.totalCreditsUsed,
      storageQuotaGB: user.storageQuotaGB,
      storageUsedGB: user.storageUsedGB,
    },
  });
});

export const getTransactions = asyncHandler(async (req, res) => {
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit || '20', 10)));
  const skip = (page - 1) * limit;

  const filter = { user: req.user._id };

  const [transactions, total] = await Promise.all([
    Transaction.find(filter)
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
 * Public User Profile Controller
 * Returns strictly safe, allowlisted public profile metadata for a username.
 * If user does not exist or has isPublicProfile set to false, returns 404.
 * GET /api/v1/users/:username/public
 */
export const getPublicProfile = asyncHandler(async (req, res) => {
  const { username } = req.params;

  const user = await User.findOne({
    username: { $regex: new RegExp(`^${username}$`, 'i') },
    isActive: true,
  });

  if (!user || !user.isPublicProfile) {
    throw ApiError.notFound('User not found');
  }

  res.status(200).json({
    success: true,
    data: user.toPublicJSON(),
  });
});

/**
 * Update Profile Controller
 * Lets authenticated user update their displayName, avatarUrl, bio, and isPublicProfile.
 * PATCH /api/v1/users/me/profile
 */
export const updateProfile = asyncHandler(async (req, res) => {
  const user = await User.findById(req.user._id);
  if (!user) {
    throw ApiError.notFound('User not found');
  }

  const { displayName, avatarUrl, bio, isPublicProfile } = req.body;

  if (displayName !== undefined) {
    user.displayName = displayName;
  }
  if (avatarUrl !== undefined) {
    user.avatarUrl = avatarUrl || null;
  }
  if (bio !== undefined) {
    user.bio = bio;
  }
  if (isPublicProfile !== undefined) {
    user.isPublicProfile = Boolean(isPublicProfile);
  }

  await user.save();

  res.status(200).json({
    success: true,
    message: 'Profile updated successfully',
    data: user,
  });
});

