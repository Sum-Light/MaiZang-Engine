Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "..\..\battle_catalog\validators\strict_json_support.ps1")
. (Join-Path $PSScriptRoot "..\..\battle_catalog\validators\canonical_json_support.ps1")

$script:P2MaxId = 2147483647L
$script:P2StableDomainDefinitions = @(
    [pscustomobject]@{ Domain = "MECHANISM"; Prefix = "MECH"; Scope = "GLOBAL" },
    [pscustomobject]@{ Domain = "BRANCH"; Prefix = "BRANCH"; Scope = "MECHANISM" },
    [pscustomobject]@{ Domain = "EVENT"; Prefix = "EVENT"; Scope = "GLOBAL" },
    [pscustomobject]@{ Domain = "HANDLER"; Prefix = "HANDLER"; Scope = "GLOBAL" },
    [pscustomobject]@{ Domain = "RESOLVER"; Prefix = "RESOLVER"; Scope = "GLOBAL" },
    [pscustomobject]@{ Domain = "PHASE"; Prefix = "PHASE"; Scope = "RESOLVER" },
    [pscustomobject]@{ Domain = "RNG_DRAW"; Prefix = "RNG_DRAW"; Scope = "MECHANISM" },
    [pscustomobject]@{ Domain = "RNG_STREAM"; Prefix = "RNG_STREAM"; Scope = "GLOBAL" },
    [pscustomobject]@{ Domain = "RNG_TAG"; Prefix = "RNG_TAG"; Scope = "GLOBAL" },
    [pscustomobject]@{ Domain = "STATE_OP"; Prefix = "STATE_OP"; Scope = "GLOBAL" },
    [pscustomobject]@{ Domain = "COMMAND"; Prefix = "COMMAND"; Scope = "GLOBAL" },
    [pscustomobject]@{ Domain = "ACTION"; Prefix = "ACTION"; Scope = "GLOBAL" },
    [pscustomobject]@{ Domain = "INTERRUPT"; Prefix = "INTERRUPT"; Scope = "GLOBAL" },
    [pscustomobject]@{ Domain = "FEATURE"; Prefix = "FEATURE"; Scope = "GLOBAL" },
    [pscustomobject]@{ Domain = "TEST"; Prefix = "TEST"; Scope = "GLOBAL" }
)
$script:P2PresentationTags = @(
    "PRES_VISUAL",
    "PRES_AUDIO",
    "PRES_CAMERA",
    "PRES_UI",
    "PRES_TEXT",
    "PRES_TIMING",
    "PRES_NONE"
)

function Assert-P2Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "$Code`: $Message"
    }
}

function Assert-P2Object {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-P2Condition ($null -ne $Value -and $Value -is [PSCustomObject]) `
        "P2_JSON_OBJECT_REQUIRED" "$Context must be a JSON object."
}

function Assert-P2Array {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [int]$Minimum = 0,
        [int]$Maximum = [int]::MaxValue
    )

    Assert-P2Condition ($null -ne $Value -and $Value -is [Array]) `
        "P2_JSON_ARRAY_REQUIRED" "$Context must be a JSON array."
    $count = @($Value).Count
    Assert-P2Condition ($count -ge $Minimum -and $count -le $Maximum) `
        "P2_JSON_ARRAY_SIZE" `
        "$Context contains $count items; expected $Minimum..$Maximum."
}

function Assert-P2ExactProperties {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Value,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $actual = @($Value.PSObject.Properties.Name)
    $actualNames = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($name in $actual) {
        $null = $actualNames.Add([string]$name)
    }
    $missing = @($Expected | Where-Object { -not $actualNames.Contains($_) })
    $expectedNames = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($name in $Expected) {
        $null = $expectedNames.Add($name)
    }
    $unknown = @($actual | Where-Object { -not $expectedNames.Contains($_) })
    Assert-P2Condition (
        $actual.Count -eq $Expected.Count -and
        $missing.Count -eq 0 -and
        $unknown.Count -eq 0
    ) "P2_JSON_PROPERTIES" (
        "$Context must contain exactly [$($Expected -join ', ')]; " +
        "missing [$($missing -join ', ')], unknown [$($unknown -join ', ')]."
    )
}

function Test-P2IntegralType {
    param([AllowNull()][object]$Value)

    return (
        $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
    )
}

function Get-P2Integer {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [long]$Minimum = [long]::MinValue,
        [long]$Maximum = [long]::MaxValue
    )

    Assert-P2Condition (Test-P2IntegralType $Value) `
        "P2_JSON_INTEGER_REQUIRED" "$Context must be an integer."
    try {
        $integer = [Convert]::ToInt64($Value)
    }
    catch {
        throw "P2_JSON_INTEGER_RANGE: $Context is outside the signed 64-bit range."
    }
    Assert-P2Condition ($integer -ge $Minimum -and $integer -le $Maximum) `
        "P2_JSON_INTEGER_RANGE" `
        "$Context value $integer is outside $Minimum..$Maximum."
    return $integer
}

function Get-P2String {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$MaximumLength = [int]::MaxValue
    )

    Assert-P2Condition ($null -ne $Value -and $Value -is [string]) `
        "P2_JSON_STRING_REQUIRED" "$Context must be a string."
    $text = [string]$Value
    Assert-P2Condition (
        $text.Length -le $MaximumLength -and $text -cmatch $Pattern
    ) "P2_JSON_STRING_FORMAT" "$Context has an invalid value '$text'."
    return $text
}

