[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotPath = "",

    [ValidateSet(
        "All", "Q0", "Q0Scene", "P0", "P0Manifest", "P0SourceAudit",
        "P0AssetBoundary", "Scope", "P1", "P1Foundation", "P1Protocol",
        "P1Session", "P1Dependency", "P1Runner"
    )]
    [string[]]$Suite = @("All"),

    [ValidateSet("None", "Fast", "Full")]
    [string]$RepositoryValidation = "None",

    [string]$AnalysisRoot = "D:\PokemonSV-Battle-Architecture",
    [string]$SourceRoot = "",
    [string]$GodotContractRoot = "D:\PokemonSV-Battle-Architecture\docs\godot"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-BattleTest {
    param([int]$ExitCode, [string]$Message)

    [Console]::Error.WriteLine($Message)
    exit $ExitCode
}

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    $candidate = $RequestedPath
    $resolved = ""
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = [Environment]::GetEnvironmentVariable("GODOT4_BIN")
    }
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $resolved = (Resolve-Path -LiteralPath $candidate).Path
        }
        else {
            $command = Get-Command $candidate -CommandType Application `
                -ErrorAction SilentlyContinue
            if ($null -ne $command) {
                $resolved = $command.Source
            }
        }
        if ([string]::IsNullOrWhiteSpace($resolved)) {
            Stop-BattleTest 2 "Godot executable was not found: $candidate"
        }
    }
    else {
        foreach ($commandName in @("godot4", "godot")) {
            $command = Get-Command $commandName -CommandType Application `
                -ErrorAction SilentlyContinue
            if ($null -ne $command) {
                $resolved = $command.Source
                break
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        Stop-BattleTest 2 (
            "Godot was not found. Pass -GodotPath or set the GODOT4_BIN environment variable."
        )
    }

    $versionOutput = @()
    $versionExitCode = -1
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $versionOutput = @(
            & $resolved --version 2>&1 |
                ForEach-Object { [string]$_ }
        )
        $versionExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    $versionText = ($versionOutput -join "`n").Trim()
    if ($versionExitCode -ne 0 -or $versionText -notmatch '(?m)^4\.7\.stable\.') {
        Stop-BattleTest 2 (
            "Godot 4.7 stable is required; '$resolved --version' returned " +
            "exit $versionExitCode and '$versionText'."
        )
    }
    return $resolved
}

