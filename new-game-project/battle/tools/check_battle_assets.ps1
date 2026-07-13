[CmdletBinding()]
param(
    [string]$ProjectRoot = "",

    [ValidateSet("Staged", "Worktree", "Repository", "All")]
    [string]$Mode = "Staged"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
. (Join-Path $PSScriptRoot "battle_catalog\validators\battle_asset_support.ps1")

function Invoke-GitPaths {
    param([string[]]$Arguments)

    $output = @(& git -c core.quotepath=false -C $ProjectRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git $($Arguments -join ' ')`n$($output -join "`n")"
    }
    $raw = @($output | ForEach-Object { [string]$_ }) -join "`n"
    return @($raw.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))
}

function Get-IndexedBlobBytes {
    param([string]$RelativePath)

    if ($ProjectRoot.Contains('"') -or $RelativePath.Contains('"')) {
        throw "Battle asset gate does not accept quote characters in repository paths."
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = "git"
    $startInfo.Arguments = "-C `"$ProjectRoot`" cat-file blob `":$RelativePath`""
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Could not start git cat-file."
        }
        $memory = [IO.MemoryStream]::new()
        try {
            $process.StandardOutput.BaseStream.CopyTo($memory)
            $errorText = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) {
                throw "Could not read indexed battle asset '$RelativePath': $errorText"
            }
            return $memory.ToArray()
        }
        finally {
            $memory.Dispose()
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-WorktreeBytes {
    param([string]$RelativePath)

    $fullPath = [IO.Path]::GetFullPath(
        (Join-Path $ProjectRoot $RelativePath.Replace('/', '\'))
    )
    if (-not $fullPath.StartsWith(
        $ProjectRoot + '\',
        [StringComparison]::OrdinalIgnoreCase
    ) -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Battle worktree asset is missing or escapes the repository: $RelativePath"
    }
    return [IO.File]::ReadAllBytes($fullPath)
}

function Get-OrdinalUniquePaths {
    param([string[]]$Paths)

    $set = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $Paths) {
        $normalized = ([string]$path).Replace('\', '/')
        if ($normalized.StartsWith("new-game-project/battle/", [StringComparison]::Ordinal)) {
            $null = $set.Add($normalized)
        }
    }
    return @($set)
}

$checked = [Collections.Generic.List[string]]::new()
if ($Mode -in @("Staged", "All")) {
    $paths = Get-OrdinalUniquePaths -Paths @(
        Invoke-GitPaths @(
            "diff", "--cached", "--name-only", "--diff-filter=ACMRTUXB", "-z",
            "--", "new-game-project/battle"
        )
    )
    foreach ($path in $paths) {
        Test-BattleAssetCandidate -RelativePath $path -Bytes (Get-IndexedBlobBytes $path)
        $checked.Add("staged:$path")
    }
}
if ($Mode -in @("Worktree", "All")) {
    $tracked = Invoke-GitPaths @(
        "diff", "--name-only", "--diff-filter=ACMRTUXB", "-z", "--",
        "new-game-project/battle"
    )
    $untracked = Invoke-GitPaths @(
        "ls-files", "--others", "--exclude-standard", "-z", "--",
        "new-game-project/battle"
    )
    $paths = Get-OrdinalUniquePaths -Paths @($tracked + $untracked)
    foreach ($path in $paths) {
        Test-BattleAssetCandidate -RelativePath $path -Bytes (Get-WorktreeBytes $path)
        $checked.Add("worktree:$path")
    }
}
if ($Mode -eq "Repository") {
    $paths = Get-OrdinalUniquePaths -Paths @(
        Invoke-GitPaths @("ls-files", "-z", "--", "new-game-project/battle")
    )
    foreach ($path in $paths) {
        Test-BattleAssetCandidate -RelativePath $path -Bytes (Get-IndexedBlobBytes $path)
        $checked.Add("repository:$path")
    }
}

Write-Host "Battle asset audit: $Mode"
Write-Host "  Checked files: $($checked.Count)"
foreach ($record in $checked) {
    Write-Host "  $record"
}
Write-Host "BATTLE_ASSET_BOUNDARY_OK"
