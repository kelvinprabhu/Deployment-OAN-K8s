# OAN Kubernetes Deployment Guide

## Architecture

```
                         ┌─────────────────────────────────────────────────┐
                         │              BROWSER (User)                     │
                         └─────────┬──────────────────────┬───────────────┘
                                   │                      │
                              port 80                port 30082
                                   ▼                      ▼
                         ┌─────────────────┐   ┌──────────────────────────┐
                         │    oan-ui        │   │  telemetry-dashboard-ui  │
                         │  LoadBalancer    │   │      NodePort :30082     │
                         │  :80 → 8081     │   │      :8082               │
                         └────┬────────────┘   └──────────┬───────────────┘
                              │                           │
               ┌──────────────┼───────────────┐           │
               │              │               │           │
               ▼              ▼               ▼           ▼
     ┌──────────────┐  ┌────────────┐  ┌──────────────────────────────────┐
     │   oan-llm    │  │  telemetry │  │  telemetry-dashboard-service     │
     │ ClusterIP    │  │  processor │  │  ClusterIP :3001                 │
     │ :80 → 8000   │  │ ClusterIP  │  └──────────────┬───────────────────┘
     └──┬────┬──────┘  │ :3000      │                 │
        │    │         └──────┬─────┘                 │
        │    │                │                       │
        ▼    ▼                ▼                       ▼
  ┌────────┐ ┌──────────┐  ┌──────────────────────────────┐
  │ redis  │ │beckn-mock│  │     telemetry-postgres        │
  │ClstrIP │ │ ClstrIP  │  │     ClusterIP :5432           │
  │ :6379  │ │ :8001    │  │     PVC: 1Gi                  │
  │PVC:512M│ └──────────┘  │     ConfigMap: schema.sql     │
  └────────┘               └──────────────────────────────┘
```

All internal communication uses **Kubernetes DNS** — no IPs needed.

---

## File Structure

| File | Kind | Description |
|---|---|---|
| `00-secrets.yaml` | Secret | All secrets (`oan-secrets`, `telemetry-postgres-secret`) |
| `00-persistent-volumes.yaml` | PVC | Persistent storage for Postgres (1Gi) & Redis (512Mi) |
| `01-redis.yaml` | Deployment + Service | Redis with AOF persistence on PVC |
| `02-beckn-mock.yaml` | Deployment + Service | Beckn protocol mock server |
| `03-oan-llm.yaml` | Deployment + Service | FastAPI LLM backend (Gemini) |
| `04-oan-ui.yaml` | ConfigMap + Deployment + Service | OAN frontend (Nginx + Vite) |
| `05-telemetry-postgres.yaml` | ConfigMap + Deployment + Service | PostgreSQL + schema init |
| `06-telemetry-dashboard-service.yaml` | Deployment + Service | Telemetry dashboard API |
| `07-telemetry-processor.yaml` | Deployment + Service | Telemetry log processor (cron) |
| `08-telemetry-ui-keycloak.yaml` | Deployment + Service | Telemetry dashboard UI (Keycloak variant) |
| `09-telemetry-dashboard-ui.yaml` | Deployment + Service | Telemetry dashboard UI (Minikube variant) |
| `keycloak-realm.json` | — | Keycloak realm import config |
| `schema.sql` | — | Reference copy of the DB schema |
| `deploy.sh` | — | Ordered deployment script |

---

## Deploy Order

### Automated (recommended)
```bash
chmod +x deploy.sh
./deploy.sh
```

### Manual (step-by-step)
```bash
# 0. Foundation — Secrets & Persistent Volumes
kubectl apply -f 00-secrets.yaml
kubectl apply -f 00-persistent-volumes.yaml

# 1. Infrastructure — Data Stores
kubectl apply -f 01-redis.yaml
kubectl apply -f 05-telemetry-postgres.yaml

# 2. Backend Services
kubectl apply -f 02-beckn-mock.yaml
kubectl apply -f 03-oan-llm.yaml

# 3. Telemetry Stack (depends on Postgres)
kubectl apply -f 06-telemetry-dashboard-service.yaml
kubectl apply -f 07-telemetry-processor.yaml

# 4. Frontend & Auth (depends on backends)
kubectl apply -f 04-oan-ui.yaml
kubectl apply -f 08-telemetry-ui-keycloak.yaml
kubectl apply -f 09-telemetry-dashboard-ui.yaml
```

