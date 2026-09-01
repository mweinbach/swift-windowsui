# Stage B collection helpers. Importing this file never launches a process.
# The public entrypoint supplies the real adapters only on macOS. Private tests
# exercise records and owned synthetic files without invoking a Swift tool.
. (Join-Path $PSScriptRoot 'swiftui-overlay-probe-intake.ps1')
. (Join-Path $PSScriptRoot 'swiftui-overlay-probe-native.ps1')
. (Join-Path $PSScriptRoot 'swiftui-overlay-probe-graphs.ps1')
. (Join-Path $PSScriptRoot 'swiftui-stateobject-process-common.ps1')

function Get-SwiftUIOverlayProbeCollectionPolicy {
    return [pscustomobject][ordered]@{
        profile = 'swiftui-overlay-native-collection-v1'
        publicSwiftSourceCommit = 'aa782beb23b8bd83bd16fca831532a05dd6cea39'
        maximumNativeRequests = [long]128
        perRequestSeconds = [long]120
        maximumBatchSeconds = [long]1200
        maximumDiagnosticBytes = [long]8MB
        maximumTraceBytes = [long]8MB
        maximumProfileBytes = [long]1MB
        maximumReportBytes = [long]16MB
        maximumLoadedFileBytes = [long]1GB
        maximumCopiedLoadedBytes = [long]8GB
        maximumRetainedFiles = [long]16384
        maximumRetainedBytes = [long]32GB
        outputSizeChecks = 'retained evidence and completed-output checks; not hard operating-system disk limits'
        descendantClosure = 'normal completion does not independently observe descendants; uncertain termination stops all subsequent native launches'
    }
}

function Assert-SwiftUIOverlayProbeExactFields {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string[]]$Names,
        [Parameter(Mandatory)][string]$Context)
    if ($Value -isnot [pscustomobject]) { throw "$Context must be a JSON object." }
    $actual = @($Value.PSObject.Properties.Name)
    if ($actual.Count -ne $Names.Count) { throw "$Context has missing or additional fields." }
    foreach ($name in $Names) {
        if ($actual -cnotcontains $name) { throw "$Context is missing exact field '$name'." }
    }
}

function Get-SwiftUIOverlayProbeBoundedHash {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][long]$MaximumBytes,
        [AllowNull()][string]$ExpectedSha256, [long]$ExpectedBytes = -1,
        [AllowNull()][string]$RelativePath, [string]$Kind = 'bounded-probe-file')
    if ($MaximumBytes -lt 0 -or $MaximumBytes -gt 32GB -or $ExpectedBytes -lt -1) { throw 'Unsupported bounded hash byte limit.' }
    $file = Assert-SwiftUIStateObjectRegularFile $Path
    $Path = $file.FullName
    if ($file.Length -gt $MaximumBytes -or ($ExpectedBytes -ge 0 -and $file.Length -ne $ExpectedBytes)) {
        throw 'Evidence file length differs from its bounded hash request.'
    }
    $length = [long]$file.Length; $write = $file.LastWriteTimeUtc.Ticks
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        if ($stream.Length -ne $length) { throw 'Evidence changed before bounded hashing.' }
        $buffer = [byte[]]::new(65536); $total = [long]0
        while ($true) {
            $count = $stream.Read($buffer, 0, [int][Math]::Min($buffer.Length, $length - $total + 1))
            if ($count -eq 0) { break }
            $total += $count
            if ($total -gt $length -or $total -gt $MaximumBytes) { throw 'Evidence grew beyond its counted hash bound.' }
            [void]$algorithm.TransformBlock($buffer, 0, $count, $null, 0)
        }
        if ($total -ne $length -or $stream.Length -ne $length) { throw 'Evidence changed during bounded hashing.' }
        [void]$algorithm.TransformFinalBlock([byte[]]@(), 0, 0)
        $sha = [BitConverter]::ToString($algorithm.Hash).Replace('-', '').ToLowerInvariant()
    } finally { try { $algorithm.Dispose() } finally { $stream.Dispose() } }
    $after = Assert-SwiftUIStateObjectRegularFile $Path
    if ($after.Length -ne $length -or $after.LastWriteTimeUtc.Ticks -ne $write) { throw 'Evidence metadata changed during bounded hashing.' }
    if (-not [string]::IsNullOrEmpty($ExpectedSha256)) {
        Assert-SwiftUIAuditSha256 $ExpectedSha256 'bounded-file.expectedSha256'
        if ($sha -cne $ExpectedSha256) { throw 'Evidence does not match its bounded expected hash.' }
    }
    return [pscustomobject]@{ path = $file.FullName; relativePath = $RelativePath; bytes = $length; sha256 = $sha; kind = $Kind }
}

function Write-SwiftUIOverlayProbeNewJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value,
        [long]$MaximumBytes = 16MB)
    $text = (ConvertTo-Json -InputObject $Value -Depth 100 -WarningAction Stop) + [char]10
    $bytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($text)
    if ($bytes.LongLength -gt $MaximumBytes) { throw 'Probe JSON exceeds its explicit byte limit.' }
    Write-SwiftUIOverlayNewFile -Path $Path -Bytes $bytes
    return Get-SwiftUIOverlayProbeBoundedHash -Path $Path -RelativePath ([IO.Path]::GetFileName($Path)) -Kind 'probe-metadata' -MaximumBytes $MaximumBytes -ExpectedBytes $bytes.LongLength
}

function Read-SwiftUIOverlayProbeMetadata {
    param([Parameter(Mandatory)][string]$Path, [long]$MaximumBytes = 16MB)
    $absolute = (Assert-SwiftUIStateObjectRegularFile $Path).FullName
    return Read-SwiftUIOverlayMetadata -Path $absolute -MaximumBytes $MaximumBytes
}

