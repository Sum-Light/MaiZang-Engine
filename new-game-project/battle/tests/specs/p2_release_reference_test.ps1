[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotContractRoot = (
        "D:\PokemonSV-Battle-Architecture\docs\godot"
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$supportPath = Join-Path $ProjectRoot (
    "new-game-project\battle\tools\battle_specs\compilers\" +
    "p2_release_reference_support.ps1"
)
$cliPath = Join-Path $ProjectRoot (
    "new-game-project\battle\tools\battle_specs\compilers\" +
    "validate_p2_release_references.ps1"
)
$schemaPath = Join-Path $ProjectRoot (
    "new-game-project\battle\tools\battle_specs\schemas\" +
    "compiled_release_mechanism_reference_manifest.schema.json"
)
$generatedRoot = Join-Path $ProjectRoot "new-game-project\battle\generated"
$script:checks = 0

. $supportPath

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:checks++
    if (-not $Condition) { throw $Message }
}

function Assert-ThrowsCode {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $script:checks++
    $caught = $null
    try { $null = & $Action }
    catch { $caught = $_ }
    if ($null -eq $caught) { throw "$Label did not fail." }
    $message = [string]$caught.Exception.Message
    $actual = $message.Split(':')[0]
    if ($actual -cne $Code) {
        throw "$Label failed with '$actual' instead of '$Code': $message"
    }
}

function Assert-BytesEqual {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Left,
        [Parameter(Mandatory = $true)][byte[]]$Right,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Assert-Condition ($Left.Length -eq $Right.Length) `
        "$Label byte lengths differ."
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            throw "$Label differs at byte $index."
        }
    }
    $script:checks++
}

function Test-ClosedSchemaNode {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$RootSchema,
        [AllowNull()][object]$Node,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($null -eq $Node) { return }
    if ($Node -is [Array]) {
        $items = @($Node)
        for ($index = 0; $index -lt $items.Count; $index++) {
            Test-ClosedSchemaNode $RootSchema $items[$index] "$Context[$index]"
        }
        return
    }
    if ($Node -isnot [PSCustomObject]) { return }
    $referenceProperty = $Node.PSObject.Properties['$ref']
    if ($null -ne $referenceProperty) {
        $reference = [string]$referenceProperty.Value
        Assert-Condition ($reference.StartsWith(
            '#/$defs/', [StringComparison]::Ordinal
        )) "$Context has a nonlocal schema reference."
        $name = $reference.Substring(8)
        Assert-Condition (
            $null -ne $RootSchema.'$defs'.PSObject.Properties[$name]
        ) "$Context has an unresolved schema reference '$reference'."
    }
    $typeProperty = $Node.PSObject.Properties['type']
    if ($null -ne $typeProperty -and [string]$typeProperty.Value -ceq 'object') {
        Assert-Condition (
            $Node.PSObject.Properties.Name -ccontains 'additionalProperties' -and
            $Node.additionalProperties -is [bool] -and
            -not [bool]$Node.additionalProperties
        ) "$Context is not closed."
        Assert-Condition (
            $Node.required -is [Array] -and
            $Node.properties -is [PSCustomObject]
        ) "$Context lacks a complete required/properties contract."
        $required = @($Node.required | ForEach-Object { [string]$_ })
        $properties = @($Node.properties.PSObject.Properties.Name)
        [Array]::Sort($required, [StringComparer]::Ordinal)
        [Array]::Sort($properties, [StringComparer]::Ordinal)
        Assert-Condition (
            ($required -join "`n") -ceq ($properties -join "`n")
        ) "$Context required fields do not cover its properties exactly."
    }
    if ($null -ne $typeProperty -and [string]$typeProperty.Value -ceq 'array') {
        Assert-Condition (
            $Node.PSObject.Properties.Name -ccontains 'maxItems' -and
            (Test-P2IntegralType $Node.maxItems) -and
            [long]$Node.maxItems -ge 0
        ) "$Context array is unbounded."
    }
    foreach ($property in $Node.PSObject.Properties) {
        Test-ClosedSchemaNode $RootSchema $property.Value `
            "$Context.$($property.Name)"
    }
}

function Assert-ExactPropertySet {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Value,
        [Parameter(Mandatory = $true)][PSCustomObject]$SchemaNode,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $actual = @($Value.PSObject.Properties.Name)
    $required = @($SchemaNode.required | ForEach-Object { [string]$_ })
    [Array]::Sort($actual, [StringComparer]::Ordinal)
    [Array]::Sort($required, [StringComparer]::Ordinal)
    Assert-Condition (
        ($actual -join "`n") -ceq ($required -join "`n")
    ) "$Label does not match its closed schema property set."
}

function New-CanonicalResult {
    param([Parameter(Mandatory = $true)][object]$Manifest)

    $json = ConvertTo-BattleCanonicalJson -Value $Manifest
    return [pscustomobject][ordered]@{
        Manifest = $Manifest
        ManifestJson = $json
        ManifestHash = Get-BattleSha256Text $json
    }
}

