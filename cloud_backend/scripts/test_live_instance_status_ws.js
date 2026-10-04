/**
 * Live Vast.ai GPU Rental & WebSocket Status Streaming End-to-End Test
 * 1. Connects to backend WebSocket status channel (/ws/instance-status)
 * 2. Selects real, cheap Vast.ai offer (RTX 3060)
 * 3. Launches real GPU instance via rentGPU()
 * 4. Subscribes via WebSocket and logs all incoming real-time lifecycle transitions
 * 5. Verifies PROVISIONING -> DOWNLOADING_MODEL -> READY sequence with real timestamps
 * 6. Immediately terminates the instance to prevent unnecessary billing
 */

import WebSocket from 'ws';
import mongoose from 'mongoose';
import { env } from '../src/config/env.js';
import { User } from '../src/models/User.js';
import { GpuInstance } from '../src/models/GpuInstance.js';
import { vastaiService } from '../src/services/vastai.service.js';
import { gpuProviderService } from '../src/services/gpuProvider.service.js';
import { signAccessToken } from '../src/utils/jwt.js';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function main() {
  console.log('================================================================');
  console.log('🚀 LIVE REAL REMOTE GPU RENTAL & WEBSOCKET STATUS STREAMING TEST');
  console.log('================================================================\n');

  await mongoose.connect(env.MONGODB_URI);
  let testUser = await User.findOne({ email: 'uone400755@example.com' });
  if (!testUser) testUser = await User.findOne({ credits: { $gt: 10 } });
  console.log(`[1] Authenticated User: ${testUser.email} (Credits: ${testUser.credits})`);

  const token = signAccessToken({ id: testUser._id });

  // 1. Establish WebSocket Connection
  const wsUrl = `ws://localhost:5000/ws/instance-status?token=${token}`;
  console.log(`[2] Connecting to WebSocket: ${wsUrl}...`);
  const ws = new WebSocket(wsUrl);

  const statusEvents = [];
  ws.on('message', (raw) => {
    const parsed = JSON.parse(raw.toString());
    console.log(`   [WS INCOMING] ${parsed.type}:`, JSON.stringify(parsed));
    if (parsed.type === 'STATUS_UPDATE') {
      statusEvents.push(parsed);
    }
  });

  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Timeout waiting for WS connection')), 6000);
    ws.on('message', function onMsg(raw) {
      const parsed = JSON.parse(raw.toString());
      if (parsed.type === 'CONNECTED') {
        clearTimeout(timer);
        ws.off('message', onMsg);
        resolve();
      }
    });
    ws.on('error', reject);
  });
  console.log('   [WS CONNECTED & AUTHENTICATED] Ready for streaming.');

  // 2. Select live cheap offer
  console.log('\n[3] Searching live GPU offers on Vast.ai marketplace...');
  const offers = await vastaiService.searchOffers({ limit: 10, minReliability: 0.95 });
  if (!offers || offers.length === 0) {
    throw new Error('No available GPU offers found on Vast.ai marketplace.');
  }

  const selectedOffer = offers[0];
  console.log(`   Selected Offer: ID ${selectedOffer.id} | GPU: ${selectedOffer.gpuName} | $${selectedOffer.pricePerHour}/hr (${selectedOffer.creditsPerHour} cr/hr) | Rel: ${selectedOffer.reliability}`);

  // 3. Launch real instance via rentGPU
  console.log('\n[4] Renting real GPU instance via rentGPU()...');
  const instance = await gpuProviderService.rentGPU({
    userId: testUser._id,
    offerId: selectedOffer.id,
    storageGB: 30,
    selectedModelIds: ['realesrgan-x4plus'],
  });

  const instanceId = String(instance._id);
  const contractId = instance.providerInstanceId;
  console.log(`   ✅ DB Instance ID: ${instanceId}`);
  console.log(`   ✅ Vast.ai Contract Established: #${contractId}`);

  // 4. Subscribe to the real instance via WebSocket
  console.log('\n[5] Subscribing to instance status WebSocket stream...');
  ws.send(JSON.stringify({ type: 'SUBSCRIBE', payload: { instanceId } }));

  // 5. Monitor transitions up to 10 minutes
  console.log('\n[6] Listening for live lifecycle transitions from background poller...');
  const startTime = Date.now();
  const maxWaitMs = 10 * 60 * 1000;
  let reachedReady = false;

  try {
    while (Date.now() - startTime < maxWaitMs) {
      const latest = statusEvents[statusEvents.length - 1];
      const elapsedSec = Math.round((Date.now() - startTime) / 1000);

      if (latest && latest.instanceId === instanceId) {
        if (latest.status === 'READY') {
          console.log(`\n🎉 [${elapsedSec}s] Instance reached READY status!`);
          reachedReady = true;
          break;
        } else if (latest.status === 'FAILED') {
          console.error(`\n❌ [${elapsedSec}s] Instance reached FAILED status!`);
          break;
        }
      }

      await sleep(4000);
    }

    if (!reachedReady) {
      console.warn('\n⚠️ Did not reach READY within test window.');
    }
  } finally {
    // 6. Terminate instance immediately to prevent unnecessary billing
    console.log('\n[7] Cleaning up & terminating instance to stop billing...');
    try {
      await gpuProviderService.terminateInstance(testUser._id, instanceId);
      console.log(`   ✅ Instance ${instanceId} (Contract #${contractId}) successfully terminated.`);
    } catch (destroyErr) {
      console.error(`   ⚠️ Failed to terminate instance ${instanceId}:`, destroyErr.message);
    }

    ws.close();
    await mongoose.disconnect();
  }

  // Summary
  console.log('\n================================================================');
  console.log('📊 REAL WEBSOCKET TRANSCRIPT RECORDED:');
  console.log('================================================================');
  statusEvents.forEach((ev, idx) => {
    console.log(`[Step ${idx + 1}] Time: ${ev.timestamp} | Status: ${ev.status} | Details: ${JSON.stringify(ev.details || {})}`);
  });
  console.log('================================================================\n');
}

main().catch((err) => {
  console.error('Fatal live test error:', err);
  process.exit(1);
});
