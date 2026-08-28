<#
.SYNOPSIS
    Synthetic CI font-coordinator tests; no SwiftPM, renderer, or font probes.
#>
param([string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ('swift-windowsui-ci-bitmap-tests-' + [Guid]::NewGuid().ToString('N'))))

$ErrorActionPreference = 'Stop'
$testRoot = [IO.Path]::GetFullPath($WorkDir)
if (Test-Path -LiteralPath $testRoot) { throw 'Synthetic test output must be new; existing evidence is never overwritten.' }
[void][IO.Directory]::CreateDirectory($testRoot)
. (Join-Path $PSScriptRoot 'capture-ci-bitmap-font-attribution.ps1')
$script:ciTestProcessImplementation = ${function:Invoke-CiBitmapProcess}

# The suite injects these boundaries. An accidental use of a production adapter
# fails before Git, Swift setup, a process launch, or a native font probe.
function Get-CiBitmapSource { throw 'Production source observer forbidden in synthetic tests.' }
function Invoke-CiBitmapProcess { throw 'Production process adapter forbidden in synthetic tests.' }
function Initialize-GalleryBitmapFontFileAdapter { throw 'Native file adapter forbidden in synthetic tests.' }
function Add-Type { throw 'Compilation forbidden in synthetic tests.' }

$script:ciTestResults = [Collections.Generic.List[object]]::new()
$script:ciTestIndex = 0

function Assert-CiTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Write-CiTestBytes {
    param([string]$Path, [byte[]]$Bytes)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    # This helper may deliberately mutate owned input fixtures. Coordinator
    # evidence itself always uses Write-CiBitmapJsonNew/CreateNew.
    [IO.File]::WriteAllBytes($Path, $Bytes)
}

function Write-CiTestJson {
    param([string]$Path, $Value, [switch]$Bom)
    $encoding = [Text.UTF8Encoding]::new([bool]$Bom)
    $json = ConvertTo-Json -InputObject $Value -Depth 24
    Write-CiTestBytes $Path ([byte[]]@($encoding.GetPreamble() + $encoding.GetBytes($json + "`n")))
}

function Copy-CiTestObject {
    param($Value)
    $options = @{ InputObject = (ConvertTo-Json -InputObject $Value -Depth 24) }
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $options.DateKind = 'String' }
    ConvertFrom-Json @options
}

