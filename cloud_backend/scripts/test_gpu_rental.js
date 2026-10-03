import { gpuProviderService } from '../src/services/gpuProvider.service.js';
import { vastaiService } from '../src/services/vastai.service.js';
import { GpuInstance } from '../src/models/GpuInstance.js';
import { User } from '../src/models/User.js';
import mongoose from 'mongoose';
import { env } from '../src/config/env.js';
import { execSync, spawn } from 'child_process';
import fs from 'fs';

async function run() {
  console.log('=== [1/4] Connecting to Database ===');
  await mongoose.connect(env.MONGODB_URI);
  console.log('Connected to MongoDB');

  // Find user with credits
  let testUser = await User.findOne({ email: 'uone400755@example.com' });
  if (!testUser) {
    testUser = await User.findOne({ credits: { $gt: 10 } });
  }
  if (!testUser) {
    throw new Error('No user with credits found');
  }
  console.log(`Using test user: ${testUser.email} (Credits: ${testUser.credits})`);

  console.log('\n=== [2/4] Fetching Live GPU Offer ===');
  const offers = await vastaiService.searchOffers({ limit: 5 });
  const offer = offers[0];
  console.log(`Selected offer: ID ${offer.id}, GPU: ${offer.gpuName}, Price: $${offer.pricePerHour}/hr`);

  console.log('\n=== [3/4] Testing rentGPU() with onstart generation ===');
  const instance = await gpuProviderService.rentGPU({
    userId: testUser._id,
    offerId: offer.id,
    storageGB: 30,
    selectedModelIds: ['realesrgan-x4plus'],
  });

  console.log('GPU Instance created successfully:');
  console.log(`- Instance ID: ${instance._id}`);
  console.log(`- Provider Instance ID: ${instance.providerInstanceId}`);
  console.log(`- Status: ${instance.status}`);
  console.log(`- Models Requested: ${JSON.stringify(instance.modelsRequested)}`);
  console.log(`- Provisioning Logs: ${instance.provisioningLogs.map(l => l.message).join('; ')}`);

  console.log('\n=== [4/4] Generating and Verifying Onstart Script Execution ===');
  const onstartScript = gpuProviderService._generateOnstartScript({
    selectedModelIds: ['realesrgan-x4plus'],
  });
  console.log('Onstart Script preview (first 15 lines):');
  console.log(onstartScript.split('\n').slice(0, 15).join('\n'));

  // Write script to /tmp/test_onstart.sh
  fs.writeFileSync('/tmp/test_onstart.sh', onstartScript, { mode: 0o755 });
  console.log('\nTesting onstart execution with real R2 download & engine launch...');

  // Set env vars as Vast.ai would set them
  const testEnv = {
    ...process.env,
    AI_STUDIO_SELECTED_MODELS: 'realesrgan-x4plus',
    AI_STUDIO_SKIP_PIP: '1',
    R2_ENDPOINT: env.R2_ENDPOINT,
    R2_BUCKET_NAME: env.R2_BUCKET_NAME,
    R2_ACCESS_KEY_ID: env.R2_READONLY_ACCESS_KEY_ID || env.R2_ACCESS_KEY_ID,
    R2_SECRET_ACCESS_KEY: env.R2_READONLY_SECRET_ACCESS_KEY || env.R2_SECRET_ACCESS_KEY,
  };

  // Run onstart script
  const child = spawn('/bin/bash', ['/tmp/test_onstart.sh'], {
    env: testEnv,
    stdio: 'inherit',
  });

  await new Promise((resolve, reject) => {
    child.on('exit', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`Onstart script exited with code ${code}`));
    });
  });

  console.log('\n=== Health Verification from Host ===');
  const healthRes = execSync('curl -s http://127.0.0.1:8000/health').toString();
  console.log('GET /health response:', healthRes);

  // Terminate test background engine process if running on port 8000
  try {
    execSync('pkill -f "python3 app.py" || true');
  } catch (e) {}

  console.log('\n[SUCCESS] GPU Rental & Onstart pipeline verified end-to-end!');
  await mongoose.disconnect();
}

run().catch((err) => {
  console.error('[TEST FAILED]', err);
  process.exit(1);
});
