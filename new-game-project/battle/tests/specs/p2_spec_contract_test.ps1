[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [switch]$LoadFixturesOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battleRoot = Join-Path $ProjectRoot "new-game-project\battle"
$supportPath = Join-Path $battleRoot `
    "tools\battle_specs\validators\p2_spec_contract_support.ps1"
$validatorPath = Join-Path $battleRoot `
    "tools\battle_specs\validators\validate_p2_spec_contracts.ps1"
$stablePath = Join-Path $battleRoot `
    "specs\id_manifests\battle_stable_ids.json"
$presentationPath = Join-Path $battleRoot `
    "specs\presentation\presentation_contracts.json"
$schemaRoot = Join-Path $battleRoot "tools\battle_specs\schemas"
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

function New-MechanismSpec {
    return [pscustomobject][ordered]@{
        artifact_kind = "MECHANISM_SPEC"
        mechanism_id = 1
        debug_key = "MECH_SYNTHETIC"
        spec_schema_version = 1
        behavior_version = 1
        ruleset_mode = "ALL"
        ruleset_ids = [object[]]@()
        feature_pack_ids = [object[]]@()
        owner_module = "BATTLE.RULES"
        target_maturity = "DISCOVERED"
        project_requirement_keys = [object[]]@("P2.SYNTHETIC")
        evidence_ids = [object[]]@()
        entry_kind = "RESOLVER"
        resolver_id = 1
        phase_id = 1
        subphase_id = 0
        preconditions = [object[]]@()
        inputs = [object[]]@(
            [pscustomobject][ordered]@{
                slot_id = 1
                field_name = "base_value"
                value_kind = "SIGNED_INT"
                stable_domain = "NONE"
                minimum = 0
                maximum = 100
                unit = "COUNT"
                ownership = "SYNTHETIC_FIXTURE"
                required = $true
                cardinality = "ONE"
                max_items = 1
            }
        )
        read_set = [object[]]@()
        write_set = [object[]]@()
        history_reads = [object[]]@()
        history_writes = [object[]]@()
        counter_reads = [object[]]@()
        counter_writes = [object[]]@()
        ordering_key = [object[]]@(
            [pscustomobject][ordered]@{
                field_key = "INSTANCE_ID"
                direction = "ASC"
                source = "STABLE_ID"
            }
        )
        short_circuit = [pscustomobject][ordered]@{
            policy = "NONE"
            result_key = "RESULT"
        }
        reentry_policy = [pscustomobject][ordered]@{
            policy = "DENY"
            maximum_depth = 0
            same_instance_recall = $false
        }
        coverage_targets = [object[]]@(
            [pscustomobject][ordered]@{
                branch_id = 1
                kind = "NORMAL"
                condition_kind = "ALWAYS"
                required_oracle_kinds = [object[]]@("FORMULA")
                required_for_active_ruleset = $true
            }
        )
        parameter_slots = [object[]]@(
            [pscustomobject][ordered]@{
                slot_id = 1
                debug_key = "BASE_VALUE"
                value_kind = "SIGNED_INT"
                stable_domain = "NONE"
                minimum = 0
                maximum = 100
                unit = "COUNT"
                source_kind = "SYNTHETIC_FIXTURE"
                required = $true
            }
        )
        formula_stages = [object[]]@(
            [pscustomobject][ordered]@{
                stage_id = 1
                debug_key = "ADD_BASE"
                operation = "ADD"
                operand_slot_ids = [object[]]@(1)
                operand_units = [object[]]@("COUNT")
                parameter_slot_ids = [object[]]@(1)
                output_slot_id = 2
                result_unit = "COUNT"
                intermediate_width_bits = 32
                negative_value_policy = "ALLOW"
                result_minimum = 0
                result_maximum = 200
                modifier_event_id = 0
                modifier_aggregation = "NONE"
                rounding_mode = "TOWARD_ZERO"
                rounding_schedule = "AT_STAGE_END"
                operation_order = "LEFT_TO_RIGHT"
                clamp_min_source = "MINIMUM"
                clamp_max_source = "MAXIMUM"
                overflow_policy = "ERROR"
                divide_by_zero_policy = "ERROR"
                trace_field_keys = [object[]]@("RESULT")
            }
        )
        rng_draws = [object[]]@(
            [pscustomobject][ordered]@{
                mechanism_id = 1
                draw_id = 1
                stream_id = 1
                tag_id = 1
                draw_order = 3
                consume_condition = "WHEN_REQUIRED"
                sample_kind = "BOUNDED_INT"
                minimum_inclusive = 0
                maximum_exclusive = 100
                candidate_order = "NOT_APPLICABLE"
                draw_count_minimum = 1
                draw_count_maximum = 1
                failure_semantics = "NO_CONSUME_ERROR"
                trace_fields = [object[]]@(
                    "CURSOR_AFTER", "CURSOR_BEFORE", "DRAW_ID",
                    "MECHANISM_ID", "STREAM_ID", "TAG_ID"
                )
            }
        )
        resolver_ids = [object[]]@(1)
        event_ids = [object[]]@(1)
        handler_ids = [object[]]@(1)
        state_op_ids = [object[]]@(1)
        command_ids = [object[]]@(1)
        presentation_cue_ids = [object[]]@(1)
        result_type = "SyntheticResult"
        mutation_contracts = [object[]]@(
            [pscustomobject][ordered]@{
                state_op_id = 1
                mutation_service_key = "STATE.APPLY"
                atomic_group_id = 1
                before_field_keys = [object[]]@("HP")
                after_field_keys = [object[]]@("HP")
                idempotency_policy = "REJECT_DUPLICATE"
                failure_boundary = "ATOMIC_GROUP"
            }
        )
        command_contracts = [object[]]@(
            [pscustomobject][ordered]@{
                command_id = 1
                audience = "PUBLIC"
                presentation_cue_ids = [object[]]@(1)
                barrier_policy = "NONE"
                optional_visual = $true
                emission_order = 5
            }
        )
        execution_steps = [object[]]@(
            [pscustomobject][ordered]@{
                step_order = 1
                step_kind = "FORMULA_STAGE"
                reference_id = 1
                condition_kind = "ALWAYS"
            },
            [pscustomobject][ordered]@{
                step_order = 2
                step_kind = "EVENT_EMISSION"
                reference_id = 1
                condition_kind = "ALWAYS"
            },
            [pscustomobject][ordered]@{
                step_order = 3
                step_kind = "RNG_DRAW"
                reference_id = 1
                condition_kind = "WHEN_REQUIRED"
            },
            [pscustomobject][ordered]@{
                step_order = 4
                step_kind = "STATE_MUTATION"
                reference_id = 1
                condition_kind = "ON_SUCCESS"
            },
            [pscustomobject][ordered]@{
                step_order = 5
                step_kind = "COMMAND_EMISSION"
                reference_id = 1
                condition_kind = "ON_SUCCESS"
            }
        )
        error_contracts = [object[]]@(
            [pscustomobject][ordered]@{
                error_code = "SYNTHETIC.REJECTED"
                category = "EXPECTED_REJECTION"
                mutation_policy = "NONE_COMMITTED"
                rng_policy = "NO_CONSUME"
                termination_policy = "CONTINUE"
            }
        )
        atomicity_policy = [pscustomobject][ordered]@{
            validation_policy = "VALIDATE_ALL_BEFORE_MUTATION"
            rollback_policy = "NO_MUTATION_ON_FAILURE"
            command_capacity_preflight = $true
        }
        test_requirements = [object[]]@(
            [pscustomobject][ordered]@{
                test_kind = "FORMULA_UNIT"
                required_oracle_kinds = [object[]]@("FORMULA")
                minimum_cases = 1
                required_for_target_maturity = "DISCOVERED"
            }
        )
    }
}

function New-EventSchema {
    return [pscustomobject][ordered]@{
        artifact_kind = "EVENT_SCHEMA"
        event_id = 1
        debug_key = "EVENT_SYNTHETIC"
        schema_version = 1
        behavior_version = 1
        context_type = "SyntheticEventContext"
        readable_fields = [object[]]@()
        writable_operations = [object[]]@()
        aggregation_policy = "VISIT_ALL"
        sort_key = [object[]]@(
            [pscustomobject][ordered]@{
                field_key = "INSTANCE_ID"
                direction = "ASC"
                source = "STABLE_ID"
            }
        )
        short_circuit_rule = "NONE"
        nested_event_ids = [object[]]@()
        same_instance_recall_policy = "DENY"
        maximum_same_instance_recalls = 0
        activation_visibility = "NEXT_DISPATCH"
        removal_visibility = "AFTER_CURRENT_EVENT"
        rounding_stage_refs = [object[]]@()
        rounding_mode = "NONE"
        rounding_schedule = "NONE"
        trace_policy = [pscustomobject][ordered]@{
            level = "OFF"
            record_context_hash = $false
            record_handler_order = $false
            record_short_circuit = $false
            trace_field_keys = [object[]]@()
        }
    }
}

function New-HandlerBinding {
    return [pscustomobject][ordered]@{
        artifact_kind = "HANDLER_BINDING"
        handler_id = 1
        debug_key = "HANDLER_SYNTHETIC"
        schema_version = 1
        behavior_version = 1
        family = "DAMAGE"
        event_id = 1
        implementation_key = "synthetic_handler"
        context_type = "SyntheticEventContext"
        instance_state_kind = "STATE.NONE"
        priority_source = "EVENT_SCHEMA"
        allowed_queries = [object[]]@("BATTLE.HP")
        allowed_mutations = [object[]]@("STATE.APPLY")
        allowed_rng_draw_ids = [object[]]@(
            [pscustomobject][ordered]@{
                mechanism_id = 1
                draw_id = 1
            }
        )
        mechanism_ids = [object[]]@(1)
    }
}

function New-ResolverSpec {
    return [pscustomobject][ordered]@{
        artifact_kind = "RESOLVER_SPEC"
        resolver_id = 1
        debug_key = "RESOLVER_SYNTHETIC"
        schema_version = 1
        behavior_version = 1
        owner_module = "BATTLE.RESOLVERS"
        input_type = "SyntheticResolverInput"
        output_type = "SyntheticResolverResult"
        phases = [object[]]@(
            [pscustomobject][ordered]@{
                phase_id = 1
                phase_order = 1
                debug_key = "EXECUTE"
                subphase_ids = [object[]]@()
                entry_invariants = [object[]]@("STATE.VALID")
                exit_invariants = [object[]]@("STATE.VALID")
                reentry_policy = "DENY"
                maximum_reentries = 0
                mechanism_ids = [object[]]@(1)
            }
        )
        legal_event_emissions = [object[]]@(
            [pscustomobject][ordered]@{
                phase_id = 1
                event_id = 1
                emission_point = "DURING_PHASE"
                nested_policy = "DENY"
                maximum_nested_depth = 0
            }
        )
        allowed_nested_resolver_ids = [object[]]@()
        mutation_services = [object[]]@("STATE.APPLY")
        interruption_points = [object[]]@(
            [pscustomobject][ordered]@{
                interruption_id = 1
                phase_id = 1
                safe_boundary = "PHASE_COMMITTED"
                resume_phase_id = 1
                request_owner = "ACTOR"
            }
        )
        error_semantics = [object[]]@(
            [pscustomobject][ordered]@{
                error_code = "SYNTHETIC.ERROR"
                phase_id = 1
                state_policy = "UNCHANGED"
                termination_policy = "ABORT_RESOLVER"
            }
        )
        termination_behavior = [pscustomobject][ordered]@{
            normal_result = "RESULT.SUCCESS"
            error_result = "RESULT.ERROR"
            terminal_state = "NONE"
            pending_input_policy = "DECLARED_INTERRUPTION_ONLY"
        }
        mechanism_ids = [object[]]@(1)
    }
}

function New-TestManifestEntry {
    return [pscustomobject][ordered]@{
        artifact_kind = "TEST_MANIFEST_ENTRY"
        test_id = 1
        debug_key = "TEST_SYNTHETIC"
        schema_version = 1
        test_kind = "SCENARIO"
        fixture_id = 1
        coverage_targets = [object[]]@(
            [pscustomobject][ordered]@{
                mechanism_id = 1
                branch_id = 1
            }
        )
        expected_event_ids = [object[]]@(1)
        expected_handler_ids = [object[]]@(1)
        expected_state_op_ids = [object[]]@(1)
        expected_command_ids = [object[]]@(1)
        required_oracle_kinds = [object[]]@("SCENARIO")
    }
}

function New-MaturityFacts {
    param([ValidateSet("DISCOVERED", "SPECIFIED", "IMPLEMENTED", "VERIFIED", "RELEASED")][string]$Level)

    $rank = [Array]::IndexOf(
        @("DISCOVERED", "SPECIFIED", "IMPLEMENTED", "VERIFIED", "RELEASED"),
        $Level
    )
    [object[]]$requiredOracles = @()
    [object[]]$passedOracles = @()
    if ($rank -ge 3) {
        $requiredOracles = [object[]]@("FORMULA")
        $passedOracles = [object[]]@("FORMULA")
    }
    return [pscustomobject][ordered]@{
        identity_registered = $true
        discovery_basis_verified = $true
        specification_valid = ($rank -ge 1)
        cross_references_valid = ($rank -ge 1)
        implementation_bindings_verified = ($rank -ge 2)
        dependency_gate_passed = ($rank -ge 2)
        required_test_count = $(if ($rank -ge 3) { 1 } else { 0 })
        executed_test_count = $(if ($rank -ge 3) { 1 } else { 0 })
        passed_test_count = $(if ($rank -ge 3) { 1 } else { 0 })
        required_oracles = $requiredOracles
        passed_oracles = $passedOracles
        coverage_observed = ($rank -ge 3)
        evidence_current = ($rank -ge 3)
        release_catalog_versioned = ($rank -ge 4)
        release_migration_complete = ($rank -ge 4)
        release_change_log_complete = ($rank -ge 4)
        release_coverage_gate_passed = ($rank -ge 4)
    }
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
        [string]$Status = "ACTIVE"
    )

    return [pscustomobject][ordered]@{
        scope_id = $ScopeId
        id = $Id
        debug_key = $DebugKey
        status = $Status
        aliases = [object[]]@()
    }
}

