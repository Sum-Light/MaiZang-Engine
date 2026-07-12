[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotPath = "",
    [switch]$Full
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-CleanGodotLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label did not create its expected Godot log: $Path"
    }
    $failures = @(
        Select-String -LiteralPath $Path -Pattern @(
            "ERROR:",
            "leaked at exit",
            "never freed",
            "orphan"
        ) -SimpleMatch
    )
    if ($failures.Count -gt 0) {
        throw "$Label reported renderer or resource cleanup errors: $($failures[0].Line)"
    }
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')

$parseFailures = New-Object System.Collections.Generic.List[object]
foreach ($script in Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "tools") -Filter "*.ps1" -File) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($parseError in $errors) {
        $parseFailures.Add([pscustomobject]@{ script = $script.Name; error = $parseError.Message })
    }
}
if ($parseFailures.Count -gt 0) {
    $parseFailures | Format-Table -AutoSize
    throw "$($parseFailures.Count) PowerShell syntax error(s) found."
}

$skillPath = Join-Path $ProjectRoot ".codex\skills\maizang-engine-godot"
$skillValidator = Join-Path $env:USERPROFILE ".codex\skills\.system\skill-creator\scripts\quick_validate.py"
if (-not (Test-Path -LiteralPath $skillValidator -PathType Leaf)) {
    throw "Skill validator was not found: $skillValidator"
}
& python $skillValidator $skillPath
if ($LASTEXITCODE -ne 0) {
    throw "Project Skill validation failed."
}

$requiredWikiPages = @(
    "Home.md",
    "Architecture.md",
    "Asset-Pipeline.md",
    "Runtime-Streaming.md",
    "Player-Control.md",
    "Validation.md",
    "Development-Workflow.md",
    "Repository-Policy.md",
    "Current-State.md",
    "Change-Log.md",
    "_Sidebar.md"
)
foreach ($page in $requiredWikiPages) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "wiki\$page") -PathType Leaf)) {
        throw "Required Wiki page is missing: $page"
    }
}

$gitProbe = ""
if (Test-Path -LiteralPath (Join-Path $ProjectRoot ".git\HEAD") -PathType Leaf) {
    $gitProbe = & git -C $ProjectRoot rev-parse --is-inside-work-tree 2>$null
}
if ($gitProbe -eq "true") {
    $tracked = @(& git -C $ProjectRoot ls-files)
    $prohibited = @(
        $tracked | Where-Object {
            $_ -eq "generated" -or
            $_.StartsWith("generated/") -or
            $_ -eq ".work" -or
            $_.StartsWith(".work/") -or
            $_.StartsWith("new-game-project/assets/platinum/") -or
            $_.StartsWith("new-game-project/captures/")
        }
    )
    if ($prohibited.Count -gt 0) {
        throw "Proprietary or generated paths are tracked: $($prohibited -join ', ')"
    }
}

if ($Full) {
    if ([string]::IsNullOrWhiteSpace($GodotPath)) {
        $GodotPath = "C:\Users\YbbNa\Downloads\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe"
    }
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
        throw "Godot executable was not found: $GodotPath"
    }
    $godotProject = Join-Path $ProjectRoot "new-game-project"
    $manifestPath = Join-Path $godotProject "assets\platinum\matrix_0000\manifest.json"
    $hd2dProfilePath = Join-Path $godotProject "assets\platinum\hd2d\p3_city.profile.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Full validation requires locally generated Platinum assets."
    }
    if (-not (Test-Path -LiteralPath $hd2dProfilePath -PathType Leaf)) {
        throw "Full validation requires the local P3 HD2D material profile. Run tools\configure_hd2d_material_variants.ps1 first."
    }

    $logRoot = Join-Path $ProjectRoot ".work"
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

    $sharedMaterialLog = Join-Path $logRoot "shared-material-validation.log"
    $hd2dMaterialLog = Join-Path $logRoot "hd2d-material-validation.log"
    $worldStreamerLog = Join-Path $logRoot "world-streamer-smoke.log"

    & $GodotPath --headless --path $godotProject --log-file $sharedMaterialLog --script "res://tools/validate_shared_materials.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Shared material validation failed."
    }
    Assert-CleanGodotLog -Path $sharedMaterialLog -Label "Shared material validation"

    & $GodotPath --headless --path $godotProject --log-file $hd2dMaterialLog --script "res://tools/validate_hd2d_material_variants.gd" -- "--profile=res://assets/platinum/hd2d/p3_city.profile.json"
    if ($LASTEXITCODE -ne 0) {
        throw "HD2D material variant validation failed."
    }
    Assert-CleanGodotLog -Path $hd2dMaterialLog -Label "HD2D material validation"

    & $GodotPath --path $godotProject --audio-driver Dummy --rendering-method gl_compatibility --rendering-driver opengl3 --log-file $worldStreamerLog --script "res://tests/world_streamer_smoke_test.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "World streamer smoke test failed."
    }
    Assert-CleanGodotLog -Path $worldStreamerLog -Label "World streamer smoke test"
}

Write-Host "Repository validation complete."
Write-Host "  PowerShell scripts: OK"
Write-Host "  Project Skill:      OK"
Write-Host "  Wiki pages:         OK"
Write-Host "  Asset boundary:     OK"
if ($Full) {
    Write-Host "  Godot validation:   OK"
}
