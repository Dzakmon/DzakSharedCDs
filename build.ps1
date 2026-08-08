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

# No Libs/ to copy — the addon is dependency-free by design. If that ever
# changes, add the folder copy and lib-asset stripping back here.

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
