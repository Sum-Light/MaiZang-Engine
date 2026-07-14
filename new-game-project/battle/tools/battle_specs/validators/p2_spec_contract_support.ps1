Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "p2_id_manifest_support.ps1")

$script:P2MaturityOrder = @(
    "DISCOVERED",
    "SPECIFIED",
    "IMPLEMENTED",
    "VERIFIED",
    "RELEASED"
)
$script:P2MaturityFactsProperties = @(
    "identity_registered",
    "discovery_basis_verified",
    "specification_valid",
    "cross_references_valid",
    "implementation_bindings_verified",
    "dependency_gate_passed",
    "required_test_count",
    "executed_test_count",
    "passed_test_count",
    "required_oracles",
    "passed_oracles",
    "coverage_observed",
    "evidence_current",
    "release_catalog_versioned",
    "release_migration_complete",
    "release_change_log_complete",
    "release_coverage_gate_passed"
)
$script:P2MaturityBlockingReasonOrder = @(
    "SPECIFICATION_INVALID",
    "CROSS_REFERENCES_INVALID",
    "IMPLEMENTATION_BINDINGS_UNVERIFIED",
    "DEPENDENCY_GATE_FAILED",
    "REQUIRED_TESTS_MISSING",
    "REQUIRED_TESTS_NOT_EXECUTED",
    "REQUIRED_TESTS_NOT_PASSED",
    "REQUIRED_ORACLES_MISSING",
    "REQUIRED_ORACLES_NOT_PASSED",
    "COVERAGE_NOT_OBSERVED",
    "EVIDENCE_STALE",
    "RELEASE_CATALOG_UNVERSIONED",
    "RELEASE_MIGRATION_INCOMPLETE",
    "RELEASE_CHANGE_LOG_INCOMPLETE",
    "RELEASE_COVERAGE_GATE_FAILED"
)

function Assert-P2SpecSafeValue {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($null -eq $Value) {
        throw "P2_SPEC_NULL_FORBIDDEN: $Context cannot be null."
    }
    if ($Value -is [string]) {
        $text = [string]$Value
        if ($text -match '(?i)(?:[A-Z]:[\\/]|\\\\|res://|user://)') {
            throw "P2_SPEC_PATH_FORBIDDEN: $Context cannot contain a path."
        }
        if ($text -match '(?:=>|&&|\|\||\$\(|[{};])') {
            throw "P2_SPEC_EXPRESSION_FORBIDDEN: $Context cannot contain executable syntax."
        }
        return
    }
    if ($Value -is [PSCustomObject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -ceq "computed_status") {
                throw (
                    "P2_SPEC_COMPUTED_STATUS_FORBIDDEN: $Context cannot author " +
                    "computed_status."
                )
            }
            Assert-P2SpecSafeValue -Value $property.Value `
                -Context "$Context.$($property.Name)"
        }
        return
    }
    if ($Value -is [Array]) {
        $items = @($Value)
        for ($index = 0; $index -lt $items.Count; $index++) {
            Assert-P2SpecSafeValue -Value $items[$index] `
                -Context "$Context[$index]"
        }
        return
    }
    if ($Value -is [bool] -or (Test-P2IntegralType $Value)) {
        return
    }
    throw (
        "P2_SPEC_VALUE_TYPE: $Context has unsupported type " +
        "'$($Value.GetType().FullName)'."
    )
}

function Get-P2SpecKey {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [int]$MaximumLength = 160
    )

    return Get-P2String -Value $Value -Context $Context `
        -Pattern '^[A-Z][A-Z0-9_]*(\.[A-Z][A-Z0-9_]*)*$' `
        -MaximumLength $MaximumLength
}

function Get-P2SpecTypeName {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $typeName = Get-P2String -Value $Value -Context $Context `
        -Pattern '^[A-Z][A-Za-z0-9_]*$' -MaximumLength 128
    if ($typeName -cmatch '(?:Dictionary|Variant|Node|Resource|Callable)') {
        throw "P2_SPEC_RUNTIME_TYPE_FORBIDDEN: $Context has forbidden type '$typeName'."
    }
    return $typeName
}

function Get-P2SpecIdArray {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [int]$MinimumCount = 0,
        [int]$MaximumCount = 256
    )

    Assert-P2Array -Value $Value -Context $Context `
        -Minimum $MinimumCount -Maximum $MaximumCount
    $items = @($Value)
    $previous = 0L
    for ($index = 0; $index -lt $items.Count; $index++) {
        $identifier = Get-P2Integer $items[$index] "$Context[$index]" `
            1 $script:P2MaxId
        Assert-P2Condition ($identifier -gt $previous) "P2_SPEC_ID_ORDER" `
            "$Context must contain unique, strictly increasing IDs."
        $previous = $identifier
    }
    return $true
}

function Get-P2SpecOrderedIdArray {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [int]$MinimumCount = 0,
        [int]$MaximumCount = 256
    )

    Assert-P2Array -Value $Value -Context $Context `
        -Minimum $MinimumCount -Maximum $MaximumCount
    $seen = [Collections.Generic.HashSet[long]]::new()
    foreach ($item in @($Value)) {
        $identifier = Get-P2Integer $item "$Context item" 1 $script:P2MaxId
        Assert-P2Condition ($seen.Add($identifier)) "P2_SPEC_ID_DUPLICATE" `
            "$Context must contain unique IDs."
    }
    return $true
}

function Get-P2SpecKeyArray {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [int]$MinimumCount = 0,
        [int]$MaximumCount = 256
    )

    Assert-P2Array -Value $Value -Context $Context `
        -Minimum $MinimumCount -Maximum $MaximumCount
    $items = @($Value)
    $previous = ""
    for ($index = 0; $index -lt $items.Count; $index++) {
        $key = Get-P2SpecKey -Value $items[$index] -Context "$Context[$index]"
        if ($index -gt 0) {
            Assert-P2Condition (
                [StringComparer]::Ordinal.Compare($key, $previous) -gt 0
            ) "P2_SPEC_KEY_ORDER" `
                "$Context must contain unique, ordinally increasing keys."
        }
        $previous = $key
    }
    return $true
}

