param(
    [switch]$Large,
    [ValidateRange(128, 4096)][int]$MaximumPeakWorkingSetMiB = 768
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "swiftui-baseline-common.ps1")
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ("artifacts/swiftui-baseline-memory-tests/" + [Guid]::NewGuid().ToString("N"))
$captureRoot = Join-Path $testRoot "synthetic-capture"
[void][System.IO.Directory]::CreateDirectory($captureRoot)
$manifestPath = Join-Path $repoRoot "docs/swiftui-baseline.json"
$manifest = Read-SwiftUIBaselineManifest -Path $manifestPath
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $captureRoot "baseline-manifest.json")
$symbolCount = 4000
$payloadCharacters = 4096
if ($Large) { $symbolCount = 160000; $payloadCharacters = 8192 }
$payload = 'x' * $payloadCharacters
$largeGraph = $null
$strictUTF8 = [System.Text.UTF8Encoding]::new($false, $true)

# Generate sequentially. Even the >1 GB fixture is never a PowerShell string
# or object graph. The shared ID spans every sort run and must not be gathered
# into an in-memory occurrence array when the final inventory is written.
$first = $true
foreach ($target in $manifest.scope.targets) {
    foreach ($module in $manifest.scope.modules) {
        $directory = Join-Path $captureRoot "graphs/$target/$module"
        [void][System.IO.Directory]::CreateDirectory($directory)
        $graphPath = Join-Path $directory "$module.symbols.json"
        $architecture = $target.Split('-')[0]
        if ($architecture -ceq "arm64") { $architecture = "aarch64" }
        $count = 1
        if ($first) { $count = $symbolCount; $largeGraph = $graphPath }
        $writer = [System.IO.StreamWriter]::new([System.IO.FileStream]::new($graphPath, [System.IO.FileMode]::CreateNew), $strictUTF8, 65536)
        try {
            $writer.Write('{"metadata":{"generator":"Synthetic memory regression; not an SDK export"},"module":{"name":"' + $module + '","platform":{"architecture":"' + $architecture + '","operatingSystem":{"name":"macosx"}}},"symbols":[')
            for ($index = 0; $index -lt $count; $index++) {
                if ($index -ne 0) { $writer.Write(',') }
                $identifier = "s:memoryHot"
                if ($index % 2 -ne 0) { $identifier = "s:memory" + ($count - $index).ToString("D8", [Globalization.CultureInfo]::InvariantCulture) }
                $writer.Write('{"identifier":{"precise":"' + $identifier + '","interfaceLanguage":"swift"},"names":{"title":"')
                if ($first) { $writer.Write($payload) } else { $writer.Write('small') }
                $writer.Write('"},"availability":[{"domain":"macOS","futureField":{"nested":[null,[],true]}}]}')
            }
            $writer.Write('],"relationships":[')
            if ($first) {
                for ($index = 0; $index -lt $count; $index++) {
                    if ($index -ne 0) { $writer.Write(',') }
                    $writer.Write('{"kind":"conformsTo","source":"s:memoryHot","target":"s:External","futureField":' + $index.ToString([Globalization.CultureInfo]::InvariantCulture) + '}')
                }
            }
            $writer.Write(']}')
        } finally { $writer.Dispose() }
        $first = $false
    }
}

