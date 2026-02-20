# OAN Kubernetes Deployment Guide

## Architecture

```
Browser (you)
     ↓
oan-ui  [LoadBalancer :80]      ← only public-facing pod
     ↓  http://oan-llm:80
oan-llm [ClusterIP :80→8000]   ← FastAPI backend
     ↓              ↓
redis               beckn-mock
[ClusterIP :6379]  [ClusterIP :8001]
```

All internal communication uses **Kubernetes DNS** — no IPs needed.

---

## Deploy Order (Important!)

```bash
# 1. Secrets first
kubectl apply -f 00-secrets.yaml

# 2. Redis (oan-llm depends on it)
kubectl apply -f 01-redis.yaml

# 3. Beckn Mock (oan-llm depends on it)
kubectl apply -f 02-beckn-mock.yaml

# 4. LLM API (depends on redis + beckn-mock)
kubectl apply -f 03-oan-llm.yaml

# 5. UI last (depends on oan-llm)
kubectl apply -f 04-oan-ui.yaml
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
NAME                           READY   STATUS    
redis-xxx                      1/1     Running   
beckn-mock-xxx                 1/1     Running   
oan-llm-xxx                    1/1     Running   
oan-ui-xxx                     1/1     Running   
```

---

## Access the UI

```bash
minikube service oan-ui
```

---

## Check Logs

```bash
kubectl logs deployment/oan-llm
kubectl logs deployment/oan-ui
kubectl logs deployment/redis
kubectl logs deployment/beckn-mock
```

---

## Test Pod Communication

```bash
# Exec into UI pod
kubectl exec -it <oan-ui-pod> -- /bin/sh

# Test LLM API
curl http://oan-llm:80/api/health/

# Test Beckn Mock (from oan-llm pod)
kubectl exec -it <oan-llm-pod> -- curl http://beckn-mock:8001/

# Test Redis (from oan-llm pod)
kubectl exec -it <oan-llm-pod> -- python3 -c "import redis; r = redis.Redis(host='redis', port=6379); print(r.ping())"
```

---

## Teardown

```bash
kubectl delete -f .
```

---

## Kubernetes DNS Cheatsheet

| Service Name | Internal DNS |
|---|---|
| redis | `redis.default.svc.cluster.local` or just `redis` |
| beckn-mock | `beckn-mock.default.svc.cluster.local` or just `beckn-mock` |
| oan-llm | `oan-llm.default.svc.cluster.local` or just `oan-llm` |
| oan-ui | `oan-ui.default.svc.cluster.local` or just `oan-ui` |