function Get-P2Enum {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string[]]$Allowed
    )

    Assert-P2Condition ($null -ne $Value -and $Value -is [string]) `
        "P2_JSON_ENUM_REQUIRED" "$Context must be a string enum."
    $text = [string]$Value
    $allowedValues = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($item in $Allowed) {
        $null = $allowedValues.Add($item)
    }
    Assert-P2Condition ($allowedValues.Contains($text)) `
        "P2_JSON_ENUM" `
        "$Context value '$text' is not one of [$($Allowed -join ', ')]."
    return $text
}

function Get-P2Boolean {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-P2Condition ($null -ne $Value -and $Value -is [bool]) `
        "P2_JSON_BOOLEAN_REQUIRED" "$Context must be a boolean."
    return [bool]$Value
}

function Get-P2Aliases {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-P2Array -Value $Value -Context $Context -Maximum 64
    $aliases = @($Value)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($aliasValue in $aliases) {
        $alias = Get-P2String -Value $aliasValue -Context "$Context item" `
            -Pattern '^[A-Z][A-Z0-9_]*$' -MaximumLength 128
        Assert-P2Condition ($seen.Add($alias)) "P2_ALIAS_DUPLICATE" `
            "$Context contains duplicate alias '$alias'."
    }
    return $true
}

function Register-P2Names {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object]$Registry,
        [Parameter(Mandatory = $true)][string]$DebugKey,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Aliases,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-P2Condition (
        $Registry -is [Collections.Generic.HashSet[string]]
    ) "P2_NAME_REGISTRY_TYPE" "$Context name registry has an invalid type."
    $nameRegistry = [Collections.Generic.HashSet[string]]$Registry
    Assert-P2Condition ($nameRegistry.Add($DebugKey)) "P2_DEBUG_KEY_COLLISION" `
        "$Context debug key '$DebugKey' collides within its domain."
    foreach ($alias in $Aliases) {
        Assert-P2Condition ($nameRegistry.Add([string]$alias)) "P2_ALIAS_COLLISION" `
            "$Context alias '$alias' collides within its domain."
    }
}

function New-P2CanonicalResult {
    param([Parameter(Mandatory = $true)][PSCustomObject]$Manifest)

    $canonicalJson = ConvertTo-BattleCanonicalJson -Value $Manifest
    return [pscustomobject]@{
        CanonicalJson = $canonicalJson
        Sha256 = Get-BattleSha256Text -Text $canonicalJson
    }
}

