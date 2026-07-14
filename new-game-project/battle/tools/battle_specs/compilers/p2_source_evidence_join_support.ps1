Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "p2_spec_compiler_support.ps1")

$script:P2EvidenceJoinContractVersion = 1
$script:P2EvidenceJoinManifestSchemaVersion = 1
$script:P2EvidenceDirectory = "new-game-project/battle/specs/evidence"
$script:P2EvidenceFilenamePattern = (
    '^new-game-project/battle/specs/evidence/' +
    '(?<id>[0-9]{10})\.source_evidence\.json$'
)
$script:P2EvidenceSealRelativePath = (
    "new-game-project/battle/manifests/source_audit/source_audit_seal.json"
)
$script:P2EvidencePolicyRelativePath = (
    "new-game-project/battle/manifests/source_audit/source_audit_policy.json"
)
$script:P2EvidenceBaselineRelativePath = (
    "new-game-project/battle/manifests/source_audit/source_index_baseline.json"
)
$script:P2EvidenceAuditRelativePath = (
    "new-game-project/battle/generated/p0/source_audit_disposition_manifest.json"
)
$script:P2EvidenceMaxAuditBytes = 8388608
$script:P2EvidenceMaxRecords = 65535
$script:P2EvidenceAllowedCategories = @(
    "MODULE", "SOURCE_FILE", "SECTION", "EVENT_HANDLER", "EVENT",
    "COMMAND", "ACTION", "INTERRUPT", "PROTOCOL", "BATTLE_MODE",
    "SCHEMA", "TEST", "SCRIPT_SCENARIO", "LOGIC_EDGE"
)
$script:P2EvidenceBehaviorFields = @(
    "ruleset_mode", "ruleset_ids", "feature_pack_ids", "entry_kind",
    "resolver_id", "phase_id", "subphase_id", "preconditions", "inputs",
    "read_set", "write_set", "history_reads", "history_writes",
    "counter_reads", "counter_writes", "ordering_key", "short_circuit",
    "reentry_policy", "execution_steps", "coverage_targets",
    "parameter_slots", "formula_stages", "rng_draws", "resolver_ids",
    "event_ids", "handler_ids", "state_op_ids", "command_ids",
    "presentation_cue_ids", "result_type", "mutation_contracts",
    "command_contracts", "error_contracts", "atomicity_policy",
    "test_requirements"
)

function Throw-P2EvidenceJoinError {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    throw "$Code`: $Message"
}

function Assert-P2EvidenceCondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        Throw-P2EvidenceJoinError -Code $Code -Message $Message
    }
}

function Assert-P2EvidenceExactProperties {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-P2EvidenceCondition (
        $null -ne $Value -and $Value -is [PSCustomObject]
    ) "P2E_EVIDENCE_SCHEMA" "$Context must be a JSON object."
    $actual = @($Value.PSObject.Properties.Name)
    $actualSet = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($name in $actual) {
        $null = $actualSet.Add([string]$name)
    }
    $expectedSet = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($name in $Expected) {
        $null = $expectedSet.Add([string]$name)
    }
    $missing = @($Expected | Where-Object { -not $actualSet.Contains($_) })
    $unknown = @($actual | Where-Object { -not $expectedSet.Contains($_) })
    Assert-P2EvidenceCondition (
        $actual.Count -eq $Expected.Count -and
        $missing.Count -eq 0 -and $unknown.Count -eq 0
    ) "P2E_EVIDENCE_SCHEMA" (
        "$Context has missing [$($missing -join ', ')] or unknown " +
        "[$($unknown -join ', ')] fields."
    )
}

function Get-P2EvidenceInteger {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [long]$Minimum = 0,
        [long]$Maximum = 2147483647L
    )

    Assert-P2EvidenceCondition (Test-P2IntegralType $Value) `
        "P2E_EVIDENCE_SCHEMA" "$Context must be an integer."
    try {
        $result = [Convert]::ToInt64($Value)
    }
    catch {
        Throw-P2EvidenceJoinError "P2E_EVIDENCE_SCHEMA" `
            "$Context is outside the signed 64-bit range."
    }
    Assert-P2EvidenceCondition (
        $result -ge $Minimum -and $result -le $Maximum
    ) "P2E_EVIDENCE_SCHEMA" (
        "$Context value $result is outside $Minimum..$Maximum."
    )
    return $result
}

function Get-P2EvidenceString {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$MaximumLength = 1024
    )

    Assert-P2EvidenceCondition (
        $null -ne $Value -and $Value -is [string]
    ) "P2E_EVIDENCE_SCHEMA" "$Context must be a string."
    $text = [string]$Value
    Assert-P2EvidenceCondition (
        $text.Length -le $MaximumLength -and $text -cmatch $Pattern
    ) "P2E_EVIDENCE_SCHEMA" "$Context has an invalid value."
    return $text
}

function Get-P2EvidenceEnum {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string[]]$Allowed
    )

    $text = Get-P2EvidenceString -Value $Value -Context $Context `
        -Pattern '^.+$' -MaximumLength 128
    Assert-P2EvidenceCondition ($text -cin $Allowed) `
        "P2E_EVIDENCE_SCHEMA" (
            "$Context value '$text' is not one of [$($Allowed -join ', ')]."
        )
    return $text
}

function Get-P2EvidenceStringArray {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [int]$Minimum = 0,
        [int]$Maximum = 64,
        [string]$Pattern = '^[^\x00-\x1f\x7f]+$',
        [int]$MaximumLength = 512
    )

    Assert-P2EvidenceCondition ($null -ne $Value -and $Value -is [Array]) `
        "P2E_EVIDENCE_SCHEMA" "$Context must be an array."
    $values = @($Value)
    Assert-P2EvidenceCondition (
        $values.Count -ge $Minimum -and $values.Count -le $Maximum
    ) "P2E_EVIDENCE_SCHEMA" (
        "$Context contains $($values.Count) items; expected $Minimum..$Maximum."
    )
    $seen = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($item in $values) {
        $text = Get-P2EvidenceString -Value $item -Context "$Context item" `
            -Pattern $Pattern -MaximumLength $MaximumLength
        Assert-P2EvidenceCondition ($seen.Add($text)) `
            "P2E_EVIDENCE_SCHEMA" "$Context repeats '$text'."
    }
    return ,$values
}

function Assert-P2EvidenceRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $valid = (
        $Value.Length -le 1024 -and
        -not [string]::IsNullOrWhiteSpace($Value) -and
        -not $Value.StartsWith('/', [StringComparison]::Ordinal) -and
        $Value -notmatch '^[A-Za-z]:' -and
        $Value -notmatch '[\\\x00-\x1f\x7f]'
    )
    if ($valid) {
        foreach ($segment in $Value.Split('/')) {
            if ([string]::IsNullOrEmpty($segment) -or
                $segment -in @('.', '..')) {
                $valid = $false
                break
            }
        }
    }
    Assert-P2EvidenceCondition $valid "P2E_PATH" `
        "$Context is not a canonical relative slash path."
}

