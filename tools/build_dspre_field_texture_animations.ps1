[CmdletBinding()]
param(
    [string]$DspreContents = "",
    [string]$DedupRoot = "",
    [string]$OutputRoot = "",
    [string]$GodotOutputRoot = "",
    [string]$WorkRoot = "",
    [ValidateRange(1, 4096)]
    [int]$ExpectedMaterialCatalogCount = 278,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot "dspre_collision_support.ps1")
. (Join-Path $PSScriptRoot "dspre_field_texture_animation_support.ps1")

$script:DspreFieldTextureSectionFile = "field_texture_animations.json"
$script:DspreFieldTextureMarkerFile = ".field-texture-animations-complete.json"
$script:DspreFieldTextureBuildContract = 1
$script:DspreFieldTextureUtf8 = [Text.UTF8Encoding]::new($false)
$script:DspreFieldTextureFingerprintNames = @(
    "fldtanime_sha256",
    "support_sha256",
    "builder_sha256",
    "material_catalogs_sha256",
    "texture_packs_sha256"
)

function Get-DspreFieldTextureFileSha256 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-DspreFieldTextureTextSha256 {
    param([Parameter(Mandatory)][string]$Text)

    return Get-DspreFieldTextureSha256 -Bytes $script:DspreFieldTextureUtf8.GetBytes($Text)
}

function ConvertTo-DspreFieldTextureNormalizedAlias {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $leaf = [IO.Path]::GetFileName($Name).ToLowerInvariant()
    if ($leaf.EndsWith(".png", [StringComparison]::Ordinal)) {
        $leaf = $leaf.Substring(0, $leaf.Length - 4)
    }
    $normalized = [regex]::Replace($leaf, '[^a-z0-9]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "Field texture alias is empty after normalization: $Name"
    }
    return $normalized
}

function Get-DspreFieldTextureCombinedRecordSha256 {
    param([Parameter(Mandatory)][object[]]$Records)

    $builder = [Text.StringBuilder]::new()
    foreach ($record in @($Records | Sort-Object { [string]$_.relative_path })) {
        $relativePath = ([string]$record.relative_path).Replace('\', '/')
        if (
            [string]::IsNullOrWhiteSpace($relativePath) -or
            [long]$record.byte_length -lt 0 -or
            [string]$record.sha256 -notmatch '^[0-9a-f]{64}$'
        ) {
            throw "Field texture fingerprint contains an invalid record: $relativePath"
        }
        $null = $builder.Append($relativePath.Normalize([Text.NormalizationForm]::FormC))
        $null = $builder.Append([char]0)
        $null = $builder.Append(([long]$record.byte_length).ToString([Globalization.CultureInfo]::InvariantCulture))
        $null = $builder.Append([char]0)
        $null = $builder.Append([string]$record.sha256)
        $null = $builder.Append("`n")
    }
    return Get-DspreFieldTextureTextSha256 -Text $builder.ToString()
}

function Resolve-DspreFieldTextureStrictDescendant {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Boundary,
        [Parameter(Mandatory)][string]$Label
    )

    $fullBoundary = [IO.Path]::GetFullPath($Boundary).TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $fullBoundary -PathType Container)) {
        $null = [IO.Directory]::CreateDirectory($fullBoundary)
    }
    $fullPath = Assert-DspreSafeRecursiveDeletePath -Path $Path -AllowedRoot $fullBoundary
    $parent = Split-Path $fullPath -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = [IO.Directory]::CreateDirectory($parent)
    }
    $null = Assert-DspreSafeRecursiveDeletePath -Path $fullPath -AllowedRoot $repositoryRoot
    if (Test-Path -LiteralPath $fullPath) {
        $null = Assert-DspreTreeHasNoReparsePoints -RootPath $fullPath -Label $Label
    }
    return $fullPath
}

function Remove-DspreFieldTextureDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $safePath = Assert-DspreSafeRecursiveDeletePath -Path $Path -AllowedRoot $repositoryRoot
    $null = Assert-DspreTreeHasNoReparsePoints -RootPath $safePath -Label $Label
    Remove-Item -LiteralPath $safePath -Recurse -Force
}

function Get-DspreFieldTextureAnimationAliasMap {
    param([Parameter(Mandatory)]$Descriptor)

    $aliases = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($animation in @($Descriptor.animations)) {
        $normalized = ConvertTo-DspreFieldTextureNormalizedAlias -Name ([string]$animation.texture_name)
        if ($aliases.ContainsKey($normalized)) {
            throw "Field texture animations normalize to the same alias: $normalized"
        }
        $aliases.Add($normalized, $animation)
    }
    return $aliases
}

function Get-DspreFieldTextureMaterialCatalogFingerprint {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][int]$ExpectedCatalogCount
    )

    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
    $rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
    $directories = @(
        Get-ChildItem -LiteralPath $root -Directory -Force |
            Where-Object { $_.Name -match '^matrix_[0-9]{4}(?:_area_[0-9]{4})?$' } |
            Sort-Object Name
    )
    if ($directories.Count -ne $ExpectedCatalogCount) {
        throw "Expected $ExpectedCatalogCount destination material catalogs, found $($directories.Count)."
    }
    $records = [Collections.Generic.List[object]]::new()
    foreach ($directory in $directories) {
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Material catalog directory cannot be a reparse point: $($directory.FullName)"
        }
        $path = Join-Path $directory.FullName "material_catalog.json"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Destination is missing material_catalog.json: $($directory.Name)"
        }
        $item = Get-Item -LiteralPath $path
        $records.Add([pscustomobject][ordered]@{
            relative_path = $item.FullName.Substring($rootPrefix.Length).Replace('\', '/')
            byte_length = [long]$item.Length
            sha256 = Get-DspreFieldTextureFileSha256 -Path $path
        })
    }
    return [pscustomobject]@{
        count = $records.Count
        sha256 = Get-DspreFieldTextureCombinedRecordSha256 -Records @($records)
    }
}

