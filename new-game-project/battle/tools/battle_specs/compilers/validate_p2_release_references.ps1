[CmdletBinding()]
param(
    [string]$ProjectRoot = "",

    [ValidateSet("Repository", "Worktree", "Staged")]
    [string]$Mode = "Repository",

    [string]$SourceAuditManifestPath = "",

    [string]$GodotContractRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "p2_release_reference_support.ps1")

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$result = Validate-P2ReleaseMechanismReferences -ProjectRoot $ProjectRoot `
    -Mode $Mode -SourceAuditManifestPath $SourceAuditManifestPath `
    -GodotContractRoot $GodotContractRoot

Write-Output ((
    "P2_RELEASE_REFERENCES_OK mode={0} release_mechanisms={1} " +
    "reference_triples={2} blocked={3} manifest_sha256={4} " +
    "validation_scope={5}"
) -f $Mode, $result.ReleaseMechanismCount, $result.ReferenceTripleCount,
    $result.BlockedMechanismCount, $result.ManifestHash,
    $result.Manifest.validation_scope)
