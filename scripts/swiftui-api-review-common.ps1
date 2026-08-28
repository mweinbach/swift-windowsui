# Review-packet input validation only. Large ledger, inventory and graph bytes
# are verified by the streaming reader, not materialized as PowerShell objects.
# The packet entry point also requires strict duplicate-key validation of these
# bounded JSON metadata files; PowerShell metadata parsing alone is insufficient.
. (Join-Path $PSScriptRoot 'swiftui-api-audit-common.ps1')

function Resolve-SwiftUIAPIReviewArtifactPath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$RelativePath,
        [ValidateSet('File', 'Directory', 'Any')][string]$Kind = 'File')

    $path = Resolve-SwiftUIAuditArtifactPath -CaptureRoot $Root -RelativePath $RelativePath -Kind $Kind
    $intended = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    $comparison = [StringComparison]::Ordinal
    if ([IO.Path]::DirectorySeparatorChar -eq '\') { $comparison = [StringComparison]::OrdinalIgnoreCase }
    if (-not $path.Equals($intended, $comparison)) {
        throw "Review artifact '$RelativePath' must not redirect through a filesystem alias."
    }
    return $path
}

function Read-SwiftUIAPIReviewInputs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CaptureRoot,
        [Parameter(Mandatory)][string]$AuditRoot,
        [string]$ManifestPath = (Join-Path $PSScriptRoot '../docs/swiftui-baseline.json'),
        [long]$MaximumMetadataBytes = 16MB)

    $ErrorActionPreference = 'Stop'
    $capture = Read-SwiftUIAuditCapture -CaptureRoot $CaptureRoot -ManifestPath $ManifestPath -MaximumMetadataBytes $MaximumMetadataBytes
    $auditRootPath = Resolve-SwiftUIBaselineFileSystemPath -Path $AuditRoot
    if (-not (Test-Path -LiteralPath $auditRootPath -PathType Container)) { throw 'AuditRoot must be an existing ledger directory.' }
    $auditPath = Resolve-SwiftUIAPIReviewArtifactPath $auditRootPath 'audit.json'
    $auditFile = Read-SwiftUIAuditMetadata $auditPath $MaximumMetadataBytes
    $sealPath = Resolve-SwiftUIAPIReviewArtifactPath $auditRootPath 'audit.sha256'
    $seal = Read-SwiftUIAuditBoundedText $sealPath ([Math]::Min($MaximumMetadataBytes, 1024))
    if ($seal.text -cnotmatch '\A([0-9a-f]{64})  audit\.json(?:\r?\n)?\z' -or $Matches[1] -cne $auditFile.sha256) {
        throw 'audit.sha256 does not seal the actual audit.json bytes.'
    }
    $audit = $auditFile.value
    Assert-SwiftUIAuditFields $audit @{
        schemaVersion = 'integer'; evidenceKind = 'string'; status = 'string'; reviewStatus = 'string'
        baselineId = 'string'; createdAtUtc = 'string'; sourceCapture = 'object'; scope = 'object'
        authority = 'object'; counts = 'object'; queues = 'object'; streaming = 'object'
        generatorSources = 'array'; recordFiles = 'array'; sourceMetadataFiles = 'array'; remainingWork = 'array'
    } 'audit'
    if ($audit.schemaVersion -ne 1 -or $audit.evidenceKind -cne 'unreviewed-native-api-audit-ledger' -or
        $audit.status -cne 'awaiting-declaration-interface-and-behavior-review' -or $audit.reviewStatus -cne 'unreviewed' -or
        $audit.baselineId -cne $capture.baselineManifest.baselineId) {
        throw 'Only the matching complete, unreviewed API audit ledger can enter a review packet.'
    }
    Assert-SwiftUIAuditJsonEqual $capture.baselineManifest.scope $audit.scope 'audit.scope'
    $expectedAuthority = [pscustomobject][ordered]@{
        rawGraphsAreAuthoritative = $true; inventoryProjectionReconciledWithRawRecords = $true
        interfaceFactsAreSourceLinesNotParsedDeclarations = $true; windowsMatchingPerformed = $false
        swiftSourceParsingPerformed = $false; behaviorConformanceAssessed = $false
        nativeExportPerformed = $false; identityReviewPerformed = $false
    }
    Assert-SwiftUIAuditJsonEqual $expectedAuthority $audit.authority 'audit.authority'
    $source = $audit.sourceCapture
    Assert-SwiftUIAuditFields $source @{
        path = 'string'; status = 'string'; captureManifestSha256 = 'string'; captureStatusSha256 = 'string'
        baselineManifestSha256 = 'string'; expectedBaselineManifestSha256 = 'string'; inventorySha256 = 'string'
        graphSetSha256 = 'string'; observedExtractorIdentity = 'object'; exactIdentityPreviouslyReviewedAsReported = 'boolean'
        exporterToolHashes = 'array'; toolHashVerification = 'string'; interfaceProducerIdentity = 'string'
    } 'audit.sourceCapture'
    foreach ($name in @('captureManifestSha256', 'captureStatusSha256', 'baselineManifestSha256',
            'expectedBaselineManifestSha256', 'inventorySha256', 'graphSetSha256')) {
        Assert-SwiftUIAuditSha256 $source.$name "audit.sourceCapture.$name"
    }
    foreach ($pair in @(
        @('captureManifestSha256', $capture.captureSha256), @('captureStatusSha256', $capture.statusSha256),
        @('baselineManifestSha256', $capture.baselineManifestSha256), @('inventorySha256', $capture.inventorySha256),
        @('graphSetSha256', $capture.capture.inventory.graphSetSha256)
    )) {
        if ($source.($pair[0]) -cne $pair[1]) { throw "audit.sourceCapture.$($pair[0]) differs from the actual source capture." }
    }
    if ($source.status -cne $capture.capture.status -or
        $source.exactIdentityPreviouslyReviewedAsReported -ne $capture.capture.exactIdentityPreviouslyReviewed -or
        $source.toolHashVerification -cne 'recorded by capture; tool executables are not present in this artifact' -or
        $source.interfaceProducerIdentity -cne 'preserved in interface source-line facts; not inferred from the extractor') {
        throw 'Audit capture status or reported producer/extractor authority differs from its source.'
    }
    Assert-SwiftUIAuditJsonEqual $capture.capture.observedIdentity $source.observedExtractorIdentity 'audit.sourceCapture.observedExtractorIdentity'
    Assert-SwiftUIAuditJsonEqual $capture.capture.tools $source.exporterToolHashes 'audit.sourceCapture.exporterToolHashes'
    $reportedFixture = Get-SwiftUIAuditProperty $source 'syntheticFixtureAsReported'
    Assert-SwiftUIAuditJsonEqual (Get-SwiftUIBaselineProperty $capture.capture 'syntheticFixture') $reportedFixture 'audit.sourceCapture.syntheticFixtureAsReported'

    $countFields = @{}
    foreach ($name in @('graphs', 'preciseIdentifiers', 'declarationOccurrences', 'relationshipOccurrences',
            'graphFieldFacts', 'inventoryFacts', 'interfaceFiles', 'interfaceSourceLines', 'overlayFiles',
            'overlaySourceLines', 'candidateQueueRecords')) { $countFields[$name] = 'integer' }
    Assert-SwiftUIAuditFields $audit.counts $countFields 'audit.counts'
    foreach ($pair in @(
        @('graphs', $capture.capture.inventory.counts.graphs), @('preciseIdentifiers', $capture.capture.inventory.counts.preciseSymbols),
        @('declarationOccurrences', $capture.capture.inventory.counts.declarationOccurrences),
        @('relationshipOccurrences', $capture.capture.inventory.counts.relationshipOccurrences),
        @('interfaceFiles', $capture.publicInterfaces.Count), @('overlayFiles', $capture.crossImportDefinitions.Count)
    )) {
        if ($audit.counts.($pair[0]) -ne $pair[1]) { throw "audit.counts.$($pair[0]) differs from its source capture." }
    }
    Assert-SwiftUIAuditFields $audit.queues @{
        selectedFamilies = 'array'; selection = 'string'; affectsLedgerRecords = 'boolean'; applicability = 'string'
    } 'audit.queues'
    if ($audit.queues.selection -cne 'lexical-candidates-only' -or $audit.queues.affectsLedgerRecords -or
        $audit.queues.applicability -cne 'unreviewed; no availability, architecture, underscore, synthesized or deprecation filter') {
        throw 'Audit queues must remain unreviewed lexical candidates without filtering ledger records.'
    }
    $queueNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in $audit.queues.selectedFamilies) {
        if ($name -isnot [string] -or @('view-builder', 'binding-projections', 'image-resizing', 'long-press', 'file-export') -cnotcontains $name -or
            -not $queueNames.Add($name)) { throw 'Audit selected queue families contain an unknown or duplicate name.' }
    }
    Assert-SwiftUIAuditFields $audit.streaming @{ implementation = 'string'; sourceSha256 = 'string' } 'audit.streaming'
    if ($audit.streaming.implementation -cne 'bounded-raw-record-visitor-and-external-ordinal-audit-v1') {
        throw 'Unsupported audit ledger implementation.'
    }
    Assert-SwiftUIAuditSha256 $audit.streaming.sourceSha256 'audit.streaming.sourceSha256'
    if ($audit.generatorSources.Count -eq 0) { throw 'Audit must retain its reported generator source provenance.' }
    $generatorPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $audit.generatorSources) {
        Assert-SwiftUIAuditFields $entry @{ path = 'string'; sha256 = 'string' } 'audit.generatorSources'
        Assert-SwiftUIAuditSha256 $entry.sha256 'audit.generatorSources.sha256'
        if (-not $generatorPaths.Add($entry.path)) { throw 'Duplicate reported audit generator source.' }
    }
    # These describe the historical producer, not the scripts running now.
    # Their hashes are preserved; no current source equality is inferred.
    $expectedNames = @('identities.ndjson', 'occurrences.ndjson', 'relationships.ndjson', 'graph-fields.ndjson',
        'partitions.ndjson', 'inventory-facts.ndjson', 'interface-facts.ndjson', 'overlay-facts.ndjson', 'candidate-queues.ndjson')
    if ($audit.recordFiles.Count -ne $expectedNames.Count) { throw 'Audit must declare exactly the nine complete ledger streams.' }
    $records = [Collections.Generic.List[object]]::new()
    $recordNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $audit.recordFiles) {
        Assert-SwiftUIAuditFields $entry @{ path = 'string'; sha256 = 'string'; bytes = 'integer' } 'audit.recordFiles'
        Assert-SwiftUIAuditSha256 $entry.sha256 'audit.recordFiles.sha256'
        if ($expectedNames -cnotcontains $entry.path -or -not $recordNames.Add($entry.path)) {
            throw "Unexpected or duplicate audit record stream '$($entry.path)'."
        }
        $path = Resolve-SwiftUIAPIReviewArtifactPath $auditRootPath $entry.path
        if ((Get-Item -LiteralPath $path -Force).Length -ne $entry.bytes) { throw "Audit record stream '$($entry.path)' byte size differs from its manifest." }
        # Do not hash or parse these large files here. The streaming reader must
        # verify every declared digest and every record against authoritative input.
        $records.Add([pscustomobject]@{ path = $path; relativePath = $entry.path; sha256 = $entry.sha256; bytes = [long]$entry.bytes })
    }
    foreach ($item in Get-ChildItem -LiteralPath $auditRootPath -Force -File) {
        if ($item.Name.EndsWith('.ndjson', [StringComparison]::OrdinalIgnoreCase) -and -not $recordNames.Contains($item.Name)) {
            throw "Undeclared audit record stream '$($item.Name)'."
        }
    }

    $expectedCopies = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $expectedDirectories = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [void]$expectedDirectories.Add('source-metadata')
    $currentExpected = $null
    foreach ($entry in $capture.inputFiles) {
        $relative = $entry.relativePath
        if ($entry.kind -ceq 'expected-baseline-manifest') { $relative = 'expected-baseline-manifest.json'; $currentExpected = $entry }
        $copyRelative = 'source-metadata/' + $relative
        $expectedCopies.Add($copyRelative, $entry)
        for ($separator = $copyRelative.IndexOf('/'); $separator -ge 0; $separator = $copyRelative.IndexOf('/', $separator + 1)) {
            [void]$expectedDirectories.Add($copyRelative.Substring(0, $separator))
        }
    }
    if ($null -eq $currentExpected -or $audit.sourceMetadataFiles.Count -ne $expectedCopies.Count) {
        throw 'Audit source metadata must contain every sealed source input exactly once.'
    }
    $copies = [Collections.Generic.List[object]]::new()
    $copyNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $historical = $null
    foreach ($entry in $audit.sourceMetadataFiles) {
        Assert-SwiftUIAuditFields $entry @{ path = 'string'; sha256 = 'string'; bytes = 'integer'; kind = 'string' } 'audit.sourceMetadataFiles'
        Assert-SwiftUIAuditSha256 $entry.sha256 'audit.sourceMetadataFiles.sha256'
        if (-not $expectedCopies.ContainsKey($entry.path) -or -not $copyNames.Add($entry.path)) {
            throw "Unexpected or duplicate audit source metadata '$($entry.path)'."
        }
        $original = $expectedCopies[$entry.path]
        if ($entry.kind -cne $original.kind) { throw "Audit source metadata kind changed for '$($entry.path)'." }
        $path = Resolve-SwiftUIAPIReviewArtifactPath $auditRootPath $entry.path
        if ((Get-Item -LiteralPath $path -Force).Length -ne $entry.bytes) { throw "Audit source metadata byte size changed for '$($entry.path)'." }
        $sourcePath = $original.path
        if ($entry.kind -ceq 'expected-baseline-manifest') {
            $historical = Read-SwiftUIAuditMetadata $path $MaximumMetadataBytes
            if ($historical.sha256 -cne $entry.sha256 -or $historical.sha256 -cne $source.expectedBaselineManifestSha256) {
                throw 'Historical expected baseline copy does not match the audit producer''s recorded hash.'
            }
            Assert-SwiftUIAuditManifest $historical.value 'Historical expected baseline'
            if ($historical.value.baselineId -cne $capture.baselineManifest.baselineId) { throw 'Historical expected baseline ID differs from the source capture.' }
            Assert-SwiftUIAuditJsonEqual $capture.baselineManifest.scope $historical.value.scope 'Historical expected baseline.scope'
            Assert-SwiftUIAuditJsonEqual $capture.baselineManifest.toolchain $historical.value.toolchain 'Historical expected baseline.toolchain'
            [void](Assert-SwiftUIBaselineIdentity -Manifest $historical.value -Identity $capture.capture.observedIdentity)
            # A later baseline review may change reviewedIdentity/evidence. This
            # sealed historical file is not the current supplied baseline file.
            $sourcePath = $null
        } else {
            if ($entry.sha256 -cne $original.sha256 -or $entry.bytes -ne $original.bytes) {
                throw "Audit source metadata differs from its capture input '$($entry.path)'."
            }
            [void](Get-SwiftUIAuditHashedFile -Path $path -RelativePath $entry.path -Kind $entry.kind -ExpectedSha256 $entry.sha256)
        }
        $copies.Add([pscustomobject]@{ path = $path; relativePath = $entry.path; sha256 = $entry.sha256
            bytes = [long]$entry.bytes; kind = $entry.kind; sourcePath = $sourcePath })
    }
    # Reject undeclared metadata and directory aliases, including hidden files.
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push('source-metadata')
    while ($pending.Count -gt 0) {
        $relativeDirectory = $pending.Pop()
        $directory = Resolve-SwiftUIAPIReviewArtifactPath $auditRootPath $relativeDirectory -Kind Directory
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force) {
            $relative = $relativeDirectory + '/' + $item.Name
            [void](Resolve-SwiftUIAPIReviewArtifactPath $auditRootPath $relative -Kind Any)
            if ($item.PSIsContainer) {
                if (-not $expectedDirectories.Contains($relative)) { throw "Undeclared audit source metadata directory '$relative'." }
                $pending.Push($relative)
            }
            elseif (-not $copyNames.Remove($relative)) { throw "Undeclared audit source metadata '$relative'." }
        }
    }
    if ($copyNames.Count -ne 0) { throw 'Declared audit source metadata was missing during discovery.' }
    return [pscustomobject][ordered]@{
        captureContext = $capture; captureRoot = $capture.captureRoot; auditRoot = $auditRootPath
        auditManifest = $audit; auditManifestPath = $auditPath; auditManifestSha256 = $auditFile.sha256; auditSealSha256 = $seal.sha256
        recordFiles = $records.ToArray(); sourceMetadataFiles = $copies.ToArray(); graphInputs = $capture.graphInputs; counts = $audit.counts
        historicalExpectedBaselineManifest = $historical; historicalExpectedBaselineManifestPath = $historical.path
        historicalExpectedBaselineManifestSha256 = $historical.sha256
        currentExpectedBaselineManifest = $currentExpected; currentExpectedBaselineManifestPath = $currentExpected.path
        currentExpectedBaselineManifestSha256 = $currentExpected.sha256
    }
}

function ConvertTo-SwiftUIAPIReviewProcessArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    # .NET Framework has no ArgumentList. This is Windows argv quoting, not a
    # PowerShell/shell command string; the process is always started directly.
    $quoted = [Text.StringBuilder]::new()
    [void]$quoted.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$quoted.Append(('\' * (2 * $slashes + 1)))
        } else { [void]$quoted.Append(('\' * $slashes)) }
        $slashes = 0
        [void]$quoted.Append($character)
    }
    [void]$quoted.Append(('\' * (2 * $slashes)))
    [void]$quoted.Append('"')
    return $quoted.ToString()
}

function Invoke-SwiftUIAPIReviewGit {
    param([Parameter(Mandatory)][string]$Executable, [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string[]]$Arguments, [long]$MaximumOutputBytes = 1MB,
        [AllowNull()][IO.Stream]$OutputStream, [int]$TimeoutMilliseconds = 30000)

    if ($MaximumOutputBytes -lt 0) { throw 'Git output byte budget cannot be negative.' }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $allArguments = @('--no-pager', '--no-optional-locks', '--no-replace-objects', '--no-lazy-fetch', '--literal-pathspecs',
        '-c', 'core.fsmonitor=false', '-c', 'core.quotepath=false', '-C', $RepositoryRoot) + $Arguments
    if ($null -ne $info.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $allArguments) { $info.ArgumentList.Add($argument) }
    } else { $info.Arguments = [string]::Join(' ', [string[]]@($allArguments | ForEach-Object { ConvertTo-SwiftUIAPIReviewProcessArgument $_ })) }
    $info.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $info.EnvironmentVariables['GIT_NO_LAZY_FETCH'] = '1'
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $stdout = $OutputStream
    $ownsStdout = $null -eq $stdout
    if ($ownsStdout) { $stdout = [IO.MemoryStream]::new() }
    $stderr = [IO.MemoryStream]::new()
    $started = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    [long]$written = 0
    try {
        $started = $process.Start()
        if (-not $started) { throw 'Could not start read-only Git inspection.' }
        $outBuffer = [byte[]]::new(8192)
        $errBuffer = [byte[]]::new(8192)
        $outTask = $process.StandardOutput.BaseStream.ReadAsync($outBuffer, 0, $outBuffer.Length)
        $errTask = $process.StandardError.BaseStream.ReadAsync($errBuffer, 0, $errBuffer.Length)
        while ($null -ne $outTask -or $null -ne $errTask) {
            $remaining = $TimeoutMilliseconds - [int]$watch.ElapsedMilliseconds
            if ($remaining -le 0) { throw 'Read-only Git inspection timed out.' }
            [Threading.Tasks.Task[]]$tasks = @($outTask, $errTask | Where-Object { $null -ne $_ })
            if ([Threading.Tasks.Task]::WaitAny($tasks, $remaining) -lt 0) { throw 'Read-only Git inspection timed out.' }
            if ($null -ne $outTask -and $outTask.IsCompleted) {
                $count = $outTask.GetAwaiter().GetResult()
                if ($count -eq 0) { $outTask = $null } else {
                    if ($count -gt $MaximumOutputBytes - $written) { throw "Git stdout exceeds its $MaximumOutputBytes byte budget." }
                    $stdout.Write($outBuffer, 0, $count)
                    $written += $count
                    $outTask = $process.StandardOutput.BaseStream.ReadAsync($outBuffer, 0, $outBuffer.Length)
                }
            }
            if ($null -ne $errTask -and $errTask.IsCompleted) {
                $count = $errTask.GetAwaiter().GetResult()
                if ($count -eq 0) { $errTask = $null } else {
                    if ($stderr.Length + $count -gt 1MB) { throw 'Git stderr exceeds its metadata byte budget.' }
                    $stderr.Write($errBuffer, 0, $count)
                    $errTask = $process.StandardError.BaseStream.ReadAsync($errBuffer, 0, $errBuffer.Length)
                }
            }
        }
        $remaining = $TimeoutMilliseconds - [int]$watch.ElapsedMilliseconds
        if ($remaining -le 0 -or -not $process.WaitForExit($remaining)) { throw 'Read-only Git inspection timed out.' }
        $errorText = [Text.UTF8Encoding]::new($false, $true).GetString($stderr.ToArray())
        if ($process.ExitCode -ne 0) { throw "Read-only Git inspection failed with exit $($process.ExitCode): $errorText" }
        $text = $null
        if ($ownsStdout) { $text = [Text.UTF8Encoding]::new($false, $true).GetString($stdout.ToArray()) }
        return [pscustomobject]@{ text = $text; bytes = $written; stderr = $errorText }
    } finally {
        if ($started -and -not $process.HasExited) {
            try { $process.Kill(); [void]$process.WaitForExit(5000) } catch { }
        }
        $watch.Stop()
        $stderr.Dispose()
        if ($ownsStdout) { $stdout.Dispose() }
        $process.Dispose()
    }
}

function Assert-SwiftUIAPIReviewSourcePath {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or $Path -match '[\\:<>"|?*\x00-\x1f\x7f]') {
        throw "Windows source path '$Path' must be an exact portable relative Git path."
    }
    foreach ($component in $Path.Split('/')) {
        if ($component.Length -eq 0 -or $component -eq '.' -or $component -eq '..' -or $component -match '[. ]$' -or
            $component -imatch '\A(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|\z)') {
            throw "Windows source path '$Path' contains a nonportable or traversing component."
        }
    }
}

function Write-SwiftUIAPIReviewWindowsSources {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string[]]$RelativePaths, [Parameter(Mandatory)][string]$DestinationDirectory,
        [long]$MaximumSourceBytes = 16MB)

    $ErrorActionPreference = 'Stop'
    if ($Commit -cnotmatch '\A[0-9a-f]{40}\z') { throw 'Windows source Commit must be an exact full lowercase 40-character Git commit ID.' }
    if ($MaximumSourceBytes -le 0) { throw 'MaximumSourceBytes must be positive; it bounds each source and their combined bytes.' }
    if ($RelativePaths.Count -eq 0) { throw 'At least one exact Windows source path is required.' }
    foreach ($name in @('GIT_DIR', 'GIT_COMMON_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY',
            'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_SHALLOW_FILE', 'GIT_CONFIG', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS',
            'GIT_CONFIG_SYSTEM', 'GIT_CONFIG_GLOBAL', 'GIT_NAMESPACE', 'GIT_REPLACE_REF_BASE')) {
        if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) {
            throw "Windows source inspection rejects inherited Git override $name."
        }
    }
    $root = Resolve-SwiftUIBaselineFileSystemPath $RepositoryRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'RepositoryRoot must exist.' }
    $comparison = [StringComparison]::Ordinal
    if ([IO.Path]::DirectorySeparatorChar -eq '\') { $comparison = [StringComparison]::OrdinalIgnoreCase }
    $destination = [IO.Path]::GetFullPath($DestinationDirectory)
    $resolvedDestination = Resolve-SwiftUIBaselineFileSystemPath $destination
    if (-not $destination.Equals($resolvedDestination, $comparison)) { throw 'Windows source destination must not redirect through filesystem aliases.' }
    if (Test-Path -LiteralPath $destination) { throw 'Windows source destination already exists; source evidence is never overwritten.' }
    $parent = [IO.Path]::GetDirectoryName($destination)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw 'Windows source destination requires an existing owned parent directory.'
    }
    $gitCommand = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $gitArguments = @{ Executable = $gitCommand.Source; RepositoryRoot = $root }
    $observedRoot = (Invoke-SwiftUIAPIReviewGit @gitArguments -Arguments @('rev-parse', '--show-toplevel')).text.TrimEnd([char[]]"`r`n")
    $observedRoot = Resolve-SwiftUIBaselineFileSystemPath $observedRoot
    if (-not $observedRoot.Equals($root, $comparison)) { throw 'RepositoryRoot must be the exact Git worktree root.' }
    $resolvedCommit = (Invoke-SwiftUIAPIReviewGit @gitArguments -Arguments @('rev-parse', '--verify', ($Commit + '^{commit}'))).text.Trim()
    if ($resolvedCommit -cne $Commit) { throw 'Windows source Commit does not identify that exact commit object.' }

    $sources = [Collections.Generic.List[object]]::new()
    # Reject case aliases on every host so packets remain portable to Windows.
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [long]$totalBytes = 0
    foreach ($relative in $RelativePaths) {
        Assert-SwiftUIAPIReviewSourcePath $relative
        if (-not $paths.Add($relative)) { throw "Duplicate or aliased Windows source path '$relative'." }
        $tree = (Invoke-SwiftUIAPIReviewGit @gitArguments -Arguments @('ls-tree', '-z', '--full-tree', $Commit, '--', $relative)).text
        $treePattern = '\A(100644|100755) blob ([0-9a-f]{40})\t([^\x00]+)\x00\z'
        if ($tree -cnotmatch $treePattern -or $Matches[3] -cne $relative) {
            throw "Windows source '$relative' must be one exact tracked regular blob, not a tree, symlink, gitlink or pathspec match."
        }
        $blobOid = $Matches[2]
        $sizeText = (Invoke-SwiftUIAPIReviewGit @gitArguments -Arguments @('cat-file', '-s', $blobOid)).text
        [long]$size = 0
        if ($sizeText -cnotmatch '\A(?:0|[1-9][0-9]*)(?:\r?\n)?\z' -or
            -not [long]::TryParse($sizeText.Trim(), [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$size)) {
            throw "Git reported an invalid blob size for '$relative'."
        }
        if ($size -gt $MaximumSourceBytes - $totalBytes) { throw 'Selected Windows sources exceed MaximumSourceBytes (per file and combined).' }
        $totalBytes += $size
        $sources.Add([pscustomobject]@{ path = $relative; blobOid = $blobOid; bytes = $size })
    }
    $observedHead = $null
    $observedDirty = $null
    $observedChanges = @()
    $observationError = $null
    try {
        $observedHead = (Invoke-SwiftUIAPIReviewGit @gitArguments -Arguments @('rev-parse', '--verify', 'HEAD')).text.Trim()
        $statusText = (Invoke-SwiftUIAPIReviewGit @gitArguments -Arguments @('status', '--porcelain=v1', '-z', '--untracked-files=all', '--ignore-submodules=none')).text
        $observedDirty = $statusText.Length -ne 0
        $observedChanges = @($statusText.Split([char]0) | Where-Object { $_.Length -ne 0 })
    } catch { $observationError = $_.Exception.Message }

    $stageLeaf = '.swiftui-api-review-sources-' + [Guid]::NewGuid().ToString('N')
    $stage = Join-Path $parent $stageLeaf
    if (Test-Path -LiteralPath $stage) { throw 'Owned Windows source staging path already exists.' }
    [void][IO.Directory]::CreateDirectory($stage)
    $published = $false
    $failure = $null
    $files = [Collections.Generic.List[object]]::new()
    try {
        foreach ($source in $sources) {
            $path = Join-Path $stage $source.path
            [void](Get-SwiftUIBaselineRelativePath -Root $stage -Path $path)
            $canonical = Resolve-SwiftUIBaselineFileSystemPath $path
            if (-not $canonical.Equals([IO.Path]::GetFullPath($path), $comparison)) { throw 'Windows source staging child was redirected through an alias.' }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
            $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            $sha1 = [Security.Cryptography.SHA1]::Create()
            $sha256 = [Security.Cryptography.SHA256]::Create()
            try {
                $copied = Invoke-SwiftUIAPIReviewGit @gitArguments -Arguments @('cat-file', 'blob', $source.blobOid) -MaximumOutputBytes $source.bytes -OutputStream $stream
                if ($copied.bytes -ne $source.bytes -or $stream.Length -ne $source.bytes) { throw "Git blob byte length changed for '$($source.path)'." }
                $stream.Position = 0
                $sha256Text = [BitConverter]::ToString($sha256.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
                $header = [Text.Encoding]::ASCII.GetBytes('blob ' + $source.bytes.ToString([Globalization.CultureInfo]::InvariantCulture) + [char]0)
                [void]$sha1.TransformBlock($header, 0, $header.Length, $header, 0)
                $stream.Position = 0
                $buffer = [byte[]]::new(8192)
                while (($count = $stream.Read($buffer, 0, $buffer.Length)) -ne 0) { [void]$sha1.TransformBlock($buffer, 0, $count, $buffer, 0) }
                [void]$sha1.TransformFinalBlock([byte[]]::new(0), 0, 0)
                $actualOid = [BitConverter]::ToString($sha1.Hash).Replace('-', '').ToLowerInvariant()
                if ($actualOid -cne $source.blobOid) { throw "Copied Git blob bytes do not match '$($source.blobOid)'." }
            } finally { $sha256.Dispose(); $sha1.Dispose(); $stream.Dispose() }
            $files.Add([pscustomobject]@{ path = $source.path; blobOid = $source.blobOid; sha256 = $sha256Text
                bytes = $source.bytes; copiedPath = $source.path })
        }
        if (-not (Resolve-SwiftUIBaselineFileSystemPath $stage).Equals([IO.Path]::GetFullPath($stage), $comparison) -or
            -not (Resolve-SwiftUIBaselineFileSystemPath $destination).Equals($destination, $comparison)) {
            throw 'Windows source output paths changed before publication.'
        }
        if (Test-Path -LiteralPath $destination) { throw 'Windows source destination appeared before publication; source evidence is never overwritten.' }
        [IO.Directory]::Move($stage, $destination)
        $published = $true
    } catch { $failure = $_; throw } finally {
        if (-not $published -and (Test-Path -LiteralPath $stage)) {
            try {
                $canonical = Resolve-SwiftUIBaselineFileSystemPath $stage
                if (-not $canonical.Equals([IO.Path]::GetFullPath($stage), $comparison) -or
                    -not [IO.Path]::GetDirectoryName($canonical).Equals($parent, $comparison) -or
                    [IO.Path]::GetFileName($canonical) -cne $stageLeaf -or
                    ((Get-Item -LiteralPath $stage -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'Refusing unsafe Windows source staging cleanup.'
                }
                Remove-Item -LiteralPath $canonical -Recurse -Force -ErrorAction Stop
            } catch {
                if ($null -ne $failure) { throw [AggregateException]::new('Windows source copy and owned staging cleanup both failed.', [Exception[]]@($failure.Exception, $_.Exception)) }
                throw
            }
        }
    }
    $observationStatus = 'observed-checkout-only'
    if ($null -ne $observationError) {
        $observationStatus = 'unavailable-checkout-observation'
        if ($null -ne $observedHead) { $observationStatus = 'partial-checkout-observation' }
    }
    return [pscustomobject][ordered]@{
        commit = $Commit; files = $files.ToArray(); observedHead = $observedHead; observedDirty = $observedDirty
        observedChanges = $observedChanges; observationError = $observationError
        checkoutObservationStatus = $observationStatus; maximumSourceBytes = $MaximumSourceBytes; totalSourceBytes = $totalBytes
    }
}
