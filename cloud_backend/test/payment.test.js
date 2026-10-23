import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { User } from '../src/models/User.js';
import { startTestDb } from './helpers/db.js';

describe('Payment & Gumroad Webhooks', () => {
  let app;
  let db;

  before(async () => {
    db = await startTestDb();
    app = createApp();
  });

  after(async () => {
    if (db) await db.stop();
  });

  beforeEach(async () => {
    if (db) await db.clear();
  });

  it('GET /api/v1/payments/plans returns Pro plan ($4.99 / 100 credits)', async () => {
    const res = await request(app).get('/api/v1/payments/plans');
    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);
    assert.ok(res.body.data.plans.pro);
    assert.equal(res.body.data.plans.pro.price, 4.99);
    assert.equal(res.body.data.plans.pro.monthlyCredits, 100);
  });

  it('POST /api/v1/payments/gumroad-webhook activates Pro membership by user_id and grants 100 credits', async () => {
    const user = await User.create({
      username: 'cosmicuser',
      email: 'cosmic@example.com',
      password: 'password123',
      credits: 10,
    });

    const res = await request(app)
      .post('/api/v1/payments/gumroad-webhook')
      .type('form')
      .send({
        email: 'buyer@example.com',
        user_id: user._id.toString(),
        product_name: 'Cosmic-Gen Pro Member',
        permalink: 'pro',
        license_key: 'GUM-PRO-12345',
        subscription_id: 'sub_pro_123',
        price: '499',
      });

    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);

    const updated = await User.findById(user._id);
    assert.equal(updated.subscriptionTier, 'pro');
    assert.equal(updated.subscriptionStatus, 'active');
    assert.equal(updated.gumroadLicenseKey, 'GUM-PRO-12345');
    assert.equal(updated.credits, 110); // 10 original + 100 pro bonus
  });

  it('POST /api/v1/payments/gumroad-webhook downgrades on refund or cancellation', async () => {
    const user = await User.create({
      username: 'canceller',
      email: 'cancel@example.com',
      password: 'password123',
      subscriptionTier: 'pro',
      subscriptionStatus: 'active',
    });

    const res = await request(app)
      .post('/api/v1/payments/gumroad-webhook')
      .type('form')
      .send({
        email: 'cancel@example.com',
        refunded: 'true',
      });

    assert.equal(res.status, 200);
    const updated = await User.findById(user._id);
    assert.equal(updated.subscriptionTier, 'free');
    assert.equal(updated.subscriptionStatus, 'cancelled');
  });
});
