# meetstack

A self-hosted productivity and collaboration stack launched from a single
`docker-compose.yml` and managed through Nginx Proxy Manager. Designed to run
on a laptop, desktop, or single-board computer (e.g. Raspberry Pi 5).

---

## Overview

| Service | Purpose |
|---|---|
| **n8n** | Workflow automation (email, chat, reminders, pipelines) |
| **Ollama** | Local LLM inference engine |
| **Open WebUI** | Chat UI for Ollama models |
| **Vikunja** | Task and project management |
| **Wiki.js** | Knowledge base and documentation |
| **Radicale** | Shared CalDAV calendar |
| **Whisper** | Speech-to-text transcription |
| **Nginx Proxy Manager** | Reverse proxy & SSL termination |

All services share a single internal Docker network (`meetstack`). Only Nginx
Proxy Manager exposes ports to the host, keeping everything else off the public
network interface.

---

## Example Use Cases

| Use case | Services involved |
|---|---|
| **Meeting minutes** — transcribe audio, summarise, publish | Whisper → Ollama → Wiki.js (via n8n) |
| **Email automation** — scan inbox, draft replies, send digests | n8n → Ollama → email provider |
| **Chat Q&A** — answer questions in Discord / Slack / Teams | n8n → Ollama → chat platform |
| **Shared calendar** — meetings, events, deadlines | Radicale + any CalDAV client |
| **Calendar reminders** — daily digest of upcoming events | n8n → Radicale → email / chat |
| **Task management** — action items, assignments, tracking | Vikunja |
| **Knowledge base** — documentation, SOPs, FAQs | Wiki.js |
| **Chat with LLM** — ad-hoc questions, drafting, brainstorming | Open WebUI → Ollama |

See [`services/n8n/workflows/README.md`](services/n8n/workflows/README.md) for
detailed workflow designs.

---

## Prerequisites

### Windows (tested on Windows 11)

1. **Enable virtualisation in BIOS** — VT-x / AMD-V must be active.
2. **Enable Windows features** (run in an elevated PowerShell):

   ```powershell
   dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
   dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
   bcdedit /set hypervisorlaunchtype auto
   # Reboot after running these
   ```

3. **Install WSL 2** with a lightweight distro:

   ```powershell
   wsl --install --no-distribution   # installs the WSL 2 kernel
   wsl --install Debian              # ~150 MB, lighter than Ubuntu
   ```

4. **Install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/)** ≥ 4.25
   — enable the **WSL 2** backend in Settings → General.

### Linux / Raspberry Pi OS

- Docker Engine ≥ 24 with the Compose V2 plugin (`docker compose`).

### Hardware

