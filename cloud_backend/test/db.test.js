import { test } from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import { startTestDb } from './helpers/db.js';

test('test database is an in-memory server, never the local production port', async () => {
  const db = await startTestDb();
  try {
    assert.doesNotMatch(db.uri, /:27017\b/);
    await mongoose.connection.db.collection('smoke').insertOne({ ok: 1 });
    assert.equal(await mongoose.connection.db.collection('smoke').countDocuments(), 1);
  } finally {
    await db.stop();
  }
});
