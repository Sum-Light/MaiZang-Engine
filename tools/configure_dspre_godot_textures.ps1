[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotPath = ""
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
$textureRoot = Join-Path $ProjectRoot "assets\platinum\matrix_0000\shared\textures"
$cacheRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot ".godot\imported")).TrimEnd('\') + '\'
$utf8NoBom = [Text.UTF8Encoding]::new($false)

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable was not found: $GodotPath"
}

$deadline = [DateTime]::UtcNow.AddMinutes(3)
do {
    $pngFiles = @(Get-ChildItem -LiteralPath $textureRoot -Filter "*.png" -File)
    $importFiles = @(Get-ChildItem -LiteralPath $textureRoot -Filter "*.png.import" -File)
    if ($pngFiles.Count -eq 480 -and $importFiles.Count -eq 480) {
        break
    }
    Start-Sleep -Milliseconds 500
} while ([DateTime]::UtcNow -lt $deadline)

if ($pngFiles.Count -ne 480 -or $importFiles.Count -ne 480) {
    throw "Expected 480 PNGs and import sidecars, found $($pngFiles.Count) PNGs and $($importFiles.Count) sidecars."
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
        $relativePath = $pathMatch.Groups[1].Value.Substring("res://".Length).Replace('/', '\')
        $cachePath = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $relativePath))
        if (-not $cachePath.StartsWith($cacheRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove cache outside the Godot imported directory: $cachePath"
        }
        $null = $cachePaths.Add($cachePath)
    }
}

$removedCaches = 0
foreach ($cachePath in $cachePaths) {
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        Remove-Item -LiteralPath $cachePath -Force
        $removedCaches++
    }
}

Write-Host "Configured 480 lossless textures and removed $removedCaches stale caches."
& $GodotPath --headless --path $ProjectRoot --import
if ($LASTEXITCODE -ne 0) {
    throw "Godot texture reimport failed with exit code $LASTEXITCODE."
}

$invalidImports = @(
    Get-ChildItem -LiteralPath $textureRoot -Filter "*.png.import" -File | Where-Object {
        $text = Get-Content -LiteralPath $_.FullName -Raw
        $text -notmatch '(?m)^compress/mode=0$' -or $text -notmatch '(?m)^mipmaps/generate=false$'
    }
)
if ($invalidImports.Count -ne 0) {
    throw "$($invalidImports.Count) texture imports do not retain lossless/no-mipmap settings."
}

Write-Host "Godot texture configuration complete."
