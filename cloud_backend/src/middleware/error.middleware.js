/**
 * Centralized Error Handling Middleware
 * Catches all operational and unexpected errors, returning standardized JSON responses.
 */

import { ApiError } from '../utils/ApiError.js';
import { env } from '../config/env.js';

// eslint-disable-next-line no-unused-vars
export const errorHandler = (err, req, res, next) => {
  let error = err;

  // Transform non-ApiError instances into ApiError
  if (!(error instanceof ApiError)) {
    let statusCode = error.statusCode || 500;
    let message = error.message || 'Internal Server Error';
    let errors = [];

    // Mongoose Duplicate Key Error (E11000)
    if (error.code === 11000) {
      statusCode = 409;
      const field = Object.keys(error.keyValue || {})[0] || 'field';
      message = `Duplicate value entered for '${field}'. Please provide a unique value.`;
    }

    // Mongoose Validation Error
    else if (error.name === 'ValidationError') {
      statusCode = 400;
      message = 'Database Validation Failed';
      errors = Object.values(error.errors || {}).map((val) => val.message);
    }

    // Mongoose CastError (invalid ObjectId)
    else if (error.name === 'CastError') {
      statusCode = 400;
      message = `Invalid format for field '${error.path}': ${error.value}`;
    }

    // JWT Errors
    else if (error.name === 'JsonWebTokenError') {
      statusCode = 401;
      message = 'Invalid authentication token';
    } else if (error.name === 'TokenExpiredError') {
      statusCode = 401;
      message = 'Authentication token expired';
    }

    error = new ApiError(statusCode, message, errors, err.stack);
  }

  const response = {
    success: false,
    message: error.message,
    ...(error.errors && error.errors.length > 0 && { errors: error.errors }),
    ...(env.isDevelopment && { stack: error.stack }),
  };

  if (!env.isTest) {
    if (error.statusCode >= 500) {
      console.error(`[Server Error] ${req.method} ${req.originalUrl}:`, error);
    } else {
      console.warn(`[Client Error ${error.statusCode}] ${req.method} ${req.originalUrl}: ${error.message}`);
    }
  }

  res.status(error.statusCode).json(response);
};
