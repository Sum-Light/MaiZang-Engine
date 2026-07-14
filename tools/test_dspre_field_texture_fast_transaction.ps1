[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$orchestratorPath = Join-Path $PSScriptRoot "dspre_export_all_matrices.ps1"
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $orchestratorPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -ne 0) {
    throw "The all-matrix orchestrator did not parse for the fast-transaction test."
}
foreach ($functionName in @(
    "Remove-MatrixCatalogPair",
    "Invoke-MatrixCatalogWithdrawalTransaction",
    "Test-FieldTextureCatalogDataEquivalent",
    "Get-FieldTextureAnimationImportStatus",
    "Get-FieldTextureFastImportPlan"
)) {
    $definition = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $functionName
    }, $true)
    if ($null -eq $definition) {
        throw "Fast field-texture helper was not found: $functionName"
    }
    Invoke-Expression $definition.Extent.Text
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Label)

    $threw = $false
    try {
        & $Action
    }
    catch {
        $threw = $true
    }
    if (-not $threw) {
        throw "Expected failure was not observed: $Label"
    }
}

$testRoot = Join-Path (
    Split-Path $PSScriptRoot -Parent
) ".work\field_texture_fast_transaction_test"
if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
$null = [IO.Directory]::CreateDirectory($testRoot)
$utf8NoBom = [Text.UTF8Encoding]::new($false)

