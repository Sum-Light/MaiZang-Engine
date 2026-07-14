[CmdletBinding()]
param(
    [string]$DspreContents = "",
    [string]$ApiculaPath = "C:\Users\YbbNa\Downloads\DSPRE-win-Portable\current\Tools\apicula.exe",
    [string]$GodotPath = "C:\Users\YbbNa\Downloads\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe",
    [int[]]$MatrixIds = @(),
    [int]$MaxParallel = 4,
    [switch]$RebuildExisting,
    [switch]$ReuseAreaResolution,
    [switch]$FieldTextureAnimationsOnly,
    [switch]$SkipGodotImport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "dspre_collision_support.ps1")
$rawRoot = Join-Path $workspaceRoot "generated\dspre_glb"
$dedupRoot = Join-Path $workspaceRoot "generated\dspre_glb_dedup"
$projectRoot = Join-Path $workspaceRoot "new-game-project"
$platinumRoot = Join-Path $projectRoot "assets\platinum"
$resolutionPath = Join-Path $workspaceRoot "generated\dspre_matrix_area_overrides.json"
$rawRoot = Assert-DspreSafeRecursiveDeletePath -Path $rawRoot -AllowedRoot $workspaceRoot
$dedupRoot = Assert-DspreSafeRecursiveDeletePath -Path $dedupRoot -AllowedRoot $workspaceRoot
$platinumRoot = Assert-DspreSafeRecursiveDeletePath -Path $platinumRoot -AllowedRoot $projectRoot
$generatedCatalogPath = Join-Path $dedupRoot "matrix_catalog.json"
$godotCatalogPath = Join-Path $platinumRoot "matrix_catalog.json"
$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Resolve-ExistingFile {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not found: $Path"
    }
    return (Get-Item -LiteralPath $Path).FullName
}

function Resolve-ExistingDirectory {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label was not found: $Path"
    }
    return (Get-Item -LiteralPath $Path).FullName
}

function Invoke-ProjectScript {
    param([string]$Path, [hashtable]$Arguments)

    $argumentList = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $Arguments.GetEnumerator()) {
        if ($entry.Value -is [Management.Automation.SwitchParameter]) {
            if ($entry.Value.IsPresent) {
                $argumentList.Add("-$($entry.Key)")
            }
            continue
        }
        if ($entry.Value -is [bool]) {
            if ($entry.Value) {
                $argumentList.Add("-$($entry.Key)")
            }
            continue
        }
        $argumentList.Add("-$($entry.Key)")
        $argumentList.Add($entry.Value)
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @argumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$([IO.Path]::GetFileName($Path)) failed with exit code $LASTEXITCODE."
    }
}

function Publish-MatrixCatalogPair {
    param(
        [string]$GeneratedPath,
        [string]$GodotPath,
        [string]$Json,
        [Text.Encoding]$Encoding
    )

    $token = [Guid]::NewGuid().ToString("N")
    $generatedTemp = Join-Path (Split-Path -Parent $GeneratedPath) ".matrix_catalog.$token.tmp"
    $godotTemp = Join-Path (Split-Path -Parent $GodotPath) ".matrix_catalog.$token.tmp"
    try {
        foreach ($finalPath in @($GeneratedPath, $GodotPath)) {
            if (Test-Path -LiteralPath $finalPath) {
                throw "Catalog publication requires an absent final path: $finalPath"
            }
        }
        [IO.File]::WriteAllText($generatedTemp, $Json, $Encoding)
        [IO.File]::WriteAllText($godotTemp, $Json, $Encoding)
        [IO.File]::Move($generatedTemp, $GeneratedPath)
        [IO.File]::Move($godotTemp, $GodotPath)
    }
    catch {
        $publishError = $_
        $cleanupErrors = New-Object System.Collections.Generic.List[string]
        foreach ($path in @($generatedTemp, $godotTemp, $GeneratedPath, $GodotPath)) {
            try {
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    [IO.File]::Delete($path)
                }
            }
            catch {
                $cleanupErrors.Add("$path ($($_.Exception.Message))")
            }
        }
        $remainingCatalogs = @(
            @($GeneratedPath, $GodotPath) |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
        )
        if ($cleanupErrors.Count -ne 0 -or $remainingCatalogs.Count -ne 0) {
            throw "Matrix catalog pair publication failed and cleanup could not withdraw both catalogs: $($cleanupErrors -join '; ')"
        }
        throw "Matrix catalog pair publication failed; both catalogs were withdrawn: $($publishError.Exception.Message)"
    }
    finally {
        foreach ($tempPath in @($generatedTemp, $godotTemp)) {
            try {
                if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
                    [IO.File]::Delete($tempPath)
                }
            }
            catch {
                Write-Warning "Could not remove catalog publication temporary file: $tempPath"
            }
        }
    }
}

function Remove-MatrixCatalogPair {
    param(
        [Parameter(Mandatory)][string]$GeneratedPath,
        [Parameter(Mandatory)][string]$GodotPath
    )

    $paths = @($GeneratedPath, $GodotPath)
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if (
            $item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        ) {
            throw "Matrix catalog path must be a regular non-reparse file: $path"
        }
    }
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            [IO.File]::Delete($path)
        }
    }
}

function Invoke-MatrixCatalogWithdrawalTransaction {
    param(
        [Parameter(Mandatory)][string]$GeneratedPath,
        [Parameter(Mandatory)][string]$GodotCatalogPath,
        [Parameter(Mandatory)][scriptblock]$Operation
    )

    Remove-MatrixCatalogPair -GeneratedPath $GeneratedPath -GodotPath $GodotCatalogPath
    try {
        $result = @(& $Operation)
        foreach ($path in @($GeneratedPath, $GodotCatalogPath)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Matrix catalog transaction did not publish both catalogs: $path"
            }
        }
        $generatedBytes = [IO.File]::ReadAllBytes($GeneratedPath)
        $godotBytes = [IO.File]::ReadAllBytes($GodotCatalogPath)
        if ($generatedBytes.Length -ne $godotBytes.Length) {
            throw "Matrix catalog transaction published different catalog lengths."
        }
        for ($index = 0; $index -lt $generatedBytes.Length; $index++) {
            if ($generatedBytes[$index] -ne $godotBytes[$index]) {
                throw "Matrix catalog transaction published different catalog content."
            }
        }
        return $result
    }
    catch {
        $failure = $_
        try {
            Remove-MatrixCatalogPair -GeneratedPath $GeneratedPath -GodotPath $GodotCatalogPath
        }
        catch {
            throw "Matrix catalog transaction failed and could not withdraw both catalogs: $($failure.Exception.Message); cleanup: $($_.Exception.Message)"
        }
        throw $failure
    }
}

function Get-DefaultCell {
    param($Manifest)

    $cells = @($Manifest.cells)
    if ($cells.Count -eq 0) {
        throw "Matrix $($Manifest.matrix.id) has no occupied cells."
    }
    if ([int]$Manifest.matrix.id -eq 0) {
        $preferred = $cells | Where-Object { [int]$_.x -eq 3 -and [int]$_.y -eq 27 } |
            Select-Object -First 1
        if ($null -ne $preferred) {
            return [pscustomobject][ordered]@{ x = 3; y = 27 }
        }
    }
    $centerX = ([double]$Manifest.matrix.width - 1.0) / 2.0
    $centerY = ([double]$Manifest.matrix.height - 1.0) / 2.0
    $sortProperties = @(
        @{ Expression = {
                [Math]::Pow([double]$_.x - $centerX, 2) +
                    [Math]::Pow([double]$_.y - $centerY, 2)
            } },
        @{ Expression = { [int]$_.y } },
        @{ Expression = { [int]$_.x } }
    )
    $selected = $cells |
        Sort-Object -Property $sortProperties |
        Select-Object -First 1
    return [pscustomobject][ordered]@{ x = [int]$selected.x; y = [int]$selected.y }
}

function Get-OptionalSummaryCount {
    param($Summary, [string]$Name, [string]$Label)

    $property = $Summary.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return 0
    }
    $value = $property.Value
    if (
        $null -eq $value -or
        [double]$value -ne [long]$value -or
        [long]$value -lt 0 -or
        [long]$value -gt [int]::MaxValue
    ) {
        throw "$Label summary '$Name' must be a non-negative integer."
    }
    return [int]$value
}

function Test-FieldTextureCatalogDataEquivalent {
    param($Catalog, $Section)

    if (
        $null -eq $Catalog.PSObject.Properties["field_texture_animations"] -or
        $null -eq $Catalog.PSObject.Properties["summary"]
    ) {
        return $false
    }
    $summary = $Catalog.summary
    foreach ($propertyName in @(
        "field_texture_animation_bindings",
        "deferred_field_texture_variants",
        "field_texture_animation_frames"
    )) {
        if ($null -eq $summary.PSObject.Properties[$propertyName]) {
            return $false
        }
    }
    if (
        [int]$summary.field_texture_animation_bindings -ne [int]$Section.summary.ready_bindings -or
        [int]$summary.deferred_field_texture_variants -ne [int]$Section.summary.deferred_variants -or
        [int]$summary.field_texture_animation_frames -ne [int]$Section.summary.generated_unique_frames
    ) {
        return $false
    }
    return (
        ($Catalog.field_texture_animations | ConvertTo-Json -Depth 20 -Compress) -ceq
        ($Section | ConvertTo-Json -Depth 20 -Compress)
    )
}

