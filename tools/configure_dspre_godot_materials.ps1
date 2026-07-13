[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotPath = "",
    [int]$LimitAssets = 0,
    [switch]$SkipMaterialBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $workspaceRoot "new-game-project"
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Users\YbbNa\Downloads\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe"
}

$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$GodotPath = [IO.Path]::GetFullPath($GodotPath)
$platinumRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot "assets\platinum")).TrimEnd('\')
$catalogPath = Join-Path $platinumRoot "matrix_catalog.json"
$cacheRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot ".godot\imported")).TrimEnd('\') + '\'

function Get-RequiredProperty {
    param($Object, [string]$Name, [string]$Label)

    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "$Label is missing required property '$Name'."
    }
    return $Object.$Name
}

function Resolve-PathUnderRoot {
    param([string]$Root, [string]$RelativePath, [string]$Label)

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw "$Label must be a relative path: $RelativePath"
    }
    $rootPrefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $fullPath = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath.Replace('/', '\')))
    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label resolves outside its allowed root: $fullPath"
    }
    return $fullPath
}

function Read-JsonFile {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not found: $Path"
    }
    try {
        return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    catch {
        throw "$Label is not valid JSON: $Path`n$($_.Exception.Message)"
    }
}

function Get-MatrixDestinations {
    param($Catalog, [string]$AssetRoot)

    $destinations = @(Get-RequiredProperty $Catalog "destinations" "Matrix catalog")
    if ($destinations.Count -eq 0) {
        throw "Matrix catalog contains no ready destinations: $catalogPath"
    }

    $destinationKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    $manifestPaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($destination in $destinations) {
        $key = [string](Get-RequiredProperty $destination "key" "Matrix catalog destination")
        if ([string]::IsNullOrWhiteSpace($key) -or -not $destinationKeys.Add($key)) {
            throw "Matrix catalog contains an empty or duplicate destination key: $key"
        }

        $manifestRelative = [string](Get-RequiredProperty $destination "manifest" "Destination $key")
        $manifestPath = Resolve-PathUnderRoot $AssetRoot $manifestRelative "Destination $key manifest"
        if (-not $manifestPaths.Add($manifestPath)) {
            throw "Matrix catalog destination $key reuses a manifest: $manifestPath"
        }
        $manifest = Read-JsonFile $manifestPath "Destination $key manifest"
        if ([int]$manifest.schema_version -ne 3) {
            throw "Destination $key manifest schema 3 is required."
        }
        $variantRoot = Split-Path -Parent $manifestPath

        $assets = Get-RequiredProperty $manifest "assets" "Destination $key manifest"
        $glbPaths = New-Object System.Collections.Generic.List[string]
        $uniqueGlbPaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
        foreach ($groupName in @("terrain", "buildings")) {
            $groupAssets = @(Get-RequiredProperty $assets $groupName "Destination $key assets")
            foreach ($asset in $groupAssets) {
                $assetKey = [string](Get-RequiredProperty $asset "key" "Destination $key $groupName asset")
                $outputGlbs = @(Get-RequiredProperty $asset "output_glbs" "Destination $key asset $assetKey")
                if ($outputGlbs.Count -eq 0) {
                    throw "Destination $key asset $assetKey has no output GLB."
                }
                foreach ($outputGlb in $outputGlbs) {
                    $glbPath = Resolve-PathUnderRoot $variantRoot ([string]$outputGlb) "Destination $key GLB"
                    if ([IO.Path]::GetExtension($glbPath) -ne ".glb") {
                        throw "Destination $key manifest contains a non-GLB output: $glbPath"
                    }
                    if (-not (Test-Path -LiteralPath $glbPath -PathType Leaf)) {
                        throw "Destination $key GLB was not found: $glbPath"
                    }
                    if (-not $uniqueGlbPaths.Add($glbPath)) {
                        throw "Destination $key manifest references a GLB more than once: $glbPath"
                    }
                    $glbPaths.Add($glbPath)
                }
            }
        }
        if ($glbPaths.Count -eq 0) {
            throw "Destination $key manifest contains no GLBs."
        }

        $actualGlbCount = @(Get-ChildItem -LiteralPath $variantRoot -Recurse -Filter "*.glb" -File).Count
        if ($actualGlbCount -ne $glbPaths.Count) {
            throw "Destination $key expected $($glbPaths.Count) manifest GLBs, found $actualGlbCount files."
        }

        $dedupe = Get-RequiredProperty $manifest "material_dedupe" "Destination $key manifest"
        $expectedPngCount = [int](Get-RequiredProperty $dedupe "unique_images" "Destination $key material_dedupe")
        if ($expectedPngCount -lt 0) {
            throw "Destination $key has a negative expected PNG count."
        }
        $textureRelative = [string](Get-RequiredProperty $dedupe "shared_texture_root" "Destination $key material_dedupe")
        $textureRoot = Resolve-PathUnderRoot $variantRoot $textureRelative "Destination $key texture root"
        if (-not (Test-Path -LiteralPath $textureRoot -PathType Container)) {
            throw "Destination $key texture root was not found: $textureRoot"
        }
        $actualPngCount = @(Get-ChildItem -LiteralPath $textureRoot -Filter "*.png" -File).Count
        if ($actualPngCount -ne $expectedPngCount) {
            throw "Destination $key expected $expectedPngCount manifest PNGs, found $actualPngCount files."
        }

        if ($null -ne $destination.PSObject.Properties["glbs"] -and
            [int]$destination.glbs -ne $glbPaths.Count) {
            throw "Destination $key catalog/manifest GLB counts differ: $($destination.glbs)/$($glbPaths.Count)."
        }
        if ($null -ne $destination.PSObject.Properties["textures"] -and
            [int]$destination.textures -ne $expectedPngCount) {
            throw "Destination $key catalog/manifest PNG counts differ: $($destination.textures)/$expectedPngCount."
        }

        $results.Add([pscustomobject]@{
            Key = $key
            ManifestPath = $manifestPath
            VariantRoot = $variantRoot
            GlbPaths = [string[]]$glbPaths.ToArray()
            TextureRoot = $textureRoot
            ExpectedPngCount = $expectedPngCount
        })
    }
    return @($results.ToArray())
}

