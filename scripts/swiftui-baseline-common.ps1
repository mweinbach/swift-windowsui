# Shared, platform-independent validation and indexing. Dot-sourcing this file
# does not run native tools, change the baseline manifest, or claim conformance.

function Write-SwiftUIBaselineJson {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)

    $json = ConvertTo-Json -InputObject $Value -Depth 100 -WarningAction Stop
    [System.IO.File]::WriteAllText($Path, $json + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Get-SwiftUIBaselineProperty {
    param($Value, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $Value) { return $null }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    # Do not let the pipeline turn an empty array into null or a singleton
    # array into a scalar; availability metadata must retain its JSON shape.
    return ,$property.Value
}

function Read-SwiftUIBaselineManifest {
    param([Parameter(Mandatory)][string]$Path)

    $manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1) { throw "Unsupported SwiftUI baseline schema version." }
    if ([string]::IsNullOrWhiteSpace($manifest.baselineId)) { throw "Baseline ID is required." }
    foreach ($field in @("xcodeVersion", "sdkVersion", "swiftCompilerMajorMinor")) {
        if ($manifest.toolchain.$field -notmatch '^\d+\.\d+(?:\.\d+)?$') {
            throw "Baseline toolchain.$field must be an explicit numeric release version."
        }
    }
    if ($manifest.toolchain.sdkName -cne "macosx" -or
        $manifest.toolchain.toolchainName -cne "XcodeDefault" -or
        $manifest.toolchain.swiftLanguageMode -cne "6") {
        throw "Baseline requires the macOS SDK, XcodeDefault toolchain, and Swift 6 language mode."
    }
    foreach ($field in @("modules", "allowedReexportedModules")) {
        $names = @($manifest.scope.$field)
        if ($names.Count -ne 2 -or $names -cnotcontains "SwiftUI" -or $names -cnotcontains "SwiftUICore") {
            throw "Baseline scope.$field must retain both SwiftUI and SwiftUICore."
        }
    }
    $expectedTargets = @("arm64-apple-macosx$($manifest.toolchain.sdkVersion)",
        "x86_64-apple-macosx$($manifest.toolchain.sdkVersion)")
    if (@($manifest.scope.targets).Count -ne 2) { throw "Both desktop architecture targets are required." }
    foreach ($target in $expectedTargets) {
        if ($manifest.scope.targets -cnotcontains $target) {
            throw "Missing complete-SDK target '$target'; the deployment floor is not an API ceiling."
        }
    }
    if ($manifest.scope.minimumAccessLevel -cne "public" -or $manifest.scope.includeSPISymbols -ne $false) {
        throw "Baseline extraction must request public API without SPI."
    }
    foreach ($field in @("preserveAvailabilityMetadata", "preserveExtensionGraphs",
            "preserveSynthesizedMembers", "preservePublicInterfacesAndImports")) {
        if ($manifest.scope.$field -ne $true) { throw "Baseline scope.$field must remain enabled." }
    }
    if ($null -eq $manifest.reviewedIdentity -or $null -eq $manifest.evidence) {
        throw "Baseline must state reviewed identity and evidence status explicitly."
    }
    return $manifest
}

function ConvertTo-SwiftUIBaselineIdentity {
    param(
        [Parameter(Mandatory)][string]$XcodeOutput,
        [Parameter(Mandatory)][string]$SDKVersion,
        [Parameter(Mandatory)][string]$SDKBuildVersion,
        [Parameter(Mandatory)][string]$SwiftOutput
    )

    $xcodeVersions = [regex]::Matches($XcodeOutput, '(?m)^Xcode (\d+\.\d+(?:\.\d+)?)[ \t]*\r?$')
    $xcodeBuilds = [regex]::Matches($XcodeOutput, '(?m)^Build version ([A-Za-z0-9]+)[ \t]*\r?$')
    # The swift driver can prepend its own version to the compiler's line.
    # Canonical identity starts at Apple Swift and retains the complete compiler
    # build suffix. Callers keep the original stdout/provenance receipt; this
    # derived field does not assert that two executables have identical bytes.
    $swiftVersions = [regex]::Matches($SwiftOutput, '(?m)^(?:swift-driver version: [^ \t\r\n]+[ \t]+)?(?<compilerLine>Apple Swift version (?<compilerVersion>\d+\.\d+(?:\.\d+)?)(?=[ \t(]|\r?$)[^\r\n]*)\r?$')
    $swiftHeaders = [regex]::Matches($SwiftOutput, '(?i)\bApple Swift version\b')
    if ($xcodeVersions.Count -ne 1 -or $xcodeBuilds.Count -ne 1) {
        throw "Cannot identify the Xcode release and build from xcodebuild -version."
    }
    if ($swiftVersions.Count -ne 1 -or $swiftHeaders.Count -ne 1 -or $SwiftOutput -match '(?i)DEVELOPMENT-SNAPSHOT|\bbeta\b') {
        throw "Expected one unambiguous released Apple Swift compiler identity from XcodeDefault."
    }
    if ($SDKVersion.Trim() -notmatch '^\d+\.\d+(?:\.\d+)?$' -or
        $SDKBuildVersion.Trim() -notmatch '^[A-Za-z0-9]+$') {
        throw "Cannot identify the macOS SDK version and build."
    }
    return [pscustomobject][ordered]@{
        xcodeVersion = $xcodeVersions[0].Groups[1].Value
        xcodeBuildVersion = $xcodeBuilds[0].Groups[1].Value
        sdkVersion = $SDKVersion.Trim()
        sdkBuildVersion = $SDKBuildVersion.Trim()
        swiftCompilerVersion = $swiftVersions[0].Groups['compilerVersion'].Value
        swiftCompilerVersionLine = $swiftVersions[0].Groups['compilerLine'].Value.TrimEnd()
    }
}

