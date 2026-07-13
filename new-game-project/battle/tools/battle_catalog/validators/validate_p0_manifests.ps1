[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$ScopeManifestPath = "",
    [string]$LicensedSourceManifestPath = "",
    [string]$SyntheticGenerationManifestPath = "",
    [string]$SourceAuditManifestPath = "",
    [string[]]$WorkItemPaths = @(),
    [string]$GodotContractRoot = "",
    [string]$SourceEvidenceRoot = "",

    [ValidateSet("Synthetic", "Production")]
    [string]$GenerationMode = "Synthetic"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "strict_json_support.ps1")

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battleRoot = Join-Path $ProjectRoot "new-game-project\battle"
$schemaRoot = Join-Path $battleRoot "tools\battle_catalog\schemas"

if ([string]::IsNullOrWhiteSpace($ScopeManifestPath)) {
    $ScopeManifestPath = Join-Path $battleRoot "manifests\battle_scope_manifest.json"
}
if ([string]::IsNullOrWhiteSpace($LicensedSourceManifestPath)) {
    $LicensedSourceManifestPath = if ($GenerationMode -eq "Production") {
        Join-Path $battleRoot "local_data\source\licensed_source_manifest.json"
    }
    else {
        Join-Path $battleRoot "manifests\licensed_source_manifest.template.json"
    }
}
if ([string]::IsNullOrWhiteSpace($SyntheticGenerationManifestPath)) {
    $SyntheticGenerationManifestPath = Join-Path $battleRoot `
        "fixtures\synthetic\p0\synthetic_generation_manifest.json"
}
if ([string]::IsNullOrWhiteSpace($SourceAuditManifestPath)) {
    $SourceAuditManifestPath = Join-Path $battleRoot "manifests\source_audit_disposition_manifest.template.json"
}

$shaPattern = '^[0-9a-f]{64}$'
$stableKeyPattern = '^[A-Z0-9_.-]+$'
$relativePathPattern = '^(?![A-Za-z]:[\\/])(?![\\/]).+'
$completionStatuses = @(
    "NOT_STARTED", "SPECIFIED", "IMPORTED", "BOUND", "IMPLEMENTED",
    "VERIFIED", "RELEASED", "BLOCKED_SOURCE", "REJECTED_UNVERIFIED",
    "DEFERRED_N0", "OUT_OF_SCOPE_PRESENTATION",
    "MERGED_INTO_OTHER_MECHANISM"
)
$scopeDispositions = @(
    "IMPLEMENT", "MERGED_INTO_OTHER_MECHANISM", "DEFERRED_N0", "TEXT_ONLY",
    "OUT_OF_SCOPE_PRESENTATION", "REJECTED_UNVERIFIED", "NOT_APPLICABLE"
)

function Read-StrictJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $value = Read-BattleStrictJsonFile -Path $fullPath -Label $Label
    if ($null -eq $value -or $value -is [Array] -or $value -isnot [PSCustomObject]) {
        throw "$Label root must be a JSON object: $fullPath"
    }
    return $value
}

function Assert-ExactProperties {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Object,
        [Parameter(Mandatory = $true)][string[]]$Required,
        [string[]]$Optional = @(),
        [Parameter(Mandatory = $true)][string]$Context
    )

    $actual = @($Object.PSObject.Properties.Name)
    foreach ($name in $Required) {
        if ($name -notin $actual) {
            throw "$Context is missing required property '$name'."
        }
    }
    $allowed = @($Required) + @($Optional)
    $unknown = @($actual | Where-Object { $_ -notin $allowed })
    if ($unknown.Count -gt 0) {
        throw "$Context contains unknown properties: $($unknown -join ', ')."
    }
}

function Assert-StringValue {
    param(
        [AllowEmptyString()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [switch]$AllowEmpty
    )

    if ($Value -isnot [string]) {
        throw "$Context must be a string."
    }
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace([string]$Value)) {
        throw "$Context must not be empty."
    }
}

function Assert-EnumValue {
    param(
        [object]$Value,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-StringValue -Value $Value -Context $Context
    if ([string]$Value -notin $Allowed) {
        throw "$Context has unsupported value '$Value'."
    }
}

function Assert-UniqueStringArray {
    param(
        [object[]]$Values,
        [Parameter(Mandatory = $true)][string]$Context,
        [switch]$AllowEmpty
    )

    $items = @($Values)
    if (-not $AllowEmpty -and $items.Count -eq 0) {
        throw "$Context must contain at least one item."
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in $items) {
        Assert-StringValue -Value $item -Context "$Context item"
        if (-not $seen.Add([string]$item)) {
            throw "$Context contains duplicate value '$item'."
        }
    }
}

function Assert-ExactStringSet {
    param(
        [object[]]$Actual,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-UniqueStringArray -Values @($Actual) -Context $Context
    $actualStrings = @($Actual | ForEach-Object { [string]$_ })
    $missing = @($Expected | Where-Object { $_ -notin $actualStrings })
    $extra = @($actualStrings | Where-Object { $_ -notin $Expected })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        throw "$Context differs from the frozen contract. Missing=[$($missing -join ', ')] Extra=[$($extra -join ', ')]."
    }
}

function Assert-Sha256 {
    param([object]$Value, [string]$Context, [switch]$AllowEmpty)

    Assert-StringValue -Value $Value -Context $Context -AllowEmpty:$AllowEmpty
    if ($AllowEmpty -and [string]::IsNullOrEmpty([string]$Value)) {
        return
    }
    if ([string]$Value -cnotmatch $shaPattern) {
        throw "$Context must be a lowercase SHA-256 value."
    }
}

function Get-LowerSha256 {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-RelativePath {
    param([object]$Value, [string]$Context)

    Assert-StringValue -Value $Value -Context $Context
    if ([string]$Value -notmatch $relativePathPattern -or [string]$Value -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "$Context must be a normalized relative path without parent traversal."
    }
}

function Get-ContainedFullPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        throw "$Context requires an explicit root path."
    }
    Assert-RelativePath -Value $RelativePath -Context $Context
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath(
        (Join-Path $fullRoot $RelativePath.Replace('/', '\'))
    )
    if (-not $fullPath.StartsWith(
        $fullRoot + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "$Context escapes its declared root."
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "$Context does not resolve to a readable file: $RelativePath"
    }
    return $fullPath
}

function Test-SchemaContracts {
    $schemaNames = @(
        "battle_scope_manifest.schema.json",
        "licensed_source_manifest.schema.json",
        "implementation_work_item.schema.json",
        "source_audit_disposition_manifest.schema.json",
        "synthetic_generation_manifest.schema.json"
    )
    foreach ($schemaName in $schemaNames) {
        $schema = Read-StrictJson -Path (Join-Path $schemaRoot $schemaName) -Label $schemaName
        if ($schema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema") {
            throw "$schemaName must use JSON Schema draft 2020-12."
        }
        if ($schema.additionalProperties -ne $false) {
            throw "$schemaName root must reject unknown properties."
        }
    }

    $workItemSchema = Read-StrictJson `
        -Path (Join-Path $schemaRoot "implementation_work_item.schema.json") `
        -Label "ImplementationWorkItem schema"
    if ([int]$workItemSchema.properties.godot_contract_refs.minItems -ne 1 -or
        [int]$workItemSchema.properties.source_evidence_refs.minItems -ne 1) {
        throw "ImplementationWorkItem schema must require non-empty contract and source evidence references."
    }
}

function Test-BattleScopeManifest {
    param([PSCustomObject]$Manifest)

    $rootProperties = @(
        "schema_version", "manifest_kind", "scope_id", "target_data_generation",
        "rule_behavior_version", "compatibility_policy", "data_domains",
        "ruleset_families", "action_kinds", "source_classes",
        "scope_dispositions", "deferred_capabilities", "presentation_policy",
        "local_data_policy"
    )
    Assert-ExactProperties -Object $Manifest -Required $rootProperties -Context "BattleScopeManifest"
    if ([int]$Manifest.schema_version -ne 1 -or $Manifest.manifest_kind -ne "BATTLE_SCOPE") {
        throw "BattleScopeManifest has an unsupported kind or schema version."
    }
    if ($Manifest.scope_id -cnotmatch $stableKeyPattern -or
        $Manifest.target_data_generation -cnotmatch $stableKeyPattern) {
        throw "BattleScopeManifest scope and generation IDs must be stable uppercase keys."
    }
    if ([int]$Manifest.rule_behavior_version -lt 1) {
        throw "BattleScopeManifest rule_behavior_version must be positive."
    }
    if ($Manifest.compatibility_policy -ne "EXACT_SCOPE_CATALOG_RULE_HASH") {
        throw "BattleScopeManifest must fail closed on exact compatibility hashes."
    }

    Assert-ExactStringSet -Actual @($Manifest.data_domains) -Expected @(
        "SPECIES", "FORM", "TYPE", "MOVE", "ABILITY", "ITEM", "GROWTH",
        "LEARNSET", "EGG", "EVOLUTION", "RULE_METADATA"
    ) -Context "BattleScopeManifest.data_domains"
    Assert-ExactStringSet -Actual @($Manifest.ruleset_families) -Expected @(
        "STANDARD_SINGLE", "STANDARD_DOUBLE", "WILD", "TRAINER", "FACILITY",
        "RAID", "LOCAL_SPECIAL_FEATURE_PACK"
    ) -Context "BattleScopeManifest.ruleset_families"
    Assert-ExactStringSet -Actual @($Manifest.action_kinds) -Expected @(
        "FIGHT", "ITEM", "SWITCH", "ESCAPE", "SKIP", "CANNOT_ACT",
        "REVIVE", "CHEER", "ROOTING", "EXTRA_ACTION"
    ) -Context "BattleScopeManifest.action_kinds"
    Assert-ExactStringSet -Actual @($Manifest.scope_dispositions) `
        -Expected $scopeDispositions -Context "BattleScopeManifest.scope_dispositions"
    Assert-ExactStringSet -Actual @($Manifest.deferred_capabilities) -Expected @(
        "REMOTE_PEER", "ROOM_MATCHMAKING", "ACK_HISTORY", "RETRANSMIT",
        "RECONNECT", "SPECTATOR", "HOST_MIGRATION", "NETWORK_TRANSPORT"
    ) -Context "BattleScopeManifest.deferred_capabilities"

    $sourceClassMap = @{}
    foreach ($sourceClass in @($Manifest.source_classes)) {
        Assert-ExactProperties -Object $sourceClass -Required @("kind", "allowed_use") `
            -Context "BattleScopeManifest.source_classes entry"
        Assert-EnumValue -Value $sourceClass.kind -Allowed @(
            "AUTHORING_DATA", "PUBLIC_BEHAVIOR_EVIDENCE", "PROJECT_DECISION",
            "SYNTHETIC_FIXTURE"
        ) -Context "source class kind"
        if ($sourceClassMap.ContainsKey([string]$sourceClass.kind)) {
            throw "BattleScopeManifest contains duplicate source class '$($sourceClass.kind)'."
        }
        $sourceClassMap[[string]$sourceClass.kind] = [string]$sourceClass.allowed_use
    }
    if ($sourceClassMap.Count -ne 4 -or
        $sourceClassMap.AUTHORING_DATA -ne "CATALOG_VALUES_WITH_VERIFIED_LICENSE_ONLY" -or
        $sourceClassMap.PUBLIC_BEHAVIOR_EVIDENCE -ne "BEHAVIOR_CLAIMS_AND_CROSS_CHECKS_ONLY" -or
        $sourceClassMap.PROJECT_DECISION -ne "GODOT_ARCHITECTURE_AND_POLICY_ONLY" -or
        $sourceClassMap.SYNTHETIC_FIXTURE -ne "PUBLIC_TESTS_WITH_PROJECT_OWNED_VALUES_ONLY") {
        throw "BattleScopeManifest source class usage is not the frozen P0 contract."
    }

    Assert-ExactProperties -Object $Manifest.presentation_policy `
        -Required @("runtime_mode", "out_of_scope", "required_text_fallback") `
        -Context "BattleScopeManifest.presentation_policy"
    if ($Manifest.presentation_policy.runtime_mode -ne "TEXT_ONLY" -or
        $Manifest.presentation_policy.required_text_fallback -ne $true) {
        throw "BattleScopeManifest presentation must remain text-only with required fallback text."
    }
    Assert-ExactStringSet -Actual @($Manifest.presentation_policy.out_of_scope) -Expected @(
        "MODEL", "TEXTURE", "ANIMATION", "AUDIO", "BATTLE_CAMERA", "PRODUCTION_HUD"
    ) -Context "BattleScopeManifest.presentation_policy.out_of_scope"

    Assert-ExactProperties -Object $Manifest.local_data_policy -Required @(
        "source_root", "normalized_root", "runtime_root", "generated_root",
        "production_requires_licensed_records", "missing_license_policy"
    ) -Context "BattleScopeManifest.local_data_policy"
    $expectedRoots = @{
        source_root = "local_data/source"
        normalized_root = "local_data/normalized"
        runtime_root = "local_data/runtime"
        generated_root = "generated"
    }
    foreach ($key in $expectedRoots.Keys) {
        if ($Manifest.local_data_policy.$key -ne $expectedRoots[$key]) {
            throw "BattleScopeManifest.local_data_policy.$key changed from the isolated battle root."
        }
    }
    if ($Manifest.local_data_policy.production_requires_licensed_records -ne $true -or
        $Manifest.local_data_policy.missing_license_policy -ne "FAIL_PRODUCTION_ALLOW_SYNTHETIC") {
        throw "BattleScopeManifest must block production when licensed data is unavailable."
    }
}

function Test-LicensedSourceManifest {
    param([PSCustomObject]$Manifest)

    Assert-ExactProperties -Object $Manifest -Required @(
        "schema_version", "manifest_kind", "manifest_mode", "scope_id",
        "target_data_generation", "records"
    ) -Context "LicensedSourceManifest"
    if ([int]$Manifest.schema_version -ne 1 -or $Manifest.manifest_kind -ne "LICENSED_SOURCE") {
        throw "LicensedSourceManifest has an unsupported kind or schema version."
    }
    Assert-EnumValue -Value $Manifest.manifest_mode -Allowed @("TEMPLATE", "PRODUCTION") `
        -Context "LicensedSourceManifest.manifest_mode"

    $records = @($Manifest.records)
    if ($GenerationMode -eq "Production" -and
        ($Manifest.manifest_mode -ne "PRODUCTION" -or $records.Count -eq 0)) {
        throw "BATTLE_P0_LICENSED_SOURCE_REQUIRED: Production generation requires a PRODUCTION LicensedSourceManifest with at least one verified record."
    }
    if ($Manifest.manifest_mode -eq "TEMPLATE" -and $records.Count -ne 0) {
        throw "Public LicensedSourceManifest templates must not contain source records."
    }

    $seenIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in $records) {
        Assert-ExactProperties -Object $record -Required @(
            "source_id", "source_class", "license_basis", "license_expression",
            "license_evidence_ref", "allowed_domains", "source_version",
            "record_count", "field_count", "content_sha256",
            "local_relative_path", "license_status"
        ) -Context "LicensedSourceManifest record"
        if ($record.source_id -cnotmatch $stableKeyPattern -or
            -not $seenIds.Add([string]$record.source_id)) {
            throw "LicensedSourceManifest source IDs must be unique stable keys."
        }
        if ($record.source_class -ne "AUTHORING_DATA" -or
            $record.license_status -ne "LICENSE_VERIFIED") {
            throw "LicensedSourceManifest records must be verified authoring data."
        }
        Assert-EnumValue -Value $record.license_basis -Allowed @(
            "PROJECT_OWNED", "PERMISSIVE_LICENSE", "PUBLIC_DOMAIN",
            "EXPLICIT_WRITTEN_PERMISSION"
        ) -Context "licensed source basis"
        Assert-RelativePath -Value $record.license_evidence_ref -Context "license evidence reference"
        Assert-UniqueStringArray -Values @($record.allowed_domains) -Context "licensed source domains"
        if ([int64]$record.record_count -lt 1 -or [int64]$record.field_count -lt 1) {
            throw "Licensed source record and field counts must be positive."
        }
        Assert-Sha256 -Value $record.content_sha256 -Context "licensed source content hash"
        Assert-RelativePath -Value $record.local_relative_path -Context "licensed source local path"
        if ([string]$record.local_relative_path -notmatch '^local_data/source/') {
            throw "Licensed source data must remain below local_data/source/."
        }
    }
}