function Test-P2SourceEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Evidence)

    $rootFields = @(
        "artifact_kind", "evidence_id", "evidence_version", "status",
        "source_audit_id", "source_kind", "source_repository",
        "source_category", "source_revision", "source_relative_path",
        "symbol_or_record_key", "line_anchor_at_scan_time", "file_sha256",
        "observation_summary", "behavior_claims", "confidence",
        "known_ambiguities", "review_status", "license_boundary"
    )
    Assert-P2EvidenceExactProperties -Value $Evidence -Expected $rootFields `
        -Context "SourceEvidence"
    $root = [PSCustomObject]$Evidence
    Assert-P2EvidenceCondition (
        [string]$root.artifact_kind -ceq "SOURCE_EVIDENCE"
    ) "P2E_EVIDENCE_SCHEMA" "SourceEvidence.artifact_kind is unsupported."
    $evidenceId = Get-P2EvidenceInteger $root.evidence_id `
        "SourceEvidence.evidence_id" 1 2147483647
    $version = Get-P2EvidenceInteger $root.evidence_version `
        "SourceEvidence.evidence_version" 1 2147483647
    $status = Get-P2EvidenceEnum $root.status "SourceEvidence.status" @(
        "ACTIVE", "TOMBSTONE"
    )
    $auditId = Get-P2EvidenceString $root.source_audit_id `
        "SourceEvidence.source_audit_id" '^AUDIT_[0-9A-F]{16}$' 22
    $sourceKind = Get-P2EvidenceEnum $root.source_kind `
        "SourceEvidence.source_kind" @(
            "SOURCE_CODE", "SOURCE_SCHEMA", "SOURCE_TEST"
        )
    $repository = Get-P2EvidenceEnum $root.source_repository `
        "SourceEvidence.source_repository" @("battlelogic", "pokelib")
    $category = Get-P2EvidenceEnum $root.source_category `
        "SourceEvidence.source_category" $script:P2EvidenceAllowedCategories
    $revision = Get-P2EvidenceString $root.source_revision `
        "SourceEvidence.source_revision" '^[0-9a-f]{40}$' 40
    $relativePath = Get-P2EvidenceString $root.source_relative_path `
        "SourceEvidence.source_relative_path" '^.+$' 1024
    Assert-P2EvidenceRelativePath $relativePath `
        "SourceEvidence.source_relative_path"
    $symbol = Get-P2EvidenceString $root.symbol_or_record_key `
        "SourceEvidence.symbol_or_record_key" '^[^\x00-\x1f\x7f]+$' 512
    $lineAnchor = Get-P2EvidenceInteger $root.line_anchor_at_scan_time `
        "SourceEvidence.line_anchor_at_scan_time" 1 2147483647
    $fileHash = Get-P2EvidenceString $root.file_sha256 `
        "SourceEvidence.file_sha256" '^[0-9a-f]{64}$' 64
    $null = Get-P2EvidenceString $root.observation_summary `
        "SourceEvidence.observation_summary" '^[^\x00-\x1f\x7f]+$' 1024
    $confidence = Get-P2EvidenceEnum $root.confidence `
        "SourceEvidence.confidence" @("LOW", "MEDIUM", "HIGH")
    $reviewStatus = Get-P2EvidenceEnum $root.review_status `
        "SourceEvidence.review_status" @(
            "DRAFT", "HUMAN_REVIEWED", "VERIFIED"
        )
    Assert-P2EvidenceCondition (
        [string]$root.license_boundary -ceq "BEHAVIOR_EVIDENCE_ONLY"
    ) "P2E_EVIDENCE_SCHEMA" (
        "SourceEvidence.license_boundary must be BEHAVIOR_EVIDENCE_ONLY."
    )
    $null = Get-P2EvidenceStringArray $root.known_ambiguities `
        "SourceEvidence.known_ambiguities" 0 64 `
        '^[^\x00-\x1f\x7f]+$' 512

    Assert-P2EvidenceCondition (
        $null -ne $root.behavior_claims -and
        $root.behavior_claims -is [Array]
    ) "P2E_EVIDENCE_SCHEMA" "SourceEvidence.behavior_claims must be an array."
    $claims = @($root.behavior_claims)
    $minimumClaims = if ($status -ceq "ACTIVE") { 1 } else { 0 }
    $maximumClaims = if ($status -ceq "TOMBSTONE") { 0 } else { 256 }
    Assert-P2EvidenceCondition (
        $claims.Count -ge $minimumClaims -and
        $claims.Count -le $maximumClaims
    ) "P2E_EVIDENCE_SCHEMA" (
        "SourceEvidence.behavior_claims is invalid for status $status."
    )
    $claimKeys = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $previousKey = ""
    foreach ($claimValue in $claims) {
        Assert-P2EvidenceExactProperties -Value $claimValue -Expected @(
            "mechanism_id", "branch_id", "spec_field_pointer", "claim_summary"
        ) -Context "SourceEvidence behavior claim"
        $claim = [PSCustomObject]$claimValue
        $mechanismId = Get-P2EvidenceInteger $claim.mechanism_id `
            "behavior claim mechanism_id" 1 2147483647
        $branchId = Get-P2EvidenceInteger $claim.branch_id `
            "behavior claim branch_id" 0 2147483647
        $pointer = Get-P2EvidenceString $claim.spec_field_pointer `
            "behavior claim spec_field_pointer" '^/(?:[^\x00-\x1f\x7f])+$' 512
        $null = Get-P2EvidenceString $claim.claim_summary `
            "behavior claim claim_summary" '^[^\x00-\x1f\x7f]+$' 1024
        $key = "{0:D10}`t{1:D10}`t{2}" -f $mechanismId, $branchId, $pointer
        Assert-P2EvidenceCondition ($claimKeys.Add($key)) `
            "P2E_EVIDENCE_SCHEMA" "SourceEvidence repeats behavior claim '$key'."
        Assert-P2EvidenceCondition (
            [string]::IsNullOrEmpty($previousKey) -or
            [StringComparer]::Ordinal.Compare($previousKey, $key) -lt 0
        ) "P2E_EVIDENCE_ORDER" (
            "SourceEvidence behavior_claims must be in canonical claim order."
        )
        $previousKey = $key
    }

    if ($sourceKind -ceq "SOURCE_SCHEMA") {
        Assert-P2EvidenceCondition ($category -ceq "SCHEMA") `
            "P2E_SOURCE_KIND_CATEGORY" (
                "SOURCE_SCHEMA evidence must bind a SCHEMA audit entry."
            )
    }
    elseif ($sourceKind -ceq "SOURCE_TEST") {
        Assert-P2EvidenceCondition ($category -cin @("TEST", "SCRIPT_SCENARIO")) `
            "P2E_SOURCE_KIND_CATEGORY" (
                "SOURCE_TEST evidence must bind TEST or SCRIPT_SCENARIO."
            )
    }
    else {
        Assert-P2EvidenceCondition (
            $category -cnotin @("SCHEMA", "TEST", "SCRIPT_SCENARIO")
        ) "P2E_SOURCE_KIND_CATEGORY" (
            "SOURCE_CODE evidence cannot bind schema or test audit entries."
        )
    }

    $canonical = ConvertTo-BattleCanonicalJson -Value $root
    return [pscustomobject][ordered]@{
        PrimaryId = $evidenceId
        Version = $version
        Status = $status
        AuditId = $auditId
        SourceKind = $sourceKind
        Repository = $repository
        Category = $category
        Revision = $revision
        RelativePath = $relativePath
        Symbol = $symbol
        LineAnchor = $lineAnchor
        FileHash = $fileHash
        Confidence = $confidence
        ReviewStatus = $reviewStatus
        CanonicalJson = $canonical
        Sha256 = Get-BattleSha256Text -Text $canonical
    }
}

function ConvertFrom-P2EvidenceBytes {
    param(
        [AllowNull()][object]$Bytes,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-P2EvidenceCondition ($null -ne $Bytes -and $Bytes -is [byte[]]) `
        "P2E_EVIDENCE_BYTES" "$Context was not captured as bytes."
    $value = [byte[]]$Bytes
    Assert-P2EvidenceCondition ($value.Length -le 524288) `
        "P2E_TOO_LARGE" "$Context exceeds the 524288-byte evidence limit."
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($value)
    }
    catch {
        Throw-P2EvidenceJoinError "P2E_EVIDENCE_UTF8" `
            "$Context is not valid strict UTF-8."
    }
    if ($value.Length -ge 3 -and $value[0] -eq 0xef -and
        $value[1] -eq 0xbb -and $value[2] -eq 0xbf) {
        Throw-P2EvidenceJoinError "P2E_EVIDENCE_BOM" `
            "$Context must not contain a UTF-8 BOM."
    }
    try {
        return ConvertFrom-BattleStrictJson -Text $text -Label $Context
    }
    catch {
        Throw-P2EvidenceJoinError "P2E_EVIDENCE_JSON" `
            "$Context is not strict JSON: $($_.Exception.Message)"
    }
}

function Get-P2EvidenceVersionIndependentHash {
    param([Parameter(Mandatory = $true)][PSCustomObject]$Manifest)

    $projection = [ordered]@{}
    foreach ($property in $Manifest.PSObject.Properties) {
        if ([string]$property.Name -cne "evidence_version") {
            $projection[[string]$property.Name] = $property.Value
        }
    }
    return Get-BattleSha256Text (
        ConvertTo-BattleCanonicalJson ([pscustomobject]$projection)
    )
}