function New-SyntheticReleaseBundle {
    param(
        [ValidateSet("MATCH", "PROJECT_DECISION")]
        [string]$FirstSourceMode = "MATCH",
        [switch]$FirstFixtureMissing,
        [switch]$FirstWorkItemMissing,
        [switch]$FirstEvidenceNoncurrent,
        [switch]$FirstProjectRequirementKeysEmpty,
        [string]$FirstCompletionStatus = "VERIFIED",
        [string]$FirstTargetMaturity = "RELEASED"
    )

    $scopeId = "SYNTHETIC_RELEASE_REFERENCE_SCOPE"
    $stableHash = "2" * 64
    $presentationHash = "3" * 64
    $mechanismRecords = [Collections.Generic.List[object]]::new()
    $mechanismInputs = [Collections.Generic.List[object]]::new()
    $testRecords = [Collections.Generic.List[object]]::new()
    $testInputs = [Collections.Generic.List[object]]::new()
    $evidenceRecords = [Collections.Generic.List[object]]::new()
    $evidenceInputs = [Collections.Generic.List[object]]::new()
    $evidenceRows = [Collections.Generic.List[object]]::new()
    $mechanismEvidenceRows = [Collections.Generic.List[object]]::new()
    $auditEntries = [Collections.Generic.List[object]]::new()
    $fixtureRows = [Collections.Generic.List[object]]::new()
    $workItemRecords = [Collections.Generic.List[object]]::new()
    $workItemInputs = [Collections.Generic.List[object]]::new()

    foreach ($index in 0..1) {
        $mechanismId = 101L + $index
        $evidenceId = 201L + $index
        $fixtureId = 301L + $index
        $workItemId = "P2.SYNTHETIC_RELEASE_$([char](65 + $index))"
        $targetMaturity = if ($index -eq 0) {
            $FirstTargetMaturity
        }
        else { "RELEASED" }
        [object[]]$projectRequirementKeys = [object[]]@($workItemId)
        if ($index -eq 0 -and $FirstProjectRequirementKeysEmpty) {
            $projectRequirementKeys = [Array]::CreateInstance([object], 0)
        }
        $mechanism = [pscustomobject][ordered]@{
            mechanism_id = $mechanismId
            spec_schema_version = 1L
            behavior_version = 1L
            target_maturity = $targetMaturity
            project_requirement_keys = $projectRequirementKeys
            evidence_ids = [object[]]@($evidenceId)
            formula_stages = [object[]]@(
                [pscustomobject][ordered]@{ operation = "SYNTHETIC_RULE" }
            )
        }
        $mechanismPath = (
            "new-game-project/battle/specs/mechanisms/{0:D10}." +
            "mechanism_spec.json"
        ) -f $mechanismId
        $mechanismAuthoringHash = Get-BattleSha256Text (
            ConvertTo-BattleCanonicalJson $mechanism
        )
        $mechanismRecords.Add([pscustomobject][ordered]@{
            RelativePath = $mechanismPath
            Manifest = $mechanism
            Validation = [pscustomobject]@{Sha256 = $mechanismAuthoringHash}
        })
        $mechanismInputs.Add([pscustomobject][ordered]@{
            relative_path = $mechanismPath
            canonical_sha256 = $mechanismAuthoringHash
        })

        $test = [pscustomobject][ordered]@{
            test_id = $fixtureId
            schema_version = 1L
            test_kind = "SCENARIO"
            fixture_id = $fixtureId
            coverage_targets = [object[]]@(
                [pscustomobject][ordered]@{
                    mechanism_id = $mechanismId
                    branch_id = 1L
                }
            )
            expected_event_ids = [object[]]@()
            expected_handler_ids = [object[]]@()
            expected_state_op_ids = [object[]]@()
            expected_command_ids = [object[]]@()
            required_oracle_kinds = [object[]]@("SCENARIO")
        }
        $testPath = (
            "new-game-project/battle/specs/tests/{0:D10}." +
            "test_manifest_entry.json"
        ) -f $fixtureId
        $testHash = Get-BattleSha256Text (ConvertTo-BattleCanonicalJson $test)
        $testRecords.Add([pscustomobject][ordered]@{
            RelativePath = $testPath
            Manifest = $test
            Validation = [pscustomobject]@{Sha256 = $testHash}
        })
        $testInputs.Add([pscustomobject][ordered]@{
            relative_path = $testPath
            canonical_sha256 = $testHash
        })
        $fixtureRows.Add([pscustomobject][ordered]@{
            fixture_id = $fixtureId
            test_id = $fixtureId
            coverage_targets = $test.coverage_targets
            expected_event_ids = [object[]]@()
            expected_handler_ids = [object[]]@()
            expected_state_op_ids = [object[]]@()
            expected_command_ids = [object[]]@()
            required_oracle_kinds = [object[]]@("SCENARIO")
        })

        $fileHash = if ($index -eq 0) { "a" * 64 } else { "b" * 64 }
        $sourcePath = "programs/src/battle_logic/release_$mechanismId.cpp"
        $sourceSymbol = "synthetic_release_$mechanismId"
        $evidenceManifest = [pscustomobject][ordered]@{
            artifact_kind = "SOURCE_EVIDENCE"
            evidence_id = $evidenceId
            evidence_version = 1L
            status = "ACTIVE"
            source_audit_id = "AUDIT_" + (Get-BattleSha256Text (
                "battlelogic`tSECTION`t$sourcePath`t$sourceSymbol"
            )).Substring(0, 16).ToUpperInvariant()
            source_kind = "SOURCE_CODE"
            source_repository = "battlelogic"
            source_category = "SECTION"
            source_revision = "c" * 40
            source_relative_path = $sourcePath
            symbol_or_record_key = $sourceSymbol
            line_anchor_at_scan_time = 1L
            file_sha256 = $fileHash
            observation_summary = "Synthetic behavior evidence locator."
            behavior_claims = [object[]]@(
                [pscustomobject][ordered]@{
                    mechanism_id = $mechanismId
                    branch_id = 0L
                    spec_field_pointer = "/formula_stages/0/operation"
                    claim_summary = "Synthetic release target evidence."
                }
            )
            confidence = "HIGH"
            known_ambiguities = [object[]]@()
            review_status = "VERIFIED"
            license_boundary = "BEHAVIOR_EVIDENCE_ONLY"
        }
        $evidenceValidation = Test-P2SourceEvidence $evidenceManifest
        $evidencePath = (
            "new-game-project/battle/specs/evidence/{0:D10}." +
            "source_evidence.json"
        ) -f $evidenceId
        $evidenceRecords.Add([pscustomobject][ordered]@{
            RelativePath = $evidencePath
            Manifest = $evidenceManifest
            Validation = $evidenceValidation
        })
        $evidenceInputs.Add([pscustomobject][ordered]@{
            relative_path = $evidencePath
            canonical_sha256 = [string]$evidenceValidation.Sha256
        })
        $isCurrent = -not ($index -eq 0 -and $FirstEvidenceNoncurrent)
        $auditEntries.Add([pscustomobject][ordered]@{
            audit_id = [string]$evidenceManifest.source_audit_id
            source_repository = "battlelogic"
            source_category = "SECTION"
            source_path = $sourcePath
            source_symbol_or_edge = $sourceSymbol
            source_sha256 = $fileHash
            evidence_status = $(if ($isCurrent) {
                "CLEAN_INDEXED"
            } else { "STALE_INDEX" })
            scope_disposition = "IMPLEMENT"
            test_evidence_disposition = "NOT_APPLICABLE"
        })
        [object[]]$evidenceBlockers = [object[]]::new(0)
        if (-not $isCurrent) {
            $evidenceBlockers = [object[]]@("STALE_INDEX")
        }
        $evidenceRows.Add([pscustomobject][ordered]@{
            evidence_id = $evidenceId
            evidence_version = 1L
            status = "ACTIVE"
            canonical_authoring_sha256 = [string]$evidenceValidation.Sha256
            source_audit_id = [string]$evidenceValidation.AuditId
            evidence_current = $isCurrent
            blocker_codes = $evidenceBlockers
            mechanism_ids = [object[]]@($mechanismId)
        })
        $mechanismEvidenceRows.Add([pscustomobject][ordered]@{
            mechanism_id = $mechanismId
            required_evidence_ids = [object[]]@($evidenceId)
            joined_evidence_ids = [object[]]@($evidenceId)
            evidence_current = $isCurrent
            blocker_codes = $evidenceBlockers
        })

        if (-not ($index -eq 0 -and $FirstWorkItemMissing)) {
            $sourceReference = if (
                $index -eq 0 -and $FirstSourceMode -ceq "PROJECT_DECISION"
            ) {
                [pscustomobject][ordered]@{
                    source_kind = "PROJECT_DECISION"
                    source_repository = "MaiZangEngine"
                    relative_path = "new-game-project/battle/README.md"
                    symbol = "release_reference_policy"
                    sha256 = "d" * 64
                }
            }
            else {
                [pscustomobject][ordered]@{
                    source_kind = "SOURCE_CODE"
                    source_repository = "battlelogic"
                    relative_path = $sourcePath
                    symbol = $sourceSymbol
                    sha256 = $fileHash
                }
            }
            $contractReference = [pscustomobject][ordered]@{
                document = "synthetic-contract.md"
                section = "Synthetic release reference"
                sha256 = "e" * 64
            }
            [object[]]$fixtureIds = [object[]]::new(0)
            if (-not ($index -eq 0 -and $FirstFixtureMissing)) {
                $fixtureIds = [object[]]@($fixtureId)
            }
            $completion = if ($index -eq 0) {
                $FirstCompletionStatus
            }
            else { "VERIFIED" }
            $workItem = [pscustomobject][ordered]@{
                schema_version = 1L
                work_item_id = $workItemId
                godot_contract_refs = [object[]]@($contractReference)
                source_evidence_refs = [object[]]@($sourceReference)
                source_test_evidence_refs = [object[]]@()
                licensed_data_refs = [object[]]@()
                mechanism_ids = [object[]]@($mechanismId)
                coverage_targets = [object[]]@()
                target_godot_types = [object[]]@()
                fixture_ids = $fixtureIds
                presentation_cue_ids = [object[]]@()
                known_ambiguities = [object[]]@()
                completion_status = $completion
            }
            $workItemPath = (
                "new-game-project/battle/manifests/work_items/" +
                "SYNTHETIC_RELEASE_$([char](65 + $index)).json"
            )
            $workItemHash = Get-BattleSha256Text (
                ConvertTo-BattleCanonicalJson $workItem
            )
            $contractHash = Get-BattleSha256Text (
                ConvertTo-BattleCanonicalJson $contractReference
            )
            $workItemRecords.Add([pscustomobject][ordered]@{
                RelativePath = $workItemPath
                Manifest = $workItem
                Validation = [pscustomobject][ordered]@{
                    WorkItemId = $workItemId
                    CompletionStatus = $completion
                    ContractRefHashes = [object[]]@($contractHash)
                    Sha256 = $workItemHash
                }
            })
            $workItemInputs.Add([pscustomobject][ordered]@{
                relative_path = $workItemPath
                canonical_sha256 = $workItemHash
            })
        }
    }

    $specInputSet = [pscustomobject][ordered]@{
        schema_version = 1L
        mechanism_specs = $mechanismInputs.ToArray()
        event_schemas = [object[]]@()
        handler_bindings = [object[]]@()
        resolver_specs = [object[]]@()
        test_entries = $testInputs.ToArray()
    }
    $specInputHash = Get-BattleSha256Text (
        ConvertTo-BattleCanonicalJson $specInputSet
    )
    $specSet = [pscustomobject][ordered]@{
        StableManifestHash = $stableHash
        PresentationManifestHash = $presentationHash
        MechanismSpecs = $mechanismRecords.ToArray()
        TestEntries = $testRecords.ToArray()
        InputSet = $specInputSet
        InputSetHash = $specInputHash
    }
    $compiledMechanisms = [Collections.Generic.List[object]]::new()
    foreach ($record in @($mechanismRecords)) {
        $compiledMechanisms.Add([pscustomobject][ordered]@{
            mechanism_id = [long]$record.Manifest.mechanism_id
            spec_schema_version = [long]$record.Manifest.spec_schema_version
            behavior_version = [long]$record.Manifest.behavior_version
            canonical_authoring_sha256 = [string]$record.Validation.Sha256
            target_maturity = [string]$record.Manifest.target_maturity
            computed_status = "SPECIFIED"
        })
    }
    $compiledTests = [Collections.Generic.List[object]]::new()
    foreach ($record in @($testRecords)) {
        $compiledTests.Add([pscustomobject][ordered]@{
            test_id = [long]$record.Manifest.test_id
            schema_version = [long]$record.Manifest.schema_version
            canonical_authoring_sha256 = [string]$record.Validation.Sha256
        })
    }
    $specManifest = [pscustomobject][ordered]@{
        manifest_kind = "COMPILED_SPEC_MANIFEST"
        schema_version = 1L
        compiler_contract_version = 1L
        stable_id_manifest_sha256 = $stableHash
        presentation_contracts_sha256 = $presentationHash
        authoring_input_set_sha256 = $specInputHash
        mechanisms = $compiledMechanisms.ToArray()
        events = [object[]]@()
        handlers = [object[]]@()
        resolvers = [object[]]@()
        tests = $compiledTests.ToArray()
    }
    $specJson = ConvertTo-BattleCanonicalJson $specManifest
    $specHash = Get-BattleSha256Text $specJson
    $compilation = [pscustomobject][ordered]@{
        CompilerContractVersion = 1L
        SpecSet = $specSet
        SpecManifest = $specManifest
        SpecManifestJson = $specJson
        SpecManifestBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes(
            $specJson
        )
        SpecManifestHash = $specHash
    }
    $evidenceInputSet = [pscustomobject][ordered]@{
        schema_version = 1L
        source_evidence = $evidenceInputs.ToArray()
    }
    $evidenceInputHash = Get-BattleSha256Text (
        ConvertTo-BattleCanonicalJson $evidenceInputSet
    )
    $evidenceSet = [pscustomobject][ordered]@{
        Records = $evidenceRecords.ToArray()
        InputSet = $evidenceInputSet
        InputSetHash = $evidenceInputHash
    }
    $auditManifestHash = Get-BattleSha256Text "synthetic audit manifest"
    $seal = [pscustomobject][ordered]@{
        scope_id = $scopeId
        source_audit_manifest_sha256 = $auditManifestHash
    }
    $repositories = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    $repositories.Add("battlelogic", [pscustomobject][ordered]@{
        commit = "c" * 40
        head_tree = "d" * 40
    })
    $repositories.Add("pokelib", [pscustomobject][ordered]@{
        commit = "e" * 40
        head_tree = "f" * 40
    })
    $governance = [pscustomobject][ordered]@{
        Seal = $seal
        SealHash = Get-BattleSha256Text (
            ConvertTo-BattleCanonicalJson $seal
        )
        Repositories = $repositories
    }
    $auditById = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($entry in @($auditEntries)) {
        $auditById.Add([string]$entry.audit_id, $entry)
    }
    $auditValidation = [pscustomobject][ordered]@{ AuditById = $auditById }
    $evidenceJoin = Invoke-P2ValidatedSourceEvidenceJoinCore `
        -Compilation $compilation -EvidenceSet $evidenceSet `
        -Governance $governance -AuditValidation $auditValidation
    $auditSealHash = [string]$governance.SealHash

    $fixtureManifest = [pscustomobject][ordered]@{
        artifact_kind = "COMPILED_FIXTURE_REQUIREMENT_MANIFEST"
        schema_version = 1L
        preflight_contract_version = 1L
        source_spec_compiler_contract_version = 1L
        setup_compiler_status = "UNAVAILABLE_P7"
        spec_manifest_sha256 = $specHash
        stable_id_manifest_sha256 = $stableHash
        fixture_requirements = $fixtureRows.ToArray()
    }
    $fixtureResult = New-CanonicalResult $fixtureManifest
    $fixtureResult | Add-Member -NotePropertyName Compilation `
        -NotePropertyValue $compilation
    $fixtureResult | Add-Member -NotePropertyName SpecSet `
        -NotePropertyValue $specSet
    $workItemInputSet = [pscustomobject][ordered]@{
        schema_version = 1L
        implementation_work_items = $workItemInputs.ToArray()
    }
    $workItemSet = [pscustomobject][ordered]@{
        Records = $workItemRecords.ToArray()
        InputSet = $workItemInputSet
        InputSetHash = Get-BattleSha256Text (
            ConvertTo-BattleCanonicalJson $workItemInputSet
        )
    }
    return [pscustomobject][ordered]@{
        Compilation = $compilation
        SpecSet = $specSet
        EvidenceJoin = $evidenceJoin
        FixtureResult = $fixtureResult
        WorkItemSet = $workItemSet
        ScopeId = $scopeId
        AuditSealHash = $auditSealHash
        AuditManifestHash = $auditManifestHash
    }
}

