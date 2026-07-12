[CmdletBinding()]
param(
    [string]$DspreContents = "",
    [string]$ApiculaPath = "C:\Users\YbbNa\Downloads\DSPRE-win-Portable\current\Tools\apicula.exe",
    [string]$OutputRoot = "",
    [string]$WorkRoot = "",
    [string]$AreaOverridesPath = "",
    [int]$MatrixId = 0,
    [int]$AreaDataId = -1,
    [int]$MaxParallel = 4,
    [long]$HeaderTableOffset = 0xE56F0,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $workspaceRoot "generated\dspre_glb"
}
if ([string]::IsNullOrWhiteSpace($WorkRoot)) {
    $WorkRoot = Join-Path $workspaceRoot ".work\dspre_export"
}

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

function Clear-DirectoryUnderRoot {
    param([string]$Path, [string]$AllowedRoot)

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $fullRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear a directory outside the allowed root: $fullPath"
    }
    if (Test-Path -LiteralPath $fullPath) {
        Remove-Item -LiteralPath $fullPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
}

function Get-U16 {
    param([byte[]]$Bytes, [int]$Offset)
    return [int][BitConverter]::ToUInt16($Bytes, $Offset)
}

function Get-I16 {
    param([byte[]]$Bytes, [int]$Offset)
    return [int][BitConverter]::ToInt16($Bytes, $Offset)
}

function Get-U32 {
    param([byte[]]$Bytes, [int]$Offset)
    return [long][BitConverter]::ToUInt32($Bytes, $Offset)
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
        $magic = [Text.Encoding]::ASCII.GetString($header, 0, 4)
        $version = [BitConverter]::ToUInt32($header, 4)
        $declaredLength = [BitConverter]::ToUInt32($header, 8)
        return $magic -eq "glTF" -and $version -eq 2 -and $declaredLength -eq $item.Length
    }
    finally {
        $stream.Dispose()
    }
}

function Get-ValidGlbs {
    param([string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return @()
    }
    return @(
        Get-ChildItem -LiteralPath $Directory -Filter "*.glb" -File |
            Where-Object { Test-GlbFile $_.FullName } |
            Sort-Object Name
    )
}

function Get-ForwardRelativePath {
    param([string]$BasePath, [string]$FullPath)

    $baseUri = New-Object Uri(([IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'))
    $fileUri = New-Object Uri([IO.Path]::GetFullPath($FullPath))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fileUri).ToString())
}

function Complete-Conversion {
    param(
        [pscustomobject]$RunningItem,
        [string]$MatrixOutputRoot,
        [System.Collections.Generic.List[object]]$Failures
    )

    $RunningItem.Process.WaitForExit()
    $job = $RunningItem.Job
    $exitCode = $RunningItem.Process.ExitCode
    $glbs = @(Get-ValidGlbs $job.OutputDirectory)

    if ($glbs.Count -gt 0) {
        $job.Asset.status = "exported"
        $job.Asset.output_glbs = @(
            $glbs | ForEach-Object { Get-ForwardRelativePath $MatrixOutputRoot $_.FullName }
        )
    }
    else {
        $job.Asset.status = "failed"
        $message = "Exit code $exitCode; valid GLBs: $($glbs.Count)"
        if (Test-Path -LiteralPath $RunningItem.StderrPath) {
            $stderrContent = Get-Content -LiteralPath $RunningItem.StderrPath -Raw
            $stderr = if ($null -eq $stderrContent) { "" } else { $stderrContent.Trim() }
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                $message = "$message; $stderr"
            }
        }
        $job.Asset.error = $message
        $Failures.Add([pscustomobject][ordered]@{
            key = $job.Key
            kind = $job.Kind
            message = $message
            stdout_log = Get-ForwardRelativePath $MatrixOutputRoot $RunningItem.StdoutPath
            stderr_log = Get-ForwardRelativePath $MatrixOutputRoot $RunningItem.StderrPath
        })
    }

    foreach ($logPath in @($RunningItem.StdoutPath, $RunningItem.StderrPath)) {
        if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -eq 0) {
            Remove-Item -LiteralPath $logPath -Force
        }
    }
}

