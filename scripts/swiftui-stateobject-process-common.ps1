# Bounded process capture for StateObject characterization tooling.
# Importing this file defines one function only; it never starts a process.
# Extracted from swiftui-state-reference-common.ps1, lines 786-939.
# Frozen source SHA256: 78975fc46f94849e22f62427fbcdf781dbb0be279b7c8019b66f8ccecca8e487
# Initial extraction changes only the function name and an explicit PS7 gate.

function Invoke-SwiftUIStateObjectProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$StdoutPath,
        [Parameter(Mandatory)][string]$StderrPath,
        [ValidateRange(1, 900)][int]$TimeoutSeconds = 30,
        [ValidateRange(1, 16777216)][long]$MaxOutputBytes = 8388608,
        [System.Collections.IDictionary]$Environment = @{}
    )
    if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Invoke-SwiftUIStateObjectProcess requires PowerShell 7 or newer.' }
    foreach ($path in @($FilePath, $WorkingDirectory, $StdoutPath, $StderrPath)) {
        if (-not [System.IO.Path]::IsPathFullyQualified($path) -or $path -match '[\x00-\x1f\x7f]') {
            throw "Process paths must be absolute and contain no control characters."
        }
    }
    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) { throw "Process working directory is missing." }
    foreach ($path in @($StdoutPath, $StderrPath)) {
        if (Test-Path -LiteralPath $path) { throw "Process output must use new files; existing evidence is never overwritten." }
    }
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if ([string]::Equals([System.IO.Path]::GetFullPath($StdoutPath), [System.IO.Path]::GetFullPath($StderrPath), $comparison)) {
        throw "Stdout and stderr must use distinct files."
    }
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    foreach ($key in $Environment.Keys) { $start.Environment[[string]$key] = [string]$Environment[$key] }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $record = [ordered]@{
        startedAtUtc = [DateTime]::UtcNow.ToString("o"); finishedAtUtc = $null
        processStarted = $false; processId = $null; exitCode = $null
        timedOut = $false; outputLimitExceeded = $false; observedDiscardedBytes = [long]0
        terminationRequested = $false; terminationCompleted = $false; allRedirectedStreamsClosed = $false
        terminationNote = "Termination status names the owned parent process only; descendant teardown is not proven by HasExited."
        stdoutBytes = [long]0; stderrBytes = [long]0; stdoutSha256 = $null; stderrSha256 = $null
        durationSeconds = 0.0; error = $null; cleanupErrors = @()
    }
    $stdoutFile = $null
    $stderrFile = $null
    $streams = @()
    $exitObservedAt = $null
    $stopDeadline = $null
    try {
        $stdoutFile = [System.IO.File]::Open($StdoutPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        $stderrFile = [System.IO.File]::Open($StderrPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        if (-not $process.Start()) { throw "The owned process was not started." }
        $record.processStarted = $true
        $record.processId = $process.Id
        $process.StandardInput.Close()
        $streams = @(
            [pscustomobject]@{ name = "stdout"; input = $process.StandardOutput.BaseStream; output = $stdoutFile; buffer = [byte[]]::new(8192); task = $null; ended = $false },
            [pscustomobject]@{ name = "stderr"; input = $process.StandardError.BaseStream; output = $stderrFile; buffer = [byte[]]::new(8192); task = $null; ended = $false }
        )
        foreach ($stream in $streams) { $stream.task = $stream.input.ReadAsync($stream.buffer, 0, $stream.buffer.Length) }
        while ($true) {
            foreach ($stream in $streams) {
                if ($stream.ended -or -not $stream.task.IsCompleted) { continue }
                $count = $stream.task.GetAwaiter().GetResult()
                if ($count -eq 0) { $stream.ended = $true; continue }
                $remaining = $MaxOutputBytes - $record.stdoutBytes - $record.stderrBytes
                $accepted = [int][Math]::Min([long]$count, $remaining)
                if ($accepted -gt 0) {
                    $stream.output.Write($stream.buffer, 0, $accepted)
                    if ($stream.name -ceq "stdout") { $record.stdoutBytes += $accepted } else { $record.stderrBytes += $accepted }
                }
                if ($accepted -lt $count) {
                    $record.outputLimitExceeded = $true
                    $record.observedDiscardedBytes += $count - $accepted
                }
                $stream.task = $stream.input.ReadAsync($stream.buffer, 0, $stream.buffer.Length)
            }
            $exited = $process.HasExited
            if ($exited -and $null -eq $exitObservedAt) {
                $exitObservedAt = $clock.Elapsed.TotalSeconds
                $record.exitCode = $process.ExitCode
            }
            if (-not $exited -and $clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { $record.timedOut = $true }
            if (($record.timedOut -or $record.outputLimitExceeded) -and -not $record.terminationRequested) {
                $record.terminationRequested = $true
                $stopDeadline = $clock.Elapsed.TotalSeconds + 5
                if (-not $exited) {
                    try { $process.Kill($true) } catch { $record.error = "Owned process termination failed: $($_.Exception.Message)" }
                }
            }
            $allEnded = @($streams | Where-Object { -not $_.ended }).Count -eq 0
            if ($exited -and $allEnded) { break }
            if ($null -ne $exitObservedAt -and $clock.Elapsed.TotalSeconds - $exitObservedAt -ge 2) {
                if ($null -eq $record.error) { $record.error = "Redirected streams did not close within the two-second drain bound." }
                break
            }
            if ($null -ne $stopDeadline -and $clock.Elapsed.TotalSeconds -ge $stopDeadline) {
                if ($null -eq $record.error) { $record.error = "Owned process did not terminate within the five-second shutdown bound." }
                break
            }
            [System.Threading.Thread]::Sleep(10)
        }
    } catch {
        if ($null -eq $record.error) { $record.error = $_.Exception.Message }
        else { $record.cleanupErrors += "Additional process failure: $($_.Exception.Message)" }
    } finally {
        # A failing close or digest must not erase the original process result
        # or skip the remaining independent cleanup. Each failure is retained.
        $cleanupFailure = {
            param([string]$Message)
            $record.cleanupErrors += $Message
            if ($null -eq $record.error) { $record.error = $Message }
        }
        try {
            if ($record.processStarted) {
                if (-not $process.HasExited -and -not $record.terminationRequested) {
                    $record.terminationRequested = $true
                    try { $process.Kill($true); [void]$process.WaitForExit(5000) } catch {
                        & $cleanupFailure "Owned process cleanup failed: $($_.Exception.Message)"
                    }
                }
                $record.terminationCompleted = $process.HasExited
                if ($record.terminationCompleted) { $record.exitCode = $process.ExitCode }
                $record.allRedirectedStreamsClosed = @($streams | Where-Object { -not $_.ended }).Count -eq 0
            }
        } catch { & $cleanupFailure "Could not inspect owned process termination: $($_.Exception.Message)" }
        foreach ($stream in $streams) {
            try { $stream.input.Dispose() } catch { & $cleanupFailure "Could not close $($stream.name) pipe: $($_.Exception.Message)" }
        }
        if ($null -ne $stdoutFile) {
            try { $stdoutFile.Dispose() } catch { & $cleanupFailure "Could not close stdout evidence: $($_.Exception.Message)" }
        }
        if ($null -ne $stderrFile) {
            try { $stderrFile.Dispose() } catch { & $cleanupFailure "Could not close stderr evidence: $($_.Exception.Message)" }
        }
        try { $process.Dispose() } catch { & $cleanupFailure "Could not dispose owned process: $($_.Exception.Message)" }
        if ($null -ne $stdoutFile) {
            try { $record.stdoutSha256 = (Get-FileHash -LiteralPath $StdoutPath -Algorithm SHA256).Hash.ToLowerInvariant() } catch {
                & $cleanupFailure "Could not hash stdout evidence: $($_.Exception.Message)"
            }
        }
        if ($null -ne $stderrFile) {
            try { $record.stderrSha256 = (Get-FileHash -LiteralPath $StderrPath -Algorithm SHA256).Hash.ToLowerInvariant() } catch {
                & $cleanupFailure "Could not hash stderr evidence: $($_.Exception.Message)"
            }
        }
        $record.durationSeconds = $clock.Elapsed.TotalSeconds
        $record.finishedAtUtc = [DateTime]::UtcNow.ToString("o")
    }
    return [pscustomobject]$record
}
