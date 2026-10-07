import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import request from 'supertest';
import { startTestDb } from './helpers/db.js';
import { makeUser } from './helpers/factories.js';
import { authService } from '../src/services/auth.service.js';
import { signRefreshToken } from '../src/utils/jwt.js';
import { Session } from '../src/models/Session.js';
import { User } from '../src/models/User.js';
import { createApp } from '../src/app.js';

const PASSWORD = 'Password-123456';

/** Older app versions' tokens: no sid, stored in the single User.refreshTokenHash slot. */
async function giveLegacyToken(user) {
  const token = signRefreshToken({ id: user._id });
  const sha = crypto.createHash('sha256').update(token).digest('hex');
  await User.updateOne({ _id: user._id }, { $set: { refreshTokenHash: await bcrypt.hash(sha, 4) } });
  return token;
}

/** Pretend the grace period after the last rotation is over. */
const endGrace = (sessionId) =>
  Session.updateOne({ _id: sessionId }, { $set: { previousValidUntil: new Date(Date.now() - 1000) } });

const sidOf = (token) => jwt.decode(token).sid;
const genOf = (token) => jwt.decode(token).gen;

describe('sessions', () => {
  let db;
  before(async () => { db = await startTestDb(); await Session.init(); });
  after(async () => { await db.stop(); });
  beforeEach(async () => { await db.clear(); });

  test('each login is its own session; two devices refresh independently', async () => {
    const user = await makeUser(10);
    const laptop = await authService.login({ email: user.email, password: PASSWORD, deviceLabel: 'Laptop' });
    const desktop = await authService.login({ email: user.email, password: PASSWORD, deviceLabel: 'Desktop' });
    assert.notEqual(sidOf(laptop.refreshToken), sidOf(desktop.refreshToken));

    let a = laptop.refreshToken;
    let b = desktop.refreshToken;
    for (let i = 0; i < 3; i += 1) {
      a = (await authService.refresh(a)).refreshToken;
      b = (await authService.refresh(b)).refreshToken;
    }
    assert.equal(genOf(a), 3);
    assert.equal(genOf(b), 3);

    const sessions = await Session.find({ user: user._id }).sort({ deviceLabel: 1 }).lean();
    assert.deepEqual(sessions.map((s) => [s.deviceLabel, s.generation, s.revokedAt]), [
      ['Desktop', 3, null],
      ['Laptop', 3, null],
    ]);
  });

  test('reusing an old token revokes that session only', async () => {
    const user = await makeUser(10);
    const one = await authService.login({ email: user.email, password: PASSWORD, deviceLabel: 'One' });
    const two = await authService.login({ email: user.email, password: PASSWORD, deviceLabel: 'Two' });

    const stolen = one.refreshToken;
    const rotated = await authService.refresh(stolen);
    await endGrace(sidOf(stolen));

    await assert.rejects(authService.refresh(stolen), /Session compromised/);
    // The legitimate holder of session one is logged out too (that is the point)...
    await assert.rejects(authService.refresh(rotated.refreshToken), /Session ended/);
    const s1 = await Session.findById(sidOf(stolen)).lean();
    assert.equal(s1.revokeReason, 'refresh_token_reuse');
    // ...but the other device is untouched.
    const ok = await authService.refresh(two.refreshToken);
    assert.equal(genOf(ok.refreshToken), 1);
  });

  test('parallel refreshes with the same token inside the grace window all succeed', async () => {
    const user = await makeUser(10);
    const { refreshToken } = await authService.login({ email: user.email, password: PASSWORD });

    const results = await Promise.all(Array.from({ length: 6 }, () => authService.refresh(refreshToken)));
    // Exactly one rotation happened; every response carries the new generation.
    assert.deepEqual(new Set(results.map((r) => genOf(r.refreshToken))), new Set([1]));
    const session = await Session.findById(sidOf(refreshToken)).lean();
    assert.equal(session.generation, 1);
    assert.equal(session.revokedAt, null);

    // Whichever response the app kept, it keeps working.
    const next = await authService.refresh(results[4].refreshToken);
    assert.equal(genOf(next.refreshToken), 2);
  });

  test('the previous token works for the grace period only', async () => {
    const user = await makeUser(10);
    const { refreshToken: t0 } = await authService.login({ email: user.email, password: PASSWORD });
    await authService.refresh(t0); // gen 0 -> 1
    const late = await authService.refresh(t0); // still inside the grace period
    assert.equal(genOf(late.refreshToken), 1);

    await endGrace(sidOf(t0));
    await assert.rejects(authService.refresh(t0), /Session compromised/);
  });

  test('a token from before sessions becomes a session on first use', async () => {
    const user = await makeUser(10);
    const legacy = await giveLegacyToken(user);

    const migrated = await authService.refresh(legacy);
    const sid = sidOf(migrated.refreshToken);
    assert.ok(sid);
    const session = await Session.findById(sid).lean();
    assert.equal(session.deviceLabel, 'Signed in before device sessions');
    const doc = await User.findById(user._id).select('+refreshTokenHash +legacySession').lean();
    assert.equal(doc.refreshTokenHash, null);
    assert.equal(String(doc.legacySession.sessionId), sid);

    // It keeps rotating like any session.
    assert.equal(genOf((await authService.refresh(migrated.refreshToken)).refreshToken), 1);
  });

  test('parallel first refreshes with one legacy token create a single session', async () => {
    const user = await makeUser(10);
    const legacy = await giveLegacyToken(user);
    const results = await Promise.all(Array.from({ length: 5 }, () => authService.refresh(legacy)));
    assert.equal(new Set(results.map((r) => sidOf(r.refreshToken))).size, 1);
    assert.equal(await Session.countDocuments({ user: user._id }), 1);
  });

  test('a legacy token replayed after the grace period revokes only its new session', async () => {
    const user = await makeUser(10);
    const legacy = await giveLegacyToken(user);
    const migrated = await authService.refresh(legacy);
    const other = await authService.login({ email: user.email, password: PASSWORD });
    await User.updateOne({ _id: user._id }, { $set: { 'legacySession.at': new Date(Date.now() - 60_000) } });

    await assert.rejects(authService.refresh(legacy), /Session compromised/);
    await assert.rejects(authService.refresh(migrated.refreshToken), /Session ended/);
    assert.ok(await authService.refresh(other.refreshToken));
  });

  test('a legacy token that is not the stored one is rejected without touching anything', async () => {
    const user = await makeUser(10);
    await giveLegacyToken(user);
    const session = await authService.login({ email: user.email, password: PASSWORD });
    const wrong = signRefreshToken({ id: user._id });
    await assert.rejects(authService.refresh(wrong), /Invalid session/);
    assert.ok((await User.findById(user._id).select('+refreshTokenHash').lean()).refreshTokenHash);
    assert.ok(await authService.refresh(session.refreshToken));
  });

  test('logout ends this session only; logout-all ends every session and the legacy slot', async () => {
    const user = await makeUser(10);
    const a = await authService.login({ email: user.email, password: PASSWORD });
    const b = await authService.login({ email: user.email, password: PASSWORD });
    const c = await authService.login({ email: user.email, password: PASSWORD });

    assert.deepEqual(await authService.logout(a.refreshToken), { revoked: true });
    assert.deepEqual(await authService.logout(a.refreshToken), { revoked: false }); // idempotent
    await assert.rejects(authService.refresh(a.refreshToken), /Session ended/);
    assert.ok(await authService.refresh(b.refreshToken));

    const legacy = await giveLegacyToken(user);
    assert.deepEqual(await authService.logoutAll(user._id), { revoked: 2 });
    await assert.rejects(authService.refresh(c.refreshToken), /Session ended/);
    await assert.rejects(authService.refresh(legacy), /Invalid session/);
  });

  test('logout accepts an expired token this server signed, rejects a forged one', async () => {
    const user = await makeUser(10);
    const { session } = await authService._startSession(user, 'x');
    const expired = jwt.sign(
      { id: String(user._id), sid: String(session._id), gen: 0, exp: Math.floor(Date.now() / 1000) - 10 },
      process.env.JWT_REFRESH_SECRET
    );
    assert.deepEqual(await authService.logout(expired), { revoked: true });
    const forged = jwt.sign({ id: String(user._id), sid: String(session._id), gen: 0 }, 'not-the-secret-'.repeat(3));
    await assert.rejects(authService.logout(forged), /Invalid refresh token/);
  });
});

