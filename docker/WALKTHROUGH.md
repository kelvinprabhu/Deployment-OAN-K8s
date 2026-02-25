# MH-OAN Docker Compose — Complete Walkthrough

A step-by-step guide to understanding, configuring, and running the full MH-OAN system using Docker Compose.

---

## System Overview

The MH-OAN system consists of **10 interconnected Docker containers** running on a single `oan-network` bridge network. Every service communicates using Docker DNS (container names as hostnames).

```
                         ┌──────────────────────────────────────────────────────┐
                         │                  BROWSER (User)                      │
                         └──────┬─────────┬───────────┬────────────────────────┘
                                │         │           │
                           :8081      :8082       :8090
                                │         │           │
                                ▼         ▼           ▼
                         ┌──────────┐ ┌────────────────────┐  ┌──────────────┐
                         │  oan-ui  │ │ telemetry-dash-ui  │  │   keycloak   │
                         │  Nginx   │ │     React SPA      │  │   IAM/Auth   │
                         │  :8081   │ │     :8082          │  │   :8090      │
                         └────┬─────┘ └─────────┬──────────┘  └──────────────┘
                              │                 │
               ┌──────────────┼────────┐        │
               │              │        │        │
               ▼              ▼        ▼        ▼
     ┌───────────────┐ ┌──────────┐ ┌──────────────────────────────────┐
     │   oan-llm     │ │ telemetry│ │  telemetry-dashboard-service     │
     │  FastAPI/LLM  │ │processor │ │       REST API :3001             │
     │    :8000      │ │  :3000   │ └──────────────┬───────────────────┘
     └──┬────┬───┬───┘ └────┬────┘                 │
        │    │   │          │                       │
        ▼    ▼   ▼          ▼                       ▼
  ┌────────┐ ┌──────────┐ ┌──────────────────────────────┐
  │ redis  │ │beckn-mock│ │     telemetry-postgres        │
  │ :6379  │ │  :8001   │ │         :5432                 │
  └────────┘ └──────────┘ │  schema.sql auto-init         │
                          └──────────────────────────────┘
  ┌──────────────┐
  │  nominatim   │  ← Optional geocoding
  │    :8080     │
  └──────────────┘
```

---

## Step 1: Understand the Services

### Layer 1 — Data Stores

| Service | Container Name | Image | Port | Purpose |
|---|---|---|---|---|
| **Redis** | `oan-redis` | `redis:7-alpine` | 6379 | In-memory cache, session store, pub/sub |
| **PostgreSQL** | `oan-telemetry-postgres` | `postgres:17` | 5432 | Telemetry data store (questions, feedback, errors) |

- Redis uses **AOF persistence** (append-only file) with a named Docker volume `redis-data`
- Postgres auto-loads `schema.sql` on first boot via `/docker-entrypoint-initdb.d/`
- Postgres data persists in named volume `postgres-data`

### Layer 2 — Backend Services

| Service | Container Name | Image | Port | Purpose |
|---|---|---|---|---|
| **Beckn Mock** | `oan-beckn-mock` | `kelvinprabhu/beckn-mock:latest` | 8001 | Beckn protocol mock BAP server |
| **OAN LLM** | `oan-llm` | `kelvinprabhu/oan-llm:ap-south-1` | 8000 | FastAPI LLM backend (Gemini-powered) |
| **Nominatim** | `oan-nominatim` | `mediagis/nominatim:4.4` | 8080 | Geocoding/reverse geocoding (OSM data) |

- OAN LLM depends on Redis (healthy) + Beckn Mock (started)
- Nominatim downloads and imports OSM data on first run (10-30 min for Western India)
- OAN LLM connects to all three via Docker DNS: `redis`, `beckn-mock`, `nominatim`

### Layer 3 — Telemetry Pipeline

