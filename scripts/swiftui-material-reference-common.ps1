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
# The opt-in hosting experiment has a separate protocol validator. None of
# these helpers changes or promotes the canonical material report above.
function Test-SwiftUIMaterialHostingNumber {
    param($Value)
    return (($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) -and
        -not [double]::IsNaN([double]$Value) -and -not [double]::IsInfinity([double]$Value))
}

function Assert-SwiftUIMaterialHostingFields {
    param($Value, [string]$Name, [string[]]$Strings = @(), [string[]]$Booleans = @(),
        [string[]]$Numbers = @(), [string[]]$Objects = @(), [string[]]$Arrays = @(),
        [string[]]$NullableStrings = @(), [string[]]$NullableBooleans = @(),
        [string[]]$NullableNumbers = @(), [string[]]$NullableObjects = @(),
        [string[]]$OptionalStrings = @(), [string[]]$OptionalNumbers = @(),
        [string[]]$OptionalObjects = @(), [switch]$Exact)
    if ($Value -isnot [pscustomobject]) { throw "$Name must be a JSON object." }
    $names = @($Value.PSObject.Properties.Name)
    $expected = [System.Collections.Generic.List[string]]::new()
    foreach ($kind in @("Strings", "Booleans", "Numbers", "Objects", "Arrays",
            "NullableStrings", "NullableBooleans", "NullableNumbers", "NullableObjects",
            "OptionalStrings", "OptionalNumbers", "OptionalObjects")) {
        foreach ($field in (Get-Variable -Name $kind -ValueOnly)) {
            $expected.Add($field)
            $present = $names -ccontains $field
            if (-not $present) {
                if ($kind.StartsWith("Optional")) { continue }
                throw "$Name.$field is missing or has incorrect case."
            }
            $actual = $Value.PSObject.Properties[$field].Value
            if ($null -eq $actual -and ($kind.StartsWith("Nullable") -or $kind.StartsWith("Optional"))) { continue }
            $type = $kind.Replace("Nullable", "").Replace("Optional", "")
            $valid = switch ($type) {
                "Strings" { $actual -is [string] }
                "Booleans" { $actual -is [bool] }
                "Numbers" { Test-SwiftUIMaterialHostingNumber $actual }
                "Objects" { $actual -is [pscustomobject] }
                "Arrays" { $actual -is [System.Array] }
            }
            if (-not $valid) { throw "$Name.$field has an invalid JSON type or nonfinite value; expected $kind." }
        }
    }
    if ($Exact -and (@($names | Where-Object { $expected -cnotcontains $_ }).Count -ne 0)) {
        throw "$Name contains an unknown field."
    }
}

function Assert-SwiftUIMaterialHostingEqual {
    param($Actual, $Expected, [string]$Name, [int]$Depth = 0)
    if ($Depth -gt 32) { throw "$Name exceeds the bounded comparison depth." }
    if ($null -eq $Expected) {
        if ($null -ne $Actual) { throw "$Name must be explicitly null." }
    } elseif ($Expected -is [pscustomobject]) {
        if ($Actual -isnot [pscustomobject]) { throw "$Name must be an object matching the hosting plan." }
        $actualNames = @($Actual.PSObject.Properties.Name)
        $expectedNames = @($Expected.PSObject.Properties.Name)
        if ($actualNames.Count -ne $expectedNames.Count) { throw "$Name has different fields from the hosting plan/provenance." }
        foreach ($field in $expectedNames) {
            if ($actualNames -cnotcontains $field) { throw "$Name.$field is missing or has incorrect case." }
            Assert-SwiftUIMaterialHostingEqual $Actual.$field $Expected.$field "$Name.$field" ($Depth + 1)
        }
    } elseif ($Expected -is [System.Array]) {
        if ($Actual -isnot [System.Array] -or $Actual.Count -ne $Expected.Count) { throw "$Name has the wrong array shape or count." }
        for ($index = 0; $index -lt $Expected.Count; $index++) {
            Assert-SwiftUIMaterialHostingEqual $Actual[$index] $Expected[$index] "$Name[$index]" ($Depth + 1)
        }
    } elseif ($Expected -is [string]) {
        if ($Actual -isnot [string] -or $Actual -cne $Expected) { throw "$Name differs from the hosting plan/provenance." }
    } elseif ($Expected -is [bool]) {
        if ($Actual -isnot [bool] -or $Actual -ne $Expected) { throw "$Name has an inconsistent Boolean value." }
    } elseif (Test-SwiftUIMaterialHostingNumber $Expected) {
        if (-not (Test-SwiftUIMaterialHostingNumber $Actual) -or $Actual -ne $Expected) {
            throw "$Name has an invalid number or differs from the hosting plan."
        }
    } else { throw "$Name has an unsupported comparison type." }
}

function Get-SwiftUIMaterialHostingEvidenceFile {
    param([string]$Directory, [string]$Name, [long]$MaximumBytes)
    if ($Name -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]*\z') { throw "Hosting evidence must name one safe relative filename." }
    $unresolved = Join-Path $Directory $Name
    $item = Get-Item -LiteralPath $unresolved -Force -ErrorAction Stop
    if ($item -isnot [System.IO.FileInfo] -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Hosting evidence must be a regular file, not a directory or link: $Name"
    }
    if ($item.Length -gt $MaximumBytes) { throw "Hosting evidence exceeds its $MaximumBytes byte limit: $Name" }
    return Get-SwiftUIMaterialEvidenceFile -Directory $Directory -Name $Name
}

