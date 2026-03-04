#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

project_name="${COMPOSE_PROJECT_NAME:-$(basename "$REPO_ROOT" | tr '[:upper:]' '[:lower:]')}"
timestamp="$(date +%Y%m%d-%H%M%S)"
out_dir="${1:-$REPO_ROOT/.temp/backups/$timestamp}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but not installed." >&2
  exit 1
fi

mkdir -p "$out_dir"

mapfile -t volumes < <(docker volume ls \
  --filter "label=com.docker.compose.project=$project_name" \
  --format '{{.Name}}')

if [[ ${#volumes[@]} -eq 0 ]]; then
  echo "No Docker volumes found for compose project '$project_name'." >&2
  exit 1
fi

for volume in "${volumes[@]}"; do
  echo "Backing up $volume"
  docker run --rm \
    -v "$volume:/data:ro" \
    -v "$out_dir:/backup" \
    alpine sh -c "tar czf /backup/${volume}.tar.gz -C /data ."
  ls -lh "$out_dir/${volume}.tar.gz"
done

echo "Backup complete: $out_dir"
