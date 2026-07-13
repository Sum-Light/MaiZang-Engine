[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "dspre_collision_support.ps1")

function New-SyntheticLandData {
    param([switch]$ZeroNormalY, [switch]$InvalidPlateIndex)

    $attributes = New-Object byte[] 2048
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]0x8015), 0, $attributes, 0, 2)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]0x0034), 0, $attributes, 2, 2)

    $bdhcStream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($bdhcStream)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes("BDHC"))
        foreach ($count in @([uint16]2, [uint16]1, [uint16]2, [uint16]2, [uint16]1, [uint16]2)) {
            $writer.Write($count)
        }
        foreach ($value in @(-1048576, -1048576, 1048576, 1048576)) {
            $writer.Write([int]$value)
        }
        $writer.Write([int]0)
        $normalY = if ($ZeroNormalY) { 0 } else { 4096 }
        $writer.Write([int]$normalY)
        $writer.Write([int]0)
        $writer.Write([int]-65536)
        $writer.Write([int]-131072)
        foreach ($constantIndex in 0, 1) {
            $writer.Write([uint16]0)
            $secondPointIndex = if ($InvalidPlateIndex -and $constantIndex -eq 1) { 2 } else { 1 }
            $writer.Write([uint16]$secondPointIndex)
            $writer.Write([uint16]0)
            $writer.Write([uint16]$constantIndex)
        }
        $writer.Write([int]1048576)
        $writer.Write([uint16]2)
        $writer.Write([uint16]0)
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Flush()
        $bdhc = $bdhcStream.ToArray()
    }
    finally {
        $writer.Dispose()
        $bdhcStream.Dispose()
    }

    $bytes = New-Object byte[] (16 + $attributes.Length + $bdhc.Length)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]$attributes.Length), 0, $bytes, 0, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]0), 0, $bytes, 4, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]0), 0, $bytes, 8, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]$bdhc.Length), 0, $bytes, 12, 4)
    [Buffer]::BlockCopy($attributes, 0, $bytes, 16, $attributes.Length)
    [Buffer]::BlockCopy($bdhc, 0, $bytes, 16 + $attributes.Length, $bdhc.Length)
    return $bytes
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Label)

    try {
        & $Action
    }
    catch {
        return
    }
    throw "$Label did not reject invalid data."
}

$asset = ConvertFrom-DspreMapCollision -Bytes (New-SyntheticLandData) -MapId 7
if (
    [string]$asset.key -ne "map_0007_collision" -or
    [int]$asset.terrain_attributes.byte_length -ne 2048 -or
    [int]$asset.bdhc.byte_length -ne 80 -or
    [int]$asset.bdhc.counts.plates -ne 2
) {
    throw "Synthetic collision data produced unexpected metadata."
}
$packedAttributes = [Convert]::FromBase64String([string]$asset.terrain_attributes.data_base64)
if (
    [BitConverter]::ToUInt16($packedAttributes, 0) -ne 0x8015 -or
    [BitConverter]::ToUInt16($packedAttributes, 2) -ne 0x0034
) {
    throw "Terrain attributes did not retain collision and behavior bits."
}
$packedBdhc = [Convert]::FromBase64String([string]$asset.bdhc.data_base64)
if ([BitConverter]::ToInt32($packedBdhc, 16) -ne -1048576) {
    throw "Signed FX32 coordinates were not preserved."
}

$manifest = [pscustomobject]@{
    schema_version = 2
    summary = [pscustomobject]@{
        collision_assets = 1
        terrain_attribute_tiles = 1024
        bdhc_assets = 1
    }
    collision_format = [pscustomobject]@{
        schema_version = 1
        terrain_width = 32
        terrain_height = 32
        terrain_order = "row_major"
        collision_mask = 0x8000
        behavior_mask = 0x00FF
        fx32_fraction_bits = 12
        source_units_per_tile = 16
        source_units_per_world_unit = 16
        bdhc_origin = "map_center"
        map_prop_collision = "cell_terrain_attributes"
    }
    collision_assets = @($asset)
    cells = @([pscustomobject]@{
        x = 0
        y = 0
        map_id = 7
        collision_asset_key = "map_0007_collision"
        buildings = @([pscustomobject]@{
            model_id = 1
            scale_fx32 = [pscustomobject]@{ x = 4096; y = 4096; z = 4096 }
            collision = [pscustomobject]@{ mode = "cell_terrain_attributes" }
        })
    })
}
$stats = Assert-DspreCollisionManifest -Manifest $manifest -ExpectedManifestSchema 2
if ([int]$stats.collision_assets -ne 1 -or [int]$stats.referenced_cells -ne 1) {
    throw "Synthetic collision manifest returned incorrect coverage."
}

