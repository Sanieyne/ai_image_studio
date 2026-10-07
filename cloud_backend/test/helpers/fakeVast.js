/**
 * In-memory stand-in for Vast.ai, installed by patching the vastaiService
 * singleton. Nothing here talks to the network.
 *
 *   const vast = installFakeVast();
 *   vast.addInstance(123);            // a running contract
 *   vast.failList = true;             // next listings throw
 *   vast.failDestroy = 1;             // next N destroys throw
 *   vast.restore();
 */

import { vastaiService } from '../../src/services/vastai.service.js';

const PATCHED = ['listInstancesStrict', 'destroyInstance', 'createInstance', 'getOffer'];

export function installFakeVast() {
  const originals = Object.fromEntries(PATCHED.map((m) => [m, vastaiService[m]]));
  let nextContract = 900000;

  const fake = {
    instances: new Map(),
    calls: { list: 0, destroy: [], create: [] },
    failList: false,
    failDestroy: 0,
    // When set, createInstance waits for this promise before answering.
    createGate: null,
    offer: null,

    addInstance(id, extra = {}) {
      const entry = { id: Number(id), actual_status: 'running', label: null, start_date: Date.now() / 1000, ...extra };
      fake.instances.set(String(id), entry);
      return entry;
    },
    removeInstance(id) {
      fake.instances.delete(String(id));
    },
    restore() {
      for (const [m, fn] of Object.entries(originals)) vastaiService[m] = fn;
    },
  };

  vastaiService.listInstancesStrict = async () => {
    fake.calls.list += 1;
    if (fake.failList) throw new Error('fake Vast.ai listing failure');
    return [...fake.instances.values()].map((v) => ({ ...v }));
  };
  vastaiService.destroyInstance = async (id) => {
    fake.calls.destroy.push(String(id));
    if (fake.failDestroy > 0) {
      fake.failDestroy -= 1;
      throw new Error('fake destroy failure');
    }
    const existed = fake.instances.delete(String(id));
    return { success: true, instanceId: id, alreadyGone: !existed };
  };
  vastaiService.createInstance = async (offerId, config = {}) => {
    fake.calls.create.push({ offerId, config });
    if (fake.createGate) await fake.createGate;
    nextContract += 1;
    fake.addInstance(nextContract, { label: config.label });
    return { success: true, new_contract: nextContract, instanceId: String(nextContract) };
  };
  vastaiService.getOffer = async () => {
    if (!fake.offer) throw new Error('fake offer not set');
    return fake.offer;
  };

  return fake;
}
