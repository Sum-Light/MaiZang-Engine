[CmdletBinding()]
param(
    [string]$ProjectRoot = "",

    [ValidateSet("Repository", "Worktree", "Staged")]
    [string]$Mode = "Repository"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "p2_fixture_preflight_support.ps1")

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$result = Invoke-P2FixturePreflight -ProjectRoot $ProjectRoot -Mode $Mode

Write-Output ((
    "P2_FIXTURE_PREFLIGHT_OK mode={0} fixture_requirements={1} " +
    "scenario_tests={2} manifest_sha256={3} spec_sha256={4} " +
    "setup_compiler_status={5}"
) -f $Mode, $result.FixtureRequirementCount, $result.ScenarioTestCount,
    $result.ManifestHash, $result.Compilation.SpecManifestHash,
    $result.SetupCompilerStatus)
