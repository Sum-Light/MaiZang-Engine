[CmdletBinding()]
param([string]$ProjectRoot = "")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battleRoot = Join-Path $ProjectRoot "new-game-project\battle"
$supportPath = Join-Path $battleRoot `
    "tools\battle_specs\validators\p2_id_manifest_support.ps1"
$validatorPath = Join-Path $battleRoot `
    "tools\battle_specs\validators\validate_p2_id_manifests.ps1"
$scopeGatePath = Join-Path $battleRoot "tools\check_battle_scope.ps1"
$stablePath = Join-Path $battleRoot `
    "specs\id_manifests\battle_stable_ids.json"
$presentationPath = Join-Path $battleRoot `
    "specs\presentation\presentation_contracts.json"
$stableSchemaPath = Join-Path $battleRoot `
    "tools\battle_specs\schemas\stable_id_manifest.schema.json"
$presentationSchemaPath = Join-Path $battleRoot `
    "tools\battle_specs\schemas\presentation_contracts.schema.json"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$script:checks = 0

. $supportPath

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:checks += 1
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Passes {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $script:checks += 1
    try {
        $null = & $Action
    }
    catch {
        throw "$Label failed unexpectedly: $($_.Exception.Message)"
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$MessagePattern,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $script:checks += 1
    $caught = $null
    try {
        $null = & $Action
    }
    catch {
        $caught = $_
    }
    if ($null -eq $caught) {
        throw "$Label did not fail."
    }
    if ([string]$caught.Exception.Message -notmatch $MessagePattern) {
        throw (
            "$Label failed with an unexpected message: " +
            $caught.Exception.Message
        )
    }
}

function Copy-JsonValue {
    param([Parameter(Mandatory = $true)][object]$Value)

    $json = ConvertTo-BattleCanonicalJson -Value $Value
    return ConvertFrom-BattleStrictJson -Text $json -Label "test JSON clone"
}

function Get-StableDomain {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Manifest,
        [Parameter(Mandatory = $true)][string]$Domain
    )

    $matches = @($Manifest.domains | Where-Object {
        [string]$_.domain -ceq $Domain
    })
    if ($matches.Count -ne 1) {
        throw "Test fixture could not resolve stable domain '$Domain'."
    }
    return [PSCustomObject]$matches[0]
}

function New-StableEntry {
    param(
        [long]$ScopeId,
        [long]$Id,
        [string]$DebugKey,
        [string]$Status = "ACTIVE",
        [string[]]$Aliases = @()
    )

    return [pscustomobject][ordered]@{
        scope_id = $ScopeId
        id = $Id
        debug_key = $DebugKey
        status = $Status
        aliases = [object[]]@($Aliases)
    }
}

function New-PayloadField {
    param(
        [string]$FieldName,
        [string]$ValueKind,
        [string]$StableDomain,
        [long]$Minimum,
        [long]$Maximum,
        [bool]$Required,
        [string]$Cardinality = "ONE",
        [long]$MaxItems = 1
    )

    return [pscustomobject][ordered]@{
        field_name = $FieldName
        value_kind = $ValueKind
        stable_domain = $StableDomain
        minimum = $Minimum
        maximum = $Maximum
        required = $Required
        cardinality = $Cardinality
        max_items = $MaxItems
    }
}

function New-PayloadSchema {
    param(
        [long]$Id,
        [string]$DebugKey,
        [object[]]$Fields,
        [string]$Status = "ACTIVE"
    )

    return [pscustomobject][ordered]@{
        payload_schema_id = $Id
        debug_key = $DebugKey
        status = $Status
        aliases = [object[]]@()
        schema_version = 1
        fields = [object[]]@($Fields)
    }
}

function New-PresentationCue {
    param(
        [long]$Id,
        [string]$DebugKey,
        [long[]]$Tags,
        [long]$PayloadSchemaId,
        [string]$Status = "ACTIVE",
        [string]$FallbackTextKey = "BATTLE.TEST",
        [string]$SemanticPhase = "AFTER"
    )

    return [pscustomobject][ordered]@{
        presentation_cue_id = $Id
        debug_key = $DebugKey
        status = $Status
        aliases = [object[]]@()
        presentation_tags = [object[]]@($Tags)
        semantic_phase = $SemanticPhase
        information_class = "REQUIRED_INFORMATION"
        fallback_text_key = $FallbackTextKey
        local_barrier_policy = "NONE"
        payload_schema_id = $PayloadSchemaId
    }
}