function Restore-SwiftUIMaterialHostingJsonStrings {
    param($Value, [int]$Depth = 0)
    if ($Depth -gt 32) { throw "Hosting JSON exceeds its bounded restoration depth." }
    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Value -is [string]) {
                if ($property.Value.Length -eq 0 -or [int]$property.Value[0] -ne 1) { throw "Hosting JSON string protection was not preserved." }
                $property.Value = $property.Value.Substring(1)
            } elseif ($property.Value -is [pscustomobject] -or $property.Value -is [System.Array]) {
                Restore-SwiftUIMaterialHostingJsonStrings $property.Value ($Depth + 1)
            }
        }
    } elseif ($Value -is [System.Array]) {
        for ($index = 0; $index -lt $Value.Count; $index++) {
            if ($Value[$index] -is [string]) {
                if ($Value[$index].Length -eq 0 -or [int]$Value[$index][0] -ne 1) { throw "Hosting JSON string protection was not preserved." }
                $Value[$index] = $Value[$index].Substring(1)
            } elseif ($Value[$index] -is [pscustomobject] -or $Value[$index] -is [System.Array]) {
                Restore-SwiftUIMaterialHostingJsonStrings $Value[$index] ($Depth + 1)
            }
        }
    }
}

function Read-SwiftUIMaterialHostingDocument {
    param([string]$Directory, [string]$Name = "hosting-experiment.json")
    $path = Get-SwiftUIMaterialHostingEvidenceFile $Directory $Name 1048576
    $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $memory = [System.IO.MemoryStream]::new()
    try {
        $buffer = [byte[]]::new(8192)
        while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($memory.Length + $count -gt 1048576) { throw "Hosting metadata exceeds the 1048576 byte limit." }
            $memory.Write($buffer, 0, $count)
        }
        $bytes = $memory.ToArray()
    } finally { $stream.Dispose(); $memory.Dispose() }
    $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    if (-not $text.TrimStart().StartsWith("{")) { throw "Hosting metadata root must be a JSON object." }
    # ConvertFrom-Json can silently overwrite duplicate property names. Check
    # object keys before deserializing; normal JSON parsing still owns grammar.
    # Bounds apply before conversion on both Windows PowerShell 5 and PS 7.
    $pattern = '"(?:\\(?:["\\/bfnrt]|u[0-9A-Fa-f]{4})|[^"\\\x00-\x1f])*"|[{}\[\],:]|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?|true|false|null'
    $tokenizer = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant, [TimeSpan]::FromSeconds(1))
    # PS 6+ may coerce date-looking strings, and DateKind String was added only
    # in PS 7.5. Protect every JSON string value with an escaped control prefix
    # before conversion, then remove precisely that prefix in place. This uses
    # the same portable path on PS 5 and every supported PS 7 version, keeps
    # nulls/arrays/numbers intact, and never changes the bytes being hashed.
    $protectedJSON = [System.Text.StringBuilder]::new($text.Length)
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $offset = 0; $tokens = 0
    foreach ($match in $tokenizer.Matches($text)) {
        $gap = $text.Substring($offset, $match.Index - $offset)
        if (-not [string]::IsNullOrWhiteSpace($gap)) { throw "Malformed hosting JSON token." }
        [void]$protectedJSON.Append($gap)
        $offset = $match.Index + $match.Length
        $tokens++
        if ($tokens -gt 100000) { throw "Hosting JSON exceeds its token/node limit." }
        $token = $match.Value
        $isPropertyName = $token.StartsWith('"') -and $stack.Count -gt 0 -and $stack.Peek().kind -ceq "{" -and $stack.Peek().expectsKey
        if ($token -ceq "{" -or $token -ceq "[") {
            if ($stack.Count -ge 32) { throw "Hosting JSON exceeds its bounded depth limit." }
            $stack.Push([pscustomobject]@{
                kind = $token; expectsKey = ($token -ceq "{")
                keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            })
        } elseif ($token -ceq "}" -or $token -ceq "]") {
            if ($stack.Count -eq 0) { throw "Malformed hosting JSON nesting." }
            $open = $stack.Pop().kind
            if (($token -ceq "}" -and $open -cne "{") -or ($token -ceq "]" -and $open -cne "[")) { throw "Malformed hosting JSON nesting." }
        } elseif ($stack.Count -gt 0 -and $stack.Peek().kind -ceq "{") {
            $state = $stack.Peek()
            if ($token -ceq ",") { $state.expectsKey = $true }
            elseif ($token -ceq ":") { $state.expectsKey = $false }
            elseif ($state.expectsKey -and $token.StartsWith('"')) {
                $key = $token.Substring(1, $token.Length - 2)
                if ($key.Contains('\')) {
                    $key = (('{"key":"\u0001' + $token.Substring(1) + '}') | ConvertFrom-Json -ErrorAction Stop).key.Substring(1)
                }
                if (-not $state.keys.Add($key)) { throw "Hosting JSON contains a duplicate or case-colliding field: $key" }
            }
        }
        if ($token.StartsWith('"') -and -not $isPropertyName) {
            [void]$protectedJSON.Append('"\u0001').Append($token.Substring(1))
        } else { [void]$protectedJSON.Append($token) }
    }
    if ($stack.Count -ne 0 -or -not [string]::IsNullOrWhiteSpace($text.Substring($offset))) { throw "Malformed hosting JSON structure." }
    [void]$protectedJSON.Append($text.Substring($offset))
    $value = $protectedJSON.ToString() | ConvertFrom-Json -ErrorAction Stop
    if ($value -isnot [pscustomobject]) { throw "Hosting metadata root must be a JSON object." }
    Restore-SwiftUIMaterialHostingJsonStrings $value
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() }
    finally { $hasher.Dispose() }
    return [pscustomobject]@{ value = $value; sha256 = $hash }
}

