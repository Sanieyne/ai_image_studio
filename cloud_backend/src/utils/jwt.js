/**
 * JSON Web Token Helper
 * Secure signing and verification routines for access and refresh tokens.
 */

import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

import crypto from 'crypto';

export function signAccessToken(payload) {
  return jwt.sign(payload, env.JWT_ACCESS_SECRET, {
    expiresIn: env.JWT_ACCESS_EXPIRES,
  });
}

export function signRefreshToken(payload) {
  return jwt.sign(
    {
      ...payload,
      jti: crypto.randomUUID(),
    },
    env.JWT_REFRESH_SECRET,
    {
      expiresIn: env.JWT_REFRESH_EXPIRES,
    }
  );
}

export function verifyAccessToken(token) {
  return jwt.verify(token, env.JWT_ACCESS_SECRET, { algorithms: ['HS256'] });
}

export function verifyRefreshToken(token) {
  return jwt.verify(token, env.JWT_REFRESH_SECRET, { algorithms: ['HS256'] });
}

/** Signature and algorithm are still checked; only expiry is ignored (used by logout). */
export function verifyRefreshTokenIgnoringExpiry(token) {
  return jwt.verify(token, env.JWT_REFRESH_SECRET, { algorithms: ['HS256'], ignoreExpiration: true });
}

/** Expiry of a token this server signed, as a Date. */
export function tokenExpiry(token) {
  const { exp } = jwt.decode(token) || {};
  return exp ? new Date(exp * 1000) : null;
}
