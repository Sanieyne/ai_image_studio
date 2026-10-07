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

## Phase 1b: one session per device

### What changes
- Each login or registration creates a `sessions` document (one per device). Refresh
  tokens carry `sid` (session) and `gen` (generation); no token values are stored.
- A refresh rotates only its own session. The previous token keeps working for
  `REFRESH_GRACE_SECONDS` (30 s) and gets a token for the current generation, so
  parallel refreshes from one app never look like reuse. Any older token revokes
  that session only (`revokeReason: refresh_token_reuse`).
- New endpoints: `POST /api/v1/auth/logout` (body `{ refreshToken }`, this device; works
  with an expired token) and `POST /api/v1/auth/logout-all` (Bearer access token, every
  device). Access tokens already issued stay valid until they expire (15 min).
- Login/register accept an optional `deviceLabel` (max 64 chars); otherwise the
  User-Agent is used. The app sends e.g. `Windows app`.

### Compatibility with v0.2.0 and with sessions from before the deploy
- Request and response shapes are unchanged; v0.2.0 keeps working without changes
  (it just doesn't call logout on Sign Out).
- A refresh token issued before the deploy (no `sid`) is checked against the old
  `User.refreshTokenHash` slot and becomes a session on first use
  (label "Signed in before device sessions"). Nobody is logged out by the deploy.
- With sessions in place, set `JWT_ACCESS_EXPIRES=15m` in the live `.env` (it is `60d` now).

### New collection, fields and indexes
- Collection `sessions`: `user`, `familyId`, `generation`, `previousValidUntil`,
  `deviceLabel`, `lastUsedAt`, `expiresAt`, `revokedAt`, `revokeReason`.
- `User.legacySession` (select: false): links a migrated pre-sessions token to its session
  for the grace period.
- Build the indexes once (`autoIndex` is off in production). The TTL index deletes
  sessions when their refresh token expires:
  ```bash
  mongosh ai_image_studio --quiet --eval '
    db.sessions.createIndex({ user: 1 });
    db.sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });'
  ```

### New setting
| Variable | Default | Meaning |
|---|---|---|
| `REFRESH_GRACE_SECONDS` | `30` | How long the previous refresh token is accepted after a rotation. |

### Test account
The e2e test account (`e2e093001@test.local`) password was rotated on 8 Oct 2026.
Credentials: `/root/backups/test-account/credentials` (chmod 600, never in git).
Smoke test: `python3 -I /root/diagnostics/scripts/smoke_login.py --refresh`.

## R2-2: prices that match Vast.ai

### Vast.ai units (checked against live offers, 8 Oct 2026)
- `dph_base`: compute, $/hour.
- `storage_cost`: **$/GB/month, 720-hour month**. For an offer searched with
  `allocated_storage = G`, `dph_total − dph_base = storage_cost × G / 720` exactly.
  The old code used it as $/GB/hour-ish and priced the host's whole free disk:
  the 7 Oct rental showed 20.83 credits/h for 50 GB instead of 0.87.
- `inet_down_cost` / `inet_up_cost`: $/GB into / out of the instance
  (`internet_*_cost_per_tb` = 1024 ×).

### One pricing function
`pricingService.priceOffer(rawOffer, { storageGB })`, used by the offer list,
recommendations, offer details, the estimate, rent, and (through the stored
`pricing.totalCreditsPerHour`) billing:

```
credits = USD × (1 + markupPercentage/100) × creditsPerUsd      (PricingConfig)
computeCreditsPerHour  = credits(dph_base)                       rounded to 0.01
storageCreditsPerHour  = credits(storage_cost × storageGB / 720) rounded to 0.01
totalCreditsPerHour    = compute + storage                       (what is charged)
bandwidthDown/UpCreditsPerGB = credits(inet_down/up_cost)        rounded to 0.0001, billed by usage
```

Example, GTX 1660 S (0.06 $/h, 0.2 $/GB/month), 50 GB, default config (1 $ = 62.5 credits):
3.75 + 0.87 = **4.62 credits/h**; bandwidth 0.2441 credits/GB each way.

- `GET /gpu/offers`, `/gpu/recommended`, `/gpu/offers/:id` accept `storageGB`
  (10–1000, default 50) and price every offer for it. v0.2.0 sends none and gets 50 GB.
- `GET /gpu/pricing/estimate`: `creditsPerHour` = `totalCreditsPerHour` (same as the card);
  `totalCredits` = per-hour total × hours; bandwidth is not in the total.
- Missing Vast.ai fields give `priceAvailable: false` and null prices; such offers sort last
  and cannot be rented (409). No default prices anywhere.
- Instances store `pricing.storageGB`, `computeCreditsPerHour`, `storageCreditsPerGBMonth`,
  `storageCreditsPerHour`, `totalCreditsPerHour`, `bandwidthDown/UpCreditsPerGB`
  (old names `creditsPerHour`, `bandwidthCreditsPerGB` kept for v0.2.0).

### Bandwidth is not billed yet
Vast.ai charges us per GB downloaded and uploaded. Whether it reports per-instance usage
could not be checked (no instance was running; rentals are paused). Until it is, users see
bandwidth prices labelled "billed by usage" but are **not charged** for it; we pay it.
Check on the approved test rental (instance fields such as `inet_down_billed`).
