<#
.SYNOPSIS
Checks bounded audit memory with a streamed synthetic repeated-identifier group.
.DESCRIPTION
-Large creates two individual graphs larger than a CLR string can hold and an
inventory larger than 2 GiB. It needs about 10 GiB of free disk space. Neither
graphs nor inventory are loaded as strings or object graphs. Process peak
includes fixture generation, inventory creation, the audit and its checks.
#>
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Large,
    [ValidateRange(128, 4096)][int]$MaximumPeakWorkingSetMiB = 768
)
$ErrorActionPreference = "Stop"
. (Join-Path $RepositoryRoot "scripts/swiftui-api-audit-test-fixtures.ps1")
. (Join-Path $RepositoryRoot "scripts/swiftui-api-audit-common.ps1")
$root = Join-Path $RepositoryRoot ("artifacts/swiftui-api-audit-memory-tests/" + [Guid]::NewGuid().ToString("N"))
[void][IO.Directory]::CreateDirectory($root)
$script:AuditMemoryAssertions = 0
function Assert-AuditMemory {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw "Audit memory regression: $Message" }
    $script:AuditMemoryAssertions++
}
function Count-AuditMemoryLines {
    param([string]$Path)
    # This reads only generated NDJSON, whose individual records are bounded.
    # Never point this helper at a symbol graph or the single-line inventory.
    if (-not $Path.EndsWith(".ndjson", [StringComparison]::Ordinal)) { throw "Expected generated NDJSON." }
    $reader = [IO.StreamReader]::new($Path, [Text.UTF8Encoding]::new($false, $true))
    [long]$count = 0
    try { while ($null -ne $reader.ReadLine()) { $count++ } } finally { $reader.Dispose() }
    return $count
}
$count = 4000
$payload = 1024
if ($Large) { $count = 160000; $payload = 8192 }
[long]$estimatedBytes = [long]$count * $payload * 2 * 4 + 512MB
$drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))
Assert-AuditMemory ($drive.AvailableFreeSpace -gt $estimatedBytes) "fixture/audit have sufficient owned scratch disk space"
$report = [ordered]@{
    schemaVersion = 1
    evidenceKind = "synthetic-api-audit-memory-regression-only"
    status = "running"
    large = [bool]$Large
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    processArchitecture = [IntPtr]::Size * 8
    nativeExportPerformed = $false
    behaviorConformanceAssessed = $false
    repeatedSymbolsPerPrimaryGraph = $count
    payloadCharacters = $payload
    fixtureGenerationSeconds = $null
    auditSeconds = $null
    sourceInventoryBytes = $null
    largestGraphBytes = $null
    ledgerBytes = $null
    counts = $null
    largestOccurrenceGroup = $null
    initialSortRuns = $null
    mergePasses = $null
    peakWorkingSetBytes = $null
    memoryMetric = $null
    memoryScope = "current test process including fixture generation, inventory creation, audit and checks"
    maximumPeakWorkingSetMiB = $MaximumPeakWorkingSetMiB
    assertions = $null
    error = $null
}
$failure = $null
try {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $fixture = New-SwiftUIAuditTestCapture -Root (Join-Path $root "synthetic-capture") -ManifestPath (Join-Path $RepositoryRoot "docs/swiftui-baseline.json") -RepeatedSymbols $count -SymbolPayloadCharacters $payload
    $timer.Stop(); $report.fixtureGenerationSeconds = $timer.Elapsed.TotalSeconds
    $captureHashBefore = (Get-FileHash -LiteralPath $fixture.CapturePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $report.sourceInventoryBytes = (Get-Item -LiteralPath $fixture.InventoryPath).Length
    $graphFiles = @(Get-ChildItem -LiteralPath (Join-Path $fixture.Root "graphs") -File -Recurse -Filter "*.symbols.json")
    $report.largestGraphBytes = ($graphFiles | Measure-Object Length -Maximum).Maximum
    Assert-AuditMemory ($graphFiles.Count -eq 6) "all target/module/extension partitions are present"
    if ($Large) {
        Assert-AuditMemory ($report.largestGraphBytes -gt 1073741823) "an individual ASCII graph exceeds the CLR string ceiling"
        Assert-AuditMemory ($report.sourceInventoryBytes -gt [int]::MaxValue) "the inventory exceeds a signed 32-bit byte count"
    } else {
        Assert-AuditMemory ($report.sourceInventoryBytes -gt 8MB) "default fixture exercises more than trivial records"
    }
    $output = Join-Path $root "ledger"
    $timer.Restart()
    $created = & (Join-Path $RepositoryRoot "scripts/build-swiftui-api-audit.ps1") -CaptureRoot $fixture.Root -OutputDirectory $output -SortChunkBytes 65536 -MergeFanIn 2
    $timer.Stop(); $report.auditSeconds = $timer.Elapsed.TotalSeconds
    $audit = Read-SwiftUIAuditTestSmallJson -Path $created.manifestPath
    $report.counts = $audit.counts
    $report.ledgerBytes = $audit.streaming.ledgerBytes
    $report.largestOccurrenceGroup = $audit.streaming.largestOccurrenceGroup
    $report.initialSortRuns = $audit.streaming.initialSortRuns
    $report.mergePasses = $audit.streaming.mergePasses
    Assert-AuditMemory ($audit.counts.preciseIdentifiers -eq $fixture.Counts.preciseSymbols) "all identities survive many disk sort runs"
    Assert-AuditMemory ($audit.counts.declarationOccurrences -eq $fixture.Counts.declarationOccurrences) "every repeated occurrence survives"
    Assert-AuditMemory ($audit.counts.relationshipOccurrences -eq $fixture.Counts.relationshipOccurrences) "relationships survive independently of groups"
    Assert-AuditMemory ($audit.streaming.largestOccurrenceGroup -eq [long]$count * 2) "the large identifier group was not gathered or truncated"
    Assert-AuditMemory ($audit.streaming.initialSortRuns -gt 1 -and $audit.streaming.mergePasses -gt 0) "external merge is exercised"
    Assert-AuditMemory ($audit.streaming.peakOpenRunReaders -le 2) "merge fan-in remains bounded"
    Assert-AuditMemory ((Count-AuditMemoryLines (Join-Path $output "occurrences.ndjson")) -eq $fixture.Counts.declarationOccurrences) "actual occurrence line count matches the complete capture"
    Assert-AuditMemory ((Count-AuditMemoryLines (Join-Path $output "identities.ndjson")) -eq $fixture.Counts.preciseSymbols) "there is one actual line per identity"
    Assert-AuditMemory ((Count-AuditMemoryLines (Join-Path $output "relationships.ndjson")) -eq $fixture.Counts.relationshipOccurrences) "actual relationship line count matches the complete capture"
    $identityRows = Get-Content -LiteralPath (Join-Path $output "identities.ndjson") -Encoding UTF8
    $hot = @($identityRows | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object preciseIdentifier -CEQ $fixture.SymbolIds.Repeated)
    Assert-AuditMemory ($hot.Count -eq 1 -and $hot[0].occurrenceCount -eq [long]$count * 2) "a repeated identifier has one identity record and all occurrences"
    $hashLines = [System.Collections.Generic.List[string]]::new()
    foreach ($graph in $graphFiles) {
        $path = Get-SwiftUIBaselineRelativePath -Root $fixture.Root -Path $graph.FullName
        $hashLines.Add($path + [char]9 + (Get-FileHash -LiteralPath $graph.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + [char]10)
    }
    [string[]]$orderedLines = $hashLines.ToArray()
    [Array]::Sort($orderedLines, [StringComparer]::Ordinal)
    Assert-AuditMemory ((Get-SwiftUIBaselineTextHash -Text ([string]::Join("", $orderedLines))) -ceq $audit.sourceCapture.graphSetSha256) "independent raw graph rehash matches after audit"
    Assert-AuditMemory ((Get-FileHash -LiteralPath $fixture.InventoryPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $audit.sourceCapture.inventorySha256) "independent inventory rehash matches after audit"
    Assert-AuditMemory ((Get-FileHash -LiteralPath $fixture.CapturePath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $captureHashBefore) "successful source capture remains unchanged"
    Assert-AuditMemory ($audit.reviewStatus -ceq "unreviewed" -and -not $audit.authority.behaviorConformanceAssessed) "scale tests cannot promote API or behavior review"
    $memory = Get-SwiftUIBaselineProcessMemory
    $report.peakWorkingSetBytes = $memory.peakWorkingSetBytes
    $report.memoryMetric = $memory.metric
    Assert-AuditMemory ($memory.peakWorkingSetBytes -gt 0 -and $memory.metric.unit -ceq "bytes") "actual process peak has an explicit metric and byte unit"
    Assert-AuditMemory ($memory.peakWorkingSetBytes -le [long]$MaximumPeakWorkingSetMiB * 1MB) "peak process memory stays below the explicit regression budget"
    $report.status = "passed"
} catch {
    $failure = $_
    $report.status = "failed"
    $report.error = $_.Exception.Message
} finally {
    $report.assertions = $script:AuditMemoryAssertions
    Write-SwiftUIBaselineJson -Value $report -Path (Join-Path $root "memory-results.json")
}
if ($null -ne $failure) { throw $failure }
Write-Host ("Audit memory tests passed {0} assertions; inventory {1:N0} bytes, peak process memory {2:N1} MiB." -f $report.assertions, $report.sourceInventoryBytes, ($report.peakWorkingSetBytes / 1MB))
Write-Host "Evidence: $root"
