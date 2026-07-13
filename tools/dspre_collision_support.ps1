Set-StrictMode -Version Latest

function Assert-DspreSafeRecursiveDeletePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$AllowedRoot
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($AllowedRoot)) {
        throw "Recursive-delete paths cannot be empty."
    }

    $fullRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $rootPrefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    if (
        $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
    ) {
        throw "Refusing a recursive delete outside a strict descendant of ${fullRoot}: $fullPath"
    }

    $rootItem = Get-Item -LiteralPath $fullRoot -Force -ErrorAction SilentlyContinue
    if ($null -ne $rootItem) {
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Recursive-delete root cannot be a reparse point: $fullRoot"
        }
        if (-not $rootItem.PSIsContainer) {
            throw "Recursive-delete root is not a directory: $fullRoot"
        }
    }

    $relativePath = $fullPath.Substring($rootPrefix.Length)
    $currentPath = $fullRoot
    foreach ($component in $relativePath.Split(@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries)) {
        $currentPath = Join-Path $currentPath $component
        $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            break
        }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Recursive-delete path cannot contain a reparse point: $currentPath"
        }
        if (-not $item.PSIsContainer) {
            throw "Recursive-delete path contains a non-directory component: $currentPath"
        }
    }

    return $fullPath
}

function Get-DspreTreeFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        [string]$Label = "DSPRE tree"
    )

    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
    $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue
    if ($null -eq $rootItem -or -not $rootItem.PSIsContainer) {
        throw "$Label root was not found: $root"
    }
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label root cannot be a reparse point: $root"
    }

    $rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
    $directories = [Collections.Generic.Queue[object]]::new()
    $files = [Collections.Generic.List[object]]::new()
    $directories.Enqueue($rootItem)
    while ($directories.Count -gt 0) {
        $directory = $directories.Dequeue()
        foreach ($child in @(Get-ChildItem -LiteralPath $directory.FullName -Force)) {
            $fullPath = [IO.Path]::GetFullPath($child.FullName)
            if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "$Label entry escaped its root: $fullPath"
            }
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Label cannot contain a reparse point: $fullPath"
            }
            if ($child.PSIsContainer) {
                $directories.Enqueue($child)
            }
            else {
                $files.Add($child)
            }
        }
    }
    return @($files | Sort-Object FullName)
}

function Assert-DspreTreeHasNoReparsePoints {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        [string]$Label = "DSPRE tree"
    )

    if (Test-Path -LiteralPath $RootPath) {
        $null = @(Get-DspreTreeFiles -RootPath $RootPath -Label $Label)
    }
    return [IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
}

function Get-DspreStageFileRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        [string[]]$ExcludedRelativePaths = @(),
        [switch]$IgnoreGodotImportSidecars,
        [string]$Label = "DSPRE stage"
    )

    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
    $rootPrefixLength = $root.Length + 1
    $excluded = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($relativePath in $ExcludedRelativePaths) {
        $null = $excluded.Add(([string]$relativePath).Replace('\', '/'))
    }
    $records = [Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-DspreTreeFiles -RootPath $root -Label $Label)) {
        $relativePath = $file.FullName.Substring($rootPrefixLength).Replace('\', '/')
        if (
            $excluded.Contains($relativePath) -or
            ($IgnoreGodotImportSidecars -and $relativePath.EndsWith(
                ".import",
                [StringComparison]::OrdinalIgnoreCase
            ))
        ) {
            continue
        }
        $fingerprint = Get-DspreFileFingerprintRecord -Path $file.FullName
        $records.Add([pscustomobject][ordered]@{
            relative_path = $relativePath
            byte_length = [long]$fingerprint.byte_length
            sha256 = [string]$fingerprint.sha256
        })
    }
    return @($records | Sort-Object { [string]$_.relative_path })
}

function Assert-DspreStageFileRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        [Parameter(Mandatory)]
        [object[]]$ExpectedRecords,
        [string[]]$ExcludedRelativePaths = @(),
        [switch]$IgnoreGodotImportSidecars,
        [string]$Label = "DSPRE stage"
    )

    $expectedByPath = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
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

    $actualRecords = @(Get-DspreStageFileRecords `
        -RootPath $RootPath `
        -ExcludedRelativePaths $ExcludedRelativePaths `
        -IgnoreGodotImportSidecars:$IgnoreGodotImportSidecars `
        -Label $Label)
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

function Get-DspreFileFingerprintRecord {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Fingerprint input file was not found: $Path"
    }
    $resolvedPath = (Get-Item -LiteralPath $Path).FullName
    $stream = [IO.File]::Open(
        $resolvedPath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $length = $stream.Length
        $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
        return [pscustomobject]@{
            sha256 = $hash
            byte_length = $length
        }
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Get-DspreToolFileFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    return [string](Get-DspreFileFingerprintRecord -Path $Path).sha256
}

