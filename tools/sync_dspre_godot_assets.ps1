[CmdletBinding()]
param(
    [string]$SourceRoot = "",
    [string]$ProjectRoot = "",
    [ValidateSet("Auto", "HardLink", "Copy")]
    [string]$Mode = "Auto",
    [string]$DedupeToolSha256 = "",
    [string]$SyncToolSha256 = "",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "dspre_collision_support.ps1")
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path $workspaceRoot "generated\dspre_glb_dedup\matrix_0000"
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $workspaceRoot "new-game-project"
}

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$utf8NoBom = [Text.UTF8Encoding]::new($false)

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

function Get-StageFilesWithoutReparsePoints {
    param(
        [string]$RootPath,
        [string]$Label = "Stage tree"
    )

    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
    $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if (-not $rootItem.PSIsContainer) {
        throw "$Label root is not a directory: $root"
    }
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label root cannot be a reparse point: $root"
    }

    $rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
    $directories = [Collections.Generic.Queue[string]]::new()
    $files = [Collections.Generic.List[IO.FileInfo]]::new()
    $directories.Enqueue($root)
    while ($directories.Count -ne 0) {
        $directory = $directories.Dequeue()
        foreach ($entry in @(Get-ChildItem -LiteralPath $directory -Force)) {
            $fullPath = [IO.Path]::GetFullPath($entry.FullName)
            if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "$Label entry escaped its root: $fullPath"
            }
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Label cannot contain a reparse point: $fullPath"
            }
            if ($entry.PSIsContainer) {
                $directories.Enqueue($fullPath)
            }
            else {
                $files.Add($entry)
            }
        }
    }
    return $files.ToArray()
}

