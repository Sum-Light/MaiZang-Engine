[CmdletBinding()]
param([string]$ProjectRoot = "")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battleRoot = Join-Path $ProjectRoot "new-game-project\battle"
$assetGatePath = Join-Path $battleRoot "tools\check_battle_assets.ps1"
$validatorPath = Join-Path $battleRoot "tools\battle_catalog\validators\validate_p0_manifests.ps1"
$assetSupportPath = Join-Path $battleRoot "tools\battle_catalog\validators\battle_asset_support.ps1"
$licenseTemplatePath = Join-Path $battleRoot "manifests\licensed_source_manifest.template.json"
$utf8NoBom = [Text.UTF8Encoding]::new($false)

. $assetSupportPath

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

function Assert-CandidateFails {
    param(
        [string]$Path,
        [string]$Text,
        [string]$MessagePattern,
        [string]$Label
    )

    $bytes = $utf8NoBom.GetBytes($Text)
    Assert-Throws -Label $Label -MessagePattern $MessagePattern -Action {
        Test-BattleAssetCandidate -RelativePath $Path -Bytes $bytes
    }
}

function Assert-CandidatePasses {
    param(
        [string]$Path,
        [string]$Text,
        [string]$Label
    )

    try {
        Test-BattleAssetCandidate -RelativePath $Path -Bytes $utf8NoBom.GetBytes($Text)
    }
    catch {
        throw "$Label failed unexpectedly: $($_.Exception.Message)"
    }
}

& $assetGatePath -ProjectRoot $ProjectRoot -Mode Repository
& $assetGatePath -ProjectRoot $ProjectRoot -Mode Worktree

$ignoreProbes = @(
    "new-game-project/battle/local_data/source/p0_probe.json",
    "new-game-project/battle/local_data/normalized/p0_probe.json",
    "new-game-project/battle/local_data/runtime/p0_probe.json",
    "new-game-project/battle/generated/p0/p0_probe.json"
)
foreach ($probe in $ignoreProbes) {
    & git -C $ProjectRoot check-ignore -q -- $probe
    if ($LASTEXITCODE -ne 0) {
        throw "Battle local-data ignore probe failed: $probe"
    }
}

