Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "dspre_field_texture_animation_support.ps1")

function Assert-True {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Label)

    $threw = $false
    try {
        & $Action
    }
    catch {
        $threw = $true
    }
    if (-not $threw) {
        throw "Expected failure was accepted: $Label"
    }
}

function Set-U16 {
    param([byte[]]$Bytes, [int]$Offset, [uint16]$Value)

    [Buffer]::BlockCopy([BitConverter]::GetBytes($Value), 0, $Bytes, $Offset, 2)
}

function Set-U32 {
    param([byte[]]$Bytes, [int]$Offset, [uint32]$Value)

    [Buffer]::BlockCopy([BitConverter]::GetBytes($Value), 0, $Bytes, $Offset, 4)
}

function Set-Ascii {
    param([byte[]]$Bytes, [int]$Offset, [string]$Value, [int]$Length = -1)

    $encoded = [Text.Encoding]::ASCII.GetBytes($Value)
    if ($Length -lt 0) { $Length = $encoded.Length }
    if ($encoded.Length -gt $Length) { throw "ASCII fixture value is too long." }
    [Buffer]::BlockCopy($encoded, 0, $Bytes, $Offset, $encoded.Length)
}

function New-InfoBlock {
    param(
        [Parameter(Mandatory)][byte[][]]$Records,
        [Parameter(Mandatory)][string[]]$Names
    )

    if ($Records.Count -ne $Names.Count -or $Records.Count -gt 255) {
        throw "Synthetic info block has inconsistent records and names."
    }
    $count = $Records.Count
    $datumSize = if ($count -eq 0) { 4 } else { $Records[0].Length }
    foreach ($record in $Records) {
        if ($record.Length -ne $datumSize) { throw "Synthetic info records differ in size." }
    }
    $headerSize = 16 + $count * (4 + $datumSize + 16)
    $bytes = New-Object byte[] $headerSize
    $bytes[1] = [byte]$count
    Set-U16 $bytes 2 ([uint16]$headerSize)
    Set-U16 $bytes 4 8
    Set-U16 $bytes 6 ([uint16](12 + 4 * $count))
    Set-U32 $bytes 8 0x17F
    $sizeOffset = 12 + 4 * $count
    Set-U16 $bytes $sizeOffset ([uint16]$datumSize)
    Set-U16 $bytes ($sizeOffset + 2) ([uint16](4 + $datumSize * $count))
    $dataOffset = $sizeOffset + 4
    $nameOffset = $dataOffset + $datumSize * $count
    for ($index = 0; $index -lt $count; $index++) {
        [Buffer]::BlockCopy($Records[$index], 0, $bytes, $dataOffset + $datumSize * $index, $datumSize)
        Set-Ascii $bytes ($nameOffset + 16 * $index) $Names[$index] 16
    }
    return ,$bytes
}

function New-TextureRecord {
    param([int]$Offset, [int]$Format, [bool]$Color0Transparent = $false)

    $record = New-Object byte[] 8
    $params = [uint32]($Offset / 8) -bor ([uint32]$Format -shl 26)
    if ($Color0Transparent) { $params = $params -bor ([uint32]1 -shl 29) }
    Set-U32 $record 0 $params
    return ,$record
}