if ([string]::IsNullOrWhiteSpace($DspreContents)) {
    $downloadRoot = "E:\Users\Admin\Downloads"
    $candidates = @(
        Get-ChildItem -LiteralPath $downloadRoot -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*_DSPRE_contents" } |
            Sort-Object LastWriteTime -Descending
    )
    if ($candidates.Count -eq 0) {
        throw "No *_DSPRE_contents directory was found under $downloadRoot. Pass -DspreContents explicitly."
    }
    $DspreContents = $candidates[0].FullName
    if ($candidates.Count -gt 1) {
        Write-Warning "Multiple DSPRE content directories were found. Using the newest: $DspreContents"
    }
}

$DspreContents = Resolve-ExistingDirectory $DspreContents "DSPRE contents directory"
$ApiculaPath = Resolve-ExistingFile $ApiculaPath "apicula.exe"
if ([string]::IsNullOrWhiteSpace($AreaOverridesPath)) {
    $defaultAreaOverridesPath = Join-Path $workspaceRoot "generated\dspre_matrix_area_overrides.json"
    if (Test-Path -LiteralPath $defaultAreaOverridesPath -PathType Leaf) {
        $AreaOverridesPath = $defaultAreaOverridesPath
    }
}
if ($MaxParallel -lt 1) {
    throw "MaxParallel must be at least 1."
}
if ($AreaDataId -lt -1 -or $AreaDataId -gt 0xFFFF) {
    throw "AreaDataId must be -1 or a valid unsigned 16-bit ID."
}

$unpackedRoot = Resolve-ExistingDirectory (Join-Path $DspreContents "unpacked") "DSPRE unpacked directory"
$mapsRoot = Resolve-ExistingDirectory (Join-Path $unpackedRoot "maps") "Map directory"
$mapTexturesRoot = Resolve-ExistingDirectory (Join-Path $unpackedRoot "mapTextures") "Map texture directory"
$buildingModelsRoot = Resolve-ExistingDirectory (Join-Path $unpackedRoot "exteriorBuildingModels") "Building model directory"
$buildingTexturesRoot = Resolve-ExistingDirectory (Join-Path $unpackedRoot "buildingTextures") "Building texture directory"
$areaDataRoot = Resolve-ExistingDirectory (Join-Path $unpackedRoot "areaData") "AreaData directory"
$matricesRoot = Resolve-ExistingDirectory (Join-Path $unpackedRoot "matrices") "Matrix directory"
$arm9Path = Resolve-ExistingFile (Join-Path $DspreContents "arm9\arm9.bin") "ARM9 binary"
$mapNamesPath = Resolve-ExistingFile (Join-Path $DspreContents "files\fielddata\maptable\mapname.bin") "Map names table"
$matrixPath = Resolve-ExistingFile (Join-Path $matricesRoot ("{0:D4}" -f $MatrixId)) "Matrix file"

$matrixVariantName = if ($AreaDataId -ge 0) {
    "matrix_{0:D4}_area_{1:D4}" -f $MatrixId, $AreaDataId
}
else {
    "matrix_{0:D4}" -f $MatrixId
}
$matrixOutputRoot = Join-Path $OutputRoot $matrixVariantName
$terrainOutputRoot = Join-Path $matrixOutputRoot "terrain"
$buildingOutputRoot = Join-Path $matrixOutputRoot "buildings"
$logsRoot = Join-Path $matrixOutputRoot "logs"
$matrixWorkRoot = Join-Path $WorkRoot ("matrix_{0:D4}" -f $MatrixId)
$mapModelsWorkRoot = Join-Path $matrixWorkRoot "map_models"

New-Item -ItemType Directory -Path $mapModelsWorkRoot -Force | Out-Null

