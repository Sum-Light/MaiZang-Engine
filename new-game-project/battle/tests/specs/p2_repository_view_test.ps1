[CmdletBinding()]
param([string]$ProjectRoot = "")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\.."
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$battleRoot = Join-Path $ProjectRoot "new-game-project\battle"
$repositorySupportPath = Join-Path $battleRoot (
    "tools\battle_specs\validators\p2_repository_view_support.ps1"
)
$specSetSupportPath = Join-Path $battleRoot (
    "tools\battle_specs\validators\p2_spec_set_support.ps1"
)
$stableManifestPath = Join-Path $battleRoot (
    "specs\id_manifests\battle_stable_ids.json"
)
$presentationManifestPath = Join-Path $battleRoot (
    "specs\presentation\presentation_contracts.json"
)
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
$script:checks = 0

$fixtureDependencies = @(
    "new-game-project/battle/tools/battle_catalog/validators/strict_json_support.ps1",
    "new-game-project/battle/tools/battle_catalog/validators/canonical_json_support.ps1",
    "new-game-project/battle/tools/battle_specs/validators/p2_id_manifest_support.ps1",
    "new-game-project/battle/tools/battle_specs/validators/p2_spec_contract_support.ps1",
    "new-game-project/battle/tools/battle_specs/validators/p2_repository_view_support.ps1",
    "new-game-project/battle/tools/battle_specs/validators/p2_spec_set_support.ps1"
)
$stableRelative = (
    "new-game-project/battle/specs/id_manifests/battle_stable_ids.json"
)
$presentationRelative = (
    "new-game-project/battle/specs/presentation/presentation_contracts.json"
)
$surfaceProbeRelative = (
    "new-game-project/battle/tests/catalog/p0_asset_boundary_test.ps1"
)

. $specSetSupportPath

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:checks += 1
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Passes {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $script:checks += 1
    try {
        $null = & $Action
    }
    catch {
        throw "$Label failed unexpectedly: $($_.Exception.Message)"
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$MessagePattern,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $script:checks += 1
    $caught = $null
    try {
        $null = & $Action
    }
    catch {
        $caught = $_
    }
    if ($null -eq $caught) {
        throw "$Label did not fail."
    }
    if ([string]$caught.Exception.Message -notmatch $MessagePattern) {
        throw (
            "$Label failed with an unexpected message: " +
            $caught.Exception.Message
        )
    }
}

function Get-ContainedPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath((Join-Path $rootFull (
        $RelativePath.Replace('/', '\')
    )))
    if (-not $fullPath.StartsWith(
        $rootFull + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to access a test path outside its repository root."
    }
    return $fullPath
}

function Write-ContainedBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $fullPath = Get-ContainedPath -Root $Root -RelativePath $RelativePath
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    [IO.File]::WriteAllBytes($fullPath, $Bytes)
}

function Write-ContainedText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Text
    )

    Write-ContainedBytes -Root $Root -RelativePath $RelativePath `
        -Bytes $utf8NoBom.GetBytes($Text)
}

function Write-ContainedSparseFile {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][long]$Length
    )

    $fullPath = Get-ContainedPath -Root $Root -RelativePath $RelativePath
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    $stream = [IO.File]::Create($fullPath)
    try {
        $stream.SetLength($Length)
    }
    finally {
        $stream.Dispose()
    }
}

function Remove-ContainedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $fullPath = Get-ContainedPath -Root $Root -RelativePath $RelativePath
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        [IO.File]::Delete($fullPath)
    }
}

function Invoke-TestGit {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& git -C $Repository @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exitCode -ne 0) {
        throw (
            "Test Git command failed: git $($Arguments -join ' ')`n" +
            ($output -join "`n")
        )
    }
    return @($output)
}

