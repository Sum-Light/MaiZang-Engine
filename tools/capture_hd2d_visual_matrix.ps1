[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotPath = "",
    [int]$MeasureFrames = 1800,
    [double]$MaxRenderCpuP95 = 2.5,
    [double]$MaxRenderGpuP95 = 2.0
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
        throw "$Label did not create its expected log: $Path"
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
        throw "$Label reported a Godot error: $($failures[0].Line)"
    }
}

function Invoke-WorldCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Cell,
        [Parameter(Mandatory = $true)]
        [string]$Offset,
        [Parameter(Mandatory = $true)]
        [ValidateSet("classic", "hd2d")]
        [string]$Profile,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [string]$MetricsPath = "",
        [int]$WarmupFrames = 10,
        [int]$PerformanceFrames = 0
    )

    $logPath = Join-Path $logRoot "hd2d-visual-$Name.log"
    $godotArguments = @(
        "--path", $ProjectRoot,
        "--audio-driver", "Dummy",
        "--rendering-method", "gl_compatibility",
        "--rendering-driver", "opengl3",
        "--log-file", $logPath,
        "--script", "res://tests/render_world_capture.gd",
        "--",
        "--cell=$Cell",
        "--offset=$Offset",
        "--visual-profile=$Profile",
        "--stability-frames=16",
        "--output=$OutputPath"
    )
    if ($PerformanceFrames -gt 0) {
        $godotArguments += @(
            "--warmup-frames=$WarmupFrames",
            "--measure-frames=$PerformanceFrames",
            "--metrics-output=$MetricsPath",
            "--max-render-cpu-p95=$MaxRenderCpuP95",
            "--max-render-gpu-p95=$MaxRenderGpuP95"
        )
    }

    & $GodotPath @godotArguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Name capture failed."
    }
    Assert-CleanGodotLog -Path $logPath -Label $Name

    $relativeOutput = $OutputPath.Substring("res://".Length).Replace('/', '\')
    $absoluteOutput = Join-Path $ProjectRoot $relativeOutput
    if (-not (Test-Path -LiteralPath $absoluteOutput -PathType Leaf)) {
        throw "$Name did not create its capture: $absoluteOutput"
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
if ($MeasureFrames -lt 1) {
    throw "MeasureFrames must be positive."
}

$logRoot = Join-Path $workspaceRoot ".work"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$captureSpecs = @(
    @{ Name = "classic-baseline"; Cell = "3,27"; Offset = "0,0"; Profile = "classic"; Output = "res://captures/p5_classic_baseline.png" },
    @{ Name = "origin"; Cell = "3,27"; Offset = "0,0"; Profile = "hd2d"; Output = "res://captures/p5_origin_hd2d.png" },
    @{ Name = "city"; Cell = "5,26"; Offset = "-4,-2"; Profile = "hd2d"; Output = "res://captures/p5_city_hd2d.png" },
    @{ Name = "water"; Cell = "16,16"; Offset = "-4.5,-2.5"; Profile = "hd2d"; Output = "res://captures/p5_water_hd2d.png" },
    @{ Name = "foliage"; Cell = "14,25"; Offset = "0,0"; Profile = "hd2d"; Output = "res://captures/p5_foliage_hd2d.png" },
    @{ Name = "emissive"; Cell = "4,24"; Offset = "2,-2"; Profile = "hd2d"; Output = "res://captures/p5_emissive_hd2d.png" }
)

foreach ($spec in $captureSpecs) {
    Invoke-WorldCapture `
        -Name $spec.Name `
        -Cell $spec.Cell `
        -Offset $spec.Offset `
        -Profile $spec.Profile `
        -OutputPath $spec.Output
}

$classicPath = Join-Path $ProjectRoot "captures\p5_classic_baseline.png"
$classicHash = (Get-FileHash -LiteralPath $classicPath -Algorithm SHA256).Hash
$expectedClassicHash = "9B44D0BBC6DAACA46D2422C77BE2D453A126C0B221772E5E77EBB35A072196FE"
if ($classicHash -ne $expectedClassicHash) {
    throw "Classic RGBA baseline changed: expected=$expectedClassicHash actual=$classicHash"
}

$metricsResourcePath = "res://captures/p5_origin_hd2d.metrics.json"
Invoke-WorldCapture `
    -Name "performance" `
    -Cell "3,27" `
    -Offset "0,0" `
    -Profile "hd2d" `
    -OutputPath "res://captures/p5_origin_hd2d_metrics.png" `
    -MetricsPath $metricsResourcePath `
    -WarmupFrames 120 `
    -PerformanceFrames $MeasureFrames

$metricsPath = Join-Path $ProjectRoot "captures\p5_origin_hd2d.metrics.json"
if (-not (Test-Path -LiteralPath $metricsPath -PathType Leaf)) {
    throw "HD2D performance metrics were not generated: $metricsPath"
}
$metrics = Get-Content -LiteralPath $metricsPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (
    [int]$metrics.visible_draw_calls.min -ne 43 -or
    [int]$metrics.visible_draw_calls.max -ne 43 -or
    [int]$metrics.visible_objects.min -ne 50 -or
    [int]$metrics.visible_objects.max -ne 50 -or
    [int]$metrics.visible_primitives.min -ne 2402 -or
    [int]$metrics.visible_primitives.max -ne 2402
) {
    throw "HD2D origin draw topology changed unexpectedly."
}

Write-Host "HD2D visual matrix complete."
Write-Host "  Classic SHA-256:  $classicHash"
Write-Host "  Stable captures:  $($captureSpecs.Count) x 16 frames"
Write-Host "  Render CPU p95:   $([double]$metrics.render_cpu_ms.p95) ms"
if ([bool]$metrics.render_gpu_ms.available) {
    Write-Host "  Render GPU p95:   $([double]$metrics.render_gpu_ms.p95) ms"
}
Write-Host "  Draw topology:    43 calls / 50 objects / 2402 primitives"