foreach ($extension in @("txt", "csv", "dat", "bin", "png", "ogg", "glb")) {
    Assert-CandidateFails `
        -Path "new-game-project/battle/fixtures/synthetic/p0/blocked.$extension" `
        -Text "synthetic" -MessagePattern "BATTLE_ASSET_BLOCKED_EXTENSION" `
        -Label "blocked .$extension asset"
}
Assert-CandidateFails `
    -Path "new-game-project/battle/fixtures/synthetic/p0/unapproved.json" `
    -Text '{"schema_version":1}' -MessagePattern "BATTLE_ASSET_JSON_PATH_NOT_ALLOWED" `
    -Label "unapproved JSON path"
foreach ($approvedP2Path in @(
    "new-game-project/battle/specs/id_manifests/battle_stable_ids.json",
    "new-game-project/battle/specs/presentation/presentation_contracts.json",
    "new-game-project/battle/specs/mechanisms/0000000001.mechanism_spec.json",
    "new-game-project/battle/specs/events/0000000001.event_schema.json",
    "new-game-project/battle/specs/handlers/0000000001.handler_binding.json",
    "new-game-project/battle/specs/resolvers/0000000001.resolver_spec.json",
    "new-game-project/battle/specs/tests/0000000001.test_manifest_entry.json",
    "new-game-project/battle/tools/battle_specs/schemas/stable_id_manifest.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/presentation_contracts.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/mechanism_spec.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/event_schema.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/handler_binding.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/resolver_spec.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/test_manifest_entry.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/compiled_spec_manifest.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/runtime_rule_catalog_manifest.schema.json"
)) {
    Assert-CandidatePasses -Path $approvedP2Path -Text '{"schema_version":1}' `
        -Label "approved P2 JSON path $approvedP2Path"
}
foreach ($unapprovedP2Path in @(
    "new-game-project/battle/specs/id_manifests/nearby.json",
    "new-game-project/battle/specs/presentation/nearby.json",
    "new-game-project/battle/specs/mechanisms/rogue.json",
    "new-game-project/battle/specs/mechanisms/1.mechanism_spec.json",
    "new-game-project/battle/specs/mechanisms/0000000001.event_schema.json",
    "new-game-project/battle/specs/mechanisms/nested/0000000001.mechanism_spec.json",
    "new-game-project/battle/specs/Events/0000000001.event_schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/rogue.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/mechanism_specs.schema.json"
)) {
    Assert-CandidateFails -Path $unapprovedP2Path -Text '{}' `
        -MessagePattern "BATTLE_ASSET_JSON_PATH_NOT_ALLOWED" `
        -Label "unapproved P2 JSON path $unapprovedP2Path"
}
Assert-CandidateFails `
    -Path "new-game-project/battle/generated/battle_specs/mechanism_coverage.json" `
    -Text '{}' -MessagePattern "BATTLE_ASSET_LOCAL_ARTIFACT" `
    -Label "tracked generated P2 report"
Assert-CandidateFails `
    -Path "new-game-project/battle/manifests/licensed_source_manifest.template.json" `
    -Text '{"schema_version":1,"manifest_kind":"LICENSED_SOURCE","manifest_mode":"PRODUCTION","scope_id":"X","target_data_generation":"X","records":[]}' `
    -MessagePattern "BATTLE_ASSET_PRODUCTION_MANIFEST" `
    -Label "tracked production license manifest"
Assert-CandidateFails `
    -Path "new-game-project/battle/manifests/licensed_source_manifest.template.json" `
    -Text '{"schema_version":1,"manifest_kind":"LICENSED_SOURCE","manifest_mode":"TEMPLATE","scope_id":"X","target_data_generation":"X","records":[{"source_id":"REAL"}]}' `
    -MessagePattern "BATTLE_ASSET_LICENSE_TEMPLATE" `
    -Label "non-empty public license template"
Assert-CandidateFails `
    -Path "new-game-project/battle/fixtures/synthetic/p0/synthetic_generation_manifest.json" `
    -Text '{"schema_version":1,"manifest_kind":"SYNTHETIC_GENERATION","generation_id":"X","scope_id":"X","source_class":"SYNTHETIC_FIXTURE","allowed_use":"TEST_ONLY","fixture_sets":["X"],"records":[{"species":1}]}' `
    -MessagePattern "BATTLE_ASSET_SYNTHETIC_MANIFEST" `
    -Label "synthetic manifest containing records"
Assert-CandidateFails `
    -Path "new-game-project/battle/manifests/work_items/P0_FAKE.json" `
    -Text '{"schema_version":1,"path":"D:\\private\\catalog.json"}' `
    -MessagePattern "BATTLE_ASSET_ABSOLUTE_PATH" `
    -Label "machine-local path in tracked JSON"

$oversizedBytes = [byte[]]::new(1048577)
Assert-Throws -Label "oversized tracked source" -MessagePattern "BATTLE_ASSET_TOO_LARGE" `
    -Action {
        Test-BattleAssetCandidate `
            -RelativePath "new-game-project/battle/tests/catalog/oversized.ps1" `
            -Bytes $oversizedBytes
    }

& $validatorPath -ProjectRoot $ProjectRoot -GenerationMode Synthetic

$missingProductionManifest = Join-Path ([IO.Path]::GetTempPath()) (
    "maizang-missing-license-" + [Guid]::NewGuid().ToString("N") + ".json"
)
Assert-Throws -Label "missing production authorization" `
    -MessagePattern "BATTLE_P0_LICENSED_SOURCE_REQUIRED" -Action {
        & $validatorPath -ProjectRoot $ProjectRoot -GenerationMode Production `
            -LicensedSourceManifestPath $missingProductionManifest
    }
Assert-Throws -Label "template used as production authorization" `
    -MessagePattern "BATTLE_P0_LICENSED_SOURCE_REQUIRED" -Action {
        & $validatorPath -ProjectRoot $ProjectRoot -GenerationMode Production `
            -LicensedSourceManifestPath $licenseTemplatePath
    }

Write-Host "P0_ASSET_BOUNDARY_TEST_OK"
