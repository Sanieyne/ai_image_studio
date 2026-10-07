/**
 * Environment Configuration & Validation
 * Loads .env and validates mandatory environment variables at startup.
 */

import dotenv from 'dotenv';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env from project root. Tests never read it: they supply their own
// throwaway values and must not pick up a real database URI or secret.
if (process.env.NODE_ENV !== 'test') {
  dotenv.config({ path: path.resolve(__dirname, '../../.env') });
}

// SHA-256 of JWT secrets that were published in .env.example. Only the hashes
// are kept so the leaked values themselves are not repeated in the source.
export const LEAKED_SECRET_SHA256 = Object.freeze([
  '2435f6badacf38c61241bb4835ed04ae7512595bd9c9bba5d3a9246925b8bfac',
  'eefb249ea0a1e9ed8fd405446d868b3c45974148650f228a7a3650f291add6b7',
]);

export const MIN_SECRET_LENGTH = 32;

const requiredEnvVars = [
  'MONGODB_URI',
  'JWT_ACCESS_SECRET',
  'JWT_REFRESH_SECRET',
];

// Settings that may be omitted in development but must be set in production.
// Later features add their variables here.
const requiredInProductionEnvVars = [];

/**
 * Throws if the JWT secrets are unsafe to run with, in any NODE_ENV.
 */
export function validateJwtSecrets(accessSecret, refreshSecret, leakedHashes = LEAKED_SECRET_SHA256) {
  const secrets = { JWT_ACCESS_SECRET: accessSecret, JWT_REFRESH_SECRET: refreshSecret };
  for (const [name, value] of Object.entries(secrets)) {
    if (typeof value !== 'string' || value.length < MIN_SECRET_LENGTH) {
      throw new Error(
        `[Config Error] ${name} must be at least ${MIN_SECRET_LENGTH} characters. ` +
          `Generate one with: node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"`
      );
    }
    const hash = crypto.createHash('sha256').update(value).digest('hex');
    if (leakedHashes.includes(hash)) {
      throw new Error(
        `[Config Error] ${name} is a publicly known example value and must be replaced with a new random secret.`
      );
    }
  }
  if (accessSecret === refreshSecret) {
    throw new Error('[Config Error] JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must be different.');
  }
}

for (const envVar of requiredEnvVars) {
  if (!process.env[envVar]) {
    throw new Error(
      `[Config Error] Missing mandatory environment variable: ${envVar}. Please check your .env file.`
    );
  }
}

if (process.env.NODE_ENV === 'production') {
  for (const envVar of requiredInProductionEnvVars) {
    if (!process.env[envVar]) {
      throw new Error(
        `[Config Error] Missing environment variable required in production: ${envVar}.`
      );
    }
  }
}

validateJwtSecrets(process.env.JWT_ACCESS_SECRET, process.env.JWT_REFRESH_SECRET);

function positiveInt(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`[Config Error] ${name} must be a positive integer (got "${raw}").`);
  }
  return value;
}

function bool(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  throw new Error(`[Config Error] ${name} must be "true" or "false" (got "${raw}").`);
}

export const env = Object.freeze({
  PORT: parseInt(process.env.PORT || '5000', 10),
  // Listen on loopback by default; nginx is the public entry point.
  HOST: process.env.HOST || '127.0.0.1',
  NODE_ENV: process.env.NODE_ENV || 'development',
  isProduction: process.env.NODE_ENV === 'production',
  isDevelopment: process.env.NODE_ENV === 'development',
  isTest: process.env.NODE_ENV === 'test',

  MONGODB_URI: process.env.MONGODB_URI,

  JWT_ACCESS_SECRET: process.env.JWT_ACCESS_SECRET,
  JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET,
  JWT_ACCESS_EXPIRES: process.env.JWT_ACCESS_EXPIRES || '15m',
  JWT_REFRESH_EXPIRES: process.env.JWT_REFRESH_EXPIRES || '60d',

  BCRYPT_SALT: parseInt(process.env.BCRYPT_SALT || '12', 10),
  FREE_CREDITS: parseInt(process.env.FREE_CREDITS || '10', 10),

  VASTAI_API_KEY: process.env.VASTAI_API_KEY || '',
  VASTAI_API_BASE: process.env.VASTAI_API_BASE || 'https://console.vast.ai/api/v0',

  // GPU rental and billing
  GPU_MAX_ACTIVE_PER_USER: positiveInt('GPU_MAX_ACTIVE_PER_USER', 1),
  BILLING_INTERVAL_MS: positiveInt('BILLING_INTERVAL_MS', 60_000),
  RECONCILE_INTERVAL_MS: positiveInt('RECONCILE_INTERVAL_MS', 10 * 60_000),
  // Vast.ai instances carrying our label but no active record are only logged unless this is true.
  RECONCILE_DESTROY_ORPHANS: bool('RECONCILE_DESTROY_ORPHANS', false),

  MEDIA_STORAGE_PATH: process.env.MEDIA_STORAGE_PATH || '/var/www/media',
  MEDIA_PUBLIC_URL: (process.env.MEDIA_PUBLIC_URL || 'https://cosmic-gen.com/media').replace(/\/+$/, ''),
  GOOGLE_APPLICATION_CREDENTIALS: process.env.GOOGLE_APPLICATION_CREDENTIALS || '',

  // Cloudflare R2 model weights storage (S3-compatible). Optional at boot —
  // modelStorage.service.js throws a clear error if used unconfigured.
  R2_ACCOUNT_ID: process.env.R2_ACCOUNT_ID || '',
  R2_ENDPOINT: (process.env.R2_ENDPOINT || '').replace(/\/+$/, ''),
  R2_ACCESS_KEY_ID: process.env.R2_ACCESS_KEY_ID || '',
  R2_SECRET_ACCESS_KEY: process.env.R2_SECRET_ACCESS_KEY || '',
  R2_BUCKET_NAME: process.env.R2_BUCKET_NAME || '',
  R2_READONLY_ACCESS_KEY_ID: process.env.R2_READONLY_ACCESS_KEY_ID || '',
  R2_READONLY_SECRET_ACCESS_KEY: process.env.R2_READONLY_SECRET_ACCESS_KEY || '',
});

