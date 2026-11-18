#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed. Install Docker Desktop or Docker Engine first."
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker Engine is not running. Start Docker and run this script again."
  exit 1
fi
mkdir -p media
docker compose up -d --build
echo
docker compose ps
echo
echo "Local HLS stream: http://localhost:8080/live/multiktv.m3u8"
echo "Stop with: docker compose down"
