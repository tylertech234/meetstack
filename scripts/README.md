# scripts/ — helper shell scripts

## Available scripts

### `backup.sh`

Dumps all named Docker volumes defined in `docker-compose.yml` to dated
tar.gz archives under `backups/YYYY-MM-DD/`.

```bash
bash scripts/backup.sh
```

### `restore.sh`

Restores a single Docker volume from a tar.gz archive. Prompts for
confirmation before overwriting data.

```bash
bash scripts/restore.sh backups/2024-03-15/n8n_data.tar.gz meetstack_n8n_data
```

### `pull-model.sh`

Pulls the Ollama model specified in `.env` (or pass a model name as an
argument).

```bash
# Pull the default model from .env
bash scripts/pull-model.sh

# Pull a specific model
bash scripts/pull-model.sh phi3:mini
```

### `update-stack.sh` / `update-stack.ps1`

Pulls latest images for all services, recreates containers, waits for
health checks, and prunes old images to free disk space.

```bash
# CPU-only update
bash scripts/update-stack.sh

# With GPU overlay
bash scripts/update-stack.sh --gpu

# Preview without changes
bash scripts/update-stack.sh --dry-run
```

PowerShell:
```powershell
.\scripts\update-stack.ps1 -Gpu
.\scripts\update-stack.ps1 -DryRun
```

### `compact-docker-vhdx.ps1`

Compacts the Docker Desktop WSL2 virtual disk (`ext4.vhdx`) to reclaim
unused space. WSL2 VHDXs grow when data is written but never auto-shrink.
**Must be run as Administrator.**

```powershell
# From an elevated PowerShell:
.\scripts\compact-docker-vhdx.ps1
```
