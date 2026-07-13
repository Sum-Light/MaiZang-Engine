[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$checker = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\tools\check_battle_scope.ps1"))
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$tempRoot = Join-Path $tempParent ("maizang-battle-scope-{0}" -f [guid]::NewGuid().ToString("N"))
$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Write-TestFile {
    param(
        [string]$Repository,
        [string]$RelativePath,
        [string]$Content = "test`n"
    )

    $path = Join-Path $Repository $RelativePath.Replace('/', '\')
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $Content, $utf8NoBom)
}

function New-TestRepository {
    param([string]$Name)

    $repository = Join-Path $tempRoot $Name
    New-Item -ItemType Directory -Path $repository -Force | Out-Null
    & git -C $repository init --quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Could not initialize test repository $Name."
    }
    & git -C $repository config user.name "Battle Scope Test"
    & git -C $repository config user.email "battle-scope@example.invalid"
    & git -C $repository config core.autocrlf false
    return $repository
}

function Invoke-Checker {
    param(
        [string]$Repository,
        [string]$Mode
    )

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $checker `
            -ProjectRoot $Repository -Mode $Mode 1>$null 2>$null
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $allowed = New-TestRepository "allowed"
    Write-TestFile $allowed "new-game-project/battle/quick_start/test.gd"
    Write-TestFile $allowed "wiki/Battle-Development.md"
    Write-TestFile $allowed "wiki/Change-Log.md"
    Write-TestFile $allowed "wiki/Current-State.md"
    Write-TestFile $allowed ".codex/skills/maizang-engine-godot/references/project-state.md"
    & git -C $allowed add --all
    if ((Invoke-Checker $allowed "Staged") -ne 0) {
        throw "Scope checker rejected an allowed staged battle change."
    }

    $runtime = New-TestRepository "runtime-outside"
    Write-TestFile $runtime "new-game-project/battle/README.md"
    Write-TestFile $runtime "new-game-project/project.godot"
    & git -C $runtime add --all
    if ((Invoke-Checker $runtime "Staged") -eq 0) {
        throw "Scope checker accepted a staged project.godot change."
    }

    $localData = New-TestRepository "local-data"
    Write-TestFile $localData "new-game-project/battle/README.md"
    Write-TestFile $localData "new-game-project/battle/local_data/source/private.json"
    & git -C $localData add --force --all
    if ((Invoke-Checker $localData "Staged") -eq 0) {
        throw "Scope checker accepted force-staged local battle data."
    }

    $reservedPaths = @(
        "new-game-project/battle/GENERATED/private.json",
        "new-game-project/battle/LOCAL_DATA/source/private.json"
    )
    for ($index = 0; $index -lt $reservedPaths.Count; $index++) {
        $reservedCase = New-TestRepository "reserved-directory-case-$index"
        Write-TestFile $reservedCase "new-game-project/battle/README.md"
        Write-TestFile $reservedCase $reservedPaths[$index]
        & git -C $reservedCase add --force --all
        if ((Invoke-Checker $reservedCase "Staged") -eq 0) {
            throw "Scope checker accepted reserved path $($reservedPaths[$index])."
        }
    }

    foreach ($extension in @(".gif", ".m4a", ".obj", ".png", ".rar")) {
        $asset = New-TestRepository ("presentation-asset-{0}" -f $extension.TrimStart('.'))
        Write-TestFile $asset "new-game-project/battle/README.md"
        Write-TestFile $asset "new-game-project/battle/fixtures/synthetic/private$extension"
        & git -C $asset add --force --all
        if ((Invoke-Checker $asset "Staged") -eq 0) {
            throw "Scope checker accepted force-staged asset extension $extension."
        }
    }

    $tempArtifact = New-TestRepository "temp-artifact"
    Write-TestFile $tempArtifact "new-game-project/battle/README.md"
    Write-TestFile $tempArtifact "new-game-project/battle/temp/cache.json"
    & git -C $tempArtifact add --force --all
    if ((Invoke-Checker $tempArtifact "Staged") -eq 0) {
        throw "Scope checker accepted a force-staged temp directory artifact."
    }

    $linkMode = New-TestRepository "link-mode"
    $linkPath = "new-game-project/battle/linked.gd"
    Write-TestFile $linkMode "new-game-project/battle/README.md"
    Write-TestFile $linkMode $linkPath "outside-target`n"
    & git -C $linkMode add --all
    $linkBlob = (& git -C $linkMode hash-object -w -- $linkPath).Trim()
    & git -C $linkMode update-index --add --cacheinfo 120000 $linkBlob $linkPath
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create the synthetic Git link-mode entry."
    }
    if ((Invoke-Checker $linkMode "Staged") -eq 0) {
        throw "Scope checker accepted a staged symbolic-link mode."
    }

    $governanceLink = New-TestRepository "governance-link-mode"
    $governanceLinkPath = "wiki/Change-Log.md"
    Write-TestFile $governanceLink "new-game-project/battle/README.md"
    Write-TestFile $governanceLink $governanceLinkPath "outside-target`n"
    & git -C $governanceLink add --all
    $governanceBlob = (& git -C $governanceLink hash-object -w -- $governanceLinkPath).Trim()
    & git -C $governanceLink update-index --add --cacheinfo `
        120000 $governanceBlob $governanceLinkPath
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create the synthetic governance link-mode entry."
    }
    if ((Invoke-Checker $governanceLink "Staged") -eq 0) {
        throw "Scope checker accepted a governance symbolic-link mode."
    }

    $leadingSpace = New-TestRepository "leading-space"
    Write-TestFile $leadingSpace "new-game-project/battle/README.md"
    Write-TestFile $leadingSpace " new-game-project/battle/outside.gd"
    & git -C $leadingSpace add --all
    if ((Invoke-Checker $leadingSpace "Staged") -eq 0) {
        throw "Scope checker normalized a leading-space path into the battle root."
    }

    $uppercase = New-TestRepository "uppercase-prefix"
    Write-TestFile $uppercase "NEW-GAME-PROJECT/BATTLE/outside.gd"
    & git -C $uppercase add --all
    if ((Invoke-Checker $uppercase "Staged") -eq 0) {
        throw "Scope checker accepted a noncanonical uppercase battle prefix."
    }

    $cleanup = New-TestRepository "cleanup-local-data"
    $leakedPath = "new-game-project/battle/local_data/source/leaked.json"
    Write-TestFile $cleanup $leakedPath
    & git -C $cleanup add --all
    & git -C $cleanup commit --quiet -m "Track synthetic leak"
    Remove-Item -LiteralPath (Join-Path $cleanup $leakedPath.Replace('/', '\')) -Force
    & git -C $cleanup add --update
    if ((Invoke-Checker $cleanup "Staged") -ne 0) {
        throw "Scope checker blocked cleanup of tracked local battle data."
    }

    $untracked = New-TestRepository "untracked-outside"
    Write-TestFile $untracked "new-game-project/battle/README.md"
    Write-TestFile $untracked "tools/rogue.ps1"
    if ((Invoke-Checker $untracked "Worktree") -eq 0) {
        throw "Scope checker accepted an untracked root tool."
    }

    Write-Host "BATTLE_SCOPE_TEST_OK"
}
finally {
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
    if (-not $resolvedTempRoot.StartsWith($tempParent + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean an unsafe test path: $resolvedTempRoot"
    }
    if (Test-Path -LiteralPath $resolvedTempRoot) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}