function Invoke-SyntheticBundle {
    param([Parameter(Mandatory = $true)][object]$Bundle)

    return Invoke-P2ValidatedReleaseReferenceCore `
        -Compilation $Bundle.Compilation `
        -EvidenceJoin $Bundle.EvidenceJoin `
        -FixtureResult $Bundle.FixtureResult `
        -WorkItemSet $Bundle.WorkItemSet `
        -ScopeId $Bundle.ScopeId `
        -AuditSealHash $Bundle.AuditSealHash `
        -AuditManifestHash $Bundle.AuditManifestHash
}

function Update-CanonicalResult {
    param([Parameter(Mandatory = $true)][object]$Result)

    $Result.ManifestJson = ConvertTo-BattleCanonicalJson $Result.Manifest
    $Result.ManifestHash = Get-BattleSha256Text $Result.ManifestJson
}

function Add-UnmatchedRequiredEvidence {
    param([Parameter(Mandatory = $true)][object]$Bundle)

    $firstMechanism = $Bundle.SpecSet.MechanismSpecs[0]
    $firstMechanism.Manifest.evidence_ids = [object[]]@(201L, 202L)
    $firstMechanismHash = Get-BattleSha256Text (
        ConvertTo-BattleCanonicalJson $firstMechanism.Manifest
    )
    $firstMechanism.Validation.Sha256 = $firstMechanismHash
    $Bundle.SpecSet.InputSet.mechanism_specs[0].canonical_sha256 = `
        $firstMechanismHash
    $Bundle.SpecSet.InputSetHash = Get-BattleSha256Text (
        ConvertTo-BattleCanonicalJson $Bundle.SpecSet.InputSet
    )

    $secondEvidence = $Bundle.EvidenceJoin.EvidenceSet.Records[1]
    $existingClaim = $secondEvidence.Manifest.behavior_claims[0]
    $secondEvidence.Manifest.behavior_claims = [object[]]@(
        [pscustomobject][ordered]@{
            mechanism_id = 101L
            branch_id = 0L
            spec_field_pointer = "/formula_stages/0/operation"
            claim_summary = "Synthetic additional required evidence."
        },
        $existingClaim
    )
    $secondEvidence.Validation = Test-P2SourceEvidence `
        -Evidence $secondEvidence.Manifest
    $Bundle.EvidenceJoin.EvidenceSet.InputSet.source_evidence[1].canonical_sha256 = `
        [string]$secondEvidence.Validation.Sha256
    $evidenceInputHash = Get-BattleSha256Text (
        ConvertTo-BattleCanonicalJson $Bundle.EvidenceJoin.EvidenceSet.InputSet
    )
    $Bundle.EvidenceJoin.EvidenceSet.InputSetHash = $evidenceInputHash

    $Bundle.Compilation.SpecManifest.authoring_input_set_sha256 = `
        $Bundle.SpecSet.InputSetHash
    $Bundle.Compilation.SpecManifest.mechanisms[0].canonical_authoring_sha256 = `
        $firstMechanismHash
    $specJson = ConvertTo-BattleCanonicalJson $Bundle.Compilation.SpecManifest
    $Bundle.Compilation.SpecManifestJson = $specJson
    $Bundle.Compilation.SpecManifestBytes = `
        [Text.UTF8Encoding]::new($false, $true).GetBytes($specJson)
    $Bundle.Compilation.SpecManifestHash = Get-BattleSha256Text $specJson
    $Bundle.FixtureResult.Manifest.spec_manifest_sha256 = `
        $Bundle.Compilation.SpecManifestHash
    Update-CanonicalResult $Bundle.FixtureResult
    $Bundle.EvidenceJoin = Invoke-P2ValidatedSourceEvidenceJoinCore `
        -Compilation $Bundle.Compilation `
        -EvidenceSet $Bundle.EvidenceJoin.EvidenceSet `
        -Governance $Bundle.EvidenceJoin.Governance `
        -AuditValidation $Bundle.EvidenceJoin.AuditValidation
    return $Bundle
}

