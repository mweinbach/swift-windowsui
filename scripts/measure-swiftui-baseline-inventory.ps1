param(
    [Parameter(Mandatory)][string]$CaptureRoot,
    [string]$OutputDirectory,
    [ValidateRange(1024, 1073741824)][long]$SortChunkBytes = 16777216,
    [ValidateRange(2, 64)][int]$MergeFanIn = 16,
    [ValidateRange(1024, 134217728)][int]$MaximumRecordCharacters = 33554432
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "swiftui-baseline-common.ps1")
$capturePath = Resolve-SwiftUIBaselineFileSystemPath -Path $CaptureRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) ("artifacts/swiftui-baseline-benchmarks/" + [Guid]::NewGuid().ToString("N"))
}
$outputPath = Resolve-SwiftUIBaselineFileSystemPath -Path $OutputDirectory
# Conservatively reject case variants on every host, including the commonly
# case-insensitive macOS filesystem. The benchmark has no reason to write near
# its read-only source through a differently-cased spelling.
$comparison = [System.StringComparison]::OrdinalIgnoreCase
$capturePrefix = $capturePath.TrimEnd([char[]]"\/") + [System.IO.Path]::DirectorySeparatorChar
if ($outputPath.Equals($capturePath, $comparison) -or $outputPath.StartsWith($capturePrefix, $comparison)) {
    throw "Benchmark output must be outside the read-only source capture."
}
if (Test-Path -LiteralPath $outputPath) { throw "Benchmark output already exists; no evidence is overwritten." }
$manifestPath = Join-Path $capturePath "baseline-manifest.json"
$manifest = Read-SwiftUIBaselineManifest -Path $manifestPath
$exports = @(
    foreach ($target in $manifest.scope.targets) {
        foreach ($module in $manifest.scope.modules) {
            [pscustomobject]@{ module = $module; target = $target; directory = Join-Path $capturePath "graphs/$target/$module" }
        }
    }
)
[void][System.IO.Directory]::CreateDirectory($outputPath)
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$report = [ordered]@{
    schemaVersion = 1
    evidenceKind = "inventory-indexing-benchmark-only"
    status = "in-progress"
    sourceCapture = $capturePath
    sourceManifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    sourceCaptureWasModified = $false
    nativeExportPerformed = $false
    identityReviewPerformed = $false
    behaviorConformance = "not-verified"
    releaseQualified = $false
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    clrVersion = [System.Environment]::Version.ToString()
    startedAtUtc = [DateTime]::UtcNow.ToString("o")
    elapsedSeconds = $null
    peakWorkingSetBytes = $null
    peakPagedMemoryBytes = $null
    privateMemoryBytesAtEnd = $null
    memoryMetric = $null
    inventory = $null
    error = $null
    memoryMeasurementError = $null
}
$failure = $null
try {
    $report.inventory = Write-SwiftUIBaselineInventory -Manifest $manifest -CaptureRoot $capturePath -Exports $exports `
        -Path (Join-Path $outputPath "inventory.json") -SortChunkBytes $SortChunkBytes -MergeFanIn $MergeFanIn `
        -MaximumRecordCharacters $MaximumRecordCharacters
    $report.status = "indexed-not-capture-qualified"
} catch {
    $failure = $_
    $report.status = "failed"
    $report.error = $_.Exception.Message
} finally {
    $timer.Stop()
    $report.elapsedSeconds = $timer.Elapsed.TotalSeconds
    try {
        $memory = Get-SwiftUIBaselineProcessMemory
        $report.peakWorkingSetBytes = $memory.peakWorkingSetBytes
        $report.peakPagedMemoryBytes = $memory.peakPagedMemoryBytes
        $report.privateMemoryBytesAtEnd = $memory.privateMemoryBytesAtEnd
        $report.memoryMetric = $memory.metric
    } catch {
        $report.status = "failed"
        $report.memoryMeasurementError = $_.Exception.Message
        if ($null -eq $failure) { $failure = $_; $report.error = $_.Exception.Message }
    }
    Write-SwiftUIBaselineJson -Value $report -Path (Join-Path $outputPath "benchmark.json")
}
if ($null -ne $failure) { throw $failure }
Write-Host ("Indexed {0} graphs, {1} declarations, {2} relationships in {3:N2}s; peak working set {4:N1} MiB." -f `
    $report.inventory.counts.graphs, $report.inventory.counts.declarationOccurrences, $report.inventory.counts.relationshipOccurrences, `
    $report.elapsedSeconds, ($report.peakWorkingSetBytes / 1MB))
Write-Host "Benchmark evidence: $outputPath"
Write-Host "Source capture remains unchanged. Reindexing is not a native export, identity review, or behavior conformance."
