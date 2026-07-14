Set-StrictMode -Version Latest

$fieldFeatureSupportPath = Join-Path $PSScriptRoot "dspre_field_feature_support.ps1"
if (-not (Get-Command ConvertFrom-DspreNarcBytes -ErrorAction SilentlyContinue)) {
    . $fieldFeatureSupportPath
}

$script:DspreMapAnimationListMemberCount = 590
$script:DspreMapAnimationArchiveMemberCount = 98
$script:DspreMapAnimationListRecordSize = 20
$script:DspreMapAnimationNone = -1

$script:DspreDoorModels = @(
    [pscustomobject][ordered]@{ model_id = 66; name = "door01" },
    [pscustomobject][ordered]@{ model_id = 67; name = "brown_wooden_door" },
    [pscustomobject][ordered]@{ model_id = 68; name = "green_wooden_door" },
    [pscustomobject][ordered]@{ model_id = 69; name = "iron_door" },
    [pscustomobject][ordered]@{ model_id = 246; name = "jubilife_city_building_door" },
    [pscustomobject][ordered]@{ model_id = 70; name = "pokecenter_door" },
    [pscustomobject][ordered]@{ model_id = 427; name = "pokecenter_inside_door" },
    [pscustomobject][ordered]@{ model_id = 456; name = "gts_inside_door" },
    [pscustomobject][ordered]@{ model_id = 260; name = "hearthome_gym_inside_door" },
    [pscustomobject][ordered]@{ model_id = 312; name = "blue_door" },
    [pscustomobject][ordered]@{ model_id = 313; name = "iron_door_2" },
    [pscustomobject][ordered]@{ model_id = 438; name = "yellow_wooden_door" },
    [pscustomobject][ordered]@{ model_id = 444; name = "blue_wooden_door" },
    [pscustomobject][ordered]@{ model_id = 441; name = "mansion_door" },
    [pscustomobject][ordered]@{ model_id = 442; name = "veilstone_dpt_store_door" },
    [pscustomobject][ordered]@{ model_id = 298; name = "gym_door" },
    [pscustomobject][ordered]@{ model_id = 484; name = "card_door" },
    [pscustomobject][ordered]@{ model_id = 128; name = "pokecenter_inside_counter_door" },
    [pscustomobject][ordered]@{ model_id = 527; name = "hotel_grand_lake_door" },
    [pscustomobject][ordered]@{ model_id = 75; name = "elevator_door" }
)

function Get-DspreMapAnimationFormat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,
        [ValidateRange(0, 97)]
        [int]$ArchiveId,
        [string]$Label = "MapProp animation"
    )

    if ($Bytes.Length -lt 4) {
        throw "$Label archive $ArchiveId is too short to contain a Nitro animation magic."
    }
    $magic = [Text.Encoding]::ASCII.GetString($Bytes, 0, 4)
    switch ($magic) {
        "BCA0" {
            return [pscustomobject][ordered]@{
                archive_id = $ArchiveId
                magic = $magic
                source_format = "nsbca"
                file_extension = ".nsbca"
                import_disposition = "native_gltf"
            }
        }
        "BTA0" {
            return [pscustomobject][ordered]@{
                archive_id = $ArchiveId
                magic = $magic
                source_format = "nsbta"
                file_extension = ".nsbta"
                import_disposition = "unsupported_deferred"
            }
        }
        "BTP0" {
            return [pscustomobject][ordered]@{
                archive_id = $ArchiveId
                magic = $magic
                source_format = "nsbtp"
                file_extension = ".nsbtp"
                import_disposition = "unsupported_deferred"
            }
        }
        default {
            throw "$Label archive $ArchiveId has unsupported magic '$magic'."
        }
    }
}