function Get-P2MaturityOracleArray {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $null = Get-P2SpecKeyArray -Value $Value -Context $Context `
        -MaximumCount 256
    return @($Value)
}

function Get-P2MaturityComputation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$MechanismId,
        [Parameter(Mandatory = $true)][object]$TargetMaturity,
        [Parameter(Mandatory = $true)][object]$Facts
    )

    $mechanismIdValue = Get-P2Integer -Value $MechanismId `
        -Context "maturity mechanism_id" -Minimum 1 -Maximum $script:P2MaxId
    $target = Get-P2Enum -Value $TargetMaturity `
        -Context "maturity target_maturity" -Allowed $script:P2MaturityOrder
    Assert-P2Object -Value $Facts -Context "maturity facts"
    $factObject = [PSCustomObject]$Facts
    Assert-P2ExactProperties -Value $factObject -Context "maturity facts" `
        -Expected $script:P2MaturityFactsProperties

    $identityRegistered = Get-P2Boolean $factObject.identity_registered `
        "maturity facts.identity_registered"
    $discoveryBasisVerified = Get-P2Boolean `
        $factObject.discovery_basis_verified `
        "maturity facts.discovery_basis_verified"
    if (-not $identityRegistered -or -not $discoveryBasisVerified) {
        $failed = @()
        if (-not $identityRegistered) {
            $failed += "IDENTITY_NOT_REGISTERED"
        }
        if (-not $discoveryBasisVerified) {
            $failed += "DISCOVERY_BASIS_UNVERIFIED"
        }
        throw (
            "P2_MATURITY_DISCOVERY_GATE: Mechanism $mechanismIdValue cannot " +
            "reach DISCOVERED: $($failed -join ', ')."
        )
    }

    $specificationValid = Get-P2Boolean $factObject.specification_valid `
        "maturity facts.specification_valid"
    $crossReferencesValid = Get-P2Boolean $factObject.cross_references_valid `
        "maturity facts.cross_references_valid"
    $bindingsVerified = Get-P2Boolean `
        $factObject.implementation_bindings_verified `
        "maturity facts.implementation_bindings_verified"
    $dependencyGatePassed = Get-P2Boolean $factObject.dependency_gate_passed `
        "maturity facts.dependency_gate_passed"
    $requiredTestCount = Get-P2Integer $factObject.required_test_count `
        "maturity facts.required_test_count" 0 $script:P2MaxId
    $executedTestCount = Get-P2Integer $factObject.executed_test_count `
        "maturity facts.executed_test_count" 0 $script:P2MaxId
    $passedTestCount = Get-P2Integer $factObject.passed_test_count `
        "maturity facts.passed_test_count" 0 $script:P2MaxId
    Assert-P2Condition ($passedTestCount -le $executedTestCount) `
        "P2_MATURITY_TEST_COUNTS" `
        "passed_test_count cannot exceed executed_test_count."
    $requiredOracles = @(Get-P2MaturityOracleArray `
        $factObject.required_oracles "maturity facts.required_oracles")
    $passedOracles = @(Get-P2MaturityOracleArray `
        $factObject.passed_oracles "maturity facts.passed_oracles")
    $coverageObserved = Get-P2Boolean $factObject.coverage_observed `
        "maturity facts.coverage_observed"
    $evidenceCurrent = Get-P2Boolean $factObject.evidence_current `
        "maturity facts.evidence_current"
    $catalogVersioned = Get-P2Boolean `
        $factObject.release_catalog_versioned `
        "maturity facts.release_catalog_versioned"
    $migrationComplete = Get-P2Boolean `
        $factObject.release_migration_complete `
        "maturity facts.release_migration_complete"
    $changeLogComplete = Get-P2Boolean `
        $factObject.release_change_log_complete `
        "maturity facts.release_change_log_complete"
    $releaseCoveragePassed = Get-P2Boolean `
        $factObject.release_coverage_gate_passed `
        "maturity facts.release_coverage_gate_passed"

    $passedOracleSet = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($oracle in $passedOracles) {
        $null = $passedOracleSet.Add([string]$oracle)
    }
    $allRequiredOraclesPassed = $requiredOracles.Count -gt 0
    foreach ($oracle in $requiredOracles) {
        if (-not $passedOracleSet.Contains([string]$oracle)) {
            $allRequiredOraclesPassed = $false
        }
    }

    $blockingReasons = [Collections.Generic.List[string]]::new()
    if (-not $specificationValid) {
        $blockingReasons.Add("SPECIFICATION_INVALID")
    }
    if (-not $crossReferencesValid) {
        $blockingReasons.Add("CROSS_REFERENCES_INVALID")
    }
    if (-not $bindingsVerified) {
        $blockingReasons.Add("IMPLEMENTATION_BINDINGS_UNVERIFIED")
    }
    if (-not $dependencyGatePassed) {
        $blockingReasons.Add("DEPENDENCY_GATE_FAILED")
    }
    if ($requiredTestCount -eq 0) {
        $blockingReasons.Add("REQUIRED_TESTS_MISSING")
    }
    elseif ($executedTestCount -lt $requiredTestCount) {
        $blockingReasons.Add("REQUIRED_TESTS_NOT_EXECUTED")
    }
    if ($requiredTestCount -gt 0 -and $passedTestCount -lt $requiredTestCount) {
        $blockingReasons.Add("REQUIRED_TESTS_NOT_PASSED")
    }
    if ($requiredOracles.Count -eq 0) {
        $blockingReasons.Add("REQUIRED_ORACLES_MISSING")
    }
    elseif (-not $allRequiredOraclesPassed) {
        $blockingReasons.Add("REQUIRED_ORACLES_NOT_PASSED")
    }
    if (-not $coverageObserved) {
        $blockingReasons.Add("COVERAGE_NOT_OBSERVED")
    }
    if (-not $evidenceCurrent) {
        $blockingReasons.Add("EVIDENCE_STALE")
    }
    if (-not $catalogVersioned) {
        $blockingReasons.Add("RELEASE_CATALOG_UNVERSIONED")
    }
    if (-not $migrationComplete) {
        $blockingReasons.Add("RELEASE_MIGRATION_INCOMPLETE")
    }
    if (-not $changeLogComplete) {
        $blockingReasons.Add("RELEASE_CHANGE_LOG_INCOMPLETE")
    }
    if (-not $releaseCoveragePassed) {
        $blockingReasons.Add("RELEASE_COVERAGE_GATE_FAILED")
    }

    $computed = "DISCOVERED"
    $specified = $specificationValid -and $crossReferencesValid
    if ($specified) {
        $computed = "SPECIFIED"
    }
    $implemented = $specified -and $bindingsVerified -and $dependencyGatePassed
    if ($implemented) {
        $computed = "IMPLEMENTED"
    }
    $verified = (
        $implemented -and
        $requiredTestCount -gt 0 -and
        $executedTestCount -ge $requiredTestCount -and
        $passedTestCount -ge $requiredTestCount -and
        $allRequiredOraclesPassed -and
        $coverageObserved -and
        $evidenceCurrent
    )
    if ($verified) {
        $computed = "VERIFIED"
    }
    $released = (
        $verified -and $catalogVersioned -and $migrationComplete -and
        $changeLogComplete -and $releaseCoveragePassed
    )
    if ($released) {
        $computed = "RELEASED"
    }

    $maturityRanks = @{}
    for ($index = 0; $index -lt $script:P2MaturityOrder.Count; $index++) {
        $maturityRanks[$script:P2MaturityOrder[$index]] = $index
    }
    $meetsTarget = [int]$maturityRanks[$computed] -ge [int]$maturityRanks[$target]
    return [pscustomobject][ordered]@{
        mechanism_id = $mechanismIdValue
        target_maturity = $target
        computed_status = $computed
        meets_target = $meetsTarget
        blocking_reason_codes = $blockingReasons.ToArray()
    }
}

function Assert-P2MaturityTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias("Result")]
        [object]$Computation
    )

    Assert-P2Object -Value $Computation -Context "maturity computation"
    $result = [PSCustomObject]$Computation
    Assert-P2ExactProperties -Value $result -Context "maturity computation" `
        -Expected @(
            "mechanism_id", "target_maturity", "computed_status",
            "meets_target", "blocking_reason_codes"
        )
    $mechanismId = Get-P2Integer $result.mechanism_id `
        "maturity computation.mechanism_id" 1 $script:P2MaxId
    $target = Get-P2Enum $result.target_maturity `
        "maturity computation.target_maturity" $script:P2MaturityOrder
    $computed = Get-P2Enum $result.computed_status `
        "maturity computation.computed_status" $script:P2MaturityOrder
    $meetsTarget = Get-P2Boolean $result.meets_target `
        "maturity computation.meets_target"
    $computedRank = [Array]::IndexOf($script:P2MaturityOrder, $computed)
    $targetRank = [Array]::IndexOf($script:P2MaturityOrder, $target)
    Assert-P2Condition ($meetsTarget -eq ($computedRank -ge $targetRank)) `
        "P2_MATURITY_RESULT_INCONSISTENT" `
        "meets_target does not match computed_status and target_maturity."
    Assert-P2Array $result.blocking_reason_codes `
        "maturity computation.blocking_reason_codes" 0 32
    $previousReasonRank = -1
    foreach ($reasonValue in @($result.blocking_reason_codes)) {
        $reason = Get-P2Enum $reasonValue `
            "maturity computation.blocking_reason_codes item" `
            $script:P2MaturityBlockingReasonOrder
        $reasonRank = [Array]::IndexOf(
            $script:P2MaturityBlockingReasonOrder,
            $reason
        )
        Assert-P2Condition ($reasonRank -gt $previousReasonRank) `
            "P2_MATURITY_BLOCKER_ORDER" `
            "Maturity blockers must be unique and follow gate order."
        $previousReasonRank = $reasonRank
    }
    Assert-P2Condition (
        $computed -cne "RELEASED" -or
        @($result.blocking_reason_codes).Count -eq 0
    ) "P2_MATURITY_RELEASE_BLOCKERS" `
        "RELEASED maturity cannot retain blocking reasons."
    Assert-P2Condition (
        $computed -ceq "RELEASED" -or
        @($result.blocking_reason_codes).Count -gt 0
    ) "P2_MATURITY_MISSING_BLOCKERS" `
        "A maturity below RELEASED must identify at least one blocker."
    if (-not $meetsTarget) {
        throw (
            "P2_MATURITY_TARGET_UNMET: Mechanism $mechanismId computed " +
            "$computed below target $target; blockers: " +
            "$(@($result.blocking_reason_codes) -join ', ')."
        )
    }
    return $true
}

function Assert-P2SpecUniqueObjects {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [int]$MinimumCount = 0,
        [int]$MaximumCount = 256
    )

    Assert-P2Array -Value $Value -Context $Context `
        -Minimum $MinimumCount -Maximum $MaximumCount
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $items = @($Value)
    for ($index = 0; $index -lt $items.Count; $index++) {
        Assert-P2Object -Value $items[$index] -Context "$Context[$index]"
        $canonical = ConvertTo-BattleCanonicalJsonValue $items[$index]
        Assert-P2Condition ($seen.Add($canonical)) "P2_SPEC_OBJECT_DUPLICATE" `
            "$Context contains a duplicate object at index $index."
    }
}

function Test-P2SpecIdArrayContains {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][long]$Identifier
    )

    foreach ($item in @($Value)) {
        if ([long]$item -eq $Identifier) {
            return $true
        }
    }
    return $false
}

function Test-P2SpecKeyArrayContains {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Key
    )

    foreach ($item in @($Value)) {
        if ([string]$item -ceq $Key) {
            return $true
        }
    }
    return $false
}

function Assert-P2SpecValueContract {
    param(
        [Parameter(Mandatory = $true)][string]$ValueKind,
        [Parameter(Mandatory = $true)][string]$StableDomain,
        [Parameter(Mandatory = $true)][long]$Minimum,
        [Parameter(Mandatory = $true)][long]$Maximum,
        [Parameter(Mandatory = $true)][string]$Context,
        [string[]]$IntegerKinds = @("SIGNED_INT", "PUBLIC_INT"),
        [string[]]$BooleanKinds = @("BOOL", "PUBLIC_BOOL")
    )

    Assert-P2Condition ($Minimum -le $Maximum) "P2_SPEC_VALUE_RANGE" `
        "$Context minimum cannot exceed maximum."
    if ($ValueKind -ceq "STABLE_ID") {
        Assert-P2Condition (
            $StableDomain -cin @("ENTITY", "EFFECT", "ITEM", "MOVE", "MESSAGE") -and
            $Minimum -eq 1 -and $Maximum -eq $script:P2MaxId
        ) "P2_SPEC_STABLE_ID_VALUE" `
            "$Context STABLE_ID requires a concrete domain and full stable-ID range."
        return
    }
    if ($ValueKind -cin $IntegerKinds) {
        Assert-P2Condition ($StableDomain -ceq "NONE") `
            "P2_SPEC_INTEGER_VALUE" "$Context integer value must use domain NONE."
        return
    }
    if ($ValueKind -cin $BooleanKinds) {
        Assert-P2Condition (
            $StableDomain -ceq "NONE" -and $Minimum -eq 0 -and $Maximum -eq 1
        ) "P2_SPEC_BOOLEAN_VALUE" `
            "$Context boolean value must use domain NONE and range 0..1."
    }
}

function Get-P2SpecOracleArray {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [int]$MinimumCount = 1
    )

    $allowed = @(
        "FORMULA", "RESOLVER_PHASE", "EVENT_HANDLER", "RNG",
        "STATE_MUTATION", "COMMAND_PRESENTATION", "AUDIENCE",
        "GAMEPLAY_INTERRUPTION", "SETTLEMENT_DECISION", "SCENARIO",
        "REPLAY", "PERFORMANCE"
    )
    Assert-P2Array -Value $Value -Context $Context `
        -Minimum $MinimumCount -Maximum 12
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in @($Value)) {
        $oracle = Get-P2Enum $item "$Context item" $allowed
        Assert-P2Condition ($seen.Add($oracle)) "P2_SPEC_ORACLE_DUPLICATE" `
            "$Context contains duplicate oracle '$oracle'."
    }
    return $true
}

function Get-P2RequiredOracleForTestKind {
    param([Parameter(Mandatory = $true)][string]$TestKind)

    if ($TestKind -ceq "FORMULA_UNIT") {
        return "FORMULA"
    }
    return $TestKind
}

function Test-P2MechanismSpec {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Spec)

    Assert-P2SpecSafeValue -Value $Spec -Context "MechanismSpec"
    Assert-P2Object -Value $Spec -Context "MechanismSpec"
    $root = [PSCustomObject]$Spec
    Assert-P2ExactProperties -Value $root -Context "MechanismSpec" -Expected @(
        "artifact_kind", "mechanism_id", "debug_key", "spec_schema_version",
        "behavior_version", "ruleset_mode", "ruleset_ids", "feature_pack_ids",
        "owner_module", "target_maturity", "project_requirement_keys",
        "evidence_ids", "entry_kind", "resolver_id", "phase_id", "subphase_id",
        "preconditions", "inputs", "read_set", "write_set", "history_reads",
        "history_writes", "counter_reads", "counter_writes", "ordering_key",
        "short_circuit", "reentry_policy", "coverage_targets", "parameter_slots",
        "formula_stages", "rng_draws", "execution_steps", "resolver_ids",
        "event_ids", "handler_ids",
        "state_op_ids", "command_ids", "presentation_cue_ids", "result_type",
        "mutation_contracts", "command_contracts", "error_contracts",
        "atomicity_policy", "test_requirements"
    )
    $null = Get-P2Enum $root.artifact_kind "MechanismSpec.artifact_kind" @(
        "MECHANISM_SPEC"
    )
    $mechanismId = Get-P2Integer $root.mechanism_id "MechanismSpec.mechanism_id" `
        1 $script:P2MaxId
    $null = Get-P2String $root.debug_key "MechanismSpec.debug_key" `
        '^[A-Z][A-Z0-9_]*$' 128
    $null = Get-P2Integer $root.spec_schema_version `
        "MechanismSpec.spec_schema_version" 1 $script:P2MaxId
    $null = Get-P2Integer $root.behavior_version `
        "MechanismSpec.behavior_version" 1 $script:P2MaxId
    $rulesetMode = Get-P2Enum $root.ruleset_mode `
        "MechanismSpec.ruleset_mode" @("ALL", "EXPLICIT")
    $null = Get-P2SpecIdArray $root.ruleset_ids "MechanismSpec.ruleset_ids" `
        -MaximumCount 4096
    if ($rulesetMode -ceq "ALL") {
        Assert-P2Condition (@($root.ruleset_ids).Count -eq 0) `
            "P2_MECHANISM_RULESET_ALL" "ruleset_mode ALL requires no ruleset IDs."
    }
    else {
        Assert-P2Condition (@($root.ruleset_ids).Count -gt 0) `
            "P2_MECHANISM_RULESET_EXPLICIT" `
            "ruleset_mode EXPLICIT requires at least one ruleset ID."
    }
    $null = Get-P2SpecIdArray $root.feature_pack_ids `
        "MechanismSpec.feature_pack_ids" -MaximumCount 4096
    $null = Get-P2SpecKey $root.owner_module "MechanismSpec.owner_module" 160
    $targetMaturity = Get-P2Enum $root.target_maturity `
        "MechanismSpec.target_maturity" $script:P2MaturityOrder
    Assert-P2Array $root.project_requirement_keys `
        "MechanismSpec.project_requirement_keys" 0 64
    $requirementNames = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($item in @($root.project_requirement_keys)) {
        $key = Get-P2String $item "MechanismSpec project requirement" `
            '^[A-Z0-9][A-Z0-9_.-]*$' 128
        Assert-P2Condition ($requirementNames.Add($key)) `
            "P2_MECHANISM_REQUIREMENT_DUPLICATE" `
            "MechanismSpec repeats project requirement '$key'."
    }
    $null = Get-P2SpecIdArray $root.evidence_ids `
        "MechanismSpec.evidence_ids" -MaximumCount 4096
    Assert-P2Condition (
        @($root.project_requirement_keys).Count -gt 0 -or
        @($root.evidence_ids).Count -gt 0
    ) "P2_MECHANISM_DISCOVERY_BASIS" `
        "MechanismSpec requires project_requirement_keys or evidence_ids."
    $entryKind = Get-P2Enum $root.entry_kind "MechanismSpec.entry_kind" @(
        "RESOLVER", "EVENT_HANDLER", "LIFECYCLE", "DOMAIN_SERVICE", "OUTCOME"
    )
    $resolverId = Get-P2Integer $root.resolver_id "MechanismSpec.resolver_id" `
        0 $script:P2MaxId
    $phaseId = Get-P2Integer $root.phase_id "MechanismSpec.phase_id" `
        0 $script:P2MaxId
    $subphaseId = Get-P2Integer $root.subphase_id "MechanismSpec.subphase_id" `
        0 $script:P2MaxId
    if ($entryKind -ceq "RESOLVER") {
        Assert-P2Condition ($resolverId -gt 0 -and $phaseId -gt 0) `
            "P2_MECHANISM_RESOLVER_ENTRY" `
            "A RESOLVER entry requires positive resolver_id and phase_id."
    }
    if ($subphaseId -gt 0) {
        Assert-P2Condition ($phaseId -gt 0) "P2_MECHANISM_SUBPHASE" `
            "A positive subphase_id requires a positive phase_id."
    }

    Assert-P2SpecUniqueObjects $root.preconditions `
        "MechanismSpec.preconditions" 0 64
    foreach ($itemValue in @($root.preconditions)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "kind", "subject", "value_kind", "stable_domain", "stable_id",
            "minimum", "maximum"
        ) "MechanismSpec precondition"
        $null = Get-P2SpecKey $item.kind "precondition.kind" 160
        $null = Get-P2Enum $item.subject "precondition.subject" @(
            "ACTOR", "TARGET", "SOURCE", "OWNER", "SIDE", "POSITION",
            "BATTLE", "NONE"
        )
        $valueKind = Get-P2Enum $item.value_kind "precondition.value_kind" @(
            "NONE", "STABLE_ID", "PUBLIC_INT", "PUBLIC_BOOL"
        )
        $domain = Get-P2Enum $item.stable_domain "precondition.stable_domain" @(
            "ENTITY", "EFFECT", "ITEM", "MOVE", "MESSAGE", "NONE"
        )
        $stableId = Get-P2Integer $item.stable_id "precondition.stable_id" `
            0 $script:P2MaxId
        $minimum = Get-P2Integer $item.minimum "precondition.minimum" `
            ([long]-2147483648) $script:P2MaxId
        $maximum = Get-P2Integer $item.maximum "precondition.maximum" `
            ([long]-2147483648) $script:P2MaxId
        if ($valueKind -ceq "NONE") {
            Assert-P2Condition (
                $domain -ceq "NONE" -and $stableId -eq 0 -and
                $minimum -eq 0 -and $maximum -eq 0
            ) "P2_MECHANISM_PRECONDITION_NONE" `
                "A NONE precondition value must use zero/empty scalar fields."
        }
        else {
            Assert-P2SpecValueContract $valueKind $domain $minimum $maximum `
                "precondition"
            if ($valueKind -ceq "STABLE_ID") {
                Assert-P2Condition ($stableId -gt 0) `
                    "P2_MECHANISM_PRECONDITION_ID" `
                    "A STABLE_ID precondition requires stable_id."
            }
            else {
                Assert-P2Condition ($stableId -eq 0) `
                    "P2_MECHANISM_PRECONDITION_NON_ID" `
                    "A non-ID precondition must use stable_id 0."
            }
        }
    }

    Assert-P2SpecUniqueObjects $root.inputs "MechanismSpec.inputs" 0 64
    $inputNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $valueSlotIds = [Collections.Generic.HashSet[long]]::new()
    $inputSlotUnits = @{}
    $previousInputSlotId = 0L
    foreach ($itemValue in @($root.inputs)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "slot_id", "field_name", "value_kind", "stable_domain", "minimum",
            "maximum", "unit", "ownership", "required", "cardinality",
            "max_items"
        ) "MechanismSpec input"
        $slotId = Get-P2Integer $item.slot_id "input.slot_id" 1 $script:P2MaxId
        Assert-P2Condition ($slotId -gt $previousInputSlotId) `
            "P2_MECHANISM_INPUT_SLOT_ORDER" `
            "Input slot IDs must be strictly increasing."
        $previousInputSlotId = $slotId
        $null = $valueSlotIds.Add($slotId)
        $fieldName = Get-P2String $item.field_name "input.field_name" `
            '^[a-z][a-z0-9_]*$' 64
        Assert-P2Condition ($inputNames.Add($fieldName)) `
            "P2_MECHANISM_INPUT_DUPLICATE" "Duplicate input '$fieldName'."
        $valueKind = Get-P2Enum $item.value_kind "input.value_kind" @(
            "STABLE_ID", "SIGNED_INT", "BOOL"
        )
        $domain = Get-P2Enum $item.stable_domain "input.stable_domain" @(
            "ENTITY", "EFFECT", "ITEM", "MOVE", "MESSAGE", "NONE"
        )
        $minimum = Get-P2Integer $item.minimum "input.minimum" `
            ([long]-2147483648) $script:P2MaxId
        $maximum = Get-P2Integer $item.maximum "input.maximum" `
            ([long]-2147483648) $script:P2MaxId
        Assert-P2SpecValueContract $valueKind $domain $minimum $maximum "input"
        $inputUnit = Get-P2Enum $item.unit "input.unit" @(
            "NONE", "COUNT", "HP", "TURN", "TICK", "PERCENT_BASIS_POINTS",
            "RATIO_NUMERATOR", "RATIO_DENOMINATOR"
        )
        $inputSlotUnits[$slotId] = $inputUnit
        $null = Get-P2Enum $item.ownership "input.ownership" @(
            "INPUT_DTO", "BATTLE_STATE", "CATALOG", "RULE_PROFILE",
            "SYNTHETIC_FIXTURE"
        )
        $null = Get-P2Boolean $item.required "input.required"
        $cardinality = Get-P2Enum $item.cardinality "input.cardinality" @(
            "ONE", "MANY"
        )
        $maxItems = Get-P2Integer $item.max_items "input.max_items" 1 256
        if ($cardinality -ceq "ONE") {
            Assert-P2Condition ($maxItems -eq 1) "P2_MECHANISM_INPUT_CARDINALITY" `
                "A ONE input requires max_items 1."
        }
    }

    foreach ($property in @(
        "read_set", "write_set", "history_reads", "history_writes",
        "counter_reads", "counter_writes"
    )) {
        $null = Get-P2SpecKeyArray $root.$property "MechanismSpec.$property" `
            -MaximumCount 256
    }
    Assert-P2SpecUniqueObjects $root.ordering_key `
        "MechanismSpec.ordering_key" 1 16
    $mechanismOrderFields = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($itemValue in @($root.ordering_key)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @("field_key", "direction", "source") `
            "MechanismSpec order term"
        $orderFieldKey = Get-P2SpecKey $item.field_key "order field_key" 160
        Assert-P2Condition ($mechanismOrderFields.Add($orderFieldKey)) `
            "P2_MECHANISM_ORDER_FIELD_DUPLICATE" `
            "MechanismSpec ordering_key repeats $orderFieldKey."
        $null = Get-P2Enum $item.direction "order direction" @("ASC", "DESC")
        $null = Get-P2Enum $item.source "order source" @(
            "INPUT", "STATE", "CATALOG", "INSTANCE", "STABLE_ID"
        )
    }
    Assert-P2Object $root.short_circuit "MechanismSpec.short_circuit"
    $shortCircuit = [PSCustomObject]$root.short_circuit
    Assert-P2ExactProperties $shortCircuit @("policy", "result_key") `
        "MechanismSpec.short_circuit"
    $null = Get-P2Enum $shortCircuit.policy "short_circuit.policy" @(
        "NONE", "FIRST_ACCEPT", "FIRST_DENY", "STOP_ON_ERROR", "STOP_ON_TERMINAL"
    )
    $null = Get-P2SpecKey $shortCircuit.result_key "short_circuit.result_key" 160
    Assert-P2Object $root.reentry_policy "MechanismSpec.reentry_policy"
    $reentry = [PSCustomObject]$root.reentry_policy
    Assert-P2ExactProperties $reentry @(
        "policy", "maximum_depth", "same_instance_recall"
    ) "MechanismSpec.reentry_policy"
    $reentryKind = Get-P2Enum $reentry.policy "reentry.policy" @(
        "DENY", "ALLOW_NESTED", "ALLOW_RECALL", "ALLOW_SAME_INSTANCE_ONCE"
    )
    $maximumDepth = Get-P2Integer $reentry.maximum_depth `
        "reentry.maximum_depth" 0 64
    $sameRecall = Get-P2Boolean $reentry.same_instance_recall `
        "reentry.same_instance_recall"
    if ($reentryKind -ceq "DENY") {
        Assert-P2Condition ($maximumDepth -eq 0 -and -not $sameRecall) `
            "P2_MECHANISM_REENTRY_DENY" `
            "DENY reentry requires depth 0 and same_instance_recall false."
    }
    elseif ($reentryKind -ceq "ALLOW_NESTED") {
        Assert-P2Condition ($maximumDepth -gt 0 -and -not $sameRecall) `
            "P2_MECHANISM_REENTRY_NESTED" `
            "ALLOW_NESTED requires positive depth and no same-instance recall."
    }
    elseif ($reentryKind -ceq "ALLOW_RECALL") {
        Assert-P2Condition ($maximumDepth -gt 0 -and $sameRecall) `
            "P2_MECHANISM_REENTRY_RECALL" `
            "ALLOW_RECALL requires positive depth and same-instance recall."
    }
    else {
        Assert-P2Condition ($maximumDepth -eq 1 -and $sameRecall) `
            "P2_MECHANISM_REENTRY_ONCE" `
            "ALLOW_SAME_INSTANCE_ONCE requires depth 1 and recall enabled."
    }

    Assert-P2SpecUniqueObjects $root.coverage_targets `
        "MechanismSpec.coverage_targets" 1 256
    $previousBranchId = 0L
    foreach ($itemValue in @($root.coverage_targets)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "branch_id", "kind", "condition_kind", "required_oracle_kinds",
            "required_for_active_ruleset"
        ) "MechanismSpec coverage target"
        $branchId = Get-P2Integer $item.branch_id "coverage branch_id" `
            1 $script:P2MaxId
        Assert-P2Condition ($branchId -gt $previousBranchId) `
            "P2_MECHANISM_BRANCH_ORDER" `
            "coverage branch IDs must be strictly increasing."
        $previousBranchId = $branchId
        $null = Get-P2Enum $item.kind "coverage kind" @(
            "NORMAL", "BOUNDARY", "INTERACTION", "REJECTION", "ERROR", "REPLAY"
        )
        $null = Get-P2SpecKey $item.condition_kind "coverage condition_kind" 160
        $null = Get-P2SpecOracleArray $item.required_oracle_kinds `
            "coverage required_oracle_kinds"
        $null = Get-P2Boolean $item.required_for_active_ruleset `
            "coverage required_for_active_ruleset"
    }

    Assert-P2SpecUniqueObjects $root.parameter_slots `
        "MechanismSpec.parameter_slots" 0 128
    $parameterIds = [Collections.Generic.HashSet[long]]::new()
    $previousSlotId = 0L
    foreach ($itemValue in @($root.parameter_slots)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "slot_id", "debug_key", "value_kind", "stable_domain", "minimum",
            "maximum", "unit", "source_kind", "required"
        ) "MechanismSpec parameter slot"
        $slotId = Get-P2Integer $item.slot_id "parameter slot_id" 1 $script:P2MaxId
        Assert-P2Condition ($slotId -gt $previousSlotId) `
            "P2_MECHANISM_PARAMETER_ORDER" `
            "parameter slot IDs must be strictly increasing."
        $previousSlotId = $slotId
        $null = $parameterIds.Add($slotId)
        $null = Get-P2String $item.debug_key "parameter debug_key" `
            '^[A-Z][A-Z0-9_]*$' 128
        $valueKind = Get-P2Enum $item.value_kind "parameter value_kind" @(
            "SIGNED_INT", "STABLE_ID", "RATIO"
        )
        $domain = Get-P2Enum $item.stable_domain "parameter stable_domain" @(
            "ENTITY", "EFFECT", "ITEM", "MOVE", "MESSAGE", "NONE"
        )
        $minimum = Get-P2Integer $item.minimum "parameter minimum" `
            ([long]-2147483648) $script:P2MaxId
        $maximum = Get-P2Integer $item.maximum "parameter maximum" `
            ([long]-2147483648) $script:P2MaxId
        Assert-P2Condition ($minimum -le $maximum) "P2_MECHANISM_PARAMETER_RANGE" `
            "parameter minimum cannot exceed maximum."
        if ($valueKind -ceq "STABLE_ID") {
            Assert-P2SpecValueContract $valueKind $domain $minimum $maximum `
                "parameter slot"
        }
        else {
            Assert-P2Condition ($domain -ceq "NONE") `
                "P2_MECHANISM_PARAMETER_DOMAIN" `
                "Non-ID parameter slots must use stable_domain NONE."
        }
        $null = Get-P2Enum $item.unit "parameter unit" @(
            "NONE", "COUNT", "HP", "TURN", "TICK", "PERCENT_BASIS_POINTS",
            "RATIO_NUMERATOR", "RATIO_DENOMINATOR"
        )
        $null = Get-P2Enum $item.source_kind "parameter source_kind" @(
            "DEFINITION", "RULESET", "FEATURE_PACK", "SYNTHETIC_FIXTURE"
        )
        $null = Get-P2Boolean $item.required "parameter required"
    }

    Assert-P2SpecUniqueObjects $root.formula_stages `
        "MechanismSpec.formula_stages" 0 128
    $previousStageId = 0L
    $stageIds = [Collections.Generic.HashSet[long]]::new()
    $formulaStagesById = @{}
    foreach ($itemValue in @($root.formula_stages)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "stage_id", "debug_key", "operation", "operand_slot_ids",
            "operand_units", "parameter_slot_ids", "output_slot_id",
            "result_unit", "intermediate_width_bits", "negative_value_policy",
            "result_minimum", "result_maximum", "modifier_event_id",
            "modifier_aggregation", "rounding_mode", "rounding_schedule",
            "operation_order", "clamp_min_source", "clamp_max_source",
            "overflow_policy", "divide_by_zero_policy", "trace_field_keys"
        ) "MechanismSpec formula stage"
        $stageId = Get-P2Integer $item.stage_id "formula stage_id" 1 $script:P2MaxId
        Assert-P2Condition ($stageId -gt $previousStageId) `
            "P2_MECHANISM_STAGE_ORDER" "formula stage IDs must be increasing."
        $previousStageId = $stageId
        $null = $stageIds.Add($stageId)
        $null = Get-P2String $item.debug_key "formula debug_key" `
            '^[A-Z][A-Z0-9_]*$' 128
        $operation = Get-P2Enum $item.operation "formula operation" @(
            "ADD", "SUBTRACT", "MULTIPLY", "DIVIDE", "MULTIPLY_DIVIDE",
            "FOLD_MODIFIERS", "CLAMP", "SELECT"
        )
        $null = Get-P2SpecOrderedIdArray $item.operand_slot_ids `
            "formula operand_slot_ids" -MinimumCount 1 -MaximumCount 32
        Assert-P2Array $item.operand_units "formula operand_units" 1 32
        Assert-P2Condition (
            @($item.operand_units).Count -eq @($item.operand_slot_ids).Count
        ) "P2_MECHANISM_STAGE_OPERAND_UNITS" `
            "formula operand_units must align one-to-one with operand_slot_ids."
        $operandUnits = [Collections.Generic.List[string]]::new()
        foreach ($operandUnitValue in @($item.operand_units)) {
            $operandUnit = Get-P2Enum $operandUnitValue "formula operand unit" @(
                "NONE", "COUNT", "HP", "TURN", "TICK", "PERCENT_BASIS_POINTS",
                "RATIO_NUMERATOR", "RATIO_DENOMINATOR"
            )
            $operandUnits.Add($operandUnit)
        }
        $null = Get-P2SpecIdArray $item.parameter_slot_ids `
            "formula parameter_slot_ids" -MaximumCount 32
        foreach ($slotIdValue in @($item.parameter_slot_ids)) {
            Assert-P2Condition ($parameterIds.Contains([long]$slotIdValue)) `
                "P2_MECHANISM_STAGE_PARAMETER_UNKNOWN" `
                "formula stage references unknown local parameter slot $slotIdValue."
        }
        $outputSlotId = Get-P2Integer $item.output_slot_id `
            "formula output_slot_id" 1 $script:P2MaxId
        Assert-P2Condition ($valueSlotIds.Add($outputSlotId)) `
            "P2_MECHANISM_STAGE_OUTPUT_DUPLICATE" `
            "formula output_slot_id $outputSlotId is already defined."
        $resultUnit = Get-P2Enum $item.result_unit "formula result_unit" @(
            "NONE", "COUNT", "HP", "TURN", "TICK", "PERCENT_BASIS_POINTS",
            "RATIO_NUMERATOR", "RATIO_DENOMINATOR"
        )
        $width = Get-P2Integer $item.intermediate_width_bits `
            "formula intermediate_width_bits" 32 64
        Assert-P2Condition ($width -in @(32, 64)) `
            "P2_MECHANISM_STAGE_WIDTH" `
            "formula intermediate_width_bits must be 32 or 64."
        $null = Get-P2Enum $item.negative_value_policy `
            "formula negative_value_policy" @("ALLOW", "REJECT", "CLAMP_TO_ZERO")
        $resultMinimum = Get-P2Integer $item.result_minimum `
            "formula result_minimum" ([long]-2147483648) $script:P2MaxId
        $resultMaximum = Get-P2Integer $item.result_maximum `
            "formula result_maximum" ([long]-2147483648) $script:P2MaxId
        Assert-P2Condition ($resultMinimum -le $resultMaximum) `
            "P2_MECHANISM_STAGE_RESULT_RANGE" `
            "formula result_minimum cannot exceed result_maximum."
        $modifierEventId = Get-P2Integer $item.modifier_event_id `
            "formula modifier_event_id" 0 $script:P2MaxId
        $modifierAggregation = Get-P2Enum $item.modifier_aggregation `
            "formula modifier_aggregation" @("NONE", "ADD", "MULTIPLY", "FOLD_ORDERED")
        if ($operation -ceq "FOLD_MODIFIERS") {
            Assert-P2Condition (
                $modifierEventId -gt 0 -and $modifierAggregation -cne "NONE"
            ) "P2_MECHANISM_STAGE_MODIFIER_EVENT" `
                "FOLD_MODIFIERS requires a modifier event and aggregation policy."
        }
        else {
            Assert-P2Condition (
                $modifierEventId -eq 0 -and $modifierAggregation -ceq "NONE"
            ) "P2_MECHANISM_STAGE_MODIFIER_UNUSED" `
                "Only FOLD_MODIFIERS may declare modifier event aggregation."
        }
        $null = Get-P2Enum $item.rounding_mode "formula rounding_mode" @(
            "FLOOR", "CEIL", "TOWARD_ZERO", "AWAY_FROM_ZERO",
            "NEAREST_TIES_DOWN", "NEAREST_TIES_UP"
        )
        $null = Get-P2Enum $item.rounding_schedule `
            "formula rounding_schedule" @(
                "AFTER_EACH_MODIFIER", "AFTER_EACH_OPERATION", "AT_STAGE_END"
            )
        $null = Get-P2Enum $item.operation_order "formula operation_order" @(
            "LEFT_TO_RIGHT", "MULTIPLY_THEN_DIVIDE", "PAIRWISE"
        )
        $null = Get-P2SpecKey $item.clamp_min_source "formula clamp_min_source" 160
        $null = Get-P2SpecKey $item.clamp_max_source "formula clamp_max_source" 160
        $null = Get-P2Enum $item.overflow_policy "formula overflow_policy" @(
            "ERROR", "SATURATE", "CLAMP_BEFORE_OPERATION"
        )
        $null = Get-P2Enum $item.divide_by_zero_policy `
            "formula divide_by_zero_policy" @("ERROR", "REJECT_BRANCH")
        $null = Get-P2SpecKeyArray $item.trace_field_keys `
            "formula trace_field_keys" -MinimumCount 1 -MaximumCount 32
        $formulaStagesById[$stageId] = [pscustomobject]@{
            StageId = $stageId
            ModifierEventId = $modifierEventId
            OperandSlotIds = @($item.operand_slot_ids)
            OperandUnits = $operandUnits.ToArray()
            OutputSlotId = $outputSlotId
            ResultUnit = $resultUnit
        }
    }

    Assert-P2SpecUniqueObjects $root.rng_draws "MechanismSpec.rng_draws" 0 128
    $previousDrawId = 0L
    $rngDrawIds = [Collections.Generic.HashSet[long]]::new()
    $rngDrawOrders = @{}
    foreach ($itemValue in @($root.rng_draws)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "mechanism_id", "draw_id", "stream_id", "tag_id", "draw_order",
            "consume_condition", "sample_kind", "minimum_inclusive", "maximum_exclusive",
            "candidate_order", "draw_count_minimum", "draw_count_maximum",
            "failure_semantics", "trace_fields"
        ) "MechanismSpec RNG draw"
        $drawMechanismId = Get-P2Integer $item.mechanism_id `
            "RNG mechanism_id" 1 $script:P2MaxId
        Assert-P2Condition ($drawMechanismId -eq $mechanismId) `
            "P2_MECHANISM_DRAW_PARENT" `
            "RNG draw mechanism_id must equal the parent MechanismSpec ID."
        $drawId = Get-P2Integer $item.draw_id "RNG draw_id" 1 $script:P2MaxId
        Assert-P2Condition ($drawId -gt $previousDrawId) `
            "P2_MECHANISM_DRAW_ORDER" "RNG draw IDs must be strictly increasing."
        $previousDrawId = $drawId
        $null = $rngDrawIds.Add($drawId)
        $null = Get-P2Integer $item.stream_id "RNG stream_id" 1 $script:P2MaxId
        $null = Get-P2Integer $item.tag_id "RNG tag_id" 1 $script:P2MaxId
        $drawOrder = Get-P2Integer $item.draw_order "RNG draw_order" 1 4096
        $rngDrawOrders[$drawId] = $drawOrder
        $null = Get-P2SpecKey $item.consume_condition "RNG consume_condition" 160
        $sampleKind = Get-P2Enum $item.sample_kind "RNG sample_kind" @(
            "BOUNDED_INT", "ORDERED_CANDIDATE", "WEIGHTED_CANDIDATE", "BOOLEAN"
        )
        $minimum = Get-P2Integer $item.minimum_inclusive `
            "RNG minimum_inclusive" ([long]-2147483648) $script:P2MaxId
        $maximum = Get-P2Integer $item.maximum_exclusive `
            "RNG maximum_exclusive" ([long]-2147483648) $script:P2MaxId
        Assert-P2Condition ($minimum -lt $maximum) "P2_MECHANISM_DRAW_BOUNDS" `
            "RNG minimum_inclusive must be below maximum_exclusive."
        $candidateOrder = Get-P2Enum $item.candidate_order "RNG candidate_order" @(
            "CANONICAL_ID_ASC", "SPEC_ORDER", "SORT_KEY_ASC", "NOT_APPLICABLE"
        )
        $drawMinimum = Get-P2Integer $item.draw_count_minimum `
            "RNG draw_count_minimum" 0 64
        $drawMaximum = Get-P2Integer $item.draw_count_maximum `
            "RNG draw_count_maximum" 0 64
        Assert-P2Condition ($drawMinimum -le $drawMaximum) `
            "P2_MECHANISM_DRAW_COUNT" `
            "RNG draw_count_minimum cannot exceed draw_count_maximum."
        if ($sampleKind -ceq "BOOLEAN") {
            Assert-P2Condition (
                $minimum -eq 0 -and $maximum -eq 2 -and
                $candidateOrder -ceq "NOT_APPLICABLE" -and
                $drawMinimum -eq 1 -and $drawMaximum -eq 1
            ) "P2_MECHANISM_DRAW_BOOLEAN" `
                "BOOLEAN draws require bounds 0..2, no candidate order, and one draw."
        }
        elseif ($sampleKind -ceq "BOUNDED_INT") {
            Assert-P2Condition (
                $candidateOrder -ceq "NOT_APPLICABLE" -and
                $drawMinimum -eq 1 -and $drawMaximum -eq 1
            ) "P2_MECHANISM_DRAW_BOUNDED_INT" `
                "BOUNDED_INT draws require no candidate order and exactly one draw."
        }
        else {
            Assert-P2Condition (
                $minimum -eq 0 -and $candidateOrder -cne "NOT_APPLICABLE" -and
                $drawMinimum -eq 0 -and $drawMaximum -eq 1
            ) "P2_MECHANISM_DRAW_CANDIDATE" `
                "Candidate draws require zero-based bounds, ordering, and 0..1 draws."
        }
        $null = Get-P2Enum $item.failure_semantics "RNG failure_semantics" @(
            "NO_CONSUME_ERROR", "CONSUME_ERROR", "NO_CONSUME_EMPTY", "CONSUME_EMPTY"
        )
        $null = Get-P2SpecKeyArray $item.trace_fields "RNG trace_fields" `
            -MinimumCount 6 -MaximumCount 16
        foreach ($requiredTraceField in @(
            "MECHANISM_ID", "DRAW_ID", "STREAM_ID", "TAG_ID",
            "CURSOR_BEFORE", "CURSOR_AFTER"
        )) {
            Assert-P2Condition (
                Test-P2SpecKeyArrayContains $item.trace_fields $requiredTraceField
            ) "P2_MECHANISM_DRAW_TRACE" `
                "RNG trace_fields must include $requiredTraceField."
        }
    }

    foreach ($property in @(
        "resolver_ids", "event_ids", "handler_ids", "state_op_ids",
        "command_ids", "presentation_cue_ids"
    )) {
        $null = Get-P2SpecIdArray $root.$property "MechanismSpec.$property" `
            -MaximumCount 4096
    }
    foreach ($formulaRecord in $formulaStagesById.Values) {
        if ([long]$formulaRecord.ModifierEventId -gt 0) {
            Assert-P2Condition (
                Test-P2SpecIdArrayContains $root.event_ids `
                    ([long]$formulaRecord.ModifierEventId)
            ) "P2_MECHANISM_STAGE_EVENT_UNKNOWN" `
                "formula modifier_event_id must appear in event_ids."
        }
    }
    if ($resolverId -gt 0) {
        Assert-P2Condition (Test-P2SpecIdArrayContains $root.resolver_ids $resolverId) `
            "P2_MECHANISM_ENTRY_RESOLVER_MISSING" `
            "resolver_id must appear in resolver_ids."
    }
    $null = Get-P2SpecTypeName $root.result_type "MechanismSpec.result_type"

    Assert-P2SpecUniqueObjects $root.mutation_contracts `
        "MechanismSpec.mutation_contracts" 0 128
    $previousStateOpId = 0L
    $mutationStateOpIds = [Collections.Generic.HashSet[long]]::new()
    foreach ($itemValue in @($root.mutation_contracts)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "state_op_id", "mutation_service_key", "atomic_group_id",
            "before_field_keys", "after_field_keys", "idempotency_policy",
            "failure_boundary"
        ) "MechanismSpec mutation contract"
        $stateOpId = Get-P2Integer $item.state_op_id "mutation state_op_id" `
            1 $script:P2MaxId
        Assert-P2Condition ($stateOpId -gt $previousStateOpId) `
            "P2_MECHANISM_MUTATION_ORDER" `
            "mutation state_op_ids must be strictly increasing."
        $previousStateOpId = $stateOpId
        $null = $mutationStateOpIds.Add($stateOpId)
        Assert-P2Condition (Test-P2SpecIdArrayContains $root.state_op_ids $stateOpId) `
            "P2_MECHANISM_MUTATION_ID_MISSING" `
            "mutation state_op_id must appear in state_op_ids."
        $null = Get-P2SpecKey $item.mutation_service_key `
            "mutation_service_key" 160
        $null = Get-P2Integer $item.atomic_group_id "atomic_group_id" `
            1 $script:P2MaxId
        $null = Get-P2SpecKeyArray $item.before_field_keys `
            "before_field_keys" -MaximumCount 256
        $null = Get-P2SpecKeyArray $item.after_field_keys `
            "after_field_keys" -MaximumCount 256
        $null = Get-P2Enum $item.idempotency_policy "idempotency_policy" @(
            "NOT_IDEMPOTENT", "REJECT_DUPLICATE", "IDEMPOTENT_BY_OPERATION_ID"
        )
        $null = Get-P2Enum $item.failure_boundary "failure_boundary" @(
            "BEFORE_GROUP", "ATOMIC_GROUP", "TERMINATE_ON_INVARIANT"
        )
    }

    Assert-P2SpecUniqueObjects $root.command_contracts `
        "MechanismSpec.command_contracts" 0 128
    $commandContractIds = [Collections.Generic.HashSet[long]]::new()
    $commandEmissionOrders = @{}
    foreach ($itemValue in @($root.command_contracts)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "command_id", "audience", "presentation_cue_ids", "barrier_policy",
            "optional_visual", "emission_order"
        ) "MechanismSpec command contract"
        $commandId = Get-P2Integer $item.command_id "command command_id" `
            1 $script:P2MaxId
        Assert-P2Condition ($commandContractIds.Add($commandId)) `
            "P2_MECHANISM_COMMAND_DUPLICATE" `
            "command_contracts repeats command_id $commandId."
        Assert-P2Condition (Test-P2SpecIdArrayContains $root.command_ids $commandId) `
            "P2_MECHANISM_COMMAND_ID_MISSING" `
            "command contract ID must appear in command_ids."
        $null = Get-P2Enum $item.audience "command audience" @(
            "AUTHORITY_ONLY", "OWNER", "OPPONENT", "PUBLIC", "SPECTATOR", "DEBUG_TEST"
        )
        $null = Get-P2SpecIdArray $item.presentation_cue_ids `
            "command presentation_cue_ids" -MaximumCount 4096
        foreach ($cueId in @($item.presentation_cue_ids)) {
            Assert-P2Condition (
                Test-P2SpecIdArrayContains $root.presentation_cue_ids ([long]$cueId)
            ) "P2_MECHANISM_COMMAND_CUE_MISSING" `
                "command cue $cueId must appear in presentation_cue_ids."
        }
        $null = Get-P2Enum $item.barrier_policy "command barrier_policy" @(
            "NONE", "OPTIONAL", "REQUIRED_LOCAL_ONLY"
        )
        $null = Get-P2Boolean $item.optional_visual "command optional_visual"
        $emissionOrder = Get-P2Integer $item.emission_order `
            "command emission_order" 1 4096
        $commandEmissionOrders[$commandId] = $emissionOrder
    }

    Assert-P2SpecUniqueObjects $root.execution_steps `
        "MechanismSpec.execution_steps" 1 512
    $previousStepOrder = 0L
    $executionReferences = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $availableValueSlotUnits = @{}
    foreach ($slotId in $inputSlotUnits.Keys) {
        $availableValueSlotUnits[$slotId] = [string]$inputSlotUnits[$slotId]
    }
    $executionCounts = @{
        FORMULA_STAGE = 0
        EVENT_EMISSION = 0
        RNG_DRAW = 0
        STATE_MUTATION = 0
        COMMAND_EMISSION = 0
    }
    foreach ($itemValue in @($root.execution_steps)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "step_order", "step_kind", "reference_id", "condition_kind"
        ) "MechanismSpec execution step"
        $stepOrder = Get-P2Integer $item.step_order `
            "execution step_order" 1 4096
        Assert-P2Condition ($stepOrder -gt $previousStepOrder) `
            "P2_MECHANISM_EXECUTION_ORDER" `
            "execution step_order must be strictly increasing."
        $previousStepOrder = $stepOrder
        $stepKind = Get-P2Enum $item.step_kind "execution step_kind" @(
            "FORMULA_STAGE", "EVENT_EMISSION", "RNG_DRAW",
            "STATE_MUTATION", "COMMAND_EMISSION"
        )
        $referenceId = Get-P2Integer $item.reference_id `
            "execution reference_id" 1 $script:P2MaxId
        $null = Get-P2SpecKey $item.condition_kind `
            "execution condition_kind" 160
        if ($stepKind -cne "EVENT_EMISSION") {
            Assert-P2Condition (
                $executionReferences.Add("$stepKind`:$referenceId")
            ) "P2_MECHANISM_EXECUTION_DUPLICATE" `
                "execution steps repeat $stepKind reference $referenceId."
        }
        $executionCounts[$stepKind] = [int]$executionCounts[$stepKind] + 1

        switch ($stepKind) {
            "FORMULA_STAGE" {
                Assert-P2Condition ($stageIds.Contains($referenceId)) `
                    "P2_MECHANISM_EXECUTION_STAGE_UNKNOWN" `
                    "execution step references unknown formula stage $referenceId."
                $formulaRecord = $formulaStagesById[$referenceId]
                for (
                    $operandIndex = 0;
                    $operandIndex -lt $formulaRecord.OperandSlotIds.Count;
                    $operandIndex++
                ) {
                    $operandSlotId = [long]$formulaRecord.OperandSlotIds[$operandIndex]
                    Assert-P2Condition (
                        $availableValueSlotUnits.ContainsKey($operandSlotId)
                    ) "P2_MECHANISM_STAGE_OPERAND_UNKNOWN" `
                        "formula stage reads unavailable value slot $operandSlotId."
                    $declaredUnit = [string]$formulaRecord.OperandUnits[$operandIndex]
                    $actualUnit = [string]$availableValueSlotUnits[$operandSlotId]
                    Assert-P2Condition ($declaredUnit -ceq $actualUnit) `
                        "P2_MECHANISM_STAGE_OPERAND_UNIT" `
                        "formula operand unit $declaredUnit does not match $actualUnit."
                }
                $availableValueSlotUnits[[long]$formulaRecord.OutputSlotId] = `
                    [string]$formulaRecord.ResultUnit
            }
            "EVENT_EMISSION" {
                Assert-P2Condition (
                    Test-P2SpecIdArrayContains $root.event_ids $referenceId
                ) "P2_MECHANISM_EXECUTION_EVENT_UNKNOWN" `
                    "execution step references unknown event $referenceId."
            }
            "RNG_DRAW" {
                Assert-P2Condition ($rngDrawIds.Contains($referenceId)) `
                    "P2_MECHANISM_EXECUTION_DRAW_UNKNOWN" `
                    "execution step references unknown RNG draw $referenceId."
                Assert-P2Condition (
                    [long]$rngDrawOrders[$referenceId] -eq $stepOrder
                ) "P2_MECHANISM_EXECUTION_DRAW_ORDER" `
                    "RNG draw_order must equal its unified execution step_order."
            }
            "STATE_MUTATION" {
                Assert-P2Condition ($mutationStateOpIds.Contains($referenceId)) `
                    "P2_MECHANISM_EXECUTION_MUTATION_UNKNOWN" `
                    "execution step references unknown mutation $referenceId."
            }
            "COMMAND_EMISSION" {
                Assert-P2Condition ($commandContractIds.Contains($referenceId)) `
                    "P2_MECHANISM_EXECUTION_COMMAND_UNKNOWN" `
                    "execution step references unknown command $referenceId."
                Assert-P2Condition (
                    [long]$commandEmissionOrders[$referenceId] -eq $stepOrder
                ) "P2_MECHANISM_EXECUTION_COMMAND_ORDER" `
                    "command emission_order must equal its unified step_order."
            }
        }
    }
    $expectedExecutionCounts = @{
        FORMULA_STAGE = $stageIds.Count
        RNG_DRAW = $rngDrawIds.Count
        STATE_MUTATION = $mutationStateOpIds.Count
        COMMAND_EMISSION = $commandContractIds.Count
    }
    foreach ($stepKind in $expectedExecutionCounts.Keys) {
        Assert-P2Condition (
            [int]$executionCounts[$stepKind] -eq
            [int]$expectedExecutionCounts[$stepKind]
        ) "P2_MECHANISM_EXECUTION_COVERAGE" `
            "execution_steps must cover every declared $stepKind exactly once."
    }

    Assert-P2SpecUniqueObjects $root.error_contracts `
        "MechanismSpec.error_contracts" 1 64
    $errorCodes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($itemValue in @($root.error_contracts)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "error_code", "category", "mutation_policy", "rng_policy",
            "termination_policy"
        ) "MechanismSpec error contract"
        $errorCode = Get-P2SpecKey $item.error_code "error_code" 160
        Assert-P2Condition ($errorCodes.Add($errorCode)) `
            "P2_MECHANISM_ERROR_DUPLICATE" "Duplicate error code '$errorCode'."
        $null = Get-P2Enum $item.category "error category" @(
            "EXPECTED_REJECTION", "DATA_ERROR", "INVARIANT_FAILURE", "CAPACITY_FAILURE"
        )
        $null = Get-P2Enum $item.mutation_policy "error mutation_policy" @(
            "NONE_COMMITTED", "PRIOR_ATOMIC_GROUPS_RETAINED", "TERMINATE_BATTLE"
        )
        $null = Get-P2Enum $item.rng_policy "error rng_policy" @(
            "NO_CONSUME", "PRIOR_DRAWS_RETAINED"
        )
        $null = Get-P2Enum $item.termination_policy "error termination_policy" @(
            "CONTINUE", "ABORT_ACTION", "END_BATTLE_ERROR"
        )
    }
    Assert-P2Object $root.atomicity_policy "MechanismSpec.atomicity_policy"
    $atomicity = [PSCustomObject]$root.atomicity_policy
    Assert-P2ExactProperties $atomicity @(
        "validation_policy", "rollback_policy", "command_capacity_preflight"
    ) "MechanismSpec.atomicity_policy"
    $null = Get-P2Enum $atomicity.validation_policy "atomicity validation_policy" @(
        "VALIDATE_ALL_BEFORE_MUTATION", "VALIDATE_PER_ATOMIC_GROUP"
    )
    $null = Get-P2Enum $atomicity.rollback_policy "atomicity rollback_policy" @(
        "NO_MUTATION_ON_FAILURE", "ATOMIC_GROUP_BOUNDARY", "TERMINATE_ON_INVARIANT"
    )
    $null = Get-P2Boolean $atomicity.command_capacity_preflight `
        "atomicity command_capacity_preflight"

    Assert-P2SpecUniqueObjects $root.test_requirements `
        "MechanismSpec.test_requirements" 1 64
    foreach ($itemValue in @($root.test_requirements)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "test_kind", "required_oracle_kinds", "minimum_cases",
            "required_for_target_maturity"
        ) "MechanismSpec test requirement"
        $testKind = Get-P2Enum $item.test_kind "test requirement kind" @(
            "FORMULA_UNIT", "RESOLVER_PHASE", "EVENT_HANDLER", "RNG",
            "STATE_MUTATION", "COMMAND_PRESENTATION", "AUDIENCE",
            "GAMEPLAY_INTERRUPTION", "SETTLEMENT_DECISION", "SCENARIO",
            "REPLAY", "PERFORMANCE"
        )
        $null = Get-P2SpecOracleArray $item.required_oracle_kinds `
            "test requirement oracles"
        $requiredOracle = Get-P2RequiredOracleForTestKind $testKind
        Assert-P2Condition (
            Test-P2SpecKeyArrayContains `
                $item.required_oracle_kinds $requiredOracle
        ) "P2_MECHANISM_TEST_ORACLE" `
            "test requirement $testKind must include oracle $requiredOracle."
        $null = Get-P2Integer $item.minimum_cases "test minimum_cases" 1 65535
        $null = Get-P2Enum $item.required_for_target_maturity `
            "test required_for_target_maturity" $script:P2MaturityOrder
    }

    return [pscustomobject]@{
        PrimaryId = $mechanismId
        DebugKey = [string]$root.debug_key
        TargetMaturity = $targetMaturity
        CanonicalJson = ConvertTo-BattleCanonicalJson $root
        Sha256 = Get-BattleSha256Text (ConvertTo-BattleCanonicalJson $root)
    }
}

function Test-P2EventSchema {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Schema)

    Assert-P2SpecSafeValue $Schema "EventSchema"
    Assert-P2Object $Schema "EventSchema"
    $root = [PSCustomObject]$Schema
    Assert-P2ExactProperties $root @(
        "artifact_kind", "event_id", "debug_key", "schema_version",
        "behavior_version", "context_type", "readable_fields",
        "writable_operations", "aggregation_policy", "sort_key",
        "short_circuit_rule", "nested_event_ids", "same_instance_recall_policy",
        "maximum_same_instance_recalls", "activation_visibility",
        "removal_visibility", "rounding_stage_refs", "rounding_mode",
        "rounding_schedule", "trace_policy"
    ) "EventSchema"
    $null = Get-P2Enum $root.artifact_kind "EventSchema.artifact_kind" @(
        "EVENT_SCHEMA"
    )
    $eventId = Get-P2Integer $root.event_id "EventSchema.event_id" `
        1 $script:P2MaxId
    $debugKey = Get-P2String $root.debug_key "EventSchema.debug_key" `
        '^[A-Z][A-Z0-9_]*$' 128
    $null = Get-P2Integer $root.schema_version "EventSchema.schema_version" `
        1 $script:P2MaxId
    $null = Get-P2Integer $root.behavior_version "EventSchema.behavior_version" `
        1 $script:P2MaxId
    $null = Get-P2SpecTypeName $root.context_type "EventSchema.context_type"

    Assert-P2SpecUniqueObjects $root.readable_fields `
        "EventSchema.readable_fields" 0 128
    $fieldNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($itemValue in @($root.readable_fields)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "field_name", "value_kind", "stable_domain", "minimum", "maximum",
            "source", "visibility"
        ) "EventSchema readable field"
        $fieldName = Get-P2String $item.field_name "readable field_name" `
            '^[a-z][a-z0-9_]*$' 64
        Assert-P2Condition ($fieldNames.Add($fieldName)) `
            "P2_EVENT_FIELD_DUPLICATE" "Duplicate readable field '$fieldName'."
        $valueKind = Get-P2Enum $item.value_kind "readable value_kind" @(
            "STABLE_ID", "SIGNED_INT", "BOOL"
        )
        $domain = Get-P2Enum $item.stable_domain "readable stable_domain" @(
            "ENTITY", "EFFECT", "ITEM", "MOVE", "MESSAGE", "NONE"
        )
        $minimum = Get-P2Integer $item.minimum "readable minimum" `
            ([long]-2147483648) $script:P2MaxId
        $maximum = Get-P2Integer $item.maximum "readable maximum" `
            ([long]-2147483648) $script:P2MaxId
        Assert-P2SpecValueContract $valueKind $domain $minimum $maximum `
            "EventSchema readable field"
        $null = Get-P2Enum $item.source "readable source" @(
            "CONTEXT", "BATTLE_READ_API", "CATALOG", "EFFECT_INSTANCE"
        )
        $null = Get-P2Enum $item.visibility "readable visibility" @(
            "AUTHORITY_ONLY", "OWNER", "OPPONENT", "PUBLIC", "DEBUG_TEST"
        )
    }

    Assert-P2SpecUniqueObjects $root.writable_operations `
        "EventSchema.writable_operations" 0 64
    $operationKeys = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($itemValue in @($root.writable_operations)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "operation_key", "argument_type", "result_type", "mutation_class"
        ) "EventSchema writable operation"
        $operationKey = Get-P2SpecKey $item.operation_key `
            "writable operation_key" 160
        Assert-P2Condition ($operationKeys.Add($operationKey)) `
            "P2_EVENT_OPERATION_DUPLICATE" `
            "Duplicate writable operation '$operationKey'."
        $null = Get-P2SpecTypeName $item.argument_type `
            "writable argument_type"
        $null = Get-P2SpecTypeName $item.result_type "writable result_type"
        $null = Get-P2Enum $item.mutation_class "writable mutation_class" @(
            "RELAY_VALUE", "DENY", "ACCEPT", "REPLACE_TARGET", "ACCUMULATE",
            "CONTEXT_RESULT"
        )
    }
    $aggregationPolicy = Get-P2Enum $root.aggregation_policy `
        "EventSchema.aggregation_policy" @(
            "VISIT_ALL", "FIRST_DENY", "FIRST_ACCEPT", "FOLD_MODIFIERS",
            "REPLACE_LAST"
        )
    Assert-P2SpecUniqueObjects $root.sort_key "EventSchema.sort_key" 1 16
    $eventSortFields = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($itemValue in @($root.sort_key)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @("field_key", "direction", "source") `
            "EventSchema sort term"
        $sortFieldKey = Get-P2SpecKey $item.field_key "sort field_key" 160
        Assert-P2Condition ($eventSortFields.Add($sortFieldKey)) `
            "P2_EVENT_SORT_FIELD_DUPLICATE" `
            "EventSchema sort_key repeats $sortFieldKey."
        $null = Get-P2Enum $item.direction "sort direction" @("ASC", "DESC")
        $null = Get-P2Enum $item.source "sort source" @(
            "EVENT_SCHEMA", "HANDLER_BINDING", "OWNER", "EFFECT_INSTANCE", "STABLE_ID"
        )
    }
    $finalSort = [PSCustomObject]@($root.sort_key)[@($root.sort_key).Count - 1]
    Assert-P2Condition (
        [string]$finalSort.field_key -ceq "INSTANCE_ID" -and
        [string]$finalSort.direction -ceq "ASC" -and
        [string]$finalSort.source -ceq "STABLE_ID"
    ) "P2_EVENT_SORT_TIE_BREAK" `
        "EventSchema sort_key must end with INSTANCE_ID ASC from STABLE_ID."
    $shortCircuitRule = Get-P2Enum $root.short_circuit_rule `
        "EventSchema.short_circuit_rule" @(
            "NONE", "ON_DENY", "ON_ACCEPT", "ON_ERROR", "ON_TERMINAL_RESULT"
        )
    if ($aggregationPolicy -ceq "FIRST_DENY") {
        Assert-P2Condition ($shortCircuitRule -ceq "ON_DENY") `
            "P2_EVENT_AGGREGATION_SHORT_CIRCUIT" `
            "FIRST_DENY aggregation requires ON_DENY short circuit."
    }
    elseif ($aggregationPolicy -ceq "FIRST_ACCEPT") {
        Assert-P2Condition ($shortCircuitRule -ceq "ON_ACCEPT") `
            "P2_EVENT_AGGREGATION_SHORT_CIRCUIT" `
            "FIRST_ACCEPT aggregation requires ON_ACCEPT short circuit."
    }
    else {
        Assert-P2Condition (
            $shortCircuitRule -cin @("NONE", "ON_ERROR", "ON_TERMINAL_RESULT")
        ) "P2_EVENT_AGGREGATION_SHORT_CIRCUIT" `
            "$aggregationPolicy cannot use accept/deny short circuit."
    }
    $null = Get-P2SpecIdArray $root.nested_event_ids `
        "EventSchema.nested_event_ids" -MaximumCount 256
    $recallPolicy = Get-P2Enum $root.same_instance_recall_policy `
        "EventSchema.same_instance_recall_policy" @(
            "DENY", "ALLOW_ONCE", "ALLOW_BOUNDED"
        )
    $maximumRecalls = Get-P2Integer $root.maximum_same_instance_recalls `
        "EventSchema.maximum_same_instance_recalls" 0 64
    if ($recallPolicy -ceq "DENY") {
        Assert-P2Condition ($maximumRecalls -eq 0) "P2_EVENT_RECALL_BOUND" `
            "DENY recall requires maximum_same_instance_recalls 0."
    }
    elseif ($recallPolicy -ceq "ALLOW_ONCE") {
        Assert-P2Condition ($maximumRecalls -eq 1) "P2_EVENT_RECALL_BOUND" `
            "ALLOW_ONCE requires maximum_same_instance_recalls 1."
    }
    else {
        Assert-P2Condition ($maximumRecalls -ge 2) "P2_EVENT_RECALL_BOUND" `
            "ALLOW_BOUNDED requires maximum_same_instance_recalls at least 2."
    }
    $null = Get-P2Enum $root.activation_visibility `
        "EventSchema.activation_visibility" @(
            "IMMEDIATE_IF_NOT_VISITED", "NEXT_NESTED_EVENT", "NEXT_DISPATCH"
        )
    $null = Get-P2Enum $root.removal_visibility `
        "EventSchema.removal_visibility" @(
            "IMMEDIATE", "AFTER_CURRENT_EVENT", "NEXT_DISPATCH"
        )
    Assert-P2SpecUniqueObjects $root.rounding_stage_refs `
        "EventSchema.rounding_stage_refs" 0 256
    $previousRoundingMechanismId = 0L
    $previousRoundingStageId = 0L
    foreach ($itemValue in @($root.rounding_stage_refs)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @("mechanism_id", "stage_id") `
            "EventSchema rounding stage reference"
        $roundingMechanismId = Get-P2Integer $item.mechanism_id `
            "rounding stage mechanism_id" 1 $script:P2MaxId
        $roundingStageId = Get-P2Integer $item.stage_id `
            "rounding stage stage_id" 1 $script:P2MaxId
        Assert-P2Condition (
            $roundingMechanismId -gt $previousRoundingMechanismId -or
            ($roundingMechanismId -eq $previousRoundingMechanismId -and
                $roundingStageId -gt $previousRoundingStageId)
        ) "P2_EVENT_ROUNDING_STAGE_ORDER" `
            "rounding_stage_refs must be ordered by mechanism_id and stage_id."
        $previousRoundingMechanismId = $roundingMechanismId
        $previousRoundingStageId = $roundingStageId
    }
    $roundingMode = Get-P2Enum $root.rounding_mode `
        "EventSchema.rounding_mode" @(
            "NONE", "FLOOR", "CEIL", "TOWARD_ZERO", "AWAY_FROM_ZERO",
            "NEAREST_TIES_DOWN", "NEAREST_TIES_UP"
        )
    $roundingSchedule = Get-P2Enum $root.rounding_schedule `
        "EventSchema.rounding_schedule" @(
            "NONE", "AFTER_EACH_MODIFIER", "AFTER_EACH_OPERATION", "AT_STAGE_END"
        )
    if ($roundingMode -ceq "NONE") {
        Assert-P2Condition (
            @($root.rounding_stage_refs).Count -eq 0 -and
            $roundingSchedule -ceq "NONE"
        ) "P2_EVENT_ROUNDING_NONE" `
            "NONE rounding requires no stages and schedule NONE."
    }
    else {
        Assert-P2Condition (
            @($root.rounding_stage_refs).Count -gt 0 -and
            $roundingSchedule -cne "NONE"
        ) "P2_EVENT_ROUNDING_REQUIRED" `
            "Active rounding requires stages and a non-NONE schedule."
    }
    Assert-P2Object $root.trace_policy "EventSchema.trace_policy"
    $trace = [PSCustomObject]$root.trace_policy
    Assert-P2ExactProperties $trace @(
        "level", "record_context_hash", "record_handler_order",
        "record_short_circuit", "trace_field_keys"
    ) "EventSchema.trace_policy"
    $traceLevel = Get-P2Enum $trace.level "trace level" @(
        "OFF", "ERRORS", "DETERMINISM", "FULL"
    )
    $recordContext = Get-P2Boolean $trace.record_context_hash `
        "trace record_context_hash"
    $recordOrder = Get-P2Boolean $trace.record_handler_order `
        "trace record_handler_order"
    $recordShort = Get-P2Boolean $trace.record_short_circuit `
        "trace record_short_circuit"
    $null = Get-P2SpecKeyArray $trace.trace_field_keys `
        "trace trace_field_keys" -MaximumCount 64
    if ($traceLevel -ceq "OFF") {
        Assert-P2Condition (
            -not $recordContext -and -not $recordOrder -and -not $recordShort -and
            @($trace.trace_field_keys).Count -eq 0
        ) "P2_EVENT_TRACE_OFF" "OFF trace policy cannot enable trace fields."
    }
    $canonical = ConvertTo-BattleCanonicalJson $root
    return [pscustomobject]@{
        PrimaryId = $eventId
        DebugKey = $debugKey
        CanonicalJson = $canonical
        Sha256 = Get-BattleSha256Text $canonical
    }
}

function Test-P2HandlerBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Binding)

    Assert-P2SpecSafeValue $Binding "HandlerBinding"
    Assert-P2Object $Binding "HandlerBinding"
    $root = [PSCustomObject]$Binding
    Assert-P2ExactProperties $root @(
        "artifact_kind", "handler_id", "debug_key", "schema_version",
        "behavior_version", "family", "event_id", "implementation_key",
        "context_type", "instance_state_kind", "priority_source",
        "allowed_queries", "allowed_mutations", "allowed_rng_draw_ids",
        "mechanism_ids"
    ) "HandlerBinding"
    $null = Get-P2Enum $root.artifact_kind "HandlerBinding.artifact_kind" @(
        "HANDLER_BINDING"
    )
    $handlerId = Get-P2Integer $root.handler_id "HandlerBinding.handler_id" `
        1 $script:P2MaxId
    $debugKey = Get-P2String $root.debug_key "HandlerBinding.debug_key" `
        '^[A-Z][A-Z0-9_]*$' 128
    $null = Get-P2Integer $root.schema_version "HandlerBinding.schema_version" `
        1 $script:P2MaxId
    $null = Get-P2Integer $root.behavior_version `
        "HandlerBinding.behavior_version" 1 $script:P2MaxId
    $null = Get-P2Enum $root.family "HandlerBinding.family" @(
        "DAMAGE", "STATUS", "ACTION", "LIFECYCLE", "TARGETING", "ACCURACY",
        "CRITICAL", "ITEM", "ABILITY", "FIELD", "SIDE", "POSITION",
        "OUTCOME", "MODE"
    )
    $null = Get-P2Integer $root.event_id "HandlerBinding.event_id" `
        1 $script:P2MaxId
    $null = Get-P2String $root.implementation_key `
        "HandlerBinding.implementation_key" '^[a-z][a-z0-9_]*$' 128
    $null = Get-P2SpecTypeName $root.context_type "HandlerBinding.context_type"
    $null = Get-P2SpecKey $root.instance_state_kind `
        "HandlerBinding.instance_state_kind" 160
    $null = Get-P2Enum $root.priority_source "HandlerBinding.priority_source" @(
        "DEFINITION", "INSTANCE", "EVENT_SCHEMA"
    )
    $null = Get-P2SpecKeyArray $root.allowed_queries `
        "HandlerBinding.allowed_queries" -MaximumCount 128
    $null = Get-P2SpecKeyArray $root.allowed_mutations `
        "HandlerBinding.allowed_mutations" -MaximumCount 128
    $null = Get-P2SpecIdArray $root.mechanism_ids `
        "HandlerBinding.mechanism_ids" -MinimumCount 1 -MaximumCount 256
    Assert-P2SpecUniqueObjects $root.allowed_rng_draw_ids `
        "HandlerBinding.allowed_rng_draw_ids" 0 128
    $previousMechanismId = 0L
    $previousDrawId = 0L
    foreach ($itemValue in @($root.allowed_rng_draw_ids)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @("mechanism_id", "draw_id") `
            "HandlerBinding RNG draw ref"
        $mechanismId = Get-P2Integer $item.mechanism_id `
            "HandlerBinding RNG mechanism_id" 1 $script:P2MaxId
        Assert-P2Condition (
            Test-P2SpecIdArrayContains $root.mechanism_ids $mechanismId
        ) "P2_HANDLER_RNG_MECHANISM_UNKNOWN" `
            "Handler RNG references must use a declared mechanism_id."
        $drawId = Get-P2Integer $item.draw_id `
            "HandlerBinding RNG draw_id" 1 $script:P2MaxId
        Assert-P2Condition (
            $mechanismId -gt $previousMechanismId -or
            ($mechanismId -eq $previousMechanismId -and $drawId -gt $previousDrawId)
        ) "P2_HANDLER_RNG_ORDER" `
            "Handler RNG references must be unique and ordered by mechanism/draw ID."
        $previousMechanismId = $mechanismId
        $previousDrawId = $drawId
    }
    $canonical = ConvertTo-BattleCanonicalJson $root
    return [pscustomobject]@{
        PrimaryId = $handlerId
        DebugKey = $debugKey
        CanonicalJson = $canonical
        Sha256 = Get-BattleSha256Text $canonical
    }
}

