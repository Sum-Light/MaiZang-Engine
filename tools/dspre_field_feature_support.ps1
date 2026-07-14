Set-StrictMode -Version Latest

# These Warp records are rewritten by Platinum field scripts or dynamic-map code.
$script:DspreMutableWarpIds = @{
    33 = @(5)
    89 = "all"
    90 = "all"
    200 = @(0)
    215 = @(1, 2, 3, 4)
    217 = @(2, 3)
    268 = @(0, 1, 2, 3)
    269 = @(0, 1, 2, 3)
    271 = @(0, 1, 2, 3)
    272 = @(0, 1, 2, 3)
    273 = @(0, 1, 2, 3)
    294 = @(2, 3)
    316 = @(0, 1)
    334 = @(0, 1, 2, 3)
    336 = @(3, 4, 5, 6)
    340 = @(0, 1, 2, 3)
    380 = @(2, 3, 4)
    406 = @(4, 5)
    450 = @(0)
    518 = @(0, 1, 2, 3)
    519 = @(0, 1, 2, 3)
    520 = @(0, 1, 2, 3)
    521 = @(0, 1, 2, 3)
    522 = @(0, 1, 2, 3)
    523 = @(0, 1, 2, 3)
    524 = @(0, 1, 2, 3)
    525 = @(0, 1, 2, 3)
    526 = @(0, 1, 2, 3)
    527 = @(0, 1, 2, 3)
    528 = @(0, 1, 2, 3)
    529 = @(0, 1, 2, 3)
    530 = @(0, 1, 2, 3)
    531 = @(0, 1, 2, 3)
    532 = @(0, 1, 2, 3)
}

function Test-DspreMutableWarp {
    param([int]$HeaderId, [int]$WarpId)

    if (-not $script:DspreMutableWarpIds.ContainsKey($HeaderId)) {
        return $false
    }
    $selection = $script:DspreMutableWarpIds[$HeaderId]
    return $selection -eq "all" -or $WarpId -in @($selection)
}

function Get-DspreFieldU16 {
    param([byte[]]$Bytes, [int]$Offset, [string]$Label = "field data")

    if ($Offset -lt 0 -or $Offset + 2 -gt $Bytes.Length) {
        throw "$Label unsigned 16-bit read exceeds the data at offset $Offset."
    }
    return [int][BitConverter]::ToUInt16($Bytes, $Offset)
}

function Get-DspreFieldU32 {
    param([byte[]]$Bytes, [int]$Offset, [string]$Label = "field data")

    if ($Offset -lt 0 -or $Offset + 4 -gt $Bytes.Length) {
        throw "$Label unsigned 32-bit read exceeds the data at offset $Offset."
    }
    return [long][BitConverter]::ToUInt32($Bytes, $Offset)
}

function Resolve-DspreFieldInputFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$AllowedRoot,
        [string]$Label = "DSPRE field input"
    )

    $root = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
    $fullPath = [IO.Path]::GetFullPath($Path)
    $rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label escaped its allowed root: $fullPath"
    }

    $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue
    if ($null -eq $rootItem -or -not $rootItem.PSIsContainer) {
        throw "$Label root was not found: $root"
    }
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label root cannot be a reparse point: $root"
    }

    $relativePath = $fullPath.Substring($rootPrefix.Length)
    $components = @($relativePath.Split(
        @('\', '/'),
        [StringSplitOptions]::RemoveEmptyEntries
    ))
    if ($components.Count -eq 0) {
        throw "$Label must name a file below its allowed root."
    }

    $currentPath = $root
    for ($index = 0; $index -lt $components.Count; $index++) {
        $currentPath = Join-Path $currentPath $components[$index]
        $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            throw "$Label was not found: $currentPath"
        }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label path cannot contain a reparse point: $currentPath"
        }
        $isLast = $index -eq $components.Count - 1
        if ($isLast -and $item.PSIsContainer) {
            throw "$Label is not a file: $currentPath"
        }
        if (-not $isLast -and -not $item.PSIsContainer) {
            throw "$Label path contains a non-directory component: $currentPath"
        }
    }
    return $fullPath
}

