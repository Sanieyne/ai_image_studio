#!/usr/bin/env node
/**
 * cleanup_gallery_preview.mjs
 * 
 * Removes all seed data created by seed_gallery_preview.mjs:
 *  - All Generation records owned by the _gallery_seed user
 *  - All Like/Report records referencing those generations
 *  - The _gallery_seed user account
 *  - The media files on disk
 */

import mongoose from 'mongoose';
import fs from 'fs';
import path from 'path';

const MONGO_URI = 'mongodb://localhost:27017/ai_image_studio?retryWrites=false';
const MEDIA_ROOT = '/var/www/media';
const SEED_USERNAME = '_gallery_seed';

async function main() {
  console.log('🧹 Gallery Seed Cleanup — Cosmic-Gen AI');
  console.log('─'.repeat(50));

  await mongoose.connect(MONGO_URI);
  console.log('✅ Connected to MongoDB');

  const db = mongoose.connection.db;
  const usersCol = db.collection('users');
  const gensCol = db.collection('generations');
  const likesCol = db.collection('likes');
  const reportsCol = db.collection('reports');

  const seedUser = await usersCol.findOne({ username: SEED_USERNAME });
  if (!seedUser) {
    console.log('ℹ️  No seed user found — nothing to clean up.');
    await mongoose.disconnect();
    return;
  }

  const seedUserId = seedUser._id;

  // Get generation IDs for cascading cleanup
  const seedGens = await gensCol.find({ userId: seedUserId }, { projection: { _id: 1 } }).toArray();
  const genIds = seedGens.map(g => g._id);

  // Delete likes and reports for seed generations
  if (genIds.length > 0) {
    const likesResult = await likesCol.deleteMany({ generationId: { $in: genIds } });
    console.log(`🗑️  Deleted ${likesResult.deletedCount} likes`);

    const reportsResult = await reportsCol.deleteMany({ generationId: { $in: genIds } });
    console.log(`🗑️  Deleted ${reportsResult.deletedCount} reports`);
  }

  // Delete generations
  const gensResult = await gensCol.deleteMany({ userId: seedUserId });
  console.log(`🗑️  Deleted ${gensResult.deletedCount} seed generations`);

  // Delete user
  await usersCol.deleteOne({ _id: seedUserId });
  console.log(`🗑️  Deleted seed user "${SEED_USERNAME}"`);

  // Delete media files
  const mediaDir = path.join(MEDIA_ROOT, seedUserId.toString());
  if (fs.existsSync(mediaDir)) {
    fs.rmSync(mediaDir, { recursive: true, force: true });
    console.log(`🗑️  Removed media directory: ${mediaDir}`);
  }

  console.log('');
  console.log('✅ Cleanup complete — all seed data removed.');

  await mongoose.disconnect();
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
