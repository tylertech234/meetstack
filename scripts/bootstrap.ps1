<#
.SYNOPSIS
  Turnkey bootstrap for the MeetStack Docker Compose stack.
  Generates .env, starts containers, seeds all services with test data.

.DESCRIPTION
  Run from the repository root:  .\scripts\bootstrap.ps1

.NOTES
  Requires: Docker Desktop (WSL 2 backend), PowerShell 5.1+
#>

param(
    [switch]$SkipSeed,
    [switch]$ResetVolumes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $root

function Write-Step { param([string]$msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-OK   { param([string]$msg) Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "  WARN $msg" -ForegroundColor Yellow }

function New-Password([int]$len = 16) {
    $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    -join ((1..$len) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

function New-HexSecret([int]$bytes = 32) {
    -join ((1..$bytes) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })
}

# ── Pre-flight checks ─────────────────────────────────────────────────────
Write-Step "Pre-flight checks"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: docker not found. Install Docker Desktop first." -ForegroundColor Red
    exit 1
}
$dockerInfo = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Docker daemon not running. Start Docker Desktop first." -ForegroundColor Red
    exit 1
}
Write-OK "Docker is running"

if (-not (Test-Path "docker-compose.yml")) {
    Write-Host "ERROR: Run this script from the meetstack repository root." -ForegroundColor Red
    exit 1
}
Write-OK "Found docker-compose.yml"

# ── Generate .env ──────────────────────────────────────────────────────────
Write-Step "Environment file"

if (Test-Path ".env") {
    Write-Warn ".env already exists — keeping it. Delete .env and re-run to regenerate."
} else {
    if (-not (Test-Path ".env.example")) {
        Write-Host "ERROR: .env.example not found." -ForegroundColor Red
        exit 1
    }
    $env_content = Get-Content ".env.example" -Raw

    # Replace changeme placeholders with generated secrets
    $vikDbRoot  = New-Password
    $vikDbPw    = New-Password
    $vikJwt     = New-HexSecret
    $wikiDbPw   = New-Password
    $webuiKey   = New-HexSecret

    $env_content = $env_content `
        -replace 'VIKUNJA_DB_ROOT_PASSWORD=changeme_root',    "VIKUNJA_DB_ROOT_PASSWORD=$vikDbRoot" `
        -replace 'VIKUNJA_DB_PASSWORD=changeme_vikunja',      "VIKUNJA_DB_PASSWORD=$vikDbPw" `
        -replace 'VIKUNJA_JWT_SECRET=changeme_jwt_secret',    "VIKUNJA_JWT_SECRET=$vikJwt" `
        -replace 'WIKIJS_DB_PASSWORD=changeme_wikijs',        "WIKIJS_DB_PASSWORD=$wikiDbPw" `
        -replace 'WEBUI_SECRET_KEY=changeme_webui_secret',    "WEBUI_SECRET_KEY=$webuiKey"

    Set-Content -Path ".env" -Value $env_content -NoNewline
    Write-OK "Generated .env with secure passwords"
}

# ── Optional volume reset ─────────────────────────────────────────────────
if ($ResetVolumes) {
    Write-Step "Resetting volumes"
    docker compose down -v 2>&1 | Out-Null
    Write-OK "Volumes removed"
}

# ── Start containers ──────────────────────────────────────────────────────
Write-Step "Starting containers"
docker compose up -d 2>&1 | ForEach-Object { Write-Host "  $_" }

# ── Wait for all services to be healthy ───────────────────────────────────
Write-Step "Waiting for services to become healthy"
$services = @("n8n","ollama","open-webui","vikunja","vikunja-db","wikijs","wikijs-db","radicale","whisper","nginx-proxy-manager")
$maxWait = 300  # seconds
$start = Get-Date

while ($true) {
    $elapsed = ((Get-Date) - $start).TotalSeconds
    if ($elapsed -gt $maxWait) {
        Write-Host "ERROR: Timed out waiting for services after ${maxWait}s" -ForegroundColor Red
        docker compose ps
        exit 1
    }

    $allHealthy = $true
    $statusLine = @()
    foreach ($svc in $services) {
        $health = (docker inspect --format '{{.State.Health.Status}}' $svc 2>$null)
        if ($health -ne "healthy") { $allHealthy = $false }
        $statusLine += "$svc=$health"
    }

    if ($allHealthy) {
        Write-OK "All 10 services healthy"
        break
    }

    $pct = [math]::Min(100, [int]($elapsed / $maxWait * 100))
    Write-Host "  [$pct%] $($statusLine -join ', ')" -ForegroundColor Gray
    Start-Sleep -Seconds 10
}

if ($SkipSeed) {
    Write-Step "Skipping service seeding (-SkipSeed)"
    Pop-Location
    exit 0
}

# ── Configure Nginx Proxy Manager ─────────────────────────────────────────
Write-Step "Configuring Nginx Proxy Manager proxy hosts"
& "$root\scripts\setup-npm.ps1"

# ── Seed Wiki.js ──────────────────────────────────────────────────────────
Write-Step "Seeding Wiki.js"

# Wiki.js needs initial setup via the web UI on first boot — we access the
# GraphQL API. First we need to trigger the setup wizard completion.
# The setup-wiki.sh script handles login + page creation.
# We run it inside the NPM container which has curl and network access.
docker cp "$root\scripts\setup-wiki.sh" nginx-proxy-manager:/tmp/setup-wiki.sh 2>&1 | Out-Null
$wikiOut = docker exec nginx-proxy-manager bash /tmp/setup-wiki.sh 2>&1
$wikiOut | ForEach-Object { Write-Host "  $_" }
if ($wikiOut -match "complete") { Write-OK "Wiki.js seeded" } else { Write-Warn "Wiki.js seeding may have issues" }

# ── Setup Open WebUI ──────────────────────────────────────────────────────
Write-Step "Setting up Open WebUI"

# Create admin account
$signupBody = @{name="Admin"; email="admin@meetstack.local"; password="MeetStack2026!"} | ConvertTo-Json -Compress
try {
    $signupResp = Invoke-WebRequest -Uri "http://chat.localhost/api/v1/auths/signup" -Method Post -Body $signupBody -ContentType "application/json" -UseBasicParsing -ErrorAction SilentlyContinue
    Write-OK "Open WebUI admin account created"
} catch {
    Write-Warn "Open WebUI admin may already exist (this is fine)"
}

# ── Pull Ollama model ────────────────────────────────────────────────────
Write-Step "Pulling Ollama model"

# Read model from .env
$model = "tinyllama"
$envContent = Get-Content ".env" -ErrorAction SilentlyContinue
$modelLine = $envContent | Where-Object { $_ -match '^OLLAMA_MODEL=' }
if ($modelLine) {
    $model = ($modelLine -split '=', 2)[1].Trim('"', "'", ' ')
}
Write-Host "  Pulling model: $model (this may take a few minutes)" -ForegroundColor Gray
docker exec ollama ollama pull $model 2>&1 | ForEach-Object { Write-Host "  $_" }
Write-OK "Model $model pulled"

# ── Seed Vikunja ──────────────────────────────────────────────────────────
Write-Step "Seeding Vikunja"
docker cp "$root\scripts\setup-vikunja.sh" nginx-proxy-manager:/tmp/setup-vikunja.sh 2>&1 | Out-Null
$vikOut = docker exec nginx-proxy-manager bash /tmp/setup-vikunja.sh 2>&1
$vikOut | ForEach-Object { Write-Host "  $_" }
if ($vikOut -match "complete") { Write-OK "Vikunja seeded" } else { Write-Warn "Vikunja seeding may have issues" }

# ── Setup n8n ─────────────────────────────────────────────────────────────
Write-Step "Setting up n8n"
docker cp "$root\scripts\setup-n8n.sh" nginx-proxy-manager:/tmp/setup-n8n.sh 2>&1 | Out-Null
$n8nOut = docker exec nginx-proxy-manager bash /tmp/setup-n8n.sh 2>&1
$n8nOut | ForEach-Object { Write-Host "  $_" }
if ($n8nOut -match "complete") { Write-OK "n8n seeded" } else { Write-Warn "n8n seeding may have issues" }

# ── Generate SECRETS.md ──────────────────────────────────────────────────
Write-Step "Generating SECRETS.md"

$secretsContent = @"
# Meetstack — Local Credentials

> **DO NOT COMMIT THIS FILE.** It is listed in ``.gitignore``.

Generated by ``scripts/bootstrap.ps1`` on $(Get-Date -Format 'yyyy-MM-dd HH:mm').

---

## Service Logins

All seeded services use the same admin account:

- **Email:** ``admin@meetstack.local``
- **Password:** ``MeetStack2026!``

| Service | URL | Notes |
|---|---|---|
| **Nginx Proxy Manager** | http://localhost:81 | Default: ``admin@example.com`` / ``changeme`` (change on first login) |
| **n8n** | http://n8n.localhost | ``admin@meetstack.local`` / ``MeetStack2026!`` |
| **Open WebUI** | http://chat.localhost | ``admin@meetstack.local`` / ``MeetStack2026!`` |
| **Vikunja** | http://tasks.localhost | ``admin@meetstack.local`` / ``MeetStack2026!`` |
| **Wiki.js** | http://wiki.localhost | ``admin@meetstack.local`` / ``MeetStack2026!`` |
| **Radicale** | http://calendar.localhost | No auth (local use) |

## Database Credentials (internal only)

| Database | User | Password | Used by |
|---|---|---|---|
| MariaDB (Vikunja) | ``vikunja`` | *(see ``.env`` → ``VIKUNJA_DB_PASSWORD``)* | vikunja container |
| PostgreSQL (Wiki.js) | ``wikijs`` | *(see ``.env`` → ``WIKIJS_DB_PASSWORD``)* | wikijs container |

## Regenerating Secrets

```powershell
# Delete .env and volumes, then re-run bootstrap:
docker compose down -v
Remove-Item .env
.\scripts\bootstrap.ps1
```
"@

Set-Content -Path "SECRETS.md" -Value $secretsContent
Write-OK "SECRETS.md written"

# ── Summary ───────────────────────────────────────────────────────────────
Write-Step "Setup complete!"
Write-Host ""
Write-Host "  Service URLs:" -ForegroundColor White
Write-Host "    NPM Admin:    http://localhost:81"
Write-Host "    n8n:          http://n8n.localhost"
Write-Host "    Open WebUI:   http://chat.localhost"
Write-Host "    Vikunja:      http://tasks.localhost"
Write-Host "    Wiki.js:      http://wiki.localhost"
Write-Host "    Radicale:     http://calendar.localhost"
Write-Host ""
Write-Host "  Login:          admin@meetstack.local / MeetStack2026!" -ForegroundColor White
Write-Host "  Credentials:    See SECRETS.md" -ForegroundColor White
Write-Host ""

Pop-Location
