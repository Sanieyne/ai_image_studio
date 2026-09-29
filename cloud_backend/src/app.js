/**
 * Express Application Factory
 * Configures global security headers, CORS, body parsers, logging, routes, and error handlers.
 */

import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';

import { env } from './config/env.js';
import routes from './routes/index.js';
import { errorHandler } from './middleware/error.middleware.js';
import { apiLimiter } from './middleware/rateLimiter.middleware.js';
import { ApiError } from './utils/ApiError.js';

export function createApp() {
  const app = express();

  // Trust reverse proxy (Contabo Nginx / Cloudflare)
  app.set('trust proxy', 1);

  // Security HTTP headers
  app.use(helmet());

  // CORS configuration
  app.use(
    cors({
      origin: env.isProduction
        ? [
            'https://cosmic-gen.com',
            'https://www.cosmic-gen.com',
            // TODO: Remove nass-works.com after transition period (~2 weeks)
            'https://nass-works.com',
            'https://www.nass-works.com',
            'http://localhost:3000',
          ]
        : '*',
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization', 'x-test-moderation-verdict'],
    })
  );

  // HTTP Request Logging
  if (!env.isTest) {
    app.use(morgan(env.isProduction ? 'combined' : 'dev'));
  }

  // Rate Limiting on API routes
  app.use('/api', apiLimiter);

  // Body parsers (allow up to 50mb for media base64 uploads)
  app.use(express.json({ limit: '50mb' }));
  app.use(express.urlencoded({ extended: true, limit: '50mb' }));

  // Root redirect/health
  app.get('/', (req, res) => {
    res.status(200).json({
      name: 'AI Image Studio Cloud Orchestrator API',
      version: '1.0.0',
      docs: '/api/v1/health',
    });
  });

  // API v1 Routing
  app.use('/api/v1', routes);

  // 404 handler for unmapped routes
  app.use((req, res, next) => {
    next(ApiError.notFound(`Cannot find endpoint ${req.method} ${req.originalUrl}`));
  });

  // Centralized Error Handling Middleware
  app.use(errorHandler);

  return app;
}
