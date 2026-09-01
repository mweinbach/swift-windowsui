<#
.SYNOPSIS
Defines full collector reader fixtures; dot-sourcing performs no collection.
.DESCRIPTION
Every receipt and graph in this file is SYNTHETIC. Native-shaped success fields
are parser inputs, not observations of a compiler, SDK or native process.

The production supplemental writer first consumes tiny local graphs with real
Windows filesystem paths. Its output remains unchanged under .work. A separate
reader fixture retains identical graph bytes and records POSIX producer paths.
The unchanged streaming writer regenerates its inventory for the new input
identity. Both production readers run normally; no path checker, parser, argv
builder, classifier or process adapter is replaced by this helper.

This file relies on helpers defined by test-swiftui-overlay-probe-collector.ps1.
Only Invoke-CollectorFullReportTests runs cases. No Swift/compiler/native tool,
workflow or recorded SDK path is ever opened or executed by these functions.
#>

function New-CollectorFullExtractorFixture {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)]$Profile, [Parameter(Mandatory)]$Request)
    if ($Request.kind -cne 'supplemental-extractor') { throw 'A synthetic extractor fixture needs an exact derived extraction request.' }
    $prefix = 'evidence/' + $Request.requestId + '/'
    $cell = New-SwiftUIOverlayProbeOwnedDirectory -Root $Root -RelativePath $prefix.TrimEnd('/')
    $recordedRoot = '/SYNTHETIC-COLLECTOR/' + [IO.Path]::GetFileName($Root)
    $work = $recordedRoot + '/.work/requests/' + $Request.requestId
    $cache = $work + '/module-cache'; $temporary = $work + '/tmp'
    $graphDirectory = $recordedRoot + '/.work/graphs/' + $Request.requestId
    $arguments = New-SwiftUIOverlayProbeExtractorArguments -OverlayModule $Request.requestedModule `
        -SDKPath $Profile.sdkPath -Target $Request.target -CxxMode $Request.cxxMode `
        -CachePath $cache -OutputDirectory $graphDirectory
    $diagnosticText = 'SYNTHETIC EXTRACTOR RECEIPT. No process or SDK was used.' + [char]10
    [void](Write-CollectorBytes (Join-Path $cell 'stdout.txt') ([byte[]]@()))
    [void](Write-CollectorText (Join-Path $cell 'stderr.txt') $diagnosticText)
    $process = [pscustomobject][ordered]@{
        evidenceKind = 'SYNTHETIC-RECORD-NOT-PROCESS-CAPTURE'
        processStarted = $true; exitCode = 0; timedOut = $false; outputLimitExceeded = $false
        terminationRequested = $false; terminationCompleted = $true; allRedirectedStreamsClosed = $true
        error = $null; cleanupErrors = @(); observedDiscardedBytes = [long]0
        stdoutBytes = [long]0; stderrBytes = [long]$script:CollectorUtf8.GetByteCount($diagnosticText)
        stdoutSha256 = Get-SwiftUIStateObjectBytesSHA256 ([byte[]]@())
        stderrSha256 = Get-SwiftUIStateObjectBytesSHA256 ($script:CollectorUtf8.GetBytes($diagnosticText))
        descendantsClosed = $null
    }
    $receipt = [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'swiftui-overlay-native-launch-request-v1'
        batchId = $Report.batchId; request = Copy-CollectorValue $Request
        profileSha256 = $Report.nativeProfile.sha256; planSha256 = $Report.plan.sha256
        sourceArtifacts = Copy-CollectorValue $Report.sourceArtifacts
        executable = $Profile.extractor.path; arguments = @($arguments); workingDirectory = $work
        childEnvironmentOverrides = [pscustomobject][ordered]@{
            DEVELOPER_DIR = $Profile.developerDirectory; LANG = 'C'; LC_ALL = 'C'
            TMPDIR = $temporary; TEMP = $temporary; TMP = $temporary
        }
        remainingEnvironment = 'inherited; not a process sandbox'
        sourcePath = $null; tracePath = $null; graphDirectory = $graphDirectory
        timeoutSeconds = 120; maximumCombinedOutputBytes = [long]8MB
        sourceProfile = (Get-SwiftUIOverlayProbeNativePolicy).profile
    }
    $invocation = [pscustomobject][ordered]@{
        invocationId = $Request.requestId; requestId = $Request.frontendRequestId
        requestedModule = $Request.requestedModule; target = $Request.target; cxxMode = $Request.cxxMode
        control = 'supplemental-direct-module'; graphDirectory = $Request.requestId; arguments = @($arguments)
        exitCode = 0; termination = 'natural'; outputComplete = $true
        candidateRecordIds = Copy-CollectorValue $Request.candidateRecordIds
        positiveFrontendObservationIds = Copy-CollectorValue $Request.positiveFrontendObservationIds
    }
    $row = [pscustomobject][ordered]@{
        requestId = $Request.requestId; kind = $Request.kind; outcome = 'extractor-completed'
        nativeInvocationAttempted = $true; processStarted = $true
        stopLaterCommands = $false; descendantClosureRequired = $false; resultFile = $prefix + 'result.json'
    }
    $result = [pscustomobject][ordered]@{
        requestId = $Request.requestId; kind = $Request.kind; outcome = 'extractor-completed'
        nativeInvocationAttempted = $true; processStarted = $true
        stopLaterCommands = $false; descendantClosureRequired = $false
        descendantsClosed = $null; descendantClosureStatus = 'not-independently-observed'; error = $null
        process = $process; processOutcome = Get-SwiftUIOverlayProbeProcessOutcome -LaunchState 'confirmed-started' -Process $process
        pathObservations = @(); assessments = @(); positiveFrontendObservations = @()
        requestFile = $prefix + 'request.json'; resultFile = $prefix + 'result.json'
        liveChecksBefore = Copy-CollectorValue (@($Profile.anchors.file) + @($Profile.frontend))
        liveChecksAfter = Copy-CollectorValue (@($Profile.anchors.file) + @($Profile.frontend))
        invocation = $invocation
    }
    return [pscustomobject]@{
        root = $Root; cell = $cell; report = $Report; row = $row; expected = $Request; profile = $Profile
        receipt = $receipt; result = $result; process = Copy-CollectorValue $process; paths = @()
    }
}