function New-StableBaseline {
    param([Parameter(Mandatory = $true)][PSCustomObject]$EmptyManifest)

    $manifest = Copy-JsonValue $EmptyManifest
    $manifest.generation = 1
    (Get-StableDomain $manifest "MECHANISM").entries = [object[]]@(
        (New-StableEntry 0 1 "MECH_SYNTHETIC_ONE"),
        (New-StableEntry 0 2 "MECH_SYNTHETIC_TWO")
    )
    (Get-StableDomain $manifest "BRANCH").entries = [object[]]@(
        (New-StableEntry 1 1 "BRANCH_ONE_START"),
        (New-StableEntry 1 3 "BRANCH_ONE_END"),
        (New-StableEntry 2 1 "BRANCH_TWO_START")
    )
    (Get-StableDomain $manifest "RNG_DRAW").entries = [object[]]@(
        (New-StableEntry 1 1 "RNG_DRAW_ONE"),
        (New-StableEntry 2 1 "RNG_DRAW_TWO")
    )
    (Get-StableDomain $manifest "EVENT").entries = [object[]]@(
        (New-StableEntry 0 1 "EVENT_ONE" "ACTIVE" @("EVENT_LEGACY")),
        (New-StableEntry 0 3 "EVENT_THREE")
    )
    return $manifest
}

function New-PresentationBaseline {
    param([Parameter(Mandatory = $true)][PSCustomObject]$EmptyManifest)

    $manifest = Copy-JsonValue $EmptyManifest
    $manifest.generation = 1
    $manifest.payload_schemas = [object[]]@(
        (New-PayloadSchema 1 "PAYLOAD_HIT" @(
            (New-PayloadField "entity_id" "STABLE_ID" "ENTITY" 1 2147483647 $true),
            (New-PayloadField "hit_count" "PUBLIC_INT" "NONE" 0 10 $false),
            (New-PayloadField "is_critical" "PUBLIC_BOOL" "NONE" 0 1 $true),
            (New-PayloadField "message_ids" "STABLE_ID" "MESSAGE" 1 2147483647 $false "MANY" 4)
        )),
        (New-PayloadSchema 2 "PAYLOAD_MESSAGE" @(
            (New-PayloadField "message_id" "STABLE_ID" "MESSAGE" 1 2147483647 $true)
        ))
    )
    $manifest.cues = [object[]]@(
        (New-PresentationCue 1 "CUE_HIT" @(1, 2, 5) 1 "ACTIVE" "BATTLE.HIT"),
        (New-PresentationCue 2 "CUE_MESSAGE" @(5) 2 "ACTIVE" "BATTLE.MESSAGE")
    )
    return $manifest
}

function Write-ContainedBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath((Join-Path $rootFull (
        $RelativePath.Replace('/', '\')
    )))
    if (-not $fullPath.StartsWith(
        $rootFull + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to write a test file outside its repository root."
    }
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    [IO.File]::WriteAllBytes($fullPath, $Bytes)
}

function Write-ContainedText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Text
    )

    Write-ContainedBytes -Root $Root -RelativePath $RelativePath `
        -Bytes $utf8NoBom.GetBytes($Text)
}

function Write-ContainedJson {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][PSCustomObject]$Value
    )

    Write-ContainedText -Root $Root -RelativePath $RelativePath `
        -Text (ConvertTo-BattleCanonicalJson -Value $Value)
}

