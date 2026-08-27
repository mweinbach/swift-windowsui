# Read-only provenance validation. No native tools or SwiftPM run when imported.
. (Join-Path $PSScriptRoot "swiftui-baseline-common.ps1")

function Get-SwiftUIMaterialEnvironmentOverrides {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Environment)
    # SwiftPM honors SWIFT_EXEC before its adjacent compiler. Driver, SDK,
    # library, and header overrides also invalidate this captured-tool build.
    # Return names only; never put environment values into candidate evidence.
    foreach ($name in $Environment.Keys) {
        if ($name -match '^(SWIFT_|SWIFTPM_|SWIFTC_|DYLD_|CLANG_)' -or
            $name -match '^(TOOLCHAINS|SDKROOT|MACOSX_DEPLOYMENT_TARGET|CC|CXX|LIBTOOL|AR|LD|LD_PRELOAD|CPATH|C_INCLUDE_PATH|CPLUS_INCLUDE_PATH|OBJC_INCLUDE_PATH|LIBRARY_PATH|XCODE_XCCONFIG_FILE)$') {
            if ($name -cne "SWIFT_WINDOWSUI_REFERENCE_BUILD_CONFIGURATION" -and
                -not [string]::IsNullOrEmpty([string]$Environment[$name])) { Write-Output ([string]$name) }
        }
    }
}

function Assert-SwiftUIMaterialFields {
    param($Value, [string]$Name, [string[]]$Strings = @(), [string[]]$Booleans = @(),
        [string[]]$Numbers = @(), [string[]]$Objects = @(), [string[]]$Arrays = @())
    if ($Value -isnot [pscustomobject]) { throw "$Name must be a JSON object." }
    foreach ($kind in @("Strings", "Booleans", "Numbers", "Objects", "Arrays")) {
        foreach ($field in (Get-Variable -Name $kind -ValueOnly)) {
            $actual = $Value.PSObject.Properties[$field].Value
            $valid = switch ($kind) {
                "Strings" { $actual -is [string] }
                "Booleans" { $actual -is [bool] }
                "Numbers" { $actual -is [int] -or $actual -is [long] -or $actual -is [double] -or $actual -is [decimal] }
                "Objects" { $actual -is [pscustomobject] }
                "Arrays" { $actual -is [System.Array] }
            }
            if (-not $valid) { throw "$Name.$field has an invalid JSON type; expected $kind." }
        }
    }
}

function Read-SwiftUIMaterialJson {
    param([Parameter(Mandatory)][string]$Path, [int]$MaxBytes = 1048576)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $memory = [System.IO.MemoryStream]::new()
    try {
        $buffer = [byte[]]::new(8192)
        while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($memory.Length + $count -gt $MaxBytes) { throw "Metadata exceeds the $MaxBytes byte limit: $Path" }
            $memory.Write($buffer, 0, $count)
        }
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($memory.ToArray())
        # ConvertFrom-Json's pipeline can unwrap a singleton root array before
        # a caller sees its type. Every metadata document here requires an object.
        if (-not $text.TrimStart().StartsWith("{")) { throw "Metadata root must be a JSON object: $Path" }
        return ($text | ConvertFrom-Json -ErrorAction Stop)
    } finally { $stream.Dispose(); $memory.Dispose() }
}

function Get-SwiftUIMaterialEvidenceFile {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Name)
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "Evidence must name one relative file: $Name" }
    $root = Resolve-SwiftUIBaselineFileSystemPath -Path $Directory
    $path = Resolve-SwiftUIBaselineFileSystemPath -Path (Join-Path $root $Name)
    [void](Get-SwiftUIBaselineRelativePath -Root $root -Path $path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing evidence file: $Name" }
    return $path
}

function Assert-SwiftUIMaterialFileHash {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$SHA256)
    if ($SHA256 -cnotmatch '^[0-9a-f]{64}$') { throw "Invalid SHA256 for $Path" }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $SHA256) { throw "SHA256 mismatch for $Path" }
    return $actual
}