function New-CiTestState {
    param([string]$Name, [switch]$DebugAlias)
    $script:ciTestIndex++
    $root = Join-Path $testRoot ('{0:d3} {1} {2} space' -f $script:ciTestIndex, $Name, $(if ($DebugAlias) { 'junction' } else { '[literal]' }))
    [void][IO.Directory]::CreateDirectory($root)
    $context = New-CiBitmapContext $root '33123456789' '2'
    if ($DebugAlias) {
        $realDebug = Join-Path $root '.build/real-debug'
        [void][IO.Directory]::CreateDirectory($realDebug)
        [void](New-Item -ItemType Junction -Path (Join-Path $root '.build/debug') -Target $realDebug -ErrorAction Stop)
    }
    Write-CiTestBytes $context.galleryExecutable ([byte[]]@(77, 90, 1, 2, 3, 0, 255, 13, 10))
    [IO.File]::SetLastWriteTimeUtc($context.galleryExecutable, [datetime]'2001-01-01T00:00:00Z')
    $fingerprint = Read-GalleryBitmapArtifact $context.galleryExecutable $script:ciBitmapExecutableLimit
    $source = [pscustomobject]@{ root = $context.root; status = 'observed-checkout-only'; revision = ('a' * 40); dirty = $false; executableBuildRevision = $null }
    $state = [pscustomobject]@{
        name = $Name; context = $context; source = $source
        now = [DateTimeOffset]::Parse('2026-08-28T12:00:00Z'); sourceCalls = 0; prepareCalls = 0; executeCalls = 0
        environmentExit = 0; childExit = 0; onSource = $null; onPrepare = $null; onExecute = $null
        pixel = 'pass'; attribution = 'partial'; render = 'succeeded'; omitReport = $false; omitProfile = $false
        omitPng = $false; omitAttribution = $false; sidecars = $false; overflow = $false; prepared = $false; captureMode = 'normal'
        fingerprint = [pscustomobject]@{ path = $context.galleryExecutable; status = 'observed'; sha256 = $fingerprint.sha256; length = $fingerprint.length; lastWriteTimeUtc = '2001-01-01T00:00:00Z'; fileVersion = $null; error = $null }
        normal = $null; request = $null; sentinels = @(); observeAdapter = $null; prepareAdapter = $null; executeAdapter = $null; clockAdapter = $null
    }
    # GetNewClosure creates a dynamic module. Under agent-check's function ->
    # scriptblock -> script nesting, bare helper names there cannot see this
    # script's local functions. Capture the original function scriptblocks so
    # their own helper lookups and script-scoped limits retain this context.
    $ciAssert = ${function:Assert-CiTest}
    $ciCopyObject = ${function:Copy-CiTestObject}
    $ciWriteRender = ${function:Write-CiTestRender}
    $ciReceiveStreams = ${function:Receive-CiBitmapStreams}
    $state.observeAdapter = {
        param($root)
        $state.sourceCalls++
        & $ciAssert ($root -ceq $state.context.root) 'Unexpected source root.'
        if ($null -ne $state.onSource) { & $state.onSource $state }
        & $ciCopyObject $state.source
    }.GetNewClosure()
    $state.prepareAdapter = {
        param($context)
        $state.prepareCalls++; $state.prepared = $true
        & $ciAssert ($context.root -ceq $state.context.root) 'Unexpected environment root.'
        if ($null -ne $state.onPrepare) { & $state.onPrepare $state }
        $state.environmentExit
    }.GetNewClosure()
    $state.executeAdapter = {
        param($request)
        $state.executeCalls++; $state.request = $request
        & $ciAssert $state.prepared 'Environment must be prepared before execution.'
        & $ciAssert (-not (Test-Path -LiteralPath $state.context.renderDirectory)) 'Child WorkDir must not exist before execution.'
        & $ciWriteRender $state
        if ($null -ne $state.onExecute) { & $state.onExecute $state }
        $outBytes = [byte[]]@(0, 255, 13, 10, 111, 117, 116, 0)
        $errBytes = [byte[]]@(254, 0, 101, 114, 114, 10, 13)
        if ($state.overflow) {
            $outBytes = [byte[]]::new($request.maximumStreamBytes + 17)
            $errBytes = [byte[]]::new($request.maximumStreamBytes + 19)
            $outBytes[0] = 71; $outBytes[$request.maximumStreamBytes - 1] = 72
            $errBytes[0] = 91; $errBytes[$request.maximumStreamBytes - 1] = 92
        }
        $outInput = [IO.MemoryStream]::new($outBytes, $false); $errInput = [IO.MemoryStream]::new($errBytes, $false)
        $outFile = [IO.File]::Open($request.stdoutPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $errFile = [IO.File]::Open($request.stderrPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $capture = & $ciReceiveStreams $outInput $errInput $outFile $errFile $request.maximumStreamBytes }
        finally { $outFile.Dispose(); $errFile.Dispose(); $outInput.Dispose(); $errInput.Dispose() }
        if ($state.captureMode -ceq 'missing') { $capture = $null }
        if ($state.captureMode -ceq 'invalid-stdout') { $capture.stdout.status = @('complete') }
        if ($state.captureMode -ceq 'missing-stdout') { Remove-Item -LiteralPath $request.stdoutPath -ErrorAction Stop }
        [pscustomobject]@{ exitCode = $state.childExit; capture = $capture }
    }.GetNewClosure()
    $state.clockAdapter = { $state.now }.GetNewClosure()
    $sentinels = @('artifacts/gallery-compare/report.json', 'artifacts/gallery-compare/report.txt', 'artifacts/gallery-compare/report.html',
        'tests/fixtures/gallery-baselines/symbol-palette.png', 'tests/fixtures/gallery-baselines/stepper.png')
    foreach ($relative in $sentinels) {
        $path = Join-Path $root $relative
        Write-CiTestBytes $path ([Text.Encoding]::UTF8.GetBytes('unchanged synthetic sentinel: ' + $relative))
        $state.sentinels += [pscustomobject]@{ path = $path; sha256 = (Read-GalleryBitmapArtifact $path 4096).sha256 }
    }
    $state
}

function New-CiTestProfile {
    param($State)
    $source = [pscustomobject]@{ root = $State.context.root; status = 'observed-checkout-only'; revision = $State.source.revision; changes = @(); error = $null; executableBuildRevision = $null }
    [pscustomobject]@{
        schemaVersion = 1; invocationID = ('b' * 32); capturedAt = $State.now.ToString('o'); stage = 'render-completed'
        qualification = [pscustomobject]@{ status = 'unqualified'; acceptedBaselineProfile = $null; reason = 'Synthetic only.' }
        renderer = [pscustomobject]@{ declaredPath = 'synthetic-no-render'; declaredDisplayScale = 1; actualGlyphFaceOwnership = 'not-observed' }
        fonts = [pscustomobject]@{ status = 'synthetic-no-font-probe' }; os = [pscustomobject]@{ status = 'synthetic' }
        process = [pscustomobject]@{ is64Bit = $true; powershellVersion = $PSVersionTable.PSVersion.ToString() }
        runner = [pscustomobject]@{ os = 'synthetic' }; directWriteLibrary = $null; directWriteLibraryObservation = 'synthetic-no-library'
        source = $source; executable = Copy-CiTestObject $State.fingerprint
        executableAssociation = 'observed-after-successful-build; build-revision-not-embedded'
        build = [pscustomobject]@{ status = 'succeeded'; exitCode = 0; executableAfter = Copy-CiTestObject $State.fingerprint }
        render = [pscustomobject]@{ status = 'succeeded'; exitCode = 0; requestedEntries = @('stepper', 'symbol-palette'); outputDirectory = (Join-Path $State.context.root 'artifacts/gallery-compare/current');
            imageAssociation = 'invocation-completed; environment-probed-before-render; glyph-faces-not-observed'; executableAfter = Copy-CiTestObject $State.fingerprint; executableUnchanged = $true }
    }
}

function Start-CiTestBoundary {
    param($State, [switch]$Previous)
    if ($Previous) {
        $old = New-CiTestProfile $State
        $old.capturedAt = $State.now.AddMinutes(-10).ToString('o')
        Write-CiTestJson $State.context.normalProvenancePath $old
    }
    $boundary = Invoke-CiBitmapFontAttribution -Context $State.context -Phase BeforeFull -ObserveSource $State.observeAdapter -Clock $State.clockAdapter
    Assert-CiTest ($boundary.coordinatorExitCode -eq 0) 'Boundary failed.'
    $State.now = $State.now.AddSeconds(30)
    $State.normal = New-CiTestProfile $State
    Write-CiTestJson $State.context.normalProvenancePath $State.normal
    $State.now = $State.now.AddSeconds(30)
}

function Write-CiTestRender {
    param($State)
    $context = $State.context
    [void][IO.Directory]::CreateDirectory($context.renderDirectory)
    $profile = New-CiTestProfile $State
    $profile.invocationID = 'c' * 32
    $profile.executableAssociation = 'preexisting-file-invoked-without-build'
    $profile.build.status = 'skipped'; $profile.build.exitCode = $null; $profile.build.executableAfter = $null
    $profile.render.outputDirectory = Join-Path $context.renderDirectory 'current'
    if ($State.render -cne 'succeeded') { $profile.stage = 'render-failed'; $profile.render.status = 'failed'; $profile.render.exitCode = 1; $profile.render.imageAssociation = 'unverified-partial-or-preexisting-images' }
    $profilePath = Join-Path $context.renderDirectory 'provenance.json'
    if (-not $State.omitProfile) { Write-CiTestJson $profilePath $profile }
    if (-not $State.omitPng) {
        foreach ($fixture in @('stepper', 'symbol-palette')) {
            # Opaque fixture bytes; no image decoder/native rasterization occurs.
            Write-CiTestBytes (Join-Path $context.renderDirectory ("current/$fixture.png")) ([byte[]]@(137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3))
        }
    }
    $entries = @(foreach ($fixture in @('stepper', 'symbol-palette')) {
        $failed = $fixture -ceq 'symbol-palette' -and $State.pixel -cne 'pass'
        [pscustomobject]@{ id = $fixture; appearance = 'dark'; tier = 'control'; status = if ($failed) { 'fail' } else { 'pass' }
            detail = if ($State.pixel -ceq 'missing-baseline' -and $failed) { 'missing baseline (run with -UpdateBaselines)' } else { 'synthetic comparison' }
            changedPercent = if ($failed -and $State.pixel -cne 'missing-baseline') { 1.25 } else { 0.0 }
            maxChannelDelta = if ($failed -and $State.pixel -cne 'missing-baseline') { 65 } else { 0 }
            images = [pscustomobject]@{ baseline = "tests/fixtures/gallery-baselines/$fixture.png"; current = "current/$fixture.png"; diff = $null }
        }
    })
    $failures = @($entries | Where-Object { $_.status -ceq 'fail' }).Count
    $report = [pscustomobject]@{
        schemaVersion = 2; generatedAt = $State.now.ToString('o'); status = if ($failures) { 'fail' } else { 'pass' }
        fontProvenance = $profile
        selection = [pscustomobject]@{ selectedCount = 2; catalogCount = 85; appearance = 'all'; tier = 'all'; pattern = ''; requestedIds = @('symbol-palette', 'stepper') }
        thresholds = [pscustomobject]@{ maxChangedPercent = 0.5; channelTolerance = 8; maxChannelDelta = 64 }
        summary = [pscustomobject]@{ total = 2; passing = 2 - $failures; failing = $failures }; entries = $entries
        bitmapFontAttribution = [pscustomobject]@{ path = 'bitmap-font-attribution/report.json'; status = $State.attribution; qualification = 'unqualified'; pixelGate = 'unchanged' }
    }
    if (-not $State.omitReport) { Write-CiTestJson (Join-Path $context.renderDirectory 'report.json') $report }
    if (-not $State.omitAttribution -and -not $State.omitProfile) {
        $attributionEntries = @(foreach ($fixture in @('stepper', 'symbol-palette')) {
            $pngPath = 'current/' + $fixture + '.png'
            $png = if (-not $State.omitPng) { Read-GalleryBitmapArtifact (Join-Path $context.renderDirectory $pngPath) 33554432 } else { $null }
            $sidecarPath = 'bitmap-font-attribution/native/' + $fixture + '.native-font-attribution.json'
            $sidecar = $null
            if ($State.sidecars) {
                Write-CiTestJson (Join-Path $context.renderDirectory $sidecarPath) ([pscustomobject]@{ kind = 'synthetic-hash-link-only' })
                $sidecar = Read-GalleryBitmapArtifact (Join-Path $context.renderDirectory $sidecarPath) 524288
            }
            [pscustomobject]@{
                fixtureID = $fixture; status = 'partial'; association = 'unverified'
                png = [pscustomobject]@{ path = $pngPath; status = if ($null -ne $png) { 'observed' } else { 'unavailable' }; sha256 = $png.sha256; length = $png.length }
                nativeSidecar = [pscustomobject]@{ path = $sidecarPath; status = if ($null -ne $sidecar) { 'read-unverified' } else { 'unavailable' }; sha256 = $sidecar.sha256; length = $sidecar.length }
                native = $null; fileReferences = @(); error = 'synthetic-no-native-attribution'
            }
        })
        $attribution = [pscustomobject]@{
            schemaVersion = 1; kind = 'gallery-bitmap-font-attribution'; status = $State.attribution
            qualification = [pscustomobject]@{ status = 'unqualified'; acceptedBaselineProfile = $null; pixelGate = 'unchanged'; performanceQualification = 'excluded' }
            invocationID = $profile.invocationID; invocationAssociation = 'linked-to-completed-invocation'
            source = [pscustomobject]@{ revision = $profile.source.revision; observationSha256 = Get-GalleryBitmapJsonDigest $profile.source; observation = 'checkout-only'; executableBuildRevision = $null }
            executable = [pscustomobject]@{ beforeSha256 = $State.fingerprint.sha256; afterSha256 = $State.fingerprint.sha256; unchanged = $true; buildRevision = 'not-embedded' }
            currentFontProfile = [pscustomobject]@{ path = 'provenance.json'; sha256 = (Read-GalleryBitmapArtifact $profilePath 524288).sha256; observation = 'current-collector-profile; not-actual-loaded-font-bytes' }
            nativeRuntimeObservation = 'synthetic'
            coverage = [pscustomobject]@{ fixtures = @('stepper', 'symbol-palette'); scope = 'bitmap-icons'; atlasGlyphs = 'not-instrumented'; textLayouts = 'not-instrumented' }
            limits = [pscustomobject]@{ aggregateDropped = $false }
            entries = $attributionEntries; files = @()
        }
        Write-CiTestJson (Join-Path $context.renderDirectory 'bitmap-font-attribution/report.json') $attribution
    }
}

function Invoke-CiTestAfter {
    param($State, [string]$Outcome = 'failure')
    $result = Invoke-CiBitmapFontAttribution -Context $State.context -Phase AfterFull -FullOutcome $Outcome `
        -ObserveSource $State.observeAdapter -PrepareEnvironment $State.prepareAdapter -Execute $State.executeAdapter -Clock $State.clockAdapter
    foreach ($sentinel in $State.sentinels) { Assert-CiTest ((Read-GalleryBitmapArtifact $sentinel.path 4096).sha256 -ceq $sentinel.sha256) 'Normal report/baseline was modified.' }
    Assert-CiTest ($result.fullOutcome -ceq $Outcome) 'Original Full outcome lost.'
    Assert-CiTest ($result.qualification -ceq 'unqualified' -and $result.loadedFontBytes -ceq 'not-observed') 'Qualification was improperly promoted.'
    $persisted = (Read-CiBitmapJson $State.context.resultPath).value
    Assert-CiTest ($persisted.childExitCode -eq $result.childExitCode -and $persisted.coordinatorExitCode -eq $result.coordinatorExitCode) 'Persisted exit codes differ.'
    $result
}

function Assert-CiTestBlocked {
    param($State, $Result, [string]$Reason = '')
    Assert-CiTest ($Result.status -ceq 'blocked' -and $Result.coordinatorExitCode -ne 0 -and $null -eq $Result.childExitCode) 'Invalid evidence did not block.'
    Assert-CiTest ($State.executeCalls -eq 0) 'Blocked evidence launched a child.'
    if ($Reason.Length -gt 0) { Assert-CiTest ($Result.reason -ceq $Reason) ('Unexpected blocked reason: ' + $Result.reason) }
}

function Test-CiCase {
    param([string]$Name, [scriptblock]$Body)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $Body
        $script:ciTestResults.Add([pscustomobject]@{ name = $Name; status = 'pass'; elapsedMilliseconds = $watch.ElapsedMilliseconds })
        Write-Host ('PASS ' + $Name)
    } catch {
        $script:ciTestResults.Add([pscustomobject]@{ name = $Name; status = 'fail'; elapsedMilliseconds = $watch.ElapsedMilliseconds; error = $_.Exception.Message; position = $_.InvocationInfo.PositionMessage })
        Write-Host ('FAIL ' + $Name + ': ' + $_.Exception.Message)
    } finally { $watch.Stop() }
}

Test-CiCase 'pass-with-partial-attribution-and-unchanged-incremental-mtime' {
    $state = New-CiTestState 'partial-pass'; Start-CiTestBoundary $state -Previous
    $result = Invoke-CiTestAfter $state 'success'
    Assert-CiTest ($result.status -ceq 'completed-pixel-pass' -and $result.childExitCode -eq 0 -and $result.coordinatorExitCode -eq 0) ('Unexpected pass result: ' + $result.reason)
    Assert-CiTest ($result.pixel.status -ceq 'pass' -and $result.attribution.status -ceq 'partial') 'Pixel and attribution outcomes conflated.'
    Assert-CiTest ($state.executeCalls -eq 1 -and $state.prepareCalls -eq 1) 'Expected one prepared invocation.'
    Assert-CiTest ([IO.File]::GetLastWriteTimeUtc($state.context.galleryExecutable).Year -eq 2001) 'Incremental mtime was changed.'
    $expected = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $state.context.wrapper, '-BitmapFontAttribution', '-SkipBuild', '-Entries', 'symbol-palette,stepper', '-GalleryExe', $state.context.galleryExecutable, '-WorkDir', $state.context.renderDirectory)
    Assert-CiTest (($state.request.arguments -join "`0") -ceq ($expected -join "`0")) 'Exact two-fixture SkipBuild argv changed.'
    Assert-CiTest ($state.request.workingDirectory -ceq $state.context.root) 'Wrong child working directory.'
    $stdout = [IO.File]::ReadAllBytes($state.request.stdoutPath); $stderr = [IO.File]::ReadAllBytes($state.request.stderrPath)
    Assert-CiTest ([Convert]::ToBase64String($stdout) -ceq [Convert]::ToBase64String([byte[]]@(0, 255, 13, 10, 111, 117, 116, 0))) 'Raw stdout bytes changed.'
    Assert-CiTest ([Convert]::ToBase64String($stderr) -ceq [Convert]::ToBase64String([byte[]]@(254, 0, 101, 114, 114, 10, 13))) 'Raw stderr bytes changed.'
    Assert-CiTest ($result.streams.stdout.sha256 -ceq (Read-GalleryBitmapArtifact $state.request.stdoutPath 16777216).sha256) 'Stdout digest mismatch.'
    Assert-CiTest ($result.streams.stderr.sha256 -ceq (Read-GalleryBitmapArtifact $state.request.stderrPath 16777216).sha256) 'Stderr digest mismatch.'
}

Test-CiCase 'completed-pixel-mismatch-retains-child-and-Full-failure' {
    $state = New-CiTestState 'pixel-failure'; Start-CiTestBoundary $state
    $state.pixel = 'mismatch'; $state.childExit = 1
    $result = Invoke-CiTestAfter $state
    Assert-CiTest ($result.status -ceq 'completed-with-pixel-mismatches' -and $result.pixel.status -ceq 'mismatches') ('Wrong mismatch classification: ' + $result.reason)
    Assert-CiTest ($result.childExitCode -eq 1 -and $result.coordinatorExitCode -eq 1) 'Exit 1 was masked.'
    Assert-CiTest (Test-Path -LiteralPath (Join-Path $state.context.renderDirectory 'report.json')) 'Pixel report was not preserved.'
}

Test-CiCase 'normal-render-failure-after-successful-build-remains-eligible' {
    $state = New-CiTestState 'normal-render-failed'; Start-CiTestBoundary $state
    $state.normal.stage = 'render-failed'; $state.normal.render.status = 'failed'; $state.normal.render.exitCode = 1
    $state.normal.render.imageAssociation = 'unverified-partial-or-preexisting-images'
    Write-CiTestJson $state.context.normalProvenancePath $state.normal
    $result = Invoke-CiTestAfter $state
    Assert-CiTest ($state.executeCalls -eq 1 -and $result.coordinatorExitCode -eq 0) ('Successful build receipt incorrectly rejected: ' + $result.reason)
    Assert-CiTest ($result.normalGallery.renderStatus -ceq 'failed' -and $result.normalGallery.renderExitCode -eq 1 -and
        $result.normalGallery.imageAssociation -ceq 'unverified-partial-or-preexisting-images') 'Original render association upgraded.'
}

Test-CiCase 'exact-provenance-copy-preserves-BOM' {
    $state = New-CiTestState 'bom-copy'; Start-CiTestBoundary $state
    Write-CiTestJson $state.context.normalProvenancePath $state.normal -Bom
    $before = Read-GalleryBitmapArtifact $state.context.normalProvenancePath 524288
    $result = Invoke-CiTestAfter $state
    Assert-CiTest ($result.coordinatorExitCode -eq 0) ('BOM receipt rejected: ' + $result.reason)
    $copy = Read-GalleryBitmapArtifact $state.context.copiedProvenancePath 524288
    Assert-CiTest ($copy.sha256 -ceq $before.sha256 -and $copy.length -eq $before.length) 'Exact receipt bytes were re-encoded.'
}

Test-CiCase 'standard-debug-directory-junction-is-allowed' {
    $state = New-CiTestState 'debug-junction' -DebugAlias; Start-CiTestBoundary $state
    $result = Invoke-CiTestAfter $state
    Assert-CiTest ($result.coordinatorExitCode -eq 0 -and $state.executeCalls -eq 1) ('Debug directory alias incorrectly rejected: ' + $result.reason)
}

$normalCases = @(
    @('stale-time', { param($s) $s.normal.capturedAt = $s.now.AddHours(-1).ToString('o') }),
    @('future-time', { param($s) $s.normal.capturedAt = $s.now.AddHours(1).ToString('o') }),
    @('failed-build', { param($s) $s.normal.build.status = 'failed'; $s.normal.build.exitCode = 1 }),
    @('skipped-build', { param($s) $s.normal.build.status = 'skipped'; $s.normal.build.exitCode = $null }),
    @('build-exit-string-zero', { param($s) $s.normal.build.exitCode = '0' }),
    @('build-exit-false', { param($s) $s.normal.build.exitCode = $false }),
    @('build-exit-nonzero', { param($s) $s.normal.build.exitCode = 1 }),
    @('build-fingerprint-null', { param($s) $s.normal.build.executableAfter = $null }),
    @('build-fingerprint-unobserved', { param($s) $s.normal.build.executableAfter.status = 'missing' }),
    @('build-hash-mismatch', { param($s) $s.normal.build.executableAfter.sha256 = 'f' * 64 }),
    @('build-size-mismatch', { param($s) $s.normal.build.executableAfter.length = 10 }),
    @('build-size-zero', { param($s) $s.normal.build.executableAfter.length = 0 }),
    @('build-size-over-limit', { param($s) $s.normal.build.executableAfter.length = 268435457 }),
    @('alternate-executable-path', { param($s) $s.normal.build.executableAfter.path = Join-Path $s.context.root '.build/release/swift-windowsui-gallery.exe' }),
    @('relative-executable-path', { param($s) $s.normal.build.executableAfter.path = '.build/debug/swift-windowsui-gallery.exe' }),
    @('pre-render-hash-mismatch', { param($s) $s.normal.executable.sha256 = 'e' * 64 }),
    @('receipt-source-revision-mismatch', { param($s) $s.normal.source.revision = 'd' * 40 }),
    @('receipt-source-root-mismatch', { param($s) $s.normal.source.root = Join-Path $s.context.root 'other' }),
    @('receipt-source-dirty', { param($s) $s.normal.source.changes = @(' M file') }),
    @('receipt-source-null-changes', { param($s) $s.normal.source.changes = $null }),
    @('receipt-source-scalar-changes', { param($s) $s.normal.source.changes = '' }),
    @('receipt-source-missing-changes', { param($s) $s.normal.source.PSObject.Properties.Remove('changes') }),
    @('receipt-source-unavailable', { param($s) $s.normal.source.status = 'unknown' }),
    @('receipt-source-invented-binary-origin', { param($s) $s.normal.source.executableBuildRevision = 'a' * 40 }),
    @('receipt-schema-wrong', { param($s) $s.normal.schemaVersion = 2 }),
    @('receipt-schema-string', { param($s) $s.normal.schemaVersion = '1' }),
    @('receipt-qualification-promoted', { param($s) $s.normal.qualification.status = 'qualified' }),
    @('build-status-array', { param($s) $s.normal.build.status = @('succeeded') }),
    @('source-status-array', { param($s) $s.normal.source.status = @('observed-checkout-only') }),
    @('fingerprint-status-array', { param($s) $s.normal.build.executableAfter.status = @('observed') }),
    @('qualification-status-array', { param($s) $s.normal.qualification.status = @('unqualified') })
)
foreach ($case in $normalCases) {
    $caseName = $case[0]; $mutation = $case[1]
    Test-CiCase $caseName {
        $state = New-CiTestState $caseName; Start-CiTestBoundary $state
        & $mutation $state
        Write-CiTestJson $state.context.normalProvenancePath $state.normal
        $result = Invoke-CiTestAfter $state
        Assert-CiTestBlocked $state $result
        Assert-CiTest ($state.prepareCalls -eq 0) 'Invalid receipt prepared native environment.'
    }
}

$invalidJsonCases = @(
    @('duplicate-json-key', [Text.Encoding]::UTF8.GetBytes('{"schemaVersion":1,"schemaVersion":1}')),
    @('case-aliased-json-key', [Text.Encoding]::UTF8.GetBytes('{"schemaVersion":1,"SchemaVersion":1}')),
    @('escaped-aliased-json-key', [Text.Encoding]::UTF8.GetBytes('{"key":1,"\u006bey":2}')),
    @('trailing-comma-json', [Text.Encoding]::UTF8.GetBytes('{"key":1,}')),
    @('comment-json', [Text.Encoding]::UTF8.GetBytes('{/* comment */"key":1}')),
    @('invalid-utf8', [byte[]]@(123, 34, 120, 34, 58, 34, 255, 34, 125)),
    @('nonobject-json', [Text.Encoding]::UTF8.GetBytes('[]')),
    @('oversized-json', [byte[]]::new(524289))
)
foreach ($case in $invalidJsonCases) {
    $caseName = $case[0]; $bytes = $case[1]
    Test-CiCase $caseName {
        $state = New-CiTestState $caseName; Start-CiTestBoundary $state
        Write-CiTestBytes $state.context.normalProvenancePath $bytes
        $result = Invoke-CiTestAfter $state
        Assert-CiTestBlocked $state $result 'ci-bitmap-normal-provenance-invalid'
    }
}

Test-CiCase 'missing-normal-provenance-does-not-use-existing-executable' {
    $state = New-CiTestState 'missing-receipt'
    [void](Invoke-CiBitmapFontAttribution -Context $state.context -Phase BeforeFull -ObserveSource $state.observeAdapter -Clock $state.clockAdapter)
    $result = Invoke-CiTestAfter $state
    Assert-CiTestBlocked $state $result
}

Test-CiCase 'unchanged-previous-provenance-is-stale' {
    $state = New-CiTestState 'unchanged-receipt'
    $state.normal = New-CiTestProfile $state
    Write-CiTestJson $state.context.normalProvenancePath $state.normal
    [void](Invoke-CiBitmapFontAttribution -Context $state.context -Phase BeforeFull -ObserveSource $state.observeAdapter -Clock $state.clockAdapter)
    $result = Invoke-CiTestAfter $state
    Assert-CiTestBlocked $state $result 'ci-bitmap-receipt-not-fresh'
}

Test-CiCase 'missing-boundary-produces-blocked-result-without-launch' {
    $state = New-CiTestState 'missing-boundary'
    $result = Invoke-CiTestAfter $state
    Assert-CiTestBlocked $state $result 'ci-bitmap-boundary-missing'
}

Test-CiCase 'boundary-run-mismatch' {
    $state = New-CiTestState 'boundary-run'; Start-CiTestBoundary $state
    $boundary = (Read-CiBitmapJson $state.context.boundaryPath).value; $boundary.runAttempt = '1'
    Write-CiTestJson $state.context.boundaryPath $boundary
    Assert-CiTestBlocked $state (Invoke-CiTestAfter $state) 'ci-bitmap-boundary-invalid'
}

foreach ($kind in @('missing-status', 'unknown-status', 'array-status', 'observed-missing-hash', 'missing-with-hash', 'array-run')) {
    Test-CiCase ('boundary-schema-' + $kind) {
        $state = New-CiTestState ('boundary-' + $kind); Start-CiTestBoundary $state
        $boundary = (Read-CiBitmapJson $state.context.boundaryPath).value
        switch ($kind) {
            'missing-status' { $boundary.previousNormalProvenance.PSObject.Properties.Remove('status') }
            'unknown-status' { $boundary.previousNormalProvenance.status = 'anything' }
            'array-status' { $boundary.previousNormalProvenance.status = @('missing') }
            'observed-missing-hash' { $boundary.previousNormalProvenance.status = 'observed' }
            'missing-with-hash' { $boundary.previousNormalProvenance.sha256 = 'f' * 64 }
            'array-run' { $boundary.runID = @($state.context.runID) }
        }
        Write-CiTestJson $state.context.boundaryPath $boundary
        Assert-CiTestBlocked $state (Invoke-CiTestAfter $state) 'ci-bitmap-boundary-invalid'
    }
}

Test-CiCase 'dirty-boundary-retained-and-blocked' {
    $state = New-CiTestState 'boundary-dirty'; $state.source.dirty = $true; Start-CiTestBoundary $state
    $state.source.dirty = $false
    Assert-CiTestBlocked $state (Invoke-CiTestAfter $state) 'ci-bitmap-source-dirty-or-unavailable'
}

foreach ($kind in @('dirty', 'revision')) {
    Test-CiCase ('current-source-' + $kind) {
        $state = New-CiTestState ('source-' + $kind); Start-CiTestBoundary $state
        if ($kind -ceq 'dirty') { $state.source.dirty = $true } else { $state.source.revision = 'e' * 40 }
        Assert-CiTestBlocked $state (Invoke-CiTestAfter $state)
    }
}

Test-CiCase 'missing-executable-blocks' {
    $state = New-CiTestState 'missing-exe'; Start-CiTestBoundary $state
    # Only a specifically named owned fixture leaf is removed, never a tree.
    Remove-Item -LiteralPath $state.context.galleryExecutable -ErrorAction Stop
    Assert-CiTestBlocked $state (Invoke-CiTestAfter $state) 'ci-bitmap-executable-unavailable'
}

Test-CiCase 'empty-executable-blocks' {
    $state = New-CiTestState 'empty-exe'; Start-CiTestBoundary $state
    Write-CiTestBytes $state.context.galleryExecutable ([byte[]]@())
    Assert-CiTestBlocked $state (Invoke-CiTestAfter $state) 'ci-bitmap-executable-unavailable'
}

Test-CiCase 'existing-render-directory-blocks-and-is-not-deleted' {
    $state = New-CiTestState 'existing-render'; Start-CiTestBoundary $state
    $marker = Join-Path $state.context.renderDirectory 'preserve.txt'; Write-CiTestBytes $marker ([byte[]]@(1, 2, 3))
    Assert-CiTestBlocked $state (Invoke-CiTestAfter $state) 'ci-bitmap-render-directory-exists'
    Assert-CiTest ((Read-GalleryBitmapArtifact $marker 3).length -eq 3) 'Existing render data changed.'
}

Test-CiCase 'environment-failure-does-not-launch' {
    $state = New-CiTestState 'environment-failed'; Start-CiTestBoundary $state
    $state.environmentExit = 7
    Assert-CiTestBlocked $state (Invoke-CiTestAfter $state) 'ci-bitmap-environment-preparation-failed'
    Assert-CiTest (Test-Path -LiteralPath (Join-Path $state.context.outputDirectory 'attempt.json')) 'Eligible attempt missing.'
}

Test-CiCase 'prelaunch-executable-change-blocks-after-environment' {
    $state = New-CiTestState 'prelaunch-change'; Start-CiTestBoundary $state
    $state.onPrepare = { param($s) Write-CiTestBytes $s.context.galleryExecutable ([byte[]]@(10, 20, 30)) }
    Assert-CiTestBlocked $state (Invoke-CiTestAfter $state) 'ci-bitmap-prelaunch-observation-changed'
}

Test-CiCase 'prelaunch-source-change-blocks-after-environment' {
    $state = New-CiTestState 'prelaunch-source'; Start-CiTestBoundary $state
    $state.onPrepare = { param($s) $s.source.dirty = $true }
    Assert-CiTestBlocked $state (Invoke-CiTestAfter $state) 'ci-bitmap-source-dirty-or-unavailable'
}

foreach ($kind in @('incomplete-render', 'missing-baseline', 'missing-report', 'missing-png')) {
    Test-CiCase ($kind + '-is-not-pixel-mismatch') {
        $state = New-CiTestState $kind; Start-CiTestBoundary $state
        $state.childExit = 1; $state.pixel = 'mismatch'
        if ($kind -ceq 'incomplete-render') { $state.render = 'failed' }
        if ($kind -ceq 'missing-baseline') { $state.pixel = 'missing-baseline' }
        if ($kind -ceq 'missing-report') { $state.omitReport = $true }
        if ($kind -ceq 'missing-png') { $state.omitPng = $true }
        $result = Invoke-CiTestAfter $state
        Assert-CiTest ($result.status -ceq 'failed-or-incomplete' -and $result.childExitCode -eq 1 -and $result.coordinatorExitCode -eq 1) 'Incomplete evidence mislabeled or exit masked.'
        Assert-CiTest ($result.association -ceq 'unverified') 'Incomplete association promoted.'
    }
}

Test-CiCase 'exit-zero-with-missing-optional-attribution-stays-unqualified' {
    $state = New-CiTestState 'attribution-unavailable'; Start-CiTestBoundary $state
    $state.omitAttribution = $true
    $result = Invoke-CiTestAfter $state
    Assert-CiTest ($result.coordinatorExitCode -eq 0 -and $result.pixel.status -ceq 'pass' -and $result.attribution.status -ceq 'unavailable') ('Missing optional metadata changed pixel result: ' + $result.reason)
}

Test-CiCase 'positive-collector-links-with-partial-metadata' {
    $state = New-CiTestState 'positive-links'; Start-CiTestBoundary $state
    $state.sidecars = $true
    $state.onExecute = {
        param($s)
        $path = Join-Path $s.context.renderDirectory 'bitmap-font-attribution/report.json'
        $record = (Read-CiBitmapJson $path).value
        foreach ($entry in $record.entries) {
            $entry.association = 'linked-to-completed-invocation; scene-reference-is-not-visible-contribution'
            $entry.nativeSidecar.status = 'validated'
        }
        Write-CiTestJson $path $record
    }
    $result = Invoke-CiTestAfter $state
    Assert-CiTest ($result.coordinatorExitCode -eq 0 -and $result.pixel.status -ceq 'pass' -and $result.attribution.status -ceq 'partial' -and
        $result.attribution.invocationAssociation -ceq 'linked-to-completed-invocation') ('Actual collector link shape rejected: ' + $result.reason)
}

foreach ($kind in @('source-digest', 'png-link', 'sidecar-link', 'observed-with-unverified-entry', 'array-kind')) {
    Test-CiCase ('attribution-link-rejection-' + $kind) {
        $state = New-CiTestState ('link-' + $kind); Start-CiTestBoundary $state
        $state.sidecars = $true
        $ciReadJson = ${function:Read-CiBitmapJson}
        $ciWriteBytes = ${function:Write-CiTestBytes}
        $ciWriteJson = ${function:Write-CiTestJson}
        # The foreach variable is in the outer script scope, so make the value
        # local before GetNewClosure captures this callback's dependencies.
        $ciMutationKind = $kind
        $state.onExecute = {
            param($s)
            $path = Join-Path $s.context.renderDirectory 'bitmap-font-attribution/report.json'
            $record = (& $ciReadJson $path).value
            switch ($ciMutationKind) {
                'source-digest' { $record.source.observationSha256 = 'f' * 64 }
                'png-link' { & $ciWriteBytes (Join-Path $s.context.renderDirectory 'current/stepper.png') ([byte[]]@(10, 11, 12)) }
                'sidecar-link' { & $ciWriteBytes (Join-Path $s.context.renderDirectory 'bitmap-font-attribution/native/stepper.native-font-attribution.json') ([byte[]]@(13, 14, 15)) }
                'observed-with-unverified-entry' { $record.status = 'observed' }
                'array-kind' { $record.kind = @('gallery-bitmap-font-attribution') }
            }
            & $ciWriteJson $path $record
        }.GetNewClosure()
        $result = Invoke-CiTestAfter $state
        Assert-CiTest ($result.status -ceq 'failed-or-incomplete' -and $result.childExitCode -eq 0 -and $result.coordinatorExitCode -eq 1 -and $result.association -ceq 'unverified') 'Invalid attribution link was accepted.'
    }
}

foreach ($exit in @(0, 1, 7)) {
    Test-CiCase ('post-validation-error-retains-child-' + $exit) {
        $state = New-CiTestState ('post-error-' + $exit); Start-CiTestBoundary $state
        $state.childExit = $exit; $state.omitReport = $true
        $result = Invoke-CiTestAfter $state
        Assert-CiTest ($result.childExitCode -eq $exit -and $result.coordinatorExitCode -eq $(if ($exit -eq 0) { 1 } else { $exit })) 'Post-validation error rewrote child outcome.'
        Assert-CiTest ($result.status -ceq 'failed-or-incomplete') 'Post-validation error accepted.'
    }
}

foreach ($kind in @('missing', 'invalid-stdout', 'missing-stdout')) {
    Test-CiCase ('incomplete-capture-still-preserves-other-observations-' + $kind) {
        $state = New-CiTestState ('capture-' + $kind); Start-CiTestBoundary $state
        $state.captureMode = $kind
        $result = Invoke-CiTestAfter $state
        Assert-CiTest ($result.status -ceq 'failed-or-incomplete' -and $result.childExitCode -eq 0 -and $result.coordinatorExitCode -eq 1) 'Incomplete capture accepted.'
        Assert-CiTest ($null -ne $result.streams.stderr.sha256 -and $null -ne $result.executable.after.sha256 -and $result.outputs.Count -eq 12) 'Available secondary observations were abandoned.'
        Assert-CiTest ($result.association -ceq 'unverified' -and $result.attribution.invocationAssociation -ceq 'unverified') 'Incomplete capture retained association.'
        if ($kind -ceq 'missing') { Assert-CiTest ($null -eq $result.streams.stdout.receivedBytes -and $null -ne $result.streams.stdout.sha256) 'Missing stream counts were invented or prefix lost.' }
    }
}

Test-CiCase 'fixed-render-parent-junction-is-rejected' {
    $state = New-CiTestState 'render-parent-alias' -DebugAlias; Start-CiTestBoundary $state
    $state.onExecute = {
        param($s)
        $target = Join-Path $s.context.root 'owned-alternate-diffs'
        [void][IO.Directory]::CreateDirectory($target)
        [void](New-Item -ItemType Junction -Path (Join-Path $s.context.renderDirectory 'diffs') -Target $target -ErrorAction Stop)
    }
    $result = Invoke-CiTestAfter $state
    Assert-CiTest ($result.reason -ceq 'ci-bitmap-render-directory-invalid' -and $result.coordinatorExitCode -eq 1 -and $result.association -ceq 'unverified') 'Redirected render output was inspected or associated.'
}

foreach ($kind in @('executable', 'normal-receipt', 'boundary', 'source')) {
    Test-CiCase ('postrun-change-' + $kind) {
        $state = New-CiTestState ('postrun-' + $kind); Start-CiTestBoundary $state
        $ciReadJson = ${function:Read-CiBitmapJson}
        $ciWriteBytes = ${function:Write-CiTestBytes}
        $ciWriteJson = ${function:Write-CiTestJson}
        $ciMutationKind = $kind
        $state.onExecute = {
            param($s)
            switch ($ciMutationKind) {
                'executable' { & $ciWriteBytes $s.context.galleryExecutable ([byte[]]@(4, 5, 6)) }
                'normal-receipt' { $s.normal.fonts.status = 'changed'; & $ciWriteJson $s.context.normalProvenancePath $s.normal }
                'boundary' { $b = (& $ciReadJson $s.context.boundaryPath).value; $b.observedAtUtc = $s.now.ToString('o'); & $ciWriteJson $s.context.boundaryPath $b }
                'source' { $s.source.dirty = $true }
            }
        }.GetNewClosure()
        $result = Invoke-CiTestAfter $state
        Assert-CiTest ($result.status -ceq 'failed-or-incomplete' -and $result.childExitCode -eq 0 -and $result.coordinatorExitCode -eq 1 -and $result.association -ceq 'unverified') 'Changed observation retained association.'
    }
}

Test-CiCase 'diagnostic-output-change-between-observations-is-rejected' {
    $state = New-CiTestState 'output-change'; Start-CiTestBoundary $state
    $state.onSource = {
        param($s)
        if ($s.executeCalls -eq 1) {
            $p = Join-Path $s.context.renderDirectory 'current/stepper.png'
            Write-CiTestBytes $p ([byte[]]@(9, 8, 7))
        }
    }
    $result = Invoke-CiTestAfter $state
    Assert-CiTest ($result.status -ceq 'failed-or-incomplete' -and $result.reason -ceq 'ci-bitmap-diagnostic-output-changed') ('Changed PNG accepted: ' + $result.reason)
}

foreach ($exit in @(0, 1)) {
    Test-CiCase ('stream-overflow-prefix-and-exit-' + $exit) {
        $state = New-CiTestState ('overflow-' + $exit); Start-CiTestBoundary $state
        $state.overflow = $true; $state.childExit = $exit
        if ($exit -eq 1) { $state.pixel = 'mismatch' }
        $result = Invoke-CiTestAfter $state
        Assert-CiTest ($result.status -ceq 'failed-or-incomplete' -and $result.childExitCode -eq $exit -and $result.coordinatorExitCode -eq 1 -and $result.association -ceq 'unverified') 'Overflow was accepted or child exit changed.'
        Assert-CiTest ($result.streams.stdout.status -ceq 'limit-exceeded' -and $result.streams.stderr.status -ceq 'limit-exceeded') 'Overflow not labeled.'
        Assert-CiTest ($result.streams.stdout.discardedBytes -eq 17 -and $result.streams.stderr.discardedBytes -eq 19) 'Overflow bytes were not drained/counted.'
        foreach ($name in @('stdout', 'stderr')) {
            $path = Join-Path $state.context.outputDirectory ("diagnostic.$name.log")
            Assert-CiTest ((Read-GalleryBitmapArtifact $path 16777216).length -eq 16777216) 'Hard per-stream spool cap changed.'
            $stream = [IO.File]::OpenRead($path)
            try {
                $first = $stream.ReadByte(); $stream.Position = $stream.Length - 1; $last = $stream.ReadByte()
                Assert-CiTest ($first -eq $(if ($name -ceq 'stdout') { 71 } else { 91 }) -and $last -eq $(if ($name -ceq 'stdout') { 72 } else { 92 })) 'Raw retained prefix changed.'
            } finally { $stream.Dispose() }
        }
    }
}

Test-CiCase 'both-stream-reads-start-before-waiting' {
    # The first fake read cannot complete until its peer read has started.
    # This models pipe backpressure without processes, native pipes, or threads.
    $pair = [pscustomobject]@{ first = $null; second = $null; starts = [Collections.Generic.List[string]]::new() }
    foreach ($name in @('first', 'second')) {
        $fake = [pscustomobject]@{ name = $name; pair = $pair; calls = 0; pending = $null }
        $fake | Add-Member -MemberType ScriptMethod -Name ReadAsync -Value {
            param($buffer, $offset, $count)
            $this.calls++
            $completion = [Threading.Tasks.TaskCompletionSource[int]]::new()
            if ($this.calls -eq 1) {
                $buffer[$offset] = if ($this.name -ceq 'first') { 11 } else { 22 }
                $this.pending = $completion; $this.pair.starts.Add($this.name)
                if ($null -ne $this.pair.first.pending -and $null -ne $this.pair.second.pending) {
                    $this.pair.first.pending.SetResult(1); $this.pair.second.pending.SetResult(1)
                }
            } else { $completion.SetResult(0) }
            return $completion.Task
        }
        $pair.$name = $fake
    }
    $out = [IO.MemoryStream]::new(); $err = [IO.MemoryStream]::new()
    try {
        $result = Receive-CiBitmapStreams $pair.first $pair.second $out $err 2
        Assert-CiTest (($pair.starts -join ',') -ceq 'first,second' -and $out.ToArray()[0] -eq 11 -and $err.ToArray()[0] -eq 22) 'Streams were not concurrently scheduled.'
        Assert-CiTest ($result.stdout.status -ceq 'complete' -and $result.stderr.status -ceq 'complete') 'Paired streams not fully drained.'
    } finally { $out.Dispose(); $err.Dispose() }
}

Test-CiCase 'stream-write-failure-keeps-draining-peer-and-counts-loss' {
    $outIn = [IO.MemoryStream]::new([byte[]]@(1, 2, 3, 4), $false)
    $errIn = [IO.MemoryStream]::new([byte[]]@(5, 6, 7), $false)
    $out = [IO.MemoryStream]::new([byte[]]@(0), $false); $err = [IO.MemoryStream]::new()
    try {
        $result = Receive-CiBitmapStreams $outIn $errIn $out $err 16
        Assert-CiTest ($result.stdout.status -ceq 'write-failed' -and $result.stdout.receivedBytes -eq 4 -and $result.stdout.discardedBytes -eq 4) 'Write failure did not retain incomplete accounting.'
        Assert-CiTest ($result.stderr.status -ceq 'complete' -and $result.stderr.receivedBytes -eq 3) 'Peer stopped draining after output failure.'
    } finally { $out.Dispose(); $err.Dispose(); $outIn.Dispose(); $errIn.Dispose() }
}

Test-CiCase 'stream-read-failure-keeps-draining-peer' {
    $outIn = [pscustomobject]@{}
    $outIn | Add-Member -MemberType ScriptMethod -Name ReadAsync -Value {
        param($buffer, $offset, $count)
        $completion = [Threading.Tasks.TaskCompletionSource[int]]::new()
        $completion.SetException([IO.IOException]::new('synthetic-read-error'))
        $completion.Task
    }
    $errIn = [IO.MemoryStream]::new([byte[]]@(5, 6, 7), $false)
    $out = [IO.MemoryStream]::new(); $err = [IO.MemoryStream]::new()
    try {
        $result = Receive-CiBitmapStreams $outIn $errIn $out $err 16
        Assert-CiTest ($result.stdout.status -ceq 'read-failed' -and $result.stderr.status -ceq 'complete' -and $result.stderr.receivedBytes -eq 3) 'Read failure abandoned the peer stream.'
    } finally { $out.Dispose(); $err.Dispose(); $errIn.Dispose() }
}

Test-CiCase 'fake-process-retains-exit-through-read-and-dispose-failures' {
    $state = New-CiTestState 'fake-process'
    [void][IO.Directory]::CreateDirectory($state.context.outputDirectory)
    $request = New-CiBitmapCommand $state.context
    $outIn = [IO.MemoryStream]::new(); $outIn.Dispose()
    $errIn = [IO.MemoryStream]::new([byte[]]@(41, 42, 43), $false)
    $process = [pscustomobject]@{ StartInfo = $null; StandardOutput = [pscustomobject]@{ BaseStream = $outIn }; StandardError = [pscustomobject]@{ BaseStream = $errIn }; ExitCode = 37; HasExited = $true; waited = $false; disposed = $false }
    $process | Add-Member -MemberType ScriptMethod -Name Start -Value { return $true }
    $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { $this.waited = $true }
    $process | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.disposed = $true; throw 'synthetic-dispose-error' }
    $factory = { $process }.GetNewClosure()
    try {
        $result = & $script:ciTestProcessImplementation -Request $request -ProcessFactory $factory
        Assert-CiTest ($result.exitCode -eq 37 -and $result.captureError -eq $true -and $result.capture.stdout.status -ceq 'read-failed' -and $result.capture.stderr.receivedBytes -eq 3) 'Known child exit was lost during capture/disposal.'
        Assert-CiTest ($process.waited -and $process.disposed -and -not $process.StartInfo.UseShellExecute -and $process.StartInfo.CreateNoWindow) 'Process lifecycle/window flags changed.'
        if ($null -ne $process.StartInfo.PSObject.Properties['ArgumentList']) {
            Assert-CiTest (($process.StartInfo.ArgumentList -join "`0") -ceq ($request.arguments -join "`0")) 'PS7 argv list changed.'
        } else {
            $quoted = [string]::Join(' ', [string[]]@($request.arguments | ForEach-Object { ConvertTo-SwiftUIAPIReviewProcessArgument $_ }))
            Assert-CiTest ($process.StartInfo.Arguments -ceq $quoted) 'PS5 argv string changed.'
        }
    } finally { $errIn.Dispose() }
}

foreach ($exit in @(0, 7, 37)) {
    Test-CiCase ('result-publication-failure-retains-child-' + $exit) {
        $state = New-CiTestState ('publication-' + $exit); Start-CiTestBoundary $state
        $state.childExit = $exit
        $state.onExecute = { param($s) [void][IO.Directory]::CreateDirectory($s.context.resultPath) }
        $result = Invoke-CiBitmapFontAttribution -Context $state.context -Phase AfterFull -FullOutcome failure `
            -ObserveSource $state.observeAdapter -PrepareEnvironment $state.prepareAdapter -Execute $state.executeAdapter -Clock $state.clockAdapter
        Assert-CiTest ($result.resultPreservation -ceq 'failed' -and $result.reason -ceq 'ci-bitmap-result-preservation-failed') 'Publication failure was not explicit.'
        Assert-CiTest ($result.childExitCode -eq $exit -and $result.coordinatorExitCode -eq $(if ($exit -eq 0) { 1 } else { $exit })) 'Publication failure replaced known child exit.'
        Assert-CiTest (Test-Path -LiteralPath $state.context.resultPath -PathType Container) 'Conflicting result path was modified.'
    }
}