function Test-P2StableIdManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Manifest)

    Assert-P2Object -Value $Manifest -Context "stable ID manifest"
    $root = [PSCustomObject]$Manifest
    Assert-P2ExactProperties -Value $root -Context "stable ID manifest" -Expected @(
        "schema_version", "manifest_kind", "generation", "invalid_id",
        "max_id", "domains"
    )
    Assert-P2Condition (
        (Get-P2Integer $root.schema_version "stable ID schema_version" 1 1) -eq 1
    ) "P2_STABLE_SCHEMA" "Stable ID schema_version must be 1."
    Assert-P2Condition (
        (Get-P2Enum $root.manifest_kind "stable ID manifest_kind" @(
            "BATTLE_STABLE_ID_REGISTRY"
        )) -ceq "BATTLE_STABLE_ID_REGISTRY"
    ) "P2_STABLE_KIND" "Stable ID manifest_kind is invalid."
    $null = Get-P2Integer $root.generation "stable ID generation" 1 $script:P2MaxId
    Assert-P2Condition (
        (Get-P2Integer $root.invalid_id "stable ID invalid_id" 0 0) -eq 0
    ) "P2_STABLE_INVALID_ID" "Stable ID invalid_id must be 0."
    Assert-P2Condition (
        (Get-P2Integer $root.max_id "stable ID max_id" `
            $script:P2MaxId $script:P2MaxId) -eq $script:P2MaxId
    ) "P2_STABLE_MAX_ID" "Stable ID max_id must be 2147483647."

    Assert-P2Array -Value $root.domains -Context "stable ID domains" `
        -Minimum $script:P2StableDomainDefinitions.Count `
        -Maximum $script:P2StableDomainDefinitions.Count
    $domains = @($root.domains)
    $domainByName = @{}
    for ($domainIndex = 0; $domainIndex -lt $domains.Count; $domainIndex++) {
        $definition = $script:P2StableDomainDefinitions[$domainIndex]
        $domainValue = $domains[$domainIndex]
        Assert-P2Object -Value $domainValue -Context "stable ID domain[$domainIndex]"
        $domain = [PSCustomObject]$domainValue
        Assert-P2ExactProperties -Value $domain `
            -Context "stable ID domain[$domainIndex]" `
            -Expected @("domain", "id_prefix", "scope_kind", "entries")
        Assert-P2Condition (
            (Get-P2Enum $domain.domain "domain[$domainIndex].domain" @(
                $definition.Domain
            )) -ceq $definition.Domain
        ) "P2_STABLE_DOMAIN_ORDER" `
            "Domain[$domainIndex] must be '$($definition.Domain)'."
        Assert-P2Condition (
            (Get-P2Enum $domain.id_prefix "domain[$domainIndex].id_prefix" @(
                $definition.Prefix
            )) -ceq $definition.Prefix
        ) "P2_STABLE_PREFIX" `
            "Domain '$($definition.Domain)' must use prefix '$($definition.Prefix)'."
        Assert-P2Condition (
            (Get-P2Enum $domain.scope_kind "domain[$domainIndex].scope_kind" @(
                $definition.Scope
            )) -ceq $definition.Scope
        ) "P2_STABLE_SCOPE_KIND" `
            "Domain '$($definition.Domain)' must use scope '$($definition.Scope)'."
        Assert-P2Array -Value $domain.entries `
            -Context "domain '$($definition.Domain)' entries" -Maximum 65535

        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $lastIdByScope = @{}
        $entries = @($domain.entries)
        for ($entryIndex = 0; $entryIndex -lt $entries.Count; $entryIndex++) {
            $entryValue = $entries[$entryIndex]
            $context = "domain '$($definition.Domain)' entry[$entryIndex]"
            Assert-P2Object -Value $entryValue -Context $context
            $entry = [PSCustomObject]$entryValue
            Assert-P2ExactProperties -Value $entry -Context $context -Expected @(
                "scope_id", "id", "debug_key", "status", "aliases"
            )
            $scopeId = Get-P2Integer $entry.scope_id "$context.scope_id" `
                0 $script:P2MaxId
            if ($definition.Scope -ceq "GLOBAL") {
                Assert-P2Condition ($scopeId -eq 0) "P2_STABLE_GLOBAL_SCOPE" `
                    "$context must use scope_id 0."
            }
            else {
                Assert-P2Condition ($scopeId -gt 0) "P2_STABLE_SCOPED_ID" `
                    "$context must use a positive scope_id."
            }
            $id = Get-P2Integer $entry.id "$context.id" 1 $script:P2MaxId
            $scopeKey = $scopeId.ToString([Globalization.CultureInfo]::InvariantCulture)
            if ($lastIdByScope.ContainsKey($scopeKey)) {
                Assert-P2Condition ($id -gt [long]$lastIdByScope[$scopeKey]) `
                    "P2_STABLE_ID_ORDER" `
                    "$context ID $id must be greater than the previous ID in scope $scopeId."
            }
            $lastIdByScope[$scopeKey] = $id
            $debugKey = Get-P2String $entry.debug_key "$context.debug_key" `
                '^[A-Z][A-Z0-9_]*$' 128
            $null = Get-P2Enum $entry.status "$context.status" @(
                "ACTIVE", "TOMBSTONE"
            )
            $null = Get-P2Aliases $entry.aliases "$context.aliases"
            $aliases = @($entry.aliases)
            Register-P2Names -Registry $names -DebugKey $debugKey `
                -Aliases $aliases -Context $context
        }
        $domainByName[$definition.Domain] = $domain
    }

    $scopedOwners = [ordered]@{
        BRANCH = "MECHANISM"
        RNG_DRAW = "MECHANISM"
        PHASE = "RESOLVER"
    }
    foreach ($scopedDomainName in $scopedOwners.Keys) {
        $ownerDomainName = [string]$scopedOwners[$scopedDomainName]
        $ownerStatuses = @{}
        foreach ($ownerValue in @($domainByName[$ownerDomainName].entries)) {
            $owner = [PSCustomObject]$ownerValue
            $ownerKey = ([long]$owner.id).ToString(
                [Globalization.CultureInfo]::InvariantCulture
            )
            $ownerStatuses[$ownerKey] = [string]$owner.status
        }
        $scopedEntries = @($domainByName[$scopedDomainName].entries)
        for ($entryIndex = 0; $entryIndex -lt $scopedEntries.Count; $entryIndex++) {
            $entry = [PSCustomObject]$scopedEntries[$entryIndex]
            $ownerKey = ([long]$entry.scope_id).ToString(
                [Globalization.CultureInfo]::InvariantCulture
            )
            $context = "domain '$scopedDomainName' entry[$entryIndex]"
            Assert-P2Condition ($ownerStatuses.ContainsKey($ownerKey)) `
                "P2_STABLE_SCOPE_OWNER_UNKNOWN" `
                "$context references unknown $ownerDomainName ID $($entry.scope_id)."
            if ([string]$entry.status -ceq "ACTIVE") {
                Assert-P2Condition (
                    [string]$ownerStatuses[$ownerKey] -ceq "ACTIVE"
                ) "P2_STABLE_SCOPE_OWNER_INACTIVE" `
                    "$context ACTIVE entry requires an ACTIVE $ownerDomainName owner."
            }
        }
    }

    return New-P2CanonicalResult -Manifest $root
}

function Test-P2PresentationContracts {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Manifest)

    Assert-P2Object -Value $Manifest -Context "presentation contract manifest"
    $root = [PSCustomObject]$Manifest
    Assert-P2ExactProperties -Value $root `
        -Context "presentation contract manifest" -Expected @(
            "schema_version", "manifest_kind", "generation", "invalid_id",
            "max_id", "tags", "payload_schemas", "cues"
        )
    Assert-P2Condition (
        (Get-P2Integer $root.schema_version "presentation schema_version" 1 1) -eq 1
    ) "P2_PRESENTATION_SCHEMA" "Presentation schema_version must be 1."
    Assert-P2Condition (
        (Get-P2Enum $root.manifest_kind "presentation manifest_kind" @(
            "PRESENTATION_CONTRACTS"
        )) -ceq "PRESENTATION_CONTRACTS"
    ) "P2_PRESENTATION_KIND" "Presentation manifest_kind is invalid."
    $null = Get-P2Integer $root.generation "presentation generation" `
        1 $script:P2MaxId
    Assert-P2Condition (
        (Get-P2Integer $root.invalid_id "presentation invalid_id" 0 0) -eq 0
    ) "P2_PRESENTATION_INVALID_ID" "Presentation invalid_id must be 0."
    Assert-P2Condition (
        (Get-P2Integer $root.max_id "presentation max_id" `
            $script:P2MaxId $script:P2MaxId) -eq $script:P2MaxId
    ) "P2_PRESENTATION_MAX_ID" "Presentation max_id must be 2147483647."

    Assert-P2Array -Value $root.tags -Context "presentation tags" `
        -Minimum $script:P2PresentationTags.Count `
        -Maximum $script:P2PresentationTags.Count
    $tags = @($root.tags)
    $tagById = @{}
    $tagNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = 0; $index -lt $tags.Count; $index++) {
        $context = "presentation tag[$index]"
        Assert-P2Object -Value $tags[$index] -Context $context
        $tag = [PSCustomObject]$tags[$index]
        Assert-P2ExactProperties -Value $tag -Context $context -Expected @(
            "presentation_tag_id", "debug_key", "status", "aliases"
        )
        $expectedId = [long]($index + 1)
        $tagId = Get-P2Integer $tag.presentation_tag_id `
            "$context.presentation_tag_id" $expectedId $expectedId
        $debugKey = Get-P2String $tag.debug_key "$context.debug_key" `
            '^PRES_[A-Z0-9_]+$' 128
        Assert-P2Condition ($debugKey -ceq $script:P2PresentationTags[$index]) `
            "P2_PRESENTATION_TAG_MAPPING" `
            "Tag ID $tagId must remain '$($script:P2PresentationTags[$index])'."
        $status = Get-P2Enum $tag.status "$context.status" @(
            "ACTIVE", "TOMBSTONE"
        )
        $null = Get-P2Aliases $tag.aliases "$context.aliases"
        $aliases = @($tag.aliases)
        Register-P2Names -Registry $tagNames -DebugKey $debugKey `
            -Aliases $aliases -Context $context
        $tagById[$tagId] = [pscustomobject]@{ Status = $status }
    }

    Assert-P2Array -Value $root.payload_schemas `
        -Context "presentation payload_schemas" -Maximum 65535
    $payloads = @($root.payload_schemas)
    $payloadById = @{}
    $payloadNames = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $lastPayloadId = 0L
    for ($index = 0; $index -lt $payloads.Count; $index++) {
        $context = "payload schema[$index]"
        Assert-P2Object -Value $payloads[$index] -Context $context
        $payload = [PSCustomObject]$payloads[$index]
        Assert-P2ExactProperties -Value $payload -Context $context -Expected @(
            "payload_schema_id", "debug_key", "status", "aliases",
            "schema_version", "fields"
        )
        $payloadId = Get-P2Integer $payload.payload_schema_id `
            "$context.payload_schema_id" 1 $script:P2MaxId
        Assert-P2Condition ($payloadId -gt $lastPayloadId) "P2_PAYLOAD_ID_ORDER" `
            "$context ID $payloadId must be strictly increasing."
        $lastPayloadId = $payloadId
        $debugKey = Get-P2String $payload.debug_key "$context.debug_key" `
            '^[A-Z][A-Z0-9_]*$' 128
        $status = Get-P2Enum $payload.status "$context.status" @(
            "ACTIVE", "TOMBSTONE"
        )
        $null = Get-P2Aliases $payload.aliases "$context.aliases"
        $aliases = @($payload.aliases)
        Register-P2Names -Registry $payloadNames -DebugKey $debugKey `
            -Aliases $aliases -Context $context
        $null = Get-P2Integer $payload.schema_version `
            "$context.schema_version" 1 $script:P2MaxId
        Assert-P2Array -Value $payload.fields -Context "$context.fields" -Maximum 64
        $fieldNames = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal
        )
        $previousFieldName = ""
        $fields = @($payload.fields)
        for ($fieldIndex = 0; $fieldIndex -lt $fields.Count; $fieldIndex++) {
            $fieldContext = "$context field[$fieldIndex]"
            Assert-P2Object -Value $fields[$fieldIndex] -Context $fieldContext
            $field = [PSCustomObject]$fields[$fieldIndex]
            Assert-P2ExactProperties -Value $field -Context $fieldContext -Expected @(
                "field_name", "value_kind", "stable_domain", "minimum",
                "maximum", "required", "cardinality", "max_items"
            )
            $fieldName = Get-P2String $field.field_name `
                "$fieldContext.field_name" '^[a-z][a-z0-9_]*$' 64
            if ($fieldIndex -gt 0) {
                Assert-P2Condition (
                    [StringComparer]::Ordinal.Compare(
                        $fieldName,
                        $previousFieldName
                    ) -gt 0
                ) "P2_PAYLOAD_FIELD_ORDER" `
                    "$context fields must be strictly ordered by field_name."
            }
            $previousFieldName = $fieldName
            Assert-P2Condition ($fieldNames.Add($fieldName)) `
                "P2_PAYLOAD_FIELD_DUPLICATE" `
                "$context repeats field name '$fieldName'."
            $valueKind = Get-P2Enum $field.value_kind `
                "$fieldContext.value_kind" @(
                    "STABLE_ID", "PUBLIC_INT", "PUBLIC_BOOL"
                )
            $stableDomain = Get-P2Enum $field.stable_domain `
                "$fieldContext.stable_domain" @(
                    "ENTITY", "EFFECT", "ITEM", "MOVE", "MESSAGE", "NONE"
                )
            $minimum = Get-P2Integer $field.minimum "$fieldContext.minimum" `
                ([long]-2147483648) $script:P2MaxId
            $maximum = Get-P2Integer $field.maximum "$fieldContext.maximum" `
                ([long]-2147483648) $script:P2MaxId
            Assert-P2Condition ($minimum -le $maximum) "P2_PAYLOAD_FIELD_RANGE" `
                "$fieldContext minimum must not exceed maximum."
            $null = Get-P2Boolean $field.required "$fieldContext.required"
            $cardinality = Get-P2Enum $field.cardinality `
                "$fieldContext.cardinality" @("ONE", "MANY")
            $maxItems = Get-P2Integer $field.max_items `
                "$fieldContext.max_items" 1 64
            switch ($valueKind) {
                "STABLE_ID" {
                    Assert-P2Condition (
                        $stableDomain -cin @("ENTITY", "EFFECT", "ITEM", "MOVE", "MESSAGE") -and
                        $minimum -eq 1 -and $maximum -eq $script:P2MaxId
                    ) "P2_PAYLOAD_STABLE_ID_FIELD" `
                        "$fieldContext STABLE_ID requires a concrete stable_domain and full ID range."
                }
                "PUBLIC_INT" {
                    Assert-P2Condition ($stableDomain -ceq "NONE") `
                        "P2_PAYLOAD_PUBLIC_INT_FIELD" `
                        "$fieldContext PUBLIC_INT must use stable_domain NONE."
                }
                "PUBLIC_BOOL" {
                    Assert-P2Condition (
                        $stableDomain -ceq "NONE" -and
                        $minimum -eq 0 -and $maximum -eq 1
                    ) "P2_PAYLOAD_PUBLIC_BOOL_FIELD" `
                        "$fieldContext PUBLIC_BOOL must use NONE and range 0..1."
                }
            }
            if ($cardinality -ceq "ONE") {
                Assert-P2Condition ($maxItems -eq 1) `
                    "P2_PAYLOAD_CARDINALITY" `
                    "$fieldContext cardinality ONE requires max_items 1."
            }
        }
        $payloadById[$payloadId] = [pscustomobject]@{ Status = $status }
    }

    Assert-P2Array -Value $root.cues -Context "presentation cues" -Maximum 65535
    $cues = @($root.cues)
    $cueNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $lastCueId = 0L
    for ($index = 0; $index -lt $cues.Count; $index++) {
        $context = "presentation cue[$index]"
        Assert-P2Object -Value $cues[$index] -Context $context
        $cue = [PSCustomObject]$cues[$index]
        Assert-P2ExactProperties -Value $cue -Context $context -Expected @(
            "presentation_cue_id", "debug_key", "status", "aliases",
            "presentation_tags", "semantic_phase", "information_class",
            "fallback_text_key", "local_barrier_policy", "payload_schema_id"
        )
        $cueId = Get-P2Integer $cue.presentation_cue_id `
            "$context.presentation_cue_id" 1 $script:P2MaxId
        Assert-P2Condition ($cueId -gt $lastCueId) "P2_CUE_ID_ORDER" `
            "$context ID $cueId must be strictly increasing."
        $lastCueId = $cueId
        $debugKey = Get-P2String $cue.debug_key "$context.debug_key" `
            '^[A-Z][A-Z0-9_]*$' 128
        $status = Get-P2Enum $cue.status "$context.status" @(
            "ACTIVE", "TOMBSTONE"
        )
        $null = Get-P2Aliases $cue.aliases "$context.aliases"
        $aliases = @($cue.aliases)
        Register-P2Names -Registry $cueNames -DebugKey $debugKey `
            -Aliases $aliases -Context $context
        Assert-P2Array -Value $cue.presentation_tags `
            -Context "$context.presentation_tags" -Minimum 1 -Maximum 7
        $presentationTags = @($cue.presentation_tags)
        $previousTag = 0L
        foreach ($tagValue in $presentationTags) {
            $tagId = Get-P2Integer $tagValue "$context presentation tag" 1 7
            Assert-P2Condition ($tagId -gt $previousTag) "P2_CUE_TAG_ORDER" `
                "$context presentation_tags must be unique and strictly increasing."
            $previousTag = $tagId
        }
        if ($presentationTags -contains 7) {
            Assert-P2Condition ($presentationTags.Count -eq 1) `
                "P2_CUE_PRES_NONE_EXCLUSIVE" `
                "$context PRES_NONE must be the only presentation tag."
        }
        $null = Get-P2Enum $cue.semantic_phase "$context.semantic_phase" @(
            "BEFORE", "ALONGSIDE", "AFTER"
        )
        $null = Get-P2Enum $cue.information_class `
            "$context.information_class" @(
                "REQUIRED_INFORMATION", "OPTIONAL_FLAVOR"
            )
        $null = Get-P2String $cue.fallback_text_key `
            "$context.fallback_text_key" '^[A-Z][A-Z0-9_.-]*$' 192
        $null = Get-P2Enum $cue.local_barrier_policy `
            "$context.local_barrier_policy" @(
                "NONE", "OPTIONAL", "REQUIRED_LOCAL_ONLY"
            )
        $payloadId = Get-P2Integer $cue.payload_schema_id `
            "$context.payload_schema_id" 1 $script:P2MaxId
        Assert-P2Condition ($payloadById.ContainsKey($payloadId)) `
            "P2_CUE_PAYLOAD_UNKNOWN" `
            "$context references unknown payload schema $payloadId."
        foreach ($tagValue in $presentationTags) {
            $tagId = [long]$tagValue
            Assert-P2Condition ($tagById.ContainsKey($tagId)) `
                "P2_CUE_TAG_UNKNOWN" "$context references unknown tag $tagId."
            if ($status -ceq "ACTIVE") {
                Assert-P2Condition (
                    $tagById[$tagId].Status -ceq "ACTIVE"
                ) "P2_CUE_TAG_INACTIVE" `
                    "$context ACTIVE cue references inactive tag $tagId."
            }
        }
        if ($status -ceq "ACTIVE") {
            Assert-P2Condition (
                $payloadById[$payloadId].Status -ceq "ACTIVE"
            ) "P2_CUE_PAYLOAD_INACTIVE" `
                "$context ACTIVE cue references inactive payload schema $payloadId."
        }
    }

    return New-P2CanonicalResult -Manifest $root
}

function Assert-P2AliasesAppendOnly {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Baseline,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Candidate,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-P2Condition ($Candidate.Count -ge $Baseline.Count) `
        "P2_EVOLUTION_ALIAS_REMOVED" "$Context aliases cannot be removed."
    for ($index = 0; $index -lt $Baseline.Count; $index++) {
        Assert-P2Condition (
            [string]$Candidate[$index] -ceq [string]$Baseline[$index]
        ) "P2_EVOLUTION_ALIAS_REORDERED" `
            "$Context aliases must retain their existing order."
    }
}

function Assert-P2EntryEvolution {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Baseline,
        [Parameter(Mandatory = $true)][PSCustomObject]$Candidate,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $baselineAliases = @($Baseline.aliases)
    $candidateAliases = @($Candidate.aliases)
    Assert-P2AliasesAppendOnly -Baseline $baselineAliases `
        -Candidate $candidateAliases -Context $Context
    if ([string]$Baseline.debug_key -cne [string]$Candidate.debug_key) {
        $candidateAliasNames = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal
        )
        foreach ($alias in $candidateAliases) {
            $null = $candidateAliasNames.Add([string]$alias)
        }
        Assert-P2Condition (
            $candidateAliasNames.Contains([string]$Baseline.debug_key)
        ) "P2_EVOLUTION_RENAME_ALIAS" `
            "$Context rename must append the previous debug key as an alias."
    }
    $baselineStatus = [string]$Baseline.status
    $candidateStatus = [string]$Candidate.status
    $statusAllowed = (
        $candidateStatus -ceq $baselineStatus -or
        ($baselineStatus -ceq "ACTIVE" -and $candidateStatus -ceq "TOMBSTONE")
    )
    Assert-P2Condition $statusAllowed "P2_EVOLUTION_STATUS" `
        "$Context may only remain unchanged or transition ACTIVE to TOMBSTONE."
}

function Assert-P2RootIdentity {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Baseline,
        [Parameter(Mandatory = $true)][PSCustomObject]$Candidate,
        [Parameter(Mandatory = $true)][string]$Context
    )

    foreach ($property in @("schema_version", "manifest_kind", "invalid_id", "max_id")) {
        $baselineValue = ConvertTo-BattleCanonicalJsonValue $Baseline.$property
        $candidateValue = ConvertTo-BattleCanonicalJsonValue $Candidate.$property
        Assert-P2Condition ($baselineValue -ceq $candidateValue) `
            "P2_EVOLUTION_ROOT_IDENTITY" `
            "$Context root property '$property' is immutable."
    }
}