function Read-P2ValidatedEvidenceSet {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$View)

    Assert-P2RepositoryViewObject $View
    $paths = @(Get-P2RepositoryViewPaths -View $View `
        -Prefix $script:P2EvidenceDirectory)
    Assert-P2EvidenceCondition ($paths.Count -le $script:P2EvidenceMaxRecords) `
        "P2E_COUNT" "SourceEvidence exceeds the 65535-record limit."
    $records = [Collections.Generic.List[object]]::new()
    $inputs = [Collections.Generic.List[object]]::new()
    $seenIds = [Collections.Generic.HashSet[long]]::new()
    $seenAuditIds = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($pathValue in $paths) {
        $path = [string]$pathValue
        Assert-P2EvidenceCondition ($path -cmatch $script:P2EvidenceFilenamePattern) `
            "P2E_EVIDENCE_FILENAME" (
                "'$path' does not match the SourceEvidence filename contract."
            )
        $filenameId = [long]::Parse(
            [string]$Matches.id,
            [Globalization.CultureInfo]::InvariantCulture
        )
        $manifest = ConvertFrom-P2EvidenceBytes `
            -Bytes (Get-P2RepositoryViewBytes -View $View -RelativePath $path) `
            -Context $path
        $validation = Test-P2SourceEvidence -Evidence $manifest
        Assert-P2EvidenceCondition (
            $filenameId -eq [long]$validation.PrimaryId
        ) "P2E_EVIDENCE_ID_FILENAME" (
            "$path filename ID does not match evidence_id."
        )
        Assert-P2EvidenceCondition ($seenIds.Add([long]$validation.PrimaryId)) `
            "P2E_EVIDENCE_ID_DUPLICATE" (
                "evidence_id $($validation.PrimaryId) is repeated."
            )
        Assert-P2EvidenceCondition ($seenAuditIds.Add([string]$validation.AuditId)) `
            "P2E_AUDIT_LINK_DUPLICATE" (
                "source_audit_id $($validation.AuditId) is bound more than once."
            )
        $records.Add([pscustomobject][ordered]@{
            RelativePath = $path
            Manifest = $manifest
            Validation = $validation
        })
        $inputs.Add([pscustomobject][ordered]@{
            relative_path = $path
            canonical_sha256 = [string]$validation.Sha256
        })
    }

    if ([string]$View.Mode -cne "Repository") {
        $baselinePaths = @(Get-P2RepositoryViewPaths -View $View `
            -Prefix $script:P2EvidenceDirectory | Where-Object {
                $View.BaselineEntries.ContainsKey([string]$_)
            })
        # Include deleted HEAD evidence, which is absent from CandidateEntries.
        foreach ($baselinePath in @($View.BaselineEntries.Keys | Where-Object {
            ([string]$_).StartsWith(
                $script:P2EvidenceDirectory + '/',
                [StringComparison]::Ordinal
            )
        })) {
            if ($baselinePath -cnotin $baselinePaths) {
                $baselinePaths += [string]$baselinePath
            }
        }
        [Array]::Sort($baselinePaths, [StringComparer]::Ordinal)
        $baselineById = [Collections.Generic.Dictionary[long, object]]::new()
        $baselineMaxId = 0L
        foreach ($path in $baselinePaths) {
            Assert-P2EvidenceCondition (
                $path -cmatch $script:P2EvidenceFilenamePattern
            ) "P2E_EVIDENCE_FILENAME" "HEAD:$path has an invalid evidence filename."
            $baselineFilenameId = [long]::Parse(
                [string]$Matches.id,
                [Globalization.CultureInfo]::InvariantCulture
            )
            $baseline = ConvertFrom-P2EvidenceBytes `
                -Bytes (Get-P2RepositoryViewBaselineBytes `
                    -View $View -RelativePath $path) -Context "HEAD:$path"
            $baselineValidation = Test-P2SourceEvidence -Evidence $baseline
            $id = [long]$baselineValidation.PrimaryId
            Assert-P2EvidenceCondition ($baselineFilenameId -eq $id) `
                "P2E_EVIDENCE_ID_FILENAME" (
                    "HEAD:$path filename ID does not match evidence_id."
                )
            Assert-P2EvidenceCondition (-not $baselineById.ContainsKey($id)) `
                "P2E_EVIDENCE_ID_DUPLICATE" "HEAD repeats evidence_id $id."
            $baselineById.Add($id, [pscustomobject]@{
                Manifest = $baseline
                Validation = $baselineValidation
            })
            if ($id -gt $baselineMaxId) { $baselineMaxId = $id }
        }
        $candidateById = [Collections.Generic.Dictionary[long, object]]::new()
        foreach ($record in $records) {
            $candidateById.Add([long]$record.Validation.PrimaryId, $record)
        }
        foreach ($id in $baselineById.Keys) {
            Assert-P2EvidenceCondition ($candidateById.ContainsKey($id)) `
                "P2E_EVIDENCE_DELETE" (
                    "evidence_id $id was deleted instead of tombstoned."
                )
            $old = $baselineById[$id]
            $new = $candidateById[$id]
            if ([string]$old.Validation.Sha256 -ceq
                [string]$new.Validation.Sha256) {
                continue
            }
            Assert-P2EvidenceCondition (
                [string]$old.Validation.Status -cne "TOMBSTONE"
            ) "P2E_EVIDENCE_TOMBSTONE_IMMUTABLE" (
                "tombstoned evidence_id $id cannot change or revive."
            )
            Assert-P2EvidenceCondition (
                [long]$new.Validation.Version -eq
                ([long]$old.Validation.Version + 1)
            ) "P2E_EVIDENCE_VERSION" (
                "changed evidence_id $id must increment evidence_version once."
            )
            Assert-P2EvidenceCondition (
                (Get-P2EvidenceVersionIndependentHash `
                    ([PSCustomObject]$old.Manifest)) -cne
                (Get-P2EvidenceVersionIndependentHash `
                    ([PSCustomObject]$new.Manifest))
            ) "P2E_EVIDENCE_VERSION_EMPTY" (
                "evidence_id $id cannot advance version without a semantic change."
            )
        }
        foreach ($id in $candidateById.Keys) {
            if (-not $baselineById.ContainsKey($id)) {
                Assert-P2EvidenceCondition ($id -gt $baselineMaxId) `
                    "P2E_EVIDENCE_ID_APPEND" (
                        "new evidence_id $id must exceed baseline max $baselineMaxId."
                    )
                Assert-P2EvidenceCondition (
                    [long]$candidateById[$id].Validation.Version -eq 1
                ) "P2E_EVIDENCE_VERSION" (
                    "new evidence_id $id must start at evidence_version 1."
                )
            }
        }
    }

    $inputSet = [pscustomobject][ordered]@{
        schema_version = 1
        source_evidence = $inputs.ToArray()
    }
    $inputJson = ConvertTo-BattleCanonicalJson $inputSet
    return [pscustomobject][ordered]@{
        Records = $records.ToArray()
        InputSet = $inputSet
        InputSetJson = $inputJson
        InputSetHash = Get-BattleSha256Text $inputJson
    }
}

function Get-P2EvidenceSha256Bytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace(
            "-", ""
        ).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function ConvertFrom-P2EvidenceGovernanceBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xef -and
        $Bytes[1] -eq 0xbb -and $Bytes[2] -eq 0xbf) {
        Throw-P2EvidenceJoinError "P2E_AUDIT_UTF8" `
            "$Context must not contain a UTF-8 BOM."
    }
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
    }
    catch {
        Throw-P2EvidenceJoinError "P2E_AUDIT_UTF8" `
            "$Context is not valid strict UTF-8."
    }
    try {
        return ConvertFrom-BattleStrictJson -Text $text -Label $Context
    }
    catch {
        Throw-P2EvidenceJoinError "P2E_AUDIT_JSON" `
            "$Context is not strict JSON: $($_.Exception.Message)"
    }
}

# The caller must first prove the raw bytes equal the immutable tracked seal.
# That byte identity makes duplicate-key and numeric spelling checks redundant;
# the platform parser keeps the 5.5 MB baseline usable in normal gates.
function ConvertFrom-P2EvidenceSealedAuditBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xef -and
        $Bytes[1] -eq 0xbb -and $Bytes[2] -eq 0xbf) {
        Throw-P2EvidenceJoinError "P2E_AUDIT_UTF8" `
            "$Context must not contain a UTF-8 BOM."
    }
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
    }
    catch {
        Throw-P2EvidenceJoinError "P2E_AUDIT_UTF8" `
            "$Context is not valid strict UTF-8."
    }
    try {
        $value = $text | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Throw-P2EvidenceJoinError "P2E_AUDIT_JSON" `
            "$Context is not valid sealed JSON: $($_.Exception.Message)"
    }
    Assert-P2EvidenceCondition ($value -is [PSCustomObject]) `
        "P2E_AUDIT_JSON" "$Context must contain a JSON object."
    return $value
}

function Assert-P2EvidenceCapturedGovernanceUnchanged {
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][byte[]]$CandidateBytes
    )

    if ([string]$View.Mode -ceq "Repository") {
        return
    }
    $baselineBytes = Get-P2RepositoryViewBaselineBytes -View $View `
        -RelativePath $RelativePath -AllowMissing
    Assert-P2EvidenceCondition ($null -ne $baselineBytes) `
        "P2E_AUDIT_SEAL_BASELINE" (
            "$RelativePath must already exist in HEAD before P2 evidence joins."
        )
    Assert-P2EvidenceCondition (
        Test-P2RepositoryViewByteEquality `
            -Left $CandidateBytes -Right ([byte[]]$baselineBytes)
    ) "P2E_AUDIT_SEAL_CHANGED" (
        "$RelativePath differs from HEAD; update the sealed P0 baseline separately."
    )
}

