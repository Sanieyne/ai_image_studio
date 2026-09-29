#!/usr/bin/env node
/**
 * seed_gallery_preview.mjs
 * 
 * Creates ~25 placeholder Generation records owned by a dedicated
 * "_gallery_seed" user for visually reviewing the gallery layout with
 * real placeholder images from Picsum and realistic varied aspect ratios.
 * 
 * CLEANUP: node scripts/cleanup_gallery_preview.mjs
 *    — or — db.generations.deleteMany({ userId: <seedUserId> })
 *           db.users.deleteOne({ username: "_gallery_seed" })
 *           rm -rf /var/www/media/<seedUserId>/
 * 
 * Idempotent: refuses to run if seed records already exist.
 */

import mongoose from 'mongoose';
import { createCanvas } from 'canvas';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import bcrypt from 'bcryptjs';

// ── Config ──────────────────────────────────────────────────────────────────
const MONGO_URI = 'mongodb://localhost:27017/ai_image_studio?retryWrites=false';
const MEDIA_ROOT = '/var/www/media';
const SEED_USERNAME = '_gallery_seed';
const SEED_EMAIL = 'seed-preview@cosmic-gen.internal';
const SEED_PASSWORD = crypto.randomBytes(32).toString('hex'); // random, unused

// ── Prompts, aspect ratios, and metadata for realistic masonry cards ────────
const SEED_ITEMS = [
  // 1. Portrait 3:4 (Cyberpunk / Urban) - FLUX.1 Kontext [dev] (Longer name test)
  { prompt: 'A futuristic neon cityscape at midnight with flying vehicles', model: 'flux-1-kontext', type: 'image', width: 600, height: 800, seed: 'cyber-city-1', likes: 47, views: 312 },
  // 2. Tall Portrait 9:16 (Character art) - Qwen-Image 2.1
  { prompt: 'Portrait of a cyberpunk samurai in a rain-soaked alley', model: 'qwen-image', type: 'image', width: 540, height: 960, seed: 'samurai-2', likes: 128, views: 890 },
  // 3. Landscape 16:9 (Nature scenery) - SDXL Base 1.0
  { prompt: 'Serene Japanese garden with cherry blossoms and koi pond', model: 'sdxl-base', type: 'image', width: 960, height: 540, seed: 'garden-3', likes: 63, views: 445 },
  // 4. Square 1:1 (Abstract) - Z-Image Turbo
  { prompt: 'Abstract fluid art in electric blue and magenta', model: 'z-image-turbo', type: 'image', width: 700, height: 700, seed: 'fluid-4', likes: 0, views: 12 },
  // 5. Tall Portrait 2:3 (Fantasy character) - FLUX.1 Kontext [dev]
  { prompt: 'Steampunk clockwork dragon breathing golden fire', model: 'flux-1-kontext', type: 'image', width: 600, height: 900, seed: 'dragon-5', likes: 215, views: 1540 },
  // 6. Landscape 4:3 (Fashion / Garment transfer) - FASHN VTON 1.5
  { prompt: 'High-fashion editorial model wearing emerald velvet tailored blazer', model: 'fashn-vton-1-5', type: 'image', width: 800, height: 600, seed: 'vton-6', likes: 31, views: 178 },
  // 7. Portrait 3:4 (4K Upscaling test) - Real-ESRGAN 4x+
  { prompt: 'Ultra-detailed macro portrait with restored fine skin textures', model: 'real-esrgan-4x', type: 'image', width: 600, height: 800, seed: 'upscale-7', likes: 89, views: 623 },
  // 8. Landscape 16:9 (Fine art) - SDXL Base 1.0
  { prompt: 'Oil painting of a thunderstorm over lavender fields', model: 'sdxl-base', type: 'image', width: 960, height: 540, seed: 'storm-8', likes: 17, views: 95 },
  // 9. Square 1:1 (Macro) - Qwen-Image 2.1
  { prompt: 'Macro photo of dewdrops on a spiderweb at sunrise', model: 'qwen-image', type: 'image', width: 720, height: 720, seed: 'macro-9', likes: 42, views: 267 },
  // 10. Portrait 4:5 (Vintage poster) - Z-Image Turbo
  { prompt: 'Art deco poster of a 1920s jazz club with brass instruments', model: 'z-image-turbo', type: 'image', width: 640, height: 800, seed: 'jazz-10', likes: 5, views: 34 },
  // 11. Landscape 16:9 (Space) - Real-ESRGAN 4x+
  { prompt: 'Volcanic eruption viewed from space with high-frequency details', model: 'real-esrgan-4x', type: 'image', width: 960, height: 540, seed: 'volcano-11', likes: 156, views: 1100 },
  // 12. Tall Portrait 9:16 (Fantasy landscape) - FASHN VTON 1.5
  { prompt: 'Haute couture model in iridescent silk gown against glowing forest', model: 'fashn-vton-1-5', type: 'image', width: 540, height: 960, seed: 'forest-12', likes: 73, views: 510 },
  // 13. Landscape 4:3 (Mecha) - FLUX.1 Kontext [dev]
  { prompt: 'Giant robot walking through a sunflower field at sunset', model: 'flux-1-kontext', type: 'image', width: 800, height: 600, seed: 'robot-13', likes: 0, views: 3 },
  // 14. Square 1:1 (Pixel art) - SDXL Base 1.0
  { prompt: 'Isometric pixel art of a cozy coffee shop interior', model: 'sdxl-base', type: 'image', width: 680, height: 680, seed: 'coffee-14', likes: 28, views: 190 },
  // 15. Portrait 3:4 (Concept art) - Qwen-Image 2.1
  { prompt: 'Double exposure portrait merging face with mountain range', model: 'qwen-image', type: 'image', width: 600, height: 800, seed: 'portrait-15', likes: 94, views: 670 },
  // 16. Landscape 16:9 (Still life) - Real-ESRGAN 4x+
  { prompt: 'Baroque still life with fruit, flowers, and crystal-clear golden light', model: 'real-esrgan-4x', type: 'image', width: 960, height: 540, seed: 'baroque-16', likes: 11, views: 58 },
  // 17. Tall Portrait 2:3 (Cyberpunk street) - FLUX.1 Kontext [dev]
  { prompt: 'Cyberpunk street market in Tokyo 2099 with holographic signage', model: 'flux-1-kontext', type: 'image', width: 600, height: 900, seed: 'tokyo-17', likes: 201, views: 1420 },
  // 18. Landscape 16:9 (Aerial nature) - SDXL Base 1.0
  { prompt: 'Aerial view of turquoise river winding through red canyon', model: 'sdxl-base', type: 'image', width: 960, height: 540, seed: 'canyon-18', likes: 36, views: 245 },
  // 19. Portrait 4:5 (Dreamy landscape) - Z-Image Turbo
  { prompt: 'Dreamy pastel clouds with floating islands and castles', model: 'z-image-turbo', type: 'image', width: 640, height: 800, seed: 'castles-19', likes: 0, views: 7 },
  // 20. Square 1:1 (Surreal) - FASHN VTON 1.5
  { prompt: 'Hyperrealistic eye reflecting a galaxy with metallic garment accents', model: 'fashn-vton-1-5', type: 'image', width: 750, height: 750, seed: 'galaxy-20', likes: 182, views: 1300 },
  // Video entries - Testing video model matrix
  { prompt: 'Timelapse of aurora borealis over snowy mountains', model: 'wan-2-1-t2v', type: 'video', width: 960, height: 540, seed: 'aurora-video', likes: 67, views: 480 },
  { prompt: 'Slow-motion waves crashing on volcanic black sand beach', model: 'wan-2-1-i2v', type: 'video', width: 540, height: 960, seed: 'beach-video', likes: 24, views: 155 },
  { prompt: 'Walking through a bioluminescent cave, POV cinematic', model: 'wan-2-2-animate', type: 'video', width: 720, height: 720, seed: 'cave-video', likes: 0, views: 20 },
  { prompt: 'Synchronized orchestral audiovisual spectacle with particle lasers', model: 'minimax-h3', type: 'video', width: 960, height: 540, seed: 'minimax-audiovisual', likes: 98, views: 640 },
  // Audio entries - Testing voice and audio models
  { prompt: 'Ambient lo-fi beat with rain sounds and soft piano narration', model: 'chatterbox-tts', type: 'audio', width: 800, height: 600, seed: 'lofi-audio', likes: 15, views: 88 },
  { prompt: 'Epic expressive dialogue and cinematic narration with heavy drums', model: 'breeze-tts-2', type: 'audio', width: 800, height: 600, seed: 'epic-audio', likes: 3, views: 19 },
];