function ConvertFrom-DspreMapAnimationListMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,
        [Parameter(Mandatory)]
        [ValidateRange(0, 589)]
        [int]$ModelId,
        [Parameter(Mandatory)]
        [object[]]$AnimationFormats,
        [string]$Label = "MapProp animation list"
    )

    if ($Bytes.Length -ne $script:DspreMapAnimationListRecordSize) {
        throw "$Label model $ModelId must contain exactly 20 bytes."
    }

    $hasAnimations = [int]$Bytes[0]
    $flags = [int]$Bytes[1]
    $isBicycleSlope = [int]$Bytes[2]
    $dummy = [int]$Bytes[3]
    $archiveIds = for ($slot = 0; $slot -lt 4; $slot++) {
        [BitConverter]::ToInt32($Bytes, 4 + 4 * $slot)
    }

    if ($hasAnimations -eq 0xFF) {
        if (
            $flags -ne 0xFF -or
            $isBicycleSlope -ne 0 -or
            $dummy -ne 0 -or
            @($archiveIds | Where-Object { $_ -ne $script:DspreMapAnimationNone }).Count -ne 0
        ) {
            throw "$Label model $ModelId is not a canonical empty record."
        }
        return $null
    }

    if ($hasAnimations -ne 1 -or $dummy -ne 0 -or $isBicycleSlope -notin @(0, 1)) {
        throw "$Label model $ModelId has invalid active-record header bytes."
    }
    if ($flags -notin @(0, 2, 3)) {
        throw "$Label model $ModelId has unsupported flags value $flags."
    }

    $slots = [Collections.Generic.List[object]]::new()
    $foundTerminator = $false
    for ($slot = 0; $slot -lt $archiveIds.Count; $slot++) {
        $archiveId = [int]$archiveIds[$slot]
        if ($archiveId -eq $script:DspreMapAnimationNone) {
            $foundTerminator = $true
            continue
        }
        if ($foundTerminator) {
            throw "$Label model $ModelId has a non-contiguous animation slot $slot."
        }
        if ($archiveId -lt 0 -or $archiveId -ge $AnimationFormats.Count) {
            throw "$Label model $ModelId references missing animation archive $archiveId."
        }
        $format = $AnimationFormats[$archiveId]
        $slots.Add([pscustomobject][ordered]@{
            slot = $slot
            archive_id = $archiveId
            magic = [string]$format.magic
            source_format = [string]$format.source_format
            import_disposition = [string]$format.import_disposition
        })
    }
    if ($slots.Count -eq 0) {
        throw "$Label model $ModelId is active but has no animation archive IDs."
    }

    $playback = if ($flags -eq 0) { "automatic_loop" } else { "deferred" }
    return [pscustomobject][ordered]@{
        model_id = $ModelId
        flags = $flags
        playback = $playback
        deferred_load = [bool](($flags -band 1) -ne 0)
        deferred_attach = [bool](($flags -band 2) -ne 0)
        is_bicycle_slope = [bool]$isBicycleSlope
        animation_count = $slots.Count
        slots = @($slots)
    }
}

function Get-DspreDoorMapAnimationDescriptors {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Models
    )

    $modelsById = @{}
    foreach ($model in $Models) {
        $modelsById[[int]$model.model_id] = $model
    }
    $doors = [Collections.Generic.List[object]]::new()
    foreach ($doorModel in $script:DspreDoorModels) {
        $modelId = [int]$doorModel.model_id
        if (-not $modelsById.ContainsKey($modelId)) {
            throw "Door model $modelId ($($doorModel.name)) has no animation descriptor."
        }
        $model = $modelsById[$modelId]
        $slots = @($model.slots)
        if ([string]$model.playback -ne "deferred" -or $slots.Count -notin @(2, 4)) {
            throw "Door model $modelId must declare two or four deferred animation slots."
        }
        $openSlot = $slots[0]
        $closeSlot = $slots[1]
        $isElevator = [string]$doorModel.name -eq "elevator_door"
        $doorDisposition = if (
            [string]$openSlot.import_disposition -eq "native_gltf" -and
            [string]$closeSlot.import_disposition -eq "native_gltf"
        ) { "native_gltf" } else { "unsupported_deferred" }
        if ($isElevator -and (
            [string]$openSlot.magic -ne "BTP0" -or
            [string]$closeSlot.magic -ne "BTP0" -or
            $doorDisposition -ne "unsupported_deferred"
        )) {
            throw "Elevator door model $modelId must remain an unsupported BTP0 animation."
        }
        $doors.Add([pscustomobject][ordered]@{
            model_id = $modelId
            name = [string]$doorModel.name
            animation_count = $slots.Count
            trigger = "one_shot"
            open_slot = 0
            close_slot = 1
            open_archive_id = [int]$openSlot.archive_id
            close_archive_id = [int]$closeSlot.archive_id
            import_disposition = $doorDisposition
            unsupported_reason = if ($isElevator) { "elevator_btp0" } else { $null }
        })
    }
    return @($doors)
}