function Test-TextureImportSettings {
    param([IO.FileInfo[]]$ImportFiles)

    return @(
        $ImportFiles | Where-Object {
            $text = Get-Content -LiteralPath $_.FullName -Raw
            $text -notmatch '(?m)^compress/mode=0$' -or
                $text -notmatch '(?m)^mipmaps/generate=false$' -or
                $text -notmatch '(?m)^detect_3d/compress_to=0$'
        }
    )
}

if ($LimitAssets -lt 0) {
    throw "LimitAssets cannot be negative."
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) {
    throw "Godot project was not found: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable was not found: $GodotPath"
}

$catalog = Read-JsonFile $catalogPath "Matrix catalog"
if ([int]$catalog.schema_version -ne 2) {
    throw "Matrix catalog schema 2 is required."
}
$matrixDestinations = @(Get-MatrixDestinations $catalog $platinumRoot)
$expectedGlbCount = 0
$expectedPngCount = 0
foreach ($destination in $matrixDestinations) {
    $expectedGlbCount += $destination.GlbPaths.Count
    $expectedPngCount += $destination.ExpectedPngCount
}

if ($SkipMaterialBuild) {
    if ($LimitAssets -gt 0) {
        throw "SkipMaterialBuild cannot be combined with LimitAssets."
    }
    $sharedMaterialRoot = Join-Path $platinumRoot "shared_materials"
    $expectedMaterialCount = [int](Get-RequiredProperty $catalog.summary "unique_materials" "Matrix catalog summary")
    $actualMaterialCount = @(
        Get-ChildItem -LiteralPath $sharedMaterialRoot -Filter "*.tres" -File -ErrorAction SilentlyContinue
    ).Count
    if ($actualMaterialCount -ne $expectedMaterialCount) {
        throw "Cannot skip material build: expected $expectedMaterialCount shared materials, found $actualMaterialCount."
    }
    Write-Host "Reusing $actualMaterialCount catalog-wide shared materials."
}
else {
    $buildArguments = @(
        "--headless",
        "--path", $ProjectRoot,
        "--script", "res://tools/build_shared_materials.gd"
    )
    if ($LimitAssets -gt 0) {
        $buildArguments += @("--", "--limit-assets=$LimitAssets")
    }
    & $GodotPath @buildArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Shared material generation failed with exit code $LASTEXITCODE."
    }
}

$configuredImports = New-Object System.Collections.Generic.List[IO.FileInfo]
$allGlbImports = New-Object System.Collections.Generic.List[IO.FileInfo]
foreach ($destination in $matrixDestinations) {
    foreach ($glbPath in $destination.GlbPaths) {
        $importPath = "$glbPath.import"
        if (-not (Test-Path -LiteralPath $importPath -PathType Leaf)) {
            throw "Godot GLB import sidecar was not found: $importPath"
        }
        $importFile = Get-Item -LiteralPath $importPath
        $allGlbImports.Add($importFile)
        $text = Get-Content -LiteralPath $importFile.FullName -Raw
        if ($text -match '"use_external/enabled"\s*:\s*true') {
            $configuredImports.Add($importFile)
        }
    }
}