function Write-CollectorFullGraphFixture {
    param([Parameter(Mandatory)][string]$GraphRoot, [Parameter(Mandatory)]$Request)
    $directory = New-SwiftUIOverlayProbeOwnedDirectory -Root $GraphRoot -RelativePath $Request.requestId
    $architecture = if ($Request.target -ceq 'arm64-apple-macosx26.5') { 'arm64' }
        elseif ($Request.target -ceq 'x86_64-apple-macosx26.5') { 'x86_64' }
        else { throw 'Synthetic full reports use only the two pinned targets.' }
    $graph = [pscustomobject][ordered]@{
        metadata = [pscustomobject]@{
            formatVersion = [pscustomobject]@{ major = 0; minor = 6; patch = 0 }
            generator = 'SYNTHETIC-FULL-REPORT-NO-COMPILER'
        }
        module = [pscustomobject]@{
            name = '_Alpha_Beta'
            platform = [pscustomobject]@{
                architecture = $architecture; operatingSystem = [pscustomobject]@{ name = 'macosx' }
            }
        }
        symbols = @([pscustomobject]@{
            identifier = [pscustomobject]@{ precise = 's:SyntheticAlphaBetaFixture'; interfaceLanguage = 'swift' }
            names = [pscustomobject]@{ title = 'SyntheticOverlayMember' }
            kind = [pscustomobject]@{ identifier = 'swift.struct'; displayName = 'Structure' }
            pathComponents = @('SyntheticOverlayMember'); accessLevel = 'public'
            declarationFragments = @(
                [pscustomobject]@{ kind = 'keyword'; spelling = 'struct' }
                [pscustomobject]@{ kind = 'text'; spelling = ' ' }
                [pscustomobject]@{ kind = 'identifier'; spelling = 'SyntheticOverlayMember' }
            )
        })
        relationships = @()
    }
    $file = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $directory '_Alpha_Beta.symbols.json') -Value $graph -MaximumBytes 64KB
    return [pscustomobject][ordered]@{
        relativePath = $Request.requestId + '/_Alpha_Beta.symbols.json'; bytes = $file.bytes; sha256 = $file.sha256
        invocationId = $Request.requestId; role = 'unattributed-emission'
        emittingModule = $null; declaringModule = $null; bystanders = $null; positiveFrontendObservationIds = @()
    }
}