// ── Color palettes for fallback gradient images ─────────────────────────────
const PALETTES = [
  ['#f04438', '#ff6b5a', '#1a1a2e'],
  ['#0f3460', '#16213e', '#e94560'],
  ['#6c5ce7', '#a29bfe', '#0d0d0d'],
  ['#00b894', '#00cec9', '#2d3436'],
  ['#fdcb6e', '#e17055', '#2d3436'],
  ['#0984e3', '#74b9ff', '#0d111d'],
  ['#e84393', '#fd79a8', '#2d3436'],
];

// ── Generate a fallback gradient image as PNG buffer ────────────────────────
function generateGradientImage(width, height, colors, label) {
  const canvas = createCanvas(width, height);
  const ctx = canvas.getContext('2d');

  const grad = ctx.createLinearGradient(0, 0, width, height);
  grad.addColorStop(0, colors[0]);
  grad.addColorStop(0.5, colors[1]);
  grad.addColorStop(1, colors[2]);
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, width, height);

  ctx.fillStyle = 'rgba(255,255,255,0.85)';
  ctx.font = 'bold 20px sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(label.slice(0, 30), width / 2, height / 2);

  return canvas.toBuffer('image/png');
}

// ── Main ────────────────────────────────────────────────────────────────────
async function main() {
  console.log('🌱 Gallery Seed Script (Real Picsum Photos & Masonry) — Cosmic-Gen AI');
  console.log('─'.repeat(65));

  await mongoose.connect(MONGO_URI);
  console.log('✅ Connected to MongoDB');

  const db = mongoose.connection.db;
  const usersCol = db.collection('users');
  const gensCol = db.collection('generations');

  // ── Idempotency check ──
  const existingSeed = await usersCol.findOne({ username: SEED_USERNAME });
  if (existingSeed) {
    const existingCount = await gensCol.countDocuments({ userId: existingSeed._id });
    if (existingCount > 0) {
      console.error(`\n❌ ABORT: Seed data already exists (${existingCount} records for user "${SEED_USERNAME}").`);
      console.error('   Run "node scripts/cleanup_gallery_preview.mjs" first to remove existing seed data.\n');
      await mongoose.disconnect();
      process.exit(1);
    }
  }

  // ── Create or reuse seed user ──
  const hashedPassword = await bcrypt.hash(SEED_PASSWORD, 12);
  let seedUserId;
  if (existingSeed) {
    seedUserId = existingSeed._id;
  } else {
    const seedUser = await usersCol.insertOne({
      username: SEED_USERNAME,
      email: SEED_EMAIL,
      password: hashedPassword,
      role: 'user',
      credits: 0,
      totalCreditsPurchased: 0,
      totalCreditsUsed: 0,
      isActive: true,
      isEmailVerified: false,
      storageQuotaGB: 100,
      storageUsedGB: 0,
      selectedModels: ['flux-dev'],
      displayName: '🎨 Preview Content',
      avatarUrl: null,
      bio: '⚠️ Temporary placeholder account for gallery layout preview. Not a real user.',
      isPublicProfile: true,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    seedUserId = seedUser.insertedId;
  }
  
  console.log(`✅ Seed user: "${SEED_USERNAME}" (${seedUserId})`);

  // ── Create media directory ──
  const mediaDir = path.join(MEDIA_ROOT, seedUserId.toString());
  fs.mkdirSync(mediaDir, { recursive: true });

  // ── Download photos & generate records ──
  console.log('\n📥 Downloading real placeholder photos from Picsum...');
  const records = [];
  const now = new Date();

  for (let i = 0; i < SEED_ITEMS.length; i++) {
    const item = SEED_ITEMS[i];
    const uuid = crypto.randomUUID();
    const ext = item.type === 'video' ? 'mp4' : item.type === 'audio' ? 'mp3' : 'jpg';
    const storageKey = `${seedUserId}/${uuid}.${ext}`;
    const filePath = path.join(MEDIA_ROOT, storageKey);

    let fileSize = 1024;

    if (item.type === 'image') {
      const picsumUrl = `https://picsum.photos/seed/${item.seed}/${item.width}/${item.height}`;
      let buf;
      try {
        process.stdout.write(`  [${(i + 1).toString().padStart(2, ' ')}/${SEED_ITEMS.length}] Fetching ${item.width}x${item.height} (${item.seed})... `);
        const res = await fetch(picsumUrl, { signal: AbortSignal.timeout(10000) });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        buf = Buffer.from(await res.arrayBuffer());
        process.stdout.write(`✅ (${(buf.length / 1024).toFixed(1)} KB)\n`);
      } catch (err) {
        process.stdout.write(`⚠️ (${err.message}, fallback to canvas)\n`);
        const palette = PALETTES[i % PALETTES.length];
        buf = generateGradientImage(item.width, item.height, palette, item.prompt);
      }
      fs.writeFileSync(filePath, buf);
      fileSize = buf.length;
    } else {
      // Small dummy payload for video/audio preview
      fs.writeFileSync(filePath, Buffer.alloc(1024, 0));
    }

    // Stagger publishedAt over the last 14 days for realistic "recent" sorting
    const daysAgo = Math.floor((i / SEED_ITEMS.length) * 14);
    const hoursAgo = Math.floor(Math.random() * 24);
    const publishDate = new Date(now - (daysAgo * 86400000) - (hoursAgo * 3600000));

    records.push({
      userId: seedUserId,
      mediaType: item.type,
      storageKey,
      prompt: item.prompt,
      negativePrompt: '',
      modelId: item.model,
      settings: {
        width: item.width,
        height: item.height,
        aspectRatio: `${item.width}:${item.height}`,
        steps: 30,
        cfg: 7.5,
      },
      fileSizeBytes: fileSize,
      isPublic: true,
      moderationStatus: 'approved',
      publishedAt: publishDate,
      likesCount: item.likes,
      viewsCount: item.views,
      reportsCount: 0,
      createdAt: publishDate,
      updatedAt: publishDate,
    });
  }

  const result = await gensCol.insertMany(records);
  console.log(`\n✅ Inserted ${result.insertedCount} seed generations with masonry proportions!`);
  console.log(`   Media directory: ${mediaDir}/`);
  console.log('');
  console.log('📊 Aspect Ratio Breakdown:');
  console.log(`   - Portrait (3:4, 2:3, 9:16, 4:5): ${SEED_ITEMS.filter(i => i.type === 'image' && i.height > i.width).length}`);
  console.log(`   - Landscape (16:9, 4:3):          ${SEED_ITEMS.filter(i => i.type === 'image' && i.width > i.height).length}`);
  console.log(`   - Square (1:1):                   ${SEED_ITEMS.filter(i => i.type === 'image' && i.width === i.height).length}`);
  console.log(`   - Videos (varied):                ${SEED_ITEMS.filter(i => i.type === 'video').length}`);
  console.log(`   - Audio (4:3 cards):              ${SEED_ITEMS.filter(i => i.type === 'audio').length}`);
  console.log('');
  console.log('🔗 Review live at: https://cosmic-gen.com/gallery');
  console.log('');
  console.log('🧹 To clean up later:');
  console.log('   node scripts/cleanup_gallery_preview.mjs');
  console.log('');

  await mongoose.disconnect();
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