function Test-SyntheticGenerationManifest {
    param([PSCustomObject]$Manifest)

    Assert-ExactProperties -Object $Manifest -Required @(
        "schema_version", "manifest_kind", "generation_id", "scope_id",
        "source_class", "allowed_use", "fixture_sets", "records"
    ) -Context "SyntheticGenerationManifest"
    if ([int]$Manifest.schema_version -ne 1 -or
        $Manifest.manifest_kind -ne "SYNTHETIC_GENERATION" -or
        [string]$Manifest.generation_id -cnotmatch $stableKeyPattern -or
        $Manifest.source_class -ne "SYNTHETIC_FIXTURE" -or
        $Manifest.allowed_use -ne "TEST_ONLY") {
        throw "SyntheticGenerationManifest does not describe a project-owned test-only generation."
    }
    Assert-UniqueStringArray -Values @($Manifest.fixture_sets) `
        -Context "SyntheticGenerationManifest.fixture_sets"
    if (@($Manifest.records).Count -ne 0) {
        throw "P0 synthetic generation must not embed catalog or Pokemon records."
    }
}

function Test-SourceAuditManifest {
    param([PSCustomObject]$Manifest)

    Assert-ExactProperties -Object $Manifest -Required @(
        "schema_version", "manifest_kind", "manifest_mode", "scope_id",
        "baseline", "entries"
    ) -Context "SourceAuditDispositionManifest"
    if ([int]$Manifest.schema_version -ne 1 -or
        $Manifest.manifest_kind -ne "SOURCE_AUDIT_DISPOSITION") {
        throw "SourceAuditDispositionManifest has an unsupported kind or schema version."
    }
    Assert-EnumValue -Value $Manifest.manifest_mode -Allowed @("TEMPLATE", "BASELINE") `
        -Context "SourceAuditDispositionManifest.manifest_mode"
    Assert-ExactProperties -Object $Manifest.baseline -Required @(
        "source_index_manifest_sha256", "repositories", "expected_counts"
    ) -Context "SourceAuditDispositionManifest.baseline"
    Assert-Sha256 -Value $Manifest.baseline.source_index_manifest_sha256 `
        -Context "source index manifest hash" -AllowEmpty

    foreach ($repository in @($Manifest.baseline.repositories)) {
        Assert-ExactProperties -Object $repository -Required @(
            "repository", "branch", "commit", "head_tree",
            "source_aggregate_sha256", "dirty_paths_sha256", "dirty_path_count"
        ) -Context "SourceAuditDispositionManifest repository baseline"
        Assert-EnumValue -Value $repository.repository -Allowed @("battlelogic", "pokelib") `
            -Context "source audit repository"
        if ([string]$repository.commit -cnotmatch '^[0-9a-f]{40}$' -or
            [string]$repository.head_tree -cnotmatch '^[0-9a-f]{40}$') {
            throw "Source audit repository commit/tree must be lowercase Git object IDs."
        }
        Assert-Sha256 -Value $repository.source_aggregate_sha256 `
            -Context "source aggregate hash"
        Assert-Sha256 -Value $repository.dirty_paths_sha256 `
            -Context "dirty paths hash"
        if ([int64]$repository.dirty_path_count -lt 0) {
            throw "Source audit dirty_path_count must not be negative."
        }
    }

    $entries = @($Manifest.entries)
    if ($Manifest.manifest_mode -eq "TEMPLATE" -and
        (@($Manifest.baseline.repositories).Count -ne 0 -or $entries.Count -ne 0)) {
        throw "Public SourceAuditDispositionManifest templates must not contain source records."
    }
    if ($Manifest.manifest_mode -eq "BASELINE" -and $entries.Count -eq 0) {
        throw "A source audit BASELINE must contain classified entries."
    }
    if ($Manifest.manifest_mode -ne "BASELINE") {
        return
    }

    $allowedCategories = @(
        "MODULE", "SOURCE_FILE", "SECTION", "EVENT_HANDLER", "EVENT",
        "COMMAND", "ACTION", "INTERRUPT", "PROTOCOL", "BATTLE_MODE",
        "SCHEMA", "TEST", "SCRIPT_SCENARIO", "LOGIC_EDGE"
    )
    $allowedEvidenceStatuses = @(
        "CLEAN_INDEXED", "DIRTY_UNVERIFIED", "MISSING_SOURCE", "STALE_INDEX"
    )
    $allowedReleaseStatuses = @(
        "NOT_STARTED", "SPECIFIED", "IMPORTED", "BOUND", "IMPLEMENTED",
        "VERIFIED", "RELEASED", "BLOCKED_SOURCE", "REJECTED_UNVERIFIED"
    )
    $allowedTestDispositions = @(
        "PORT_BEHAVIOR", "REPLACED_BY_SYNTHETIC_FIXTURE", "NOT_APPLICABLE"
    )
    $seenAuditIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $seenIdentities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $entries) {
        Assert-ExactProperties -Object $entry -Required @(
            "audit_id", "source_repository", "source_path", "source_sha256",
            "source_symbol_or_edge", "source_category", "domain_package",
            "mechanism_ids", "branch_ids", "target_godot_types", "fixture_ids",
            "scope_disposition", "evidence_status", "release_status",
            "test_evidence_disposition", "classification_rule_id", "reason_code",
            "reason", "known_ambiguities", "review_status"
        ) -Context "SourceAuditDispositionManifest entry"
        if ([string]$entry.audit_id -cnotmatch '^AUDIT_[0-9A-F]{16}$' -or
            -not $seenAuditIds.Add([string]$entry.audit_id)) {
            throw "Source audit IDs must be unique AUDIT_ plus 16 uppercase hex digits."
        }
        Assert-EnumValue -Value $entry.source_repository -Allowed @("battlelogic", "pokelib") `
            -Context "source audit entry repository"
        Assert-RelativePath -Value $entry.source_path -Context "source audit entry path"
        Assert-Sha256 -Value $entry.source_sha256 -Context "source audit entry hash"
        Assert-StringValue -Value $entry.source_symbol_or_edge `
            -Context "source audit entry symbol/edge"
        Assert-StringValue -Value $entry.domain_package -Context "source audit domain package"
        Assert-EnumValue -Value $entry.source_category -Allowed $allowedCategories `
            -Context "source audit category"
        Assert-EnumValue -Value $entry.scope_disposition -Allowed $scopeDispositions `
            -Context "source audit scope disposition"
        Assert-EnumValue -Value $entry.evidence_status -Allowed $allowedEvidenceStatuses `
            -Context "source audit evidence status"
        Assert-EnumValue -Value $entry.release_status -Allowed $allowedReleaseStatuses `
            -Context "source audit release status"
        Assert-EnumValue -Value $entry.test_evidence_disposition `
            -Allowed $allowedTestDispositions -Context "source test evidence disposition"
        Assert-StringValue -Value $entry.classification_rule_id `
            -Context "source audit classification rule"
        Assert-StringValue -Value $entry.reason_code -Context "source audit reason code"
        Assert-StringValue -Value $entry.reason -Context "source audit reason"
        Assert-EnumValue -Value $entry.review_status -Allowed @(
            "GENERATED_SCOPE_CLASSIFICATION", "HUMAN_REVIEWED", "VERIFIED"
        ) -Context "source audit review status"
        $identity = "$($entry.source_category)`t$($entry.source_repository)`t$($entry.source_path)`t$($entry.source_symbol_or_edge)"
        if (-not $seenIdentities.Add($identity)) {
            throw "Source audit contains a duplicate source identity: $identity"
        }
        if ($entry.evidence_status -ne "CLEAN_INDEXED" -and
            $entry.release_status -notin @("BLOCKED_SOURCE", "REJECTED_UNVERIFIED")) {
            throw "Unverified source evidence cannot advance its release status."
        }
        if ($entry.scope_disposition -eq "REJECTED_UNVERIFIED" -and
            $entry.release_status -ne "REJECTED_UNVERIFIED") {
            throw "Rejected source scope must retain REJECTED_UNVERIFIED release status."
        }
        if ($entry.source_category -notin @("TEST", "SCRIPT_SCENARIO") -and
            $entry.test_evidence_disposition -ne "NOT_APPLICABLE") {
            throw "Only test/scenario entries may declare a test port disposition."
        }
    }
    $expectedProperties = @($Manifest.baseline.expected_counts.PSObject.Properties.Name)
    if ("audit_entries" -notin $expectedProperties -or
        [int64]$Manifest.baseline.expected_counts.audit_entries -ne $entries.Count) {
        throw "Source audit entry count does not match its sealed baseline."
    }
}

