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

function Invoke-MaterialTestCleanup {
    param($OriginalFailure, [scriptblock]$Cleanup)
    try { & $Cleanup } catch {
        if ($null -eq $OriginalFailure) { throw }
        # A failing resolver can be reached both by the test and by cleanup.
        # Keep the original ErrorRecord/stack; never retry deletion unchecked.
        $OriginalFailure.Exception.Data["MaterialFixtureCleanupFailure"] = $_.Exception.Message
        Write-Warning "Material fixture cleanup also failed: $($_.Exception.Message). The original test failure is preserved." -WarningAction Continue
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
    param([string]$Name, [string]$CompilerVersionLine = $script:MaterialTestCompiler)
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
        -SDKVersion "26.5" -SDKBuildVersion "TESTSDK" -SwiftOutput "$CompilerVersionLine`nTarget: x86_64-apple-macosx26.5"
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
            swiftAtCapture = "$CompilerVersionLine`nTarget: x86_64-apple-macosx26.5"
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

function Get-MaterialHostingTestParameters {
    # Literal fixture constants are deliberately independent of the production
    # parameter generator; changing that generator must not change this oracle.
    return [pscustomobject][ordered]@{
        logicalWidth = 384; logicalHeight = 288; requestedScale = 2
        requestedAppearance = "light / NSAppearance.aqua"; material = "regularMaterial"
        repetitions = 2; settlingMillisecondsBeforeEachCapture = 50
        stripeWidthPoints = 4; patternBandBoundaryPoints = 144; baselinePhaseSampleInsetPixels = 2
        patternDarkSRGB = 0.1; patternLightSRGB = 0.9
        panel = [pscustomobject]@{ x = 24; y = 24; width = 336; height = 240 }
        fineSample = [pscustomobject]@{ x = 96; y = 64; width = 192; height = 32 }
        darkSample = [pscustomobject]@{ x = 64; y = 208; width = 16; height = 16 }
        lightSample = [pscustomobject]@{ x = 304; y = 208; width = 16; height = 16 }
        thresholds = [pscustomobject]@{
            patternMinimumContrast = 0.5; patternMaximumDarkMean = 0.25; patternMinimumLightMean = 0.75
            minimumSampleAlpha = 0.98; tintMinimumContrast = 0.15; tintMinimumRelativeFrequencyRatio = 0.8
            tintMaximumRelativeFrequencyRatio = 1.2; tintMaximumCoarseRetention = 0.9; tintMinimumDarkMeanLift = 0.1
            materialMinimumCoarseContrast = 0.04; materialMinimumCoarseRetention = 0.05
            materialMaximumRelativeFrequencyRatio = 0.35; materialMaximumFrequencyRatioRelativeToTint = 0.4
            maximumRepeatedMetricDifference = 0.02
        }
    }
}

function Get-MaterialHostingTestSchedule {
    # The independently declared order is fixture-major. Every second pair
    # reverses U/W; neither production schedule nor arm report generates it.
    $fixtures = @("pattern-control", "flat-tint-control", "material-direct-control",
        "material-compositing-group", "material-drawing-group", "material-content-blur")
    for ($fixtureIndex = 0; $fixtureIndex -lt $fixtures.Count; $fixtureIndex++) {
        $fixtureName = $fixtures[$fixtureIndex]
        for ($repetition = 1; $repetition -le 2; $repetition++) {
            $pair = $fixtureIndex * 2 + $repetition
            $armOrder = @("accessory-unattached", "accessory-unshown-window")
            if ($repetition -eq 2) { $armOrder = @("accessory-unshown-window", "accessory-unattached") }
            for ($position = 0; $position -lt 2; $position++) {
                $arm = $armOrder[$position]
                [pscustomobject][ordered]@{
                    ordinal = ($pair - 1) * 2 + $position + 1; pairIndex = $pair; positionInPair = $position + 1
                    arm = $arm; fixture = $fixtureName; repetition = $repetition
                    pngFile = "$arm-$fixtureName-$repetition.png"
                }
            }
        }
    }
}

function New-MaterialHostingTestApplication {
    param([string]$Policy = "accessory")
    return [pscustomobject]@{ activationPolicy = $Policy; isActive = $false; isHidden = $false; isRunning = $true }
}

function New-MaterialHostingTestWindow {
    return [pscustomobject]@{
        isVisible = $false; isMiniaturized = $false; isKeyWindow = $false; isMainWindow = $false
        occlusionStateVisible = $false; backingScaleFactor = 1.0
    }
}

function New-MaterialHostingTestSnapshot {
    param([ValidateSet("accessory-unattached", "accessory-unshown-window")][string]$Arm)
    $hasWindow = $Arm -ceq "accessory-unshown-window"
    $window = $null
    if ($hasWindow) { $window = New-MaterialHostingTestWindow }
    return [pscustomobject]@{
        timestampUTC = "2026-08-27T00:03:00Z"
        systemAccessibility = [pscustomobject]@{ reduceTransparency = $true; increaseContrast = $false; reduceMotion = $false }
        swiftUIEnvironment = [pscustomobject]@{
            status = "observed"; bodyEvaluationCount = 1; latestBodyEvaluationUTC = "2026-08-27T00:03:00Z"
            values = [pscustomobject]@{
                reduceTransparency = $true; reduceMotion = $false; colorScheme = "light"
                colorSchemeContrast = "standard"; displayScale = 2.0
            }
        }
        application = (New-MaterialHostingTestApplication)
        host = [pscustomobject]@{
            hasWindow = $hasWindow; hasSuperview = $hasWindow; isHidden = $false; isHiddenOrHasHiddenAncestor = $false
            isFlipped = $true; effectiveAppearance = "NSAppearanceNameAqua"
            frame = [pscustomobject]@{ x = 0; y = 0; width = 384; height = 288 }
            bounds = [pscustomobject]@{ x = 0; y = 0; width = 384; height = 288 }
            visibleRect = [pscustomobject]@{ x = 0; y = 0; width = 384; height = 288 }
            convertedBackingBounds = [pscustomobject]@{ x = 0; y = 0; width = 384; height = 288 }
            wantsLayer = $true; hasLayer = $true; layerContentsScale = 1.0; window = $window
        }
    }
}

function New-MaterialHostingTestCaptureProvenance {
    param([string]$Arm)
    return [pscustomobject]@{
        schemaVersion = 1
        observationScope = "before/after the synchronous cache, encode, and measurement attempt; SwiftUI values are the last body observation, not compositor state"
        recommendedBitmapScope = "bitmapImageRepForCachingDisplay(in:) sampled after the attempt; metadata only, not used for capture"
        before = (New-MaterialHostingTestSnapshot $Arm); after = (New-MaterialHostingTestSnapshot $Arm)
        cacheDisplayCompleted = $true
        recommendedBitmap = [pscustomobject]@{
            status = "observed"
            bitmap = [pscustomobject]@{
                pixelWidth = 384; pixelHeight = 288; logicalWidth = 384.0; logicalHeight = 288.0
                bitsPerSample = 8; samplesPerPixel = 4; hasAlpha = $true; isPlanar = $false
                bitsPerPixel = 32; bytesPerRow = 1536; bitmapFormatRawValue = 0; colorSpaceName = "NSCalibratedRGBColorSpace"
            }
        }
    }
}

function Publish-MaterialHostingTest {
    param($Fixture)
    Write-SwiftUIBaselineJson -Value $Fixture.hosting -Path $Fixture.hostingPath
}

function Read-MaterialHostingTest {
    param($Fixture, $Context)
    return Read-SwiftUIMaterialHostingExperiment -Directory $Fixture.observationRoot -SDKContext $Context `
        -ExpectedCommit $script:MaterialTestCommit -ExpectedExecutableSha256 $Fixture.executableHash `
        -ExpectedArchitecture "x86_64"
}

function New-MaterialHostingTestFixture {
    param([string]$Name)
    # The base fixture contains a deeply nested synthetic Xcode tool path.
    # Keep it below legacy Windows path limits; the sequential fixture counter
    # still makes every directory unique, and assertions retain the full name.
    $directoryLabel = $Name.Substring(0, [Math]::Min(32, $Name.Length))
    $fixture = New-MaterialTestFixture "hosting-$directoryLabel"
    $canonicalHash = Get-MaterialTestHash $fixture.observationPath
    $schedule = @(Get-MaterialHostingTestSchedule)
    $attempts = @(
        foreach ($step in $schedule) {
            $canonicalObservation = @($fixture.observation.observations | Where-Object { $_.fixture -ceq $step.fixture })[0]
            $capture = Copy-MaterialTestObject $canonicalObservation.captures[$step.repetition - 1]
            $capture.pngFile = $step.pngFile
            $pngPath = Join-Path $fixture.observationRoot $capture.pngFile
            Write-MaterialTestText $pngPath "SYNTHETIC NON-IMAGE HOSTING PAYLOAD: $($step.arm), $($step.fixture), repetition $($step.repetition). No pixels captured.`n"
            $capture.sha256 = Get-MaterialTestHash $pngPath
            $capture | Add-Member -NotePropertyName captureProvenance -NotePropertyValue (New-MaterialHostingTestCaptureProvenance $step.arm)
            $cleanup = [pscustomobject]@{
                ownsWindow = $false; status = "not-required"; closeCalled = $false
                contentDetached = $null; hostHasWindowAfterCleanup = $null; windowAfterCleanup = $null
                applicationAfterCleanup = (New-MaterialHostingTestApplication)
            }
            if ($step.arm -ceq "accessory-unshown-window") {
                $cleanup.ownsWindow = $true; $cleanup.status = "observed"; $cleanup.closeCalled = $true
                $cleanup.contentDetached = $true; $cleanup.hostHasWindowAfterCleanup = $false
                $cleanup.windowAfterCleanup = New-MaterialHostingTestWindow
            }
            [pscustomobject]@{
                attempt = (Copy-MaterialTestObject $step); setup = (New-MaterialHostingTestSnapshot $step.arm)
                capture = $capture; cleanup = $cleanup; protocolFailures = @(); error = $null
            }
        }
    )
    $arms = @(
        foreach ($arm in @("accessory-unattached", "accessory-unshown-window")) {
            [pscustomobject]@{
                arm = $arm
                observations = @(
                    foreach ($canonicalObservation in $fixture.observation.observations) {
                        [pscustomobject]@{
                            fixture = $canonicalObservation.fixture; modifierOrder = $canonicalObservation.modifierOrder
                            captureOrdinals = @($schedule | Where-Object { $_.arm -ceq $arm -and $_.fixture -ceq $canonicalObservation.fixture } |
                                Sort-Object -Property repetition | ForEach-Object { $_.ordinal })
                            repeatedMeasurementsStable = $true
                        }
                    }
                )
                controlsByRepetition = (Copy-MaterialTestObject $fixture.observation.controlsByRepetition)
                positiveControlStatus = "backdrop-filtering-observed"; inconclusiveReasons = @()
            }
        }
    )
    $hosting = [pscustomobject][ordered]@{
        schemaVersion = 1; experimentPlanVersion = 1; fixtureVersion = 1
        evidenceKind = "material-hosting-context-experiment-candidate"; requested = $true
        qualification = [pscustomobject]@{ nativeBehaviorReviewed = $false; nativeRuntimeBuildReviewed = $false; releaseQualified = $false }
        captureAPI = "NSHostingView.cacheDisplay(in:to:); no desktop or window capture"
        canonicalManifestFile = "manifest.json"; canonicalManifestSha256 = $canonicalHash
        canonicalPositiveControlStatus = $fixture.observation.positiveControlStatus; canonicalCaptureCount = 12
        provenance = (Copy-MaterialTestObject $fixture.observation.provenance)
        parameters = (Get-MaterialHostingTestParameters)
        startedAtUTC = "2026-08-27T00:03:00Z"; checkpointAtUTC = "2026-08-27T00:04:00Z"; finishedAtUTC = "2026-08-27T00:04:00Z"
        scheduledAttempts = $schedule; attempts = $attempts; arms = $arms
        session = [pscustomobject]@{
            status = "completed"; phase = "finished"; initialApplication = (New-MaterialHostingTestApplication "prohibited")
            restorationRequired = $true
            accessoryTransition = [pscustomobject]@{
                requestedPolicy = "accessory"; returnedSuccess = $true; observedApplication = (New-MaterialHostingTestApplication)
            }
            restoration = [pscustomobject]@{
                requestedPolicy = "prohibited"; returnedSuccess = $true; observedApplication = (New-MaterialHostingTestApplication "prohibited")
            }
            completedAttemptCount = 24; nextCaptureOrdinal = $null; failures = @(); additionalFailureCount = 0
        }
    }
    $fixture | Add-Member -NotePropertyName hosting -NotePropertyValue $hosting
    $fixture | Add-Member -NotePropertyName hostingPath -NotePropertyValue (Join-Path $fixture.observationRoot "hosting-experiment.json")
    $fixture | Add-Member -NotePropertyName originalCanonicalHash -NotePropertyValue $canonicalHash
    Publish-MaterialHostingTest $fixture
    return $fixture
}

function Set-MaterialHostingTestOpaqueArm {
    param($Fixture, [int]$ArmIndex)
    $arm = $Fixture.hosting.arms[$ArmIndex]
    $reason = "The ordinary material has no coarse contrast; opaque or missing content cannot establish filtering."
    foreach ($record in $Fixture.hosting.attempts) {
        if ($record.attempt.arm -ceq $arm.arm -and $record.attempt.fixture -like "material-*") {
            $metrics = $record.capture.measurements
            $metrics.fineContrast = 0.0; $metrics.coarseContrast = 0.0
            $metrics.fineDarkMean = 0.8; $metrics.fineLightMean = 0.8; $metrics.darkMean = 0.8; $metrics.lightMean = 0.8
        }
    }
    foreach ($control in $arm.controlsByRepetition) {
        $control.status = "inconclusive"; $control.reasons = @($reason)
        $control.materialRelativeFrequencyRatio = $null; $control.materialToTintFrequencyRatio = $null
        $control.materialCoarseRetention = 0.0
    }
    $arm.positiveControlStatus = "inconclusive"
    $arm.inconclusiveReasons = @("Repetition 1: $reason", "Repetition 2: $reason")
}

function Set-MaterialHostingTestValue {
    param($Fixture, [string]$Path, $Value)
    $parts = $Path.Split('.')
    $current = $Fixture.hosting
    for ($index = 0; $index -lt $parts.Length - 1; $index++) {
        $part = $parts[$index]
        if ($current -is [System.Array]) { $current = $current[[int]$part] }
        else { $current = $current.PSObject.Properties[$part].Value }
    }
    $last = $parts[$parts.Length - 1]
    if ($current -is [System.Array]) { $current[[int]$last] = $Value }
    else { $current.PSObject.Properties[$last].Value = $Value }
}

function Set-MaterialHostingTestPartial {
    param($Fixture, [ValidateSet("in-progress", "failed")][string]$Status)
    $report = $Fixture.hosting
    $report.finishedAtUTC = $null
    $report.session.status = $Status; $report.session.phase = "captures"
    $report.session.completedAttemptCount = 2; $report.session.nextCaptureOrdinal = 3
    $report.session.restoration = $null
    $report.attempts = @($report.attempts[0], $report.attempts[1])
    if ($Status -ceq "failed") {
        $report.finishedAtUTC = "2026-08-27T00:04:00Z"; $report.session.phase = "finished"
        $report.session.failures = @(
            [pscustomobject]@{ stage = "capture-or-checkpoint"; message = "Synthetic original capture failure."; captureOrdinal = 3 },
            [pscustomobject]@{ stage = "restoration"; message = "Synthetic restoration failure retained separately."; captureOrdinal = $null }
        )
        $report.session.restoration = [pscustomobject]@{
            requestedPolicy = "prohibited"; returnedSuccess = $false; observedApplication = (New-MaterialHostingTestApplication)
        }
    }
    foreach ($arm in $report.arms) {
        foreach ($observation in $arm.observations) {
            $observation.captureOrdinals = @($report.attempts | Where-Object {
                $_.attempt.arm -ceq $arm.arm -and $_.attempt.fixture -ceq $observation.fixture
            } | ForEach-Object { $_.attempt.ordinal })
            $observation.repeatedMeasurementsStable = $false
        }
        $reason = "Synthetic incomplete arm did not capture all control measurements."
        foreach ($control in $arm.controlsByRepetition) {
            $control.status = "inconclusive"; $control.reasons = @($reason)
            foreach ($field in @("flatTintRelativeFrequencyRatio", "flatTintCoarseRetention", "flatTintDarkMeanLift",
                    "materialRelativeFrequencyRatio", "materialToTintFrequencyRatio", "materialCoarseRetention")) {
                $control.$field = $null
            }
        }
        $arm.positiveControlStatus = "inconclusive"
        $arm.inconclusiveReasons = @("Repetition 1: $reason", "Repetition 2: $reason",
            "Control pattern-control did not produce stable repeated measurements.",
            "Control flat-tint-control did not produce stable repeated measurements.",
            "Control material-direct-control did not produce stable repeated measurements.")
    }
}

function Assert-MaterialHostingTestEquivalent {
    param($Actual, $Expected, [string]$Name)
    if ($Expected -is [pscustomobject]) {
        Assert-MaterialTest ($Actual -is [pscustomobject]) "$Name is an object"
        Assert-MaterialTest (@($Actual.PSObject.Properties).Count -eq @($Expected.PSObject.Properties).Count) "$Name has the exact fields"
        foreach ($property in $Expected.PSObject.Properties) {
            Assert-MaterialTest ($null -ne $Actual.PSObject.Properties[$property.Name]) "$Name retains $($property.Name)"
            Assert-MaterialHostingTestEquivalent $Actual.PSObject.Properties[$property.Name].Value $property.Value "$Name.$($property.Name)"
        }
    } elseif ($Expected -is [System.Array]) {
        Assert-MaterialTest ($Actual -is [System.Array] -and $Actual.Count -eq $Expected.Count) "$Name has the exact array size"
        for ($index = 0; $index -lt $Expected.Count; $index++) {
            Assert-MaterialHostingTestEquivalent $Actual[$index] $Expected[$index] "$Name[$index]"
        }
    } elseif ($Expected -is [string]) {
        Assert-MaterialTest ($Actual -is [string] -and $Actual -ceq $Expected) "$Name retains its exact string"
    } elseif ($Expected -is [bool]) {
        Assert-MaterialTest ($Actual -is [bool] -and $Actual -eq $Expected) "$Name retains its boolean"
    } else {
        Assert-MaterialTest ($Actual -eq $Expected) "$Name retains its expected value"
    }
}

function Invoke-MaterialHostingContextWriteTests {
    # Extract only the injectable persistence function. Dot-sourcing the whole
    # native wrapper would run its platform/build guards and is forbidden here.
    $tokens = $null
    $errors = $null
    $wrapperAST = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $RepositoryRoot "scripts/capture-swiftui-material-reference.ps1"), [ref]$tokens, [ref]$errors)
    Assert-MaterialTest ($errors.Count -eq 0) "hosting wrapper syntax parses without native execution"
    $writers = @($wrapperAST.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq "Write-MaterialHostingContextPreservingFailure"
    }, $false))
    Assert-MaterialTest ($writers.Count -eq 1) "extract exactly one context-write test seam"
    . ([scriptblock]::Create($writers[0].Extent.Text))
    $context = [pscustomobject]@{ hostingContextExperiment = [pscustomobject]@{ contextWriteErrors = @() } }
    $primary = $null
    $observed = $null
    $warnings = @()
    try {
        try { throw "Synthetic original native-wrapper failure." } catch { $primary = $_; throw } finally {
            foreach ($stage in @("capture-checkpoint", "final")) {
                $warnings += @(Write-MaterialHostingContextPreservingFailure -PrimaryFailure $primary -Stage $stage -Writer {
                    throw "Synthetic $stage context write failure."
                } 3>&1)
            }
        }
    } catch { $observed = $_ }
    Assert-MaterialTest ([object]::ReferenceEquals($primary.Exception, $observed.Exception)) "both secondary context failures preserve the original exception instance"
    Assert-MaterialTest ($observed.Exception.Message -ceq "Synthetic original native-wrapper failure.") "secondary persistence errors do not replace the original message"
    Assert-MaterialTest ($observed.ScriptStackTrace -ceq $primary.ScriptStackTrace) "rethrow outside the persistence helper preserves the original stack"
    Assert-MaterialTest ($context.hostingContextExperiment.contextWriteErrors.Count -eq 2) "both context-write stages retain separate diagnostics"
    Assert-MaterialTest ($warnings.Count -eq 2) "both secondary context failures emit warnings without throwing"
    for ($index = 0; $index -lt 2; $index++) {
        $stage = @("capture-checkpoint", "final")[$index]
        $message = "Synthetic $stage context write failure."
        Assert-MaterialTest ($primary.Exception.Data["MaterialHostingContextWriteFailure:$stage"] -ceq $message) "$stage secondary failure remains attached to the original exception"
        Assert-MaterialTest ($context.hostingContextExperiment.contextWriteErrors[$index].stage -ceq $stage -and
            $context.hostingContextExperiment.contextWriteErrors[$index].message -ceq $message) "$stage secondary failure remains in wrapper context"
        Assert-MaterialTest ($warnings[$index].Message.Contains($message)) "$stage warning retains its secondary diagnostic"
        Assert-MaterialTestThrows {
            Write-MaterialHostingContextPreservingFailure -PrimaryFailure $null -Stage $stage -Writer {
                throw "Synthetic persistence-only failure."
            }
        } 'Synthetic persistence-only failure' "$stage persistence failure alone is not swallowed"
    }
    $calls = [pscustomobject]@{ count = 0 }
    Write-MaterialHostingContextPreservingFailure -PrimaryFailure $null -Stage "final" -Writer { $calls.count++ }
    Assert-MaterialTest ($calls.count -eq 1) "successful context writer executes exactly once"
    Assert-MaterialTest ($context.hostingContextExperiment.contextWriteErrors.Count -eq 2) "successful context write invents no failure record"
}

