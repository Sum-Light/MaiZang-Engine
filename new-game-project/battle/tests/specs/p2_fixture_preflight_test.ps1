[CmdletBinding()]
param([string]$ProjectRoot = "")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battleRoot = Join-Path $ProjectRoot "new-game-project\battle"
$supportRelative = (
    "new-game-project/battle/tools/battle_specs/compilers/" +
    "p2_fixture_preflight_support.ps1"
)
$cliRelative = (
    "new-game-project/battle/tools/battle_specs/compilers/" +
    "compile_p2_fixture_requirements.ps1"
)
$schemaRelative = (
    "new-game-project/battle/tools/battle_specs/schemas/" +
    "compiled_fixture_requirement_manifest.schema.json"
)
$supportPath = Join-Path $ProjectRoot $supportRelative.Replace('/', '\')
$cliPath = Join-Path $ProjectRoot $cliRelative.Replace('/', '\')
$schemaPath = Join-Path $ProjectRoot $schemaRelative.Replace('/', '\')
$generatedRoot = Join-Path $battleRoot "generated\battle_specs"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$script:checks = 0

. $supportPath

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:checks++
    if (-not $Condition) {
        throw $Message
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

function Assert-ThrowsCode {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $script:checks++
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
    $message = [string]$caught.Exception.Message
    $actualCode = $message.Split(':')[0]
    if ($actualCode -cne $Code) {
        throw "$Label failed with '$actualCode' instead of '$Code': $message"
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
    Assert-Condition (($actual -join "`n") -ceq ($required -join "`n")) `
        "$Label does not exactly match its closed schema property set."
}

function Test-ClosedSchemaNode {
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
            Test-ClosedSchemaNode -RootSchema $RootSchema `
                -Node $items[$index] -Context "$Context[$index]"
        }
        return
    }
    if ($Node -isnot [PSCustomObject]) {
        return
    }

    $referenceProperty = $Node.PSObject.Properties['$ref']
    if ($null -ne $referenceProperty) {
        $reference = [string]$referenceProperty.Value
        Assert-Condition ($reference.StartsWith(
            '#/$defs/', [StringComparison]::Ordinal
        )) "$Context has a nonlocal schema reference '$reference'."
        $definitionName = $reference.Substring(8)
        Assert-Condition (
            $null -ne $RootSchema.'$defs'.PSObject.Properties[$definitionName]
        ) "$Context has unresolved schema reference '$reference'."
    }

    $typeProperty = $Node.PSObject.Properties['type']
    if ($null -ne $typeProperty -and [string]$typeProperty.Value -ceq 'object') {
        Assert-Condition (
            $null -ne $Node.PSObject.Properties['additionalProperties'] -and
            $Node.additionalProperties -is [bool] -and
            -not [bool]$Node.additionalProperties
        ) "$Context is not a closed object schema."
        Assert-Condition (
            $null -ne $Node.PSObject.Properties['required'] -and
            $Node.required -is [Array]
        ) "$Context has no required property list."
        Assert-Condition (
            $null -ne $Node.PSObject.Properties['properties'] -and
            $Node.properties -is [PSCustomObject]
        ) "$Context has no properties object."
        $requiredNames = @($Node.required | ForEach-Object { [string]$_ })
        $propertyNames = @($Node.properties.PSObject.Properties.Name)
        [Array]::Sort($requiredNames, [StringComparer]::Ordinal)
        [Array]::Sort($propertyNames, [StringComparer]::Ordinal)
        Assert-Condition (
            ($requiredNames -join "`n") -ceq ($propertyNames -join "`n")
        ) "$Context required fields do not exactly cover its properties."
    }
    if ($null -ne $typeProperty -and [string]$typeProperty.Value -ceq 'array') {
        Assert-Condition (
            $null -ne $Node.PSObject.Properties['maxItems'] -and
            (Test-P2IntegralType $Node.maxItems) -and
            [long]$Node.maxItems -ge 0
        ) "$Context array has no finite maxItems."
    }

    foreach ($property in $Node.PSObject.Properties) {
        Test-ClosedSchemaNode -RootSchema $RootSchema -Node $property.Value `
            -Context "$Context.$($property.Name)"
    }
}

function Get-ContainedPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath((Join-Path $rootFull (
        $RelativePath.Replace('/', '\')
    )))
    if (-not $fullPath.StartsWith(
        $rootFull + '\', [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to access a test path outside its repository root."
    }
    return $fullPath
}

function Copy-ContainedFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $source = Get-ContainedPath -Root $SourceRoot -RelativePath $RelativePath
    $destination = Get-ContainedPath -Root $DestinationRoot `
        -RelativePath $RelativePath
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    [IO.File]::Copy($source, $destination, $true)
}

function Write-ContainedText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $path = Get-ContainedPath -Root $Root -RelativePath $RelativePath
    $parent = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    [IO.File]::WriteAllText($path, $Text, $utf8NoBom)
}

function Invoke-TestGit {
    param(
        [string]$Repository = "",
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        if ([string]::IsNullOrWhiteSpace($Repository)) {
            $output = @(& git @Arguments 2>&1)
        }
        else {
            $output = @(& git -C $Repository @Arguments 2>&1)
        }
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

function Invoke-PreflightCli {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass `
            -File $ScriptPath -ProjectRoot $Root -Mode $Mode 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = [object[]]@($output)
    }
}

function Assert-OnlyErrorCode {
    param(
        [Parameter(Mandatory = $true)][object[]]$Output,
        [Parameter(Mandatory = $true)][string]$ExpectedCode,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $text = @($Output | ForEach-Object { [string]$_ }) -join "`n"
    $codes = @(
        [regex]::Matches($text, '\b(?<code>P2D_[A-Z0-9_]+)(?=:)') |
            ForEach-Object { $_.Groups['code'].Value } |
            Select-Object -Unique
    )
    $unexpected = @($codes | Where-Object {
        [string]$_ -cne $ExpectedCode
    })
    Assert-Condition (
        $codes -ccontains $ExpectedCode -and $unexpected.Count -eq 0
    ) "$Label emitted unexpected P2D error codes: $($codes -join ', ')."
}

function Get-NonGitSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $gitPrefix = (Join-Path $rootFull ".git") + '\'
    $records = [Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $rootFull -File -Recurse) {
        $fullPath = [IO.Path]::GetFullPath([string]$file.FullName)
        if ($fullPath.StartsWith(
            $gitPrefix, [StringComparison]::OrdinalIgnoreCase
        )) {
            continue
        }
        $relative = $fullPath.Substring($rootFull.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
        $records.Add("$relative|$($file.Length)|$hash")
    }
    $values = $records.ToArray()
    [Array]::Sort($values, [StringComparer]::Ordinal)
    return $values -join "`n"
}

function Get-DirectorySnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return "<ABSENT>"
    }
    return Get-NonGitSnapshot -Root $Path
}

function New-SyntheticTestRecord {
    param(
        [Parameter(Mandatory = $true)][long]$TestId,
        [Parameter(Mandatory = $true)][string]$TestKind,
        [Parameter(Mandatory = $true)][long]$FixtureId,
        [Parameter(Mandatory = $true)][long]$ValueBase
    )

    $oracleKinds = [object[]]@("FORMULA")
    if ($TestKind -ceq "SCENARIO") {
        $oracleKinds = [object[]]@("FORMULA", "SCENARIO")
    }
    $manifest = [pscustomobject][ordered]@{
            artifact_kind = "TEST_MANIFEST_ENTRY"
            test_id = $TestId
            debug_key = "TEST_SYNTHETIC_$TestId"
            schema_version = 1
            test_kind = $TestKind
            fixture_id = $FixtureId
            coverage_targets = [object[]]@(
                [pscustomobject][ordered]@{
                    mechanism_id = $ValueBase
                    branch_id = $ValueBase + 1
                }
            )
            expected_event_ids = [object[]]@(
                ($ValueBase + 2), ($ValueBase + 3)
            )
            expected_handler_ids = [object[]]@($ValueBase + 4)
            expected_state_op_ids = [object[]]@($ValueBase + 5)
            expected_command_ids = [object[]]@($ValueBase + 6)
            required_oracle_kinds = $oracleKinds
    }
    $validation = Test-P2TestManifestEntry -Entry $manifest
    return [pscustomobject][ordered]@{
        RelativePath = (
            "new-game-project/battle/specs/tests/{0:D10}." +
            "test_manifest_entry.json"
        ) -f $TestId
        Manifest = $manifest
        Validation = [pscustomobject][ordered]@{
            Sha256 = [string]$validation.Sha256
        }
    }
}

function Copy-CanonicalValue {
    param([Parameter(Mandatory = $true)][object]$Value)

    return ConvertFrom-BattleStrictJson `
        -Text (ConvertTo-BattleCanonicalJson -Value $Value) `
        -Label "synthetic preflight clone"
}

function Copy-SyntheticTestRecord {
    param([Parameter(Mandatory = $true)][object]$Source)

    return [pscustomobject][ordered]@{
        RelativePath = [string]$Source.RelativePath
        Manifest = Copy-CanonicalValue -Value $Source.Manifest
        Validation = [pscustomobject][ordered]@{
            Sha256 = [string]$Source.Validation.Sha256
        }
    }
}

function New-SyntheticPreflightCompilation {
    param(
        [Parameter(Mandatory = $true)][object]$BaseCompilation,
        [Parameter(Mandatory = $true)][object[]]$TestEntries
    )

    $specSet = [pscustomobject][ordered]@{
        StableManifestHash = [string]$BaseCompilation.SpecSet.StableManifestHash
        TestEntries = [object[]]@($TestEntries)
        InputSet = Copy-CanonicalValue -Value $BaseCompilation.SpecSet.InputSet
        InputSetHash = ""
    }
    $inputTests = [Collections.Generic.List[object]]::new()
    foreach ($recordValue in @($TestEntries)) {
        $record = [PSCustomObject]$recordValue
        $inputTests.Add([pscustomobject][ordered]@{
            relative_path = [string]$record.RelativePath
            canonical_sha256 = [string]$record.Validation.Sha256
        })
    }
    $specSet.InputSet.test_entries = $inputTests.ToArray()
    $specSet.InputSetHash = Get-BattleSha256Text `
        -Text (ConvertTo-BattleCanonicalJson -Value $specSet.InputSet)

    $compiledTests = [Collections.Generic.List[object]]::new()
    $orderedRecords = @($TestEntries)
    [Array]::Sort($orderedRecords, [Comparison[object]]{
        param($left, $right)
        return [long]$left.Manifest.test_id.CompareTo(
            [long]$right.Manifest.test_id
        )
    })
    foreach ($recordValue in $orderedRecords) {
        $record = [PSCustomObject]$recordValue
        $compiledTests.Add([pscustomobject][ordered]@{
            test_id = [long]$record.Manifest.test_id
            schema_version = [long]$record.Manifest.schema_version
            canonical_authoring_sha256 = [string]$record.Validation.Sha256
        })
    }
    $specManifest = Copy-CanonicalValue -Value $BaseCompilation.SpecManifest
    $specManifest.authoring_input_set_sha256 = [string]$specSet.InputSetHash
    $specManifest.tests = $compiledTests.ToArray()
    $specJson = ConvertTo-BattleCanonicalJson -Value $specManifest
    $specHash = Get-BattleSha256Text -Text $specJson

    $runtimeManifest = Copy-CanonicalValue `
        -Value $BaseCompilation.RuntimeManifest
    $runtimeManifest.spec_manifest_sha256 = $specHash
    $runtimeJson = ConvertTo-BattleCanonicalJson -Value $runtimeManifest
    $runtimeHash = Get-BattleSha256Text -Text $runtimeJson
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    return [pscustomobject][ordered]@{
        CompilerContractVersion = [long]$BaseCompilation.CompilerContractVersion
        SpecSet = $specSet
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

function Copy-SyntheticCompilation {
    param([Parameter(Mandatory = $true)][object]$Source)

    $records = [Collections.Generic.List[object]]::new()
    foreach ($record in @($Source.SpecSet.TestEntries)) {
        $records.Add((Copy-SyntheticTestRecord -Source $record))
    }
    $specSet = [pscustomobject][ordered]@{
        StableManifestHash = [string]$Source.SpecSet.StableManifestHash
        TestEntries = $records.ToArray()
        InputSet = Copy-CanonicalValue -Value $Source.SpecSet.InputSet
        InputSetHash = [string]$Source.SpecSet.InputSetHash
    }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    return [pscustomobject][ordered]@{
        CompilerContractVersion = [long]$Source.CompilerContractVersion
        SpecSet = $specSet
        SpecManifest = Copy-CanonicalValue -Value $Source.SpecManifest
        RuntimeManifest = Copy-CanonicalValue -Value $Source.RuntimeManifest
        SpecManifestJson = [string]$Source.SpecManifestJson
        RuntimeManifestJson = [string]$Source.RuntimeManifestJson
        SpecManifestBytes = $utf8.GetBytes([string]$Source.SpecManifestJson)
        RuntimeManifestBytes = $utf8.GetBytes(
            [string]$Source.RuntimeManifestJson
        )
        SpecManifestHash = [string]$Source.SpecManifestHash
        RuntimeManifestHash = [string]$Source.RuntimeManifestHash
    }
}

foreach ($parsePath in @($supportPath, $cliPath, $PSCommandPath)) {
    $tokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile(
        $parsePath, [ref]$tokens, [ref]$parseErrors
    )
    Assert-Condition ($parseErrors.Count -eq 0) `
        "PowerShell parse failed for '$parsePath': $($parseErrors -join '; ')"
}

$schema = Read-BattleStrictJsonFile -Path $schemaPath `
    -Label "compiled fixture requirement schema"
Assert-Condition ([string]$schema.'$schema' -ceq `
    "https://json-schema.org/draft/2020-12/schema") `
    "Fixture requirement schema does not declare Draft 2020-12."
Assert-Condition ([string]$schema.title -ceq `
    "CompiledFixtureRequirementManifest") `
    "Fixture requirement schema title changed unexpectedly."
Test-ClosedSchemaNode -RootSchema $schema -Node $schema `
    -Context "CompiledFixtureRequirementManifest"

$expectedEmptyManifestHash = (
    "ab8ecfeb6a3c5ba0b1a7147ee06082b6cb174d6c9e95c917f034a74d1c836b59"
)
$expectedEmptySpecHash = (
    "9f35401d489d6a0e55c2514fe8325850dc353c8b907f919fcd30dccfd6a87b57"
)
$expectedEmptyRuntimeHash = (
    "5d3971516b957d9f58986eba6d5b8e741dc8da8b609c234ffb8b7222e00b9d39"
)
$generatedBefore = Get-DirectorySnapshot -Path $generatedRoot
$specBefore = Invoke-P2SpecCompiler -ProjectRoot $ProjectRoot -Mode Repository
$emptyFirst = Invoke-P2FixturePreflight `
    -ProjectRoot $ProjectRoot -Mode Repository
$emptySecond = Invoke-P2FixturePreflight `
    -ProjectRoot $ProjectRoot -Mode Repository
$specAfter = Invoke-P2SpecCompiler -ProjectRoot $ProjectRoot -Mode Repository

Assert-Condition ($emptyFirst.FixtureRequirementCount -eq 0) `
    "Current Repository preflight is not empty."
Assert-Condition ($emptyFirst.ScenarioTestCount -eq 0) `
    "Current Repository preflight found unexpected SCENARIO tests."
Assert-Condition ([string]$emptyFirst.SetupCompilerStatus -ceq "UNAVAILABLE_P7") `
    "Current Repository preflight did not preserve the P7 setup gate."
Assert-Condition ([string]$emptyFirst.ManifestHash -ceq `
    $expectedEmptyManifestHash) "Current empty preflight hash changed."
Assert-Condition ([string]$specBefore.SpecManifestHash -ceq `
    $expectedEmptySpecHash) "Current empty spec hash changed."
Assert-Condition ([string]$specBefore.RuntimeManifestHash -ceq `
    $expectedEmptyRuntimeHash) "Current empty runtime hash changed."
Assert-BytesEqual $emptyFirst.ManifestBytes $emptySecond.ManifestBytes `
    "repeat empty preflight manifest"
Assert-Condition ([string]$emptyFirst.ManifestHash -ceq `
    [string]$emptySecond.ManifestHash) "Repeat preflight hashes differ."
Assert-BytesEqual $specBefore.SpecManifestBytes $specAfter.SpecManifestBytes `
    "spec manifest before and after preflight"
Assert-BytesEqual $specBefore.RuntimeManifestBytes $specAfter.RuntimeManifestBytes `
    "runtime manifest before and after preflight"
Assert-Condition ([string]$specBefore.SpecManifestHash -ceq `
    [string]$specAfter.SpecManifestHash) `
    "Preflight changed the compiled spec hash."
Assert-Condition ([string]$specBefore.RuntimeManifestHash -ceq `
    [string]$specAfter.RuntimeManifestHash) `
    "Preflight changed the runtime catalog hash."
Assert-Condition ([string]$emptyFirst.Compilation.RuntimeManifestHash -ceq `
    [string]$specBefore.RuntimeManifestHash) `
    "Preflight returned a different runtime compilation."
Assert-Condition ($emptyFirst.ManifestBytes[$emptyFirst.ManifestBytes.Length - 1] `
    -eq 0x0a) "Preflight manifest does not end with LF."
Assert-Condition (-not (
    $emptyFirst.ManifestBytes.Length -ge 3 -and
    $emptyFirst.ManifestBytes[0] -eq 0xef -and
    $emptyFirst.ManifestBytes[1] -eq 0xbb -and
    $emptyFirst.ManifestBytes[2] -eq 0xbf
)) "Preflight manifest contains a UTF-8 BOM."
$strictEmpty = ConvertFrom-BattleStrictJson -Text $emptyFirst.ManifestJson `
    -Label "empty fixture requirement manifest"
Assert-ExactPropertySet -Value $strictEmpty -SchemaNode $schema `
    -Label "fixture requirement root"
Assert-Condition ([string]$strictEmpty.artifact_kind -ceq `
    "COMPILED_FIXTURE_REQUIREMENT_MANIFEST") `
    "Fixture requirement artifact kind changed."
Assert-Condition ([string]$strictEmpty.spec_manifest_sha256 -ceq `
    [string]$specBefore.SpecManifestHash) `
    "Preflight manifest is not bound to the spec manifest hash."
Assert-Condition ([string]$strictEmpty.stable_id_manifest_sha256 -ceq `
    [string]$specBefore.SpecSet.StableManifestHash) `
    "Preflight manifest is not bound to the stable-ID manifest hash."

$cliResult = Invoke-PreflightCli -ScriptPath $cliPath `
    -Root $ProjectRoot -Mode Repository
Assert-Condition ($cliResult.ExitCode -eq 0) `
    "Current Repository preflight CLI failed: $($cliResult.Output -join "`n")"
$expectedCliMarker = (
    "P2_FIXTURE_PREFLIGHT_OK mode=Repository fixture_requirements=0 " +
    "scenario_tests=0 manifest_sha256=$expectedEmptyManifestHash " +
    "spec_sha256=$expectedEmptySpecHash setup_compiler_status=UNAVAILABLE_P7"
)
Assert-Condition (
    @($cliResult.Output | ForEach-Object { [string]$_ }) -ccontains
        $expectedCliMarker
) "Current Repository CLI did not emit its exact success marker."
Assert-Condition ((Get-DirectorySnapshot -Path $generatedRoot) -ceq `
    $generatedBefore) "No-write Repository preflight created an artifact."

$scenarioTen = New-SyntheticTestRecord -TestId 10 -TestKind "SCENARIO" `
    -FixtureId 10 -ValueBase 100
$scenarioTwo = New-SyntheticTestRecord -TestId 2 -TestKind "SCENARIO" `
    -FixtureId 2 -ValueBase 20
$unitOne = New-SyntheticTestRecord -TestId 1 -TestKind "FORMULA_UNIT" `
    -FixtureId 0 -ValueBase 200
$syntheticCompilation = New-SyntheticPreflightCompilation `
    -BaseCompilation $specBefore `
    -TestEntries @($scenarioTen, $unitOne, $scenarioTwo)
$syntheticSourceBefore = ConvertTo-BattleCanonicalJson `
    $syntheticCompilation.SpecSet.TestEntries
$syntheticSpecHashBefore = [string]$syntheticCompilation.SpecManifestHash
$syntheticRuntimeHashBefore = [string]$syntheticCompilation.RuntimeManifestHash
$coreFirst = Invoke-P2ValidatedFixturePreflightCore `
    -Compilation $syntheticCompilation
$coreSecond = Invoke-P2ValidatedFixturePreflightCore `
    -Compilation $syntheticCompilation

Assert-Condition ($coreFirst.FixtureRequirementCount -eq 2) `
    "Synthetic core did not project exactly two SCENARIO requirements."
Assert-Condition ($coreFirst.ScenarioTestCount -eq 2) `
    "Synthetic core counted a non-SCENARIO test."
Assert-Condition (
    (@($coreFirst.Manifest.fixture_requirements | ForEach-Object {
        [long]$_.fixture_id
    }) -join ',') -ceq '2,10'
) "Fixture requirements are not sorted by numeric fixture ID."
Assert-BytesEqual $coreFirst.ManifestBytes $coreSecond.ManifestBytes `
    "repeat synthetic preflight manifest"
Assert-Condition ([string]$coreFirst.ManifestHash -ceq `
    [string]$coreSecond.ManifestHash) `
    "Repeat synthetic preflight hashes differ."
Assert-Condition ((ConvertTo-BattleCanonicalJson `
    $syntheticCompilation.SpecSet.TestEntries) -ceq `
    $syntheticSourceBefore) "Preflight mutated synthetic test declarations."
Assert-Condition (
    @($coreFirst.Manifest.fixture_requirements | Where-Object {
        [long]$_.test_id -eq 1
    }).Count -eq 0
) "Non-SCENARIO test was included in fixture requirements."
$projectedTwo = [PSCustomObject]$coreFirst.Manifest.fixture_requirements[0]
Assert-ExactPropertySet -Value $projectedTwo `
    -SchemaNode $schema.'$defs'.fixture_requirement `
    -Label "synthetic fixture requirement"
Assert-ExactPropertySet `
    -Value ([PSCustomObject]$projectedTwo.coverage_targets[0]) `
    -SchemaNode $schema.'$defs'.coverage_target `
    -Label "synthetic coverage target"
Assert-Condition (
    [long]$projectedTwo.fixture_id -eq 2 -and
    [long]$projectedTwo.test_id -eq 2
) "Synthetic SCENARIO identity projection changed."
Assert-Condition (
    [long]$projectedTwo.coverage_targets[0].mechanism_id -eq 20 -and
    [long]$projectedTwo.coverage_targets[0].branch_id -eq 21
) "Synthetic coverage projection changed."
Assert-Condition (
    (@($projectedTwo.expected_event_ids) -join ',') -ceq '22,23' -and
    (@($projectedTwo.expected_handler_ids) -join ',') -ceq '24' -and
    (@($projectedTwo.expected_state_op_ids) -join ',') -ceq '25' -and
    (@($projectedTwo.expected_command_ids) -join ',') -ceq '26'
) "Synthetic expected-ID projection changed."
Assert-Condition (
    (@($projectedTwo.required_oracle_kinds) -join ',') -ceq
        'FORMULA,SCENARIO'
) "Synthetic oracle projection changed."
Assert-Condition ([string]$coreFirst.Manifest.spec_manifest_sha256 -ceq `
    $syntheticSpecHashBefore) `
    "Synthetic preflight changed its source spec hash."
Assert-Condition ([string]$syntheticCompilation.SpecManifestHash -ceq `
    $syntheticSpecHashBefore) "Synthetic preflight mutated the spec hash."
Assert-Condition ([string]$syntheticCompilation.RuntimeManifestHash -ceq `
    $syntheticRuntimeHashBefore) "Synthetic preflight mutated the runtime hash."

$mismatchCompilation = Copy-SyntheticCompilation $syntheticCompilation
$mismatchRecord = @($mismatchCompilation.SpecSet.TestEntries | Where-Object {
    [long]$_.Manifest.test_id -eq 2
})[0]
$mismatchRecord.Manifest.fixture_id = 8
Assert-ThrowsCode -Label "fixture/test identity mismatch" `
    -Code "P2_TEST_SCENARIO_FIXTURE" -Action {
        Invoke-P2ValidatedFixturePreflightCore `
            -Compilation $mismatchCompilation
    }
$duplicateCompilation = Copy-SyntheticCompilation $syntheticCompilation
$duplicateRecord = Copy-CanonicalValue -Value @(
    $duplicateCompilation.SpecSet.TestEntries | Where-Object {
        [long]$_.Manifest.test_id -eq 2
    }
)[0]
$duplicateCompilation.SpecSet.TestEntries = [object[]]@(
    @($duplicateCompilation.SpecSet.TestEntries) + $duplicateRecord
)
Assert-ThrowsCode -Label "duplicate fixture identity" `
    -Code "P2D_TEST_ID_DUPLICATE" -Action {
        Invoke-P2ValidatedFixturePreflightCore `
            -Compilation $duplicateCompilation
    }

$forgedInputCompilation = Copy-SyntheticCompilation $syntheticCompilation
$forgedInputCompilation.SpecSet.InputSet.test_entries[0].canonical_sha256 = `
    "0" * 64
Assert-ThrowsCode -Label "forged input-set hash" `
    -Code "P2D_INPUT_SET_HASH" -Action {
        Invoke-P2ValidatedFixturePreflightCore `
            -Compilation $forgedInputCompilation
    }
$forgedRecordCompilation = Copy-SyntheticCompilation $syntheticCompilation
$forgedRecordCompilation.SpecSet.TestEntries[0].Validation.Sha256 = "1" * 64
Assert-ThrowsCode -Label "forged test validation hash" `
    -Code "P2D_TEST_VALIDATION_HASH" -Action {
        Invoke-P2ValidatedFixturePreflightCore `
            -Compilation $forgedRecordCompilation
    }
$noncanonicalCompilation = Copy-SyntheticCompilation $syntheticCompilation
$noncanonicalCompilation.SpecManifestJson = `
    [string]$noncanonicalCompilation.SpecManifestJson + " "
Assert-ThrowsCode -Label "noncanonical compiled spec JSON" `
    -Code "P2D_SPEC_MANIFEST_CANONICAL" -Action {
        Invoke-P2ValidatedFixturePreflightCore `
            -Compilation $noncanonicalCompilation
    }

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$tempRoot = Join-Path $tempParent (
    "maizang-p2d-fixture-preflight-" + [Guid]::NewGuid().ToString("N")
)
$null = New-Item -ItemType Directory -Path $tempRoot
try {
    $seedRoot = Join-Path $tempRoot "seed"
    $null = Invoke-TestGit -Arguments @(
        "clone", "--quiet", "--no-local", "--", $ProjectRoot, $seedRoot
    )
    foreach ($relativePath in @(
        $supportRelative, $cliRelative, $schemaRelative
    )) {
        Copy-ContainedFile -SourceRoot $ProjectRoot `
            -DestinationRoot $seedRoot -RelativePath $relativePath
    }
    $null = Invoke-TestGit -Repository $seedRoot `
        -Arguments @("config", "user.name", "Battle Fixture Test")
    $null = Invoke-TestGit -Repository $seedRoot `
        -Arguments @("config", "user.email", "battle-test@example.invalid")
    $seedChanges = @(Invoke-TestGit -Repository $seedRoot -Arguments @(
        "status", "--porcelain", "--", $supportRelative, $cliRelative,
        $schemaRelative
    ))
    if ($seedChanges.Count -gt 0) {
        $null = Invoke-TestGit -Repository $seedRoot -Arguments @(
            "add", "--", $supportRelative, $cliRelative, $schemaRelative
        )
        $null = Invoke-TestGit -Repository $seedRoot -Arguments @(
            "commit", "--quiet", "-m", "Add fixture preflight surface"
        )
    }
    Assert-Condition (
        @(Invoke-TestGit -Repository $seedRoot `
            -Arguments @("status", "--porcelain")).Count -eq 0
    ) "Temporary seed repository is not clean."

    $viewCases = @(
        [pscustomobject]@{
            Mode = "Repository"
            RelativePath = (
                "new-game-project/battle/fixtures/synthetic/scenarios/" +
                "repository/opaque.payload"
            )
            GitState = "COMMITTED"
        },
        [pscustomobject]@{
            Mode = "Worktree"
            RelativePath = (
                "new-game-project/battle/fixtures/synthetic/scenarios/" +
                "worktree/arbitrary.txt"
            )
            GitState = "UNTRACKED"
        },
        [pscustomobject]@{
            Mode = "Staged"
            RelativePath = (
                "new-game-project/battle/fixtures/synthetic/scenarios/" +
                "staged/deep/arbitrary.bin"
            )
            GitState = "STAGED"
        }
    )
    foreach ($case in $viewCases) {
        $caseRoot = Join-Path $tempRoot ([string]$case.Mode).ToLowerInvariant()
        $null = Invoke-TestGit -Arguments @(
            "clone", "--quiet", "--no-local", "--", $seedRoot, $caseRoot
        )
        Assert-Condition (
            @(Invoke-TestGit -Repository $caseRoot `
                -Arguments @("status", "--porcelain")).Count -eq 0
        ) "$($case.Mode) temporary clone did not start clean."
        $null = Invoke-TestGit -Repository $caseRoot `
            -Arguments @("config", "user.name", "Battle Fixture Test")
        $null = Invoke-TestGit -Repository $caseRoot `
            -Arguments @("config", "user.email", "battle-test@example.invalid")
        Write-ContainedText -Root $caseRoot `
            -RelativePath $case.RelativePath `
            -Text "synthetic pre-P7 fixture sentinel`n"

        if ([string]$case.GitState -ceq "COMMITTED") {
            $null = Invoke-TestGit -Repository $caseRoot `
                -Arguments @("add", "--", $case.RelativePath)
            $null = Invoke-TestGit -Repository $caseRoot -Arguments @(
                "commit", "--quiet", "-m", "Add repository fixture sentinel"
            )
            Assert-Condition (
                @(Invoke-TestGit -Repository $caseRoot `
                    -Arguments @("status", "--porcelain")).Count -eq 0
            ) "Repository fixture clone was not clean after its fixture commit."
        }
        elseif ([string]$case.GitState -ceq "STAGED") {
            $null = Invoke-TestGit -Repository $caseRoot `
                -Arguments @("add", "--", $case.RelativePath)
            $stagedPaths = @(Invoke-TestGit -Repository $caseRoot `
                -Arguments @("diff", "--cached", "--name-only", "--"))
            Assert-Condition (
                $stagedPaths.Count -eq 1 -and
                [string]$stagedPaths[0] -ceq [string]$case.RelativePath
            ) "Staged fixture clone did not contain exactly its sentinel."
        }
        else {
            $worktreeStatus = @(Invoke-TestGit -Repository $caseRoot `
                -Arguments @("status", "--porcelain", "--", $case.RelativePath))
            Assert-Condition (
                $worktreeStatus.Count -eq 1 -and
                [string]$worktreeStatus[0] -ceq "?? $($case.RelativePath)"
            ) "Worktree fixture clone did not contain exactly its sentinel."
        }

        $caseBefore = Get-NonGitSnapshot -Root $caseRoot
        $caseGenerated = Join-Path $caseRoot `
            "new-game-project\battle\generated"
        Assert-Condition (-not (Test-Path -LiteralPath $caseGenerated)) `
            "$($case.Mode) clone had a generated artifact root before preflight."
        $caseCli = Get-ContainedPath -Root $caseRoot -RelativePath $cliRelative
        $failure = Invoke-PreflightCli -ScriptPath $caseCli `
            -Root $caseRoot -Mode $case.Mode
        Assert-Condition ($failure.ExitCode -ne 0) `
            "$($case.Mode) preflight accepted a pre-P7 scenario fixture."
        Assert-OnlyErrorCode -Output $failure.Output `
            -ExpectedCode "P2D_SETUP_COMPILER_UNAVAILABLE_P7" `
            -Label "$($case.Mode) fixture rejection"
        Assert-Condition ((Get-NonGitSnapshot -Root $caseRoot) -ceq `
            $caseBefore) "$($case.Mode) fixture rejection wrote an artifact."
        Assert-Condition (-not (Test-Path -LiteralPath $caseGenerated)) `
            "$($case.Mode) fixture rejection created generated output."
    }
}
finally {
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot).TrimEnd('\')
    if (-not $resolvedTempRoot.StartsWith(
        $tempParent + '\', [StringComparison]::OrdinalIgnoreCase
    ) -or -not ([IO.Path]::GetFileName($resolvedTempRoot)).StartsWith(
        "maizang-p2d-fixture-preflight-", [StringComparison]::Ordinal
    )) {
        throw "Refusing to remove a test directory outside the system temp root."
    }
    if (Test-Path -LiteralPath $resolvedTempRoot) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}

Write-Host "P2_FIXTURE_PREFLIGHT_TEST_OK checks=$checks"