function Assert-P2GenerationEvolution {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Baseline,
        [Parameter(Mandatory = $true)][PSCustomObject]$Candidate,
        [Parameter(Mandatory = $true)][string]$BaselineContent,
        [Parameter(Mandatory = $true)][string]$CandidateContent,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $baselineGeneration = [long]$Baseline.generation
    $candidateGeneration = [long]$Candidate.generation
    if ($BaselineContent -ceq $CandidateContent) {
        Assert-P2Condition ($candidateGeneration -eq $baselineGeneration) `
            "P2_EVOLUTION_GENERATION_UNCHANGED" `
            "$Context generation must remain unchanged when content is unchanged."
        return
    }
    Assert-P2Condition (
        $baselineGeneration -lt $script:P2MaxId -and
        $candidateGeneration -eq ($baselineGeneration + 1)
    ) "P2_EVOLUTION_GENERATION_INCREMENT" `
        "$Context generation must increase by exactly one when content changes."
}

function Test-P2StableIdEvolution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Baseline,
        [Parameter(Mandatory = $true)][object]$Candidate
    )

    $null = Test-P2StableIdManifest -Manifest $Baseline
    $null = Test-P2StableIdManifest -Manifest $Candidate
    $baselineRoot = [PSCustomObject]$Baseline
    $candidateRoot = [PSCustomObject]$Candidate
    Assert-P2RootIdentity -Baseline $baselineRoot -Candidate $candidateRoot `
        -Context "stable ID manifest"

    $baselineDomains = @($baselineRoot.domains)
    $candidateDomains = @($candidateRoot.domains)
    for ($domainIndex = 0; $domainIndex -lt $baselineDomains.Count; $domainIndex++) {
        $baselineDomain = [PSCustomObject]$baselineDomains[$domainIndex]
        $candidateDomain = [PSCustomObject]$candidateDomains[$domainIndex]
        foreach ($property in @("domain", "id_prefix", "scope_kind")) {
            Assert-P2Condition (
                [string]$baselineDomain.$property -ceq [string]$candidateDomain.$property
            ) "P2_EVOLUTION_DOMAIN_IDENTITY" `
                "Stable domain[$domainIndex] property '$property' is immutable."
        }
        $baselineEntries = @($baselineDomain.entries)
        $candidateEntries = @($candidateDomain.entries)
        Assert-P2Condition ($candidateEntries.Count -ge $baselineEntries.Count) `
            "P2_EVOLUTION_ENTRY_REMOVED" `
            "Stable domain '$($baselineDomain.domain)' cannot remove entries."

        $baselineMaxByScope = @{}
        foreach ($entryValue in $baselineEntries) {
            $entry = [PSCustomObject]$entryValue
            $scopeKey = ([long]$entry.scope_id).ToString(
                [Globalization.CultureInfo]::InvariantCulture
            )
            $entryId = [long]$entry.id
            if (-not $baselineMaxByScope.ContainsKey($scopeKey) -or
                $entryId -gt [long]$baselineMaxByScope[$scopeKey]) {
                $baselineMaxByScope[$scopeKey] = $entryId
            }
        }
        for ($entryIndex = 0; $entryIndex -lt $baselineEntries.Count; $entryIndex++) {
            $baselineEntry = [PSCustomObject]$baselineEntries[$entryIndex]
            $candidateEntry = [PSCustomObject]$candidateEntries[$entryIndex]
            $context = (
                "stable domain '$($baselineDomain.domain)' entry[$entryIndex]"
            )
            Assert-P2Condition (
                [long]$baselineEntry.scope_id -eq [long]$candidateEntry.scope_id -and
                [long]$baselineEntry.id -eq [long]$candidateEntry.id
            ) "P2_EVOLUTION_ENTRY_REORDERED" `
                "$context scope and ID cannot be deleted, changed, inserted, or reordered."
            Assert-P2EntryEvolution -Baseline $baselineEntry `
                -Candidate $candidateEntry -Context $context
        }
        for (
            $entryIndex = $baselineEntries.Count;
            $entryIndex -lt $candidateEntries.Count;
            $entryIndex++
        ) {
            $entry = [PSCustomObject]$candidateEntries[$entryIndex]
            $scopeKey = ([long]$entry.scope_id).ToString(
                [Globalization.CultureInfo]::InvariantCulture
            )
            $baselineMaximum = 0L
            if ($baselineMaxByScope.ContainsKey($scopeKey)) {
                $baselineMaximum = [long]$baselineMaxByScope[$scopeKey]
            }
            Assert-P2Condition ([long]$entry.id -gt $baselineMaximum) `
                "P2_EVOLUTION_NEW_ID" `
                "New stable ID $($entry.id) must exceed baseline scope maximum $baselineMaximum."
        }
    }

    $baselineContent = ConvertTo-BattleCanonicalJsonValue ([ordered]@{
        schema_version = $baselineRoot.schema_version
        manifest_kind = $baselineRoot.manifest_kind
        invalid_id = $baselineRoot.invalid_id
        max_id = $baselineRoot.max_id
        domains = $baselineRoot.domains
    })
    $candidateContent = ConvertTo-BattleCanonicalJsonValue ([ordered]@{
        schema_version = $candidateRoot.schema_version
        manifest_kind = $candidateRoot.manifest_kind
        invalid_id = $candidateRoot.invalid_id
        max_id = $candidateRoot.max_id
        domains = $candidateRoot.domains
    })
    Assert-P2GenerationEvolution -Baseline $baselineRoot -Candidate $candidateRoot `
        -BaselineContent $baselineContent -CandidateContent $candidateContent `
        -Context "stable ID manifest"
    return $true
}

function Assert-P2PresentationArrayEvolution {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$BaselineItems,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$CandidateItems,
        [Parameter(Mandatory = $true)][string]$IdProperty,
        [Parameter(Mandatory = $true)][string]$Context,
        [string[]]$SemanticProperties = @()
    )

    Assert-P2Condition ($CandidateItems.Count -ge $BaselineItems.Count) `
        "P2_EVOLUTION_ENTRY_REMOVED" "$Context entries cannot be removed."
    $baselineMaximum = 0L
    foreach ($itemValue in $BaselineItems) {
        $item = [PSCustomObject]$itemValue
        if ([long]$item.$IdProperty -gt $baselineMaximum) {
            $baselineMaximum = [long]$item.$IdProperty
        }
    }
    for ($index = 0; $index -lt $BaselineItems.Count; $index++) {
        $baselineItem = [PSCustomObject]$BaselineItems[$index]
        $candidateItem = [PSCustomObject]$CandidateItems[$index]
        Assert-P2Condition (
            [long]$baselineItem.$IdProperty -eq [long]$candidateItem.$IdProperty
        ) "P2_EVOLUTION_ENTRY_REORDERED" `
            "$Context entry[$index] ID cannot be deleted, changed, inserted, or reordered."
        Assert-P2EntryEvolution -Baseline $baselineItem -Candidate $candidateItem `
            -Context "$Context entry[$index]"
        foreach ($property in $SemanticProperties) {
            $baselineValue = ConvertTo-BattleCanonicalJsonValue $baselineItem.$property
            $candidateValue = ConvertTo-BattleCanonicalJsonValue $candidateItem.$property
            Assert-P2Condition ($baselineValue -ceq $candidateValue) `
                "P2_EVOLUTION_SEMANTICS" `
                "$Context entry[$index] semantic property '$property' is immutable."
        }
    }
    for (
        $index = $BaselineItems.Count;
        $index -lt $CandidateItems.Count;
        $index++
    ) {
        $candidateItem = [PSCustomObject]$CandidateItems[$index]
        Assert-P2Condition ([long]$candidateItem.$IdProperty -gt $baselineMaximum) `
            "P2_EVOLUTION_NEW_ID" `
            "$Context new ID $($candidateItem.$IdProperty) must exceed baseline maximum $baselineMaximum."
    }
}

function Test-P2PresentationEvolution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Baseline,
        [Parameter(Mandatory = $true)][object]$Candidate
    )

    $null = Test-P2PresentationContracts -Manifest $Baseline
    $null = Test-P2PresentationContracts -Manifest $Candidate
    $baselineRoot = [PSCustomObject]$Baseline
    $candidateRoot = [PSCustomObject]$Candidate
    Assert-P2RootIdentity -Baseline $baselineRoot -Candidate $candidateRoot `
        -Context "presentation contract manifest"

    Assert-P2PresentationArrayEvolution `
        -BaselineItems @($baselineRoot.tags) `
        -CandidateItems @($candidateRoot.tags) `
        -IdProperty "presentation_tag_id" -Context "presentation tags"
    Assert-P2PresentationArrayEvolution `
        -BaselineItems @($baselineRoot.payload_schemas) `
        -CandidateItems @($candidateRoot.payload_schemas) `
        -IdProperty "payload_schema_id" -Context "payload schemas" `
        -SemanticProperties @("schema_version", "fields")
    Assert-P2PresentationArrayEvolution `
        -BaselineItems @($baselineRoot.cues) `
        -CandidateItems @($candidateRoot.cues) `
        -IdProperty "presentation_cue_id" -Context "presentation cues" `
        -SemanticProperties @(
            "presentation_tags", "semantic_phase", "information_class",
            "fallback_text_key", "local_barrier_policy", "payload_schema_id"
        )

    $baselineContent = ConvertTo-BattleCanonicalJsonValue ([ordered]@{
        schema_version = $baselineRoot.schema_version
        manifest_kind = $baselineRoot.manifest_kind
        invalid_id = $baselineRoot.invalid_id
        max_id = $baselineRoot.max_id
        tags = $baselineRoot.tags
        payload_schemas = $baselineRoot.payload_schemas
        cues = $baselineRoot.cues
    })
    $candidateContent = ConvertTo-BattleCanonicalJsonValue ([ordered]@{
        schema_version = $candidateRoot.schema_version
        manifest_kind = $candidateRoot.manifest_kind
        invalid_id = $candidateRoot.invalid_id
        max_id = $candidateRoot.max_id
        tags = $candidateRoot.tags
        payload_schemas = $candidateRoot.payload_schemas
        cues = $candidateRoot.cues
    })
    Assert-P2GenerationEvolution -Baseline $baselineRoot -Candidate $candidateRoot `
        -BaselineContent $baselineContent -CandidateContent $candidateContent `
        -Context "presentation contract manifest"
    return $true
}
