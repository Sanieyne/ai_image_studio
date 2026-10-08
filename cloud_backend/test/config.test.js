import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const secret = () => crypto.randomBytes(48).toString('base64url');

/**
 * Loads the config module in a fresh process, as server startup does, with
 * only the given variables set. Returns { status, stderr }.
 */
function loadConfig(vars) {
  const result = spawnSync(
    process.execPath,
    ['--input-type=module', '-e', "await import('./src/config/env.js'); console.log('loaded');"],
    {
      cwd: backendRoot,
      env: {
        PATH: process.env.PATH,
        NODE_ENV: 'test',
        MONGODB_URI: 'mongodb://127.0.0.1:9/never-connect',
        ...vars,
      },
      encoding: 'utf8',
    }
  );
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

test('starts with two distinct random secrets', () => {
  const r = loadConfig({ JWT_ACCESS_SECRET: secret(), JWT_REFRESH_SECRET: secret() });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /loaded/);
});

test('refuses to start when a secret is shorter than 32 characters', () => {
  const r = loadConfig({ JWT_ACCESS_SECRET: 'x'.repeat(31), JWT_REFRESH_SECRET: secret() });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /JWT_ACCESS_SECRET must be at least 32 characters/);
});

test('refuses to start when both secrets are the same', () => {
  const s = secret();
  const r = loadConfig({ JWT_ACCESS_SECRET: s, JWT_REFRESH_SECRET: s });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /must be different/);
});

test('refuses to start when a secret is missing', () => {
  const r = loadConfig({ JWT_ACCESS_SECRET: secret() });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /Missing mandatory environment variable: JWT_REFRESH_SECRET/);
});

test('rejects a secret whose SHA-256 is on the leaked list', async () => {
  const { validateJwtSecrets } = await import('../src/config/env.js');
  const leaked = secret();
  const leakedHash = crypto.createHash('sha256').update(leaked).digest('hex');

  assert.throws(
    () => validateJwtSecrets(leaked, secret(), [leakedHash]),
    /JWT_ACCESS_SECRET is a publicly known example value/
  );
  assert.throws(
    () => validateJwtSecrets(secret(), leaked, [leakedHash]),
    /JWT_REFRESH_SECRET is a publicly known example value/
  );
  assert.doesNotThrow(() => validateJwtSecrets(secret(), secret(), [leakedHash]));
});

test('the leaked list holds the hashes of both published example secrets', async () => {
  const { LEAKED_SECRET_SHA256 } = await import('../src/config/env.js');
  assert.deepEqual([...LEAKED_SECRET_SHA256], [
    '2435f6badacf38c61241bb4835ed04ae7512595bd9c9bba5d3a9246925b8bfac',
    'eefb249ea0a1e9ed8fd405446d868b3c45974148650f228a7a3650f291add6b7',
  ]);
});

for (const nodeEnv of ['development', 'production', 'test']) {
  test(`secret checks run at startup when NODE_ENV=${nodeEnv}`, () => {
    const s = secret();
    const r = loadConfig({ NODE_ENV: nodeEnv, JWT_ACCESS_SECRET: s, JWT_REFRESH_SECRET: s });
    assert.notEqual(r.status, 0);
    assert.match(r.stderr, /must be different/);
  });
}