Test-CiCase 'bounded-copy-detects-same-size-replacement-and-preserves-failed-copy' {
    $state = New-CiTestState 'copy-change'
    $source = Join-Path $state.context.root 'input.json'; $destination = Join-Path $state.context.root 'copy.json'
    Write-CiTestBytes $source ([Text.Encoding]::UTF8.GetBytes('{"key":1}'))
    $expected = Read-GalleryBitmapArtifact $source 524288
    Write-CiTestBytes $source ([Text.Encoding]::UTF8.GetBytes('{"key":2}'))
    $threw = $false
    try { Copy-CiBitmapReceiptNew $source $destination $expected } catch { $threw = $true }
    Assert-CiTest ($threw -and (Test-Path -LiteralPath $destination)) 'Changed source copy was accepted or erased.'
    $preserved = Read-GalleryBitmapArtifact $destination 524288
    $threw = $false
    try { Copy-CiBitmapReceiptNew $source $destination (Read-GalleryBitmapArtifact $source 524288) } catch { $threw = $true }
    Assert-CiTest ($threw -and (Read-GalleryBitmapArtifact $destination 524288).sha256 -ceq $preserved.sha256) 'Existing failed copy was overwritten.'
}

Test-CiCase 'existing-result-attempt-and-boundary-are-never-overwritten' {
    $state = New-CiTestState 'immutable-repeat'; Start-CiTestBoundary $state
    [void](Invoke-CiTestAfter $state)
    $before = Read-GalleryBitmapArtifact $state.context.resultPath 524288
    $threw = $false
    try { [void](Invoke-CiTestAfter $state) } catch { $threw = $true }
    Assert-CiTest ($threw -and $state.executeCalls -eq 1) 'Second invocation was not rejected.'
    Assert-CiTest ((Read-GalleryBitmapArtifact $state.context.resultPath 524288).sha256 -ceq $before.sha256) 'Existing result overwritten.'
    $boundaryBefore = Read-GalleryBitmapArtifact $state.context.boundaryPath 524288
    $threw = $false
    try { [void](Invoke-CiBitmapFontAttribution -Context $state.context -Phase BeforeFull -ObserveSource $state.observeAdapter -Clock $state.clockAdapter) } catch { $threw = $true }
    Assert-CiTest ($threw -and (Read-GalleryBitmapArtifact $state.context.boundaryPath 524288).sha256 -ceq $boundaryBefore.sha256) 'Existing boundary overwritten.'
}

