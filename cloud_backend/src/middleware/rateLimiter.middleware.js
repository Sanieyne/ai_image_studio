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

// Permissive limiter for public read browsing: 120 requests per minute per IP
export const publicReadLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 120, // 120 requests per minute per IP
  standardHeaders: true,
  legacyHeaders: false,
  validate: { xForwardedForHeader: false, default: true },
  message: {
    success: false,
    message: 'Too many browsing requests from this IP. Please wait a moment before exploring more.',
  },
});

// General API limiter for write operations and authenticated endpoints: 300 requests per 15 minutes
export const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  validate: { xForwardedForHeader: false, default: true },
  skip: (req) => {
    // Completely exempt health check
    if (req.path === '/health' || req.originalUrl?.includes('/health')) {
      return true;
    }
    // Exempt public read endpoints handled by dedicated publicReadLimiter
    if (req.method === 'GET' || req.method === 'OPTIONS') {
      const url = req.originalUrl || req.url || '';
      return (
        url.includes('/gallery') ||
        url.includes('/gpu/offers') ||
        url.includes('/gpu/recommended') ||
        url.includes('/gpu/pricing') ||
        url.includes('/models') ||
        url.includes('/pricing/config') ||
        url.includes('/public')
      );
    }
    // Exempt public interactive calculation endpoints
    if (req.method === 'POST') {
      const url = req.originalUrl || req.url || '';
      if (url.includes('/models/recommend') || url.includes('/models/storage/estimate')) {
        return true;
      }
    }
    return false;
  },
  message: {
    success: false,
    message: 'API rate limit exceeded. Please slow down your requests.',
  },
});

// Strict report limiter: 5 reports per user per hour to prevent griefing
export const reportLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5,
  keyGenerator: (req) => req.user?._id?.toString() || req.ip,
  validate: { xForwardedForHeader: false, default: true },
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many reports submitted. You can only submit up to 5 reports per hour.',
  },
});

