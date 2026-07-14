[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "dspre_field_feature_support.ps1")

function Assert-Throws {
    param([scriptblock]$Action, [string]$Label)

    try {
        & $Action
    }
    catch {
        return
    }
    throw "Expected failure was not raised: $Label"
}

function New-ZoneEventMember {
    param([object[]]$Warps = @())

    $stream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint32]0) # Background events are intentionally excluded.
        $writer.Write([uint32]0) # Object events/NPCs are intentionally excluded.
        $writer.Write([uint32]$Warps.Count)
        foreach ($warp in $Warps) {
            $writer.Write([uint16]$warp.x)
            $writer.Write([uint16]$warp.z)
            $writer.Write([uint16]$warp.dest_header_id)
            $writer.Write([uint16]$warp.dest_warp_id)
            $writer.Write([uint32]0)
        }
        $writer.Write([uint32]0) # Coordinate events are not exported yet.
        $writer.Flush()
        Write-Output -NoEnumerate $stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function New-SyntheticNarc {
    param([object[]]$Members)

    $imageStream = [IO.MemoryStream]::new()
    $fatEntries = [Collections.Generic.List[object]]::new()
    try {
        foreach ($member in $Members) {
            $memberBytes = [byte[]]$member
            $start = $imageStream.Length
            $imageStream.Write($memberBytes, 0, $memberBytes.Length)
            $fatEntries.Add([pscustomobject]@{ start = $start; end = $imageStream.Length })
        }
        $imageBytes = $imageStream.ToArray()
    }
    finally {
        $imageStream.Dispose()
    }

    $fatLength = 12 + 8 * $Members.Count
    $nameLength = 16
    $imageLength = 8 + $imageBytes.Length
    $totalLength = 16 + $fatLength + $nameLength + $imageLength
    $stream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes("NARC"))
        $writer.Write([uint16]0xFFFE)
        $writer.Write([uint16]0x0100)
        $writer.Write([uint32]$totalLength)
        $writer.Write([uint16]16)
        $writer.Write([uint16]3)

        $writer.Write([Text.Encoding]::ASCII.GetBytes("BTAF"))
        $writer.Write([uint32]$fatLength)
        $writer.Write([uint16]$Members.Count)
        $writer.Write([uint16]0)
        foreach ($entry in $fatEntries) {
            $writer.Write([uint32]$entry.start)
            $writer.Write([uint32]$entry.end)
        }

        $writer.Write([Text.Encoding]::ASCII.GetBytes("BTNF"))
        $writer.Write([uint32]$nameLength)
        $writer.Write((New-Object byte[] 8))

        $writer.Write([Text.Encoding]::ASCII.GetBytes("GMIF"))
        $writer.Write([uint32]$imageLength)
        $writer.Write($imageBytes)
        $writer.Flush()
        Write-Output -NoEnumerate $stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Write-SyntheticMatrix {
    param(
        [string]$Root,
        [int]$Id,
        [int]$Width,
        [int]$Height,
        [AllowNull()]
        [int[]]$HeaderIds,
        [int[]]$MapIds
    )

    $cellCount = $Width * $Height
    if ($MapIds.Count -ne $cellCount -or ($null -ne $HeaderIds -and $HeaderIds.Count -ne $cellCount)) {
        throw "Synthetic matrix arrays have inconsistent sizes."
    }
    $stream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([byte]$Width)
        $writer.Write([byte]$Height)
        $writer.Write([byte]($null -ne $HeaderIds))
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        if ($null -ne $HeaderIds) {
            foreach ($headerId in $HeaderIds) {
                $writer.Write([uint16]$headerId)
            }
        }
        foreach ($mapId in $MapIds) {
            $writer.Write([uint16]$mapId)
        }
        $writer.Flush()
        [IO.File]::WriteAllBytes((Join-Path $Root ("{0:D4}" -f $Id)), $stream.ToArray())
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

$testRoot = Join-Path (Split-Path -Parent $PSScriptRoot) ".work\field_feature_support_test"
if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $testRoot -Force
$matricesRoot = Join-Path $testRoot "matrices"
$null = New-Item -ItemType Directory -Path $matricesRoot -Force

try {
    $sourceMember = New-ZoneEventMember -Warps @(
        [pscustomobject]@{ x = 5; z = 6; dest_header_id = 2; dest_warp_id = 0 },
        [pscustomobject]@{ x = 5; z = 6; dest_header_id = 2; dest_warp_id = 0 }
    )
    $destinationMember = New-ZoneEventMember -Warps @(
        [pscustomobject]@{ x = 3; z = 4; dest_header_id = 0; dest_warp_id = 0 }
    )
    $specialMember = New-ZoneEventMember -Warps @(
        [pscustomobject]@{ x = 33; z = 7; dest_header_id = 0x0FFF; dest_warp_id = 0x100 }
    )
    $sharedHeaderMember = New-ZoneEventMember -Warps @(
        [pscustomobject]@{ x = 7; z = 8; dest_header_id = 0x0FFF; dest_warp_id = 0x100 }
    )
    $narcBytes = New-SyntheticNarc -Members @(
        $sourceMember,
        $destinationMember,
        $specialMember,
        $sharedHeaderMember
    )
    $narcPath = Join-Path $testRoot "zone_event.narc"
    [IO.File]::WriteAllBytes($narcPath, $narcBytes)

    $archive = Read-DspreNarcArchive -Path $narcPath -AllowedRoot $testRoot
    if ([int]$archive.member_count -ne 4 -or @($archive.members).Count -ne 4) {
        throw "Synthetic NARC member count was not preserved."
    }
    $memberList = Get-DspreNarcMembers -Path $narcPath -AllowedRoot $testRoot
    if (@($memberList).Count -ne 4) {
        throw "Reusable NARC member API changed the member count."
    }
    $firstMember = Get-DspreNarcMemberBytes -Archive $archive -MemberId 0
    if ($firstMember.Length -ne $sourceMember.Length) {
        throw "Reusable NARC member lookup changed the member bytes."
    }
    Assert-Throws {
        Get-DspreNarcMemberBytes -Archive $archive -MemberId 4
    } "NARC member index bounds"

    $badNarc = [byte[]]$narcBytes.Clone()
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]($badNarc.Length - 1)), 0, $badNarc, 8, 4)
    Assert-Throws {
        ConvertFrom-DspreNarcBytes -Bytes $badNarc
    } "NARC declared-size mismatch"

    $trailingEvent = New-Object byte[] ($sourceMember.Length + 1)
    [Buffer]::BlockCopy($sourceMember, 0, $trailingEvent, 0, $sourceMember.Length)
    Assert-Throws {
        ConvertFrom-DspreZoneEventMember -Bytes $trailingEvent -ArchiveId 0
    } "zone_event trailing bytes"
    $emptyEvents = ConvertFrom-DspreZoneEventMember -Bytes (New-Object byte[] 0) -ArchiveId 9
    if ([int]$emptyEvents.counts.warp -ne 0) {
        throw "An empty zone_event member did not remain empty."
    }

    $arm9 = New-Object byte[] (32 + 4 * 24)
    $eventArchiveIds = @(0, 2, 1, 3)
    $areaDataIds = @(1, 2, 3, 3)
    for ($headerId = 0; $headerId -lt 4; $headerId++) {
        $offset = 32 + 24 * $headerId
        $arm9[$offset] = [byte]$areaDataIds[$headerId]
        [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]$(if ($headerId -ge 2) { 1 } else { 0 })), 0, $arm9, $offset + 2, 2)
        [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]$eventArchiveIds[$headerId]), 0, $arm9, $offset + 16, 2)
        $arm9[$offset + 18] = [byte](10 + $headerId)
    }
    $headers = @(ConvertFrom-DspreMapHeaderTable -Arm9Bytes $arm9 -Offset 32 -HeaderCount 4)
    if ([int]$headers[2].events_archive_id -ne 1 -or [int]$headers[2].matrix_id -ne 1) {
        throw "MapHeader eventsArchiveID was not read from byte offset +16."
    }

    Write-SyntheticMatrix -Root $matricesRoot -Id 0 -Width 2 -Height 1 -HeaderIds @(0, 1) -MapIds @(10, 11)
    Write-SyntheticMatrix -Root $matricesRoot -Id 1 -Width 1 -Height 1 -HeaderIds $null -MapIds @(20)
    $cells = @(
        [pscustomobject]@{ x = 0; y = 0; header_id = 0; map_id = 10 },
        [pscustomobject]@{ x = 1; y = 0; header_id = 1; map_id = 11 }
    )
    $features = ConvertTo-DspreWarpFieldFeatures `
        -Headers $headers `
        -ZoneEventArchive $archive `
        -MatricesRoot $matricesRoot `
        -MatrixId 0 `
        -Variant "matrix_0000" `
        -Cells $cells
    if (
        [int]$features.warp_count -ne 3 -or
        [int]$features.ordinary_warp_count -ne 2 -or
        [int]$features.special_return_count -ne 1 -or
        [int]$features.dynamic_warp_count -ne 0
    ) {
        throw "Warp feature summary is inconsistent."
    }
    $ordinary = @($features.warps | Where-Object { $_.kind -eq "map_warp" })[0]
    if (
        [string]$ordinary.runtime_disposition -ne "ready" -or
        [int]$ordinary.source.header_id -ne 0 -or
        [int]$ordinary.source.cell.x -ne 0 -or
        [int]$ordinary.source.tile.x -ne 5 -or
        [int]$ordinary.destination.header_id -ne 2 -or
        [int]$ordinary.destination.matrix_id -ne 1 -or
        [string]$ordinary.destination.variant -ne "matrix_0001" -or
        [int]$ordinary.destination.tile.x -ne 3 -or
        -not [bool]$ordinary.reciprocal
    ) {
        throw "Ordinary Warp endpoints were not resolved in both directions."
    }
    $special = @($features.warps | Where-Object { $_.kind -eq "special_return" })[0]
    if (
        [string]$special.runtime_disposition -ne "fail_closed" -or
        $null -ne $special.destination -or
        [int]$special.raw_destination.header_id -ne 0x0FFF -or
        [int]$special.raw_destination.warp_id -ne 0x100
    ) {
        throw "Special-return Warp did not preserve its fail-closed contract."
    }
    $validation = Assert-DspreFieldFeatures -FieldFeatures $features
    if (
        [int]$validation.warps -ne 3 -or
        [string]$features.source_selection -ne "first_warp_id_at_tile" -or
        $null -ne $features.default_header_id -or
        @($features.header_ids).Count -ne 2
    ) {
        throw "Field-feature validation did not return its checked Warp count."
    }
    if (
        -not (Test-DspreMutableWarp -HeaderId 33 -WarpId 5) -or
        (Test-DspreMutableWarp -HeaderId 33 -WarpId 4) -or
        -not (Test-DspreMutableWarp -HeaderId 89 -WarpId 0)
    ) {
        throw "Platinum runtime-mutable Warp metadata is incomplete."
    }

    $sharedFeatures = ConvertTo-DspreWarpFieldFeatures `
        -Headers $headers `
        -ZoneEventArchive $archive `
        -MatricesRoot $matricesRoot `
        -MatrixId 1 `
        -Variant "matrix_0001" `
        -AreaDataId 3 `
        -DefaultHeaderId 2 `
        -Cells @([pscustomobject]@{ x = 0; y = 0; header_id = 2; map_id = 20 })
    if (
        [int]$sharedFeatures.default_header_id -ne 2 -or
        (@($sharedFeatures.header_ids) -join ',') -ne '2,3' -or
        [int]$sharedFeatures.warp_count -ne 2 -or
        @($sharedFeatures.warps | Where-Object { [int]$_.source.header_id -eq 3 }).Count -ne 1
    ) {
        throw "Headerless destination did not export every same-Matrix/AreaData Header."
    }

    $badFeatures = $features | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $badFeatures.warps[0].destination.tile.x = 32
    Assert-Throws {
        Assert-DspreFieldFeatures -FieldFeatures $badFeatures
    } "resolved Warp tile range"
    $badSpecial = $features | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $specialIndex = @($badSpecial.warps).Count - 1
    $badSpecial.warps[$specialIndex].runtime_disposition = "ready"
    Assert-Throws {
        Assert-DspreFieldFeatures -FieldFeatures $badSpecial
    } "special-return runtime disposition"

    $outsideRoot = Join-Path $testRoot "outside"
    $null = New-Item -ItemType Directory -Path $outsideRoot
    [IO.File]::WriteAllBytes((Join-Path $outsideRoot "linked.narc"), $narcBytes)
    $junctionPath = Join-Path $testRoot "linked"
    $null = New-Item -ItemType Junction -Path $junctionPath -Target $outsideRoot
    try {
        Assert-Throws {
            Read-DspreNarcArchive `
                -Path (Join-Path $junctionPath "linked.narc") `
                -AllowedRoot $testRoot
        } "NARC ancestor junction"
    }
    finally {
        [IO.Directory]::Delete($junctionPath, $false)
    }

    Write-Host (ConvertTo-Json ([ordered]@{
        narc_members = [int]$archive.member_count
        warp_events = [int]$features.warp_count
        ordinary_warps = [int]$features.ordinary_warp_count
        special_returns = [int]$features.special_return_count
        dynamic_warps = [int]$features.dynamic_warp_count
        npc_events_exported = 0
    }) -Compress)
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
