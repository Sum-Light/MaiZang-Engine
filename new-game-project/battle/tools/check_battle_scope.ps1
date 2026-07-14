[CmdletBinding()]
param(
    [string]$ProjectRoot = "",

    [ValidateSet("Staged", "Worktree", "All")]
    [string]$Mode = "Staged",

    [string]$GodotContractRoot = "",

    [switch]$RunRepositoryValidator
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battlePrefix = "new-game-project/battle/"
$trackedGdignore = @(
    "new-game-project/battle/local_data/source/.gdignore",
    "new-game-project/battle/local_data/normalized/.gdignore"
)
$blockedAssetExtensions = @(
    ".3ds", ".7z", ".aac", ".abc", ".aif", ".aiff", ".avi", ".blend",
    ".bmp", ".bz2", ".cab", ".cia", ".dae", ".dds", ".exr", ".fbx",
    ".flac", ".flv", ".gba", ".gif", ".glb", ".gltf", ".gz", ".hdr",
    ".icns", ".ico", ".iso", ".jpeg", ".jpg", ".ktx", ".lz", ".lz4",
    ".m4a", ".m4v", ".mesh", ".mid", ".midi", ".mkv", ".mov", ".mp3",
    ".mp4", ".nds", ".nsp", ".obj", ".ogg", ".opus", ".otf", ".pck",
    ".ply", ".png", ".psd", ".qoi", ".rar", ".rom", ".stl", ".svg",
    ".tar", ".tga", ".tif", ".tiff", ".ttf", ".usd", ".usda", ".usdc",
    ".usdz", ".wav", ".wbfs", ".webm", ".webp", ".wma", ".wmv", ".woff",
    ".woff2", ".xci", ".xcf", ".xz", ".zip", ".zst"
)
$governancePaths = @(
    ".codex/skills/maizang-engine-godot/references/project-state.md",
    "wiki/Battle-Development.md",
    "wiki/Change-Log.md",
    "wiki/Current-State.md"
)

function Invoke-GitLines {
    param([string[]]$Arguments)

    $output = @(& git -C $ProjectRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git $($Arguments -join ' ')`n$($output -join "`n")"
    }
    return @(
        $output |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Invoke-GitPaths {
    param([string[]]$Arguments)

    $output = @(& git -c core.quotepath=false -C $ProjectRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git $($Arguments -join ' ')`n$($output -join "`n")"
    }
    $rawOutput = @($output | ForEach-Object { [string]$_ }) -join "`n"
    return @(
        $rawOutput.Split([char[]]@([char]0), [StringSplitOptions]::RemoveEmptyEntries)
    )
}

function Write-PathGroup {
    param(
        [string]$Name,
        [string[]]$Paths
    )

    Write-Host "$Name ($($Paths.Count))"
    foreach ($path in $Paths) {
        Write-Host "  $path"
    }
}

function Test-ExactPathIn {
    param(
        [string]$Path,
        [string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        if ([string]::Equals($Path, $candidate, [StringComparison]::Ordinal)) {
            return $true
        }
    }
    return $false
}

function Get-OrdinalUniquePaths {
    param([string[]]$Paths)

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $result = [Collections.Generic.List[string]]::new()
    foreach ($path in $Paths) {
        if ($seen.Add($path)) {
            $result.Add($path)
        }
    }
    $array = $result.ToArray()
    [Array]::Sort($array, [StringComparer]::Ordinal)
    return $array
}

function Test-ReparsePath {
    param([string]$RelativePath)

    $fullPath = [IO.Path]::GetFullPath(
        (Join-Path $ProjectRoot $RelativePath.Replace('/', '\'))
    )
    $currentPath = $fullPath
    while ($currentPath.StartsWith($ProjectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $currentPath) {
            $item = Get-Item -LiteralPath $currentPath -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                return $true
            }
        }
        $parentPath = Split-Path -Parent $currentPath
        if ([string]::IsNullOrWhiteSpace($parentPath) -or $parentPath -eq $currentPath) {
            break
        }
        $currentPath = $parentPath
    }
    $indexEntry = @(& git -C $ProjectRoot ls-files -s -- $RelativePath)
    return @(
        $indexEntry |
            Where-Object { [string]$_ -notmatch '^100(644|755) ' }
    ).Count -gt 0
}

$gitRoot = (Invoke-GitLines @("rev-parse", "--show-toplevel") | Select-Object -First 1)
if ([IO.Path]::GetFullPath($gitRoot).TrimEnd('\') -ne $ProjectRoot) {
    throw "ProjectRoot is not the Git worktree root: $ProjectRoot"
}

$stagedPaths = @()
$stagedDeletedPaths = @()
$unstagedPaths = @()
$unstagedDeletedPaths = @()
$untrackedPaths = @()
if ($Mode -in @("Staged", "All")) {
    $stagedPaths = @(Invoke-GitPaths @(
        "diff", "--cached", "--name-only", "--no-renames", "--diff-filter=ACDMRTUXB", "-z", "--"
    ))
    $stagedDeletedPaths = @(Invoke-GitPaths @(
        "diff", "--cached", "--name-only", "--no-renames", "--diff-filter=D", "-z", "--"
    ))
}
if ($Mode -in @("Worktree", "All")) {
    $unstagedPaths = @(Invoke-GitPaths @(
        "diff", "--name-only", "--no-renames", "--diff-filter=ACDMRTUXB", "-z", "--"
    ))
    $unstagedDeletedPaths = @(Invoke-GitPaths @(
        "diff", "--name-only", "--no-renames", "--diff-filter=D", "-z", "--"
    ))
    $untrackedPaths = @(Invoke-GitPaths @(
        "ls-files", "--others", "--exclude-standard", "-z", "--"
    ))
}

$candidatePaths = @(Get-OrdinalUniquePaths @(
    @($stagedPaths) + @($unstagedPaths) + @($untrackedPaths) |
        ForEach-Object { ([string]$_).Replace('\', '/') } |
        ForEach-Object { $_ }
))
$nonDeletedPaths = @(Get-OrdinalUniquePaths @(
    @($stagedPaths | Where-Object { -not (Test-ExactPathIn $_ $stagedDeletedPaths) }) +
        @($unstagedPaths | Where-Object { -not (Test-ExactPathIn $_ $unstagedDeletedPaths) }) +
        @($untrackedPaths) |
        ForEach-Object { ([string]$_).Replace('\', '/') } |
        ForEach-Object { $_ }
))
$deletedPaths = @(Get-OrdinalUniquePaths @(
    @($stagedDeletedPaths) + @($unstagedDeletedPaths) |
        ForEach-Object { ([string]$_).Replace('\', '/') } |
        Where-Object { -not (Test-ExactPathIn $_ $nonDeletedPaths) }
))
$businessPaths = [Collections.Generic.List[string]]::new()
$governance = [Collections.Generic.List[string]]::new()
$violations = [Collections.Generic.List[string]]::new()

foreach ($path in $candidatePaths) {
    $isDeletion = Test-ExactPathIn $path $deletedPaths
    if (-not $isDeletion -and (Test-ReparsePath $path)) {
        $violations.Add("$path [symbolic link or reparse point]")
        continue
    }
    if ($path.StartsWith($battlePrefix, [StringComparison]::Ordinal)) {
        $isTrackedSentinel = Test-ExactPathIn $path $trackedGdignore
        $isLocalArtifact = $path.StartsWith(
            "new-game-project/battle/local_data/",
            [StringComparison]::OrdinalIgnoreCase
        ) -or $path.StartsWith(
            "new-game-project/battle/generated/",
            [StringComparison]::OrdinalIgnoreCase
        ) -or $path.StartsWith(
            "new-game-project/battle/.godot/",
            [StringComparison]::OrdinalIgnoreCase
        ) -or $path.StartsWith(
            "new-game-project/battle/exports/",
            [StringComparison]::OrdinalIgnoreCase
        )
        $isTemporary = $path -match '(^|/)(\.tmp|tmp|temp)/' -or
            $path -match '\.(tmp|temp|part)$'
        $isBlockedAsset = [IO.Path]::GetExtension($path).ToLowerInvariant() -in
            $blockedAssetExtensions
        if (-not $isDeletion -and (
            ($isLocalArtifact -and -not $isTrackedSentinel) -or
            $isTemporary -or
            $isBlockedAsset
        )) {
            $violations.Add("$path [local/generated/temporary/proprietary asset]")
            continue
        }
        $businessPaths.Add($path)
        continue
    }
    if (Test-ExactPathIn $path $governancePaths) {
        $governance.Add($path)
        continue
    }
    $violations.Add("$path [outside battle root and governance whitelist]")
}

Write-Host "Battle scope audit: $Mode"
Write-PathGroup "Staged paths" @($stagedPaths)
Write-PathGroup "Unstaged paths" @($unstagedPaths)
Write-PathGroup "Untracked paths" @($untrackedPaths)
Write-PathGroup "Deletion-only paths" @($deletedPaths)
Write-PathGroup "Battle business paths" @($businessPaths)
Write-PathGroup "Governance attachments" @($governance)
Write-PathGroup "Violations" @($violations)

if ($businessPaths.Count -eq 0) {
    throw "Battle scope audit found no battle business paths."
}
if ($violations.Count -gt 0) {
    throw "Battle scope audit rejected $($violations.Count) path(s)."
}

$assetGatePath = Join-Path $PSScriptRoot "check_battle_assets.ps1"
if (-not (Test-Path -LiteralPath $assetGatePath -PathType Leaf)) {
    throw "Battle asset gate was not found: $assetGatePath"
}
& $assetGatePath -ProjectRoot $ProjectRoot -Mode $Mode
if ($LASTEXITCODE -ne 0) {
    throw "Battle asset gate failed with exit code $LASTEXITCODE."
}

$p2StableIdPath = "new-game-project/battle/specs/id_manifests/battle_stable_ids.json"
$p2PresentationPath = "new-game-project/battle/specs/presentation/presentation_contracts.json"
function Test-GitObjectExists {
    param([Parameter(Mandatory = $true)][string]$ObjectSpec)

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & git -C $ProjectRoot cat-file -e $ObjectSpec 1>$null 2>$null
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return $exitCode -eq 0
}

function Test-P2ContractsRelevant {
    param([ValidateSet("Staged", "Worktree")][string]$ContractMode)

    foreach ($path in @($p2StableIdPath, $p2PresentationPath)) {
        if (Test-GitObjectExists -ObjectSpec "HEAD:$path") {
            return $true
        }
        if ($ContractMode -eq "Staged" -and
            (Test-GitObjectExists -ObjectSpec ":$path")) {
            return $true
        }
        if ($ContractMode -eq "Worktree" -and
            (Test-Path -LiteralPath (Join-Path $ProjectRoot $path.Replace('/', '\')) -PathType Leaf)) {
            return $true
        }
    }
    return $false
}

$p2ContractGatePath = Join-Path $PSScriptRoot `
    "battle_specs\validators\validate_p2_id_manifests.ps1"
$p2SpecGatePath = Join-Path $PSScriptRoot `
    "battle_specs\validators\validate_p2_spec_contracts.ps1"
$p2CompilerGatePath = Join-Path $PSScriptRoot `
    "battle_specs\compilers\compile_p2_specs.ps1"
$p2FixturePreflightGatePath = Join-Path $PSScriptRoot `
    "battle_specs\compilers\compile_p2_fixture_requirements.ps1"
$p2EvidenceJoinGatePath = Join-Path $PSScriptRoot `
    "battle_specs\compilers\compile_p2_source_evidence_join.ps1"
$p2ReleaseReferenceGatePath = Join-Path $PSScriptRoot `
    "battle_specs\compilers\validate_p2_release_references.ps1"
foreach ($contractMode in @("Staged", "Worktree")) {
    if ($contractMode -eq "Staged" -and $Mode -notin @("Staged", "All")) {
        continue
    }
    if ($contractMode -eq "Worktree" -and $Mode -notin @("Worktree", "All")) {
        continue
    }
    if (-not (Test-P2ContractsRelevant -ContractMode $contractMode)) {
        continue
    }
    if (-not (Test-Path -LiteralPath $p2ContractGatePath -PathType Leaf)) {
        throw "P2 ID/presentation contract gate was not found: $p2ContractGatePath"
    }
    & $p2ContractGatePath -ProjectRoot $ProjectRoot -Mode $contractMode
    if (-not (Test-Path -LiteralPath $p2SpecGatePath -PathType Leaf)) {
        throw "P2 strict spec contract gate was not found: $p2SpecGatePath"
    }
    & $p2SpecGatePath -ProjectRoot $ProjectRoot -Mode $contractMode
    if (-not (Test-Path -LiteralPath $p2CompilerGatePath -PathType Leaf)) {
        throw "P2 spec compiler gate was not found: $p2CompilerGatePath"
    }
    & $p2CompilerGatePath -ProjectRoot $ProjectRoot -Mode $contractMode
    if (-not (Test-Path -LiteralPath $p2FixturePreflightGatePath -PathType Leaf)) {
        throw (
            "P2 fixture requirement preflight gate was not found: " +
            $p2FixturePreflightGatePath
        )
    }
    & $p2FixturePreflightGatePath -ProjectRoot $ProjectRoot -Mode $contractMode
    if (-not (Test-Path -LiteralPath $p2EvidenceJoinGatePath -PathType Leaf)) {
        throw (
            "P2 source-evidence join gate was not found: " +
            $p2EvidenceJoinGatePath
        )
    }
    & $p2EvidenceJoinGatePath -ProjectRoot $ProjectRoot -Mode $contractMode
    if (-not (Test-Path -LiteralPath $p2ReleaseReferenceGatePath -PathType Leaf)) {
        throw (
            "P2 release-reference gate was not found: " +
            $p2ReleaseReferenceGatePath
        )
    }
    & $p2ReleaseReferenceGatePath -ProjectRoot $ProjectRoot `
        -Mode $contractMode -GodotContractRoot $GodotContractRoot
}

$dependencyGatePath = Join-Path $PSScriptRoot "check_battle_dependencies.ps1"
if (-not (Test-Path -LiteralPath $dependencyGatePath -PathType Leaf)) {
    throw "Battle dependency gate was not found: $dependencyGatePath"
}
if ($Mode -in @("Staged", "All")) {
    & $dependencyGatePath -ProjectRoot $ProjectRoot -Mode Staged
    if ($LASTEXITCODE -ne 0) {
        throw "Staged battle dependency gate failed with exit code $LASTEXITCODE."
    }
}
if ($Mode -in @("Worktree", "All")) {
    & $dependencyGatePath -ProjectRoot $ProjectRoot -Mode Worktree
    if ($LASTEXITCODE -ne 0) {
        throw "Worktree battle dependency gate failed with exit code $LASTEXITCODE."
    }
}

if ($RunRepositoryValidator) {
    $validatorPath = Join-Path $ProjectRoot "tools\validate_repository.ps1"
    if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
        throw "Repository validator was not found: $validatorPath"
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validatorPath `
        -ProjectRoot $ProjectRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Repository validator failed with exit code $LASTEXITCODE."
    }
}

Write-Host "BATTLE_SCOPE_OK"