function Read-P2EvidenceGovernance {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$View)

    $sealBytes = Get-P2RepositoryViewBytes -View $View `
        -RelativePath $script:P2EvidenceSealRelativePath
    $policyBytes = Get-P2RepositoryViewBytes -View $View `
        -RelativePath $script:P2EvidencePolicyRelativePath
    $baselineBytes = Get-P2RepositoryViewBytes -View $View `
        -RelativePath $script:P2EvidenceBaselineRelativePath
    Assert-P2EvidenceCapturedGovernanceUnchanged -View $View `
        -RelativePath $script:P2EvidenceSealRelativePath `
        -CandidateBytes $sealBytes
    Assert-P2EvidenceCapturedGovernanceUnchanged -View $View `
        -RelativePath $script:P2EvidencePolicyRelativePath `
        -CandidateBytes $policyBytes
    Assert-P2EvidenceCapturedGovernanceUnchanged -View $View `
        -RelativePath $script:P2EvidenceBaselineRelativePath `
        -CandidateBytes $baselineBytes

    $seal = ConvertFrom-P2EvidenceGovernanceBytes -Bytes $sealBytes `
        -Context $script:P2EvidenceSealRelativePath
    Assert-P2EvidenceExactProperties -Value $seal -Expected @(
        "baseline_id", "category_counts", "counts", "evidence_status_counts",
        "manifest_kind", "release_status_counts", "schema_version",
        "scope_disposition_counts", "scope_id", "seal_id",
        "source_audit_manifest_sha256", "source_audit_policy_sha256",
        "source_index_baseline_sha256", "source_payloads_verified",
        "unclassified_modules"
    ) -Context "Source audit seal"
    Assert-P2EvidenceCondition (
        (Get-P2EvidenceInteger $seal.schema_version `
            "source audit seal schema_version" 1 1) -eq 1 -and
        [string]$seal.manifest_kind -ceq "SOURCE_AUDIT_SEAL" -and
        [string]$seal.seal_id -ceq "SV_SOURCE_AUDIT_P0_V1" -and
        $seal.source_payloads_verified -is [bool] -and
        [bool]$seal.source_payloads_verified
    ) "P2E_AUDIT_SEAL" "The tracked source audit seal is unsupported."
    foreach ($field in @(
        "source_audit_manifest_sha256", "source_audit_policy_sha256",
        "source_index_baseline_sha256"
    )) {
        $null = Get-P2EvidenceString $seal.$field "source audit seal $field" `
            '^[0-9a-f]{64}$' 64
    }
    Assert-P2EvidenceCondition (
        (Get-P2EvidenceSha256Bytes $policyBytes) -ceq
        [string]$seal.source_audit_policy_sha256
    ) "P2E_AUDIT_POLICY_HASH" (
        "The tracked source audit policy does not match its seal."
    )
    Assert-P2EvidenceCondition (
        (Get-P2EvidenceSha256Bytes $baselineBytes) -ceq
        [string]$seal.source_index_baseline_sha256
    ) "P2E_BASELINE_HASH" (
        "The tracked source index baseline does not match its seal."
    )

    $baseline = ConvertFrom-P2EvidenceGovernanceBytes -Bytes $baselineBytes `
        -Context $script:P2EvidenceBaselineRelativePath
    Assert-P2EvidenceExactProperties -Value $baseline -Expected @(
        "schema_version", "manifest_kind", "baseline_id", "repositories",
        "index_files", "scanner_files", "expected_counts", "known_ambiguities"
    ) -Context "Source index baseline"
    Assert-P2EvidenceCondition (
        (Get-P2EvidenceInteger $baseline.schema_version `
            "source index baseline schema_version" 1 1) -eq 1 -and
        [string]$baseline.manifest_kind -ceq "SOURCE_INDEX_BASELINE" -and
        [string]$baseline.baseline_id -ceq [string]$seal.baseline_id
    ) "P2E_BASELINE_IDENTITY" (
        "The source index baseline identity does not match its seal."
    )
    Assert-P2EvidenceCondition (
        $baseline.repositories -is [Array] -and
        @($baseline.repositories).Count -eq 2
    ) "P2E_BASELINE_REPOSITORIES" (
        "The source index baseline must contain battlelogic and pokelib."
    )
    $repositories = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($repositoryValue in @($baseline.repositories)) {
        Assert-P2EvidenceExactProperties -Value $repositoryValue -Expected @(
            "repository", "branch", "commit", "head_tree", "file_count",
            "source_aggregate_sha256", "dirty_path_count", "dirty_paths_sha256"
        ) -Context "Source index repository"
        $repository = [PSCustomObject]$repositoryValue
        $name = Get-P2EvidenceEnum $repository.repository `
            "source index repository name" @("battlelogic", "pokelib")
        Assert-P2EvidenceCondition (-not $repositories.ContainsKey($name)) `
            "P2E_BASELINE_REPOSITORIES" "Repository '$name' is repeated."
        $null = Get-P2EvidenceString $repository.commit `
            "source index repository commit" '^[0-9a-f]{40}$' 40
        $null = Get-P2EvidenceString $repository.head_tree `
            "source index repository tree" '^[0-9a-f]{40}$' 40
        $repositories.Add($name, $repository)
    }
    foreach ($requiredRepository in @("battlelogic", "pokelib")) {
        Assert-P2EvidenceCondition ($repositories.ContainsKey($requiredRepository)) `
            "P2E_BASELINE_REPOSITORIES" (
                "Source index baseline omits '$requiredRepository'."
            )
    }
    return [pscustomobject][ordered]@{
        Seal = $seal
        SealHash = Get-P2EvidenceSha256Bytes $sealBytes
        Baseline = $baseline
        Repositories = $repositories
    }
}

function Read-P2EvidenceAuditBytes {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$AuditManifestPath = ""
    )

    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $expected = [IO.Path]::GetFullPath((Join-Path $root `
        $script:P2EvidenceAuditRelativePath.Replace('/', '\')))
    $requested = if ([string]::IsNullOrWhiteSpace($AuditManifestPath)) {
        $expected
    }
    elseif ([IO.Path]::IsPathRooted($AuditManifestPath)) {
        [IO.Path]::GetFullPath($AuditManifestPath)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $root $AuditManifestPath))
    }
    Assert-P2EvidenceCondition (
        $requested.Equals($expected, [StringComparison]::OrdinalIgnoreCase)
    ) "P2E_AUDIT_PATH" (
        "The source audit manifest must use the ignored canonical P0 path."
    )
    Assert-P2EvidenceCondition (Test-Path -LiteralPath $requested -PathType Leaf) `
        "P2E_AUDIT_REQUIRED" (
            "SourceEvidence exists but the sealed P0 audit manifest is absent."
        )
    $guard = $null
    $stream = $null
    try {
        $guard = Open-P2RepositoryViewVerifiedHandle -Path $requested `
            -ExpectedFinalPath $expected -ExpectedKind File -Access Read `
            -ErrorPrefix "P2E_AUDIT"
        $stream = [IO.FileStream]::new(
            [Microsoft.Win32.SafeHandles.SafeFileHandle]$guard.Handle,
            [IO.FileAccess]::Read
        )
        Assert-P2EvidenceCondition (
            $stream.Length -gt 0 -and
            $stream.Length -le $script:P2EvidenceMaxAuditBytes
        ) "P2E_TOO_LARGE" (
            "Source audit manifest must be 1..$script:P2EvidenceMaxAuditBytes bytes."
        )
        $bytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            Assert-P2EvidenceCondition ($read -gt 0) "P2E_AUDIT_TORN_READ" `
                "The source audit manifest ended during its bounded read."
            $offset += $read
        }
        Assert-P2EvidenceCondition ($stream.ReadByte() -eq -1) `
            "P2E_AUDIT_TORN_READ" (
                "The source audit manifest changed during its bounded read."
            )
        return ,$bytes
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
        elseif ($null -ne $guard) {
            $guard.Handle.Dispose()
        }
    }
}

function Add-P2EvidenceCount {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Counts,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if (-not $Counts.ContainsKey($Key)) { $Counts[$Key] = 0L }
    $Counts[$Key] = [long]$Counts[$Key] + 1L
}

function Assert-P2EvidenceCountMap {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Computed,
        [AllowNull()][object]$Expected,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-P2EvidenceCondition ($Expected -is [PSCustomObject]) `
        "P2E_AUDIT_COUNT" "$Context must be an object."
    $expectedNames = @($Expected.PSObject.Properties.Name)
    $computedNames = @($Computed.Keys | ForEach-Object { [string]$_ })
    [Array]::Sort($expectedNames, [StringComparer]::Ordinal)
    [Array]::Sort($computedNames, [StringComparer]::Ordinal)
    Assert-P2EvidenceCondition (
        ($expectedNames -join "`n") -ceq ($computedNames -join "`n")
    ) "P2E_AUDIT_COUNT" "$Context keys do not match the audit entries."
    foreach ($name in $computedNames) {
        Assert-P2EvidenceCondition (
            (Get-P2EvidenceInteger $Expected.$name "$Context.$name" `
                0 2147483647) -eq [long]$Computed[$name]
        ) "P2E_AUDIT_COUNT" "$Context.$name does not match the audit entries."
    }
}

function Assert-P2EvidencePositiveIdArray {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-P2EvidenceCondition ($null -ne $Value -and $Value -is [Array]) `
        "P2E_AUDIT_SCHEMA" "$Context must be an array."
    Assert-P2EvidenceCondition (@($Value).Count -le 4096) `
        "P2E_AUDIT_SCHEMA" "$Context exceeds 4096 items."
    $seen = [Collections.Generic.HashSet[long]]::new()
    foreach ($item in @($Value)) {
        $id = Get-P2EvidenceInteger $item "$Context item" 1 2147483647
        Assert-P2EvidenceCondition ($seen.Add($id)) `
            "P2E_AUDIT_SCHEMA" "$Context repeats ID $id."
    }
}

function Test-P2EvidenceAuditManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][object]$Governance,
        [switch]$SealedBytesVerified
    )

    Assert-P2EvidenceExactProperties -Value $Manifest -Expected @(
        "schema_version", "manifest_kind", "manifest_mode", "scope_id",
        "baseline", "entries"
    ) -Context "SourceAuditDispositionManifest"
    $root = [PSCustomObject]$Manifest
    Assert-P2EvidenceCondition (
        (Get-P2EvidenceInteger $root.schema_version `
            "source audit schema_version" 1 1) -eq 1 -and
        [string]$root.manifest_kind -ceq "SOURCE_AUDIT_DISPOSITION" -and
        [string]$root.manifest_mode -ceq "BASELINE" -and
        [string]$root.scope_id -ceq [string]$Governance.Seal.scope_id
    ) "P2E_AUDIT_IDENTITY" (
        "Source audit kind, mode, schema, or scope does not match the seal."
    )
    Assert-P2EvidenceExactProperties -Value $root.baseline -Expected @(
        "source_index_manifest_sha256", "repositories", "expected_counts"
    ) -Context "Source audit baseline"
    Assert-P2EvidenceCondition (
        [string]$root.baseline.source_index_manifest_sha256 -ceq
        [string]$Governance.Seal.source_index_baseline_sha256
    ) "P2E_SOURCE_INDEX_HASH" (
        "Source audit baseline does not bind the sealed source index."
    )
    Assert-P2EvidenceCondition (
        $root.baseline.repositories -is [Array] -and
        @($root.baseline.repositories).Count -eq 2
    ) "P2E_AUDIT_BASELINE" (
        "Source audit baseline must contain exactly two repositories."
    )
    $auditRepositories = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($repositoryValue in @($root.baseline.repositories)) {
        Assert-P2EvidenceExactProperties -Value $repositoryValue -Expected @(
            "repository", "branch", "commit", "head_tree",
            "source_aggregate_sha256", "dirty_paths_sha256", "dirty_path_count"
        ) -Context "Source audit repository baseline"
        $repository = [PSCustomObject]$repositoryValue
        $name = Get-P2EvidenceEnum $repository.repository `
            "source audit repository" @("battlelogic", "pokelib")
        Assert-P2EvidenceCondition (-not $auditRepositories.ContainsKey($name)) `
            "P2E_AUDIT_BASELINE" "Source audit repeats repository '$name'."
        Assert-P2EvidenceCondition ($Governance.Repositories.ContainsKey($name)) `
            "P2E_AUDIT_BASELINE" "Source index omits repository '$name'."
        $sourceRepository = [PSCustomObject]$Governance.Repositories[$name]
        foreach ($field in @(
            "branch", "commit", "head_tree", "source_aggregate_sha256",
            "dirty_paths_sha256", "dirty_path_count"
        )) {
            Assert-P2EvidenceCondition (
                [string]$repository.$field -ceq [string]$sourceRepository.$field
            ) "P2E_AUDIT_BASELINE" (
                "Source audit repository '$name' field '$field' is stale."
            )
        }
        $auditRepositories.Add($name, $repository)
    }

    Assert-P2EvidenceCondition ($root.entries -is [Array]) `
        "P2E_AUDIT_SCHEMA" "Source audit entries must be an array."
    $entries = @($root.entries)
    Assert-P2EvidenceCondition (
        $entries.Count -gt 0 -and
        $entries.Count -le $script:P2EvidenceMaxRecords
    ) "P2E_COUNT" "Source audit entry count is outside 1..65535."
    if ($SealedBytesVerified) {
        Assert-P2EvidenceCondition (
            (Get-P2EvidenceInteger $root.baseline.expected_counts.audit_entries `
                "source audit expected audit_entries" 1 65535) -eq
                $entries.Count -and
            (Get-P2EvidenceInteger $Governance.Seal.counts.audit_entries `
                "source audit seal audit_entries" 1 65535) -eq $entries.Count
        ) "P2E_AUDIT_COUNT" (
            "Sealed source audit entry count does not match baseline and seal."
        )
        $sealedAuditById = `
            [Collections.Generic.Dictionary[string, object]]::new(
                [StringComparer]::Ordinal
            )
        foreach ($entryValue in $entries) {
            Assert-P2EvidenceCondition ($entryValue -is [PSCustomObject]) `
                "P2E_AUDIT_SCHEMA" "A sealed source audit entry is not an object."
            $auditIdProperty = $entryValue.PSObject.Properties['audit_id']
            Assert-P2EvidenceCondition ($null -ne $auditIdProperty) `
                "P2E_AUDIT_SCHEMA" "A sealed source audit entry omits audit_id."
            $auditId = [string]$auditIdProperty.Value
            Assert-P2EvidenceCondition (
                $auditId -cmatch '^AUDIT_[0-9A-F]{16}$' -and
                -not $sealedAuditById.ContainsKey($auditId)
            ) "P2E_AUDIT_ID_DUPLICATE" (
                "A sealed source audit ID is invalid or repeated: '$auditId'."
            )
            $sealedAuditById.Add($auditId, $entryValue)
        }
        return [pscustomobject][ordered]@{
            Manifest = $root
            AuditById = $sealedAuditById
            Repositories = $auditRepositories
            EntryCount = [long]$entries.Count
        }
    }
    $entryFields = @(
        "audit_id", "source_repository", "source_path", "source_sha256",
        "source_symbol_or_edge", "source_category", "domain_package",
        "mechanism_ids", "branch_ids", "target_godot_types", "fixture_ids",
        "scope_disposition", "evidence_status", "release_status",
        "test_evidence_disposition", "classification_rule_id", "reason_code",
        "reason", "known_ambiguities", "review_status"
    )
    $auditById = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    $identities = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $categoryCounts = @{}
    $evidenceCounts = @{}
    $scopeCounts = @{}
    $releaseCounts = @{}
    $previousSortKey = ""
    foreach ($entryValue in $entries) {
        if ($SealedBytesVerified) {
            Assert-P2EvidenceCondition (
                $entryValue -is [PSCustomObject] -and
                @($entryValue.PSObject.Properties).Count -eq $entryFields.Count
            ) "P2E_AUDIT_SCHEMA" "A sealed source audit entry is not closed."
            foreach ($field in $entryFields) {
                Assert-P2EvidenceCondition (
                    $null -ne $entryValue.PSObject.Properties[$field]
                ) "P2E_AUDIT_SCHEMA" (
                    "A sealed source audit entry omits '$field'."
                )
            }
        }
        else {
            Assert-P2EvidenceExactProperties -Value $entryValue `
                -Expected $entryFields -Context "Source audit entry"
        }
        $entry = [PSCustomObject]$entryValue
        if ($SealedBytesVerified) {
            $auditId = [string]$entry.audit_id
            $repository = [string]$entry.source_repository
            $category = [string]$entry.source_category
            $path = [string]$entry.source_path
            $sourceHash = [string]$entry.source_sha256
            $symbol = [string]$entry.source_symbol_or_edge
            Assert-P2EvidenceCondition (
                $auditId -cmatch '^AUDIT_[0-9A-F]{16}$' -and
                $repository -cin @("battlelogic", "pokelib") -and
                $category -cin $script:P2EvidenceAllowedCategories -and
                $sourceHash -cmatch '^[0-9a-f]{64}$' -and
                -not [string]::IsNullOrWhiteSpace($path) -and
                -not [string]::IsNullOrWhiteSpace($symbol)
            ) "P2E_AUDIT_SCHEMA" (
                "A sealed source audit entry has invalid identity fields."
            )
        }
        else {
            $auditId = Get-P2EvidenceString $entry.audit_id `
                "source audit ID" '^AUDIT_[0-9A-F]{16}$' 22
            $repository = Get-P2EvidenceEnum $entry.source_repository `
                "source audit repository" @("battlelogic", "pokelib")
            $category = Get-P2EvidenceEnum $entry.source_category `
                "source audit category" $script:P2EvidenceAllowedCategories
            $path = Get-P2EvidenceString $entry.source_path `
                "source audit path" '^.+$' 1024
            Assert-P2EvidenceRelativePath $path "source audit path"
            $sourceHash = Get-P2EvidenceString $entry.source_sha256 `
                "source audit hash" '^[0-9a-f]{64}$' 64
            $symbol = Get-P2EvidenceString $entry.source_symbol_or_edge `
                "source audit symbol" '^[^\x00-\x1f\x7f]+$' 1024
        }
        $identity = "$repository`t$category`t$path`t$symbol"
        $expectedAuditId = "AUDIT_" + (
            Get-BattleSha256Text -Text $identity
        ).Substring(0, 16).ToUpperInvariant()
        Assert-P2EvidenceCondition ($auditId -ceq $expectedAuditId) `
            "P2E_AUDIT_ID_DERIVATION" (
                "Source audit ID '$auditId' does not match its identity."
            )
        Assert-P2EvidenceCondition (-not $auditById.ContainsKey($auditId)) `
            "P2E_AUDIT_ID_DUPLICATE" "Source audit ID '$auditId' is repeated."
        Assert-P2EvidenceCondition ($identities.Add($identity)) `
            "P2E_AUDIT_IDENTITY_DUPLICATE" (
                "Source audit identity '$identity' is repeated."
            )
        $sortKey = "$category`t$repository`t$path`t$symbol"
        Assert-P2EvidenceCondition (
            [string]::IsNullOrEmpty($previousSortKey) -or
            [StringComparer]::Ordinal.Compare($previousSortKey, $sortKey) -lt 0
        ) "P2E_AUDIT_ORDER" (
            "Source audit entries are not in canonical identity order."
        )
        $previousSortKey = $sortKey
        if (-not $SealedBytesVerified) {
            $null = Get-P2EvidenceEnum $entry.scope_disposition `
                "source audit scope disposition" @(
                    "IMPLEMENT", "MERGED_INTO_OTHER_MECHANISM", "DEFERRED_N0",
                    "TEXT_ONLY", "OUT_OF_SCOPE_PRESENTATION",
                    "REJECTED_UNVERIFIED", "NOT_APPLICABLE"
                )
            $null = Get-P2EvidenceEnum $entry.evidence_status `
                "source audit evidence status" @(
                    "CLEAN_INDEXED", "DIRTY_UNVERIFIED", "MISSING_SOURCE",
                    "STALE_INDEX"
                )
            $null = Get-P2EvidenceEnum $entry.release_status `
                "source audit release status" @(
                    "NOT_STARTED", "SPECIFIED", "IMPORTED", "BOUND",
                    "IMPLEMENTED", "VERIFIED", "RELEASED", "BLOCKED_SOURCE",
                    "REJECTED_UNVERIFIED"
                )
            $null = Get-P2EvidenceEnum $entry.test_evidence_disposition `
                "source audit test disposition" @(
                    "PORT_BEHAVIOR", "REPLACED_BY_SYNTHETIC_FIXTURE",
                    "NOT_APPLICABLE"
                )
            $null = Get-P2EvidenceEnum $entry.review_status `
                "source audit review status" @(
                    "GENERATED_SCOPE_CLASSIFICATION", "HUMAN_REVIEWED", "VERIFIED"
                )
            foreach ($field in @(
                "domain_package", "classification_rule_id", "reason_code", "reason"
            )) {
                $null = Get-P2EvidenceString $entry.$field `
                    "source audit $field" '^[^\x00-\x1f\x7f]+$' 2048
            }
            Assert-P2EvidencePositiveIdArray $entry.mechanism_ids `
                "source audit mechanism_ids"
            Assert-P2EvidencePositiveIdArray $entry.branch_ids `
                "source audit branch_ids"
            Assert-P2EvidencePositiveIdArray $entry.fixture_ids `
                "source audit fixture_ids"
            $null = Get-P2EvidenceStringArray $entry.target_godot_types `
                "source audit target_godot_types" 0 4096 `
                '^[A-Za-z_][A-Za-z0-9_]*$' 128
            $null = Get-P2EvidenceStringArray $entry.known_ambiguities `
                "source audit known_ambiguities" 0 4096 `
                '^[^\x00-\x1f\x7f]+$' 1024
        }
        $auditById.Add($auditId, $entry)
        Add-P2EvidenceCount $categoryCounts $category
        Add-P2EvidenceCount $evidenceCounts ([string]$entry.evidence_status)
        Add-P2EvidenceCount $scopeCounts ([string]$entry.scope_disposition)
        Add-P2EvidenceCount $releaseCounts ([string]$entry.release_status)
        $null = $sourceHash
    }
    Assert-P2EvidenceCondition (
        (Get-P2EvidenceInteger $root.baseline.expected_counts.audit_entries `
            "source audit expected audit_entries" 1 65535) -eq $entries.Count -and
        (Get-P2EvidenceInteger $Governance.Seal.counts.audit_entries `
            "source audit seal audit_entries" 1 65535) -eq $entries.Count
    ) "P2E_AUDIT_COUNT" (
        "Source audit entry count does not match baseline and seal."
    )
    Assert-P2EvidenceCountMap $categoryCounts `
        $Governance.Seal.category_counts "source audit category counts"
    Assert-P2EvidenceCountMap $evidenceCounts `
        $Governance.Seal.evidence_status_counts "source audit evidence counts"
    Assert-P2EvidenceCountMap $scopeCounts `
        $Governance.Seal.scope_disposition_counts "source audit scope counts"
    Assert-P2EvidenceCountMap $releaseCounts `
        $Governance.Seal.release_status_counts "source audit release counts"
    return [pscustomobject][ordered]@{
        Manifest = $root
        AuditById = $auditById
        Repositories = $auditRepositories
        EntryCount = [long]$entries.Count
    }
}

function Resolve-P2EvidenceJsonPointer {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Mechanism,
        [Parameter(Mandatory = $true)][string]$Pointer,
        [Parameter(Mandatory = $true)][long]$EvidenceId
    )

    Assert-P2EvidenceCondition ($Pointer.StartsWith('/', [StringComparison]::Ordinal)) `
        "P2E_CLAIM_POINTER" (
            "Evidence $EvidenceId claim pointer must start with '/'."
        )
    $rawSegments = @($Pointer.Substring(1).Split('/'))
    Assert-P2EvidenceCondition ($rawSegments.Count -gt 0) `
        "P2E_CLAIM_POINTER" "Evidence $EvidenceId claim pointer is empty."
    $segments = [Collections.Generic.List[string]]::new()
    foreach ($raw in $rawSegments) {
        Assert-P2EvidenceCondition ($raw -cnotmatch '~(?:[^01]|$)') `
            "P2E_CLAIM_POINTER_ESCAPE" (
                "Evidence $EvidenceId claim pointer has an invalid '~' escape."
            )
        $segments.Add($raw.Replace('~1', '/').Replace('~0', '~'))
    }
    Assert-P2EvidenceCondition (
        [string]$segments[0] -cin $script:P2EvidenceBehaviorFields
    ) "P2E_CLAIM_POINTER_METADATA" (
        "Evidence $EvidenceId claim pointer targets non-behavior field " +
        "'$($segments[0])'."
    )

    [object]$current = $Mechanism
    foreach ($segment in $segments) {
        if ($current -is [PSCustomObject]) {
            $property = $null
            foreach ($candidateProperty in $current.PSObject.Properties) {
                if ([string]$candidateProperty.Name -ceq [string]$segment) {
                    $property = $candidateProperty
                    break
                }
            }
            Assert-P2EvidenceCondition ($null -ne $property) `
                "P2E_CLAIM_POINTER_MISSING" (
                    "Evidence $EvidenceId claim pointer '$Pointer' does not resolve."
                )
            $current = $property.Value
            continue
        }
        if ($current -is [Array]) {
            Assert-P2EvidenceCondition ($segment -cmatch '^(?:0|[1-9][0-9]*)$') `
                "P2E_CLAIM_POINTER_INDEX" (
                    "Evidence $EvidenceId claim pointer uses a noncanonical index."
                )
            $index = 0L
            Assert-P2EvidenceCondition (
                [long]::TryParse(
                    $segment,
                    [Globalization.NumberStyles]::None,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [ref]$index
                ) -and $index -ge 0 -and $index -lt @($current).Count
            ) "P2E_CLAIM_POINTER_INDEX" (
                "Evidence $EvidenceId claim pointer index is outside its array."
            )
            $current = @($current)[[int]$index]
            continue
        }
        Throw-P2EvidenceJoinError "P2E_CLAIM_POINTER_SCALAR" (
            "Evidence $EvidenceId claim pointer traverses a scalar value."
        )
    }
    return $current
}