function Write-CollectorRelocatedSupplementalFixture {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$OriginalWriter,
        [Parameter(Mandatory)]$RecordedFrozen, [Parameter(Mandatory)]$RecordedNative)
    # OriginalWriter remains untouched. This is construction of a separate
    # synthetic reader input, not relocation of observed compiler evidence.
    $original = (Read-SwiftUIStateObjectJson -Path $OriginalWriter.report.path -MaxBytes 16MB).document
    $output = New-SwiftUIOverlayProbeOwnedDirectory -Root $Root -RelativePath 'supplemental'
    [void](New-SwiftUIOverlayProbeOwnedDirectory -Root $output -RelativePath 'inputs')
    $frozen = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $Root 'inputs/frozen-graphs.json') -Value $RecordedFrozen -MaximumBytes 1MB
    $native = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $Root 'inputs/graph-invocations.json') -Value $RecordedNative -MaximumBytes 1MB
    [void](Copy-SwiftUIOverlayProbeBoundedFile -Source $frozen.path -Destination (Join-Path $output 'inputs/frozen-graphs.json') -MaximumBytes 1MB -ExpectedSha256 $frozen.sha256)
    [void](Copy-SwiftUIOverlayProbeBoundedFile -Source $native.path -Destination (Join-Path $output 'inputs/native-invocations.json') -MaximumBytes 1MB -ExpectedSha256 $native.sha256)
    $graphs = [Collections.Generic.List[SwiftUIBaseline.Streaming.GraphInput]]::new()
    $files = [Collections.Generic.List[object]]::new()
    foreach ($graph in $original.graphs) {
        [void](New-SwiftUIOverlayProbeOwnedDirectory -Root $output -RelativePath ('graphs/' + $graph.invocationId))
        $source = Resolve-SwiftUIOverlayGraphRelativePath -Root $OriginalWriter.outputDirectory -RelativePath $graph.path
        $destination = Resolve-SwiftUIOverlayGraphRelativePath -Root $output -RelativePath $graph.path
        [void](Copy-SwiftUIOverlayProbeBoundedFile -Source $source -Destination $destination -MaximumBytes 64KB -ExpectedSha256 $graph.sha256)
        $input = [SwiftUIBaseline.Streaming.GraphInput]::new()
        $input.Path = $destination; $input.RelativePath = $graph.path
        $input.RequestedModule = $graph.requestedModule; $input.Target = $graph.target; $input.Primary = $false
        $graphs.Add($input)
        $files.Add((Get-SwiftUIOverlayGraphBinding -Root $output -RelativePath $graph.path -Kind 'raw-supplemental-graph'))
    }
    $identity = Get-SwiftUIBaselineTextHash -Text ('swiftui-overlay-supplemental-v1:' + $frozen.sha256 + ':' + $native.sha256)
    $inventoryId = 'swiftui-overlay-supplemental-v1:' + $identity
    $limits = $original.limits
    $summary = [SwiftUIBaseline.Streaming.InventoryWriter]::Write($inventoryId, $graphs.ToArray(),
        (Join-Path $output 'supplemental-inventory.json'), [long]$limits.sortChunkBytes,
        [int]$limits.mergeFanIn, [int]$limits.maximumRecordCharacters)
    foreach ($relative in @('inputs/frozen-graphs.json', 'inputs/native-invocations.json', 'supplemental-inventory.json')) {
        $files.Add((Get-SwiftUIOverlayGraphBinding -Root $output -RelativePath $relative -Kind 'supplemental-artifact'))
    }
    $report = Copy-CollectorValue $original
    $report.supplementalInventoryId = $inventoryId
    $report.inputBindings = @(
        [pscustomobject]@{ kind = 'frozen-supplemental-input'; sha256 = $frozen.sha256; retainedPath = 'inputs/frozen-graphs.json' }
        [pscustomobject]@{ kind = 'native-invocation-context'; sha256 = $native.sha256; retainedPath = 'inputs/native-invocations.json' }
    )
    $report.inventory = [pscustomobject]@{
        path = 'supplemental-inventory.json'; sha256 = $summary.InventorySha256
        bytes = $summary.OutputBytes; graphSetSha256 = $summary.GraphSetSha256
    }
    $report.counts = [pscustomobject]@{
        graphs = $summary.Graphs; preciseSymbols = $summary.PreciseSymbols
        declarationOccurrences = $summary.DeclarationOccurrences; relationshipOccurrences = $summary.RelationshipOccurrences
        emptyInvocations = $report.emptyObservations.Count
    }
    $report.indexing = [pscustomobject]@{
        implementation = 'unchanged-InventoryWriter-and-VisitGraph'; sourceSha256 = [SwiftUIBaseline.Streaming.InventoryWriter]::SourceHash
        inputBytes = $summary.InputBytes; outputBytes = $summary.OutputBytes; largestRecordCharacters = $summary.LargestRecordCharacters
        peakBufferedIndexEstimatedBytes = $summary.PeakBufferedIndexBytes; peakBufferedIndexRecords = $summary.PeakBufferedIndexRecords
        initialSortRuns = $summary.InitialSortRuns; mergePasses = $summary.MergePasses; peakOpenRunReaders = $summary.PeakOpenRunReaders
        largestOccurrenceGroup = $summary.LargestOccurrenceGroup
    }
    $report.files = $files.ToArray()
    $reportFile = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $output 'supplemental-report.json') -Value $report -MaximumBytes 16MB
    [void](Write-CollectorText (Join-Path $output 'supplemental-report.sha256') ($reportFile.sha256 + '  supplemental-report.json' + [char]10))
    $descriptor = Read-SwiftUIOverlaySupplementalInventory -OutputDirectory $output -ExpectedReportSha256 $reportFile.sha256
    # Check the regenerated inventory's embedded ID too; the retained reader's
    # hash checks alone do not establish this internal metadata relationship.
    $inventory = (Read-SwiftUIStateObjectJson -Path (Join-Path $output 'supplemental-inventory.json') -MaxBytes 1MB).document
    if ($inventory.baselineId -cne $inventoryId) { throw 'Regenerated synthetic inventory retained the wrong input identity.' }
    return $descriptor
}

