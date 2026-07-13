[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotContractRoot = "D:\PokemonSV-Battle-Architecture\docs\godot"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battleRoot = Join-Path $ProjectRoot "new-game-project\battle"
$validatorPath = Join-Path $battleRoot "tools\battle_catalog\validators\validate_p0_manifests.ps1"
$strictJsonPath = Join-Path $battleRoot "tools\battle_catalog\validators\strict_json_support.ps1"
$scopePath = Join-Path $battleRoot "manifests\battle_scope_manifest.json"
$utf8NoBom = [Text.UTF8Encoding]::new($false)

. $strictJsonPath

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

function Write-TestJson {
    param([string]$Path, [object]$Value)

    $json = $Value | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($Path, $json.TrimEnd() + "`n", $utf8NoBom)
}

function Get-LowerSha256 {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$parseErrors = @()
Get-ChildItem -LiteralPath (Join-Path $battleRoot "tools") -Recurse -Filter "*.ps1" -File |
    ForEach-Object {
        $tokens = $null
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile(
            $_.FullName,
            [ref]$tokens,
            [ref]$errors
        ) | Out-Null
        foreach ($error in @($errors)) {
            $parseErrors += "$($_.FullName): $($error.Message)"
        }
    }
if ($parseErrors.Count -gt 0) {
    throw "Battle PowerShell parse failures:`n$($parseErrors -join "`n")"
}

$parsed = ConvertFrom-BattleStrictJson `
    -Text '{"value":1,"items":[true,false,null],"text":"ok"}' `
    -Label "valid strict JSON"
if ([int64]$parsed.value -ne 1 -or @($parsed.items).Count -ne 3 -or $parsed.text -ne "ok") {
    throw "Strict JSON parser changed a valid document."
}

$invalidJsonCases = @(
    @{Label = "duplicate key"; Text = '{"a":1,"a":2}'; Pattern = "Duplicate object key"},
    @{Label = "leading zero"; Text = '{"a":01}'; Pattern = "Leading zero"},
    @{Label = "floating point"; Text = '{"a":1.0}'; Pattern = "bounded integers only"},
    @{Label = "NaN"; Text = '{"a":NaN}'; Pattern = "Invalid JSON literal"},
    @{Label = "trailing comma"; Text = '{"a":1,}'; Pattern = "Trailing comma"},
    @{Label = "UTF-8 BOM"; Text = ([string][char]0xfeff + '{}'); Pattern = "BOM is not permitted"}
)
foreach ($case in $invalidJsonCases) {
    $text = [string]$case.Text
    Assert-Throws -Label "strict JSON $($case.Label)" `
        -MessagePattern ([string]$case.Pattern) -Action {
            ConvertFrom-BattleStrictJson -Text $text -Label ([string]$case.Label) | Out-Null
        }
}

& $validatorPath -ProjectRoot $ProjectRoot

Assert-Throws -Label "production without licensed data" `
    -MessagePattern "BATTLE_P0_LICENSED_SOURCE_REQUIRED" -Action {
        & $validatorPath -ProjectRoot $ProjectRoot -GenerationMode Production
    }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "maizang-p0-manifest-test-" + [Guid]::NewGuid().ToString("N")
)
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $unknownScopePath = Join-Path $tempRoot "unknown_scope.json"
    $scopeText = [IO.File]::ReadAllText($scopePath, [Text.Encoding]::UTF8)
    $scopeWithUnknown = [regex]::Replace(
        $scopeText,
        '^\{',
        "{`n  `"unexpected_property`": true,",
        1
    )
    [IO.File]::WriteAllText($unknownScopePath, $scopeWithUnknown, $utf8NoBom)
    Assert-Throws -Label "unknown scope property" -MessagePattern "unknown properties" -Action {
        & $validatorPath -ProjectRoot $ProjectRoot -ScopeManifestPath $unknownScopePath
    }

    $contractPath = Join-Path $GodotContractRoot "22-full-data-and-text-battle-implementation-todo.md"
    if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
        throw "Godot contract test dependency is missing: $contractPath"
    }
    $validWorkItem = [ordered]@{
        schema_version = 1
        work_item_id = "P0.MANIFEST_CONTRACTS"
        godot_contract_refs = @(
            [ordered]@{
                document = "22-full-data-and-text-battle-implementation-todo.md"
                section = "P0: scope, authorization, and asset boundary"
                sha256 = Get-LowerSha256 $contractPath
            }
        )
        source_evidence_refs = @(
            [ordered]@{
                source_kind = "PROJECT_DECISION"
                source_repository = "MaiZangEngine"
                relative_path = "new-game-project/battle/manifests/battle_scope_manifest.json"
                symbol = "MAIZANG_GEN9_SINGLE_PLAYER_TEXT_V1"
                sha256 = Get-LowerSha256 $scopePath
            }
        )
        source_test_evidence_refs = @()
        licensed_data_refs = @()
        mechanism_ids = @()
        coverage_targets = @()
        target_godot_types = @()
        fixture_ids = @()
        presentation_cue_ids = @()
        known_ambiguities = @()
        completion_status = "SPECIFIED"
    }
    $validWorkItemPath = Join-Path $tempRoot "valid_work_item.json"
    Write-TestJson -Path $validWorkItemPath -Value $validWorkItem
    & $validatorPath -ProjectRoot $ProjectRoot -WorkItemPaths $validWorkItemPath `
        -GodotContractRoot $GodotContractRoot

    $invalidWorkItem = [ordered]@{}
    foreach ($key in $validWorkItem.Keys) {
        $invalidWorkItem[$key] = $validWorkItem[$key]
    }
    $invalidWorkItem.godot_contract_refs = @()
    $invalidWorkItem.source_evidence_refs = @()
    $invalidWorkItemPath = Join-Path $tempRoot "invalid_work_item.json"
    Write-TestJson -Path $invalidWorkItemPath -Value $invalidWorkItem
    Assert-Throws -Label "empty work item evidence" `
        -MessagePattern "at least one Godot contract reference" -Action {
            & $validatorPath -ProjectRoot $ProjectRoot `
                -WorkItemPaths $invalidWorkItemPath `
                -GodotContractRoot $GodotContractRoot
        }

    $staleWorkItem = [ordered]@{}
    foreach ($key in $validWorkItem.Keys) {
        $staleWorkItem[$key] = $validWorkItem[$key]
    }
    $staleWorkItem.source_evidence_refs = @(
        [ordered]@{
            source_kind = "PROJECT_DECISION"
            source_repository = "MaiZangEngine"
            relative_path = "new-game-project/battle/manifests/battle_scope_manifest.json"
            symbol = "MAIZANG_GEN9_SINGLE_PLAYER_TEXT_V1"
            sha256 = ("0" * 64)
        }
    )
    $staleWorkItemPath = Join-Path $tempRoot "stale_work_item.json"
    Write-TestJson -Path $staleWorkItemPath -Value $staleWorkItem
    Assert-Throws -Label "stale source evidence hash" `
        -MessagePattern "source evidence hash is stale" -Action {
            & $validatorPath -ProjectRoot $ProjectRoot `
                -WorkItemPaths $staleWorkItemPath `
                -GodotContractRoot $GodotContractRoot
        }
}
finally {
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
    $systemTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if (-not $resolvedTempRoot.StartsWith(
        $systemTempRoot + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove a test directory outside the system temp root."
    }
    Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
}

Write-Host "P0_MANIFEST_CONTRACT_TEST_OK"