| Service | Container Name | Image | Port | Purpose |
|---|---|---|---|---|
| **Telemetry Processor** | `oan-telemetry-processor` | `kelvinprabhu/telemetry-dashboard-processor:latest` | 3000 | Cron-based log processor (every 2 min) |
| **Dashboard Service** | `oan-telemetry-dashboard-service` | `kelvinprabhu/oan-telementry-service:latest` | 3001 | REST API for telemetry data |

### Layer 4 — Frontend & Auth

| Service | Container Name | Image | Port | Purpose |
|---|---|---|---|---|
| **Keycloak** | `oan-keycloak` | `quay.io/keycloak/keycloak:24.0` | 8082 | Identity & access management |
| **OAN UI** | `oan-ui` | `kelvinprabhu/oan-ui-service:yaseen-version` | 8081 | Main frontend (Vite + Nginx) |
| **Dashboard UI** | `oan-telemetry-dashboard-ui` | `kelvinprabhu/telemetry-dashboard-ui:latest` | 8881 | Telemetry dashboard (Keycloak-protected) |

---

## Step 2: Configure Environment

Open `.env` and set your API keys:

```bash
cd docker/
nano .env
```

**Required changes:**
```env
# Replace these placeholders with real keys
GEMINI_API_KEY=your-actual-gemini-key
MAPBOX_API_TOKEN=your-actual-mapbox-token
```

**Optional changes:**
```env
# Change auth mode (true = skip login, false = require Keycloak)
BYPASS_AUTH=true

# Use a smaller dataset for faster Nominatim import
NOMINATIM_PBF_URL=https://download.geofabrik.de/europe/monaco-latest.osm.pbf
```

---

## Step 3: Start the System

```bash
chmod +x start-mh-oan.sh

# Quick start (without Nominatim — recommended for first run)
./start-mh-oan.sh

# Full start (includes Nominatim geocoding)
./start-mh-oan.sh up --with-nominatim
```

The script will:
1. ✅ Check Docker and Docker Compose are installed
2. ✅ Validate `.env` file exists and warn about placeholder keys
3. 📥 Pull latest Docker images
4. 🚀 Start all containers with `docker compose up -d`
5. ⏳ Wait for Redis, Postgres, OAN LLM, and OAN UI health checks
6. 📊 Print container status and access URLs

---

## Step 4: Verify Everything is Running

```bash
# Check container status
./start-mh-oan.sh status

# Or use docker compose directly
docker compose ps
```

Expected output:
```
NAME                             STATUS          PORTS
oan-redis                        Up (healthy)    0.0.0.0:6379->6379/tcp
oan-telemetry-postgres           Up (healthy)    0.0.0.0:5432->5432/tcp
oan-beckn-mock                   Up (healthy)    0.0.0.0:8001->8001/tcp
oan-llm                          Up (healthy)    0.0.0.0:8000->8000/tcp
oan-ui                           Up (healthy)    0.0.0.0:8081->8081/tcp
oan-telemetry-dashboard-service  Up (healthy)    0.0.0.0:3001->3001/tcp
oan-telemetry-processor          Up              0.0.0.0:3000->3000/tcp
oan-keycloak                     Up (healthy)    0.0.0.0:8082->8080/tcp
oan-telemetry-dashboard-ui       Up (healthy)    0.0.0.0:8881->8881/tcp
```

---

## Step 5: Access the Services

