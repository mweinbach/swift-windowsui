<#
.SYNOPSIS
Tests RGB-constructor evidence tooling using synthetic files only.
.DESCRIPTION
No Swift compiler, SwiftPM, Apple tool, reference executable, or color API is
run. Fake source/tool/executable metadata cannot establish native behavior.
The tests exercise bounded PowerShell child processes and compile only the
managed JSON helper; PS5 Add-Type can invoke its framework C# compiler.
All mutable fixtures live beneath one new UUID OS-temp directory. Production
writers remain create-new; test-only mutation deliberately simulates tampering.
#>
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot), [string]$EvidenceDirectory)

$ErrorActionPreference = "Stop"
. (Join-Path $RepositoryRoot "scripts/swiftui-color-rgb-reference-common.ps1")
$script:RGBTestAssertions = 0; $script:RGBTestCases = 0
$script:RGBTestUTF8 = [Text.UTF8Encoding]::new($false)
# Temp ancestors can be aliases, including /var on macOS. Establish one physical
# fixture root before creation for both source snapshots and strict cleanup.
$script:RGBTestRoot = Resolve-SwiftUIBaselineFileSystemPath -Path (Join-Path ([IO.Path]::GetTempPath()) ("swiftui-color-rgb-tests-" + [Guid]::NewGuid().ToString("N")))
if (Test-Path -LiteralPath $script:RGBTestRoot) { throw "Test directory already exists." }
[void][IO.Directory]::CreateDirectory($script:RGBTestRoot)
$script:RGBTestFailures = [System.Collections.Generic.List[string]]::new()
$script:RGBTestResults = [System.Collections.Generic.List[object]]::new()
$script:RGBTestStarted = [DateTime]::UtcNow.ToString("o")
$script:RGBTestFallbackExercised = $false
$script:RGBTestSourceHashes = @(
    foreach ($name in @("capture", "compare", "test")) {
        $path = Join-Path $PSScriptRoot "$name-swiftui-color-rgb-reference.ps1"
        [pscustomobject]@{ path = "scripts/$name-swiftui-color-rgb-reference.ps1"; sha256 = Get-SwiftUIColorRGBHash $path }
    }
    [pscustomobject]@{ path = "scripts/swiftui-color-rgb-reference-common.ps1"; sha256 = Get-SwiftUIColorRGBHash (Join-Path $PSScriptRoot "swiftui-color-rgb-reference-common.ps1") }
)
if (-not [string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = New-SwiftUIColorRGBOutputRoot $EvidenceDirectory $RepositoryRoot
}
$script:RGBTestCompiler = "Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)"

function Assert-RGBTest {
    param([bool]$Condition, [string]$Message)
    $script:RGBTestAssertions++
    if (-not $Condition) { throw "RGB synthetic assertion failed: $Message" }
}

function Invoke-RGBTestCase {
    param([string]$Name, [scriptblock]$Action)
    $script:RGBTestCases++
    $timer = [Diagnostics.Stopwatch]::StartNew(); $failure = $null
    try { & $Action } catch { $failure = $_.Exception.Message; $script:RGBTestFailures.Add("${Name}: $failure") }
    $timer.Stop()
    $script:RGBTestResults.Add([pscustomobject]@{ name = $Name; passed = ($null -eq $failure); failure = $failure; elapsedMilliseconds = $timer.ElapsedMilliseconds })
}

function Assert-RGBTestThrows {
    param([scriptblock]$Action, [string]$Pattern = 'RGB_', [string]$Message = "expected rejection")
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-RGBTest ($null -ne $caught) "$Message raised"
    if ($null -ne $caught) { Assert-RGBTest ($caught.Exception.Message -match $Pattern) "$Message reason ($($caught.Exception.Message))" }
}

function Write-RGBTestText {
    param([string]$Path, [string]$Text)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, $script:RGBTestUTF8)
}

function Write-RGBTestJson {
    param([string]$Path, $Value)
    Write-RGBTestText $Path ((ConvertTo-Json -InputObject $Value -Depth 48) + "`n")
}

function Copy-RGBTestValue {
    param($Value)
    return (ConvertFrom-SwiftUIColorRGBJsonText (ConvertTo-Json -InputObject $Value -Depth 48))
}

function New-RGBTestRawReport {
    param([string]$Observer, [string]$RunId = ([Guid]::NewGuid().ToString("D")), [int]$ProcessId = 1001)
    $cases = @(
        foreach ($case in Get-SwiftUIColorRGBCases) {
            $input = [ordered]@{}
            foreach ($name in @("red", "green", "blue", "opacity")) { $input[$name] = New-SwiftUIColorRGBNumber $case.input.$name "float64" }
            $encoded = @([double]$case.input.red, [double]$case.input.green, [double]$case.input.blue)
            # Labelled synthetic values only. These tables exercise validation
            # and comparison; they are not native or standards color evidence.
            if ($case.caseId -cin @("linear-interior", "linear-alpha-zero", "linear-alpha-fraction")) { $encoded = @(0.53709873, 0.73535698, 0.88082504) }
            if ($case.caseId -cin @("p3-red", "p3-alpha-zero", "p3-alpha-fraction")) { $encoded = @(1.093, -0.227, -0.15) }
            if ($case.caseId -ceq "p3-green") { $encoded = @(-0.51, 1.018, -0.31) }
            $environments = if ($Observer -ceq "swiftui-resolved") { @("light", "dark") } else { @("none") }
            $observations = @(
                foreach ($environment in $environments) {
                    $storage = if ($Observer -ceq "appkit-extended-srgb") { "float64" } else { "float32" }
                    $rgba = [ordered]@{}; $linear = $null; $appKit = $null
                    $names = @("red", "green", "blue")
                    for ($i = 0; $i -lt 3; $i++) { $rgba[$names[$i]] = New-SwiftUIColorRGBNumber ([double][single]$encoded[$i]) $storage }
                    $rgba.alpha = New-SwiftUIColorRGBNumber $case.input.opacity $storage
                    if ($Observer -ceq "swiftui-resolved") {
                        $linear = [ordered]@{}
                        foreach ($name in $names) {
                            $number = if ($case.sourceSpace -ceq "srgb-linear") { $case.input.$name } else { $case.input.$name / 2 }
                            $linear[$name] = New-SwiftUIColorRGBNumber $number "float32"
                        }
                    }
                    if ($Observer -ceq "appkit-extended-srgb") { $appKit = [pscustomobject]@{ targetColorSpace = "extendedSRGB"; actualColorSpaceName = "SYNTHETIC - not an NSColor observation"; colorSpaceModel = "rgb"; componentCount = 4; targetIdentityMatches = $true } }
                    [pscustomobject]@{ environment = $environment; status = "observed"; reason = $null; encodedRGBA = [pscustomobject]$rgba; linearRGB = $(if ($null -eq $linear) { $null } else { [pscustomobject]$linear }); appKit = $appKit }
                }
            )
            [pscustomobject]@{ caseId = $case.caseId; domain = $case.domain; sourceSpace = $case.sourceSpace; input = [pscustomobject]$input; observations = $observations }
        }
    )
    $p = Get-SwiftUIColorRGBProtocol
    return [pscustomobject]@{
        schemaVersion = 1; protocolId = $p.protocolId; caseSetId = $p.caseSetId; componentEncoding = $p.componentEncoding
        collectionStatus = "complete"; runId = $RunId; observer = $Observer
        platform = $(if ($Observer -ceq "windows-retained") { "windows" } else { "macos" })
        runtime = [pscustomobject]@{ processId = $ProcessId; processArchitecture = "x86_64"; operatingSystemVersion = $(if ($Observer -ceq "windows-retained") { "10.0.26220" } else { "26.5.0" }); operatingSystemVersionString = "SYNTHETIC - not an executed observer" }
        cases = $cases
    }
}

function Save-RGBTestReport {
    param($Raw, [string]$Name = ([Guid]::NewGuid().ToString("N") + ".json"))
    $path = Join-Path $script:RGBTestRoot $Name
    Write-RGBTestJson $path $Raw
    return Read-SwiftUIColorRGBReport $path $Raw.observer $Raw.runId "x86_64"
}

function New-RGBTestReports {
    param([string]$Observer)
    return @(1..3 | ForEach-Object { Save-RGBTestReport (New-RGBTestRawReport $Observer) })
}

function Set-RGBTestComponents {
    param($Raw, [string]$CaseId, [string]$Component, [double]$Value)
    $case = @($Raw.cases | Where-Object { $_.caseId -ceq $CaseId })[0]
    foreach ($observation in $case.observations) { $observation.encodedRGBA.$Component = New-SwiftUIColorRGBNumber $Value $observation.encodedRGBA.$Component.storage }
}

function New-RGBTestCommand {
    param($Fixture, $Tool, [string[]]$Arguments, [string]$Stdout = "SYNTHETIC command only`n", [int]$ExitCode = 0)
    $index = $Fixture.commands.Count + 1; $id = "command-{0:D3}" -f $index
    $outName = "$id.stdout.txt"; $errName = "$id.stderr.txt"
    Write-RGBTestText (Join-Path $Fixture.root $outName) $Stdout
    Write-RGBTestText (Join-Path $Fixture.root $errName) ""
    $record = [pscustomobject]@{
        commandId = $id; executable = $Tool.path; executableSha256 = $Tool.sha256; arguments = @($Arguments)
        processId = 1000 + $index; startedAtUtc = "2026-08-27T12:00:00.0000000Z"; finishedAtUtc = "2026-08-27T12:00:00.0100000Z"
        timeoutSeconds = 30; maxLogBytesPerStream = 16777216; state = "exited"; exitCode = $ExitCode; errorCode = $null; cleanupComplete = $true
        cleanupScope = "owned-root-and-redirected-streams; no process-tree closure claim"
        stdout = Get-SwiftUIColorRGBFileRecord (Join-Path $Fixture.root $outName) $outName
        stderr = Get-SwiftUIColorRGBFileRecord (Join-Path $Fixture.root $errName) $errName
    }
    $Fixture.commands.Add($record)
    return $record
}

function New-RGBTestSourceEntry {
    param([string]$Root, [string]$Name, [string]$Group)
    $relative = "sources/$Group/$Name"
    $path = Join-Path $Root $relative
    $bytes = $script:RGBTestUTF8.GetBytes("// SYNTHETIC source bytes only: $Name`n")
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path)); [IO.File]::WriteAllBytes($path, $bytes)
    return [pscustomobject]@{ path = $Name; gitBlob = Get-SwiftUIColorRGBGitBlobHash $bytes; byteIdentity = "git-blob-exact"; file = Get-SwiftUIColorRGBFileRecord $path $relative }
}

function New-RGBTestSDK {
    param([string]$Root, [object[]]$Tools)
    $directory = Join-Path $Root "sdk"; [void][IO.Directory]::CreateDirectory($directory)
    $baselinePath = Join-Path $directory "baseline-manifest.json"
    [IO.File]::Copy((Join-Path $RepositoryRoot "docs/swiftui-baseline.json"), $baselinePath, $false)
    $baselineHash = Get-SwiftUIColorRGBHash $baselinePath
    $baseline = Read-SwiftUIBaselineManifest $baselinePath
    $identity = ConvertTo-SwiftUIBaselineIdentity -XcodeOutput "Xcode 26.6`nBuild version TESTXCODE" -SDKVersion "26.5" -SDKBuildVersion "25F70" -SwiftOutput $script:RGBTestCompiler
    Write-RGBTestText (Join-Path $directory "SDKSettings.json") '{"Version":"26.5","ProductBuildVersion":"25F70","synthetic":true}'
    $capture = [pscustomobject]@{
        schemaVersion = 1; baselineId = $baseline.baselineId; status = "exported-awaiting-inventory-and-behavior-review"
        developerDirectoryOverride = "/Applications/SYNTHETIC-Xcode.app/Contents/Developer"
        exactIdentityPreviouslyReviewed = $false; observedIdentity = $identity
        host = [pscustomobject]@{ macOSVersion = "26.5.0"; macOSBuildVersion = "25F70"; architecture = "x86_64" }
        baselineManifest = [pscustomobject]@{ path = "baseline-manifest.json"; sha256 = $baselineHash }
        sdk = [pscustomobject]@{ path = "/Applications/SYNTHETIC-Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk"; version = "26.5"; buildVersion = "25F70"; settingsPath = "SDKSettings.json"; settingsSha256 = Get-SwiftUIColorRGBHash (Join-Path $directory "SDKSettings.json") }
        tools = @($Tools | ForEach-Object { [pscustomobject]@{ path = $_.path; sha256 = $_.sha256 } })
        qualification = [pscustomobject]@{ publicAPIAuditComplete = $false; behaviorConformanceVerified = $false; releaseQualified = $false }
    }
    Write-RGBTestJson (Join-Path $directory "capture.json") $capture
    $captureHash = Get-SwiftUIColorRGBHash (Join-Path $directory "capture.json")
    Write-RGBTestJson (Join-Path $directory "capture-status.json") ([pscustomobject]@{ status = "exported-awaiting-review"; captureManifest = "capture.json"; captureManifestSha256 = $captureHash; baselineId = $baseline.baselineId; behaviorConformance = "not-verified" })
    Write-RGBTestText (Join-Path $directory "capture.sha256") "$captureHash  capture.json`n"
    $files = [ordered]@{}
    foreach ($item in @(@("capture", "capture.json"), @("status", "capture-status.json"), @("seal", "capture.sha256"), @("baseline", "baseline-manifest.json"), @("settings", "SDKSettings.json"))) {
        $files[$item[0]] = Get-SwiftUIColorRGBFileRecord (Join-Path $directory $item[1]) ("sdk/" + $item[1])
    }
    return [pscustomobject]@{ validationMethod = "Read-SwiftUIMaterialSDKContext"; beforeVerified = $true; afterVerified = $true; captureRoot = "/SYNTHETIC-sdk-capture"; baselineId = $baseline.baselineId; observedIdentity = $identity; files = [pscustomobject]$files }
}

function Publish-RGBTestCapture {
    param($Fixture)
    $Fixture.manifest.commands = @($Fixture.commands.ToArray())
    Write-RGBTestJson (Join-Path $Fixture.root "capture.json") $Fixture.manifest
    $hash = Get-SwiftUIColorRGBHash (Join-Path $Fixture.root "capture.json")
    Write-RGBTestText (Join-Path $Fixture.root "capture.sha256") "$hash  capture.json`n"
}

