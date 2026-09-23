/**
 * Authentication Controller
 * HTTP request handlers for user registration, authentication, and session token rotation.
 */

import { asyncHandler } from '../utils/asyncHandler.js';
import { authService } from '../services/auth.service.js';

export const register = asyncHandler(async (req, res) => {
  const { username, email, password } = req.body;
  const result = await authService.register({ username, email, password });

  res.status(201).json({
    success: true,
    message: 'User registered successfully',
    data: result,
  });
});

export const login = asyncHandler(async (req, res) => {
  const { email, password } = req.body;
  const result = await authService.login({ email, password });

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