function New-SyntheticNsbtx {
    $regular = New-Object byte[] 368
    $regular[0] = 0xE1
    $regular[1] = 0x62
    $regular[64] = 0xE4
    $regular[80] = 0x21
    $regular[112] = 0xFF
    $regular[176] = 0xFA
    Set-U16 $regular 240 0x801F

    $compressed1 = New-Object byte[] 16
    for ($offset = 0; $offset -lt $compressed1.Length; $offset += 4) {
        Set-U32 $compressed1 $offset 0xE4
    }
    $compressed2 = New-Object byte[] 8
    Set-U16 $compressed2 0 0x0000
    Set-U16 $compressed2 2 0x4000
    Set-U16 $compressed2 4 0x8000
    Set-U16 $compressed2 6 0xC000

    $palette = New-Object byte[] 512
    Set-U16 $palette 0 0x001F
    Set-U16 $palette 2 0x03E0
    Set-U16 $palette 4 0x7C00
    Set-U16 $palette 6 0x7FFF
    Set-U16 $palette 510 0x7C1F

    $textureRecords = New-Object 'byte[][]' 7
    $textureRecords[0] = [byte[]](New-TextureRecord -Offset 0 -Format 1)
    $textureRecords[1] = [byte[]](New-TextureRecord -Offset 64 -Format 2 -Color0Transparent $true)
    $textureRecords[2] = [byte[]](New-TextureRecord -Offset 80 -Format 3)
    $textureRecords[3] = [byte[]](New-TextureRecord -Offset 112 -Format 4)
    $textureRecords[4] = [byte[]](New-TextureRecord -Offset 0 -Format 5)
    $textureRecords[5] = [byte[]](New-TextureRecord -Offset 176 -Format 6)
    $textureRecords[6] = [byte[]](New-TextureRecord -Offset 240 -Format 7)
    $textureInfo = [byte[]](New-InfoBlock `
        -Records $textureRecords `
        -Names @("tex_f1", "tex_f2", "tex_f3", "tex_f4", "tex_f5", "tex_f6", "tex_f7"))
    $paletteRecord = New-Object byte[] 4
    $paletteRecords = New-Object 'byte[][]' 1
    $paletteRecords[0] = $paletteRecord
    $paletteInfo = [byte[]](New-InfoBlock -Records $paletteRecords -Names @("test_pal"))

    $textureInfoOffset = 60
    $paletteInfoOffset = $textureInfoOffset + $textureInfo.Length
    $regularOffset = $paletteInfoOffset + $paletteInfo.Length
    $compressed1Offset = $regularOffset + $regular.Length
    $compressed2Offset = $compressed1Offset + $compressed1.Length
    $paletteOffset = $compressed2Offset + $compressed2.Length
    foreach ($offset in @($regularOffset, $compressed1Offset, $compressed2Offset, $paletteOffset)) {
        if (($offset % 8) -ne 0) { throw "Synthetic TEX0 data block is not aligned." }
    }

    $sectionSize = $paletteOffset + $palette.Length
    $bytes = New-Object byte[] (20 + $sectionSize)
    Set-Ascii $bytes 0 "BTX0"
    Set-U16 $bytes 4 0xFEFF
    Set-U16 $bytes 6 1
    Set-U32 $bytes 8 ([uint32]$bytes.Length)
    Set-U16 $bytes 12 16
    Set-U16 $bytes 14 1
    Set-U32 $bytes 16 20

    $section = 20
    Set-Ascii $bytes $section "TEX0"
    Set-U32 $bytes ($section + 4) ([uint32]$sectionSize)
    Set-U16 $bytes ($section + 12) ([uint16]($regular.Length / 8))
    Set-U16 $bytes ($section + 14) ([uint16]$textureInfoOffset)
    Set-U32 $bytes ($section + 20) ([uint32]$regularOffset)
    Set-U16 $bytes ($section + 28) ([uint16]($compressed1.Length / 8))
    Set-U16 $bytes ($section + 30) ([uint16]$textureInfoOffset)
    Set-U32 $bytes ($section + 36) ([uint32]$compressed1Offset)
    Set-U32 $bytes ($section + 40) ([uint32]$compressed2Offset)
    Set-U16 $bytes ($section + 48) ([uint16]($palette.Length / 8))
    Set-U32 $bytes ($section + 52) ([uint32]$paletteInfoOffset)
    Set-U32 $bytes ($section + 56) ([uint32]$paletteOffset)
    [Buffer]::BlockCopy($textureInfo, 0, $bytes, $section + $textureInfoOffset, $textureInfo.Length)
    [Buffer]::BlockCopy($paletteInfo, 0, $bytes, $section + $paletteInfoOffset, $paletteInfo.Length)
    [Buffer]::BlockCopy($regular, 0, $bytes, $section + $regularOffset, $regular.Length)
    [Buffer]::BlockCopy($compressed1, 0, $bytes, $section + $compressed1Offset, $compressed1.Length)
    [Buffer]::BlockCopy($compressed2, 0, $bytes, $section + $compressed2Offset, $compressed2.Length)
    [Buffer]::BlockCopy($palette, 0, $bytes, $section + $paletteOffset, $palette.Length)
    return ,$bytes
}

