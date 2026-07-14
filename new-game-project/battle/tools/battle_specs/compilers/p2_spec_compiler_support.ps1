Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "..\validators\p2_spec_set_support.ps1")

$script:P2CompilerContractVersion = 1
$script:P2CompilerSpecFileName = "spec_manifest.json"
$script:P2CompilerRuntimeFileName = "runtime_manifest.json"

function New-P2CompilerDiagnostic {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Pass,
        [Parameter(Mandatory = $true)][string]$ArtifactKind,
        [Parameter(Mandatory = $true)][long]$PrimaryId,
        [Parameter(Mandatory = $true)][string]$FieldPath,
        [string]$TargetDomain = "",
        [long]$ScopeId = 0,
        [long]$TargetId = 0,
        [string]$Detail = ""
    )

    $sortKey = (
        "{0}|{1}|{2:D10}|{3}|{4}|{5:D10}|{6:D10}|{7}|{8}" -f
        $Pass, $ArtifactKind, $PrimaryId, $FieldPath, $TargetDomain,
        $ScopeId, $TargetId, $Code, $Detail
    )
    return [pscustomobject][ordered]@{
        code = $Code
        pass = $Pass
        artifact_kind = $ArtifactKind
        primary_id = $PrimaryId
        field_path = $FieldPath
        target_domain = $TargetDomain
        scope_id = $ScopeId
        target_id = $TargetId
        detail = $Detail
        sort_key = $sortKey
    }
}