function ConvertFrom-DspreMapAnimationArchives {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $AnimeListArchive,
        [Parameter(Mandatory)]
        $AnimeArchive,
        [string]$Label = "DSPRE MapProp animations"
    )

    $listMembers = @($AnimeListArchive.members)
    $animeMembers = @($AnimeArchive.members)
    if (
        [int]$AnimeListArchive.schema_version -ne 1 -or
        [int]$AnimeListArchive.member_count -ne $script:DspreMapAnimationListMemberCount -or
        $listMembers.Count -ne $script:DspreMapAnimationListMemberCount
    ) {
        throw "$Label bm_anime_list must contain exactly 590 NARC members."
    }
    if (
        [int]$AnimeArchive.schema_version -ne 1 -or
        [int]$AnimeArchive.member_count -ne $script:DspreMapAnimationArchiveMemberCount -or
        $animeMembers.Count -ne $script:DspreMapAnimationArchiveMemberCount
    ) {
        throw "$Label bm_anime must contain exactly 98 NARC members."
    }

    $formats = New-Object object[] $animeMembers.Count
    for ($archiveId = 0; $archiveId -lt $animeMembers.Count; $archiveId++) {
        $formats[$archiveId] = Get-DspreMapAnimationFormat `
            -Bytes ([byte[]]$animeMembers[$archiveId]) `
            -ArchiveId $archiveId `
            -Label $Label
    }

    $models = [Collections.Generic.List[object]]::new()
    for ($modelId = 0; $modelId -lt $listMembers.Count; $modelId++) {
        $model = ConvertFrom-DspreMapAnimationListMember `
            -Bytes ([byte[]]$listMembers[$modelId]) `
            -ModelId $modelId `
            -AnimationFormats $formats `
            -Label $Label
        if ($null -ne $model) {
            $models.Add($model)
        }
    }
    $doors = @(Get-DspreDoorMapAnimationDescriptors -Models @($models))

    $descriptor = [pscustomobject][ordered]@{
        schema_version = 1
        model_table_count = $script:DspreMapAnimationListMemberCount
        active_model_count = $models.Count
        animation_archive_count = $script:DspreMapAnimationArchiveMemberCount
        animations = @($formats)
        models = @($models)
        doors = $doors
        summary = [pscustomobject][ordered]@{
            automatic_loop_models = @($models | Where-Object { $_.playback -eq "automatic_loop" }).Count
            deferred_models = @($models | Where-Object { $_.playback -eq "deferred" }).Count
            native_gltf_animations = @($formats | Where-Object { $_.import_disposition -eq "native_gltf" }).Count
            unsupported_animations = @($formats | Where-Object { $_.import_disposition -eq "unsupported_deferred" }).Count
            door_models = $doors.Count
        }
    }
    $null = Assert-DspreMapAnimationDescriptor -Descriptor $descriptor -Label $Label
    return $descriptor
}

function Read-DspreMapAnimationDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AnimeListPath,
        [Parameter(Mandatory)]
        [string]$AnimePath,
        [Parameter(Mandatory)]
        [string]$AllowedRoot,
        [string]$Label = "DSPRE MapProp animations"
    )

    $animeListArchive = Read-DspreNarcArchive `
        -Path $AnimeListPath `
        -AllowedRoot $AllowedRoot `
        -Label "$Label bm_anime_list"
    $animeArchive = Read-DspreNarcArchive `
        -Path $AnimePath `
        -AllowedRoot $AllowedRoot `
        -Label "$Label bm_anime"
    return ConvertFrom-DspreMapAnimationArchives `
        -AnimeListArchive $animeListArchive `
        -AnimeArchive $animeArchive `
        -Label $Label
}

