[CmdletBinding()]
param(
    [string]$ProjectRoot = "",

    [ValidateSet("Repository", "Worktree", "Staged")]
    [string]$Mode = "Repository"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "p2_spec_contract_support.ps1")

$stableRelativePath = (
    "new-game-project/battle/specs/id_manifests/battle_stable_ids.json"
)
$presentationRelativePath = (
    "new-game-project/battle/specs/presentation/presentation_contracts.json"
)
$artifactDefinitions = @(
    [pscustomobject]@{
        Name = "mechanism_specs"
        Directory = "new-game-project/battle/specs/mechanisms"
        Pattern = '^new-game-project/battle/specs/mechanisms/(?<id>[0-9]{10})\.mechanism_spec\.json$'
        Domain = "MECHANISM"
        Validator = "Test-P2MechanismSpec"
    },
    [pscustomobject]@{
        Name = "event_schemas"
        Directory = "new-game-project/battle/specs/events"
        Pattern = '^new-game-project/battle/specs/events/(?<id>[0-9]{10})\.event_schema\.json$'
        Domain = "EVENT"
        Validator = "Test-P2EventSchema"
    },
    [pscustomobject]@{
        Name = "handler_bindings"
        Directory = "new-game-project/battle/specs/handlers"
        Pattern = '^new-game-project/battle/specs/handlers/(?<id>[0-9]{10})\.handler_binding\.json$'
        Domain = "HANDLER"
        Validator = "Test-P2HandlerBinding"
    },
    [pscustomobject]@{
        Name = "resolver_specs"
        Directory = "new-game-project/battle/specs/resolvers"
        Pattern = '^new-game-project/battle/specs/resolvers/(?<id>[0-9]{10})\.resolver_spec\.json$'
        Domain = "RESOLVER"
        Validator = "Test-P2ResolverSpec"
    },
    [pscustomobject]@{
        Name = "test_entries"
        Directory = "new-game-project/battle/specs/tests"
        Pattern = '^new-game-project/battle/specs/tests/(?<id>[0-9]{10})\.test_manifest_entry\.json$'
        Domain = "TEST"
        Validator = "Test-P2TestManifestEntry"
    }
)

function ConvertFrom-P2SpecBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Bytes.Length -gt 524288) {
        throw "P2_SPEC_TOO_LARGE: $Label exceeds the 524288-byte limit."
    }
    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    try {
        $text = $strictUtf8.GetString($Bytes)
    }
    catch {
        throw "P2_SPEC_UTF8: $Label is not valid strict UTF-8."
    }
    return ConvertFrom-BattleStrictJson -Text $text -Label $Label
}

function Invoke-P2SpecGitBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Arguments
    )

    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        throw "P2_SPEC_GIT_NOT_FOUND: Git is required."
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $gitCommand.Source
    $escapedRoot = $Root.Replace('"', '\"')
    $startInfo.Arguments = '-C "{0}" {1}' -f $escapedRoot, $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $memory = [IO.MemoryStream]::new()
    try {
        if (-not $process.Start()) {
            throw "P2_SPEC_GIT_START: Git could not be started."
        }
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Bytes = $memory.ToArray()
            ErrorText = $errorTask.Result.Trim()
        }
    }
    finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

function Assert-P2SpecGitRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $result = Invoke-P2SpecGitBytes $Root "rev-parse --show-toplevel"
    if ($result.ExitCode -ne 0) {
        throw "P2_SPEC_GIT_ROOT: ProjectRoot is not a readable Git worktree."
    }
    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    try {
        $reported = $strictUtf8.GetString([byte[]]$result.Bytes).Trim()
    }
    catch {
        throw "P2_SPEC_GIT_ROOT_UTF8: Git returned a non-UTF-8 root."
    }
    $reported = [IO.Path]::GetFullPath($reported).TrimEnd('\')
    $requested = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if (-not $reported.Equals($requested, [StringComparison]::OrdinalIgnoreCase)) {
        throw (
            "P2_SPEC_GIT_ROOT_MISMATCH: Git top-level '$reported' does not " +
            "equal ProjectRoot '$requested'."
        )
    }
}

function Get-P2SpecGitBlob {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ObjectSpec
    )

    $escaped = $ObjectSpec.Replace('"', '\"')
    $result = Invoke-P2SpecGitBytes $Root (
        'cat-file blob "{0}"' -f $escaped
    )
    if ($result.ExitCode -ne 0) {
        throw (
            "P2_SPEC_GIT_BLOB: Git object '$ObjectSpec' could not be read" +
            $(if ($result.ErrorText.Length -gt 0) {
                ": $($result.ErrorText)"
            } else {
                "."
            })
        )
    }
    return ,([byte[]]$result.Bytes)
}