function New-RGBTestCapture {
    param([ValidateSet("windows", "native")][string]$Platform)
    $root = Join-Path $script:RGBTestRoot ("capture-$Platform-" + [Guid]::NewGuid().ToString("N")); [void][IO.Directory]::CreateDirectory($root)
    $fixture = [pscustomobject]@{ root = $root; commands = [System.Collections.Generic.List[object]]::new(); manifest = $null }
    $p = Get-SwiftUIColorRGBProtocol; $captureId = [Guid]::NewGuid().ToString("D")
    $originalOutput = if ($Platform -ceq "windows") { "C:/SYNTHETIC-evidence/windows" } else { "/SYNTHETIC-evidence/native" }
    $repository = if ($Platform -ceq "windows") { "C:/SYNTHETIC-repository" } else { "/SYNTHETIC-repository" }
    $shared = @(Get-SwiftUIColorRGBSourceNames | ForEach-Object { New-RGBTestSourceEntry $root $_ "shared" })
    $buildNames = @(Get-SwiftUIColorRGBSourceNames) + @("Package.swift")
    if ($Platform -ceq "windows") { $buildNames += @("Sources/WinSwiftUI/Core.swift", "Sources/WinSwiftUI/ColorSpaceConversion.swift", "Sources/SwiftWindowsApp/FoundationApp+DefaultRenderer.swift") }
    $buildInputs = @($buildNames | ForEach-Object { New-RGBTestSourceEntry $root $_ "build-inputs" })
    $collector = @(New-RGBTestSourceEntry $root "scripts/capture-swiftui-color-rgb-reference.ps1" "collector")
    $toolRoot = if ($Platform -ceq "windows") { "C:/SYNTHETIC-Swift/usr/bin" } else { "/Applications/SYNTHETIC-Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin" }
    $tools = @(
        foreach ($role in @("swift", "swiftc", "swift-frontend")) {
            $suffix = if ($Platform -ceq "windows") { ".exe" } else { "" }
            [pscustomobject]@{ role = $role; path = "$toolRoot/$role$suffix"; sha256 = Get-SwiftUIBaselineTextHash "SYNTHETIC $role"; bytes = 128 }
        }
    )
    $sdk = $null; $cache = $null; $versions = @(); $typechecks = @(); $binCommand = $null
    if ($Platform -ceq "native") {
        $sdk = New-RGBTestSDK $root $tools
        $sdkPath = "/Applications/SYNTHETIC-Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk"
        for ($i = 0; $i -lt 3; $i++) {
            $line = $script:RGBTestCompiler
            if ($i -lt 2) { $line = "swift-driver version: 1.148.6 " + $line }
            $command = New-RGBTestCommand $fixture $tools[$i] @("--version") ($line + "`nTarget: x86_64-apple-macosx26.5`n")
            $versions += [pscustomobject]@{ role = $tools[$i].role; commandId = $command.commandId }
        }
        $versionLine = $script:RGBTestCompiler; $target = "x86_64-apple-macosx26.5"
        $cache = "/private/tmp/swiftui-color-rgb-cache-$captureId"
        $common = @("-parse-as-library", "-swift-version", "6", "-module-name", "SwiftUIColorRGBReference", "-sdk", $sdkPath)
        $sources = @(Get-SwiftUIColorRGBSourceNames | ForEach-Object { "$repository/$_" })
        foreach ($architecture in @("arm64", "x86_64")) {
            $typeTarget = "$architecture-apple-macosx26.5"
            $command = New-RGBTestCommand $fixture $tools[1] ($common + @("-target", $typeTarget, "-module-cache-path", "$cache/$architecture", "-typecheck") + $sources)
            $typechecks += [pscustomobject]@{ target = $typeTarget; commandId = $command.commandId; state = "typechecked"; nativeExecution = $false }
        }
        $binaryPath = "$originalOutput/reference-executable"; $binaryName = "reference-executable"
        $build = New-RGBTestCommand $fixture $tools[1] ($common + @("-target", $target, "-module-cache-path", "$cache/native-host", "-O", "-framework", "SwiftUI", "-framework", "AppKit", "-o", $binaryPath) + $sources)
    } else {
        $sdkPath = "C:/SYNTHETIC-Windows.sdk"; $target = "x86_64-unknown-windows-msvc"; $versionLine = "Swift version 6.3 (SYNTHETIC test only)"
        $versionCommand = New-RGBTestCommand $fixture $tools[0] @("--version") "$versionLine`nTarget: $target`n"
        $versions += [pscustomobject]@{ role = "swift"; commandId = $versionCommand.commandId }
        $build = New-RGBTestCommand $fixture $tools[0] @("build", "--package-path", $repository, "--configuration", "release", "--product", "swiftui-color-rgb-reference")
        $binCommand = New-RGBTestCommand $fixture $tools[0] @("build", "--package-path", $repository, "--configuration", "release", "--show-bin-path") "$repository/.build/x86_64-unknown-windows-msvc/release`n"
        $binaryPath = "$repository/.build/x86_64-unknown-windows-msvc/release/swiftui-color-rgb-reference.exe"; $binaryName = "reference-executable.exe"
    }
    Write-RGBTestText (Join-Path $root $binaryName) "SYNTHETIC NOT-EXECUTABLE bytes; never launch this file."
    $binary = [pscustomobject]@{ originalPath = $binaryPath; file = Get-SwiftUIColorRGBFileRecord (Join-Path $root $binaryName) $binaryName }
    $runs = @(); $controls = @(); $observerNames = if ($Platform -ceq "windows") { @("windows-retained") } else { @("swiftui-resolved", "appkit-extended-srgb") }
    foreach ($observer in $observerNames) {
        $reports = @()
        for ($repetition = 1; $repetition -le 3; $repetition++) {
            $runId = [Guid]::NewGuid().ToString("D"); $reportName = "$observer-$repetition.json"
            $command = New-RGBTestCommand $fixture ([pscustomobject]@{ path = $binaryPath; sha256 = $binary.file.sha256 }) @("--observer", $observer, "--run-id", $runId, "--output", "$originalOutput/$reportName")
            $raw = New-RGBTestRawReport $observer $runId $command.processId
            $reportPath = Join-Path $root $reportName; Write-RGBTestJson $reportPath $raw
            $reports += Read-SwiftUIColorRGBReport $reportPath $observer $runId "x86_64"
            $runs += [pscustomobject]@{ observer = $observer; repetition = $repetition; runId = $runId; commandId = $command.commandId; report = Get-SwiftUIColorRGBFileRecord $reportPath $reportName; reportState = "valid"; reasonCode = $null }
        }
        $control = Test-SwiftUIColorRGBObserverControls $reports $observer
        $controls += [pscustomobject]@{ observer = $observer; state = $control.state; reasons = $control.reasons }
    }
    $fixture.manifest = [pscustomobject]@{
        schemaVersion = 1; evidenceKind = "color-rgb-reference-candidate"; protocolId = $p.protocolId; caseSetId = $p.caseSetId; toleranceId = $p.toleranceId
        captureId = $captureId; originalOutputRoot = $originalOutput; platform = $Platform; status = "captured-candidate"
        startedAtUtc = "2026-08-27T12:00:00.0000000Z"; finishedAtUtc = "2026-08-27T12:01:00.0000000Z"
        source = [pscustomobject]@{ repositoryRoot = $repository; commit = ("1" * 40); tree = ("2" * 40); clean = $true; sharedSources = $shared; buildInputs = $buildInputs; collectorSources = $collector }
        sourceCompilation = [pscustomobject]@{ state = "compiled"; typechecks = $typechecks; buildCommandId = $build.commandId; buildTarget = $target; moduleCacheRoot = $cache; binaryPathCommandId = $(if ($null -ne $binCommand) { $binCommand.commandId } else { $null }) }
        runtimeEligibility = [pscustomobject]@{ state = "eligible"; reason = $null; processArchitecture = "x86_64"; hardwareArchitecture = "x86_64"; translated = $false; operatingSystemVersion = $(if ($Platform -ceq "windows") { "10.0.26220" } else { "26.5.0" }); operatingSystemBuild = $(if ($Platform -ceq "windows") { "26220" } else { "25F70" }) }
        toolchain = [pscustomobject]@{ kind = $(if ($Platform -ceq "windows") { "windows-with-swift" } else { "pinned-xcode" }); versionLine = $versionLine; sdkPath = $sdkPath; tools = $tools; versionCommands = $versions }
        sdk = $sdk; binary = $binary; commands = @(); bootstrapCommands = @(); runs = $runs; auxiliaryFiles = @(); observerControls = $controls
        integrity = [pscustomobject]@{ sourceUnchanged = $true; toolsUnchanged = $true; executableUnchanged = $true; sdkCaptureUnchanged = $true }
        qualification = [pscustomobject]@{ declarationReview = "unverified"; sourceReview = "unverified"; behaviorReview = "unverified"; releaseQualified = $false }
        failureCodes = @()
    }
    Publish-RGBTestCapture $fixture
    return $fixture
}

function Copy-RGBTestCapture {
    param($Fixture)
    $root = Join-Path $script:RGBTestRoot ("clone-" + [Guid]::NewGuid().ToString("N"))
    [void](Get-SwiftUIBaselineRelativePath -Root $script:RGBTestRoot -Path $root)
    Copy-Item -LiteralPath $Fixture.root -Destination $root -Recurse
    $manifest = Read-SwiftUIColorRGBJson (Join-Path $root "capture.json") -MaxBytes 16777216
    $commands = [System.Collections.Generic.List[object]]::new(); foreach ($command in $manifest.commands) { $commands.Add($command) }
    return [pscustomobject]@{ root = $root; manifest = $manifest; commands = $commands }
}

function Set-RGBTestBridgeFailure {
    param($Fixture, [string]$Reason = 'RGB_OBSERVER_PROCESS_FAILED')
    $Fixture.manifest.status = 'failure'
    $Fixture.manifest.failureCodes = @($Reason, 'RGB_OBSERVER_FAILURE:appkit-extended-srgb')
    foreach ($run in $Fixture.manifest.runs) {
        if ($run.observer -cne 'appkit-extended-srgb') { continue }
        $run.reportState = 'invalid'; $run.reasonCode = $Reason
        $command = @($Fixture.commands | Where-Object { $_.commandId -ceq $run.commandId })[0]
        $command.exitCode = 9
        if ($Reason -ceq 'RGB_OBSERVER_REPORT_MISSING') { $run.reportState = 'missing'; $run.report = $null; $command.exitCode = 0 }
    }
    $control = @($Fixture.manifest.observerControls | Where-Object { $_.observer -ceq 'appkit-extended-srgb' })[0]
    $control.state = 'failure'; $control.reasons = @('incomplete-repetitions')
}

function Publish-RGBTestPacket {
    param($Fixture)
    $path = Join-Path $Fixture.root 'review-unit.json'; Write-RGBTestJson $path $Fixture.manifest
    Write-RGBTestText (Join-Path $Fixture.root 'review-unit.sha256') ((Get-SwiftUIColorRGBHash $path) + "  review-unit.json`n")
}

function Update-RGBTestPacketRecord {
    param($Fixture, [string]$Name)
    $file = @($Fixture.manifest.recordFiles | Where-Object { $_.path -ceq $Name })[0]
    $record = Get-SwiftUIColorRGBFileRecord (Join-Path $Fixture.root $Name) $Name
    $file.sha256 = $record.sha256; $file.bytes = $record.bytes
}

function New-RGBTestPacket {
    $root = Join-Path $script:RGBTestRoot ('review-packet-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($root)
    $id = 's:7SwiftUI5ColorV_3red5green4blue7opacityA2C13RGBColorSpaceO_S4dtcfc'
    $occurrences = @(
        foreach ($target in @('arm64-apple-macosx26.5', 'x86_64-apple-macosx26.5')) {
            foreach ($module in @('SwiftUI', 'SwiftUICore')) {
                [pscustomobject]@{ graphPath = "graphs/$target/$module/$module.symbols.json"; requestedModule = $module; target = $target; symbolIndex = $(if ($module -ceq 'SwiftUI') { 100453 } else { 3694 }); preciseIdentifier = $id; symbol = [pscustomobject]@{ synthetic = $true } }
            }
        }
    )
    $recordFiles = @(
        foreach ($name in @('native/identity.ndjson', 'native/occurrences.ndjson', 'native/relationships.ndjson', 'context/graph-fields.ndjson', 'context/partitions.ndjson', 'context/inventory-facts.ndjson', 'context/interface-facts.ndjson', 'context/overlay-facts.ndjson', 'context/candidate-queues.ndjson')) {
            $content = if ($name -ceq 'native/occurrences.ndjson') { (@($occurrences | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress -Depth 8 }) -join "`n") + "`n" } else { '{"synthetic":true}' + "`n" }
            $path = Join-Path $root $name; Write-RGBTestText $path $content
            $record = Get-SwiftUIColorRGBFileRecord $path $name
            [pscustomobject]@{ path = $name; sha256 = $record.sha256; bytes = $record.bytes }
        }
    )
    $metadata = @(
        foreach ($entry in @(@('capture', 'capture.json', 'capture-manifest'), @('status', 'capture-status.json', 'capture-status'), @('seal', 'capture.sha256', 'capture-seal'), @('baseline', 'baseline-manifest.json', 'captured-baseline-manifest'))) {
            $source = Join-Path $script:RGBTestNativeCapture.root $script:RGBTestValidatedNative.manifest.sdk.files.($entry[0]).evidenceFile
            $name = 'context/' + $entry[1]; $path = Join-Path $root $name; [IO.File]::Copy($source, $path, $false)
            $record = Get-SwiftUIColorRGBFileRecord $path $name
            [pscustomobject]@{ path = $name; sha256 = $record.sha256; bytes = $record.bytes; kind = $entry[2] }
        }
    )
    $auditPath = Join-Path $root 'context/audit.json'; Write-RGBTestText $auditPath '{"synthetic":true,"reviewStatus":"unreviewed"}'
    $auditHash = Get-SwiftUIColorRGBHash $auditPath
    Write-RGBTestText (Join-Path $root 'context/audit.sha256') "$auditHash  audit.json`n"
    foreach ($entry in @(@('context/audit.json', 'source-audit-manifest'), @('context/audit.sha256', 'source-audit-seal'))) {
        $record = Get-SwiftUIColorRGBFileRecord (Join-Path $root $entry[0]) $entry[0]
        $metadata += [pscustomobject]@{ path = $entry[0]; sha256 = $record.sha256; bytes = $record.bytes; kind = $entry[1] }
    }
    $input = @($script:RGBTestValidatedWindows.manifest.source.buildInputs | Where-Object { $_.path -ceq 'Sources/WinSwiftUI/Core.swift' })[0]
    $copyName = 'windows/Sources/WinSwiftUI/Core.swift'; $copyPath = Join-Path $root $copyName
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $copyPath)); [IO.File]::Copy((Join-Path $script:RGBTestWindowsCapture.root $input.file.evidenceFile), $copyPath, $false)
    $record = Get-SwiftUIColorRGBFileRecord $copyPath $copyName
    $fixture = [pscustomobject]@{ root = $root; manifest = [pscustomobject]@{
        schemaVersion = 1; evidenceKind = 'unreviewed-api-review-unit'; status = 'awaiting-declaration-source-and-behavior-review'; reviewStatus = 'unreviewed'; baselineId = $script:RGBTestValidatedNative.manifest.sdk.baselineId
        selection = [pscustomobject]@{ preciseIdentifier = $id; comparison = 'ordinal-exact'; closure = 'all-occurrences-and-source-or-target-incident-relationships'; standaloneNativeUniverse = $false; declarationOccurrences = 4 }
        sourceCapture = [pscustomobject]@{ captureManifestSha256 = $script:RGBTestValidatedNative.manifest.sdk.files.capture.sha256; captureStatusSha256 = $script:RGBTestValidatedNative.manifest.sdk.files.status.sha256; baselineManifestSha256 = $script:RGBTestValidatedNative.manifest.sdk.files.baseline.sha256 }
        sourceAudit = [pscustomobject]@{ manifestSha256 = $auditHash; sealSha256 = Get-SwiftUIColorRGBHash (Join-Path $root 'context/audit.sha256'); reviewStatus = 'unreviewed' }
        windowsSource = [pscustomobject]@{ commit = $script:RGBTestValidatedWindows.manifest.source.commit; files = @([pscustomobject]@{ path = $input.path; blobOid = $input.gitBlob; sha256 = $record.sha256; bytes = $record.bytes; copiedPath = $copyName }) }
        claims = @(@('declaration', 'source-compatibility', 'behavior') | ForEach-Object { [pscustomobject]@{ claimId = $_; kind = $_; status = 'unverified'; evidenceRefs = @() } }); evidenceReferences = @()
        recordFiles = $recordFiles; sourceMetadataFiles = $metadata
    } }
    Publish-RGBTestPacket $fixture
    return $fixture
}

