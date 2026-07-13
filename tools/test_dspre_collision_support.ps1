[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "dspre_collision_support.ps1")

function New-SyntheticLandData {
    param([switch]$ZeroNormalY, [switch]$InvalidPlateIndex)

    $attributes = New-Object byte[] 2048
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]0x8015), 0, $attributes, 0, 2)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]0x0034), 0, $attributes, 2, 2)

    $bdhcStream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($bdhcStream)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes("BDHC"))
        foreach ($count in @([uint16]2, [uint16]1, [uint16]2, [uint16]2, [uint16]1, [uint16]2)) {
            $writer.Write($count)
        }
        foreach ($value in @(-1048576, -1048576, 1048576, 1048576)) {
            $writer.Write([int]$value)
        }
        $writer.Write([int]0)
        $normalY = if ($ZeroNormalY) { 0 } else { 4096 }
        $writer.Write([int]$normalY)
        $writer.Write([int]0)
        $writer.Write([int]-65536)
        $writer.Write([int]-131072)
        foreach ($constantIndex in 0, 1) {
            $writer.Write([uint16]0)
            $secondPointIndex = if ($InvalidPlateIndex -and $constantIndex -eq 1) { 2 } else { 1 }
            $writer.Write([uint16]$secondPointIndex)
            $writer.Write([uint16]0)
            $writer.Write([uint16]$constantIndex)
        }
        $writer.Write([int]1048576)
        $writer.Write([uint16]2)
        $writer.Write([uint16]0)
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Flush()
        $bdhc = $bdhcStream.ToArray()
    }
    finally {
        $writer.Dispose()
        $bdhcStream.Dispose()
    }

    $bytes = New-Object byte[] (16 + $attributes.Length + $bdhc.Length)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]$attributes.Length), 0, $bytes, 0, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]0), 0, $bytes, 4, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]0), 0, $bytes, 8, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]$bdhc.Length), 0, $bytes, 12, 4)
    [Buffer]::BlockCopy($attributes, 0, $bytes, 16, $attributes.Length)
    [Buffer]::BlockCopy($bdhc, 0, $bytes, 16 + $attributes.Length, $bdhc.Length)
    return $bytes
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Label)

    try {
        & $Action
    }
    catch {
        return
    }
    throw "$Label did not reject invalid data."
}

$asset = ConvertFrom-DspreMapCollision -Bytes (New-SyntheticLandData) -MapId 7
if (
    [string]$asset.key -ne "map_0007_collision" -or
    [int]$asset.terrain_attributes.byte_length -ne 2048 -or
    [int]$asset.bdhc.byte_length -ne 80 -or
    [int]$asset.bdhc.counts.plates -ne 2
) {
    throw "Synthetic collision data produced unexpected metadata."
}
$packedAttributes = [Convert]::FromBase64String([string]$asset.terrain_attributes.data_base64)
if (
    [BitConverter]::ToUInt16($packedAttributes, 0) -ne 0x8015 -or
    [BitConverter]::ToUInt16($packedAttributes, 2) -ne 0x0034
) {
    throw "Terrain attributes did not retain collision and behavior bits."
}
$packedBdhc = [Convert]::FromBase64String([string]$asset.bdhc.data_base64)
if ([BitConverter]::ToInt32($packedBdhc, 16) -ne -1048576) {
    throw "Signed FX32 coordinates were not preserved."
}

$manifest = [pscustomobject]@{
    schema_version = 2
    summary = [pscustomobject]@{
        collision_assets = 1
        terrain_attribute_tiles = 1024
        bdhc_assets = 1
    }
    collision_format = [pscustomobject]@{
        schema_version = 1
        terrain_width = 32
        terrain_height = 32
        terrain_order = "row_major"
        collision_mask = 0x8000
        behavior_mask = 0x00FF
        fx32_fraction_bits = 12
        source_units_per_tile = 16
        source_units_per_world_unit = 16
        bdhc_origin = "map_center"
        map_prop_collision = "cell_terrain_attributes"
    }
    collision_assets = @($asset)
    cells = @([pscustomobject]@{
        x = 0
        y = 0
        map_id = 7
        collision_asset_key = "map_0007_collision"
        buildings = @([pscustomobject]@{
            model_id = 1
            scale_fx32 = [pscustomobject]@{ x = 4096; y = 4096; z = 4096 }
            collision = [pscustomobject]@{ mode = "cell_terrain_attributes" }
        })
    })
}
$stats = Assert-DspreCollisionManifest -Manifest $manifest -ExpectedManifestSchema 2
if ([int]$stats.collision_assets -ne 1 -or [int]$stats.referenced_cells -ne 1) {
    throw "Synthetic collision manifest returned incorrect coverage."
}