function Invoke-MaterialHostingTests {
    Invoke-MaterialHostingContextWriteTests
    Assert-MaterialHostingTestEquivalent (Get-SwiftUIMaterialHostingParameters) (Get-MaterialHostingTestParameters) "hosting parameters"
    Assert-MaterialHostingTestEquivalent @(Get-SwiftUIMaterialHostingSchedule) @(Get-MaterialHostingTestSchedule) "hosting schedule"

    $valid = New-MaterialHostingTestFixture "valid-confirmed"
    $context = Read-MaterialTestSDK $valid
    $result = Read-MaterialHostingTest $valid $context
    Assert-MaterialTest ($result.reportSha256 -ceq (Get-MaterialTestHash $valid.hostingPath)) "hosting result returns the exact sidecar hash"
    Assert-MaterialTest ($result.canonicalManifestSha256 -ceq $valid.originalCanonicalHash) "hosting result links the original manifest bytes"
    Assert-MaterialTest ($result.operationalStatus -ceq "completed") "completed hosting capture remains operationally complete"
    Assert-MaterialTest ($result.canonicalPositiveControlStatus -ceq "backdrop-filtering-observed") "canonical control status is retained separately"
    Assert-MaterialTest ($result.report.startedAtUTC -is [string] -and $result.report.startedAtUTC -ceq "2026-08-27T00:03:00Z") "raw JSON start timestamp remains the exact observed string on both PowerShell versions"
    Assert-MaterialTest ($result.report.attempts[0].setup.timestampUTC -is [string] -and
        $result.report.attempts[0].setup.timestampUTC -ceq "2026-08-27T00:03:00Z") "snapshot timestamps are not implicitly converted to DateTime"
    Assert-MaterialTest ($result.armControlStatuses.Count -eq 2) "hosting result returns exactly two independent control statuses"
    foreach ($arm in $result.armControlStatuses) {
        Assert-MaterialTest ($arm.positiveControlStatus -ceq "backdrop-filtering-observed" -and $arm.inconclusiveReasons.Count -eq 0) "confirmed arm preserves its status without reasons"
    }
    foreach ($field in @("nativeBehaviorReviewed", "nativeRuntimeBuildReviewed", "releaseQualified")) {
        Assert-MaterialTest ($result.report.qualification.$field -eq $false) "passing arm never promotes $field"
    }
    Assert-MaterialTest ((Get-MaterialTestHash $valid.observationPath) -ceq $valid.originalCanonicalHash) "hosting fixture and validation leave canonical bytes unchanged"
    Assert-MaterialTest (@(Get-ChildItem -LiteralPath $valid.observationRoot -Filter '*.png' -File).Count -eq 36) "fixture contains the original twelve and supplementary twenty-four synthetic files"
    $summary = Get-SwiftUIMaterialHostingExperimentContext -Directory $valid.observationRoot
    Assert-MaterialTest ($summary.reportSha256 -ceq $result.reportSha256 -and $summary.operationalStatus -ceq "completed" -and $summary.phase -ceq "finished") "bounded summary retains completed hash and session context"

    foreach ($opaqueArm in @(0, 1)) {
        $fixture = New-MaterialHostingTestFixture "opaque-arm-$opaqueArm"
        Set-MaterialHostingTestOpaqueArm $fixture $opaqueArm
        Publish-MaterialHostingTest $fixture
        $result = Read-MaterialHostingTest $fixture (Read-MaterialTestSDK $fixture)
        $opaque = @($result.armControlStatuses | Where-Object { $_.arm -ceq $fixture.hosting.arms[$opaqueArm].arm })[0]
        $other = @($result.armControlStatuses | Where-Object { $_.arm -cne $fixture.hosting.arms[$opaqueArm].arm })[0]
        Assert-MaterialTest ($opaque.positiveControlStatus -ceq "inconclusive" -and $opaque.inconclusiveReasons.Count -eq 2) "opaque arm is inconclusive with its own repeated reasons"
        Assert-MaterialTest ($other.positiveControlStatus -ceq "backdrop-filtering-observed" -and $other.inconclusiveReasons.Count -eq 0) "opaque arm does not contaminate the other arm"
        Assert-MaterialTest ($result.operationalStatus -ceq "completed") "opaque controls do not become an operational failure"
        Assert-MaterialTest ($result.canonicalPositiveControlStatus -ceq "backdrop-filtering-observed") "arm results do not replace the canonical result"
    }

    $canonicalInconclusive = New-MaterialHostingTestFixture "canonical-inconclusive"
    $canonicalInconclusive.observation.positiveControlStatus = "inconclusive"
    $canonicalInconclusive.observation.inconclusiveReasons = @("Synthetic canonical material remained opaque.")
    foreach ($control in $canonicalInconclusive.observation.controlsByRepetition) {
        $control.status = "inconclusive"; $control.reasons = @("Synthetic canonical material remained opaque.")
    }
    Publish-MaterialTestObservation $canonicalInconclusive
    $canonicalInconclusive.hosting.canonicalManifestSha256 = Get-MaterialTestHash $canonicalInconclusive.observationPath
    $canonicalInconclusive.hosting.canonicalPositiveControlStatus = "inconclusive"
    Publish-MaterialHostingTest $canonicalInconclusive
    $result = Read-MaterialHostingTest $canonicalInconclusive (Read-MaterialTestSDK $canonicalInconclusive)
    Assert-MaterialTest ($result.canonicalPositiveControlStatus -ceq "inconclusive") "two confirmed supplemental arms never promote an inconclusive canonical control"
    Assert-MaterialTest (@($result.armControlStatuses | Where-Object { $_.positiveControlStatus -ceq "backdrop-filtering-observed" }).Count -eq 2) "canonical inconclusive status does not discard completed arm observations"

    $bothOpaque = New-MaterialHostingTestFixture "both-arms-opaque"
    Set-MaterialHostingTestOpaqueArm $bothOpaque 0
    Set-MaterialHostingTestOpaqueArm $bothOpaque 1
    Publish-MaterialHostingTest $bothOpaque
    $result = Read-MaterialHostingTest $bothOpaque (Read-MaterialTestSDK $bothOpaque)
    Assert-MaterialTest ($result.operationalStatus -ceq "completed" -and
        @($result.armControlStatuses | Where-Object { $_.positiveControlStatus -ceq "inconclusive" }).Count -eq 2) "two opaque arms remain completed but inconclusive"

    $unobserved = New-MaterialHostingTestFixture "unobserved-environments"
    foreach ($record in $unobserved.hosting.attempts) {
        foreach ($snapshot in @($record.setup, $record.capture.captureProvenance.before, $record.capture.captureProvenance.after)) {
            $snapshot.swiftUIEnvironment.status = "unobserved"
            $snapshot.swiftUIEnvironment.bodyEvaluationCount = 0
            $snapshot.swiftUIEnvironment.latestBodyEvaluationUTC = $null
            $snapshot.swiftUIEnvironment.values = $null
            # Optional values synthesized by native Encodable may be omitted.
            $snapshot.host.PSObject.Properties.Remove("layerContentsScale")
            if (-not $snapshot.host.hasWindow) { $snapshot.host.PSObject.Properties.Remove("window") }
            else {
                $snapshot.host.window.isMiniaturized = $true
                $snapshot.host.window.occlusionStateVisible = $true
                $snapshot.host.window.backingScaleFactor = 1.25
            }
        }
        $record.capture.captureProvenance.recommendedBitmap.status = "unavailable"
        $record.capture.captureProvenance.recommendedBitmap.bitmap = $null
    }
    Publish-MaterialHostingTest $unobserved
    $result = Read-MaterialHostingTest $unobserved (Read-MaterialTestSDK $unobserved)
    Assert-MaterialTest ($result.operationalStatus -ceq "completed") "explicit unobserved environments and unavailable bitmap recommendations are valid evidence"
    Assert-MaterialTest ($null -eq $result.report.attempts[0].setup.swiftUIEnvironment.values) "unobserved environment is never filled from requested defaults"
    Assert-MaterialTest ($result.report.attempts[1].setup.host.window.backingScaleFactor -eq 1.25) "actual window backing scale need not match the requested bitmap scale"

    $unstableWrapper = New-MaterialHostingTestFixture "unstable-noncontrol-wrapper"
    $unstableWrapper.hosting.attempts[15].capture.measurements.fineContrast = 0.08
    $unstableWrapper.hosting.arms[0].observations[3].repeatedMeasurementsStable = $false
    Publish-MaterialHostingTest $unstableWrapper
    $result = Read-MaterialHostingTest $unstableWrapper (Read-MaterialTestSDK $unstableWrapper)
    Assert-MaterialTest ($result.armControlStatuses[0].positiveControlStatus -ceq "backdrop-filtering-observed") "unstable wrapper does not silently redefine the three positive controls"
    Assert-MaterialTest (-not $result.report.arms[0].observations[3].repeatedMeasurementsStable) "wrapper instability remains visible for later review"

    $unstableControl = New-MaterialHostingTestFixture "unstable-control"
    $unstableControl.hosting.attempts[3].capture.measurements.fineDarkMean = 0.14
    $unstableControl.hosting.arms[0].observations[0].repeatedMeasurementsStable = $false
    $unstableControl.hosting.arms[0].positiveControlStatus = "inconclusive"
    $unstableControl.hosting.arms[0].inconclusiveReasons = @("Control pattern-control did not produce stable repeated measurements.")
    Publish-MaterialHostingTest $unstableControl
    $result = Read-MaterialHostingTest $unstableControl (Read-MaterialTestSDK $unstableControl)
    Assert-MaterialTest ($result.armControlStatuses[0].positiveControlStatus -ceq "inconclusive") "unstable same-arm control makes the arm inconclusive"
    Assert-MaterialTest ($result.armControlStatuses[1].positiveControlStatus -ceq "backdrop-filtering-observed") "control instability does not pool data from the other arm"

    $stabilityBoundary = New-MaterialHostingTestFixture "stability-inclusive-boundary"
    $stabilityBoundary.hosting.attempts[12].capture.measurements.fineContrast = 0.0
    $stabilityBoundary.hosting.attempts[15].capture.measurements.fineContrast = 0.02
    Publish-MaterialHostingTest $stabilityBoundary
    Assert-MaterialTest ($null -ne (Read-MaterialHostingTest $stabilityBoundary (Read-MaterialTestSDK $stabilityBoundary))) "a repeated metric difference exactly at 0.02 remains stable"

    foreach ($status in @("in-progress", "failed")) {
        $fixture = New-MaterialHostingTestFixture "partial-$status"
        Set-MaterialHostingTestPartial $fixture $status
        Publish-MaterialHostingTest $fixture
        $sidecarHash = Get-MaterialTestHash $fixture.hostingPath
        $firstPNGPath = Join-Path $fixture.observationRoot $fixture.hosting.attempts[0].capture.pngFile
        $firstPNGHash = Get-MaterialTestHash $firstPNGPath
        $summary = Get-SwiftUIMaterialHostingExperimentContext -Directory $fixture.observationRoot
        Assert-MaterialTest ($summary.reportSha256 -ceq $sidecarHash -and $summary.operationalStatus -ceq $status) "summary preserves $status checkpoint hash and status"
        Assert-MaterialTest ($summary.phase -ceq $fixture.hosting.session.phase) "summary preserves the actual $status phase"
        Assert-MaterialTest ($summary.armControlStatuses.Count -eq 2 -and
            @($summary.armControlStatuses | Where-Object { $_.positiveControlStatus -ceq "inconclusive" }).Count -eq 2) "partial arm statuses are not promoted"
        if ($status -ceq "failed") {
            Assert-MaterialTest ($summary.report.session.failures.Count -eq 2) "summary preserves both original and restoration failures"
            Assert-MaterialTest ($summary.report.session.failures[0].message -ceq "Synthetic original capture failure.") "restoration does not replace the original failure"
        } else {
            Assert-MaterialTest ($null -eq $summary.report.session.restoration) "interrupted checkpoint does not claim restoration was observed"
        }
        Test-MaterialRejection { Read-MaterialHostingTest $fixture (Read-MaterialTestSDK $fixture) } `
            '(?i)(complete|operational|session|finished|restoration|attempt)' "full validation rejects $status checkpoint"
        Assert-MaterialTest ((Get-MaterialTestHash $fixture.hostingPath) -ceq $sidecarHash -and
            (Get-MaterialTestHash $firstPNGPath) -ceq $firstPNGHash) "summary and rejection preserve partial evidence bytes"
    }

    $cases = @(
        @{ name = "schema-version"; path = "schemaVersion"; value = 2; pattern = '(?i)(schema|version|candidate|supported)' },
        @{ name = "fractional-schema"; path = "schemaVersion"; value = 1.5; pattern = '(?i)(schema|version|integer|candidate|supported)' },
        @{ name = "string-schema"; path = "schemaVersion"; value = "1"; pattern = '(?i)(schema|type|number|integer)' },
        @{ name = "plan-version"; path = "experimentPlanVersion"; value = 2; pattern = '(?i)(plan|version|candidate|supported)' },
        @{ name = "fixture-version"; path = "fixtureVersion"; value = 2; pattern = '(?i)(fixture|version|candidate|supported)' },
        @{ name = "wrong-evidence-kind"; path = "evidenceKind"; value = "native-conformance-proof"; pattern = '(?i)(evidence|candidate|kind)' },
        @{ name = "not-requested"; path = "requested"; value = $false; pattern = '(?i)(requested|candidate|experiment)' },
        @{ name = "string-requested"; path = "requested"; value = "true"; pattern = '(?i)(requested|type|boolean)' },
        @{ name = "window-capture-api"; path = "captureAPI"; value = "window screenshot"; pattern = '(?i)(captureAPI|API|cache|candidate)' },
        @{ name = "canonical-parent-traversal"; path = "canonicalManifestFile"; value = "../manifest.json"; pattern = '(?i)(canonical|manifest|path|file)' },
        @{ name = "canonical-other-file"; path = "canonicalManifestFile"; value = "other.json"; pattern = '(?i)(canonical|manifest|file)' },
        @{ name = "canonical-hash-mismatch"; path = "canonicalManifestSha256"; value = ("3" * 64); pattern = '(?i)(canonical|SHA256|hash|digest)' },
        @{ name = "canonical-promoted-status"; path = "canonicalPositiveControlStatus"; value = "release-qualified"; pattern = '(?i)(canonical|control|status)' },
        @{ name = "wrong-canonical-count"; path = "canonicalCaptureCount"; value = 13; pattern = '(?i)(canonical|count|12|plan)' },
        @{ name = "raw-source-identity"; path = "provenance.sourceCommitAtCapture"; value = ("2" * 40); pattern = '(?i)(source|commit|provenance)' },
        @{ name = "raw-executable-identity"; path = "provenance.executableSHA256"; value = ("2" * 64); pattern = '(?i)(executable|SHA256|provenance)' },
        @{ name = "raw-host-identity"; path = "provenance.osBuild"; value = "OTHEROS"; pattern = '(?i)(OS|runtime|build|provenance)' },
        @{ name = "raw-architecture"; path = "provenance.processArchitecture"; value = "arm64"; pattern = '(?i)(architecture|provenance)' },
        @{ name = "raw-compiler-line"; path = "provenance.swiftAtCapture"; value = "synthetic replacement compiler"; pattern = '(?i)(Swift|compiler|provenance)' },
        @{ name = "raw-optional-image-version"; path = "provenance.ImageVersion"; value = "different-image"; pattern = '(?i)(ImageVersion|provenance|canonical)' },
        @{ name = "raw-optional-run-id"; path = "provenance.GITHUB_RUN_ID"; value = "54321"; pattern = '(?i)(GITHUB_RUN_ID|provenance|canonical)' },
        @{ name = "raw-build-description"; path = "provenance.buildProvenance"; value = "different description"; pattern = '(?i)(buildProvenance|provenance|canonical)' },
        @{ name = "wrong-width"; path = "parameters.logicalWidth"; value = 385; pattern = '(?i)(logicalWidth|parameter|plan|geometry)' },
        @{ name = "wrong-scale"; path = "parameters.requestedScale"; value = 1; pattern = '(?i)(requestedScale|parameter|plan)' },
        @{ name = "wrong-settling"; path = "parameters.settlingMillisecondsBeforeEachCapture"; value = 51; pattern = '(?i)(settling|parameter|plan)' },
        @{ name = "string-settling"; path = "parameters.settlingMillisecondsBeforeEachCapture"; value = "50"; pattern = '(?i)(settling|type|number|parameter)' },
        @{ name = "wrong-panel-origin"; path = "parameters.panel.x"; value = 23; pattern = '(?i)(panel|parameter|plan)' },
        @{ name = "wrong-fine-sample"; path = "parameters.fineSample.width"; value = 193; pattern = '(?i)(fineSample|parameter|plan)' },
        @{ name = "wrong-threshold"; path = "parameters.thresholds.maximumRepeatedMetricDifference"; value = 0.03; pattern = '(?i)(threshold|parameter|plan)' },
        @{ name = "missing-completed-time"; path = "finishedAtUTC"; value = $null; pattern = '(?i)(finished|time|complete)' },
        @{ name = "bad-started-time"; path = "startedAtUTC"; value = "not-a-timestamp"; pattern = '(?i)(started|timestamp|time)' },
        @{ name = "bad-checkpoint-time"; path = "checkpointAtUTC"; value = @(); pattern = '(?i)(checkpoint|timestamp|type|string)' },
        @{ name = "wrong-scheduled-ordinal"; path = "scheduledAttempts.0.ordinal"; value = 2; pattern = '(?i)(schedule|ordinal|plan|attempt)' },
        @{ name = "wrong-scheduled-pair"; path = "scheduledAttempts.0.pairIndex"; value = 2; pattern = '(?i)(schedule|pair|plan|attempt)' },
        @{ name = "wrong-scheduled-position"; path = "scheduledAttempts.0.positionInPair"; value = 2; pattern = '(?i)(schedule|position|plan|attempt)' },
        @{ name = "unknown-scheduled-arm"; path = "scheduledAttempts.0.arm"; value = "regular-visible-window"; pattern = '(?i)(schedule|arm|plan|attempt)' },
        @{ name = "fractional-scheduled-repetition"; path = "scheduledAttempts.0.repetition"; value = 1.5; pattern = '(?i)(schedule|repetition|integer|plan|attempt)' },
        @{ name = "wrong-actual-ordinal"; path = "attempts.0.attempt.ordinal"; value = 2; pattern = '(?i)(ordinal|schedule|attempt)' },
        @{ name = "unknown-actual-fixture"; path = "attempts.0.attempt.fixture"; value = "unknown-fixture"; pattern = '(?i)(fixture|schedule|attempt)' },
        @{ name = "actual-setup-null"; path = "attempts.0.setup"; value = $null; pattern = '(?i)(setup|snapshot|object|attempt)' },
        @{ name = "actual-capture-null"; path = "attempts.0.capture"; value = $null; pattern = '(?i)(capture|object|attempt)' },
        @{ name = "actual-error"; path = "attempts.0.error"; value = "Synthetic attempt failed."; pattern = '(?i)(error|attempt|complete)' },
        @{ name = "actual-protocol-failure"; path = "attempts.0.protocolFailures"; value = @("Synthetic policy observation failed."); pattern = '(?i)(protocol|failure|attempt|complete)' },
        @{ name = "capture-repetition"; path = "attempts.0.capture.repetition"; value = 2; pattern = '(?i)(repetition|capture|attempt)' },
        @{ name = "capture-error"; path = "attempts.0.capture.error"; value = "Synthetic cache failed."; pattern = '(?i)(capture|error|complete)' },
        @{ name = "capture-parent-traversal"; path = "attempts.0.capture.pngFile"; value = "../outside.png"; pattern = '(?i)(png|file|path|capture)' },
        @{ name = "capture-backslash-traversal"; path = "attempts.0.capture.pngFile"; value = '..\outside.png'; pattern = '(?i)(png|file|path|capture)' },
        @{ name = "capture-alternate-stream"; path = "attempts.0.capture.pngFile"; value = 'accessory-unattached-pattern-control-1.png:extra'; pattern = '(?i)(png|file|path|capture)' },
        @{ name = "capture-hash-mismatch"; path = "attempts.0.capture.sha256"; value = ("4" * 64); pattern = '(?i)(SHA256|hash|PNG)' },
        @{ name = "capture-pixel-width"; path = "attempts.0.capture.decodedPNG.pixelWidth"; value = 767; pattern = '(?i)(pixel|width|PNG|dimension)' },
        @{ name = "capture-measured-height"; path = "attempts.0.capture.measurements.pixelHeight"; value = 577; pattern = '(?i)(pixel|height|measurement|dimension)' },
        @{ name = "capture-alpha-type"; path = "attempts.0.capture.decodedPNG.hasAlpha"; value = "true"; pattern = '(?i)(hasAlpha|boolean|type|PNG)' },
        @{ name = "capture-bit-depth"; path = "attempts.0.capture.decodedPNG.bitsPerSample"; value = 16; pattern = '(?i)(bitsPerSample|PNG|format|sample)' },
        @{ name = "capture-metadata-version"; path = "attempts.0.capture.captureProvenance.schemaVersion"; value = 2; pattern = '(?i)(schema|version|provenance)' },
        @{ name = "capture-cache-not-completed"; path = "attempts.0.capture.captureProvenance.cacheDisplayCompleted"; value = $false; pattern = '(?i)(cache|complete|capture)' },
        @{ name = "unattached-owned-window"; path = "attempts.0.cleanup.ownsWindow"; value = $true; pattern = '(?i)(cleanup|window|unattached)' },
        @{ name = "unattached-close-called"; path = "attempts.0.cleanup.closeCalled"; value = $true; pattern = '(?i)(cleanup|close|unattached)' },
        @{ name = "unattached-detach-invented"; path = "attempts.0.cleanup.contentDetached"; value = $true; pattern = '(?i)(cleanup|detach|unattached)' },
        @{ name = "window-not-owned"; path = "attempts.1.cleanup.ownsWindow"; value = $false; pattern = '(?i)(cleanup|window|owns)' },
        @{ name = "window-close-not-called"; path = "attempts.1.cleanup.closeCalled"; value = $false; pattern = '(?i)(cleanup|close|window)' },
        @{ name = "window-not-detached"; path = "attempts.1.cleanup.contentDetached"; value = $false; pattern = '(?i)(cleanup|detach|window)' },
        @{ name = "window-still-attached"; path = "attempts.1.cleanup.hostHasWindowAfterCleanup"; value = $true; pattern = '(?i)(cleanup|window|attach)' },
        @{ name = "window-cleanup-unobserved"; path = "attempts.1.cleanup.windowAfterCleanup"; value = $null; pattern = '(?i)(cleanup|window|object|observed)' },
        @{ name = "window-cleanup-visible"; path = "attempts.1.cleanup.windowAfterCleanup.isVisible"; value = $true; pattern = '(?i)(cleanup|window|visible)' },
        @{ name = "window-cleanup-key"; path = "attempts.1.cleanup.windowAfterCleanup.isKeyWindow"; value = $true; pattern = '(?i)(cleanup|window|key)' },
        @{ name = "window-cleanup-main"; path = "attempts.1.cleanup.windowAfterCleanup.isMainWindow"; value = $true; pattern = '(?i)(cleanup|window|main)' },
        @{ name = "unattached-cleanup-active"; path = "attempts.0.cleanup.applicationAfterCleanup.isActive"; value = $true; pattern = '(?i)(cleanup|active|activity)' },
        @{ name = "unattached-cleanup-wrong-policy"; path = "attempts.0.cleanup.applicationAfterCleanup.activationPolicy"; value = "prohibited"; pattern = '(?i)(cleanup|policy|accessory)' },
        @{ name = "window-cleanup-active"; path = "attempts.1.cleanup.applicationAfterCleanup.isActive"; value = $true; pattern = '(?i)(cleanup|active|activity)' },
        @{ name = "window-cleanup-wrong-policy"; path = "attempts.1.cleanup.applicationAfterCleanup.activationPolicy"; value = "prohibited"; pattern = '(?i)(cleanup|policy|accessory)' },
        @{ name = "cleanup-application-unobserved"; path = "attempts.1.cleanup.applicationAfterCleanup"; value = $null; pattern = '(?i)(cleanup|application|object)' },
        @{ name = "initial-policy"; path = "session.initialApplication.activationPolicy"; value = "accessory"; pattern = '(?i)(session|initial|policy|prohibited)' },
        @{ name = "initial-active"; path = "session.initialApplication.isActive"; value = $true; pattern = '(?i)(session|initial|active)' },
        @{ name = "restoration-not-required"; path = "session.restorationRequired"; value = $false; pattern = '(?i)(restoration|session|complete)' },
        @{ name = "transition-returned-failure"; path = "session.accessoryTransition.returnedSuccess"; value = $false; pattern = '(?i)(accessory|transition|policy|session)' },
        @{ name = "transition-wrong-request"; path = "session.accessoryTransition.requestedPolicy"; value = "regular"; pattern = '(?i)(accessory|transition|policy|session)' },
        @{ name = "transition-not-observed"; path = "session.accessoryTransition.observedApplication.activationPolicy"; value = "prohibited"; pattern = '(?i)(accessory|transition|policy|session)' },
        @{ name = "transition-observed-active"; path = "session.accessoryTransition.observedApplication.isActive"; value = $true; pattern = '(?i)(active|transition|policy|session)' },
        @{ name = "restoration-missing"; path = "session.restoration"; value = $null; pattern = '(?i)(restoration|object|session)' },
        @{ name = "restoration-returned-failure"; path = "session.restoration.returnedSuccess"; value = $false; pattern = '(?i)(restoration|policy|session)' },
        @{ name = "restoration-wrong-request"; path = "session.restoration.requestedPolicy"; value = "accessory"; pattern = '(?i)(restoration|policy|session)' },
        @{ name = "restoration-wrong-observation"; path = "session.restoration.observedApplication.activationPolicy"; value = "accessory"; pattern = '(?i)(restoration|policy|session)' },
        @{ name = "restoration-observed-active"; path = "session.restoration.observedApplication.isActive"; value = $true; pattern = '(?i)(restoration|active|session)' },
        @{ name = "wrong-completed-count"; path = "session.completedAttemptCount"; value = 23; pattern = '(?i)(complete|count|attempt|session)' },
        @{ name = "complete-with-next-ordinal"; path = "session.nextCaptureOrdinal"; value = 24; pattern = '(?i)(nextCaptureOrdinal|attempt|complete|session)' },
        @{ name = "complete-with-extra-failures"; path = "session.additionalFailureCount"; value = 1; pattern = '(?i)(failure|session|complete)' },
        @{ name = "complete-before-finished-phase"; path = "session.phase"; value = "restoration"; pattern = '(?i)(phase|finished|session|complete)' },
        @{ name = "unknown-arm"; path = "arms.0.arm"; value = "unknown-arm"; pattern = '(?i)(arm|schedule)' },
        @{ name = "wrong-modifier-order"; path = "arms.0.observations.3.modifierOrder"; value = "modified public fixture"; pattern = '(?i)(modifier|canonical|fixture)' },
        @{ name = "cross-arm-capture-ordinals"; path = "arms.0.observations.0.captureOrdinals"; value = @(2, 3); pattern = '(?i)(ordinal|arm|capture|reference)' },
        @{ name = "reverse-capture-ordinals"; path = "arms.0.observations.0.captureOrdinals"; value = @(4, 1); pattern = '(?i)(ordinal|repetition|capture|reference)' },
        @{ name = "duplicate-capture-ordinals"; path = "arms.0.observations.0.captureOrdinals"; value = @(1, 1); pattern = '(?i)(ordinal|duplicate|capture|reference)' },
        @{ name = "string-capture-ordinal"; path = "arms.0.observations.0.captureOrdinals"; value = @("1", 4); pattern = '(?i)(ordinal|integer|number|type)' },
        @{ name = "false-stability-with-identical-measurements"; path = "arms.0.observations.0.repeatedMeasurementsStable"; value = $false; pattern = '(?i)(stable|stability|repeated|measurement)' },
        @{ name = "array-stability"; path = "arms.0.observations.0.repeatedMeasurementsStable"; value = @(); pattern = '(?i)(stable|boolean|type)' },
        @{ name = "unknown-control-status"; path = "arms.0.controlsByRepetition.0.status"; value = "native-qualified"; pattern = '(?i)(control|status|classification)' },
        @{ name = "confirmed-control-with-reason"; path = "arms.0.controlsByRepetition.0.reasons"; value = @("Unexpected reason."); pattern = '(?i)(control|reason|classification|inconsistent)' },
        @{ name = "control-reason-type"; path = "arms.0.controlsByRepetition.0.reasons"; value = @(42); pattern = '(?i)(control|reason|string|type)' },
        @{ name = "negative-frequency-ratio"; path = "arms.0.controlsByRepetition.0.materialRelativeFrequencyRatio"; value = -0.1; pattern = '(?i)(ratio|range|finite|control)' },
        @{ name = "invalid-lift-range"; path = "arms.0.controlsByRepetition.0.flatTintDarkMeanLift"; value = 1.1; pattern = '(?i)(lift|range|finite|control)' },
        @{ name = "array-frequency-ratio"; path = "arms.0.controlsByRepetition.0.materialToTintFrequencyRatio"; value = @(); pattern = '(?i)(ratio|number|type|control)' },
        @{ name = "inconclusive-without-any-reason"; path = "arms.0.positiveControlStatus"; value = "inconclusive"; pattern = '(?i)(inconclusive|control|status|reason|inconsistent)' }
    )
    foreach ($field in @("nativeBehaviorReviewed", "nativeRuntimeBuildReviewed", "releaseQualified")) {
        $cases += @{ name = "qualification-$field"; path = "qualification.$field"; value = $true; pattern = '(?i)(qualification|review|candidate)' }
    }
    foreach ($field in @("flatTintRelativeFrequencyRatio", "flatTintCoarseRetention", "flatTintDarkMeanLift",
            "materialRelativeFrequencyRatio", "materialToTintFrequencyRatio", "materialCoarseRetention")) {
        $cases += @{ name = "confirmed-control-missing-$field"; path = "arms.0.controlsByRepetition.0.$field"; value = $null; pattern = '(?i)(confirmed|control|missing|measured)' }
    }
    foreach ($location in @("setup", "capture.captureProvenance.before", "capture.captureProvenance.after")) {
        $locationName = $location.Replace('.', '-')
        $prefix = "attempts.0.$location"
        $windowPrefix = "attempts.1.$location"
        $cases += @(
            @{ name = "$locationName-policy"; path = "$prefix.application.activationPolicy"; value = "prohibited"; pattern = '(?i)(snapshot|application|policy|accessory)' },
            @{ name = "$locationName-active"; path = "$prefix.application.isActive"; value = $true; pattern = '(?i)(snapshot|application|active)' },
            @{ name = "$locationName-active-type"; path = "$prefix.application.isActive"; value = "false"; pattern = '(?i)(isActive|boolean|type)' },
            @{ name = "$locationName-unattached-window"; path = "$prefix.host.hasWindow"; value = $true; pattern = '(?i)(unattached|window|host)' },
            @{ name = "$locationName-unattached-superview"; path = "$prefix.host.hasSuperview"; value = $true; pattern = '(?i)(unattached|superview|host)' },
            @{ name = "$locationName-window-attachment-missing"; path = "$windowPrefix.host.hasWindow"; value = $false; pattern = '(?i)(window|attach|host)' },
            @{ name = "$locationName-window-record-missing"; path = "$windowPrefix.host.window"; value = $null; pattern = '(?i)(window|object|host)' },
            @{ name = "$locationName-visible-window"; path = "$windowPrefix.host.window.isVisible"; value = $true; pattern = '(?i)(window|visible|host)' },
            @{ name = "$locationName-key-window"; path = "$windowPrefix.host.window.isKeyWindow"; value = $true; pattern = '(?i)(window|key|host)' },
            @{ name = "$locationName-main-window"; path = "$windowPrefix.host.window.isMainWindow"; value = $true; pattern = '(?i)(window|main|host)' },
            @{ name = "$locationName-zero-backing-scale"; path = "$windowPrefix.host.window.backingScaleFactor"; value = 0; pattern = '(?i)(backing|scale|positive|window)' },
            @{ name = "$locationName-frame-origin"; path = "$prefix.host.frame.x"; value = 1; pattern = '(?i)(frame|geometry|rectangle|host)' },
            @{ name = "$locationName-bounds-size"; path = "$prefix.host.bounds.height"; value = 287; pattern = '(?i)(bounds|geometry|rectangle|host)' },
            @{ name = "$locationName-flipped"; path = "$prefix.host.isFlipped"; value = $false; pattern = '(?i)(flipped|orientation|host)' },
            @{ name = "$locationName-appearance"; path = "$prefix.host.effectiveAppearance"; value = "NSAppearanceNameDarkAqua"; pattern = '(?i)(appearance|Aqua|host)' },
            @{ name = "$locationName-environment-scale"; path = "$prefix.swiftUIEnvironment.values.displayScale"; value = 1; pattern = '(?i)(environment|displayScale|scale)' },
            @{ name = "$locationName-environment-color-scheme"; path = "$prefix.swiftUIEnvironment.values.colorScheme"; value = "dark"; pattern = '(?i)(environment|colorScheme|light)' },
            @{ name = "$locationName-environment-body-count"; path = "$prefix.swiftUIEnvironment.bodyEvaluationCount"; value = 0; pattern = '(?i)(environment|body|count|observed)' },
            @{ name = "$locationName-environment-values-null"; path = "$prefix.swiftUIEnvironment.values"; value = $null; pattern = '(?i)(environment|values|object|observed)' },
            @{ name = "$locationName-accessibility-type"; path = "$prefix.systemAccessibility.reduceTransparency"; value = @(); pattern = '(?i)(accessibility|reduceTransparency|boolean|type)' }
        )
    }
    foreach ($metric in @("fineContrast", "fineDarkMean", "fineLightMean", "coarseContrast", "darkMean", "lightMean", "minimumSampleAlpha")) {
        $cases += @(
            @{ name = "metric-negative-$metric"; path = "attempts.0.capture.measurements.$metric"; value = -0.01; pattern = '(?i)(measurement|range|finite|contrast|mean|alpha)' },
            @{ name = "metric-too-large-$metric"; path = "attempts.0.capture.measurements.$metric"; value = 1.01; pattern = '(?i)(measurement|range|finite|contrast|mean|alpha)' },
            @{ name = "metric-null-$metric"; path = "attempts.0.capture.measurements.$metric"; value = $null; pattern = '(?i)(measurement|number|type|finite)' }
        )
        $changedValue = 0.14
        switch ($metric) {
            "fineContrast" { $changedValue = 0.84 }
            "fineLightMean" { $changedValue = 0.94 }
            "coarseContrast" { $changedValue = 0.84 }
            "lightMean" { $changedValue = 0.94 }
            "minimumSampleAlpha" { $changedValue = 0.96 }
        }
        $cases += @{ name = "false-stability-claim-$metric"; path = "attempts.3.capture.measurements.$metric"; value = $changedValue; pattern = '(?i)(stable|stability|repeated|measurement)' }
    }
    foreach ($case in $cases) {
        $fixture = New-MaterialHostingTestFixture $case.name
        $context = Read-MaterialTestSDK $fixture
        Set-MaterialHostingTestValue $fixture $case.path $case.value
        Publish-MaterialHostingTest $fixture
        Test-MaterialRejection { Read-MaterialHostingTest $fixture $context } $case.pattern "hosting $($case.name)"
    }

    $changeCases = @(
        @{ name = "extra-qualification-field"; pattern = '(?i)(qualification|field|plan)'; change = {
            param($f) $f.hosting.qualification | Add-Member -NotePropertyName syntheticExtra -NotePropertyValue $false
        } },
        @{ name = "missing-qualification-field"; pattern = '(?i)(qualification|field|plan)'; change = {
            param($f) $f.hosting.qualification.PSObject.Properties.Remove("nativeRuntimeBuildReviewed")
        } },
        @{ name = "unknown-provenance-field"; pattern = '(?i)(provenance|field|canonical)'; change = {
            param($f) $f.hosting.provenance | Add-Member -NotePropertyName syntheticExtra -NotePropertyValue "unrecorded"
        } },
        @{ name = "missing-optional-provenance-field"; pattern = '(?i)(provenance|field|canonical)'; change = {
            param($f) $f.hosting.provenance.PSObject.Properties.Remove("GITHUB_RUN_ATTEMPT")
        } },
        @{ name = "extra-parameter"; pattern = '(?i)(parameter|field|plan)'; change = {
            param($f) $f.hosting.parameters | Add-Member -NotePropertyName adaptiveSettling -NotePropertyValue $true
        } },
        @{ name = "missing-parameter"; pattern = '(?i)(parameter|field|plan)'; change = {
            param($f) $f.hosting.parameters.PSObject.Properties.Remove("settlingMillisecondsBeforeEachCapture")
        } },
        @{ name = "extra-threshold"; pattern = '(?i)(threshold|parameter|field|plan)'; change = {
            param($f) $f.hosting.parameters.thresholds | Add-Member -NotePropertyName moreLenientThreshold -NotePropertyValue 1
        } },
        @{ name = "canonical-parameter-mismatch"; pattern = '(?i)(canonical|parameter|threshold|plan)'; change = {
            param($f)
            $f.observation.thresholds.materialMaximumRelativeFrequencyRatio = 0.5
            Publish-MaterialTestObservation $f
            $f.hosting.canonicalManifestSha256 = Get-MaterialTestHash $f.observationPath
        } },
        @{ name = "canonical-manifest-byte-tamper"; pattern = '(?i)(canonical|manifest|digest|hash)'; change = {
            param($f) [System.IO.File]::AppendAllText($f.observationPath, " ", $script:MaterialTestUTF8)
        } },
        @{ name = "missing-scheduled-attempt"; pattern = '(?i)(schedule|attempt|count|shape)'; change = {
            param($f) $f.hosting.scheduledAttempts = @($f.hosting.scheduledAttempts | Select-Object -First 23)
        } },
        @{ name = "duplicate-scheduled-attempt"; pattern = '(?i)(schedule|attempt|ordinal|plan)'; change = {
            param($f) $f.hosting.scheduledAttempts[1] = Copy-MaterialTestObject $f.hosting.scheduledAttempts[0]
        } },
        @{ name = "swapped-counterbalanced-order"; pattern = '(?i)(schedule|attempt|plan)'; change = {
            param($f)
            $first = $f.hosting.scheduledAttempts[0]
            $f.hosting.scheduledAttempts[0] = $f.hosting.scheduledAttempts[1]
            $f.hosting.scheduledAttempts[1] = $first
        } },
        @{ name = "extra-scheduled-field"; pattern = '(?i)(schedule|attempt|field|plan)'; change = {
            param($f) $f.hosting.scheduledAttempts[0] | Add-Member -NotePropertyName adaptedAfterControl -NotePropertyValue $true
        } },
        @{ name = "missing-actual-attempt"; pattern = '(?i)(complete|attempt|24)'; change = {
            param($f) $f.hosting.attempts = @($f.hosting.attempts | Select-Object -First 23)
        } },
        @{ name = "extra-actual-attempt"; pattern = '(?i)(complete|attempt|24)'; change = {
            param($f) $f.hosting.attempts += @(Copy-MaterialTestObject $f.hosting.attempts[23])
        } },
        @{ name = "duplicate-actual-attempt"; pattern = '(?i)(attempt|schedule|ordinal)'; change = {
            param($f) $f.hosting.attempts[1] = Copy-MaterialTestObject $f.hosting.attempts[0]
        } },
        @{ name = "missing-explicit-attempt-error"; pattern = '(?i)(error|missing|field|attempt)'; change = {
            param($f) $f.hosting.attempts[0].PSObject.Properties.Remove("error")
        } },
        @{ name = "cross-arm-png-with-matching-hash"; pattern = '(?i)(png|filename|capture|attempt)'; change = {
            param($f)
            $f.hosting.attempts[0].capture.pngFile = $f.hosting.attempts[1].capture.pngFile
            $f.hosting.attempts[0].capture.sha256 = $f.hosting.attempts[1].capture.sha256
        } },
        @{ name = "canonical-png-reused-as-supplement"; pattern = '(?i)(png|filename|capture|attempt)'; change = {
            param($f)
            $f.hosting.attempts[0].capture.pngFile = $f.observation.observations[0].captures[0].pngFile
            $f.hosting.attempts[0].capture.sha256 = $f.observation.observations[0].captures[0].sha256
        } },
        @{ name = "absolute-png"; pattern = '(?i)(png|filename|path|capture)'; change = {
            param($f) $f.hosting.attempts[0].capture.pngFile = Join-Path $f.directory "outside.png"
        } },
        @{ name = "png-bytes-tampered"; pattern = '(?i)(SHA256|hash|PNG)'; change = {
            param($f) Write-MaterialTestText (Join-Path $f.observationRoot $f.hosting.attempts[0].capture.pngFile) "TAMPERED SYNTHETIC HOSTING BYTES"
        } },
        @{ name = "png-missing"; pattern = '(?i)(file|missing|exist|PNG)'; change = {
            param($f) Remove-Item -LiteralPath (Join-Path $f.observationRoot $f.hosting.attempts[0].capture.pngFile)
        } },
        @{ name = "png-is-directory"; pattern = '(?i)(regular|file|directory|flat|PNG)'; change = {
            param($f)
            $pngPath = Join-Path $f.observationRoot $f.hosting.attempts[0].capture.pngFile
            Remove-Item -LiteralPath $pngPath
            [void][System.IO.Directory]::CreateDirectory($pngPath)
        } },
        @{ name = "nested-evidence"; pattern = '(?i)(regular|directory|flat|nested)'; change = {
            param($f) [void][System.IO.Directory]::CreateDirectory((Join-Path $f.observationRoot "nested-evidence"))
        } },
        @{ name = "unplanned-png-evidence"; pattern = '(?i)(exact|canonical|file|scheduled|PNG)'; change = {
            param($f) Write-MaterialTestText (Join-Path $f.observationRoot "unplanned-extra.png") "SYNTHETIC UNPLANNED NON-IMAGE PAYLOAD"
        } },
        @{ name = "unattached-window-record"; pattern = '(?i)(unattached|window|host)'; change = {
            param($f) $f.hosting.attempts[0].setup.host.window = New-MaterialHostingTestWindow
        } },
        @{ name = "unobserved-environment-fabricated"; pattern = '(?i)(environment|unobserved|fabricat)'; change = {
            param($f)
            $environment = $f.hosting.attempts[0].setup.swiftUIEnvironment
            $environment.status = "unobserved"; $environment.bodyEvaluationCount = 0; $environment.latestBodyEvaluationUTC = $null
        } },
        @{ name = "unobserved-environment-missing-explicit-values"; pattern = '(?i)(environment|values|missing|field)'; change = {
            param($f)
            $environment = $f.hosting.attempts[0].setup.swiftUIEnvironment
            $environment.status = "unobserved"; $environment.bodyEvaluationCount = 0; $environment.latestBodyEvaluationUTC = $null
            $environment.PSObject.Properties.Remove("values")
        } },
        @{ name = "missing-explicit-cleanup-null"; pattern = '(?i)(cleanup|windowAfterCleanup|missing|field)'; change = {
            param($f) $f.hosting.attempts[0].cleanup.PSObject.Properties.Remove("windowAfterCleanup")
        } },
        @{ name = "complete-with-recorded-failure"; pattern = '(?i)(complete|failed|session)'; change = {
            param($f) $f.hosting.session.failures = @([pscustomobject]@{ stage = "capture"; message = "Synthetic failure."; captureOrdinal = 1 })
        } },
        @{ name = "missing-arm"; pattern = '(?i)(both|arm|two|count)'; change = {
            param($f) $f.hosting.arms = @($f.hosting.arms[0])
        } },
        @{ name = "duplicate-arm"; pattern = '(?i)(arm|control|unknown)'; change = {
            param($f) $f.hosting.arms[1] = Copy-MaterialTestObject $f.hosting.arms[0]
        } },
        @{ name = "swapped-arm-reports"; pattern = '(?i)(arm|control|unknown)'; change = {
            param($f) $f.hosting.arms = @($f.hosting.arms[1], $f.hosting.arms[0])
        } },
        @{ name = "missing-observation"; pattern = '(?i)(six|observation|count)'; change = {
            param($f) $f.hosting.arms[0].observations = @($f.hosting.arms[0].observations | Select-Object -First 5)
        } },
        @{ name = "duplicate-observation"; pattern = '(?i)(fixture|observation|order)'; change = {
            param($f) $f.hosting.arms[0].observations[1] = Copy-MaterialTestObject $f.hosting.arms[0].observations[0]
        } },
        @{ name = "missing-control-repetition"; pattern = '(?i)(two|control|repetition|count)'; change = {
            param($f) $f.hosting.arms[0].controlsByRepetition = @($f.hosting.arms[0].controlsByRepetition[0])
        } },
        @{ name = "inconclusive-control-without-reason"; pattern = '(?i)(control|reason|inconsistent)'; change = {
            param($f)
            $f.hosting.arms[0].controlsByRepetition[0].status = "inconclusive"
            $f.hosting.arms[0].positiveControlStatus = "inconclusive"
        } },
        @{ name = "wrong-repeated-reason-prefix"; pattern = '(?i)(inconclusiveReasons|reason|provenance|plan)'; change = {
            param($f)
            Set-MaterialHostingTestOpaqueArm $f 0
            $f.hosting.arms[0].inconclusiveReasons[0] = "Repetition 2: wrong ordinal"
        } },
        @{ name = "missing-repeated-reason"; pattern = '(?i)(inconclusiveReasons|reason|count|shape)'; change = {
            param($f)
            Set-MaterialHostingTestOpaqueArm $f 0
            $f.hosting.arms[0].inconclusiveReasons = @($f.hosting.arms[0].inconclusiveReasons[0])
        } },
        @{ name = "cross-arm-control-reasons"; pattern = '(?i)(inconclusiveReasons|reason|status|control)'; change = {
            param($f)
            Set-MaterialHostingTestOpaqueArm $f 0
            $f.hosting.arms[1].inconclusiveReasons = @($f.hosting.arms[0].inconclusiveReasons)
        } },
        @{ name = "opaque-control-promoted"; pattern = '(?i)(control|status|inconsistent)'; change = {
            param($f)
            Set-MaterialHostingTestOpaqueArm $f 0
            $f.hosting.arms[0].positiveControlStatus = "backdrop-filtering-observed"
        } },
        @{ name = "invented-arm-inconclusive-reason"; pattern = '(?i)(inconclusiveReasons|reason|status|control|count|shape)'; change = {
            param($f) $f.hosting.arms[0].inconclusiveReasons = @("Unrelated to either same-arm control.")
        } }
    )
    foreach ($case in $changeCases) {
        $fixture = New-MaterialHostingTestFixture $case.name
        $context = Read-MaterialTestSDK $fixture
        & $case.change $fixture | Out-Null
        Publish-MaterialHostingTest $fixture
        Test-MaterialRejection { Read-MaterialHostingTest $fixture $context } $case.pattern "hosting $($case.name)"
    }

    $rawCases = @(
        @{ name = "malformed-json"; pattern = '(?i)(JSON|malformed|invalid|unexpected|structure)'; change = {
            param($text) return ($text + "not JSON")
        } },
        @{ name = "singleton-array-root"; pattern = '(?i)(root|JSON.*object)'; change = {
            param($text) return ("[" + $text + "]")
        } },
        @{ name = "duplicate-root-key"; pattern = '(?i)(duplicate|collid|collision)'; change = {
            param($text) return [regex]::Replace($text, '"schemaVersion"\s*:\s*1(?=\s*[,}])', '"schemaVersion": 1, "schemaVersion": 1')
        } },
        @{ name = "case-colliding-root-key"; pattern = '(?i)(duplicate|collid|collision)'; change = {
            param($text) return [regex]::Replace($text, '"schemaVersion"\s*:\s*1(?=\s*[,}])', '"schemaVersion": 1, "SchemaVersion": 1')
        } },
        @{ name = "escaped-duplicate-key"; pattern = '(?i)(duplicate|collid|collision)'; change = {
            param($text) return [regex]::Replace($text, '"schemaVersion"\s*:\s*1(?=\s*[,}])', '"schemaVersion": 1, "schema\u0056ersion": 1')
        } },
        @{ name = "nested-duplicate-key"; pattern = '(?i)(duplicate|collid|collision)'; change = {
            param($text) return [regex]::Replace($text, '"isVisible"\s*:\s*false', '"isVisible": false, "isVisible": false')
        } },
        @{ name = "oversized-sidecar"; pattern = '(?i)(limit|bytes|size|bounded|exceeds)'; change = {
            param($text) return ('{"syntheticPadding":"' + ("x" * 1048577) + '"}')
        } },
        @{ name = "deep-sidecar"; pattern = '(?i)(depth|nest|bounded)'; change = {
            param($text) return ('{"syntheticNested":' + ('{"x":' * 40) + '0' + ('}' * 40) + '}')
        } },
        @{ name = "many-token-sidecar"; pattern = '(?i)(token|node|limit|bounded)'; change = {
            param($text) return ('{"syntheticNodes":[' + ('0,' * 55000) + '0]}')
        } },
        @{ name = "nonfinite-measurement"; summary = $false; pattern = '(?i)(finite|number|measurement|JSON)'; change = {
            param($text) return [regex]::Replace($text, '"fineContrast"\s*:\s*0\.8(?=\s*[,}])', '"fineContrast": 1e309')
        } }
    )
    foreach ($case in $rawCases) {
        $fixture = New-MaterialHostingTestFixture $case.name
        $context = Read-MaterialTestSDK $fixture
        $originalText = [System.IO.File]::ReadAllText($fixture.hostingPath)
        $changedText = & $case.change $originalText
        Assert-MaterialTest ($changedText -cne $originalText) "raw hosting mutation $($case.name) changed the serialized bytes"
        Write-MaterialTestText $fixture.hostingPath $changedText
        if (-not $case.ContainsKey("summary") -or $case.summary) {
            Test-MaterialRejection { Get-SwiftUIMaterialHostingExperimentContext -Directory $fixture.observationRoot } `
                $case.pattern "hosting summary rejects $($case.name)"
        }
        Test-MaterialRejection { Read-MaterialHostingTest $fixture $context } $case.pattern "hosting full validation rejects $($case.name)"
    }
    $invalidUTF8 = New-MaterialHostingTestFixture "invalid-utf8"
    [System.IO.File]::WriteAllBytes($invalidUTF8.hostingPath, [byte[]](0x7B, 0x22, 0x78, 0x22, 0x3A, 0x22, 0xC3, 0x28, 0x22, 0x7D))
    Test-MaterialRejection { Get-SwiftUIMaterialHostingExperimentContext -Directory $invalidUTF8.observationRoot } `
        '(?i)(UTF|byte|decode|convert|fallback)' "hosting summary rejects invalid UTF-8 before parsing"

    $missingReport = New-MaterialHostingTestFixture "missing-sidecar"
    Remove-Item -LiteralPath $missingReport.hostingPath
    Test-MaterialRejection { Get-SwiftUIMaterialHostingExperimentContext -Directory $missingReport.observationRoot } `
        '(?i)(missing|file|exist|path|find)' "missing hosting sidecar is not fabricated"
    $directoryReport = New-MaterialHostingTestFixture "directory-sidecar"
    Remove-Item -LiteralPath $directoryReport.hostingPath
    [void][System.IO.Directory]::CreateDirectory($directoryReport.hostingPath)
    Test-MaterialRejection { Get-SwiftUIMaterialHostingExperimentContext -Directory $directoryReport.observationRoot } `
        '(?i)(regular|file|directory)' "hosting sidecar must be a regular file"

    if ([System.IO.Path]::DirectorySeparatorChar -eq '/') {
        $linkedReport = New-MaterialHostingTestFixture "linked-sidecar"
        $outsideReport = Join-Path $linkedReport.directory "outside-hosting-experiment.json"
        Copy-Item -LiteralPath $linkedReport.hostingPath -Destination $outsideReport
        Remove-Item -LiteralPath $linkedReport.hostingPath
        [void][System.IO.File]::CreateSymbolicLink($linkedReport.hostingPath, $outsideReport)
        Test-MaterialRejection { Get-SwiftUIMaterialHostingExperimentContext -Directory $linkedReport.observationRoot } `
            '(?i)(regular|link|outside|contain)' "hosting sidecar link is rejected even when its target is valid synthetic evidence"
    }
}

