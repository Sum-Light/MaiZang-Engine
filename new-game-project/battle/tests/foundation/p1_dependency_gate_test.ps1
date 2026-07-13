[CmdletBinding()]
param(
    [string]$ProjectRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battleRoot = Join-Path $ProjectRoot "new-game-project\battle"
$gatePath = Join-Path $battleRoot "tools\check_battle_dependencies.ps1"
if (-not (Test-Path -LiteralPath $gatePath -PathType Leaf)) {
    throw "Dependency gate was not found: $gatePath"
}

$scriptsToParse = @(
    Get-ChildItem -LiteralPath $battleRoot -Filter "*.ps1" -File -Recurse
)
foreach ($script in $scriptsToParse) {
    [void][scriptblock]::Create([IO.File]::ReadAllText($script.FullName))
}

function Write-Fixture {
    param(
        [string]$Root,
        [string]$RelativePath,
        [string]$Content
    )

    $path = Join-Path $Root $RelativePath
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
    [IO.File]::WriteAllText($path, $Content, [Text.UTF8Encoding]::new($false))
}

function Test-Gate {
    param(
        [string]$Root,
        [bool]$ShouldPass,
        [string]$Label,
        [ValidateSet("Worktree", "Staged")]
        [string]$Mode = "Worktree",
        [string]$GateProjectRoot = $ProjectRoot
    )

    $passed = $true
    try {
        & $gatePath -ProjectRoot $GateProjectRoot -BattleRoot $Root -Mode $Mode *>$null
    }
    catch {
        $passed = $false
    }
    if ($passed -ne $ShouldPass) {
        throw "Dependency gate fixture '$Label' expected pass=$ShouldPass, got pass=$passed."
    }
}

& $gatePath -ProjectRoot $ProjectRoot -BattleRoot $battleRoot -Mode Worktree

$tempRoot = Join-Path (
    [IO.Path]::GetTempPath()
) ("maizang_battle_dependencies_" + [Guid]::NewGuid().ToString("N"))
try {
    Write-Fixture $tempRoot "scripts\foundation\fixture_value.gd" @'
class_name FixtureValue
extends RefCounted
'@
    Write-Fixture $tempRoot "scripts\engine\fixture_engine.gd" @'
class_name FixtureEngine
extends RefCounted

var value: FixtureValue
'@
    Test-Gate $tempRoot $true "valid inward dependency"

    Write-Fixture $tempRoot "scripts\engine\fixture_engine.gd" @'
class_name FixtureEngine
extends Node
'@
    Test-Gate $tempRoot $false "core Node inheritance"

    Write-Fixture $tempRoot "scripts\engine\fixture_engine.gd" @'
class_name FixtureEngine
extends RefCounted

func read_runtime_resource() -> void:
    load("res://synthetic.tres")
'@
    Test-Gate $tempRoot $false "runtime load"

    Write-Fixture $tempRoot "scripts\engine\fixture_engine.gd" @'
class_name FixtureEngine
extends RefCounted
'@
    Write-Fixture $tempRoot "scripts\foundation\fixture_value.gd" @'
class_name FixtureValue
extends RefCounted

const ENGINE_SCRIPT = preload("res://battle/scripts/engine/fixture_engine.gd")
'@
    Test-Gate $tempRoot $false "outward preload path"

    Write-Fixture $tempRoot "scripts\foundation\fixture_value.gd" @'
class_name FixtureValue
extends RefCounted

const WORLD_SCRIPT = preload("res://scripts/player_controller.gd")
'@
    Test-Gate $tempRoot $false "preload outside battle"

    Write-Fixture $tempRoot "scripts\foundation\fixture_value.gd" @'
class_name FixtureValue
extends RefCounted

func allocate_node() -> Node:
    return Node.new()
'@
    Test-Gate $tempRoot $false "Node API without Node inheritance"

    Write-Fixture $tempRoot "scripts\engine\fixture_engine.gd" @'
class_name FixtureEngine
extends Button
'@
    Test-Gate $tempRoot $false "indirect UI Node inheritance"

    Write-Fixture $tempRoot "scripts\engine\fixture_engine.gd" @'
class_name FixtureEngine
extends RefCounted

var peer: MultiplayerPeer
'@
    Test-Gate $tempRoot $false "network base API"

    Write-Fixture $tempRoot "scripts\engine\fixture_engine.gd" @'
class_name FixtureEngine
extends RefCounted

var owner_path: NodePath
'@
    Test-Gate $tempRoot $false "NodePath API"

    Write-Fixture $tempRoot "scripts\engine\fixture_engine.gd" @'
class_name FixtureEngine
extends RefCounted
'@
    Write-Fixture $tempRoot "scripts\foundation\fixture_value.gd" @'
class_name FixtureValue
extends RefCounted

const TRAVERSAL = preload("res://battle/scripts/foundation/../engine/fixture_engine.gd")
'@
    Test-Gate $tempRoot $false "resource path traversal"
    Write-Fixture $tempRoot "scripts\foundation\fixture_value.gd" @'
class_name FixtureValue
extends RefCounted
'@

    Write-Fixture $tempRoot "scripts\application\fixture_application.gd" @'
class_name FixtureApplication
extends RefCounted

const WORLD_SCRIPT = preload("res://scripts/player_controller.gd")
'@
    Test-Gate $tempRoot $false "application preload outside battle"
    Write-Fixture $tempRoot "scripts\application\fixture_application.gd" @'
class_name FixtureApplication
extends RefCounted
'@

    Write-Fixture $tempRoot "scripts\protocol\fixture_protocol.gd" @'
class_name FixtureProtocol
extends RefCounted
'@
    Write-Fixture $tempRoot "scripts\engine\fixture_engine.gd" @'
class_name FixtureEngine
extends RefCounted

var protocol: FixtureProtocol
'@
    Test-Gate $tempRoot $false "generic engine to protocol dependency"

    Write-Fixture $tempRoot "scripts\protocol\battle_step_input.gd" @'
class_name BattleStepInput
extends RefCounted
'@
    Write-Fixture $tempRoot "scripts\engine\fixture_engine.gd" @'
class_name FixtureEngine
extends RefCounted

var input: BattleStepInput
'@
    Test-Gate $tempRoot $true "reviewed engine protocol DTO exception"
    Remove-Item -LiteralPath (
        Join-Path $tempRoot "scripts\protocol\battle_step_input.gd"
    ) -Force
    Write-Fixture $tempRoot "scripts\presentation\battle_step_input.gd" @'
class_name BattleStepInput
extends RefCounted
'@
    Test-Gate $tempRoot $false "DTO exception in wrong target layer"

    Write-Fixture $tempRoot "scripts\engine\fixture_engine.gd" @'
class_name FixtureEngine
extends RefCounted
'@
    Write-Fixture $tempRoot "scripts\foundation\fixture_value.gd" @'
class_name FixtureValue
extends RefCounted

var engine: FixtureEngine
'@
    Test-Gate $tempRoot $false "outward foundation dependency"

    Write-Fixture $tempRoot "scripts\foundation\fixture_value.gd" @'
class_name FixtureValue
extends RefCounted
'@
    Write-Fixture $tempRoot "scripts\unknown\unknown_value.gd" @'
class_name UnknownValue
extends RefCounted
'@
    Test-Gate $tempRoot $false "unknown layer"

    $stagedRepository = Join-Path $tempRoot "staged-repository"
    [void](New-Item -ItemType Directory -Path $stagedRepository -Force)
    & git -C $stagedRepository init --quiet
    & git -C $stagedRepository config user.name "Battle Dependency Test"
    & git -C $stagedRepository config user.email "battle-dependency@example.invalid"
    & git -C $stagedRepository config core.autocrlf false
    $stagedBattleRoot = Join-Path $stagedRepository "new-game-project\battle"
    $stagedScript = "scripts\foundation\staged_value.gd"
    $safeScript = @'
class_name StagedValue
extends RefCounted
'@
    Write-Fixture $stagedBattleRoot $stagedScript $safeScript
    & git -C $stagedRepository add --all
    Test-Gate $stagedBattleRoot $true "safe staged blob" "Staged" $stagedRepository

    Write-Fixture $stagedBattleRoot $stagedScript @'
class_name StagedValue
extends Node
'@
    & git -C $stagedRepository add --all
    Write-Fixture $stagedBattleRoot $stagedScript $safeScript
    Test-Gate $stagedBattleRoot $false "forbidden staged blob" "Staged" $stagedRepository
    Test-Gate $stagedBattleRoot $true "safe worktree over forbidden index" "Worktree" $stagedRepository
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host "BATTLE_P1_DEPENDENCY_GATE_OK"
