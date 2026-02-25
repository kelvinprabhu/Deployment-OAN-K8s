# MH-OAN Docker Compose Setup Guide

Complete guide for running the MH-OAN system with Docker Compose on WSL / Linux / macOS.

---

## Architecture

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
  │  nominatim   │  ← Optional (geocoding)
  │    :8080     │
  └──────────────┘
```

All services communicate over the `oan-network` Docker bridge network using service names as hostnames.

---

## Telemetry Data Flow

```
 OAN UI (browser)
    │
    │  1. User asks a question
    │  2. Telemetry SDK fires events
    │     (OE_ITEM_RESPONSE)
    │
    ▼
 telemetry-postgres ──► winston_logs table
    │
    │  3. Processor reads unprocessed logs
    │     every 2 minutes (CRON)
    │
    ▼
 telemetry-processor
    │
    │  4. Routes events by type:
    │     • questions    → questions table
    │     • feedback     → feedback table
    │     • errors       → errorDetails table
    │     • unknown      → dead_letter_logs
    │
    ▼
 telemetry-dashboard-service (REST API)
    │
    │  5. Serves processed data via /v3 endpoints
    │
    ▼
 telemetry-dashboard-ui
    │
    │  6. Renders dashboards, leaderboards,
    │     Q&A analytics (Keycloak-protected)
    │
    ▼
 Browser → http://localhost:8082
```

---

## Prerequisites

| Requirement | Minimum | Install |
|---|---|---|
| Docker | 24.0+ | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| Docker Compose | v2.20+ | Included with Docker Desktop |
| WSL 2 (Windows) | Ubuntu 22.04+ | `wsl --install` |
| RAM | 8 GB | 16 GB recommended with Nominatim |
| Disk | 5 GB | 30 GB+ with Nominatim (OSM data) |

---

## Quick Start

### 1. Configure environment

```bash
cd docker/

# Edit .env and fill in your API keys
nano .env
```

**Required keys:**
- `GEMINI_API_KEY` — Get from [Google AI Studio](https://aistudio.google.com/apikey)
- `MAPBOX_API_TOKEN` — Get from [Mapbox](https://account.mapbox.com/)

### 2. Start the system

```bash
# Make script executable
chmod +x start-mh-oan.sh

# Start (without Nominatim — faster for development)
./start-mh-oan.sh

# OR start with Nominatim geocoding
./start-mh-oan.sh up --with-nominatim
```

### 3. Access services

| Service | URL |
|---|---|
| 📱 OAN Frontend | [http://localhost:8081](http://localhost:8081) |
| 🔧 API Docs | [http://localhost:8000/docs](http://localhost:8000/docs) |
| 📊 Telemetry Dashboard | [http://localhost:8881](http://localhost:8881) |
| 🔑 Keycloak Admin | [http://localhost:8082](http://localhost:8082) |
| 🗺️ Nominatim | [http://localhost:8080](http://localhost:8080) |

---

## Script Commands

```bash
./start-mh-oan.sh up                    # Start (no Nominatim)
./start-mh-oan.sh up --with-nominatim   # Start with Nominatim
./start-mh-oan.sh down                  # Stop everything
./start-mh-oan.sh restart               # Restart all
./start-mh-oan.sh status                # Show status + URLs
./start-mh-oan.sh logs                  # Tail all logs
./start-mh-oan.sh logs oan-llm          # Tail specific service
./start-mh-oan.sh clean                 # Remove everything + volumes
```

---

## Keycloak Setup

Keycloak auto-imports the realm from `keycloak-realm.json` on first start.

### Default Users

| Username | Password | Role | Access |
|---|---|---|---|
| `admin` | `admin` | Keycloak Admin | Admin console only |
| `kelvin` | `1234` | `admin` | Full dashboard access |
| `viewer` | `viewer123` | `viewer` | Read-only dashboard |

### Admin Console

1. Go to [http://localhost:8090](http://localhost:8090)
2. Log in with `admin` / `admin`
3. Select the **oan-telemetry** realm from the dropdown

### Adding New Users

1. Admin Console → Users → Add User
2. Set username, email, first/last name
3. Go to Credentials tab → Set password
4. Go to Role Mapping → Assign `admin` or `viewer`

---

## Service Configuration Reference

### OAN LLM (`oan-llm`)

| Variable | Default | Description |
|---|---|---|
| `LLM_PROVIDER` | `gemini` | LLM provider |
| `LLM_MODEL_NAME` | `gemini-2.5-flash` | Model name |
| `GEMINI_API_KEY` | — | **Required** |
| `MAPBOX_API_TOKEN` | — | **Required** for maps |
| `LOGFIRE_TOKEN` | — | Optional telemetry |

### Telemetry Processor

| Variable | Default | Description |
|---|---|---|
| `BATCH_SIZE` | `500` | Logs processed per cycle |
| `CRON_SCHEDULE` | `*/2 * * * *` | Every 2 minutes |
| `LEADERBOARD_REFRESH_SCHEDULE` | `0 1 * * *` | Daily at 1 AM |

### Nominatim

| Variable | Default | Description |
|---|---|---|
| `NOMINATIM_PBF_URL` | Western India | OSM data file URL |
| `NOMINATIM_THREADS` | `4` | Import parallelism |

> **Tip:** Use Monaco for fast test imports:
> `NOMINATIM_PBF_URL=https://download.geofabrik.de/europe/monaco-latest.osm.pbf`

---

## Troubleshooting

### Container won't start

```bash
# Check logs
docker compose logs <service-name>

# Check all container status
docker compose ps -a
```

### OAN LLM fails with API key error

Edit `.env` and set a valid `GEMINI_API_KEY`.

### Keycloak redirect errors

Ensure `redirectUris` in `keycloak-realm.json` includes your access URL.
Default config covers `localhost:8082` and `localhost:8081`.

### Nominatim takes too long

First import downloads and processes OSM data. For Western India this can take **10-30 minutes**. Use a smaller dataset for testing:

```env
NOMINATIM_PBF_URL=https://download.geofabrik.de/europe/monaco-latest.osm.pbf
```

### Port conflicts

If a port is already in use, edit `docker-compose.yml` and change the host port (left side of `:`):

```yaml
ports:
  - "9000:8000"  # Changed host port from 8000 to 9000
```

### Reset everything

```bash
./start-mh-oan.sh clean   # Removes containers + volumes
./start-mh-oan.sh up      # Fresh start
```

---

## File Structure

```
docker/
├── docker-compose.yml      # All 10 services definition
├── .env                    # Environment variables (secrets)
├── keycloak-realm.json     # Keycloak realm auto-import config
├── nginx.conf              # OAN UI reverse proxy config
├── start-mh-oan.sh         # WSL startup script
└── DOCKER_SETUP.md         # This file
```

Parent directory (referenced by compose):
```
../schema.sql               # PostgreSQL schema (auto-loaded)
```
