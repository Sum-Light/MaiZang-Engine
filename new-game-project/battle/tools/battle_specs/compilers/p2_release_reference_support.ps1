Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "p2_source_evidence_join_support.ps1")
. (Join-Path $PSScriptRoot "p2_fixture_preflight_support.ps1")

$script:P2FClosureContractVersion = 1
$script:P2FManifestSchemaVersion = 1
$script:P2FWorkItemPrefix = "new-game-project/battle/manifests/work_items"
$script:P2FWorkItemPattern = (
    '^new-game-project/battle/manifests/work_items/' +
    '(?<name>[A-Z0-9_.-]+)\.json$'
)
$script:P2FMaxWorkItems = 4096
$script:P2FMaxContractBytes = 8388608
$script:P2FValidationScope = "STATIC_REFERENCE_TRIPLE_ONLY"

function Throw-P2FError {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    throw "$Code`: $Message"
}

function Assert-P2FCondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        Throw-P2FError -Code $Code -Message $Message
    }
}

function Assert-P2FExactProperties {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Context,
        [string]$Code = "P2F_SCHEMA"
    )

    Assert-P2FCondition (
        $null -ne $Value -and $Value -is [PSCustomObject]
    ) $Code "$Context must be a JSON object."
    $actual = @($Value.PSObject.Properties.Name)
    $actualSet = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($name in $actual) { $null = $actualSet.Add([string]$name) }
    $expectedSet = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($name in $Expected) { $null = $expectedSet.Add([string]$name) }
    $missing = @($Expected | Where-Object { -not $actualSet.Contains($_) })
    $unknown = @($actual | Where-Object { -not $expectedSet.Contains($_) })
    Assert-P2FCondition (
        $missing.Count -eq 0 -and $unknown.Count -eq 0
    ) $Code (
        "$Context is not closed; missing=[$($missing -join ',')], " +
        "unknown=[$($unknown -join ',')]."
    )
}

function Assert-P2FRequiredProperties {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string[]]$Required,
        [Parameter(Mandatory = $true)][string]$Context,
        [string]$Code = "P2F_INPUT"
    )

    Assert-P2FCondition (
        $null -ne $Value -and $Value -is [PSCustomObject]
    ) $Code "$Context must be an object."
    foreach ($name in $Required) {
        Assert-P2FCondition (
            $Value.PSObject.Properties.Name -ccontains $name
        ) $Code "$Context omits '$name'."
    }
}

function Get-P2FInteger {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [long]$Minimum = 0,
        [long]$Maximum = 2147483647
    )

    Assert-P2FCondition (
        $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64]
    ) "P2F_SCHEMA" "$Context must be an integer."
    $integer = [long]$Value
    Assert-P2FCondition (
        $integer -ge $Minimum -and $integer -le $Maximum
    ) "P2F_SCHEMA" "$Context is outside $Minimum..$Maximum."
    return $integer
}

function Get-P2FString {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$MaximumLength = 1024
    )

    Assert-P2FCondition ($Value -is [string]) "P2F_SCHEMA" `
        "$Context must be a string."
    $text = [string]$Value
    Assert-P2FCondition (
        $text.Length -gt 0 -and $text.Length -le $MaximumLength -and
        $text -cmatch $Pattern
    ) "P2F_SCHEMA" "$Context has an invalid value."
    return $text
}

function Assert-P2FArray {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [int]$MinimumCount = 0,
        [int]$MaximumCount = 65535
    )

    Assert-P2FCondition (
        $null -ne $Value -and $Value -is [Array]
    ) "P2F_SCHEMA" "$Context must be an array."
    $count = @($Value).Count
    Assert-P2FCondition (
        $count -ge $MinimumCount -and $count -le $MaximumCount
    ) "P2F_SCHEMA" (
        "$Context requires $MinimumCount..$MaximumCount items."
    )
}

function Get-P2FSortedLongArray {
    param([AllowEmptyCollection()][object[]]$Values)

    $seen = [Collections.Generic.HashSet[long]]::new()
    foreach ($value in @($Values)) { $null = $seen.Add([long]$value) }
    [long[]]$result = @($seen)
    [Array]::Sort($result)
    return ,$result
}

function Get-P2FSortedStringArray {
    param([AllowEmptyCollection()][object[]]$Values)

    $seen = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($value in @($Values)) { $null = $seen.Add([string]$value) }
    [string[]]$result = @($seen)
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return ,$result
}

function Test-P2FLongArrayContains {
    param([AllowNull()][object]$Values, [long]$Expected)

    foreach ($value in @($Values)) {
        if ([long]$value -eq $Expected) { return $true }
    }
    return $false
}

function Test-P2FStringArrayContains {
    param([AllowNull()][object]$Values, [string]$Expected)

    foreach ($value in @($Values)) {
        if ([string]$value -ceq $Expected) { return $true }
    }
    return $false
}

function Get-P2FSha256Bytes {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace(
            "-", ""
        ).ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Read-P2FContractBytes {
    param(
        [Parameter(Mandatory = $true)][string]$ContractRoot,
        [Parameter(Mandatory = $true)][string]$Document
    )

    $root = [IO.Path]::GetFullPath($ContractRoot).TrimEnd('\')
    Assert-P2FCondition (
        Test-Path -LiteralPath $root -PathType Container
    ) "P2F_CONTRACT_ROOT" "Godot contract root is missing."
    $path = [IO.Path]::GetFullPath((Join-Path $root $Document))
    Assert-P2FCondition (
        (Split-Path -Parent $path).Equals(
            $root, [StringComparison]::OrdinalIgnoreCase
        )
    ) "P2F_CONTRACT_PATH" "Godot contract document escapes its root."
    $guard = $null
    $stream = $null
    try {
        $guard = Open-P2RepositoryViewVerifiedHandle -Path $path `
            -ExpectedFinalPath $path -ExpectedKind File -Access Read `
            -ErrorPrefix "P2F_CONTRACT"
        $stream = [IO.FileStream]::new(
            [Microsoft.Win32.SafeHandles.SafeFileHandle]$guard.Handle,
            [IO.FileAccess]::Read
        )
        Assert-P2FCondition (
            $stream.Length -gt 0 -and
            $stream.Length -le $script:P2FMaxContractBytes
        ) "P2F_CONTRACT_SIZE" (
            "Godot contract must be 1..$script:P2FMaxContractBytes bytes."
        )
        $bytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            Assert-P2FCondition ($read -gt 0) "P2F_CONTRACT_TORN_READ" `
                "Godot contract ended during its bounded read."
            $offset += $read
        }
        Assert-P2FCondition ($stream.ReadByte() -eq -1) `
            "P2F_CONTRACT_TORN_READ" `
            "Godot contract changed during its bounded read."
        return ,$bytes
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        elseif ($null -ne $guard) { $guard.Handle.Dispose() }
    }
}

function Get-P2FMarkdownHeadings {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Document
    )

    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
    }
    catch {
        Throw-P2FError "P2F_CONTRACT_UTF8" `
            "Godot contract '$Document' is not strict UTF-8."
    }
    # Release refs accept only column-zero ATX headings; ambiguous Markdown
    # containers are excluded instead of approximating the full block parser.
    $lines = [regex]::Split($text, "\r\n|\n|\r")
    $headings = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $fenceCharacter = ""
    $fenceLength = 0
    $htmlBlockEndPattern = ""
    $htmlBlockUntilBlank = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]

        if ($fenceLength -gt 0) {
            $closingFencePattern = '^[ ]{0,3}' +
                [regex]::Escape($fenceCharacter) +
                "{$fenceLength,}[ \t]*`$"
            if ($line -cmatch $closingFencePattern) {
                $fenceCharacter = ""
                $fenceLength = 0
            }
            continue
        }

        if ($htmlBlockUntilBlank) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                $htmlBlockUntilBlank = $false
            }
            continue
        }
        if (-not [string]::IsNullOrEmpty($htmlBlockEndPattern)) {
            if ([regex]::IsMatch(
                $line, $htmlBlockEndPattern,
                [Text.RegularExpressions.RegexOptions]::IgnoreCase
            )) {
                $htmlBlockEndPattern = ""
            }
            continue
        }

        $htmlEndPattern = ""
        if ($line -cmatch '^[ ]{0,3}<!--') {
            $htmlEndPattern = '-->'
        }
        elseif ($line -cmatch '^[ ]{0,3}<\?') {
            $htmlEndPattern = '\?>'
        }
        elseif ($line -cmatch '^[ ]{0,3}<!\[CDATA\[') {
            $htmlEndPattern = '\]\]>'
        }
        elseif ($line -cmatch '^[ ]{0,3}<![A-Z]') {
            $htmlEndPattern = '>'
        }
        if (-not [string]::IsNullOrEmpty($htmlEndPattern)) {
            if (-not [regex]::IsMatch(
                $line, $htmlEndPattern,
                [Text.RegularExpressions.RegexOptions]::IgnoreCase
            )) {
                $htmlBlockEndPattern = $htmlEndPattern
            }
            continue
        }

        $rawHtmlBlock = [regex]::Match(
            $line,
            '^[ ]{0,3}<(?<closing>/?)(?<tag>[A-Za-z][A-Za-z0-9-]*)' +
                '(?:[ \t/>]|$)',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($rawHtmlBlock.Success) {
            $tag = $rawHtmlBlock.Groups['tag'].Value
            if ($rawHtmlBlock.Groups['closing'].Value.Length -eq 0 -and
                $tag -cin @('script', 'pre', 'style', 'textarea')) {
                $endPattern = '</' + [regex]::Escape($tag) + '\s*>'
                if (-not [regex]::IsMatch(
                    $line, $endPattern,
                    [Text.RegularExpressions.RegexOptions]::IgnoreCase
                )) {
                    $htmlBlockEndPattern = $endPattern
                }
            }
            else {
                $htmlBlockUntilBlank = $true
            }
            continue
        }

        $openingFence = [regex]::Match(
            $line,
            '^[ ]{0,3}(?<marker>`{3,}|~{3,})(?<info>.*)$'
        )
        if ($openingFence.Success) {
            $marker = $openingFence.Groups['marker'].Value
            $candidateCharacter = $marker.Substring(0, 1)
            $info = $openingFence.Groups['info'].Value
            if ($candidateCharacter -ceq '~' -or -not $info.Contains('`')) {
                $fenceCharacter = $candidateCharacter
                $fenceLength = $marker.Length
                continue
            }
        }

        $atx = [regex]::Match(
            $line,
            '^#{1,6}(?:[ \t]+(?<heading>.*)|[ \t]*)$'
        )
        if ($atx.Success) {
            $heading = $atx.Groups['heading'].Value.TrimEnd()
            if ($heading -cmatch '^#+$') {
                $heading = ""
            }
            else {
                $heading = [regex]::Replace($heading, '[ \t]+#+$', '').Trim()
            }
            if (-not [string]::IsNullOrWhiteSpace($heading)) {
                $null = $headings.Add($heading)
            }
            continue
        }
    }
    return ,$headings
}

