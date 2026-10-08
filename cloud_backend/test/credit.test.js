import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { startTestDb } from './helpers/db.js';
import { makeUser } from './helpers/factories.js';
import { creditService } from '../src/services/credit.service.js';
import { User } from '../src/models/User.js';
import { Transaction } from '../src/models/Transaction.js';

// deductCredits uses no transactions; addCredits does when a replica set is
// available. Run the same checks against both deployment shapes.
for (const replSet of [false, true]) {
  describe(`credits (${replSet ? 'replica set, transactions available' : 'standalone, no transactions'})`, () => {
    let db;
    before(async () => { db = await startTestDb({ replSet }); });
    after(async () => { await db.stop(); });
    beforeEach(async () => { await db.clear(); });

    test('concurrent exact deductions never overdraw', async () => {
      const user = await makeUser(10);
      const results = await Promise.allSettled(
        Array.from({ length: 40 }, () => creditService.deductCredits(user._id, 1, 'test'))
      );
      const ok = results.filter((r) => r.status === 'fulfilled');
      const refused = results.filter((r) => r.status === 'rejected');
      assert.equal(ok.length, 10);
      assert.ok(refused.every((r) => r.reason.statusCode === 402));
      const fresh = await User.findById(user._id).lean();
      assert.equal(fresh.credits, 0);
      assert.equal(fresh.totalCreditsUsed, 10);
      assert.equal(await Transaction.countDocuments({ user: user._id }), 10);
    });

    test('concurrent "up to" deductions charge exactly the balance and stop at zero', async () => {
      const user = await makeUser(5);
      const results = await Promise.all(
        Array.from({ length: 20 }, () =>
          creditService.deductCredits(user._id, 0.75, 'test', {}, null, { upTo: true })
        )
      );
      const total = results.reduce((sum, r) => sum + r.charged, 0);
      assert.ok(Math.abs(total - 5) < 1e-9, `charged ${total}`);
      const fresh = await User.findById(user._id).lean();
      assert.equal(fresh.credits, 0);
      // One ledger entry per non-zero charge, none for zero.
      assert.equal(await Transaction.countDocuments({ user: user._id }), results.filter((r) => r.charged > 0).length);
    });

    test('"up to" returns the partial amount when the balance is short', async () => {
      const user = await makeUser(0.3);
      const r = await creditService.deductCredits(user._id, 1, 'test', {}, null, { upTo: true });
      assert.equal(r.charged, 0.3);
      assert.equal((await User.findById(user._id).lean()).credits, 0);
      const zero = await creditService.deductCredits(user._id, 1, 'test', {}, null, { upTo: true });
      assert.equal(zero.charged, 0);
      assert.equal(zero.transaction, null);
    });

    test('deductions and refunds interleave without losing updates', async () => {
      const user = await makeUser(50);
      await Promise.all([
        ...Array.from({ length: 20 }, () => creditService.deductCredits(user._id, 1, 'test')),
        ...Array.from({ length: 10 }, () => creditService.addCredits(user._id, 2, 'refund', 'test')),
      ]);
      assert.equal((await User.findById(user._id).lean()).credits, 50);
    });
  });
}