try {
    $generatedCatalog = Join-Path $testRoot "generated\matrix_catalog.json"
    $godotCatalog = Join-Path $testRoot "godot\matrix_catalog.json"
    $null = [IO.Directory]::CreateDirectory((Split-Path $generatedCatalog -Parent))
    $null = [IO.Directory]::CreateDirectory((Split-Path $godotCatalog -Parent))
    foreach ($path in @($generatedCatalog, $godotCatalog)) {
        [IO.File]::WriteAllText($path, '{"version":"old"}', $utf8NoBom)
    }

    Assert-Throws {
        Invoke-MatrixCatalogWithdrawalTransaction `
            -GeneratedPath $generatedCatalog `
            -GodotCatalogPath $godotCatalog `
            -Operation {
                if (
                    (Test-Path -LiteralPath $generatedCatalog) -or
                    (Test-Path -LiteralPath $godotCatalog)
                ) {
                    throw "Catalogs were visible when the injected builder started."
                }
                throw "Injected builder interruption"
            }
    } "builder interruption"
    if (
        (Test-Path -LiteralPath $generatedCatalog) -or
        (Test-Path -LiteralPath $godotCatalog)
    ) {
        throw "Builder interruption restored a stale catalog."
    }

    foreach ($path in @($generatedCatalog, $godotCatalog)) {
        [IO.File]::WriteAllText($path, '{"version":"old"}', $utf8NoBom)
    }
    Assert-Throws {
        Invoke-MatrixCatalogWithdrawalTransaction `
            -GeneratedPath $generatedCatalog `
            -GodotCatalogPath $godotCatalog `
            -Operation {
                [IO.File]::WriteAllText($generatedCatalog, '{"version":"new"}', $utf8NoBom)
                [IO.File]::WriteAllText($godotCatalog, '{"version":"new"}', $utf8NoBom)
                throw "Injected validation interruption"
            }
    } "validation interruption"
    if (
        (Test-Path -LiteralPath $generatedCatalog) -or
        (Test-Path -LiteralPath $godotCatalog)
    ) {
        throw "Validation interruption left a partially published catalog pair."
    }

    $null = Invoke-MatrixCatalogWithdrawalTransaction `
        -GeneratedPath $generatedCatalog `
        -GodotCatalogPath $godotCatalog `
        -Operation {
            [IO.File]::WriteAllText($generatedCatalog, '{"version":"new"}', $utf8NoBom)
            [IO.File]::WriteAllText($godotCatalog, '{"version":"new"}', $utf8NoBom)
        }
    if (
        [IO.File]::ReadAllText($generatedCatalog, [Text.Encoding]::UTF8) -cne
        [IO.File]::ReadAllText($godotCatalog, [Text.Encoding]::UTF8)
    ) {
        throw "Successful catalog transaction did not publish an identical pair."
    }
    Assert-Throws {
        throw "Injected post-transaction Godot import failure"
    } "post-transaction import interruption"
    if (
        -not (Test-Path -LiteralPath $generatedCatalog -PathType Leaf) -or
        -not (Test-Path -LiteralPath $godotCatalog -PathType Leaf)
    ) {
        throw "Post-transaction import failure withdrew a valid catalog pair."
    }
    $secondRun = Invoke-MatrixCatalogWithdrawalTransaction `
        -GeneratedPath $generatedCatalog `
        -GodotCatalogPath $godotCatalog `
        -Operation {
            if (
                (Test-Path -LiteralPath $generatedCatalog) -or
                (Test-Path -LiteralPath $godotCatalog)
            ) {
                throw "Second run did not withdraw the prior valid pair before its builder."
            }
            [IO.File]::WriteAllText($generatedCatalog, '{"version":"new"}', $utf8NoBom)
            [IO.File]::WriteAllText($godotCatalog, '{"version":"new"}', $utf8NoBom)
            return [pscustomobject]@{ recovered = $true }
        }
    if (-not [bool]$secondRun.recovered) {
        throw "Second fast transaction did not complete after an injected import failure."
    }

    $frameRelativePath = "field_texture_animations/frames/$('a' * 64).png"
    $section = [pscustomobject][ordered]@{
        schema_version = 1
        source_fps = 30
        summary = [pscustomobject][ordered]@{
            ready_bindings = 1
            deferred_variants = 2
            generated_unique_frames = 1
        }
        bindings = @([pscustomobject][ordered]@{
            frames = @([pscustomobject][ordered]@{ path = $frameRelativePath })
        })
    }
    $catalog = [pscustomobject][ordered]@{
        summary = [pscustomobject][ordered]@{
            field_texture_animation_bindings = 1
            deferred_field_texture_variants = 2
            field_texture_animation_frames = 1
        }
        field_texture_animations = $section
    }
    if (-not (Test-FieldTextureCatalogDataEquivalent -Catalog $catalog -Section $section)) {
        throw "Equivalent field-texture catalog data was reported as changed."
    }
    $catalog.summary.field_texture_animation_frames = 2
    if (Test-FieldTextureCatalogDataEquivalent -Catalog $catalog -Section $section) {
        throw "Changed field-texture summary was reported as equivalent."
    }
    $catalog.summary.field_texture_animation_frames = 1

    $assetRoot = Join-Path $testRoot "assets\platinum"
    $framePath = Join-Path $assetRoot $frameRelativePath.Replace('/', '\')
    $null = [IO.Directory]::CreateDirectory((Split-Path $framePath -Parent))
    [IO.File]::WriteAllBytes($framePath, [byte[]](1, 2, 3, 4))
$cachePath = Join-Path $testRoot ".godot\imported\field-texture-test.ctex"
    $null = [IO.Directory]::CreateDirectory((Split-Path $cachePath -Parent))
    [IO.File]::WriteAllBytes($cachePath, [byte[]](5, 6, 7, 8))
    $validImport = @'
[remap]
path="res://.godot/imported/field-texture-test.ctex"

deps=[]

dest_files=["res://.godot/imported/field-texture-test.ctex"]

[params]
compress/mode=0
mipmaps/generate=false
detect_3d/compress_to=0
'@
    [IO.File]::WriteAllText("$framePath.import", $validImport, $utf8NoBom)

    $buildResult = [pscustomobject]@{
        reused = $true
        godot_stage_repaired = $false
        godot_stage_changed = $false
    }
    $status = Get-FieldTextureAnimationImportStatus -Section $section -AssetRoot $assetRoot
    $plan = Get-FieldTextureFastImportPlan -BuildResult $buildResult -ImportStatus $status
    if (-not $plan.no_op -or $plan.initial_import -or $plan.configure_textures) {
        throw "A fully reused field-texture stage did not produce a no-op import plan."
    }

    [IO.File]::Delete("$framePath.import")
    $status = Get-FieldTextureAnimationImportStatus -Section $section -AssetRoot $assetRoot
    $plan = Get-FieldTextureFastImportPlan -BuildResult $buildResult -ImportStatus $status
    if (-not $plan.initial_import -or -not $plan.configure_textures -or $plan.no_op) {
        throw "A missing sidecar did not request initial import and texture repair."
    }

    [IO.File]::WriteAllText(
        "$framePath.import",
        $validImport.Replace("compress/mode=0", "compress/mode=1"),
        $utf8NoBom
    )
    $status = Get-FieldTextureAnimationImportStatus -Section $section -AssetRoot $assetRoot
    $plan = Get-FieldTextureFastImportPlan -BuildResult $buildResult -ImportStatus $status
    if ($plan.initial_import -or -not $plan.configure_textures -or $plan.no_op) {
        throw "An invalid existing sidecar did not select the one-stage repair path."
    }

    [IO.File]::WriteAllText("$framePath.import", $validImport, $utf8NoBom)
    [IO.File]::Delete($cachePath)
    $status = Get-FieldTextureAnimationImportStatus -Section $section -AssetRoot $assetRoot
    $plan = Get-FieldTextureFastImportPlan -BuildResult $buildResult -ImportStatus $status
    if (-not $plan.initial_import -or $plan.configure_textures -or $plan.no_op) {
        throw "A missing imported cache did not select one initial import without sidecar repair: status=$($status | ConvertTo-Json -Compress) plan=$($plan | ConvertTo-Json -Compress)"
    }
    [IO.File]::WriteAllBytes($cachePath, [byte[]](5, 6, 7, 8))

    $buildResult.godot_stage_repaired = $true
    $buildResult.godot_stage_changed = $true
    [IO.File]::WriteAllText("$framePath.import", $validImport, $utf8NoBom)
    $status = Get-FieldTextureAnimationImportStatus -Section $section -AssetRoot $assetRoot
    $plan = Get-FieldTextureFastImportPlan -BuildResult $buildResult -ImportStatus $status
    if (-not $plan.initial_import -or -not $plan.configure_textures -or $plan.no_op) {
        throw "A changed Godot animation stage did not request the import pipeline."
    }

    $orchestratorText = [IO.File]::ReadAllText($orchestratorPath, [Text.Encoding]::UTF8)
    $textureConfigurationText = [IO.File]::ReadAllText(
        (Join-Path $PSScriptRoot "configure_dspre_godot_textures.ps1"),
        [Text.Encoding]::UTF8
    )
    if ($textureConfigurationText -notmatch '\$textureDestinations\s*=\s*@\(') {
        throw "Field-only texture configuration does not preserve an explicit empty destination array."
    }
    $fastStart = $orchestratorText.IndexOf(
        'if ($FieldTextureAnimationsOnly) {',
        [StringComparison]::Ordinal
    )
    $fastEnd = $orchestratorText.IndexOf(
        '$ApiculaPath = Resolve-ExistingFile',
        $fastStart,
        [StringComparison]::Ordinal
    )
    if ($fastStart -lt 0 -or $fastEnd -le $fastStart) {
        throw "Could not locate the field-texture fast path."
    }
    $fastText = $orchestratorText.Substring($fastStart, $fastEnd - $fastStart)
    $transactionIndex = $fastText.IndexOf(
        'Invoke-MatrixCatalogWithdrawalTransaction',
        [StringComparison]::Ordinal
    )
    $builderIndex = $fastText.IndexOf(
        'Invoke-FieldTextureAnimationBuild',
        [StringComparison]::Ordinal
    )
    if ($transactionIndex -lt 0 -or $builderIndex -le $transactionIndex) {
        throw "The fast builder is not enclosed by the catalog-withdrawal transaction."
    }
    if (
        $fastText.IndexOf('if ($importPlan.no_op)', [StringComparison]::Ordinal) -lt 0 -or
        $fastText.IndexOf('if ($importPlan.initial_import)', [StringComparison]::Ordinal) -lt 0
    ) {
        throw "The fast path does not apply its no-op/import plan."
    }
    $transactionResultCheck = $fastText.IndexOf(
        'Field texture catalog transaction did not return its build state.',
        [StringComparison]::Ordinal
    )
    $importStart = $fastText.IndexOf(
        'if (-not $SkipGodotImport)',
        [StringComparison]::Ordinal
    )
    if ($transactionResultCheck -lt 0 -or $importStart -le $transactionResultCheck) {
        throw "Godot import is still inside the catalog-withdrawal transaction."
    }

    Write-Output ([pscustomobject][ordered]@{
        catalog_withdrawn_before_builder = $true
        failed_publication_withdrawn = $true
        successful_pair_identical = $true
        import_failure_preserved_pair = $true
        second_transaction_recovered = $true
        no_op_import_skipped = $true
        missing_sidecar_two_stage = $true
        invalid_sidecar_one_stage = $true
        missing_cache_one_stage = $true
        changed_stage_imported = $true
        empty_destination_array_preserved = $true
    } | ConvertTo-Json -Compress)
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
