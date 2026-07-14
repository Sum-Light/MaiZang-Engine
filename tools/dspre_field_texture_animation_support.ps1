Set-StrictMode -Version Latest

$fieldFeatureSupportPath = Join-Path $PSScriptRoot "dspre_field_feature_support.ps1"
if (-not (Get-Command ConvertFrom-DspreNarcBytes -ErrorAction SilentlyContinue)) {
    . $fieldFeatureSupportPath
}

$script:DspreFieldTextureAnimationCount = 52
$script:DspreFieldTextureArchiveMemberCount = 53
$script:DspreFieldTextureRecordSize = 52
$script:DspreFieldTextureTimelineCapacity = 18
$script:DspreFieldTextureSourceFps = 30

function Get-DspreFieldTextureSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha256.ComputeHash($Bytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-DspreFieldTextureNsbtxMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,
        [Parameter(Mandatory)]
        [ValidateRange(1, 52)]
        [int]$MemberId,
        [int[]]$RequiredFrameIndices = @(),
        [string]$Label = "field texture animation"
    )

    if (
        $Bytes.Length -lt 28 -or
        [Text.Encoding]::ASCII.GetString($Bytes, 0, 4) -ne "BTX0" -or
        [BitConverter]::ToUInt16($Bytes, 4) -ne 0xFEFF -or
        [BitConverter]::ToUInt16($Bytes, 6) -ne 1 -or
        [BitConverter]::ToUInt32($Bytes, 8) -ne $Bytes.Length -or
        [BitConverter]::ToUInt16($Bytes, 12) -ne 16 -or
        [BitConverter]::ToUInt16($Bytes, 14) -ne 1
    ) {
        throw "$Label member $MemberId is not a supported BTX0 resource."
    }
    $blockOffset = [int][BitConverter]::ToUInt32($Bytes, 16)
    if (
        $blockOffset -ne 20 -or
        [Text.Encoding]::ASCII.GetString($Bytes, $blockOffset, 4) -ne "TEX0" -or
        [BitConverter]::ToUInt32($Bytes, $blockOffset + 4) -ne $Bytes.Length - $blockOffset
    ) {
        throw "$Label member $MemberId has an invalid TEX0 block."
    }

    $frameIndices = @($RequiredFrameIndices | Sort-Object -Unique)
    if (@($frameIndices | Where-Object { $_ -lt 0 -or $_ -ge 0xFF }).Count -ne 0) {
        throw "$Label member $MemberId has an invalid required frame index."
    }
    return [pscustomobject][ordered]@{
        member_id = $MemberId
        magic = "BTX0"
        source_format = "nsbtx"
        byte_length = $Bytes.Length
        sha256 = Get-DspreFieldTextureSha256 -Bytes $Bytes
        required_frame_indices = $frameIndices
        maximum_frame_index = if ($frameIndices.Count -eq 0) { $null } else { [int]$frameIndices[-1] }
    }
}

function ConvertFrom-DspreFieldTextureAnimationArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Archive,
        [string]$Label = "DSPRE field texture animations"
    )

    $members = @($Archive.members)
    if (
        [int]$Archive.schema_version -ne 1 -or
        [int]$Archive.member_count -ne $script:DspreFieldTextureArchiveMemberCount -or
        $members.Count -ne $script:DspreFieldTextureArchiveMemberCount
    ) {
        throw "$Label fldtanime must contain exactly 53 NARC members."
    }

    $table = [byte[]]$members[0]
    $expectedTableLength = 4 + $script:DspreFieldTextureAnimationCount * $script:DspreFieldTextureRecordSize
    if (
        $table.Length -ne $expectedTableLength -or
        [BitConverter]::ToUInt32($table, 0) -ne $script:DspreFieldTextureAnimationCount
    ) {
        throw "$Label member 0 must contain the 52-record animation table."
    }

    $animations = [Collections.Generic.List[object]]::new()
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $totalSequenceEntries = 0
    for ($animationId = 0; $animationId -lt $script:DspreFieldTextureAnimationCount; $animationId++) {
        $recordOffset = 4 + $animationId * $script:DspreFieldTextureRecordSize
        $nameBytes = New-Object byte[] 16
        [Buffer]::BlockCopy($table, $recordOffset, $nameBytes, 0, $nameBytes.Length)
        $nullOffset = [Array]::IndexOf($nameBytes, [byte]0)
        if ($nullOffset -le 0) {
            throw "$Label record $animationId has no non-empty null-terminated texture name."
        }
        for ($paddingOffset = $nullOffset; $paddingOffset -lt $nameBytes.Length; $paddingOffset++) {
            if ($nameBytes[$paddingOffset] -ne 0) {
                throw "$Label record $animationId has non-zero texture-name padding."
            }
        }
        $name = [Text.Encoding]::ASCII.GetString($nameBytes, 0, $nullOffset)
        if ($name -notmatch '^[A-Za-z0-9_.]+$' -or -not $names.Add($name)) {
            throw "$Label contains an invalid or duplicate texture name '$name'."
        }

        $sequence = [Collections.Generic.List[object]]::new()
        $foundTerminator = $false
        for ($sequenceIndex = 0; $sequenceIndex -lt $script:DspreFieldTextureTimelineCapacity; $sequenceIndex++) {
            $pairOffset = $recordOffset + 16 + 2 * $sequenceIndex
            $frameIndex = [int]$table[$pairOffset]
            $delayTicks = [int]$table[$pairOffset + 1]
            if ($frameIndex -eq 0xFF) {
                if ($delayTicks -ne 0xFF) {
                    throw "$Label record $animationId has a non-canonical timeline terminator."
                }
                $foundTerminator = $true
                for ($tailIndex = $sequenceIndex; $tailIndex -lt $script:DspreFieldTextureTimelineCapacity; $tailIndex++) {
                    $tailOffset = $recordOffset + 16 + 2 * $tailIndex
                    if ($table[$tailOffset] -ne 0xFF -or $table[$tailOffset + 1] -ne 0xFF) {
                        throw "$Label record $animationId has data after its timeline terminator."
                    }
                }
                break
            }
            $sequence.Add([pscustomobject][ordered]@{
                sequence_index = $sequenceIndex
                frame_index = $frameIndex
                delay_ticks = $delayTicks
                hold_ticks = $delayTicks + 1
            })
        }
        if (-not $foundTerminator -or $sequence.Count -eq 0) {
            throw "$Label record $animationId must contain a non-empty terminated timeline."
        }

        $memberId = $animationId + 1
        $requiredFrames = @($sequence | ForEach-Object { [int]$_.frame_index } | Sort-Object -Unique)
        $memberMetadata = Get-DspreFieldTextureNsbtxMetadata `
            -Bytes ([byte[]]$members[$memberId]) `
            -MemberId $memberId `
            -RequiredFrameIndices $requiredFrames `
            -Label $Label
        $cycleTicks = [int](($sequence | Measure-Object -Property hold_ticks -Sum).Sum)
        $animations.Add([pscustomobject][ordered]@{
            animation_id = $animationId
            texture_name = $name
            member_id = $memberId
            source_fps = $script:DspreFieldTextureSourceFps
            sequence_count = $sequence.Count
            sequence = @($sequence)
            unique_frame_indices = $requiredFrames
            cycle_ticks = $cycleTicks
            cycle_seconds = [Math]::Round($cycleTicks / [double]$script:DspreFieldTextureSourceFps, 8)
            member = $memberMetadata
        })
        $totalSequenceEntries += $sequence.Count
    }

    $descriptor = [pscustomobject][ordered]@{
        schema_version = 1
        source_fps = $script:DspreFieldTextureSourceFps
        archive_member_count = $script:DspreFieldTextureArchiveMemberCount
        animation_count = $animations.Count
        animations = @($animations)
        summary = [pscustomobject][ordered]@{
            animation_count = $animations.Count
            sequence_entries = $totalSequenceEntries
            nsbtx_members = $animations.Count
        }
    }
    $null = Assert-DspreFieldTextureAnimationDescriptor -Descriptor $descriptor -Label $Label
    return $descriptor
}

function Read-DspreFieldTextureAnimationDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$AllowedRoot,
        [string]$Label = "DSPRE field texture animations"
    )

    $archive = Read-DspreNarcArchive -Path $Path -AllowedRoot $AllowedRoot -Label "$Label fldtanime"
    return ConvertFrom-DspreFieldTextureAnimationArchive -Archive $archive -Label $Label
}

function Assert-DspreFieldTextureAnimationDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Descriptor,
        [string]$Label = "field texture animation descriptor"
    )

    if (
        [int]$Descriptor.schema_version -ne 1 -or
        [int]$Descriptor.source_fps -ne $script:DspreFieldTextureSourceFps -or
        [int]$Descriptor.archive_member_count -ne $script:DspreFieldTextureArchiveMemberCount -or
        [int]$Descriptor.animation_count -ne $script:DspreFieldTextureAnimationCount -or
        @($Descriptor.animations).Count -ne $script:DspreFieldTextureAnimationCount
    ) {
        throw "$Label has inconsistent top-level counts."
    }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $memberIds = [Collections.Generic.HashSet[int]]::new()
    $sequenceEntries = 0
    foreach ($animation in @($Descriptor.animations)) {
        $sequence = @($animation.sequence)
        if (
            [int]$animation.animation_id -lt 0 -or
            [int]$animation.animation_id -ge $script:DspreFieldTextureAnimationCount -or
            [int]$animation.member_id -ne [int]$animation.animation_id + 1 -or
            -not $memberIds.Add([int]$animation.member_id) -or
            [string]$animation.texture_name -notmatch '^[A-Za-z0-9_.]+$' -or
            -not $names.Add([string]$animation.texture_name) -or
            [int]$animation.source_fps -ne $script:DspreFieldTextureSourceFps -or
            [int]$animation.sequence_count -ne $sequence.Count -or
            $sequence.Count -lt 1 -or
            $sequence.Count -ge $script:DspreFieldTextureTimelineCapacity -or
            [string]$animation.member.magic -ne "BTX0" -or
            [string]$animation.member.source_format -ne "nsbtx" -or
            [int]$animation.member.member_id -ne [int]$animation.member_id
        ) {
            throw "$Label contains an invalid animation record."
        }
        $cycleTicks = 0
        for ($index = 0; $index -lt $sequence.Count; $index++) {
            $entry = $sequence[$index]
            if (
                [int]$entry.sequence_index -ne $index -or
                [int]$entry.frame_index -lt 0 -or
                [int]$entry.frame_index -ge 0xFF -or
                [int]$entry.delay_ticks -lt 0 -or
                [int]$entry.delay_ticks -ge 0xFF -or
                [int]$entry.hold_ticks -ne [int]$entry.delay_ticks + 1
            ) {
                throw "$Label contains an invalid timeline entry."
            }
            $cycleTicks += [int]$entry.hold_ticks
        }
        if (
            [int]$animation.cycle_ticks -ne $cycleTicks -or
            [Math]::Abs([double]$animation.cycle_seconds - $cycleTicks / 30.0) -gt 0.00000001
        ) {
            throw "$Label contains an invalid cycle duration."
        }
        $sequenceEntries += $sequence.Count
    }
    if (
        [int]$Descriptor.summary.animation_count -ne $script:DspreFieldTextureAnimationCount -or
        [int]$Descriptor.summary.nsbtx_members -ne $script:DspreFieldTextureAnimationCount -or
        [int]$Descriptor.summary.sequence_entries -ne $sequenceEntries
    ) {
        throw "$Label summary is inconsistent."
    }
    return [pscustomobject][ordered]@{
        animations = $script:DspreFieldTextureAnimationCount
        sequence_entries = $sequenceEntries
        source_fps = $script:DspreFieldTextureSourceFps
    }
}

function Resolve-DspreFieldTextureOutputPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedRoot,
        [string]$Label = "field texture output"
    )

    $root = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
    $fullPath = [IO.Path]::GetFullPath($Path)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label escaped its allowed root: $fullPath"
    }
    $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue
    if (
        $null -eq $rootItem -or
        -not $rootItem.PSIsContainer -or
        ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    ) {
        throw "$Label root is missing or unsafe: $root"
    }
    $parent = Split-Path $fullPath -Parent
    $relativeParent = $parent.Substring($root.Length).TrimStart('\', '/')
    $current = $root
    foreach ($component in @($relativeParent.Split(@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))) {
        $current = Join-Path $current $component
        if (-not (Test-Path -LiteralPath $current)) {
            $null = [IO.Directory]::CreateDirectory($current)
        }
        $item = Get-Item -LiteralPath $current -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label path contains an unsafe directory: $current"
        }
    }
    if (Test-Path -LiteralPath $fullPath) {
        $item = Get-Item -LiteralPath $fullPath -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label is not a replaceable regular file: $fullPath"
        }
    }
    return $fullPath
}

function Export-DspreFieldTextureAnimationMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Archive,
        [Parameter(Mandatory)]
        [ValidateRange(1, 52)]
        [int]$MemberId,
        [Parameter(Mandatory)]
        [string]$OutputPath,
        [string]$WorkRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) ".work")
    )

    $repositoryWorkRoot = [IO.Path]::GetFullPath(
        (Join-Path (Split-Path $PSScriptRoot -Parent) ".work")
    ).TrimEnd('\', '/')
    $workRootFull = [IO.Path]::GetFullPath($WorkRoot).TrimEnd('\', '/')
    $workPrefix = $repositoryWorkRoot + [IO.Path]::DirectorySeparatorChar
    if ($workRootFull -ne $repositoryWorkRoot -and -not $workRootFull.StartsWith(
        $workPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Field texture animation work root must remain under .work: $workRootFull"
    }
    if (-not (Test-Path -LiteralPath $repositoryWorkRoot)) {
        $null = [IO.Directory]::CreateDirectory($repositoryWorkRoot)
    }
    if (-not (Test-Path -LiteralPath $workRootFull)) {
        $relative = $workRootFull.Substring($repositoryWorkRoot.Length).TrimStart('\', '/')
        $current = $repositoryWorkRoot
        foreach ($component in @($relative.Split(@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))) {
            $current = Join-Path $current $component
            if (-not (Test-Path -LiteralPath $current)) {
                $null = [IO.Directory]::CreateDirectory($current)
            }
            $item = Get-Item -LiteralPath $current -Force
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Field texture animation work root contains an unsafe directory: $current"
            }
        }
    }
    $outputFull = Resolve-DspreFieldTextureOutputPath `
        -Path $OutputPath `
        -AllowedRoot $workRootFull `
        -Label "Field texture animation member"
    if ([IO.Path]::GetExtension($outputFull) -cne ".nsbtx") {
        throw "Field texture animation member $MemberId must use the .nsbtx extension."
    }
    $members = @($Archive.members)
    if (
        [int]$Archive.schema_version -ne 1 -or
        [int]$Archive.member_count -ne $script:DspreFieldTextureArchiveMemberCount -or
        $members.Count -ne $script:DspreFieldTextureArchiveMemberCount
    ) {
        throw "Field texture animation archive must contain exactly 53 members."
    }
    $bytes = [byte[]](Get-DspreNarcMemberBytes -Archive $Archive -MemberId $MemberId -Label "fldtanime")
    $metadata = Get-DspreFieldTextureNsbtxMetadata -Bytes $bytes -MemberId $MemberId
    $parent = Split-Path $outputFull -Parent
    $temporaryPath = Join-Path $parent (".{0}.{1}.tmp" -f [IO.Path]::GetFileName($outputFull), [Guid]::NewGuid().ToString("N"))
    try {
        [IO.File]::WriteAllBytes($temporaryPath, $bytes)
        Move-Item -LiteralPath $temporaryPath -Destination $outputFull -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
    return [pscustomobject][ordered]@{
        member_id = $MemberId
        path = $outputFull
        magic = [string]$metadata.magic
        source_format = [string]$metadata.source_format
        byte_length = [int]$metadata.byte_length
        sha256 = [string]$metadata.sha256
    }
}

function Assert-DspreFieldTextureRgbaImage {
    param($Image, [string]$Label = "field texture image")

    foreach ($property in @("width", "height", "rgba")) {
        if ($null -eq $Image.PSObject.Properties[$property]) {
            throw "$Label is missing '$property'."
        }
    }
    $width = [int]$Image.width
    $height = [int]$Image.height
    $rgba = [byte[]]$Image.rgba
    if ($width -lt 1 -or $height -lt 1 -or $rgba.Length -ne 4 * $width * $height) {
        throw "$Label has inconsistent RGBA dimensions."
    }
    return [pscustomobject]@{ width = $width; height = $height; rgba = $rgba }
}

function New-DspreFieldTextureRgbaImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(1, 16384)][int]$Width,
        [Parameter(Mandatory)][ValidateRange(1, 16384)][int]$Height,
        [Parameter(Mandatory)][byte[]]$Rgba
    )

    if ($Rgba.Length -ne 4 * $Width * $Height) {
        throw "RGBA byte length does not match $Width x $Height."
    }
    return [pscustomobject][ordered]@{
        schema_version = 1
        width = $Width
        height = $Height
        rgba = [byte[]]$Rgba.Clone()
        rgba_sha256 = Get-DspreFieldTextureSha256 -Bytes $Rgba
    }
}

function Get-DspreFieldTextureColorSet {
    param($Image)

    $validated = Assert-DspreFieldTextureRgbaImage -Image $Image
    $colors = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($offset = 0; $offset -lt $validated.rgba.Length; $offset += 4) {
        if ($validated.rgba[$offset + 3] -eq 0) {
            continue
        }
        $colorKey = "{0:x2}{1:x2}{2:x2}" -f @(
            $validated.rgba[$offset],
            $validated.rgba[$offset + 1],
            $validated.rgba[$offset + 2]
        )
        $null = $colors.Add($colorKey)
    }
    return @($colors | Sort-Object)
}

function New-DspreFieldTexturePalettePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$BaseImage,
        [Parameter(Mandatory)]$ReferenceFrame,
        [Parameter(Mandatory)][object[]]$FrameImages,
        [string]$Label = "field texture palette"
    )

    if ($FrameImages.Count -eq 0) {
        throw "$Label requires at least one animation frame."
    }
    $base = Assert-DspreFieldTextureRgbaImage -Image $BaseImage -Label "$Label base image"
    $reference = Assert-DspreFieldTextureRgbaImage -Image $ReferenceFrame -Label "$Label reference frame"
    $frames = [Collections.Generic.List[object]]::new()
    foreach ($frame in $FrameImages) {
        $frames.Add((Assert-DspreFieldTextureRgbaImage -Image $frame -Label "$Label animation frame"))
    }
    if ($base.width -ne $reference.width -or $base.height -ne $reference.height) {
        return [pscustomobject][ordered]@{
            schema_version = 1
            disposition = "unsupported_deferred"
            reason = "reference_dimensions_mismatch"
            color_map = @()
        }
    }
    foreach ($frame in $frames) {
        if ($frame.width -ne $reference.width -or $frame.height -ne $reference.height) {
            return [pscustomobject][ordered]@{
                schema_version = 1
                disposition = "unsupported_deferred"
                reason = "frame_dimensions_mismatch"
                color_map = @()
            }
        }
    }

    $sourceColors = @(Get-DspreFieldTextureColorSet -Image $ReferenceFrame)
    $baseColors = @(Get-DspreFieldTextureColorSet -Image $BaseImage)
    if ($sourceColors.Count -eq $baseColors.Count -and ($sourceColors -join ',') -ceq ($baseColors -join ',')) {
        return [pscustomobject][ordered]@{
            schema_version = 1
            disposition = "reuse_source_frames"
            reason = "visible_color_set_match"
            color_map = @()
        }
    }

    $mapping = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    for ($offset = 0; $offset -lt $reference.rgba.Length; $offset += 4) {
        $sourceAlpha = [int]$reference.rgba[$offset + 3]
        $baseAlpha = [int]$base.rgba[$offset + 3]
        if ($sourceAlpha -ne $baseAlpha) {
            return [pscustomobject][ordered]@{
                schema_version = 1
                disposition = "unsupported_deferred"
                reason = "alpha_layout_mismatch"
                color_map = @()
            }
        }
        if ($sourceAlpha -eq 0) {
            continue
        }
        $sourceKey = "{0:x2}{1:x2}{2:x2}" -f $reference.rgba[$offset], $reference.rgba[$offset + 1], $reference.rgba[$offset + 2]
        $targetKey = "{0:x2}{1:x2}{2:x2}" -f $base.rgba[$offset], $base.rgba[$offset + 1], $base.rgba[$offset + 2]
        if ($mapping.ContainsKey($sourceKey) -and $mapping[$sourceKey] -cne $targetKey) {
            return [pscustomobject][ordered]@{
                schema_version = 1
                disposition = "unsupported_deferred"
                reason = "ambiguous_color_mapping"
                color_map = @()
            }
        }
        $mapping[$sourceKey] = $targetKey
    }
    foreach ($frame in $frames) {
        for ($offset = 0; $offset -lt $frame.rgba.Length; $offset += 4) {
            if ($frame.rgba[$offset + 3] -eq 0) {
                continue
            }
            $sourceKey = "{0:x2}{1:x2}{2:x2}" -f $frame.rgba[$offset], $frame.rgba[$offset + 1], $frame.rgba[$offset + 2]
            if (-not $mapping.ContainsKey($sourceKey)) {
                return [pscustomobject][ordered]@{
                    schema_version = 1
                    disposition = "unsupported_deferred"
                    reason = "unmapped_frame_color"
                    color_map = @()
                }
            }
        }
    }
    $colorMap = @($mapping.Keys | Sort-Object | ForEach-Object {
        [pscustomobject][ordered]@{ source_rgb = $_; target_rgb = $mapping[$_] }
    })
    return [pscustomobject][ordered]@{
        schema_version = 1
        disposition = "recolor_frames"
        reason = "unique_coordinate_color_mapping"
        color_map = $colorMap
    }
}

function ConvertTo-DspreFieldTexturePaletteVariant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Image,
        [Parameter(Mandatory)]$PalettePlan
    )

    $validated = Assert-DspreFieldTextureRgbaImage -Image $Image
    $pixels = [byte[]]$validated.rgba.Clone()
    $disposition = [string]$PalettePlan.disposition
    if ($disposition -eq "reuse_source_frames") {
        return New-DspreFieldTextureRgbaImage -Width $validated.width -Height $validated.height -Rgba $pixels
    }
    if ($disposition -ne "recolor_frames") {
        throw "Cannot generate a palette variant from disposition '$disposition'."
    }
    $mapping = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($entry in @($PalettePlan.color_map)) {
        $source = [string]$entry.source_rgb
        $target = [string]$entry.target_rgb
        if ($source -notmatch '^[0-9a-f]{6}$' -or $target -notmatch '^[0-9a-f]{6}$' -or $mapping.ContainsKey($source)) {
            throw "Palette plan contains an invalid or duplicate color mapping."
        }
        $mapping.Add($source, $target)
    }
    for ($offset = 0; $offset -lt $pixels.Length; $offset += 4) {
        if ($pixels[$offset + 3] -eq 0) {
            continue
        }
        $sourceKey = "{0:x2}{1:x2}{2:x2}" -f $pixels[$offset], $pixels[$offset + 1], $pixels[$offset + 2]
        if (-not $mapping.ContainsKey($sourceKey)) {
            throw "Palette plan does not map animation color $sourceKey."
        }
        $target = $mapping[$sourceKey]
        $pixels[$offset] = [Convert]::ToByte($target.Substring(0, 2), 16)
        $pixels[$offset + 1] = [Convert]::ToByte($target.Substring(2, 2), 16)
        $pixels[$offset + 2] = [Convert]::ToByte($target.Substring(4, 2), 16)
    }
    return New-DspreFieldTextureRgbaImage -Width $validated.width -Height $validated.height -Rgba $pixels
}

function Read-DspreFieldTexturePng {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedRoot
    )

    Add-Type -AssemblyName System.Drawing
    $safePath = Resolve-DspreFieldInputFile -Path $Path -AllowedRoot $AllowedRoot -Label "Field texture PNG"
    $stream = [IO.File]::Open($safePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $bitmap = $null
    $data = $null
    try {
        $bitmap = [Drawing.Bitmap]::new($stream)
        $rectangle = [Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height)
        $data = $bitmap.LockBits($rectangle, [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $stride = [Math]::Abs($data.Stride)
        $raw = New-Object byte[] ($stride * $bitmap.Height)
        [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $raw, 0, $raw.Length)
        $rgba = New-Object byte[] (4 * $bitmap.Width * $bitmap.Height)
        for ($y = 0; $y -lt $bitmap.Height; $y++) {
            $sourceRow = if ($data.Stride -ge 0) { $y * $stride } else { ($bitmap.Height - 1 - $y) * $stride }
            for ($x = 0; $x -lt $bitmap.Width; $x++) {
                $sourceOffset = $sourceRow + 4 * $x
                $targetOffset = 4 * ($y * $bitmap.Width + $x)
                $rgba[$targetOffset] = $raw[$sourceOffset + 2]
                $rgba[$targetOffset + 1] = $raw[$sourceOffset + 1]
                $rgba[$targetOffset + 2] = $raw[$sourceOffset]
                $rgba[$targetOffset + 3] = $raw[$sourceOffset + 3]
            }
        }
        return New-DspreFieldTextureRgbaImage -Width $bitmap.Width -Height $bitmap.Height -Rgba $rgba
    }
    finally {
        if ($null -ne $data -and $null -ne $bitmap) { $bitmap.UnlockBits($data) }
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        $stream.Dispose()
    }
}

function Write-DspreFieldTexturePng {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Image,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedRoot
    )

    Add-Type -AssemblyName System.Drawing
    $validated = Assert-DspreFieldTextureRgbaImage -Image $Image
    $outputPath = Resolve-DspreFieldTextureOutputPath -Path $Path -AllowedRoot $AllowedRoot -Label "Field texture PNG"
    if ([IO.Path]::GetExtension($outputPath) -cne ".png") {
        throw "Field texture image output must use the .png extension."
    }
    $bitmap = [Drawing.Bitmap]::new($validated.width, $validated.height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $data = $null
    $temporaryPath = Join-Path (Split-Path $outputPath -Parent) (".{0}.{1}.tmp" -f [IO.Path]::GetFileName($outputPath), [Guid]::NewGuid().ToString("N"))
    try {
        $rectangle = [Drawing.Rectangle]::new(0, 0, $validated.width, $validated.height)
        $data = $bitmap.LockBits($rectangle, [Drawing.Imaging.ImageLockMode]::WriteOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $stride = [Math]::Abs($data.Stride)
        $raw = New-Object byte[] ($stride * $validated.height)
        for ($y = 0; $y -lt $validated.height; $y++) {
            $targetRow = if ($data.Stride -ge 0) { $y * $stride } else { ($validated.height - 1 - $y) * $stride }
            for ($x = 0; $x -lt $validated.width; $x++) {
                $sourceOffset = 4 * ($y * $validated.width + $x)
                $targetOffset = $targetRow + 4 * $x
                $raw[$targetOffset] = $validated.rgba[$sourceOffset + 2]
                $raw[$targetOffset + 1] = $validated.rgba[$sourceOffset + 1]
                $raw[$targetOffset + 2] = $validated.rgba[$sourceOffset]
                $raw[$targetOffset + 3] = $validated.rgba[$sourceOffset + 3]
            }
        }
        [Runtime.InteropServices.Marshal]::Copy($raw, 0, $data.Scan0, $raw.Length)
        $bitmap.UnlockBits($data)
        $data = $null
        $bitmap.Save($temporaryPath, [Drawing.Imaging.ImageFormat]::Png)
        Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
    }
    finally {
        if ($null -ne $data) { $bitmap.UnlockBits($data) }
        $bitmap.Dispose()
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
    $file = Get-Item -LiteralPath $outputPath
    return [pscustomobject][ordered]@{
        path = $outputPath
        width = $validated.width
        height = $validated.height
        byte_length = [long]$file.Length
        sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Assert-DspreFieldTextureByteRange {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][long]$Offset,
        [Parameter(Mandatory)][long]$Length,
        [string]$Label = "field texture bytes"
    )

    if ($Offset -lt 0 -or $Length -lt 0 -or $Offset -gt $Bytes.LongLength -or $Length -gt $Bytes.LongLength - $Offset) {
        throw "$Label range is outside its source buffer."
    }
}

function Get-DspreFieldTextureUInt16 {
    param([byte[]]$Bytes, [long]$Offset, [string]$Label)

    $null = Assert-DspreFieldTextureByteRange -Bytes $Bytes -Offset $Offset -Length 2 -Label $Label
    return [BitConverter]::ToUInt16($Bytes, [int]$Offset)
}

function Get-DspreFieldTextureUInt32 {
    param([byte[]]$Bytes, [long]$Offset, [string]$Label)

    $null = Assert-DspreFieldTextureByteRange -Bytes $Bytes -Offset $Offset -Length 4 -Label $Label
    return [BitConverter]::ToUInt32($Bytes, [int]$Offset)
}

function Copy-DspreFieldTextureBytes {
    param([byte[]]$Bytes, [long]$Offset, [long]$Length, [string]$Label)

    $null = Assert-DspreFieldTextureByteRange -Bytes $Bytes -Offset $Offset -Length $Length -Label $Label
    $copy = New-Object byte[] ([int]$Length)
    if ($Length -gt 0) {
        [Buffer]::BlockCopy($Bytes, [int]$Offset, $copy, 0, [int]$Length)
    }
    return $copy
}

function ConvertFrom-DspreFieldTextureNitroName {
    param([byte[]]$Bytes, [long]$Offset, [string]$Label)

    $nameBytes = [byte[]](Copy-DspreFieldTextureBytes -Bytes $Bytes -Offset $Offset -Length 16 -Label $Label)
    $length = 16
    while ($length -gt 0 -and $nameBytes[$length - 1] -eq 0) {
        $length--
    }
    if ($length -eq 0) {
        throw "$Label is empty."
    }
    for ($index = 0; $index -lt $length; $index++) {
        if ($nameBytes[$index] -lt 0x20 -or $nameBytes[$index] -gt 0x7E) {
            throw "$Label contains a non-printable byte."
        }
    }
    return [Text.Encoding]::ASCII.GetString($nameBytes, 0, $length)
}

function ConvertFrom-DspreFieldTextureInfoBlock {
    param(
        [byte[]]$Bytes,
        [long]$Offset,
        [ValidateSet(4, 8)][int]$DatumSize,
        [string]$Label
    )

    $null = Assert-DspreFieldTextureByteRange -Bytes $Bytes -Offset $Offset -Length 16 -Label $Label
    $dummy = [int]$Bytes[[int]$Offset]
    $count = [int]$Bytes[[int]$Offset + 1]
    $headerSize = [int](Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset ($Offset + 2) -Label $Label)
    $unknownSubheaderSize = [int](Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset ($Offset + 4) -Label $Label)
    $unknownSectionSize = [int](Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset ($Offset + 6) -Label $Label)
    $expectedHeaderSize = 16 + $count * (4 + $DatumSize + 16)
    if (
        $dummy -ne 0 -or
        $unknownSubheaderSize -ne 8 -or
        $unknownSectionSize -ne 12 + 4 * $count -or
        $headerSize -ne $expectedHeaderSize
    ) {
        throw "$Label has an invalid Nitro info-block header."
    }
    $null = Assert-DspreFieldTextureByteRange -Bytes $Bytes -Offset $Offset -Length $headerSize -Label $Label
    $sizeOffset = $Offset + 12 + 4 * $count
    $recordSize = [int](Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset $sizeOffset -Label $Label)
    $dataSectionSize = [int](Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset ($sizeOffset + 2) -Label $Label)
    if ($recordSize -ne $DatumSize -or $dataSectionSize -ne 4 + $DatumSize * $count) {
        throw "$Label has an invalid Nitro info-block data section."
    }
    $dataOffset = $sizeOffset + 4
    $namesOffset = $dataOffset + $DatumSize * $count
    $names = [Collections.Generic.List[string]]::new()
    $uniqueNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = 0; $index -lt $count; $index++) {
        $name = ConvertFrom-DspreFieldTextureNitroName `
            -Bytes $Bytes `
            -Offset ($namesOffset + 16 * $index) `
            -Label "$Label name $index"
        if (-not $uniqueNames.Add($name)) {
            throw "$Label contains duplicate name '$name'."
        }
        $names.Add($name)
    }
    return [pscustomobject][ordered]@{
        offset = [int]$Offset
        byte_length = $headerSize
        count = $count
        data_offset = [int]$dataOffset
        datum_size = $DatumSize
        names = @($names)
    }
}

function Get-DspreFieldTextureFormatName {
    param([ValidateRange(0, 7)][int]$Format)

    return @(
        "none",
        "a3i5",
        "palette4",
        "palette16",
        "palette256",
        "block4x4",
        "a5i3",
        "direct"
    )[$Format]
}

function Get-DspreFieldTextureDataByteLength {
    param(
        [ValidateRange(0, 7)][int]$Format,
        [ValidateRange(1, 1024)][int]$Width,
        [ValidateRange(1, 1024)][int]$Height
    )

    $bitsPerPixel = @(0, 8, 2, 4, 8, 2, 8, 16)[$Format]
    return [int](([long]$Width * $Height * $bitsPerPixel) / 8)
}

function ConvertFrom-DspreFieldTextureNsbtxBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [string]$Label = "field texture NSBTX"
    )

    if ($Bytes.Length -lt 80 -or [Text.Encoding]::ASCII.GetString($Bytes, 0, 4) -ne "BTX0") {
        throw "$Label is not a BTX0 container."
    }
    if (
        (Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset 4 -Label $Label) -ne 0xFEFF -or
        (Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset 6 -Label $Label) -ne 1 -or
        (Get-DspreFieldTextureUInt32 -Bytes $Bytes -Offset 8 -Label $Label) -ne $Bytes.Length -or
        (Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset 12 -Label $Label) -ne 16 -or
        (Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset 14 -Label $Label) -ne 1
    ) {
        throw "$Label has an invalid BTX0 header."
    }
    $sectionOffset = [int](Get-DspreFieldTextureUInt32 -Bytes $Bytes -Offset 16 -Label $Label)
    if ($sectionOffset -ne 20) {
        throw "$Label must contain one canonical TEX0 section at offset 20."
    }
    $null = Assert-DspreFieldTextureByteRange -Bytes $Bytes -Offset $sectionOffset -Length 60 -Label "$Label TEX0"
    if ([Text.Encoding]::ASCII.GetString($Bytes, $sectionOffset, 4) -ne "TEX0") {
        throw "$Label does not contain a TEX0 section."
    }
    $sectionSize = [int](Get-DspreFieldTextureUInt32 -Bytes $Bytes -Offset ($sectionOffset + 4) -Label "$Label TEX0")
    if ($sectionSize -ne $Bytes.Length - $sectionOffset -or $sectionSize -lt 60) {
        throw "$Label has an invalid TEX0 section size."
    }

    $regularLength = [int](Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset ($sectionOffset + 12) -Label "$Label TEX0") * 8
    $textureInfoRelative = [int](Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset ($sectionOffset + 14) -Label "$Label TEX0")
    $regularRelative = [int](Get-DspreFieldTextureUInt32 -Bytes $Bytes -Offset ($sectionOffset + 20) -Label "$Label TEX0")
    $compressedLength = [int](Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset ($sectionOffset + 28) -Label "$Label TEX0") * 8
    $compressedInfoRelative = [int](Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset ($sectionOffset + 30) -Label "$Label TEX0")
    $compressed1Relative = [int](Get-DspreFieldTextureUInt32 -Bytes $Bytes -Offset ($sectionOffset + 36) -Label "$Label TEX0")
    $compressed2Relative = [int](Get-DspreFieldTextureUInt32 -Bytes $Bytes -Offset ($sectionOffset + 40) -Label "$Label TEX0")
    $paletteLength = [int](Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset ($sectionOffset + 48) -Label "$Label TEX0") * 8
    $paletteInfoRelative = [int](Get-DspreFieldTextureUInt32 -Bytes $Bytes -Offset ($sectionOffset + 52) -Label "$Label TEX0")
    $paletteBlockRelative = [int](Get-DspreFieldTextureUInt32 -Bytes $Bytes -Offset ($sectionOffset + 56) -Label "$Label TEX0")
    foreach ($relative in @($textureInfoRelative, $compressedInfoRelative, $regularRelative, $compressed1Relative, $compressed2Relative, $paletteInfoRelative, $paletteBlockRelative)) {
        if ($relative -lt 60 -or $relative -gt $sectionSize) {
            throw "$Label has a TEX0 offset outside its section."
        }
    }

    $textureInfo = ConvertFrom-DspreFieldTextureInfoBlock `
        -Bytes $Bytes `
        -Offset ($sectionOffset + $textureInfoRelative) `
        -DatumSize 8 `
        -Label "$Label texture table"
    $paletteInfo = ConvertFrom-DspreFieldTextureInfoBlock `
        -Bytes $Bytes `
        -Offset ($sectionOffset + $paletteInfoRelative) `
        -DatumSize 4 `
        -Label "$Label palette table"
    $infoEnd = [Math]::Max(
        [int]$textureInfo.offset + [int]$textureInfo.byte_length,
        [int]$paletteInfo.offset + [int]$paletteInfo.byte_length
    )
    $dataStarts = [Collections.Generic.List[int]]::new()
    if ($regularLength -gt 0) { $dataStarts.Add($sectionOffset + $regularRelative) }
    if ($compressedLength -gt 0) {
        $dataStarts.Add($sectionOffset + $compressed1Relative)
        $dataStarts.Add($sectionOffset + $compressed2Relative)
    }
    if ($paletteLength -gt 0) { $dataStarts.Add($sectionOffset + $paletteBlockRelative) }
    if ($dataStarts.Count -gt 0 -and $infoEnd -gt ($dataStarts | Measure-Object -Minimum).Minimum) {
        throw "$Label has overlapping TEX0 tables and data blocks."
    }

    $null = Assert-DspreFieldTextureByteRange -Bytes $Bytes -Offset ($sectionOffset + $regularRelative) -Length $regularLength -Label "$Label regular texture block"
    $null = Assert-DspreFieldTextureByteRange -Bytes $Bytes -Offset ($sectionOffset + $compressed1Relative) -Length $compressedLength -Label "$Label compressed texture block"
    $null = Assert-DspreFieldTextureByteRange -Bytes $Bytes -Offset ($sectionOffset + $compressed2Relative) -Length ($compressedLength / 2) -Label "$Label compressed info block"
    $null = Assert-DspreFieldTextureByteRange -Bytes $Bytes -Offset ($sectionOffset + $paletteBlockRelative) -Length $paletteLength -Label "$Label palette block"

    $textures = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt [int]$textureInfo.count; $index++) {
        $recordOffset = [int]$textureInfo.data_offset + 8 * $index
        $params = [uint32](Get-DspreFieldTextureUInt32 -Bytes $Bytes -Offset $recordOffset -Label "$Label texture $index")
        $format = [int](($params -shr 26) -band 7)
        if ($format -eq 0) {
            throw "$Label texture $index uses unsupported format 0."
        }
        $width = [int](8 -shl (($params -shr 20) -band 7))
        $height = [int](8 -shl (($params -shr 23) -band 7))
        $dataLength = Get-DspreFieldTextureDataByteLength -Format $format -Width $width -Height $height
        $dataRelative = [int](($params -band 0xFFFF) * 8)
        if ($format -eq 5) {
            if ($dataRelative + $dataLength -gt $compressedLength) {
                throw "$Label texture $index exceeds the compressed texture block."
            }
            $data = [byte[]](Copy-DspreFieldTextureBytes `
                -Bytes $Bytes `
                -Offset ($sectionOffset + $compressed1Relative + $dataRelative) `
                -Length $dataLength `
                -Label "$Label texture $index texels")
            $data2 = [byte[]](Copy-DspreFieldTextureBytes `
                -Bytes $Bytes `
                -Offset ($sectionOffset + $compressed2Relative + $dataRelative / 2) `
                -Length ($dataLength / 2) `
                -Label "$Label texture $index compression info")
        }
        else {
            if ($dataRelative + $dataLength -gt $regularLength) {
                throw "$Label texture $index exceeds the regular texture block."
            }
            $data = [byte[]](Copy-DspreFieldTextureBytes `
                -Bytes $Bytes `
                -Offset ($sectionOffset + $regularRelative + $dataRelative) `
                -Length $dataLength `
                -Label "$Label texture $index texels")
            $data2 = [byte[]]@()
        }
        $textures.Add([pscustomobject][ordered]@{
            index = $index
            name = [string]$textureInfo.names[$index]
            params = [uint32]$params
            format = $format
            format_name = Get-DspreFieldTextureFormatName -Format $format
            width = $width
            height = $height
            color0_transparent = [bool](($params -shr 29) -band 1)
            data = $data
            data2 = $data2
            data_sha256 = Get-DspreFieldTextureSha256 -Bytes $data
            data2_sha256 = if ($data2.Length -eq 0) { $null } else { Get-DspreFieldTextureSha256 -Bytes $data2 }
        })
    }

    $paletteBlock = [byte[]](Copy-DspreFieldTextureBytes `
        -Bytes $Bytes `
        -Offset ($sectionOffset + $paletteBlockRelative) `
        -Length $paletteLength `
        -Label "$Label palette block")
    $paletteBlockSha256 = if ($paletteBlock.Length -eq 0) { $null } else { Get-DspreFieldTextureSha256 -Bytes $paletteBlock }
    $paletteOffsets = [Collections.Generic.List[int]]::new()
    for ($index = 0; $index -lt [int]$paletteInfo.count; $index++) {
        $recordOffset = [int]$paletteInfo.data_offset + 4 * $index
        $offset = [int](Get-DspreFieldTextureUInt16 -Bytes $Bytes -Offset $recordOffset -Label "$Label palette $index") * 8
        if ($offset -lt 0 -or $offset -ge $paletteLength -or ($offset % 2) -ne 0) {
            throw "$Label palette $index has an invalid palette-block offset."
        }
        $paletteOffsets.Add($offset)
    }
    $palettes = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $paletteOffsets.Count; $index++) {
        $offset = $paletteOffsets[$index]
        $end = $paletteLength
        foreach ($candidate in $paletteOffsets) {
            if ($candidate -gt $offset -and $candidate -lt $end) {
                $end = $candidate
            }
        }
        $colorCount = [int](($end - $offset) / 2)
        if ($colorCount -lt 1) {
            throw "$Label palette $index contains no colors."
        }
        $colors = New-Object uint16[] $colorCount
        for ($colorIndex = 0; $colorIndex -lt $colorCount; $colorIndex++) {
            $colors[$colorIndex] = [BitConverter]::ToUInt16($paletteBlock, $offset + 2 * $colorIndex)
        }
        $palettes.Add([pscustomobject][ordered]@{
            index = $index
            name = [string]$paletteInfo.names[$index]
            offset = $offset
            colors = [uint16[]]$colors
            palette_block = [byte[]]$paletteBlock.Clone()
            palette_block_sha256 = $paletteBlockSha256
        })
    }

    return [pscustomobject][ordered]@{
        schema_version = 1
        magic = "BTX0"
        source_format = "nsbtx"
        byte_length = $Bytes.Length
        sha256 = Get-DspreFieldTextureSha256 -Bytes $Bytes
        textures = @($textures)
        palettes = @($palettes)
    }
}

