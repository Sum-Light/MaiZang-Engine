[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "dspre_field_texture_animation_support.ps1")

function Assert-Throws {
    param([scriptblock]$Action, [string]$Label)

    try { & $Action }
    catch { return }
    throw "Expected failure was not raised: $Label"
}

function New-SyntheticNarcBytes {
    param([object[]]$Members)

    $imageStream = [IO.MemoryStream]::new()
    $entries = [Collections.Generic.List[object]]::new()
    try {
        foreach ($member in $Members) {
            $bytes = [byte[]]$member
            $start = $imageStream.Length
            $imageStream.Write($bytes, 0, $bytes.Length)
            $entries.Add([pscustomobject]@{ start = $start; end = $imageStream.Length })
        }
        $imageBytes = $imageStream.ToArray()
    }
    finally { $imageStream.Dispose() }

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
        foreach ($entry in $entries) {
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

function New-SyntheticNsbtx {
    param([byte]$Payload = 0)

    $bytes = New-Object byte[] 32
    [Buffer]::BlockCopy([Text.Encoding]::ASCII.GetBytes("BTX0"), 0, $bytes, 0, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]0xFEFF), 0, $bytes, 4, 2)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]1), 0, $bytes, 6, 2)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]$bytes.Length), 0, $bytes, 8, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]16), 0, $bytes, 12, 2)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]1), 0, $bytes, 14, 2)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]20), 0, $bytes, 16, 4)
    [Buffer]::BlockCopy([Text.Encoding]::ASCII.GetBytes("TEX0"), 0, $bytes, 20, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]12), 0, $bytes, 24, 4)
    $bytes[28] = $Payload
    return $bytes
}

function New-AnimationTable {
    $table = New-Object byte[] (4 + 52 * 52)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]52), 0, $table, 0, 4)
    for ($animationId = 0; $animationId -lt 52; $animationId++) {
        $offset = 4 + 52 * $animationId
        $name = if ($animationId -eq 0) { "sea" } elseif ($animationId -eq 1) { "rhana" } else { "anim{0:D2}" -f $animationId }
        $nameBytes = [Text.Encoding]::ASCII.GetBytes($name)
        [Buffer]::BlockCopy($nameBytes, 0, $table, $offset, $nameBytes.Length)
        for ($pair = 0; $pair -lt 18; $pair++) {
            $table[$offset + 16 + 2 * $pair] = 0xFF
            $table[$offset + 17 + 2 * $pair] = 0xFF
        }
        $timeline = if ($animationId -eq 0) {
            @(0, 1, 2, 3, 4, 5, 6, 7 | ForEach-Object { [pscustomobject]@{ frame = $_; delay = 9 } })
        }
        elseif ($animationId -eq 1) {
            @(
                [pscustomobject]@{ frame = 0; delay = 16 },
                [pscustomobject]@{ frame = 1; delay = 16 },
                [pscustomobject]@{ frame = 2; delay = 16 },
                [pscustomobject]@{ frame = 1; delay = 16 }
            )
        }
        else { @([pscustomobject]@{ frame = 0; delay = 9 }) }
        $timeline = @($timeline)
        for ($pair = 0; $pair -lt $timeline.Count; $pair++) {
            $table[$offset + 16 + 2 * $pair] = [byte]$timeline[$pair].frame
            $table[$offset + 17 + 2 * $pair] = [byte]$timeline[$pair].delay
        }
    }
    return $table
}

function New-Image {
    param([int]$Width, [int]$Height, [int[]]$Bytes)
    return New-DspreFieldTextureRgbaImage -Width $Width -Height $Height -Rgba ([byte[]]$Bytes)
}