function Get-DspreFieldTexturePackFingerprint {
    param([Parameter(Mandatory)][string]$DspreRoot)

    $root = Join-Path $DspreRoot "unpacked\mapTextures"
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "DSPRE map texture root was not found: $root"
    }
    $records = [Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Force | Sort-Object Name)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Map texture pack cannot be a reparse point: $($file.FullName)"
        }
        $records.Add([pscustomobject][ordered]@{
            relative_path = $file.Name
            byte_length = [long]$file.Length
            sha256 = Get-DspreFieldTextureFileSha256 -Path $file.FullName
        })
    }
    if ($records.Count -eq 0) {
        throw "DSPRE contains no map texture packs."
    }
    return [pscustomobject]@{
        count = $records.Count
        sha256 = Get-DspreFieldTextureCombinedRecordSha256 -Records @($records)
    }
}

function Get-DspreFieldTextureBuildFingerprints {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FldtanimePath,
        [Parameter(Mandatory)][string]$MaterialRoot,
        [Parameter(Mandatory)][int]$ExpectedCatalogCount,
        [Parameter(Mandatory)][string]$DspreRoot
    )

    $catalogFingerprint = Get-DspreFieldTextureMaterialCatalogFingerprint `
        -RootPath $MaterialRoot `
        -ExpectedCatalogCount $ExpectedCatalogCount
    $packFingerprint = Get-DspreFieldTexturePackFingerprint -DspreRoot $DspreRoot
    return [pscustomobject][ordered]@{
        fldtanime_sha256 = Get-DspreFieldTextureFileSha256 -Path $FldtanimePath
        support_sha256 = Get-DspreFieldTextureFileSha256 -Path (Join-Path $PSScriptRoot "dspre_field_texture_animation_support.ps1")
        builder_sha256 = Get-DspreFieldTextureFileSha256 -Path (Join-Path $PSScriptRoot "build_dspre_field_texture_animations.ps1")
        material_catalogs_sha256 = [string]$catalogFingerprint.sha256
        texture_packs_sha256 = [string]$packFingerprint.sha256
    }
}

function Assert-DspreFieldTextureFingerprintsEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual,
        [string]$Label = "Field texture build inputs"
    )

    foreach ($document in @($Expected, $Actual)) {
        $propertyNames = @($document.PSObject.Properties.Name)
        if (
            $propertyNames.Count -ne $script:DspreFieldTextureFingerprintNames.Count -or
            @($propertyNames | Where-Object { $_ -notin $script:DspreFieldTextureFingerprintNames }).Count -ne 0
        ) {
            throw "$Label must contain exactly the five required fingerprints."
        }
    }
    foreach ($name in $script:DspreFieldTextureFingerprintNames) {
        $expectedProperty = $Expected.PSObject.Properties[$name]
        $actualProperty = $Actual.PSObject.Properties[$name]
        if (
            $null -eq $expectedProperty -or
            $null -eq $actualProperty -or
            [string]$expectedProperty.Value -notmatch '^[0-9a-f]{64}$' -or
            [string]$actualProperty.Value -notmatch '^[0-9a-f]{64}$' -or
            [string]$expectedProperty.Value -cne [string]$actualProperty.Value
        ) {
            throw "$Label changed during the field texture build: $name"
        }
    }
    return $true
}