function Get-SwiftUIMaterialHostingParameters {
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
        thresholds = [pscustomobject][ordered]@{
            patternMinimumContrast = 0.5; patternMaximumDarkMean = 0.25; patternMinimumLightMean = 0.75
            minimumSampleAlpha = 0.98; tintMinimumContrast = 0.15; tintMinimumRelativeFrequencyRatio = 0.8
            tintMaximumRelativeFrequencyRatio = 1.2; tintMaximumCoarseRetention = 0.9; tintMinimumDarkMeanLift = 0.1
            materialMinimumCoarseContrast = 0.04; materialMinimumCoarseRetention = 0.05
            materialMaximumRelativeFrequencyRatio = 0.35; materialMaximumFrequencyRatioRelativeToTint = 0.4
            maximumRepeatedMetricDifference = 0.02
        }
    }
}

function Get-SwiftUIMaterialHostingSchedule {
    $ordinal = 0; $pairIndex = 0
    foreach ($fixture in @("pattern-control", "flat-tint-control", "material-direct-control",
            "material-compositing-group", "material-drawing-group", "material-content-blur")) {
        foreach ($repetition in 1..2) {
            $pairIndex++
            $arms = @("accessory-unattached", "accessory-unshown-window")
            if ($repetition -eq 2) { $arms = @("accessory-unshown-window", "accessory-unattached") }
            for ($position = 0; $position -lt 2; $position++) {
                $ordinal++
                [pscustomobject][ordered]@{
                    ordinal = $ordinal; pairIndex = $pairIndex; positionInPair = $position + 1
                    arm = $arms[$position]; fixture = $fixture; repetition = $repetition
                    pngFile = "$($arms[$position])-$fixture-$repetition.png"
                }
            }
        }
    }
}

