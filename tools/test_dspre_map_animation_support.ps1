param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "dspre_map_animation_support.ps1")

function New-SyntheticNarcBytes {
    param([Parameter(Mandatory)][object[]]$Members)

    $memberBytes = New-Object object[] $Members.Count
    for ($memberIndex = 0; $memberIndex -lt $Members.Count; $memberIndex++) {
        $memberBytes[$memberIndex] = [byte[]]$Members[$memberIndex]
    }
    $fatLength = 12 + 8 * $memberBytes.Count
    $nameLength = 8
    $imagePayloadLength = [int](@($memberBytes | Measure-Object Length -Sum).Sum)
    $imageLength = 8 + $imagePayloadLength
    $archiveLength = 16 + $fatLength + $nameLength + $imageLength
    $stream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes("NARC"))
        $writer.Write([uint16]0xFFFE)
        $writer.Write([uint16]0x0100)
        $writer.Write([uint32]$archiveLength)
        $writer.Write([uint16]16)
        $writer.Write([uint16]3)

        $writer.Write([Text.Encoding]::ASCII.GetBytes("BTAF"))
        $writer.Write([uint32]$fatLength)
        $writer.Write([uint16]$memberBytes.Count)
        $writer.Write([uint16]0)
        $offset = 0
        foreach ($member in $memberBytes) {
            $writer.Write([uint32]$offset)
            $offset += $member.Length
            $writer.Write([uint32]$offset)
        }

        $writer.Write([Text.Encoding]::ASCII.GetBytes("BTNF"))
        $writer.Write([uint32]$nameLength)
        $writer.Write([Text.Encoding]::ASCII.GetBytes("GMIF"))
        $writer.Write([uint32]$imageLength)
        foreach ($member in $memberBytes) {
            $writer.Write($member)
        }
        $writer.Flush()
        return $stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function New-AnimationListMember {
    param(
        [int]$Flags,
        [int[]]$ArchiveIds,
        [bool]$BicycleSlope = $false
    )

    $bytes = New-Object byte[] 20
    $bytes[0] = 1
    $bytes[1] = [byte]$Flags
    $bytes[2] = if ($BicycleSlope) { 1 } else { 0 }
    $bytes[3] = 0
    for ($slot = 0; $slot -lt 4; $slot++) {
        $archiveId = if ($slot -lt $ArchiveIds.Count) { $ArchiveIds[$slot] } else { -1 }
        [Buffer]::BlockCopy([BitConverter]::GetBytes([int]$archiveId), 0, $bytes, 4 + 4 * $slot, 4)
    }
    return $bytes
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
        throw "Expected failure was accepted: $Label"
    }
}

$emptyListMember = New-Object byte[] 20
for ($index = 0; $index -lt $emptyListMember.Length; $index++) {
    $emptyListMember[$index] = 0xFF
}
$emptyListMember[2] = 0
$emptyListMember[3] = 0
$listMembers = New-Object object[] 590
for ($modelId = 0; $modelId -lt $listMembers.Count; $modelId++) {
    $listMembers[$modelId] = [byte[]]$emptyListMember.Clone()
}

$listMembers[1] = New-AnimationListMember -Flags 0 -ArchiveIds @(1)
$listMembers[2] = New-AnimationListMember -Flags 2 -ArchiveIds @(0)
$listMembers[3] = New-AnimationListMember -Flags 3 -ArchiveIds @(51)

$ordinaryDoorIds = @($script:DspreDoorModels | Where-Object { $_.name -ne "elevator_door" } | ForEach-Object { [int]$_.model_id })
foreach ($modelId in $ordinaryDoorIds) {
    $listMembers[$modelId] = New-AnimationListMember -Flags 3 -ArchiveIds @(5, 6)
}
$listMembers[75] = New-AnimationListMember -Flags 3 -ArchiveIds @(51, 52)

$animeMembers = New-Object object[] 98
for ($archiveId = 0; $archiveId -lt $animeMembers.Count; $archiveId++) {
    $bytes = New-Object byte[] 8
    [Buffer]::BlockCopy([Text.Encoding]::ASCII.GetBytes("BCA0"), 0, $bytes, 0, 4)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([int]$archiveId), 0, $bytes, 4, 4)
    $animeMembers[$archiveId] = $bytes
}
[Buffer]::BlockCopy([Text.Encoding]::ASCII.GetBytes("BTA0"), 0, $animeMembers[0], 0, 4)
[Buffer]::BlockCopy([Text.Encoding]::ASCII.GetBytes("BTP0"), 0, $animeMembers[51], 0, 4)
[Buffer]::BlockCopy([Text.Encoding]::ASCII.GetBytes("BTP0"), 0, $animeMembers[52], 0, 4)

$animeListArchive = ConvertFrom-DspreNarcBytes `
    -Bytes (New-SyntheticNarcBytes -Members $listMembers) `
    -Label "Synthetic bm_anime_list"
$animeArchive = ConvertFrom-DspreNarcBytes `
    -Bytes (New-SyntheticNarcBytes -Members $animeMembers) `
    -Label "Synthetic bm_anime"