function Get-PixelKey {
    param($Image, [int]$X, [int]$Y)

    $offset = 4 * ($Y * [int]$Image.width + $X)
    return "{0},{1},{2},{3}" -f @(
        $Image.rgba[$offset],
        $Image.rgba[$offset + 1],
        $Image.rgba[$offset + 2],
        $Image.rgba[$offset + 3]
    )
}

$bytes = [byte[]](New-SyntheticNsbtx)
$parsed = ConvertFrom-DspreFieldTextureNsbtxBytes -Bytes $bytes -Label "synthetic TEX0"
Assert-True (@($parsed.textures).Count -eq 7) "Texture table count changed."
Assert-True (@($parsed.palettes).Count -eq 1) "Palette table count changed."
Assert-True ((@($parsed.textures | ForEach-Object { $_.name }) -join ',') -ceq "tex_f1,tex_f2,tex_f3,tex_f4,tex_f5,tex_f6,tex_f7") "Texture table order changed."
Assert-True ((@($parsed.textures | ForEach-Object { $_.format }) -join ',') -eq "1,2,3,4,5,6,7") "Texture formats were not preserved."
Assert-True ((@($parsed.textures | ForEach-Object { $_.data.Length }) -join ',') -eq "64,16,32,64,16,64,128") "Texture data lengths changed."
Assert-True ($parsed.textures[4].data2.Length -eq 8) "Compressed secondary data length changed."
Assert-True ($parsed.palettes[0].name -ceq "test_pal" -and @($parsed.palettes[0].colors).Count -eq 256) "Palette colors were not parsed."
Assert-True ($parsed.sha256 -eq (Get-DspreFieldTextureSha256 -Bytes $bytes)) "NSBTX source hash changed."

