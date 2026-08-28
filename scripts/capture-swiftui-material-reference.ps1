<#
.SYNOPSIS
Builds and captures the existing public material diagnostics after an SDK export.
.DESCRIPTION
Requires PowerShell 7 on the same Mac that completed export-swiftui-baseline.ps1.
Uses that export's exact XcodeDefault compiler and SDK with a fresh temporary
SwiftPM scratch directory. Results remain unreviewed candidates, including
inconclusive controls. Does not change pins, capture a desktop/window, or open
inventory.json. The caller's CI step must also have a 15 minute timeout.
The optional hosting experiment stays in the same UUID evidence directory,
after the unchanged canonical run. It cannot promote the canonical result.
.PARAMETER HostingContextExperiment
Also request the fixed accessory-policy unattached/unshown-window experiment.
Failed or interrupted checkpoints remain preserved, but fail this opt-in run.
#>
param(
    [string]$CaptureRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "artifacts/swiftui-baseline/github-actions/capture"),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "artifacts/swiftui-baseline/github-actions/material"),
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "docs/swiftui-baseline.json"),
    [switch]$HostingContextExperiment
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -lt 7 -or -not $IsMacOS) {
    throw "Material reference capture requires PowerShell 7 on macOS. Synthetic provenance tests are not native observations."
}
. (Join-Path $PSScriptRoot "swiftui-material-reference-common.ps1")
$repoRoot = Resolve-SwiftUIBaselineFileSystemPath (Split-Path -Parent $PSScriptRoot)
$artifactRoot = Resolve-SwiftUIBaselineFileSystemPath (Join-Path $repoRoot "artifacts")
$outputRoot = Resolve-SwiftUIBaselineFileSystemPath $OutputPath
[void](Get-SwiftUIBaselineRelativePath -Root $artifactRoot -Path $outputRoot)
if (Test-Path -LiteralPath $outputRoot) { throw "Material OutputPath must be new; existing evidence is never overwritten." }
[void](New-Item -ItemType Directory -Path $outputRoot)
$contextPath = Join-Path $outputRoot "context.json"
$commands = [System.Collections.Generic.List[object]]::new()
# Leave two minutes for failure evidence and the CI artifact upload.
$deadline = [DateTime]::UtcNow.AddMinutes(13)
$context = [ordered]@{
    schemaVersion = 1; evidenceKind = "native-material-observation-candidate"; status = "in-progress"
    baselineId = $null; checkedOutCommit = $null; eventCommit = $env:GITHUB_SHA
    repository = $env:GITHUB_REPOSITORY; runId = $env:GITHUB_RUN_ID; runAttempt = $env:GITHUB_RUN_ATTEMPT
    workflowRef = $env:GITHUB_WORKFLOW_REF; workflowCommit = $env:GITHUB_WORKFLOW_SHA; job = $env:GITHUB_JOB
    requestedRunnerLabel = "macos-26-intel"; runnerArchitecture = $env:RUNNER_ARCH
    imageOS = $env:ImageOS; imageVersion = $env:ImageVersion
    sdkCaptureManifestSha256 = $null; baselineManifestSha256 = $null
    materialManifestSha256 = $null; materialDirectory = $null; preservedDirectories = @()
    developerDirectoryOverride = $env:DEVELOPER_DIR; observedIdentity = $null
    swiftExecutable = $null; swiftExecutableSha256 = $null; sdkPath = $null; sdkSettingsSha256 = $null
    environmentPolicy = "Reject compiler, SwiftPM, SDK, driver, dynamic-library and header overrides; do not record values."
    rejectedEnvironmentOverrides = @()
    scratchPath = $null; buildConfiguration = "release"; swiftLanguageMode = "6"
    executable = $null; executableSha256 = $null; runtime = $null
    positiveControlStatus = $null; inconclusiveReasons = @(); commands = $commands
    qualification = [ordered]@{
        capturedEnvironmentMatched = $false; exactIdentityPreviouslyReviewed = $false
        nativeRuntimeBuildReviewed = $false; nativeBehaviorReviewed = $false
        behaviorConformanceVerified = $false; releaseQualified = $false
        note = "Candidate observations on one native architecture; SDK inventory targets are not native execution coverage."
    }
    startedAtUtc = [DateTime]::UtcNow.ToString("o"); finishedAtUtc = $null; error = $null
}
if ($HostingContextExperiment) {
    $context.hostingContextExperiment = [ordered]@{
        requested = $true; reportFile = "hosting-experiment.json"; reportSha256 = $null
        operationalStatus = $null; phase = $null; armControlStatuses = @()
        validationStatus = "not-observed"; protocolValidated = $false; capturedEnvironmentMatched = $false
        nativeCommandError = $null; preservationError = $null; reportValidationError = $null; contextWriteErrors = @()
        qualification = [ordered]@{
            nativeBehaviorReviewed = $false; nativeRuntimeBuildReviewed = $false; releaseQualified = $false
        }
        note = "Supplemental hosting observations only; no promotion of canonical classification or native qualification."
    }
}
Write-SwiftUIBaselineJson -Path $contextPath -Value $context