$descriptor = ConvertFrom-DspreMapAnimationArchives `
    -AnimeListArchive $animeListArchive `
    -AnimeArchive $animeArchive `
    -Label "Synthetic MapProp animations"

if (
    [int]$descriptor.model_table_count -ne 590 -or
    [int]$descriptor.animation_archive_count -ne 98 -or
    @($descriptor.doors).Count -ne 20
) {
    throw "Synthetic descriptor counts are incorrect."
}
$modelsById = @{}
foreach ($model in @($descriptor.models)) {
    $modelsById[[int]$model.model_id] = $model
}
if (
    [string]$modelsById[1].playback -ne "automatic_loop" -or
    [string]$modelsById[1].slots[0].import_disposition -ne "native_gltf" -or
    [string]$modelsById[2].playback -ne "deferred" -or
    [string]$modelsById[2].slots[0].magic -ne "BTA0" -or
    [string]$modelsById[2].slots[0].import_disposition -ne "unsupported_deferred" -or
    [string]$modelsById[3].playback -ne "deferred" -or
    [string]$modelsById[3].slots[0].magic -ne "BTP0"
) {
    throw "Flags or Nitro animation formats were classified incorrectly."
}
$elevator = @($descriptor.doors | Where-Object { $_.model_id -eq 75 })
if (
    $elevator.Count -ne 1 -or
    [int]$elevator[0].open_slot -ne 0 -or
    [int]$elevator[0].close_slot -ne 1 -or
    [string]$elevator[0].import_disposition -ne "unsupported_deferred" -or
    [string]$elevator[0].unsupported_reason -ne "elevator_btp0"
) {
    throw "Elevator-door BTP0 animations were not held as unsupported."
}
$ordinaryDoor = @($descriptor.doors | Where-Object { $_.model_id -eq 66 })[0]
if (
    [int]$ordinaryDoor.open_slot -ne 0 -or
    [int]$ordinaryDoor.close_slot -ne 1 -or
    [string]$ordinaryDoor.import_disposition -ne "native_gltf"
) {
    throw "Ordinary door open/close slots were described incorrectly."
}

$invalidFlagsMembers = New-Object object[] $listMembers.Count
for ($memberIndex = 0; $memberIndex -lt $listMembers.Count; $memberIndex++) {
    $invalidFlagsMembers[$memberIndex] = [byte[]]$listMembers[$memberIndex].Clone()
}
$invalidFlagsMembers[1][1] = 1
$invalidFlagsArchive = ConvertFrom-DspreNarcBytes `
    -Bytes (New-SyntheticNarcBytes -Members $invalidFlagsMembers) `
    -Label "Synthetic invalid flags list"
Assert-Throws {
    ConvertFrom-DspreMapAnimationArchives `
        -AnimeListArchive $invalidFlagsArchive `
        -AnimeArchive $animeArchive
} "unsupported flags 1"

$invalidMagicMembers = New-Object object[] $animeMembers.Count
for ($memberIndex = 0; $memberIndex -lt $animeMembers.Count; $memberIndex++) {
    $invalidMagicMembers[$memberIndex] = [byte[]]$animeMembers[$memberIndex].Clone()
}
[Buffer]::BlockCopy([Text.Encoding]::ASCII.GetBytes("BAD0"), 0, $invalidMagicMembers[4], 0, 4)
$invalidMagicArchive = ConvertFrom-DspreNarcBytes `
    -Bytes (New-SyntheticNarcBytes -Members $invalidMagicMembers) `
    -Label "Synthetic invalid magic archive"
Assert-Throws {
    ConvertFrom-DspreMapAnimationArchives `
        -AnimeListArchive $animeListArchive `
        -AnimeArchive $invalidMagicArchive
} "unsupported animation magic"

$testRoot = Join-Path (Split-Path $PSScriptRoot -Parent) (".work\test_dspre_map_animation_{0}" -f [Guid]::NewGuid().ToString("N"))
try {
    $outputPath = Join-Path $testRoot "member_0001.nsbca"
    $export = Export-DspreMapAnimationMember `
        -AnimeArchive $animeArchive `
        -MemberId 1 `
        -OutputPath $outputPath `
        -WorkRoot $testRoot
    if (
        -not (Test-Path -LiteralPath $outputPath -PathType Leaf) -or
        [string]$export.magic -ne "BCA0" -or
        [string]$export.import_disposition -ne "native_gltf" -or
        [long]$export.byte_length -ne ([byte[]]$animeMembers[1]).Length -or
        @([IO.Directory]::GetFiles($testRoot, "*.tmp", [IO.SearchOption]::AllDirectories)).Count -ne 0
    ) {
        throw "Atomic animation member export did not produce the expected file."
    }
    Assert-Throws {
        Export-DspreMapAnimationMember `
            -AnimeArchive $animeArchive `
            -MemberId 0 `
            -OutputPath (Join-Path $testRoot "wrong.nsbca") `
            -WorkRoot $testRoot
    } "animation extension mismatch"
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

[pscustomobject][ordered]@{
    models = @($descriptor.models).Count
    animations = @($descriptor.animations).Count
    doors = @($descriptor.doors).Count
    flags = @("automatic_loop", "deferred")
    magics = @("BCA0", "BTA0", "BTP0")
    elevator = "unsupported_deferred"
    atomic_export = $true
} | ConvertTo-Json -Depth 4
