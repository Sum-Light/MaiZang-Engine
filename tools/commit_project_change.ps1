[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Message,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Summary,

    [string]$ProjectRoot = "",
    [string]$GodotPath = "",
    [switch]$FullValidation,
    [switch]$NoPush,
    [switch]$NoWikiSync
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$changeLogPath = Join-Path $ProjectRoot "wiki\Change-Log.md"

$gitProbe = & git -C $ProjectRoot rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or $gitProbe -ne "true") {
    throw "Project repository is not initialized: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $changeLogPath -PathType Leaf)) {
    throw "Project change log was not found: $changeLogPath"
}

$date = Get-Date -Format "yyyy-MM-dd"
$heading = "## $date - $Message"
$entry = "## $date - $Message`n`n- $Summary`n"
$changeLog = Get-Content -LiteralPath $changeLogPath -Raw -Encoding UTF8
if ($changeLog -notmatch '\A# Change Log\r?\n') {
    throw "Unexpected Change Log format."
}
$updatedChangeLog = $changeLog
if ($changeLog -notmatch [regex]::Escape($heading)) {
    $updatedChangeLog = [regex]::Replace(
        $changeLog,
        '\A# Change Log\r?\n',
        "# Change Log`n`n$entry`n",
        1
    )
}
[IO.File]::WriteAllText($changeLogPath, $updatedChangeLog.TrimEnd() + "`n", $utf8NoBom)

& (Join-Path $ProjectRoot "tools\update_project_memory.ps1") -ProjectRoot $ProjectRoot
& git -C $ProjectRoot add -A
if ($LASTEXITCODE -ne 0) {
    throw "Could not stage the project change."
}

if ($FullValidation) {
    if ([string]::IsNullOrWhiteSpace($GodotPath)) {
        & (Join-Path $ProjectRoot "tools\validate_repository.ps1") -ProjectRoot $ProjectRoot -Full
    }
    else {
        & (Join-Path $ProjectRoot "tools\validate_repository.ps1") -ProjectRoot $ProjectRoot -Full -GodotPath $GodotPath
    }
}
else {
    & (Join-Path $ProjectRoot "tools\validate_repository.ps1") -ProjectRoot $ProjectRoot
}

& git -C $ProjectRoot diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    throw "There are no staged changes to commit."
}

& git -C $ProjectRoot commit -m $Message
if ($LASTEXITCODE -ne 0) {
    throw "Git commit failed."
}

$branch = (& git -C $ProjectRoot branch --show-current).Trim()
if (-not $NoPush) {
    & git -C $ProjectRoot push -u origin $branch
    if ($LASTEXITCODE -ne 0) {
        throw "Project push failed."
    }
}

if (-not $NoWikiSync -and -not $NoPush) {
    & (Join-Path $ProjectRoot "tools\sync_github_wiki.ps1") -ProjectRoot $ProjectRoot -Message "Sync Wiki for: $Message" -Push
}

Write-Host "Project change committed."
Write-Host "  Branch:  $branch"
Write-Host "  Message: $Message"
