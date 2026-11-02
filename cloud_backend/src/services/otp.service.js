/**
 * OTP Business Logic Service
 * Generates, hashes, stores, and verifies one-time passwords for authentication and password resets.
 */

import crypto from 'crypto';
import { Otp } from '../models/Otp.js';
import { User } from '../models/User.js';
import { emailService } from './email.service.js';
import { ApiError } from '../utils/ApiError.js';
import { env } from '../config/env.js';

const OTP_EXPIRY_MINUTES = 10;
const MAX_ATTEMPTS = 5;
const RESEND_COOLDOWN_SECONDS = 60;

function hashOtpCode(email, code) {
  return crypto
    .createHash('sha256')
    .update(`${email.toLowerCase()}:${code}:${env.JWT_ACCESS_SECRET}`)
    .digest('hex');
}

export const otpService = {
  /**
   * Generates a 6-digit OTP code, saves it to the database, and sends it via email.
   */
  async sendOtp({ email, purpose = 'email_verification' }) {
    const normalizedEmail = email.toLowerCase().trim();

    // If password_reset, verify user actually exists
    if (purpose === 'password_reset') {
      const user = await User.findOne({ email: normalizedEmail });
      if (!user) {
        // Return success without revealing user non-existence (security best practice)
        return {
          success: true,
          message: 'If this email is registered, a verification code has been sent.',
        };
      }
    }

    // Check resend cooldown
    const recentOtp = await Otp.findOne({
      email: normalizedEmail,
      purpose,
      isUsed: false,
      createdAt: { $gt: new Date(Date.now() - RESEND_COOLDOWN_SECONDS * 1000) },
    });

    if (recentOtp) {
      throw ApiError.badRequest(
        `Please wait ${RESEND_COOLDOWN_SECONDS} seconds before requesting a new code.`
      );
    }

    // Invalidate any existing unused OTPs for this email and purpose
    await Otp.deleteMany({ email: normalizedEmail, purpose, isUsed: false });

    // Generate cryptographically secure 6-digit code
    const code = crypto.randomInt(100000, 1000000).toString();
    const codeHash = hashOtpCode(normalizedEmail, code);
    const expiresAt = new Date(Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000);

    await Otp.create({
      email: normalizedEmail,
      codeHash,
      purpose,
      expiresAt,
    });

    await emailService.sendOtpEmail(normalizedEmail, code, purpose);

    return {
      success: true,
      message: 'Verification code sent successfully.',
      expiresInMinutes: OTP_EXPIRY_MINUTES,
    };
  },

  /**
   * Verifies an OTP code for a given email and purpose.
   */
  async verifyOtp({ email, code, purpose = 'email_verification' }) {
    const normalizedEmail = email.toLowerCase().trim();

    const otpRecord = await Otp.findOne({
      email: normalizedEmail,
      purpose,
      isUsed: false,
      expiresAt: { $gt: new Date() },
    });

    if (!otpRecord) {
      throw ApiError.badRequest('Invalid or expired verification code.');
    }

    if (otpRecord.attempts >= MAX_ATTEMPTS) {
      await Otp.deleteOne({ _id: otpRecord._id });
      throw ApiError.badRequest('Too many incorrect attempts. Please request a new code.');
    }

    const expectedHash = hashOtpCode(normalizedEmail, code);
    if (otpRecord.codeHash !== expectedHash) {
      otpRecord.attempts += 1;
      await otpRecord.save();
      throw ApiError.badRequest('Incorrect verification code.');
    }

    otpRecord.isUsed = true;
    await otpRecord.save();

    // If verifying email, update User model
    if (purpose === 'email_verification' || purpose === 'signup') {
      await User.updateOne({ email: normalizedEmail }, { $set: { isEmailVerified: true } });
    }

    return {
      success: true,
      verified: true,
      message: 'Code verified successfully.',
    };
  },

  /**
   * Resets password using a verified OTP code.
   */
  async resetPassword({ email, code, newPassword }) {
    const normalizedEmail = email.toLowerCase().trim();

    // Verify OTP first
    await this.verifyOtp({ email: normalizedEmail, code, purpose: 'password_reset' });

    const user = await User.findOne({ email: normalizedEmail }).select('+password');
    if (!user) {
      throw ApiError.notFound('User not found.');
    }

    user.password = newPassword;
    await user.save();

    return {
      success: true,
      message: 'Password reset successfully. You can now log in with your new password.',
    };
  },
};
