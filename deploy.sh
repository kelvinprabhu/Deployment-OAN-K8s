#!/bin/bash

echo "=== Deploying OAN Kubernetes Stack ==="

# 1. Secrets (Ensure you have this file, it is ignored by git)
if [ -f "00-secrets.yaml" ]; then
    echo "Applying Secrets..."
    kubectl apply -f 00-secrets.yaml
else
    echo "WARNING: 00-secrets.yaml not found! Skipping secrets."
fi

# 2. Infrastructure (Redis)
echo "Applying Redis..."
kubectl apply -f 01-redis.yaml

# 3. Backend Services
echo "Applying Beckn Mock..."
kubectl apply -f 02-beckn-mock.yaml

echo "Applying OAN LLM Service..."
kubectl apply -f 03-oan-llm.yaml

# 4. Telemetry Stack
echo "Applying Telemetry Database (Postgres)..."
kubectl apply -f 05-telemetry-postgres.yaml
# Wait a bit for Postgres to be ready if needed, or rely on readiness probes
# sleep 5

echo "Applying Telemetry Dashboard Service..."
kubectl apply -f 06-telemetry-dashboard-service.yaml

echo "Applying Telemetry Processor..."
kubectl apply -f 07-telemetry-processor.yaml

# 5. Frontend & Auth
echo "Applying OAN UI..."
kubectl apply -f 04-oan-ui.yaml

echo "Applying Telemetry UI (Keycloak & Frontend)..."
kubectl apply -f 08-telemetry-ui-keycloak.yaml

echo "Showing Pods working fine..."
kubectl get pods -w
echo "=== Deployment Complete ==="
echo "Check status with: kubectl get pods"
