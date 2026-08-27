<#
.SYNOPSIS
Creates an immutable, entirely unreviewed API audit ledger from a successful
pinned SwiftUI candidate capture.
.DESCRIPTION
No SDK export, Windows module build, source matcher or conformance assessment
runs. Raw graph records and the existing inventory are streamed and reconciled.
A failed capture is never accepted, including a failed capture reindexed later.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CaptureRoot,
    [string]$OutputDirectory,
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "docs/swiftui-baseline.json"),
    [ValidateSet("view-builder", "binding-projections", "image-resizing", "long-press", "file-export")]
    [string[]]$QueueFamily = @("view-builder", "binding-projections", "image-resizing", "long-press", "file-export"),
    [ValidateRange(1024, 1073741824)][long]$SortChunkBytes = 16777216,
    [ValidateRange(2, 64)][int]$MergeFanIn = 16,
    [ValidateRange(1024, 134217728)][int]$MaximumRecordCharacters = 33554432,
    [ValidateRange(1024, 134217728)][long]$MaximumMetadataBytes = 16777216
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "swiftui-api-audit-common.ps1")
. (Join-Path $PSScriptRoot "swiftui-baseline-streaming.ps1")
$capture = Read-SwiftUIAuditCapture -CaptureRoot $CaptureRoot -ManifestPath $ManifestPath -MaximumMetadataBytes $MaximumMetadataBytes

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) ("artifacts/swiftui-api-audit/" + [Guid]::NewGuid().ToString("N"))
}
$outputPath = Resolve-SwiftUIBaselineFileSystemPath -Path $OutputDirectory
$sourcePath = $capture.captureRoot
$comparison = [StringComparison]::OrdinalIgnoreCase
$sourcePrefix = $sourcePath.TrimEnd([char[]]"\/") + [System.IO.Path]::DirectorySeparatorChar
if ($outputPath.Equals($sourcePath, $comparison) -or $outputPath.StartsWith($sourcePrefix, $comparison)) {
    throw "Audit output must be outside the read-only source capture."
}
if (Test-Path -LiteralPath $outputPath) { throw "Audit output already exists; immutable evidence is never overwritten." }
$outputParent = [System.IO.Path]::GetDirectoryName($outputPath)
if ([string]::IsNullOrWhiteSpace($outputParent)) { throw "Audit output requires a parent directory." }
[void][System.IO.Directory]::CreateDirectory($outputParent)
$stagingLeaf = ".swiftui-api-audit-" + [Guid]::NewGuid().ToString("N")
$stagingPath = Join-Path $outputParent $stagingLeaf
if (Test-Path -LiteralPath $stagingPath) { throw "Audit staging directory already exists." }
[void][System.IO.Directory]::CreateDirectory($stagingPath)
$failure = $null
$published = $false

