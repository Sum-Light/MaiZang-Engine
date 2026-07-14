[CmdletBinding()]
param(
    [string]$ProjectRoot = "",

    [ValidateSet("Repository", "Worktree", "Staged")]
    [string]$Mode = "Repository",

    [string]$StableIdManifestPath = "",
    [string]$PresentationManifestPath = "",
    [string]$BaselineStableIdManifestPath = "",
    [string]$BaselinePresentationManifestPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "p2_id_manifest_support.ps1")

$stableRelativePath = (
    "new-game-project/battle/specs/id_manifests/battle_stable_ids.json"
)
$presentationRelativePath = (
    "new-game-project/battle/specs/presentation/presentation_contracts.json"
)

function Test-P2PathProvided {
    param([AllowEmptyString()][string]$Path)

    return -not [string]::IsNullOrWhiteSpace($Path)
}

function Resolve-P2InputPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $Root $Path))
}

function ConvertFrom-P2ManifestBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Bytes.Length -gt 524288) {
        throw "P2_MANIFEST_TOO_LARGE: $Label exceeds the 524288-byte limit."
    }
    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    try {
        $text = $strictUtf8.GetString($Bytes)
    }
    catch {
        throw "P2_MANIFEST_UTF8: $Label is not valid strict UTF-8."
    }
    return ConvertFrom-BattleStrictJson -Text $text -Label $Label
}

function Read-P2ManifestFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "P2_MANIFEST_NOT_FOUND: $Label was not found: $fullPath"
    }
    $bytes = [IO.File]::ReadAllBytes($fullPath)
    return ConvertFrom-P2ManifestBytes -Bytes $bytes -Label $Label
}

function Invoke-P2GitBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Arguments
    )

    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        throw "P2_GIT_NOT_FOUND: Git is required for mode $Mode."
    }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $gitCommand.Source
    $escapedRoot = $Root.Replace('"', '\"')
    $startInfo.Arguments = '-C "{0}" {1}' -f $escapedRoot, $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $memory = [IO.MemoryStream]::new()
    try {
        if (-not $process.Start()) {
            throw "P2_GIT_START: Git could not be started."
        }
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $process.WaitForExit()
        $errorText = $errorTask.Result.Trim()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Bytes = $memory.ToArray()
            ErrorText = $errorText
        }
    }
    finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

function Assert-P2GitRepositoryRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $result = Invoke-P2GitBytes -Root $Root `
        -Arguments "rev-parse --show-toplevel"
    if ($result.ExitCode -ne 0) {
        throw (
            "P2_GIT_ROOT: ProjectRoot is not a readable Git worktree" +
            $(if ($result.ErrorText.Length -gt 0) {
                ": $($result.ErrorText)"
            } else {
                "."
            })
        )
    }
    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    try {
        $reportedRoot = $strictUtf8.GetString([byte[]]$result.Bytes).Trim()
    }
    catch {
        throw "P2_GIT_ROOT_UTF8: Git returned a non-UTF-8 worktree root."
    }
    $resolvedReportedRoot = [IO.Path]::GetFullPath($reportedRoot).TrimEnd('\')
    $resolvedRequestedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if (-not $resolvedReportedRoot.Equals(
        $resolvedRequestedRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw (
            "P2_GIT_ROOT_MISMATCH: Git top-level '$resolvedReportedRoot' " +
            "does not equal ProjectRoot '$resolvedRequestedRoot'."
        )
    }
}

function Test-P2GitObjectExists {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ObjectSpec
    )

    $escapedSpec = $ObjectSpec.Replace('"', '\"')
    $result = Invoke-P2GitBytes -Root $Root -Arguments (
        'rev-parse --verify --quiet "{0}"' -f $escapedSpec
    )
    if ($result.ExitCode -eq 1) {
        return $false
    }
    if ($result.ExitCode -ne 0) {
        throw (
            "P2_GIT_VERIFY: Git object '$ObjectSpec' could not be verified" +
            $(if ($result.ErrorText.Length -gt 0) {
                ": $($result.ErrorText)"
            } else {
                "."
            })
        )
    }
    return $true
}

function Get-P2GitBlobBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ObjectSpec,
        [switch]$AllowMissing
    )

    $escapedSpec = $ObjectSpec.Replace('"', '\"')
    if ($AllowMissing) {
        if (-not $ObjectSpec.StartsWith("HEAD:", [StringComparison]::Ordinal)) {
            throw "P2_GIT_ALLOW_MISSING: Only a HEAD path baseline may be optional."
        }
        $verify = Invoke-P2GitBytes -Root $Root -Arguments (
            'rev-parse --verify --quiet "{0}"' -f $escapedSpec
        )
        if ($verify.ExitCode -eq 1) {
            return $null
        }
        if ($verify.ExitCode -ne 0) {
            throw (
                "P2_GIT_VERIFY: Git object '$ObjectSpec' could not be verified" +
                $(if ($verify.ErrorText.Length -gt 0) {
                    ": $($verify.ErrorText)"
                } else {
                    "."
                })
            )
        }
    }

    $result = Invoke-P2GitBytes -Root $Root -Arguments (
        'cat-file blob "{0}"' -f $escapedSpec
    )
    if ($result.ExitCode -ne 0) {
        throw (
            "P2_GIT_BLOB_NOT_FOUND: Git object '$ObjectSpec' could not be read" +
            $(if ($result.ErrorText.Length -gt 0) {
                ": $($result.ErrorText)"
            } else {
                "."
            })
        )
    }
    return ,([byte[]]$result.Bytes)
}

function Read-P2GitManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ObjectSpec,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$AllowMissing
    )

    $bytes = Get-P2GitBlobBytes -Root $Root -ObjectSpec $ObjectSpec `
        -AllowMissing:$AllowMissing
    if ($null -eq $bytes) {
        return $null
    }
    return ConvertFrom-P2ManifestBytes -Bytes $bytes -Label $Label
}

