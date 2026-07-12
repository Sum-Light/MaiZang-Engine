[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotPath = "",
    [string]$ProfilePath = "res://assets/platinum/hd2d/world_semantics.profile.json",
    [string]$SeedProfilePath = "res://assets/platinum/hd2d/p3_city.profile.json",
    [string]$RulesPath = "res://tools/hd2d_semantic_rules.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-CleanGodotLog {
    param([string]$Path, [string]$Label)

    $failures = @(
        Select-String -LiteralPath $Path -Pattern @(
            "ERROR:", "leaked at exit", "never freed", "orphan"
        ) -SimpleMatch
    )
    if ($failures.Count -gt 0) {
        throw "$Label reported a Godot error: $($failures[0].Line)"
    }
}

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
$seedProfileAbsolutePath = $SeedProfilePath
if ($SeedProfilePath.StartsWith("res://", [StringComparison]::OrdinalIgnoreCase)) {
    $seedProfileRelativePath = $SeedProfilePath.Substring("res://".Length).Replace('/', '\')
    $seedProfileAbsolutePath = Join-Path $ProjectRoot $seedProfileRelativePath
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
$seedLog = Join-Path $logRoot "hd2d-p3-seed-profile.log"
$profileLog = Join-Path $logRoot "hd2d-semantic-profile.log"
$buildLog = Join-Path $logRoot "hd2d-material-build.log"
$validationLog = Join-Path $logRoot "hd2d-material-validation.log"

try {
$seedArguments = @(
    "--headless",
    "--path", $ProjectRoot,
    "--log-file", $seedLog,
    "--script", "res://tools/generate_hd2d_p3_seed_profile.gd",
    "--",
    "--output-profile=$SeedProfilePath"
)
& $GodotPath @seedArguments
if ($LASTEXITCODE -ne 0) {
    throw "HD2D P3 seed profile generation failed."
}
Assert-CleanGodotLog -Path $seedLog -Label "HD2D P3 seed profile generation"
if (-not (Test-Path -LiteralPath $seedProfileAbsolutePath -PathType Leaf)) {
    throw "HD2D P3 seed profile was not generated: $seedProfileAbsolutePath"
}

$profileArguments = @(
    "--headless",
    "--path", $ProjectRoot,
    "--log-file", $profileLog,
    "--script", "res://tools/generate_hd2d_semantic_profile.gd",
    "--",
    "--rules=$RulesPath",
    "--seed-profile=$SeedProfilePath",
    "--output-profile=$ProfilePath"
)
& $GodotPath @profileArguments
if ($LASTEXITCODE -ne 0) {
    throw "HD2D semantic profile generation failed."
}
Assert-CleanGodotLog -Path $profileLog -Label "HD2D semantic profile generation"
if (-not (Test-Path -LiteralPath $profileAbsolutePath -PathType Leaf)) {
    throw "HD2D material profile was not generated: $profileAbsolutePath"
}

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
Assert-CleanGodotLog -Path $buildLog -Label "HD2D material variant build"

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
Assert-CleanGodotLog -Path $validationLog -Label "HD2D material variant validation"
}
finally {
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
}

Write-Host "HD2D material variants configured and validated."
Write-Host "  Profile: $ProfilePath"
Write-Host "  Rules: $RulesPath"
Write-Host "  Shared base materials unchanged: $($baseMaterialFiles.Count)"