function Assert-SwiftUIBaselineIdentity {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)]$Identity,
        [switch]$RequireReviewedIdentity
    )

    foreach ($field in @("xcodeVersion", "sdkVersion")) {
        if ($Identity.$field -cne $Manifest.toolchain.$field) {
            throw "Wrong $field for $($Manifest.baselineId): expected '$($Manifest.toolchain.$field)', got '$($Identity.$field)'. Select the pinned Xcode installation using DEVELOPER_DIR; no fallback is allowed."
        }
    }
    $compilerParts = $Identity.swiftCompilerVersion.Split('.')
    $majorMinor = $compilerParts[0] + "." + $compilerParts[1]
    if ($majorMinor -cne $Manifest.toolchain.swiftCompilerMajorMinor) {
        throw "Wrong Swift compiler: expected Apple Swift $($Manifest.toolchain.swiftCompilerMajorMinor).x, got '$($Identity.swiftCompilerVersion)'."
    }
    $hasReviewedIdentity = $Manifest.reviewedIdentity.status -ceq "reviewed"
    foreach ($field in @("xcodeBuildVersion", "sdkBuildVersion", "swiftCompilerVersionLine")) {
        $expected = $Manifest.reviewedIdentity.$field
        if ([string]::IsNullOrWhiteSpace($expected)) {
            $hasReviewedIdentity = $false
        } elseif ($Identity.$field -cne $expected) {
            throw "Pinned identity mismatch for ${field}: expected '$expected', got '$($Identity.$field)'."
        }
    }
    if ($RequireReviewedIdentity -and -not $hasReviewedIdentity) {
        throw "Exact Xcode/SDK/compiler identity is awaiting actual capture and review. A version-matched candidate export cannot qualify the baseline."
    }
    return $hasReviewedIdentity
}

function Get-SwiftUIBaselineRelativePath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)

    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]"\/") + [System.IO.Path]::DirectorySeparatorChar
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $comparison = [System.StringComparison]::Ordinal
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $comparison = [System.StringComparison]::OrdinalIgnoreCase }
    if (-not $fullPath.StartsWith($rootPath, $comparison)) {
        throw "Path '$fullPath' is not contained in '$rootPath'."
    }
    return $fullPath.Substring($rootPath.Length).Replace('\', '/')
}

function Get-SwiftUIBaselineTextHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $algorithm.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
        return ([System.BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Resolve-SwiftUIBaselineFileSystemPath {
    param([Parameter(Mandatory)][string]$Path, [int]$LinkDepth = 0)

    if ($LinkDepth -gt 64) { throw "Too many filesystem aliases while resolving '$Path'." }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    $separators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $parts = $fullPath.Substring($root.Length).Split($separators, [System.StringSplitOptions]::RemoveEmptyEntries)
    $current = $root
    foreach ($part in $parts) {
        $candidate = Join-Path $current $part
        $item = $null
        try { $item = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop } catch {
            if ($_.CategoryInfo.Category -ne [System.Management.Automation.ErrorCategory]::ObjectNotFound) { throw }
        }
        if ($null -eq $item) {
            # A not-yet-created suffix has no aliases of its own. Its existing
            # ancestors have already been resolved before any output is made.
            $current = $candidate
            continue
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            $targetProperty = $item.PSObject.Properties["Target"]
            if ($null -eq $targetProperty -or [string]::IsNullOrEmpty([string]$targetProperty.Value)) {
                $targetProperty = $item.PSObject.Properties["LinkTarget"]
            }
            $targets = @($targetProperty.Value)
            if ($targets.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$targets[0])) {
                throw "Cannot resolve the filesystem alias '$candidate'; no benchmark output was created."
            }
            $target = [string]$targets[0]
            # PowerShell/.NET versions expose Windows junction targets with
            # either DOS or native path prefixes. Normalize only those prefixes.
            if ($target.StartsWith('\??\UNC\') -or $target.StartsWith('\\?\UNC\')) {
                $target = '\\' + $target.Substring(8)
            } elseif ($target.StartsWith('\??\') -or $target.StartsWith('\\?\')) {
                $target = $target.Substring(4)
                if ($target -notmatch '^[A-Za-z]:[\\/]') { throw "Unsupported filesystem alias target for '$candidate'." }
            }
            if (-not [System.IO.Path]::IsPathRooted($target)) {
                # $current is already the resolved parent. Split-Path can lose
                # the Unix root qualifier for /var -> private/var and return an
                # empty parent; filesystem combination must retain that root.
                $target = [System.IO.Path]::Combine($current, $target)
            }
            $current = Resolve-SwiftUIBaselineFileSystemPath -Path $target -LinkDepth ($LinkDepth + 1)
        } else { $current = [System.IO.Path]::GetFullPath($item.FullName) }
    }
    return [System.IO.Path]::GetFullPath($current)
}

function Initialize-SwiftUIBaselineProcessMemory {
    # This public Darwin ABI is used only to measure the current benchmark
    # process. It does not sample unrelated processes or change system settings.
    $source = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace SwiftUIBaseline.ProcessMemory {
    [StructLayout(LayoutKind.Explicit, Size = 144)]
    public struct DarwinRUsage64 {
        [FieldOffset(32)] public long MaximumResidentBytes;
    }
    public static class Native {
        public static string SourceHash;
        [DllImport("/usr/lib/libSystem.B.dylib", EntryPoint = "getrusage", SetLastError = true, CallingConvention = CallingConvention.Cdecl)]
        private static extern int GetResourceUsage(int who, out DarwinRUsage64 usage);
        public static long DarwinPeakResidentBytes(bool isMacOS) {
            if (!isMacOS || IntPtr.Size != 8) throw new PlatformNotSupportedException("Darwin peak RSS requires a 64-bit macOS process.");
            if (Marshal.SizeOf(typeof(DarwinRUsage64)) != 144 || Marshal.OffsetOf(typeof(DarwinRUsage64), "MaximumResidentBytes").ToInt64() != 32)
                throw new InvalidOperationException("Unexpected Darwin rusage ABI layout.");
            DarwinRUsage64 usage;
            if (GetResourceUsage(0, out usage) != 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "getrusage(RUSAGE_SELF) failed.");
            if (usage.MaximumResidentBytes <= 0) throw new InvalidOperationException("Darwin did not return a positive process peak RSS.");
            return usage.MaximumResidentBytes;
        }
    }
}
'@
    $sourceHash = Get-SwiftUIBaselineTextHash -Text $source
    if ($null -eq ("SwiftUIBaseline.ProcessMemory.Native" -as [type])) {
        Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
        [SwiftUIBaseline.ProcessMemory.Native]::SourceHash = $sourceHash
    } elseif ([SwiftUIBaseline.ProcessMemory.Native]::SourceHash -cne $sourceHash) {
        throw "The loaded process-memory adapter differs from this source. Start a fresh PowerShell process."
    }
}

function Get-SwiftUIBaselineProcessMemory {
    $process = [System.Diagnostics.Process]::GetCurrentProcess()
    try {
        $process.Refresh()
        $isDarwin = $PSVersionTable.PSVersion.Major -ge 7 -and $IsMacOS
        if ($isDarwin) {
            Initialize-SwiftUIBaselineProcessMemory
            $peak = [SwiftUIBaseline.ProcessMemory.Native]::DarwinPeakResidentBytes($true)
            $source = "Darwin getrusage(RUSAGE_SELF).ru_maxrss"
        } else {
            $peak = $process.PeakWorkingSet64
            $source = "System.Diagnostics.Process.PeakWorkingSet64"
        }
        if ($peak -le 0) { throw "This host does not provide a positive process peak RSS; current RSS is not substituted for peak memory." }
        $isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
        return [pscustomobject][ordered]@{
            peakWorkingSetBytes = $peak
            # These .NET fields are unset on macOS. Keep them unavailable, not
            # zero or a different physical-footprint metric under the same name.
            peakPagedMemoryBytes = $(if ($isWindowsHost) { $process.PeakPagedMemorySize64 } else { $null })
            privateMemoryBytesAtEnd = $(if ($isWindowsHost) { $process.PrivateMemorySize64 } else { $null })
            metric = [ordered]@{
                source = $source
                unit = "bytes"
                scope = "current benchmark process"
                kind = "kernel process peak; not sampled current RSS"
            }
        }
    } finally { $process.Dispose() }
}

function Get-SwiftUIBaselineInterfaceImports {
    param([Parameter(Mandatory)][string]$Text)

    # This is an evidence index, not a Swift conditional-compilation parser.
    # The unmodified interface is retained, including surrounding #if blocks.
    $pattern = '(?m)^[ \t]*(?<attributes>(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\r\n]*\))?[ \t]*(?:\r?\n[ \t]*)?)*)((?<access>public|internal|package|fileprivate|private)[ \t]+)?import[ \t]+(?:(?:typealias|struct|class|enum|protocol|let|var|func)[ \t]+)?(?<module>[A-Za-z_][A-Za-z0-9_]*)(?:\.[^\r\n ]+)?[^\r\n]*'
    $imports = [System.Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        $imports.Add([pscustomobject][ordered]@{
            line = 1 + [regex]::Matches($Text.Substring(0, $match.Index), "`n").Count
            module = $match.Groups["module"].Value
            exportedAttribute = $match.Groups["attributes"].Value -match '@_exported\b'
            access = $match.Groups["access"].Value
            declaration = $match.Value.Trim()
            conditionalCompilationEvaluated = $false
        })
    }
    return ,$imports.ToArray()
}

function Get-SwiftUIBaselineGraphInputs {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$CaptureRoot,
        [Parameter(Mandatory)][object[]]$Exports
    )

    $expectedPairs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($target in $Manifest.scope.targets) {
        foreach ($module in $Manifest.scope.modules) { [void]$expectedPairs.Add("$target/$module") }
    }
    $graphPaths = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($export in $Exports) {
        $pair = "$($export.target)/$($export.module)"
        if (-not $expectedPairs.Remove($pair)) { throw "Unexpected or duplicate module/target export '$pair'." }
        [void](Get-SwiftUIBaselineRelativePath -Root $CaptureRoot -Path $export.directory)
        $primaryGraph = Join-Path $export.directory "$($export.module).symbols.json"
        if (-not (Test-Path -LiteralPath $primaryGraph -PathType Leaf)) {
            throw "Missing primary symbol graph for '$pair'. No partial capture is accepted."
        }
        foreach ($file in Get-ChildItem -LiteralPath $export.directory -Filter '*.symbols.json' -File -Recurse) {
            $relativePath = Get-SwiftUIBaselineRelativePath -Root $CaptureRoot -Path $file.FullName
            if ($graphPaths.ContainsKey($relativePath)) { throw "Graph '$relativePath' belongs to multiple exports." }
            $graphPaths.Add($relativePath, [pscustomobject]@{ file = $file; export = $export; primary = ($file.FullName -ceq $primaryGraph) })
        }
    }
    if ($expectedPairs.Count -ne 0) { throw "Missing module/target exports: $([string]::Join(', ', $expectedPairs))." }

    [string[]]$orderedPaths = @($graphPaths.Keys)
    [System.Array]::Sort($orderedPaths, [System.StringComparer]::Ordinal)
    $inputs = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $orderedPaths) {
        $entry = $graphPaths[$path]
        $inputs.Add([pscustomobject]@{
            path = $entry.file.FullName
            relativePath = $path
            requestedModule = $entry.export.module
            target = $entry.export.target
            primary = $entry.primary
        })
    }
    return ,$inputs.ToArray()
}

function Write-SwiftUIBaselineInventory {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$CaptureRoot,
        [Parameter(Mandatory)][object[]]$Exports,
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1024, 1073741824)][long]$SortChunkBytes = 16777216,
        [ValidateRange(2, 64)][int]$MergeFanIn = 16,
        [ValidateRange(1024, 134217728)][int]$MaximumRecordCharacters = 33554432
    )

    $entries = Get-SwiftUIBaselineGraphInputs -Manifest $Manifest -CaptureRoot $CaptureRoot -Exports $Exports
    . (Join-Path $PSScriptRoot "swiftui-baseline-streaming.ps1")
    Initialize-SwiftUIBaselineStreaming
    $inputs = [System.Collections.Generic.List[SwiftUIBaseline.Streaming.GraphInput]]::new()
    foreach ($entry in $entries) {
        $graphInput = [SwiftUIBaseline.Streaming.GraphInput]::new()
        $graphInput.Path = $entry.path
        $graphInput.RelativePath = $entry.relativePath
        $graphInput.RequestedModule = $entry.requestedModule
        $graphInput.Target = $entry.target
        $graphInput.Primary = $entry.primary
        $inputs.Add($graphInput)
    }
    $summary = [SwiftUIBaseline.Streaming.InventoryWriter]::Write(
        $Manifest.baselineId, $inputs.ToArray(), [System.IO.Path]::GetFullPath($Path),
        $SortChunkBytes, $MergeFanIn, $MaximumRecordCharacters)
    # This is deliberately a compact result. Never deserialize inventory.json
    # here or hand the complete inventory to ConvertTo-Json in the exporter.
    return [pscustomobject][ordered]@{
        path = [System.IO.Path]::GetFullPath($Path)
        sha256 = $summary.InventorySha256
        graphSetSha256 = $summary.GraphSetSha256
        counts = [ordered]@{
            graphs = $summary.Graphs
            preciseSymbols = $summary.PreciseSymbols
            declarationOccurrences = $summary.DeclarationOccurrences
            relationshipOccurrences = $summary.RelationshipOccurrences
        }
        indexing = [ordered]@{
            implementation = "bounded-json-records-and-external-ordinal-index-v1"
            sourceSha256 = [SwiftUIBaseline.Streaming.InventoryWriter]::SourceHash
            powerShellVersion = $PSVersionTable.PSVersion.ToString()
            clrVersion = [System.Environment]::Version.ToString()
            sortChunkBytes = $SortChunkBytes
            mergeFanIn = $MergeFanIn
            maximumRecordCharacters = $MaximumRecordCharacters
            inputBytes = $summary.InputBytes
            outputBytes = $summary.OutputBytes
            largestRecordCharacters = $summary.LargestRecordCharacters
            peakBufferedIndexEstimatedBytes = $summary.PeakBufferedIndexBytes
            peakBufferedIndexRecords = $summary.PeakBufferedIndexRecords
            initialSortRuns = $summary.InitialSortRuns
            mergePasses = $summary.MergePasses
            peakOpenRunReaders = $summary.PeakOpenRunReaders
            largestOccurrenceGroup = $summary.LargestOccurrenceGroup
        }
    }
}

