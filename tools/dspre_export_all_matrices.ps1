[CmdletBinding()]
param(
    [string]$DspreContents = "",
    [string]$ApiculaPath = "C:\Users\YbbNa\Downloads\DSPRE-win-Portable\current\Tools\apicula.exe",
    [string]$GodotPath = "C:\Users\YbbNa\Downloads\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe",
    [int[]]$MatrixIds = @(),
    [int]$MaxParallel = 4,
    [switch]$RebuildExisting,
    [switch]$ReuseAreaResolution,
    [switch]$SkipGodotImport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$rawRoot = Join-Path $workspaceRoot "generated\dspre_glb"
$dedupRoot = Join-Path $workspaceRoot "generated\dspre_glb_dedup"
$projectRoot = Join-Path $workspaceRoot "new-game-project"
$platinumRoot = Join-Path $projectRoot "assets\platinum"
$resolutionPath = Join-Path $workspaceRoot "generated\dspre_matrix_area_overrides.json"
$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Resolve-ExistingFile {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not found: $Path"
    }
    return (Get-Item -LiteralPath $Path).FullName
}

function Resolve-ExistingDirectory {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label was not found: $Path"
    }
    return (Get-Item -LiteralPath $Path).FullName
}

function Invoke-ProjectScript {
    param([string]$Path, [hashtable]$Arguments)

    $argumentList = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $Arguments.GetEnumerator()) {
        if ($entry.Value -is [Management.Automation.SwitchParameter]) {
            if ($entry.Value.IsPresent) {
                $argumentList.Add("-$($entry.Key)")
            }
            continue
        }
        if ($entry.Value -is [bool]) {
            if ($entry.Value) {
                $argumentList.Add("-$($entry.Key)")
            }
            continue
        }
        $argumentList.Add("-$($entry.Key)")
        $argumentList.Add($entry.Value)
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @argumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$([IO.Path]::GetFileName($Path)) failed with exit code $LASTEXITCODE."
    }
}

function Get-DefaultCell {
    param($Manifest)

    $cells = @($Manifest.cells)
    if ($cells.Count -eq 0) {
        throw "Matrix $($Manifest.matrix.id) has no occupied cells."
    }
    if ([int]$Manifest.matrix.id -eq 0) {
        $preferred = $cells | Where-Object { [int]$_.x -eq 3 -and [int]$_.y -eq 27 } |
            Select-Object -First 1
        if ($null -ne $preferred) {
            return [pscustomobject][ordered]@{ x = 3; y = 27 }
        }
    }
    $centerX = ([double]$Manifest.matrix.width - 1.0) / 2.0
    $centerY = ([double]$Manifest.matrix.height - 1.0) / 2.0
    $sortProperties = @(
        @{ Expression = {
                [Math]::Pow([double]$_.x - $centerX, 2) +
                    [Math]::Pow([double]$_.y - $centerY, 2)
            } },
        @{ Expression = { [int]$_.y } },
        @{ Expression = { [int]$_.x } }
    )
    $selected = $cells |
        Sort-Object -Property $sortProperties |
        Select-Object -First 1
    return [pscustomobject][ordered]@{ x = [int]$selected.x; y = [int]$selected.y }
}

function Get-ReadyStatus {
    param($Manifest)

    $resolutions = @(
        @($Manifest.cells) |
            ForEach-Object {
                if ($null -ne $_.PSObject.Properties["area_resolution"]) {
                    [string]$_.area_resolution
                }
                elseif ([bool]$Manifest.matrix.has_headers) {
                    "per_cell_header"
                }
                else {
                    "linked_map_header"
                }
            } |
            Sort-Object -Unique
    )
    if ($resolutions -contains "known_map_reference") {
        return "ready_duplicate_map"
    }
    if ($resolutions -contains "asset_compatibility") {
        return "ready_unique_texture"
    }
    return "ready_header"
}

