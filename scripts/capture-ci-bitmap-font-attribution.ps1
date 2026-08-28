<#
.SYNOPSIS
    Preserves an advisory two-fixture font diagnostic after the normal CI gate.
.DESCRIPTION
    The CLI accepts only the phase and the completed Full outcome. It derives
    all paths from this checkout and numeric GitHub run identifiers. Dot-source
    for synthetic tests; doing so does not observe Git, prepare Swift, or launch
    anything. Test adapters are function parameters, never CLI bypass switches.
#>
param(
    [ValidateSet('', 'BeforeFull', 'AfterFull')][string]$Phase = '',
    [ValidateSet('', 'success', 'failure')][string]$FullOutcome = ''
)

. (Join-Path $PSScriptRoot 'gallery-bitmap-font-attribution.ps1')
# Reuse the bounded read-only Git process and Windows argv quoting helpers.
# These common files define functions only; no native adapter is initialized.
. (Join-Path $PSScriptRoot 'swiftui-api-review-common.ps1')

$script:ciBitmapMetadataLimit = 524288
$script:ciBitmapExecutableLimit = 268435456
$script:ciBitmapLogLimit = 16777216
$script:ciBitmapFixtures = @('symbol-palette', 'stepper')

function Assert-CiBitmapPathEqual {
    param($Actual, [string]$Expected)
    if ($Actual -isnot [string] -or $Actual.Length -gt 4096 -or
        -not [IO.Path]::IsPathRooted($Actual) -or
        -not [IO.Path]::GetFullPath($Actual).Equals([IO.Path]::GetFullPath($Expected), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ci-bitmap-path-mismatch'
    }
}

function New-CiBitmapContext {
    param([string]$RepositoryRoot, [string]$RunID, [string]$RunAttempt)
    foreach ($value in @($RunID, $RunAttempt)) {
        if ($value -cnotmatch '\A[1-9][0-9]{0,19}\z') { throw 'ci-bitmap-invalid-run-identity' }
    }
    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([char[]]@('/', '\'))
    if (-not [IO.Path]::IsPathRooted($RepositoryRoot) -or $root -cnotmatch '\A[A-Za-z]:[\\/]') { throw 'ci-bitmap-invalid-root' }
    $owned = Join-Path $root ('artifacts/gallery-compare/bitmap-font-attribution-ci/' + $RunID + '-' + $RunAttempt)
    [pscustomobject]@{
        root = $root; runID = $RunID; runAttempt = $RunAttempt; outputDirectory = $owned
        boundaryPath = Join-Path $owned 'boundary.json'; resultPath = Join-Path $owned 'result.json'
        normalProvenancePath = Join-Path $root 'artifacts/gallery-compare/provenance.json'
        copiedProvenancePath = Join-Path $owned 'normal-gallery-provenance.json'
        renderDirectory = Join-Path $owned 'render'
        galleryExecutable = Join-Path $root '.build/debug/swift-windowsui-gallery.exe'
        wrapper = Join-Path $root 'scripts/gallery-compare.ps1'
        powershell = Join-Path ([Environment]::GetFolderPath('Windows')) 'System32/WindowsPowerShell/v1.0/powershell.exe'
    }
}

function Get-CiBitmapContext {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows') { throw 'ci-bitmap-windows-ci-required' }
    $root = Split-Path -Parent $PSScriptRoot
    Assert-CiBitmapPathEqual $env:GITHUB_WORKSPACE $root
    New-CiBitmapContext -RepositoryRoot $root -RunID $env:GITHUB_RUN_ID -RunAttempt $env:GITHUB_RUN_ATTEMPT
}

function Assert-CiBitmapOwnedDirectories {
    param($Context)
    # Check existing directory components, not the legitimate .build/debug
    # directory alias. This is not a pinned-handle defense against replacement.
    $path = $Context.root
    foreach ($component in @('', 'artifacts', 'gallery-compare', 'bitmap-font-attribution-ci', ($Context.runID + '-' + $Context.runAttempt))) {
        if ($component.Length -gt 0) { $path = Join-Path $path $component }
        if (Test-Path -LiteralPath $path) {
            $info = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if (-not $info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'ci-bitmap-output-directory-invalid' }
        }
    }
}

function Write-CiBitmapJsonNew {
    param([string]$Path, $Value)
    $json = ConvertTo-Json -InputObject $Value -Depth 24 -WarningAction Stop
    $bytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($json + "`n")
    if ($bytes.Length -gt $script:ciBitmapMetadataLimit) { throw 'ci-bitmap-result-size-limit' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush() } finally { $stream.Dispose() }
}

function Read-CiBitmapJson {
    param([string]$Path)
    $artifact = Read-GalleryBitmapArtifact -Path $Path -MaximumBytes $script:ciBitmapMetadataLimit -Json
    Assert-GalleryBitmapJsonLexicalBounds -Json $artifact.text
    # PowerShell 7.5 otherwise converts ISO JSON strings to DateTime objects.
    $options = @{ InputObject = $artifact.text; ErrorAction = 'Stop' }
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $options.DateKind = 'String' }
    $value = ConvertFrom-Json @options
    if ($value -isnot [pscustomobject]) { throw 'ci-bitmap-json-object-required' }
    [pscustomobject]@{ artifact = $artifact; value = $value }
}

function Copy-CiBitmapReceiptNew {
    param([string]$Source, [string]$Destination, $Expected)
    # Copy original bytes, including a BOM if present. Both reads are bounded;
    # reopening a file with ReadAllBytes after a size check would not be bounded.
    $inputStream = $null; $outputStream = $null
    try {
        $inputStream = [IO.FileStream]::new($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read, 1)
        if ($inputStream.Length -ne $Expected.length -or $inputStream.Length -gt $script:ciBitmapMetadataLimit) { throw 'ci-bitmap-receipt-changed' }
        $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buffer = [byte[]]::new(8192); [long]$remaining = $Expected.length
        while ($remaining -gt 0) {
            $read = $inputStream.Read($buffer, 0, [int][math]::Min($remaining, $buffer.Length))
            if ($read -le 0) { throw 'ci-bitmap-receipt-changed' }
            $outputStream.Write($buffer, 0, $read); $remaining -= $read
        }
        if ($inputStream.Length -ne $Expected.length) { throw 'ci-bitmap-receipt-changed' }
    } finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $inputStream) { $inputStream.Dispose() }
    }
    foreach ($path in @($Source, $Destination)) {
        $actual = Read-GalleryBitmapArtifact -Path $path -MaximumBytes $script:ciBitmapMetadataLimit
        if ($actual.sha256 -cne $Expected.sha256 -or $actual.length -ne $Expected.length) { throw 'ci-bitmap-receipt-changed' }
    }
}