function Get-DspreContentFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath)

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        throw "Fingerprint input directory was not found: $RootPath"
    }
	$root = [IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
	$rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
	$rootPrefixLength = $root.Length + 1
	$filesByRelativePath = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
	$relativePaths = New-Object 'System.Collections.Generic.List[string]'
	foreach ($file in @(Get-DspreTreeFiles -RootPath $root -Label "Fingerprint input")) {
		$fullPath = [IO.Path]::GetFullPath($file.FullName)
		if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
			throw "Fingerprint input escaped its root: $fullPath"
		}
		$relativePath = $fullPath.Substring($rootPrefixLength).Replace('\', '/').Normalize(
			[Text.NormalizationForm]::FormC
		)
        if ([string]::IsNullOrWhiteSpace($relativePath) -or $filesByRelativePath.ContainsKey($relativePath)) {
            throw "Fingerprint input contains an invalid or duplicate relative path: $relativePath"
        }
        $filesByRelativePath.Add($relativePath, $file)
        $relativePaths.Add($relativePath)
    }
    $relativePaths.Sort([StringComparer]::Ordinal)

    $aggregate = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($aggregate, [Text.UTF8Encoding]::new($false), $true)
    try {
        $writer.Write([byte]1)
        $writer.Write([int]$relativePaths.Count)
        foreach ($relativePath in $relativePaths) {
            $pathBytes = [Text.UTF8Encoding]::new($false).GetBytes($relativePath)
            $record = Get-DspreFileFingerprintRecord -Path $filesByRelativePath[$relativePath].FullName
            $hashBytes = New-Object byte[] 32
            for ($index = 0; $index -lt $hashBytes.Length; $index++) {
                $hashBytes[$index] = [Convert]::ToByte(
                    ([string]$record.sha256).Substring($index * 2, 2),
                    16
                )
            }
            $writer.Write([int]$pathBytes.Length)
            $writer.Write($pathBytes)
            $writer.Write([long]$record.byte_length)
            $writer.Write($hashBytes)
        }
        $writer.Flush()
        $bytes = $aggregate.ToArray()
    }
    finally {
        $writer.Dispose()
        $aggregate.Dispose()
    }
    return Get-DspreCollisionSha256 -Bytes $bytes -Offset 0 -Length $bytes.Length
}

function Assert-DspreSha256Fingerprint {
    param($Value, [string]$Label)

    $fingerprint = [string]$Value
    if ($fingerprint -notmatch '^[0-9a-fA-F]{64}$') {
        throw "$Label must be a SHA-256 fingerprint."
    }
    return $fingerprint.ToLowerInvariant()
}

