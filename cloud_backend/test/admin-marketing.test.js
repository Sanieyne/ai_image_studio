import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { startTestDb } from './helpers/db.js';
import { authService } from '../src/services/auth.service.js';
import { User } from '../src/models/User.js';
import { MarketingCampaign } from '../src/models/MarketingCampaign.js';

describe('Admin Marketing API', () => {
  let db;
  let app;
  let adminToken;
  let userToken;
  let adminUser;

  before(async () => {
    db = await startTestDb();
    await User.init();
    await MarketingCampaign.init();
    app = createApp();

    // Register admin user
    const adminReg = await authService.register({
      username: 'adminuser',
      email: 'admin@cosmic-gen.com',
      password: 'StrongPassword123!',
    });
    adminUser = await User.findById(adminReg.user.id);
    adminUser.role = 'admin';
    adminUser.isEmailVerified = true;
    await adminUser.save();

    const adminLogin = await authService.login({
      email: 'admin@cosmic-gen.com',
      password: 'StrongPassword123!',
    });
    adminToken = adminLogin.accessToken;

    // Register normal user
    const userReg = await authService.register({
      username: 'normaluser',
      email: 'user@example.com',
      password: 'StrongPassword123!',
    });
    userToken = userReg.accessToken;
  });

  after(async () => {
    await db.stop();
  });

  it('rejects unauthenticated requests to marketing endpoints', async () => {
    const res = await request(app).get('/api/v1/admin/marketing/stats');
    assert.equal(res.status, 401);
  });

  it('rejects non-admin users from marketing endpoints', async () => {
    const res = await request(app)
      .get('/api/v1/admin/marketing/stats')
      .set('Authorization', `Bearer ${userToken}`);
    assert.equal(res.status, 403);
  });

  it('allows admin to fetch marketing stats and audience counts', async () => {
    const res = await request(app)
      .get('/api/v1/admin/marketing/stats')
      .set('Authorization', `Bearer ${adminToken}`);
    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);
    assert.ok(typeof res.body.data.totalUsers === 'number');
    assert.ok(typeof res.body.data.verifiedUsers === 'number');
    assert.equal(res.body.data.smtp.sender, 'marketing@cosmic-gen.com');
  });

  it('allows admin to fetch presets and media library', async () => {
    const res = await request(app)
      .get('/api/v1/admin/marketing/presets')
      .set('Authorization', `Bearer ${adminToken}`);
    assert.equal(res.status, 200);
    assert.ok(res.body.data.presets.digest);
    assert.ok(res.body.data.presets.video);
    assert.ok(res.body.data.presets.image);
    assert.ok(res.body.data.presets.audio);
    assert.ok(Array.isArray(res.body.data.mediaLibrary));
  });

  it('renders marketing preview HTML', async () => {
    const res = await request(app)
      .post('/api/v1/admin/marketing/preview')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({
        type: 'digest',
        options: {
          headline: 'Live Preview Test',
          subtitle: 'Testing preview rendering',
        },
      });
    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);
    assert.ok(res.body.data.html.includes('Live Preview Test'));
    assert.ok(res.body.data.html.includes('COSMIC'));
  });

  it('rejects test dispatch if subject contains emojis (antispam protection)', async () => {
    const res = await request(app)
      .post('/api/v1/admin/marketing/send-test')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({
        testEmail: 'test@example.com',
        type: 'digest',
        subject: '🚀 Hello World with Emoji',
      });
    assert.equal(res.status, 400);
    assert.ok(res.body.message.includes('emojis'));
  });

  it('fetches marketing campaign history', async () => {
    await MarketingCampaign.create({
      subject: 'Past Campaign Test',
      type: 'digest',
      recipientCount: 5,
      status: 'sent',
      sentBy: adminUser._id,
      sentByEmail: adminUser.email,
    });

    const res = await request(app)
      .get('/api/v1/admin/marketing/history')
      .set('Authorization', `Bearer ${adminToken}`);
    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);
    assert.ok(res.body.data.campaigns.length >= 1);
    assert.equal(res.body.data.campaigns[0].subject, 'Past Campaign Test');
  });
});