Test-CiCase 'incomplete-existing-attempt-is-not-retried' {
    $state = New-CiTestState 'existing-attempt'; Start-CiTestBoundary $state
    $path = Join-Path $state.context.outputDirectory 'attempt.json'; Write-CiTestBytes $path ([byte[]]@(1, 2, 3))
    $threw = $false
    try { [void](Invoke-CiTestAfter $state) } catch { $threw = $true }
    Assert-CiTest ($threw -and $state.executeCalls -eq 0 -and -not (Test-Path -LiteralPath $state.context.resultPath)) 'Incomplete attempt was reused.'
    Assert-CiTest ((Read-GalleryBitmapArtifact $path 3).length -eq 3) 'Incomplete attempt was overwritten.'
}

Test-CiCase 'numeric-run-identity-path-boundary' {
    foreach ($invalid in @('', '0', '../2', '1/2', '1\2', '1:2', '1 ', '-1', '1e2', ('1' * 21))) {
        $threw = $false
        try { [void](New-CiBitmapContext $testRoot $invalid '1') } catch { $threw = $true }
        Assert-CiTest $threw 'Invalid run identifier accepted.'
    }
}

Test-CiCase 'CLI-context-requires-Windows-GitHub-workspace-and-run' {
    $names = @('GITHUB_ACTIONS', 'RUNNER_OS', 'GITHUB_WORKSPACE', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT')
    $saved = @{}
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        $env:GITHUB_ACTIONS = 'true'; $env:RUNNER_OS = 'Windows'
        $env:GITHUB_WORKSPACE = Split-Path -Parent $PSScriptRoot; $env:GITHUB_RUN_ID = '123'; $env:GITHUB_RUN_ATTEMPT = '1'
        $context = Get-CiBitmapContext
        Assert-CiTest ($context.runID -ceq '123') 'Expected CLI environment rejected.'
        foreach ($case in @(@('GITHUB_ACTIONS', 'false'), @('RUNNER_OS', 'Linux'), @('GITHUB_WORKSPACE', $testRoot), @('GITHUB_RUN_ID', '../1'))) {
            $name = $case[0]; $before = [Environment]::GetEnvironmentVariable($name, 'Process')
            [Environment]::SetEnvironmentVariable($name, $case[1], 'Process')
            $threw = $false
            try { [void](Get-CiBitmapContext) } catch { $threw = $true }
            Assert-CiTest $threw 'Invalid CLI environment accepted.'
            [Environment]::SetEnvironmentVariable($name, $before, 'Process')
        }
    } finally { foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') } }
}

Test-CiCase 'PS5-Windows-argv-quoting-preserves-literals' {
    Assert-CiTest ((ConvertTo-SwiftUIAPIReviewProcessArgument '') -ceq '""') 'Empty argv quoted incorrectly.'
    Assert-CiTest ((ConvertTo-SwiftUIAPIReviewProcessArgument 'C:\path with spaces\') -ceq '"C:\path with spaces\\"') 'Trailing backslash quoted incorrectly.'
    Assert-CiTest ((ConvertTo-SwiftUIAPIReviewProcessArgument 'literal"quote') -ceq '"literal\"quote"') 'Embedded quote escaped incorrectly.'
    Assert-CiTest ((ConvertTo-SwiftUIAPIReviewProcessArgument '$x; & (text)') -ceq '"$x; & (text)"') 'Literal metacharacters changed.'
}

Test-CiCase 'workflow-preserves-Full-command-failure-and-upload-scope' {
    $workflow = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) '.github/workflows/windows-ci.yml')).Replace("`r`n", "`n")
    $expectedFull = @'
      - name: Run full agent checks
        id: full_checks
        shell: pwsh
        run: |
          # agent-check -Full runs contracts, full swift test, demo build,
          # scene + frame-fallback screenshots, and the gallery regression
          # gate (gallery-compare.ps1) serially.
          powershell -NoProfile -ExecutionPolicy Bypass `
            -File scripts/agent-check.ps1 -Full
'@
    Assert-CiTest ($workflow.Contains($expectedFull.Replace("`r`n", "`n"))) 'Original Full command or failure policy changed.'
    Assert-CiTest ($workflow.Contains("      - name: Record bitmap font diagnostic boundary`n        continue-on-error: true")) 'Boundary failure can suppress Full.'
    $condition = 'if: ${{ !cancelled() && (steps.full_checks.outcome == ''success'' || steps.full_checks.outcome == ''failure'') }}'
    Assert-CiTest ($workflow.Contains($condition)) 'Diagnostic condition changed.'
    foreach ($outcome in @('success', 'failure', 'skipped', 'cancelled')) {
        foreach ($cancelled in @($false, $true)) {
            $runs = -not $cancelled -and ($outcome -ceq 'success' -or $outcome -ceq 'failure')
            Assert-CiTest ($runs -eq (-not $cancelled -and $outcome -cin @('success', 'failure'))) 'Condition truth table changed.'
        }
    }
    $screenshot = $workflow.IndexOf('      - name: Upload screenshot artifacts', $workflow.IndexOf('      - name: Run full agent checks'))
    $diagnostic = $workflow.IndexOf('      - name: Collect bitmap font attribution (diagnostic only)')
    $upload = $workflow.IndexOf('      - name: Upload gallery compare artifacts')
    Assert-CiTest ($screenshot -gt 0 -and $screenshot -lt $diagnostic -and $diagnostic -lt $upload) 'Primary screenshot upload or diagnostic ordering changed.'
    foreach ($line in @('runs-on: windows-2022', 'timeout-minutes: 150', 'uses: compnerd/gha-setup-swift@v0.4.0', 'cache: true',
        'timeout-minutes: 10', 'name: windows-gallery-compare', 'retention-days: 14', 'if-no-files-found: warn',
        'artifacts/gallery-compare/report.txt', 'artifacts/gallery-compare/report.json', 'artifacts/gallery-compare/report.html',
        'artifacts/gallery-compare/provenance*.json', 'artifacts/gallery-compare/current/*.png', 'artifacts/gallery-compare/diffs/*.png',
        'artifacts/gallery-compare/bitmap-font-attribution-ci/**')) { Assert-CiTest ($workflow.Contains($line)) ('Required workflow setting missing: ' + $line) }
    $fullBlock = $workflow.Substring($workflow.IndexOf('      - name: Run full agent checks'), $screenshot - $workflow.IndexOf('      - name: Run full agent checks'))
    Assert-CiTest (-not $fullBlock.Contains('continue-on-error')) 'Full failure made advisory.'
}