function Test-P2ResolverSpec {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Spec)

    Assert-P2SpecSafeValue $Spec "ResolverSpec"
    Assert-P2Object $Spec "ResolverSpec"
    $root = [PSCustomObject]$Spec
    Assert-P2ExactProperties $root @(
        "artifact_kind", "resolver_id", "debug_key", "schema_version",
        "behavior_version", "owner_module", "input_type", "output_type",
        "phases", "legal_event_emissions", "allowed_nested_resolver_ids",
        "mutation_services", "interruption_points", "error_semantics",
        "termination_behavior", "mechanism_ids"
    ) "ResolverSpec"
    $null = Get-P2Enum $root.artifact_kind "ResolverSpec.artifact_kind" @(
        "RESOLVER_SPEC"
    )
    $resolverId = Get-P2Integer $root.resolver_id "ResolverSpec.resolver_id" `
        1 $script:P2MaxId
    $debugKey = Get-P2String $root.debug_key "ResolverSpec.debug_key" `
        '^[A-Z][A-Z0-9_]*$' 128
    $null = Get-P2Integer $root.schema_version "ResolverSpec.schema_version" `
        1 $script:P2MaxId
    $null = Get-P2Integer $root.behavior_version "ResolverSpec.behavior_version" `
        1 $script:P2MaxId
    $null = Get-P2SpecKey $root.owner_module "ResolverSpec.owner_module" 160
    $null = Get-P2SpecTypeName $root.input_type "ResolverSpec.input_type"
    $null = Get-P2SpecTypeName $root.output_type "ResolverSpec.output_type"
    $null = Get-P2SpecIdArray $root.mechanism_ids `
        "ResolverSpec.mechanism_ids" -MinimumCount 1 -MaximumCount 512
    Assert-P2SpecUniqueObjects $root.phases "ResolverSpec.phases" 1 128
    $phaseIds = [Collections.Generic.HashSet[long]]::new()
    $phaseOrders = [Collections.Generic.HashSet[long]]::new()
    $previousPhaseId = 0L
    foreach ($itemValue in @($root.phases)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "phase_id", "phase_order", "debug_key", "subphase_ids",
            "entry_invariants", "exit_invariants", "reentry_policy",
            "maximum_reentries", "mechanism_ids"
        ) "ResolverSpec phase"
        $phaseId = Get-P2Integer $item.phase_id "Resolver phase_id" `
            1 $script:P2MaxId
        Assert-P2Condition ($phaseId -gt $previousPhaseId) `
            "P2_RESOLVER_PHASE_ORDER" "Resolver phase IDs must be increasing."
        $previousPhaseId = $phaseId
        $null = $phaseIds.Add($phaseId)
        $phaseOrder = Get-P2Integer $item.phase_order `
            "Resolver phase_order" 1 128
        Assert-P2Condition ($phaseOrders.Add($phaseOrder)) `
            "P2_RESOLVER_PHASE_ORDER_DUPLICATE" `
            "Resolver phase_order values must be unique."
        $null = Get-P2String $item.debug_key "Resolver phase debug_key" `
            '^[A-Z][A-Z0-9_]*$' 128
        $null = Get-P2SpecIdArray $item.subphase_ids `
            "Resolver phase subphase_ids" -MaximumCount 64
        $null = Get-P2SpecKeyArray $item.entry_invariants `
            "Resolver phase entry_invariants" -MaximumCount 128
        $null = Get-P2SpecKeyArray $item.exit_invariants `
            "Resolver phase exit_invariants" -MaximumCount 128
        $reentry = Get-P2Enum $item.reentry_policy "Resolver phase reentry_policy" @(
            "DENY", "ALLOW_ONCE", "ALLOW_BOUNDED", "RESUME_ONLY"
        )
        $maximum = Get-P2Integer $item.maximum_reentries `
            "Resolver phase maximum_reentries" 0 64
        if ($reentry -cin @("DENY", "RESUME_ONLY")) {
            Assert-P2Condition ($maximum -eq 0) "P2_RESOLVER_REENTRY_ZERO" `
                "$reentry requires maximum_reentries 0."
        }
        elseif ($reentry -ceq "ALLOW_ONCE") {
            Assert-P2Condition ($maximum -eq 1) "P2_RESOLVER_REENTRY_ONCE" `
                "ALLOW_ONCE requires maximum_reentries 1."
        }
        else {
            Assert-P2Condition ($maximum -gt 0) "P2_RESOLVER_REENTRY_BOUNDED" `
                "ALLOW_BOUNDED requires positive maximum_reentries."
        }
        $null = Get-P2SpecIdArray $item.mechanism_ids `
            "Resolver phase mechanism_ids" -MinimumCount 1 -MaximumCount 256
        foreach ($phaseMechanismId in @($item.mechanism_ids)) {
            Assert-P2Condition (
                Test-P2SpecIdArrayContains `
                    $root.mechanism_ids ([long]$phaseMechanismId)
            ) "P2_RESOLVER_PHASE_MECHANISM_UNKNOWN" `
                "Resolver phases must use declared mechanism_ids."
        }
    }

    Assert-P2SpecUniqueObjects $root.legal_event_emissions `
        "ResolverSpec.legal_event_emissions" 0 256
    foreach ($itemValue in @($root.legal_event_emissions)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "phase_id", "event_id", "emission_point", "nested_policy",
            "maximum_nested_depth"
        ) "ResolverSpec event emission"
        $phaseId = Get-P2Integer $item.phase_id "emission phase_id" `
            1 $script:P2MaxId
        Assert-P2Condition ($phaseIds.Contains($phaseId)) `
            "P2_RESOLVER_EMISSION_PHASE" `
            "Event emission references unknown local phase $phaseId."
        $null = Get-P2Integer $item.event_id "emission event_id" `
            1 $script:P2MaxId
        $null = Get-P2Enum $item.emission_point "emission point" @(
            "BEFORE_PHASE", "DURING_PHASE", "AFTER_PHASE", "ON_ERROR",
            "ON_TERMINATION"
        )
        $nestedPolicy = Get-P2Enum $item.nested_policy "emission nested_policy" @(
            "DENY", "ALLOW_DECLARED_ONLY", "ALLOW_BOUNDED"
        )
        $maximumNestedDepth = Get-P2Integer $item.maximum_nested_depth `
            "emission maximum_nested_depth" 0 64
        if ($nestedPolicy -ceq "DENY") {
            Assert-P2Condition ($maximumNestedDepth -eq 0) `
                "P2_RESOLVER_NESTED_BOUND" `
                "DENY nested event emission requires depth 0."
        }
        elseif ($nestedPolicy -ceq "ALLOW_DECLARED_ONLY") {
            Assert-P2Condition ($maximumNestedDepth -eq 1) `
                "P2_RESOLVER_NESTED_BOUND" `
                "ALLOW_DECLARED_ONLY requires maximum_nested_depth 1."
        }
        else {
            Assert-P2Condition ($maximumNestedDepth -ge 2) `
                "P2_RESOLVER_NESTED_BOUND" `
                "ALLOW_BOUNDED requires maximum_nested_depth at least 2."
        }
    }
    $null = Get-P2SpecIdArray $root.allowed_nested_resolver_ids `
        "ResolverSpec.allowed_nested_resolver_ids" -MaximumCount 512
    $null = Get-P2SpecKeyArray $root.mutation_services `
        "ResolverSpec.mutation_services" -MaximumCount 128

    Assert-P2SpecUniqueObjects $root.interruption_points `
        "ResolverSpec.interruption_points" 0 64
    $previousInterruptionId = 0L
    foreach ($itemValue in @($root.interruption_points)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "interruption_id", "phase_id", "safe_boundary", "resume_phase_id",
            "request_owner"
        ) "ResolverSpec interruption"
        $interruptionId = Get-P2Integer $item.interruption_id `
            "interruption_id" 1 $script:P2MaxId
        Assert-P2Condition ($interruptionId -gt $previousInterruptionId) `
            "P2_RESOLVER_INTERRUPTION_ORDER" `
            "Interruption IDs must be strictly increasing."
        $previousInterruptionId = $interruptionId
        $phaseId = Get-P2Integer $item.phase_id "interruption phase_id" `
            1 $script:P2MaxId
        $resumeId = Get-P2Integer $item.resume_phase_id `
            "interruption resume_phase_id" 1 $script:P2MaxId
        Assert-P2Condition (
            $phaseIds.Contains($phaseId) -and $phaseIds.Contains($resumeId)
        ) "P2_RESOLVER_INTERRUPTION_PHASE" `
            "Interruption phases must exist in the local resolver."
        $null = Get-P2Enum $item.safe_boundary "interruption safe_boundary" @(
            "EVENT_STACK_EMPTY", "PHASE_COMMITTED", "COMMAND_BATCH_SEALED"
        )
        $null = Get-P2Enum $item.request_owner "interruption request_owner" @(
            "ACTOR", "SIDE", "APPLICATION"
        )
    }
    Assert-P2SpecUniqueObjects $root.error_semantics `
        "ResolverSpec.error_semantics" 1 64
    $errorCodes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($itemValue in @($root.error_semantics)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @(
            "error_code", "phase_id", "state_policy", "termination_policy"
        ) "ResolverSpec error semantic"
        $errorCode = Get-P2SpecKey $item.error_code "resolver error_code" 160
        Assert-P2Condition ($errorCodes.Add($errorCode)) `
            "P2_RESOLVER_ERROR_DUPLICATE" "Duplicate resolver error '$errorCode'."
        $phaseId = Get-P2Integer $item.phase_id "resolver error phase_id" `
            0 $script:P2MaxId
        Assert-P2Condition ($phaseId -eq 0 -or $phaseIds.Contains($phaseId)) `
            "P2_RESOLVER_ERROR_PHASE" `
            "Resolver error phase must be 0 or a local phase."
        $null = Get-P2Enum $item.state_policy "resolver error state_policy" @(
            "UNCHANGED", "PRIOR_ATOMIC_GROUPS_RETAINED", "TERMINAL_ERROR_STATE"
        )
        $null = Get-P2Enum $item.termination_policy `
            "resolver error termination_policy" @(
                "CONTINUE", "ABORT_RESOLVER", "END_BATTLE_ERROR"
            )
    }
    Assert-P2Object $root.termination_behavior "ResolverSpec.termination_behavior"
    $termination = [PSCustomObject]$root.termination_behavior
    Assert-P2ExactProperties $termination @(
        "normal_result", "error_result", "terminal_state", "pending_input_policy"
    ) "ResolverSpec.termination_behavior"
    $null = Get-P2SpecKey $termination.normal_result "normal_result" 160
    $null = Get-P2SpecKey $termination.error_result "error_result" 160
    $null = Get-P2Enum $termination.terminal_state "terminal_state" @(
        "NONE", "BATTLE_ENDED", "ERROR_ENDED"
    )
    $null = Get-P2Enum $termination.pending_input_policy `
        "pending_input_policy" @("FORBIDDEN", "DECLARED_INTERRUPTION_ONLY")
    $canonical = ConvertTo-BattleCanonicalJson $root
    return [pscustomobject]@{
        PrimaryId = $resolverId
        DebugKey = $debugKey
        CanonicalJson = $canonical
        Sha256 = Get-BattleSha256Text $canonical
    }
}

function Test-P2TestManifestEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Entry)

    Assert-P2SpecSafeValue $Entry "TestManifestEntry"
    Assert-P2Object $Entry "TestManifestEntry"
    $root = [PSCustomObject]$Entry
    Assert-P2ExactProperties $root @(
        "artifact_kind", "test_id", "debug_key", "schema_version", "test_kind",
        "fixture_id", "coverage_targets", "expected_event_ids",
        "expected_handler_ids", "expected_state_op_ids", "expected_command_ids",
        "required_oracle_kinds"
    ) "TestManifestEntry"
    $null = Get-P2Enum $root.artifact_kind `
        "TestManifestEntry.artifact_kind" @("TEST_MANIFEST_ENTRY")
    $testId = Get-P2Integer $root.test_id "TestManifestEntry.test_id" `
        1 $script:P2MaxId
    $debugKey = Get-P2String $root.debug_key "TestManifestEntry.debug_key" `
        '^[A-Z][A-Z0-9_]*$' 128
    $null = Get-P2Integer $root.schema_version `
        "TestManifestEntry.schema_version" 1 $script:P2MaxId
    $testKinds = @(
        "FORMULA_UNIT", "RESOLVER_PHASE", "EVENT_HANDLER", "RNG",
        "STATE_MUTATION", "COMMAND_PRESENTATION", "AUDIENCE",
        "GAMEPLAY_INTERRUPTION", "SETTLEMENT_DECISION", "SCENARIO",
        "REPLAY", "PERFORMANCE"
    )
    $testKind = Get-P2Enum $root.test_kind "TestManifestEntry.test_kind" `
        $testKinds
    $fixtureId = Get-P2Integer $root.fixture_id "TestManifestEntry.fixture_id" `
        0 $script:P2MaxId
    if ($testKind -ceq "SCENARIO") {
        Assert-P2Condition ($fixtureId -eq $testId) `
            "P2_TEST_SCENARIO_FIXTURE" `
            "SCENARIO fixture_id must equal test_id."
    }
    else {
        Assert-P2Condition ($fixtureId -eq 0) "P2_TEST_UNIT_FIXTURE" `
            "Non-SCENARIO tests must use fixture_id 0 in the P2B contract."
    }
    Assert-P2SpecUniqueObjects $root.coverage_targets `
        "TestManifestEntry.coverage_targets" 1 256
    $previousMechanismId = 0L
    $previousBranchId = 0L
    foreach ($itemValue in @($root.coverage_targets)) {
        $item = [PSCustomObject]$itemValue
        Assert-P2ExactProperties $item @("mechanism_id", "branch_id") `
            "TestManifestEntry coverage target"
        $mechanismId = Get-P2Integer $item.mechanism_id `
            "test coverage mechanism_id" 1 $script:P2MaxId
        $branchId = Get-P2Integer $item.branch_id `
            "test coverage branch_id" 1 $script:P2MaxId
        Assert-P2Condition (
            $mechanismId -gt $previousMechanismId -or
            ($mechanismId -eq $previousMechanismId -and $branchId -gt $previousBranchId)
        ) "P2_TEST_COVERAGE_ORDER" `
            "Coverage targets must be ordered by mechanism/branch ID."
        $previousMechanismId = $mechanismId
        $previousBranchId = $branchId
    }
    foreach ($property in @(
        "expected_event_ids", "expected_handler_ids", "expected_state_op_ids",
        "expected_command_ids"
    )) {
        $null = Get-P2SpecIdArray $root.$property `
            "TestManifestEntry.$property" -MaximumCount 512
    }
    $null = Get-P2SpecOracleArray $root.required_oracle_kinds `
        "TestManifestEntry.required_oracle_kinds"
    $requiredOracle = Get-P2RequiredOracleForTestKind $testKind
    Assert-P2Condition (
        Test-P2SpecKeyArrayContains $root.required_oracle_kinds $requiredOracle
    ) "P2_TEST_REQUIRED_ORACLE" `
        "$testKind tests must include oracle $requiredOracle."
    $canonical = ConvertTo-BattleCanonicalJson $root
    return [pscustomobject]@{
        PrimaryId = $testId
        DebugKey = $debugKey
        CanonicalJson = $canonical
        Sha256 = Get-BattleSha256Text $canonical
    }
}