function Update-SyntheticWorkItemRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Bundle,
        [Parameter(Mandatory = $true)][int]$Index
    )

    $record = $Bundle.WorkItemSet.Records[$Index]
    $record.Validation.Sha256 = Get-BattleSha256Text (
        ConvertTo-BattleCanonicalJson $record.Manifest
    )
    $record.Validation.CompletionStatus = `
        [string]$record.Manifest.completion_status
    foreach ($input in @(
        $Bundle.WorkItemSet.InputSet.implementation_work_items
    )) {
        if ([string]$input.relative_path -ceq [string]$record.RelativePath) {
            $input.canonical_sha256 = [string]$record.Validation.Sha256
        }
    }
    $Bundle.WorkItemSet.InputSetHash = Get-BattleSha256Text (
        ConvertTo-BattleCanonicalJson $Bundle.WorkItemSet.InputSet
    )
    return $Bundle
}

function Add-UnreviewedBoundWorkItem {
    param([Parameter(Mandatory = $true)][object]$Bundle)

    $source = $Bundle.WorkItemSet.Records[0]
    $manifest = ConvertFrom-BattleStrictJson `
        -Text (ConvertTo-BattleCanonicalJson $source.Manifest) `
        -Label "synthetic extra work item"
    $manifest.work_item_id = "P2.SYNTHETIC_RELEASE_EXTRA"
    $manifest.completion_status = "IMPLEMENTED"
    $relativePath = (
        "new-game-project/battle/manifests/work_items/" +
        "SYNTHETIC_RELEASE_EXTRA.json"
    )
    $hash = Get-BattleSha256Text (ConvertTo-BattleCanonicalJson $manifest)
    $contractHashes = [Collections.Generic.List[string]]::new()
    foreach ($reference in @($manifest.godot_contract_refs)) {
        $contractHashes.Add((Get-BattleSha256Text (
            ConvertTo-BattleCanonicalJson $reference
        )))
    }
    $validation = [pscustomobject][ordered]@{
        WorkItemId = [string]$manifest.work_item_id
        CompletionStatus = [string]$manifest.completion_status
        ContractRefHashes = Get-P2FSortedStringArray $contractHashes.ToArray()
        Sha256 = $hash
    }
    $Bundle.WorkItemSet.Records = [object[]]@(
        @($Bundle.WorkItemSet.Records) +
        [pscustomobject][ordered]@{
            RelativePath = $relativePath
            Manifest = $manifest
            Validation = $validation
        }
    )
    $Bundle.WorkItemSet.InputSet.implementation_work_items = [object[]]@(
        @($Bundle.WorkItemSet.InputSet.implementation_work_items) +
        [pscustomobject][ordered]@{
            relative_path = $relativePath
            canonical_sha256 = $hash
        }
    )
    $Bundle.WorkItemSet.InputSetHash = Get-BattleSha256Text (
        ConvertTo-BattleCanonicalJson $Bundle.WorkItemSet.InputSet
    )
    return $Bundle
}

$schemaText = [IO.File]::ReadAllText($schemaPath, [Text.Encoding]::UTF8)
$schema = ConvertFrom-BattleStrictJson -Text $schemaText `
    -Label "release reference output schema"