function Invoke-TestGitExpectFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& git -C $Repository @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exitCode -eq 0) {
        throw (
            "Test Git command unexpectedly succeeded: git " +
            "$($Arguments -join ' ')`n$($output -join "`n")"
        )
    }
    return $exitCode
}

function Get-ViewText {
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $bytes = Get-P2RepositoryViewBytes -View $View `
        -RelativePath $RelativePath
    return $strictUtf8.GetString([byte[]]$bytes)
}

function Get-WorktreeSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $gitPrefix = (Join-Path $rootFull ".git") + '\'
    $records = [Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $rootFull -File -Recurse) {
        $fullPath = [IO.Path]::GetFullPath([string]$file.FullName)
        if ($fullPath.StartsWith(
            $gitPrefix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            continue
        }
        $relative = $fullPath.Substring($rootFull.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
        $records.Add("$relative|$($file.Length)|$hash")
    }
    $result = $records.ToArray()
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result -join "`n"
}

function New-FixtureRepository {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$IncludeSurfaceProbe
    )

    $root = Join-Path $Parent $Name
    New-Item -ItemType Directory -Path $root | Out-Null
    $null = Invoke-TestGit $root @("init", "--quiet")
    $null = Invoke-TestGit $root @("config", "user.name", "Battle View Test")
    $null = Invoke-TestGit $root @(
        "config", "user.email", "battle-view-test@example.invalid"
    )
    $null = Invoke-TestGit $root @("config", "core.autocrlf", "false")
    foreach ($relativePath in $fixtureDependencies) {
        $sourcePath = Get-ContainedPath -Root $ProjectRoot `
            -RelativePath $relativePath
        Write-ContainedBytes -Root $root -RelativePath $relativePath `
            -Bytes ([IO.File]::ReadAllBytes($sourcePath))
    }
    Write-ContainedBytes -Root $root -RelativePath $stableRelative `
        -Bytes ([IO.File]::ReadAllBytes($stableManifestPath))
    Write-ContainedBytes -Root $root -RelativePath $presentationRelative `
        -Bytes ([IO.File]::ReadAllBytes($presentationManifestPath))
    if ($IncludeSurfaceProbe) {
        Write-ContainedText -Root $root -RelativePath $surfaceProbeRelative `
            -Text "Set-StrictMode -Version Latest`n"
    }
    $null = Invoke-TestGit $root @("add", "--all", "--")
    $null = Invoke-TestGit $root @(
        "commit", "--quiet", "-m", "Fixture baseline"
    )
    return $root
}

$parsePaths = @($fixtureDependencies | ForEach-Object {
    Get-ContainedPath -Root $ProjectRoot -RelativePath ([string]$_)
}) + @($MyInvocation.MyCommand.Path)
foreach ($parsePath in $parsePaths) {
    $tokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile(
        $parsePath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    Assert-Condition ($parseErrors.Count -eq 0) `
        "PowerShell parse failed for '$parsePath'."
}

$repositorySource = [IO.File]::ReadAllText($repositorySupportPath, $strictUtf8)
Assert-Condition (
    $repositorySource -notmatch '(?i)write-tree|update-index|read-tree|checkout-index'
) "Repository view support contains a Git index/tree mutation command."
Assert-Condition (
    $repositorySource -notmatch '\[IO\.File\]::ReadAllBytes|\.CopyTo\('
) "Repository view support contains an unbounded candidate/blob read."
Assert-Condition ($repositorySource -match 'cat-file -s') `
    "Staged blob capture does not preflight object size."
Assert-Condition (
    $repositorySource -match 'CreateFileW' -and
    $repositorySource -match 'GetFinalPathNameByHandleW' -and
    $repositorySource -match 'OpenReparsePoint'
) "Repository view does not enforce no-follow final-path handles."
Assert-Throws -Label "invalid repository view object" `
    -MessagePattern "P2_REPOSITORY_VIEW_REQUIRED" -Action {
        Get-P2RepositoryViewPaths -View ([pscustomobject]@{
            ViewKind = "NOT_A_REPOSITORY_VIEW"
            Mode = "Repository"
        })
    }
Assert-Throws -Label "invalid UTF-8 decoder" `
    -MessagePattern "P2_REPOSITORY_VIEW_UTF8" -Action {
        ConvertFrom-P2RepositoryViewUtf8 `
            -Bytes ([byte[]]@(0xC3, 0x28)) -Context "invalid vector"
    }

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$tempRoot = Join-Path $tempParent (
    "maizang-p2-repository-view-test-" + [Guid]::NewGuid().ToString("N")
)
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $mainRoot = New-FixtureRepository -Parent $tempRoot -Name "main"
    $candidatePrefixes = @("data", "new-game-project/battle/specs")
    $currentRelative = "data/current.txt"
    Write-ContainedText $mainRoot $currentRelative "head-one`n"
    $null = Invoke-TestGit $mainRoot @("add", "--", $currentRelative)
    $null = Invoke-TestGit $mainRoot @(
        "commit", "--quiet", "-m", "Add current vector"
    )

    $repositoryView = New-P2RepositoryView -ProjectRoot $mainRoot `
        -Mode Repository -CandidatePrefixes $candidatePrefixes
    Write-ContainedText $mainRoot $currentRelative "repository-dirty`n"
    Assert-Condition (
        (Get-ViewText $repositoryView $currentRelative) -ceq
        "head-one`n"
    ) "Repository mode followed a worktree change after capture."
    Assert-Throws -Label "repository has no baseline" `
        -MessagePattern "P2_REPOSITORY_VIEW_NO_BASELINE" -Action {
            Get-P2RepositoryViewBaselineBytes -View $repositoryView `
                -RelativePath $currentRelative
        }
    Assert-Condition (
        $null -eq (Get-P2RepositoryViewBaselineBytes -View $repositoryView `
            -RelativePath $currentRelative -AllowMissing)
    ) "Repository AllowMissing baseline did not return null."

    $worktreeView = New-P2RepositoryView -ProjectRoot $mainRoot `
        -Mode Worktree -CandidatePrefixes $candidatePrefixes
    Assert-Condition (
        (Get-ViewText $worktreeView $currentRelative) -ceq
        "repository-dirty`n"
    ) "Worktree mode did not read current worktree bytes."
    $returnedClone = Get-P2RepositoryViewBytes -View $worktreeView `
        -RelativePath $currentRelative
    $returnedClone[0] = $returnedClone[0] -bxor 0xFF
    Assert-Condition (
        (Get-ViewText $worktreeView $currentRelative) -ceq
        "repository-dirty`n"
    ) "Repository view exposed mutable captured bytes."
    $worktreeBaseline = Get-P2RepositoryViewBaselineBytes `
        -View $worktreeView -RelativePath $currentRelative
    Assert-Condition (
        $strictUtf8.GetString([byte[]]$worktreeBaseline) -ceq "head-one`n"
    ) "Worktree mode did not capture its HEAD baseline."
    Write-ContainedText $mainRoot $currentRelative "head-two`n"
    $null = Invoke-TestGit $mainRoot @("add", "--", $currentRelative)
    $null = Invoke-TestGit $mainRoot @(
        "commit", "--quiet", "-m", "Advance HEAD after capture"
    )
    Assert-Condition (
        $strictUtf8.GetString([byte[]](
            Get-P2RepositoryViewBaselineBytes -View $worktreeView `
                -RelativePath $currentRelative
        )) -ceq "head-one`n"
    ) "Worktree baseline followed HEAD after view construction."
    Assert-Condition (
        (Get-ViewText $worktreeView $currentRelative) -ceq "repository-dirty`n"
    ) "Captured Worktree view followed a later worktree change."

    foreach ($vector in @(
        @{ Path = "data/Z.txt"; Text = "Z`n" },
        @{ Path = "data/a.txt"; Text = "a`n" },
        @{ Path = "data/B.txt"; Text = "B`n" },
        @{ Path = "data/captured.txt"; Text = "stage-one`n" }
    )) {
        Write-ContainedText $mainRoot ([string]$vector.Path) `
            ([string]$vector.Text)
    }
    $null = Invoke-TestGit $mainRoot @("add", "--all", "--")
    $indexPath = Join-Path $mainRoot ".git\index"
    $indexBefore = [IO.File]::ReadAllBytes($indexPath)
    $snapshotBefore = Get-WorktreeSnapshot $mainRoot
    $stagedView = New-P2RepositoryView -ProjectRoot $mainRoot -Mode Staged `
        -CandidatePrefixes $candidatePrefixes
    $ordinalRepositoryView = New-P2RepositoryView -ProjectRoot $mainRoot `
        -Mode Repository -CandidatePrefixes $candidatePrefixes
    $ordinalWorktreeView = New-P2RepositoryView -ProjectRoot $mainRoot `
        -Mode Worktree -CandidatePrefixes $candidatePrefixes

    $repositorySet = Read-P2ValidatedSpecSet -View $repositoryView
    $worktreeSet = Read-P2ValidatedSpecSet -View $worktreeView
    $stagedSet = Read-P2ValidatedSpecSet -View $stagedView
    Assert-Condition (
        [long]$repositorySet.Counts.mechanism_specs -eq 0 -and
        [long]$repositorySet.Counts.event_schemas -eq 0 -and
        [long]$repositorySet.Counts.handler_bindings -eq 0 -and
        [long]$repositorySet.Counts.resolver_specs -eq 0 -and
        [long]$repositorySet.Counts.test_entries -eq 0
    ) "Minimal Repository spec set was not empty."
    Assert-Condition (
        [string]$repositorySet.InputSetHash -ceq
        "32857c87d8e374886c91e9a65a2eed546478930d640d5ba4ecf006c18a1fa821"
    ) "Minimal spec-set canonical hash changed."
    Assert-Condition (
        [string]$repositorySet.InputSetHash -ceq
        [string]$worktreeSet.InputSetHash -and
        [string]$repositorySet.InputSetHash -ceq
        [string]$stagedSet.InputSetHash
    ) "The three repository views disagreed on the same empty spec set."
    Assert-Condition (
        [string]$repositorySet.StableManifestHash -cmatch '^[0-9a-f]{64}$' -and
        [string]$repositorySet.PresentationManifestHash -cmatch '^[0-9a-f]{64}$'
    ) "Validated spec set did not return canonical manifest hashes."

    $expectedPaths = @(
        "data/B.txt",
        "data/Z.txt",
        "data/a.txt",
        "data/captured.txt",
        "data/current.txt"
    )
    $repositoryPaths = @(Get-P2RepositoryViewPaths `
        -View $ordinalRepositoryView -Prefix "data")
    $worktreePaths = @(Get-P2RepositoryViewPaths `
        -View $ordinalWorktreeView -Prefix "data")
    $stagedPaths = @(Get-P2RepositoryViewPaths `
        -View $stagedView -Prefix "data")
    Assert-Condition (
        ($repositoryPaths -join "|") -ceq ($expectedPaths -join "|")
    ) "Repository path enumeration was not ordinal and complete."
    Assert-Condition (
        ($worktreePaths -join "|") -ceq ($expectedPaths -join "|")
    ) "Worktree path enumeration was not ordinal and complete."
    $stagedPathsAreOrdinal = (
        ($stagedPaths -join "|") -ceq ($expectedPaths -join "|")
    )
    Assert-Condition (
        @(Get-P2RepositoryViewPaths -View $ordinalRepositoryView `
            -Prefix "missing-prefix").Count -eq 0
    ) "A missing worktree prefix did not enumerate as empty."

    $indexAfter = [IO.File]::ReadAllBytes($indexPath)
    Assert-Condition (
        Test-P2RepositoryViewByteEquality $indexBefore $indexAfter
    ) "Repository view construction or spec-set reading mutated the Git index."
    Assert-Condition (
        (Get-WorktreeSnapshot $mainRoot) -ceq $snapshotBefore
    ) "Repository view construction or spec-set reading wrote worktree files."

    Write-ContainedText $mainRoot "data/captured.txt" "stage-two`n"
    $null = Invoke-TestGit $mainRoot @("add", "--", "data/captured.txt")
    Write-ContainedText $mainRoot "data/captured.txt" "worktree-three`n"
    Write-ContainedText $mainRoot "data/later.txt" "later-index`n"
    $null = Invoke-TestGit $mainRoot @("add", "--", "data/later.txt")
    Assert-Condition (
        (Get-ViewText $stagedView "data/captured.txt") -ceq "stage-one`n"
    ) "Captured Staged view followed a later index or worktree mutation."
    Assert-Condition (
        @(Get-P2RepositoryViewPaths -View $stagedView `
            -Prefix "data") -cnotcontains "data/later.txt"
    ) "Captured Staged path set followed a later index addition."
    Assert-Condition (
        (Get-ViewText $ordinalWorktreeView "data/captured.txt") -ceq
        "stage-one`n"
    ) "Captured Worktree bytes followed a later file mutation."
    Assert-Condition (
        @(Get-P2RepositoryViewPaths -View $ordinalRepositoryView `
            -Prefix "data") -cnotcontains "data/later.txt"
    ) "Captured Repository paths followed a later file addition."
    Assert-Condition (
        $null -eq (Get-P2RepositoryViewBaselineBytes -View $stagedView `
            -RelativePath "data/captured.txt" -AllowMissing)
    ) "Staged baseline unexpectedly contained a post-HEAD file."
    Assert-Throws -Label "captured staged missing path" `
        -MessagePattern "P2_REPOSITORY_VIEW_NOT_FOUND" -Action {
            Get-P2RepositoryViewBytes -View $stagedView `
                -RelativePath "data/later.txt"
        }
    Assert-Condition (
        $null -eq (Get-P2RepositoryViewBytes -View $stagedView `
            -RelativePath "data/later.txt" -AllowMissing)
    ) "Staged AllowMissing did not use the captured index."

    Assert-Throws -Label "worktree missing path" `
        -MessagePattern "P2_REPOSITORY_VIEW_NOT_FOUND" -Action {
            Get-P2RepositoryViewBytes -View $worktreeView `
                -RelativePath "data/absent.txt"
        }
    Assert-Condition (
        $null -eq (Get-P2RepositoryViewBytes -View $worktreeView `
            -RelativePath "data/absent.txt" -AllowMissing)
    ) "Worktree AllowMissing did not return null."
    Assert-Throws -Label "baseline missing path" `
        -MessagePattern "P2_REPOSITORY_VIEW_BASELINE_NOT_FOUND" -Action {
            Get-P2RepositoryViewBaselineBytes -View $worktreeView `
                -RelativePath "data/absent.txt"
        }

    foreach ($invalidPath in @(
        "../outside.txt",
        "data//double.txt",
        "C:\outside.txt",
        "/absolute.txt"
    )) {
        Assert-Throws -Label "invalid path $invalidPath" `
            -MessagePattern "P2_REPOSITORY_VIEW_PATH" -Action {
                Get-P2RepositoryViewBytes -View $repositoryView `
                    -RelativePath $invalidPath
            }
    }
    Assert-Throws -Label "Git root mismatch" `
        -MessagePattern "P2_REPOSITORY_VIEW_ROOT_MISMATCH" -Action {
            New-P2RepositoryView -ProjectRoot (Join-Path $mainRoot "data") `
                -Mode Repository
        }

    Write-ContainedBytes $mainRoot $stableRelative `
        ([byte[]]@(0x7B, 0x22, 0xC3, 0x28, 0x22, 0x7D))
    $null = Invoke-TestGit $mainRoot @("add", "--", $stableRelative)
    Assert-Passes -Label "captured Staged spec set ignores later invalid index" `
        -Action {
            $result = Read-P2ValidatedSpecSet -View $stagedView
            if ([string]$result.InputSetHash -cne
                "32857c87d8e374886c91e9a65a2eed546478930d640d5ba4ecf006c18a1fa821") {
                throw "Captured staged input hash changed."
            }
        }
    $invalidWorktreeView = New-P2RepositoryView -ProjectRoot $mainRoot `
        -Mode Worktree
    Assert-Throws -Label "spec set rejects invalid worktree UTF-8" `
        -MessagePattern "P2_SPEC_SET_UTF8" -Action {
            Read-P2ValidatedSpecSet -View $invalidWorktreeView
        }
    $invalidStagedView = New-P2RepositoryView -ProjectRoot $mainRoot `
        -Mode Staged
    Assert-Throws -Label "spec set rejects invalid staged UTF-8" `
        -MessagePattern "P2_SPEC_SET_UTF8" -Action {
            Read-P2ValidatedSpecSet -View $invalidStagedView
        }

    $junctionTarget = Join-Path $tempRoot "junction-target-outside-root"
    $junctionPath = Join-Path $mainRoot "data\junction"
    $null = [IO.Directory]::CreateDirectory($junctionTarget)
    [IO.File]::WriteAllText(
        (Join-Path $junctionTarget "payload.txt"),
        "outside",
        $utf8NoBom
    )
    try {
        $junction = New-Item -ItemType Junction -Path $junctionPath `
            -Target $junctionTarget
        Assert-Condition (
            ($junction.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        ) "The repository-view junction fixture is not a reparse point."
        Assert-Condition (
            @(Get-P2RepositoryViewPaths -View $ordinalRepositoryView `
                -Prefix "data") -cnotcontains "data/junction/payload.txt"
        ) "Captured Repository view followed a later reparse path."
        Assert-Throws -Label "ancestor junction final-path redirect" `
            -MessagePattern "P2_REPOSITORY_VIEW_REDIRECT" -Action {
                $redirectGuard = Open-P2RepositoryViewVerifiedHandle `
                    -Path (Join-Path $junctionPath "payload.txt") `
                    -ExpectedFinalPath (Get-P2RepositoryViewExpectedFinalPath `
                        -View $ordinalRepositoryView `
                        -RelativePath "data/junction/payload.txt") `
                    -ExpectedKind File -Access Read
                $redirectGuard.Handle.Dispose()
            }
        Assert-Throws -Label "worktree reparse snapshot" `
            -MessagePattern "P2_REPOSITORY_VIEW_REPARSE" -Action {
                New-P2RepositoryView -ProjectRoot $mainRoot `
                    -Mode Repository -CandidatePrefixes $candidatePrefixes
            }
    }
    finally {
        if (Test-Path -LiteralPath $junctionPath) {
            [IO.Directory]::Delete($junctionPath)
        }
    }

    $untrackedRoot = New-FixtureRepository -Parent $tempRoot `
        -Name "surface-untracked"
    Write-ContainedText $untrackedRoot $surfaceProbeRelative "untracked`n"
    Assert-Throws -Label "untracked staged execution surface" `
        -MessagePattern "P2_REPOSITORY_VIEW_SURFACE_UNTRACKED" -Action {
            New-P2RepositoryView -ProjectRoot $untrackedRoot -Mode Staged
        }

    $mismatchRoot = New-FixtureRepository -Parent $tempRoot `
        -Name "surface-mismatch" -IncludeSurfaceProbe
    Write-ContainedText $mismatchRoot $surfaceProbeRelative "dirty`n"
    Assert-Throws -Label "mismatched staged execution surface" `
        -MessagePattern "P2_REPOSITORY_VIEW_SURFACE_MISMATCH" -Action {
            New-P2RepositoryView -ProjectRoot $mismatchRoot -Mode Staged
        }

    $missingRoot = New-FixtureRepository -Parent $tempRoot `
        -Name "surface-missing" -IncludeSurfaceProbe
    Remove-ContainedFile $missingRoot $surfaceProbeRelative
    Assert-Throws -Label "missing staged execution surface" `
        -MessagePattern "P2_REPOSITORY_VIEW_SURFACE_MISSING" -Action {
            New-P2RepositoryView -ProjectRoot $missingRoot -Mode Staged
        }

    $deletedRoot = New-FixtureRepository -Parent $tempRoot `
        -Name "surface-deleted" -IncludeSurfaceProbe
    $null = Invoke-TestGit $deletedRoot @(
        "rm", "--quiet", "--", $surfaceProbeRelative
    )
    Assert-Throws -Label "deleted staged execution surface" `
        -MessagePattern "P2_REPOSITORY_VIEW_SURFACE_DELETED" -Action {
            New-P2RepositoryView -ProjectRoot $deletedRoot -Mode Staged
        }

    $ignoreSurfaceRoot = New-FixtureRepository -Parent $tempRoot `
        -Name "ignore-surface"
    $battleIgnoreRelative = "new-game-project/battle/.gitignore"
    Write-ContainedText $ignoreSurfaceRoot $battleIgnoreRelative `
        "generated/`n"
    $null = Invoke-TestGit $ignoreSurfaceRoot @(
        "add", "--", $battleIgnoreRelative
    )
    $null = Invoke-TestGit $ignoreSurfaceRoot @(
        "commit", "--quiet", "-m", "Add battle ignore contract"
    )
    $null = Invoke-TestGit $ignoreSurfaceRoot @(
        "rm", "--cached", "--quiet", "--", $battleIgnoreRelative
    )
    Assert-Condition (
        Test-Path -LiteralPath (Get-ContainedPath -Root $ignoreSurfaceRoot `
            -RelativePath $battleIgnoreRelative) -PathType Leaf
    ) "Ignore-surface fixture did not preserve its worktree ignore file."
    Assert-Throws -Label "staged deletion of battle ignore contract" `
        -MessagePattern "P2_REPOSITORY_VIEW_SURFACE_DELETED" -Action {
            New-P2RepositoryView -ProjectRoot $ignoreSurfaceRoot -Mode Staged
        }

    $modeRoot = New-FixtureRepository -Parent $tempRoot -Name "invalid-mode"
    Write-ContainedText $modeRoot "data/link-target.txt" "target`n"
    $linkBlob = (@(Invoke-TestGit $modeRoot @(
        "hash-object", "-w", "--", "data/link-target.txt"
    )) -join "").Trim()
    $null = Invoke-TestGit $modeRoot @(
        "update-index", "--add", "--cacheinfo",
        "120000,$linkBlob,data/nonregular"
    )
    Assert-Throws -Label "nonregular staged index mode" `
        -MessagePattern "P2_REPOSITORY_VIEW_MODE" -Action {
            New-P2RepositoryView -ProjectRoot $modeRoot -Mode Staged `
                -CandidatePrefixes $candidatePrefixes
        }
    $null = Invoke-TestGit $modeRoot @(
        "commit", "--quiet", "-m", "Commit nonregular fixture"
    )
    Assert-Throws -Label "nonregular HEAD baseline mode" `
        -MessagePattern "P2_REPOSITORY_VIEW_BASELINE_MODE" -Action {
            New-P2RepositoryView -ProjectRoot $modeRoot -Mode Worktree `
                -CandidatePrefixes $candidatePrefixes
        }

    $oversizedWorktreeRoot = New-FixtureRepository -Parent $tempRoot `
        -Name "oversized-worktree"
    $oversizedRelative = "data/oversized.json"
    Write-ContainedSparseFile -Root $oversizedWorktreeRoot `
        -RelativePath $oversizedRelative -Length 524289
    Assert-Throws -Label "oversized Worktree candidate pre-allocation" `
        -MessagePattern "P2_REPOSITORY_VIEW_FILE_TOO_LARGE" -Action {
            New-P2RepositoryView -ProjectRoot $oversizedWorktreeRoot `
                -Mode Worktree -CandidatePrefixes @($oversizedRelative)
        }

    $oversizedStagedRoot = New-FixtureRepository -Parent $tempRoot `
        -Name "oversized-staged"
    Write-ContainedSparseFile -Root $oversizedStagedRoot `
        -RelativePath $oversizedRelative -Length 524289
    $null = Invoke-TestGit $oversizedStagedRoot @(
        "add", "--", $oversizedRelative
    )
    Assert-Throws -Label "oversized Staged blob size preflight" `
        -MessagePattern "P2_REPOSITORY_VIEW_FILE_TOO_LARGE" -Action {
            New-P2RepositoryView -ProjectRoot $oversizedStagedRoot `
                -Mode Staged -CandidatePrefixes @($oversizedRelative)
        }

    $countRoot = New-FixtureRepository -Parent $tempRoot -Name "candidate-count"
    foreach ($name in @("one", "two", "three")) {
        Write-ContainedText -Root $countRoot -RelativePath "data/$name.txt" `
            -Text "$name`n"
    }
    $originalCandidateLimit = $script:P2RepositoryViewMaxCandidatePaths
    try {
        $script:P2RepositoryViewMaxCandidatePaths = 2
        foreach ($mode in @("Repository", "Worktree")) {
            Assert-Throws -Label "$mode candidate count pre-read" `
                -MessagePattern "P2_REPOSITORY_VIEW_CANDIDATE_COUNT" -Action {
                    New-P2RepositoryView -ProjectRoot $countRoot -Mode $mode `
                        -CandidatePrefixes @("data")
                }
        }
        $null = Invoke-TestGit $countRoot @("add", "--", "data")
        Assert-Throws -Label "Staged candidate count pre-blob" `
            -MessagePattern "P2_REPOSITORY_VIEW_CANDIDATE_COUNT" -Action {
                New-P2RepositoryView -ProjectRoot $countRoot -Mode Staged `
                    -CandidatePrefixes @("data")
            }
    }
    finally {
        $script:P2RepositoryViewMaxCandidatePaths = $originalCandidateLimit
    }

    $budgetRoot = New-FixtureRepository -Parent $tempRoot -Name "capture-budget"
    Write-ContainedText $budgetRoot "data/one.txt" "12"
    Write-ContainedText $budgetRoot "data/two.txt" "34"
    $originalCaptureBudget = $script:P2RepositoryViewMaxCapturedBytes
    try {
        $script:P2RepositoryViewMaxCapturedBytes = 3
        Assert-Throws -Label "aggregate capture budget pre-allocation" `
            -MessagePattern "P2_REPOSITORY_VIEW_CAPTURE_BYTES" -Action {
                New-P2RepositoryView -ProjectRoot $budgetRoot -Mode Worktree `
                    -CandidatePrefixes @("data")
            }
    }
    finally {
        $script:P2RepositoryViewMaxCapturedBytes = $originalCaptureBudget
    }

    Assert-Throws -Label "bounded Git command output" `
        -MessagePattern "P2_REPOSITORY_VIEW_GIT_OUTPUT_LIMIT" -Action {
            Invoke-P2RepositoryViewGit -Root $mainRoot `
                -Arguments "rev-parse --show-toplevel" -MaxOutputBytes 1
        }

    $unmergedRoot = New-FixtureRepository -Parent $tempRoot -Name "unmerged"
    $conflictRelative = "data/conflict.txt"
    Write-ContainedText $unmergedRoot $conflictRelative "base`n"
    $null = Invoke-TestGit $unmergedRoot @("add", "--", $conflictRelative)
    $null = Invoke-TestGit $unmergedRoot @(
        "commit", "--quiet", "-m", "Conflict base"
    )
    $baseBranch = (@(Invoke-TestGit $unmergedRoot @(
        "branch", "--show-current"
    )) -join "").Trim()
    $null = Invoke-TestGit $unmergedRoot @(
        "switch", "--quiet", "-c", "conflict-side"
    )
    Write-ContainedText $unmergedRoot $conflictRelative "side`n"
    $null = Invoke-TestGit $unmergedRoot @("add", "--", $conflictRelative)
    $null = Invoke-TestGit $unmergedRoot @(
        "commit", "--quiet", "-m", "Conflict side"
    )
    $null = Invoke-TestGit $unmergedRoot @(
        "switch", "--quiet", $baseBranch
    )
    Write-ContainedText $unmergedRoot $conflictRelative "main`n"
    $null = Invoke-TestGit $unmergedRoot @("add", "--", $conflictRelative)
    $null = Invoke-TestGit $unmergedRoot @(
        "commit", "--quiet", "-m", "Conflict main"
    )
    $null = Invoke-TestGitExpectFailure $unmergedRoot @(
        "merge", "--no-edit", "conflict-side"
    )
    Assert-Throws -Label "unmerged staged index" `
        -MessagePattern "P2_REPOSITORY_VIEW_UNMERGED" -Action {
            New-P2RepositoryView -ProjectRoot $unmergedRoot -Mode Staged `
                -CandidatePrefixes $candidatePrefixes
        }
    Assert-Condition $stagedPathsAreOrdinal (
        "Staged path enumeration was not ordinal and complete: " +
        ($stagedPaths -join "|")
    )
}
finally {
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot).TrimEnd('\')
    if (-not $resolvedTempRoot.StartsWith(
        $tempParent + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove a test directory outside the system temp root."
    }
    if (Test-Path -LiteralPath $resolvedTempRoot) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}

Write-Host "P2_REPOSITORY_VIEW_TEST_OK checks=$checks"
