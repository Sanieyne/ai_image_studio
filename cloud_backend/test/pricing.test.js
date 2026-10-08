import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { pricingService, VAST_HOURS_PER_MONTH } from '../src/services/pricing.service.js';

const fixtures = JSON.parse(fs.readFileSync(new URL('./fixtures/vast_offers.json', import.meta.url))).offers;
const offer = (name) => fixtures.find((o) => o.gpu_name === name);

// The defaults in PricingConfig: 25 % markup, 50 credits per USD -> 1 USD = 62.5 credits.
const DEFAULT = { markupPercentage: 25, creditsPerUsd: 50 };
const close = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) < eps, `${a} != ${b}`);

describe('Vast.ai units (real offers)', () => {
  test('storage_cost is $/GB/month over a 720-hour month', () => {
    // Searched with allocated_storage = 50 and 100:
    //   dph_total - dph_base = storage_cost x GB / 720
    for (const o of fixtures) {
      close(o.dph_total - o.dph_base, (o.storage_cost * 50) / VAST_HOURS_PER_MONTH, 1e-9);
      close(o._dph_total_at_100GB - o.dph_base, (o.storage_cost * 100) / VAST_HOURS_PER_MONTH, 1e-9);
      close(o.storage_total_cost, (o.storage_cost * 50) / VAST_HOURS_PER_MONTH, 1e-9);
    }
  });

  test('inet_down_cost / inet_up_cost are $/GB (1 TB = 1024 GB)', () => {
    for (const o of fixtures) {
      close(o.internet_down_cost_per_tb, o.inet_down_cost * 1024, 1e-9);
      close(o.internet_up_cost_per_tb, o.inet_up_cost * 1024, 1e-9);
    }
  });
});