| Service | URL | Credentials |
|---|---|---|
| 📱 **OAN Frontend** | [http://localhost:8081](http://localhost:8081) | Bypass auth (dev mode) |
| 🔧 **API Docs** | [http://localhost:8000/docs](http://localhost:8000/docs) | — |
| 📊 **Telemetry Dashboard** | [http://localhost:8881](http://localhost:8881) | `kelvin` / `1234` |
| 🔑 **Keycloak Admin** | [http://localhost:8082](http://localhost:8082) | `admin` / `admin` |
| 🗺️ **Nominatim** | [http://localhost:8080](http://localhost:8080) | — |
| 🔷 **Beckn Mock** | [http://localhost:8001](http://localhost:8001) | — |

---

## Step 6: Understand the Telemetry Flow

```
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                        TELEMETRY DATA FLOW                              │
 ├─────────────────────────────────────────────────────────────────────────┤
 │                                                                         │
 │  1. USER INTERACTION                                                    │
 │     └─ User asks a question in OAN UI (localhost:8081)                  │
 │                                                                         │
 │  2. TELEMETRY EVENT GENERATED                                           │
 │     └─ OAN UI Telemetry SDK fires OE_ITEM_RESPONSE event               │
 │     └─ Event written to winston_logs table in Postgres                  │
 │                                                                         │
 │  3. PROCESSOR PICKS UP LOGS (every 2 minutes)                           │
 │     └─ telemetry-processor reads unprocessed rows (sync_status = 0)     │
 │     └─ Routes by event type using event_processors config table:        │
 │         • questionsDetails  → questions table                           │
 │         • feedbackDetails   → feedback table                            │
 │         • errorDetails      → errorDetails table                        │
 │         • unmatched         → dead_letter_logs table                    │
 │     └─ Marks rows as processed (sync_status = 1)                        │
 │                                                                         │
 │  4. DASHBOARD SERVICE SERVES DATA                                       │
 │     └─ telemetry-dashboard-service (REST API on :3001)                  │
 │     └─ Exposes /v3 endpoints for questions, feedback, errors,           │
 │        leaderboard, and analytics                                       │
 │                                                                         │
 │  5. DASHBOARD UI DISPLAYS                                               │
 │     └─ telemetry-dashboard-ui (localhost:8082)                          │
 │     └─ Protected by Keycloak authentication                             │
 │     └─ Shows dashboards, leaderboards, Q&A analytics                    │
 │                                                                         │
 │  6. LEADERBOARD AGGREGATION (daily at 1:00 AM)                          │
 │     └─ Processor refreshes leaderboard table from questions data        │
 │                                                                         │
 └─────────────────────────────────────────────────────────────────────────┘
```

### Database Tables

| Table | Source | Description |
|---|---|---|
| `winston_logs` | Telemetry SDK | Raw event log ingestion point |
| `questions` | Processor | Processed Q&A events |
| `feedback` | Processor | User feedback (thumbs up/down) |
| `errorDetails` | Processor | Error events |
| `dead_letter_logs` | Processor | Unroutable events |
| `event_processors` | Seed data | Dynamic event routing config |
| `leaderboard` | Processor (daily) | Aggregated user activity |
| `village_list` | Seed script | Reference geo data |

---

## Step 7: Keycloak Configuration

Keycloak is pre-configured via `keycloak-realm.json` which auto-imports on first start.

### Realm: `oan-telemetry`

**Roles:**
| Role | Access Level |
|---|---|
| `admin` | Full read/write access to telemetry dashboard |
| `viewer` | Read-only dashboard access |

**Pre-configured Users:**
| Username | Password | Role | Email |
|---|---|---|---|
| `kelvin` | `1234` | `admin` | kelvin@oan.com |
| `viewer` | `viewer123` | `viewer` | viewer@oan.com |

**Client: `oan-telemetry-dashboard`**
- Public client (no client secret)
- Standard flow + Direct access grants enabled
- Redirect URIs: `localhost:8082`, `localhost:8081`, wildcard (`*` for dev)
- CORS: All listed origins + `+` (auto from redirects)
- Token lifespan: 1 hour
- SSO session: 7 days max

### Adding a New User

1. Open [http://localhost:8082](http://localhost:8082) → Login as `admin`/`admin`
2. Select **oan-telemetry** realm (top-left dropdown)
3. Go to **Users** → **Add User**
4. Fill in username, email, name → Save
5. Go to **Credentials** tab → Set password (temporary = off)
6. Go to **Role Mapping** → Assign `admin` or `viewer`

---

## Step 8: Docker Network Internals

All containers join the `oan-network` bridge network. Internal communication uses service names:

| From | To | Internal URL |
|---|---|---|
| `oan-llm` | Redis | `redis:6379` |
| `oan-llm` | Beckn Mock | `http://beckn-mock:8001` |
| `oan-llm` | Nominatim | `http://nominatim:8080` |
| `oan-ui` (nginx) | OAN LLM | `http://oan-llm:8000` |
| `oan-ui` (nginx) | Dashboard Service | `http://telemetry-dashboard-service:3001` |
| `telemetry-processor` | Postgres | `telemetry-postgres:5432` |
| `telemetry-dashboard-service` | Postgres | `telemetry-postgres:5432` |
| `telemetry-dashboard-service` | Redis | `redis:6379` |
| `telemetry-dashboard-ui` | Keycloak | `http://localhost:8082` (browser-side) |

> **Note:** The Dashboard UI connects to Keycloak via `localhost:8082` (not internal DNS) because authentication happens in the **browser**, which can't resolve Docker DNS names.

### Persistent Volumes

| Volume | Used By | Data |
|---|---|---|
| `redis-data` | Redis | AOF persistence files |
| `postgres-data` | PostgreSQL | Database files |
| `nominatim-data` | Nominatim | Imported OSM data |
| `nominatim-flatnode` | Nominatim | Flatnode cache |

---

## Step 9: Common Commands

```bash
# ── Lifecycle ──────────────────────────────────
./start-mh-oan.sh                       # Start (no Nominatim)
./start-mh-oan.sh up --with-nominatim   # Start with Nominatim
./start-mh-oan.sh down                  # Stop everything
./start-mh-oan.sh restart               # Restart all
./start-mh-oan.sh clean                 # Delete containers + volumes

# ── Monitoring ─────────────────────────────────
./start-mh-oan.sh status                # Status + URLs
./start-mh-oan.sh logs                  # All logs
./start-mh-oan.sh logs oan-llm          # Specific service logs

# ── Docker Compose Direct ─────────────────────
docker compose ps                        # Container status
docker compose exec redis redis-cli      # Redis CLI
docker compose exec telemetry-postgres psql -U postgres -d telemetry  # Postgres CLI

# ── Database Inspection ───────────────────────
docker compose exec telemetry-postgres psql -U postgres -d telemetry -c '\dt'
docker compose exec telemetry-postgres psql -U postgres -d telemetry -c 'SELECT count(*) FROM winston_logs'
docker compose exec telemetry-postgres psql -U postgres -d telemetry -c 'SELECT count(*) FROM questions'

# ── Debugging ─────────────────────────────────
docker compose logs --tail=50 oan-llm    # Last 50 lines
docker compose exec oan-ui cat /etc/nginx/conf.d/default.conf
docker compose exec oan-llm env          # Check env vars
```

---

## Step 10: Troubleshooting

| Problem | Solution |
|---|---|
| `GEMINI_API_KEY is required` | Edit `.env`, replace placeholder with real key |
| OAN LLM keeps restarting | Check logs: `./start-mh-oan.sh logs oan-llm` — likely API key issue |
| Keycloak returns 404 | Wait 60+ seconds for realm import to complete |
| Dashboard shows "Not Authenticated" | Login via Keycloak at `localhost:8881`, use `kelvin`/`1234` |
| Nominatim import stuck | First import takes 10-30 min. Check: `./start-mh-oan.sh logs nominatim` |
| Port already in use | Edit `docker-compose.yml`, change host port (left of `:`) |
| Postgres data not persisting | Ensure volume `postgres-data` exists: `docker volume ls` |
| All services failing | Run `./start-mh-oan.sh clean` then `./start-mh-oan.sh` for fresh start |

---

## File Structure

```
docker/
├── docker-compose.yml      # 10 services on oan-network
├── .env                    # All secrets & config
├── keycloak-realm.json     # Keycloak realm auto-import
├── nginx.conf              # OAN UI reverse proxy
├── start-mh-oan.sh         # WSL startup script
├── DOCKER_SETUP.md         # Quick setup reference
└── WALKTHROUGH.md          # This file
```

Referenced from parent:
```
../schema.sql               # PostgreSQL schema (auto-loaded on first boot)
```
