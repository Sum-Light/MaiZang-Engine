[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [switch]$Stage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Get-Sha256Text {
    param([string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ForwardRelativePath {
    param([string]$FullPath)

    $relative = [IO.Path]::GetFullPath($FullPath).Substring($ProjectRoot.Length).TrimStart('\')
    return $relative.Replace('\', '/')
}

function Test-MemoryInputPath {
    param([string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/')
    $excludedPrefixes = @(
        ".git/",
        ".agents/",
        ".work/",
        ".wiki-sync/",
        "generated/",
        "new-game-project/.godot/",
        "new-game-project/assets/platinum/",
        "new-game-project/captures/"
    )
    foreach ($prefix in $excludedPrefixes) {
        if ($normalized.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $normalized -notin @(
        "wiki/Current-State.md",
        ".codex/skills/maizang-engine-godot/references/project-state.md"
    )
}

$insideGit = $false
$branch = "not-initialized"
$candidatePaths = @()
$gitProbe = ""
if (Test-Path -LiteralPath (Join-Path $ProjectRoot ".git\HEAD") -PathType Leaf) {
    $gitProbe = & git -C $ProjectRoot rev-parse --is-inside-work-tree 2>$null
}
if ($gitProbe -eq "true") {
    $insideGit = $true
    $branchOutput = & git -C $ProjectRoot branch --show-current
    if (-not [string]::IsNullOrWhiteSpace($branchOutput)) {
        $branch = $branchOutput.Trim()
    }
    $candidatePaths = @(& git -C $ProjectRoot ls-files --cached --others --exclude-standard)
}
else {
    $candidatePaths = @(
        Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force |
            ForEach-Object { Get-ForwardRelativePath $_.FullName }
    )
}

$inputPaths = @(
    $candidatePaths |
        Where-Object { Test-MemoryInputPath $_ } |
        Sort-Object -Unique
)
$fingerprintInput = [Text.StringBuilder]::new()
foreach ($relativePath in $inputPaths) {
    $fullPath = Join-Path $ProjectRoot $relativePath.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        continue
    }
    $fileHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $null = $fingerprintInput.Append($relativePath).Append("|").Append($fileHash).AppendLine()
}
$sourceFingerprint = Get-Sha256Text $fingerprintInput.ToString()

$godotRoot = Join-Path $ProjectRoot "new-game-project"
$assetRoot = Join-Path $godotRoot "assets\platinum"
$matrixRoot = Join-Path $assetRoot "matrix_0000"
$manifestPath = Join-Path $matrixRoot "manifest.json"
$catalogPath = Join-Path $assetRoot "matrix_catalog.json"
$localAssetsPresent = (Test-Path -LiteralPath $manifestPath -PathType Leaf) -and
    (Test-Path -LiteralPath $catalogPath -PathType Leaf)
$localGlbs = 0
$localPngFiles = 0
$localUniqueTextures = 0
$localMaterials = 0
$localCells = 0
$localBuildings = 0
$localSourceMatrices = 0
$localReadyMatrices = 0
$localReadyDestinations = 0
$localUnresolvedMatrices = 0
$localTerrainAssets = 0
$localBuildingAssets = 0
if ($localAssetsPresent) {
    $catalog = [IO.File]::ReadAllText($catalogPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $localGlbs = [int]$catalog.summary.destination_scoped_glbs
    $localPngFiles = @(
        Get-ChildItem -LiteralPath $assetRoot -Recurse -Filter "*.png" -File |
            Where-Object { $_.FullName -like "*\shared\textures\*" }
    ).Count
    $localUniqueTextures = [int]$catalog.summary.unique_textures
    $localMaterials = @(Get-ChildItem -LiteralPath (Join-Path $assetRoot "shared_materials") -Filter "*.tres" -File).Count
    $localCells = [int]$catalog.summary.occupied_cells
    $localBuildings = [int]$catalog.summary.building_instances
    $localSourceMatrices = [int]$catalog.summary.source_matrices
    $localReadyMatrices = [int]$catalog.summary.ready_matrices
    $localReadyDestinations = [int]$catalog.summary.ready_destinations
    $localUnresolvedMatrices = [int]$catalog.summary.unresolved_matrices
    $localTerrainAssets = [int]$catalog.summary.unique_terrain_assets
    $localBuildingAssets = [int]$catalog.summary.unique_building_assets
}

$godotScripts = @(Get-ChildItem -LiteralPath (Join-Path $godotRoot "scripts") -Filter "*.gd" -File -ErrorAction SilentlyContinue).Count
$godotTests = @(Get-ChildItem -LiteralPath (Join-Path $godotRoot "tests") -Filter "*.gd" -File -ErrorAction SilentlyContinue).Count
$powershellTools = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "tools") -Filter "*.ps1" -File).Count
$assetStatus = if ($localAssetsPresent) {
    "catalog present locally (ignored by Git)"
}
else {
    "not present; rebuild from a local DSPRE project"
}
$playerSpritePath = Join-Path $assetRoot "characters\dawn_overworld.png"
$playerSpriteStatus = if (Test-Path -LiteralPath $playerSpritePath -PathType Leaf) {
    "present locally (ignored by Git)"
}
else {
    "not present; run tools/import_player_sprite.ps1"
}

$currentState = @"
# Current State

<!-- Generated by tools/update_project_memory.ps1. Do not edit by hand. -->

## Repository

- Branch: ``$branch``
- Source fingerprint: ``$sourceFingerprint``
- Fingerprinted files: $($inputPaths.Count)
- Godot runtime scripts: $godotScripts
- Godot test scripts: $godotTests
- PowerShell tools: $powershellTools

## Runtime Baseline

- Godot target: 4.7 stable, compatibility renderer.
- Display: one fixed ``256 x 192`` NDS screen at 4:3.
- Player: half-integer-centered one-unit grid steps at ``60 Hz``; walk ``16`` ticks, ``Z`` run ``8`` ticks, stationary turn ``6`` ticks.
- Camera: orthographic size ``11.24`` by default; ``F1`` toggles FOV-75 perspective.
- Camera transform: orthographic distance ``16``, perspective distance ``8``, yaw ``0``, pitch ``50``, wheel step ``5``.
- Main matrix: ``0000`` (``30 x 30`` with 468 occupied cells).
- Matrix catalog: $localSourceMatrices source matrices, $localReadyMatrices ready matrices, $localReadyDestinations runnable destinations, and $localUnresolvedMatrices unresolved source records.
- Debug destination: ``F2`` validates an in-game selection and reloads the main scene through a one-shot process-local request.
- Global asset variants: $localTerrainAssets terrain and $localBuildingAssets building/texture pairs.
- Building instances across ready matrices: $localBuildings.
- Shared resources: $localUniqueTextures unique texture hashes and $localMaterials external materials.
- Streaming: radius 1 active, radius 2 prefetch, radius 3 retention.
- Coordinates: 32 world units per cell, 0.5 per altitude unit, model scale ``1 / 16``.

## Local Asset Cache

- Status: $assetStatus.
- Occupied cells across ready matrices: $localCells
- Destination-scoped GLBs: $localGlbs
- Destination-scoped PNG files: $localPngFiles
- Unique texture hashes: $localUniqueTextures
- Shared materials found: $localMaterials
- Building instances found: $localBuildings
- Dawn sprite atlas: $playerSpriteStatus.

## Next Engineering Milestone

Integrate ``a.dat`` tile behavior and ``h.bhc`` height/collision data without
coupling the collision cache to rendered scene lifetime.
"@

$skillState = @"
# Project State

Generated by ``tools/update_project_memory.ps1``. Read this before modifying
MaiZang Engine and regenerate it in every functional commit.

- Branch: ``$branch``
- Source fingerprint: ``$sourceFingerprint``
- Runtime: Godot 4.7 compatibility renderer.
- Display: one fixed ``256 x 192`` NDS screen at 4:3.
- Player: half-integer-centered one-unit grid steps at ``60 Hz``; walk ``16`` ticks, ``Z`` run ``8`` ticks, stationary turn ``6`` ticks.
- Camera: size-11.24 orthographic default, ``F1`` FOV-75 perspective debug view.
- Camera transform: orthographic distance ``16``, perspective distance ``8``, yaw ``0``, pitch ``50``, wheel step ``5``.
- World: $localReadyMatrices ready matrices exposed through $localReadyDestinations debug destinations, with $localUnresolvedMatrices unresolved source records; matrix ``0000`` remains the default.
- Debug destination: ``F2`` opens the validated in-game selector and crosses a complete scene-reload boundary.
- Assets: $localGlbs destination-scoped GLBs, $localUniqueTextures unique texture hashes, and $localMaterials shared materials.
- Streaming: ``3 x 3`` active, ``5 x 5`` prefetch, radius-3 retention.
- Scale: cell 32, altitude step 0.5, imported model scale ``1 / 16``.
- Local asset cache: $assetStatus.
- Dawn sprite atlas: $playerSpriteStatus.
- Next milestone: ``a.dat`` behavior plus ``h.bhc`` height and collision.

The public repository must not contain ROM-derived models, textures, maps, or
other proprietary Pokemon assets.
"@

$currentStatePath = Join-Path $ProjectRoot "wiki\Current-State.md"
$skillStatePath = Join-Path $ProjectRoot ".codex\skills\maizang-engine-godot\references\project-state.md"
New-Item -ItemType Directory -Path (Split-Path -Parent $currentStatePath) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $skillStatePath) -Force | Out-Null
[IO.File]::WriteAllText($currentStatePath, $currentState.TrimEnd() + "`n", $utf8NoBom)
[IO.File]::WriteAllText($skillStatePath, $skillState.TrimEnd() + "`n", $utf8NoBom)

if ($Stage) {
    if (-not $insideGit) {
        throw "Cannot stage project memory before the repository is initialized."
    }
    & git -C $ProjectRoot add -- "wiki/Current-State.md" ".codex/skills/maizang-engine-godot/references/project-state.md"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not stage generated project memory."
    }
}

Write-Host "Project memory updated."
Write-Host "  Fingerprint: $sourceFingerprint"
Write-Host "  Files:       $($inputPaths.Count)"
Write-Host "  Wiki:        $currentStatePath"
Write-Host "  Skill:       $skillStatePath"