function Get-FieldTextureAnimationImportStatus {
    param(
        [Parameter(Mandatory)]$Section,
        [Parameter(Mandatory)][string]$AssetRoot
    )

    $root = [IO.Path]::GetFullPath($AssetRoot).TrimEnd('\', '/')
    $rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
    $projectRootForImports = Split-Path (Split-Path $root -Parent) -Parent
    $cacheRoot = [IO.Path]::GetFullPath(
        (Join-Path $projectRootForImports ".godot\imported")
    ).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($binding in @($Section.bindings)) {
        foreach ($frame in @($binding.frames)) {
            $relativePath = ([string]$frame.path).Replace('/', '\')
            $path = [IO.Path]::GetFullPath((Join-Path $root $relativePath))
            if (
                -not $path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
                -not $paths.Add($path)
            ) {
                continue
            }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Field texture animation frame was not found: $path"
            }
        }
    }
    if ($paths.Count -ne [int]$Section.summary.generated_unique_frames) {
        throw "Field texture animation frame paths do not match the section summary."
    }

    $missingSidecars = 0
    $invalidSidecars = 0
    $missingCaches = 0
    foreach ($path in $paths) {
        $importPath = "$path.import"
        if (-not (Test-Path -LiteralPath $importPath -PathType Leaf)) {
            $missingSidecars++
            continue
        }
        $text = [IO.File]::ReadAllText($importPath, [Text.Encoding]::UTF8)
        if (
            $text -notmatch '(?m)^compress/mode=0$' -or
            $text -notmatch '(?m)^mipmaps/generate=false$' -or
            $text -notmatch '(?m)^detect_3d/compress_to=0$'
        ) {
            $invalidSidecars++
            continue
        }
        $destMatch = [regex]::Match($text, '(?m)^dest_files=\[(.+)\]$')
        if (-not $destMatch.Success) {
            $invalidSidecars++
            continue
        }
        foreach ($pathMatch in [regex]::Matches($destMatch.Groups[1].Value, '"([^"]+)"')) {
            $resourcePath = $pathMatch.Groups[1].Value
            if (-not $resourcePath.StartsWith("res://.godot/imported/", [StringComparison]::Ordinal)) {
                throw "Field texture animation cache path is invalid: $resourcePath"
            }
            $cachePath = [IO.Path]::GetFullPath((Join-Path $projectRootForImports (
                $resourcePath.Substring("res://".Length).Replace('/', '\')
            )))
            if (-not $cachePath.StartsWith($cacheRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Field texture animation cache escaped the import root: $cachePath"
            }
            if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
                $missingCaches++
            }
        }
    }
    return [pscustomobject][ordered]@{
        frames = $paths.Count
        missing_sidecars = $missingSidecars
        invalid_sidecars = $invalidSidecars
        missing_caches = $missingCaches
        all_current = (
            $missingSidecars -eq 0 -and
            $invalidSidecars -eq 0 -and
            $missingCaches -eq 0
        )
    }
}

function Get-FieldTextureFastImportPlan {
    param(
        [Parameter(Mandatory)]$BuildResult,
        [Parameter(Mandatory)]$ImportStatus
    )

    foreach ($propertyName in @(
        "reused",
        "godot_stage_repaired",
        "godot_stage_changed"
    )) {
        $property = $BuildResult.PSObject.Properties[$propertyName]
        if ($null -eq $property -or $property.Value -isnot [bool]) {
            throw "Field texture build result is missing Boolean '$propertyName'."
        }
    }
    $stageChanged = [bool]$BuildResult.godot_stage_changed
    $missingSidecars = [int]$ImportStatus.missing_sidecars -gt 0
    $initialImport = $stageChanged -or $missingSidecars -or
        [int]$ImportStatus.missing_caches -gt 0
    $configureTextures = $stageChanged -or $missingSidecars -or
        [int]$ImportStatus.invalid_sidecars -gt 0
    return [pscustomobject][ordered]@{
        initial_import = $initialImport
        configure_textures = $configureTextures
        no_op = -not $initialImport -and -not $configureTextures
    }
}

function Invoke-FieldTextureAnimationBuild {
    param(
        [string]$SourceRoot,
        [switch]$Force
    )

    $builderPath = Resolve-ExistingFile `
        (Join-Path $PSScriptRoot "build_dspre_field_texture_animations.ps1") `
        "DSPRE field texture animation builder"
    $buildOutput = @(& {
        param(
            [string]$Path,
            [string]$DspreRoot,
            [string]$MaterialRoot,
            [string]$GeneratedRoot,
            [string]$GodotRoot,
            [string]$BuildWorkRoot,
            [bool]$Rebuild
        )
        . $Path
        Invoke-DspreFieldTextureAnimationBuild `
            -SourceRoot $DspreRoot `
            -MaterialRoot $MaterialRoot `
            -GeneratedRoot $GeneratedRoot `
            -GodotRoot $GodotRoot `
            -BuildWorkRoot $BuildWorkRoot `
            -ExpectedCatalogCount 278 `
            -Rebuild:$Rebuild
    } `
        $builderPath `
        $SourceRoot `
        $dedupRoot `
        (Join-Path $dedupRoot "field_texture_animations") `
        (Join-Path $platinumRoot "field_texture_animations") `
        (Join-Path $workspaceRoot ".work\dspre_field_texture_animations") `
        ([bool]$Force))
    $buildResult = @(
        $buildOutput | Where-Object {
            $null -ne $_ -and $null -ne $_.PSObject.Properties["reused"]
        }
    ) | Select-Object -Last 1
    if ($null -eq $buildResult) {
        throw "Field texture animation builder did not return its build result."
    }
    $sectionPath = Join-Path $dedupRoot "field_texture_animations\field_texture_animations.json"
    if (-not (Test-Path -LiteralPath $sectionPath -PathType Leaf)) {
        throw "Field texture animation builder did not publish its catalog section."
    }
    $section = [IO.File]::ReadAllText($sectionPath, [Text.Encoding]::UTF8) |
        ConvertFrom-Json
    if (
        [int]$section.schema_version -ne 1 -or
        [int]$section.source_fps -ne 30 -or
        @($section.bindings).Count -lt 1 -or
        [int]$section.summary.ready_bindings -ne @($section.bindings).Count
    ) {
        throw "Field texture animation builder published an invalid catalog section."
    }
    foreach ($propertyName in @(
        "reused",
        "godot_stage_repaired",
        "godot_stage_changed"
    )) {
        $property = $buildResult.PSObject.Properties[$propertyName]
        if ($null -eq $property -or $property.Value -isnot [bool]) {
            throw "Field texture animation builder returned an invalid '$propertyName' value."
        }
    }
    return [pscustomobject][ordered]@{
        section = $section
        reused = [bool]$buildResult.reused
        godot_stage_repaired = [bool]$buildResult.godot_stage_repaired
        godot_stage_changed = [bool]$buildResult.godot_stage_changed
    }
}

function Add-FieldTextureAnimationCatalogData {
    param($Catalog, $Section)

    $Catalog | Add-Member -NotePropertyName "field_texture_animations" -NotePropertyValue $Section -Force
    $Catalog.summary | Add-Member `
        -NotePropertyName "field_texture_animation_bindings" `
        -NotePropertyValue ([int]$Section.summary.ready_bindings) `
        -Force
    $Catalog.summary | Add-Member `
        -NotePropertyName "deferred_field_texture_variants" `
        -NotePropertyValue ([int]$Section.summary.deferred_variants) `
        -Force
    $Catalog.summary | Add-Member `
        -NotePropertyName "field_texture_animation_frames" `
        -NotePropertyValue ([int]$Section.summary.generated_unique_frames) `
        -Force
}

function Get-ReadyStatus {
    param($Manifest)

    $resolutions = @(
        @($Manifest.cells) |
            ForEach-Object {
                if ($null -ne $_.PSObject.Properties["area_resolution"]) {
                    [string]$_.area_resolution
                }
                elseif ([bool]$Manifest.matrix.has_headers) {
                    "per_cell_header"
                }
                else {
                    "linked_map_header"
                }
            } |
            Sort-Object -Unique
    )
    if ($resolutions -contains "known_map_reference") {
        return "ready_duplicate_map"
    }
    if ($resolutions -contains "asset_compatibility") {
        return "ready_unique_texture"
    }
    return "ready_header"
}

function Test-GlbFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt 12) {
        return $false
    }
    $stream = [IO.File]::OpenRead($item.FullName)
    try {
        $header = New-Object byte[] 12
        if ($stream.Read($header, 0, 12) -ne 12) {
            return $false
        }
        return [Text.Encoding]::ASCII.GetString($header, 0, 4) -eq "glTF" -and
            [BitConverter]::ToUInt32($header, 4) -eq 2 -and
            [BitConverter]::ToUInt32($header, 8) -eq $item.Length
    }
    finally {
        $stream.Dispose()
    }
}

function Get-StageFileRecords {
    param(
        [string]$RootPath,
        [string[]]$ExcludedRelativePaths = @(),
        [switch]$IgnoreGodotImportSidecars
    )

    $records = @(Get-DspreStageFileRecords `
        -RootPath $RootPath `
        -ExcludedRelativePaths $ExcludedRelativePaths `
        -IgnoreGodotImportSidecars:$IgnoreGodotImportSidecars `
        -Label "All-matrix stage")
    if ($IgnoreGodotImportSidecars) {
        $records = @($records | Where-Object {
            [string]$_.relative_path -notmatch '(?i)\.import~[^/]+\.tmp$'
        })
    }
    return $records
}

function Assert-StageFileRecords {
    param(
        [string]$RootPath,
        [object[]]$ExpectedRecords,
        [string[]]$ExcludedRelativePaths = @(),
        [switch]$IgnoreGodotImportSidecars,
        [string]$Label = "Stage output"
    )

    $expectedByPath = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in @($ExpectedRecords)) {
        $relativePath = ([string]$record.relative_path).Replace('\', '/')
        if (
            [string]::IsNullOrWhiteSpace($relativePath) -or
            [IO.Path]::IsPathRooted($relativePath) -or
            $relativePath -match '(^|/)\.\.(/|$)' -or
            $expectedByPath.ContainsKey($relativePath) -or
            [long]$record.byte_length -lt 0 -or
            [string]$record.sha256 -notmatch '^[0-9a-f]{64}$'
        ) {
            throw "$Label contains an invalid or duplicate file record: $relativePath"
        }
        $expectedByPath.Add($relativePath, $record)
    }
    $actualRecords = @(Get-StageFileRecords `
        -RootPath $RootPath `
        -ExcludedRelativePaths $ExcludedRelativePaths `
        -IgnoreGodotImportSidecars:$IgnoreGodotImportSidecars)
    if ($actualRecords.Count -ne $expectedByPath.Count) {
        throw "$Label file count does not match its completion record."
    }
    foreach ($actual in $actualRecords) {
        $relativePath = [string]$actual.relative_path
        if (-not $expectedByPath.ContainsKey($relativePath)) {
            throw "$Label contains an undeclared file: $relativePath"
        }
        $expected = $expectedByPath[$relativePath]
        if (
            [long]$actual.byte_length -ne [long]$expected.byte_length -or
            [string]$actual.sha256 -ne [string]$expected.sha256
        ) {
            throw "$Label file content does not match its completion record: $relativePath"
        }
    }
    return $actualRecords
}

function Assert-EquivalentStageFileRecords {
    param(
        [object[]]$ExpectedRecords,
        [object[]]$ActualRecords,
        [string]$Label
    )

    $expectedByPath = @{}
    foreach ($record in @($ExpectedRecords)) {
        $key = ([string]$record.relative_path).ToLowerInvariant()
        if ($expectedByPath.ContainsKey($key)) {
            throw "$Label contains a duplicate expected file: $($record.relative_path)"
        }
        $expectedByPath[$key] = $record
    }
    if ($expectedByPath.Count -ne @($ActualRecords).Count) {
        throw "$Label file sets have different counts."
    }
    foreach ($record in @($ActualRecords)) {
        $key = ([string]$record.relative_path).ToLowerInvariant()
        if (-not $expectedByPath.ContainsKey($key)) {
            throw "$Label contains an unexpected file: $($record.relative_path)"
        }
        $expected = $expectedByPath[$key]
        if (
            [long]$record.byte_length -ne [long]$expected.byte_length -or
            [string]$record.sha256 -ne [string]$expected.sha256
        ) {
            throw "$Label contains different file content: $($record.relative_path)"
        }
    }
    return $true
}

function Assert-AreaResolution {
    param($Resolution, [int[]]$SourceMatrixIds, [string]$ExpectedSource, [long]$HeaderTableOffset)

    if ([int]$Resolution.schema_version -ne 1) {
        throw "Unsupported Matrix AreaData resolution schema: $($Resolution.schema_version)"
    }
    $resolutionSource = [IO.Path]::GetFullPath([string]$Resolution.source.dspre_contents)
    if (-not $resolutionSource.Equals($ExpectedSource, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Area resolution source does not match DspreContents. Regenerate without -ReuseAreaResolution."
    }
    $expectedOffset = "0x{0:X}" -f $HeaderTableOffset
    if (-not $expectedOffset.Equals(
        [string]$Resolution.source.header_table_offset,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Area resolution header table offset does not match $expectedOffset. Regenerate without -ReuseAreaResolution."
    }

    $sourceIds = New-Object System.Collections.Generic.HashSet[int]
    foreach ($matrixId in $SourceMatrixIds) {
        $null = $sourceIds.Add([int]$matrixId)
    }
    $variantNames = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    $variantPairs = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    $coveredIds = New-Object System.Collections.Generic.HashSet[int]
    $variantByMatrix = @{}
    $variantGroups = @(@($Resolution.variants) | Group-Object { [int]$_.matrix_id })
    foreach ($group in $variantGroups) {
        $records = @($group.Group)
        $matrixId = [int]$records[0].matrix_id
        if (-not $sourceIds.Contains($matrixId)) {
            throw "Area resolution references a matrix that does not exist: $matrixId"
        }
        if (-not $coveredIds.Add($matrixId)) {
            throw "Area resolution contains duplicate matrix groups: $matrixId"
        }
        $variantByMatrix[$matrixId] = $records
        foreach ($record in $records) {
            $areaId = $record.area_data_id
            if ($null -ne $areaId -and ([int]$areaId -lt 0 -or [int]$areaId -gt 0xFFFF)) {
                throw "Area resolution contains an invalid AreaData ID for matrix $matrixId."
            }
            if ($records.Count -gt 1 -and $null -eq $areaId) {
                throw "Multi-variant matrix $matrixId is missing an AreaData ID."
            }
            if ([string]$record.resolution -notin @(
                "per_cell_header",
                "linked_map_header",
                "known_map_reference",
                "asset_compatibility"
            )) {
                throw "Area resolution contains an unknown resolution for matrix $matrixId`: $($record.resolution)"
            }
            $expectedVariant = if ($records.Count -gt 1) {
                "matrix_{0:D4}_area_{1:D4}" -f $matrixId, [int]$areaId
            }
            else {
                "matrix_{0:D4}" -f $matrixId
            }
            $variantName = [string]$record.variant
            if ($variantName -notmatch '^matrix_\d{4}(_area_\d{4})?$' -or $variantName -ne $expectedVariant) {
                throw "Unsafe or inconsistent matrix variant '$variantName'; expected '$expectedVariant'."
            }
            if (-not $variantNames.Add($variantName)) {
                throw "Area resolution contains duplicate variant '$variantName'."
            }
            $pairKey = if ($null -eq $areaId) { "$matrixId|null" } else { "$matrixId|$([int]$areaId)" }
            if (-not $variantPairs.Add($pairKey)) {
                throw "Area resolution contains duplicate matrix/AreaData pair '$pairKey'."
            }
        }
    }

    $overrideIds = New-Object System.Collections.Generic.HashSet[int]
    foreach ($override in @($Resolution.overrides)) {
        $matrixId = [int]$override.matrix_id
        if (-not $overrideIds.Add($matrixId)) {
            throw "Area resolution contains duplicate override matrix $matrixId."
        }
        if (-not $variantByMatrix.ContainsKey($matrixId)) {
            throw "Area resolution override references a non-runnable matrix: $matrixId"
        }
        $records = @($variantByMatrix[$matrixId])
        if ($records.Count -ne 1) {
            throw "Area resolution override matrix $matrixId must have one canonical variant."
        }
        $variant = $records[0]
        if (
            $null -eq $variant.area_data_id -or
            [int]$variant.area_data_id -ne [int]$override.area_data_id -or
            [string]$variant.resolution -ne [string]$override.resolution -or
            [string]$override.resolution -notin @("known_map_reference", "asset_compatibility")
        ) {
            throw "Area resolution override disagrees with canonical variant for matrix $matrixId."
        }
    }
    foreach ($matrixId in @($variantByMatrix.Keys)) {
        $records = @($variantByMatrix[$matrixId])
        if (
            $records.Count -eq 1 -and
            [string]$records[0].resolution -in @("known_map_reference", "asset_compatibility") -and
            -not $overrideIds.Contains([int]$matrixId)
        ) {
            throw "Resolved orphan matrix $matrixId has no matching override record."
        }
    }

    $unresolvedIds = New-Object System.Collections.Generic.HashSet[int]
    foreach ($record in @($Resolution.unresolved)) {
        $matrixId = [int]$record.matrix_id
        if (-not $sourceIds.Contains($matrixId)) {
            throw "Area resolution marks a matrix unresolved that does not exist: $matrixId"
        }
        if (-not $unresolvedIds.Add($matrixId)) {
            throw "Area resolution contains duplicate unresolved matrix $matrixId."
        }
        if ($coveredIds.Contains($matrixId)) {
            throw "Area resolution marks matrix $matrixId both ready and unresolved."
        }
        $null = $coveredIds.Add($matrixId)
    }
    if ($coveredIds.Count -ne $sourceIds.Count) {
        $missing = @($SourceMatrixIds | Where-Object { -not $coveredIds.Contains([int]$_) })
        throw "Area resolution does not cover every source matrix. Missing: $($missing -join ', ')"
    }
    if ([int]$Resolution.summary.matrices -ne $sourceIds.Count -or
        [int]$Resolution.summary.ready_variants -ne $variantNames.Count -or
        [int]$Resolution.summary.resolved_orphans -ne $overrideIds.Count -or
        [int]$Resolution.summary.unresolved_orphans -ne $unresolvedIds.Count) {
        throw "Area resolution summary does not match its matrix records."
    }
}

function Test-DedupeComplete {
    param(
        [string]$SourceManifest,
        [string]$DestinationRoot,
        [string]$ExpectedVariant,
        [int]$ExpectedMatrixId,
        $ExpectedAreaDataId,
        [string]$ExpectedDedupeToolSha256,
        [switch]$MarkerOnly
    )

    $DestinationRoot = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
    $destinationPrefix = $DestinationRoot + '\'
    $markerPath = Join-Path $DestinationRoot ".dedupe-complete.json"
    $manifestPath = Join-Path $DestinationRoot "manifest.json"
    $summaryPath = Join-Path $DestinationRoot "summary.json"
    $catalogPath = Join-Path $DestinationRoot "material_catalog.json"
    foreach ($path in @($SourceManifest, $markerPath, $manifestPath, $summaryPath, $catalogPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            return $false
        }
    }
    try {
        $marker = [IO.File]::ReadAllText($markerPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $sourceManifestDocument = [IO.File]::ReadAllText(
            $SourceManifest,
            [Text.Encoding]::UTF8
        ) | ConvertFrom-Json
        $summary = [IO.File]::ReadAllText($summaryPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $catalog = [IO.File]::ReadAllText($catalogPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $catalogMaterials = @($catalog.materials)
        if (
            [int]$marker.schema_version -ne 2 -or
            [string]$marker.dedupe_tool_sha256 -ne $ExpectedDedupeToolSha256
        ) {
            return $false
        }
        if (
            [int]$sourceManifestDocument.schema_version -ne 3 -or
            [int]$manifest.schema_version -ne 4 -or
            [int]$sourceManifestDocument.field_features.schema_version -ne 1 -or
            [int]$manifest.field_features.schema_version -ne 1 -or
            ($sourceManifestDocument.field_features | ConvertTo-Json -Depth 30 -Compress) -ne
            ($manifest.field_features | ConvertTo-Json -Depth 30 -Compress) -or
            (ConvertTo-DspreMapAnimationContractJson $sourceManifestDocument) -ne
            (ConvertTo-DspreMapAnimationContractJson $manifest)
        ) {
            return $false
        }
        if ($MarkerOnly) {
            $manifestVariant = if ($null -ne $manifest.matrix.PSObject.Properties["variant"]) {
                [string]$manifest.matrix.variant
            }
            else {
                "matrix_{0:D4}" -f [int]$manifest.matrix.id
            }
            $manifestArea = if ($null -ne $manifest.matrix.PSObject.Properties["area_data_id"]) {
                $manifest.matrix.area_data_id
            }
            else {
                $null
            }
            $areaMatches = ($null -eq $ExpectedAreaDataId -and $null -eq $manifestArea) -or
                ($null -ne $ExpectedAreaDataId -and $null -ne $manifestArea -and
                    [int]$ExpectedAreaDataId -eq [int]$manifestArea)
            return @($marker.files).Count -gt 0 -and
                [int]$catalog.schema_version -eq 1 -and
                [string]$marker.source_manifest_sha256 -eq (Get-FileHash -LiteralPath $SourceManifest -Algorithm SHA256).Hash.ToLowerInvariant() -and
                [string]$marker.output_manifest_sha256 -eq (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -and
                [int]$manifest.matrix.id -eq $ExpectedMatrixId -and
                $manifestVariant -eq $ExpectedVariant -and
                $areaMatches -and
                [int]$manifest.summary.failed -eq 0 -and
                [int]$marker.glbs -eq [int]$summary.glbs -and
                [int]$summary.glbs -eq [int]$catalog.summary.glbs -and
                [int]$marker.unique_images -eq [int]$summary.unique_images -and
                [int]$summary.unique_images -eq [int]$catalog.summary.unique_images -and
                [int]$marker.unique_materials -eq $catalogMaterials.Count -and
                [int]$summary.unique_materials -eq $catalogMaterials.Count -and
                [int]$catalog.summary.unique_materials -eq $catalogMaterials.Count
        }
        $null = Assert-DspreCollisionManifest `
            -Manifest $sourceManifestDocument `
            -Label "Raw source for $ExpectedVariant" `
            -ExpectedManifestSchema 3
        $null = Assert-DspreCollisionManifest `
            -Manifest $manifest `
            -Label "Deduplicated destination $ExpectedVariant" `
            -ExpectedManifestSchema 4
        $materialKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
        foreach ($material in $catalogMaterials) {
            if (
                [string]$material.key -notmatch '^mat_[0-9a-f]{64}$' -or
                -not $materialKeys.Add([string]$material.key) -or
                $null -eq $material.PSObject.Properties["signature"] -or
                $material.signature -isnot [pscustomobject]
            ) {
                return $false
            }
        }
        $validatedFileRecords = @(Assert-StageFileRecords `
            -RootPath $DestinationRoot `
            -ExpectedRecords @($marker.files) `
            -ExcludedRelativePaths @(".dedupe-complete.json") `
            -Label "Deduplicated destination $ExpectedVariant")
        $fileRecordByPath = @{}
        foreach ($record in $validatedFileRecords) {
            $fileRecordByPath[([string]$record.relative_path).ToLowerInvariant()] = $record
        }

        $actualGlbFiles = @(
            Get-ChildItem -LiteralPath $DestinationRoot -Recurse -Filter "*.glb" -File
        )
        $actualGlbPaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
        foreach ($glb in $actualGlbFiles) {
            if (-not (Test-GlbFile $glb.FullName) -or -not $actualGlbPaths.Add($glb.FullName)) {
                return $false
            }
        }
        $declaredGlbs = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
        foreach ($asset in @($manifest.assets.terrain) + @($manifest.assets.buildings)) {
            foreach ($relativeGlb in @($asset.output_glbs)) {
                $relativePath = [string]$relativeGlb
                $fullPath = [IO.Path]::GetFullPath(
                    (Join-Path $DestinationRoot $relativePath.Replace('/', '\'))
                )
                if (
                    [IO.Path]::IsPathRooted($relativePath) -or
                    -not $fullPath.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase) -or
                    -not $declaredGlbs.Add($fullPath) -or
                    -not $actualGlbPaths.Contains($fullPath)
                ) {
                    return $false
                }
            }
        }
        if ($declaredGlbs.Count -ne $actualGlbPaths.Count) {
            return $false
        }

        $catalogGlbs = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
        foreach ($asset in @($catalog.assets)) {
            $fullPath = [IO.Path]::GetFullPath(
                (Join-Path $DestinationRoot ([string]$asset.glb).Replace('/', '\'))
            )
            if (
                -not $fullPath.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase) -or
                -not $catalogGlbs.Add($fullPath) -or
                -not $declaredGlbs.Contains($fullPath)
            ) {
                return $false
            }
            $materialBindings = @($asset.materials)
            $boundMaterialKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
            foreach ($binding in $materialBindings) {
                $boundKey = [string]$binding.material_key
                if (-not $materialKeys.Contains($boundKey)) {
                    return $false
                }
                $null = $boundMaterialKeys.Add($boundKey)
            }
            if (
                $materialBindings.Count -eq 0 -or
                [int]$asset.output_material_count -le 0 -or
                $boundMaterialKeys.Count -ne [int]$asset.output_material_count
            ) {
                return $false
            }
        }
        if ($catalogGlbs.Count -ne $declaredGlbs.Count) {
            return $false
        }

        $manifestVariant = if ($null -ne $manifest.matrix.PSObject.Properties["variant"]) {
            [string]$manifest.matrix.variant
        }
        else {
            "matrix_{0:D4}" -f [int]$manifest.matrix.id
        }
        $manifestArea = if ($null -ne $manifest.matrix.PSObject.Properties["area_data_id"]) {
            $manifest.matrix.area_data_id
        }
        else {
            $null
        }
        $areaMatches = ($null -eq $ExpectedAreaDataId -and $null -eq $manifestArea) -or
            ($null -ne $ExpectedAreaDataId -and $null -ne $manifestArea -and
                [int]$ExpectedAreaDataId -eq [int]$manifestArea)
        $textureRoot = Join-Path $DestinationRoot "shared\textures"
        $actualPngs = @(
            Get-ChildItem -LiteralPath $textureRoot -Filter "*.png" -File -ErrorAction Stop
        )
        $allPngs = @(Get-ChildItem -LiteralPath $DestinationRoot -Recurse -Filter "*.png" -File)
        if ($actualPngs.Count -ne $allPngs.Count) {
            return $false
        }
        $actualPngPaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
        foreach ($png in $actualPngs) {
            $null = $actualPngPaths.Add($png.FullName)
        }
        $catalogImages = @($catalog.images)
        $catalogPngPaths = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
        foreach ($image in $catalogImages) {
            $imagePath = [IO.Path]::GetFullPath(
                (Join-Path $DestinationRoot ([string]$image.relative_path).Replace('/', '\'))
            )
            $sha256 = [string]$image.sha256
            $imageRelativePath = $imagePath.Substring($destinationPrefix.Length).Replace('\', '/')
            $imageRecordKey = $imageRelativePath.ToLowerInvariant()
            if (
                -not $imagePath.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase) -or
                -not $catalogPngPaths.Add($imagePath) -or
                -not $actualPngPaths.Contains($imagePath) -or
                -not $fileRecordByPath.ContainsKey($imageRecordKey) -or
                $sha256 -notmatch '^[0-9a-f]{64}$' -or
                [string]$image.key -ne "img_$sha256" -or
                [long]$image.byte_length -ne [long]$fileRecordByPath[$imageRecordKey].byte_length -or
                [string]$fileRecordByPath[$imageRecordKey].sha256 -ne $sha256
            ) {
                return $false
            }
        }
        if ($catalogPngPaths.Count -ne $actualPngPaths.Count) {
            return $false
        }
        return [int]$catalog.schema_version -eq 1 -and
            [string]$marker.source_manifest_sha256 -eq (Get-FileHash -LiteralPath $SourceManifest -Algorithm SHA256).Hash.ToLowerInvariant() -and
            [string]$marker.output_manifest_sha256 -eq (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -and
            [int]$manifest.matrix.id -eq $ExpectedMatrixId -and
            $manifestVariant -eq $ExpectedVariant -and
            $areaMatches -and
            [int]$manifest.summary.failed -eq 0 -and
            [int]$marker.glbs -eq $actualGlbPaths.Count -and
            [int]$summary.glbs -eq $actualGlbPaths.Count -and
            [int]$catalog.summary.glbs -eq $actualGlbPaths.Count -and
            [int]$marker.unique_images -eq $actualPngs.Count -and
            [int]$summary.unique_images -eq $actualPngs.Count -and
            [int]$catalog.summary.unique_images -eq $actualPngs.Count -and
            [int]$manifest.material_dedupe.unique_images -eq $actualPngs.Count -and
            $catalogImages.Count -eq $actualPngs.Count -and
            [int]$marker.unique_materials -eq $catalogMaterials.Count -and
            [int]$summary.unique_materials -eq $catalogMaterials.Count -and
            [int]$catalog.summary.unique_materials -eq $catalogMaterials.Count -and
            [int]$manifest.material_dedupe.unique_materials -eq $catalogMaterials.Count
    }
    catch {
        return $false
    }
}

function Test-SyncComplete {
    param(
        [string]$SourceManifest,
        [string]$DestinationRoot,
        [string]$ExpectedVariant,
        [int]$ExpectedMatrixId,
        $ExpectedAreaDataId,
        [string]$ExpectedDedupeToolSha256,
        [string]$ExpectedSyncToolSha256,
        [switch]$MarkerOnly
    )

    $sourceRoot = Split-Path -Parent $SourceManifest
    $sourceDedupeMarkerPath = Join-Path $sourceRoot ".dedupe-complete.json"
    $destinationManifest = Join-Path $DestinationRoot "manifest.json"
    $markerPath = Join-Path $DestinationRoot ".sync-complete.json"
    if (
        -not (Test-Path -LiteralPath $SourceManifest -PathType Leaf) -or
        -not (Test-Path -LiteralPath $sourceDedupeMarkerPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $destinationManifest -PathType Leaf) -or
        -not (Test-Path -LiteralPath $markerPath -PathType Leaf)
    ) {
        return $false
    }
    try {
        $marker = [IO.File]::ReadAllText($markerPath, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        $sourceDedupeMarker = [IO.File]::ReadAllText(
            $sourceDedupeMarkerPath,
            [Text.Encoding]::UTF8
        ) | ConvertFrom-Json
        $destination = [IO.File]::ReadAllText($destinationManifest, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        $source = [IO.File]::ReadAllText($SourceManifest, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        $destinationVariant = if ($null -ne $destination.matrix.PSObject.Properties["variant"]) {
            [string]$destination.matrix.variant
        }
        else {
            "matrix_{0:D4}" -f [int]$destination.matrix.id
        }
        $sourceHash = (Get-FileHash -LiteralPath $SourceManifest -Algorithm SHA256).Hash.ToLowerInvariant()
        $destinationHash = (Get-FileHash -LiteralPath $destinationManifest -Algorithm SHA256).Hash.ToLowerInvariant()
        $destinationArea = if ($null -ne $destination.matrix.PSObject.Properties["area_data_id"]) {
            $destination.matrix.area_data_id
        }
        else {
            $null
        }
        $areaMatches = ($null -eq $ExpectedAreaDataId -and $null -eq $destinationArea) -or
            ($null -ne $ExpectedAreaDataId -and $null -ne $destinationArea -and
                [int]$ExpectedAreaDataId -eq [int]$destinationArea)
        if (
            [int]$sourceDedupeMarker.schema_version -ne 2 -or
            [string]$sourceDedupeMarker.dedupe_tool_sha256 -ne $ExpectedDedupeToolSha256 -or
            [string]$sourceDedupeMarker.output_manifest_sha256 -ne $sourceHash -or
            [int]$marker.schema_version -ne 2 -or
            [string]$marker.dedupe_tool_sha256 -ne $ExpectedDedupeToolSha256 -or
            [string]$marker.sync_tool_sha256 -ne $ExpectedSyncToolSha256 -or
            [int]$marker.matrix_id -ne $ExpectedMatrixId -or
            [string]$marker.variant -ne $ExpectedVariant -or
            [int]$destination.matrix.id -ne $ExpectedMatrixId -or
            $destinationVariant -ne $ExpectedVariant -or
            -not $areaMatches -or
            [string]$marker.source_manifest_sha256 -ne $sourceHash -or
            $destinationHash -ne $sourceHash
        ) {
            return $false
        }
        if ($MarkerOnly) {
            return [int]$source.schema_version -eq 4 -and
                [int]$destination.schema_version -eq 4 -and
                @($marker.files).Count -gt 0 -and
                [int]$marker.glbs -gt 0 -and
                [int]$marker.textures -ge 0
        }
        $null = Assert-DspreCollisionManifest `
            -Manifest $source `
            -Label "Deduplicated source $ExpectedVariant" `
            -ExpectedManifestSchema 4
        $null = Assert-DspreCollisionManifest `
            -Manifest $destination `
            -Label "Godot destination $ExpectedVariant" `
            -ExpectedManifestSchema 4
        $destinationRecords = @(Assert-StageFileRecords `
            -RootPath $DestinationRoot `
            -ExpectedRecords @($marker.files) `
            -ExcludedRelativePaths @(".sync-complete.json") `
            -IgnoreGodotImportSidecars `
            -Label "Godot destination $ExpectedVariant")
        $sourceDedupeMarkerItem = Get-Item -LiteralPath $sourceDedupeMarkerPath
        $sourceRecords = @(
            @($sourceDedupeMarker.files) + @([pscustomobject][ordered]@{
                relative_path = ".dedupe-complete.json"
                byte_length = [long]$sourceDedupeMarkerItem.Length
                sha256 = (Get-FileHash `
                    -LiteralPath $sourceDedupeMarkerPath `
                    -Algorithm SHA256).Hash.ToLowerInvariant()
            }) | Sort-Object { [string]$_.relative_path }
        )
        $null = Assert-EquivalentStageFileRecords `
            -ExpectedRecords $sourceRecords `
            -ActualRecords $destinationRecords `
            -Label "Godot destination $ExpectedVariant"

        $actualGlbFiles = @(
            Get-ChildItem -LiteralPath $DestinationRoot -Recurse -Filter "*.glb" -File
        )
        foreach ($glb in $actualGlbFiles) {
            if (-not (Test-GlbFile $glb.FullName)) {
                return $false
            }
        }
        $textureRoot = Join-Path $DestinationRoot "shared\textures"
        $actualTextures = @(
            Get-ChildItem -LiteralPath $textureRoot -Filter "*.png" -File
        ).Count
        return $actualGlbFiles.Count -eq [int]$marker.glbs -and
            $actualTextures -eq [int]$marker.textures
    }
    catch {
        return $false
    }
}

function Test-RawMarkerCurrent {
    param(
        [string]$DestinationRoot,
        [string]$ExpectedVariant,
        [int]$ExpectedMatrixId,
        $ExpectedAreaDataId,
        [string]$ExpectedDspreSourceSha256,
        [string]$ExpectedExporterSha256,
        [string]$ExpectedSupportToolSha256,
        [string]$ExpectedApiculaSha256,
        [string]$ExpectedAreaResolutionSha256
    )

    $manifestPath = Join-Path $DestinationRoot "manifest.json"
    $summaryPath = Join-Path $DestinationRoot "summary.json"
    $markerPath = Join-Path $DestinationRoot ".export-complete.json"
    foreach ($path in @($manifestPath, $summaryPath, $markerPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            return $false
        }
    }
    try {
        $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        $summary = [IO.File]::ReadAllText($summaryPath, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        $marker = [IO.File]::ReadAllText($markerPath, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        if (
            [int]$manifest.schema_version -ne 3 -or
            [int]$manifest.field_features.schema_version -ne 1
        ) {
            return $false
        }
        $manifestVariant = if ($null -ne $manifest.matrix.PSObject.Properties["variant"]) {
            [string]$manifest.matrix.variant
        }
        else {
            "matrix_{0:D4}" -f [int]$manifest.matrix.id
        }
        $manifestArea = if ($null -ne $manifest.matrix.PSObject.Properties["area_data_id"]) {
            $manifest.matrix.area_data_id
        }
        else {
            $null
        }
        $areaMatches = ($null -eq $ExpectedAreaDataId -and $null -eq $manifestArea) -or
            ($null -ne $ExpectedAreaDataId -and $null -ne $manifestArea -and
                [int]$ExpectedAreaDataId -eq [int]$manifestArea)
        return (Assert-DspreRawExportMarker `
            -Marker $marker `
            -ExpectedMatrixId $ExpectedMatrixId `
            -ExpectedVariant $ExpectedVariant `
            -ExpectedAreaDataId $ExpectedAreaDataId `
            -ExpectedDspreSourceSha256 $ExpectedDspreSourceSha256 `
            -ExpectedExporterSha256 $ExpectedExporterSha256 `
            -ExpectedSupportToolSha256 $ExpectedSupportToolSha256 `
            -ExpectedApiculaSha256 $ExpectedApiculaSha256 `
            -ExpectedAreaResolutionSha256 $ExpectedAreaResolutionSha256 `
            -ExpectedManifestSha256 (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() `
            -ExpectedOccupiedCells @($manifest.cells).Count `
            -ExpectedCollisionAssets @($manifest.collision_assets).Count `
            -Label "Raw destination $ExpectedVariant marker") -and
            @($marker.files).Count -gt 0 -and
            [int]$summary.failed -eq 0 -and
            [int]$summary.warp_events -eq [int]$manifest.field_features.warp_count -and
            [int]$summary.ordinary_warps -eq [int]$manifest.field_features.ordinary_warp_count -and
            [int]$summary.special_returns -eq [int]$manifest.field_features.special_return_count -and
            [int]$summary.dynamic_warps -eq [int]$manifest.field_features.dynamic_warp_count -and
            [int]$manifest.matrix.id -eq $ExpectedMatrixId -and
            $manifestVariant -eq $ExpectedVariant -and
            $areaMatches
    }
    catch {
        return $false
    }
}

function Assert-AllDestinationStagesCurrent {
    param(
        [object[]]$Variants,
        [string]$RawRoot,
        [string]$DedupRoot,
        [string]$GodotRoot,
        [string]$ExpectedDspreSourceSha256,
        [string]$ExpectedExporterSha256,
        [string]$ExpectedSupportToolSha256,
        [string]$ExpectedDedupeToolSha256,
        [string]$ExpectedSyncToolSha256,
        [string]$ExpectedApiculaSha256,
        [string]$ExpectedAreaResolutionSha256
    )

    $expectedKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    foreach ($variantRecord in @($Variants)) {
        $variantName = [string]$variantRecord.variant
        if (
            $variantName -notmatch '^matrix_\d{4}(_area_\d{4})?$' -or
            -not $expectedKeys.Add($variantName)
        ) {
            throw "Final destination validation received an invalid or duplicate variant: $variantName"
        }
    }
    if ($expectedKeys.Count -ne @($Variants).Count) {
        throw "Final destination validation did not cover every expected variant."
    }

    $validatedRaw = 0
    $validatedDedupe = 0
    $validatedSync = 0
    foreach ($variantRecord in @($Variants)) {
        $variantName = [string]$variantRecord.variant
        $matrixId = [int]$variantRecord.matrix_id
        $rawManifestPath = Join-Path $RawRoot "$variantName\manifest.json"
        $rawVariantRoot = Join-Path $RawRoot $variantName
        $dedupVariantRoot = Join-Path $DedupRoot $variantName
        $dedupManifestPath = Join-Path $dedupVariantRoot "manifest.json"
        $godotVariantRoot = Join-Path $GodotRoot $variantName
        if (-not (Test-RawMarkerCurrent `
            $rawVariantRoot `
            $variantName `
            $matrixId `
            $variantRecord.area_data_id `
            $ExpectedDspreSourceSha256 `
            $ExpectedExporterSha256 `
            $ExpectedSupportToolSha256 `
            $ExpectedApiculaSha256 `
            $ExpectedAreaResolutionSha256
        )) {
            throw "Final destination validation found a stale raw marker: $variantName"
        }
        $validatedRaw++
        if (-not (Test-DedupeComplete `
            $rawManifestPath `
            $dedupVariantRoot `
            $variantName `
            $matrixId `
            $variantRecord.area_data_id `
            $ExpectedDedupeToolSha256 `
            -MarkerOnly
        )) {
            throw "Final destination validation found stale dedupe output: $variantName"
        }
        $validatedDedupe++
        if (-not (Test-SyncComplete `
            $dedupManifestPath `
            $godotVariantRoot `
            $variantName `
            $matrixId `
            $variantRecord.area_data_id `
            $ExpectedDedupeToolSha256 `
            $ExpectedSyncToolSha256 `
            -MarkerOnly
        )) {
            throw "Final destination validation found stale Godot sync output: $variantName"
        }
        $validatedSync++
    }
    if (
        $validatedRaw -ne $expectedKeys.Count -or
        $validatedDedupe -ne $expectedKeys.Count -or
        $validatedSync -ne $expectedKeys.Count
    ) {
        throw "Final destination stage validation count does not match the expected variants."
    }
	return $expectedKeys.Count
}

function Get-UnexpectedMatrixDestinations {
	param(
		[object[]]$Variants,
		[string]$RootPath,
		[string]$AllowedRoot,
		[string]$Label
	)

	$expectedKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
	foreach ($variantRecord in @($Variants)) {
		$variantName = [string]$variantRecord.variant
		if (-not $expectedKeys.Add($variantName)) {
			throw "$Label received a duplicate expected variant: $variantName"
		}
	}

	$staleDirectories = New-Object System.Collections.Generic.List[string]
	foreach ($item in @(Get-ChildItem -LiteralPath $RootPath -Directory -Force -ErrorAction Stop)) {
		if ($item.Name -notmatch '^matrix_\d{4}(_area_\d{4})?$') {
			continue
		}
		if ($expectedKeys.Contains($item.Name)) {
			continue
		}
		$safePath = Assert-DspreSafeRecursiveDeletePath `
			-Path $item.FullName `
			-AllowedRoot $AllowedRoot
		$null = Assert-DspreTreeHasNoReparsePoints `
			-RootPath $safePath `
			-Label "$Label stale destination"
		$staleDirectories.Add($safePath)
	}

	return @($staleDirectories)
}

if ([string]::IsNullOrWhiteSpace($DspreContents)) {
    $existingManifest = Join-Path $rawRoot "matrix_0000\manifest.json"
    if (Test-Path -LiteralPath $existingManifest -PathType Leaf) {
        $existing = [IO.File]::ReadAllText($existingManifest, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        $candidate = [string]$existing.source.dspre_contents
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $DspreContents = $candidate
        }
    }
}
if ([string]::IsNullOrWhiteSpace($DspreContents)) {
    throw "Pass -DspreContents or generate matrix_0000 first so the source can be recovered."
}

$DspreContents = Resolve-ExistingDirectory $DspreContents "DSPRE contents directory"
if ($FieldTextureAnimationsOnly) {
    if ($MatrixIds.Count -gt 0) {
        throw "FieldTextureAnimationsOnly cannot be combined with MatrixIds."
    }
    foreach ($catalogPath in @($generatedCatalogPath, $godotCatalogPath)) {
        if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
            throw "Field texture fast update requires the existing complete catalog: $catalogPath"
        }
        $catalogItem = Get-Item -LiteralPath $catalogPath -Force
        if (($catalogItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Field texture fast update refuses a reparse-point catalog: $catalogPath"
        }
    }
    if ((Get-DspreToolFileFingerprint -Path $generatedCatalogPath) -ne
        (Get-DspreToolFileFingerprint -Path $godotCatalogPath)) {
        throw "Field texture fast update requires byte-identical generated and Godot catalogs."
    }
    $existingCatalogJson = [IO.File]::ReadAllText($generatedCatalogPath, [Text.Encoding]::UTF8)
    $existingCatalog = $existingCatalogJson | ConvertFrom-Json
    if (
        [int]$existingCatalog.schema_version -ne 3 -or
        @($existingCatalog.destinations).Count -ne 278
    ) {
        throw "Field texture fast update requires the complete schema-3 matrix catalog."
    }
    $fieldTextureTransactionResult = Invoke-MatrixCatalogWithdrawalTransaction `
        -GeneratedPath $generatedCatalogPath `
        -GodotCatalogPath $godotCatalogPath `
        -Operation {
            $fieldTextureBuild = Invoke-FieldTextureAnimationBuild `
                -SourceRoot $DspreContents `
                -Force:$RebuildExisting
            $fieldTextureSection = $fieldTextureBuild.section
            $catalogDataUnchanged = Test-FieldTextureCatalogDataEquivalent `
                -Catalog $existingCatalog `
                -Section $fieldTextureSection
            if ($catalogDataUnchanged) {
                $catalogJson = $existingCatalogJson
            }
            else {
                Add-FieldTextureAnimationCatalogData `
                    -Catalog $existingCatalog `
                    -Section $fieldTextureSection
                $existingCatalog.generated_utc = [DateTime]::UtcNow.ToString("o")
                $catalogJson = $existingCatalog | ConvertTo-Json -Depth 20
            }
            Publish-MatrixCatalogPair `
                -GeneratedPath $generatedCatalogPath `
                -GodotPath $godotCatalogPath `
                -Json $catalogJson `
                -Encoding $utf8NoBom
            $null = Invoke-ProjectScript (Join-Path $PSScriptRoot "validate_dspre_matrix_catalog.ps1") @{
                ProjectRoot = $workspaceRoot
                FieldTextureAnimationsOnly = $true
            }
            return [pscustomobject][ordered]@{
                build = $fieldTextureBuild
                section = $fieldTextureSection
            }
        }
    if (
        $null -eq $fieldTextureTransactionResult -or
        $null -eq $fieldTextureTransactionResult.PSObject.Properties["build"] -or
        $null -eq $fieldTextureTransactionResult.PSObject.Properties["section"]
    ) {
        throw "Field texture catalog transaction did not return its build state."
    }
    Write-Host "Field texture animation catalog update complete."
    if (-not $SkipGodotImport) {
        $importStatus = Get-FieldTextureAnimationImportStatus `
            -Section $fieldTextureTransactionResult.section `
            -AssetRoot $platinumRoot
        $importPlan = Get-FieldTextureFastImportPlan `
            -BuildResult $fieldTextureTransactionResult.build `
            -ImportStatus $importStatus
        if ($importPlan.no_op) {
            Write-Host "Field texture animation PNGs and import sidecars are unchanged; Godot import skipped."
        }
        else {
            $GodotPath = Resolve-ExistingFile $GodotPath "Godot console executable"
            if ($importPlan.initial_import) {
                & $GodotPath --headless --path $projectRoot --import
                if ($LASTEXITCODE -ne 0) {
                    throw "Field texture animation import failed with exit code $LASTEXITCODE."
                }
            }
            if ($importPlan.configure_textures) {
                Invoke-ProjectScript (Join-Path $PSScriptRoot "configure_dspre_godot_textures.ps1") @{
                    ProjectRoot = $projectRoot
                    GodotPath = $GodotPath
                    RepairInvalidOnly = $true
                    FieldTextureAnimationsOnly = $true
                }
            }
        }
    }
    return
}
$ApiculaPath = Resolve-ExistingFile $ApiculaPath "apicula.exe"
$matricesRoot = Resolve-ExistingDirectory (Join-Path $DspreContents "unpacked\matrices") "Matrix directory"
if ($MaxParallel -lt 1) {
    throw "MaxParallel must be at least 1."
}

$allMatrixIds = @(
    Get-ChildItem -LiteralPath $matricesRoot -File |
        Where-Object { $_.Name -match '^\d{4}$' } |
        ForEach-Object { [int]$_.Name } |
        Sort-Object -Unique
)
if ($allMatrixIds.Count -eq 0) {
    throw "No numeric matrix files were found: $matricesRoot"
}

if (-not $ReuseAreaResolution -or -not (Test-Path -LiteralPath $resolutionPath -PathType Leaf)) {
    Invoke-ProjectScript (Join-Path $PSScriptRoot "resolve_dspre_matrix_areas.ps1") @{
        DspreContents = $DspreContents
        ApiculaPath = $ApiculaPath
        OutputPath = $resolutionPath
        AllowUnresolved = $true
    }
}
$resolution = [IO.File]::ReadAllText($resolutionPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
Assert-AreaResolution $resolution $allMatrixIds $DspreContents 0xE56F0
$batchExporterPath = Resolve-ExistingFile (Join-Path $PSScriptRoot "dspre_batch_export.ps1") "DSPRE batch exporter"
$supportToolPath = Resolve-ExistingFile (Join-Path $PSScriptRoot "dspre_collision_support.ps1") "DSPRE collision support tool"
$dedupeToolPath = Resolve-ExistingFile (Join-Path $PSScriptRoot "dedupe_dspre_materials.ps1") "DSPRE material dedupe tool"
$syncToolPath = Resolve-ExistingFile (Join-Path $PSScriptRoot "sync_dspre_godot_assets.ps1") "DSPRE Godot sync tool"
Write-Host "Fingerprinting DSPRE contents once for all matrix variants..."
$dspreSourceSha256 = Get-DspreContentFingerprint -RootPath $DspreContents
$exporterSha256 = Get-DspreToolFileFingerprint -Path $batchExporterPath
$supportToolSha256 = Get-DspreSupportBundleFingerprint -ToolsRoot $PSScriptRoot
$dedupeToolSha256 = Get-DspreToolFileFingerprint -Path $dedupeToolPath
$syncToolSha256 = Get-DspreToolFileFingerprint -Path $syncToolPath
$apiculaSha256 = Get-DspreToolFileFingerprint -Path $ApiculaPath
$areaResolutionSha256 = Get-DspreAreaResolutionFingerprint -Path $resolutionPath
$arm9Path = Resolve-ExistingFile (Join-Path $DspreContents "arm9\arm9.bin") "ARM9 binary"
$mapNamesPath = Resolve-ExistingFile `
    (Join-Path $DspreContents "files\fielddata\maptable\mapname.bin") `
    "Map names table"
$sourceHeaderCount = [int]((Get-Item -LiteralPath $mapNamesPath).Length / 16)
$sourceMapHeaders = @(ConvertFrom-DspreMapHeaderTable `
    -Arm9Bytes ([IO.File]::ReadAllBytes($arm9Path)) `
    -Offset 0xE56F0 `
    -HeaderCount $sourceHeaderCount)
if ($sourceMapHeaders.Count -ne 593) {
    throw "The Platinum source must contain exactly 593 MapHeaders; found $($sourceMapHeaders.Count)."
}
$unresolvedById = @{}
foreach ($record in @($resolution.unresolved)) {
    $unresolvedById[[int]$record.matrix_id] = $record
}

$requestedIds = @(
    if ($MatrixIds.Count -gt 0) {
        $MatrixIds | Sort-Object -Unique
    }
    else {
        $allMatrixIds
    }
)
foreach ($matrixId in $requestedIds) {
    if ($matrixId -notin $allMatrixIds) {
        throw "Requested matrix does not exist: $matrixId"
    }
}
$allVariants = @($resolution.variants)
$readyRequestedVariants = @(
    $allVariants | Where-Object { [int]$_.matrix_id -in $requestedIds }
)
$skippedRequestedIds = @($requestedIds | Where-Object { $unresolvedById.ContainsKey($_) })

if ($MatrixIds.Count -gt 0) {
    $null = Assert-DspreUnrequestedRawMarkersCurrent `
        -Variants $allVariants `
        -RequestedMatrixIds $requestedIds `
        -RawRoot $rawRoot `
        -ExpectedDspreSourceSha256 $dspreSourceSha256 `
        -ExpectedExporterSha256 $exporterSha256 `
        -ExpectedSupportToolSha256 $supportToolSha256 `
        -ExpectedApiculaSha256 $apiculaSha256 `
        -ExpectedAreaResolutionSha256 $areaResolutionSha256

    $staleDownstreamVariants = New-Object System.Collections.Generic.List[string]
    foreach ($variantRecord in $allVariants) {
        $matrixId = [int]$variantRecord.matrix_id
        if ($matrixId -in $requestedIds) {
            continue
        }
        $variantName = [string]$variantRecord.variant
        $rawManifestPath = Join-Path $rawRoot "$variantName\manifest.json"
        $dedupVariantRoot = Join-Path $dedupRoot $variantName
        $dedupManifestPath = Join-Path $dedupVariantRoot "manifest.json"
        $godotVariantRoot = Join-Path $platinumRoot $variantName
        if (-not (Test-DedupeComplete `
            $rawManifestPath `
            $dedupVariantRoot `
            $variantName `
            $matrixId `
            $variantRecord.area_data_id `
            $dedupeToolSha256
        )) {
            $staleDownstreamVariants.Add("$variantName (dedupe)")
            continue
        }
        if (-not (Test-SyncComplete `
            $dedupManifestPath `
            $godotVariantRoot `
            $variantName `
            $matrixId `
            $variantRecord.area_data_id `
            $dedupeToolSha256 `
            $syncToolSha256
        )) {
            $staleDownstreamVariants.Add("$variantName (Godot sync)")
        }
    }
    if ($staleDownstreamVariants.Count -ne 0) {
        $details = @($staleDownstreamVariants | Select-Object -First 8) -join '; '
        if ($staleDownstreamVariants.Count -gt 8) {
            $details += "; ... and $($staleDownstreamVariants.Count - 8) more"
        }
        throw "Partial matrix export cannot publish a complete catalog while unrequested destinations are stale: $details. Rerun without -MatrixIds."
    }
}

$rawRoot = Assert-DspreSafeRecursiveDeletePath -Path $rawRoot -AllowedRoot $workspaceRoot
$dedupRoot = Assert-DspreSafeRecursiveDeletePath -Path $dedupRoot -AllowedRoot $workspaceRoot
$platinumRoot = Assert-DspreSafeRecursiveDeletePath -Path $platinumRoot -AllowedRoot $projectRoot
New-Item -ItemType Directory -Path $rawRoot, $dedupRoot, $platinumRoot -Force | Out-Null

$publishedCatalogPaths = @($generatedCatalogPath, $godotCatalogPath)
foreach ($catalogPath in $publishedCatalogPaths) {
    if (Test-Path -LiteralPath $catalogPath) {
        $catalogItem = Get-Item -LiteralPath $catalogPath -Force -ErrorAction Stop
        if (
            $catalogItem.PSIsContainer -or
            ($catalogItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        ) {
            throw "Published matrix catalog path is not a file: $catalogPath"
        }
    }
}
foreach ($catalogPath in $publishedCatalogPaths) {
	if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
		Remove-Item -LiteralPath $catalogPath -Force
	}
}

$staleDestinationPaths = @(
	Get-UnexpectedMatrixDestinations `
		-Variants $allVariants `
		-RootPath $rawRoot `
		-AllowedRoot $workspaceRoot `
		-Label "Raw output"
	Get-UnexpectedMatrixDestinations `
		-Variants $allVariants `
		-RootPath $dedupRoot `
		-AllowedRoot $workspaceRoot `
		-Label "Deduplicated output"
	Get-UnexpectedMatrixDestinations `
		-Variants $allVariants `
		-RootPath $platinumRoot `
		-AllowedRoot $projectRoot `
		-Label "Godot output"
)
foreach ($staleDestinationPath in $staleDestinationPaths) {
	Remove-Item -LiteralPath $staleDestinationPath -Recurse -Force
}
if ($staleDestinationPaths.Count -gt 0) {
	Write-Host "Removed $($staleDestinationPaths.Count) stale matrix destination directories."
}

Write-Host "DSPRE all-matrix export starting."
Write-Host "  Requested matrices: $($requestedIds.Count)"
Write-Host "  Ready variants:     $($readyRequestedVariants.Count)"
Write-Host "  Unresolved:         $($skippedRequestedIds.Count)"

$processed = 0
$destinationAssetsChanged = $false
foreach ($variantRecord in $readyRequestedVariants) {
    $matrixId = [int]$variantRecord.matrix_id
    $variantName = [string]$variantRecord.variant
    $rawMatrixRoot = Join-Path $rawRoot $variantName
    $dedupMatrixRoot = Join-Path $dedupRoot $variantName
    $godotMatrixRoot = Join-Path $platinumRoot $variantName
    $rawManifest = Join-Path $rawMatrixRoot "manifest.json"
    $rawSummaryPath = Join-Path $rawMatrixRoot "summary.json"
    $rawMarkerPath = Join-Path $rawMatrixRoot ".export-complete.json"
    $dedupManifest = Join-Path $dedupMatrixRoot "manifest.json"
    $dedupSummaryPath = Join-Path $dedupMatrixRoot "summary.json"
    $dedupCatalogPath = Join-Path $dedupMatrixRoot "material_catalog.json"

    $progress = @{
        Activity = "Migrating DSPRE matrices"
        Status = "$variantName ($($processed + 1)/$($readyRequestedVariants.Count))"
        PercentComplete = 100.0 * $processed / [Math]::Max(1, $readyRequestedVariants.Count)
    }
    Write-Progress @progress

    $rawComplete = $false
    if (
        -not $RebuildExisting -and
        (Test-Path -LiteralPath $rawManifest -PathType Leaf) -and
        (Test-Path -LiteralPath $rawSummaryPath -PathType Leaf) -and
        (Test-Path -LiteralPath $rawMarkerPath -PathType Leaf)
    ) {
        try {
            $existingRawSummary = [IO.File]::ReadAllText(
                $rawSummaryPath,
                [Text.Encoding]::UTF8
            ) | ConvertFrom-Json
            $existingRawManifest = [IO.File]::ReadAllText(
                $rawManifest,
                [Text.Encoding]::UTF8
            ) | ConvertFrom-Json
            $existingRawMarker = [IO.File]::ReadAllText(
                $rawMarkerPath,
                [Text.Encoding]::UTF8
            ) | ConvertFrom-Json
            $null = Assert-DspreCollisionManifest `
                -Manifest $existingRawManifest `
                -Label "Raw destination $variantName" `
                -ExpectedManifestSchema 3
            $manifestVariant = if (
                $null -ne $existingRawManifest.matrix.PSObject.Properties["variant"]
            ) {
                [string]$existingRawManifest.matrix.variant
            }
            else {
                "matrix_{0:D4}" -f [int]$existingRawManifest.matrix.id
            }
            $manifestArea = if (
                $null -ne $existingRawManifest.matrix.PSObject.Properties["area_data_id"]
            ) {
                $existingRawManifest.matrix.area_data_id
            }
            else {
                $null
            }
            $expectedArea = $variantRecord.area_data_id
            $areaMatches = ($null -eq $expectedArea -and $null -eq $manifestArea) -or
                ($null -ne $expectedArea -and $null -ne $manifestArea -and
                    [int]$expectedArea -eq [int]$manifestArea)
            $markerMatches = Assert-DspreRawExportMarker `
                -Marker $existingRawMarker `
                -ExpectedMatrixId $matrixId `
                -ExpectedVariant $variantName `
                -ExpectedAreaDataId $expectedArea `
                -ExpectedDspreSourceSha256 $dspreSourceSha256 `
                -ExpectedExporterSha256 $exporterSha256 `
                -ExpectedSupportToolSha256 $supportToolSha256 `
                -ExpectedApiculaSha256 $apiculaSha256 `
                -ExpectedAreaResolutionSha256 $areaResolutionSha256 `
                -ExpectedManifestSha256 (Get-FileHash -LiteralPath $rawManifest -Algorithm SHA256).Hash.ToLowerInvariant() `
                -ExpectedOccupiedCells @($existingRawManifest.cells).Count `
                -ExpectedCollisionAssets @($existingRawManifest.collision_assets).Count `
                -OutputRoot $rawMatrixRoot `
                -Label "Raw destination $variantName marker"
            $rawComplete = $markerMatches -and [int]$existingRawSummary.failed -eq 0 -and
                [int]$existingRawManifest.matrix.id -eq $matrixId -and
                $manifestVariant -eq $variantName -and $areaMatches
        }
        catch {
            $rawComplete = $false
        }
    }
    $rawWasRebuilt = $RebuildExisting -or -not $rawComplete
    if ($rawWasRebuilt) {
        $exportArguments = @{
            DspreContents = $DspreContents
            ApiculaPath = $ApiculaPath
            AreaOverridesPath = $resolutionPath
            MatrixId = $matrixId
            MaxParallel = $MaxParallel
            DspreSourceSha256 = $dspreSourceSha256
            ExporterSha256 = $exporterSha256
            SupportToolSha256 = $supportToolSha256
            ApiculaSha256 = $apiculaSha256
            AreaResolutionSha256 = $areaResolutionSha256
            Force = [bool]$RebuildExisting
        }
        if ($variantName -match '_area_\d{4}$') {
            $exportArguments.AreaDataId = [int]$variantRecord.area_data_id
        }
        Invoke-ProjectScript (Join-Path $PSScriptRoot "dspre_batch_export.ps1") $exportArguments
    }
    $rawSummary = [IO.File]::ReadAllText(
        $rawSummaryPath,
        [Text.Encoding]::UTF8
    ) | ConvertFrom-Json
    $rawManifestDocument = [IO.File]::ReadAllText(
        $rawManifest,
        [Text.Encoding]::UTF8
    ) | ConvertFrom-Json
    $rawMarker = [IO.File]::ReadAllText($rawMarkerPath, [Text.Encoding]::UTF8) |
        ConvertFrom-Json
    $null = Assert-DspreCollisionManifest `
        -Manifest $rawManifestDocument `
        -Label "Raw destination $variantName" `
        -ExpectedManifestSchema 3
    $rawManifestVariant = if ($null -ne $rawManifestDocument.matrix.PSObject.Properties["variant"]) {
        [string]$rawManifestDocument.matrix.variant
    }
    else {
        "matrix_{0:D4}" -f [int]$rawManifestDocument.matrix.id
    }
    $rawManifestArea = if ($null -ne $rawManifestDocument.matrix.PSObject.Properties["area_data_id"]) {
        $rawManifestDocument.matrix.area_data_id
    }
    else {
        $null
    }
    $expectedArea = $variantRecord.area_data_id
    $rawAreaMatches = ($null -eq $expectedArea -and $null -eq $rawManifestArea) -or
        ($null -ne $expectedArea -and $null -ne $rawManifestArea -and
            [int]$expectedArea -eq [int]$rawManifestArea)
    $markerMatches = Assert-DspreRawExportMarker `
        -Marker $rawMarker `
        -ExpectedMatrixId $matrixId `
        -ExpectedVariant $variantName `
        -ExpectedAreaDataId $expectedArea `
        -ExpectedDspreSourceSha256 $dspreSourceSha256 `
        -ExpectedExporterSha256 $exporterSha256 `
        -ExpectedSupportToolSha256 $supportToolSha256 `
        -ExpectedApiculaSha256 $apiculaSha256 `
        -ExpectedAreaResolutionSha256 $areaResolutionSha256 `
        -ExpectedManifestSha256 (Get-FileHash -LiteralPath $rawManifest -Algorithm SHA256).Hash.ToLowerInvariant() `
        -ExpectedOccupiedCells @($rawManifestDocument.cells).Count `
        -ExpectedCollisionAssets @($rawManifestDocument.collision_assets).Count `
        -Label "Raw destination $variantName marker"
    if (
        -not $markerMatches -or
        [int]$rawSummary.failed -ne 0 -or
        [int]$rawManifestDocument.matrix.id -ne $matrixId -or
        $rawManifestVariant -ne $variantName -or
        -not $rawAreaMatches
    ) {
        throw "$variantName raw export does not match its resolution record."
    }

    $dedupComplete = $false
    if (-not $rawWasRebuilt) {
        $dedupComplete = Test-DedupeComplete `
            $rawManifest `
            $dedupMatrixRoot `
            $variantName `
            $matrixId `
            $variantRecord.area_data_id `
            $dedupeToolSha256
    }
    $dedupWasRebuilt = $rawWasRebuilt -or -not $dedupComplete
    if ($dedupWasRebuilt) {
        Invoke-ProjectScript (Join-Path $PSScriptRoot "dedupe_dspre_materials.ps1") @{
            SourceRoot = $rawMatrixRoot
            OutputRoot = $dedupMatrixRoot
            DedupeToolSha256 = $dedupeToolSha256
            Force = (Test-Path -LiteralPath $dedupMatrixRoot)
        }
        $dedupComplete = Test-DedupeComplete `
            $rawManifest `
            $dedupMatrixRoot `
            $variantName `
            $matrixId `
            $variantRecord.area_data_id `
            $dedupeToolSha256 `
            -MarkerOnly
    }
    if (-not $dedupComplete) {
        throw "$variantName dedupe output is incomplete or inconsistent."
    }

    $syncComplete = $false
    if (-not $RebuildExisting -and -not $dedupWasRebuilt) {
        $syncComplete = Test-SyncComplete `
            $dedupManifest `
            $godotMatrixRoot `
            $variantName `
            $matrixId `
            $variantRecord.area_data_id `
            $dedupeToolSha256 `
            $syncToolSha256
    }
    if ($RebuildExisting -or $dedupWasRebuilt -or -not $syncComplete) {
		$destinationAssetsChanged = $true
        $dedupeMarkerPath = Join-Path $dedupMatrixRoot ".dedupe-complete.json"
        $dedupeMarkerSha256 = (
            Get-FileHash -LiteralPath $dedupeMarkerPath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        Invoke-ProjectScript (Join-Path $PSScriptRoot "sync_dspre_godot_assets.ps1") @{
            SourceRoot = $dedupMatrixRoot
            ProjectRoot = $projectRoot
            DedupeToolSha256 = $dedupeToolSha256
            SyncToolSha256 = $syncToolSha256
            TrustSourceMarkerRecords = $true
            ExpectedDedupeMarkerSha256 = $dedupeMarkerSha256
            Force = (Test-Path -LiteralPath $godotMatrixRoot)
        }
        $syncComplete = Test-SyncComplete `
            $dedupManifest `
            $godotMatrixRoot `
            $variantName `
            $matrixId `
            $variantRecord.area_data_id `
            $dedupeToolSha256 `
            $syncToolSha256 `
            -MarkerOnly
    }
    if (-not $syncComplete) {
        throw "$variantName Godot sync is incomplete or inconsistent."
    }
    $processed++
}
Write-Progress -Activity "Migrating DSPRE matrices" -Completed

$fieldTextureBuild = Invoke-FieldTextureAnimationBuild `
    -SourceRoot $DspreContents `
    -Force:$RebuildExisting
$fieldTextureSection = $fieldTextureBuild.section

$terrainKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$buildingKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$collisionKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$collisionFingerprints = @{}
$textureKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$materialKeys = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$matrixEntries = New-Object System.Collections.Generic.List[object]
$destinationEntries = New-Object System.Collections.Generic.List[object]
$headerEntries = New-Object System.Collections.Generic.List[object]
$warpIds = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
$totalCells = 0
$totalBuildings = 0
$totalGlbs = 0
$totalDestinationCollisionAssets = 0
$totalWarpEvents = 0
$totalOrdinaryWarps = 0
$totalSpecialReturns = 0
$totalDynamicWarps = 0
$totalAnimatedBuildingAssets = 0
$totalNativeAnimationClips = 0
$totalUnsupportedAnimationClips = 0
$readyMatrixCount = 0
$readyDestinationCount = 0
$notExportedMatrixCount = 0

foreach ($matrixId in $allMatrixIds) {
    if ($unresolvedById.ContainsKey($matrixId)) {
        $unresolved = $unresolvedById[$matrixId]
        $status = if (@($unresolved.candidate_signatures).Count -eq 0) {
            "unresolved_no_single_texture_bundle"
        }
        else {
            "unresolved_ambiguous_area"
        }
        $matrixEntries.Add([pscustomobject][ordered]@{
            id = $matrixId
            status = $status
            destinations = @()
            candidate_signatures = @($unresolved.candidate_signatures)
        })
        continue
    }

    $matrixVariants = @($allVariants | Where-Object { [int]$_.matrix_id -eq $matrixId })
    $destinationKeys = New-Object System.Collections.Generic.List[string]
    $firstManifest = $null
    foreach ($variantRecord in $matrixVariants) {
        $variantName = [string]$variantRecord.variant
        $manifestPath = Join-Path $dedupRoot "$variantName\manifest.json"
        $materialCatalogPath = Join-Path $dedupRoot "$variantName\material_catalog.json"
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "Expected catalog destination manifest is missing: $manifestPath"
        }
        $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        $null = Assert-DspreCollisionManifest `
            -Manifest $manifest `
            -Label "Catalog destination $variantName" `
            -ExpectedManifestSchema 4
        $fieldStats = [pscustomobject]@{
            warps = [int]$manifest.field_features.warp_count
            ordinary_warps = [int]$manifest.field_features.ordinary_warp_count
            special_returns = [int]$manifest.field_features.special_return_count
            dynamic_warps = [int]$manifest.field_features.dynamic_warp_count
        }
        $materialCatalog = [IO.File]::ReadAllText(
            $materialCatalogPath,
            [Text.Encoding]::UTF8
        ) | ConvertFrom-Json
        if ([int]$materialCatalog.schema_version -ne 1) {
            throw "Catalog destination $variantName has an unsupported material catalog schema: $($materialCatalog.schema_version)"
        }
        if ($null -eq $firstManifest) {
            $firstManifest = $manifest
        }
        foreach ($asset in @($manifest.assets.terrain)) {
            $null = $terrainKeys.Add([string]$asset.key)
        }
        foreach ($asset in @($manifest.assets.buildings)) {
            $null = $buildingKeys.Add([string]$asset.key)
        }
        foreach ($asset in @($manifest.collision_assets)) {
            $collisionKey = [string]$asset.key
            $collisionFingerprint = "{0}:{1}" -f `
                [string]$asset.terrain_attributes.sha256,
                [string]$asset.bdhc.sha256
            if (
                $collisionFingerprints.ContainsKey($collisionKey) -and
                [string]$collisionFingerprints[$collisionKey] -ne $collisionFingerprint
            ) {
                throw "Collision asset $collisionKey differs across destination manifests."
            }
            $collisionFingerprints[$collisionKey] = $collisionFingerprint
            $null = $collisionKeys.Add($collisionKey)
        }
        foreach ($image in @($materialCatalog.images)) {
            $null = $textureKeys.Add([string]$image.key)
        }
        foreach ($material in @($materialCatalog.materials)) {
            $null = $materialKeys.Add([string]$material.key)
        }
        $defaultCell = Get-DefaultCell $manifest
        $glbCount = [int]$materialCatalog.summary.glbs
        $buildingCount = [int]$manifest.summary.building_instances
        $collisionCount = @($manifest.collision_assets).Count
        $warpCount = [int]$fieldStats.warps
        $ordinaryWarpCount = [int]$fieldStats.ordinary_warps
        $specialReturnCount = [int]$fieldStats.special_returns
        $dynamicWarpCount = [int]$fieldStats.dynamic_warps
        if (
            [int]$manifest.summary.warp_events -ne $warpCount -or
            [int]$manifest.summary.ordinary_warps -ne $ordinaryWarpCount -or
            [int]$manifest.summary.special_returns -ne $specialReturnCount -or
            [int]$manifest.summary.dynamic_warps -ne $dynamicWarpCount
        ) {
            throw "Catalog destination $variantName field-feature summary is inconsistent."
        }
        $animatedBuildingAssetCount = Get-OptionalSummaryCount `
            -Summary $manifest.summary `
            -Name "animated_building_assets" `
            -Label "Catalog destination $variantName"
        $nativeAnimationClipCount = Get-OptionalSummaryCount `
            -Summary $manifest.summary `
            -Name "native_animation_clips" `
            -Label "Catalog destination $variantName"
        $unsupportedAnimationClipCount = Get-OptionalSummaryCount `
            -Summary $manifest.summary `
            -Name "unsupported_animation_clips" `
            -Label "Catalog destination $variantName"
        foreach ($warp in @($manifest.field_features.warps)) {
            if (-not $warpIds.Add([string]$warp.id)) {
                throw "Warp ID is duplicated across runnable destinations: $($warp.id)"
            }
            if (
                [string]$warp.source.variant -ne $variantName -or
                [int]$warp.source.matrix_id -ne $matrixId
            ) {
                throw "Warp $($warp.id) source does not match destination $variantName."
            }
        }
        $totalGlbs += $glbCount
        $totalDestinationCollisionAssets += $collisionCount
        $totalWarpEvents += $warpCount
        $totalOrdinaryWarps += $ordinaryWarpCount
        $totalSpecialReturns += $specialReturnCount
        $totalDynamicWarps += $dynamicWarpCount
        $totalAnimatedBuildingAssets += $animatedBuildingAssetCount
        $totalNativeAnimationClips += $nativeAnimationClipCount
        $totalUnsupportedAnimationClips += $unsupportedAnimationClipCount
        $readyDestinationCount++
        $destinationKeys.Add($variantName)
        $destinationEntries.Add([pscustomobject][ordered]@{
            key = $variantName
            matrix_id = $matrixId
            area_data_id = if ($null -eq $variantRecord.area_data_id) {
                $null
            }
            else {
                [int]$variantRecord.area_data_id
            }
            status = Get-ReadyStatus $manifest
            manifest = "$variantName/manifest.json"
            width = [int]$manifest.matrix.width
            height = [int]$manifest.matrix.height
            occupied_cells = [int]$manifest.matrix.occupied_cells
            default_cell = $defaultCell
            terrain_assets = @($manifest.assets.terrain).Count
            building_assets = @($manifest.assets.buildings).Count
            collision_assets = $collisionCount
            terrain_attribute_tiles = [int]$manifest.summary.terrain_attribute_tiles
            bdhc_assets = [int]$manifest.summary.bdhc_assets
            building_instances = $buildingCount
            warp_events = $warpCount
            ordinary_warps = $ordinaryWarpCount
            special_returns = $specialReturnCount
            dynamic_warps = $dynamicWarpCount
            animated_building_assets = $animatedBuildingAssetCount
            native_animation_clips = $nativeAnimationClipCount
            unsupported_animation_clips = $unsupportedAnimationClipCount
            glbs = $glbCount
            textures = [int]$materialCatalog.summary.unique_images
            materials = [int]$materialCatalog.summary.unique_materials
        })
    }

    if ($destinationKeys.Count -eq 0) {
        $notExportedMatrixCount++
        $matrixEntries.Add([pscustomobject][ordered]@{
            id = $matrixId
            status = "not_exported"
            destinations = @()
        })
        continue
    }
    $matrixStatus = if ($destinationKeys.Count -eq $matrixVariants.Count) {
        $readyMatrixCount++
        "ready"
    }
    else {
        $notExportedMatrixCount++
        "partially_exported"
    }
    $totalCells += [int]$firstManifest.matrix.occupied_cells
    $totalBuildings += [int]$firstManifest.summary.building_instances
    $matrixEntries.Add([pscustomobject][ordered]@{
        id = $matrixId
        name = [string]$firstManifest.matrix.name
        status = $matrixStatus
        destinations = @($destinationKeys | ForEach-Object { $_ })
    })
}

$destinationsByMatrix = @{}
foreach ($destination in $destinationEntries) {
    $matrixKey = [string][int]$destination.matrix_id
    if (-not $destinationsByMatrix.ContainsKey($matrixKey)) {
        $destinationsByMatrix[$matrixKey] = [Collections.Generic.List[object]]::new()
    }
    $destinationsByMatrix[$matrixKey].Add($destination)
}
foreach ($header in $sourceMapHeaders) {
    $headerId = [int]$header.id
    $matrixId = [int]$header.matrix_id
    $matrixKey = [string]$matrixId
    if (-not $destinationsByMatrix.ContainsKey($matrixKey)) {
        throw "MapHeader $headerId points to matrix $matrixId without a runnable destination."
    }
    $matrixDestinations = @($destinationsByMatrix[$matrixKey])
    $areaDestinations = @(
        $matrixDestinations | Where-Object {
            $null -ne $_.area_data_id -and
            [int]$_.area_data_id -eq [int]$header.area_data_id
        }
    )
    $destination = if ($areaDestinations.Count -eq 1) {
        $areaDestinations[0]
    }
    elseif (
        $areaDestinations.Count -eq 0 -and
        $matrixDestinations.Count -eq 1 -and
        $null -eq $matrixDestinations[0].area_data_id
    ) {
        $matrixDestinations[0]
    }
    else {
        throw "MapHeader $headerId does not resolve uniquely for matrix $matrixId AreaData $($header.area_data_id)."
    }
    $headerEntries.Add([pscustomobject][ordered]@{
        header_id = $headerId
        destination_key = [string]$destination.key
        matrix_id = $matrixId
        area_data_id = [int]$header.area_data_id
    })
}

if ($headerEntries.Count -ne 593 -or $totalWarpEvents -ne 1213) {
    throw "Runnable field-feature totals are unexpected: $($headerEntries.Count)/593 headers and $totalWarpEvents/1213 warps."
}

$catalog = [pscustomobject][ordered]@{
    schema_version = 3
    generated_utc = [DateTime]::UtcNow.ToString("o")
    summary = [pscustomobject][ordered]@{
        source_matrices = $allMatrixIds.Count
        expected_destinations = $allVariants.Count
        ready_matrices = $readyMatrixCount
        ready_destinations = $readyDestinationCount
        unresolved_matrices = $unresolvedById.Count
        not_exported_matrices = $notExportedMatrixCount
        occupied_cells = $totalCells
        building_instances = $totalBuildings
        destination_scoped_glbs = $totalGlbs
        destination_scoped_collision_assets = $totalDestinationCollisionAssets
        headers = $headerEntries.Count
        warp_events = $totalWarpEvents
        ordinary_warps = $totalOrdinaryWarps
        special_returns = $totalSpecialReturns
        dynamic_warps = $totalDynamicWarps
        animated_building_assets = $totalAnimatedBuildingAssets
        native_animation_clips = $totalNativeAnimationClips
        unsupported_animation_clips = $totalUnsupportedAnimationClips
        unique_terrain_assets = $terrainKeys.Count
        unique_building_assets = $buildingKeys.Count
        unique_collision_assets = $collisionKeys.Count
        unique_textures = $textureKeys.Count
        unique_materials = $materialKeys.Count
    }
    matrices = @($matrixEntries | ForEach-Object { $_ })
    destinations = @($destinationEntries | ForEach-Object { $_ })
    headers = @($headerEntries | Sort-Object header_id | ForEach-Object { $_ })
}
Add-FieldTextureAnimationCatalogData -Catalog $catalog -Section $fieldTextureSection
$catalogJson = $catalog | ConvertTo-Json -Depth 12

$validatedDestinationCount = Assert-AllDestinationStagesCurrent `
    -Variants $allVariants `
    -RawRoot $rawRoot `
    -DedupRoot $dedupRoot `
    -GodotRoot $platinumRoot `
    -ExpectedDspreSourceSha256 $dspreSourceSha256 `
    -ExpectedExporterSha256 $exporterSha256 `
    -ExpectedSupportToolSha256 $supportToolSha256 `
    -ExpectedDedupeToolSha256 $dedupeToolSha256 `
    -ExpectedSyncToolSha256 $syncToolSha256 `
    -ExpectedApiculaSha256 $apiculaSha256 `
    -ExpectedAreaResolutionSha256 $areaResolutionSha256
if (
    $validatedDestinationCount -ne $allVariants.Count -or
    $readyDestinationCount -ne $allVariants.Count -or
    $destinationEntries.Count -ne $allVariants.Count -or
    $notExportedMatrixCount -ne 0
) {
    throw "Catalog aggregation did not cover every expected runnable destination."
}
Write-Host "All $validatedDestinationCount expected raw, dedupe, and sync destinations passed final validation."

$changedInputs = New-Object System.Collections.Generic.List[string]
if ((Get-DspreContentFingerprint -RootPath $DspreContents) -ne $dspreSourceSha256) {
    $changedInputs.Add("DSPRE contents")
}
if ((Get-DspreToolFileFingerprint -Path $batchExporterPath) -ne $exporterSha256) {
    $changedInputs.Add("batch exporter")
}
if ((Get-DspreSupportBundleFingerprint -ToolsRoot $PSScriptRoot) -ne $supportToolSha256) {
    $changedInputs.Add("DSPRE support bundle")
}
if ((Get-DspreToolFileFingerprint -Path $dedupeToolPath) -ne $dedupeToolSha256) {
    $changedInputs.Add("material dedupe tool")
}
if ((Get-DspreToolFileFingerprint -Path $syncToolPath) -ne $syncToolSha256) {
    $changedInputs.Add("Godot sync tool")
}
if ((Get-DspreToolFileFingerprint -Path $ApiculaPath) -ne $apiculaSha256) {
    $changedInputs.Add("apicula")
}
if ((Get-DspreAreaResolutionFingerprint -Path $resolutionPath) -ne $areaResolutionSha256) {
    $changedInputs.Add("AreaData resolution")
}
if ($changedInputs.Count -ne 0) {
    throw "Export inputs changed during the matrix run: $($changedInputs -join ', '). Rerun before publishing the catalog."
}
Write-Host "Export input fingerprints remained stable throughout catalog aggregation."

$dedupRoot = Assert-DspreSafeRecursiveDeletePath -Path $dedupRoot -AllowedRoot $workspaceRoot
$platinumRoot = Assert-DspreSafeRecursiveDeletePath -Path $platinumRoot -AllowedRoot $projectRoot
Publish-MatrixCatalogPair `
    -GeneratedPath $generatedCatalogPath `
    -GodotPath $godotCatalogPath `
    -Json $catalogJson `
    -Encoding $utf8NoBom

Write-Host "DSPRE matrix migration complete."
Write-Host "  Ready matrices:      $readyMatrixCount"
Write-Host "  Ready destinations:  $readyDestinationCount"
Write-Host "  Unresolved matrices: $($unresolvedById.Count)"
Write-Host "  Occupied cells:      $totalCells"
Write-Host "  Matrix GLBs:         $totalGlbs"
Write-Host "  Collision assets:    $($collisionKeys.Count) unique / $totalDestinationCollisionAssets destination-scoped"
Write-Host "  Catalog:             $godotCatalogPath"

if (-not $SkipGodotImport) {
    $GodotPath = Resolve-ExistingFile $GodotPath "Godot console executable"
    & $GodotPath --headless --path $projectRoot --import
    if ($LASTEXITCODE -ne 0) {
        throw "Initial Godot import failed with exit code $LASTEXITCODE."
    }
    if ($destinationAssetsChanged) {
        Invoke-ProjectScript (Join-Path $PSScriptRoot "configure_dspre_godot_materials.ps1") @{
            ProjectRoot = $projectRoot
            GodotPath = $GodotPath
        }
    }
    else {
        Invoke-ProjectScript (Join-Path $PSScriptRoot "configure_dspre_godot_textures.ps1") @{
            ProjectRoot = $projectRoot
            GodotPath = $GodotPath
            RepairInvalidOnly = $true
        }
    }
}
