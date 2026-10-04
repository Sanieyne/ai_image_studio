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
  return jwt.verify(token, env.JWT_ACCESS_SECRET);
}

export function verifyRefreshToken(token) {
  return jwt.verify(token, env.JWT_REFRESH_SECRET);
}
