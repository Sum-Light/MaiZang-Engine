Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "strict_json_support.ps1")

$script:BattleRootPrefix = "new-game-project/battle/"
$script:BattleAllowedTextExtensions = @(".gd", ".md", ".ps1", ".tscn", ".uid")
$script:BattleBlockedExtensions = @(
    ".3ds", ".7z", ".aac", ".abc", ".aif", ".aiff", ".avi", ".bin",
    ".blend", ".bmp", ".bz2", ".cab", ".cdat", ".cia", ".csv", ".dae",
    ".dat", ".dds", ".doc", ".docx", ".exe", ".exr", ".fbx", ".flac",
    ".flv", ".gba", ".gif", ".glb", ".gltf", ".gz", ".hdr", ".iso",
    ".jpeg", ".jpg", ".ktx", ".lz", ".lz4", ".m4a", ".m4v", ".mesh",
    ".mid", ".midi", ".mkv", ".mov", ".mp3", ".mp4", ".nds", ".nsp",
    ".obj", ".ogg", ".opus", ".otf", ".pck", ".ply", ".png", ".psd",
    ".qoi", ".rar", ".rom", ".stl", ".svg", ".tab", ".tar", ".tga",
    ".tif", ".tiff", ".ttf", ".txt", ".usd", ".usda", ".usdc", ".usdz",
    ".wav", ".wbfs", ".webm", ".webp", ".wma", ".wmv", ".woff",
    ".woff2", ".xci", ".xcf", ".xls", ".xlsx", ".xz", ".zip", ".zst"
)

function Test-BattleAllowedJsonPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ($RelativePath -in @(
        "new-game-project/battle/manifests/battle_scope_manifest.json",
        "new-game-project/battle/manifests/licensed_source_manifest.template.json",
        "new-game-project/battle/manifests/source_audit_disposition_manifest.template.json",
        "new-game-project/battle/manifests/source_audit/source_audit_policy.json",
        "new-game-project/battle/manifests/source_audit/source_audit_seal.json",
        "new-game-project/battle/manifests/source_audit/source_index_baseline.json",
        "new-game-project/battle/fixtures/synthetic/p0/synthetic_generation_manifest.json",
        "new-game-project/battle/specs/id_manifests/battle_stable_ids.json",
        "new-game-project/battle/specs/presentation/presentation_contracts.json"
    )) {
        return $true
    }
    if ($RelativePath -cmatch '^new-game-project/battle/manifests/work_items/[A-Z0-9_.-]+\.json$') {
        return $true
    }
    if ($RelativePath -cmatch '^new-game-project/battle/specs/mechanisms/[0-9]{10}\.mechanism_spec\.json$' -or
        $RelativePath -cmatch '^new-game-project/battle/specs/events/[0-9]{10}\.event_schema\.json$' -or
        $RelativePath -cmatch '^new-game-project/battle/specs/handlers/[0-9]{10}\.handler_binding\.json$' -or
        $RelativePath -cmatch '^new-game-project/battle/specs/resolvers/[0-9]{10}\.resolver_spec\.json$' -or
        $RelativePath -cmatch '^new-game-project/battle/specs/tests/[0-9]{10}\.test_manifest_entry\.json$') {
        return $true
    }
    if ($RelativePath -cmatch '^new-game-project/battle/tools/battle_catalog/schemas/[a-z0-9_]+\.schema\.json$') {
        return $true
    }
    if ($RelativePath -in @(
        "new-game-project/battle/tools/battle_specs/schemas/stable_id_manifest.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/presentation_contracts.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/mechanism_spec.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/event_schema.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/handler_binding.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/resolver_spec.schema.json",
        "new-game-project/battle/tools/battle_specs/schemas/test_manifest_entry.schema.json"
    )) {
        return $true
    }
    return $false
}

function ConvertFrom-BattleAssetBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    try {
        return $strictUtf8.GetString($Bytes)
    }
    catch {
        throw "$Label is not valid UTF-8."
    }
}

