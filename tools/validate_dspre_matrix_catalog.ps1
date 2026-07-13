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
. (Join-Path $PSScriptRoot "dspre_collision_support.ps1")
if ([string]::IsNullOrWhiteSpace($ResolutionPath)) {
    $ResolutionPath = Join-Path $ProjectRoot "generated\dspre_matrix_area_overrides.json"
}
$godotRoot = Join-Path $ProjectRoot "new-game-project"
$platinumRoot = [IO.Path]::GetFullPath((Join-Path $godotRoot "assets\platinum")).TrimEnd('\')
$catalogPath = Join-Path $platinumRoot "matrix_catalog.json"
$rawRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot "generated\dspre_glb")).TrimEnd('\')
$dedupRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot "generated\dspre_glb_dedup")).TrimEnd('\')
$rawRoot = Assert-DspreSafeRecursiveDeletePath -Path $rawRoot -AllowedRoot $ProjectRoot
$dedupRoot = Assert-DspreSafeRecursiveDeletePath -Path $dedupRoot -AllowedRoot $ProjectRoot
$platinumRoot = Assert-DspreSafeRecursiveDeletePath -Path $platinumRoot -AllowedRoot $ProjectRoot
$generatedCatalogPath = Join-Path $dedupRoot "matrix_catalog.json"

function Get-ValidatedRegularFile {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label was not found: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (
        $item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    ) {
        throw "$Label must be a regular non-reparse file: $Path"
    }
    return $item
}

function Read-JsonFile {
    param([string]$Path, [string]$Label)

    $null = Get-ValidatedRegularFile -Path $Path -Label $Label
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Assert-FilesByteIdentical {
    param(
        [string]$ExpectedPath,
        [string]$ActualPath,
        [string]$Label
    )

    foreach ($record in @(
        [pscustomobject]@{ Path = $ExpectedPath; Kind = "expected" },
        [pscustomobject]@{ Path = $ActualPath; Kind = "actual" }
    )) {
        if (-not (Test-Path -LiteralPath $record.Path)) {
            throw "$Label $($record.Kind) file was not found: $($record.Path)"
        }
        $item = Get-Item -LiteralPath $record.Path -Force -ErrorAction Stop
        if (
            $item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        ) {
            throw "$Label $($record.Kind) path must be a regular non-reparse file: $($record.Path)"
        }
    }
    $expectedBytes = [IO.File]::ReadAllBytes($ExpectedPath)
    $actualBytes = [IO.File]::ReadAllBytes($ActualPath)
    if ($expectedBytes.Length -ne $actualBytes.Length) {
        throw "$Label files are not byte-identical."
    }
    for ($index = 0; $index -lt $expectedBytes.Length; $index++) {
        if ($expectedBytes[$index] -ne $actualBytes[$index]) {
            throw "$Label files are not byte-identical."
        }
    }
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

function Assert-TreeHasNoReparsePoints {
    param([string]$RootPath, [string]$Label)

    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    $rootPrefix = $root + '\'
    $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if (-not $rootItem.PSIsContainer) {
        throw "$Label root is not a directory: $root"
    }
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label root cannot be a reparse point: $root"
    }
    $directories = New-Object 'System.Collections.Generic.Queue[object]'
    $directories.Enqueue($rootItem)
    while ($directories.Count -gt 0) {
        $directory = $directories.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction Stop)) {
            $fullPath = [IO.Path]::GetFullPath($item.FullName)
            if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "$Label entry escaped its root: $fullPath"
            }
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Label cannot contain a reparse point: $fullPath"
            }
            if ($item.PSIsContainer) {
                $directories.Enqueue($item)
            }
        }
    }
    return $root
}