function Get-CiBitmapSource {
    param([string]$RepositoryRoot)
    foreach ($name in @('GIT_DIR', 'GIT_COMMON_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY',
        'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_SHALLOW_FILE', 'GIT_CONFIG', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS',
        'GIT_CONFIG_SYSTEM', 'GIT_CONFIG_GLOBAL', 'GIT_NAMESPACE', 'GIT_REPLACE_REF_BASE')) {
        if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) { throw 'ci-bitmap-git-override' }
    }
    $git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $options = @{ Executable = $git; RepositoryRoot = $RepositoryRoot; MaximumOutputBytes = 1048576; TimeoutMilliseconds = 30000 }
    $root = (Invoke-SwiftUIAPIReviewGit @options -Arguments @('rev-parse', '--show-toplevel')).text.TrimEnd([char[]]"`r`n")
    Assert-CiBitmapPathEqual $root $RepositoryRoot
    $revision = (Invoke-SwiftUIAPIReviewGit @options -Arguments @('rev-parse', '--verify', 'HEAD')).text.Trim()
    if ($revision -cnotmatch '\A[0-9a-f]{40}\z') { throw 'ci-bitmap-invalid-source-revision' }
    $status = (Invoke-SwiftUIAPIReviewGit @options -Arguments @('status', '--porcelain=v1', '-z', '--untracked-files=normal', '--ignore-submodules=none')).text
    [pscustomobject]@{ root = $RepositoryRoot; status = 'observed-checkout-only'; revision = $revision; dirty = ($status.Length -ne 0); executableBuildRevision = $null }
}

function Assert-CiBitmapSource {
    param($Source, $Context, [AllowNull()][string]$Revision, [switch]$Gallery)
    $keys = if ($Gallery) { @('root', 'status', 'revision', 'changes', 'error', 'executableBuildRevision') } else { @('root', 'status', 'revision', 'dirty', 'executableBuildRevision') }
    Assert-GalleryBitmapObject $Source $keys $keys
    Assert-CiBitmapPathEqual $Source.root $Context.root
    Assert-GalleryBitmapEnum $Source.status @('observed-checkout-only')
    if ($Source.revision -isnot [string] -or
        $Source.revision -cnotmatch '\A[0-9a-f]{40}\z' -or $null -ne $Source.executableBuildRevision) { throw 'ci-bitmap-source-invalid' }
    if ($Gallery) {
        if ($Source.changes -isnot [array] -or $Source.changes.Count -ne 0 -or $null -ne $Source.error) { throw 'ci-bitmap-source-dirty-or-unavailable' }
    } elseif ($Source.dirty -isnot [bool] -or $Source.dirty) { throw 'ci-bitmap-source-dirty-or-unavailable' }
    if (-not [string]::IsNullOrEmpty($Revision) -and $Source.revision -cne $Revision) { throw 'ci-bitmap-source-changed' }
}

function ConvertTo-CiBitmapTime {
    param($Value)
    if ($Value -is [datetime]) { return [DateTimeOffset]$Value.ToUniversalTime() }
    if ($Value -isnot [string] -or $Value -cnotmatch '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,7})?(?:Z|[+-][0-9]{2}:[0-9]{2})\z') { throw 'ci-bitmap-invalid-time' }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) { throw 'ci-bitmap-invalid-time' }
    $parsed.ToUniversalTime()
}

function Assert-CiBitmapFingerprint {
    param($Fingerprint, $Context, [AllowNull()]$Expected)
    $keys = @('path', 'status', 'sha256', 'length', 'lastWriteTimeUtc', 'fileVersion', 'error')
    Assert-GalleryBitmapObject $Fingerprint $keys @('path', 'status', 'sha256', 'length')
    Assert-CiBitmapPathEqual $Fingerprint.path $Context.galleryExecutable
    Assert-GalleryBitmapEnum $Fingerprint.status @('observed')
    if ($Fingerprint.sha256 -isnot [string] -or $Fingerprint.sha256 -cnotmatch '\A[0-9a-f]{64}\z') { throw 'ci-bitmap-executable-unobserved' }
    Assert-GalleryBitmapInteger $Fingerprint.length $script:ciBitmapExecutableLimit 1
    if ($null -ne $Expected -and ($Expected.sha256 -cne $Fingerprint.sha256 -or $Expected.length -ne $Fingerprint.length)) { throw 'ci-bitmap-executable-changed' }
}

function Assert-CiBitmapFixtures {
    param($Value)
    Assert-GalleryBitmapArray $Value 2
    if ($Value.Count -ne 2 -or @($Value | Select-Object -Unique).Count -ne 2) { throw 'ci-bitmap-fixture-selection-invalid' }
    foreach ($fixture in $Value) { Assert-GalleryBitmapEnum $fixture $script:ciBitmapFixtures }
}

function Assert-CiBitmapNormalReceipt {
    param($Receipt, $Boundary, $Context, [DateTimeOffset]$Now, $Executable)
    $keys = @('schemaVersion', 'invocationID', 'capturedAt', 'stage', 'qualification', 'renderer', 'fonts', 'os', 'process', 'runner',
        'directWriteLibrary', 'directWriteLibraryObservation', 'source', 'executable', 'executableAssociation', 'build', 'render')
    Assert-GalleryBitmapObject $Receipt $keys $keys
    Assert-GalleryBitmapInteger $Receipt.schemaVersion 1 1
    if ($Receipt.invocationID -isnot [string] -or $Receipt.invocationID -cnotmatch '\A[0-9a-f]{32}\z') { throw 'ci-bitmap-receipt-invalid' }
    $captured = ConvertTo-CiBitmapTime $Receipt.capturedAt
    if ($captured -lt (ConvertTo-CiBitmapTime $Boundary.observedAtUtc) -or $captured -gt $Now) { throw 'ci-bitmap-receipt-not-fresh' }
    Assert-CiBitmapSource $Receipt.source $Context $Boundary.source.revision -Gallery
    Assert-GalleryBitmapObject $Receipt.qualification @('status', 'acceptedBaselineProfile', 'reason') @('status', 'acceptedBaselineProfile')
    Assert-GalleryBitmapEnum $Receipt.qualification.status @('unqualified')
    if ($null -ne $Receipt.qualification.acceptedBaselineProfile) { throw 'ci-bitmap-receipt-invalid' }
    Assert-GalleryBitmapObject $Receipt.build @('status', 'exitCode', 'executableAfter') @('status', 'exitCode', 'executableAfter')
    if ($Receipt.build.status -isnot [string] -or $Receipt.build.status -cne 'succeeded') { throw 'ci-bitmap-successful-build-required' }
    Assert-GalleryBitmapInteger $Receipt.build.exitCode 0 0
    Assert-CiBitmapFingerprint $Receipt.build.executableAfter $Context $Executable
    # A pre-render observation is additional evidence, never a replacement for
    # the fresh successful build receipt. No mtime/PE timestamp freshness test.
    if ($null -ne $Receipt.executable) { Assert-CiBitmapFingerprint $Receipt.executable $Context $Executable }
    Assert-GalleryBitmapObject $Receipt.render @('status', 'exitCode', 'requestedEntries', 'outputDirectory', 'imageAssociation', 'executableAfter', 'executableUnchanged') @('status', 'exitCode', 'imageAssociation')
    Assert-GalleryBitmapEnum $Receipt.render.status @('not-requested', 'pending', 'running', 'succeeded', 'failed', 'skipped')
    if ($null -ne $Receipt.render.exitCode) { Assert-GalleryBitmapInteger $Receipt.render.exitCode ([int]::MaxValue) ([int]::MinValue) }
    if ($Receipt.render.imageAssociation -isnot [string] -or $Receipt.render.imageAssociation.Length -gt 256) { throw 'ci-bitmap-receipt-invalid' }
}

