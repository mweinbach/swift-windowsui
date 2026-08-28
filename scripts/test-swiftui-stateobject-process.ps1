<#
.SYNOPSIS
Exercises the extracted process helper with synthetic PowerShell children only.
.DESCRIPTION
PowerShell 7 runs process cases. Older hosts verify inert import, static
contracts, and explicit rejection only; their receipt never claims process
coverage. No Swift compiler, SwiftUI application, or native UI is launched.
#>
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$helperPath = Join-Path $PSScriptRoot 'swiftui-stateobject-process-common.ps1'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path (Split-Path -Parent $PSScriptRoot) (
        'artifacts/swiftui-stateobject-process-tests/' + [Guid]::NewGuid().ToString('N'))
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if ($OutputRoot -match '[\x00-\x1f\x7f]' -or (Test-Path -LiteralPath $OutputRoot)) {
    throw 'Synthetic process tests require a new output directory without control characters.'
}
[void][IO.Directory]::CreateDirectory($OutputRoot)
$script:ProcessTestAssertions = 0
$script:ProcessTestCases = [Collections.Generic.List[object]]::new()
$script:ProcessTestPreflights = [Collections.Generic.List[object]]::new()
$script:ProcessTestDescendants = [Collections.Generic.List[object]]::new()
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$failure = $null
$unsupportedGateVerified = $false

function Assert-ProcessTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Process test assertion failed: $Message" }
    $script:ProcessTestAssertions++
}

function Write-ProcessTestText {
    param([string]$Path, [AllowEmptyString()][string]$Text)
    $bytes = $utf8.GetBytes($Text)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $stream.Write($bytes, 0, $bytes.Length) }
    finally { $stream.Dispose() }
}