function Assert-DspreMapAnimationDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Descriptor,
        [string]$Label = "MapProp animation descriptor"
    )

    if (
        [int]$Descriptor.schema_version -ne 1 -or
        [int]$Descriptor.model_table_count -ne $script:DspreMapAnimationListMemberCount -or
        [int]$Descriptor.animation_archive_count -ne $script:DspreMapAnimationArchiveMemberCount -or
        @($Descriptor.animations).Count -ne $script:DspreMapAnimationArchiveMemberCount -or
        [int]$Descriptor.active_model_count -ne @($Descriptor.models).Count -or
        @($Descriptor.doors).Count -ne $script:DspreDoorModels.Count
    ) {
        throw "$Label has inconsistent top-level counts."
    }

    foreach ($animation in @($Descriptor.animations)) {
        if (
            [int]$animation.archive_id -lt 0 -or
            [int]$animation.archive_id -ge $script:DspreMapAnimationArchiveMemberCount -or
            [string]$animation.magic -notin @("BCA0", "BTA0", "BTP0") -or
            (
                [string]$animation.magic -eq "BCA0" -and
                [string]$animation.import_disposition -ne "native_gltf"
            ) -or
            (
                [string]$animation.magic -ne "BCA0" -and
                [string]$animation.import_disposition -ne "unsupported_deferred"
            )
        ) {
            throw "$Label contains an invalid animation archive descriptor."
        }
    }
    foreach ($model in @($Descriptor.models)) {
        if (
            [int]$model.model_id -lt 0 -or
            [int]$model.model_id -ge $script:DspreMapAnimationListMemberCount -or
            [int]$model.flags -notin @(0, 2, 3) -or
            ([int]$model.flags -eq 0 -and [string]$model.playback -ne "automatic_loop") -or
            ([int]$model.flags -ne 0 -and [string]$model.playback -ne "deferred") -or
            [int]$model.animation_count -ne @($model.slots).Count -or
            @($model.slots).Count -lt 1
        ) {
            throw "$Label contains an invalid model animation descriptor."
        }
    }
    $elevator = @($Descriptor.doors | Where-Object { $_.name -eq "elevator_door" })
    if (
        $elevator.Count -ne 1 -or
        [int]$elevator[0].model_id -ne 75 -or
        [int]$elevator[0].open_slot -ne 0 -or
        [int]$elevator[0].close_slot -ne 1 -or
        [string]$elevator[0].import_disposition -ne "unsupported_deferred" -or
        [string]$elevator[0].unsupported_reason -ne "elevator_btp0"
    ) {
        throw "$Label does not preserve the unsupported elevator-door contract."
    }
    return [pscustomobject]@{
        active_models = @($Descriptor.models).Count
        animations = @($Descriptor.animations).Count
        doors = @($Descriptor.doors).Count
    }
}