function Read-SwiftUIMaterialSDKContext {
    param([Parameter(Mandatory)][string]$CaptureRoot, [Parameter(Mandatory)][string]$ManifestPath)
    $status = Read-SwiftUIMaterialJson -Path (Get-SwiftUIMaterialEvidenceFile $CaptureRoot "capture-status.json") -MaxBytes 65536
    Assert-SwiftUIMaterialFields $status "SDK status" -Strings @("status", "captureManifest", "captureManifestSha256", "baselineId", "behaviorConformance")
    if ($status.status -cne "exported-awaiting-review" -or $status.captureManifest -cne "capture.json" -or
        $status.behaviorConformance -cne "not-verified") {
        throw "Material capture requires a complete SDK candidate export."
    }
    $capturePath = Get-SwiftUIMaterialEvidenceFile $CaptureRoot "capture.json"
    $capture = Read-SwiftUIMaterialJson -Path $capturePath -MaxBytes 16777216
    Assert-SwiftUIMaterialFields $capture "SDK capture" -Strings @("baselineId", "status", "developerDirectoryOverride") `
        -Booleans @("exactIdentityPreviouslyReviewed") -Numbers @("schemaVersion") -Arrays @("tools") `
        -Objects @("observedIdentity", "host", "baselineManifest", "sdk", "qualification")
    Assert-SwiftUIMaterialFields $capture.observedIdentity "SDK identity" -Strings @("xcodeVersion", "xcodeBuildVersion", "sdkVersion", "sdkBuildVersion", "swiftCompilerVersion", "swiftCompilerVersionLine")
    Assert-SwiftUIMaterialFields $capture.host "SDK host" -Strings @("macOSVersion", "macOSBuildVersion", "architecture")
    Assert-SwiftUIMaterialFields $capture.baselineManifest "SDK baseline manifest" -Strings @("path", "sha256")
    Assert-SwiftUIMaterialFields $capture.sdk "SDK settings" -Strings @("path", "version", "buildVersion", "settingsPath", "settingsSha256")
    Assert-SwiftUIMaterialFields $capture.qualification "SDK qualification" -Booleans @("publicAPIAuditComplete", "behaviorConformanceVerified", "releaseQualified")
    foreach ($tool in $capture.tools) { Assert-SwiftUIMaterialFields $tool "SDK tool" -Strings @("path", "sha256") }
    $captureHash = Assert-SwiftUIMaterialFileHash $capturePath $status.captureManifestSha256
    $digestPath = Get-SwiftUIMaterialEvidenceFile $CaptureRoot "capture.sha256"
    if ((Get-Item -LiteralPath $digestPath).Length -gt 1024 -or
        [System.IO.File]::ReadAllText($digestPath).Trim() -cne "$captureHash  capture.json") {
        throw "SDK capture digest file disagrees with its status."
    }
    [void](Read-SwiftUIMaterialJson -Path $ManifestPath)
    $manifest = Read-SwiftUIBaselineManifest -Path $ManifestPath
    $baselineHash = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($capture.schemaVersion -ne 1 -or $capture.baselineId -cne $manifest.baselineId -or $status.baselineId -cne $manifest.baselineId -or
        $capture.status -cne "exported-awaiting-inventory-and-behavior-review" -or
        $capture.baselineManifest.path -cne "baseline-manifest.json" -or
        $capture.baselineManifest.sha256 -cne $baselineHash) { throw "SDK candidate does not match the requested baseline manifest." }
    [void](Assert-SwiftUIMaterialFileHash (Get-SwiftUIMaterialEvidenceFile $CaptureRoot "baseline-manifest.json") $baselineHash)
    $reviewed = Assert-SwiftUIBaselineIdentity -Manifest $manifest -Identity $capture.observedIdentity
    if ($capture.exactIdentityPreviouslyReviewed -ne $reviewed -or
        $capture.qualification.publicAPIAuditComplete -ne $false -or
        $capture.qualification.behaviorConformanceVerified -ne $false -or $capture.qualification.releaseQualified -ne $false) {
        throw "SDK candidate contains inconsistent qualification or review status."
    }
    if ($capture.sdk.settingsPath -cnotin @("SDKSettings.json", "SDKSettings.plist") -or
        $capture.sdk.version -cne $capture.observedIdentity.sdkVersion -or
        $capture.sdk.buildVersion -cne $capture.observedIdentity.sdkBuildVersion) { throw "SDK metadata disagrees with captured identity." }
    $swiftTools = @($capture.tools | Where-Object { [System.IO.Path]::GetFileName($_.path) -ceq "swift" })
    if ($swiftTools.Count -ne 1 -or $swiftTools[0].path.Replace('\', '/') -notmatch '/Toolchains/XcodeDefault\.xctoolchain/usr/bin/swift$') {
        throw "SDK capture must identify exactly one XcodeDefault Swift executable."
    }
    foreach ($path in @($swiftTools[0].path, $capture.sdk.path)) {
        [void](Get-SwiftUIBaselineRelativePath -Root $capture.developerDirectoryOverride -Path $path)
        [void](Get-SwiftUIBaselineRelativePath -Root (Resolve-SwiftUIBaselineFileSystemPath $capture.developerDirectoryOverride) `
            -Path (Resolve-SwiftUIBaselineFileSystemPath $path))
    }
    [void](Assert-SwiftUIMaterialFileHash $swiftTools[0].path $swiftTools[0].sha256)
    $settings = Get-SwiftUIMaterialEvidenceFile $CaptureRoot $capture.sdk.settingsPath
    [void](Assert-SwiftUIMaterialFileHash $settings $capture.sdk.settingsSha256)
    $liveSettings = Join-Path $capture.sdk.path $capture.sdk.settingsPath
    [void](Assert-SwiftUIMaterialFileHash $liveSettings $capture.sdk.settingsSha256)
    if ([string]::IsNullOrWhiteSpace($capture.host.macOSVersion) -or [string]::IsNullOrWhiteSpace($capture.host.macOSBuildVersion) -or
        $capture.host.architecture -cnotin @("x86_64", "arm64")) { throw "SDK capture is missing its actual host identity." }
    # Deliberately never open inventory.json: its hash/counts are not needed to run these fixtures.
    return [pscustomobject]@{
        manifest = $manifest; capture = $capture; swiftTool = $swiftTools[0]
        captureManifestSha256 = $captureHash; baselineManifestSha256 = $baselineHash
        exactIdentityPreviouslyReviewed = $reviewed
    }
}

function Read-SwiftUIMaterialObservation {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)]$SDKContext,
        [Parameter(Mandatory)][string]$ExpectedCommit,
        [Parameter(Mandatory)][string]$ExpectedExecutableSha256,
        [Parameter(Mandatory)][string]$ExpectedArchitecture
    )
    if ($ExpectedCommit -cnotmatch '^[0-9a-f]{40}$' -or $ExpectedExecutableSha256 -cnotmatch '^[0-9a-f]{64}$') { throw "Invalid expected build identity." }
    $path = Get-SwiftUIMaterialEvidenceFile $Directory "manifest.json"
    $manifest = Read-SwiftUIMaterialJson -Path $path
    Assert-SwiftUIMaterialFields $manifest "Material manifest" -Strings @("qualification", "groupBehaviorReview", "requestedAppearance", "material", "positiveControlStatus") `
        -Numbers @("schemaVersion", "fixtureVersion", "logicalWidth", "logicalHeight", "requestedScale", "repetitions") `
        -Objects @("provenance") -Arrays @("observations", "controlsByRepetition", "inconclusiveReasons")
    if ($manifest.schemaVersion -ne 1 -or $manifest.fixtureVersion -ne 1 -or
        $manifest.qualification -cne "candidate-only; not pinned SDK qualification or SwiftUI conformance" -or
        $manifest.groupBehaviorReview -cne "unreviewed; even a passing direct control does not qualify every wrapper") {
        throw "Material report is not a supported, unreviewed candidate."
    }
    $provenance = $manifest.provenance
    Assert-SwiftUIMaterialFields $provenance "Material provenance" -Strings @("sourceCommitAtCapture", "executableSHA256", "processArchitecture", "osBuild", "osVersion", "swiftLanguageMode",
        "declaredBuildConfiguration", "sdkPathAtCapture", "trackedWorkingTreeAtCapture", "xcodeAtCapture", "sdkVersionAtCapture", "sdkBuildAtCapture", "swiftAtCapture")
    if ($provenance.sourceCommitAtCapture -cne $ExpectedCommit -or $provenance.executableSHA256 -cne $ExpectedExecutableSha256 -or
        $provenance.processArchitecture -cne $ExpectedArchitecture -or $ExpectedArchitecture -cne $SDKContext.capture.host.architecture -or
        $provenance.osBuild -cne $SDKContext.capture.host.macOSBuildVersion -or [string]::IsNullOrWhiteSpace($provenance.osVersion) -or
        $provenance.swiftLanguageMode -cne "6" -or $provenance.declaredBuildConfiguration -cne "release" -or
        $provenance.sdkPathAtCapture -cne $SDKContext.capture.sdk.path -or
        -not [string]::IsNullOrEmpty($provenance.trackedWorkingTreeAtCapture)) { throw "Material runtime/build provenance disagrees with the SDK capture or clean source commit." }
    $identity = ConvertTo-SwiftUIBaselineIdentity -XcodeOutput $provenance.xcodeAtCapture -SDKVersion $provenance.sdkVersionAtCapture `
        -SDKBuildVersion $provenance.sdkBuildAtCapture -SwiftOutput $provenance.swiftAtCapture
    [void](Assert-SwiftUIBaselineIdentity -Manifest $SDKContext.manifest -Identity $identity)
    foreach ($field in @("xcodeVersion", "xcodeBuildVersion", "sdkVersion", "sdkBuildVersion", "swiftCompilerVersionLine")) {
        if ($identity.$field -cne $SDKContext.capture.observedIdentity.$field) { throw "Material $field disagrees with the captured SDK identity." }
    }
    if ($manifest.logicalWidth -ne 384 -or $manifest.logicalHeight -ne 288 -or $manifest.requestedScale -ne 2 -or
        $manifest.repetitions -ne 2 -or $manifest.requestedAppearance -cne "light / NSAppearance.aqua" -or
        $manifest.material -cne "regularMaterial") { throw "Material fixture plan differs from the captured public fixture version." }
    $expectedFixtures = @("pattern-control", "flat-tint-control", "material-direct-control", "material-compositing-group", "material-drawing-group", "material-content-blur")
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if (@($manifest.observations).Count -ne $expectedFixtures.Count) { throw "Material report must contain all six fixtures." }
    foreach ($observation in $manifest.observations) {
        Assert-SwiftUIMaterialFields $observation "Material observation" -Strings @("fixture", "modifierOrder") -Booleans @("repeatedMeasurementsStable") -Arrays @("captures")
        if ($expectedFixtures -cnotcontains $observation.fixture -or -not $seen.Add($observation.fixture) -or @($observation.captures).Count -ne 2) {
            throw "Missing or duplicate material fixture/capture."
        }
        $repetitions = [System.Collections.Generic.HashSet[int]]::new()
        foreach ($image in $observation.captures) {
            Assert-SwiftUIMaterialFields $image "Material PNG" -Numbers @("repetition") -Strings @("pngFile", "sha256") -Objects @("decodedPNG", "measurements")
            Assert-SwiftUIMaterialFields $image.decodedPNG "Decoded PNG" -Numbers @("pixelWidth", "pixelHeight")
            Assert-SwiftUIMaterialFields $image.measurements "PNG measurements" -Numbers @("pixelWidth", "pixelHeight")
            if ($image.repetition -notin @(1, 2) -or -not $repetitions.Add([int]$image.repetition) -or $null -ne $image.error -or
                $image.pngFile -cne "$($observation.fixture)-$($image.repetition).png" -or
                $image.decodedPNG.pixelWidth -ne 768 -or $image.decodedPNG.pixelHeight -ne 576 -or
                $image.measurements.pixelWidth -ne 768 -or $image.measurements.pixelHeight -ne 576) { throw "Incomplete or malformed material PNG record." }
            $png = Get-SwiftUIMaterialEvidenceFile $Directory $image.pngFile
            if ((Get-Item -LiteralPath $png).Length -gt 16777216) { throw "Diagnostic PNG exceeds its bounded fixture size." }
            [void](Assert-SwiftUIMaterialFileHash $png $image.sha256)
        }
    }
    if ($manifest.positiveControlStatus -cnotin @("backdrop-filtering-observed", "inconclusive") -or @($manifest.controlsByRepetition).Count -ne 2) {
        throw "Missing or unknown material control classification."
    }
    foreach ($control in $manifest.controlsByRepetition) {
        Assert-SwiftUIMaterialFields $control "Material repetition control" -Strings @("status") -Arrays @("reasons")
        if ($control.status -cnotin @("backdrop-filtering-observed", "inconclusive") -or
            ($control.status -ceq "backdrop-filtering-observed" -and $control.reasons.Count -ne 0) -or
            ($control.status -ceq "inconclusive" -and $control.reasons.Count -eq 0)) {
            throw "Material repetition control classification/reasons are inconsistent."
        }
        foreach ($reason in $control.reasons) {
            if ($reason -isnot [string] -or [string]::IsNullOrWhiteSpace($reason)) { throw "Material repetition control reasons must be nonempty strings." }
        }
    }
    foreach ($reason in $manifest.inconclusiveReasons) {
        if ($reason -isnot [string] -or [string]::IsNullOrWhiteSpace($reason)) { throw "Material inconclusive reasons must be nonempty strings." }
    }
    $unstableControls = @($manifest.observations | Where-Object { $_.fixture -cin $expectedFixtures[0..2] -and $_.repeatedMeasurementsStable -ne $true })
    $unconfirmed = @($manifest.controlsByRepetition | Where-Object { $_.status -cne "backdrop-filtering-observed" })
    if ($manifest.positiveControlStatus -ceq "backdrop-filtering-observed") {
        if ($manifest.inconclusiveReasons.Count -ne 0 -or $unconfirmed.Count -gt 0 -or $unstableControls.Count -gt 0) {
            throw "Material positive control classification is inconsistent."
        }
    } elseif ($manifest.inconclusiveReasons.Count -eq 0 -or ($unconfirmed.Count -eq 0 -and $unstableControls.Count -eq 0)) {
        throw "Inconclusive material capture must preserve its failing control or instability reasons."
    }
    return [pscustomobject]@{
        manifest = $manifest; manifestSha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        positiveControlStatus = $manifest.positiveControlStatus; runtimeOSBuild = $provenance.osBuild
        runtimeOSVersion = $provenance.osVersion; architecture = $provenance.processArchitecture
    }
}