describe('priceOffer', () => {
  test('GTX 1660 S, 50 GB', () => {
    const p = pricingService.priceOffer(offer('GTX 1660 S'), { storageGB: 50, config: DEFAULT });
    // compute:  0.06 $/h x 62.5                     = 3.75 credits/h
    // storage:  0.2 $/GB/month x 62.5               = 12.5 credits/GB/month
    //           0.2 x 50 / 720 = 0.0138889 $/h x 62.5 = 0.868 -> 0.87 credits/h
    // total:    3.75 + 0.87                          = 4.62 credits/h
    // download: 0.00390625 $/GB x 62.5               = 0.2441 credits/GB (upload the same)
    assert.equal(p.priceAvailable, true);
    assert.equal(p.computeCreditsPerHour, 3.75);
    assert.equal(p.storageCreditsPerGBMonth, 12.5);
    assert.equal(p.storageCreditsPerHour, 0.87);
    assert.equal(p.totalCreditsPerHour, 4.62);
    assert.equal(p.bandwidthDownCreditsPerGB, 0.2441);
    assert.equal(p.bandwidthUpCreditsPerGB, 0.2441);
    assert.equal(p.bandwidthBilling, 'usage');
    // The host has 381 GB free; only the 50 GB chosen are priced.
    assert.ok(offer('GTX 1660 S').disk_space > 300);
  });

  test('RTX 4060, 100 GB (higher storage rate)', () => {
    const p = pricingService.priceOffer(offer('RTX 4060'), { storageGB: 100, config: DEFAULT });
    // compute:  0.0733333 x 62.5            = 4.583 -> 4.58
    // storage:  0.4 x 100 / 720 = 0.0555556 $/h x 62.5 = 3.472 -> 3.47
    // total:    4.58 + 3.47                  = 8.05
    assert.equal(p.computeCreditsPerHour, 4.58);
    assert.equal(p.storageCreditsPerGBMonth, 25);
    assert.equal(p.storageCreditsPerHour, 3.47);
    assert.equal(p.totalCreditsPerHour, 8.05);
  });

  test('RTX 3080, 50 GB (expensive bandwidth)', () => {
    const p = pricingService.priceOffer(offer('RTX 3080'), { storageGB: 50, config: DEFAULT });
    // compute:  0.1333333 x 62.5 = 8.333 -> 8.33; storage 0.87 (as above); total 9.20
    // download: 0.01953125 x 62.5 = 1.2207 credits/GB
    assert.equal(p.computeCreditsPerHour, 8.33);
    assert.equal(p.totalCreditsPerHour, 9.2);
    assert.equal(p.bandwidthDownCreditsPerGB, 1.2207);
    assert.equal(p.bandwidthUpCreditsPerGB, 1.2207);
  });

  test('RTX 2070S: download and upload are priced separately', () => {
    const p = pricingService.priceOffer(offer('RTX 2070S'), { storageGB: 50, config: DEFAULT });
    // download 0.0026041667 x 62.5 = 0.1628; upload 0.00390625 x 62.5 = 0.2441
    assert.equal(p.bandwidthDownCreditsPerGB, 0.1628);
    assert.equal(p.bandwidthUpCreditsPerGB, 0.2441);
  });

  test('the total equals the shown components, at every size', () => {
    for (const o of fixtures) {
      for (const gb of [10, 37, 50, 100, 250, 1000]) {
        const p = pricingService.priceOffer(o, { storageGB: gb, config: DEFAULT });
        close(p.totalCreditsPerHour, Math.round((p.computeCreditsPerHour + p.storageCreditsPerHour) * 100) / 100);
      }
    }
  });

  test('the 7 Oct case: storage is no longer many times what Vast charges', () => {
    // That rental priced 50 GB of storage at 20.83 credits/h. At Vast's real rate
    // (0.2 $/GB/month) 50 GB is 0.87 credits/h, 24x less.
    const p = pricingService.priceOffer(offer('GTX 1660 S'), { storageGB: 50, config: DEFAULT });
    assert.ok(p.storageCreditsPerHour < 1);
    close(20.83 / p.storageCreditsPerHour, 23.94, 0.01);
  });

  test('markup and credits-per-USD from PricingConfig are respected', () => {
    const o = offer('GTX 1660 S');
    // No markup, 100 credits per USD: compute 0.06 x 100 = 6.00; storage 0.0138889 x 100 = 1.39; total 7.39
    const a = pricingService.priceOffer(o, { storageGB: 50, config: { markupPercentage: 0, creditsPerUsd: 100 } });
    assert.deepEqual([a.computeCreditsPerHour, a.storageCreditsPerHour, a.totalCreditsPerHour], [6, 1.39, 7.39]);
    // 50 % markup, 50 credits per USD (x 75): compute 4.50; storage 1.04; total 5.54
    const b = pricingService.priceOffer(o, { storageGB: 50, config: { markupPercentage: 50, creditsPerUsd: 50 } });
    assert.deepEqual([b.computeCreditsPerHour, b.storageCreditsPerHour, b.totalCreditsPerHour], [4.5, 1.04, 5.54]);
    // Older config objects carry tokenValue instead of creditsPerUsd.
    const c = pricingService.priceOffer(o, { storageGB: 50, config: { markupPercentage: 0, tokenValue: 100 } });
    assert.equal(c.totalCreditsPerHour, 7.39);
  });

  test('missing Vast.ai data gives "price unavailable", never a guess', () => {
    const { storage_cost, ...noStorage } = offer('GTX 1660 S');
    const p = pricingService.priceOffer(noStorage, { storageGB: 50, config: DEFAULT });
    assert.equal(p.priceAvailable, false);
    assert.equal(p.totalCreditsPerHour, null);
    assert.equal(p.computeCreditsPerHour, null);
    const { inet_up_cost, ...noUpload } = offer('GTX 1660 S');
    assert.equal(pricingService.priceOffer(noUpload, { storageGB: 50, config: DEFAULT }).bandwidthUpCreditsPerGB, null);
    assert.equal(pricingService.priceOffer({}, { storageGB: 50, config: DEFAULT }).priceAvailable, false);
  });

  test('repriceOffer recomputes a normalized offer for another size', () => {
    const normalized = { id: '9000001', gpuName: 'GTX 1660 S', rawOffer: offer('GTX 1660 S') };
    const at100 = pricingService.repriceOffer(normalized, 100, DEFAULT);
    // storage 0.2 x 100 / 720 x 62.5 = 1.736 -> 1.74; total 3.75 + 1.74 = 5.49
    assert.equal(at100.storageGB, 100);
    assert.equal(at100.totalCreditsPerHour, 5.49);
    assert.equal(at100.gpuName, 'GTX 1660 S');
  });
});
