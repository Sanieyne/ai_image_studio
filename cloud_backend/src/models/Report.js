/**
 * Report Mongoose Model
 * Tracks user-submitted moderation reports on public gallery content for admin review.
 */

import mongoose from 'mongoose';

const reportSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'userId (reporter) is required'],
      index: true,
    },
    generationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Generation',
      required: [true, 'generationId is required'],
      index: true,
    },
    reason: {
      type: String,
      enum: {
        values: ['inappropriate', 'spam', 'copyright', 'other'],
        message: 'Reason must be inappropriate, spam, copyright, or other',
      },
      required: [true, 'Reason is required'],
    },
    details: {
      type: String,
      maxlength: [500, 'Details cannot exceed 500 characters'],
      trim: true,
      default: '',
    },
    status: {
      type: String,
      enum: {
        values: ['pending', 'reviewed', 'dismissed'],
        message: 'Status must be pending, reviewed, or dismissed',
      },
      default: 'pending',
      index: true,
    },
  },
  {
    timestamps: true,
    toJSON: {
      virtuals: true,
      transform: (doc, ret) => {
        delete ret.__v;
        return ret;
      },
    },
    toObject: {
      virtuals: true,
    },
  }
);

reportSchema.index({ status: 1, createdAt: -1 });

export const Report = mongoose.model('Report', reportSchema);
export default Report;
