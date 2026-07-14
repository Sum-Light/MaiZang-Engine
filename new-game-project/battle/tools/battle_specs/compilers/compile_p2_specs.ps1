[CmdletBinding()]
param(
    [string]$ProjectRoot = "",

    [ValidateSet("Repository", "Worktree", "Staged")]
    [string]$Mode = "Repository",

    [Alias("OutputRoot")]
    [string]$OutputDirectory = "",

    [Alias("VerifyRoot")]
    [string]$VerifyDirectory = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "p2_spec_compiler_support.ps1")

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$result = Invoke-P2SpecCompilerAction -ProjectRoot $ProjectRoot -Mode $Mode `
    -OutputDirectory $OutputDirectory -VerifyDirectory $VerifyDirectory
$compilation = $result.Compilation
$action = [string]$result.Action

Write-Output ((
    "P2_SPEC_COMPILER_OK mode={0} action={1} mechanisms={2} events={3} " +
    "handlers={4} resolvers={5} tests={6} spec_sha256={7} " +
    "runtime_sha256={8}"
) -f $Mode, $action, @($compilation.SpecSet.MechanismSpecs).Count,
    @($compilation.SpecSet.EventSchemas).Count,
    @($compilation.SpecSet.HandlerBindings).Count,
    @($compilation.SpecSet.ResolverSpecs).Count,
    @($compilation.SpecSet.TestEntries).Count,
    $compilation.SpecManifestHash, $compilation.RuntimeManifestHash)