Test-ClosedSchemaNode -RootSchema $schema -Node $schema -Context "schema"
Assert-Condition (
    [string]$schema.'$comment' -cmatch 'evaluates and reports' -and
    [string]$schema.'$comment' -cnotmatch '\bproves\b'
) "Release-reference schema overclaimed that every reported triple is complete."
Assert-Condition (
    @($schema.'$defs'.blocker_code.enum).Count -eq 7 -and
    "EXTERNAL_SOURCE_EVIDENCE_REF_INCOMPLETE" -cin
        @($schema.'$defs'.blocker_code.enum)
) "Release-reference blocker vocabulary is not closed and complete."
Assert-Condition (
    [long]$schema.'$defs'.sha256_set.maxItems -eq 262144L
) "Contract-hash output capacity does not match 4096 work items x 64 refs."
Assert-Condition (
    @($schema.'$defs'.release_mechanism.allOf).Count -ge 9
) "Release-reference schema omits presence/triple consistency constraints."

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$sectionRoot = Join-Path $tempParent (
    "maizang-p2f-section-{0}" -f [guid]::NewGuid().ToString("N")
)
try {
    $null = New-Item -ItemType Directory -Path $sectionRoot
    $contractText = @'
# Synthetic Contract

## Synthetic release reference

## C#

### Closed heading ###

```markdown
## Fenced false heading

Fenced false Setext heading
---------------------------
```

<!--
## Comment false heading
-->
<div>
## HTML block false heading
</div>

- Fake list item
----------------

> Fake quote
------------

First multiline paragraph line
Second multiline paragraph line
-------------------------------

- Nested fence
  ```markdown
  ## Fake nested-fence heading
  ```

Setext release reference
------------------------
'@
    $contractBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes(
        $contractText
    )
    [IO.File]::WriteAllBytes(
        (Join-Path $sectionRoot "synthetic-contract.md"),
        $contractBytes
    )
    $headings = Get-P2FMarkdownHeadings -Bytes $contractBytes `
        -Document "synthetic-contract.md"
    Assert-Condition (
        $headings.Contains("Synthetic release reference") -and
        -not $headings.Contains("Setext release reference")
    ) "Contract heading policy did not enforce top-level ATX syntax."
    Assert-Condition (
        $headings.Contains("C#") -and
        $headings.Contains("Closed heading") -and
        -not $headings.Contains("Closed heading ###")
    ) "Markdown ATX closing markers corrupted the contract heading."
    Assert-Condition (
        -not $headings.Contains("Fenced false heading") -and
        -not $headings.Contains("Fenced false Setext heading")
    ) "Fenced Markdown content was accepted as a contract heading."
    Assert-Condition (
        -not $headings.Contains("Comment false heading") -and
        -not $headings.Contains("HTML block false heading")
    ) "HTML block content was accepted as a contract heading."
    Assert-Condition (
        -not $headings.Contains("- Fake list item") -and
        -not $headings.Contains("> Fake quote") -and
        -not $headings.Contains("Second multiline paragraph line") -and
        -not $headings.Contains("Fake nested-fence heading")
    ) "Markdown container or multiline content was accepted as a heading."

    $sectionBundle = New-SyntheticReleaseBundle
    $sectionWorkItem = $sectionBundle.WorkItemSet.Records[0].Manifest
    $sectionWorkItem.godot_contract_refs[0].sha256 = `
        Get-P2FSha256Bytes $contractBytes
    $contractCache = `
        [Collections.Generic.Dictionary[string, object]]::new(
            [StringComparer]::Ordinal
        )
    $sectionValidation = Test-P2FWorkItem -WorkItem $sectionWorkItem `
        -ContractRoot $sectionRoot -ContractHashCache $contractCache
    Assert-Condition (
        [string]$sectionValidation.WorkItemId -ceq
            [string]$sectionWorkItem.work_item_id
    ) "Bound work item rejected an existing Markdown contract heading."
    $sectionWorkItem.godot_contract_refs[0].section = "Missing heading"
    Assert-ThrowsCode {
        Test-P2FWorkItem -WorkItem $sectionWorkItem `
            -ContractRoot $sectionRoot -ContractHashCache $contractCache
    } "P2F_GODOT_CONTRACT_SECTION_MISSING" `
        "missing bound-work-item contract heading"
}
finally {
    $resolvedSectionRoot = [IO.Path]::GetFullPath($sectionRoot)
    if (-not $resolvedSectionRoot.StartsWith(
        $tempParent + '\', [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to clean unsafe P2F section test path."
    }
    if (Test-Path -LiteralPath $resolvedSectionRoot) {
        Remove-Item -LiteralPath $resolvedSectionRoot -Recurse -Force
    }
}

$beforeGenerated = @(
    if (Test-Path -LiteralPath $generatedRoot -PathType Container) {
        Get-ChildItem -LiteralPath $generatedRoot -Recurse -Force -File |
            ForEach-Object { $_.FullName }
    }
)
$specBefore = Invoke-P2SpecCompiler -ProjectRoot $ProjectRoot -Mode Repository
$todo9WorkItemPath = Join-Path $ProjectRoot (
    "new-game-project\battle\manifests\work_items\" +
    "P2_RELEASE_REFERENCE_TRIPLE.json"
)
$todo9WorkItem = ConvertFrom-P2FWorkItemBytes `
    -Bytes ([IO.File]::ReadAllBytes($todo9WorkItemPath)) `
    -Context "P2 release-reference work item"
Assert-Condition (
    [string]$todo9WorkItem.work_item_id -ceq "P2.RELEASE_REFERENCE_TRIPLE"
) "Todo 9 heading regression loaded the wrong work item."
foreach ($contractReference in @($todo9WorkItem.godot_contract_refs)) {
    $document = [string]$contractReference.document
    $contractBytes = Read-P2FContractBytes `
        -ContractRoot $GodotContractRoot -Document $document
    $contractHeadings = Get-P2FMarkdownHeadings `
        -Bytes $contractBytes -Document $document
    Assert-Condition (
        $contractHeadings.Contains([string]$contractReference.section)
    ) "Todo 9 work item names a missing top-level ATX heading in '$document'."
}
$repositoryOne = Validate-P2ReleaseMechanismReferences `
    -ProjectRoot $ProjectRoot -Mode Repository `
    -GodotContractRoot $GodotContractRoot
$repositoryTwo = Validate-P2ReleaseMechanismReferences `
    -ProjectRoot $ProjectRoot -Mode Repository `
    -GodotContractRoot $GodotContractRoot
$portableRepository = Validate-P2ReleaseMechanismReferences `
    -ProjectRoot $ProjectRoot -Mode Repository
$publicResultProperties = @($repositoryOne.PSObject.Properties.Name)
$expectedPublicResultProperties = @(
    "BlockedMechanismCount", "Manifest", "ManifestBytes", "ManifestHash",
    "ManifestJson", "ReferenceTripleCount", "ReleaseMechanismCount"
)
[Array]::Sort($publicResultProperties, [StringComparer]::Ordinal)
[Array]::Sort($expectedPublicResultProperties, [StringComparer]::Ordinal)
Assert-Condition (
    ($publicResultProperties -join "`n") -ceq
        ($expectedPublicResultProperties -join "`n")
) "Public release-reference validation leaked internal compiler inputs."
Assert-BytesEqual $repositoryOne.ManifestBytes $repositoryTwo.ManifestBytes `
    "empty Repository release-reference output"
Assert-BytesEqual $repositoryOne.ManifestBytes `
    $portableRepository.ManifestBytes `
    "portable reference-only and explicit contract-byte output"
Assert-Condition (
    [string]$repositoryOne.ManifestHash -ceq
        "bd30940a4c04452238c6f410df79da14a4755754ae5585a63c07fecd5de15439"
) "Current empty release-reference manifest hash changed."
$specAfter = Invoke-P2SpecCompiler -ProjectRoot $ProjectRoot -Mode Repository
Assert-BytesEqual $specBefore.SpecManifestBytes $specAfter.SpecManifestBytes `
    "spec manifest before and after release-reference validation"
Assert-BytesEqual $specBefore.RuntimeManifestBytes `
    $specAfter.RuntimeManifestBytes `
    "runtime manifest before and after release-reference validation"
Assert-Condition (
    [string]$specBefore.SpecManifestHash -ceq
        "9f35401d489d6a0e55c2514fe8325850dc353c8b907f919fcd30dccfd6a87b57" -and
    [string]$specBefore.RuntimeManifestHash -ceq
        "5d3971516b957d9f58986eba6d5b8e741dc8da8b609c234ffb8b7222e00b9d39"
) "Release-reference validation changed the empty spec/runtime identity."
$strictRepositoryManifest = ConvertFrom-BattleStrictJson `
    -Text $repositoryOne.ManifestJson -Label "release-reference manifest"
Assert-ExactPropertySet $strictRepositoryManifest $schema `
    "release-reference root"
Assert-ExactPropertySet $strictRepositoryManifest.counts `
    $schema.'$defs'.counts "release-reference counts"
$worktreeResult = Validate-P2ReleaseMechanismReferences `
    -ProjectRoot $ProjectRoot -Mode Worktree `
    -GodotContractRoot $GodotContractRoot
Assert-Condition ($worktreeResult.ReleaseMechanismCount -eq 0) `
    "Worktree authoring unexpectedly contains a release mechanism."
Assert-Condition (
    $worktreeResult.Manifest.validation_scope -ceq "STATIC_REFERENCE_TRIPLE_ONLY"
) "Worktree validation changed the release-reference scope."
Assert-Condition ($repositoryOne.ReleaseMechanismCount -eq 0) `
    "Public authoring unexpectedly contains a release mechanism."
Assert-Condition ($repositoryOne.ReferenceTripleCount -eq 0) `
    "Empty authoring unexpectedly contains a reference triple."
Assert-Condition (
    $repositoryOne.Manifest.validation_scope -ceq "STATIC_REFERENCE_TRIPLE_ONLY"
) "Release overlay did not retain its static-only scope."
Assert-Condition (
    $repositoryOne.Manifest.setup_compiler_status -ceq "UNAVAILABLE_P7"
) "Release overlay concealed the unavailable P7 setup compiler."
Assert-Condition (
    $repositoryOne.Manifest.PSObject.Properties.Name -cnotcontains "runtime" -and
    $repositoryOne.Manifest.PSObject.Properties.Name -cnotcontains "computed_status"
) "Release overlay leaked runtime/maturity state."

$null = Assert-P2FReleaseContractRoot -SpecSet $specBefore.SpecSet
$positiveBundle = New-SyntheticReleaseBundle
Assert-ThrowsCode {
    Assert-P2FReleaseContractRoot -SpecSet $positiveBundle.SpecSet
} "P2F_GODOT_CONTRACT_ROOT_REQUIRED" `
    "nonempty release set without contract root"
$null = Assert-P2FReleaseContractRoot -SpecSet $positiveBundle.SpecSet `
    -GodotContractRoot $GodotContractRoot
$positive = Invoke-SyntheticBundle $positiveBundle
Assert-Condition ($positive.ReleaseMechanismCount -eq 2) `
    "Synthetic release set count is wrong."
Assert-Condition ($positive.ReferenceTripleCount -eq 2) `
    "Synthetic release triples did not close."
foreach ($row in @($positive.Manifest.release_mechanisms)) {
    Assert-ExactPropertySet ([PSCustomObject]$row) `
        $schema.'$defs'.release_mechanism `
        "synthetic release-reference row"
}
Assert-Condition (
    [long]$positive.Manifest.release_mechanisms[0].mechanism_id -eq 101 -and
    [long]$positive.Manifest.release_mechanisms[1].mechanism_id -eq 102
) "Release mechanisms are not ordered by stable ID."
foreach ($row in @($positive.Manifest.release_mechanisms)) {
    Assert-Condition ([bool]$row.reference_triple_present) `
        "Complete synthetic mechanism lacks a triple."
    Assert-Condition ([bool]$row.source_evidence_current) `
        "Current synthetic evidence was marked noncurrent."
    Assert-Condition (
        @($row.blocker_codes).Count -eq 1 -and
        [string]$row.blocker_codes[0] -ceq "SETUP_COMPILER_UNAVAILABLE_P7"
    ) "P7 preflight blocker was not explicit and isolated."
    Assert-Condition (
        $row.PSObject.Properties.Name -cnotcontains "executed" -and
        $row.PSObject.Properties.Name -cnotcontains "passed" -and
        $row.PSObject.Properties.Name -cnotcontains "coverage"
    ) "Release reference row claimed execution or coverage."
}

$nonRelease = Invoke-SyntheticBundle (
    New-SyntheticReleaseBundle -FirstTargetMaturity "SPECIFIED"
)
Assert-Condition ($nonRelease.ReleaseMechanismCount -eq 1) `
    "Non-RELEASED target entered the release set."
Assert-Condition (
    [long]$nonRelease.Manifest.release_mechanisms[0].mechanism_id -eq 102
) "Release selection used generated status instead of target_maturity."

$missingWorkItem = Invoke-SyntheticBundle (
    New-SyntheticReleaseBundle -FirstWorkItemMissing
)
$missingWorkItemRow = $missingWorkItem.Manifest.release_mechanisms[0]
foreach ($code in @(
    "GODOT_CONTRACT_REF_MISSING",
    "EXTERNAL_SOURCE_EVIDENCE_REF_MISSING",
    "SCENARIO_FIXTURE_REF_MISSING"
)) {
    Assert-Condition ($code -cin @($missingWorkItemRow.blocker_codes)) `
        "Missing work item did not expose blocker $code."
}
Assert-Condition (-not [bool]$missingWorkItemRow.reference_triple_present) `
    "Missing work item produced a forged reference triple."
Assert-ThrowsCode {
    Assert-P2FReleaseReferenceClosure -Result $missingWorkItem
} "P2F_RELEASE_REFERENCE_CLOSURE_FAILED" `
    "public missing-triple policy"