### Or deploy everything at once:
```bash
kubectl apply -f .
```

---

## Verify Everything is Running

```bash
# Check all pods
kubectl get pods

# Check all services
kubectl get services

# Watch pods come up
kubectl get pods -w
```

Expected output:
```
NAME                                          READY   STATUS
redis-xxx                                     1/1     Running
beckn-mock-xxx                                1/1     Running
oan-llm-xxx                                   1/1     Running
oan-ui-xxx                                    1/1     Running
telemetry-postgres-xxx                        1/1     Running
telemetry-processor-xxx                       1/1     Running
telemetry-dashboard-service-xxx               1/1     Running
telemetry-dashboard-ui-xxx                    1/1     Running
```

---

## Access the Services

```bash
# OAN UI (main frontend)
minikube service oan-ui

# Telemetry Dashboard UI (NodePort)
# Access at: http://<minikube-ip>:30082
minikube service telemetry-dashboard-ui
```

---

## Check Logs

```bash
kubectl logs deployment/oan-llm
kubectl logs deployment/oan-ui
kubectl logs deployment/redis
kubectl logs deployment/beckn-mock
kubectl logs deployment/telemetry-postgres
kubectl logs deployment/telemetry-processor
kubectl logs deployment/telemetry-dashboard-service
kubectl logs deployment/telemetry-dashboard-ui
```

---

## Secrets Management

All sensitive values are stored in `00-secrets.yaml`:

| Secret Name | Keys | Used By |
|---|---|---|
| `oan-secrets` | `GEMINI_API_KEY`, `MAPBOX_API_TOKEN`, `LOGFIRE_TOKEN` | `oan-llm` |
| `telemetry-postgres-secret` | `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` | `telemetry-postgres`, `telemetry-dashboard-service`, `telemetry-processor` |

> **Note:** `00-secrets.yaml` is listed in `.gitignore`. Never commit real secrets to version control.

---

## Persistent Storage

| PVC Name | Size | Used By | Mount Path |
|---|---|---|---|
| `telemetry-postgres-pvc` | 1Gi | `telemetry-postgres` | `/var/lib/postgresql/data` |
| `redis-pvc` | 512Mi | `redis` | `/data` |

Data survives pod restarts and redeployments.

---

## Kubernetes DNS Cheatsheet

| Service Name | Internal DNS | Port |
|---|---|---|
| redis | `redis` | 6379 |
| beckn-mock | `beckn-mock` | 8001 |
| oan-llm | `oan-llm` | 80 → 8000 |
| oan-ui | `oan-ui` | 80 → 8081 |
| telemetry-postgres | `telemetry-postgres` | 5432 |
| telemetry-processor | `telemetry-processor` | 3000 |
| telemetry-dashboard-service | `telemetry-dashboard-service` | 3001 |
| telemetry-dashboard-ui | `telemetry-dashboard-ui` | 8082 (NodePort 30082) |

---

## Test Pod Communication

```bash
# Exec into UI pod
kubectl exec -it deployment/oan-ui -- /bin/sh

# Test LLM API
curl http://oan-llm:80/api/health/

# Test Beckn Mock (from oan-llm pod)
kubectl exec -it deployment/oan-llm -- curl http://beckn-mock:8001/

# Test Redis (from oan-llm pod)
kubectl exec -it deployment/oan-llm -- python3 -c "import redis; r = redis.Redis(host='redis', port=6379); print(r.ping())"

# Test Postgres (from telemetry-processor pod)
kubectl exec -it deployment/telemetry-processor -- sh -c "apt-get update && apt-get install -y postgresql-client && psql -h telemetry-postgres -U localhost -d telemetry -c '\dt'"
```

---

## Teardown

```bash
kubectl delete -f .
```

> **Warning:** Deleting PVCs will destroy all persistent data. To preserve data, delete deployments only:
> ```bash
> kubectl delete deployment --all
> kubectl delete service --all -l 'app!=kubernetes'
> ```
