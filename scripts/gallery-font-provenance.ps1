<#
.SYNOPSIS
    Records the bounded font environment used to diagnose gallery differences.
.DESCRIPTION
    This is evidence, not an accepted baseline profile. It does not select fonts,
    install or copy fonts, inspect unrelated families, or change the pixel gate.
    Dot-source the script to use its collectors without writing an artifact.
#>
param(
    [string]$OutputPath = "artifacts/gallery-compare/provenance.json",
    [string]$GalleryExe = ".build/debug/swift-windowsui-gallery.exe",
    [string]$Stage = "standalone",
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot)
)

$script:galleryFontFamilies = @(
    "Segoe UI Variable Small", "Segoe UI Variable Text", "Segoe UI Variable Display",
    "Segoe UI", "Segoe Fluent Icons", "Segoe MDL2 Assets"
)

function Initialize-GalleryFontProbe {
    if ("SwiftWindowsUIGalleryFontProbe" -as [type]) { return }
    # The first three slots are IUnknown. Only the factory/collection methods
    # preceding FindFamilyName are declared; no text format or glyph is created.
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class SwiftWindowsUIGalleryFontProbe {
    [ComImport, Guid("b859ee5a-d838-4b5b-a2e8-1adc7d93db48"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFactory {
        [PreserveSig] int GetSystemFontCollection(out ICollection collection, [MarshalAs(UnmanagedType.Bool)] bool update);
    }
    [ComImport, Guid("a84cee02-3eea-4eee-a827-87c1a02a0fcc"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ICollection {
        [PreserveSig] uint GetFontFamilyCount();
        [PreserveSig] int GetFontFamily(uint index, out IntPtr family);
        [PreserveSig] int FindFamilyName([MarshalAs(UnmanagedType.LPWStr)] string name, out uint index,
            [MarshalAs(UnmanagedType.Bool)] out bool exists);
    }
    [DllImport("dwrite.dll", PreserveSig = true)]
    private static extern int DWriteCreateFactory(uint type, ref Guid iid, out IFactory factory);

    public static bool IsFamilyInstalled(string family) {
        IFactory factory = null;
        ICollection collection = null;
        try {
            Guid iid = typeof(IFactory).GUID;
            Marshal.ThrowExceptionForHR(DWriteCreateFactory(0, ref iid, out factory));
            Marshal.ThrowExceptionForHR(factory.GetSystemFontCollection(out collection, false));
            uint index;
            bool exists;
            Marshal.ThrowExceptionForHR(collection.FindFamilyName(family, out index, out exists));
            return exists;
        } finally {
            if (collection != null) Marshal.ReleaseComObject(collection);
            if (factory != null) Marshal.ReleaseComObject(factory);
        }
    }

    private static ushort U16(byte[] data, int offset) {
        if (offset < 0 || offset > data.Length - 2) throw new InvalidDataException("Truncated font name table.");
        return (ushort)((data[offset] << 8) | data[offset + 1]);
    }
    private static uint U32(byte[] data, int offset) {
        return ((uint)U16(data, offset) << 16) | U16(data, offset + 2);
    }
    private static byte[] ReadExact(Stream stream, int count) {
        byte[] data = new byte[count];
        int offset = 0;
        while (offset < count) {
            int read = stream.Read(data, offset, count - offset);
            if (read == 0) throw new InvalidDataException("Truncated font file.");
            offset += read;
        }
        return data;
    }

    // FileVersionInfo is commonly empty for TTF files. Read only name ID 5
    // from bounded Unicode/Windows records; unsupported containers stay unknown.
    public static string[] ReadFontVersions(string path) {
        using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
            byte[] header = ReadExact(stream, 12);
            uint signature = U32(header, 0);
            if (signature != 0x00010000 && signature != 0x4f54544f)
                throw new InvalidDataException("Unsupported font container; version is unknown.");
            int count = U16(header, 4);
            if (count > 4096) throw new InvalidDataException("Font table count exceeds diagnostic bound.");
            byte[] directory = ReadExact(stream, count * 16);
            for (int i = 0; i < count; i++) {
                int entry = i * 16;
                if (U32(directory, entry) != 0x6e616d65) continue;
                uint start = U32(directory, entry + 8);
                uint length = U32(directory, entry + 12);
                if (length > 1048576 || (ulong)start + length > (ulong)stream.Length)
                    throw new InvalidDataException("Font name table exceeds diagnostic bounds.");
                stream.Position = start;
                byte[] table = ReadExact(stream, (int)length);
                if (U16(table, 0) > 1) throw new InvalidDataException("Unsupported font name format.");
                int records = U16(table, 2);
                int storage = U16(table, 4);
                if (records > 4096 || 6 + records * 12 > table.Length || storage < 6 + records * 12)
                    throw new InvalidDataException("Invalid font name records.");
                SortedSet<string> versions = new SortedSet<string>(StringComparer.Ordinal);
                for (int n = 0; n < records; n++) {
                    int record = 6 + n * 12;
                    int platform = U16(table, record);
                    int encoding = U16(table, record + 2);
                    if ((platform != 0 && platform != 3) || U16(table, record + 6) != 5) continue;
                    if (platform == 3 && encoding != 0 && encoding != 1 && encoding != 10) continue;
                    int bytes = U16(table, record + 8);
                    int offset = storage + U16(table, record + 10);
                    if (bytes > 4096 || (bytes & 1) != 0 || offset > table.Length - bytes)
                        throw new InvalidDataException("Invalid font version record.");
                    versions.Add(Encoding.BigEndianUnicode.GetString(table, offset, bytes));
                }
                string[] result = new string[versions.Count];
                versions.CopyTo(result);
                return result;
            }
            return new string[0];
        }
    }
}
'@
}

function Get-GalleryFontFamilyAvailability {
    param([string]$Family)
    if ($script:galleryFontFamilies -cnotcontains $Family) { throw "Family is outside the gallery diagnostic allowlist." }
    Initialize-GalleryFontProbe
    [SwiftWindowsUIGalleryFontProbe]::IsFamilyInstalled($Family)
}

function Resolve-GalleryProvenancePath {
    param([string]$Path)
    # Set-Location does not necessarily update Environment.CurrentDirectory.
    # Attribute the same file that PowerShell's executable invocation resolves.
    $provider = $null
    $drive = $null
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref]$provider, [ref]$drive)
    if ($provider.Name -ne "FileSystem") { throw "Gallery provenance requires a filesystem path." }
    [IO.Path]::GetFullPath($resolved)
}

function Get-GalleryFileFingerprint {
    param([string]$Path)
    $record = [ordered]@{ path = $Path; status = "unknown"; sha256 = $null; length = $null; lastWriteTimeUtc = $null; fileVersion = $null; error = $null }
    try {
        $record.path = Resolve-GalleryProvenancePath $Path
        if (-not (Test-Path -LiteralPath $record.path -PathType Leaf)) { $record.status = "missing"; return [pscustomobject]$record }
        $file = Get-Item -LiteralPath $record.path
        $record.length = $file.Length
        $record.lastWriteTimeUtc = $file.LastWriteTimeUtc.ToString("o")
        $record.fileVersion = $file.VersionInfo.FileVersion
        $record.sha256 = (Get-FileHash -LiteralPath $record.path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $record.status = "observed"
    } catch { $record.error = $_.Exception.Message }
    [pscustomobject]$record
}

function Get-GalleryRegisteredFontFiles {
    # Query known registration names directly, without enumerating the user's
    # font inventory. Styles remain within the six relevant family identities.
    $styles = @("", " Black", " Black Italic", " Bold", " Bold Italic", " Italic", " Light", " Light Italic", " Semibold", " Semibold Italic", " Semilight", " Semilight Italic")
    $stems = @("Segoe Fluent Icons", "Segoe MDL2 Assets", "Segoe UI Variable")
    foreach ($family in @("Segoe UI", "Segoe UI Variable Small", "Segoe UI Variable Text", "Segoe UI Variable Display")) {
        foreach ($style in $styles) { $stems += $family + $style }
    }
    $systemFonts = Join-Path $env:WINDIR "Fonts"
    $userFonts = Join-Path $env:LOCALAPPDATA "Microsoft/Windows/Fonts"
    $scopes = @(
        @{ key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"; base = $systemFonts },
        @{ key = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"; base = $userFonts }
    )
    $files = @{}
    $errors = @()
    foreach ($scope in $scopes) {
        if (-not (Test-Path -LiteralPath $scope.key)) { continue }
        try {
            $key = Get-Item -LiteralPath $scope.key -ErrorAction Stop
            foreach ($stem in $stems) {
                foreach ($suffix in @(" (TrueType)", " (OpenType)")) {
                    $registration = $stem + $suffix
                    $value = $key.GetValue($registration, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) { continue }
                    $path = [Environment]::ExpandEnvironmentVariables($value)
                    if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $scope.base $path }
                    $path = [IO.Path]::GetFullPath($path)
                    $insideFontDirectory = $false
                    foreach ($directory in @($systemFonts, $userFonts)) {
                        $prefix = [IO.Path]::GetFullPath($directory).TrimEnd([char[]]@('/', '\')) + [IO.Path]::DirectorySeparatorChar
                        if ($path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $insideFontDirectory = $true }
                    }
                    if (-not $insideFontDirectory -or [IO.Path]::GetExtension($path) -notin @(".ttf", ".otf", ".ttc")) {
                        $errors += "Registration '$registration' is outside the bounded font-file locations/types; file not inspected."
                        continue
                    }
                    $identity = $path.ToLowerInvariant()
                    if (-not $files.ContainsKey($identity)) {
                        $fingerprint = Get-GalleryFileFingerprint $path
                        $versions = @()
                        $versionError = $null
                        try { Initialize-GalleryFontProbe; $versions = @([SwiftWindowsUIGalleryFontProbe]::ReadFontVersions($path)) }
                        catch { $versionError = $_.Exception.Message }
                        $files[$identity] = [ordered]@{ file = $fingerprint; embeddedVersions = $versions; versionStatus = if ($versions.Count -gt 0) { "observed-embedded-name" } else { "unknown" }; versionError = $versionError; registrations = @() }
                    }
                    $files[$identity].registrations += [ordered]@{ scope = $scope.key; name = $registration }
                }
            }
        } catch { $errors += $_.Exception.Message }
    }
    [pscustomobject]@{
        resolution = "Allowlisted registry registrations under system/user font directories; not glyph-face ownership."
        files = @($files.Keys | Sort-Object | ForEach-Object { [pscustomobject]$files[$_] })
        errors = $errors
    }
}

function New-GalleryFontEnvironment {
    param(
        [AllowNull()]$ClassicOverride = [Environment]::GetEnvironmentVariable("SWIFT_WINDOWSUI_CLASSIC_UI_FONT", "Process"),
        [scriptblock]$ProbeFamily = { param($family) Get-GalleryFontFamilyAvailability $family },
        [scriptblock]$FontFiles = { Get-GalleryRegisteredFontFiles }
    )
    $families = @(foreach ($family in $script:galleryFontFamilies) {
        $available = $null
        $errorText = $null
        try {
            $available = & $ProbeFamily $family
            if ($null -ne $available -and $available -isnot [bool]) { throw "Font probe returned neither Bool nor unknown." }
        } catch { $available = $null; $errorText = $_.Exception.Message }
        [pscustomobject]@{ family = $family; installed = $available; status = if ($null -eq $available) { "unknown" } else { "observed" }; error = $errorText }
    })
    $variable = @($families | Select-Object -First 3)
    $choice = "unknown"
    if ($ClassicOverride -ceq "1" -or @($variable | Where-Object { $null -ne $_.installed -and -not $_.installed }).Count -gt 0) { $choice = "classic" }
    elseif (@($variable | Where-Object { $_.installed -eq $true }).Count -eq 3) { $choice = "variable" }
    try { $fontFilesRecord = & $FontFiles }
    catch { $fontFilesRecord = [pscustomobject]@{ files = @(); errors = @($_.Exception.Message); resolution = "unknown" } }
    [pscustomobject]@{
        probe = "Collector-process DirectWrite GetSystemFontCollection(false)/FindFamilyName; no glyph ownership inference."
        families = $families
        override = [ordered]@{ name = "SWIFT_WINDOWSUI_CLASSIC_UI_FONT"; value = $ClassicOverride; forcesClassic = ($ClassicOverride -ceq "1") }
        uiPolicy = [ordered]@{
            projectedChoice = $choice
            projectedFamilies = @(if ($choice -eq "variable") { $script:galleryFontFamilies | Select-Object -First 3 } elseif ($choice -eq "classic") { "Segoe UI" })
            observation = "Projection of the source policy, not observed glyph runs or custom Font families."
        }
        icons = [ordered]@{
            declaredPreference = @("Segoe Fluent Icons", "Segoe MDL2 Assets")
            perGlyphProbeResults = $null
            selectedFamily = $null
            actualGlyphFaces = $null
            observation = "The renderer probes each glyph against a missing-glyph sentinel. This diagnostic records family availability only; actual face ownership is not observed."
        }
        registeredFontFiles = $fontFilesRecord
    }
}

function Get-GallerySourceProvenance {
    param([string]$Root)
    $record = [ordered]@{ root = $Root; revision = $null; changes = @(); status = "unknown"; error = $null; executableBuildRevision = $null }
    try {
        $record.root = Resolve-GalleryProvenancePath $Root
        foreach ($name in @("GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS")) {
            if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name, "Process"))) { throw "Repository override $name prevents source attribution." }
        }
        $ErrorActionPreference = "Continue"
        $revision = @(& git --no-optional-locks -c core.fsmonitor=false -C $record.root rev-parse --verify HEAD 2>&1)
        if ($LASTEXITCODE -ne 0 -or $revision.Count -ne 1 -or $revision[0] -notmatch '^[0-9a-f]{40,64}$') { throw "Git revision is unavailable." }
        $changes = @(& git --no-optional-locks -c core.fsmonitor=false -C $record.root status --porcelain --untracked-files=normal 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Git worktree status is unavailable." }
        $record.revision = [string]$revision[0]
        $record.changes = @($changes | ForEach-Object { $_.ToString() })
        $record.status = "observed-checkout-only"
    } catch { $record.error = $_.Exception.Message }
    [pscustomobject]$record
}

function New-GalleryFontProvenance {
    param([string]$Executable, [string]$Root, [string]$CaptureStage)
    $os = [ordered]@{ description = [Environment]::OSVersion.VersionString; caption = $null; version = $null; build = $null; error = $null }
    try {
        $system = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $os.caption = $system.Caption; $os.version = $system.Version; $os.build = $system.BuildNumber
    } catch { $os.error = $_.Exception.Message }
    [pscustomobject]@{
        schemaVersion = 1
        invocationID = [Guid]::NewGuid().ToString("N")
        capturedAt = [DateTimeOffset]::UtcNow.ToString("o")
        stage = $CaptureStage
        qualification = [ordered]@{ status = "unqualified"; acceptedBaselineProfile = $null; reason = "Diagnostic only; no reviewed font-profile manifest is defined. Pixel comparison is reported separately." }
        renderer = [ordered]@{ declaredPath = "WinSwiftUIRendererSnapshotter / GPUIRawSceneRasterizer"; declaredDisplayScale = 1; actualGlyphFaceOwnership = "not-observed" }
        fonts = New-GalleryFontEnvironment
        os = $os
        process = [ordered]@{ is64Bit = [Environment]::Is64BitProcess; powershellVersion = $PSVersionTable.PSVersion.ToString() }
        runner = [ordered]@{ imageOS = $env:ImageOS; imageVersion = $env:ImageVersion; os = $env:RUNNER_OS; architecture = $env:RUNNER_ARCH }
        directWriteLibrary = Get-GalleryFileFingerprint (Join-Path ([Environment]::SystemDirectory) "dwrite.dll")
        directWriteLibraryObservation = "System library file; the gallery process's loaded-module path is not observed."
        source = Get-GallerySourceProvenance $Root
        executable = Get-GalleryFileFingerprint $Executable
        executableAssociation = "preexisting-file-not-attested-to-checkout"
        build = [ordered]@{ status = "not-requested"; exitCode = $null; executableAfter = $null }
        render = [ordered]@{ status = "not-requested"; exitCode = $null; requestedEntries = @(); outputDirectory = $null; imageAssociation = "not-established"; executableAfter = $null; executableUnchanged = $null }
    }
}

function Write-GalleryFontProvenance {
    param($Provenance, [string]$Path)
    $absolutePath = Resolve-GalleryProvenancePath $Path
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($absolutePath))
    $json = $Provenance | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($absolutePath, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

if ($MyInvocation.InvocationName -ne ".") {
    $ErrorActionPreference = "Stop"
    $provenance = New-GalleryFontProvenance -Executable $GalleryExe -Root $SourceRoot -CaptureStage $Stage
    Write-GalleryFontProvenance -Provenance $provenance -Path $OutputPath
    Write-Host "Gallery font provenance written to $OutputPath (unqualified; pixel gate unchanged)."
    exit 0
}