try {
    if ((Resolve-SwiftUIBaselineFileSystemPath -Path $stagingPath) -cne [System.IO.Path]::GetFullPath($stagingPath)) {
        throw "Audit staging directory must not be substituted by a filesystem alias."
    }
    Initialize-SwiftUIBaselineStreaming
    $options = [SwiftUIBaseline.Streaming.AuditLedgerOptions]::new()
    $options.BaselineId = $capture.baselineManifest.baselineId
    $options.InventoryPath = $capture.inventoryPath
    $options.InventorySha256 = $capture.inventorySha256
    $options.GraphSetSha256 = $capture.capture.inventory.graphSetSha256
    $options.ExpectedGraphs = $capture.capture.inventory.counts.graphs
    $options.ExpectedPreciseSymbols = $capture.capture.inventory.counts.preciseSymbols
    $options.ExpectedDeclarations = $capture.capture.inventory.counts.declarationOccurrences
    $options.ExpectedRelationships = $capture.capture.inventory.counts.relationshipOccurrences
    $options.OutputDirectory = $stagingPath
    $options.SortChunkBytes = $SortChunkBytes
    $options.MergeFanIn = $MergeFanIn
    $options.MaximumRecordCharacters = $MaximumRecordCharacters
    $queueNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($family in $QueueFamily) { [void]$queueNames.Add($family) }
    [string[]]$selectedQueues = @($queueNames)
    [Array]::Sort($selectedQueues, [StringComparer]::Ordinal)
    $options.QueueFamilies = $selectedQueues

    $graphs = [System.Collections.Generic.List[SwiftUIBaseline.Streaming.GraphInput]]::new()
    foreach ($entry in $capture.graphInputs) {
        $graph = [SwiftUIBaseline.Streaming.GraphInput]::new()
        $graph.Path = $entry.path
        $graph.RelativePath = $entry.relativePath
        $graph.RequestedModule = $entry.requestedModule
        $graph.Target = $entry.target
        $graph.Primary = $entry.primary
        $graphs.Add($graph)
    }
    $options.Graphs = $graphs.ToArray()
    foreach ($kind in @("Interfaces", "Overlays")) {
        $records = $capture.publicInterfaces
        if ($kind -ceq "Overlays") { $records = $capture.crossImportDefinitions }
        $textInputs = [System.Collections.Generic.List[SwiftUIBaseline.Streaming.AuditTextInput]]::new()
        $recordsByPath = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        foreach ($entry in $records) {
            $recordsByPath.Add($entry.relativePath, $entry)
        }
        [string[]]$recordPaths = @($recordsByPath.Keys)
        [Array]::Sort($recordPaths, [StringComparer]::Ordinal)
        foreach ($recordPath in $recordPaths) {
            $entry = $recordsByPath[$recordPath]
            $textInput = [SwiftUIBaseline.Streaming.AuditTextInput]::new()
            $textInput.Path = $entry.path
            $textInput.RelativePath = $entry.relativePath
            $textInput.Module = $entry.record.module
            $textInput.Sha256 = $entry.record.sha256
            $textInput.CaptureRecordJson = ConvertTo-Json -InputObject $entry.record -Depth 100 -Compress -WarningAction Stop
            $textInputs.Add($textInput)
        }
        $options.$kind = $textInputs.ToArray()
    }
    $result = [SwiftUIBaseline.Streaming.AuditLedgerWriter]::Write($options)

    # Retain authoritative small metadata/interface bytes instead of treating
    # PowerShell's parsed copies as lossless representations of unknown fields.
    $copiedInputs = [System.Collections.Generic.List[object]]::new()
    $metadataRoot = Join-Path $stagingPath "source-metadata"
    [void][System.IO.Directory]::CreateDirectory($metadataRoot)
    foreach ($inputFile in $capture.inputFiles) {
        $relativeInput = $inputFile.relativePath
        if ($inputFile.kind -ceq "expected-baseline-manifest") { $relativeInput = "expected-baseline-manifest.json" }
        if ([string]::IsNullOrWhiteSpace($relativeInput)) { throw "An input file has no audited metadata destination." }
        $destination = Join-Path $metadataRoot $relativeInput
        [void](Get-SwiftUIBaselineRelativePath -Root $metadataRoot -Path $destination)
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destination))
        [System.IO.File]::Copy($inputFile.path, $destination, $false)
        $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -cne $inputFile.sha256) { throw "Source metadata changed while copying '$($inputFile.relativePath)'." }
        $copiedInputs.Add([ordered]@{
            path = "source-metadata/" + $relativeInput
            sha256 = $hash
            bytes = ([System.IO.FileInfo]$destination).Length
            kind = $inputFile.kind
        })
    }
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $result.RecordFiles) {
        $path = Join-Path $stagingPath $name
        $files.Add([ordered]@{
            path = $name
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            bytes = ([System.IO.FileInfo]$path).Length
        })
    }
    $manifest = [ordered]@{
        schemaVersion = 1
        evidenceKind = "unreviewed-native-api-audit-ledger"
        status = "awaiting-declaration-interface-and-behavior-review"
        reviewStatus = "unreviewed"
        baselineId = $capture.baselineManifest.baselineId
        createdAtUtc = [DateTime]::UtcNow.ToString("o")
        sourceCapture = [ordered]@{
            path = $sourcePath
            status = $capture.capture.status
            captureManifestSha256 = $capture.captureSha256
            captureStatusSha256 = $capture.statusSha256
            baselineManifestSha256 = $capture.baselineManifestSha256
            expectedBaselineManifestSha256 = $capture.expectedBaselineSha256
            inventorySha256 = $result.Inventory.InventorySha256
            graphSetSha256 = $result.Inventory.GraphSetSha256
            observedExtractorIdentity = $capture.capture.observedIdentity
            exactIdentityPreviouslyReviewedAsReported = $capture.capture.exactIdentityPreviouslyReviewed
            syntheticFixtureAsReported = (Get-SwiftUIBaselineProperty -Value $capture.capture -Name "syntheticFixture")
            exporterToolHashes = $capture.capture.tools
            toolHashVerification = "recorded by capture; tool executables are not present in this artifact"
            interfaceProducerIdentity = "preserved in interface source-line facts; not inferred from the extractor"
        }
        scope = $capture.baselineManifest.scope
        authority = [ordered]@{
            rawGraphsAreAuthoritative = $true
            inventoryProjectionReconciledWithRawRecords = $true
            interfaceFactsAreSourceLinesNotParsedDeclarations = $true
            windowsMatchingPerformed = $false
            swiftSourceParsingPerformed = $false
            behaviorConformanceAssessed = $false
            nativeExportPerformed = $false
            identityReviewPerformed = $false
        }
        counts = [ordered]@{
            graphs = $result.Inventory.Graphs
            preciseIdentifiers = $result.Inventory.PreciseSymbols
            declarationOccurrences = $result.Inventory.DeclarationOccurrences
            relationshipOccurrences = $result.Inventory.RelationshipOccurrences
            graphFieldFacts = $result.GraphFieldFacts
            inventoryFacts = $result.InventoryFacts
            interfaceFiles = $result.InterfaceFiles
            interfaceSourceLines = $result.InterfaceLines
            overlayFiles = $result.OverlayFiles
            overlaySourceLines = $result.OverlayLines
            candidateQueueRecords = $result.QueueRecords
        }
        queues = [ordered]@{
            selectedFamilies = $selectedQueues
            selection = "lexical-candidates-only"
            affectsLedgerRecords = $false
            applicability = "unreviewed; no availability, architecture, underscore, synthesized or deprecation filter"
        }
        streaming = [ordered]@{
            implementation = "bounded-raw-record-visitor-and-external-ordinal-audit-v1"
            sourceSha256 = [SwiftUIBaseline.Streaming.InventoryWriter]::SourceHash
            powerShellVersion = $PSVersionTable.PSVersion.ToString()
            clrVersion = [System.Environment]::Version.ToString()
            sortChunkBytes = $SortChunkBytes
            mergeFanIn = $MergeFanIn
            maximumRecordCharacters = $MaximumRecordCharacters
            maximumMetadataBytes = $MaximumMetadataBytes
            rawGraphBytes = $result.Inventory.InputBytes
            ledgerBytes = $result.Inventory.OutputBytes
            largestRecordCharacters = $result.Inventory.LargestRecordCharacters
            largestTextLineCharacters = $result.LargestTextLineCharacters
            peakBufferedIndexEstimatedBytes = $result.Inventory.PeakBufferedIndexBytes
            initialSortRuns = $result.Inventory.InitialSortRuns
            mergePasses = $result.Inventory.MergePasses
            peakOpenRunReaders = $result.Inventory.PeakOpenRunReaders
            largestOccurrenceGroup = $result.Inventory.LargestOccurrenceGroup
        }
        generatorSources = @(
            foreach ($name in @("build-swiftui-api-audit.ps1", "swiftui-api-audit-common.ps1",
                    "swiftui-baseline-common.ps1", "swiftui-baseline-streaming.ps1")) {
                [ordered]@{
                    path = "scripts/" + $name
                    sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
        )
        recordFiles = $files.ToArray()
        sourceMetadataFiles = $copiedInputs.ToArray()
        remainingWork = @(
            "Review exact captured identity without changing the pinned release baseline.",
            "Reconcile public declarations, availability, imports, conditional compilation, macros and overlays.",
            "Capture and map Windows declarations and paired source probes at an exact commit.",
            "Implement remaining behaviors and attach reviewed native and Windows conformance evidence."
        )
    }
    $manifestPath = Join-Path $stagingPath "audit.json"
    Write-SwiftUIBaselineJson -Value $manifest -Path $manifestPath
    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText((Join-Path $stagingPath "audit.sha256"), "$manifestHash  audit.json`n", [System.Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $outputPath) { throw "Audit output appeared before publication; immutable evidence is never overwritten." }
    [System.IO.Directory]::Move($stagingPath, $outputPath)
    $published = $true
} catch {
    $failure = $_
    throw
} finally {
    if (-not $published -and (Test-Path -LiteralPath $stagingPath)) {
        try {
            $resolved = Resolve-SwiftUIBaselineFileSystemPath -Path $stagingPath
            if ($resolved -cne [System.IO.Path]::GetFullPath($stagingPath) -or
                [System.IO.Path]::GetDirectoryName($resolved) -cne $outputParent -or
                [System.IO.Path]::GetFileName($resolved) -cne $stagingLeaf -or
                ((Get-Item -LiteralPath $stagingPath -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing unsafe audit staging cleanup."
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
        } catch {
            if ($null -ne $failure) {
                throw [System.AggregateException]::new("Audit creation failed and owned staging cleanup also failed.",
                    [Exception[]]@($failure.Exception, $_.Exception))
            }
            throw
        }
    }
}

Write-Host "Created $($result.Inventory.PreciseSymbols) unreviewed identifier records with every occurrence retained."
Write-Host "Audit evidence: $outputPath"
Write-Host "No declaration, source-compatibility, overlay, identity or behavior qualification was performed."
[pscustomobject][ordered]@{
    path = $outputPath
    manifestPath = Join-Path $outputPath "audit.json"
    manifestSha256 = $manifestHash
    counts = $manifest.counts
    reviewStatus = "unreviewed"
}