function Assert-DspreFieldTextureBuildInputsCurrent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ExpectedFingerprints,
        [Parameter(Mandatory)][string]$FldtanimePath,
        [Parameter(Mandatory)][string]$MaterialRoot,
        [Parameter(Mandatory)][int]$ExpectedCatalogCount,
        [Parameter(Mandatory)][string]$DspreRoot
    )

    $actualFingerprints = Get-DspreFieldTextureBuildFingerprints `
        -FldtanimePath $FldtanimePath `
        -MaterialRoot $MaterialRoot `
        -ExpectedCatalogCount $ExpectedCatalogCount `
        -DspreRoot $DspreRoot
    $null = Assert-DspreFieldTextureFingerprintsEqual `
        -Expected $ExpectedFingerprints `
        -Actual $actualFingerprints `
        -Label "Field texture publication inputs"
    return $actualFingerprints
}

function Get-DspreFieldTextureMaterialInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)]$Descriptor,
        [Parameter(Mandatory)][int]$ExpectedCatalogCount
    )

    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
    $rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
    $aliasMap = Get-DspreFieldTextureAnimationAliasMap -Descriptor $Descriptor
    $catalogDirectories = @(
        Get-ChildItem -LiteralPath $root -Directory -Force |
            Where-Object { $_.Name -match '^matrix_[0-9]{4}(?:_area_[0-9]{4})?$' } |
            Sort-Object Name
    )
    if ($catalogDirectories.Count -ne $ExpectedCatalogCount) {
        throw "Expected $ExpectedCatalogCount destination material catalogs, found $($catalogDirectories.Count)."
    }

    $catalogRecords = [Collections.Generic.List[object]]::new()
    $variants = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($directory in $catalogDirectories) {
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Material catalog directory cannot be a reparse point: $($directory.FullName)"
        }
        $catalogPath = Join-Path $directory.FullName "material_catalog.json"
        if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
            throw "Destination is missing material_catalog.json: $($directory.Name)"
        }
        $catalogItem = Get-Item -LiteralPath $catalogPath
        $catalogSha = Get-DspreFieldTextureFileSha256 -Path $catalogPath
        $catalogRecords.Add([pscustomobject][ordered]@{
            relative_path = $catalogItem.FullName.Substring($rootPrefix.Length).Replace('\', '/')
            byte_length = [long]$catalogItem.Length
            sha256 = $catalogSha
        })
        $catalog = [IO.File]::ReadAllText($catalogPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ([int]$catalog.schema_version -ne 1 -or $null -eq $catalog.PSObject.Properties["images"]) {
            throw "Destination has an unsupported material catalog: $($directory.Name)"
        }
        foreach ($image in @($catalog.images)) {
            $imageSha = [string]$image.sha256
            if ($imageSha -notmatch '^[0-9a-f]{64}$') {
                throw "Material catalog has an invalid image SHA-256: $($directory.Name)"
            }
            $matchedAnimations = [Collections.Generic.Dictionary[int, object]]::new()
            foreach ($alias in @($image.aliases)) {
                $normalizedAlias = ConvertTo-DspreFieldTextureNormalizedAlias -Name ([string]$alias)
                if ($aliasMap.ContainsKey($normalizedAlias)) {
                    $animation = $aliasMap[$normalizedAlias]
                    $matchedAnimations[[int]$animation.animation_id] = $animation
                }
            }
            if ($matchedAnimations.Count -eq 0) {
                continue
            }
            if ($matchedAnimations.Count -ne 1) {
                throw "One material image binds multiple field texture timelines: $imageSha"
            }
            $animation = @($matchedAnimations.Values)[0]
            $animationId = [int]$animation.animation_id
            $variantKey = "{0:D2}:{1}" -f $animationId, $imageSha
            if ($variants.ContainsKey($variantKey)) {
                continue
            }
            $relativeImagePath = ([string]$image.relative_path).Replace('/', [IO.Path]::DirectorySeparatorChar)
            if (
                [string]::IsNullOrWhiteSpace($relativeImagePath) -or
                [IO.Path]::IsPathRooted($relativeImagePath) -or
                $relativeImagePath -match '(^|[\\/])\.\.([\\/]|$)'
            ) {
                throw "Material catalog has an unsafe image path: $relativeImagePath"
            }
            $imagePath = [IO.Path]::GetFullPath((Join-Path $directory.FullName $relativeImagePath))
            $directoryPrefix = $directory.FullName.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            if (-not $imagePath.StartsWith($directoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Material image escaped its destination root: $imagePath"
            }
            if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
                throw "Material image is missing: $imagePath"
            }
            $imageItem = Get-Item -LiteralPath $imagePath
            if (
                [long]$imageItem.Length -ne [long]$image.byte_length -or
                (Get-DspreFieldTextureFileSha256 -Path $imagePath) -ne $imageSha
            ) {
                throw "Material image content does not match its catalog: $imagePath"
            }
            $variants.Add($variantKey, [pscustomobject][ordered]@{
                animation_id = $animationId
                texture_name = [string]$animation.texture_name
                base_texture_sha256 = $imageSha
                source_path = $imagePath
            })
        }
    }

    return [pscustomobject][ordered]@{
        catalog_count = $catalogRecords.Count
        catalog_records = @($catalogRecords)
        material_catalogs_sha256 = Get-DspreFieldTextureCombinedRecordSha256 -Records @($catalogRecords)
        variants = @($variants.Values | Sort-Object animation_id, base_texture_sha256)
    }
}

function Test-DspreFieldTextureImagesEqual {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual
    )

    $expectedImage = Assert-DspreFieldTextureRgbaImage -Image $Expected
    $actualImage = Assert-DspreFieldTextureRgbaImage -Image $Actual
    if (
        $expectedImage.width -ne $actualImage.width -or
        $expectedImage.height -ne $actualImage.height -or
        $expectedImage.rgba.Length -ne $actualImage.rgba.Length
    ) {
        return $false
    }
    for ($index = 0; $index -lt $expectedImage.rgba.Length; $index++) {
        if ($expectedImage.rgba[$index] -ne $actualImage.rgba[$index]) {
            return $false
        }
    }
    return $true
}

function ConvertTo-DspreFieldTextureRuntimeFrameTexture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$TargetTexture,
        [Parameter(Mandatory)]$SourceFrameTexture
    )

    $targetData = [byte[]]$TargetTexture.data
    $sourceData = [byte[]]$SourceFrameTexture.data
    if ($sourceData.Length -lt $targetData.Length) {
        throw "fldtanime frame data is shorter than the destination texture allocation."
    }
    $runtimeData = [byte[]]::new($targetData.Length)
    if ($runtimeData.Length -gt 0) {
        [Buffer]::BlockCopy($sourceData, 0, $runtimeData, 0, $runtimeData.Length)
    }

    $runtimeData2 = [byte[]]@()
    if ([int]$TargetTexture.format -eq 5) {
        $targetData2 = [byte[]]$TargetTexture.data2
        $sourceData2 = [byte[]]$SourceFrameTexture.data2
        if ($sourceData2.Length -ne $targetData2.Length) {
            throw "fldtanime format-5 frame auxiliary data does not match the destination texture."
        }
        $runtimeData2 = [byte[]]::new($targetData2.Length)
        if ($runtimeData2.Length -gt 0) {
            [Buffer]::BlockCopy($sourceData2, 0, $runtimeData2, 0, $runtimeData2.Length)
        }
    }

    return [pscustomobject][ordered]@{
        format = [int]$TargetTexture.format
        width = [int]$TargetTexture.width
        height = [int]$TargetTexture.height
        color0_transparent = [bool]$TargetTexture.color0_transparent
        data = $runtimeData
        data_sha256 = Get-DspreFieldTextureSha256 -Bytes $runtimeData
        data2 = $runtimeData2
        data2_sha256 = if ($runtimeData2.Length -eq 0) {
            $null
        }
        else {
            Get-DspreFieldTextureSha256 -Bytes $runtimeData2
        }
    }
}

function Get-DspreFieldTextureResourceInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Archive,
        [Parameter(Mandatory)]$Descriptor,
        [Parameter(Mandatory)][string]$DspreRoot
    )

    $animationResources = [Collections.Generic.Dictionary[int, object]]::new()
    foreach ($animation in @($Descriptor.animations)) {
        $memberId = [int]$animation.member_id
        $resource = ConvertFrom-DspreFieldTextureNsbtxBytes `
            -Bytes ([byte[]]$Archive.members[$memberId]) `
            -Label ("fldtanime member {0}" -f $memberId)
        $maximumFrame = [int](@($animation.unique_frame_indices | Measure-Object -Maximum).Maximum)
        if (@($resource.textures).Count -le $maximumFrame) {
            throw "fldtanime member $memberId does not contain frame texture $maximumFrame."
        }
        $animationResources.Add([int]$animation.animation_id, $resource)
    }

    $mapTextureRoot = Join-Path $DspreRoot "unpacked\mapTextures"
    if (-not (Test-Path -LiteralPath $mapTextureRoot -PathType Container)) {
        throw "DSPRE map texture root was not found: $mapTextureRoot"
    }
    $textureCandidates = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    $packRecords = [Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $mapTextureRoot -File -Force | Sort-Object Name)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Map texture pack cannot be a reparse point: $($file.FullName)"
        }
        $packSha = Get-DspreFieldTextureFileSha256 -Path $file.FullName
        $packRecords.Add([pscustomobject][ordered]@{
            relative_path = $file.Name
            byte_length = [long]$file.Length
            sha256 = $packSha
        })
        $resource = ConvertFrom-DspreFieldTextureNsbtxBytes `
            -Bytes ([IO.File]::ReadAllBytes($file.FullName)) `
            -Label ("Map texture pack {0}" -f $file.Name)
        foreach ($texture in @($resource.textures)) {
            $alias = ConvertTo-DspreFieldTextureNormalizedAlias -Name ([string]$texture.name)
            if (-not $textureCandidates.ContainsKey($alias)) {
                $textureCandidates.Add($alias, [Collections.Generic.List[object]]::new())
            }
            $textureCandidates[$alias].Add([pscustomobject]@{
                pack_name = $file.Name
                texture = $texture
                palettes = @($resource.palettes)
            })
        }
    }
    if ($packRecords.Count -eq 0) {
        throw "DSPRE contains no map texture packs."
    }
    return [pscustomobject][ordered]@{
        animation_resources = $animationResources
        texture_candidates = $textureCandidates
        texture_pack_count = $packRecords.Count
        texture_packs_sha256 = Get-DspreFieldTextureCombinedRecordSha256 -Records @($packRecords)
    }
}

function Resolve-DspreFieldTextureMaterialVariants {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Variants,
        [Parameter(Mandatory)]$Descriptor,
        [Parameter(Mandatory)]$ResourceInventory,
        [Parameter(Mandatory)][string]$MaterialRoot
    )

    $animations = [Collections.Generic.Dictionary[int, object]]::new()
    foreach ($animation in @($Descriptor.animations)) {
        $animations.Add([int]$animation.animation_id, $animation)
    }
    $baseDecodeCache = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    $frameSetCache = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    $resolved = [Collections.Generic.List[object]]::new()
    foreach ($variant in @($Variants | Sort-Object animation_id, base_texture_sha256)) {
        $animationId = [int]$variant.animation_id
        $animation = $animations[$animationId]
        $alias = ConvertTo-DspreFieldTextureNormalizedAlias -Name ([string]$animation.texture_name)
        $baseImage = Read-DspreFieldTexturePng `
            -Path ([string]$variant.source_path) `
            -AllowedRoot $MaterialRoot
        $matchingFrameSets = [Collections.Generic.Dictionary[string, object]]::new(
            [StringComparer]::Ordinal
        )
        if ($ResourceInventory.texture_candidates.ContainsKey($alias)) {
            foreach ($candidate in @($ResourceInventory.texture_candidates[$alias])) {
                $paletteChoices = @($candidate.palettes)
                if ([int]$candidate.texture.format -eq 7) {
                    $paletteChoices = @($null)
                }
                foreach ($palette in $paletteChoices) {
                    $paletteIndex = if ($null -eq $palette) { -1 } else { [int]$palette.index }
                    $decodeKey = "{0}:{1}:{2}" -f @(
                        [string]$candidate.pack_name,
                        [int]$candidate.texture.index,
                        $paletteIndex
                    )
                    if (-not $baseDecodeCache.ContainsKey($decodeKey)) {
                        try {
                            $decodedBase = ConvertFrom-DspreFieldTextureTexelData `
                                -Texture $candidate.texture `
                                -Palette $palette
                            $baseDecodeCache.Add($decodeKey, [pscustomobject]@{
                                ok = $true
                                image = $decodedBase
                            })
                        }
                        catch {
                            $baseDecodeCache.Add($decodeKey, [pscustomobject]@{
                                ok = $false
                                image = $null
                            })
                        }
                    }
                    $baseDecode = $baseDecodeCache[$decodeKey]
                    if (-not $baseDecode.ok) {
                        continue
                    }
                    $candidateBase = $baseDecode.image
                    if (-not (Test-DspreFieldTextureImagesEqual -Expected $baseImage -Actual $candidateBase)) {
                        continue
                    }
                    $animationResource = $ResourceInventory.animation_resources[$animationId]
                    $frameSetKey = "{0}:{1}" -f $animationId, $decodeKey
                    if (-not $frameSetCache.ContainsKey($frameSetKey)) {
                        $frameImages = [Collections.Generic.Dictionary[int, object]]::new()
                        $signature = [Text.StringBuilder]::new()
                        $decodeFailed = $false
                        foreach ($frameIndex in @($animation.unique_frame_indices | Sort-Object)) {
                            $sourceFrameTexture = $animationResource.textures[[int]$frameIndex]
                            try {
                                $runtimeTexture = ConvertTo-DspreFieldTextureRuntimeFrameTexture `
                                    -TargetTexture $candidate.texture `
                                    -SourceFrameTexture $sourceFrameTexture
                                $frameImage = ConvertFrom-DspreFieldTextureTexelData `
                                    -Texture $runtimeTexture `
                                    -Palette $palette
                            }
                            catch {
                                $decodeFailed = $true
                                break
                            }
                            if (
                                [int]$frameImage.width -ne [int]$baseImage.width -or
                                [int]$frameImage.height -ne [int]$baseImage.height
                            ) {
                                $decodeFailed = $true
                                break
                            }
                            $frameImages.Add([int]$frameIndex, $frameImage)
                            $null = $signature.Append([string]$frameImage.rgba_sha256)
                            $null = $signature.Append([char]0)
                        }
                        $frameSetCache.Add($frameSetKey, [pscustomobject]@{
                            ok = -not $decodeFailed
                            frames = if ($decodeFailed) { $null } else { $frameImages }
                            signature = if ($decodeFailed) { $null } else {
                                Get-DspreFieldTextureTextSha256 -Text $signature.ToString()
                            }
                        })
                    }
                    $frameSet = $frameSetCache[$frameSetKey]
                    if (-not $frameSet.ok) {
                        continue
                    }
                    $signatureHash = [string]$frameSet.signature
                    if (-not $matchingFrameSets.ContainsKey($signatureHash)) {
                        $matchingFrameSets.Add($signatureHash, [pscustomobject]@{
                            frames = $frameSet.frames
                            pack_name = [string]$candidate.pack_name
                            palette_name = if ($null -eq $palette) { $null } else { [string]$palette.name }
                        })
                    }
                }
            }
        }
        if ($matchingFrameSets.Count -eq 1) {
            $match = @($matchingFrameSets.Values)[0]
            $resolved.Add([pscustomobject][ordered]@{
                animation_id = $animationId
                texture_name = [string]$animation.texture_name
                base_texture_sha256 = [string]$variant.base_texture_sha256
                source_path = [string]$variant.source_path
                disposition = "target_palette_decode"
                reason = $null
                palette_source_pack = [string]$match.pack_name
                palette_name = $match.palette_name
                frame_images = $match.frames
            })
        }
        else {
            $reason = if ($matchingFrameSets.Count -eq 0) {
                "base_palette_unresolved"
            }
            else {
                "base_palette_ambiguous"
            }
            $resolved.Add([pscustomobject][ordered]@{
                animation_id = $animationId
                texture_name = [string]$animation.texture_name
                base_texture_sha256 = [string]$variant.base_texture_sha256
                source_path = [string]$variant.source_path
                disposition = "unsupported_deferred"
                reason = $reason
                palette_source_pack = $null
                palette_name = $null
                frame_images = $null
            })
        }
    }
    $final = [Collections.Generic.List[object]]::new()
    foreach ($group in @($resolved | Group-Object base_texture_sha256 | Sort-Object Name)) {
        $records = @($group.Group | Sort-Object animation_id)
        if ($records.Count -eq 1) {
            $final.Add($records[0])
            continue
        }
        $signatures = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $allReady = $true
        foreach ($record in $records) {
            if ([string]$record.disposition -ne "target_palette_decode") {
                $allReady = $false
                break
            }
            $animation = $animations[[int]$record.animation_id]
            $signature = [Text.StringBuilder]::new()
            foreach ($entry in @($animation.sequence | Sort-Object sequence_index)) {
                $null = $signature.Append(([int]$entry.hold_ticks).ToString())
                $null = $signature.Append(':')
                $null = $signature.Append([string]$record.frame_images[[int]$entry.frame_index].rgba_sha256)
                $null = $signature.Append([char]0)
            }
            $null = $signatures.Add((Get-DspreFieldTextureTextSha256 -Text $signature.ToString()))
        }
        if ($allReady -and $signatures.Count -eq 1) {
            $kept = $records[0]
            $kept | Add-Member -Force -NotePropertyName equivalent_animation_ids -NotePropertyValue @(
                $records | ForEach-Object { [int]$_.animation_id }
            )
            $final.Add($kept)
            continue
        }
        foreach ($record in $records) {
            $final.Add([pscustomobject][ordered]@{
                animation_id = [int]$record.animation_id
                texture_name = [string]$record.texture_name
                base_texture_sha256 = [string]$record.base_texture_sha256
                source_path = [string]$record.source_path
                disposition = "unsupported_deferred"
                reason = "base_texture_sha_ambiguous"
                palette_source_pack = $null
                palette_name = $null
                frame_images = $null
            })
        }
    }
    return @($final)
}

function New-DspreFieldTextureAnimationSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Descriptor,
        [Parameter(Mandatory)][object[]]$Variants,
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)]$Fingerprints,
        [Parameter(Mandatory)][int]$MaterialCatalogCount
    )

    $null = [IO.Directory]::CreateDirectory($StageRoot)
    $frameOutputRoot = Join-Path $StageRoot "frames"
    $null = [IO.Directory]::CreateDirectory($frameOutputRoot)
    $animationById = [Collections.Generic.Dictionary[int, object]]::new()
    foreach ($animation in @($Descriptor.animations)) {
        $animationById.Add([int]$animation.animation_id, $animation)
    }
    $outputFrames = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $bindings = [Collections.Generic.List[object]]::new()
    $deferred = [Collections.Generic.List[object]]::new()
    $matchedAnimationIds = [Collections.Generic.HashSet[int]]::new()

    foreach ($variant in @($Variants | Sort-Object animation_id, base_texture_sha256)) {
        $animationId = [int]$variant.animation_id
        if (-not $animationById.ContainsKey($animationId)) {
            throw "Material variant references an unknown animation: $animationId"
        }
        $null = $matchedAnimationIds.Add($animationId)
        $animation = $animationById[$animationId]
        $bindingId = "fldtex_{0:D2}_{1}" -f $animationId, [string]$variant.base_texture_sha256
        if ([string]$variant.disposition -eq "unsupported_deferred") {
            $deferred.Add([pscustomobject][ordered]@{
                binding_id = $bindingId
                animation_id = $animationId
                texture_name = [string]$animation.texture_name
                base_texture_sha256 = [string]$variant.base_texture_sha256
                disposition = "unsupported_deferred"
                reason = [string]$variant.reason
            })
            continue
        }
        if (
            [string]$variant.disposition -ne "target_palette_decode" -or
            $null -eq $variant.frame_images
        ) {
            throw "Animation variant $bindingId has an unsupported resolution disposition."
        }

        $frameMetadataByIndex = [Collections.Generic.Dictionary[int, object]]::new()
        foreach ($frameIndex in @($animation.unique_frame_indices | Sort-Object)) {
            if (-not $variant.frame_images.ContainsKey([int]$frameIndex)) {
                throw "Animation variant $bindingId is missing frame $frameIndex."
            }
            $converted = $variant.frame_images[[int]$frameIndex]
            $rgbaHash = [string]$converted.rgba_sha256
            if (-not $outputFrames.ContainsKey($rgbaHash)) {
                $outputPath = Join-Path $frameOutputRoot "$rgbaHash.png"
                $written = Write-DspreFieldTexturePng `
                    -Image $converted `
                    -Path $outputPath `
                    -AllowedRoot $StageRoot
                $outputFrames.Add($rgbaHash, [pscustomobject][ordered]@{
                    path = "field_texture_animations/frames/$rgbaHash.png"
                    byte_length = [long]$written.byte_length
                    sha256 = [string]$written.sha256
                })
            }
            $frameMetadataByIndex.Add([int]$frameIndex, $outputFrames[$rgbaHash])
        }
        $timelineFrames = [Collections.Generic.List[object]]::new()
        foreach ($entry in @($animation.sequence | Sort-Object sequence_index)) {
            $metadata = $frameMetadataByIndex[[int]$entry.frame_index]
            $timelineFrames.Add([pscustomobject][ordered]@{
                sequence_index = [int]$entry.sequence_index
                frame_index = [int]$entry.frame_index
                path = [string]$metadata.path
                hold_ticks = [int]$entry.hold_ticks
                byte_length = [long]$metadata.byte_length
                sha256 = [string]$metadata.sha256
            })
        }
        $bindings.Add([pscustomobject][ordered]@{
            binding_id = $bindingId
            animation_id = $animationId
            texture_name = [string]$animation.texture_name
            base_texture_sha256 = [string]$variant.base_texture_sha256
            disposition = "target_palette_decode"
            source_fps = 30
            initial_base_texture = $true
            initial_hold_ticks = [int]$animation.sequence[0].hold_ticks
            cycle_ticks = [int]$animation.cycle_ticks
            frames = @($timelineFrames)
        })
    }

    $sourceAnimationRecords = @($Descriptor.animations | Sort-Object animation_id | ForEach-Object {
        [pscustomobject][ordered]@{
            animation_id = [int]$_.animation_id
            texture_name = [string]$_.texture_name
            member_id = [int]$_.member_id
            cycle_ticks = [int]$_.cycle_ticks
            sequence = @($_.sequence | Sort-Object sequence_index | ForEach-Object {
                [pscustomobject][ordered]@{
                    frame_index = [int]$_.frame_index
                    hold_ticks = [int]$_.hold_ticks
                }
            })
        }
    })
    return [pscustomobject][ordered]@{
        schema_version = 1
        source_fps = 30
        fingerprints = $Fingerprints
        summary = [pscustomobject][ordered]@{
            source_animations = @($Descriptor.animations).Count
            material_catalogs = $MaterialCatalogCount
            matched_variants = @($Variants).Count
            matched_source_animations = $matchedAnimationIds.Count
            unmatched_source_animations = @($Descriptor.animations).Count - $matchedAnimationIds.Count
            ready_bindings = $bindings.Count
            deferred_variants = $deferred.Count
            generated_unique_frames = $outputFrames.Count
        }
        animations = $sourceAnimationRecords
        bindings = @($bindings)
        deferred = @($deferred)
    }
}

