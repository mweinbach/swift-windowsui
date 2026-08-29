# Windows-only recovery for the final, sealed audit-directory rename. No SDK,
# source parsing, input-validation, copy fallback, or permission changes run here.

function New-SwiftUIAuditPublicationOwnership {
    param([string]$StagingPath, [string]$OutputPath, [string]$OutputParent, [string]$StagingLeaf)

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return $null }
    if ($null -eq ('SwiftUIAudit.PublicationDirectoryIdentity' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace SwiftUIAudit {
    public sealed class PublicationDirectoryIdentity : IDisposable {
        [StructLayout(LayoutKind.Sequential)]
        private struct Information {
            public uint Attributes, CreationLow, CreationHigh, AccessLow, AccessHigh;
            public uint WriteLow, WriteHigh, Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct FileIdentity { public ulong Volume, Low, High; }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(string path, uint access, uint share,
            IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle file, out Information info);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandleEx(SafeFileHandle file, int infoClass,
            out FileIdentity info, uint size);
        private readonly SafeFileHandle handle;
        private readonly FileIdentity identity;
        private PublicationDirectoryIdentity(SafeFileHandle handle, FileIdentity identity) {
            this.handle = handle; this.identity = identity;
        }
        public static PublicationDirectoryIdentity Open(string path) {
            // FILE_READ_ATTRIBUTES; share read/write/delete; OPEN_EXISTING;
            // BACKUP_SEMANTICS | OPEN_REPARSE_POINT. The pin permits the rename.
            SafeFileHandle handle = CreateFileW(path, 0x80, 7, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero);
            try {
                if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
                Information info;
                if (!GetFileInformationByHandle(handle, out info))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                if ((info.Attributes & 0x10) == 0 || (info.Attributes & 0x400) != 0)
                    throw new IOException("Publication identity requires an ordinary directory.");
                FileIdentity identity;
                // FileIdInfo supplies the full 128-bit ID, including on ReFS.
                if (!GetFileInformationByHandleEx(handle, 18, out identity, 24))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                return new PublicationDirectoryIdentity(handle, identity);
            } catch { handle.Dispose(); throw; }
        }
        public void AssertCurrent(string path) {
            if (handle.IsClosed || handle.IsInvalid) throw new IOException("Publication ownership pin is closed.");
            using (PublicationDirectoryIdentity current = Open(path)) {
                if (identity.Volume != current.identity.Volume || identity.High != current.identity.High ||
                    identity.Low != current.identity.Low)
                    throw new IOException("Publication directory identity changed.");
            }
        }
        public void Dispose() { handle.Dispose(); }
    }
}
'@
    }
    $ownership = [pscustomobject]@{
        StagingPath = $StagingPath; OutputPath = $OutputPath; OutputParent = $OutputParent; StagingLeaf = $StagingLeaf
        ParentIdentity = $null; StagingIdentity = $null
    }
    try {
        Assert-SwiftUIAuditPublicationPaths -Ownership $ownership
        $ownership.ParentIdentity = [SwiftUIAudit.PublicationDirectoryIdentity]::Open($OutputParent)
        $ownership.StagingIdentity = [SwiftUIAudit.PublicationDirectoryIdentity]::Open($StagingPath)
        return $ownership
    } catch {
        $identityFailure = $_
        if ($null -ne $ownership.StagingIdentity) { $ownership.StagingIdentity.Dispose() }
        if ($null -ne $ownership.ParentIdentity) { $ownership.ParentIdentity.Dispose() }
        # An unavailable Windows identity query cannot enable recovery, but it
        # must not prevent the original single-attempt publication path.
        if ($identityFailure.Exception.GetBaseException() -is [ComponentModel.Win32Exception]) { return $null }
        throw
    }
}

function Assert-SwiftUIAuditPublicationPaths {
    param([Parameter(Mandatory)]$Ownership)

    if ($Ownership.StagingLeaf -cnotmatch '\A\.swiftui-api-audit-[0-9a-f]{32}\z') { throw 'Invalid publication staging identity.' }
    foreach ($path in @($Ownership.StagingPath, $Ownership.OutputPath, $Ownership.OutputParent)) {
        if ($path.Length -gt 32768 -or [IO.Path]::GetFullPath($path) -cne $path -or
            (Resolve-SwiftUIBaselineFileSystemPath -Path $path) -cne $path) {
            throw 'Publication paths must be canonical and must not traverse filesystem aliases.'
        }
    }
    if ([IO.Path]::GetDirectoryName($Ownership.StagingPath) -cne $Ownership.OutputParent -or
        [IO.Path]::GetDirectoryName($Ownership.OutputPath) -cne $Ownership.OutputParent -or
        [IO.Path]::GetFileName($Ownership.StagingPath) -cne $Ownership.StagingLeaf -or
        $Ownership.StagingPath.Equals($Ownership.OutputPath, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($Ownership.OutputPath) -match '[ .]$') {
        throw 'Publication requires distinct ordinary sibling paths in the owned parent.'
    }
    for ($ancestor = $Ownership.StagingPath; -not [string]::IsNullOrEmpty($ancestor); $ancestor = [IO.Path]::GetDirectoryName($ancestor)) {
        $attributes = [IO.File]::GetAttributes($ancestor)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ($attributes -band [IO.FileAttributes]::Directory) -eq 0) {
            throw 'Publication paths must contain only ordinary directory ancestors.'
        }
    }
}

function Assert-SwiftUIAuditPublicationOwnership {
    param([Parameter(Mandatory)]$Ownership)
    Assert-SwiftUIAuditPublicationPaths -Ownership $Ownership
    $Ownership.ParentIdentity.AssertCurrent($Ownership.OutputParent)
    $Ownership.StagingIdentity.AssertCurrent($Ownership.StagingPath)
}

function Assert-SwiftUIAuditPublicationRetry {
    param([Parameter(Mandatory)]$Ownership, [Parameter(Mandatory)][string]$ManifestSha256)

    Assert-SwiftUIAuditPublicationOwnership -Ownership $Ownership
    if ($ManifestSha256 -cnotmatch '\A[0-9a-f]{64}\z') { throw 'Invalid sealed audit manifest digest.' }
    foreach ($name in @('audit.json', 'audit.sha256')) {
        $path = Join-Path $Ownership.StagingPath $name
        $attributes = [IO.File]::GetAttributes($path)
        if (($attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Directory)) -ne 0) {
            throw 'Publication seal files must be ordinary files.'
        }
        $stream = $null; $algorithm = $null
        try {
            # Deny writers while checking the seal. Dispose before Directory.Move.
            $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            if ($name -ceq 'audit.json') {
                $algorithm = [Security.Cryptography.SHA256]::Create()
                $actual = ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
                if ($actual -cne $ManifestSha256) { throw 'Sealed audit manifest changed before publication retry.' }
            } else {
                $expected = [Text.Encoding]::UTF8.GetBytes($ManifestSha256 + '  audit.json' + [char]10)
                if ($stream.Length -ne $expected.Length) { throw 'Audit manifest seal changed before publication retry.' }
                foreach ($value in $expected) {
                    if ($stream.ReadByte() -ne $value) { throw 'Audit manifest seal changed before publication retry.' }
                }
            }
        } finally {
            if ($null -ne $algorithm) { $algorithm.Dispose() }
            if ($null -ne $stream) { $stream.Dispose() }
        }
    }
    $destination = Get-SwiftUIAuditPublicationPathFacts -Path $Ownership.OutputPath
    $chain = @($destination.attributeReadError.exceptions)
    if ($destination.fileExists -or $destination.directoryExists -or $null -ne $destination.attributes -or
        $null -eq $destination.attributeReadError -or $destination.attributeReadError.exceptionChainTruncated -or
        $chain.Count -eq 0 -or $chain[-1].type -cne 'System.IO.FileNotFoundException' -or
        $chain[-1].hresultHex -cne '0x80070002') {
        throw 'Publication retry requires an attribute-confirmed absent destination.'
    }
    Assert-SwiftUIAuditPublicationOwnership -Ownership $Ownership
}

