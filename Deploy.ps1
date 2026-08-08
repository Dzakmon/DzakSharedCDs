# Deploy.ps1 — mirror the current repo into the WoW AddOns folder.
#
# Usage: .\Deploy.ps1
#
# robocopy /MIR mirrors the source — files removed from the repo also get
# removed from the installed addon on the next deploy. Excluded paths
# (dev metadata, build output, reference addons listed in .gitignore) are
# left untouched in both source and destination.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---------- paths ----------

$repoRoot  = Split-Path -Parent $PSCommandPath
$addonsDir = 'C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns'
$destDir   = Join-Path $addonsDir 'DzakSharedCDs'

if (-not (Test-Path $addonsDir)) {
    Write-Error "AddOns folder not found: $addonsDir"
    exit 1
}

# ---------- read version from TOC ----------

$tocPath = Join-Path $repoRoot 'DzakSharedCDs.toc'
$version = '?'
if (Test-Path $tocPath) {
    $match = Select-String -Path $tocPath -Pattern '^## Version:\s*(.+)$' | Select-Object -First 1
    if ($match) { $version = $match.Matches.Groups[1].Value.Trim() }
}

Write-Host "Deploying DzakSharedCDs v$version" -ForegroundColor Cyan
Write-Host "  from: $repoRoot"
Write-Host "  to:   $destDir"

# ---------- excludes (mirror .gitignore + dev metadata) ----------

# Directories: full paths so robocopy matches unambiguously.
$excludeDirs = @(
    '.git',
    '.claude',
    '.vscode',
    'dist',                  # build output (.gitignore)
    'PetesDefensiveHistory', # reference addon (.gitignore)
    'BliZzi_Interrupts'      # reference addon (.gitignore)
) | ForEach-Object { Join-Path $repoRoot $_ } | Where-Object { Test-Path $_ }

# Files: matched by name.
$excludeFiles = @(
    'Deploy.ps1',
    'build.ps1',
    '.gitignore',
    '.gitattributes',
    '*.md'
)

# ---------- run robocopy ----------

$robocopyArgs = @(
    $repoRoot,
    $destDir,
    '/MIR',
    '/NFL', '/NDL', '/NJH', '/NJS', '/NP'
)
if ($excludeDirs.Count -gt 0)  { $robocopyArgs += '/XD'; $robocopyArgs += $excludeDirs }
if ($excludeFiles.Count -gt 0) { $robocopyArgs += '/XF'; $robocopyArgs += $excludeFiles }

& robocopy @robocopyArgs | Out-Null

# robocopy exit codes: 0–7 indicate success (0 = no-op, 1 = files copied,
# 2 = extra files removed, etc., bitmask). 8+ is failure.
if ($LASTEXITCODE -ge 8) {
    Write-Error "robocopy failed (exit $LASTEXITCODE)."
    exit 1
}

Write-Host "Done. /reload in-game to pick up the changes." -ForegroundColor Green
