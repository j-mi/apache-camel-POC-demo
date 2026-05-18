#!/usr/bin/env bash
# Nuke everything: delete the minikube cluster, the image, and the temp build context.
set -euo pipefail

echo "[clean] This deletes the minikube cluster, all its images, and /tmp/camel-poc-build."
read -r -p "Continue? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "[clean] aborted."; exit 1; }

pkill -f "kubectl port-forward.*camel-weather-poc" 2>/dev/null || true
minikube delete 2>/dev/null || true
rm -rf /tmp/camel-poc-build

echo "[clean] done. Run ./scripts/start.sh to rebuild from scratch."