function New-SwiftUIOverlayProbeOutputDirectory {
    param([Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ForbiddenRoots)
    if (-not [IO.Path]::IsPathFullyQualified($Path) -or $Path -match '[\x00-\x1f\x7f]') {
        throw 'Probe output must be an absolute filesystem path without control characters.'
    }
    $full = [IO.Path]::GetFullPath($Path)
    $resolved = Resolve-SwiftUIBaselineFileSystemPath $full
    if ($full -cne $resolved) { throw 'Probe output must not redirect through filesystem aliases.' }
    $repository = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
    $allowed = $false
    foreach ($root in @((Join-Path $repository 'artifacts'), [IO.Path]::GetTempPath())) {
        $physical = Resolve-SwiftUIBaselineFileSystemPath $root
        try {
            $relative = Get-SwiftUIBaselineRelativePath -Root $physical -Path $resolved
            if (-not [string]::IsNullOrWhiteSpace($relative) -and $relative -cne '.') { $allowed = $true }
        } catch { }
    }
    if (-not $allowed) { throw 'Probe output must be a new child of repository artifacts or OS temp.' }
    foreach ($root in $ForbiddenRoots) {
        $physical = Resolve-SwiftUIBaselineFileSystemPath $root
        $inside = $false
        try { [void](Get-SwiftUIBaselineRelativePath -Root $physical -Path $resolved); $inside = $true } catch { }
        if ($inside) { throw 'Probe output cannot modify a source capture, census, ledger, or live tool/SDK tree.' }
    }
    if (Test-Path -LiteralPath $resolved) { throw 'Probe output already exists; there is no overwrite or retry.' }
    $parent = [IO.Path]::GetDirectoryName($resolved)
    [void][IO.Directory]::CreateDirectory($parent)
    if ((Resolve-SwiftUIBaselineFileSystemPath $parent) -cne $parent) {
        throw 'Probe output parent changed or redirects through an alias.'
    }
    [void][IO.Directory]::CreateDirectory($resolved)
    return $resolved
}

function Get-SwiftUIOverlayProbeLiveFile {
    param([Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedPhysicalRoot,
        [long]$MaximumBytes = 1GB)
    $logical = ConvertTo-SwiftUIOverlayUnixPath $Path
    if ($logical -cne $Path) { throw 'A live probe path must use its exact canonical POSIX spelling.' }
    $boundary = ConvertTo-SwiftUIOverlayUnixPath $AllowedPhysicalRoot
    if ($boundary -cne $AllowedPhysicalRoot) { throw 'A live probe boundary must be canonical.' }
    $physical = Resolve-SwiftUIBaselineFileSystemPath $logical
    if (-not (Test-SwiftUIOverlayInside -Root $boundary -Path $physical)) {
        throw 'A live probe file resolves outside its explicitly selected physical boundary.'
    }
    $file = Assert-SwiftUIStateObjectRegularFile $physical
    if ($file.Length -lt 0 -or $file.Length -gt $MaximumBytes) { throw 'A live probe file exceeds its byte limit.' }
    $beforeLength = $file.Length
    $beforeWrite = $file.LastWriteTimeUtc.Ticks
    $bounded = Get-SwiftUIOverlayProbeBoundedHash -Path $physical -MaximumBytes $MaximumBytes -ExpectedBytes $beforeLength
    $digest = $bounded.sha256
    $after = Assert-SwiftUIStateObjectRegularFile $physical
    if ($after.Length -ne $beforeLength -or $after.LastWriteTimeUtc.Ticks -ne $beforeWrite -or
        (Resolve-SwiftUIBaselineFileSystemPath $logical) -cne $physical) {
        throw 'A live probe file changed during the recorded hash observation.'
    }
    return [pscustomobject][ordered]@{
        path = $logical; canonicalPath = $physical; bytes = [long]$beforeLength; sha256 = $digest
        allowedPhysicalRoot = $boundary
        observation = 'path, length, last-write time and content checks; not atomic loaded-image attestation'
    }
}

function Get-SwiftUIOverlayProbeSelectedRoots {
    param([Parameter(Mandatory)]$Inputs)
    $roots = [Collections.Generic.List[object]]::new()
    foreach ($root in $Inputs.rootPlanContext.plan.roots) {
        if ($root.selection -ceq 'not-selected') { continue }
        $fact = @($Inputs.discovery.report.roots | Where-Object { $_.rootId -ceq $root.rootId })
        if ($fact.Count -ne 1) { throw 'The selected root has no unique census root receipt.' }
        if ($fact[0].state -ceq 'absent-confirmed') {
            # A saved absence is not a fresh filesystem fact. Only a typed
            # not-found result qualifies here; access and I/O errors propagate.
            $absent = $false
            try { [void][IO.File]::GetAttributes($root.logicalPath) }
            catch [IO.FileNotFoundException] { $absent = $true }
            catch [IO.DirectoryNotFoundException] { $absent = $true }
            if (-not $absent) { throw 'A selected optional root no longer matches its recorded absence.' }
            [void]$roots.Add([pscustomobject][ordered]@{
                rootId = $root.rootId; logicalPath = $root.logicalPath
                physicalPath = $root.expectedPhysicalPath; state = 'absent-confirmed'
            })
            continue
        }
        if ($fact[0].state -cne 'readable-complete' -or -not $fact[0].traversalComplete) {
            throw 'A selected probe root was not completely observed.'
        }
        if ((Resolve-SwiftUIBaselineFileSystemPath $root.logicalPath) -cne $root.expectedPhysicalPath) {
            throw 'A selected live root no longer matches its census physical path.'
        }
        [void](Assert-SwiftUIOverlayGraphPath -Path $root.expectedPhysicalPath -Kind Directory)
        [void]$roots.Add([pscustomobject][ordered]@{
            rootId = $root.rootId; logicalPath = $root.logicalPath
            physicalPath = $root.expectedPhysicalPath; state = 'readable-complete'
        })
    }
    return ,$roots.ToArray()
}

function Write-SwiftUIOverlayProbeNativeProfile {
    param([Parameter(Mandatory)]$Inputs, [Parameter(Mandatory)][string]$FrontendPath,
        [Parameter(Mandatory)][string]$OutputDirectory)
    if ($Inputs.syntheticFixture) { throw 'Synthetic input cannot create a live native profile.' }
    $layout = Get-SwiftUIOverlayExpectedLayout -SourceContext $Inputs.source
    $expectedFrontend = $layout.toolchain + '/usr/bin/swift-frontend'
    if ($FrontendPath -cne $expectedFrontend) {
        throw 'The frontend must be explicitly named at the selected XcodeDefault path; no inferred tool is substituted.'
    }
    $roots = Get-SwiftUIOverlayProbeSelectedRoots $Inputs
    $anchors = [Collections.Generic.List[object]]::new()
    foreach ($anchor in $Inputs.rootPlanContext.plan.identityAnchors) {
        $live = Get-SwiftUIOverlayProbeLiveFile -Path $anchor.logicalPath -AllowedPhysicalRoot $anchor.allowedPhysicalBoundary
        if ($live.sha256 -cne $anchor.expectedSha256) { throw 'A native-profile anchor differs from the saved capture.' }
        [void]$anchors.Add([pscustomobject][ordered]@{ anchorId = $anchor.anchorId; file = $live })
    }
    $extractor = @($anchors | Where-Object { $_.anchorId -ceq 'extractor-tool' })
    if ($extractor.Count -ne 1) { throw 'A native profile requires the exact captured extractor anchor.' }
    $frontend = Get-SwiftUIOverlayProbeLiveFile -Path $FrontendPath -AllowedPhysicalRoot $extractor[0].file.allowedPhysicalRoot
    $profile = [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'swiftui-overlay-native-tool-profile'
        status = 'metadata-recorded-awaiting-explicit-plan-selection'; syntheticFixture = $false
        sourceArtifacts = $Inputs.sourceArtifacts
        nativeEvidenceProfile = 'public-swift-6.3-overlay-load-v1'
        publicSwiftSourceCommit = (Get-SwiftUIOverlayProbeCollectionPolicy).publicSwiftSourceCommit
        developerDirectory = $layout.developer; sdkPath = $layout.sdk; toolchainPath = $layout.toolchain
        selectedRoots = $roots; anchors = $anchors.ToArray(); frontend = $frontend; extractor = $extractor[0].file
        observedExtractorIdentityAsRecorded = $Inputs.source.inputs.captureContext.capture.observedIdentity
        observations = [pscustomobject][ordered]@{
            nativeCommandsExecuted = $false; frontendVersionExecuted = $false
            frontendIdentityMeaning = 'separately named and hashed file; not inferred from the recorded swift compiler version'
            nativeProcessSandboxEstablished = $false; wholeSDKByteIdentityEstablished = $false
        }
        qualification = [pscustomobject][ordered]@{
            reviewedIdentity = $false; declarationCompleteness = $false; overlayCompleteness = $false; behaviorConformance = $false
        }
    }
    Assert-SwiftUIOverlayProbeInputSeals $Inputs
    $forbidden = @($Inputs.source.inputs.captureContext.captureRoot, $Inputs.source.inputs.auditRoot,
        (Split-Path -Parent $Inputs.discovery.path), $layout.sdk, $layout.toolchain)
    $output = New-SwiftUIOverlayProbeOutputDirectory -Path $OutputDirectory -ForbiddenRoots $forbidden
    $file = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $output 'native-profile.json') -Value $profile -MaximumBytes 1MB
    $seal = [Text.UTF8Encoding]::new($false).GetBytes($file.sha256 + '  native-profile.json' + [char]10)
    Write-SwiftUIOverlayNewFile -Path (Join-Path $output 'native-profile.sha256') -Bytes $seal
    return [pscustomobject]@{
        path = Join-Path $output 'native-profile.json'; sha256 = $file.sha256; bytes = $file.bytes
        status = $profile.status; nativeCommandsExecuted = $false; qualification = $profile.qualification
    }
}

function Read-SwiftUIOverlayProbeNativeProfile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ExpectedSha256,
        [Parameter(Mandatory)]$Inputs)
    Assert-SwiftUIAuditSha256 $ExpectedSha256 'native-profile.expectedSha256'
    $Path = (Assert-SwiftUIStateObjectRegularFile $Path).FullName
    $file = Read-SwiftUIOverlayProbeMetadata -Path $Path -MaximumBytes 1MB
    if ($file.sha256 -cne $ExpectedSha256) { throw 'The native profile differs from the explicitly selected plan hash.' }
    $profile = $file.value
    Assert-SwiftUIOverlayProbeFields $profile @{
        schemaVersion='integer'; evidenceKind='string'; status='string'; syntheticFixture='boolean'
        sourceArtifacts='object'; nativeEvidenceProfile='string'; publicSwiftSourceCommit='string'
        developerDirectory='string'; sdkPath='string'; toolchainPath='string'; selectedRoots='array'; anchors='array'
        frontend='object'; extractor='object'; observedExtractorIdentityAsRecorded='object'; observations='object'; qualification='object'
    } 'native-profile'
    if (($profile.schemaVersion -isnot [int] -and $profile.schemaVersion -isnot [long]) -or
        $profile.schemaVersion -ne 1 -or $profile.evidenceKind -cne 'swiftui-overlay-native-tool-profile' -or
        $profile.status -cne 'metadata-recorded-awaiting-explicit-plan-selection' -or
        $profile.syntheticFixture -isnot [bool] -or $profile.syntheticFixture -or $Inputs.syntheticFixture -or
        $profile.nativeEvidenceProfile -cne 'public-swift-6.3-overlay-load-v1' -or
        $profile.publicSwiftSourceCommit -cne (Get-SwiftUIOverlayProbeCollectionPolicy).publicSwiftSourceCommit) {
        throw 'Unsupported, synthetic or promoted native profile.'
    }
    Assert-SwiftUIAuditJsonEqual -Expected $Inputs.sourceArtifacts -Actual $profile.sourceArtifacts -Context 'native-profile.sourceArtifacts'
    $layout = Get-SwiftUIOverlayExpectedLayout -SourceContext $Inputs.source
    if ($profile.developerDirectory -cne $layout.developer -or $profile.sdkPath -cne $layout.sdk -or
        $profile.toolchainPath -cne $layout.toolchain -or $profile.frontend.path -cne ($layout.toolchain + '/usr/bin/swift-frontend') -or
        $profile.extractor.path -cne ($layout.toolchain + '/usr/bin/swift-symbolgraph-extract')) {
        throw 'Native profile paths differ from the original selected installation.'
    }
    Assert-SwiftUIAuditJsonEqual -Expected $Inputs.source.inputs.captureContext.capture.observedIdentity `
        -Actual $profile.observedExtractorIdentityAsRecorded -Context 'native-profile.extractorIdentity'
    Assert-SwiftUIOverlayProbeFields $profile.observations @{
        nativeCommandsExecuted='boolean'; frontendVersionExecuted='boolean'; frontendIdentityMeaning='string'
        nativeProcessSandboxEstablished='boolean'; wholeSDKByteIdentityEstablished='boolean'
    } 'native-profile.observations'
    foreach ($field in @('nativeCommandsExecuted', 'frontendVersionExecuted', 'nativeProcessSandboxEstablished', 'wholeSDKByteIdentityEstablished')) {
        if ($profile.observations.$field -isnot [bool] -or $profile.observations.$field) { throw 'Native metadata cannot promote execution or filesystem claims.' }
    }
    if ($profile.observations.frontendIdentityMeaning -cne 'separately named and hashed file; not inferred from the recorded swift compiler version') {
        throw 'The frontend identity interpretation differs from the fixed profile.'
    }
    Assert-SwiftUIOverlayProbeExactFields $profile.qualification @('reviewedIdentity', 'declarationCompleteness', 'overlayCompleteness', 'behaviorConformance') 'native-profile.qualification'
    foreach ($field in @('reviewedIdentity', 'declarationCompleteness', 'overlayCompleteness', 'behaviorConformance')) {
        if ($profile.qualification.$field -isnot [bool] -or $profile.qualification.$field) { throw 'A native profile cannot promote qualification.' }
    }
    $expectedAnchors = $Inputs.rootPlanContext.plan.identityAnchors
    if ($profile.anchors -isnot [Array] -or $profile.anchors.Count -ne $expectedAnchors.Count) { throw 'Native profile anchor set is incomplete.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($anchor in $profile.anchors) {
        Assert-SwiftUIOverlayProbeFields $anchor @{ anchorId='string'; file='object' } 'native-profile.anchor'
        $expected = @($expectedAnchors | Where-Object { $_.anchorId -ceq $anchor.anchorId })
        if ($expected.Count -ne 1 -or -not $seen.Add($anchor.anchorId) -or
            $anchor.file.path -cne $expected[0].logicalPath -or $anchor.file.sha256 -cne $expected[0].expectedSha256 -or
            $anchor.file.allowedPhysicalRoot -cne $expected[0].allowedPhysicalBoundary) { throw 'Native profile anchor does not match its exact captured occurrence.' }
    }
    foreach ($entry in @($profile.anchors.file) + @($profile.frontend, $profile.extractor)) {
        Assert-SwiftUIOverlayProbeFields $entry @{
            path='string'; canonicalPath='string'; bytes='integer'; sha256='string'; allowedPhysicalRoot='string'; observation='string'
        } 'native-profile.file'
        Assert-SwiftUIAuditSha256 $entry.sha256 'native-profile.file.sha256'
        if ($entry.observation -cne 'path, length, last-write time and content checks; not atomic loaded-image attestation') {
            throw 'Unsupported native file observation interpretation.'
        }
        if (($entry.bytes -isnot [long] -and $entry.bytes -isnot [int]) -or $entry.bytes -lt 1 -or $entry.bytes -gt 1GB -or
            (ConvertTo-SwiftUIOverlayUnixPath $entry.path) -cne $entry.path -or
            (ConvertTo-SwiftUIOverlayUnixPath $entry.canonicalPath) -cne $entry.canonicalPath -or
            -not (Test-SwiftUIOverlayInside -Root $entry.allowedPhysicalRoot -Path $entry.canonicalPath)) {
            throw 'A native profile file is outside its bound path or byte limits.'
        }
    }
    $extractorAnchor = @($profile.anchors | Where-Object { $_.anchorId -ceq 'extractor-tool' })
    if ($extractorAnchor.Count -ne 1 -or $profile.frontend.allowedPhysicalRoot -cne $extractorAnchor[0].file.allowedPhysicalRoot) {
        throw 'Frontend boundary cannot expand beyond the captured physical toolchain.'
    }
    Assert-SwiftUIAuditJsonEqual -Expected $extractorAnchor[0].file -Actual $profile.extractor -Context 'native-profile.extractor'
    return [pscustomobject]@{ file = $file; profile = $profile }
}

function Assert-SwiftUIOverlayProbeLiveProfile {
    param([Parameter(Mandatory)]$Inputs, [Parameter(Mandatory)]$NativeProfile)
    $roots = Get-SwiftUIOverlayProbeSelectedRoots $Inputs
    Assert-SwiftUIAuditJsonEqual -Expected $NativeProfile.profile.selectedRoots -Actual $roots -Context 'native-profile.liveRoots'
    $checks = [Collections.Generic.List[object]]::new()
    foreach ($entry in @($NativeProfile.profile.anchors.file) + @($NativeProfile.profile.frontend)) {
        $actual = Get-SwiftUIOverlayProbeLiveFile -Path $entry.path -AllowedPhysicalRoot $entry.allowedPhysicalRoot
        if ($actual.canonicalPath -cne $entry.canonicalPath -or $actual.bytes -ne $entry.bytes -or $actual.sha256 -cne $entry.sha256) {
            throw 'The selected frontend, extractor, SDK settings or interface bytes changed before a native request.'
        }
        [void]$checks.Add($actual)
    }
    return ,$checks.ToArray()
}

function New-SwiftUIOverlayProbeRequestSchedule {
    param([Parameter(Mandatory)]$Plan)
    $requests = [Collections.Generic.List[object]]::new()
    foreach ($pair in $Plan.pairs) {
        if ($pair.overlayNameOccurrences.Count -eq 0) { continue }
        foreach ($context in $Plan.targetContexts) {
            $candidates = @($pair.sourceCandidates | Where-Object { $_.target -ceq $context.target })
            if ($candidates.Count -ne 1) { throw 'A probe context requires one exact source candidate occurrence.' }
            foreach ($control in (Get-SwiftUIOverlayProbeNativePolicy).controls) {
                # Constructing the source now rejects unsupported/self imports
                # before any request in the batch can launch.
                $source = New-SwiftUIOverlayProbeSource $pair.declaringModule $pair.bystanderModule $control
                $id = Get-SwiftUIOverlayId @('native-import-request-v1', $Plan.file.sha256,
                    $pair.pairId, $context.target, $context.cxxInteroperabilityMode, $control)
                [void]$requests.Add([pscustomobject][ordered]@{
                    requestId = $id; kind = 'frontend-import'; pairId = $pair.pairId
                    definitionOccurrenceId = $pair.definitionOccurrenceId
                    rawDefinitionSha256 = $pair.rawDefinitionSha256
                    declaringModule = $pair.declaringModule; bystanderModule = $pair.bystanderModule
                    overlayNameOccurrences = $pair.overlayNameOccurrences
                    candidateRecordIds = @($candidates[0].recordId)
                    target = $context.target; cxxMode = $context.cxxInteroperabilityMode
                    control = $control; source = $source
                })
            }
        }
    }
    if ($requests.Count -gt 64) { throw 'The fixed four-control import schedule exceeds 64 requests.' }
    return ,$requests.ToArray()
}

function New-SwiftUIOverlayProbeScheduleState {
    return [pscustomobject]@{
        clock = [Diagnostics.Stopwatch]::StartNew(); requestAttempts = 0
        stopped = $false; stopReason = $null; descendantClosureRequired = $false
        results = [Collections.Generic.List[object]]::new()
    }
}

function Invoke-SwiftUIOverlayProbeSchedule {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Requests,
        [Parameter(Mandatory)]$State, [Parameter(Mandatory)][scriptblock]$Execute,
        [AllowNull()]$Context)
    # The callback is an internal test seam. Neither public CLI parameter set
    # accepts callbacks or synthetic receipts. Native and fake tests exercise
    # this same stop-before-next-request controller.
    $policy = Get-SwiftUIOverlayProbeCollectionPolicy
    foreach ($request in $Requests) {
        if (-not $State.stopped -and ($State.requestAttempts -ge $policy.maximumNativeRequests -or
            $State.clock.Elapsed.TotalSeconds -ge $policy.maximumBatchSeconds)) {
            $State.stopped = $true; $State.stopReason = 'request-or-elapsed-batch-budget'
        }
        if ($State.stopped) {
            $State.results.Add([pscustomobject][ordered]@{
                requestId = $request.requestId; kind = $request.kind; outcome = 'not-run'
                reason = $State.stopReason; nativeInvocationAttempted = $false; processStarted = $false
                stopLaterCommands = $true; descendantClosureRequired = $State.descendantClosureRequired
                resultFile = $null; positiveFrontendObservations = @(); assessments = @()
            })
            continue
        }
        $State.requestAttempts++
        try {
            $values = @(& $Execute $request $Context)
            if ($values.Count -ne 1 -or $values[0] -isnot [pscustomobject] -or
                $values[0].requestId -cne $request.requestId -or $values[0].kind -cne $request.kind -or
                $values[0].stopLaterCommands -isnot [bool] -or
                $values[0].descendantClosureRequired -isnot [bool] -or
                ($values[0].descendantClosureRequired -and -not $values[0].stopLaterCommands)) {
                throw 'A request executor did not return its one exact bounded closure receipt.'
            }
            $result = $values[0]
        } catch {
            # A thrown adapter does not establish that Process.Start was never
            # reached. Treat the launch as unknown and never invoke it again.
            $result = [pscustomobject][ordered]@{
                requestId = $request.requestId; kind = $request.kind; outcome = 'execution-adapter-failed'
                error = $_.Exception.Message; nativeInvocationAttempted = $null; processStarted = $null
                stopLaterCommands = $true; descendantClosureRequired = $true
                resultFile = $null; positiveFrontendObservations = @(); assessments = @()
            }
        }
        $State.results.Add($result)
        if ($result.stopLaterCommands) {
            $State.stopped = $true; $State.stopReason = $result.outcome
            $State.descendantClosureRequired = $result.descendantClosureRequired
        }
    }
}

function New-SwiftUIOverlayProbeOwnedDirectory {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$RelativePath)
    $path = Resolve-SwiftUIOverlayGraphRelativePath -Root $Root -RelativePath $RelativePath
    [void](Assert-SwiftUIOverlayGraphPath -Path $Root -Kind Directory)
    [void](Assert-SwiftUIOverlayGraphPath -Path $path -Kind Absent)
    [void][IO.Directory]::CreateDirectory($path)
    [void](Assert-SwiftUIOverlayGraphPath -Path $path -Kind Directory)
    return $path
}

function Copy-SwiftUIOverlayProbeBoundedFile {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][long]$MaximumBytes, [AllowNull()][string]$ExpectedSha256)
    $file = Assert-SwiftUIStateObjectRegularFile $Source
    $Source = $file.FullName
    [void](Assert-SwiftUIOverlayGraphPath -Path $Destination -Kind Absent)
    if ($file.Length -gt $MaximumBytes) { throw 'Retained evidence file exceeds its copy budget.' }
    $inputStream = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $outputStream = $null
    try {
        if ($inputStream.Length -ne $file.Length) { throw 'Evidence length changed before its retained copy.' }
        $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $buffer = [byte[]]::new(65536); $total = [long]0
        while (($count = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $total += $count
            if ($total -gt $MaximumBytes -or $total -gt $file.Length) { throw 'Evidence grew beyond its copy budget.' }
            $outputStream.Write($buffer, 0, $count)
        }
        if ($total -ne $file.Length) { throw 'Evidence changed during its retained copy.' }
        $outputStream.Flush()
    } finally {
        try { if ($null -ne $outputStream) { $outputStream.Dispose() } } finally { $inputStream.Dispose() }
    }
    $copy = Get-SwiftUIOverlayProbeBoundedHash -Path $Destination -Kind 'retained-native-evidence' -MaximumBytes $MaximumBytes -ExpectedBytes $file.Length
    if (-not [string]::IsNullOrEmpty($ExpectedSha256) -and $copy.sha256 -cne $ExpectedSha256) {
        throw 'Retained evidence bytes differ from the bound source hash.'
    }
    return $copy
}

function Get-SwiftUIOverlayProbePathObservations {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)]$Diagnostics, [Parameter(Mandatory)][string]$CellEvidence,
        [Parameter(Mandatory)][string]$CellCache)
    $observations = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $requestedNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($occurrence in $Request.overlayNameOccurrences) { [void]$requestedNames.Add($occurrence.name) }
    $moduleRoot = $null
    foreach ($load in $Diagnostics.loads) {
        if (-not $requestedNames.Contains($load.module)) { continue }
        foreach ($path in @($load.sourcePath, $load.loadedPath)) {
            if (-not $seen.Add($path)) { continue }
            $observation = [ordered]@{
                path = $path; canonicalPath = $null; status = 'not-authorized'
                bytes = $null; sha256 = $null; retainedFile = $null; error = $null
            }
            try {
                Assert-SwiftUIOverlayProbeNativePath $path
                # Resolving aliases may query incidental target metadata. No
                # outward file content is read until the physical check passes.
                $physical = Resolve-SwiftUIBaselineFileSystemPath $path
                $boundaries = @($Session.nativeProfile.profile.selectedRoots | Where-Object { $_.state -ceq 'readable-complete' } |
                    ForEach-Object { $_.physicalPath }) + @($CellCache)
                $boundary = $null
                foreach ($root in $boundaries) {
                    if (Test-SwiftUIOverlayInside -Root $root -Path $physical) { $boundary = $root; break }
                }
                if ($null -ne $boundary) {
                    $policy = Get-SwiftUIOverlayProbeCollectionPolicy
                    $live = Get-SwiftUIOverlayProbeLiveFile -Path $path -AllowedPhysicalRoot $boundary -MaximumBytes $policy.maximumLoadedFileBytes
                    if ($Session.loadedBytes + $live.bytes -gt $policy.maximumCopiedLoadedBytes) { throw 'The batch loaded-file retention budget is exhausted.' }
                    # Failed partial copies still occupy disk and consume the
                    # reserved retention budget for this batch.
                    $Session.loadedBytes += $live.bytes
                    if ($null -eq $moduleRoot) { $moduleRoot = New-SwiftUIOverlayProbeOwnedDirectory -Root $CellEvidence -RelativePath 'modules' }
                    $fileName = (Get-SwiftUIOverlayId @('loaded-path-v1', $path)) + '.bytes'
                    $copy = Copy-SwiftUIOverlayProbeBoundedFile -Source $live.canonicalPath -Destination (Join-Path $moduleRoot $fileName) `
                        -MaximumBytes $policy.maximumLoadedFileBytes -ExpectedSha256 $live.sha256
                    $after = Get-SwiftUIOverlayProbeLiveFile -Path $path -AllowedPhysicalRoot $boundary -MaximumBytes $policy.maximumLoadedFileBytes
                    Assert-SwiftUIAuditJsonEqual -Expected $live -Actual $after -Context 'loaded-file.afterCopy'
                    $observation.canonicalPath = $live.canonicalPath; $observation.status = 'recorded'
                    $observation.bytes = $copy.bytes; $observation.sha256 = $copy.sha256
                    $observation.retainedFile = Get-SwiftUIBaselineRelativePath -Root $Session.output -Path $copy.path
                }
            } catch { $observation.status = 'failed'; $observation.error = $_.Exception.Message }
            $observations.Add([pscustomobject]$observation)
        }
    }
    return ,$observations.ToArray()
}

