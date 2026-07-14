[CmdletBinding()]
param([string]$ProjectRoot = "")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battleRoot = Join-Path $ProjectRoot "new-game-project\battle"
$supportPath = Join-Path $battleRoot (
    "tools\battle_specs\compilers\p2_source_evidence_join_support.ps1"
)
$cliPath = Join-Path $battleRoot (
    "tools\battle_specs\compilers\compile_p2_source_evidence_join.ps1"
)
$evidenceSchemaPath = Join-Path $battleRoot (
    "tools\battle_specs\schemas\source_evidence.schema.json"
)
$joinSchemaPath = Join-Path $battleRoot (
    "tools\battle_specs\schemas\compiled_source_evidence_join_manifest." +
    "schema.json"
)
$script:checks = 0
$script:battleCommit = "1111111111111111111111111111111111111111"
$script:battleTree = "2222222222222222222222222222222222222222"
$script:pokelibCommit = "3333333333333333333333333333333333333333"
$script:pokelibTree = "4444444444444444444444444444444444444444"

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

function Assert-ThrowsCode {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Label,
        [string]$MessageFragment = ""
    )

    $caught = $null
    try {
        $null = & $Action
    }
    catch {
        $caught = $_
    }
    Assert-Condition ($null -ne $caught) "$Label did not fail."
    $message = [string]$caught.Exception.Message
    $actualCode = $message.Split(':')[0]
    Assert-Condition ($actualCode -ceq $Code) (
        "$Label failed with '$actualCode' instead of '$Code': $message"
    )
    if (-not [string]::IsNullOrEmpty($MessageFragment)) {
        Assert-Condition ($message.IndexOf(
            $MessageFragment, [StringComparison]::Ordinal
        ) -ge 0) "$Label did not identify '$MessageFragment': $message"
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

function Assert-ExactPropertySet {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Value,
        [Parameter(Mandatory = $true)][PSCustomObject]$SchemaNode,
        [Parameter(Mandatory = $true)][string]$Label
    )

    [string[]]$actual = @($Value.PSObject.Properties.Name)
    [string[]]$required = @(
        $SchemaNode.required | ForEach-Object { [string]$_ }
    )
    [Array]::Sort($actual, [StringComparer]::Ordinal)
    [Array]::Sort($required, [StringComparer]::Ordinal)
    Assert-Condition (($actual -join "`n") -ceq ($required -join "`n")) `
        "$Label does not exactly match its closed schema property set."
}

function Assert-FlatSchemaArray {
    param(
        [AllowNull()][object]$Value,
        [AllowEmptyCollection()][object[]]$Expected,
        [ValidateSet("ID", "BLOCKER")][string]$ItemKind,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Assert-Condition ($null -ne $Value -and $Value -is [Array]) `
        "$Label is not an array."
    $actual = @($Value)
    Assert-Condition ($actual.Count -eq $Expected.Count) `
        "$Label count $($actual.Count) differs from $($Expected.Count)."
    for ($index = 0; $index -lt $actual.Count; $index++) {
        Assert-Condition ($actual[$index] -isnot [Array]) `
            "$Label item $index is a nested array."
        if ($ItemKind -ceq "ID") {
            Assert-Condition ((Test-P2IntegralType $actual[$index]) -and `
                [long]$actual[$index] -gt 0) `
                "$Label item $index is not a positive stable ID."
            Assert-Condition ([long]$actual[$index] -eq `
                [long]$Expected[$index]) `
                "$Label item $index differs from the expected ID."
        }
        else {
            Assert-Condition ($actual[$index] -is [string] -and `
                [string]$actual[$index] -cmatch '^[A-Z][A-Z0-9_]*$') `
                "$Label item $index is not a blocker code."
            Assert-Condition ([string]$actual[$index] -ceq `
                [string]$Expected[$index]) `
                "$Label item $index differs from the expected blocker."
        }
    }
}

function Test-ClosedFiniteSchemaNode {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$RootSchema,
        [AllowNull()][object]$Node,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($null -eq $Node) { return }
    if ($Node -is [Array]) {
        $items = @($Node)
        for ($index = 0; $index -lt $items.Count; $index++) {
            Test-ClosedFiniteSchemaNode -RootSchema $RootSchema `
                -Node $items[$index] -Context "$Context[$index]"
        }
        return
    }
    if ($Node -isnot [PSCustomObject]) { return }

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
        [string[]]$requiredNames = @(
            $Node.required | ForEach-Object { [string]$_ }
        )
        [string[]]$propertyNames = @($Node.properties.PSObject.Properties.Name)
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
        Test-ClosedFiniteSchemaNode -RootSchema $RootSchema `
            -Node $property.Value -Context "$Context.$($property.Name)"
    }
}

function Copy-CanonicalValue {
    param([Parameter(Mandatory = $true)][object]$Value)

    return ConvertFrom-BattleStrictJson `
        -Text (ConvertTo-BattleCanonicalJson -Value $Value) `
        -Label "synthetic SourceEvidence clone"
}

function Get-SyntheticAuditId {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Symbol
    )

    $identity = "$Repository`t$Category`t$Path`t$Symbol"
    return "AUDIT_" + (
        Get-BattleSha256Text -Text $identity
    ).Substring(0, 16).ToUpperInvariant()
}

function New-SyntheticClaim {
    param(
        [long]$MechanismId = 1,
        [long]$BranchId = 0,
        [string]$Pointer = "/ruleset_mode",
        [string]$Summary = "SYNTHETIC_CLAIM_TOKEN"
    )

    return [pscustomobject][ordered]@{
        mechanism_id = $MechanismId
        branch_id = $BranchId
        spec_field_pointer = $Pointer
        claim_summary = $Summary
    }
}

function New-SyntheticEvidence {
    param(
        [long]$Id = 1,
        [long]$Version = 1,
        [string]$Status = "ACTIVE",
        [string]$SourceKind = "SOURCE_CODE",
        [string]$Repository = "battlelogic",
        [string]$Category = "SECTION",
        [string]$Path = "programs/src/secret_section.cpp",
        [string]$Symbol = "SecretSection",
        [string]$Revision = "",
        [string]$FileHash = "",
        [AllowNull()][object[]]$Claims = $null,
        [string]$Confidence = "HIGH",
        [string]$ReviewStatus = "VERIFIED"
    )

    if ([string]::IsNullOrEmpty($Revision)) {
        $Revision = if ($Repository -ceq "pokelib") {
            $script:pokelibCommit
        }
        else {
            $script:battleCommit
        }
    }
    if ([string]::IsNullOrEmpty($FileHash)) {
        $FileHash = Get-BattleSha256Text -Text "$Repository/$Path/$Symbol"
    }
    if ($null -eq $Claims -and $Status -ceq "TOMBSTONE") {
        $claimValues = [Array]::CreateInstance([object], 0)
    }
    elseif ($null -eq $Claims) {
        $claimValues = [object[]]@(New-SyntheticClaim)
    }
    else {
        $claimValues = [object[]]@($Claims)
    }
    $auditId = Get-SyntheticAuditId -Repository $Repository `
        -Category $Category -Path $Path -Symbol $Symbol
    return [pscustomobject][ordered]@{
        artifact_kind = "SOURCE_EVIDENCE"
        evidence_id = $Id
        evidence_version = $Version
        status = $Status
        source_audit_id = $auditId
        source_kind = $SourceKind
        source_repository = $Repository
        source_category = $Category
        source_revision = $Revision
        source_relative_path = $Path
        symbol_or_record_key = $Symbol
        line_anchor_at_scan_time = 17
        file_sha256 = $FileHash
        observation_summary = "SENSITIVE_OBSERVATION_TOKEN"
        behavior_claims = $claimValues
        confidence = $Confidence
        known_ambiguities = [object[]]@("Synthetic ambiguity retained")
        review_status = $ReviewStatus
        license_boundary = "BEHAVIOR_EVIDENCE_ONLY"
    }
}

function New-SyntheticEvidenceHistoryRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Evidence,
        [long]$FilenameId = 0
    )

    if ($FilenameId -eq 0) {
        $FilenameId = [long]$Evidence.evidence_id
    }
    return [pscustomobject][ordered]@{
        Path = (
            "new-game-project/battle/specs/evidence/{0:D10}." +
            "source_evidence.json"
        ) -f $FilenameId
        Evidence = $Evidence
    }
}

function New-SyntheticEvidenceHistoryView {
    param(
        [AllowEmptyCollection()][object[]]$CandidateRecords = @(),
        [AllowEmptyCollection()][object[]]$BaselineRecords = @()
    )

    $candidateEntries = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    $baselineEntries = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    foreach ($record in $CandidateRecords) {
        $candidateEntries.Add(
            [string]$record.Path,
            [byte[]]$utf8.GetBytes((
                ConvertTo-BattleCanonicalJson -Value $record.Evidence
            ))
        )
    }
    foreach ($record in $BaselineRecords) {
        $baselineEntries.Add(
            [string]$record.Path,
            [byte[]]$utf8.GetBytes((
                ConvertTo-BattleCanonicalJson -Value $record.Evidence
            ))
        )
    }
    return [pscustomobject][ordered]@{
        ViewKind = "P2_REPOSITORY_VIEW"
        Mode = "Worktree"
        CandidateEntries = $candidateEntries
        BaselineEntries = $baselineEntries
    }
}

function New-SyntheticMechanism {
    param(
        [long]$Id = 1,
        [long[]]$EvidenceIds = @(1),
        [long[]]$BranchIds = @(7),
        [string[]]$ProjectRequirementKeys = @()
    )

    $targets = [Collections.Generic.List[object]]::new()
    foreach ($branchId in $BranchIds) {
        $targets.Add([pscustomobject][ordered]@{
            branch_id = $branchId
            kind = "NORMAL"
        })
    }
    return [pscustomobject][ordered]@{
        mechanism_id = $Id
        evidence_ids = [long[]]$EvidenceIds
        project_requirement_keys = [string[]]$ProjectRequirementKeys
        coverage_targets = $targets.ToArray()
        ruleset_mode = "ALL"
        inputs = [object[]]@(
            [pscustomobject][ordered]@{ field_name = "synthetic_input" }
        )
    }
}

function New-SyntheticGovernance {
    $repositories = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    $repositories.Add("battlelogic", [pscustomobject][ordered]@{
        commit = $script:battleCommit
        head_tree = $script:battleTree
    })
    $repositories.Add("pokelib", [pscustomobject][ordered]@{
        commit = $script:pokelibCommit
        head_tree = $script:pokelibTree
    })
    $seal = [pscustomobject][ordered]@{
        scope_id = "MAIZANG_GEN9_SINGLE_PLAYER_TEXT_V1"
        source_audit_manifest_sha256 = Get-BattleSha256Text `
            -Text "synthetic audit manifest"
    }
    return [pscustomobject][ordered]@{
        Seal = $seal
        SealHash = Get-BattleSha256Text `
            -Text (ConvertTo-BattleCanonicalJson -Value $seal)
        Repositories = $repositories
    }
}

function New-SyntheticAuditEntry {
    param(
        [Parameter(Mandatory = $true)][object]$Evidence,
        [string]$EvidenceStatus = "CLEAN_INDEXED",
        [string]$ScopeDisposition = "IMPLEMENT",
        [string]$TestDisposition = "NOT_APPLICABLE"
    )

    return [pscustomobject][ordered]@{
        audit_id = [string]$Evidence.source_audit_id
        source_repository = [string]$Evidence.source_repository
        source_category = [string]$Evidence.source_category
        source_path = [string]$Evidence.source_relative_path
        source_symbol_or_edge = [string]$Evidence.symbol_or_record_key
        source_sha256 = [string]$Evidence.file_sha256
        evidence_status = $EvidenceStatus
        scope_disposition = $ScopeDisposition
        test_evidence_disposition = $TestDisposition
    }
}

function New-SyntheticAuditValidation {
    param([Parameter(Mandatory = $true)][object[]]$Entries)

    $byId = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($entry in $Entries) {
        $byId.Add([string]$entry.audit_id, $entry)
    }
    return [pscustomobject][ordered]@{ AuditById = $byId }
}

function New-SyntheticEvidenceSet {
    param([Parameter(Mandatory = $true)][object[]]$Evidence)

    $records = [Collections.Generic.List[object]]::new()
    $inputs = [Collections.Generic.List[object]]::new()
    foreach ($manifest in $Evidence) {
        $validation = Test-P2SourceEvidence -Evidence $manifest
        $records.Add([pscustomobject][ordered]@{
            RelativePath = (
                "new-game-project/battle/specs/evidence/{0:D10}." +
                "source_evidence.json"
            ) -f [long]$validation.PrimaryId
            Manifest = $manifest
            Validation = $validation
        })
        $inputs.Add([pscustomobject][ordered]@{
            evidence_id = [long]$validation.PrimaryId
            canonical_sha256 = [string]$validation.Sha256
        })
    }
    [object[]]$sortedInputs = @($inputs.ToArray())
    [Array]::Sort($sortedInputs, [Comparison[object]]{
        param($left, $right)
        return [long]$left.evidence_id.CompareTo([long]$right.evidence_id)
    })
    $inputSet = [pscustomobject][ordered]@{
        schema_version = 1
        source_evidence = $sortedInputs
    }
    return [pscustomobject][ordered]@{
        Records = $records.ToArray()
        InputSetHash = Get-BattleSha256Text `
            -Text (ConvertTo-BattleCanonicalJson -Value $inputSet)
    }
}

function New-SyntheticCompilation {
    param([Parameter(Mandatory = $true)][object[]]$Mechanisms)

    $records = [Collections.Generic.List[object]]::new()
    $inputs = [Collections.Generic.List[object]]::new()
    foreach ($mechanism in $Mechanisms) {
        $records.Add([pscustomobject][ordered]@{ Manifest = $mechanism })
        $inputs.Add([pscustomobject][ordered]@{
            mechanism_id = [long]$mechanism.mechanism_id
            canonical_sha256 = Get-BattleSha256Text `
                -Text (ConvertTo-BattleCanonicalJson -Value $mechanism)
        })
    }
    [object[]]$sortedInputs = @($inputs.ToArray())
    [Array]::Sort($sortedInputs, [Comparison[object]]{
        param($left, $right)
        return [long]$left.mechanism_id.CompareTo([long]$right.mechanism_id)
    })
    $inputSet = [pscustomobject][ordered]@{
        schema_version = 1
        mechanisms = $sortedInputs
    }
    $inputHash = Get-BattleSha256Text `
        -Text (ConvertTo-BattleCanonicalJson -Value $inputSet)
    $specManifest = [pscustomobject][ordered]@{
        artifact_kind = "SYNTHETIC_SPEC_MANIFEST"
        authoring_input_set_sha256 = $inputHash
        mechanisms = $sortedInputs
    }
    $specHash = Get-BattleSha256Text `
        -Text (ConvertTo-BattleCanonicalJson -Value $specManifest)
    $runtimeManifest = [pscustomobject][ordered]@{
        artifact_kind = "SYNTHETIC_RUNTIME_MANIFEST"
        spec_manifest_sha256 = $specHash
    }
    return [pscustomobject][ordered]@{
        CompilerContractVersion = [long]$script:P2CompilerContractVersion
        SpecSet = [pscustomobject][ordered]@{
            MechanismSpecs = $records.ToArray()
            InputSetHash = $inputHash
        }
        SpecManifestHash = $specHash
        RuntimeManifestHash = Get-BattleSha256Text `
            -Text (ConvertTo-BattleCanonicalJson -Value $runtimeManifest)
    }
}

function Invoke-SyntheticJoin {
    param(
        [Parameter(Mandatory = $true)][object[]]$Evidence,
        [Parameter(Mandatory = $true)][object[]]$Mechanisms,
        [AllowNull()][object[]]$AuditEntries = $null
    )

    if ($null -eq $AuditEntries) {
        $AuditEntries = @(
            $Evidence | ForEach-Object { New-SyntheticAuditEntry -Evidence $_ }
        )
    }
    return Invoke-P2ValidatedSourceEvidenceJoinCore `
        -Compilation (New-SyntheticCompilation -Mechanisms $Mechanisms) `
        -EvidenceSet (New-SyntheticEvidenceSet -Evidence $Evidence) `
        -Governance (New-SyntheticGovernance) `
        -AuditValidation (New-SyntheticAuditValidation -Entries $AuditEntries)
}

function Invoke-EvidenceJoinCli {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass `
            -File $cliPath -ProjectRoot $ProjectRoot -Mode Repository 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject][ordered]@{
        ExitCode = $exitCode
        Output = [string[]]@($output | ForEach-Object { [string]$_ })
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

$evidenceSchema = Read-BattleStrictJsonFile -Path $evidenceSchemaPath `
    -Label "SourceEvidence schema"
$joinSchema = Read-BattleStrictJsonFile -Path $joinSchemaPath `
    -Label "compiled SourceEvidence join schema"
foreach ($schemaCase in @(
    [pscustomobject]@{
        Schema = $evidenceSchema
        Title = "SourceEvidence"
    },
    [pscustomobject]@{
        Schema = $joinSchema
        Title = "CompiledSourceEvidenceJoinManifest"
    }
)) {
    Assert-Condition ([string]$schemaCase.Schema.'$schema' -ceq `
        "https://json-schema.org/draft/2020-12/schema") `
        "$($schemaCase.Title) does not declare Draft 2020-12."
    Assert-Condition ([string]$schemaCase.Schema.title -ceq `
        [string]$schemaCase.Title) "$($schemaCase.Title) title changed."
    Test-ClosedFiniteSchemaNode -RootSchema $schemaCase.Schema `
        -Node $schemaCase.Schema -Context $schemaCase.Title
}

$expectedJoinHash = (
    "ac1277e109e28492a380656c8c39d783bfd464aca5251cd78d1edf30d99313fe"
)
$expectedSpecHash = (
    "9f35401d489d6a0e55c2514fe8325850dc353c8b907f919fcd30dccfd6a87b57"
)
$expectedRuntimeHash = (
    "5d3971516b957d9f58986eba6d5b8e741dc8da8b609c234ffb8b7222e00b9d39"
)
$expectedEvidenceInputHash = (
    "a07e6384acd2d662315e412856053b2c6b9404b0fc7083e262cefd8884572e33"
)
$expectedCliMarker = (
    "P2_SOURCE_EVIDENCE_JOIN_OK mode=Repository evidence=0 current=0 " +
    "mechanisms=0 join_sha256=$expectedJoinHash"
)
$specBefore = Invoke-P2SpecCompiler -ProjectRoot $ProjectRoot -Mode Repository
$emptyFirst = Invoke-P2SourceEvidenceJoin `
    -ProjectRoot $ProjectRoot -Mode Repository
$emptySecond = Invoke-P2SourceEvidenceJoin `
    -ProjectRoot $ProjectRoot -Mode Repository
$specAfter = Invoke-P2SpecCompiler -ProjectRoot $ProjectRoot -Mode Repository

Assert-Condition ([string]$emptyFirst.ManifestHash -ceq $expectedJoinHash) `
    "Current empty SourceEvidence join hash changed."
Assert-Condition ([string]$emptyFirst.Compilation.SpecManifestHash -ceq `
    $expectedSpecHash) "Current empty spec hash changed."
Assert-Condition ([string]$emptyFirst.Compilation.RuntimeManifestHash -ceq `
    $expectedRuntimeHash) "Current empty runtime hash changed."
Assert-Condition ([string]$emptyFirst.EvidenceSet.InputSetHash -ceq `
    $expectedEvidenceInputHash) "Current empty evidence input hash changed."
Assert-Condition ($emptyFirst.EvidenceRecordCount -eq 0) `
    "Repository join found unexpected SourceEvidence."
Assert-Condition ($emptyFirst.CurrentEvidenceCount -eq 0) `
    "Repository join found unexpected current evidence."
Assert-Condition ($emptyFirst.MechanismCount -eq 0) `
    "Repository join found unexpected mechanisms."
Assert-BytesEqual $emptyFirst.ManifestBytes $emptySecond.ManifestBytes `
    "repeat empty SourceEvidence join"
Assert-Condition ([string]$emptyFirst.ManifestHash -ceq `
    [string]$emptySecond.ManifestHash) "Repeat empty join hashes differ."
Assert-BytesEqual $specBefore.SpecManifestBytes $specAfter.SpecManifestBytes `
    "spec manifest before and after evidence join"
Assert-BytesEqual $specBefore.RuntimeManifestBytes `
    $specAfter.RuntimeManifestBytes "runtime manifest before and after evidence join"
Assert-Condition ([string]$specBefore.SpecManifestHash -ceq `
    [string]$specAfter.SpecManifestHash) "Evidence join changed the spec hash."
Assert-Condition ([string]$specBefore.RuntimeManifestHash -ceq `
    [string]$specAfter.RuntimeManifestHash) "Evidence join changed the runtime hash."
Assert-Condition ([string]$emptyFirst.Compilation.SpecManifestHash -ceq `
    [string]$specBefore.SpecManifestHash) `
    "Evidence join returned a different spec compilation."
Assert-Condition ([string]$emptyFirst.Compilation.RuntimeManifestHash -ceq `
    [string]$specBefore.RuntimeManifestHash) `
    "Evidence join returned a different runtime compilation."
Assert-Condition ($emptyFirst.ManifestBytes[$emptyFirst.ManifestBytes.Length - 1] `
    -eq 0x0a) "Evidence join manifest does not end with LF."
Assert-Condition (-not (
    $emptyFirst.ManifestBytes.Length -ge 3 -and
    $emptyFirst.ManifestBytes[0] -eq 0xef -and
    $emptyFirst.ManifestBytes[1] -eq 0xbb -and
    $emptyFirst.ManifestBytes[2] -eq 0xbf
)) "Evidence join manifest contains a UTF-8 BOM."
$strictEmpty = ConvertFrom-BattleStrictJson -Text $emptyFirst.ManifestJson `
    -Label "empty SourceEvidence join manifest"
Assert-ExactPropertySet -Value $strictEmpty -SchemaNode $joinSchema `
    -Label "SourceEvidence join root"
Assert-ExactPropertySet -Value $strictEmpty.counts `
    -SchemaNode $joinSchema.'$defs'.counts -Label "SourceEvidence join counts"
Assert-Condition ([string]$strictEmpty.artifact_kind -ceq `
    "COMPILED_SOURCE_EVIDENCE_JOIN_MANIFEST") `
    "Evidence join artifact kind changed."
Assert-Condition ([long]$strictEmpty.schema_version -eq 1 -and `
    [long]$strictEmpty.join_contract_version -eq 1 -and `
    [long]$strictEmpty.source_spec_compiler_contract_version -eq 1) `
    "Evidence join contract versions changed."
Assert-Condition ([string]$strictEmpty.scope_id -ceq `
    "MAIZANG_GEN9_SINGLE_PLAYER_TEXT_V1") "Evidence join scope changed."
Assert-Condition ([string]$strictEmpty.spec_manifest_sha256 -ceq `
    $expectedSpecHash) "Evidence join does not bind the spec hash."
Assert-Condition ([string]$strictEmpty.evidence_input_set_sha256 -ceq `
    $expectedEvidenceInputHash) "Evidence join does not bind its evidence set."
foreach ($countProperty in $strictEmpty.counts.PSObject.Properties) {
    Assert-Condition ([long]$countProperty.Value -eq 0) `
        "Empty join count '$($countProperty.Name)' is not zero."
}
Assert-Condition (@($strictEmpty.evidence_records).Count -eq 0) `
    "Empty join contains evidence records."
Assert-Condition (@($strictEmpty.mechanism_evidence).Count -eq 0) `
    "Empty join contains mechanism links."
$cliResult = Invoke-EvidenceJoinCli
Assert-Condition ($cliResult.ExitCode -eq 0) `
    "Repository SourceEvidence join CLI failed: $($cliResult.Output -join ' | ')"
Assert-Condition ($cliResult.Output.Count -eq 1) `
    "Repository SourceEvidence join CLI emitted unexpected output."
Assert-Condition ([string]$cliResult.Output[0] -ceq $expectedCliMarker) `
    "Repository SourceEvidence join CLI marker changed."

$active = New-SyntheticEvidence
$activeValidation = Test-P2SourceEvidence -Evidence $active
Assert-Condition ($activeValidation.PrimaryId -eq 1) `
    "Valid ACTIVE evidence changed its primary ID."
Assert-Condition ([string]$activeValidation.Status -ceq "ACTIVE") `
    "Valid ACTIVE evidence changed status."
Assert-Condition ([string]$activeValidation.AuditId -ceq `
    [string]$active.source_audit_id) "Valid evidence changed audit identity."
Assert-Condition ([string]$activeValidation.Sha256 -ceq `
    (Get-BattleSha256Text -Text (
        ConvertTo-BattleCanonicalJson -Value $active
    ))) "Valid evidence authoring hash is not canonical."
Assert-Condition ([string]$activeValidation.CanonicalJson -ceq `
    (ConvertTo-BattleCanonicalJson -Value $active)) `
    "Valid evidence canonical JSON changed."

$tombstone = New-SyntheticEvidence -Id 2 -Status "TOMBSTONE"
$tombstoneValidation = Test-P2SourceEvidence -Evidence $tombstone
Assert-Condition ($tombstoneValidation.PrimaryId -eq 2) `
    "Valid TOMBSTONE evidence changed its primary ID."
Assert-Condition ([string]$tombstoneValidation.Status -ceq "TOMBSTONE") `
    "Valid TOMBSTONE evidence changed status."
Assert-Condition (@($tombstone.behavior_claims).Count -eq 0) `
    "Valid TOMBSTONE evidence retained claims."

Assert-Condition ([long]$evidenceSchema.'$defs'.summary.maxLength -eq 1024) `
    "SourceEvidence summary schema maximum changed from 1024."
Assert-Condition ([string]$evidenceSchema.'$defs'.behavior_claim.properties.`
    claim_summary.'$ref' -ceq '#/$defs/summary') `
    "Claim summary no longer uses the bounded summary schema."
$maximumClaimSummary = "C" * 1024
$maximumClaimEvidence = New-SyntheticEvidence -Claims @(
    (New-SyntheticClaim -Summary $maximumClaimSummary)
)
$maximumClaimValidation = Test-P2SourceEvidence `
    -Evidence $maximumClaimEvidence
Assert-Condition ($maximumClaimEvidence.behavior_claims[0].claim_summary.Length `
    -eq 1024) "The maximum claim summary fixture has the wrong length."
Assert-Condition ([string]$maximumClaimValidation.Sha256 -ceq `
    (Get-BattleSha256Text -Text (
        ConvertTo-BattleCanonicalJson -Value $maximumClaimEvidence
    ))) "A 1024-character claim summary did not validate canonically."
$maximumClaimJoin = Invoke-SyntheticJoin -Evidence @($maximumClaimEvidence) `
    -Mechanisms @((New-SyntheticMechanism))
Assert-Condition ($maximumClaimJoin.CurrentEvidenceCount -eq 1 -and `
    [bool]$maximumClaimJoin.Manifest.evidence_records[0].evidence_current) `
    "A schema-valid 1024-character claim summary failed the executable join."
$oversizedClaimEvidence = New-SyntheticEvidence -Claims @(
    (New-SyntheticClaim -Summary ("C" * 1025))
)
Assert-ThrowsCode -Action {
    Test-P2SourceEvidence -Evidence $oversizedClaimEvidence
} -Code "P2E_EVIDENCE_SCHEMA" -Label "1025-character claim summary"

$validKindCases = @(
    [pscustomobject]@{ Kind = "SOURCE_CODE"; Category = "ACTION" },
    [pscustomobject]@{ Kind = "SOURCE_SCHEMA"; Category = "SCHEMA" },
    [pscustomobject]@{ Kind = "SOURCE_TEST"; Category = "TEST" },
    [pscustomobject]@{ Kind = "SOURCE_TEST"; Category = "SCRIPT_SCENARIO" }
)
foreach ($case in $validKindCases) {
    $candidate = New-SyntheticEvidence -SourceKind $case.Kind `
        -Category $case.Category
    $validation = Test-P2SourceEvidence -Evidence $candidate
    Assert-Condition ([string]$validation.SourceKind -ceq $case.Kind) `
        "Valid source kind '$($case.Kind)' was not retained."
    Assert-Condition ([string]$validation.Category -ceq $case.Category) `
        "Valid source category '$($case.Category)' was not retained."
}

$candidate = Copy-CanonicalValue $active
$candidate | Add-Member -NotePropertyName unexpected_field -NotePropertyValue 1
Assert-ThrowsCode -Action { Test-P2SourceEvidence $candidate } `
    -Code "P2E_EVIDENCE_SCHEMA" -Label "unknown evidence field"
$candidate = Copy-CanonicalValue $active
$candidate.evidence_id = "1"
Assert-ThrowsCode -Action { Test-P2SourceEvidence $candidate } `
    -Code "P2E_EVIDENCE_SCHEMA" -Label "string evidence ID"
$candidate = Copy-CanonicalValue $active
$candidate.behavior_claims[0].mechanism_id = "1"
Assert-ThrowsCode -Action { Test-P2SourceEvidence $candidate } `
    -Code "P2E_EVIDENCE_SCHEMA" -Label "string claim mechanism ID"
$candidate = Copy-CanonicalValue $active
$candidate.behavior_claims[0] | Add-Member `
    -NotePropertyName unexpected_claim_field -NotePropertyValue $true
Assert-ThrowsCode -Action { Test-P2SourceEvidence $candidate } `
    -Code "P2E_EVIDENCE_SCHEMA" -Label "unknown claim field"
$candidate = Copy-CanonicalValue $active
$candidate.behavior_claims = [object[]]@()
Assert-ThrowsCode -Action { Test-P2SourceEvidence $candidate } `
    -Code "P2E_EVIDENCE_SCHEMA" -Label "claimless ACTIVE evidence"
$candidate = Copy-CanonicalValue $tombstone
$candidate.behavior_claims = [object[]]@(New-SyntheticClaim)
Assert-ThrowsCode -Action { Test-P2SourceEvidence $candidate } `
    -Code "P2E_EVIDENCE_SCHEMA" -Label "claimed TOMBSTONE evidence"

foreach ($badPath in @(
    "/absolute.cpp", "C:/rooted.cpp", "src\backslash.cpp",
    "src/../traversal.cpp", "src/./dot.cpp", "src//empty.cpp",
    "src/trailing/"
)) {
    $candidate = Copy-CanonicalValue $active
    $candidate.source_relative_path = $badPath
    Assert-ThrowsCode -Action { Test-P2SourceEvidence $candidate } `
        -Code "P2E_PATH" -Label "invalid path '$badPath'"
}

foreach ($case in @(
    [pscustomobject]@{ Kind = "SOURCE_SCHEMA"; Category = "SECTION" },
    [pscustomobject]@{ Kind = "SOURCE_TEST"; Category = "SECTION" },
    [pscustomobject]@{ Kind = "SOURCE_CODE"; Category = "SCHEMA" },
    [pscustomobject]@{ Kind = "SOURCE_CODE"; Category = "TEST" }
)) {
    $candidate = New-SyntheticEvidence -SourceKind $case.Kind `
        -Category $case.Category
    Assert-ThrowsCode -Action { Test-P2SourceEvidence $candidate } `
        -Code "P2E_SOURCE_KIND_CATEGORY" `
        -Label "invalid $($case.Kind)/$($case.Category) pair"
}

$candidate = New-SyntheticEvidence -Claims @(
    (New-SyntheticClaim -MechanismId 2),
    (New-SyntheticClaim -MechanismId 1)
)
Assert-ThrowsCode -Action { Test-P2SourceEvidence $candidate } `
    -Code "P2E_EVIDENCE_ORDER" -Label "noncanonical claim order"
$candidate = New-SyntheticEvidence -Claims @(
    (New-SyntheticClaim), (New-SyntheticClaim)
)
Assert-ThrowsCode -Action { Test-P2SourceEvidence $candidate } `
    -Code "P2E_EVIDENCE_SCHEMA" -Label "duplicate claims"

$historyActive = New-SyntheticEvidence -Id 10 `
    -Path "programs/src/history_active.cpp" -Symbol "HistoryActive"
$historyActiveRecord = New-SyntheticEvidenceHistoryRecord `
    -Evidence $historyActive
$historySemanticWithoutVersion = Copy-CanonicalValue $historyActive
$historySemanticWithoutVersion.observation_summary = `
    "Changed without advancing evidence_version"
$historySemanticWithoutVersionRecord = New-SyntheticEvidenceHistoryRecord `
    -Evidence $historySemanticWithoutVersion
$historyVersionView = New-SyntheticEvidenceHistoryView `
    -CandidateRecords @($historySemanticWithoutVersionRecord) `
    -BaselineRecords @($historyActiveRecord)
Assert-Condition ($historyVersionView.ViewKind -ceq "P2_REPOSITORY_VIEW" -and `
    $historyVersionView.CandidateEntries -is `
        [Collections.Generic.Dictionary[string, object]] -and `
    $historyVersionView.BaselineEntries -is `
        [Collections.Generic.Dictionary[string, object]]) `
    "Synthetic history view does not use byte dictionaries."
Assert-Condition (($historyVersionView.CandidateEntries.Values | `
    ForEach-Object { $_ -is [byte[]] } | Where-Object { -not $_ } | `
    Measure-Object | Select-Object -ExpandProperty Count) -eq 0) `
    "Synthetic candidate history contains a non-byte value."
Assert-Condition (($historyVersionView.BaselineEntries.Values | `
    ForEach-Object { $_ -is [byte[]] } | Where-Object { -not $_ } | `
    Measure-Object | Select-Object -ExpandProperty Count) -eq 0) `
    "Synthetic baseline history contains a non-byte value."
Assert-ThrowsCode -Action {
    Read-P2ValidatedEvidenceSet -View $historyVersionView
} -Code "P2E_EVIDENCE_VERSION" `
    -Label "semantic evidence edit without version increment"

$historyTombstone = Copy-CanonicalValue $historyActive
$historyTombstone.evidence_version = 2
$historyTombstone.status = "TOMBSTONE"
$historyTombstone.behavior_claims = [Array]::CreateInstance([object], 0)
$historyTombstoneRecord = New-SyntheticEvidenceHistoryRecord `
    -Evidence $historyTombstone
$historyTombstoneView = New-SyntheticEvidenceHistoryView `
    -CandidateRecords @($historyTombstoneRecord) `
    -BaselineRecords @($historyActiveRecord)
$historyTombstoneSet = Read-P2ValidatedEvidenceSet `
    -View $historyTombstoneView
Assert-Condition (@($historyTombstoneSet.Records).Count -eq 1) `
    "ACTIVE to TOMBSTONE history changed the record count."
Assert-Condition ([long]$historyTombstoneSet.Records[0].Validation.Version `
    -eq 2) "ACTIVE to TOMBSTONE history lost its incremented version."
Assert-Condition ([string]$historyTombstoneSet.Records[0].Validation.Status `
    -ceq "TOMBSTONE") "ACTIVE to TOMBSTONE history did not retain status."
Assert-Condition ([string]$historyTombstoneSet.InputSetHash -ceq `
    (Get-BattleSha256Text -Text $historyTombstoneSet.InputSetJson)) `
    "ACTIVE to TOMBSTONE history input hash is not canonical."

$historyRevived = Copy-CanonicalValue $historyActive
$historyRevived.evidence_version = 3
$historyRevivedRecord = New-SyntheticEvidenceHistoryRecord `
    -Evidence $historyRevived
$historyReviveView = New-SyntheticEvidenceHistoryView `
    -CandidateRecords @($historyRevivedRecord) `
    -BaselineRecords @($historyTombstoneRecord)
Assert-ThrowsCode -Action {
    Read-P2ValidatedEvidenceSet -View $historyReviveView
} -Code "P2E_EVIDENCE_TOMBSTONE_IMMUTABLE" `
    -Label "tombstoned evidence revival"

$historyDeleteView = New-SyntheticEvidenceHistoryView `
    -CandidateRecords @() -BaselineRecords @($historyActiveRecord)
Assert-ThrowsCode -Action {
    Read-P2ValidatedEvidenceSet -View $historyDeleteView
} -Code "P2E_EVIDENCE_DELETE" -Label "evidence history deletion"

$historyMax = New-SyntheticEvidence -Id 20 `
    -Path "programs/src/history_max.cpp" -Symbol "HistoryMax"
$historyBelowMax = New-SyntheticEvidence -Id 19 `
    -Path "programs/src/history_below_max.cpp" -Symbol "HistoryBelowMax"
$historyMaxRecord = New-SyntheticEvidenceHistoryRecord -Evidence $historyMax
$historyBelowMaxRecord = New-SyntheticEvidenceHistoryRecord `
    -Evidence $historyBelowMax
$historyAppendView = New-SyntheticEvidenceHistoryView -CandidateRecords @(
    $historyBelowMaxRecord, $historyMaxRecord
) -BaselineRecords @($historyMaxRecord)
Assert-ThrowsCode -Action {
    Read-P2ValidatedEvidenceSet -View $historyAppendView
} -Code "P2E_EVIDENCE_ID_APPEND" `
    -Label "new evidence ID below baseline maximum"

$historyFilenameEvidence = New-SyntheticEvidence -Id 30 `
    -Path "programs/src/history_filename.cpp" -Symbol "HistoryFilename"
$historyFilenameCandidateRecord = New-SyntheticEvidenceHistoryRecord `
    -Evidence $historyFilenameEvidence
$historyFilenameBaselineRecord = New-SyntheticEvidenceHistoryRecord `
    -Evidence $historyFilenameEvidence -FilenameId 31
$historyFilenameView = New-SyntheticEvidenceHistoryView `
    -CandidateRecords @($historyFilenameCandidateRecord) `
    -BaselineRecords @($historyFilenameBaselineRecord)
Assert-ThrowsCode -Action {
    Read-P2ValidatedEvidenceSet -View $historyFilenameView
} -Code "P2E_EVIDENCE_ID_FILENAME" `
    -Label "baseline evidence filename ID mismatch" -MessageFragment "HEAD:"

$cleanCompilation = New-SyntheticCompilation -Mechanisms @(
    (New-SyntheticMechanism)
)
$cleanEvidenceSet = New-SyntheticEvidenceSet -Evidence @($active)
$cleanGovernance = New-SyntheticGovernance
$cleanAudit = New-SyntheticAuditValidation -Entries @(
    (New-SyntheticAuditEntry -Evidence $active)
)
$cleanSpecHashBefore = [string]$cleanCompilation.SpecManifestHash
$cleanRuntimeHashBefore = [string]$cleanCompilation.RuntimeManifestHash
$cleanFirst = Invoke-P2ValidatedSourceEvidenceJoinCore `
    -Compilation $cleanCompilation -EvidenceSet $cleanEvidenceSet `
    -Governance $cleanGovernance -AuditValidation $cleanAudit
$cleanSecond = Invoke-P2ValidatedSourceEvidenceJoinCore `
    -Compilation $cleanCompilation -EvidenceSet $cleanEvidenceSet `
    -Governance $cleanGovernance -AuditValidation $cleanAudit
Assert-Condition ([string]$cleanCompilation.SpecManifestHash -ceq `
    $cleanSpecHashBefore) "Synthetic join mutated the spec hash."
Assert-Condition ([string]$cleanCompilation.RuntimeManifestHash -ceq `
    $cleanRuntimeHashBefore) "Synthetic join mutated the runtime hash."
Assert-BytesEqual $cleanFirst.ManifestBytes $cleanSecond.ManifestBytes `
    "repeat clean synthetic join"
Assert-Condition ([string]$cleanFirst.ManifestHash -ceq `
    (Get-BattleSha256Text -Text $cleanFirst.ManifestJson)) `
    "Synthetic join hash is not canonical."
Assert-Condition ($cleanFirst.Manifest.counts.evidence_record_count -eq 1) `
    "Clean join evidence count is wrong."
Assert-Condition ($cleanFirst.Manifest.counts.active_evidence_count -eq 1) `
    "Clean join ACTIVE count is wrong."
Assert-Condition ($cleanFirst.Manifest.counts.tombstone_evidence_count -eq 0) `
    "Clean join TOMBSTONE count is wrong."
Assert-Condition ($cleanFirst.Manifest.counts.current_evidence_count -eq 1) `
    "Clean join current count is wrong."
Assert-Condition ($cleanFirst.Manifest.counts.blocked_evidence_count -eq 0) `
    "Clean join blocked count is wrong."
Assert-Condition ($cleanFirst.Manifest.counts.mechanism_count -eq 1) `
    "Clean join mechanism count is wrong."
Assert-Condition ($cleanFirst.Manifest.counts.evidence_link_count -eq 1) `
    "Clean join link count is wrong."
$cleanRecord = [PSCustomObject]$cleanFirst.Manifest.evidence_records[0]
$cleanLink = [PSCustomObject]$cleanFirst.Manifest.mechanism_evidence[0]
Assert-ExactPropertySet -Value $cleanRecord `
    -SchemaNode $joinSchema.'$defs'.evidence_record `
    -Label "compiled evidence record"
Assert-ExactPropertySet -Value $cleanLink `
    -SchemaNode $joinSchema.'$defs'.mechanism_evidence_record `
    -Label "compiled mechanism evidence record"
Assert-Condition ($cleanRecord.evidence_current -is [bool] -and `
    [bool]$cleanRecord.evidence_current) "Clean evidence is not current."
Assert-Condition (@($cleanRecord.blocker_codes).Count -eq 0) `
    "Clean evidence has blockers."
Assert-Condition ((@($cleanRecord.mechanism_ids) -join ',') -ceq "1") `
    "Clean evidence mechanism IDs are wrong."
Assert-Condition ($cleanLink.evidence_current -is [bool] -and `
    [bool]$cleanLink.evidence_current) "Clean mechanism is not current."
Assert-Condition ((@($cleanLink.required_evidence_ids) -join ',') -ceq "1") `
    "Clean mechanism required evidence IDs are wrong."
Assert-Condition ((@($cleanLink.joined_evidence_ids) -join ',') -ceq "1") `
    "Clean mechanism joined evidence IDs are wrong."
Assert-Condition (@($cleanLink.blocker_codes).Count -eq 0) `
    "Clean mechanism has blockers."
Assert-FlatSchemaArray -Value $cleanRecord.blocker_codes `
    -Expected @() -ItemKind BLOCKER -Label "zero clean evidence blockers"
Assert-FlatSchemaArray -Value $cleanRecord.mechanism_ids `
    -Expected @(1) -ItemKind ID -Label "one clean evidence mechanism ID"
Assert-FlatSchemaArray -Value $cleanLink.required_evidence_ids `
    -Expected @(1) -ItemKind ID -Label "one required evidence ID"
Assert-FlatSchemaArray -Value $cleanLink.joined_evidence_ids `
    -Expected @(1) -ItemKind ID -Label "one joined evidence ID"
Assert-FlatSchemaArray -Value $cleanLink.blocker_codes `
    -Expected @() -ItemKind BLOCKER -Label "zero clean mechanism blockers"

$projectOnlyMechanism = New-SyntheticMechanism -EvidenceIds @() `
    -ProjectRequirementKeys @("PROJECT.SYNTHETIC_REQUIREMENT")
$projectOnlyCompilation = New-SyntheticCompilation -Mechanisms @(
    $projectOnlyMechanism
)
$projectOnlyEvidenceInput = [pscustomobject][ordered]@{
    schema_version = 1
    source_evidence = [Array]::CreateInstance([object], 0)
}
$projectOnlyEvidenceSet = [pscustomobject][ordered]@{
    Records = [Array]::CreateInstance([object], 0)
    InputSetHash = Get-BattleSha256Text -Text (
        ConvertTo-BattleCanonicalJson -Value $projectOnlyEvidenceInput
    )
}
$projectOnly = Invoke-P2ValidatedSourceEvidenceJoinCore `
    -Compilation $projectOnlyCompilation -EvidenceSet $projectOnlyEvidenceSet `
    -Governance (New-SyntheticGovernance) -AuditValidation $null
Assert-Condition ((@($projectOnlyMechanism.project_requirement_keys) `
    -join ',') -ceq "PROJECT.SYNTHETIC_REQUIREMENT") `
    "Project-only mechanism lost its project requirement."
Assert-Condition ($projectOnly.Manifest.counts.mechanism_count -eq 1 -and `
    $projectOnly.Manifest.counts.evidence_record_count -eq 0 -and `
    $projectOnly.Manifest.counts.evidence_link_count -eq 0) `
    "Project-only mechanism join counts are wrong."
$projectOnlyLink = [PSCustomObject]$projectOnly.Manifest.mechanism_evidence[0]
Assert-ExactPropertySet -Value $projectOnlyLink `
    -SchemaNode $joinSchema.'$defs'.mechanism_evidence_record `
    -Label "project-only mechanism evidence record"
Assert-Condition ($projectOnlyLink.evidence_current -is [bool] -and `
    [bool]$projectOnlyLink.evidence_current) `
    "A project-only mechanism without evidence is not current."
Assert-FlatSchemaArray -Value $projectOnlyLink.required_evidence_ids `
    -Expected @() -ItemKind ID -Label "zero project-only required IDs"
Assert-FlatSchemaArray -Value $projectOnlyLink.joined_evidence_ids `
    -Expected @() -ItemKind ID -Label "zero project-only joined IDs"
Assert-FlatSchemaArray -Value $projectOnlyLink.blocker_codes `
    -Expected @() -ItemKind BLOCKER -Label "zero project-only blockers"

$unlinkedTombstone = Invoke-SyntheticJoin -Evidence @($tombstone) `
    -Mechanisms @($projectOnlyMechanism)
$unlinkedTombstoneRecord = [PSCustomObject](
    $unlinkedTombstone.Manifest.evidence_records[0]
)
$unlinkedTombstoneLink = [PSCustomObject](
    $unlinkedTombstone.Manifest.mechanism_evidence[0]
)
Assert-ExactPropertySet -Value $unlinkedTombstoneRecord `
    -SchemaNode $joinSchema.'$defs'.evidence_record `
    -Label "unlinked tombstone evidence record"
Assert-ExactPropertySet -Value $unlinkedTombstoneLink `
    -SchemaNode $joinSchema.'$defs'.mechanism_evidence_record `
    -Label "unlinked tombstone mechanism record"
Assert-FlatSchemaArray -Value $unlinkedTombstoneRecord.mechanism_ids `
    -Expected @() -ItemKind ID -Label "zero tombstone mechanism IDs"
Assert-FlatSchemaArray -Value $unlinkedTombstoneRecord.blocker_codes `
    -Expected @("EVIDENCE_TOMBSTONED") -ItemKind BLOCKER `
    -Label "one tombstone blocker"
Assert-FlatSchemaArray -Value $unlinkedTombstoneLink.required_evidence_ids `
    -Expected @() -ItemKind ID -Label "zero tombstone-link required IDs"
Assert-FlatSchemaArray -Value $unlinkedTombstoneLink.joined_evidence_ids `
    -Expected @() -ItemKind ID -Label "zero tombstone-link joined IDs"
Assert-FlatSchemaArray -Value $unlinkedTombstoneLink.blocker_codes `
    -Expected @() -ItemKind BLOCKER -Label "zero tombstone-link blockers"

$multiEvidence = New-SyntheticEvidence -Claims @(
    (New-SyntheticClaim -MechanismId 1),
    (New-SyntheticClaim -MechanismId 2)
)
$multi = Invoke-SyntheticJoin -Evidence @($multiEvidence) -Mechanisms @(
    (New-SyntheticMechanism -Id 2),
    (New-SyntheticMechanism -Id 1)
)
Assert-Condition ($multi.Manifest.counts.evidence_record_count -eq 1) `
    "Multi-mechanism join evidence count is wrong."
Assert-Condition ($multi.Manifest.counts.mechanism_count -eq 2) `
    "Multi-mechanism join mechanism count is wrong."
Assert-Condition ($multi.Manifest.counts.evidence_link_count -eq 2) `
    "Multi-mechanism join link count is wrong."
Assert-Condition ((@($multi.Manifest.evidence_records[0].mechanism_ids) `
    -join ',') -ceq "1,2") "Multi-mechanism evidence IDs are not sorted."
Assert-Condition ((@($multi.Manifest.mechanism_evidence | ForEach-Object {
    [long]$_.mechanism_id
}) -join ',') -ceq "1,2") "Mechanism output is not sorted."
Assert-Condition (@($multi.Manifest.mechanism_evidence | Where-Object {
    -not [bool]$_.evidence_current
}).Count -eq 0) "A clean multi-mechanism link is blocked."
Assert-FlatSchemaArray -Value $multi.Manifest.evidence_records[0].mechanism_ids `
    -Expected @(1, 2) -ItemKind ID -Label "two evidence mechanism IDs"

$blockerCases = @(
    [pscustomobject]@{
        EvidenceStatus = "DIRTY_UNVERIFIED"; Scope = "IMPLEMENT"
        Confidence = "HIGH"; Review = "VERIFIED"
        Expected = "SOURCE_DIRTY_UNVERIFIED"
    },
    [pscustomobject]@{
        EvidenceStatus = "CLEAN_INDEXED"; Scope = "DEFERRED_N0"
        Confidence = "HIGH"; Review = "VERIFIED"
        Expected = "SCOPE_DEFERRED_N0"
    },
    [pscustomobject]@{
        EvidenceStatus = "CLEAN_INDEXED"; Scope = "REJECTED_UNVERIFIED"
        Confidence = "HIGH"; Review = "VERIFIED"
        Expected = "SCOPE_REJECTED_UNVERIFIED"
    },
    [pscustomobject]@{
        EvidenceStatus = "CLEAN_INDEXED"; Scope = "IMPLEMENT"
        Confidence = "HIGH"; Review = "HUMAN_REVIEWED"
        Expected = "REVIEW_NOT_VERIFIED"
    },
    [pscustomobject]@{
        EvidenceStatus = "CLEAN_INDEXED"; Scope = "IMPLEMENT"
        Confidence = "MEDIUM"; Review = "VERIFIED"
        Expected = "CONFIDENCE_NOT_HIGH"
    }
)
foreach ($case in $blockerCases) {
    $evidence = New-SyntheticEvidence -Confidence $case.Confidence `
        -ReviewStatus $case.Review
    $entry = New-SyntheticAuditEntry -Evidence $evidence `
        -EvidenceStatus $case.EvidenceStatus `
        -ScopeDisposition $case.Scope
    $result = Invoke-SyntheticJoin -Evidence @($evidence) `
        -Mechanisms @((New-SyntheticMechanism)) -AuditEntries @($entry)
    Assert-Condition (-not [bool]$result.Manifest.evidence_records[0].evidence_current) `
        "$($case.Expected) did not block evidence."
    Assert-Condition ((@($result.Manifest.evidence_records[0].blocker_codes) `
        -join ',') -ceq $case.Expected) `
        "$($case.Expected) evidence blockers are wrong."
    Assert-Condition (-not [bool]$result.Manifest.mechanism_evidence[0].evidence_current) `
        "$($case.Expected) did not block the mechanism."
    Assert-Condition ((@($result.Manifest.mechanism_evidence[0].blocker_codes) `
        -join ',') -ceq $case.Expected) `
        "$($case.Expected) mechanism blockers are wrong."
    Assert-Condition ($result.Manifest.counts.current_evidence_count -eq 0 -and `
        $result.Manifest.counts.blocked_evidence_count -eq 1) `
        "$($case.Expected) counts are wrong."
    Assert-FlatSchemaArray `
        -Value $result.Manifest.evidence_records[0].blocker_codes `
        -Expected @($case.Expected) -ItemKind BLOCKER `
        -Label "one $($case.Expected) evidence blocker"
    Assert-FlatSchemaArray `
        -Value $result.Manifest.mechanism_evidence[0].blocker_codes `
        -Expected @($case.Expected) -ItemKind BLOCKER `
        -Label "one $($case.Expected) mechanism blocker"
}

$twoBlockerEvidence = New-SyntheticEvidence
$twoBlockerEntry = New-SyntheticAuditEntry -Evidence $twoBlockerEvidence `
    -EvidenceStatus "DIRTY_UNVERIFIED" -ScopeDisposition "DEFERRED_N0"
$twoBlocker = Invoke-SyntheticJoin -Evidence @($twoBlockerEvidence) `
    -Mechanisms @((New-SyntheticMechanism)) `
    -AuditEntries @($twoBlockerEntry)
$twoBlockerCodes = @("SCOPE_DEFERRED_N0", "SOURCE_DIRTY_UNVERIFIED")
$twoBlockerRecord = [PSCustomObject]$twoBlocker.Manifest.evidence_records[0]
$twoBlockerLink = [PSCustomObject]$twoBlocker.Manifest.mechanism_evidence[0]
Assert-ExactPropertySet -Value $twoBlockerRecord `
    -SchemaNode $joinSchema.'$defs'.evidence_record `
    -Label "two-blocker evidence record"
Assert-ExactPropertySet -Value $twoBlockerLink `
    -SchemaNode $joinSchema.'$defs'.mechanism_evidence_record `
    -Label "two-blocker mechanism record"
Assert-FlatSchemaArray -Value $twoBlockerRecord.blocker_codes `
    -Expected $twoBlockerCodes -ItemKind BLOCKER `
    -Label "two evidence blockers"
Assert-FlatSchemaArray -Value $twoBlockerLink.blocker_codes `
    -Expected $twoBlockerCodes -ItemKind BLOCKER `
    -Label "two mechanism blockers"

$combinedEvidence = New-SyntheticEvidence -Confidence "LOW" `
    -ReviewStatus "DRAFT"
$combinedEntry = New-SyntheticAuditEntry -Evidence $combinedEvidence `
    -EvidenceStatus "DIRTY_UNVERIFIED" -ScopeDisposition "DEFERRED_N0"
$combined = Invoke-SyntheticJoin -Evidence @($combinedEvidence) `
    -Mechanisms @((New-SyntheticMechanism)) `
    -AuditEntries @($combinedEntry)
$expectedCombined = (
    "CONFIDENCE_NOT_HIGH,REVIEW_NOT_VERIFIED,SCOPE_DEFERRED_N0," +
    "SOURCE_DIRTY_UNVERIFIED"
)
Assert-Condition ((@($combined.Manifest.evidence_records[0].blocker_codes) `
    -join ',') -ceq $expectedCombined) `
    "Combined evidence blockers are not canonical."
Assert-Condition ((@($combined.Manifest.mechanism_evidence[0].blocker_codes) `
    -join ',') -ceq $expectedCombined) `
    "Combined mechanism blockers are not canonical."

$testEvidence = New-SyntheticEvidence -SourceKind "SOURCE_TEST" `
    -Category "TEST"
$testEntry = New-SyntheticAuditEntry -Evidence $testEvidence `
    -TestDisposition "REPLACED_BY_SYNTHETIC_FIXTURE"
$testBlocked = Invoke-SyntheticJoin -Evidence @($testEvidence) `
    -Mechanisms @((New-SyntheticMechanism)) -AuditEntries @($testEntry)
Assert-Condition ((@($testBlocked.Manifest.evidence_records[0].blocker_codes) `
    -join ',') -ceq "TEST_NOT_PORT_BEHAVIOR") `
    "Non-port source test evidence was not blocked."

$emptyEvidenceSet = [pscustomobject][ordered]@{
    Records = [object[]]@()
    InputSetHash = Get-BattleSha256Text -Text "empty synthetic evidence"
}
Assert-ThrowsCode -Action {
    Invoke-P2ValidatedSourceEvidenceJoinCore `
        -Compilation (New-SyntheticCompilation -Mechanisms @(
            (New-SyntheticMechanism -EvidenceIds @(99))
        )) -EvidenceSet $emptyEvidenceSet `
        -Governance (New-SyntheticGovernance) -AuditValidation $null
} -Code "P2E_SPEC_EVIDENCE_UNKNOWN" -Label "unknown spec evidence"

$tombstone = New-SyntheticEvidence -Status "TOMBSTONE"
Assert-ThrowsCode -Action {
    Invoke-SyntheticJoin -Evidence @($tombstone) `
        -Mechanisms @((New-SyntheticMechanism))
} -Code "P2E_SPEC_EVIDENCE_TOMBSTONED" `
    -Label "spec reference to tombstoned evidence"

$backrefEvidence = New-SyntheticEvidence
Assert-ThrowsCode -Action {
    Invoke-SyntheticJoin -Evidence @($backrefEvidence) `
        -Mechanisms @((New-SyntheticMechanism -EvidenceIds @()))
} -Code "P2E_CLAIM_BACKREF" -Label "claim without spec back-reference"

$reverseEvidence = New-SyntheticEvidence -Claims @(
    (New-SyntheticClaim -MechanismId 2)
)
Assert-ThrowsCode -Action {
    Invoke-SyntheticJoin -Evidence @($reverseEvidence) -Mechanisms @(
        (New-SyntheticMechanism -Id 1),
        (New-SyntheticMechanism -Id 2)
    )
} -Code "P2E_SPEC_EVIDENCE_CLAIM" `
    -Label "spec evidence without matching claim"

$unknownMechanismEvidence = New-SyntheticEvidence -Claims @(
    (New-SyntheticClaim -MechanismId 99)
)
Assert-ThrowsCode -Action {
    Invoke-SyntheticJoin -Evidence @($unknownMechanismEvidence) `
        -Mechanisms @((New-SyntheticMechanism))
} -Code "P2E_CLAIM_MECHANISM_UNKNOWN" -Label "unknown claim mechanism"

$unknownBranchEvidence = New-SyntheticEvidence -Claims @(
    (New-SyntheticClaim -BranchId 99)
)
Assert-ThrowsCode -Action {
    Invoke-SyntheticJoin -Evidence @($unknownBranchEvidence) `
        -Mechanisms @((New-SyntheticMechanism))
} -Code "P2E_CLAIM_BRANCH_UNKNOWN" -Label "unknown claim branch"

$pointerCases = @(
    [pscustomobject]@{
        Pointer = "/evidence_ids"; Code = "P2E_CLAIM_POINTER_METADATA"
    },
    [pscustomobject]@{
        Pointer = "/write_set"; Code = "P2E_CLAIM_POINTER_MISSING"
    },
    [pscustomobject]@{
        Pointer = "/ruleset_mode/value"; Code = "P2E_CLAIM_POINTER_SCALAR"
    },
    [pscustomobject]@{
        Pointer = "/coverage_targets/01"; Code = "P2E_CLAIM_POINTER_INDEX"
    },
    [pscustomobject]@{
        Pointer = "/coverage_targets/9"; Code = "P2E_CLAIM_POINTER_INDEX"
    },
    [pscustomobject]@{
        Pointer = "/coverage_targets/0/Branch_ID"
        Code = "P2E_CLAIM_POINTER_MISSING"
    },
    [pscustomobject]@{
        Pointer = "/ruleset_mode/~2"; Code = "P2E_CLAIM_POINTER_ESCAPE"
    }
)
foreach ($case in $pointerCases) {
    $evidence = New-SyntheticEvidence -Claims @(
        (New-SyntheticClaim -Pointer $case.Pointer)
    )
    Assert-ThrowsCode -Action {
        Invoke-SyntheticJoin -Evidence @($evidence) `
            -Mechanisms @((New-SyntheticMechanism))
    } -Code $case.Code -Label "invalid pointer '$($case.Pointer)'"
}

$identityBase = New-SyntheticEvidence
$identityAudit = New-SyntheticAuditEntry -Evidence $identityBase
$identityCases = @(
    [pscustomobject]@{
        Field = "source_repository"; Value = "pokelib"
        Message = "source_repository"
    },
    [pscustomobject]@{
        Field = "source_category"; Value = "ACTION"
        Message = "source_category"
    },
    [pscustomobject]@{
        Field = "source_relative_path"; Value = "programs/src/other.cpp"
        Message = "source_relative_path"
    },
    [pscustomobject]@{
        Field = "symbol_or_record_key"; Value = "OtherSymbol"
        Message = "symbol_or_record_key"
    },
    [pscustomobject]@{
        Field = "file_sha256"; Value = (Get-BattleSha256Text -Text "other")
        Message = "file_sha256"
    },
    [pscustomobject]@{
        Field = "source_revision"; Value = ("f" * 40)
        Message = "source_revision"
    }
)
foreach ($case in $identityCases) {
    $evidence = Copy-CanonicalValue $identityBase
    $evidence.($case.Field) = $case.Value
    Assert-ThrowsCode -Action {
        Invoke-SyntheticJoin -Evidence @($evidence) `
            -Mechanisms @((New-SyntheticMechanism)) `
            -AuditEntries @($identityAudit)
    } -Code "P2E_AUDIT_LINK_MISMATCH" `
        -Label "audit mismatch $($case.Field)" `
        -MessageFragment $case.Message
}
$missingAuditEvidence = Copy-CanonicalValue $identityBase
$missingAuditEvidence.source_audit_id = "AUDIT_0000000000000000"
Assert-ThrowsCode -Action {
    Invoke-SyntheticJoin -Evidence @($missingAuditEvidence) `
        -Mechanisms @((New-SyntheticMechanism)) `
        -AuditEntries @($identityAudit)
} -Code "P2E_AUDIT_ID_MISSING" -Label "unknown audit identity"

$secondEvidence = New-SyntheticEvidence -Id 2 `
    -Path "programs/src/second.cpp" -Symbol "SecondSection"
$firstMechanism = New-SyntheticMechanism -EvidenceIds @(1, 2)
$deterministicFirst = Invoke-SyntheticJoin `
    -Evidence @($secondEvidence, $active) -Mechanisms @($firstMechanism)
$deterministicSecond = Invoke-SyntheticJoin `
    -Evidence @($active, $secondEvidence) -Mechanisms @(
        (New-SyntheticMechanism -EvidenceIds @(1, 2))
    )
Assert-BytesEqual $deterministicFirst.ManifestBytes `
    $deterministicSecond.ManifestBytes "shuffled synthetic joins"
Assert-Condition ([string]$deterministicFirst.ManifestHash -ceq `
    [string]$deterministicSecond.ManifestHash) `
    "Shuffled synthetic join hashes differ."
Assert-Condition ((@($deterministicFirst.Manifest.evidence_records | `
    ForEach-Object { [long]$_.evidence_id }) -join ',') -ceq "1,2") `
    "Shuffled evidence output is not sorted."
Assert-Condition ((@(
    $deterministicFirst.Manifest.mechanism_evidence[0].required_evidence_ids
) -join ',') -ceq "1,2") "Required evidence IDs are not sorted."
Assert-Condition ((@(
    $deterministicFirst.Manifest.mechanism_evidence[0].joined_evidence_ids
) -join ',') -ceq "1,2") "Joined evidence IDs are not sorted."
Assert-FlatSchemaArray -Value (
    $deterministicFirst.Manifest.mechanism_evidence[0].required_evidence_ids
) -Expected @(1, 2) -ItemKind ID -Label "two required evidence IDs"
Assert-FlatSchemaArray -Value (
    $deterministicFirst.Manifest.mechanism_evidence[0].joined_evidence_ids
) -Expected @(1, 2) -ItemKind ID -Label "two joined evidence IDs"

$projection = [string]$deterministicFirst.ManifestJson
foreach ($forbidden in @(
    "programs/src/secret_section.cpp", "SecretSection",
    "SENSITIVE_OBSERVATION_TOKEN", "SYNTHETIC_CLAIM_TOKEN",
    "source_relative_path", "symbol_or_record_key", "observation_summary",
    "claim_summary", "line_anchor_at_scan_time", "created_at", "timestamp",
    $ProjectRoot
)) {
    Assert-Condition ($projection.IndexOf(
        $forbidden, [StringComparison]::OrdinalIgnoreCase
    ) -lt 0) "Compiled join leaked forbidden value '$forbidden'."
}
Assert-Condition ($projection -cnotmatch `
    '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}') `
    "Compiled join contains a timestamp."
Assert-Condition ($projection -cnotmatch `
    '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-' +
    '[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}') `
    "Compiled join contains a GUID."
Assert-Condition ($projection -ceq `
    (ConvertTo-BattleCanonicalJson -Value $deterministicFirst.Manifest)) `
    "Compiled join output is not canonical JSON."
Assert-Condition ([string]$deterministicFirst.ManifestHash -ceq `
    (Get-BattleSha256Text -Text $projection)) `
    "Compiled join hash does not match canonical output."

Write-Host "P2_SOURCE_EVIDENCE_JOIN_TEST_OK checks=$checks"
