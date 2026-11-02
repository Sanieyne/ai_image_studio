import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { startTestDb } from './helpers/db.js';
import { makeUser } from './helpers/factories.js';
import { createApp } from '../src/app.js';
import { emailService } from '../src/services/email.service.js';
import { otpService } from '../src/services/otp.service.js';
import { Otp } from '../src/models/Otp.js';
import { User } from '../src/models/User.js';

describe('Email & OTP Service', () => {
  let db;
  let app;

  before(async () => {
    db = await startTestDb();
    await Otp.init();
    await User.init();
    app = createApp();
  });

  after(async () => {
    await db.stop();
  });

  beforeEach(async () => {
    await db.clear();
    emailService.sentEmails = [];
  });

  test('sends OTP email and saves hashed record to database', async () => {
    const email = 'user@example.com';
    const res = await otpService.sendOtp({ email, purpose: 'email_verification' });

    assert.equal(res.success, true);
    assert.equal(emailService.sentEmails.length, 1);
    assert.equal(emailService.sentEmails[0].to, email);
    assert.match(emailService.sentEmails[0].subject, /Verification Code/);

    const otpInDb = await Otp.findOne({ email });
    assert.ok(otpInDb);
    assert.equal(otpInDb.isUsed, false);
    assert.equal(otpInDb.attempts, 0);
    assert.ok(otpInDb.codeHash);
  });

  test('enforces cooldown when requesting OTP repeatedly', async () => {
    const email = 'cooldown@example.com';
    await otpService.sendOtp({ email });

    await assert.rejects(
      () => otpService.sendOtp({ email }),
      /Please wait 60 seconds before requesting a new code/
    );
  });

  test('verifies OTP successfully and updates isEmailVerified on user', async () => {
    const email = 'verify@example.com';
    await User.create({
      username: 'verifyuser',
      email,
      password: 'Password-123456',
      isEmailVerified: false,
    });

    await otpService.sendOtp({ email, purpose: 'email_verification' });
    const sentEmail = emailService.sentEmails[0];
    const codeMatch = sentEmail.text.match(/verification code is: (\d{6})/);
    assert.ok(codeMatch, 'Code should be present in email text');
    const code = codeMatch[1];

    const verifyResult = await otpService.verifyOtp({ email, code, purpose: 'email_verification' });
    assert.equal(verifyResult.verified, true);

    const updatedUser = await User.findOne({ email });
    assert.equal(updatedUser.isEmailVerified, true);

    const otpInDb = await Otp.findOne({ email });
    assert.equal(otpInDb.isUsed, true);
  });

  test('rejects incorrect OTP and counts attempts', async () => {
    const email = 'wrongcode@example.com';
    await otpService.sendOtp({ email });

    await assert.rejects(
      () => otpService.verifyOtp({ email, code: '000000', purpose: 'email_verification' }),
      /Incorrect verification code/
    );

    const otpInDb = await Otp.findOne({ email });
    assert.equal(otpInDb.attempts, 1);
  });

  test('locks out after 5 incorrect attempts', async () => {
    const email = 'lockout@example.com';
    await otpService.sendOtp({ email });

    // Set attempts to 5
    await Otp.updateOne({ email }, { $set: { attempts: 5 } });

    await assert.rejects(
      () => otpService.verifyOtp({ email, code: '123456', purpose: 'email_verification' }),
      /Too many incorrect attempts/
    );
  });

  test('rejects expired OTP', async () => {
    const email = 'expired@example.com';
    await otpService.sendOtp({ email });

    // Backdate expiresAt
    await Otp.updateOne({ email }, { $set: { expiresAt: new Date(Date.now() - 1000) } });

    await assert.rejects(
      () => otpService.verifyOtp({ email, code: '123456', purpose: 'email_verification' }),
      /Invalid or expired verification code/
    );
  });

  test('resets password using verified OTP', async () => {
    const email = 'reset@example.com';
    const oldPassword = 'OldPassword-123456';
    const newPassword = 'NewPassword-987654';

    const user = await User.create({
      username: 'resetuser',
      email,
      password: oldPassword,
    });

    await otpService.sendOtp({ email, purpose: 'password_reset' });
    const codeMatch = emailService.sentEmails[0].text.match(/code is: (\d{6})/);
    const code = codeMatch[1];

    const resetRes = await otpService.resetPassword({ email, code, newPassword });
    assert.equal(resetRes.success, true);

    const updatedUser = await User.findOne({ email }).select('+password');
    const oldMatches = await updatedUser.comparePassword(oldPassword);
    const newMatches = await updatedUser.comparePassword(newPassword);

    assert.equal(oldMatches, false);
    assert.equal(newMatches, true);
  });

  test('HTTP endpoints: send-otp and verify-otp', async () => {
    const email = 'httpotp@example.com';

    // 1. Send OTP
    const sendRes = await request(app)
      .post('/api/v1/auth/send-otp')
      .send({ email, purpose: 'email_verification' })
      .expect(200);

    assert.equal(sendRes.body.success, true);

    const codeMatch = emailService.sentEmails[0].text.match(/code is: (\d{6})/);
    const code = codeMatch[1];

    // 2. Verify OTP
    const verifyRes = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ email, code, purpose: 'email_verification' })
      .expect(200);

    assert.equal(verifyRes.body.verified, true);
  });

  test('HTTP endpoints: forgot-password and reset-password', async () => {
    const email = 'forgothttp@example.com';
    await User.create({
      username: 'forgotuser',
      email,
      password: 'InitialPassword-123',
    });

    // 1. Forgot password
    await request(app)
      .post('/api/v1/auth/forgot-password')
      .send({ email })
      .expect(200);

    const codeMatch = emailService.sentEmails[0].text.match(/code is: (\d{6})/);
    const code = codeMatch[1];

    // 2. Reset password
    const resetRes = await request(app)
      .post('/api/v1/auth/reset-password')
      .send({
        email,
        code,
        newPassword: 'UpdatedPassword-456',
      })
      .expect(200);

    assert.equal(resetRes.body.success, true);

    // 3. Login with new password
    const loginRes = await request(app)
      .post('/api/v1/auth/login')
      .send({
        email,
        password: 'UpdatedPassword-456',
      })
      .expect(200);

    assert.equal(loginRes.body.success, true);
    assert.ok(loginRes.body.data.accessToken);
  });
});