function Assert-DspreRawExportMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Marker,
        [Parameter(Mandatory)]
        [ValidateRange(0, 0xFFFF)]
        [int]$ExpectedMatrixId,
        [Parameter(Mandatory)]
        [string]$ExpectedVariant,
        [AllowNull()]
        $ExpectedAreaDataId = $null,
        [Parameter(Mandatory)]
        [string]$ExpectedDspreSourceSha256,
        [Parameter(Mandatory)]
        [string]$ExpectedExporterSha256,
        [Parameter(Mandatory)]
        [string]$ExpectedSupportToolSha256,
        [Parameter(Mandatory)]
        [string]$ExpectedApiculaSha256,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ExpectedAreaResolutionSha256,
        [string]$ExpectedManifestSha256 = "",
        [int]$ExpectedOccupiedCells = -1,
        [int]$ExpectedCollisionAssets = -1,
        [string]$OutputRoot = "",
        [string]$Label = "DSPRE raw export marker"
    )

    $requiredProperties = @(
        "schema_version",
        "export_contract_version",
        "matrix_id",
        "variant",
        "area_data_id",
        "manifest_sha256",
        "dspre_source_sha256",
        "exporter_sha256",
        "support_tool_sha256",
        "apicula_sha256",
        "area_resolution_sha256",
        "occupied_cells",
        "collision_assets",
        "files"
    )
    foreach ($propertyName in $requiredProperties) {
        if ($null -eq $Marker.PSObject.Properties[$propertyName]) {
            throw "$Label is missing '$propertyName'."
        }
    }

    if ([int]$Marker.schema_version -ne 2 -or [int]$Marker.export_contract_version -ne 3) {
        throw "$Label must use marker schema 2 and export contract 3."
    }

    $filePaths = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($record in @($Marker.files)) {
        $relativePath = ([string]$record.relative_path).Replace('\', '/')
        if (
            [string]::IsNullOrWhiteSpace($relativePath) -or
            [IO.Path]::IsPathRooted($relativePath) -or
            $relativePath -match '(^|/)\.\.(/|$)' -or
            $relativePath.Equals(
                ".export-complete.json",
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            -not $filePaths.Add($relativePath) -or
            [long]$record.byte_length -lt 0 -or
            [string]$record.sha256 -notmatch '^[0-9a-f]{64}$'
        ) {
            throw "$Label contains an invalid or duplicate file record: $relativePath"
        }
    }
    if ($filePaths.Count -eq 0) {
        throw "$Label must declare at least one output file."
    }
    if ([int]$Marker.matrix_id -ne $ExpectedMatrixId -or [string]$Marker.variant -ne $ExpectedVariant) {
        throw "$Label does not match matrix $ExpectedMatrixId variant '$ExpectedVariant'."
    }

    $actualAreaDataId = $Marker.area_data_id
    $areaMatches = ($null -eq $ExpectedAreaDataId -and $null -eq $actualAreaDataId) -or
        ($null -ne $ExpectedAreaDataId -and $null -ne $actualAreaDataId -and
            [int]$ExpectedAreaDataId -eq [int]$actualAreaDataId)
    if (-not $areaMatches) {
        throw "$Label does not match the expected AreaData ID."
    }

    $expectedFingerprints = [ordered]@{
        dspre_source_sha256 = Assert-DspreSha256Fingerprint $ExpectedDspreSourceSha256 "Expected DSPRE source fingerprint"
        exporter_sha256 = Assert-DspreSha256Fingerprint $ExpectedExporterSha256 "Expected batch exporter fingerprint"
        support_tool_sha256 = Assert-DspreSha256Fingerprint $ExpectedSupportToolSha256 "Expected collision support fingerprint"
        apicula_sha256 = Assert-DspreSha256Fingerprint $ExpectedApiculaSha256 "Expected apicula fingerprint"
    }
    foreach ($entry in $expectedFingerprints.GetEnumerator()) {
        if ([string]$Marker.($entry.Key) -ne [string]$entry.Value) {
            throw "$Label has a stale $($entry.Key) value."
        }
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedAreaResolutionSha256)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Marker.area_resolution_sha256)) {
            throw "$Label unexpectedly binds an AreaData resolution fingerprint."
        }
    }
    else {
        $expectedAreaResolution = Assert-DspreSha256Fingerprint `
            $ExpectedAreaResolutionSha256 `
            "Expected AreaData resolution fingerprint"
        if ([string]$Marker.area_resolution_sha256 -ne $expectedAreaResolution) {
            throw "$Label has a stale area_resolution_sha256 value."
        }
    }

    $manifestSha256 = Assert-DspreSha256Fingerprint $Marker.manifest_sha256 "$Label manifest fingerprint"
    if (-not [string]::IsNullOrWhiteSpace($ExpectedManifestSha256)) {
        $expectedManifest = Assert-DspreSha256Fingerprint $ExpectedManifestSha256 "Expected manifest fingerprint"
        if ($manifestSha256 -ne $expectedManifest) {
            throw "$Label does not match its manifest."
        }
    }
    if ([int]$Marker.occupied_cells -lt 0 -or [int]$Marker.collision_assets -lt 0) {
        throw "$Label contains negative output counts."
    }
    if ($ExpectedOccupiedCells -ge 0 -and [int]$Marker.occupied_cells -ne $ExpectedOccupiedCells) {
        throw "$Label occupied-cell count does not match its manifest."
    }
    if ($ExpectedCollisionAssets -ge 0 -and [int]$Marker.collision_assets -ne $ExpectedCollisionAssets) {
        throw "$Label collision-asset count does not match its manifest."
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
        $null = Assert-DspreStageFileRecords `
            -RootPath $OutputRoot `
            -ExpectedRecords @($Marker.files) `
            -ExcludedRelativePaths @(".export-complete.json") `
            -Label "$Label output"
    }

    return $true
}