function ConvertFrom-DspreNarcBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,
        [string]$Label = "NARC archive"
    )

    if ($Bytes.Length -lt 16 -or [Text.Encoding]::ASCII.GetString($Bytes, 0, 4) -ne "NARC") {
        throw "$Label is not a standard NARC archive."
    }
    if (
        (Get-DspreFieldU16 $Bytes 4 $Label) -ne 0xFFFE -or
        (Get-DspreFieldU16 $Bytes 6 $Label) -ne 0x0100 -or
        (Get-DspreFieldU32 $Bytes 8 $Label) -ne $Bytes.Length -or
        (Get-DspreFieldU16 $Bytes 12 $Label) -ne 16
    ) {
        throw "$Label has an unsupported byte order, version, size, or header."
    }

    $blockCount = Get-DspreFieldU16 $Bytes 14 $Label
    if ($blockCount -ne 3) {
        throw "$Label must contain exactly the FAT, name, and image blocks."
    }

    $blocks = @{}
    $offset = 16
    for ($index = 0; $index -lt $blockCount; $index++) {
        if ($offset + 8 -gt $Bytes.Length) {
            throw "$Label block $index header is truncated."
        }
        $magic = [Text.Encoding]::ASCII.GetString($Bytes, $offset, 4)
        $blockLength = [int](Get-DspreFieldU32 $Bytes ($offset + 4) $Label)
        if (
            $magic -notin @("BTAF", "BTNF", "GMIF") -or
            $blocks.ContainsKey($magic) -or
            $blockLength -lt 8 -or
            $offset + $blockLength -gt $Bytes.Length
        ) {
            throw "$Label contains an invalid or duplicate '$magic' block."
        }
        $blocks[$magic] = [pscustomobject]@{
            offset = $offset
            length = $blockLength
        }
        $offset += $blockLength
    }
    if ($offset -ne $Bytes.Length -or $blocks.Count -ne 3) {
        throw "$Label block lengths do not exactly cover the archive."
    }

    $fat = $blocks["BTAF"]
    $image = $blocks["GMIF"]
    if ($fat.length -lt 12 -or $image.length -lt 8) {
        throw "$Label FAT or image block is truncated."
    }
    $memberCount = Get-DspreFieldU16 $Bytes ($fat.offset + 8) $Label
    if ($fat.length -ne 12 + 8 * $memberCount) {
        throw "$Label FAT length does not match its member count."
    }

    $imageLength = $image.length - 8
    $imageOffset = $image.offset + 8
    $members = [Collections.Generic.List[object]]::new()
    $previousStart = 0L
    $previousEnd = 0L
    for ($index = 0; $index -lt $memberCount; $index++) {
        $entryOffset = $fat.offset + 12 + 8 * $index
        $start = Get-DspreFieldU32 $Bytes $entryOffset $Label
        $end = Get-DspreFieldU32 $Bytes ($entryOffset + 4) $Label
        if (
            $start -gt $end -or
            $end -gt $imageLength -or
            $start -lt $previousStart -or
            $end -lt $previousEnd
        ) {
            throw "$Label FAT member $index has invalid or unsorted bounds."
        }
        $memberBytes = New-Object byte[] ([int]($end - $start))
        if ($memberBytes.Length -gt 0) {
            [Buffer]::BlockCopy($Bytes, $imageOffset + [int]$start, $memberBytes, 0, $memberBytes.Length)
        }
        $members.Add($memberBytes)
        $previousStart = $start
        $previousEnd = $end
    }

    return [pscustomobject][ordered]@{
        schema_version = 1
        member_count = $memberCount
        members = @($members)
    }
}

function Read-DspreNarcArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$AllowedRoot,
        [string]$Label = "NARC archive"
    )

    $safePath = Resolve-DspreFieldInputFile -Path $Path -AllowedRoot $AllowedRoot -Label $Label
    return ConvertFrom-DspreNarcBytes -Bytes ([IO.File]::ReadAllBytes($safePath)) -Label $Label
}

