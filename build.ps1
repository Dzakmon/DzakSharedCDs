# build.ps1 — package DzakSharedCDs for CurseForge upload.
#
# CurseForge rejects zips whose files sit at the top level; everything
# must live inside a single root folder named after the addon. This
# script also excludes the reference addons we keep alongside the
# source (MiniCC, LuraMemorySync*, TerribleLuraHelper) and the local
# .claude / .git directories.
#
# Usage:
#   pwsh ./build.ps1            (from the addon folder)
# Output:
#   dist/DzakSharedCDs-<version>.zip
#
# To inspect before uploading, open the zip in Explorer and confirm the
# top entry is "DzakSharedCDs/" — not loose files.

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }

# --- Parse version from the .toc ---------------------------------------------
$tocPath = Join-Path $root 'DzakSharedCDs.toc'
if (-not (Test-Path $tocPath)) { throw "Missing $tocPath; run this from the addon root." }

$version = $null
foreach ($line in Get-Content $tocPath) {
    if ($line -match '^##\s*Version:\s*(.+)$') {
        $version = $Matches[1].Trim()
        break
    }
}
if (-not $version) { throw "Couldn't find '## Version:' in $tocPath" }
Write-Host "Packaging DzakSharedCDs v$version"

# --- Build a clean staging tree ----------------------------------------------
# dist/staging/DzakSharedCDs/  <-- this folder becomes the zip's root entry.
$distDir   = Join-Path $root 'dist'
$staging   = Join-Path $distDir 'staging'
$pkgRoot   = Join-Path $staging 'DzakSharedCDs'

if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Force -Path $pkgRoot | Out-Null

# Whitelist: only ship these. Reference addons / IDE config / dist / .git
# are left out because they aren't listed here.
$topLevelFiles = @('DzakSharedCDs.toc', 'README.md') +
                 (Get-ChildItem -Path $root -Filter '*.lua' -File | ForEach-Object { $_.Name })

foreach ($name in $topLevelFiles) {
    $src = Join-Path $root $name
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $pkgRoot
    }
}

$dirs = @('Libs')
foreach ($name in $dirs) {
    $src = Join-Path $root $name
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $pkgRoot -Recurse
    }
}

# --- Strip documentation assets from bundled libs ----------------------------
# NoobTaco-Config ships ~12 MB of PNG screenshots, fonts use ~750 KB, and the
# nested LICENSE / CHANGELOG / README files add up. None are loaded at runtime,
# so they're dead weight in the distributed zip. We exclude:
#   - Screenshots/ folders (NoobTaco's CurseForge gallery)
#   - *.md / *.txt / LICENSE / LICENSE.txt / License.txt
#   - AI_USAGE.md
# Fonts and Textures STAY because Theme.lua references them at runtime.
$libsRoot = Join-Path $pkgRoot 'Libs'
$junkDirs = @('Screenshots')
foreach ($pattern in $junkDirs) {
    Get-ChildItem -Path $libsRoot -Recurse -Directory -Filter $pattern -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -Recurse -Force $_.FullName }
}
$junkFiles = @('*.md', 'LICENSE', 'LICENSE.txt', 'License.txt', 'AI_USAGE.md')
foreach ($pattern in $junkFiles) {
    Get-ChildItem -Path $libsRoot -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -Force $_.FullName }
}

# --- Zip it ------------------------------------------------------------------
# Compress-Archive with -Path pointing at a directory includes the
# directory itself as the zip's top entry — exactly what CurseForge wants.
$zipPath = Join-Path $distDir "DzakSharedCDs-$version.zip"
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path $pkgRoot -DestinationPath $zipPath

Remove-Item -Recurse -Force $staging

# --- Report ------------------------------------------------------------------
$zipInfo = Get-Item $zipPath
$sizeKB  = [math]::Round($zipInfo.Length / 1KB, 1)
Write-Host ""
Write-Host "  Output: $zipPath  ($sizeKB KB)"
Write-Host ""
Write-Host "  Verify with: " -NoNewline
Write-Host "Expand-Archive -Path '$zipPath' -DestinationPath dist/_verify -Force" -ForegroundColor DarkGray
Write-Host "             then list dist/_verify and check the top entry is DzakSharedCDs/"