function New-SwiftUIBaselineInventory {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$CaptureRoot,
        [Parameter(Mandatory)][object[]]$Exports
    )

    # Compatibility convenience for small synthetic fixtures only. The native
    # exporter uses Write-SwiftUIBaselineInventory and never materializes a DOM.
    $entries = Get-SwiftUIBaselineGraphInputs -Manifest $Manifest -CaptureRoot $CaptureRoot -Exports $Exports
    [long]$inputBytes = 0
    foreach ($entry in $entries) { $inputBytes += ([System.IO.FileInfo]$entry.path).Length }
    if ($inputBytes -gt 16777216) {
        throw "Object-returning inventory is limited to 16 MiB synthetic fixtures. Use Write-SwiftUIBaselineInventory for complete SDK graphs."
    }
    $fixtureDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("swiftui-small-inventory-" + [Guid]::NewGuid().ToString("N"))
    if (Test-Path -LiteralPath $fixtureDirectory) { throw "Fixture inventory directory already exists." }
    [void][System.IO.Directory]::CreateDirectory($fixtureDirectory)
    $fixturePath = Join-Path $fixtureDirectory "inventory.json"
    try {
        $summary = Write-SwiftUIBaselineInventory -Manifest $Manifest -CaptureRoot $CaptureRoot -Exports $Exports -Path $fixturePath
        if ($summary.indexing.outputBytes -gt 16777216) {
            throw "Object-returning inventory exceeded 16 MiB. Use the complete file from Write-SwiftUIBaselineInventory instead."
        }
        return (Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } finally {
        # No recursive removal: only our exact output file and now-empty GUID
        # directory are owned by this small-fixture convenience wrapper.
        if (Test-Path -LiteralPath $fixturePath -PathType Leaf) { [System.IO.File]::Delete($fixturePath) }
        [System.IO.Directory]::Delete($fixtureDirectory, $false)
    }
}
