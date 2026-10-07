import { User } from '../../src/models/User.js';
import { GpuInstance } from '../../src/models/GpuInstance.js';
import { GPU_STATUS, GPU_PROVIDERS } from '../../src/config/constants.js';

let n = 0;

export async function makeUser(credits = 100, extra = {}) {
  n += 1;
  return User.create({
    username: `user${n}${Date.now() % 100000}`,
    email: `user${n}-${Date.now()}@example.com`,
    password: 'Password-123456',
    credits,
    ...extra,
  });
}

/**
 * A READY instance with a confirmed contract, billed up to `billedUntil`.
 * - reachedReadyAt: set for READY/RUNNING instances, unless overridden.
 * - billingStartedAt: billedUntil (nothing charged yet), unless overridden. With a
 *   preset creditsCharged it stays empty, as on records billed before the field
 *   existed; billing then derives the start from what was charged.
 */
export async function makeInstance(user, overrides = {}) {
  const status = overrides.status ?? GPU_STATUS.READY;
  const ready = status === GPU_STATUS.READY || status === GPU_STATUS.RUNNING;
  return GpuInstance.create({
    user: user._id,
    provider: GPU_PROVIDERS.VASTAI,
    providerInstanceId: '123456',
    status: GPU_STATUS.READY,
    gpuType: 'RTX 4060 Ti',
    vramGB: 16,
    costPerHour: 0.5,
    pricing: { totalCreditsPerHour: 36 }, // 0.01 credits per second
    startedAt: new Date(),
    reachedReadyAt: ready ? new Date() : null,
    ...overrides,
    billingStartedAt:
      overrides.billingStartedAt ?? (overrides.creditsCharged ? null : overrides.billedUntil ?? null),
  });
}