$projectDecision = Invoke-SyntheticBundle (
    New-SyntheticReleaseBundle -FirstSourceMode "PROJECT_DECISION"
)
$projectDecisionRow = $projectDecision.Manifest.release_mechanisms[0]
Assert-Condition (
    -not [bool]$projectDecisionRow.external_source_evidence_ref_present -and
    "EXTERNAL_SOURCE_EVIDENCE_REF_MISSING" -cin
        @($projectDecisionRow.blocker_codes)
) "Project-decision provenance replaced actual external evidence."

$missingFixture = Invoke-SyntheticBundle (
    New-SyntheticReleaseBundle -FirstFixtureMissing
)
$missingFixtureRow = $missingFixture.Manifest.release_mechanisms[0]
Assert-Condition (
    -not [bool]$missingFixtureRow.scenario_fixture_ref_present -and
    "SCENARIO_FIXTURE_REF_MISSING" -cin @($missingFixtureRow.blocker_codes)
) "Work item without fixture linkage produced a fixture reference."

$partialEvidence = Invoke-SyntheticBundle (
    Add-UnmatchedRequiredEvidence (New-SyntheticReleaseBundle)
)
$partialEvidenceRow = $partialEvidence.Manifest.release_mechanisms[0]
Assert-Condition (
    @($partialEvidenceRow.external_evidence_ids).Count -eq 1 -and
    [long]$partialEvidenceRow.external_evidence_ids[0] -eq 201L
) "Partial evidence diagnostics did not retain the exact matched subset."
Assert-Condition (
    -not [bool]$partialEvidenceRow.external_source_evidence_ref_present -and
    -not [bool]$partialEvidenceRow.source_evidence_current -and
    "EXTERNAL_SOURCE_EVIDENCE_REF_INCOMPLETE" -cin
        @($partialEvidenceRow.blocker_codes)
) (
    "A partial required evidence set closed the external-evidence leg: " +
    "present=$($partialEvidenceRow.external_source_evidence_ref_present) " +
    "current=$($partialEvidenceRow.source_evidence_current) " +
    "blockers=$(@($partialEvidenceRow.blocker_codes) -join ',')."
)
Assert-Condition (-not [bool]$partialEvidenceRow.reference_triple_present) `
    "A partial required evidence set produced a complete reference triple."

$noncurrent = Invoke-SyntheticBundle (
    New-SyntheticReleaseBundle -FirstEvidenceNoncurrent
)
$noncurrentRow = $noncurrent.Manifest.release_mechanisms[0]
Assert-Condition ([bool]$noncurrentRow.external_source_evidence_ref_present) `
    "Noncurrent evidence was incorrectly treated as a missing reference."
