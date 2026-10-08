/**
 * Event bus for GPU instance status changes, shared by the poller and billing
 * and forwarded to WebSocket subscribers by websocket/instanceStatus.ws.js.
 */

import { EventEmitter } from 'events';

export const instanceEvents = new EventEmitter();

/**
 * Standardize database status into WebSocket status string
 * @param {string} dbStatus
 * @returns {string}
 */
export function toWebSocketStatus(dbStatus) {
  switch (dbStatus?.toLowerCase()) {
    case 'provisioning':
      return 'PROVISIONING';
    case 'downloading_model':
      return 'DOWNLOADING_MODEL';
    case 'ready':
      return 'READY';
    case 'running':
      return 'READY';
    case 'failed':
      return 'FAILED';
    case 'stopped':
      return 'STOPPED';
    default:
      return (dbStatus || 'UNKNOWN').toUpperCase();
  }
}