$originalHash = (Get-FileHash -LiteralPath $largeGraph -Algorithm SHA256).Hash.ToLowerInvariant()
$graphBytes = ([System.IO.FileInfo]$largeGraph).Length
if ($Large -and $graphBytes -le 1073741824) { throw "Large regression must exceed the single CLR UTF-16 string byte limit." }
$objectAPIRejected = $false
$exports = @(foreach ($target in $manifest.scope.targets) {
    foreach ($module in $manifest.scope.modules) {
        [pscustomobject]@{ target = $target; module = $module; directory = Join-Path $captureRoot "graphs/$target/$module" }
    }
})
try { [void](New-SwiftUIBaselineInventory -Manifest $manifest -CaptureRoot $captureRoot -Exports $exports) } catch {
    if ($_.Exception.Message -notmatch 'Object-returning inventory is limited') { throw }
    $objectAPIRejected = $true
}
if (-not $objectAPIRejected) { throw "Large input must never enter the fixture-only object-returning API." }
$benchmarkOutput = Join-Path $testRoot "index"
$benchmarkScript = Join-Path $PSScriptRoot "measure-swiftui-baseline-inventory.ps1"
$childCommand = "& '" + $benchmarkScript.Replace("'", "''") + "' -CaptureRoot '" + $captureRoot.Replace("'", "''") +
    "' -OutputDirectory '" + $benchmarkOutput.Replace("'", "''") + "' -SortChunkBytes 131072 -MergeFanIn 2"
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
$executable = "pwsh"
if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
    $executable = "pwsh.exe"
    if ($PSVersionTable.PSVersion.Major -lt 6) { $executable = "powershell.exe" }
}
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = Join-Path $PSHOME $executable
$startInfo.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand " + $encodedCommand
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$child = [System.Diagnostics.Process]::new()
$child.StartInfo = $startInfo
$waitTimer = [System.Diagnostics.Stopwatch]::StartNew()
try {
    [void]$child.Start()
    $stdout = $child.StandardOutput.ReadToEndAsync()
    $stderr = $child.StandardError.ReadToEndAsync()
    while (-not $child.WaitForExit(1000)) {
        if ($waitTimer.Elapsed.TotalMinutes -gt 10) {
            $child.Kill()
            $child.WaitForExit()
            throw "Inventory memory regression timed out; no reduced fixture was substituted."
        }
    }
    $output = $stdout.GetAwaiter().GetResult()
    $errorOutput = $stderr.GetAwaiter().GetResult()
    if ($child.ExitCode -ne 0) { throw "Inventory memory regression failed: $errorOutput $output" }
} finally { $waitTimer.Stop(); $child.Dispose() }

$report = Get-Content -LiteralPath (Join-Path $benchmarkOutput "benchmark.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$summary = $report.inventory
$assertions = [ordered]@{
    completed = ($report.status -ceq "indexed-not-capture-qualified")
    allGraphs = ($summary.counts.graphs -eq 4)
    allDeclarations = ($summary.counts.declarationOccurrences -eq $symbolCount + 3)
    allRelationships = ($summary.counts.relationshipOccurrences -eq $symbolCount)
    allPreciseIDs = ($summary.counts.preciseSymbols -eq $symbolCount / 2 + 1)
    entireHotGroup = ($summary.indexing.largestOccurrenceGroup -eq $symbolCount / 2 + 3)
    boundedSortBuffer = ($summary.indexing.peakBufferedIndexEstimatedBytes -le 131072)
    multipleRuns = ($summary.indexing.initialSortRuns -gt 2)
    multipleMergePasses = ($summary.indexing.mergePasses -ge 2)
    boundedReaders = ($summary.indexing.peakOpenRunReaders -eq 2)
    measuredPeak = ($report.peakWorkingSetBytes -gt 0)
    peakMetricProvenance = ($report.memoryMetric.unit -ceq "bytes" -and $report.memoryMetric.kind -ceq "kernel process peak; not sampled current RSS")
    boundedProcessMemory = ($report.peakWorkingSetBytes -le $MaximumPeakWorkingSetMiB * 1MB)
    originalUnchanged = ((Get-FileHash -LiteralPath $largeGraph -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $originalHash)
    outputHash = ((Get-FileHash -LiteralPath (Join-Path $benchmarkOutput "inventory.json") -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $summary.sha256)
    noScratch = (@(Get-ChildItem -LiteralPath $benchmarkOutput -Directory -Force -Filter '.swiftui-index-*').Count -eq 0)
    noCapturePromotion = (-not $report.nativeExportPerformed -and -not $report.identityReviewPerformed -and -not $report.releaseQualified)
    objectAPIGuard = $objectAPIRejected
}
Write-SwiftUIBaselineJson -Path (Join-Path $testRoot "memory-regression.json") -Value ([ordered]@{
    syntheticOnly = $true
    large = [bool]$Large
    graphBytes = $graphBytes
    declarations = $symbolCount + 3
    maximumPeakWorkingSetMiB = $MaximumPeakWorkingSetMiB
    benchmark = "index/benchmark.json"
    assertions = $assertions
})
foreach ($name in $assertions.Keys) {
    if (-not $assertions[$name]) { throw "Inventory memory regression failed: $name. Evidence: $testRoot" }
}
Write-Host ("SwiftUI inventory memory regression passed {0} assertions ({1:N1} MiB graph, {2:N1} MiB peak working set)." -f `
    $assertions.Count, ($graphBytes / 1MB), ($report.peakWorkingSetBytes / 1MB))
Write-Host "Synthetic evidence: $testRoot"
Write-Host "Peak metric: $($report.memoryMetric.source) (bytes, current benchmark process)."
