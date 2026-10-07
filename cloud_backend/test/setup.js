/**
 * Loaded before every test file (node --import). Gives the backend throwaway
 * configuration so no test can pick up a real secret, API key or database.
 */

import crypto from 'crypto';

const randomSecret = () => crypto.randomBytes(48).toString('base64url');

// Anything that could point at a live service is removed first.
for (const name of Object.keys(process.env)) {
  if (/^(MONGODB_|JWT_|VASTAI_|R2_|GOOGLE_|GCP_|MEDIA_)/.test(name)) {
    delete process.env[name];
  }
}

process.env.NODE_ENV = 'test';
process.env.JWT_ACCESS_SECRET = randomSecret();
process.env.JWT_REFRESH_SECRET = randomSecret();
// Placeholder only; tests that need a database use helpers/db.js, which
// starts mongodb-memory-server and connects mongoose to it directly.
process.env.MONGODB_URI = 'mongodb://127.0.0.1:9/never-connect';
