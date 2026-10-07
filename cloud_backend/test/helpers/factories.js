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

/** An active instance with a confirmed contract, billed up to `billedUntil`. */
export async function makeInstance(user, overrides = {}) {
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
    ...overrides,
  });
}
