/**
 * Token Rotation & Reuse Detection Verification Script
 * Validates:
 * 1. Refresh token lifetime is exactly 60 days (5184000s)
 * 2. Access token lifetime remains exactly 15 minutes (900s)
 * 3. Token rotation correctly issues new tokens and updates the stored hash
 * 4. Reusing a rotated token triggers reuse-detection, wipes session, and returns 401
 * 5. Subsequent attempts with revoked/wiped session fail
 */

import jwt from 'jsonwebtoken';
import mongoose from 'mongoose';
import { env } from '../src/config/env.js';
import { User } from '../src/models/User.js';
import { signAccessToken, signRefreshToken, verifyRefreshToken } from '../src/utils/jwt.js';
import { authService } from '../src/services/auth.service.js';

async function run() {
  console.log('====================================================');
  console.log('🔒 Testing 60-Day Refresh Expiry, Rotation & Reuse Detection');
  console.log('====================================================\n');

  await mongoose.connect(env.MONGODB_URI);

  // 1. Verify token expiration times
  console.log('[Step 1] Verifying JWT token durations...');
  const dummyPayload = { id: new mongoose.Types.ObjectId().toString(), role: 'user' };
  const accessToken = signAccessToken(dummyPayload);
  const refreshToken = signRefreshToken({ id: dummyPayload.id });

  const decodedAccess = jwt.decode(accessToken);
  const decodedRefresh = jwt.decode(refreshToken);

  const accessDurationSec = decodedAccess.exp - decodedAccess.iat;
  const refreshDurationSec = decodedRefresh.exp - decodedRefresh.iat;

  console.log(`  Access Token expiresIn: ${accessDurationSec}s (${accessDurationSec / 60}m)`);
  console.log(`  Refresh Token expiresIn: ${refreshDurationSec}s (${refreshDurationSec / (24 * 3600)}d)`);

  if (accessDurationSec !== 15 * 60) {
    throw new Error(`Expected access token to be 900s (15m), but got ${accessDurationSec}s`);
  }
  if (refreshDurationSec !== 60 * 24 * 3600) {
    throw new Error(`Expected refresh token to be 5184000s (60d), but got ${refreshDurationSec}s`);
  }
  console.log('  ✅ Step 1 Passed: Expirations are exactly 15m and 60d.\n');

  // 2. Set up test user in DB
  console.log('[Step 2] Registering test user session for rotation test...');
  const testEmail = `token_test_${Date.now()}@example.com`;
  const registerResult = await authService.register({
    username: `toktest_${Date.now()}`,
    email: testEmail,
    password: 'Password123!',
  });

  const initialRefreshToken = registerResult.refreshToken;
  const initialAccessToken = registerResult.accessToken;
  const userId = registerResult.user.id;

  const userAfterRegister = await User.findById(userId).select('+refreshTokenHash');
  if (!userAfterRegister.refreshTokenHash) {
    throw new Error('User refreshTokenHash was not saved after registration.');
  }
  console.log('  ✅ Step 2 Passed: User registered, refreshTokenHash stored.\n');

  // 3. Perform legal rotation (refreshTokens)
  console.log('[Step 3] Performing legal token rotation with initial refresh token...');
  const rotationResult = await authService.refresh(initialRefreshToken);
  const secondRefreshToken = rotationResult.refreshToken;
  const secondAccessToken = rotationResult.accessToken;

  if (secondRefreshToken === initialRefreshToken) {
    throw new Error('Rotation failed: Refresh token was not rotated to a new string.');
  }

  const userAfterRotation = await User.findById(userId).select('+refreshTokenHash');
  if (!userAfterRotation.refreshTokenHash) {
    throw new Error('User refreshTokenHash missing after rotation.');
  }
  console.log('  ✅ Step 3 Passed: Legitimate rotation succeeded, new refresh token issued.\n');

  // 4. Test reuse-detection by attempting to reuse the initial (now stale) refresh token
  console.log('[Step 4] Testing reuse detection by resubmitting initial (old) refresh token...');
  let reuseDetected = false;
  try {
    const res = await authService.refresh(initialRefreshToken);
    console.log('  WARNING: refresh returned instead of throwing!', {
      resTokenPrefix: res.refreshToken.slice(0, 20),
      initialTokenPrefix: initialRefreshToken.slice(0, 20),
      secondTokenPrefix: secondRefreshToken.slice(0, 20),
    });
  } catch (err) {
    console.log(`  Caught error in Step 4: "${err.message}" (status: ${err.statusCode})`);
    if (err.statusCode === 401 && err.message.includes('Session compromised')) {
      reuseDetected = true;
    }
  }

  if (!reuseDetected) {
    throw new Error('Reuse detection failed: Reused refresh token was not rejected with "Session compromised"!');
  }

  // Confirm user session was wiped
  const userAfterCompromise = await User.findById(userId).select('+refreshTokenHash');
  if (userAfterCompromise.refreshTokenHash !== null) {
    throw new Error('Compromise cleanup failed: user.refreshTokenHash was NOT nulled!');
  }
  console.log('  ✅ Step 4 Passed: Reuse detected, session compromised error thrown, hash wiped to null.\n');

  // 5. Test that the second refresh token is now ALSO invalid because session was wiped
  console.log('[Step 5] Verifying that subsequent attempts with second refresh token now fail...');
  let secondTokenFailed = false;
  try {
    await authService.refresh(secondRefreshToken);
  } catch (err) {
    console.log(`  Caught expected error: "${err.message}" (status: ${err.statusCode})`);
    if (err.statusCode === 401 && err.message.includes('Invalid session')) {
      secondTokenFailed = true;
    }
  }

  if (!secondTokenFailed) {
    throw new Error('Expected second refresh token to fail after compromise cleanup!');
  }
  console.log('  ✅ Step 5 Passed: Subsequent refreshes fail, user must log in again.\n');

  // Clean up test user
  await User.deleteOne({ _id: userId });
  await mongoose.disconnect();

  console.log('====================================================');
  console.log('🎉 ALL ROTATION & REUSE-DETECTION TESTS PASSED (60-DAY WINDOW)');
  console.log('====================================================');
}

run().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
