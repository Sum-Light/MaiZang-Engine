[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$ResolutionPath = "",
    [switch]$RequireComplete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($ResolutionPath)) {
    $ResolutionPath = Join-Path $ProjectRoot "generated\dspre_matrix_area_overrides.json"
}
$godotRoot = Join-Path $ProjectRoot "new-game-project"
$platinumRoot = [IO.Path]::GetFullPath((Join-Path $godotRoot "assets\platinum")).TrimEnd('\')
$catalogPath = Join-Path $platinumRoot "matrix_catalog.json"

function Read-JsonFile {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not found: $Path"
    }
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Test-GlbFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt 12) {
        return $false
    }
    $stream = [IO.File]::OpenRead($item.FullName)
    try {
        $header = New-Object byte[] 12
        if ($stream.Read($header, 0, 12) -ne 12) {
            return $false
        }
        return [Text.Encoding]::ASCII.GetString($header, 0, 4) -eq "glTF" -and
            [BitConverter]::ToUInt32($header, 4) -eq 2 -and
            [BitConverter]::ToUInt32($header, 8) -eq $item.Length
    }
    finally {
        $stream.Dispose()
    }
}

$catalog = Read-JsonFile $catalogPath "Godot matrix catalog"
if ([int]$catalog.schema_version -ne 1) {
    throw "Unsupported matrix catalog schema: $($catalog.schema_version)"
}
$matrixEntries = @($catalog.matrices)
$destinations = @($catalog.destinations)
if ($matrixEntries.Count -ne [int]$catalog.summary.source_matrices) {
    throw "Matrix catalog entry count does not match source_matrices."
}

