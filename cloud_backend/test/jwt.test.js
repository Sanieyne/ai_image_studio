import { test } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { env } from '../src/config/env.js';
import { signAccessToken, verifyAccessToken, verifyRefreshToken } from '../src/utils/jwt.js';
import { describeMongoUri } from '../src/config/database.js';

test('access tokens default to a 15 minute lifetime', () => {
  assert.equal(env.JWT_ACCESS_EXPIRES, '15m');
  const { iat, exp } = jwt.decode(signAccessToken({ id: 'u1' }));
  assert.equal(exp - iat, 15 * 60);
});

test('verification accepts HS256 tokens from signAccessToken', () => {
  assert.equal(verifyAccessToken(signAccessToken({ id: 'u1' })).id, 'u1');
});

test('verification rejects other algorithms, even with the right secret', () => {
  const hs512 = jwt.sign({ id: 'u1' }, env.JWT_ACCESS_SECRET, { algorithm: 'HS512' });
  assert.throws(() => verifyAccessToken(hs512), /invalid algorithm/);
  const refreshHs384 = jwt.sign({ id: 'u1' }, env.JWT_REFRESH_SECRET, { algorithm: 'HS384' });
  assert.throws(() => verifyRefreshToken(refreshHs384), /invalid algorithm/);
});

test('MongoDB URI is logged as host and database only', () => {
  const described = describeMongoUri('mongodb://admin:p%40ss@db1:27017,db2:27018/appdb?authSource=admin&tls=true');
  assert.equal(described, 'db1:27017,db2:27018 / appdb');
  assert.doesNotMatch(described, /admin:|p%40ss|authSource/);
  assert.equal(describeMongoUri('mongodb+srv://u:p@cluster.example.net/?retryWrites=false'), 'cluster.example.net / (default)');
});
