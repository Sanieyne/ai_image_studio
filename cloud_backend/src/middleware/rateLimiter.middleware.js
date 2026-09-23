/**
 * Rate Limiting Middleware
 * Protects auth endpoints and general APIs from brute-force and DDoS attacks.
 */

import rateLimit from 'express-rate-limit';

// Strict limiter for authentication endpoints: 5 attempts per minute
export const authLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many authentication attempts from this IP. Please try again after 60 seconds.',
  },
});

// General API limiter: 100 requests per 15 minutes
export const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'API rate limit exceeded. Please slow down your requests.',
  },
});
