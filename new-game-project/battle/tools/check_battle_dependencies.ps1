[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$BattleRoot = "",

    [ValidateSet("Worktree", "Staged")]
    [string]$Mode = "Worktree"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($BattleRoot)) {
    $BattleRoot = Join-Path $ProjectRoot "new-game-project\battle"
}
$BattleRoot = [IO.Path]::GetFullPath($BattleRoot).TrimEnd('\')

$knownLayers = @(
    "foundation", "catalog", "domain", "rules", "effects", "commands",
    "protocol", "engine", "ai", "persistence", "application", "presentation"
)
$allowedDependencies = @{
    foundation = @("foundation")
    catalog = @("foundation", "catalog")
    domain = @("foundation", "catalog", "domain")
    rules = @("foundation", "catalog", "domain", "rules")
    effects = @("foundation", "catalog", "domain", "effects")
    commands = @("foundation", "domain", "commands")
    protocol = @("foundation", "domain", "commands", "protocol")
    engine = @(
        "foundation", "catalog", "domain", "rules", "effects", "commands",
        "engine"
    )
    ai = @("foundation", "catalog", "domain", "rules", "ai")
    persistence = @("foundation", "catalog", "domain", "persistence")
    application = @(
        "foundation", "catalog", "domain", "rules", "effects", "commands",
        "protocol", "engine", "ai", "persistence", "application"
    )
    presentation = @(
        "foundation", "commands", "protocol", "application", "presentation"
    )
}
$classDependencyExceptions = @{
    engine = @{
        BattleDecisionPayload = "protocol"
        BattleInputRequest = "protocol"
        BattleStepInput = "protocol"
        BattleStepResult = "protocol"
    }
}
$allowedBuiltInBases = @{
    foundation = @("RefCounted")
    catalog = @("RefCounted", "Resource")
    domain = @("RefCounted")
    rules = @("RefCounted")
    effects = @("RefCounted")
    commands = @("RefCounted")
    protocol = @("RefCounted")
    engine = @("RefCounted")
    ai = @("RefCounted")
    persistence = @("RefCounted")
    application = @("RefCounted", "Node")
    presentation = @(
        "RefCounted", "Node", "Node2D", "Node3D", "Control", "CanvasLayer",
        "Window"
    )
}
$coreLayers = @("foundation", "catalog", "domain", "engine", "rules", "effects")
$forbiddenCorePatterns = [ordered]@{
    "Node inheritance" = '(?m)^\s*extends\s+(?:Node|Node2D|Node3D|Control|CanvasLayer|Window)\b'
    "Node API" = '\b(?:Node|Node2D|Node3D|NodePath)\b'
    "SceneTree" = '\bSceneTree\b'
    "scene tree lookup" = '\bget_tree\s*\('
    "node lookup" = '\bget_node(?:_or_null)?\s*\('
    "unique or shorthand node lookup" = '(?m)(?:^|[^\w])(?:\$|%)[A-Za-z_]'
    "runtime resource load" = '\b(?:ResourceLoader\s*\.|load\s*\()'
    "scene or UI path" = '(?i)(?:res://battle/)?(?:presentation|scenes|ui)/'
    "UI class" = '\b(?:Control|CanvasItem|CanvasLayer|Window|BaseButton|Button|Label|LineEdit|TextEdit|ItemList|Tree|AnimationPlayer|AudioStreamPlayer)\b'
    "network API" = '\b(?:HTTPRequest|HTTPClient|ENet\w*|WebSocket\w*|MultiplayerAPI|MultiplayerPeer\w*|PacketPeer\w*|StreamPeerTCP|TCPServer|UDPServer)\b'
    "filesystem I/O" = '\b(?:FileAccess|DirAccess)\b'
    "autoload or singleton lookup" = '\bEngine\.get_singleton\s*\('
}

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$Path
    )

    $resolvedBase = [IO.Path]::GetFullPath($BasePath).TrimEnd('\')
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    if (-not $resolvedPath.StartsWith(
        $resolvedBase + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Path is outside the expected root: $resolvedPath"
    }
    return $resolvedPath.Substring($resolvedBase.Length + 1).Replace('\', '/')
}

function Get-ScriptRecords {
    $records = [Collections.Generic.List[object]]::new()
    if ($Mode -eq "Staged") {
        $battleRelative = Get-RelativePath $ProjectRoot $BattleRoot
        $gitPaths = @(
            & git -C $ProjectRoot ls-files -- "$battleRelative/scripts"
        )
        if ($LASTEXITCODE -ne 0) {
            throw "Could not enumerate staged battle scripts."
        }
        foreach ($gitPathValue in $gitPaths) {
            $gitPath = ([string]$gitPathValue).Replace('\', '/')
            if (-not $gitPath.EndsWith(".gd", [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $contentLines = @(
                & git -C $ProjectRoot show --no-textconv ":$gitPath" 2>&1
            )
            if ($LASTEXITCODE -ne 0) {
                throw "Could not read staged battle script: $gitPath"
            }
            $records.Add([pscustomobject]@{
                Path = $gitPath.Substring($battleRelative.Length + 1)
                Content = ($contentLines -join [Environment]::NewLine) + [Environment]::NewLine
            })
        }
        return $records.ToArray()
    }

    $scriptRoot = Join-Path $BattleRoot "scripts"
    if (-not (Test-Path -LiteralPath $scriptRoot -PathType Container)) {
        throw "Battle script root was not found: $scriptRoot"
    }
    foreach ($file in Get-ChildItem -LiteralPath $scriptRoot -Filter "*.gd" -File -Recurse) {
        $records.Add([pscustomobject]@{
            Path = Get-RelativePath $BattleRoot $file.FullName
            Content = [IO.File]::ReadAllText($file.FullName)
        })
    }
    return $records.ToArray()
}

function Get-Layer {
    param([string]$Path)

    if ($Path -notmatch '^scripts/([^/]+)/') {
        return ""
    }
    return $Matches[1]
}

function Test-ClassDependencyAllowed {
    param(
        [string]$SourceLayer,
        [string]$TargetLayer,
        [string]$ClassName
    )

    if ($TargetLayer -in $allowedDependencies[$SourceLayer]) {
        return $true
    }
    return (
        $classDependencyExceptions.ContainsKey($SourceLayer) -and
        $classDependencyExceptions[$SourceLayer].ContainsKey($ClassName) -and
        $classDependencyExceptions[$SourceLayer][$ClassName] -eq $TargetLayer
    )
}

function Test-CanonicalResourcePath {
    param([string]$Path)

    if (
        -not $Path.StartsWith("res://battle/", [StringComparison]::Ordinal) -or
        $Path.Contains('\') -or
        $Path.Substring(6).Contains('//')
    ) {
        return $false
    }
    foreach ($segment in $Path.Substring(6).Split('/')) {
        if (
            [string]::IsNullOrWhiteSpace($segment) -or
            $segment -in @(".", "..") -or
            $segment -notmatch '^[A-Za-z0-9_.-]+$'
        ) {
            return $false
        }
    }
    return $true
}

$scripts = @(Get-ScriptRecords | Sort-Object Path)
if ($scripts.Count -eq 0) {
    throw "No battle GDScript files were found."
}

$classOwners = @{}
$violations = [Collections.Generic.List[string]]::new()
foreach ($script in $scripts) {
    $layer = Get-Layer $script.Path
    if ($layer -notin $knownLayers) {
        $violations.Add("$($script.Path): unknown dependency layer '$layer'")
        continue
    }
    $classMatches = @(
        [regex]::Matches(
            $script.Content,
            '(?m)^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)\s*$'
        )
    )
    if ($classMatches.Count -gt 1) {
        $violations.Add("$($script.Path): more than one public class_name")
    }
    foreach ($classMatch in $classMatches) {
        $className = $classMatch.Groups[1].Value
        if ($classOwners.ContainsKey($className)) {
            $violations.Add(
                "$($script.Path): duplicate class_name $className also owned by " +
                $classOwners[$className].Path
            )
            continue
        }
        $classOwners[$className] = [pscustomobject]@{
            Path = $script.Path
            Layer = $layer
        }
    }
}

foreach ($script in $scripts) {
    $layer = Get-Layer $script.Path
    if ($layer -notin $knownLayers) {
        continue
    }
    $extendsMatches = @(
        [regex]::Matches(
            $script.Content,
            '(?m)^\s*extends\s+([A-Za-z_][A-Za-z0-9_]*)\s*$'
        )
    )
    foreach ($extendsMatch in $extendsMatches) {
        $baseName = $extendsMatch.Groups[1].Value
        if ($baseName -in $allowedBuiltInBases[$layer]) {
            continue
        }
        if (
            $classOwners.ContainsKey($baseName) -and
            $classOwners[$baseName].Layer -in $allowedDependencies[$layer]
        ) {
            continue
        }
        $violations.Add("$($script.Path): layer $layer cannot extend base $baseName")
    }
    $preloadMatches = @(
        [regex]::Matches(
            $script.Content,
            '\bpreload\s*\(\s*["'']([^"'']+)["'']'
        )
    )
    foreach ($preloadMatch in $preloadMatches) {
        $preloadPath = $preloadMatch.Groups[1].Value
        if (-not $preloadPath.StartsWith("res://", [StringComparison]::Ordinal)) {
            $violations.Add("$($script.Path): preload must use a canonical res:// path")
        }
    }
    $resourceMatches = @(
        [regex]::Matches(
            $script.Content,
            'res://[^"''\s\)\],;]+'
        )
    )
    foreach ($resourceMatch in $resourceMatches) {
        $resourcePath = $resourceMatch.Value
        if (-not (Test-CanonicalResourcePath $resourcePath)) {
            $violations.Add(
                "$($script.Path): noncanonical or external resource path [$resourcePath]"
            )
            continue
        }
        if ($resourcePath -match '^res://battle/scripts/([^/]+)/') {
            $targetLayer = $Matches[1]
            if (
                $targetLayer -notin $knownLayers -or
                $targetLayer -notin $allowedDependencies[$layer]
            ) {
                $violations.Add(
                    "$($script.Path): layer $layer cannot reference resource layer " +
                    "$targetLayer [$resourcePath]"
                )
            }
            continue
        }
        if ($layer -ne "presentation") {
            $violations.Add(
                "$($script.Path): non-presentation layer cannot reference " +
                "battle scene or adapter path [$resourcePath]"
            )
        }
    }
    if ($layer -in $coreLayers) {
        foreach ($entry in $forbiddenCorePatterns.GetEnumerator()) {
            if ($script.Content -match $entry.Value) {
                $violations.Add("$($script.Path): forbidden core dependency [$($entry.Key)]")
            }
        }
    }
    if (
        $layer -eq "foundation" -and
        $script.Content -match '\b(?:Resource|Dictionary|Callable|Object|Variant)\b'
    ) {
        $violations.Add(
            "$($script.Path): foundation must use typed Godot core values only"
        )
    }
    foreach ($className in $classOwners.Keys) {
        $owner = $classOwners[$className]
        if ($owner.Path -eq $script.Path) {
            continue
        }
        if (
            $script.Content -match ('\b' + [regex]::Escape($className) + '\b') -and
            -not (Test-ClassDependencyAllowed -SourceLayer $layer -TargetLayer $owner.Layer -ClassName $className)
        ) {
            $violations.Add(
                "$($script.Path): layer $layer cannot depend on " +
                "$className from layer $($owner.Layer)"
            )
        }
    }
}

Write-Host "Battle dependency audit: $Mode"
Write-Host "Scripts: $($scripts.Count)"
Write-Host "Public classes: $($classOwners.Count)"
foreach ($violation in $violations) {
    Write-Host "  $violation"
}
if ($violations.Count -gt 0) {
    throw "Battle dependency audit rejected $($violations.Count) violation(s)."
}

Write-Host "BATTLE_DEPENDENCIES_OK"