function Assert-P2StagedReviewSurfaceParity {
    param([Parameter(Mandatory = $true)][string]$Root)

    $reviewedPaths = @(
        "new-game-project/battle/.gitignore",
        "new-game-project/battle/tests/catalog/p0_asset_boundary_test.ps1",
        "new-game-project/battle/tests/specs/p2_id_presentation_contract_test.ps1",
        "new-game-project/battle/tests/specs/p2_fixture_preflight_test.ps1",
        "new-game-project/battle/tests/specs/p2_repository_view_test.ps1",
        "new-game-project/battle/tests/specs/p2_spec_compiler_test.ps1",
        "new-game-project/battle/tests/specs/p2_spec_contract_test.ps1",
        "new-game-project/battle/tools/battle_catalog/validators/battle_asset_support.ps1",
        "new-game-project/battle/tools/battle_catalog/validators/canonical_json_support.ps1",
        "new-game-project/battle/tools/battle_catalog/validators/strict_json_support.ps1",
        "new-game-project/battle/tools/battle_specs/schemas/presentation_contracts.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/stable_id_manifest.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/compiled_fixture_requirement_manifest.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/compiled_spec_manifest.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/event_schema.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/handler_binding.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/mechanism_spec.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/resolver_spec.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/runtime_rule_catalog_manifest.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/test_manifest_entry.schema.json",
        "new-game-project/battle/tools/battle_specs/compilers/compile_p2_specs.ps1",
        "new-game-project/battle/tools/battle_specs/compilers/compile_p2_fixture_requirements.ps1",
        "new-game-project/battle/tools/battle_specs/compilers/p2_fixture_preflight_support.ps1",
        "new-game-project/battle/tools/battle_specs/compilers/p2_spec_compiler_support.ps1",
        "new-game-project/battle/tools/battle_specs/validators/p2_id_manifest_support.ps1",
        "new-game-project/battle/tools/battle_specs/validators/p2_repository_view_support.ps1",
        "new-game-project/battle/tools/battle_specs/validators/p2_spec_contract_support.ps1",
        "new-game-project/battle/tools/battle_specs/validators/p2_spec_set_support.ps1",
        "new-game-project/battle/tools/battle_specs/validators/validate_p2_id_manifests.ps1",
        "new-game-project/battle/tools/battle_specs/validators/validate_p2_spec_contracts.ps1",
        "new-game-project/battle/tools/check_battle_assets.ps1",
        "new-game-project/battle/tools/check_battle_dependencies.ps1",
        "new-game-project/battle/tools/check_battle_scope.ps1"
    )
    foreach ($relativePath in $reviewedPaths) {
        $indexSpec = ":$relativePath"
        $headSpec = "HEAD:$relativePath"
        $indexExists = Test-P2GitObjectExists -Root $Root -ObjectSpec $indexSpec
        $headExists = Test-P2GitObjectExists -Root $Root -ObjectSpec $headSpec
        $fullPath = [IO.Path]::GetFullPath((Join-Path $Root (
            $relativePath.Replace('/', '\')
        )))
        $worktreeExists = Test-Path -LiteralPath $fullPath -PathType Leaf
        if (-not $indexExists) {
            if ($headExists) {
                throw (
                    "P2_STAGED_REVIEW_SURFACE_DELETED: '$relativePath' is " +
                    "required by the staged P2 gate."
                )
            }
            if ($worktreeExists) {
                throw (
                    "P2_STAGED_REVIEW_SURFACE_UNTRACKED: '$relativePath' " +
                    "participates in validation but is absent from the index."
                )
            }
            continue
        }

        if (-not $worktreeExists) {
            throw (
                "P2_STAGED_REVIEW_SURFACE_MISSING: Worktree file is missing " +
                "for staged path '$relativePath'."
            )
        }
        $indexBytes = Get-P2GitBlobBytes -Root $Root -ObjectSpec $indexSpec
        $worktreeBytes = [IO.File]::ReadAllBytes($fullPath)
        $matches = $indexBytes.Length -eq $worktreeBytes.Length
        if ($matches) {
            for ($index = 0; $index -lt $indexBytes.Length; $index++) {
                if ($indexBytes[$index] -ne $worktreeBytes[$index]) {
                    $matches = $false
                    break
                }
            }
        }
        if (-not $matches) {
            throw (
                "P2_STAGED_REVIEW_SURFACE_MISMATCH: '$relativePath' differs " +
                "between the Git index and worktree."
            )
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')

$hasStablePath = Test-P2PathProvided $StableIdManifestPath
$hasPresentationPath = Test-P2PathProvided $PresentationManifestPath
if ($hasStablePath -ne $hasPresentationPath) {
    throw (
        "P2_MANIFEST_PATH_PAIR: StableIdManifestPath and " +
        "PresentationManifestPath must be provided together."
    )
}
$hasBaselineStablePath = Test-P2PathProvided $BaselineStableIdManifestPath
$hasBaselinePresentationPath = Test-P2PathProvided (
    $BaselinePresentationManifestPath
)
if ($hasBaselineStablePath -ne $hasBaselinePresentationPath) {
    throw (
        "P2_BASELINE_PATH_PAIR: BaselineStableIdManifestPath and " +
        "BaselinePresentationManifestPath must be provided together."
    )
}
if ($Mode -eq "Staged" -and ($hasStablePath -or $hasBaselineStablePath)) {
    throw (
        "P2_STAGED_PATH_OVERRIDE: Staged mode reads candidate and baseline " +
        "only from the Git index and HEAD."
    )
}
if ($Mode -eq "Worktree" -and $hasStablePath -and
    -not $hasBaselineStablePath) {
    throw (
        "P2_WORKTREE_BASELINE_REQUIRED: Explicit Worktree candidates require " +
        "an explicit baseline pair."
    )
}
if ($Mode -eq "Staged" -or (
    $Mode -eq "Worktree" -and -not $hasStablePath -and
    -not $hasBaselineStablePath
)) {
    Assert-P2GitRepositoryRoot -Root $ProjectRoot
}
if ($Mode -eq "Staged") {
    Assert-P2StagedReviewSurfaceParity -Root $ProjectRoot
}

$stableManifest = $null
$presentationManifest = $null
$baselineStableManifest = $null
$baselinePresentationManifest = $null

if ($Mode -eq "Staged") {
    $stableManifest = Read-P2GitManifest -Root $ProjectRoot `
        -ObjectSpec (":" + $stableRelativePath) `
        -Label "staged stable ID manifest"
    $presentationManifest = Read-P2GitManifest -Root $ProjectRoot `
        -ObjectSpec (":" + $presentationRelativePath) `
        -Label "staged presentation contract manifest"
    $baselineStableManifest = Read-P2GitManifest -Root $ProjectRoot `
        -ObjectSpec ("HEAD:" + $stableRelativePath) `
        -Label "HEAD stable ID baseline" -AllowMissing
    $baselinePresentationManifest = Read-P2GitManifest -Root $ProjectRoot `
        -ObjectSpec ("HEAD:" + $presentationRelativePath) `
        -Label "HEAD presentation baseline" -AllowMissing
}
else {
    if ($hasStablePath) {
        $candidateStablePath = Resolve-P2InputPath -Root $ProjectRoot `
            -Path $StableIdManifestPath
        $candidatePresentationPath = Resolve-P2InputPath -Root $ProjectRoot `
            -Path $PresentationManifestPath
    }
    else {
        $candidateStablePath = Join-Path $ProjectRoot (
            $stableRelativePath.Replace('/', '\')
        )
        $candidatePresentationPath = Join-Path $ProjectRoot (
            $presentationRelativePath.Replace('/', '\')
        )
    }
    $stableManifest = Read-P2ManifestFile -Path $candidateStablePath `
        -Label "stable ID manifest"
    $presentationManifest = Read-P2ManifestFile `
        -Path $candidatePresentationPath `
        -Label "presentation contract manifest"

    if ($hasBaselineStablePath) {
        $baselineStablePath = Resolve-P2InputPath -Root $ProjectRoot `
            -Path $BaselineStableIdManifestPath
        $baselinePresentationPath = Resolve-P2InputPath -Root $ProjectRoot `
            -Path $BaselinePresentationManifestPath
        $baselineStableManifest = Read-P2ManifestFile `
            -Path $baselineStablePath -Label "stable ID baseline"
        $baselinePresentationManifest = Read-P2ManifestFile `
            -Path $baselinePresentationPath `
            -Label "presentation contract baseline"
    }
    elseif ($Mode -eq "Worktree" -and -not $hasStablePath) {
        $baselineStableManifest = Read-P2GitManifest -Root $ProjectRoot `
            -ObjectSpec ("HEAD:" + $stableRelativePath) `
            -Label "HEAD stable ID baseline" -AllowMissing
        $baselinePresentationManifest = Read-P2GitManifest -Root $ProjectRoot `
            -ObjectSpec ("HEAD:" + $presentationRelativePath) `
            -Label "HEAD presentation baseline" -AllowMissing
    }
}

$hasStableBaseline = $null -ne $baselineStableManifest
$hasPresentationBaseline = $null -ne $baselinePresentationManifest
if ($hasStableBaseline -ne $hasPresentationBaseline) {
    throw (
        "P2_BASELINE_PAIR: Stable ID and presentation baselines must either " +
        "both exist or both be absent."
    )
}

$stableResult = Test-P2StableIdManifest -Manifest $stableManifest
$presentationResult = Test-P2PresentationContracts `
    -Manifest $presentationManifest
if (-not $hasStableBaseline -and $Mode -in @("Staged", "Worktree") -and
    -not $hasStablePath) {
    Assert-P2Condition (
        [long]$stableManifest.generation -eq 1 -and
        [long]$presentationManifest.generation -eq 1
    ) "P2_INITIAL_GENERATION" `
        "A newly introduced stable-ID/presentation pair must start at generation 1."
}
if ($null -ne $baselineStableManifest) {
    $null = Test-P2StableIdEvolution -Baseline $baselineStableManifest `
        -Candidate $stableManifest
}
if ($null -ne $baselinePresentationManifest) {
    $null = Test-P2PresentationEvolution `
        -Baseline $baselinePresentationManifest `
        -Candidate $presentationManifest
}

Write-Output (
    (
        "P2_ID_PRESENTATION_CONTRACTS_OK stable_ids_sha256={0} " +
        "presentation_sha256={1}"
    ) -f `
        $stableResult.Sha256, $presentationResult.Sha256
)