function New-CiBitmapCommand {
    param($Context)
    [pscustomobject]@{
        executable = $Context.powershell; workingDirectory = $Context.root
        arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Context.wrapper,
            '-BitmapFontAttribution', '-SkipBuild', '-Entries', 'symbol-palette,stepper',
            '-GalleryExe', $Context.galleryExecutable, '-WorkDir', $Context.renderDirectory)
        stdoutPath = Join-Path $Context.outputDirectory 'diagnostic.stdout.log'
        stderrPath = Join-Path $Context.outputDirectory 'diagnostic.stderr.log'
        maximumStreamBytes = $script:ciBitmapLogLimit
    }
}

function Receive-CiBitmapStreams {
    param($StandardOutput, $StandardError, [IO.Stream]$OutputStream, [IO.Stream]$ErrorStream, [long]$MaximumBytes = 16777216)
    if ($MaximumBytes -lt 1 -or $MaximumBytes -gt $script:ciBitmapLogLimit) { throw 'ci-bitmap-invalid-stream-budget' }
    $channels = @(
        [pscustomobject]@{ input = $StandardOutput; output = $OutputStream; buffer = [byte[]]::new(8192); task = $null; received = [long]0; retained = [long]0; writeFailed = $false; readFailed = $false },
        [pscustomobject]@{ input = $StandardError; output = $ErrorStream; buffer = [byte[]]::new(8192); task = $null; received = [long]0; retained = [long]0; writeFailed = $false; readFailed = $false }
    )
    # Start both reads before waiting on either. Even after reaching the spool
    # cap, drain and count every subsequent byte so a full pipe cannot deadlock.
    foreach ($channel in $channels) {
        try { $channel.task = $channel.input.ReadAsync($channel.buffer, 0, $channel.buffer.Length) }
        catch { $channel.readFailed = $true; $channel.task = $null }
    }
    while ($null -ne $channels[0].task -or $null -ne $channels[1].task) {
        [Threading.Tasks.Task[]]$pending = @($channels | Where-Object { $null -ne $_.task } | ForEach-Object { $_.task })
        [void][Threading.Tasks.Task]::WaitAny($pending)
        foreach ($channel in $channels) {
            if ($null -eq $channel.task -or -not $channel.task.IsCompleted) { continue }
            try {
                $count = $channel.task.GetAwaiter().GetResult()
                if ($count -lt 0 -or $count -gt $channel.buffer.Length) { throw 'ci-bitmap-stream-read-invalid' }
            } catch { $channel.readFailed = $true; $channel.task = $null; continue }
            if ($count -eq 0) { $channel.task = $null; continue }
            $channel.received += $count
            $keep = [int][math]::Min($count, $MaximumBytes - $channel.retained)
            if ($keep -gt 0 -and -not $channel.writeFailed) {
                try { $channel.output.Write($channel.buffer, 0, $keep); $channel.retained += $keep }
                catch { $channel.writeFailed = $true }
            }
            try { $channel.task = $channel.input.ReadAsync($channel.buffer, 0, $channel.buffer.Length) }
            catch { $channel.readFailed = $true; $channel.task = $null }
        }
    }
    $observations = @(foreach ($channel in $channels) {
        try { $channel.output.Flush() } catch { $channel.writeFailed = $true }
        [pscustomobject]@{
            status = if ($channel.readFailed) { 'read-failed' } elseif ($channel.writeFailed) { 'write-failed' } elseif ($channel.received -gt $MaximumBytes) { 'limit-exceeded' } else { 'complete' }
            receivedBytes = $channel.received; retainedBytes = $channel.retained
            discardedBytes = $channel.received - $channel.retained; maximumBytes = $MaximumBytes
        }
    })
    [pscustomobject]@{ stdout = $observations[0]; stderr = $observations[1] }
}

