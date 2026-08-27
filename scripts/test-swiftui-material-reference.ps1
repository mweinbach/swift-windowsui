<#
.SYNOPSIS
Tests pinned material-capture provenance with synthetic metadata only.
.DESCRIPTION
No native tool, Apple SDK, SwiftPM command, or image capture runs. The files
named .png deliberately contain labelled non-image bytes: these tests verify
manifest validation, hashes, and file containment, not PNG decoding or pixels.
Every fixture lives in a new UUID directory under the OS temporary directory.
#>
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = "Stop"
. (Join-Path $RepositoryRoot "scripts/swiftui-material-reference-common.ps1")
$script:MaterialTestAssertions = 0
$script:MaterialTestCases = 0
$script:MaterialTestFailures = [System.Collections.Generic.List[string]]::new()
$script:MaterialTestUTF8 = [System.Text.UTF8Encoding]::new($false)
$script:MaterialTestCommit = "1111111111111111111111111111111111111111"
$script:MaterialTestCompiler = "Apple Swift version 6.3 (synthetic test compiler)"
$script:MaterialTestFixtures = @(
    "pattern-control", "flat-tint-control", "material-direct-control",
    "material-compositing-group", "material-drawing-group", "material-content-blur"
)
$script:MaterialTestBaseline = Join-Path $RepositoryRoot "docs/swiftui-baseline.json"
$materialTestTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$materialTestName = "swiftui-material-provenance-" + [Guid]::NewGuid().ToString("N")
$script:MaterialTestRoot = Join-Path $materialTestTemp $materialTestName
if (Test-Path -LiteralPath $script:MaterialTestRoot) { throw "Synthetic fixture directory already exists." }
[void][System.IO.Directory]::CreateDirectory($script:MaterialTestRoot)

function Assert-MaterialTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Material provenance test failed: $Message" }
    $script:MaterialTestAssertions++
}

function Assert-MaterialTestThrows {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-MaterialTest ($null -ne $caught) "$Message (no error was raised)"
    Assert-MaterialTest ($caught.Exception.Message -match $Pattern) "$Message (unexpected error: $($caught.Exception.Message))"
}

function Test-MaterialRejection {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    # Each rejection uses an independent fixture. Run the remaining cases so
    # one missing check does not hide unrelated validation gaps.
    try { Assert-MaterialTestThrows $Action $Pattern $Message } catch {
        $script:MaterialTestFailures.Add($_.Exception.Message)
    }
}

function Get-MaterialTestHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-MaterialTestText {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, $script:MaterialTestUTF8)
}

function Copy-MaterialTestObject {
    param($Value)
    return (ConvertTo-Json -InputObject $Value -Depth 100 | ConvertFrom-Json)
}

function Publish-MaterialTestCapture {
    param($Fixture)
    Write-SwiftUIBaselineJson -Value $Fixture.capture -Path $Fixture.capturePath
    $hash = Get-MaterialTestHash $Fixture.capturePath
    Write-MaterialTestText -Path $Fixture.digestPath -Text "$hash  capture.json`n"
    $Fixture.status.captureManifestSha256 = $hash
    Write-SwiftUIBaselineJson -Value $Fixture.status -Path $Fixture.statusPath
}

function Publish-MaterialTestObservation {
    param($Fixture)
    Write-SwiftUIBaselineJson -Value $Fixture.observation -Path $Fixture.observationPath
}

function Read-MaterialTestSDK {
    param($Fixture)
    return Read-SwiftUIMaterialSDKContext -CaptureRoot $Fixture.captureRoot -ManifestPath $Fixture.manifestPath
}

function Read-MaterialTestObservation {
    param($Fixture, $Context)
    return Read-SwiftUIMaterialObservation -Directory $Fixture.observationRoot -SDKContext $Context `
        -ExpectedCommit $script:MaterialTestCommit -ExpectedExecutableSha256 $Fixture.executableHash `
        -ExpectedArchitecture "x86_64"
}

