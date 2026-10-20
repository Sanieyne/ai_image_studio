import { WebSocket } from 'ws';
import { signAccessToken } from '../src/utils/jwt.js';

const BASE_URL = 'http://localhost:5000/api/v1';
const WS_URL = 'ws://localhost:5000/ws/instance-status';
const USER_ID = '6ac171077aa40685d51c972f'; // masana

async function main() {
  console.log('=== [1] Authenticating Test User ===');
  const token = signAccessToken({ id: USER_ID, role: 'user' });
  console.log('Generated token for user masana (60d lifetime)');

  console.log('\n=== [2] Finding Cheapest Live Offer ===');
  const offersRes = await fetch(`${BASE_URL}/gpu/offers?limit=10&orderBy=price`);
  const offersJson = await offersRes.json();
  const offers = offersJson.data?.offers || [];
  if (offers.length === 0) {
    throw new Error('No GPU offers available on Vast.ai');
  }

  // Pick the cheapest rentable offer
  const selectedOffer = offers.find((o) => o.rentable) || offers[0];
  console.log(`Selected offer: #${selectedOffer.id} - ${selectedOffer.gpuName} at ${selectedOffer.creditsPerHour} credits/hr (${selectedOffer.geolocation})`);

  console.log('\n=== [3] Renting GPU Instance via POST /gpu/rent ===');
  const rentPayload = {
    offerId: selectedOffer.id,
    storageGB: 30,
    selectedModelIds: ['realesrgan-x4plus'], // Tiny ~64MB model for fast test
  };

  const rentRes = await fetch(`${BASE_URL}/gpu/rent`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(rentPayload),
  });

  const rentJson = await rentRes.json();
  if (!rentJson.success) {
    throw new Error(`Rent failed: ${rentJson.message || JSON.stringify(rentJson)}`);
  }

  const instance = rentJson.data;
  const instanceId = instance._id || instance.id;
  const contractId = instance.providerInstanceId;
  console.log(`[OK] Instance created in DB: ${instanceId}`);
  console.log(`[OK] Vast.ai Contract ID: #${contractId}`);
  console.log(`[OK] Initial Status: ${instance.status}`);

  const transcript = [];
  const addLog = (event, data) => {
    const entry = {
      timestamp: new Date().toISOString(),
      event,
      data,
    };
    transcript.push(entry);
    console.log(`[${entry.timestamp}] [WS ${event}]`, JSON.stringify(data));
  };

  try {
    console.log('\n=== [4] Connecting to InstanceStatus WebSocket Channel ===');
    const wsUri = `${WS_URL}?token=${token}&instanceId=${instanceId}`;
    const ws = new WebSocket(wsUri);

    await new Promise((resolve, reject) => {
      const timeoutTimer = setTimeout(() => {
        console.log('\n[!] Test run monitoring window completed (240s limit). Proceeding to cleanup...');
        resolve();
      }, 240000); // 4 minutes max monitoring

      ws.on('open', () => {
        addLog('OPEN', { url: wsUri });
      });

      ws.on('message', (raw) => {
        try {
          const msg = JSON.parse(raw.toString());
          addLog(msg.type, msg);

          if (msg.type === 'STATUS_UPDATE') {
            console.log(`>>> STATE TRANSITION: ${msg.status} <<<`);
            if (msg.status === 'READY') {
              console.log('>>> GPU REACHED READY STATE! <<<');
              clearTimeout(timeoutTimer);
              resolve();
            }
          }
        } catch (err) {
          addLog('RAW', raw.toString());
        }
      });

      ws.on('error', (err) => {
        addLog('ERROR', { message: err.message });
        resolve(); // proceed to cleanup rather than hanging
      });

      ws.on('close', (code, reason) => {
        addLog('CLOSE', { code, reason: reason.toString() });
      });
    });

    try { ws.close(); } catch (_) {}
  } finally {
    console.log('\n=== [5] Terminating Rented Test Instance to Avoid Charges ===');
    try {
      const termRes = await fetch(`${BASE_URL}/gpu/instances/${instanceId}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` },
      });
      const termJson = await termRes.json();
      console.log(`[OK] Instance termination result: ${termJson.success ? 'Terminated successfully' : termJson.message}`);
    } catch (err) {
      console.error('Failed to terminate instance via API, falling back to direct vastai CLI destroy:', err.message);
      try {
        const { execSync } = await import('child_process');
        execSync(`vastai destroy instance ${contractId}`, { stdio: 'inherit' });
      } catch (e2) {
        console.error('Direct destroy error:', e2.message);
      }
    }
  }

  console.log('\n=== [6] Real Test Transcript Summary ===');
  console.log(JSON.stringify(transcript, null, 2));
}

main().catch((err) => {
  console.error('\n[FATAL ERROR]:', err);
  process.exit(1);
});