$images = [Collections.Generic.List[object]]::new()
for ($index = 0; $index -lt 6; $index++) {
    $images.Add((ConvertFrom-DspreFieldTextureTexelData -Texture $parsed.textures[$index] -Palette $parsed.palettes[0]))
}
$images.Add((ConvertFrom-DspreFieldTextureTexelData -Texture $parsed.textures[6]))
foreach ($image in $images) {
    Assert-True ($image.width -eq 8 -and $image.height -eq 8 -and $image.rgba.Length -eq 256) "Decoded dimensions changed."
}
Assert-True ((Get-PixelKey $images[0] 0 0) -eq "0,255,0,255") "A3I5 decode changed."
Assert-True ((Get-PixelKey $images[0] 1 0) -eq "0,0,255,107") "A3I5 translucent decode changed."
Assert-True ((Get-PixelKey $images[1] 0 0) -eq "255,0,0,0") "Palette4 transparent color zero changed."
Assert-True ((Get-PixelKey $images[1] 1 0) -eq "0,255,0,255") "Palette4 texel ordering changed."
Assert-True ((Get-PixelKey $images[1] 2 0) -eq "0,0,255,255") "Palette4 second texel changed."
Assert-True ((Get-PixelKey $images[1] 3 0) -eq "255,255,255,255") "Palette4 third texel changed."
Assert-True ((Get-PixelKey $images[2] 0 0) -eq "0,255,0,255" -and (Get-PixelKey $images[2] 1 0) -eq "0,0,255,255") "Palette16 nibble order changed."
Assert-True ((Get-PixelKey $images[3] 0 0) -eq "255,0,255,255") "Palette256 decode changed."
Assert-True ((Get-PixelKey $images[4] 3 0) -eq "0,0,0,0") "Block mode 0 transparency changed."
Assert-True ((Get-PixelKey $images[4] 6 0) -eq "127,127,0,255") "Block mode 1 average changed."
Assert-True ((Get-PixelKey $images[4] 3 4) -eq "255,255,255,255") "Block mode 2 direct color changed."
Assert-True ((Get-PixelKey $images[4] 6 4) -eq "159,95,0,255") "Block mode 3 first weighted color changed."
Assert-True ((Get-PixelKey $images[4] 7 4) -eq "95,159,0,255") "Block mode 3 second weighted color changed."
Assert-True ((Get-PixelKey $images[5] 0 0) -eq "0,0,255,255") "A5I3 decode changed."
Assert-True ((Get-PixelKey $images[6] 0 0) -eq "255,0,0,255" -and (Get-PixelKey $images[6] 1 0) -eq "0,0,0,0") "Direct-color decode changed."

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$workRoot = Join-Path $repositoryRoot ".work"
if (-not (Test-Path -LiteralPath $workRoot)) {
    $null = [IO.Directory]::CreateDirectory($workRoot)
}
$pngRoundTripRoot = Join-Path $workRoot ("field_texture_tex0_{0}" -f [Guid]::NewGuid().ToString("N"))
$null = [IO.Directory]::CreateDirectory($pngRoundTripRoot)
try {
    $pngPath = Join-Path $pngRoundTripRoot "a3i5_translucent.png"
    $null = Write-DspreFieldTexturePng -Image $images[0] -Path $pngPath -AllowedRoot $pngRoundTripRoot
    $roundTrip = Read-DspreFieldTexturePng -Path $pngPath -AllowedRoot $pngRoundTripRoot
    Assert-True ($roundTrip.rgba_sha256 -eq $images[0].rgba_sha256) "PNG reading changed translucent RGB values."
    $partialAlpha = New-DspreFieldTextureRgbaImage `
        -Width 1 `
        -Height 1 `
        -Rgba ([byte[]]@(41, 140, 198, 107))
    $partialPath = Join-Path $pngRoundTripRoot "partial_alpha_exact.png"
    $null = Write-DspreFieldTexturePng -Image $partialAlpha -Path $partialPath -AllowedRoot $pngRoundTripRoot
    $partialRoundTrip = Read-DspreFieldTexturePng -Path $partialPath -AllowedRoot $pngRoundTripRoot
    Assert-True (
        $partialRoundTrip.rgba_sha256 -eq $partialAlpha.rgba_sha256 -and
        (Get-PixelKey $partialRoundTrip 0 0) -eq "41,140,198,107"
    ) "PNG reading rounded a partial-alpha A3I5 color."
}
finally {
    if (Test-Path -LiteralPath $pngRoundTripRoot) {
        Remove-Item -LiteralPath $pngRoundTripRoot -Recurse -Force
    }
}

$badSize = [byte[]]$bytes.Clone()
Set-U32 $badSize 8 ([uint32]($badSize.Length - 1))
Assert-Throws { ConvertFrom-DspreFieldTextureNsbtxBytes -Bytes $badSize } "BTX0 size mismatch"

$badOffset = [byte[]]$bytes.Clone()
$textureRecordOffset = 20 + 60 + 12 + 4 * 7 + 4
Set-U32 $badOffset $textureRecordOffset 0x0400FFFF
Assert-Throws { ConvertFrom-DspreFieldTextureNsbtxBytes -Bytes $badOffset } "texture data range"

$duplicateName = [byte[]]$bytes.Clone()
$textureNamesOffset = $textureRecordOffset + 8 * 7
[Buffer]::BlockCopy($duplicateName, $textureNamesOffset, $duplicateName, $textureNamesOffset + 16, 16)
Assert-Throws { ConvertFrom-DspreFieldTextureNsbtxBytes -Bytes $duplicateName } "duplicate texture name"

$originalTexel = $parsed.textures[0].data[0]
$parsed.textures[0].data[0] = $originalTexel -bxor 1
Assert-Throws { ConvertFrom-DspreFieldTextureTexelData -Texture $parsed.textures[0] -Palette $parsed.palettes[0] } "mutated texel hash"
$parsed.textures[0].data[0] = $originalTexel
Assert-Throws { ConvertFrom-DspreFieldTextureTexelData -Texture $parsed.textures[0] } "missing required palette"

$originalPaletteByte = $parsed.palettes[0].palette_block[0]
$parsed.palettes[0].palette_block[0] = $originalPaletteByte -bxor 1
Assert-Throws { ConvertFrom-DspreFieldTextureTexelData -Texture $parsed.textures[0] -Palette $parsed.palettes[0] } "mutated palette hash"
$parsed.palettes[0].palette_block[0] = $originalPaletteByte

$badFormat = $parsed.textures[0].PSObject.Copy()
$badFormat.format = 0
Assert-Throws { ConvertFrom-DspreFieldTextureTexelData -Texture $badFormat -Palette $parsed.palettes[0] } "format zero"

[pscustomobject][ordered]@{
    textures = @($parsed.textures).Count
    palettes = @($parsed.palettes).Count
    decoded_formats = 7
    rgba_hashes_verified = 7
    strict_failures = 7
} | ConvertTo-Json -Compress