function Add-P2CompilerDiagnostic {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][Collections.Generic.List[object]]$Diagnostics,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Pass,
        [Parameter(Mandatory = $true)][string]$ArtifactKind,
        [Parameter(Mandatory = $true)][long]$PrimaryId,
        [Parameter(Mandatory = $true)][string]$FieldPath,
        [string]$TargetDomain = "",
        [long]$ScopeId = 0,
        [long]$TargetId = 0,
        [string]$Detail = ""
    )

    if ($Diagnostics.Count -ge 65536) {
        throw "P2C_DIAGNOSTIC_LIMIT: Cross-reference diagnostics exceed 65536."
    }
    $Diagnostics.Add((New-P2CompilerDiagnostic -Code $Code -Pass $Pass `
        -ArtifactKind $ArtifactKind -PrimaryId $PrimaryId `
        -FieldPath $FieldPath -TargetDomain $TargetDomain `
        -ScopeId $ScopeId -TargetId $TargetId -Detail $Detail))
}

function Sort-P2CompilerDiagnostics {
    param([Parameter(Mandatory = $true)][object[]]$Diagnostics)

    $result = [object[]]@($Diagnostics)
    for ($index = 1; $index -lt $result.Count; $index++) {
        $candidate = $result[$index]
        $position = $index - 1
        while (
            $position -ge 0 -and
            [StringComparer]::Ordinal.Compare(
                [string]$result[$position].sort_key,
                [string]$candidate.sort_key
            ) -gt 0
        ) {
            $result[$position + 1] = $result[$position]
            $position--
        }
        $result[$position + 1] = $candidate
    }
    return $result
}

function Assert-P2CompilerNoDiagnostics {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][Collections.Generic.List[object]]$Diagnostics
    )

    if ($Diagnostics.Count -eq 0) {
        return
    }
    $ordered = @(Sort-P2CompilerDiagnostics -Diagnostics $Diagnostics.ToArray())
    $parts = [Collections.Generic.List[string]]::new()
    foreach ($item in $ordered) {
        $parts.Add((
            "{0} {1}:{2} {3} -> {4}[{5},{6}]{7}" -f
            $item.code, $item.artifact_kind, $item.primary_id,
            $item.field_path, $item.target_domain, $item.scope_id,
            $item.target_id,
            $(if ([string]::IsNullOrEmpty([string]$item.detail)) {
                ""
            } else {
                " ($($item.detail))"
            })
        ))
    }
    throw (
        "P2C_CROSS_REFERENCE_FAILED count=$($ordered.Count): " +
        ($parts -join "; ")
    )
}

function New-P2CompilerStableIndex {
    param([Parameter(Mandatory = $true)][PSCustomObject]$Manifest)

    $domains = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($domainValue in @($Manifest.domains)) {
        $domain = [PSCustomObject]$domainValue
        $entries = [Collections.Generic.Dictionary[string, object]]::new(
            [StringComparer]::Ordinal
        )
        foreach ($entryValue in @($domain.entries)) {
            $entry = [PSCustomObject]$entryValue
            $key = "$([long]$entry.scope_id):$([long]$entry.id)"
            $entries.Add($key, $entry)
        }
        $domains.Add([string]$domain.domain, $entries)
    }
    return ,$domains
}

function New-P2CompilerPresentationCueIndex {
    param([Parameter(Mandatory = $true)][PSCustomObject]$Manifest)

    $result = [Collections.Generic.Dictionary[long, object]]::new()
    foreach ($cueValue in @($Manifest.cues)) {
        $cue = [PSCustomObject]$cueValue
        $result.Add([long]$cue.presentation_cue_id, $cue)
    }
    return ,$result
}

function New-P2CompilerRecordMap {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Records,
        [Parameter(Mandatory = $true)][string]$IdProperty
    )

    $result = [Collections.Generic.Dictionary[long, object]]::new()
    foreach ($recordValue in @($Records)) {
        $record = [PSCustomObject]$recordValue
        $manifest = [PSCustomObject]$record.Manifest
        $identifier = [long]$manifest.$IdProperty
        $result.Add($identifier, $record)
    }
    return ,$result
}

function Test-P2CompilerIdArrayContains {
    param(
        [AllowNull()][object]$Values,
        [Parameter(Mandatory = $true)][long]$Identifier
    )

    foreach ($value in @($Values)) {
        if ([long]$value -eq $Identifier) {
            return $true
        }
    }
    return $false
}

function Test-P2CompilerKeyArrayContains {
    param(
        [AllowNull()][object]$Values,
        [Parameter(Mandatory = $true)][string]$Key
    )

    foreach ($value in @($Values)) {
        if ([string]$value -ceq $Key) {
            return $true
        }
    }
    return $false
}

function Get-P2CompilerSpecMapForDomain {
    param(
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$SpecMaps,
        [Parameter(Mandatory = $true)][string]$Domain
    )

    if ($SpecMaps.ContainsKey($Domain)) {
        return $SpecMaps[$Domain]
    }
    return $null
}

function Test-P2CompilerStableReference {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][Collections.Generic.List[object]]$Diagnostics,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$StableIndex,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$SpecMaps,
        [Parameter(Mandatory = $true)][string]$Pass,
        [Parameter(Mandatory = $true)][string]$ArtifactKind,
        [Parameter(Mandatory = $true)][long]$PrimaryId,
        [Parameter(Mandatory = $true)][string]$FieldPath,
        [Parameter(Mandatory = $true)][string]$Domain,
        [long]$ScopeId = 0,
        [Parameter(Mandatory = $true)][long]$TargetId,
        [switch]$RequireSpec
    )

    $domainEntries = $null
    if ($StableIndex.ContainsKey($Domain)) {
        $domainEntries = $StableIndex[$Domain]
    }
    $key = "$ScopeId`:$TargetId"
    if ($null -eq $domainEntries -or -not $domainEntries.ContainsKey($key)) {
        Add-P2CompilerDiagnostic -Diagnostics $Diagnostics `
            -Code "P2C_REF_UNKNOWN" -Pass $Pass `
            -ArtifactKind $ArtifactKind -PrimaryId $PrimaryId `
            -FieldPath $FieldPath -TargetDomain $Domain `
            -ScopeId $ScopeId -TargetId $TargetId
        return $false
    }
    $entry = [PSCustomObject]$domainEntries[$key]
    if ([string]$entry.status -cne "ACTIVE") {
        Add-P2CompilerDiagnostic -Diagnostics $Diagnostics `
            -Code "P2C_REF_INACTIVE" -Pass $Pass `
            -ArtifactKind $ArtifactKind -PrimaryId $PrimaryId `
            -FieldPath $FieldPath -TargetDomain $Domain `
            -ScopeId $ScopeId -TargetId $TargetId
        return $false
    }
    if ($RequireSpec) {
        $specMap = Get-P2CompilerSpecMapForDomain `
            -SpecMaps $SpecMaps -Domain $Domain
        if ($null -eq $specMap -or -not $specMap.ContainsKey($TargetId)) {
            Add-P2CompilerDiagnostic -Diagnostics $Diagnostics `
                -Code "P2C_SPEC_MISSING" -Pass $Pass `
                -ArtifactKind $ArtifactKind -PrimaryId $PrimaryId `
                -FieldPath $FieldPath -TargetDomain $Domain `
                -ScopeId $ScopeId -TargetId $TargetId
            return $false
        }
    }
    return $true
}

function Test-P2CompilerPresentationCueReference {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][Collections.Generic.List[object]]$Diagnostics,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[long, object]]$CueIndex,
        [Parameter(Mandatory = $true)][string]$Pass,
        [Parameter(Mandatory = $true)][string]$ArtifactKind,
        [Parameter(Mandatory = $true)][long]$PrimaryId,
        [Parameter(Mandatory = $true)][string]$FieldPath,
        [Parameter(Mandatory = $true)][long]$CueId
    )

    if (-not $CueIndex.ContainsKey($CueId)) {
        Add-P2CompilerDiagnostic -Diagnostics $Diagnostics `
            -Code "P2C_REF_UNKNOWN" -Pass $Pass `
            -ArtifactKind $ArtifactKind -PrimaryId $PrimaryId `
            -FieldPath $FieldPath -TargetDomain "PRESENTATION_CUE" `
            -TargetId $CueId
        return $false
    }
    if ([string]$CueIndex[$CueId].status -cne "ACTIVE") {
        Add-P2CompilerDiagnostic -Diagnostics $Diagnostics `
            -Code "P2C_CUE_INACTIVE" -Pass $Pass `
            -ArtifactKind $ArtifactKind -PrimaryId $PrimaryId `
            -FieldPath $FieldPath -TargetDomain "PRESENTATION_CUE" `
            -TargetId $CueId
        return $false
    }
    return $true
}

function Add-P2CompilerBackReferenceDiagnostic {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][Collections.Generic.List[object]]$Diagnostics,
        [Parameter(Mandatory = $true)][string]$Pass,
        [Parameter(Mandatory = $true)][string]$ArtifactKind,
        [Parameter(Mandatory = $true)][long]$PrimaryId,
        [Parameter(Mandatory = $true)][string]$FieldPath,
        [Parameter(Mandatory = $true)][string]$TargetDomain,
        [long]$ScopeId = 0,
        [Parameter(Mandatory = $true)][long]$TargetId,
        [string]$Detail = ""
    )

    Add-P2CompilerDiagnostic -Diagnostics $Diagnostics `
        -Code "P2C_BACKREF_MISMATCH" -Pass $Pass `
        -ArtifactKind $ArtifactKind -PrimaryId $PrimaryId `
        -FieldPath $FieldPath -TargetDomain $TargetDomain `
        -ScopeId $ScopeId -TargetId $TargetId -Detail $Detail
}

function Get-P2CompilerStableEntry {
    param(
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$StableIndex,
        [Parameter(Mandatory = $true)][string]$Domain,
        [long]$ScopeId = 0,
        [Parameter(Mandatory = $true)][long]$Identifier
    )

    if (-not $StableIndex.ContainsKey($Domain)) {
        return $null
    }
    $entries = $StableIndex[$Domain]
    $key = "$ScopeId`:$Identifier"
    if (-not $entries.ContainsKey($key)) {
        return $null
    }
    return $entries[$key]
}

function Add-P2CompilerMismatchDiagnostic {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][Collections.Generic.List[object]]$Diagnostics,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Pass,
        [Parameter(Mandatory = $true)][string]$ArtifactKind,
        [Parameter(Mandatory = $true)][long]$PrimaryId,
        [Parameter(Mandatory = $true)][string]$FieldPath,
        [Parameter(Mandatory = $true)][string]$TargetDomain,
        [long]$ScopeId = 0,
        [Parameter(Mandatory = $true)][long]$TargetId,
        [string]$Detail = ""
    )

    Add-P2CompilerDiagnostic -Diagnostics $Diagnostics -Code $Code `
        -Pass $Pass -ArtifactKind $ArtifactKind -PrimaryId $PrimaryId `
        -FieldPath $FieldPath -TargetDomain $TargetDomain `
        -ScopeId $ScopeId -TargetId $TargetId -Detail $Detail
}

function Test-P2CompilerMechanismReferences {
    param(
        [Parameter(Mandatory = $true)][object]$SpecSet,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$StableIndex,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$SpecMaps,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[long, object]]$CueIndex,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][Collections.Generic.List[object]]$Diagnostics
    )

    $mechanismMap = $SpecMaps["MECHANISM"]
    $eventMap = $SpecMaps["EVENT"]
    $handlerMap = $SpecMaps["HANDLER"]
    $resolverMap = $SpecMaps["RESOLVER"]
    $requirementEvaluations = `
        [Collections.Generic.Dictionary[long, object]]::new()
    $testsByMechanism = [Collections.Generic.Dictionary[long, object]]::new()
    foreach ($testRecordValue in @($SpecSet.TestEntries)) {
        $test = [PSCustomObject]$testRecordValue.Manifest
        foreach ($targetValue in @($test.coverage_targets)) {
            $target = [PSCustomObject]$targetValue
            $targetMechanismId = [long]$target.mechanism_id
            $targetBranchId = [long]$target.branch_id
            if (-not $mechanismMap.ContainsKey($targetMechanismId)) {
                continue
            }
            $targetMechanism = [PSCustomObject](
                $mechanismMap[$targetMechanismId].Manifest
            )
            $branchDeclared = @($targetMechanism.coverage_targets | Where-Object {
                [long]$_.branch_id -eq $targetBranchId
            }).Count -eq 1
            $stableBranch = Get-P2CompilerStableEntry `
                -StableIndex $StableIndex -Domain "BRANCH" `
                -ScopeId $targetMechanismId -Identifier $targetBranchId
            if (-not $branchDeclared -or $null -eq $stableBranch -or
                [string]$stableBranch.status -cne "ACTIVE") {
                continue
            }
            if (-not $testsByMechanism.ContainsKey($targetMechanismId)) {
                $testsByMechanism.Add(
                    $targetMechanismId,
                    [Collections.Generic.Dictionary[long, object]]::new()
                )
            }
            $testMap = $testsByMechanism[$targetMechanismId]
            $testId = [long]$test.test_id
            if (-not $testMap.ContainsKey($testId)) {
                $testMap.Add($testId, $test)
            }
        }
    }
    foreach ($recordValue in @($SpecSet.MechanismSpecs)) {
        $record = [PSCustomObject]$recordValue
        $mechanism = [PSCustomObject]$record.Manifest
        $mechanismId = [long]$mechanism.mechanism_id
        $kind = "MECHANISM_SPEC"
        $pass = "10_MECHANISM"

        if ([string]$mechanism.ruleset_mode -ceq "EXPLICIT") {
            foreach ($rulesetId in @($mechanism.ruleset_ids)) {
                Add-P2CompilerMismatchDiagnostic -Diagnostics $Diagnostics `
                    -Code "P2C_RULESET_PROVIDER_MISSING" -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $mechanismId `
                    -FieldPath "ruleset_ids" -TargetDomain "RULESET" `
                    -TargetId ([long]$rulesetId) `
                    -Detail "P2C has no versioned RULESET provider."
            }
        }
        foreach ($featureId in @($mechanism.feature_pack_ids)) {
            $null = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $mechanismId -FieldPath "feature_pack_ids" `
                -Domain "FEATURE" -TargetId ([long]$featureId)
        }
        foreach ($targetValue in @($mechanism.coverage_targets)) {
            $target = [PSCustomObject]$targetValue
            $null = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $mechanismId `
                -FieldPath "coverage_targets.branch_id" -Domain "BRANCH" `
                -ScopeId $mechanismId -TargetId ([long]$target.branch_id)
        }
        $targetMaturityRank = [Array]::IndexOf(
            $script:P2MaturityOrder,
            [string]$mechanism.target_maturity
        )
        $specifiedMaturityRank = [Array]::IndexOf(
            $script:P2MaturityOrder,
            "SPECIFIED"
        )
        $requiredTestCount = 0L
        $requiredOracleSet = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal
        )
        $specifiedRequirementsSatisfied = $true
        foreach ($requirementValue in @($mechanism.test_requirements)) {
            $requirement = [PSCustomObject]$requirementValue
            $requiredMaturityRank = [Array]::IndexOf(
                $script:P2MaturityOrder,
                [string]$requirement.required_for_target_maturity
            )
            if ($requiredMaturityRank -gt $targetMaturityRank -and
                $requiredMaturityRank -gt $specifiedMaturityRank) {
                continue
            }
            $qualifyingTestIds = [Collections.Generic.HashSet[long]]::new()
            if ($testsByMechanism.ContainsKey($mechanismId)) {
                foreach ($testValue in $testsByMechanism[$mechanismId].Values) {
                    $test = [PSCustomObject]$testValue
                    if ([string]$test.test_kind -cne
                        [string]$requirement.test_kind) {
                        continue
                    }
                    $testOracles = [Collections.Generic.HashSet[string]]::new(
                        [StringComparer]::Ordinal
                    )
                    foreach ($oracleValue in @($test.required_oracle_kinds)) {
                        $null = $testOracles.Add([string]$oracleValue)
                    }
                    $hasRequiredOracles = $true
                    foreach ($oracleValue in @(
                        $requirement.required_oracle_kinds
                    )) {
                        if (-not $testOracles.Contains([string]$oracleValue)) {
                            $hasRequiredOracles = $false
                            break
                        }
                    }
                    if ($hasRequiredOracles) {
                        $null = $qualifyingTestIds.Add([long]$test.test_id)
                    }
                }
            }
            $requirementSatisfied = (
                $qualifyingTestIds.Count -ge [long]$requirement.minimum_cases
            )
            if ($requiredMaturityRank -le $targetMaturityRank) {
                $requiredTestCount += [long]$requirement.minimum_cases
                foreach ($oracleValue in @(
                    $requirement.required_oracle_kinds
                )) {
                    $null = $requiredOracleSet.Add([string]$oracleValue)
                }
            }
            if ($requiredMaturityRank -le $specifiedMaturityRank -and
                -not $requirementSatisfied) {
                $specifiedRequirementsSatisfied = $false
            }
            if ($requiredMaturityRank -le $targetMaturityRank -and
                -not $requirementSatisfied) {
                Add-P2CompilerMismatchDiagnostic -Diagnostics $Diagnostics `
                    -Code "P2C_TEST_REQUIREMENT_UNMET" -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $mechanismId `
                    -FieldPath "test_requirements" -TargetDomain "TEST" `
                    -TargetId 0 -Detail ((
                        "kind={0};required_maturity={1};minimum_cases={2};" +
                        "qualifying_cases={3};required_oracles={4}"
                    ) -f [string]$requirement.test_kind,
                        [string]$requirement.required_for_target_maturity,
                        [long]$requirement.minimum_cases,
                        $qualifyingTestIds.Count,
                        (@($requirement.required_oracle_kinds) -join ','))
            }
        }
        [string[]]$requiredOracles = @($requiredOracleSet)
        [Array]::Sort($requiredOracles, [StringComparer]::Ordinal)
        $requirementEvaluations.Add($mechanismId, [pscustomobject][ordered]@{
            RequiredTestCount = $requiredTestCount
            RequiredOracles = [object[]]$requiredOracles
            SpecifiedRequirementsSatisfied = $specifiedRequirementsSatisfied
        })

        $referenceDefinitions = @(
            [pscustomobject]@{
                Property = "resolver_ids"; Domain = "RESOLVER"; RequireSpec = $true
            },
            [pscustomobject]@{
                Property = "event_ids"; Domain = "EVENT"; RequireSpec = $true
            },
            [pscustomobject]@{
                Property = "handler_ids"; Domain = "HANDLER"; RequireSpec = $true
            },
            [pscustomobject]@{
                Property = "state_op_ids"; Domain = "STATE_OP"; RequireSpec = $false
            },
            [pscustomobject]@{
                Property = "command_ids"; Domain = "COMMAND"; RequireSpec = $false
            }
        )
        foreach ($definition in $referenceDefinitions) {
            foreach ($targetIdValue in @($mechanism.($definition.Property))) {
                $arguments = @{
                    Diagnostics = $Diagnostics
                    StableIndex = $StableIndex
                    SpecMaps = $SpecMaps
                    Pass = $pass
                    ArtifactKind = $kind
                    PrimaryId = $mechanismId
                    FieldPath = [string]$definition.Property
                    Domain = [string]$definition.Domain
                    TargetId = [long]$targetIdValue
                }
                if ([bool]$definition.RequireSpec) {
                    $arguments.RequireSpec = $true
                }
                $null = Test-P2CompilerStableReference @arguments
            }
        }
        foreach ($cueId in @($mechanism.presentation_cue_ids)) {
            $null = Test-P2CompilerPresentationCueReference `
                -Diagnostics $Diagnostics -CueIndex $CueIndex -Pass $pass `
                -ArtifactKind $kind -PrimaryId $mechanismId `
                -FieldPath "presentation_cue_ids" -CueId ([long]$cueId)
        }

        foreach ($drawValue in @($mechanism.rng_draws)) {
            $draw = [PSCustomObject]$drawValue
            $drawId = [long]$draw.draw_id
            $null = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $mechanismId -FieldPath "rng_draws.draw_id" `
                -Domain "RNG_DRAW" -ScopeId $mechanismId -TargetId $drawId
            $null = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $mechanismId -FieldPath "rng_draws.stream_id" `
                -Domain "RNG_STREAM" -TargetId ([long]$draw.stream_id)
            $null = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $mechanismId -FieldPath "rng_draws.tag_id" `
                -Domain "RNG_TAG" -TargetId ([long]$draw.tag_id)
        }

        $mutationIds = [Collections.Generic.HashSet[long]]::new()
        foreach ($contractValue in @($mechanism.mutation_contracts)) {
            $contract = [PSCustomObject]$contractValue
            $null = $mutationIds.Add([long]$contract.state_op_id)
        }
        foreach ($stateOpIdValue in @($mechanism.state_op_ids)) {
            $stateOpId = [long]$stateOpIdValue
            if (-not $mutationIds.Contains($stateOpId)) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $mechanismId `
                    -FieldPath "state_op_ids" -TargetDomain "MUTATION_CONTRACT" `
                    -ScopeId $mechanismId -TargetId $stateOpId `
                    -Detail "No mutation_contract owns the root state_op_id."
            }
        }
        $commandContractIds = [Collections.Generic.HashSet[long]]::new()
        foreach ($contractValue in @($mechanism.command_contracts)) {
            $contract = [PSCustomObject]$contractValue
            $commandId = [long]$contract.command_id
            $null = $commandContractIds.Add($commandId)
            foreach ($cueId in @($contract.presentation_cue_ids)) {
                $null = Test-P2CompilerPresentationCueReference `
                    -Diagnostics $Diagnostics -CueIndex $CueIndex -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $mechanismId `
                    -FieldPath "command_contracts.presentation_cue_ids" `
                    -CueId ([long]$cueId)
            }
        }
        foreach ($commandIdValue in @($mechanism.command_ids)) {
            $commandId = [long]$commandIdValue
            if (-not $commandContractIds.Contains($commandId)) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $mechanismId `
                    -FieldPath "command_ids" -TargetDomain "COMMAND_CONTRACT" `
                    -ScopeId $mechanismId -TargetId $commandId `
                    -Detail "No command_contract owns the root command_id."
            }
        }

        foreach ($formulaValue in @($mechanism.formula_stages)) {
            $formula = [PSCustomObject]$formulaValue
            $eventId = [long]$formula.modifier_event_id
            if ($eventId -eq 0 -or -not $eventMap.ContainsKey($eventId)) {
                continue
            }
            $event = [PSCustomObject]$eventMap[$eventId].Manifest
            if ([string]$event.aggregation_policy -cne "FOLD_MODIFIERS") {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $mechanismId `
                    -FieldPath "formula_stages.modifier_event_id" `
                    -TargetDomain "EVENT" -TargetId $eventId `
                    -Detail "Modifier events must use FOLD_MODIFIERS aggregation."
            }
            $stageId = [long]$formula.stage_id
            $roundingOwnerFound = $false
            foreach ($referenceValue in @($event.rounding_stage_refs)) {
                $reference = [PSCustomObject]$referenceValue
                if ([long]$reference.mechanism_id -eq $mechanismId -and
                    [long]$reference.stage_id -eq $stageId) {
                    $roundingOwnerFound = $true
                    break
                }
            }
            if (-not $roundingOwnerFound) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $mechanismId `
                    -FieldPath "formula_stages.modifier_event_id" `
                    -TargetDomain "EVENT_ROUNDING_STAGE" `
                    -ScopeId $eventId -TargetId $stageId `
                    -Detail "Modifier event omits this formula stage."
            }
            elseif (
                [string]$event.rounding_mode -cne
                    [string]$formula.rounding_mode -or
                [string]$event.rounding_schedule -cne
                    [string]$formula.rounding_schedule
            ) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $mechanismId `
                    -FieldPath "formula_stages.rounding_mode" `
                    -TargetDomain "EVENT" -TargetId $eventId `
                    -Detail "Formula and modifier event rounding differ."
            }
        }

        foreach ($resolverIdValue in @($mechanism.resolver_ids)) {
            $resolverId = [long]$resolverIdValue
            if (-not $resolverMap.ContainsKey($resolverId)) {
                continue
            }
            $resolver = [PSCustomObject]$resolverMap[$resolverId].Manifest
            if (-not (Test-P2CompilerIdArrayContains `
                -Values $resolver.mechanism_ids -Identifier $mechanismId)) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $mechanismId `
                    -FieldPath "resolver_ids" -TargetDomain "RESOLVER" `
                    -TargetId $resolverId `
                    -Detail "Resolver mechanism_ids omits this mechanism."
            }
        }
        foreach ($handlerIdValue in @($mechanism.handler_ids)) {
            $handlerId = [long]$handlerIdValue
            if (-not $handlerMap.ContainsKey($handlerId)) {
                continue
            }
            $handler = [PSCustomObject]$handlerMap[$handlerId].Manifest
            if (-not (Test-P2CompilerIdArrayContains `
                -Values $handler.mechanism_ids -Identifier $mechanismId)) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $mechanismId `
                    -FieldPath "handler_ids" -TargetDomain "HANDLER" `
                    -TargetId $handlerId `
                    -Detail "Handler mechanism_ids omits this mechanism."
            }
            if (-not (Test-P2CompilerIdArrayContains `
                -Values $mechanism.event_ids -Identifier ([long]$handler.event_id))) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $mechanismId `
                    -FieldPath "handler_ids" -TargetDomain "EVENT" `
                    -TargetId ([long]$handler.event_id) `
                    -Detail "A linked handler's event is absent from event_ids."
            }
        }

        $entryResolverId = [long]$mechanism.resolver_id
        $entryPhaseId = [long]$mechanism.phase_id
        $entrySubphaseId = [long]$mechanism.subphase_id
        if (($entryResolverId -eq 0) -ne ($entryPhaseId -eq 0) -or
            ($entrySubphaseId -gt 0 -and (
                $entryResolverId -eq 0 -or $entryPhaseId -eq 0
            ))) {
            Add-P2CompilerMismatchDiagnostic `
                -Diagnostics $Diagnostics -Code "P2C_SCOPE_MISMATCH" `
                -Pass $pass -ArtifactKind $kind -PrimaryId $mechanismId `
                -FieldPath "resolver_id/phase_id/subphase_id" `
                -TargetDomain "RESOLVER_PHASE" `
                -ScopeId $entryResolverId -TargetId $entryPhaseId `
                -Detail "Entry resolver and phase must form a complete scope."
        }
        if ($entryResolverId -gt 0 -and $entryPhaseId -gt 0) {
            $resolverValid = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $mechanismId -FieldPath "resolver_id" `
                -Domain "RESOLVER" -TargetId $entryResolverId -RequireSpec
            $phaseValid = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $mechanismId -FieldPath "phase_id" -Domain "PHASE" `
                -ScopeId $entryResolverId -TargetId $entryPhaseId
            if ($resolverValid -and $resolverMap.ContainsKey($entryResolverId)) {
                $resolver = [PSCustomObject]$resolverMap[$entryResolverId].Manifest
                $localPhases = @($resolver.phases | Where-Object {
                    [long]$_.phase_id -eq $entryPhaseId
                })
                if ($phaseValid -and $localPhases.Count -ne 1) {
                    Add-P2CompilerMismatchDiagnostic `
                        -Diagnostics $Diagnostics -Code "P2C_SCOPE_MISMATCH" `
                        -Pass $pass -ArtifactKind $kind -PrimaryId $mechanismId `
                        -FieldPath "phase_id" -TargetDomain "PHASE" `
                        -ScopeId $entryResolverId -TargetId $entryPhaseId `
                        -Detail "The phase is not declared by the entry resolver."
                }
                elseif ($localPhases.Count -eq 1) {
                    $phase = [PSCustomObject]$localPhases[0]
                    if (-not (Test-P2CompilerIdArrayContains `
                        -Values $phase.mechanism_ids -Identifier $mechanismId)) {
                        Add-P2CompilerBackReferenceDiagnostic `
                            -Diagnostics $Diagnostics -Pass $pass `
                            -ArtifactKind $kind -PrimaryId $mechanismId `
                            -FieldPath "phase_id" -TargetDomain "PHASE" `
                            -ScopeId $entryResolverId -TargetId $entryPhaseId `
                            -Detail "Entry phase mechanism_ids omits this mechanism."
                    }
                    if ($entrySubphaseId -gt 0 -and -not (
                        Test-P2CompilerIdArrayContains `
                            -Values $phase.subphase_ids `
                            -Identifier $entrySubphaseId
                    )) {
                        Add-P2CompilerMismatchDiagnostic `
                            -Diagnostics $Diagnostics -Code "P2C_SCOPE_MISMATCH" `
                            -Pass $pass -ArtifactKind $kind `
                            -PrimaryId $mechanismId -FieldPath "subphase_id" `
                            -TargetDomain "SUBPHASE" -ScopeId $entryPhaseId `
                            -TargetId $entrySubphaseId `
                            -Detail "The subphase is not local to the entry phase."
                    }
                }
            }
        }

        foreach ($mutationValue in @($mechanism.mutation_contracts)) {
            $mutation = [PSCustomObject]$mutationValue
            $serviceFound = $false
            foreach ($resolverIdValue in @($mechanism.resolver_ids)) {
                $resolverId = [long]$resolverIdValue
                if ($resolverMap.ContainsKey($resolverId)) {
                    $resolver = [PSCustomObject]$resolverMap[$resolverId].Manifest
                    if (Test-P2CompilerKeyArrayContains `
                        -Values $resolver.mutation_services `
                        -Key ([string]$mutation.mutation_service_key)) {
                        $serviceFound = $true
                    }
                }
            }
            if (-not $serviceFound) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $mechanismId `
                    -FieldPath "mutation_contracts.mutation_service_key" `
                    -TargetDomain "RESOLVER_MUTATION_SERVICE" `
                    -ScopeId $mechanismId `
                    -TargetId ([long]$mutation.state_op_id) `
                    -Detail ([string]$mutation.mutation_service_key)
            }
        }
    }
    return $requirementEvaluations
}

function Test-P2CompilerEventReferences {
    param(
        [Parameter(Mandatory = $true)][object]$SpecSet,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$StableIndex,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$SpecMaps,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][Collections.Generic.List[object]]$Diagnostics
    )

    $mechanismMap = $SpecMaps["MECHANISM"]
    foreach ($recordValue in @($SpecSet.EventSchemas)) {
        $record = [PSCustomObject]$recordValue
        $event = [PSCustomObject]$record.Manifest
        $eventId = [long]$event.event_id
        $kind = "EVENT_SCHEMA"
        $pass = "20_EVENT"
        foreach ($nestedEventId in @($event.nested_event_ids)) {
            $null = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $eventId -FieldPath "nested_event_ids" `
                -Domain "EVENT" -TargetId ([long]$nestedEventId) -RequireSpec
        }
        foreach ($referenceValue in @($event.rounding_stage_refs)) {
            $reference = [PSCustomObject]$referenceValue
            $mechanismId = [long]$reference.mechanism_id
            $stageId = [long]$reference.stage_id
            $mechanismValid = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $eventId `
                -FieldPath "rounding_stage_refs.mechanism_id" `
                -Domain "MECHANISM" -TargetId $mechanismId -RequireSpec
            if (-not $mechanismValid -or -not $mechanismMap.ContainsKey($mechanismId)) {
                continue
            }
            $mechanism = [PSCustomObject]$mechanismMap[$mechanismId].Manifest
            $stages = @($mechanism.formula_stages | Where-Object {
                [long]$_.stage_id -eq $stageId
            })
            if ($stages.Count -ne 1) {
                Add-P2CompilerMismatchDiagnostic `
                    -Diagnostics $Diagnostics -Code "P2C_SCOPE_MISMATCH" `
                    -Pass $pass -ArtifactKind $kind -PrimaryId $eventId `
                    -FieldPath "rounding_stage_refs.stage_id" `
                    -TargetDomain "FORMULA_STAGE" -ScopeId $mechanismId `
                    -TargetId $stageId `
                    -Detail "The formula stage is not local to the mechanism."
                continue
            }
            $stage = [PSCustomObject]$stages[0]
            if (-not (Test-P2CompilerIdArrayContains `
                -Values $mechanism.event_ids -Identifier $eventId) -or
                [long]$stage.modifier_event_id -ne $eventId) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $eventId `
                    -FieldPath "rounding_stage_refs" `
                    -TargetDomain "FORMULA_STAGE" -ScopeId $mechanismId `
                    -TargetId $stageId `
                    -Detail "The mechanism/stage does not bind this rounding event."
            }
            if ([string]$stage.rounding_mode -cne [string]$event.rounding_mode -or
                [string]$stage.rounding_schedule -cne [string]$event.rounding_schedule) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $eventId `
                    -FieldPath "rounding_mode" `
                    -TargetDomain "FORMULA_STAGE" -ScopeId $mechanismId `
                    -TargetId $stageId `
                    -Detail "Rounding mode/schedule differs from the referenced stage."
            }
        }
    }
}

function Test-P2CompilerHandlerReferences {
    param(
        [Parameter(Mandatory = $true)][object]$SpecSet,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$StableIndex,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$SpecMaps,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][Collections.Generic.List[object]]$Diagnostics
    )

    $mechanismMap = $SpecMaps["MECHANISM"]
    $eventMap = $SpecMaps["EVENT"]
    foreach ($recordValue in @($SpecSet.HandlerBindings)) {
        $record = [PSCustomObject]$recordValue
        $handler = [PSCustomObject]$record.Manifest
        $handlerId = [long]$handler.handler_id
        $eventId = [long]$handler.event_id
        $kind = "HANDLER_BINDING"
        $pass = "30_HANDLER"
        $eventValid = Test-P2CompilerStableReference `
            -Diagnostics $Diagnostics -StableIndex $StableIndex `
            -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
            -PrimaryId $handlerId -FieldPath "event_id" -Domain "EVENT" `
            -TargetId $eventId -RequireSpec
        if ($eventValid -and $eventMap.ContainsKey($eventId)) {
            $event = [PSCustomObject]$eventMap[$eventId].Manifest
            if ([string]$handler.context_type -cne [string]$event.context_type) {
                Add-P2CompilerMismatchDiagnostic `
                    -Diagnostics $Diagnostics -Code "P2C_CONTEXT_MISMATCH" `
                    -Pass $pass -ArtifactKind $kind -PrimaryId $handlerId `
                    -FieldPath "context_type" -TargetDomain "EVENT" `
                    -TargetId $eventId `
                    -Detail "Handler and event context_type must be identical."
            }
            $writableOperations = [Collections.Generic.HashSet[string]]::new(
                [StringComparer]::Ordinal
            )
            foreach ($operationValue in @($event.writable_operations)) {
                $operation = [PSCustomObject]$operationValue
                $null = $writableOperations.Add([string]$operation.operation_key)
            }
            foreach ($mutationKeyValue in @($handler.allowed_mutations)) {
                $mutationKey = [string]$mutationKeyValue
                if (-not $writableOperations.Contains($mutationKey)) {
                    Add-P2CompilerBackReferenceDiagnostic `
                        -Diagnostics $Diagnostics -Pass $pass `
                        -ArtifactKind $kind -PrimaryId $handlerId `
                        -FieldPath "allowed_mutations" `
                        -TargetDomain "EVENT_WRITABLE_OPERATION" `
                        -TargetId $eventId -Detail $mutationKey
                }
            }
        }
        foreach ($mechanismIdValue in @($handler.mechanism_ids)) {
            $mechanismId = [long]$mechanismIdValue
            $mechanismValid = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $handlerId -FieldPath "mechanism_ids" `
                -Domain "MECHANISM" -TargetId $mechanismId -RequireSpec
            if (-not $mechanismValid -or -not $mechanismMap.ContainsKey($mechanismId)) {
                continue
            }
            $mechanism = [PSCustomObject]$mechanismMap[$mechanismId].Manifest
            if (-not (Test-P2CompilerIdArrayContains `
                -Values $mechanism.handler_ids -Identifier $handlerId)) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $handlerId `
                    -FieldPath "mechanism_ids" -TargetDomain "MECHANISM" `
                    -TargetId $mechanismId `
                    -Detail "Mechanism handler_ids omits this handler."
            }
            if (-not (Test-P2CompilerIdArrayContains `
                -Values $mechanism.event_ids -Identifier $eventId)) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $handlerId `
                    -FieldPath "event_id" -TargetDomain "MECHANISM_EVENT" `
                    -ScopeId $mechanismId -TargetId $eventId `
                    -Detail "Handler event is absent from mechanism event_ids."
            }
        }
        foreach ($drawReferenceValue in @($handler.allowed_rng_draw_ids)) {
            $drawReference = [PSCustomObject]$drawReferenceValue
            $mechanismId = [long]$drawReference.mechanism_id
            $drawId = [long]$drawReference.draw_id
            if (-not (Test-P2CompilerIdArrayContains `
                -Values $handler.mechanism_ids -Identifier $mechanismId)) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $handlerId `
                    -FieldPath "allowed_rng_draw_ids.mechanism_id" `
                    -TargetDomain "MECHANISM" -TargetId $mechanismId `
                    -Detail "RNG capability belongs to an unbound mechanism."
            }
            $drawValid = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $handlerId `
                -FieldPath "allowed_rng_draw_ids.draw_id" `
                -Domain "RNG_DRAW" -ScopeId $mechanismId -TargetId $drawId
            if ($drawValid -and $mechanismMap.ContainsKey($mechanismId)) {
                $mechanism = [PSCustomObject]$mechanismMap[$mechanismId].Manifest
                $matches = @($mechanism.rng_draws | Where-Object {
                    [long]$_.draw_id -eq $drawId
                })
                if ($matches.Count -ne 1) {
                    Add-P2CompilerMismatchDiagnostic `
                        -Diagnostics $Diagnostics -Code "P2C_SCOPE_MISMATCH" `
                        -Pass $pass -ArtifactKind $kind -PrimaryId $handlerId `
                        -FieldPath "allowed_rng_draw_ids" `
                        -TargetDomain "RNG_DRAW" -ScopeId $mechanismId `
                        -TargetId $drawId `
                        -Detail "Stable draw is not declared by the mechanism spec."
                }
            }
        }
    }
}

function Test-P2CompilerResolverReferences {
    param(
        [Parameter(Mandatory = $true)][object]$SpecSet,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$StableIndex,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$SpecMaps,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][Collections.Generic.List[object]]$Diagnostics
    )

    $mechanismMap = $SpecMaps["MECHANISM"]
    $resolverMap = $SpecMaps["RESOLVER"]
    foreach ($recordValue in @($SpecSet.ResolverSpecs)) {
        $record = [PSCustomObject]$recordValue
        $resolver = [PSCustomObject]$record.Manifest
        $resolverId = [long]$resolver.resolver_id
        $kind = "RESOLVER_SPEC"
        $pass = "40_RESOLVER"
        $phaseMap = [Collections.Generic.Dictionary[long, object]]::new()
        foreach ($phaseValue in @($resolver.phases)) {
            $phase = [PSCustomObject]$phaseValue
            $phaseMap.Add([long]$phase.phase_id, $phase)
        }
        foreach ($mechanismIdValue in @($resolver.mechanism_ids)) {
            $mechanismId = [long]$mechanismIdValue
            $mechanismValid = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $resolverId -FieldPath "mechanism_ids" `
                -Domain "MECHANISM" -TargetId $mechanismId -RequireSpec
            if ($mechanismValid -and $mechanismMap.ContainsKey($mechanismId)) {
                $mechanism = [PSCustomObject]$mechanismMap[$mechanismId].Manifest
                if (-not (Test-P2CompilerIdArrayContains `
                    -Values $mechanism.resolver_ids -Identifier $resolverId)) {
                    Add-P2CompilerBackReferenceDiagnostic `
                        -Diagnostics $Diagnostics -Pass $pass `
                        -ArtifactKind $kind -PrimaryId $resolverId `
                        -FieldPath "mechanism_ids" -TargetDomain "MECHANISM" `
                        -TargetId $mechanismId `
                        -Detail "Mechanism resolver_ids omits this resolver."
                }
            }
        }
        foreach ($phaseValue in @($resolver.phases)) {
            $phase = [PSCustomObject]$phaseValue
            $phaseId = [long]$phase.phase_id
            $phaseValid = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $resolverId -FieldPath "phases.phase_id" `
                -Domain "PHASE" -ScopeId $resolverId -TargetId $phaseId
            if ($phaseValid) {
                $stablePhase = Get-P2CompilerStableEntry `
                    -StableIndex $StableIndex -Domain "PHASE" `
                    -ScopeId $resolverId -Identifier $phaseId
                if ($null -ne $stablePhase -and
                    [string]$stablePhase.debug_key -cne [string]$phase.debug_key) {
                    Add-P2CompilerMismatchDiagnostic `
                        -Diagnostics $Diagnostics `
                        -Code "P2C_CANONICAL_MISMATCH" -Pass $pass `
                        -ArtifactKind $kind -PrimaryId $resolverId `
                        -FieldPath "phases.debug_key" -TargetDomain "PHASE" `
                        -ScopeId $resolverId -TargetId $phaseId `
                        -Detail "Phase debug_key differs from the stable registry."
                }
            }
            foreach ($mechanismIdValue in @($phase.mechanism_ids)) {
                $mechanismId = [long]$mechanismIdValue
                $mechanismValid = Test-P2CompilerStableReference `
                    -Diagnostics $Diagnostics -StableIndex $StableIndex `
                    -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                    -PrimaryId $resolverId `
                    -FieldPath "phases.mechanism_ids" `
                    -Domain "MECHANISM" -TargetId $mechanismId -RequireSpec
                if ($mechanismValid -and $mechanismMap.ContainsKey($mechanismId)) {
                    $mechanism = [PSCustomObject]$mechanismMap[$mechanismId].Manifest
                    if (-not (Test-P2CompilerIdArrayContains `
                        -Values $mechanism.resolver_ids -Identifier $resolverId)) {
                        Add-P2CompilerBackReferenceDiagnostic `
                            -Diagnostics $Diagnostics -Pass $pass `
                            -ArtifactKind $kind -PrimaryId $resolverId `
                            -FieldPath "phases.mechanism_ids" `
                            -TargetDomain "MECHANISM" -ScopeId $phaseId `
                            -TargetId $mechanismId `
                            -Detail "Phase mechanism does not link this resolver."
                    }
                }
            }
        }
        foreach ($emissionValue in @($resolver.legal_event_emissions)) {
            $emission = [PSCustomObject]$emissionValue
            $eventId = [long]$emission.event_id
            $eventValid = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $resolverId `
                -FieldPath "legal_event_emissions.event_id" `
                -Domain "EVENT" -TargetId $eventId -RequireSpec
            $phaseId = [long]$emission.phase_id
            if ($eventValid -and $phaseMap.ContainsKey($phaseId)) {
                $eventOwnedByPhase = $false
                foreach ($mechanismIdValue in @(
                    $phaseMap[$phaseId].mechanism_ids
                )) {
                    $mechanismId = [long]$mechanismIdValue
                    if ($mechanismMap.ContainsKey($mechanismId) -and
                        (Test-P2CompilerIdArrayContains `
                            -Values $mechanismMap[$mechanismId].Manifest.event_ids `
                            -Identifier $eventId)) {
                        $eventOwnedByPhase = $true
                        break
                    }
                }
                if (-not $eventOwnedByPhase) {
                    Add-P2CompilerBackReferenceDiagnostic `
                        -Diagnostics $Diagnostics -Pass $pass `
                        -ArtifactKind $kind -PrimaryId $resolverId `
                        -FieldPath "legal_event_emissions.event_id" `
                        -TargetDomain "PHASE_MECHANISM_EVENT" `
                        -ScopeId $phaseId -TargetId $eventId `
                        -Detail "No mechanism in the emission phase owns this event."
                }
            }
        }
        foreach ($nestedResolverId in @($resolver.allowed_nested_resolver_ids)) {
            $null = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $resolverId `
                -FieldPath "allowed_nested_resolver_ids" `
                -Domain "RESOLVER" -TargetId ([long]$nestedResolverId) -RequireSpec
        }
        foreach ($interruptionValue in @($resolver.interruption_points)) {
            $interruption = [PSCustomObject]$interruptionValue
            $null = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $resolverId `
                -FieldPath "interruption_points.interruption_id" `
                -Domain "INTERRUPT" `
                -TargetId ([long]$interruption.interruption_id)
        }
        $pendingInputPolicy = [string]$resolver.termination_behavior.pending_input_policy
        $interruptionCount = @($resolver.interruption_points).Count
        if ($pendingInputPolicy -ceq "FORBIDDEN" -and $interruptionCount -ne 0) {
            Add-P2CompilerMismatchDiagnostic -Diagnostics $Diagnostics `
                -Code "P2C_BACKREF_MISMATCH" -Pass $pass `
                -ArtifactKind $kind -PrimaryId $resolverId `
                -FieldPath "termination_behavior.pending_input_policy" `
                -TargetDomain "INTERRUPT" -TargetId 0 `
                -Detail "FORBIDDEN pending input requires zero interruptions."
        }
        elseif ($pendingInputPolicy -ceq "DECLARED_INTERRUPTION_ONLY" -and
            $interruptionCount -eq 0) {
            Add-P2CompilerMismatchDiagnostic -Diagnostics $Diagnostics `
                -Code "P2C_BACKREF_MISMATCH" -Pass $pass `
                -ArtifactKind $kind -PrimaryId $resolverId `
                -FieldPath "termination_behavior.pending_input_policy" `
                -TargetDomain "INTERRUPT" -TargetId 0 `
                -Detail "DECLARED_INTERRUPTION_ONLY requires an interruption."
        }
    }

    foreach ($resolverId in @($resolverMap.Keys)) {
        $visited = [Collections.Generic.HashSet[long]]::new()
        $pending = [Collections.Generic.Stack[long]]::new()
        $pending.Push([long]$resolverId)
        $cycle = $false
        while ($pending.Count -gt 0 -and -not $cycle) {
            $current = $pending.Pop()
            if (-not $visited.Add($current)) {
                continue
            }
            if (-not $resolverMap.ContainsKey($current)) {
                continue
            }
            $currentResolver = [PSCustomObject]$resolverMap[$current].Manifest
            foreach ($nextValue in @($currentResolver.allowed_nested_resolver_ids)) {
                $next = [long]$nextValue
                if ($next -eq [long]$resolverId) {
                    $cycle = $true
                    break
                }
                if (-not $visited.Contains($next)) {
                    $pending.Push($next)
                }
            }
        }
        if ($cycle) {
            Add-P2CompilerMismatchDiagnostic -Diagnostics $Diagnostics `
                -Code "P2C_GRAPH_CYCLE" -Pass "45_RESOLVER_GRAPH" `
                -ArtifactKind "RESOLVER_SPEC" -PrimaryId ([long]$resolverId) `
                -FieldPath "allowed_nested_resolver_ids" `
                -TargetDomain "RESOLVER" -TargetId ([long]$resolverId) `
                -Detail "Nested resolver graph reaches its origin."
        }
    }
}

