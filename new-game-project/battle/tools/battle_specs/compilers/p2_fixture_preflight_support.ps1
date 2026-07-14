Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "p2_spec_compiler_support.ps1")

$script:P2FixturePreflightContractVersion = 1
$script:P2FixtureRequirementManifestSchemaVersion = 1
$script:P2FixtureSetupCompilerStatus = "UNAVAILABLE_P7"
$script:P2FixtureScenarioPrefix = (
    "new-game-project/battle/fixtures/synthetic/scenarios"
)

function Assert-P2FixturePreflightObjectFields {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string[]]$Fields,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Label
    )

    foreach ($field in $Fields) {
        if ($Value.PSObject.Properties.Name -cnotcontains $field) {
            throw "$Code`: $Label omits '$field'."
        }
    }
}

function Copy-P2FixturePreflightCoverageTargets {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][object[]]$CoverageTargets
    )

    $result = [Collections.Generic.List[object]]::new()
    foreach ($targetValue in $CoverageTargets) {
        $target = [PSCustomObject]$targetValue
        Assert-P2FixturePreflightObjectFields -Value $target `
            -Fields @("mechanism_id", "branch_id") `
            -Code "P2D_COVERAGE_TARGET_FIELD" -Label "Coverage target"
        $result.Add([pscustomobject][ordered]@{
            mechanism_id = [long]$target.mechanism_id
            branch_id = [long]$target.branch_id
        })
    }
    return ,$result.ToArray()
}

function Copy-P2FixturePreflightLongArray {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][object[]]$Values
    )

    $result = [Collections.Generic.List[long]]::new()
    foreach ($value in $Values) {
        $result.Add([long]$value)
    }
    return ,$result.ToArray()
}

function Copy-P2FixturePreflightStringArray {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][object[]]$Values
    )

    $result = [Collections.Generic.List[string]]::new()
    foreach ($value in $Values) {
        $result.Add([string]$value)
    }
    return ,$result.ToArray()
}

function Sort-P2FixturePreflightRequirements {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][object[]]$Requirements
    )

    $result = [object[]]@($Requirements)
    for ($index = 1; $index -lt $result.Count; $index++) {
        $candidate = $result[$index]
        $position = $index - 1
        while (
            $position -ge 0 -and
            [long]$result[$position].fixture_id -gt
                [long]$candidate.fixture_id
        ) {
            $result[$position + 1] = $result[$position]
            $position--
        }
        $result[$position + 1] = $candidate
    }
    return $result
}

