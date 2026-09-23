/**
 * Database Connection Manager
 * Mongoose setup with automated reconnection, error monitoring, and graceful termination.
 */

import mongoose from 'mongoose';
import { env } from './env.js';

const MAX_RETRIES = 5;
const INITIAL_RETRY_INTERVAL_MS = 2000;

export async function connectDB(retries = MAX_RETRIES, delay = INITIAL_RETRY_INTERVAL_MS) {
  mongoose.connection.on('connected', () => {
    console.info(`[Database] MongoDB connected successfully to ${mongoose.connection.host}`);
  });

  mongoose.connection.on('error', (err) => {
    console.error(`[Database] MongoDB connection error: ${err.message}`);
  });

  mongoose.connection.on('disconnected', () => {
    console.warn('[Database] MongoDB connection disconnected.');
  });

  while (retries > 0) {
    try {
      await mongoose.connect(env.MONGODB_URI, {
        serverSelectionTimeoutMS: 5000,
        socketTimeoutMS: 45000,
        autoIndex: env.isDevelopment,
      });
      return;
    } catch (error) {
      retries -= 1;
      console.error(
        `[Database] Connection failed: ${error.message}. Retries remaining: ${retries}`
      );

      if (retries === 0) {
        throw new Error(`[Database] Could not connect to MongoDB after ${MAX_RETRIES} attempts.`);
      }

      await new Promise((resolve) => setTimeout(resolve, delay));
      delay *= 1.5; // Exponential backoff
    }
  }
}

export async function disconnectDB() {
  try {
    await mongoose.connection.close(false);
    console.info('[Database] MongoDB connection closed gracefully.');
  } catch (error) {
    console.error(`[Database] Error during MongoDB disconnect: ${error.message}`);
  }
}