function Assert-P2SpecContainedPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $resolved = [IO.Path]::GetFullPath($FullPath)
    if (-not $resolved.StartsWith(
        $Root + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "P2_SPEC_PATH_ESCAPE: '$resolved' is outside ProjectRoot."
    }
    $current = $resolved
    while ($current.StartsWith(
        $Root + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "P2_SPEC_REPARSE_PATH: '$current' is a reparse point."
            }
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            break
        }
        $current = $parent
    }
    return $resolved
}

function Get-P2SpecWorktreePaths {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Directory
    )

    $fullDirectory = Assert-P2SpecContainedPath $Root (
        Join-Path $Root $Directory.Replace('/', '\')
    )
    if (-not (Test-Path -LiteralPath $fullDirectory -PathType Container)) {
        return @()
    }
    $paths = [Collections.Generic.List[string]]::new()
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($fullDirectory)
    while ($pending.Count -gt 0) {
        $currentDirectory = $pending.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $currentDirectory -Force) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "P2_SPEC_REPARSE_PATH: '$($item.FullName)' is a reparse point."
            }
            if ($item.PSIsContainer) {
                $pending.Push([IO.Path]::GetFullPath($item.FullName))
                continue
            }
            $fullPath = [IO.Path]::GetFullPath($item.FullName)
            $paths.Add($fullPath.Substring($Root.Length + 1).Replace('\', '/'))
        }
    }
    $result = $paths.ToArray()
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result
}

function Get-P2SpecStagedPaths {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Directory
    )

    $result = Invoke-P2SpecGitBytes $Root (
        'ls-files -z -- "{0}"' -f $Directory
    )
    if ($result.ExitCode -ne 0) {
        throw "P2_SPEC_GIT_ENUMERATE: Could not enumerate staged '$Directory'."
    }
    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    try {
        $text = $strictUtf8.GetString([byte[]]$result.Bytes)
    }
    catch {
        throw "P2_SPEC_GIT_PATH_UTF8: Staged paths are not valid UTF-8."
    }
    $paths = @($text.Split([char]0) | Where-Object { $_.Length -gt 0 })
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    return $paths
}

function Read-P2SpecCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$ReadMode
    )

    if ($ReadMode -ceq "Staged") {
        $bytes = Get-P2SpecGitBlob $Root (":" + $RelativePath)
    }
    else {
        $fullPath = Assert-P2SpecContainedPath $Root (Join-Path $Root (
            $RelativePath.Replace('/', '\')
        ))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "P2_SPEC_NOT_FOUND: '$RelativePath' was not found."
        }
        $bytes = [IO.File]::ReadAllBytes($fullPath)
    }
    return ConvertFrom-P2SpecBytes $bytes $RelativePath
}

function Get-P2SpecRegistryDomain {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Registry,
        [Parameter(Mandatory = $true)][string]$DomainName
    )

    foreach ($domainValue in @($Registry.domains)) {
        $domain = [PSCustomObject]$domainValue
        if ([string]$domain.domain -ceq $DomainName) {
            return $domain
        }
    }
    throw "P2_SPEC_REGISTRY_DOMAIN: Missing stable-ID domain '$DomainName'."
}

