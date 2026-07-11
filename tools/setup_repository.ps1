[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$CodexSkillRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($CodexSkillRoot)) {
    $CodexSkillRoot = Join-Path $env:USERPROFILE ".codex\skills"
}

$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$CodexSkillRoot = [IO.Path]::GetFullPath($CodexSkillRoot).TrimEnd('\')
$sourceSkill = [IO.Path]::GetFullPath((Join-Path $ProjectRoot ".codex\skills\maizang-engine-godot"))
$installedSkill = Join-Path $CodexSkillRoot "maizang-engine-godot"

$gitProbe = & git -C $ProjectRoot rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or $gitProbe -ne "true") {
    throw "Project repository is not initialized: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceSkill "SKILL.md") -PathType Leaf)) {
    throw "Versioned project Skill was not found: $sourceSkill"
}

& git -C $ProjectRoot config core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) {
    throw "Could not configure the versioned Git hooks."
}

New-Item -ItemType Directory -Path $CodexSkillRoot -Force | Out-Null
if (Test-Path -LiteralPath $installedSkill) {
    $item = Get-Item -LiteralPath $installedSkill -Force
    $targets = @($item.Target | ForEach-Object { [IO.Path]::GetFullPath([string]$_).TrimEnd('\') })
    if ($item.LinkType -ne "Junction" -or $targets -notcontains $sourceSkill.TrimEnd('\')) {
        throw "Skill install path already exists and is not the expected junction: $installedSkill"
    }
}
else {
    New-Item -ItemType Junction -Path $installedSkill -Target $sourceSkill | Out-Null
}

& (Join-Path $ProjectRoot "tools\validate_repository.ps1") -ProjectRoot $ProjectRoot
if ($LASTEXITCODE -ne 0) {
    throw "Repository validation failed during setup."
}

Write-Host "Repository setup complete."
Write-Host "  Hooks:  .githooks"
Write-Host "  Skill:  $installedSkill -> $sourceSkill"