function Test-P2CompilerTestReferences {
    param(
        [Parameter(Mandatory = $true)][object]$SpecSet,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$StableIndex,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$SpecMaps,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][Collections.Generic.List[object]]$Diagnostics
    )

    $mechanismMap = $SpecMaps["MECHANISM"]
    $handlerMap = $SpecMaps["HANDLER"]
    foreach ($recordValue in @($SpecSet.TestEntries)) {
        $record = [PSCustomObject]$recordValue
        $test = [PSCustomObject]$record.Manifest
        $testId = [long]$test.test_id
        $kind = "TEST_MANIFEST_ENTRY"
        $pass = "50_TEST"
        $coveredMechanismIds = [Collections.Generic.HashSet[long]]::new()
        $requiredBranchOracles = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal
        )
        foreach ($targetValue in @($test.coverage_targets)) {
            $target = [PSCustomObject]$targetValue
            $mechanismId = [long]$target.mechanism_id
            $branchId = [long]$target.branch_id
            $null = $coveredMechanismIds.Add($mechanismId)
            $mechanismValid = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $testId `
                -FieldPath "coverage_targets.mechanism_id" `
                -Domain "MECHANISM" -TargetId $mechanismId -RequireSpec
            $branchValid = Test-P2CompilerStableReference `
                -Diagnostics $Diagnostics -StableIndex $StableIndex `
                -SpecMaps $SpecMaps -Pass $pass -ArtifactKind $kind `
                -PrimaryId $testId -FieldPath "coverage_targets.branch_id" `
                -Domain "BRANCH" -ScopeId $mechanismId -TargetId $branchId
            if ($mechanismValid -and $branchValid -and
                $mechanismMap.ContainsKey($mechanismId)) {
                $mechanism = [PSCustomObject]$mechanismMap[$mechanismId].Manifest
                $branches = @($mechanism.coverage_targets | Where-Object {
                    [long]$_.branch_id -eq $branchId
                })
                if ($branches.Count -ne 1) {
                    Add-P2CompilerMismatchDiagnostic `
                        -Diagnostics $Diagnostics `
                        -Code "P2C_TEST_BRANCH_UNKNOWN" -Pass $pass `
                        -ArtifactKind $kind -PrimaryId $testId `
                        -FieldPath "coverage_targets.branch_id" `
                        -TargetDomain "BRANCH" -ScopeId $mechanismId `
                        -TargetId $branchId `
                        -Detail "Stable branch is absent from MechanismSpec coverage_targets."
                }
                else {
                    foreach ($oracle in @($branches[0].required_oracle_kinds)) {
                        $null = $requiredBranchOracles.Add([string]$oracle)
                    }
                }
            }
        }
        foreach ($oracle in $requiredBranchOracles) {
            if (-not (Test-P2CompilerKeyArrayContains `
                -Values $test.required_oracle_kinds -Key $oracle)) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $testId `
                    -FieldPath "required_oracle_kinds" `
                    -TargetDomain "BRANCH_ORACLE" -TargetId 0 -Detail $oracle
            }
        }

        $expectedDefinitions = @(
            [pscustomobject]@{
                Property = "expected_event_ids"; Domain = "EVENT"; RequireSpec = $true
            },
            [pscustomobject]@{
                Property = "expected_handler_ids"; Domain = "HANDLER"; RequireSpec = $true
            },
            [pscustomobject]@{
                Property = "expected_state_op_ids"; Domain = "STATE_OP"; RequireSpec = $false
            },
            [pscustomobject]@{
                Property = "expected_command_ids"; Domain = "COMMAND"; RequireSpec = $false
            }
        )
        foreach ($definition in $expectedDefinitions) {
            foreach ($expectedIdValue in @($test.($definition.Property))) {
                $expectedId = [long]$expectedIdValue
                $arguments = @{
                    Diagnostics = $Diagnostics
                    StableIndex = $StableIndex
                    SpecMaps = $SpecMaps
                    Pass = $pass
                    ArtifactKind = $kind
                    PrimaryId = $testId
                    FieldPath = [string]$definition.Property
                    Domain = [string]$definition.Domain
                    TargetId = $expectedId
                }
                if ([bool]$definition.RequireSpec) {
                    $arguments.RequireSpec = $true
                }
                $referenceValid = Test-P2CompilerStableReference @arguments
                if (-not $referenceValid) {
                    continue
                }
                $belongs = $false
                foreach ($mechanismId in $coveredMechanismIds) {
                    if (-not $mechanismMap.ContainsKey([long]$mechanismId)) {
                        continue
                    }
                    $mechanism = [PSCustomObject]$mechanismMap[[long]$mechanismId].Manifest
                    $mechanismProperty = switch ([string]$definition.Domain) {
                        "EVENT" { "event_ids" }
                        "HANDLER" { "handler_ids" }
                        "STATE_OP" { "state_op_ids" }
                        "COMMAND" { "command_ids" }
                    }
                    if (Test-P2CompilerIdArrayContains `
                        -Values $mechanism.$mechanismProperty `
                        -Identifier $expectedId) {
                        $belongs = $true
                    }
                }
                if (-not $belongs) {
                    Add-P2CompilerBackReferenceDiagnostic `
                        -Diagnostics $Diagnostics -Pass $pass `
                        -ArtifactKind $kind -PrimaryId $testId `
                        -FieldPath ([string]$definition.Property) `
                        -TargetDomain ([string]$definition.Domain) `
                        -TargetId $expectedId `
                        -Detail "Expected ID belongs to no covered mechanism."
                }
            }
        }
        foreach ($handlerIdValue in @($test.expected_handler_ids)) {
            $handlerId = [long]$handlerIdValue
            if (-not $handlerMap.ContainsKey($handlerId)) {
                continue
            }
            $handler = [PSCustomObject]$handlerMap[$handlerId].Manifest
            $handlerEventId = [long]$handler.event_id
            if (-not (Test-P2CompilerIdArrayContains `
                -Values $test.expected_event_ids -Identifier $handlerEventId)) {
                Add-P2CompilerBackReferenceDiagnostic `
                    -Diagnostics $Diagnostics -Pass $pass `
                    -ArtifactKind $kind -PrimaryId $testId `
                    -FieldPath "expected_handler_ids" `
                    -TargetDomain "EVENT" -ScopeId $handlerId `
                    -TargetId $handlerEventId `
                    -Detail "Expected handler event is absent from expected_event_ids."
            }
        }
    }
}

function Test-P2CompilerCrossReferences {
    param(
        [Parameter(Mandatory = $true)][object]$SpecSet,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$StableIndex,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$SpecMaps,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[long, object]]$CueIndex
    )

    $diagnostics = [Collections.Generic.List[object]]::new()
    $requirementEvaluations = Test-P2CompilerMechanismReferences -SpecSet $SpecSet `
        -StableIndex $StableIndex -SpecMaps $SpecMaps `
        -CueIndex $CueIndex -Diagnostics $diagnostics
    Test-P2CompilerEventReferences -SpecSet $SpecSet `
        -StableIndex $StableIndex -SpecMaps $SpecMaps `
        -Diagnostics $diagnostics
    Test-P2CompilerHandlerReferences -SpecSet $SpecSet `
        -StableIndex $StableIndex -SpecMaps $SpecMaps `
        -Diagnostics $diagnostics
    Test-P2CompilerResolverReferences -SpecSet $SpecSet `
        -StableIndex $StableIndex -SpecMaps $SpecMaps `
        -Diagnostics $diagnostics
    Test-P2CompilerTestReferences -SpecSet $SpecSet `
        -StableIndex $StableIndex -SpecMaps $SpecMaps `
        -Diagnostics $diagnostics
    Assert-P2CompilerNoDiagnostics -Diagnostics $diagnostics
    return $requirementEvaluations
}

function Sort-P2CompilerRecordsById {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Records,
        [Parameter(Mandatory = $true)][string]$IdProperty
    )

    $result = [object[]]@($Records)
    for ($index = 1; $index -lt $result.Count; $index++) {
        $candidate = $result[$index]
        $candidateId = [long]$candidate.Manifest.$IdProperty
        $position = $index - 1
        while (
            $position -ge 0 -and
            [long]$result[$position].Manifest.$IdProperty -gt $candidateId
        ) {
            $result[$position + 1] = $result[$position]
            $position--
        }
        $result[$position + 1] = $candidate
    }
    return $result
}

function Sort-P2CompilerPhasesByBehaviorOrder {
    param([Parameter(Mandatory = $true)][object[]]$Phases)

    $result = [object[]]@($Phases)
    for ($index = 1; $index -lt $result.Count; $index++) {
        $candidate = $result[$index]
        $candidateOrder = [long]$candidate.phase_order
        $candidateId = [long]$candidate.phase_id
        $position = $index - 1
        while ($position -ge 0) {
            $existingOrder = [long]$result[$position].phase_order
            $existingId = [long]$result[$position].phase_id
            if ($existingOrder -lt $candidateOrder -or
                ($existingOrder -eq $candidateOrder -and
                    $existingId -le $candidateId)) {
                break
            }
            $result[$position + 1] = $result[$position]
            $position--
        }
        $result[$position + 1] = $candidate
    }
    return $result
}

function ConvertTo-P2CompilerRuntimeValue {
    param(
        [AllowNull()][object]$Value,
        [string[]]$ExcludedPropertyNames = @("debug_key")
    )

    if ($null -eq $Value -or $Value -is [bool] -or
        $Value -is [string] -or (Test-P2IntegralType $Value)) {
        return $Value
    }
    if ($Value -is [PSCustomObject] -or $Value -is [Collections.IDictionary]) {
        $result = [ordered]@{}
        if ($Value -is [Collections.IDictionary]) {
            $names = @($Value.Keys)
        }
        else {
            $names = @($Value.PSObject.Properties.Name)
        }
        foreach ($nameValue in $names) {
            $name = [string]$nameValue
            if ($name -cin $ExcludedPropertyNames) {
                continue
            }
            $propertyValue = $(if ($Value -is [Collections.IDictionary]) {
                $Value[$name]
            } else {
                $Value.$name
            })
            $result[$name] = ConvertTo-P2CompilerRuntimeValue `
                -Value $propertyValue `
                -ExcludedPropertyNames $ExcludedPropertyNames
        }
        return [pscustomobject]$result
    }
    if ($Value -is [Array] -or $Value -is [Collections.IEnumerable]) {
        $result = [Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            $result.Add((ConvertTo-P2CompilerRuntimeValue -Value $item `
                -ExcludedPropertyNames $ExcludedPropertyNames))
        }
        return ,$result.ToArray()
    }
    throw (
        "P2C_RUNTIME_VALUE_TYPE: Runtime projection cannot encode " +
        "'$($Value.GetType().FullName)'."
    )
}

