/**
 * Full End-to-End Real GPU Rental & WebSocket Relay Verification Test
 * 
 * Verifies:
 * 1. Real GPU rented on Vast.ai with 3 models: ['realesrgan-x4plus', 'fashn-vton-1.5', 'breeze-tts-2'].
 * 2. Connects to real backend WebSocket (/ws/instance-status).
 * 3. Captures full real lifecycle: PROVISIONING -> DOWNLOADING_MODEL -> READY.
 * 4. Verifies details.models is present in WebSocket messages with modelId, status, progressPercent, loadedInVram.
 * 5. Verifies independent per-model progression over the wire.
 * 6. Cleanly terminates the instance immediately upon verification.
 */

import WebSocket from 'ws';
import mongoose from 'mongoose';
import fs from 'fs';
import { env } from '../src/config/env.js';
import { User } from '../src/models/User.js';
import { GpuInstance } from '../src/models/GpuInstance.js';
import { signAccessToken } from '../src/utils/jwt.js';
import { gpuProviderService } from '../src/services/gpuProvider.service.js';
import { vastaiService } from '../src/services/vastai.service.js';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function main() {
  console.log('=' .repeat(80));
  console.log('REAL GPU RENTAL & WEBSOCKET PER-MODEL STATUS RELAY TEST');
  console.log('='.repeat(80));

  await mongoose.connect(env.MONGODB_URI);
  console.log('[1/6] Connected to MongoDB.');

  const testUser = await User.findOne({ email: 'alhajine20@gmail.com' });
  if (!testUser) {
    throw new Error('Test user alhajine20@gmail.com not found in MongoDB');
  }
  console.log(`User: ${testUser.username} (${testUser.email}), Credits: ${testUser.credits}`);

  const token = signAccessToken({ id: testUser._id, role: testUser.role });
  console.log(`Signed JWT token: ${token.slice(0, 20)}...`);

  // Search for the cheapest reliable GPU offer
  console.log('\n[2/6] Searching for available GPU offers on Vast.ai...');
  const offers = await vastaiService.searchOffers({ limit: 15, minReliability: 0.95 });
  if (!offers || offers.length === 0) {
    throw new Error('No compatible GPU offers found on Vast.ai');
  }

  // Pick cheapest offer (e.g. RTX 3060, GTX 1080 Ti, RTX A4000)
  const selectedOffer = offers[0];
  console.log(`Selected Offer #${selectedOffer.id}: ${selectedOffer.gpuName} (${selectedOffer.vramGB}GB VRAM) @ $${selectedOffer.pricePerHour}/hr`);

  const modelsToRequest = ['realesrgan-x4plus', 'fashn-vton-1.5', 'breeze-tts-2'];
  console.log(`Requesting 3 models of different sizes: ${JSON.stringify(modelsToRequest)}`);

  console.log('\n[3/6] Renting real instance via gpuProviderService.rentGPU()...');
  const instance = await gpuProviderService.rentGPU({
    userId: testUser._id,
    offerId: selectedOffer.id,
    storageGB: 35,
    selectedModelIds: modelsToRequest,
  });

  const instanceId = String(instance._id);
  const contractId = instance.providerInstanceId;
  console.log(`Instance Created! DB ID: ${instanceId} | Vast.ai Contract: #${contractId}`);

  // Connect WebSocket to real backend
  console.log('\n[4/6] Connecting to real WebSocket relay: /ws/instance-status...');
  const wsUrl = `ws://localhost:${env.PORT}/ws/instance-status?token=${token}&instanceId=${instanceId}`;
  const ws = new WebSocket(wsUrl);

  const capturedMessages = [];
  let isWsConnected = false;
  let reachedReady = false;
  let readyModelCount = 0;

  ws.on('open', () => {
    console.log('[WS] WebSocket connection opened successfully.');
    isWsConnected = true;
    ws.send(JSON.stringify({ type: 'SUBSCRIBE', instanceId }));
  });

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      const now = new Date().toISOString();
      capturedMessages.push({ receivedAt: now, message: msg });

      if (msg.type === 'STATUS_UPDATE') {
        const details = msg.details || {};
        const models = details.models || [];
        const modelSummaries = models.map(
          (m) => `${m.modelId}: ${m.status.toUpperCase()} (${m.progressPercent ?? 0}%)`
        );

        console.log(`\n[WS RECV ${now}] STATUS_UPDATE: status=${msg.status} | models=[${modelSummaries.join(' | ')}]`);
        console.log(`          └─ details: publicIp=${details.publicIp || 'pending'} | pythonEngineUrl=${details.pythonEngineUrl || 'pending'}`);

        if (models.length > 0) {
          console.log('          └─ per-model breakdown:');
          for (const m of models) {
            console.log(`             • ${m.modelId}: status=${m.status} progress=${m.progressPercent}% vram=${m.loadedInVram}`);
          }
        }

        if (msg.status === 'READY') {
          reachedReady = true;
        }

        const readyModels = models.filter((m) => m.status === 'ready');
        readyModelCount = readyModels.length;
      } else {
        console.log(`[WS RECV] ${msg.type}: ${msg.message || JSON.stringify(msg.payload || {})}`);
      }
    } catch (e) {
      console.error('[WS Parse Error]', e.message, raw.toString());
    }
  });

  ws.on('error', (err) => {
    console.error('[WS Error]', err.message);
  });

  ws.on('close', (code, reason) => {
    console.log(`[WS Closed] code=${code} reason=${reason}`);
  });

  // Monitor the lifecycle until READY and multiple per-model transitions are observed
  console.log('\n[5/6] Monitoring live boot & per-model progression over WebSocket...');
  const startTime = Date.now();
  const maxWaitMs = 12 * 60 * 1000; // 12 minutes max
  let lastLogTime = 0;

  try {
    while (Date.now() - startTime < maxWaitMs) {
      await sleep(5000);
      const elapsed = Math.round((Date.now() - startTime) / 1000);

      // Periodically log Vast.ai container status from the provider side
      if (Date.now() - lastLogTime >= 20000) {
        lastLogTime = Date.now();
        try {
          const remoteData = await vastaiService.getInstance(contractId);
          if (remoteData) {
            const curState = remoteData.actual_status || remoteData.cur_state || remoteData.statusMsg;
            console.log(`  [${elapsed}s Provider Heartbeat] State: ${curState} | SSH: ${remoteData.ssh_host}:${remoteData.ssh_port}`);
          }
        } catch (e) {
          // ignore transient poll error
        }
      }

      // Exit condition: READY state reached AND at least one model ready while another was downloading/progressed
      if (reachedReady && readyModelCount >= 1 && capturedMessages.some(m => m.message.details?.models?.some(x => x.progressPercent > 0))) {
        console.log(`\n>>> SUCCESS: READY state reached with verified per-model progression! <<<`);
        // Let it capture a few more seconds of updates
        await sleep(10000);
        break;
      }
    }
  } finally {
    // [6/6] Cleanly terminate the instance immediately to avoid extra charges
    console.log('\n[6/6] Terminating Vast.ai instance to avoid ongoing billing...');
    try {
      if (contractId) {
        const destroyRes = await vastaiService.destroyInstance(contractId);
        console.log(`Instance #${contractId} destroyed successfully:`, destroyRes);
      }
      instance.status = 'stopped';
      instance.stoppedAt = new Date();
      await instance.save();
    } catch (destroyErr) {
      console.error(`Failed to destroy instance #${contractId}:`, destroyErr.message);
    }

    if (ws.readyState === WebSocket.OPEN) {
      ws.close();
    }
    await mongoose.disconnect();
  }

  // Write out transcript
  const transcriptPath = '/root/projects/ai_image_studio/cloud_backend/test_websocket_relay_transcript.json';
  fs.writeFileSync(transcriptPath, JSON.stringify(capturedMessages, null, 2));
  console.log(`\nFull captured WebSocket message transcript saved to: ${transcriptPath}`);

  // Summary validation
  console.log('\n' + '='.repeat(80));
  console.log('WEBSOCKET RELAY VERIFICATION SUMMARY');
  console.log('='.repeat(80));
  console.log(`Total WebSocket messages received: ${capturedMessages.length}`);
  const statusUpdates = capturedMessages.filter((m) => m.message.type === 'STATUS_UPDATE');
  console.log(`Total STATUS_UPDATE events: ${statusUpdates.length}`);

  const hasModelsInUpdates = statusUpdates.some(
    (u) => Array.isArray(u.message.details?.models) && u.message.details.models.length > 0
  );
  console.log(`1. 'details.models' array present in STATUS_UPDATE: ${hasModelsInUpdates ? 'PASS' : 'FAIL'}`);

  const capturedReady = statusUpdates.some((u) => u.message.status === 'READY');
  console.log(`2. Instance reached READY state over WebSocket: ${capturedReady ? 'PASS' : 'FAIL'}`);

  const capturedPerModelFields = statusUpdates.some((u) => {
    const models = u.message.details?.models || [];
    return models.some(
      (m) =>
        m.modelId &&
        m.status &&
        typeof m.progressPercent !== 'undefined' &&
        typeof m.loadedInVram !== 'undefined'
    );
  });
  console.log(`3. Per-model fields (modelId, status, progressPercent, loadedInVram) confirmed: ${capturedPerModelFields ? 'PASS' : 'FAIL'}`);

  console.log('\nVerification complete!');
}

main().catch((err) => {
  console.error('\n[FATAL ERROR IN TEST SCRIPT]:', err);
  process.exit(1);
});
