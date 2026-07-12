[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotPath = "",
    [string]$ProfilePath = "res://assets/platinum/hd2d/p3_city.profile.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $workspaceRoot "new-game-project"
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Users\YbbNa\Downloads\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe"
}
$GodotPath = [IO.Path]::GetFullPath($GodotPath)
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable was not found: $GodotPath"
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) {
    throw "Godot project was not found: $ProjectRoot"
}
$profileAbsolutePath = $ProfilePath
if ($ProfilePath.StartsWith("res://", [StringComparison]::OrdinalIgnoreCase)) {
    $profileRelativePath = $ProfilePath.Substring("res://".Length).Replace('/', '\')
    $profileAbsolutePath = Join-Path $ProjectRoot $profileRelativePath
}
if (-not (Test-Path -LiteralPath $profileAbsolutePath -PathType Leaf)) {
    throw "HD2D material profile was not found: $profileAbsolutePath"
}

$baseMaterialRoot = Join-Path $ProjectRoot "assets\platinum\shared_materials"
$baseMaterialFiles = @(Get-ChildItem -LiteralPath $baseMaterialRoot -Filter "*.tres" -File)
if ($baseMaterialFiles.Count -ne 511) {
    throw "Expected 511 shared base materials, found $($baseMaterialFiles.Count)."
}
$baseHashesBefore = @{}
foreach ($file in $baseMaterialFiles) {
    $baseHashesBefore[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
}

$logRoot = Join-Path $workspaceRoot ".work"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$buildLog = Join-Path $logRoot "hd2d-material-build.log"
$validationLog = Join-Path $logRoot "hd2d-material-validation.log"

$buildArguments = @(
    "--headless",
    "--path", $ProjectRoot,
    "--log-file", $buildLog,
    "--script", "res://tools/build_hd2d_material_variants.gd",
    "--",
    "--profile=$ProfilePath"
)
& $GodotPath @buildArguments
if ($LASTEXITCODE -ne 0) {
    throw "HD2D material variant build failed."
}

$validationArguments = @(
    "--headless",
    "--path", $ProjectRoot,
    "--log-file", $validationLog,
    "--script", "res://tools/validate_hd2d_material_variants.gd",
    "--",
    "--profile=$ProfilePath"
)
& $GodotPath @validationArguments
if ($LASTEXITCODE -ne 0) {
    throw "HD2D material variant validation failed."
}

$baseMaterialFilesAfter = @(Get-ChildItem -LiteralPath $baseMaterialRoot -Filter "*.tres" -File)
if ($baseMaterialFilesAfter.Count -ne $baseMaterialFiles.Count) {
    throw "Shared base material count changed during HD2D variant generation."
}
foreach ($file in $baseMaterialFilesAfter) {
    $hashAfter = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    if (-not $baseHashesBefore.ContainsKey($file.Name) -or $baseHashesBefore[$file.Name] -ne $hashAfter) {
        throw "Shared base material changed during HD2D variant generation: $($file.Name)"
    }
}

Write-Host "HD2D material variants configured and validated."
Write-Host "  Profile: $ProfilePath"
Write-Host "  Shared base materials unchanged: $($baseMaterialFiles.Count)"
