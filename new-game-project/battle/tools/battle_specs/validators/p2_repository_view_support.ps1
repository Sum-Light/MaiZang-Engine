Set-StrictMode -Version Latest

$script:P2RepositoryViewMaxFileBytes = 524288
$script:P2RepositoryViewMaxCandidatePaths = 65535
$script:P2RepositoryViewMaxCapturedBytes = 67108864
$script:P2RepositoryViewMaxGitMetadataBytes = 33554432
$script:P2RepositoryViewMaxMetadataEntries = 131072

if ($null -eq ("MaiZang.Battle.P2NativeFile" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace MaiZang.Battle {
    public static class P2NativeFile {
        private const uint GenericRead = 0x80000000;
        private const uint GenericWrite = 0x40000000;
        private const uint FileReadAttributes = 0x00000080;
        private const uint FileShareRead = 0x00000001;
        private const uint FileShareWrite = 0x00000002;
        private const uint OpenExisting = 3;
        private const uint CreateNew = 1;
        private const uint BackupSemantics = 0x02000000;
        private const uint OpenReparsePoint = 0x00200000;

        [StructLayout(LayoutKind.Sequential)]
        private struct ByHandleFileInformation {
            public uint FileAttributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(
            SafeFileHandle file,
            out ByHandleFileInformation information);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(
            SafeFileHandle file,
            StringBuilder path,
            uint pathLength,
            uint flags);

        public static SafeFileHandle OpenAttributesNoFollow(string path) {
            return Open(path, FileReadAttributes, FileShareRead | FileShareWrite);
        }

        public static SafeFileHandle OpenReadNoFollow(string path) {
            return Open(path, GenericRead, FileShareRead);
        }

        public static SafeFileHandle CreateNewReadWriteNoFollow(string path) {
            SafeFileHandle handle = CreateFileW(
                path,
                GenericRead | GenericWrite,
                FileShareRead,
                IntPtr.Zero,
                CreateNew,
                OpenReparsePoint,
                IntPtr.Zero);
            if (handle.IsInvalid) {
                int error = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new Win32Exception(error,
                    "No-follow create failed for '" + path + "'.");
            }
            return handle;
        }

        private static SafeFileHandle Open(string path, uint access, uint share) {
            SafeFileHandle handle = CreateFileW(
                path,
                access,
                share,
                IntPtr.Zero,
                OpenExisting,
                BackupSemantics | OpenReparsePoint,
                IntPtr.Zero);
            if (handle.IsInvalid) {
                int error = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new Win32Exception(error, "No-follow open failed for '" + path + "'.");
            }
            return handle;
        }

        public static uint GetAttributes(SafeFileHandle handle) {
            ByHandleFileInformation information;
            if (!GetFileInformationByHandle(handle, out information)) {
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Handle attributes could not be read.");
            }
            return information.FileAttributes;
        }

        public static string GetFinalPath(SafeFileHandle handle) {
            StringBuilder value = new StringBuilder(32768);
            uint length = GetFinalPathNameByHandleW(
                handle, value, (uint)value.Capacity, 0);
            if (length == 0 || length >= value.Capacity) {
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Final handle path could not be read.");
            }
            return value.ToString();
        }
    }
}
'@
}

$script:P2RepositoryViewExecutionSurface = @(
    "new-game-project/battle/.gitignore",
    "new-game-project/battle/manifests/source_audit/source_audit_policy.json",
    "new-game-project/battle/manifests/source_audit/source_audit_seal.json",
    "new-game-project/battle/manifests/source_audit/source_index_baseline.json",
    "new-game-project/battle/tests/catalog/p0_asset_boundary_test.ps1",
    "new-game-project/battle/tests/check_battle_scope_test.ps1",
    "new-game-project/battle/tests/specs/p2_id_presentation_contract_test.ps1",
    "new-game-project/battle/tests/specs/p2_fixture_preflight_test.ps1",
    "new-game-project/battle/tests/specs/p2_repository_view_test.ps1",
    "new-game-project/battle/tests/specs/p2_release_reference_test.ps1",
    "new-game-project/battle/tests/specs/p2_spec_compiler_test.ps1",
    "new-game-project/battle/tests/specs/p2_spec_contract_test.ps1",
    "new-game-project/battle/tests/specs/p2_source_evidence_join_test.ps1",
    "new-game-project/battle/tools/battle_catalog/validators/battle_asset_support.ps1",
    "new-game-project/battle/tools/battle_catalog/validators/canonical_json_support.ps1",
    "new-game-project/battle/tools/battle_catalog/validators/strict_json_support.ps1",
    "new-game-project/battle/tools/battle_specs/compilers/compile_p2_specs.ps1",
    "new-game-project/battle/tools/battle_specs/compilers/compile_p2_fixture_requirements.ps1",
    "new-game-project/battle/tools/battle_specs/compilers/compile_p2_source_evidence_join.ps1",
    "new-game-project/battle/tools/battle_specs/compilers/p2_release_reference_support.ps1",
    "new-game-project/battle/tools/battle_specs/compilers/p2_fixture_preflight_support.ps1",
    "new-game-project/battle/tools/battle_specs/compilers/p2_source_evidence_join_support.ps1",
    "new-game-project/battle/tools/battle_specs/compilers/p2_spec_compiler_support.ps1",
    "new-game-project/battle/tools/battle_specs/compilers/validate_p2_release_references.ps1",
    "new-game-project/battle/tools/battle_specs/schemas/compiled_fixture_requirement_manifest.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/compiled_release_mechanism_reference_manifest.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/compiled_spec_manifest.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/compiled_source_evidence_join_manifest.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/event_schema.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/handler_binding.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/mechanism_spec.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/presentation_contracts.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/resolver_spec.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/runtime_rule_catalog_manifest.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/stable_id_manifest.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/source_evidence.schema.json",
    "new-game-project/battle/tools/battle_specs/schemas/test_manifest_entry.schema.json",
    "new-game-project/battle/tools/battle_specs/validators/p2_id_manifest_support.ps1",
    "new-game-project/battle/tools/battle_specs/validators/p2_repository_view_support.ps1",
    "new-game-project/battle/tools/battle_specs/validators/p2_spec_contract_support.ps1",
    "new-game-project/battle/tools/battle_specs/validators/p2_spec_set_support.ps1",
    "new-game-project/battle/tools/battle_specs/validators/validate_p2_id_manifests.ps1",
    "new-game-project/battle/tools/battle_specs/validators/validate_p2_spec_contracts.ps1",
    "new-game-project/battle/tools/check_battle_assets.ps1",
    "new-game-project/battle/tools/check_battle_dependencies.ps1",
    "new-game-project/battle/tools/check_battle_scope.ps1"
)

function Invoke-P2RepositoryViewGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [ValidateRange(1, 67108864)]
        [int]$MaxOutputBytes = $script:P2RepositoryViewMaxGitMetadataBytes
    )

    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        throw "P2_REPOSITORY_VIEW_GIT_NOT_FOUND: Git is required."
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $gitCommand.Source
    $startInfo.Arguments = '-C "{0}" {1}' -f $Root.Replace('"', '\"'), $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    # Do not buffer an attacker-amplifiable stderr stream in memory.
    $startInfo.RedirectStandardError = $false
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $memory = [IO.MemoryStream]::new()
    $processStarted = $false
    try {
        if (-not $process.Start()) {
            throw "P2_REPOSITORY_VIEW_GIT_START: Git could not be started."
        }
        $processStarted = $true
        $buffer = New-Object byte[] 81920
        while (($read = $process.StandardOutput.BaseStream.Read(
            $buffer,
            0,
            $buffer.Length
        )) -gt 0) {
            if (($memory.Length + $read) -gt $MaxOutputBytes) {
                try {
                    $process.Kill()
                }
                catch {
                    # The process may have exited between the bounded read and kill.
                }
                throw (
                    "P2_REPOSITORY_VIEW_GIT_OUTPUT_LIMIT: Git output exceeds " +
                    "the $MaxOutputBytes-byte command limit."
                )
            }
            $memory.Write($buffer, 0, $read)
        }
        $process.WaitForExit()
        return [pscustomobject][ordered]@{
            ExitCode = $process.ExitCode
            Bytes = $memory.ToArray()
            ErrorText = ""
        }
    }
    finally {
        if ($processStarted -and -not $process.HasExited) {
            try {
                $process.Kill()
                $process.WaitForExit()
            }
            catch {
                # Preserve the primary bounded-read or Git failure.
            }
        }
        $memory.Dispose()
        $process.Dispose()
    }
}