function ConvertFrom-P2FWorkItemBytes {
    param(
        [AllowNull()][object]$Bytes,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-P2FCondition (
        $null -ne $Bytes -and $Bytes -is [byte[]]
    ) "P2F_WORK_ITEM_BYTES" "$Context was not captured as bytes."
    $value = [byte[]]$Bytes
    Assert-P2FCondition (
        $value.Length -gt 0 -and $value.Length -le 524288
    ) "P2F_WORK_ITEM_SIZE" "$Context exceeds the bounded JSON size."
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($value)
    }
    catch {
        Throw-P2FError "P2F_WORK_ITEM_UTF8" "$Context is not strict UTF-8."
    }
    return ConvertFrom-BattleStrictJson -Text $text -Label $Context
}

function Assert-P2FUniqueIds {
    param(
        [AllowNull()][object]$Values,
        [Parameter(Mandatory = $true)][string]$Context,
        [int]$MaximumCount = 4096
    )

    Assert-P2FArray $Values $Context 0 $MaximumCount
    $seen = [Collections.Generic.HashSet[long]]::new()
    foreach ($value in @($Values)) {
        $id = Get-P2FInteger $value "$Context item" 1 2147483647
        Assert-P2FCondition ($seen.Add($id)) "P2F_WORK_ITEM_DUPLICATE" `
            "$Context repeats ID $id."
    }
}

function Test-P2FWorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$WorkItem,
        [AllowEmptyString()][string]$ContractRoot = "",
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$ContractHashCache
    )

    $root = [PSCustomObject]$WorkItem
    Assert-P2FExactProperties -Value $root -Context "ImplementationWorkItem" `
        -Expected @(
            "schema_version", "work_item_id", "godot_contract_refs",
            "source_evidence_refs", "source_test_evidence_refs",
            "licensed_data_refs", "mechanism_ids", "coverage_targets",
            "target_godot_types", "fixture_ids", "presentation_cue_ids",
            "known_ambiguities", "completion_status"
        )
    Assert-P2FCondition (
        (Get-P2FInteger $root.schema_version `
            "ImplementationWorkItem.schema_version" 1 1) -eq 1
    ) "P2F_WORK_ITEM_VERSION" "ImplementationWorkItem version is unsupported."
    $workItemId = Get-P2FString $root.work_item_id `
        "ImplementationWorkItem.work_item_id" `
        '^[A-Z0-9][A-Z0-9_.-]*$' 128
    Assert-P2FUniqueIds $root.mechanism_ids `
        "ImplementationWorkItem.mechanism_ids"
    $requiresContractSection = @($root.mechanism_ids).Count -gt 0

    Assert-P2FArray $root.godot_contract_refs `
        "ImplementationWorkItem.godot_contract_refs" 1 64
    $contractKeys = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $contractRefHashes = [Collections.Generic.List[string]]::new()
    foreach ($referenceValue in @($root.godot_contract_refs)) {
        $reference = [PSCustomObject]$referenceValue
        Assert-P2FExactProperties -Value $reference `
            -Context "Godot contract reference" `
            -Expected @("document", "section", "sha256")
        $document = Get-P2FString $reference.document `
            "Godot contract document" '^[0-9A-Za-z_.-]+\.md$' 255
        $section = Get-P2FString $reference.section `
            "Godot contract section" '^(?=.*\S)[^\r\n\x00-\x1f\x7f]+$' 512
        $expectedHash = Get-P2FString $reference.sha256 `
            "Godot contract SHA-256" '^[0-9a-f]{64}$' 64
        $key = "$document`t$section`t$expectedHash"
        Assert-P2FCondition ($contractKeys.Add($key)) `
            "P2F_WORK_ITEM_DUPLICATE" `
            "Work item $workItemId repeats a Godot contract reference."
        if (-not [string]::IsNullOrWhiteSpace($ContractRoot)) {
            if (-not $ContractHashCache.ContainsKey($document)) {
                $bytes = Read-P2FContractBytes -ContractRoot $ContractRoot `
                    -Document $document
                $ContractHashCache.Add(
                    $document,
                    [pscustomobject][ordered]@{
                        Hash = Get-P2FSha256Bytes $bytes
                        Headings = Get-P2FMarkdownHeadings `
                            -Bytes $bytes -Document $document
                    }
                )
            }
            $contract = [PSCustomObject]$ContractHashCache[$document]
            Assert-P2FCondition (
                [string]$contract.Hash -ceq $expectedHash
            ) "P2F_GODOT_CONTRACT_REF_STALE" (
                "Work item $workItemId has a stale contract hash for " +
                "'$document'."
            )
            if ($requiresContractSection) {
                Assert-P2FCondition (
                    $contract.Headings.Contains($section)
                ) "P2F_GODOT_CONTRACT_SECTION_MISSING" (
                    "Work item $workItemId names missing top-level ATX " +
                    "Markdown heading " +
                    "'$section' in '$document'."
                )
            }
        }
        $contractRefHashes.Add((Get-BattleSha256Text (
            ConvertTo-BattleCanonicalJson -Value $reference
        )))
    }

    $sourceKeys = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($definition in @(
        [pscustomobject]@{Name = "source_evidence_refs"; Minimum = 1},
        [pscustomobject]@{Name = "source_test_evidence_refs"; Minimum = 0}
    )) {
        $values = $root.($definition.Name)
        Assert-P2FArray $values "ImplementationWorkItem.$($definition.Name)" `
            ([int]$definition.Minimum) 256
        foreach ($referenceValue in @($values)) {
            $reference = [PSCustomObject]$referenceValue
            Assert-P2FExactProperties -Value $reference `
                -Context "Source evidence reference" -Expected @(
                    "source_kind", "source_repository", "relative_path",
                    "symbol", "sha256"
                )
            $kind = Get-P2FString $reference.source_kind "Source kind" `
                '^(SOURCE_CODE|SOURCE_SCHEMA|SOURCE_TEST|PROJECT_DECISION)$' 32
            $repository = Get-P2FString $reference.source_repository `
                "Source repository" '^(battlelogic|pokelib|MaiZangEngine)$' 32
            $relativePath = Get-P2FString $reference.relative_path `
                "Source relative path" '^[^\\\x00-\x1f\x7f]+$' 1024
            Assert-P2FCondition (
                -not [IO.Path]::IsPathRooted($relativePath) -and
                $relativePath -cnotmatch '(^|/)\.{1,2}(/|$)' -and
                $relativePath -cnotmatch '//|/$'
            ) "P2F_WORK_ITEM_PATH" `
                "Work item $workItemId has a non-canonical source path."
            $symbol = Get-P2FString $reference.symbol "Source symbol" `
                '^(?=.*\S)[^\r\n\x00-\x1f\x7f]+$' 512
            $hash = Get-P2FString $reference.sha256 "Source SHA-256" `
                '^[0-9a-f]{64}$' 64
            Assert-P2FCondition (
                -not ($repository -cin @("battlelogic", "pokelib") -and
                    $kind -ceq "PROJECT_DECISION") -and
                -not ($repository -ceq "MaiZangEngine" -and
                    $kind -cne "PROJECT_DECISION")
            ) "P2F_WORK_ITEM_SOURCE_KIND" (
                "Work item $workItemId has an invalid source/repository pairing."
            )
            $key = "$kind`t$repository`t$relativePath`t$symbol`t$hash"
            Assert-P2FCondition ($sourceKeys.Add($key)) `
                "P2F_WORK_ITEM_DUPLICATE" `
                "Work item $workItemId repeats a source reference."
        }
    }

    Assert-P2FUniqueIds $root.fixture_ids `
        "ImplementationWorkItem.fixture_ids"
    Assert-P2FUniqueIds $root.presentation_cue_ids `
        "ImplementationWorkItem.presentation_cue_ids"

    Assert-P2FArray $root.coverage_targets `
        "ImplementationWorkItem.coverage_targets" 0 65535
    $coverageKeys = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($targetValue in @($root.coverage_targets)) {
        $target = [PSCustomObject]$targetValue
        Assert-P2FExactProperties -Value $target -Context "Coverage target" `
            -Expected @("mechanism_id", "branch_id")
        $mechanismId = Get-P2FInteger $target.mechanism_id `
            "Coverage target mechanism_id" 1 2147483647
        $branchId = Get-P2FInteger $target.branch_id `
            "Coverage target branch_id" 1 2147483647
        Assert-P2FCondition ($coverageKeys.Add("$mechanismId`:$branchId")) `
            "P2F_WORK_ITEM_DUPLICATE" `
            "Work item $workItemId repeats a coverage target."
    }

    foreach ($definition in @(
        [pscustomobject]@{
            Name = "licensed_data_refs"; Pattern = '^[A-Z0-9_.-]+$'; Max = 4096
        },
        [pscustomobject]@{
            Name = "target_godot_types";
            Pattern = '^[A-Za-z_][A-Za-z0-9_]*$'; Max = 512
        },
        [pscustomobject]@{
            Name = "known_ambiguities";
            Pattern = '^(?=.*\S)[^\r\n\x00-\x1f\x7f]+$'; Max = 64
        }
    )) {
        $values = $root.($definition.Name)
        Assert-P2FArray $values "ImplementationWorkItem.$($definition.Name)" `
            0 ([int]$definition.Max)
        $seen = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal
        )
        foreach ($value in @($values)) {
            $text = Get-P2FString $value `
                "ImplementationWorkItem.$($definition.Name) item" `
                ([string]$definition.Pattern) 1024
            Assert-P2FCondition ($seen.Add($text)) `
                "P2F_WORK_ITEM_DUPLICATE" `
                "Work item $workItemId repeats $($definition.Name) '$text'."
        }
    }

    $completionStatus = Get-P2FString $root.completion_status `
        "ImplementationWorkItem.completion_status" (
            '^(NOT_STARTED|SPECIFIED|IMPORTED|BOUND|IMPLEMENTED|VERIFIED|' +
            'RELEASED|BLOCKED_SOURCE|REJECTED_UNVERIFIED|DEFERRED_N0|' +
            'OUT_OF_SCOPE_PRESENTATION|MERGED_INTO_OTHER_MECHANISM)$'
        ) 64
    $canonicalJson = ConvertTo-BattleCanonicalJson -Value $root
    return [pscustomobject][ordered]@{
        WorkItemId = $workItemId
        CompletionStatus = $completionStatus
        ContractRefHashes = Get-P2FSortedStringArray $contractRefHashes.ToArray()
        CanonicalJson = $canonicalJson
        Sha256 = Get-BattleSha256Text $canonicalJson
    }
}