function New-P2CompilerProjection {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Source,
        [Parameter(Mandatory = $true)][string[]]$Properties
    )

    $result = [ordered]@{}
    foreach ($property in $Properties) {
        if ($Source.PSObject.Properties.Name -cnotcontains $property) {
            throw "P2C_PROJECTION_FIELD: Source omits required field '$property'."
        }
        $result[$property] = ConvertTo-P2CompilerRuntimeValue `
            -Value $Source.$property
    }
    return [pscustomobject]$result
}

function New-P2CompilerMaturityResult {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Mechanism,
        [Parameter(Mandatory = $true)][object]$RequirementEvaluation
    )

    $evaluation = [PSCustomObject]$RequirementEvaluation
    $facts = [pscustomobject][ordered]@{
        identity_registered = $true
        discovery_basis_verified = $true
        specification_valid = [bool]$evaluation.SpecifiedRequirementsSatisfied
        cross_references_valid = [bool]$evaluation.SpecifiedRequirementsSatisfied
        implementation_bindings_verified = $false
        dependency_gate_passed = $false
        required_test_count = [long]$evaluation.RequiredTestCount
        executed_test_count = 0
        passed_test_count = 0
        required_oracles = [object[]]$evaluation.RequiredOracles
        passed_oracles = [object[]]@()
        coverage_observed = $false
        evidence_current = $false
        release_catalog_versioned = $false
        release_migration_complete = $false
        release_change_log_complete = $false
        release_coverage_gate_passed = $false
    }
    $result = Get-P2MaturityComputation `
        -MechanismId ([long]$Mechanism.mechanism_id) `
        -TargetMaturity ([string]$Mechanism.target_maturity) -Facts $facts
    $null = Assert-P2MaturityTarget -Computation $result
    return $result
}

function New-P2CompiledSpecManifest {
    param(
        [Parameter(Mandatory = $true)][object]$SpecSet,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[long, object]]$RequirementEvaluations
    )

    $mechanisms = [Collections.Generic.List[object]]::new()
    $mechanismRecords = @(Sort-P2CompilerRecordsById `
        -Records @($SpecSet.MechanismSpecs) -IdProperty "mechanism_id")
    foreach ($recordValue in $mechanismRecords) {
        $record = [PSCustomObject]$recordValue
        $mechanism = [PSCustomObject]$record.Manifest
        $maturity = New-P2CompilerMaturityResult -Mechanism $mechanism `
            -RequirementEvaluation $RequirementEvaluations[
                [long]$mechanism.mechanism_id
            ]
        $mechanisms.Add([pscustomobject][ordered]@{
            mechanism_id = [long]$mechanism.mechanism_id
            spec_schema_version = [long]$mechanism.spec_schema_version
            behavior_version = [long]$mechanism.behavior_version
            canonical_authoring_sha256 = [string]$record.Validation.Sha256
            target_maturity = [string]$mechanism.target_maturity
            computed_status = [string]$maturity.computed_status
        })
    }

    $events = [Collections.Generic.List[object]]::new()
    foreach ($recordValue in @(Sort-P2CompilerRecordsById `
        -Records @($SpecSet.EventSchemas) -IdProperty "event_id")) {
        $record = [PSCustomObject]$recordValue
        $manifest = [PSCustomObject]$record.Manifest
        $events.Add([pscustomobject][ordered]@{
            event_id = [long]$manifest.event_id
            schema_version = [long]$manifest.schema_version
            behavior_version = [long]$manifest.behavior_version
            canonical_authoring_sha256 = [string]$record.Validation.Sha256
        })
    }
    $handlers = [Collections.Generic.List[object]]::new()
    foreach ($recordValue in @(Sort-P2CompilerRecordsById `
        -Records @($SpecSet.HandlerBindings) -IdProperty "handler_id")) {
        $record = [PSCustomObject]$recordValue
        $manifest = [PSCustomObject]$record.Manifest
        $handlers.Add([pscustomobject][ordered]@{
            handler_id = [long]$manifest.handler_id
            schema_version = [long]$manifest.schema_version
            behavior_version = [long]$manifest.behavior_version
            canonical_authoring_sha256 = [string]$record.Validation.Sha256
        })
    }
    $resolvers = [Collections.Generic.List[object]]::new()
    foreach ($recordValue in @(Sort-P2CompilerRecordsById `
        -Records @($SpecSet.ResolverSpecs) -IdProperty "resolver_id")) {
        $record = [PSCustomObject]$recordValue
        $manifest = [PSCustomObject]$record.Manifest
        $resolvers.Add([pscustomobject][ordered]@{
            resolver_id = [long]$manifest.resolver_id
            schema_version = [long]$manifest.schema_version
            behavior_version = [long]$manifest.behavior_version
            canonical_authoring_sha256 = [string]$record.Validation.Sha256
        })
    }
    $tests = [Collections.Generic.List[object]]::new()
    foreach ($recordValue in @(Sort-P2CompilerRecordsById `
        -Records @($SpecSet.TestEntries) -IdProperty "test_id")) {
        $record = [PSCustomObject]$recordValue
        $manifest = [PSCustomObject]$record.Manifest
        $tests.Add([pscustomobject][ordered]@{
            test_id = [long]$manifest.test_id
            schema_version = [long]$manifest.schema_version
            canonical_authoring_sha256 = [string]$record.Validation.Sha256
        })
    }

    return [pscustomobject][ordered]@{
        manifest_kind = "COMPILED_SPEC_MANIFEST"
        schema_version = 1
        compiler_contract_version = $script:P2CompilerContractVersion
        stable_id_manifest_sha256 = [string]$SpecSet.StableManifestHash
        presentation_contracts_sha256 = [string]$SpecSet.PresentationManifestHash
        authoring_input_set_sha256 = [string]$SpecSet.InputSetHash
        mechanisms = $mechanisms.ToArray()
        events = $events.ToArray()
        handlers = $handlers.ToArray()
        resolvers = $resolvers.ToArray()
        tests = $tests.ToArray()
    }
}

function New-P2RuntimeRuleCatalog {
    param(
        [Parameter(Mandatory = $true)][object]$SpecSet,
        [Parameter(Mandatory = $true)][string]$SpecManifestHash
    )

    $mechanismProperties = @(
        "mechanism_id", "behavior_version", "ruleset_mode", "ruleset_ids",
        "feature_pack_ids", "entry_kind", "resolver_id", "phase_id",
        "subphase_id", "preconditions", "inputs", "read_set", "write_set",
        "history_reads", "history_writes", "counter_reads", "counter_writes",
        "ordering_key", "short_circuit", "reentry_policy", "execution_steps",
        "parameter_slots", "formula_stages", "rng_draws", "resolver_ids",
        "event_ids", "handler_ids", "state_op_ids", "command_ids",
        "presentation_cue_ids", "result_type", "mutation_contracts",
        "command_contracts", "error_contracts", "atomicity_policy"
    )
    $mechanismPlans = [Collections.Generic.List[object]]::new()
    foreach ($recordValue in @(Sort-P2CompilerRecordsById `
        -Records @($SpecSet.MechanismSpecs) -IdProperty "mechanism_id")) {
        $manifest = [PSCustomObject]$recordValue.Manifest
        $mechanismPlans.Add((New-P2CompilerProjection `
            -Source $manifest -Properties $mechanismProperties))
    }

    $eventProperties = @(
        "event_id", "behavior_version", "context_type", "readable_fields",
        "writable_operations", "aggregation_policy", "sort_key",
        "short_circuit_rule", "nested_event_ids",
        "same_instance_recall_policy", "maximum_same_instance_recalls",
        "activation_visibility", "removal_visibility", "rounding_stage_refs",
        "rounding_mode", "rounding_schedule", "trace_policy"
    )
    $eventTable = [Collections.Generic.List[object]]::new()
    foreach ($recordValue in @(Sort-P2CompilerRecordsById `
        -Records @($SpecSet.EventSchemas) -IdProperty "event_id")) {
        $manifest = [PSCustomObject]$recordValue.Manifest
        $eventTable.Add((New-P2CompilerProjection `
            -Source $manifest -Properties $eventProperties))
    }

    $handlerProperties = @(
        "handler_id", "behavior_version", "family", "event_id",
        "implementation_key", "context_type", "instance_state_kind",
        "priority_source", "allowed_queries", "allowed_mutations",
        "allowed_rng_draw_ids", "mechanism_ids"
    )
    $handlerTable = [Collections.Generic.List[object]]::new()
    foreach ($recordValue in @(Sort-P2CompilerRecordsById `
        -Records @($SpecSet.HandlerBindings) -IdProperty "handler_id")) {
        $manifest = [PSCustomObject]$recordValue.Manifest
        $handlerTable.Add((New-P2CompilerProjection `
            -Source $manifest -Properties $handlerProperties))
    }

    $resolverProperties = @(
        "resolver_id", "behavior_version", "input_type", "output_type",
        "phases", "legal_event_emissions", "allowed_nested_resolver_ids",
        "mutation_services", "interruption_points", "error_semantics",
        "termination_behavior", "mechanism_ids"
    )
    $resolverTable = [Collections.Generic.List[object]]::new()
    foreach ($recordValue in @(Sort-P2CompilerRecordsById `
        -Records @($SpecSet.ResolverSpecs) -IdProperty "resolver_id")) {
        $manifest = [PSCustomObject]$recordValue.Manifest
        $projection = New-P2CompilerProjection `
            -Source $manifest -Properties $resolverProperties
        $orderedPhases = @(Sort-P2CompilerPhasesByBehaviorOrder `
            -Phases @($manifest.phases))
        $phaseProjections = [Collections.Generic.List[object]]::new()
        foreach ($phase in $orderedPhases) {
            $phaseProjections.Add((ConvertTo-P2CompilerRuntimeValue `
                -Value $phase))
        }
        $projection.phases = $phaseProjections.ToArray()
        $resolverTable.Add($projection)
    }

    return [pscustomobject][ordered]@{
        manifest_kind = "RUNTIME_RULE_CATALOG"
        schema_version = 1
        compiler_contract_version = $script:P2CompilerContractVersion
        spec_manifest_sha256 = $SpecManifestHash
        stable_id_manifest_sha256 = [string]$SpecSet.StableManifestHash
        presentation_contracts_sha256 = [string]$SpecSet.PresentationManifestHash
        mechanism_plans = $mechanismPlans.ToArray()
        event_dispatch_table = $eventTable.ToArray()
        handler_binding_table = $handlerTable.ToArray()
        resolver_phase_table = $resolverTable.ToArray()
    }
}

# Public compilation constructs this value through Read-P2ValidatedSpecSet.
# Synthetic tests use the core directly to isolate cross-reference failures.
function Invoke-P2ValidatedSpecCompilerCore {
    param([Parameter(Mandatory = $true)][object]$SpecSet)

    foreach ($property in @(
        "StableManifest", "StableManifestHash", "PresentationManifest",
        "PresentationManifestHash", "MechanismSpecs", "EventSchemas",
        "HandlerBindings", "ResolverSpecs", "TestEntries", "InputSetHash"
    )) {
        if ($SpecSet.PSObject.Properties.Name -cnotcontains $property) {
            throw "P2C_SPEC_SET_FIELD: SpecSet omits '$property'."
        }
    }
    $stableIndex = New-P2CompilerStableIndex `
        -Manifest ([PSCustomObject]$SpecSet.StableManifest)
    $cueIndex = New-P2CompilerPresentationCueIndex `
        -Manifest ([PSCustomObject]$SpecSet.PresentationManifest)
    $specMaps = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    $specMaps.Add("MECHANISM", (New-P2CompilerRecordMap `
        -Records @($SpecSet.MechanismSpecs) -IdProperty "mechanism_id"))
    $specMaps.Add("EVENT", (New-P2CompilerRecordMap `
        -Records @($SpecSet.EventSchemas) -IdProperty "event_id"))
    $specMaps.Add("HANDLER", (New-P2CompilerRecordMap `
        -Records @($SpecSet.HandlerBindings) -IdProperty "handler_id"))
    $specMaps.Add("RESOLVER", (New-P2CompilerRecordMap `
        -Records @($SpecSet.ResolverSpecs) -IdProperty "resolver_id"))
    $specMaps.Add("TEST", (New-P2CompilerRecordMap `
        -Records @($SpecSet.TestEntries) -IdProperty "test_id"))

    $requirementEvaluations = Test-P2CompilerCrossReferences -SpecSet $SpecSet `
        -StableIndex $stableIndex -SpecMaps $specMaps -CueIndex $cueIndex
    $specManifest = New-P2CompiledSpecManifest -SpecSet $SpecSet `
        -RequirementEvaluations $requirementEvaluations
    $specJson = ConvertTo-BattleCanonicalJson -Value $specManifest
    $specHash = Get-BattleSha256Text -Text $specJson
    $runtimeManifest = New-P2RuntimeRuleCatalog -SpecSet $SpecSet `
        -SpecManifestHash $specHash
    $runtimeJson = ConvertTo-BattleCanonicalJson -Value $runtimeManifest
    $runtimeHash = Get-BattleSha256Text -Text $runtimeJson
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    return [pscustomobject][ordered]@{
        CompilerContractVersion = $script:P2CompilerContractVersion
        SpecSet = $SpecSet
        SpecManifest = $specManifest
        RuntimeManifest = $runtimeManifest
        SpecManifestJson = $specJson
        RuntimeManifestJson = $runtimeJson
        SpecManifestBytes = $utf8.GetBytes($specJson)
        RuntimeManifestBytes = $utf8.GetBytes($runtimeJson)
        SpecManifestHash = $specHash
        RuntimeManifestHash = $runtimeHash
    }
}

function Invoke-P2SpecCompiler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet("Repository", "Worktree", "Staged")]
        [string]$Mode = "Repository"
    )

    $view = New-P2RepositoryView -ProjectRoot $ProjectRoot -Mode $Mode
    $specSet = Read-P2ValidatedSpecSet -View $view
    return Invoke-P2ValidatedSpecCompilerCore -SpecSet $specSet
}

function Compile-P2SpecSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet("Repository", "Worktree", "Staged")]
        [string]$Mode = "Repository"
    )

    return Invoke-P2SpecCompiler -ProjectRoot $ProjectRoot -Mode $Mode
}

function Test-P2CompilerPathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Boundary
    )

    return $Path.StartsWith(
        $Boundary.TrimEnd('\') + '\',
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Assert-P2CompilerNoReparsePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Boundary
    )

    $current = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $stop = [IO.Path]::GetFullPath($Boundary).TrimEnd('\')
    while ($true) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "P2C_OUTPUT_REPARSE: '$current' is a reparse point."
            }
        }
        if ($current.Equals($stop, [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current -or
            -not (Test-P2CompilerPathWithin -Path $current -Boundary $stop)) {
            throw "P2C_OUTPUT_BOUNDARY: '$Path' escapes '$Boundary'."
        }
        $current = [IO.Path]::GetFullPath($parent).TrimEnd('\')
    }
}

function Resolve-P2CompilerArtifactDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Directory
    )

    if ([string]::IsNullOrWhiteSpace($Directory) -or
        $Directory -match '[\x00-\x1f\x7f"]') {
        throw "P2C_OUTPUT_PATH: Output/verify directory is invalid."
    }
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath($Directory).TrimEnd('\')
    $generatedRoot = [IO.Path]::GetFullPath((Join-Path $root `
        "new-game-project\battle\generated\battle_specs")).TrimEnd('\')
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $boundary = ""
    $locationKind = ""
    if ($fullPath.Equals($generatedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw (
            "P2C_OUTPUT_LOCATION: Output must use an immutable child " +
            "directory below new-game-project/battle/generated/battle_specs."
        )
    }
    if (Test-P2CompilerPathWithin -Path $fullPath -Boundary $generatedRoot) {
        $boundary = $root
        $locationKind = "BATTLE_GENERATED"
    }
    elseif ($fullPath.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
        (Test-P2CompilerPathWithin -Path $fullPath -Boundary $root)) {
        throw (
            "P2C_OUTPUT_LOCATION: Project-local output must be below " +
            "new-game-project/battle/generated/battle_specs."
        )
    }
    elseif (Test-P2CompilerPathWithin -Path $fullPath -Boundary $tempRoot) {
        $boundary = $tempRoot
        $locationKind = "SYSTEM_TEMP"
    }
    else {
        throw (
            "P2C_OUTPUT_LOCATION: '$fullPath' must be below the system temp " +
            "directory or new-game-project/battle/generated/battle_specs."
        )
    }
    Assert-P2CompilerNoReparsePath -Path $fullPath -Boundary $boundary
    $boundaryGuard = Open-P2RepositoryViewVerifiedHandle -Path $boundary `
        -ExpectedKind Directory -ErrorPrefix "P2C_OUTPUT"
    try {
        $boundaryFinalPath = [string]$boundaryGuard.FinalPath
    }
    finally {
        $boundaryGuard.Handle.Dispose()
    }
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        throw "P2C_OUTPUT_NOT_DIRECTORY: '$fullPath' is a file."
    }
    if ($locationKind -ceq "BATTLE_GENERATED") {
        $relative = $fullPath.Substring($root.Length + 1).Replace('\', '/')
        $generatedRelative = (
            "new-game-project/battle/generated/battle_specs"
        )
        $tracked = Invoke-P2RepositoryViewGit -Root $root `
            -Arguments ('ls-files -z -- ":(icase,literal){0}"' -f `
                $generatedRelative)
        if ($tracked.ExitCode -ne 0) {
            throw "P2C_OUTPUT_TRACKED_CHECK: Git could not inspect '$relative'."
        }
        $trackedText = ConvertFrom-P2RepositoryViewUtf8 `
            -Bytes ([byte[]]$tracked.Bytes) `
            -Context "tracked generated output paths"
        $trackedCollision = $false
        foreach ($trackedPath in $trackedText.Split([char]0)) {
            if ([string]::IsNullOrEmpty($trackedPath)) {
                continue
            }
            if ($trackedPath.Equals(
                $relative,
                [StringComparison]::OrdinalIgnoreCase
            ) -or $trackedPath.StartsWith(
                $relative.TrimEnd('/') + '/',
                [StringComparison]::OrdinalIgnoreCase
            )) {
                $trackedCollision = $true
                break
            }
        }
        if ($trackedCollision) {
            throw "P2C_OUTPUT_TRACKED: '$relative' contains tracked files."
        }
        foreach ($ignoredPath in @(
            $relative,
            "$relative/$script:P2CompilerSpecFileName",
            "$relative/$script:P2CompilerRuntimeFileName"
        )) {
            $ignored = Invoke-P2RepositoryViewGit -Root $root -Arguments (
                'check-ignore --no-index -q -- "{0}"' -f $ignoredPath
            )
            if ($ignored.ExitCode -ne 0) {
                throw (
                    "P2C_OUTPUT_NOT_IGNORED: Project-local generated path " +
                    "'$ignoredPath' is not covered by Git ignore rules."
                )
            }
        }
    }
    return [pscustomobject][ordered]@{
        FullPath = $fullPath
        Boundary = $boundary
        BoundaryFinalPath = $boundaryFinalPath
        LocationKind = $locationKind
        SpecPath = Join-Path $fullPath $script:P2CompilerSpecFileName
        RuntimePath = Join-Path $fullPath $script:P2CompilerRuntimeFileName
    }
}

function Get-P2CompilerExpectedFinalPath {
    param(
        [Parameter(Mandatory = $true)][object]$ResolvedDirectory,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $boundary = [IO.Path]::GetFullPath(
        [string]$ResolvedDirectory.Boundary
    ).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-P2CompilerPathWithin -Path $fullPath -Boundary $boundary)) {
        throw "P2C_OUTPUT_BOUNDARY: '$Path' escapes '$boundary'."
    }
    $relative = $fullPath.Substring($boundary.Length + 1)
    return [IO.Path]::GetFullPath((Join-Path `
        ([string]$ResolvedDirectory.BoundaryFinalPath) $relative)).TrimEnd('\')
}

function Test-P2CompilerByteEquality {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Left,
        [Parameter(Mandatory = $true)][byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function Read-P2CompilerLockedStreamBytes {
    param(
        [Parameter(Mandatory = $true)][IO.FileStream]$Stream,
        [ValidateRange(0, 2147483647)]
        [int]$ExpectedLength
    )

    $bytes = New-Object byte[] $ExpectedLength
    $Stream.Position = 0
    $offset = 0
    while ($offset -lt $ExpectedLength) {
        $read = $Stream.Read($bytes, $offset, $ExpectedLength - $offset)
        if ($read -le 0) {
            throw "P2C_ARTIFACT_SHORT_READ: Locked artifact ended during read."
        }
        $offset += $read
    }
    if ($Stream.ReadByte() -ne -1) {
        throw "P2C_ARTIFACT_GROWTH: Locked artifact exceeded its expected length."
    }
    return ,([byte[]]$bytes)
}

function Assert-P2CompilerExactArtifactEntries {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$ContentErrorCode,
        [Parameter(Mandatory = $true)][int]$Pass
    )

    $entryNames = [Collections.Generic.List[string]]::new(2)
    $directoryInfo = [IO.DirectoryInfo]::new($Directory)
    foreach ($entry in $directoryInfo.EnumerateFileSystemInfos()) {
        if ($entryNames.Count -ge 2) {
            throw (
                "${ContentErrorCode}: Artifact directory contains more than " +
                "two entries during stable read pass $Pass."
            )
        }
        $entryNames.Add([string]$entry.Name)
    }
    $names = $entryNames.ToArray()
    [Array]::Sort($names, [StringComparer]::Ordinal)
    if ($names.Count -ne 2 -or
        ($names -join "`n") -cne
            "runtime_manifest.json`nspec_manifest.json") {
        throw (
            "${ContentErrorCode}: Artifact directory is not an exact " +
            "two-file pair during stable read pass $Pass."
        )
    }
}

function Assert-P2CompilerStableArtifactPair {
    param(
        [Parameter(Mandatory = $true)][object]$ResolvedDirectory,
        [Parameter(Mandatory = $true)][byte[]]$ExpectedSpecBytes,
        [Parameter(Mandatory = $true)][byte[]]$ExpectedRuntimeBytes,
        [Parameter(Mandatory = $true)][string]$ContentErrorCode,
        [Parameter(Mandatory = $true)][string]$MissingErrorCode,
        [Parameter(Mandatory = $true)][string]$MismatchErrorCode
    )

    Assert-P2CompilerArtifactTargets -ResolvedDirectory $ResolvedDirectory
    foreach ($path in @(
        [string]$ResolvedDirectory.SpecPath,
        [string]$ResolvedDirectory.RuntimePath
    )) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "${MissingErrorCode}: '$path' is missing."
        }
    }

    $specStream = $null
    $runtimeStream = $null
    $specVerified = $null
    $runtimeVerified = $null
    $directoryGuard = $null
    try {
        try {
            $directoryGuard = Open-P2RepositoryViewVerifiedHandle `
                -Path ([string]$ResolvedDirectory.FullPath) `
                -ExpectedFinalPath (Get-P2CompilerExpectedFinalPath `
                    -ResolvedDirectory $ResolvedDirectory `
                    -Path ([string]$ResolvedDirectory.FullPath)) `
                -ExpectedKind Directory -ErrorPrefix "P2C_OUTPUT"
            $specVerified = Open-P2RepositoryViewVerifiedHandle `
                -Path ([string]$ResolvedDirectory.SpecPath) `
                -ExpectedFinalPath (Get-P2CompilerExpectedFinalPath `
                    -ResolvedDirectory $ResolvedDirectory `
                    -Path ([string]$ResolvedDirectory.SpecPath)) `
                -ExpectedKind File -Access Read -ErrorPrefix "P2C_OUTPUT"
            $specStream = [IO.FileStream]::new(
                [Microsoft.Win32.SafeHandles.SafeFileHandle]$specVerified.Handle,
                [IO.FileAccess]::Read
            )
            $runtimeVerified = Open-P2RepositoryViewVerifiedHandle `
                -Path ([string]$ResolvedDirectory.RuntimePath) `
                -ExpectedFinalPath (Get-P2CompilerExpectedFinalPath `
                    -ResolvedDirectory $ResolvedDirectory `
                    -Path ([string]$ResolvedDirectory.RuntimePath)) `
                -ExpectedKind File -Access Read -ErrorPrefix "P2C_OUTPUT"
            $runtimeStream = [IO.FileStream]::new(
                [Microsoft.Win32.SafeHandles.SafeFileHandle]$runtimeVerified.Handle,
                [IO.FileAccess]::Read
            )
        }
        catch {
            if ([string]$_.Exception.Message -cmatch '^P2C_OUTPUT_') {
                throw
            }
            throw (
                "${MissingErrorCode}: Artifact pair could not be locked for " +
                "a stable read. $($_.Exception.Message)"
            )
        }

        if ($specStream.Length -ne $ExpectedSpecBytes.Length -or
            $runtimeStream.Length -ne $ExpectedRuntimeBytes.Length) {
            throw (
                "${MismatchErrorCode}: Artifact lengths are not identical " +
                "to canonical compiler output."
            )
        }

        foreach ($pass in 1..2) {
            Assert-P2CompilerExactArtifactEntries `
                -Directory ([string]$ResolvedDirectory.FullPath) `
                -ContentErrorCode $ContentErrorCode -Pass $pass
            if ($pass -eq 1) {
                $specBytes = [byte[]](Read-P2CompilerLockedStreamBytes `
                    -Stream $specStream -ExpectedLength $ExpectedSpecBytes.Length)
                $runtimeBytes = [byte[]](Read-P2CompilerLockedStreamBytes `
                    -Stream $runtimeStream `
                    -ExpectedLength $ExpectedRuntimeBytes.Length)
                if (-not (Test-P2CompilerByteEquality `
                    -Left $specBytes -Right $ExpectedSpecBytes) -or
                    -not (Test-P2CompilerByteEquality `
                        -Left $runtimeBytes -Right $ExpectedRuntimeBytes)) {
                    throw (
                        "${MismatchErrorCode}: Artifact bytes are not " +
                        "byte-identical to canonical compiler output."
                    )
                }
            }
        }
    }
    finally {
        if ($null -ne $runtimeStream) {
            $runtimeStream.Dispose()
        }
        if ($null -ne $specStream) {
            $specStream.Dispose()
        }
        elseif ($null -ne $specVerified) {
            $specVerified.Handle.Dispose()
        }
        if ($null -ne $directoryGuard) {
            $directoryGuard.Handle.Dispose()
        }
    }
}