function Assert-P2SpecPrimaryIdentity {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Registry,
        [Parameter(Mandatory = $true)][string]$DomainName,
        [Parameter(Mandatory = $true)][long]$Identifier,
        [Parameter(Mandatory = $true)][string]$DebugKey,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $domain = Get-P2SpecRegistryDomain $Registry $DomainName
    foreach ($entryValue in @($domain.entries)) {
        $entry = [PSCustomObject]$entryValue
        if ([long]$entry.scope_id -eq 0 -and [long]$entry.id -eq $Identifier) {
            Assert-P2Condition ([string]$entry.status -ceq "ACTIVE") `
                "P2_SPEC_PRIMARY_INACTIVE" `
                "$RelativePath primary $DomainName ID $Identifier is not ACTIVE."
            Assert-P2Condition ([string]$entry.debug_key -ceq $DebugKey) `
                "P2_SPEC_PRIMARY_DEBUG_KEY" `
                "$RelativePath debug_key does not match the stable registry."
            return
        }
    }
    throw (
        "P2_SPEC_PRIMARY_UNKNOWN: $RelativePath primary $DomainName ID " +
        "$Identifier is not registered."
    )
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
Assert-P2SpecGitRoot $ProjectRoot

if ($Mode -ceq "Staged") {
    $idContractValidator = Join-Path $PSScriptRoot `
        "validate_p2_id_manifests.ps1"
    if (-not (Test-Path -LiteralPath $idContractValidator -PathType Leaf)) {
        throw (
            "P2_SPEC_REVIEW_GATE_MISSING: The staged ID/review-surface " +
            "validator was not found."
        )
    }
    $null = & $idContractValidator -ProjectRoot $ProjectRoot -Mode Staged
}

$stableManifest = Read-P2SpecCandidate $ProjectRoot $stableRelativePath $Mode
$presentationManifest = Read-P2SpecCandidate `
    $ProjectRoot $presentationRelativePath $Mode
$null = Test-P2StableIdManifest $stableManifest
$null = Test-P2PresentationContracts $presentationManifest
$stableRegistry = [PSCustomObject]$stableManifest

$counts = [ordered]@{}
$inputSets = [ordered]@{}
foreach ($definition in $artifactDefinitions) {
    if ($Mode -ceq "Staged") {
        $paths = @(Get-P2SpecStagedPaths $ProjectRoot $definition.Directory)
    }
    else {
        $paths = @(Get-P2SpecWorktreePaths $ProjectRoot $definition.Directory)
    }
    if ($paths.Count -gt 65535) {
        throw "P2_SPEC_SET_TOO_LARGE: $($definition.Name) exceeds 65535 files."
    }
    $records = [Collections.Generic.List[object]]::new()
    $seenIds = [Collections.Generic.HashSet[long]]::new()
    foreach ($relativePath in $paths) {
        if ([string]$relativePath -cnotmatch $definition.Pattern) {
            throw (
                "P2_SPEC_FILENAME: '$relativePath' does not match the anchored " +
                "$($definition.Name) filename contract."
            )
        }
        $fileIdentifier = [long]::Parse(
            $Matches.id,
            [Globalization.CultureInfo]::InvariantCulture
        )
        $manifest = Read-P2SpecCandidate $ProjectRoot $relativePath $Mode
        $validation = & $definition.Validator $manifest
        Assert-P2Condition ($fileIdentifier -eq [long]$validation.PrimaryId) `
            "P2_SPEC_FILENAME_ID" `
            "$relativePath filename ID does not match its primary ID."
        Assert-P2Condition ($seenIds.Add([long]$validation.PrimaryId)) `
            "P2_SPEC_PRIMARY_DUPLICATE" `
            "$($definition.Name) repeats primary ID $($validation.PrimaryId)."
        Assert-P2SpecPrimaryIdentity $stableRegistry $definition.Domain `
            ([long]$validation.PrimaryId) ([string]$validation.DebugKey) $relativePath
        if ($definition.Name -ceq "mechanism_specs") {
            $facts = [pscustomobject][ordered]@{
                identity_registered = $true
                discovery_basis_verified = $true
                specification_valid = $true
                cross_references_valid = $false
                implementation_bindings_verified = $false
                dependency_gate_passed = $false
                required_test_count = 0
                executed_test_count = 0
                passed_test_count = 0
                required_oracles = @()
                passed_oracles = @()
                coverage_observed = $false
                evidence_current = $false
                release_catalog_versioned = $false
                release_migration_complete = $false
                release_change_log_complete = $false
                release_coverage_gate_passed = $false
            }
            $maturity = Get-P2MaturityComputation `
                ([long]$validation.PrimaryId) `
                ([string]$validation.TargetMaturity) $facts
            $null = Assert-P2MaturityTarget $maturity
        }
        $records.Add([pscustomobject][ordered]@{
            relative_path = [string]$relativePath
            canonical_sha256 = [string]$validation.Sha256
        })
    }
    $counts[$definition.Name] = $paths.Count
    $inputSets[$definition.Name] = $records.ToArray()
}

$inputSet = [pscustomobject][ordered]@{
    schema_version = 1
    mechanism_specs = $inputSets.mechanism_specs
    event_schemas = $inputSets.event_schemas
    handler_bindings = $inputSets.handler_bindings
    resolver_specs = $inputSets.resolver_specs
    test_entries = $inputSets.test_entries
}
$inputSetJson = ConvertTo-BattleCanonicalJson $inputSet
$inputSetHash = Get-BattleSha256Text $inputSetJson

Write-Output (
    (
        "P2_SPEC_CONTRACTS_OK mechanism_specs={0} event_schemas={1} " +
        "handler_bindings={2} resolver_specs={3} test_entries={4} " +
        "input_set_sha256={5}"
    ) -f `
        $counts.mechanism_specs, $counts.event_schemas,
        $counts.handler_bindings, $counts.resolver_specs,
        $counts.test_entries, $inputSetHash
)