function Get-StageFileRecords {
    param(
        [string]$RootPath,
        [string[]]$ExcludedRelativePaths = @(),
        [switch]$IgnoreGodotImportSidecars
    )

    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    $rootPrefix = $root + '\'
    $excluded = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($relativePath in $ExcludedRelativePaths) {
        $null = $excluded.Add(([string]$relativePath).Replace('\', '/'))
    }
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-StageFilesWithoutReparsePoints `
        -RootPath $root `
        -Label "Stage output")) {
        $fullPath = [IO.Path]::GetFullPath($file.FullName)
        if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Stage output file escaped its root: $fullPath"
        }
        $relativePath = $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
        if (
            $excluded.Contains($relativePath) -or
            ($IgnoreGodotImportSidecars -and $relativePath.EndsWith(
                ".import",
                [StringComparison]::OrdinalIgnoreCase
            ))
        ) {
            continue
        }
        $records.Add([pscustomobject][ordered]@{
            relative_path = $relativePath
            byte_length = [long]$file.Length
            sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    }
    return @($records | Sort-Object { [string]$_.relative_path })
}

function Assert-StageFileRecords {
    param(
        [string]$RootPath,
        [object[]]$ExpectedRecords,
        [string[]]$ExcludedRelativePaths = @(),
        [switch]$IgnoreGodotImportSidecars,
        [string]$Label = "Stage output"
    )

    $expectedByPath = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in @($ExpectedRecords)) {
        $relativePath = ([string]$record.relative_path).Replace('\', '/')
        if (
            [string]::IsNullOrWhiteSpace($relativePath) -or
            [IO.Path]::IsPathRooted($relativePath) -or
            $relativePath -match '(^|/)\.\.(/|$)' -or
            $expectedByPath.ContainsKey($relativePath) -or
            [long]$record.byte_length -lt 0 -or
            [string]$record.sha256 -notmatch '^[0-9a-f]{64}$'
        ) {
            throw "$Label contains an invalid or duplicate file record: $relativePath"
        }
        $expectedByPath.Add($relativePath, $record)
    }
    $actualRecords = @(Get-StageFileRecords `
        -RootPath $RootPath `
        -ExcludedRelativePaths $ExcludedRelativePaths `
        -IgnoreGodotImportSidecars:$IgnoreGodotImportSidecars)
    if ($actualRecords.Count -ne $expectedByPath.Count) {
        throw "$Label file count does not match its completion record."
    }
    foreach ($actual in $actualRecords) {
        $relativePath = [string]$actual.relative_path
        if (-not $expectedByPath.ContainsKey($relativePath)) {
            throw "$Label contains an undeclared file: $relativePath"
        }
        $expected = $expectedByPath[$relativePath]
        if (
            [long]$actual.byte_length -ne [long]$expected.byte_length -or
            [string]$actual.sha256 -ne [string]$expected.sha256
        ) {
            throw "$Label file content does not match its completion record: $relativePath"
        }
    }
    return $actualRecords
}

$actualDedupeToolSha256 = Get-DspreToolFileFingerprint `
    -Path (Join-Path $PSScriptRoot "dedupe_dspre_materials.ps1")
if ([string]::IsNullOrWhiteSpace($DedupeToolSha256)) {
    $DedupeToolSha256 = $actualDedupeToolSha256
}
else {
    $DedupeToolSha256 = Assert-DspreSha256Fingerprint `
        $DedupeToolSha256 `
        "Expected material dedupe tool fingerprint"
    if ($DedupeToolSha256 -ne $actualDedupeToolSha256) {
        throw "Material dedupe tool changed before the sync stage started."
    }
}
$actualSyncToolSha256 = Get-DspreToolFileFingerprint -Path $PSCommandPath
if ([string]::IsNullOrWhiteSpace($SyncToolSha256)) {
    $SyncToolSha256 = $actualSyncToolSha256
}
else {
    $SyncToolSha256 = Assert-DspreSha256Fingerprint `
        $SyncToolSha256 `
        "Expected Godot sync tool fingerprint"
    if ($SyncToolSha256 -ne $actualSyncToolSha256) {
        throw "Godot sync tool changed before the stage started."
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) {
    throw "Godot project was not found: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot "manifest.json") -PathType Leaf)) {
    throw "Deduplicated DSPRE manifest was not found: $SourceRoot"
}
$manifestPath = Join-Path $SourceRoot "manifest.json"
$manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$null = Assert-DspreCollisionManifest `
    -Manifest $manifest `
    -Label "Deduplicated source manifest" `
    -ExpectedManifestSchema 3
$matrixId = [int]$manifest.matrix.id
if ($matrixId -lt 0 -or $matrixId -gt 9999) {
    throw "Manifest matrix ID is outside the supported range: $matrixId"
}
$matrixVariant = if ($null -ne $manifest.matrix.PSObject.Properties["variant"]) {
    [string]$manifest.matrix.variant
}
else {
    "matrix_{0:D4}" -f $matrixId
}
$variantMatch = [regex]::Match($matrixVariant, '^matrix_(\d{4})(?:_area_(\d{4}))?$')
if (-not $variantMatch.Success) {
    throw "Manifest matrix variant is invalid: $matrixVariant"
}
if ([int]$variantMatch.Groups[1].Value -ne $matrixId) {
    throw "Manifest matrix variant does not match matrix ID $matrixId`: $matrixVariant"
}
if ($variantMatch.Groups[2].Success) {
    $manifestAreaId = if ($null -ne $manifest.matrix.PSObject.Properties["area_data_id"]) {
        $manifest.matrix.area_data_id
    }
    else {
        $null
    }
    if ($null -eq $manifestAreaId -or [int]$manifestAreaId -ne [int]$variantMatch.Groups[2].Value) {
        throw "Manifest matrix variant does not match its AreaData ID: $matrixVariant"
    }
}
$destinationRoot = Join-Path $ProjectRoot "assets\platinum\$matrixVariant"

$platinumRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot "assets\platinum")).TrimEnd('\')
$resolvedDestination = [IO.Path]::GetFullPath($destinationRoot).TrimEnd('\', '/')
$platinumPrefix = $platinumRoot + [IO.Path]::DirectorySeparatorChar
if (
    $resolvedDestination.Equals($platinumRoot, [StringComparison]::OrdinalIgnoreCase) -or
    -not $resolvedDestination.StartsWith($platinumPrefix, [StringComparison]::OrdinalIgnoreCase)
) {
    throw "Refusing to write outside a Godot Platinum destination: $resolvedDestination"
}
$resolvedDestination = Assert-DspreSafeRecursiveDeletePath `
    -Path $resolvedDestination `
    -AllowedRoot $ProjectRoot
$sourcePrefix = $SourceRoot + '\'
$destinationPrefix = $resolvedDestination + '\'
if (
    $SourceRoot.Equals($resolvedDestination, [StringComparison]::OrdinalIgnoreCase) -or
    $sourcePrefix.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    $destinationPrefix.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)
) {
    throw "Source and destination must not overlap: $SourceRoot -> $resolvedDestination"
}

$summaryPath = Join-Path $SourceRoot "summary.json"
$catalogPath = Join-Path $SourceRoot "material_catalog.json"
$dedupeMarkerPath = Join-Path $SourceRoot ".dedupe-complete.json"
foreach ($requiredPath in @($summaryPath, $catalogPath, $dedupeMarkerPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Deduplicated source is incomplete; required file is missing: $requiredPath"
    }
}
$summary = [IO.File]::ReadAllText($summaryPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$materialCatalog = [IO.File]::ReadAllText($catalogPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$dedupeMarker = [IO.File]::ReadAllText($dedupeMarkerPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$sourceManifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()

$sourcePayloadRecords = @(Assert-StageFileRecords `
    -RootPath $SourceRoot `
    -ExpectedRecords @($dedupeMarker.files) `
    -ExcludedRelativePaths @(".dedupe-complete.json") `
    -Label "Deduplicated source")
$dedupeMarkerItem = Get-Item -LiteralPath $dedupeMarkerPath
$sourceTransferRecords = @(
    @($sourcePayloadRecords) + @([pscustomobject][ordered]@{
        relative_path = ".dedupe-complete.json"
        byte_length = [long]$dedupeMarkerItem.Length
        sha256 = (Get-FileHash -LiteralPath $dedupeMarkerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }) | Sort-Object { [string]$_.relative_path }
)
$sourceRecordByPath = @{}
foreach ($record in $sourcePayloadRecords) {
    $sourceRecordByPath[([string]$record.relative_path).ToLowerInvariant()] = $record
}
$sourceFiles = @(
    foreach ($record in $sourceTransferRecords) {
        Get-Item -LiteralPath (Join-Path $SourceRoot ([string]$record.relative_path).Replace('/', '\'))
    }
)
$actualSourceGlbFiles = @($sourceFiles | Where-Object { $_.Extension -ieq ".glb" })
$actualSourceGlbs = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
foreach ($glb in $actualSourceGlbFiles) {
    if (-not (Test-GlbFile $glb.FullName)) {
        throw "Deduplicated source contains an invalid GLB: $($glb.FullName)"
    }
    $null = $actualSourceGlbs.Add($glb.FullName)
}
$declaredGlbs = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
foreach ($asset in @($manifest.assets.terrain) + @($manifest.assets.buildings)) {
    foreach ($relativeGlb in @($asset.output_glbs)) {
        $relativeGlbPath = [string]$relativeGlb
        $declaredSourcePath = [IO.Path]::GetFullPath(
            (Join-Path $SourceRoot $relativeGlbPath.Replace('/', '\'))
        )
        if (-not $declaredSourcePath.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Manifest GLB path escapes its source root: $relativeGlbPath"
        }
        if (-not $declaredGlbs.Add($declaredSourcePath)) {
            throw "Manifest declares a GLB more than once: $relativeGlbPath"
        }
        if (-not $actualSourceGlbs.Contains($declaredSourcePath)) {
            throw "Manifest declares a missing GLB: $relativeGlbPath"
        }
    }
}
if ($declaredGlbs.Count -ne $actualSourceGlbs.Count) {
    throw "Deduplicated source GLB set does not match its manifest."
}
foreach ($glbPath in $actualSourceGlbs) {
    if (-not $declaredGlbs.Contains($glbPath)) {
        throw "Deduplicated source contains an undeclared GLB: $glbPath"
    }
}

$textureRelative = [string]$manifest.material_dedupe.shared_texture_root
if ([string]::IsNullOrWhiteSpace($textureRelative) -or [IO.Path]::IsPathRooted($textureRelative)) {
    throw "Manifest shared texture root must be a relative path: $textureRelative"
}
$sourceTextureRoot = [IO.Path]::GetFullPath(
    (Join-Path $SourceRoot $textureRelative.Replace('/', '\'))
).TrimEnd('\')
if (
    -not ($sourceTextureRoot + '\').StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase) -or
    -not (Test-Path -LiteralPath $sourceTextureRoot -PathType Container)
) {
    throw "Manifest shared texture root is missing or escapes the source: $sourceTextureRoot"
}
$allSourcePngFiles = @($sourceFiles | Where-Object { $_.Extension -ieq ".png" })
$sourcePngFiles = @($allSourcePngFiles | Where-Object {
    $_.DirectoryName.Equals($sourceTextureRoot, [StringComparison]::OrdinalIgnoreCase)
})
if ($sourcePngFiles.Count -ne $allSourcePngFiles.Count) {
    throw "Deduplicated source contains PNGs outside its shared texture root."
}
$sourcePngPaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
foreach ($png in $sourcePngFiles) {
    $null = $sourcePngPaths.Add($png.FullName)
}
$catalogPngPaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
$catalogImageKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$catalogImages = @($materialCatalog.images)
foreach ($image in $catalogImages) {
    $imageKey = [string]$image.key
    $sha256 = [string]$image.sha256
    $imagePath = [IO.Path]::GetFullPath(
        (Join-Path $SourceRoot ([string]$image.relative_path).Replace('/', '\'))
    )
    $imageRelativePath = $imagePath.Substring($sourcePrefix.Length).Replace('\', '/')
    $imageRecordKey = $imageRelativePath.ToLowerInvariant()
    if (
        $sha256 -notmatch '^[0-9a-f]{64}$' -or
        $imageKey -ne "img_$sha256" -or
        -not $catalogImageKeys.Add($imageKey) -or
        -not $imagePath.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $catalogPngPaths.Add($imagePath) -or
        -not $sourcePngPaths.Contains($imagePath) -or
        -not $sourceRecordByPath.ContainsKey($imageRecordKey) -or
        [long]$image.byte_length -ne [long]$sourceRecordByPath[$imageRecordKey].byte_length -or
        [string]$sourceRecordByPath[$imageRecordKey].sha256 -ne $sha256
    ) {
        throw "Material catalog contains an invalid image record: $imageKey"
    }
}
if ($catalogPngPaths.Count -ne $sourcePngPaths.Count) {
    throw "Deduplicated source PNG set does not match its material catalog."
}

$catalogMaterials = @($materialCatalog.materials)
$catalogMaterialKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
foreach ($material in $catalogMaterials) {
    $materialKey = [string]$material.key
    if (
        $materialKey -notmatch '^mat_[0-9a-f]{64}$' -or
        -not $catalogMaterialKeys.Add($materialKey) -or
        $null -eq $material.PSObject.Properties["signature"] -or
        $material.signature -isnot [pscustomobject]
    ) {
        throw "Material catalog contains an invalid or duplicate material key: $materialKey"
    }
}
$catalogGlbs = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
foreach ($asset in @($materialCatalog.assets)) {
    $catalogGlbPath = [IO.Path]::GetFullPath(
        (Join-Path $SourceRoot ([string]$asset.glb).Replace('/', '\'))
    )
    if (
        -not $catalogGlbPath.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $catalogGlbs.Add($catalogGlbPath) -or
        -not $declaredGlbs.Contains($catalogGlbPath)
    ) {
        throw "Material catalog contains an invalid or duplicate GLB: $($asset.glb)"
    }
    $materialBindings = @($asset.materials)
    $boundMaterialKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    foreach ($binding in $materialBindings) {
        $boundKey = [string]$binding.material_key
        if (-not $catalogMaterialKeys.Contains($boundKey)) {
            throw "Material catalog GLB binds an unknown material key: $boundKey"
        }
        $null = $boundMaterialKeys.Add($boundKey)
    }
    if (
        $materialBindings.Count -eq 0 -or
        [int]$asset.output_material_count -le 0 -or
        $boundMaterialKeys.Count -ne [int]$asset.output_material_count
    ) {
        throw "Material catalog GLB material bindings disagree: $($asset.glb)"
    }
    foreach ($binding in @($asset.images)) {
        if (-not $catalogImageKeys.Contains([string]$binding.image_key)) {
            throw "Material catalog GLB binds an unknown image key: $($binding.image_key)"
        }
    }
}
if ($catalogGlbs.Count -ne $declaredGlbs.Count) {
    throw "Material catalog GLB set does not match the manifest."
}

$expectedGlbCount = $declaredGlbs.Count
$expectedPngCount = $sourcePngPaths.Count
$expectedMaterialCount = $catalogMaterialKeys.Count
if (
    [int]$manifest.summary.failed -ne 0 -or
    [int]$materialCatalog.schema_version -ne 1 -or
    [string]$manifest.material_dedupe.catalog -ne "material_catalog.json" -or
    [int]$manifest.material_dedupe.unique_images -ne $expectedPngCount -or
    [int]$manifest.material_dedupe.unique_materials -ne $expectedMaterialCount -or
    [int]$summary.glbs -ne $expectedGlbCount -or
    [int]$summary.unique_images -ne $expectedPngCount -or
    [int]$summary.unique_materials -ne $expectedMaterialCount -or
    [int]$materialCatalog.summary.glbs -ne $expectedGlbCount -or
    [int]$materialCatalog.summary.unique_images -ne $expectedPngCount -or
    [int]$materialCatalog.summary.unique_materials -ne $expectedMaterialCount -or
    [int]$dedupeMarker.schema_version -ne 2 -or
    [string]$dedupeMarker.dedupe_tool_sha256 -ne $DedupeToolSha256 -or
    [string]$dedupeMarker.output_manifest_sha256 -ne $sourceManifestHash -or
    [string]$dedupeMarker.source_manifest_sha256 -notmatch '^[0-9a-f]{64}$' -or
    [int]$dedupeMarker.glbs -ne $expectedGlbCount -or
    [int]$dedupeMarker.unique_images -ne $expectedPngCount -or
    [int]$dedupeMarker.unique_materials -ne $expectedMaterialCount
) {
    throw "Deduplicated source summary, catalog, manifest, and completion marker disagree."
}
$destinationTextureRoot = [IO.Path]::GetFullPath(
    (Join-Path $resolvedDestination $textureRelative.Replace('/', '\'))
).TrimEnd('\')
if (-not ($destinationTextureRoot + '\').StartsWith(
    $resolvedDestination + '\',
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw "Refusing to create a shared texture root outside the destination: $destinationTextureRoot"
}
$files = @($sourceFiles | Sort-Object FullName)
if ($files.Count -eq 0) {
    throw "No source assets were found: $SourceRoot"
}

$sourceDrive = [IO.Path]::GetPathRoot($SourceRoot)
$destinationDrive = [IO.Path]::GetPathRoot($resolvedDestination)
$canHardLink = $sourceDrive.Equals($destinationDrive, [StringComparison]::OrdinalIgnoreCase)
$useHardLinks = $Mode -eq "HardLink" -or ($Mode -eq "Auto" -and $canHardLink)
if ($Mode -eq "HardLink" -and -not $canHardLink) {
    throw "Hard links require source and destination on the same volume."
}

if (Test-Path -LiteralPath $resolvedDestination) {
    if (-not $Force) {
        throw "Destination already exists. Pass -Force to rebuild it: $resolvedDestination"
    }
    $resolvedDestination = Assert-DspreSafeRecursiveDeletePath `
        -Path $resolvedDestination `
        -AllowedRoot $ProjectRoot
    $null = @(Get-StageFilesWithoutReparsePoints `
        -RootPath $resolvedDestination `
        -Label "Existing Godot sync destination")
    Remove-Item -LiteralPath $resolvedDestination -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedDestination -Force | Out-Null
New-Item -ItemType Directory -Path $destinationTextureRoot -Force | Out-Null

$linked = 0
$copied = 0
for ($index = 0; $index -lt $files.Count; $index++) {
    $sourceFile = $files[$index]
    $relativePath = $sourceFile.FullName.Substring($SourceRoot.Length).TrimStart('\')
    $destinationPath = Join-Path $resolvedDestination $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null

    if ($useHardLinks) {
        try {
            New-Item -ItemType HardLink -Path $destinationPath -Target $sourceFile.FullName -Force | Out-Null
            $linked++
        }
        catch {
            if ($Mode -eq "HardLink") {
                throw
            }
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationPath -Force
            $copied++
        }
    }
    else {
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationPath -Force
        $copied++
    }

    Write-Progress -Activity "Syncing DSPRE assets into Godot" -Status "$($index + 1) / $($files.Count)" -PercentComplete (100.0 * ($index + 1) / $files.Count)
}
Write-Progress -Activity "Syncing DSPRE assets into Godot" -Completed

$destinationFileRecords = @(Assert-StageFileRecords `
    -RootPath $resolvedDestination `
    -ExpectedRecords $sourceTransferRecords `
    -ExcludedRelativePaths @(".sync-complete.json") `
    -IgnoreGodotImportSidecars `
    -Label "Godot sync destination")
$glbCount = @($destinationFileRecords | Where-Object {
    ([string]$_.relative_path).EndsWith(".glb", [StringComparison]::OrdinalIgnoreCase)
}).Count
$pngCount = @($destinationFileRecords | Where-Object {
    ([string]$_.relative_path).EndsWith(".png", [StringComparison]::OrdinalIgnoreCase)
}).Count
if ($glbCount -ne $expectedGlbCount -or $pngCount -ne $expectedPngCount) {
    throw "Synced matrix $matrixId asset counts are unexpected: $glbCount/$expectedGlbCount GLBs, $pngCount/$expectedPngCount PNGs."
}

$completionMarker = [pscustomobject][ordered]@{
    schema_version = 2
    matrix_id = $matrixId
    variant = $matrixVariant
    dedupe_tool_sha256 = $DedupeToolSha256
    sync_tool_sha256 = $SyncToolSha256
    source_manifest_sha256 = $sourceManifestHash
    glbs = $glbCount
    textures = $pngCount
    files = $destinationFileRecords
    completed_utc = [DateTime]::UtcNow.ToString("o")
}
[IO.File]::WriteAllText(
    (Join-Path $resolvedDestination ".sync-complete.json"),
    ($completionMarker | ConvertTo-Json -Depth 6),
    $utf8NoBom
)

Write-Host "DSPRE $matrixVariant Godot asset sync complete."
Write-Host "  Destination: $resolvedDestination"
Write-Host "  Hard linked: $linked"
Write-Host "  Copied:      $copied"
Write-Host "  GLBs:        $glbCount"
Write-Host "  PNGs:        $pngCount"
