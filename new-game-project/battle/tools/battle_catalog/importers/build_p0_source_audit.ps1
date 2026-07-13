[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$AnalysisRoot = "",
    [string]$SourceRoot = "",
    [string]$BaselinePath = "",
    [string]$PolicyPath = "",
    [string]$OutputPath = "",
    [string]$SealOutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battleRoot = Join-Path $ProjectRoot "new-game-project\battle"
$validatorRoot = Join-Path $battleRoot "tools\battle_catalog\validators"
. (Join-Path $validatorRoot "strict_json_support.ps1")
. (Join-Path $validatorRoot "canonical_json_support.ps1")

if ([string]::IsNullOrWhiteSpace($AnalysisRoot)) {
    $AnalysisRoot = if (-not [string]::IsNullOrWhiteSpace($env:BATTLE_ARCHITECTURE_ROOT)) {
        $env:BATTLE_ARCHITECTURE_ROOT
    }
    else {
        "D:\PokemonSV-Battle-Architecture"
    }
}
$AnalysisRoot = [IO.Path]::GetFullPath($AnalysisRoot).TrimEnd('\')
$generatedRoot = Join-Path $AnalysisRoot "generated"
$analysisToolsRoot = Join-Path $AnalysisRoot "tools"
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $summaryPath = Join-Path $generatedRoot "summary.json"
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        throw "SourceRoot was not supplied and the architecture summary is missing."
    }
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $SourceRoot = [string]$summary.SourceRoot
}
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')

if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $battleRoot "manifests\source_audit\source_index_baseline.json"
}
if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path $battleRoot "manifests\source_audit\source_audit_policy.json"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $battleRoot "generated\p0\source_audit_disposition_manifest.json"
}
if ([string]::IsNullOrWhiteSpace($SealOutputPath)) {
    $SealOutputPath = Join-Path $battleRoot "generated\p0\source_audit_seal.json"
}

$shaPattern = '^[0-9a-f]{64}$'
$scopeDispositions = @(
    "IMPLEMENT", "MERGED_INTO_OTHER_MECHANISM", "DEFERRED_N0", "TEXT_ONLY",
    "OUT_OF_SCOPE_PRESENTATION", "REJECTED_UNVERIFIED", "NOT_APPLICABLE"
)
$nonScenarioPaths = @(
    "programs/msvc/battle/battle_unit_test/HowToBuild_battle_unit_test.txt",
    "programs/msvc/battle/battle_unit_test/README.txt"
)

function Get-LowerFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file was not found: $Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-ExactProperties {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Object,
        [Parameter(Mandatory = $true)][string[]]$Required,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $actual = @($Object.PSObject.Properties.Name)
    $missing = @($Required | Where-Object { $_ -notin $actual })
    $unknown = @($actual | Where-Object { $_ -notin $Required })
    if ($missing.Count -gt 0 -or $unknown.Count -gt 0) {
        throw "$Context property mismatch. Missing=[$($missing -join ', ')] Unknown=[$($unknown -join ', ')]."
    }
}

function Get-OrdinalSortedStrings {
    param([string[]]$Values)

    $result = @($Values)
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return ,$result
}

