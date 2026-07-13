Set-StrictMode -Version Latest

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
	$rootItem = Get-Item -LiteralPath $root -Force
	if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
		throw "Fingerprint input root cannot be a reparse point: $root"
	}
	$rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
	$rootPrefixLength = $root.Length + 1
	$filesByRelativePath = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
	$relativePaths = New-Object 'System.Collections.Generic.List[string]'
	$reparseDirectory = Get-ChildItem -LiteralPath $root -Recurse -Directory -Force |
		Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } |
		Select-Object -First 1
	if ($null -ne $reparseDirectory) {
		throw "Fingerprint input cannot contain a reparse-point directory: $($reparseDirectory.FullName)"
	}
	foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
		if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
			throw "Fingerprint input cannot contain a reparse point: $($file.FullName)"
		}
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