function Get-ProcessTestHash {
    param([string]$Path)
    return (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ProcessTestTextHash {
    param([string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($utf8.GetBytes($Text))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Read-ProcessTestText {
    param([string]$Path)
    Assert-ProcessTest ((Get-Item -LiteralPath $Path).Length -le 1MB) 'Only bounded synthetic text is read.'
    return [IO.File]::ReadAllText($Path, $utf8)
}

function New-ProcessTestScript {
    param([string]$Name, [string]$Text)
    $path = Join-Path $script:ProcessTestWorkingDirectory $Name
    Write-ProcessTestText -Path $path -Text $Text
    return $path
}

function Invoke-ProcessTestCase {
    param(
        [string]$Name, [string]$FilePath, [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 15, [long]$MaxOutputBytes = 1048576,
        [Collections.IDictionary]$Environment = @{}
    )
    $stdoutPath = Join-Path $OutputRoot ($Name + '.stdout.bin')
    $stderrPath = Join-Path $OutputRoot ($Name + '.stderr.bin')
    $record = Invoke-SwiftUIStateObjectProcess -FilePath $FilePath -Arguments $Arguments `
        -WorkingDirectory $script:ProcessTestWorkingDirectory -StdoutPath $stdoutPath -StderrPath $stderrPath `
        -TimeoutSeconds $TimeoutSeconds -MaxOutputBytes $MaxOutputBytes -Environment $Environment
    $case = [pscustomobject]@{ name = $Name; stdoutPath = $stdoutPath; stderrPath = $stderrPath; record = $record }
    $script:ProcessTestCases.Add($case)
    return $case
}

function Assert-ProcessTestRecord {
    param($Case, [long]$Limit, [bool]$CheckHashes = $true)
    $record = $Case.record
    Assert-ProcessTest ($record.stdoutBytes -ge 0 -and $record.stderrBytes -ge 0) "$($Case.name): byte counts are nonnegative."
    Assert-ProcessTest (($record.stdoutBytes + $record.stderrBytes) -le $Limit) "$($Case.name): one combined byte cap applies."
    Assert-ProcessTest ((Get-Item -LiteralPath $Case.stdoutPath).Length -eq $record.stdoutBytes) "$($Case.name): stdout count matches evidence."
    Assert-ProcessTest ((Get-Item -LiteralPath $Case.stderrPath).Length -eq $record.stderrBytes) "$($Case.name): stderr count matches evidence."
    Assert-ProcessTest ($record.durationSeconds -ge 0 -and $null -ne $record.finishedAtUtc) "$($Case.name): completion timing is recorded."
    Assert-ProcessTest ($record.terminationNote -ceq 'Termination status names the owned parent process only; descendant teardown is not proven by HasExited.') "$($Case.name): termination claim is parent-only."
    if ($CheckHashes) {
        Assert-ProcessTest ($record.stdoutSha256 -ceq (Get-ProcessTestHash $Case.stdoutPath)) "$($Case.name): stdout digest hashes captured bytes."
        Assert-ProcessTest ($record.stderrSha256 -ceq (Get-ProcessTestHash $Case.stderrPath)) "$($Case.name): stderr digest hashes captured bytes."
    }
    # Opening both files exclusively proves cleanup released evidence handles.
    foreach ($path in @($Case.stdoutPath, $Case.stderrPath)) {
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        $stream.Dispose()
        Assert-ProcessTest $true "$($Case.name): evidence handle was released."
    }
}

function Assert-ProcessTestRejected {
    param([string]$Name, [hashtable]$Parameters, [string]$Pattern)
    $caught = $null
    try { Invoke-SwiftUIStateObjectProcess @Parameters | Out-Null }
    catch { $caught = $_ }
    Assert-ProcessTest ($null -ne $caught) "$($Name): preflight rejects the invocation."
    Assert-ProcessTest ($caught.Exception.Message -match $Pattern) "$($Name): preflight reports the expected reason."
    $script:ProcessTestPreflights.Add([pscustomobject]@{ name = $Name; message = $caught.Exception.Message })
}

try {
    $tokens = $null
    $parseErrors = $null
    $helperAst = [Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$tokens, [ref]$parseErrors)
    Assert-ProcessTest ($parseErrors.Count -eq 0) 'The helper parses on this host.'
    $selfTokens = $null
    $selfErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$selfTokens, [ref]$selfErrors)
    Assert-ProcessTest ($selfErrors.Count -eq 0) 'The synthetic test script parses on this host.'
    Assert-ProcessTest ($helperAst.EndBlock.Statements.Count -eq 1) 'The import contains exactly one definition and no top-level execution.'
    $definition = $helperAst.EndBlock.Statements[0]
    Assert-ProcessTest ($definition -is [Management.Automation.Language.FunctionDefinitionAst]) 'The single statement is a function definition.'
    Assert-ProcessTest ($definition.Name -ceq 'Invoke-SwiftUIStateObjectProcess') 'The extracted function has the approved name.'
    $canonicalFunction = $definition.Extent.Text.Replace("`r`n", "`n").Replace("`r", "`n")
    Assert-ProcessTest ((Get-ProcessTestTextHash $canonicalFunction) -ceq '29b298ed09546f29cca0b1b6070fe32091a1c057061adc4dd913a3e5af9164b2') 'The pinned extraction differs only by its approved rename and PS7 gate.'
    $filesBeforeImport = @(Get-ChildItem -LiteralPath $OutputRoot -Force).Count
    $importOutput = @(. $helperPath)
    Assert-ProcessTest ($importOutput.Count -eq 0) 'Import emits no process result.'
    Assert-ProcessTest (@(Get-ChildItem -LiteralPath $OutputRoot -Force).Count -eq $filesBeforeImport) 'Import creates no evidence files.'

    $command = Get-Command Invoke-SwiftUIStateObjectProcess -CommandType Function
    $timeoutRange = @($command.Parameters['TimeoutSeconds'].Attributes | Where-Object { $_ -is [Management.Automation.ValidateRangeAttribute] })[0]
    $outputRange = @($command.Parameters['MaxOutputBytes'].Attributes | Where-Object { $_ -is [Management.Automation.ValidateRangeAttribute] })[0]
    Assert-ProcessTest ($timeoutRange.MinRange -eq 1 -and $timeoutRange.MaxRange -eq 900) 'Timeout parameter bounds remain 1 through 900 seconds.'
    Assert-ProcessTest ($outputRange.MinRange -eq 1 -and $outputRange.MaxRange -eq 16777216) 'Output parameter bounds remain 1 through 16 MiB.'
    $defaults = @{}
    foreach ($parameter in $definition.Body.ParamBlock.Parameters) {
        if ($null -ne $parameter.DefaultValue) { $defaults[$parameter.Name.VariablePath.UserPath] = $parameter.DefaultValue.SafeGetValue() }
    }
    Assert-ProcessTest ($defaults['TimeoutSeconds'] -eq 30) 'Default timeout remains 30 seconds.'
    Assert-ProcessTest ($defaults['MaxOutputBytes'] -eq 8388608) 'Default aggregate output cap remains 8 MiB.'

    $preflight = @{
        FilePath = Join-Path $OutputRoot 'never-launched.exe'
        WorkingDirectory = $OutputRoot
        StdoutPath = Join-Path $OutputRoot 'never-created.stdout'
        StderrPath = Join-Path $OutputRoot 'never-created.stderr'
    }
    foreach ($invalid in @(
        @{ name = 'timeout-zero'; key = 'TimeoutSeconds'; value = 0 },
        @{ name = 'timeout-too-large'; key = 'TimeoutSeconds'; value = 901 },
        @{ name = 'output-zero'; key = 'MaxOutputBytes'; value = 0 },
        @{ name = 'output-too-large'; key = 'MaxOutputBytes'; value = 16777217 }
    )) {
        $parameters = $preflight.Clone()
        $parameters[$invalid.key] = $invalid.value
        Assert-ProcessTestRejected -Name $invalid.name -Parameters $parameters -Pattern 'validate|range|greater|less'
    }
    Assert-ProcessTest (-not (Test-Path -LiteralPath $preflight.StdoutPath)) 'Parameter rejection does not create stdout.'
    Assert-ProcessTest (-not (Test-Path -LiteralPath $preflight.StderrPath)) 'Parameter rejection does not create stderr.'

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Assert-ProcessTestRejected -Name 'unsupported-host' -Parameters $preflight -Pattern 'requires PowerShell 7 or newer'
        Assert-ProcessTest (-not (Test-Path -LiteralPath $preflight.StdoutPath)) 'The unsupported-host gate runs before evidence creation.'
        Assert-ProcessTest (-not (Test-Path -LiteralPath $preflight.StderrPath)) 'The unsupported-host gate leaves both paths absent.'
        $unsupportedGateVerified = $true
    } else {
        $script:ProcessTestWorkingDirectory = Join-Path $OutputRoot 'PowerShell child fixtures with spaces'
        [void][IO.Directory]::CreateDirectory($script:ProcessTestWorkingDirectory)
        $currentProcess = [Diagnostics.Process]::GetCurrentProcess()
        try { $powerShellPath = $currentProcess.MainModule.FileName }
        finally { $currentProcess.Dispose() }
        Assert-ProcessTest ([IO.Path]::GetFileNameWithoutExtension($powerShellPath) -ieq 'pwsh') 'Real-process fixtures launch this PowerShell 7 executable only.'

        $argvScript = New-ProcessTestScript -Name 'literal argv.ps1' -Text @'
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$inputText = [Console]::In.ReadToEnd()
$result = [ordered]@{
    arguments = [string[]]$args
    workingDirectory = [IO.Directory]::GetCurrentDirectory()
    environment = [Environment]::GetEnvironmentVariable('SWIFTUI_STATEOBJECT_PROCESS_FIXTURE')
    stdinClosed = $inputText.Length -eq 0
}
[Console]::Out.Write(($result | ConvertTo-Json -Depth 4 -Compress))
'@
        $literalArguments = [string[]]@(
            'two words', '', 'a"b', '"quoted"', 'literal`backtick', 'trailing\',
            '$(Write-Output not-executed)', '$env:PATH', 'semi;colon', '-looks-like-a-parameter')
        $environmentValue = 'literal value with spaces, "quotes", and `backticks'
        $argvCase = Invoke-ProcessTestCase -Name 'literal-argv' -FilePath $powerShellPath `
            -Arguments (@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $argvScript) + $literalArguments) `
            -Environment @{ SWIFTUI_STATEOBJECT_PROCESS_FIXTURE = $environmentValue }
        Assert-ProcessTestRecord $argvCase 1048576
        Assert-ProcessTest ($argvCase.record.processStarted -and $argvCase.record.exitCode -eq 0 -and $null -eq $argvCase.record.error) 'Literal arguments child exits successfully.'
        Assert-ProcessTest ($argvCase.record.terminationCompleted -and $argvCase.record.allRedirectedStreamsClosed -and -not $argvCase.record.terminationRequested) 'Normal exit reaches EOF without claiming a kill.'
        Assert-ProcessTest ($argvCase.record.cleanupErrors.Count -eq 0) 'Normal exit records no cleanup error.'
        $argv = (Read-ProcessTestText $argvCase.stdoutPath) | ConvertFrom-Json
        Assert-ProcessTest ($argv.arguments.Count -eq $literalArguments.Count) 'Empty arguments are not lost.'
        for ($argumentIndex = 0; $argumentIndex -lt $literalArguments.Count; $argumentIndex++) {
            Assert-ProcessTest ([string]::Equals($argv.arguments[$argumentIndex], $literalArguments[$argumentIndex], [StringComparison]::Ordinal)) "Argument $argumentIndex round-trips literally."
        }
        $pathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        Assert-ProcessTest ([string]::Equals($argv.workingDirectory, $script:ProcessTestWorkingDirectory, $pathComparison)) 'The explicit working directory is used.'
        Assert-ProcessTest ($argv.environment -ceq $environmentValue) 'The explicit environment value is data, not shell syntax.'
        Assert-ProcessTest ([bool]$argv.stdinClosed) 'The helper closes child stdin.'

        $exitScript = New-ProcessTestScript -Name 'exit one.ps1' -Text @'
[Console]::Out.Write('stdout-before-exit-one')
[Console]::Error.Write('stderr-before-exit-one')
exit 1
'@
        $exitCase = Invoke-ProcessTestCase -Name 'exit-one' -FilePath $powerShellPath -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $exitScript)
        Assert-ProcessTestRecord $exitCase 1048576
        Assert-ProcessTest ($exitCase.record.exitCode -eq 1 -and $null -eq $exitCase.record.error) 'A child exit of one remains distinct from a helper error.'
        Assert-ProcessTest ($exitCase.record.terminationCompleted -and $exitCase.record.allRedirectedStreamsClosed) 'Nonzero exit still drains both streams.'
        Assert-ProcessTest ((Read-ProcessTestText $exitCase.stdoutPath) -ceq 'stdout-before-exit-one') 'Nonzero exit retains stdout.'
        Assert-ProcessTest ((Read-ProcessTestText $exitCase.stderrPath) -ceq 'stderr-before-exit-one') 'Nonzero exit retains stderr.'

        $dualScript = New-ProcessTestScript -Name 'dual stream exact cap.ps1' -Text @'
[Console]::Out.Write(('O' * 65536))
[Console]::Out.Flush()
[Console]::Error.Write(('E' * 65536))
[Console]::Error.Flush()
'@
        $dualCase = Invoke-ProcessTestCase -Name 'dual-stream-exact-cap' -FilePath $powerShellPath `
            -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $dualScript) -MaxOutputBytes 131072
        Assert-ProcessTestRecord $dualCase 131072
        Assert-ProcessTest ($dualCase.record.stdoutBytes -eq 65536 -and $dualCase.record.stderrBytes -eq 65536) 'Both large streams drain without a serial-read deadlock.'
        Assert-ProcessTest (-not $dualCase.record.outputLimitExceeded -and $dualCase.record.observedDiscardedBytes -eq 0) 'Exactly reaching the combined cap is not overflow.'
        Assert-ProcessTest ($dualCase.record.exitCode -eq 0 -and $dualCase.record.allRedirectedStreamsClosed -and $null -eq $dualCase.record.error) 'Exact-cap output completes normally.'

        $sleepScript = New-ProcessTestScript -Name 'sleep past deadline.ps1' -Text '[Threading.Thread]::Sleep(30000)'
        $sleepCase = Invoke-ProcessTestCase -Name 'deadline' -FilePath $powerShellPath `
            -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $sleepScript) -TimeoutSeconds 1
        Assert-ProcessTestRecord $sleepCase 1048576
        Assert-ProcessTest ($sleepCase.record.processStarted -and $sleepCase.record.timedOut) 'The process deadline is enforced.'
        Assert-ProcessTest ($sleepCase.record.terminationRequested -and $sleepCase.record.terminationCompleted) 'The timed-out owned parent is confirmed exited.'
        Assert-ProcessTest ($null -ne $sleepCase.record.exitCode -and $sleepCase.record.allRedirectedStreamsClosed) 'Timeout status keeps its platform-specific exit code and EOF result.'
        Assert-ProcessTest ($sleepCase.record.durationSeconds -lt 10) 'Deadline plus shutdown/drain overhead stays bounded in this local synthetic case.'

        $floodScript = New-ProcessTestScript -Name 'combined stream overflow.ps1' -Text @'
for ($index = 0; $index -lt 256; $index++) {
    [Console]::Out.Write(('O' * 8192))
    [Console]::Out.Flush()
    [Console]::Error.Write(('E' * 8192))
    [Console]::Error.Flush()
}
'@
        $floodCase = Invoke-ProcessTestCase -Name 'combined-stream-limit' -FilePath $powerShellPath `
            -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $floodScript) -MaxOutputBytes 32768
        Assert-ProcessTestRecord $floodCase 32768
        Assert-ProcessTest ($floodCase.record.outputLimitExceeded -and $floodCase.record.observedDiscardedBytes -gt 0) 'Combined overflow records only excess bytes actually observed.'
        Assert-ProcessTest (($floodCase.record.stdoutBytes + $floodCase.record.stderrBytes) -eq 32768) 'Neither stream receives a second independent cap.'
        Assert-ProcessTest ($floodCase.record.terminationRequested -and $floodCase.record.terminationCompleted) 'Overflow requests stopping and confirms the owned parent exited.'
        Assert-ProcessTest ($floodCase.record.allRedirectedStreamsClosed -and -not $floodCase.record.timedOut) 'Overflow cleanup reaches EOF before the process deadline.'

        $utf8Script = New-ProcessTestScript -Name 'partial utf8 output.ps1' -Text @'
$stream = [Console]::OpenStandardOutput()
$bytes = [byte[]]@(0xf0, 0x9f, 0x92, 0xa1)
$stream.Write($bytes, 0, $bytes.Length)
$stream.Flush()
'@
        $utf8Case = Invoke-ProcessTestCase -Name 'partial-utf8-limit' -FilePath $powerShellPath `
            -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $utf8Script) -MaxOutputBytes 3
        Assert-ProcessTestRecord $utf8Case 3
        Assert-ProcessTest ($utf8Case.record.outputLimitExceeded -and $utf8Case.record.stdoutBytes -eq 3) 'Byte limits need not end at a UTF-8 character boundary.'
        Assert-ProcessTest ([BitConverter]::ToString([IO.File]::ReadAllBytes($utf8Case.stdoutPath)) -ceq 'F0-9F-92') 'The truncated evidence remains the original captured bytes.'

        $missingExecutable = Join-Path $script:ProcessTestWorkingDirectory 'missing executable'
        $launchCase = Invoke-ProcessTestCase -Name 'launch-failure' -FilePath $missingExecutable
        Assert-ProcessTestRecord $launchCase 1048576
        Assert-ProcessTest (-not $launchCase.record.processStarted -and $null -eq $launchCase.record.exitCode) 'Launch failure cannot claim a process or exit code.'
        Assert-ProcessTest ($null -ne $launchCase.record.error -and -not $launchCase.record.terminationCompleted -and -not $launchCase.record.allRedirectedStreamsClosed) 'Launch failure remains distinct from completed termination or drain.'
        Assert-ProcessTest ($launchCase.record.stdoutBytes -eq 0 -and $launchCase.record.stderrBytes -eq 0) 'Launch failure retains its empty, newly created evidence.'

        $protectedStdout = Join-Path $OutputRoot 'protected stdout.log'
        $protectedStderr = Join-Path $OutputRoot 'protected stderr.log'
        Write-ProcessTestText $protectedStdout 'stdout evidence must survive'
        Write-ProcessTestText $protectedStderr 'stderr evidence must survive'
        $stdoutHash = Get-ProcessTestHash $protectedStdout
        $stderrHash = Get-ProcessTestHash $protectedStderr
        $validPreflight = @{
            FilePath = $powerShellPath; WorkingDirectory = $script:ProcessTestWorkingDirectory
            StdoutPath = Join-Path $OutputRoot 'preflight-new.stdout'
            StderrPath = Join-Path $OutputRoot 'preflight-new.stderr'
        }
        $parameters = $validPreflight.Clone()
        $parameters.StdoutPath = $protectedStdout
        Assert-ProcessTestRejected 'existing-stdout' $parameters 'existing evidence is never overwritten'
        $parameters = $validPreflight.Clone()
        $parameters.StderrPath = $protectedStderr
        Assert-ProcessTestRejected 'existing-stderr' $parameters 'existing evidence is never overwritten'
        Assert-ProcessTest ((Get-ProcessTestHash $protectedStdout) -ceq $stdoutHash -and (Get-ProcessTestHash $protectedStderr) -ceq $stderrHash) 'Both preexisting evidence files are unchanged.'
        Assert-ProcessTest (-not (Test-Path -LiteralPath $validPreflight.StdoutPath) -and -not (Test-Path -LiteralPath $validPreflight.StderrPath)) 'Preflight rejection does not create the other log.'
        $parameters = $validPreflight.Clone()
        $parameters.StderrPath = Join-Path $OutputRoot './preflight-new.stdout'
        Assert-ProcessTestRejected 'same-canonical-log' $parameters 'distinct files'
        $parameters = $validPreflight.Clone()
        $parameters.WorkingDirectory = Join-Path $OutputRoot 'missing-directory'
        Assert-ProcessTestRejected 'missing-working-directory' $parameters 'working directory is missing'
        foreach ($pathKey in @('FilePath', 'WorkingDirectory', 'StdoutPath', 'StderrPath')) {
            $parameters = $validPreflight.Clone()
            $parameters[$pathKey] = 'relative-path'
            Assert-ProcessTestRejected ('relative-' + $pathKey) $parameters 'absolute and contain no control'
        }
        $parameters = $validPreflight.Clone()
        $parameters.StdoutPath = $validPreflight.StdoutPath + [char]10
        Assert-ProcessTestRejected 'control-character-path' $parameters 'absolute and contain no control'

        # Shadow only hashing inside this scope. No process implementation is
        # replaced, and both evidence handles must still close independently.
        $hashFailureCase = & {
            function Get-FileHash {
                param([string]$LiteralPath, [string]$Algorithm)
                throw ('synthetic hash failure: ' + [IO.Path]::GetFileName($LiteralPath))
            }
            Invoke-ProcessTestCase -Name 'successful-exit-hash-failure' -FilePath $powerShellPath `
                -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $argvScript)
        }
        Assert-ProcessTestRecord $hashFailureCase 1048576 $false
        Assert-ProcessTest ($hashFailureCase.record.exitCode -eq 0 -and $hashFailureCase.record.terminationCompleted -and $hashFailureCase.record.allRedirectedStreamsClosed) 'Digest failures do not erase completed process facts.'
        Assert-ProcessTest ($hashFailureCase.record.cleanupErrors.Count -eq 2 -and $hashFailureCase.record.error -match 'synthetic hash failure') 'Both failed digest cleanups are retained.'
        Assert-ProcessTest ($null -eq $hashFailureCase.record.stdoutSha256 -and $null -eq $hashFailureCase.record.stderrSha256) 'Failed digests are not fabricated.'
        $primaryFailureCase = & {
            function Get-FileHash {
                param([string]$LiteralPath, [string]$Algorithm)
                throw ('synthetic hash failure: ' + [IO.Path]::GetFileName($LiteralPath))
            }
            Invoke-ProcessTestCase -Name 'launch-and-hash-failure' -FilePath $missingExecutable
        }
        Assert-ProcessTestRecord $primaryFailureCase 1048576 $false
        Assert-ProcessTest (-not $primaryFailureCase.record.processStarted -and $primaryFailureCase.record.cleanupErrors.Count -eq 2) 'Launch failure still attempts both independent hash cleanups.'
        Assert-ProcessTest ($primaryFailureCase.record.error -notmatch 'synthetic hash failure') 'Cleanup failures do not replace the primary launch error.'

        # The synthetic descendant retains inherited pipe handles after its parent exits.
        # The test, not the helper, owns and separately verifies descendant cleanup.
        $holderReceiptPath = Join-Path $OutputRoot 'owned pipe-holder.json'
        $holderReadyPath = Join-Path $OutputRoot 'owned pipe-holder.ready'
        $holderScript = New-ProcessTestScript -Name 'hold inherited pipes.ps1' -Text @'
param([string]$ReadyPath)
$ready = [IO.File]::Open($ReadyPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
$ready.Dispose()
[Threading.Thread]::Sleep(7000)
'@
        $spawnScript = New-ProcessTestScript -Name 'spawn pipe holder.ps1' -Text @'
param([string]$PowerShellPath, [string]$HolderScript, [string]$ReceiptPath, [string]$ReadyPath)
$ErrorActionPreference = 'Stop'
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = $PowerShellPath
$start.WorkingDirectory = [IO.Directory]::GetCurrentDirectory()
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $HolderScript, $ReadyPath)) { $start.ArgumentList.Add($argument) }
$holder = [Diagnostics.Process]::new()
$holder.StartInfo = $start
try {
    if (-not $holder.Start()) { throw 'Synthetic pipe holder did not start.' }
    $receipt = [ordered]@{
        processId = $holder.Id
        startTimeUtcTicks = $holder.StartTime.ToUniversalTime().Ticks
        executable = $PowerShellPath
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($receipt | ConvertTo-Json -Compress))
    $file = [IO.File]::Open($ReceiptPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $file.Write($bytes, 0, $bytes.Length) }
    finally { $file.Dispose() }
    $startup = [Diagnostics.Stopwatch]::StartNew()
    while (-not [IO.File]::Exists($ReadyPath) -and -not $holder.HasExited -and $startup.Elapsed.TotalSeconds -lt 3) {
        [Threading.Thread]::Sleep(10)
    }
    if (-not [IO.File]::Exists($ReadyPath)) { throw 'Synthetic pipe holder did not signal readiness.' }
    [Console]::Out.Write('owned-parent-exited;')
    [Console]::Out.Flush()
} finally { $holder.Dispose() }
'@
        $drainCase = $null
        try {
            $drainCase = Invoke-ProcessTestCase -Name 'parent-exit-incomplete-drain' -FilePath $powerShellPath `
                -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $spawnScript, $powerShellPath, $holderScript, $holderReceiptPath, $holderReadyPath)
        } finally {
            if (Test-Path -LiteralPath $holderReceiptPath) {
                $holderIdentity = (Read-ProcessTestText $holderReceiptPath) | ConvertFrom-Json
                $cleanup = [ordered]@{ processId = $holderIdentity.processId; identityMatched = $false; terminationRequested = $false; terminationCompleted = $false; error = $null }
                $holderProcess = $null
                try {
                    $holderProcess = [Diagnostics.Process]::GetProcessById([int]$holderIdentity.processId)
                    $identityMatches = $holderProcess.StartTime.ToUniversalTime().Ticks -eq [long]$holderIdentity.startTimeUtcTicks -and
                        [string]::Equals($holderProcess.MainModule.FileName, [string]$holderIdentity.executable, $pathComparison)
                    if (-not $identityMatches) { throw 'Refusing to stop a process whose identity does not match the owned synthetic child.' }
                    $cleanup.identityMatched = $true
                    if (-not $holderProcess.HasExited) {
                        $cleanup.terminationRequested = $true
                        $holderProcess.Kill($true)
                        [void]$holderProcess.WaitForExit(5000)
                    }
                    $cleanup.terminationCompleted = $holderProcess.HasExited
                } catch [ArgumentException] {
                    # A child that already exited need not still have a process table entry.
                    $cleanup.terminationCompleted = $true
                } catch { $cleanup.error = $_.Exception.Message }
                finally { if ($null -ne $holderProcess) { $holderProcess.Dispose() } }
                $script:ProcessTestDescendants.Add([pscustomobject]$cleanup)
            }
        }
        Assert-ProcessTest ($null -ne $drainCase -and $script:ProcessTestDescendants.Count -eq 1) 'The inherited-pipe fixture records separate descendant ownership.'
        Assert-ProcessTestRecord $drainCase 1048576
        Assert-ProcessTest ($drainCase.record.exitCode -eq 0 -and $drainCase.record.terminationCompleted) 'The owned parent exited successfully.'
        Assert-ProcessTest (-not $drainCase.record.allRedirectedStreamsClosed -and $drainCase.record.error -match 'two-second drain bound') 'At least one inherited pipe remains open after the owned parent exits and reaches the drain bound.'
        Assert-ProcessTest (-not $drainCase.record.timedOut -and -not $drainCase.record.terminationRequested) 'A pipe-drain failure is not mislabeled as a process deadline or parent kill.'
        # The record reports aggregate EOF, not a separate status for each stream.
        # Readiness plus a still-live owned descendant proves the intended fixture;
        # it does not assert that both standard stream mappings are inherited.
        Assert-ProcessTest ((Test-Path -LiteralPath $holderReadyPath) -and (Read-ProcessTestText $drainCase.stdoutPath).Contains('owned-parent-exited;')) 'The parent exits only after the descendant signals readiness.'
        Assert-ProcessTest ($drainCase.record.durationSeconds -ge 2 -and $drainCase.record.durationSeconds -lt 10) 'The open inherited pipe reaches the bounded drain deadline.'
        Assert-ProcessTest ($script:ProcessTestDescendants[0].identityMatched -and $script:ProcessTestDescendants[0].terminationRequested) 'The separately owned descendant is still live after the parent and pipe-drain deadline.'
        Assert-ProcessTest ($script:ProcessTestDescendants[0].terminationCompleted -and $null -eq $script:ProcessTestDescendants[0].error) 'Separately owned descendant cleanup completed.'
    }
} catch { $failure = $_ }
finally {
    $receipt = [ordered]@{
        schemaVersion = 1
        status = if ($null -ne $failure) { 'failed' } elseif ($PSVersionTable.PSVersion.Major -lt 7) { 'unsupported-host-verified' } else { 'synthetic-tests-passed' }
        coverage = if ($PSVersionTable.PSVersion.Major -lt 7) { 'inert-import-static-contracts-and-version-rejection-only' } else { 'synthetic-powershell-processes' }
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
        unsupportedGateVerified = $unsupportedGateVerified
        assertions = $script:ProcessTestAssertions
        processCasesExecuted = $script:ProcessTestCases.Count
        powerShellParentsStarted = @($script:ProcessTestCases | Where-Object { $_.record.processStarted }).Count
        preflightCases = $script:ProcessTestPreflights.ToArray()
        processCases = $script:ProcessTestCases.ToArray()
        separatelyOwnedDescendantCleanup = $script:ProcessTestDescendants.ToArray()
        swiftCompilerInvoked = $false
        swiftUIAppExecuted = $false
        helperSha256 = Get-ProcessTestHash $helperPath
        testScriptSha256 = Get-ProcessTestHash $PSCommandPath
        failure = if ($null -eq $failure) { $null } else { $failure.Exception.Message }
    }
    $receiptPath = Join-Path $OutputRoot 'test-results.json'
    Write-ProcessTestText -Path $receiptPath -Text ($receipt | ConvertTo-Json -Depth 12)
}
if ($null -ne $failure) { throw $failure }
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "Unsupported-host checks passed: $script:ProcessTestAssertions assertions. PowerShell 7 process cases NOT RUN."
} else {
    Write-Host "Synthetic PowerShell process tests passed: $script:ProcessTestAssertions assertions across $($script:ProcessTestCases.Count) process cases."
}
Write-Host "Receipt: $receiptPath"
