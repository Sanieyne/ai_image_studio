import axios from 'axios';
import { env } from '../src/config/env.js';
import { execSync } from 'child_process';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function main() {
  const instanceId = 53979233;
  console.log(`=== Monitoring Real Remote Vast.ai Instance #${instanceId} ===`);

  const client = axios.create({
    headers: {
      Authorization: `Bearer ${env.VASTAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    timeout: 10000,
  });

  const startTime = Date.now();
  let mappedPort = null;
  let publicIp = '142.127.68.223';

  while (Date.now() - startTime < 600000) { // 10 minutes
    try {
      const res = await client.get('https://console.vast.ai/api/v1/instances/');
      const inst = res.data?.instances?.find((i) => String(i.id) === String(instanceId));
      if (!inst) {
        console.log('Instance not found in active list, waiting...');
        await sleep(5000);
        continue;
      }

      publicIp = inst.public_ipaddr || inst.ssh_host || publicIp;
      const status = inst.actual_status || inst.cur_state;
      const statusMsg = inst.status_msg || 'none';

      console.log(`[${Math.round((Date.now() - startTime) / 1000)}s] Status: ${status} | Msg: ${statusMsg} | DirectPorts: ${inst.direct_port_count}`);

      if (inst.ports) {
        console.log('Current Port Mappings:', JSON.stringify(inst.ports));
        if (inst.ports['8000/tcp']) {
          mappedPort = inst.ports['8000/tcp'][0]?.HostPort;
          console.log(`>>> FOUND MAPPED PORT: http://${publicIp}:${mappedPort} -> 8000`);
        }
      }

      // If running or starting, attempt to curl public port
      if (mappedPort) {
        console.log(`Testing HTTP GET http://${publicIp}:${mappedPort}/health...`);
        try {
          const raw = execSync(`curl -s --connect-timeout 4 --max-time 6 http://${publicIp}:${mappedPort}/health`, {
            encoding: 'utf-8',
          }).trim();
          if (raw) {
            console.log('\n========================================================');
            console.log('>>> REAL REMOTE GPU INFERENCE ENGINE HEALTH CHECK <<<');
            console.log('RAW RESPONSE:', raw);
            console.log('========================================================\n');
            if (raw.startsWith('{')) {
              const data = JSON.parse(raw);
              console.log('[SUCCESS] Remote Engine Verified:');
              console.log('- Status:', data.status);
              console.log('- Device:', data.device);
              console.log('- Device Name:', data.device_name);
              console.log('- Current Model:', data.current_model);
              break;
            }
          }
        } catch (curlErr) {
          console.log(`Port not reachable yet (${curlErr.message.split('\n')[0]})`);
        }
      }

      // Check console logs periodically
      if (Math.round((Date.now() - startTime) / 1000) % 20 === 0) {
        try {
          const logRes = await client.get(`https://console.vast.ai/api/v0/instances/${instanceId}/logs/`);
          if (logRes.data?.logs) {
            console.log('--- Remote Console Logs ---');
            console.log(logRes.data.logs.split('\n').slice(-15).join('\n'));
            console.log('---------------------------');
          }
        } catch (e) {}
      }

      if (status === 'running' && mappedPort) {
        // Let it poll a few times
      }
    } catch (err) {
      console.log('Poll error:', err.message);
    }
    await sleep(6000);
  }

  // After test completion, print final logs and offer termination
  console.log('\nFetching final logs from instance...');
  try {
    const finalLogs = await client.get(`https://console.vast.ai/api/v0/instances/${instanceId}/logs/`);
    console.log('Final Instance Logs:');
    console.log(finalLogs.data?.logs || '(no logs available)');
  } catch (e) {}
}

main().catch(console.error);