function Read-P2FValidatedWorkItemSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [AllowEmptyString()][string]$GodotContractRoot = ""
    )

    Assert-P2RepositoryViewObject $View
    $paths = @(Get-P2RepositoryViewPaths -View $View `
        -Prefix $script:P2FWorkItemPrefix)
    Assert-P2FCondition ($paths.Count -le $script:P2FMaxWorkItems) `
        "P2F_WORK_ITEM_COUNT" `
        "ImplementationWorkItem count exceeds $script:P2FMaxWorkItems."
    $records = [Collections.Generic.List[object]]::new()
    $inputs = [Collections.Generic.List[object]]::new()
    $seenIds = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $contractCache = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($pathValue in $paths) {
        $path = [string]$pathValue
        Assert-P2FCondition ($path -cmatch $script:P2FWorkItemPattern) `
            "P2F_WORK_ITEM_FILENAME" `
            "'$path' is not an anchored work-item JSON path."
        $manifest = ConvertFrom-P2FWorkItemBytes `
            -Bytes (Get-P2RepositoryViewBytes -View $View -RelativePath $path) `
            -Context $path
        $validation = Test-P2FWorkItem -WorkItem $manifest `
            -ContractRoot $GodotContractRoot -ContractHashCache $contractCache
        Assert-P2FCondition ($seenIds.Add([string]$validation.WorkItemId)) `
            "P2F_WORK_ITEM_ID_DUPLICATE" `
            "Work item ID '$($validation.WorkItemId)' is repeated."
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
    $inputSet = [pscustomobject][ordered]@{
        schema_version = 1
        implementation_work_items = $inputs.ToArray()
    }
    $inputJson = ConvertTo-BattleCanonicalJson -Value $inputSet
    return [pscustomobject][ordered]@{
        Records = $records.ToArray()
        InputSet = $inputSet
        InputSetJson = $inputJson
        InputSetHash = Get-BattleSha256Text $inputJson
    }
}

function Test-P2FLongArraysEqual {
    param([AllowNull()][object]$Left, [AllowNull()][object]$Right)

    $leftValues = @($Left)
    $rightValues = @($Right)
    if ($leftValues.Count -ne $rightValues.Count) { return $false }
    for ($index = 0; $index -lt $leftValues.Count; $index++) {
        if ([long]$leftValues[$index] -ne [long]$rightValues[$index]) {
            return $false
        }
    }
    return $true
}

function Test-P2FStringArraysEqual {
    param([AllowNull()][object]$Left, [AllowNull()][object]$Right)

    $leftValues = @($Left)
    $rightValues = @($Right)
    if ($leftValues.Count -ne $rightValues.Count) { return $false }
    for ($index = 0; $index -lt $leftValues.Count; $index++) {
        if ([string]$leftValues[$index] -cne [string]$rightValues[$index]) {
            return $false
        }
    }
    return $true
}

function Assert-P2FCanonicalResult {
    param(
        [Parameter(Mandatory = $true)][object]$Result,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string]$Code
    )

    Assert-P2FRequiredProperties -Value $Result `
        -Required @("Manifest", "ManifestJson", "ManifestHash") `
        -Context $Context -Code $Code
    $canonical = ConvertTo-BattleCanonicalJson -Value $Result.Manifest
    Assert-P2FCondition (
        $canonical -ceq [string]$Result.ManifestJson
    ) $Code "$Context canonical JSON was substituted."
    Assert-P2FCondition (
        (Get-BattleSha256Text $canonical) -ceq [string]$Result.ManifestHash
    ) $Code "$Context SHA-256 does not match its canonical manifest."
}

