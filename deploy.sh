#!/bin/bash

echo "=== Deploying OAN Kubernetes Stack ==="

# ──────────────────────────────────────────────
# 0. Foundation: Secrets & Persistent Volumes
# ──────────────────────────────────────────────
if [ -f "00-secrets.yaml" ]; then
    echo "Applying Secrets..."
    kubectl apply -f 00-secrets.yaml
else
    echo "WARNING: 00-secrets.yaml not found! Skipping secrets."
fi

echo "Applying Persistent Volumes..."
kubectl apply -f 00-persistent-volumes.yaml

# ──────────────────────────────────────────────
# 1. Infrastructure: Redis & PostgreSQL
# ──────────────────────────────────────────────
echo "Applying Redis..."
kubectl apply -f 01-redis.yaml

echo "Applying Telemetry Database (Postgres)..."
kubectl apply -f 05-telemetry-postgres.yaml
echo "Waiting for Postgres to initialize..."
kubectl wait --for=condition=ready pod -l app=telemetry-postgres --timeout=60s 2>/dev/null || true

# ──────────────────────────────────────────────
# 2. Backend Services
# ──────────────────────────────────────────────
echo "Applying Beckn Mock..."
kubectl apply -f 02-beckn-mock.yaml

echo "Applying OAN LLM Service..."
kubectl apply -f 03-oan-llm.yaml

# ──────────────────────────────────────────────
# 3. Telemetry Stack (depends on Postgres)
# ──────────────────────────────────────────────
echo "Applying Telemetry Dashboard Service..."
kubectl apply -f 06-telemetry-dashboard-service.yaml

echo "Applying Telemetry Processor..."
kubectl apply -f 07-telemetry-processor.yaml

# ──────────────────────────────────────────────
# 4. Frontend & Auth (depends on backends)
# ──────────────────────────────────────────────
echo "Applying OAN UI..."
kubectl apply -f 04-oan-ui.yaml

echo "Applying Telemetry UI (Keycloak & Frontend)..."
kubectl apply -f 08-telemetry-ui-keycloak.yaml

echo "Applying Telemetry Dashboard UI..."
kubectl apply -f 09-telemetry-dashboard-ui.yaml

# ──────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────
echo ""
echo "=== Deployment Complete ==="
echo "Check status with: kubectl get pods"
echo "Watch pods:        kubectl get pods -w"