function Read-DspreFieldTextureNsbtx {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedRoot,
        [string]$Label = "field texture NSBTX"
    )

    $safePath = Resolve-DspreFieldInputFile -Path $Path -AllowedRoot $AllowedRoot -Label $Label
    return ConvertFrom-DspreFieldTextureNsbtxBytes `
        -Bytes ([IO.File]::ReadAllBytes($safePath)) `
        -Label $Label
}

function ConvertFrom-DspreFieldTextureTexelData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Texture,
        [AllowNull()]$Palette = $null,
        [string]$Label = "field texture"
    )

    foreach ($property in @("format", "width", "height", "data", "data_sha256")) {
        if ($null -eq $Texture.PSObject.Properties[$property]) {
            throw "$Label texture is missing '$property'."
        }
    }
    $format = [int]$Texture.format
    $width = [int]$Texture.width
    $height = [int]$Texture.height
    if ($format -lt 1 -or $format -gt 7 -or $width -lt 1 -or $width -gt 1024 -or $height -lt 1 -or $height -gt 1024) {
        throw "$Label texture has invalid format or dimensions."
    }
    $data = [byte[]]$Texture.data
    $expectedLength = Get-DspreFieldTextureDataByteLength -Format $format -Width $width -Height $height
    if ($data.Length -ne $expectedLength -or (Get-DspreFieldTextureSha256 -Bytes $data) -ne [string]$Texture.data_sha256) {
        throw "$Label texture texels do not match their declared length and hash."
    }
    $data2 = [byte[]]@()
    if ($format -eq 5) {
        if ($null -eq $Texture.PSObject.Properties["data2"] -or $null -eq $Texture.PSObject.Properties["data2_sha256"]) {
            throw "$Label compressed texture is missing its secondary data."
        }
        $data2 = [byte[]]$Texture.data2
        if (
            $data2.Length -ne $expectedLength / 2 -or
            (Get-DspreFieldTextureSha256 -Bytes $data2) -ne [string]$Texture.data2_sha256
        ) {
            throw "$Label compressed texture secondary data is invalid."
        }
    }

    $paletteRgba = [byte[]]@()
    $paletteColorCount = 0
    if ($format -ne 7) {
        if ($null -eq $Palette) {
            throw "$Label format $format requires a palette."
        }
        foreach ($property in @("offset", "palette_block", "palette_block_sha256")) {
            if ($null -eq $Palette.PSObject.Properties[$property]) {
                throw "$Label palette is missing '$property'."
            }
        }
        $paletteBlock = [byte[]]$Palette.palette_block
        $paletteOffset = [int]$Palette.offset
        if (
            $paletteBlock.Length -eq 0 -or
            (Get-DspreFieldTextureSha256 -Bytes $paletteBlock) -ne [string]$Palette.palette_block_sha256 -or
            $paletteOffset -lt 0 -or
            $paletteOffset -ge $paletteBlock.Length -or
            ($paletteOffset % 2) -ne 0
        ) {
            throw "$Label palette has invalid bytes, hash, or offset."
        }
        $paletteColorCount = [int](($paletteBlock.Length - $paletteOffset) / 2)
        $paletteRgba = New-Object byte[] (4 * $paletteColorCount)
        for ($index = 0; $index -lt $paletteColorCount; $index++) {
            $rgb555 = [int][BitConverter]::ToUInt16($paletteBlock, $paletteOffset + 2 * $index)
            $paletteRgba[4 * $index] = [byte]((($rgb555 -band 0x1F) -shl 3) -bor (($rgb555 -band 0x1F) -shr 2))
            $paletteRgba[4 * $index + 1] = [byte](((($rgb555 -shr 5) -band 0x1F) -shl 3) -bor ((($rgb555 -shr 5) -band 0x1F) -shr 2))
            $paletteRgba[4 * $index + 2] = [byte](((($rgb555 -shr 10) -band 0x1F) -shl 3) -bor ((($rgb555 -shr 10) -band 0x1F) -shr 2))
            $paletteRgba[4 * $index + 3] = 255
        }
    }

    $rgba = New-Object byte[] (4 * $width * $height)
    $transparent0 = $false
    if ($null -ne $Texture.PSObject.Properties["color0_transparent"]) {
        $transparent0 = [bool]$Texture.color0_transparent
    }
    $pixelIndex = 0
    switch ($format) {
        1 {
            foreach ($texel in $data) {
                $colorIndex = [int]($texel -band 0x1F)
                if ($colorIndex -ge $paletteColorCount) { throw "$Label A3I5 texel exceeds its palette." }
                $alpha3 = [int](($texel -shr 5) -band 7)
                $alpha5 = ($alpha3 -shl 2) -bor ($alpha3 -shr 1)
                $target = 4 * $pixelIndex++
                $source = 4 * $colorIndex
                $rgba[$target] = $paletteRgba[$source]
                $rgba[$target + 1] = $paletteRgba[$source + 1]
                $rgba[$target + 2] = $paletteRgba[$source + 2]
                $rgba[$target + 3] = [byte](($alpha5 -shl 3) -bor ($alpha5 -shr 2))
            }
        }
        2 {
            foreach ($packed in $data) {
                for ($shift = 0; $shift -lt 8; $shift += 2) {
                    $colorIndex = [int](($packed -shr $shift) -band 3)
                    if ($colorIndex -ge $paletteColorCount) { throw "$Label palette4 texel exceeds its palette." }
                    $target = 4 * $pixelIndex++
                    $source = 4 * $colorIndex
                    $rgba[$target] = $paletteRgba[$source]
                    $rgba[$target + 1] = $paletteRgba[$source + 1]
                    $rgba[$target + 2] = $paletteRgba[$source + 2]
                    $rgba[$target + 3] = if ($colorIndex -eq 0 -and $transparent0) { 0 } else { 255 }
                }
            }
        }
        3 {
            foreach ($packed in $data) {
                for ($shift = 0; $shift -lt 8; $shift += 4) {
                    $colorIndex = [int](($packed -shr $shift) -band 15)
                    if ($colorIndex -ge $paletteColorCount) { throw "$Label palette16 texel exceeds its palette." }
                    $target = 4 * $pixelIndex++
                    $source = 4 * $colorIndex
                    $rgba[$target] = $paletteRgba[$source]
                    $rgba[$target + 1] = $paletteRgba[$source + 1]
                    $rgba[$target + 2] = $paletteRgba[$source + 2]
                    $rgba[$target + 3] = if ($colorIndex -eq 0 -and $transparent0) { 0 } else { 255 }
                }
            }
        }
        4 {
            foreach ($texel in $data) {
                $colorIndex = [int]$texel
                if ($colorIndex -ge $paletteColorCount) { throw "$Label palette256 texel exceeds its palette." }
                $target = 4 * $pixelIndex++
                $source = 4 * $colorIndex
                $rgba[$target] = $paletteRgba[$source]
                $rgba[$target + 1] = $paletteRgba[$source + 1]
                $rgba[$target + 2] = $paletteRgba[$source + 2]
                $rgba[$target + 3] = if ($colorIndex -eq 0 -and $transparent0) { 0 } else { 255 }
            }
        }
        5 {
            $blocksX = [int]($width / 4)
            for ($y = 0; $y -lt $height; $y++) {
                for ($x = 0; $x -lt $width; $x++) {
                    $blockIndex = $blocksX * ($y -shr 2) + ($x -shr 2)
                    $block = [uint32][BitConverter]::ToUInt32($data, 4 * $blockIndex)
                    $extra = [int][BitConverter]::ToUInt16($data2, 2 * $blockIndex)
                    $shift = 2 * (4 * ($y % 4) + ($x % 4))
                    $texel = [int](($block -shr $shift) -band 3)
                    $mode = [int](($extra -shr 14) -band 3)
                    $paletteBase = [int](($extra -band 0x3FFF) -shl 1)
                    $requiredColors = if ($mode -eq 2) { 4 } elseif ($mode -eq 0) { 3 } else { 2 }
                    if ($paletteBase + $requiredColors -gt $paletteColorCount) {
                        throw "$Label block-compressed texel exceeds its palette."
                    }
                    $target = 4 * ($y * $width + $x)
                    if (($mode -eq 0 -or $mode -eq 1) -and $texel -eq 3) {
                        $rgba[$target] = 0
                        $rgba[$target + 1] = 0
                        $rgba[$target + 2] = 0
                        $rgba[$target + 3] = 0
                        continue
                    }
                    if ($mode -eq 1 -and $texel -eq 2) {
                        for ($channel = 0; $channel -lt 4; $channel++) {
                            $rgba[$target + $channel] = [byte][Math]::Floor(
                                ([int]$paletteRgba[4 * $paletteBase + $channel] + [int]$paletteRgba[4 * ($paletteBase + 1) + $channel]) / 2.0
                            )
                        }
                        continue
                    }
                    if ($mode -eq 3 -and $texel -ge 2) {
                        $first = if ($texel -eq 2) { $paletteBase + 1 } else { $paletteBase }
                        $second = if ($texel -eq 2) { $paletteBase } else { $paletteBase + 1 }
                        for ($channel = 0; $channel -lt 4; $channel++) {
                            $rgba[$target + $channel] = [byte][Math]::Floor(
                                (3 * [int]$paletteRgba[4 * $first + $channel] + 5 * [int]$paletteRgba[4 * $second + $channel]) / 8.0
                            )
                        }
                        continue
                    }
                    $colorIndex = $paletteBase + $texel
                    $source = 4 * $colorIndex
                    $rgba[$target] = $paletteRgba[$source]
                    $rgba[$target + 1] = $paletteRgba[$source + 1]
                    $rgba[$target + 2] = $paletteRgba[$source + 2]
                    $rgba[$target + 3] = $paletteRgba[$source + 3]
                }
            }
        }
        6 {
            foreach ($texel in $data) {
                $colorIndex = [int]($texel -band 7)
                if ($colorIndex -ge $paletteColorCount) { throw "$Label A5I3 texel exceeds its palette." }
                $alpha5 = [int](($texel -shr 3) -band 0x1F)
                $target = 4 * $pixelIndex++
                $source = 4 * $colorIndex
                $rgba[$target] = $paletteRgba[$source]
                $rgba[$target + 1] = $paletteRgba[$source + 1]
                $rgba[$target + 2] = $paletteRgba[$source + 2]
                $rgba[$target + 3] = [byte](($alpha5 -shl 3) -bor ($alpha5 -shr 2))
            }
        }
        7 {
            for ($index = 0; $index -lt $width * $height; $index++) {
                $texel = [int][BitConverter]::ToUInt16($data, 2 * $index)
                $red = $texel -band 0x1F
                $green = ($texel -shr 5) -band 0x1F
                $blue = ($texel -shr 10) -band 0x1F
                $target = 4 * $index
                $rgba[$target] = [byte](($red -shl 3) -bor ($red -shr 2))
                $rgba[$target + 1] = [byte](($green -shl 3) -bor ($green -shr 2))
                $rgba[$target + 2] = [byte](($blue -shl 3) -bor ($blue -shr 2))
                $rgba[$target + 3] = if (($texel -band 0x8000) -eq 0) { 0 } else { 255 }
            }
        }
    }
    return New-DspreFieldTextureRgbaImage -Width $width -Height $height -Rgba $rgba
}
