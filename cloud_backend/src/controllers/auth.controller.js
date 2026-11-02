/**
 * Authentication Controller
 * HTTP request handlers for user registration, authentication, and session token rotation.
 */

import { asyncHandler } from '../utils/asyncHandler.js';
import { authService } from '../services/auth.service.js';
import { otpService } from '../services/otp.service.js';

export const register = asyncHandler(async (req, res) => {
  const { username, email, password, deviceLabel } = req.body;
  const result = await authService.register({
    username,
    email,
    password,
    deviceLabel: deviceLabel || req.get('x-device-label') || req.get('user-agent'),
  });

  res.status(201).json({
    success: true,
    message: 'User registered successfully',
    data: result,
  });
});

export const login = asyncHandler(async (req, res) => {
  const { email, password, deviceLabel } = req.body;
  // Apps send the label as X-Device-Label (older backends reject unknown body fields).
  const result = await authService.login({
    email,
    password,
    deviceLabel: deviceLabel || req.get('x-device-label') || req.get('user-agent'),
  });

  res.status(200).json({
    success: true,
    message: 'Login successful',
    data: result,
  });
});

export const refresh = asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;
  const result = await authService.refresh(refreshToken);

  res.status(200).json({
    success: true,
    message: 'Tokens refreshed successfully',
    data: result,
  });
});

/** Ends the session the given refresh token belongs to (this device). */
export const logout = asyncHandler(async (req, res) => {
  const result = await authService.logout(req.body.refreshToken);
  res.status(200).json({
    success: true,
    message: 'Logged out',
    data: result,
  });
});

/** Ends every session of the signed-in user. */
export const logoutAll = asyncHandler(async (req, res) => {
  const result = await authService.logoutAll(req.user._id);
  res.status(200).json({
    success: true,
    message: 'Logged out on all devices',
    data: result,
  });
});

/** Sends an OTP verification code via email. */
export const sendOtp = asyncHandler(async (req, res) => {
  const { email, purpose } = req.body;
  const result = await otpService.sendOtp({ email, purpose });
  res.status(200).json(result);
});

/** Verifies an OTP code for email verification or signup. */
export const verifyOtp = asyncHandler(async (req, res) => {
  const { email, code, purpose } = req.body;
  const result = await otpService.verifyOtp({ email, code, purpose });
  res.status(200).json(result);
});

/** Initiates a forgot-password flow by sending an OTP. */
export const forgotPassword = asyncHandler(async (req, res) => {
  const { email } = req.body;
  const result = await otpService.sendOtp({ email, purpose: 'password_reset' });
  res.status(200).json(result);
});

/** Completes password reset using verified OTP and new password. */
export const resetPassword = asyncHandler(async (req, res) => {
  const { email, code, newPassword } = req.body;
  const result = await otpService.resetPassword({ email, code, newPassword });
  res.status(200).json(result);
});