function Get-ContainedFilePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($RelativePath -match '(^|[\\/])\.\.([\\/]|$)' -or
        $RelativePath -match '^[A-Za-z]:[\\/]' -or
        $RelativePath.StartsWith('/') -or $RelativePath.StartsWith('\')) {
        throw "$Context contains an unsafe path: $RelativePath"
    }
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath(
        (Join-Path $fullRoot $RelativePath.Replace('/', '\'))
    )
    if (-not $fullPath.StartsWith(
        $fullRoot + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "$Context escapes its root: $RelativePath"
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "$Context file is missing: $RelativePath"
    }
    return $fullPath
}

function Invoke-GitScalar {
    param([string]$RepositoryRoot, [string[]]$Arguments)

    $output = @(& git -C $RepositoryRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Git failed in ${RepositoryRoot}: git $($Arguments -join ' ')`n$($output -join "`n")"
    }
    if ($output.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$output[0])) {
        throw "Git returned an unexpected scalar result in $RepositoryRoot."
    }
    return ([string]$output[0]).Trim()
}

function Get-GitStatusLines {
    param([string]$RepositoryRoot)

    $raw = @(& git -c core.quotepath=false -C $RepositoryRoot status `
        --porcelain=v1 --untracked-files=all 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read Git status in $RepositoryRoot."
    }
    $lines = @()
    foreach ($lineValue in $raw) {
        $line = [string]$lineValue
        if ([string]::IsNullOrEmpty($line)) {
            continue
        }
        if ($line.Length -lt 4 -or $line[2] -ne ' ') {
            throw "Unsupported Git porcelain status record: $line"
        }
        $status = $line.Substring(0, 2)
        $path = $line.Substring(3).Replace('\', '/')
        if ($path.Contains(" -> ")) {
            throw "Renamed source paths require an explicit baseline refresh: $path"
        }
        $lines += "$status`t$path"
    }
    return Get-OrdinalSortedStrings -Values $lines
}

function Get-ReasonText {
    param([string]$ReasonCode)

    $reasons = @{
        PROJECT_OR_BUILD_METADATA = "Project/build metadata is indexed but is not battle behavior."
        NETWORK_ONLY_DEFERRED = "Network-only behavior is deferred to N0."
        TEXT_COMMAND_MAPPING_REQUIRED = "The source command requires an explicit state/text/optional presentation mapping."
        PRESENTATION_ASSET_OUT_OF_SCOPE = "Model, animation, audio, or camera presentation is outside the text-only runtime."
        DIRTY_OR_BINARY_SOURCE_UNVERIFIED = "Dirty experimental or binary source cannot establish release behavior."
        NON_NETWORK_BEHAVIOR_OR_SCHEMA_EVIDENCE = "The entry remains in scope as behavior or schema evidence."
        SOURCE_ENTRY_IMPLEMENT = "The non-network source entry remains in the implementation audit."
        SOURCE_ENTRY_NETWORK_DEFERRED = "The source entry is network-only and deferred to N0."
        SOURCE_ENTRY_TEXT_COMMAND = "The source command must map to a local state operation, text command, optional visual, or explicit no-op."
        SOURCE_ENTRY_PRESENTATION_ONLY = "The source entry is presentation-only; text fallback policy remains required where observable."
        SOURCE_ENTRY_UNVERIFIED_EXTENSION = "Auction, Kodaigame, or another unverified extension is blocked pending evidence review."
        NON_SCENARIO_TEXT_DOCUMENT = "The indexed text file is documentation, not an executable scripted battle scenario."
    }
    if (-not $reasons.ContainsKey($ReasonCode)) {
        throw "Unknown source audit reason code: $ReasonCode"
    }
    return [string]$reasons[$ReasonCode]
}

function Get-EntryClassification {
    param(
        [string]$Category,
        [string]$SourcePath,
        [string]$Symbol
    )

    if ($SourcePath -in $nonScenarioPaths) {
        return [PSCustomObject]@{
            RuleId = "ENTRY_NON_SCENARIO_TEXT_DOCUMENT"
            Disposition = "NOT_APPLICABLE"
            ReasonCode = "NON_SCENARIO_TEXT_DOCUMENT"
        }
    }
    $combined = "$SourcePath $Symbol"
    if ($combined -match '(?i)(auction|kodaigame)') {
        return [PSCustomObject]@{
            RuleId = "ENTRY_UNVERIFIED_EXTENSION"
            Disposition = "REJECTED_UNVERIFIED"
            ReasonCode = "SOURCE_ENTRY_UNVERIFIED_EXTENSION"
        }
    }
    if ($combined -match '(?i)(host[_ ]?migration|remote[_ ]?peer|\back\b|retransmit|reconnect|spectator)') {
        return [PSCustomObject]@{
            RuleId = "ENTRY_NETWORK_DEFERRED"
            Disposition = "DEFERRED_N0"
            ReasonCode = "SOURCE_ENTRY_NETWORK_DEFERRED"
        }
    }
    if ($combined -match '(?i)(camera|sound|audio|voice|bgm|animation|model)') {
        return [PSCustomObject]@{
            RuleId = "ENTRY_PRESENTATION_ONLY"
            Disposition = "OUT_OF_SCOPE_PRESENTATION"
            ReasonCode = "SOURCE_ENTRY_PRESENTATION_ONLY"
        }
    }
    if ($Category -eq "COMMAND") {
        return [PSCustomObject]@{
            RuleId = "ENTRY_TEXT_COMMAND"
            Disposition = "TEXT_ONLY"
            ReasonCode = "SOURCE_ENTRY_TEXT_COMMAND"
        }
    }
    return [PSCustomObject]@{
        RuleId = "ENTRY_IMPLEMENT"
        Disposition = "IMPLEMENT"
        ReasonCode = "SOURCE_ENTRY_IMPLEMENT"
    }
}

function New-AuditEntry {
    param(
        [string]$Repository,
        [string]$SourcePath,
        [string]$SourceSha256,
        [string]$Symbol,
        [string]$Category,
        [string]$DomainPackage,
        [string]$GitState,
        [PSCustomObject]$Classification
    )

    if ($SourceSha256 -cnotmatch $shaPattern) {
        throw "Source entry has an invalid SHA-256: ${Repository}:$SourcePath"
    }
    $identity = "$Repository`t$Category`t$SourcePath`t$Symbol"
    $auditId = "AUDIT_" + (Get-BattleSha256Text -Text $identity).Substring(0, 16).ToUpperInvariant()
    $ambiguities = [Collections.Generic.List[string]]::new()
    $isDirty = -not [string]::IsNullOrWhiteSpace($GitState)
    if ($isDirty) {
        $ambiguities.Add("SOURCE_WORKTREE_DIRTY")
    }
    if ($Classification.RuleId -eq "ENTRY_UNVERIFIED_EXTENSION" -or
        $Classification.ReasonCode -eq "DIRTY_OR_BINARY_SOURCE_UNVERIFIED") {
        $ambiguities.Add("UNVERIFIED_EXPERIMENTAL_OR_BINARY_SOURCE")
    }
    if ($Classification.RuleId -eq "ENTRY_NON_SCENARIO_TEXT_DOCUMENT") {
        $ambiguities.Add("INDEXED_TXT_IS_DOCUMENTATION_NOT_SCENARIO")
    }
    $releaseStatus = if ($Classification.Disposition -eq "REJECTED_UNVERIFIED") {
        "REJECTED_UNVERIFIED"
    }
    elseif ($isDirty) {
        "BLOCKED_SOURCE"
    }
    else {
        "NOT_STARTED"
    }
    $testDisposition = if ($Category -notin @("TEST", "SCRIPT_SCENARIO")) {
        "NOT_APPLICABLE"
    }
    elseif ($Classification.Disposition -eq "NOT_APPLICABLE") {
        "NOT_APPLICABLE"
    }
    else {
        "PORT_BEHAVIOR"
    }

    return [PSCustomObject]@{
        audit_id = $auditId
        source_repository = $Repository
        source_path = $SourcePath
        source_sha256 = $SourceSha256
        source_symbol_or_edge = $Symbol
        source_category = $Category
        domain_package = $DomainPackage
        mechanism_ids = @()
        branch_ids = @()
        target_godot_types = @()
        fixture_ids = @()
        scope_disposition = [string]$Classification.Disposition
        evidence_status = $(if ($isDirty) { "DIRTY_UNVERIFIED" } else { "CLEAN_INDEXED" })
        release_status = $releaseStatus
        test_evidence_disposition = $testDisposition
        classification_rule_id = [string]$Classification.RuleId
        reason_code = [string]$Classification.ReasonCode
        reason = Get-ReasonText -ReasonCode ([string]$Classification.ReasonCode)
        known_ambiguities = $ambiguities.ToArray()
        review_status = "GENERATED_SCOPE_CLASSIFICATION"
    }
}

function Get-CountObject {
    param([object[]]$Values, [string]$PropertyName)

    $counts = @{}
    foreach ($value in @($Values)) {
        $key = [string]$value.$PropertyName
        if (-not $counts.ContainsKey($key)) {
            $counts[$key] = 0
        }
        $counts[$key] = [int]$counts[$key] + 1
    }
    return [PSCustomObject]$counts
}

$baseline = Read-BattleStrictJsonFile -Path $BaselinePath -Label "Source index baseline"
$policy = Read-BattleStrictJsonFile -Path $PolicyPath -Label "Source audit policy"
Assert-ExactProperties -Object $baseline -Required @(
    "schema_version", "manifest_kind", "baseline_id", "repositories",
    "index_files", "scanner_files", "expected_counts", "known_ambiguities"
) -Context "Source index baseline"
Assert-ExactProperties -Object $policy -Required @(
    "schema_version", "manifest_kind", "policy_id", "module_rules"
) -Context "Source audit policy"
if ([int]$baseline.schema_version -ne 1 -or
    $baseline.manifest_kind -ne "SOURCE_INDEX_BASELINE" -or
    [int]$policy.schema_version -ne 1 -or
    $policy.manifest_kind -ne "SOURCE_AUDIT_POLICY") {
    throw "P0 source audit baseline or policy has an unsupported schema."
}

$indexRows = @{}
foreach ($indexFile in @($baseline.index_files)) {
    Assert-ExactProperties -Object $indexFile -Required @(
        "relative_path", "record_count", "sha256"
    ) -Context "Source index file"
    $path = Get-ContainedFilePath -Root $generatedRoot `
        -RelativePath ([string]$indexFile.relative_path) -Context "Source index"
    if ((Get-LowerFileSha256 $path) -cne [string]$indexFile.sha256) {
        throw "Source index hash changed: $($indexFile.relative_path)"
    }
    $rows = @(Import-Csv -LiteralPath $path -Encoding UTF8)
    if ($rows.Count -ne [int]$indexFile.record_count) {
        throw "Source index count changed: $($indexFile.relative_path)"
    }
    $indexRows[[string]$indexFile.relative_path] = $rows
}
foreach ($scannerFile in @($baseline.scanner_files)) {
    Assert-ExactProperties -Object $scannerFile -Required @("relative_path", "sha256") `
        -Context "Source scanner file"
    $path = Get-ContainedFilePath -Root $analysisToolsRoot `
        -RelativePath ([string]$scannerFile.relative_path) -Context "Source scanner"
    if ((Get-LowerFileSha256 $path) -cne [string]$scannerFile.sha256) {
        throw "Source scanner hash changed: $($scannerFile.relative_path)"
    }
}

$sourceRows = @($indexRows["source-files.csv"])
$sourceLookup = [Collections.Generic.Dictionary[string, object]]::new(
    [StringComparer]::Ordinal
)
$moduleFiles = [Collections.Generic.Dictionary[string, object]]::new(
    [StringComparer]::Ordinal
)
foreach ($row in $sourceRows) {
    $key = "$($row.Repository)$([char]0)$($row.Path)"
    if ($sourceLookup.ContainsKey($key)) {
        throw "Duplicate source index path: $($row.Repository):$($row.Path)"
    }
    if ([string]$row.Sha256 -cnotmatch $shaPattern) {
        throw "Source index row has an invalid SHA-256: $($row.Repository):$($row.Path)"
    }
    $sourceLookup.Add($key, $row)
    $moduleKey = "$($row.Repository):$($row.Module)"
    if (-not $moduleFiles.ContainsKey($moduleKey)) {
        $moduleFiles.Add($moduleKey, [Collections.Generic.List[object]]::new())
    }
    ([Collections.Generic.List[object]]$moduleFiles[$moduleKey]).Add($row)
}

function Get-IndexedSourceRow {
    param([string]$Repository, [string]$Path)

    $key = "$Repository$([char]0)$Path"
    if (-not $sourceLookup.ContainsKey($key)) {
        throw "Derived source index row cannot resolve its source file: ${Repository}:$Path"
    }
    return $sourceLookup[$key]
}

$worktreeRows = @($indexRows["worktree-changes.csv"])
$repositoryBaselines = [Collections.Generic.List[object]]::new()
foreach ($repository in @($baseline.repositories)) {
    Assert-ExactProperties -Object $repository -Required @(
        "repository", "branch", "commit", "head_tree", "file_count",
        "source_aggregate_sha256", "dirty_path_count", "dirty_paths_sha256"
    ) -Context "Source repository baseline"
    $repositoryName = [string]$repository.repository
    if ($repositoryName -notin @("battlelogic", "pokelib")) {
        throw "Unknown source repository: $repositoryName"
    }
    $repositoryRoot = Join-Path $SourceRoot $repositoryName
    if (-not (Test-Path -LiteralPath $repositoryRoot -PathType Container)) {
        throw "Source repository is missing: $repositoryName"
    }
    $branch = Invoke-GitScalar -RepositoryRoot $repositoryRoot -Arguments @(
        "branch", "--show-current"
    )
    $commit = Invoke-GitScalar -RepositoryRoot $repositoryRoot -Arguments @(
        "rev-parse", "HEAD"
    )
    $headTree = Invoke-GitScalar -RepositoryRoot $repositoryRoot -Arguments @(
        "rev-parse", "HEAD^{tree}"
    )
    if ($branch -cne [string]$repository.branch -or
        $commit -cne [string]$repository.commit -or
        $headTree -cne [string]$repository.head_tree) {
        throw "Source repository revision changed: $repositoryName"
    }

    $repositoryRows = @($sourceRows | Where-Object Repository -eq $repositoryName)
    if ($repositoryRows.Count -ne [int]$repository.file_count) {
        throw "Source repository file count changed: $repositoryName"
    }
    $aggregateLines = [Collections.Generic.List[string]]::new()
    foreach ($row in $repositoryRows) {
        $sourcePath = Get-ContainedFilePath -Root $repositoryRoot `
            -RelativePath ([string]$row.Path) -Context "Source payload"
        $actualHash = Get-LowerFileSha256 $sourcePath
        if ($actualHash -cne [string]$row.Sha256) {
            throw "Source payload changed since indexing: ${repositoryName}:$($row.Path)"
        }
        $aggregateLines.Add("$($row.Path)`t$actualHash")
    }
    $sortedAggregateLines = Get-OrdinalSortedStrings -Values $aggregateLines.ToArray()
    $aggregateHash = Get-BattleSha256Text -Text (
        ($sortedAggregateLines -join "`n") + "`n"
    )
    if ($aggregateHash -cne [string]$repository.source_aggregate_sha256) {
        throw "Source aggregate hash changed: $repositoryName"
    }

    $indexedStatusLines = @(
        $worktreeRows |
            Where-Object Repository -eq $repositoryName |
            ForEach-Object { "$($_.Status)`t$($_.Path)" }
    )
    $indexedStatusLines = Get-OrdinalSortedStrings -Values $indexedStatusLines
    $actualStatusLines = Get-GitStatusLines -RepositoryRoot $repositoryRoot
    if (($actualStatusLines -join "`n") -cne ($indexedStatusLines -join "`n")) {
        throw "Source dirty paths changed since indexing: $repositoryName"
    }
    $dirtyHash = Get-BattleSha256Text -Text (
        ($indexedStatusLines -join "`n") + $(if ($indexedStatusLines.Count -gt 0) { "`n" } else { "" })
    )
    if ($indexedStatusLines.Count -ne [int]$repository.dirty_path_count -or
        $dirtyHash -cne [string]$repository.dirty_paths_sha256) {
        throw "Source dirty-path baseline changed: $repositoryName"
    }
    $repositoryBaselines.Add([PSCustomObject]@{
        repository = $repositoryName
        branch = $branch
        commit = $commit
        head_tree = $headTree
        source_aggregate_sha256 = $aggregateHash
        dirty_paths_sha256 = $dirtyHash
        dirty_path_count = $indexedStatusLines.Count
    })
}

$moduleRows = @($indexRows["modules.csv"])
$actualModuleKeys = Get-OrdinalSortedStrings -Values @(
    $moduleRows | ForEach-Object { "$($_.Repository):$($_.Module)" }
)
$modulePolicy = [Collections.Generic.Dictionary[string, object]]::new(
    [StringComparer]::Ordinal
)
foreach ($rule in @($policy.module_rules)) {
    Assert-ExactProperties -Object $rule -Required @(
        "rule_id", "members", "scope_disposition", "reason_code"
    ) -Context "Source audit module rule"
    if ([string]$rule.scope_disposition -notin $scopeDispositions) {
        throw "Module rule has an unknown scope disposition: $($rule.rule_id)"
    }
    Get-ReasonText -ReasonCode ([string]$rule.reason_code) | Out-Null
    foreach ($member in @($rule.members)) {
        $key = [string]$member
        if ($key -notin $actualModuleKeys) {
            throw "Module policy references an unknown module: $key"
        }
        if ($modulePolicy.ContainsKey($key)) {
            throw "Module policy classifies a module more than once: $key"
        }
        $modulePolicy.Add($key, $rule)
    }
}
$unclassifiedModules = @($actualModuleKeys | Where-Object {
    -not $modulePolicy.ContainsKey($_)
})
if ($unclassifiedModules.Count -gt 0 -or
    $modulePolicy.Count -ne $actualModuleKeys.Count) {
    throw "Module policy is not exhaustive. Unclassified=[$($unclassifiedModules -join ', ')]."
}

$entryMap = [Collections.Generic.SortedDictionary[string, object]]::new(
    [StringComparer]::Ordinal
)
$auditIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
function Add-AuditEntry {
    param([PSCustomObject]$Entry)

    $key = "$($Entry.source_category)`t$($Entry.source_repository)`t$($Entry.source_path)`t$($Entry.source_symbol_or_edge)"
    if ($entryMap.ContainsKey($key)) {
        throw "Duplicate source audit identity: $key"
    }
    if (-not $auditIds.Add([string]$Entry.audit_id)) {
        throw "Source audit ID collision: $($Entry.audit_id)"
    }
    $entryMap.Add($key, $Entry)
}

foreach ($moduleRow in $moduleRows) {
    $moduleKey = "$($moduleRow.Repository):$($moduleRow.Module)"
    $rule = $modulePolicy[$moduleKey]
    $files = @($moduleFiles[$moduleKey])
    $aggregateLines = Get-OrdinalSortedStrings -Values @(
        $files | ForEach-Object { "$($_.Path)`t$($_.Sha256)" }
    )
    $moduleHash = Get-BattleSha256Text -Text (
        ($aggregateLines -join "`n") + "`n"
    )
    $gitState = if (@($files | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.GitState)
    }).Count -gt 0) { "DIRTY" } else { "" }
    $classification = [PSCustomObject]@{
        RuleId = [string]$rule.rule_id
        Disposition = [string]$rule.scope_disposition
        ReasonCode = [string]$rule.reason_code
    }
    Add-AuditEntry (New-AuditEntry -Repository ([string]$moduleRow.Repository) `
        -SourcePath ([string]$moduleRow.Module) -SourceSha256 $moduleHash `
        -Symbol "module:$($moduleRow.Module)" -Category "MODULE" `
        -DomainPackage ([string]$moduleRow.Module) -GitState $gitState `
        -Classification $classification)
}

