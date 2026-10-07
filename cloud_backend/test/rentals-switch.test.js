import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** Run a snippet in a fresh process with GPU_RENTALS_ENABLED as given (unset = default). */
function run(snippet, rentalsEnabled) {
  const env = { ...process.env };
  delete env.GPU_RENTALS_ENABLED;
  if (rentalsEnabled !== undefined) env.GPU_RENTALS_ENABLED = rentalsEnabled;
  const r = spawnSync(process.execPath, ['--import', './test/setup.js', '--input-type=module', '-e', snippet], {
    cwd: backendRoot,
    env: { ...env, RENTALS_SWITCH_UNDER_TEST: rentalsEnabled ?? '' },
    encoding: 'utf8',
  });
  return { status: r.status, out: r.stdout.trim(), err: r.stderr };
}

// test/setup.js turns rentals on for the other tests; undo that for the default case.
const DEFAULT_PRELUDE = `
  if (process.env.RENTALS_SWITCH_UNDER_TEST === '') delete process.env.GPU_RENTALS_ENABLED;
  else process.env.GPU_RENTALS_ENABLED = process.env.RENTALS_SWITCH_UNDER_TEST;
`;

test('rentals are paused by default: rent answers 503 with the message, before touching anything', () => {
  const r = run(`${DEFAULT_PRELUDE}
    const { gpuProviderService } = await import('./src/services/gpuProvider.service.js');
    try { await gpuProviderService.rentGPU({ userId: 'u1', offerId: '1', storageGB: 50 }); console.log('rented'); }
    catch (e) { console.log(JSON.stringify({ code: e.statusCode, message: e.message })); }
  `);
  assert.equal(r.status, 0, r.err);
  assert.deepEqual(JSON.parse(r.out), { code: 503, message: 'Cloud GPU rentals are paused while we upgrade them.' });
});

test('GET /gpu/rentals/status tells the app whether rentals are open', async () => {
  const snippet = `${DEFAULT_PRELUDE}
    const request = (await import('supertest')).default;
    const { createApp } = await import('./src/app.js');
    const res = await request(createApp()).get('/api/v1/gpu/rentals/status');
    console.log(JSON.stringify({ status: res.status, data: res.body.data }));
  `;
  const paused = run(snippet);
  assert.equal(paused.status, 0, paused.err);
  assert.deepEqual(JSON.parse(paused.out), {
    status: 200,
    data: { rentalsEnabled: false, message: 'Cloud GPU rentals are paused while we upgrade them.' },
  });
  const open = run(snippet, 'true');
  assert.deepEqual(JSON.parse(open.out).data, { rentalsEnabled: true, message: null });
});