function Complete-DspreFieldTextureStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Section,
        [Parameter(Mandatory)][string]$StageRoot,
        [Parameter(Mandatory)]$Fingerprints
    )

    $sectionPath = Join-Path $StageRoot $script:DspreFieldTextureSectionFile
    [IO.File]::WriteAllText(
        $sectionPath,
        ($Section | ConvertTo-Json -Depth 20 -Compress),
        $script:DspreFieldTextureUtf8
    )
    $files = @(Get-DspreStageFileRecords `
        -RootPath $StageRoot `
        -ExcludedRelativePaths @($script:DspreFieldTextureMarkerFile) `
        -Label "Field texture animation stage")
    $marker = [pscustomobject][ordered]@{
        schema_version = 1
        build_contract_version = $script:DspreFieldTextureBuildContract
        fingerprints = $Fingerprints
        section_sha256 = Get-DspreFieldTextureFileSha256 -Path $sectionPath
        files = $files
        completed_utc = [DateTime]::UtcNow.ToString("o")
    }
    [IO.File]::WriteAllText(
        (Join-Path $StageRoot $script:DspreFieldTextureMarkerFile),
        ($marker | ConvertTo-Json -Depth 10 -Compress),
        $script:DspreFieldTextureUtf8
    )
    return $marker
}

function Test-DspreFieldTextureStageReusable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)]$Fingerprints,
        [switch]$IgnoreGodotImportSidecars
    )

    try {
        $markerPath = Join-Path $RootPath $script:DspreFieldTextureMarkerFile
        $sectionPath = Join-Path $RootPath $script:DspreFieldTextureSectionFile
        if (
            -not (Test-Path -LiteralPath $markerPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $sectionPath -PathType Leaf)
        ) {
            return $false
        }
        $marker = [IO.File]::ReadAllText($markerPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if (
            [int]$marker.schema_version -ne 1 -or
            [int]$marker.build_contract_version -ne $script:DspreFieldTextureBuildContract
        ) {
            return $false
        }
        foreach ($property in $Fingerprints.PSObject.Properties) {
            $actualProperty = $marker.fingerprints.PSObject.Properties[$property.Name]
            if ($null -eq $actualProperty -or [string]$actualProperty.Value -cne [string]$property.Value) {
                return $false
            }
        }
        if ((Get-DspreFieldTextureFileSha256 -Path $sectionPath) -ne [string]$marker.section_sha256) {
            return $false
        }
        $null = Assert-DspreStageFileRecords `
            -RootPath $RootPath `
            -ExpectedRecords @($marker.files) `
            -ExcludedRelativePaths @($script:DspreFieldTextureMarkerFile) `
            -IgnoreGodotImportSidecars:$IgnoreGodotImportSidecars `
            -Label "Field texture animation reusable stage"
        $section = [IO.File]::ReadAllText($sectionPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        return (
            [int]$section.schema_version -eq 1 -and
            [int]$section.source_fps -eq 30 -and
            $null -ne $section.PSObject.Properties["bindings"]
        )
    }
    catch {
        return $false
    }
}