function Assert-P2CompilerArtifactTargets {
    param([Parameter(Mandatory = $true)][object]$ResolvedDirectory)

    foreach ($path in @(
        [string]$ResolvedDirectory.SpecPath,
        [string]$ResolvedDirectory.RuntimePath
    )) {
        Assert-P2CompilerNoReparsePath -Path $path `
            -Boundary ([string]$ResolvedDirectory.Boundary)
        if (Test-Path -LiteralPath $path -PathType Container) {
            throw "P2C_OUTPUT_TARGET_DIRECTORY: '$path' is a directory."
        }
    }
}

function Write-P2CompilerNewVerifiedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedFinalPath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes
    )

    $verified = $null
    $stream = $null
    try {
        $verified = New-P2RepositoryViewVerifiedFileHandle -Path $Path `
            -ExpectedFinalPath $ExpectedFinalPath -ErrorPrefix "P2C_OUTPUT"
        $stream = [IO.FileStream]::new(
            [Microsoft.Win32.SafeHandles.SafeFileHandle]$verified.Handle,
            [IO.FileAccess]::ReadWrite
        )
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
        elseif ($null -ne $verified) {
            $verified.Handle.Dispose()
        }
    }
}

# Internal boundary for already validated compiler output and synthetic I/O tests.
function Write-P2ValidatedCompiledSpecArtifactsCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Compilation,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$OutputDirectory
    )

    $resolved = Resolve-P2CompilerArtifactDirectory `
        -ProjectRoot $ProjectRoot -Directory $OutputDirectory
    if (Test-Path -LiteralPath $resolved.FullPath -PathType Container) {
        Assert-P2CompilerStableArtifactPair -ResolvedDirectory $resolved `
            -ExpectedSpecBytes ([byte[]]$Compilation.SpecManifestBytes) `
            -ExpectedRuntimeBytes ([byte[]]$Compilation.RuntimeManifestBytes) `
            -ContentErrorCode "P2C_OUTPUT_EXISTS" `
            -MissingErrorCode "P2C_OUTPUT_EXISTS" `
            -MismatchErrorCode "P2C_OUTPUT_EXISTS"
        return [pscustomobject][ordered]@{
            OutputDirectory = [string]$resolved.FullPath
            SpecPath = [string]$resolved.SpecPath
            RuntimePath = [string]$resolved.RuntimePath
            SpecManifestHash = [string]$Compilation.SpecManifestHash
            RuntimeManifestHash = [string]$Compilation.RuntimeManifestHash
        }
    }
    $parent = Split-Path -Parent ([string]$resolved.FullPath)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw (
            "P2C_OUTPUT_PARENT_MISSING: Output parent '$parent' must already " +
            "exist so it can be locked before publication."
        )
    }
    Assert-P2CompilerNoReparsePath -Path $parent `
        -Boundary ([string]$resolved.Boundary)
    $parentGuard = Open-P2RepositoryViewVerifiedHandle -Path $parent `
        -ExpectedFinalPath (Get-P2CompilerExpectedFinalPath `
            -ResolvedDirectory $resolved -Path $parent) `
        -ExpectedKind Directory -ErrorPrefix "P2C_OUTPUT"
    $stagingGuard = $null
    try {
        $token = [Guid]::NewGuid().ToString("N")
        $leaf = [IO.Path]::GetFileName([string]$resolved.FullPath)
        $stagingDirectory = Join-Path $parent ".$leaf.p2c-$token.tmp"
        if (Test-Path -LiteralPath $stagingDirectory) {
            throw "P2C_OUTPUT_TEMP_COLLISION: Compiler temporary path already exists."
        }
        $null = [IO.Directory]::CreateDirectory($stagingDirectory)
        $stagingGuard = Open-P2RepositoryViewVerifiedHandle `
            -Path $stagingDirectory `
            -ExpectedFinalPath (Get-P2CompilerExpectedFinalPath `
                -ResolvedDirectory $resolved -Path $stagingDirectory) `
            -ExpectedKind Directory -ErrorPrefix "P2C_OUTPUT"
        $specTemp = Join-Path $stagingDirectory $script:P2CompilerSpecFileName
        $runtimeTemp = Join-Path $stagingDirectory $script:P2CompilerRuntimeFileName
        Write-P2CompilerNewVerifiedFile -Path $specTemp `
            -ExpectedFinalPath (Get-P2CompilerExpectedFinalPath `
                -ResolvedDirectory $resolved -Path $specTemp) `
            -Bytes ([byte[]]$Compilation.SpecManifestBytes)
        Write-P2CompilerNewVerifiedFile -Path $runtimeTemp `
            -ExpectedFinalPath (Get-P2CompilerExpectedFinalPath `
                -ResolvedDirectory $resolved -Path $runtimeTemp) `
            -Bytes ([byte[]]$Compilation.RuntimeManifestBytes)
        $stagingResolved = [pscustomobject][ordered]@{
            FullPath = $stagingDirectory
            Boundary = [string]$resolved.Boundary
            BoundaryFinalPath = [string]$resolved.BoundaryFinalPath
            SpecPath = $specTemp
            RuntimePath = $runtimeTemp
        }
        Assert-P2CompilerStableArtifactPair `
            -ResolvedDirectory $stagingResolved `
            -ExpectedSpecBytes ([byte[]]$Compilation.SpecManifestBytes) `
            -ExpectedRuntimeBytes ([byte[]]$Compilation.RuntimeManifestBytes) `
            -ContentErrorCode "P2C_OUTPUT_TEMP_CONTENTS" `
            -MissingErrorCode "P2C_OUTPUT_TEMP_MISSING" `
            -MismatchErrorCode "P2C_OUTPUT_TEMP_MISMATCH"
        if (Test-Path -LiteralPath $resolved.FullPath) {
            throw "P2C_OUTPUT_RACE: Output directory appeared before publish."
        }
        $stagingGuard.Handle.Dispose()
        $stagingGuard = $null
        [IO.Directory]::Move(
            [string]$stagingDirectory,
            [string]$resolved.FullPath
        )
        Assert-P2CompilerStableArtifactPair -ResolvedDirectory $resolved `
            -ExpectedSpecBytes ([byte[]]$Compilation.SpecManifestBytes) `
            -ExpectedRuntimeBytes ([byte[]]$Compilation.RuntimeManifestBytes) `
            -ContentErrorCode "P2C_OUTPUT_PUBLISH_CONTENTS" `
            -MissingErrorCode "P2C_OUTPUT_PUBLISH_MISSING" `
            -MismatchErrorCode "P2C_OUTPUT_PUBLISH_MISMATCH"
        return [pscustomobject][ordered]@{
            OutputDirectory = [string]$resolved.FullPath
            SpecPath = [string]$resolved.SpecPath
            RuntimePath = [string]$resolved.RuntimePath
            SpecManifestHash = [string]$Compilation.SpecManifestHash
            RuntimeManifestHash = [string]$Compilation.RuntimeManifestHash
        }
    }
    finally {
        if ($null -ne $stagingGuard) {
            $stagingGuard.Handle.Dispose()
        }
        $parentGuard.Handle.Dispose()
    }
}

# Internal boundary for already validated compiler output and synthetic I/O tests.
function Confirm-P2ValidatedCompiledSpecArtifactsCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Compilation,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$VerifyDirectory
    )

    $resolved = Resolve-P2CompilerArtifactDirectory `
        -ProjectRoot $ProjectRoot -Directory $VerifyDirectory
    Assert-P2CompilerStableArtifactPair -ResolvedDirectory $resolved `
        -ExpectedSpecBytes ([byte[]]$Compilation.SpecManifestBytes) `
        -ExpectedRuntimeBytes ([byte[]]$Compilation.RuntimeManifestBytes) `
        -ContentErrorCode "P2C_VERIFY_CONTENTS" `
        -MissingErrorCode "P2C_VERIFY_MISSING" `
        -MismatchErrorCode "P2C_CANONICAL_MISMATCH"
    return [pscustomobject][ordered]@{
        VerifyDirectory = [string]$resolved.FullPath
        SpecManifestHash = [string]$Compilation.SpecManifestHash
        RuntimeManifestHash = [string]$Compilation.RuntimeManifestHash
    }
}

function Invoke-P2SpecCompilerAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,

        [ValidateSet("Repository", "Worktree", "Staged")]
        [string]$Mode = "Repository",

        [string]$OutputDirectory = "",

        [string]$VerifyDirectory = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($OutputDirectory) -and
        -not [string]::IsNullOrWhiteSpace($VerifyDirectory)) {
        throw "P2C_ACTION_CONFLICT: OutputDirectory and VerifyDirectory are exclusive."
    }

    # The public action owns repository capture through publication/verification;
    # callers cannot substitute a prebuilt view, spec set, or compilation object.
    $compilation = Invoke-P2SpecCompiler -ProjectRoot $ProjectRoot -Mode $Mode
    $action = "NO_WRITE"
    $artifact = $null
    if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $artifact = Write-P2ValidatedCompiledSpecArtifactsCore `
            -Compilation $compilation -ProjectRoot $ProjectRoot `
            -OutputDirectory $OutputDirectory
        $action = "WRITE"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($VerifyDirectory)) {
        $artifact = Confirm-P2ValidatedCompiledSpecArtifactsCore `
            -Compilation $compilation -ProjectRoot $ProjectRoot `
            -VerifyDirectory $VerifyDirectory
        $action = "VERIFY"
    }

    return [pscustomobject][ordered]@{
        Action = $action
        Compilation = $compilation
        Artifact = $artifact
    }
}