Test-CiCase 'closure-bound-assertion-rejects-wrong-root' {
    $state = New-CiTestState 'closure-assertion'
    $caught = $null
    try { & $state.observeAdapter (Join-Path $state.context.root 'wrong-root') } catch { $caught = $_.Exception.Message }
    Assert-CiTest ($caught -ceq 'Unexpected source root.') 'The captured adapter assertion did not retain its original failure.'
    Assert-CiTest ($state.sourceCalls -eq 1 -and $state.prepareCalls -eq 0 -and $state.executeCalls -eq 0) 'The failing assertion allowed later adapters to run.'
}

$failed = @($script:ciTestResults | Where-Object { $_.status -ceq 'fail' }).Count
$summary = [pscustomobject]@{
    schemaVersion = 1; kind = 'synthetic-ci-bitmap-font-tests'; powershellVersion = $PSVersionTable.PSVersion.ToString()
    status = if ($failed -eq 0) { 'pass' } else { 'fail' }; total = $script:ciTestResults.Count; failed = $failed
    nativeExecution = $false; swiftPM = $false; fontProbes = $false; rendererExecution = $false; hostedCI = $false
    qualification = 'unqualified'; tests = @($script:ciTestResults.ToArray())
}
Write-CiBitmapJsonNew (Join-Path $testRoot 'test-results.json') $summary
Write-Host ("Synthetic CI bitmap tests: $($summary.total - $failed)/$($summary.total) passed. Evidence: $testRoot")
if ($failed -gt 0) { exit 1 }
exit 0
