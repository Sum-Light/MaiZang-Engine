[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [Parameter(Mandatory = $true)][string]$GodotPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$godotProject = Join-Path $ProjectRoot "new-game-project"
$suiteScript = "res://battle/tests/battle_suite_test.gd"
$toolPath = Join-Path $godotProject "battle\tools\test_battle.ps1"
$checks = 0

function Assert-Condition {
    param([bool]$Condition, [string]$Message)

    $script:checks += 1
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-CapturedProcess {
    param([string]$FilePath, [string[]]$Arguments)

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(
            & $FilePath @Arguments 2>&1 |
                ForEach-Object { [string]$_ }
        )
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = $output
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
}

$baseGodotArguments = @(
    "--no-header", "--headless", "--path", $godotProject,
    "--script", $suiteScript
)
$cases = @(
    @{
        Label = "default all"
        Arguments = @()
        ExitCode = 0
        ExpectedLine = "BATTLE_SUITE_OK suite=all checks=597"
    },
    @{
        Label = "explicit all"
        Arguments = @("--suite=all")
        ExitCode = 0
        ExpectedLine = "BATTLE_SUITE_OK suite=all checks=597"
    },
    @{
        Label = "foundation"
        Arguments = @("--suite=p1_foundation")
        ExitCode = 0
        ExpectedLine = "BATTLE_SUITE_OK suite=p1_foundation checks=164"
    },
    @{
        Label = "protocol"
        Arguments = @("--suite", "p1_protocol_command")
        ExitCode = 0
        ExpectedLine = "BATTLE_SUITE_OK suite=p1_protocol_command checks=151"
    },
    @{
        Label = "Session"
        Arguments = @("--suite=p1_session_lifecycle")
        ExitCode = 0
        ExpectedLine = "BATTLE_SUITE_OK suite=p1_session_lifecycle checks=282"
    },
    @{
        Label = "unknown suite"
        Arguments = @("--suite=unknown")
        ExitCode = 2
        ExpectedLine = ""
    },
    @{
        Label = "duplicate suite"
        Arguments = @("--suite=all", "--suite=p1_foundation")
        ExitCode = 2
        ExpectedLine = ""
    },
    @{
        Label = "missing suite value"
        Arguments = @("--suite")
        ExitCode = 2
        ExpectedLine = ""
    },
    @{
        Label = "unknown argument"
        Arguments = @("--other=value")
        ExitCode = 2
        ExpectedLine = ""
    }
)

foreach ($case in $cases) {
    $arguments = @($baseGodotArguments)
    if (@($case.Arguments).Count -gt 0) {
        $arguments += "--"
        $arguments += @($case.Arguments)
    }
    $result = Invoke-CapturedProcess $GodotPath $arguments
    Assert-Condition ($result.ExitCode -eq [int]$case.ExitCode) (
        "$($case.Label) returned $($result.ExitCode); expected $($case.ExitCode).`n" +
        ($result.Output -join "`n")
    )
    if (-not [string]::IsNullOrEmpty([string]$case.ExpectedLine)) {
        Assert-Condition (($result.Output -join "`n").Contains([string]$case.ExpectedLine)) (
            "$($case.Label) did not print '$($case.ExpectedLine)'."
        )
    }
    $resultText = $result.Output -join "`n"
    if ([int]$case.ExitCode -eq 0) {
        Assert-Condition ($resultText -notmatch '(?i)leaked at exit|resources still in use') (
            "$($case.Label) reported leaked objects or resources."
        )
    }
    else {
        Assert-Condition (-not $resultText.Contains("BATTLE_SUITE_OK")) (
            "$($case.Label) printed the final success marker."
        )
    }
    if ([string]$case.Label -eq "default all") {
        $foundationIndex = $resultText.IndexOf("suite=p1_foundation", [StringComparison]::Ordinal)
        $protocolIndex = $resultText.IndexOf("suite=p1_protocol_command", [StringComparison]::Ordinal)
        $sessionIndex = $resultText.IndexOf("suite=p1_session_lifecycle", [StringComparison]::Ordinal)
        $allIndex = $resultText.LastIndexOf("BATTLE_SUITE_OK suite=all", [StringComparison]::Ordinal)
        Assert-Condition (
            $foundationIndex -ge 0 -and
            $protocolIndex -gt $foundationIndex -and
            $sessionIndex -gt $protocolIndex -and
            $allIndex -gt $sessionIndex
        ) "Aggregate suites did not run in Foundation, Protocol, Session order."
    }
}

$toolResult = Invoke-CapturedProcess "powershell.exe" @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $toolPath,
    "-ProjectRoot", $ProjectRoot,
    "-GodotPath", $GodotPath,
    "-Suite", "P1Foundation",
    "-RepositoryValidation", "None"
)
Assert-Condition ($toolResult.ExitCode -eq 0) (
    "test_battle.ps1 single-suite invocation failed.`n" + ($toolResult.Output -join "`n")
)
Assert-Condition (($toolResult.Output -join "`n").Contains(
    "BATTLE_TESTS_OK suites=P1Foundation repository_validation=None"
)) "test_battle.ps1 did not report its selected single suite."
Assert-Condition (($toolResult.Output -join "`n").Contains(
    "BATTLE_SUITE_OK suite=p1_foundation checks=164"
)) "test_battle.ps1 did not run the selected Foundation suite."
Assert-Condition (-not ($toolResult.Output -join "`n").Contains(
    "BATTLE_SUITE_OK suite=all"
)) "test_battle.ps1 single-suite selection also ran the aggregate."

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$tempRoot = [IO.Path]::GetFullPath((Join-Path $tempParent (
    "maizang-battle-runner-{0}" -f [guid]::NewGuid().ToString("N")
)))
if (-not $tempRoot.StartsWith($tempParent + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe P1 suite runner temp path: $tempRoot"
}
try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $tempProject = Join-Path $tempRoot "project"
    $tempBattle = Join-Path $tempProject "battle"
    New-Item -ItemType Directory -Path $tempBattle -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $tempProject "project.godot"),
        @'
; Engine configuration file.
config_version=5

[application]

config/name="MaiZang Battle Runner Test"

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'@ + "`n",
        [Text.UTF8Encoding]::new($false)
    )
    Copy-Item -LiteralPath (Join-Path $godotProject "battle\scripts") `
        -Destination $tempBattle -Recurse
    Copy-Item -LiteralPath (Join-Path $godotProject "battle\tests") `
        -Destination $tempBattle -Recurse

    $scanResult = Invoke-CapturedProcess $GodotPath @(
        "--no-header", "--headless", "--editor", "--path", $tempProject, "--quit"
    )
    Assert-Condition ($scanResult.ExitCode -eq 0) (
        "Battle-only project script scan failed.`n" + ($scanResult.Output -join "`n")
    )

    $noAssetArguments = @(
        "--no-header", "--headless", "--path", $tempProject,
        "--script", $suiteScript
    )
    $noAssetResult = Invoke-CapturedProcess $GodotPath $noAssetArguments
    Assert-Condition ($noAssetResult.ExitCode -eq 0) (
        "P1 aggregate failed in the project.godot + battle-only project.`n" +
        ($noAssetResult.Output -join "`n")
    )
    Assert-Condition (($noAssetResult.Output -join "`n").Contains(
        "BATTLE_SUITE_OK suite=all checks=597"
    )) "Battle-only aggregate did not report all 597 checks."
    Assert-Condition (($noAssetResult.Output -join "`n") -notmatch (
        '(?i)leaked at exit|resources still in use'
    )) "Battle-only aggregate reported leaked objects or resources."

    $tempRunner = Join-Path $tempBattle "tests\battle_suite_test.gd"
    $runnerText = [IO.File]::ReadAllText($tempRunner, [Text.Encoding]::UTF8)
    $successPrint = 'print("BATTLE_SUITE_OK suite=%s checks=%d" % [suite, checks])'
    $duplicateMarkerText = $runnerText.Replace(
        $successPrint,
        $successPrint + "`n`t" + $successPrint
    )
    Assert-Condition ($duplicateMarkerText -ne $runnerText) (
        "Could not create the synthetic duplicate-marker failure."
    )
    [IO.File]::WriteAllText(
        $tempRunner,
        $duplicateMarkerText,
        [Text.UTF8Encoding]::new($false)
    )
    $duplicateAggregate = Invoke-CapturedProcess $GodotPath $noAssetArguments
    Assert-Condition ($duplicateAggregate.ExitCode -eq 1) (
        "Duplicate aggregate markers returned $($duplicateAggregate.ExitCode), not 1."
    )
    Assert-Condition (-not ($duplicateAggregate.Output -join "`n").Contains(
        "BATTLE_SUITE_OK suite=all"
    )) "Duplicate child markers allowed the aggregate success marker."
    [IO.File]::WriteAllText(
        $tempRunner,
        $runnerText,
        [Text.UTF8Encoding]::new($false)
    )

    $invalidCountText = [regex]::Replace(
        $runnerText,
        '("p1_foundation",\r?\n\s+FOUNDATION_VECTORS_PATH,\r?\n\s+)164,',
        '${1}1,',
        1
    )
    Assert-Condition ($invalidCountText -ne $runnerText) (
        "Could not create the synthetic assertion-count failure."
    )
    [IO.File]::WriteAllText(
        $tempRunner,
        $invalidCountText,
        [Text.UTF8Encoding]::new($false)
    )
    $assertionFailure = Invoke-CapturedProcess $GodotPath @(
        "--no-header", "--headless", "--path", $tempProject,
        "--script", $suiteScript, "--", "--suite=p1_foundation"
    )
    Assert-Condition ($assertionFailure.ExitCode -eq 1) (
        "Synthetic assertion failure returned $($assertionFailure.ExitCode), not 1."
    )
    Assert-Condition (-not ($assertionFailure.Output -join "`n").Contains(
        "BATTLE_SUITE_OK"
    )) "Failed suite printed the final success marker."

    $fakeRepository = Join-Path $tempRoot "full-repository"
    $fakeGodotProject = Join-Path $fakeRepository "new-game-project"
    $fakeBattle = Join-Path $fakeGodotProject "battle"
    $fakeTools = Join-Path $fakeRepository "tools"
    New-Item -ItemType Directory -Path $fakeBattle -Force | Out-Null
    New-Item -ItemType Directory -Path $fakeTools -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $tempProject "project.godot") `
        -Destination $fakeGodotProject
    Copy-Item -LiteralPath (Join-Path $godotProject "battle\scripts") `
        -Destination $fakeBattle -Recurse
    Copy-Item -LiteralPath (Join-Path $godotProject "battle\tests") `
        -Destination $fakeBattle -Recurse
    $fakeScan = Invoke-CapturedProcess $GodotPath @(
        "--no-header", "--headless", "--editor", "--path", $fakeGodotProject, "--quit"
    )
    Assert-Condition ($fakeScan.ExitCode -eq 0) (
        "Fake Full repository script scan failed.`n" + ($fakeScan.Output -join "`n")
    )

    $missingProject = Invoke-CapturedProcess "powershell.exe" @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $toolPath,
        "-ProjectRoot", (Join-Path $tempRoot "missing-repository"),
        "-GodotPath", $GodotPath,
        "-Suite", "P1Foundation"
    )
    Assert-Condition ($missingProject.ExitCode -eq 2) (
        "Missing project returned $($missingProject.ExitCode), not usage/config code 2."
    )
    $missingGodot = Invoke-CapturedProcess "powershell.exe" @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $toolPath,
        "-ProjectRoot", $fakeRepository,
        "-GodotPath", (Join-Path $tempRoot "missing-godot.exe"),
        "-Suite", "P1Foundation"
    )
    Assert-Condition ($missingGodot.ExitCode -eq 2) (
        "Missing Godot returned $($missingGodot.ExitCode), not usage/config code 2."
    )

    $fullMarker = Join-Path $tempRoot "full-validator-arguments.txt"
    $escapedMarker = $fullMarker.Replace("'", "''")
    $fakeValidator = Join-Path $fakeTools "validate_repository.ps1"
    [IO.File]::WriteAllText(
        $fakeValidator,
        @"
[CmdletBinding()]
param(
    [string]`$ProjectRoot = "",
    [string]`$GodotPath = "",
    [switch]`$Full
)
[IO.File]::WriteAllText(
    '$escapedMarker',
    ("full={0}`ngodot={1}`n" -f `$Full.IsPresent, `$GodotPath),
    [Text.UTF8Encoding]::new(`$false)
)
exit 41
"@,
        [Text.UTF8Encoding]::new($false)
    )
    $fullPropagation = Invoke-CapturedProcess "powershell.exe" @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $toolPath,
        "-ProjectRoot", $fakeRepository,
        "-GodotPath", $GodotPath,
        "-Suite", "P1Foundation",
        "-RepositoryValidation", "Full"
    )
    Assert-Condition ($fullPropagation.ExitCode -eq 41) (
        "Full validator failure returned $($fullPropagation.ExitCode), not 41."
    )
    Assert-Condition (Test-Path -LiteralPath $fullMarker -PathType Leaf) (
        "Full repository validator was not invoked."
    )
    $fullArguments = [IO.File]::ReadAllText($fullMarker, [Text.Encoding]::UTF8)
    Assert-Condition $fullArguments.Contains("full=True") (
        "Repository validator did not receive -Full."
    )
    Assert-Condition $fullArguments.Contains("godot=$GodotPath") (
        "Repository validator did not receive the selected Godot path."
    )

    $nonGodot = Invoke-CapturedProcess "powershell.exe" @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $toolPath,
        "-ProjectRoot", $ProjectRoot,
        "-GodotPath", $env:ComSpec,
        "-Suite", "P1Foundation",
        "-RepositoryValidation", "None"
    )
    Assert-Condition ($nonGodot.ExitCode -eq 2) (
        "Non-Godot executable returned $($nonGodot.ExitCode), not config code 2."
    )

    $markerlessGodot = Join-Path $tempRoot "markerless-godot.cmd"
    [IO.File]::WriteAllText(
        $markerlessGodot,
        @'
@echo off
if "%~1"=="--version" (
  echo 4.7.stable.test.fake
  exit /b 0
)
exit /b 0
'@ + "`r`n",
        [Text.Encoding]::ASCII
    )
    $markerless = Invoke-CapturedProcess "powershell.exe" @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $toolPath,
        "-ProjectRoot", $ProjectRoot,
        "-GodotPath", $markerlessGodot,
        "-Suite", "P1Foundation",
        "-RepositoryValidation", "None"
    )
    Assert-Condition ($markerless.ExitCode -eq 1) (
        "Markerless fake Godot returned $($markerless.ExitCode), not test-failure code 1."
    )

    $duplicateGodot = Join-Path $tempRoot "duplicate-marker-godot.cmd"
    [IO.File]::WriteAllText(
        $duplicateGodot,
        @'
@echo off
if "%~1"=="--version" (
  echo 4.7.stable.test.fake
  exit /b 0
)
echo BATTLE_SUITE_OK suite=p1_foundation checks=164
echo BATTLE_SUITE_OK suite=p1_foundation checks=164
exit /b 0
'@ + "`r`n",
        [Text.Encoding]::ASCII
    )
    $duplicateMarker = Invoke-CapturedProcess "powershell.exe" @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $toolPath,
        "-ProjectRoot", $ProjectRoot,
        "-GodotPath", $duplicateGodot,
        "-Suite", "P1Foundation",
        "-RepositoryValidation", "None"
    )
    Assert-Condition ($duplicateMarker.ExitCode -eq 1) (
        "Duplicate-marker fake Godot returned $($duplicateMarker.ExitCode), not 1."
    )

    $failingGodot = Join-Path $tempRoot "fake-godot.cmd"
    [IO.File]::WriteAllText(
        $failingGodot,
        @'
@echo off
if "%~1"=="--version" (
  echo 4.7.stable.test.fake
  exit /b 0
)
exit /b 37
'@ + "`r`n",
        [Text.Encoding]::ASCII
    )
    $propagation = Invoke-CapturedProcess "powershell.exe" @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $toolPath,
        "-ProjectRoot", $ProjectRoot,
        "-GodotPath", $failingGodot,
        "-Suite", "P1Foundation",
        "-RepositoryValidation", "Fast"
    )
    Assert-Condition ($propagation.ExitCode -eq 37) (
        "test_battle.ps1 returned $($propagation.ExitCode) instead of child exit code 37."
    )
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
        if (-not $resolvedTempRoot.StartsWith(
            $tempParent + '\',
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Unsafe P1 suite runner cleanup path: $resolvedTempRoot"
        }
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}

$toolText = [IO.File]::ReadAllText($toolPath, [Text.Encoding]::UTF8)
foreach ($forbidden in @(
    "q0_console_render_test.gd", "--editor", "--import",
    "rendering-driver", "assets\platinum"
)) {
    Assert-Condition (-not $toolText.Contains($forbidden)) (
        "Default battle runner contains forbidden renderer/asset token '$forbidden'."
    )
}
foreach ($required in @("validate_repository.ps1", '"-Full"', "RepositoryValidation")) {
    Assert-Condition $toolText.Contains($required) (
        "Battle runner is missing repository-validation token '$required'."
    )
}

$expectedChecks = 57
if ($checks -ne $expectedChecks) {
    throw "P1 suite runner test stopped at $checks checks; expected $expectedChecks."
}
Write-Host "BATTLE_P1_SUITE_RUNNER_OK checks=$checks"
exit 0
