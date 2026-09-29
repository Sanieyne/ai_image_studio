/**
 * Like Mongoose Model
 * Manages user likes on published generations with a compound unique index
 * to prevent duplicates at the database level.
 */

import mongoose from 'mongoose';

const likeSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'userId is required'],
      index: true,
    },
    generationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Generation',
      required: [true, 'generationId is required'],
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

// Compound unique index prevents duplicate likes at DB level
likeSchema.index({ userId: 1, generationId: 1 }, { unique: true });

export const Like = mongoose.model('Like', likeSchema);
export default Like;