Assert-Throws { ConvertFrom-DspreMapCollision -Bytes (New-SyntheticLandData -InvalidPlateIndex) -MapId 7 } "BDHC plate index"
Assert-Throws { ConvertFrom-DspreMapCollision -Bytes (New-SyntheticLandData -ZeroNormalY) -MapId 7 } "BDHC zero normal Y"
$truncated = New-SyntheticLandData
[Array]::Resize([ref]$truncated, $truncated.Length - 1)
Assert-Throws { ConvertFrom-DspreMapCollision -Bytes $truncated -MapId 7 } "Truncated land data"

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$fingerprintRoot = [IO.Path]::GetFullPath(
    (Join-Path $tempBase ("maizang_fingerprint_{0}" -f [Guid]::NewGuid().ToString("N")))
)
$junctionPath = $null
if (-not ($fingerprintRoot + '\').StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Synthetic fingerprint root escaped the system temporary directory."
}
try {
    $sourceA = Join-Path $fingerprintRoot "source_a"
    $sourceB = Join-Path $fingerprintRoot "source_b"
    $null = [IO.Directory]::CreateDirectory((Join-Path $sourceA "nested"))
    $null = [IO.Directory]::CreateDirectory((Join-Path $sourceB "nested"))
    [IO.File]::WriteAllBytes((Join-Path $sourceA "alpha.bin"), [byte[]]@(1, 2, 3, 4))
    [IO.File]::WriteAllBytes((Join-Path $sourceA "nested\beta.bin"), [byte[]]@(5, 6, 7))
    [IO.File]::WriteAllBytes((Join-Path $sourceB "nested\beta.bin"), [byte[]]@(5, 6, 7))
    [IO.File]::WriteAllBytes((Join-Path $sourceB "alpha.bin"), [byte[]]@(1, 2, 3, 4))

    $sourceHashA = Get-DspreContentFingerprint -RootPath $sourceA
    $sourceHashB = Get-DspreContentFingerprint -RootPath $sourceB
    if ($sourceHashA -ne $sourceHashB) {
        throw "Identical DSPRE trees under different absolute roots produced different fingerprints."
    }
    [IO.File]::WriteAllBytes((Join-Path $sourceB "alpha.bin"), [byte[]]@(1, 2, 3, 5))
    if ((Get-DspreContentFingerprint -RootPath $sourceB) -eq $sourceHashA) {
        throw "A same-length DSPRE content change did not alter the fingerprint."
    }
    [IO.File]::WriteAllBytes((Join-Path $sourceB "alpha.bin"), [byte[]]@(1, 2, 3, 4))
    Move-Item -LiteralPath (Join-Path $sourceB "nested\beta.bin") -Destination (Join-Path $sourceB "renamed.bin")
    if ((Get-DspreContentFingerprint -RootPath $sourceB) -eq $sourceHashA) {
        throw "A DSPRE relative-path change did not alter the fingerprint."
    }

    $toolA = Join-Path $fingerprintRoot "tool_a.bin"
    $toolB = Join-Path $fingerprintRoot "tool_b.bin"
    [IO.File]::WriteAllBytes($toolA, [byte[]]@(9, 8, 7))
    [IO.File]::WriteAllBytes($toolB, [byte[]]@(9, 8, 7))
    if ((Get-DspreToolFileFingerprint $toolA) -ne (Get-DspreToolFileFingerprint $toolB)) {
        throw "Tool fingerprints unexpectedly included the absolute file path."
    }
    [IO.File]::WriteAllBytes($toolB, [byte[]]@(9, 8, 6))
    if ((Get-DspreToolFileFingerprint $toolA) -eq (Get-DspreToolFileFingerprint $toolB)) {
        throw "A tool content change did not alter its fingerprint."
    }

    $resolutionA = Join-Path $fingerprintRoot "resolution_a.json"
    $resolutionB = Join-Path $fingerprintRoot "resolution_b.json"
    $resolutionTemplate = [pscustomobject][ordered]@{
        schema_version = 1
        generated_utc = "2000-01-01T00:00:00Z"
        source = [pscustomobject][ordered]@{
            dspre_contents = "C:\source_a"
            header_table_offset = "0xE56F0"
        }
        summary = [pscustomobject][ordered]@{ matrices = 1; ready_variants = 1 }
        variants = @([pscustomobject][ordered]@{
            matrix_id = 0
            variant = "matrix_0000"
            area_data_id = $null
            resolution = "per_cell_header"
        })
        overrides = @()
        unresolved = @()
    }
    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($resolutionA, ($resolutionTemplate | ConvertTo-Json -Depth 10), $utf8NoBom)
    $resolutionTemplate.generated_utc = "2030-01-01T00:00:00Z"
    $resolutionTemplate.source.dspre_contents = "D:\relocated\source_b"
    [IO.File]::WriteAllText($resolutionB, ($resolutionTemplate | ConvertTo-Json -Depth 10), $utf8NoBom)
    $resolutionHash = Get-DspreAreaResolutionFingerprint $resolutionA
    if ($resolutionHash -ne (Get-DspreAreaResolutionFingerprint $resolutionB)) {
        throw "Area resolution fingerprint included volatile time or absolute source paths."
    }
    $resolutionTemplate.variants[0].resolution = "linked_map_header"
    [IO.File]::WriteAllText($resolutionB, ($resolutionTemplate | ConvertTo-Json -Depth 10), $utf8NoBom)
    if ($resolutionHash -eq (Get-DspreAreaResolutionFingerprint $resolutionB)) {
        throw "An Area resolution semantic change did not alter its fingerprint."
    }

    $fingerprints = [ordered]@{
        source = "1" * 64
        exporter = "2" * 64
        support = "3" * 64
        apicula = "4" * 64
        area = "5" * 64
        manifest = "6" * 64
    }
    $rawMarker = [pscustomobject][ordered]@{
        schema_version = 2
        export_contract_version = 3
        matrix_id = 1
        variant = "matrix_0001_area_0007"
        area_data_id = 7
        manifest_sha256 = $fingerprints.manifest
        dspre_source_sha256 = $fingerprints.source
        exporter_sha256 = $fingerprints.exporter
        support_tool_sha256 = $fingerprints.support
        apicula_sha256 = $fingerprints.apicula
        area_resolution_sha256 = $fingerprints.area
        occupied_cells = 12
        collision_assets = 3
        files = @([pscustomobject][ordered]@{
            relative_path = "manifest.json"
            byte_length = 1
            sha256 = "7" * 64
        })
    }
    $markerArguments = @{
        Marker = $rawMarker
        ExpectedMatrixId = 1
        ExpectedVariant = "matrix_0001_area_0007"
        ExpectedAreaDataId = 7
        ExpectedDspreSourceSha256 = $fingerprints.source
        ExpectedExporterSha256 = $fingerprints.exporter
        ExpectedSupportToolSha256 = $fingerprints.support
        ExpectedApiculaSha256 = $fingerprints.apicula
        ExpectedAreaResolutionSha256 = $fingerprints.area
        ExpectedManifestSha256 = $fingerprints.manifest
        ExpectedOccupiedCells = 12
        ExpectedCollisionAssets = 3
    }
    if (-not (Assert-DspreRawExportMarker @markerArguments)) {
        throw "A current raw export marker was not accepted."
    }
    $directMarker = $rawMarker | ConvertTo-Json -Depth 4 | ConvertFrom-Json
    $directMarker.area_resolution_sha256 = $null
    $directArguments = @{} + $markerArguments
    $directArguments.Marker = $directMarker
    $directArguments.ExpectedAreaResolutionSha256 = ""
    if (-not (Assert-DspreRawExportMarker @directArguments)) {
        throw "A direct raw marker without AreaData resolution was not accepted."
    }
    foreach ($invalidMarker in @(
        [pscustomobject]@{ Property = "schema_version"; Value = 1; Label = "raw marker schema" },
        [pscustomobject]@{ Property = "export_contract_version"; Value = 2; Label = "raw export contract" },
        [pscustomobject]@{ Property = "matrix_id"; Value = 2; Label = "raw marker matrix" },
        [pscustomobject]@{ Property = "variant"; Value = "matrix_0001"; Label = "raw marker variant" },
        [pscustomobject]@{ Property = "area_data_id"; Value = 8; Label = "raw marker AreaData" },
        [pscustomobject]@{ Property = "dspre_source_sha256"; Value = "a" * 64; Label = "raw marker source" },
        [pscustomobject]@{ Property = "exporter_sha256"; Value = "b" * 64; Label = "raw marker exporter" },
        [pscustomobject]@{ Property = "support_tool_sha256"; Value = "c" * 64; Label = "raw marker support" },
        [pscustomobject]@{ Property = "apicula_sha256"; Value = "d" * 64; Label = "raw marker apicula" },
        [pscustomobject]@{ Property = "area_resolution_sha256"; Value = "e" * 64; Label = "raw marker AreaData resolution" },
        [pscustomobject]@{ Property = "files"; Value = @(); Label = "raw marker file records" }
    )) {
        $candidate = $rawMarker | ConvertTo-Json -Depth 4 | ConvertFrom-Json
        $candidate.($invalidMarker.Property) = $invalidMarker.Value
        $invalidArguments = @{} + $markerArguments
        $invalidArguments.Marker = $candidate
        Assert-Throws { Assert-DspreRawExportMarker @invalidArguments } $invalidMarker.Label
    }

    $partialRawRoot = Join-Path $fingerprintRoot "partial_raw"
    $unrequestedRoot = Join-Path $partialRawRoot "matrix_0001_area_0007"
    $null = [IO.Directory]::CreateDirectory($unrequestedRoot)
    $partialManifest = $manifest | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $partialManifest | Add-Member -NotePropertyName matrix -NotePropertyValue ([pscustomobject]@{
        id = 1
        variant = "matrix_0001_area_0007"
        area_data_id = 7
    })
    $partialManifestPath = Join-Path $unrequestedRoot "manifest.json"
    $partialSummaryPath = Join-Path $unrequestedRoot "summary.json"
    $partialGlbPath = Join-Path $unrequestedRoot "terrain.glb"
    $markerPath = Join-Path $unrequestedRoot ".export-complete.json"
    [IO.File]::WriteAllText(
        $partialManifestPath,
        ($partialManifest | ConvertTo-Json -Depth 20),
        $utf8NoBom
    )
    $partialSummary = [pscustomobject][ordered]@{
        matrix_id = 1
        variant = "matrix_0001_area_0007"
        area_data_id = 7
        occupied_cells = @($partialManifest.cells).Count
        collision_assets = @($partialManifest.collision_assets).Count
        failed = 0
    }
    [IO.File]::WriteAllText(
        $partialSummaryPath,
        ($partialSummary | ConvertTo-Json -Depth 4),
        $utf8NoBom
    )
    $partialGlbBytes = New-Object byte[] 12
    [Buffer]::BlockCopy([Text.Encoding]::ASCII.GetBytes("glTF"), 0, $partialGlbBytes, 0, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]2), 0, $partialGlbBytes, 4, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]12), 0, $partialGlbBytes, 8, 4)
    [IO.File]::WriteAllBytes($partialGlbPath, $partialGlbBytes)
    $partialMarker = $rawMarker | ConvertTo-Json -Depth 4 | ConvertFrom-Json
    $partialMarker.manifest_sha256 = (
        Get-FileHash -LiteralPath $partialManifestPath -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    $partialMarker.occupied_cells = @($partialManifest.cells).Count
    $partialMarker.collision_assets = @($partialManifest.collision_assets).Count
    $partialMarker.files = @(Get-DspreStageFileRecords `
        -RootPath $unrequestedRoot `
        -ExcludedRelativePaths @(".export-complete.json") `
        -Label "Synthetic raw destination")
    [IO.File]::WriteAllText(
        $markerPath,
        ($partialMarker | ConvertTo-Json -Depth 6),
        $utf8NoBom
    )
    $variants = @(
        [pscustomobject]@{ matrix_id = 0; variant = "matrix_0000"; area_data_id = $null },
        [pscustomobject]@{ matrix_id = 1; variant = "matrix_0001_area_0007"; area_data_id = 7 }
    )
    $partialArguments = @{
        Variants = $variants
        RequestedMatrixIds = @(0)
        RawRoot = $partialRawRoot
        ExpectedDspreSourceSha256 = $fingerprints.source
        ExpectedExporterSha256 = $fingerprints.exporter
        ExpectedSupportToolSha256 = $fingerprints.support
        ExpectedApiculaSha256 = $fingerprints.apicula
        ExpectedAreaResolutionSha256 = $fingerprints.area
    }
    if (-not (Assert-DspreUnrequestedRawMarkersCurrent @partialArguments)) {
        throw "Current unrequested raw markers did not pass partial-export preflight."
    }
    $mutatedGlbBytes = [byte[]]$partialGlbBytes.Clone()
    $mutatedGlbBytes[0] = [byte][int][char]'G'
    [IO.File]::WriteAllBytes($partialGlbPath, $mutatedGlbBytes)
    Assert-Throws {
        Assert-DspreUnrequestedRawMarkersCurrent @partialArguments
    } "same-length unrequested raw content replacement"
    [IO.File]::WriteAllBytes($partialGlbPath, $partialGlbBytes)
    $replacementGlbPath = Join-Path $unrequestedRoot "replacement.glb"
    Move-Item -LiteralPath $partialGlbPath -Destination $replacementGlbPath
    Assert-Throws {
        Assert-DspreUnrequestedRawMarkersCurrent @partialArguments
    } "same-count unrequested raw path replacement"
    Move-Item -LiteralPath $replacementGlbPath -Destination $partialGlbPath
    if (-not (Assert-DspreUnrequestedRawMarkersCurrent @partialArguments)) {
        throw "Restored unrequested raw files did not pass partial-export preflight."
    }
    $publishedCatalog = Join-Path $fingerprintRoot "published_catalog.json"
    [IO.File]::WriteAllText($publishedCatalog, "catalog-sentinel", $utf8NoBom)
    $partialSummary.failed = 1
    [IO.File]::WriteAllText(
        $partialSummaryPath,
        ($partialSummary | ConvertTo-Json -Depth 4),
        $utf8NoBom
    )
    Assert-Throws {
        Assert-DspreUnrequestedRawMarkersCurrent @partialArguments
    } "failed unrequested raw summary"
    if ([IO.File]::ReadAllText($publishedCatalog, [Text.Encoding]::UTF8) -ne "catalog-sentinel") {
        throw "Partial-export raw preflight removed a published catalog before rejecting stale output."
    }
    $partialSummary.failed = 0
    [IO.File]::WriteAllText(
        $partialSummaryPath,
        ($partialSummary | ConvertTo-Json -Depth 4),
        $utf8NoBom
    )
    $staleMarker = $partialMarker | ConvertTo-Json -Depth 4 | ConvertFrom-Json
    $staleMarker.support_tool_sha256 = "f" * 64
    [IO.File]::WriteAllText($markerPath, ($staleMarker | ConvertTo-Json -Depth 4), $utf8NoBom)
    Assert-Throws {
        Assert-DspreUnrequestedRawMarkersCurrent @partialArguments
    } "stale unrequested raw marker"
    if ([IO.File]::ReadAllText($publishedCatalog, [Text.Encoding]::UTF8) -ne "catalog-sentinel") {
        throw "Partial-export preflight mutated a published catalog before rejecting stale output."
    }

    $deleteRoot = Join-Path $fingerprintRoot "delete_root"
    $outsideRoot = Join-Path $fingerprintRoot "outside_root"
    $normalDeleteTarget = Join-Path $deleteRoot "normal\child"
    $null = [IO.Directory]::CreateDirectory($deleteRoot)
    $null = [IO.Directory]::CreateDirectory($outsideRoot)
    $outsideSentinel = Join-Path $outsideRoot "sentinel.txt"
    [IO.File]::WriteAllText($outsideSentinel, "keep", $utf8NoBom)
    if ((Assert-DspreSafeRecursiveDeletePath -Path $normalDeleteTarget -AllowedRoot $deleteRoot) -ne
        [IO.Path]::GetFullPath($normalDeleteTarget)) {
        throw "Safe recursive-delete validation changed a normal descendant path."
    }
    Assert-Throws {
        Assert-DspreSafeRecursiveDeletePath -Path $deleteRoot -AllowedRoot $deleteRoot
    } "recursive-delete root target"
    Assert-Throws {
        Assert-DspreSafeRecursiveDeletePath `
            -Path (Join-Path (Split-Path -Parent $deleteRoot) "sibling") `
            -AllowedRoot $deleteRoot
    } "recursive-delete sibling target"

    $junctionPath = Join-Path $deleteRoot "external_link"
    $null = New-Item -ItemType Junction -Path $junctionPath -Target $outsideRoot -ErrorAction Stop
    try {
        Assert-Throws {
            Assert-DspreSafeRecursiveDeletePath `
                -Path (Join-Path $junctionPath "stale_asset") `
                -AllowedRoot $deleteRoot
        } "recursive-delete junction"
        if (-not (Test-Path -LiteralPath $outsideSentinel -PathType Leaf)) {
            throw "Junction rejection did not preserve the external sentinel."
        }
    }
    finally {
        if (Test-Path -LiteralPath $junctionPath) {
            $junctionItem = Get-Item -LiteralPath $junctionPath -Force
            if (($junctionItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                throw "Synthetic junction unexpectedly became a normal directory."
            }
            [IO.Directory]::Delete($junctionPath, $false)
        }
    }

    $treeRoot = Join-Path $deleteRoot "tree_with_link"
    $null = [IO.Directory]::CreateDirectory((Join-Path $treeRoot "normal"))
    $junctionPath = Join-Path $treeRoot "nested_external_link"
    $null = New-Item -ItemType Junction -Path $junctionPath -Target $outsideRoot -ErrorAction Stop
    try {
        Assert-Throws {
            Assert-DspreTreeHasNoReparsePoints `
                -RootPath $treeRoot `
                -Label "Synthetic delete tree"
        } "recursive-delete nested junction"
        Assert-Throws {
            Get-DspreStageFileRecords `
                -RootPath $treeRoot `
                -Label "Synthetic stage tree"
        } "stage walker nested junction"
        if (-not (Test-Path -LiteralPath $outsideSentinel -PathType Leaf)) {
            throw "Nested junction rejection did not preserve the external sentinel."
        }
    }
    finally {
        if (Test-Path -LiteralPath $junctionPath) {
            [IO.Directory]::Delete($junctionPath, $false)
        }
    }

    $orchestratorPath = Join-Path $PSScriptRoot "dspre_export_all_matrices.ps1"
    $tokens = $null
    $parseErrors = $null
    $orchestratorAst = [Management.Automation.Language.Parser]::ParseFile(
        $orchestratorPath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -ne 0) {
        throw "The all-matrix orchestrator did not parse for focused helper tests."
    }
	foreach ($functionName in @(
		"Get-StageFileRecords",
		"Assert-StageFileRecords",
		"Publish-MatrixCatalogPair",
		"Get-UnexpectedMatrixDestinations"
	)) {
        $definition = $orchestratorAst.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $functionName
        }, $true)
        if ($null -eq $definition) {
            throw "All-matrix helper was not found for focused testing: $functionName"
        }
        Invoke-Expression $definition.Extent.Text
    }

    $stageRoot = Join-Path $fingerprintRoot "stage_records"
    $textureRoot = Join-Path $stageRoot "shared\textures"
    $null = [IO.Directory]::CreateDirectory($textureRoot)
    $glbPath = Join-Path $stageRoot "terrain.glb"
    $glbBytes = New-Object byte[] 12
    [Buffer]::BlockCopy([Text.Encoding]::ASCII.GetBytes("glTF"), 0, $glbBytes, 0, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]2), 0, $glbBytes, 4, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]12), 0, $glbBytes, 8, 4)
    [IO.File]::WriteAllBytes($glbPath, $glbBytes)
    $pngPath = Join-Path $textureRoot "texture.png"
    [IO.File]::WriteAllBytes($pngPath, [byte[]]@(1, 2, 3, 4))
    $stageRecords = @(Get-StageFileRecords -RootPath $stageRoot)
    $null = Assert-StageFileRecords `
        -RootPath $stageRoot `
        -ExpectedRecords $stageRecords `
        -Label "Synthetic stage"

    [IO.File]::WriteAllBytes($pngPath, [byte[]]@(1, 2, 3, 5))
    Assert-Throws {
        Assert-StageFileRecords `
            -RootPath $stageRoot `
            -ExpectedRecords $stageRecords `
            -Label "Synthetic changed-content stage"
    } "same-length stage content replacement"
    [IO.File]::WriteAllBytes($pngPath, [byte[]]@(1, 2, 3, 4))
    Move-Item -LiteralPath $glbPath -Destination (Join-Path $stageRoot "replacement.glb")
    Assert-Throws {
        Assert-StageFileRecords `
            -RootPath $stageRoot `
            -ExpectedRecords $stageRecords `
            -Label "Synthetic changed-path stage"
    } "same-count stage path replacement"
    Move-Item -LiteralPath (Join-Path $stageRoot "replacement.glb") -Destination $glbPath

    $importSidecar = "$pngPath.import"
    [IO.File]::WriteAllText($importSidecar, "generated-sidecar", $utf8NoBom)
    Assert-Throws {
        Assert-StageFileRecords `
            -RootPath $stageRoot `
            -ExpectedRecords $stageRecords `
            -Label "Synthetic sidecar stage"
    } "undeclared stage sidecar"
    $null = Assert-StageFileRecords `
        -RootPath $stageRoot `
        -ExpectedRecords $stageRecords `
        -IgnoreGodotImportSidecars `
        -Label "Synthetic Godot-imported stage"
    $importTemporary = "$pngPath.import~RF1234567.TMP"
    [IO.File]::WriteAllText($importTemporary, "generated-import-temporary", $utf8NoBom)
    $null = Assert-StageFileRecords `
        -RootPath $stageRoot `
        -ExpectedRecords $stageRecords `
        -IgnoreGodotImportSidecars `
        -Label "Synthetic Godot-import temporary stage"
    Remove-Item -LiteralPath $importTemporary -Force

    $syncPath = Join-Path $PSScriptRoot "sync_dspre_godot_assets.ps1"
    $syncTokens = $null
    $syncParseErrors = $null
    $syncAst = [Management.Automation.Language.Parser]::ParseFile(
        $syncPath,
        [ref]$syncTokens,
        [ref]$syncParseErrors
    )
    if ($syncParseErrors.Count -ne 0) {
        throw "The Godot sync script did not parse for focused helper tests."
    }
    foreach ($functionName in @(
        "Get-StageFilesWithoutReparsePoints",
        "Get-StageFileRecords",
        "Assert-StageFileRecords"
    )) {
        $definition = $syncAst.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $functionName
        }, $true)
        if ($null -eq $definition) {
            throw "Godot sync helper was not found for focused testing: $functionName"
        }
        Invoke-Expression $definition.Extent.Text
    }
    Assert-Throws {
        Assert-StageFileRecords `
            -RootPath $stageRoot `
            -ExpectedRecords $stageRecords `
            -Label "Synthetic strict sync destination"
    } "sync destination import sidecar without explicit exception"
    $null = Assert-StageFileRecords `
        -RootPath $stageRoot `
        -ExpectedRecords $stageRecords `
        -IgnoreGodotImportSidecars `
        -Label "Synthetic editor-raced sync destination"
    $undeclaredDestinationFile = Join-Path $stageRoot "undeclared.cache"
    [IO.File]::WriteAllText($undeclaredDestinationFile, "undeclared", $utf8NoBom)
    Assert-Throws {
        Assert-StageFileRecords `
            -RootPath $stageRoot `
            -ExpectedRecords $stageRecords `
            -IgnoreGodotImportSidecars `
            -Label "Synthetic sync destination with undeclared file"
    } "sync destination non-import sidecar"
    Remove-Item -LiteralPath $undeclaredDestinationFile -Force

    $catalogRootA = Join-Path $fingerprintRoot "catalog_a"
    $catalogRootB = Join-Path $fingerprintRoot "catalog_b"
    $null = [IO.Directory]::CreateDirectory($catalogRootA)
    $null = [IO.Directory]::CreateDirectory($catalogRootB)
    $catalogA = Join-Path $catalogRootA "matrix_catalog.json"
    $catalogB = Join-Path $catalogRootB "matrix_catalog.json"
    Publish-MatrixCatalogPair `
        -GeneratedPath $catalogA `
        -GodotPath $catalogB `
        -Json '{"schema_version":2}' `
        -Encoding $utf8NoBom
    if (
        [IO.File]::ReadAllText($catalogA, [Text.Encoding]::UTF8) -ne '{"schema_version":2}' -or
        [IO.File]::ReadAllText($catalogB, [Text.Encoding]::UTF8) -ne '{"schema_version":2}'
    ) {
        throw "Catalog pair publication did not write identical final files."
    }
    [IO.File]::Delete($catalogA)
    [IO.File]::Delete($catalogB)
    $failingCatalog = Join-Path $catalogRootA "failed_catalog.json"
    Assert-Throws {
        Publish-MatrixCatalogPair `
            -GeneratedPath $failingCatalog `
            -GodotPath $failingCatalog `
            -Json '{"schema_version":2}' `
            -Encoding $utf8NoBom
    } "second catalog publication move"
	if (Test-Path -LiteralPath $failingCatalog -PathType Leaf) {
		throw "Failed catalog pair publication left a final catalog behind."
	}

	$cleanupRoot = Join-Path $fingerprintRoot "stale_destinations"
	$expectedCleanupRoot = Join-Path $cleanupRoot "matrix_0001"
	$staleCleanupRoot = Join-Path $cleanupRoot "matrix_0002"
	$null = [IO.Directory]::CreateDirectory($expectedCleanupRoot)
	$null = [IO.Directory]::CreateDirectory($staleCleanupRoot)
	$staleDestinationPaths = @(Get-UnexpectedMatrixDestinations `
		-Variants @([pscustomobject]@{ variant = "matrix_0001" }) `
		-RootPath $cleanupRoot `
		-AllowedRoot $fingerprintRoot `
		-Label "Synthetic cleanup")
	if (
		$staleDestinationPaths.Count -ne 1 -or
		[string]$staleDestinationPaths[0] -ne [IO.Path]::GetFullPath($staleCleanupRoot) -or
		-not (Test-Path -LiteralPath $staleCleanupRoot -PathType Container) -or
		-not (Test-Path -LiteralPath $expectedCleanupRoot -PathType Container)
	) {
		throw "Stale destination preflight did not return the exact removable set."
	}
	foreach ($staleDestinationPath in $staleDestinationPaths) {
		Remove-Item -LiteralPath $staleDestinationPath -Recurse -Force
	}
	if (Test-Path -LiteralPath $staleCleanupRoot) {
		throw "Prevalidated stale destination cleanup did not remove its candidate."
	}

	$staleCleanupRoot = Join-Path $cleanupRoot "matrix_0002"
	$staleCleanupJunction = Join-Path $cleanupRoot "matrix_0003"
	$null = [IO.Directory]::CreateDirectory($staleCleanupRoot)
	$null = New-Item -ItemType Junction `
		-Path $staleCleanupJunction `
		-Target $outsideRoot `
		-ErrorAction Stop
	try {
		Assert-Throws {
			Get-UnexpectedMatrixDestinations `
				-Variants @([pscustomobject]@{ variant = "matrix_0001" }) `
				-RootPath $cleanupRoot `
				-AllowedRoot $fingerprintRoot `
				-Label "Synthetic cleanup"
		} "stale destination junction"
		if (
			-not (Test-Path -LiteralPath $staleCleanupRoot -PathType Container) -or
			-not (Test-Path -LiteralPath $outsideSentinel -PathType Leaf)
		) {
			throw "Stale destination preflight mutated output before rejecting a junction."
		}
	}
	finally {
		if (Test-Path -LiteralPath $staleCleanupJunction) {
			[IO.Directory]::Delete($staleCleanupJunction, $false)
		}
	}

	$validatorPath = Join-Path $PSScriptRoot "validate_dspre_matrix_catalog.ps1"
    $validatorTokens = $null
    $validatorParseErrors = $null
    $validatorAst = [Management.Automation.Language.Parser]::ParseFile(
        $validatorPath,
        [ref]$validatorTokens,
        [ref]$validatorParseErrors
    )
    if ($validatorParseErrors.Count -ne 0) {
        throw "The matrix catalog validator did not parse for focused helper tests."
    }
    foreach ($functionName in @(
        "Get-StageFileRecords",
        "Assert-StageFileRecords",
        "Assert-FilesByteIdentical"
    )) {
        $definition = $validatorAst.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $functionName
        }, $true)
        if ($null -eq $definition) {
            throw "Matrix catalog validator helper was not found: $functionName"
        }
        Invoke-Expression $definition.Extent.Text
    }
    $validatorJunction = Join-Path $stageRoot "validator_external_link"
    $null = New-Item -ItemType Junction `
        -Path $validatorJunction `
        -Target $outsideRoot `
        -ErrorAction Stop
    try {
        Assert-Throws {
            Get-StageFileRecords -RootPath $stageRoot -IgnoreGodotImportSidecars
        } "validator stage nested junction"
    }
    finally {
        if (Test-Path -LiteralPath $validatorJunction) {
            [IO.Directory]::Delete($validatorJunction, $false)
        }
    }
    [IO.File]::WriteAllText($importTemporary, "generated-import-temporary", $utf8NoBom)
    $validatorRecords = @(Assert-StageFileRecords `
        -RootPath $stageRoot `
        -ExpectedRecords $stageRecords `
        -IgnoreGodotImportSidecars `
        -Label "Synthetic validator stage")
    if ($validatorRecords.Count -ne $stageRecords.Count) {
        throw "Matrix catalog validator did not return its validated file records."
    }
    Remove-Item -LiteralPath $importTemporary -Force

    $validatorCatalogA = Join-Path $catalogRootA "validator_catalog.json"
    $validatorCatalogB = Join-Path $catalogRootB "validator_catalog.json"
    [IO.File]::WriteAllText($validatorCatalogA, '{"schema_version":2}', $utf8NoBom)
    [IO.File]::WriteAllText($validatorCatalogB, '{"schema_version":2}', $utf8NoBom)
    Assert-FilesByteIdentical `
        -ExpectedPath $validatorCatalogA `
        -ActualPath $validatorCatalogB `
        -Label "Synthetic catalog pair"
    [IO.File]::WriteAllText($validatorCatalogB, '{"schema_version":3}', $utf8NoBom)
    Assert-Throws {
        Assert-FilesByteIdentical `
            -ExpectedPath $validatorCatalogA `
            -ActualPath $validatorCatalogB `
            -Label "Synthetic mismatched catalog pair"
    } "mismatched complete catalog pair"
}
finally {
    if ($null -ne $junctionPath -and (Test-Path -LiteralPath $junctionPath)) {
        $junctionItem = Get-Item -LiteralPath $junctionPath -Force
        if (($junctionItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
            throw "Refusing to recursively clean a synthetic root containing a non-junction link path."
        }
        [IO.Directory]::Delete($junctionPath, $false)
    }
    if (Test-Path -LiteralPath $fingerprintRoot -PathType Container) {
        Remove-Item -LiteralPath $fingerprintRoot -Recurse -Force
    }
}

$deleteConsumerMinimums = [ordered]@{
    "dspre_batch_export.ps1" = 5
    "dedupe_dspre_materials.ps1" = 1
    "sync_dspre_godot_assets.ps1" = 2
}
foreach ($entry in $deleteConsumerMinimums.GetEnumerator()) {
    $consumerPath = Join-Path $PSScriptRoot $entry.Key
    $consumerText = [IO.File]::ReadAllText($consumerPath, [Text.Encoding]::UTF8)
    $safeDeleteCalls = [regex]::Matches(
        $consumerText,
        '\bAssert-DspreSafeRecursiveDeletePath\b'
    ).Count
    if ($safeDeleteCalls -lt [int]$entry.Value) {
        throw "$($entry.Key) is not fully wired to shared recursive-delete validation."
    }
}

$dedupeConsumerText = [IO.File]::ReadAllText(
    (Join-Path $PSScriptRoot "dedupe_dspre_materials.ps1"),
    [Text.Encoding]::UTF8
)
$syncConsumerText = [IO.File]::ReadAllText(
    (Join-Path $PSScriptRoot "sync_dspre_godot_assets.ps1"),
    [Text.Encoding]::UTF8
)
$batchConsumerText = [IO.File]::ReadAllText(
    (Join-Path $PSScriptRoot "dspre_batch_export.ps1"),
    [Text.Encoding]::UTF8
)
if (
    $dedupeConsumerText.IndexOf('AllowedRoot $workspaceRoot', [StringComparison]::Ordinal) -lt 0 -or
    $syncConsumerText.IndexOf('AllowedRoot $ProjectRoot', [StringComparison]::Ordinal) -lt 0 -or
    $batchConsumerText.IndexOf('AllowedRoot $workspaceRoot', [StringComparison]::Ordinal) -lt 0
) {
    throw "A direct pipeline consumer does not validate its complete ancestor chain."
}
if ($batchConsumerText.IndexOf(
    'DSPRE matrix work tree before model write',
    [StringComparison]::Ordinal
) -ge 0) {
    throw "Batch export still rescans the complete work tree before every model write."
}
foreach ($consumer in @(
    [pscustomobject]@{ Name = "dedupe"; Text = $dedupeConsumerText },
    [pscustomobject]@{ Name = "sync"; Text = $syncConsumerText }
)) {
    if ([regex]::IsMatch([string]$consumer.Text, 'Get-ChildItem[^\r\n]*-Recurse')) {
        throw "$($consumer.Name) still uses a recursive stage walker that can follow junctions."
    }
}

$orchestratorText = [IO.File]::ReadAllText(
    (Join-Path $PSScriptRoot "dspre_export_all_matrices.ps1"),
    [Text.Encoding]::UTF8
)
$markerOnlyChecks = [regex]::Matches($orchestratorText, '(?m)^\s+-MarkerOnly\s*$').Count
if ($markerOnlyChecks -lt 4) {
    throw "The all-matrix pipeline does not use lightweight post-stage and publication checks."
}
$rawPreflightIndex = $orchestratorText.IndexOf(
    "Assert-DspreUnrequestedRawMarkersCurrent",
    [StringComparison]::Ordinal
)
$downstreamPreflightIndex = $orchestratorText.IndexOf(
    '$staleDownstreamVariants =',
    [StringComparison]::Ordinal
)
$catalogInvalidationIndex = $orchestratorText.IndexOf(
	'$publishedCatalogPaths =',
	[StringComparison]::Ordinal
)
$staleCleanupIndex = $orchestratorText.IndexOf(
	'$staleDestinationPaths = @(',
	[StringComparison]::Ordinal
)
$rootCreationIndex = $orchestratorText.IndexOf(
    'New-Item -ItemType Directory -Path $rawRoot, $dedupRoot, $platinumRoot',
    [StringComparison]::Ordinal
)
$rootValidationPrefix = if ($rootCreationIndex -ge 0) {
    $orchestratorText.Substring(0, $rootCreationIndex)
}
else {
    ""
}
$rootRevalidationIndex = $rootValidationPrefix.LastIndexOf(
    '$rawRoot = Assert-DspreSafeRecursiveDeletePath',
    [StringComparison]::Ordinal
)
$destinationMutationIndex = $orchestratorText.IndexOf(
    '$processed = 0',
    [StringComparison]::Ordinal
)
$catalogAggregationIndex = $orchestratorText.IndexOf(
    '$catalogJson =',
    [StringComparison]::Ordinal
)
$finalFingerprintIndex = $orchestratorText.LastIndexOf(
    '$changedInputs =',
    [StringComparison]::Ordinal
)
$catalogPublicationIndex = $orchestratorText.LastIndexOf(
    'Publish-MatrixCatalogPair',
    [StringComparison]::Ordinal
)
if (
    $rawPreflightIndex -lt 0 -or
    $downstreamPreflightIndex -le $rawPreflightIndex -or
    $rootRevalidationIndex -le $downstreamPreflightIndex -or
    $rootCreationIndex -le $rootRevalidationIndex -or
	$catalogInvalidationIndex -le $downstreamPreflightIndex -or
	$catalogInvalidationIndex -le $rootCreationIndex -or
	$staleCleanupIndex -le $catalogInvalidationIndex -or
	$destinationMutationIndex -le $catalogInvalidationIndex -or
	$destinationMutationIndex -le $staleCleanupIndex -or
    $catalogAggregationIndex -le $destinationMutationIndex -or
    $finalFingerprintIndex -le $catalogAggregationIndex -or
    $catalogPublicationIndex -le $finalFingerprintIndex
) {
    throw "Pipeline preflight, aggregation, final fingerprints, and catalog publication are misordered."
}

$markerContracts = [ordered]@{
	"dspre_batch_export.ps1" = @("Assert-CurrentRawDestination", "Get-DspreStageFileRecords", "files =", 'Assert-DspreSafeRecursiveDeletePath `')
	"dspre_export_all_matrices.ps1" = @("signature -isnot [pscustomobject]", "output_material_count -le 0", "Get-UnexpectedMatrixDestinations", "import~")
	"dedupe_dspre_materials.ps1" = @("schema_version = 2", "dedupe_tool_sha256", "files =")
	"sync_dspre_godot_assets.ps1" = @("schema_version = 2", "materialCatalog.schema_version -ne 1", "signature -isnot [pscustomobject]", "output_material_count -le 0", "dedupe_tool_sha256", "sync_tool_sha256", "files =", "IgnoreGodotImportSidecars")
	"validate_dspre_matrix_catalog.ps1" = @("schema_version -ne 2", "materialCatalog.schema_version -ne 1", "signature -isnot [pscustomobject]", "output_material_count -le 0", '$rawRoot = Assert-DspreSafeRecursiveDeletePath', "dedupe_tool_sha256", "sync_tool_sha256", "Assert-StageFileRecords", "generatedCatalogPath", "Assert-FilesByteIdentical", "import~")
}
foreach ($entry in $markerContracts.GetEnumerator()) {
    $consumerText = [IO.File]::ReadAllText(
        (Join-Path $PSScriptRoot $entry.Key),
        [Text.Encoding]::UTF8
    )
    foreach ($requiredText in $entry.Value) {
        if ($consumerText.IndexOf($requiredText, [StringComparison]::Ordinal) -lt 0) {
            throw "$($entry.Key) is missing the stage-marker contract '$requiredText'."
        }
    }
}

Write-Host "DSPRE collision support test complete."
Write-Host "  Packed attributes: OK"
Write-Host "  Packed BDHC:       OK"
Write-Host "  Manifest contract: OK"
Write-Host "  Invalid data:      OK"
Write-Host "  Source fingerprints: OK"
Write-Host "  Tool fingerprints:   OK"
Write-Host "  Raw marker contract:  OK"
Write-Host "  Partial preflight:    OK"
Write-Host "  Safe recursive delete: OK"
Write-Host "  Delete consumer wiring: OK"
Write-Host "  Partial mutation order: OK"
Write-Host "  Exact stage file records: OK"
Write-Host "  Atomic catalog pair: OK"
Write-Host "  Stale destination cleanup: OK"
Write-Host "  Stage marker schema 2: OK"