Assert-Throws { ConvertFrom-DspreMapCollision -Bytes (New-SyntheticLandData -InvalidPlateIndex) -MapId 7 } "BDHC plate index"
Assert-Throws { ConvertFrom-DspreMapCollision -Bytes (New-SyntheticLandData -ZeroNormalY) -MapId 7 } "BDHC zero normal Y"
$truncated = New-SyntheticLandData
[Array]::Resize([ref]$truncated, $truncated.Length - 1)
Assert-Throws { ConvertFrom-DspreMapCollision -Bytes $truncated -MapId 7 } "Truncated land data"

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$fingerprintRoot = [IO.Path]::GetFullPath(
    (Join-Path $tempBase ("maizang_fingerprint_{0}" -f [Guid]::NewGuid().ToString("N")))
)
if (-not ($fingerprintRoot + '\').StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Synthetic fingerprint root escaped the system temporary directory."
}
try {
    $sourceA = Join-Path $fingerprintRoot "source_a"
    $sourceB = Join-Path $fingerprintRoot "source_b"
    $null = [IO.Directory]::CreateDirectory((Join-Path $sourceA "nested"))
    $null = [IO.Directory]::CreateDirectory((Join-Path $sourceB "nested"))
    [IO.File]::WriteAllBytes((Join-Path $sourceA "alpha.bin"), [byte[]]@(1, 2, 3, 4))
    [IO.File]::WriteAllBytes((Join-Path $sourceA "nested\beta.bin"), [byte[]]@(5, 6, 7))
    [IO.File]::WriteAllBytes((Join-Path $sourceB "nested\beta.bin"), [byte[]]@(5, 6, 7))
    [IO.File]::WriteAllBytes((Join-Path $sourceB "alpha.bin"), [byte[]]@(1, 2, 3, 4))

    $sourceHashA = Get-DspreContentFingerprint -RootPath $sourceA
    $sourceHashB = Get-DspreContentFingerprint -RootPath $sourceB
    if ($sourceHashA -ne $sourceHashB) {
        throw "Identical DSPRE trees under different absolute roots produced different fingerprints."
    }
    [IO.File]::WriteAllBytes((Join-Path $sourceB "alpha.bin"), [byte[]]@(1, 2, 3, 5))
    if ((Get-DspreContentFingerprint -RootPath $sourceB) -eq $sourceHashA) {
        throw "A same-length DSPRE content change did not alter the fingerprint."
    }
    [IO.File]::WriteAllBytes((Join-Path $sourceB "alpha.bin"), [byte[]]@(1, 2, 3, 4))
    Move-Item -LiteralPath (Join-Path $sourceB "nested\beta.bin") -Destination (Join-Path $sourceB "renamed.bin")
    if ((Get-DspreContentFingerprint -RootPath $sourceB) -eq $sourceHashA) {
        throw "A DSPRE relative-path change did not alter the fingerprint."
    }

    $toolA = Join-Path $fingerprintRoot "tool_a.bin"
    $toolB = Join-Path $fingerprintRoot "tool_b.bin"
    [IO.File]::WriteAllBytes($toolA, [byte[]]@(9, 8, 7))
    [IO.File]::WriteAllBytes($toolB, [byte[]]@(9, 8, 7))
    if ((Get-DspreToolFileFingerprint $toolA) -ne (Get-DspreToolFileFingerprint $toolB)) {
        throw "Tool fingerprints unexpectedly included the absolute file path."
    }
    [IO.File]::WriteAllBytes($toolB, [byte[]]@(9, 8, 6))
    if ((Get-DspreToolFileFingerprint $toolA) -eq (Get-DspreToolFileFingerprint $toolB)) {
        throw "A tool content change did not alter its fingerprint."
    }

    $resolutionA = Join-Path $fingerprintRoot "resolution_a.json"
    $resolutionB = Join-Path $fingerprintRoot "resolution_b.json"
    $resolutionTemplate = [pscustomobject][ordered]@{
        schema_version = 1
        generated_utc = "2000-01-01T00:00:00Z"
        source = [pscustomobject][ordered]@{
            dspre_contents = "C:\source_a"
            header_table_offset = "0xE56F0"
        }
        summary = [pscustomobject][ordered]@{ matrices = 1; ready_variants = 1 }
        variants = @([pscustomobject][ordered]@{
            matrix_id = 0
            variant = "matrix_0000"
            area_data_id = $null
            resolution = "per_cell_header"
        })
        overrides = @()
        unresolved = @()
    }
    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($resolutionA, ($resolutionTemplate | ConvertTo-Json -Depth 10), $utf8NoBom)
    $resolutionTemplate.generated_utc = "2030-01-01T00:00:00Z"
    $resolutionTemplate.source.dspre_contents = "D:\relocated\source_b"
    [IO.File]::WriteAllText($resolutionB, ($resolutionTemplate | ConvertTo-Json -Depth 10), $utf8NoBom)
    $resolutionHash = Get-DspreAreaResolutionFingerprint $resolutionA
    if ($resolutionHash -ne (Get-DspreAreaResolutionFingerprint $resolutionB)) {
        throw "Area resolution fingerprint included volatile time or absolute source paths."
    }
    $resolutionTemplate.variants[0].resolution = "linked_map_header"
    [IO.File]::WriteAllText($resolutionB, ($resolutionTemplate | ConvertTo-Json -Depth 10), $utf8NoBom)
    if ($resolutionHash -eq (Get-DspreAreaResolutionFingerprint $resolutionB)) {
        throw "An Area resolution semantic change did not alter its fingerprint."
    }
}
finally {
    if (Test-Path -LiteralPath $fingerprintRoot -PathType Container) {
        Remove-Item -LiteralPath $fingerprintRoot -Recurse -Force
    }
}

Write-Host "DSPRE collision support test complete."
Write-Host "  Packed attributes: OK"
Write-Host "  Packed BDHC:       OK"
Write-Host "  Manifest contract: OK"
Write-Host "  Invalid data:      OK"
Write-Host "  Source fingerprints: OK"
Write-Host "  Tool fingerprints:   OK"
