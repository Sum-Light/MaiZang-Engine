[CmdletBinding()]
param(
    [string]$SourceRoot = "",
    [string]$ProjectRoot = "",
    [ValidateSet("Auto", "HardLink", "Copy")]
    [string]$Mode = "Auto",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path $workspaceRoot "generated\dspre_glb_dedup\matrix_0000"
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $workspaceRoot "new-game-project"
}

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$destinationRoot = Join-Path $ProjectRoot "assets\platinum\matrix_0000"

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) {
    throw "Godot project was not found: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot "manifest.json") -PathType Leaf)) {
    throw "Deduplicated DSPRE manifest was not found: $SourceRoot"
}

$allowedRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot "assets\platinum")).TrimEnd('\') + '\'
$resolvedDestination = [IO.Path]::GetFullPath($destinationRoot).TrimEnd('\')
if (-not ($resolvedDestination + '\').StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to write outside the Godot Platinum asset root: $resolvedDestination"
}

if (Test-Path -LiteralPath $resolvedDestination) {
    if (-not $Force) {
        throw "Destination already exists. Pass -Force to rebuild it: $resolvedDestination"
    }
    Remove-Item -LiteralPath $resolvedDestination -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedDestination -Force | Out-Null

$sourceDrive = [IO.Path]::GetPathRoot($SourceRoot)
$destinationDrive = [IO.Path]::GetPathRoot($resolvedDestination)
$canHardLink = $sourceDrive.Equals($destinationDrive, [StringComparison]::OrdinalIgnoreCase)
$useHardLinks = $Mode -eq "HardLink" -or ($Mode -eq "Auto" -and $canHardLink)
if ($Mode -eq "HardLink" -and -not $canHardLink) {
    throw "Hard links require source and destination on the same volume."
}

$files = @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File | Sort-Object FullName)
if ($files.Count -eq 0) {
    throw "No source assets were found: $SourceRoot"
}

$linked = 0
$copied = 0
for ($index = 0; $index -lt $files.Count; $index++) {
    $sourceFile = $files[$index]
    $relativePath = $sourceFile.FullName.Substring($SourceRoot.Length).TrimStart('\')
    $destinationPath = Join-Path $resolvedDestination $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null

    if ($useHardLinks) {
        try {
            New-Item -ItemType HardLink -Path $destinationPath -Target $sourceFile.FullName -Force | Out-Null
            $linked++
        }
        catch {
            if ($Mode -eq "HardLink") {
                throw
            }
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationPath -Force
            $copied++
        }
    }
    else {
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationPath -Force
        $copied++
    }

    Write-Progress -Activity "Syncing DSPRE assets into Godot" -Status "$($index + 1) / $($files.Count)" -PercentComplete (100.0 * ($index + 1) / $files.Count)
}
Write-Progress -Activity "Syncing DSPRE assets into Godot" -Completed

$glbCount = @(Get-ChildItem -LiteralPath $resolvedDestination -Recurse -Filter "*.glb" -File).Count
$pngCount = @(Get-ChildItem -LiteralPath $resolvedDestination -Recurse -Filter "*.png" -File).Count
if ($glbCount -ne 398 -or $pngCount -ne 480) {
    throw "Synced asset counts are unexpected: $glbCount GLBs, $pngCount PNGs."
}

Write-Host "DSPRE Godot asset sync complete."
Write-Host "  Destination: $resolvedDestination"
Write-Host "  Hard linked: $linked"
Write-Host "  Copied:      $copied"
Write-Host "  GLBs:        $glbCount"
Write-Host "  PNGs:        $pngCount"