describe('auth endpoints (v0.2.0 and new clients)', () => {
  let db;
  let app;
  before(async () => { db = await startTestDb(); await Session.init(); app = createApp(); });
  after(async () => { await db.stop(); });
  beforeEach(async () => { await db.clear(); });

  test('v0.2.0 request shapes still work: login and refresh without deviceLabel', async () => {
    const user = await makeUser(10);
    const login = await request(app)
      .post('/api/v1/auth/login')
      .set('User-Agent', 'Dart/3.13 (dart:io)')
      .send({ email: user.email, password: PASSWORD });
    assert.equal(login.status, 200);
    const { accessToken, refreshToken, user: profile } = login.body.data;
    assert.ok(accessToken && refreshToken && profile);
    assert.equal(profile.refreshTokenHash, undefined);
    assert.equal(profile.legacySession, undefined);
    assert.equal((await Session.findById(sidOf(refreshToken)).lean()).deviceLabel, 'Dart/3.13 (dart:io)');

    const refreshed = await request(app).post('/api/v1/auth/refresh').send({ refreshToken });
    assert.equal(refreshed.status, 200);
    assert.deepEqual(Object.keys(refreshed.body.data).sort(), ['accessToken', 'refreshToken']);

    const me = await request(app).get('/api/v1/users/me').set('Authorization', `Bearer ${refreshed.body.data.accessToken}`);
    assert.equal(me.status, 200);
  });

  test('v0.2.0 app holding a pre-sessions token is not logged out by the deploy', async () => {
    const user = await makeUser(10);
    const legacy = await giveLegacyToken(user);
    const res = await request(app).post('/api/v1/auth/refresh').send({ refreshToken: legacy });
    assert.equal(res.status, 200);
    assert.ok(sidOf(res.body.data.refreshToken));
  });

  test('new clients: deviceLabel, logout, logout-all', async () => {
    const user = await makeUser(10);
    const login = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: user.email, password: PASSWORD, deviceLabel: 'Windows app' });
    assert.equal(login.status, 200);
    const { refreshToken, accessToken } = login.body.data;
    assert.equal((await Session.findById(sidOf(refreshToken)).lean()).deviceLabel, 'Windows app');

    const tooLong = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: user.email, password: PASSWORD, deviceLabel: 'x'.repeat(65) });
    assert.equal(tooLong.status, 400);

    const out = await request(app).post('/api/v1/auth/logout').send({ refreshToken });
    assert.equal(out.status, 200);
    assert.equal(out.body.data.revoked, true);
    assert.equal((await request(app).post('/api/v1/auth/refresh').send({ refreshToken })).status, 401);

    assert.equal((await request(app).post('/api/v1/auth/logout-all')).status, 401);
    const all = await request(app).post('/api/v1/auth/logout-all').set('Authorization', `Bearer ${accessToken}`);
    assert.equal(all.status, 200);
  });
});
