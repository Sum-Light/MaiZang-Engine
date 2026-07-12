[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotPath = "",
    [switch]$Full
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Full validation requires locally generated Platinum assets."
    }

    & $GodotPath --headless --path $godotProject --script "res://tools/validate_shared_materials.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Shared material validation failed."
    }
    & $GodotPath --path $godotProject --audio-driver Dummy --rendering-method gl_compatibility --rendering-driver opengl3 --script "res://tests/world_streamer_smoke_test.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "World streamer smoke test failed."
    }
}

Write-Host "Repository validation complete."
Write-Host "  PowerShell scripts: OK"
Write-Host "  Project Skill:      OK"
Write-Host "  Wiki pages:         OK"
Write-Host "  Asset boundary:     OK"
if ($Full) {
    Write-Host "  Godot validation:   OK"
}