function ConvertFrom-P2RepositoryViewUtf8 {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Context
    )

    try {
        return [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
    }
    catch {
        throw "P2_REPOSITORY_VIEW_UTF8: $Context is not valid UTF-8."
    }
}

function ConvertTo-P2RepositoryViewRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowEmpty
    )

    $normalized = $Path.Replace('\', '/')
    if ($AllowEmpty -and [string]::IsNullOrEmpty($normalized)) {
        return ""
    }
    if ([string]::IsNullOrWhiteSpace($normalized) -or
        $normalized.StartsWith('/', [StringComparison]::Ordinal) -or
        $normalized -match '^[A-Za-z]:' -or
        $normalized -match '[\x00-\x1f\x7f"]') {
        throw "P2_REPOSITORY_VIEW_PATH: '$Path' is not a canonical relative path."
    }
    foreach ($segment in $normalized.Split('/')) {
        if ([string]::IsNullOrEmpty($segment) -or $segment -in @('.', '..')) {
            throw "P2_REPOSITORY_VIEW_PATH: '$Path' is not a canonical relative path."
        }
    }
    return $normalized
}

function ConvertFrom-P2RepositoryViewNativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        return '\\' + $Path.Substring(8)
    }
    if ($Path.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring(4)
    }
    return $Path
}

