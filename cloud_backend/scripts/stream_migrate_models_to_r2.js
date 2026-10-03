#!/usr/bin/env node
/**
 * Stream-Migrate HuggingFace Model Repositories Directly to Cloudflare R2
 * 
 * Pipes HTTP download streams directly into R2 multipart uploads via @aws-sdk/lib-storage.
 * Does NOT write files to local server disk (0 local disk usage).
 * Resumable: files already present in R2 with matching size are skipped.
 * 
 * Usage:
 *   node scripts/stream_migrate_models_to_r2.js [--only MODEL_ID] [--dry-run]
 */

import axios from 'axios';
import path from 'path';
import { env } from '../src/config/env.js';
import { modelStorageService } from '../src/services/modelStorage.service.js';

const MODELS = [
  { id: 'wan-2.2-animate-14b', repo: 'Wan-AI/Wan2.2-Animate-14B', gb: 60.5 },
  { id: 'wan-2.1-i2v-14b', repo: 'Wan-AI/Wan2.1-I2V-14B-480P-Diffusers', gb: 90.1 },
  { id: 'minimax-h3', repo: 'MiniMaxAI/MiniMax-H3', gb: 498.0 },
  // Available for streaming fallback on any other model:
  { id: 'flux-kontext-dev', repo: 'black-forest-labs/FLUX.1-Kontext-dev', gb: 33.8 },
  { id: 'qwen-image-2.1', repo: 'Qwen/Qwen-Image-2.1', gb: 33.1 },
  { id: 'z-image-turbo', repo: 'Tongyi-MAI/Z-Image-Turbo', gb: 32.9 },
  { id: 'wan-2.1-t2v-1.3b', repo: 'Wan-AI/Wan2.1-T2V-1.3B-Diffusers', gb: 28.9 },
  { id: 'chatterbox-tts', repo: 'ResembleAI/chatterbox', gb: 13.9 },
  { id: 'breeze-tts-2', repo: 'BreezeBlue/Breeze-TTS-2', gb: 7.7 },
  { id: 'sdxl-base-1.0', repo: 'stabilityai/stable-diffusion-xl-base-1.0', gb: 6.9 },
  { id: 'fashn-vton-1.5', repo: 'fashn-ai/fashn-vton-1.5', gb: 1.9 },
  { id: 'realesrgan-x4plus', repo: 'amd/realesrgan-x4plus', gb: 0.15 },
];

const ALWAYS_IGNORE_PATTERNS = [
  /\.(bin|onnx|pb|tflite|h5|ot|msgpack|ckpt|opus|flac|mp3|wav)$/i,
  /(^|\/)(onnx|openvino|onnx_data)\//i,
  /_onnx|_openvino|onnx_data/i,
  /\.DS_Store$/i,
  /(^|\/)\.(git|cache)\//i,
];

function shouldIgnoreFile(relPath) {
  for (const pat of ALWAYS_IGNORE_PATTERNS) {
    if (pat.test(relPath)) return true;
  }
  return false;
}

function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1000;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`;
}

function formatDuration(sec) {
  if (sec < 60) return `${Math.round(sec)}s`;
  if (sec < 3600) return `${(sec / 60).toFixed(1)}m`;
  return `${(sec / 3600).toFixed(2)}h`;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function fetchRepoSiblings(repo, hfToken) {
  const url = `https://huggingface.co/api/models/${repo}?blobs=true`;
  const headers = {
    'User-Agent': 'ai-image-studio-streamer/1.0',
    ...(hfToken ? { Authorization: `Bearer ${hfToken}` } : {}),
  };
  const res = await axios.get(url, { headers, timeout: 20000 });
  const siblings = res.data?.siblings || [];
  return siblings.filter((s) => s.rfilename && s.size !== undefined);
}

async function streamUploadFile(repo, relPath, expectedSize, modelId, hfToken, maxRetries = 5) {
  const downloadUrl = `https://huggingface.co/${repo}/resolve/main/${relPath}`;
  const reqHeaders = {
    'User-Agent': 'ai-image-studio-streamer/1.0',
    ...(hfToken ? { Authorization: `Bearer ${hfToken}` } : {}),
  };

  let attempt = 0;
  while (attempt < maxRetries) {
    attempt++;
    let streamRes = null;
    try {
      streamRes = await axios.get(downloadUrl, {
        responseType: 'stream',
        headers: reqHeaders,
        timeout: 30000,
        maxRedirects: 8,
      });

      const reportedLen = Number(streamRes.headers['content-length'] || expectedSize);
      const startTime = Date.now();
      let lastLogTime = Date.now();
      let lastLoaded = 0;

      await modelStorageService.uploadStream(
        streamRes.data,
        modelId,
        relPath,
        {
          contentLength: reportedLen,
          partSize: 50 * 1024 * 1024, // 50MB parts
          queueSize: 4,
          onProgress: (p) => {
            const now = Date.now();
            if (now - lastLogTime >= 8000) {
              const loaded = p.loaded || 0;
              const total = p.total || reportedLen;
              const pct = total > 0 ? ((loaded / total) * 100).toFixed(1) : '?';
              const deltaBytes = loaded - lastLoaded;
              const deltaSec = (now - lastLogTime) / 1000;
              const speedMB = deltaSec > 0 ? (deltaBytes / (1024 * 1024 * deltaSec)).toFixed(1) : '0';
              const elapsed = (now - startTime) / 1000;
              console.log(
                `    -> [${pct}%] ${formatBytes(loaded)} / ${formatBytes(total)} ` +
                `(${speedMB} MB/s, elapsed: ${formatDuration(elapsed)})`
              );
              lastLogTime = now;
              lastLoaded = loaded;
            }
          },
        }
      );

      // Verify final object in R2
      const verified = await modelStorageService.getModelFileInfo(modelId, relPath);
      if (!verified.exists) {
        throw new Error(`R2 HeadObject returned not found after upload for ${relPath}`);
      }
      if (verified.size !== reportedLen && reportedLen > 0) {
        throw new Error(
          `R2 size mismatch for ${relPath}: expected ${reportedLen} bytes, got ${verified.size} bytes`
        );
      }

      const totalElapsed = (Date.now() - startTime) / 1000;
      const avgSpeed = totalElapsed > 0 ? (reportedLen / (1024 * 1024 * totalElapsed)).toFixed(1) : '0';
      return { success: true, size: verified.size, duration: totalElapsed, avgSpeed };
    } catch (err) {
      if (streamRes?.data?.destroy) {
        try { streamRes.data.destroy(); } catch (_) {}
      }
      console.warn(`    [!] Attempt ${attempt}/${maxRetries} failed for ${relPath}: ${err.message}`);
      if (attempt >= maxRetries) {
        throw err;
      }
      const backoffMs = Math.min(1000 * Math.pow(2, attempt), 30000);
      console.log(`    [*] Retrying in ${backoffMs / 1000}s...`);
      await sleep(backoffMs);
    }
  }
}

