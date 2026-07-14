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

& powershell.exe -NoProfile -ExecutionPolicy Bypass `
	-File (Join-Path $ProjectRoot "tools\test_dspre_collision_support.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "DSPRE collision support test failed."
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $ProjectRoot "tools\test_dspre_field_feature_support.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "DSPRE field feature support test failed."
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $ProjectRoot "tools\test_dspre_map_animation_support.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "DSPRE map animation support test failed."
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $ProjectRoot "tools\test_dspre_sync_incremental.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "DSPRE incremental sync test failed."
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
    $catalogPath = Join-Path $godotProject "assets\platinum\matrix_catalog.json"
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        throw "Full validation requires locally generated Platinum assets."
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $ProjectRoot "tools\validate_dspre_matrix_catalog.ps1") `
        -ProjectRoot $ProjectRoot `
        -RequireComplete
    if ($LASTEXITCODE -ne 0) {
        throw "DSPRE matrix catalog validation failed."
    }

    $catalog = [IO.File]::ReadAllText($catalogPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $invalidTextureImports = New-Object System.Collections.Generic.List[string]
    foreach ($destination in @($catalog.destinations)) {
        $manifestPath = Join-Path $godotProject (
            "assets\platinum\" + ([string]$destination.manifest).Replace('/', '\')
        )
        $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        $textureRoot = Join-Path (Split-Path -Parent $manifestPath) (
            ([string]$manifest.material_dedupe.shared_texture_root).Replace('/', '\')
        )
        $textureImports = @(Get-ChildItem -LiteralPath $textureRoot -Filter "*.png.import" -File)
        if ($textureImports.Count -ne [int]$destination.textures) {
            throw "Destination $($destination.key) texture import count is incomplete: $($textureImports.Count)/$($destination.textures)."
        }
        foreach ($importFile in $textureImports) {
            $text = [IO.File]::ReadAllText($importFile.FullName, [Text.Encoding]::UTF8)
            if (
                $text -notmatch '(?m)^compress/mode=0$' -or
                $text -notmatch '(?m)^mipmaps/generate=false$' -or
                $text -notmatch '(?m)^detect_3d/compress_to=0$'
            ) {
                $invalidTextureImports.Add($importFile.FullName)
            }
        }
    }
    if ($invalidTextureImports.Count -ne 0) {
        throw "$($invalidTextureImports.Count) texture imports do not retain lossless/no-mipmap settings."
    }

    & $GodotPath --headless --path $godotProject --script "res://tests/material_catalog_support_test.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Material catalog support test failed."
    }
    & $GodotPath --headless --path $godotProject --script "res://tests/debug_coordinate_test.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Debug coordinate test failed."
    }
    & $GodotPath --headless --path $godotProject --script "res://tests/platinum_collision_map_test.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Platinum collision map test failed."
    }
    & $GodotPath --headless --path $godotProject --script "res://tests/platinum_collision_map_test.gd" -- `
        --real-manifest=res://assets/platinum/matrix_0049_area_0061/manifest.json
    if ($LASTEXITCODE -ne 0) {
        throw "Real Platinum collision manifest test failed."
    }
    & $GodotPath --headless --path $godotProject --script "res://tests/player_collision_test.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Player collision test failed."
    }
    & $GodotPath --headless --path $godotProject --script "res://tests/map_prop_animation_test.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "MapProp animation test failed."
    }
    & $GodotPath --headless --path $godotProject --script "res://tests/world_transition_runtime_test.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "World transition runtime test failed."
    }
    & $GodotPath --headless --path $godotProject --script "res://tools/validate_shared_materials.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Shared material validation failed."
    }
    & $GodotPath --path $godotProject --audio-driver Dummy --rendering-method gl_compatibility --rendering-driver opengl3 --script "res://tests/world_streamer_smoke_test.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "World streamer smoke test failed."
    }
    & $GodotPath --path $godotProject --audio-driver Dummy --rendering-method gl_compatibility --rendering-driver opengl3 --script "res://tests/debug_destination_test.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Debug destination test failed."
    }
    & $GodotPath --path $godotProject --audio-driver Dummy --rendering-method gl_compatibility --rendering-driver opengl3 --script "res://tests/debug_destination_test.gd" -- `
        --matrix=49 --area=4 --tile=7,9 --expect-runtime-cli
    if ($LASTEXITCODE -ne 0) {
        throw "Debug destination command-line test failed."
    }
    & $GodotPath --path $godotProject --audio-driver Dummy --rendering-method gl_compatibility --rendering-driver opengl3 --script "res://tests/runtime_debug_jump_test.gd" -- `
        --capture-panel=res://captures/runtime_debug_jump_panel.png
    if ($LASTEXITCODE -ne 0) {
        throw "Runtime debug jump test failed."
    }
    & $GodotPath --path $godotProject --audio-driver Dummy --rendering-method gl_compatibility --rendering-driver opengl3 --script "res://tests/warp_transition_integration_test.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Warp transition integration test failed."
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