$matrixIds = New-Object System.Collections.Generic.HashSet[int]
$destinationKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$destinationByKey = @{}
$terrainKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$buildingKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$textureKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$materialKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$recalculatedGlbs = 0
foreach ($matrix in $matrixEntries) {
    if (-not $matrixIds.Add([int]$matrix.id)) {
        throw "Duplicate matrix catalog ID: $($matrix.id)"
    }
}
foreach ($destination in $destinations) {
    $key = [string]$destination.key
    $keyMatch = [regex]::Match($key, '^matrix_(\d{4})(?:_area_(\d{4}))?$')
    if (-not $keyMatch.Success) {
        throw "Invalid destination key: $key"
    }
    if (-not $destinationKeys.Add($key)) {
        throw "Duplicate destination key: $key"
    }
    if (-not $matrixIds.Contains([int]$destination.matrix_id)) {
        throw "Destination $key references an unknown matrix ID."
    }
    if ([int]$keyMatch.Groups[1].Value -ne [int]$destination.matrix_id) {
        throw "Destination key $key does not match matrix ID $($destination.matrix_id)."
    }
    if (
        $keyMatch.Groups[2].Success -and
        ($null -eq $destination.area_data_id -or
            [int]$keyMatch.Groups[2].Value -ne [int]$destination.area_data_id)
    ) {
        throw "Destination key $key does not match AreaData ID $($destination.area_data_id)."
    }
    if (
        $null -ne $destination.area_data_id -and
        ([int]$destination.area_data_id -lt 0 -or [int]$destination.area_data_id -gt 0xFFFF)
    ) {
        throw "Destination $key contains an invalid AreaData ID."
    }
    $expectedManifest = "$key/manifest.json"
    if ([string]$destination.manifest -ne $expectedManifest) {
        throw "Destination $key has an unexpected manifest path: $($destination.manifest)"
    }
    $destinationRoot = [IO.Path]::GetFullPath((Join-Path $platinumRoot $key)).TrimEnd('\')
    if (-not ($destinationRoot + '\').StartsWith(
        $platinumRoot + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Destination escapes the Platinum asset root: $destinationRoot"
    }
    $manifestPath = Join-Path $destinationRoot "manifest.json"
    $manifest = Read-JsonFile $manifestPath "Destination manifest"
    if ([int]$manifest.matrix.id -ne [int]$destination.matrix_id) {
        throw "Destination $key matrix ID does not match its manifest."
    }
    $manifestVariant = if ($null -ne $manifest.matrix.PSObject.Properties["variant"]) {
        [string]$manifest.matrix.variant
    }
    else {
        "matrix_{0:D4}" -f [int]$manifest.matrix.id
    }
    if ($manifestVariant -ne $key) {
        throw "Destination $key variant does not match its manifest: $manifestVariant"
    }
    $catalogArea = $destination.area_data_id
    $manifestArea = if ($null -ne $manifest.matrix.PSObject.Properties["area_data_id"]) {
        $manifest.matrix.area_data_id
    }
    else {
        $null
    }
    if (
        ($catalogArea -eq $null -and $manifestArea -ne $null) -or
        ($catalogArea -ne $null -and (
            $manifestArea -eq $null -or [int]$catalogArea -ne [int]$manifestArea
        ))
    ) {
        throw "Destination $key AreaData does not match its manifest."
    }
    if (@($manifest.cells).Count -ne [int]$destination.occupied_cells) {
        throw "Destination $key occupied cell count does not match its manifest."
    }
    $defaultCell = $destination.default_cell
    $defaultFound = @(
        @($manifest.cells) | Where-Object {
            [int]$_.x -eq [int]$defaultCell.x -and [int]$_.y -eq [int]$defaultCell.y
        }
    ).Count -eq 1
    if (-not $defaultFound) {
        throw "Destination $key default cell is not occupied."
    }
    if ([int]$manifest.summary.failed -ne 0) {
        throw "Destination $key manifest contains failed assets."
    }
    if ([string]$destination.status -notlike "ready_*") {
        throw "Destination $key has an invalid runnable status: $($destination.status)"
    }
    if (
        [int]$destination.width -ne [int]$manifest.matrix.width -or
        [int]$destination.height -ne [int]$manifest.matrix.height -or
        [int]$destination.terrain_assets -ne @($manifest.assets.terrain).Count -or
        [int]$destination.building_assets -ne @($manifest.assets.buildings).Count -or
        [int]$destination.building_instances -ne [int]$manifest.summary.building_instances
    ) {
        throw "Destination $key metadata does not match its manifest."
    }

    $assetRecords = @($manifest.assets.terrain) + @($manifest.assets.buildings)
    $declaredGlbs = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($asset in $assetRecords) {
        foreach ($relativePath in @($asset.output_glbs)) {
            $assetPath = [IO.Path]::GetFullPath(
                (Join-Path $destinationRoot ([string]$relativePath).Replace('/', '\'))
            )
            if (-not $assetPath.StartsWith(
                $destinationRoot + '\',
                [StringComparison]::OrdinalIgnoreCase
            )) {
                throw "Destination $key asset path escapes its root: $relativePath"
            }
            if (-not (Test-GlbFile $assetPath)) {
                throw "Destination $key has an invalid GLB: $relativePath"
            }
            if (-not $declaredGlbs.Add($assetPath)) {
                throw "Destination $key declares a GLB more than once: $relativePath"
            }
        }
    }
    $actualGlbFiles = @(
        Get-ChildItem -LiteralPath $destinationRoot -Recurse -Filter "*.glb" -File
    )
    $actualGlbs = $actualGlbFiles.Count
    $actualGlbPaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($actualGlb in $actualGlbFiles) {
        $null = $actualGlbPaths.Add($actualGlb.FullName)
    }
    foreach ($declaredGlb in $declaredGlbs) {
        if (-not $actualGlbPaths.Contains($declaredGlb)) {
            throw "Destination $key declares a GLB outside its actual file set: $declaredGlb"
        }
    }
    foreach ($actualGlb in $actualGlbPaths) {
        if (-not $declaredGlbs.Contains($actualGlb)) {
            throw "Destination $key contains an undeclared GLB: $actualGlb"
        }
    }
    $textureRoot = Join-Path $destinationRoot "shared\textures"
    if (-not (Test-Path -LiteralPath $textureRoot -PathType Container)) {
        throw "Destination $key shared texture root is missing: $textureRoot"
    }
    $actualPngFiles = @(
        Get-ChildItem -LiteralPath $textureRoot -Filter "*.png" -File -ErrorAction SilentlyContinue
    )
    $actualPngs = $actualPngFiles.Count
    $actualPngPaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($png in $actualPngFiles) {
        $null = $actualPngPaths.Add($png.FullName)
    }
    if ($declaredGlbs.Count -ne $actualGlbs -or $actualGlbs -ne [int]$destination.glbs) {
        throw "Destination $key GLB counts disagree: $($declaredGlbs.Count)/$actualGlbs/$($destination.glbs)"
    }
    if ($actualPngs -ne [int]$destination.textures) {
        throw "Destination $key texture count disagrees: $actualPngs/$($destination.textures)"
    }
    $materialCatalog = Read-JsonFile (Join-Path $destinationRoot "material_catalog.json") "Destination material catalog"
    $catalogImages = @($materialCatalog.images)
    $catalogMaterials = @($materialCatalog.materials)
    $catalogAssets = @($materialCatalog.assets)
    if (
        [int]$materialCatalog.summary.glbs -ne $actualGlbs -or
        [int]$materialCatalog.summary.unique_images -ne $actualPngs -or
        [int]$materialCatalog.summary.unique_materials -ne [int]$destination.materials -or
        $catalogImages.Count -ne $actualPngs -or
        $catalogMaterials.Count -ne [int]$destination.materials -or
        $catalogAssets.Count -ne $actualGlbs -or
        [int]$manifest.material_dedupe.unique_images -ne $actualPngs -or
        [int]$manifest.material_dedupe.unique_materials -ne [int]$destination.materials -or
        [string]$manifest.material_dedupe.catalog -ne "material_catalog.json"
    ) {
        throw "Destination $key material catalog counts disagree with the destination."
    }
    $localImageKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    $catalogPngPaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($image in $catalogImages) {
        $imageKey = [string]$image.key
        $sha256 = [string]$image.sha256
        if (
            $sha256 -notmatch '^[0-9a-f]{64}$' -or
            $imageKey -ne "img_$sha256" -or
            -not $localImageKeys.Add($imageKey)
        ) {
            throw "Destination $key material catalog has an invalid or duplicate image key: $imageKey"
        }
        $imagePath = [IO.Path]::GetFullPath(
            (Join-Path $destinationRoot ([string]$image.relative_path).Replace('/', '\'))
        )
        if (
            -not $imagePath.StartsWith($destinationRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not $catalogPngPaths.Add($imagePath) -or
            -not $actualPngPaths.Contains($imagePath) -or
            [long]$image.byte_length -ne (Get-Item -LiteralPath $imagePath).Length -or
            (Get-FileHash -LiteralPath $imagePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha256
        ) {
            throw "Destination $key material catalog image does not match its PNG: $($image.relative_path)"
        }
        $null = $textureKeys.Add($imageKey)
    }
    foreach ($pngPath in $actualPngPaths) {
        if (-not $catalogPngPaths.Contains($pngPath)) {
            throw "Destination $key contains a PNG absent from its material catalog: $pngPath"
        }
    }

    $localMaterialKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    foreach ($material in $catalogMaterials) {
        $materialKey = [string]$material.key
        if ($materialKey -notmatch '^mat_[0-9a-f]{64}$' -or -not $localMaterialKeys.Add($materialKey)) {
            throw "Destination $key material catalog has an invalid or duplicate material key: $materialKey"
        }
        if ($null -eq $material.PSObject.Properties["signature"]) {
            throw "Destination $key material $materialKey has no signature."
        }
        $null = $materialKeys.Add($materialKey)
    }

    $catalogGlbPaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($asset in $catalogAssets) {
        $catalogGlbPath = [IO.Path]::GetFullPath(
            (Join-Path $destinationRoot ([string]$asset.glb).Replace('/', '\'))
        )
        if (
            -not $catalogGlbPath.StartsWith($destinationRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not $catalogGlbPaths.Add($catalogGlbPath) -or
            -not $declaredGlbs.Contains($catalogGlbPath)
        ) {
            throw "Destination $key material catalog has an invalid or duplicate GLB: $($asset.glb)"
        }
        $boundMaterialKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
        foreach ($binding in @($asset.materials)) {
            $boundKey = [string]$binding.material_key
            if (-not $localMaterialKeys.Contains($boundKey)) {
                throw "Destination $key GLB binds an unknown material key: $boundKey"
            }
            $null = $boundMaterialKeys.Add($boundKey)
        }
        if ($boundMaterialKeys.Count -ne [int]$asset.output_material_count) {
            throw "Destination $key GLB material bindings disagree with output_material_count: $($asset.glb)"
        }
        foreach ($binding in @($asset.images)) {
            if (-not $localImageKeys.Contains([string]$binding.image_key)) {
                throw "Destination $key GLB binds an unknown image key: $($binding.image_key)"
            }
        }
    }
    foreach ($declaredGlb in $declaredGlbs) {
        if (-not $catalogGlbPaths.Contains($declaredGlb)) {
            throw "Destination $key GLB is absent from its material catalog: $declaredGlb"
        }
    }
    foreach ($asset in @($manifest.assets.terrain)) {
        $null = $terrainKeys.Add([string]$asset.key)
    }
    foreach ($asset in @($manifest.assets.buildings)) {
        $null = $buildingKeys.Add([string]$asset.key)
    }
    $recalculatedGlbs += $actualGlbs
    $destinationByKey[$key] = $destination
    if ($RequireComplete) {
        $dedupeMarkerPath = Join-Path $destinationRoot ".dedupe-complete.json"
        $dedupeMarker = Read-JsonFile $dedupeMarkerPath "Destination dedupe marker"
        $markerPath = Join-Path $destinationRoot ".sync-complete.json"
        $marker = Read-JsonFile $markerPath "Destination sync marker"
        $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if (
            [int]$dedupeMarker.schema_version -ne 1 -or
            [string]$dedupeMarker.output_manifest_sha256 -ne $manifestHash -or
            [int]$dedupeMarker.glbs -ne $actualGlbs -or
            [int]$dedupeMarker.unique_images -ne $actualPngs -or
            [int]$dedupeMarker.unique_materials -ne [int]$destination.materials
        ) {
            throw "Destination $key dedupe marker does not match its validated assets."
        }
        if (
            [int]$marker.schema_version -ne 1 -or
            [int]$marker.matrix_id -ne [int]$destination.matrix_id -or
            [string]$marker.variant -ne $key -or
            [string]$marker.source_manifest_sha256 -ne $manifestHash -or
            [int]$marker.glbs -ne $actualGlbs -or
            [int]$marker.textures -ne $actualPngs
        ) {
            throw "Destination $key sync marker does not match its validated assets."
        }
    }
}

$referencedDestinations = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$readyMatrices = 0
$unresolvedMatrices = 0
$notExportedMatrices = 0
$recalculatedCells = 0
$recalculatedBuildings = 0
foreach ($matrix in $matrixEntries) {
    $matrixDestinationKeys = @($matrix.destinations)
    foreach ($keyValue in $matrixDestinationKeys) {
        $key = [string]$keyValue
        if (-not $destinationKeys.Contains($key)) {
            throw "Matrix $($matrix.id) references a missing destination: $key"
        }
        if (-not $referencedDestinations.Add($key)) {
            throw "Destination $key is referenced by more than one matrix entry."
        }
        if ([int]$destinationByKey[$key].matrix_id -ne [int]$matrix.id) {
            throw "Matrix $($matrix.id) references destination $key owned by another matrix."
        }
    }
    $status = [string]$matrix.status
    if ($status -eq "ready") {
        $readyMatrices++
        if ($matrixDestinationKeys.Count -eq 0) {
            throw "Ready matrix $($matrix.id) has no runnable destination."
        }
    }
    elseif ($status -eq "partially_exported") {
        $notExportedMatrices++
        if ($matrixDestinationKeys.Count -eq 0) {
            throw "Partially exported matrix $($matrix.id) has no exported destination."
        }
    }
    elseif ($status -eq "not_exported") {
        $notExportedMatrices++
        if ($matrixDestinationKeys.Count -ne 0) {
            throw "Unexported matrix $($matrix.id) exposes a runnable destination."
        }
    }
    elseif ($status -like "unresolved_*") {
        $unresolvedMatrices++
        if ($matrixDestinationKeys.Count -ne 0) {
            throw "Unresolved matrix $($matrix.id) exposes a runnable destination."
        }
    }
    else {
        throw "Matrix $($matrix.id) has an unknown status: $status"
    }
    if ($matrixDestinationKeys.Count -gt 0) {
        $firstDestination = $destinationByKey[[string]$matrixDestinationKeys[0]]
        foreach ($keyValue in $matrixDestinationKeys) {
            $destination = $destinationByKey[[string]$keyValue]
            if (
                [int]$destination.occupied_cells -ne [int]$firstDestination.occupied_cells -or
                [int]$destination.building_instances -ne [int]$firstDestination.building_instances
            ) {
                throw "Matrix $($matrix.id) variants disagree on matrix-scoped counts."
            }
        }
        $recalculatedCells += [int]$firstDestination.occupied_cells
        $recalculatedBuildings += [int]$firstDestination.building_instances
    }
}

foreach ($key in $destinationKeys) {
    if (-not $referencedDestinations.Contains($key)) {
        throw "Destination $key is not referenced by its matrix entry."
    }
}

if (
    $destinations.Count -ne [int]$catalog.summary.ready_destinations -or
    $readyMatrices -ne [int]$catalog.summary.ready_matrices -or
    $unresolvedMatrices -ne [int]$catalog.summary.unresolved_matrices -or
    $notExportedMatrices -ne [int]$catalog.summary.not_exported_matrices -or
    $recalculatedCells -ne [int]$catalog.summary.occupied_cells -or
    $recalculatedBuildings -ne [int]$catalog.summary.building_instances -or
    $recalculatedGlbs -ne [int]$catalog.summary.destination_scoped_glbs -or
    $terrainKeys.Count -ne [int]$catalog.summary.unique_terrain_assets -or
    $buildingKeys.Count -ne [int]$catalog.summary.unique_building_assets -or
    $textureKeys.Count -ne [int]$catalog.summary.unique_textures -or
    $materialKeys.Count -ne [int]$catalog.summary.unique_materials
) {
    throw "Matrix catalog summary does not match its validated records."
}

if ($RequireComplete) {
    $resolution = Read-JsonFile $ResolutionPath "Matrix AreaData resolution"
    if ([int]$resolution.schema_version -ne 1) {
        throw "Unsupported Matrix AreaData resolution schema: $($resolution.schema_version)"
    }
    $expectedKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    $expectedByMatrix = @{}
    $expectedDestinationByKey = @{}
    foreach ($variant in @($resolution.variants)) {
        $key = [string]$variant.variant
        $matrixId = [int]$variant.matrix_id
        $keyMatch = [regex]::Match($key, '^matrix_(\d{4})(?:_area_(\d{4}))?$')
        if (-not $keyMatch.Success -or [int]$keyMatch.Groups[1].Value -ne $matrixId) {
            throw "Area resolution variant does not match matrix ID $matrixId`: $key"
        }
        if (
            $keyMatch.Groups[2].Success -and
            ($null -eq $variant.area_data_id -or
                [int]$keyMatch.Groups[2].Value -ne [int]$variant.area_data_id)
        ) {
            throw "Area resolution variant does not match its AreaData ID: $key"
        }
        if (-not $expectedKeys.Add($key)) {
            throw "Area resolution contains duplicate variant: $key"
        }
        $expectedDestinationByKey[$key] = [pscustomobject]@{
            matrix_id = $matrixId
            area_data_id = $variant.area_data_id
        }
        if (-not $expectedByMatrix.ContainsKey($matrixId)) {
            $expectedByMatrix[$matrixId] = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
        }
        $null = $expectedByMatrix[$matrixId].Add($key)
    }
    $expectedUnresolved = New-Object System.Collections.Generic.HashSet[int]
    foreach ($record in @($resolution.unresolved)) {
        $matrixId = [int]$record.matrix_id
        if ($expectedByMatrix.ContainsKey($matrixId) -or -not $expectedUnresolved.Add($matrixId)) {
            throw "Area resolution contains duplicate or conflicting matrix $matrixId."
        }
    }
    if (
        $expectedByMatrix.Count + $expectedUnresolved.Count -ne $matrixEntries.Count -or
        [int]$catalog.summary.expected_destinations -ne $expectedKeys.Count -or
        [int]$resolution.summary.matrices -ne $matrixEntries.Count -or
        [int]$resolution.summary.ready_variants -ne $expectedKeys.Count -or
        [int]$resolution.summary.unresolved_orphans -ne $expectedUnresolved.Count
    ) {
        throw "Complete AreaData resolution does not cover the catalog exactly."
    }
    if ($catalog.summary.not_exported_matrices -ne 0) {
        throw "Complete validation found unexported matrices: $($catalog.summary.not_exported_matrices)"
    }
    if ($destinationKeys.Count -ne $expectedKeys.Count) {
        throw "Complete destination count disagrees with AreaData resolution: $($destinationKeys.Count)/$($expectedKeys.Count)"
    }
    foreach ($key in $expectedKeys) {
        if (-not $destinationKeys.Contains($key)) {
            throw "Resolved destination is absent from the catalog: $key"
        }
        $destination = $destinationByKey[$key]
        $expected = $expectedDestinationByKey[$key]
        $expectedArea = $expected.area_data_id
        $actualArea = $destination.area_data_id
        $areaMatches = ($null -eq $expectedArea -and $null -eq $actualArea) -or
            ($null -ne $expectedArea -and $null -ne $actualArea -and
                [int]$expectedArea -eq [int]$actualArea)
        if ([int]$destination.matrix_id -ne [int]$expected.matrix_id -or -not $areaMatches) {
            throw "Destination $key does not match its AreaData resolution record."
        }
    }
    foreach ($matrix in $matrixEntries) {
        $matrixId = [int]$matrix.id
        $actualKeys = @($matrix.destinations)
        if ($expectedByMatrix.ContainsKey($matrixId)) {
            if ([string]$matrix.status -ne "ready" -or $actualKeys.Count -ne $expectedByMatrix[$matrixId].Count) {
                throw "Resolved matrix $matrixId is not completely exported."
            }
            foreach ($key in $actualKeys) {
                if (-not $expectedByMatrix[$matrixId].Contains([string]$key)) {
                    throw "Matrix $matrixId exposes an unexpected destination: $key"
                }
            }
        }
        elseif (-not $expectedUnresolved.Contains($matrixId) -or [string]$matrix.status -notlike "unresolved_*") {
            throw "Matrix $matrixId does not match its AreaData resolution status."
        }
    }
    if (
        [int]$catalog.summary.ready_matrices + [int]$catalog.summary.unresolved_matrices -ne
        [int]$catalog.summary.source_matrices
    ) {
        throw "Complete matrix status counts do not cover every source matrix."
    }
}

Write-Host "DSPRE matrix catalog validation complete."
Write-Host "  Matrices:     $($matrixEntries.Count)"
Write-Host "  Destinations: $($destinations.Count)"
Write-Host "  Complete:     $RequireComplete"
