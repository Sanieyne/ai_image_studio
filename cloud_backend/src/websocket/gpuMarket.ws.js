/**
 * Real-Time GPU Marketplace & Price Ticker WebSocket Handler
 * Route: /ws/gpu-market?token=ACCESS_TOKEN
 * Streams live Vast.ai offers every 10s and emits instance burn rate ticks every 5s.
 */

import { authenticateWebSocket } from './recommendation.ws.js';
import { gpuProviderService } from '../services/gpuProvider.service.js';
import { priceTrackerService } from '../services/priceTracker.service.js';

/**
 * Wire up WebSocket client lifecycle and message dispatching for GPU marketplace.
 * @param {import('ws').WebSocket} ws
 * @param {import('http').IncomingMessage} req
 * @param {Object} user
 */
export async function handleGpuMarketWS(ws, req, user) {
  let searchInterval = null;
  let priceTickInterval = null;
  let activeSearchPayload = null;
  let activeInstanceId = null;

  const send = (type, payload = null, message = null) => {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify({ type, payload, message, timestamp: new Date().toISOString() }));
    }
  };

  const clearTimers = () => {
    if (searchInterval) {
      clearInterval(searchInterval);
      searchInterval = null;
    }
    if (priceTickInterval) {
      clearInterval(priceTickInterval);
      priceTickInterval = null;
    }
  };

  // Execute single search run and send update
  const executeSearch = async (payload) => {
    try {
      const result = await gpuProviderService.searchAvailableGPUs({
        selectedModelIds: payload?.selectedModelIds || [],
        minVramGB: payload?.minVramGB ? Number(payload.minVramGB) : 0,
        maxPricePerHour: payload?.maxPrice ? Number(payload.maxPrice) : undefined,
        minInetDown: payload?.minInetDown ? Number(payload.minInetDown) : 50,
        gpuName: payload?.gpuName,
        limit: payload?.limit || 20,
      });
      send('GPU_OFFERS_UPDATE', result);
    } catch (err) {
      send('ERROR', null, `GPU Search Error: ${err.message}`);
    }
  };

  // Execute single price tick for an instance
  const executePriceTick = async (instanceId) => {
    try {
      const metrics = await priceTrackerService.trackPriceEat(instanceId);
      send('PRICE_TICK', metrics);
    } catch (err) {
      send('ERROR', null, `Price Tracker Error: ${err.message}`);
    }
  };

  ws.on('message', async (data) => {
    try {
      const parsed = JSON.parse(data.toString());
      const { type, payload } = parsed;

      switch (type) {
        case 'PING':
          send('PONG');
          break;

        case 'SEARCH_GPUS': {
          activeSearchPayload = payload || {};
          if (searchInterval) clearInterval(searchInterval);

          // Initial immediate broadcast
          await executeSearch(activeSearchPayload);

          // Stream live market updates every 10 seconds
          searchInterval = setInterval(() => {
            if (activeSearchPayload) {
              executeSearch(activeSearchPayload);
            }
          }, 10000);
          break;
        }

        case 'SUBSCRIBE_PRICE': {
          const { instanceId } = payload || {};
          if (!instanceId) {
            send('ERROR', null, 'instanceId is required for SUBSCRIBE_PRICE');
            return;
          }

          activeInstanceId = instanceId;
          if (priceTickInterval) clearInterval(priceTickInterval);

          // Initial immediate price tick
          await executePriceTick(activeInstanceId);

          // Emit price ticks every 5 seconds
          priceTickInterval = setInterval(() => {
            if (activeInstanceId) {
              executePriceTick(activeInstanceId);
            }
          }, 5000);
          break;
        }

        case 'UNSUBSCRIBE_SEARCH':
          if (searchInterval) {
            clearInterval(searchInterval);
            searchInterval = null;
          }
          activeSearchPayload = null;
          send('SEARCH_UNSUBSCRIBED');
          break;

        case 'UNSUBSCRIBE_PRICE':
          if (priceTickInterval) {
            clearInterval(priceTickInterval);
            priceTickInterval = null;
          }
          activeInstanceId = null;
          send('PRICE_UNSUBSCRIBED');
          break;

        default:
          send('ERROR', null, `Unknown message type: ${type}`);
      }
    } catch (err) {
      send('ERROR', null, err.message || 'Invalid WebSocket message');
    }
  });

  ws.on('error', (err) => {
    console.error(`[WS:GpuMarket] Error (${user.username}):`, err.message);
    clearTimers();
  });

  ws.on('close', () => {
    clearTimers();
  });
}
