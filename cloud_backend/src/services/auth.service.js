/**
 * Authentication Business Logic Service
 * User registration, credential verification, JWT generation, and token rotation.
 *
 * Sessions (one per login/device, models/Session.js):
 * - Refresh tokens carry { id, sid, gen }. A refresh with the session's current
 *   generation rotates it (gen + 1) and affects no other session.
 * - The previous generation stays valid for REFRESH_GRACE_SECONDS after a
 *   rotation; it gets a token for the current generation without rotating again,
 *   so parallel refreshes from one device end up with equivalent tokens.
 * - Any older token is reuse: that session alone is revoked.
 * - Tokens from before sessions existed (no sid) are checked against the old
 *   User.refreshTokenHash slot and become a session on first use.
 */

import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import mongoose from 'mongoose';
import { User } from '../models/User.js';
import { creditService } from './credit.service.js';
import { ApiError } from '../utils/ApiError.js';
import { Session } from '../models/Session.js';
import {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
  verifyRefreshTokenIgnoringExpiry,
  tokenExpiry,
} from '../utils/jwt.js';
import { TRANSACTION_TYPES } from '../config/constants.js';
import { env } from '../config/env.js';
import { canUseTransactions } from '../config/database.js';

function hashTokenForStorage(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

const LEGACY_DEVICE_LABEL = 'Signed in before device sessions';

/** Device label from the client, else a trimmed User-Agent. */
export function deviceLabelFrom(label, userAgent) {
  const text = (label || userAgent || '').replace(/[\u0000-\u001f\u007f]/g, '').trim();
  return (text || 'Unknown device').slice(0, 64);
}

function sessionEnded() {
  return ApiError.unauthorized('Session ended. Please log in again.');
}

class AuthService {
  /**
   * Register a new user, grant initial signup bonus credits, and issue tokens.
   * @param {Object} params - { username, email, password, deviceLabel }
   * @returns {Promise<{ user: Object, accessToken: string, refreshToken: string }>}
   */
  async register({ username, email, password, deviceLabel }) {
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

      user.lastLoginAt = new Date();
      if (useTransaction) {
        await user.save({ session });
        await session.commitTransaction();
      } else {
        await user.save();
      }

      // 3. Issue authentication tokens for a new device session
      const { accessToken, refreshToken } = await this._startSession(user, deviceLabel);

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
   * @param {Object} params - { email, password, deviceLabel }
   * @returns {Promise<{ user: Object, accessToken: string, refreshToken: string }>}
   */
  async login({ email, password, deviceLabel }) {
    const user = await User.findOne({ email }).select('+password');
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

    user.lastLoginAt = new Date();
    await user.save();
    const { accessToken, refreshToken } = await this._startSession(user, deviceLabel);

    return {
      user,
      accessToken,
      refreshToken,
    };
  }

  /**
   * Exchange a refresh token for a new token pair (see the header comment).
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

    const user = await User.findById(decoded.id);
    if (!user || !user.isActive) {
      throw ApiError.unauthorized('User not found or account deactivated.');
    }

    if (decoded.sid) return this._refreshSession(user, decoded);
    return this._refreshLegacy(user, refreshToken);
  }

  /**
   * Revoke the session a refresh token belongs to. Idempotent. Works with an
   * expired token, as long as this server signed it.
   * @param {string} refreshToken
   * @returns {Promise<{ revoked: boolean }>}
   */
  async logout(refreshToken) {
    let decoded;
    try {
      decoded = verifyRefreshTokenIgnoringExpiry(refreshToken);
    } catch {
      throw ApiError.unauthorized('Invalid refresh token.');
    }
    if (decoded.sid) {
      const res = await Session.updateOne(
        { _id: decoded.sid, user: decoded.id, revokedAt: null },
        { $set: { revokedAt: new Date(), revokeReason: 'logout' } }
      );
      return { revoked: res.modifiedCount === 1 };
    }
    // Legacy token: clear the old slot only if this is the token in it.
    const user = await User.findById(decoded.id).select('+refreshTokenHash');
    if (user?.refreshTokenHash && (await this._matchesLegacyHash(refreshToken, user.refreshTokenHash))) {
      await User.updateOne(
        { _id: user._id, refreshTokenHash: user.refreshTokenHash },
        { $set: { refreshTokenHash: null } }
      );
      return { revoked: true };
    }
    return { revoked: false };
  }

  /**
   * Revoke every session of a user, including a not-yet-migrated legacy token.
   * Access tokens already issued stay valid until they expire (JWT_ACCESS_EXPIRES).
   * @returns {Promise<{ revoked: number }>}
   */
  async logoutAll(userId) {
    const res = await Session.updateMany(
      { user: userId, revokedAt: null },
      { $set: { revokedAt: new Date(), revokeReason: 'logout_all' } }
    );
    await User.updateOne({ _id: userId }, { $set: { refreshTokenHash: null, legacySession: null } });
    return { revoked: res.modifiedCount };
  }

  // --- internals ---

  async _startSession(user, deviceLabel, { familyId = crypto.randomUUID() } = {}) {
    const session = new Session({
      user: user._id,
      familyId,
      generation: 0,
      deviceLabel: deviceLabelFrom(deviceLabel),
      lastUsedAt: new Date(),
      expiresAt: new Date(Date.now() + 60 * 1000), // replaced below with the token's expiry
    });
    const tokens = this._issueTokens(user, session._id, 0);
    session.expiresAt = tokenExpiry(tokens.refreshToken) || session.expiresAt;
    await session.save();
    return { ...tokens, session };
  }

  _issueTokens(user, sessionId, generation) {
    const sid = String(sessionId);
    return {
      accessToken: signAccessToken({ id: user._id, role: user.role, sid }),
      refreshToken: signRefreshToken({ id: user._id, sid, gen: generation }),
    };
  }

  async _refreshSession(user, decoded) {
    const gen = Number(decoded.gen);
    if (!Number.isInteger(gen) || gen < 0) throw sessionEnded();

    for (let attempt = 0; attempt < 3; attempt += 1) {
      const now = new Date();
      const session = await Session.findOne({ _id: decoded.sid, user: user._id }).lean();
      if (!session || session.revokedAt || session.expiresAt <= now) throw sessionEnded();

      if (gen === session.generation) {
        // Current token: rotate. Conditional on the generation, so only one
        // parallel request rotates; the others take the grace path below.
        const next = gen + 1;
        const tokens = this._issueTokens(user, session._id, next);
        const rotated = await Session.findOneAndUpdate(
          { _id: session._id, generation: gen, revokedAt: null },
          {
            $set: {
              generation: next,
              previousValidUntil: new Date(now.getTime() + env.REFRESH_GRACE_SECONDS * 1000),
              lastUsedAt: now,
              expiresAt: tokenExpiry(tokens.refreshToken) || session.expiresAt,
            },
          },
          { returnDocument: 'after' }
        );
        if (rotated) return { accessToken: tokens.accessToken, refreshToken: tokens.refreshToken };
        continue; // someone rotated first; re-read
      }

      if (gen === session.generation - 1 && session.previousValidUntil && session.previousValidUntil >= now) {
        // Parallel request with the token just rotated: same generation as the winner.
        await Session.updateOne({ _id: session._id }, { $set: { lastUsedAt: now } });
        const tokens = this._issueTokens(user, session._id, session.generation);
        return { accessToken: tokens.accessToken, refreshToken: tokens.refreshToken };
      }

      // An old token was replayed: end this session only.
      await Session.updateOne(
        { _id: session._id, revokedAt: null },
        { $set: { revokedAt: now, revokeReason: 'refresh_token_reuse' } }
      );
      throw ApiError.unauthorized('Session compromised. Please log in again.');
    }
    throw ApiError.conflict('Session is being refreshed. Please retry.');
  }

  async _matchesLegacyHash(refreshToken, storedHash) {
    if (await bcrypt.compare(hashTokenForStorage(refreshToken), storedHash)) return true;
    return bcrypt.compare(refreshToken, storedHash);
  }

  /** A token from before sessions: becomes a session on first use. */
  async _refreshLegacy(user, refreshToken) {
    const tokenSha256 = hashTokenForStorage(refreshToken);

    for (let attempt = 0; attempt < 3; attempt += 1) {
      const now = new Date();
      const doc = await User.findById(user._id).select('+refreshTokenHash +legacySession').lean();

      // Already migrated by a parallel or earlier request with this same token.
      if (doc.legacySession?.tokenSha256 === tokenSha256) {
        const graceEnds = new Date(new Date(doc.legacySession.at).getTime() + env.REFRESH_GRACE_SECONDS * 1000);
        const session = await Session.findById(doc.legacySession.sessionId).lean();
        if (!session || session.revokedAt || session.expiresAt <= now) throw sessionEnded();
        if (graceEnds >= now) {
          const tokens = this._issueTokens(user, session._id, session.generation);
          return { accessToken: tokens.accessToken, refreshToken: tokens.refreshToken };
        }
        await Session.updateOne(
          { _id: session._id, revokedAt: null },
          { $set: { revokedAt: now, revokeReason: 'refresh_token_reuse' } }
        );
        throw ApiError.unauthorized('Session compromised. Please log in again.');
      }

      if (!doc.refreshTokenHash || !(await this._matchesLegacyHash(refreshToken, doc.refreshTokenHash))) {
        // Not the token in the old slot. Other sessions are unaffected.
        throw ApiError.unauthorized('Invalid session. Please log in again.');
      }

      // Migrate: create the session, then claim the old slot. If another request
      // claimed it first, drop ours and join theirs on the next pass.
      const { accessToken, refreshToken: newRefresh, session } = await this._startSession(
        user,
        LEGACY_DEVICE_LABEL
      );
      const claimed = await User.updateOne(
        { _id: user._id, refreshTokenHash: doc.refreshTokenHash },
        { $set: { refreshTokenHash: null, legacySession: { sessionId: session._id, tokenSha256, at: now } } }
      );
      if (claimed.modifiedCount === 1) return { accessToken, refreshToken: newRefresh };
      await Session.deleteOne({ _id: session._id });
    }
    throw ApiError.conflict('Session is being refreshed. Please retry.');
  }
}

export const authService = new AuthService();
