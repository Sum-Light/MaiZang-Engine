[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [switch]$LoadCompilerFixturesOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battleRoot = Join-Path $ProjectRoot "new-game-project\battle"
$fixturePath = Join-Path $PSScriptRoot "p2_spec_contract_test.ps1"
$compilerPath = Join-Path $battleRoot (
    "tools\battle_specs\compilers\p2_spec_compiler_support.ps1"
)
$compilerCliPath = Join-Path $battleRoot (
    "tools\battle_specs\compilers\compile_p2_specs.ps1"
)
$schemaRoot = Join-Path $battleRoot "tools\battle_specs\schemas"
$stablePath = Join-Path $battleRoot (
    "specs\id_manifests\battle_stable_ids.json"
)
$presentationPath = Join-Path $battleRoot (
    "specs\presentation\presentation_contracts.json"
)
$script:checks = 0

. $compilerPath
. $fixturePath -ProjectRoot $ProjectRoot -LoadFixturesOnly
$script:checks = 0

$compilerSource = [IO.File]::ReadAllText(
    $compilerPath,
    [Text.UTF8Encoding]::new($false, $true)
)
Assert-Condition ($compilerSource -notmatch '\bMove-Item\b') `
    "Compiler uses Move-Item, which nests staging under a racing directory."
Assert-Condition ($compilerSource -match '\[IO\.Directory\]::Move\(') `
    "Compiler does not use target-must-not-exist directory publication."
Assert-Condition ($compilerSource -notmatch '\bRemove-Item\b|\[IO\.Directory\]::Delete\(') `
    "Compiler may delete a staging or published path after concurrent replacement."
Assert-Condition ($compilerSource -notmatch '\[IO\.MemoryStream\]|\.CopyTo\(') `
    "Artifact verification may allocate from an untrusted file length."
Assert-Condition (
    $compilerSource -notmatch '\[IO\.File\]::ReadAllBytes|\[IO\.File\]::WriteAllBytes' -and
    $compilerSource -match 'Open-P2RepositoryViewVerifiedHandle' -and
    $compilerSource -match 'New-P2RepositoryViewVerifiedFileHandle' -and
    $compilerSource -match 'EnumerateFileSystemInfos\(\)'
) "Compiler artifact I/O does not consistently use verified no-follow handles."

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
    $script:checks += 1
}

