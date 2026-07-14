Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "p2_repository_view_support.ps1")
. (Join-Path $PSScriptRoot "p2_spec_contract_support.ps1")

$script:P2SpecSetStableRelativePath = (
    "new-game-project/battle/specs/id_manifests/battle_stable_ids.json"
)
$script:P2SpecSetPresentationRelativePath = (
    "new-game-project/battle/specs/presentation/presentation_contracts.json"
)
$script:P2SpecSetArtifactDefinitions = @(
    [pscustomobject][ordered]@{
        Name = "mechanism_specs"
        ResultProperty = "MechanismSpecs"
        Directory = "new-game-project/battle/specs/mechanisms"
        Pattern = '^new-game-project/battle/specs/mechanisms/(?<id>[0-9]{10})\.mechanism_spec\.json$'
        Domain = "MECHANISM"
        Validator = "Test-P2MechanismSpec"
    },
    [pscustomobject][ordered]@{
        Name = "event_schemas"
        ResultProperty = "EventSchemas"
        Directory = "new-game-project/battle/specs/events"
        Pattern = '^new-game-project/battle/specs/events/(?<id>[0-9]{10})\.event_schema\.json$'
        Domain = "EVENT"
        Validator = "Test-P2EventSchema"
    },
    [pscustomobject][ordered]@{
        Name = "handler_bindings"
        ResultProperty = "HandlerBindings"
        Directory = "new-game-project/battle/specs/handlers"
        Pattern = '^new-game-project/battle/specs/handlers/(?<id>[0-9]{10})\.handler_binding\.json$'
        Domain = "HANDLER"
        Validator = "Test-P2HandlerBinding"
    },
    [pscustomobject][ordered]@{
        Name = "resolver_specs"
        ResultProperty = "ResolverSpecs"
        Directory = "new-game-project/battle/specs/resolvers"
        Pattern = '^new-game-project/battle/specs/resolvers/(?<id>[0-9]{10})\.resolver_spec\.json$'
        Domain = "RESOLVER"
        Validator = "Test-P2ResolverSpec"
    },
    [pscustomobject][ordered]@{
        Name = "test_entries"
        ResultProperty = "TestEntries"
        Directory = "new-game-project/battle/specs/tests"
        Pattern = '^new-game-project/battle/specs/tests/(?<id>[0-9]{10})\.test_manifest_entry\.json$'
        Domain = "TEST"
        Validator = "Test-P2TestManifestEntry"
    }
)

function ConvertFrom-P2SpecSetBytes {
    param(
        [AllowNull()][object]$Bytes,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($null -eq $Bytes -or $Bytes -isnot [byte[]]) {
        throw "P2_SPEC_SET_BYTES: $Context was not read as bytes."
    }
    $byteArray = [byte[]]$Bytes
    if ($byteArray.Length -gt 524288) {
        throw "P2_SPEC_SET_TOO_LARGE: $Context exceeds the 524288-byte limit."
    }
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($byteArray)
    }
    catch {
        throw "P2_SPEC_SET_UTF8: $Context is not valid strict UTF-8."
    }
    return ConvertFrom-BattleStrictJson -Text $text -Label $Context
}

function Get-P2SpecSetRegistryDomain {
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
    throw "P2_SPEC_SET_REGISTRY_DOMAIN: Missing stable-ID domain '$DomainName'."
}