function Assert-P2FSpecSet {
    param([Parameter(Mandatory = $true)][object]$SpecSet)

    Assert-P2FRequiredProperties -Value $SpecSet -Context "SpecSet" `
        -Code "P2F_SPEC_SET" -Required @(
            "StableManifestHash", "PresentationManifestHash",
            "MechanismSpecs", "TestEntries", "InputSet", "InputSetHash"
        )
    foreach ($hashName in @("StableManifestHash", "PresentationManifestHash")) {
        $null = Get-P2FString $SpecSet.$hashName "SpecSet.$hashName" `
            '^[0-9a-f]{64}$' 64
    }
    Assert-P2FExactProperties -Value $SpecSet.InputSet `
        -Context "SpecSet.InputSet" -Code "P2F_SPEC_INPUT_SET" `
        -Expected @(
            "schema_version", "mechanism_specs", "event_schemas",
            "handler_bindings", "resolver_specs", "test_entries"
        )
    Assert-P2FCondition (
        (Get-P2FInteger $SpecSet.InputSet.schema_version `
            "SpecSet.InputSet.schema_version" 1 1) -eq 1
    ) "P2F_SPEC_INPUT_SET" "Spec input-set version is unsupported."
    $inputJson = ConvertTo-BattleCanonicalJson -Value $SpecSet.InputSet
    Assert-P2FCondition (
        (Get-BattleSha256Text $inputJson) -ceq [string]$SpecSet.InputSetHash
    ) "P2F_SPEC_INPUT_SET_HASH" `
        "SpecSet input-set hash does not match its canonical projection."

    $result = [ordered]@{}
    foreach ($definition in @(
        [pscustomobject]@{
            Name = "MechanismSpecs"; Input = "mechanism_specs";
            Id = "mechanism_id"; Required = @(
                "mechanism_id", "target_maturity",
                "project_requirement_keys", "evidence_ids"
            )
        },
        [pscustomobject]@{
            Name = "TestEntries"; Input = "test_entries";
            Id = "test_id"; Required = @(
                "test_id", "test_kind", "fixture_id", "coverage_targets",
                "expected_event_ids", "expected_handler_ids",
                "expected_state_op_ids", "expected_command_ids",
                "required_oracle_kinds"
            )
        }
    )) {
        $records = @($SpecSet.($definition.Name))
        $inputs = @($SpecSet.InputSet.($definition.Input))
        Assert-P2FCondition ($records.Count -eq $inputs.Count) `
            "P2F_SPEC_INPUT_BINDING" `
            "$($definition.Name) count differs from its input index."
        $inputByPath = [Collections.Generic.Dictionary[string, string]]::new(
            [StringComparer]::Ordinal
        )
        foreach ($inputValue in $inputs) {
            $input = [PSCustomObject]$inputValue
            Assert-P2FExactProperties -Value $input `
                -Context "$($definition.Input) input" `
                -Code "P2F_SPEC_INPUT_SET" `
                -Expected @("relative_path", "canonical_sha256")
            $path = Get-P2FString $input.relative_path `
                "$($definition.Input) path" '^[^\\\x00-\x1f\x7f]+$' 1024
            $hash = Get-P2FString $input.canonical_sha256 `
                "$($definition.Input) hash" '^[0-9a-f]{64}$' 64
            Assert-P2FCondition (-not $inputByPath.ContainsKey($path)) `
                "P2F_SPEC_INPUT_DUPLICATE" `
                "$($definition.Input) repeats path '$path'."
            $inputByPath.Add($path, $hash)
        }
        $byId = [Collections.Generic.Dictionary[long, object]]::new()
        $seenPaths = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal
        )
        foreach ($recordValue in $records) {
            $record = [PSCustomObject]$recordValue
            Assert-P2FRequiredProperties -Value $record `
                -Required @("RelativePath", "Manifest", "Validation") `
                -Context "$($definition.Name) record" `
                -Code "P2F_SPEC_RECORD"
            $path = [string]$record.RelativePath
            Assert-P2FRequiredProperties -Value $record.Validation `
                -Required @("Sha256") -Context "$path validation" `
                -Code "P2F_SPEC_RECORD"
            Assert-P2FRequiredProperties -Value $record.Manifest `
                -Required ([string[]]$definition.Required) `
                -Context "$path manifest" -Code "P2F_SPEC_RECORD"
            $id = Get-P2FInteger $record.Manifest.($definition.Id) `
                "$path $($definition.Id)" 1 2147483647
            Assert-P2FCondition (-not $byId.ContainsKey($id)) `
                "P2F_SPEC_ID_DUPLICATE" `
                "$($definition.Name) repeats ID $id."
            Assert-P2FCondition ($seenPaths.Add($path)) `
                "P2F_SPEC_PATH_DUPLICATE" `
                "$($definition.Name) repeats path '$path'."
            $canonicalHash = Get-BattleSha256Text (
                ConvertTo-BattleCanonicalJson -Value $record.Manifest
            )
            Assert-P2FCondition (
                $canonicalHash -ceq [string]$record.Validation.Sha256
            ) "P2F_SPEC_RECORD_HASH" `
                "$path validation hash is not canonical."
            Assert-P2FCondition (
                $inputByPath.ContainsKey($path) -and
                [string]$inputByPath[$path] -ceq $canonicalHash
            ) "P2F_SPEC_INPUT_BINDING" `
                "$path is not bound to its canonical input record."
            $byId.Add($id, $record)
        }
        $result[$definition.Name] = $byId
    }
    return [pscustomobject]$result
}

function Test-P2FByteArraysEqual {
    param(
        [AllowNull()][byte[]]$Left,
        [AllowNull()][byte[]]$Right
    )

    if ($null -eq $Left -or $null -eq $Right -or
        $Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function Assert-P2FCompilation {
    param([Parameter(Mandatory = $true)][object]$Compilation)

    Assert-P2FRequiredProperties -Value $Compilation `
        -Required @(
            "CompilerContractVersion", "SpecSet", "SpecManifest",
            "SpecManifestJson", "SpecManifestBytes", "SpecManifestHash"
        ) -Context "Compilation" -Code "P2F_SPEC_COMPILATION_TAMPERED"
    Assert-P2FCondition (
        [long]$Compilation.CompilerContractVersion -eq
            [long]$script:P2CompilerContractVersion
    ) "P2F_SPEC_COMPILATION_TAMPERED" `
        "Compilation uses an unsupported P2C contract version."

    $specIndexes = Assert-P2FSpecSet -SpecSet $Compilation.SpecSet
    $canonical = ConvertTo-BattleCanonicalJson -Value $Compilation.SpecManifest
    $expectedBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes(
        $canonical
    )
    Assert-P2FCondition (
        $canonical -ceq [string]$Compilation.SpecManifestJson -and
        (Get-BattleSha256Text $canonical) -ceq
            [string]$Compilation.SpecManifestHash -and
        (Test-P2FByteArraysEqual $expectedBytes `
            ([byte[]]$Compilation.SpecManifestBytes))
    ) "P2F_SPEC_COMPILATION_TAMPERED" `
        "Compilation spec JSON, bytes, or hash is not canonical."

    $manifest = [PSCustomObject]$Compilation.SpecManifest
    Assert-P2FExactProperties -Value $manifest `
        -Context "Compiled spec manifest" `
        -Code "P2F_SPEC_COMPILATION_TAMPERED" -Expected @(
            "manifest_kind", "schema_version", "compiler_contract_version",
            "stable_id_manifest_sha256", "presentation_contracts_sha256",
            "authoring_input_set_sha256", "mechanisms", "events",
            "handlers", "resolvers", "tests"
        )
    Assert-P2FCondition (
        [string]$manifest.manifest_kind -ceq "COMPILED_SPEC_MANIFEST" -and
        [long]$manifest.schema_version -eq 1 -and
        [long]$manifest.compiler_contract_version -eq
            [long]$Compilation.CompilerContractVersion -and
        [string]$manifest.stable_id_manifest_sha256 -ceq
            [string]$Compilation.SpecSet.StableManifestHash -and
        [string]$manifest.presentation_contracts_sha256 -ceq
            [string]$Compilation.SpecSet.PresentationManifestHash -and
        [string]$manifest.authoring_input_set_sha256 -ceq
            [string]$Compilation.SpecSet.InputSetHash
    ) "P2F_SPEC_COMPILATION_TAMPERED" `
        "Compiled spec identity does not bind the validated SpecSet."

    foreach ($definition in @(
        [pscustomobject]@{
            Rows = @($manifest.mechanisms)
            Records = $specIndexes.MechanismSpecs
            Id = "mechanism_id"
            Fields = @(
                "mechanism_id", "spec_schema_version", "behavior_version",
                "canonical_authoring_sha256", "target_maturity",
                "computed_status"
            )
        },
        [pscustomobject]@{
            Rows = @($manifest.tests)
            Records = $specIndexes.TestEntries
            Id = "test_id"
            Fields = @("test_id", "schema_version", "canonical_authoring_sha256")
        }
    )) {
        Assert-P2FCondition (
            @($definition.Rows).Count -eq $definition.Records.Count
        ) "P2F_SPEC_COMPILATION_TAMPERED" `
            "Compiled spec index count differs from its validated records."
        $previousId = 0L
        foreach ($rowValue in @($definition.Rows)) {
            $row = [PSCustomObject]$rowValue
            Assert-P2FExactProperties -Value $row -Expected $definition.Fields `
                -Context "Compiled $($definition.Id) row" `
                -Code "P2F_SPEC_COMPILATION_TAMPERED"
            $id = Get-P2FInteger $row.($definition.Id) `
                "Compiled $($definition.Id)" 1 2147483647
            Assert-P2FCondition (
                $id -gt $previousId -and $definition.Records.ContainsKey($id)
            ) "P2F_SPEC_COMPILATION_TAMPERED" `
                "Compiled $($definition.Id) rows are unknown or unordered."
            $record = $definition.Records[$id]
            Assert-P2FCondition (
                [string]$row.canonical_authoring_sha256 -ceq
                    [string]$record.Validation.Sha256
            ) "P2F_SPEC_COMPILATION_TAMPERED" `
                "Compiled $($definition.Id) $id authoring hash was substituted."
            if ($definition.Id -ceq "mechanism_id") {
                Assert-P2FCondition (
                    [long]$row.spec_schema_version -eq
                        [long]$record.Manifest.spec_schema_version -and
                    [long]$row.behavior_version -eq
                        [long]$record.Manifest.behavior_version -and
                    [string]$row.target_maturity -ceq
                        [string]$record.Manifest.target_maturity -and
                    [string]$row.computed_status -cmatch
                        '^(DISCOVERED|SPECIFIED)$'
                ) "P2F_SPEC_COMPILATION_TAMPERED" `
                    "Compiled mechanism $id identity or maturity was substituted."
            }
            else {
                Assert-P2FCondition (
                    [long]$row.schema_version -eq
                        [long]$record.Manifest.schema_version
                ) "P2F_SPEC_COMPILATION_TAMPERED" `
                    "Compiled test $id schema version was substituted."
            }
            $previousId = $id
        }
    }
    return $specIndexes
}

