<#
.SYNOPSIS
  pi-fast: bundle the npm-installed pi coding agent into a single file for fast startup.

.DESCRIPTION
  Run this script anytime - it is idempotent:
    - installs pi if missing, upgrades it if a newer version exists on npm
      (skip with -NoUpdate), rebuilds the single-file bundle, regenerates
      the launch shims, and verifies everything
  Rollback: delete pi / pi.cmd in the shim dir and the whole install dir.

.PARAMETER InstallDir
  Where the bundle lives. Default: existing D:\pi-dist, else %LOCALAPPDATA%\pi-dist

.PARAMETER ShimDir
  Where the pi / pi.cmd launchers go. Must be on PATH; the script warns if not.
  Default: %USERPROFILE%\.local\bin

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File pi-fast.ps1
#>
param(
    [string]$InstallDir = $(if (Test-Path "D:\pi-dist") { "D:\pi-dist" } else { "$env:LOCALAPPDATA\pi-dist" }),
    [string]$ShimDir = "$env:USERPROFILE\.local\bin",
    [switch]$NoUpdate
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------- 1. locate npm + pi
$npmRoot = (npm root -g 2>$null | Select-Object -First 1)
if (-not $npmRoot -or -not (Test-Path $npmRoot)) {
    Write-Error "npm not found on PATH. Install Node.js (LTS) first: https://nodejs.org"
}
$npmRoot = $npmRoot.Trim()
$pkgDir = Join-Path $npmRoot "@earendil-works\pi-coding-agent"
$pkgJson = Join-Path $pkgDir "package.json"

if (-not (Test-Path (Join-Path $pkgDir "dist\cli.js"))) {
    Write-Host "pi is not installed yet - installing latest..."
    npm install -g --ignore-scripts "@earendil-works/pi-coding-agent"
    if ($LASTEXITCODE -ne 0) { Write-Error "npm install of pi failed" }
}

# ---------------------------------------------------------------- 2. optional upgrade
$installed = (Get-Content $pkgJson -Raw | ConvertFrom-Json).version
if (-not $NoUpdate) {
    $latest = $null
    try { $latest = (npm view "@earendil-works/pi-coding-agent" version 2>$null | Select-Object -First 1) } catch {}
    if ($latest) { $latest = $latest.Trim() }
    if ($latest -and $latest -ne $installed) {
        Write-Host "New version on npm: $installed -> $latest  (upgrading...)"
        npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@latest"
        if ($LASTEXITCODE -ne 0) { Write-Error "npm upgrade failed" }
        $installed = (Get-Content $pkgJson -Raw | ConvertFrom-Json).version
    } elseif ($latest) {
        Write-Host "pi $installed is already the latest on npm."
    } else {
        Write-Host "(could not reach npm registry - skipping update check, rebuilding from $installed)"
    }
}

# ---------------------------------------------------------------- 3. bundle
Write-Host "Bundling pi $installed -> $InstallDir\pi-single.mjs"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

$entry = Join-Path $pkgDir "dist\cli.js"
$banner = "import { createRequire as __piCr } from 'module';var require = __piCr(import.meta.url);"

# Native .node modules cannot be bundled - they stay external on disk.
# Pick the clipboard native build by node's own arch (same rule npm uses for
# optionalDependencies; correct even on ARM64 machines running x64 node)
$nodeArch = (& node -p "process.arch").Trim()
$clip = "@mariozechner/clipboard-win32-x64-msvc"
if ($nodeArch -eq "arm64") { $clip = "@mariozechner/clipboard-win32-arm64-msvc" }
$extArgs = @("--external:@earendil-works/pi-tui", "--external:$clip")

npx -y esbuild $entry --bundle --platform=node --format=esm "--banner:js=$banner" $extArgs `
    "--outfile=$(Join-Path $InstallDir 'pi-single.mjs')" --log-level=error
if ($LASTEXITCODE -ne 0) { Write-Error "esbuild bundling failed" }

# ---------------------------------------------------------------- 4. copy runtime externals
# pi-tui + native clipboard + packages that user extensions resolve at runtime via jiti.
$nested = Join-Path $pkgDir "node_modules"
$targets = @(
    "@earendil-works/pi-tui",
    "@earendil-works/pi-agent-core",
    "@earendil-works/pi-ai",
    "@earendil-works/pi-telemetry",
    $clip,
    "marked",
    "get-east-asian-width",
    "typebox",
    "diff",
    "ignore",
    "yaml"
)
foreach ($t in $targets) {
    $src = Join-Path $nested $t
    if (-not (Test-Path $src)) { Write-Host "  (skip, not present in install: $t)"; continue }
    $dst = Join-Path $InstallDir "node_modules\$t"
    # robocopy /MIR: identical files are skipped, so this works even while
    # a pi session is running (loaded .node files stay locked on Windows)
    robocopy $src $dst /MIR /NJH /NJS /NDL /NFL /R:0 /W:0 | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Warning "robocopy failed for ${t} (exit $LASTEXITCODE)" }
}

# Freeze marker: which version this bundle actually is
Set-Content -Path (Join-Path $InstallDir "pi-single.version") -Value $installed -Encoding ASCII

# ---------------------------------------------------------------- 5. regenerate shims
New-Item -ItemType Directory -Force -Path $ShimDir | Out-Null

$cmdShim = Join-Path $ShimDir "pi.cmd"
@"
@echo off
setlocal
rem pi fast launcher - generated by pi-fast.ps1. Rollback: delete this file.
if not defined PI_OFFLINE set PI_OFFLINE=1
set "PI_PACKAGE_DIR=$pkgDir"
node "$InstallDir\pi-single.mjs" `%*
"@ | Set-Content -Path $cmdShim -Encoding ASCII
Write-Host "Shim updated: $cmdShim"

$shShim = Join-Path $ShimDir "pi"
@"
#!/bin/sh
# pi fast launcher (Git Bash) - generated by pi-fast.ps1. Rollback: delete this file.
if [ -z "`$PI_OFFLINE" ]; then PI_OFFLINE=1; export PI_OFFLINE; fi
PI_PACKAGE_DIR='$($pkgDir -replace '\\','\\')'
export PI_PACKAGE_DIR
exec node '$($InstallDir -replace '\\','\\')\pi-single.mjs' "`$@"
"@ | Set-Content -Path $shShim -Encoding ASCII
Write-Host "Shim updated: $shShim"

# ---------------------------------------------------------------- 6. verify
Write-Host ""
Write-Host "=== verification ===" -ForegroundColor Cyan

$env:PI_PACKAGE_DIR = $pkgDir   # shims set this too; mirror real usage for the check
$bundleVer = (& node (Join-Path $InstallDir "pi-single.mjs") --version 2>$null | Select-Object -First 1)
if ($bundleVer -eq $installed) {
    Write-Host "[ok] bundle runs and reports version $installed"
} else {
    Write-Warning "bundle reported '$bundleVer' but npm package is $installed - re-run this script."
}

# PATH order: does OUR shim win when Windows resolves 'pi'? (PATHEXT rules:
# extensionless sh scripts are never chosen by CreateProcess - ignore them)
$firstHit = (cmd /c "where pi" 2>$null | Where-Object { $_ -match '\.(cmd|bat|exe)$' } | Select-Object -First 1)
if ($firstHit -and $firstHit.Trim() -ieq $cmdShim) {
    $t = (Measure-Command { cmd /c "pi --version" | Out-Null }).TotalSeconds
    Write-Host ("[ok] 'pi' resolves to the fast shim, --version takes {0:N2}s" -f $t)
} else {
    Write-Warning "shim $cmdShim is not first on PATH for 'pi' (found: $firstHit)."
    Write-Host "  Fix: move $ShimDir ahead of the other pi location in PATH."
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ';') -notcontains $ShimDir) {
    Write-Warning "$ShimDir is not in your user PATH."
    Write-Host "  Fix (run once):"
    Write-Host "  [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User')+';$ShimDir','User')"
}

Write-Host ""
Write-Host "Frozen pi version : $installed  (marker: $InstallDir\pi-single.version)"
Write-Host "To update later   : re-run this script (it upgrades npm package + rebuilds together)"
Write-Host "Temporary online  : set PI_OFFLINE to empty before launching"
Write-Host "Rollback          : delete $cmdShim, $shShim and $InstallDir"
