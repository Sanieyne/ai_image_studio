/**
 * Request Validation Middleware (Joi)
 * Validates request bodies against schemas and throws structured 400 ApiError on failure.
 */

import Joi from 'joi';
import { ApiError } from '../utils/ApiError.js';

export const validate = (schema, options = {}) => (req, res, next) => {
  const { error, value } = schema.validate(req.body, {
    abortEarly: false,
    stripUnknown: options.stripUnknown !== undefined ? options.stripUnknown : true,
    ...options,
  });

  if (error) {
    const errorMessages = error.details.map((detail) => detail.message.replace(/['"]/g, ''));
    return next(new ApiError(400, 'Validation Error', errorMessages));
  }

  req.body = value;
  next();
};

export const registerSchema = Joi.object({
  username: Joi.string()
    .alphanum()
    .min(3)
    .max(30)
    .trim()
    .required()
    .messages({
      'string.alphanum': 'Username must only contain alphanumeric characters',
      'string.min': 'Username must be at least 3 characters',
      'string.max': 'Username cannot exceed 30 characters',
      'any.required': 'Username is required',
    }),
  email: Joi.string()
    .email({ tlds: { allow: false } })
    .trim()
    .lowercase()
    .required()
    .messages({
      'string.email': 'Please provide a valid email address',
      'any.required': 'Email is required',
    }),
  password: Joi.string()
    .min(8)
    .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
    .required()
    .messages({
      'string.min': 'Password must be at least 8 characters long',
      'string.pattern.base': 'Password must contain at least one uppercase letter, one lowercase letter, and one number',
      'any.required': 'Password is required',
    }),
});

export const loginSchema = Joi.object({
  email: Joi.string()
    .email({ tlds: { allow: false } })
    .trim()
    .lowercase()
    .required()
    .messages({
      'string.email': 'Please provide a valid email address',
      'any.required': 'Email is required',
    }),
  password: Joi.string()
    .required()
    .messages({
      'any.required': 'Password is required',
    }),
});

export const refreshSchema = Joi.object({
  refreshToken: Joi.string()
    .required()
    .messages({
      'any.required': 'Refresh token is required',
    }),
});

export const createGenerationSchema = Joi.object({
  mediaBase64: Joi.string()
    .required()
    .messages({
      'any.required': 'mediaBase64 is required',
      'string.empty': 'mediaBase64 cannot be empty',
    }),
  mediaType: Joi.string()
    .valid('image', 'video', 'audio')
    .default('image'),
  extension: Joi.string()
    .trim()
    .alphanum()
    .max(10)
    .optional()
    .allow('', null),
  prompt: Joi.string()
    .trim()
    .min(1)
    .max(5000)
    .required()
    .messages({
      'any.required': 'prompt is required',
      'string.empty': 'prompt cannot be empty',
    }),
  negativePrompt: Joi.string()
    .trim()
    .max(5000)
    .optional()
    .allow('', null)
    .default(''),
  modelId: Joi.string()
    .trim()
    .required()
    .messages({
      'any.required': 'modelId is required',
      'string.empty': 'modelId cannot be empty',
    }),
  settings: Joi.object()
    .unknown(true)
    .optional()
    .default({}),
});

const RESERVED_DISPLAY_NAMES = [
  'admin',
  'administrator',
  'root',
  'system',
  'moderator',
  'mod',
  'support',
  'official',
  'staff',
  'help',
  'security',
];

export const updateProfileSchema = Joi.object({
  displayName: Joi.string()
    .trim()
    .min(1)
    .max(50)
    .custom((value, helpers) => {
      if (RESERVED_DISPLAY_NAMES.includes(value.toLowerCase())) {
        return helpers.error('any.invalid');
      }
      return value;
    })
    .messages({
      'string.min': 'Display name must be at least 1 character',
      'string.max': 'Display name cannot exceed 50 characters',
      'any.invalid': 'This display name is reserved. Please choose another.',
    }),
  avatarUrl: Joi.string()
    .uri({ scheme: ['http', 'https'] })
    .max(1000)
    .allow('', null)
    .messages({
      'string.uri': 'avatarUrl must be a valid HTTP or HTTPS URL',
    }),
  bio: Joi.string()
    .trim()
    .max(160)
    .allow('', null)
    .messages({
      'string.max': 'Bio cannot exceed 160 characters',
    }),
  isPublicProfile: Joi.boolean(),
})
  .min(1)
  .unknown(false)
  .messages({
    'object.min': 'At least one profile field must be provided for update',
    'object.unknown': 'Field "{#child}" is not allowed to be modified through profile update',
  });

export const adminModerationDecideSchema = Joi.object({
  decision: Joi.string()
    .valid('approve', 'reject')
    .required()
    .messages({
      'any.required': 'decision is required',
      'any.only': 'decision must be either approve or reject',
    }),
  reason: Joi.string()
    .trim()
    .max(500)
    .optional()
    .allow('', null)
    .default(''),
});

export const createReportSchema = Joi.object({
  reason: Joi.string()
    .valid('inappropriate', 'spam', 'copyright', 'other')
    .required()
    .messages({
      'any.required': 'reason is required',
      'any.only': 'reason must be one of inappropriate, spam, copyright, or other',
    }),
  details: Joi.string()
    .trim()
    .max(500)
    .optional()
    .allow('', null)
    .default(''),
});

export const resolveReportSchema = Joi.object({
  action: Joi.string()
    .valid('dismiss', 'remove_content')
    .required()
    .messages({
      'any.required': 'action is required',
      'any.only': 'action must be either dismiss or remove_content',
    }),
  reason: Joi.string()
    .trim()
    .max(500)
    .optional()
    .allow('', null)
    .default(''),
});




