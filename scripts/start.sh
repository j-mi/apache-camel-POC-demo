#!/usr/bin/env bash
# Bring up the whole stack and port-forward to localhost:8080.
# Idempotent — safe to run repeatedly.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-camel-weather-poc:1.0.0}"

# 1. Cluster
if ! minikube status >/dev/null 2>&1; then
  echo "[start] starting minikube..."
  minikube start --driver=docker --cpus=2 --memory=4096
else
  echo "[start] minikube already running"
fi

# 2. Image
have_image="$(eval "$(minikube docker-env)"; docker images --format '{{.Repository}}:{{.Tag}}' | grep -Fxq "$IMAGE" && echo yes || echo no)"
if [[ "$have_image" != "yes" ]]; then
  echo "[start] image $IMAGE missing; building..."
  "$REPO_DIR/scripts/build-image.sh"
else
  echo "[start] image $IMAGE already in minikube"
fi

# 3. Manifests
if ! kubectl get deploy camel-weather-poc >/dev/null 2>&1; then
  echo "[start] applying k8s manifests..."
  kubectl apply -f "$REPO_DIR/k8s/"
else
  echo "[start] deployment already exists"
fi

# 4. Wait for rollout
echo "[start] waiting for pod to be ready..."
kubectl rollout status deploy/camel-weather-poc --timeout=120s

# 5. Drop stale port-forwards before starting a new one
pkill -f "kubectl port-forward.*camel-weather-poc" 2>/dev/null || true
sleep 1

cat <<EOF

[start] ready. Endpoints (Ctrl+C here to stop the port-forward):
   POST   http://localhost:8080/process
   GET    http://localhost:8080/health
   GET    http://localhost:8080/openapi.json
   GET    http://localhost:8080/swagger-ui

EOF

exec kubectl port-forward svc/camel-weather-poc 8080:80
