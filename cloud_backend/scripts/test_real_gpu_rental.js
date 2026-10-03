import { gpuProviderService } from '../src/services/gpuProvider.service.js';
import { vastaiService } from '../src/services/vastai.service.js';
import { GpuInstance } from '../src/models/GpuInstance.js';
import { User } from '../src/models/User.js';
import mongoose from 'mongoose';
import { env } from '../src/config/env.js';
import { execSync } from 'child_process';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function main() {
  console.log('=== [1/6] Connecting to DB & Validating User ===');
  await mongoose.connect(env.MONGODB_URI);
  let testUser = await User.findOne({ email: 'uone400755@example.com' });
  if (!testUser) testUser = await User.findOne({ credits: { $gt: 10 } });
  console.log(`User: ${testUser.email} (Credits: ${testUser.credits})`);

  console.log('\n=== [2/6] Selecting Live Cheap GPU Offer ===');
  const offers = await vastaiService.searchOffers({ limit: 10, minReliability: 0.95 });
  const offer = offers[0];
  console.log(`Chosen Offer: ID ${offer.id} | GPU: ${offer.gpuName} | $${offer.pricePerHour}/hr | Rel: ${offer.reliability}`);

  console.log('\n=== [3/6] Launching Real Remote Instance via rentGPU() ===');
  const instance = await gpuProviderService.rentGPU({
    userId: testUser._id,
    offerId: offer.id,
    storageGB: 30,
    selectedModelIds: ['realesrgan-x4plus'],
  });

  const contractId = instance.providerInstanceId;
  console.log(`\nREAL VAST.AI CONTRACT ESTABLISHED: #${contractId}`);
  console.log(`DB Instance ID: ${instance._id}`);
  console.log(`Models Requested: ${JSON.stringify(instance.modelsRequested)}`);

  console.log('\n=== [4/6] Polling Instance Status & Network Mapping from Vast.ai ===');
  let instanceData = null;
  let publicIp = null;
  let publicPort = null;
  const startTime = Date.now();
  const maxWaitMs = 10 * 60 * 1000; // 10 minutes max boot time

  while (Date.now() - startTime < maxWaitMs) {
    await sleep(8000);
    instanceData = await vastaiService.getInstance(contractId);
    if (!instanceData) {
      console.log(`[${Math.round((Date.now() - startTime) / 1000)}s] Waiting for instance data...`);
      continue;
    }

    const status = instanceData.actual_status || instanceData.cur_state || instanceData.statusMsg || 'provisioning';
    console.log(`[${Math.round((Date.now() - startTime) / 1000)}s] Status: ${status} | Host: ${instanceData.ssh_host}:${instanceData.ssh_port}`);

    // Check port mapping for 8000/tcp
    if (instanceData.ports && instanceData.ports['8000/tcp']) {
      const portObj = instanceData.ports['8000/tcp'][0];
      publicPort = portObj.HostPort;
      publicIp = instanceData.public_ipaddr || instanceData.ssh_host;
      console.log(`>>> Discovered Port Mapping: http://${publicIp}:${publicPort} -> container:8000`);
    }

    if (status === 'running' && publicPort) {
      console.log(`[OK] Instance reached RUNNING state! Public endpoint: http://${publicIp}:${publicPort}`);
      break;
    }
  }

  console.log('\n=== [5/6] Testing Public /health Endpoint Over the Internet ===');
  if (publicIp && publicPort) {
    let healthSuccess = false;
    for (let attempt = 1; attempt <= 20; attempt++) {
      console.log(`[Attempt ${attempt}/20] Querying http://${publicIp}:${publicPort}/health...`);
      try {
        const rawRes = execSync(`curl -s --connect-timeout 5 --max-time 10 http://${publicIp}:${publicPort}/health`, {
          encoding: 'utf-8',
        }).trim();
        if (rawRes && rawRes.startsWith('{')) {
          console.log('\n================ REAL REMOTE ENGINE HEALTH RESPONSE ================');
          console.log(rawRes);
          console.log('====================================================================\n');
          const parsed = JSON.parse(rawRes);
          console.log(`Verified Real Device: ${parsed.device} (${parsed.device_name})`);
          console.log(`Verified Status: ${parsed.status}`);
          healthSuccess = true;
          break;
        } else if (rawRes) {
          console.log(`Received non-JSON response: ${rawRes.substring(0, 100)}...`);
        }
      } catch (err) {
        console.log(`Curl attempt ${attempt} not responding yet: ${err.message}`);
      }
      await sleep(10000);
    }
  } else {
    console.log('[!] Warning: Instance did not provide public port mapping in time.');
  }

  console.log('\n=== Fetching Console Logs from Instance ===');
  try {
    const logs = await vastaiService.getInstanceLogs(contractId);
    console.log('--- Last 30 lines of instance console logs ---');
    console.log(logs.split('\n').slice(-30).join('\n'));
    console.log('----------------------------------------------');
  } catch (e) {
    console.log('Could not fetch console logs:', e.message);
  }

  console.log('\n=== [6/6] Terminating Instance to Stop Billing ===');
  try {
    const destroyRes = await vastaiService.destroyInstance(contractId);
    console.log(`Instance #${contractId} destroyed successfully:`, destroyRes);
    instance.status = 'stopped';
    instance.stoppedAt = new Date();
    await instance.save();
  } catch (e) {
    console.error(`Failed to terminate instance #${contractId}:`, e.message);
  }

  await mongoose.disconnect();
  console.log('\n[TEST COMPLETE]');
}

main().catch((err) => {
  console.error('[FATAL ERROR]', err);
  process.exit(1);
});
