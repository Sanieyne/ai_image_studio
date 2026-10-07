/**
 * Session Mongoose Model
 * One document per login (device). Refresh tokens carry the session id (`sid`)
 * and a generation number (`gen`); no token values are stored. Each refresh
 * moves the session to the next generation. See services/auth.service.js.
 */

import mongoose from 'mongoose';

const sessionSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    // Groups the tokens of one login; stays the same across rotations.
    familyId: { type: String, required: true },
    // Generation of the current refresh token. Rotating increments it.
    generation: { type: Number, default: 0 },
    // The previous generation is still accepted until this moment, so parallel
    // refreshes with the same token don't count as reuse.
    previousValidUntil: { type: Date, default: null },
    deviceLabel: { type: String, default: 'Unknown device', maxlength: 64 },
    lastUsedAt: { type: Date, default: Date.now },
    // Matches the refresh token's expiry; MongoDB deletes the document after it.
    expiresAt: { type: Date, required: true },
    revokedAt: { type: Date, default: null },
    revokeReason: { type: String, default: null },
  },
  { timestamps: true }
);

sessionSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

export const Session = mongoose.model('Session', sessionSchema);
