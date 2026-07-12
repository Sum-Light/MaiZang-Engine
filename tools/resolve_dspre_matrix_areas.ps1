[CmdletBinding()]
param(
    [string]$DspreContents = "",
    [string]$ApiculaPath = "C:\Users\YbbNa\Downloads\DSPRE-win-Portable\current\Tools\apicula.exe",
    [string]$OutputPath = "",
    [string]$WorkRoot = "",
    [long]$HeaderTableOffset = 0xE56F0,
    [switch]$AllowUnresolved
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $workspaceRoot "generated\dspre_matrix_area_overrides.json"
}
if ([string]::IsNullOrWhiteSpace($WorkRoot)) {
    $WorkRoot = Join-Path $workspaceRoot ".work\dspre_area_resolution"
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

function Get-U16 {
    param([byte[]]$Bytes, [int]$Offset)
    return [int][BitConverter]::ToUInt16($Bytes, $Offset)
}

function Get-U32 {
    param([byte[]]$Bytes, [int]$Offset)
    return [long][BitConverter]::ToUInt32($Bytes, $Offset)
}

function Get-NitroInfo {
    param([string[]]$Paths)

    $quotedPaths = @(
        $Paths | ForEach-Object { '"{0}"' -f $_.Replace('"', '\"') }
    )
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $ApiculaPath
    $startInfo.Arguments = "info $($quotedPaths -join ' ')"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Could not start apicula info for $($Paths -join ', ')."
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $exitCode = $process.ExitCode
    $process.Dispose()
    $output = "$stdout`n$stderr"
    if ($exitCode -ne 0) {
        throw "apicula info failed for $($Paths -join ', ') with exit code $exitCode.`n$output"
    }
    return $output
}

function Normalize-NitroName {
    param([string]$Name)

    $value = $Name.Trim()
    if ($value.Length -ge 2 -and $value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') {
        return $value.Substring(1, $value.Length - 2)
    }
    return $value
}

function Get-ExternalModelRequirements {
    param([string]$ModelPath)

    $info = Get-NitroInfo -Paths @($ModelPath)
    $requirements = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    foreach ($match in [regex]::Matches(
        $info,
        '(?m)^\s+(?:Texture|Palette):\s+(.+?)\s+\((?:not found|skipped; texture missing)\)\s*$'
    )) {
        $name = Normalize-NitroName $match.Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $null = $requirements.Add($name)
        }
    }
    return @($requirements | Sort-Object)
}

function Get-ArchiveNames {
    param([string]$ArchivePath)

    $info = Get-NitroInfo -Paths @($ArchivePath)
    $names = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    foreach ($match in [regex]::Matches($info, '(?m)^\s+Name:\s+(.+?)\s*$')) {
        $name = Normalize-NitroName $match.Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $null = $names.Add($name)
        }
    }
    return ,$names
}

function Test-Requirements {
    param(
        [string[]]$Requirements,
        [System.Collections.Generic.HashSet[string]]$AvailableNames
    )

    foreach ($requirement in $Requirements) {
        if (-not $AvailableNames.Contains($requirement)) {
            return $false
        }
    }
    return $true
}

function Get-MatrixInfo {
    param([IO.FileInfo]$File)

    $bytes = [IO.File]::ReadAllBytes($File.FullName)
    if ($bytes.Length -lt 5) {
        throw "Matrix file is too short: $($File.FullName)"
    }
    $width = [int]$bytes[0]
    $height = [int]$bytes[1]
    $hasHeaders = $bytes[2] -ne 0
    $hasHeights = $bytes[3] -ne 0
    $nameLength = [int]$bytes[4]
    $cellCount = $width * $height
    $offset = 5 + $nameLength
    $headerIds = New-Object int[] $cellCount
    if ($hasHeaders) {
        for ($index = 0; $index -lt $cellCount; $index++) {
            $headerIds[$index] = Get-U16 $bytes ($offset + 2 * $index)
        }
        $offset += 2 * $cellCount
    }
    if ($hasHeights) {
        $offset += $cellCount
    }
    if ($offset + 2 * $cellCount -ne $bytes.Length) {
        throw "Matrix layout does not match its file length: $($File.FullName)"
    }
    $mapIds = New-Object int[] $cellCount
    for ($index = 0; $index -lt $cellCount; $index++) {
        $mapIds[$index] = Get-U16 $bytes ($offset + 2 * $index)
    }
    return [pscustomobject]@{
        id = [int]$File.Name
        name = [Text.Encoding]::UTF8.GetString($bytes, 5, $nameLength).TrimEnd([char]0)
        has_headers = $hasHeaders
        header_ids = $headerIds
        map_ids = $mapIds
    }
}