function Assert-P2SpecSetPrimaryIdentity {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Registry,
        [Parameter(Mandatory = $true)][string]$DomainName,
        [Parameter(Mandatory = $true)][long]$Identifier,
        [Parameter(Mandatory = $true)][string]$DebugKey,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $domain = Get-P2SpecSetRegistryDomain -Registry $Registry `
        -DomainName $DomainName
    foreach ($entryValue in @($domain.entries)) {
        $entry = [PSCustomObject]$entryValue
        if ([long]$entry.scope_id -eq 0 -and [long]$entry.id -eq $Identifier) {
            Assert-P2Condition ([string]$entry.status -ceq "ACTIVE") `
                "P2_SPEC_SET_PRIMARY_INACTIVE" `
                "$RelativePath primary $DomainName ID $Identifier is not ACTIVE."
            Assert-P2Condition ([string]$entry.debug_key -ceq $DebugKey) `
                "P2_SPEC_SET_PRIMARY_DEBUG_KEY" `
                "$RelativePath debug_key does not match the stable registry."
            return
        }
    }
    throw (
        "P2_SPEC_SET_PRIMARY_UNKNOWN: $RelativePath primary $DomainName ID " +
        "$Identifier is not registered."
    )
}

function Read-P2SpecSetCandidateJson {
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $bytes = Get-P2RepositoryViewBytes -View $View -RelativePath $RelativePath
    return ConvertFrom-P2SpecSetBytes -Bytes $bytes -Context $RelativePath
}

function Read-P2SpecSetBaselineJson {
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $bytes = Get-P2RepositoryViewBaselineBytes -View $View `
        -RelativePath $RelativePath -AllowMissing
    if ($null -eq $bytes) {
        return $null
    }
    return ConvertFrom-P2SpecSetBytes -Bytes $bytes `
        -Context "HEAD:$RelativePath"
}

function Read-P2ValidatedSpecSet {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$View)

    Assert-P2RepositoryViewObject $View
    $stableManifest = Read-P2SpecSetCandidateJson -View $View `
        -RelativePath $script:P2SpecSetStableRelativePath
    $presentationManifest = Read-P2SpecSetCandidateJson -View $View `
        -RelativePath $script:P2SpecSetPresentationRelativePath
    $stableValidation = Test-P2StableIdManifest -Manifest $stableManifest
    $presentationValidation = Test-P2PresentationContracts `
        -Manifest $presentationManifest

    if ([string]$View.Mode -cne "Repository") {
        $baselineStable = Read-P2SpecSetBaselineJson -View $View `
            -RelativePath $script:P2SpecSetStableRelativePath
        $baselinePresentation = Read-P2SpecSetBaselineJson -View $View `
            -RelativePath $script:P2SpecSetPresentationRelativePath
        $hasStableBaseline = $null -ne $baselineStable
        $hasPresentationBaseline = $null -ne $baselinePresentation
        Assert-P2Condition ($hasStableBaseline -eq $hasPresentationBaseline) `
            "P2_SPEC_SET_BASELINE_PAIR" `
            "Stable-ID and presentation baselines must both exist or both be absent."
        if ($hasStableBaseline) {
            $null = Test-P2StableIdEvolution -Baseline $baselineStable `
                -Candidate $stableManifest
            $null = Test-P2PresentationEvolution `
                -Baseline $baselinePresentation -Candidate $presentationManifest
        }
        else {
            Assert-P2Condition (
                [long]$stableManifest.generation -eq 1 -and
                [long]$presentationManifest.generation -eq 1
            ) "P2_SPEC_SET_INITIAL_GENERATION" `
                "A new stable-ID/presentation pair must start at generation 1."
        }
    }

    $stableRegistry = [PSCustomObject]$stableManifest
    $counts = [ordered]@{}
    $inputSets = [ordered]@{}
    $recordSets = [ordered]@{}
    foreach ($definition in $script:P2SpecSetArtifactDefinitions) {
        $paths = @(Get-P2RepositoryViewPaths -View $View `
            -Prefix ([string]$definition.Directory))
        if ($paths.Count -gt 65535) {
            throw (
                "P2_SPEC_SET_COUNT: $($definition.Name) exceeds the " +
                "65535-file limit."
            )
        }
        $records = [Collections.Generic.List[object]]::new()
        $inputRecords = [Collections.Generic.List[object]]::new()
        $seenIds = [Collections.Generic.HashSet[long]]::new()
        foreach ($relativePathValue in $paths) {
            $relativePath = [string]$relativePathValue
            if ($relativePath -cnotmatch [string]$definition.Pattern) {
                throw (
                    "P2_SPEC_SET_FILENAME: '$relativePath' does not match " +
                    "the anchored $($definition.Name) filename contract."
                )
            }
            $fileIdentifier = [long]::Parse(
                $Matches.id,
                [Globalization.CultureInfo]::InvariantCulture
            )
            $manifest = Read-P2SpecSetCandidateJson -View $View `
                -RelativePath $relativePath
            $validation = & ([string]$definition.Validator) $manifest
            Assert-P2Condition (
                $fileIdentifier -eq [long]$validation.PrimaryId
            ) "P2_SPEC_SET_FILENAME_ID" `
                "$relativePath filename ID does not match its primary ID."
            Assert-P2Condition (
                $seenIds.Add([long]$validation.PrimaryId)
            ) "P2_SPEC_SET_PRIMARY_DUPLICATE" `
                "$($definition.Name) repeats primary ID $($validation.PrimaryId)."
            Assert-P2SpecSetPrimaryIdentity -Registry $stableRegistry `
                -DomainName ([string]$definition.Domain) `
                -Identifier ([long]$validation.PrimaryId) `
                -DebugKey ([string]$validation.DebugKey) `
                -RelativePath $relativePath
            $records.Add([pscustomobject][ordered]@{
                RelativePath = $relativePath
                Manifest = $manifest
                Validation = $validation
            })
            $inputRecords.Add([pscustomobject][ordered]@{
                relative_path = $relativePath
                canonical_sha256 = [string]$validation.Sha256
            })
        }
        $counts[$definition.Name] = $paths.Count
        $inputSets[$definition.Name] = $inputRecords.ToArray()
        $recordSets[$definition.ResultProperty] = $records.ToArray()
    }

    $inputSet = [pscustomobject][ordered]@{
        schema_version = 1
        mechanism_specs = $inputSets.mechanism_specs
        event_schemas = $inputSets.event_schemas
        handler_bindings = $inputSets.handler_bindings
        resolver_specs = $inputSets.resolver_specs
        test_entries = $inputSets.test_entries
    }
    $inputSetJson = ConvertTo-BattleCanonicalJson -Value $inputSet
    $inputSetHash = Get-BattleSha256Text -Text $inputSetJson
    return [pscustomobject][ordered]@{
        StableManifest = $stableManifest
        StableManifestHash = [string]$stableValidation.Sha256
        PresentationManifest = $presentationManifest
        PresentationManifestHash = [string]$presentationValidation.Sha256
        MechanismSpecs = $recordSets.MechanismSpecs
        EventSchemas = $recordSets.EventSchemas
        HandlerBindings = $recordSets.HandlerBindings
        ResolverSpecs = $recordSets.ResolverSpecs
        TestEntries = $recordSets.TestEntries
        InputSet = $inputSet
        InputSetHash = $inputSetHash
        Counts = [pscustomobject]$counts
    }
}