function Invoke-MaterialNative {
    param([string]$FilePath, [string[]]$Arguments, [int]$TimeoutSeconds = 30)
    $remaining = [int][Math]::Floor(($deadline - [DateTime]::UtcNow).TotalSeconds)
    if ($remaining -le 0) { throw "Material capture exhausted its 13 minute internal time budget." }
    $limit = [Math]::Min($TimeoutSeconds, $remaining)
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FilePath; $info.WorkingDirectory = $repoRoot
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.Environment["SWIFT_WINDOWSUI_REFERENCE_BUILD_CONFIGURATION"] = "release"
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $logPrefix = "command-{0:D3}" -f ($commands.Count + 1)
    $record = [ordered]@{
        executable = $FilePath; arguments = $Arguments; timeoutSeconds = $limit
        startedAtUtc = [DateTime]::UtcNow.ToString("o"); finishedAtUtc = $null
        exitCode = $null; timedOut = $false; stdoutFile = "$logPrefix.stdout.txt"; stderrFile = "$logPrefix.stderr.txt"; error = $null
    }
    $commands.Add($record)
    Write-SwiftUIBaselineJson -Path $contextPath -Value $context
    $process = [System.Diagnostics.Process]::new(); $process.StartInfo = $info
    $stdoutFile = $null; $stderrFile = $null; $wasStarted = $false
    try {
        $stdoutPath = Join-Path $outputRoot $record.stdoutFile
        $stderrPath = Join-Path $outputRoot $record.stderrFile
        $stdoutFile = [System.IO.File]::Open($stdoutPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        $stderrFile = [System.IO.File]::Open($stderrPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        [void]$process.Start()
        $wasStarted = $true
        # Stream raw bytes to evidence as they arrive, including partial output
        # when a timeout or surviving descendant leaves a redirected pipe open.
        $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($stdoutFile)
        $stderrTask = $process.StandardError.BaseStream.CopyToAsync($stderrFile)
        $record.timedOut = -not $process.WaitForExit($limit * 1000)
        if ($record.timedOut) { $process.Kill($true); [void]$process.WaitForExit(5000) }
        if (-not $process.HasExited) { throw "Native process did not terminate after timeout: $FilePath" }
        $record.exitCode = $process.ExitCode
        if (-not $stdoutTask.Wait(5000) -or -not $stderrTask.Wait(5000)) {
            throw "Native output streams did not close within the bounded shutdown interval: $FilePath"
        }
        $stdoutFile.Dispose(); $stdoutFile = $null
        $stderrFile.Dispose(); $stderrFile = $null
        if ($record.timedOut) { throw "Native command timed out after ${limit}s: $FilePath" }
        if ($record.exitCode -ne 0) { throw "Native command failed ($($record.exitCode)): $FilePath $($Arguments -join ' ')" }
        if ((Get-Item -LiteralPath $stdoutPath).Length -gt 16777216) { throw "Native stdout exceeds its 16 MiB metadata-read bound; raw output is preserved." }
        return [System.IO.File]::ReadAllText($stdoutPath).Trim()
    } catch {
        $record.error = $_.Exception.Message
        if ($wasStarted -and -not $process.HasExited) {
            try { $process.Kill($true); [void]$process.WaitForExit(5000) } catch { }
        }
        throw
    } finally {
        $record.finishedAtUtc = [DateTime]::UtcNow.ToString("o")
        $process.Dispose()
        if ($null -ne $stdoutFile) { $stdoutFile.Dispose() }
        if ($null -ne $stderrFile) { $stderrFile.Dispose() }
        Write-SwiftUIBaselineJson -Path $contextPath -Value $context
    }
}

function Save-MaterialRuns {
    param([string]$SourceRoot, [string[]]$ExistingNames)
    if (-not (Test-Path -LiteralPath $SourceRoot)) { return }
    foreach ($directory in @(Get-ChildItem -LiteralPath $SourceRoot -Directory | Where-Object { $ExistingNames -cnotcontains $_.Name })) {
        if ($directory.Name -notmatch '^[0-9A-Fa-f-]{36}$') { throw "Unexpected material capture directory name." }
        $source = Resolve-SwiftUIBaselineFileSystemPath $directory.FullName
        [void](Get-SwiftUIBaselineRelativePath -Root $SourceRoot -Path $source)
        $destination = Join-Path $outputRoot $directory.Name
        [void](New-Item -ItemType Directory -Path $destination)
        $context.preservedDirectories += $directory.Name
        # The unchanged diagnostic produces one flat directory. Copy every file,
        # even an incomplete report, before inspecting its classification.
        foreach ($file in @(Get-ChildItem -LiteralPath $source -Force)) {
            if ($file.PSIsContainer) { throw "Unexpected nested material evidence directory." }
            $safeFile = Get-SwiftUIMaterialEvidenceFile -Directory $source -Name $file.Name
            Copy-Item -LiteralPath $safeFile -Destination (Join-Path $destination $file.Name)
        }
        Write-Output $destination
    }
}

function Set-MaterialHostingExperimentContext {
    param([string]$Directory)
    try {
        # Save-MaterialRuns already preserved every flat file. Keep a bounded
        # digest even when the sidecar cannot pass its typed summary checks.
        $sidecarPath = Get-SwiftUIMaterialHostingEvidenceFile $Directory "hosting-experiment.json" 1048576
        $context.hostingContextExperiment.reportSha256 = (Get-FileHash -LiteralPath $sidecarPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $receipt = Get-SwiftUIMaterialHostingExperimentContext -Directory $Directory
        $context.hostingContextExperiment.reportSha256 = $receipt.reportSha256
        $context.hostingContextExperiment.operationalStatus = $receipt.operationalStatus
        $context.hostingContextExperiment.phase = $receipt.phase
        $context.hostingContextExperiment.armControlStatuses = @($receipt.armControlStatuses)
        $context.hostingContextExperiment.validationStatus = "checkpoint-only; not complete validation"
    } catch {
        $context.hostingContextExperiment.validationStatus = "rejected"
        $context.hostingContextExperiment.reportValidationError = $_.Exception.Message
    }
}

function Write-MaterialHostingContextPreservingFailure {
    param($PrimaryFailure, [string]$Stage, [scriptblock]$Writer = {
            Write-SwiftUIBaselineJson -Path $contextPath -Value $context
        })
    try { & $Writer } catch {
        if ($null -eq $PrimaryFailure) { throw }
        $message = $_.Exception.Message
        $context.hostingContextExperiment.contextWriteErrors += [ordered]@{ stage = $Stage; message = $message }
        $PrimaryFailure.Exception.Data["MaterialHostingContextWriteFailure:$Stage"] = $message
        # If persistence itself failed, retain the secondary failure on the
        # original exception and in stderr rather than replacing that error.
        Write-Warning "Material hosting $Stage context write also failed: $message. The original failure is preserved." -WarningAction Continue
    }
}

function Assert-MaterialCheckout {
    param([string]$ExpectedCommit)
    if ((Invoke-MaterialNative "/usr/bin/git" @("rev-parse", "HEAD")) -cne $ExpectedCommit -or
        -not [string]::IsNullOrEmpty((Invoke-MaterialNative "/usr/bin/git" @("status", "--porcelain", "--untracked-files=no")))) {
        throw "Material diagnostics require the same clean tracked source commit throughout the build and capture."
    }
    # Omit --exclude-standard intentionally: even ignored extra Swift sources
    # or package configuration can affect a build without changing its commit.
    $extraInputs = Invoke-MaterialNative "/usr/bin/git" @("ls-files", "--others", "--", ":(glob)Package*.swift",
        "Package.resolved", "Sources/macos-reference-renderer", ".swiftpm/configuration")
    if (-not [string]::IsNullOrEmpty($extraInputs)) { throw "Untracked or ignored material build inputs are not part of the recorded source commit." }
}

$hostingPrimaryFailure = $null
try {
    $context.rejectedEnvironmentOverrides = @(Get-SwiftUIMaterialEnvironmentOverrides ([Environment]::GetEnvironmentVariables()))
    if ($context.rejectedEnvironmentOverrides.Count -ne 0) {
        throw "Material capture rejects inherited build/runtime overrides: $($context.rejectedEnvironmentOverrides -join ', ')"
    }
    $sdk = Read-SwiftUIMaterialSDKContext -CaptureRoot $CaptureRoot -ManifestPath $ManifestPath
    $context.baselineId = $sdk.manifest.baselineId
    $context.sdkCaptureManifestSha256 = $sdk.captureManifestSha256
    $context.baselineManifestSha256 = $sdk.baselineManifestSha256
    $context.observedIdentity = $sdk.capture.observedIdentity
    $context.qualification.exactIdentityPreviouslyReviewed = $sdk.exactIdentityPreviouslyReviewed
    $context.swiftExecutable = $sdk.swiftTool.path; $context.swiftExecutableSha256 = $sdk.swiftTool.sha256
    $context.sdkPath = $sdk.capture.sdk.path; $context.sdkSettingsSha256 = $sdk.capture.sdk.settingsSha256
    if ($env:DEVELOPER_DIR -cne $sdk.capture.developerDirectoryOverride) { throw "DEVELOPER_DIR changed after SDK capture." }
    $commit = Invoke-MaterialNative "/usr/bin/git" @("rev-parse", "HEAD")
    if ($commit -cnotmatch '^[0-9a-f]{40}$' -or (-not [string]::IsNullOrEmpty($env:GITHUB_SHA) -and $commit -cne $env:GITHUB_SHA)) {
        throw "Checked-out source does not match the workflow event commit."
    }
    $context.checkedOutCommit = $commit
    Assert-MaterialCheckout $commit
    foreach ($arguments in @(@("--find", "swift"), @("--toolchain", "XcodeDefault", "--find", "swift"))) {
        if ((Invoke-MaterialNative "/usr/bin/xcrun" $arguments) -cne $sdk.swiftTool.path) { throw "Capture-time Swift lookup differs from the SDK export compiler." }
    }
    $sdkPath = Invoke-MaterialNative "/usr/bin/xcrun" @("--sdk", "macosx", "--show-sdk-path")
    if ($sdkPath -cne $sdk.capture.sdk.path) { throw "The selected SDK path changed after export." }
    $identity = ConvertTo-SwiftUIBaselineIdentity `
        -XcodeOutput (Invoke-MaterialNative "/usr/bin/xcodebuild" @("-version")) `
        -SDKVersion (Invoke-MaterialNative "/usr/bin/xcrun" @("--sdk", "macosx", "--show-sdk-version")) `
        -SDKBuildVersion (Invoke-MaterialNative "/usr/bin/xcrun" @("--sdk", "macosx", "--show-sdk-build-version")) `
        -SwiftOutput (Invoke-MaterialNative $sdk.swiftTool.path @("--version"))
    foreach ($field in @("xcodeVersion", "xcodeBuildVersion", "sdkVersion", "sdkBuildVersion", "swiftCompilerVersionLine")) {
        if ($identity.$field -cne $sdk.capture.observedIdentity.$field) { throw "Live $field changed after the SDK export." }
    }
    $osVersion = Invoke-MaterialNative "/usr/bin/sw_vers" @("-productVersion")
    $osBuild = Invoke-MaterialNative "/usr/bin/sw_vers" @("-buildVersion")
    $architecture = Invoke-MaterialNative "/usr/bin/uname" @("-m")
    if ($osVersion -cne $sdk.capture.host.macOSVersion -or $osBuild -cne $sdk.capture.host.macOSBuildVersion -or
        $architecture -cne "x86_64" -or $architecture -cne $sdk.capture.host.architecture) {
        throw "Material capture must run on the same native Intel Mac as this pinned-job SDK export."
    }
    $context.runtime = [ordered]@{ macOSVersion = $osVersion; macOSBuildVersion = $osBuild; architecture = $architecture; processArchitecture = $null }
    $temporaryRoot = Resolve-SwiftUIBaselineFileSystemPath ([System.IO.Path]::GetTempPath())
    $scratch = Resolve-SwiftUIBaselineFileSystemPath (Join-Path $temporaryRoot ("swift-windowsui-material-build-" + [Guid]::NewGuid().ToString("N")))
    [void](Get-SwiftUIBaselineRelativePath -Root $temporaryRoot -Path $scratch)
    if (Test-Path -LiteralPath $scratch) { throw "Material scratch directory unexpectedly exists." }
    [void](New-Item -ItemType Directory -Path $scratch)
    $context.scratchPath = $scratch
    # No root .build, cache restore, toolchain fallback, or shared SwiftPM process.
    $buildArguments = @("build", "--package-path", $repoRoot, "--scratch-path", $scratch, "--sdk", $sdkPath,
        "--configuration", "release", "--product", "macos-reference-renderer", "-Xswiftc", "-swift-version", "-Xswiftc", "6")
    Write-Host "Building the public material diagnostic with the captured compiler and SDK."
    [void](Invoke-MaterialNative $sdk.swiftTool.path $buildArguments -TimeoutSeconds 600)
    $binaryDirectory = Invoke-MaterialNative $sdk.swiftTool.path ($buildArguments + @("--show-bin-path"))
    $binary = Resolve-SwiftUIBaselineFileSystemPath (Join-Path $binaryDirectory "macos-reference-renderer")
    [void](Get-SwiftUIBaselineRelativePath -Root $scratch -Path $binary)
    $binaryHash = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
    $context.executable = $binary; $context.executableSha256 = $binaryHash
    [void](Invoke-MaterialNative $binary @("--self-test-material-diagnostics") -TimeoutSeconds 30)
    $sourceRoot = Resolve-SwiftUIBaselineFileSystemPath (Join-Path $repoRoot "artifacts/macos-reference/material-diagnostics")
    [void](Get-SwiftUIBaselineRelativePath -Root $artifactRoot -Path $sourceRoot)
    $existingNames = @()
    if (Test-Path -LiteralPath $sourceRoot) { $existingNames = @(Get-ChildItem -LiteralPath $sourceRoot -Directory | ForEach-Object { $_.Name }) }
    Write-Host "Capturing native material candidates; inconclusive controls will be retained."
    $materialArguments = @("--material-diagnostics")
    if ($HostingContextExperiment) { $materialArguments += "--hosting-context-experiment" }
    $hostingCaptureFailure = $null
    try {
        if ($HostingContextExperiment) {
            try { [void](Invoke-MaterialNative $binary $materialArguments -TimeoutSeconds 120) }
            catch {
                $hostingCaptureFailure = $_
                $context.hostingContextExperiment.nativeCommandError = $_.Exception.Message
            }
        } else { [void](Invoke-MaterialNative $binary $materialArguments -TimeoutSeconds 120) }
    } finally {
        try { $saved = @(Save-MaterialRuns -SourceRoot $sourceRoot -ExistingNames $existingNames) }
        catch {
            if ($HostingContextExperiment) {
                $context.hostingContextExperiment.preservationError = $_.Exception.Message
                if ($null -ne $hostingCaptureFailure) { throw $hostingCaptureFailure }
            }
            throw
        }
        if ($HostingContextExperiment -and $saved.Count -eq 1) {
            Set-MaterialHostingExperimentContext -Directory $saved[0]
            Write-MaterialHostingContextPreservingFailure -PrimaryFailure $hostingCaptureFailure -Stage "capture-checkpoint"
        }
    }
    if ($null -ne $hostingCaptureFailure) { throw $hostingCaptureFailure }
    if ($saved.Count -ne 1) { throw "Expected one fresh native material capture directory, found $($saved.Count)." }
    $observation = Read-SwiftUIMaterialObservation -Directory $saved[0] -SDKContext $sdk -ExpectedCommit $commit `
        -ExpectedExecutableSha256 $binaryHash -ExpectedArchitecture $architecture
    $hostingObservation = $null
    if ($HostingContextExperiment) {
        try {
            $hostingObservation = Read-SwiftUIMaterialHostingExperiment -Directory $saved[0] -SDKContext $sdk -ExpectedCommit $commit `
                -ExpectedExecutableSha256 $binaryHash -ExpectedArchitecture $architecture
        } catch {
            $context.hostingContextExperiment.validationStatus = "rejected"
            $context.hostingContextExperiment.reportValidationError = $_.Exception.Message
            throw
        }
    }
    # Recheck the build inputs and output after the subprocesses finish.
    $after = Read-SwiftUIMaterialSDKContext -CaptureRoot $CaptureRoot -ManifestPath $ManifestPath
    if ($after.captureManifestSha256 -cne $sdk.captureManifestSha256 -or $after.baselineManifestSha256 -cne $sdk.baselineManifestSha256) {
        throw "SDK capture or baseline manifest changed during material build/capture."
    }
    [void](Assert-SwiftUIMaterialFileHash $binary $binaryHash)
    Assert-MaterialCheckout $commit
    $context.materialDirectory = Split-Path -Leaf $saved[0]
    $context.materialManifestSha256 = $observation.manifestSha256
    $context.runtime.processArchitecture = $observation.architecture
    $context.positiveControlStatus = $observation.positiveControlStatus
    $context.inconclusiveReasons = @($observation.manifest.inconclusiveReasons)
    $context.qualification.capturedEnvironmentMatched = $true
    if ($HostingContextExperiment) {
        $context.hostingContextExperiment.reportSha256 = $hostingObservation.reportSha256
        $context.hostingContextExperiment.operationalStatus = $hostingObservation.operationalStatus
        $context.hostingContextExperiment.armControlStatuses = @($hostingObservation.armControlStatuses)
        $context.hostingContextExperiment.validationStatus = "complete-protocol-validated; native behavior unreviewed"
        $context.hostingContextExperiment.protocolValidated = $true
        $context.hostingContextExperiment.capturedEnvironmentMatched = $true
    }
    $context.status = "captured-awaiting-review"
    Write-Host "Material candidate: $($context.positiveControlStatus). Native behavior and runtime-build review remain outstanding."
} catch {
    if ($HostingContextExperiment) { $hostingPrimaryFailure = $_ }
    $context.status = "failed"; $context.error = $_.Exception.Message
    throw
} finally {
    $context.finishedAtUtc = [DateTime]::UtcNow.ToString("o")
    if ($HostingContextExperiment) {
        Write-MaterialHostingContextPreservingFailure -PrimaryFailure $hostingPrimaryFailure -Stage "final"
    } else { Write-SwiftUIBaselineJson -Path $contextPath -Value $context }
}