function Assert-SwiftUIMaterialHostingTimestamp {
    param($Value, [string]$Name)
    $parsed = [DateTimeOffset]::MinValue
    if ($Value -isnot [string] -or $Value -cnotmatch '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?Z\z' -or
        -not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { throw "$Name must be an observed UTC timestamp." }
}

function Assert-SwiftUIMaterialHostingReasons {
    param($Reasons, [string]$Name)
    if ($Reasons -isnot [System.Array]) { throw "$Name must be an array." }
    foreach ($reason in $Reasons) {
        if ($reason -isnot [string] -or [string]::IsNullOrWhiteSpace($reason)) { throw "$Name requires nonempty string reasons." }
    }
}

function Assert-SwiftUIMaterialHostingApplication {
    param($Value, [string]$Policy, [string]$Name)
    Assert-SwiftUIMaterialHostingFields $Value $Name -Strings @("activationPolicy") -Booleans @("isActive", "isHidden", "isRunning") -Exact
    if ($Value.activationPolicy -cne $Policy -or $Value.isActive) { throw "$Name has an unexpected activation policy or activity." }
}

function Assert-SwiftUIMaterialHostingWindow {
    param($Value, [string]$Name)
    Assert-SwiftUIMaterialHostingFields $Value $Name -Booleans @("isVisible", "isMiniaturized", "isKeyWindow", "isMainWindow", "occlusionStateVisible") `
        -Numbers @("backingScaleFactor") -Exact
    if ($Value.isVisible -or $Value.isKeyWindow -or $Value.isMainWindow -or $Value.backingScaleFactor -le 0) {
        throw "$Name must remain unshown, not key/main, with an observed positive backing scale."
    }
}

function Assert-SwiftUIMaterialHostingSnapshot {
    param($Value, [string]$Arm, [string]$Name)
    Assert-SwiftUIMaterialHostingFields $Value $Name -Strings @("timestampUTC") `
        -Objects @("systemAccessibility", "swiftUIEnvironment", "application", "host") -Exact
    Assert-SwiftUIMaterialHostingTimestamp $Value.timestampUTC "$Name.timestampUTC"
    Assert-SwiftUIMaterialHostingFields $Value.systemAccessibility "$Name.systemAccessibility" `
        -Booleans @("reduceTransparency", "increaseContrast", "reduceMotion") -Exact
    Assert-SwiftUIMaterialHostingApplication $Value.application "accessory" "$Name.application"
    $environment = $Value.swiftUIEnvironment
    Assert-SwiftUIMaterialHostingFields $environment "$Name.swiftUIEnvironment" -Strings @("status") -Numbers @("bodyEvaluationCount") `
        -NullableStrings @("latestBodyEvaluationUTC") -NullableObjects @("values") -Exact
    if ($environment.bodyEvaluationCount -lt 0 -or [Math]::Floor($environment.bodyEvaluationCount) -ne $environment.bodyEvaluationCount) {
        throw "$Name.swiftUIEnvironment has an invalid body evaluation count."
    }
    if ($environment.status -ceq "unobserved") {
        if ($environment.bodyEvaluationCount -ne 0 -or $null -ne $environment.latestBodyEvaluationUTC -or $null -ne $environment.values) {
            throw "$Name.swiftUIEnvironment fabricates an unobserved value."
        }
    } elseif ($environment.status -ceq "observed") {
        if ($environment.bodyEvaluationCount -lt 1) { throw "$Name.swiftUIEnvironment lacks its observed body count." }
        Assert-SwiftUIMaterialHostingTimestamp $environment.latestBodyEvaluationUTC "$Name.swiftUIEnvironment.latestBodyEvaluationUTC"
        Assert-SwiftUIMaterialHostingFields $environment.values "$Name.swiftUIEnvironment.values" -Strings @("colorScheme", "colorSchemeContrast") `
            -Booleans @("reduceTransparency", "reduceMotion") -Numbers @("displayScale") -Exact
        if ($environment.values.colorScheme -cne "light" -or $environment.values.colorSchemeContrast -cnotin @("standard", "increased") -or
            $environment.values.displayScale -ne 2) { throw "$Name.swiftUIEnvironment differs from the requested appearance/scale." }
    } else { throw "$Name.swiftUIEnvironment has an unknown observation status." }
    $hostMetadata = $Value.host
    Assert-SwiftUIMaterialHostingFields $hostMetadata "$Name.host" -Strings @("effectiveAppearance") `
        -Booleans @("hasWindow", "hasSuperview", "isHidden", "isHiddenOrHasHiddenAncestor", "isFlipped", "wantsLayer", "hasLayer") `
        -Objects @("frame", "bounds", "visibleRect", "convertedBackingBounds") -OptionalNumbers @("layerContentsScale") -OptionalObjects @("window") -Exact
    $logical = [pscustomobject]@{ x = 0; y = 0; width = 384; height = 288 }
    Assert-SwiftUIMaterialHostingEqual $hostMetadata.frame $logical "$Name.host.frame"
    Assert-SwiftUIMaterialHostingEqual $hostMetadata.bounds $logical "$Name.host.bounds"
    foreach ($field in @("visibleRect", "convertedBackingBounds")) {
        Assert-SwiftUIMaterialHostingFields $hostMetadata.$field "$Name.host.$field" -Numbers @("x", "y", "width", "height") -Exact
        if ($hostMetadata.$field.width -lt 0 -or $hostMetadata.$field.height -lt 0) { throw "$Name.host.$field has a negative extent." }
    }
    if ($hostMetadata.effectiveAppearance -cne "NSAppearanceNameAqua" -or -not $hostMetadata.isFlipped -or
        ($null -ne $hostMetadata.layerContentsScale -and $hostMetadata.layerContentsScale -le 0)) { throw "$Name.host has inconsistent appearance or backing metadata." }
    if ($Arm -ceq "accessory-unattached") {
        if ($hostMetadata.hasWindow -or $hostMetadata.hasSuperview -or $null -ne $hostMetadata.window) { throw "$Name.host has an invalid unattached arm attachment." }
    } elseif ($Arm -ceq "accessory-unshown-window") {
        if (-not $hostMetadata.hasWindow) { throw "$Name.host is missing its required window attachment." }
        Assert-SwiftUIMaterialHostingWindow $hostMetadata.window "$Name.host.window"
    } else { throw "$Name has an unknown hosting arm." }
}

function Assert-SwiftUIMaterialHostingMeasurements {
    param($Value, [string]$Name)
    $metrics = @("fineContrast", "fineDarkMean", "fineLightMean", "coarseContrast", "darkMean", "lightMean", "minimumSampleAlpha")
    Assert-SwiftUIMaterialHostingFields $Value $Name -Numbers (@("pixelWidth", "pixelHeight") + $metrics) -Exact
    if ($Value.pixelWidth -ne 768 -or $Value.pixelHeight -ne 576) { throw "$Name has incorrect pixel dimensions." }
    foreach ($field in $metrics) {
        if ($Value.$field -lt 0 -or $Value.$field -gt 1) { throw "$Name.$field is outside the normalized measurement range." }
    }
}

function Test-SwiftUIMaterialHostingRepeatedStability {
    param($First, $Second)
    if ($First.pixelWidth -ne $Second.pixelWidth -or $First.pixelHeight -ne $Second.pixelHeight) { return $false }
    foreach ($field in @("fineContrast", "fineDarkMean", "fineLightMean", "coarseContrast", "darkMean", "lightMean", "minimumSampleAlpha")) {
        if ([Math]::Abs($First.$field - $Second.$field) -gt 0.02) { return $false }
    }
    return $true
}

function Assert-SwiftUIMaterialHostingCapture {
    param($Value, $Planned, [string]$Directory, [string]$Name)
    Assert-SwiftUIMaterialHostingFields $Value $Name -Numbers @("repetition") -Strings @("timestampUTC", "pngFile", "sha256") `
        -Objects @("decodedPNG", "measurements", "captureProvenance") -OptionalStrings @("error") -Exact
    if ($Value.repetition -ne $Planned.repetition -or $Value.pngFile -cne $Planned.pngFile -or $null -ne $Value.error -or
        $Value.sha256 -cnotmatch '\A[0-9a-f]{64}\z') { throw "$Name has an invalid repetition, PNG filename/hash, or capture error." }
    Assert-SwiftUIMaterialHostingTimestamp $Value.timestampUTC "$Name.timestampUTC"
    $png = Get-SwiftUIMaterialHostingEvidenceFile $Directory $Value.pngFile 16777216
    [void](Assert-SwiftUIMaterialFileHash $png $Value.sha256)
    $decoded = $Value.decodedPNG
    Assert-SwiftUIMaterialHostingFields $decoded "$Name.decodedPNG" -Numbers @("pixelWidth", "pixelHeight", "bitsPerSample", "samplesPerPixel", "bytesPerRow") `
        -Booleans @("hasAlpha") -Strings @("colorSpaceName") -Exact
    if ($decoded.pixelWidth -ne 768 -or $decoded.pixelHeight -ne 576 -or $decoded.bitsPerSample -ne 8 -or
        $decoded.samplesPerPixel -notin @(3, 4) -or $decoded.bytesPerRow -lt 768 * $decoded.samplesPerPixel -or
        [Math]::Floor($decoded.bytesPerRow) -ne $decoded.bytesPerRow -or [string]::IsNullOrWhiteSpace($decoded.colorSpaceName)) {
        throw "$Name.decodedPNG has invalid 2x interleaved RGB bitmap metadata."
    }
    Assert-SwiftUIMaterialHostingMeasurements $Value.measurements "$Name.measurements"
    $capture = $Value.captureProvenance
    Assert-SwiftUIMaterialHostingFields $capture "$Name.captureProvenance" -Numbers @("schemaVersion") `
        -Strings @("observationScope", "recommendedBitmapScope") -Booleans @("cacheDisplayCompleted") `
        -Objects @("before", "after", "recommendedBitmap") -Exact
    if ($capture.schemaVersion -ne 1 -or -not $capture.cacheDisplayCompleted -or
        $capture.observationScope -cne "before/after the synchronous cache, encode, and measurement attempt; SwiftUI values are the last body observation, not compositor state" -or
        $capture.recommendedBitmapScope -cne "bitmapImageRepForCachingDisplay(in:) sampled after the attempt; metadata only, not used for capture") {
        throw "$Name.captureProvenance has invalid capture completion/scope metadata."
    }
    Assert-SwiftUIMaterialHostingSnapshot $capture.before $Planned.arm "$Name.captureProvenance.before"
    Assert-SwiftUIMaterialHostingSnapshot $capture.after $Planned.arm "$Name.captureProvenance.after"
    $recommendation = $capture.recommendedBitmap
    Assert-SwiftUIMaterialHostingFields $recommendation "$Name.recommendedBitmap" -Strings @("status") -NullableObjects @("bitmap") -Exact
    if ($recommendation.status -ceq "unavailable") {
        if ($null -ne $recommendation.bitmap) { throw "$Name.recommendedBitmap fabricates an unavailable bitmap." }
    } elseif ($recommendation.status -ceq "observed") {
        $bitmap = $recommendation.bitmap
        Assert-SwiftUIMaterialHostingFields $bitmap "$Name.recommendedBitmap.bitmap" -Strings @("colorSpaceName") `
            -Booleans @("hasAlpha", "isPlanar") -Numbers @("pixelWidth", "pixelHeight", "logicalWidth", "logicalHeight",
                "bitsPerSample", "samplesPerPixel", "bitsPerPixel", "bytesPerRow", "bitmapFormatRawValue") -Exact
        foreach ($field in @("pixelWidth", "pixelHeight", "logicalWidth", "logicalHeight", "bitsPerSample", "samplesPerPixel", "bitsPerPixel", "bytesPerRow")) {
            if ($bitmap.$field -le 0) { throw "$Name.recommendedBitmap.$field must be positive." }
        }
        foreach ($field in @("pixelWidth", "pixelHeight", "bitsPerSample", "samplesPerPixel", "bitsPerPixel", "bytesPerRow", "bitmapFormatRawValue")) {
            if ($bitmap.$field -lt 0 -or [Math]::Floor($bitmap.$field) -ne $bitmap.$field) { throw "$Name.recommendedBitmap.$field must be an unsigned integer." }
        }
        if ([string]::IsNullOrWhiteSpace($bitmap.colorSpaceName)) { throw "$Name.recommendedBitmap is missing its color space." }
    } else { throw "$Name.recommendedBitmap has an unknown observation status." }
}

function Get-SwiftUIMaterialHostingExperimentContext {
    param([Parameter(Mandatory)][string]$Directory)
    $document = Read-SwiftUIMaterialHostingDocument -Directory $Directory
    $report = $document.value
    Assert-SwiftUIMaterialHostingFields $report "Hosting report" -Strings @("evidenceKind") -Booleans @("requested") `
        -Numbers @("schemaVersion", "experimentPlanVersion", "fixtureVersion") -Objects @("qualification", "session") -Arrays @("arms")
    if ($report.schemaVersion -ne 1 -or $report.experimentPlanVersion -ne 1 -or $report.fixtureVersion -ne 1 -or
        $report.evidenceKind -cne "material-hosting-context-experiment-candidate" -or -not $report.requested) {
        throw "Hosting report is not a supported opt-in candidate."
    }
    Assert-SwiftUIMaterialHostingEqual $report.qualification ([pscustomobject]@{
            nativeBehaviorReviewed = $false; nativeRuntimeBuildReviewed = $false; releaseQualified = $false
        }) "Hosting qualification"
    Assert-SwiftUIMaterialHostingFields $report.session "Hosting session" -Strings @("status", "phase")
    if ($report.session.status -cnotin @("in-progress", "completed", "failed") -or
        $report.session.phase -cnotin @("precondition", "accessory-transition", "captures", "restoration", "finished")) {
        throw "Hosting session has an unknown status or phase."
    }
    $armStatuses = [System.Collections.Generic.List[object]]::new()
    if ($report.arms.Count -ne 2) { throw "Hosting report must retain both arm status records." }
    for ($index = 0; $index -lt 2; $index++) {
        $arm = $report.arms[$index]
        Assert-SwiftUIMaterialHostingFields $arm "Hosting arm context" -Strings @("arm", "positiveControlStatus") -Arrays @("inconclusiveReasons")
        if ($arm.arm -cne @("accessory-unattached", "accessory-unshown-window")[$index] -or
            $arm.positiveControlStatus -cnotin @("backdrop-filtering-observed", "inconclusive")) { throw "Hosting context has an unknown arm or control status." }
        Assert-SwiftUIMaterialHostingReasons $arm.inconclusiveReasons "Hosting context arm reasons"
        $armStatuses.Add([pscustomobject]@{ arm = $arm.arm; positiveControlStatus = $arm.positiveControlStatus; inconclusiveReasons = @($arm.inconclusiveReasons) })
    }
    # This is a bounded receipt only. It deliberately accepts failed/partial
    # checkpoints so the wrapper can preserve their status before throwing.
    return [pscustomobject]@{
        report = $report; reportSha256 = $document.sha256; operationalStatus = $report.session.status
        phase = $report.session.phase; armControlStatuses = @($armStatuses.ToArray())
    }
}

function Read-SwiftUIMaterialHostingExperiment {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)]$SDKContext,
        [Parameter(Mandatory)][string]$ExpectedCommit,
        [Parameter(Mandatory)][string]$ExpectedExecutableSha256,
        [Parameter(Mandatory)][string]$ExpectedArchitecture
    )
    $context = Get-SwiftUIMaterialHostingExperimentContext -Directory $Directory
    $report = $context.report
    Assert-SwiftUIMaterialHostingFields $report "Hosting report" `
        -Strings @("evidenceKind", "captureAPI", "canonicalManifestFile", "canonicalManifestSha256", "canonicalPositiveControlStatus", "startedAtUTC", "checkpointAtUTC") `
        -Booleans @("requested") -Numbers @("schemaVersion", "experimentPlanVersion", "fixtureVersion", "canonicalCaptureCount") `
        -Objects @("qualification", "provenance", "parameters", "session") -Arrays @("scheduledAttempts", "attempts", "arms") `
        -NullableStrings @("finishedAtUTC") -Exact
    $session = $report.session
    Assert-SwiftUIMaterialHostingFields $session "Hosting session" -Strings @("status", "phase") -Booleans @("restorationRequired") `
        -Numbers @("completedAttemptCount", "additionalFailureCount") -Arrays @("failures") -NullableNumbers @("nextCaptureOrdinal") `
        -NullableObjects @("initialApplication", "accessoryTransition", "restoration") -Exact
    if ($session.status -cne "completed" -or $session.phase -cne "finished" -or -not $session.restorationRequired -or
        $session.completedAttemptCount -ne 24 -or $null -ne $session.nextCaptureOrdinal -or $session.failures.Count -ne 0 -or
        $session.additionalFailureCount -ne 0 -or $null -eq $report.finishedAtUTC) {
        throw "Hosting experiment is incomplete or failed; its checkpoint remains preserved but cannot pass complete validation."
    }
    foreach ($field in @("startedAtUTC", "checkpointAtUTC", "finishedAtUTC")) { Assert-SwiftUIMaterialHostingTimestamp $report.$field "Hosting report.$field" }
    Assert-SwiftUIMaterialHostingApplication $session.initialApplication "prohibited" "Hosting initialApplication"
    foreach ($field in @("accessoryTransition", "restoration")) {
        $change = $session.$field
        $policy = if ($field -ceq "accessoryTransition") { "accessory" } else { "prohibited" }
        Assert-SwiftUIMaterialHostingFields $change "Hosting $field" -Strings @("requestedPolicy") -Booleans @("returnedSuccess") -Objects @("observedApplication") -Exact
        if ($change.requestedPolicy -cne $policy -or -not $change.returnedSuccess) { throw "Hosting $field did not successfully request the expected policy." }
        Assert-SwiftUIMaterialHostingApplication $change.observedApplication $policy "Hosting $field.observedApplication"
    }
    # Reuse the unchanged original validator first, then link its exact bytes
    # and all source/toolchain/runtime provenance to this separate experiment.
    $canonical = Read-SwiftUIMaterialObservation -Directory $Directory -SDKContext $SDKContext -ExpectedCommit $ExpectedCommit `
        -ExpectedExecutableSha256 $ExpectedExecutableSha256 -ExpectedArchitecture $ExpectedArchitecture
    $canonicalDocument = Read-SwiftUIMaterialHostingDocument -Directory $Directory -Name "manifest.json"
    if ($canonicalDocument.sha256 -cne $canonical.manifestSha256 -or $report.canonicalManifestFile -cne "manifest.json" -or
        $report.canonicalManifestSha256 -cne $canonicalDocument.sha256 -or
        $report.canonicalPositiveControlStatus -cne $canonical.positiveControlStatus -or $report.canonicalCaptureCount -ne 12 -or
        $report.captureAPI -cne "NSHostingView.cacheDisplay(in:to:); no desktop or window capture") {
        throw "Hosting canonical manifest digest, capture count, API or original classification disagrees."
    }
    # The hash also binds fields the original reader does not inspect. Compare
    # provenance from the date-preserving parse; the unchanged canonical reader
    # may materialize timestamp-looking dictionary strings as DateTime on PS 7.
    Assert-SwiftUIMaterialHostingEqual $report.provenance $canonicalDocument.value.provenance "Hosting provenance"
    $parameters = Get-SwiftUIMaterialHostingParameters
    Assert-SwiftUIMaterialHostingEqual $report.parameters $parameters "Hosting parameters"
    foreach ($field in $parameters.PSObject.Properties.Name) {
        Assert-SwiftUIMaterialHostingEqual $canonical.manifest.$field $parameters.$field "Hosting canonical parameters.$field"
    }
    $entries = @(Get-ChildItem -LiteralPath $Directory -Force)
    foreach ($entry in $entries) {
        if ($entry.PSIsContainer -or ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Hosting evidence must remain flat regular files; nested directories and links are invalid."
        }
    }
    $scheduled = @(Get-SwiftUIMaterialHostingSchedule)
    Assert-SwiftUIMaterialHostingEqual $report.scheduledAttempts $scheduled "Hosting scheduledAttempts"
    $expectedFiles = @("manifest.json", "hosting-experiment.json") + @($scheduled | ForEach-Object { $_.pngFile }) +
        @($canonical.manifest.observations | ForEach-Object { $_.captures | ForEach-Object { $_.pngFile } })
    if ($entries.Count -ne $expectedFiles.Count -or @($entries | Where-Object { $expectedFiles -cnotcontains $_.Name }).Count -ne 0) {
        throw "Complete hosting evidence requires exactly the canonical files, sidecar and 24 scheduled PNG filenames."
    }
    if ($report.attempts.Count -ne 24) { throw "Complete hosting experiment requires exactly 24 attempts." }
    for ($index = 0; $index -lt 24; $index++) {
        $actual = $report.attempts[$index]
        $planned = $scheduled[$index]
        $name = "Hosting attempt $($planned.ordinal)"
        Assert-SwiftUIMaterialHostingFields $actual $name -Objects @("attempt", "cleanup") -Arrays @("protocolFailures") `
            -NullableObjects @("setup", "capture") -NullableStrings @("error") -Exact
        Assert-SwiftUIMaterialHostingEqual $actual.attempt $planned "$name.schedule"
        if ($null -ne $actual.error -or $actual.protocolFailures.Count -ne 0) { throw "$name records a capture/protocol failure." }
        Assert-SwiftUIMaterialHostingSnapshot $actual.setup $planned.arm "$name.setup"
        Assert-SwiftUIMaterialHostingCapture $actual.capture $planned $Directory "$name.capture"
        $cleanup = $actual.cleanup
        Assert-SwiftUIMaterialHostingFields $cleanup "$name.cleanup" -Strings @("status") -Booleans @("ownsWindow", "closeCalled") `
            -NullableBooleans @("contentDetached", "hostHasWindowAfterCleanup") -NullableObjects @("windowAfterCleanup", "applicationAfterCleanup") -Exact
        Assert-SwiftUIMaterialHostingApplication $cleanup.applicationAfterCleanup "accessory" "$name.cleanup.applicationAfterCleanup"
        if ($planned.arm -ceq "accessory-unattached") {
            Assert-SwiftUIMaterialHostingEqual $cleanup ([pscustomobject]@{
                    ownsWindow = $false; status = "not-required"; closeCalled = $false
                    contentDetached = $null; hostHasWindowAfterCleanup = $null; windowAfterCleanup = $null
                    applicationAfterCleanup = $cleanup.applicationAfterCleanup
                }) "$name.cleanup"
        } else {
            if (-not $cleanup.ownsWindow -or $cleanup.status -cne "observed" -or -not $cleanup.closeCalled -or
                $cleanup.contentDetached -ne $true -or $null -eq $cleanup.hostHasWindowAfterCleanup -or $cleanup.hostHasWindowAfterCleanup) {
                throw "$name.cleanup does not establish owned-window detachment and close."
            }
            Assert-SwiftUIMaterialHostingWindow $cleanup.windowAfterCleanup "$name.cleanup.windowAfterCleanup"
        }
    }
    $fixtures = @("pattern-control", "flat-tint-control", "material-direct-control", "material-compositing-group", "material-drawing-group", "material-content-blur")
    $materialOrder = "ZStack { Color.clear.frame(width:336,height:240).background(.regularMaterial) }"
    $orders = @("pattern only", "Color.white.opacity(0.4) over pattern", $materialOrder,
        ($materialOrder + ".compositingGroup()"), ($materialOrder + ".drawingGroup(opaque:false,colorMode:.nonLinear)"), ($materialOrder + ".blur(radius:3,opaque:false)"))
    for ($armIndex = 0; $armIndex -lt 2; $armIndex++) {
        $arm = $report.arms[$armIndex]
        $name = "Hosting arm $($arm.arm)"
        Assert-SwiftUIMaterialHostingFields $arm $name -Strings @("arm", "positiveControlStatus") `
            -Arrays @("observations", "controlsByRepetition", "inconclusiveReasons") -Exact
        if ($arm.observations.Count -ne 6 -or $arm.controlsByRepetition.Count -ne 2) { throw "$name requires six observations and two control results." }
        $unstableControls = [System.Collections.Generic.List[string]]::new()
        for ($fixtureIndex = 0; $fixtureIndex -lt 6; $fixtureIndex++) {
            $fixture = $fixtures[$fixtureIndex]
            $observation = $arm.observations[$fixtureIndex]
            Assert-SwiftUIMaterialHostingFields $observation "$name observation" -Strings @("fixture", "modifierOrder") `
                -Arrays @("captureOrdinals") -Booleans @("repeatedMeasurementsStable") -Exact
            $expectedOrdinals = @($scheduled | Where-Object { $_.arm -ceq $arm.arm -and $_.fixture -ceq $fixture } | ForEach-Object { $_.ordinal })
            if ($observation.fixture -cne $fixture -or $observation.modifierOrder -cne $orders[$fixtureIndex] -or
                $canonical.manifest.observations[$fixtureIndex].fixture -cne $fixture -or
                $canonical.manifest.observations[$fixtureIndex].modifierOrder -cne $observation.modifierOrder) { throw "$name has an incorrect fixture order or modifier order." }
            Assert-SwiftUIMaterialHostingEqual $observation.captureOrdinals $expectedOrdinals "$name $fixture captureOrdinals"
            $first = $report.attempts[$expectedOrdinals[0] - 1].capture.measurements
            $second = $report.attempts[$expectedOrdinals[1] - 1].capture.measurements
            $stable = Test-SwiftUIMaterialHostingRepeatedStability $first $second
            if ($observation.repeatedMeasurementsStable -ne $stable) { throw "$name $fixture repeatedMeasurementsStable disagrees with its measurements." }
            if ($fixtureIndex -lt 3 -and -not $stable) { $unstableControls.Add($fixture) }
        }
        $expectedReasons = [System.Collections.Generic.List[string]]::new()
        $unconfirmed = 0
        for ($repetition = 0; $repetition -lt 2; $repetition++) {
            $control = $arm.controlsByRepetition[$repetition]
            Assert-SwiftUIMaterialHostingFields $control "$name control" -Strings @("status") -Arrays @("reasons") `
                -OptionalNumbers @("flatTintRelativeFrequencyRatio", "flatTintCoarseRetention", "flatTintDarkMeanLift", "materialRelativeFrequencyRatio", "materialToTintFrequencyRatio", "materialCoarseRetention") -Exact
            Assert-SwiftUIMaterialHostingReasons $control.reasons "$name control reasons"
            if ($control.status -cnotin @("backdrop-filtering-observed", "inconclusive") -or
                ($control.status -ceq "backdrop-filtering-observed" -and $control.reasons.Count -ne 0) -or
                ($control.status -ceq "inconclusive" -and $control.reasons.Count -eq 0)) { throw "$name control status and reasons are inconsistent." }
            if ($control.status -ceq "inconclusive") { $unconfirmed++ }
            if ($control.status -ceq "backdrop-filtering-observed") {
                foreach ($field in @("flatTintRelativeFrequencyRatio", "flatTintCoarseRetention", "flatTintDarkMeanLift", "materialRelativeFrequencyRatio", "materialToTintFrequencyRatio", "materialCoarseRetention")) {
                    if ($null -eq $control.$field) { throw "$name confirmed control.$field is missing its measured value." }
                }
            }
            foreach ($field in @("flatTintRelativeFrequencyRatio", "flatTintCoarseRetention", "materialRelativeFrequencyRatio", "materialToTintFrequencyRatio", "materialCoarseRetention")) {
                if ($null -ne $control.$field -and $control.$field -lt 0) { throw "$name control.$field has a negative ratio." }
            }
            if ($null -ne $control.flatTintDarkMeanLift -and ($control.flatTintDarkMeanLift -lt -1 -or $control.flatTintDarkMeanLift -gt 1)) {
                throw "$name control.flatTintDarkMeanLift is outside the measurement range."
            }
            foreach ($reason in $control.reasons) { $expectedReasons.Add("Repetition $($repetition + 1): $reason") }
        }
        foreach ($fixture in $unstableControls) { $expectedReasons.Add("Control $fixture did not produce stable repeated measurements.") }
        $expectedStatus = if ($unconfirmed -eq 0 -and $unstableControls.Count -eq 0) { "backdrop-filtering-observed" } else { "inconclusive" }
        if ($arm.positiveControlStatus -cne $expectedStatus) { throw "$name positive control status is inconsistent with its own repeated controls." }
        Assert-SwiftUIMaterialHostingEqual $arm.inconclusiveReasons @($expectedReasons.ToArray()) "$name inconclusiveReasons"
    }
    return [pscustomobject]@{
        report = $report; reportSha256 = $context.reportSha256; canonicalManifestSha256 = $canonical.manifestSha256
        canonicalPositiveControlStatus = $canonical.positiveControlStatus; operationalStatus = $session.status
        armControlStatuses = $context.armControlStatuses
        validationScope = "provenance and hosting protocol only; PNG pixels and the native classifier are not re-executed"
    }
}
