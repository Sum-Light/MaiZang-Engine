[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "dspre_collision_support.ps1")

function Assert-Throws {
    param([scriptblock]$Action, [string]$Label)

    try {
        & $Action
    }
    catch {
        return
    }
    throw "$Label did not reject invalid state."
}

function Write-TestBytes {
    param([string]$Path, [byte[]]$Bytes)

    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllBytes($Path, $Bytes)
}

$syncPath = Join-Path $PSScriptRoot "sync_dspre_godot_assets.ps1"
$tokens = $null
$parseErrors = $null
$syncAst = [Management.Automation.Language.Parser]::ParseFile(
    $syncPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -ne 0) {
    throw "The DSPRE sync script did not parse."
}
foreach ($functionName in @(
    "Test-GodotImportSidecarArtifact",
    "Get-StageFilesWithoutReparsePoints",
    "Get-StageFileRecords",
    "Assert-StageFileRecords",
    "ConvertTo-StageRecordMap",
    "Get-StageFileShapes",
    "Assert-StageFileShapes",
    "Assert-DspreTrustedMarkerFingerprint",
    "Test-GodotImportAssetPath",
    "Remove-GodotManagedFile",
    "Sync-DspreManagedFiles"
)) {
    $definition = $syncAst.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $functionName
    }, $true)
    if ($null -eq $definition) {
        throw "DSPRE sync helper was not found: $functionName"
    }
    Invoke-Expression $definition.Extent.Text
}

$tempBoundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path $tempBoundary ("maizang_sync_{0}" -f [Guid]::NewGuid().ToString("N"))
$sourceRoot = Join-Path $testRoot "source"
$projectRoot = Join-Path $testRoot "project"
$destinationRoot = Join-Path $projectRoot "assets\platinum\matrix_0001"
$utf8NoBom = [Text.UTF8Encoding]::new($false)

