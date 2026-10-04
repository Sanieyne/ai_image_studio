/**
 * Authentication Business Logic Service
 * User registration, credential verification, JWT generation, and token rotation.
 */

import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import mongoose from 'mongoose';
import { User } from '../models/User.js';
import { creditService } from './credit.service.js';
import { ApiError } from '../utils/ApiError.js';
import { signAccessToken, signRefreshToken, verifyRefreshToken } from '../utils/jwt.js';
import { TRANSACTION_TYPES } from '../config/constants.js';
import { env } from '../config/env.js';
import { canUseTransactions } from '../config/database.js';

function hashTokenForStorage(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

class AuthService {
  /**
   * Register a new user, grant initial signup bonus credits, and issue tokens.
   * @param {Object} params - { username, email, password }
   * @returns {Promise<{ user: Object, accessToken: string, refreshToken: string }>}
   */
  async register({ username, email, password }) {
    // Check if email or username is already taken
    const existingEmail = await User.findOne({ email });
    if (existingEmail) {
      throw ApiError.conflict('An account with this email address already exists.');
    }

    const existingUsername = await User.findOne({ username });
    if (existingUsername) {
      throw ApiError.conflict('Username is already taken. Please choose another.');
    }

    let session = null;
    let useTransaction = false;
    if (canUseTransactions()) {
      try {
        session = await mongoose.startSession();
        session.startTransaction();
        useTransaction = true;
      } catch {
        if (session) {
          try { session.endSession(); } catch {}
          session = null;
        }
        useTransaction = false;
      }
    }

    try {
      // 1. Create user with 0 starting credits initially (to be credited atomically)
      const user = new User({
        username,
        email,
        password,
        credits: 0,
      });
      if (useTransaction) {
        await user.save({ session });
      } else {
        await user.save();
      }

      // 2. Grant initial bonus credits via CreditService within the same transaction
      if (env.FREE_CREDITS > 0) {
        await creditService.addCredits(
          user._id,
          env.FREE_CREDITS,
          TRANSACTION_TYPES.BONUS,
          'Welcome bonus credits for new account',
          { signupBonus: true },
          useTransaction ? session : null
        );
      }

      // 3. Issue authentication tokens
      const accessToken = signAccessToken({ id: user._id, role: user.role });
      const refreshToken = signRefreshToken({ id: user._id });

      // 4. Hash and store refresh token for secure rotation
      const salt = await bcrypt.genSalt(env.BCRYPT_SALT);
      user.refreshTokenHash = await bcrypt.hash(hashTokenForStorage(refreshToken), salt);
      user.lastLoginAt = new Date();
      if (useTransaction) {
        await user.save({ session });
        await session.commitTransaction();
      } else {
        await user.save();
      }

      // Refetch user to get clean JSON with populated credits
      const savedUser = await User.findById(user._id);

      return {
        user: savedUser,
        accessToken,
        refreshToken,
      };
    } catch (error) {
      if (useTransaction && session) {
        try { await session.abortTransaction(); } catch {}
      }
      throw error;
    } finally {
      if (useTransaction && session) {
        try { session.endSession(); } catch {}
      }
    }
  }

  /**
   * Authenticate user with email and password and issue fresh tokens.
   * @param {Object} params - { email, password }
   * @returns {Promise<{ user: Object, accessToken: string, refreshToken: string }>}
   */
  async login({ email, password }) {
    const user = await User.findOne({ email }).select('+password +refreshTokenHash');
    if (!user) {
      throw ApiError.unauthorized('Invalid email or password.');
    }

    if (!user.isActive) {
      throw ApiError.unauthorized('Account is deactivated. Please contact support.');
    }

    const isPasswordValid = await user.comparePassword(password);
    if (!isPasswordValid) {
      throw ApiError.unauthorized('Invalid email or password.');
    }

    const accessToken = signAccessToken({ id: user._id, role: user.role });
    const refreshToken = signRefreshToken({ id: user._id });

    // Store hashed refresh token
    const salt = await bcrypt.genSalt(env.BCRYPT_SALT);
    user.refreshTokenHash = await bcrypt.hash(hashTokenForStorage(refreshToken), salt);
    user.lastLoginAt = new Date();
    await user.save();

    return {
      user,
      accessToken,
      refreshToken,
    };
  }

  /**
   * Verify refresh token, ensure single-use rotation, and issue a fresh pair of tokens.
   * @param {string} refreshToken
   * @returns {Promise<{ accessToken: string, refreshToken: string }>}
   */
  async refresh(refreshToken) {
    let decoded;
    try {
      decoded = verifyRefreshToken(refreshToken);
    } catch (err) {
      throw ApiError.unauthorized('Invalid or expired refresh token. Please log in again.');
    }

    const user = await User.findById(decoded.id).select('+refreshTokenHash');
    if (!user || !user.isActive) {
      throw ApiError.unauthorized('User not found or account deactivated.');
    }

    if (!user.refreshTokenHash) {
      throw ApiError.unauthorized('Invalid session. Please log in again.');
    }

    const preHashed = hashTokenForStorage(refreshToken);
    let isMatch = await bcrypt.compare(preHashed, user.refreshTokenHash);
    if (!isMatch) {
      isMatch = await bcrypt.compare(refreshToken, user.refreshTokenHash);
    }

    if (!isMatch) {
      // Possible token reuse attack - invalidate stored refresh token
      user.refreshTokenHash = null;
      await user.save();
      throw ApiError.unauthorized('Session compromised. Please log in again.');
    }

    // Rotate tokens
    const newAccessToken = signAccessToken({ id: user._id, role: user.role });
    const newRefreshToken = signRefreshToken({ id: user._id });

    const salt = await bcrypt.genSalt(env.BCRYPT_SALT);
    user.refreshTokenHash = await bcrypt.hash(hashTokenForStorage(newRefreshToken), salt);
    await user.save();

    return {
      accessToken: newAccessToken,
      refreshToken: newRefreshToken,
    };
  }
}

export const authService = new AuthService();
