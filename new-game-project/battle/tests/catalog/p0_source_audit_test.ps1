[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$AnalysisRoot = "D:\PokemonSV-Battle-Architecture",
    [string]$SourceRoot = "",
    [string]$GodotContractRoot = "D:\PokemonSV-Battle-Architecture\docs\godot"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battleRoot = Join-Path $ProjectRoot "new-game-project\battle"
$builderPath = Join-Path $battleRoot "tools\battle_catalog\importers\build_p0_source_audit.ps1"
$validatorPath = Join-Path $battleRoot "tools\battle_catalog\validators\validate_p0_manifests.ps1"
$strictJsonPath = Join-Path $battleRoot "tools\battle_catalog\validators\strict_json_support.ps1"
$canonicalJsonPath = Join-Path $battleRoot "tools\battle_catalog\validators\canonical_json_support.ps1"
$baselinePath = Join-Path $battleRoot "manifests\source_audit\source_index_baseline.json"
$trackedSealPath = Join-Path $battleRoot "manifests\source_audit\source_audit_seal.json"
$workItemPath = Join-Path $battleRoot "manifests\work_items\P0_SOURCE_AUDIT_BASELINE.json"

. $strictJsonPath
. $canonicalJsonPath

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$MessagePattern,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $caught = $null
    try {
        & $Action
    }
    catch {
        $caught = $_
    }
    if ($null -eq $caught) {
        throw "$Label did not fail."
    }
    if ([string]$caught.Exception.Message -notmatch $MessagePattern) {
        throw "$Label failed with an unexpected message: $($caught.Exception.Message)"
    }
}

function Get-LowerSha256 {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "maizang-p0-source-audit-test-" + [Guid]::NewGuid().ToString("N")
)
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $auditPath = Join-Path $tempRoot "source_audit_disposition_manifest.json"
    $sealPath = Join-Path $tempRoot "source_audit_seal.json"
    $builderArgs = @{
        ProjectRoot = $ProjectRoot
        AnalysisRoot = $AnalysisRoot
        OutputPath = $auditPath
        SealOutputPath = $sealPath
    }
    if (-not [string]::IsNullOrWhiteSpace($SourceRoot)) {
        $builderArgs.SourceRoot = $SourceRoot
    }
    & $builderPath @builderArgs

    $trackedSealHash = Get-LowerSha256 $trackedSealPath
    $generatedSealHash = Get-LowerSha256 $sealPath
    if ($trackedSealHash -cne $generatedSealHash) {
        throw "Generated source audit seal differs from the reviewed tracked seal."
    }
    $seal = Read-BattleStrictJsonFile -Path $sealPath -Label "generated source audit seal"
    if ([int]$seal.counts.audit_entries -ne 6559 -or
        [int]$seal.unclassified_modules -ne 0 -or
        [int]$seal.counts.executable_script_scenarios -ne 964 -or
        [int]$seal.counts.non_scenario_text_documents -ne 2 -or
        $seal.source_payloads_verified -ne $true) {
        throw "Generated source audit seal does not prove the P0 denominator and source gates."
    }
    if ((Get-LowerSha256 $auditPath) -cne [string]$seal.source_audit_manifest_sha256) {
        throw "Generated source audit bytes do not match the sealed audit hash."
    }
    $auditText = [IO.File]::ReadAllText($auditPath, [Text.Encoding]::UTF8)
    if ($auditText -match '(?i)[A-Z]:[\\/]' -or
        $auditText -match 'D:\\DownLoad|D:\\PokemonSV-Battle-Architecture') {
        throw "Generated source audit contains a machine-local absolute path."
    }

    & $validatorPath -ProjectRoot $ProjectRoot -SourceAuditManifestPath $auditPath `
        -WorkItemPaths $workItemPath -GodotContractRoot $GodotContractRoot `
        -SourceEvidenceRoot $(if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
            $summary = Get-Content -LiteralPath (Join-Path $AnalysisRoot "generated\summary.json") `
                -Raw -Encoding UTF8 | ConvertFrom-Json
            [string]$summary.SourceRoot
        } else { $SourceRoot })

    $tamperedBaseline = Read-BattleStrictJsonFile -Path $baselinePath `
        -Label "source index baseline"
    $tamperedBaseline.index_files[0].sha256 = "0" * 64
    $tamperedBaselinePath = Join-Path $tempRoot "tampered_source_index_baseline.json"
    Write-BattleCanonicalJsonFile -Path $tamperedBaselinePath -Value $tamperedBaseline | Out-Null
    $tamperedArgs = @{
        ProjectRoot = $ProjectRoot
        AnalysisRoot = $AnalysisRoot
        BaselinePath = $tamperedBaselinePath
        OutputPath = (Join-Path $tempRoot "should_not_exist_audit.json")
        SealOutputPath = (Join-Path $tempRoot "should_not_exist_seal.json")
    }
    if (-not [string]::IsNullOrWhiteSpace($SourceRoot)) {
        $tamperedArgs.SourceRoot = $SourceRoot
    }
    Assert-Throws -Label "tampered source index hash" `
        -MessagePattern "Source index hash changed" -Action {
            & $builderPath @tamperedArgs
        }
}
finally {
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
    $systemTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if (-not $resolvedTempRoot.StartsWith(
        $systemTempRoot + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove a source-audit test directory outside system temp."
    }
    Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
}

Write-Host "P0_SOURCE_AUDIT_TEST_OK"
