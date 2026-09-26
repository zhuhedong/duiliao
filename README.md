# Duiliao

A secure full-stack starter: **Python (FastAPI)** backend + **React 19 / Vite / TypeScript / Tailwind CSS v4 / [appica-ui](https://github.com/appica-dev/appica-ui)** frontend.

Every API call is encrypted end-to-end (on top of HTTPS), every request is signed and replay-protected, every page requires login, and the data model + crypto are designed so a native mobile app can reuse the exact same backend later.

```
duiliao/
├── backend/     FastAPI, SQLAlchemy, pycryptodome, PyJWT, Argon2
└── frontend/    Vite + React 19 + Tailwind v4 + appica-ui
```

---

## How your five requirements are met

| # | Requirement | How it's addressed |
|---|-------------|--------------------|
| 1 | **All APIs encrypted/decrypted** | Hybrid RSA + AES-256-GCM envelope. A middleware transparently decrypts every request body and encrypts every response, so route handlers only ever see plaintext. See [Encryption flow](#encryption-flow). |
| 2 | **Comprehensive API security** | Argon2id password hashing, JWT access + refresh with server-side revocation, HMAC request signing, timestamp + one-time-nonce replay protection, per-route rate limiting, brute-force lockout, strict security headers, tight CORS, no user enumeration. |
| 3 | **All pages require login** | Backend: `X-Session-Id` + JWT required on every `/api/v1` route except the crypto handshake and health. Frontend: a `<ProtectedRoute>` guard wraps every app page and redirects anonymous users to `/login`. |
| 4 | **User model ready for an app** | `users` table supports email **or** phone identity, verification flags, roles, status, `registration_source` (web/ios/android/api), MFA fields, brute-force fields, and soft delete. A `refresh_tokens` table models one row per device session (device id/name/platform/app version/IP) for a device list and "log out everywhere". |
| 5 | **Encryption + security work for an app** | The crypto uses only the standard Web Crypto API (no browser-only tricks), so the same `lib/crypto.ts` runs unchanged in a Capacitor/native WebView. CORS already allows the Capacitor origins. The signing secret is shipped per client build. |

---

## Prerequisites

- **Python 3.11+** (verified on 3.14). No system OpenSSL/Rust needed — crypto uses `pycryptodome`.
- **Node 18+** (verified on 22).

---

## Running it

### 1. Backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env      # then edit secrets (see below)
uvicorn app.main:app --reload --port 8000
```

- API root: `http://127.0.0.1:8000/api/v1`
- Interactive docs (dev only): `http://127.0.0.1:8000/docs`
- Health: `http://127.0.0.1:8000/health`

The dev database is SQLite (`backend/duiliao.db`), created automatically on first boot. For production set `DATABASE_URL` to Postgres and manage schema with Alembic.

### 2. Frontend

```bash
cd frontend
npm install

cp .env.example .env.local   # set VITE_APP_SIGNING_SECRET to match backend APP_SIGNING_SECRET
npm run dev
```

- App: `http://localhost:5173`
- Vite proxies `/api/*` to the backend, so no CORS friction in dev.

> **Important:** `VITE_APP_SIGNING_SECRET` (frontend) **must equal** `APP_SIGNING_SECRET` (backend) or every request will be rejected with `bad_signature`.

### 3. Verify (optional)

```bash
# Backend reference client — full encrypted flow + replay/auth checks
backend/.venv/bin/python backend/scripts/e2e_test.py

# Browser Web Crypto ↔ backend interop (uses Node's crypto.subtle)
node frontend/scripts/webcrypto_e2e.mjs
```

---

## Encryption flow

```
Client                                             Server
  │  GET /crypto/public-key                          │
  │ ───────────────────────────────────────────────▶ │  returns RSA public key (SPKI)
  │                                                   │
  │  generate AES-256 key, RSA-OAEP-wrap it           │
  │  POST /crypto/handshake { encryptedKey }          │
  │ ───────────────────────────────────────────────▶ │  stores AES key, returns sessionId
  │                                                   │
  │  every request thereafter:                        │
  │    headers: X-Session-Id, X-Timestamp,            │
  │             X-Nonce, X-Signature (HMAC)           │
  │    body:    AES-256-GCM { iv, ciphertext }        │
  │ ───────────────────────────────────────────────▶ │  verify signature + timestamp + nonce,
  │                                                   │  decrypt body, run handler,
  │ ◀─────────────────────────────────────────────── │  encrypt response (X-Encrypted: 1)
```

- **Confidentiality + integrity of the payload**: AES-256-GCM (the GCM tag authenticates the ciphertext).
- **Key exchange**: RSA-OAEP-SHA256 wraps a per-client AES session key.
- **Anti-tamper / anti-replay**: `X-Signature = HMAC-SHA256(APP_SIGNING_SECRET, sessionId\ntimestamp\nnonce\nsha256(body))`, with a ±300s timestamp window and a one-time nonce cache.

**This is defense-in-depth, not a replacement for HTTPS.** Always terminate TLS in front of the API in production. The app-level layer additionally protects against tampering by intermediaries/proxies, casual payload inspection, and replay.

---

## Authentication

- **Passwords**: Argon2id (memory-hard), auto-rehash on parameter changes.
- **Access token**: short-lived JWT (default 30 min), sent as `Authorization: Bearer`.
- **Refresh token**: long-lived JWT (default 30 days) whose `jti` is stored as a row in `refresh_tokens`. Deleting/revoking the row invalidates it server-side — enabling per-device logout and "log out everywhere".
- **Brute force**: after 5 failed logins the account locks for 15 minutes.
- The frontend keeps the access token in memory and the refresh token in `localStorage`, and transparently refreshes on `401`.

### Endpoints (all under `/api/v1`)

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/crypto/public-key` | — | Fetch server RSA public key |
| POST | `/crypto/handshake` | — | Register wrapped AES key → `sessionId` |
| POST | `/auth/register` | session | Create account, returns tokens |
| POST | `/auth/login` | session | Log in, returns tokens |
| POST | `/auth/refresh` | session | Exchange refresh token for a new access token |
| POST | `/auth/logout` | session + bearer | Revoke current or all sessions |
| GET | `/auth/me` | session + bearer | Current user |
| GET/PATCH | `/users/me` | session + bearer | View / update profile |
| GET | `/users/me/sessions` | session + bearer | List device sessions |
| DELETE | `/users/me/sessions/{id}` | session + bearer | Revoke a device session |

("session" = the crypto handshake / `X-Session-Id` layer, required on everything except the two crypto bootstrap routes.)

---

## Security checklist before production

- [ ] Serve everything over **HTTPS**; terminate TLS at a reverse proxy.
- [ ] Set strong, unique `JWT_SECRET` and `APP_SIGNING_SECRET`; rotate the app secret per client release.
- [ ] Set a stable `RSA_PRIVATE_KEY_PEM` (don't rely on the dev auto-generated key) and store it in a secret manager.
- [ ] Move the session-key store and nonce cache to **Redis** (the in-memory versions are single-process only).
- [ ] Switch `DATABASE_URL` to Postgres and adopt **Alembic** migrations.
- [ ] Set `APP_ENV=production` (disables `/docs`, enables HSTS).
- [ ] Put the API behind a WAF / edge rate limiter in addition to the app-level limits.
- [ ] Review CORS origins for your real web + app domains.

---

## Growing into a mobile app

The frontend was built so the crypto/auth layer is portable:

1. Add [Capacitor](https://capacitorjs.com/) to the `frontend` project.
2. `lib/crypto.ts` and `lib/api.ts` run unchanged (they use only Web Crypto + `fetch`).
3. Set `VITE_API_BASE_URL` to your deployed API and `VITE_APP_ID=ios|android`.
4. The backend already accepts `capacitor://localhost` / `http://localhost` origins and records `platform`, `device_name`, and `app_version` per session.

> **Note on the client signing secret:** anything shipped in a web bundle or app binary is inspectable. `APP_SIGNING_SECRET` is an integrity/anti-tamper + anti-replay layer, not a shared secret that is truly hidden from a determined user. Per-user security comes from the auth tokens.

---

## Prediction collector (ported from pred-collector)

The backend embeds a self-contained **collector** subsystem at `backend/collector/`. It ports six core features from the standalone `pred-collector` project and exposes them through the same authenticated, end-to-end-encrypted API as the rest of the app.

```
backend/collector/
├── runner.py + sources/*.py   collection: 43+ per-column scripts, one website each
├── ingest.py                  parse run.v1, dedupe by signature, upsert, auto-judge
├── draw_sync.py               import/validate official draws, trigger re-judge
├── judge.py + rules.py        judge engine: dispatch by play type to j_* handlers
├── consensus.py + analytics.py + missing_periods.py   consensus votes, rolling-window ratings, gap detection
├── source_catalog.py          auto-discover / validate site-group routes, isolate anomalies
├── registry.py                manage sources.yaml + scripts (backs the "采集管理" UI)
├── schema.py + db.py          SQLAlchemy models + engine (its own DB)
├── common/                    http / hash / xiao / attr / period / pred.v1 contract
└── sources.yaml + fixtures/
```

### Design carried over

- **Only the source subprocess touches the network.** `/collect` launches each source script (`sources/<id>.py`) as an isolated child process; the API process never connects to prediction sites directly. This keeps the API's attack surface small.
- **Standardized `pred.v1` JSON** flows from scripts → ingest → judge → analytics.
- **Draw validation**: exactly 7 balls in `01–49`, no duplicates, period = year + 3-digit sequence, year matches the draw date, and no future dates.
- **Missing periods** are recorded as internal gap rows that count as a miss but never vote in consensus and are never treated as source-claimed errors.

### Database isolation

The collector uses its **own** database so its ~15 domain tables never mix with the app's `users` / `refresh_tokens` tables. It defaults to SQLite at `backend/collector/data/pred.db`; override with a DSN (e.g. Postgres) via:

```bash
export COLLECTOR_DATABASE_URL="postgresql+psycopg://pred:...@127.0.0.1:5432/pred"
```

Tables are created and seeded lazily on the first collector request (or CLI call).

### API endpoints (all under `/api/v1/collector`)

Read endpoints require a logged-in user; mutating / operational endpoints require the `staff` or `admin` role.

| Method | Path | Role | Purpose |
|--------|------|------|---------|
| POST | `/collect` | staff | Run enabled source scripts for a lottery+period, then ingest |
| POST | `/ingest` | staff | Ingest a `run.v1` payload directly |
| POST | `/draws/sync` | staff | Import official draws and re-judge affected predictions |
| POST | `/judge` | staff | Recompute `JudgeResult`s for a lottery+period |
| GET | `/consensus` | user | Cross-source consensus vote for a period |
| GET | `/ratings` | user | Rolling-window (30/50/100) hit-rate ratings per source |
| GET | `/monitor` | user | Coverage / lag / missing-period monitor |
| POST | `/missing/confirm` | staff | Confirm covered-but-missing periods |
| GET | `/rules` | user | Implemented play-type rule catalog (versioned) |
| GET/POST | `/sources` | user / staff | List / create sources |
| GET/PATCH/DELETE | `/sources/{id}` | user / staff | Inspect / update / delete a source |
| GET | `/families` | user | Site families |
| GET | `/scripts`, GET/PUT `/scripts/{name}` | user / staff | List / read / write source scripts |
| GET/PUT | `/draw-config[/{lottery}]` | user / staff | Draw-fetch adapter config |
| GET | `/catalog/status[?site_family=...]` | user | 588080 / 83191 / 77452 catalog status (aggregate by default) |
| POST | `/catalog/scan[?site_family=...]` | staff | Run one or all dynamic catalog discovery scans |
| POST | `/sources/batch` | staff | Create reviewed source/script rows in one batch (supports `dry_run`) |

The catalog aggregate walks 83191's wrapper page and local iframe before
comparing the generated `/chajie/*.js` list, and probes 77452's 69 subpages
concurrently.  New or disappeared columns stay visible as `pending` / `missing`
until a reviewed source batch is attached.

### Offline try-out

Bundled fixtures let you exercise the whole pipeline without any network access. `PRED_ALLOW_FIXTURE=1` lets source scripts read a local fixture instead of fetching:

```bash
cd backend
PRED_ALLOW_FIXTURE=1 .venv/bin/python -c "
import json
from app import collector_bridge as cb
cb.bootstrap()
print(cb.collect('macau','248', source_ids=['haige_pingte','heizhuang_pingte'], fixture_dir='fixtures/dingjian'))
draws = json.load(open('collector/fixtures/draw_macau.json'))
print(cb.sync_draws('macau','248', draws=draws if isinstance(draws, list) else [draws]))
print(cb.judge('macau','248'))
print(cb.consensus_compare('macau','248'))
print(cb.ratings('macau','pingte_xiao'))
"
```

The original CLIs still work too (run from `backend/collector/` with the venv), e.g. `python judge.py --lottery macau --period 248`.

### Frontend pages

The React app gains a collector section (all behind the login guard). The nav
adds these pages, wired to the endpoints above:

| Route | Page | Uses |
|-------|------|------|
| `/collector/sources` | 采集 — list sources, enable/disable, run a collection (with optional offline fixtures) | `/sources`, `/collect` |
| `/collector/draws` | 开奖 — import official draws (or fetch) and re-judge | `/draws/sync`, `/judge` |
| `/collector/consensus` | 对照 — cross-source consensus vote for a period | `/consensus`, `/rules` |
| `/collector/ratings` | 源评级 — rolling-window hit-rate table | `/ratings`, `/rules` |
| `/collector/monitor` | 监控 — missing-period coverage + catalog scan status | `/monitor`, `/catalog/*` |

Read pages render for any logged-in user; buttons that trigger collection,
draw sync, judging, or source edits are disabled unless the user is `staff` /
`admin` (and the API enforces the same server-side).

### Getting an admin account

There is **no default admin account** — normal registration always creates a
`user`-role account. There are two ways to create the first admin.

**Option A — first-run web bootstrap (recommended for local/dev).** When no
admin/staff account exists yet, opening the app on a **loopback** client shows
an "初始化管理员账户" screen (the login page auto-redirects to `/bootstrap`).
Set a username + password and it creates the first admin and logs you straight
in. This entry is:

- only available while **no** admin/staff account exists (one-time),
- only accepted from `127.0.0.1` / `::1` (the real socket peer, not a spoofable
  `X-Forwarded-For`),
- **always disabled in production** (`APP_ENV=production`), and
- toggleable with `ALLOW_LOCAL_BOOTSTRAP=false`.

Endpoints: `GET /api/v1/auth/bootstrap` (availability) and
`POST /api/v1/auth/bootstrap` (create + auto-login).

**Option B — CLI (works anywhere, incl. production).** Bootstrap or promote an
account with the script (run from `backend/` with the venv):

```bash
# create a new admin (prompts for the password if --password is omitted)
.venv/bin/python scripts/manage_admin.py create --username admin --role admin

# or promote an account you already registered through the web UI
.venv/bin/python scripts/manage_admin.py promote --identifier you@example.com --role admin

# list current staff/admin accounts
.venv/bin/python scripts/manage_admin.py list
```

`--role` accepts `admin` or `staff` (both may run collector write operations).
`promote` also takes an optional `--password` to reset the account's password.

### Adding a source

1. Create `collector/sources/<id>.py` (it must only print `pred.v1` JSON to stdout; put the request URLs in the script's `URLS`, not in server config).
2. Add a row to `collector/sources.yaml` (or `POST /api/v1/collector/sources`).
3. The JSON contract and tables don't change.
```