function Invoke-TestGit {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& git -C $Repository @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exitCode -ne 0) {
        throw "Test Git command failed: git $($Arguments -join ' ')`n$($output -join "`n")"
    }
    return @($output)
}

function Remove-ContainedTestFile {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath((Join-Path $rootFull (
        $RelativePath.Replace('/', '\')
    )))
    if (-not $fullPath.StartsWith(
        $rootFull + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove a test file outside its repository root."
    }
    Remove-Item -LiteralPath $fullPath -Force
}

$stableManifest = Read-BattleStrictJsonFile -Path $stablePath `
    -Label "tracked stable ID manifest"
$presentationManifest = Read-BattleStrictJsonFile -Path $presentationPath `
    -Label "tracked presentation manifest"
$stableSchema = Read-BattleStrictJsonFile -Path $stableSchemaPath `
    -Label "stable ID schema"
$presentationSchema = Read-BattleStrictJsonFile -Path $presentationSchemaPath `
    -Label "presentation schema"

Assert-Condition (
    [string]$stableSchema.PSObject.Properties['$schema'].Value -ceq
    "https://json-schema.org/draft/2020-12/schema"
) "Stable ID schema does not declare JSON Schema draft 2020-12."
Assert-Condition (
    [string]$presentationSchema.PSObject.Properties['$schema'].Value -ceq
    "https://json-schema.org/draft/2020-12/schema"
) "Presentation schema does not declare JSON Schema draft 2020-12."
Assert-Condition ($stableSchema.additionalProperties -eq $false) `
    "Stable ID schema root must reject unknown properties."
Assert-Condition ($presentationSchema.additionalProperties -eq $false) `
    "Presentation schema root must reject unknown properties."

$stableResultOne = Test-P2StableIdManifest -Manifest $stableManifest
$stableResultTwo = Test-P2StableIdManifest -Manifest $stableManifest
$presentationResultOne = Test-P2PresentationContracts `
    -Manifest $presentationManifest
$presentationResultTwo = Test-P2PresentationContracts `
    -Manifest $presentationManifest
Assert-Condition (
    $stableResultOne.CanonicalJson -ceq $stableResultTwo.CanonicalJson
) "Stable ID canonical bytes changed between identical runs."
Assert-Condition ($stableResultOne.Sha256 -ceq $stableResultTwo.Sha256) `
    "Stable ID canonical hash changed between identical runs."
Assert-Condition (
    $presentationResultOne.CanonicalJson -ceq
    $presentationResultTwo.CanonicalJson
) "Presentation canonical bytes changed between identical runs."
Assert-Condition (
    $presentationResultOne.Sha256 -ceq $presentationResultTwo.Sha256
) "Presentation canonical hash changed between identical runs."
Assert-Condition (@($stableManifest.domains).Count -eq 15) `
    "Tracked stable ID manifest does not contain exactly 15 domains."
Assert-Condition (@($presentationManifest.tags).Count -eq 7) `
    "Tracked presentation manifest does not contain exactly seven tags."
Assert-Passes -Label "repository P2 validator" -Action {
    & $validatorPath -ProjectRoot $ProjectRoot -Mode Repository
}
Assert-Throws -Label "candidate path pair guard" `
    -MessagePattern "P2_MANIFEST_PATH_PAIR" -Action {
        & $validatorPath -ProjectRoot $ProjectRoot -Mode Repository `
            -StableIdManifestPath $stablePath
    }
Assert-Throws -Label "baseline path pair guard" `
    -MessagePattern "P2_BASELINE_PATH_PAIR" -Action {
        & $validatorPath -ProjectRoot $ProjectRoot -Mode Repository `
            -BaselineStableIdManifestPath $stablePath
    }