Assert-Condition (-not [bool]$noncurrentRow.source_evidence_current) `
    "Noncurrent evidence was marked current."
Assert-Condition (
    "EXTERNAL_SOURCE_EVIDENCE_NONCURRENT" -cin @($noncurrentRow.blocker_codes)
) "Noncurrent evidence blocker is missing."
$null = Assert-P2FReleaseReferenceClosure -Result $noncurrent

$unreviewed = Invoke-SyntheticBundle (
    New-SyntheticReleaseBundle -FirstCompletionStatus "IMPLEMENTED"
)
Assert-Condition (
    "GODOT_CONTRACT_REVIEW_INCOMPLETE" -cin
        @($unreviewed.Manifest.release_mechanisms[0].blocker_codes)
) "Unreviewed contract work item did not remain blocked."

$mixedReview = Invoke-SyntheticBundle (
    Add-UnreviewedBoundWorkItem (New-SyntheticReleaseBundle)
)
$mixedReviewRow = $mixedReview.Manifest.release_mechanisms[0]
Assert-Condition ([bool]$mixedReviewRow.reference_triple_present) `
    "An additional work item removed an otherwise complete reference triple."
Assert-Condition (
    @($mixedReviewRow.contract_work_item_ids).Count -eq 2 -and
    "P2.SYNTHETIC_RELEASE_A" -cin
        @($mixedReviewRow.contract_work_item_ids) -and
    "P2.SYNTHETIC_RELEASE_EXTRA" -cin
        @($mixedReviewRow.contract_work_item_ids)
) "Mixed-review diagnostics omitted a bound work item."
Assert-Condition (
    "GODOT_CONTRACT_REVIEW_INCOMPLETE" -cin
        @($mixedReviewRow.blocker_codes)
) "One VERIFIED work item concealed another unreviewed bound work item."
$null = Assert-P2FReleaseReferenceClosure -Result $mixedReview

$identityCases = @(
    [pscustomobject]@{ Field = "source_kind"; Value = "SOURCE_SCHEMA" },
    [pscustomobject]@{ Field = "source_repository"; Value = "pokelib" },
    [pscustomobject]@{
        Field = "relative_path"
        Value = "programs/src/battle_logic/different.cpp"
    },
    [pscustomobject]@{ Field = "symbol"; Value = "different_symbol" },
    [pscustomobject]@{ Field = "sha256"; Value = "9" * 64 }
)
foreach ($identityCase in $identityCases) {
    $identityBundle = New-SyntheticReleaseBundle
    $identityBundle.WorkItemSet.Records[0].Manifest.source_evidence_refs[0].(
        [string]$identityCase.Field
    ) = [string]$identityCase.Value
    $null = Update-SyntheticWorkItemRecord -Bundle $identityBundle -Index 0
    $identityResult = Invoke-SyntheticBundle $identityBundle
    $identityRow = $identityResult.Manifest.release_mechanisms[0]
    Assert-Condition (
        @($identityRow.external_evidence_ids).Count -eq 0
    ) "Identity mismatch '$($identityCase.Field)' retained an evidence ID."
    Assert-Condition (
        -not [bool]$identityRow.external_source_evidence_ref_present
    ) "Identity mismatch '$($identityCase.Field)' satisfied evidence presence."
    Assert-Condition (
        "EXTERNAL_SOURCE_EVIDENCE_REF_MISSING" -cin
            @($identityRow.blocker_codes)
    ) "Identity mismatch '$($identityCase.Field)' omitted its blocker."
    Assert-Condition (-not [bool]$identityRow.reference_triple_present) `
        "Identity mismatch '$($identityCase.Field)' closed the triple."
    Assert-ThrowsCode {
        Assert-P2FReleaseReferenceClosure -Result $identityResult
    } "P2F_RELEASE_REFERENCE_CLOSURE_FAILED" `
        "identity mismatch $($identityCase.Field) closure"
}

$evidenceOnlyRequirement = Invoke-SyntheticBundle (
    New-SyntheticReleaseBundle -FirstProjectRequirementKeysEmpty
)
Assert-Condition (
    [bool]$evidenceOnlyRequirement.Manifest.release_mechanisms[0].reference_triple_present
) "Evidence-backed mechanism was forced to encode a work item as a project requirement."

$forgedEvidence = New-SyntheticReleaseBundle
$forgedEvidence.EvidenceJoin.Manifest.counts.evidence_link_count = 99L
Update-CanonicalResult $forgedEvidence.EvidenceJoin
Assert-ThrowsCode { Invoke-SyntheticBundle $forgedEvidence } `
    "P2F_EVIDENCE_JOIN_TAMPERED" "forged evidence-join count"

$forgedCurrentness = New-SyntheticReleaseBundle -FirstEvidenceNoncurrent
$forgedCurrentness.EvidenceJoin.Manifest.evidence_records[0].evidence_current = `
    $true