function Assert-DspreUnrequestedRawMarkersCurrent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Variants,
        [Parameter(Mandatory)]
        [int[]]$RequestedMatrixIds,
        [Parameter(Mandatory)]
        [string]$RawRoot,
        [Parameter(Mandatory)]
        [string]$ExpectedDspreSourceSha256,
        [Parameter(Mandatory)]
        [string]$ExpectedExporterSha256,
        [Parameter(Mandatory)]
        [string]$ExpectedSupportToolSha256,
        [Parameter(Mandatory)]
        [string]$ExpectedApiculaSha256,
        [Parameter(Mandatory)]
        [string]$ExpectedAreaResolutionSha256
    )

    $requested = New-Object System.Collections.Generic.HashSet[int]
    foreach ($matrixId in $RequestedMatrixIds) {
        $null = $requested.Add([int]$matrixId)
    }
    $staleVariants = New-Object System.Collections.Generic.List[string]
    foreach ($variantRecord in $Variants) {
        $matrixId = [int]$variantRecord.matrix_id
        if ($requested.Contains($matrixId)) {
            continue
        }
        $variantName = [string]$variantRecord.variant
        if ($variantName -notmatch '^matrix_\d{4}(_area_\d{4})?$') {
            throw "Partial matrix export received an unsafe variant name: '$variantName'."
        }
        $variantRoot = Join-Path $RawRoot $variantName
        $manifestPath = Join-Path $variantRoot "manifest.json"
        $summaryPath = Join-Path $variantRoot "summary.json"
        $markerPath = Join-Path $variantRoot ".export-complete.json"
        try {
            if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
                throw "required raw output is missing: $([IO.Path]::GetFileName($markerPath))"
            }
            $marker = [IO.File]::ReadAllText($markerPath, [Text.Encoding]::UTF8) |
                ConvertFrom-Json
            $expectedAreaDataId = $variantRecord.area_data_id
            $markerArguments = @{
                Marker = $marker
                ExpectedMatrixId = $matrixId
                ExpectedVariant = $variantName
                ExpectedAreaDataId = $expectedAreaDataId
                ExpectedDspreSourceSha256 = $ExpectedDspreSourceSha256
                ExpectedExporterSha256 = $ExpectedExporterSha256
                ExpectedSupportToolSha256 = $ExpectedSupportToolSha256
                ExpectedApiculaSha256 = $ExpectedApiculaSha256
                ExpectedAreaResolutionSha256 = $ExpectedAreaResolutionSha256
                Label = "Raw destination $variantName marker"
            }
            $null = Assert-DspreRawExportMarker @markerArguments

            foreach ($requiredPath in @($manifestPath, $summaryPath)) {
                if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
                    throw "required raw output is missing: $([IO.Path]::GetFileName($requiredPath))"
                }
            }
            $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) |
                ConvertFrom-Json
            $summary = [IO.File]::ReadAllText($summaryPath, [Text.Encoding]::UTF8) |
                ConvertFrom-Json
            $null = Assert-DspreCollisionManifest `
                -Manifest $manifest `
                -Label "Raw destination $variantName" `
                -ExpectedManifestSchema 2
            $manifestVariant = if ($null -ne $manifest.matrix.PSObject.Properties["variant"]) {
                [string]$manifest.matrix.variant
            }
            else {
                "matrix_{0:D4}" -f [int]$manifest.matrix.id
            }
            $manifestAreaDataId = if (
                $null -ne $manifest.matrix.PSObject.Properties["area_data_id"]
            ) {
                $manifest.matrix.area_data_id
            }
            else {
                $null
            }
            $manifestAreaMatches = ($null -eq $expectedAreaDataId -and $null -eq $manifestAreaDataId) -or
                ($null -ne $expectedAreaDataId -and $null -ne $manifestAreaDataId -and
                    [int]$expectedAreaDataId -eq [int]$manifestAreaDataId)
            $summaryAreaMatches = ($null -eq $expectedAreaDataId -and $null -eq $summary.area_data_id) -or
                ($null -ne $expectedAreaDataId -and $null -ne $summary.area_data_id -and
                    [int]$expectedAreaDataId -eq [int]$summary.area_data_id)
            if (
                [int]$manifest.matrix.id -ne $matrixId -or
                $manifestVariant -ne $variantName -or
                -not $manifestAreaMatches -or
                [int]$summary.matrix_id -ne $matrixId -or
                [string]$summary.variant -ne $variantName -or
                -not $summaryAreaMatches -or
                [int]$summary.failed -ne 0 -or
                [int]$summary.occupied_cells -ne @($manifest.cells).Count -or
                [int]$summary.collision_assets -ne @($manifest.collision_assets).Count
            ) {
                throw "manifest or summary identity/counts do not match the resolution record"
            }
            $markerArguments.ExpectedManifestSha256 = (
                Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256
            ).Hash.ToLowerInvariant()
            $markerArguments.ExpectedOccupiedCells = @($manifest.cells).Count
            $markerArguments.ExpectedCollisionAssets = @($manifest.collision_assets).Count
            $markerArguments.OutputRoot = $variantRoot
            $null = Assert-DspreRawExportMarker @markerArguments
        }
        catch {
            $staleVariants.Add("$variantName ($($_.Exception.Message))")
        }
    }
    if ($staleVariants.Count -ne 0) {
        $details = @($staleVariants | Select-Object -First 8) -join '; '
        if ($staleVariants.Count -gt 8) {
            $details += "; ... and $($staleVariants.Count - 8) more"
        }
        throw "Partial matrix export cannot publish a complete catalog while unrequested destinations are stale: $details. Rerun without -MatrixIds."
    }

    return $true
}

function Get-DspreAreaResolutionFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Area resolution file was not found: $Path"
    }
    $document = [IO.File]::ReadAllText(
        (Get-Item -LiteralPath $Path).FullName,
        [Text.Encoding]::UTF8
    ) | ConvertFrom-Json
    $document.PSObject.Properties.Remove("generated_utc")
    if ($null -ne $document.PSObject.Properties["source"] -and $null -ne $document.source) {
        $document.source.PSObject.Properties.Remove("dspre_contents")
        $document.source.PSObject.Properties.Remove("apicula")
    }
    $canonicalJson = $document | ConvertTo-Json -Depth 50 -Compress
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($canonicalJson)
    return Get-DspreCollisionSha256 -Bytes $bytes -Offset 0 -Length $bytes.Length
}

function Get-DspreCollisionU16 {
    param([byte[]]$Bytes, [int]$Offset)

    if ($Offset -lt 0 -or $Offset + 2 -gt $Bytes.Length) {
        throw "Unsigned 16-bit read exceeds the map data at offset $Offset."
    }
    return [int][BitConverter]::ToUInt16($Bytes, $Offset)
}

function Get-DspreCollisionI32 {
    param([byte[]]$Bytes, [int]$Offset)

    if ($Offset -lt 0 -or $Offset + 4 -gt $Bytes.Length) {
        throw "Signed 32-bit read exceeds the map data at offset $Offset."
    }
    return [int][BitConverter]::ToInt32($Bytes, $Offset)
}

function Get-DspreCollisionSha256 {
    param([byte[]]$Bytes, [int]$Offset, [int]$Length)

    if ($Offset -lt 0 -or $Length -lt 0 -or $Offset + $Length -gt $Bytes.Length) {
        throw "SHA-256 range exceeds the map data: offset $Offset, length $Length."
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
            $sha.ComputeHash($Bytes, $Offset, $Length)
        )).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function ConvertFrom-DspreMapCollision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,
        [Parameter(Mandatory)]
        [ValidateRange(0, 0xFFFF)]
        [int]$MapId
    )

    if ($Bytes.Length -lt 32) {
        throw "Map $MapId is too short to contain land-data sections and BDHC."
    }

    $attributesLength = [int][BitConverter]::ToUInt32($Bytes, 0)
    $mapPropsLength = [int][BitConverter]::ToUInt32($Bytes, 4)
    $modelLength = [int][BitConverter]::ToUInt32($Bytes, 8)
    $bdhcLength = [int][BitConverter]::ToUInt32($Bytes, 12)
    if ($attributesLength -ne 2048) {
        throw "Map $MapId terrain attributes must be exactly 2048 bytes; found $attributesLength."
    }

    $attributesOffset = 16
    $bdhcOffset = $attributesOffset + $attributesLength + $mapPropsLength + $modelLength
    if ($bdhcLength -lt 16 -or $bdhcOffset + $bdhcLength -ne $Bytes.Length) {
        throw "Map $MapId section lengths do not exactly cover the source file."
    }
    if ([Text.Encoding]::ASCII.GetString($Bytes, $bdhcOffset, 4) -ne "BDHC") {
        throw "Map $MapId BDHC magic is invalid."
    }

    $attributeValues = New-Object int[] 1024
    for ($index = 0; $index -lt $attributeValues.Length; $index++) {
        $attributeValues[$index] = Get-DspreCollisionU16 $Bytes ($attributesOffset + 2 * $index)
    }

    $pointsCount = Get-DspreCollisionU16 $Bytes ($bdhcOffset + 4)
    $normalsCount = Get-DspreCollisionU16 $Bytes ($bdhcOffset + 6)
    $constantsCount = Get-DspreCollisionU16 $Bytes ($bdhcOffset + 8)
    $platesCount = Get-DspreCollisionU16 $Bytes ($bdhcOffset + 10)
    $stripsCount = Get-DspreCollisionU16 $Bytes ($bdhcOffset + 12)
    $accessListCount = Get-DspreCollisionU16 $Bytes ($bdhcOffset + 14)
    $expectedBdhcLength = 16 + 8 * $pointsCount + 12 * $normalsCount +
        4 * $constantsCount + 8 * $platesCount + 8 * $stripsCount +
        2 * $accessListCount
    if ($expectedBdhcLength -ne $bdhcLength) {
        throw "Map $MapId BDHC arrays require $expectedBdhcLength bytes; header declares $bdhcLength."
    }

    $pointsOffset = $bdhcOffset + 16
    $normalsOffset = $pointsOffset + 8 * $pointsCount
    $constantsOffset = $normalsOffset + 12 * $normalsCount
    $platesOffset = $constantsOffset + 4 * $constantsCount
    $stripsOffset = $platesOffset + 8 * $platesCount
    $accessListOffset = $stripsOffset + 8 * $stripsCount

    $points = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $pointsCount; $index++) {
        $offset = $pointsOffset + 8 * $index
        $points.Add([pscustomobject][ordered]@{
            x = Get-DspreCollisionI32 $Bytes $offset
            z = Get-DspreCollisionI32 $Bytes ($offset + 4)
        })
    }

    $normals = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $normalsCount; $index++) {
        $offset = $normalsOffset + 12 * $index
        $normals.Add([pscustomobject][ordered]@{
            x = Get-DspreCollisionI32 $Bytes $offset
            y = Get-DspreCollisionI32 $Bytes ($offset + 4)
            z = Get-DspreCollisionI32 $Bytes ($offset + 8)
        })
    }

    $constants = New-Object int[] $constantsCount
    for ($index = 0; $index -lt $constantsCount; $index++) {
        $constants[$index] = Get-DspreCollisionI32 $Bytes ($constantsOffset + 4 * $index)
    }

    $plates = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $platesCount; $index++) {
        $offset = $platesOffset + 8 * $index
        $firstPointIndex = Get-DspreCollisionU16 $Bytes $offset
        $secondPointIndex = Get-DspreCollisionU16 $Bytes ($offset + 2)
        $normalIndex = Get-DspreCollisionU16 $Bytes ($offset + 4)
        $constantIndex = Get-DspreCollisionU16 $Bytes ($offset + 6)
        if (
            $firstPointIndex -ge $pointsCount -or
            $secondPointIndex -ge $pointsCount -or
            $normalIndex -ge $normalsCount -or
            $constantIndex -ge $constantsCount
        ) {
            throw "Map $MapId BDHC plate $index contains an out-of-range array index."
        }
        if ((Get-DspreCollisionI32 $Bytes ($normalsOffset + 12 * $normalIndex + 4)) -eq 0) {
            throw "Map $MapId BDHC plate $index references a normal with zero Y."
        }
        $plates.Add([pscustomobject][ordered]@{
            first_point_index = $firstPointIndex
            second_point_index = $secondPointIndex
            normal_index = $normalIndex
            constant_index = $constantIndex
        })
    }

    $strips = New-Object System.Collections.Generic.List[object]
    $previousScanline = [int]::MinValue
    for ($index = 0; $index -lt $stripsCount; $index++) {
        $offset = $stripsOffset + 8 * $index
        $scanline = Get-DspreCollisionI32 $Bytes $offset
        $elementCount = Get-DspreCollisionU16 $Bytes ($offset + 4)
        $startIndex = Get-DspreCollisionU16 $Bytes ($offset + 6)
        if ($scanline -lt $previousScanline) {
            throw "Map $MapId BDHC strip scanlines are not sorted at index $index."
        }
        if ($startIndex + $elementCount -gt $accessListCount) {
            throw "Map $MapId BDHC strip $index exceeds the access list."
        }
        $strips.Add([pscustomobject][ordered]@{
            scanline_fx32 = $scanline
            access_list_element_count = $elementCount
            access_list_start_index = $startIndex
        })
        $previousScanline = $scanline
    }

    $accessList = New-Object int[] $accessListCount
    for ($index = 0; $index -lt $accessListCount; $index++) {
        $plateIndex = Get-DspreCollisionU16 $Bytes ($accessListOffset + 2 * $index)
        if ($plateIndex -ge $platesCount) {
            throw "Map $MapId BDHC access-list entry $index references missing plate $plateIndex."
        }
        $accessList[$index] = $plateIndex
    }

    return [pscustomobject][ordered]@{
        key = "map_{0:D4}_collision" -f $MapId
        map_id = $MapId
        terrain_attributes = [pscustomobject][ordered]@{
            byte_length = $attributesLength
            sha256 = Get-DspreCollisionSha256 $Bytes $attributesOffset $attributesLength
            data_base64 = [Convert]::ToBase64String($Bytes, $attributesOffset, $attributesLength)
        }
        bdhc = [pscustomobject][ordered]@{
            magic = "BDHC"
            byte_length = $bdhcLength
            sha256 = Get-DspreCollisionSha256 $Bytes $bdhcOffset $bdhcLength
            counts = [pscustomobject][ordered]@{
                points = $pointsCount
                normals = $normalsCount
                constants = $constantsCount
                plates = $platesCount
                strips = $stripsCount
                access_list = $accessListCount
            }
            data_base64 = [Convert]::ToBase64String($Bytes, $bdhcOffset, $bdhcLength)
        }
    }
}

function Assert-DspreCollisionInteger {
    param(
        $Value,
        [long]$Minimum,
        [long]$Maximum,
        [string]$Label
    )

    try {
        $integer = [long]$Value
        if ([double]$Value -ne [double]$integer -or $integer -lt $Minimum -or $integer -gt $Maximum) {
            throw "range"
        }
        return $integer
    }
    catch {
        throw "$Label must be an integer in [$Minimum, $Maximum]."
    }
}

function Get-DspreCollisionAssetHashes {
    param($Asset, [string]$Label = "Collision asset")

    try {
        $attributeBytes = [Convert]::FromBase64String([string]$Asset.terrain_attributes.data_base64)
        $bdhcBytes = [Convert]::FromBase64String([string]$Asset.bdhc.data_base64)
    }
    catch {
        throw "$Label contains invalid Base64 collision data: $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        attributes_sha256 = Get-DspreCollisionSha256 $attributeBytes 0 $attributeBytes.Length
        bdhc_sha256 = Get-DspreCollisionSha256 $bdhcBytes 0 $bdhcBytes.Length
        bdhc_length = $bdhcBytes.Length
    }
}

function Assert-DspreCollisionManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Manifest,
        [string]$Label = "DSPRE manifest",
        [int]$ExpectedManifestSchema = -1
    )

    if ($ExpectedManifestSchema -ge 0 -and [int]$Manifest.schema_version -ne $ExpectedManifestSchema) {
        throw "$Label schema must be $ExpectedManifestSchema; found $($Manifest.schema_version)."
    }
    $format = $Manifest.collision_format
    if (
        [int]$format.schema_version -ne 1 -or
        [int]$format.terrain_width -ne 32 -or
        [int]$format.terrain_height -ne 32 -or
        [string]$format.terrain_order -ne "row_major" -or
        [int]$format.collision_mask -ne 0x8000 -or
        [int]$format.behavior_mask -ne 0x00FF -or
        [int]$format.fx32_fraction_bits -ne 12 -or
        [int]$format.source_units_per_tile -ne 16 -or
        [int]$format.source_units_per_world_unit -ne 16 -or
        [string]$format.bdhc_origin -ne "map_center" -or
        [string]$format.map_prop_collision -ne "cell_terrain_attributes"
    ) {
        throw "$Label collision format is missing or unsupported."
    }

    $assets = @($Manifest.collision_assets)
    if ($assets.Count -eq 0 -or [int]$Manifest.summary.collision_assets -ne $assets.Count) {
        throw "$Label collision asset count is empty or inconsistent."
    }
    if (
        [int]$Manifest.summary.terrain_attribute_tiles -ne 1024 * $assets.Count -or
        [int]$Manifest.summary.bdhc_assets -ne $assets.Count
    ) {
        throw "$Label collision summary is inconsistent."
    }

    $assetsByKey = @{}
    $assetsByMap = @{}
    foreach ($asset in $assets) {
        $mapId = [int](Assert-DspreCollisionInteger $asset.map_id 0 0xFFFF "$Label map ID")
        $key = [string]$asset.key
        if ($key -ne ("map_{0:D4}_collision" -f $mapId)) {
            throw "$Label collision key does not match map ${mapId}: $key"
        }
        if ($assetsByKey.ContainsKey($key) -or $assetsByMap.ContainsKey($mapId)) {
            throw "$Label contains duplicate collision asset $key or map $mapId."
        }

        if (
            [int]$asset.terrain_attributes.byte_length -ne 2048 -or
            [string]$asset.terrain_attributes.sha256 -notmatch '^[0-9a-f]{64}$' -or
            [string]::IsNullOrWhiteSpace([string]$asset.terrain_attributes.data_base64)
        ) {
            throw "$Label collision asset $key has invalid terrain attributes."
        }

        $bdhc = $asset.bdhc
        $counts = $bdhc.counts
        if (
            [string]$bdhc.magic -ne "BDHC" -or
            [string]$bdhc.sha256 -notmatch '^[0-9a-f]{64}$' -or
            [string]::IsNullOrWhiteSpace([string]$bdhc.data_base64)
        ) {
            throw "$Label collision asset $key has invalid BDHC metadata."
        }
        $pointsCount = [int](Assert-DspreCollisionInteger $counts.points 0 0xFFFF "$Label points count")
        $normalsCount = [int](Assert-DspreCollisionInteger $counts.normals 0 0xFFFF "$Label normals count")
        $constantsCount = [int](Assert-DspreCollisionInteger $counts.constants 0 0xFFFF "$Label constants count")
        $platesCount = [int](Assert-DspreCollisionInteger $counts.plates 0 0xFFFF "$Label plates count")
        $stripsCount = [int](Assert-DspreCollisionInteger $counts.strips 0 0xFFFF "$Label strips count")
        $accessListCount = [int](Assert-DspreCollisionInteger $counts.access_list 0 0xFFFF "$Label access-list count")
        $expectedLength = 16 + 8 * $pointsCount + 12 * $normalsCount +
            4 * $constantsCount + 8 * $platesCount + 8 * $stripsCount +
            2 * $accessListCount
        if ([int]$bdhc.byte_length -ne $expectedLength) {
            throw "$Label collision asset $key has an invalid BDHC byte length."
        }

        $hashes = Get-DspreCollisionAssetHashes $asset "$Label collision asset $key"
        if (
            [string]$asset.terrain_attributes.sha256 -ne $hashes.attributes_sha256 -or
            [string]$bdhc.sha256 -ne $hashes.bdhc_sha256 -or
            [int]$bdhc.byte_length -ne $hashes.bdhc_length
        ) {
            throw "$Label collision asset $key hashes do not match its packed data."
        }

        $attributeBytes = [Convert]::FromBase64String([string]$asset.terrain_attributes.data_base64)
        $bdhcBytes = [Convert]::FromBase64String([string]$bdhc.data_base64)
        if ($attributeBytes.Length -ne 2048 -or $bdhcBytes.Length -ne [int]$bdhc.byte_length) {
            throw "$Label collision asset $key packed lengths are invalid."
        }
        $syntheticMap = New-Object byte[] (16 + $attributeBytes.Length + $bdhcBytes.Length)
        [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]$attributeBytes.Length), 0, $syntheticMap, 0, 4)
        [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]0), 0, $syntheticMap, 4, 4)
        [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]0), 0, $syntheticMap, 8, 4)
        [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]$bdhcBytes.Length), 0, $syntheticMap, 12, 4)
        [Buffer]::BlockCopy($attributeBytes, 0, $syntheticMap, 16, $attributeBytes.Length)
        [Buffer]::BlockCopy($bdhcBytes, 0, $syntheticMap, 16 + $attributeBytes.Length, $bdhcBytes.Length)
        $parsedAsset = ConvertFrom-DspreMapCollision -Bytes $syntheticMap -MapId $mapId
        foreach ($countName in @("points", "normals", "constants", "plates", "strips", "access_list")) {
            if ([int]$parsedAsset.bdhc.counts.$countName -ne [int]$counts.$countName) {
                throw "$Label collision asset $key packed BDHC count $countName is inconsistent."
            }
        }
        $assetsByKey[$key] = $asset
        $assetsByMap[$mapId] = $asset
    }

    $referencedKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    foreach ($cell in @($Manifest.cells)) {
        $key = [string]$cell.collision_asset_key
        if (-not $assetsByKey.ContainsKey($key)) {
            throw "$Label cell $($cell.x),$($cell.y) references missing collision asset $key."
        }
        if ([int]$assetsByKey[$key].map_id -ne [int]$cell.map_id) {
            throw "$Label cell $($cell.x),$($cell.y) collision map does not match its map ID."
        }
        $null = $referencedKeys.Add($key)
        foreach ($building in @($cell.buildings)) {
            if (
                [string]$building.collision.mode -ne "cell_terrain_attributes" -or
                $null -eq $building.scale_fx32
            ) {
                throw "$Label building $($building.model_id) lacks the source collision/scale contract."
            }
            foreach ($axis in @("x", "y", "z")) {
                $null = Assert-DspreCollisionInteger $building.scale_fx32.$axis ([int]::MinValue) ([int]::MaxValue) "$Label building scale $axis"
            }
        }
    }
    if ($referencedKeys.Count -ne $assets.Count) {
        throw "$Label contains orphaned collision assets."
    }

    return [pscustomobject]@{
        collision_assets = $assets.Count
        terrain_attribute_tiles = 1024 * $assets.Count
        bdhc_assets = $assets.Count
        referenced_cells = @($Manifest.cells).Count
    }
}
