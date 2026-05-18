#!/usr/bin/env bash
# Stop the running app: kill the port-forward and pause the cluster.
# Cluster state, image, and manifests are preserved — start.sh will resume fast.
set -euo pipefail

pkill -f "kubectl port-forward.*camel-weather-poc" 2>/dev/null && \
  echo "[stop] killed port-forward" || \
  echo "[stop] no port-forward running"

if [[ "${DELETE_DEPLOY:-no}" == "yes" ]]; then
  REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  echo "[stop] DELETE_DEPLOY=yes — removing k8s manifests..."
  kubectl delete -f "$REPO_DIR/k8s/" --ignore-not-found
fi

if minikube status >/dev/null 2>&1; then
  echo "[stop] stopping minikube..."
  minikube stop
else
  echo "[stop] minikube already stopped"
fi

echo "[stop] done."