$forgedCurrentness.EvidenceJoin.Manifest.evidence_records[0].blocker_codes = `
    [object[]]@()
$forgedCurrentness.EvidenceJoin.Manifest.mechanism_evidence[0].evidence_current = `
    $true
$forgedCurrentness.EvidenceJoin.Manifest.mechanism_evidence[0].blocker_codes = `
    [object[]]@()
$forgedCurrentness.EvidenceJoin.Manifest.counts.current_evidence_count = 2L
$forgedCurrentness.EvidenceJoin.Manifest.counts.blocked_evidence_count = 0L
Update-CanonicalResult $forgedCurrentness.EvidenceJoin
Assert-ThrowsCode { Invoke-SyntheticBundle $forgedCurrentness } `
    "P2F_EVIDENCE_JOIN_TAMPERED" `
    "forged evidence currentness with recomputed outer hash"

$forgedFixture = New-SyntheticReleaseBundle
$forgedFixture.FixtureResult.Manifest.fixture_requirements[0].test_id = 999L
Update-CanonicalResult $forgedFixture.FixtureResult
Assert-ThrowsCode { Invoke-SyntheticBundle $forgedFixture } `
    "P2F_FIXTURE_MANIFEST_TAMPERED" "forged fixture binding"

$forgedSpecBinding = New-SyntheticReleaseBundle
$forgedSpecBinding.EvidenceJoin.Compilation = [pscustomobject]@{
    SpecManifestHash = "f" * 64
}
Assert-ThrowsCode { Invoke-SyntheticBundle $forgedSpecBinding } `
    "P2F_INPUT_BINDING_MISMATCH" "forged spec binding"

$forgedCompilation = New-SyntheticReleaseBundle
$forgedCompilation.Compilation.SpecManifest.mechanisms[0].target_maturity = `
    "SPECIFIED"
$forgedCompilationJson = ConvertTo-BattleCanonicalJson `
    $forgedCompilation.Compilation.SpecManifest
$forgedCompilation.Compilation.SpecManifestJson = $forgedCompilationJson
$forgedCompilation.Compilation.SpecManifestBytes = `
    [Text.UTF8Encoding]::new($false, $true).GetBytes($forgedCompilationJson)
$forgedCompilation.Compilation.SpecManifestHash = Get-BattleSha256Text `
    $forgedCompilationJson
Assert-ThrowsCode { Invoke-SyntheticBundle $forgedCompilation } `
    "P2F_SPEC_COMPILATION_TAMPERED" `
    "forged compiled target with recomputed spec hash"

$forgedWorkItem = New-SyntheticReleaseBundle
$forgedWorkItem.WorkItemSet.InputSetHash = "f" * 64
Assert-ThrowsCode { Invoke-SyntheticBundle $forgedWorkItem } `
    "P2F_WORK_ITEM_INPUT_HASH" "forged work-item input hash"

$forgedCompletion = New-SyntheticReleaseBundle
$forgedCompletion.WorkItemSet.Records[0].Validation.CompletionStatus = "RELEASED"
Assert-ThrowsCode { Invoke-SyntheticBundle $forgedCompletion } `
    "P2F_WORK_ITEM_ID_BINDING" "forged work-item completion status"

$releaseJson = $positive.ManifestJson
foreach ($forbidden in @(
    "programs/src", "synthetic-contract.md", "source_relative_path",
    "symbol_or_record_key", "observation_summary", "fixture_payload",
    "timestamp", "guid", "D:\\"
)) {
    Assert-Condition ($releaseJson -cnotmatch [regex]::Escape($forbidden)) `
        "Release output leaked forbidden text '$forbidden'."
}

$inspectionMechanism = [pscustomobject]@{
    mechanism_id = 101L
    target_maturity = "RELEASED"
}
$inspectionRequirements = [pscustomobject]@{
    SpecifiedRequirementsSatisfied = $true
    RequiredTestCount = 1L
    RequiredOracles = [object[]]@("SCENARIO")
}
Assert-ThrowsCode {
    New-P2CompilerMaturityResult -Mechanism $inspectionMechanism `
        -RequirementEvaluation $inspectionRequirements
} "P2_MATURITY_TARGET_UNMET" "default compiler maturity gate"
$inspectionMaturity = New-P2CompilerMaturityResult `
    -Mechanism $inspectionMechanism `
    -RequirementEvaluation $inspectionRequirements `
    -InspectUnmetMaturityTargets
Assert-Condition (
    [string]$inspectionMaturity.computed_status -ceq "SPECIFIED" -and
    -not [bool]$inspectionMaturity.meets_target
) "Reference inspection promoted or concealed an unmet maturity target."

$facts = [pscustomobject][ordered]@{
    identity_registered = $true
    discovery_basis_verified = $true
    specification_valid = $true
    cross_references_valid = $true
    implementation_bindings_verified = $false
    dependency_gate_passed = $false
    required_test_count = 1L
    executed_test_count = 0L
    passed_test_count = 0L
    required_oracles = [object[]]@("SCENARIO")
    passed_oracles = [object[]]@()
    coverage_observed = $false
    evidence_current = $false
    release_catalog_versioned = $false
    release_migration_complete = $false
    release_change_log_complete = $false
    release_coverage_gate_passed = $false
}
$maturity = Get-P2MaturityComputation -MechanismId 101L `
    -TargetMaturity "RELEASED" -Facts $facts
Assert-Condition (
    [string]$maturity.computed_status -ceq "SPECIFIED" -and
    -not [bool]$maturity.meets_target
) "Release reference overlay weakened the existing maturity computation."
Assert-ThrowsCode { Assert-P2MaturityTarget $maturity } `
    "P2_MATURITY_TARGET_UNMET" "existing release maturity gate"

$cliOutput = @(
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cliPath `
        -ProjectRoot $ProjectRoot -Mode Repository `
        -GodotContractRoot $GodotContractRoot 2>&1 |
        ForEach-Object { [string]$_ }
)
Assert-Condition ($LASTEXITCODE -eq 0) `
    "Release-reference CLI failed: $($cliOutput -join "`n")"
$cliText = $cliOutput -join "`n"
Assert-Condition ($cliText -cmatch (
    '^P2_RELEASE_REFERENCES_OK mode=Repository release_mechanisms=0 ' +
    'reference_triples=0 blocked=0 manifest_sha256=[0-9a-f]{64} ' +
    'validation_scope=STATIC_REFERENCE_TRIPLE_ONLY$'
)) "Release-reference CLI marker is unstable."

$afterGenerated = @(
    if (Test-Path -LiteralPath $generatedRoot -PathType Container) {
        Get-ChildItem -LiteralPath $generatedRoot -Recurse -Force -File |
            ForEach-Object { $_.FullName }
    }
)
Assert-Condition (
    (@($beforeGenerated) -join "`n") -ceq (@($afterGenerated) -join "`n")
) "Release-reference validation wrote generated artifacts."

Write-Output (
    "P2_RELEASE_REFERENCE_TEST_OK checks=$script:checks " +
    "repository_sha256=$($repositoryOne.ManifestHash) " +
    "synthetic_sha256=$($positive.ManifestHash)"
)