function Assert-AreaResolution {
    param($Resolution, [int[]]$SourceMatrixIds, [string]$ExpectedSource, [long]$HeaderTableOffset)

    if ([int]$Resolution.schema_version -ne 1) {
        throw "Unsupported Matrix AreaData resolution schema: $($Resolution.schema_version)"
    }
    $resolutionSource = [IO.Path]::GetFullPath([string]$Resolution.source.dspre_contents)
    if (-not $resolutionSource.Equals($ExpectedSource, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Area resolution source does not match DspreContents. Regenerate without -ReuseAreaResolution."
    }
    $expectedOffset = "0x{0:X}" -f $HeaderTableOffset
    if (-not $expectedOffset.Equals(
        [string]$Resolution.source.header_table_offset,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Area resolution header table offset does not match $expectedOffset. Regenerate without -ReuseAreaResolution."
    }

    $sourceIds = New-Object System.Collections.Generic.HashSet[int]
    foreach ($matrixId in $SourceMatrixIds) {
        $null = $sourceIds.Add([int]$matrixId)
    }
    $variantNames = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    $variantPairs = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    $coveredIds = New-Object System.Collections.Generic.HashSet[int]
    $variantByMatrix = @{}
    $variantGroups = @(@($Resolution.variants) | Group-Object { [int]$_.matrix_id })
    foreach ($group in $variantGroups) {
        $records = @($group.Group)
        $matrixId = [int]$records[0].matrix_id
        if (-not $sourceIds.Contains($matrixId)) {
            throw "Area resolution references a matrix that does not exist: $matrixId"
        }
        if (-not $coveredIds.Add($matrixId)) {
            throw "Area resolution contains duplicate matrix groups: $matrixId"
        }
        $variantByMatrix[$matrixId] = $records
        foreach ($record in $records) {
            $areaId = $record.area_data_id
            if ($null -ne $areaId -and ([int]$areaId -lt 0 -or [int]$areaId -gt 0xFFFF)) {
                throw "Area resolution contains an invalid AreaData ID for matrix $matrixId."
            }
            if ($records.Count -gt 1 -and $null -eq $areaId) {
                throw "Multi-variant matrix $matrixId is missing an AreaData ID."
            }
            if ([string]$record.resolution -notin @(
                "per_cell_header",
                "linked_map_header",
                "known_map_reference",
                "asset_compatibility"
            )) {
                throw "Area resolution contains an unknown resolution for matrix $matrixId`: $($record.resolution)"
            }
            $expectedVariant = if ($records.Count -gt 1) {
                "matrix_{0:D4}_area_{1:D4}" -f $matrixId, [int]$areaId
            }
            else {
                "matrix_{0:D4}" -f $matrixId
            }
            $variantName = [string]$record.variant
            if ($variantName -notmatch '^matrix_\d{4}(_area_\d{4})?$' -or $variantName -ne $expectedVariant) {
                throw "Unsafe or inconsistent matrix variant '$variantName'; expected '$expectedVariant'."
            }
            if (-not $variantNames.Add($variantName)) {
                throw "Area resolution contains duplicate variant '$variantName'."
            }
            $pairKey = if ($null -eq $areaId) { "$matrixId|null" } else { "$matrixId|$([int]$areaId)" }
            if (-not $variantPairs.Add($pairKey)) {
                throw "Area resolution contains duplicate matrix/AreaData pair '$pairKey'."
            }
        }
    }

    $overrideIds = New-Object System.Collections.Generic.HashSet[int]
    foreach ($override in @($Resolution.overrides)) {
        $matrixId = [int]$override.matrix_id
        if (-not $overrideIds.Add($matrixId)) {
            throw "Area resolution contains duplicate override matrix $matrixId."
        }
        if (-not $variantByMatrix.ContainsKey($matrixId)) {
            throw "Area resolution override references a non-runnable matrix: $matrixId"
        }
        $records = @($variantByMatrix[$matrixId])
        if ($records.Count -ne 1) {
            throw "Area resolution override matrix $matrixId must have one canonical variant."
        }
        $variant = $records[0]
        if (
            $null -eq $variant.area_data_id -or
            [int]$variant.area_data_id -ne [int]$override.area_data_id -or
            [string]$variant.resolution -ne [string]$override.resolution -or
            [string]$override.resolution -notin @("known_map_reference", "asset_compatibility")
        ) {
            throw "Area resolution override disagrees with canonical variant for matrix $matrixId."
        }
    }
    foreach ($matrixId in @($variantByMatrix.Keys)) {
        $records = @($variantByMatrix[$matrixId])
        if (
            $records.Count -eq 1 -and
            [string]$records[0].resolution -in @("known_map_reference", "asset_compatibility") -and
            -not $overrideIds.Contains([int]$matrixId)
        ) {
            throw "Resolved orphan matrix $matrixId has no matching override record."
        }
    }

    $unresolvedIds = New-Object System.Collections.Generic.HashSet[int]
    foreach ($record in @($Resolution.unresolved)) {
        $matrixId = [int]$record.matrix_id
        if (-not $sourceIds.Contains($matrixId)) {
            throw "Area resolution marks a matrix unresolved that does not exist: $matrixId"
        }
        if (-not $unresolvedIds.Add($matrixId)) {
            throw "Area resolution contains duplicate unresolved matrix $matrixId."
        }
        if ($coveredIds.Contains($matrixId)) {
            throw "Area resolution marks matrix $matrixId both ready and unresolved."
        }
        $null = $coveredIds.Add($matrixId)
    }
    if ($coveredIds.Count -ne $sourceIds.Count) {
        $missing = @($SourceMatrixIds | Where-Object { -not $coveredIds.Contains([int]$_) })
        throw "Area resolution does not cover every source matrix. Missing: $($missing -join ', ')"
    }
    if ([int]$Resolution.summary.matrices -ne $sourceIds.Count -or
        [int]$Resolution.summary.ready_variants -ne $variantNames.Count -or
        [int]$Resolution.summary.resolved_orphans -ne $overrideIds.Count -or
        [int]$Resolution.summary.unresolved_orphans -ne $unresolvedIds.Count) {
        throw "Area resolution summary does not match its matrix records."
    }
}

function Test-DedupeComplete {
    param(
        [string]$SourceManifest,
        [string]$DestinationRoot,
        [string]$ExpectedVariant,
        [int]$ExpectedMatrixId,
        $ExpectedAreaDataId
    )

    $markerPath = Join-Path $DestinationRoot ".dedupe-complete.json"
    $manifestPath = Join-Path $DestinationRoot "manifest.json"
    $summaryPath = Join-Path $DestinationRoot "summary.json"
    $catalogPath = Join-Path $DestinationRoot "material_catalog.json"
    foreach ($path in @($SourceManifest, $markerPath, $manifestPath, $summaryPath, $catalogPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            return $false
        }
    }
    try {
        $marker = [IO.File]::ReadAllText($markerPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $summary = [IO.File]::ReadAllText($summaryPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $catalog = [IO.File]::ReadAllText($catalogPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $actualGlbs = @(Get-ChildItem -LiteralPath $DestinationRoot -Recurse -Filter "*.glb" -File).Count
        $manifestVariant = if ($null -ne $manifest.matrix.PSObject.Properties["variant"]) {
            [string]$manifest.matrix.variant
        }
        else {
            "matrix_{0:D4}" -f [int]$manifest.matrix.id
        }
        $manifestArea = if ($null -ne $manifest.matrix.PSObject.Properties["area_data_id"]) {
            $manifest.matrix.area_data_id
        }
        else {
            $null
        }
        $areaMatches = ($null -eq $ExpectedAreaDataId -and $null -eq $manifestArea) -or
            ($null -ne $ExpectedAreaDataId -and $null -ne $manifestArea -and
                [int]$ExpectedAreaDataId -eq [int]$manifestArea)
        $textureRoot = Join-Path $DestinationRoot "shared\textures"
        $actualPngs = @(Get-ChildItem -LiteralPath $textureRoot -Filter "*.png" -File -ErrorAction SilentlyContinue)
        $catalogImages = @($catalog.images)
        $catalogMaterials = @($catalog.materials)
        foreach ($image in $catalogImages) {
            $imagePath = [IO.Path]::GetFullPath(
                (Join-Path $DestinationRoot ([string]$image.relative_path).Replace('/', '\'))
            )
            if (
                -not $imagePath.StartsWith($DestinationRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
                -not (Test-Path -LiteralPath $imagePath -PathType Leaf) -or
                (Get-FileHash -LiteralPath $imagePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne [string]$image.sha256
            ) {
                return $false
            }
        }
        return [int]$marker.schema_version -eq 1 -and
            [string]$marker.source_manifest_sha256 -eq (Get-FileHash -LiteralPath $SourceManifest -Algorithm SHA256).Hash.ToLowerInvariant() -and
            [string]$marker.output_manifest_sha256 -eq (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -and
            [int]$manifest.matrix.id -eq $ExpectedMatrixId -and
            $manifestVariant -eq $ExpectedVariant -and
            $areaMatches -and
            [int]$marker.glbs -eq $actualGlbs -and
            [int]$summary.glbs -eq $actualGlbs -and
            [int]$catalog.summary.glbs -eq $actualGlbs -and
            [int]$marker.unique_images -eq $actualPngs.Count -and
            [int]$summary.unique_images -eq $actualPngs.Count -and
            [int]$catalog.summary.unique_images -eq $actualPngs.Count -and
            [int]$manifest.material_dedupe.unique_images -eq $actualPngs.Count -and
            $catalogImages.Count -eq $actualPngs.Count -and
            [int]$marker.unique_materials -eq $catalogMaterials.Count -and
            [int]$summary.unique_materials -eq $catalogMaterials.Count -and
            [int]$catalog.summary.unique_materials -eq $catalogMaterials.Count -and
            [int]$manifest.material_dedupe.unique_materials -eq $catalogMaterials.Count
    }
    catch {
        return $false
    }
}

function Test-SyncComplete {
    param(
        [string]$SourceManifest,
        [string]$DestinationRoot,
        [string]$ExpectedVariant,
        [int]$ExpectedMatrixId,
        $ExpectedAreaDataId
    )

    $destinationManifest = Join-Path $DestinationRoot "manifest.json"
    $markerPath = Join-Path $DestinationRoot ".sync-complete.json"
    if (
        -not (Test-Path -LiteralPath $SourceManifest -PathType Leaf) -or
        -not (Test-Path -LiteralPath $destinationManifest -PathType Leaf) -or
        -not (Test-Path -LiteralPath $markerPath -PathType Leaf)
    ) {
        return $false
    }
    try {
        $marker = [IO.File]::ReadAllText($markerPath, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        $destination = [IO.File]::ReadAllText($destinationManifest, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        $destinationVariant = if ($null -ne $destination.matrix.PSObject.Properties["variant"]) {
            [string]$destination.matrix.variant
        }
        else {
            "matrix_{0:D4}" -f [int]$destination.matrix.id
        }
        $sourceHash = (Get-FileHash -LiteralPath $SourceManifest -Algorithm SHA256).Hash.ToLowerInvariant()
        $destinationHash = (Get-FileHash -LiteralPath $destinationManifest -Algorithm SHA256).Hash.ToLowerInvariant()
        $destinationArea = if ($null -ne $destination.matrix.PSObject.Properties["area_data_id"]) {
            $destination.matrix.area_data_id
        }
        else {
            $null
        }
        $areaMatches = ($null -eq $ExpectedAreaDataId -and $null -eq $destinationArea) -or
            ($null -ne $ExpectedAreaDataId -and $null -ne $destinationArea -and
                [int]$ExpectedAreaDataId -eq [int]$destinationArea)
        if (
            [int]$marker.schema_version -ne 1 -or
            [int]$marker.matrix_id -ne $ExpectedMatrixId -or
            [string]$marker.variant -ne $ExpectedVariant -or
            [int]$destination.matrix.id -ne $ExpectedMatrixId -or
            $destinationVariant -ne $ExpectedVariant -or
            -not $areaMatches -or
            [string]$marker.source_manifest_sha256 -ne $sourceHash -or
            $destinationHash -ne $sourceHash
        ) {
            return $false
        }
        $actualGlbs = @(
            Get-ChildItem -LiteralPath $DestinationRoot -Recurse -Filter "*.glb" -File
        ).Count
        $textureRoot = Join-Path $DestinationRoot "shared\textures"
        $actualTextures = @(
            Get-ChildItem -LiteralPath $textureRoot -Filter "*.png" -File
        ).Count
        return $actualGlbs -eq [int]$marker.glbs -and
            $actualTextures -eq [int]$marker.textures
    }
    catch {
        return $false
    }
}

if ([string]::IsNullOrWhiteSpace($DspreContents)) {
    $existingManifest = Join-Path $rawRoot "matrix_0000\manifest.json"
    if (Test-Path -LiteralPath $existingManifest -PathType Leaf) {
        $existing = [IO.File]::ReadAllText($existingManifest, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        $candidate = [string]$existing.source.dspre_contents
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $DspreContents = $candidate
        }
    }
}
if ([string]::IsNullOrWhiteSpace($DspreContents)) {
    throw "Pass -DspreContents or generate matrix_0000 first so the source can be recovered."
}

$DspreContents = Resolve-ExistingDirectory $DspreContents "DSPRE contents directory"
$ApiculaPath = Resolve-ExistingFile $ApiculaPath "apicula.exe"
$matricesRoot = Resolve-ExistingDirectory (Join-Path $DspreContents "unpacked\matrices") "Matrix directory"
if ($MaxParallel -lt 1) {
    throw "MaxParallel must be at least 1."
}
New-Item -ItemType Directory -Path $rawRoot, $dedupRoot, $platinumRoot -Force | Out-Null

$allMatrixIds = @(
    Get-ChildItem -LiteralPath $matricesRoot -File |
        Where-Object { $_.Name -match '^\d{4}$' } |
        ForEach-Object { [int]$_.Name } |
        Sort-Object -Unique
)
if ($allMatrixIds.Count -eq 0) {
    throw "No numeric matrix files were found: $matricesRoot"
}

if (-not $ReuseAreaResolution -or -not (Test-Path -LiteralPath $resolutionPath -PathType Leaf)) {
    Invoke-ProjectScript (Join-Path $PSScriptRoot "resolve_dspre_matrix_areas.ps1") @{
        DspreContents = $DspreContents
        ApiculaPath = $ApiculaPath
        OutputPath = $resolutionPath
        AllowUnresolved = $true
    }
}
$resolution = [IO.File]::ReadAllText($resolutionPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
Assert-AreaResolution $resolution $allMatrixIds $DspreContents 0xE56F0
$unresolvedById = @{}
foreach ($record in @($resolution.unresolved)) {
    $unresolvedById[[int]$record.matrix_id] = $record
}

$requestedIds = @(
    if ($MatrixIds.Count -gt 0) {
        $MatrixIds | Sort-Object -Unique
    }
    else {
        $allMatrixIds
    }
)
foreach ($matrixId in $requestedIds) {
    if ($matrixId -notin $allMatrixIds) {
        throw "Requested matrix does not exist: $matrixId"
    }
}
$allVariants = @($resolution.variants)
$readyRequestedVariants = @(
    $allVariants | Where-Object { [int]$_.matrix_id -in $requestedIds }
)
$skippedRequestedIds = @($requestedIds | Where-Object { $unresolvedById.ContainsKey($_) })

Write-Host "DSPRE all-matrix export starting."
Write-Host "  Requested matrices: $($requestedIds.Count)"
Write-Host "  Ready variants:     $($readyRequestedVariants.Count)"
Write-Host "  Unresolved:         $($skippedRequestedIds.Count)"

$processed = 0
foreach ($variantRecord in $readyRequestedVariants) {
    $matrixId = [int]$variantRecord.matrix_id
    $variantName = [string]$variantRecord.variant
    $rawMatrixRoot = Join-Path $rawRoot $variantName
    $dedupMatrixRoot = Join-Path $dedupRoot $variantName
    $godotMatrixRoot = Join-Path $platinumRoot $variantName
    $rawManifest = Join-Path $rawMatrixRoot "manifest.json"
    $rawSummaryPath = Join-Path $rawMatrixRoot "summary.json"
    $dedupManifest = Join-Path $dedupMatrixRoot "manifest.json"
    $dedupSummaryPath = Join-Path $dedupMatrixRoot "summary.json"
    $dedupCatalogPath = Join-Path $dedupMatrixRoot "material_catalog.json"

    $progress = @{
        Activity = "Migrating DSPRE matrices"
        Status = "$variantName ($($processed + 1)/$($readyRequestedVariants.Count))"
        PercentComplete = 100.0 * $processed / [Math]::Max(1, $readyRequestedVariants.Count)
    }
    Write-Progress @progress

    $rawComplete = $false
    if (
        (Test-Path -LiteralPath $rawManifest -PathType Leaf) -and
        (Test-Path -LiteralPath $rawSummaryPath -PathType Leaf)
    ) {
        try {
            $existingRawSummary = [IO.File]::ReadAllText(
                $rawSummaryPath,
                [Text.Encoding]::UTF8
            ) | ConvertFrom-Json
            $existingRawManifest = [IO.File]::ReadAllText(
                $rawManifest,
                [Text.Encoding]::UTF8
            ) | ConvertFrom-Json
            $manifestVariant = if (
                $null -ne $existingRawManifest.matrix.PSObject.Properties["variant"]
            ) {
                [string]$existingRawManifest.matrix.variant
            }
            else {
                "matrix_{0:D4}" -f [int]$existingRawManifest.matrix.id
            }
            $manifestArea = if (
                $null -ne $existingRawManifest.matrix.PSObject.Properties["area_data_id"]
            ) {
                $existingRawManifest.matrix.area_data_id
            }
            else {
                $null
            }
            $expectedArea = $variantRecord.area_data_id
            $areaMatches = ($null -eq $expectedArea -and $null -eq $manifestArea) -or
                ($null -ne $expectedArea -and $null -ne $manifestArea -and
                    [int]$expectedArea -eq [int]$manifestArea)
            $rawComplete = [int]$existingRawSummary.failed -eq 0 -and
                [int]$existingRawManifest.matrix.id -eq $matrixId -and
                $manifestVariant -eq $variantName -and $areaMatches
        }
        catch {
            $rawComplete = $false
        }
    }
    $rawWasRebuilt = $RebuildExisting -or -not $rawComplete
    if ($rawWasRebuilt) {
        $exportArguments = @{
            DspreContents = $DspreContents
            ApiculaPath = $ApiculaPath
            AreaOverridesPath = $resolutionPath
            MatrixId = $matrixId
            MaxParallel = $MaxParallel
            Force = (Test-Path -LiteralPath $rawMatrixRoot)
        }
        if ($variantName -match '_area_\d{4}$') {
            $exportArguments.AreaDataId = [int]$variantRecord.area_data_id
        }
        Invoke-ProjectScript (Join-Path $PSScriptRoot "dspre_batch_export.ps1") $exportArguments
    }
    $rawSummary = [IO.File]::ReadAllText(
        $rawSummaryPath,
        [Text.Encoding]::UTF8
    ) | ConvertFrom-Json
    $rawManifestDocument = [IO.File]::ReadAllText(
        $rawManifest,
        [Text.Encoding]::UTF8
    ) | ConvertFrom-Json
    $rawManifestVariant = if ($null -ne $rawManifestDocument.matrix.PSObject.Properties["variant"]) {
        [string]$rawManifestDocument.matrix.variant
    }
    else {
        "matrix_{0:D4}" -f [int]$rawManifestDocument.matrix.id
    }
    $rawManifestArea = if ($null -ne $rawManifestDocument.matrix.PSObject.Properties["area_data_id"]) {
        $rawManifestDocument.matrix.area_data_id
    }
    else {
        $null
    }
    $expectedArea = $variantRecord.area_data_id
    $rawAreaMatches = ($null -eq $expectedArea -and $null -eq $rawManifestArea) -or
        ($null -ne $expectedArea -and $null -ne $rawManifestArea -and
            [int]$expectedArea -eq [int]$rawManifestArea)
    if (
        [int]$rawSummary.failed -ne 0 -or
        [int]$rawManifestDocument.matrix.id -ne $matrixId -or
        $rawManifestVariant -ne $variantName -or
        -not $rawAreaMatches
    ) {
        throw "$variantName raw export does not match its resolution record."
    }

    $dedupComplete = Test-DedupeComplete `
        $rawManifest $dedupMatrixRoot $variantName $matrixId $variantRecord.area_data_id
    if ($rawWasRebuilt -or -not $dedupComplete) {
        Invoke-ProjectScript (Join-Path $PSScriptRoot "dedupe_dspre_materials.ps1") @{
            SourceRoot = $rawMatrixRoot
            OutputRoot = $dedupMatrixRoot
            Force = (Test-Path -LiteralPath $dedupMatrixRoot)
        }
    }
    if (-not (Test-DedupeComplete `
        $rawManifest $dedupMatrixRoot $variantName $matrixId $variantRecord.area_data_id
    )) {
        throw "$variantName dedupe output is incomplete or inconsistent."
    }

    $syncComplete = Test-SyncComplete `
        $dedupManifest $godotMatrixRoot $variantName $matrixId $variantRecord.area_data_id
    if ($RebuildExisting -or -not $syncComplete) {
        Invoke-ProjectScript (Join-Path $PSScriptRoot "sync_dspre_godot_assets.ps1") @{
            SourceRoot = $dedupMatrixRoot
            ProjectRoot = $projectRoot
            Force = (Test-Path -LiteralPath $godotMatrixRoot)
        }
    }
    if (-not (Test-SyncComplete `
        $dedupManifest $godotMatrixRoot $variantName $matrixId $variantRecord.area_data_id
    )) {
        throw "$variantName Godot sync is incomplete or inconsistent."
    }
    $processed++
}
Write-Progress -Activity "Migrating DSPRE matrices" -Completed

$terrainKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$buildingKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$textureKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$materialKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$matrixEntries = New-Object System.Collections.Generic.List[object]
$destinationEntries = New-Object System.Collections.Generic.List[object]
$totalCells = 0
$totalBuildings = 0
$totalGlbs = 0
$readyMatrixCount = 0
$readyDestinationCount = 0
$notExportedMatrixCount = 0

foreach ($matrixId in $allMatrixIds) {
    if ($unresolvedById.ContainsKey($matrixId)) {
        $unresolved = $unresolvedById[$matrixId]
        $status = if (@($unresolved.candidate_signatures).Count -eq 0) {
            "unresolved_no_single_texture_bundle"
        }
        else {
            "unresolved_ambiguous_area"
        }
        $matrixEntries.Add([pscustomobject][ordered]@{
            id = $matrixId
            status = $status
            destinations = @()
            candidate_signatures = @($unresolved.candidate_signatures)
        })
        continue
    }

    $matrixVariants = @($allVariants | Where-Object { [int]$_.matrix_id -eq $matrixId })
    $destinationKeys = New-Object System.Collections.Generic.List[string]
    $firstManifest = $null
    foreach ($variantRecord in $matrixVariants) {
        $variantName = [string]$variantRecord.variant
        $manifestPath = Join-Path $dedupRoot "$variantName\manifest.json"
        $materialCatalogPath = Join-Path $dedupRoot "$variantName\material_catalog.json"
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            continue
        }
        $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        $materialCatalog = [IO.File]::ReadAllText(
            $materialCatalogPath,
            [Text.Encoding]::UTF8
        ) | ConvertFrom-Json
        if ($null -eq $firstManifest) {
            $firstManifest = $manifest
        }
        foreach ($asset in @($manifest.assets.terrain)) {
            $null = $terrainKeys.Add([string]$asset.key)
        }
        foreach ($asset in @($manifest.assets.buildings)) {
            $null = $buildingKeys.Add([string]$asset.key)
        }
        foreach ($image in @($materialCatalog.images)) {
            $null = $textureKeys.Add([string]$image.key)
        }
        foreach ($material in @($materialCatalog.materials)) {
            $null = $materialKeys.Add([string]$material.key)
        }
        $defaultCell = Get-DefaultCell $manifest
        $glbCount = [int]$materialCatalog.summary.glbs
        $buildingCount = [int]$manifest.summary.building_instances
        $totalGlbs += $glbCount
        $readyDestinationCount++
        $destinationKeys.Add($variantName)
        $destinationEntries.Add([pscustomobject][ordered]@{
            key = $variantName
            matrix_id = $matrixId
            area_data_id = if ($null -eq $variantRecord.area_data_id) {
                $null
            }
            else {
                [int]$variantRecord.area_data_id
            }
            status = Get-ReadyStatus $manifest
            manifest = "$variantName/manifest.json"
            width = [int]$manifest.matrix.width
            height = [int]$manifest.matrix.height
            occupied_cells = [int]$manifest.matrix.occupied_cells
            default_cell = $defaultCell
            terrain_assets = @($manifest.assets.terrain).Count
            building_assets = @($manifest.assets.buildings).Count
            building_instances = $buildingCount
            glbs = $glbCount
            textures = [int]$materialCatalog.summary.unique_images
            materials = [int]$materialCatalog.summary.unique_materials
        })
    }

    if ($destinationKeys.Count -eq 0) {
        $notExportedMatrixCount++
        $matrixEntries.Add([pscustomobject][ordered]@{
            id = $matrixId
            status = "not_exported"
            destinations = @()
        })
        continue
    }
    $matrixStatus = if ($destinationKeys.Count -eq $matrixVariants.Count) {
        $readyMatrixCount++
        "ready"
    }
    else {
        $notExportedMatrixCount++
        "partially_exported"
    }
    $totalCells += [int]$firstManifest.matrix.occupied_cells
    $totalBuildings += [int]$firstManifest.summary.building_instances
    $matrixEntries.Add([pscustomobject][ordered]@{
        id = $matrixId
        name = [string]$firstManifest.matrix.name
        status = $matrixStatus
        destinations = @($destinationKeys | ForEach-Object { $_ })
    })
}

$catalog = [pscustomobject][ordered]@{
    schema_version = 1
    generated_utc = [DateTime]::UtcNow.ToString("o")
    summary = [pscustomobject][ordered]@{
        source_matrices = $allMatrixIds.Count
        expected_destinations = $allVariants.Count
        ready_matrices = $readyMatrixCount
        ready_destinations = $readyDestinationCount
        unresolved_matrices = $unresolvedById.Count
        not_exported_matrices = $notExportedMatrixCount
        occupied_cells = $totalCells
        building_instances = $totalBuildings
        destination_scoped_glbs = $totalGlbs
        unique_terrain_assets = $terrainKeys.Count
        unique_building_assets = $buildingKeys.Count
        unique_textures = $textureKeys.Count
        unique_materials = $materialKeys.Count
    }
    matrices = @($matrixEntries | ForEach-Object { $_ })
    destinations = @($destinationEntries | ForEach-Object { $_ })
}
$catalogJson = $catalog | ConvertTo-Json -Depth 12
$generatedCatalogPath = Join-Path $dedupRoot "matrix_catalog.json"
$godotCatalogPath = Join-Path $platinumRoot "matrix_catalog.json"
[IO.File]::WriteAllText($generatedCatalogPath, $catalogJson, $utf8NoBom)
[IO.File]::WriteAllText($godotCatalogPath, $catalogJson, $utf8NoBom)

Write-Host "DSPRE matrix migration complete."
Write-Host "  Ready matrices:      $readyMatrixCount"
Write-Host "  Ready destinations:  $readyDestinationCount"
Write-Host "  Unresolved matrices: $($unresolvedById.Count)"
Write-Host "  Occupied cells:      $totalCells"
Write-Host "  Matrix GLBs:         $totalGlbs"
Write-Host "  Catalog:             $godotCatalogPath"

if (-not $SkipGodotImport) {
    $GodotPath = Resolve-ExistingFile $GodotPath "Godot console executable"
    & $GodotPath --headless --path $projectRoot --import
    if ($LASTEXITCODE -ne 0) {
        throw "Initial Godot import failed with exit code $LASTEXITCODE."
    }
    Invoke-ProjectScript (Join-Path $PSScriptRoot "configure_dspre_godot_materials.ps1") @{
        ProjectRoot = $projectRoot
        GodotPath = $GodotPath
    }
}