- At least **8 GB RAM** (SBC) or **16 GB RAM** (laptop/desktop)
- At least **30 GB** free disk space
- *(Optional)* NVIDIA GPU with the latest driver and the **NVIDIA Container
  Toolkit** installed — see [GPU passthrough notes](#gpu-passthrough--ollama--nvidia-gpu) below

### Known Limitations

- **Windows/WSL 2 file bind-mounts:** Docker Desktop cannot bind-mount
  individual files from Windows paths into Linux containers — it creates
  directories instead. This stack uses environment variables and directory
  mounts as workarounds (e.g. Radicale config).

---

## Quick Start

### Turnkey Setup (recommended)

```powershell
# 1. Clone the repository
git clone https://github.com/tylertech234/meetstack.git
cd meetstack

# 2. Run the bootstrap script — generates .env, starts containers,
#    seeds all services with test data, and pulls the LLM model.
.\scripts\bootstrap.ps1
```

The bootstrap script will:
- Copy `.env.example` → `.env` with freshly generated passwords
- Start all 10 containers and wait for them to become healthy
- Configure Nginx Proxy Manager with proxy hosts for every service
- Create an admin account (`admin@meetstack.local` / `MeetStack2026!`) on
  n8n, Open WebUI, Wiki.js, and Vikunja
- Seed Wiki.js with starter pages, Vikunja with sample projects/tasks,
  and n8n with demo workflows
- Pull the default Ollama model (`tinyllama` or whichever is set in `.env`)
- Write credentials to `SECRETS.md` (git-ignored)

### Manual Setup

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

# 5. Pull the default LLM model
bash scripts/pull-model.sh
```

---

## Service URLs

After running the bootstrap script (or setting up NPM manually), services are
available through Nginx Proxy Manager using `.localhost` domains:

| Service | URL | Default Login |
|---|---|---|
| **Nginx Proxy Manager** admin | <http://localhost:8181> | `admin@example.com` / `changeme` (change on first login) |
| **n8n** | <http://n8n.localhost> | `admin@meetstack.local` / `MeetStack2026!` |
| **Open WebUI** (Ollama chat) | <http://chat.localhost> | `admin@meetstack.local` / `MeetStack2026!` |
| **Vikunja** (tasks) | <http://tasks.localhost> | `admin@meetstack.local` / `MeetStack2026!` |
| **Wiki.js** | <http://wiki.localhost> | `admin@meetstack.local` / `MeetStack2026!` |
| **Radicale** (CalDAV) | <http://calendar.localhost> | No auth (local use) |
| **Ollama API** | internal only | Consumed by Open WebUI & n8n |
| **Whisper API** | internal only | Consumed by n8n only |

> **Tip:** `.localhost` domains resolve to `127.0.0.1` on most systems. To
> access from other devices on your LAN, add entries to their `hosts` file
> pointing to your machine's IP, or use the NPM admin UI to add proxy hosts
> with your LAN IP.

---

## AI Agent Infrastructure

MeetStack includes a context-aware AI agent that can search the wiki, fetch
tasks, and generate answers using a local LLM. The agent pipeline runs entirely
through n8n webhooks — no external API calls.

### Architecture

```
User Question → n8n Agent Router → LLM keyword extraction
                                 → Wiki.js search (GraphQL)
                                 → Vikunja task fetch
                                 → Ollama LLM (RAG prompt)
                                 → JSON response
```

The agent first uses the LLM to extract search keywords from natural language
questions (so "What are the meeting minutes about?" becomes "meeting minutes"),
then searches Wiki.js with those keywords for relevant context.

### Webhooks

| Endpoint | Method | Purpose |
|---|---|---|
| `/webhook/agent` | POST | Ask the AI agent a question (RAG with wiki + tasks) |
| `/webhook/escalate` | POST | Create a high-priority Vikunja task for review |
| `/webhook/learn` | POST | Add a verified Q&A to the wiki knowledge base |

### Usage

```bash
# Ask the agent
curl -X POST http://n8n.localhost/webhook/agent \
  -H "Content-Type: application/json" \
  -d '{"message": "What are the latest meeting minutes about?"}'

# Escalate for review
curl -X POST http://n8n.localhost/webhook/escalate \
  -H "Content-Type: application/json" \
  -d '{"question": "Leave policy?", "user": "jsmith", "agent_response": "Not confident"}'  

# Teach the agent (adds to wiki)
curl -X POST http://n8n.localhost/webhook/learn \
  -H "Content-Type: application/json" \
  -d '{"question": "What is the onboarding process?", "answer": "New members complete orientation then..."}'  
```

### Model Selection

Set `OLLAMA_AGENT_MODEL` in `.env` or pass as an argument to `setup-agent.sh`.
If omitted, the script auto-detects VRAM and picks the best fit.

| GPU VRAM | Recommended Model | Speed | Notes |
|---|---|---|---|
| < 4 GB | `tinyllama` (1.1B) | ~30 tok/s | Basic, fast, limited quality |
| 4 GB | `llama3.2:3b` (2 GB) | ~15 tok/s | Good balance for GTX 1650 |
| 8–12 GB | `llama3.1:8b` (4.7 GB) | ~25 tok/s | **Recommended** — RTX 3060/4070, Tesla P100 |
| 16 GB+ | `llama3.1:13b` Q4 (7.4 GB) | ~15 tok/s | Best quality — P100 16GB, RTX 4090 |

### Setup

```bash
# Run the agent setup script (after bootstrap.ps1)
# Auto-detects your GPU and picks the best model
docker cp scripts/setup-agent.sh nginx-proxy-manager:/tmp/
docker exec nginx-proxy-manager bash /tmp/setup-agent.sh

# Or specify a model explicitly
docker exec nginx-proxy-manager bash /tmp/setup-agent.sh llama3.1:8b
```

---

## SBC Deployment Notes

When running on a Raspberry Pi 5 (8 GB) or similar ARM SBC:

- **LLM model:** Use `phi3:mini` (default) or `tinyllama` for the lightest
  footprint. Avoid `llama3` (8B) — it needs more RAM than the SBC has.
- **Whisper model:** Use `tiny` (default). The `base` model works on a laptop;
  `small`+ should only be used with a GPU.
- **Expect slower inference:** CPU-only LLM and Whisper will be noticeably
  slower than GPU-accelerated setups. Meeting transcription of a 30-minute
  recording may take several minutes with the `tiny` model.
- **Swap space:** Configure at least 2 GB of swap on the SBC to handle
  occasional memory spikes.
- **ARM images:** All images in this stack publish `linux/arm64` variants.

---

## GPU Passthrough — Ollama & NVIDIA GPU

To offload LLM inference to an NVIDIA GPU, follow these steps **inside WSL 2**
(or natively on Linux):

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
   ```

3. **Start the stack with GPU enabled** using the GPU override file:

   ```bash
   docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
   ```

   Alternatively, uncomment the `deploy.resources.reservations` block in
   `docker-compose.yml` directly.

---

## Directory Structure

```
meetstack/
├── docker-compose.yml        # Single compose file for all services
├── docker-compose.gpu.yml    # GPU override — adds NVIDIA passthrough
├── .env.example              # Template — copy to .env and fill in secrets
├── .gitignore
├── README.md
├── SECRETS.md                # Generated credentials (git-ignored)
├── services/
│   ├── n8n/                  # n8n bind-mount config & credentials
│   │   └── workflows/        # Workflow design docs & exported JSON
│   ├── ollama/               # Modelfiles, custom config for Ollama
│   ├── open-webui/           # Open WebUI config overrides
│   ├── vikunja/              # Vikunja config.yml overrides
│   ├── wikijs/               # Wiki.js config overrides
│   ├── radicale/             # Radicale CalDAV config
│   │   └── config            # Server configuration file
│   └── whisper/              # Whisper ASR documentation
├── nginx/
│   └── proxy.conf            # Additional Nginx snippets loaded by NPM
├── scripts/
│   ├── bootstrap.ps1         # Turnkey setup: .env, containers, test data
│   ├── setup-npm.ps1         # Configure NPM proxy hosts
│   ├── setup-wiki.sh         # Seed Wiki.js with starter pages
│   ├── setup-vikunja.sh      # Seed Vikunja with projects & tasks
│   ├── setup-n8n.sh          # Create n8n demo workflows
│   ├── setup-agent.sh        # Create AI agent workflows (RAG, escalation, learning)
│   ├── update-stack.sh       # Pull latest images, recreate, prune (bash)
│   ├── update-stack.ps1      # Pull latest images, recreate, prune (PowerShell)
│   ├── compact-docker-vhdx.ps1 # Shrink Docker WSL2 virtual disk (admin)
│   ├── backup.sh             # Dump all Docker volumes to tar archives
│   ├── restore.sh            # Restore a volume from a tar archive
│   └── pull-model.sh         # Pull the Ollama model from .env
└── backups/                  # Created by backup.sh (git-ignored)
```

---

## Notes

- **`.env` is never committed** — only `.env.example` is tracked by Git.
- All services have **health checks** — `docker compose ps` shows `healthy`
  status when services are ready. `depends_on` uses `condition: service_healthy`
  to ensure proper startup order.
- Named Docker volumes handle all persistent data. Back them up with
  `bash scripts/backup.sh` and restore with `bash scripts/restore.sh`.
- Use `docker compose logs -f <service>` to tail logs for a specific service.