function Test-P2EvidenceIdArrayContains {
    param(
        [AllowNull()][object]$Values,
        [Parameter(Mandatory = $true)][long]$Identifier
    )

    foreach ($value in @($Values)) {
        if ([long]$value -eq $Identifier) { return $true }
    }
    return $false
}

function Get-P2EvidenceSortedLongArray {
    param([AllowNull()][object]$Values)

    [long[]]$result = @($Values | ForEach-Object { [long]$_ })
    [Array]::Sort($result)
    return $result
}

function Get-P2EvidenceSortedStringArray {
    param([AllowNull()][object]$Values)

    [string[]]$result = @($Values | ForEach-Object { [string]$_ })
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result
}

function Get-P2EvidenceRecordBlockers {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][PSCustomObject]$AuditEntry
    )

    $blockers = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    if ([string]$Record.Validation.Status -ceq "TOMBSTONE") {
        $null = $blockers.Add("EVIDENCE_TOMBSTONED")
    }
    switch ([string]$AuditEntry.evidence_status) {
        "DIRTY_UNVERIFIED" { $null = $blockers.Add("SOURCE_DIRTY_UNVERIFIED") }
        "MISSING_SOURCE" { $null = $blockers.Add("SOURCE_MISSING") }
        "STALE_INDEX" { $null = $blockers.Add("SOURCE_STALE_INDEX") }
    }
    switch ([string]$AuditEntry.scope_disposition) {
        "MERGED_INTO_OTHER_MECHANISM" { $null = $blockers.Add("SCOPE_MERGED") }
        "DEFERRED_N0" { $null = $blockers.Add("SCOPE_DEFERRED_N0") }
        "TEXT_ONLY" { $null = $blockers.Add("SCOPE_TEXT_ONLY") }
        "OUT_OF_SCOPE_PRESENTATION" {
            $null = $blockers.Add("SCOPE_OUT_OF_SCOPE_PRESENTATION")
        }
        "REJECTED_UNVERIFIED" {
            $null = $blockers.Add("SCOPE_REJECTED_UNVERIFIED")
        }
        "NOT_APPLICABLE" { $null = $blockers.Add("SCOPE_NOT_APPLICABLE") }
    }
    if ([string]$Record.Validation.ReviewStatus -cne "VERIFIED") {
        $null = $blockers.Add("REVIEW_NOT_VERIFIED")
    }
    if ([string]$Record.Validation.Confidence -cne "HIGH") {
        $null = $blockers.Add("CONFIDENCE_NOT_HIGH")
    }
    if ([string]$Record.Validation.SourceKind -ceq "SOURCE_TEST" -and
        [string]$AuditEntry.test_evidence_disposition -cne "PORT_BEHAVIOR") {
        $null = $blockers.Add("TEST_NOT_PORT_BEHAVIOR")
    }
    return Get-P2EvidenceSortedStringArray @($blockers)
}

