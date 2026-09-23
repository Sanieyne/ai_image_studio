/**
 * Real-Time Model Recommendation WebSocket Handler
 * Route: /ws/recommendations?token=ACCESS_TOKEN
 * Provides instant live sizing feedback as user toggles models in UI.
 */

import { URL } from 'url';
import { verifyAccessToken } from '../utils/jwt.js';
import { User } from '../models/User.js';
import { recommendationService } from '../services/recommendation.service.js';

/**
 * Authenticate incoming WebSocket connection via query token or Bearer header.
 * @param {import('http').IncomingMessage} req
 * @returns {Promise<Object>} user document or throws error
 */
export async function authenticateWebSocket(req) {
  try {
    const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    let token = parsedUrl.searchParams.get('token');

    if (!token && req.headers.authorization && req.headers.authorization.startsWith('Bearer ')) {
      token = req.headers.authorization.split(' ')[1];
    }

    if (!token) {
      throw new Error('Authentication token required in query (?token=) or header.');
    }

    const decoded = verifyAccessToken(token);
    const user = await User.findById(decoded.id).select('_id username email selectedModels isActive');

    if (!user) {
      throw new Error('User not found.');
    }

    if (!user.isActive) {
      throw new Error('User account is inactive.');
    }

    return user;
  } catch (error) {
    throw new Error(`WebSocket authentication failed: ${error.message}`);
  }
}

/**
 * Wire up WebSocket client lifecycle and message dispatching.
 * @param {import('ws').WebSocket} ws
 * @param {import('http').IncomingMessage} req
 * @param {Object} user
 */
export async function handleRecommendationWS(ws, req, user) {
  // Helper to send formatted JSON
  const send = (type, payload = null, message = null) => {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify({ type, payload, message, timestamp: new Date().toISOString() }));
    }
  };

  // Send initial state if user already has selected models
  try {
    const initialModels = user.selectedModels || ['sdxl-base-1.0'];
    const initialRecs = await recommendationService.calculateRequirements(initialModels);
    send('RECOMMENDATION_UPDATE', initialRecs);
  } catch (err) {
    // Non-fatal, just log or notify
    console.warn(`[WS] Initial recommendation calculation skipped: ${err.message}`);
  }

  // Handle incoming messages
  ws.on('message', async (data) => {
    try {
      const parsed = JSON.parse(data.toString());
      const { type, payload } = parsed;

      switch (type) {
        case 'PING':
          send('PONG');
          break;

        case 'SELECT_MODELS': {
          const modelIds = payload?.modelIds;
          if (!Array.isArray(modelIds) || modelIds.length === 0) {
            send('ERROR', null, 'payload.modelIds must be a non-empty array of model IDs.');
            return;
          }

          const recs = await recommendationService.calculateRequirements(modelIds);

          // If persist flag is true, update the user selection in DB
          if (payload?.persist) {
            await User.findByIdAndUpdate(user._id, { selectedModels: modelIds });
          }

          send('RECOMMENDATION_UPDATE', recs);
          break;
        }

        default:
          send('ERROR', null, `Unknown message type: ${type}`);
      }
    } catch (err) {
      send('ERROR', null, err.message || 'Internal WebSocket error');
    }
  });

  ws.on('error', (err) => {
    console.error(`[WS] Client error (${user.username}):`, err.message);
  });

  ws.on('close', (code, reason) => {
    // Clean close
  });
}