function Get-P2RepositoryViewExpectedFinalPath {
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $relative = ConvertTo-P2RepositoryViewRelativePath $RelativePath
    return [IO.Path]::GetFullPath((Join-Path ([string]$View.RootFinalPath) `
        $relative.Replace('/', '\'))).TrimEnd('\')
}

function Open-P2RepositoryViewVerifiedHandle {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ExpectedFinalPath = "",
        [ValidateSet("File", "Directory", "Either")]
        [string]$ExpectedKind = "Either",
        [ValidateSet("Attributes", "Read")]
        [string]$Access = "Attributes",
        [string]$ErrorPrefix = "P2_REPOSITORY_VIEW"
    )

    $handle = $null
    try {
        if ($Access -ceq "Read") {
            $handle = [MaiZang.Battle.P2NativeFile]::OpenReadNoFollow($Path)
        }
        else {
            $handle = [MaiZang.Battle.P2NativeFile]::OpenAttributesNoFollow($Path)
        }
        $attributes = [MaiZang.Battle.P2NativeFile]::GetAttributes($handle)
        if (($attributes -band [uint32][IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "${ErrorPrefix}_REPARSE: '$Path' is a reparse point."
        }
        $isDirectory = (
            ($attributes -band [uint32][IO.FileAttributes]::Directory) -ne 0
        )
        if (($ExpectedKind -ceq "File" -and $isDirectory) -or
            ($ExpectedKind -ceq "Directory" -and -not $isDirectory)) {
            throw "${ErrorPrefix}_KIND: '$Path' is not a $ExpectedKind."
        }
        $finalPath = ConvertFrom-P2RepositoryViewNativePath (
            [MaiZang.Battle.P2NativeFile]::GetFinalPath($handle)
        )
        $finalPath = [IO.Path]::GetFullPath($finalPath).TrimEnd('\')
        if (-not [string]::IsNullOrWhiteSpace($ExpectedFinalPath)) {
            $expected = [IO.Path]::GetFullPath($ExpectedFinalPath).TrimEnd('\')
            if (-not $finalPath.Equals(
                $expected,
                [StringComparison]::OrdinalIgnoreCase
            )) {
                throw (
                    "${ErrorPrefix}_REDIRECT: '$Path' resolves to '$finalPath', " +
                    "not '$expected'."
                )
            }
        }
        return [pscustomobject][ordered]@{
            Handle = $handle
            FinalPath = $finalPath
            IsDirectory = $isDirectory
            Attributes = $attributes
        }
    }
    catch {
        if ($null -ne $handle) {
            $handle.Dispose()
        }
        throw
    }
}

function New-P2RepositoryViewVerifiedFileHandle {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedFinalPath,
        [string]$ErrorPrefix = "P2_REPOSITORY_VIEW"
    )

    $handle = $null
    try {
        $handle = [MaiZang.Battle.P2NativeFile]::CreateNewReadWriteNoFollow($Path)
        $attributes = [MaiZang.Battle.P2NativeFile]::GetAttributes($handle)
        if (($attributes -band [uint32][IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ($attributes -band [uint32][IO.FileAttributes]::Directory) -ne 0) {
            throw "${ErrorPrefix}_KIND: '$Path' is not a regular file."
        }
        $finalPath = ConvertFrom-P2RepositoryViewNativePath (
            [MaiZang.Battle.P2NativeFile]::GetFinalPath($handle)
        )
        $finalPath = [IO.Path]::GetFullPath($finalPath).TrimEnd('\')
        $expected = [IO.Path]::GetFullPath($ExpectedFinalPath).TrimEnd('\')
        if (-not $finalPath.Equals(
            $expected,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw (
                "${ErrorPrefix}_REDIRECT: '$Path' resolves to '$finalPath', " +
                "not '$expected'."
            )
        }
        return [pscustomobject][ordered]@{
            Handle = $handle
            FinalPath = $finalPath
            IsDirectory = $false
            Attributes = $attributes
        }
    }
    catch {
        if ($null -ne $handle) {
            $handle.Dispose()
        }
        throw
    }
}

function Assert-P2RepositoryViewObject {
    param([Parameter(Mandatory = $true)][object]$View)

    if ($View -isnot [PSCustomObject] -or
        [string]$View.ViewKind -cne "P2_REPOSITORY_VIEW" -or
        [string]$View.Mode -cnotin @("Repository", "Worktree", "Staged")) {
        throw "P2_REPOSITORY_VIEW_REQUIRED: A valid repository view is required."
    }
}

function Get-P2RepositoryViewContainedPath {
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    Assert-P2RepositoryViewObject $View
    $relative = ConvertTo-P2RepositoryViewRelativePath $RelativePath
    $root = [string]$View.ProjectRoot
    $fullPath = [IO.Path]::GetFullPath((Join-Path $root $relative.Replace('/', '\')))
    if (-not $fullPath.StartsWith(
        $root + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "P2_REPOSITORY_VIEW_PATH_ESCAPE: '$RelativePath' escapes ProjectRoot."
    }
    $current = $fullPath
    while ($current.StartsWith(
        $root + '\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "P2_REPOSITORY_VIEW_REPARSE: '$current' is a reparse point."
            }
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            break
        }
        $current = $parent
    }
    return $fullPath
}

function Get-P2RepositoryViewGitBlobBytes {
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [Parameter(Mandatory = $true)][string]$BlobOid,
        [ValidateRange(1, 524288)]
        [int]$MaxBytes = $script:P2RepositoryViewMaxFileBytes,
        [ValidateRange(0, 67108864)]
        [long]$RemainingCaptureBytes = $script:P2RepositoryViewMaxCapturedBytes
    )

    if ($BlobOid -cnotmatch '^[0-9a-f]{40}([0-9a-f]{24})?$') {
        throw "P2_REPOSITORY_VIEW_BLOB_ID: '$BlobOid' is not a Git blob OID."
    }
    $sizeResult = Invoke-P2RepositoryViewGit -Root ([string]$View.ProjectRoot) `
        -Arguments ('cat-file -s "{0}"' -f $BlobOid) -MaxOutputBytes 128
    if ($sizeResult.ExitCode -ne 0) {
        throw "P2_REPOSITORY_VIEW_BLOB_SIZE: Git blob '$BlobOid' size is unavailable."
    }
    $sizeText = (ConvertFrom-P2RepositoryViewUtf8 `
        -Bytes ([byte[]]$sizeResult.Bytes) -Context "Git blob size").Trim()
    $blobLength = 0L
    if (-not [long]::TryParse(
        $sizeText,
        [Globalization.NumberStyles]::None,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$blobLength
    ) -or $blobLength -lt 0) {
        throw "P2_REPOSITORY_VIEW_BLOB_SIZE: Git returned an invalid blob size."
    }
    if ($blobLength -gt $MaxBytes) {
        throw (
            "P2_REPOSITORY_VIEW_FILE_TOO_LARGE: Git blob '$BlobOid' exceeds " +
            "the $MaxBytes-byte capture limit."
        )
    }
    if ($blobLength -gt $RemainingCaptureBytes) {
        throw (
            "P2_REPOSITORY_VIEW_CAPTURE_BYTES: Git blob '$BlobOid' exceeds " +
            "the remaining $RemainingCaptureBytes-byte view budget."
        )
    }
    $result = Invoke-P2RepositoryViewGit -Root ([string]$View.ProjectRoot) `
        -Arguments ('cat-file blob "{0}"' -f $BlobOid) `
        -MaxOutputBytes $MaxBytes
    if ($result.ExitCode -ne 0) {
        throw (
            "P2_REPOSITORY_VIEW_BLOB: Git blob '$BlobOid' could not be read" +
            $(if ($result.ErrorText.Length -gt 0) {
                ": $($result.ErrorText)"
            } else {
                "."
            })
        )
    }
    return ,([byte[]]$result.Bytes)
}

function Read-P2RepositoryViewBoundedFileBytes {
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [ValidateRange(1, 524288)]
        [int]$MaxBytes = $script:P2RepositoryViewMaxFileBytes,
        [ValidateRange(0, 67108864)]
        [long]$RemainingCaptureBytes = $script:P2RepositoryViewMaxCapturedBytes
    )

    $stream = $null
    $verified = $null
    try {
        $relative = ConvertTo-P2RepositoryViewRelativePath $RelativePath
        $path = Get-P2RepositoryViewContainedPath -View $View `
            -RelativePath $relative
        $verified = Open-P2RepositoryViewVerifiedHandle -Path $path `
            -ExpectedFinalPath (Get-P2RepositoryViewExpectedFinalPath `
                -View $View -RelativePath $relative) `
            -ExpectedKind File -Access Read
        $stream = [IO.FileStream]::new(
            [Microsoft.Win32.SafeHandles.SafeFileHandle]$verified.Handle,
            [IO.FileAccess]::Read
        )
        if ($stream.Length -gt $MaxBytes) {
            throw (
                "P2_REPOSITORY_VIEW_FILE_TOO_LARGE: '$relative' exceeds the " +
                "$MaxBytes-byte capture limit."
            )
        }
        if ($stream.Length -gt $RemainingCaptureBytes) {
            throw (
                "P2_REPOSITORY_VIEW_CAPTURE_BYTES: '$relative' exceeds the " +
                "remaining $RemainingCaptureBytes-byte view budget."
            )
        }
        $length = [int]$stream.Length
        $bytes = New-Object byte[] $length
        $offset = 0
        while ($offset -lt $length) {
            $read = $stream.Read($bytes, $offset, $length - $offset)
            if ($read -le 0) {
                throw "P2_REPOSITORY_VIEW_FILE_SHORT_READ: '$relative' changed while captured."
            }
            $offset += $read
        }
        if ($stream.ReadByte() -ne -1) {
            throw "P2_REPOSITORY_VIEW_FILE_GROWTH: '$relative' grew while captured."
        }
        return ,([byte[]]$bytes)
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
        elseif ($null -ne $verified) {
            $verified.Handle.Dispose()
        }
    }
}

function Join-P2RepositoryViewGitPathspecArguments {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $arguments = [Collections.Generic.List[string]]::new()
    foreach ($pathValue in $Paths) {
        $path = ConvertTo-P2RepositoryViewRelativePath ([string]$pathValue)
        $arguments.Add(('"{0}"' -f $path))
    }
    return $arguments.ToArray() -join ' '
}

function Get-P2RepositoryViewHeadEntries {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$HeadOid,
        [Parameter(Mandatory = $true)][string[]]$Pathspecs
    )

    $entries = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    if ([string]::IsNullOrEmpty($HeadOid)) {
        return $entries
    }
    $pathspecArguments = Join-P2RepositoryViewGitPathspecArguments `
        -Paths $Pathspecs
    $result = Invoke-P2RepositoryViewGit -Root $Root -Arguments (
        '--literal-pathspecs ls-tree -r -z "{0}" -- {1}' -f
            $HeadOid, $pathspecArguments
    )
    if ($result.ExitCode -ne 0) {
        throw "P2_REPOSITORY_VIEW_HEAD_TREE: HEAD tree could not be enumerated."
    }
    $text = ConvertFrom-P2RepositoryViewUtf8 -Bytes ([byte[]]$result.Bytes) `
        -Context "HEAD tree paths"
    foreach ($record in $text.Split([char]0)) {
        if ($record.Length -eq 0) {
            continue
        }
        if ($record -cnotmatch '^(?<mode>[0-9]{6}) (?<type>[a-z]+) (?<blob>[0-9a-f]{40}([0-9a-f]{24})?)\t(?<path>.+)$') {
            throw "P2_REPOSITORY_VIEW_HEAD_ENTRY: Git returned a malformed HEAD entry."
        }
        $relativePath = ConvertTo-P2RepositoryViewRelativePath $Matches.path
        if ($entries.ContainsKey($relativePath)) {
            throw "P2_REPOSITORY_VIEW_HEAD_DUPLICATE: HEAD repeats '$relativePath'."
        }
        if ($entries.Count -ge $script:P2RepositoryViewMaxMetadataEntries) {
            throw (
                "P2_REPOSITORY_VIEW_METADATA_COUNT: HEAD exceeds the " +
                "$script:P2RepositoryViewMaxMetadataEntries-entry limit."
            )
        }
        $entries.Add($relativePath, [pscustomobject][ordered]@{
            RelativePath = $relativePath
            Mode = [string]$Matches.mode
            ObjectType = [string]$Matches.type
            BlobOid = [string]$Matches.blob
            Stage = 0
        })
    }
    return $entries
}

function Get-P2RepositoryViewIndexEntries {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Pathspecs
    )

    $pathspecArguments = Join-P2RepositoryViewGitPathspecArguments `
        -Paths $Pathspecs
    $result = Invoke-P2RepositoryViewGit -Root $Root -Arguments (
        '--literal-pathspecs ls-files --stage -z -- {0}' -f $pathspecArguments
    )
    if ($result.ExitCode -ne 0) {
        throw "P2_REPOSITORY_VIEW_INDEX: Git index could not be enumerated."
    }
    $text = ConvertFrom-P2RepositoryViewUtf8 -Bytes ([byte[]]$result.Bytes) `
        -Context "Git index paths"
    $entries = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($record in $text.Split([char]0)) {
        if ($record.Length -eq 0) {
            continue
        }
        if ($record -cnotmatch '^(?<mode>[0-9]{6}) (?<blob>[0-9a-f]{40}([0-9a-f]{24})?) (?<stage>[0-3])\t(?<path>.+)$') {
            throw "P2_REPOSITORY_VIEW_INDEX_ENTRY: Git returned a malformed index entry."
        }
        $relativePath = ConvertTo-P2RepositoryViewRelativePath $Matches.path
        $stage = [int]$Matches.stage
        if ($stage -ne 0) {
            throw "P2_REPOSITORY_VIEW_UNMERGED: '$relativePath' has index stage $stage."
        }
        $mode = [string]$Matches.mode
        if ($mode -cnotin @("100644", "100755")) {
            throw "P2_REPOSITORY_VIEW_MODE: '$relativePath' has unsupported mode $mode."
        }
        if ($entries.ContainsKey($relativePath)) {
            throw "P2_REPOSITORY_VIEW_INDEX_DUPLICATE: Index repeats '$relativePath'."
        }
        if ($entries.Count -ge $script:P2RepositoryViewMaxMetadataEntries) {
            throw (
                "P2_REPOSITORY_VIEW_METADATA_COUNT: Index exceeds the " +
                "$script:P2RepositoryViewMaxMetadataEntries-entry limit."
            )
        }
        $entries.Add($relativePath, [pscustomobject][ordered]@{
            RelativePath = $relativePath
            Mode = $mode
            ObjectType = "blob"
            BlobOid = [string]$Matches.blob
            Stage = $stage
        })
    }
    return $entries
}

function Test-P2RepositoryViewByteEquality {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Left,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function Assert-P2RepositoryViewExecutionSurfaceParity {
    param([Parameter(Mandatory = $true)][object]$View)

    Assert-P2RepositoryViewObject $View
    if ([string]$View.Mode -cne "Staged") {
        return
    }
    foreach ($relativePath in $script:P2RepositoryViewExecutionSurface) {
        $indexExists = $View.IndexEntries.ContainsKey($relativePath)
        $headExists = $View.HeadEntries.ContainsKey($relativePath)
        $fullPath = Get-P2RepositoryViewContainedPath -View $View `
            -RelativePath $relativePath
        $worktreeExists = Test-Path -LiteralPath $fullPath -PathType Leaf
        if (-not $indexExists) {
            if ($headExists) {
                throw (
                    "P2_REPOSITORY_VIEW_SURFACE_DELETED: '$relativePath' is " +
                    "required by the staged execution surface."
                )
            }
            if ($worktreeExists) {
                throw (
                    "P2_REPOSITORY_VIEW_SURFACE_UNTRACKED: '$relativePath' " +
                    "participates in validation but is absent from the index."
                )
            }
            continue
        }
        if (-not $worktreeExists) {
            throw (
                "P2_REPOSITORY_VIEW_SURFACE_MISSING: Worktree file is missing " +
                "for staged execution path '$relativePath'."
            )
        }
        $indexBytes = Get-P2RepositoryViewGitBlobBytes -View $View `
            -BlobOid ([string]$View.IndexEntries[$relativePath].BlobOid)
        $worktreeBytes = Read-P2RepositoryViewBoundedFileBytes -View $View `
            -RelativePath $relativePath
        if (-not (Test-P2RepositoryViewByteEquality $indexBytes $worktreeBytes)) {
            throw (
                "P2_REPOSITORY_VIEW_SURFACE_MISMATCH: '$relativePath' differs " +
                "between the captured index and worktree."
            )
        }
    }
}

function Get-P2RepositoryViewWorktreePaths {
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [Parameter(Mandatory = $true)][string]$Prefix,
        [ValidateRange(1, 65535)]
        [int]$MaxPaths = $script:P2RepositoryViewMaxCandidatePaths
    )

    $normalizedPrefix = ConvertTo-P2RepositoryViewRelativePath $Prefix
    $fullPrefix = Get-P2RepositoryViewContainedPath -View $View `
        -RelativePath $normalizedPrefix
    if (-not (Test-Path -LiteralPath $fullPrefix)) {
        return @()
    }
    $prefixGuard = Open-P2RepositoryViewVerifiedHandle -Path $fullPrefix `
        -ExpectedFinalPath (Get-P2RepositoryViewExpectedFinalPath `
            -View $View -RelativePath $normalizedPrefix) -ExpectedKind Either
    $paths = [Collections.Generic.List[string]]::new()
    $visitedEntries = 0
    try {
        if (-not $prefixGuard.IsDirectory) {
            $paths.Add($normalizedPrefix)
        }
        else {
            $pending = [Collections.Generic.Stack[string]]::new()
            $pending.Push($fullPrefix)
            while ($pending.Count -gt 0) {
                $directory = $pending.Pop()
                $directoryRelative = $directory.Substring(
                    ([string]$View.ProjectRoot).Length + 1
                ).Replace('\', '/')
                $directoryGuard = Open-P2RepositoryViewVerifiedHandle `
                    -Path $directory -ExpectedFinalPath (
                        Get-P2RepositoryViewExpectedFinalPath -View $View `
                            -RelativePath $directoryRelative
                    ) -ExpectedKind Directory
                try {
                    $directoryInfo = [IO.DirectoryInfo]::new($directory)
                    foreach ($item in $directoryInfo.EnumerateFileSystemInfos()) {
                $visitedEntries += 1
                if ($visitedEntries -gt $script:P2RepositoryViewMaxMetadataEntries) {
                    throw (
                        "P2_REPOSITORY_VIEW_METADATA_COUNT: Worktree traversal " +
                        "exceeds the $script:P2RepositoryViewMaxMetadataEntries-entry limit."
                    )
                }
                        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                            throw "P2_REPOSITORY_VIEW_REPARSE: '$($item.FullName)' is a reparse point."
                        }
                        if ($item -is [IO.DirectoryInfo]) {
                            $pending.Push([string]$item.FullName)
                            continue
                        }
                        $fullPath = [IO.Path]::GetFullPath([string]$item.FullName)
                        if ($paths.Count -ge $MaxPaths) {
                            throw (
                                "P2_REPOSITORY_VIEW_CANDIDATE_COUNT: Candidate capture " +
                                "exceeds the $MaxPaths-path limit."
                            )
                        }
                        $paths.Add($fullPath.Substring(
                            ([string]$View.ProjectRoot).Length + 1
                        ).Replace('\', '/'))
                    }
                }
                finally {
                    $directoryGuard.Handle.Dispose()
                }
            }
        }
    }
    finally {
        $prefixGuard.Handle.Dispose()
    }
    [string[]]$result = $paths.ToArray()
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result
}

function Test-P2RepositoryViewCandidatePath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string[]]$Prefixes
    )

    foreach ($prefix in $Prefixes) {
        if ($RelativePath -ceq $prefix -or $RelativePath.StartsWith(
            $prefix + '/',
            [StringComparison]::Ordinal
        )) {
            return $true
        }
    }
    return $false
}

function Add-P2RepositoryViewCapturedEntry {
    param(
        [Parameter(Mandatory = $true)]
        [Collections.Generic.Dictionary[string, object]]$Entries,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][long]$CapturedByteCount,
        [Parameter(Mandatory = $true)][string]$CaptureKind
    )

    if ($Entries.ContainsKey($RelativePath)) {
        return $CapturedByteCount
    }
    if ($Entries.Count -ge $script:P2RepositoryViewMaxCandidatePaths) {
        throw (
            "P2_REPOSITORY_VIEW_CANDIDATE_COUNT: $CaptureKind capture exceeds " +
            "the $script:P2RepositoryViewMaxCandidatePaths-path limit."
        )
    }
    if ($Bytes.Length -gt $script:P2RepositoryViewMaxFileBytes) {
        throw (
            "P2_REPOSITORY_VIEW_FILE_TOO_LARGE: '$RelativePath' exceeds the " +
            "$script:P2RepositoryViewMaxFileBytes-byte capture limit."
        )
    }
    $newByteCount = $CapturedByteCount + [long]$Bytes.Length
    if ($newByteCount -gt $script:P2RepositoryViewMaxCapturedBytes) {
        throw (
            "P2_REPOSITORY_VIEW_CAPTURE_BYTES: Candidate and baseline bytes " +
            "exceed the $script:P2RepositoryViewMaxCapturedBytes-byte view limit."
        )
    }
    $Entries.Add($RelativePath, $Bytes)
    return $newByteCount
}

function New-P2RepositoryView {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = "",
        [ValidateSet("Repository", "Worktree", "Staged")]
        [string]$Mode = "Repository",
        [string[]]$CandidatePrefixes = @(
            "new-game-project/battle/specs"
        )
    )

    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        $ProjectRoot = Join-Path $PSScriptRoot "..\..\..\..\.."
    }
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $rootResult = Invoke-P2RepositoryViewGit -Root $root `
        -Arguments 'rev-parse --show-toplevel'
    if ($rootResult.ExitCode -ne 0) {
        throw "P2_REPOSITORY_VIEW_ROOT: ProjectRoot is not a readable Git worktree."
    }
    $reportedRoot = (ConvertFrom-P2RepositoryViewUtf8 `
        -Bytes ([byte[]]$rootResult.Bytes) -Context "Git root").Trim()
    $reportedRoot = [IO.Path]::GetFullPath($reportedRoot).TrimEnd('\')
    if (-not $reportedRoot.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw (
            "P2_REPOSITORY_VIEW_ROOT_MISMATCH: Git top-level '$reportedRoot' " +
            "does not equal ProjectRoot '$root'."
        )
    }
    $rootGuard = Open-P2RepositoryViewVerifiedHandle -Path $root `
        -ExpectedKind Directory
    try {
        $rootFinalPath = [string]$rootGuard.FinalPath
    }
    finally {
        $rootGuard.Handle.Dispose()
    }

    if ($null -eq $CandidatePrefixes -or $CandidatePrefixes.Count -eq 0 -or
        $CandidatePrefixes.Count -gt 32) {
        throw "P2_REPOSITORY_VIEW_PREFIXES: CandidatePrefixes requires 1..32 entries."
    }
    $prefixSet = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($prefixValue in $CandidatePrefixes) {
        $prefix = ConvertTo-P2RepositoryViewRelativePath ([string]$prefixValue)
        if (-not $prefixSet.Add($prefix)) {
            throw "P2_REPOSITORY_VIEW_PREFIX_DUPLICATE: '$prefix' is repeated."
        }
    }
    [string[]]$normalizedPrefixes = @($prefixSet)
    [Array]::Sort($normalizedPrefixes, [StringComparer]::Ordinal)

    $headResult = Invoke-P2RepositoryViewGit -Root $root `
        -Arguments 'rev-parse --verify --quiet HEAD'
    $headOid = ""
    if ($headResult.ExitCode -eq 0) {
        $headOid = (ConvertFrom-P2RepositoryViewUtf8 `
            -Bytes ([byte[]]$headResult.Bytes) -Context "HEAD OID").Trim()
        if ($headOid -cnotmatch '^[0-9a-f]{40}([0-9a-f]{24})?$') {
            throw "P2_REPOSITORY_VIEW_HEAD_ID: Git returned an invalid HEAD OID."
        }
    }
    elseif ($headResult.ExitCode -ne 1) {
        throw "P2_REPOSITORY_VIEW_HEAD: HEAD could not be resolved."
    }

    $metadataPathSet = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($prefix in $normalizedPrefixes) {
        $null = $metadataPathSet.Add($prefix)
    }
    if ($Mode -ceq "Staged") {
        foreach ($surfacePath in $script:P2RepositoryViewExecutionSurface) {
            $null = $metadataPathSet.Add($surfacePath)
        }
    }
    [string[]]$metadataPathspecs = @($metadataPathSet)
    [Array]::Sort($metadataPathspecs, [StringComparer]::Ordinal)
    $headEntries = Get-P2RepositoryViewHeadEntries -Root $root `
        -HeadOid $headOid -Pathspecs $metadataPathspecs
    $indexEntries = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    if ($Mode -ceq "Staged") {
        $indexEntries = Get-P2RepositoryViewIndexEntries -Root $root `
            -Pathspecs $metadataPathspecs
    }
    $candidateEntries = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    $baselineEntries = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::Ordinal
    )
    $view = [pscustomobject][ordered]@{
        ViewKind = "P2_REPOSITORY_VIEW"
        ProjectRoot = $root
        RootFinalPath = $rootFinalPath
        Mode = $Mode
        HeadOid = $headOid
        HeadEntries = $headEntries
        IndexEntries = $indexEntries
        CandidatePrefixes = $normalizedPrefixes
        CandidateEntries = $candidateEntries
        BaselineEntries = $baselineEntries
        CapturedByteCount = 0L
    }
    $capturedByteCount = 0L
    if ($Mode -ceq "Staged") {
        [string[]]$stagedCandidatePaths = @($indexEntries.Keys | Where-Object {
            Test-P2RepositoryViewCandidatePath -RelativePath ([string]$_) `
                -Prefixes $normalizedPrefixes
        })
        [Array]::Sort($stagedCandidatePaths, [StringComparer]::Ordinal)
        if ($stagedCandidatePaths.Count -gt
            $script:P2RepositoryViewMaxCandidatePaths) {
            throw (
                "P2_REPOSITORY_VIEW_CANDIDATE_COUNT: Staged candidate capture " +
                "exceeds the $script:P2RepositoryViewMaxCandidatePaths-path limit."
            )
        }
        foreach ($relativePath in $stagedCandidatePaths) {
            $entry = $indexEntries[$relativePath]
            $bytes = Get-P2RepositoryViewGitBlobBytes -View $view `
                -BlobOid ([string]$entry.BlobOid) -RemainingCaptureBytes (
                    $script:P2RepositoryViewMaxCapturedBytes - $capturedByteCount
                )
            $capturedByteCount = Add-P2RepositoryViewCapturedEntry `
                -Entries $candidateEntries -RelativePath $relativePath `
                -Bytes $bytes -CapturedByteCount $capturedByteCount `
                -CaptureKind "Staged candidate"
        }
    }
    else {
        foreach ($prefix in $normalizedPrefixes) {
            $remainingPaths = $script:P2RepositoryViewMaxCandidatePaths -
                $candidateEntries.Count
            if ($remainingPaths -le 0) {
                throw (
                    "P2_REPOSITORY_VIEW_CANDIDATE_COUNT: Candidate capture " +
                    "exceeds the $script:P2RepositoryViewMaxCandidatePaths-path limit."
                )
            }
            foreach ($relativePath in @(Get-P2RepositoryViewWorktreePaths `
                -View $view -Prefix $prefix -MaxPaths $remainingPaths)) {
                if ($candidateEntries.ContainsKey([string]$relativePath)) {
                    continue
                }
                $fullPath = Get-P2RepositoryViewContainedPath -View $view `
                    -RelativePath ([string]$relativePath)
                try {
                    $bytes = Read-P2RepositoryViewBoundedFileBytes `
                        -View $view -RelativePath ([string]$relativePath) `
                        -RemainingCaptureBytes (
                            $script:P2RepositoryViewMaxCapturedBytes -
                            $capturedByteCount
                        )
                    $capturedByteCount = Add-P2RepositoryViewCapturedEntry `
                        -Entries $candidateEntries `
                        -RelativePath ([string]$relativePath) -Bytes $bytes `
                        -CapturedByteCount $capturedByteCount `
                        -CaptureKind "$Mode candidate"
                }
                catch {
                    if ([string]$_.Exception.Message -cmatch
                        '^P2_REPOSITORY_VIEW_') {
                        throw
                    }
                    throw (
                        "P2_REPOSITORY_VIEW_SNAPSHOT_READ: '$relativePath' " +
                        "could not be captured."
                    )
                }
            }
        }
    }
    if ($Mode -cne "Repository") {
        [string[]]$baselinePaths = @($headEntries.Keys | Where-Object {
            Test-P2RepositoryViewCandidatePath -RelativePath ([string]$_) `
                -Prefixes $normalizedPrefixes
        })
        [Array]::Sort($baselinePaths, [StringComparer]::Ordinal)
        if ($baselinePaths.Count -gt $script:P2RepositoryViewMaxCandidatePaths) {
            throw (
                "P2_REPOSITORY_VIEW_CANDIDATE_COUNT: $Mode baseline capture " +
                "exceeds the $script:P2RepositoryViewMaxCandidatePaths-path limit."
            )
        }
        foreach ($relativePath in $baselinePaths) {
            $entry = $headEntries[$relativePath]
            if ([string]$entry.ObjectType -cne "blob" -or
                [string]$entry.Mode -cnotin @("100644", "100755")) {
                throw (
                    "P2_REPOSITORY_VIEW_BASELINE_MODE: '$relativePath' is " +
                    "not a regular HEAD blob."
                )
            }
            $bytes = Get-P2RepositoryViewGitBlobBytes -View $view `
                -BlobOid ([string]$entry.BlobOid) -RemainingCaptureBytes (
                    $script:P2RepositoryViewMaxCapturedBytes - $capturedByteCount
                )
            $capturedByteCount = Add-P2RepositoryViewCapturedEntry `
                -Entries $baselineEntries -RelativePath $relativePath `
                -Bytes $bytes -CapturedByteCount $capturedByteCount `
                -CaptureKind "$Mode baseline"
        }
    }
    $view.CapturedByteCount = $capturedByteCount
    if ($Mode -ceq "Staged") {
        Assert-P2RepositoryViewExecutionSurfaceParity -View $view
    }
    return $view
}