function Test-ImplementationWorkItem {
    param([PSCustomObject]$WorkItem, [string]$Label)

    Assert-ExactProperties -Object $WorkItem -Required @(
        "schema_version", "work_item_id", "godot_contract_refs",
        "source_evidence_refs", "source_test_evidence_refs",
        "licensed_data_refs", "mechanism_ids", "coverage_targets",
        "target_godot_types", "fixture_ids", "presentation_cue_ids",
        "known_ambiguities", "completion_status"
    ) -Context $Label
    if ([int]$WorkItem.schema_version -ne 1 -or
        [string]$WorkItem.work_item_id -cnotmatch $stableKeyPattern) {
        throw "$Label has an invalid schema version or work item ID."
    }
    if (@($WorkItem.godot_contract_refs).Count -eq 0) {
        throw "$Label must contain at least one Godot contract reference."
    }
    foreach ($reference in @($WorkItem.godot_contract_refs)) {
        Assert-ExactProperties -Object $reference -Required @("document", "section", "sha256") `
            -Context "$Label Godot contract reference"
        if ([string]$reference.document -notmatch '^[0-9A-Za-z_.-]+\.md$') {
            throw "$Label Godot contract document must be a file name below docs/godot/."
        }
        Assert-StringValue -Value $reference.section -Context "$Label Godot contract section"
        Assert-Sha256 -Value $reference.sha256 -Context "$Label Godot contract hash"
        $contractPath = Get-ContainedFullPath -Root $GodotContractRoot `
            -RelativePath ([string]$reference.document) `
            -Context "$Label Godot contract reference"
        if ((Get-LowerSha256 $contractPath) -cne [string]$reference.sha256) {
            throw "$Label Godot contract hash is stale for '$($reference.document)'."
        }
    }

    if (@($WorkItem.source_evidence_refs).Count -eq 0) {
        throw "$Label must contain at least one source evidence reference."
    }
    foreach ($reference in @($WorkItem.source_evidence_refs) + @($WorkItem.source_test_evidence_refs)) {
        Assert-ExactProperties -Object $reference -Required @(
            "source_kind", "source_repository", "relative_path", "symbol", "sha256"
        ) -Context "$Label source evidence reference"
        Assert-EnumValue -Value $reference.source_kind -Allowed @(
            "SOURCE_CODE", "SOURCE_SCHEMA", "SOURCE_TEST", "PROJECT_DECISION"
        ) -Context "$Label source kind"
        Assert-EnumValue -Value $reference.source_repository -Allowed @(
            "battlelogic", "pokelib", "MaiZangEngine"
        ) -Context "$Label source repository"
        Assert-RelativePath -Value $reference.relative_path -Context "$Label source path"
        Assert-StringValue -Value $reference.symbol -Context "$Label source symbol"
        Assert-Sha256 -Value $reference.sha256 -Context "$Label source hash"
        if ($reference.source_repository -in @("battlelogic", "pokelib") -and
            $reference.source_kind -eq "PROJECT_DECISION") {
            throw "$Label external evidence must identify actual code, schema, or test material."
        }
        if ($reference.source_repository -eq "MaiZangEngine" -and
            $reference.source_kind -ne "PROJECT_DECISION") {
            throw "$Label MaiZang evidence is reserved for explicit project decisions."
        }
        $evidenceRoot = if ($reference.source_repository -eq "MaiZangEngine") {
            $ProjectRoot
        }
        else {
            Join-Path $SourceEvidenceRoot ([string]$reference.source_repository)
        }
        $evidencePath = Get-ContainedFullPath -Root $evidenceRoot `
            -RelativePath ([string]$reference.relative_path) `
            -Context "$Label source evidence reference"
        if ((Get-LowerSha256 $evidencePath) -cne [string]$reference.sha256) {
            throw "$Label source evidence hash is stale for '$($reference.relative_path)'."
        }
        $extension = [IO.Path]::GetExtension($evidencePath).ToLowerInvariant()
        if ($reference.source_kind -eq "SOURCE_CODE" -and
            $extension -notin @(".c", ".cc", ".cpp", ".h", ".hpp")) {
            throw "$Label SOURCE_CODE evidence must resolve to an actual code file."
        }
        if ($reference.source_kind -eq "SOURCE_SCHEMA" -and
            $extension -notin @(".fbs", ".json", ".csv", ".tab")) {
            throw "$Label SOURCE_SCHEMA evidence must resolve to an actual schema file."
        }
    }
    Assert-EnumValue -Value $WorkItem.completion_status -Allowed $completionStatuses `
        -Context "$Label completion status"
}

Test-SchemaContracts
$scopeManifest = Read-StrictJson -Path $ScopeManifestPath -Label "BattleScopeManifest"
if ($GenerationMode -eq "Production" -and
    -not (Test-Path -LiteralPath $LicensedSourceManifestPath -PathType Leaf)) {
    throw "BATTLE_P0_LICENSED_SOURCE_REQUIRED: Production generation requires the ignored local_data/source/licensed_source_manifest.json."
}
$licensedManifest = Read-StrictJson -Path $LicensedSourceManifestPath -Label "LicensedSourceManifest"
$sourceAuditManifest = Read-StrictJson -Path $SourceAuditManifestPath -Label "SourceAuditDispositionManifest"
$syntheticManifest = $null
if ($GenerationMode -eq "Synthetic") {
    $syntheticManifest = Read-StrictJson -Path $SyntheticGenerationManifestPath `
        -Label "SyntheticGenerationManifest"
}

Test-BattleScopeManifest -Manifest $scopeManifest
Test-LicensedSourceManifest -Manifest $licensedManifest
Test-SourceAuditManifest -Manifest $sourceAuditManifest
if ($null -ne $syntheticManifest) {
    Test-SyntheticGenerationManifest -Manifest $syntheticManifest
}

if ($licensedManifest.scope_id -ne $scopeManifest.scope_id -or
    $sourceAuditManifest.scope_id -ne $scopeManifest.scope_id) {
    throw "P0 manifests do not reference the same frozen scope ID."
}
if ($licensedManifest.target_data_generation -ne $scopeManifest.target_data_generation) {
    throw "LicensedSourceManifest does not target the frozen data generation."
}
if ($null -ne $syntheticManifest -and
    $syntheticManifest.scope_id -ne $scopeManifest.scope_id) {
    throw "SyntheticGenerationManifest does not reference the frozen battle scope."
}

foreach ($workItemPath in @($WorkItemPaths)) {
    $workItem = Read-StrictJson -Path $workItemPath -Label "ImplementationWorkItem"
    Test-ImplementationWorkItem -WorkItem $workItem -Label "ImplementationWorkItem '$workItemPath'"
}

Write-Host "P0 manifest contracts validated."
Write-Host "  Scope SHA-256:         $(Get-LowerSha256 $ScopeManifestPath)"
Write-Host "  Licensed template hash: $(Get-LowerSha256 $LicensedSourceManifestPath)"
Write-Host "  Source audit hash:      $(Get-LowerSha256 $SourceAuditManifestPath)"
if ($null -ne $syntheticManifest) {
    Write-Host "  Synthetic input hash:   $(Get-LowerSha256 $SyntheticGenerationManifestPath)"
}
Write-Host "  Generation mode:        $GenerationMode"
Write-Host "P0_MANIFEST_CONTRACTS_OK"