foreach ($row in @($indexRows["sections.csv"])) {
    $path = if (-not [string]::IsNullOrWhiteSpace([string]$row.SourcePath)) {
        [string]$row.SourcePath
    }
    else {
        [string]$row.HeaderPath
    }
    $source = Get-IndexedSourceRow -Repository "battlelogic" -Path $path
    $classification = Get-EntryClassification -Category "SECTION" `
        -SourcePath $path -Symbol ([string]$row.Name)
    Add-AuditEntry (New-AuditEntry -Repository "battlelogic" -SourcePath $path `
        -SourceSha256 ([string]$source.Sha256) -Symbol ([string]$row.Name) `
        -Category "SECTION" -DomainPackage "section" `
        -GitState ([string]$source.GitState) -Classification $classification)
}

foreach ($row in @($indexRows["event-handler-symbols.csv"])) {
    $path = [string]$row.SourcePath
    $source = Get-IndexedSourceRow -Repository "battlelogic" -Path $path
    $symbol = "$($row.Family):$($row.Kind):$($row.Symbol):line$($row.Line)"
    $classification = Get-EntryClassification -Category "EVENT_HANDLER" `
        -SourcePath $path -Symbol $symbol
    Add-AuditEntry (New-AuditEntry -Repository "battlelogic" -SourcePath $path `
        -SourceSha256 ([string]$source.Sha256) -Symbol $symbol `
        -Category "EVENT_HANDLER" -DomainPackage ([string]$row.Family) `
        -GitState ([string]$source.GitState) -Classification $classification)
}

