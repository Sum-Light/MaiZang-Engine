[CmdletBinding()]
param(
    [string]$ProjectRoot = "",

    [ValidateSet("Repository", "Worktree", "Staged")]
    [string]$Mode = "Repository",

    [string]$SourceAuditManifestPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "p2_source_evidence_join_support.ps1")

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$result = Compile-P2SourceEvidenceJoin -ProjectRoot $ProjectRoot -Mode $Mode `
    -SourceAuditManifestPath $SourceAuditManifestPath

Write-Output ((
    "P2_SOURCE_EVIDENCE_JOIN_OK mode={0} evidence={1} current={2} " +
    "mechanisms={3} join_sha256={4}"
) -f $Mode, $result.EvidenceRecordCount, $result.CurrentEvidenceCount,
    $result.MechanismCount, $result.ManifestHash)