function Assert-P2FWorkItemSet {
    param([Parameter(Mandatory = $true)][object]$WorkItemSet)

    Assert-P2FRequiredProperties -Value $WorkItemSet `
        -Required @("Records", "InputSet", "InputSetHash") `
        -Context "WorkItemSet" -Code "P2F_WORK_ITEM_SET"
    Assert-P2FExactProperties -Value $WorkItemSet.InputSet `
        -Expected @("schema_version", "implementation_work_items") `
        -Context "WorkItemSet.InputSet" -Code "P2F_WORK_ITEM_SET"
    Assert-P2FCondition (
        (Get-P2FInteger $WorkItemSet.InputSet.schema_version `
            "WorkItemSet.InputSet.schema_version" 1 1) -eq 1
    ) "P2F_WORK_ITEM_SET" "Work-item input-set version is unsupported."
    $canonicalInput = ConvertTo-BattleCanonicalJson -Value $WorkItemSet.InputSet
    Assert-P2FCondition (
        (Get-BattleSha256Text $canonicalInput) -ceq
        [string]$WorkItemSet.InputSetHash
    ) "P2F_WORK_ITEM_INPUT_HASH" `
        "Work-item input-set hash is not canonical."
    $inputs = @($WorkItemSet.InputSet.implementation_work_items)
    $records = @($WorkItemSet.Records)
    Assert-P2FCondition ($inputs.Count -eq $records.Count) `
        "P2F_WORK_ITEM_INPUT_BINDING" `
        "Work-item record count differs from its input index."
    $inputByPath = [Collections.Generic.Dictionary[string, string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($inputValue in $inputs) {
        $input = [PSCustomObject]$inputValue
        Assert-P2FExactProperties -Value $input `
            -Expected @("relative_path", "canonical_sha256") `
            -Context "Work-item input" -Code "P2F_WORK_ITEM_SET"
        $path = [string]$input.relative_path
        $hash = Get-P2FString $input.canonical_sha256 `
            "Work-item input hash" '^[0-9a-f]{64}$' 64
        Assert-P2FCondition (-not $inputByPath.ContainsKey($path)) `
            "P2F_WORK_ITEM_INPUT_DUPLICATE" `
            "Work-item input path '$path' is repeated."
        $inputByPath.Add($path, $hash)
    }
    $byId = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($recordValue in $records) {
        $record = [PSCustomObject]$recordValue
        Assert-P2FRequiredProperties -Value $record `
            -Required @("RelativePath", "Manifest", "Validation") `
            -Context "Work-item record" -Code "P2F_WORK_ITEM_SET"
        Assert-P2FRequiredProperties -Value $record.Validation `
            -Required @("WorkItemId", "CompletionStatus", "ContractRefHashes", "Sha256") `
            -Context "Work-item validation" -Code "P2F_WORK_ITEM_SET"
        $id = [string]$record.Validation.WorkItemId
        Assert-P2FCondition (-not $byId.ContainsKey($id)) `
            "P2F_WORK_ITEM_ID_DUPLICATE" "Work item '$id' is repeated."
        Assert-P2FCondition (
            [string]$record.Manifest.work_item_id -ceq $id -and
            [string]$record.Manifest.completion_status -ceq
                [string]$record.Validation.CompletionStatus
        ) "P2F_WORK_ITEM_ID_BINDING" `
            "Work-item validation identity/status differs from its manifest."
        $canonicalHash = Get-BattleSha256Text (
            ConvertTo-BattleCanonicalJson -Value $record.Manifest
        )
        Assert-P2FCondition (
            $canonicalHash -ceq [string]$record.Validation.Sha256 -and
            $inputByPath.ContainsKey([string]$record.RelativePath) -and
            [string]$inputByPath[[string]$record.RelativePath] -ceq $canonicalHash
        ) "P2F_WORK_ITEM_INPUT_BINDING" `
            "Work item '$id' is not bound to its canonical input record."
        $expectedContractHashes = [Collections.Generic.List[string]]::new()
        foreach ($reference in @($record.Manifest.godot_contract_refs)) {
            $expectedContractHashes.Add((Get-BattleSha256Text (
                ConvertTo-BattleCanonicalJson -Value $reference
            )))
        }
        Assert-P2FCondition (
            Test-P2FStringArraysEqual `
                (Get-P2FSortedStringArray $expectedContractHashes.ToArray()) `
                @($record.Validation.ContractRefHashes)
        ) "P2F_WORK_ITEM_CONTRACT_BINDING" `
            "Work item '$id' contract hashes were substituted."
        $byId.Add($id, $record)
    }
    return $byId
}

function Assert-P2FEvidenceJoin {
    param(
        [Parameter(Mandatory = $true)][object]$EvidenceJoin,
        [Parameter(Mandatory = $true)][object]$Compilation,
        [Parameter(Mandatory = $true)][object]$SpecSet,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[long, object]]$MechanismRecords,
        [Parameter(Mandatory = $true)][string]$SpecManifestHash,
        [Parameter(Mandatory = $true)][string]$ScopeId,
        [Parameter(Mandatory = $true)][string]$AuditSealHash,
        [Parameter(Mandatory = $true)][string]$AuditManifestHash
    )

    Assert-P2FCanonicalResult -Result $EvidenceJoin `
        -Context "Source-evidence join" -Code "P2F_EVIDENCE_JOIN_TAMPERED"
    Assert-P2FRequiredProperties -Value $EvidenceJoin `
        -Required @(
            "Compilation", "EvidenceSet", "Governance", "AuditValidation"
        ) -Context "Source-evidence join" `
        -Code "P2F_EVIDENCE_JOIN_TAMPERED"
    Assert-P2FCondition (
        [string]$EvidenceJoin.Compilation.SpecManifestHash -ceq
            [string]$Compilation.SpecManifestHash
    ) "P2F_INPUT_BINDING_MISMATCH" `
        "Source-evidence join carries a different spec compilation."
    $recomputedJoin = Invoke-P2ValidatedSourceEvidenceJoinCore `
        -Compilation $Compilation -EvidenceSet $EvidenceJoin.EvidenceSet `
        -Governance $EvidenceJoin.Governance `
        -AuditValidation $EvidenceJoin.AuditValidation
    Assert-P2FCondition (
        [string]$recomputedJoin.ManifestJson -ceq
            [string]$EvidenceJoin.ManifestJson -and
        [string]$recomputedJoin.ManifestHash -ceq
            [string]$EvidenceJoin.ManifestHash
    ) "P2F_EVIDENCE_JOIN_TAMPERED" `
        "Source-evidence join differs from its validated audit inputs."
    $manifest = [PSCustomObject]$EvidenceJoin.Manifest
    Assert-P2FExactProperties -Value $manifest `
        -Context "Compiled source-evidence join manifest" `
        -Code "P2F_EVIDENCE_JOIN_TAMPERED" -Expected @(
            "artifact_kind", "schema_version", "join_contract_version",
            "source_spec_compiler_contract_version", "scope_id",
            "spec_manifest_sha256", "spec_input_set_sha256",
            "source_audit_seal_sha256", "source_audit_manifest_sha256",
            "evidence_input_set_sha256", "counts", "evidence_records",
            "mechanism_evidence"
        )
    Assert-P2FCondition (
        [string]$manifest.artifact_kind -ceq
            "COMPILED_SOURCE_EVIDENCE_JOIN_MANIFEST" -and
        [long]$manifest.schema_version -eq 1 -and
        [long]$manifest.join_contract_version -eq
            [long]$script:P2EvidenceJoinContractVersion -and
        [long]$manifest.source_spec_compiler_contract_version -eq
            [long]$script:P2CompilerContractVersion
    ) "P2F_EVIDENCE_JOIN_TAMPERED" `
        "Source-evidence join contract version is unsupported."
    Assert-P2FCondition (
        [string]$manifest.scope_id -ceq $ScopeId -and
        [string]$manifest.spec_manifest_sha256 -ceq $SpecManifestHash -and
        [string]$manifest.spec_input_set_sha256 -ceq
            [string]$SpecSet.InputSetHash -and
        [string]$manifest.source_audit_seal_sha256 -ceq $AuditSealHash -and
        [string]$manifest.source_audit_manifest_sha256 -ceq $AuditManifestHash
    ) "P2F_INPUT_BINDING_MISMATCH" `
        "Source-evidence join does not bind the selected spec/audit inputs."

    $evidenceSet = $EvidenceJoin.EvidenceSet
    Assert-P2FRequiredProperties -Value $evidenceSet `
        -Required @("Records", "InputSet", "InputSetHash") `
        -Context "EvidenceSet" -Code "P2F_EVIDENCE_JOIN_TAMPERED"
    $evidenceInputJson = ConvertTo-BattleCanonicalJson -Value $evidenceSet.InputSet
    Assert-P2FCondition (
        (Get-BattleSha256Text $evidenceInputJson) -ceq
            [string]$evidenceSet.InputSetHash -and
        [string]$manifest.evidence_input_set_sha256 -ceq
            [string]$evidenceSet.InputSetHash
    ) "P2F_EVIDENCE_JOIN_TAMPERED" `
        "SourceEvidence input-set hash was substituted."

    $rawById = [Collections.Generic.Dictionary[long, object]]::new()
    foreach ($recordValue in @($evidenceSet.Records)) {
        $record = [PSCustomObject]$recordValue
        Assert-P2FRequiredProperties -Value $record `
            -Required @("Manifest", "Validation") `
            -Context "SourceEvidence record" `
            -Code "P2F_EVIDENCE_JOIN_TAMPERED"
        $validation = Test-P2SourceEvidence -Evidence $record.Manifest
        $id = [long]$validation.PrimaryId
        Assert-P2FCondition (-not $rawById.ContainsKey($id)) `
            "P2F_EVIDENCE_JOIN_TAMPERED" `
            "SourceEvidence ID $id is repeated."
        foreach ($field in @(
            "PrimaryId", "Version", "Status", "AuditId", "SourceKind",
            "Repository", "Category", "Revision", "RelativePath", "Symbol",
            "LineAnchor", "FileHash", "Confidence", "ReviewStatus", "Sha256"
        )) {
            Assert-P2FCondition (
                [string]$record.Validation.$field -ceq [string]$validation.$field
            ) "P2F_EVIDENCE_JOIN_TAMPERED" `
                "SourceEvidence $id validation field '$field' was substituted."
        }
        $rawById.Add($id, [pscustomobject][ordered]@{
            Record = $record
            Validation = $validation
        })
    }

    $outputById = [Collections.Generic.Dictionary[long, object]]::new()
    $activeCount = 0L
    $tombstoneCount = 0L
    $currentCount = 0L
    $blockedCount = 0L
    foreach ($rowValue in @($manifest.evidence_records)) {
        $row = [PSCustomObject]$rowValue
        Assert-P2FExactProperties -Value $row -Context "Evidence join row" `
            -Code "P2F_EVIDENCE_JOIN_TAMPERED" -Expected @(
                "evidence_id", "evidence_version", "status",
                "canonical_authoring_sha256", "source_audit_id",
                "evidence_current", "blocker_codes", "mechanism_ids"
            )
        $id = Get-P2FInteger $row.evidence_id "Evidence row ID" 1 2147483647
        Assert-P2FCondition (
            $rawById.ContainsKey($id) -and -not $outputById.ContainsKey($id)
        ) "P2F_EVIDENCE_JOIN_TAMPERED" `
            "Evidence join row $id is unknown or repeated."
        $raw = $rawById[$id]
        $claimIds = [Collections.Generic.List[long]]::new()
        foreach ($claim in @($raw.Record.Manifest.behavior_claims)) {
            $claimIds.Add([long]$claim.mechanism_id)
        }
        [long[]]$expectedClaimIds = Get-P2FSortedLongArray $claimIds.ToArray()
        Assert-P2FCondition (
            [long]$row.evidence_version -eq [long]$raw.Validation.Version -and
            [string]$row.status -ceq [string]$raw.Validation.Status -and
            [string]$row.canonical_authoring_sha256 -ceq
                [string]$raw.Validation.Sha256 -and
            [string]$row.source_audit_id -ceq [string]$raw.Validation.AuditId -and
            (Test-P2FLongArraysEqual @($row.mechanism_ids) $expectedClaimIds)
        ) "P2F_EVIDENCE_JOIN_TAMPERED" `
            "Evidence join row $id does not match SourceEvidence authoring."
        Assert-P2FArray $row.blocker_codes "Evidence blocker codes" 0 128
        [string[]]$sortedBlockers = Get-P2FSortedStringArray @($row.blocker_codes)
        Assert-P2FCondition (
            (Test-P2FStringArraysEqual @($row.blocker_codes) $sortedBlockers) -and
            ([bool]$row.evidence_current -eq ($sortedBlockers.Count -eq 0))
        ) "P2F_EVIDENCE_JOIN_TAMPERED" `
            "Evidence row $id currentness/blocker order is inconsistent."
        if ([string]$row.status -ceq "ACTIVE") { $activeCount++ }
        else { $tombstoneCount++ }
        if ([bool]$row.evidence_current) { $currentCount++ }
        else { $blockedCount++ }
        $outputById.Add($id, $row)
    }
    Assert-P2FCondition ($outputById.Count -eq $rawById.Count) `
        "P2F_EVIDENCE_JOIN_TAMPERED" `
        "Evidence join omits SourceEvidence rows."

    $mechanismRows = [Collections.Generic.Dictionary[long, object]]::new()
    $linkCount = 0L
    foreach ($rowValue in @($manifest.mechanism_evidence)) {
        $row = [PSCustomObject]$rowValue
        Assert-P2FExactProperties -Value $row `
            -Context "Mechanism evidence row" `
            -Code "P2F_EVIDENCE_JOIN_TAMPERED" -Expected @(
                "mechanism_id", "required_evidence_ids", "joined_evidence_ids",
                "evidence_current", "blocker_codes"
            )
        $mechanismId = Get-P2FInteger $row.mechanism_id `
            "Mechanism evidence ID" 1 2147483647
        Assert-P2FCondition (
            $MechanismRecords.ContainsKey($mechanismId) -and
            -not $mechanismRows.ContainsKey($mechanismId)
        ) "P2F_EVIDENCE_JOIN_TAMPERED" `
            "Mechanism evidence row $mechanismId is unknown or repeated."
        $mechanism = $MechanismRecords[$mechanismId].Manifest
        [long[]]$required = Get-P2FSortedLongArray @($mechanism.evidence_ids)
        Assert-P2FCondition (
            (Test-P2FLongArraysEqual @($row.required_evidence_ids) $required) -and
            (Test-P2FLongArraysEqual @($row.joined_evidence_ids) $required)
        ) "P2F_EVIDENCE_JOIN_TAMPERED" `
            "Mechanism $mechanismId evidence closure was substituted."
        $blockers = [Collections.Generic.List[string]]::new()
        foreach ($evidenceId in $required) {
            Assert-P2FCondition ($outputById.ContainsKey($evidenceId)) `
                "P2F_EVIDENCE_JOIN_TAMPERED" `
                "Mechanism $mechanismId joins unknown evidence $evidenceId."
            foreach ($blocker in @($outputById[$evidenceId].blocker_codes)) {
                $blockers.Add([string]$blocker)
            }
            $linkCount++
        }
        [string[]]$expectedBlockers = Get-P2FSortedStringArray `
            $blockers.ToArray()
        Assert-P2FCondition (
            (Test-P2FStringArraysEqual @($row.blocker_codes) $expectedBlockers) -and
            ([bool]$row.evidence_current -eq ($expectedBlockers.Count -eq 0))
        ) "P2F_EVIDENCE_JOIN_TAMPERED" `
            "Mechanism $mechanismId evidence currentness was substituted."
        $mechanismRows.Add($mechanismId, $row)
    }
    Assert-P2FCondition ($mechanismRows.Count -eq $MechanismRecords.Count) `
        "P2F_EVIDENCE_JOIN_TAMPERED" `
        "Evidence join does not contain the complete mechanism set."

    Assert-P2FExactProperties -Value $manifest.counts `
        -Context "Evidence join counts" -Code "P2F_EVIDENCE_JOIN_TAMPERED" `
        -Expected @(
            "evidence_record_count", "active_evidence_count",
            "tombstone_evidence_count", "current_evidence_count",
            "blocked_evidence_count", "mechanism_count",
            "evidence_link_count"
        )
    $expectedCounts = [ordered]@{
        evidence_record_count = [long]$rawById.Count
        active_evidence_count = $activeCount
        tombstone_evidence_count = $tombstoneCount
        current_evidence_count = $currentCount
        blocked_evidence_count = $blockedCount
        mechanism_count = [long]$MechanismRecords.Count
        evidence_link_count = $linkCount
    }
    foreach ($name in $expectedCounts.Keys) {
        Assert-P2FCondition (
            [long]$manifest.counts.$name -eq [long]$expectedCounts[$name]
        ) "P2F_EVIDENCE_JOIN_TAMPERED" `
            "Evidence join count '$name' is inconsistent."
    }
    return [pscustomobject][ordered]@{
        RawById = $rawById
        OutputById = $outputById
        MechanismRows = $mechanismRows
    }
}

function Assert-P2FFixtureRequirements {
    param(
        [Parameter(Mandatory = $true)][object]$FixtureResult,
        [Parameter(Mandatory = $true)][object]$SpecSet,
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[long, object]]$TestRecords,
        [Parameter(Mandatory = $true)][string]$SpecManifestHash
    )

    Assert-P2FCanonicalResult -Result $FixtureResult `
        -Context "Fixture requirement preflight" `
        -Code "P2F_FIXTURE_MANIFEST_TAMPERED"
    $manifest = [PSCustomObject]$FixtureResult.Manifest
    Assert-P2FExactProperties -Value $manifest `
        -Context "Compiled fixture requirement manifest" `
        -Code "P2F_FIXTURE_MANIFEST_TAMPERED" -Expected @(
            "artifact_kind", "schema_version", "preflight_contract_version",
            "source_spec_compiler_contract_version", "setup_compiler_status",
            "spec_manifest_sha256", "stable_id_manifest_sha256",
            "fixture_requirements"
        )
    Assert-P2FCondition (
        [string]$manifest.artifact_kind -ceq
            "COMPILED_FIXTURE_REQUIREMENT_MANIFEST" -and
        [long]$manifest.schema_version -eq 1 -and
        [long]$manifest.preflight_contract_version -eq
            [long]$script:P2FixturePreflightContractVersion -and
        [long]$manifest.source_spec_compiler_contract_version -eq
            [long]$script:P2CompilerContractVersion -and
        [string]$manifest.setup_compiler_status -ceq
            $script:P2FixtureSetupCompilerStatus -and
        [string]$manifest.spec_manifest_sha256 -ceq $SpecManifestHash -and
        [string]$manifest.stable_id_manifest_sha256 -ceq
            [string]$SpecSet.StableManifestHash
    ) "P2F_INPUT_BINDING_MISMATCH" `
        "Fixture preflight does not bind the selected spec inputs."

    $expected = [Collections.Generic.List[object]]::new()
    [long[]]$testIds = @($TestRecords.Keys)
    [Array]::Sort($testIds)
    foreach ($testId in $testIds) {
        $test = [PSCustomObject]$TestRecords[$testId].Manifest
        if ([string]$test.test_kind -cne "SCENARIO") { continue }
        Assert-P2FCondition ([long]$test.fixture_id -eq $testId) `
            "P2F_FIXTURE_MANIFEST_TAMPERED" `
            "SCENARIO test $testId does not use fixture_id == test_id."
        $expected.Add([pscustomobject][ordered]@{
            fixture_id = $testId
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
    Assert-P2FCondition (
        (ConvertTo-BattleCanonicalJson -Value @($manifest.fixture_requirements)) `
            -ceq (ConvertTo-BattleCanonicalJson -Value $expected.ToArray())
    ) "P2F_FIXTURE_MANIFEST_TAMPERED" `
        "Fixture requirements differ from validated SCENARIO declarations."
    $byId = [Collections.Generic.Dictionary[long, object]]::new()
    foreach ($requirement in @($manifest.fixture_requirements)) {
        $id = [long]$requirement.fixture_id
        Assert-P2FCondition (-not $byId.ContainsKey($id)) `
            "P2F_FIXTURE_MANIFEST_TAMPERED" `
            "Fixture requirement ID $id is repeated."
        $byId.Add($id, $requirement)
    }
    return $byId
}

function Test-P2FSourceReferenceMatchesEvidence {
    param(
        [Parameter(Mandatory = $true)][object]$Reference,
        [Parameter(Mandatory = $true)][object]$EvidenceValidation
    )

    return (
        [string]$Reference.source_repository -ceq
            [string]$EvidenceValidation.Repository -and
        [string]$Reference.source_kind -ceq
            [string]$EvidenceValidation.SourceKind -and
        [string]$Reference.relative_path -ceq
            [string]$EvidenceValidation.RelativePath -and
        [string]$Reference.symbol -ceq
            [string]$EvidenceValidation.Symbol -and
        [string]$Reference.sha256 -ceq
            [string]$EvidenceValidation.FileHash
    )
}

function Assert-P2FReleaseContractRoot {
    param(
        [Parameter(Mandatory = $true)][object]$SpecSet,
        [AllowEmptyString()][string]$GodotContractRoot = ""
    )

    foreach ($record in @($SpecSet.MechanismSpecs)) {
        if ([string]$record.Manifest.target_maturity -cne "RELEASED") {
            continue
        }
        Assert-P2FCondition (
            -not [string]::IsNullOrWhiteSpace($GodotContractRoot)
        ) "P2F_GODOT_CONTRACT_ROOT_REQUIRED" (
            "A nonempty release-target set requires GodotContractRoot so " +
            "contract document bytes can be verified."
        )
        return $true
    }
    return $true
}

# Internal projection seam. The public CLI constructs every argument from one
# captured repository view and does not expose object injection. Focused tests
# may provide trusted synthetic upstream results to isolate closure semantics.
function Invoke-P2ValidatedReleaseReferenceCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Compilation,
        [Parameter(Mandatory = $true)][object]$EvidenceJoin,
        [Parameter(Mandatory = $true)][object]$FixtureResult,
        [Parameter(Mandatory = $true)][object]$WorkItemSet,
        [Parameter(Mandatory = $true)][string]$ScopeId,
        [Parameter(Mandatory = $true)][string]$AuditSealHash,
        [Parameter(Mandatory = $true)][string]$AuditManifestHash
    )

    foreach ($definition in @(
        [pscustomobject]@{Name = "AuditSealHash"; Value = $AuditSealHash},
        [pscustomobject]@{Name = "AuditManifestHash"; Value = $AuditManifestHash}
    )) {
        $null = Get-P2FString ([string]$definition.Value) `
            ([string]$definition.Name) '^[0-9a-f]{64}$' 64
    }
    $null = Get-P2FString $ScopeId "ScopeId" '^[A-Z0-9_]+$' 128

    $specIndexes = Assert-P2FCompilation -Compilation $Compilation
    $SpecSet = $Compilation.SpecSet
    $SpecManifestHash = [string]$Compilation.SpecManifestHash
    $mechanismRecords = $specIndexes.MechanismSpecs
    $testRecords = $specIndexes.TestEntries
    $workItems = Assert-P2FWorkItemSet -WorkItemSet $WorkItemSet
    $evidence = Assert-P2FEvidenceJoin -EvidenceJoin $EvidenceJoin `
        -Compilation $Compilation `
        -SpecSet $SpecSet -MechanismRecords $mechanismRecords `
        -SpecManifestHash $SpecManifestHash -ScopeId $ScopeId `
        -AuditSealHash $AuditSealHash -AuditManifestHash $AuditManifestHash
    $fixtures = Assert-P2FFixtureRequirements -FixtureResult $FixtureResult `
        -SpecSet $SpecSet -TestRecords $testRecords `
        -SpecManifestHash $SpecManifestHash

    $workItemsByMechanism = [Collections.Generic.Dictionary[long, object]]::new()
    foreach ($workItemId in $workItems.Keys) {
        $record = $workItems[$workItemId]
        foreach ($mechanismIdValue in @($record.Manifest.mechanism_ids)) {
            $mechanismId = [long]$mechanismIdValue
            Assert-P2FCondition ($mechanismRecords.ContainsKey($mechanismId)) `
                "P2F_WORK_ITEM_MECHANISM_UNKNOWN" `
                "Work item '$workItemId' references unknown mechanism $mechanismId."
            if (-not $workItemsByMechanism.ContainsKey($mechanismId)) {
                $workItemsByMechanism.Add(
                    $mechanismId,
                    [Collections.Generic.List[object]]::new()
                )
            }
            $workItemsByMechanism[$mechanismId].Add($record)
        }
        foreach ($fixtureIdValue in @($record.Manifest.fixture_ids)) {
            $fixtureId = [long]$fixtureIdValue
            Assert-P2FCondition ($fixtures.ContainsKey($fixtureId)) `
                "P2F_WORK_ITEM_FIXTURE_UNKNOWN" `
                "Work item '$workItemId' references unknown SCENARIO fixture $fixtureId."
        }
    }
    [long[]]$mechanismIds = @($mechanismRecords.Keys)
    [Array]::Sort($mechanismIds)
    $releaseRows = [Collections.Generic.List[object]]::new()
    $referenceTripleCount = 0L
    $blockedMechanismCount = 0L
    $contractWorkItemLinkCount = 0L
    $contractRefLinkCount = 0L
    $evidenceLinkCount = 0L
    $fixtureLinkCount = 0L
    foreach ($mechanismId in $mechanismIds) {
        $mechanism = [PSCustomObject]$mechanismRecords[$mechanismId].Manifest
        if ([string]$mechanism.target_maturity -cne "RELEASED") { continue }

        [object[]]$boundWorkItems = [Array]::CreateInstance([object], 0)
        if ($workItemsByMechanism.ContainsKey($mechanismId)) {
            $boundWorkItems = [object[]]$workItemsByMechanism[
                $mechanismId
            ].ToArray()
        }
        $contractWorkItemIds = [Collections.Generic.List[string]]::new()
        $contractHashes = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal
        )
        $hasReviewedContract = @($boundWorkItems).Count -gt 0
        foreach ($recordValue in @($boundWorkItems)) {
            $record = [PSCustomObject]$recordValue
            $contractWorkItemIds.Add([string]$record.Validation.WorkItemId)
            foreach ($hash in @($record.Validation.ContractRefHashes)) {
                $null = $contractHashes.Add([string]$hash)
            }
            if ([string]$record.Validation.CompletionStatus -cnotin @(
                "VERIFIED", "RELEASED"
            )) {
                $hasReviewedContract = $false
            }
        }
        [string[]]$sortedWorkItemIds = Get-P2FSortedStringArray `
            $contractWorkItemIds.ToArray()
        [string[]]$sortedContractHashes = Get-P2FSortedStringArray `
            @($contractHashes)

        $matchedEvidenceIds = [Collections.Generic.List[long]]::new()
        $allMatchedEvidenceCurrent = $true
        $mechanismEvidence = $evidence.MechanismRows[$mechanismId]
        foreach ($evidenceIdValue in @($mechanismEvidence.joined_evidence_ids)) {
            $evidenceId = [long]$evidenceIdValue
            $rawEvidence = $evidence.RawById[$evidenceId]
            $matched = $false
            foreach ($recordValue in $boundWorkItems) {
                $workItem = [PSCustomObject]$recordValue.Manifest
                foreach ($reference in @(
                    @($workItem.source_evidence_refs) +
                    @($workItem.source_test_evidence_refs)
                )) {
                    if (Test-P2FSourceReferenceMatchesEvidence `
                        -Reference $reference `
                        -EvidenceValidation $rawEvidence.Validation) {
                        $matched = $true
                        break
                    }
                }
                if ($matched) { break }
            }
            if ($matched) {
                $matchedEvidenceIds.Add($evidenceId)
                if (-not [bool]$evidence.OutputById[$evidenceId].evidence_current) {
                    $allMatchedEvidenceCurrent = $false
                }
            }
        }
        [long[]]$sortedEvidenceIds = Get-P2FSortedLongArray `
            $matchedEvidenceIds.ToArray()
        [long[]]$requiredEvidenceIds = Get-P2FSortedLongArray `
            @($mechanismEvidence.required_evidence_ids)

        $matchedFixtureIds = [Collections.Generic.List[long]]::new()
        foreach ($fixtureId in $fixtures.Keys) {
            $requirement = $fixtures[$fixtureId]
            $coversMechanism = $false
            foreach ($target in @($requirement.coverage_targets)) {
                if ([long]$target.mechanism_id -eq $mechanismId) {
                    $coversMechanism = $true
                    break
                }
            }
            if (-not $coversMechanism) { continue }
            foreach ($recordValue in $boundWorkItems) {
                if (Test-P2FLongArrayContains `
                    $recordValue.Manifest.fixture_ids ([long]$fixtureId)) {
                    $matchedFixtureIds.Add([long]$fixtureId)
                    break
                }
            }
        }
        [long[]]$sortedFixtureIds = Get-P2FSortedLongArray `
            $matchedFixtureIds.ToArray()

        $hasContract = $sortedContractHashes.Count -gt 0
        $hasAnyEvidence = $sortedEvidenceIds.Count -gt 0
        $hasEvidence = (
            $requiredEvidenceIds.Count -gt 0 -and
            (Test-P2FLongArraysEqual $sortedEvidenceIds $requiredEvidenceIds)
        )
        $hasFixture = $sortedFixtureIds.Count -gt 0
        $hasTriple = $hasContract -and $hasEvidence -and $hasFixture
        $sourceCurrent = (
            $hasEvidence -and $allMatchedEvidenceCurrent -and
            [bool]$mechanismEvidence.evidence_current
        )
        $blockers = [Collections.Generic.List[string]]::new()
        if (-not $hasContract) {
            $blockers.Add("GODOT_CONTRACT_REF_MISSING")
        }
        elseif (-not $hasReviewedContract) {
            $blockers.Add("GODOT_CONTRACT_REVIEW_INCOMPLETE")
        }
        if (-not $hasEvidence) {
            if ($hasAnyEvidence) {
                $blockers.Add("EXTERNAL_SOURCE_EVIDENCE_REF_INCOMPLETE")
            }
            else {
                $blockers.Add("EXTERNAL_SOURCE_EVIDENCE_REF_MISSING")
            }
        }
        elseif (-not $sourceCurrent) {
            $blockers.Add("EXTERNAL_SOURCE_EVIDENCE_NONCURRENT")
        }
        if (-not $hasFixture) {
            $blockers.Add("SCENARIO_FIXTURE_REF_MISSING")
        }
        else {
            $blockers.Add("SETUP_COMPILER_UNAVAILABLE_P7")
        }
        [string[]]$sortedBlockers = Get-P2FSortedStringArray `
            $blockers.ToArray()
        if ($hasTriple) { $referenceTripleCount++ }
        if ($sortedBlockers.Count -gt 0) { $blockedMechanismCount++ }
        $contractWorkItemLinkCount += $sortedWorkItemIds.Count
        $contractRefLinkCount += $sortedContractHashes.Count
        $evidenceLinkCount += $sortedEvidenceIds.Count
        $fixtureLinkCount += $sortedFixtureIds.Count
        $releaseRows.Add([pscustomobject][ordered]@{
            mechanism_id = $mechanismId
            target_maturity = "RELEASED"
            contract_work_item_ids = $sortedWorkItemIds
            godot_contract_ref_hashes = $sortedContractHashes
            external_evidence_ids = $sortedEvidenceIds
            scenario_fixture_ids = $sortedFixtureIds
            godot_contract_ref_present = $hasContract
            external_source_evidence_ref_present = $hasEvidence
            scenario_fixture_ref_present = $hasFixture
            reference_triple_present = $hasTriple
            source_evidence_current = $sourceCurrent
            blocker_codes = $sortedBlockers
        })
    }

    $manifest = [pscustomobject][ordered]@{
        artifact_kind = "COMPILED_RELEASE_MECHANISM_REFERENCE_MANIFEST"
        schema_version = $script:P2FManifestSchemaVersion
        closure_contract_version = $script:P2FClosureContractVersion
        source_spec_compiler_contract_version = `
            $script:P2CompilerContractVersion
        source_evidence_join_contract_version = `
            $script:P2EvidenceJoinContractVersion
        fixture_preflight_contract_version = `
            $script:P2FixturePreflightContractVersion
        validation_scope = $script:P2FValidationScope
        setup_compiler_status = $script:P2FixtureSetupCompilerStatus
        scope_id = $ScopeId
        spec_manifest_sha256 = $SpecManifestHash
        stable_id_manifest_sha256 = [string]$SpecSet.StableManifestHash
        spec_input_set_sha256 = [string]$SpecSet.InputSetHash
        source_evidence_join_manifest_sha256 = `
            [string]$EvidenceJoin.ManifestHash
        fixture_requirement_manifest_sha256 = `
            [string]$FixtureResult.ManifestHash
        work_item_input_set_sha256 = [string]$WorkItemSet.InputSetHash
        counts = [pscustomobject][ordered]@{
            release_mechanism_count = [long]$releaseRows.Count
            reference_triple_count = $referenceTripleCount
            blocked_mechanism_count = $blockedMechanismCount
            contract_work_item_link_count = $contractWorkItemLinkCount
            godot_contract_ref_link_count = $contractRefLinkCount
            external_evidence_ref_link_count = $evidenceLinkCount
            scenario_fixture_ref_link_count = $fixtureLinkCount
        }
        release_mechanisms = $releaseRows.ToArray()
    }
    $manifestJson = ConvertTo-BattleCanonicalJson -Value $manifest
    return [pscustomobject][ordered]@{
        Compilation = $Compilation
        SpecSet = $SpecSet
        EvidenceJoin = $EvidenceJoin
        FixtureResult = $FixtureResult
        WorkItemSet = $WorkItemSet
        Manifest = $manifest
        ManifestJson = $manifestJson
        ManifestBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes(
            $manifestJson
        )
        ManifestHash = Get-BattleSha256Text $manifestJson
        ReleaseMechanismCount = [long]$releaseRows.Count
        ReferenceTripleCount = $referenceTripleCount
        BlockedMechanismCount = $blockedMechanismCount
    }
}

function Assert-P2FReleaseReferenceClosure {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Result)

    Assert-P2FRequiredProperties -Value $Result `
        -Required @(
            "ReleaseMechanismCount", "ReferenceTripleCount", "Manifest"
        ) -Context "Release-reference result" `
        -Code "P2F_RELEASE_REFERENCE_CLOSURE_FAILED"
    if ([long]$Result.ReferenceTripleCount -eq
        [long]$Result.ReleaseMechanismCount) {
        return $Result
    }
    $missingIds = [Collections.Generic.List[long]]::new()
    foreach ($row in @($Result.Manifest.release_mechanisms)) {
        if (-not [bool]$row.reference_triple_present) {
            $missingIds.Add([long]$row.mechanism_id)
        }
    }
    Throw-P2FError "P2F_RELEASE_REFERENCE_CLOSURE_FAILED" (
        "Release-target mechanisms lack a complete contract/source/fixture " +
        "reference triple: [$($missingIds.ToArray() -join ',')]."
    )
}

function Invoke-P2ReleaseReferenceValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet("Repository", "Worktree", "Staged")]
        [string]$Mode = "Repository",
        [string]$SourceAuditManifestPath = "",
        [string]$GodotContractRoot = ""
    )

    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $view = New-P2RepositoryView -ProjectRoot $root -Mode $Mode `
        -CandidatePrefixes @(
            "new-game-project/battle/specs",
            $script:P2FWorkItemPrefix,
            $script:P2EvidenceSealRelativePath,
            $script:P2EvidencePolicyRelativePath,
            $script:P2EvidenceBaselineRelativePath,
            $script:P2FixtureScenarioPrefix
        )
    $fixturePaths = @(Get-P2RepositoryViewPaths -View $view `
        -Prefix $script:P2FixtureScenarioPrefix)
    Assert-P2FCondition ($fixturePaths.Count -eq 0) `
        "P2D_SETUP_COMPILER_UNAVAILABLE_P7" (
            "Cannot compile $($fixturePaths.Count) scenario fixture payload " +
            "path(s) before the production P7 setup compiler exists."
        )

    $specSet = Read-P2ValidatedSpecSet -View $view
    $null = Assert-P2FReleaseContractRoot -SpecSet $specSet `
        -GodotContractRoot $GodotContractRoot
    $compilation = Invoke-P2ValidatedSpecCompilerCore -SpecSet $specSet `
        -InspectUnmetMaturityTargets
    $fixtureResult = Invoke-P2ValidatedFixturePreflightCore `
        -Compilation $compilation
    $evidenceSet = Read-P2ValidatedEvidenceSet -View $view
    $governance = Read-P2EvidenceGovernance -View $view
    $auditValidation = $null
    if (@($evidenceSet.Records).Count -gt 0) {
        $auditBytes = Read-P2EvidenceAuditBytes -ProjectRoot $root `
            -AuditManifestPath $SourceAuditManifestPath
        $auditHash = Get-P2EvidenceSha256Bytes $auditBytes
        Assert-P2FCondition (
            $auditHash -ceq
                [string]$governance.Seal.source_audit_manifest_sha256
        ) "P2E_AUDIT_HASH" `
            "The local source audit manifest does not match its tracked seal."
        $auditManifest = ConvertFrom-P2EvidenceSealedAuditBytes `
            -Bytes $auditBytes -Context $script:P2EvidenceAuditRelativePath
        $auditValidation = Test-P2EvidenceAuditManifest `
            -Manifest $auditManifest -Governance $governance `
            -SealedBytesVerified
    }
    $evidenceJoin = Invoke-P2ValidatedSourceEvidenceJoinCore `
        -Compilation $compilation -EvidenceSet $evidenceSet `
        -Governance $governance -AuditValidation $auditValidation
    $workItemSet = Read-P2FValidatedWorkItemSet -View $view `
        -GodotContractRoot $GodotContractRoot
    $result = Invoke-P2ValidatedReleaseReferenceCore `
        -Compilation $compilation `
        -EvidenceJoin $evidenceJoin -FixtureResult $fixtureResult `
        -WorkItemSet $workItemSet -ScopeId ([string]$governance.Seal.scope_id) `
        -AuditSealHash ([string]$governance.SealHash) `
        -AuditManifestHash (
            [string]$governance.Seal.source_audit_manifest_sha256
        )
    $null = Assert-P2FReleaseReferenceClosure -Result $result
    return [pscustomobject][ordered]@{
        Manifest = $result.Manifest
        ManifestJson = [string]$result.ManifestJson
        ManifestBytes = [byte[]]$result.ManifestBytes.Clone()
        ManifestHash = [string]$result.ManifestHash
        ReleaseMechanismCount = [long]$result.ReleaseMechanismCount
        ReferenceTripleCount = [long]$result.ReferenceTripleCount
        BlockedMechanismCount = [long]$result.BlockedMechanismCount
    }
}

function Validate-P2ReleaseMechanismReferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet("Repository", "Worktree", "Staged")]
        [string]$Mode = "Repository",
        [string]$SourceAuditManifestPath = "",
        [string]$GodotContractRoot = ""
    )

    return Invoke-P2ReleaseReferenceValidation -ProjectRoot $ProjectRoot `
        -Mode $Mode -SourceAuditManifestPath $SourceAuditManifestPath `
        -GodotContractRoot $GodotContractRoot
}