function Assert-ExactPropertySet {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Value,
        [Parameter(Mandatory = $true)][object]$SchemaNode,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $actual = @($Value.PSObject.Properties.Name)
    $required = @($SchemaNode.required | ForEach-Object { [string]$_ })
    [Array]::Sort($actual, [StringComparer]::Ordinal)
    [Array]::Sort($required, [StringComparer]::Ordinal)
    Assert-Condition (($actual -join "`n") -ceq ($required -join "`n")) `
        "$Label does not exactly match its schema property set."
}

function Test-P2CompilerExternalSchemaReferences {
    param(
        [AllowNull()][object]$Node,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$SchemaCache
    )

    if ($null -eq $Node) {
        return
    }
    if ($Node -is [Array]) {
        $items = @($Node)
        for ($index = 0; $index -lt $items.Count; $index++) {
            Test-P2CompilerExternalSchemaReferences -Node $items[$index] `
                -Context "$Context[$index]" -SchemaCache $SchemaCache
        }
        return
    }
    if ($Node -isnot [PSCustomObject]) {
        return
    }
    $referenceProperty = $Node.PSObject.Properties['$ref']
    if ($null -ne $referenceProperty) {
        $reference = [string]$referenceProperty.Value
        if (-not $reference.StartsWith('#', [StringComparison]::Ordinal)) {
            Assert-Condition (
                $reference -cmatch
                '^(?<file>[a-z0-9_]+\.schema\.json)#/(?<pointer>.+)$'
            ) "$Context has a noncanonical external schema reference '$reference'."
            $fileName = [string]$Matches.file
            if (-not $SchemaCache.ContainsKey($fileName)) {
                $schemaPath = Join-Path $schemaRoot $fileName
                Assert-Condition (
                    Test-Path -LiteralPath $schemaPath -PathType Leaf
                ) "$Context references missing schema '$fileName'."
                $SchemaCache.Add($fileName, (Read-BattleStrictJsonFile `
                    -Path $schemaPath -Label "referenced schema $fileName"))
            }
            $target = $SchemaCache[$fileName]
            foreach ($rawSegment in ([string]$Matches.pointer).Split('/')) {
                $segment = $rawSegment.Replace('~1', '/').Replace('~0', '~')
                Assert-Condition (
                    $target -is [PSCustomObject] -and
                    $null -ne $target.PSObject.Properties[$segment]
                ) "$Context has unresolved external reference '$reference'."
                $target = $target.PSObject.Properties[$segment].Value
            }
        }
    }
    foreach ($property in $Node.PSObject.Properties) {
        Test-P2CompilerExternalSchemaReferences -Node $property.Value `
            -Context "$Context.$($property.Name)" -SchemaCache $SchemaCache
    }
}

function Get-P2CompilerExceptionMessage {
    param([Parameter(Mandatory = $true)][scriptblock]$Action)

    try {
        $null = & $Action
    }
    catch {
        return [string]$_.Exception.Message
    }
    throw "Expected compiler action did not fail."
}

function New-P2CompilerPresentationManifest {
    param([Parameter(Mandatory = $true)][PSCustomObject]$EmptyManifest)

    $manifest = Copy-JsonValue $EmptyManifest
    $manifest.payload_schemas = [object[]]@(
        [pscustomobject][ordered]@{
            payload_schema_id = 1
            debug_key = "PAYLOAD_SYNTHETIC"
            status = "ACTIVE"
            aliases = [object[]]@()
            schema_version = 1
            fields = [object[]]@()
        }
    )
    $manifest.cues = [object[]]@(
        [pscustomobject][ordered]@{
            presentation_cue_id = 1
            debug_key = "CUE_SYNTHETIC"
            status = "ACTIVE"
            aliases = [object[]]@()
            presentation_tags = [object[]]@(5)
            semantic_phase = "AFTER"
            information_class = "REQUIRED_INFORMATION"
            fallback_text_key = "BATTLE.SYNTHETIC"
            local_barrier_policy = "NONE"
            payload_schema_id = 1
        }
    )
    return $manifest
}

function New-P2CompilerRecord {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Manifest,
        [Parameter(Mandatory = $true)][string]$Validator,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $validation = & $Validator $Manifest
    return [pscustomobject][ordered]@{
        RelativePath = $RelativePath
        Manifest = $Manifest
        Validation = $validation
    }
}

function New-P2CompilerInputRecords {
    param([Parameter(Mandatory = $true)][object[]]$Records)

    $result = [Collections.Generic.List[object]]::new()
    foreach ($recordValue in @($Records)) {
        $record = [PSCustomObject]$recordValue
        $result.Add([pscustomobject][ordered]@{
            relative_path = [string]$record.RelativePath
            canonical_sha256 = [string]$record.Validation.Sha256
        })
    }
    return ,$result.ToArray()
}

function Copy-P2CompilerSpecSet {
    param([Parameter(Mandatory = $true)][PSCustomObject]$Source)

    $definitions = @(
        [pscustomobject]@{ Property = "MechanismSpecs" },
        [pscustomobject]@{ Property = "EventSchemas" },
        [pscustomobject]@{ Property = "HandlerBindings" },
        [pscustomobject]@{ Property = "ResolverSpecs" },
        [pscustomobject]@{ Property = "TestEntries" }
    )
    $recordSets = [ordered]@{}
    foreach ($definition in $definitions) {
        $records = [Collections.Generic.List[object]]::new()
        foreach ($recordValue in @($Source.($definition.Property))) {
            $record = [PSCustomObject]$recordValue
            $records.Add([pscustomobject][ordered]@{
                RelativePath = [string]$record.RelativePath
                Manifest = Copy-JsonValue $record.Manifest
                Validation = [pscustomobject][ordered]@{
                    Sha256 = [string]$record.Validation.Sha256
                }
            })
        }
        $recordSets[$definition.Property] = $records.ToArray()
    }
    return [pscustomobject][ordered]@{
        StableManifest = Copy-JsonValue $Source.StableManifest
        StableManifestHash = [string]$Source.StableManifestHash
        PresentationManifest = Copy-JsonValue $Source.PresentationManifest
        PresentationManifestHash = [string]$Source.PresentationManifestHash
        MechanismSpecs = $recordSets.MechanismSpecs
        EventSchemas = $recordSets.EventSchemas
        HandlerBindings = $recordSets.HandlerBindings
        ResolverSpecs = $recordSets.ResolverSpecs
        TestEntries = $recordSets.TestEntries
        InputSet = Copy-JsonValue $Source.InputSet
        InputSetHash = [string]$Source.InputSetHash
        Counts = Copy-JsonValue $Source.Counts
    }
}

function New-P2CompilerSyntheticSpecSet {
    $emptyStable = Read-BattleStrictJsonFile -Path $stablePath `
        -Label "tracked stable registry"
    $emptyPresentation = Read-BattleStrictJsonFile -Path $presentationPath `
        -Label "tracked presentation registry"
    $stable = New-SyntheticStableRegistry -EmptyRegistry $emptyStable
    (Get-StableDomain $stable "PHASE").entries = [object[]]@(
        (New-StableEntry 1 1 "EXECUTE"),
        (New-StableEntry 1 2 "PHASE_SECOND")
    )
    (Get-StableDomain $stable "INTERRUPT").entries = [object[]]@(
        (New-StableEntry 0 1 "INTERRUPT_SYNTHETIC")
    )
    $presentation = New-P2CompilerPresentationManifest $emptyPresentation

    $mechanism = New-MechanismSpec
    $mechanism.target_maturity = "SPECIFIED"
    $mechanism.formula_stages[0].operation = "FOLD_MODIFIERS"
    $mechanism.formula_stages[0].modifier_event_id = 1
    $mechanism.formula_stages[0].modifier_aggregation = "ADD"
    $event = New-EventSchema
    $event.aggregation_policy = "FOLD_MODIFIERS"
    $event.rounding_stage_refs = [object[]]@(
        [pscustomobject][ordered]@{ mechanism_id = 1; stage_id = 1 }
    )
    $event.rounding_mode = "TOWARD_ZERO"
    $event.rounding_schedule = "AT_STAGE_END"
    $event.writable_operations = [object[]]@(
        [pscustomobject][ordered]@{
            operation_key = "STATE.APPLY"
            argument_type = "SyntheticMutationArgs"
            result_type = "SyntheticMutationResult"
            mutation_class = "CONTEXT_RESULT"
        }
    )
    $event.sort_key = [object[]]@(
        [pscustomobject][ordered]@{
            field_key = "PRIORITY"
            direction = "DESC"
            source = "HANDLER_BINDING"
        },
        [pscustomobject][ordered]@{
            field_key = "INSTANCE_ID"
            direction = "ASC"
            source = "STABLE_ID"
        }
    )
    $handler = New-HandlerBinding
    $resolver = New-ResolverSpec
    $resolver.phases[0].phase_order = 2
    $resolver.phases = [object[]]@(
        $resolver.phases[0],
        [pscustomobject][ordered]@{
            phase_id = 2
            phase_order = 1
            debug_key = "PHASE_SECOND"
            subphase_ids = [object[]]@(1)
            entry_invariants = [object[]]@("STATE.VALID")
            exit_invariants = [object[]]@("STATE.VALID")
            reentry_policy = "DENY"
            maximum_reentries = 0
            mechanism_ids = [object[]]@(1)
        }
    )
    $test = New-TestManifestEntry
    $test.test_kind = "FORMULA_UNIT"
    $test.fixture_id = 0
    $test.required_oracle_kinds = [object[]]@("FORMULA")

    $mechanismRecord = New-P2CompilerRecord -Manifest $mechanism `
        -Validator "Test-P2MechanismSpec" `
        -RelativePath "new-game-project/battle/specs/mechanisms/0000000001.mechanism_spec.json"
    $eventRecord = New-P2CompilerRecord -Manifest $event `
        -Validator "Test-P2EventSchema" `
        -RelativePath "new-game-project/battle/specs/events/0000000001.event_schema.json"
    $handlerRecord = New-P2CompilerRecord -Manifest $handler `
        -Validator "Test-P2HandlerBinding" `
        -RelativePath "new-game-project/battle/specs/handlers/0000000001.handler_binding.json"
    $resolverRecord = New-P2CompilerRecord -Manifest $resolver `
        -Validator "Test-P2ResolverSpec" `
        -RelativePath "new-game-project/battle/specs/resolvers/0000000001.resolver_spec.json"
    $testRecord = New-P2CompilerRecord -Manifest $test `
        -Validator "Test-P2TestManifestEntry" `
        -RelativePath "new-game-project/battle/specs/tests/0000000001.test_manifest_entry.json"

    $stableValidation = Test-P2StableIdManifest $stable
    $presentationValidation = Test-P2PresentationContracts $presentation
    $mechanismRecords = [object[]]@($mechanismRecord)
    $eventRecords = [object[]]@($eventRecord)
    $handlerRecords = [object[]]@($handlerRecord)
    $resolverRecords = [object[]]@($resolverRecord)
    $testRecords = [object[]]@($testRecord)
    $inputSet = [pscustomobject][ordered]@{
        schema_version = 1
        mechanism_specs = New-P2CompilerInputRecords $mechanismRecords
        event_schemas = New-P2CompilerInputRecords $eventRecords
        handler_bindings = New-P2CompilerInputRecords $handlerRecords
        resolver_specs = New-P2CompilerInputRecords $resolverRecords
        test_entries = New-P2CompilerInputRecords $testRecords
    }
    $inputSetJson = ConvertTo-BattleCanonicalJson $inputSet
    return [pscustomobject][ordered]@{
        StableManifest = $stable
        StableManifestHash = [string]$stableValidation.Sha256
        PresentationManifest = $presentation
        PresentationManifestHash = [string]$presentationValidation.Sha256
        MechanismSpecs = $mechanismRecords
        EventSchemas = $eventRecords
        HandlerBindings = $handlerRecords
        ResolverSpecs = $resolverRecords
        TestEntries = $testRecords
        InputSet = $inputSet
        InputSetHash = Get-BattleSha256Text $inputSetJson
        Counts = [pscustomobject][ordered]@{
            mechanism_specs = 1
            event_schemas = 1
            handler_bindings = 1
            resolver_specs = 1
            test_entries = 1
        }
    }
}

function Get-DirectorySnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return "<ABSENT>"
    }
    $records = [Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $Path -File -Recurse) {
        $relative = $file.FullName.Substring(
            [IO.Path]::GetFullPath($Path).TrimEnd('\').Length + 1
        ).Replace('\', '/')
        $records.Add(("{0}|{1}|{2}" -f $relative, $file.Length, (
            Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
        ).Hash))
    }
    $result = $records.ToArray()
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result -join "`n"
}

if ($LoadCompilerFixturesOnly) {
    return
}

$specSet = New-P2CompilerSyntheticSpecSet
$first = Invoke-P2ValidatedSpecCompilerCore -SpecSet $specSet
$second = Invoke-P2ValidatedSpecCompilerCore -SpecSet $specSet
Assert-Throws -Label "public compiler rejects injected spec set" `
    -MessagePattern "parameter.*SpecSet" -Action {
        Invoke-P2SpecCompiler -SpecSet $specSet
    }
Assert-Throws -Label "public compiler rejects injected repository view" `
    -MessagePattern "parameter.*View" -Action {
        Invoke-P2SpecCompiler -View ([pscustomobject]@{
            ViewKind = "P2_REPOSITORY_VIEW"
            Mode = "Repository"
        })
    }
$forgedCompilation = [pscustomobject]@{
    SpecManifestBytes = [Text.Encoding]::UTF8.GetBytes("not-json")
    RuntimeManifestBytes = [Text.Encoding]::UTF8.GetBytes("also-not-json")
    SpecManifestHash = ("0" * 64)
    RuntimeManifestHash = ("1" * 64)
}
Assert-Throws -Label "public action rejects injected compilation" `
    -MessagePattern "parameter.*Compilation" -Action {
        Invoke-P2SpecCompilerAction -ProjectRoot $ProjectRoot `
            -Mode Repository -Compilation $forgedCompilation
    }
Assert-BytesEqual $first.SpecManifestBytes $second.SpecManifestBytes `
    "repeat spec manifest"
Assert-BytesEqual $first.RuntimeManifestBytes $second.RuntimeManifestBytes `
    "repeat runtime manifest"
Assert-Condition ($first.SpecManifestHash -ceq $second.SpecManifestHash) `
    "Repeat spec hashes differ."
Assert-Condition ($first.RuntimeManifestHash -ceq $second.RuntimeManifestHash) `
    "Repeat runtime hashes differ."
Assert-Condition ($first.SpecManifestHash -cmatch '^[0-9a-f]{64}$') `
    "Spec hash is not lowercase SHA-256."
Assert-Condition ($first.RuntimeManifestHash -cmatch '^[0-9a-f]{64}$') `
    "Runtime hash is not lowercase SHA-256."
Assert-Condition (
    [string]$first.RuntimeManifest.spec_manifest_sha256 -ceq
    [string]$first.SpecManifestHash
) "Runtime manifest is not bound to the spec manifest hash."
Assert-Condition (
    [string]$first.SpecManifest.mechanisms[0].computed_status -ceq "SPECIFIED"
) "P2C did not promote the closed synthetic mechanism to SPECIFIED."
Assert-Condition (
    [string]$first.SpecManifest.mechanisms[0].target_maturity -ceq "SPECIFIED"
) "Compiled spec index lost target_maturity."
Assert-Condition (
    [string]$first.SpecManifest.mechanisms[0].canonical_authoring_sha256 -ceq
    [string]$specSet.MechanismSpecs[0].Validation.Sha256
) "Compiled spec index changed the mechanism authoring hash."
Assert-Condition (
    (@($first.RuntimeManifest.resolver_phase_table[0].phases | ForEach-Object {
        [long]$_.phase_id
    }) -join ',') -ceq '2,1'
) "Runtime resolver phases are not sorted by phase_order then phase_id."
Assert-Condition (
    (@($specSet.ResolverSpecs[0].Manifest.phases | ForEach-Object {
        [long]$_.phase_id
    }) -join ',') -ceq '1,2'
) "Compiler mutated the authoring resolver phase order."
Assert-Condition (
    (@($first.RuntimeManifest.event_dispatch_table[0].sort_key | ForEach-Object {
        [string]$_.field_key
    }) -join ',') -ceq 'PRIORITY,INSTANCE_ID'
) "Runtime event sort terms did not preserve semantic declaration order."
Assert-Condition (
    $null -eq $first.RuntimeManifest.resolver_phase_table[0].phases[0].PSObject.Properties['debug_key']
) "Runtime resolver phase leaked debug_key."

$runtimeJson = [string]$first.RuntimeManifestJson
foreach ($forbiddenName in @(
    "artifact_kind", "debug_key", "owner_module", "target_maturity",
    "computed_status", "project_requirement_keys", "evidence_ids",
    "coverage_targets", "test_requirements", "fixture_id", "tests"
)) {
    Assert-Condition ($runtimeJson -cnotmatch ('"' + $forbiddenName + '"')) `
        "Runtime manifest leaked forbidden field '$forbiddenName'."
}
Assert-Condition ($runtimeJson -notmatch '(?i)([A-Z]:[\\/]|res://|user://)') `
    "Runtime manifest contains a machine or engine path."
Assert-Condition ($runtimeJson -notmatch '(?i)(timestamp|generated_at|guid|uuid)') `
    "Runtime manifest contains nondeterministic identity or time metadata."

foreach ($bytes in @(
    [byte[]]$first.SpecManifestBytes,
    [byte[]]$first.RuntimeManifestBytes
)) {
    Assert-Condition (-not (
        $bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and
        $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf
    )) "Compiled JSON contains a UTF-8 BOM."
    Assert-Condition ($bytes[$bytes.Length - 1] -eq 0x0a) `
        "Compiled JSON does not end with LF."
    Assert-Condition ($bytes[$bytes.Length - 2] -ne 0x0d) `
        "Compiled JSON ends with CRLF instead of one LF."
}
$null = ConvertFrom-BattleStrictJson -Text $first.SpecManifestJson `
    -Label "compiled spec manifest"
$null = ConvertFrom-BattleStrictJson -Text $first.RuntimeManifestJson `
    -Label "runtime rule catalog"
$script:checks += 2

$specSchema = Read-BattleStrictJsonFile `
    (Join-Path $schemaRoot "compiled_spec_manifest.schema.json") `
    "compiled spec schema"
$runtimeSchema = Read-BattleStrictJsonFile `
    (Join-Path $schemaRoot "runtime_rule_catalog_manifest.schema.json") `
    "runtime rule catalog schema"
Test-StrictSchemaNode $specSchema $specSchema "CompiledSpecManifest"
Test-StrictSchemaNode $runtimeSchema $runtimeSchema "RuntimeRuleCatalog"
$schemaCache = [Collections.Generic.Dictionary[string, object]]::new(
    [StringComparer]::Ordinal
)
Test-P2CompilerExternalSchemaReferences -Node $specSchema `
    -Context "CompiledSpecManifest" -SchemaCache $schemaCache
Test-P2CompilerExternalSchemaReferences -Node $runtimeSchema `
    -Context "RuntimeRuleCatalog" -SchemaCache $schemaCache
Assert-ExactPropertySet $first.SpecManifest $specSchema "compiled spec root"
Assert-ExactPropertySet $first.SpecManifest.mechanisms[0] `
    $specSchema.'$defs'.mechanism_index "compiled mechanism index"
Assert-ExactPropertySet $first.SpecManifest.events[0] `
    $specSchema.'$defs'.event_index "compiled event index"
Assert-ExactPropertySet $first.SpecManifest.handlers[0] `
    $specSchema.'$defs'.handler_index "compiled handler index"
Assert-ExactPropertySet $first.SpecManifest.resolvers[0] `
    $specSchema.'$defs'.resolver_index "compiled resolver index"
Assert-ExactPropertySet $first.SpecManifest.tests[0] `
    $specSchema.'$defs'.test_index "compiled test index"
Assert-ExactPropertySet $first.RuntimeManifest $runtimeSchema "runtime root"
Assert-ExactPropertySet $first.RuntimeManifest.mechanism_plans[0] `
    $runtimeSchema.'$defs'.mechanism_plan "runtime mechanism"
Assert-ExactPropertySet `
    $first.RuntimeManifest.mechanism_plans[0].parameter_slots[0] `
    $runtimeSchema.'$defs'.runtime_parameter_slot "runtime parameter slot"
Assert-ExactPropertySet `
    $first.RuntimeManifest.mechanism_plans[0].formula_stages[0] `
    $runtimeSchema.'$defs'.runtime_formula_stage "runtime formula stage"
Assert-ExactPropertySet $first.RuntimeManifest.event_dispatch_table[0] `
    $runtimeSchema.'$defs'.event_dispatch "runtime event"
Assert-ExactPropertySet $first.RuntimeManifest.handler_binding_table[0] `
    $runtimeSchema.'$defs'.runtime_handler_binding "runtime handler"
Assert-ExactPropertySet $first.RuntimeManifest.resolver_phase_table[0] `
    $runtimeSchema.'$defs'.resolver_phase_plan "runtime resolver"
Assert-ExactPropertySet $first.RuntimeManifest.resolver_phase_table[0].phases[0] `
    $runtimeSchema.'$defs'.runtime_resolver_phase "runtime phase"

$recordTwo = [pscustomobject]@{ Manifest = [pscustomobject]@{ mechanism_id = 2 } }
$recordOne = [pscustomobject]@{ Manifest = [pscustomobject]@{ mechanism_id = 1 } }
$sortedRecords = @(Sort-P2CompilerRecordsById `
    -Records @($recordTwo, $recordOne) -IdProperty "mechanism_id")
Assert-Condition (
    (@($sortedRecords | ForEach-Object { [long]$_.Manifest.mechanism_id }) -join ',') -ceq '1,2'
) "Primary-ID record sort is not numeric ascending."

$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.MechanismSpecs[0].Manifest.feature_pack_ids = [object[]]@(99)
Assert-Throws -Label "unknown feature ID" -MessagePattern "P2C_REF_UNKNOWN" `
    -Action { Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate }
$candidate = Copy-P2CompilerSpecSet $specSet
(Get-StableDomain $candidate.StableManifest "EVENT").entries[0].status = "TOMBSTONE"
Assert-Throws -Label "inactive event ID" -MessagePattern "P2C_REF_INACTIVE" `
    -Action { Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.EventSchemas = [object[]]@()
Assert-Throws -Label "missing event specification" `
    -MessagePattern "P2C_SPEC_MISSING" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.HandlerBindings[0].Manifest.context_type = "OtherEventContext"
Assert-Throws -Label "handler context mismatch" `
    -MessagePattern "P2C_CONTEXT_MISMATCH" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.HandlerBindings[0].Manifest.allowed_mutations = `
    [object[]]@("STATE.UNKNOWN")
Assert-Throws -Label "handler mutation capability mismatch" `
    -MessagePattern "P2C_BACKREF_MISMATCH" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
(Get-StableDomain $candidate.StableManifest "RNG_DRAW").entries = [object[]]@(
    (New-StableEntry 1 1 "RNG_DRAW_SYNTHETIC"),
    (New-StableEntry 1 2 "RNG_DRAW_SECOND")
)
$candidate.HandlerBindings[0].Manifest.allowed_rng_draw_ids = [object[]]@(
    [pscustomobject][ordered]@{ mechanism_id = 1; draw_id = 2 }
)
Assert-Throws -Label "handler undeclared scoped RNG draw" `
    -MessagePattern "P2C_SCOPE_MISMATCH" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
(Get-StableDomain $candidate.StableManifest "MECHANISM").entries = [object[]]@(
    (New-StableEntry 0 1 "MECH_SYNTHETIC"),
    (New-StableEntry 0 2 "MECH_SECOND")
)
(Get-StableDomain $candidate.StableManifest "RNG_DRAW").entries = [object[]]@(
    (New-StableEntry 1 1 "RNG_DRAW_SYNTHETIC"),
    (New-StableEntry 2 1 "RNG_DRAW_SECOND")
)
$candidate.HandlerBindings[0].Manifest.allowed_rng_draw_ids = [object[]]@(
    [pscustomobject][ordered]@{ mechanism_id = 2; draw_id = 1 }
)
$unboundDrawMessage = Get-P2CompilerExceptionMessage {
    Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
}
Assert-Condition (
    $unboundDrawMessage -match
    "P2C_BACKREF_MISMATCH.*allowed_rng_draw_ids.mechanism_id"
) "Handler accepted RNG capability from an unbound mechanism."
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.ResolverSpecs[0].Manifest.phases[0].debug_key = "PHASE_WRONG"
Assert-Throws -Label "phase registry debug mismatch" `
    -MessagePattern "P2C_CANONICAL_MISMATCH" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.MechanismSpecs[0].Manifest.subphase_id = 9
Assert-Throws -Label "entry subphase scope mismatch" `
    -MessagePattern "P2C_SCOPE_MISMATCH" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.MechanismSpecs[0].Manifest.resolver_id = 0
Assert-Throws -Label "entry phase without resolver scope" `
    -MessagePattern "P2C_SCOPE_MISMATCH" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.MechanismSpecs[0].Manifest.handler_ids = [object[]]@()
Assert-Throws -Label "handler reverse link mismatch" `
    -MessagePattern "P2C_BACKREF_MISMATCH" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.ResolverSpecs[0].Manifest.allowed_nested_resolver_ids = [object[]]@(1)
Assert-Throws -Label "nested resolver cycle" -MessagePattern "P2C_GRAPH_CYCLE" `
    -Action { Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate }
$candidate = Copy-P2CompilerSpecSet $specSet
(Get-StableDomain $candidate.StableManifest "BRANCH").entries = [object[]]@(
    (New-StableEntry 1 1 "BRANCH_SYNTHETIC"),
    (New-StableEntry 1 2 "BRANCH_SECOND")
)
$candidate.TestEntries[0].Manifest.coverage_targets[0].branch_id = 2
Assert-Throws -Label "test branch absent from mechanism" `
    -MessagePattern "P2C_TEST_BRANCH_UNKNOWN" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.TestEntries[0].Manifest.expected_event_ids = [object[]]@()
Assert-Throws -Label "expected handler event omitted" `
    -MessagePattern "P2C_BACKREF_MISMATCH" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.MechanismSpecs[0].Manifest.ruleset_mode = "EXPLICIT"
$candidate.MechanismSpecs[0].Manifest.ruleset_ids = [object[]]@(1)
Assert-Throws -Label "missing ruleset provider" `
    -MessagePattern "P2C_RULESET_PROVIDER_MISSING" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.PresentationManifest.cues[0].status = "TOMBSTONE"
Assert-Throws -Label "inactive presentation cue" `
    -MessagePattern "P2C_CUE_INACTIVE" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.EventSchemas[0].Manifest.rounding_stage_refs = [object[]]@(
    [pscustomobject][ordered]@{ mechanism_id = 1; stage_id = 99 }
)
$candidate.EventSchemas[0].Manifest.rounding_mode = "FLOOR"
$candidate.EventSchemas[0].Manifest.rounding_schedule = "AT_STAGE_END"
Assert-Throws -Label "rounding stage scope mismatch" `
    -MessagePattern "P2C_SCOPE_MISMATCH" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.EventSchemas[0].Manifest.rounding_stage_refs = [object[]]@()
$candidate.EventSchemas[0].Manifest.rounding_mode = "NONE"
$candidate.EventSchemas[0].Manifest.rounding_schedule = "NONE"
Assert-Throws -Label "modifier event omits formula rounding stage" `
    -MessagePattern "P2C_BACKREF_MISMATCH" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.MechanismSpecs[0].Manifest.test_requirements = [object[]]@(
    @($candidate.MechanismSpecs[0].Manifest.test_requirements) +
    [pscustomobject][ordered]@{
        test_kind = "RNG"
        required_oracle_kinds = [object[]]@("RNG")
        minimum_cases = 65535
        required_for_target_maturity = "VERIFIED"
    }
)
Assert-Passes -Label "future maturity test requirement remains inactive" -Action {
    Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
}
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.MechanismSpecs[0].Manifest.target_maturity = "DISCOVERED"
$candidate.MechanismSpecs[0].Manifest.test_requirements[0].required_for_target_maturity = `
    "SPECIFIED"
$candidate.TestEntries[0].Manifest.test_kind = "RNG"
$candidate.TestEntries[0].Manifest.required_oracle_kinds = `
    [object[]]@("FORMULA", "RNG")
$belowRequirementTarget = Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
Assert-Condition (
    [string]$belowRequirementTarget.SpecManifest.mechanisms[0].computed_status -ceq
    "DISCOVERED"
) "An unmet future SPECIFIED requirement over-promoted computed maturity."
$candidate.MechanismSpecs[0].Manifest.target_maturity = "SPECIFIED"
Assert-Throws -Label "requirement becomes hard gate at target maturity" `
    -MessagePattern "P2C_TEST_REQUIREMENT_UNMET" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.TestEntries[0].Manifest.test_kind = "RNG"
$candidate.TestEntries[0].Manifest.required_oracle_kinds = `
    [object[]]@("FORMULA", "RNG")
Assert-Throws -Label "test requirement exact kind" `
    -MessagePattern "P2C_TEST_REQUIREMENT_UNMET" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.MechanismSpecs[0].Manifest.test_requirements[0].required_oracle_kinds = `
    [object[]]@("FORMULA", "RNG")
Assert-Throws -Label "test requirement oracle superset" `
    -MessagePattern "P2C_TEST_REQUIREMENT_UNMET" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.MechanismSpecs[0].Manifest.test_requirements[0].minimum_cases = 2
Assert-Throws -Label "test requirement minimum distinct cases" `
    -MessagePattern "P2C_TEST_REQUIREMENT_UNMET" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.TestEntries[0].Manifest.coverage_targets[0].branch_id = 2
Assert-Throws -Label "test requirement declared branch coverage" `
    -MessagePattern "P2C_TEST_REQUIREMENT_UNMET" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.ResolverSpecs[0].Manifest.legal_event_emissions[0].phase_id = 2
Assert-Passes -Label "event emission owned by non-array-order phase" -Action {
    Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
}
$candidate = Copy-P2CompilerSpecSet $specSet
(Get-StableDomain $candidate.StableManifest "EVENT").entries = [object[]]@(
    @((Get-StableDomain $candidate.StableManifest "EVENT").entries) +
    (New-StableEntry 0 2 "EVENT_SECOND")
)
$eventTwo = New-EventSchema
$eventTwo.event_id = 2
$eventTwo.debug_key = "EVENT_SECOND"
$eventTwoRecord = New-P2CompilerRecord -Manifest $eventTwo `
    -Validator "Test-P2EventSchema" `
    -RelativePath "new-game-project/battle/specs/events/0000000002.event_schema.json"
$candidate.EventSchemas = [object[]]@(
    @($candidate.EventSchemas) + $eventTwoRecord
)
$candidate.ResolverSpecs[0].Manifest.legal_event_emissions[0].event_id = 2
Assert-Throws -Label "emission phase mechanism event ownership" `
    -MessagePattern "PHASE_MECHANISM_EVENT" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
(Get-StableDomain $candidate.StableManifest "INTERRUPT").entries = [object[]]@()
Assert-Throws -Label "unknown interruption ID" `
    -MessagePattern "P2C_REF_UNKNOWN" -Action {
        Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
    }
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.MechanismSpecs[0].Manifest.feature_pack_ids = [object[]]@(99)
$candidate.MechanismSpecs[0].Manifest.event_ids = [object[]]@(1, 99)
$diagnosticOne = Get-P2CompilerExceptionMessage {
    Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
}
$diagnosticTwo = Get-P2CompilerExceptionMessage {
    Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
}
Assert-Condition ($diagnosticOne -ceq $diagnosticTwo) `
    "Cross-reference diagnostic ordering is not repeatable."
Assert-Condition (
    $diagnosticOne.IndexOf("event_ids", [StringComparison]::Ordinal) -lt
    $diagnosticOne.IndexOf("feature_pack_ids", [StringComparison]::Ordinal)
) "Cross-reference diagnostics are not ordered by stable field path."
$candidate = Copy-P2CompilerSpecSet $specSet
$candidate.MechanismSpecs[0].Manifest.coverage_targets[0].required_oracle_kinds = `
    [object[]]@("FORMULA", "RNG")
$candidate.TestEntries[0].Manifest.required_oracle_kinds = `
    [object[]]@("SCENARIO")
$oracleDiagnostics = Get-P2CompilerExceptionMessage {
    Invoke-P2ValidatedSpecCompilerCore -SpecSet $candidate
}
Assert-Condition (
    $oracleDiagnostics.IndexOf("(FORMULA)", [StringComparison]::Ordinal) -lt
    $oracleDiagnostics.IndexOf("(RNG)", [StringComparison]::Ordinal)
) "Equal-key diagnostics are not ordered by detail."

$generatedRoot = Join-Path $battleRoot "generated\battle_specs"
$generatedBefore = Get-DirectorySnapshot $generatedRoot
$cliOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File $compilerCliPath -ProjectRoot $ProjectRoot -Mode Repository 2>&1)
$cliExitCode = $LASTEXITCODE
Assert-Condition ($cliExitCode -eq 0) `
    "No-write compiler CLI failed: $($cliOutput -join "`n")"
Assert-Condition (
    (@($cliOutput) -join "`n") -match
    'P2_SPEC_COMPILER_OK mode=Repository action=NO_WRITE mechanisms=0'
) "No-write compiler CLI did not emit its exact action marker."
Assert-Condition ((Get-DirectorySnapshot $generatedRoot) -ceq $generatedBefore) `
    "No-write compiler CLI changed the generated artifact directory."

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$tempRoot = Join-Path $tempParent ("maizang-p2c-{0}" -f [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $tempRoot
try {
    $outputOne = Join-Path $tempRoot "one"
    $outputTwo = Join-Path $tempRoot "two"
    $writeOne = Write-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
        -ProjectRoot $ProjectRoot -OutputDirectory $outputOne
    $writeTwo = Write-P2ValidatedCompiledSpecArtifactsCore -Compilation $second `
        -ProjectRoot $ProjectRoot -OutputDirectory $outputTwo
    Assert-Passes -Label "idempotent immutable output pair" -Action {
        Write-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
            -ProjectRoot $ProjectRoot -OutputDirectory $outputOne
    }
    Assert-BytesEqual ([IO.File]::ReadAllBytes($writeOne.SpecPath)) `
        ([IO.File]::ReadAllBytes($writeTwo.SpecPath)) `
        "two written spec manifests"
    Assert-BytesEqual ([IO.File]::ReadAllBytes($writeOne.RuntimePath)) `
        ([IO.File]::ReadAllBytes($writeTwo.RuntimePath)) `
        "two written runtime manifests"
    Assert-Passes -Label "verify canonical output pair" -Action {
        Confirm-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
            -ProjectRoot $ProjectRoot -VerifyDirectory $outputOne
    }
    $script:stableReadAttackPath = $writeOne.SpecPath
    $script:stableReadAttackAttempted = $false
    $script:stableReadAttackDenied = $false
    $script:originalCompilerByteEquality = (
        Get-Item -LiteralPath Function:\Test-P2CompilerByteEquality
    ).ScriptBlock
    try {
        Set-Item -LiteralPath Function:\Test-P2CompilerByteEquality -Value {
            param([byte[]]$Left, [byte[]]$Right)

            if (-not $script:stableReadAttackAttempted) {
                $script:stableReadAttackAttempted = $true
                try {
                    [IO.File]::AppendAllText(
                        $script:stableReadAttackPath,
                        "race",
                        [Text.UTF8Encoding]::new($false)
                    )
                }
                catch [IO.IOException] {
                    $script:stableReadAttackDenied = $true
                }
                catch [UnauthorizedAccessException] {
                    $script:stableReadAttackDenied = $true
                }
            }
            return & $script:originalCompilerByteEquality `
                -Left $Left -Right $Right
        }
        Assert-Passes -Label "stable pair blocks mid-verify mutation" -Action {
            Confirm-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
                -ProjectRoot $ProjectRoot -VerifyDirectory $outputOne
        }
    }
    finally {
        Set-Item -LiteralPath Function:\Test-P2CompilerByteEquality `
            -Value $script:originalCompilerByteEquality
    }
    Assert-Condition (
        $script:stableReadAttackAttempted -and $script:stableReadAttackDenied
    ) "Stable pair verification did not deny a concurrent artifact write."

    $oversizedPair = Join-Path $tempRoot "oversized-pair"
    $null = New-Item -ItemType Directory -Path $oversizedPair
    $oversizedSpec = Join-Path $oversizedPair "spec_manifest.json"
    $oversizedStream = [IO.File]::Create($oversizedSpec)
    try {
        $oversizedStream.SetLength(1073741824L)
    }
    finally {
        $oversizedStream.Dispose()
    }
    [IO.File]::WriteAllBytes(
        (Join-Path $oversizedPair "runtime_manifest.json"),
        [byte[]]$first.RuntimeManifestBytes
    )
    Assert-Throws -Label "oversized artifact length mismatch" `
        -MessagePattern "P2C_CANONICAL_MISMATCH" -Action {
            Confirm-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
                -ProjectRoot $ProjectRoot -VerifyDirectory $oversizedPair
        }
    [IO.File]::WriteAllText(
        (Join-Path $outputTwo "extra.txt"),
        "extra",
        [Text.UTF8Encoding]::new($false)
    )
    Assert-Throws -Label "verify rejects extra artifact" `
        -MessagePattern "P2C_VERIFY_CONTENTS" -Action {
            Confirm-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
                -ProjectRoot $ProjectRoot -VerifyDirectory $outputTwo
        }
    [IO.File]::AppendAllText($writeOne.RuntimePath, "tamper", `
        [Text.UTF8Encoding]::new($false))
    Assert-Throws -Label "tampered output pair" `
        -MessagePattern "P2C_CANONICAL_MISMATCH" -Action {
            Confirm-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
                -ProjectRoot $ProjectRoot -VerifyDirectory $outputOne
        }
    Assert-Throws -Label "immutable output refuses replacement" `
        -MessagePattern "P2C_OUTPUT_EXISTS" -Action {
            Write-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
                -ProjectRoot $ProjectRoot -OutputDirectory $outputOne
        }

    Assert-Throws -Label "tracked source output location" `
        -MessagePattern "P2C_OUTPUT_LOCATION" -Action {
            Write-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
                -ProjectRoot $ProjectRoot -OutputDirectory $battleRoot
        }
    Assert-Throws -Label "generated boundary requires immutable child" `
        -MessagePattern "P2C_OUTPUT_LOCATION" -Action {
            Write-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
                -ProjectRoot $ProjectRoot -OutputDirectory $generatedRoot
        }
    $tempProject = Join-Path $tempRoot "ci-project"
    $null = New-Item -ItemType Directory -Path $tempProject
    Assert-Throws -Label "temp-hosted project source output" `
        -MessagePattern "P2C_OUTPUT_LOCATION" -Action {
            Write-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
                -ProjectRoot $tempProject `
                -OutputDirectory (Join-Path $tempProject "source-output")
        }
    $unignoredProject = Join-Path $tempRoot "unignored-project"
    $null = New-Item -ItemType Directory -Path $unignoredProject
    $gitInitOutput = @(& git -C $unignoredProject init --quiet 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Temporary Git initialization failed: $($gitInitOutput -join "`n")"
    }
    $unignoredOutput = Join-Path $unignoredProject (
        "new-game-project\battle\generated\battle_specs\unignored"
    )
    Assert-Throws -Label "project-local output must be ignored" `
        -MessagePattern "P2C_OUTPUT_NOT_IGNORED" -Action {
            Write-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
                -ProjectRoot $unignoredProject -OutputDirectory $unignoredOutput
        }
    Assert-Condition (-not (Test-Path -LiteralPath $unignoredOutput)) `
        "Unignored project-local output was created before rejection."
    $trackedProject = Join-Path $tempRoot "tracked-wildcard-project"
    $null = New-Item -ItemType Directory -Path $trackedProject
    $gitInitOutput = @(& git -C $trackedProject init --quiet 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Tracked-path Git initialization failed: $($gitInitOutput -join "`n")"
    }
    [IO.File]::WriteAllText(
        (Join-Path $trackedProject ".gitignore"),
        "new-game-project/battle/generated/`n",
        [Text.UTF8Encoding]::new($false)
    )
    $trackedOutput = Join-Path $trackedProject (
        "new-game-project\battle\generated\battle_specs\run[1]"
    )
    $null = New-Item -ItemType Directory -Path $trackedOutput -Force
    [IO.File]::WriteAllText(
        (Join-Path $trackedOutput "spec_manifest.json"),
        "tracked",
        [Text.UTF8Encoding]::new($false)
    )
    $trackedBlob = (@(& git -C $trackedProject hash-object -w -- `
        (Join-Path $trackedOutput "spec_manifest.json") 2>&1) -join "").Trim()
    if ($LASTEXITCODE -ne 0 -or $trackedBlob -cnotmatch '^[0-9a-f]{40,64}$') {
        throw "Tracked-path fixture blob creation failed."
    }
    $trackedIndexPath = (
        "new-game-project/battle/generated/battle_specs/RUN[1]/spec_manifest.json"
    )
    $gitAddOutput = @(& git -C $trackedProject update-index --add `
        --cacheinfo "100644,$trackedBlob,$trackedIndexPath" 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Tracked-path fixture index add failed: $($gitAddOutput -join "`n")"
    }
    Assert-Throws -Label "case-insensitive literal tracked output path" `
        -MessagePattern "P2C_OUTPUT_TRACKED" -Action {
            Write-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
                -ProjectRoot $trackedProject -OutputDirectory $trackedOutput
        }
    $blockedPair = Join-Path $tempRoot "blocked-pair"
    $null = New-Item -ItemType Directory -Path $blockedPair
    $seedSpec = Join-Path $blockedPair "spec_manifest.json"
    [IO.File]::WriteAllText($seedSpec, "seed", [Text.UTF8Encoding]::new($false))
    $null = New-Item -ItemType Directory `
        -Path (Join-Path $blockedPair "runtime_manifest.json")
    Assert-Throws -Label "pair target preflight" `
        -MessagePattern "P2C_OUTPUT_TARGET_DIRECTORY" -Action {
            Write-P2ValidatedCompiledSpecArtifactsCore -Compilation $first `
                -ProjectRoot $ProjectRoot -OutputDirectory $blockedPair
        }
    Assert-Condition (
        [IO.File]::ReadAllText($seedSpec, [Text.UTF8Encoding]::new($false)) -ceq
        "seed"
    ) "Pair preflight modified the first artifact before rejecting the second."
    $retainedBefore = @(
        Get-ChildItem -LiteralPath $tempRoot -Directory -Force |
            Where-Object { $_.Name -like '.retained.p2c-*.tmp' }
    ).Count
    $retainedOutput = Join-Path $tempRoot "retained"
    $invalidCompilation = [pscustomobject]@{
        SpecManifestBytes = $null
        RuntimeManifestBytes = [byte[]]@(1)
    }
    Assert-Throws -Label "failed publication retains staging evidence" `
        -MessagePattern "null" -Action {
            Write-P2ValidatedCompiledSpecArtifactsCore `
                -Compilation $invalidCompilation `
                -ProjectRoot $ProjectRoot -OutputDirectory $retainedOutput
        }
    $retainedAfter = @(
        Get-ChildItem -LiteralPath $tempRoot -Directory -Force |
            Where-Object { $_.Name -like '.retained.p2c-*.tmp' }
    ).Count
    Assert-Condition ($retainedAfter -eq ($retainedBefore + 1)) `
        "Failed publication removed or replaced its staging evidence."
    Assert-Condition (
        @(Get-ChildItem -LiteralPath $tempRoot -Directory -Force -Recurse |
            Where-Object {
                $_.Name -like '*.p2c-*.tmp' -and
                $_.Name -notlike '.retained.p2c-*.tmp'
            }).Count -eq 0
    ) "Successful atomic publication left a staging directory behind."
}
finally {
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot).TrimEnd('\')
    if (-not $resolvedTempRoot.StartsWith(
        $tempParent + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove compiler test files outside system temp."
    }
    if (Test-Path -LiteralPath $resolvedTempRoot) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}

Write-Host "P2_SPEC_COMPILER_TEST_OK checks=$checks"