function New-MaterialTestFixture {
    param([string]$Name)
    $script:MaterialTestCases++
    $directory = Join-Path $script:MaterialTestRoot ("{0:D3}-{1}" -f $script:MaterialTestCases, $Name)
    $captureRoot = Join-Path $directory "sdk-capture"
    $observationRoot = Join-Path $directory "material-observation"
    $developerDirectory = (Join-Path $directory "Xcode-26.6.app/Contents/Developer").Replace('\', '/')
    $toolDirectory = Join-Path $developerDirectory "Toolchains/XcodeDefault.xctoolchain/usr/bin"
    $sdkPath = (Join-Path $developerDirectory "Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk").Replace('\', '/')
    foreach ($path in @($captureRoot, $observationRoot, $toolDirectory, $sdkPath)) {
        [void][System.IO.Directory]::CreateDirectory($path)
    }
    $manifestPath = Join-Path $directory "requested-baseline.json"
    Copy-Item -LiteralPath $script:MaterialTestBaseline -Destination $manifestPath
    $baselineCopy = Join-Path $captureRoot "baseline-manifest.json"
    Copy-Item -LiteralPath $manifestPath -Destination $baselineCopy
    $swiftPath = (Join-Path $toolDirectory "swift").Replace('\', '/')
    $extractorPath = (Join-Path $toolDirectory "swift-symbolgraph-extract").Replace('\', '/')
    Write-MaterialTestText $swiftPath "SYNTHETIC FIXTURE ONLY: not a Swift executable.`n"
    Write-MaterialTestText $extractorPath "SYNTHETIC FIXTURE ONLY: not a symbol graph extractor.`n"
    $settingsPath = Join-Path $sdkPath "SDKSettings.json"
    Write-MaterialTestText $settingsPath '{"Version":"26.5","ProductBuildVersion":"TESTSDK","synthetic":true}'
    $settingsCopy = Join-Path $captureRoot "SDKSettings.json"
    Copy-Item -LiteralPath $settingsPath -Destination $settingsCopy
    $inventoryPath = Join-Path $captureRoot "inventory.json"
    Write-MaterialTestText $inventoryPath "SYNTHETIC INVALID INVENTORY: material provenance must never parse this file."
    $executablePath = Join-Path $directory "synthetic-reference-executable"
    Write-MaterialTestText $executablePath "SYNTHETIC FIXTURE ONLY: not a reference renderer executable.`n"
    $manifest = Read-SwiftUIBaselineManifest -Path $manifestPath
    $identity = ConvertTo-SwiftUIBaselineIdentity -XcodeOutput "Xcode 26.6`nBuild version TESTXCODE" `
        -SDKVersion "26.5" -SDKBuildVersion "TESTSDK" -SwiftOutput "$script:MaterialTestCompiler`nTarget: x86_64-apple-macosx26.5"
    $fixture = [pscustomobject]@{
        directory = $directory; captureRoot = $captureRoot; observationRoot = $observationRoot
        manifestPath = $manifestPath; baselineCopy = $baselineCopy; developerDirectory = $developerDirectory
        swiftPath = $swiftPath; extractorPath = $extractorPath; sdkPath = $sdkPath
        settingsPath = $settingsPath; settingsCopy = $settingsCopy; inventoryPath = $inventoryPath
        executablePath = $executablePath; executableHash = (Get-MaterialTestHash $executablePath)
        capturePath = (Join-Path $captureRoot "capture.json")
        statusPath = (Join-Path $captureRoot "capture-status.json")
        digestPath = (Join-Path $captureRoot "capture.sha256")
        observationPath = (Join-Path $observationRoot "manifest.json")
        capture = [pscustomobject][ordered]@{
            schemaVersion = 1; baselineId = $manifest.baselineId
            status = "exported-awaiting-inventory-and-behavior-review"
            startedAtUtc = "2026-08-27T00:00:00.0000000Z"; finishedAtUtc = "2026-08-27T00:01:00.0000000Z"
            exactIdentityPreviouslyReviewed = $false; observedIdentity = $identity
            host = [pscustomobject]@{
                macOSVersion = "26.6"; macOSBuildVersion = "TESTOS"; architecture = "x86_64"
                powerShellVersion = "7.6.4"
                note = "Synthetic fixture only; no native SwiftUI reference behavior was exercised."
            }
            developerDirectoryOverride = $developerDirectory
            baselineManifest = [pscustomobject]@{ path = "baseline-manifest.json"; sha256 = (Get-MaterialTestHash $baselineCopy) }
            tools = @(
                [pscustomobject]@{ path = $swiftPath; sha256 = (Get-MaterialTestHash $swiftPath) },
                [pscustomobject]@{ path = $extractorPath; sha256 = (Get-MaterialTestHash $extractorPath) }
            )
            exporterSources = @()
            sdk = [pscustomobject]@{
                path = $sdkPath; version = "26.5"; buildVersion = "TESTSDK"
                settingsPath = "SDKSettings.json"; settingsSha256 = (Get-MaterialTestHash $settingsCopy)
            }
            requestedScope = $manifest.scope; publicInterfaces = @(); crossImportDefinitions = @()
            crossImportOverlayCompleteness = "not-verified; compiler may silently skip an overlay that fails to load"
            inventory = [pscustomobject]@{
                path = "inventory.json"; sha256 = (Get-MaterialTestHash $inventoryPath)
                graphSetSha256 = ("2" * 64); counts = [pscustomobject]@{}
            }
            commands = @()
            qualification = [pscustomobject]@{
                publicAPIAuditComplete = $false; behaviorConformanceVerified = $false; releaseQualified = $false
            }
        }
        status = [pscustomobject]@{
            baselineId = $manifest.baselineId; status = "exported-awaiting-review"
            captureManifest = "capture.json"; captureManifestSha256 = ""; behaviorConformance = "not-verified"
        }
        observation = $null
    }
    $observations = @(
        foreach ($name in $script:MaterialTestFixtures) {
            $measurements = switch ($name) {
                "pattern-control" { [pscustomobject]@{ fineContrast = 0.8; fineDarkMean = 0.1; fineLightMean = 0.9; coarseContrast = 0.8; darkMean = 0.1; lightMean = 0.9 } }
                "flat-tint-control" { [pscustomobject]@{ fineContrast = 0.48; fineDarkMean = 0.46; fineLightMean = 0.94; coarseContrast = 0.48; darkMean = 0.46; lightMean = 0.94 } }
                default { [pscustomobject]@{ fineContrast = 0.05; fineDarkMean = 0.475; fineLightMean = 0.525; coarseContrast = 0.5; darkMean = 0.25; lightMean = 0.75 } }
            }
            $materialOrder = "ZStack { Color.clear.frame(width:336,height:240).background(.regularMaterial) }"
            $modifierOrder = switch ($name) {
                "pattern-control" { "pattern only" }
                "flat-tint-control" { "Color.white.opacity(0.4) over pattern" }
                "material-direct-control" { $materialOrder }
                "material-compositing-group" { $materialOrder + ".compositingGroup()" }
                "material-drawing-group" { $materialOrder + ".drawingGroup(opaque:false,colorMode:.nonLinear)" }
                "material-content-blur" { $materialOrder + ".blur(radius:3,opaque:false)" }
            }
            $captures = @(
                foreach ($repetition in 1..2) {
                    $pngName = "$name-$repetition.png"
                    $pngPath = Join-Path $observationRoot $pngName
                    Write-MaterialTestText $pngPath "SYNTHETIC NON-IMAGE PAYLOAD for $name repetition $repetition. No pixels were captured.`n"
                    [pscustomobject]@{
                        repetition = $repetition; timestampUTC = "2026-08-27T00:02:00Z"
                        pngFile = $pngName; sha256 = (Get-MaterialTestHash $pngPath); error = $null
                        decodedPNG = [pscustomobject]@{
                            pixelWidth = 768; pixelHeight = 576; bitsPerSample = 8; samplesPerPixel = 4
                            hasAlpha = $true; bytesPerRow = 3072; colorSpaceName = "NSCalibratedRGBColorSpace"
                        }
                        measurements = [pscustomobject]@{
                            pixelWidth = 768; pixelHeight = 576; fineContrast = $measurements.fineContrast
                            fineDarkMean = $measurements.fineDarkMean; fineLightMean = $measurements.fineLightMean
                            coarseContrast = $measurements.coarseContrast
                            darkMean = $measurements.darkMean; lightMean = $measurements.lightMean; minimumSampleAlpha = 1.0
                        }
                    }
                }
            )
            [pscustomobject]@{
                fixture = $name; modifierOrder = $modifierOrder; captures = $captures
                repeatedMeasurementsStable = $true; effectiveAppearance = "NSAppearanceNameAqua"; hostIsFlipped = $true
            }
        }
    )
    $fixture.observation = [pscustomobject][ordered]@{
        schemaVersion = 1; fixtureVersion = 1
        qualification = "candidate-only; not pinned SDK qualification or SwiftUI conformance"
        groupBehaviorReview = "unreviewed; even a passing direct control does not qualify every wrapper"
        captureAPI = "NSHostingView.cacheDisplay(in:to:), unattached view; no desktop or window capture"
        pixelCoordinates = "PNG top row first; no automatic orientation correction"
        logicalWidth = 384; logicalHeight = 288; requestedScale = 2
        requestedAppearance = "light / NSAppearance.aqua"
        outputColorSpace = "sRGB, converted before PNG encoding; metrics read the decoded PNG"
        material = "regularMaterial"; stripeWidthPoints = 4; patternBandBoundaryPoints = 144
        baselinePhaseSampleInsetPixels = 2; patternDarkSRGB = 0.1; patternLightSRGB = 0.9
        panel = [pscustomobject]@{ x = 24; y = 24; width = 336; height = 240 }
        fineSample = [pscustomobject]@{ x = 96; y = 64; width = 192; height = 32 }
        darkSample = [pscustomobject]@{ x = 64; y = 208; width = 16; height = 16 }
        lightSample = [pscustomobject]@{ x = 304; y = 208; width = 16; height = 16 }
        metric = "fine: twice the standard deviation of all fine-region pixels; coarse: absolute patch-mean difference; encoded sRGB luma 0.2126R+0.7152G+0.0722B"
        thresholds = [pscustomobject]@{
            patternMinimumContrast = 0.5; patternMaximumDarkMean = 0.25; patternMinimumLightMean = 0.75
            minimumSampleAlpha = 0.98; tintMinimumContrast = 0.15; tintMinimumRelativeFrequencyRatio = 0.8
            tintMaximumRelativeFrequencyRatio = 1.2; tintMaximumCoarseRetention = 0.9; tintMinimumDarkMeanLift = 0.1
            materialMinimumCoarseContrast = 0.04; materialMinimumCoarseRetention = 0.05
            materialMaximumRelativeFrequencyRatio = 0.35; materialMaximumFrequencyRatioRelativeToTint = 0.4
            maximumRepeatedMetricDifference = 0.02
        }
        repetitions = 2; settlingMillisecondsBeforeEachCapture = 50
        provenance = [pscustomobject]@{
            osVersion = "Version 26.6 (Build TESTOS)"; osBuild = "TESTOS"
            xcodeAtCapture = "Xcode 26.6`nBuild version TESTXCODE"
            swiftAtCapture = "$script:MaterialTestCompiler`nTarget: x86_64-apple-macosx26.5"
            sdkVersionAtCapture = "26.5"; sdkBuildAtCapture = "TESTSDK"; sdkPathAtCapture = $sdkPath
            sourceCommitAtCapture = $script:MaterialTestCommit; trackedWorkingTreeAtCapture = ""
            buildProvenance = "Synthetic fixture only; no native build."
            declaredBuildConfiguration = "release"; executableSHA256 = $fixture.executableHash
            swiftLanguageMode = "6"; processArchitecture = "x86_64"
            GITHUB_SHA = $script:MaterialTestCommit; GITHUB_RUN_ID = "12345"; GITHUB_RUN_ATTEMPT = "1"
            ImageOS = "synthetic-macos26"; ImageVersion = "synthetic-only"
        }
        systemAccessibility = [pscustomobject]@{ reduceTransparency = $false; increaseContrast = $false; reduceMotion = $false }
        controlsByRepetition = @(
            foreach ($repetition in 1..2) {
                [pscustomobject]@{
                    status = "backdrop-filtering-observed"; reasons = @()
                    flatTintRelativeFrequencyRatio = 1.0; flatTintCoarseRetention = 0.6; flatTintDarkMeanLift = 0.36
                    materialRelativeFrequencyRatio = 0.1; materialToTintFrequencyRatio = 0.1; materialCoarseRetention = 0.625
                }
            }
        )
        positiveControlStatus = "backdrop-filtering-observed"; inconclusiveReasons = @(); observations = $observations
    }
    Publish-MaterialTestCapture $fixture
    Publish-MaterialTestObservation $fixture
    return $fixture
}

try {
    foreach ($name in @("swiftui-material-reference-common.ps1", "test-swiftui-material-reference.ps1")) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepositoryRoot "scripts/$name"), [ref]$tokens, [ref]$errors)
        Assert-MaterialTest ($errors.Count -eq 0) "PowerShell syntax in $name"
    }
    # Dictionary fixtures only: never inspect or print the caller's actual
    # environment. Build override diagnostics must contain names, not values.
    $ordinaryEnvironment = @{
        GITHUB_SHA = $script:MaterialTestCommit; GITHUB_RUN_ID = "12345"; GITHUB_RUN_ATTEMPT = "1"
        HOME = "synthetic-home"; DEVELOPER_DIR = "synthetic-developer-directory"; XCODE_VERSION = "26.6"
        SWIFT_WINDOWSUI_REFERENCE_BUILD_CONFIGURATION = "release"
    }
    Assert-MaterialTest (@(Get-SwiftUIMaterialEnvironmentOverrides -Environment $ordinaryEnvironment).Count -eq 0) "ordinary workflow variables and declared release configuration are allowed"
    Assert-MaterialTest (@(Get-SwiftUIMaterialEnvironmentOverrides -Environment @{}).Count -eq 0) "an empty environment has no compiler overrides"
    $overrideNames = @(
        "SWIFT_EXEC", "SWIFT_EXEC_MANIFEST", "SWIFT_DRIVER_SWIFT_FRONTEND_EXEC", "SWIFTPM_CUSTOM_LIBS_DIR",
        "SWIFTC_MAXIMUM_DETERMINISM", "SDKROOT", "TOOLCHAINS", "MACOSX_DEPLOYMENT_TARGET",
        "DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "CC", "CXX", "LIBTOOL", "AR", "LD", "LD_PRELOAD",
        "CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "OBJC_INCLUDE_PATH", "LIBRARY_PATH",
        "CLANG_MODULE_CACHE_PATH", "XCODE_XCCONFIG_FILE"
    )
    $overrides = @{}
    $emptyOverrides = @{}
    $syntheticEnvironmentValue = "synthetic-unlogged-value-" + [Guid]::NewGuid().ToString("N")
    foreach ($name in $overrideNames) {
        $overrides[$name] = $syntheticEnvironmentValue
        $emptyOverrides[$name] = ""
    }
    $reportedOverrides = @(Get-SwiftUIMaterialEnvironmentOverrides -Environment $overrides)
    Assert-MaterialTest ($reportedOverrides.Count -eq $overrideNames.Count) "return every conflicting override name exactly once"
    foreach ($name in $overrideNames) {
        Assert-MaterialTest ($reportedOverrides -ccontains $name) "report the $name override without its value"
        Assert-MaterialTest ($overrides[$name] -ceq $syntheticEnvironmentValue) "environment validation does not mutate $name"
    }
    Assert-MaterialTest ($reportedOverrides -cnotcontains $syntheticEnvironmentValue) "override output never contains environment values"
    Assert-MaterialTest (@(Get-SwiftUIMaterialEnvironmentOverrides -Environment $emptyOverrides).Count -eq 0) "empty compiler override values do not override anything"
    foreach ($name in $overrideNames) { $emptyOverrides[$name] = $null }
    Assert-MaterialTest (@(Get-SwiftUIMaterialEnvironmentOverrides -Environment $emptyOverrides).Count -eq 0) "null override values are absent"
    $whitespaceOverride = @(Get-SwiftUIMaterialEnvironmentOverrides -Environment @{ SDKROOT = " " })
    Assert-MaterialTest ($whitespaceOverride.Count -eq 1 -and $whitespaceOverride[0] -ceq "SDKROOT") "a whitespace SDK path is still a nonempty override"
    $baselineHashBefore = Get-MaterialTestHash $script:MaterialTestBaseline
    $valid = New-MaterialTestFixture "valid-confirmed"
    $sdk = Read-MaterialTestSDK $valid
    Assert-MaterialTest ($sdk.captureManifestSha256 -ceq (Get-MaterialTestHash $valid.capturePath)) "return the verified SDK capture hash"
    Assert-MaterialTest ($sdk.baselineManifestSha256 -ceq (Get-MaterialTestHash $valid.manifestPath)) "return the requested baseline hash"
    Assert-MaterialTest (-not $sdk.exactIdentityPreviouslyReviewed) "matching requested versions do not promote the exact identity to reviewed"
    Assert-MaterialTest ($sdk.capture.host.macOSBuildVersion -ceq "TESTOS") "retain the runtime host build independently from the SDK build"
    $result = Read-MaterialTestObservation $valid $sdk
    Assert-MaterialTest ($result.manifestSha256 -ceq (Get-MaterialTestHash $valid.observationPath)) "return the material manifest hash"
    Assert-MaterialTest ($result.positiveControlStatus -ceq "backdrop-filtering-observed") "preserve successful positive-control status without qualification"
    Assert-MaterialTest ($result.runtimeOSBuild -ceq "TESTOS" -and $result.architecture -ceq "x86_64") "retain the actually observed OS build and native architecture"
    Assert-MaterialTest ($result.manifest.groupBehaviorReview -match '^unreviewed;') "successful controls do not review group behavior"
    Assert-MaterialTest ($result.manifest.qualification -match '^candidate-only;') "successful controls remain candidate observations"

    $inconclusive = New-MaterialTestFixture "valid-inconclusive"
    $inconclusive.observation.positiveControlStatus = "inconclusive"
    $inconclusive.observation.inconclusiveReasons = @("Synthetic ordinary-material control could not establish spatial filtering.")
    foreach ($control in $inconclusive.observation.controlsByRepetition) {
        $control.status = "inconclusive"
        $control.reasons = @("Synthetic ordinary-material control could not establish spatial filtering.")
    }
    Publish-MaterialTestObservation $inconclusive
    $inconclusiveResult = Read-MaterialTestObservation $inconclusive (Read-MaterialTestSDK $inconclusive)
    Assert-MaterialTest ($inconclusiveResult.positiveControlStatus -ceq "inconclusive") "inconclusive capture is valid operational evidence"
    Assert-MaterialTest ($inconclusiveResult.manifest.inconclusiveReasons[0] -ceq $inconclusive.observation.inconclusiveReasons[0]) "preserve the inconclusive reason verbatim"

    $sdkCases = @(
        @{ name = "capture-tamper"; pattern = '(?i)capture.*(hash|sha256|digest)|(?:hash|sha256|digest).*capture'; publish = $false; change = {
            param($f) [System.IO.File]::AppendAllText($f.capturePath, " ", $script:MaterialTestUTF8)
        } },
        @{ name = "status-hash-tamper"; pattern = '(?i)capture.*(hash|sha256|digest)|(?:hash|sha256|digest).*capture'; publish = $false; change = {
            param($f) $f.status.captureManifestSha256 = "3" * 64; Write-SwiftUIBaselineJson $f.status $f.statusPath
        } },
        @{ name = "digest-tamper"; pattern = '(?i)(capture|digest|sha256|hash)'; publish = $false; change = {
            param($f) Write-MaterialTestText $f.digestPath (("3" * 64) + "  capture.json`n")
        } },
        @{ name = "missing-completion"; pattern = '(?i)(status|complete|exported)'; publish = $false; change = {
            param($f) $f.status.status = "in-progress"; Write-SwiftUIBaselineJson $f.status $f.statusPath
        } },
        @{ name = "failed-export"; pattern = '(?i)(status|complete|exported)'; publish = $false; change = {
            param($f) $f.status.status = "failed"; Write-SwiftUIBaselineJson $f.status $f.statusPath
        } },
        @{ name = "status-promotes-conformance"; pattern = '(?i)(behavior|conformance|qualification|status|complete SDK candidate)'; publish = $false; change = {
            param($f) $f.status.behaviorConformance = "verified"; Write-SwiftUIBaselineJson $f.status $f.statusPath
        } },
        @{ name = "status-capture-traversal"; pattern = '(?i)(capture|path|file|basename)'; publish = $false; change = {
            param($f) $f.status.captureManifest = "../capture.json"; Write-SwiftUIBaselineJson $f.status $f.statusPath
        } },
        @{ name = "baseline-copy-tamper"; pattern = '(?i)baseline.*(hash|sha256|digest)|(?:hash|sha256|digest).*baseline'; publish = $false; change = {
            param($f) [System.IO.File]::AppendAllText($f.baselineCopy, " ", $script:MaterialTestUTF8)
        } },
        @{ name = "requested-baseline-mismatch"; pattern = '(?i)(baseline|manifest).*(hash|sha256|digest|match)|(?:hash|sha256|digest|match).*(baseline|manifest)'; publish = $false; change = {
            param($f) [System.IO.File]::AppendAllText($f.manifestPath, " ", $script:MaterialTestUTF8)
        } },
        @{ name = "compiler-bytes-tamper"; pattern = '(?i)(swift|compiler|tool).*(hash|sha256|digest)|(?:hash|sha256|digest).*(swift|compiler|tool)'; publish = $false; change = {
            param($f) Write-MaterialTestText $f.swiftPath "TAMPERED SYNTHETIC COMPILER"
        } },
        @{ name = "sdk-settings-copy-tamper"; pattern = '(?i)(SDK|settings).*(hash|sha256|digest)|(?:hash|sha256|digest).*(SDK|settings)'; publish = $false; change = {
            param($f) Write-MaterialTestText $f.settingsCopy "TAMPERED SYNTHETIC SDK COPY"
        } },
        @{ name = "live-sdk-settings-tamper"; pattern = '(?i)(SDK|settings).*(hash|sha256|digest)|(?:hash|sha256|digest).*(SDK|settings)'; publish = $false; change = {
            param($f) Write-MaterialTestText $f.settingsPath "TAMPERED SYNTHETIC LIVE SDK"
        } },
        @{ name = "unsupported-capture-schema"; pattern = '(?i)(schema|version|candidate.*baseline)'; publish = $true; change = {
            param($f) $f.capture.schemaVersion = 99
        } },
        @{ name = "wrong-xcode-release"; pattern = '(?i)(wrong|mismatch|expected).*xcode|xcode.*(wrong|mismatch|expected)'; publish = $true; change = {
            param($f) $f.capture.observedIdentity.xcodeVersion = "26.7"
        } },
        @{ name = "wrong-sdk-release"; pattern = '(?i)(wrong|mismatch|expected).*(SDK|sdkVersion)|(SDK|sdkVersion).*(wrong|mismatch|expected)'; publish = $true; change = {
            param($f) $f.capture.observedIdentity.sdkVersion = "26.6"
        } },
        @{ name = "wrong-compiler-release"; pattern = '(?i)(wrong|mismatch|expected).*(Swift|compiler)|(Swift|compiler).*(wrong|mismatch|expected)'; publish = $true; change = {
            param($f) $f.capture.observedIdentity.swiftCompilerVersion = "6.4"
        } },
        @{ name = "sdk-record-version-mismatch"; pattern = '(?i)(SDK|version|identity)'; publish = $true; change = {
            param($f) $f.capture.sdk.version = "26.6"
        } },
        @{ name = "sdk-record-build-mismatch"; pattern = '(?i)(SDK|build|identity)'; publish = $true; change = {
            param($f) $f.capture.sdk.buildVersion = "ANOTHERSDK"
        } },
        @{ name = "capture-promotes-release"; pattern = '(?i)(release|qualification|candidate)'; publish = $true; change = {
            param($f) $f.capture.qualification.releaseQualified = $true
        } },
        @{ name = "capture-promotes-behavior"; pattern = '(?i)(behavior|conformance|qualification|candidate)'; publish = $true; change = {
            param($f) $f.capture.qualification.behaviorConformanceVerified = $true
        } },
        @{ name = "capture-promotes-api-audit"; pattern = '(?i)(audit|qualification|candidate)'; publish = $true; change = {
            param($f) $f.capture.qualification.publicAPIAuditComplete = $true
        } },
        @{ name = "capture-promotes-identity"; pattern = '(?i)(review|identity)'; publish = $true; change = {
            param($f) $f.capture.exactIdentityPreviouslyReviewed = $true
        } },
        @{ name = "compiler-outside-xcode"; pattern = '(?i)(XcodeDefault|developer|contain|outside|toolchain)'; publish = $true; change = {
            param($f)
            $outside = Join-Path $f.directory "Other-Xcode/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $outside))
            Copy-Item -LiteralPath $f.swiftPath -Destination $outside
            $f.capture.tools[0].path = $outside.Replace('\', '/')
        } },
        @{ name = "sdk-outside-xcode"; pattern = '(?i)(developer|contain|outside|SDK|Xcode)'; publish = $true; change = {
            param($f)
            $outside = Join-Path $f.directory "Other-SDK"
            [void][System.IO.Directory]::CreateDirectory($outside)
            Copy-Item -LiteralPath $f.settingsPath -Destination (Join-Path $outside "SDKSettings.json")
            $f.capture.sdk.path = $outside.Replace('\', '/')
        } },
        @{ name = "duplicate-swift-tool"; pattern = '(?i)(one|single|duplicate|tool|Swift)'; publish = $true; change = {
            param($f) $f.capture.tools += (Copy-MaterialTestObject $f.capture.tools[0])
        } },
        @{ name = "missing-swift-tool"; pattern = '(?i)(tool|Swift)'; publish = $true; change = {
            param($f) $f.capture.tools = @($f.capture.tools[1])
        } },
        @{ name = "baseline-path-traversal"; pattern = '(?i)(baseline|path|basename|file)'; publish = $true; change = {
            param($f) $f.capture.baselineManifest.path = "../requested-baseline.json"
        } },
        @{ name = "settings-path-traversal"; pattern = '(?i)(settings|path|basename|file|SDK metadata)'; publish = $true; change = {
            param($f) $f.capture.sdk.settingsPath = "../SDKSettings.json"
        } },
        @{ name = "array-status-status"; pattern = '(?i)(status|field|type|string|scalar)'; publish = $false; change = {
            param($f) $f.status.status = @(); Write-SwiftUIBaselineJson $f.status $f.statusPath
        } },
        @{ name = "array-capture-status"; pattern = '(?i)(status|field|type|string|scalar)'; publish = $true; change = {
            param($f) $f.capture.status = @()
        } },
        @{ name = "array-capture-baseline-id"; pattern = '(?i)(baselineId|field|type|string|scalar)'; publish = $true; change = {
            param($f) $f.capture.baselineId = @()
        } },
        @{ name = "array-swift-tool-path"; pattern = '(?i)(path|field|type|string|scalar)'; publish = $true; change = {
            param($f) $f.capture.tools[0].path = @()
        } },
        @{ name = "array-swift-tool-hash"; pattern = '(?i)(sha256|field|type|string|scalar)'; publish = $true; change = {
            param($f) $f.capture.tools[0].sha256 = @()
        } },
        @{ name = "array-observed-sdk-version"; pattern = '(?i)(sdkVersion|field|type|string|scalar)'; publish = $true; change = {
            param($f) $f.capture.observedIdentity.sdkVersion = @()
        } }
    )
    foreach ($case in $sdkCases) {
        $fixture = New-MaterialTestFixture $case.name
        & $case.change $fixture | Out-Null
        if ($case.publish) { Publish-MaterialTestCapture $fixture }
        Test-MaterialRejection { Read-MaterialTestSDK $fixture } $case.pattern $case.name
    }

    $observationCases = @(
        @{ name = "unsupported-observation-schema"; pattern = '(?i)(schema|version|supported.*candidate)'; change = { param($f) $f.observation.schemaVersion = 2 } },
        @{ name = "unsupported-fixture-version"; pattern = '(?i)(fixture|version|supported.*candidate)'; change = { param($f) $f.observation.fixtureVersion = 99 } },
        @{ name = "observation-promotes-qualification"; pattern = '(?i)(candidate|qualification)'; change = { param($f) $f.observation.qualification = "release-qualified" } },
        @{ name = "observation-promotes-group-review"; pattern = '(?i)(group|review|unreviewed)'; change = { param($f) $f.observation.groupBehaviorReview = "reviewed; conforms to SwiftUI" } },
        @{ name = "wrong-observation-xcode"; pattern = '(?i)(xcode|identity)'; change = { param($f) $f.observation.provenance.xcodeAtCapture = "Xcode 26.7`nBuild version TESTXCODE" } },
        @{ name = "wrong-observation-xcode-build"; pattern = '(?i)(xcode|identity|build)'; change = { param($f) $f.observation.provenance.xcodeAtCapture = "Xcode 26.6`nBuild version OTHERXCODE" } },
        @{ name = "wrong-observation-compiler"; pattern = '(?i)(Swift|compiler|identity)'; change = { param($f) $f.observation.provenance.swiftAtCapture = "Apple Swift version 6.3 (different synthetic compiler)" } },
        @{ name = "wrong-observation-sdk"; pattern = '(?i)(SDK|identity)'; change = { param($f) $f.observation.provenance.sdkVersionAtCapture = "26.6" } },
        @{ name = "wrong-observation-sdk-build"; pattern = '(?i)(SDK|identity|build)'; change = { param($f) $f.observation.provenance.sdkBuildAtCapture = "OTHERBUILD" } },
        @{ name = "wrong-observation-sdk-path"; pattern = '(?i)(SDK|path)'; change = { param($f) $f.observation.provenance.sdkPathAtCapture = (Join-Path $f.directory "Other-SDK").Replace('\', '/') } },
        @{ name = "wrong-os-build"; pattern = '(?i)(OS|runtime|build)'; change = { param($f) $f.observation.provenance.osBuild = "OTHEROS" } },
        @{ name = "unavailable-os-build"; pattern = '(?i)(OS|runtime|build|unavailable)'; change = { param($f) $f.observation.provenance.osBuild = "unavailable" } },
        @{ name = "wrong-source-commit"; pattern = '(?i)(source|commit)'; change = { param($f) $f.observation.provenance.sourceCommitAtCapture = "2" * 40 } },
        @{ name = "dirty-source"; pattern = '(?i)(clean|dirty|tracked|working.tree|source)'; change = { param($f) $f.observation.provenance.trackedWorkingTreeAtCapture = " M Sources/macos-reference-renderer/main.swift" } },
        @{ name = "wrong-executable-hash"; pattern = '(?i)(executable|hash|sha256|build provenance)'; change = { param($f) $f.observation.provenance.executableSHA256 = "3" * 64 } },
        @{ name = "wrong-architecture"; pattern = '(?i)(architecture|x86_64|runtime/build provenance)'; change = { param($f) $f.observation.provenance.processArchitecture = "arm64" } },
        @{ name = "wrong-language-mode"; pattern = '(?i)(Swift|language|mode|runtime/build provenance)'; change = { param($f) $f.observation.provenance.swiftLanguageMode = "5" } },
        @{ name = "wrong-build-configuration"; pattern = '(?i)(release|configuration|build)'; change = { param($f) $f.observation.provenance.declaredBuildConfiguration = "debug" } },
        @{ name = "unsupported-control-status"; pattern = '(?i)(control|status)'; change = { param($f) $f.observation.positiveControlStatus = "conformance-passed" } },
        @{ name = "inconclusive-without-reason"; pattern = '(?i)(inconclusive|reason)'; change = { param($f) $f.observation.positiveControlStatus = "inconclusive"; $f.observation.inconclusiveReasons = @() } },
        @{ name = "missing-fixture"; pattern = '(?i)(fixture|six|6|observation)'; change = { param($f) $f.observation.observations = @($f.observation.observations | Select-Object -First 5) } },
        @{ name = "duplicate-fixture"; pattern = '(?i)(fixture|duplicate|observation)'; change = { param($f) $f.observation.observations[5].fixture = $f.observation.observations[0].fixture } },
        @{ name = "unknown-fixture"; pattern = '(?i)(fixture|unknown|observation)'; change = { param($f) $f.observation.observations[5].fixture = "unknown-material-fixture" } },
        @{ name = "missing-repetition"; pattern = '(?i)(capture|repetition|two|2)'; change = { param($f) $f.observation.observations[0].captures = @($f.observation.observations[0].captures[0]) } },
        @{ name = "duplicate-repetition"; pattern = '(?i)(capture|repetition|duplicate|malformed material PNG record)'; change = { param($f) $f.observation.observations[0].captures[1].repetition = 1 } },
        @{ name = "unknown-repetition"; pattern = '(?i)(capture|repetition|malformed material PNG record)'; change = { param($f) $f.observation.observations[0].captures[1].repetition = 3 } },
        @{ name = "capture-error"; pattern = '(?i)(capture|error|failure|Incomplete.*PNG record)'; change = { param($f) $f.observation.observations[0].captures[0].error = "synthetic capture allocation failure" } },
        @{ name = "wrong-logical-size"; pattern = '(?i)(size|dimension|width|geometry|384|fixture plan)'; change = { param($f) $f.observation.logicalWidth = 385 } },
        @{ name = "wrong-scale"; pattern = '(?i)(scale|dimension|geometry|2|fixture plan)'; change = { param($f) $f.observation.requestedScale = 1 } },
        @{ name = "wrong-pixel-width"; pattern = '(?i)(pixel|dimension|768|PNG)'; change = { param($f) $f.observation.observations[0].captures[0].decodedPNG.pixelWidth = 767 } },
        @{ name = "wrong-pixel-height"; pattern = '(?i)(pixel|dimension|576|PNG)'; change = { param($f) $f.observation.observations[0].captures[0].decodedPNG.pixelHeight = 577 } },
        @{ name = "png-hash-mismatch"; pattern = '(?i)(PNG|hash|sha256)'; change = { param($f) $f.observation.observations[0].captures[0].sha256 = "4" * 64 } },
        @{ name = "png-byte-tamper"; pattern = '(?i)(PNG|hash|sha256)'; change = {
            param($f) Write-MaterialTestText (Join-Path $f.observationRoot $f.observation.observations[0].captures[0].pngFile) "TAMPERED SYNTHETIC PAYLOAD"
        } },
        @{ name = "missing-png"; pattern = '(?i)(PNG|missing|file|exist)'; change = {
            param($f) Remove-Item -LiteralPath (Join-Path $f.observationRoot $f.observation.observations[0].captures[0].pngFile)
        } },
        @{ name = "png-parent-traversal"; pattern = '(?i)(PNG|path|basename|filename|file name)'; change = { param($f) $f.observation.observations[0].captures[0].pngFile = "../outside.png" } },
        @{ name = "png-backslash-traversal"; pattern = '(?i)(PNG|path|basename|filename|file name)'; change = { param($f) $f.observation.observations[0].captures[0].pngFile = '..\outside.png' } },
        @{ name = "png-absolute-path"; pattern = '(?i)(PNG|path|basename|filename|file name)'; change = { param($f) $f.observation.observations[0].captures[0].pngFile = (Join-Path $f.directory "outside.png") } },
        @{ name = "png-reused-between-captures"; pattern = '(?i)(PNG|file|duplicate|capture)'; change = {
            param($f)
            $f.observation.observations[0].captures[1].pngFile = $f.observation.observations[0].captures[0].pngFile
            $f.observation.observations[0].captures[1].sha256 = $f.observation.observations[0].captures[0].sha256
        } },
        @{ name = "array-source-commit"; pattern = '(?i)(sourceCommit|field|type|string|scalar)'; change = { param($f) $f.observation.provenance.sourceCommitAtCapture = @() } },
        @{ name = "array-executable-hash"; pattern = '(?i)(executableSHA256|field|type|string|scalar)'; change = { param($f) $f.observation.provenance.executableSHA256 = @() } },
        @{ name = "array-os-build"; pattern = '(?i)(osBuild|field|type|string|scalar)'; change = { param($f) $f.observation.provenance.osBuild = @() } },
        @{ name = "array-process-architecture"; pattern = '(?i)(processArchitecture|field|type|string|scalar)'; change = { param($f) $f.observation.provenance.processArchitecture = @() } },
        @{ name = "array-build-configuration"; pattern = '(?i)(declaredBuildConfiguration|field|type|string|scalar)'; change = { param($f) $f.observation.provenance.declaredBuildConfiguration = @() } },
        @{ name = "array-qualification"; pattern = '(?i)(qualification|field|type|string|scalar)'; change = { param($f) $f.observation.qualification = @() } },
        @{ name = "array-logical-width"; pattern = '(?i)(logicalWidth|field|type|number|integer|scalar)'; change = { param($f) $f.observation.logicalWidth = @() } },
        @{ name = "array-logical-height"; pattern = '(?i)(logicalHeight|field|type|number|integer|scalar)'; change = { param($f) $f.observation.logicalHeight = @() } },
        @{ name = "array-requested-scale"; pattern = '(?i)(requestedScale|field|type|number|integer|scalar)'; change = { param($f) $f.observation.requestedScale = @() } },
        @{ name = "array-pixel-width"; pattern = '(?i)(pixelWidth|field|type|number|integer|scalar)'; change = { param($f) $f.observation.observations[0].captures[0].decodedPNG.pixelWidth = @() } },
        @{ name = "array-pixel-height"; pattern = '(?i)(pixelHeight|field|type|number|integer|scalar)'; change = { param($f) $f.observation.observations[0].captures[0].decodedPNG.pixelHeight = @() } },
        @{ name = "array-measurement-width"; pattern = '(?i)(pixelWidth|field|type|number|integer|scalar)'; change = { param($f) $f.observation.observations[0].captures[0].measurements.pixelWidth = @() } },
        @{ name = "array-measurement-height"; pattern = '(?i)(pixelHeight|field|type|number|integer|scalar)'; change = { param($f) $f.observation.observations[0].captures[0].measurements.pixelHeight = @() } },
        @{ name = "array-stable-boolean"; pattern = '(?i)(repeatedMeasurementsStable|field|type|boolean|scalar)'; change = { param($f) $f.observation.observations[0].repeatedMeasurementsStable = @() } },
        @{ name = "null-control-records"; pattern = '(?i)(control|object|record|field|type)'; change = { param($f) $f.observation.controlsByRepetition = @($null, $null) } },
        @{ name = "unknown-inconclusive-repetition-status"; pattern = '(?i)(control|classification|status)'; change = {
            param($f)
            $f.observation.positiveControlStatus = "inconclusive"
            $f.observation.inconclusiveReasons = @("Synthetic overall control is inconclusive.")
            $f.observation.controlsByRepetition[0].status = "unknown-control-classification"
        } },
        @{ name = "confirmed-repetition-with-reasons"; pattern = '(?i)(control|classification|reason|inconsistent)'; change = {
            param($f) $f.observation.controlsByRepetition[0].reasons = @("Contradicts the confirmed repetition.")
        } },
        @{ name = "confirmed-repetition-with-reasons-in-inconclusive-report"; pattern = '(?i)(control|classification|reason|inconsistent)'; change = {
            param($f)
            $f.observation.positiveControlStatus = "inconclusive"
            $f.observation.inconclusiveReasons = @("Synthetic controls were unstable across repetitions.")
            $f.observation.controlsByRepetition[0].reasons = @("Contradicts the confirmed repetition even in an inconclusive report.")
        } },
        @{ name = "inconclusive-with-all-confirmed-stable-controls"; pattern = '(?i)(inconclusive|control|instability|reason|inconsistent)'; change = {
            param($f)
            $f.observation.positiveControlStatus = "inconclusive"
            $f.observation.inconclusiveReasons = @("Contradicts the confirmed and stable repetition records.")
        } }
    )
    foreach ($case in $observationCases) {
        $fixture = New-MaterialTestFixture $case.name
        $context = Read-MaterialTestSDK $fixture
        & $case.change $fixture | Out-Null
        Publish-MaterialTestObservation $fixture
        Test-MaterialRejection { Read-MaterialTestObservation $fixture $context } $case.pattern $case.name
    }

    foreach ($metadata in @("status", "capture", "observation")) {
        $fixture = New-MaterialTestFixture "singleton-array-root-$metadata"
        $context = Read-MaterialTestSDK $fixture
        $target = switch ($metadata) {
            "status" { $fixture.statusPath }
            "capture" { $fixture.capturePath }
            "observation" { $fixture.observationPath }
        }
        # Wrap the exact valid JSON bytes as text. PowerShell pipelines and
        # ConvertTo-Json can otherwise unwrap a one-element object array.
        $validJSON = [System.IO.File]::ReadAllText($target)
        Write-MaterialTestText $target ("[" + $validJSON + "]")
        if ($metadata -ceq "capture") {
            $wrappedHash = Get-MaterialTestHash $fixture.capturePath
            Write-MaterialTestText $fixture.digestPath "$wrappedHash  capture.json`n"
            $fixture.status.captureManifestSha256 = $wrappedHash
            Write-SwiftUIBaselineJson $fixture.status $fixture.statusPath
        }
        if ($metadata -ceq "observation") {
            Test-MaterialRejection { Read-MaterialTestObservation $fixture $context } '(?i)(root|JSON.*object|object.*JSON)' "reject singleton-array observation root"
        } else {
            Test-MaterialRejection { Read-MaterialTestSDK $fixture } '(?i)(root|JSON.*object|object.*JSON)' "reject singleton-array $metadata root"
        }
    }

    # The SDK inventory is not an input to material capture. Invalid JSON,
    # an absent file, and an exclusively locked 16 MiB sentinel must all work.
    $noInventory = New-MaterialTestFixture "inventory-never-read"
    $context = Read-MaterialTestSDK $noInventory
    Assert-MaterialTest ($null -ne (Read-MaterialTestObservation $noInventory $context)) "invalid inventory JSON is not parsed"
    Remove-Item -LiteralPath $noInventory.inventoryPath
    Assert-MaterialTest ($null -ne (Read-MaterialTestSDK $noInventory)) "inventory payload need not be present"
    $inventoryStream = [System.IO.File]::Open($noInventory.inventoryPath, [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $sentinel = $script:MaterialTestUTF8.GetBytes("SYNTHETIC INVALID INVENTORY; DO NOT READ THIS FILE.")
        $inventoryStream.Write($sentinel, 0, $sentinel.Length)
        $inventoryStream.SetLength(16MB)
        $inventoryStream.Flush()
        $context = Read-MaterialTestSDK $noInventory
        Assert-MaterialTest ($null -ne (Read-MaterialTestObservation $noInventory $context)) "exclusive inventory lock does not block provenance validation"
        Assert-MaterialTest ($inventoryStream.Position -eq $sentinel.Length -and $inventoryStream.Length -eq 16MB) "inventory sentinel stays unchanged"
    } finally { $inventoryStream.Dispose() }

    foreach ($metadata in @("capture", "observation", "status")) {
        $fixture = New-MaterialTestFixture "oversized-$metadata"
        $context = Read-MaterialTestSDK $fixture
        $target = switch ($metadata) {
            "capture" { $fixture.capturePath }
            "observation" { $fixture.observationPath }
            "status" { $fixture.statusPath }
        }
        # Valid JSON larger than the helper's metadata budget must be rejected
        # before deserialization. A mismatching hash is not this test's oracle.
        Write-MaterialTestText $target ('{"syntheticPadding":"' + ("x" * 17MB) + '"}')
        if ($metadata -ceq "capture") {
            $largeHash = Get-MaterialTestHash $fixture.capturePath
            Write-MaterialTestText $fixture.digestPath "$largeHash  capture.json`n"
            $fixture.status.captureManifestSha256 = $largeHash
            Write-SwiftUIBaselineJson $fixture.status $fixture.statusPath
        }
        if ($metadata -ceq "observation") {
            Test-MaterialRejection { Read-MaterialTestObservation $fixture $context } '(?i)(large|limit|maximum|bounded|size|bytes)' "reject oversized observation metadata before JSON parsing"
        } else {
            Test-MaterialRejection { Read-MaterialTestSDK $fixture } '(?i)(large|limit|maximum|bounded|size|bytes)' "reject oversized $metadata metadata before JSON parsing"
        }
    }
    Assert-MaterialTest ((Get-MaterialTestHash $script:MaterialTestBaseline) -ceq $baselineHashBefore) "synthetic tests never edit or promote the repository baseline"
    if ($script:MaterialTestFailures.Count -gt 0) {
        throw ("Material provenance rejected $($script:MaterialTestFailures.Count) test expectations:`n" + ($script:MaterialTestFailures -join "`n"))
    }
    Write-Host "Material provenance tests passed: $script:MaterialTestAssertions assertions across $script:MaterialTestCases synthetic fixtures. No native execution or pixel validation."
} finally {
    # Delete only this invocation's exact, resolved UUID child of the OS temp
    # directory. Do not pass enumerated paths to another shell for deletion.
    if (Test-Path -LiteralPath $script:MaterialTestRoot) {
        $resolvedRoot = Resolve-SwiftUIBaselineFileSystemPath -Path $script:MaterialTestRoot
        $resolvedTemp = (Resolve-SwiftUIBaselineFileSystemPath -Path $materialTestTemp).TrimEnd([char[]]"\/")
        $expectedRoot = [System.IO.Path]::GetFullPath((Join-Path $resolvedTemp $materialTestName))
        $comparison = [System.StringComparison]::Ordinal
        if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $comparison = [System.StringComparison]::OrdinalIgnoreCase }
        if (-not [string]::Equals($resolvedRoot, $expectedRoot, $comparison) -or
            -not [string]::Equals((Split-Path -Parent $resolvedRoot), $resolvedTemp, $comparison) -or
            $materialTestName -notmatch '^swiftui-material-provenance-[a-f0-9]{32}$') {
            throw "Refusing to clean a synthetic fixture directory outside the owned OS-temp location."
        }
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