function Get-DspreNarcMembers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$AllowedRoot,
        [string]$Label = "NARC archive"
    )

    $archive = Read-DspreNarcArchive -Path $Path -AllowedRoot $AllowedRoot -Label $Label
    Write-Output -NoEnumerate @($archive.members)
}

function Get-DspreNarcMemberBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Archive,
        [Parameter(Mandatory)]
        [ValidateRange(0, 0xFFFF)]
        [int]$MemberId,
        [string]$Label = "NARC archive"
    )

    $members = @($Archive.members)
    if ($MemberId -ge $members.Count) {
        throw "$Label does not contain member $MemberId."
    }
    Write-Output -NoEnumerate ([byte[]]$members[$MemberId])
}

function ConvertFrom-DspreZoneEventMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes,
        [ValidateRange(0, 0xFFFF)]
        [int]$ArchiveId = 0,
        [string]$Label = "zone_event member"
    )

    if ($Bytes.Length -eq 0) {
        return [pscustomobject][ordered]@{
            archive_id = $ArchiveId
            counts = [pscustomobject][ordered]@{ background = 0; object = 0; warp = 0; coordinate = 0 }
            warps = @()
        }
    }

    $offset = 0
    $sectionCounts = [ordered]@{}
    $warps = [Collections.Generic.List[object]]::new()
    $sections = @(
        [pscustomobject]@{ name = "background"; record_size = 20 },
        [pscustomobject]@{ name = "object"; record_size = 32 },
        [pscustomobject]@{ name = "warp"; record_size = 12 },
        [pscustomobject]@{ name = "coordinate"; record_size = 16 }
    )
    foreach ($section in $sections) {
        if ($offset + 4 -gt $Bytes.Length) {
            throw "$Label archive $ArchiveId is missing the $($section.name) count."
        }
        $count = Get-DspreFieldU32 $Bytes $offset "$Label archive $ArchiveId"
        $offset += 4
        $sectionLength = [long]$section.record_size * $count
        if ($count -gt 0x10000 -or $sectionLength -gt $Bytes.Length - $offset) {
            throw "$Label archive $ArchiveId has an invalid $($section.name) section length."
        }
        $sectionCounts[$section.name] = [int]$count
        if ($section.name -eq "warp") {
            for ($index = 0; $index -lt $count; $index++) {
                $recordOffset = $offset + $section.record_size * $index
                $warps.Add([pscustomobject][ordered]@{
                    warp_id = $index
                    x = Get-DspreFieldU16 $Bytes $recordOffset $Label
                    z = Get-DspreFieldU16 $Bytes ($recordOffset + 2) $Label
                    dest_header_id = Get-DspreFieldU16 $Bytes ($recordOffset + 4) $Label
                    dest_warp_id = Get-DspreFieldU16 $Bytes ($recordOffset + 6) $Label
                })
            }
        }
        $offset += [int]$sectionLength
    }
    if ($offset -ne $Bytes.Length) {
        throw "$Label archive $ArchiveId contains trailing bytes after its four sections."
    }

    return [pscustomobject][ordered]@{
        archive_id = $ArchiveId
        counts = [pscustomobject][ordered]@{
            background = $sectionCounts.background
            object = $sectionCounts.object
            warp = $sectionCounts.warp
            coordinate = $sectionCounts.coordinate
        }
        warps = @($warps)
    }
}

function ConvertFrom-DspreMapHeaderTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Arm9Bytes,
        [Parameter(Mandatory)]
        [long]$Offset,
        [Parameter(Mandatory)]
        [ValidateRange(1, 0xFFFF)]
        [int]$HeaderCount
    )

    $recordSize = 24L
    if ($Offset -lt 0 -or $Offset + $recordSize * $HeaderCount -gt $Arm9Bytes.Length) {
        throw "MapHeader table does not fit in ARM9."
    }
    $headers = New-Object object[] $HeaderCount
    for ($headerId = 0; $headerId -lt $HeaderCount; $headerId++) {
        $recordOffset = [int]($Offset + $recordSize * $headerId)
        $headers[$headerId] = [pscustomobject][ordered]@{
            id = $headerId
            area_data_id = [int]$Arm9Bytes[$recordOffset]
            matrix_id = Get-DspreFieldU16 $Arm9Bytes ($recordOffset + 2) "MapHeader $headerId"
            events_archive_id = Get-DspreFieldU16 $Arm9Bytes ($recordOffset + 16) "MapHeader $headerId"
            location_name_id = [int]$Arm9Bytes[$recordOffset + 18]
        }
    }
    return $headers
}

