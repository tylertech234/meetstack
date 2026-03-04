#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

backup_dir="${1:-}"
force_flag="${2:-}"

if [[ -z "$backup_dir" ]]; then
  echo "Usage: bash scripts/restore.sh <backup-dir> [--force]" >&2
  exit 1
fi

if [[ ! -d "$backup_dir" ]]; then
  echo "Backup directory not found: $backup_dir" >&2
  exit 1
fi

if [[ "$force_flag" != "--force" ]]; then
  echo "Restore will overwrite volume contents. Re-run with --force to continue." >&2
  exit 1
fi

shopt -s nullglob
archives=("$backup_dir"/*.tar.gz)
shopt -u nullglob

if [[ ${#archives[@]} -eq 0 ]]; then
  echo "No .tar.gz volume archives found in: $backup_dir" >&2
  exit 1
fi

for archive in "${archives[@]}"; do
  volume_name="$(basename "$archive" .tar.gz)"
  echo "Restoring $volume_name"

  docker volume create "$volume_name" >/dev/null
  docker run --rm \
    -v "$volume_name:/data" \
    -v "$backup_dir:/backup" \
    alpine sh -c "find /data -mindepth 1 -maxdepth 1 -exec rm -rf {} + && tar xzf /backup/${volume_name}.tar.gz -C /data"
done

echo "Restore complete from: $backup_dir"