function Invoke-SwiftUIOverlayProbeNativeRequest {
    param([Parameter(Mandatory)]$Request, [Parameter(Mandatory)]$Session)
    if (-not $IsMacOS -or $Session.executionKind -cne 'native' -or $Session.inputs.syntheticFixture) {
        throw 'Only explicitly planned native macOS collection can call the process adapter.'
    }
    $policy = Get-SwiftUIOverlayProbeCollectionPolicy
    $result = [ordered]@{
        requestId = $Request.requestId; kind = $Request.kind; outcome = 'not-run'
        nativeInvocationAttempted = $false; processStarted = $false
        stopLaterCommands = $true; descendantClosureRequired = $false; descendantsClosed = $null
        descendantClosureStatus = 'not-independently-observed'; error = $null
        process = $null; processOutcome = $null; pathObservations = @(); assessments = @(); positiveFrontendObservations = @()
        requestFile = $null; resultFile = $null; liveChecksBefore = @(); liveChecksAfter = @()
    }
    $cell = New-SwiftUIOverlayProbeOwnedDirectory -Root $Session.output -RelativePath ('evidence/' + $Request.requestId)
    $work = New-SwiftUIOverlayProbeOwnedDirectory -Root $Session.output -RelativePath ('.work/requests/' + $Request.requestId)
    $cache = New-SwiftUIOverlayProbeOwnedDirectory -Root $work -RelativePath 'module-cache'
    $temporary = New-SwiftUIOverlayProbeOwnedDirectory -Root $work -RelativePath 'tmp'
    $sourcePath = $null; $tracePath = $null; $graphs = $null
    $launchState = 'not-run'; $process = $null
    try {
        [void](Get-SwiftUIOverlayProbeBoundedHash -Path $Session.plan.file.path -Kind 'selected-plan' -ExpectedSha256 $Session.plan.file.sha256 -MaximumBytes 1MB)
        [void](Get-SwiftUIOverlayProbeBoundedHash -Path $Session.nativeProfile.file.path -Kind 'selected-native-profile' -ExpectedSha256 $Session.nativeProfile.file.sha256 -MaximumBytes 1MB)
        foreach ($tool in $Session.toolingSeals) {
            [void](Assert-SwiftUIStateObjectRegularFile $tool.path)
            [void](Get-SwiftUIOverlayProbeBoundedHash -Path $tool.path -Kind 'collector-source' -ExpectedSha256 $tool.sha256 -MaximumBytes 2MB)
        }
        $result.liveChecksBefore = Assert-SwiftUIOverlayProbeLiveProfile -Inputs $Session.inputs -NativeProfile $Session.nativeProfile
        if ($Request.kind -ceq 'frontend-import') {
            $sourcePath = Join-Path $cell 'imports.swift'
            Write-SwiftUIOverlayNewFile -Path $sourcePath -Bytes ([Text.UTF8Encoding]::new($false, $true).GetBytes($Request.source.text))
            $tracePath = Join-Path $work 'loaded-module-trace.json'
            # Preserve the explicitly selected invocation name. A tool symlink
            # can select a multi-call executable entrypoint through argv[0].
            $executable = $Session.nativeProfile.profile.frontend.path
            $arguments = New-SwiftUIOverlayProbeCompilerArguments -SDKPath $Session.nativeProfile.profile.sdkPath `
                -Target $Request.target -CxxMode $Request.cxxMode -CachePath $cache `
                -ModuleName ('SWUIOverlayProbe_' + $Request.requestId) -TracePath $tracePath -SourcePath $sourcePath
        } elseif ($Request.kind -ceq 'supplemental-extractor') {
            $graphs = New-SwiftUIOverlayProbeOwnedDirectory -Root $Session.graphRoot -RelativePath $Request.requestId
            $executable = $Session.nativeProfile.profile.extractor.path
            $arguments = New-SwiftUIOverlayProbeExtractorArguments -OverlayModule $Request.requestedModule `
                -SDKPath $Session.nativeProfile.profile.sdkPath -Target $Request.target -CxxMode $Request.cxxMode `
                -CachePath $cache -OutputDirectory $graphs
        } else { throw 'Unknown native request kind.' }
        $environment = [ordered]@{
            DEVELOPER_DIR = $Session.nativeProfile.profile.developerDirectory
            LANG = 'C'; LC_ALL = 'C'; TMPDIR = $temporary; TEMP = $temporary; TMP = $temporary
        }
        $remainingSeconds = [int][Math]::Floor($policy.maximumBatchSeconds - $Session.state.clock.Elapsed.TotalSeconds)
        if ($remainingSeconds -lt 1) { throw 'Batch elapsed budget was exhausted during prelaunch checks.' }
        $requestSeconds = [int][Math]::Min($policy.perRequestSeconds, $remainingSeconds)
        $receipt = [pscustomobject][ordered]@{
            schemaVersion = 1; evidenceKind = 'swiftui-overlay-native-launch-request-v1'
            batchId = $Session.batchId; request = $Request
            profileSha256 = $Session.nativeProfile.file.sha256; planSha256 = $Session.plan.file.sha256
            sourceArtifacts = $Session.inputs.sourceArtifacts
            executable = $executable; arguments = @($arguments); workingDirectory = $work
            childEnvironmentOverrides = [pscustomobject]$environment; remainingEnvironment = 'inherited; not a process sandbox'
            sourcePath = $sourcePath; tracePath = $tracePath; graphDirectory = $graphs
            timeoutSeconds = $requestSeconds; maximumCombinedOutputBytes = $policy.maximumDiagnosticBytes
            sourceProfile = (Get-SwiftUIOverlayProbeNativePolicy).profile
        }
        $requestFile = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $cell 'request.json') -Value $receipt -MaximumBytes 1MB
        $result.requestFile = Get-SwiftUIBaselineRelativePath -Root $Session.output -Path $requestFile.path
        # Once the invocation is entered, an exception is not proof of nonlaunch.
        $result.nativeInvocationAttempted = $true; $launchState = 'unknown-after-invocation'
        $result.outcome = 'launch-observation-pending'; $result.descendantClosureRequired = $true
        $process = Invoke-SwiftUIStateObjectProcess -FilePath $executable -Arguments $arguments -WorkingDirectory $work `
            -StdoutPath (Join-Path $cell 'stdout.txt') -StderrPath (Join-Path $cell 'stderr.txt') `
            -TimeoutSeconds $requestSeconds `
            -MaxOutputBytes $policy.maximumDiagnosticBytes -Environment $environment
        $result.process = $process; $result.processStarted = $process.processStarted
        # A Start exception cannot independently establish absence of a native
        # child. A true processStarted receipt is positive launch evidence.
        $launchState = if ($process.processStarted) { 'confirmed-started' } else { 'unknown-after-invocation' }
        $outcome = Get-SwiftUIOverlayProbeProcessOutcome -LaunchState $launchState -Process $process
        $result.processOutcome = $outcome; $result.outcome = $outcome.outcome
        $result.stopLaterCommands = $outcome.stopLaterCommands
        $result.descendantClosureRequired = $outcome.descendantClosureRequired
        $result.descendantsClosed = $outcome.descendantsClosed
        $result.descendantClosureStatus = $outcome.descendantClosureStatus
        [void](Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $cell 'process.json') -Value $process -MaximumBytes 1MB)
        if ($outcome.stopLaterCommands) { throw 'The native process did not close with an unambiguous natural result.' }
        $result.liveChecksAfter = Assert-SwiftUIOverlayProbeLiveProfile -Inputs $Session.inputs -NativeProfile $Session.nativeProfile
        if ($Request.kind -ceq 'frontend-import') {
            [void](Get-SwiftUIOverlayProbeBoundedHash -Path $sourcePath -Kind 'fixed-import-source' -ExpectedSha256 $Request.source.sha256 -MaximumBytes 1MB)
            $diagnostics = Read-SwiftUIOverlayProbeDiagnostics -StderrPath (Join-Path $cell 'stderr.txt') `
                -ExpectedSourcePath $sourcePath -SourceRecord $Request.source
            $trace = $null
            if ($process.exitCode -eq 0) {
                [void](Copy-SwiftUIOverlayProbeBoundedFile -Source $tracePath -Destination (Join-Path $cell 'trace.json') -MaximumBytes $policy.maximumTraceBytes)
                $trace = Read-SwiftUIOverlayProbeTrace -Path (Join-Path $cell 'trace.json') -ExpectedModuleName ('SWUIOverlayProbe_' + $Request.requestId) -Target $Request.target
            }
            if ($process.exitCode -ne 0 -or -not $diagnostics.complete -or
                ($null -ne $trace -and -not $trace.complete)) {
                $result.outcome = if ($process.exitCode -eq 1) { 'compiler-rejected' } else { 'evidence-incomplete' }
                $result.stopLaterCommands = $true
                throw 'The fixed native profile rejected the source or produced unsupported diagnostic/trace evidence; no alternate profile is attempted.'
            }
            $result.pathObservations = Get-SwiftUIOverlayProbePathObservations -Session $Session -Request $Request `
                -Diagnostics $diagnostics -CellEvidence $cell -CellCache $cache
            $assessments = [Collections.Generic.List[object]]::new()
            $positives = [Collections.Generic.List[object]]::new()
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($occurrence in $Request.overlayNameOccurrences) {
                if (-not $seen.Add($occurrence.name)) { continue }
                $assessment = Get-SwiftUIOverlayProbeAssessment -RequestId $Request.requestId `
                    -CompilerProfileSha256 $Session.nativeProfile.file.sha256 -DeclaringModule $Request.declaringModule `
                    -BystandingModule $Request.bystanderModule -OverlayModule $occurrence.name -Control $Request.control `
                    -Target $Request.target -CxxMode $Request.cxxMode -CandidateRecordIds $Request.candidateRecordIds `
                    -LaunchState $launchState -Process $process -Diagnostics $diagnostics -Trace $trace -PathObservations $result.pathObservations
                $assessments.Add($assessment)
                if ($assessment.stopLaterCommands) { $result.stopLaterCommands = $true }
                if ($assessment.overlayActivationObserved) {
                    $load = @($diagnostics.loads | Where-Object { $_.module -ceq $occurrence.name })[0]
                    $sourceFile = @($result.pathObservations | Where-Object { $_.path -ceq $load.sourcePath })[0]
                    $loadedFile = @($result.pathObservations | Where-Object { $_.path -ceq $load.loadedPath })[0]
                    $positives.Add([pscustomobject][ordered]@{
                        observationId = Get-SwiftUIOverlayId @('frontend-overlay-observation-v1', $Request.requestId, $occurrence.name)
                        requestId = $Request.requestId; profileSha256 = $Session.nativeProfile.file.sha256
                        module = $occurrence.name; target = $Request.target; cxxMode = $Request.cxxMode; control = $Request.control
                        candidateRecordIds = $Request.candidateRecordIds; sourcePath = $load.sourcePath; loadedPath = $load.loadedPath
                        sourceSha256 = $sourceFile.sha256; loadedSha256 = $loadedFile.sha256
                        activationTuple = [pscustomobject]@{ declaringModule = $Request.declaringModule; bystanderModules = @($Request.bystanderModule); overlayModule = $occurrence.name }
                        traceSha256 = $trace.sha256; diagnosticsSha256 = $diagnostics.sha256; eligible = $true
                    })
                }
            }
            $result.assessments = $assessments.ToArray(); $result.positiveFrontendObservations = $positives.ToArray()
            $result.outcome = if ($result.stopLaterCommands) { 'evidence-incomplete' } else { 'import-controls-recorded' }
        } else {
            if ($process.exitCode -ne 0) {
                $result.outcome = 'extractor-rejected'; $result.stopLaterCommands = $true
                throw 'The fixed extractor returned nonzero; no fallback flags or broader module allowlist are attempted.'
            }
            $result.outcome = 'extractor-completed'
            $result['invocation'] = [pscustomobject][ordered]@{
                invocationId = $Request.requestId; requestId = $Request.frontendRequestId; requestedModule = $Request.requestedModule
                target = $Request.target; cxxMode = $Request.cxxMode; control = 'supplemental-direct-module'
                graphDirectory = $Request.requestId; arguments = @($arguments); exitCode = 0; termination = 'natural'; outputComplete = $true
                candidateRecordIds = $Request.candidateRecordIds; positiveFrontendObservationIds = $Request.positiveFrontendObservationIds
            }
        }
    } catch {
        $result.error = $_.Exception.Message; $result.stopLaterCommands = $true
        if ($result.outcome -ceq 'not-run') { $result.outcome = 'prelaunch-rejected' }
        if ($launchState -ceq 'unknown-after-invocation') {
            $result.outcome = 'launch-uncertain'; $result.processStarted = $null; $result.descendantClosureRequired = $true
        }
        # Every actual process receipt remains in process.json even if later
        # interpretation fails. Normal postprocessing failure does not invent a
        # descendant timeout; the controller nevertheless stops this batch.
    }
    $result.resultFile = Get-SwiftUIBaselineRelativePath -Root $Session.output -Path (Join-Path $cell 'result.json')
    [void](Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $cell 'result.json') -Value ([pscustomobject]$result))
    return [pscustomobject]$result
}

function New-SwiftUIOverlayProbeExtractionSchedule {
    param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ImportResults)
    $groups = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $positive = [Collections.Generic.List[object]]::new()
    foreach ($result in $ImportResults) {
        # A failed cell may retain a locally positive observation alongside a
        # later failed assessment. Keep those raw facts in its result, but do
        # not use them to authorize extraction after an incomplete profile.
        if ($result.outcome -cne 'import-controls-recorded' -or $result.stopLaterCommands) { continue }
        foreach ($observation in $result.positiveFrontendObservations) {
            if ($observation.eligible -isnot [bool] -or -not $observation.eligible -or
                $observation.requestId -cne $result.requestId) {
                throw 'A direct extraction cannot use failed, ineligible or relabeled frontend evidence.'
            }
            if ($observation.control -cnotin @('owner-bystander', 'bystander-owner')) { continue }
            $positive.Add($observation)
            $id = Get-SwiftUIOverlayId @('direct-overlay-extraction-v1', $Plan.file.sha256,
                $observation.module, $observation.target, $observation.cxxMode)
            if (-not $groups.ContainsKey($id)) {
                $groups.Add($id, [pscustomobject][ordered]@{
                    requestId = $id; kind = 'supplemental-extractor'; requestedModule = $observation.module
                    target = $observation.target; cxxMode = $observation.cxxMode
                    control = 'supplemental-direct-module'; frontendRequestId = $observation.requestId
                    candidateRecordIds = $observation.candidateRecordIds
                    positiveFrontendObservationIds = @($observation.observationId)
                    relatedFrontendObservationIds = [Collections.Generic.List[string]]::new()
                    associationMeaning = 'One exact positive request is the extraction basis; related observations retain their own occurrence and import-order identities.'
                })
            }
            $groups[$id].relatedFrontendObservationIds.Add($observation.observationId)
        }
    }
    if ($groups.Count -gt 64) { throw 'Direct overlay extraction exceeds the fixed distinct-module/context budget.' }
    return [pscustomobject]@{ requests = @($groups.Values); positiveFrontendObservations = $positive.ToArray() }
}

function Write-SwiftUIOverlayProbeSupplementalGraphs {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)]$ExtractionSchedule)
    $results = @($Session.state.results | Where-Object { $_.kind -ceq 'supplemental-extractor' })
    if ($results.Count -ne $ExtractionSchedule.requests.Count -or
        @($results | Where-Object { $_.outcome -cne 'extractor-completed' -or $_.stopLaterCommands }).Count -gt 0) {
        throw 'Incomplete native graph production cannot be relabeled as a frozen supplemental inventory.'
    }
    if ($results.Count -eq 0) {
        return [pscustomobject]@{ status = 'not-requested-without-eligible-combined-load-observation'; report = $null }
    }
    $limits = Get-SwiftUIOverlayGraphLimits
    $files = Get-SwiftUIOverlayGraphFileInventory -Root $Session.graphRoot -Limits $limits
    if ($files.Count -gt $limits.graphFiles) { throw 'Completed graph output exceeds the file count budget.' }
    $entries = [Collections.Generic.List[object]]::new(); $totalBytes = [long]0
    $names = [string[]]@($files.Keys); [Array]::Sort($names, [StringComparer]::Ordinal)
    $invocations = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($result in $results) { $invocations.Add($result.invocation.invocationId, $result.invocation) }
    foreach ($name in $names) {
        $file = $files[$name]; $invocationId = $name.Split('/')[0]
        if (-not $invocations.ContainsKey($invocationId) -or
            -not $name.EndsWith('.symbols.json', [StringComparison]::Ordinal)) {
            throw 'Completed extractor output contains an undeclared invocation or non-graph file.'
        }
        $totalBytes += $file.bytes
        if ($file.bytes -gt $limits.graphBytes -or $totalBytes -gt $limits.totalGraphBytes) {
            throw 'Completed graph output exceeds its retention budget; this is not a disk quota.'
        }
        [void](Assert-SwiftUIStateObjectRegularFile $file.path)
        $binding = Get-SwiftUIOverlayProbeBoundedHash -Path $file.path -RelativePath $name -Kind 'supplemental-source-graph' -MaximumBytes $limits.graphBytes -ExpectedBytes $file.bytes
        $entries.Add([pscustomobject][ordered]@{
            relativePath = $name; bytes = $binding.bytes; sha256 = $binding.sha256; invocationId = $invocationId
            role = 'unattributed-emission'; emittingModule = $null; declaringModule = $null; bystanders = $null
            positiveFrontendObservationIds = @()
        })
    }
    $frozen = [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'swiftui-overlay-supplemental-graph-inputs-v1'
        batchId = $Session.batchId; graphRoot = $Session.graphRoot; supplementalGraphInputs = $entries.ToArray()
    }
    $native = [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'swiftui-overlay-graph-native-invocations-v1'; batchId = $Session.batchId
        profileSha256 = $Session.nativeProfile.file.sha256; executionKind = 'native'
        invocations = @($results.invocation); positiveFrontendObservations = $ExtractionSchedule.positiveFrontendObservations
    }
    $frozenFile = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $Session.output 'inputs/frozen-graphs.json') -Value $frozen
    $nativeFile = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $Session.output 'inputs/graph-invocations.json') -Value $native
    $inventory = Write-SwiftUIOverlaySupplementalInventory -FrozenGraphInventoryPath $frozenFile.path `
        -FrozenGraphInventorySha256 $frozenFile.sha256 -NativeInvocationMetadataPath $nativeFile.path `
        -NativeInvocationMetadataSha256 $nativeFile.sha256 -OutputDirectory (Join-Path $Session.output 'supplemental')
    return [pscustomobject]@{ status = 'retained-awaiting-review'; report = $inventory }
}

function Get-SwiftUIOverlayProbePayloadInventory {
    param([Parameter(Mandatory)][string]$Root)
    $policy = Get-SwiftUIOverlayProbeCollectionPolicy
    [void](Assert-SwiftUIOverlayGraphPath -Path $Root -Kind Directory)
    $pending = [Collections.Generic.Stack[object]]::new()
    $pending.Push([pscustomobject]@{ path = $Root; relative = ''; depth = 0 })
    $files = [Collections.Generic.List[object]]::new(); $directories = 1; $totalBytes = [long]0
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        $iterator = [IO.Directory]::EnumerateFileSystemEntries($directory.path).GetEnumerator()
        try {
            while ($iterator.MoveNext()) {
                $path = [string]$iterator.Current; $name = [IO.Path]::GetFileName($path)
                $relative = if ($directory.relative.Length -eq 0) { $name } else { $directory.relative + '/' + $name }
                if ($directory.relative.Length -eq 0 -and $name -cin @('.work', '.in-progress', 'probe-report.json', 'probe-report.sha256')) { continue }
                [void](Resolve-SwiftUIOverlayGraphRelativePath -Root $Root -RelativePath $relative)
                $attributes = [IO.File]::GetAttributes($path)
                if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Retained probe evidence cannot contain filesystem aliases.' }
                if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                    $directories++
                    if ($directories -gt 16384 -or $directory.depth -ge 64) { throw 'Retained probe evidence directory budget exceeded.' }
                    $pending.Push([pscustomobject]@{ path = $path; relative = $relative; depth = $directory.depth + 1 })
                } else {
                    $file = Assert-SwiftUIStateObjectRegularFile $path
                    $totalBytes += $file.Length
                    if ($files.Count -ge $policy.maximumRetainedFiles -or $totalBytes -gt $policy.maximumRetainedBytes) {
                        throw 'Retained probe evidence exceeds its file or aggregate byte budget.'
                    }
                    $files.Add((Get-SwiftUIOverlayProbeBoundedHash -Path $path -RelativePath $relative -Kind 'probe-payload' -MaximumBytes $file.Length -ExpectedBytes $file.Length))
                }
            }
        } finally { $iterator.Dispose() }
    }
    $sorted = $files.ToArray()
    [Array]::Sort($sorted, [Collections.Generic.Comparer[object]]::Create([Comparison[object]]{
        param($left, $right); return [StringComparer]::Ordinal.Compare($left.relativePath, $right.relativePath)
    }))
    # Get-SwiftUIAuditHashedFile records both absolute path and relativePath.
    # Only the portable relative identity is serialized into a relocatable seal.
    return ,@($sorted | ForEach-Object { [pscustomobject][ordered]@{
        path = $_.relativePath; bytes = $_.bytes; sha256 = $_.sha256
    } })
}

function Assert-SwiftUIOverlayProbeEquivalentJson {
    param($Expected, $Actual, [Parameter(Mandatory)][string]$Context)
    # Generated CLR Int32/Int64 and list values must cross the same JSON boundary
    # as recorded files before exact comparison. This never weakens key/type
    # checks on untrusted metadata; only the internally generated value is read.
    $arguments = @{ InputObject = (ConvertTo-Json -InputObject $Expected -Depth 100 -WarningAction Stop); Depth = 100; NoEnumerate = $true }
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $arguments.DateKind = 'String' }
    $normalized = ConvertFrom-Json @arguments
    Assert-SwiftUIAuditJsonEqual -Expected $normalized -Actual $Actual -Context $Context
}

function Get-SwiftUIOverlayProbeReportPlan {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$Report)
    if ($Report.plan.path -cne 'inputs/probe-plan.json' -or $Report.nativeProfile.path -cne 'inputs/native-profile.json') {
        throw 'Probe report inputs must retain their exact reserved names.'
    }
    $plan = (Read-SwiftUIOverlayProbeMetadata -Path (Join-Path $Root $Report.plan.path) -MaximumBytes 1MB).value
    $profile = (Read-SwiftUIOverlayProbeMetadata -Path (Join-Path $Root $Report.nativeProfile.path) -MaximumBytes 1MB).value
    Assert-SwiftUIOverlayProbeFields $plan @{
        schemaVersion='integer'; evidenceKind='string'; sourceArtifacts='object'; nativeProfileSha256='string'
        languageMode='string'; targetContexts='array'; pairs='array'; limits='object'
    } 'retained probe plan'
    if ($plan.schemaVersion -ne 1 -or $plan.evidenceKind -cne 'swiftui-overlay-probe-plan' -or
        $plan.nativeProfileSha256 -cne $Report.nativeProfile.sha256 -or $plan.languageMode -cne '6') {
        throw 'The retained plan does not bind its exact native profile and language mode.'
    }
    $sourceFields = @{}
    foreach ($name in @('captureManifestSha256', 'captureStatusSha256', 'auditManifestSha256', 'baselineManifestSha256',
        'inventorySha256', 'graphSetSha256', 'discoveryManifestSha256', 'rootPlanSha256')) { $sourceFields.Add($name, 'string') }
    Assert-SwiftUIOverlayProbeFields $Report.sourceArtifacts $sourceFields 'probe-report.sources'
    foreach ($name in $sourceFields.Keys) { Assert-SwiftUIAuditSha256 $Report.sourceArtifacts.$name ('probe-report.sources.' + $name) }
    Assert-SwiftUIAuditJsonEqual $Report.sourceArtifacts $plan.sourceArtifacts 'retained-plan.sources'
    Assert-SwiftUIOverlayProbeFields $profile @{
        schemaVersion='integer'; evidenceKind='string'; status='string'; syntheticFixture='boolean'; sourceArtifacts='object'
        nativeEvidenceProfile='string'; publicSwiftSourceCommit='string'; developerDirectory='string'; sdkPath='string'
        toolchainPath='string'; selectedRoots='array'; anchors='array'; frontend='object'; extractor='object'
        observedExtractorIdentityAsRecorded='object'; observations='object'; qualification='object'
    } 'retained native profile'
    if ($profile.schemaVersion -ne 1 -or $profile.evidenceKind -cne 'swiftui-overlay-native-tool-profile' -or
        $profile.status -cne 'metadata-recorded-awaiting-explicit-plan-selection' -or $profile.syntheticFixture -or
        $profile.nativeEvidenceProfile -cne 'public-swift-6.3-overlay-load-v1' -or
        $profile.publicSwiftSourceCommit -cne (Get-SwiftUIOverlayProbeCollectionPolicy).publicSwiftSourceCommit -or
        $profile.sdkPath -cne (Get-SwiftUIOverlayProbeNativePolicy).sdkPath) { throw 'Unsupported or synthetic retained native profile.' }
    Assert-SwiftUIAuditJsonEqual $Report.sourceArtifacts $profile.sourceArtifacts 'retained-profile.sources'
    $pinnedDeveloper = '/Applications/Xcode_26.6.app/Contents/Developer'
    if ($profile.developerDirectory -cne $pinnedDeveloper -or $profile.toolchainPath -cne ($pinnedDeveloper + '/Toolchains/XcodeDefault.xctoolchain') -or
        $profile.frontend.path -cne ($profile.toolchainPath + '/usr/bin/swift-frontend') -or
        $profile.extractor.path -cne ($profile.toolchainPath + '/usr/bin/swift-symbolgraph-extract')) { throw 'Retained logical invocation names differ from the pinned selected installation.' }
    Assert-SwiftUIAuditJsonEqual $Report.qualification $profile.qualification 'retained-profile.qualification'
    Assert-SwiftUIOverlayProbeFields $profile.observations @{
        nativeCommandsExecuted='boolean'; frontendVersionExecuted='boolean'; frontendIdentityMeaning='string'
        nativeProcessSandboxEstablished='boolean'; wholeSDKByteIdentityEstablished='boolean'
    } 'retained-profile.observations'
    if ($profile.observations.nativeCommandsExecuted -or $profile.observations.frontendVersionExecuted -or
        $profile.observations.nativeProcessSandboxEstablished -or $profile.observations.wholeSDKByteIdentityEstablished -or
        $profile.observations.frontendIdentityMeaning -cne 'separately named and hashed file; not inferred from the recorded swift compiler version') {
        throw 'Retained profile promotes an unobserved native identity or sandbox claim.'
    }
    foreach ($file in @($profile.frontend, $profile.extractor)) {
        Assert-SwiftUIOverlayProbeFields $file @{
            path='string'; canonicalPath='string'; bytes='integer'; sha256='string'; allowedPhysicalRoot='string'; observation='string'
        } 'retained native tool'
        Assert-SwiftUIAuditSha256 $file.sha256 'retained tool hash'
        foreach ($path in @($file.path, $file.canonicalPath, $file.allowedPhysicalRoot)) { Assert-SwiftUIOverlayProbeNativePath $path }
        if ($file.bytes -lt 1 -or $file.bytes -gt 1GB -or -not (Test-SwiftUIOverlayInside $file.allowedPhysicalRoot $file.canonicalPath)) {
            throw 'Retained tool identity leaves its recorded physical boundary.'
        }
    }
    Assert-SwiftUIOverlayProbeFields $plan.limits @{ maximumDefinitionPairs='integer'; maximumDistinctOverlayModules='integer' } 'retained-plan.limits'
    if ($plan.limits.maximumDefinitionPairs -lt 1 -or $plan.limits.maximumDefinitionPairs -gt 4 -or
        $plan.pairs.Count -lt 1 -or $plan.pairs.Count -gt $plan.limits.maximumDefinitionPairs -or
        $plan.limits.maximumDistinctOverlayModules -lt 1 -or $plan.limits.maximumDistinctOverlayModules -gt 16) { throw 'Retained plan exceeds its batch limits.' }
    $contexts = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $modes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($context in $plan.targetContexts) {
        Assert-SwiftUIOverlayProbeFields $context @{ target='string'; targetVariant='null'; cxxInteroperabilityMode='string' } 'retained-plan.context'
        Assert-SwiftUIOverlayProbeContext $context.target $context.cxxInteroperabilityMode
        if (-not $contexts.Add($context.target + '/' + $context.cxxInteroperabilityMode)) { throw 'Duplicate retained target context.' }
        [void]$modes.Add($context.cxxInteroperabilityMode)
    }
    if ($modes.Count -eq 0 -or $contexts.Count -ne 2 * $modes.Count) { throw 'Both pinned targets are required for each selected Cxx mode.' }
    Assert-SwiftUIOverlayProbeFields $Report.selection @{
        meaning='string'; candidateDispositions='array'; selectedPairIds='array'; duplicateNameOccurrencesRemainInPlan='boolean'
        definitionOccurrenceTriggered='boolean'
    } 'probe-report.selection'
    if ($Report.selection.meaning -cne 'explicit bounded batch only; unselected candidates remain unresolved' -or
        -not $Report.selection.duplicateNameOccurrencesRemainInPlan -or $Report.selection.definitionOccurrenceTriggered) {
        throw 'Probe selection cannot relabel a bounded plan as a census or definition-trigger proof.'
    }
    $dispositions = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Report.selection.candidateDispositions) {
        Assert-SwiftUIOverlayProbeFields $entry @{
            candidateId='string'; definitionOccurrenceId='string'; pairId='nullable-string'; target='string'; disposition='string'
            expectedOverlayNameCount='integer'; nativeLoadEvidence='string'
        } 'probe-report.candidateDisposition'
        Assert-SwiftUIAuditSha256 $entry.candidateId 'candidate disposition ID'
        Assert-SwiftUIAuditSha256 $entry.definitionOccurrenceId 'candidate definition ID'
        if ($dispositions.ContainsKey($entry.candidateId) -or $entry.disposition -cnotin @('selected', 'unselected') -or
            $entry.nativeLoadEvidence -cne 'not-performed' -or $entry.expectedOverlayNameCount -lt 0 -or
            $entry.target -cnotin (Get-SwiftUIOverlayProbeNativePolicy).targets -or
            ($entry.disposition -ceq 'unselected' -and $null -ne $entry.pairId)) { throw 'Contradictory candidate disposition.' }
        $dispositions.Add($entry.candidateId, $entry)
    }
    $pairs = [Collections.Generic.List[object]]::new(); $pairIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $modules = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal); $selectedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($pair in $plan.pairs) {
        Assert-SwiftUIOverlayProbeFields $pair @{
            pairId='string'; definitionOccurrenceId='string'; rawDefinitionSha256='string'; declaringModule='string'; bystanderModule='string'
            overlayNameOccurrences='array'; sourceCandidateIds='array'
        } 'retained-plan.pair'
        foreach ($name in @('pairId', 'definitionOccurrenceId', 'rawDefinitionSha256')) { Assert-SwiftUIAuditSha256 $pair.$name ('retained pair.' + $name) }
        Assert-SwiftUIOverlayProbeNativeIdentifier $pair.declaringModule
        Assert-SwiftUIOverlayProbeNativeIdentifier $pair.bystanderModule
        if (-not $pairIds.Add($pair.pairId) -or $pair.pairId -cne (Get-SwiftUIOverlayId @('probe-pair', $pair.definitionOccurrenceId)) -or
            $pair.sourceCandidateIds.Count -ne 2) { throw 'Retained pair identity or candidate set is invalid.' }
        [void](Get-SwiftUIOverlayProbeNameSeal -Occurrences $pair.overlayNameOccurrences)
        foreach ($name in $pair.overlayNameOccurrences) { Assert-SwiftUIOverlayProbeNativeIdentifier $name.name; [void]$modules.Add($name.name) }
        $candidates = [Collections.Generic.List[object]]::new(); $targets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($id in $pair.sourceCandidateIds) {
            if ($id -isnot [string] -or -not $dispositions.ContainsKey($id) -or -not $selectedIds.Add($id)) { throw 'Selected candidate is missing or duplicated.' }
            $candidate = $dispositions[$id]
            if ($candidate.disposition -cne 'selected' -or $candidate.definitionOccurrenceId -cne $pair.definitionOccurrenceId -or
                $candidate.pairId -cne $pair.pairId -or $candidate.expectedOverlayNameCount -ne $pair.overlayNameOccurrences.Count -or
                -not $targets.Add($candidate.target)) { throw 'Selected candidate disposition disagrees with its saved pair.' }
            $candidates.Add([pscustomobject]@{ recordId = $id; target = $candidate.target })
        }
        $copy = [pscustomobject]@{
            pairId=$pair.pairId; definitionOccurrenceId=$pair.definitionOccurrenceId; rawDefinitionSha256=$pair.rawDefinitionSha256
            declaringModule=$pair.declaringModule; bystanderModule=$pair.bystanderModule
            overlayNameOccurrences=$pair.overlayNameOccurrences; sourceCandidates=$candidates.ToArray()
        }
        $pairs.Add($copy)
    }
    if ($modules.Count -gt $plan.limits.maximumDistinctOverlayModules -or
        @($dispositions.Values | Where-Object { $_.disposition -ceq 'selected' }).Count -ne $selectedIds.Count) { throw 'Selected disposition or module counts are inconsistent.' }
    Assert-SwiftUIOverlayProbeEquivalentJson -Expected @($plan.pairs.pairId) -Actual $Report.selection.selectedPairIds -Context 'retained selected pairs'
    if ($Report.batchId -cne (Get-SwiftUIOverlayId @('overlay-probe-batch-v1', $Report.plan.sha256, $Report.nativeProfile.sha256))) { throw 'Probe batch ID does not bind its exact plan/profile.' }
    return [pscustomobject]@{
        file = [pscustomobject]@{ sha256 = $Report.plan.sha256 }; pairs = $pairs.ToArray()
        targetContexts = $plan.targetContexts; profile = $profile
    }
}

function Assert-SwiftUIOverlayProbeRecordedRequest {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)]$Row, [Parameter(Mandatory)]$Expected, [Parameter(Mandatory)]$Profile)
    if ($Row.requestId -cne $Expected.requestId -or $Row.kind -cne $Expected.kind) { throw 'Recorded request differs from the exact selected schedule.' }
    $allowed = @('not-run', 'execution-adapter-failed', 'prelaunch-rejected', 'launch-observation-pending',
        'launch-uncertain', 'timeout', 'output-limit', 'process-uncertain', 'compiler-succeeded', 'compiler-exited-one')
    if ($Row.kind -ceq 'frontend-import') { $allowed += @('compiler-rejected', 'evidence-incomplete', 'import-controls-recorded') }
    elseif ($Row.kind -ceq 'supplemental-extractor') { $allowed += @('extractor-rejected', 'extractor-completed') }
    else { throw 'Unknown recorded request kind.' }
    if ($Row.outcome -cnotin $allowed) { throw 'Recorded outcome does not belong to this exact native request kind.' }
    if ($null -eq $Row.resultFile) {
        if ($Row.outcome -cnotin @('not-run', 'execution-adapter-failed') -or
            -not $Row.stopLaterCommands -or
            ($Row.outcome -ceq 'not-run' -and ($Row.nativeInvocationAttempted -ne $false -or $Row.processStarted -ne $false)) -or
            ($Row.outcome -ceq 'execution-adapter-failed' -and ($null -ne $Row.nativeInvocationAttempted -or
                $null -ne $Row.processStarted -or -not $Row.descendantClosureRequired))) {
            throw 'A missing result receipt cannot claim a recorded native outcome.'
        }
        return [pscustomobject]@{ requestId=$Row.requestId; kind=$Row.kind; outcome=$Row.outcome; stopLaterCommands=$true; positiveFrontendObservations=@() }
    }
    $prefix = 'evidence/' + $Row.requestId + '/'
    if ($Row.resultFile -cne ($prefix + 'result.json')) { throw 'Result receipt must retain its exact request-relative name.' }
    $result = (Read-SwiftUIOverlayProbeMetadata -Path (Join-Path $Root $Row.resultFile) -MaximumBytes 16MB).value
    $resultFields = @('requestId', 'kind', 'outcome', 'nativeInvocationAttempted', 'processStarted', 'stopLaterCommands',
        'descendantClosureRequired', 'descendantsClosed', 'descendantClosureStatus', 'error', 'process', 'processOutcome',
        'pathObservations', 'assessments', 'positiveFrontendObservations', 'requestFile', 'resultFile', 'liveChecksBefore', 'liveChecksAfter')
    if ($Row.kind -ceq 'supplemental-extractor' -and $Row.outcome -ceq 'extractor-completed') { $resultFields += 'invocation' }
    Assert-SwiftUIOverlayProbeExactFields $result $resultFields 'recorded request result'
    foreach ($field in @('pathObservations', 'assessments', 'positiveFrontendObservations', 'liveChecksBefore', 'liveChecksAfter')) {
        if ($result.$field -isnot [array]) { throw 'Recorded evidence collections must preserve their array shape.' }
    }
    if ($null -ne $result.descendantsClosed -or ($null -ne $result.error -and $result.error -isnot [string]) -or
        $result.descendantClosureStatus -isnot [string]) { throw 'Recorded request cannot invent descendant closure or malformed errors.' }
    foreach ($name in @('requestId', 'kind', 'outcome', 'nativeInvocationAttempted', 'processStarted', 'stopLaterCommands', 'descendantClosureRequired', 'resultFile')) {
        Assert-SwiftUIAuditJsonEqual -Expected $Row.$name -Actual $result.$name -Context ('request result.' + $name)
    }
    if ($null -eq $result.requestFile) {
        if ($result.nativeInvocationAttempted -ne $false -or $null -ne $result.process -or $Row.outcome -cne 'prelaunch-rejected') { throw 'Missing launch receipt contradicts a native attempt.' }
        return $result
    }
    if ($result.requestFile -cne ($prefix + 'request.json')) { throw 'Launch receipt must retain its exact request-relative name.' }
    $receipt = (Read-SwiftUIOverlayProbeMetadata -Path (Join-Path $Root $result.requestFile) -MaximumBytes 1MB).value
    Assert-SwiftUIOverlayProbeFields $receipt @{
        schemaVersion='integer'; evidenceKind='string'; batchId='string'; request='object'; profileSha256='string'; planSha256='string'
        sourceArtifacts='object'; executable='string'; arguments='array'; workingDirectory='string'; childEnvironmentOverrides='object'
        remainingEnvironment='string'; sourcePath='nullable-string'; tracePath='nullable-string'; graphDirectory='nullable-string'
        timeoutSeconds='integer'; maximumCombinedOutputBytes='integer'; sourceProfile='string'
    } 'recorded launch receipt'
    if ($receipt.schemaVersion -ne 1 -or $receipt.evidenceKind -cne 'swiftui-overlay-native-launch-request-v1' -or
        $receipt.batchId -cne $Report.batchId -or $receipt.profileSha256 -cne $Report.nativeProfile.sha256 -or
        $receipt.planSha256 -cne $Report.plan.sha256 -or $receipt.sourceProfile -cne (Get-SwiftUIOverlayProbeNativePolicy).profile -or
        $receipt.remainingEnvironment -cne 'inherited; not a process sandbox' -or $receipt.timeoutSeconds -lt 1 -or
        $receipt.timeoutSeconds -gt 120 -or $receipt.maximumCombinedOutputBytes -ne 8MB) { throw 'Launch receipt changes the fixed native profile or source bindings.' }
    Assert-SwiftUIAuditJsonEqual $Report.sourceArtifacts $receipt.sourceArtifacts 'request source artifacts'
    Assert-SwiftUIOverlayProbeEquivalentJson -Expected $Expected -Actual $receipt.request -Context 'exact selected request'
    Assert-SwiftUIOverlayProbeNativePath $receipt.workingDirectory
    $suffix = '/.work/requests/' + $Row.requestId
    if (-not $receipt.workingDirectory.EndsWith($suffix, [StringComparison]::Ordinal)) { throw 'Native work directory does not bind the request ID.' }
    $originalRoot = $receipt.workingDirectory.Substring(0, $receipt.workingDirectory.Length - $suffix.Length)
    $cache = $receipt.workingDirectory + '/module-cache'; $temporary = $receipt.workingDirectory + '/tmp'
    Assert-SwiftUIOverlayProbeEquivalentJson -Expected ([pscustomobject][ordered]@{
        DEVELOPER_DIR=$Profile.developerDirectory; LANG='C'; LC_ALL='C'; TMPDIR=$temporary; TEMP=$temporary; TMP=$temporary
    }) -Actual $receipt.childEnvironmentOverrides -Context 'recorded child environment overrides'
    if ($Row.kind -ceq 'frontend-import') {
        if ($receipt.executable -cne $Profile.frontend.path -or $receipt.sourcePath -cne ($originalRoot + '/' + $prefix + 'imports.swift') -or
            $receipt.tracePath -cne ($receipt.workingDirectory + '/loaded-module-trace.json') -or $null -ne $receipt.graphDirectory) { throw 'Frontend source/path/executable binding differs from the fixed request.' }
        $arguments = New-SwiftUIOverlayProbeCompilerArguments -SDKPath $Profile.sdkPath -Target $Expected.target -CxxMode $Expected.cxxMode `
            -CachePath $cache -ModuleName ('SWUIOverlayProbe_' + $Row.requestId) -TracePath $receipt.tracePath -SourcePath $receipt.sourcePath
        [void](Get-SwiftUIOverlayProbeBoundedHash -Path (Join-Path $Root ($prefix + 'imports.swift')) -MaximumBytes 1MB -ExpectedSha256 $Expected.source.sha256 -ExpectedBytes $Expected.source.bytes)
    } else {
        if ($receipt.executable -cne $Profile.extractor.path -or $null -ne $receipt.sourcePath -or $null -ne $receipt.tracePath -or
            $receipt.graphDirectory -cne ($originalRoot + '/.work/graphs/' + $Row.requestId)) { throw 'Extractor executable or graph directory differs from the request.' }
        $arguments = New-SwiftUIOverlayProbeExtractorArguments -OverlayModule $Expected.requestedModule -SDKPath $Profile.sdkPath `
            -Target $Expected.target -CxxMode $Expected.cxxMode -CachePath $cache -OutputDirectory $receipt.graphDirectory
    }
    Assert-SwiftUIOverlayProbeEquivalentJson -Expected $arguments -Actual $receipt.arguments -Context 'recorded literal argv'
    $expectedLiveFiles = @($Profile.anchors.file) + @($Profile.frontend)
    if ($Row.nativeInvocationAttempted -eq $true) {
        Assert-SwiftUIOverlayProbeEquivalentJson -Expected $expectedLiveFiles -Actual $result.liveChecksBefore -Context 'before-launch native profile observations'
    }
    if ($Row.outcome -cin @('import-controls-recorded', 'extractor-completed')) {
        Assert-SwiftUIOverlayProbeEquivalentJson -Expected $expectedLiveFiles -Actual $result.liveChecksAfter -Context 'after-launch native profile observations'
    }
    if ($null -ne $result.process) {
        if ($Row.nativeInvocationAttempted -ne $true -or
            ($result.process.processStarted -eq $true -and $Row.processStarted -ne $true) -or
            ($result.process.processStarted -eq $false -and $null -ne $Row.processStarted)) {
            throw 'Outer attempt/start counters disagree with the owned process observation.'
        }
        $launch = if ($result.process.processStarted) { 'confirmed-started' } else { 'unknown-after-invocation' }
        $outcome = Get-SwiftUIOverlayProbeProcessOutcome -LaunchState $launch -Process $result.process
        if ($null -ne $result.processOutcome) {
            Assert-SwiftUIOverlayProbeEquivalentJson -Expected $outcome -Actual $result.processOutcome -Context 'derived process outcome'
        } elseif ($Row.outcome -cin @('import-controls-recorded', 'extractor-completed')) { throw 'Successful native request lacks a validated process outcome.' }
        if ($outcome.descendantClosureRequired -and (-not $Row.descendantClosureRequired -or -not $Row.stopLaterCommands)) { throw 'Recorded uncertainty cannot lose its descendant-closure barrier.' }
        $processPath = Join-Path $Root ($prefix + 'process.json')
        if (Test-Path -LiteralPath $processPath) {
            $savedProcess = (Read-SwiftUIOverlayProbeMetadata -Path $processPath -MaximumBytes 1MB).value
            Assert-SwiftUIAuditJsonEqual $result.process $savedProcess 'retained process receipt'
        } elseif ($Row.outcome -cin @('import-controls-recorded', 'extractor-completed')) { throw 'Successful request lacks its process receipt.' }
        if (-not $outcome.stopLaterCommands) {
            foreach ($channel in @('stdout', 'stderr')) {
                [void](Get-SwiftUIOverlayProbeBoundedHash -Path (Join-Path $Root ($prefix + $channel + '.txt')) -MaximumBytes 8MB `
                    -ExpectedSha256 $result.process.($channel + 'Sha256') -ExpectedBytes $result.process.($channel + 'Bytes'))
            }
        }
        if ($Row.outcome -cin @('import-controls-recorded', 'extractor-completed')) {
            if ($outcome.outcome -cne 'compiler-succeeded' -or $Row.stopLaterCommands -or $Row.descendantClosureRequired) { throw 'A successful native outcome requires a clean natural zero exit.' }
        }
    } elseif ($Row.nativeInvocationAttempted -eq $true) {
        if ($Row.outcome -cne 'launch-uncertain' -or $null -ne $Row.processStarted -or
            -not $Row.stopLaterCommands -or -not $Row.descendantClosureRequired) {
            throw 'An invocation without a process receipt must retain its exact unknown-launch barrier.'
        }
    } elseif ($Row.nativeInvocationAttempted -ne $false -or $Row.processStarted -ne $false -or $Row.outcome -cne 'prelaunch-rejected') {
        throw 'A missing process observation cannot claim another recorded native outcome.'
    }
    if ($Row.outcome -ceq 'extractor-completed') {
        $invocation = [pscustomobject][ordered]@{
            invocationId=$Expected.requestId; requestId=$Expected.frontendRequestId; requestedModule=$Expected.requestedModule
            target=$Expected.target; cxxMode=$Expected.cxxMode; control='supplemental-direct-module'
            graphDirectory=$Expected.requestId; arguments=$arguments; exitCode=0; termination='natural'; outputComplete=$true
            candidateRecordIds=$Expected.candidateRecordIds; positiveFrontendObservationIds=$Expected.positiveFrontendObservationIds
        }
        Assert-SwiftUIOverlayProbeEquivalentJson -Expected $invocation -Actual $result.invocation -Context 'recorded exact extractor invocation'
    }
    if ($Row.outcome -ceq 'import-controls-recorded') {
        $diagnostics = Read-SwiftUIOverlayProbeDiagnostics -StderrPath (Join-Path $Root ($prefix + 'stderr.txt')) -ExpectedSourcePath $receipt.sourcePath -SourceRecord $Expected.source
        $trace = Read-SwiftUIOverlayProbeTrace -Path (Join-Path $Root ($prefix + 'trace.json')) -ExpectedModuleName ('SWUIOverlayProbe_' + $Row.requestId) -Target $Expected.target
        foreach ($path in $result.pathObservations) {
            if ($path.status -ceq 'recorded') {
                $expectedCopy = $prefix + 'modules/' + (Get-SwiftUIOverlayId @('loaded-path-v1', $path.path)) + '.bytes'
                if ($path.retainedFile -isnot [string] -or $path.retainedFile -cne $expectedCopy) { throw 'A module identity lacks its exact request-owned byte copy.' }
                $inside = Test-SwiftUIOverlayInside -Root $cache -Path $path.canonicalPath
                foreach ($selectedRoot in $Profile.selectedRoots) {
                    if ($selectedRoot.state -ceq 'readable-complete' -and (Test-SwiftUIOverlayInside -Root $selectedRoot.physicalPath -Path $path.canonicalPath)) { $inside = $true }
                }
                if (-not $inside) { throw 'A retained module identity leaves the selected physical SDK/resource/cache roots.' }
                $retained = Resolve-SwiftUIOverlayGraphRelativePath -Root $Root -RelativePath $path.retainedFile
                [void](Get-SwiftUIOverlayProbeBoundedHash -Path $retained -MaximumBytes 1GB -ExpectedSha256 $path.sha256 -ExpectedBytes $path.bytes)
            }
        }
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $positives = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach ($name in $Expected.overlayNameOccurrences) {
            if (-not $names.Add($name.name)) { continue }
            $saved = @($result.assessments | Where-Object { $_.overlayModule -ceq $name.name })
            if ($saved.Count -ne 1) { throw 'A requested overlay has no unique recorded assessment.' }
            $replay = Get-SwiftUIOverlayProbeAssessment -RequestId $Expected.requestId -CompilerProfileSha256 $Report.nativeProfile.sha256 `
                -DeclaringModule $Expected.declaringModule -BystandingModule $Expected.bystanderModule -OverlayModule $name.name `
                -Control $Expected.control -Target $Expected.target -CxxMode $Expected.cxxMode -CandidateRecordIds $Expected.candidateRecordIds `
                -LaunchState 'confirmed-started' -Process $result.process -Diagnostics $diagnostics -Trace $trace -PathObservations $result.pathObservations
            Assert-SwiftUIOverlayProbeEquivalentJson -Expected $replay -Actual $saved[0] -Context 'raw native assessment replay'
            if ($Report.successful -and $Expected.control -cin @('owner-bystander', 'bystander-owner') -and -not $replay.overlayActivationObserved) {
                throw 'Operational success requires each requested combined import to retain an eligible overlay-load observation.'
            }
            if ($replay.overlayActivationObserved) {
                $load = @($diagnostics.loads | Where-Object { $_.module -ceq $name.name })[0]
                $sourceFile = @($result.pathObservations | Where-Object { $_.path -ceq $load.sourcePath })[0]
                $loadedFile = @($result.pathObservations | Where-Object { $_.path -ceq $load.loadedPath })[0]
                $id = Get-SwiftUIOverlayId @('frontend-overlay-observation-v1', $Expected.requestId, $name.name)
                $positives.Add($id, [pscustomobject][ordered]@{
                    observationId=$id; requestId=$Expected.requestId; profileSha256=$Report.nativeProfile.sha256
                    module=$name.name; target=$Expected.target; cxxMode=$Expected.cxxMode; control=$Expected.control
                    candidateRecordIds=$Expected.candidateRecordIds; sourcePath=$load.sourcePath; loadedPath=$load.loadedPath
                    sourceSha256=$sourceFile.sha256; loadedSha256=$loadedFile.sha256
                    activationTuple=[pscustomobject]@{ declaringModule=$Expected.declaringModule; bystanderModules=@($Expected.bystanderModule); overlayModule=$name.name }
                    traceSha256=$trace.sha256; diagnosticsSha256=$diagnostics.sha256; eligible=$true
                })
            }
        }
        if ($result.assessments.Count -ne $names.Count -or $result.positiveFrontendObservations.Count -ne $positives.Count) { throw 'Assessment or positive observation count differs from raw replay.' }
        $seenPositives = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($observation in $result.positiveFrontendObservations) {
            if (-not $positives.ContainsKey($observation.observationId) -or -not $seenPositives.Add($observation.observationId)) { throw 'Positive observation is missing, duplicated or not supported by raw replay.' }
            Assert-SwiftUIOverlayProbeEquivalentJson -Expected $positives[$observation.observationId] -Actual $observation -Context 'positive frontend observation replay'
        }
    }
    return $result
}

function Assert-SwiftUIOverlayProbeReportSemantics {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$Report)
    Assert-SwiftUIOverlayProbeFields $Report.processBoundary @{
        nativeSandboxEstablished='boolean'; inheritedEnvironmentIsNotSealed='boolean'; wholeSDKByteIdentityEstablished='boolean'
        atomicLoadedImageAttestation='boolean'; descendantsClosed='null'; descendantClosureRequired='boolean'
        followup='string'; unsealedDisposableNamespace='string'; unsealedMeaning='string'
    } 'probe-report.processBoundary'
    $boundary = $Report.processBoundary
    if ($boundary.nativeSandboxEstablished -or -not $boundary.inheritedEnvironmentIsNotSealed -or $boundary.wholeSDKByteIdentityEstablished -or
        $boundary.atomicLoadedImageAttestation -or $boundary.unsealedDisposableNamespace -cne '.work' -or
        $boundary.followup -cne 'No resume in this profile. After termination uncertainty, an operator must establish descendant closure before authorizing another native command.' -or
        $boundary.unsealedMeaning -cne 'compiler caches, original traces and original graph outputs; no disk quota or immutable evidence claim') {
        throw 'Probe report promotes unsupported process or filesystem guarantees.'
    }
    $plan = Get-SwiftUIOverlayProbeReportPlan -Root $Root -Report $Report
    $expectedImports = New-SwiftUIOverlayProbeRequestSchedule -Plan $plan
    $rows = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $attempts = 0; $starts = 0; $closure = $false; $stopped = $false
    foreach ($row in $Report.requests) {
        Assert-SwiftUIOverlayProbeExactFields $row @('requestId', 'kind', 'outcome', 'nativeInvocationAttempted', 'processStarted', 'stopLaterCommands', 'descendantClosureRequired', 'resultFile') 'probe-report.request'
        Assert-SwiftUIAuditSha256 $row.requestId 'probe request ID'
        foreach ($name in @('kind', 'outcome')) { if ($row.$name -isnot [string]) { throw 'Request labels must be exact strings.' } }
        foreach ($name in @('nativeInvocationAttempted', 'processStarted')) {
            if ($null -ne $row.$name -and $row.$name -isnot [bool]) { throw 'Request observations must be booleans or explicit unknown.' }
        }
        foreach ($name in @('stopLaterCommands', 'descendantClosureRequired')) { if ($row.$name -isnot [bool]) { throw 'Request stop/closure fields must be booleans.' } }
        if ($row.kind -cnotin @('frontend-import', 'supplemental-extractor') -or $rows.ContainsKey($row.requestId) -or
            ($null -ne $row.resultFile -and $row.resultFile -isnot [string]) -or
            ($row.descendantClosureRequired -and -not $row.stopLaterCommands) -or
            ($stopped -and $row.outcome -cne 'not-run')) { throw 'Request list contradicts its stop barrier, type or identity.' }
        if ($row.nativeInvocationAttempted -eq $true) { $attempts++ }
        if ($row.processStarted -eq $true) { $starts++ }
        if ($row.descendantClosureRequired) { $closure = $true }
        if ($row.stopLaterCommands) { $stopped = $true }
        $rows.Add($row.requestId, $row)
    }
    if ($Report.nativeInvocationsAttempted -ne $attempts -or $Report.confirmedProcessesStarted -ne $starts -or
        $Report.requests.Count -gt 128 -or $boundary.descendantClosureRequired -ne $closure) { throw 'Probe counters or aggregate closure barrier disagree with exact requests.' }
    $details = [Collections.Generic.List[object]]::new(); $expectedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $position = 0
    foreach ($expected in $expectedImports) {
        if (-not $rows.ContainsKey($expected.requestId) -or $Report.requests[$position].requestId -cne $expected.requestId) { throw 'Probe report omitted or reordered an exact planned import request.' }
        $position++
        [void]$expectedIds.Add($expected.requestId)
        $details.Add((Assert-SwiftUIOverlayProbeRecordedRequest -Root $Root -Report $Report -Row $rows[$expected.requestId] -Expected $expected -Profile $plan.profile))
    }
    $extractions = New-SwiftUIOverlayProbeExtractionSchedule -Plan $plan -ImportResults $details.ToArray()
    $extractionDetails = [Collections.Generic.List[object]]::new()
    foreach ($expected in $extractions.requests) {
        if (-not $rows.ContainsKey($expected.requestId) -or $Report.requests[$position].requestId -cne $expected.requestId) { throw 'Probe report omitted or reordered a derived direct extraction request.' }
        $position++
        [void]$expectedIds.Add($expected.requestId)
        $extractionDetails.Add((Assert-SwiftUIOverlayProbeRecordedRequest -Root $Root -Report $Report -Row $rows[$expected.requestId] -Expected $expected -Profile $plan.profile))
    }
    if ($rows.Count -ne $expectedIds.Count) { throw 'Probe report contains undeclared native requests.' }
    $toolNames = Get-SwiftUIOverlayProbeToolingNames
    if ($Report.tooling.Count -ne $toolNames.Count) { throw 'Collector source snapshot roster is incomplete.' }
    $seenTools = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($tool in $Report.tooling) {
        Assert-SwiftUIOverlayProbeFields $tool @{ path='string'; bytes='integer'; sha256='string'; interpretation='string' } 'collector tooling source'
        $name = $tool.path.Substring('inputs/tooling/'.Length)
        if (-not $tool.path.StartsWith('inputs/tooling/', [StringComparison]::Ordinal) -or $name -cnotin $toolNames -or
            -not $seenTools.Add($name) -or $tool.interpretation -cne 'source file observed before launch; not an independent attestation of in-memory execution') { throw 'Unknown or misleading collector source snapshot.' }
        $file = @($Report.files | Where-Object { $_.path -ceq $tool.path })
        if ($file.Count -ne 1 -or $file[0].sha256 -cne $tool.sha256 -or $file[0].bytes -ne $tool.bytes) { throw 'Collector source snapshot does not match its retained bytes.' }
    }
    Assert-SwiftUIOverlayProbeFields $Report.supplemental @{ status='string'; report=$(if ($null -eq $Report.supplemental.report) { 'null' } else { 'object' }) } 'supplemental status'
    if ($Report.supplemental.status -ceq 'retained-awaiting-review') {
        $saved = $Report.supplemental.report
        $live = Read-SwiftUIOverlaySupplementalInventory -OutputDirectory (Join-Path $Root 'supplemental') -ExpectedReportSha256 $saved.report.sha256
        foreach ($field in @('evidenceKind', 'batchId', 'supplementalInventoryId', 'executionKind', 'inventory', 'counts', 'status', 'attributionCompleteness', 'behaviorConformance', 'inputBindings', 'files')) {
            Assert-SwiftUIAuditJsonEqual -Expected $live.$field -Actual $saved.$field -Context ('supplemental report.' + $field)
        }
        if ($live.batchId -cne $Report.batchId -or $live.executionKind -cne 'native' -or $extractions.requests.Count -eq 0) { throw 'Supplemental report is not this batch of native extraction requests.' }
        if (@($extractionDetails | Where-Object { $_.outcome -cne 'extractor-completed' }).Count -gt 0) { throw 'A supplemental inventory cannot claim unfinished native producers.' }
        $expectedNative = [pscustomobject][ordered]@{
            schemaVersion=1; evidenceKind='swiftui-overlay-graph-native-invocations-v1'; batchId=$Report.batchId
            profileSha256=$Report.nativeProfile.sha256; executionKind='native'
            invocations=@($extractionDetails.invocation); positiveFrontendObservations=$extractions.positiveFrontendObservations
        }
        foreach ($relative in @('inputs/graph-invocations.json', 'supplemental/inputs/native-invocations.json')) {
            $native = (Read-SwiftUIOverlayProbeMetadata -Path (Join-Path $Root $relative) -MaximumBytes 16MB).value
            Assert-SwiftUIOverlayProbeEquivalentJson -Expected $expectedNative -Actual $native -Context 'exact supplemental native producer bindings'
        }
    } elseif ($Report.supplemental.status -cnotin @('not-attempted', 'not-requested-without-eligible-combined-load-observation') -or
        $null -ne $Report.supplemental.report -or ($Report.successful -and $extractions.requests.Count -gt 0)) { throw 'Supplemental status contradicts required direct extractions.' }
}

function Read-SwiftUIOverlayProbeReport {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$ExpectedSha256)
    Assert-SwiftUIAuditSha256 $ExpectedSha256 'probe-report.expectedSha256'
    $Root = Assert-SwiftUIOverlayGraphPath -Path $Root -Kind Directory
    if (Test-Path -LiteralPath (Join-Path $Root '.in-progress')) { throw 'Probe collection did not close its evidence publication.' }
    $path = Join-Path $Root 'probe-report.json'
    [void](Assert-SwiftUIStateObjectRegularFile $path)
    $file = Read-SwiftUIOverlayProbeMetadata -Path $path -MaximumBytes (Get-SwiftUIOverlayProbeCollectionPolicy).maximumReportBytes
    if ($file.sha256 -cne $ExpectedSha256) { throw 'Probe report differs from its expected external seal.' }
    $sealPath = Join-Path $Root 'probe-report.sha256'
    [void](Assert-SwiftUIStateObjectRegularFile $sealPath)
    $seal = Read-SwiftUIStateObjectBoundedBytes -Path $sealPath -MaxBytes 128
    $expectedSeal = $ExpectedSha256 + '  probe-report.json' + [char]10
    if ([Text.UTF8Encoding]::new($false, $true).GetString($seal.rawBytes) -cne $expectedSeal) { throw 'Probe report seal sidecar is malformed.' }
    $report = $file.value
    Assert-SwiftUIOverlayProbeFields $report @{
        schemaVersion='integer'; evidenceKind='string'; batchId='string'; executionKind='string'; successful='boolean'
        status='string'; sourceArtifacts='object'; plan='object'; nativeProfile='object'; selection='object'
        policy='object'; processBoundary='object'; requests='array'; supplemental='object'; errors='array'; tooling='array'
        nativeInvocationsAttempted='integer'; confirmedProcessesStarted='integer'; sourceSealsRechecked='boolean'
        qualification='object'; files='array'
    } 'probe report'
    if ($report.schemaVersion -ne 1 -or $report.evidenceKind -cne 'swiftui-overlay-probe-report-v1' -or
        $report.executionKind -cne 'native' -or $report.status -cnotin @('recorded-awaiting-review', 'incomplete-or-failed')) {
        throw 'Unsupported or synthetic native probe report.'
    }
    Assert-SwiftUIAuditSha256 $report.batchId 'probe-report.batchId'
    Assert-SwiftUIOverlayProbeFields $report.qualification @{
        reviewedIdentity='boolean'; declarationCompleteness='boolean'; overlayCompleteness='boolean'; behaviorConformance='boolean'
    } 'probe-report.qualification'
    foreach ($name in @($report.qualification.PSObject.Properties.Name)) {
        if ($report.qualification.$name) { throw 'Unreviewed native probe reports cannot promote any original completion gate.' }
    }
    Assert-SwiftUIAuditJsonEqual -Expected (Get-SwiftUIOverlayProbeCollectionPolicy) -Actual $report.policy -Context 'probe-report.policy'
    $actual = Get-SwiftUIOverlayProbePayloadInventory -Root $Root
    Assert-SwiftUIAuditJsonEqual -Expected $report.files -Actual $actual -Context 'probe-report.exactPayloadMembership'
    foreach ($binding in @($report.plan, $report.nativeProfile)) {
        Assert-SwiftUIOverlayProbeFields $binding @{ path='string'; bytes='integer'; sha256='string' } 'probe-report.inputBinding'
        Assert-SwiftUIAuditSha256 $binding.sha256 'probe-report.inputBinding.sha256'
        $retained = @($actual | Where-Object { $_.path -ceq $binding.path })
        if ($retained.Count -ne 1 -or $retained[0].sha256 -cne $binding.sha256 -or $retained[0].bytes -ne $binding.bytes) {
            throw 'A probe report input binding is not present in the exact retained payload.'
        }
    }
    Assert-SwiftUIOverlayProbeReportSemantics -Root $Root -Report $report
    if ($report.successful -and (-not $report.sourceSealsRechecked -or $report.errors.Count -gt 0 -or
        $report.status -cne 'recorded-awaiting-review' -or
        @($report.requests | Where-Object { $_.outcome -cnotin @('import-controls-recorded', 'extractor-completed') }).Count -gt 0)) {
        throw 'A successful probe report contradicts its recorded request or input status.'
    }
    return [pscustomobject]@{
        reportPath = $path; sha256 = $file.sha256; successful = $report.successful; status = $report.status
        qualification = $report.qualification; report = $report
        verification = 'strict metadata and exact retained file seals; not an independent native execution attestation'
    }
}

function Get-SwiftUIOverlayProbeToolingNames {
    return ,@('capture-swiftui-overlay-probes.ps1', 'swiftui-overlay-probe-collector.ps1',
        'swiftui-overlay-probe-intake.ps1', 'swiftui-overlay-probe-native.ps1', 'swiftui-overlay-probe-graphs.ps1',
        'swiftui-overlay-discovery-common.ps1', 'swiftui-stateobject-process-common.ps1',
        'swiftui-stateobject-isolation-common.ps1', 'swiftui-api-review-common.ps1',
        'swiftui-api-audit-common.ps1', 'swiftui-baseline-common.ps1', 'swiftui-baseline-streaming.ps1')
}

function Write-SwiftUIOverlayProbeToolingSnapshot {
    param([Parameter(Mandatory)][string]$OutputDirectory)
    $root = New-SwiftUIOverlayProbeOwnedDirectory -Root $OutputDirectory -RelativePath 'inputs/tooling'
    $names = Get-SwiftUIOverlayProbeToolingNames
    $seals = [Collections.Generic.List[object]]::new()
    foreach ($name in $names) {
        $source = Join-Path $PSScriptRoot $name
        [void](Assert-SwiftUIStateObjectRegularFile $source)
        $hash = Get-SwiftUIOverlayProbeBoundedHash -Path $source -RelativePath $name -Kind 'observed-collector-source' -MaximumBytes 2MB
        [void](Copy-SwiftUIOverlayProbeBoundedFile -Source $source -Destination (Join-Path $root $name) -MaximumBytes 2MB -ExpectedSha256 $hash.sha256)
        $seals.Add($hash)
    }
    return ,$seals.ToArray()
}

function Invoke-SwiftUIOverlayProbeCollection {
    param([Parameter(Mandatory)]$Inputs, [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$NativeProfile, [Parameter(Mandatory)][string]$OutputDirectory)
    if (-not $IsMacOS -or $Inputs.syntheticFixture -or $Plan.syntheticFixture) {
        throw 'Live collection requires real native inputs on macOS; synthetic seams cannot dispatch native work.'
    }
    # Public CLI intake returns a rederived immutable source context with the
    # reviewed plan. Do not execute caller-mutated convenience arrays.
    $canonicalPlan = Read-SwiftUIOverlayProbePlan -Path $Plan.file.path -ExpectedSha256 $Plan.file.sha256 -Inputs $Inputs
    if ($null -ne $canonicalPlan.inputs) { $Inputs = $canonicalPlan.inputs }
    $Plan = $canonicalPlan
    $NativeProfile = Read-SwiftUIOverlayProbeNativeProfile -Path $NativeProfile.file.path `
        -ExpectedSha256 $Plan.nativeProfileSha256 -Inputs $Inputs
    $requests = New-SwiftUIOverlayProbeRequestSchedule -Plan $Plan
    $layout = Get-SwiftUIOverlayExpectedLayout -SourceContext $Inputs.source
    $forbidden = @($Inputs.source.inputs.captureContext.captureRoot, $Inputs.source.inputs.auditRoot,
        (Split-Path -Parent $Inputs.discovery.path), $layout.sdk, $layout.toolchain)
    $output = New-SwiftUIOverlayProbeOutputDirectory -Path $OutputDirectory -ForbiddenRoots $forbidden
    Write-SwiftUIOverlayNewFile -Path (Join-Path $output '.in-progress') -Bytes ([Text.Encoding]::UTF8.GetBytes('native overlay observation publication has not closed' + [char]10))
    [void](New-SwiftUIOverlayProbeOwnedDirectory -Root $output -RelativePath 'inputs')
    [void](New-SwiftUIOverlayProbeOwnedDirectory -Root $output -RelativePath 'evidence')
    [void](New-SwiftUIOverlayProbeOwnedDirectory -Root $output -RelativePath '.work/requests')
    $graphRoot = New-SwiftUIOverlayProbeOwnedDirectory -Root $output -RelativePath '.work/graphs'
    $planFile = Copy-SwiftUIOverlayProbeBoundedFile -Source $Plan.file.path -Destination (Join-Path $output 'inputs/probe-plan.json') -MaximumBytes 1MB -ExpectedSha256 $Plan.file.sha256
    $profileFile = Copy-SwiftUIOverlayProbeBoundedFile -Source $NativeProfile.file.path -Destination (Join-Path $output 'inputs/native-profile.json') -MaximumBytes 1MB -ExpectedSha256 $NativeProfile.file.sha256
    $state = New-SwiftUIOverlayProbeScheduleState
    $session = [pscustomobject]@{
        output = $output; inputs = $Inputs; plan = $Plan; nativeProfile = $NativeProfile; state = $state
        graphRoot = $graphRoot; loadedBytes = [long]0; executionKind = 'native'
        toolingSeals = Write-SwiftUIOverlayProbeToolingSnapshot -OutputDirectory $output
        batchId = Get-SwiftUIOverlayId @('overlay-probe-batch-v1', $Plan.file.sha256, $NativeProfile.file.sha256)
    }
    $errors = [Collections.Generic.List[string]]::new()
    $supplemental = [pscustomobject]@{ status = 'not-attempted'; report = $null }
    $sourceRechecked = $false
    try {
        Assert-SwiftUIOverlayProbeInputSeals $Inputs
        Invoke-SwiftUIOverlayProbeSchedule -Requests $requests -State $state -Context $session -Execute {
            param($request, $context); Invoke-SwiftUIOverlayProbeNativeRequest -Request $request -Session $context
        }
        $extractions = New-SwiftUIOverlayProbeExtractionSchedule -Plan $Plan -ImportResults $state.results.ToArray()
        Invoke-SwiftUIOverlayProbeSchedule -Requests $extractions.requests -State $state -Context $session -Execute {
            param($request, $context); Invoke-SwiftUIOverlayProbeNativeRequest -Request $request -Session $context
        }
        if (-not $state.stopped) { $supplemental = Write-SwiftUIOverlayProbeSupplementalGraphs -Session $session -ExtractionSchedule $extractions }
        else { $errors.Add('Remaining launches stopped: ' + $state.stopReason) }
        Assert-SwiftUIOverlayProbeInputSeals $Inputs
        [void](Get-SwiftUIOverlayProbeBoundedHash -Path $Plan.file.path -Kind 'selected-plan' -ExpectedSha256 $Plan.file.sha256 -MaximumBytes 1MB)
        [void](Get-SwiftUIOverlayProbeBoundedHash -Path $NativeProfile.file.path -Kind 'selected-profile' -ExpectedSha256 $NativeProfile.file.sha256 -MaximumBytes 1MB)
        $sourceRechecked = $true
    } catch {
        $errors.Add($_.Exception.Message)
        $state.stopped = $true
        if ($null -eq $state.stopReason) { $state.stopReason = 'collection-or-publication-failed' }
    }
    # A failure before scheduling cannot erase the promised request roster.
    # Record omitted requests as unrun; this does not call any executor.
    $known = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in $state.results) { [void]$known.Add($record.requestId) }
    $remaining = [Collections.Generic.List[object]]::new()
    foreach ($request in $requests) { if (-not $known.Contains($request.requestId)) { $remaining.Add($request) } }
    $derived = New-SwiftUIOverlayProbeExtractionSchedule -Plan $Plan -ImportResults $state.results.ToArray()
    foreach ($request in $derived.requests) { if (-not $known.Contains($request.requestId)) { $remaining.Add($request) } }
    foreach ($request in $remaining) {
        $state.results.Add([pscustomobject]@{
            requestId=$request.requestId; kind=$request.kind; outcome='not-run'; nativeInvocationAttempted=$false; processStarted=$false
            stopLaterCommands=$true; descendantClosureRequired=$state.descendantClosureRequired; resultFile=$null
            positiveFrontendObservations=@(); assessments=@()
        })
    }
    # Every requested combined import remains an observation even if it did not
    # load a named overlay. This changes operational success, never API scope.
    foreach ($request in $requests) {
        $matches = @($state.results | Where-Object { $_.requestId -ceq $request.requestId })
        if ($matches.Count -ne 1 -or $matches[0].outcome -cne 'import-controls-recorded') { continue }
        if ($request.control -cin @('owner-bystander', 'bystander-owner')) {
            foreach ($assessment in $matches[0].assessments) {
                if (-not $assessment.overlayActivationObserved) {
                    $errors.Add('No eligible overlay load observation for request ' + $request.requestId + ' module ' + $assessment.overlayModule)
                }
            }
        }
    }
    $compact = @($state.results | ForEach-Object { [pscustomobject][ordered]@{
        requestId = $_.requestId; kind = $_.kind; outcome = $_.outcome
        nativeInvocationAttempted = $_.nativeInvocationAttempted; processStarted = $_.processStarted
        stopLaterCommands = $_.stopLaterCommands; descendantClosureRequired = $_.descendantClosureRequired
        resultFile = $_.resultFile
    } })
    $successful = $sourceRechecked -and $errors.Count -eq 0 -and -not $state.stopped -and
        @($compact | Where-Object { $_.outcome -cnotin @('import-controls-recorded', 'extractor-completed') }).Count -eq 0
    $report = [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'swiftui-overlay-probe-report-v1'; batchId = $session.batchId; executionKind = 'native'
        successful = $successful; status = $(if ($successful) { 'recorded-awaiting-review' } else { 'incomplete-or-failed' })
        sourceArtifacts = $Inputs.sourceArtifacts
        plan = [pscustomobject]@{ path = 'inputs/probe-plan.json'; bytes = $planFile.bytes; sha256 = $planFile.sha256 }
        nativeProfile = [pscustomobject]@{ path = 'inputs/native-profile.json'; bytes = $profileFile.bytes; sha256 = $profileFile.sha256 }
        selection = [pscustomobject]@{
            meaning = 'explicit bounded batch only; unselected candidates remain unresolved'
            candidateDispositions = $Plan.dispositions; selectedPairIds = @($Plan.pairs.pairId)
            duplicateNameOccurrencesRemainInPlan = $true; definitionOccurrenceTriggered = $false
        }
        policy = Get-SwiftUIOverlayProbeCollectionPolicy
        tooling = @($session.toolingSeals | ForEach-Object { [pscustomobject]@{
            path = 'inputs/tooling/' + $_.relativePath; bytes = $_.bytes; sha256 = $_.sha256
            interpretation = 'source file observed before launch; not an independent attestation of in-memory execution'
        } })
        processBoundary = [pscustomobject]@{
            nativeSandboxEstablished = $false; inheritedEnvironmentIsNotSealed = $true
            wholeSDKByteIdentityEstablished = $false; atomicLoadedImageAttestation = $false
            descendantsClosed = $null; descendantClosureRequired = $state.descendantClosureRequired
            followup = 'No resume in this profile. After termination uncertainty, an operator must establish descendant closure before authorizing another native command.'
            unsealedDisposableNamespace = '.work'; unsealedMeaning = 'compiler caches, original traces and original graph outputs; no disk quota or immutable evidence claim'
        }
        requests = $compact; supplemental = $supplemental; errors = $errors.ToArray()
        nativeInvocationsAttempted = @($compact | Where-Object { $_.nativeInvocationAttempted -eq $true }).Count
        confirmedProcessesStarted = @($compact | Where-Object { $_.processStarted -eq $true }).Count
        sourceSealsRechecked = $sourceRechecked
        qualification = [pscustomobject][ordered]@{
            reviewedIdentity = $false; declarationCompleteness = $false; overlayCompleteness = $false; behaviorConformance = $false
        }
        files = Get-SwiftUIOverlayProbePayloadInventory -Root $output
    }
    $file = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $output 'probe-report.json') -Value $report
    Write-SwiftUIOverlayNewFile -Path (Join-Path $output 'probe-report.sha256') `
        -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($file.sha256 + '  probe-report.json' + [char]10))
    # The marker concerns publication only, not process-tree closure. A failed
    # but sealed report keeps its uncertainty and cannot authorize a resume.
    [IO.File]::Delete((Join-Path $output '.in-progress'))
    return Read-SwiftUIOverlayProbeReport -Root $output -ExpectedSha256 $file.sha256
}