function Invoke-CiBitmapProcess {
    param($Request, [scriptblock]$ProcessFactory = { [Diagnostics.Process]::new() })
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Request.executable; $info.WorkingDirectory = $Request.workingDirectory
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    if ($null -ne $info.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $Request.arguments) { $info.ArgumentList.Add($argument) }
    } else { $info.Arguments = [string]::Join(' ', [string[]]@($Request.arguments | ForEach-Object { ConvertTo-SwiftUIAPIReviewProcessArgument $_ })) }
    $process = & $ProcessFactory; $process.StartInfo = $info
    $stdout = $null; $stderr = $null; $capture = $null; $knownExit = $null; $started = $false; $captureError = $false
    try {
        $stdout = [IO.File]::Open($Request.stdoutPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $stderr = [IO.File]::Open($Request.stderrPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $started = $process.Start()
        if (-not $started) { throw 'ci-bitmap-process-start-failed' }
        $capture = Receive-CiBitmapStreams $process.StandardOutput.BaseStream $process.StandardError.BaseStream $stdout $stderr $Request.maximumStreamBytes
        $process.WaitForExit()
        $knownExit = $process.ExitCode
    } catch { $captureError = $true } finally {
        # A capture/disposal fault must not discard an exit already observable.
        if ($started -and $null -eq $knownExit) {
            try { if ($process.HasExited) { $knownExit = $process.ExitCode } } catch { $captureError = $true }
        }
        if ($null -ne $stdout) { try { $stdout.Dispose() } catch { $captureError = $true } }
        if ($null -ne $stderr) { try { $stderr.Dispose() } catch { $captureError = $true } }
        # No process-tree killer. An Actions timeout may leave only attempt.json
        # and prefixes; neither is reported as a completed invocation.
        try { $process.Dispose() } catch { $captureError = $true }
    }
    [pscustomobject]@{ exitCode = $knownExit; capture = $capture; captureError = $captureError }
}

function Get-CiBitmapStreamObservations {
    param($Context, $Capture)
    $streams = [ordered]@{}
    foreach ($name in @('stdout', 'stderr')) {
        $record = [ordered]@{
            status = 'invalid-capture-metadata'; receivedBytes = $null; retainedBytes = $null; discardedBytes = $null
            maximumBytes = $script:ciBitmapLogLimit; sha256 = $null; fileBytes = $null
        }
        try {
            $channel = $Capture.$name
            $keys = @('status', 'receivedBytes', 'retainedBytes', 'discardedBytes', 'maximumBytes')
            Assert-GalleryBitmapObject $channel $keys $keys
            Assert-GalleryBitmapEnum $channel.status @('complete', 'limit-exceeded', 'write-failed', 'read-failed')
            Assert-GalleryBitmapInteger $channel.receivedBytes ([long]::MaxValue) 0
            Assert-GalleryBitmapInteger $channel.retainedBytes $script:ciBitmapLogLimit 0
            Assert-GalleryBitmapInteger $channel.discardedBytes ([long]::MaxValue) 0
            Assert-GalleryBitmapInteger $channel.maximumBytes $script:ciBitmapLogLimit $script:ciBitmapLogLimit
            if ($channel.receivedBytes - $channel.retainedBytes -ne $channel.discardedBytes -or
                ($channel.status -ceq 'complete' -and $channel.discardedBytes -ne 0)) { throw 'ci-bitmap-stream-capture-incomplete' }
            foreach ($key in $keys) { $record[$key] = $channel.$key }
        } catch { $record.status = 'invalid-capture-metadata' }
        # Independently hash both available prefixes even if one channel's
        # metadata/read failed. Do not infer missing received/discarded counts.
        try {
            $log = Read-GalleryBitmapArtifact (Join-Path $Context.outputDirectory ("diagnostic.$name.log")) $script:ciBitmapLogLimit
            $record.sha256 = $log.sha256; $record.fileBytes = $log.length
            if ($record.status -ceq 'write-failed' -and $null -ne $record.receivedBytes -and $log.length -le $record.receivedBytes) {
                # A failed Write can leave a partial prefix. Observe its actual
                # length rather than claim the entire failed write was lost.
                $record.retainedBytes = $log.length; $record.discardedBytes = $record.receivedBytes - $log.length
            } elseif ($record.status -ceq 'complete' -and $record.retainedBytes -ne $log.length) { $record.status = 'incomplete' }
        } catch { $record.status = 'log-unavailable' }
        $streams[$name] = [pscustomobject]$record
    }
    [pscustomobject]$streams
}

function Get-CiBitmapOutputObservations {
    param($Context)
    foreach ($relative in @('', 'current', 'diffs', 'bitmap-font-attribution', 'bitmap-font-attribution/native')) {
        $directory = if ($relative.Length -eq 0) { $Context.renderDirectory } else { Join-Path $Context.renderDirectory $relative }
        if (Test-Path -LiteralPath $directory) {
            $info = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
            if (-not $info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'ci-bitmap-render-directory-invalid' }
        }
    }
    $files = @(
        @('provenance.json', 524288), @('provenance-initial.json', 524288),
        @('report.json', 524288), @('report.txt', 1048576), @('report.html', 16777216),
        @('bitmap-font-attribution/report.json', 524288)
    )
    foreach ($fixture in $script:ciBitmapFixtures) {
        $files += ,@("current/$fixture.png", 33554432)
        $files += ,@("diffs/$fixture-diff.png", 33554432)
        $files += ,@("bitmap-font-attribution/native/$fixture.native-font-attribution.json", 524288)
    }
    @(foreach ($file in $files) {
        $path = Join-Path $Context.renderDirectory $file[0]
        $record = [ordered]@{ path = [string]$file[0]; status = 'missing'; sha256 = $null; length = $null; maximumBytes = [long]$file[1] }
        if (Test-Path -LiteralPath $path) {
            try {
                $observed = Read-GalleryBitmapArtifact $path $file[1]
                if ($observed.length -le 0) { throw 'ci-bitmap-empty-output' }
                $record.status = 'observed'; $record.sha256 = $observed.sha256; $record.length = $observed.length
            } catch { $record.status = 'rejected' }
        }
        [pscustomobject]$record
    })
}

function Assert-CiBitmapDiagnosticProfile {
    param($Profile, $Context, [string]$Revision, $Executable, [DateTimeOffset]$StartedAt, [DateTimeOffset]$Now)
    Assert-GalleryBitmapInteger $Profile.schemaVersion 1 1
    if ($Profile.invocationID -isnot [string] -or $Profile.invocationID -cnotmatch '\A[0-9a-f]{32}\z') { throw 'ci-bitmap-diagnostic-profile-invalid' }
    Assert-CiBitmapSource $Profile.source $Context $Revision -Gallery
    $captured = ConvertTo-CiBitmapTime $Profile.capturedAt
    if ($captured -lt $StartedAt -or $captured -gt $Now) { throw 'ci-bitmap-diagnostic-profile-stale' }
    Assert-GalleryBitmapEnum $Profile.stage @('render-completed')
    Assert-GalleryBitmapEnum $Profile.build.status @('skipped')
    Assert-GalleryBitmapEnum $Profile.render.status @('succeeded')
    if ($null -ne $Profile.build.exitCode -or $null -ne $Profile.build.executableAfter -or
        $Profile.render.executableUnchanged -isnot [bool] -or -not $Profile.render.executableUnchanged) { throw 'ci-bitmap-render-incomplete' }
    Assert-GalleryBitmapInteger $Profile.render.exitCode 0 0
    Assert-CiBitmapFixtures $Profile.render.requestedEntries
    Assert-CiBitmapPathEqual $Profile.render.outputDirectory (Join-Path $Context.renderDirectory 'current')
    Assert-CiBitmapFingerprint $Profile.executable $Context $Executable
    Assert-CiBitmapFingerprint $Profile.render.executableAfter $Context $Executable
    Assert-GalleryBitmapEnum $Profile.executableAssociation @('preexisting-file-invoked-without-build')
    Assert-GalleryBitmapEnum $Profile.qualification.status @('unqualified')
    if ($null -ne $Profile.qualification.acceptedBaselineProfile) { throw 'ci-bitmap-diagnostic-profile-invalid' }
}

function Get-CiBitmapPixelStatus {
    param($Report, $Profile, $Context, [int]$ChildExitCode, $Outputs)
    $keys = @('schemaVersion', 'generatedAt', 'status', 'fontProvenance', 'selection', 'thresholds', 'summary', 'entries', 'bitmapFontAttribution')
    Assert-GalleryBitmapObject $Report $keys $keys
    Assert-GalleryBitmapInteger $Report.schemaVersion 2 2
    if ((Get-GalleryBitmapJsonDigest $Report.fontProvenance) -cne (Get-GalleryBitmapJsonDigest $Profile)) { throw 'ci-bitmap-comparison-profile-mismatch' }
    Assert-CiBitmapFixtures $Report.selection.requestedIds
    Assert-GalleryBitmapInteger $Report.selection.selectedCount 2 2
    Assert-GalleryBitmapEnum $Report.selection.appearance @('all')
    Assert-GalleryBitmapEnum $Report.selection.tier @('all')
    if ($Report.selection.pattern -isnot [string] -or $Report.selection.pattern.Length -ne 0) { throw 'ci-bitmap-comparison-selection-invalid' }
    if (($Report.thresholds.maxChangedPercent -isnot [double] -and $Report.thresholds.maxChangedPercent -isnot [decimal]) -or
        $Report.thresholds.maxChangedPercent -ne 0.5) { throw 'ci-bitmap-comparison-thresholds-invalid' }
    Assert-GalleryBitmapInteger $Report.thresholds.channelTolerance 8 8
    Assert-GalleryBitmapInteger $Report.thresholds.maxChannelDelta 64 64
    Assert-GalleryBitmapInteger $Report.summary.total 2 2
    Assert-GalleryBitmapInteger $Report.summary.failing 2 0
    Assert-GalleryBitmapInteger $Report.summary.passing 2 0
    if ($Report.summary.passing + $Report.summary.failing -ne 2) { throw 'ci-bitmap-comparison-incomplete' }
    Assert-GalleryBitmapArray $Report.entries 2
    Assert-CiBitmapFixtures @($Report.entries | ForEach-Object { $_.id })
    $failures = 0
    foreach ($entry in $Report.entries) {
        Assert-GalleryBitmapEnum $entry.status @('pass', 'fail')
        if (($entry.changedPercent -isnot [double] -and $entry.changedPercent -isnot [decimal] -and $entry.changedPercent -isnot [int] -and $entry.changedPercent -isnot [long]) -or
            [double]::IsNaN([double]$entry.changedPercent) -or $entry.changedPercent -lt 0 -or $entry.changedPercent -gt 100) { throw 'ci-bitmap-comparison-incomplete' }
        Assert-GalleryBitmapInteger $entry.maxChannelDelta 255 0
        $breach = $entry.changedPercent -gt 0.5 -or $entry.maxChannelDelta -gt 64
        # Missing baseline/render failures have zero deltas, not pixel breaches.
        if (($entry.status -ceq 'fail') -ne $breach) { throw 'ci-bitmap-comparison-incomplete' }
        if ($breach) { $failures++ }
        $pngPath = 'current/' + $entry.id + '.png'
        if ($entry.images.current -isnot [string] -or $entry.images.current -cne $pngPath -or @($Outputs | Where-Object { $_.path -ceq $pngPath -and $_.status -ceq 'observed' }).Count -ne 1) { throw 'ci-bitmap-comparison-png-unavailable' }
    }
    Assert-GalleryBitmapEnum $Report.status @('pass', 'fail')
    if ($Report.summary.failing -ne $failures -or $Report.status -cne $(if ($failures -gt 0) { 'fail' } else { 'pass' }) -or
        $ChildExitCode -ne $(if ($failures -gt 0) { 1 } else { 0 })) { throw 'ci-bitmap-comparison-exit-mismatch' }
    Assert-GalleryBitmapEnum $Report.bitmapFontAttribution.path @('bitmap-font-attribution/report.json')
    Assert-GalleryBitmapEnum $Report.bitmapFontAttribution.status @('observed', 'partial', 'unavailable')
    Assert-GalleryBitmapEnum $Report.bitmapFontAttribution.qualification @('unqualified')
    Assert-GalleryBitmapEnum $Report.bitmapFontAttribution.pixelGate @('unchanged')
    if ($failures -gt 0) { 'mismatches' } else { 'pass' }
}

function Get-CiBitmapAttributionStatus {
    param($Context, $ProfileObservation, $Executable, $Outputs)
    $path = Join-Path $Context.renderDirectory 'bitmap-font-attribution/report.json'
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]@{ status = 'unavailable'; invocationAssociation = 'unverified'; qualification = 'unqualified' } }
    $read = Read-CiBitmapJson $path; $report = $read.value
    Assert-GalleryBitmapInteger $report.schemaVersion 1 1
    Assert-GalleryBitmapEnum $report.status @('observed', 'partial')
    Assert-GalleryBitmapEnum $report.invocationAssociation @('linked-to-completed-invocation', 'unverified-invocation')
    Assert-GalleryBitmapEnum $report.kind @('gallery-bitmap-font-attribution')
    Assert-GalleryBitmapEnum $report.qualification.status @('unqualified')
    Assert-GalleryBitmapEnum $report.qualification.pixelGate @('unchanged')
    Assert-GalleryBitmapEnum $report.coverage.scope @('bitmap-icons')
    if ($null -ne $report.qualification.acceptedBaselineProfile -or $report.invocationID -isnot [string] -or
        $report.invocationID -cne $ProfileObservation.value.invocationID) { throw 'ci-bitmap-attribution-invalid' }
    Assert-CiBitmapFixtures $report.coverage.fixtures
    Assert-GalleryBitmapArray $report.entries 2
    Assert-CiBitmapFixtures @($report.entries | ForEach-Object { $_.fixtureID })
    if ($report.invocationAssociation -ceq 'linked-to-completed-invocation') {
        foreach ($digest in @($report.currentFontProfile.sha256, $report.executable.beforeSha256, $report.executable.afterSha256, $report.source.observationSha256)) {
            if ($digest -isnot [string] -or $digest -cnotmatch '\A[0-9a-f]{64}\z') { throw 'ci-bitmap-attribution-association-invalid' }
        }
        Assert-GalleryBitmapEnum $report.executable.buildRevision @('not-embedded')
        Assert-GalleryBitmapEnum $report.source.observation @('checkout-only')
        if ($report.currentFontProfile.sha256 -cne $ProfileObservation.artifact.sha256 -or
            $report.executable.beforeSha256 -cne $Executable.sha256 -or $report.executable.afterSha256 -cne $Executable.sha256 -or
            $report.executable.unchanged -isnot [bool] -or -not $report.executable.unchanged -or $report.executable.buildRevision -cne 'not-embedded' -or
            $report.source.revision -isnot [string] -or $report.source.revision -cne $ProfileObservation.value.source.revision -or
            $report.source.observationSha256 -cne (Get-GalleryBitmapJsonDigest $ProfileObservation.value.source) -or
            $null -ne $report.source.executableBuildRevision) { throw 'ci-bitmap-attribution-association-invalid' }
    } elseif ($report.status -ceq 'observed') { throw 'ci-bitmap-attribution-association-invalid' }
    foreach ($entry in $report.entries) {
        Assert-GalleryBitmapEnum $entry.status @('observed', 'partial')
        Assert-GalleryBitmapEnum $entry.association @('unverified', 'linked-to-completed-invocation; scene-reference-is-not-visible-contribution')
        if ($report.status -ceq 'observed' -and ($entry.status -cne 'observed' -or $entry.association -ceq 'unverified')) { throw 'ci-bitmap-attribution-artifact-link-invalid' }
        foreach ($link in @(
            @('png', ('current/' + $entry.fixtureID + '.png'), @('observed')),
            @('nativeSidecar', ('bitmap-font-attribution/native/' + $entry.fixtureID + '.native-font-attribution.json'), @('validated', 'read-unverified', 'rejected'))
        )) {
            $reference = $entry.($link[0])
            if ($null -eq $reference) { throw 'ci-bitmap-attribution-artifact-link-invalid' }
            Assert-GalleryBitmapEnum $reference.status $(if ($link[0] -ceq 'png') { @('observed', 'unavailable') } else { @('unavailable', 'validated', 'read-unverified', 'rejected') })
            if ($entry.association -cne 'unverified' -and $reference.status -cne $(if ($link[0] -ceq 'png') { 'observed' } else { 'validated' })) { throw 'ci-bitmap-attribution-artifact-link-invalid' }
            if ($link[2] -cnotcontains $reference.status) { continue }
            if ($reference.path -isnot [string] -or $reference.path -cne $link[1] -or $reference.sha256 -isnot [string] -or $reference.sha256 -cnotmatch '\A[0-9a-f]{64}\z') { throw 'ci-bitmap-attribution-artifact-link-invalid' }
            Assert-GalleryBitmapInteger $reference.length $(if ($link[0] -ceq 'png') { 33554432 } else { 524288 }) 1
            $observed = @($Outputs | Where-Object { $_.path -ceq $link[1] -and $_.status -ceq 'observed' })
            if ($observed.Count -ne 1 -or $observed[0].sha256 -cne $reference.sha256 -or $observed[0].length -ne $reference.length) { throw 'ci-bitmap-attribution-artifact-link-invalid' }
        }
    }
    [pscustomobject]@{ status = $report.status; invocationAssociation = $report.invocationAssociation; qualification = 'unqualified'; reportSha256 = $read.artifact.sha256 }
}