function Export-DspreMapAnimationMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $AnimeArchive,
        [Parameter(Mandatory)]
        [ValidateRange(0, 97)]
        [int]$MemberId,
        [Parameter(Mandatory)]
        [string]$OutputPath,
        [string]$WorkRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) ".work")
    )

    $repositoryWorkRoot = [IO.Path]::GetFullPath(
        (Join-Path (Split-Path $PSScriptRoot -Parent) ".work")
    ).TrimEnd('\', '/')
    $workRootFull = [IO.Path]::GetFullPath($WorkRoot).TrimEnd('\', '/')
    $repositoryPrefix = $repositoryWorkRoot + [IO.Path]::DirectorySeparatorChar
    if (
        $workRootFull -ne $repositoryWorkRoot -and
        -not $workRootFull.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)
    ) {
        throw "MapProp animation work root must remain under .work: $workRootFull"
    }
    $outputFull = [IO.Path]::GetFullPath($OutputPath)
    $workPrefix = $workRootFull + [IO.Path]::DirectorySeparatorChar
    if (-not $outputFull.StartsWith($workPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "MapProp animation output must remain below its .work root: $outputFull"
    }

    $members = @($AnimeArchive.members)
    if (
        [int]$AnimeArchive.schema_version -ne 1 -or
        [int]$AnimeArchive.member_count -ne $script:DspreMapAnimationArchiveMemberCount -or
        $members.Count -ne $script:DspreMapAnimationArchiveMemberCount
    ) {
        throw "MapProp animation archive must contain exactly 98 members."
    }
    $bytes = [byte[]](Get-DspreNarcMemberBytes `
        -Archive $AnimeArchive `
        -MemberId $MemberId `
        -Label "bm_anime")
    $format = Get-DspreMapAnimationFormat -Bytes $bytes -ArchiveId $MemberId
    if ([IO.Path]::GetExtension($outputFull) -ne [string]$format.file_extension) {
        throw "MapProp animation member $MemberId must use the $($format.file_extension) extension."
    }

    if (-not (Test-Path -LiteralPath $repositoryWorkRoot)) {
        $null = [IO.Directory]::CreateDirectory($repositoryWorkRoot)
    }
    $repositoryWorkItem = Get-Item -LiteralPath $repositoryWorkRoot -Force
    if (
        -not $repositoryWorkItem.PSIsContainer -or
        ($repositoryWorkItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    ) {
        throw "Repository .work root is unsafe: $repositoryWorkRoot"
    }
    $relativeWorkRoot = $workRootFull.Substring($repositoryWorkRoot.Length).TrimStart('\', '/')
    $current = $repositoryWorkRoot
    foreach ($component in @($relativeWorkRoot.Split(@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))) {
        $current = Join-Path $current $component
        if (-not (Test-Path -LiteralPath $current)) {
            $null = [IO.Directory]::CreateDirectory($current)
        }
        $item = Get-Item -LiteralPath $current -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "MapProp animation work root contains an unsafe component: $current"
        }
    }
    $rootItem = Get-Item -LiteralPath $workRootFull -Force
    if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "MapProp animation work root is unsafe: $workRootFull"
    }
    $parent = Split-Path $outputFull -Parent
    $relativeParent = $parent.Substring($workRootFull.Length).TrimStart('\', '/')
    $current = $workRootFull
    foreach ($component in @($relativeParent.Split(@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))) {
        $current = Join-Path $current $component
        if (-not (Test-Path -LiteralPath $current)) {
            $null = [IO.Directory]::CreateDirectory($current)
        }
        $item = Get-Item -LiteralPath $current -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "MapProp animation output path contains an unsafe component: $current"
        }
    }
    if (Test-Path -LiteralPath $outputFull) {
        $outputItem = Get-Item -LiteralPath $outputFull -Force
        if ($outputItem.PSIsContainer -or ($outputItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "MapProp animation output is not a replaceable regular file: $outputFull"
        }
    }

    $temporaryPath = Join-Path $parent (".{0}.{1}.tmp" -f [IO.Path]::GetFileName($outputFull), [Guid]::NewGuid().ToString("N"))
    try {
        [IO.File]::WriteAllBytes($temporaryPath, $bytes)
        Move-Item -LiteralPath $temporaryPath -Destination $outputFull -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
    $hash = (Get-FileHash -LiteralPath $outputFull -Algorithm SHA256).Hash.ToLowerInvariant()
    return [pscustomobject][ordered]@{
        member_id = $MemberId
        path = $outputFull
        magic = [string]$format.magic
        source_format = [string]$format.source_format
        import_disposition = [string]$format.import_disposition
        byte_length = $bytes.Length
        sha256 = $hash
    }
}

function Get-DspreGlbAnimationMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "MapProp animation GLB was not found: $Path"
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if (
        $bytes.Length -lt 20 -or
        [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne "glTF" -or
        [BitConverter]::ToUInt32($bytes, 4) -ne 2 -or
        [BitConverter]::ToUInt32($bytes, 8) -ne $bytes.Length
    ) {
        throw "MapProp animation GLB header is invalid: $Path"
    }
    $jsonLength = [int][BitConverter]::ToUInt32($bytes, 12)
    $jsonType = [Text.Encoding]::ASCII.GetString($bytes, 16, 4)
    if ($jsonType -ne "JSON" -or $jsonLength -lt 2 -or 20 + $jsonLength -gt $bytes.Length) {
        throw "MapProp animation GLB JSON chunk is invalid: $Path"
    }
    $jsonText = [Text.Encoding]::UTF8.GetString($bytes, 20, $jsonLength).TrimEnd(
        [char]0,
        [char]0x20
    )
    $document = $jsonText | ConvertFrom-Json
    $animations = [Collections.Generic.List[object]]::new()
    $animationIndex = 0
    foreach ($animation in @($document.animations)) {
        $name = [string]$animation.name
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = "animation_{0:D2}" -f $animationIndex
        }
        $duration = 0.0
        foreach ($sampler in @($animation.samplers)) {
            $accessorIndex = [int]$sampler.input
            if ($accessorIndex -lt 0 -or $accessorIndex -ge @($document.accessors).Count) {
                throw "GLB animation '$name' references a missing input accessor: $Path"
            }
            $accessor = @($document.accessors)[$accessorIndex]
            if ($null -eq $accessor.PSObject.Properties["max"] -or @($accessor.max).Count -ne 1) {
                throw "GLB animation '$name' input accessor has no scalar maximum: $Path"
            }
            $duration = [Math]::Max($duration, [double]@($accessor.max)[0])
        }
        if ($duration -le 0.0) {
            throw "GLB animation '$name' has no positive duration: $Path"
        }
        $sourceFrameCount = [int][Math]::Round($duration * 60.0) + 1
        if ($sourceFrameCount -lt 2) {
            throw "GLB animation '$name' has fewer than two source frames: $Path"
        }
        $animations.Add([pscustomobject][ordered]@{
            index = $animationIndex
            name = $name
            source_frame_count = $sourceFrameCount
            gltf_fps = 60
            gltf_duration_seconds = [Math]::Round($duration, 8)
            duration_seconds = [Math]::Round($sourceFrameCount / 30.0, 8)
        })
        $animationIndex++
    }
    return @($animations)
}