function New-CollectorFullReportFixture {
    param([ValidateSet('none', 'foreign-profile', 'foreign-module', 'foreign-trace-metadata')][string]$Mutation = 'none')
    $full = New-CollectorReportFixture -OverlayNames @('_Alpha_Beta', '_Alpha_Beta') -MutateProfile {
        param($profile)
        $profile.selectedRoots = @([pscustomobject]@{
            rootId = 'synthetic-recorded-sdk'; logicalPath = $profile.sdkPath
            physicalPath = $profile.sdkPath; state = 'readable-complete'
        })
    }
    $full.report.successful = $true; $full.report.status = 'recorded-awaiting-review'
    $full.report.errors = @(); $full.report.sourceSealsRechecked = $true
    $plan = Get-SwiftUIOverlayProbeReportPlan -Root $full.root -Report $full.report
    $imports = New-SwiftUIOverlayProbeRequestSchedule -Plan $plan
    $rows = [Collections.Generic.List[object]]::new()
    $importRecords = [Collections.Generic.List[object]]::new()
    foreach ($request in $imports) {
        $fixture = New-CollectorRecordedRequestFixture -Root $full.root -Report $full.report -Profile $full.profile -Request $request
        Save-CollectorRecordedRequest $fixture
        $importRecords.Add((Read-CollectorRecordedRequest $fixture))
        $rows.Add($fixture.row)
    }
    $extractions = New-SwiftUIOverlayProbeExtractionSchedule -Plan $plan -ImportResults $importRecords.ToArray()
    $extractionRecords = [Collections.Generic.List[object]]::new()
    foreach ($request in $extractions.requests) {
        $fixture = New-CollectorFullExtractorFixture -Root $full.root -Report $full.report -Profile $full.profile -Request $request
        Save-CollectorRecordedRequest $fixture
        $extractionRecords.Add((Read-CollectorRecordedRequest $fixture))
        $rows.Add($fixture.row)
    }
    if ($imports.Count -ne 8 -or $extractions.requests.Count -ne 2 -or $extractions.positiveFrontendObservations.Count -ne 4) {
        throw 'The synthetic full report did not exercise exactly eight imports and two derived extractions.'
    }
    $full.report.requests = $rows.ToArray()
    $full.report.nativeInvocationsAttempted = $rows.Count; $full.report.confirmedProcessesStarted = $rows.Count
    $source = New-SwiftUIOverlayProbeOwnedDirectory -Root $full.root -RelativePath '.work/synthetic-full-source'
    $graphRoot = New-SwiftUIOverlayProbeOwnedDirectory -Root $full.root -RelativePath '.work/synthetic-graph-producer'
    $entries = @($extractions.requests | ForEach-Object { Write-CollectorFullGraphFixture -GraphRoot $graphRoot -Request $_ })
    $recordedRoot = '/SYNTHETIC-COLLECTOR/' + [IO.Path]::GetFileName($full.root)
    $recordedFrozen = [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'swiftui-overlay-supplemental-graph-inputs-v1'
        batchId = $full.report.batchId; graphRoot = $recordedRoot + '/.work/graphs'
        supplementalGraphInputs = $entries
    }
    $recordedNative = [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'swiftui-overlay-graph-native-invocations-v1'
        batchId = $full.report.batchId; profileSha256 = $full.report.nativeProfile.sha256; executionKind = 'native'
        invocations = Copy-CollectorValue @($extractionRecords.ToArray().invocation)
        positiveFrontendObservations = Copy-CollectorValue $extractions.positiveFrontendObservations
    }
    switch ($Mutation) {
        'foreign-profile' {
            $recordedNative.profileSha256 = New-CollectorHash 'full-report-foreign-profile'
            foreach ($observation in $recordedNative.positiveFrontendObservations) { $observation.profileSha256 = $recordedNative.profileSha256 }
        }
        'foreign-module' {
            foreach ($invocation in $recordedNative.invocations) {
                $invocation.requestedModule = '_Foreign_Alpha_Beta'
                for ($index = 0; $index -lt $invocation.arguments.Count; $index++) {
                    if ($invocation.arguments[$index] -ceq '-module-name') { $invocation.arguments[$index + 1] = $invocation.requestedModule }
                }
            }
            foreach ($observation in $recordedNative.positiveFrontendObservations) {
                $observation.module = '_Foreign_Alpha_Beta'; $observation.activationTuple.overlayModule = '_Foreign_Alpha_Beta'
            }
        }
        'foreign-trace-metadata' { $recordedNative.positiveFrontendObservations[0].traceSha256 = New-CollectorHash 'full-report-foreign-trace' }
    }
    $localFrozen = Copy-CollectorValue $recordedFrozen
    $localFrozen.graphRoot = $graphRoot
    $localNative = Copy-CollectorValue $recordedNative
    foreach ($invocation in $localNative.invocations) {
        $expectedOutput = Resolve-SwiftUIOverlayGraphRelativePath -Root $graphRoot -RelativePath $invocation.graphDirectory
        for ($index = 0; $index -lt $invocation.arguments.Count; $index++) {
            if ($invocation.arguments[$index] -ceq '-output-dir') { $invocation.arguments[$index + 1] = $expectedOutput }
        }
    }
    $frozenFile = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $source 'local-frozen-graphs.json') -Value $localFrozen -MaximumBytes 1MB
    $nativeFile = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $source 'local-native-invocations.json') -Value $localNative -MaximumBytes 1MB
    $originalWriter = Write-SwiftUIOverlaySupplementalInventory -FrozenGraphInventoryPath $frozenFile.path -FrozenGraphInventorySha256 $frozenFile.sha256 `
        -NativeInvocationMetadataPath $nativeFile.path -NativeInvocationMetadataSha256 $nativeFile.sha256 `
        -OutputDirectory (Join-Path $full.root '.work/original-writer-output')
    $retained = Write-CollectorRelocatedSupplementalFixture -Root $full.root -OriginalWriter $originalWriter `
        -RecordedFrozen $recordedFrozen -RecordedNative $recordedNative
    [void](Get-SwiftUIOverlayProbeBoundedHash -Path $originalWriter.report.path -MaximumBytes 16MB -ExpectedSha256 $originalWriter.report.sha256 -ExpectedBytes $originalWriter.report.bytes)
    foreach ($file in $originalWriter.files) {
        [void](Get-SwiftUIOverlayProbeBoundedHash -Path (Join-Path $originalWriter.outputDirectory $file.relativePath) `
            -MaximumBytes 1MB -ExpectedSha256 $file.sha256 -ExpectedBytes $file.bytes)
    }
    $full.report.supplemental = [pscustomobject]@{ status = 'retained-awaiting-review'; report = $retained }
    $adaptation = [pscustomobject][ordered]@{
        evidenceKind = 'SYNTHETIC-RELOCATED-COLLECTOR-READER-FIXTURE-NOT-NATIVE-CAPTURE'
        mutation = $Mutation; root = $full.root
        actualNativeCommandsExecuted = $false; actualCompilerExecuted = $false; recordedSDKPathsOpened = $false
        nativeShapedFieldsAreSyntheticParserInputs = $true
        construction = 'Production supplemental writer with local synthetic graph paths; unchanged original output retained; separate POSIX-shaped metadata and a newly streamed inventory for production reader tests.'
        productionWriter = [pscustomobject]@{
            outputDirectory = $originalWriter.outputDirectory; reportSha256 = $originalWriter.report.sha256
            supplementalInventoryId = $originalWriter.supplementalInventoryId; sourceFilesUnchanged = $true
        }
        relocatedReaderFixture = [pscustomobject]@{
            outputDirectory = $retained.outputDirectory; reportSha256 = $retained.report.sha256
            supplementalInventoryId = $retained.supplementalInventoryId
            inventoryRegeneratedWithUnchangedStreamingWriter = $true
            originalGraphBytesPreserved = $true; supplementalReaderAccepted = $true
        }
        outerReaderStatus = 'not-yet-tested'
        qualification = Copy-CollectorValue $script:CollectorFixture.qualification
    }
    [void](Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $full.root 'SYNTHETIC-FULL-REPORT.json') -Value $adaptation -MaximumBytes 1MB)
    [void](Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $source 'SYNTHETIC-PATH-ADAPTATION.json') -Value $adaptation -MaximumBytes 1MB)
    if ($null -eq (Get-Variable -Name CollectorRelocatedFixtureEvidence -Scope Script -ErrorAction SilentlyContinue)) {
        $script:CollectorRelocatedFixtureEvidence = [Collections.Generic.List[object]]::new()
    }
    $script:CollectorRelocatedFixtureEvidence.Add($adaptation)
    $full.report.files = Get-SwiftUIOverlayProbePayloadInventory -Root $full.root
    return [pscustomobject]@{
        root = $full.root; report = $full.report; plan = $full.plan; profile = $full.profile
        importRecords = $importRecords.ToArray(); extractionRecords = $extractionRecords.ToArray()
        originalWriter = $originalWriter; supplemental = $retained; adaptation = $adaptation
    }
}