function Read-DspreFieldMatrixLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MatricesRoot,
        [Parameter(Mandatory)]
        [ValidateRange(0, 0xFFFF)]
        [int]$MatrixId
    )

    $path = Resolve-DspreFieldInputFile `
        -Path (Join-Path $MatricesRoot ("{0:D4}" -f $MatrixId)) `
        -AllowedRoot $MatricesRoot `
        -Label "Matrix $MatrixId"
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 5) {
        throw "Matrix $MatrixId is too short."
    }
    $width = [int]$bytes[0]
    $height = [int]$bytes[1]
    $hasHeaders = $bytes[2] -ne 0
    $hasHeights = $bytes[3] -ne 0
    $nameLength = [int]$bytes[4]
    $cellCount = $width * $height
    if ($width -eq 0 -or $height -eq 0 -or 5 + $nameLength -gt $bytes.Length) {
        throw "Matrix $MatrixId has invalid dimensions or name length."
    }
    $offset = 5 + $nameLength
    $headerIds = New-Object int[] $cellCount
    if ($hasHeaders) {
        if ($offset + 2 * $cellCount -gt $bytes.Length) {
            throw "Matrix $MatrixId header grid is truncated."
        }
        for ($index = 0; $index -lt $cellCount; $index++) {
            $headerIds[$index] = Get-DspreFieldU16 $bytes ($offset + 2 * $index) "Matrix $MatrixId"
        }
        $offset += 2 * $cellCount
    }
    if ($hasHeights) {
        if ($offset + $cellCount -gt $bytes.Length) {
            throw "Matrix $MatrixId height grid is truncated."
        }
        $offset += $cellCount
    }
    if ($offset + 2 * $cellCount -ne $bytes.Length) {
        throw "Matrix $MatrixId map grid does not exactly cover the file."
    }
    $mapIds = New-Object int[] $cellCount
    for ($index = 0; $index -lt $cellCount; $index++) {
        $mapIds[$index] = Get-DspreFieldU16 $bytes ($offset + 2 * $index) "Matrix $MatrixId"
    }

    return [pscustomobject][ordered]@{
        id = $MatrixId
        width = $width
        height = $height
        has_headers = $hasHeaders
        header_ids = $headerIds
        map_ids = $mapIds
    }
}

function Get-DspreFieldVariantName {
    param($Header, $Layout, [object[]]$Headers)

    if ($Layout.has_headers) {
        return "matrix_{0:D4}" -f [int]$Layout.id
    }
    $areaIds = @(
        $Headers |
            Where-Object { [int]$_.matrix_id -eq [int]$Layout.id } |
            ForEach-Object { [int]$_.area_data_id } |
            Sort-Object -Unique
    )
    if ($areaIds.Count -gt 1) {
        return "matrix_{0:D4}_area_{1:D4}" -f [int]$Layout.id, [int]$Header.area_data_id
    }
    return "matrix_{0:D4}" -f [int]$Layout.id
}

function Resolve-DspreWarpEndpoint {
    param(
        $Header,
        $Warp,
        [object[]]$Headers,
        [string]$MatricesRoot,
        [hashtable]$MatrixCache,
        [string]$Label
    )

    $matrixId = [int]$Header.matrix_id
    if (-not $MatrixCache.ContainsKey($matrixId)) {
        $MatrixCache[$matrixId] = Read-DspreFieldMatrixLayout -MatricesRoot $MatricesRoot -MatrixId $matrixId
    }
    $layout = $MatrixCache[$matrixId]
    $worldX = [int]$Warp.x
    $worldZ = [int]$Warp.z
    $cellX = [Math]::Floor($worldX / 32)
    $cellY = [Math]::Floor($worldZ / 32)
    if ($cellX -lt 0 -or $cellY -lt 0 -or $cellX -ge $layout.width -or $cellY -ge $layout.height) {
        throw "$Label lies outside matrix $matrixId at $worldX,$worldZ."
    }
    $cellIndex = $cellY * $layout.width + $cellX
    if ([int]$layout.map_ids[$cellIndex] -eq 0xFFFF) {
        throw "$Label lies in an unoccupied matrix $matrixId cell $cellX,$cellY."
    }
    if ($layout.has_headers -and [int]$layout.header_ids[$cellIndex] -ne [int]$Header.id) {
        throw "$Label header $($Header.id) does not own matrix $matrixId cell $cellX,$cellY."
    }

    return [pscustomobject][ordered]@{
        header_id = [int]$Header.id
        event_archive_id = [int]$Header.events_archive_id
        warp_id = [int]$Warp.warp_id
        matrix_id = $matrixId
        variant = Get-DspreFieldVariantName -Header $Header -Layout $layout -Headers $Headers
        cell = [pscustomobject][ordered]@{ x = [int]$cellX; y = [int]$cellY }
        tile = [pscustomobject][ordered]@{ x = $worldX % 32; y = $worldZ % 32 }
        world_tile = [pscustomobject][ordered]@{ x = $worldX; y = $worldZ }
    }
}

function ConvertTo-DspreWarpFieldFeatures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Headers,
        [Parameter(Mandatory)]
        $ZoneEventArchive,
        [Parameter(Mandatory)]
        [string]$MatricesRoot,
        [Parameter(Mandatory)]
        [ValidateRange(0, 0xFFFF)]
        [int]$MatrixId,
        [Parameter(Mandatory)]
        [string]$Variant,
        [AllowNull()]
        $AreaDataId = $null,
        [ValidateRange(-1, 0xFFFF)]
        [int]$DefaultHeaderId = -1,
        [Parameter(Mandatory)]
        [object[]]$Cells
    )

    if ([int]$ZoneEventArchive.schema_version -ne 1) {
        throw "Unsupported zone_event NARC schema."
    }
    $members = @($ZoneEventArchive.members)
    $eventsCache = @{}
    $matrixCache = @{}
    $currentLayout = Read-DspreFieldMatrixLayout -MatricesRoot $MatricesRoot -MatrixId $MatrixId
    $matrixCache[$MatrixId] = $currentLayout
    $headerIds = [Collections.Generic.HashSet[int]]::new()
    $cellsByKey = @{}
    foreach ($cell in $Cells) {
        $cellKey = "{0},{1}" -f [int]$cell.x, [int]$cell.y
        if ($cellsByKey.ContainsKey($cellKey)) {
            throw "Destination $Variant contains duplicate cell $cellKey."
        }
        $cellsByKey[$cellKey] = $cell
        if ($currentLayout.has_headers -and [int]$cell.header_id -ge 0) {
            $null = $headerIds.Add([int]$cell.header_id)
        }
    }
    if (-not $currentLayout.has_headers) {
        if ($null -eq $AreaDataId) {
            throw "Headerless destination $Variant requires its selected AreaData ID."
        }
        foreach ($header in $Headers) {
            if (
                [int]$header.matrix_id -eq $MatrixId -and
                [int]$header.area_data_id -eq [int]$AreaDataId
            ) {
                $null = $headerIds.Add([int]$header.id)
            }
        }
        if ($DefaultHeaderId -ge 0 -and -not $headerIds.Contains($DefaultHeaderId)) {
            throw "Headerless destination $Variant default Header $DefaultHeaderId is not linked to its Matrix/AreaData."
        }
    }
    elseif ($DefaultHeaderId -ge 0) {
        throw "Per-cell Header destination $Variant cannot declare a default Header."
    }

    $getEvents = {
        param($Header)
        $archiveId = [int]$Header.events_archive_id
        if ($archiveId -lt 0 -or $archiveId -ge $members.Count) {
            throw "Header $($Header.id) references missing zone_event member $archiveId."
        }
        if (-not $eventsCache.ContainsKey($archiveId)) {
            $eventsCache[$archiveId] = ConvertFrom-DspreZoneEventMember `
                -Bytes ([byte[]]$members[$archiveId]) `
                -ArchiveId $archiveId
        }
        return $eventsCache[$archiveId]
    }

    $warps = [Collections.Generic.List[object]]::new()
    foreach ($headerId in @($headerIds | Sort-Object)) {
        if ($headerId -lt 0 -or $headerId -ge $Headers.Count -or [int]$Headers[$headerId].id -ne $headerId) {
            throw "Destination $Variant references missing MapHeader $headerId."
        }
        $header = $Headers[$headerId]
        $events = & $getEvents $header
        foreach ($warp in @($events.warps)) {
            $source = Resolve-DspreWarpEndpoint `
                -Header $header `
                -Warp $warp `
                -Headers $Headers `
                -MatricesRoot $MatricesRoot `
                -MatrixCache $matrixCache `
                -Label "Header $headerId warp $($warp.warp_id)"
            if ([int]$source.matrix_id -ne $MatrixId -or [string]$source.variant -ne $Variant) {
                throw "Header $headerId warp $($warp.warp_id) resolved outside destination $Variant."
            }
            $cellKey = "{0},{1}" -f [int]$source.cell.x, [int]$source.cell.y
            if (
                -not $cellsByKey.ContainsKey($cellKey) -or
                ($currentLayout.has_headers -and [int]$cellsByKey[$cellKey].header_id -ne $headerId)
            ) {
                throw "Header $headerId warp $($warp.warp_id) source cell is not exported by $Variant."
            }
            $rawDestination = [pscustomobject][ordered]@{
                header_id = [int]$warp.dest_header_id
                warp_id = [int]$warp.dest_warp_id
            }
            if ([int]$warp.dest_warp_id -eq 0x100) {
                if ([int]$warp.dest_header_id -ne 0x0FFF) {
                    throw "Header $headerId warp $($warp.warp_id) special return must target header 0x0FFF."
                }
                $warps.Add([pscustomobject][ordered]@{
                    id = ("header_{0:D4}_warp_{1:D4}" -f $headerId, [int]$warp.warp_id)
                    kind = "special_return"
                    runtime_disposition = "fail_closed"
                    runtime_mutable = $false
                    mutable_reason = $null
                    source = $source
                    raw_destination = $rawDestination
                    destination = $null
                    reciprocal = $false
                })
                continue
            }

            $destinationHeaderId = [int]$warp.dest_header_id
            if ($destinationHeaderId -lt 0 -or $destinationHeaderId -ge $Headers.Count) {
                throw "Header $headerId warp $($warp.warp_id) targets missing MapHeader $destinationHeaderId."
            }
            $destinationHeader = $Headers[$destinationHeaderId]
            $destinationEvents = & $getEvents $destinationHeader
            $destinationWarpId = [int]$warp.dest_warp_id
            if ($destinationWarpId -lt 0 -or $destinationWarpId -ge @($destinationEvents.warps).Count) {
                throw "Header $headerId warp $($warp.warp_id) targets missing warp $destinationWarpId in header $destinationHeaderId."
            }
            $destinationWarp = @($destinationEvents.warps)[$destinationWarpId]
            $destination = Resolve-DspreWarpEndpoint `
                -Header $destinationHeader `
                -Warp $destinationWarp `
                -Headers $Headers `
                -MatricesRoot $MatricesRoot `
                -MatrixCache $matrixCache `
                -Label "Destination header $destinationHeaderId warp $destinationWarpId"
            $isReciprocal = (
                [int]$destinationWarp.dest_header_id -eq $headerId -and
                [int]$destinationWarp.dest_warp_id -eq [int]$warp.warp_id
            )
            $runtimeMutable = Test-DspreMutableWarp `
                -HeaderId $headerId `
                -WarpId ([int]$warp.warp_id)
            $warps.Add([pscustomobject][ordered]@{
                id = ("header_{0:D4}_warp_{1:D4}" -f $headerId, [int]$warp.warp_id)
                kind = "map_warp"
                runtime_disposition = if ($runtimeMutable) { "fail_closed_dynamic" } else { "ready" }
                runtime_mutable = $runtimeMutable
                mutable_reason = if ($runtimeMutable) { "platinum_script_or_dynamic_map" } else { $null }
                source = $source
                raw_destination = $rawDestination
                destination = $destination
                reciprocal = $isReciprocal
            })
        }
    }

    $ordinaryCount = @($warps | Where-Object { $_.kind -eq "map_warp" }).Count
    $specialCount = @($warps | Where-Object { $_.kind -eq "special_return" }).Count
    $dynamicCount = @($warps | Where-Object { [bool]$_.runtime_mutable }).Count
    $result = [pscustomobject][ordered]@{
        schema_version = 1
        source_selection = "first_warp_id_at_tile"
        default_header_id = if ($DefaultHeaderId -ge 0) { $DefaultHeaderId } else { $null }
        header_ids = @($headerIds | Sort-Object)
        warp_count = $warps.Count
        ordinary_warp_count = $ordinaryCount
        special_return_count = $specialCount
        dynamic_warp_count = $dynamicCount
        warps = @($warps)
    }
    $null = Assert-DspreFieldFeatures -FieldFeatures $result -Label "Destination $Variant field features"
    return $result
}

function Assert-DspreWarpEndpoint {
    param($Endpoint, [string]$Label)

    foreach ($name in @("header_id", "event_archive_id", "warp_id", "matrix_id", "variant", "cell", "tile", "world_tile")) {
        if ($null -eq $Endpoint.PSObject.Properties[$name]) {
            throw "$Label is missing '$name'."
        }
    }
    foreach ($value in @($Endpoint.header_id, $Endpoint.event_archive_id, $Endpoint.warp_id, $Endpoint.matrix_id)) {
        if ([long]$value -lt 0 -or [long]$value -gt 0xFFFF -or [double]$value -ne [long]$value) {
            throw "$Label contains an invalid unsigned 16-bit ID."
        }
    }
    if ([string]$Endpoint.variant -notmatch '^matrix_\d{4}(_area_\d{4})?$') {
        throw "$Label contains an unsafe destination variant."
    }
    foreach ($pointName in @("cell", "tile", "world_tile")) {
        $point = $Endpoint.$pointName
        if (
            $null -eq $point -or
            [double]$point.x -ne [long]$point.x -or
            [double]$point.y -ne [long]$point.y
        ) {
            throw "$Label has an invalid $pointName coordinate."
        }
    }
    if (
        [int]$Endpoint.cell.x -lt 0 -or
        [int]$Endpoint.cell.y -lt 0 -or
        [int]$Endpoint.tile.x -lt 0 -or
        [int]$Endpoint.tile.x -gt 31 -or
        [int]$Endpoint.tile.y -lt 0 -or
        [int]$Endpoint.tile.y -gt 31 -or
        [int]$Endpoint.world_tile.x -ne 32 * [int]$Endpoint.cell.x + [int]$Endpoint.tile.x -or
        [int]$Endpoint.world_tile.y -ne 32 * [int]$Endpoint.cell.y + [int]$Endpoint.tile.y
    ) {
        throw "$Label cell, tile, and world coordinates are inconsistent."
    }
    return $true
}

function Assert-DspreFieldFeatures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $FieldFeatures,
        [string]$Label = "DSPRE field features"
    )

    if ([int]$FieldFeatures.schema_version -ne 1) {
        throw "$Label must use schema 1."
    }
    $warps = @($FieldFeatures.warps)
    $ordinary = 0
    $special = 0
    $dynamic = 0
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ([string]$FieldFeatures.source_selection -ne "first_warp_id_at_tile") {
        throw "$Label must preserve the original first-Warp-at-tile lookup order."
    }
    $headerIds = [Collections.Generic.HashSet[int]]::new()
    foreach ($headerId in @($FieldFeatures.header_ids)) {
        if (
            [double]$headerId -ne [long]$headerId -or
            [long]$headerId -lt 0 -or
            [long]$headerId -gt 0xFFFF -or
            -not $headerIds.Add([int]$headerId)
        ) {
            throw "$Label contains an invalid or duplicate source Header ID."
        }
    }
    if ($null -ne $FieldFeatures.default_header_id) {
        if (
            [double]$FieldFeatures.default_header_id -ne [long]$FieldFeatures.default_header_id -or
            -not $headerIds.Contains([int]$FieldFeatures.default_header_id)
        ) {
            throw "$Label default Header is not present in its Header set."
        }
    }
    foreach ($warp in $warps) {
        $id = [string]$warp.id
        if ($id -notmatch '^header_\d{4}_warp_\d{4}$' -or -not $ids.Add($id)) {
            throw "$Label contains an invalid or duplicate warp ID: $id"
        }
        $null = Assert-DspreWarpEndpoint $warp.source "$Label warp $id source"
        if (-not $headerIds.Contains([int]$warp.source.header_id)) {
            throw "$Label warp $id source Header is not declared by the destination."
        }
        if (
            [int]$warp.raw_destination.header_id -lt 0 -or
            [int]$warp.raw_destination.header_id -gt 0xFFFF -or
            [int]$warp.raw_destination.warp_id -lt 0 -or
            [int]$warp.raw_destination.warp_id -gt 0xFFFF
        ) {
            throw "$Label warp $id contains an invalid raw destination."
        }
        if ([string]$warp.kind -eq "map_warp") {
            $ordinary++
            if ($warp.runtime_mutable -isnot [bool] -or $null -eq $warp.destination) {
                throw "$Label ordinary warp $id has an invalid runtime-mutability contract."
            }
            if ([bool]$warp.runtime_mutable) {
                $dynamic++
                if (
                    [string]$warp.runtime_disposition -ne "fail_closed_dynamic" -or
                    [string]$warp.mutable_reason -ne "platinum_script_or_dynamic_map"
                ) {
                    throw "$Label dynamic warp $id is not fail-closed."
                }
            }
            elseif (
                [string]$warp.runtime_disposition -ne "ready" -or
                $null -ne $warp.mutable_reason
            ) {
                throw "$Label static ordinary warp $id is not ready."
            }
            $null = Assert-DspreWarpEndpoint $warp.destination "$Label warp $id destination"
            if (
                [int]$warp.raw_destination.header_id -ne [int]$warp.destination.header_id -or
                [int]$warp.raw_destination.warp_id -ne [int]$warp.destination.warp_id -or
                $warp.reciprocal -isnot [bool]
            ) {
                throw "$Label ordinary warp $id does not match its resolved destination."
            }
        }
        elseif ([string]$warp.kind -eq "special_return") {
            $special++
            if (
                [string]$warp.runtime_disposition -ne "fail_closed" -or
                $null -ne $warp.destination -or
                [int]$warp.raw_destination.header_id -ne 0x0FFF -or
                [int]$warp.raw_destination.warp_id -ne 0x100 -or
                $warp.runtime_mutable -isnot [bool] -or
                [bool]$warp.runtime_mutable -or
                $null -ne $warp.mutable_reason -or
                $warp.reciprocal -isnot [bool] -or
                [bool]$warp.reciprocal
            ) {
                throw "$Label special return $id does not preserve the fail-closed contract."
            }
        }
        else {
            throw "$Label warp $id has unsupported kind '$($warp.kind)'."
        }
    }
    if (
        [int]$FieldFeatures.warp_count -ne $warps.Count -or
        [int]$FieldFeatures.ordinary_warp_count -ne $ordinary -or
        [int]$FieldFeatures.special_return_count -ne $special -or
        [int]$FieldFeatures.dynamic_warp_count -ne $dynamic
    ) {
        throw "$Label warp summary is inconsistent."
    }
    return [pscustomobject]@{
        warps = $warps.Count
        ordinary_warps = $ordinary
        special_returns = $special
        dynamic_warps = $dynamic
    }
}