$enumCategoryMap = @{
    Action = "ACTION"
    BattleMode = "BATTLE_MODE"
    CommandStream = "COMMAND"
    Event = "EVENT"
    Interrupt = "INTERRUPT"
    Protocol = "PROTOCOL"
}
foreach ($row in @($indexRows["protocol-and-domain-enums.csv"])) {
    if (-not $enumCategoryMap.ContainsKey([string]$row.Group)) {
        throw "Unknown protocol/domain enum group: $($row.Group)"
    }
    $category = [string]$enumCategoryMap[[string]$row.Group]
    $path = [string]$row.SourcePath
    $source = Get-IndexedSourceRow -Repository ([string]$row.Repository) -Path $path
    $symbol = "$($row.Group):$($row.Enum):$($row.Name):line$($row.Line)"
    $classification = Get-EntryClassification -Category $category `
        -SourcePath $path -Symbol $symbol
    Add-AuditEntry (New-AuditEntry -Repository ([string]$row.Repository) `
        -SourcePath $path -SourceSha256 ([string]$source.Sha256) `
        -Symbol $symbol -Category $category -DomainPackage ([string]$row.Group) `
        -GitState ([string]$source.GitState) -Classification $classification)
}

foreach ($row in @($indexRows["schema-declarations.csv"])) {
    $path = [string]$row.Path
    $source = Get-IndexedSourceRow -Repository ([string]$row.Repository) -Path $path
    $symbol = "$($row.Kind):$($row.Name):line$($row.Line)"
    $classification = Get-EntryClassification -Category "SCHEMA" `
        -SourcePath $path -Symbol $symbol
    Add-AuditEntry (New-AuditEntry -Repository ([string]$row.Repository) `
        -SourcePath $path -SourceSha256 ([string]$source.Sha256) `
        -Symbol $symbol -Category "SCHEMA" -DomainPackage ([string]$row.Kind) `
        -GitState ([string]$source.GitState) -Classification $classification)
}

