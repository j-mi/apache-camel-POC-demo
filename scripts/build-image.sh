#!/usr/bin/env bash
# Build the camel-weather-poc Docker image inside minikube's Docker daemon.
# Copies host's ~/.jbang and ~/.m2 caches into the build context so the
# image build does no network downloads.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/camel-poc-build}"
IMAGE="${IMAGE:-camel-weather-poc:1.0.0}"

echo "[build-image] repo:    $REPO_DIR"
echo "[build-image] context: $BUILD_DIR"
echo "[build-image] image:   $IMAGE"

if ! minikube status >/dev/null 2>&1; then
  echo "[build-image] minikube is not running. Run 'minikube start' first." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cp "$REPO_DIR/Dockerfile" \
   "$REPO_DIR/process.camel.yaml" \
   "$REPO_DIR/application.properties" \
   "$REPO_DIR/openapi.json" \
   "$BUILD_DIR/"

cp -R "$HOME/.jbang" "$BUILD_DIR/jbang-cache"
cp -R "$HOME/.m2"    "$BUILD_DIR/m2-cache"
find "$BUILD_DIR/m2-cache" -name '*.tmp' -delete 2>/dev/null || true

eval "$(minikube docker-env)"
docker build -t "$IMAGE" "$BUILD_DIR"

echo
echo "[build-image] done — $IMAGE is now in minikube's docker:"
docker images --filter "reference=$IMAGE"
