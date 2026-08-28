<#
.SYNOPSIS
    Collects optional, bounded bitmap font observations for two fixed fixtures.
.DESCRIPTION
    Dot-source this file. Nothing is probed, compiled, opened, or written until
    a function is called. The native file adapter is lazy and replaceable in
    synthetic tests; it never reuses the unrestricted provenance file hasher.
#>
param()

$script:bitmapFontMetadataStatuses = @('observed', 'partial', 'unavailable', 'failed', 'limit-exceeded', 'invalid-value', 'not-in-system-collection', 'nonlocal-or-custom', 'not-approved', 'not-implemented')
$script:bitmapFontFixtureRoles = @{
    'symbol-palette' = @('sparkle', 'bolt', 'heart', 'star', 'folder', 'chart', 'globe', 'checkmark')
    'stepper' = @('increment', 'decrement')
}

function Resolve-GalleryBitmapPath {
    param([string]$Path)
    $provider = $null; $drive = $null
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref]$provider, [ref]$drive)
    if ($provider.Name -cne 'FileSystem') { throw 'bitmap-path-not-filesystem' }
    [IO.Path]::GetFullPath($resolved)
}

function Assert-GalleryBitmapFontAttributionOptions {
    param([string[]]$EntryIds, [bool]$ExplicitEntries, [bool]$SkipRender, [bool]$UpdateBaselines, [bool]$List, [string]$WorkDir)
    if (-not $ExplicitEntries -or $EntryIds.Count -lt 1 -or $EntryIds.Count -gt 2) { throw '-BitmapFontAttribution requires explicit -Entries symbol-palette,stepper (or one of those fixtures).' }
    foreach ($id in $EntryIds) {
        if ($script:bitmapFontFixtureRoles.Keys -cnotcontains $id) { throw '-BitmapFontAttribution supports only symbol-palette and stepper.' }
    }
    if (@($EntryIds | Select-Object -Unique).Count -ne $EntryIds.Count) { throw 'Duplicate bitmap attribution fixtures are not allowed.' }
    if ($SkipRender -or $UpdateBaselines -or $List) { throw '-BitmapFontAttribution cannot be combined with -SkipRender, -UpdateBaselines, or -List.' }
    $path = Resolve-GalleryBitmapPath $WorkDir
    if (Test-Path -LiteralPath $path) { throw '-BitmapFontAttribution requires a new, nonexisting -WorkDir.' }
}

function New-GalleryBitmapFontAttributionInvocation {
    param([string]$WorkDir, [string[]]$EntryIds, [string]$InvocationID, [ValidateSet(1, 2)][int]$Version = 1)
    Assert-GalleryBitmapFontAttributionOptions -EntryIds $EntryIds -ExplicitEntries $true -SkipRender $false -UpdateBaselines $false -List $false -WorkDir $WorkDir
    if ($InvocationID -cnotmatch '^[0-9a-f]{32}$') { throw 'bitmap-invalid-invocation' }
    $root = Resolve-GalleryBitmapPath $WorkDir
    # Native code owns creation of the native directory. It must not already
    # exist when the paired CLI options are passed to the gallery executable.
    [void][IO.Directory]::CreateDirectory($root)
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'bitmap-font-attribution'))
    $invocation = [pscustomobject]@{
        invocationID = $InvocationID
        entries = @($EntryIds)
        workDirectory = $root
        currentDirectory = Join-Path $root 'current'
        nativeDirectory = Join-Path $root 'bitmap-font-attribution/native'
        reportPath = Join-Path $root 'bitmap-font-attribution/report.json'
        startedAtUtc = [DateTime]::UtcNow
    }
    # Absence retains the exact V1 invocation shape. Only an explicit V2
    # selection may choose the separate V2 reader; sidecar content never does.
    if ($Version -eq 2) { $invocation | Add-Member NoteProperty nativeSchemaVersion 2 }
    $invocation
}

function Test-GalleryBitmapSafeFontBasename {
    param($Value)
    if ($Value -isnot [string] -or $Value.Length -lt 5 -or $Value.Length -gt 255) { return $false }
    if ($Value -match '[\x00-\x1f\x7f-\x9f<>:"/\\|?*~]' -or $Value.Contains('..') -or $Value -match '[ .]$') { return $false }
    if ($Value.Split('.')[0].EndsWith(' ') -or $Value -match '^(?i:CON|PRN|AUX|NUL|CLOCK\$|CONIN\$|CONOUT\$|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])(?:\.|$)' -or $Value -notmatch '(?i)\.(ttf|otf|ttc)$') { return $false }
    for ($i = 0; $i -lt $Value.Length; $i++) {
        if ([char]::IsSurrogate($Value[$i])) {
            if (-not [char]::IsHighSurrogate($Value[$i]) -or $i + 1 -ge $Value.Length -or -not [char]::IsLowSurrogate($Value[$i + 1])) { return $false }
            $i++
        }
    }
    $true
}

