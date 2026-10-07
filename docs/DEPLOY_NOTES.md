# Deploy notes: fix/security-billing

Work in progress; completed per phase. Commands assume the live checkout at
`/root/projects/ai_image_studio` and the PM2 app `ai-studio-backend`.

## Already done on the live server (7 Oct 2026)

| Change | Rollback |
|---|---|
| nginx: `POST …/v1/gpu/rent` returns 503 on `/ai-api/api`, `/ai-backend/api`, `/ai/api` (rentals paused) | restore `/root/backups/nginx/20261007T190111Z/cosmic-gen.com`, `nginx -t && systemctl reload nginx` |
| ufw: removed `5000/tcp` allow rules (v4 + v6) | `ufw allow 5000/tcp` |
| `JWT_ACCESS_SECRET` rotated, backend restarted | restore `/root/backups/env/20261007T210256Z/.env`, `pm2 restart ai-studio-backend` |

## Phase 1: secrets and configuration

- The backend refuses to start if a JWT secret is a leaked example value, shorter
  than 32 characters, or if both secrets are equal. The live secrets pass these checks.
- `JWT_ACCESS_EXPIRES` defaults to `15m`. The live `.env` sets `60d`; change it only
  together with Phase 1b (multiple sessions), or every 15 minutes the app refreshes
  through the single-slot refresh logic.
- New GitHub secret before the next tagged build: `CONTABO_KNOWN_HOSTS`
  (output of `ssh-keyscan <server>`, checked against the server's real host key).

## Phase 2: GPU billing

### New settings (all optional)

| Variable | Default | Meaning |
|---|---|---|
| `HOST` | `127.0.0.1` | Listen address. nginx proxies to 127.0.0.1:5000. |
| `GPU_MAX_ACTIVE_PER_USER` | `1` | Active GPU instances per user. |
| `BILLING_INTERVAL_MS` | `60000` | Billing cycle. Charges are per second of rental. |
| `RECONCILE_INTERVAL_MS` | `600000` | Orphan and slot-counter check. |
| `RECONCILE_DESTROY_ORPHANS` | `false` | Destroy our labelled Vast.ai instances with no active record (else log only). |

### New fields

- `GpuInstance`: `contractConfirmedAt`, `billedUntil`, `creditsCharged`, `creditsRefunded`,
  `refundIssued`, `reachedReadyAt`, `stopReason`, `pendingStopReason`, `lowBalanceWarnedAt`,
  `lastSeenOnVastAt`, `vastMissCount`, `firstMissAt`, `holdsSlot`; index `{ status: 1 }`.
- `User`: `activeGpuInstances` (rental slots in use).

Indexes are not auto-built in production (`autoIndex` is off). Build the new one once:

```bash
mongosh ai_image_studio --quiet --eval 'db.gpuinstances.createIndex({ status: 1 })'
```

### How charging works

- Every 60 s, one Vast.ai listing; only contracts listed and not exited are charged.
  `test-…`, `pending-…` and other non-numeric ids are never charged.
- New rentals: billing starts when Vast.ai confirms the contract.
- Instances that exist before this deploy have no `billedUntil`: billing starts the
  first time the service sees them. Nothing earlier is charged.
- Stop (user, timeout, credits exhausted, instance gone from Vast.ai) settles a final
  charge. Instances that never reached READY are refunded in full.
- Out of credits: charge what is left, destroy the instance, status `stopped`,
  `stopReason: insufficient_credits`. A low-balance event is sent when under 15 minutes remain.

### Worked example

Rate stored on the instance: `pricing.totalCreditsPerHour = 28.9` (the 7 Oct RTX 4060 Ti
rental). Note: 20.83 of those 28.9 credits/hr are the overpriced storage fixed in R2-2.

| Step | Value |
|---|---|
| Per 60-s cycle | 60 × 28.9 / 3600 = 0.481667 credits (rounded to 6 decimals) |
| Runs 37 minutes (37 cycles) | 37 × 0.481667 = **17.821679 credits** |
| Exact | 28.9 × 37 / 60 = 17.821667 (rounding difference 0.000012) |
| Stopped 20 s into the next cycle | + 20 × 28.9 / 3600 = 0.160556 |
| Total charged | 17.982235 credits |
| If it never reached READY | all 17.982235 credits refunded |

### Before restarting with this code

1. Rentals stay paused (nginx rule above).
2. Close stale records, so billing never sees them:
   ```bash
   cd /root/projects/ai_image_studio/cloud_backend
   node scripts/cleanup_stale_gpu_instances.mjs          # dry run: review the list
   node scripts/cleanup_stale_gpu_instances.mjs --apply  # then apply
   ```
   Expected today: #54547010 (no longer on Vast.ai), `test-contract-1791101619182`,
   `test-contract-1791101680240`, `pending-1791099211934`.
3. Build the index above.
