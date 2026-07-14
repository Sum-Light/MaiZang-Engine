[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot "build_dspre_field_texture_animations.ps1")

function Assert-FieldTextureEqual {
    param($Expected, $Actual, [string]$Label)

    if ([string]$Expected -cne [string]$Actual) {
        throw "$Label expected '$Expected', got '$Actual'."
    }
}

function Assert-FieldTextureFalse {
    param([bool]$Value, [string]$Label)

    if ($Value) {
        throw "$Label unexpectedly succeeded."
    }
}

function Assert-FieldTextureThrows {
    param([scriptblock]$Action, [string]$Label)

    try {
        & $Action
    }
    catch {
        return
    }
    throw "$Label unexpectedly succeeded."
}

$testRoot = Join-Path $repositoryRoot ".work\test_build_dspre_field_texture_animations"
if (Test-Path -LiteralPath $testRoot) {
    $null = Assert-DspreTreeHasNoReparsePoints -RootPath $testRoot -Label "Field texture builder test"
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
$null = [IO.Directory]::CreateDirectory($testRoot)

try {
    Assert-FieldTextureEqual "lakep_1" `
        (ConvertTo-DspreFieldTextureNormalizedAlias -Name "lakep.1") `
        "Nitro texture alias"
    Assert-FieldTextureEqual "lakep_1" `
        (ConvertTo-DspreFieldTextureNormalizedAlias -Name "LAKEP_1.PNG") `
        "material image alias"

    $animation = [pscustomobject][ordered]@{
        animation_id = 10
        texture_name = "lakep.1"
        member_id = 11
        unique_frame_indices = @(0, 1)
        cycle_ticks = 12
        sequence = @(
            [pscustomobject][ordered]@{ sequence_index = 0; frame_index = 0; hold_ticks = 4 },
            [pscustomobject][ordered]@{ sequence_index = 1; frame_index = 1; hold_ticks = 4 },
            [pscustomobject][ordered]@{ sequence_index = 2; frame_index = 0; hold_ticks = 4 }
        )
    }
    $frameInputRoot = Join-Path $testRoot "frame_input"
    $null = [IO.Directory]::CreateDirectory($frameInputRoot)
    $frameZero = New-DspreFieldTextureRgbaImage -Width 2 -Height 1 -Rgba ([byte[]]@(
        0, 0, 255, 255,
        255, 255, 0, 255
    ))
    $frameOne = New-DspreFieldTextureRgbaImage -Width 2 -Height 1 -Rgba ([byte[]]@(
        255, 255, 0, 255,
        0, 0, 255, 255
    ))
    $frameZeroPath = Join-Path $frameInputRoot "lakep_1.png"
    $frameOnePath = Join-Path $frameInputRoot "lakep_2.png"
    $null = Write-DspreFieldTexturePng -Image $frameZero -Path $frameZeroPath -AllowedRoot $testRoot
    $null = Write-DspreFieldTexturePng -Image $frameOne -Path $frameOnePath -AllowedRoot $testRoot

    $dedupRoot = Join-Path $testRoot "dedup"
    $readyImage = New-DspreFieldTextureRgbaImage -Width 2 -Height 1 -Rgba ([byte[]]@(
        0, 0, 255, 255,
        255, 255, 0, 255
    ))
    $deferredImage = New-DspreFieldTextureRgbaImage -Width 2 -Height 1 -Rgba ([byte[]]@(
        0, 0, 255, 255,
        255, 255, 0, 0
    ))
    $catalogIndex = 0
    $readySha = ""
    $deferredSha = ""
    foreach ($image in @($readyImage, $deferredImage)) {
        $destinationRoot = Join-Path $dedupRoot ("matrix_{0:D4}" -f $catalogIndex)
        $textureRoot = Join-Path $destinationRoot "shared\textures"
        $null = [IO.Directory]::CreateDirectory($textureRoot)
        $temporaryImagePath = Join-Path $textureRoot "temporary.png"
        $written = Write-DspreFieldTexturePng `
            -Image $image `
            -Path $temporaryImagePath `
            -AllowedRoot $testRoot
        $finalImagePath = Join-Path $textureRoot ("$($written.sha256).png")
        Move-Item -LiteralPath $temporaryImagePath -Destination $finalImagePath
        if ($catalogIndex -eq 0) {
            $readySha = [string]$written.sha256
        }
        else {
            $deferredSha = [string]$written.sha256
        }
        $catalog = [pscustomobject][ordered]@{
            schema_version = 1
            images = @([pscustomobject][ordered]@{
                key = "img_$($written.sha256)"
                sha256 = [string]$written.sha256
                relative_path = "shared/textures/$($written.sha256).png"
                byte_length = [long]$written.byte_length
                aliases = @("lakep_1.png")
            })
            materials = @()
            assets = @()
        }
        [IO.File]::WriteAllText(
            (Join-Path $destinationRoot "material_catalog.json"),
            ($catalog | ConvertTo-Json -Depth 8 -Compress),
            [Text.UTF8Encoding]::new($false)
        )
        $catalogIndex++
    }

    $descriptor = [pscustomobject][ordered]@{
        schema_version = 1
        source_fps = 30
        animation_count = 1
        animations = @($animation)
    }
    $inventory = Get-DspreFieldTextureMaterialInventory `
        -RootPath $dedupRoot `
        -Descriptor $descriptor `
        -ExpectedCatalogCount 2
    Assert-FieldTextureEqual 2 @($inventory.variants).Count "material palette variants"
    if ([string]$inventory.material_catalogs_sha256 -notmatch '^[0-9a-f]{64}$') {
        throw "Material catalog fingerprint is invalid."
    }

    $paletteBytes = [byte[]]@(0x00, 0x7C, 0xFF, 0x03)
    $palette = [pscustomobject][ordered]@{
        index = 0
        name = "lakep"
        offset = 0
        colors = [uint16[]]@(0x7C00, 0x03FF)
        palette_block = $paletteBytes
        palette_block_sha256 = Get-DspreFieldTextureSha256 -Bytes $paletteBytes
    }

    $seaTargetData = [byte[]](0..15 | ForEach-Object { 0xE4 })
    $seaSourceData = [byte[]]::new(32)
    [Buffer]::BlockCopy($seaTargetData, 0, $seaSourceData, 0, $seaTargetData.Length)
    for ($index = $seaTargetData.Length; $index -lt $seaSourceData.Length; $index++) {
        $seaSourceData[$index] = 0xFF
    }
    $seaTarget = [pscustomobject][ordered]@{
        format = 2
        width = 8
        height = 8
        color0_transparent = $false
        data = $seaTargetData
        data2 = [byte[]]@()
    }
    $seaSource = [pscustomobject][ordered]@{
        format = 3
        width = 8
        height = 8
        color0_transparent = $false
        data = $seaSourceData
        data2 = [byte[]]@()
    }
    $seaRuntime = ConvertTo-DspreFieldTextureRuntimeFrameTexture `
        -TargetTexture $seaTarget `
        -SourceFrameTexture $seaSource
    Assert-FieldTextureEqual 2 $seaRuntime.format "destination texture format"
    Assert-FieldTextureEqual 16 ([byte[]]$seaRuntime.data).Length "destination texture allocation"
    if (@([byte[]]$seaRuntime.data | Where-Object { $_ -ne 0xE4 }).Count -ne 0) {
        throw "The fldtanime frame prefix was not copied exactly into the destination allocation."
    }
    $seaPaletteBytes = [byte[]]@(
        0x00, 0x00,
        0x1F, 0x00,
        0xE0, 0x03,
        0x00, 0x7C
    )
    $seaPalette = [pscustomobject][ordered]@{
        offset = 0
        palette_block = $seaPaletteBytes
        palette_block_sha256 = Get-DspreFieldTextureSha256 -Bytes $seaPaletteBytes
    }
    $seaDecoded = ConvertFrom-DspreFieldTextureTexelData `
        -Texture $seaRuntime `
        -Palette $seaPalette `
        -Label "Synthetic cross-format sea frame"
    Assert-FieldTextureEqual 8 $seaDecoded.width "cross-format sea width"
    Assert-FieldTextureEqual 8 $seaDecoded.height "cross-format sea height"
    $shortSeaSource = $seaSource | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $shortSeaSource.data = [byte[]]::new(15)
    Assert-FieldTextureThrows {
        ConvertTo-DspreFieldTextureRuntimeFrameTexture `
            -TargetTexture $seaTarget `
            -SourceFrameTexture $shortSeaSource
    } "short fldtanime frame"
    $formatFiveTarget = [pscustomobject][ordered]@{
        format = 5
        width = 4
        height = 4
        color0_transparent = $false
        data = [byte[]]::new(4)
        data2 = [byte[]]::new(2)
    }
    $formatFiveSource = [pscustomobject][ordered]@{
        format = 3
        width = 4
        height = 4
        color0_transparent = $false
        data = [byte[]]::new(8)
        data2 = [byte[]]::new(1)
    }
    Assert-FieldTextureThrows {
        ConvertTo-DspreFieldTextureRuntimeFrameTexture `
            -TargetTexture $formatFiveTarget `
            -SourceFrameTexture $formatFiveSource
    } "format-5 auxiliary data mismatch"
    $targetTexels = [byte[]]@(0x10)
    $targetTexture = [pscustomobject][ordered]@{
        index = 0
        name = "lakep.1"
        format = 3
        width = 2
        height = 1
        color0_transparent = $false
        data = $targetTexels
        data2 = [byte[]]@()
        data_sha256 = Get-DspreFieldTextureSha256 -Bytes $targetTexels
        data2_sha256 = $null
    }
    $secondTexels = [byte[]]@(0x01)
    $secondTexture = [pscustomobject][ordered]@{
        index = 1
        name = "lakep.2"
        format = 3
        width = 2
        height = 1
        color0_transparent = $false
        data = $secondTexels
        data2 = [byte[]]@()
        data_sha256 = Get-DspreFieldTextureSha256 -Bytes $secondTexels
        data2_sha256 = $null
    }
    $animationResources = [Collections.Generic.Dictionary[int, object]]::new()
    $animationResources.Add(10, [pscustomobject]@{ textures = @($targetTexture, $secondTexture) })
    $textureCandidates = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $candidateList = [Collections.Generic.List[object]]::new()
    $candidateList.Add([pscustomobject]@{
        pack_name = "synthetic"
        texture = $targetTexture
        palettes = @($palette)
    })
    $textureCandidates.Add("lakep_1", $candidateList)
    $resourceInventory = [pscustomobject]@{
        animation_resources = $animationResources
        texture_candidates = $textureCandidates
    }
    $resolvedVariants = @(Resolve-DspreFieldTextureMaterialVariants `
        -Variants @($inventory.variants) `
        -Descriptor $descriptor `
        -ResourceInventory $resourceInventory `
        -MaterialRoot $dedupRoot)
    $readyVariant = @($resolvedVariants | Where-Object disposition -eq "target_palette_decode")
    $deferredVariant = @($resolvedVariants | Where-Object disposition -eq "unsupported_deferred")
    Assert-FieldTextureEqual 1 $readyVariant.Count "target-palette ready variant"
    Assert-FieldTextureEqual 1 $deferredVariant.Count "target-palette deferred variant"
    Assert-FieldTextureEqual $readySha $readyVariant[0].base_texture_sha256 "target-palette base SHA"
    Assert-FieldTextureEqual $deferredSha $deferredVariant[0].base_texture_sha256 "unmatched base SHA"
    if (
        -not (Test-DspreFieldTextureImagesEqual -Expected $readyImage -Actual $readyVariant[0].frame_images[0]) -or
        -not (Test-DspreFieldTextureImagesEqual -Expected $frameOne -Actual $readyVariant[0].frame_images[1])
    ) {
        throw "Target-palette resolution did not decode exact fldtanime frames."
    }
    $fingerprints = [pscustomobject][ordered]@{
        fldtanime_sha256 = "1" * 64
        support_sha256 = "3" * 64
        builder_sha256 = "4" * 64
        material_catalogs_sha256 = [string]$inventory.material_catalogs_sha256
        texture_packs_sha256 = "5" * 64
    }
    $stageRoot = Join-Path $testRoot "stage"
    $section = New-DspreFieldTextureAnimationSection `
        -Descriptor $descriptor `
        -Variants @($resolvedVariants) `
        -StageRoot $stageRoot `
        -Fingerprints $fingerprints `
        -MaterialCatalogCount 2
    Assert-FieldTextureEqual 1 $section.summary.ready_bindings "ready binding count"
    Assert-FieldTextureEqual 1 $section.summary.deferred_variants "deferred variant count"
    Assert-FieldTextureEqual 2 $section.summary.generated_unique_frames "content-pooled frame count"
    Assert-FieldTextureEqual 3 @($section.bindings[0].frames).Count "timeline frame count"
    Assert-FieldTextureEqual 4 $section.bindings[0].initial_hold_ticks "initial base hold"
    foreach ($frame in @($section.bindings[0].frames)) {
        if (
            [string]$frame.path -notmatch '^field_texture_animations/frames/[0-9a-f]{64}\.png$' -or
            [long]$frame.byte_length -lt 1 -or
            [string]$frame.sha256 -notmatch '^[0-9a-f]{64}$'
        ) {
            throw "Runtime frame record is incomplete."
        }
    }

    $marker = Complete-DspreFieldTextureStage `
        -Section $section `
        -StageRoot $stageRoot `
        -Fingerprints $fingerprints
    if (@($marker.files).Count -ne 3) {
        throw "Stage marker did not record the section and two pooled frames."
    }
    $publishedA = Join-Path $testRoot "published_a"
    $publishedB = Join-Path $testRoot "published_b"
    $null = Publish-DspreFieldTextureStageDirectories `
        -SourceRoot $stageRoot `
        -TargetRoots @($publishedA, $publishedB)
    if (
        -not (Test-DspreFieldTextureStageReusable -RootPath $publishedA -Fingerprints $fingerprints) -or
        -not (Test-DspreFieldTextureStageReusable -RootPath $publishedB -Fingerprints $fingerprints)
    ) {
        throw "Published field texture stages were not reusable."
    }
    $wrongFingerprints = $fingerprints | ConvertTo-Json -Depth 4 | ConvertFrom-Json
    $wrongFingerprints.support_sha256 = "9" * 64
    Assert-FieldTextureFalse `
        (Test-DspreFieldTextureStageReusable -RootPath $publishedA -Fingerprints $wrongFingerprints) `
        "stale input fingerprint"

    $null = Assert-DspreFieldTextureFingerprintsEqual `
        -Expected $fingerprints `
        -Actual ($fingerprints | ConvertTo-Json -Depth 4 | ConvertFrom-Json)
    foreach ($fingerprintName in $script:DspreFieldTextureFingerprintNames) {
        $changedFingerprints = $fingerprints | ConvertTo-Json -Depth 4 | ConvertFrom-Json
        $changedFingerprints.$fingerprintName = "9" * 64
        Assert-FieldTextureThrows {
            Assert-DspreFieldTextureFingerprintsEqual `
                -Expected $fingerprints `
                -Actual $changedFingerprints `
                -Label "Injected publication input change"
        } "changed $fingerprintName"
    }

    $publishedFrame = Get-ChildItem (Join-Path $publishedB "frames") -File -Filter "*.png" | Select-Object -First 1
    $bytes = [IO.File]::ReadAllBytes($publishedFrame.FullName)
    $bytes[0] = $bytes[0] -bxor 0x01
    [IO.File]::WriteAllBytes($publishedFrame.FullName, $bytes)
    Assert-FieldTextureFalse `
        (Test-DspreFieldTextureStageReusable -RootPath $publishedB -Fingerprints $fingerprints) `
        "same-length frame mutation"
    $null = Publish-DspreFieldTextureStageDirectories `
        -SourceRoot $publishedA `
        -TargetRoots @($publishedB)
    if (-not (Test-DspreFieldTextureStageReusable -RootPath $publishedB -Fingerprints $fingerprints)) {
        throw "Focused Godot-stage repair did not restore exact files."
    }

    $committedStage = Join-Path $testRoot "committed_stage"
    Copy-DspreFieldTextureStage -SourceRoot $stageRoot -DestinationRoot $committedStage
    $committedSection = $section | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $committedSection.summary.material_catalogs = 3
    $null = Complete-DspreFieldTextureStage `
        -Section $committedSection `
        -StageRoot $committedStage `
        -Fingerprints $fingerprints
    $oldSectionSha = Get-DspreFieldTextureFileSha256 `
        -Path (Join-Path $publishedA $script:DspreFieldTextureSectionFile)
    $committedSectionSha = Get-DspreFieldTextureFileSha256 `
        -Path (Join-Path $committedStage $script:DspreFieldTextureSectionFile)
    if ($oldSectionSha -eq $committedSectionSha) {
        throw "The cleanup-failure fixture did not create a distinct committed stage."
    }
    $cleanupFailureTarget = [IO.Path]::GetFullPath($publishedA).TrimEnd('\', '/')
    $cleanupFault = {
        param($Phase, $Transaction)

        if (
            $Phase -eq "before_backup_cleanup" -and
            [string]$Transaction.target -eq $cleanupFailureTarget
        ) {
            throw "Injected committed-backup cleanup failure."
        }
    }.GetNewClosure()
    $publication = Publish-DspreFieldTextureStageDirectories `
        -SourceRoot $committedStage `
        -TargetRoots @($publishedA, $publishedB) `
        -FaultInjector $cleanupFault
    Assert-FieldTextureEqual $true $publication.committed "publication commit state"
    Assert-FieldTextureEqual 1 @($publication.backup_cleanup_failures).Count "backup cleanup failure count"
    foreach ($publishedRoot in @($publishedA, $publishedB)) {
        Assert-FieldTextureEqual $committedSectionSha `
            (Get-DspreFieldTextureFileSha256 -Path (Join-Path $publishedRoot $script:DspreFieldTextureSectionFile)) `
            "committed target after cleanup failure"
    }
    $retainedBackup = [string]$publication.backup_cleanup_failures[0].backup
    if (-not (Test-Path -LiteralPath $retainedBackup -PathType Container)) {
        throw "The failed backup cleanup did not leave a recoverable diagnostic directory."
    }
    Assert-FieldTextureEqual $oldSectionSha `
        (Get-DspreFieldTextureFileSha256 -Path (Join-Path $retainedBackup $script:DspreFieldTextureSectionFile)) `
        "retained committed backup"

    $orchestratorText = [IO.File]::ReadAllText(
        (Join-Path $PSScriptRoot "dspre_export_all_matrices.ps1"),
        [Text.Encoding]::UTF8
    )
    if ($orchestratorText -notmatch '(?s)function Invoke-FieldTextureAnimationBuild.*?\$null\s*=\s*Invoke-ProjectScript') {
        throw "The all-matrix fast path does not suppress builder process output before returning its catalog section."
    }
    if ($orchestratorText -notmatch '(?s)if \(\$FieldTextureAnimationsOnly\).*?FieldTextureAnimationsOnly\s*=\s*\$true') {
        throw "The field texture fast path does not constrain texture-sidecar repair to its own frame pool."
    }
    $catalogValidatorText = [IO.File]::ReadAllText(
        (Join-Path $PSScriptRoot "validate_dspre_matrix_catalog.ps1"),
        [Text.Encoding]::UTF8
    )
    if ($catalogValidatorText -notmatch '(?s)if \(\$FieldTextureAnimationsOnly\).*?Assert-FieldTextureAnimationCatalog.*?return') {
        throw "The matrix catalog validator has no focused field-texture validation path."
    }
    $builderText = [IO.File]::ReadAllText(
        (Join-Path $PSScriptRoot "build_dspre_field_texture_animations.ps1"),
        [Text.Encoding]::UTF8
    )
    if ([regex]::Matches(
        $builderText,
        '(?s)\$null\s*=\s*Assert-DspreFieldTextureBuildInputsCurrent.*?\$null\s*=\s*Publish-DspreFieldTextureStageDirectories'
    ).Count -ne 2) {
        throw "Every field texture publication path must recheck all five inputs immediately before publish."
    }
    foreach ($resultProperty in @(
        "reused",
        "generated_stage_changed",
        "godot_stage_repaired",
        "godot_stage_changed"
    )) {
        if ([regex]::Matches($builderText, "(?m)^\s+$resultProperty\s*=").Count -ne 2) {
            throw "The builder result does not declare '$resultProperty' on both return paths."
        }
    }

    Write-Output ([pscustomobject][ordered]@{
        material_catalogs = [int]$inventory.catalog_count
        ready_bindings = [int]$section.summary.ready_bindings
        deferred_variants = [int]$section.summary.deferred_variants
        unique_frames = [int]$section.summary.generated_unique_frames
        timeline_entries = @($section.bindings[0].frames).Count
        marker_files = @($marker.files).Count
        exact_stage_repair = $true
        cross_format_prefix_decode = $true
        committed_cleanup_failure_preserved_targets = $true
        five_input_publish_guard = $true
        orchestrator_output_suppressed = $true
    } | ConvertTo-Json -Compress)
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $null = Assert-DspreTreeHasNoReparsePoints -RootPath $testRoot -Label "Field texture builder test cleanup"
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
