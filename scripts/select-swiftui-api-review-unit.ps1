<#
.SYNOPSIS
Selects one exact native precise identifier into an immutable, unreviewed packet.
.DESCRIPTION
Requires the original successful pinned capture and its complete sealed audit.
Streams and reconciles every raw graph, inventory record and ledger stream; no
name matching, Swift source parsing, compilation or behavioral review occurs.
Windows source bytes are copied from an explicit existing full Git commit.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CaptureRoot,
    [Parameter(Mandatory)][string]$AuditRoot,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PreciseIdentifier,
    [Parameter(Mandatory)][string]$WindowsRepositoryRoot,
    [Parameter(Mandatory)][string]$WindowsCommit,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$WindowsSourcePath,
    [string]$OutputDirectory,
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs/swiftui-baseline.json'),
    [ValidateRange(1024, 1073741824)][long]$SortChunkBytes = 16777216,
    [ValidateRange(2, 64)][int]$MergeFanIn = 16,
    [ValidateRange(1024, 134217728)][int]$MaximumRecordCharacters = 33554432,
    [ValidateRange(1024, 134217728)][long]$MaximumMetadataBytes = 16777216,
    [ValidateRange(1024, 134217728)][long]$MaximumSourceBytes = 16777216
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'swiftui-api-review-common.ps1')
. (Join-Path $PSScriptRoot 'swiftui-baseline-streaming.ps1')
$inputs = Read-SwiftUIAPIReviewInputs -CaptureRoot $CaptureRoot -AuditRoot $AuditRoot `
    -ManifestPath $ManifestPath -MaximumMetadataBytes $MaximumMetadataBytes
$capture = $inputs.captureContext

if ([string]::IsNullOrWhiteSpace($PreciseIdentifier) -or $PreciseIdentifier.Length -gt $MaximumRecordCharacters) {
    throw 'One exact nonempty precise identifier within MaximumRecordCharacters is required.'
}
[void][System.Text.UTF8Encoding]::new($false, $true).GetByteCount($PreciseIdentifier)
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) ('artifacts/swiftui-api-review/' + [Guid]::NewGuid().ToString('N'))
}
$outputPath = Resolve-SwiftUIBaselineFileSystemPath -Path $OutputDirectory
$comparison = [StringComparison]::OrdinalIgnoreCase
foreach ($sourceRoot in @($inputs.captureRoot, $inputs.auditRoot)) {
    $sourcePrefix = $sourceRoot.TrimEnd([char[]]'\/') + [System.IO.Path]::DirectorySeparatorChar
    if ($outputPath.Equals($sourceRoot, $comparison) -or $outputPath.StartsWith($sourcePrefix, $comparison)) {
        throw 'Review output must be outside the read-only source capture and audit ledger.'
    }
}
if (Test-Path -LiteralPath $outputPath) { throw 'Review output already exists; immutable evidence is never overwritten.' }
$outputParent = [System.IO.Path]::GetDirectoryName($outputPath)
if ([string]::IsNullOrWhiteSpace($outputParent)) { throw 'Review output requires a parent directory.' }
[void][System.IO.Directory]::CreateDirectory($outputParent)
$stagingLeaf = '.swiftui-api-review-' + [Guid]::NewGuid().ToString('N')
$stagingPath = Join-Path $outputParent $stagingLeaf
if (Test-Path -LiteralPath $stagingPath) { throw 'Review staging directory already exists.' }
[void][System.IO.Directory]::CreateDirectory($stagingPath)
$published = $false
$failure = $null

try {
    if ((Resolve-SwiftUIBaselineFileSystemPath -Path $stagingPath) -cne [System.IO.Path]::GetFullPath($stagingPath)) {
        throw 'Review staging directory must not be substituted by a filesystem alias.'
    }
    Initialize-SwiftUIBaselineStreaming
    # The shared bounded intake checks schema and hashes. PowerShell's JSON
    # projection can accept duplicate property names, so also reject ambiguity
    # with the existing grammar reader before consuming any large input.
    $metadataInputs = [System.Collections.Generic.List[object]]::new()
    $metadataInputs.Add([pscustomobject]@{ path = $inputs.auditManifestPath; sha256 = $inputs.auditManifestSha256 })
    $metadataInputs.Add([pscustomobject]@{
        path = $inputs.historicalExpectedBaselineManifestPath; sha256 = $inputs.historicalExpectedBaselineManifestSha256
    })
    foreach ($entry in $capture.inputFiles) {
        if ($entry.kind -in @('expected-baseline-manifest', 'capture-status', 'capture-manifest', 'captured-baseline-manifest')) {
            $metadataInputs.Add($entry)
        }
    }
    # SDK settings are never projected into PowerShell objects. Their exact
    # sealed bytes, like interface/overlay text, remain opaque source evidence.
    foreach ($entry in $metadataInputs) {
        $metadata = Read-SwiftUIAuditBoundedText -Path $entry.path -MaximumBytes $MaximumMetadataBytes
        if ($metadata.sha256 -cne $entry.sha256) { throw 'Review metadata changed before grammar validation.' }
        [SwiftUIBaseline.Streaming.AuditReviewPacketWriter]::ValidateMetadataObject($metadata.text, [int]$MaximumMetadataBytes)
    }
    $metadata = $null
    $ledger = [SwiftUIBaseline.Streaming.AuditLedgerOptions]::new()
    $ledger.BaselineId = $capture.baselineManifest.baselineId
    $ledger.InventoryPath = $capture.inventoryPath
    $ledger.InventorySha256 = $capture.inventorySha256
    $ledger.GraphSetSha256 = $capture.capture.inventory.graphSetSha256
    $ledger.ExpectedGraphs = $capture.capture.inventory.counts.graphs
    $ledger.ExpectedPreciseSymbols = $capture.capture.inventory.counts.preciseSymbols
    $ledger.ExpectedDeclarations = $capture.capture.inventory.counts.declarationOccurrences
    $ledger.ExpectedRelationships = $capture.capture.inventory.counts.relationshipOccurrences
    $ledger.OutputDirectory = $stagingPath
    $ledger.SortChunkBytes = $SortChunkBytes
    $ledger.MergeFanIn = $MergeFanIn
    $ledger.MaximumRecordCharacters = $MaximumRecordCharacters
    # Queue families reproduce the original complete ledger. They never filter
    # declarations, occurrences or incident relationships in this review unit.
    $ledger.QueueFamilies = [string[]]@($inputs.auditManifest.queues.selectedFamilies)
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
    $ledger.Graphs = $graphs.ToArray()
    foreach ($kind in @('Interfaces', 'Overlays')) {
        $records = $capture.publicInterfaces
        if ($kind -ceq 'Overlays') { $records = $capture.crossImportDefinitions }
        $textInputs = [System.Collections.Generic.List[SwiftUIBaseline.Streaming.AuditTextInput]]::new()
        $recordsByPath = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        foreach ($entry in $records) { $recordsByPath.Add($entry.relativePath, $entry) }
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
        $ledger.$kind = $textInputs.ToArray()
    }
    $files = [System.Collections.Generic.List[SwiftUIBaseline.Streaming.AuditReviewFileInput]]::new()
    foreach ($entry in $inputs.recordFiles) {
        $file = [SwiftUIBaseline.Streaming.AuditReviewFileInput]::new()
        $file.Path = $entry.path
        $file.RelativePath = $entry.relativePath
        $file.Sha256 = $entry.sha256
        $file.Bytes = $entry.bytes
        $files.Add($file)
    }
    $options = [SwiftUIBaseline.Streaming.AuditReviewOptions]::new()
    $options.Ledger = $ledger
    $options.Files = $files.ToArray()
    $options.PreciseIdentifier = $PreciseIdentifier
    $options.OutputDirectory = $stagingPath
    $result = [SwiftUIBaseline.Streaming.AuditReviewPacketWriter]::Write($options)
    $verifiedCounts = [ordered]@{
        graphs = $result.Verified.Inventory.Graphs
        preciseIdentifiers = $result.Verified.Inventory.PreciseSymbols
        declarationOccurrences = $result.Verified.Inventory.DeclarationOccurrences
        relationshipOccurrences = $result.Verified.Inventory.RelationshipOccurrences
        graphFieldFacts = $result.Verified.GraphFieldFacts
        inventoryFacts = $result.Verified.InventoryFacts
        interfaceFiles = $result.Verified.InterfaceFiles
        interfaceSourceLines = $result.Verified.InterfaceLines
        overlayFiles = $result.Verified.OverlayFiles
        overlaySourceLines = $result.Verified.OverlayLines
        candidateQueueRecords = $result.Verified.QueueRecords
    }
    foreach ($name in $verifiedCounts.Keys) {
        if ([long]$verifiedCounts[$name] -ne [long]$inputs.auditManifest.counts.$name) {
            throw "Complete ledger count differs after streaming verification: $name."
        }
    }

    # Retain complete sealed interface/overlay and metadata bytes. No textual
    # match is presented as a parsed Swift declaration or complete dependency.
    $copiedInputs = [System.Collections.Generic.List[object]]::new()
    $copySources = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $inputs.sourceMetadataFiles) {
        $copySources.Add([pscustomobject]@{
            sourcePath = $entry.path; relativePath = 'context/' + $entry.relativePath
            sha256 = $entry.sha256; bytes = $entry.bytes; kind = $entry.kind
        })
    }
    foreach ($entry in @(
        @{ path = $inputs.auditManifestPath; relativePath = 'context/audit.json'; sha256 = $inputs.auditManifestSha256; kind = 'source-audit-manifest' },
        @{ path = (Join-Path $inputs.auditRoot 'audit.sha256'); relativePath = 'context/audit.sha256'; sha256 = $inputs.auditSealSha256; kind = 'source-audit-seal' },
        @{ path = $inputs.currentExpectedBaselineManifestPath; relativePath = 'context/current-expected-baseline-manifest.json'; sha256 = $inputs.currentExpectedBaselineManifestSha256; kind = 'current-expected-baseline-manifest' }
    )) {
        $copySources.Add([pscustomobject]@{
            sourcePath = $entry.path; relativePath = $entry.relativePath
            sha256 = $entry.sha256; bytes = ([System.IO.FileInfo]$entry.path).Length; kind = $entry.kind
        })
    }
    foreach ($entry in $copySources) {
        $destination = Join-Path $stagingPath $entry.relativePath
        [void](Get-SwiftUIBaselineRelativePath -Root $stagingPath -Path $destination)
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destination))
        [System.IO.File]::Copy($entry.sourcePath, $destination, $false)
        $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -cne $entry.sha256 -or ([System.IO.FileInfo]$destination).Length -ne $entry.bytes) {
            throw "Source context changed while copying '$($entry.relativePath)'."
        }
        $copiedInputs.Add([ordered]@{ path = $entry.relativePath; sha256 = $hash; bytes = $entry.bytes; kind = $entry.kind })
    }

    $windows = Write-SwiftUIAPIReviewWindowsSources -RepositoryRoot $WindowsRepositoryRoot `
        -Commit $WindowsCommit -RelativePaths $WindowsSourcePath -DestinationDirectory (Join-Path $stagingPath 'windows-source') `
        -MaximumSourceBytes $MaximumSourceBytes
    $windowsFiles = @(
        foreach ($entry in $windows.files) {
            [ordered]@{
                path = $entry.path; blobOid = $entry.blobOid; sha256 = $entry.sha256; bytes = $entry.bytes
                copiedPath = 'windows-source/' + $entry.copiedPath
            }
        }
    )
    $recordFiles = @(
        foreach ($name in $result.RecordFiles) {
            $path = Join-Path $stagingPath $name
            [ordered]@{
                path = $name; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                bytes = ([System.IO.FileInfo]$path).Length
            }
        }
    )
    # Recheck small metadata before publication. The large inputs were hashed
    # during their complete streamed verification; no whole-file DOM is used.
    foreach ($entry in $copySources) {
        if ((Get-FileHash -LiteralPath $entry.sourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256) {
            throw "Source context changed before review publication: $($entry.relativePath)."
        }
    }
    foreach ($entry in $capture.inputFiles) {
        if ((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256) {
            throw 'Original successful capture metadata changed before review publication.'
        }
    }
    $manifest = [ordered]@{
        schemaVersion = 1
        evidenceKind = 'unreviewed-api-review-unit'
        status = 'awaiting-declaration-source-and-behavior-review'
        reviewStatus = 'unreviewed'
        baselineId = $capture.baselineManifest.baselineId
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        selection = [ordered]@{
            preciseIdentifier = $PreciseIdentifier
            comparison = 'ordinal-exact'
            declarationOccurrences = $result.SelectedOccurrences
            incidentRelationships = $result.IncidentRelationships
            closure = 'all-occurrences-and-source-or-target-incident-relationships'
            standaloneNativeUniverse = $false
        }
        sourceCapture = [ordered]@{
            path = $inputs.captureRoot
            captureManifestSha256 = $capture.captureSha256
            captureStatusSha256 = $capture.statusSha256
            baselineManifestSha256 = $capture.baselineManifestSha256
            inventorySha256 = $result.Verified.Inventory.InventorySha256
            graphSetSha256 = $result.Verified.Inventory.GraphSetSha256
            observedExtractorIdentity = $capture.capture.observedIdentity
            exactIdentityPreviouslyReviewedAsReported = $capture.capture.exactIdentityPreviouslyReviewed
            syntheticFixtureAsReported = (Get-SwiftUIBaselineProperty -Value $capture.capture -Name 'syntheticFixture')
            exporterToolHashes = $capture.capture.tools
            toolHashVerification = 'reported by capture; producer executables are not present in this artifact'
            interfaceProducerIdentity = 'retained in complete interface bytes; not inferred from the extractor'
        }
        sourceAudit = [ordered]@{
            path = $inputs.auditRoot
            manifestSha256 = $inputs.auditManifestSha256
            sealSha256 = $inputs.auditSealSha256
            evidenceKind = $inputs.auditManifest.evidenceKind
            status = $inputs.auditManifest.status
            reviewStatus = $inputs.auditManifest.reviewStatus
            historicalExpectedBaselineManifestSha256 = $inputs.historicalExpectedBaselineManifestSha256
            currentExpectedBaselineManifestSha256 = $inputs.currentExpectedBaselineManifestSha256
            recordFiles = $inputs.auditManifest.recordFiles
            generatorSourcesAsReported = $inputs.auditManifest.generatorSources
            streamingImplementationAsReported = $inputs.auditManifest.streaming
        }
        scope = $capture.baselineManifest.scope
        verification = [ordered]@{
            wholeLedgerReconciledWithCapture = $true
            sourceLedgerRecordsMutated = $false
            fullSelectedRawRecordsPreserved = $true
            rawGraphsRemainAuthoritative = $true
            swiftSourceParsingPerformed = $false
            windowsDeclarationMatchingPerformed = $false
            compilationPerformed = $false
            behaviorConformanceAssessed = $false
            identityReviewPerformed = $false
        }
        counts = [ordered]@{
            nativeLedger = $inputs.auditManifest.counts
            selected = [ordered]@{
                preciseIdentifiers = 1
                declarationOccurrences = $result.SelectedOccurrences
                relationshipOccurrences = $result.IncidentRelationships
            }
        }
        context = [ordered]@{
            strategy = 'complete-captured-files-and-ledger-context'
            nativePartitions = 'every sealed graph partition and root metadata fact'
            interfacesAndOverlays = 'every captured public interface and overlay file with exact bytes and source-line facts'
            semanticDeclarationOrDependencyCompleteness = 'unverified; no Swift grammar or conditional-compilation interpretation'
            crossImportOverlayCompleteness = $capture.capture.crossImportOverlayCompleteness
            sourceRawGraphsAndCompleteLedgerRequired = $true
        }
        windowsSource = [ordered]@{
            commit = $windows.commit
            files = $windowsFiles
            binding = 'explicit-paths-from-existing-committed-regular-git-blobs-only'
            observedHead = $windows.observedHead
            observedDirty = $windows.observedDirty
            observedChanges = $windows.observedChanges
            observationError = $windows.observationError
            checkoutObservationStatus = $windows.checkoutObservationStatus
            declarationMatchingPerformed = $false
            buildPerformed = $false
        }
        claims = @(
            foreach ($kind in @('declaration', 'source-compatibility', 'behavior')) {
                [ordered]@{ claimId = $kind; kind = $kind; status = 'unverified'; evidenceRefs = @() }
            }
        )
        evidenceReferences = @()
        recordFiles = $recordFiles
        sourceMetadataFiles = $copiedInputs.ToArray()
        streaming = [ordered]@{
            implementation = 'bounded-exact-identifier-review-selector-v1'
            sourceSha256 = [SwiftUIBaseline.Streaming.InventoryWriter]::SourceHash
            powerShellVersion = $PSVersionTable.PSVersion.ToString()
            clrVersion = [System.Environment]::Version.ToString()
            sortChunkBytes = $SortChunkBytes
            mergeFanIn = $MergeFanIn
            maximumRecordCharacters = $MaximumRecordCharacters
            maximumMetadataBytes = $MaximumMetadataBytes
            maximumSourceBytesPerFileAndAggregate = $MaximumSourceBytes
            limitBehavior = 'fail without publishing; never truncate, omit or qualify a record'
            rawGraphBytesRead = $result.Verified.Inventory.InputBytes
            sourceLedgerBytesRead = $result.LedgerInputBytes
            selectedAndContextRecordBytes = $result.Verified.Inventory.OutputBytes
            largestRawRecordCharacters = $result.Verified.Inventory.LargestRecordCharacters
            largestSourceTextLineCharacters = $result.Verified.LargestTextLineCharacters
            peakBufferedIndexEstimatedBytes = $result.Verified.Inventory.PeakBufferedIndexBytes
            initialSortRuns = $result.Verified.Inventory.InitialSortRuns
            mergePasses = $result.Verified.Inventory.MergePasses
            peakOpenRunReaders = $result.Verified.Inventory.PeakOpenRunReaders
            largestOccurrenceGroup = $result.Verified.Inventory.LargestOccurrenceGroup
        }
        generatorSources = @(
            foreach ($name in @('select-swiftui-api-review-unit.ps1', 'swiftui-api-review-common.ps1',
                    'swiftui-api-audit-common.ps1', 'swiftui-baseline-common.ps1', 'swiftui-baseline-streaming.ps1')) {
                [ordered]@{
                    path = 'scripts/' + $name
                    sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
        )
        remainingWork = @(
            'Review the exact SDK/extractor identity and interface producer identity separately.',
            'Review all native occurrences, availability, extensions, interfaces and overlays for this exact identifier.',
            'Identify and review corresponding Windows declarations at the recorded commit.',
            'Attach exact paired source and behavior evidence in a separate immutable review record.',
            'Keep declaration, source compatibility and behavior assessments independent; test success alone approves none.'
        )
    }
    $manifestPath = Join-Path $stagingPath 'review-unit.json'
    Write-SwiftUIBaselineJson -Value $manifest -Path $manifestPath
    if (([System.IO.FileInfo]$manifestPath).Length -gt $MaximumMetadataBytes) {
        throw 'Review manifest exceeds MaximumMetadataBytes; increase the explicit budget, never truncate metadata.'
    }
    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText((Join-Path $stagingPath 'review-unit.sha256'), "$manifestHash  review-unit.json`n", [System.Text.UTF8Encoding]::new($false))
    if ((Resolve-SwiftUIBaselineFileSystemPath -Path $stagingPath) -cne [System.IO.Path]::GetFullPath($stagingPath) -or
        (Resolve-SwiftUIBaselineFileSystemPath -Path $outputPath) -cne $outputPath) {
        throw 'Review output paths changed before publication.'
    }
    if (Test-Path -LiteralPath $outputPath) { throw 'Review output appeared before publication; immutable evidence is never overwritten.' }
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
                throw 'Refusing unsafe review staging cleanup.'
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
        } catch {
            if ($null -ne $failure) {
                throw [System.AggregateException]::new('Review creation failed and owned staging cleanup also failed.',
                    [Exception[]]@($failure.Exception, $_.Exception))
            }
            throw
        }
    }
}

Write-Host "Created an unreviewed unit with $($result.SelectedOccurrences) occurrences and $($result.IncidentRelationships) incident relationships."
Write-Host "Review packet: $outputPath"
Write-Host 'No native identity, declaration, source compatibility or behavior claim was approved.'
[pscustomobject][ordered]@{
    path = $outputPath
    manifestPath = Join-Path $outputPath 'review-unit.json'
    manifestSha256 = $manifestHash
    reviewStatus = 'unreviewed'
}