function New-SyntheticStableRegistry {
    param([Parameter(Mandatory = $true)][PSCustomObject]$EmptyRegistry)

    $registry = Copy-JsonValue $EmptyRegistry
    $entries = @{
        MECHANISM = @(New-StableEntry 0 1 "MECH_SYNTHETIC")
        BRANCH = @(New-StableEntry 1 1 "BRANCH_SYNTHETIC")
        EVENT = @(New-StableEntry 0 1 "EVENT_SYNTHETIC")
        HANDLER = @(New-StableEntry 0 1 "HANDLER_SYNTHETIC")
        RESOLVER = @(New-StableEntry 0 1 "RESOLVER_SYNTHETIC")
        PHASE = @(New-StableEntry 1 1 "PHASE_SYNTHETIC")
        RNG_DRAW = @(New-StableEntry 1 1 "RNG_DRAW_SYNTHETIC")
        RNG_STREAM = @(New-StableEntry 0 1 "RNG_STREAM_SYNTHETIC")
        RNG_TAG = @(New-StableEntry 0 1 "RNG_TAG_SYNTHETIC")
        STATE_OP = @(New-StableEntry 0 1 "STATE_OP_SYNTHETIC")
        COMMAND = @(New-StableEntry 0 1 "COMMAND_SYNTHETIC")
        TEST = @(New-StableEntry 0 1 "TEST_SYNTHETIC")
    }
    foreach ($name in $entries.Keys) {
        (Get-StableDomain $registry $name).entries = [object[]]@($entries[$name])
    }
    return $registry
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

function Write-ContainedJson {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][PSCustomObject]$Value
    )

    Write-ContainedBytes $Root $RelativePath (
        $utf8NoBom.GetBytes((ConvertTo-BattleCanonicalJson $Value))
    )
}

