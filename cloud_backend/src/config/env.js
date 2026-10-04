/**
 * Environment Configuration & Validation
 * Loads .env and validates mandatory environment variables at startup.
 */

import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env from project root
dotenv.config({ path: path.resolve(__dirname, '../../.env') });

const requiredEnvVars = [
  'MONGODB_URI',
  'JWT_ACCESS_SECRET',
  'JWT_REFRESH_SECRET',
];

for (const envVar of requiredEnvVars) {
  if (!process.env[envVar]) {
    throw new Error(
      `[Config Error] Missing mandatory environment variable: ${envVar}. Please check your .env file.`
    );
  }
}

export const env = Object.freeze({
  PORT: parseInt(process.env.PORT || '5000', 10),
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