Assert-Throws -Label "explicit Worktree candidate requires baseline" `
    -MessagePattern "P2_WORKTREE_BASELINE_REQUIRED" -Action {
        & $validatorPath -ProjectRoot $ProjectRoot -Mode Worktree `
            -StableIdManifestPath $stablePath `
            -PresentationManifestPath $presentationPath
    }

$stableBaseline = New-StableBaseline $stableManifest
Assert-Passes -Label "scoped local ID reuse" -Action {
    Test-P2StableIdManifest -Manifest $stableBaseline
}
$branchEntries = @((Get-StableDomain $stableBaseline "BRANCH").entries)
$rngDrawEntries = @((Get-StableDomain $stableBaseline "RNG_DRAW").entries)
Assert-Condition (
    @($branchEntries | Where-Object { [long]$_.id -eq 1 }).Count -eq 2
) "BRANCH local ID 1 was not reusable across mechanism scopes."
Assert-Condition (
    @($rngDrawEntries | Where-Object { [long]$_.id -eq 1 }).Count -eq 2
) "RNG_DRAW local ID 1 was not reusable across mechanism scopes."

$candidate = Copy-JsonValue $stableBaseline
(Get-StableDomain $candidate "EVENT").entries[0].scope_id = 1
Assert-Throws -Label "global domain nonzero scope" `
    -MessagePattern "P2_STABLE_GLOBAL_SCOPE" -Action {
        Test-P2StableIdManifest -Manifest $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
(Get-StableDomain $candidate "BRANCH").entries[0].scope_id = 0
Assert-Throws -Label "scoped domain zero scope" `
    -MessagePattern "P2_STABLE_SCOPED_ID" -Action {
        Test-P2StableIdManifest -Manifest $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
(Get-StableDomain $candidate "BRANCH").entries[0].scope_id = 99
Assert-Throws -Label "branch with unknown mechanism owner" `
    -MessagePattern "P2_STABLE_SCOPE_OWNER_UNKNOWN" -Action {
        Test-P2StableIdManifest -Manifest $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
(Get-StableDomain $candidate "RNG_DRAW").entries[0].scope_id = 99
Assert-Throws -Label "RNG draw with unknown mechanism owner" `
    -MessagePattern "P2_STABLE_SCOPE_OWNER_UNKNOWN" -Action {
        Test-P2StableIdManifest -Manifest $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
(Get-StableDomain $candidate "PHASE").entries = [object[]]@(
    (New-StableEntry 99 1 "PHASE_ORPHAN")
)
Assert-Throws -Label "phase with unknown resolver owner" `
    -MessagePattern "P2_STABLE_SCOPE_OWNER_UNKNOWN" -Action {
        Test-P2StableIdManifest -Manifest $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
(Get-StableDomain $candidate "MECHANISM").entries[0].status = "TOMBSTONE"
Assert-Throws -Label "active scoped ID with tombstoned owner" `
    -MessagePattern "P2_STABLE_SCOPE_OWNER_INACTIVE" -Action {
        Test-P2StableIdManifest -Manifest $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
(Get-StableDomain $candidate "MECHANISM").entries[0].status = "TOMBSTONE"
foreach ($entry in @((Get-StableDomain $candidate "BRANCH").entries)) {
    if ([long]$entry.scope_id -eq 1) {
        $entry.status = "TOMBSTONE"
    }
}
foreach ($entry in @((Get-StableDomain $candidate "RNG_DRAW").entries)) {
    if ([long]$entry.scope_id -eq 1) {
        $entry.status = "TOMBSTONE"
    }
}
Assert-Passes -Label "tombstoned scoped IDs retain tombstoned owner" -Action {
    Test-P2StableIdManifest -Manifest $candidate
}
$candidate = Copy-JsonValue $stableBaseline
(Get-StableDomain $candidate "EVENT").entries[1].id = 1
Assert-Throws -Label "duplicate stable ID" `
    -MessagePattern "P2_STABLE_ID_ORDER" -Action {
        Test-P2StableIdManifest -Manifest $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
$events = Get-StableDomain $candidate "EVENT"
$events.entries = [object[]]@($events.entries[1], $events.entries[0])
Assert-Throws -Label "reordered stable IDs" `
    -MessagePattern "P2_STABLE_ID_ORDER" -Action {
        Test-P2StableIdManifest -Manifest $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
(Get-StableDomain $candidate "EVENT").entries[1].id = 2147483648L
Assert-Throws -Label "out-of-range stable ID" `
    -MessagePattern "P2_JSON_INTEGER_RANGE" -Action {
        Test-P2StableIdManifest -Manifest $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
(Get-StableDomain $candidate "EVENT").entries[1].aliases = [object[]]@("EVENT_ONE")
Assert-Throws -Label "stable alias collision" `
    -MessagePattern "P2_ALIAS_COLLISION" -Action {
        Test-P2StableIdManifest -Manifest $candidate
    }

$stableAppend = Copy-JsonValue $stableBaseline
$stableAppend.generation = 2
$events = Get-StableDomain $stableAppend "EVENT"
$events.entries[0].debug_key = "EVENT_ONE_RENAMED"
$events.entries[0].status = "TOMBSTONE"
$events.entries[0].aliases = [object[]]@("EVENT_LEGACY", "EVENT_ONE")
$events.entries = [object[]]@(
    $events.entries[0],
    $events.entries[1],
    (New-StableEntry 0 4 "EVENT_FOUR")
)
Assert-Passes -Label "append, tombstone, and aliased rename evolution" -Action {
    Test-P2StableIdEvolution -Baseline $stableBaseline -Candidate $stableAppend
}

$candidate = Copy-JsonValue $stableBaseline
$candidate.generation = 2
$events = Get-StableDomain $candidate "EVENT"
$events.entries = [object[]]@($events.entries[0])
Assert-Throws -Label "stable entry deletion" `
    -MessagePattern "P2_EVOLUTION_ENTRY_REMOVED" -Action {
        Test-P2StableIdEvolution -Baseline $stableBaseline -Candidate $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
$candidate.generation = 2
(Get-StableDomain $candidate "EVENT").entries[0].id = 2
Assert-Throws -Label "stable ID replacement" `
    -MessagePattern "P2_EVOLUTION_ENTRY_REORDERED" -Action {
        Test-P2StableIdEvolution -Baseline $stableBaseline -Candidate $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
$candidate.generation = 2
$events = Get-StableDomain $candidate "EVENT"
$events.entries = [object[]]@($events.entries[1], $events.entries[0])
Assert-Throws -Label "stable baseline reorder" `
    -MessagePattern "P2_(STABLE_ID_ORDER|EVOLUTION_ENTRY_REORDERED)" -Action {
        Test-P2StableIdEvolution -Baseline $stableBaseline -Candidate $candidate
    }
$tombstoneBaseline = Copy-JsonValue $stableBaseline
(Get-StableDomain $tombstoneBaseline "EVENT").entries[0].status = "TOMBSTONE"
$candidate = Copy-JsonValue $tombstoneBaseline
$candidate.generation = 2
(Get-StableDomain $candidate "EVENT").entries[0].status = "ACTIVE"
Assert-Throws -Label "stable tombstone revival" `
    -MessagePattern "P2_EVOLUTION_STATUS" -Action {
        Test-P2StableIdEvolution -Baseline $tombstoneBaseline -Candidate $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
$candidate.generation = 2
$events = Get-StableDomain $candidate "EVENT"
$events.entries = [object[]]@(
    $events.entries[0],
    $events.entries[1],
    (New-StableEntry 0 2 "EVENT_REUSED_GAP")
)
Assert-Throws -Label "stable gap reuse" `
    -MessagePattern "P2_(STABLE_ID_ORDER|EVOLUTION_NEW_ID)" -Action {
        Test-P2StableIdEvolution -Baseline $stableBaseline -Candidate $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
$candidate.generation = 2
(Get-StableDomain $candidate "EVENT").entries[0].aliases = [object[]]@()
Assert-Throws -Label "stable alias removal" `
    -MessagePattern "P2_EVOLUTION_ALIAS_REMOVED" -Action {
        Test-P2StableIdEvolution -Baseline $stableBaseline -Candidate $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
$candidate.generation = 2
(Get-StableDomain $candidate "EVENT").entries[0].debug_key = "EVENT_RENAMED_WITHOUT_ALIAS"
Assert-Throws -Label "stable rename without prior-key alias" `
    -MessagePattern "P2_EVOLUTION_RENAME_ALIAS" -Action {
        Test-P2StableIdEvolution -Baseline $stableBaseline -Candidate $candidate
    }
$candidate = Copy-JsonValue $stableAppend
$candidate.generation = 1
Assert-Throws -Label "stable changed content without generation increment" `
    -MessagePattern "P2_EVOLUTION_GENERATION_INCREMENT" -Action {
        Test-P2StableIdEvolution -Baseline $stableBaseline -Candidate $candidate
    }
$candidate = Copy-JsonValue $stableBaseline
$candidate.generation = 2
Assert-Throws -Label "stable unchanged content with generation increment" `
    -MessagePattern "P2_EVOLUTION_GENERATION_UNCHANGED" -Action {
        Test-P2StableIdEvolution -Baseline $stableBaseline -Candidate $candidate
    }

$presentationBaseline = New-PresentationBaseline $presentationManifest
Assert-Passes -Label "valid synthetic payload and cues" -Action {
    Test-P2PresentationContracts -Manifest $presentationBaseline
}
$candidate = Copy-JsonValue $presentationBaseline
$candidate.cues[0].presentation_tags = [object[]]@()
Assert-Throws -Label "empty presentation tag set" `
    -MessagePattern "P2_JSON_ARRAY_SIZE" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.cues[0].presentation_tags = [object[]]@(1, 7)
Assert-Throws -Label "PRES_NONE mixed with another tag" `
    -MessagePattern "P2_CUE_PRES_NONE_EXCLUSIVE" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.cues[0].presentation_tags = [object[]]@(8)
Assert-Throws -Label "unknown presentation tag" `
    -MessagePattern "P2_JSON_INTEGER_RANGE" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.tags[0].status = "TOMBSTONE"
Assert-Throws -Label "active cue referencing tombstone tag" `
    -MessagePattern "P2_CUE_TAG_INACTIVE" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.cues[0].payload_schema_id = 99
Assert-Throws -Label "unknown presentation payload" `
    -MessagePattern "P2_CUE_PAYLOAD_UNKNOWN" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.payload_schemas[0].status = "TOMBSTONE"
Assert-Throws -Label "active cue referencing tombstone payload" `
    -MessagePattern "P2_CUE_PAYLOAD_INACTIVE" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.payload_schemas[0].fields[0].value_kind = "VECTOR"
Assert-Throws -Label "unknown payload value kind" `
    -MessagePattern "P2_JSON_ENUM" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.payload_schemas[0].fields[0].stable_domain = "NONE"
Assert-Throws -Label "stable payload without stable domain" `
    -MessagePattern "P2_PAYLOAD_STABLE_ID_FIELD" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.payload_schemas[0].fields[1].minimum = 11
$candidate.payload_schemas[0].fields[1].maximum = 10
Assert-Throws -Label "payload inverted public integer range" `
    -MessagePattern "P2_PAYLOAD_FIELD_RANGE" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.payload_schemas[0].fields[2].maximum = 2
Assert-Throws -Label "payload public boolean range" `
    -MessagePattern "P2_PAYLOAD_PUBLIC_BOOL_FIELD" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.payload_schemas[0].fields[0].max_items = 2
Assert-Throws -Label "payload ONE cardinality max_items" `
    -MessagePattern "P2_PAYLOAD_CARDINALITY" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$fields = @($candidate.payload_schemas[0].fields)
$candidate.payload_schemas[0].fields = [object[]]@(
    $fields[0], $fields[0], $fields[1], $fields[2], $fields[3]
)
Assert-Throws -Label "duplicate payload field" `
    -MessagePattern "P2_PAYLOAD_FIELD_(ORDER|DUPLICATE)" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$fields = @($candidate.payload_schemas[0].fields)
$candidate.payload_schemas[0].fields = [object[]]@(
    $fields[1], $fields[0], $fields[2], $fields[3]
)
Assert-Throws -Label "reordered payload fields" `
    -MessagePattern "P2_PAYLOAD_FIELD_ORDER" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.cues[0].fallback_text_key = "../BATTLE.HIT"
Assert-Throws -Label "path-like cue fallback" `
    -MessagePattern "P2_JSON_STRING_FORMAT" -Action {
        Test-P2PresentationContracts -Manifest $candidate
    }

$presentationAppend = Copy-JsonValue $presentationBaseline
$presentationAppend.generation = 2
$presentationAppend.payload_schemas[0].status = "TOMBSTONE"
$presentationAppend.cues[0].status = "TOMBSTONE"
$presentationAppend.payload_schemas = [object[]]@(
    $presentationAppend.payload_schemas[0],
    $presentationAppend.payload_schemas[1],
    (New-PayloadSchema 3 "PAYLOAD_TURN" @(
        (New-PayloadField "turn_index" "PUBLIC_INT" "NONE" 0 65535 $true)
    ))
)
$presentationAppend.cues = [object[]]@(
    $presentationAppend.cues[0],
    $presentationAppend.cues[1],
    (New-PresentationCue 3 "CUE_NO_PRESENTATION" @(7) 3 "ACTIVE" "BATTLE.TURN")
)
Assert-Passes -Label "presentation append and tombstone evolution" -Action {
    Test-P2PresentationEvolution -Baseline $presentationBaseline `
        -Candidate $presentationAppend
}
$candidate = Copy-JsonValue $presentationBaseline
$candidate.generation = 2
$candidate.cues = [object[]]@($candidate.cues[0])
Assert-Throws -Label "presentation entry deletion" `
    -MessagePattern "P2_EVOLUTION_ENTRY_REMOVED" -Action {
        Test-P2PresentationEvolution -Baseline $presentationBaseline `
            -Candidate $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.generation = 2
$candidate.cues = [object[]]@($candidate.cues[1], $candidate.cues[0])
Assert-Throws -Label "presentation entry reorder" `
    -MessagePattern "P2_(CUE_ID_ORDER|EVOLUTION_ENTRY_REORDERED)" -Action {
        Test-P2PresentationEvolution -Baseline $presentationBaseline `
            -Candidate $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.generation = 2
$candidate.cues[0].fallback_text_key = "BATTLE.CHANGED"
Assert-Throws -Label "presentation semantic mutation" `
    -MessagePattern "P2_EVOLUTION_SEMANTICS" -Action {
        Test-P2PresentationEvolution -Baseline $presentationBaseline `
            -Candidate $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.generation = 2
$candidate.payload_schemas[0].fields[1].maximum = 11
Assert-Throws -Label "presentation payload semantic mutation" `
    -MessagePattern "P2_EVOLUTION_SEMANTICS" -Action {
        Test-P2PresentationEvolution -Baseline $presentationBaseline `
            -Candidate $candidate
    }
$presentationTombstoneBaseline = Copy-JsonValue $presentationBaseline
$presentationTombstoneBaseline.payload_schemas[0].status = "TOMBSTONE"
$presentationTombstoneBaseline.cues[0].status = "TOMBSTONE"
$candidate = Copy-JsonValue $presentationTombstoneBaseline
$candidate.generation = 2
$candidate.payload_schemas[0].status = "ACTIVE"
$candidate.cues[0].status = "ACTIVE"
Assert-Throws -Label "presentation tombstone revival" `
    -MessagePattern "P2_EVOLUTION_STATUS" -Action {
        Test-P2PresentationEvolution `
            -Baseline $presentationTombstoneBaseline -Candidate $candidate
    }
$candidate = Copy-JsonValue $presentationAppend
$candidate.generation = 1
Assert-Throws -Label "presentation generation not incremented" `
    -MessagePattern "P2_EVOLUTION_GENERATION_INCREMENT" -Action {
        Test-P2PresentationEvolution -Baseline $presentationBaseline `
            -Candidate $candidate
    }
$candidate = Copy-JsonValue $presentationBaseline
$candidate.generation = 2
Assert-Throws -Label "unchanged presentation generation increment" `
    -MessagePattern "P2_EVOLUTION_GENERATION_UNCHANGED" -Action {
        Test-P2PresentationEvolution -Baseline $presentationBaseline `
            -Candidate $candidate
    }

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$tempRoot = Join-Path $tempParent (
    "maizang-p2-id-contract-test-" + [Guid]::NewGuid().ToString("N")
)
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $null = Invoke-TestGit $tempRoot @("init", "--quiet")
    $null = Invoke-TestGit $tempRoot @("config", "user.name", "Battle Contract Test")
    $null = Invoke-TestGit $tempRoot @("config", "user.email", "battle-test@example.invalid")

    $nestedGitRoot = Join-Path $tempRoot "nested"
    New-Item -ItemType Directory -Path $nestedGitRoot | Out-Null
    Assert-Throws -Label "Git root mismatch" `
        -MessagePattern "P2_GIT_ROOT_MISMATCH" -Action {
            & $validatorPath -ProjectRoot $nestedGitRoot -Mode Staged
        }

    $oversizedRelative = "oversized-stable-ids.json"
    Write-ContainedBytes $tempRoot $oversizedRelative ([byte[]]::new(524289))
    $oversizedPath = Join-Path $tempRoot $oversizedRelative
    Assert-Throws -Label "direct manifest size bound" `
        -MessagePattern "P2_MANIFEST_TOO_LARGE" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Repository `
                -StableIdManifestPath $oversizedPath `
                -PresentationManifestPath $presentationPath
        }

    $foundationRelative = (
        "new-game-project/battle/scripts/foundation/" +
        "battle_p2_temp_foundation.gd"
    )
    Write-ContainedText $tempRoot $foundationRelative (
        "class_name BattleP2TempFoundation`n" +
        "extends RefCounted`n"
    )
    $null = Invoke-TestGit $tempRoot @("add", "--", $foundationRelative)
    $null = Invoke-TestGit $tempRoot @("commit", "--quiet", "-m", "Foundation")

    $stableRelative = (
        "new-game-project/battle/specs/id_manifests/battle_stable_ids.json"
    )
    $presentationRelative = (
        "new-game-project/battle/specs/presentation/presentation_contracts.json"
    )
    $stableSchemaRelative = (
        "new-game-project/battle/tools/battle_specs/schemas/" +
        "stable_id_manifest.schema.json"
    )
    $presentationSchemaRelative = (
        "new-game-project/battle/tools/battle_specs/schemas/" +
        "presentation_contracts.schema.json"
    )
    $p0GovernanceRelatives = @(
        "new-game-project/battle/manifests/source_audit/source_audit_policy.json",
        "new-game-project/battle/manifests/source_audit/source_audit_seal.json",
        "new-game-project/battle/manifests/source_audit/source_index_baseline.json"
    )
    $stableBytes = [IO.File]::ReadAllBytes($stablePath)
    $presentationBytes = [IO.File]::ReadAllBytes($presentationPath)
    Write-ContainedBytes $tempRoot $stableRelative $stableBytes
    Write-ContainedBytes $tempRoot $presentationRelative $presentationBytes
    $stableSchemaBytes = [IO.File]::ReadAllBytes($stableSchemaPath)
    $presentationSchemaBytes = [IO.File]::ReadAllBytes($presentationSchemaPath)
    Write-ContainedBytes $tempRoot $stableSchemaRelative $stableSchemaBytes
    Write-ContainedBytes $tempRoot $presentationSchemaRelative `
        $presentationSchemaBytes
    foreach ($relativePath in $p0GovernanceRelatives) {
        $sourcePath = Join-Path $ProjectRoot $relativePath.Replace('/', '\')
        Write-ContainedBytes $tempRoot $relativePath `
            ([IO.File]::ReadAllBytes($sourcePath))
    }
    $contractPaths = @(
        $stableRelative,
        $presentationRelative,
        $stableSchemaRelative,
        $presentationSchemaRelative
    ) + $p0GovernanceRelatives
    $null = Invoke-TestGit $tempRoot (@("add", "--") + $contractPaths)
    $invalidInitialStable = Copy-JsonValue $stableManifest
    $invalidInitialStable.generation = 2
    Write-ContainedJson $tempRoot $stableRelative $invalidInitialStable
    $null = Invoke-TestGit $tempRoot @("add", "--", $stableRelative)
    Assert-Throws -Label "initial generation must start at one" `
        -MessagePattern "P2_INITIAL_GENERATION" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Staged
        }
    Write-ContainedBytes $tempRoot $stableRelative $stableBytes
    $null = Invoke-TestGit $tempRoot @("add", "--", $stableRelative)
    Assert-Passes -Label "valid staged P2 contracts" -Action {
        & $validatorPath -ProjectRoot $tempRoot -Mode Staged
    }
    $null = Invoke-TestGit $tempRoot @(
        "commit", "--quiet", "-m", "P2 contracts"
    )

    $untrackedReviewSurface = (
        "new-game-project/battle/tools/check_battle_dependencies.ps1"
    )
    Write-ContainedText $tempRoot $untrackedReviewSurface "Write-Host 'probe'`n"
    Assert-Throws -Label "untracked reviewed validation tool" `
        -MessagePattern "P2_STAGED_REVIEW_SURFACE_UNTRACKED" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Staged
        }
    Remove-ContainedTestFile $tempRoot $untrackedReviewSurface

    Write-ContainedText $tempRoot $stableSchemaRelative `
        '{"schema_version":1}'
    $null = Invoke-TestGit $tempRoot @("add", "--", $stableSchemaRelative)
    Write-ContainedBytes $tempRoot $stableSchemaRelative $stableSchemaBytes
    Assert-Throws -Label "staged review surface differs from worktree" `
        -MessagePattern "P2_STAGED_REVIEW_SURFACE_MISMATCH" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Staged
        }
    $null = Invoke-TestGit $tempRoot @("add", "--", $stableSchemaRelative)

    $validStagedStable = Copy-JsonValue $stableManifest
    $validStagedStable.generation = 2
    (Get-StableDomain $validStagedStable "EVENT").entries = [object[]]@(
        (New-StableEntry 0 1 "EVENT_STAGED_APPEND")
    )
    Write-ContainedJson $tempRoot $stableRelative $validStagedStable
    $null = Invoke-TestGit $tempRoot @("add", "--", $stableRelative)
    Assert-Passes -Label "valid staged P2 scope integration" -Action {
        & $scopeGatePath -ProjectRoot $tempRoot -Mode Staged
    }
    $null = Invoke-TestGit $tempRoot @(
        "commit", "--quiet", "-m", "Append stable ID"
    )
    $stableBytes = [IO.File]::ReadAllBytes((Join-Path $tempRoot (
        $stableRelative.Replace('/', '\')
    )))

    $dirtyInvalidStable = Copy-JsonValue $stableManifest
    $dirtyInvalidStable.generation = 3
    (Get-StableDomain $dirtyInvalidStable "EVENT").entries = [object[]]@(
        (New-StableEntry 1 1 "EVENT_INVALID_GLOBAL_SCOPE")
    )
    Write-ContainedJson $tempRoot $stableRelative $dirtyInvalidStable
    Assert-Passes -Label "staged validator ignores dirty worktree" -Action {
        & $validatorPath -ProjectRoot $tempRoot -Mode Staged
    }
    Assert-Throws -Label "worktree validator reads dirty candidate" `
        -MessagePattern "P2_STABLE_GLOBAL_SCOPE" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Worktree
        }
    $null = Invoke-TestGit $tempRoot @("add", "--", $stableRelative)
    Assert-Throws -Label "staged invalid manifest" `
        -MessagePattern "P2_STABLE_GLOBAL_SCOPE" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Staged
        }
    Assert-Throws -Label "scope gate rejects staged P2 semantics" `
        -MessagePattern "P2_STABLE_GLOBAL_SCOPE" -Action {
            & $scopeGatePath -ProjectRoot $tempRoot -Mode Staged
        }
    Write-ContainedBytes $tempRoot $stableRelative $stableBytes
    $null = Invoke-TestGit $tempRoot @("add", "--", $stableRelative)

    foreach ($coreManifest in @(
        @{Path = $stableRelative; Bytes = $stableBytes; Label = "stable ID"},
        @{
            Path = $presentationRelative
            Bytes = $presentationBytes
            Label = "presentation"
        }
    )) {
        Remove-ContainedTestFile $tempRoot ([string]$coreManifest.Path)
        $null = Invoke-TestGit $tempRoot @("add", "--all", "--")
        Assert-Throws -Label "staged deletion of $($coreManifest.Label) manifest" `
            -MessagePattern "P2_GIT_BLOB_NOT_FOUND" -Action {
                & $validatorPath -ProjectRoot $tempRoot -Mode Staged
            }
        Write-ContainedBytes $tempRoot ([string]$coreManifest.Path) `
            ([byte[]]$coreManifest.Bytes)
        $null = Invoke-TestGit $tempRoot @(
            "add", "--", ([string]$coreManifest.Path)
        )
    }

    Remove-ContainedTestFile $tempRoot $presentationRelative
    $null = Invoke-TestGit $tempRoot @("add", "--all", "--")
    $null = Invoke-TestGit $tempRoot @(
        "commit", "--quiet", "-m", "Create one-sided P2 baseline"
    )
    Write-ContainedBytes $tempRoot $presentationRelative $presentationBytes
    $null = Invoke-TestGit $tempRoot @("add", "--", $presentationRelative)
    Assert-Throws -Label "one-sided HEAD P2 baseline" `
        -MessagePattern "P2_BASELINE_PAIR" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Staged
        }
}
finally {
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot).TrimEnd('\')
    if (-not $resolvedTempRoot.StartsWith(
        $tempParent + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove a test directory outside the system temp root."
    }
    if (Test-Path -LiteralPath $resolvedTempRoot) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}

Write-Host "P2_ID_PRESENTATION_CONTRACT_TEST_OK checks=$checks"
