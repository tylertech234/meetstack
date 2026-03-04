# meetstack

A self-hosted meetings and life-organisation stack, launched from a single
`docker-compose.yml` and managed through Nginx Proxy Manager.

---

## Overview

| Service | Purpose |
|---|---|
| **n8n** | Workflow automation |
| **Ollama** | Local LLM inference engine |
| **Open WebUI** | Chat UI for Ollama models |
| **Vikunja** | Task / project management |
| **Home Assistant** | Home automation |
| **Nginx Proxy Manager** | Reverse proxy & SSL termination |

All services share a single internal Docker network (`meetstack`). Only Nginx
Proxy Manager exposes ports to the host, keeping everything else off the public
network interface.

---

## Prerequisites

- **Docker Desktop for Windows** ≥ 4.25 with the **WSL 2** backend enabled
- **WSL 2** (Ubuntu 22.04 LTS recommended)
- At least **16 GB RAM** and **50 GB** free disk space
- *(Optional)* NVIDIA GPU with the latest Game Ready / Studio driver and the
  **NVIDIA Container Toolkit** installed inside WSL 2 — see
  [GPU passthrough notes](#gpu-passthrough-ollama--rtx-4070-ti) below

---

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/tylertech234/meetstack.git
cd meetstack

# 2. Create your local environment file
cp .env.example .env
#    Edit .env and replace every "changeme" value with real secrets/settings

# 3. Start the stack
docker compose up -d

# 4. Check that all containers are healthy
docker compose ps

# 5. Run the included service health check helper
bash scripts/health-check.sh
```

---

## Service URLs

After the stack is running, reach each service through Nginx Proxy Manager.
While you are setting up proxy hosts, the default direct-access addresses
(on the Docker host) are:

| Service | Direct URL | Notes |
|---|---|---|
| Nginx Proxy Manager admin | <http://localhost:81> | Default login: `admin@example.com` / `changeme` |
| n8n | internal only | Proxied via NPM |
| Open WebUI | internal only | Proxied via NPM |
| Vikunja | internal only | Proxied via NPM |
| Home Assistant | internal only | Proxied via NPM |
| Ollama API | internal only | Consumed by Open WebUI |

> **Tip:** On your local network, replace `localhost` with your machine's LAN
> IP address (e.g. `192.168.1.x`) to access the stack from other devices.

---

## GPU Passthrough — Ollama & RTX 4070 Ti

To offload inference to your NVIDIA RTX 4070 Ti, follow these steps **inside WSL 2**:

1. **Install NVIDIA Container Toolkit**

   ```bash
   distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
   curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo apt-key add -
   curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list \
     | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo service docker restart
   ```

2. **Verify GPU visibility**

   ```bash
   docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi
   # Replace the image tag above with the latest compatible CUDA version from:
   # https://hub.docker.com/r/nvidia/cuda/tags
   ```

3. **Enable the GPU block in `docker-compose.yml`**

   Uncomment the `deploy.resources.reservations` block under the `ollama`
   service:

   ```yaml
   deploy:
     resources:
       reservations:
         devices:
           - driver: nvidia
             count: all
             capabilities: [gpu]
   ```

4. Restart the stack:

   ```bash
   docker compose up -d ollama
   ```

---

## Directory Structure

```
meetstack/
├── docker-compose.yml       # Single compose file for all services
├── .env.example             # Template — copy to .env and fill in secrets
├── .gitignore
├── .github/
│   ├── actions/             # Composite / reusable action scaffolding
│   └── workflows/           # GitHub Actions workflow definitions
├── .temp/                   # Local-only temp files (ignored by Git)
├── README.md
├── services/
│   ├── n8n/                 # Bind-mount config / credentials for n8n
│   ├── ollama/              # Modelfiles, custom config for Ollama
│   ├── open-webui/          # Open WebUI config overrides
│   ├── vikunja/             # Vikunja config.yml overrides
│   └── home-assistant/      # HA custom_components and extra config
├── nginx/
│   └── proxy.conf           # Additional Nginx snippets loaded by NPM
└── scripts/                 # Helper shell scripts (backup, restore, etc.)
```

---

## Automation

- CI includes `.github/workflows/compose-validate.yml`, which validates
  `docker-compose.yml` with `.env.example` on push/PR.
- The `.github/actions/` folder is scaffolded for future reusable composite
  actions.

---

## Operations helpers

- `bash scripts/health-check.sh` verifies all core services are running.
- `bash scripts/backup.sh` writes per-volume backup archives to
  `.temp/backups/<timestamp>/`.
- `bash scripts/restore.sh <backup-dir> --force` restores those archives.

---

## Notes

- **`.env` is never committed** — only `.env.example` is tracked by Git.
- Use the scripts in `scripts/` for volume backup and restore operations.
- Use `docker compose logs -f <service>` to tail logs for a specific service.
