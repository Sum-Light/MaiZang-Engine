[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourcePath,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$assetRoot = Join-Path $projectRoot "new-game-project\assets\platinum"
$outputPath = Join-Path $assetRoot "characters\dawn_overworld.png"
$sourcePath = [IO.Path]::GetFullPath($SourcePath)
$outputPath = [IO.Path]::GetFullPath($outputPath)
$allowedPrefix = [IO.Path]::GetFullPath($assetRoot).TrimEnd('\') + '\'

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Source sprite sheet does not exist: $sourcePath"
}
if (-not $outputPath.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to write the player sprite outside the ignored Platinum asset root."
}
if ((Test-Path -LiteralPath $outputPath -PathType Leaf) -and -not $Force) {
    throw "Player sprite already exists. Pass -Force to rebuild it: $outputPath"
}

Add-Type -AssemblyName System.Drawing

$frameSize = 34
$directions = 4
$framesPerAction = 4
$actionOrigins = @(
    [Drawing.Point]::new(0, 0),
    [Drawing.Point]::new(170, 0)
)
$atlasWidth = $frameSize * $framesPerAction * $actionOrigins.Count
$atlasHeight = $frameSize * $directions
$transparentColors = @(
    [Drawing.Color]::FromArgb(0, 128, 128).ToArgb(),
    [Drawing.Color]::FromArgb(136, 184, 176).ToArgb()
)

$source = [Drawing.Bitmap]::new($sourcePath)
try {
    $requiredWidth = ($actionOrigins | ForEach-Object { $_.X } | Measure-Object -Maximum).Maximum + ($frameSize * $framesPerAction)
    if ($source.Width -lt $requiredWidth -or $source.Height -lt $atlasHeight) {
        throw "Source sheet is too small for the expected Dawn walk/run groups: $($source.Width)x$($source.Height)"
    }

    $atlas = [Drawing.Bitmap]::new($atlasWidth, $atlasHeight, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $transparentPixels = 0
        $opaquePixels = 0
        for ($direction = 0; $direction -lt $directions; $direction++) {
            for ($action = 0; $action -lt $actionOrigins.Count; $action++) {
                for ($frame = 0; $frame -lt $framesPerAction; $frame++) {
                    $sourceX = $actionOrigins[$action].X + ($frame * $frameSize)
                    $sourceY = $actionOrigins[$action].Y + ($direction * $frameSize)
                    $destinationX = (($action * $framesPerAction) + $frame) * $frameSize
                    $destinationY = $direction * $frameSize

                    for ($y = 0; $y -lt $frameSize; $y++) {
                        for ($x = 0; $x -lt $frameSize; $x++) {
                            $color = $source.GetPixel($sourceX + $x, $sourceY + $y)
                            if ($transparentColors -contains $color.ToArgb()) {
                                $atlas.SetPixel($destinationX + $x, $destinationY + $y, [Drawing.Color]::Transparent)
                                $transparentPixels++
                            }
                            else {
                                $atlas.SetPixel(
                                    $destinationX + $x,
                                    $destinationY + $y,
                                    [Drawing.Color]::FromArgb(255, $color.R, $color.G, $color.B)
                                )
                                $opaquePixels++
                            }
                        }
                    }
                }
            }
        }

        if ($transparentPixels -eq 0 -or $opaquePixels -eq 0) {
            throw "Color-key conversion produced an invalid atlas."
        }

        $outputDirectory = Split-Path -Parent $outputPath
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
        $temporaryPath = "$outputPath.tmp"
        try {
            $atlas.Save($temporaryPath, [Drawing.Imaging.ImageFormat]::Png)
            Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }
    }
    finally {
        $atlas.Dispose()
    }
}
finally {
    $source.Dispose()
}

$check = [Drawing.Bitmap]::new($outputPath)
try {
    if ($check.Width -ne $atlasWidth -or $check.Height -ne $atlasHeight) {
        throw "Unexpected output atlas size: $($check.Width)x$($check.Height)"
    }
}
finally {
    $check.Dispose()
}

Write-Host "Player sprite atlas imported."
Write-Host "  Layout: 8 columns x 4 directions"
Write-Host "  Frames: walk 0-3, run 4-7"
Write-Host "  Output: $outputPath"