function Invoke-BattleProcess {
    param(
        [string]$Label,
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$ExpectedMarker = ""
    )

    Write-Host "BATTLE_TEST_STEP $Label"
    $output = @()
    $exitCode = -1
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(
            & $FilePath @Arguments 2>&1 |
                ForEach-Object { [string]$_ }
        )
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    foreach ($line in $output) {
        Write-Host $line
    }
    if ($exitCode -ne 0) {
        Stop-BattleTest $exitCode "$Label failed with exit code $exitCode."
    }
    if (-not [string]::IsNullOrEmpty($ExpectedMarker)) {
        $outputText = $output -join "`n"
        if ($outputText -match '(?i)leaked at exit|resources still in use') {
            Stop-BattleTest 1 "$Label reported leaked objects or resources."
        }
        $markerCount = [regex]::Matches(
            $outputText,
            [regex]::Escape($ExpectedMarker)
        ).Count
        if ($markerCount -ne 1) {
            Stop-BattleTest 1 (
                "$Label exited 0 with $markerCount copies of required success marker " +
                "'$ExpectedMarker'; expected exactly one."
            )
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$godotProject = Join-Path $ProjectRoot "new-game-project"
if (-not (Test-Path -LiteralPath (Join-Path $godotProject "project.godot") -PathType Leaf)) {
    Stop-BattleTest 2 "Godot project was not found below repository root: $ProjectRoot"
}

$steps = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
function Add-BattleStep {
    param([string]$Name)

    $steps.Add($Name) | Out-Null
}

foreach ($requestedSuite in $Suite) {
    switch ($requestedSuite) {
        "All" {
            foreach ($step in @(
                "P1All", "Q0Scene", "ScopeContract", "P0Manifest",
                "P0AssetBoundary", "P0SourceAudit", "P1Dependency",
                "P1RunnerContract"
            )) {
                Add-BattleStep $step
            }
        }
        "Q0" { Add-BattleStep "Q0Scene" }
        "Q0Scene" { Add-BattleStep "Q0Scene" }
        "P0" {
            Add-BattleStep "P0Manifest"
            Add-BattleStep "P0AssetBoundary"
            Add-BattleStep "P0SourceAudit"
        }
        "P0Manifest" { Add-BattleStep "P0Manifest" }
        "P0SourceAudit" { Add-BattleStep "P0SourceAudit" }
        "P0AssetBoundary" { Add-BattleStep "P0AssetBoundary" }
        "Scope" { Add-BattleStep "ScopeContract" }
        "P1" {
            Add-BattleStep "P1All"
            Add-BattleStep "P1Dependency"
            Add-BattleStep "P1RunnerContract"
        }
        "P1Foundation" { Add-BattleStep "P1Foundation" }
        "P1Protocol" { Add-BattleStep "P1Protocol" }
        "P1Session" { Add-BattleStep "P1Session" }
        "P1Dependency" { Add-BattleStep "P1Dependency" }
        "P1Runner" { Add-BattleStep "P1RunnerContract" }
    }
}
if ($steps.Count -eq 0) {
    Stop-BattleTest 2 "At least one battle suite is required."
}

$godotStepNames = @("P1All", "P1Foundation", "P1Protocol", "P1Session", "Q0Scene", "P1RunnerContract")
$requiresGodot = $RepositoryValidation -eq "Full"
foreach ($step in $godotStepNames) {
    if ($steps.Contains($step)) {
        $requiresGodot = $true
    }
}
$resolvedGodot = ""
if ($requiresGodot) {
    $resolvedGodot = Resolve-GodotExecutable $GodotPath
}

$orderedSteps = @(
    "P1All", "P1Foundation", "P1Protocol", "P1Session", "Q0Scene",
    "ScopeContract", "P0Manifest", "P0AssetBoundary", "P0SourceAudit",
    "P1Dependency", "P1RunnerContract"
)
foreach ($step in $orderedSteps) {
    if (-not $steps.Contains($step)) {
        continue
    }
    switch ($step) {
        "P1All" {
            Invoke-BattleProcess "P1 aggregate" $resolvedGodot @(
                "--no-header", "--headless", "--path", $godotProject,
                "--script", "res://battle/tests/battle_suite_test.gd",
                "--", "--suite=all"
            ) "BATTLE_SUITE_OK suite=all checks=597"
        }
        "P1Foundation" {
            Invoke-BattleProcess "P1 foundation" $resolvedGodot @(
                "--no-header", "--headless", "--path", $godotProject,
                "--script", "res://battle/tests/battle_suite_test.gd",
                "--", "--suite=p1_foundation"
            ) "BATTLE_SUITE_OK suite=p1_foundation checks=164"
        }
        "P1Protocol" {
            Invoke-BattleProcess "P1 protocol/command" $resolvedGodot @(
                "--no-header", "--headless", "--path", $godotProject,
                "--script", "res://battle/tests/battle_suite_test.gd",
                "--", "--suite=p1_protocol_command"
            ) "BATTLE_SUITE_OK suite=p1_protocol_command checks=151"
        }
        "P1Session" {
            Invoke-BattleProcess "P1 Session lifecycle" $resolvedGodot @(
                "--no-header", "--headless", "--path", $godotProject,
                "--script", "res://battle/tests/battle_suite_test.gd",
                "--", "--suite=p1_session_lifecycle"
            ) "BATTLE_SUITE_OK suite=p1_session_lifecycle checks=282"
        }
        "Q0Scene" {
            Invoke-BattleProcess "Q0 scene smoke" $resolvedGodot @(
                "--no-header", "--headless", "--path", $godotProject,
                "--script", "res://battle/tests/q0_scene_smoke_test.gd"
            ) "BATTLE_Q0_SCENE_SMOKE_OK"
        }
        "ScopeContract" {
            Invoke-BattleProcess "battle scope contract" "powershell.exe" @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                (Join-Path $godotProject "battle\tests\check_battle_scope_test.ps1")
            )
        }
        "P0Manifest" {
            Invoke-BattleProcess "P0 manifest contracts" "powershell.exe" @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                (Join-Path $godotProject "battle\tests\catalog\p0_manifest_contract_test.ps1"),
                "-ProjectRoot", $ProjectRoot,
                "-GodotContractRoot", $GodotContractRoot
            )
        }
        "P0AssetBoundary" {
            Invoke-BattleProcess "P0 asset boundary" "powershell.exe" @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                (Join-Path $godotProject "battle\tests\catalog\p0_asset_boundary_test.ps1"),
                "-ProjectRoot", $ProjectRoot
            )
        }
        "P0SourceAudit" {
            $sourceAuditArguments = @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                (Join-Path $godotProject "battle\tests\catalog\p0_source_audit_test.ps1"),
                "-ProjectRoot", $ProjectRoot,
                "-AnalysisRoot", $AnalysisRoot
            )
            if (-not [string]::IsNullOrWhiteSpace($SourceRoot)) {
                $sourceAuditArguments += @("-SourceRoot", $SourceRoot)
            }
            $sourceAuditArguments += @("-GodotContractRoot", $GodotContractRoot)
            Invoke-BattleProcess "P0 source audit" "powershell.exe" `
                $sourceAuditArguments
        }
        "P1Dependency" {
            Invoke-BattleProcess "P1 dependency gate" "powershell.exe" @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                (Join-Path $godotProject "battle\tests\foundation\p1_dependency_gate_test.ps1"),
                "-ProjectRoot", $ProjectRoot
            )
        }
        "P1RunnerContract" {
            Invoke-BattleProcess "P1 suite runner contract" "powershell.exe" @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                (Join-Path $godotProject "battle\tests\tools\p1_suite_runner_test.ps1"),
                "-ProjectRoot", $ProjectRoot,
                "-GodotPath", $resolvedGodot
            )
        }
    }
}

if ($RepositoryValidation -ne "None") {
    $repositoryArguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
        (Join-Path $ProjectRoot "tools\validate_repository.ps1"),
        "-ProjectRoot", $ProjectRoot
    )
    if ($RepositoryValidation -eq "Full") {
        $repositoryArguments += @("-Full", "-GodotPath", $resolvedGodot)
    }
    Invoke-BattleProcess "repository validation ($RepositoryValidation)" `
        "powershell.exe" $repositoryArguments
}

Write-Host (
    "BATTLE_TESTS_OK suites={0} repository_validation={1}" -f `
        ($Suite -join ","), $RepositoryValidation
)
exit 0
