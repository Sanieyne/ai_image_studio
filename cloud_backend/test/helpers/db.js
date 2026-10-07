/**
 * In-memory MongoDB for tests. Never connects to anything else.
 *
 *   const db = await startTestDb();          // plain server
 *   const db = await startTestDb({ replSet: true }); // when transactions are used
 *   ...
 *   await db.stop();
 */

import mongoose from 'mongoose';
import { MongoMemoryServer, MongoMemoryReplSet } from 'mongodb-memory-server';

const PRODUCTION_PORT = 27017;

export async function startTestDb({ replSet = false } = {}) {
  const server = replSet
    ? await MongoMemoryReplSet.create({ replSet: { count: 1, storageEngine: 'wiredTiger' } })
    : await MongoMemoryServer.create();
  const uri = server.getUri();

  // Guard against ever reaching the real database on this machine.
  const ports = [...uri.matchAll(/:(\d+)/g)].map((m) => Number(m[1]));
  if (ports.includes(PRODUCTION_PORT)) {
    await server.stop();
    throw new Error(`Refusing to use test database on port ${PRODUCTION_PORT}: ${uri}`);
  }

  await mongoose.connect(uri, { dbName: 'test' });

  return {
    uri,
    async clear() {
      const collections = await mongoose.connection.db.collections();
      await Promise.all(collections.map((c) => c.deleteMany({})));
    },
    async stop() {
      await mongoose.disconnect();
      await server.stop();
    },
  };
}