Write-Host "Reading DSPRE data..."
$arm9 = [IO.File]::ReadAllBytes($arm9Path)
$headerCount = [int]((Get-Item -LiteralPath $mapNamesPath).Length / 16)
$headerEnd = $HeaderTableOffset + 24L * $headerCount
if ($HeaderTableOffset -lt 0 -or $headerEnd -gt $arm9.Length) {
    throw "Header table does not fit in ARM9. Offset: 0x$($HeaderTableOffset.ToString('X')); headers: $headerCount"
}

$headers = New-Object object[] $headerCount
for ($headerId = 0; $headerId -lt $headerCount; $headerId++) {
    $offset = [int]($HeaderTableOffset + 24L * $headerId)
    $headers[$headerId] = [pscustomobject][ordered]@{
        id = $headerId
        area_data_id = [int]$arm9[$offset]
        matrix_id = Get-U16 $arm9 ($offset + 2)
        location_name_id = [int]$arm9[$offset + 18]
    }
}

$areaData = @{}
Get-ChildItem -LiteralPath $areaDataRoot -File | ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -lt 8) {
        throw "AreaData file is too short: $($_.FullName)"
    }
    $id = [int]$_.Name
    $areaData[$id] = [pscustomobject][ordered]@{
        id = $id
        building_texture_id = Get-U16 $bytes 0
        map_texture_id = Get-U16 $bytes 2
        auxiliary_id = Get-U16 $bytes 4
        light_id = Get-U16 $bytes 6
    }
}