function Test-BattleAssetCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $path = $RelativePath.Replace('\', '/')
    if (-not $path.StartsWith($script:BattleRootPrefix, [StringComparison]::Ordinal) -or
        $path -match '(^|/)\.\.(/|$)') {
        throw "BATTLE_ASSET_PATH_INVALID: '$RelativePath' is outside the battle root."
    }
    if ($path.StartsWith("new-game-project/battle/local_data/", [StringComparison]::Ordinal) -or
        $path.StartsWith("new-game-project/battle/generated/", [StringComparison]::Ordinal) -or
        $path -match '(^|/)(\.tmp|tmp|temp|exports|\.godot)(/|$)' -or
        $path -match '\.(tmp|temp|part)$') {
        if ($path -notin @(
            "new-game-project/battle/local_data/source/.gdignore",
            "new-game-project/battle/local_data/normalized/.gdignore"
        )) {
            throw "BATTLE_ASSET_LOCAL_ARTIFACT: '$path' must remain untracked."
        }
    }
    if ($Bytes.Length -gt 1048576) {
        throw "BATTLE_ASSET_TOO_LARGE: '$path' exceeds the tracked text-file limit."
    }

    $leaf = [IO.Path]::GetFileName($path)
    $extension = [IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($extension -in $script:BattleBlockedExtensions) {
        throw "BATTLE_ASSET_BLOCKED_EXTENSION: '$path' is not a public battle source artifact."
    }
    if ($leaf -in @(".gitignore", ".gdignore")) {
        ConvertFrom-BattleAssetBytes -Bytes $Bytes -Label $path | Out-Null
        return
    }
    if ($extension -in $script:BattleAllowedTextExtensions) {
        ConvertFrom-BattleAssetBytes -Bytes $Bytes -Label $path | Out-Null
        return
    }
    if ($extension -ne ".json") {
        throw "BATTLE_ASSET_TYPE_NOT_ALLOWED: '$path' is not an allowed tracked battle source type."
    }
    if (-not (Test-BattleAllowedJsonPath -RelativePath $path)) {
        throw "BATTLE_ASSET_JSON_PATH_NOT_ALLOWED: '$path' is not an approved battle JSON contract path."
    }
    if ($Bytes.Length -gt 524288) {
        throw "BATTLE_ASSET_JSON_TOO_LARGE: '$path' resembles a catalog or generated payload."
    }

    $text = ConvertFrom-BattleAssetBytes -Bytes $Bytes -Label $path
    if ($text -match '(?i)(^|["'']\s*)[A-Z]:[\\/]' -or
        $text -match '(?i)["'']\\\\[^"'']+') {
        throw "BATTLE_ASSET_ABSOLUTE_PATH: '$path' contains a machine-local path."
    }
    $json = ConvertFrom-BattleStrictJson -Text $text -Label $path
    if ($json -isnot [PSCustomObject]) {
        throw "BATTLE_ASSET_JSON_ROOT: '$path' must contain a JSON object."
    }
    $propertyNames = @($json.PSObject.Properties.Name)
    if ("manifest_mode" -in $propertyNames -and $json.manifest_mode -eq "PRODUCTION") {
        throw "BATTLE_ASSET_PRODUCTION_MANIFEST: production authorization must remain ignored."
    }
    if ($path.EndsWith("licensed_source_manifest.template.json", [StringComparison]::Ordinal)) {
        if ($json.manifest_kind -ne "LICENSED_SOURCE" -or
            $json.manifest_mode -ne "TEMPLATE" -or @($json.records).Count -ne 0) {
            throw "BATTLE_ASSET_LICENSE_TEMPLATE: the public licensed-source template must remain empty."
        }
    }
    if ($path.EndsWith("source_audit_disposition_manifest.template.json", [StringComparison]::Ordinal)) {
        if ($json.manifest_kind -ne "SOURCE_AUDIT_DISPOSITION" -or
            $json.manifest_mode -ne "TEMPLATE" -or @($json.entries).Count -ne 0 -or
            @($json.baseline.repositories).Count -ne 0) {
            throw "BATTLE_ASSET_AUDIT_TEMPLATE: the public source-audit template must remain empty."
        }
    }
    if ($path.EndsWith("synthetic_generation_manifest.json", [StringComparison]::Ordinal)) {
        if ($json.manifest_kind -ne "SYNTHETIC_GENERATION" -or
            $json.source_class -ne "SYNTHETIC_FIXTURE" -or
            $json.allowed_use -ne "TEST_ONLY" -or @($json.records).Count -ne 0) {
            throw "BATTLE_ASSET_SYNTHETIC_MANIFEST: synthetic P0 input must remain test-only and record-free."
        }
    }
}