try {
    $null = [IO.Directory]::CreateDirectory($sourceRoot)
    $null = [IO.Directory]::CreateDirectory($destinationRoot)

    Write-TestBytes (Join-Path $sourceRoot "terrain\unchanged.glb") ([byte[]]@(1, 2, 3, 4))
    Write-TestBytes (Join-Path $sourceRoot "terrain\changed.glb") ([byte[]]@(5, 6, 7, 8))
    Write-TestBytes (Join-Path $sourceRoot "terrain\new.glb") ([byte[]]@(9, 10, 11, 12))
    Write-TestBytes (Join-Path $sourceRoot "shared\textures\unchanged.png") ([byte[]]@(13, 14, 15))
    [IO.File]::WriteAllText((Join-Path $sourceRoot "manifest.json"), "new-manifest", $utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $sourceRoot "summary.json"), "new-summary", $utf8NoBom)
    [IO.File]::WriteAllText(
        (Join-Path $sourceRoot "material_catalog.json"),
        "new-catalog",
        $utf8NoBom
    )
    [IO.File]::WriteAllText(
        (Join-Path $sourceRoot ".dedupe-complete.json"),
        "new-dedupe-marker",
        $utf8NoBom
    )

    Write-TestBytes (Join-Path $destinationRoot "terrain\unchanged.glb") ([byte[]]@(1, 2, 3, 4))
    Write-TestBytes (Join-Path $destinationRoot "terrain\changed.glb") ([byte[]]@(8, 7, 6, 5))
    Write-TestBytes (Join-Path $destinationRoot "terrain\stale.glb") ([byte[]]@(20, 21, 22))
    Write-TestBytes (
        (Join-Path $destinationRoot "shared\textures\unchanged.png")
    ) ([byte[]]@(13, 14, 15))
    [IO.File]::WriteAllText((Join-Path $destinationRoot "manifest.json"), "old-manifest", $utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $destinationRoot "summary.json"), "old-summary", $utf8NoBom)
    [IO.File]::WriteAllText(
        (Join-Path $destinationRoot "material_catalog.json"),
        "old-catalog",
        $utf8NoBom
    )
    [IO.File]::WriteAllText(
        (Join-Path $destinationRoot ".dedupe-complete.json"),
        "old-dedupe-marker",
        $utf8NoBom
    )

    $oldRecords = @(Get-StageFileRecords -RootPath $destinationRoot)
    $oldMarker = [pscustomobject][ordered]@{
        schema_version = 2
        matrix_id = 1
        variant = "matrix_0001"
        files = $oldRecords
    }
    [IO.File]::WriteAllText(
        (Join-Path $destinationRoot ".sync-complete.json"),
        ($oldMarker | ConvertTo-Json -Depth 6),
        $utf8NoBom
    )
    foreach ($relativePath in @(
        "terrain\unchanged.glb.import",
        "terrain\changed.glb.import",
        "terrain\stale.glb.import",
        "terrain\orphan.glb.import"
    )) {
        [IO.File]::WriteAllText(
            (Join-Path $destinationRoot $relativePath),
            "sidecar:$relativePath",
            $utf8NoBom
        )
    }
    $importTemporaryPath = Join-Path `
        $destinationRoot `
        "terrain\unchanged.glb.import~RF1234567.TMP"
    [IO.File]::WriteAllText($importTemporaryPath, "active-import", $utf8NoBom)
    $unchangedSidecar = Join-Path $destinationRoot "terrain\unchanged.glb.import"
    $unchangedSidecarText = [IO.File]::ReadAllText($unchangedSidecar, [Text.Encoding]::UTF8)

    $sourceRecords = @(Get-StageFileRecords -RootPath $sourceRoot)
    $result = Sync-DspreManagedFiles `
        -SourceRoot $sourceRoot `
        -DestinationRoot $destinationRoot `
        -AllowedRoot $projectRoot `
        -SourceRecords $sourceRecords `
        -ExpectedMatrixId 1 `
        -ExpectedVariant "matrix_0001" `
        -Mode Auto `
        -Force

    if (
        -not (Test-Path -LiteralPath $unchangedSidecar -PathType Leaf) -or
        [IO.File]::ReadAllText($unchangedSidecar, [Text.Encoding]::UTF8) -ne
            $unchangedSidecarText -or
        -not (Test-Path -LiteralPath $importTemporaryPath -PathType Leaf)
    ) {
        throw "An unchanged GLB lost its stable or in-progress Godot import sidecar."
    }
    foreach ($removedPath in @(
        "terrain\changed.glb.import",
        "terrain\stale.glb",
        "terrain\stale.glb.import",
        "terrain\orphan.glb.import"
    )) {
        if (Test-Path -LiteralPath (Join-Path $destinationRoot $removedPath)) {
            throw "Incremental sync retained stale output: $removedPath"
        }
    }
    if (
        $result.retained -lt 2 -or
        $result.linked -lt 1 -or
        $result.removed_sidecars -lt 3
    ) {
        throw "Incremental sync statistics do not describe the focused reconciliation."
    }
    $validatedRecords = @(Assert-StageFileRecords `
        -RootPath $destinationRoot `
        -ExpectedRecords @($result.records) `
        -ExcludedRelativePaths @(".sync-complete.json", ".sync-in-progress.json") `
        -IgnoreGodotImportSidecars `
        -Label "Synthetic reconciled destination")
    if ($validatedRecords.Count -ne $sourceRecords.Count) {
        throw "Incremental sync did not publish the exact source record set."
    }

    $replacementMarker = [pscustomobject][ordered]@{
        schema_version = 2
        matrix_id = 1
        variant = "matrix_0001"
        files = @($result.records)
    }
    $replacementMarkerPath = Join-Path $destinationRoot ".sync-complete.json"
    Remove-Item -LiteralPath ([string]$result.transaction_marker) -Force
    [IO.File]::WriteAllText(
        $replacementMarkerPath,
        ($replacementMarker | ConvertTo-Json -Depth 6),
        $utf8NoBom
    )
    $unexpectedPath = Join-Path $destinationRoot "unexpected.bin"
    Write-TestBytes $unexpectedPath ([byte[]]@(99))
    Assert-Throws {
        Sync-DspreManagedFiles `
            -SourceRoot $sourceRoot `
            -DestinationRoot $destinationRoot `
            -AllowedRoot $projectRoot `
            -SourceRecords $sourceRecords `
            -ExpectedMatrixId 1 `
            -ExpectedVariant "matrix_0001" `
            -Mode Auto `
            -Force
    } "unexpected managed destination file"
    if (
        -not (Test-Path -LiteralPath $unexpectedPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $replacementMarkerPath -PathType Leaf)
    ) {
        throw "Unexpected-file rejection mutated the destination before failing."
    }

    $recoveryRoot = Join-Path $projectRoot "assets\platinum\matrix_0002"
    $null = [IO.Directory]::CreateDirectory($recoveryRoot)
    Write-TestBytes (Join-Path $recoveryRoot "terrain\partial.glb") ([byte[]]@(1, 1, 2, 3))
    $interruptedTemporaryMarker = Join-Path $recoveryRoot (
        ".sync-in-progress~{0}.tmp" -f [Guid]::NewGuid().ToString("N")
    )
    [IO.File]::WriteAllText($interruptedTemporaryMarker, '{', $utf8NoBom)
    $recoveryResult = Sync-DspreManagedFiles `
        -SourceRoot $sourceRoot `
        -DestinationRoot $recoveryRoot `
        -AllowedRoot $projectRoot `
        -SourceRecords $sourceRecords `
        -ExpectedMatrixId 2 `
        -ExpectedVariant "matrix_0002" `
        -Mode Auto `
        -Force
    if (
        (Test-Path -LiteralPath (Join-Path $recoveryRoot "terrain\partial.glb")) -or
        -not (Test-Path -LiteralPath ([string]$recoveryResult.transaction_marker) -PathType Leaf)
    ) {
        throw "Interrupted sync recovery did not reset and rebuild the partial destination."
    }
    $null = @(Assert-StageFileShapes `
        -RootPath $recoveryRoot `
        -ExpectedRecords @($recoveryResult.records) `
        -ExcludedRelativePaths @(".sync-in-progress.json") `
        -Label "Recovered synthetic destination")
    Remove-Item -LiteralPath ([string]$recoveryResult.transaction_marker) -Force

    $dedupeMarkerPath = Join-Path $sourceRoot ".dedupe-complete.json"
    $trustedHash = (
        Get-FileHash -LiteralPath $dedupeMarkerPath -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    $null = Assert-DspreTrustedMarkerFingerprint `
        -Path $dedupeMarkerPath `
        -ExpectedSha256 $trustedHash
    [IO.File]::WriteAllText($dedupeMarkerPath, "bad-dedupe-marker", $utf8NoBom)
    Assert-Throws {
        Assert-DspreTrustedMarkerFingerprint `
            -Path $dedupeMarkerPath `
            -ExpectedSha256 $trustedHash
    } "trusted source marker mutation"

    $syncText = [IO.File]::ReadAllText($syncPath, [Text.Encoding]::UTF8)
    $orchestratorText = [IO.File]::ReadAllText(
        (Join-Path $PSScriptRoot "dspre_export_all_matrices.ps1"),
        [Text.Encoding]::UTF8
    )
    foreach ($requiredText in @(
        "TrustSourceMarkerRecords = `$true",
        "ExpectedDedupeMarkerSha256 = `$dedupeMarkerSha256"
    )) {
        if ($orchestratorText.IndexOf($requiredText, [StringComparison]::Ordinal) -lt 0) {
            throw "The all-matrix orchestrator is missing trusted sync wiring: $requiredText"
        }
    }
    if (
        $syncText.IndexOf('if ($TrustSourceMarkerRecords)', [StringComparison]::Ordinal) -lt 0 -or
        $syncText.IndexOf('Assert-StageFileRecords', [StringComparison]::Ordinal) -lt 0
    ) {
        throw "Direct sync no longer retains its strict source-record validation path."
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Write-Host "DSPRE incremental sync test complete."
Write-Host "  Unchanged sidecar preservation: OK"
Write-Host "  Changed/stale sidecar cleanup: OK"
Write-Host "  Exact managed record set: OK"
Write-Host "  Interrupted transaction recovery: OK"
Write-Host "  Trusted marker mutation: OK"