if ($LimitAssets -le 0 -and $configuredImports.Count -ne $expectedGlbCount) {
    $missingImports = @(
        $allGlbImports | Where-Object {
            $text = Get-Content -LiteralPath $_.FullName -Raw
            $text -notmatch '"use_external/enabled"\s*:\s*true'
        }
    )
    Write-Warning "Retrying external material mappings for $($missingImports.Count) GLBs."
    $retryArguments = @(
        "--headless",
        "--path", $ProjectRoot,
        "--script", "res://tools/build_shared_materials.gd",
        "--",
        "--reuse-existing-materials"
    )
    foreach ($importFile in $missingImports) {
        $glbPath = $importFile.FullName.Substring(0, $importFile.FullName.Length - ".import".Length)
        if (-not $glbPath.StartsWith($ProjectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "GLB import resolves outside the Godot project: $($importFile.FullName)"
        }
        $resourcePath = "res://" + $glbPath.Substring($ProjectRoot.Length + 1).Replace('\', '/')
        $retryArguments += "--asset=$resourcePath"
    }
    & $GodotPath @retryArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Focused shared material retry failed with exit code $LASTEXITCODE."
    }
    $configuredImports.Clear()
    foreach ($importFile in $allGlbImports) {
        $text = Get-Content -LiteralPath $importFile.FullName -Raw
        if ($text -match '"use_external/enabled"\s*:\s*true') {
            $configuredImports.Add($importFile)
        }
    }
    if ($configuredImports.Count -ne $expectedGlbCount) {
        throw "Expected external material mappings on $expectedGlbCount GLBs after focused retry, found $($configuredImports.Count)."
    }
}
if ($LimitAssets -gt 0 -and $configuredImports.Count -lt [Math]::Min($LimitAssets, $expectedGlbCount)) {
    throw "Expected at least $([Math]::Min($LimitAssets, $expectedGlbCount)) configured GLBs, found $($configuredImports.Count)."
}

$removedSceneCaches = 0
foreach ($importFile in $configuredImports) {
    $text = Get-Content -LiteralPath $importFile.FullName -Raw
    $match = [regex]::Match($text, '(?m)^path="([^"]+\.scn)"$')
    if (-not $match.Success) {
        throw "Could not find imported scene cache path in $($importFile.FullName)"
    }
    $resourcePath = $match.Groups[1].Value
    if (-not $resourcePath.StartsWith("res://", [StringComparison]::Ordinal)) {
        throw "Scene cache path is not project-relative in $($importFile.FullName): $resourcePath"
    }
    $relativeCache = $resourcePath.Substring("res://".Length).Replace('/', '\')
    $cachePath = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $relativeCache))
    if (-not $cachePath.StartsWith($cacheRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove cache outside the Godot imported directory: $cachePath"
    }
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        Remove-Item -LiteralPath $cachePath -Force
        $removedSceneCaches++
    }
}

& (Join-Path $PSScriptRoot "configure_dspre_godot_textures.ps1") `
    -ProjectRoot $ProjectRoot `
    -GodotPath $GodotPath `
    -DeferReimport

Write-Host "Configured $($configuredImports.Count) of $expectedGlbCount GLBs across $($matrixDestinations.Count) destinations and removed $removedSceneCaches stale scene caches."
& $GodotPath --headless --path $ProjectRoot --import
if ($LASTEXITCODE -ne 0) {
    throw "Godot reimport failed with exit code $LASTEXITCODE."
}

$unmappedImports = @(
    $allGlbImports | Where-Object {
        $text = Get-Content -LiteralPath $_.FullName -Raw
        $text -notmatch '"use_external/enabled"\s*:\s*true'
    }
)
if ($LimitAssets -le 0 -and $unmappedImports.Count -ne 0) {
    throw "$($unmappedImports.Count) GLB imports do not retain external material mappings."
}

$textureImports = @(
    foreach ($destination in $matrixDestinations) {
        $destinationImports = @(Get-ChildItem -LiteralPath $destination.TextureRoot -Filter "*.png.import" -File)
        if ($destinationImports.Count -ne $destination.ExpectedPngCount) {
            throw "Destination $($destination.Key) expected $($destination.ExpectedPngCount) texture import sidecars after reimport, found $($destinationImports.Count)."
        }
        $destinationImports
    }
)
if ($textureImports.Count -ne $expectedPngCount) {
    throw "Expected $expectedPngCount texture import sidecars after reimport, found $($textureImports.Count)."
}
$invalidTextureImports = @(Test-TextureImportSettings $textureImports)
if ($invalidTextureImports.Count -ne 0) {
    Write-Warning "Repairing $($invalidTextureImports.Count) texture imports changed during reimport."
    & (Join-Path $PSScriptRoot "configure_dspre_godot_textures.ps1") `
        -ProjectRoot $ProjectRoot `
        -GodotPath $GodotPath `
        -RepairInvalidOnly
    $invalidTextureImports = @(Test-TextureImportSettings $textureImports)
    if ($invalidTextureImports.Count -ne 0) {
        throw "$($invalidTextureImports.Count) texture imports do not retain lossless/no-mipmap settings after focused repair."
    }
}

if ($LimitAssets -le 0) {
    & $GodotPath --headless --path $ProjectRoot --script "res://tools/validate_shared_materials.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Shared material validation failed with exit code $LASTEXITCODE."
    }
}

Write-Host "Godot shared material configuration complete: $expectedGlbCount GLBs and $expectedPngCount textures."