$testRows = @($indexRows["tests.csv"])
foreach ($row in $testRows) {
    $path = [string]$row.Path
    $source = Get-IndexedSourceRow -Repository ([string]$row.Repository) -Path $path
    $classification = Get-EntryClassification -Category "TEST" `
        -SourcePath $path -Symbol "test:$path"
    Add-AuditEntry (New-AuditEntry -Repository ([string]$row.Repository) `
        -SourcePath $path -SourceSha256 ([string]$source.Sha256) `
        -Symbol "test:$path" -Category "TEST" `
        -DomainPackage ([string]$row.Module) -GitState ([string]$source.GitState) `
        -Classification $classification)
}

$scenarioRows = @($testRows | Where-Object {
    $_.Repository -eq "battlelogic" -and $_.Extension -eq ".txt" -and
    $_.Path.StartsWith(
        "programs/msvc/battle/battle_unit_test/",
        [StringComparison]::Ordinal
    )
})
foreach ($row in $scenarioRows) {
    $path = [string]$row.Path
    $source = Get-IndexedSourceRow -Repository "battlelogic" -Path $path
    $classification = Get-EntryClassification -Category "SCRIPT_SCENARIO" `
        -SourcePath $path -Symbol "scenario:$path"
    Add-AuditEntry (New-AuditEntry -Repository "battlelogic" -SourcePath $path `
        -SourceSha256 ([string]$source.Sha256) -Symbol "scenario:$path" `
        -Category "SCRIPT_SCENARIO" -DomainPackage "battle_unit_test_script" `
        -GitState ([string]$source.GitState) -Classification $classification)
}

foreach ($row in @($indexRows["logic-edges.csv"])) {
    $path = [string]$row.SourcePath
    $source = Get-IndexedSourceRow -Repository ([string]$row.Repository) -Path $path
    $symbol = "$($row.Caller):$($row.EdgeType):$($row.Target):line$($row.Line)"
    $classification = Get-EntryClassification -Category "LOGIC_EDGE" `
        -SourcePath $path -Symbol $symbol
    Add-AuditEntry (New-AuditEntry -Repository ([string]$row.Repository) `
        -SourcePath $path -SourceSha256 ([string]$source.Sha256) `
        -Symbol $symbol -Category "LOGIC_EDGE" `
        -DomainPackage ([string]$row.SourceModule) `
        -GitState ([string]$source.GitState) -Classification $classification)
}

$entries = @($entryMap.Values)
$actualCounts = @{
    modules = $moduleRows.Count
    sections = @($indexRows["sections.csv"]).Count
    event_handlers = @($indexRows["event-handler-symbols.csv"]).Count
    events = @($indexRows["protocol-and-domain-enums.csv"] | Where-Object Group -eq "Event").Count
    commands = @($indexRows["protocol-and-domain-enums.csv"] | Where-Object Group -eq "CommandStream").Count
    actions = @($indexRows["protocol-and-domain-enums.csv"] | Where-Object Group -eq "Action").Count
    interrupts = @($indexRows["protocol-and-domain-enums.csv"] | Where-Object Group -eq "Interrupt").Count
    protocol_entries = @($indexRows["protocol-and-domain-enums.csv"] | Where-Object Group -eq "Protocol").Count
    battle_modes = @($indexRows["protocol-and-domain-enums.csv"] | Where-Object Group -eq "BattleMode").Count
    schema_declarations = @($indexRows["schema-declarations.csv"]).Count
    tests = $testRows.Count
    script_scenario_candidates = $scenarioRows.Count
    executable_script_scenarios = @($scenarioRows | Where-Object {
        $_.Path -notin $nonScenarioPaths
    }).Count
    non_scenario_text_documents = @($scenarioRows | Where-Object {
        $_.Path -in $nonScenarioPaths
    }).Count
    logic_edges = @($indexRows["logic-edges.csv"]).Count
    audit_entries = $entries.Count
}
foreach ($property in $baseline.expected_counts.PSObject.Properties) {
    if (-not $actualCounts.ContainsKey($property.Name) -or
        [int]$actualCounts[$property.Name] -ne [int]$property.Value) {
        throw "Source audit count mismatch for '$($property.Name)'. Expected=$($property.Value) Actual=$($actualCounts[$property.Name])."
    }
}

$sourceIndexBaselineHash = Get-LowerFileSha256 $BaselinePath
$policyHash = Get-LowerFileSha256 $PolicyPath
$auditManifest = [PSCustomObject]@{
    schema_version = 1
    manifest_kind = "SOURCE_AUDIT_DISPOSITION"
    manifest_mode = "BASELINE"
    scope_id = "MAIZANG_GEN9_SINGLE_PLAYER_TEXT_V1"
    baseline = [PSCustomObject]@{
        source_index_manifest_sha256 = $sourceIndexBaselineHash
        repositories = $repositoryBaselines.ToArray()
        expected_counts = [PSCustomObject]$actualCounts
    }
    entries = $entries
}
$auditHash = Write-BattleCanonicalJsonFile -Path $OutputPath -Value $auditManifest
$seal = [PSCustomObject]@{
    schema_version = 1
    manifest_kind = "SOURCE_AUDIT_SEAL"
    seal_id = "SV_SOURCE_AUDIT_P0_V1"
    scope_id = "MAIZANG_GEN9_SINGLE_PLAYER_TEXT_V1"
    baseline_id = [string]$baseline.baseline_id
    source_index_baseline_sha256 = $sourceIndexBaselineHash
    source_audit_policy_sha256 = $policyHash
    source_audit_manifest_sha256 = $auditHash
    source_payloads_verified = $true
    unclassified_modules = 0
    counts = [PSCustomObject]$actualCounts
    category_counts = Get-CountObject -Values $entries -PropertyName "source_category"
    scope_disposition_counts = Get-CountObject -Values $entries -PropertyName "scope_disposition"
    evidence_status_counts = Get-CountObject -Values $entries -PropertyName "evidence_status"
    release_status_counts = Get-CountObject -Values $entries -PropertyName "release_status"
}
$sealHash = Write-BattleCanonicalJsonFile -Path $SealOutputPath -Value $seal

Write-Host "P0 source audit generated."
Write-Host "  Entries:        $($entries.Count)"
Write-Host "  Modules:        $($moduleRows.Count) (unclassified: 0)"
Write-Host "  Scenarios:      $($actualCounts.executable_script_scenarios) executable + $($actualCounts.non_scenario_text_documents) documentation"
Write-Host "  Audit SHA-256:  $auditHash"
Write-Host "  Seal SHA-256:   $sealHash"
Write-Host "  Audit output:   $([IO.Path]::GetFullPath($OutputPath))"
Write-Host "  Seal output:    $([IO.Path]::GetFullPath($SealOutputPath))"
Write-Host "P0_SOURCE_AUDIT_OK"