function Initialize-GalleryBitmapFontFileAdapter {
    if ('SwiftWindowsUIBitmapFontFileAdapterV1' -as [type]) { return }
    # SOURCE ONLY in synthetic tests. The final path, 128-bit file identity,
    # hash and name-ID-5 parser use the same handle. FileStream buffer size 1
    # disables read-ahead; every requested byte is charged before another read.
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

public static class SwiftWindowsUIBitmapFontFileAdapterV1 {
    private const uint GENERIC_READ = 0x80000000, FILE_READ_ATTRIBUTES = 0x80;
    private const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, OPEN_EXISTING = 3;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000, FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
    private const uint FILE_ATTRIBUTE_DIRECTORY = 0x10, FILE_ATTRIBUTE_REPARSE_POINT = 0x400;
    private const int FileIdInfo = 18;
    private const long PerFileLimit = 128L * 1024 * 1024, TotalLimit = 512L * 1024 * 1024;
    [StructLayout(LayoutKind.Sequential)] private struct FileTime { public uint Low, High; }
    [StructLayout(LayoutKind.Sequential)] private struct HandleInfo {
        public uint Attributes; public FileTime Creation, Access, Write;
        public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [StructLayout(LayoutKind.Sequential)] private struct FileIdentity { public ulong Volume, Low, High; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(SafeFileHandle file, StringBuilder path, uint size, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle file, out HandleInfo info);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandleEx(SafeFileHandle file, int kind, out FileIdentity info, uint size);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern uint GetFileType(SafeFileHandle file);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern uint GetDriveTypeW(string root);
    public sealed class Result {
        public string Status = "unavailable", Sha256, LastWriteTimeUtc, FileVersion, Error;
        public long? Length;
        public string[] EmbeddedVersions = new string[0];
        public string VersionStatus = "unknown", VersionError = "not-observed";
        public long BytesRead;
        public bool Stable;
        public string Validation = "not-validated";
    }
    private sealed class BoundFailure : Exception { public readonly string Code; public BoundFailure(string code) { Code = code; } }
    private sealed class Reader {
        internal readonly FileStream Stream; internal readonly Result Result; internal readonly long Budget;
        internal Reader(FileStream stream, Result result, long budget) { Stream = stream; Result = result; Budget = budget; }
        internal int Read(byte[] buffer, int offset, int count) {
            if (count < 0 || count > Budget - Result.BytesRead) throw new BoundFailure("read-budget-exhausted");
            // An IO exception cannot prove that no bytes reached the OS.
            // Reserve the full request, refund only a successful short read.
            Result.BytesRead += count;
            int read = Stream.Read(buffer, offset, count); Result.BytesRead -= count - read; return read;
        }
        internal byte[] Exact(int count) {
            if (count < 0 || count > 1048576) throw new BoundFailure("invalid-font");
            byte[] data = new byte[count]; int offset = 0;
            while (offset < count) { int read = Read(data, offset, count - offset); if (read == 0) throw new BoundFailure("invalid-font"); offset += read; }
            return data;
        }
    }
    private static bool SafeName(string name) {
        if (String.IsNullOrEmpty(name) || name.Length > 255 || name.Length < 5 || name.Contains("..") || name.IndexOf('~') >= 0) return false;
        if (Regex.IsMatch(name, "[\\x00-\\x1f\\x7f-\\x9f<>:\"/\\\\|?*]") || name.EndsWith(".") || name.EndsWith(" ")) return false;
        if (name.Split('.')[0].EndsWith(" ") || Regex.IsMatch(name, @"^(CON|PRN|AUX|NUL|CLOCK\$|CONIN\$|CONOUT\$|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])(?:\.|$)", RegexOptions.IgnoreCase)) return false;
        string ext = Path.GetExtension(name).ToLowerInvariant();
        if (ext != ".ttf" && ext != ".otf" && ext != ".ttc") return false;
        for (int i = 0; i < name.Length; i++) if (Char.IsSurrogate(name[i])) {
            if (!Char.IsHighSurrogate(name[i]) || i + 1 == name.Length || !Char.IsLowSurrogate(name[++i])) return false;
        }
        return true;
    }
    private static bool LocalPath(string path) {
        if (String.IsNullOrEmpty(path) || path.Length > 1024 || !Regex.IsMatch(path, @"^[A-Za-z]:\\")) return false;
        if (path.Substring(2).IndexOf(':') >= 0 || path.IndexOf('/') >= 0 || path.IndexOf('~') >= 0 || Regex.IsMatch(path, "[\\x00-\\x1f\\x7f-\\x9f]")) return false;
        string[] parts = path.Substring(3).Split('\\');
        foreach (string part in parts) if (part.Length == 0 || part == "." || part == ".." || part.EndsWith(".") || part.EndsWith(" ")) return false;
        return true;
    }
    private static string FinalPath(SafeFileHandle handle) {
        StringBuilder buffer = new StringBuilder(1030);
        uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
        if (length == 0 || length >= buffer.Capacity) throw new BoundFailure("final-path-unavailable");
        string value = buffer.ToString();
        if (!value.StartsWith(@"\\?\", StringComparison.Ordinal)) throw new BoundFailure("path-not-approved");
        value = value.Substring(4);
        if (!LocalPath(value)) throw new BoundFailure("path-not-approved");
        return value;
    }
    private static HandleInfo Info(SafeFileHandle handle) {
        HandleInfo result;
        if (GetFileType(handle) != 1 || !GetFileInformationByHandle(handle, out result)) throw new BoundFailure("metadata-unavailable");
        return result;
    }
    private static FileIdentity Identity(SafeFileHandle handle) {
        FileIdentity result;
        if (!GetFileInformationByHandleEx(handle, FileIdInfo, out result, (uint)Marshal.SizeOf(typeof(FileIdentity)))) throw new BoundFailure("identity-unavailable");
        return result;
    }
    private static List<SafeFileHandle> HoldDirectories(string root) {
        List<SafeFileHandle> handles = new List<SafeFileHandle>();
        try {
            string current = root.Substring(0, 3);
            string[] parts = root.Substring(3).Split('\\');
            if (parts.Length > 64) throw new BoundFailure("path-not-approved");
            foreach (string part in parts) {
                current = Path.Combine(current, part);
                SafeFileHandle handle = CreateFileW(current, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING,
                    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, IntPtr.Zero);
                handles.Add(handle);
                if (handle.IsInvalid) throw new BoundFailure("directory-unavailable");
                HandleInfo info = Info(handle);
                if ((info.Attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 || (info.Attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0 ||
                    !String.Equals(FinalPath(handle), current, StringComparison.OrdinalIgnoreCase)) throw new BoundFailure("path-not-approved");
            }
            return handles;
        } catch { foreach (SafeFileHandle handle in handles) handle.Dispose(); throw; }
    }
    private static ushort U16(byte[] data, int offset) {
        if (offset < 0 || offset > data.Length - 2) throw new BoundFailure("invalid-font");
        return (ushort)((data[offset] << 8) | data[offset + 1]);
    }
    private static uint U32(byte[] data, int offset) { return ((uint)U16(data, offset) << 16) | U16(data, offset + 2); }
    // Same bounded name-ID-5 algorithm as gallery-font-provenance.ps1, with
    // a supplied validated stream, strict UTF-16, and bounded result strings.
    private static string[] ReadFontVersions(Reader reader, long length) {
        reader.Stream.Position = 0;
        byte[] header = reader.Exact(12); uint signature = U32(header, 0);
        if (signature != 0x00010000 && signature != 0x4f54544f) throw new BoundFailure("unsupported-container");
        int tables = U16(header, 4); if (tables > 4096) throw new BoundFailure("invalid-font");
        byte[] directory = reader.Exact(tables * 16);
        for (int i = 0; i < tables; i++) {
            int entry = i * 16; if (U32(directory, entry) != 0x6e616d65) continue;
            uint start = U32(directory, entry + 8), size = U32(directory, entry + 12);
            if (size > 1048576 || (ulong)start + size > (ulong)length) throw new BoundFailure("invalid-font");
            reader.Stream.Position = start; byte[] table = reader.Exact((int)size);
            if (U16(table, 0) > 1) throw new BoundFailure("invalid-font");
            int records = U16(table, 2), storage = U16(table, 4);
            if (records > 4096 || 6 + records * 12 > table.Length || storage < 6 + records * 12 || storage > table.Length) throw new BoundFailure("invalid-font");
            SortedSet<string> versions = new SortedSet<string>(StringComparer.Ordinal);
            for (int n = 0; n < records; n++) {
                int record = 6 + n * 12, platform = U16(table, record), encoding = U16(table, record + 2);
                if ((platform != 0 && platform != 3) || U16(table, record + 6) != 5 || (platform == 3 && encoding != 0 && encoding != 1 && encoding != 10)) continue;
                int bytes = U16(table, record + 8), offset = storage + U16(table, record + 10);
                if (bytes > 1024 || (bytes & 1) != 0 || offset > table.Length - bytes) throw new BoundFailure("invalid-font");
                string value = new UnicodeEncoding(true, false, true).GetString(table, offset, bytes);
                if (value.Length == 0 || Regex.IsMatch(value, "[\\x00-\\x1f\\x7f-\\x9f\\\\/:]")) throw new BoundFailure("invalid-font");
                versions.Add(value); if (versions.Count > 16) throw new BoundFailure("version-limit-exceeded");
            }
            string[] result = new string[versions.Count]; versions.CopyTo(result); return result;
        }
        return new string[0];
    }
    private static bool Same(HandleInfo a, HandleInfo b, FileIdentity ai, FileIdentity bi) {
        return a.Attributes == b.Attributes && a.SizeHigh == b.SizeHigh && a.SizeLow == b.SizeLow && a.Links == b.Links &&
            a.Write.Low == b.Write.Low && a.Write.High == b.Write.High && a.Creation.Low == b.Creation.Low && a.Creation.High == b.Creation.High &&
            ai.Volume == bi.Volume && ai.Low == bi.Low && ai.High == bi.High;
    }
    public static Result Inspect(string scope, string basename, long remainingBytes) {
        Result result = new Result(); List<SafeFileHandle> directories = null;
        try {
            if (Environment.OSVersion.Platform != PlatformID.Win32NT) throw new BoundFailure("windows-required");
            if (!SafeName(basename) || (scope != "system-fonts" && scope != "user-fonts")) throw new BoundFailure("invalid-reference");
            if (remainingBytes < 0 || remainingBytes > TotalLimit) throw new BoundFailure("invalid-budget");
            string root = scope == "system-fonts" ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Fonts") :
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "Windows", "Fonts");
            if (!LocalPath(root) || GetDriveTypeW(Path.GetPathRoot(root)) != 3) throw new BoundFailure("path-not-approved");
            string path = Path.Combine(root, basename);
            if (!LocalPath(path)) throw new BoundFailure("path-not-approved");
            directories = HoldDirectories(root);
            using (SafeFileHandle handle = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, IntPtr.Zero)) {
                if (handle.IsInvalid) { int code = Marshal.GetLastWin32Error(); throw new BoundFailure(code == 2 || code == 3 ? "missing" : "file-open-failed"); }
                HandleInfo before = Info(handle); FileIdentity identityBefore = Identity(handle);
                if ((before.Attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0 ||
                    !String.Equals(FinalPath(handle), path, StringComparison.OrdinalIgnoreCase)) throw new BoundFailure("path-not-approved");
                // Multiple directory entries are not enumerated. Only this
                // validated path and open identity are observed, never a claim
                // that the physical file has no other hard links.
                result.Validation = "same-handle-final-path-and-file-id";
                ulong unsignedLength = ((ulong)before.SizeHigh << 32) | before.SizeLow;
                if (unsignedLength > PerFileLimit) throw new BoundFailure("file-limit-exceeded");
                long length = (long)unsignedLength; result.Length = length;
                if (length > remainingBytes) throw new BoundFailure("total-limit-exceeded");
                result.LastWriteTimeUtc = DateTime.FromFileTimeUtc(((long)before.Write.High << 32) | before.Write.Low).ToString("o");
                using (FileStream stream = new FileStream(handle, FileAccess.Read, 1, false)) {
                    Reader reader = new Reader(stream, result, Math.Min(PerFileLimit, remainingBytes));
                    using (SHA256 hash = SHA256.Create()) {
                        byte[] buffer = new byte[65536]; long left = length;
                        while (left > 0) {
                            int read = reader.Read(buffer, 0, (int)Math.Min(buffer.Length, left));
                            if (read == 0) throw new BoundFailure("file-mutated");
                            hash.TransformBlock(buffer, 0, read, buffer, 0); left -= read;
                        }
                        hash.TransformFinalBlock(new byte[0], 0, 0);
                        result.Sha256 = BitConverter.ToString(hash.Hash).Replace("-", "").ToLowerInvariant();
                    }
                    try {
                        result.EmbeddedVersions = ReadFontVersions(reader, length);
                        result.VersionStatus = result.EmbeddedVersions.Length == 0 ? "unknown" : "observed-embedded-name";
                        result.VersionError = result.EmbeddedVersions.Length == 0 ? "no-name-id-5" : null;
                    } catch (BoundFailure failure) { result.VersionError = failure.Code; }
                      catch { result.VersionError = "invalid-font"; }
                    HandleInfo after = Info(handle); FileIdentity identityAfter = Identity(handle);
                    if (!Same(before, after, identityBefore, identityAfter) || stream.Length != length ||
                        !String.Equals(FinalPath(handle), path, StringComparison.OrdinalIgnoreCase)) throw new BoundFailure("file-mutated");
                    result.Stable = true; result.Status = "observed";
                }
            }
        } catch (BoundFailure failure) {
            result.Error = failure.Code;
            result.Status = failure.Code == "missing" ? "missing" : failure.Code == "file-mutated" ? "mutated" :
                failure.Code == "invalid-reference" || failure.Code == "path-not-approved" ? "not-approved" :
                failure.Code.EndsWith("limit-exceeded") || failure.Code == "read-budget-exhausted" ? "limit-exceeded" : "unavailable";
        } catch { result.Status = "failed"; result.Error = "fingerprint-failed"; }
        finally { if (directories != null) foreach (SafeFileHandle handle in directories) handle.Dispose(); }
        if (result.Status != "observed") { result.Sha256 = null; result.EmbeddedVersions = new string[0]; result.VersionStatus = "unknown"; result.VersionError = "not-observed"; result.Stable = false; }
        return result;
    }
}
'@
}

function Get-GalleryBitmapNativeFileFingerprint {
    param([string]$Scope, [string]$Basename, [long]$RemainingBytes)
    Initialize-GalleryBitmapFontFileAdapter
    [SwiftWindowsUIBitmapFontFileAdapterV1]::Inspect($Scope, $Basename, $RemainingBytes)
}

function Assert-GalleryBitmapJsonLexicalBounds {
    param([string]$Json)
    # PowerShell versions differ in accepting comments, single quotes, trailing
    # commas and duplicate keys. Validate standard JSON grammar first, retaining
    # case-insensitive object key sets (including escaped spellings).
    $stack = New-Object 'System.Collections.Generic.List[object]'
    $root = [pscustomobject]@{ kind = 'root'; state = 'value' }
    $numberPattern = New-Object Text.RegularExpressions.Regex('\G-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?')
    $tokens = 0
    for ($i = 0; $i -lt $Json.Length; $i++) {
        $character = $Json[$i]
        if ([int]$character -in @(32, 9, 10, 13)) { continue }
        $tokens++
        if ($tokens -gt 65536) { throw 'native-json-token-limit' }
        $frame = if ($stack.Count -gt 0) { $stack[$stack.Count - 1] } else { $root }
        if ($frame.state -ceq 'end') { throw 'native-json-invalid' }
        if ($frame.state -ceq 'colon') {
            if ($character -cne ':') { throw 'native-json-invalid' }
            $frame.state = 'value'; continue
        }
        if ($frame.state -ceq 'comma-or-end') {
            if ($character -ceq ',') { $frame.state = if ($frame.kind -ceq 'object') { 'key' } else { 'value' }; continue }
            if (($frame.kind -ceq 'object' -and $character -ceq '}') -or ($frame.kind -ceq 'array' -and $character -ceq ']')) { $stack.RemoveAt($stack.Count - 1); continue }
            throw 'native-json-invalid'
        }
        if (($frame.state -ceq 'key-or-end' -and $character -ceq '}') -or ($frame.state -ceq 'value-or-end' -and $character -ceq ']')) { $stack.RemoveAt($stack.Count - 1); continue }
        $isKey = $frame.state -cin @('key', 'key-or-end')
        if ($isKey -and $character -cne '"') { throw 'native-json-invalid' }
        if ($character -eq '"') {
            $start = $i; $closed = $false
            while (++$i -lt $Json.Length) {
                if ($i - $start -gt 8192) { throw 'native-json-string-limit' }
                if ($Json[$i] -eq '\') {
                    $i++
                    if ($i -ge $Json.Length -or [string]$Json[$i] -cnotin @('"', '\', '/', 'b', 'f', 'n', 'r', 't', 'u')) { throw 'native-json-invalid' }
                    if ($Json[$i] -ceq 'u') {
                        if ($i + 4 -ge $Json.Length -or $Json.Substring($i + 1, 4) -cnotmatch '^[0-9a-fA-F]{4}$') { throw 'native-json-invalid' }
                        $unit = [Convert]::ToInt32($Json.Substring($i + 1, 4), 16); $i += 4
                        if ($unit -ge 0xdc00 -and $unit -le 0xdfff) { throw 'native-json-invalid' }
                        if ($unit -ge 0xd800 -and $unit -le 0xdbff) {
                            if ($i + 6 -ge $Json.Length -or $Json.Substring($i + 1, 2) -cne '\u' -or $Json.Substring($i + 3, 4) -cnotmatch '^[0-9a-fA-F]{4}$') { throw 'native-json-invalid' }
                            $low = [Convert]::ToInt32($Json.Substring($i + 3, 4), 16)
                            if ($low -lt 0xdc00 -or $low -gt 0xdfff) { throw 'native-json-invalid' }
                            $i += 6
                        }
                    }
                    continue
                }
                if ($Json[$i] -eq '"') { $closed = $true; break }
                if ([int]$Json[$i] -lt 32) { throw 'native-json-invalid' }
            }
            if (-not $closed) { throw 'native-json-invalid' }
            if ($isKey) {
                $name = (ConvertFrom-Json ('{"key":' + $Json.Substring($start, $i - $start + 1) + '}')).key
                if ($name.Length -gt 64 -or -not $frame.keys.Add($name)) { throw 'native-json-duplicate-or-long-key' }
                $frame.state = 'colon'; continue
            }
        } elseif ($character -eq '{' -or $character -eq '[') {
            if ($stack.Count -ge 24) { throw 'native-json-depth-limit' }
            $stack.Add([pscustomobject]@{
                kind = if ($character -eq '{') { 'object' } else { 'array' }
                state = if ($character -eq '{') { 'key-or-end' } else { 'value-or-end' }
                keys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            })
        } elseif ($character -ceq '-' -or ([int]$character -ge 48 -and [int]$character -le 57)) {
            $match = $numberPattern.Match($Json, $i)
            if (-not $match.Success -or $match.Index -ne $i -or $match.Length -gt 64) { throw 'native-json-invalid' }
            $i += $match.Length - 1
        } else {
            $literal = $null
            foreach ($candidate in @('true', 'false', 'null')) { if ($Json.Length - $i -ge $candidate.Length -and $Json.Substring($i, $candidate.Length) -ceq $candidate) { $literal = $candidate; break } }
            if ($null -eq $literal) { throw 'native-json-invalid' }
            $i += $literal.Length - 1
        }
        $frame.state = if ($frame.kind -ceq 'root') { 'end' } else { 'comma-or-end' }
    }
    if ($stack.Count -ne 0 -or $root.state -cne 'end') { throw 'native-json-invalid' }
}

function Get-GalleryBitmapOptionalProperty {
    param($Value, [string]$Name)
    $property = $Value.PSObject.Properties[$Name]
    if ($null -ne $property) {
        if ($property.Value -is [array]) { return ,$property.Value }
        $property.Value
    }
}

function Assert-GalleryBitmapObject {
    param($Value, [string[]]$Allowed, [string[]]$Required = @())
    if ($null -eq $Value -or $Value -isnot [pscustomobject]) { throw 'invalid-native-schema' }
    $keys = @($Value.PSObject.Properties.Name)
    foreach ($key in $keys) { if ($Allowed -cnotcontains $key) { throw 'invalid-native-schema' } }
    foreach ($key in $Required) { if ($keys -cnotcontains $key) { throw 'invalid-native-schema' } }
}

function Assert-GalleryBitmapArray {
    param($Value, [int]$Maximum)
    if ($Value -isnot [array] -or $Value.Count -gt $Maximum) { throw 'invalid-native-schema' }
}

function Assert-GalleryBitmapEnum {
    param($Value, [string[]]$Allowed)
    if ($Value -isnot [string] -or $Allowed -cnotcontains $Value) { throw 'invalid-native-schema' }
}

function Assert-GalleryBitmapInteger {
    param($Value, [long]$Maximum, [long]$Minimum = 0)
    if (($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [uint32] -and $Value -isnot [uint64]) -or $Value -lt $Minimum -or $Value -gt $Maximum) { throw 'invalid-native-schema' }
}

function Assert-GalleryBitmapMetadataString {
    param($Value, [int]$Maximum = 512)
    if ($Value -isnot [string] -or $Value.Length -eq 0 -or $Value.Length -gt $Maximum -or $Value -match '[\x00-\x1f\x7f-\x9f\\/:]') { throw 'invalid-native-schema' }
    # Reject malformed surrogate pairs before any JSON writer can replace them.
    for ($i = 0; $i -lt $Value.Length; $i++) {
        if ([char]::IsSurrogate($Value[$i])) {
            if (-not [char]::IsHighSurrogate($Value[$i]) -or $i + 1 -ge $Value.Length -or -not [char]::IsLowSurrogate($Value[$i + 1])) { throw 'invalid-native-schema' }
            $i++
        }
    }
}

function ConvertTo-GalleryBitmapFaceMetadata {
    param($Value)
    $required = @('status', 'namesStatus', 'files', 'filesStatus', 'axesStatus')
    Assert-GalleryBitmapObject $Value ($required + @('familyName', 'faceName', 'faceIndex', 'simulations', 'axes')) $required
    foreach ($name in @('status', 'namesStatus', 'filesStatus', 'axesStatus')) { Assert-GalleryBitmapEnum $Value.$name $script:bitmapFontMetadataStatuses }
    $familyName = Get-GalleryBitmapOptionalProperty $Value 'familyName'
    $faceName = Get-GalleryBitmapOptionalProperty $Value 'faceName'
    $faceIndex = Get-GalleryBitmapOptionalProperty $Value 'faceIndex'
    $simulations = Get-GalleryBitmapOptionalProperty $Value 'simulations'
    $nativeAxes = Get-GalleryBitmapOptionalProperty $Value 'axes'
    foreach ($name in @($familyName, $faceName)) { if ($null -ne $name) { Assert-GalleryBitmapMetadataString $name } }
    foreach ($number in @($faceIndex, $simulations)) { if ($null -ne $number) { Assert-GalleryBitmapInteger $number 4294967295 } }
    if ($Value.namesStatus -ceq 'observed' -and ($null -eq $familyName -or $null -eq $faceName)) { throw 'invalid-native-schema' }
    if ($Value.status -ceq 'observed' -and ($null -eq $faceIndex -or $null -eq $simulations)) { throw 'invalid-native-schema' }
    Assert-GalleryBitmapArray $Value.files 8
    $files = @(foreach ($file in $Value.files) {
        Assert-GalleryBitmapObject $file @('status', 'scope', 'basename') @('status')
        Assert-GalleryBitmapEnum $file.status $script:bitmapFontMetadataStatuses
        $scope = Get-GalleryBitmapOptionalProperty $file 'scope'
        $basename = Get-GalleryBitmapOptionalProperty $file 'basename'
        if ($file.status -ceq 'observed') {
            Assert-GalleryBitmapEnum $scope @('system-fonts', 'user-fonts')
            if (-not (Test-GalleryBitmapSafeFontBasename $basename)) { throw 'invalid-native-schema' }
        } elseif ($null -ne $scope -or $null -ne $basename) { throw 'invalid-native-schema' }
        [pscustomobject][ordered]@{ status = $file.status; scope = $scope; basename = $basename }
    })
    if ($Value.filesStatus -ceq 'observed' -and ($files.Count -eq 0 -or @($files | Where-Object { $_.status -cne 'observed' }).Count -gt 0)) { throw 'invalid-native-schema' }
    $axes = $null
    if ($null -ne $nativeAxes) {
        Assert-GalleryBitmapArray $nativeAxes 32
        if ($Value.axesStatus -cne 'observed') { throw 'invalid-native-schema' }
        $axisTags = @{}
        $axes = @(foreach ($axis in $nativeAxes) {
            Assert-GalleryBitmapObject $axis @('tag', 'value') @('tag', 'value')
            Assert-GalleryBitmapInteger $axis.tag 4294967295
            if (($axis.value -isnot [int] -and $axis.value -isnot [long] -and $axis.value -isnot [double] -and $axis.value -isnot [decimal] -and $axis.value -isnot [float]) -or [double]::IsNaN($axis.value) -or [double]::IsInfinity($axis.value) -or [math]::Abs([double]$axis.value) -gt [float]::MaxValue -or $axisTags.ContainsKey([string]$axis.tag)) { throw 'invalid-native-schema' }
            $axisTags[[string]$axis.tag] = $true
            [pscustomobject][ordered]@{ tag = $axis.tag; value = $axis.value }
        })
    } elseif ($Value.axesStatus -ceq 'observed') { throw 'invalid-native-schema' }
    [pscustomobject][ordered]@{
        status = $Value.status; familyName = $familyName; faceName = $faceName; namesStatus = $Value.namesStatus
        faceIndex = $faceIndex; simulations = $simulations; files = $files; filesStatus = $Value.filesStatus
        axes = $axes; axesStatus = $Value.axesStatus
    }
}

function ConvertTo-GalleryBitmapNativeReport {
    param([string]$Json, [string]$InvocationID, [string]$FixtureID)
    Assert-GalleryBitmapJsonLexicalBounds $Json
    $envelope = ConvertFrom-Json $Json -ErrorAction Stop
    $envelopeKeys = @('schemaVersion', 'invocationID', 'fixtureID', 'status', 'runtime', 'pngFileName', 'report')
    Assert-GalleryBitmapObject $envelope $envelopeKeys $envelopeKeys
    Assert-GalleryBitmapInteger $envelope.schemaVersion 1 1
    if ($InvocationID -cnotmatch '^[0-9a-f]{32}$' -or $envelope.invocationID -isnot [string] -or $envelope.invocationID -cne $InvocationID -or $envelope.fixtureID -isnot [string] -or $envelope.fixtureID -cne $FixtureID -or $script:bitmapFontFixtureRoles.Keys -cnotcontains $FixtureID -or $envelope.pngFileName -isnot [string] -or $envelope.pngFileName -cne "$FixtureID.png") { throw 'native-invocation-mismatch' }
    Assert-GalleryBitmapEnum $envelope.status @('observed', 'partial')
    Assert-GalleryBitmapObject $envelope.runtime @('os', 'architecture') @('os', 'architecture')
    Assert-GalleryBitmapMetadataString $envelope.runtime.os 256
    Assert-GalleryBitmapEnum $envelope.runtime.architecture @('x86_64', 'arm64', 'unknown')
    $report = $envelope.report
    $reportKeys = @('schemaVersion', 'kind', 'scope', 'fixtureID', 'status', 'qualification', 'coverage', 'faces', 'observations', 'limits')
    Assert-GalleryBitmapObject $report $reportKeys $reportKeys
    Assert-GalleryBitmapInteger $report.schemaVersion 1 1
    Assert-GalleryBitmapEnum $report.kind @('native-bitmap-font-attribution')
    Assert-GalleryBitmapEnum $report.scope @('bitmap-icons')
    Assert-GalleryBitmapEnum $report.status @('observed', 'partial')
    Assert-GalleryBitmapEnum $report.qualification @('unqualified')
    if ($report.fixtureID -isnot [string] -or $report.fixtureID -cne $FixtureID -or $envelope.status -cne $report.status) { throw 'invalid-native-schema' }
    $coverageKeys = @('bitmapIcons', 'atlasGlyphs', 'textLayouts', 'sceneReferences')
    Assert-GalleryBitmapObject $report.coverage $coverageKeys $coverageKeys
    Assert-GalleryBitmapEnum $report.coverage.bitmapIcons @('observed', 'partial')
    Assert-GalleryBitmapEnum $report.coverage.sceneReferences @('observed', 'partial')
    Assert-GalleryBitmapEnum $report.coverage.atlasGlyphs @('not-instrumented')
    Assert-GalleryBitmapEnum $report.coverage.textLayouts @('not-instrumented')
    $limitKeys = @('maxFaces', 'maxReceipts', 'maxObservations', 'dropped')
    Assert-GalleryBitmapObject $report.limits $limitKeys $limitKeys
    Assert-GalleryBitmapInteger $report.limits.maxFaces 64 64
    Assert-GalleryBitmapInteger $report.limits.maxReceipts 256 256
    Assert-GalleryBitmapInteger $report.limits.maxObservations 256 256
    Assert-GalleryBitmapInteger $report.limits.dropped 2147483647
    Assert-GalleryBitmapArray $report.faces 64
    $faceIDs = @{}
    $faces = @(foreach ($face in $report.faces) {
        Assert-GalleryBitmapObject $face @('id', 'metadata') @('id', 'metadata')
        if ($face.id -isnot [string] -or $face.id -cnotmatch '^face-(0|[1-9][0-9]?)$' -or $faceIDs.ContainsKey($face.id)) { throw 'invalid-native-schema' }
        $faceIDs[$face.id] = $true
        [pscustomobject][ordered]@{ id = $face.id; metadata = ConvertTo-GalleryBitmapFaceMetadata $face.metadata }
    })
    Assert-GalleryBitmapArray $report.observations 256
    $observations = @(foreach ($observation in $report.observations) {
        $keys = @('role', 'purpose', 'backend', 'outcome', 'faceIDs', 'count')
        Assert-GalleryBitmapObject $observation $keys $keys
        Assert-GalleryBitmapEnum $observation.role $script:bitmapFontFixtureRoles[$FixtureID]
        Assert-GalleryBitmapEnum $observation.purpose @('candidate-probe', 'sentinel-probe', 'display-bitmap')
        Assert-GalleryBitmapEnum $observation.backend @('direct-write', 'gdi', 'vector', 'testing-override', 'unknown')
        Assert-GalleryBitmapEnum $observation.outcome @('draw-produced', 'draw-unavailable', 'bitmap-accepted', 'bitmap-rejected', 'bitmap-cache-hit-known', 'bitmap-cache-hit-unobserved', 'probe-cache-hit', 'scene-referenced', 'not-referenced', 'scene-association-unobserved', 'vector-selected', 'limit-exceeded', 'testing-override')
        Assert-GalleryBitmapInteger $observation.count 2147483647 1
        Assert-GalleryBitmapArray $observation.faceIDs 64
        $seen = @{}
        foreach ($id in $observation.faceIDs) {
            if ($id -isnot [string] -or -not $faceIDs.ContainsKey($id) -or $seen.ContainsKey($id) -or $observation.backend -cne 'direct-write') { throw 'invalid-native-schema' }
            $seen[$id] = $true
        }
        if ($observation.purpose -cne 'display-bitmap' -and $observation.outcome -cin @('bitmap-accepted', 'bitmap-cache-hit-known', 'scene-referenced', 'not-referenced', 'scene-association-unobserved', 'vector-selected')) { throw 'invalid-native-schema' }
        if ($observation.outcome -cin @('bitmap-cache-hit-unobserved', 'probe-cache-hit', 'vector-selected', 'testing-override') -and $observation.faceIDs.Count -gt 0) { throw 'invalid-native-schema' }
        [pscustomobject][ordered]@{
            role = $observation.role; purpose = $observation.purpose; backend = $observation.backend; outcome = $observation.outcome
            faceIDs = @($observation.faceIDs | Sort-Object); count = $observation.count
        }
    })
    [pscustomobject][ordered]@{
        schemaVersion = 1; invocationID = $InvocationID; fixtureID = $FixtureID; status = $report.status
        runtime = [ordered]@{ os = $envelope.runtime.os; architecture = $envelope.runtime.architecture }
        pngFileName = "$FixtureID.png"
        report = [ordered]@{
            schemaVersion = 1; kind = 'native-bitmap-font-attribution'; scope = 'bitmap-icons'; fixtureID = $FixtureID; status = $report.status; qualification = 'unqualified'
            coverage = [ordered]@{ bitmapIcons = $report.coverage.bitmapIcons; atlasGlyphs = 'not-instrumented'; textLayouts = 'not-instrumented'; sceneReferences = $report.coverage.sceneReferences }
            faces = $faces; observations = $observations
            limits = [ordered]@{ maxFaces = 64; maxReceipts = 256; maxObservations = 256; dropped = $report.limits.dropped }
        }
    }
}

function Assert-GalleryBitmapUInt64V2 {
    param($Value)
    # PowerShell 7 represents JSON integers beyond Int64 as BigInteger;
    # Windows PowerShell 5 uses exact Decimal values with scale zero. Reject
    # fractional Decimal and all Double/Float values without rounding them.
    $exactLargeDecimal = $Value -is [decimal] -and $Value -gt [decimal][long]::MaxValue -and
        (([decimal]::GetBits($Value)[3] -shr 16) -band 255) -eq 0
    if ($null -eq $Value -or ($Value -isnot [int] -and $Value -isnot [long] -and
        $Value -isnot [uint32] -and $Value -isnot [uint64] -and
        $Value.GetType().FullName -cne 'System.Numerics.BigInteger' -and -not $exactLargeDecimal)) { throw 'invalid-native-schema-v2' }
    [uint64]$parsed = 0
    if (-not [uint64]::TryParse($Value.ToString([Globalization.CultureInfo]::InvariantCulture),
        [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { throw 'invalid-native-schema-v2' }
}

function Assert-GalleryBitmapAxisTagV2 {
    param($Value)
    Assert-GalleryBitmapInteger $Value 4294967295
    # DirectWrite's tag packs the first OpenType ASCII character in the low
    # byte. Unknown registered/private tags are allowed; invalid spelling is not.
    $trailingSpace = $false
    for ($i = 0; $i -lt 4; $i++) {
        $unit = ([long]$Value -shr (8 * $i)) -band 255
        $letter = ($unit -ge 65 -and $unit -le 90) -or ($unit -ge 97 -and $unit -le 122)
        if ($i -eq 0 -and -not $letter) { throw 'invalid-native-schema-v2' }
        if ($unit -eq 32) { $trailingSpace = $true }
        elseif ($trailingSpace -or (-not $letter -and ($unit -lt 48 -or $unit -gt 57))) { throw 'invalid-native-schema-v2' }
    }
}

function ConvertTo-GalleryBitmapFaceEvidenceV2 {
    param($Value)
    $required = @('axesStatus', 'files', 'filesStatus')
    Assert-GalleryBitmapObject $Value ($required + @('faceType', 'axes', 'hasVariations')) $required
    Assert-GalleryBitmapEnum $Value.axesStatus $script:bitmapFontMetadataStatuses
    Assert-GalleryBitmapEnum $Value.filesStatus $script:bitmapFontMetadataStatuses
    $faceType = Get-GalleryBitmapOptionalProperty $Value 'faceType'
    $nativeAxes = Get-GalleryBitmapOptionalProperty $Value 'axes'
    $hasVariations = Get-GalleryBitmapOptionalProperty $Value 'hasVariations'
    if ($null -ne $faceType) { Assert-GalleryBitmapInteger $faceType 4294967295 }
    if ($null -ne $hasVariations -and $hasVariations -isnot [bool]) { throw 'invalid-native-schema-v2' }
    $axes = $null
    if ($null -ne $nativeAxes) {
        Assert-GalleryBitmapArray $nativeAxes 32
        if ($Value.axesStatus -cne 'observed' -or $null -eq $hasVariations) { throw 'invalid-native-schema-v2' }
        $axisTags = @{}
        $axes = @(foreach ($axis in $nativeAxes) {
            Assert-GalleryBitmapObject $axis @('tag', 'value') @('tag', 'value')
            Assert-GalleryBitmapAxisTagV2 $axis.tag
            if (($axis.value -isnot [int] -and $axis.value -isnot [long] -and $axis.value -isnot [double] -and $axis.value -isnot [decimal] -and $axis.value -isnot [float]) -or
                [double]::IsNaN($axis.value) -or [double]::IsInfinity($axis.value) -or [math]::Abs([double]$axis.value) -gt [float]::MaxValue -or
                $axisTags.ContainsKey([string]$axis.tag)) { throw 'invalid-native-schema-v2' }
            $axisTags[[string]$axis.tag] = $true
            [pscustomobject][ordered]@{ tag = $axis.tag; value = $axis.value }
        })
    } elseif ($Value.axesStatus -ceq 'observed') { throw 'invalid-native-schema-v2' }
    Assert-GalleryBitmapArray $Value.files 8
    $fileIndices = @{}
    $operations = @('not-started', 'get-files', 'get-reference-key', 'get-loader', 'query-local-loader', 'get-local-path',
        'validate-local-path', 'open-local-file', 'verify-local-file', 'create-stream', 'get-stream-size', 'check-byte-budget',
        'initialize-sha256', 'read-stream-fragment', 'hash-stream-fragment', 'finish-sha256', 'verify-local-file-after', 'complete')
    $preSizeOperations = @('not-started', 'get-files', 'get-reference-key', 'get-loader', 'query-local-loader', 'get-local-path',
        'validate-local-path', 'open-local-file', 'verify-local-file', 'create-stream')
    $files = @(foreach ($file in $Value.files) {
        $fileRequired = @('index', 'reference', 'status', 'operation', 'codeDomain', 'requestedBytes', 'readBytes', 'observationKind', 'loadedBytesDigest')
        Assert-GalleryBitmapObject $file ($fileRequired + @('code', 'streamLength', 'sha256')) $fileRequired
        Assert-GalleryBitmapInteger $file.index 7
        if ($fileIndices.ContainsKey([string]$file.index)) { throw 'invalid-native-schema-v2' }
        $fileIndices[[string]$file.index] = $true
        Assert-GalleryBitmapEnum $file.status $script:bitmapFontMetadataStatuses
        Assert-GalleryBitmapEnum $file.operation $operations
        Assert-GalleryBitmapEnum $file.codeDomain @('none', 'hresult', 'win32', 'ntstatus')
        Assert-GalleryBitmapEnum $file.observationKind @('face-file-stream-at-observation')
        Assert-GalleryBitmapEnum $file.loadedBytesDigest @('not-observed')
        $code = Get-GalleryBitmapOptionalProperty $file 'code'
        $streamLength = Get-GalleryBitmapOptionalProperty $file 'streamLength'
        $sha256 = Get-GalleryBitmapOptionalProperty $file 'sha256'
        if ($file.codeDomain -ceq 'none') {
            if ($null -ne $code) { throw 'invalid-native-schema-v2' }
        } else { Assert-GalleryBitmapInteger $code 2147483647 -2147483648 }
        Assert-GalleryBitmapInteger $file.requestedBytes 16777216
        Assert-GalleryBitmapInteger $file.readBytes 16777216
        if ($file.readBytes -gt $file.requestedBytes) { throw 'invalid-native-schema-v2' }
        if ($null -ne $streamLength) {
            Assert-GalleryBitmapUInt64V2 $streamLength
            $streamLength = [uint64]::Parse($streamLength.ToString([Globalization.CultureInfo]::InvariantCulture), [Globalization.CultureInfo]::InvariantCulture)
            if ([uint64]$file.requestedBytes -gt $streamLength) { throw 'invalid-native-schema-v2' }
        } elseif ($file.requestedBytes -ne 0 -or $file.readBytes -ne 0) { throw 'invalid-native-schema-v2' }
        Assert-GalleryBitmapObject $file.reference @('status', 'scope', 'basename') @('status')
        Assert-GalleryBitmapEnum $file.reference.status $script:bitmapFontMetadataStatuses
        $scope = Get-GalleryBitmapOptionalProperty $file.reference 'scope'
        $basename = Get-GalleryBitmapOptionalProperty $file.reference 'basename'
        if ($file.reference.status -ceq 'observed') {
            Assert-GalleryBitmapEnum $scope @('system-fonts', 'user-fonts')
            if (-not (Test-GalleryBitmapSafeFontBasename $basename)) { throw 'invalid-native-schema-v2' }
        } elseif ($null -ne $scope -or $null -ne $basename) { throw 'invalid-native-schema-v2' }
        if ($file.operation -cin $preSizeOperations -or $file.status -ceq 'nonlocal-or-custom') {
            if ($null -ne $streamLength -or $file.requestedBytes -ne 0 -or $file.readBytes -ne 0) { throw 'invalid-native-schema-v2' }
        }
        if ($file.status -ceq 'observed') {
            if ($file.operation -cne 'complete' -or $file.codeDomain -cne 'none' -or $file.reference.status -cne 'observed' -or
                $null -eq $streamLength -or $streamLength -eq 0 -or $streamLength -gt 16777216 -or
                $file.requestedBytes -ne $streamLength -or $file.readBytes -ne $streamLength -or
                $sha256 -isnot [string] -or $sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'invalid-native-schema-v2' }
        } elseif ($null -ne $sha256 -or $file.operation -ceq 'complete') { throw 'invalid-native-schema-v2' }
        if ($null -ne $streamLength -and $streamLength -gt 16777216 -and
            ($file.status -cne 'limit-exceeded' -or $file.operation -cne 'check-byte-budget' -or $file.requestedBytes -ne 0)) { throw 'invalid-native-schema-v2' }
        [pscustomobject][ordered]@{
            index = $file.index
            reference = [pscustomobject][ordered]@{ status = $file.reference.status; scope = $scope; basename = $basename }
            status = $file.status; operation = $file.operation; codeDomain = $file.codeDomain; code = $code
            streamLength = $streamLength; requestedBytes = $file.requestedBytes; readBytes = $file.readBytes; sha256 = $sha256
            observationKind = 'face-file-stream-at-observation'; loadedBytesDigest = 'not-observed'
        }
    })
    if ($Value.filesStatus -ceq 'observed' -and ($files.Count -eq 0 -or @($files | Where-Object { $_.status -cne 'observed' }).Count -gt 0)) { throw 'invalid-native-schema-v2' }
    [pscustomobject][ordered]@{
        faceType = $faceType; axes = $axes; axesStatus = $Value.axesStatus; hasVariations = $hasVariations
        files = $files; filesStatus = $Value.filesStatus
    }
}

function ConvertTo-GalleryBitmapNativeReportV2 {
    param([string]$Json, [string]$InvocationID, [string]$FixtureID)
    if ((New-Object Text.UTF8Encoding($false, $true)).GetByteCount($Json) -gt 524288) { throw 'native-json-size-limit-v2' }
    Assert-GalleryBitmapJsonLexicalBounds $Json
    $envelope = ConvertFrom-Json $Json -ErrorAction Stop
    $envelopeKeys = @('schemaVersion', 'invocationID', 'fixtureID', 'status', 'runtime', 'pngFileName', 'report')
    Assert-GalleryBitmapObject $envelope $envelopeKeys $envelopeKeys
    Assert-GalleryBitmapInteger $envelope.schemaVersion 2 2
    $report = $envelope.report
    $reportKeys = @('schemaVersion', 'kind', 'scope', 'fixtureID', 'status', 'qualification', 'attributionV1', 'coverage', 'faces', 'glyphRuns', 'observations', 'limits')
    Assert-GalleryBitmapObject $report $reportKeys $reportKeys
    Assert-GalleryBitmapInteger $report.schemaVersion 2 2
    Assert-GalleryBitmapEnum $report.kind @('native-bitmap-font-attribution-v2')
    Assert-GalleryBitmapEnum $report.scope @('bitmap-icons')
    Assert-GalleryBitmapEnum $report.status @('observed', 'partial')
    Assert-GalleryBitmapEnum $report.qualification @('unqualified')
    if ($report.fixtureID -isnot [string] -or $report.fixtureID -cne $FixtureID -or $envelope.status -isnot [string] -or $envelope.status -cne $report.status) { throw 'invalid-native-schema-v2' }
    # Validate the actual nested V1 report, not a V2 object with a downgraded
    # version. This keeps every V1 privacy/grammar/schema rule authoritative.
    $legacyEnvelope = [pscustomobject][ordered]@{
        schemaVersion = 1; invocationID = $envelope.invocationID; fixtureID = $envelope.fixtureID
        status = Get-GalleryBitmapOptionalProperty $report.attributionV1 'status'
        runtime = $envelope.runtime; pngFileName = $envelope.pngFileName; report = $report.attributionV1
    }
    $legacy = ConvertTo-GalleryBitmapNativeReport -Json ($legacyEnvelope | ConvertTo-Json -Depth 24 -Compress) -InvocationID $InvocationID -FixtureID $FixtureID
    $coverageKeys = @('bitmapDrawGlyphRuns', 'faceFileStreams', 'sceneReferences', 'atlasGlyphs', 'textLayouts', 'visiblePixels', 'loadedBytesDigest')
    Assert-GalleryBitmapObject $report.coverage $coverageKeys $coverageKeys
    foreach ($key in @('bitmapDrawGlyphRuns', 'faceFileStreams', 'sceneReferences')) { Assert-GalleryBitmapEnum $report.coverage.$key @('observed', 'partial') }
    foreach ($key in @('atlasGlyphs', 'textLayouts')) { Assert-GalleryBitmapEnum $report.coverage.$key @('not-instrumented') }
    foreach ($key in @('visiblePixels', 'loadedBytesDigest')) { Assert-GalleryBitmapEnum $report.coverage.$key @('not-observed') }
    $fixedLimits = [ordered]@{
        maxFaces = 64; maxReceipts = 256; maxObservations = 256; maxGlyphsPerRun = 128; maxRunsPerRaster = 16
        maxRuns = 256; maxGlyphs = 4096; maxFilesPerFace = 8; maxAxesPerFace = 32
        maxStreamBytesPerFile = 16777216; maxStreamBytesSession = 67108864; streamFragmentBytes = 65536
    }
    $counterLimits = [ordered]@{ copiedRuns = 256; copiedGlyphs = 4096; requestedStreamBytes = 67108864; readStreamBytes = 67108864; dropped = 2147483647 }
    $limitKeys = @($fixedLimits.Keys) + @($counterLimits.Keys)
    Assert-GalleryBitmapObject $report.limits $limitKeys $limitKeys
    foreach ($key in $fixedLimits.Keys) { Assert-GalleryBitmapInteger $report.limits.$key $fixedLimits[$key] $fixedLimits[$key] }
    foreach ($key in $counterLimits.Keys) { Assert-GalleryBitmapInteger $report.limits.$key $counterLimits[$key] }
    if ($report.limits.readStreamBytes -gt $report.limits.requestedStreamBytes) { throw 'invalid-native-schema-v2' }
    Assert-GalleryBitmapArray $report.faces 64
    $faceIDs = @{}; [long]$requestedBytes = 0; [long]$readBytes = 0
    $faces = @(foreach ($face in $report.faces) {
        Assert-GalleryBitmapObject $face @('id', 'metadata', 'evidence') @('id', 'metadata', 'evidence')
        if ($face.id -isnot [string] -or $face.id -cnotmatch '^draw-face-([1-9][0-9]?)$' -or [int]$Matches[1] -gt 64 -or $faceIDs.ContainsKey($face.id)) { throw 'invalid-native-schema-v2' }
        $faceIDs[$face.id] = $true
        $evidence = ConvertTo-GalleryBitmapFaceEvidenceV2 $face.evidence
        foreach ($file in $evidence.files) { $requestedBytes += [long]$file.requestedBytes; $readBytes += [long]$file.readBytes }
        [pscustomobject][ordered]@{ id = $face.id; metadata = ConvertTo-GalleryBitmapFaceMetadata $face.metadata; evidence = $evidence }
    })
    if ($requestedBytes -gt $report.limits.requestedStreamBytes -or $readBytes -gt $report.limits.readStreamBytes) { throw 'invalid-native-schema-v2' }
    if ($report.coverage.faceFileStreams -ceq 'observed' -and ($faces.Count -eq 0 -or
        $requestedBytes -ne $report.limits.requestedStreamBytes -or $readBytes -ne $report.limits.readStreamBytes -or
        @($faces | Where-Object { $_.evidence.filesStatus -cne 'observed' }).Count -gt 0)) { throw 'invalid-native-schema-v2' }
    Assert-GalleryBitmapArray $report.glyphRuns 256
    $runMap = @{}; $runFaces = @{}; [long]$copiedRuns = 0; [long]$copiedGlyphs = 0
    $glyphRuns = @(foreach ($run in $report.glyphRuns) {
        $keys = @('id', 'faceID', 'glyphCount', 'glyphIndices', 'drawResult', 'drawStatus', 'count')
        Assert-GalleryBitmapObject $run $keys $keys
        if ($run.id -isnot [string] -or $run.id -cnotmatch '^glyph-run-([1-9][0-9]{0,2})$' -or [int]$Matches[1] -gt 256 -or $runMap.ContainsKey($run.id) -or
            $run.faceID -isnot [string] -or $run.faceID -cnotmatch '^draw-face-[1-9][0-9]?$' -or -not $faceIDs.ContainsKey($run.faceID)) { throw 'invalid-native-schema-v2' }
        Assert-GalleryBitmapInteger $run.glyphCount 128
        Assert-GalleryBitmapArray $run.glyphIndices 128
        if ($run.glyphIndices.Count -ne $run.glyphCount) { throw 'invalid-native-schema-v2' }
        foreach ($glyph in $run.glyphIndices) { Assert-GalleryBitmapInteger $glyph 65535 }
        Assert-GalleryBitmapInteger $run.drawResult 2147483647 -2147483648
        Assert-GalleryBitmapEnum $run.drawStatus @('succeeded', 'failed')
        if (($run.drawResult -ge 0) -ne ($run.drawStatus -ceq 'succeeded')) { throw 'invalid-native-schema-v2' }
        Assert-GalleryBitmapInteger $run.count 256 1
        $copiedRuns += [long]$run.count; $copiedGlyphs += [long]$run.glyphCount * [long]$run.count
        $normalized = [pscustomobject][ordered]@{
            id = $run.id; faceID = $run.faceID; glyphCount = $run.glyphCount; glyphIndices = @($run.glyphIndices)
            drawResult = $run.drawResult; drawStatus = $run.drawStatus; count = $run.count
        }
        $runMap[$run.id] = $normalized
        $runFaces[$run.faceID] = $true
        $normalized
    })
    if ($copiedRuns -gt $report.limits.copiedRuns -or $copiedGlyphs -gt $report.limits.copiedGlyphs) { throw 'invalid-native-schema-v2' }
    if ($report.coverage.bitmapDrawGlyphRuns -ceq 'observed' -and ($glyphRuns.Count -eq 0 -or
        $copiedRuns -ne $report.limits.copiedRuns -or $copiedGlyphs -ne $report.limits.copiedGlyphs -or $runFaces.Count -ne $faces.Count)) { throw 'invalid-native-schema-v2' }
    Assert-GalleryBitmapArray $report.observations 256
    $observationKeys = @{}; $producedBags = @{}; $acceptedBags = @{}; $drawnRuns = @{}
    $observationBags = New-Object 'System.Collections.Generic.List[object]'
    $observations = @(foreach ($observation in $report.observations) {
        $keys = @('role', 'purpose', 'backend', 'outcome', 'status', 'runIDs', 'runCounts', 'count')
        Assert-GalleryBitmapObject $observation $keys $keys
        Assert-GalleryBitmapEnum $observation.role $script:bitmapFontFixtureRoles[$FixtureID]
        Assert-GalleryBitmapEnum $observation.purpose @('display-bitmap')
        Assert-GalleryBitmapEnum $observation.backend @('direct-write', 'gdi', 'vector', 'testing-override', 'unknown')
        Assert-GalleryBitmapEnum $observation.outcome @('draw-produced', 'draw-unavailable', 'bitmap-accepted', 'bitmap-rejected', 'bitmap-cache-hit-known',
            'bitmap-cache-hit-unobserved', 'scene-referenced', 'not-referenced', 'scene-association-unobserved', 'vector-selected', 'limit-exceeded', 'testing-override')
        Assert-GalleryBitmapEnum $observation.status @('observed', 'partial', 'not-observed')
        Assert-GalleryBitmapInteger $observation.count 2147483647 1
        Assert-GalleryBitmapArray $observation.runIDs 16
        Assert-GalleryBitmapArray $observation.runCounts 16
        if ($observation.runIDs.Count -ne $observation.runCounts.Count) { throw 'invalid-native-schema-v2' }
        $seen = @{}; $runTotal = 0; $allSucceeded = $true
        $bag = @(for ($i = 0; $i -lt $observation.runIDs.Count; $i++) {
            $runID = $observation.runIDs[$i]; $runCount = $observation.runCounts[$i]
            if ($runID -isnot [string] -or $runID -cnotmatch '^glyph-run-[1-9][0-9]{0,2}$' -or -not $runMap.ContainsKey($runID) -or $seen.ContainsKey($runID) -or $observation.backend -cne 'direct-write') { throw 'invalid-native-schema-v2' }
            Assert-GalleryBitmapInteger $runCount 16 1
            if ($runCount -gt $runMap[$runID].count) { throw 'invalid-native-schema-v2' }
            $seen[$runID] = $true; $runTotal += [int]$runCount
            if ($runMap[$runID].drawStatus -cne 'succeeded' -or $runMap[$runID].glyphCount -eq 0) { $allSucceeded = $false }
            [pscustomobject]@{ id = $runID; count = $runCount }
        })
        if ($runTotal -gt 16 -or ($observation.status -ceq 'not-observed' -and $bag.Count -gt 0) -or
            ($observation.status -ceq 'observed' -and ($bag.Count -eq 0 -or -not $allSucceeded))) { throw 'invalid-native-schema-v2' }
        if ($observation.outcome -cin @('bitmap-cache-hit-unobserved', 'scene-association-unobserved', 'vector-selected', 'testing-override', 'limit-exceeded') -and $bag.Count -gt 0) { throw 'invalid-native-schema-v2' }
        $bag = @($bag | Sort-Object id)
        $bagKey = (@($bag | ForEach-Object { $_.id + '=' + $_.count }) -join ',')
        $key = $observation.role + '|' + $observation.backend + '|' + $observation.outcome + '|' + $observation.status + '|' + $bagKey
        if ($observationKeys.ContainsKey($key)) { throw 'invalid-native-schema-v2' }
        $observationKeys[$key] = $true
        if ($bag.Count -gt 0) {
            if ($observation.outcome -cin @('draw-produced', 'draw-unavailable')) {
                foreach ($run in $bag) {
                    # Only these two outcomes consume an actual raster attempt.
                    # Acceptance, cache reuse, and scene references do not draw.
                    if (-not $drawnRuns.ContainsKey($run.id)) { $drawnRuns[$run.id] = [long]0 }
                    $drawnRuns[$run.id] += [long]$run.count * [long]$observation.count
                    if ($drawnRuns[$run.id] -gt $runMap[$run.id].count) { throw 'invalid-native-schema-v2' }
                }
            }
            if ($observation.outcome -ceq 'draw-produced') {
                $producedBags[$bagKey] = $producedBags[$bagKey] -eq $true -or $observation.status -ceq 'observed'
            }
            if ($observation.outcome -cin @('bitmap-accepted', 'bitmap-cache-hit-known')) {
                $acceptedKey = $observation.role + '|' + $bagKey
                $acceptedBags[$acceptedKey] = $acceptedBags[$acceptedKey] -eq $true -or $observation.status -ceq 'observed'
            }
        }
        $normalized = [pscustomobject][ordered]@{
            role = $observation.role; purpose = 'display-bitmap'; backend = $observation.backend; outcome = $observation.outcome; status = $observation.status
            runIDs = @($bag | ForEach-Object { $_.id }); runCounts = @($bag | ForEach-Object { $_.count }); count = $observation.count
        }
        $observationBags.Add([pscustomobject]@{ observation = $normalized; key = $bagKey })
        $normalized
    })
    foreach ($item in $observationBags) {
        if ($item.observation.runIDs.Count -eq 0) { continue }
        if ($item.observation.outcome -cin @('bitmap-accepted', 'bitmap-cache-hit-known') -and
            (-not $producedBags.ContainsKey($item.key) -or ($item.observation.status -ceq 'observed' -and -not $producedBags[$item.key]))) { throw 'invalid-native-schema-v2' }
        $acceptedKey = $item.observation.role + '|' + $item.key
        if ($item.observation.outcome -cin @('scene-referenced', 'not-referenced') -and
            (-not $acceptedBags.ContainsKey($acceptedKey) -or ($item.observation.status -ceq 'observed' -and -not $acceptedBags[$acceptedKey]))) { throw 'invalid-native-schema-v2' }
    }
    foreach ($run in $glyphRuns) {
        $charged = if ($drawnRuns.ContainsKey($run.id)) { $drawnRuns[$run.id] } else { [long]0 }
        if ($charged -ne $run.count -and ($report.coverage.bitmapDrawGlyphRuns -ceq 'observed' -or $report.limits.dropped -eq 0)) { throw 'invalid-native-schema-v2' }
    }
    if ($report.coverage.bitmapDrawGlyphRuns -ceq 'observed' -and ($observations.Count -eq 0 -or
        @($observations | Where-Object { $_.status -cne 'observed' }).Count -gt 0 -or $drawnRuns.Count -ne $glyphRuns.Count)) { throw 'invalid-native-schema-v2' }
    if ($report.coverage.sceneReferences -ceq 'observed' -and @($observations | Where-Object { $_.outcome -ceq 'scene-association-unobserved' }).Count -gt 0) { throw 'invalid-native-schema-v2' }
    if ($report.status -ceq 'observed' -and ($legacy.status -cne 'observed' -or $report.limits.dropped -ne 0 -or
        $report.coverage.bitmapDrawGlyphRuns -cne 'observed' -or $report.coverage.faceFileStreams -cne 'observed' -or
        $report.coverage.sceneReferences -cne 'observed')) { throw 'invalid-native-schema-v2' }
    $limits = [ordered]@{}
    foreach ($key in $fixedLimits.Keys) { $limits[$key] = $fixedLimits[$key] }
    foreach ($key in $counterLimits.Keys) { $limits[$key] = $report.limits.$key }
    [pscustomobject][ordered]@{
        schemaVersion = 2; invocationID = $InvocationID; fixtureID = $FixtureID; status = $report.status
        runtime = $legacy.runtime; pngFileName = "$FixtureID.png"
        report = [ordered]@{
            schemaVersion = 2; kind = 'native-bitmap-font-attribution-v2'; scope = 'bitmap-icons'; fixtureID = $FixtureID
            status = $report.status; qualification = 'unqualified'; attributionV1 = $legacy.report
            coverage = [ordered]@{
                bitmapDrawGlyphRuns = $report.coverage.bitmapDrawGlyphRuns; faceFileStreams = $report.coverage.faceFileStreams
                sceneReferences = $report.coverage.sceneReferences; atlasGlyphs = 'not-instrumented'; textLayouts = 'not-instrumented'
                visiblePixels = 'not-observed'; loadedBytesDigest = 'not-observed'
            }
            faces = $faces; glyphRuns = $glyphRuns; observations = $observations; limits = $limits
        }
    }
}

function Read-GalleryBitmapArtifact {
    param([string]$Path, [long]$MaximumBytes, [switch]$Json)
    $stream = $null; $hash = $null
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'missing-artifact' }
        $info = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'artifact-alias-rejected' }
        # No permissive retry: sharing violations remain a missing observation.
        $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read, 1)
        $length = $stream.Length
        if ($length -lt 0 -or $length -gt $MaximumBytes) { throw 'artifact-size-limit' }
        $hash = [Security.Cryptography.SHA256]::Create()
        $data = $null
        if ($Json) {
            $data = New-Object byte[] ([int]$length)
            $offset = 0
            while ($offset -lt $length) {
                $read = $stream.Read($data, $offset, [int]$length - $offset)
                if ($read -eq 0) { throw 'artifact-mutated' }
                $offset += $read
            }
            $digest = $hash.ComputeHash($data)
        } else {
            $buffer = New-Object byte[] 65536
            $left = $length
            while ($left -gt 0) {
                $read = $stream.Read($buffer, 0, [int][math]::Min($buffer.Length, $left))
                if ($read -eq 0) { throw 'artifact-mutated' }
                [void]$hash.TransformBlock($buffer, 0, $read, $buffer, 0)
                $left -= $read
            }
            [void]$hash.TransformFinalBlock([byte[]]@(), 0, 0)
            $digest = $hash.Hash
        }
        $info.Refresh()
        if ($stream.Length -ne $length -or $info.Length -ne $length) { throw 'artifact-mutated' }
        $text = $null
        if ($Json) {
            $text = (New-Object Text.UTF8Encoding($false, $true)).GetString($data)
            if ($text.Length -gt 0 -and $text[0] -eq [char]0xfeff) { $text = $text.Substring(1) }
        }
        [pscustomobject]@{
            status = 'observed'; sha256 = [BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
            length = $length; lastWriteTimeUtc = $info.LastWriteTimeUtc; text = $text
        }
    } finally {
        if ($null -ne $hash) { $hash.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-GalleryBitmapJsonDigest {
    param($Value)
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = (New-Object Text.UTF8Encoding($false, $true)).GetBytes(($Value | ConvertTo-Json -Depth 20 -Compress))
        [BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally { $hash.Dispose() }
}

function New-GalleryBitmapDiskObservation {
    param([string]$Scope, [string]$Basename, [long]$RemainingBytes, [scriptblock]$FileFingerprinter)
    if ($Scope -cnotin @('system-fonts', 'user-fonts') -or -not (Test-GalleryBitmapSafeFontBasename $Basename)) {
        return [pscustomobject]@{ scope = $null; basename = $null; faceFileReference = 'not-observed'; loadedBytesDigest = 'not-observed'; diskObservation = 'not-observed'; bytesRead = 0; file = [ordered]@{ path = $null; status = 'not-approved'; sha256 = $null; length = $null; lastWriteTimeUtc = $null; fileVersion = $null; error = 'invalid-reference' } }
    }
    $output = [ordered]@{
        scope = $Scope; basename = $Basename; faceFileReference = 'observed'; loadedBytesDigest = 'not-observed'
        diskObservation = 'not-observed'; validation = 'not-validated'; hardLinkPolicy = 'approved-path-only; other-links-not-enumerated'
        file = [ordered]@{ path = "$Scope/$Basename"; status = 'unavailable'; sha256 = $null; length = $null; lastWriteTimeUtc = $null; fileVersion = $null; error = 'adapter-unavailable' }
        embeddedVersions = @(); versionStatus = 'unknown'; versionError = 'not-observed'; bytesRead = 0
    }
    try {
        if ($Scope -cnotin @('system-fonts', 'user-fonts') -or -not (Test-GalleryBitmapSafeFontBasename $Basename)) { throw 'invalid-reference' }
        if ($RemainingBytes -le 0) { $output.file.status = 'limit-exceeded'; $output.file.error = 'total-limit-exceeded'; return [pscustomobject]$output }
        $value = & $FileFingerprinter $Scope $Basename $RemainingBytes
        Assert-GalleryBitmapEnum $value.Status @('observed', 'missing', 'not-approved', 'unavailable', 'limit-exceeded', 'mutated', 'failed')
        Assert-GalleryBitmapInteger $value.BytesRead ([math]::Min(134217728, $RemainingBytes))
        $output.bytesRead = [long]$value.BytesRead
        $output.file.status = $value.Status
        $errorCodes = @('windows-required', 'invalid-reference', 'invalid-budget', 'path-not-approved', 'final-path-unavailable', 'metadata-unavailable', 'identity-unavailable', 'directory-unavailable', 'missing', 'file-open-failed', 'file-limit-exceeded', 'total-limit-exceeded', 'read-budget-exhausted', 'file-mutated', 'fingerprint-failed')
        if ($null -ne $value.Error) { Assert-GalleryBitmapEnum $value.Error $errorCodes }
        $output.file.error = $value.Error
        if ($value.Status -ceq 'observed') {
            if ($value.Stable -isnot [bool] -or -not $value.Stable -or $value.Sha256 -isnot [string] -or $value.Sha256 -cnotmatch '^[0-9a-f]{64}$' -or $value.Validation -cne 'same-handle-final-path-and-file-id') { throw 'invalid-adapter-result' }
            Assert-GalleryBitmapInteger $value.Length 134217728
            if ($value.BytesRead -lt $value.Length) { throw 'invalid-adapter-result' }
            if ($value.LastWriteTimeUtc -isnot [string] -or $value.LastWriteTimeUtc -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$') { throw 'invalid-adapter-result' }
            Assert-GalleryBitmapArray $value.EmbeddedVersions 16
            foreach ($version in $value.EmbeddedVersions) { Assert-GalleryBitmapMetadataString $version }
            Assert-GalleryBitmapEnum $value.VersionStatus @('observed-embedded-name', 'unknown')
            if ($null -ne $value.VersionError) { Assert-GalleryBitmapEnum $value.VersionError @('not-observed', 'no-name-id-5', 'unsupported-container', 'invalid-font', 'read-budget-exhausted', 'version-limit-exceeded') }
            if (($value.VersionStatus -ceq 'observed-embedded-name') -ne ($value.EmbeddedVersions.Count -gt 0)) { throw 'invalid-adapter-result' }
            $output.diskObservation = 'observed-after-render'; $output.validation = $value.Validation
            $output.file.sha256 = $value.Sha256; $output.file.length = $value.Length; $output.file.lastWriteTimeUtc = $value.LastWriteTimeUtc
            $output.embeddedVersions = @($value.EmbeddedVersions); $output.versionStatus = $value.VersionStatus; $output.versionError = $value.VersionError
        }
    } catch {
        # A faulty adapter must not create more budget or export its exception.
        $output.bytesRead = [math]::Min(134217728, [math]::Max(0, $RemainingBytes))
        $output.file.status = 'failed'; $output.file.error = 'invalid-adapter-result'; $output.file.sha256 = $null
        $output.file.length = $null; $output.file.lastWriteTimeUtc = $null; $output.diskObservation = 'not-observed'; $output.validation = 'not-validated'
        $output.embeddedVersions = @(); $output.versionStatus = 'unknown'; $output.versionError = 'not-observed'
    }
    [pscustomobject]$output
}

function Complete-GalleryBitmapFontAttribution {
    param(
        $Invocation,
        $Provenance,
        [string]$ProfilePath,
        [scriptblock]$FileFingerprinter = { param($scope, $basename, $remaining) Get-GalleryBitmapNativeFileFingerprint $scope $basename $remaining }
    )
    # Invalid library callers must fail before any path construction or output.
    $nativeSchemaVersion = 1
    $explicitVersion = Get-GalleryBitmapOptionalProperty $Invocation 'nativeSchemaVersion'
    if ($null -ne $Invocation.PSObject.Properties['nativeSchemaVersion']) {
        Assert-GalleryBitmapInteger $explicitVersion 2 2
        $nativeSchemaVersion = 2
    }
    if ($Invocation.invocationID -isnot [string] -or $Invocation.invocationID -cnotmatch '^[0-9a-f]{32}$' -or $Invocation.entries -isnot [array] -or $Invocation.entries.Count -lt 1 -or $Invocation.entries.Count -gt 2) { throw 'invalid-invocation' }
    foreach ($id in $Invocation.entries) { if ($id -isnot [string] -or $script:bitmapFontFixtureRoles.Keys -cnotcontains $id) { throw 'invalid-invocation' } }
    if (@($Invocation.entries | Select-Object -Unique).Count -ne $Invocation.entries.Count) { throw 'invalid-invocation' }
    $profile = $null; $profileArtifact = $null; $binding = 'unverified-invocation'
    $source = [ordered]@{ revision = $null; observationSha256 = $null; observation = 'checkout-only'; executableBuildRevision = $null }
    $executable = [ordered]@{ beforeSha256 = $null; afterSha256 = $null; unchanged = $false; buildRevision = 'not-embedded' }
    try {
        $profileArtifact = Read-GalleryBitmapArtifact -Path $ProfilePath -MaximumBytes 524288 -Json
        $profile = ConvertFrom-Json $profileArtifact.text -ErrorAction Stop
        # Match the exact serializer contract of Write-GalleryFontProvenance,
        # not a JSON round trip that may convert ISO strings into DateTimes.
        $expectedProfileBytes = (New-Object Text.UTF8Encoding($false, $true)).GetBytes(($Provenance | ConvertTo-Json -Depth 12) + [Environment]::NewLine)
        $profileHasher = [Security.Cryptography.SHA256]::Create()
        try { $expectedProfileDigest = [BitConverter]::ToString($profileHasher.ComputeHash($expectedProfileBytes)).Replace('-', '').ToLowerInvariant() }
        finally { $profileHasher.Dispose() }
        if ($profile.invocationID -cne $Invocation.invocationID -or $Provenance.invocationID -cne $Invocation.invocationID -or
            $profileArtifact.sha256 -cne $expectedProfileDigest) { throw 'profile-binding-mismatch' }
        if ($profile.source.revision -isnot [string] -or $profile.source.revision -cnotmatch '^[0-9a-f]{40,64}$' -or $profile.source.status -cne 'observed-checkout-only' -or $null -ne $profile.source.executableBuildRevision) { throw 'source-unobserved' }
        $source.revision = $profile.source.revision
        $source.observationSha256 = Get-GalleryBitmapJsonDigest $profile.source
        foreach ($fingerprint in @($profile.executable, $profile.render.executableAfter)) {
            if ($fingerprint.status -cne 'observed' -or $fingerprint.sha256 -isnot [string] -or $fingerprint.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'executable-unobserved' }
        }
        $executable.beforeSha256 = $profile.executable.sha256
        $executable.afterSha256 = $profile.render.executableAfter.sha256
        $executable.unchanged = $executable.beforeSha256 -ceq $executable.afterSha256
        if ($profile.executable.path -isnot [string] -or $profile.executable.path.Length -gt 1024) { throw 'executable-path-unavailable' }
        $executableArtifact = Read-GalleryBitmapArtifact -Path $profile.executable.path -MaximumBytes 268435456
        if ($executableArtifact.sha256 -cne $executable.afterSha256) { throw 'executable-digest-mismatch' }
        Assert-GalleryBitmapInteger $profile.render.exitCode 0 0
        if (-not $executable.unchanged -or $profile.render.executableUnchanged -isnot [bool] -or -not $profile.render.executableUnchanged -or
            $profile.render.status -cne 'succeeded' -or
            $profile.build.status -cnotin @('succeeded', 'skipped') -or $profile.stage -cne 'render-completed') { throw 'render-unverified' }
        Assert-GalleryBitmapArray $profile.render.requestedEntries 2
        if (($profile.render.requestedEntries -join ',') -cne ($Invocation.entries -join ',')) { throw 'selection-mismatch' }
        $binding = 'linked-to-completed-invocation'
    } catch {
        # No exception strings or raw provenance fields enter this report.
        $binding = 'unverified-invocation'
    }

    $files = @{}; $fileLimit = $false; $partial = $binding -cne 'linked-to-completed-invocation'
    $entries = @(foreach ($id in $Invocation.entries) {
        $entry = [ordered]@{
            fixtureID = $id; status = 'partial'; association = 'unverified'
            png = [ordered]@{ path = "current/$id.png"; status = 'unavailable'; sha256 = $null; length = $null; observation = 'observed-file-after-render; no-native-embedded-image-digest' }
            nativeSidecar = [ordered]@{ path = "bitmap-font-attribution/native/$id.native-font-attribution.json"; status = 'unavailable'; sha256 = $null; length = $null }
            native = $null; fileReferences = @(); error = $null
        }
        try {
            foreach ($directory in @($Invocation.workDirectory, $Invocation.currentDirectory)) {
                if (-not (Test-Path -LiteralPath $directory -PathType Container) -or ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'artifact-directory-unavailable' }
            }
            $png = Read-GalleryBitmapArtifact -Path (Join-Path $Invocation.currentDirectory "$id.png") -MaximumBytes 33554432
            $entry.png.status = 'observed'; $entry.png.sha256 = $png.sha256; $entry.png.length = $png.length
            foreach ($directory in @((Split-Path -Parent $Invocation.nativeDirectory), $Invocation.nativeDirectory)) {
                if (-not (Test-Path -LiteralPath $directory -PathType Container) -or ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'artifact-directory-unavailable' }
            }
            $sidecar = Read-GalleryBitmapArtifact -Path (Join-Path $Invocation.nativeDirectory "$id.native-font-attribution.json") -MaximumBytes 524288 -Json
            $entry.nativeSidecar.status = 'read-unverified'; $entry.nativeSidecar.sha256 = $sidecar.sha256; $entry.nativeSidecar.length = $sidecar.length
            # Fresh ownership plus the unguessable per-invocation token is the
            # primary stale-file boundary; timestamps are a conservative check.
            if ($sidecar.lastWriteTimeUtc -lt $Invocation.startedAtUtc.AddSeconds(-2) -or $png.lastWriteTimeUtc -lt $Invocation.startedAtUtc.AddSeconds(-2)) { throw 'stale-artifact' }
            $native = if ($nativeSchemaVersion -eq 2) {
                ConvertTo-GalleryBitmapNativeReportV2 -Json $sidecar.text -InvocationID $Invocation.invocationID -FixtureID $id
            } else {
                ConvertTo-GalleryBitmapNativeReport -Json $sidecar.text -InvocationID $Invocation.invocationID -FixtureID $id
            }
            if ($binding -cne 'linked-to-completed-invocation') { throw 'unverified-invocation' }
            $entry.nativeSidecar.status = 'validated'
            $entry.association = 'linked-to-completed-invocation; scene-reference-is-not-visible-contribution'
            $entry.native = $native; $entry.status = $native.status
            $legacyReport = if ($nativeSchemaVersion -eq 2) { $native.report.attributionV1 } else { $native.report }
            if ($native.runtime.architecture -ceq 'unknown' -or $legacyReport.limits.dropped -gt 0 -or
                $legacyReport.coverage.bitmapIcons -cne 'observed' -or $legacyReport.coverage.sceneReferences -cne 'observed' -or
                $legacyReport.observations.Count -eq 0 -or
                @($legacyReport.observations | Where-Object {
                    $_.outcome -cin @('bitmap-cache-hit-unobserved', 'scene-association-unobserved', 'limit-exceeded', 'testing-override') -or $_.backend -cin @('gdi', 'unknown', 'testing-override') -or
                    ($_.backend -ceq 'direct-write' -and $_.outcome -cin @('draw-produced', 'bitmap-accepted', 'bitmap-cache-hit-known', 'scene-referenced') -and $_.faceIDs.Count -eq 0)
                }).Count -gt 0) { $entry.status = 'partial' }
            if ($nativeSchemaVersion -eq 2 -and ($native.report.limits.dropped -gt 0 -or
                $native.report.coverage.bitmapDrawGlyphRuns -cne 'observed' -or $native.report.coverage.faceFileStreams -cne 'observed' -or
                $native.report.coverage.sceneReferences -cne 'observed' -or $native.report.observations.Count -eq 0 -or
                @($native.report.observations | Where-Object { $_.status -cne 'observed' }).Count -gt 0)) { $entry.status = 'partial' }
            $references = @{}
            $referenceFaces = @($legacyReport.faces)
            if ($nativeSchemaVersion -eq 2) {
                # The V2 face-file stream is a separate observation, never a
                # loaded-byte digest or a substitute for the disk adapter.
                $referenceFaces += @($native.report.faces)
                foreach ($face in $native.report.faces) {
                    if ($face.evidence.filesStatus -cne 'observed' -or @($face.evidence.files | Where-Object { $_.status -cne 'observed' }).Count -gt 0) { $entry.status = 'partial' }
                    $referenceFaces += [pscustomobject]@{ metadata = [pscustomobject]@{
                        status = $face.evidence.filesStatus; filesStatus = $face.evidence.filesStatus
                        files = @($face.evidence.files | ForEach-Object { $_.reference })
                    } }
                }
            }
            foreach ($face in $referenceFaces) {
                if ($face.metadata.status -cne 'observed' -or $face.metadata.filesStatus -cne 'observed') { $entry.status = 'partial' }
                foreach ($file in $face.metadata.files) {
                    if ($file.status -cne 'observed') { $entry.status = 'partial'; continue }
                    $key = $file.scope + '/' + $file.basename.ToLowerInvariant()
                    if (-not $files.ContainsKey($key)) {
                        if ($files.Count -ge 64) { $fileLimit = $true; $entry.status = 'partial'; continue }
                        $files[$key] = [pscustomobject]@{ scope = $file.scope; basename = $file.basename }
                    }
                    $references[$key] = $true
                }
            }
            $entry.fileReferences = @($references.Keys | Sort-Object)
        } catch {
            $entry.status = 'partial'; $entry.native = $null; $entry.fileReferences = @()
            if ($entry.nativeSidecar.status -ceq 'read-unverified') { $entry.nativeSidecar.status = 'rejected' }
            $entry.error = 'native-sidecar-unavailable-invalid-stale-or-unbound'
        }
        if ($entry.status -cne 'observed') { $partial = $true }
        [pscustomobject]$entry
    })

    $remaining = [long]536870912
    $diskFiles = @(foreach ($key in @($files.Keys | Sort-Object)) {
        $file = $files[$key]
        $disk = New-GalleryBitmapDiskObservation -Scope $file.scope -Basename $file.basename -RemainingBytes $remaining -FileFingerprinter $FileFingerprinter
        $remaining -= [long]$disk.bytesRead
        if ($disk.diskObservation -cne 'observed-after-render') { $partial = $true }
        # Registry records are only a cross-reference by exact approved path.
        # A matching family, digest, or basename alone never supplies an owner.
        $matches = @()
        $root = if ($file.scope -ceq 'system-fonts') { Join-Path ([Environment]::GetFolderPath('Windows')) 'Fonts' } else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Microsoft/Windows/Fonts' }
        $expected = Join-Path $root $file.basename
        $registered = @($profile.fonts.registeredFontFiles.files)
        for ($i = 0; $i -lt [math]::Min(128, $registered.Count); $i++) {
            $registeredPath = $registered[$i].file.path
            if ($registeredPath -is [string] -and $registeredPath.Length -le 1024 -and [string]::Equals($registeredPath, $expected, [StringComparison]::OrdinalIgnoreCase)) {
                $matches += [ordered]@{ profileFileIndex = $i; sha256MatchesDiskObservation = if ($null -ne $disk.file.sha256 -and $registered[$i].file.sha256 -is [string] -and $registered[$i].file.sha256 -cmatch '^[0-9a-f]{64}$') { $disk.file.sha256 -ceq $registered[$i].file.sha256 } else { $null } }
            }
        }
        [pscustomobject][ordered]@{ reference = $key; observation = $disk; registeredFileMatches = $matches }
    })
    # Detect artifact substitution while the post-render collector was working.
    # These are comparisons of later disk observations, not embedded native
    # image/build digests and not proof of loaded font bytes.
    if ($binding -ceq 'linked-to-completed-invocation') {
        try {
            if ((Read-GalleryBitmapArtifact -Path $ProfilePath -MaximumBytes 524288).sha256 -cne $profileArtifact.sha256 -or
                (Read-GalleryBitmapArtifact -Path $profile.executable.path -MaximumBytes 268435456).sha256 -cne $executable.afterSha256) { throw 'binding-mutated' }
        } catch {
            $binding = 'unverified-invocation'; $partial = $true
            foreach ($entry in $entries) { $entry.status = 'partial'; $entry.association = 'unverified'; $entry.native = $null; $entry.fileReferences = @(); $entry.error = 'invocation-files-changed-during-collection' }
            $diskFiles = @()
        }
        if ($binding -ceq 'linked-to-completed-invocation') {
            foreach ($entry in $entries) {
                if ($null -eq $entry.native) { continue }
                try {
                    if ((Read-GalleryBitmapArtifact -Path (Join-Path $Invocation.currentDirectory ($entry.fixtureID + '.png')) -MaximumBytes 33554432).sha256 -cne $entry.png.sha256 -or
                        (Read-GalleryBitmapArtifact -Path (Join-Path $Invocation.nativeDirectory ($entry.fixtureID + '.native-font-attribution.json')) -MaximumBytes 524288).sha256 -cne $entry.nativeSidecar.sha256) { throw 'artifact-digest-mismatch' }
                } catch {
                    $partial = $true; $entry.status = 'partial'; $entry.association = 'unverified'; $entry.native = $null; $entry.fileReferences = @(); $entry.error = 'fixture-files-changed-during-collection'
                }
            }
        }
    }
    $retainedReferences = @{}
    foreach ($entry in $entries) { if ($null -ne $entry.native) { foreach ($reference in $entry.fileReferences) { $retainedReferences[$reference] = $true } } }
    $diskFiles = @($diskFiles | Where-Object { $retainedReferences.ContainsKey($_.reference) })
    $result = [pscustomobject][ordered]@{
        schemaVersion = $nativeSchemaVersion; kind = 'gallery-bitmap-font-attribution'; status = if ($partial -or $fileLimit) { 'partial' } else { 'observed' }
        qualification = [ordered]@{ status = 'unqualified'; acceptedBaselineProfile = $null; pixelGate = 'unchanged'; performanceQualification = 'excluded' }
        invocationID = $Invocation.invocationID; invocationAssociation = $binding; source = $source; executable = $executable
        currentFontProfile = [ordered]@{ path = 'provenance.json'; sha256 = if ($null -ne $profileArtifact) { $profileArtifact.sha256 } else { $null }; observation = 'current-collector-profile; not-actual-loaded-font-bytes' }
        nativeRuntimeObservation = 'Foundation.ProcessInfo compatibility version; physical OS details are separate collector profile observations'
        coverage = [ordered]@{ fixtures = @($Invocation.entries); scope = 'bitmap-icons'; atlasGlyphs = 'not-instrumented'; textLayouts = 'not-instrumented' }
        limits = [ordered]@{ maxSidecarBytes = 524288; maxReportBytes = 524288; maxFiles = 64; maxFileReadBytes = 134217728; maxTotalReadBytes = 536870912; chargedReadBytes = 536870912 - $remaining; readAccounting = 'returned-bytes; requested-bytes-reserved-on-IO-failure'; filesDropped = $fileLimit; aggregateDropped = $false }
        entries = $entries; files = $diskFiles
    }
    Write-GalleryBitmapFontAttributionReport -Report $result -Path $Invocation.reportPath
    $result
}

function Write-GalleryBitmapFontAttributionReport {
    param($Report, [string]$Path)
    $encoding = New-Object Text.UTF8Encoding($false, $true)
    $json = $Report | ConvertTo-Json -Depth 24
    if ($encoding.GetByteCount($json) -gt 524286) {
        # Keep every PNG and native sidecar. A bounded aggregate links the exact
        # files but drops detail rather than truncating JSON or blessing it.
        $Report.status = 'partial'; $Report.limits.aggregateDropped = $true
        $Report.files = @()
        foreach ($entry in $Report.entries) { $entry.native = $null; $entry.fileReferences = @(); $entry.status = 'partial'; $entry.error = 'aggregate-size-limit' }
        $json = $Report | ConvertTo-Json -Depth 24
        if ($encoding.GetByteCount($json) -gt 524286) { throw 'bitmap-report-size-limit' }
    }
    [IO.File]::WriteAllText($Path, $json + "`n", $encoding)
}
