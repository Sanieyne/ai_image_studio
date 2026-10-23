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

  it('GET /api/v1/payments/plans returns Starter, Pro, and VIP plans', async () => {
    const res = await request(app).get('/api/v1/payments/plans');
    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);
    assert.ok(res.body.data.plans.starter);
    assert.equal(res.body.data.plans.starter.price, 4.99);
    assert.ok(res.body.data.plans.pro);
    assert.equal(res.body.data.plans.pro.price, 9.99);
    assert.ok(res.body.data.plans.vip);
    assert.equal(res.body.data.plans.vip.price, 19.99);
  });

  it('POST /api/v1/payments/gumroad-webhook activates Pro membership by user_id', async () => {
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
        permalink: 'cosmic-pro',
        license_key: 'GUM-PRO-12345',
        subscription_id: 'sub_pro_123',
        price: '999',
      });

    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);

    const updated = await User.findById(user._id);
    assert.equal(updated.subscriptionTier, 'pro');
    assert.equal(updated.subscriptionStatus, 'active');
    assert.equal(updated.gumroadLicenseKey, 'GUM-PRO-12345');
    assert.equal(updated.credits, 260); // 10 original + 250 pro bonus
  });

  it('POST /api/v1/payments/gumroad-webhook activates VIP membership and badge', async () => {
    const user = await User.create({
      username: 'vipuser',
      email: 'vip@example.com',
      password: 'password123',
      credits: 0,
    });

    const res = await request(app)
      .post('/api/v1/payments/gumroad-webhook')
      .type('form')
      .send({
        email: 'vip@example.com',
        product_name: 'Cosmic-Gen VIP Lifetime Access',
        permalink: 'cosmic-vip',
        license_key: 'GUM-VIP-999',
        price: '1999',
      });

    assert.equal(res.status, 200);
    const updated = await User.findById(user._id);
    assert.equal(updated.subscriptionTier, 'vip');
    assert.equal(updated.subscriptionStatus, 'active');
    assert.equal(updated.credits, 1000);
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