$testRoot = Join-Path (Split-Path $PSScriptRoot -Parent) (".work\field_texture_animation_test_{0}" -f [Guid]::NewGuid().ToString("N"))
$null = New-Item -ItemType Directory -Path $testRoot -Force
try {
    $members = New-Object object[] 53
    $members[0] = New-AnimationTable
    for ($memberId = 1; $memberId -lt $members.Count; $memberId++) {
        $members[$memberId] = New-SyntheticNsbtx -Payload ([byte]$memberId)
    }
    $narcPath = Join-Path $testRoot "fldtanime.narc"
    [IO.File]::WriteAllBytes($narcPath, (New-SyntheticNarcBytes -Members $members))
    $archive = Read-DspreNarcArchive -Path $narcPath -AllowedRoot $testRoot -Label "Synthetic fldtanime"
    $descriptor = ConvertFrom-DspreFieldTextureAnimationArchive -Archive $archive -Label "Synthetic field animations"
    $readDescriptor = Read-DspreFieldTextureAnimationDescriptor -Path $narcPath -AllowedRoot $testRoot
    if (
        [int]$descriptor.animation_count -ne 52 -or
        [int]$readDescriptor.animation_count -ne 52 -or
        [string]$descriptor.animations[0].texture_name -ne "sea" -or
        [int]$descriptor.animations[0].sequence_count -ne 8 -or
        [int]$descriptor.animations[0].sequence[0].hold_ticks -ne 10 -or
        [int]$descriptor.animations[0].cycle_ticks -ne 80 -or
        [double]$descriptor.animations[0].cycle_seconds -ne 2.66666667 -or
        [string]$descriptor.animations[1].texture_name -ne "rhana" -or
        [int]$descriptor.animations[1].cycle_ticks -ne 68 -or
        [string]$descriptor.animations[0].member.magic -ne "BTX0"
    ) {
        throw "Synthetic fldtanime descriptor did not preserve source timing or members."
    }

    $exportPath = Join-Path $testRoot "members\sea.nsbtx"
    $export = Export-DspreFieldTextureAnimationMember -Archive $archive -MemberId 1 -OutputPath $exportPath -WorkRoot $testRoot
    if (
        -not (Test-Path -LiteralPath $exportPath -PathType Leaf) -or
        [string]$export.magic -ne "BTX0" -or
        [long]$export.byte_length -ne ([byte[]]$members[1]).Length -or
        @([IO.Directory]::GetFiles($testRoot, "*.tmp", [IO.SearchOption]::AllDirectories)).Count -ne 0
    ) {
        throw "Atomic fldtanime member export failed."
    }
    Assert-Throws {
        Export-DspreFieldTextureAnimationMember -Archive $archive -MemberId 1 -OutputPath (Join-Path $testRoot "bad.bin") -WorkRoot $testRoot
    } "NSBTX extension"

    $badTableMembers = [object[]]$members.Clone()
    $badTableMembers[0] = [byte[]]([byte[]]$members[0]).Clone()
    $badTableMembers[0][4 + 16] = 0xFF
    $badTableMembers[0][4 + 17] = 0
    Assert-Throws {
        ConvertFrom-DspreFieldTextureAnimationArchive -Archive (ConvertFrom-DspreNarcBytes -Bytes (New-SyntheticNarcBytes -Members $badTableMembers))
    } "non-canonical timeline terminator"
    $badMemberArchive = $archive | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $badBytes = [byte[]]$members[1].Clone()
    $badBytes[0] = [byte][char]'X'
    $badMemberArchive.members[1] = $badBytes
    Assert-Throws {
        ConvertFrom-DspreFieldTextureAnimationArchive -Archive $badMemberArchive
    } "invalid NSBTX member"

    $reference = New-Image 2 2 @(
        255, 0, 0, 255, 0, 255, 0, 255,
        255, 0, 0, 255, 0, 0, 0, 0
    )
    $base = New-Image 2 2 @(
        255, 255, 0, 255, 0, 255, 255, 255,
        255, 255, 0, 255, 10, 20, 30, 0
    )
    $secondFrame = New-Image 2 2 @(
        0, 255, 0, 255, 255, 0, 0, 255,
        0, 255, 0, 255, 99, 88, 77, 0
    )
    $plan = New-DspreFieldTexturePalettePlan -BaseImage $base -ReferenceFrame $reference -FrameImages @($reference, $secondFrame)
    if ([string]$plan.disposition -ne "recolor_frames" -or @($plan.color_map).Count -ne 2) {
        throw "A unique palette variant was not accepted for offline recoloring."
    }
    $variant = ConvertTo-DspreFieldTexturePaletteVariant -Image $secondFrame -PalettePlan $plan
    if (
        ([byte[]]$variant.rgba)[0] -ne 0 -or
        ([byte[]]$variant.rgba)[1] -ne 255 -or
        ([byte[]]$variant.rgba)[2] -ne 255 -or
        ([byte[]]$variant.rgba)[4] -ne 255 -or
        ([byte[]]$variant.rgba)[5] -ne 255 -or
        ([byte[]]$variant.rgba)[6] -ne 0 -or
        ([byte[]]$variant.rgba)[15] -ne 0
    ) {
        throw "Offline palette recoloring changed the wrong RGB or alpha bytes."
    }

    $sameColorsDifferentLayout = New-Image 2 2 @(
        0, 255, 0, 255, 255, 0, 0, 255,
        255, 0, 0, 255, 0, 0, 0, 0
    )
    $reusePlan = New-DspreFieldTexturePalettePlan -BaseImage $sameColorsDifferentLayout -ReferenceFrame $reference -FrameImages @($reference)
    if ([string]$reusePlan.disposition -ne "reuse_source_frames") {
        throw "A matching visible palette was incorrectly tied to texel layout."
    }

    $ambiguousBase = New-Image 2 2 @(
        255, 255, 0, 255, 0, 255, 255, 255,
        0, 0, 255, 255, 0, 0, 0, 0
    )
    $ambiguous = New-DspreFieldTexturePalettePlan -BaseImage $ambiguousBase -ReferenceFrame $reference -FrameImages @($reference)
    if ([string]$ambiguous.disposition -ne "unsupported_deferred" -or [string]$ambiguous.reason -ne "ambiguous_color_mapping") {
        throw "An ambiguous palette mapping did not fail closed."
    }
    $alphaMismatchBase = New-Image 2 2 @(
        255, 255, 0, 255, 0, 255, 255, 255,
        255, 255, 0, 0, 0, 0, 0, 0
    )
    $alphaMismatch = New-DspreFieldTexturePalettePlan -BaseImage $alphaMismatchBase -ReferenceFrame $reference -FrameImages @($reference)
    if ([string]$alphaMismatch.reason -ne "alpha_layout_mismatch") {
        throw "An alpha-layout mismatch did not fail closed."
    }
    $unmappedFrame = New-Image 2 2 @(
        0, 0, 255, 255, 255, 0, 0, 255,
        0, 255, 0, 255, 0, 0, 0, 0
    )
    $unmapped = New-DspreFieldTexturePalettePlan -BaseImage $base -ReferenceFrame $reference -FrameImages @($reference, $unmappedFrame)
    if ([string]$unmapped.reason -ne "unmapped_frame_color") {
        throw "A later frame with an unknown palette color did not fail closed."
    }

    $pngPath = Join-Path $testRoot "png\variant.png"
    $png = Write-DspreFieldTexturePng -Image $variant -Path $pngPath -AllowedRoot $testRoot
    $roundTrip = Read-DspreFieldTexturePng -Path $pngPath -AllowedRoot $testRoot
    if ([int]$png.width -ne 2 -or [int]$png.height -ne 2) {
        throw "Palette-aware PNG output changed its dimensions."
    }
    $variantPixels = [byte[]]$variant.rgba
    $roundTripPixels = [byte[]]$roundTrip.rgba
    for ($offset = 0; $offset -lt $variantPixels.Length; $offset += 4) {
        if ($variantPixels[$offset + 3] -ne $roundTripPixels[$offset + 3]) {
            throw "Palette-aware PNG output changed frame alpha."
        }
        if ($variantPixels[$offset + 3] -ne 0) {
            for ($channel = 0; $channel -lt 3; $channel++) {
                if ($variantPixels[$offset + $channel] -ne $roundTripPixels[$offset + $channel]) {
                    throw "Palette-aware PNG output changed a visible RGB channel."
                }
            }
        }
    }

    [pscustomobject][ordered]@{
        animations = [int]$descriptor.animation_count
        source_fps = [int]$descriptor.source_fps
        sea_cycle_ticks = [int]$descriptor.animations[0].cycle_ticks
        rhana_cycle_ticks = [int]$descriptor.animations[1].cycle_ticks
        nsbtx_export = $true
        palette_reuse = [string]$reusePlan.disposition
        palette_variant = [string]$plan.disposition
        incompatible_palette = [string]$ambiguous.disposition
        png_round_trip = $true
    } | ConvertTo-Json -Compress
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