function Save-CollectorFullReaderVerification {
    param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][string]$Status)
    $Fixture.adaptation.outerReaderStatus = $Status
    [void](Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $Fixture.root '.work/synthetic-full-source/reader-verification.json') `
        -Value $Fixture.adaptation -MaximumBytes 1MB)
}

function Invoke-CollectorFullReportTests {
    Invoke-CollectorCase 'full-report-replays-eight-imports-two-extractions-and-streamed-graphs' {
        $fixture = New-CollectorFullReportFixture
        $saved = Save-CollectorReportFixture $fixture
        $read = Read-SwiftUIOverlayProbeReport -Root $saved.root -ExpectedSha256 $saved.sha256
        Assert-CollectorTrue ($read.successful -and $read.status -ceq 'recorded-awaiting-review') 'production report reader accepts the complete synthetic operational shape'
        Assert-CollectorTrue ($read.report.requests.Count -eq 10 -and $read.report.nativeInvocationsAttempted -eq 10 -and $read.report.confirmedProcessesStarted -eq 10) 'every synthetic frontend and extractor receipt is replayed'
        Assert-CollectorTrue ($fixture.importRecords.Count -eq 8 -and $fixture.extractionRecords.Count -eq 2) 'both target architectures retain all four controls and one direct extraction'
        Assert-CollectorTrue ($fixture.supplemental.counts.graphs -eq 2 -and $fixture.supplemental.counts.preciseSymbols -eq 1 -and $fixture.supplemental.counts.declarationOccurrences -eq 2) 'real streaming retains two target occurrences of one precise identifier'
        Assert-CollectorTrue ($fixture.plan.pairs[0].overlayNameOccurrences.Count -eq 2 -and $fixture.plan.pairs[0].overlayNameOccurrences[1].index -eq 1) 'duplicate overlay names retain their two exact planned positions'
        Assert-CollectorTrue (-not $read.qualification.reviewedIdentity -and -not $read.qualification.declarationCompleteness -and -not $read.qualification.overlayCompleteness -and -not $read.qualification.behaviorConformance) 'successful-shaped synthetic receipts cannot complete any original gate'
        Assert-CollectorTrue ($fixture.adaptation.productionWriter.sourceFilesUnchanged -and $fixture.adaptation.relocatedReaderFixture.inventoryRegeneratedWithUnchangedStreamingWriter) 'original writer evidence and independently rebuilt reader fixture remain distinct'
        Save-CollectorFullReaderVerification $fixture 'accepted-synthetic-reader-fixture-not-native-execution'
    }
    foreach ($mutation in @('foreign-profile', 'foreign-module', 'foreign-trace-metadata')) {
        Invoke-CollectorCase ('full-report-rejects-resealed-supplemental-' + $mutation) {
            $fixture = New-CollectorFullReportFixture -Mutation $mutation
            Assert-CollectorTrue ($fixture.adaptation.relocatedReaderFixture.supplementalReaderAccepted -and $fixture.supplemental.counts.graphs -eq 2) 'foreign producer context passes its internally consistent supplemental seal'
            $saved = Save-CollectorReportFixture $fixture
            Assert-CollectorThrows { Read-SwiftUIOverlayProbeReport -Root $saved.root -ExpectedSha256 $saved.sha256 } `
                ($mutation + ': outer reader compares supplemental producers to replayed compiler/extractor receipts') 'exact supplemental native producer bindings'
            Save-CollectorFullReaderVerification $fixture ('rejected-at-exact-supplemental-native-producer-bindings:' + $mutation)
        }
    }
}