$areaOverrides = @{}
if (-not [string]::IsNullOrWhiteSpace($AreaOverridesPath)) {
    $AreaOverridesPath = Resolve-ExistingFile $AreaOverridesPath "Matrix AreaData overrides"
    $overrideDocument = [IO.File]::ReadAllText($AreaOverridesPath, [Text.Encoding]::UTF8) |
        ConvertFrom-Json
    if ([int]$overrideDocument.schema_version -ne 1) {
        throw "Unsupported Matrix AreaData override schema: $($overrideDocument.schema_version)"
    }
    $overrideSource = [IO.Path]::GetFullPath([string]$overrideDocument.source.dspre_contents)
    if (-not $overrideSource.Equals($DspreContents, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Matrix AreaData overrides were generated from a different DSPRE source. Regenerate them for: $DspreContents"
    }
    $expectedHeaderOffset = "0x{0:X}" -f $HeaderTableOffset
    if (-not $expectedHeaderOffset.Equals(
        [string]$overrideDocument.source.header_table_offset,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Matrix AreaData overrides use a different header table offset. Expected $expectedHeaderOffset."
    }
    foreach ($record in @($overrideDocument.overrides)) {
        $overrideMatrixId = [int]$record.matrix_id
        if ($areaOverrides.ContainsKey($overrideMatrixId)) {
            throw "Matrix AreaData overrides contain duplicate matrix ID $overrideMatrixId."
        }
        $areaOverrides[$overrideMatrixId] = $record
    }
}

$matrixBytes = [IO.File]::ReadAllBytes($matrixPath)
if ($matrixBytes.Length -lt 5) {
    throw "Matrix file is too short: $matrixPath"
}
$matrixWidth = [int]$matrixBytes[0]
$matrixHeight = [int]$matrixBytes[1]
$hasHeaders = $matrixBytes[2] -ne 0
$hasHeights = $matrixBytes[3] -ne 0
$nameLength = [int]$matrixBytes[4]
$matrixName = [Text.Encoding]::UTF8.GetString($matrixBytes, 5, $nameLength).TrimEnd([char]0)
$cellCount = $matrixWidth * $matrixHeight
$matrixOffset = 5 + $nameLength

$cellHeaderIds = New-Object int[] $cellCount
if ($hasHeaders) {
    for ($index = 0; $index -lt $cellCount; $index++) {
        $cellHeaderIds[$index] = Get-U16 $matrixBytes ($matrixOffset + 2 * $index)
    }
    $matrixOffset += 2 * $cellCount
}

$cellHeights = New-Object int[] $cellCount
if ($hasHeights) {
    for ($index = 0; $index -lt $cellCount; $index++) {
        $cellHeights[$index] = [int]$matrixBytes[$matrixOffset + $index]
    }
    $matrixOffset += $cellCount
}

$cellMapIds = New-Object int[] $cellCount
for ($index = 0; $index -lt $cellCount; $index++) {
    $cellMapIds[$index] = Get-U16 $matrixBytes ($matrixOffset + 2 * $index)
}

$fallbackHeader = $null
$fallbackAreaResolution = "per_cell_header"
if ($hasHeaders -and $AreaDataId -ge 0) {
    throw "Matrix $MatrixId has per-cell headers and cannot use -AreaDataId."
}
if (-not $hasHeaders) {
    $linkedHeaders = @($headers | Where-Object { $_.matrix_id -eq $MatrixId })
    $linkedAreaIds = @(
        $linkedHeaders | ForEach-Object { $_.area_data_id } | Sort-Object -Unique
    )
    if ($AreaDataId -ge 0) {
        $matchingHeaders = @($linkedHeaders | Where-Object { $_.area_data_id -eq $AreaDataId })
        if ($matchingHeaders.Count -gt 0) {
            $fallbackHeader = $matchingHeaders |
                Where-Object { $_.location_name_id -ne 0 } |
                Select-Object -First 1
            if ($null -eq $fallbackHeader) {
                $fallbackHeader = $matchingHeaders[0]
            }
            $fallbackAreaResolution = "linked_map_header"
        }
        elseif (
            $areaOverrides.ContainsKey($MatrixId) -and
            [int]$areaOverrides[$MatrixId].area_data_id -eq $AreaDataId
        ) {
            $fallbackHeader = [pscustomobject][ordered]@{
                id = -1
                area_data_id = $AreaDataId
                matrix_id = $MatrixId
                location_name_id = 0
            }
            $fallbackAreaResolution = [string]$areaOverrides[$MatrixId].resolution
        }
        else {
            throw "Matrix $MatrixId is not linked to AreaData $AreaDataId and has no matching resolved override."
        }
    }
    elseif ($linkedAreaIds.Count -gt 1) {
        throw "Matrix $MatrixId is linked to multiple AreaData IDs ($($linkedAreaIds -join ', ')). Pass -AreaDataId."
    }
    if ($linkedHeaders.Count -eq 0) {
        if ($null -ne $fallbackHeader) {
            # An explicit AreaData override already selected the fallback.
        }
        elseif (-not $areaOverrides.ContainsKey($MatrixId)) {
            throw "Matrix $MatrixId has no per-cell headers, linked map header, or resolved AreaData override. Run resolve_dspre_matrix_areas.ps1 or pass -AreaOverridesPath."
        }
        else {
            $override = $areaOverrides[$MatrixId]
            $overrideAreaId = [int]$override.area_data_id
            if (-not $areaData.ContainsKey($overrideAreaId)) {
                throw "Matrix $MatrixId override references missing AreaData $overrideAreaId."
            }
            $fallbackHeader = [pscustomobject][ordered]@{
                id = -1
                area_data_id = $overrideAreaId
                matrix_id = $MatrixId
                location_name_id = 0
            }
            $fallbackAreaResolution = [string]$override.resolution
        }
    }
    elseif ($null -eq $fallbackHeader) {
        $fallbackHeader = $linkedHeaders |
            Where-Object { $_.location_name_id -ne 0 } |
            Select-Object -First 1
        if ($null -eq $fallbackHeader) {
            $fallbackHeader = $linkedHeaders[0]
        }
        $fallbackAreaResolution = "linked_map_header"
    }
}

$terrainAssets = @{}
$buildingAssets = @{}
$mapCache = @{}
$cells = New-Object System.Collections.Generic.List[object]

for ($index = 0; $index -lt $cellCount; $index++) {
    $mapId = $cellMapIds[$index]
    if ($mapId -eq 0xFFFF) {
        continue
    }

    if ($hasHeaders) {
        $headerId = $cellHeaderIds[$index]
        if ($headerId -ge $headerCount) {
            throw "Matrix cell $index references missing header $headerId."
        }
        $header = $headers[$headerId]
    }
    else {
        $header = $fallbackHeader
        $headerId = $header.id
    }

    if (-not $areaData.ContainsKey($header.area_data_id)) {
        throw "Header $headerId references missing AreaData $($header.area_data_id)."
    }
    $area = $areaData[$header.area_data_id]
    $terrainKey = "map_{0:D4}_tex_{1:D4}" -f $mapId, $area.map_texture_id

    $mapPath = Join-Path $mapsRoot ("{0:D4}" -f $mapId)
    if (-not $mapCache.ContainsKey($mapId)) {
        $mapPath = Resolve-ExistingFile $mapPath "Map $mapId"
        $mapBytes = [IO.File]::ReadAllBytes($mapPath)
        if ($mapBytes.Length -lt 16) {
            throw "Map file is too short: $mapPath"
        }
        $permissionsLength = [int](Get-U32 $mapBytes 0)
        $buildingsLength = [int](Get-U32 $mapBytes 4)
        $modelLength = [int](Get-U32 $mapBytes 8)
        $terrainLength = [int](Get-U32 $mapBytes 12)
        $buildingsOffset = 16 + $permissionsLength
        $modelOffset = $buildingsOffset + $buildingsLength
        if ($modelOffset + $modelLength -gt $mapBytes.Length) {
            throw "Map section lengths exceed the file size: $mapPath"
        }
        if ([Text.Encoding]::ASCII.GetString($mapBytes, $modelOffset, 4) -ne "BMD0") {
            throw "Map model section is not BMD0: $mapPath"
        }

        $buildingRemainder = $buildingsLength % 48
        if ($buildingRemainder -ne 0) {
            $paddingOffset = $buildingsOffset + $buildingsLength - $buildingRemainder
            $hasKnownCrLfPadding = $buildingRemainder -eq 2 -and
                $mapBytes[$paddingOffset] -eq 0x0D -and
                $mapBytes[$paddingOffset + 1] -eq 0x0A
            if (-not $hasKnownCrLfPadding) {
                throw "Map building section has unsupported trailing bytes: $mapPath"
            }
        }

        $buildings = New-Object System.Collections.Generic.List[object]
        for ($buildingOffset = 0; $buildingOffset + 48 -le $buildingsLength; $buildingOffset += 48) {
            $recordOffset = $buildingsOffset + $buildingOffset
            $xFraction = Get-U16 $mapBytes ($recordOffset + 4)
            $xPosition = Get-I16 $mapBytes ($recordOffset + 6)
            $yFraction = Get-U16 $mapBytes ($recordOffset + 8)
            $yPosition = Get-I16 $mapBytes ($recordOffset + 10)
            $zFraction = Get-U16 $mapBytes ($recordOffset + 12)
            $zPosition = Get-I16 $mapBytes ($recordOffset + 14)
            $xRotation = Get-U16 $mapBytes ($recordOffset + 16)
            $yRotation = Get-U16 $mapBytes ($recordOffset + 20)
            $zRotation = Get-U16 $mapBytes ($recordOffset + 24)
            $buildings.Add([pscustomobject][ordered]@{
                model_id = [int](Get-U32 $mapBytes $recordOffset)
                position = [pscustomobject][ordered]@{
                    x = [Math]::Round($xPosition + $xFraction / 65536.0, 8)
                    y = [Math]::Round($yPosition + $yFraction / 65536.0, 8)
                    z = [Math]::Round($zPosition + $zFraction / 65536.0, 8)
                }
                position_integer = [pscustomobject][ordered]@{ x = $xPosition; y = $yPosition; z = $zPosition }
                position_fraction = [pscustomobject][ordered]@{ x = $xFraction; y = $yFraction; z = $zFraction }
                rotation_u16 = [pscustomobject][ordered]@{ x = $xRotation; y = $yRotation; z = $zRotation }
                rotation_degrees = [pscustomobject][ordered]@{
                    x = [Math]::Round($xRotation * 360.0 / 65536.0, 8)
                    y = [Math]::Round($yRotation * 360.0 / 65536.0, 8)
                    z = [Math]::Round($zRotation * 360.0 / 65536.0, 8)
                }
                size = [pscustomobject][ordered]@{
                    width = Get-U16 $mapBytes ($recordOffset + 29)
                    height = Get-U16 $mapBytes ($recordOffset + 33)
                    length = Get-U16 $mapBytes ($recordOffset + 37)
                }
            })
        }

        $mapCache[$mapId] = [pscustomobject][ordered]@{
            path = $mapPath
            bytes = $mapBytes
            permissions_length = $permissionsLength
            buildings_length = $buildingsLength
            model_offset = $modelOffset
            model_length = $modelLength
            terrain_length = $terrainLength
            buildings = $buildings
        }
    }

    if (-not $terrainAssets.ContainsKey($terrainKey)) {
        $terrainAssets[$terrainKey] = [pscustomobject][ordered]@{
            key = $terrainKey
            map_id = $mapId
            texture_id = $area.map_texture_id
            source_map = $mapCache[$mapId].path
            source_texture = Join-Path $mapTexturesRoot ("{0:D4}" -f $area.map_texture_id)
            status = "pending"
            output_glbs = @()
            error = $null
        }
    }

    $cellBuildings = New-Object System.Collections.Generic.List[object]
    foreach ($building in $mapCache[$mapId].buildings) {
        $buildingKey = "building_{0:D4}_tex_{1:D4}" -f $building.model_id, $area.building_texture_id
        if (-not $buildingAssets.ContainsKey($buildingKey)) {
            $buildingAssets[$buildingKey] = [pscustomobject][ordered]@{
                key = $buildingKey
                model_id = $building.model_id
                texture_id = $area.building_texture_id
                source_model = Join-Path $buildingModelsRoot ("{0:D4}" -f $building.model_id)
                source_texture = Join-Path $buildingTexturesRoot ("{0:D4}" -f $area.building_texture_id)
                status = "pending"
                output_glbs = @()
                error = $null
            }
        }
        $cellBuildings.Add([pscustomobject][ordered]@{
            asset_key = $buildingKey
            model_id = $building.model_id
            position = $building.position
            position_integer = $building.position_integer
            position_fraction = $building.position_fraction
            rotation_u16 = $building.rotation_u16
            rotation_degrees = $building.rotation_degrees
            size = $building.size
        })
    }

    $cells.Add([pscustomobject][ordered]@{
        x = $index % $matrixWidth
        y = [Math]::Floor($index / $matrixWidth)
        altitude = $cellHeights[$index]
        map_id = $mapId
        header_id = $headerId
        area_data_id = $header.area_data_id
        area_resolution = if ($hasHeaders) { "per_cell_header" } else { $fallbackAreaResolution }
        map_texture_id = $area.map_texture_id
        building_texture_id = $area.building_texture_id
        terrain_asset_key = $terrainKey
        buildings = $cellBuildings
    })
}

if ($Force) {
    Clear-DirectoryUnderRoot $matrixOutputRoot $OutputRoot
}
foreach ($directory in @($terrainOutputRoot, $buildingOutputRoot, $logsRoot)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

$conversionJobs = New-Object System.Collections.Generic.List[object]
foreach ($asset in @($terrainAssets.Values | Sort-Object key)) {
    $mapInfo = $mapCache[$asset.map_id]
    $modelPath = Join-Path $mapModelsWorkRoot ("{0}.nsbmd" -f $asset.key)
    if ($Force -or -not (Test-Path -LiteralPath $modelPath -PathType Leaf)) {
        $modelBytes = New-Object byte[] $mapInfo.model_length
        [Buffer]::BlockCopy($mapInfo.bytes, $mapInfo.model_offset, $modelBytes, 0, $mapInfo.model_length)
        [IO.File]::WriteAllBytes($modelPath, $modelBytes)
    }
    $asset.source_texture = Resolve-ExistingFile $asset.source_texture "Map texture $($asset.texture_id)"
    $outputDirectory = Join-Path $terrainOutputRoot $asset.key
    $validGlbs = @(Get-ValidGlbs $outputDirectory)
    if (-not $Force -and $validGlbs.Count -gt 0) {
        $asset.status = "skipped_existing"
        $asset.output_glbs = @($validGlbs | ForEach-Object { Get-ForwardRelativePath $matrixOutputRoot $_.FullName })
        continue
    }
    Clear-DirectoryUnderRoot $outputDirectory $matrixOutputRoot
    $conversionJobs.Add([pscustomobject][ordered]@{
        Kind = "terrain"
        Key = $asset.key
        ModelPath = $modelPath
        TexturePath = $asset.source_texture
        OutputDirectory = $outputDirectory
        Asset = $asset
    })
}

foreach ($asset in @($buildingAssets.Values | Sort-Object key)) {
    $asset.source_model = Resolve-ExistingFile $asset.source_model "Building model $($asset.model_id)"
    $asset.source_texture = Resolve-ExistingFile $asset.source_texture "Building texture $($asset.texture_id)"
    $outputDirectory = Join-Path $buildingOutputRoot $asset.key
    $validGlbs = @(Get-ValidGlbs $outputDirectory)
    if (-not $Force -and $validGlbs.Count -gt 0) {
        $asset.status = "skipped_existing"
        $asset.output_glbs = @($validGlbs | ForEach-Object { Get-ForwardRelativePath $matrixOutputRoot $_.FullName })
        continue
    }
    Clear-DirectoryUnderRoot $outputDirectory $matrixOutputRoot
    $conversionJobs.Add([pscustomobject][ordered]@{
        Kind = "building"
        Key = $asset.key
        ModelPath = $asset.source_model
        TexturePath = $asset.source_texture
        OutputDirectory = $outputDirectory
        Asset = $asset
    })
}

Write-Host ("Matrix {0:D4}: {1} occupied cells, {2} terrain assets, {3} building assets, {4} conversions queued." -f $MatrixId, $cells.Count, $terrainAssets.Count, $buildingAssets.Count, $conversionJobs.Count)

$failures = New-Object System.Collections.Generic.List[object]
$running = New-Object System.Collections.Generic.List[object]
$completedCount = 0
$totalJobs = $conversionJobs.Count

foreach ($job in $conversionJobs) {
    while ($running.Count -ge $MaxParallel) {
        $completedItem = $running | Where-Object { $_.Process.HasExited } | Select-Object -First 1
        if ($null -eq $completedItem) {
            Start-Sleep -Milliseconds 50
            continue
        }
        Complete-Conversion $completedItem $matrixOutputRoot $failures
        $null = $running.Remove($completedItem)
        $completedCount++
        Write-Progress -Activity "Exporting DSPRE models" -Status "$completedCount / $totalJobs" -PercentComplete (100.0 * $completedCount / [Math]::Max(1, $totalJobs))
    }

    $stdoutPath = Join-Path $logsRoot ("{0}_{1}.stdout.log" -f $job.Kind, $job.Key)
    $stderrPath = Join-Path $logsRoot ("{0}_{1}.stderr.log" -f $job.Kind, $job.Key)
    foreach ($logPath in @($stdoutPath, $stderrPath)) {
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
    }
    $arguments = 'convert "{0}" "{1}" -f glb -o "{2}" --overwrite' -f $job.ModelPath, $job.TexturePath, $job.OutputDirectory
    $process = Start-Process -FilePath $ApiculaPath -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $running.Add([pscustomobject][ordered]@{
        Job = $job
        Process = $process
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
    })
}

while ($running.Count -gt 0) {
    $completedItems = @($running | Where-Object { $_.Process.HasExited })
    if ($completedItems.Count -eq 0) {
        Start-Sleep -Milliseconds 50
        continue
    }
    foreach ($completedItem in $completedItems) {
        Complete-Conversion $completedItem $matrixOutputRoot $failures
        $null = $running.Remove($completedItem)
        $completedCount++
        Write-Progress -Activity "Exporting DSPRE models" -Status "$completedCount / $totalJobs" -PercentComplete (100.0 * $completedCount / [Math]::Max(1, $totalJobs))
    }
}
Write-Progress -Activity "Exporting DSPRE models" -Completed

$terrainArray = @($terrainAssets.Values | Sort-Object key)
$buildingArray = @($buildingAssets.Values | Sort-Object key)
$exportedCount = @($terrainArray + $buildingArray | Where-Object { $_.status -eq "exported" }).Count
$skippedCount = @($terrainArray + $buildingArray | Where-Object { $_.status -eq "skipped_existing" }).Count
$failedCount = @($terrainArray + $buildingArray | Where-Object { $_.status -eq "failed" }).Count

$manifest = [pscustomobject][ordered]@{
    schema_version = 1
    generated_utc = [DateTime]::UtcNow.ToString("o")
    source = [pscustomobject][ordered]@{
        dspre_contents = $DspreContents
        apicula = $ApiculaPath
        area_overrides = $AreaOverridesPath
        header_table_offset = ("0x{0:X}" -f $HeaderTableOffset)
    }
    matrix = [pscustomobject][ordered]@{
        id = $MatrixId
        variant = $matrixVariantName
        name = $matrixName
        width = $matrixWidth
        height = $matrixHeight
        has_headers = $hasHeaders
        has_heights = $hasHeights
        occupied_cells = $cells.Count
        area_data_id = if ($hasHeaders) { $null } else { $fallbackHeader.area_data_id }
    }
    summary = [pscustomobject][ordered]@{
        terrain_assets = $terrainArray.Count
        building_assets = $buildingArray.Count
        building_instances = [int](($cells | ForEach-Object { $_.buildings.Count } | Measure-Object -Sum).Sum)
        exported = $exportedCount
        skipped_existing = $skippedCount
        failed = $failedCount
    }
    assets = [pscustomobject][ordered]@{
        terrain = $terrainArray
        buildings = $buildingArray
    }
    cells = $cells
    failures = $failures
}

$utf8NoBom = New-Object Text.UTF8Encoding($false)
$manifestPath = Join-Path $matrixOutputRoot "manifest.json"
$summaryPath = Join-Path $matrixOutputRoot "summary.json"
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 14), $utf8NoBom)
[IO.File]::WriteAllText($summaryPath, ([pscustomobject][ordered]@{
    matrix_id = $MatrixId
    variant = $matrixVariantName
    area_data_id = if ($hasHeaders) { $null } else { $fallbackHeader.area_data_id }
    occupied_cells = $cells.Count
    terrain_assets = $terrainArray.Count
    building_assets = $buildingArray.Count
    building_instances = $manifest.summary.building_instances
    exported = $exportedCount
    skipped_existing = $skippedCount
    failed = $failedCount
    manifest = $manifestPath
} | ConvertTo-Json -Depth 4), $utf8NoBom)

Write-Host ""
Write-Host "Export complete."
Write-Host "  Exported: $exportedCount"
Write-Host "  Reused:   $skippedCount"
Write-Host "  Failed:   $failedCount"
Write-Host "  Manifest: $manifestPath"

if ($failedCount -gt 0) {
    exit 2
}
