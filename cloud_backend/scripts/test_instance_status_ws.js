/**
 * Automated Verification Script for Instance Health Poller & WebSocket Channel
 * Tests:
 * 1. Authentication & ownership authorization
 * 2. Immediate push of current status upon subscription
 * 3. Event-driven transition: PROVISIONING -> DOWNLOADING_MODEL -> READY
 * 4. Timeout transition: -> FAILED with auto-termination
 * 5. WebSocket message structure: { instanceId, status, timestamp }
 */

import http from 'http';
import WebSocket from 'ws';
import mongoose from 'mongoose';
import { env } from '../src/config/env.js';
import { User } from '../src/models/User.js';
import { GpuInstance } from '../src/models/GpuInstance.js';
import { signAccessToken } from '../src/utils/jwt.js';
import { instancePollerService } from '../src/services/instancePoller.service.js';
import { GPU_STATUS, GPU_PROVIDERS } from '../src/config/constants.js';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function main() {
  console.log('================================================================');
  console.log('🧪 Starting Instance Poller & WebSocket Status Stream Verification');
  console.log('================================================================\n');

  await mongoose.connect(env.MONGODB_URI);
  let testUser = await User.findOne({ email: 'uone400755@example.com' });
  if (!testUser) testUser = await User.findOne();
  console.log(`[1] Authenticated Test User: ${testUser.email} (ID: ${testUser._id})`);

  let otherUser = await User.findOne({ _id: { $ne: testUser._id } });
  if (!otherUser) {
    otherUser = await User.create({
      username: 'other_test_user_' + Date.now(),
      email: `other_${Date.now()}@example.com`,
      passwordHash: 'dummyhash',
      credits: 50,
    });
  }

  const token = signAccessToken({ id: testUser._id });

  // Spin up a lightweight local mock server to simulate the remote Python engine's /health endpoint
  let mockEngineState = {
    reachable: false,
    model_loaded: false,
    current_model: null,
  };

  const mockPort = 8089;
  const mockServer = http.createServer((req, res) => {
    if (!mockEngineState.reachable) {
      req.socket.destroy();
      return;
    }

    if (req.url === '/health' && req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(
        JSON.stringify({
          status: mockEngineState.model_loaded ? 'ok' : 'ok-mock',
          device: 'cuda',
          device_name: 'NVIDIA GeForce RTX 3060',
          model_loaded: mockEngineState.model_loaded,
          current_model: mockEngineState.current_model,
        })
      );
    } else {
      res.writeHead(404);
      res.end();
    }
  });

  await new Promise((resolve) => mockServer.listen(mockPort, '127.0.0.1', resolve));
  console.log(`[2] Mock Remote Engine created on http://127.0.0.1:${mockPort}`);

  // Create a test instance belonging to testUser
  const testInstance = await GpuInstance.create({
    user: testUser._id,
    provider: GPU_PROVIDERS.VASTAI,
    providerInstanceId: `test-contract-${Date.now()}`,
    status: GPU_STATUS.PROVISIONING,
    gpuType: 'RTX 3060',
    vramGB: 12,
    costPerHour: 0.25,
    publicIp: '127.0.0.1',
    pythonEngineUrl: `http://127.0.0.1:${mockPort}`,
    modelsRequested: ['sdxl-base-1.0'],
    startedAt: new Date(),
  });
  console.log(`[3] Created Test GpuInstance: ID ${testInstance._id} (status: ${testInstance.status})`);

  // Create an instance belonging to otherUser to test ownership rejection
  const unauthorizedInstance = await GpuInstance.create({
    user: otherUser._id,
    provider: GPU_PROVIDERS.VASTAI,
    providerInstanceId: `test-unauth-${Date.now()}`,
    status: GPU_STATUS.PROVISIONING,
    gpuType: 'RTX 4090',
    vramGB: 24,
    costPerHour: 0.75,
  });

  // Connect to WebSocket /ws/instance-status
  const wsUrl = `ws://localhost:5000/ws/instance-status?token=${token}`;
  console.log(`[4] Connecting to WebSocket: ${wsUrl}...`);
  const ws = new WebSocket(wsUrl);

  const receivedMessages = [];
  ws.on('message', (raw) => {
    const parsed = JSON.parse(raw.toString());
    receivedMessages.push(parsed);
    console.log(`   [WS INCOMING] ${parsed.type || 'MSG'}:`, JSON.stringify(parsed));
  });

  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Timed out waiting for CONNECTED message')), 5000);
    const checkConnected = (raw) => {
      const parsed = JSON.parse(raw.toString());
      if (parsed.type === 'CONNECTED') {
        clearTimeout(timeout);
        ws.off('message', checkConnected);
        resolve();
      }
    };
    ws.on('message', checkConnected);
    ws.on('error', reject);
  });
  console.log('   [WS CONNECTED & AUTHENTICATED] Server ready.');

  // Test 1: Subscribe to unauthorized instance (must reject with ERROR)
  console.log('\n--- Sub-test A: Ownership Authorization Check ---');
  ws.send(JSON.stringify({ type: 'SUBSCRIBE', payload: { instanceId: String(unauthorizedInstance._id) } }));
  await sleep(600);

  const authErrorMsg = receivedMessages.find(
    (m) => m.type === 'ERROR' && m.message?.includes('Unauthorized')
  );
  if (!authErrorMsg) {
    throw new Error('FAILED: Expected unauthorized subscription rejection!');
  }
  console.log('   ✅ PASS: Unauthorized instance subscription correctly rejected.');

  // Test 2: Subscribe to owned instance (must receive SUBSCRIBED and immediate current STATUS_UPDATE)
  console.log('\n--- Sub-test B: Subscribe & Immediate Status Push ---');
  ws.send(JSON.stringify({ type: 'SUBSCRIBE', payload: { instanceId: String(testInstance._id) } }));
  await sleep(600);

  const immediateStatus = receivedMessages.find(
    (m) => m.type === 'STATUS_UPDATE' && m.instanceId === String(testInstance._id) && m.status === 'PROVISIONING'
  );
  if (!immediateStatus) {
    throw new Error('FAILED: Did not receive immediate STATUS_UPDATE with PROVISIONING status!');
  }
  console.log('   ✅ PASS: Received immediate initial status update:');
  console.log(`      Status: ${immediateStatus.status} | Timestamp: ${immediateStatus.timestamp}`);

  // Test 3: Engine still unreachable -> Poller runs, status must stay PROVISIONING (no duplicate broadcast)
  console.log('\n--- Sub-test C: Port Unreachable -> Stays PROVISIONING ---');
  const countBefore = receivedMessages.filter((m) => m.instanceId === String(testInstance._id)).length;
  await instancePollerService.pollInstance(testInstance);
  await sleep(300);

  const countAfter = receivedMessages.filter((m) => m.instanceId === String(testInstance._id)).length;
  if (countBefore !== countAfter) {
    throw new Error('FAILED: Spurious message sent while remaining in PROVISIONING state.');
  }
  console.log('   ✅ PASS: No-op polling verified — stayed PROVISIONING without sending spam messages.');

  const waitForStatus = (instanceId, expectedStatus, timeoutMs = 12000) => {
    return new Promise((resolve, reject) => {
      const existing = receivedMessages.find(
        (m) => m.type === 'STATUS_UPDATE' && m.instanceId === String(instanceId) && m.status === expectedStatus
      );
      if (existing) return resolve(existing);

      const timer = setTimeout(() => {
        ws.off('message', handler);
        reject(new Error(`Timed out waiting for status ${expectedStatus} on instance ${instanceId}`));
      }, timeoutMs);

      const handler = (raw) => {
        const parsed = JSON.parse(raw.toString());
        if (parsed.type === 'STATUS_UPDATE' && parsed.instanceId === String(instanceId) && parsed.status === expectedStatus) {
          clearTimeout(timer);
          ws.off('message', handler);
          resolve(parsed);
        }
      };
      ws.on('message', handler);
    });
  };

  // Test 4: Engine starts responding with model_loaded: false -> Transition to DOWNLOADING_MODEL
  console.log('\n--- Sub-test D: Engine Online, model_loaded: false -> Transition to DOWNLOADING_MODEL ---');
  mockEngineState.reachable = true;
  mockEngineState.model_loaded = false;

  console.log('   Waiting for background poller to detect model download...');
  const downloadingMsg = await waitForStatus(testInstance._id, 'DOWNLOADING_MODEL');
  console.log('   ✅ PASS: Successfully transitioned to DOWNLOADING_MODEL:');
  console.log(`      Payload: ${JSON.stringify(downloadingMsg)}`);

  // Verify DB state
  const dbInst1 = await GpuInstance.findById(testInstance._id);
  console.log(`      Database Status: ${dbInst1.status}`);

  // Test 5: Engine finishes downloading, model_loaded: true -> Transition to READY
  console.log('\n--- Sub-test E: Model Loaded into VRAM -> Transition to READY ---');
  mockEngineState.model_loaded = true;
  mockEngineState.current_model = 'stabilityai/stable-diffusion-xl-base-1.0';

  console.log('   Waiting for background poller to detect ready state...');
  const readyMsg = await waitForStatus(testInstance._id, 'READY');
  console.log('   ✅ PASS: Successfully transitioned to READY:');
  console.log(`      Payload: ${JSON.stringify(readyMsg)}`);

  // Verify DB state
  const dbInst2 = await GpuInstance.findById(testInstance._id);
  console.log(`      Database Status: ${dbInst2.status}`);

  // Test 6: Timeout test -> Transition to FAILED with auto-termination
  console.log('\n--- Sub-test F: Timeout Ceiling Exceeded -> Transition to FAILED ---');
  const timeoutInstance = await GpuInstance.create({
    user: testUser._id,
    provider: GPU_PROVIDERS.VASTAI,
    providerInstanceId: `mock-contract-timeout-${Date.now()}`,
    status: GPU_STATUS.PROVISIONING,
    gpuType: 'RTX 3090',
    vramGB: 24,
    costPerHour: 0.35,
    // Set startedAt to 30 minutes ago to trigger timeout (base timeout is 25 min)
    startedAt: new Date(Date.now() - 30 * 60 * 1000),
  });

  // Subscribe to timeout instance
  ws.send(JSON.stringify({ type: 'SUBSCRIBE', payload: { instanceId: String(timeoutInstance._id) } }));
  await sleep(400);

  console.log('   Waiting for background poller to enforce timeout ceiling...');
  const failedMsg = await waitForStatus(timeoutInstance._id, 'FAILED');
  console.log('   ✅ PASS: Successfully transitioned to FAILED upon timeout:');
  console.log(`      Payload: ${JSON.stringify(failedMsg)}`);

  const dbInst3 = await GpuInstance.findById(timeoutInstance._id);
  console.log(`      Database Status: ${dbInst3.status}`);
  console.log(`      Logs: ${JSON.stringify(dbInst3.provisioningLogs.map((l) => l.message))}`);

  // Clean up
  console.log('\n--- Cleanup ---');
  ws.close();
  mockServer.close();
  await GpuInstance.deleteMany({ _id: { $in: [testInstance._id, unauthorizedInstance._id, timeoutInstance._id] } });
  if (otherUser.username.startsWith('other_test_user_')) {
    await User.deleteOne({ _id: otherUser._id });
  }
  await mongoose.disconnect();

  console.log('\n================================================================');
  console.log('🎉 ALL HEALTH POLLER & WEBSOCKET VERIFICATION TESTS PASSED!');
  console.log('================================================================');
}

main().catch((err) => {
  console.error('\n❌ TEST FAILED:', err);
  process.exit(1);
});
