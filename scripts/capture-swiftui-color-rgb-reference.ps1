<#
.SYNOPSIS
Collects immutable canonical RGB constructor candidates on Windows or macOS.
.DESCRIPTION
Windows reserves the repository .build directory for serial release SwiftPM
commands through with-swift.ps1. Native requires a complete sealed pinned SDK
capture and uses its XcodeDefault compiler directly. No window, event loop,
screen capture, global setting, inventory read, or API-claim promotion occurs.
The caller must reserve the build directory and authorize actual execution.
Failed/unsupported evidence remains at the new output path; never retry there.
#>
param(
    [Parameter(Mandatory)][ValidateSet("Windows", "Native")][string]$Platform,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$CaptureRoot,
    [string]$ManifestPath
)

$ErrorActionPreference = "Stop"
$Platform = if ($Platform -ieq "Windows") { "Windows" } else { "Native" }
. (Join-Path $PSScriptRoot "swiftui-color-rgb-reference-common.ps1")
if (-not $PSBoundParameters.ContainsKey("ManifestPath")) {
    $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) "docs/swiftui-baseline.json"
}
$rgbRepository = (Resolve-SwiftUIBaselineFileSystemPath (Split-Path -Parent $PSScriptRoot)).Replace('\', '/')
$rgbOutput = (New-SwiftUIColorRGBOutputRoot -Path $OutputPath -RepositoryRoot $rgbRepository -ExcludedRoots @($CaptureRoot)).Replace('\', '/')
$rgbProtocol = Get-SwiftUIColorRGBProtocol
$rgbCaptureId = [Guid]::NewGuid().ToString("D")
$rgbCommands = [System.Collections.Generic.List[object]]::new()
$rgbBootstrap = [System.Collections.Generic.List[object]]::new()
$rgbRuns = [System.Collections.Generic.List[object]]::new()
$rgbFailures = [System.Collections.Generic.List[string]]::new()
$rgbSourceOriginals = [System.Collections.Generic.List[object]]::new()
$rgbAuxiliary = [System.Collections.Generic.List[object]]::new()
$rgbSequence = 0; $rgbPreparedSequence = 0; $rgbStopCommands = $false
$rgbDeadline = [DateTime]::UtcNow.AddMinutes(30)
$rgbHelperPath = $null; $rgbWindowsIdentity = $null; $rgbSDKContext = $null
$rgbManifest = [pscustomobject][ordered]@{
    schemaVersion = 1; evidenceKind = "color-rgb-reference-candidate"
    protocolId = $rgbProtocol.protocolId; caseSetId = $rgbProtocol.caseSetId; toleranceId = $rgbProtocol.toleranceId
    captureId = $rgbCaptureId; originalOutputRoot = $rgbOutput; platform = $Platform.ToLowerInvariant(); status = "failure"
    startedAtUtc = [DateTime]::UtcNow.ToString("o"); finishedAtUtc = $null
    source = $null
    sourceCompilation = [pscustomobject]@{ state = "not-run"; typechecks = @(); buildCommandId = $null; buildTarget = $null; moduleCacheRoot = $null; binaryPathCommandId = $null }
    runtimeEligibility = [pscustomobject]@{ state = "not-evaluated"; reason = "collection-not-started"; processArchitecture = $null; hardwareArchitecture = $null; translated = $null; operatingSystemVersion = $null; operatingSystemBuild = $null }
    toolchain = $null; sdk = $null; binary = $null
    commands = @(); bootstrapCommands = @(); runs = @(); auxiliaryFiles = @(); observerControls = @()
    integrity = [pscustomobject]@{ sourceUnchanged = $false; toolsUnchanged = $false; executableUnchanged = $false; sdkCaptureUnchanged = ($Platform -ceq "Windows") }
    qualification = [pscustomobject]@{ declarationReview = "unverified"; sourceReview = "unverified"; behaviorReview = "unverified"; releaseQualified = $false }
    failureCodes = @()
}
$rgbStartPath = Join-Path $rgbOutput "capture-start.json"
Write-SwiftUIColorRGBJsonNew -Path $rgbStartPath -Value ([pscustomobject]@{
    schemaVersion = 1; protocolId = $rgbProtocol.protocolId; captureId = $rgbCaptureId
    startedAtUtc = $rgbManifest.startedAtUtc; status = "started; no completed evidence yet"
})
$rgbAuxiliary.Add((Get-SwiftUIColorRGBFileRecord $rgbStartPath "capture-start.json"))

function Invoke-RGBDirect {
    param([string]$FilePath, [string[]]$Arguments = @(), [int]$TimeoutSeconds = 30,
        [System.Collections.IDictionary]$EnvironmentOverrides = @{})
    if ($script:rgbStopCommands) { throw "RGB_PREVIOUS_PROCESS_CLEANUP_UNVERIFIED" }
    $remaining = [int][Math]::Floor(($script:rgbDeadline - [DateTime]::UtcNow).TotalSeconds)
    if ($remaining -lt 1) { throw "RGB_COLLECTION_DEADLINE_EXCEEDED" }
    $script:rgbSequence++
    $id = "command-{0:D3}" -f $script:rgbSequence
    $record = Invoke-SwiftUIColorRGBProcess -FilePath $FilePath.Replace('\', '/') -Arguments $Arguments -WorkingDirectory $script:rgbRepository `
        -EvidenceRoot $script:rgbOutput -CommandId $id -TimeoutSeconds ([Math]::Min($TimeoutSeconds, $remaining)) -EnvironmentOverrides $EnvironmentOverrides
    $script:rgbCommands.Add($record)
    if ($record.state -cne "exited") { $script:rgbStopCommands = $true }
    return $record
}

function Get-RGBCommandText {
    param($Command, [int]$MaxBytes = 65536)
    if (-not (Test-SwiftUIColorRGBCommandSucceeded $Command)) { throw "RGB_REQUIRED_COMMAND_FAILED" }
    return (Read-SwiftUIColorRGBText (Get-SwiftUIColorRGBEvidencePath $script:rgbOutput $Command.stdout.evidenceFile) $MaxBytes).Trim()
}

function Invoke-RGBGit {
    param([string[]]$Arguments, [int]$MaxBytes = 1048576)
    $git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    return Get-RGBCommandText (Invoke-RGBDirect $git $Arguments) $MaxBytes
}

function Assert-RGBCheckout {
    param([string]$ExpectedCommit, [string]$ExpectedTree)
    $commit = Invoke-RGBGit @("rev-parse", "HEAD")
    $tree = Invoke-RGBGit @("rev-parse", "HEAD^{tree}")
    if ($commit -cnotmatch '^[0-9a-f]{40}$' -or $tree -cnotmatch '^[0-9a-f]{40}$' -or
        (-not [string]::IsNullOrEmpty($ExpectedCommit) -and $commit -cne $ExpectedCommit) -or
        (-not [string]::IsNullOrEmpty($ExpectedTree) -and $tree -cne $ExpectedTree)) { throw "RGB_SOURCE_COMMIT_OR_TREE_CHANGED" }
    if (-not [string]::IsNullOrEmpty((Invoke-RGBGit @("status", "--porcelain", "--untracked-files=no")))) { throw "RGB_SOURCE_CHECKOUT_DIRTY" }
    $flags = Invoke-RGBGit @("ls-files", "-v") 2097152
    foreach ($line in ($flags -split "`n")) { if (-not $line.StartsWith("H ", [StringComparison]::Ordinal)) { throw "RGB_SOURCE_INDEX_FLAGS_UNSUPPORTED" } }
    # Even ignored extra inputs can alter SwiftPM or the explicit five-file
    # native fixture. Do not let an untracked source become unrecorded input.
    $extra = Invoke-RGBGit @("ls-files", "--others", "--", "Sources", "Package.swift", "Package.resolved", ".swiftpm/configuration")
    if (-not [string]::IsNullOrEmpty($extra)) { throw "RGB_UNTRACKED_OR_IGNORED_BUILD_INPUT" }
    return [pscustomobject]@{ commit = $commit; tree = $tree }
}

function Copy-RGBSourceEntries {
    param([string[]]$Names, [string]$Group)
    $entries = [System.Collections.Generic.List[object]]::new()
    [long]$total = 0
    foreach ($name in $Names) {
        if ($name -cnotmatch '^[A-Za-z0-9._/-]+$' -or $name -match '(^|/)\.\.?(/|$)') { throw "RGB_SOURCE_PATH_UNSUPPORTED" }
        $source = Resolve-SwiftUIBaselineFileSystemPath (Join-Path $script:rgbRepository $name)
        [void](Get-SwiftUIBaselineRelativePath -Root $script:rgbRepository -Path $source)
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "RGB_SOURCE_INPUT_MISSING" }
        $length = (Get-Item -LiteralPath $source).Length; $total += $length
        if ($length -gt 33554432 -or $total -gt 134217728) { throw "RGB_SOURCE_SNAPSHOT_BYTE_LIMIT" }
        $blob = $script:rgbGitBlobs[$name]
        if ($null -eq $blob -or $blob -cnotmatch '^[0-9a-f]{40}$') { throw "RGB_SOURCE_NOT_IN_COMMIT" }
        $relative = "sources/$Group/$name"; $destination = Join-Path $script:rgbOutput $relative
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        $before = Get-SwiftUIColorRGBHash $source
        [IO.File]::Copy($source, $destination, $false)
        $file = Get-SwiftUIColorRGBFileRecord $destination $relative
        if ($file.sha256 -cne $before -or (Get-SwiftUIColorRGBHash $source) -cne $before) { throw "RGB_SOURCE_CHANGED_DURING_COPY" }
        $byteIdentity = Get-SwiftUIColorRGBSourceByteIdentity $destination $blob
        $entries.Add([pscustomobject]@{ path = $name; gitBlob = $blob; byteIdentity = $byteIdentity; file = $file })
        $script:rgbSourceOriginals.Add([pscustomobject]@{ path = $source; sha256 = $before; bytes = $length })
    }
    return ,@($entries.ToArray())
}

function New-RGBSourceSnapshot {
    $identity = Assert-RGBCheckout
    $listing = Invoke-RGBGit @("-c", "core.quotepath=false", "ls-tree", "-r", "HEAD") 2097152
    $script:rgbGitBlobs = @{}
    foreach ($line in ($listing -split "`n")) {
        if ($line -match '^100(?:644|755) blob ([0-9a-f]{40})\t(.+)\r?$') { $script:rgbGitBlobs[$matches[2].TrimEnd("`r")] = $matches[1] }
    }
    $sharedNames = @(Get-SwiftUIColorRGBSourceNames)
    $buildNames = @($sharedNames) + @("Package.swift")
    if ($script:Platform -ceq "Windows") {
        $buildNames = @($script:rgbGitBlobs.Keys | Where-Object { $_.StartsWith("Sources/", [StringComparison]::Ordinal) -or $_ -cin @("Package.swift", "Package.resolved") -or $_.StartsWith(".swiftpm/configuration/", [StringComparison]::Ordinal) } | Sort-Object -CaseSensitive)
    }
    if ($buildNames.Count -lt 1 -or $buildNames.Count -gt 4096) { throw "RGB_BUILD_INPUT_COUNT_LIMIT" }
    $collectorNames = @(
        "scripts/capture-swiftui-color-rgb-reference.ps1", "scripts/swiftui-color-rgb-reference-common.ps1",
        "scripts/compare-swiftui-color-rgb-reference.ps1", "scripts/swiftui-material-reference-common.ps1",
        "scripts/swiftui-baseline-common.ps1", "scripts/with-swift.ps1", "docs/swiftui-baseline.json"
    )
    return [pscustomobject]@{
        repositoryRoot = $script:rgbRepository; commit = $identity.commit; tree = $identity.tree; clean = $true
        sharedSources = Copy-RGBSourceEntries $sharedNames "shared"
        buildInputs = Copy-RGBSourceEntries $buildNames "build-inputs"
        collectorSources = Copy-RGBSourceEntries $collectorNames "collector"
    }
}

function Initialize-RGBWindowsHelper {
    $commonPath = Join-Path $PSScriptRoot "swiftui-color-rgb-reference-common.ps1"
    $commonEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($commonPath))
    # BOM-less UTF-8 .ps1 is ANSI to Windows PowerShell 5.1. Keep this helper
    # entirely ASCII, including a checkout path containing non-ASCII characters.
    $text = "param([Parameter(Mandatory)][string]`$RequestPath)`n`$ErrorActionPreference = 'Stop'`n`$rgbCommonPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$commonEncoded'))`n. `$rgbCommonPath`nInvoke-SwiftUIColorRGBPreparedWindowsRequest -RequestPath `$RequestPath`n"
    $script:rgbHelperPath = Join-Path $script:rgbOutput "windows-prepared-command.ps1"
    Write-SwiftUIColorRGBTextNew $script:rgbHelperPath $text
    $script:rgbAuxiliary.Add((Get-SwiftUIColorRGBFileRecord $script:rgbHelperPath "windows-prepared-command.ps1"))
}

function Invoke-RGBPrepared {
    param([string]$Action, [string]$FilePath = "", [string[]]$Arguments = @(), [int]$TimeoutSeconds = 30)
    if ($script:rgbStopCommands) { throw "RGB_PREVIOUS_PROCESS_CLEANUP_UNVERIFIED" }
    $remaining = [int][Math]::Floor(($script:rgbDeadline - [DateTime]::UtcNow).TotalSeconds)
    if ($remaining -lt 15) { throw "RGB_COLLECTION_DEADLINE_EXCEEDED" }
    $script:rgbPreparedSequence++; $script:rgbSequence++
    $id = "command-{0:D3}" -f $script:rgbSequence
    $prefix = "prepared-{0:D3}" -f $script:rgbPreparedSequence
    $requestPath = Join-Path $script:rgbOutput "$prefix.request.json"
    $resultName = "$prefix.result.json"; $resultPath = Join-Path $script:rgbOutput $resultName
    $runId = [Guid]::NewGuid().ToString("D")
    Write-SwiftUIColorRGBJsonNew -Path $requestPath -Value ([pscustomobject]@{
        action = $Action; runId = $runId; repositoryRoot = $script:rgbRepository; evidenceRoot = $script:rgbOutput
        resultFile = $resultName; commandId = $id; filePath = $FilePath; arguments = @($Arguments)
        timeoutSeconds = [Math]::Min($TimeoutSeconds, $remaining - 10); maxLogBytes = 16777216
    })
    $script:rgbAuxiliary.Add((Get-SwiftUIColorRGBFileRecord $requestPath "$prefix.request.json"))
    $powerShell = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
    $literalArguments = @($powerShell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script:rgbHelperPath, "-RequestPath", $requestPath) |
        ForEach-Object { "'" + $_.Replace("'", "''") + "'" }
    $withSwift = (Join-Path $PSScriptRoot "with-swift.ps1").Replace("'", "''")
    $program = "& '$withSwift' -Command @(" + ($literalArguments -join ',') + ")"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($program))
    $bootstrapId = "bootstrap-{0:D3}" -f $script:rgbPreparedSequence
    $bootstrap = Invoke-SwiftUIColorRGBProcess -FilePath $powerShell.Replace('\', '/') -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded) `
        -WorkingDirectory $script:rgbRepository -EvidenceRoot $script:rgbOutput -CommandId $bootstrapId -TimeoutSeconds ([Math]::Min($TimeoutSeconds + 10, $remaining))
    $script:rgbBootstrap.Add($bootstrap)
    if ($bootstrap.state -cne "exited") { $script:rgbStopCommands = $true; throw "RGB_WINDOWS_PREPARATION_CLEANUP_UNVERIFIED" }
    if (-not (Test-SwiftUIColorRGBCommandSucceeded $bootstrap) -or -not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { throw "RGB_WINDOWS_PREPARED_RESULT_MISSING" }
    $result = Read-SwiftUIColorRGBJson $resultPath -MaxBytes 1048576
    $script:rgbAuxiliary.Add((Get-SwiftUIColorRGBFileRecord $resultPath $resultName))
    if ($Action -ceq "identity") {
        if ($result.runId -cne $runId -or $result.environmentContentsRecorded -ne $false) { throw "RGB_WINDOWS_PREPARED_IDENTITY_MISMATCH" }
        return $result
    }
    Assert-SwiftUIColorRGBCommandRecord $script:rgbOutput $result
    if ($result.commandId -cne $id -or $result.arguments.Count -ne $Arguments.Count) { throw "RGB_WINDOWS_PREPARED_COMMAND_MISMATCH" }
    for ($index = 0; $index -lt $Arguments.Count; $index++) { if ($result.arguments[$index] -cne $Arguments[$index]) { throw "RGB_WINDOWS_PREPARED_COMMAND_MISMATCH" } }
    $script:rgbCommands.Add($result)
    if ($result.state -cne "exited") { $script:rgbStopCommands = $true }
    return $result
}

function Copy-RGBSDKMetadata {
    param($Context)
    $names = [ordered]@{ capture = "capture.json"; status = "capture-status.json"; seal = "capture.sha256"; baseline = "baseline-manifest.json"; settings = $Context.capture.sdk.settingsPath }
    $files = [ordered]@{}
    [void][IO.Directory]::CreateDirectory((Join-Path $script:rgbOutput "sdk"))
    foreach ($key in $names.Keys) {
        $source = Get-SwiftUIMaterialEvidenceFile $script:CaptureRoot $names[$key]
        if ((Get-Item -LiteralPath $source).Length -gt 16777216) { throw "RGB_SDK_METADATA_BYTE_LIMIT" }
        $relative = "sdk/$($names[$key])"; $destination = Join-Path $script:rgbOutput $relative
        [IO.File]::Copy($source, $destination, $false)
        $files[$key] = Get-SwiftUIColorRGBFileRecord $destination $relative
    }
    return [pscustomobject]@{
        validationMethod = "Read-SwiftUIMaterialSDKContext"; beforeVerified = $true; afterVerified = $false
        captureRoot = $script:CaptureRoot; baselineId = $Context.manifest.baselineId
        observedIdentity = $Context.capture.observedIdentity; files = [pscustomobject]$files
    }
}

function Read-RGBPinnedSDK {
    # The shared version normalizer is an explicit upstream dependency. Never
    # duplicate or relax its policy to accept a driver-prefix mismatch here.
    return Read-SwiftUIColorRGBPinnedSDKContext -CaptureRoot $script:CaptureRoot -ManifestPath $script:ManifestPath
}

function Test-RGBToolFilesUnchanged {
    foreach ($tool in $script:rgbManifest.toolchain.tools) {
        if (-not (Test-Path -LiteralPath $tool.path -PathType Leaf) -or (Get-Item -LiteralPath $tool.path).Length -ne $tool.bytes -or
            (Get-SwiftUIColorRGBHash $tool.path) -cne $tool.sha256) { throw "RGB_TOOL_CHANGED_DURING_COLLECTION" }
    }
}

function Invoke-RGBObserver {
    param([string]$Observer, [int]$Repetition)
    $runId = [Guid]::NewGuid().ToString("D")
    $reportName = "$Observer-$Repetition.json"; $reportPath = (Join-Path $script:rgbOutput $reportName).Replace('\', '/')
    $arguments = @("--observer", $Observer, "--run-id", $runId, "--output", $reportPath)
    $binary = $script:rgbManifest.binary.originalPath
    if ($script:Platform -ceq "Windows") { $command = Invoke-RGBPrepared "run" $binary $arguments 30 }
    else { $command = Invoke-RGBDirect $binary $arguments 30 }
    $run = [pscustomobject]@{ observer = $Observer; repetition = $Repetition; runId = $runId; commandId = $command.commandId; report = $null; reportState = "missing"; reasonCode = "RGB_OBSERVER_REPORT_MISSING" }
    if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
        $run.report = Get-SwiftUIColorRGBFileRecord $reportPath $reportName
        $run.reportState = "invalid"; $run.reasonCode = "RGB_OBSERVER_REPORT_INVALID"
        try {
            if ($run.report.bytes -gt 2097152) { throw "RGB_OBSERVER_REPORT_BYTE_LIMIT" }
            if (-not (Test-SwiftUIColorRGBCommandSucceeded $command)) { throw "RGB_OBSERVER_PROCESS_FAILED" }
            if ($command.executableSha256 -cne $script:rgbManifest.binary.file.sha256) { throw "RGB_OBSERVER_EXECUTABLE_CHANGED" }
            $validated = Read-SwiftUIColorRGBReport $reportPath $Observer $runId $script:rgbManifest.runtimeEligibility.processArchitecture
            if ($validated.report.runtime.processId -ne $command.processId) { throw "RGB_OBSERVER_PID_MISMATCH" }
            $runtimeVersion = [version]$validated.report.runtime.operatingSystemVersion
            $hostVersion = [version]$script:rgbManifest.runtimeEligibility.operatingSystemVersion
            if ($runtimeVersion.Major -ne $hostVersion.Major -or $runtimeVersion.Minor -ne $hostVersion.Minor -or
                $runtimeVersion.Build -ne $hostVersion.Build) { throw "RGB_OBSERVER_OS_VERSION_MISMATCH" }
            $run.reportState = "valid"; $run.reasonCode = $null
        } catch {
            $code = [regex]::Match($_.Exception.Message, '^RGB_[A-Z0-9_]+').Value
            if (-not [string]::IsNullOrEmpty($code)) { $run.reasonCode = $code }
        }
    }
    $script:rgbRuns.Add($run)
    if ($run.reportState -cne "valid") { $script:rgbFailures.Add($run.reasonCode) }
    if ($script:rgbStopCommands) { throw "RGB_OBSERVER_CLEANUP_UNVERIFIED" }
}

try {
    $parserPath = Join-Path $rgbOutput "json-parser-identity.json"
    Write-SwiftUIColorRGBJsonNew $parserPath (Get-SwiftUIColorRGBJsonParserIdentity)
    $rgbAuxiliary.Add((Get-SwiftUIColorRGBFileRecord $parserPath "json-parser-identity.json"))
    $isWindowsHost = [IO.Path]::DirectorySeparatorChar -eq '\'
    $isNativeHost = $PSVersionTable.PSVersion.Major -ge 7 -and $null -ne (Get-Variable IsMacOS -ErrorAction SilentlyContinue) -and (Get-Variable IsMacOS -ValueOnly)
    if (($Platform -ceq "Windows" -and -not $isWindowsHost) -or ($Platform -ceq "Native" -and -not $isNativeHost)) {
        $rgbManifest.status = "unsupported"; $rgbManifest.runtimeEligibility.state = "unsupported"; $rgbManifest.runtimeEligibility.reason = "requested-platform-unavailable"
    } else {
        $rgbManifest.source = New-RGBSourceSnapshot
        if ($Platform -ceq "Windows") {
            $overrides = @(Get-SwiftUIColorRGBWindowsEnvironmentOverrides ([Environment]::GetEnvironmentVariables()))
            if ($overrides.Count -gt 0) { throw "RGB_WINDOWS_ENVIRONMENT_OVERRIDE_REJECTED" }
            Initialize-RGBWindowsHelper
            $rgbWindowsIdentity = Invoke-RGBPrepared "identity"
            if ($rgbWindowsIdentity.processArchitecture -cnotin @("x86_64", "arm64") -or $rgbWindowsIdentity.hardwareArchitecture -cnotin @("x86_64", "arm64")) { throw "RGB_WINDOWS_ARCHITECTURE_UNSUPPORTED" }
            $versionCommand = Invoke-RGBPrepared "run" "swift" @("--version")
            $version = Get-RGBCommandText $versionCommand
            if ($version -notmatch '(?m)^Swift version [0-9]+\.[0-9]+') { throw "RGB_WINDOWS_SWIFT_VERSION_UNRECOGNIZED" }
            $rgbManifest.toolchain = [pscustomobject]@{ kind = "windows-with-swift"; versionLine = ($version -split "`n")[0].TrimEnd("`r"); sdkPath = $rgbWindowsIdentity.sdkPath; tools = @($rgbWindowsIdentity.tools); versionCommands = @([pscustomobject]@{ role = "swift"; commandId = $versionCommand.commandId }) }
            $rgbManifest.runtimeEligibility = [pscustomobject]@{
                state = "eligible"; reason = $null; processArchitecture = $rgbWindowsIdentity.processArchitecture
                hardwareArchitecture = $rgbWindowsIdentity.hardwareArchitecture; translated = $rgbWindowsIdentity.translated
                operatingSystemVersion = $rgbWindowsIdentity.operatingSystemVersion; operatingSystemBuild = $rgbWindowsIdentity.operatingSystemBuild
            }
            $rgbManifest.sourceCompilation.state = "failure"
            $build = Invoke-RGBPrepared "run" "swift" @("build", "--package-path", $rgbRepository, "--configuration", "release", "--product", "swiftui-color-rgb-reference") 1200
            $rgbManifest.sourceCompilation.buildCommandId = $build.commandId
            $targetArchitecture = if ($rgbWindowsIdentity.processArchitecture -ceq "arm64") { "aarch64" } else { "x86_64" }
            $rgbManifest.sourceCompilation.buildTarget = "$targetArchitecture-unknown-windows-msvc"
            [void](Get-RGBCommandText $build 16777216)
            $binCommand = Invoke-RGBPrepared "run" "swift" @("build", "--package-path", $rgbRepository, "--configuration", "release", "--show-bin-path") 60
            $rgbManifest.sourceCompilation.binaryPathCommandId = $binCommand.commandId
            $binDirectory = Get-RGBCommandText $binCommand
            if ($binDirectory -match '[\r\n]' -or -not [IO.Path]::IsPathRooted($binDirectory)) { throw "RGB_WINDOWS_BIN_PATH_INVALID" }
            $binary = (Resolve-SwiftUIBaselineFileSystemPath (Join-Path $binDirectory "swiftui-color-rgb-reference.exe")).Replace('\', '/')
            [void](Get-SwiftUIBaselineRelativePath -Root (Join-Path $rgbRepository ".build") -Path $binary)
            $savedBinary = Join-Path $rgbOutput "reference-executable.exe"
            [IO.File]::Copy($binary, $savedBinary, $false)
            $rgbManifest.binary = [pscustomobject]@{ originalPath = $binary; file = Get-SwiftUIColorRGBFileRecord $savedBinary "reference-executable.exe" }
            $rgbManifest.sourceCompilation.state = "compiled"
            for ($repetition = 1; $repetition -le 3; $repetition++) { Invoke-RGBObserver "windows-retained" $repetition }
        } else {
            if ([string]::IsNullOrWhiteSpace($CaptureRoot)) { throw "RGB_NATIVE_CAPTURE_ROOT_REQUIRED" }
            $CaptureRoot = Resolve-SwiftUIBaselineFileSystemPath $CaptureRoot
            $overrides = @(Get-SwiftUIMaterialEnvironmentOverrides ([Environment]::GetEnvironmentVariables()))
            if ($overrides.Count -gt 0) { throw "RGB_NATIVE_ENVIRONMENT_OVERRIDE_REJECTED" }
            $rgbSDKContext = Read-RGBPinnedSDK
            $rgbManifest.sdk = Copy-RGBSDKMetadata $rgbSDKContext
            $developer = $rgbSDKContext.capture.developerDirectoryOverride
            $toolDirectory = Split-Path -Parent $rgbSDKContext.swiftTool.path
            $tools = @(
                foreach ($name in @("swift", "swiftc", "swift-frontend")) {
                    $lexicalPath = Join-Path $toolDirectory $name
                    $resolved = Resolve-SwiftUIBaselineFileSystemPath $lexicalPath
                    [void](Get-SwiftUIBaselineRelativePath -Root $developer -Path $lexicalPath)
                    [void](Get-SwiftUIBaselineRelativePath -Root (Resolve-SwiftUIBaselineFileSystemPath $toolDirectory) -Path $resolved)
                    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "RGB_NATIVE_COMPILER_MISSING" }
                    [pscustomobject]@{ role = $name; path = $lexicalPath; sha256 = Get-SwiftUIColorRGBHash $lexicalPath; bytes = (Get-Item -LiteralPath $lexicalPath).Length }
                }
            )
            $childEnvironment = @{ DEVELOPER_DIR = $developer }
            $xcode = Get-RGBCommandText (Invoke-RGBDirect (Join-Path $developer "usr/bin/xcodebuild") @("-version") 30 $childEnvironment)
            $swiftVersionCommand = Invoke-RGBDirect $tools[0].path @("--version") 30 $childEnvironment
            $compilerVersionCommand = Invoke-RGBDirect $tools[1].path @("--version") 30 $childEnvironment
            $frontendVersionCommand = Invoke-RGBDirect $tools[2].path @("--version") 30 $childEnvironment
            $swiftVersion = Get-RGBCommandText $swiftVersionCommand
            $compilerVersion = Get-RGBCommandText $compilerVersionCommand
            $frontendVersion = Get-RGBCommandText $frontendVersionCommand
            $sdkVersion = Get-RGBCommandText (Invoke-RGBDirect "/usr/bin/xcrun" @("--sdk", "macosx", "--show-sdk-version") 30 $childEnvironment)
            $sdkBuild = Get-RGBCommandText (Invoke-RGBDirect "/usr/bin/xcrun" @("--sdk", "macosx", "--show-sdk-build-version") 30 $childEnvironment)
            $sdkPath = Get-RGBCommandText (Invoke-RGBDirect "/usr/bin/xcrun" @("--sdk", "macosx", "--show-sdk-path") 30 $childEnvironment)
            if ((Resolve-SwiftUIBaselineFileSystemPath $sdkPath) -cne (Resolve-SwiftUIBaselineFileSystemPath $rgbSDKContext.capture.sdk.path)) { throw "RGB_NATIVE_SELECTED_SDK_PATH_MISMATCH" }
            foreach ($versionText in @($swiftVersion, $compilerVersion, $frontendVersion)) {
                $identity = ConvertTo-SwiftUIBaselineIdentity -XcodeOutput $xcode -SDKVersion $sdkVersion -SDKBuildVersion $sdkBuild -SwiftOutput $versionText
                [void](Assert-SwiftUIBaselineIdentity -Manifest $rgbSDKContext.manifest -Identity $identity)
                foreach ($field in @("xcodeVersion", "xcodeBuildVersion", "sdkVersion", "sdkBuildVersion", "swiftCompilerVersion", "swiftCompilerVersionLine")) {
                    if ($identity.$field -cne $rgbSDKContext.capture.observedIdentity.$field) { throw "RGB_NATIVE_COMPILER_BUILD_MISMATCH" }
                }
            }
            $rgbManifest.toolchain = [pscustomobject]@{ kind = "pinned-xcode"; versionLine = $identity.swiftCompilerVersionLine; sdkPath = $rgbSDKContext.capture.sdk.path; tools = $tools; versionCommands = @(
                [pscustomobject]@{ role = "swift"; commandId = $swiftVersionCommand.commandId },
                [pscustomobject]@{ role = "swiftc"; commandId = $compilerVersionCommand.commandId },
                [pscustomobject]@{ role = "swift-frontend"; commandId = $frontendVersionCommand.commandId }
            ) }
            $osVersion = Get-RGBCommandText (Invoke-RGBDirect "/usr/bin/sw_vers" @("-productVersion"))
            $osBuild = Get-RGBCommandText (Invoke-RGBDirect "/usr/bin/sw_vers" @("-buildVersion"))
            $processArchitecture = Get-RGBCommandText (Invoke-RGBDirect "/usr/bin/uname" @("-m"))
            $arm64 = Get-RGBCommandText (Invoke-RGBDirect "/usr/sbin/sysctl" @("-i", "-n", "hw.optional.arm64"))
            $translatedText = Get-RGBCommandText (Invoke-RGBDirect "/usr/sbin/sysctl" @("-i", "-n", "sysctl.proc_translated"))
            # XNU's arm64 OID can be absent on Intel. -i permits that specific
            # missing-key result; a nonzero command exit still fails above.
            if ($processArchitecture -cnotin @("arm64", "x86_64") -or $arm64 -cnotin @("", "0", "1") -or $translatedText -cnotin @("", "0", "1") -or
                ($arm64 -cne "1" -and ($processArchitecture -ceq "arm64" -or $translatedText -ceq "1")) -or
                $osVersion -cnotmatch '^[0-9]+\.[0-9]+(?:\.[0-9]+)?$' -or $osBuild -cnotmatch '^[A-Za-z0-9]+$') { throw "RGB_NATIVE_RUNTIME_IDENTITY_INVALID" }
            $hardwareArchitecture = if ($arm64 -ceq "1") { "arm64" } else { "x86_64" }
            $translated = $translatedText -ceq "1" -or $processArchitecture -cne $hardwareArchitecture
            if (($osVersion -split '\.').Count -eq 2) { $osVersion += ".0" }
            $runtimeEligible = [version]$osVersion -ge [version]"26.5" -and -not $translated
            $rgbManifest.runtimeEligibility = [pscustomobject]@{
                state = $(if ($runtimeEligible) { "eligible" } else { "unsupported" })
                reason = $(if ($translated) { "translated-host-process" } elseif (-not $runtimeEligible) { "runtime-below-macos-26.5" } else { $null })
                processArchitecture = $processArchitecture; hardwareArchitecture = $hardwareArchitecture; translated = $translated
                operatingSystemVersion = $osVersion; operatingSystemBuild = $osBuild
            }
            $cacheRoot = Join-Path ([IO.Path]::GetTempPath()) ("swiftui-color-rgb-cache-" + $rgbCaptureId)
            if (Test-Path -LiteralPath $cacheRoot) { throw "RGB_MODULE_CACHE_ALREADY_EXISTS" }
            [void][IO.Directory]::CreateDirectory($cacheRoot)
            $rgbManifest.sourceCompilation.moduleCacheRoot = $cacheRoot
            $sourcePaths = @(Get-SwiftUIColorRGBSourceNames | ForEach-Object { Join-Path $rgbRepository $_ })
            $commonArguments = @("-parse-as-library", "-swift-version", "6", "-module-name", "SwiftUIColorRGBReference", "-sdk", $rgbSDKContext.capture.sdk.path)
            $rgbManifest.sourceCompilation.state = "failure"
            foreach ($architecture in @("arm64", "x86_64")) {
                $target = "$architecture-apple-macosx26.5"
                $arguments = $commonArguments + @("-target", $target, "-module-cache-path", (Join-Path $cacheRoot $architecture), "-typecheck") + $sourcePaths
                $command = Invoke-RGBDirect $tools[1].path $arguments 180 $childEnvironment
                $rgbManifest.sourceCompilation.typechecks += [pscustomobject]@{ target = $target; commandId = $command.commandId; state = $(if (Test-SwiftUIColorRGBCommandSucceeded $command) { "typechecked" } else { "failure" }); nativeExecution = $false }
                if ($rgbStopCommands) { throw "RGB_TYPECHECK_CLEANUP_UNVERIFIED" }
            }
            if (@($rgbManifest.sourceCompilation.typechecks | Where-Object { $_.state -cne "typechecked" }).Count -gt 0) { throw "RGB_SOURCE_COMPILATION_FAILED" }
            $target = "$hardwareArchitecture-apple-macosx26.5"; $binary = Join-Path $rgbOutput "reference-executable"
            $arguments = $commonArguments + @("-target", $target, "-module-cache-path", (Join-Path $cacheRoot "native-host"), "-O", "-framework", "SwiftUI", "-framework", "AppKit", "-o", $binary) + $sourcePaths
            $build = Invoke-RGBDirect $tools[1].path $arguments 180 $childEnvironment
            $rgbManifest.sourceCompilation.buildCommandId = $build.commandId; $rgbManifest.sourceCompilation.buildTarget = $target
            [void](Get-RGBCommandText $build 16777216)
            $rgbManifest.binary = [pscustomobject]@{ originalPath = $binary; file = Get-SwiftUIColorRGBFileRecord $binary "reference-executable" }
            $rgbManifest.sourceCompilation.state = "compiled"
            if ($runtimeEligible) {
                foreach ($observer in @("swiftui-resolved", "appkit-extended-srgb")) {
                    for ($repetition = 1; $repetition -le 3; $repetition++) { Invoke-RGBObserver $observer $repetition }
                }
            }
        }
        Test-RGBToolFilesUnchanged
        if ($Platform -ceq "Windows") {
            $after = Invoke-RGBPrepared "identity"
            if ($after.sdkPath -cne $rgbWindowsIdentity.sdkPath -or $after.processArchitecture -cne $rgbWindowsIdentity.processArchitecture -or $after.hardwareArchitecture -cne $rgbWindowsIdentity.hardwareArchitecture -or $after.translated -ne $rgbWindowsIdentity.translated) { throw "RGB_WINDOWS_TOOL_SELECTION_CHANGED" }
            foreach ($tool in $rgbWindowsIdentity.tools) {
                $match = @($after.tools | Where-Object { $_.role -ceq $tool.role })
                if ($match.Count -ne 1 -or $match[0].path -cne $tool.path -or $match[0].sha256 -cne $tool.sha256) { throw "RGB_WINDOWS_TOOL_SELECTION_CHANGED" }
            }
        }
        $rgbManifest.integrity.toolsUnchanged = $true
        if ((Get-SwiftUIColorRGBHash $rgbManifest.binary.originalPath) -cne $rgbManifest.binary.file.sha256) { throw "RGB_EXECUTABLE_CHANGED_DURING_COLLECTION" }
        [void](Assert-SwiftUIColorRGBFileRecord $rgbOutput $rgbManifest.binary.file)
        $rgbManifest.integrity.executableUnchanged = $true
        if ($Platform -ceq "Native") {
            $afterSDK = Read-RGBPinnedSDK
            if ($afterSDK.captureManifestSha256 -cne $rgbSDKContext.captureManifestSha256 -or $afterSDK.baselineManifestSha256 -cne $rgbSDKContext.baselineManifestSha256) { throw "RGB_SDK_CAPTURE_CHANGED_DURING_COLLECTION" }
            foreach ($field in @("capture", "status", "seal", "baseline", "settings")) {
                $record = $rgbManifest.sdk.files.$field
                $originalName = [IO.Path]::GetFileName($record.evidenceFile)
                if ((Get-SwiftUIColorRGBHash (Join-Path $CaptureRoot $originalName)) -cne $record.sha256) { throw "RGB_SDK_METADATA_CHANGED_DURING_COLLECTION" }
            }
            $rgbManifest.sdk.afterVerified = $true; $rgbManifest.integrity.sdkCaptureUnchanged = $true
        }
        [void](Assert-RGBCheckout $rgbManifest.source.commit $rgbManifest.source.tree)
        foreach ($file in $rgbSourceOriginals) {
            if ((Get-Item -LiteralPath $file.path).Length -ne $file.bytes -or (Get-SwiftUIColorRGBHash $file.path) -cne $file.sha256) { throw "RGB_SOURCE_CHANGED_DURING_COLLECTION" }
        }
        Test-RGBToolFilesUnchanged
        $rgbManifest.integrity.sourceUnchanged = $true
        $expectedObservers = if ($Platform -ceq "Windows") { @("windows-retained") } else { @("swiftui-resolved", "appkit-extended-srgb") }
        foreach ($observer in $expectedObservers) {
            $reports = @(
                foreach ($run in @($rgbRuns | Where-Object { $_.observer -ceq $observer -and $_.reportState -ceq "valid" } | Sort-Object repetition)) {
                    Read-SwiftUIColorRGBReport (Join-Path $rgbOutput $run.report.evidenceFile) $observer $run.runId $rgbManifest.runtimeEligibility.processArchitecture
                }
            )
            if ($rgbManifest.runtimeEligibility.state -ceq "unsupported") { $controls = [pscustomobject]@{ state = "unsupported"; reasons = @($rgbManifest.runtimeEligibility.reason) } }
            else { $controls = Test-SwiftUIColorRGBObserverControls $reports $observer }
            $rgbManifest.observerControls += [pscustomobject]@{ observer = $observer; state = $controls.state; reasons = $controls.reasons }
            if ($controls.state -ceq "failure") { $rgbFailures.Add("RGB_OBSERVER_FAILURE:$observer") }
        }
        if ($rgbFailures.Count -eq 0) {
            $rgbManifest.status = if ($rgbManifest.runtimeEligibility.state -ceq "eligible" -and @($rgbManifest.observerControls | Where-Object { $_.state -cne "healthy" }).Count -eq 0) { "captured-candidate" } else { "unsupported" }
        }
    }
} catch {
    $code = [regex]::Match($_.Exception.Message, '^RGB_[A-Z0-9_]+').Value
    if ([string]::IsNullOrEmpty($code)) { $code = "RGB_COLLECTION_FAILURE" }
    $rgbFailures.Add($code); $rgbManifest.status = "failure"
} finally {
    $rgbManifest.commands = @($rgbCommands.ToArray()); $rgbManifest.bootstrapCommands = @($rgbBootstrap.ToArray())
    $rgbManifest.runs = @($rgbRuns.ToArray()); $rgbManifest.auxiliaryFiles = @($rgbAuxiliary.ToArray())
    $rgbManifest.failureCodes = @($rgbFailures.ToArray()); $rgbManifest.finishedAtUtc = [DateTime]::UtcNow.ToString("o")
    Write-SwiftUIColorRGBJsonNew -Path (Join-Path $rgbOutput "capture.json") -Value $rgbManifest
    $manifestHash = Get-SwiftUIColorRGBHash (Join-Path $rgbOutput "capture.json")
    Write-SwiftUIColorRGBTextNew -Path (Join-Path $rgbOutput "capture.sha256") -Text "$manifestHash  capture.json`n"
}
Write-Host "RGB capture: $($rgbManifest.status); source compilation: $($rgbManifest.sourceCompilation.state). Evidence: $rgbOutput"
Write-Host "Declaration, source, behavior, and release review remain unverified."
try { [void](Read-SwiftUIColorRGBCapture $rgbOutput) } catch { Write-Error "RGB_CAPTURE_SELF_VALIDATION_FAILED: raw evidence is preserved; this capture cannot qualify." -ErrorAction Continue; exit 1 }
if ($rgbManifest.status -ceq "failure") { exit 1 }
if ($rgbManifest.status -ceq "unsupported") { exit 2 }
exit 0