$materialTestPrimaryFailure = $null
try {
    foreach ($name in @("swiftui-material-reference-common.ps1", "test-swiftui-material-reference.ps1")) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepositoryRoot "scripts/$name"), [ref]$tokens, [ref]$errors)
        Assert-MaterialTest ($errors.Count -eq 0) "PowerShell syntax in $name"
    }
    $primaryFixtureError = $null
    $observedFixtureError = $null
    $cleanupWarnings = @()
    try {
        try { throw "synthetic primary fixture failure" } catch { $primaryFixtureError = $_; throw } finally {
            $cleanupWarnings = @(Invoke-MaterialTestCleanup -OriginalFailure $primaryFixtureError -Cleanup {
                throw "synthetic secondary cleanup failure"
            } 3>&1)
        }
    } catch { $observedFixtureError = $_ }
    Assert-MaterialTest ([object]::ReferenceEquals($primaryFixtureError.Exception, $observedFixtureError.Exception)) "cleanup preserves the original fixture exception"
    Assert-MaterialTest ($observedFixtureError.ScriptStackTrace -ceq $primaryFixtureError.ScriptStackTrace) "cleanup preserves the original fixture stack"
    Assert-MaterialTest ($observedFixtureError.Exception.Message -ceq "synthetic primary fixture failure") "cleanup does not replace the original message"
    Assert-MaterialTest ($observedFixtureError.Exception.Data["MaterialFixtureCleanupFailure"] -ceq "synthetic secondary cleanup failure") "secondary cleanup diagnostics remain attached"
    Assert-MaterialTest ($cleanupWarnings.Count -eq 1 -and $cleanupWarnings[0].Message -match 'synthetic secondary cleanup failure') "secondary cleanup failure is reported separately"
    Assert-MaterialTestThrows { Invoke-MaterialTestCleanup -Cleanup { throw "synthetic cleanup-only failure" } } `
        'synthetic cleanup-only failure' "cleanup failure alone still fails the suite"

    if ([System.IO.Path]::DirectorySeparatorChar -eq '/') {
        # Exercise actual Unix relative symlinks, including a missing suffix,
        # using only this invocation's owned temporary directory.
        $relativeAliasRoot = Join-Path $script:MaterialTestRoot "relative-symlink"
        $relativeAliasTarget = Join-Path $relativeAliasRoot "target"
        [void][System.IO.Directory]::CreateDirectory($relativeAliasTarget)
        $relativeAlias = Join-Path $relativeAliasRoot "alias"
        [void][System.IO.Directory]::CreateSymbolicLink($relativeAlias, "target")
        $resolvedTarget = Resolve-SwiftUIBaselineFileSystemPath -Path $relativeAliasTarget
        Assert-MaterialTest ((Resolve-SwiftUIBaselineFileSystemPath -Path $relativeAlias) -ceq $resolvedTarget) "Unix relative symlink resolves from its filesystem parent"
        $absentSuffix = "missing-" + [Guid]::NewGuid().ToString("N")
        Assert-MaterialTest ((Resolve-SwiftUIBaselineFileSystemPath -Path (Join-Path $relativeAlias $absentSuffix)) -ceq (Join-Path $resolvedTarget $absentSuffix)) "Unix relative symlink retains a nonexistent suffix"
        if ($IsMacOS) {
            # Read the OS aliases without creating or deleting anything there.
            # Split-Path's Unix drive-qualifier handling used to lose this root.
            Assert-MaterialTest ((Resolve-SwiftUIBaselineFileSystemPath -Path "/var") -ceq (Resolve-SwiftUIBaselineFileSystemPath -Path "/private/var")) "macOS root-level /var alias resolves canonically"
            $resolvedTempForTest = Resolve-SwiftUIBaselineFileSystemPath -Path $materialTestTemp
            Assert-MaterialTest ((Resolve-SwiftUIBaselineFileSystemPath -Path (Join-Path $materialTestTemp $absentSuffix)) -ceq (Join-Path $resolvedTempForTest $absentSuffix)) "macOS temporary-directory aliases retain a nonexistent UUID suffix"
        }
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

    # Reuse the observed spelling only as synthetic test data. Every tool, SDK,
    # renderer, and PNG remains a labelled fixture; these are not native results.
    $syntheticReleaseCompiler = "Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)"
    $syntheticDriverPrefix = "swift-driver version: 1.148.6 "
    $syntheticRawReceipt = "$syntheticDriverPrefix$syntheticReleaseCompiler`nTarget: x86_64-apple-macosx26.0"
    $prefixed = New-MaterialTestFixture "valid-driver-prefixed-receipt" -CompilerVersionLine $syntheticReleaseCompiler
    $prefixedSDK = Read-MaterialTestSDK $prefixed
    Assert-MaterialTest ($prefixedSDK.capture.observedIdentity.swiftCompilerVersion -ceq "6.3.3" -and
        $prefixedSDK.capture.observedIdentity.swiftCompilerVersionLine -ceq $syntheticReleaseCompiler) "the SDK fixture has the complete canonical compiler identity"
    $prefixed.observation.provenance.swiftAtCapture = $syntheticRawReceipt
    Publish-MaterialTestObservation $prefixed
    $prefixedCaptureHash = Get-MaterialTestHash $prefixed.capturePath
    $prefixedObservationHash = Get-MaterialTestHash $prefixed.observationPath
    $prefixedResult = Read-MaterialTestObservation $prefixed $prefixedSDK
    Assert-MaterialTest ($prefixedResult.manifest.provenance.swiftAtCapture -ceq $syntheticRawReceipt) "normalizing compiler identity preserves the complete raw driver receipt and Target line"
    Assert-MaterialTest ($prefixedResult.manifestSha256 -ceq $prefixedObservationHash -and
        (Get-MaterialTestHash $prefixed.observationPath) -ceq $prefixedObservationHash) "normalizing compiler identity neither rewrites nor reseals the material manifest"
    Assert-MaterialTest ($prefixedResult.positiveControlStatus -ceq "backdrop-filtering-observed") "recognized driver prefix does not change the synthetic control classification"
    Assert-MaterialTest ($prefixedResult.manifest.qualification -ceq $prefixed.observation.qualification -and
        $prefixedResult.manifest.groupBehaviorReview -ceq $prefixed.observation.groupBehaviorReview -and
        -not $prefixedSDK.exactIdentityPreviouslyReviewed) "matching compiler text does not review or qualify synthetic evidence"

    $prefixed.observation.positiveControlStatus = "inconclusive"
    $prefixed.observation.inconclusiveReasons = @(
        "Synthetic prefixed receipt: ordinary material did not retain enough coarse variation.",
        "Synthetic prefixed receipt: ordinary material did not selectively attenuate the fine pattern."
    )
    foreach ($control in $prefixed.observation.controlsByRepetition) {
        $control.status = "inconclusive"
        $control.reasons = @($prefixed.observation.inconclusiveReasons)
    }
    Publish-MaterialTestObservation $prefixed
    $prefixedInconclusiveHash = Get-MaterialTestHash $prefixed.observationPath
    $prefixedInconclusive = Read-MaterialTestObservation $prefixed $prefixedSDK
    Assert-MaterialTest ($prefixedInconclusive.positiveControlStatus -ceq "inconclusive" -and
        $prefixedInconclusive.manifest.qualification -ceq $prefixed.observation.qualification -and
        $prefixedInconclusive.manifest.groupBehaviorReview -ceq $prefixed.observation.groupBehaviorReview) "recognized driver prefix leaves inconclusive observations unreviewed and unqualified"
    Assert-MaterialTest ($prefixedInconclusive.manifest.provenance.swiftAtCapture -ceq $syntheticRawReceipt -and
        $prefixedInconclusive.manifestSha256 -ceq $prefixedInconclusiveHash -and
        (Get-MaterialTestHash $prefixed.observationPath) -ceq $prefixedInconclusiveHash) "inconclusive validation preserves the raw receipt and exact manifest bytes"
    Assert-MaterialTest ($prefixedInconclusive.manifest.inconclusiveReasons.Count -eq 2) "all inconclusive reasons survive prefix normalization"
    for ($reasonIndex = 0; $reasonIndex -lt 2; $reasonIndex++) {
        $expectedReason = $prefixed.observation.inconclusiveReasons[$reasonIndex]
        Assert-MaterialTest ($prefixedInconclusive.manifest.inconclusiveReasons[$reasonIndex] -ceq $expectedReason) "preserve inconclusive reason $reasonIndex verbatim"
        foreach ($control in $prefixedInconclusive.manifest.controlsByRepetition) {
            Assert-MaterialTest ($control.status -ceq "inconclusive" -and $control.reasons.Count -eq 2 -and
                $control.reasons[$reasonIndex] -ceq $expectedReason) "preserve each repetition's inconclusive reason $reasonIndex verbatim"
        }
    }
    Assert-MaterialTest ((Get-MaterialTestHash $prefixed.capturePath) -ceq $prefixedCaptureHash) "material receipt normalization leaves the captured SDK identity and seal unchanged"

    foreach ($case in @(
            @{ name = "prefixed-compiler-patch"; compiler = $syntheticReleaseCompiler.Replace("version 6.3.3 ", "version 6.3.4 ") },
            @{ name = "prefixed-swiftlang-build"; compiler = $syntheticReleaseCompiler.Replace("swiftlang-6.3.3.1.3", "swiftlang-6.3.3.1.4") },
            @{ name = "prefixed-clang-build"; compiler = $syntheticReleaseCompiler.Replace("clang-2100.1.1.101", "clang-2100.1.1.102") })) {
        $fixture = New-MaterialTestFixture $case.name -CompilerVersionLine $syntheticReleaseCompiler
        $context = Read-MaterialTestSDK $fixture
        $fixture.observation.provenance.swiftAtCapture = $syntheticDriverPrefix + $case.compiler + "`nTarget: x86_64-apple-macosx26.0"
        Publish-MaterialTestObservation $fixture
        Test-MaterialRejection { Read-MaterialTestObservation $fixture $context } `
            'Material swiftCompilerVersionLine disagrees with the captured SDK identity' $case.name
    }

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
    Invoke-MaterialHostingTests

    Assert-MaterialTest ((Get-MaterialTestHash $script:MaterialTestBaseline) -ceq $baselineHashBefore) "synthetic tests never edit or promote the repository baseline"
    if ($script:MaterialTestFailures.Count -gt 0) {
        throw ("Material provenance rejected $($script:MaterialTestFailures.Count) test expectations:`n" + ($script:MaterialTestFailures -join "`n"))
    }
} catch {
    $materialTestPrimaryFailure = $_
    throw
} finally {
    # Delete only this invocation's exact, resolved UUID child of the OS temp
    # directory. Do not pass enumerated paths to another shell for deletion.
    Invoke-MaterialTestCleanup -OriginalFailure $materialTestPrimaryFailure -Cleanup {
        if (Test-Path -LiteralPath $script:MaterialTestRoot) {
            $resolvedRoot = Resolve-SwiftUIBaselineFileSystemPath -Path $script:MaterialTestRoot
            $resolvedTemp = Resolve-SwiftUIBaselineFileSystemPath -Path $materialTestTemp
            $expectedRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($resolvedTemp, $materialTestName))
            $relativeRoot = Get-SwiftUIBaselineRelativePath -Root $resolvedTemp -Path $resolvedRoot
            $comparison = [System.StringComparison]::Ordinal
            if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $comparison = [System.StringComparison]::OrdinalIgnoreCase }
            if (-not [string]::Equals($resolvedRoot, $expectedRoot, $comparison) -or
                -not [string]::Equals($relativeRoot, $materialTestName, $comparison) -or
                $materialTestName -notmatch '^swiftui-material-provenance-[a-f0-9]{32}$') {
                throw "Refusing to clean a synthetic fixture directory outside the owned OS-temp location."
            }
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
Write-Host "Material provenance tests passed: $script:MaterialTestAssertions assertions across $script:MaterialTestCases synthetic fixtures. No native execution or pixel validation."
