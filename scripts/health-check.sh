#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

required_services=(
  n8n
  ollama
  open-webui
  vikunja-db
  vikunja
  home-assistant
  nginx-proxy-manager
)

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but not installed." >&2
  exit 1
fi

if ! docker compose ps >/dev/null 2>&1; then
  echo "Unable to query docker compose status. Is Docker running and is the stack initialized?" >&2
  exit 1
fi

mapfile -t running_services < <(docker compose ps --services --filter status=running)
missing=()

for service in "${required_services[@]}"; do
  if [[ ! " ${running_services[*]} " =~ " ${service} " ]]; then
    missing+=("$service")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Stack health check failed. Missing running services: ${missing[*]}" >&2
  exit 1
fi

echo "Stack health check passed. All required services are running."