function Remove-ContainedFile {
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
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        Remove-Item -LiteralPath $fullPath -Force
    }
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

function Get-NonGitSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $records = [Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $rootFull -File -Recurse) {
        $fullPath = [IO.Path]::GetFullPath($file.FullName)
        if ($fullPath.StartsWith(
            (Join-Path $rootFull ".git") + '\',
            [StringComparison]::OrdinalIgnoreCase
        )) {
            continue
        }
        $relative = $fullPath.Substring($rootFull.Length + 1).Replace('\', '/')
        $records.Add(
            "$relative|$($file.Length)|$((Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash)"
        )
    }
    $values = $records.ToArray()
    [Array]::Sort($values, [StringComparer]::Ordinal)
    return $values -join "`n"
}

function Assert-Marker {
    param(
        [Parameter(Mandatory = $true)][object[]]$Output,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Assert-Condition ((@($Output) -join "`n") -match $Pattern) `
        "$Label did not emit the expected marker."
}

function Test-StrictSchemaNode {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$RootSchema,
        [AllowNull()][object]$Node,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($null -eq $Node) {
        return
    }
    if ($Node -is [Array]) {
        $items = @($Node)
        for ($index = 0; $index -lt $items.Count; $index++) {
            Test-StrictSchemaNode $RootSchema $items[$index] `
                "$Context[$index]"
        }
        return
    }
    if ($Node -isnot [PSCustomObject]) {
        return
    }

    $referenceProperty = $Node.PSObject.Properties['$ref']
    if ($null -ne $referenceProperty) {
        $reference = [string]$referenceProperty.Value
        if ($reference.StartsWith('#/$defs/', [StringComparison]::Ordinal)) {
            $definitionName = $reference.Substring(8)
            $definitionsProperty = $RootSchema.PSObject.Properties['$defs']
            Assert-Condition (
                $null -ne $definitionsProperty -and
                $definitionsProperty.Value -is [PSCustomObject] -and
                $null -ne $definitionsProperty.Value.PSObject.Properties[$definitionName]
            ) "$Context has unresolved internal reference '$reference'."
        }
    }

    $typeProperty = $Node.PSObject.Properties['type']
    if ($null -ne $typeProperty -and [string]$typeProperty.Value -ceq 'object') {
        $additionalProperty = $Node.PSObject.Properties['additionalProperties']
        Assert-Condition (
            $null -ne $additionalProperty -and
            $additionalProperty.Value -is [bool] -and
            $additionalProperty.Value -eq $false
        ) "$Context object schema is not closed."
        $requiredProperty = $Node.PSObject.Properties['required']
        $propertiesProperty = $Node.PSObject.Properties['properties']
        Assert-Condition (
            $null -ne $requiredProperty -and
            $requiredProperty.Value -is [Array]
        ) "$Context object schema has no required array."
        Assert-Condition (
            $null -ne $propertiesProperty -and
            $propertiesProperty.Value -is [PSCustomObject]
        ) "$Context object schema has no properties object."
        $requiredNames = @(
            $requiredProperty.Value | ForEach-Object { [string]$_ } | Sort-Object
        )
        $propertyNames = @(
            $propertiesProperty.Value.PSObject.Properties.Name | Sort-Object
        )
        Assert-Condition (
            ($requiredNames -join "`n") -ceq ($propertyNames -join "`n")
        ) "$Context required fields do not exactly cover properties."
    }
    if ($null -ne $typeProperty -and [string]$typeProperty.Value -ceq 'array') {
        $maximumProperty = $Node.PSObject.Properties['maxItems']
        Assert-Condition (
            $null -ne $maximumProperty -and
            (Test-P2IntegralType $maximumProperty.Value) -and
            [long]$maximumProperty.Value -ge 0
        ) "$Context array schema has no finite maxItems."
    }

    foreach ($property in $Node.PSObject.Properties) {
        Test-StrictSchemaNode $RootSchema $property.Value `
            "$Context.$($property.Name)"
    }
}

if ($LoadFixturesOnly) {
    return
}

$contracts = @(
    [pscustomobject]@{
        Name = "MechanismSpec"
        Schema = "mechanism_spec.schema.json"
        Object = (New-MechanismSpec)
        Validator = "Test-P2MechanismSpec"
        Missing = "mechanism_id"
    },
    [pscustomobject]@{
        Name = "EventSchema"
        Schema = "event_schema.schema.json"
        Object = (New-EventSchema)
        Validator = "Test-P2EventSchema"
        Missing = "event_id"
    },
    [pscustomobject]@{
        Name = "HandlerBinding"
        Schema = "handler_binding.schema.json"
        Object = (New-HandlerBinding)
        Validator = "Test-P2HandlerBinding"
        Missing = "handler_id"
    },
    [pscustomobject]@{
        Name = "ResolverSpec"
        Schema = "resolver_spec.schema.json"
        Object = (New-ResolverSpec)
        Validator = "Test-P2ResolverSpec"
        Missing = "resolver_id"
    },
    [pscustomobject]@{
        Name = "TestManifestEntry"
        Schema = "test_manifest_entry.schema.json"
        Object = (New-TestManifestEntry)
        Validator = "Test-P2TestManifestEntry"
        Missing = "test_id"
    }
)
$typeNameSchemaCount = 0

foreach ($contract in $contracts) {
    Assert-Passes -Label "valid synthetic $($contract.Name)" -Action {
        & $contract.Validator $contract.Object
    }
    $schema = Read-BattleStrictJsonFile `
        (Join-Path $schemaRoot $contract.Schema) "$($contract.Name) schema"
    Assert-Condition (
        [string]$schema.PSObject.Properties['$schema'].Value -ceq
        "https://json-schema.org/draft/2020-12/schema"
    ) "$($contract.Name) schema does not declare draft 2020-12."
    Assert-Condition ($schema.additionalProperties -eq $false) `
        "$($contract.Name) schema must close its root object."
    $schemaRequired = @($schema.required | ForEach-Object { [string]$_ } | Sort-Object)
    $objectProperties = @($contract.Object.PSObject.Properties.Name | Sort-Object)
    Assert-Condition (
        ($schemaRequired -join "`n") -ceq ($objectProperties -join "`n")
    ) "$($contract.Name) schema and semantic validator roots diverge."
    Test-StrictSchemaNode $schema $schema $contract.Name
    $definitions = $schema.PSObject.Properties['$defs'].Value
    $typeNameDefinition = $definitions.PSObject.Properties['type_name']
    if ($null -ne $typeNameDefinition) {
        $typeNameSchemaCount += 1
        $typeNamePattern = [string]$typeNameDefinition.Value.pattern
        Assert-Condition ("SyntheticBattleType" -cmatch $typeNamePattern) `
            "$($contract.Name) type_name rejects a valid type."
        foreach ($forbiddenType in @(
            "Node", "Dictionary", "Resource", "Callable",
            "node", "dictionary", "resource", "callable"
        )) {
            Assert-Condition ($forbiddenType -cnotmatch $typeNamePattern) `
                "$($contract.Name) type_name pattern admits $forbiddenType."
        }
    }

    $candidate = Copy-JsonValue $contract.Object
    $candidate.PSObject.Properties.Remove([string]$contract.Missing)
    Assert-Throws -Label "$($contract.Name) missing root property" `
        -MessagePattern "P2_JSON_PROPERTIES" -Action {
            & $contract.Validator $candidate
        }
    $candidate = Copy-JsonValue $contract.Object
    $candidate | Add-Member -NotePropertyName unknown_field -NotePropertyValue 1
    Assert-Throws -Label "$($contract.Name) unknown root property" `
        -MessagePattern "P2_JSON_PROPERTIES" -Action {
            & $contract.Validator $candidate
        }
    $candidate = Copy-JsonValue $contract.Object
    $candidate | Add-Member -NotePropertyName computed_status `
        -NotePropertyValue "DISCOVERED"
    Assert-Throws -Label "$($contract.Name) authored computed_status" `
        -MessagePattern "P2_SPEC_COMPUTED_STATUS_FORBIDDEN" -Action {
            & $contract.Validator $candidate
        }
}
Assert-Condition ($typeNameSchemaCount -eq 4) `
    "The five P2B schemas expose an unexpected type_name definition set."

$candidate = New-MechanismSpec
$candidate.ruleset_ids = [object[]]@(1)
Assert-Throws -Label "ALL ruleset rejects explicit IDs" `
    -MessagePattern "P2_MECHANISM_RULESET_ALL" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.ruleset_mode = "EXPLICIT"
Assert-Throws -Label "EXPLICIT ruleset requires IDs" `
    -MessagePattern "P2_MECHANISM_RULESET_EXPLICIT" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.phase_id = 0
Assert-Throws -Label "resolver entry requires phase" `
    -MessagePattern "P2_MECHANISM_RESOLVER_ENTRY" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$secondBranch = Copy-JsonValue $candidate.coverage_targets[0]
$candidate.coverage_targets[0].branch_id = 2
$secondBranch.branch_id = 1
$candidate.coverage_targets = [object[]]@($candidate.coverage_targets[0], $secondBranch)
Assert-Throws -Label "mechanism branch order" `
    -MessagePattern "P2_MECHANISM_BRANCH_ORDER" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.ordering_key = [object[]]@(
    [pscustomobject][ordered]@{
        field_key = "INSTANCE_ID"; direction = "DESC"; source = "INSTANCE"
    },
    [pscustomobject][ordered]@{
        field_key = "INSTANCE_ID"; direction = "ASC"; source = "STABLE_ID"
    }
)
Assert-Throws -Label "mechanism ordering field uniqueness" `
    -MessagePattern "P2_MECHANISM_ORDER_FIELD_DUPLICATE" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.parameter_slots[0].minimum = 101
Assert-Throws -Label "mechanism parameter range" `
    -MessagePattern "P2_MECHANISM_PARAMETER_RANGE" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.formula_stages[0].parameter_slot_ids = [object[]]@(2)
Assert-Throws -Label "mechanism local formula parameter" `
    -MessagePattern "P2_MECHANISM_STAGE_PARAMETER_UNKNOWN" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.formula_stages[0].output_slot_id = 1
Assert-Throws -Label "mechanism formula output slot reuse" `
    -MessagePattern "P2_MECHANISM_STAGE_OUTPUT_DUPLICATE" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.formula_stages[0].result_minimum = 201
Assert-Throws -Label "mechanism formula result range" `
    -MessagePattern "P2_MECHANISM_STAGE_RESULT_RANGE" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.rng_draws[0].mechanism_id = 2
Assert-Throws -Label "mechanism RNG parent" `
    -MessagePattern "P2_MECHANISM_DRAW_PARENT" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.rng_draws[0].trace_fields = [object[]]@(
    "CURSOR_BEFORE", "DRAW_ID", "EXTRA", "MECHANISM_ID", "STREAM_ID", "TAG_ID"
)
Assert-Throws -Label "mechanism RNG trace fields" `
    -MessagePattern "P2_MECHANISM_DRAW_TRACE" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.resolver_ids = [object[]]@()
Assert-Throws -Label "mechanism local resolver reference" `
    -MessagePattern "P2_MECHANISM_ENTRY_RESOLVER_MISSING" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.execution_steps[1].step_order = 1
Assert-Throws -Label "mechanism unified execution order" `
    -MessagePattern "P2_MECHANISM_EXECUTION_ORDER" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.rng_draws[0].draw_order = 2
Assert-Throws -Label "mechanism RNG unified execution position" `
    -MessagePattern "P2_MECHANISM_EXECUTION_DRAW_ORDER" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.formula_stages[0].operand_units = [object[]]@("HP")
Assert-Throws -Label "mechanism formula operand unit mismatch" `
    -MessagePattern "P2_MECHANISM_STAGE_OPERAND_UNIT" -Action {
        Test-P2MechanismSpec $candidate
    }
$candidate = New-MechanismSpec
$candidate.reentry_policy.policy = "ALLOW_NESTED"
$candidate.reentry_policy.maximum_depth = 1
$candidate.reentry_policy.same_instance_recall = $true
Assert-Throws -Label "mechanism reentry policy contradiction" `
    -MessagePattern "P2_MECHANISM_REENTRY_NESTED" -Action {
        Test-P2MechanismSpec $candidate
    }
foreach ($booleanCase in @(
    @{ Label = "bounds"; Minimum = 0; Maximum = 3; Order = "NOT_APPLICABLE"; CountMin = 1; CountMax = 1 },
    @{ Label = "order"; Minimum = 0; Maximum = 2; Order = "SPEC_ORDER"; CountMin = 1; CountMax = 1 },
    @{ Label = "count"; Minimum = 0; Maximum = 2; Order = "NOT_APPLICABLE"; CountMin = 0; CountMax = 1 }
)) {
    $candidate = New-MechanismSpec
    $candidate.rng_draws[0].sample_kind = "BOOLEAN"
    $candidate.rng_draws[0].minimum_inclusive = $booleanCase.Minimum
    $candidate.rng_draws[0].maximum_exclusive = $booleanCase.Maximum
    $candidate.rng_draws[0].candidate_order = $booleanCase.Order
    $candidate.rng_draws[0].draw_count_minimum = $booleanCase.CountMin
    $candidate.rng_draws[0].draw_count_maximum = $booleanCase.CountMax
    Assert-Throws -Label "BOOLEAN draw rejects $($booleanCase.Label)" `
        -MessagePattern "P2_MECHANISM_DRAW_BOOLEAN" -Action {
            Test-P2MechanismSpec $candidate
        }
}

$candidate = New-MechanismSpec
$drawOne = $candidate.rng_draws[0]
$drawTwo = Copy-JsonValue $drawOne
$drawOne.draw_order = 4
$drawTwo.draw_id = 2
$drawTwo.draw_order = 3
$candidate.rng_draws = [object[]]@($drawOne, $drawTwo)
$formulaStep = $candidate.execution_steps[0]
$eventStep = $candidate.execution_steps[1]
$rngTwoStep = Copy-JsonValue $candidate.execution_steps[2]
$rngTwoStep.reference_id = 2
$rngTwoStep.step_order = 3
$rngOneStep = Copy-JsonValue $candidate.execution_steps[2]
$rngOneStep.reference_id = 1
$rngOneStep.step_order = 4
$mutationStep = $candidate.execution_steps[3]
$mutationStep.step_order = 5
$commandStep = $candidate.execution_steps[4]
$commandStep.step_order = 6
$candidate.command_contracts[0].emission_order = 6
$candidate.execution_steps = [object[]]@(
    $formulaStep, $eventStep, $rngTwoStep, $rngOneStep,
    $mutationStep, $commandStep
)
Assert-Passes -Label "RNG execution order is independent from draw ID" -Action {
    Test-P2MechanismSpec $candidate
}

$candidate = New-MechanismSpec
$stageOne = $candidate.formula_stages[0]
$stageTwo = Copy-JsonValue $stageOne
$stageTwo.stage_id = 2
$stageTwo.debug_key = "ADD_SECOND"
$stageTwo.output_slot_id = 3
$candidate.formula_stages = [object[]]@($stageOne, $stageTwo)
$stageTwoStep = Copy-JsonValue $candidate.execution_steps[0]
$stageTwoStep.reference_id = 2
$stageTwoStep.step_order = 1
$stageOneStep = Copy-JsonValue $candidate.execution_steps[0]
$stageOneStep.reference_id = 1
$stageOneStep.step_order = 2
$eventStep = $candidate.execution_steps[1]
$eventStep.step_order = 3
$rngStep = $candidate.execution_steps[2]
$rngStep.step_order = 4
$candidate.rng_draws[0].draw_order = 4
$mutationStep = $candidate.execution_steps[3]
$mutationStep.step_order = 5
$commandStep = $candidate.execution_steps[4]
$commandStep.step_order = 6
$candidate.command_contracts[0].emission_order = 6
$candidate.execution_steps = [object[]]@(
    $stageTwoStep, $stageOneStep, $eventStep, $rngStep,
    $mutationStep, $commandStep
)
Assert-Passes -Label "formula execution order is independent from stage ID" -Action {
    Test-P2MechanismSpec $candidate
}

$candidate = New-MechanismSpec
$candidate.event_ids = [object[]]@(1, 2)
$formulaStep = $candidate.execution_steps[0]
$eventStepOne = $candidate.execution_steps[1]
$eventStepTwo = Copy-JsonValue $eventStepOne
$eventStepTwo.step_order = 3
$eventStepTwo.condition_kind = "ON_RETRY"
$rngStep = $candidate.execution_steps[2]
$rngStep.step_order = 4
$candidate.rng_draws[0].draw_order = 4
$mutationStep = $candidate.execution_steps[3]
$mutationStep.step_order = 5
$commandStep = $candidate.execution_steps[4]
$commandStep.step_order = 6
$candidate.command_contracts[0].emission_order = 6
$candidate.execution_steps = [object[]]@(
    $formulaStep, $eventStepOne, $eventStepTwo, $rngStep,
    $mutationStep, $commandStep
)
Assert-Passes -Label "event allowlist permits repeats and unused IDs" -Action {
    Test-P2MechanismSpec $candidate
}

$candidate = New-MechanismSpec
$candidate.event_ids = [object[]]@(1, 2)
$candidate.formula_stages[0].operation = "FOLD_MODIFIERS"
$candidate.formula_stages[0].modifier_event_id = 2
$candidate.formula_stages[0].modifier_aggregation = "ADD"
Assert-Passes -Label "modifier event needs no extra emission step" -Action {
    Test-P2MechanismSpec $candidate
}

$candidate = New-EventSchema
$candidate.sort_key[0].direction = "DESC"
Assert-Throws -Label "event stable tie break" `
    -MessagePattern "P2_EVENT_SORT_TIE_BREAK" -Action {
        Test-P2EventSchema $candidate
    }
$candidate = New-EventSchema
$candidate.sort_key = [object[]]@(
    [pscustomobject][ordered]@{
        field_key = "INSTANCE_ID"; direction = "DESC"; source = "OWNER"
    },
    [pscustomobject][ordered]@{
        field_key = "INSTANCE_ID"; direction = "ASC"; source = "STABLE_ID"
    }
)
Assert-Throws -Label "event sort field uniqueness" `
    -MessagePattern "P2_EVENT_SORT_FIELD_DUPLICATE" -Action {
        Test-P2EventSchema $candidate
    }
$candidate = New-EventSchema
$candidate.rounding_stage_refs = [object[]]@(
    [pscustomobject][ordered]@{ mechanism_id = 1; stage_id = 1 }
)
Assert-Throws -Label "event NONE rounding consistency" `
    -MessagePattern "P2_EVENT_ROUNDING_NONE" -Action {
        Test-P2EventSchema $candidate
    }
$candidate = New-EventSchema
$candidate.rounding_mode = "FLOOR"
$candidate.rounding_schedule = "AT_STAGE_END"
Assert-Throws -Label "event active rounding requires stages" `
    -MessagePattern "P2_EVENT_ROUNDING_REQUIRED" -Action {
        Test-P2EventSchema $candidate
    }
$candidate = New-EventSchema
$candidate.rounding_stage_refs = [object[]]@(
    [pscustomobject][ordered]@{ mechanism_id = 1; stage_id = 1 }
)
$candidate.rounding_mode = "FLOOR"
$candidate.rounding_schedule = "AT_STAGE_END"
Assert-Passes -Label "event scoped rounding stage" -Action {
    Test-P2EventSchema $candidate
}
$candidate = New-EventSchema
$candidate.rounding_stage_refs = [object[]]@(
    [pscustomobject][ordered]@{ mechanism_id = 1; stage_id = 2 },
    [pscustomobject][ordered]@{ mechanism_id = 1; stage_id = 1 }
)
$candidate.rounding_mode = "FLOOR"
$candidate.rounding_schedule = "AT_STAGE_END"
Assert-Throws -Label "event scoped rounding order" `
    -MessagePattern "P2_EVENT_ROUNDING_STAGE_ORDER" -Action {
        Test-P2EventSchema $candidate
    }
$candidate = New-EventSchema
$candidate.trace_policy.record_context_hash = $true
Assert-Throws -Label "event OFF trace policy" `
    -MessagePattern "P2_EVENT_TRACE_OFF" -Action {
        Test-P2EventSchema $candidate
    }
$candidate = New-EventSchema
$candidate.same_instance_recall_policy = "ALLOW_BOUNDED"
$candidate.maximum_same_instance_recalls = 1
Assert-Throws -Label "event bounded recall limit" `
    -MessagePattern "P2_EVENT_RECALL_BOUND" -Action {
        Test-P2EventSchema $candidate
    }
$candidate = New-EventSchema
$candidate.aggregation_policy = "FIRST_DENY"
$candidate.short_circuit_rule = "NONE"
Assert-Throws -Label "event aggregation and short circuit contradiction" `
    -MessagePattern "P2_EVENT_AGGREGATION_SHORT_CIRCUIT" -Action {
        Test-P2EventSchema $candidate
    }
$candidate = New-EventSchema
$candidate.context_type = "SyntheticNodeContext"
Assert-Throws -Label "semantic type name rejects runtime classes" `
    -MessagePattern "P2_SPEC_RUNTIME_TYPE_FORBIDDEN" -Action {
        Test-P2EventSchema $candidate
    }
$candidate = New-EventSchema
$candidate.context_type = "node"
Assert-Throws -Label "semantic type name requires PascalCase" `
    -MessagePattern "P2_JSON_STRING_FORMAT" -Action {
        Test-P2EventSchema $candidate
    }
$candidate = New-EventSchema
$candidate.debug_key = "NODE"
Assert-Passes -Label "runtime token is allowed as a non-type debug key" -Action {
    Test-P2EventSchema $candidate
}

$candidate = New-HandlerBinding
$candidate.implementation_key = "res://battle/handler.gd"
Assert-Throws -Label "handler implementation path" `
    -MessagePattern "P2_SPEC_PATH_FORBIDDEN" -Action {
        Test-P2HandlerBinding $candidate
    }
$candidate = New-HandlerBinding
$candidate.implementation_key = "node"
Assert-Passes -Label "runtime token is allowed as an implementation key" -Action {
    Test-P2HandlerBinding $candidate
}
$candidate = New-HandlerBinding
$candidate.allowed_rng_draw_ids = [object[]]@(
    [pscustomobject][ordered]@{ mechanism_id = 2; draw_id = 1 },
    [pscustomobject][ordered]@{ mechanism_id = 1; draw_id = 2 }
)
$candidate.mechanism_ids = [object[]]@(1, 2)
Assert-Throws -Label "handler composite RNG order" `
    -MessagePattern "P2_HANDLER_RNG_ORDER" -Action {
        Test-P2HandlerBinding $candidate
    }
$candidate = New-HandlerBinding
$candidate.allowed_rng_draw_ids[0].mechanism_id = 2
Assert-Throws -Label "handler RNG mechanism must be declared" `
    -MessagePattern "P2_HANDLER_RNG_MECHANISM_UNKNOWN" -Action {
        Test-P2HandlerBinding $candidate
    }
$stableKey159 = "A" * 159
$stableKey160 = "B" * 160
Assert-Condition ($stableKey159.Length -eq 159 -and $stableKey160.Length -eq 160) `
    "Stable-key length fixtures are incorrect."
$candidate = New-HandlerBinding
$candidate.allowed_queries = [object[]]@($stableKey159, $stableKey160)
Assert-Passes -Label "159 and 160 character stable-key array items" -Action {
    Test-P2HandlerBinding $candidate
}

$candidate = New-ResolverSpec
$phaseTwo = Copy-JsonValue $candidate.phases[0]
$phaseTwo.phase_id = 2
$phaseTwo.debug_key = "SECOND"
$candidate.phases = [object[]]@($phaseTwo, $candidate.phases[0])
Assert-Throws -Label "resolver phase order" `
    -MessagePattern "P2_RESOLVER_PHASE_ORDER" -Action {
        Test-P2ResolverSpec $candidate
    }
$candidate = New-ResolverSpec
$candidate.phases[0].reentry_policy = "ALLOW_ONCE"
Assert-Throws -Label "resolver reentry bound" `
    -MessagePattern "P2_RESOLVER_REENTRY_ONCE" -Action {
        Test-P2ResolverSpec $candidate
    }
$candidate = New-ResolverSpec
$candidate.phases[0].mechanism_ids = [object[]]@(2)
Assert-Throws -Label "resolver phase mechanism must be declared" `
    -MessagePattern "P2_RESOLVER_PHASE_MECHANISM_UNKNOWN" -Action {
        Test-P2ResolverSpec $candidate
    }
$candidate = New-ResolverSpec
$candidate.legal_event_emissions[0].phase_id = 2
Assert-Throws -Label "resolver emission local phase" `
    -MessagePattern "P2_RESOLVER_EMISSION_PHASE" -Action {
        Test-P2ResolverSpec $candidate
    }
$candidate = New-ResolverSpec
$candidate.interruption_points[0].resume_phase_id = 2
Assert-Throws -Label "resolver interruption local phase" `
    -MessagePattern "P2_RESOLVER_INTERRUPTION_PHASE" -Action {
        Test-P2ResolverSpec $candidate
    }
$candidate = New-ResolverSpec
$candidate.legal_event_emissions[0].nested_policy = "ALLOW_BOUNDED"
$candidate.legal_event_emissions[0].maximum_nested_depth = 1
Assert-Throws -Label "resolver bounded nested emission limit" `
    -MessagePattern "P2_RESOLVER_NESTED_BOUND" -Action {
        Test-P2ResolverSpec $candidate
    }
$candidate = New-ResolverSpec
$phaseOne = $candidate.phases[0]
$phaseOne.phase_order = 2
$phaseTwo = Copy-JsonValue $phaseOne
$phaseTwo.phase_id = 2
$phaseTwo.phase_order = 1
$phaseTwo.debug_key = "PREPARE"
$candidate.phases = [object[]]@($phaseOne, $phaseTwo)
Assert-Passes -Label "resolver phase order is independent from phase ID" -Action {
    Test-P2ResolverSpec $candidate
}

$candidate = New-TestManifestEntry
$candidate.fixture_id = 2
Assert-Throws -Label "scenario fixture identity" `
    -MessagePattern "P2_TEST_SCENARIO_FIXTURE" -Action {
        Test-P2TestManifestEntry $candidate
    }
$candidate = New-TestManifestEntry
$candidate.test_kind = "FORMULA_UNIT"
$candidate.fixture_id = 0
$candidate.required_oracle_kinds = [object[]]@("FORMULA")
Assert-Passes -Label "non-scenario zero fixture" -Action {
    Test-P2TestManifestEntry $candidate
}
$candidate.fixture_id = 1
Assert-Throws -Label "non-scenario nonzero fixture" `
    -MessagePattern "P2_TEST_UNIT_FIXTURE" -Action {
        Test-P2TestManifestEntry $candidate
    }
$candidate = New-TestManifestEntry
$candidate.test_kind = "REPLAY"
$candidate.fixture_id = 0
$candidate.required_oracle_kinds = [object[]]@("REPLAY")
Assert-Passes -Label "replay zero fixture" -Action {
    Test-P2TestManifestEntry $candidate
}
$candidate.fixture_id = 2
Assert-Throws -Label "replay rejects nonzero fixture" `
    -MessagePattern "P2_TEST_UNIT_FIXTURE" -Action {
        Test-P2TestManifestEntry $candidate
    }
$candidate = New-TestManifestEntry
$candidate.test_kind = "PERFORMANCE"
$candidate.fixture_id = 0
$candidate.required_oracle_kinds = [object[]]@("PERFORMANCE")
Assert-Passes -Label "performance zero fixture" -Action {
    Test-P2TestManifestEntry $candidate
}
$candidate.fixture_id = 2
Assert-Throws -Label "performance rejects nonzero fixture" `
    -MessagePattern "P2_TEST_UNIT_FIXTURE" -Action {
        Test-P2TestManifestEntry $candidate
    }
$candidate = New-TestManifestEntry
$candidate.required_oracle_kinds = [object[]]@("FORMULA")
Assert-Throws -Label "test kind requires matching oracle" `
    -MessagePattern "P2_TEST_REQUIRED_ORACLE" -Action {
        Test-P2TestManifestEntry $candidate
    }

$maturityLevels = @("DISCOVERED", "SPECIFIED", "IMPLEMENTED", "VERIFIED", "RELEASED")
foreach ($level in $maturityLevels) {
    $facts = New-MaturityFacts $level
    $result = Get-P2MaturityComputation 1 $level $facts
    Assert-Condition ([string]$result.computed_status -ceq $level) `
        "$level maturity did not compute exactly."
    Assert-Condition ([bool]$result.meets_target) `
        "$level maturity did not meet its same-level target."
    Assert-Passes -Label "$level target acceptance" -Action {
        Assert-P2MaturityTarget $result
    }
}

$skipCases = @(
    @{ Missing = "cross_references_valid"; Expected = "DISCOVERED" },
    @{ Missing = "dependency_gate_passed"; Expected = "SPECIFIED" },
    @{ Missing = "coverage_observed"; Expected = "IMPLEMENTED" },
    @{ Missing = "release_migration_complete"; Expected = "VERIFIED" }
)
foreach ($case in $skipCases) {
    $facts = New-MaturityFacts "RELEASED"
    $facts.($case.Missing) = $false
    $result = Get-P2MaturityComputation 1 "RELEASED" $facts
    Assert-Condition ([string]$result.computed_status -ceq $case.Expected) `
        "Maturity skipped prerequisite $($case.Missing)."
}
$facts = New-MaturityFacts "RELEASED"
$facts.identity_registered = $false
Assert-Throws -Label "maturity discovery hard gate" `
    -MessagePattern "P2_MATURITY_DISCOVERY_GATE" -Action {
        Get-P2MaturityComputation 1 "DISCOVERED" $facts
    }
$facts = New-MaturityFacts "DISCOVERED"
$firstReasons = @((Get-P2MaturityComputation 1 "DISCOVERED" $facts).blocking_reason_codes)
$secondReasons = @((Get-P2MaturityComputation 1 "DISCOVERED" (Copy-JsonValue $facts)).blocking_reason_codes)
Assert-Condition (($firstReasons -join "|") -ceq ($secondReasons -join "|")) `
    "Maturity blocker order is not deterministic."
$expectedDiscoveryBlockers = @(
    "SPECIFICATION_INVALID",
    "CROSS_REFERENCES_INVALID",
    "IMPLEMENTATION_BINDINGS_UNVERIFIED",
    "DEPENDENCY_GATE_FAILED",
    "REQUIRED_TESTS_MISSING",
    "REQUIRED_ORACLES_MISSING",
    "COVERAGE_NOT_OBSERVED",
    "EVIDENCE_STALE",
    "RELEASE_CATALOG_UNVERSIONED",
    "RELEASE_MIGRATION_INCOMPLETE",
    "RELEASE_CHANGE_LOG_INCOMPLETE",
    "RELEASE_COVERAGE_GATE_FAILED"
)
Assert-Condition (
    ($firstReasons -join "|") -ceq ($expectedDiscoveryBlockers -join "|")
) "Maturity blockers do not follow the declared gate order."
$tampered = Get-P2MaturityComputation 1 "DISCOVERED" $facts
$tampered.blocking_reason_codes = [object[]]@(
    $tampered.blocking_reason_codes[1], $tampered.blocking_reason_codes[0]
)
Assert-Throws -Label "maturity blocker order validator" `
    -MessagePattern "P2_MATURITY_BLOCKER_ORDER" -Action {
        Assert-P2MaturityTarget $tampered
    }
$targetFailure = Get-P2MaturityComputation 1 "SPECIFIED" $facts
Assert-Throws -Label "maturity target hard failure" `
    -MessagePattern "P2_MATURITY_TARGET_UNMET" -Action {
        Assert-P2MaturityTarget $targetFailure
    }
$forgedMaturity = Copy-JsonValue $targetFailure
$forgedMaturity.meets_target = $true
Assert-Throws -Label "forged maturity meets_target" `
    -MessagePattern "P2_MATURITY_RESULT_INCONSISTENT" -Action {
        Assert-P2MaturityTarget $forgedMaturity
    }

$stableManifest = Read-BattleStrictJsonFile $stablePath "tracked stable IDs"
$presentationManifest = Read-BattleStrictJsonFile `
    $presentationPath "tracked presentation contracts"
$syntheticStable = New-SyntheticStableRegistry $stableManifest
$specPaths = [ordered]@{
    mechanism = "new-game-project/battle/specs/mechanisms/0000000001.mechanism_spec.json"
    event = "new-game-project/battle/specs/events/0000000001.event_schema.json"
    handler = "new-game-project/battle/specs/handlers/0000000001.handler_binding.json"
    resolver = "new-game-project/battle/specs/resolvers/0000000001.resolver_spec.json"
    test = "new-game-project/battle/specs/tests/0000000001.test_manifest_entry.json"
}
$stableRelative = "new-game-project/battle/specs/id_manifests/battle_stable_ids.json"
$presentationRelative = "new-game-project/battle/specs/presentation/presentation_contracts.json"
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$tempRoot = Join-Path $tempParent (
    "maizang-p2-spec-contract-test-" + [Guid]::NewGuid().ToString("N")
)
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $null = Invoke-TestGit $tempRoot @("init", "--quiet")
    $null = Invoke-TestGit $tempRoot @("config", "user.name", "Battle Contract Test")
    $null = Invoke-TestGit $tempRoot @(
        "config", "user.email", "battle-test@example.invalid"
    )
    Write-ContainedJson $tempRoot $stableRelative $syntheticStable
    Write-ContainedJson $tempRoot $presentationRelative $presentationManifest
    $null = Invoke-TestGit $tempRoot @("add", "--all", "--")
    $null = Invoke-TestGit $tempRoot @("commit", "--quiet", "-m", "P2 registries")

    $emptyInput = [pscustomobject][ordered]@{
        schema_version = 1
        mechanism_specs = [object[]]@()
        event_schemas = [object[]]@()
        handler_bindings = [object[]]@()
        resolver_specs = [object[]]@()
        test_entries = [object[]]@()
    }
    $emptyHash = Get-BattleSha256Text (ConvertTo-BattleCanonicalJson $emptyInput)
    $before = Get-NonGitSnapshot $tempRoot
    $output = @(& $validatorPath -ProjectRoot $tempRoot -Mode Repository)
    Assert-Marker $output (
        "P2_SPEC_CONTRACTS_OK mechanism_specs=0 event_schemas=0 " +
        "handler_bindings=0 resolver_specs=0 test_entries=0 " +
        "input_set_sha256=$emptyHash"
    ) "empty repository"
    $output = @(& $validatorPath -ProjectRoot $tempRoot -Mode Staged)
    Assert-Marker $output "input_set_sha256=$emptyHash" "empty staged set"
    Assert-Condition ((Get-NonGitSnapshot $tempRoot) -ceq $before) `
        "Validator wrote files while checking an empty repository."

    Write-ContainedJson $tempRoot $specPaths.mechanism (New-MechanismSpec)
    Write-ContainedJson $tempRoot $specPaths.event (New-EventSchema)
    Write-ContainedJson $tempRoot $specPaths.handler (New-HandlerBinding)
    Write-ContainedJson $tempRoot $specPaths.resolver (New-ResolverSpec)
    Write-ContainedJson $tempRoot $specPaths.test (New-TestManifestEntry)
    $null = Invoke-TestGit $tempRoot @("add", "--all", "--")
    $null = Invoke-TestGit $tempRoot @("commit", "--quiet", "-m", "P2 specs")

    $before = Get-NonGitSnapshot $tempRoot
    foreach ($mode in @("Repository", "Worktree", "Staged")) {
        $output = @(& $validatorPath -ProjectRoot $tempRoot -Mode $mode)
        Assert-Marker $output (
            "P2_SPEC_CONTRACTS_OK mechanism_specs=1 event_schemas=1 " +
            "handler_bindings=1 resolver_specs=1 test_entries=1 " +
            "input_set_sha256=[0-9a-f]{64}"
        ) "non-empty $mode"
    }
    Assert-Condition ((Get-NonGitSnapshot $tempRoot) -ceq $before) `
        "Validator wrote files while checking a non-empty repository."

    $untrackedReviewSurface = (
        "new-game-project/battle/tools/battle_specs/validators/" +
        "p2_spec_contract_support.ps1"
    )
    Write-ContainedBytes $tempRoot $untrackedReviewSurface `
        ($utf8NoBom.GetBytes("Set-StrictMode -Version Latest`n"))
    Assert-Throws -Label "untracked staged review support" `
        -MessagePattern "P2_STAGED_REVIEW_SURFACE_UNTRACKED" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Staged
        }
    Remove-ContainedFile $tempRoot $untrackedReviewSurface

    $junctionTarget = [IO.Path]::GetFullPath((Join-Path $tempRoot (
        "new-game-project\battle\reparse-target"
    )))
    $junctionPath = [IO.Path]::GetFullPath((Join-Path $tempRoot (
        "new-game-project\battle\specs\events\reparse-probe"
    )))
    $null = [IO.Directory]::CreateDirectory($junctionTarget)
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $junctionPath))
    try {
        $junction = New-Item -ItemType Junction -Path $junctionPath `
            -Target $junctionTarget
        Assert-Condition (
            ($junction.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        ) "The Windows junction fixture is not a reparse point."
        Assert-Throws -Label "worktree reparse directory" `
            -MessagePattern "P2_SPEC_REPARSE_PATH" -Action {
                & $validatorPath -ProjectRoot $tempRoot -Mode Worktree
            }
    }
    finally {
        if (Test-Path -LiteralPath $junctionPath) {
            [IO.Directory]::Delete($junctionPath)
        }
    }

    $dirtyEvent = New-EventSchema
    $dirtyEvent | Add-Member -NotePropertyName computed_status `
        -NotePropertyValue "DISCOVERED"
    Write-ContainedJson $tempRoot $specPaths.event $dirtyEvent
    Assert-Passes -Label "staged validator ignores dirty worktree" -Action {
        & $validatorPath -ProjectRoot $tempRoot -Mode Staged
    }
    Assert-Throws -Label "worktree validator reads dirty spec" `
        -MessagePattern "P2_SPEC_COMPUTED_STATUS_FORBIDDEN" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Worktree
        }
    Write-ContainedJson $tempRoot $specPaths.event (New-EventSchema)

    $nonPadded = "new-game-project/battle/specs/mechanisms/1.mechanism_spec.json"
    Write-ContainedJson $tempRoot $nonPadded (New-MechanismSpec)
    Assert-Throws -Label "non-ten-digit authoring filename" `
        -MessagePattern "P2_SPEC_FILENAME" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Worktree
        }
    Remove-ContainedFile $tempRoot $nonPadded

    $wrongFileId = "new-game-project/battle/specs/events/0000000002.event_schema.json"
    Write-ContainedJson $tempRoot $wrongFileId (New-EventSchema)
    Assert-Throws -Label "filename and primary ID mismatch" `
        -MessagePattern "P2_SPEC_FILENAME_ID" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Worktree
        }
    Remove-ContainedFile $tempRoot $wrongFileId

    $unknownEvent = New-EventSchema
    $unknownEvent.event_id = 2
    $unknownEvent.debug_key = "EVENT_UNKNOWN"
    Write-ContainedJson $tempRoot $wrongFileId $unknownEvent
    Assert-Throws -Label "unregistered root primary ID" `
        -MessagePattern "P2_SPEC_PRIMARY_UNKNOWN" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Worktree
        }
    Remove-ContainedFile $tempRoot $wrongFileId

    $inactiveRegistry = Copy-JsonValue $syntheticStable
    (Get-StableDomain $inactiveRegistry "EVENT").entries[0].status = "TOMBSTONE"
    Write-ContainedJson $tempRoot $stableRelative $inactiveRegistry
    Assert-Throws -Label "inactive primary ID" `
        -MessagePattern "P2_SPEC_PRIMARY_INACTIVE" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Worktree
        }
    Write-ContainedJson $tempRoot $stableRelative $syntheticStable

    $wrongDebug = New-EventSchema
    $wrongDebug.debug_key = "EVENT_WRONG"
    Write-ContainedJson $tempRoot $specPaths.event $wrongDebug
    Assert-Throws -Label "primary debug key mismatch" `
        -MessagePattern "P2_SPEC_PRIMARY_DEBUG_KEY" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Worktree
        }
    Write-ContainedJson $tempRoot $specPaths.event (New-EventSchema)

    $targetSpec = New-MechanismSpec
    $targetSpec.target_maturity = "SPECIFIED"
    Write-ContainedJson $tempRoot $specPaths.mechanism $targetSpec
    Write-ContainedBytes $tempRoot `
        "new-game-project/battle/scripts/rules/synthetic_handler.gd" `
        ($utf8NoBom.GetBytes("extends RefCounted`n"))
    Assert-Throws -Label "source and handler files do not promote maturity" `
        -MessagePattern "P2_MATURITY_TARGET_UNMET" -Action {
            & $validatorPath -ProjectRoot $tempRoot -Mode Worktree
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

Write-Host "P2_SPEC_CONTRACT_TEST_OK checks=$checks"