async function migrateModel(model, hfToken, dryRun = false) {
  console.log(`\n======================================================================`);
  console.log(`>>> Starting Stream Migration for: ${model.id} (${model.repo})`);
  console.log(`======================================================================`);

  const t0 = Date.now();
  console.log(`[*] Fetching repo metadata from HuggingFace...`);
  const rawSiblings = await fetchRepoSiblings(model.repo, hfToken);
  console.log(`[*] Found ${rawSiblings.length} total files in HF repo.`);

  // Filter out non-production files
  const productionFiles = [];
  let ignoredCount = 0;
  let ignoredBytes = 0;

  for (const s of rawSiblings) {
    if (shouldIgnoreFile(s.rfilename)) {
      ignoredCount++;
      ignoredBytes += s.size;
    } else {
      productionFiles.push(s);
    }
  }

  const totalBytes = productionFiles.reduce((acc, f) => acc + f.size, 0);
  console.log(
    `[*] Filtered: ${ignoredCount} ignored files (${formatBytes(ignoredBytes)}), ` +
    `${productionFiles.length} production files to migrate (${formatBytes(totalBytes)} total).`
  );

  if (dryRun) {
    console.log(`[Dry Run] Would migrate ${productionFiles.length} files (${formatBytes(totalBytes)}).`);
    return;
  }

  let uploadedCount = 0;
  let skippedCount = 0;
  let uploadedBytes = 0;
  let skippedBytes = 0;

  for (let i = 0; i < productionFiles.length; i++) {
    const file = productionFiles[i];
    const relPath = file.rfilename;
    const expectedSize = file.size;

    console.log(
      `\n[${i + 1}/${productionFiles.length}] ${relPath} (${formatBytes(expectedSize)})`
    );

    // Check if already present in R2
    try {
      const existing = await modelStorageService.getModelFileInfo(model.id, relPath);
      if (existing.exists && existing.size === expectedSize) {
        console.log(`   [SKIP] Already verified in R2 (${formatBytes(existing.size)}).`);
        skippedCount++;
        skippedBytes += existing.size;
        continue;
      }
    } catch (_) {}

    // Stream upload directly from HF to R2
    const result = await streamUploadFile(model.repo, relPath, expectedSize, model.id, hfToken);
    uploadedCount++;
    uploadedBytes += result.size;
    console.log(
      `   [OK] Uploaded & verified: ${formatBytes(result.size)} in ${formatDuration(result.duration)} ` +
      `(${result.avgSpeed} MB/s avg).`
    );
  }

  const totalDuration = (Date.now() - t0) / 1000;
  console.log(`\n======================================================================`);
  console.log(`[DONE] Model ${model.id} migration complete!`);
  console.log(`- Uploaded: ${uploadedCount} files (${formatBytes(uploadedBytes)})`);
  console.log(`- Skipped: ${skippedCount} files (${formatBytes(skippedBytes)})`);
  console.log(`- Total Time: ${formatDuration(totalDuration)}`);
  console.log(`- Storage Destination: R2 models/${model.id}/`);
  console.log(`======================================================================\n`);
}

async function main() {
  const args = process.argv.slice(2);
  let onlyModelId = null;
  let dryRun = false;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--only' && args[i + 1]) {
      onlyModelId = args[i + 1];
      i++;
    } else if (args[i] === '--dry-run') {
      dryRun = true;
    }
  }

  const hfToken = process.env.HF_TOKEN || null;

  if (!modelStorageService.isConfigured) {
    console.error('Fatal: R2 credentials missing in environment.');
    process.exit(1);
  }

  const targets = onlyModelId
    ? MODELS.filter((m) => m.id === onlyModelId)
    : MODELS.filter((m) => ['wan-2.2-animate-14b', 'wan-2.1-i2v-14b', 'minimax-h3'].includes(m.id));

  if (targets.length === 0) {
    console.error(`Model ID '${onlyModelId}' not found in streaming catalog.`);
    console.log(`Available models: ${MODELS.map((m) => m.id).join(', ')}`);
    process.exit(1);
  }

  console.log(`=== AI Image Studio Direct Stream-to-R2 Uploader ===`);
  console.log(`Bucket: ${modelStorageService.bucket}`);
  console.log(`Target Models: ${targets.map((m) => m.id).join(', ')}`);

  for (const model of targets) {
    await migrateModel(model, hfToken, dryRun);
  }

  console.log(`\nAll target models processed successfully!`);
}

main().catch((err) => {
  console.error('\n[FATAL] Migration error:', err);
  process.exit(1);
});