function Get-P2RepositoryViewBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [switch]$AllowMissing
    )

    Assert-P2RepositoryViewObject $View
    $relative = ConvertTo-P2RepositoryViewRelativePath $RelativePath
    if (-not $View.CandidateEntries.ContainsKey($relative)) {
        if ($AllowMissing) {
            return $null
        }
        throw "P2_REPOSITORY_VIEW_NOT_FOUND: '$relative' is absent from the captured view."
    }
    return ,([byte[]]$View.CandidateEntries[$relative].Clone())
}

function Get-P2RepositoryViewBaselineBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [switch]$AllowMissing
    )

    Assert-P2RepositoryViewObject $View
    $relative = ConvertTo-P2RepositoryViewRelativePath $RelativePath
    if ([string]$View.Mode -ceq "Repository") {
        if ($AllowMissing) {
            return $null
        }
        throw "P2_REPOSITORY_VIEW_NO_BASELINE: Repository mode has no baseline."
    }
    if (-not $View.BaselineEntries.ContainsKey($relative)) {
        if ($AllowMissing) {
            return $null
        }
        throw "P2_REPOSITORY_VIEW_BASELINE_NOT_FOUND: '$relative' is absent from captured HEAD."
    }
    return ,([byte[]]$View.BaselineEntries[$relative].Clone())
}

function Get-P2RepositoryViewPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$View,
        [string]$Prefix = ""
    )

    Assert-P2RepositoryViewObject $View
    $normalizedPrefix = ConvertTo-P2RepositoryViewRelativePath `
        -Path $Prefix -AllowEmpty
    [string[]]$result = @($View.CandidateEntries.Keys | Where-Object {
        [string]::IsNullOrEmpty($normalizedPrefix) -or
        [string]$_ -ceq $normalizedPrefix -or
        ([string]$_).StartsWith(
            $normalizedPrefix + '/',
            [StringComparison]::Ordinal
        )
    })
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result
}
