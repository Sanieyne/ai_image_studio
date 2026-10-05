/**
 * Real-Time GPU Provisioning Status WebSocket Handler
 * Route: /ws/instance-status?token=ACCESS_TOKEN[&instanceId=INSTANCE_ID]
 * Streams instance lifecycle state transitions (PROVISIONING -> DOWNLOADING_MODEL -> READY / FAILED)
 * Enforces ownership authorization and pushes immediate state upon subscription.
 */

import { URL } from 'url';
import { GpuInstance } from '../models/GpuInstance.js';
import { instanceEvents, toWebSocketStatus, instancePollerService } from '../services/instancePoller.service.js';

// Map of instanceId -> Set<WebSocket>
const instanceSubscriptions = new Map();

// Global listener for status change events from instancePollerService
instanceEvents.on('status_change', (payload) => {
  const { instanceId } = payload;
  const subscribers = instanceSubscriptions.get(instanceId);
  if (!subscribers || subscribers.size === 0) return;

  const msg = JSON.stringify({
    type: 'STATUS_UPDATE',
    instanceId: payload.instanceId,
    status: payload.status,
    timestamp: payload.timestamp,
    details: payload.details,
  });

  for (const client of subscribers) {
    if (client.readyState === 1 /* WebSocket.OPEN */) {
      try {
        client.send(msg);
      } catch (err) {
        // Send failure handled on client close
      }
    }
  }
});

/**
 * Handle individual WebSocket connection lifecycle for instance status streaming
 * @param {import('ws').WebSocket} ws
 * @param {import('http').IncomingMessage} req
 * @param {Object} user - Authenticated user object
 */
export async function handleInstanceStatusWS(ws, req, user) {
  // Track all instanceIds this specific socket has subscribed to
  const subscribedInstanceIds = new Set();

  const send = (type, payload = null, message = null) => {
    if (ws.readyState === 1 /* WebSocket.OPEN */) {
      ws.send(JSON.stringify({ type, payload, message, timestamp: new Date().toISOString() }));
    }
  };

  // Notify client that connection and authentication succeeded
  send('CONNECTED', { userId: String(user._id), username: user.username });

  /**
   * Subscribe client to an instance after checking ownership
   * @param {string} instanceId
   */
  const subscribeInstance = async (instanceId) => {
    if (!instanceId) {
      send('ERROR', null, 'instanceId is required.');
      return;
    }

    try {
      const instance = await GpuInstance.findById(instanceId).lean();
      if (!instance) {
        send('ERROR', null, `Instance ${instanceId} not found.`);
        return;
      }

      // Enforce strict ownership check
      const isOwner = String(instance.user) === String(user._id);
      const isAdmin = user.role === 'admin';
      if (!isOwner && !isAdmin) {
        send('ERROR', null, 'Unauthorized: You do not own this GPU instance.');
        return;
      }

      // Add to tracking map
      if (!instanceSubscriptions.has(instanceId)) {
        instanceSubscriptions.set(instanceId, new Set());
      }
      instanceSubscriptions.get(instanceId).add(ws);
      subscribedInstanceIds.add(instanceId);

      // Confirm subscription
      send('SUBSCRIBED', { instanceId });

      // Requirement: Immediately push current status once upon subscription
      const currentStatus = toWebSocketStatus(instance.status);
      const lastDetails = instancePollerService.getLastKnownDetails(String(instance._id));
      ws.send(
        JSON.stringify({
          type: 'STATUS_UPDATE',
          instanceId: String(instance._id),
          status: currentStatus,
          timestamp: new Date().toISOString(),
          details: {
            gpuType: instance.gpuType,
            publicIp: instance.publicIp,
            pythonEngineUrl: instance.pythonEngineUrl,
            modelsRequested: instance.modelsRequested,
            startedAt: instance.startedAt,
            ...lastDetails,
          },
        })
      );
    } catch (err) {
      send('ERROR', null, `Failed to subscribe to instance ${instanceId}: ${err.message}`);
    }
  };

  /**
   * Unsubscribe client from an instance
   * @param {string} instanceId
   */
  const unsubscribeInstance = (instanceId) => {
    if (!instanceId) return;
    const subs = instanceSubscriptions.get(instanceId);
    if (subs) {
      subs.delete(ws);
      if (subs.size === 0) instanceSubscriptions.delete(instanceId);
    }
    subscribedInstanceIds.delete(instanceId);
    send('UNSUBSCRIBED', { instanceId });
  };

  // Cleanup on client close
  ws.on('close', () => {
    for (const instId of subscribedInstanceIds) {
      const subs = instanceSubscriptions.get(instId);
      if (subs) {
        subs.delete(ws);
        if (subs.size === 0) instanceSubscriptions.delete(instId);
      }
    }
    subscribedInstanceIds.clear();
  });

  // Handle incoming messages
  ws.on('message', async (data) => {
    try {
      const parsed = JSON.parse(data.toString());
      const type = parsed.type || parsed.action;
      const payload = parsed.payload || parsed;
      const targetInstanceId = payload.instanceId || parsed.instanceId;

      switch (type) {
        case 'PING':
          send('PONG');
          break;

        case 'SUBSCRIBE':
        case 'SUBSCRIBE_INSTANCE':
          await subscribeInstance(targetInstanceId);
          break;

        case 'UNSUBSCRIBE':
        case 'UNSUBSCRIBE_INSTANCE':
          unsubscribeInstance(targetInstanceId);
          break;

        default:
          send('ERROR', null, `Unknown message type: ${type}`);
      }
    } catch (parseErr) {
      send('ERROR', null, `Invalid JSON payload: ${parseErr.message}`);
    }
  });

  // Check if instanceId was supplied in the initial handshake query string
  try {
    const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const initialInstanceId = parsedUrl.searchParams.get('instanceId');
    if (initialInstanceId) {
      await subscribeInstance(initialInstanceId);
    }
  } catch (urlErr) {
    // Non-fatal
  }
}
