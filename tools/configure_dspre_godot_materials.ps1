[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotPath = "",
    [int]$LimitAssets = 0
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
$matrixRoot = Join-Path $ProjectRoot "assets\platinum\matrix_0000"
$cacheRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot ".godot\imported")).TrimEnd('\') + '\'

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) {
    throw "Godot project was not found: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable was not found: $GodotPath"
}
if (-not (Test-Path -LiteralPath $matrixRoot -PathType Container)) {
    throw "Synced DSPRE assets were not found: $matrixRoot"
}

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

$configuredImports = New-Object System.Collections.Generic.List[IO.FileInfo]
foreach ($importFile in Get-ChildItem -LiteralPath $matrixRoot -Recurse -Filter "*.glb.import" -File) {
    $text = Get-Content -LiteralPath $importFile.FullName -Raw
    if ($text -match '"use_external/enabled"\s*:\s*true') {
        $configuredImports.Add($importFile)
    }
}
if ($configuredImports.Count -eq 0) {
    throw "No GLB import settings contain external material mappings."
}

$removedCaches = 0
foreach ($importFile in $configuredImports) {
    $text = Get-Content -LiteralPath $importFile.FullName -Raw
    $match = [regex]::Match($text, '(?m)^path="(res://\.godot/imported/[^"]+\.scn)"')
    if (-not $match.Success) {
        throw "Could not find imported scene cache path in $($importFile.FullName)"
    }
    $relativeCache = $match.Groups[1].Value.Substring("res://".Length).Replace('/', '\')
    $cachePath = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $relativeCache))
    if (-not $cachePath.StartsWith($cacheRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove cache outside the Godot imported directory: $cachePath"
    }
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        Remove-Item -LiteralPath $cachePath -Force
        $removedCaches++
    }
}

Write-Host "Configured $($configuredImports.Count) GLBs and removed $removedCaches stale import caches."
& $GodotPath --headless --path $ProjectRoot --import
if ($LASTEXITCODE -ne 0) {
    throw "Godot reimport failed with exit code $LASTEXITCODE."
}

& (Join-Path $PSScriptRoot "configure_dspre_godot_textures.ps1") -ProjectRoot $ProjectRoot -GodotPath $GodotPath

if ($LimitAssets -le 0) {
    & $GodotPath --headless --path $ProjectRoot --script "res://tools/validate_shared_materials.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Shared material validation failed with exit code $LASTEXITCODE."
    }
}

Write-Host "Godot shared material configuration complete."