function Copy-DspreFieldTextureStage {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$DestinationRoot
    )

    $null = Assert-DspreTreeHasNoReparsePoints -RootPath $SourceRoot -Label "Field texture publish source"
    $null = [IO.Directory]::CreateDirectory($DestinationRoot)
    foreach ($child in @(Get-ChildItem -LiteralPath $SourceRoot -Force)) {
        Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $DestinationRoot $child.Name) -Recurse -Force
    }
}

function Publish-DspreFieldTextureStageDirectories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string[]]$TargetRoots,
        [scriptblock]$FaultInjector = $null
    )

    $source = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\', '/')
    $targets = @($TargetRoots | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\', '/') })
    if ($targets.Count -eq 0) {
        throw "Field texture publication requires at least one target."
    }
    if (@($targets | Sort-Object -Unique).Count -ne $targets.Count) {
        throw "Field texture publication targets must be distinct."
    }
    $marker = [IO.File]::ReadAllText(
        (Join-Path $source $script:DspreFieldTextureMarkerFile),
        [Text.Encoding]::UTF8
    ) | ConvertFrom-Json
    $transactions = [Collections.Generic.List[object]]::new()
    $committed = $false
    try {
        foreach ($target in $targets) {
            $null = Assert-DspreSafeRecursiveDeletePath -Path $target -AllowedRoot $repositoryRoot
            if (Test-Path -LiteralPath $target) {
                $null = Assert-DspreTreeHasNoReparsePoints -RootPath $target -Label "Field texture publish target"
            }
            $incoming = "$target.incoming.$([Guid]::NewGuid().ToString('N'))"
            $backup = "$target.backup.$([Guid]::NewGuid().ToString('N'))"
            $null = Assert-DspreSafeRecursiveDeletePath -Path $incoming -AllowedRoot $repositoryRoot
            $null = Assert-DspreSafeRecursiveDeletePath -Path $backup -AllowedRoot $repositoryRoot
            $transaction = [pscustomobject]@{
                target = $target
                incoming = $incoming
                backup = $backup
                had_target = Test-Path -LiteralPath $target
                promoted = $false
            }
            $transactions.Add($transaction)
            Copy-DspreFieldTextureStage -SourceRoot $source -DestinationRoot $incoming
            $null = Assert-DspreStageFileRecords `
                -RootPath $incoming `
                -ExpectedRecords @($marker.files) `
                -ExcludedRelativePaths @($script:DspreFieldTextureMarkerFile) `
                -Label "Field texture incoming stage"
        }
        foreach ($transaction in $transactions) {
            if ($transaction.had_target) {
                Move-Item -LiteralPath $transaction.target -Destination $transaction.backup
            }
            Move-Item -LiteralPath $transaction.incoming -Destination $transaction.target
            $transaction.promoted = $true
        }
        foreach ($transaction in $transactions) {
            $null = Assert-DspreStageFileRecords `
                -RootPath $transaction.target `
                -ExpectedRecords @($marker.files) `
                -ExcludedRelativePaths @($script:DspreFieldTextureMarkerFile) `
                -Label "Field texture published stage"
        }
        $committed = $true
    }
    catch {
        $failure = $_
        if (-not $committed) {
            foreach ($transaction in @($transactions | Sort-Object { [array]::IndexOf($targets, $_.target) } -Descending)) {
                if ($transaction.promoted -and (Test-Path -LiteralPath $transaction.target)) {
                    Remove-DspreFieldTextureDirectory -Path $transaction.target -Label "Field texture failed promotion"
                }
                if (Test-Path -LiteralPath $transaction.backup) {
                    Move-Item -LiteralPath $transaction.backup -Destination $transaction.target
                }
                if (Test-Path -LiteralPath $transaction.incoming) {
                    Remove-DspreFieldTextureDirectory -Path $transaction.incoming -Label "Field texture failed incoming"
                }
            }
        }
        throw $failure
    }

    $cleanupFailures = [Collections.Generic.List[object]]::new()
    foreach ($transaction in $transactions) {
        if (-not (Test-Path -LiteralPath $transaction.backup)) {
            continue
        }
        try {
            if ($null -ne $FaultInjector) {
                $null = & $FaultInjector "before_backup_cleanup" $transaction
            }
            Remove-DspreFieldTextureDirectory `
                -Path $transaction.backup `
                -Label "Field texture committed publish backup"
        }
        catch {
            $cleanupFailures.Add([pscustomobject][ordered]@{
                target = [string]$transaction.target
                backup = [string]$transaction.backup
                error = [string]$_.Exception.Message
            })
            Write-Warning "Field texture publication committed, but backup cleanup failed: $($transaction.backup)"
        }
    }
    return [pscustomobject][ordered]@{
        committed = $true
        changed = $true
        backup_cleanup_failures = @($cleanupFailures)
    }
}

function Invoke-DspreFieldTextureAnimationBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$MaterialRoot,
        [Parameter(Mandatory)][string]$GeneratedRoot,
        [Parameter(Mandatory)][string]$GodotRoot,
        [Parameter(Mandatory)][string]$BuildWorkRoot,
        [Parameter(Mandatory)][int]$ExpectedCatalogCount,
        [switch]$Rebuild
    )

    $sourceRootFull = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $sourceRootFull -PathType Container)) {
        throw "DSPRE contents root was not found: $sourceRootFull"
    }
    $fldtanimePath = Join-Path $sourceRootFull "files\data\fldtanime.narc"
    if (-not (Test-Path -LiteralPath $fldtanimePath -PathType Leaf)) {
        throw "DSPRE fldtanime.narc was not found: $fldtanimePath"
    }
    $materialRootFull = [IO.Path]::GetFullPath($MaterialRoot).TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $materialRootFull -PathType Container)) {
        throw "Deduplicated destination root was not found: $materialRootFull"
    }

    $expectedGeneratedRoot = [IO.Path]::GetFullPath(
        (Join-Path $materialRootFull "field_texture_animations")
    ).TrimEnd('\', '/')
    if (-not [IO.Path]::GetFullPath($GeneratedRoot).TrimEnd('\', '/').Equals(
        $expectedGeneratedRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Field texture generated output must be $expectedGeneratedRoot"
    }
    $generatedBoundary = Join-Path $repositoryRoot "generated"
    $godotBoundary = Join-Path $repositoryRoot "new-game-project\assets\platinum"
    $workBoundary = Join-Path $repositoryRoot ".work"
    foreach ($boundary in @($generatedBoundary, $godotBoundary, $workBoundary)) {
        if (-not (Test-Path -LiteralPath $boundary -PathType Container)) {
            $null = [IO.Directory]::CreateDirectory($boundary)
        }
    }
    $generatedRootFull = Resolve-DspreFieldTextureStrictDescendant `
        -Path $GeneratedRoot -Boundary $generatedBoundary -Label "Field texture generated root"
    $godotRootFull = Resolve-DspreFieldTextureStrictDescendant `
        -Path $GodotRoot -Boundary $godotBoundary -Label "Field texture Godot root"
    $workRootFull = Resolve-DspreFieldTextureStrictDescendant `
        -Path $BuildWorkRoot -Boundary $workBoundary -Label "Field texture work root"

    $fingerprints = Get-DspreFieldTextureBuildFingerprints `
        -FldtanimePath $fldtanimePath `
        -MaterialRoot $materialRootFull `
        -ExpectedCatalogCount $ExpectedCatalogCount `
        -DspreRoot $sourceRootFull

    if (-not $Rebuild -and (Test-DspreFieldTextureStageReusable `
        -RootPath $generatedRootFull `
        -Fingerprints $fingerprints)) {
        $godotStageRepaired = $false
        if (-not (Test-DspreFieldTextureStageReusable `
            -RootPath $godotRootFull `
            -Fingerprints $fingerprints `
            -IgnoreGodotImportSidecars)) {
            $null = Assert-DspreFieldTextureBuildInputsCurrent `
                -ExpectedFingerprints $fingerprints `
                -FldtanimePath $fldtanimePath `
                -MaterialRoot $materialRootFull `
                -ExpectedCatalogCount $ExpectedCatalogCount `
                -DspreRoot $sourceRootFull
            $null = Publish-DspreFieldTextureStageDirectories `
                -SourceRoot $generatedRootFull `
                -TargetRoots @($godotRootFull)
            $godotStageRepaired = $true
        }
        $section = [IO.File]::ReadAllText(
            (Join-Path $generatedRootFull $script:DspreFieldTextureSectionFile),
            [Text.Encoding]::UTF8
        ) | ConvertFrom-Json
        return [pscustomobject][ordered]@{
            reused = $true
            generated_stage_changed = $false
            godot_stage_repaired = $godotStageRepaired
            godot_stage_changed = $godotStageRepaired
            section_path = Join-Path $generatedRootFull $script:DspreFieldTextureSectionFile
            godot_section_path = Join-Path $godotRootFull $script:DspreFieldTextureSectionFile
            summary = $section.summary
        }
    }

    $archive = Read-DspreNarcArchive `
        -Path $fldtanimePath `
        -AllowedRoot $sourceRootFull `
        -Label "DSPRE fldtanime"
    $descriptor = ConvertFrom-DspreFieldTextureAnimationArchive -Archive $archive
    $inventory = Get-DspreFieldTextureMaterialInventory `
        -RootPath $materialRootFull `
        -Descriptor $descriptor `
        -ExpectedCatalogCount $ExpectedCatalogCount
    $resourceInventory = Get-DspreFieldTextureResourceInventory `
        -Archive $archive `
        -Descriptor $descriptor `
        -DspreRoot $sourceRootFull
    if (
        [string]$inventory.material_catalogs_sha256 -ne [string]$fingerprints.material_catalogs_sha256 -or
        [string]$resourceInventory.texture_packs_sha256 -ne [string]$fingerprints.texture_packs_sha256
    ) {
        throw "Field texture inputs changed while the global stage was being prepared."
    }

    Remove-DspreFieldTextureDirectory -Path $workRootFull -Label "Field texture build work"
    $null = [IO.Directory]::CreateDirectory($workRootFull)
    $stageRoot = Join-Path $workRootFull "stage"
    $null = [IO.Directory]::CreateDirectory($stageRoot)
    $resolvedVariants = Resolve-DspreFieldTextureMaterialVariants `
        -Variants @($inventory.variants) `
        -Descriptor $descriptor `
        -ResourceInventory $resourceInventory `
        -MaterialRoot $materialRootFull
    $section = New-DspreFieldTextureAnimationSection `
        -Descriptor $descriptor `
        -Variants @($resolvedVariants) `
        -StageRoot $stageRoot `
        -Fingerprints $fingerprints `
        -MaterialCatalogCount $inventory.catalog_count
    $null = Complete-DspreFieldTextureStage `
        -Section $section `
        -StageRoot $stageRoot `
        -Fingerprints $fingerprints
    $null = Assert-DspreFieldTextureBuildInputsCurrent `
        -ExpectedFingerprints $fingerprints `
        -FldtanimePath $fldtanimePath `
        -MaterialRoot $materialRootFull `
        -ExpectedCatalogCount $ExpectedCatalogCount `
        -DspreRoot $sourceRootFull
    $null = Publish-DspreFieldTextureStageDirectories `
        -SourceRoot $stageRoot `
        -TargetRoots @($generatedRootFull, $godotRootFull)
    return [pscustomobject][ordered]@{
        reused = $false
        generated_stage_changed = $true
        godot_stage_repaired = $false
        godot_stage_changed = $true
        section_path = Join-Path $generatedRootFull $script:DspreFieldTextureSectionFile
        godot_section_path = Join-Path $godotRootFull $script:DspreFieldTextureSectionFile
        summary = $section.summary
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    foreach ($required in @(
        [pscustomobject]@{ name = "DspreContents"; value = $DspreContents }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$required.value)) {
            throw "$($required.name) is required."
        }
    }
    if ([string]::IsNullOrWhiteSpace($DedupRoot)) {
        $DedupRoot = Join-Path $repositoryRoot "generated\dspre_glb_dedup"
    }
    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        $OutputRoot = Join-Path $DedupRoot "field_texture_animations"
    }
    if ([string]::IsNullOrWhiteSpace($GodotOutputRoot)) {
        $GodotOutputRoot = Join-Path $repositoryRoot "new-game-project\assets\platinum\field_texture_animations"
    }
    if ([string]::IsNullOrWhiteSpace($WorkRoot)) {
        $WorkRoot = Join-Path $repositoryRoot ".work\dspre_field_texture_animations"
    }
    $result = Invoke-DspreFieldTextureAnimationBuild `
        -SourceRoot $DspreContents `
        -MaterialRoot $DedupRoot `
        -GeneratedRoot $OutputRoot `
        -GodotRoot $GodotOutputRoot `
        -BuildWorkRoot $WorkRoot `
        -ExpectedCatalogCount $ExpectedMaterialCatalogCount `
        -Rebuild:$Force
    Write-Host ("Field texture animations: {0} ready, {1} deferred, {2} unique frames{3}." -f @(
        [int]$result.summary.ready_bindings,
        [int]$result.summary.deferred_variants,
        [int]$result.summary.generated_unique_frames,
        $(if ($result.reused) { " (reused)" } else { "" })
    ))
    Write-Output $result
}