if ([string]::IsNullOrWhiteSpace($DspreContents)) {
    $existingManifest = Join-Path $workspaceRoot "generated\dspre_glb\matrix_0000\manifest.json"
    if (Test-Path -LiteralPath $existingManifest -PathType Leaf) {
        $manifestText = [IO.File]::ReadAllText($existingManifest, [Text.Encoding]::UTF8)
        $existingSource = [string](($manifestText | ConvertFrom-Json).source.dspre_contents)
        if (Test-Path -LiteralPath $existingSource -PathType Container) {
            $DspreContents = $existingSource
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
}

$DspreContents = Resolve-ExistingDirectory $DspreContents "DSPRE contents directory"
$ApiculaPath = Resolve-ExistingFile $ApiculaPath "apicula.exe"
$unpackedRoot = Resolve-ExistingDirectory (Join-Path $DspreContents "unpacked") "DSPRE unpacked directory"
$matricesRoot = Resolve-ExistingDirectory (Join-Path $unpackedRoot "matrices") "Matrix directory"
$mapsRoot = Resolve-ExistingDirectory (Join-Path $unpackedRoot "maps") "Map directory"
$areaDataRoot = Resolve-ExistingDirectory (Join-Path $unpackedRoot "areaData") "AreaData directory"
$mapTexturesRoot = Resolve-ExistingDirectory (Join-Path $unpackedRoot "mapTextures") "Map texture directory"
$buildingModelsRoot = Resolve-ExistingDirectory (Join-Path $unpackedRoot "exteriorBuildingModels") "Building model directory"
$buildingTexturesRoot = Resolve-ExistingDirectory (Join-Path $unpackedRoot "buildingTextures") "Building texture directory"
$arm9Path = Resolve-ExistingFile (Join-Path $DspreContents "arm9\arm9.bin") "ARM9 binary"
$mapNamesPath = Resolve-ExistingFile (Join-Path $DspreContents "files\fielddata\maptable\mapname.bin") "Map names table"

$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot).TrimEnd('\')
$allowedWorkRoot = [IO.Path]::GetFullPath((Join-Path $workspaceRoot ".work")).TrimEnd('\') + '\'
if (-not ($WorkRoot + '\').StartsWith($allowedWorkRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "WorkRoot must stay under the repository .work directory: $WorkRoot"
}
New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null

$arm9 = [IO.File]::ReadAllBytes($arm9Path)
$headerCount = [int]((Get-Item -LiteralPath $mapNamesPath).Length / 16)
$headerEnd = $HeaderTableOffset + 24L * $headerCount
if ($HeaderTableOffset -lt 0 -or $headerEnd -gt $arm9.Length) {
    throw "Header table does not fit in ARM9."
}
$headers = New-Object object[] $headerCount
for ($headerId = 0; $headerId -lt $headerCount; $headerId++) {
    $offset = [int]($HeaderTableOffset + 24L * $headerId)
    $headers[$headerId] = [pscustomobject]@{
        id = $headerId
        area_data_id = [int]$arm9[$offset]
        matrix_id = Get-U16 $arm9 ($offset + 2)
        location_name_id = [int]$arm9[$offset + 18]
    }
}

$areaData = @(
    foreach ($file in Get-ChildItem -LiteralPath $areaDataRoot -File | Sort-Object { [int]$_.Name }) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -lt 8) {
            throw "AreaData file is too short: $($file.FullName)"
        }
        [pscustomobject]@{
            id = [int]$file.Name
            building_texture_id = Get-U16 $bytes 0
            map_texture_id = Get-U16 $bytes 2
        }
    }
)

$matrixInfos = @(
    Get-ChildItem -LiteralPath $matricesRoot -File |
        Where-Object { $_.Name -match '^\d{4}$' } |
        Sort-Object { [int]$_.Name } |
        ForEach-Object { Get-MatrixInfo $_ }
)
$knownMapAreas = @{}
$orphanMatrices = New-Object System.Collections.Generic.List[object]
foreach ($matrix in $matrixInfos) {
    $linkedHeaders = @($headers | Where-Object { $_.matrix_id -eq $matrix.id })
    if (-not $matrix.has_headers -and $linkedHeaders.Count -eq 0) {
        $orphanMatrices.Add($matrix)
        continue
    }
    for ($index = 0; $index -lt $matrix.map_ids.Count; $index++) {
        $mapId = $matrix.map_ids[$index]
        if ($mapId -eq 0xFFFF) {
            continue
        }
        $areaIds = if ($matrix.has_headers) {
            @([int]$headers[$matrix.header_ids[$index]].area_data_id)
        }
        else {
            @(
                $linkedHeaders |
                    ForEach-Object { [int]$_.area_data_id } |
                    Sort-Object -Unique
            )
        }
        if (-not $knownMapAreas.ContainsKey($mapId)) {
            $knownMapAreas[$mapId] = New-Object System.Collections.Generic.HashSet[int]
        }
        foreach ($areaId in $areaIds) {
            $null = $knownMapAreas[$mapId].Add([int]$areaId)
        }
    }
}

Write-Host "Reading Nitro texture and palette catalogs..."
$mapTextureNames = @{}
foreach ($file in Get-ChildItem -LiteralPath $mapTexturesRoot -File | Sort-Object { [int]$_.Name }) {
    $mapTextureNames[[int]$file.Name] = Get-ArchiveNames $file.FullName
}
$buildingTextureNames = @{}
foreach ($file in Get-ChildItem -LiteralPath $buildingTexturesRoot -File | Sort-Object { [int]$_.Name }) {
    $buildingTextureNames[[int]$file.Name] = Get-ArchiveNames $file.FullName
}

$buildingRequirements = @{}
$mapRecords = @{}
$resolutions = New-Object System.Collections.Generic.List[object]
$unresolved = New-Object System.Collections.Generic.List[object]
foreach ($matrix in $orphanMatrices) {
    $matrixMapIds = @($matrix.map_ids | Where-Object { $_ -ne 0xFFFF } | Sort-Object -Unique)
    $matrixCandidateSignatures = $null
    $matrixEvidence = New-Object System.Collections.Generic.List[object]

    foreach ($mapId in $matrixMapIds) {
        if (-not $mapRecords.ContainsKey($mapId)) {
            $mapPath = Resolve-ExistingFile (Join-Path $mapsRoot ("{0:D4}" -f $mapId)) "Map $mapId"
            $mapBytes = [IO.File]::ReadAllBytes($mapPath)
            if ($mapBytes.Length -lt 16) {
                throw "Map file is too short: $mapPath"
            }
            $permissionsLength = [int](Get-U32 $mapBytes 0)
            $buildingsLength = [int](Get-U32 $mapBytes 4)
            $modelLength = [int](Get-U32 $mapBytes 8)
            $buildingsOffset = 16 + $permissionsLength
            $modelOffset = $buildingsOffset + $buildingsLength
            if ($modelOffset + $modelLength -gt $mapBytes.Length) {
                throw "Map section lengths exceed the file size: $mapPath"
            }
            $modelPath = Join-Path $WorkRoot ("map_{0:D4}.nsbmd" -f $mapId)
            $modelBytes = New-Object byte[] $modelLength
            [Buffer]::BlockCopy($mapBytes, $modelOffset, $modelBytes, 0, $modelLength)
            [IO.File]::WriteAllBytes($modelPath, $modelBytes)

            $buildingIds = New-Object System.Collections.Generic.HashSet[int]
            for ($buildingOffset = 0; $buildingOffset + 48 -le $buildingsLength; $buildingOffset += 48) {
                $null = $buildingIds.Add([int](Get-U32 $mapBytes ($buildingsOffset + $buildingOffset)))
            }
            $mapRecords[$mapId] = [pscustomobject]@{
                terrain_requirements = @(Get-ExternalModelRequirements $modelPath)
                building_ids = @($buildingIds | Sort-Object)
            }
        }

        $mapRecord = $mapRecords[$mapId]
        $allBuildingRequirements = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
        foreach ($buildingId in $mapRecord.building_ids) {
            if (-not $buildingRequirements.ContainsKey($buildingId)) {
                $buildingPath = Resolve-ExistingFile (
                    Join-Path $buildingModelsRoot ("{0:D4}" -f $buildingId)
                ) "Building model $buildingId"
                $buildingRequirements[$buildingId] = @(Get-ExternalModelRequirements $buildingPath)
            }
            foreach ($name in $buildingRequirements[$buildingId]) {
                $null = $allBuildingRequirements.Add($name)
            }
        }

        $candidateAreas = @()
        $resolutionSource = "asset_compatibility"
        if ($knownMapAreas.ContainsKey($mapId) -and $knownMapAreas[$mapId].Count -eq 1) {
            $knownAreaId = @($knownMapAreas[$mapId] | Select-Object -First 1)[0]
            $candidateAreas = @($areaData | Where-Object { $_.id -eq $knownAreaId })
            $resolutionSource = "known_map_reference"
        }
        else {
            $candidateAreas = @(
                $areaData | Where-Object {
                    $mapNames = $mapTextureNames[$_.map_texture_id]
                    $buildingNames = $buildingTextureNames[$_.building_texture_id]
                    $null -ne $mapNames -and
                        $null -ne $buildingNames -and
                        (Test-Requirements $mapRecord.terrain_requirements $mapNames) -and
                        (Test-Requirements @($allBuildingRequirements) $buildingNames)
                }
            )
        }

        $signatures = @(
            $candidateAreas | ForEach-Object {
                "{0}:{1}" -f $_.map_texture_id, $_.building_texture_id
            } | Sort-Object -Unique
        )
        if ($null -eq $matrixCandidateSignatures) {
            $matrixCandidateSignatures = @($signatures)
        }
        else {
            $matrixCandidateSignatures = @($matrixCandidateSignatures | Where-Object { $signatures -contains $_ })
        }
        $matrixEvidence.Add([pscustomobject][ordered]@{
            map_id = $mapId
            terrain_requirements = @($mapRecord.terrain_requirements)
            building_ids = @($mapRecord.building_ids)
            building_requirements = @($allBuildingRequirements | Sort-Object)
            resolution_source = $resolutionSource
            candidate_area_ids = @(
                $candidateAreas | ForEach-Object { $_.id } | Sort-Object
            )
            candidate_signatures = $signatures
        })
    }

    if ($matrixCandidateSignatures.Count -ne 1) {
        $unresolved.Add([pscustomobject][ordered]@{
            matrix_id = $matrix.id
            candidate_signatures = @($matrixCandidateSignatures)
            evidence = @($matrixEvidence | ForEach-Object { $_ })
        })
        continue
    }

    $selectedSignature = $matrixCandidateSignatures[0]
    $signatureParts = $selectedSignature.Split(':')
    $mapTextureId = [int]$signatureParts[0]
    $buildingTextureId = [int]$signatureParts[1]
    $matchingAreas = @(
        $areaData | Where-Object {
            $_.map_texture_id -eq $mapTextureId -and
                $_.building_texture_id -eq $buildingTextureId
        } | Sort-Object id
    )
    if ($matchingAreas.Count -eq 0) {
        throw "Internal area resolution error for matrix $($matrix.id)."
    }
    $usesKnownMapReference = @(
        $matrixEvidence | Where-Object { $_.resolution_source -eq "known_map_reference" }
    ).Count -gt 0
    $resolutionName = if ($usesKnownMapReference) {
        "known_map_reference"
    }
    else {
        "asset_compatibility"
    }
    $resolutions.Add([pscustomobject][ordered]@{
        matrix_id = $matrix.id
        area_data_id = $matchingAreas[0].id
        equivalent_area_ids = @($matchingAreas | ForEach-Object { $_.id })
        map_texture_id = $mapTextureId
        building_texture_id = $matchingAreas[0].building_texture_id
        resolution = $resolutionName
        evidence = @($matrixEvidence | ForEach-Object { $_ })
    })
}

$overrideById = @{}
foreach ($record in $resolutions) {
    $overrideById[[int]$record.matrix_id] = $record
}
$unresolvedIds = New-Object System.Collections.Generic.HashSet[int]
foreach ($record in $unresolved) {
    $null = $unresolvedIds.Add([int]$record.matrix_id)
}
$variants = New-Object System.Collections.Generic.List[object]
foreach ($matrix in $matrixInfos) {
    if ($unresolvedIds.Contains([int]$matrix.id)) {
        continue
    }
    if ($matrix.has_headers) {
        $variants.Add([pscustomobject][ordered]@{
            matrix_id = [int]$matrix.id
            variant = "matrix_{0:D4}" -f [int]$matrix.id
            area_data_id = $null
            resolution = "per_cell_header"
        })
        continue
    }
    $linkedAreaIds = @(
        $headers |
            Where-Object { $_.matrix_id -eq $matrix.id } |
            ForEach-Object { [int]$_.area_data_id } |
            Sort-Object -Unique
    )
    if ($linkedAreaIds.Count -gt 0) {
        foreach ($areaId in $linkedAreaIds) {
            $variantName = if ($linkedAreaIds.Count -gt 1) {
                "matrix_{0:D4}_area_{1:D4}" -f [int]$matrix.id, [int]$areaId
            }
            else {
                "matrix_{0:D4}" -f [int]$matrix.id
            }
            $variants.Add([pscustomobject][ordered]@{
                matrix_id = [int]$matrix.id
                variant = $variantName
                area_data_id = [int]$areaId
                resolution = "linked_map_header"
            })
        }
        continue
    }
    if (-not $overrideById.ContainsKey([int]$matrix.id)) {
        throw "Internal resolution error: matrix $($matrix.id) is neither linked, resolved, nor unresolved."
    }
    $override = $overrideById[[int]$matrix.id]
    $variants.Add([pscustomobject][ordered]@{
        matrix_id = [int]$matrix.id
        variant = "matrix_{0:D4}" -f [int]$matrix.id
        area_data_id = [int]$override.area_data_id
        resolution = [string]$override.resolution
    })
}

$result = [pscustomobject][ordered]@{
    schema_version = 1
    generated_utc = [DateTime]::UtcNow.ToString("o")
    source = [pscustomobject][ordered]@{
        dspre_contents = $DspreContents
        header_table_offset = ("0x{0:X}" -f $HeaderTableOffset)
    }
    summary = [pscustomobject][ordered]@{
        matrices = $matrixInfos.Count
        linked_matrices = $matrixInfos.Count - $orphanMatrices.Count
        orphan_matrices = $orphanMatrices.Count
        resolved_orphans = $resolutions.Count
        unresolved_orphans = $unresolved.Count
        ready_variants = $variants.Count
    }
    variants = @($variants | ForEach-Object { $_ })
    overrides = @($resolutions | ForEach-Object { $_ })
    unresolved = @($unresolved | ForEach-Object { $_ })
}
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($OutputPath, ($result | ConvertTo-Json -Depth 20), $utf8NoBom)

Write-Host "DSPRE matrix AreaData resolution complete."
Write-Host "  Matrices:          $($matrixInfos.Count)"
Write-Host "  Header-linked:     $($matrixInfos.Count - $orphanMatrices.Count)"
Write-Host "  Orphan resolved:   $($resolutions.Count)"
Write-Host "  Orphan unresolved: $($unresolved.Count)"
Write-Host "  Output:            $OutputPath"

if ($unresolved.Count -gt 0 -and -not $AllowUnresolved) {
    $ids = @(
        $unresolved | ForEach-Object { "{0:D4}" -f $_.matrix_id }
    ) -join ", "
    throw "AreaData could not be resolved uniquely for matrix IDs: $ids"
}
