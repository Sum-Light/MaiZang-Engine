[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$Repository = "Sum-Light/MaiZang-Engine",
    [string]$RemoteUrl = "",
    [string]$Message = "Sync project Wiki",
    [switch]$Push
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$sourceRoot = Join-Path $ProjectRoot "wiki"
$workRoot = Join-Path $ProjectRoot ".wiki-sync"
$remote = if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
    "git@github.com:$Repository.wiki.git"
}
else {
    $RemoteUrl
}

if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot "Home.md") -PathType Leaf)) {
    throw "Versioned Wiki source was not found: $sourceRoot"
}

function Clear-WikiWorktree {
    $resolvedRoot = [IO.Path]::GetFullPath($workRoot).TrimEnd('\') + '\'
    foreach ($item in Get-ChildItem -LiteralPath $workRoot -Force) {
        if ($item.Name -eq ".git") {
            continue
        }
        $fullPath = [IO.Path]::GetFullPath($item.FullName)
        if (-not $fullPath.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clear Wiki item outside the worktree: $fullPath"
        }
        if ($item.PSIsContainer) {
            Remove-Item -LiteralPath $fullPath -Recurse -Force
        }
        else {
            Remove-Item -LiteralPath $fullPath -Force
        }
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $workRoot ".git") -PathType Container)) {
    if (Test-Path -LiteralPath $workRoot) {
        $resolved = [IO.Path]::GetFullPath($workRoot)
        $allowed = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\') + '\'
        if (-not $resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to reset Wiki worktree outside the project: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }

    & git clone $remote $workRoot
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path -LiteralPath $workRoot) {
            Remove-Item -LiteralPath $workRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
        & git -C $workRoot init -b master
        & git -C $workRoot remote add origin $remote
    }
}

Clear-WikiWorktree
foreach ($page in Get-ChildItem -LiteralPath $sourceRoot -Filter "*.md" -File) {
    Copy-Item -LiteralPath $page.FullName -Destination (Join-Path $workRoot $page.Name) -Force
}

& git -C $workRoot add -A
& git -C $workRoot diff --cached --quiet
$hasChanges = $LASTEXITCODE -ne 0
if ($hasChanges) {
    & git -C $workRoot commit -m $Message
    if ($LASTEXITCODE -ne 0) {
        throw "Could not commit the synchronized Wiki."
    }
}
else {
    Write-Host "GitHub Wiki is already synchronized."
}

if ($Push) {
    $branch = (& git -C $workRoot branch --show-current).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        $branch = "master"
    }
    & git -C $workRoot push -u origin $branch
    if ($LASTEXITCODE -ne 0) {
        throw "Could not push the GitHub Wiki. The first Wiki page may need to be initialized on GitHub."
    }
}

Write-Host "Wiki synchronization complete."
Write-Host "  Source: $sourceRoot"
Write-Host "  Work:   $workRoot"
Write-Host "  Remote: $remote"
