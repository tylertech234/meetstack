<#
.SYNOPSIS
    Compacts the Docker Desktop WSL2 VHDX to reclaim unused disk space.
    Must be run as Administrator.

.DESCRIPTION
    WSL2's ext4.vhdx grows when data is written but never auto-shrinks.
    This script shuts down WSL, compacts the VHDX via diskpart, then
    shows the before/after size.

.EXAMPLE
    Right-click this file -> "Run with PowerShell" (as Admin)
    Or from an elevated terminal: .\scripts\compact-docker-vhdx.ps1
#>
$ErrorActionPreference = "Stop"

# Ensure running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell -> 'Run as administrator', then run this script." -ForegroundColor Yellow
    pause
    exit 1
}

$vhdxPath = "$env:LOCALAPPDATA\Docker\wsl\data\ext4.vhdx"

if (-not (Test-Path $vhdxPath)) {
    Write-Host "ERROR: VHDX not found at: $vhdxPath" -ForegroundColor Red
    pause
    exit 1
}

$sizeBefore = [math]::Round((Get-Item $vhdxPath).Length / 1GB, 2)
Write-Host ""
Write-Host "Docker WSL2 VHDX Compaction" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan
Write-Host "File:   $vhdxPath"
Write-Host "Before: $sizeBefore GB"
Write-Host ""

# Shut down WSL
Write-Host ">> Shutting down WSL..." -ForegroundColor Yellow
wsl --shutdown
Start-Sleep -Seconds 3

# Create diskpart script
$diskpartScript = @"
select vdisk file="$vhdxPath"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@
$tempScript = "$env:TEMP\compact-docker-vhdx.txt"
$diskpartScript | Set-Content -Path $tempScript -Encoding ASCII

# Run diskpart
Write-Host ">> Compacting VHDX (this may take a few minutes)..." -ForegroundColor Yellow
diskpart /s $tempScript

# Show results
$sizeAfter = [math]::Round((Get-Item $vhdxPath).Length / 1GB, 2)
$saved = [math]::Round($sizeBefore - $sizeAfter, 2)

Write-Host ""
Write-Host "===========================" -ForegroundColor Green
Write-Host "Before: $sizeBefore GB" -ForegroundColor White
Write-Host "After:  $sizeAfter GB" -ForegroundColor Green
Write-Host "Saved:  $saved GB" -ForegroundColor Green
Write-Host "===========================" -ForegroundColor Green
Write-Host ""
Write-Host "Start Docker Desktop to bring containers back up."

# Clean up
Remove-Item $tempScript -ErrorAction SilentlyContinue
pause
