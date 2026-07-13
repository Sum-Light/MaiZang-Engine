[CmdletBinding()]
param(
    [string]$SourceRoot = "",
    [string]$OutputRoot = "",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "dspre_collision_support.ps1")
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path $workspaceRoot "generated\dspre_glb\matrix_0000"
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $workspaceRoot "generated\dspre_glb_dedup\matrix_0000"
}

function Test-ObjectProperty {
    param($Object, [string]$Name)
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-Sha256Bytes {
    param([byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Sha256File {
    param([string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Get-Sha256Text {
    param([string]$Text)
    return Get-Sha256Bytes ([Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Get-ForwardRelativePath {
    param([string]$BasePath, [string]$FullPath)

    $baseUri = [Uri]::new(([IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'))
    $fileUri = [Uri]::new([IO.Path]::GetFullPath($FullPath))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fileUri).ToString())
}

function Get-RelativeUriFromDirectory {
    param([string]$Directory, [string]$FilePath)

    $baseUri = [Uri]::new(([IO.Path]::GetFullPath($Directory).TrimEnd('\') + '\'))
    $fileUri = [Uri]::new([IO.Path]::GetFullPath($FilePath))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fileUri).ToString())
}

function Clear-OutputDirectory {
    param([string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $allowedRoot = [IO.Path]::GetFullPath((Join-Path $workspaceRoot "generated\dspre_glb_dedup")).TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear output outside the dedupe root: $fullPath"
    }
    if (Test-Path -LiteralPath $fullPath) {
        Remove-Item -LiteralPath $fullPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
}

function Read-Glb {
    param([string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 12) {
        throw "GLB is shorter than its header: $Path"
    }
    if ([BitConverter]::ToUInt32($bytes, 0) -ne 0x46546C67) {
        throw "Invalid GLB magic: $Path"
    }
    if ([BitConverter]::ToUInt32($bytes, 4) -ne 2) {
        throw "Unsupported GLB version: $Path"
    }
    if ([BitConverter]::ToUInt32($bytes, 8) -ne $bytes.Length) {
        throw "GLB length mismatch: $Path"
    }

    $chunks = New-Object System.Collections.Generic.List[object]
    $offset = 12
    while ($offset -lt $bytes.Length) {
        if ($offset + 8 -gt $bytes.Length) {
            throw "Truncated GLB chunk header: $Path"
        }
        $length = [BitConverter]::ToUInt32($bytes, $offset)
        $type = [BitConverter]::ToUInt32($bytes, $offset + 4)
        $dataOffset = $offset + 8
        if ($dataOffset + $length -gt $bytes.Length) {
            throw "Truncated GLB chunk: $Path"
        }
        $data = New-Object byte[] $length
        [Array]::Copy($bytes, $dataOffset, $data, 0, $length)
        $chunks.Add([pscustomobject]@{ type = $type; data = $data })
        $offset = $dataOffset + $length
    }

    $jsonChunks = @($chunks | Where-Object { $_.type -eq 0x4E4F534A })
    if ($jsonChunks.Count -ne 1) {
        throw "Expected exactly one JSON chunk: $Path"
    }
    $jsonText = [Text.Encoding]::UTF8.GetString($jsonChunks[0].data).TrimEnd([char]0, [char]32, [char]9, [char]10, [char]13)
    return [pscustomobject]@{
        path = $Path
        chunks = $chunks
        json = $jsonText | ConvertFrom-Json
    }
}

function Write-Glb {
    param($Glb, [string]$OutputPath)

    $jsonText = $Glb.json | ConvertTo-Json -Depth 100 -Compress
    $jsonBytes = [Text.UTF8Encoding]::new($false).GetBytes($jsonText)
    $paddedLength = ($jsonBytes.Length + 3) -band -4
    $jsonData = New-Object byte[] $paddedLength
    [Array]::Copy($jsonBytes, $jsonData, $jsonBytes.Length)
    for ($index = $jsonBytes.Length; $index -lt $jsonData.Length; $index++) {
        $jsonData[$index] = 0x20
    }

    $outputChunks = New-Object System.Collections.Generic.List[object]
    foreach ($chunk in $Glb.chunks) {
        if ($chunk.type -eq 0x4E4F534A) {
            $outputChunks.Add([pscustomobject]@{ type = $chunk.type; data = $jsonData })
        }
        else {
            $outputChunks.Add($chunk)
        }
    }

    $totalLength = 12
    foreach ($chunk in $outputChunks) {
        $totalLength += 8 + $chunk.data.Length
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
    $stream = [IO.File]::Open($OutputPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = [IO.BinaryWriter]::new($stream, [Text.Encoding]::UTF8, $true)
    try {
        $writer.Write([uint32]0x46546C67)
        $writer.Write([uint32]2)
        $writer.Write([uint32]$totalLength)
        foreach ($chunk in $outputChunks) {
            $writer.Write([uint32]$chunk.data.Length)
            $writer.Write([uint32]$chunk.type)
            $writer.Write([byte[]]$chunk.data)
        }
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Assert-AllowedProperties {
    param($Object, [string[]]$Allowed, [string]$Label)

    if ($null -eq $Object) {
        return
    }
    foreach ($property in $Object.PSObject.Properties) {
        if ($Allowed -notcontains $property.Name) {
            throw "Unsupported $Label property '$($property.Name)'."
        }
    }
}

function Get-SamplerSignature {
    param($Sampler)

    if ($null -eq $Sampler) {
        return [ordered]@{
            mag_filter = $null
            min_filter = $null
            wrap_s = 10497
            wrap_t = 10497
        }
    }
    Assert-AllowedProperties $Sampler @("magFilter", "minFilter", "wrapS", "wrapT", "name", "extensions", "extras") "sampler"
    return [ordered]@{
        mag_filter = if (Test-ObjectProperty $Sampler "magFilter") { [int]$Sampler.magFilter } else { $null }
        min_filter = if (Test-ObjectProperty $Sampler "minFilter") { [int]$Sampler.minFilter } else { $null }
        wrap_s = if (Test-ObjectProperty $Sampler "wrapS") { [int]$Sampler.wrapS } else { 10497 }
        wrap_t = if (Test-ObjectProperty $Sampler "wrapT") { [int]$Sampler.wrapT } else { 10497 }
    }
}

function Get-TextureKey {
    param($Texture, [string[]]$ImageKeys, [object[]]$Samplers)

    Assert-AllowedProperties $Texture @("source", "sampler", "name", "extensions", "extras") "texture"
    if (-not (Test-ObjectProperty $Texture "source")) {
        throw "Texture has no source image."
    }
    $sourceIndex = [int]$Texture.source
    if ($sourceIndex -lt 0 -or $sourceIndex -ge $ImageKeys.Length) {
        throw "Texture source index is out of range: $sourceIndex"
    }
    $sampler = $null
    if (Test-ObjectProperty $Texture "sampler") {
        $samplerIndex = [int]$Texture.sampler
        if ($samplerIndex -lt 0 -or $samplerIndex -ge $Samplers.Length) {
            throw "Sampler index is out of range: $samplerIndex"
        }
        $sampler = $Samplers[$samplerIndex]
    }
    $signature = [ordered]@{
        image_key = $ImageKeys[$sourceIndex]
        sampler = Get-SamplerSignature $sampler
    }
    $json = $signature | ConvertTo-Json -Depth 10 -Compress
    return "tex_$(Get-Sha256Text $json)"
}

function Get-NumberArray {
    param($Value, [double[]]$Default)

    if ($null -eq $Value) {
        return @($Default)
    }
    return @($Value | ForEach-Object { [double]$_ })
}

function Get-MaterialSignature {
    param($Material, [string[]]$TextureKeys)

    Assert-AllowedProperties $Material @("name", "pbrMetallicRoughness", "extensions", "alphaMode", "alphaCutoff", "doubleSided", "emissiveFactor") "material"
    $pbr = if (Test-ObjectProperty $Material "pbrMetallicRoughness") { $Material.pbrMetallicRoughness } else { $null }
    Assert-AllowedProperties $pbr @("baseColorTexture", "baseColorFactor", "metallicFactor", "roughnessFactor") "PBR material"

    $baseTextureKey = $null
    if ($null -ne $pbr -and (Test-ObjectProperty $pbr "baseColorTexture")) {
        $textureInfo = $pbr.baseColorTexture
        Assert-AllowedProperties $textureInfo @("index") "base color texture info"
        $textureIndex = [int]$textureInfo.index
        if ($textureIndex -lt 0 -or $textureIndex -ge $TextureKeys.Length) {
            throw "Material texture index is out of range: $textureIndex"
        }
        $baseTextureKey = $TextureKeys[$textureIndex]
    }

    $unlit = $false
    if (Test-ObjectProperty $Material "extensions") {
        Assert-AllowedProperties $Material.extensions @("KHR_materials_unlit") "material extension"
        $unlit = Test-ObjectProperty $Material.extensions "KHR_materials_unlit"
    }

    return [ordered]@{
        unlit = $unlit
        base_color_texture = $baseTextureKey
        base_color_factor = Get-NumberArray $(if ($null -ne $pbr -and (Test-ObjectProperty $pbr "baseColorFactor")) { $pbr.baseColorFactor } else { $null }) ([double[]]@(1, 1, 1, 1))
        metallic_factor = if ($null -ne $pbr -and (Test-ObjectProperty $pbr "metallicFactor")) { [double]$pbr.metallicFactor } else { 1.0 }
        roughness_factor = if ($null -ne $pbr -and (Test-ObjectProperty $pbr "roughnessFactor")) { [double]$pbr.roughnessFactor } else { 1.0 }
        alpha_mode = if (Test-ObjectProperty $Material "alphaMode") { [string]$Material.alphaMode } else { "OPAQUE" }
        alpha_cutoff = if (Test-ObjectProperty $Material "alphaCutoff") { [double]$Material.alphaCutoff } else { 0.5 }
        double_sided = if (Test-ObjectProperty $Material "doubleSided") { [bool]$Material.doubleSided } else { $false }
        emissive_factor = Get-NumberArray $(if (Test-ObjectProperty $Material "emissiveFactor") { $Material.emissiveFactor } else { $null }) ([double[]]@(0, 0, 0))
    }
}

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "Source export does not exist: $SourceRoot"
}
$sourcePrefix = $SourceRoot + '\'
$outputPrefix = $OutputRoot + '\'
if (
    $SourceRoot.Equals($OutputRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $sourcePrefix.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    $outputPrefix.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)
) {
    throw "Source and output must not overlap: $SourceRoot -> $OutputRoot"
}
$manifestPath = Join-Path $SourceRoot "manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Source manifest does not exist: $manifestPath"
}
$manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$null = Assert-DspreCollisionManifest `
    -Manifest $manifest `
    -Label "Source export manifest" `
    -ExpectedManifestSchema 2
$sourceManifestSha256 = Get-Sha256File $manifestPath
if (Test-Path -LiteralPath $OutputRoot) {
    if (-not $Force) {
        throw "Output already exists. Pass -Force to rebuild it: $OutputRoot"
    }
    Clear-OutputDirectory $OutputRoot
}
else {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

$sharedTextureRoot = Join-Path $OutputRoot "shared\textures"
New-Item -ItemType Directory -Path $sharedTextureRoot -Force | Out-Null
$sourceGlbs = @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -Filter "*.glb" -File | Sort-Object FullName)
if ($sourceGlbs.Count -eq 0) {
    throw "No GLBs were found under $SourceRoot"
}

$imageCatalog = @{}
$materialCatalog = @{}
$assetBindings = New-Object System.Collections.Generic.List[object]
$sourceImageCount = 0
$sourceMaterialCount = 0
$outputMaterialCount = 0
$utf8NoBom = [Text.UTF8Encoding]::new($false)

for ($fileIndex = 0; $fileIndex -lt $sourceGlbs.Count; $fileIndex++) {
    $sourceFile = $sourceGlbs[$fileIndex]
    $relativeGlb = Get-ForwardRelativePath $SourceRoot $sourceFile.FullName
    $outputPath = Join-Path $OutputRoot $relativeGlb.Replace('/', '\')
    $outputDirectory = Split-Path -Parent $outputPath
    $glb = Read-Glb $sourceFile.FullName
    $images = @(if (Test-ObjectProperty $glb.json "images") { $glb.json.images })
    $imageKeys = New-Object string[] $images.Count
    $imageBindings = New-Object System.Collections.Generic.List[object]

    for ($imageIndex = 0; $imageIndex -lt $images.Count; $imageIndex++) {
        $sourceImageCount++
        $image = $images[$imageIndex]
        Assert-AllowedProperties $image @("uri", "name", "mimeType", "extras", "extensions") "image"
        if (-not (Test-ObjectProperty $image "uri")) {
            throw "Embedded images are not supported: $($sourceFile.FullName)"
        }
        $sourceUri = [string]$image.uri
        $sourceImagePath = [IO.Path]::GetFullPath((Join-Path $sourceFile.DirectoryName $sourceUri))
        if (-not $sourceImagePath.StartsWith(($SourceRoot + '\'), [StringComparison]::OrdinalIgnoreCase)) {
            throw "Image URI escapes the source root: $sourceUri"
        }
        if (-not (Test-Path -LiteralPath $sourceImagePath -PathType Leaf)) {
            throw "Referenced image is missing: $sourceImagePath"
        }

        $hash = Get-Sha256File $sourceImagePath
        $imageKey = "img_$hash"
        $imageKeys[$imageIndex] = $imageKey
        $sharedPath = Join-Path $sharedTextureRoot "$hash.png"
        if (-not $imageCatalog.ContainsKey($imageKey)) {
            Copy-Item -LiteralPath $sourceImagePath -Destination $sharedPath
            $imageCatalog[$imageKey] = [pscustomobject]@{
                key = $imageKey
                sha256 = $hash
                relative_path = Get-ForwardRelativePath $OutputRoot $sharedPath
                byte_length = (Get-Item -LiteralPath $sharedPath).Length
                aliases = New-Object System.Collections.Generic.HashSet[string]
                use_count = 0
            }
        }
        $null = $imageCatalog[$imageKey].aliases.Add([IO.Path]::GetFileName($sourceUri))
        $imageCatalog[$imageKey].use_count++
        $newUri = Get-RelativeUriFromDirectory $outputDirectory $sharedPath
        $image.uri = $newUri
        $imageBindings.Add([pscustomobject][ordered]@{
            index = $imageIndex
            source_uri = $sourceUri
            image_key = $imageKey
            shared_uri = $newUri
        })
    }

    $samplers = @(if (Test-ObjectProperty $glb.json "samplers") { $glb.json.samplers })
    $textures = @(if (Test-ObjectProperty $glb.json "textures") { $glb.json.textures })
    $textureKeys = New-Object string[] $textures.Count
    for ($textureIndex = 0; $textureIndex -lt $textures.Count; $textureIndex++) {
        $textureKeys[$textureIndex] = Get-TextureKey $textures[$textureIndex] $imageKeys $samplers
    }

    $materials = @(if (Test-ObjectProperty $glb.json "materials") { $glb.json.materials })
    $oldToNew = New-Object int[] $materials.Count
    $localMaterialIndexes = @{}
    $newMaterials = New-Object System.Collections.Generic.List[object]
    $materialBindings = New-Object System.Collections.Generic.List[object]

    for ($materialIndex = 0; $materialIndex -lt $materials.Count; $materialIndex++) {
        $sourceMaterialCount++
        $material = $materials[$materialIndex]
        $originalName = if (Test-ObjectProperty $material "name") { [string]$material.name } else { "" }
        $signature = Get-MaterialSignature $material $textureKeys
        $signatureJson = $signature | ConvertTo-Json -Depth 20 -Compress
        $hash = Get-Sha256Text $signatureJson
        $materialKey = "mat_$hash"

        if (-not $materialCatalog.ContainsKey($materialKey)) {
            $materialCatalog[$materialKey] = [pscustomobject]@{
                key = $materialKey
                signature = $signature
                aliases = New-Object System.Collections.Generic.HashSet[string]
                use_count = 0
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($originalName)) {
            $null = $materialCatalog[$materialKey].aliases.Add($originalName)
        }
        $materialCatalog[$materialKey].use_count++

        if (-not $localMaterialIndexes.ContainsKey($materialKey)) {
            $newIndex = $newMaterials.Count
            $localMaterialIndexes[$materialKey] = $newIndex
            if (Test-ObjectProperty $material "name") {
                $material.name = "dspre_$materialKey"
            }
            else {
                $material | Add-Member -NotePropertyName "name" -NotePropertyValue "dspre_$materialKey"
            }
            $newMaterials.Add($material)
        }
        $oldToNew[$materialIndex] = [int]$localMaterialIndexes[$materialKey]
        $materialBindings.Add([pscustomobject][ordered]@{
            source_index = $materialIndex
            output_index = $oldToNew[$materialIndex]
            source_name = $originalName
            material_key = $materialKey
        })
    }

    if ($materials.Count -gt 0) {
        foreach ($mesh in @($glb.json.meshes)) {
            foreach ($primitive in @($mesh.primitives)) {
                if (Test-ObjectProperty $primitive "material") {
                    $primitive.material = $oldToNew[[int]$primitive.material]
                }
            }
        }
        $glb.json.materials = [object[]]$newMaterials.ToArray()
    }
    $outputMaterialCount += $newMaterials.Count

    $tempPath = "$outputPath.tmp"
    Write-Glb $glb $tempPath
    $check = Read-Glb $tempPath
    if ($null -eq $check.json) {
        throw "Rewritten GLB could not be parsed: $tempPath"
    }
    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Force
    }
    Move-Item -LiteralPath $tempPath -Destination $outputPath

    $assetBindings.Add([pscustomobject][ordered]@{
        glb = $relativeGlb
        source_material_count = $materials.Count
        output_material_count = $newMaterials.Count
        images = [object[]]$imageBindings.ToArray()
        materials = [object[]]$materialBindings.ToArray()
    })
    Write-Progress -Activity "Deduplicating DSPRE materials" -Status "$($fileIndex + 1) / $($sourceGlbs.Count)" -PercentComplete (100.0 * ($fileIndex + 1) / $sourceGlbs.Count)
}
Write-Progress -Activity "Deduplicating DSPRE materials" -Completed

$imageRecords = @(
    $imageCatalog.Values | Sort-Object key | ForEach-Object {
        [pscustomobject][ordered]@{
            key = $_.key
            sha256 = $_.sha256
            relative_path = $_.relative_path
            byte_length = $_.byte_length
            use_count = $_.use_count
            aliases = @($_.aliases | Sort-Object)
        }
    }
)
$materialRecords = @(
    $materialCatalog.Values | Sort-Object key | ForEach-Object {
        [pscustomobject][ordered]@{
            key = $_.key
            use_count = $_.use_count
            aliases = @($_.aliases | Sort-Object)
            signature = $_.signature
        }
    }
)

$catalog = [pscustomobject][ordered]@{
    schema_version = 1
    generated_utc = [DateTime]::UtcNow.ToString("o")
    source_root = $SourceRoot
    summary = [pscustomobject][ordered]@{
        glbs = $sourceGlbs.Count
        source_image_references = $sourceImageCount
        unique_images = $imageRecords.Count
        source_material_slots = $sourceMaterialCount
        within_glb_material_slots = $outputMaterialCount
        unique_materials = $materialRecords.Count
        removed_image_files = $sourceImageCount - $imageRecords.Count
        removed_within_glb_materials = $sourceMaterialCount - $outputMaterialCount
    }
    images = $imageRecords
    materials = $materialRecords
    assets = [object[]]$assetBindings.ToArray()
}
$catalogPath = Join-Path $OutputRoot "material_catalog.json"
[IO.File]::WriteAllText($catalogPath, ($catalog | ConvertTo-Json -Depth 30 -Compress), $utf8NoBom)

$manifest.schema_version = 3
$manifest.generated_utc = [DateTime]::UtcNow.ToString("o")
$manifest | Add-Member -Force -NotePropertyName "material_dedupe" -NotePropertyValue ([pscustomobject][ordered]@{
    catalog = "material_catalog.json"
    shared_texture_root = "shared/textures"
    source_image_references = $sourceImageCount
    unique_images = $imageRecords.Count
    source_material_slots = $sourceMaterialCount
    within_glb_material_slots = $outputMaterialCount
    unique_materials = $materialRecords.Count
})
[IO.File]::WriteAllText((Join-Path $OutputRoot "manifest.json"), ($manifest | ConvertTo-Json -Depth 30 -Compress), $utf8NoBom)

$sourcePngBytes = 0L
foreach ($png in @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -Filter "*.png" -File)) {
    $sourcePngBytes += [long]$png.Length
}
$sharedPngBytes = 0L
foreach ($png in @(Get-ChildItem -LiteralPath $sharedTextureRoot -Filter "*.png" -File)) {
    $sharedPngBytes += [long]$png.Length
}
$summary = [pscustomobject][ordered]@{
    glbs = $sourceGlbs.Count
    source_image_references = $sourceImageCount
    unique_images = $imageRecords.Count
    removed_image_files = $sourceImageCount - $imageRecords.Count
    source_png_bytes = $sourcePngBytes
    shared_png_bytes = $sharedPngBytes
    source_material_slots = $sourceMaterialCount
    within_glb_material_slots = $outputMaterialCount
    unique_materials = $materialRecords.Count
    removed_within_glb_materials = $sourceMaterialCount - $outputMaterialCount
    manifest = Join-Path $OutputRoot "manifest.json"
    material_catalog = $catalogPath
}
[IO.File]::WriteAllText((Join-Path $OutputRoot "summary.json"), ($summary | ConvertTo-Json -Depth 5), $utf8NoBom)
$outputManifestPath = Join-Path $OutputRoot "manifest.json"
$completionMarker = [pscustomobject][ordered]@{
    schema_version = 1
    generated_utc = [DateTime]::UtcNow.ToString("o")
    source_manifest_sha256 = $sourceManifestSha256
    output_manifest_sha256 = Get-Sha256File $outputManifestPath
    glbs = $sourceGlbs.Count
    unique_images = $imageRecords.Count
    unique_materials = $materialRecords.Count
}
[IO.File]::WriteAllText(
    (Join-Path $OutputRoot ".dedupe-complete.json"),
    ($completionMarker | ConvertTo-Json -Depth 4),
    $utf8NoBom
)

Write-Host "Material dedupe complete."
Write-Host "  GLBs:                 $($sourceGlbs.Count)"
Write-Host "  Images:               $sourceImageCount -> $($imageRecords.Count)"
Write-Host "  Material slots:       $sourceMaterialCount -> $outputMaterialCount"
Write-Host "  Unique materials:     $($materialRecords.Count)"
Write-Host "  Catalog:              $catalogPath"