function Invoke-CiBitmapFontAttribution {
    param($Context, [ValidateSet('BeforeFull', 'AfterFull')][string]$Phase, [string]$FullOutcome = '',
        [scriptblock]$ObserveSource = { param($root) Get-CiBitmapSource $root },
        [scriptblock]$PrepareEnvironment = {
            param($context)
            & (Join-Path $context.root 'scripts/with-swift.ps1') -CheckOnly | Out-Host
            $environmentExit = $LASTEXITCODE
            return $environmentExit
        },
        [scriptblock]$Execute = { param($request) Invoke-CiBitmapProcess $request },
        [scriptblock]$Clock = { [DateTimeOffset]::UtcNow })

    $ErrorActionPreference = 'Stop'
    Assert-CiBitmapOwnedDirectories $Context
    if ($Phase -ceq 'BeforeFull') {
        if (Test-Path -LiteralPath $Context.outputDirectory) { throw 'ci-bitmap-output-exists' }
        $source = & $ObserveSource $Context.root
        # A dirty source is retained as a boundary observation and will block
        # AfterFull. Failed observation cannot manufacture a clean boundary.
        $previous = [ordered]@{ status = 'missing'; sha256 = $null; length = $null }
        if (Test-Path -LiteralPath $Context.normalProvenancePath) {
            try {
                $observed = Read-GalleryBitmapArtifact $Context.normalProvenancePath $script:ciBitmapMetadataLimit
                $previous.status = 'observed'; $previous.sha256 = $observed.sha256; $previous.length = $observed.length
            } catch { $previous.status = 'unavailable' }
        }
        [void][IO.Directory]::CreateDirectory($Context.outputDirectory)
        Assert-CiBitmapOwnedDirectories $Context
        Write-CiBitmapJsonNew $Context.boundaryPath ([ordered]@{
            schemaVersion = 1; kind = 'ci-bitmap-font-boundary'; runID = $Context.runID; runAttempt = $Context.runAttempt
            observedAtUtc = (& $Clock).ToUniversalTime().ToString('o'); outputDirectory = $Context.outputDirectory
            source = $source; previousNormalProvenance = $previous; qualification = 'unqualified'
        })
        return [pscustomobject]@{ status = 'boundary-recorded'; coordinatorExitCode = 0; childExitCode = $null }
    }
    if ($FullOutcome -cnotin @('success', 'failure')) { throw 'ci-bitmap-completed-full-required' }
    [void][IO.Directory]::CreateDirectory($Context.outputDirectory)
    Assert-CiBitmapOwnedDirectories $Context
    foreach ($leaf in @('result.json', 'attempt.json', 'normal-gallery-provenance.json', 'diagnostic.stdout.log', 'diagnostic.stderr.log')) {
        if (Test-Path -LiteralPath (Join-Path $Context.outputDirectory $leaf)) { throw 'ci-bitmap-output-exists' }
    }
    $result = [ordered]@{
        schemaVersion = 1; kind = 'ci-gallery-bitmap-font-attribution'; runID = $Context.runID; runAttempt = $Context.runAttempt
        fullOutcome = $FullOutcome; status = 'blocked'; reason = $null; childExitCode = $null; coordinatorExitCode = 1
        qualification = 'unqualified'; association = 'unverified'; source = $null; normalGallery = $null
        executable = [ordered]@{ before = $null; after = $null; unchanged = $false; embeddedBuildRevision = $null }
        streams = $null; pixel = [ordered]@{ status = 'not-observed' }
        attribution = [ordered]@{ status = 'unavailable'; invocationAssociation = 'unverified'; qualification = 'unqualified' }
        outputs = @(); loadedFontBytes = 'not-observed'; resultPreservation = 'pending'; observedAtUtc = (& $Clock).ToUniversalTime().ToString('o')
    }
    $stage = 'ci-bitmap-boundary-invalid'; $launched = $false; $request = $null
    try {
        if (-not (Test-Path -LiteralPath $Context.boundaryPath)) { throw 'ci-bitmap-boundary-missing' }
        $boundaryRead = Read-CiBitmapJson $Context.boundaryPath; $boundary = $boundaryRead.value
        $keys = @('schemaVersion', 'kind', 'runID', 'runAttempt', 'observedAtUtc', 'outputDirectory', 'source', 'previousNormalProvenance', 'qualification')
        Assert-GalleryBitmapObject $boundary $keys $keys
        Assert-GalleryBitmapInteger $boundary.schemaVersion 1 1
        Assert-GalleryBitmapEnum $boundary.kind @('ci-bitmap-font-boundary')
        Assert-GalleryBitmapEnum $boundary.runID @($Context.runID)
        Assert-GalleryBitmapEnum $boundary.runAttempt @($Context.runAttempt)
        Assert-GalleryBitmapEnum $boundary.qualification @('unqualified')
        Assert-GalleryBitmapObject $boundary.previousNormalProvenance @('status', 'sha256', 'length') @('status', 'sha256', 'length')
        Assert-GalleryBitmapEnum $boundary.previousNormalProvenance.status @('missing', 'unavailable', 'observed')
        if ($boundary.previousNormalProvenance.status -ceq 'observed') {
            if ($boundary.previousNormalProvenance.sha256 -isnot [string] -or $boundary.previousNormalProvenance.sha256 -cnotmatch '\A[0-9a-f]{64}\z') { throw 'ci-bitmap-boundary-invalid' }
            Assert-GalleryBitmapInteger $boundary.previousNormalProvenance.length $script:ciBitmapMetadataLimit 0
        } elseif ($null -ne $boundary.previousNormalProvenance.sha256 -or $null -ne $boundary.previousNormalProvenance.length) { throw 'ci-bitmap-boundary-invalid' }
        Assert-CiBitmapPathEqual $boundary.outputDirectory $Context.outputDirectory
        Assert-CiBitmapSource $boundary.source $Context $null
        if ((ConvertTo-CiBitmapTime $boundary.observedAtUtc) -gt (& $Clock)) { throw 'ci-bitmap-boundary-invalid' }
        if (Test-Path -LiteralPath $Context.renderDirectory) { throw 'ci-bitmap-render-directory-exists' }
        $stage = 'ci-bitmap-normal-provenance-invalid'
        $receipt = Read-CiBitmapJson $Context.normalProvenancePath
        $result.normalGallery = [ordered]@{ provenanceSha256 = $receipt.artifact.sha256; provenanceBytes = $receipt.artifact.length; buildStatus = $null; renderStatus = $null; renderExitCode = $null; imageAssociation = $null }
        if ($boundary.previousNormalProvenance.status -ceq 'observed' -and $receipt.artifact.sha256 -ceq $boundary.previousNormalProvenance.sha256) { throw 'ci-bitmap-receipt-not-fresh' }
        Copy-CiBitmapReceiptNew $Context.normalProvenancePath $Context.copiedProvenancePath $receipt.artifact
        $stage = 'ci-bitmap-executable-unavailable'
        $executable = Read-GalleryBitmapArtifact $Context.galleryExecutable $script:ciBitmapExecutableLimit
        if ($executable.length -le 0) { throw 'ci-bitmap-executable-unavailable' }
        $result.executable.before = [ordered]@{ sha256 = $executable.sha256; length = $executable.length }
        $stage = 'ci-bitmap-normal-provenance-invalid'
        Assert-CiBitmapNormalReceipt $receipt.value $boundary $Context (& $Clock) $executable
        $result.normalGallery.buildStatus = $receipt.value.build.status
        $result.normalGallery.renderStatus = $receipt.value.render.status
        $result.normalGallery.renderExitCode = $receipt.value.render.exitCode
        $result.normalGallery.imageAssociation = $receipt.value.render.imageAssociation
        $stage = 'ci-bitmap-source-unavailable'
        $currentSource = & $ObserveSource $Context.root
        Assert-CiBitmapSource $currentSource $Context $boundary.source.revision
        $result.source = $currentSource
        $request = New-CiBitmapCommand $Context
        $startedAt = & $Clock
        Write-CiBitmapJsonNew (Join-Path $Context.outputDirectory 'attempt.json') ([ordered]@{
            schemaVersion = 1; kind = 'ci-bitmap-font-attempt'; runID = $Context.runID; runAttempt = $Context.runAttempt
            startedAtUtc = $startedAt.ToUniversalTime().ToString('o'); fullOutcome = $FullOutcome; command = $request
            boundarySha256 = $boundaryRead.artifact.sha256; normalProvenanceSha256 = $receipt.artifact.sha256
            executable = $result.executable.before; source = $currentSource; qualification = 'unqualified'
            limits = [ordered]@{ streamBytesEach = $script:ciBitmapLogLimit; overflow = 'preserved-prefix; continue-draining; incomplete'; actionsStepTimeoutMinutes = 10 }
        })
        $stage = 'ci-bitmap-environment-preparation-failed'
        $environmentExit = & $PrepareEnvironment $Context
        Assert-GalleryBitmapInteger $environmentExit 0 0
        $stage = 'ci-bitmap-prelaunch-observation-changed'
        Assert-CiBitmapOwnedDirectories $Context
        if (Test-Path -LiteralPath $Context.renderDirectory) { throw 'ci-bitmap-render-directory-exists' }
        Assert-CiBitmapSource (& $ObserveSource $Context.root) $Context $boundary.source.revision
        if ((Read-GalleryBitmapArtifact $Context.normalProvenancePath $script:ciBitmapMetadataLimit).sha256 -cne $receipt.artifact.sha256 -or
            (Read-GalleryBitmapArtifact $Context.boundaryPath $script:ciBitmapMetadataLimit).sha256 -cne $boundaryRead.artifact.sha256 -or
            (Read-GalleryBitmapArtifact $Context.galleryExecutable $script:ciBitmapExecutableLimit).sha256 -cne $executable.sha256) { throw 'ci-bitmap-prelaunch-observation-changed' }
        $stage = 'ci-bitmap-process-failed'; $launched = $true; $result.status = 'failed-or-incomplete'
        $child = & $Execute $request
        Assert-GalleryBitmapInteger $child.exitCode ([int]::MaxValue) ([int]::MinValue)
        $result.childExitCode = $child.exitCode; $result.coordinatorExitCode = $child.exitCode
        $stage = 'ci-bitmap-stream-capture-incomplete'
        Assert-CiBitmapOwnedDirectories $Context
        $result.streams = Get-CiBitmapStreamObservations $Context $child.capture
        if ($child.captureError -eq $true) { $result.reason = 'ci-bitmap-stream-capture-incomplete' }
        foreach ($name in @('stdout', 'stderr')) {
            if ($result.streams.$name.status -cne 'complete') { $result.reason = 'ci-bitmap-stream-capture-incomplete' }
        }
        $result.outputs = @(Get-CiBitmapOutputObservations $Context)
        $stage = 'ci-bitmap-postrun-observation-changed'
        $after = Read-GalleryBitmapArtifact $Context.galleryExecutable $script:ciBitmapExecutableLimit
        $result.executable.after = [ordered]@{ sha256 = $after.sha256; length = $after.length }
        $result.executable.unchanged = $after.sha256 -ceq $executable.sha256 -and $after.length -eq $executable.length
        if (-not $result.executable.unchanged -or (Read-GalleryBitmapArtifact $Context.normalProvenancePath $script:ciBitmapMetadataLimit).sha256 -cne $receipt.artifact.sha256 -or
            (Read-GalleryBitmapArtifact $Context.boundaryPath $script:ciBitmapMetadataLimit).sha256 -cne $boundaryRead.artifact.sha256) { throw 'ci-bitmap-postrun-observation-changed' }
        Assert-CiBitmapSource (& $ObserveSource $Context.root) $Context $boundary.source.revision
        $stage = 'ci-bitmap-diagnostic-report-invalid'
        if (@($result.outputs | Where-Object { $_.status -ceq 'rejected' }).Count -gt 0) { throw 'ci-bitmap-diagnostic-output-rejected' }
        $profile = Read-CiBitmapJson (Join-Path $Context.renderDirectory 'provenance.json')
        Assert-CiBitmapDiagnosticProfile $profile.value $Context $boundary.source.revision $executable $startedAt (& $Clock)
        $comparison = Read-CiBitmapJson (Join-Path $Context.renderDirectory 'report.json')
        $result.pixel.status = Get-CiBitmapPixelStatus $comparison.value $profile.value $Context $child.exitCode $result.outputs
        $stage = 'ci-bitmap-attribution-invalid'
        $result.attribution = Get-CiBitmapAttributionStatus $Context $profile $executable $result.outputs
        $stage = 'ci-bitmap-diagnostic-output-changed'
        foreach ($output in $result.outputs) {
            if ($output.status -cne 'observed') { continue }
            if ((Read-GalleryBitmapArtifact (Join-Path $Context.renderDirectory $output.path) $output.maximumBytes).sha256 -cne $output.sha256) { throw 'ci-bitmap-diagnostic-output-changed' }
        }
        $stage = 'ci-bitmap-postrun-observation-changed'
        if ((Read-GalleryBitmapArtifact $Context.normalProvenancePath $script:ciBitmapMetadataLimit).sha256 -cne $receipt.artifact.sha256 -or
            (Read-GalleryBitmapArtifact $Context.boundaryPath $script:ciBitmapMetadataLimit).sha256 -cne $boundaryRead.artifact.sha256 -or
            (Read-GalleryBitmapArtifact $Context.galleryExecutable $script:ciBitmapExecutableLimit).sha256 -cne $executable.sha256) { throw 'ci-bitmap-postrun-observation-changed' }
        if ($null -eq $result.reason) {
            $result.status = if ($result.pixel.status -ceq 'mismatches') { 'completed-with-pixel-mismatches' } else { 'completed-pixel-pass' }
            $result.association = 'observed-within-ci-invocation; checkout-only'
        }
    } catch {
        # Do not export raw exception text, paths, environment values, or input.
        $message = $_.Exception.Message
        $result.reason = if ($message -cmatch '\Aci-bitmap-[a-z-]{1,80}\z') { $message } else { $stage }
        $result.status = if ($launched) { 'failed-or-incomplete' } else { 'blocked' }
        $result.association = 'unverified'
    }
    if ($result.status -cin @('blocked', 'failed-or-incomplete')) {
        if ($null -eq $result.childExitCode -or $result.childExitCode -eq 0) { $result.coordinatorExitCode = 1 } else { $result.coordinatorExitCode = $result.childExitCode }
        $result.attribution.invocationAssociation = 'unverified'
    }
    try {
        Assert-CiBitmapOwnedDirectories $Context
        $result.resultPreservation = 'written'
        Write-CiBitmapJsonNew $Context.resultPath $result
    } catch {
        # Result IO can fail after the child has completed. Retain its known
        # nonzero exit in the return value even when no result can be published.
        $result.resultPreservation = 'failed'; $result.status = if ($launched) { 'failed-or-incomplete' } else { 'blocked' }
        $result.reason = 'ci-bitmap-result-preservation-failed'; $result.association = 'unverified'
        $result.attribution.invocationAssociation = 'unverified'
        $result.coordinatorExitCode = if ($null -ne $result.childExitCode -and $result.childExitCode -ne 0) { $result.childExitCode } else { 1 }
    }
    [pscustomobject]$result
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    try {
        if ($Phase -ceq '') { throw 'ci-bitmap-phase-required' }
        $context = Get-CiBitmapContext
        $completed = Invoke-CiBitmapFontAttribution -Context $context -Phase $Phase -FullOutcome $FullOutcome
        Write-Host ('Bitmap font CI diagnostic: ' + $completed.status + ' (unqualified).')
        exit $completed.coordinatorExitCode
    } catch {
        Write-Host 'Bitmap font CI diagnostic could not preserve a fresh result; existing evidence and the Full gate are unchanged.'
        exit 1
    }
}