function Assert-ExpectedDestinationTree {
    param(
        [string]$RootPath,
        [string[]]$ExpectedKeys,
        [string[]]$AllowedRootFiles = @(),
        [string]$Label
    )

    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if (
        -not $rootItem.PSIsContainer -or
        ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    ) {
        throw "$Label root must be a regular directory: $root"
    }
    $expected = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    foreach ($key in @($ExpectedKeys)) {
        if (
            [string]$key -notmatch '^matrix_\d{4}(_area_\d{4})?$' -or
            -not $expected.Add([string]$key)
        ) {
            throw "$Label received an invalid or duplicate expected destination: $key"
        }
    }
    $allowedFiles = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($fileName in @($AllowedRootFiles)) {
        $null = $allowedFiles.Add([string]$fileName)
    }
    $actual = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label root cannot contain a reparse point: $($item.FullName)"
        }
        if ($item.PSIsContainer) {
            if (-not $expected.Contains($item.Name) -or -not $actual.Add($item.Name)) {
                throw "$Label contains an unexpected destination directory: $($item.Name)"
            }
        }
        elseif (-not $allowedFiles.Contains($item.Name)) {
            throw "$Label contains an unexpected root file: $($item.Name)"
        }
    }
    if ($actual.Count -ne $expected.Count) {
        $missing = @($expected | Where-Object { -not $actual.Contains($_) })
        throw "$Label destination coverage is incomplete. Missing: $($missing -join ', ')"
    }
    return $actual.Count
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
    $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if (-not $rootItem.PSIsContainer) {
        throw "Validated destination root is not a directory: $root"
    }
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Validated destination root cannot be a reparse-point directory: $root"
    }
    $directories = New-Object 'System.Collections.Generic.Queue[string]'
    $directories.Enqueue($root)
    while ($directories.Count -gt 0) {
        $directory = $directories.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)) {
            $fullPath = [IO.Path]::GetFullPath($item.FullName)
            if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Validated destination entry escaped its root: $fullPath"
            }
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Validated destination cannot contain a reparse point: $fullPath"
            }
            if ($item.PSIsContainer) {
                $directories.Enqueue($fullPath)
                continue
            }
            $relativePath = $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
            if (
                $excluded.Contains($relativePath) -or
                ($IgnoreGodotImportSidecars -and (
                    $relativePath.EndsWith(
                        ".import",
                        [StringComparison]::OrdinalIgnoreCase
                    ) -or
                    $relativePath -match '(?i)\.import~[^/]+\.tmp$'
                ))
            ) {
                continue
            }
            $records.Add([pscustomobject][ordered]@{
                relative_path = $relativePath
                byte_length = [long]$item.Length
                sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            })
        }
    }
    return @($records | Sort-Object { [string]$_.relative_path })
}

function Assert-StageFileRecords {
    param(
        [string]$RootPath,
        [object[]]$ExpectedRecords,
        [string[]]$ExcludedRelativePaths = @(),
        [switch]$IgnoreGodotImportSidecars,
        [string]$Label
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
        throw "$Label file count does not match its completion marker."
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
            throw "$Label file content does not match its completion marker: $relativePath"
        }
    }
    return $actualRecords
}