function Publish-RGBTestLiveSDK {
    param($Fixture)
    Write-RGBTestJson (Join-Path $Fixture.captureRoot 'capture.json') $Fixture.capture
    $hash = Get-SwiftUIColorRGBHash (Join-Path $Fixture.captureRoot 'capture.json')
    Write-RGBTestText (Join-Path $Fixture.captureRoot 'capture.sha256') "$hash  capture.json`n"
    $Fixture.status.captureManifestSha256 = $hash
    Write-RGBTestJson (Join-Path $Fixture.captureRoot 'capture-status.json') $Fixture.status
}

function New-RGBTestLiveSDK {
    $root = Join-Path $script:RGBTestRoot ('sdk-live-' + [Guid]::NewGuid().ToString('N'))
    $captureRoot = Join-Path $root 'capture'; [void][IO.Directory]::CreateDirectory($captureRoot)
    $developer = (Join-Path $root 'Xcode.app/Contents/Developer').Replace('\', '/')
    $bin = "$developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
    $sdkPath = "$developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk"
    [void][IO.Directory]::CreateDirectory($bin); [void][IO.Directory]::CreateDirectory($sdkPath)
    $swiftPath = "$bin/swift"; Write-RGBTestText $swiftPath 'SYNTHETIC not executable Swift'
    $settingsPath = "$sdkPath/SDKSettings.json"; Write-RGBTestText $settingsPath '{"Version":"26.5","ProductBuildVersion":"25F70","synthetic":true}'
    [IO.File]::Copy($settingsPath, (Join-Path $captureRoot 'SDKSettings.json'), $false)
    $manifestPath = Join-Path $root 'requested-baseline.json'; [IO.File]::Copy((Join-Path $RepositoryRoot 'docs/swiftui-baseline.json'), $manifestPath, $false)
    [IO.File]::Copy($manifestPath, (Join-Path $captureRoot 'baseline-manifest.json'), $false)
    $baseline = Read-SwiftUIBaselineManifest $manifestPath
    $identity = ConvertTo-SwiftUIBaselineIdentity -XcodeOutput "Xcode 26.6`nBuild version TESTXCODE" -SDKVersion '26.5' -SDKBuildVersion '25F70' -SwiftOutput $script:RGBTestCompiler
    $capture = [pscustomobject]@{
        schemaVersion = 1; baselineId = $baseline.baselineId; status = 'exported-awaiting-inventory-and-behavior-review'; developerDirectoryOverride = $developer
        exactIdentityPreviouslyReviewed = $false; observedIdentity = $identity
        host = [pscustomobject]@{ macOSVersion = '26.5.0'; macOSBuildVersion = '25F70'; architecture = 'x86_64' }
        baselineManifest = [pscustomobject]@{ path = 'baseline-manifest.json'; sha256 = Get-SwiftUIColorRGBHash $manifestPath }
        sdk = [pscustomobject]@{ path = $sdkPath; version = '26.5'; buildVersion = '25F70'; settingsPath = 'SDKSettings.json'; settingsSha256 = Get-SwiftUIColorRGBHash $settingsPath }
        tools = @([pscustomobject]@{ path = $swiftPath; sha256 = Get-SwiftUIColorRGBHash $swiftPath })
        qualification = [pscustomobject]@{ publicAPIAuditComplete = $false; behaviorConformanceVerified = $false; releaseQualified = $false }
    }
    $status = [pscustomobject]@{ status = 'exported-awaiting-review'; captureManifest = 'capture.json'; captureManifestSha256 = ''; baselineId = $baseline.baselineId; behaviorConformance = 'not-verified' }
    $inventoryPath = Join-Path $captureRoot 'inventory.json'; Write-RGBTestText $inventoryPath 'INTENTIONALLY INVALID: the RGB SDK validator must never open this inventory.'
    $fixture = [pscustomobject]@{ root = $root; captureRoot = $captureRoot; manifestPath = $manifestPath; capture = $capture; status = $status; swiftPath = $swiftPath; settingsPath = $settingsPath; inventoryPath = $inventoryPath }
    Publish-RGBTestLiveSDK $fixture
    return $fixture
}

$rgbTestOriginalFailure = $null
try {
    $script:RGBTestParserIdentity = Get-SwiftUIColorRGBJsonParserIdentity
    if (-not [string]::IsNullOrWhiteSpace($EvidenceDirectory)) { Write-SwiftUIColorRGBJsonNew (Join-Path $EvidenceDirectory 'json-parser-identity.json') $script:RGBTestParserIdentity }
    Invoke-RGBTestCase "protocol and membership" {
        $cases = @(Get-SwiftUIColorRGBCases); $protocol = Get-SwiftUIColorRGBProtocol
        Assert-RGBTest ($cases.Count -eq 25) "25 exact cases"
        Assert-RGBTest (@($cases | Where-Object { $_.domain -ceq "required-finite" }).Count -eq 23) "23 required cases"
        Assert-RGBTest (@($cases | Where-Object { $_.domain -ceq "exploratory-extended-p3" }).Count -eq 2) "2 exploratory cases"
        Assert-RGBTest (@($cases.caseId | Select-Object -Unique).Count -eq 25) "unique case IDs"
        Assert-RGBTest ($protocol.repetitions -eq 3 -and $protocol.absoluteRGB -eq 2e-6 -and $protocol.absoluteAlpha -eq 2.384185791015625e-7) "frozen tolerances"
    }
    Invoke-RGBTestCase "numeric storage and exact bits" {
        foreach ($storage in @("float32", "float64")) {
            foreach ($number in @(0.0, 1.0, -0.5, 1.25, 0.1, 2.0, [double]::NaN, [double]::PositiveInfinity, [double]::NegativeInfinity)) {
                $record = New-SwiftUIColorRGBNumber $number $storage
                $parsed = Read-SwiftUIColorRGBNumber $record $storage "test"
                Assert-RGBTest ($parsed.kind -ceq $record.kind -and $parsed.bitPattern -ceq $record.bitPattern) "numeric storage round-trip $storage/$($record.kind)"
                if ($record.kind -cne "finite") { Assert-RGBTest ($null -eq $record.value) "nonfinite JSON value is null" }
            }
        }
        $n = New-SwiftUIColorRGBNumber 0.1 "float32"; $n.value = 0.1
        Assert-RGBTestThrows { Read-SwiftUIColorRGBNumber $n "float32" "test" } 'VALUE_BITS_MISMATCH' "short decimal cannot impersonate widened Float"
        $n = New-SwiftUIColorRGBNumber ([double]::NaN) "float64"; $n.kind = "finite"; $n.value = 0
        Assert-RGBTestThrows { Read-SwiftUIColorRGBNumber $n "float64" "test" } 'KIND_BITS_MISMATCH' "nonfinite bits cannot be zero"
        $n = New-SwiftUIColorRGBNumber ([double][single]0.88082504) "float32"
        $n.value = [decimal]::Parse('0.88082504272460938', [Globalization.CultureInfo]::InvariantCulture)
        Assert-RGBTest ((Read-SwiftUIColorRGBNumber $n "float32" "test").bitPattern -ceq '3f617dc0') "PS5 Decimal reader retains exact widened Float"
        $n.value = [decimal]::Parse('0.88082504272460949', [Globalization.CultureInfo]::InvariantCulture)
        Assert-RGBTestThrows { Read-SwiftUIColorRGBNumber $n "float32" "test" } 'VALUE_BITS_MISMATCH' "neighbor Double cannot impersonate Float"
    }
    Invoke-RGBTestCase "strict JSON grammar" {
        foreach ($json in @('{"x":1,"x":2}', '{"x":1,"X":2}', '{"x":1,"\u0078":2}', '{"a":{"x":0,"x":1}}')) { Assert-RGBTestThrows { Assert-SwiftUIColorRGBJsonGrammar $json } 'DUPLICATE_JSON_KEY' "duplicate keys" }
        foreach ($json in @('[]', '{"x":1,}', '{"x":[1,]}', '{"x":01}', '{"x":NaN}', '{"x":Infinity}', '{"x":/*comment*/1}', '{}{}', '{', '{"x":true false}')) { Assert-RGBTestThrows { Assert-SwiftUIColorRGBJsonGrammar $json } 'RGB_' "malformed JSON" }
        Assert-SwiftUIColorRGBJsonGrammar '{"x":[{},[],null,true,false,-1.2e+3,"escaped \\ \" \u0061"],"a":{"x":1}}'
        Assert-RGBTest $true "valid nested JSON"
        $path = Join-Path $script:RGBTestRoot "large-metadata.json"; Write-RGBTestText $path '{"long":"0123456789"}'
        Assert-RGBTestThrows { Read-SwiftUIColorRGBJson $path 8 } 'BYTE_LIMIT' "bounded metadata"
        $bom = Join-Path $script:RGBTestRoot "bom.json"; [IO.File]::WriteAllBytes($bom, [byte[]]@(239,187,191,123,125))
        Assert-RGBTestThrows { Read-SwiftUIColorRGBJson $bom } 'BOM' "strict UTF-8 JSON"
    }
    Invoke-RGBTestCase "managed grammar limits and controlled file-reader errors" {
        $path = Join-Path $script:RGBTestRoot 'grammar-boundaries.json'
        $depth48 = '{"x":' + ('[' * 47) + '0' + (']' * 47) + '}'
        Write-RGBTestText $path $depth48; $null = Read-SwiftUIColorRGBJson $path
        Assert-RGBTest $true 'root plus 47 arrays is depth 48'
        Write-RGBTestText $path ('{"x":' + ('[' * 48) + '0' + (']' * 48) + '}')
        Assert-RGBTestThrows { Read-SwiftUIColorRGBJson $path } '^RGB_JSON_DEPTH_LIMIT$' 'depth 49 rejected through file reader'
        Write-RGBTestText $path ('{"x":[' + ('0,' * 249996) + '{}]}')
        Assert-RGBTest ((Read-SwiftUIColorRGBJson $path).x.Count -eq 249997) 'exactly 500000 tokens accepted'
        Write-RGBTestText $path ('{"x":[' + ('0,' * 249997) + '0]}')
        Assert-RGBTestThrows { Read-SwiftUIColorRGBJson $path } '^RGB_JSON_TOKEN_LIMIT$' '500001 tokens rejected through file reader'
        Write-RGBTestText $path '{"key":1,"\u004bey":2}'
        Assert-RGBTestThrows { Read-SwiftUIColorRGBJson $path } '^RGB_DUPLICATE_JSON_KEY$' 'decoded case collision controlled error'
        [IO.File]::WriteAllBytes($path, [byte[]]@(123,34,120,34,58,34,237,160,128,34,125))
        Assert-RGBTestThrows { Read-SwiftUIColorRGBJson $path } '^RGB_JSON_INVALID_UTF8$' 'UTF8 cannot encode lone surrogate'
        $first = Initialize-SwiftUIColorRGBJsonHelper; $again = Initialize-SwiftUIColorRGBJsonHelper
        Assert-RGBTest ($first.type -eq $again.type -and $first.type.FullName.EndsWith($first.templateSha256) -and $first.type.GetField('SourceIdentity').GetRawConstantValue() -ceq $first.templateSha256) 'loaded type is bound to exact embedded source'
    }
    Invoke-RGBTestCase "Unicode strings and surrogate rejection" {
        $path = Join-Path $script:RGBTestRoot 'unicode-json.json'
        $pair = [char]0xd83d + [string][char]0xde00
        Write-RGBTestText $path ('{"escaped":"\ud83d\ude00","raw":"' + $pair + '","controls":"\b\f\n\r\t\\\"\/"}')
        $value = Read-SwiftUIColorRGBJson $path
        Assert-RGBTest ($value.escaped -ceq $pair -and $value.raw -ceq $pair -and $value.controls.Length -eq 8) 'valid escaped and raw Unicode pairs preserved'
        foreach ($json in @('{"x":"\ud800"}', '{"x":"\udc00"}', '{"x":"\ud800x"}', '{"x":"\ud800\u0061"}')) {
            Write-RGBTestText $path $json
            Assert-RGBTestThrows { Read-SwiftUIColorRGBJson $path } '^RGB_INVALID_JSON_SURROGATE$' 'unpaired escaped surrogate'
        }
        Assert-RGBTestThrows { Assert-SwiftUIColorRGBJsonGrammar ('{"x":"' + [char]0xd800 + '"}') } '^RGB_INVALID_JSON_SURROGATE$' 'raw unpaired surrogate'
        Write-RGBTestText $path ('{"\ud83d\ude00":1,"' + $pair + '":2}')
        Assert-RGBTestThrows { Read-SwiftUIColorRGBJson $path } '^RGB_DUPLICATE_JSON_KEY$' 'raw and escaped Unicode key collision'
    }
    Invoke-RGBTestCase 'PS5 reserved metadata keys cannot disappear' {
        $path = Join-Path $script:RGBTestRoot 'reserved-key.json'
        foreach ($json in @('{"__type":"opaque","value":1}', '{"nested":{"__type":"opaque","value":1}}', '{"\u005f_type":"opaque"}', '{"__Type":"opaque"}', '{"items":[{"__type":"opaque"}]}')) {
            Write-RGBTestText $path $json
            Assert-RGBTestThrows { Read-SwiftUIColorRGBJson $path } '^RGB_JSON_RESERVED_KEY$' 'decoded reserved key rejected before host data loss'
        }
        Write-RGBTestText $path '{"value":"__type","nested":["__Type"]}'
        $value = Read-SwiftUIColorRGBJson $path
        Assert-RGBTest ($value.value -ceq '__type' -and $value.nested[0] -ceq '__Type') 'reserved spelling is allowed as ordinary string data'
        $raw = New-RGBTestRawReport 'windows-retained'; $raw | Add-Member NoteProperty '__type' 'opaque'
        Assert-RGBTestThrows { Save-RGBTestReport $raw } '^RGB_JSON_RESERVED_KEY$' 'unknown report field cannot evade exact field validation'
    }
    Invoke-RGBTestCase "lossless JSON strings and array shapes" {
        $json = '{"z":"2026-08-28T00:00:00.0000000Z","offset":"2026-08-28T01:02:03.1234567+05:30","plain":"2026-08-28","legacy":"/Date(0)/","legacyEscaped":"\/Date(0)\/","legacyUnicode":"\u002fDate(0)\u002f","null":null,"empty":[],"oneNull":[null],"one":[1],"nested":[[],[null],[1]],"escaped":"a\\b\n\"c","blank":"","Type":"plain-type-data","Value":"unchanged","Properties":"text","Children":"text","$type":"NotAType","$id":"1","$ref":"other","$values":[2],"integer":2147483648,"\u006bey":"escaped-name"}'
        $path = Join-Path $script:RGBTestRoot 'lossless-json.json'; Write-RGBTestText $path $json
        $modes = @('current')
        $null = ConvertFrom-Json -InputObject '{}'
        if ($null -ne ('Newtonsoft.Json.JsonSerializerSettings' -as [type])) { $modes += 'fallback' }
        foreach ($mode in $modes) {
            $value = if ($mode -ceq 'fallback') { $script:RGBTestFallbackExercised = $true; ConvertFrom-SwiftUIColorRGBJsonText $json -ForceNewtonsoftFallback } else { Read-SwiftUIColorRGBJson $path }
            Assert-RGBTest ($value.z -is [string] -and $value.z -ceq '2026-08-28T00:00:00.0000000Z') "$mode Z date remains exact string"
            Assert-RGBTest ($value.offset -is [string] -and $value.offset -ceq '2026-08-28T01:02:03.1234567+05:30' -and $value.plain -ceq '2026-08-28') "$mode offset and date text preserved"
            Assert-RGBTest ($value.legacy -is [string] -and $value.legacyEscaped -is [string] -and $value.legacyUnicode -is [string] -and $value.legacy -ceq '/Date(0)/' -and $value.legacyEscaped -ceq $value.legacy -and $value.legacyUnicode -ceq $value.legacy) "$mode legacy date spellings remain exact strings"
            Assert-RGBTest ($null -eq $value.null -and $value.empty -is [array] -and $value.empty.Count -eq 0 -and $value.oneNull -is [array] -and $value.oneNull.Count -eq 1 -and $null -eq $value.oneNull[0]) "$mode null and arrays remain distinct"
            Assert-RGBTest ($value.one -is [array] -and $value.one.Count -eq 1 -and $value.nested.Count -eq 3 -and $value.nested[0] -is [array] -and $value.nested[0].Count -eq 0 -and $value.nested[1] -is [array] -and $value.nested[1].Count -eq 1 -and $null -eq $value.nested[1][0] -and $value.nested[2] -is [array] -and $value.nested[2].Count -eq 1 -and $value.nested[2][0] -eq 1) "$mode singleton and nested arrays preserved"
            Assert-RGBTest ($value.escaped -ceq "a\b`n`"c" -and $value.blank -is [string] -and $value.blank.Length -eq 0) "$mode escaped and empty strings preserved"
            Assert-RGBTest ($value.Type -ceq 'plain-type-data' -and $value.Value -ceq 'unchanged' -and $value.Properties -ceq 'text' -and $value.Children -ceq 'text' -and $value.key -ceq 'escaped-name') "$mode CLR-looking and escaped keys are plain data"
            Assert-RGBTest ($value.'$type' -ceq 'NotAType' -and $value.'$id' -ceq '1' -and $value.'$ref' -ceq 'other' -and $value.'$values'[0] -eq 2) "$mode metadata-looking keys are plain data"
            Assert-RGBTest (($value.integer -is [long] -or $value.integer -is [int]) -and $value.integer -eq 2147483648) "$mode JSON integer retains integral storage"
        }
        if ($PSVersionTable.PSVersion.Major -ge 7) { Assert-RGBTest $script:RGBTestFallbackExercised 'public fallback exercised on bundled PowerShell Newtonsoft' }
        foreach ($slashes in 0..9) {
            Write-RGBTestText $path ('{"value":"' + ('\' * $slashes) + '/"}')
            Assert-RGBTest ((Read-SwiftUIColorRGBJson $path).value -ceq (('\' * [Math]::Floor($slashes / 2)) + '/')) "slash escape preserves backslash-run parity $slashes"
        }
    }
    Invoke-RGBTestCase "actual JSON numeric token and signed-zero evidence" {
        $path = Join-Path $script:RGBTestRoot 'numeric-token.json'
        $good = '{"kind":"finite","value":0.88082504272460938,"storage":"float32","bitPattern":"3f617dc0"}'
        Write-RGBTestText $path $good; $value = Read-SwiftUIColorRGBJson $path
        Assert-RGBTest ((Read-SwiftUIColorRGBNumber $value 'float32' 'rawtoken').value -eq [double][single]0.88082504) 'real reader preserves widened Float token'
        if ($PSVersionTable.PSVersion.Major -le 5) {
            Assert-RGBTest ($value.value -is [decimal]) 'PS5 raw token deserializes as Decimal'
            Assert-RGBTest ((Get-SwiftUIColorRGBBits ([double]$value.value)) -ceq '3fec2fb800000001') 'PS5 direct Decimal cast demonstrates neighboring Double'
            Assert-RGBTest ((Get-SwiftUIColorRGBBits ([double]::Parse($value.value.ToString([Globalization.CultureInfo]::InvariantCulture), [Globalization.CultureInfo]::InvariantCulture))) -ceq '3fec2fb800000000') 'invariant decimal parse restores exact Float widening'
        }
        Write-RGBTestText $path $good.Replace('0.88082504272460938', '0.88082504272460949')
        Assert-RGBTestThrows { Read-SwiftUIColorRGBNumber (Read-SwiftUIColorRGBJson $path) 'float32' 'rawtoken' } 'VALUE_BITS_MISMATCH' 'neighbor token remains rejected'
        foreach ($bits in @('00000000', '80000000')) {
            Write-RGBTestText $path ('{"kind":"finite","value":-0.0,"storage":"float32","bitPattern":"' + $bits + '"}')
            Assert-RGBTest ((Read-SwiftUIColorRGBNumber (Read-SwiftUIColorRGBJson $path) 'float32' 'zero').bitPattern -ceq $bits) 'zero numeric equality does not erase recorded sign bits'
        }
    }
    Invoke-RGBTestCase "bounds inside and outside" {
        Assert-RGBTest ((Get-SwiftUIColorRGBDelta 0 0.000001999999 "red").matches) "absolute just inside"
        Assert-RGBTest (-not (Get-SwiftUIColorRGBDelta 0 0.000002000001 "red").matches) "absolute just outside"
        Assert-RGBTest ((Get-SwiftUIColorRGBDelta 10 10.000019 "red").matches) "relative inside"
        Assert-RGBTest (-not (Get-SwiftUIColorRGBDelta 10 10.000020 "red").matches) "relative outside"
        Assert-RGBTest ((Get-SwiftUIColorRGBDelta 0 2.384185791015625e-7 "alpha").matches) "alpha exact bound"
        Assert-RGBTest (-not (Get-SwiftUIColorRGBDelta 0 2.384185791115625e-7 "alpha").matches) "alpha outside"
        Assert-RGBTest ((Get-SwiftUIColorRGBDelta ([double]::NaN) 0 "red").status -ceq "nonfinite") "nonfinite has no manufactured delta"
    }
    $script:RGBTestWindowsReports = New-RGBTestReports "windows-retained"
    $script:RGBTestResolvedReports = New-RGBTestReports "swiftui-resolved"
    $script:RGBTestAppKitReports = New-RGBTestReports "appkit-extended-srgb"
    Invoke-RGBTestCase "required comparison counts" {
        $primary = Compare-SwiftUIColorRGBObserver $script:RGBTestWindowsReports $script:RGBTestResolvedReports "swiftui-resolved"
        $bridge = Compare-SwiftUIColorRGBObserver $script:RGBTestWindowsReports $script:RGBTestAppKitReports "appkit-extended-srgb"
        Assert-RGBTest ($primary.state -ceq "match-candidate" -and $primary.requiredComparisons -eq 552 -and $primary.exploratoryComparisons -eq 48) "primary exact counts"
        Assert-RGBTest ($bridge.state -ceq "match-candidate" -and $bridge.requiredComparisons -eq 276 -and $bridge.exploratoryComparisons -eq 24) "bridge exact counts"
        Assert-RGBTest (@($primary.rows | Where-Object { $_.component -ceq "alpha" -and $null -ne $_.bound }).Count -eq 150) "all alpha comparisons preserved"
        $missing = Compare-SwiftUIColorRGBObserver $script:RGBTestWindowsReports @($script:RGBTestResolvedReports[0..1]) "swiftui-resolved"
        Assert-RGBTest ($missing.state -ceq "failure") "missing repeat fails, no AppKit substitution"
    }
    $reportChanges = @(
        @{ name = "missing case"; change = { param($r) $r.cases = @($r.cases[0..23]) } },
        @{ name = "duplicate case"; change = { param($r) $r.cases[24] = Copy-RGBTestValue $r.cases[0] } },
        @{ name = "unknown case"; change = { param($r) $r.cases[0].caseId = "other" } },
        @{ name = "case reclassified"; change = { param($r) $r.cases[0].domain = "exploratory-extended-p3" } },
        @{ name = "source space wrong"; change = { param($r) $r.cases[0].sourceSpace = "display-p3" } },
        @{ name = "wrong input"; change = { param($r) $r.cases[0].input.red = New-SwiftUIColorRGBNumber 0.1 "float64" } },
        @{ name = "wrong output storage"; change = { param($r) $r.cases[0].observations[0].encodedRGBA.red = New-SwiftUIColorRGBNumber 0 "float64" } },
        @{ name = "missing environment"; change = { param($r) $r.cases[0].observations = @($r.cases[0].observations[0]) } },
        @{ name = "duplicate environment"; change = { param($r) $r.cases[0].observations[1].environment = "light" } },
        @{ name = "unknown environment"; change = { param($r) $r.cases[0].observations[0].environment = "system" } },
        @{ name = "linear missing"; change = { param($r) $r.cases[0].observations[0].linearRGB = $null } },
        @{ name = "unknown property"; change = { param($r) $r | Add-Member NoteProperty qualified $true } },
        @{ name = "wrong protocol"; change = { param($r) $r.protocolId = "other-v1" } },
        @{ name = "schema string"; change = { param($r) $r.schemaVersion = "1" } },
        @{ name = "collection unfinished"; change = { param($r) $r.collectionStatus = "started" } },
        @{ name = "scalar cases"; change = { param($r) $r.cases = $r.cases[0] } },
        @{ name = "array sourceSpace"; change = { param($r) $r.cases[0].sourceSpace = @() } },
        @{ name = "unsupported with numbers"; change = { param($r) $r.cases[0].observations[0].status = "unsupported"; $r.cases[0].observations[0].reason = "unavailable" } },
        @{ name = "observed reason"; change = { param($r) $r.cases[0].observations[0].reason = "unexpected" } },
        @{ name = "nonfinite JSON number"; change = { param($r) $r.cases[0].observations[0].encodedRGBA.red.value = $null } }
    )
    foreach ($change in $reportChanges) {
        Invoke-RGBTestCase ("report rejects " + $change.name) {
            $raw = New-RGBTestRawReport "swiftui-resolved"; & $change.change $raw
            Assert-RGBTestThrows { Save-RGBTestReport $raw } 'RGB_' $change.name
        }
    }
    Invoke-RGBTestCase "stale nonce and observer" {
        $raw = New-RGBTestRawReport "windows-retained"; $path = Join-Path $script:RGBTestRoot "nonce.json"; Write-RGBTestJson $path $raw
        Assert-RGBTestThrows { Read-SwiftUIColorRGBReport $path "windows-retained" ([Guid]::NewGuid().ToString("D")) "x86_64" } 'IDENTITY_MISMATCH' "stale nonce"
        Assert-RGBTestThrows { Read-SwiftUIColorRGBReport $path "swiftui-resolved" $raw.runId "x86_64" } 'IDENTITY_MISMATCH' "wrong observer"
        Assert-RGBTestThrows { Read-SwiftUIColorRGBReport $path "windows-retained" $raw.runId "arm64" } 'RUNTIME_MISMATCH' "wrong architecture"
    }
    Invoke-RGBTestCase "Windows finite errors remain mismatches" {
        foreach ($kind in @("clipping", "one-repeat", "alpha", "premultiply")) {
            $reports = @()
            for ($r = 1; $r -le 3; $r++) {
                $raw = New-RGBTestRawReport "windows-retained"
                if ($kind -ceq "clipping") { Set-RGBTestComponents $raw "srgb-extended" "red" 0 }
                if ($kind -ceq "one-repeat" -and $r -eq 2) { Set-RGBTestComponents $raw "p3-neutral" "green" 0.7 }
                if ($kind -ceq "alpha") { Set-RGBTestComponents $raw "srgb-alpha-fraction" "alpha" 1 }
                if ($kind -ceq "premultiply") { Set-RGBTestComponents $raw "srgb-alpha-zero" "red" 0 }
                $reports += Save-RGBTestReport $raw
            }
            $result = Compare-SwiftUIColorRGBObserver $reports $script:RGBTestResolvedReports "swiftui-resolved"
            Assert-RGBTest ($result.state -ceq "mismatch" -and $result.nativeObserverControls.state -ceq "healthy") "$kind is mismatch"
        }
    }
    Invoke-RGBTestCase "native zero alpha is an observation" {
        $reports = @()
        for ($r = 1; $r -le 3; $r++) { $raw = New-RGBTestRawReport "swiftui-resolved"; Set-RGBTestComponents $raw "srgb-alpha-zero" "red" 0; $reports += Save-RGBTestReport $raw }
        $result = Compare-SwiftUIColorRGBObserver $script:RGBTestWindowsReports $reports "swiftui-resolved"
        Assert-RGBTest ($result.state -ceq "mismatch" -and $result.nativeObserverControls.state -ceq "healthy") "native alpha-zero does not invalidate reference"
    }
    Invoke-RGBTestCase "Windows nonfinite failure outranks unsupported" {
        $reports = @()
        1..3 | ForEach-Object {
            $raw = New-RGBTestRawReport "windows-retained"
            $raw.cases[0].observations[0].status = 'unsupported'; $raw.cases[0].observations[0].reason = 'synthetic-unavailable'; $raw.cases[0].observations[0].encodedRGBA = $null
            Set-RGBTestComponents $raw 'p3-neutral' 'red' ([double]::NaN)
            $reports += Save-RGBTestReport $raw
        }
        $result = Compare-SwiftUIColorRGBObserver $reports $script:RGBTestResolvedReports 'swiftui-resolved'
        Assert-RGBTest ($result.state -ceq 'failure') 'mixed unsupported cannot mask nonfinite Windows failure'
    }
    Invoke-RGBTestCase "native control failures remain inconclusive" {
        foreach ($kind in @("clipped", "wrong-getter", "nonfinite", "unstable", "light-dark", "constant")) {
            $reports = @()
            for ($r = 1; $r -le 3; $r++) {
                $raw = New-RGBTestRawReport "swiftui-resolved"
                if ($kind -ceq "clipped") { Set-RGBTestComponents $raw "srgb-extended" "red" 0 }
                if ($kind -ceq "wrong-getter") { Set-RGBTestComponents $raw "linear-interior" "green" 0.5 }
                if ($kind -ceq "nonfinite") { Set-RGBTestComponents $raw "p3-neutral" "green" ([double]::NaN) }
                if ($kind -ceq "unstable" -and $r -eq 2) { Set-RGBTestComponents $raw "p3-neutral" "green" 0.7 }
                if ($kind -ceq "light-dark") { $raw.cases[2].observations[1].encodedRGBA.red = New-SwiftUIColorRGBNumber 0.4 "float32" }
                if ($kind -ceq "constant") { foreach ($case in $raw.cases) { foreach ($observation in $case.observations) { foreach ($c in @("red", "green", "blue")) { $observation.encodedRGBA.$c = New-SwiftUIColorRGBNumber 0 "float32" } } } }
                $reports += Save-RGBTestReport $raw
            }
            $result = Compare-SwiftUIColorRGBObserver $script:RGBTestWindowsReports $reports "swiftui-resolved"
            Assert-RGBTest ($result.state -ceq "unsupported" -and $result.nativeObserverControls.state -ceq "inconclusive") "$kind reference does not qualify"
        }
    }
    Invoke-RGBTestCase "AppKit unavailable metadata retained" {
        foreach ($kind in @("nil", "model", "identity", "count")) {
            $reports = @()
            for ($r = 1; $r -le 3; $r++) {
                $raw = New-RGBTestRawReport "appkit-extended-srgb"; $observation = $raw.cases[0].observations[0]
                $observation.status = "unsupported"; $observation.encodedRGBA = $null; $observation.reason = "synthetic-$kind"
                if ($kind -ceq "nil") { $observation.appKit = $null }
                if ($kind -ceq "model") { $observation.appKit.colorSpaceModel = "pattern"; $observation.appKit.componentCount = $null; $observation.appKit.targetIdentityMatches = $false }
                if ($kind -ceq "identity") { $observation.appKit.targetIdentityMatches = $false }
                if ($kind -ceq "count") { $observation.appKit.componentCount = 3 }
                $reports += Save-RGBTestReport $raw
            }
            Assert-RGBTest ((Compare-SwiftUIColorRGBObserver $script:RGBTestWindowsReports $reports "appkit-extended-srgb").state -ceq "unsupported") "$kind remains unsupported"
        }
        $raw = New-RGBTestRawReport "appkit-extended-srgb"; $raw.cases[0].observations[0].appKit.targetIdentityMatches = $false
        Assert-RGBTestThrows { Save-RGBTestReport $raw } 'APPKIT_UNEXPECTED_OBSERVED_SPACE' "wrong AppKit observed identity"
    }
    Invoke-RGBTestCase "exploratory differences do not change required domain" {
        $reports = @()
        1..3 | ForEach-Object { $raw = New-RGBTestRawReport "windows-retained"; Set-RGBTestComponents $raw "p3-extended-input" "red" 20; $reports += Save-RGBTestReport $raw }
        $result = Compare-SwiftUIColorRGBObserver $reports $script:RGBTestResolvedReports "swiftui-resolved"
        Assert-RGBTest ($result.state -ceq "match-candidate") "required agreement unchanged"
        Assert-RGBTest (@($result.rows | Where-Object { $_.domain -ceq "exploratory-extended-p3" -and $_.state -ceq "mismatch" }).Count -eq 6) "all exploratory differences retained"
    }
    $script:RGBTestWindowsCapture = New-RGBTestCapture "windows"
    $script:RGBTestNativeCapture = New-RGBTestCapture "native"
    $script:RGBTestValidatedWindows = Read-SwiftUIColorRGBCapture $script:RGBTestWindowsCapture.root
    $script:RGBTestValidatedNative = Read-SwiftUIColorRGBCapture $script:RGBTestNativeCapture.root
    Invoke-RGBTestCase "sealed captures compare with exact provenance" {
        $result = Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows $script:RGBTestValidatedNative
        Assert-RGBTest ($result.state -ceq "match-candidate" -and $result.appKit.state -ceq "match-candidate") "complete synthetic captures match"
        Assert-RGBTest ($result.sourceCompilation.native.typechecks.Count -eq 2) "both typechecks preserved"
        Assert-RGBTest (@($result.sourceCompilation.native.typechecks | Where-Object nativeExecution).Count -eq 0) "typecheck is not execution"
    }
    $captureChanges = @(
        @{ name = "source dirty"; native = $false; change = { param($f) $f.manifest.source.clean = $false } },
        @{ name = "qualifies release"; native = $false; change = { param($f) $f.manifest.qualification.releaseQualified = $true } },
        @{ name = "qualifies behavior"; native = $false; change = { param($f) $f.manifest.qualification.behaviorReview = "verified" } },
        @{ name = "missing repeat"; native = $false; change = { param($f) $f.manifest.runs = @($f.manifest.runs[0..1]) } },
        @{ name = "duplicate repeat"; native = $false; change = { param($f) $f.manifest.runs[2].repetition = 1 } },
        @{ name = "duplicate nonce"; native = $false; change = { param($f) $f.manifest.runs[2].runId = $f.manifest.runs[0].runId } },
        @{ name = "wrong process ID"; native = $false; change = { param($f) $id = $f.manifest.runs[0].commandId; @($f.commands | Where-Object { $_.commandId -ceq $id })[0].processId = 99999 } },
        @{ name = "wrong report path"; native = $false; change = { param($f) $id = $f.manifest.runs[0].commandId; @($f.commands | Where-Object { $_.commandId -ceq $id })[0].arguments[5] = 'C:/elsewhere/windows-retained-1.json' } },
        @{ name = "wrong OS version"; native = $false; change = { param($f) $f.manifest.runtimeEligibility.operatingSystemVersion = '10.0.11111' } },
        @{ name = "wrong observer exe hash"; native = $false; change = { param($f) $id = $f.manifest.runs[0].commandId; @($f.commands | Where-Object { $_.commandId -ceq $id })[0].executableSha256 = 'f' * 64 } },
        @{ name = "wrong build product"; native = $false; change = { param($f) $id = $f.manifest.sourceCompilation.buildCommandId; @($f.commands | Where-Object { $_.commandId -ceq $id })[0].arguments[6] = 'other-product' } },
        @{ name = "wrong build compiler hash"; native = $false; change = { param($f) $id = $f.manifest.sourceCompilation.buildCommandId; @($f.commands | Where-Object { $_.commandId -ceq $id })[0].executableSha256 = 'f' * 64 } },
        @{ name = "missing binary path command"; native = $false; change = { param($f) $f.manifest.sourceCompilation.binaryPathCommandId = $null } },
        @{ name = "unrelated binary path"; native = $false; change = { param($f) $f.manifest.binary.originalPath = 'C:/other/reference.exe' } },
        @{ name = "missing dependency snapshot"; native = $false; change = { param($f) $f.manifest.source.buildInputs = @($f.manifest.source.buildInputs | Where-Object { $_.path -cne 'Sources/WinSwiftUI/Core.swift' }) } },
        @{ name = "shared build copy mismatch"; native = $false; change = { param($f) $f.manifest.source.sharedSources[0].gitBlob = 'f' * 40 } },
        @{ name = "wrong SDK path argument"; native = $true; change = { param($f) $id = $f.manifest.sourceCompilation.typechecks[0].commandId; @($f.commands | Where-Object { $_.commandId -ceq $id })[0].arguments[6] = '/another/sdk' } },
        @{ name = "wrong source argument"; native = $true; change = { param($f) $id = $f.manifest.sourceCompilation.typechecks[0].commandId; $c = @($f.commands | Where-Object { $_.commandId -ceq $id })[0]; $c.arguments[$c.arguments.Count - 1] = '/another/main.swift' } },
        @{ name = "wrong language mode"; native = $true; change = { param($f) $id = $f.manifest.sourceCompilation.typechecks[0].commandId; @($f.commands | Where-Object { $_.commandId -ceq $id })[0].arguments[2] = '5' } },
        @{ name = "wrong typecheck compiler path"; native = $true; change = { param($f) $id = $f.manifest.sourceCompilation.typechecks[0].commandId; @($f.commands | Where-Object { $_.commandId -ceq $id })[0].executable = '/other/swiftc' } },
        @{ name = "only one architecture"; native = $true; change = { param($f) $f.manifest.sourceCompilation.typechecks = @($f.manifest.sourceCompilation.typechecks[0]) } },
        @{ name = "cross arch claims execution"; native = $true; change = { param($f) $f.manifest.sourceCompilation.typechecks[0].nativeExecution = $true } },
        @{ name = "typecheck exit nonzero"; native = $true; change = { param($f) $id = $f.manifest.sourceCompilation.typechecks[0].commandId; @($f.commands | Where-Object { $_.commandId -ceq $id })[0].exitCode = 1 } },
        @{ name = "unrelated native executable"; native = $true; change = { param($f) $f.manifest.binary.originalPath = '/other/reference-executable' } },
        @{ name = "source SDK not rechecked"; native = $true; change = { param($f) $f.manifest.sdk.afterVerified = $false } },
        @{ name = "wrong native version line"; native = $true; change = { param($f) $f.manifest.toolchain.versionLine += ' changed-build' } },
        @{ name = "wrong native runtime floor"; native = $true; change = { param($f) $f.manifest.runtimeEligibility.operatingSystemVersion = '26.4.0' } },
        @{ name = "translated native eligible"; native = $true; change = { param($f) $f.manifest.runtimeEligibility.hardwareArchitecture = 'arm64'; $f.manifest.runtimeEligibility.translated = $true } }
    )
    foreach ($change in $captureChanges) {
        Invoke-RGBTestCase ("capture rejects " + $change.name) {
            $source = if ($change.native) { $script:RGBTestNativeCapture } else { $script:RGBTestWindowsCapture }
            $fixture = Copy-RGBTestCapture $source; & $change.change $fixture; Publish-RGBTestCapture $fixture
            Assert-RGBTestThrows { Read-SwiftUIColorRGBCapture $fixture.root } 'RGB_' $change.name
        }
    }
    Invoke-RGBTestCase "actual snapshot helpers preserve the committed plus-name input" {
        # Execute the unmodified production functions, never the collection
        # entrypoint. Only Git replies are synthetic; no process or Swift runs.
        $tokens = $null; $errors = $null
        $captureAST = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepositoryRoot 'scripts/capture-swiftui-color-rgb-reference.ps1'), [ref]$tokens, [ref]$errors)
        Assert-RGBTest ($errors.Count -eq 0) 'capture source parses before extracting snapshot helpers'
        foreach ($name in @('Assert-RGBCheckout', 'Copy-RGBSourceEntries', 'New-RGBSourceSnapshot')) {
            $definitions = @($captureAST.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq $name })
            Assert-RGBTest ($definitions.Count -eq 1) "exactly one top-level production helper $name"
            . ([scriptblock]::Create($definitions[0].Extent.Text))
        }
        $savedVariables = @{}
        foreach ($name in @('rgbRepository', 'rgbOutput', 'rgbGitBlobs', 'rgbSourceOriginals', 'Platform', 'rgbSnapshotGitReplies', 'rgbSnapshotGitCalls')) {
            $variable = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
            $savedVariables[$name] = [pscustomobject]@{ existed = ($null -ne $variable); value = $(if ($null -ne $variable) { $variable.Value } else { $null }) }
        }
        try {
            Assert-RGBTest ($script:RGBTestRoot -ceq (Resolve-SwiftUIBaselineFileSystemPath $script:RGBTestRoot)) 'the owned synthetic root is physical before snapshot fixtures use it'
            $physicalTemp = Resolve-SwiftUIBaselineFileSystemPath ([IO.Path]::GetTempPath())
            Assert-RGBTest ((Get-SwiftUIBaselineRelativePath -Root $physicalTemp -Path $script:RGBTestRoot) -ceq (Split-Path -Leaf $script:RGBTestRoot)) 'the cleanup root remains one owned UUID child of the physical temp directory'
            Assert-RGBTestThrows { Get-SwiftUIBaselineRelativePath -Root $script:RGBTestRoot -Path ($script:RGBTestRoot + '-sibling/child') } 'not contained' 'strict containment still rejects a sibling sharing the fixture prefix'
            $plusName = 'Sources/SwiftWindowsApp/FoundationApp+DefaultRenderer.swift'
            $plusBytes = [IO.File]::ReadAllBytes((Join-Path $RepositoryRoot $plusName))
            $plusHash = Get-SwiftUIColorRGBHash (Join-Path $RepositoryRoot $plusName)
            $fixtureRoot = Join-Path $script:RGBTestRoot 'actual-source-snapshot'
            $script:rgbRepository = Join-Path $fixtureRoot 'synthetic-repository'
            $script:rgbOutput = Join-Path $fixtureRoot 'evidence'
            $script:Platform = 'Windows'
            $script:rgbSourceOriginals = [System.Collections.Generic.List[object]]::new()
            $script:rgbSnapshotGitReplies = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
            $script:rgbSnapshotGitCalls = [System.Collections.Generic.List[string]]::new()
            $collectorNames = @('scripts/capture-swiftui-color-rgb-reference.ps1', 'scripts/swiftui-color-rgb-reference-common.ps1',
                'scripts/compare-swiftui-color-rgb-reference.ps1', 'scripts/swiftui-material-reference-common.ps1',
                'scripts/swiftui-baseline-common.ps1', 'scripts/with-swift.ps1', 'docs/swiftui-baseline.json')
            $sourceNames = @(Get-SwiftUIColorRGBSourceNames) + @('Package.swift', $plusName) + $collectorNames
            $treeRows = [System.Collections.Generic.List[string]]::new()
            foreach ($sourceName in $sourceNames) {
                $path = Join-Path $script:rgbRepository $sourceName
                if ($sourceName -ceq $plusName) {
                    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path)); [IO.File]::WriteAllBytes($path, $plusBytes)
                } else { Write-RGBTestText $path "// SYNTHETIC snapshot input only: $sourceName`n" }
                $blob = Get-SwiftUIColorRGBGitBlobHash ([IO.File]::ReadAllBytes($path))
                $treeRows.Add('100644 blob ' + $blob + [char]9 + $sourceName)
            }
            $script:rgbSnapshotGitReplies[(('rev-parse', 'HEAD') -join "`t")] = '1' * 40
            $script:rgbSnapshotGitReplies[(('rev-parse', 'HEAD^{tree}') -join "`t")] = '2' * 40
            $script:rgbSnapshotGitReplies[(('status', '--porcelain', '--untracked-files=no') -join "`t")] = ''
            $script:rgbSnapshotGitReplies[(('ls-files', '-v') -join "`t")] = (($sourceNames | ForEach-Object { "H $_" }) -join "`n")
            $script:rgbSnapshotGitReplies[(('ls-files', '--others', '--', 'Sources', 'Package.swift', 'Package.resolved', '.swiftpm/configuration') -join "`t")] = ''
            $script:rgbSnapshotGitReplies[(('-c', 'core.quotepath=false', 'ls-tree', '-r', 'HEAD') -join "`t")] = $treeRows -join "`n"
            function Invoke-RGBGit {
                param([string[]]$Arguments, [int]$MaxBytes = 1048576)
                $key = $Arguments -join "`t"
                if (-not $script:rgbSnapshotGitReplies.ContainsKey($key)) { throw 'Unexpected synthetic Git request; no external command may run.' }
                $script:rgbSnapshotGitCalls.Add($key)
                return $script:rgbSnapshotGitReplies[$key]
            }
            $snapshot = New-RGBSourceSnapshot
            Assert-RGBTest ($script:rgbSnapshotGitCalls.Count -eq 6) 'actual checkout and snapshot helpers used only six exact synthetic Git replies'
            Assert-RGBTest ($snapshot.sharedSources.Count -eq 5 -and $snapshot.buildInputs.Count -eq 7 -and $snapshot.collectorSources.Count -eq 7) 'snapshot includes every synthetic tracked build input and collector dependency'
            $plusEntries = @($snapshot.buildInputs | Where-Object { $_.path -ceq $plusName })
            Assert-RGBTest ($plusEntries.Count -eq 1) 'actual Windows source selection retains exactly one plus-named build input'
            $entry = $plusEntries[0]
            Assert-RGBTest ($entry.file.evidenceFile -ceq "sources/build-inputs/$plusName") 'actual writer preserves the plus spelling in the evidence path'
            Assert-RGBTest ($entry.gitBlob -ceq (Get-SwiftUIColorRGBGitBlobHash $plusBytes) -and $entry.byteIdentity -ceq 'git-blob-exact') 'copied committed-source bytes retain their exact Git blob identity'
            Assert-RGBTest ($entry.file.sha256 -ceq $plusHash -and $entry.file.bytes -eq $plusBytes.Length) 'copied plus-name bytes and length match the real repository input'
            Assert-SwiftUIColorRGBSourceSnapshot $script:rgbOutput $snapshot
            Assert-RGBTest $true 'actual source and evidence-path validators accept the complete helper-produced snapshot'
            $copiedPath = Get-SwiftUIColorRGBEvidencePath $script:rgbOutput $entry.file.evidenceFile
            Assert-RGBTest ((Get-SwiftUIColorRGBHash $copiedPath) -ceq $plusHash -and (Get-SwiftUIColorRGBHash (Join-Path $RepositoryRoot $plusName)) -ceq $plusHash) 'archive and original retain identical physical bytes'
            foreach ($badName in @('Sources/../X+Y.swift', 'Sources/./X+Y.swift', 'Sources\X+Y.swift', 'C:/X+Y.swift', 'Sources/X+Y.swift:stream')) {
                Assert-RGBTestThrows { Copy-RGBSourceEntries @($badName) 'rejected' } 'RGB_SOURCE_PATH_UNSUPPORTED' "actual source writer still rejects $badName"
                $changed = Copy-RGBTestValue $snapshot
                @($changed.buildInputs | Where-Object { $_.path -ceq $plusName })[0].path = $badName
                Assert-RGBTestThrows { Assert-SwiftUIColorRGBSourceSnapshot $script:rgbOutput $changed } 'RGB_SOURCE_FILE_IDENTITY_INVALID' "source snapshot reader still rejects $badName"
            }
        } finally {
            foreach ($name in $savedVariables.Keys) {
                if ($savedVariables[$name].existed) { Set-Variable -Name $name -Scope Script -Value $savedVariables[$name].value }
                else { Remove-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue }
            }
        }
    }
    Invoke-RGBTestCase "physical source tampering and CRLF policy" {
        $file = Join-Path $script:RGBTestRoot "blob.txt"; Write-RGBTestText $file "first`nsecond`n"
        $blob = Get-SwiftUIColorRGBGitBlobHash ([IO.File]::ReadAllBytes($file))
        Assert-RGBTest ((Get-SwiftUIColorRGBSourceByteIdentity $file $blob) -ceq "git-blob-exact") "exact blob"
        Write-RGBTestText $file "first`r`nsecond`r`n"
        Assert-RGBTest ((Get-SwiftUIColorRGBSourceByteIdentity $file $blob) -ceq "git-blob-after-crlf-normalization") "CRLF representation explicit"
        Write-RGBTestText $file "first`r`nchanged`r`n"
        Assert-RGBTestThrows { Get-SwiftUIColorRGBSourceByteIdentity $file $blob } 'NOT_COMMITTED_BLOB' "changed source rejected even with claimed clean Git status"
        $fixture = Copy-RGBTestCapture $script:RGBTestWindowsCapture
        $entry = $fixture.manifest.source.sharedSources[0]; $path = Join-Path $fixture.root $entry.file.evidenceFile
        [IO.File]::AppendAllText($path, "// changed", $script:RGBTestUTF8)
        $entry.file = Get-SwiftUIColorRGBFileRecord $path $entry.file.evidenceFile
        Publish-RGBTestCapture $fixture
        Assert-RGBTestThrows { Read-SwiftUIColorRGBCapture $fixture.root } 'NOT_COMMITTED_BLOB' "rehashing physical source cannot change its HEAD blob"
    }
    Invoke-RGBTestCase "raw files and seals stay authoritative" {
        foreach ($kind in @("report", "source", "log", "binary", "seal")) {
            $f = Copy-RGBTestCapture $script:RGBTestWindowsCapture
            $path = switch ($kind) {
                "report" { Join-Path $f.root $f.manifest.runs[0].report.evidenceFile }
                "source" { Join-Path $f.root $f.manifest.source.sharedSources[0].file.evidenceFile }
                "log" { Join-Path $f.root $f.commands[0].stdout.evidenceFile }
                "binary" { Join-Path $f.root $f.manifest.binary.file.evidenceFile }
                "seal" { Join-Path $f.root "capture.sha256" }
            }
            [IO.File]::AppendAllText($path, "tampered", $script:RGBTestUTF8)
            Assert-RGBTestThrows { Read-SwiftUIColorRGBCapture $f.root } '(MISMATCH|LENGTH)' "$kind tamper"
            Assert-RGBTest ([IO.File]::ReadAllText($path).EndsWith("tampered")) "raw $kind not rewritten during rejection"
        }
    }
    Invoke-RGBTestCase "global source mismatch prevents primary promotion" {
        $f = Copy-RGBTestCapture $script:RGBTestNativeCapture; $f.manifest.source.commit = '3' * 40; Publish-RGBTestCapture $f
        $native = Read-SwiftUIColorRGBCapture $f.root
        $result = Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows $native
        Assert-RGBTest ($result.state -ceq 'failure' -and $result.primary.rows.Count -eq 600) "source mismatch retains rows but fails"
        $f = Copy-RGBTestCapture $script:RGBTestNativeCapture; $f.manifest.status = 'failure'; $f.manifest.integrity.toolsUnchanged = $false; $f.manifest.failureCodes = @('RGB_TOOL_CHANGED'); Publish-RGBTestCapture $f
        $native = Read-SwiftUIColorRGBCapture $f.root
        Assert-RGBTest ((Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows $native).state -ceq 'failure') "unverified tool provenance prevents candidate"
    }
    Invoke-RGBTestCase "later integrity failure invalidates candidate states" {
        $result = Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows $script:RGBTestValidatedNative
        $count = $result.primary.rows.Count
        Set-SwiftUIColorRGBComparisonFailure $result 'RGB_CAPTURE_CHANGED_DURING_COMPARISON'
        Assert-RGBTest ($result.state -ceq 'failure' -and $result.primary.state -ceq 'failure' -and $result.appKit.state -ceq 'failure' -and $result.provenance.state -ceq 'failure') 'no stale candidate state after revalidation failure'
        Assert-RGBTest ($result.primary.rows.Count -eq $count -and $count -eq 600) 'raw comparison rows retained'
        $result = Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows $script:RGBTestValidatedNative
        Set-SwiftUIColorRGBComparisonFailure $result 'RGB_REVIEW_PACKET_CHANGED' -AssociationOnly
        Assert-RGBTest ($result.state -ceq 'failure' -and $result.primary.state -ceq 'match-candidate') 'association error remains separate from independently valid primary'
    }
    Invoke-RGBTestCase "unsupported runtime cannot hide actual Windows failure" {
        $native = [pscustomobject]@{ manifest = Copy-RGBTestValue $script:RGBTestValidatedNative.manifest; reports = @{ 'swiftui-resolved' = @(); 'appkit-extended-srgb' = @() } }
        $native.manifest.runtimeEligibility.state = 'unsupported'; $native.manifest.runtimeEligibility.reason = 'runtime-below-macos-26.5'
        $native.manifest.runtimeEligibility.operatingSystemVersion = '26.4.0'; $native.manifest.status = 'unsupported'; $native.manifest.runs = @()
        $result = Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows $native
        Assert-RGBTest ($result.state -ceq 'unsupported' -and $result.sourceCompilation.native.state -ceq 'compiled') 'compile-only older runtime remains unsupported'
        $reports = @()
        1..3 | ForEach-Object { $raw = New-RGBTestRawReport 'windows-retained'; Set-RGBTestComponents $raw 'p3-neutral' 'red' ([double]::NaN); $reports += Save-RGBTestReport $raw }
        $windows = [pscustomobject]@{ manifest = $script:RGBTestValidatedWindows.manifest; reports = @{ 'windows-retained' = $reports } }
        $result = Compare-SwiftUIColorRGBCaptures $windows $native
        Assert-RGBTest ($result.state -ceq 'failure' -and $result.primary.windowsObserverControls.state -ceq 'failure') 'Windows nonfinite failure outranks opposite runtime unavailability'
    }
    Invoke-RGBTestCase "bridge process failure never erases primary" {
        foreach ($reason in @('RGB_OBSERVER_PROCESS_FAILED', 'RGB_OBSERVER_REPORT_MISSING')) {
            $f = Copy-RGBTestCapture $script:RGBTestNativeCapture; Set-RGBTestBridgeFailure $f $reason
            Publish-RGBTestCapture $f; $native = Read-SwiftUIColorRGBCapture $f.root
            $result = Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows $native
            Assert-RGBTest ($result.state -ceq 'match-candidate' -and $result.appKit.state -ceq 'failure' -and $result.provenance.state -ceq 'verified-for-candidate') "primary independent of bound bridge failure $reason"
            Assert-RGBTest ($native.invalidRuns.Count -eq 3 -and $result.primary.rows.Count -eq 600) "failed bridge runs and valid primary rows preserved"
        }
    }
    Invoke-RGBTestCase 'bridge unsupported capture leaves primary independent' {
        $f = Copy-RGBTestCapture $script:RGBTestNativeCapture; $f.manifest.status = 'unsupported'
        $reports = @()
        foreach ($run in $f.manifest.runs) {
            if ($run.observer -cne 'appkit-extended-srgb') { continue }
            $path = Join-Path $f.root $run.report.evidenceFile; $raw = Read-SwiftUIColorRGBJson $path
            $observation = $raw.cases[0].observations[0]; $observation.status = 'unsupported'; $observation.reason = 'color-space-conversion-unavailable'; $observation.encodedRGBA = $null; $observation.appKit = $null
            Write-RGBTestJson $path $raw; $run.report = Get-SwiftUIColorRGBFileRecord $path $run.report.evidenceFile
            $reports += Read-SwiftUIColorRGBReport $path $run.observer $run.runId 'x86_64'
        }
        $control = Test-SwiftUIColorRGBObserverControls $reports 'appkit-extended-srgb'
        $recordedControl = @($f.manifest.observerControls | Where-Object { $_.observer -ceq 'appkit-extended-srgb' })[0]
        $recordedControl.state = $control.state; $recordedControl.reasons = $control.reasons
        Publish-RGBTestCapture $f
        $result = Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows (Read-SwiftUIColorRGBCapture $f.root)
        Assert-RGBTest ($result.primary.state -ceq 'match-candidate' -and $result.appKit.state -ceq 'unsupported' -and $result.provenance.state -ceq 'verified-for-candidate') 'nil AppKit result never substitutes for or vetoes healthy resolved observations'
    }
    foreach ($code in @('RGB_SOURCE_CHANGED_DURING_COLLECTION', 'RGB_TOOL_CHANGED_DURING_COLLECTION', 'RGB_SDK_CAPTURE_CHANGED_DURING_COLLECTION', 'RGB_OBSERVER_EXECUTABLE_CHANGED', 'RGB_OBSERVER_PID_MISMATCH', 'RGB_OBSERVER_OS_VERSION_MISMATCH', 'RGB_UNKNOWN_FAILURE')) {
        Invoke-RGBTestCase ("global failure cannot masquerade as observer-local: " + $code) {
            $f = Copy-RGBTestCapture $script:RGBTestNativeCapture; Set-RGBTestBridgeFailure $f $code
            Publish-RGBTestCapture $f; $native = Read-SwiftUIColorRGBCapture $f.root
            $result = Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows $native
            Assert-RGBTest ($result.state -ceq 'failure' -and $result.provenance.state -ceq 'failure' -and $result.primary.rows.Count -eq 600) "global identity fault retained despite final integrity flags $code"
        }
    }
    Invoke-RGBTestCase "omitted global failure code and unexplained aggregate fail closed" {
        $f = Copy-RGBTestCapture $script:RGBTestNativeCapture; Set-RGBTestBridgeFailure $f 'RGB_OBSERVER_PID_MISMATCH'
        $f.manifest.failureCodes = @(); Publish-RGBTestCapture $f
        $result = Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows (Read-SwiftUIColorRGBCapture $f.root)
        Assert-RGBTest ($result.state -ceq 'failure' -and @($result.provenance.reasons | Where-Object { $_ -cmatch '^uncontained-observer-failure:' }).Count -eq 3) 'all invalid runs classified independently of aggregate codes'
        $f = Copy-RGBTestCapture $script:RGBTestNativeCapture; $f.manifest.status = 'failure'; $f.manifest.failureCodes = @(); Publish-RGBTestCapture $f
        Assert-RGBTest ((Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows (Read-SwiftUIColorRGBCapture $f.root)).state -ceq 'failure') 'unexplained failure cannot become candidate'
        $f = Copy-RGBTestCapture $script:RGBTestNativeCapture; $f.manifest.status = 'failure'; $f.manifest.failureCodes = @('RGB_OBSERVER_FAILURE:appkit-extended-srgb'); Publish-RGBTestCapture $f
        Assert-RGBTest ((Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows (Read-SwiftUIColorRGBCapture $f.root)).state -ceq 'failure') 'forged derived observer failure requires recomputed failed controls'
    }
    $unboundChanges = @(
        @{ name = 'binary path'; change = { param($c) $c.executable += '.other' } },
        @{ name = 'binary hash'; change = { param($c) $c.executableSha256 = 'f' * 64 } },
        @{ name = 'observer'; change = { param($c) $c.arguments[1] = 'swiftui-resolved' } },
        @{ name = 'nonce'; change = { param($c) $c.arguments[3] = [Guid]::NewGuid().ToString('D') } },
        @{ name = 'full output path'; change = { param($c) $c.arguments[5] = '/OTHER/' + [IO.Path]::GetFileName($c.arguments[5]) } },
        @{ name = 'zero exit with claimed failure'; change = { param($c) $c.exitCode = 0 } },
        @{ name = 'timeout'; change = { param($c) $c.state = 'timeout'; $c.cleanupComplete = $false; $c.errorCode = 'RGB_PROCESS_TIMEOUT' } }
    )
    foreach ($change in $unboundChanges) {
        Invoke-RGBTestCase ("shared local code cannot hide unbound run: " + $change.name) {
            $f = Copy-RGBTestCapture $script:RGBTestNativeCapture; Set-RGBTestBridgeFailure $f
            $first = @($f.manifest.runs | Where-Object { $_.observer -ceq 'appkit-extended-srgb' })[0]
            $command = @($f.commands | Where-Object { $_.commandId -ceq $first.commandId })[0]; & $change.change $command
            Publish-RGBTestCapture $f; $native = Read-SwiftUIColorRGBCapture $f.root
            $result = Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows $native
            Assert-RGBTest ($result.state -ceq 'failure' -and $result.provenance.state -ceq 'failure') "one unbound run stays global while two share its local reason $($change.name)"
        }
    }
    Invoke-RGBTestCase "unreferenced failed command cannot hide in partial capture" {
        $f = Copy-RGBTestCapture $script:RGBTestNativeCapture; Set-RGBTestBridgeFailure $f
        $null = New-RGBTestCommand $f $f.manifest.toolchain.tools[0] @('SYNTHETIC-unrelated-failure') 'SYNTHETIC' 7
        Publish-RGBTestCapture $f
        $result = Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows (Read-SwiftUIColorRGBCapture $f.root)
        Assert-RGBTest ($result.state -ceq 'failure' -and @($result.provenance.reasons | Where-Object { $_ -cmatch '^uncontained-command-failure:' }).Count -eq 1) 'every failed process requires independently contained scope'
    }
    Invoke-RGBTestCase "environment policy names only" {
        foreach ($name in @('SWIFT_EXEC', 'SWIFT_DRIVER_SWIFT_FRONTEND_EXEC', 'SWIFTPM_CUSTOM_BIN_DIR', 'CLANG_EXEC', 'LIBRARY_PATH', 'CPATH', 'LD_PRELOAD')) {
            $envMap = @{}; $envMap[$name] = 'SYNTHETIC_SECRET_VALUE'
            $rejected = @(Get-SwiftUIColorRGBWindowsEnvironmentOverrides $envMap)
            Assert-RGBTest ($rejected.Count -eq 1 -and $rejected[0] -ceq $name -and ($rejected -join ',') -notmatch 'SECRET_VALUE') "override rejected by name $name"
        }
        Assert-RGBTest (@(Get-SwiftUIColorRGBWindowsEnvironmentOverrides @{ SDKROOT = 'prepared'; SWIFT_REPO_ROOT = 'prepared'; SWIFT_WINDOWSUI_DEV_ENV_SIGNATURE = 'prepared' }).Count -eq 0) "with-swift prepared names allowed"
        Assert-RGBTest (@(Get-SwiftUIMaterialEnvironmentOverrides @{ SDKROOT = 'foreign' }).Count -eq 1) "native SDK override still rejected"
    }
    Invoke-RGBTestCase "upstream driver normalizer preserves complete build" {
        $plain = ConvertTo-SwiftUIBaselineIdentity 'Xcode 26.6
Build version TESTXCODE' '26.5' '25F70' $script:RGBTestCompiler
        $driver = ConvertTo-SwiftUIBaselineIdentity 'Xcode 26.6
Build version TESTXCODE' '26.5' '25F70' ("swift-driver version: 1.148.6 " + $script:RGBTestCompiler)
        Assert-RGBTest ($plain.swiftCompilerVersionLine -ceq $driver.swiftCompilerVersionLine -and $plain.swiftCompilerVersion -ceq '6.3.3') "known driver prefix normalizes through shared helper"
        $other = ConvertTo-SwiftUIBaselineIdentity 'Xcode 26.6
Build version TESTXCODE' '26.5' '25F70' ($script:RGBTestCompiler.Replace('clang-2100.1.1.101', 'clang-2100.1.1.102'))
        Assert-RGBTest ($other.swiftCompilerVersionLine -cne $plain.swiftCompilerVersionLine) "build suffix mismatch not normalized away"
    }
    Invoke-RGBTestCase "SDK intake reuses sealed live validator without inventory" {
        $fixture = New-RGBTestLiveSDK
        $hash = Get-SwiftUIColorRGBHash $fixture.inventoryPath
        $context = Read-SwiftUIColorRGBPinnedSDKContext $fixture.captureRoot $fixture.manifestPath
        Assert-RGBTest ($context.captureManifestSha256 -ceq $fixture.status.captureManifestSha256) 'valid synthetic SDK seal accepted'
        Assert-RGBTest ($context.exactIdentityPreviouslyReviewed -eq $false) 'successful capture does not qualify identity'
        Assert-RGBTest ((Get-SwiftUIColorRGBHash $fixture.inventoryPath) -ceq $hash) 'invalid inventory never parsed or modified'
    }
    $sdkChanges = @(
        @{ name = 'failed export'; change = { param($f) $f.status.status = 'failed' } },
        @{ name = 'incomplete export'; change = { param($f) $f.capture.status = 'in-progress' } },
        @{ name = 'wrong SDK release'; change = { param($f) $f.capture.observedIdentity.sdkVersion = '26.6' } },
        @{ name = 'wrong Xcode release'; change = { param($f) $f.capture.observedIdentity.xcodeVersion = '26.7' } },
        @{ name = 'wrong compiler release'; change = { param($f) $f.capture.observedIdentity.swiftCompilerVersion = '6.4' } },
        @{ name = 'wrong baseline hash'; change = { param($f) $f.capture.baselineManifest.sha256 = 'f' * 64 } },
        @{ name = 'wrong compiler hash'; change = { param($f) $f.capture.tools[0].sha256 = 'f' * 64 } },
        @{ name = 'live SDK modified'; change = { param($f) Write-RGBTestText $f.settingsPath 'changed SDK bytes' } },
        @{ name = 'captured SDK modified'; change = { param($f) Write-RGBTestText (Join-Path $f.captureRoot 'SDKSettings.json') 'changed copy bytes' } },
        @{ name = 'qualification promoted'; change = { param($f) $f.capture.qualification.releaseQualified = $true } },
        @{ name = 'review flag promoted'; change = { param($f) $f.capture.exactIdentityPreviouslyReviewed = $true } },
        @{ name = 'tool outside XcodeDefault'; change = { param($f) $outside = Join-Path $f.root 'outside/swift'; Write-RGBTestText $outside 'SYNTHETIC outside compiler'; $f.capture.tools[0].path = $outside; $f.capture.tools[0].sha256 = Get-SwiftUIColorRGBHash $outside } }
    )
    foreach ($change in $sdkChanges) {
        Invoke-RGBTestCase ('SDK rejects ' + $change.name) {
            $fixture = New-RGBTestLiveSDK; & $change.change $fixture; Publish-RGBTestLiveSDK $fixture
            Assert-RGBTestThrows { Read-SwiftUIColorRGBPinnedSDKContext $fixture.captureRoot $fixture.manifestPath } '.' $change.name
        }
    }
    Invoke-RGBTestCase 'SDK duplicate JSON key and bad seal' {
        $fixture = New-RGBTestLiveSDK; $path = Join-Path $fixture.captureRoot 'capture-status.json'
        Write-RGBTestText $path '{"status":"failed","status":"exported-awaiting-review"}'
        Assert-RGBTestThrows { Read-SwiftUIColorRGBPinnedSDKContext $fixture.captureRoot $fixture.manifestPath } 'DUPLICATE_JSON_KEY' 'duplicate SDK metadata rejected before shared validator'
        $fixture = New-RGBTestLiveSDK; Write-RGBTestText (Join-Path $fixture.captureRoot 'capture.sha256') (('f' * 64) + "  capture.json`n")
        Assert-RGBTestThrows { Read-SwiftUIColorRGBPinnedSDKContext $fixture.captureRoot $fixture.manifestPath } '(digest|disagrees)' 'bad SDK seal'
    }
    Invoke-RGBTestCase "immutable output and safe paths" {
        $name = Join-Path $script:RGBTestRoot 'new-output'
        $created = New-SwiftUIColorRGBOutputRoot $name $RepositoryRoot
        Assert-RGBTest (Test-Path -LiteralPath $created -PathType Container) "new output created"
        Assert-RGBTestThrows { New-SwiftUIColorRGBOutputRoot $name $RepositoryRoot } 'OUTPUT_EXISTS' "no overwrite"
        Assert-RGBTestThrows { New-SwiftUIColorRGBOutputRoot (Join-Path $created 'nested') $RepositoryRoot @($created) } 'INSIDE_INPUT' "not inside capture"
        Assert-RGBTestThrows { Get-SwiftUIColorRGBEvidencePath $created '../outside' } 'INVALID_EVIDENCE_PATH' "parent traversal"
        Assert-RGBTestThrows { Get-SwiftUIColorRGBEvidencePath $created 'x/../../outside' } 'INVALID_EVIDENCE_PATH' "nested parent traversal"
        foreach ($badName in @('../X+Y.swift', 'x/../../X+Y.swift', '/X+Y.swift', 'C:/X+Y.swift', 'x\X+Y.swift', 'x//X+Y.swift', 'x/./X+Y.swift', 'x/X+Y.swift/')) {
            Assert-RGBTestThrows { Get-SwiftUIColorRGBEvidencePath $created $badName } 'INVALID_EVIDENCE_PATH' "plus spelling cannot hide invalid evidence path $badName"
        }
        $file = Join-Path $created 'immutable.json'; Write-SwiftUIColorRGBJsonNew $file ([pscustomobject]@{ value = 1 })
        $before = Get-SwiftUIColorRGBHash $file
        Assert-RGBTestThrows { Write-SwiftUIColorRGBJsonNew $file ([pscustomobject]@{ value = 2 }) } '(exist|already|CreateNew)' "create-new JSON writer"
        Assert-RGBTest ((Get-SwiftUIColorRGBHash $file) -ceq $before) "existing evidence unchanged"
    }
    Invoke-RGBTestCase 'optional packet association is exact and remains unverified' {
        $packet = New-RGBTestPacket
        $before = Get-SwiftUIColorRGBHash (Join-Path $packet.root 'review-unit.json')
        $association = Read-SwiftUIColorRGBReviewAssociation $packet.root $packet.manifest.selection.preciseIdentifier $script:RGBTestValidatedWindows $script:RGBTestValidatedNative
        Assert-RGBTest ($association.state -ceq 'linked-unverified' -and $association.occurrences.Count -eq 4 -and $association.windowsFiles.Count -eq 1) 'four explicit tuples and committed source blob bound'
        Assert-RGBTest ($association.declarationReview -ceq 'unverified' -and $association.sourceReview -ceq 'unverified' -and $association.behaviorReview -ceq 'unverified' -and $association.validationScope -match 'not full ledger') 'attachment does not promote any claim or invent semantic closure'
        Assert-RGBTest ((Get-SwiftUIColorRGBHash (Join-Path $packet.root 'review-unit.json')) -ceq $before -and $packet.manifest.evidenceReferences.Count -eq 0) 'immutable packet and empty claim refs unchanged'
        Assert-RGBTestThrows { Read-SwiftUIColorRGBReviewAssociation $packet.root 's:OTHER' $script:RGBTestValidatedWindows $script:RGBTestValidatedNative } 'PRECISE_IDENTIFIER_MISMATCH' 'no display-name or approximate ID fallback'
    }
    $packetChanges = @(
        @{ name = 'precise identifier'; change = { param($f) $f.manifest.selection.preciseIdentifier += 'other' } },
        @{ name = 'source commit'; change = { param($f) $f.manifest.windowsSource.commit = 'f' * 40 } },
        @{ name = 'capture hash'; change = { param($f) $f.manifest.sourceCapture.captureManifestSha256 = 'f' * 64 } },
        @{ name = 'promoted claim'; change = { param($f) $f.manifest.claims[0].status = 'verified' } },
        @{ name = 'claim reference'; change = { param($f) $f.manifest.claims[1].evidenceRefs = @('fabricated') } },
        @{ name = 'missing record'; change = { param($f) $f.manifest.recordFiles = @($f.manifest.recordFiles[0..7]) } },
        @{ name = 'duplicate record'; change = { param($f) $f.manifest.recordFiles[8] = Copy-RGBTestValue $f.manifest.recordFiles[0] } },
        @{ name = 'metadata binding'; change = { param($f) @($f.manifest.sourceMetadataFiles | Where-Object { $_.kind -ceq 'source-audit-manifest' })[0].kind = 'other' } },
        @{ name = 'source blob'; change = { param($f) $f.manifest.windowsSource.files[0].blobOid = 'f' * 40 } },
        @{ name = 'source not compiled'; change = { param($f) $f.manifest.windowsSource.files[0].path = 'Sources/Other.swift' } },
        @{ name = 'count noninteger'; change = { param($f) $f.manifest.selection.declarationOccurrences = '4' } },
        @{ name = 'duplicate occurrence'; change = { param($f) $name = 'native/occurrences.ndjson'; $lines = @(Read-SwiftUIColorRGBText (Join-Path $f.root $name) | ForEach-Object { $_ -split "`n" } | Where-Object { $_ }); Write-RGBTestText (Join-Path $f.root $name) (($lines[0], $lines[0], $lines[2], $lines[3]) -join "`n"); Update-RGBTestPacketRecord $f $name } },
        @{ name = 'missing occurrence'; change = { param($f) $name = 'native/occurrences.ndjson'; $lines = @(Read-SwiftUIColorRGBText (Join-Path $f.root $name) | ForEach-Object { $_ -split "`n" } | Where-Object { $_ }); Write-RGBTestText (Join-Path $f.root $name) ($lines[0..2] -join "`n"); Update-RGBTestPacketRecord $f $name } },
        @{ name = 'wrong occurrence module'; change = { param($f) $name = 'native/occurrences.ndjson'; $text = Read-SwiftUIColorRGBText (Join-Path $f.root $name); Write-RGBTestText (Join-Path $f.root $name) $text.Replace('"requestedModule":"SwiftUI"', '"requestedModule":"Other"'); Update-RGBTestPacketRecord $f $name } }
    )
    foreach ($change in $packetChanges) {
        Invoke-RGBTestCase ('packet association rejects ' + $change.name) {
            $packet = New-RGBTestPacket; & $change.change $packet; Publish-RGBTestPacket $packet
            Assert-RGBTestThrows { Read-SwiftUIColorRGBReviewAssociation $packet.root 's:7SwiftUI5ColorV_3red5green4blue7opacityA2C13RGBColorSpaceO_S4dtcfc' $script:RGBTestValidatedWindows $script:RGBTestValidatedNative } 'RGB_|Review selection' $change.name
        }
    }
    Invoke-RGBTestCase 'packet raw bytes and seals remain authoritative' {
        foreach ($name in @('review-unit.sha256', 'native/identity.ndjson', 'context/audit.json', 'windows/Sources/WinSwiftUI/Core.swift')) {
            $packet = New-RGBTestPacket; $path = Join-Path $packet.root $name
            [IO.File]::AppendAllText($path, 'tampered', $script:RGBTestUTF8)
            Assert-RGBTestThrows { Read-SwiftUIColorRGBReviewAssociation $packet.root $packet.manifest.selection.preciseIdentifier $script:RGBTestValidatedWindows $script:RGBTestValidatedNative } '(MISMATCH|LENGTH)' "packet $name tamper"
            Assert-RGBTest ([IO.File]::ReadAllText($path).EndsWith('tampered')) 'read-only rejection does not rewrite packet'
        }
    }
    Invoke-RGBTestCase 'PowerShell comparison entrypoint and unsupported capture guard' {
        $exe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $directory = Join-Path $script:RGBTestRoot 'entrypoint-processes'; [void][IO.Directory]::CreateDirectory($directory)
        $comparison = Join-Path $script:RGBTestRoot 'cli-comparison'
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $RepositoryRoot 'scripts/compare-swiftui-color-rgb-reference.ps1'), '-WindowsRoot', $script:RGBTestWindowsCapture.root, '-NativeRoot', $script:RGBTestNativeCapture.root, '-OutputPath', $comparison)
        $record = Invoke-SwiftUIColorRGBProcess $exe $args $RepositoryRoot $directory 'compare-success' 60 65536
        Assert-RGBTest (Test-SwiftUIColorRGBCommandSucceeded $record) 'actual comparison CLI succeeds on synthetic immutable captures'
        $result = Read-SwiftUIColorRGBJson (Join-Path $comparison 'comparison.json') -MaxBytes 16777216
        Assert-RGBTest ($result.state -ceq 'match-candidate' -and $result.primary.requiredComparisons -eq 552 -and $result.appKit.requiredComparisons -eq 276) 'CLI report contains exact independent counts'
        Assert-RGBTest ($result.auxiliaryFiles.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $comparison 'json-parser-identity.json'))) 'managed parser provenance is archived separately'
        $before = Get-SwiftUIColorRGBHash (Join-Path $comparison 'comparison.json')
        $record = Invoke-SwiftUIColorRGBProcess $exe $args $RepositoryRoot $directory 'compare-no-overwrite' 30 65536
        Assert-RGBTest ($record.state -ceq 'exited' -and $record.exitCode -ne 0 -and (Get-SwiftUIColorRGBHash (Join-Path $comparison 'comparison.json')) -ceq $before) 'second CLI invocation cannot overwrite output'
        if ([IO.Path]::DirectorySeparatorChar -eq '\') {
            # Only the opposite-platform early guard is exercised. Windows
            # collection would compile Swift and is never invoked by tests.
            foreach ($alias in @('native', 'NATIVE')) {
                $captureRoot = Join-Path $script:RGBTestRoot ('cli-unavailable-' + $alias + '-' + [Guid]::NewGuid().ToString('N'))
                $record = Invoke-SwiftUIColorRGBProcess $exe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $RepositoryRoot 'scripts/capture-swiftui-color-rgb-reference.ps1'), '-Platform', $alias, '-OutputPath', $captureRoot) $RepositoryRoot $directory ('guard-' + $alias.ToLowerInvariant() + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)) 30 65536
                Assert-RGBTest ($record.state -ceq 'exited' -and $record.exitCode -eq 2) 'accepted native alias reaches unsupported guard'
                $capture = Read-SwiftUIColorRGBCapture $captureRoot
                Assert-RGBTest ($capture.manifest.runtimeEligibility.reason -ceq 'requested-platform-unavailable' -and $capture.manifest.commands.Count -eq 0 -and $null -eq $capture.manifest.source) 'opposite-platform capture executes no source/tool/observer commands'
                $unavailable = Compare-SwiftUIColorRGBCaptures $script:RGBTestValidatedWindows $capture
                Assert-RGBTest ($unavailable.state -ceq 'unsupported' -and $unavailable.provenance.state -ceq 'not-evaluated') 'truly unattempted platform remains unsupported, not a source failure'
                if ($alias -ceq 'native') {
                    $changed = Copy-RGBTestCapture $capture; $changed.manifest.status = 'failure'; $changed.manifest.failureCodes = @('RGB_TOOL_CHANGED'); Publish-RGBTestCapture $changed
                    Assert-RGBTestThrows { Read-SwiftUIColorRGBCapture $changed.root } 'PLATFORM_UNAVAILABLE_RECORD_INCONSISTENT' 'unavailable exemption cannot carry a global failure'
                    $changed = Copy-RGBTestCapture $capture; $changed.manifest.toolchain = Copy-RGBTestValue $script:RGBTestValidatedNative.manifest.toolchain; Publish-RGBTestCapture $changed
                    Assert-RGBTestThrows { Read-SwiftUIColorRGBCapture $changed.root } 'RGB_' 'unavailable exemption cannot carry compiler evidence'
                }
            }
        }
    }
    Invoke-RGBTestCase "bounded PowerShell child process adapter" {
        $exe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $directory = Join-Path $script:RGBTestRoot 'processes'; [void][IO.Directory]::CreateDirectory($directory)
        $program = "[Console]::Out.Write('synthetic stdout'); [Console]::Error.Write('synthetic stderr'); exit 0"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($program))
        $record = Invoke-SwiftUIColorRGBProcess $exe @('-NoProfile', '-EncodedCommand', $encoded) $directory $directory 'success' 10 256
        Assert-RGBTest (Test-SwiftUIColorRGBCommandSucceeded $record) "bounded child success"
        Assert-RGBTest ($record.processId -gt 0 -and $record.processId -ne $PID) "actual child PID"
        Assert-RGBTest ((Read-SwiftUIColorRGBText (Join-Path $directory $record.stdout.evidenceFile)) -ceq 'synthetic stdout') "raw stdout"
        Assert-RGBTest ((Read-SwiftUIColorRGBText (Join-Path $directory $record.stderr.evidenceFile)) -ceq 'synthetic stderr') "raw stderr"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("[Console]::Out.Write('x' * 4096); exit 0"))
        $record = Invoke-SwiftUIColorRGBProcess $exe @('-NoProfile', '-EncodedCommand', $encoded) $directory $directory 'limited' 10 64
        Assert-RGBTest ($record.state -ceq 'output-limit' -and $record.stdout.bytes -eq 64 -and -not $record.cleanupComplete) "log cap fails closed without unbounded bytes"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("[Threading.Thread]::Sleep(60000)"))
        $record = Invoke-SwiftUIColorRGBProcess $exe @('-NoProfile', '-EncodedCommand', $encoded) $directory $directory 'timeout' 1 256
        Assert-RGBTest ($record.state -ceq 'timeout' -and -not $record.cleanupComplete -and $record.errorCode -ceq 'RGB_PROCESS_TIMEOUT') "timeout has no closure claim"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("[Console]::Error.Write('synthetic failure'); exit 9"))
        $record = Invoke-SwiftUIColorRGBProcess $exe @('-NoProfile', '-EncodedCommand', $encoded) $directory $directory 'nonzero' 10 256
        Assert-RGBTest ($record.state -ceq 'exited' -and $record.exitCode -eq 9 -and -not (Test-SwiftUIColorRGBCommandSucceeded $record)) "nonzero process distinct from unsupported API"
        $unicodeDirectory = Join-Path $directory ('unicode-' + [char]0x03c3); [void][IO.Directory]::CreateDirectory($unicodeDirectory)
        $source = Join-Path $unicodeDirectory 'source.ps1'; Write-RGBTestText $source "[Console]::Out.Write('unicode-source-path-preserved')"
        $encodedPath = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($source))
        $helper = Join-Path $unicodeDirectory 'ascii-helper.ps1'
        Write-RGBTestText $helper ("`$p = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedPath')); . `$p")
        Assert-RGBTest (@([IO.File]::ReadAllBytes($helper) | Where-Object { $_ -gt 127 }).Count -eq 0) 'generated helper can be ASCII under PS5'
        $record = Invoke-SwiftUIColorRGBProcess $exe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $helper) $directory $directory 'unicode' 10 256
        Assert-RGBTest ((Test-SwiftUIColorRGBCommandSucceeded $record) -and (Read-SwiftUIColorRGBText (Join-Path $directory $record.stdout.evidenceFile)) -ceq 'unicode-source-path-preserved') 'actual PowerShell Unicode path helper succeeds'
    }
    Invoke-RGBTestCase 'suite source files unchanged during execution' {
        foreach ($file in $script:RGBTestSourceHashes) { Assert-RGBTest ((Get-SwiftUIColorRGBHash (Join-Path $RepositoryRoot $file.path)) -ceq $file.sha256) "tested source unchanged $($file.path)" }
    }
    if ($script:RGBTestFailures.Count -gt 0) { throw ($script:RGBTestFailures -join "`n") }
    Write-Host "RGB reference synthetic tests passed: $script:RGBTestCases cases, $script:RGBTestAssertions assertions, PowerShell $($PSVersionTable.PSVersion). No Swift/native color execution."
} catch {
    $rgbTestOriginalFailure = $_
    Write-Host "Synthetic failure artifacts preserved: $script:RGBTestRoot"
    throw
} finally {
    if (-not [string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
        Write-SwiftUIColorRGBJsonNew (Join-Path $EvidenceDirectory 'test-summary.json') ([pscustomobject]@{
            schemaVersion = 1; evidenceKind = 'synthetic-color-rgb-tooling-tests'; passed = ($null -eq $rgbTestOriginalFailure)
            startedAtUtc = $script:RGBTestStarted; finishedAtUtc = [DateTime]::UtcNow.ToString('o')
            cases = $script:RGBTestCases; assertions = $script:RGBTestAssertions; results = @($script:RGBTestResults.ToArray())
            powerShellVersion = $PSVersionTable.PSVersion.ToString(); parser = $script:RGBTestParserIdentity
            forcedNewtonsoftFallbackExercised = $script:RGBTestFallbackExercised; sourceFiles = $script:RGBTestSourceHashes
            fixtureRoot = $script:RGBTestRoot; fixtureDisposition = $(if ($null -eq $rgbTestOriginalFailure) { 'removed-after-success' } else { 'preserved-after-failure' })
            swiftCompilerExecuted = $false; swiftPMExecuted = $false; nativeColorObserverExecuted = $false
        })
    }
    if ($null -eq $rgbTestOriginalFailure) {
        $resolvedTemp = Resolve-SwiftUIBaselineFileSystemPath ([IO.Path]::GetTempPath())
        $resolvedTest = Resolve-SwiftUIBaselineFileSystemPath $script:RGBTestRoot
        [void](Get-SwiftUIBaselineRelativePath -Root $resolvedTemp -Path $resolvedTest)
        if ($resolvedTest -ne [IO.Path]::GetFullPath($script:RGBTestRoot) -or (Split-Path -Leaf $resolvedTest) -notmatch '^swiftui-color-rgb-tests-[0-9a-f]{32}$') { throw "Refusing unsafe synthetic fixture cleanup." }
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}
