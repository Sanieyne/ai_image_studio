/**
 * User Mongoose Model
 * Manages authentication credentials, authorization roles, storage quotas, and credit balances.
 */

import mongoose from 'mongoose';
import bcrypt from 'bcryptjs';
import { ROLES } from '../config/constants.js';
import { env } from '../config/env.js';

const userSchema = new mongoose.Schema(
  {
    username: {
      type: String,
      required: [true, 'Username is required'],
      unique: true,
      trim: true,
      minlength: [3, 'Username must be at least 3 characters'],
      maxlength: [30, 'Username cannot exceed 30 characters'],
      index: true,
    },
    email: {
      type: String,
      required: [true, 'Email is required'],
      unique: true,
      lowercase: true,
      trim: true,
      index: true,
      match: [/^\S+@\S+\.\S+$/, 'Please provide a valid email address'],
    },
    password: {
      type: String,
      required: [true, 'Password is required'],
      minlength: [8, 'Password must be at least 8 characters'],
      select: false,
    },
    role: {
      type: String,
      enum: Object.values(ROLES),
      default: ROLES.USER,
    },
    credits: {
      type: Number,
      default: env.FREE_CREDITS,
      min: [0, 'Credits cannot be negative'],
    },
    totalCreditsPurchased: {
      type: Number,
      default: 0,
      min: 0,
    },
    totalCreditsUsed: {
      type: Number,
      default: 0,
      min: 0,
    },
    // Number of GPU instances currently holding a rental slot (see GPU_MAX_ACTIVE_PER_USER).
    activeGpuInstances: {
      type: Number,
      default: 0,
      min: 0,
    },
    isActive: {
      type: Boolean,
      default: true,
    },
    isEmailVerified: {
      type: Boolean,
      default: false,
    },
    refreshTokenHash: {
      type: String,
      select: false,
    },
    lastLoginAt: {
      type: Date,
      default: null,
    },
    storageQuotaGB: {
      type: Number,
      default: 20,
    },
    storageUsedGB: {
      type: Number,
      default: 0,
    },
    selectedModels: {
      type: [String],
      default: ['sdxl-base-1.0'],
    },
    displayName: {
      type: String,
      trim: true,
      maxlength: [50, 'Display name cannot exceed 50 characters'],
      default: function () {
        return this.username;
      },
    },
    avatarUrl: {
      type: String,
      default: null,
      trim: true,
    },
    bio: {
      type: String,
      maxlength: [160, 'Bio cannot exceed 160 characters'],
      default: '',
      trim: true,
    },
    isPublicProfile: {
      type: Boolean,
      default: true,
      index: true,
    },
  },
  {
    timestamps: true,
  }
);

// Hash password before saving and ensure displayName defaults to username
userSchema.pre('save', async function () {
  if (!this.displayName) {
    this.displayName = this.username;
  }
  if (!this.isModified('password')) {
    return;
  }
  const salt = await bcrypt.genSalt(env.BCRYPT_SALT);
  this.password = await bcrypt.hash(this.password, salt);
});

// Compare password instance method
userSchema.methods.comparePassword = async function (candidatePassword) {
  return bcrypt.compare(candidatePassword, this.password);
};

// Safe JSON serialization (strip password and refresh token hash)
userSchema.methods.toJSON = function () {
  const obj = this.toObject();
  delete obj.password;
  delete obj.refreshTokenHash;
  delete obj.__v;
  return obj;
};

// Public safe JSON serialization (strictly allowlisted fields)
userSchema.methods.toPublicJSON = function () {
  return {
    username: this.username,
    displayName: this.displayName || this.username,
    avatarUrl: this.avatarUrl || null,
    bio: this.bio || '',
    createdAt: this.createdAt,
  };
};

export const User = mongoose.model('User', userSchema);
