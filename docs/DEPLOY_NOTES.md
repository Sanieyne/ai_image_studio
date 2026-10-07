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

- `GpuInstance`: `contractConfirmedAt`, `billedUntil`, `billingStartedAt`, `creditsCharged`, `creditsRefunded`,
  `refundIssued`, `reachedReadyAt`, `stopReason`, `pendingStopReason`, `lowBalanceWarnedAt`,
  `lastSeenOnVastAt`, `vastMissCount`, `firstMissAt`, `holdsSlot`; index `{ status: 1 }`.
- `User`: `activeGpuInstances` (rental slots in use).
- `Transaction`: `gpuInstance` (set only on GPU rental entries); unique partial index
  `{ gpuInstance: 1, type: 1 }`, so each rental has one charge entry and one refund entry.

Indexes are not auto-built in production (`autoIndex` is off). Build the new ones once:

```bash
mongosh ai_image_studio --quiet --eval '
  db.gpuinstances.createIndex({ status: 1 });
  db.transactions.createIndex(
    { gpuInstance: 1, type: 1 },
    { unique: true, partialFilterExpression: { gpuInstance: { $type: "objectId" } } }
  );'
```

### How charging works

- Every 60 s, one Vast.ai listing; only contracts listed and not exited are charged.
  `test-…`, `pending-…` and other non-numeric ids are never charged.
- New rentals: billing starts when Vast.ai confirms the contract.
- Instances that exist before this deploy have no `billedUntil`: billing starts the
  first time the service sees them. Nothing earlier is charged.
- Each charge is the total owed since billing started minus what was already charged,
  so per-cycle rounding never accumulates.
- Stop (user, timeout, credits exhausted, instance gone from Vast.ai) settles a final
  charge. A rental that never reached READY is refunded in full, whatever stopped it,
  including a user stop: nothing usable is delivered before READY.
  (TODO in code: once the app can send work before every model is ready, charge from
  the first generation instead.)
- Out of credits: charge what is left, destroy the instance, status `stopped`,
  `stopReason: insufficient_credits`. A low-balance event is sent when under 15 minutes remain.

### Ledger

- One `deduction` entry per rental, updated every cycle: amount (total charged so far),
  `balanceAfter`, and in `metadata` the GPU, credits/hr, billed seconds and minutes.
  Description, e.g. `GPU rental: RTX 4060 Ti, 37 min at 28.9 credits/hr`.
- At most one `refund` entry per rental (`Refund: RTX 4060 Ti rental stopped before it was ready`).
- Write order per charge: (1) claim the period and add to `creditsCharged`, (2) take the
  credits, (3) correct `creditsCharged` if the balance was short, (4) update the ledger entry.
  A crash between steps can only under-charge the user. The reconcile job (every 10 min)
  compares each rental's `creditsCharged`/`creditsRefunded` with its ledger entries and logs
  `[Billing] !!! LEDGER MISMATCH …` for any difference. Grep for it after deploy:
  `pm2 logs ai-studio-backend --nostream --lines 2000 | grep 'LEDGER MISMATCH'`

### Worked example

Rate stored on the instance: `pricing.totalCreditsPerHour = 28.9` (the 7 Oct RTX 4060 Ti
rental). Note: 20.83 of those 28.9 credits/hr are the overpriced storage fixed in R2-2.

| Step | Value |
|---|---|
| Cycle 1 (60 s) | owed round6(60 × 28.9 / 3600) = 0.481667; charged 0.481667 |
| Cycle 2 (120 s) | owed round6(120 × 28.9 / 3600) = 0.963333; charged 0.963333 − 0.481667 = 0.481666 |
| After 37 cycles | owed = charged = round6(2220 × 28.9 / 3600) = **17.821667** (no drift) |
| Stopped 20 s later (2240 s) | owed round6(2240 × 28.9 / 3600) = 17.982222; final charge 0.160555 |
| Total charged | **17.982222 credits**, one ledger row: `GPU rental: RTX 4060 Ti, 37 min at 28.9 credits/hr` |
| If it never reached READY | 17.982222 refunded; a second row `Refund: …` (+17.982222) |

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
