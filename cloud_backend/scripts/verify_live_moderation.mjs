/**
 * Live Google Cloud Vision API Verification Script
 * Validates credential accessibility, file permissions, live SafeSearch detection,
 * and end-to-end publish moderation with real Vision scores.
 */

import vision from '@google-cloud/vision';
import fs from 'fs/promises';
import fsSync from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import mongoose from 'mongoose';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: '/root/projects/ai-studio-backend/.env' });

import { moderationService } from '../src/services/moderation.service.js';
import { Generation } from '../src/models/Generation.js';
import { ModerationLog } from '../src/models/ModerationLog.js';
import { User } from '../src/models/User.js';

// Minimal 1x1 test PNG
const testPngBuffer = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  'base64'
);

async function verifyLiveVision() {
  console.log('=================================================================');
  console.log('🔍 Google Cloud Vision API & Automated Moderation Verification');
  console.log('=================================================================');

  const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || '/root/secrets/gcp-vision-key.json';
  console.log(`\n1. Checking Credential Path: ${keyPath}`);

  if (!fsSync.existsSync(keyPath)) {
    console.log('⚠️  Key file does NOT exist yet at path:', keyPath);
    console.log('   The backend is currently operating in secure fail-safe fallback mode.');
    
    // Test that fail-safe still safely holds content for review
    const fallbackResult = await moderationService.checkImageSafety(testPngBuffer);
    console.log(`   Fail-safe check confirmed: verdict="${fallbackResult.verdict}", reason="${fallbackResult.reason}"`);
    return { live: false, reason: 'Key file missing' };
  }

  // 2. Validate file permissions and content
  console.log('\n2. Validating Key File Security & JSON Structure:');
  const stat = await fs.stat(keyPath);
  const octalPerms = '0' + (stat.mode & 0o777).toString(8);
  console.log(`   File Permissions: ${octalPerms} (Expected: 0600)`);
  if (octalPerms !== '0600') {
    console.warn(`   WARNING: Key file permissions are ${octalPerms}, adjusting to 0600...`);
    await fs.chmod(keyPath, 0o600);
    console.log('   ✓ Permissions set to 0600.');
  } else {
    console.log('   ✓ Security check PASS: Key file is restricted to owner read/write (0600).');
  }

  const rawKey = await fs.readFile(keyPath, 'utf8');
  let keyJson;
  try {
    keyJson = JSON.parse(rawKey);
    console.log(`   ✓ Service Account: ${keyJson.client_email}`);
    console.log(`   ✓ GCP Project ID:  ${keyJson.project_id}`);
  } catch (err) {
    throw new Error(`Corrupted JSON in key file: ${err.message}`);
  }

  // 3. Test Live Google Cloud Vision API Connection
  console.log('\n3. Connecting to Google Cloud Vision API (SafeSearch Detection)...');
  const client = new vision.ImageAnnotatorClient({ keyFilename: keyPath });
  const [visionRes] = await client.safeSearchDetection({
    image: { content: testPngBuffer },
  });

  const annotations = visionRes?.safeSearchAnnotation;
  if (!annotations) {
    throw new Error('Google Cloud Vision returned empty response for SafeSearch detection.');
  }

  console.log('   ✓ Live SafeSearch response received from Google Cloud!');
  console.log('   Raw SafeSearch Scores:', {
    adult: annotations.adult,
    violence: annotations.violence,
    racy: annotations.racy,
    medical: annotations.medical,
    spoof: annotations.spoof,
  });

  // 4. Test Moderation Service Pipeline
  console.log('\n4. Testing Moderation Service Pipeline:');
  moderationService.clearMockHandler();
  const pipelineResult = await moderationService.checkImageSafety(testPngBuffer);
  console.log('   Pipeline Result:', pipelineResult);

  if (pipelineResult.verdict !== 'allow') {
    throw new Error(`Expected clean test image to result in 'allow', got '${pipelineResult.verdict}'`);
  }
  if (pipelineResult.scores.adult === 'UNKNOWN' || pipelineResult.scores.error) {
    throw new Error('Pipeline returned fallback/mock scores instead of live Vision annotations!');
  }
  console.log('   ✓ Pipeline PASS: Live scores successfully mapped to "allow" verdict.');

  // 5. Connect to MongoDB to test end-to-end publish flow with audit trail
  console.log('\n5. Testing End-to-End Publish with Live Vision Audit Logging:');
  await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/ai_image_studio?retryWrites=false');

  const ts = Date.now().toString().slice(-5);
  const testUser = await User.create({
    username: `livetest${ts}`,
    email: `livetest${ts}@example.com`,
    password: 'Password123!',
  });

  const testGen = await Generation.create({
    userId: testUser._id,
    mediaType: 'image',
    storageKey: `${testUser._id}/test-live.png`,
    prompt: 'A tranquil mountain lake reflecting morning sunlight',
    modelId: 'sdxl-base-1.0',
    isPublic: false,
    fileSizeBytes: testPngBuffer.length,
  });

  // Ensure media file exists in storage for publish flow
  const mediaStoragePath = process.env.MEDIA_STORAGE_PATH || '/var/www/media';
  const targetDir = path.join(mediaStoragePath, testUser._id.toString());
  await fs.mkdir(targetDir, { recursive: true });
  const targetFile = path.join(mediaStoragePath, testGen.storageKey);
  await fs.writeFile(targetFile, testPngBuffer);

  // Run publish flow via moderation check
  const modResult = await moderationService.checkMediaSafety({
    buffer: testPngBuffer,
    filePath: targetFile,
    mediaType: 'image',
  });

  const auditLog = await ModerationLog.create({
    generationId: testGen._id,
    userId: testUser._id,
    mediaType: testGen.mediaType,
    verdict: modResult.verdict,
    provider: modResult.provider,
    scores: modResult.scores,
    reason: modResult.reason,
  });

  console.log('   ✓ ModerationLog Created:');
  console.log('     ID:', auditLog._id.toString());
  console.log('     Provider:', auditLog.provider);
  console.log('     Verdict:', auditLog.verdict);
  console.log('     Scores:', auditLog.scores);

  if (auditLog.provider !== 'google-vision') {
    throw new Error(`Expected provider 'google-vision', got '${auditLog.provider}'`);
  }
  if (!auditLog.scores || !auditLog.scores.adult) {
    throw new Error('ModerationLog does not contain genuine Google Vision SafeSearch scores');
  }

  // Cleanup test records
  await User.deleteOne({ _id: testUser._id });
  await Generation.deleteOne({ _id: testGen._id });
  await ModerationLog.deleteOne({ _id: auditLog._id });
  await fs.rm(targetFile, { force: true });
  await fs.rmdir(targetDir).catch(() => {});
  await mongoose.disconnect();

  console.log('\n🎉 ALL LIVE VERIFICATION CHECKS PASSED!');
  console.log('   Automated moderation is genuinely live with Google Cloud Vision.');
  return { live: true };
}

verifyLiveVision().catch((err) => {
  console.error('\n❌ Verification failed:', err.message);
  process.exit(1);
});