function Assert-P2FixturePreflightTestBindings {
    param(
        [Parameter(Mandatory = $true)][object]$Compilation,
        [Parameter(Mandatory = $true)][object]$SpecSet
    )

    $compiledById = [Collections.Generic.Dictionary[long, string]]::new()
    foreach ($compiledValue in @($Compilation.SpecManifest.tests)) {
        $compiled = [PSCustomObject]$compiledValue
        Assert-P2FixturePreflightObjectFields -Value $compiled -Fields @(
            "test_id", "canonical_authoring_sha256"
        ) -Code "P2D_COMPILED_TEST_FIELD" -Label "Compiled test index"
        $testId = [long]$compiled.test_id
        if ($compiledById.ContainsKey($testId)) {
            throw "P2D_COMPILED_TEST_DUPLICATE: Compiled test_id $testId is repeated."
        }
        $compiledById.Add($testId, [string]$compiled.canonical_authoring_sha256)
    }

    Assert-P2FixturePreflightObjectFields -Value $SpecSet.InputSet `
        -Fields @("test_entries") -Code "P2D_INPUT_SET_FIELD" `
        -Label "Spec input set"
    $inputByPath = [Collections.Generic.Dictionary[string, string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($inputValue in @($SpecSet.InputSet.test_entries)) {
        $input = [PSCustomObject]$inputValue
        Assert-P2FixturePreflightObjectFields -Value $input -Fields @(
            "relative_path", "canonical_sha256"
        ) -Code "P2D_INPUT_TEST_FIELD" -Label "Input test index"
        $relativePath = [string]$input.relative_path
        if ($inputByPath.ContainsKey($relativePath)) {
            throw (
                "P2D_INPUT_TEST_DUPLICATE: Input test path " +
                "'$relativePath' is repeated."
            )
        }
        $inputByPath.Add($relativePath, [string]$input.canonical_sha256)
    }

    $seenIds = [Collections.Generic.HashSet[long]]::new()
    $seenPaths = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($recordValue in @($SpecSet.TestEntries)) {
        $record = [PSCustomObject]$recordValue
        Assert-P2FixturePreflightObjectFields -Value $record -Fields @(
            "RelativePath", "Manifest", "Validation"
        ) -Code "P2D_TEST_RECORD_FIELD" -Label "Test record"
        Assert-P2FixturePreflightObjectFields -Value $record.Validation `
            -Fields @("Sha256") -Code "P2D_TEST_VALIDATION_FIELD" `
            -Label "Test validation"
        $validation = Test-P2TestManifestEntry `
            -Entry ([PSCustomObject]$record.Manifest)
        $testId = [long]$validation.PrimaryId
        $relativePath = [string]$record.RelativePath
        $authoringHash = [string]$validation.Sha256
        if (-not $seenIds.Add($testId)) {
            throw "P2D_TEST_ID_DUPLICATE: Test record ID $testId is repeated."
        }
        if (-not $seenPaths.Add($relativePath)) {
            throw "P2D_TEST_PATH_DUPLICATE: Test path '$relativePath' is repeated."
        }
        if ([string]$record.Validation.Sha256 -cne $authoringHash) {
            throw (
                "P2D_TEST_VALIDATION_HASH: Test $testId validation hash " +
                "does not match its canonical authoring bytes."
            )
        }
        if (-not $inputByPath.ContainsKey($relativePath) -or
            $inputByPath[$relativePath] -cne $authoringHash) {
            throw (
                "P2D_INPUT_TEST_BINDING: Test $testId is not bound to the " +
                "same path and hash in the spec input set."
            )
        }
        if (-not $compiledById.ContainsKey($testId) -or
            $compiledById[$testId] -cne $authoringHash) {
            throw (
                "P2D_COMPILED_TEST_BINDING: Test $testId is not bound to " +
                "the same hash in the compiled spec manifest."
            )
        }
    }
    if ($seenIds.Count -ne $compiledById.Count -or
        $seenPaths.Count -ne $inputByPath.Count) {
        throw (
            "P2D_TEST_SET_COUNT: Validated, input-set, and compiled test " +
            "indexes do not contain the same complete test set."
        )
    }
}

function Assert-P2FixturePreflightCompilationSpecSet {
    param([Parameter(Mandatory = $true)][object]$Compilation)

    Assert-P2FixturePreflightObjectFields -Value $Compilation -Fields @(
        "CompilerContractVersion", "SpecSet", "SpecManifest",
        "SpecManifestJson", "SpecManifestHash"
    ) -Code "P2D_COMPILATION_FIELD" -Label "Compilation"
    $SpecSet = $Compilation.SpecSet
    Assert-P2FixturePreflightObjectFields -Value $SpecSet -Fields @(
        "StableManifestHash", "TestEntries", "InputSet", "InputSetHash"
    ) -Code "P2D_SPEC_SET_FIELD" -Label "SpecSet"

    if ([long]$Compilation.CompilerContractVersion -ne
        $script:P2CompilerContractVersion) {
        throw (
            "P2D_SOURCE_COMPILER_CONTRACT_VERSION: Expected P2 spec " +
            "compiler contract $script:P2CompilerContractVersion."
        )
    }
    $canonicalSpecJson = ConvertTo-BattleCanonicalJson `
        -Value $Compilation.SpecManifest
    if ($canonicalSpecJson -cne [string]$Compilation.SpecManifestJson) {
        throw (
            "P2D_SPEC_MANIFEST_CANONICAL: Compilation SpecManifestJson " +
            "does not equal the canonical SpecManifest projection."
        )
    }
    $computedSpecHash = Get-BattleSha256Text -Text $canonicalSpecJson
    if ($computedSpecHash -cne [string]$Compilation.SpecManifestHash) {
        throw "P2D_SPEC_MANIFEST_HASH: Compilation spec hash is not canonical."
    }

    $canonicalInputSetJson = ConvertTo-BattleCanonicalJson `
        -Value $SpecSet.InputSet
    $computedInputSetHash = Get-BattleSha256Text -Text $canonicalInputSetJson
    if ($computedInputSetHash -cne [string]$SpecSet.InputSetHash) {
        throw (
            "P2D_INPUT_SET_HASH: SpecSet input hash does not match its " +
            "canonical input projection."
        )
    }
    Assert-P2FixturePreflightObjectFields -Value $Compilation.SpecManifest `
        -Fields @(
            "compiler_contract_version", "stable_id_manifest_sha256",
            "authoring_input_set_sha256", "tests"
        ) -Code "P2D_SPEC_MANIFEST_FIELD" -Label "Compiled spec manifest"
    if ([long]$Compilation.SpecManifest.compiler_contract_version -ne
        [long]$Compilation.CompilerContractVersion -or
        [string]$Compilation.SpecManifest.stable_id_manifest_sha256 -cne
        [string]$SpecSet.StableManifestHash -or
        [string]$Compilation.SpecManifest.authoring_input_set_sha256 -cne
        $computedInputSetHash) {
        throw (
            "P2D_COMPILATION_SPEC_SET_MISMATCH: Compiled spec identity " +
            "does not match its validated input set."
        )
    }
    Assert-P2FixturePreflightTestBindings -Compilation $Compilation `
        -SpecSet $SpecSet
}

# P2D intentionally compiles declarations only. It does not decode fixture
# payloads or stand in for the production setup compiler assigned to P7.
function Invoke-P2ValidatedFixturePreflightCore {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Compilation)

    Assert-P2FixturePreflightObjectFields -Value $Compilation `
        -Fields @("SpecSet") -Code "P2D_COMPILATION_FIELD" `
        -Label "Compilation"
    $SpecSet = $Compilation.SpecSet
    Assert-P2FixturePreflightCompilationSpecSet -Compilation $Compilation

    $requirements = [Collections.Generic.List[object]]::new()
    $fixtureIds = [Collections.Generic.HashSet[long]]::new()
    $scenarioTestCount = 0
    foreach ($recordValue in @($SpecSet.TestEntries)) {
        $record = [PSCustomObject]$recordValue
        Assert-P2FixturePreflightObjectFields -Value $record `
            -Fields @("Manifest") -Code "P2D_TEST_RECORD_FIELD" `
            -Label "Test record"
        $test = [PSCustomObject]$record.Manifest
        Assert-P2FixturePreflightObjectFields -Value $test -Fields @(
            "test_id", "test_kind", "fixture_id", "coverage_targets",
            "expected_event_ids", "expected_handler_ids",
            "expected_state_op_ids", "expected_command_ids",
            "required_oracle_kinds"
        ) -Code "P2D_TEST_MANIFEST_FIELD" -Label "Test manifest"
        if ([string]$test.test_kind -cne "SCENARIO") {
            continue
        }

        $scenarioTestCount++
        $testId = [long]$test.test_id
        $fixtureId = [long]$test.fixture_id
        if ($fixtureId -ne $testId) {
            throw (
                "P2D_FIXTURE_TEST_ID_MISMATCH: SCENARIO test $testId " +
                "declares fixture_id $fixtureId."
            )
        }
        if (-not $fixtureIds.Add($fixtureId)) {
            throw (
                "P2D_FIXTURE_ID_DUPLICATE: SCENARIO fixture_id $fixtureId " +
                "is declared more than once."
            )
        }
        $requirements.Add([pscustomobject][ordered]@{
            fixture_id = $fixtureId
            test_id = $testId
            coverage_targets = Copy-P2FixturePreflightCoverageTargets `
                -CoverageTargets @($test.coverage_targets)
            expected_event_ids = Copy-P2FixturePreflightLongArray `
                -Values @($test.expected_event_ids)
            expected_handler_ids = Copy-P2FixturePreflightLongArray `
                -Values @($test.expected_handler_ids)
            expected_state_op_ids = Copy-P2FixturePreflightLongArray `
                -Values @($test.expected_state_op_ids)
            expected_command_ids = Copy-P2FixturePreflightLongArray `
                -Values @($test.expected_command_ids)
            required_oracle_kinds = Copy-P2FixturePreflightStringArray `
                -Values @($test.required_oracle_kinds)
        })
    }

    $orderedRequirements = @(Sort-P2FixturePreflightRequirements `
        -Requirements $requirements.ToArray())
    for ($index = 1; $index -lt $orderedRequirements.Count; $index++) {
        if ([long]$orderedRequirements[$index - 1].fixture_id -ge
            [long]$orderedRequirements[$index].fixture_id) {
            throw "P2D_FIXTURE_ID_ORDER: Fixture requirements are not unique and sorted."
        }
    }

    $manifest = [pscustomobject][ordered]@{
        artifact_kind = "COMPILED_FIXTURE_REQUIREMENT_MANIFEST"
        schema_version = $script:P2FixtureRequirementManifestSchemaVersion
        preflight_contract_version = $script:P2FixturePreflightContractVersion
        source_spec_compiler_contract_version = `
            [long]$Compilation.CompilerContractVersion
        setup_compiler_status = $script:P2FixtureSetupCompilerStatus
        spec_manifest_sha256 = [string]$Compilation.SpecManifestHash
        stable_id_manifest_sha256 = [string]$SpecSet.StableManifestHash
        fixture_requirements = $orderedRequirements
    }
    $manifestJson = ConvertTo-BattleCanonicalJson -Value $manifest
    $manifestHash = Get-BattleSha256Text -Text $manifestJson
    $manifestBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes(
        $manifestJson
    )
    return [pscustomobject][ordered]@{
        Compilation = $Compilation
        SpecSet = $SpecSet
        Manifest = $manifest
        ManifestJson = $manifestJson
        ManifestBytes = $manifestBytes
        ManifestHash = $manifestHash
        FixtureRequirementCount = [long]$orderedRequirements.Count
        ScenarioTestCount = [long]$scenarioTestCount
        SetupCompilerStatus = $script:P2FixtureSetupCompilerStatus
    }
}

function Invoke-P2FixturePreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet("Repository", "Worktree", "Staged")]
        [string]$Mode = "Repository"
    )

    $view = New-P2RepositoryView -ProjectRoot $ProjectRoot -Mode $Mode `
        -CandidatePrefixes @(
            "new-game-project/battle/specs",
            $script:P2FixtureScenarioPrefix
        )
    $fixturePaths = @(Get-P2RepositoryViewPaths -View $view `
        -Prefix $script:P2FixtureScenarioPrefix)
    if ($fixturePaths.Count -gt 0) {
        throw (
            "P2D_SETUP_COMPILER_UNAVAILABLE_P7: Cannot compile " +
            "$($fixturePaths.Count) synthetic scenario fixture path(s) " +
            "before the production BattleSetup compiler exists."
        )
    }

    $specSet = Read-P2ValidatedSpecSet -View $view
    $compilation = Invoke-P2ValidatedSpecCompilerCore -SpecSet $specSet
    return Invoke-P2ValidatedFixturePreflightCore `
        -Compilation $compilation
}

function Compile-P2FixtureRequirements {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet("Repository", "Worktree", "Staged")]
        [string]$Mode = "Repository"
    )

    return Invoke-P2FixturePreflight -ProjectRoot $ProjectRoot -Mode $Mode
}