function Assert-EquivalentStageFileRecords {
    param(
        [object[]]$ExpectedRecords,
        [object[]]$ActualRecords,
        [string]$Label
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
    if ($expectedByPath.Count -ne @($ActualRecords).Count) {
        throw "$Label file sets have different counts."
    }
    foreach ($actual in @($ActualRecords)) {
        $relativePath = ([string]$actual.relative_path).Replace('\', '/')
        if (-not $expectedByPath.ContainsKey($relativePath)) {
            throw "$Label contains an unexpected file: $relativePath"
        }
        $expected = $expectedByPath[$relativePath]
        if (
            [long]$actual.byte_length -ne [long]$expected.byte_length -or
            [string]$actual.sha256 -ne [string]$expected.sha256
        ) {
            throw "$Label contains different file content: $relativePath"
        }
    }
}

function Get-ManifestVariantName {
    param($Manifest)

    if ($null -ne $Manifest.matrix.PSObject.Properties["variant"]) {
        return [string]$Manifest.matrix.variant
    }
    return "matrix_{0:D4}" -f [int]$Manifest.matrix.id
}

function Get-OptionalAreaDataId {
    param($Record)

    if ($null -ne $Record.PSObject.Properties["area_data_id"]) {
        return $Record.area_data_id
    }
    return $null
}

function Test-AreaDataIdsEqual {
    param($Expected, $Actual)

    return ($null -eq $Expected -and $null -eq $Actual) -or
        ($null -ne $Expected -and $null -ne $Actual -and [int]$Expected -eq [int]$Actual)
}

function Assert-GeneratedDestinationStages {
    param(
        [object[]]$Variants,
        [string]$RawRoot,
        [string]$DedupRoot,
		[string]$ExpectedExporterSha256,
		[string]$ExpectedSupportToolSha256,
		[string]$ExpectedDedupeToolSha256,
		[string]$ExpectedAreaResolutionSha256,
		[hashtable]$SyncedDedupeRecordsByKey,
		[hashtable]$SyncedDedupeMarkerSha256ByKey
	)

    $variantKeys = New-Object System.Collections.Generic.List[string]
    $uniqueVariantKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    foreach ($variant in @($Variants)) {
        $key = [string]$variant.variant
        if (
            $key -notmatch '^matrix_\d{4}(_area_\d{4})?$' -or
            -not $uniqueVariantKeys.Add($key)
        ) {
            throw "Generated stage validation received an invalid or duplicate variant: $key"
        }
        $variantKeys.Add($key)
    }
    $rawCoverage = Assert-ExpectedDestinationTree `
        -RootPath $RawRoot `
        -ExpectedKeys $variantKeys `
        -Label "Generated raw tree"
    $dedupCoverage = Assert-ExpectedDestinationTree `
        -RootPath $DedupRoot `
        -ExpectedKeys $variantKeys `
        -AllowedRootFiles @("matrix_catalog.json") `
        -Label "Generated dedupe tree"
    if ($rawCoverage -ne $variantKeys.Count -or $dedupCoverage -ne $variantKeys.Count) {
        throw "Generated stage destination counts do not cover every expected variant."
    }

	$validated = 0
	$sharedDspreSourceSha256 = ""
	$sharedApiculaSha256 = ""
	foreach ($variant in @($Variants)) {
        $key = [string]$variant.variant
        $matrixId = [int]$variant.matrix_id
        $expectedArea = $variant.area_data_id
        $rawDestinationRoot = Join-Path $RawRoot $key
        $rawRecords = @(Get-StageFileRecords `
            -RootPath $rawDestinationRoot `
            -ExcludedRelativePaths @(".export-complete.json"))
        $rawMarkerPath = Join-Path $rawDestinationRoot ".export-complete.json"
        $rawManifestPath = Join-Path $rawDestinationRoot "manifest.json"
        $rawSummaryPath = Join-Path $rawDestinationRoot "summary.json"
		$rawMarker = Read-JsonFile $rawMarkerPath "Generated raw marker $key"
        $rawManifest = Read-JsonFile $rawManifestPath "Generated raw manifest $key"
        $rawSummary = Read-JsonFile $rawSummaryPath "Generated raw summary $key"
        $null = Assert-DspreCollisionManifest `
            -Manifest $rawManifest `
            -Label "Generated raw destination $key" `
            -ExpectedManifestSchema 2
		$rawManifestHash = (
			Get-FileHash -LiteralPath $rawManifestPath -Algorithm SHA256
		).Hash.ToLowerInvariant()
		$rawDspreSourceSha256 = Assert-DspreSha256Fingerprint `
			([string]$rawMarker.dspre_source_sha256) `
			"Generated raw DSPRE source fingerprint"
		$rawApiculaSha256 = Assert-DspreSha256Fingerprint `
			([string]$rawMarker.apicula_sha256) `
			"Generated raw apicula fingerprint"
		if ([string]::IsNullOrWhiteSpace($sharedDspreSourceSha256)) {
			$sharedDspreSourceSha256 = $rawDspreSourceSha256
			$sharedApiculaSha256 = $rawApiculaSha256
		}
		elseif (
			$rawDspreSourceSha256 -ne $sharedDspreSourceSha256 -or
			$rawApiculaSha256 -ne $sharedApiculaSha256
		) {
			throw "Generated raw destination $key does not share the catalog's source/tool snapshot."
		}
		$null = Assert-DspreRawExportMarker `
            -Marker $rawMarker `
            -ExpectedMatrixId $matrixId `
            -ExpectedVariant $key `
            -ExpectedAreaDataId $expectedArea `
			-ExpectedDspreSourceSha256 $rawDspreSourceSha256 `
            -ExpectedExporterSha256 $ExpectedExporterSha256 `
            -ExpectedSupportToolSha256 $ExpectedSupportToolSha256 `
			-ExpectedApiculaSha256 $rawApiculaSha256 `
            -ExpectedAreaResolutionSha256 $ExpectedAreaResolutionSha256 `
            -ExpectedManifestSha256 $rawManifestHash `
            -ExpectedOccupiedCells @($rawManifest.cells).Count `
            -ExpectedCollisionAssets @($rawManifest.collision_assets).Count `
            -Label "Generated raw marker $key"
        $null = Assert-EquivalentStageFileRecords `
            -ExpectedRecords @($rawMarker.files) `
            -ActualRecords $rawRecords `
            -Label "Generated raw destination $key"
        $rawManifestArea = Get-OptionalAreaDataId $rawManifest.matrix
        $rawSummaryArea = Get-OptionalAreaDataId $rawSummary
		if (
            [int]$rawManifest.matrix.id -ne $matrixId -or
            (Get-ManifestVariantName $rawManifest) -ne $key -or
            -not (Test-AreaDataIdsEqual $expectedArea $rawManifestArea) -or
            [int]$rawSummary.matrix_id -ne $matrixId -or
            [string]$rawSummary.variant -ne $key -or
            -not (Test-AreaDataIdsEqual $expectedArea $rawSummaryArea) -or
            [int]$rawSummary.failed -ne 0 -or
            [int]$rawSummary.occupied_cells -ne @($rawManifest.cells).Count -or
            [int]$rawSummary.collision_assets -ne @($rawManifest.collision_assets).Count
        ) {
            throw "Generated raw destination $key does not match its resolution record."
        }

        $dedupDestinationRoot = Join-Path $DedupRoot $key
        $dedupRecords = @(Get-StageFileRecords `
            -RootPath $dedupDestinationRoot `
            -ExcludedRelativePaths @(".dedupe-complete.json"))
        $dedupMarkerPath = Join-Path $dedupDestinationRoot ".dedupe-complete.json"
        $dedupManifestPath = Join-Path $dedupDestinationRoot "manifest.json"
        $dedupSummaryPath = Join-Path $dedupDestinationRoot "summary.json"
        $materialCatalogPath = Join-Path $dedupDestinationRoot "material_catalog.json"
        $dedupMarker = Read-JsonFile $dedupMarkerPath "Generated dedupe marker $key"
        $dedupManifest = Read-JsonFile $dedupManifestPath "Generated dedupe manifest $key"
        $dedupSummary = Read-JsonFile $dedupSummaryPath "Generated dedupe summary $key"
        $materialCatalog = Read-JsonFile $materialCatalogPath "Generated material catalog $key"
        $null = Assert-DspreCollisionManifest `
            -Manifest $dedupManifest `
            -Label "Generated dedupe destination $key" `
            -ExpectedManifestSchema 3
        $dedupManifestHash = (
            Get-FileHash -LiteralPath $dedupManifestPath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        $null = Assert-EquivalentStageFileRecords `
            -ExpectedRecords @($dedupMarker.files) `
            -ActualRecords $dedupRecords `
            -Label "Generated dedupe destination $key"
        $dedupManifestArea = Get-OptionalAreaDataId $dedupManifest.matrix
        $glbRecords = @(
            $dedupRecords | Where-Object {
                ([string]$_.relative_path).EndsWith(".glb", [StringComparison]::OrdinalIgnoreCase)
            }
        )
        $pngRecords = @(
            $dedupRecords | Where-Object {
                ([string]$_.relative_path).EndsWith(".png", [StringComparison]::OrdinalIgnoreCase)
            }
        )
        foreach ($record in $glbRecords) {
            $glbPath = Join-Path $dedupDestinationRoot ([string]$record.relative_path).Replace('/', '\')
            if (-not (Test-GlbFile $glbPath)) {
                throw "Generated dedupe destination $key contains an invalid GLB: $($record.relative_path)"
            }
        }
        if (
            [int]$dedupMarker.schema_version -ne 2 -or
            [string]$dedupMarker.dedupe_tool_sha256 -ne $ExpectedDedupeToolSha256 -or
            [string]$dedupMarker.source_manifest_sha256 -ne $rawManifestHash -or
            [string]$dedupMarker.output_manifest_sha256 -ne $dedupManifestHash -or
            [int]$dedupManifest.matrix.id -ne $matrixId -or
            (Get-ManifestVariantName $dedupManifest) -ne $key -or
            -not (Test-AreaDataIdsEqual $expectedArea $dedupManifestArea) -or
            [int]$dedupManifest.summary.failed -ne 0 -or
            [int]$materialCatalog.schema_version -ne 1 -or
            [int]$dedupMarker.glbs -ne $glbRecords.Count -or
            [int]$dedupSummary.glbs -ne $glbRecords.Count -or
            [int]$materialCatalog.summary.glbs -ne $glbRecords.Count -or
            @($materialCatalog.assets).Count -ne $glbRecords.Count -or
            [int]$dedupMarker.unique_images -ne $pngRecords.Count -or
            [int]$dedupSummary.unique_images -ne $pngRecords.Count -or
            [int]$materialCatalog.summary.unique_images -ne $pngRecords.Count -or
            @($materialCatalog.images).Count -ne $pngRecords.Count -or
            [int]$dedupManifest.material_dedupe.unique_images -ne $pngRecords.Count -or
            [int]$dedupMarker.unique_materials -ne @($materialCatalog.materials).Count -or
            [int]$dedupSummary.unique_materials -ne @($materialCatalog.materials).Count -or
            [int]$materialCatalog.summary.unique_materials -ne @($materialCatalog.materials).Count -or
            [int]$dedupManifest.material_dedupe.unique_materials -ne @($materialCatalog.materials).Count
		) {
			throw "Generated dedupe destination $key does not match its marker, manifest, or material catalog."
		}
		if (
			-not $SyncedDedupeRecordsByKey.ContainsKey($key) -or
			-not $SyncedDedupeMarkerSha256ByKey.ContainsKey($key)
		) {
			throw "Generated dedupe destination $key has no validated Godot sync counterpart."
		}
		$null = Assert-EquivalentStageFileRecords `
			-ExpectedRecords $dedupRecords `
			-ActualRecords @($SyncedDedupeRecordsByKey[$key]) `
			-Label "Generated and Godot dedupe destination $key"
		$dedupMarkerSha256 = (
			Get-FileHash -LiteralPath $dedupMarkerPath -Algorithm SHA256
		).Hash.ToLowerInvariant()
		if ($dedupMarkerSha256 -ne [string]$SyncedDedupeMarkerSha256ByKey[$key]) {
			throw "Generated and Godot dedupe markers differ for destination $key."
		}
		$validated++
    }
    if ($validated -ne $variantKeys.Count) {
        throw "Generated stage validation count does not match the expected destinations."
    }
    return $validated
}

$exporterSha256 = Get-DspreToolFileFingerprint `
    -Path (Join-Path $PSScriptRoot "dspre_batch_export.ps1")
$supportToolSha256 = Get-DspreToolFileFingerprint `
    -Path (Join-Path $PSScriptRoot "dspre_collision_support.ps1")
$dedupeToolSha256 = Get-DspreToolFileFingerprint `
    -Path (Join-Path $PSScriptRoot "dedupe_dspre_materials.ps1")
$syncToolSha256 = Get-DspreToolFileFingerprint `
    -Path (Join-Path $PSScriptRoot "sync_dspre_godot_assets.ps1")

if ($RequireComplete) {
    Assert-FilesByteIdentical `
        -ExpectedPath $generatedCatalogPath `
        -ActualPath $catalogPath `
        -Label "Generated and Godot matrix catalogs"
}
$catalog = Read-JsonFile $catalogPath "Godot matrix catalog"
if ([int]$catalog.schema_version -ne 2) {
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
$syncedDedupeRecordsByKey = @{}
$syncedDedupeMarkerSha256ByKey = @{}
$terrainKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$buildingKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$collisionKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$collisionFingerprints = @{}
$textureKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$materialKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$recalculatedGlbs = 0
$recalculatedDestinationCollisionAssets = 0
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
    $null = Assert-TreeHasNoReparsePoints `
        -RootPath $destinationRoot `
        -Label "Destination $key"
    $manifestPath = Join-Path $destinationRoot "manifest.json"
    $manifest = Read-JsonFile $manifestPath "Destination manifest"
    $collisionStats = Assert-DspreCollisionManifest `
        -Manifest $manifest `
        -Label "Destination $key" `
        -ExpectedManifestSchema 3
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
        [int]$destination.collision_assets -ne [int]$collisionStats.collision_assets -or
        [int]$destination.terrain_attribute_tiles -ne [int]$collisionStats.terrain_attribute_tiles -or
        [int]$destination.bdhc_assets -ne [int]$collisionStats.bdhc_assets -or
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
    if ([int]$materialCatalog.schema_version -ne 1) {
        throw "Destination $key has an unsupported material catalog schema: $($materialCatalog.schema_version)"
    }
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
        if (
            $materialKey -notmatch '^mat_[0-9a-f]{64}$' -or
            -not $localMaterialKeys.Add($materialKey) -or
            $null -eq $material.PSObject.Properties["signature"] -or
            $material.signature -isnot [pscustomobject]
        ) {
            throw "Destination $key material catalog has an invalid or duplicate material key: $materialKey"
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
        $materialBindings = @($asset.materials)
        $boundMaterialKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
        foreach ($binding in $materialBindings) {
            $boundKey = [string]$binding.material_key
            if (-not $localMaterialKeys.Contains($boundKey)) {
                throw "Destination $key GLB binds an unknown material key: $boundKey"
            }
            $null = $boundMaterialKeys.Add($boundKey)
        }
        if (
            $materialBindings.Count -eq 0 -or
            [int]$asset.output_material_count -le 0 -or
            $boundMaterialKeys.Count -ne [int]$asset.output_material_count
        ) {
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
    foreach ($asset in @($manifest.collision_assets)) {
        $collisionKey = [string]$asset.key
        $fingerprint = "{0}:{1}" -f `
            [string]$asset.terrain_attributes.sha256,
            [string]$asset.bdhc.sha256
        if (
            $collisionFingerprints.ContainsKey($collisionKey) -and
            [string]$collisionFingerprints[$collisionKey] -ne $fingerprint
        ) {
            throw "Collision asset $collisionKey differs across destination manifests."
        }
        $collisionFingerprints[$collisionKey] = $fingerprint
        $null = $collisionKeys.Add($collisionKey)
    }
    $recalculatedGlbs += $actualGlbs
    $recalculatedDestinationCollisionAssets += [int]$collisionStats.collision_assets
    $destinationByKey[$key] = $destination
    if ($RequireComplete) {
        $dedupeMarkerPath = Join-Path $destinationRoot ".dedupe-complete.json"
        $dedupeMarker = Read-JsonFile $dedupeMarkerPath "Destination dedupe marker"
        $markerPath = Join-Path $destinationRoot ".sync-complete.json"
        $marker = Read-JsonFile $markerPath "Destination sync marker"
        $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if (
            [int]$dedupeMarker.schema_version -ne 2 -or
            [string]$dedupeMarker.dedupe_tool_sha256 -ne $dedupeToolSha256 -or
            [string]$dedupeMarker.source_manifest_sha256 -notmatch '^[0-9a-f]{64}$' -or
            [string]$dedupeMarker.output_manifest_sha256 -ne $manifestHash -or
            [int]$dedupeMarker.glbs -ne $actualGlbs -or
            [int]$dedupeMarker.unique_images -ne $actualPngs -or
            [int]$dedupeMarker.unique_materials -ne [int]$destination.materials
        ) {
            throw "Destination $key dedupe marker does not match its validated assets."
        }
        if (
            [int]$marker.schema_version -ne 2 -or
            [string]$marker.dedupe_tool_sha256 -ne $dedupeToolSha256 -or
            [string]$marker.sync_tool_sha256 -ne $syncToolSha256 -or
            [int]$marker.matrix_id -ne [int]$destination.matrix_id -or
            [string]$marker.variant -ne $key -or
            [string]$marker.source_manifest_sha256 -ne $manifestHash -or
            [int]$marker.glbs -ne $actualGlbs -or
            [int]$marker.textures -ne $actualPngs
        ) {
            throw "Destination $key sync marker does not match its validated assets."
        }
        $syncFileRecords = @(Assert-StageFileRecords `
            -RootPath $destinationRoot `
            -ExpectedRecords @($marker.files) `
            -ExcludedRelativePaths @(".sync-complete.json") `
            -IgnoreGodotImportSidecars `
            -Label "Destination $key sync output")
        $dedupeFileRecords = @(
            $syncFileRecords |
                Where-Object {
                    [string]$_.relative_path -ne ".dedupe-complete.json"
                }
        )
		$null = Assert-EquivalentStageFileRecords `
			-ExpectedRecords @($dedupeMarker.files) `
			-ActualRecords $dedupeFileRecords `
			-Label "Destination $key dedupe output"
		$syncedDedupeRecordsByKey[$key] = @($dedupeFileRecords)
		$syncedDedupeMarkerSha256ByKey[$key] = (
			Get-FileHash -LiteralPath $dedupeMarkerPath -Algorithm SHA256
		).Hash.ToLowerInvariant()
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
    $recalculatedDestinationCollisionAssets -ne [int]$catalog.summary.destination_scoped_collision_assets -or
    $terrainKeys.Count -ne [int]$catalog.summary.unique_terrain_assets -or
    $buildingKeys.Count -ne [int]$catalog.summary.unique_building_assets -or
    $collisionKeys.Count -ne [int]$catalog.summary.unique_collision_assets -or
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
    $areaResolutionSha256 = Get-DspreAreaResolutionFingerprint -Path $ResolutionPath
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
    $validatedGeneratedDestinations = Assert-GeneratedDestinationStages `
        -Variants @($resolution.variants) `
        -RawRoot $rawRoot `
        -DedupRoot $dedupRoot `
        -ExpectedExporterSha256 $exporterSha256 `
		-ExpectedSupportToolSha256 $supportToolSha256 `
		-ExpectedDedupeToolSha256 $dedupeToolSha256 `
		-ExpectedAreaResolutionSha256 $areaResolutionSha256 `
		-SyncedDedupeRecordsByKey $syncedDedupeRecordsByKey `
		-SyncedDedupeMarkerSha256ByKey $syncedDedupeMarkerSha256ByKey
    if ($validatedGeneratedDestinations -ne $expectedKeys.Count) {
        throw "Complete generated stage count disagrees with AreaData resolution."
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