function Assert-P2EvidenceAuditLink {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][object]$AuditValidation,
        [Parameter(Mandatory = $true)][object]$Governance
    )

    $validation = $Record.Validation
    $auditId = [string]$validation.AuditId
    Assert-P2EvidenceCondition ($AuditValidation.AuditById.ContainsKey($auditId)) `
        "P2E_AUDIT_ID_MISSING" (
            "Evidence $($validation.PrimaryId) references unknown audit ID '$auditId'."
        )
    $entry = [PSCustomObject]$AuditValidation.AuditById[$auditId]
    $entryIdentity = (
        "$([string]$entry.source_repository)`t" +
        "$([string]$entry.source_category)`t" +
        "$([string]$entry.source_path)`t" +
        [string]$entry.source_symbol_or_edge
    )
    $derivedAuditId = "AUDIT_" + (
        Get-BattleSha256Text -Text $entryIdentity
    ).Substring(0, 16).ToUpperInvariant()
    Assert-P2EvidenceCondition ($auditId -ceq $derivedAuditId) `
        "P2E_AUDIT_ID_DERIVATION" (
            "Linked audit ID '$auditId' does not match its source identity."
        )
    $mismatches = [Collections.Generic.List[string]]::new()
    if ([string]$validation.Repository -cne [string]$entry.source_repository) {
        $mismatches.Add("source_repository")
    }
    if ([string]$validation.Category -cne [string]$entry.source_category) {
        $mismatches.Add("source_category")
    }
    if ([string]$validation.RelativePath -cne [string]$entry.source_path) {
        $mismatches.Add("source_relative_path")
    }
    if ([string]$validation.Symbol -cne [string]$entry.source_symbol_or_edge) {
        $mismatches.Add("symbol_or_record_key")
    }
    if ([string]$validation.FileHash -cne [string]$entry.source_sha256) {
        $mismatches.Add("file_sha256")
    }
    Assert-P2EvidenceCondition (
        $Governance.Repositories.ContainsKey([string]$validation.Repository)
    ) "P2E_AUDIT_LINK_MISMATCH" (
        "Evidence $($validation.PrimaryId) repository is absent from the baseline."
    )
    $repository = [PSCustomObject]$Governance.Repositories[
        [string]$validation.Repository
    ]
    if ([string]$validation.Revision -cne [string]$repository.commit -and
        [string]$validation.Revision -cne [string]$repository.head_tree) {
        $mismatches.Add("source_revision")
    }
    Assert-P2EvidenceCondition ($mismatches.Count -eq 0) `
        "P2E_AUDIT_LINK_MISMATCH" (
            "Evidence $($validation.PrimaryId) differs from audit '$auditId' in " +
            "[$($mismatches -join ', ')]."
        )
    return $entry
}

function Invoke-P2ValidatedSourceEvidenceJoinCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Compilation,
        [Parameter(Mandatory = $true)][object]$EvidenceSet,
        [Parameter(Mandatory = $true)][object]$Governance,
        [AllowNull()][object]$AuditValidation
    )

    foreach ($field in @(
        "CompilerContractVersion", "SpecSet", "SpecManifestHash"
    )) {
        Assert-P2EvidenceCondition (
            $Compilation.PSObject.Properties.Name -ccontains $field
        ) "P2E_COMPILATION" "Compilation omits '$field'."
    }
    Assert-P2EvidenceCondition (
        [long]$Compilation.CompilerContractVersion -eq
        [long]$script:P2CompilerContractVersion
    ) "P2E_COMPILATION" "Source spec compiler contract version is unsupported."
    foreach ($field in @("MechanismSpecs", "InputSetHash")) {
        Assert-P2EvidenceCondition (
            $Compilation.SpecSet.PSObject.Properties.Name -ccontains $field
        ) "P2E_COMPILATION" "Compilation.SpecSet omits '$field'."
    }
    foreach ($field in @("Records", "InputSetHash")) {
        Assert-P2EvidenceCondition (
            $EvidenceSet.PSObject.Properties.Name -ccontains $field
        ) "P2E_EVIDENCE_SET" "EvidenceSet omits '$field'."
    }
    $records = @($EvidenceSet.Records)
    Assert-P2EvidenceCondition (
        $records.Count -eq 0 -or $null -ne $AuditValidation
    ) "P2E_AUDIT_REQUIRED" (
        "A nonempty SourceEvidence catalog requires the sealed P0 audit manifest."
    )

    $mechanisms = [Collections.Generic.Dictionary[long, object]]::new()
    foreach ($mechanismRecordValue in @($Compilation.SpecSet.MechanismSpecs)) {
        $mechanismRecord = [PSCustomObject]$mechanismRecordValue
        $mechanism = [PSCustomObject]$mechanismRecord.Manifest
        $mechanismId = [long]$mechanism.mechanism_id
        Assert-P2EvidenceCondition (-not $mechanisms.ContainsKey($mechanismId)) `
            "P2E_MECHANISM_DUPLICATE" "Mechanism $mechanismId is repeated."
        $mechanisms.Add($mechanismId, $mechanism)
    }
    $evidenceById = [Collections.Generic.Dictionary[long, object]]::new()
    $auditEntriesByEvidence = [Collections.Generic.Dictionary[long, object]]::new()
    $blockersByEvidence = [Collections.Generic.Dictionary[long, object]]::new()
    $mechanismIdsByEvidence = [Collections.Generic.Dictionary[long, object]]::new()
    foreach ($recordValue in $records) {
        $record = [PSCustomObject]$recordValue
        $id = [long]$record.Validation.PrimaryId
        Assert-P2EvidenceCondition (-not $evidenceById.ContainsKey($id)) `
            "P2E_EVIDENCE_ID_DUPLICATE" "Evidence ID $id is repeated."
        $evidenceById.Add($id, $record)
        $entry = Assert-P2EvidenceAuditLink -Record $record `
            -AuditValidation $AuditValidation -Governance $Governance
        $auditEntriesByEvidence.Add($id, $entry)
        $blockersByEvidence.Add(
            $id,
            @(Get-P2EvidenceRecordBlockers -Record $record -AuditEntry $entry)
        )
        $claimMechanisms = [Collections.Generic.HashSet[long]]::new()
        foreach ($claimValue in @($record.Manifest.behavior_claims)) {
            $claim = [PSCustomObject]$claimValue
            $mechanismId = [long]$claim.mechanism_id
            Assert-P2EvidenceCondition ($mechanisms.ContainsKey($mechanismId)) `
                "P2E_CLAIM_MECHANISM_UNKNOWN" (
                    "Evidence $id claims unknown mechanism $mechanismId."
                )
            $mechanism = [PSCustomObject]$mechanisms[$mechanismId]
            Assert-P2EvidenceCondition (
                Test-P2EvidenceIdArrayContains $mechanism.evidence_ids $id
            ) "P2E_CLAIM_BACKREF" (
                "Evidence $id claims mechanism $mechanismId without a spec back-reference."
            )
            $branchId = [long]$claim.branch_id
            if ($branchId -ne 0) {
                $branchFound = $false
                foreach ($targetValue in @($mechanism.coverage_targets)) {
                    if ([long]$targetValue.branch_id -eq $branchId) {
                        $branchFound = $true
                        break
                    }
                }
                Assert-P2EvidenceCondition $branchFound `
                    "P2E_CLAIM_BRANCH_UNKNOWN" (
                        "Evidence $id claims unknown branch $mechanismId`:$branchId."
                    )
            }
            $null = Resolve-P2EvidenceJsonPointer -Mechanism $mechanism `
                -Pointer ([string]$claim.spec_field_pointer) -EvidenceId $id
            $null = $claimMechanisms.Add($mechanismId)
        }
        $mechanismIdsByEvidence.Add(
            $id,
            @(Get-P2EvidenceSortedLongArray @($claimMechanisms))
        )
    }

    [long[]]$mechanismIds = @($mechanisms.Keys)
    [Array]::Sort($mechanismIds)
    $mechanismOutput = [Collections.Generic.List[object]]::new()
    $evidenceLinkCount = 0L
    foreach ($mechanismId in $mechanismIds) {
        $mechanism = [PSCustomObject]$mechanisms[$mechanismId]
        [long[]]$required = @(Get-P2EvidenceSortedLongArray $mechanism.evidence_ids)
        $joined = [Collections.Generic.List[long]]::new()
        $mechanismBlockers = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal
        )
        foreach ($evidenceId in $required) {
            Assert-P2EvidenceCondition ($evidenceById.ContainsKey($evidenceId)) `
                "P2E_SPEC_EVIDENCE_UNKNOWN" (
                    "Mechanism $mechanismId references unknown evidence $evidenceId."
                )
            $record = [PSCustomObject]$evidenceById[$evidenceId]
            Assert-P2EvidenceCondition (
                [string]$record.Validation.Status -ceq "ACTIVE"
            ) "P2E_SPEC_EVIDENCE_TOMBSTONED" (
                "Mechanism $mechanismId references tombstoned evidence $evidenceId."
            )
            Assert-P2EvidenceCondition (
                Test-P2EvidenceIdArrayContains `
                    $mechanismIdsByEvidence[$evidenceId] $mechanismId
            ) "P2E_SPEC_EVIDENCE_CLAIM" (
                "Mechanism $mechanismId evidence $evidenceId has no matching claim."
            )
            $joined.Add($evidenceId)
            $evidenceLinkCount++
            foreach ($blocker in @($blockersByEvidence[$evidenceId])) {
                $null = $mechanismBlockers.Add([string]$blocker)
            }
        }
        [string[]]$sortedMechanismBlockers = @(
            Get-P2EvidenceSortedStringArray @($mechanismBlockers)
        )
        $mechanismOutput.Add([pscustomobject][ordered]@{
            mechanism_id = $mechanismId
            required_evidence_ids = $required
            joined_evidence_ids = $joined.ToArray()
            evidence_current = ($sortedMechanismBlockers.Count -eq 0)
            blocker_codes = $sortedMechanismBlockers
        })
    }

    [long[]]$evidenceIds = @($evidenceById.Keys)
    [Array]::Sort($evidenceIds)
    $evidenceOutput = [Collections.Generic.List[object]]::new()
    $activeCount = 0L
    $tombstoneCount = 0L
    $currentCount = 0L
    $blockedCount = 0L
    foreach ($evidenceId in $evidenceIds) {
        $record = [PSCustomObject]$evidenceById[$evidenceId]
        [string[]]$blockers = @($blockersByEvidence[$evidenceId])
        $isCurrent = $blockers.Count -eq 0
        if ([string]$record.Validation.Status -ceq "ACTIVE") {
            $activeCount++
        }
        else {
            $tombstoneCount++
        }
        if ($isCurrent) { $currentCount++ } else { $blockedCount++ }
        $evidenceOutput.Add([pscustomobject][ordered]@{
            evidence_id = $evidenceId
            evidence_version = [long]$record.Validation.Version
            status = [string]$record.Validation.Status
            canonical_authoring_sha256 = [string]$record.Validation.Sha256
            source_audit_id = [string]$record.Validation.AuditId
            evidence_current = $isCurrent
            blocker_codes = $blockers
            mechanism_ids = [long[]]$mechanismIdsByEvidence[$evidenceId]
        })
    }

    $manifest = [pscustomobject][ordered]@{
        artifact_kind = "COMPILED_SOURCE_EVIDENCE_JOIN_MANIFEST"
        schema_version = $script:P2EvidenceJoinManifestSchemaVersion
        join_contract_version = $script:P2EvidenceJoinContractVersion
        source_spec_compiler_contract_version = `
            [long]$Compilation.CompilerContractVersion
        scope_id = [string]$Governance.Seal.scope_id
        spec_manifest_sha256 = [string]$Compilation.SpecManifestHash
        spec_input_set_sha256 = [string]$Compilation.SpecSet.InputSetHash
        source_audit_seal_sha256 = [string]$Governance.SealHash
        source_audit_manifest_sha256 = `
            [string]$Governance.Seal.source_audit_manifest_sha256
        evidence_input_set_sha256 = [string]$EvidenceSet.InputSetHash
        counts = [pscustomobject][ordered]@{
            evidence_record_count = [long]$records.Count
            active_evidence_count = $activeCount
            tombstone_evidence_count = $tombstoneCount
            current_evidence_count = $currentCount
            blocked_evidence_count = $blockedCount
            mechanism_count = [long]$mechanismIds.Count
            evidence_link_count = $evidenceLinkCount
        }
        evidence_records = $evidenceOutput.ToArray()
        mechanism_evidence = $mechanismOutput.ToArray()
    }
    $manifestJson = ConvertTo-BattleCanonicalJson $manifest
    return [pscustomobject][ordered]@{
        Compilation = $Compilation
        EvidenceSet = $EvidenceSet
        Governance = $Governance
        Manifest = $manifest
        ManifestJson = $manifestJson
        ManifestBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes(
            $manifestJson
        )
        ManifestHash = Get-BattleSha256Text $manifestJson
        EvidenceRecordCount = [long]$records.Count
        CurrentEvidenceCount = $currentCount
        MechanismCount = [long]$mechanismIds.Count
    }
}

function Invoke-P2SourceEvidenceJoin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet("Repository", "Worktree", "Staged")]
        [string]$Mode = "Repository",
        [string]$SourceAuditManifestPath = ""
    )

    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $view = New-P2RepositoryView -ProjectRoot $root -Mode $Mode `
        -CandidatePrefixes @(
            "new-game-project/battle/specs",
            $script:P2EvidenceSealRelativePath,
            $script:P2EvidencePolicyRelativePath,
            $script:P2EvidenceBaselineRelativePath
        )
    $specSet = Read-P2ValidatedSpecSet -View $view
    $compilation = Invoke-P2ValidatedSpecCompilerCore -SpecSet $specSet
    $evidenceSet = Read-P2ValidatedEvidenceSet -View $view
    $governance = Read-P2EvidenceGovernance -View $view
    $auditValidation = $null
    if (@($evidenceSet.Records).Count -gt 0) {
        $auditBytes = Read-P2EvidenceAuditBytes -ProjectRoot $root `
            -AuditManifestPath $SourceAuditManifestPath
        $auditHash = Get-P2EvidenceSha256Bytes $auditBytes
        Assert-P2EvidenceCondition (
            $auditHash -ceq
            [string]$governance.Seal.source_audit_manifest_sha256
        ) "P2E_AUDIT_HASH" (
            "The local source audit manifest does not match the tracked seal."
        )
        $auditManifest = ConvertFrom-P2EvidenceSealedAuditBytes `
            -Bytes $auditBytes -Context $script:P2EvidenceAuditRelativePath
        $auditValidation = Test-P2EvidenceAuditManifest `
            -Manifest $auditManifest -Governance $governance `
            -SealedBytesVerified
    }
    return Invoke-P2ValidatedSourceEvidenceJoinCore `
        -Compilation $compilation -EvidenceSet $evidenceSet `
        -Governance $governance -AuditValidation $auditValidation
}

function Compile-P2SourceEvidenceJoin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet("Repository", "Worktree", "Staged")]
        [string]$Mode = "Repository",
        [string]$SourceAuditManifestPath = ""
    )

    return Invoke-P2SourceEvidenceJoin -ProjectRoot $ProjectRoot -Mode $Mode `
        -SourceAuditManifestPath $SourceAuditManifestPath
}
