# scripts/ — helper shell scripts

Run scripts from the repository root.

## Included scripts

- `bash scripts/health-check.sh`
	- Verifies all required meetstack services are running.

- `bash scripts/backup.sh [output-dir]`
	- Backs up all Docker volumes for the compose project into `.tar.gz` archives.
	- Default destination: `.temp/backups/<timestamp>/`

- `bash scripts/restore.sh <backup-dir> --force`
	- Restores volume archives created by `backup.sh`.
	- Requires `--force` to avoid accidental data overwrite.

## Notes

- `backup.sh` and `restore.sh` operate on Docker volumes attached to the current compose project name.
- The repository-local `.temp/` folder is ignored by Git and is intended for local backup artifacts.
