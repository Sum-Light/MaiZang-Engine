[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotPath = "",
    [switch]$DeferReimport,
    [switch]$RepairInvalidOnly
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
$utf8NoBom = New-Object Text.UTF8Encoding($false)

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

function Get-TextureDestinations {
    param($Catalog, [string]$AssetRoot)

    $destinations = @(Get-RequiredProperty $Catalog "destinations" "Matrix catalog")
    if ($destinations.Count -eq 0) {
        throw "Matrix catalog contains no ready destinations: $catalogPath"
    }

    $destinationKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    $manifestPaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    $textureRoots = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
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
        $dedupe = Get-RequiredProperty $manifest "material_dedupe" "Destination $key manifest"
        $expectedPngCount = [int](Get-RequiredProperty $dedupe "unique_images" "Destination $key material_dedupe")
        if ($expectedPngCount -lt 0) {
            throw "Destination $key has a negative expected PNG count."
        }

        $variantRoot = Split-Path -Parent $manifestPath
        $textureRelative = [string](Get-RequiredProperty $dedupe "shared_texture_root" "Destination $key material_dedupe")
        $textureRoot = Resolve-PathUnderRoot $variantRoot $textureRelative "Destination $key texture root"
        if (-not (Test-Path -LiteralPath $textureRoot -PathType Container)) {
            throw "Destination $key texture root was not found: $textureRoot"
        }
        if (-not $textureRoots.Add($textureRoot)) {
            throw "Matrix catalog destinations share a texture root unexpectedly: $textureRoot"
        }

        if ($null -ne $destination.PSObject.Properties["textures"] -and
            [int]$destination.textures -ne $expectedPngCount) {
            throw "Destination $key catalog/manifest PNG counts differ: $($destination.textures)/$expectedPngCount."
        }

        $results.Add([pscustomobject]@{
            Key = $key
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

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) {
    throw "Godot project was not found: $ProjectRoot"
}
if ($DeferReimport -and $RepairInvalidOnly) {
    throw "RepairInvalidOnly cannot be combined with DeferReimport."
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable was not found: $GodotPath"
}

$catalog = Read-JsonFile $catalogPath "Matrix catalog"
$textureDestinations = @(Get-TextureDestinations $catalog $platinumRoot)
$expectedTextureCount = 0
foreach ($destination in $textureDestinations) {
    $expectedTextureCount += $destination.ExpectedPngCount
}

$pngFiles = @()
$importFiles = @()
$deadline = [DateTime]::UtcNow.AddMinutes(3)
do {
    $pngFiles = @(
        foreach ($destination in $textureDestinations) {
            Get-ChildItem -LiteralPath $destination.TextureRoot -Filter "*.png" -File
        }
    )
    $importFiles = @(
        foreach ($destination in $textureDestinations) {
            Get-ChildItem -LiteralPath $destination.TextureRoot -Filter "*.png.import" -File
        }
    )
    if ($pngFiles.Count -eq $expectedTextureCount -and $importFiles.Count -eq $expectedTextureCount) {
        break
    }
    Start-Sleep -Milliseconds 500
} while ([DateTime]::UtcNow -lt $deadline)

foreach ($destination in $textureDestinations) {
    $destinationPngs = @(Get-ChildItem -LiteralPath $destination.TextureRoot -Filter "*.png" -File)
    $destinationImports = @(Get-ChildItem -LiteralPath $destination.TextureRoot -Filter "*.png.import" -File)
    if ($destinationPngs.Count -ne $destination.ExpectedPngCount -or
        $destinationImports.Count -ne $destination.ExpectedPngCount) {
        throw "Destination $($destination.Key) expected $($destination.ExpectedPngCount) PNGs and import sidecars, found $($destinationPngs.Count) PNGs and $($destinationImports.Count) sidecars."
    }
}
$allImportFiles = @($importFiles)
if ($RepairInvalidOnly) {
    $importFiles = @(Test-TextureImportSettings $allImportFiles)
    if ($importFiles.Count -eq 0) {
        Write-Host "All $expectedTextureCount texture imports already retain lossless/no-mipmap settings."
        return
    }
    Write-Warning "Repairing $($importFiles.Count) texture import sidecars."
}

$cachePaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
foreach ($importFile in $importFiles) {
    $text = Get-Content -LiteralPath $importFile.FullName -Raw
    $text = [regex]::Replace($text, '(?m)^compress/mode=\d+$', 'compress/mode=0')
    $text = [regex]::Replace($text, '(?m)^mipmaps/generate=(?:true|false)$', 'mipmaps/generate=false')
    $text = [regex]::Replace($text, '(?m)^detect_3d/compress_to=\d+$', 'detect_3d/compress_to=0')
    [IO.File]::WriteAllText($importFile.FullName, $text, $utf8NoBom)

    $destMatch = [regex]::Match($text, '(?m)^dest_files=\[(.+)\]$')
    if (-not $destMatch.Success) {
        throw "Could not read texture cache paths from $($importFile.FullName)"
    }
    foreach ($pathMatch in [regex]::Matches($destMatch.Groups[1].Value, '"([^"]+)"')) {
        $resourcePath = $pathMatch.Groups[1].Value
        if (-not $resourcePath.StartsWith("res://", [StringComparison]::Ordinal)) {
            throw "Texture cache path is not project-relative in $($importFile.FullName): $resourcePath"
        }
        $relativePath = $resourcePath.Substring("res://".Length).Replace('/', '\')
        $cachePath = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $relativePath))
        if (-not $cachePath.StartsWith($cacheRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove cache outside the Godot imported directory: $cachePath"
        }
        $null = $cachePaths.Add($cachePath)
    }
}

$invalidImports = @(Test-TextureImportSettings $importFiles)
if ($invalidImports.Count -ne 0) {
    throw "$($invalidImports.Count) texture imports could not be configured as lossless/no-mipmap."
}

$removedCaches = 0
foreach ($cachePath in $cachePaths) {
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        Remove-Item -LiteralPath $cachePath -Force
        $removedCaches++
    }
}

Write-Host "Configured $($importFiles.Count) lossless textures across $($textureDestinations.Count) destinations and removed $removedCaches stale caches."
if ($DeferReimport) {
    Write-Host "Godot texture reimport deferred to the calling workflow."
    return
}

& $GodotPath --headless --path $ProjectRoot --import
if ($LASTEXITCODE -ne 0) {
    throw "Godot texture reimport failed with exit code $LASTEXITCODE."
}

$validationImports = if ($RepairInvalidOnly) { $allImportFiles } else { $importFiles }
$invalidImports = @(Test-TextureImportSettings $validationImports)
if ($invalidImports.Count -ne 0) {
    throw "$($invalidImports.Count) texture imports do not retain lossless/no-mipmap settings."
}

Write-Host "Godot texture configuration complete."