function Test-SwiftUIAuditPublicationRetryableError {
    param([Parameter(Mandatory)][Management.Automation.ErrorRecord]$ErrorRecord)
    $facts = Get-SwiftUIAuditPublicationExceptionFacts -Exception $ErrorRecord.Exception
    $chain = @($facts.chain)
    if ($facts.truncated -or $chain.Count -eq 0) { return $false }
    # Only unwrap PowerShell's reflection wrapper. An unknown outer IOException
    # is not made retryable by a differently classified inner exception.
    for ($index = 0; $index -lt $chain.Count - 1; $index++) {
        if ($chain[$index].type -cne 'System.Management.Automation.MethodInvocationException') { return $false }
    }
    return ($chain[-1].type -cin @('System.IO.IOException', 'System.UnauthorizedAccessException') -and
        $chain[-1].hresultHex -cin @('0x80070005', '0x80070020'))
}

function Complete-SwiftUIAuditPublicationAfterFailure {
    param(
        [AllowNull()]$Ownership,
        [Parameter(Mandatory)][Management.Automation.ErrorRecord]$OriginalError,
        [Parameter(Mandatory)][string]$FirstDiagnosticPath,
        [Parameter(Mandatory)][string]$ManifestSha256
    )

    $originalFacts = Get-SwiftUIAuditPublicationExceptionFacts -Exception $OriginalError.Exception
    $result = [ordered]@{ published = $false; attempts = 1; recovered = $false
        failedAttemptDiagnostics = @($FirstDiagnosticPath); retryDelaysMilliseconds = @()
        failedAttempts = @([ordered]@{ attemptNumber = 1; exceptions = $originalFacts.chain; exceptionChainTruncated = $originalFacts.truncated })
        stopReason = 'unsupported-ownership'; validationError = $null; outcomeDiagnostic = $null; outcomeDiagnosticError = $null }
    if ($null -eq $Ownership) { return [pscustomobject]$result }
    $lastError = $OriginalError
    foreach ($delay in @(25, 100)) {
        if (-not (Test-SwiftUIAuditPublicationRetryableError -ErrorRecord $lastError)) {
            $result.stopReason = 'non-retryable-error'; break
        }
        $result.retryDelaysMilliseconds += $delay
        Start-Sleep -Milliseconds $delay
        try { Assert-SwiftUIAuditPublicationRetry -Ownership $Ownership -ManifestSha256 $ManifestSha256 }
        catch {
            $result.stopReason = 'retry-validation-failed'
            $result.validationError = Get-SwiftUIAuditPublicationExceptionFacts -Exception $_.Exception
            break
        }
        $attemptedAt = [DateTime]::UtcNow.ToString('o')
        $result.attempts++
        try {
            [IO.Directory]::Move($Ownership.StagingPath, $Ownership.OutputPath)
            $result.published = $true; $result.recovered = $true; $result.stopReason = 'recovered'
            break
        } catch {
            $lastError = $_
            $facts = Get-SwiftUIAuditPublicationExceptionFacts -Exception $lastError.Exception
            $result.failedAttempts += [ordered]@{ attemptNumber = $result.attempts
                exceptions = $facts.chain; exceptionChainTruncated = $facts.truncated }
            try {
                $diagnostic = Write-SwiftUIAuditPublicationFailureDiagnostic -ErrorRecord $lastError `
                    -StagingPath $Ownership.StagingPath -OutputPath $Ownership.OutputPath -OutputParent $Ownership.OutputParent `
                    -StagingLeaf $Ownership.StagingLeaf -ManifestSha256 $ManifestSha256 -AttemptedAtUTC $attemptedAt `
                    -AttemptNumber $result.attempts
                $result.failedAttemptDiagnostics += $diagnostic
            } catch {
                $result.stopReason = 'failed-attempt-diagnostic-unavailable'
                $result.validationError = Get-SwiftUIAuditPublicationExceptionFacts -Exception $_.Exception
                break
            }
            $result.stopReason = 'attempt-limit'
        }
    }
    try {
        $Ownership.ParentIdentity.AssertCurrent($Ownership.OutputParent)
        $result.outcomeDiagnostic = Write-SwiftUIAuditPublicationRecoveryDiagnostic -Ownership $Ownership `
            -ManifestSha256 $ManifestSha256 -Result $result
    } catch {
        # A rename already completed cannot be undone by a receipt failure.
        $result.outcomeDiagnosticError = Get-SwiftUIAuditPublicationExceptionFacts -Exception $_.Exception
    }
    return [pscustomobject]$result
}
