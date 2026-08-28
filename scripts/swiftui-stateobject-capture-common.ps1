# Private orchestration for compiler characterization. Importing this file runs
# no processes. The public entry point supplies the only native request adapter;
# synthetic tests supply PowerShell records to these functions, never Swift.
. (Join-Path $PSScriptRoot 'swiftui-stateobject-isolation-common.ps1')
. (Join-Path $PSScriptRoot 'swiftui-stateobject-process-common.ps1')
. (Join-Path $PSScriptRoot 'swiftui-material-reference-common.ps1')

function Get-SwiftUIStateObjectCapturePolicy {
    return [pscustomobject]@{
        schemaVersion = 1
        captureManifestSHA256 = 'f900bef9de2e5c37b8145ad6bdae7a3fe1c9b679f15b324175e3f1c89797057d'
        captureStatusSHA256 = 'd4d937791faf39ea0a1768ce6105d0173125b96aea8069457e798f17a3647a74'
        captureDigestSHA256 = '5cf94b6893a4ad8f90ef6ef29f376d37db4ef3ff9829d7c861895dc11a48e08e'
        baselineManifestSHA256 = '24b9c8680528247173e74dfec68a143b85b300bbfb64d43c1e545517782bf51a'
        developerDirectory = '/Applications/Xcode_26.6.app/Contents/Developer'
        sdkPath = '/Applications/Xcode_26.6.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk'
        sdkSettingsSHA256 = 'f8d005f09381389167f9e0aeaa169bc9e7dff162ef22ca2fd8e98df7ff1acafe'
        compilerVersionLine = 'Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)'
        xcodeVersion = '26.6'; xcodeBuildVersion = '17F113'; sdkVersion = '26.5'; sdkBuildVersion = '25F70'
        interfaceAnchors = @(
            [pscustomobject]@{ path = 'interfaces/SwiftUI/arm64e-apple-macos.swiftinterface'; sha256 = 'da276921c83f2fa0e00bb3892865cfb4d3326d895984947c260b018306433bef'; platform = 'macOS'; interfaceArchitecture = 'arm64e' },
            [pscustomobject]@{ path = 'interfaces/SwiftUI/x86_64-apple-macos.swiftinterface'; sha256 = 'e6ba841c2a4522b2bdd3760f944ca4c2b41ce17a6ad720c6a19180e3446b4d56'; platform = 'macOS'; interfaceArchitecture = 'x86_64' },
            [pscustomobject]@{ path = 'interfaces/SwiftUICore/arm64e-apple-macos.swiftinterface'; sha256 = '18577568a167a7ab27abd42968891cf913d455a9bbd3d30b01eda8f8011af0db'; platform = 'macOS'; interfaceArchitecture = 'arm64e' },
            [pscustomobject]@{ path = 'interfaces/SwiftUICore/x86_64-apple-macos.swiftinterface'; sha256 = '77eb01dd0625b35403d08e0247aaa03add0595528fd1c3d69f21a4cbb3cfe498'; platform = 'macOS'; interfaceArchitecture = 'x86_64' },
            [pscustomobject]@{ path = 'interfaces/SwiftUICore/arm64e-apple-ios-macabi.swiftinterface'; sha256 = '59ae88b2cf5c7e82fc1a08e3e6f5dc9540baada996046c758fc1297f3fe61f8d'; platform = 'Catalyst-source-only'; interfaceArchitecture = 'arm64e' },
            [pscustomobject]@{ path = 'interfaces/SwiftUICore/x86_64-apple-ios-macabi.swiftinterface'; sha256 = 'fbfad6305cb8e1e2f99c219a62d06378adc82b2f2beebf18b0010ec48267a5b9'; platform = 'Catalyst-source-only'; interfaceArchitecture = 'x86_64' }
        )
        harnessPaths = @(
            'scripts/capture-swiftui-stateobject-isolation.ps1',
            'scripts/swiftui-stateobject-capture-common.ps1',
            'scripts/swiftui-stateobject-isolation-common.ps1',
            'scripts/swiftui-stateobject-process-common.ps1',
            'scripts/swiftui-material-reference-common.ps1',
            'scripts/swiftui-baseline-common.ps1',
            '.github/workflows/swiftui-stateobject-isolation.yml'
        )
        qualification = [pscustomobject]@{
            runtimeEvidence = $false; parityClaimed = $false; productionApprovalChanged = $false
        }
    }
}

function Assert-SwiftUIStateObjectCaptureFields {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string[]]$Fields, [string]$Name = 'Record')
    if ($Value -isnot [pscustomobject] -and $Value -isnot [System.Collections.IDictionary]) { throw "$Name must be an object." }
    $names = @($Value.PSObject.Properties.Name)
    if ($Value -is [System.Collections.IDictionary]) { $names = @($Value.Keys) }
    if ($names.Count -ne $Fields.Count) { throw "$Name has unexpected or missing fields." }
    foreach ($field in $Fields) { if ($names -cnotcontains $field) { throw "$Name is missing $field." } }
}

function Assert-SwiftUIStateObjectCaptureSHA256 {
    param([Parameter(Mandatory)][string]$Value, [string]$Name = 'SHA256')
    if ($Value -cnotmatch '^[0-9a-f]{64}$') { throw "$Name must be a lowercase SHA256." }
}

function Assert-SwiftUIStateObjectNoQualification {
    param([Parameter(Mandatory)]$Value)
    Assert-SwiftUIStateObjectCaptureFields $Value @('runtimeEvidence', 'parityClaimed', 'productionApprovalChanged') 'Qualification'
    foreach ($field in @('runtimeEvidence', 'parityClaimed', 'productionApprovalChanged')) {
        if ($Value.$field -isnot [bool] -or $Value.$field) { throw 'Compiler characterization cannot qualify runtime behavior or a production change.' }
    }
}

function Assert-SwiftUIStateObjectNativePath {
    param([Parameter(Mandatory)]$Value)
    $canonical = ConvertTo-SwiftUIStateObjectDiagnosticPath $Value
    if ($null -eq $canonical -or -not $canonical.StartsWith('/') -or $canonical -cne $Value) { throw 'A producer path must be a canonical absolute POSIX name, regardless of the archive reader host.' }
}

function Assert-SwiftUIStateObjectExecutionEnvironment {
    param([Parameter(Mandatory)]$Value)
    Assert-SwiftUIStateObjectCaptureFields $Value @('overrideNames', 'developerDirectory') 'Process environment policy'
    Assert-SwiftUIStateObjectStringArray -Value $Value.overrideNames -Name 'Environment override names' -Unique
    if (($Value.overrideNames -join '|') -cne 'DEVELOPER_DIR|LANG|LC_ALL|TEMP|TMP|TMPDIR' -or
        $Value.developerDirectory -cne (Get-SwiftUIStateObjectCapturePolicy).developerDirectory) { throw 'Archived process environment differs from the fixed execution policy.' }
}

function Assert-SwiftUIStateObjectRawProcess {
    param([Parameter(Mandatory)]$Value, [long]$MaxCombinedBytes)
    Assert-SwiftUIStateObjectCaptureFields $Value @('startedAtUtc', 'finishedAtUtc', 'processStarted', 'processId', 'exitCode',
        'timedOut', 'outputLimitExceeded', 'observedDiscardedBytes', 'terminationRequested', 'terminationCompleted',
        'allRedirectedStreamsClosed', 'terminationNote', 'stdoutBytes', 'stderrBytes', 'stdoutSha256', 'stderrSha256',
        'durationSeconds', 'error', 'cleanupErrors') 'Raw process record'
    foreach ($field in @('stdoutBytes', 'stderrBytes', 'observedDiscardedBytes')) {
        Assert-SwiftUIStateObjectInteger -Value $Value.$field -Name "Raw process $field" -Minimum 0 -Maximum ([long]::MaxValue)
    }
    if ($Value.stdoutBytes -gt $MaxCombinedBytes -or $Value.stderrBytes -gt $MaxCombinedBytes -or
        ([long]$Value.stdoutBytes + [long]$Value.stderrBytes) -gt $MaxCombinedBytes) { throw 'Raw process streams exceed the combined byte limit.' }
    foreach ($field in @('processStarted', 'timedOut', 'outputLimitExceeded', 'terminationRequested', 'terminationCompleted', 'allRedirectedStreamsClosed')) {
        Assert-SwiftUIStateObjectBoolean -Value $Value.$field -Name "Raw process $field"
    }
    if ($null -ne $Value.processId) { Assert-SwiftUIStateObjectInteger -Value $Value.processId -Name 'Raw process ID' -Minimum 1 -Maximum ([int]::MaxValue) }
    if ($null -ne $Value.exitCode) { Assert-SwiftUIStateObjectInteger -Value $Value.exitCode -Name 'Raw process exitCode' -Minimum ([int]::MinValue) -Maximum ([uint32]::MaxValue) }
    if ($Value.durationSeconds -isnot [double] -and $Value.durationSeconds -isnot [decimal] -and $Value.durationSeconds -isnot [int] -and $Value.durationSeconds -isnot [long]) { throw 'Raw process duration must be numeric.' }
    if ([double]::IsNaN([double]$Value.durationSeconds) -or [double]::IsInfinity([double]$Value.durationSeconds) -or $Value.durationSeconds -lt 0) { throw 'Raw process duration must be finite and nonnegative.' }
    foreach ($field in @('startedAtUtc', 'finishedAtUtc', 'terminationNote')) { Assert-SwiftUIStateObjectString -Value $Value.$field -Name "Raw process $field" }
    foreach ($field in @('stdoutSha256', 'stderrSha256')) { Assert-SwiftUIStateObjectCaptureSHA256 $Value.$field "Raw process $field" }
    if ($null -ne $Value.error) { Assert-SwiftUIStateObjectString -Value $Value.error -Name 'Raw process error' }
    Assert-SwiftUIStateObjectStringArray -Value $Value.cleanupErrors -Name 'Raw process cleanup errors'
}

function Get-SwiftUIStateObjectCaptureFilePolicy {
    $policy = Get-SwiftUIStateObjectCapturePolicy
    $files = @(
        [pscustomobject]@{ path = 'capture.json'; sha256 = $policy.captureManifestSHA256 },
        [pscustomobject]@{ path = 'capture-status.json'; sha256 = $policy.captureStatusSHA256 },
        [pscustomobject]@{ path = 'baseline-manifest.json'; sha256 = $policy.baselineManifestSHA256 },
        [pscustomobject]@{ path = 'SDKSettings.json'; sha256 = $policy.sdkSettingsSHA256 },
        [pscustomobject]@{ path = 'capture.sha256'; sha256 = $policy.captureDigestSHA256 }
    )
    foreach ($anchor in $policy.interfaceAnchors) { $files += [pscustomobject]@{ path = $anchor.path; sha256 = $anchor.sha256 } }
    return $files
}

function Read-SwiftUIStateObjectCaptureFixtureFiles {
    param([Parameter(Mandatory)][string]$Root)
    # Offline source data only. This has no SDK discovery, live macOS paths,
    # process adapter, or alternate expected-hash parameter.
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($pin in (Get-SwiftUIStateObjectCaptureFilePolicy)) {
        $path = Resolve-SwiftUIStateObjectEvidencePath -Root $Root -RelativePath $pin.path
        $file = Get-SwiftUIStateObjectFileHash $path -MaxBytes 16777216
        if ($file.sha256 -cne $pin.sha256) { throw 'Explicit SDK source fixture differs from the sealed capture.' }
        $files.Add([pscustomobject]@{ path = $path; relativePath = $pin.path; sha256 = $file.sha256; bytes = $file.bytes })
    }
    return $files.ToArray()
}

function Write-SwiftUIStateObjectCaptureJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value, [int]$MaxBytes = 4194304)
    $text = ($Value | ConvertTo-Json -Depth 40) + [Environment]::NewLine
    $bytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes($text)
    if ($bytes.Length -gt $MaxBytes) { throw "JSON output exceeds its $MaxBytes byte bound." }
    $parent = Split-Path -Parent $Path
    [void](Resolve-SwiftUIStateObjectEvidencePath -Root $parent -RelativePath ([System.IO.Path]::GetFileName($Path)) -AllowMissingLeaf)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    return (Get-SwiftUIStateObjectFileHash -Path $Path -MaxBytes $MaxBytes)
}

function New-SwiftUIStateObjectCaptureDirectory {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$RepositoryRoot)
    if (-not [System.IO.Path]::IsPathRooted($Path) -or $Path -match '[\x00-\x1f\x7f]') { throw 'OutputPath must be an absolute, control-free path.' }
    $resolved = Resolve-SwiftUIBaselineFileSystemPath -Path $Path
    $allowedRoots = @(
        (Resolve-SwiftUIBaselineFileSystemPath -Path (Join-Path $RepositoryRoot 'artifacts')),
        (Resolve-SwiftUIBaselineFileSystemPath -Path ([System.IO.Path]::GetTempPath()))
    )
    $allowed = $false
    foreach ($root in $allowedRoots) {
        try {
            $relative = Get-SwiftUIBaselineRelativePath -Root $root -Path $resolved
            if (-not [string]::IsNullOrEmpty($relative)) { $allowed = $true }
        } catch { }
    }
    if (-not $allowed) { throw 'OutputPath must be a new descendant of repository artifacts or OS temp.' }
    if (Test-Path -LiteralPath $resolved) { throw 'OutputPath already exists; no evidence is overwritten.' }
    $parent = Split-Path -Parent $resolved
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'The output parent must already exist.' }
    [void](New-Item -ItemType Directory -Path $resolved -ErrorAction Stop)
    foreach ($child in @('evidence', 'work')) { [void](New-Item -ItemType Directory -Path (Join-Path $resolved $child)) }
    return [pscustomobject]@{ root = $resolved; evidence = (Join-Path $resolved 'evidence'); work = (Join-Path $resolved 'work') }
}

function Get-SwiftUIStateObjectCaptureSources {
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)]$Matrix)
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($relative in (Get-SwiftUIStateObjectCapturePolicy).harnessPaths) {
        # The reviewed harness includes .github; evidence-relative names use a
        # deliberately narrower portable grammar and are not reused for this list.
        $path = Join-Path $RepositoryRoot $relative
        $hash = Get-SwiftUIStateObjectFileHash $path
        $files.Add([pscustomobject]@{ path = $relative; sha256 = $hash.sha256; bytes = $hash.bytes })
    }
    foreach ($source in $Matrix.sourceFiles) {
        $actual = Get-SwiftUIStateObjectFileHash $source.path -MaxBytes 1048576
        if ($actual.sha256 -cne $source.sha256 -or $actual.bytes -ne $source.bytes) { throw 'A frozen fixture changed after matrix intake.' }
        $files.Add([pscustomobject]@{ path = "scripts/fixtures/swiftui-stateobject-isolation/$($source.relativePath)"; sha256 = $actual.sha256; bytes = $actual.bytes })
    }
    return $files.ToArray()
}

function Get-SwiftUIStateObjectLiveFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$AllowedRoot,
        [long]$MaxBytes = 2147483647)
    if (-not [System.IO.Path]::IsPathRooted($Path) -or $Path -match '[\x00-\x1f\x7f]') { throw 'A pinned native file path must be absolute and control-free.' }
    [void](Get-SwiftUIBaselineRelativePath -Root $AllowedRoot -Path $Path)
    $canonical = Resolve-SwiftUIBaselineFileSystemPath -Path $Path
    $canonicalRoot = Resolve-SwiftUIBaselineFileSystemPath -Path $AllowedRoot
    [void](Get-SwiftUIBaselineRelativePath -Root $canonicalRoot -Path $canonical)
    $hash = Get-SwiftUIStateObjectFileHash -Path $canonical -MaxBytes $MaxBytes
    return [pscustomobject]@{ path = $Path; canonicalPath = $canonical; sha256 = $hash.sha256; bytes = $hash.bytes }
}

function Read-SwiftUIStateObjectSDKInputs {
    param([Parameter(Mandatory)][string]$CaptureRoot, [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ExpectedCaptureManifestSHA256)
    $policy = Get-SwiftUIStateObjectCapturePolicy
    Assert-SwiftUIStateObjectCaptureSHA256 $ExpectedCaptureManifestSHA256 'SDK capture hash'
    if ($ExpectedCaptureManifestSHA256 -cne $policy.captureManifestSHA256) { throw 'This matrix is bound to the reviewed source packet from capture 33135644721; a different capture requires a separately reviewed change.' }
    $root = Resolve-SwiftUIBaselineFileSystemPath -Path $CaptureRoot
    [void](Assert-SwiftUIStateObjectDirectory $root)
    $capturePath = Resolve-SwiftUIStateObjectEvidencePath $root 'capture.json'
    $captureRead = Read-SwiftUIStateObjectJson $capturePath -MaxBytes 16777216
    if ($captureRead.sha256 -cne $ExpectedCaptureManifestSHA256) { throw 'SDK capture hash differs from the explicitly requested capture.' }
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($relative in @('capture.json', 'capture-status.json', 'baseline-manifest.json', 'SDKSettings.json')) {
        $path = Resolve-SwiftUIStateObjectEvidencePath $root $relative
        $read = Read-SwiftUIStateObjectJson $path -MaxBytes 16777216
        $files.Add([pscustomobject]@{ path = $path; relativePath = $relative; sha256 = $read.sha256; bytes = $read.bytes })
    }
    $digest = Get-SwiftUIStateObjectFileHash (Resolve-SwiftUIStateObjectEvidencePath $root 'capture.sha256') -MaxBytes 1024
    $files.Add([pscustomobject]@{ path = $digest.path; relativePath = 'capture.sha256'; sha256 = $digest.sha256; bytes = $digest.bytes })
    $baselinePath = Join-Path $RepositoryRoot 'docs/swiftui-baseline.json'
    $baselineRead = Read-SwiftUIStateObjectJson $baselinePath
    if ($baselineRead.sha256 -cne $policy.baselineManifestSHA256) { throw 'The baseline manifest differs from the approved packet.' }
    # The existing validator checks the completed export, release identity,
    # baseline, recorded swift binary, and live SDK settings. Strict reads above
    # reject ambiguous JSON before that validator consumes the same files.
    $sdkContext = Read-SwiftUIMaterialSDKContext -CaptureRoot $root -ManifestPath $baselinePath
    $capture = $sdkContext.capture
    if ($capture.developerDirectoryOverride -cne $policy.developerDirectory -or $capture.sdk.path -cne $policy.sdkPath -or
        $capture.sdk.settingsSha256 -cne $policy.sdkSettingsSHA256) { throw 'Captured SDK/developer anchors differ from the sealed plan.' }
    foreach ($field in @('xcodeVersion', 'xcodeBuildVersion', 'sdkVersion', 'sdkBuildVersion', 'compilerVersionLine')) {
        $captureField = $field
        if ($field -ceq 'compilerVersionLine') { $captureField = 'swiftCompilerVersionLine' }
        if ($capture.observedIdentity.$captureField -cne $policy.$field) { throw "Captured $captureField differs from the sealed plan." }
    }
    $anchors = [System.Collections.Generic.List[object]]::new()
    foreach ($anchor in $policy.interfaceAnchors) {
        $records = @($capture.publicInterfaces | Where-Object { $_.path -ceq $anchor.path })
        if ($records.Count -ne 1 -or $records[0].sha256 -cne $anchor.sha256) { throw 'A selected captured SDK interface anchor is missing or changed.' }
        $record = $records[0]
        Assert-SwiftUIStateObjectRelativePath $record.sdkRelativeSource 'SDK interface relative path'
        $path = Resolve-SwiftUIStateObjectEvidencePath $root $anchor.path
        $hash = Get-SwiftUIStateObjectFileHash $path -MaxBytes 16777216
        if ($hash.sha256 -cne $anchor.sha256) { throw 'A captured interface differs from its sealed hash.' }
        $live = Get-SwiftUIStateObjectLiveFile -Path (Join-Path $policy.sdkPath $record.sdkRelativeSource) -AllowedRoot $policy.sdkPath -MaxBytes 16777216
        if ($live.sha256 -cne $anchor.sha256) { throw 'A live SDK interface differs from the selected captured interface.' }
        $files.Add([pscustomobject]@{ path = $path; relativePath = $anchor.path; sha256 = $hash.sha256; bytes = $hash.bytes })
        $anchors.Add([pscustomobject]@{
            capturePath = $anchor.path; sdkRelativeSource = $record.sdkRelativeSource; live = $live
            platform = $anchor.platform; interfaceArchitecture = $anchor.interfaceArchitecture
            producerCompiler = 'Apple Swift 6.3.2 effective-5.10'; producerModuleLanguageMode = '5'
        })
    }
    foreach ($file in $files) {
        $again = Get-SwiftUIStateObjectFileHash -Path $file.path -MaxBytes 16777216
        if ($again.sha256 -cne $file.sha256 -or $again.bytes -ne $file.bytes) { throw 'SDK source evidence changed during validation.' }
    }
    foreach ($pin in (Get-SwiftUIStateObjectCaptureFilePolicy)) {
        $actual = @($files | Where-Object { $_.relativePath -ceq $pin.path })
        if ($actual.Count -ne 1 -or $actual[0].sha256 -cne $pin.sha256) { throw 'Selected SDK evidence differs from the exact source packet.' }
    }
    return [pscustomobject]@{
        captureRoot = $root; context = $sdkContext; files = $files.ToArray()
        anchors = $anchors.ToArray(); baselinePath = $baselinePath
        canonicalSDKPath = (Resolve-SwiftUIBaselineFileSystemPath $policy.sdkPath)
        settings = (Get-SwiftUIStateObjectLiveFile -Path (Join-Path $policy.sdkPath 'SDKSettings.json') -AllowedRoot $policy.sdkPath -MaxBytes 1048576)
    }
}

function Assert-SwiftUIStateObjectProfileShape {
    param([Parameter(Mandatory)]$CompilerProfile, [Parameter(Mandatory)]$Matrix)
    Assert-SwiftUIStateObjectCaptureFields $CompilerProfile @(
        'schemaVersion', 'product', 'status', 'attemptID', 'createdAtUtc', 'caseRequests', 'captureManifestSHA256',
        'baselineManifestSHA256', 'matrixSHA256', 'matrixContentSHA256', 'clientFlags', 'targets',
        'source', 'sourceFiles', 'sdk', 'tools', 'nativeHost', 'metadataRequests', 'qualification') 'Compiler profile'
    $policy = Get-SwiftUIStateObjectCapturePolicy
    Assert-SwiftUIStateObjectInteger -Value $CompilerProfile.schemaVersion -Name 'Profile schemaVersion' -Minimum 1 -Maximum 1
    Assert-SwiftUIStateObjectInteger -Value $CompilerProfile.caseRequests -Name 'Profile caseRequests' -Minimum 0 -Maximum 0
    if ($CompilerProfile.schemaVersion -ne 1 -or $CompilerProfile.product -cne 'swiftui-stateobject-isolation-compiler-profile' -or
        $CompilerProfile.status -cne 'metadata-only-awaiting-review' -or $CompilerProfile.caseRequests -ne 0 -or
        $CompilerProfile.attemptID -cnotmatch '^[0-9a-f]{32}$' -or $CompilerProfile.captureManifestSHA256 -cne $policy.captureManifestSHA256 -or
        $CompilerProfile.baselineManifestSHA256 -cne $policy.baselineManifestSHA256) { throw 'Profile is not a completed metadata-only candidate for this packet.' }
    Assert-SwiftUIStateObjectCaptureSHA256 $CompilerProfile.matrixSHA256 'Profile matrix hash'
    if ($CompilerProfile.matrixSHA256 -cne $Matrix.sha256 -or $CompilerProfile.matrixContentSHA256 -cne $Matrix.contentSha256 -or
        (@($CompilerProfile.targets) -join '|') -cne (@($Matrix.targets) -join '|') -or
        (@($CompilerProfile.clientFlags) -join '|') -cne (@($Matrix.document.requiredFlags) -join '|')) { throw 'Profile matrix, targets, or strict client flags differ from this invocation.' }
    Assert-SwiftUIStateObjectNoQualification $CompilerProfile.qualification
    Assert-SwiftUIStateObjectCaptureFields $CompilerProfile.source @('commit', 'tree', 'trackedWorkingTree', 'workflow') 'Profile source'
    if ($CompilerProfile.source.commit -cnotmatch '^[0-9a-f]{40}$' -or $CompilerProfile.source.tree -cnotmatch '^[0-9a-f]{40}$' -or
        $CompilerProfile.source.trackedWorkingTree -cne '') { throw 'Profile must identify a clean committed source tree.' }
    if (@($CompilerProfile.sourceFiles).Count -ne ($policy.harnessPaths.Count + 24)) { throw 'Profile is missing exact fixture or harness source hashes.' }
    $expectedSourcePaths = @($policy.harnessPaths) + @($Matrix.sourceFiles | ForEach-Object { "scripts/fixtures/swiftui-stateobject-isolation/$($_.relativePath)" })
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $sourceIndex = 0
    foreach ($file in $CompilerProfile.sourceFiles) {
        Assert-SwiftUIStateObjectCaptureFields $file @('path', 'sha256', 'bytes') 'Profile source file'
        Assert-SwiftUIStateObjectCaptureSHA256 $file.sha256 'Profile source hash'
        if ($file.bytes -isnot [long] -and $file.bytes -isnot [int]) { throw 'Profile source size must be an integer.' }
        if ($file.bytes -lt 1 -or $file.bytes -gt 16777216 -or -not $seen.Add($file.path)) { throw 'Profile source record is invalid or duplicated.' }
        if ($file.path -cne $expectedSourcePaths[$sourceIndex]) { throw 'Profile source paths differ from the exact repository input set.' }
        if ($sourceIndex -ge $policy.harnessPaths.Count -and $file.sha256 -cne $Matrix.sourceFiles[$sourceIndex - $policy.harnessPaths.Count].sha256) { throw 'Profile changes a frozen public fixture hash.' }
        $sourceIndex++
    }
    Assert-SwiftUIStateObjectCaptureFields $CompilerProfile.sdk @('developerDirectory', 'path', 'canonicalPath', 'settings', 'anchors', 'captureFiles') 'Profile SDK'
    if ($CompilerProfile.sdk.developerDirectory -cne $policy.developerDirectory -or $CompilerProfile.sdk.path -cne $policy.sdkPath -or
        $CompilerProfile.sdk.settings.sha256 -cne $policy.sdkSettingsSHA256 -or @($CompilerProfile.sdk.anchors).Count -ne 6) { throw 'Profile SDK anchors differ from the sealed plan.' }
    Assert-SwiftUIStateObjectNativePath $CompilerProfile.sdk.canonicalPath
    Assert-SwiftUIStateObjectCaptureFields $CompilerProfile.sdk.settings @('path', 'canonicalPath', 'sha256', 'bytes') 'SDK settings pin'
    Assert-SwiftUIStateObjectInteger -Value $CompilerProfile.sdk.settings.bytes -Name 'SDK settings bytes' -Minimum 1 -Maximum 1048576
    Assert-SwiftUIStateObjectNativePath $CompilerProfile.sdk.settings.path
    Assert-SwiftUIStateObjectNativePath $CompilerProfile.sdk.settings.canonicalPath
    $capturePins = @(Get-SwiftUIStateObjectCaptureFilePolicy)
    Assert-SwiftUIStateObjectArray -Value $CompilerProfile.sdk.captureFiles -Name 'Profile capture files' -MaximumCount 11
    if ($CompilerProfile.sdk.captureFiles.Count -ne 11) { throw 'Profile must pin all eleven required captured source files.' }
    for ($i = 0; $i -lt 11; $i++) {
        $file = $CompilerProfile.sdk.captureFiles[$i]
        Assert-SwiftUIStateObjectCaptureFields $file @('path', 'sha256', 'bytes') 'Captured source pin'
        Assert-SwiftUIStateObjectInteger -Value $file.bytes -Name 'Captured source bytes' -Minimum 1 -Maximum 16777216
        if ($file.path -cne $capturePins[$i].path -or $file.sha256 -cne $capturePins[$i].sha256) { throw 'Profile captured source pins differ from the sealed source packet.' }
    }
    for ($i = 0; $i -lt 6; $i++) {
        $anchor = $CompilerProfile.sdk.anchors[$i]; $pin = $policy.interfaceAnchors[$i]
        Assert-SwiftUIStateObjectCaptureFields $anchor @('capturePath', 'sdkRelativeSource', 'live', 'platform', 'interfaceArchitecture', 'producerCompiler', 'producerModuleLanguageMode') 'SDK interface anchor'
        Assert-SwiftUIStateObjectCaptureFields $anchor.live @('path', 'canonicalPath', 'sha256', 'bytes') 'SDK interface file'
        Assert-SwiftUIStateObjectNativePath $anchor.live.path
        Assert-SwiftUIStateObjectNativePath $anchor.live.canonicalPath
        Assert-SwiftUIStateObjectInteger -Value $anchor.live.bytes -Name 'SDK interface bytes' -Minimum 1 -Maximum 16777216
        $parts = $pin.path.Split('/')
        $relative = "System/Library/Frameworks/$($parts[1]).framework/Modules/$($parts[1]).swiftmodule/$($parts[2])"
        if ($anchor.capturePath -cne $pin.path -or $anchor.sdkRelativeSource -cne $relative -or $anchor.live.path -cne "$($policy.sdkPath)/$relative" -or
            $anchor.live.sha256 -cne $pin.sha256 -or $anchor.platform -cne $pin.platform -or $anchor.interfaceArchitecture -cne $pin.interfaceArchitecture -or
            $anchor.producerCompiler -cne 'Apple Swift 6.3.2 effective-5.10' -or $anchor.producerModuleLanguageMode -cne '5') { throw 'Profile conflates or changes the selected SDK interface/producer anchors.' }
    }
    if (@($CompilerProfile.tools).Count -ne 2) { throw 'Profile must separately pin swiftc and swift-frontend.' }
    $toolNames = @($CompilerProfile.tools | ForEach-Object { $_.name })
    if (($toolNames -join '|') -cne 'swiftc|swift-frontend') { throw 'Profile must name swiftc and swift-frontend in the reviewed order.' }
    foreach ($tool in $CompilerProfile.tools) {
        Assert-SwiftUIStateObjectCaptureFields $tool @('name', 'file', 'versionOutput', 'targetInfo') 'Compiler tool'
        Assert-SwiftUIStateObjectCaptureFields $tool.file @('path', 'canonicalPath', 'sha256', 'bytes') 'Compiler file'
        Assert-SwiftUIStateObjectCaptureSHA256 $tool.file.sha256 'Compiler executable hash'
        Assert-SwiftUIStateObjectInteger -Value $tool.file.bytes -Name 'Compiler executable bytes' -Minimum 1 -Maximum 2147483647
        Assert-SwiftUIStateObjectNativePath $tool.file.path
        Assert-SwiftUIStateObjectNativePath $tool.file.canonicalPath
        if ($tool.file.bytes -lt 1 -or $tool.file.bytes -gt 2147483647 -or
            $tool.file.path -cne "$($policy.developerDirectory)/Toolchains/XcodeDefault.xctoolchain/usr/bin/$($tool.name)" -or
            [string]::IsNullOrWhiteSpace($tool.file.canonicalPath)) { throw 'Profile has missing or unsupported executable pins.' }
        if ($tool.versionOutput -isnot [string] -or $tool.versionOutput.IndexOf($policy.compilerVersionLine, [System.StringComparison]::Ordinal) -lt 0 -or
            @($tool.targetInfo).Count -ne 2) { throw 'Compiler version or target metadata is missing.' }
        for ($i = 0; $i -lt 2; $i++) {
            $info = $tool.targetInfo[$i]
            Assert-SwiftUIStateObjectCaptureFields $info @('target', 'compilerVersion', 'triple', 'rawSHA256') 'Target metadata'
            Assert-SwiftUIStateObjectCaptureSHA256 $info.rawSHA256 'Target metadata hash'
            if ($info.target -cne $Matrix.targets[$i] -or $info.triple -cne $Matrix.targets[$i] -or
                $info.compilerVersion -cne $policy.compilerVersionLine) { throw 'Compiler target metadata does not describe the requested desktop target.' }
        }
    }
    Assert-SwiftUIStateObjectCaptureFields $CompilerProfile.nativeHost @('macOSVersion', 'macOSBuildVersion', 'architecture', 'powerShellVersion') 'Native metadata host'
    if ($CompilerProfile.nativeHost.macOSVersion -cnotmatch '^26\.[0-9]+(?:\.[0-9]+)?$' -or
        $CompilerProfile.nativeHost.macOSBuildVersion -cnotmatch '^[0-9]+[A-Z][0-9]+[a-z]?$' -or
        $CompilerProfile.nativeHost.architecture -cnotin @('x86_64', 'arm64') -or $CompilerProfile.nativeHost.powerShellVersion -cnotmatch '^7\.') {
        throw 'Profile lacks an actual supported native metadata host identity.'
    }
    $expectedIDs = @('xcode-version', 'sdk-path', 'sdk-version', 'sdk-build',
        'find-swiftc', 'swiftc-version', 'swiftc-target-x86_64', 'swiftc-target-arm64',
        'find-swift-frontend', 'swift-frontend-version', 'swift-frontend-target-x86_64', 'swift-frontend-target-arm64',
        'host-version', 'host-build', 'host-architecture')
    if (@($CompilerProfile.metadataRequests).Count -ne $expectedIDs.Count) { throw 'Profile has no complete raw metadata request inventory.' }
    for ($i = 0; $i -lt $expectedIDs.Count; $i++) {
        $request = $CompilerProfile.metadataRequests[$i]
        Assert-SwiftUIStateObjectCaptureFields $request @('id', 'filePath', 'canonicalPath', 'executableSHA256', 'executableBytes',
            'arguments', 'workingDirectory', 'environment', 'stdoutPath', 'stderrPath', 'process') 'Metadata request'
        if ($request.id -cne $expectedIDs[$i] -or $request.stdoutPath -cne "metadata/$($request.id).stdout.txt" -or
            $request.stderrPath -cne "metadata/$($request.id).stderr.txt") { throw 'Profile metadata request identity/order differs from the fixed plan.' }
        Assert-SwiftUIStateObjectCaptureSHA256 $request.executableSHA256 'Metadata tool hash'
        Assert-SwiftUIStateObjectInteger -Value $request.executableBytes -Name 'Metadata tool bytes' -Minimum 1 -Maximum 2147483647
        Assert-SwiftUIStateObjectNativePath $request.filePath
        Assert-SwiftUIStateObjectNativePath $request.canonicalPath
        Assert-SwiftUIStateObjectNativePath $request.workingDirectory
        Assert-SwiftUIStateObjectExecutionEnvironment $request.environment
        if ($request.executableBytes -lt 1 -or $request.executableBytes -gt 2147483647 -or
            -not [System.IO.Path]::IsPathRooted($request.canonicalPath) -or -not [System.IO.Path]::IsPathRooted($request.workingDirectory)) { throw 'Metadata native file identity is incomplete.' }
        $expected = Get-SwiftUIStateObjectMetadataCommand -ID $request.id -Tools $CompilerProfile.tools
        if ($request.filePath -cne $expected.filePath -or @($request.arguments).Count -ne $expected.arguments.Count) { throw 'Profile contains an unexpected metadata command.' }
        for ($j = 0; $j -lt $expected.arguments.Count; $j++) {
            if ($request.arguments[$j] -cne $expected.arguments[$j]) { throw 'Profile metadata argv differs from the fixed non-compiling plan.' }
        }
        $process = $request.process
        Assert-SwiftUIStateObjectRawProcess -Value $process -MaxCombinedBytes 262144
        foreach ($field in @('processStarted', 'terminationCompleted', 'allRedirectedStreamsClosed')) {
            if ($process.$field -isnot [bool] -or -not $process.$field) { throw 'Profile includes an incomplete metadata process.' }
        }
        foreach ($field in @('timedOut', 'outputLimitExceeded')) {
            if ($process.$field -isnot [bool] -or $process.$field) { throw 'Profile includes a bounded metadata process failure.' }
        }
        if ($process.exitCode -ne 0 -or $null -ne $process.error -or @($process.cleanupErrors).Count -ne 0 -or
            $process.stdoutBytes -lt 0 -or $process.stderrBytes -lt 0 -or $process.stdoutBytes + $process.stderrBytes -gt 262144) { throw 'Profile includes an unsuccessful metadata process.' }
        Assert-SwiftUIStateObjectCaptureSHA256 $process.stdoutSha256 'Metadata stdout hash'
        Assert-SwiftUIStateObjectCaptureSHA256 $process.stderrSha256 'Metadata stderr hash'
    }
}

function Get-SwiftUIStateObjectMetadataCommand {
    param([Parameter(Mandatory)][string]$ID, [Parameter(Mandatory)][object[]]$Tools)
    $policy = Get-SwiftUIStateObjectCapturePolicy
    switch -CaseSensitive ($ID) {
        'xcode-version' { return [pscustomobject]@{ filePath = '/usr/bin/xcodebuild'; arguments = @('-version') } }
        'sdk-path' { return [pscustomobject]@{ filePath = '/usr/bin/xcrun'; arguments = @('--sdk', 'macosx', '--show-sdk-path') } }
        'sdk-version' { return [pscustomobject]@{ filePath = '/usr/bin/xcrun'; arguments = @('--sdk', 'macosx', '--show-sdk-version') } }
        'sdk-build' { return [pscustomobject]@{ filePath = '/usr/bin/xcrun'; arguments = @('--sdk', 'macosx', '--show-sdk-build-version') } }
        'host-version' { return [pscustomobject]@{ filePath = '/usr/bin/sw_vers'; arguments = @('-productVersion') } }
        'host-build' { return [pscustomobject]@{ filePath = '/usr/bin/sw_vers'; arguments = @('-buildVersion') } }
        'host-architecture' { return [pscustomobject]@{ filePath = '/usr/bin/uname'; arguments = @('-m') } }
    }
    foreach ($tool in $Tools) {
        if ($ID -ceq "find-$($tool.name)") { return [pscustomobject]@{ filePath = '/usr/bin/xcrun'; arguments = @('--toolchain', 'XcodeDefault', '--find', $tool.name) } }
        if ($ID -ceq "$($tool.name)-version") {
            $flag = '--version'; if ($tool.name -ceq 'swift-frontend') { $flag = '-version' }
            return [pscustomobject]@{ filePath = $tool.file.canonicalPath; arguments = @($flag) }
        }
        foreach ($arch in @('x86_64', 'arm64')) {
            if ($ID -ceq "$($tool.name)-target-$arch") {
                return [pscustomobject]@{ filePath = $tool.file.canonicalPath; arguments = @('-print-target-info', '-sdk', $policy.sdkPath, '-target', "$arch-apple-macosx26.5") }
            }
        }
    }
    throw 'Unknown metadata command identifier.'
}

function Read-SwiftUIStateObjectReviewedProfile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ReviewedProfileSHA256,
        [Parameter(Mandatory)][string]$ReviewedMatrixSHA256, [Parameter(Mandatory)]$Matrix)
    Assert-SwiftUIStateObjectCaptureSHA256 $ReviewedProfileSHA256 'Explicit reviewed profile hash'
    Assert-SwiftUIStateObjectCaptureSHA256 $ReviewedMatrixSHA256 'Explicit reviewed matrix hash'
    if ($ReviewedMatrixSHA256 -cne $Matrix.sha256) { throw 'The caller has not supplied this exact matrix hash.' }
    if ([System.IO.Path]::GetFileName($Path) -cne 'profile.json') { throw 'The explicit reviewed path must name the packet profile.json.' }
    $declaredPath = Resolve-SwiftUIStateObjectEvidencePath -Root (Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))) -RelativePath 'profile.json'
    if ([System.IO.Path]::GetFullPath($Path) -cne $declaredPath) { throw 'The explicit reviewed path differs from the declared packet profile.json.' }
    $read = Read-SwiftUIStateObjectJson -Path $Path -MaxBytes 4194304
    if ($read.sha256 -cne $ReviewedProfileSHA256) { throw 'The profile does not match the explicit reviewed profile hash.' }
    Assert-SwiftUIStateObjectProfileShape -CompilerProfile $read.document -Matrix $Matrix
    $packet = Read-SwiftUIStateObjectCompletedEvidence -Root (Split-Path -Parent $Path)
    if ($packet.manifest.mode -cne 'metadata-only' -or $packet.manifest.status -cne 'metadata-only-awaiting-review' -or
        $packet.manifest.compilerProfileSHA256 -cne $read.sha256 -or $packet.manifest.profileFile.path -cne 'profile.json' -or
        $packet.manifest.profileFile.sha256 -cne $read.sha256 -or $packet.manifest.profileFile.bytes -ne $read.bytes -or $packet.manifest.matrixSHA256 -cne $Matrix.sha256 -or
        $packet.manifest.attemptID -cne $read.document.attemptID -or $packet.manifest.caseRequests -ne 0) {
        throw 'The reviewed profile lacks its matching completed metadata-only evidence manifest.'
    }
    return $read
}

function Assert-SwiftUIStateObjectProfileMetadataStreams {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$CompilerProfile)
    foreach ($request in $CompilerProfile.metadataRequests) {
        foreach ($stream in @('stdout', 'stderr')) {
            $name = $request.($stream + 'Path')
            $file = Get-SwiftUIStateObjectFileHash (Resolve-SwiftUIStateObjectEvidencePath $Root $name) -MaxBytes 262144
            if ($file.sha256 -cne $request.process.($stream + 'Sha256') -or $file.bytes -ne $request.process.($stream + 'Bytes')) {
                throw 'Reviewed profile metadata streams disagree with the archived process records.'
            }
        }
        $raw = Read-SwiftUIStateObjectJson (Resolve-SwiftUIStateObjectEvidencePath $Root "metadata/$($request.id).request.json")
        if (($raw.document | ConvertTo-Json -Depth 30 -Compress) -cne ($request | ConvertTo-Json -Depth 30 -Compress)) { throw 'Reviewed profile metadata request differs from its archived record.' }
    }
    foreach ($tool in $CompilerProfile.tools) {
        $versionBytes = Read-SwiftUIStateObjectBoundedBytes (Resolve-SwiftUIStateObjectEvidencePath $root "metadata/$($tool.name)-version.stdout.txt") -MaxBytes 262144
        $version = [System.Text.UTF8Encoding]::new($false, $true).GetString($versionBytes.rawBytes)
        if ($version -cne $tool.versionOutput) { throw 'Profile version text disagrees with its archived native output.' }
        $findBytes = Read-SwiftUIStateObjectBoundedBytes (Resolve-SwiftUIStateObjectEvidencePath $root "metadata/find-$($tool.name).stdout.txt") -MaxBytes 262144
        if ([System.Text.UTF8Encoding]::new($false, $true).GetString($findBytes.rawBytes).Trim() -cne $tool.file.path) { throw 'Profile tool path disagrees with actual tool lookup.' }
        foreach ($info in $tool.targetInfo) {
            $arch = $info.target.Split('-')[0]
            $request = @($CompilerProfile.metadataRequests | Where-Object { $_.id -ceq "$($tool.name)-target-$arch" })[0]
            $targetRead = Read-SwiftUIStateObjectJson (Resolve-SwiftUIStateObjectEvidencePath $root $request.stdoutPath) -MaxBytes 262144
            if ($targetRead.sha256 -cne $info.rawSHA256 -or $targetRead.document.compilerVersion -cne $info.compilerVersion -or
                $targetRead.document.target.triple -cne $info.target -or $request.executableSHA256 -cne $tool.file.sha256 -or
                $request.executableBytes -ne $tool.file.bytes -or $request.canonicalPath -cne $tool.file.canonicalPath) { throw 'Profile target information disagrees with its actual compiler and raw output.' }
        }
    }
}

function Assert-SwiftUIStateObjectProfileSnapshot {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$CompilerProfile, [Parameter(Mandatory)]$Matrix)
    $sourceRoot = Resolve-SwiftUIStateObjectEvidencePath $Root 'sources'
    $snapshotMatrix = Read-SwiftUIStateObjectMatrix -Path (Join-Path $sourceRoot 'matrix.json') -SourceRoot $sourceRoot
    if ($snapshotMatrix.sha256 -cne $Matrix.sha256 -or $snapshotMatrix.contentSha256 -cne $Matrix.contentSha256) { throw 'Profile source snapshot has a different matrix.' }
    $policy = Get-SwiftUIStateObjectCapturePolicy
    foreach ($file in $CompilerProfile.sourceFiles) {
        $relative = $null
        if ($file.path -cin $policy.harnessPaths) { $relative = 'sources/harness/' + [System.IO.Path]::GetFileName($file.path) }
        else { $relative = 'sources/' + $file.path.Substring('scripts/fixtures/swiftui-stateobject-isolation/'.Length) }
        $hash = Get-SwiftUIStateObjectFileHash (Resolve-SwiftUIStateObjectEvidencePath $Root $relative) -MaxBytes 16777216
        if ($hash.sha256 -cne $file.sha256 -or $hash.bytes -ne $file.bytes) { throw 'Profile copied source or harness differs from its reviewed pin.' }
    }
    foreach ($file in $CompilerProfile.sdk.captureFiles) {
        $hash = Get-SwiftUIStateObjectFileHash (Resolve-SwiftUIStateObjectEvidencePath $Root "sdk/$($file.path)") -MaxBytes 16777216
        if ($hash.sha256 -cne $file.sha256 -or $hash.bytes -ne $file.bytes) { throw 'Profile copied SDK evidence differs from its reviewed pin.' }
    }
    $settings = @($CompilerProfile.sdk.captureFiles | Where-Object { $_.path -ceq 'SDKSettings.json' })[0]
    if ($settings.bytes -ne $CompilerProfile.sdk.settings.bytes -or $settings.sha256 -cne $CompilerProfile.sdk.settings.sha256) { throw 'Copied and live SDK settings pins disagree.' }
    foreach ($anchor in $CompilerProfile.sdk.anchors) {
        $file = @($CompilerProfile.sdk.captureFiles | Where-Object { $_.path -ceq $anchor.capturePath })[0]
        if ($file.bytes -ne $anchor.live.bytes -or $file.sha256 -cne $anchor.live.sha256) { throw 'Copied and live SDK interface pins disagree.' }
    }
    $inputs = Read-SwiftUIStateObjectJson (Resolve-SwiftUIStateObjectEvidencePath $Root 'source-inputs.json')
    Assert-SwiftUIStateObjectCaptureFields $inputs.document @('source', 'files', 'matrixSHA256', 'captureManifestSHA256') 'Profile source-input receipt'
    if ($inputs.document.matrixSHA256 -cne $Matrix.sha256 -or $inputs.document.captureManifestSHA256 -cne $CompilerProfile.captureManifestSHA256 -or
        ($inputs.document.files | ConvertTo-Json -Depth 30 -Compress) -cne ($CompilerProfile.sourceFiles | ConvertTo-Json -Depth 30 -Compress) -or
        ($inputs.document.source | ConvertTo-Json -Depth 30 -Compress) -cne ($CompilerProfile.source | ConvertTo-Json -Depth 30 -Compress)) { throw 'Profile source-input receipt differs from the reviewed source identity.' }
}

function Assert-SwiftUIStateObjectProfileInputs {
    param([Parameter(Mandatory)]$CompilerProfile, [Parameter(Mandatory)]$Matrix,
        [Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)]$SDKInputs)
    Assert-SwiftUIStateObjectProfileShape -CompilerProfile $CompilerProfile -Matrix $Matrix
    $current = @(Get-SwiftUIStateObjectCaptureSources -RepositoryRoot $RepositoryRoot -Matrix $Matrix)
    if ($current.Count -ne @($CompilerProfile.sourceFiles).Count) { throw 'Profile source inventory is incomplete.' }
    for ($i = 0; $i -lt $current.Count; $i++) {
        $pin = $CompilerProfile.sourceFiles[$i]
        if ($current[$i].path -cne $pin.path -or $current[$i].sha256 -cne $pin.sha256 -or $current[$i].bytes -ne $pin.bytes) { throw 'Fixture or harness source bytes changed after profile review.' }
    }
    foreach ($tool in $CompilerProfile.tools) {
        $live = Get-SwiftUIStateObjectLiveFile -Path $tool.file.path -AllowedRoot $CompilerProfile.sdk.developerDirectory
        if ($live.canonicalPath -cne $tool.file.canonicalPath -or $live.sha256 -cne $tool.file.sha256 -or $live.bytes -ne $tool.file.bytes) { throw 'A compiler or frontend executable changed after profile review.' }
    }
    $settings = Get-SwiftUIStateObjectLiveFile -Path $CompilerProfile.sdk.settings.path -AllowedRoot $CompilerProfile.sdk.path -MaxBytes 1048576
    if ($settings.sha256 -cne $CompilerProfile.sdk.settings.sha256 -or $settings.canonicalPath -cne $CompilerProfile.sdk.settings.canonicalPath -or
        (Resolve-SwiftUIBaselineFileSystemPath $CompilerProfile.sdk.path) -cne $CompilerProfile.sdk.canonicalPath) { throw 'Live SDK settings or SDK canonical path changed after review.' }
    for ($i = 0; $i -lt 6; $i++) {
        $currentAnchor = $SDKInputs.anchors[$i]; $pin = $CompilerProfile.sdk.anchors[$i]
        if ($currentAnchor.capturePath -cne $pin.capturePath -or $currentAnchor.sdkRelativeSource -cne $pin.sdkRelativeSource -or
            $currentAnchor.platform -cne $pin.platform -or $currentAnchor.interfaceArchitecture -cne $pin.interfaceArchitecture -or
            $currentAnchor.live.path -cne $pin.live.path -or $currentAnchor.live.sha256 -cne $pin.live.sha256) { throw 'Profile interface anchors disagree with the selected capture.' }
        $live = Get-SwiftUIStateObjectLiveFile -Path $currentAnchor.live.path -AllowedRoot $CompilerProfile.sdk.path -MaxBytes 16777216
        if ($live.canonicalPath -cne $pin.live.canonicalPath -or $live.sha256 -cne $pin.live.sha256 -or $live.bytes -ne $pin.live.bytes) { throw 'A live SDK interface changed after profile review.' }
    }
    foreach ($file in $SDKInputs.files) {
        $currentFile = Get-SwiftUIStateObjectFileHash $file.path -MaxBytes 16777216
        if ($currentFile.sha256 -cne $file.sha256 -or $currentFile.bytes -ne $file.bytes) { throw 'The selected capture changed during the attempt.' }
    }
}

function Get-SwiftUIStateObjectEvidenceInventory {
    param([Parameter(Mandatory)][string]$Root)
    $directory = Assert-SwiftUIStateObjectDirectory $Root
    $pending = [System.Collections.Generic.Stack[object]]::new()
    $pending.Push([pscustomobject]@{ path = $directory.FullName; depth = 0 })
    $files = [System.Collections.Generic.List[object]]::new()
    $entryCount = 0; $totalBytes = [long]0
    while ($pending.Count -gt 0) {
        $next = $pending.Pop()
        foreach ($item in (Get-ChildItem -LiteralPath $next.path -Force)) {
            $entryCount++
            if ($entryCount -gt 768 -or $next.depth -gt 12) { throw 'Evidence directory exceeds its bounded file/depth inventory.' }
            if ($item -is [System.IO.DirectoryInfo]) {
                [void](Assert-SwiftUIStateObjectDirectory $item.FullName)
                $pending.Push([pscustomobject]@{ path = $item.FullName; depth = $next.depth + 1 })
                continue
            }
            $relative = Get-SwiftUIBaselineRelativePath -Root $directory.FullName -Path $item.FullName
            if ($relative -cin @('manifest.json', 'manifest.sha256')) { continue }
            Assert-SwiftUIStateObjectRelativePath $relative 'Evidence inventory path'
            $hash = Get-SwiftUIStateObjectFileHash -Path $item.FullName -MaxBytes 16777216
            $totalBytes += $hash.bytes
            if ($totalBytes -gt 536870912 -or $files.Count -ge 512) { throw 'Evidence archive exceeds its bounded file/byte inventory.' }
            $files.Add([pscustomobject]@{ path = $relative; sha256 = $hash.sha256; bytes = $hash.bytes })
        }
    }
    return @($files.ToArray() | Sort-Object -Property path -CaseSensitive)
}

function Read-SwiftUIStateObjectCompletedEvidence {
    param([Parameter(Mandatory)][string]$Root)
    $manifestPath = Resolve-SwiftUIStateObjectEvidencePath $Root 'manifest.json'
    $read = Read-SwiftUIStateObjectJson -Path $manifestPath -MaxBytes 4194304 -MaxDepth 48
    $manifest = $read.document
    Assert-SwiftUIStateObjectCaptureFields $manifest @(
        'schemaVersion', 'product', 'mode', 'attemptID', 'status', 'startedAtUtc', 'finishedAtUtc', 'source', 'executionHost',
        'captureManifestSHA256', 'matrixSHA256', 'compilerProfileSHA256', 'reviewedProfileSHA256', 'reviewedMatrixSHA256',
        'profileFile', 'caseRequests', 'unconfirmedCaseRequests', 'expectedCaseRequests', 'results', 'disagreements', 'issues', 'artifactFiles', 'qualification') 'Evidence manifest'
    foreach ($field in @('schemaVersion', 'caseRequests', 'unconfirmedCaseRequests', 'expectedCaseRequests')) {
        Assert-SwiftUIStateObjectInteger -Value $manifest.$field -Name "Manifest $field" -Minimum 0 -Maximum 42
    }
    if ($manifest.schemaVersion -ne 1 -or $manifest.product -cne 'swiftui-stateobject-isolation' -or
        $manifest.mode -cnotin @('metadata-only', 'cases') -or $manifest.attemptID -cnotmatch '^[0-9a-f]{32}$' -or
        $manifest.status -cnotin @('metadata-only-awaiting-review', 'complete-characterization-candidate') -or
        @($manifest.issues).Count -ne 0 -or $manifest.unconfirmedCaseRequests -ne 0) { throw 'Evidence manifest is incomplete, unsupported, or blocked.' }
    Assert-SwiftUIStateObjectNoQualification $manifest.qualification
    Assert-SwiftUIStateObjectCaptureFields $manifest.profileFile @('path', 'sha256', 'bytes') 'Manifest profile file'
    Assert-SwiftUIStateObjectInteger -Value $manifest.profileFile.bytes -Name 'Manifest profile bytes' -Minimum 1 -Maximum 4194304
    Assert-SwiftUIStateObjectCaptureFields $manifest.disagreements @('safety', 'controls', 'collectionSuccessDoesNotApproveSafety') 'Manifest disagreement counts'
    foreach ($field in @('safety', 'controls')) { Assert-SwiftUIStateObjectInteger -Value $manifest.disagreements.$field -Name "Manifest disagreements $field" -Minimum 0 -Maximum 42 }
    if ($manifest.disagreements.collectionSuccessDoesNotApproveSafety -isnot [bool] -or -not $manifest.disagreements.collectionSuccessDoesNotApproveSafety) { throw 'Collection success cannot approve safety.' }
    $digestPath = Resolve-SwiftUIStateObjectEvidencePath $Root 'manifest.sha256'
    $digest = Read-SwiftUIStateObjectBoundedBytes $digestPath -MaxBytes 256
    $digestText = [System.Text.UTF8Encoding]::new($false, $true).GetString($digest.rawBytes)
    if ($digestText -cne "$($read.sha256)  manifest.json`n") { throw 'Manifest digest is missing or inconsistent.' }
    $current = @(Get-SwiftUIStateObjectEvidenceInventory $Root)
    if ($current.Count -ne @($manifest.artifactFiles).Count) { throw 'The evidence archive has missing or extra files.' }
    for ($i = 0; $i -lt $current.Count; $i++) {
        $pin = $manifest.artifactFiles[$i]
        Assert-SwiftUIStateObjectCaptureFields $pin @('path', 'sha256', 'bytes') 'Archived file'
        Assert-SwiftUIStateObjectInteger -Value $pin.bytes -Name 'Archived file bytes' -Minimum 0 -Maximum 16777216
        if ($current[$i].path -cne $pin.path -or $current[$i].sha256 -cne $pin.sha256 -or $current[$i].bytes -ne $pin.bytes) { throw 'The evidence archive changed after finalization.' }
    }
    if ($manifest.mode -ceq 'metadata-only') {
        if ($manifest.status -cne 'metadata-only-awaiting-review' -or $manifest.caseRequests -ne 0 -or
            $manifest.expectedCaseRequests -ne 0 -or @($manifest.results).Count -ne 0) { throw 'Metadata-only evidence must not contain compiler case requests.' }
        $profilePath = Resolve-SwiftUIStateObjectEvidencePath $Root 'profile.json'
        $profileRead = Read-SwiftUIStateObjectJson $profilePath -MaxBytes 4194304
        $snapshotRoot = Resolve-SwiftUIStateObjectEvidencePath $Root 'sources'
        $snapshotMatrix = Read-SwiftUIStateObjectMatrix -Path (Join-Path $snapshotRoot 'matrix.json') -SourceRoot $snapshotRoot
        if ($profileRead.sha256 -cne $manifest.compilerProfileSHA256 -or $manifest.profileFile.path -cne 'profile.json' -or
            $manifest.profileFile.sha256 -cne $profileRead.sha256 -or $manifest.profileFile.bytes -ne $profileRead.bytes -or
            $snapshotMatrix.sha256 -cne $manifest.matrixSHA256) { throw 'Metadata packet profile or source matrix does not match its final manifest.' }
        Assert-SwiftUIStateObjectProfileShape -CompilerProfile $profileRead.document -Matrix $snapshotMatrix
        Assert-SwiftUIStateObjectProfileSnapshot -Root $Root -CompilerProfile $profileRead.document -Matrix $snapshotMatrix
        Assert-SwiftUIStateObjectProfileMetadataStreams -Root $Root -CompilerProfile $profileRead.document
        if ($manifest.attemptID -cne $profileRead.document.attemptID -or $manifest.captureManifestSHA256 -cne $profileRead.document.captureManifestSHA256 -or
            ($manifest.source | ConvertTo-Json -Depth 30 -Compress) -cne ($profileRead.document.source | ConvertTo-Json -Depth 30 -Compress) -or
            ($manifest.executionHost | ConvertTo-Json -Depth 20 -Compress) -cne ($profileRead.document.nativeHost | ConvertTo-Json -Depth 20 -Compress)) { throw 'Metadata manifest contradicts its profile source/host identity.' }
    } else {
        if ($manifest.status -cne 'complete-characterization-candidate' -or $manifest.caseRequests -ne 42 -or
            $manifest.expectedCaseRequests -ne 42 -or @($manifest.results).Count -ne 42) { throw 'A complete case packet must account for all 42 executed requests.' }
        Assert-SwiftUIStateObjectCompletedCaseRecords -Root $Root -Manifest $manifest
    }
    return [pscustomobject]@{ manifest = $manifest; sha256 = $read.sha256; path = $manifestPath }
}

function Assert-SwiftUIStateObjectCompletedCaseRecords {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$Manifest)
    $sourceRoot = Resolve-SwiftUIStateObjectEvidencePath $Root 'sources'
    $matrix = Read-SwiftUIStateObjectMatrix -Path (Join-Path $sourceRoot 'matrix.json') -SourceRoot $sourceRoot
    if ($matrix.sha256 -cne $Manifest.matrixSHA256 -or $Manifest.reviewedMatrixSHA256 -cne $matrix.sha256 -or
        $Manifest.compilerProfileSHA256 -cne $Manifest.reviewedProfileSHA256 -or $Manifest.profileFile.path -cne 'reviewed-profile/profile.json' -or
        $Manifest.profileFile.sha256 -cne $Manifest.compilerProfileSHA256) { throw 'Case packet does not reference its explicit profile and matrix review receipts.' }
    $profilePath = Resolve-SwiftUIStateObjectEvidencePath $Root 'reviewed-profile/profile.json'
    $reviewed = Read-SwiftUIStateObjectReviewedProfile -Path $profilePath -ReviewedProfileSHA256 $Manifest.reviewedProfileSHA256 `
        -ReviewedMatrixSHA256 $Manifest.reviewedMatrixSHA256 -Matrix $matrix
    if ($Manifest.captureManifestSHA256 -cne $reviewed.document.captureManifestSHA256 -or
        ($Manifest.executionHost | ConvertTo-Json -Depth 20 -Compress) -cne ($reviewed.document.nativeHost | ConvertTo-Json -Depth 20 -Compress)) { throw 'Case packet host or capture differs from the reviewed profile.' }
    $prior = [System.Collections.Generic.List[object]]::new()
    $ordinal = 0
    foreach ($target in $matrix.targets) {
        $index = 0
        foreach ($case in $matrix.cases) {
            $index++; $result = $Manifest.results[$ordinal]; $ordinal++
            Assert-SwiftUIStateObjectInteger -Value $result.ordinal -Name 'Case ordinal' -Minimum 1 -Maximum 42
            if ($result.ordinal -ne $ordinal -or $result.target -cne $target -or $result.caseID -cne $case.caseID -or
                $result.launchState -cne 'confirmed-started' -or $null -ne $result.collectionError -or $null -eq $result.raw -or
                $null -eq $result.process -or $null -eq $result.assessment) { throw 'Case packet differs from the exact 21-case/two-target order or contains an incomplete record.' }
            Assert-SwiftUIStateObjectAssessment $result.assessment
            if ($result.assessment.attemptID -cne $Manifest.attemptID -or $result.assessment.compilerProfileSHA256 -cne $Manifest.compilerProfileSHA256 -or
                $result.assessment.target -cne $target -or $result.assessment.caseID -cne $case.caseID -or
                $result.assessment.observedOutcome -cnotin @('source-admitted', 'source-rejected')) { throw 'Case assessment belongs to a different scope or is not an ordinary source observation.' }
            $raw = $result.raw
            Assert-SwiftUIStateObjectCaptureFields $raw @('attemptID', 'target', 'caseID', 'compilerProfileSHA256', 'filePath', 'arguments',
                'workingDirectory', 'environment', 'timeoutSeconds', 'stdoutPath', 'stderrPath', 'sourceFiles', 'process') 'Archived case request'
            Assert-SwiftUIStateObjectInteger -Value $raw.timeoutSeconds -Name 'Request timeoutSeconds' -Minimum 1 -Maximum 120
            Assert-SwiftUIStateObjectRawProcess -Value $raw.process -MaxCombinedBytes 1048576
            Assert-SwiftUIStateObjectExecutionEnvironment $raw.environment
            Assert-SwiftUIStateObjectNativePath $raw.filePath
            Assert-SwiftUIStateObjectNativePath $raw.workingDirectory
            $arch = $target.Split('-')[0]; $module = 'SOI_{0:D2}_{1}' -f $index, $arch
            $prefix = "requests/$arch/$module"
            if ($raw.attemptID -cne $Manifest.attemptID -or $raw.target -cne $target -or $raw.caseID -cne $case.caseID -or
                $raw.compilerProfileSHA256 -cne $Manifest.compilerProfileSHA256 -or $raw.stdoutPath -cne "$prefix/stdout.txt" -or
                $raw.stderrPath -cne "$prefix/stderr.txt" -or $raw.filePath -cne $reviewed.document.tools[0].file.canonicalPath -or
                $raw.timeoutSeconds -lt 1 -or $raw.timeoutSeconds -gt 120) { throw 'Raw compiler invocation differs from its case, tool, or bounded process policy.' }
            $saved = Read-SwiftUIStateObjectJson (Resolve-SwiftUIStateObjectEvidencePath $Root "$prefix/request.json")
            if (($saved.document | ConvertTo-Json -Depth 30 -Compress) -cne ($raw | ConvertTo-Json -Depth 30 -Compress)) { throw 'Case manifest differs from the archived request record.' }
            $sources = @($matrix.sourceFiles | Where-Object { $_.relativePath -cin (@($case.sharedSources) + @($case.source)) })
            if (@($raw.sourceFiles).Count -ne $sources.Count) { throw 'Case source mapping is incomplete.' }
            $paths = [ordered]@{}; $originalSourceRoot = $null
            foreach ($source in $sources) {
                $matches = @($raw.sourceFiles | Where-Object { $_.relativePath -ceq $source.relativePath })
                if ($matches.Count -ne 1) { throw 'Case source mapping is missing or duplicated.' }
                $pin = $matches[0]
                Assert-SwiftUIStateObjectCaptureFields $pin @('path', 'relativePath', 'sha256', 'bytes') 'Archived source mapping'
                $canonical = ConvertTo-SwiftUIStateObjectDiagnosticPath $pin.path
                if ($null -eq $canonical -or -not $canonical.StartsWith('/') -or $pin.sha256 -cne $source.sha256 -or $pin.bytes -ne $source.bytes -or
                    -not $canonical.EndsWith('/' + $source.relativePath, [System.StringComparison]::Ordinal)) { throw 'Archived source path/hash does not describe the exact native case source.' }
                $candidateRoot = $canonical.Substring(0, $canonical.Length - $source.relativePath.Length - 1)
                if ($null -eq $originalSourceRoot) { $originalSourceRoot = $candidateRoot }
                if ($originalSourceRoot -cne $candidateRoot -or -not $originalSourceRoot.EndsWith('/evidence/sources')) { throw 'Case source paths do not share their owned source snapshot.' }
                $paths.Add($source.relativePath, $canonical)
            }
            $originalOutput = $originalSourceRoot.Substring(0, $originalSourceRoot.Length - '/evidence/sources'.Length)
            $expectedArguments = @($matrix.document.requiredFlags) + @('-sdk', $reviewed.document.sdk.path, '-target', $target,
                '-module-cache-path', "$originalOutput/work/module-cache/$arch", '-module-name', $module)
            foreach ($path in @($case.sharedSources) + @($case.source)) { $expectedArguments += $paths[$path] }
            $expectedArguments += @('-o', "$originalOutput/work/$prefix/case.sil")
            if (@($raw.arguments).Count -ne $expectedArguments.Count -or $raw.workingDirectory -cne "$originalOutput/work/$prefix") { throw 'Archived compiler paths differ from the owned SIL-only command.' }
            for ($i = 0; $i -lt $expectedArguments.Count; $i++) {
                if ($raw.arguments[$i] -cne $expectedArguments[$i]) { throw 'Archived compiler arguments differ from the frozen strict command.' }
            }
            foreach ($stream in @('stdout', 'stderr')) {
                $file = Get-SwiftUIStateObjectFileHash (Resolve-SwiftUIStateObjectEvidencePath $Root $raw.($stream + 'Path')) -MaxBytes 1048576
                if ($file.sha256 -cne $raw.process.($stream + 'Sha256') -or $file.bytes -ne $raw.process.($stream + 'Bytes')) { throw 'Compiler output differs from its raw process receipt.' }
            }
            if ($raw.process.stdoutBytes + $raw.process.stderrBytes -gt 1048576 -or $null -ne $raw.process.error -or
                @($raw.process.cleanupErrors).Count -ne 0 -or @($result.process.artifactIssues).Count -ne 0 -or
                $null -ne $result.process.notRunReason -or $result.process.abnormalTermination) { throw 'Complete case contains an unacknowledged process failure.' }
            foreach ($field in @('processStarted', 'exitCode', 'timedOut', 'outputLimitExceeded', 'allRedirectedStreamsClosed', 'terminationCompleted', 'error')) {
                if (-not (Test-SwiftUIStateObjectEqual $result.process.$field $raw.process.$field)) { throw 'Adapted process status differs from the raw launch receipt.' }
            }
            if ($result.process.exitCode -eq 0) {
                if ($null -eq $result.process.sil -or $result.process.sil.path -cne "$prefix/case.sil") { throw 'Admitted source has no corresponding archived SIL.' }
                $sil = Get-SwiftUIStateObjectFileHash (Resolve-SwiftUIStateObjectEvidencePath $Root $result.process.sil.path) -MaxBytes 8388608
                if ($sil.bytes -lt 1 -or $sil.sha256 -cne $result.process.sil.sha256 -or $sil.bytes -ne $result.process.sil.bytes) { throw 'Archived SIL is missing, empty, oversized, or changed.' }
            } elseif ($null -ne $result.process.sil) { throw 'A source rejection cannot report admitted SIL.' }
            $diagnostics = Get-SwiftUIStateObjectDiagnostics -StderrPath (Resolve-SwiftUIStateObjectEvidencePath $Root $raw.stderrPath) `
                -Sources $sources -Case $case -DiagnosticPaths $paths
            $expectedStderr = "$originalOutput/evidence/$($raw.stderrPath)"
            if ($result.diagnostics.stderr.path -cne $expectedStderr) { throw 'Archived diagnostic stream path differs from the original evidence directory.' }
            $diagnostics.stderr.path = $expectedStderr
            if (($diagnostics | ConvertTo-Json -Depth 30 -Compress) -cne ($result.diagnostics | ConvertTo-Json -Depth 30 -Compress)) { throw 'Archived diagnostics do not replay from the exact source and stderr bytes.' }
            $assessment = Get-SwiftUIStateObjectCaseAssessment -Case $case -AttemptID $Manifest.attemptID -Target $target `
                -CompilerProfileSHA256 $Manifest.compilerProfileSHA256 -Process $result.process -Diagnostics $diagnostics -PrerequisiteResults ($prior.ToArray())
            if (($assessment | ConvertTo-Json -Depth 30 -Compress) -cne ($result.assessment | ConvertTo-Json -Depth 30 -Compress)) { throw 'Archived assessment does not replay within its actual dependency scope.' }
            $prior.Add($assessment)
        }
    }
    $safety = @($prior | Where-Object { $_.safetyRequirementMet -ceq $false }).Count
    $controls = @($prior | Where-Object { $_.controlRequirementMet -ceq $false }).Count
    if ($Manifest.disagreements.safety -ne $safety -or $Manifest.disagreements.controls -ne $controls -or
        $Manifest.disagreements.collectionSuccessDoesNotApproveSafety -isnot [bool] -or -not $Manifest.disagreements.collectionSuccessDoesNotApproveSafety) { throw 'Final disagreement counts hide or misstate source/control observations.' }
}

function Get-SwiftUIStateObjectMetadataProfile {
    param([Parameter(Mandatory)]$Matrix, [Parameter(Mandatory)]$SDKInputs,
        [Parameter(Mandatory)][string]$AttemptID, [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][object[]]$SourceFiles,
        [Parameter(Mandatory)][scriptblock]$ExecuteMetadata,
        [Parameter(Mandatory)][scriptblock]$InspectTool)
    # Test seams are private function parameters, not public command-line
    # switches or JSON callbacks. This function contains no case request path.
    $policy = Get-SwiftUIStateObjectCapturePolicy
    $raw = [System.Collections.Generic.List[object]]::new()
    $xcode = & $ExecuteMetadata 'xcode-version' '/usr/bin/xcodebuild' @('-version')
    $raw.Add($xcode.raw)
    $sdkPath = & $ExecuteMetadata 'sdk-path' '/usr/bin/xcrun' @('--sdk', 'macosx', '--show-sdk-path')
    $raw.Add($sdkPath.raw)
    $sdkVersion = & $ExecuteMetadata 'sdk-version' '/usr/bin/xcrun' @('--sdk', 'macosx', '--show-sdk-version')
    $raw.Add($sdkVersion.raw)
    $sdkBuild = & $ExecuteMetadata 'sdk-build' '/usr/bin/xcrun' @('--sdk', 'macosx', '--show-sdk-build-version')
    $raw.Add($sdkBuild.raw)
    if ($sdkPath.text.Trim() -cne $policy.sdkPath -or $sdkVersion.text.Trim() -cne $policy.sdkVersion -or
        $sdkBuild.text.Trim() -cne $policy.sdkBuildVersion) { throw 'Actual SDK selection differs from the sealed capture.' }
    $tools = [System.Collections.Generic.List[object]]::new()
    foreach ($name in @('swiftc', 'swift-frontend')) {
        $found = & $ExecuteMetadata "find-$name" '/usr/bin/xcrun' @('--toolchain', 'XcodeDefault', '--find', $name)
        $raw.Add($found.raw)
        $requested = $found.text.Trim()
        if ($requested -cne "$($policy.developerDirectory)/Toolchains/XcodeDefault.xctoolchain/usr/bin/$name") { throw 'Actual compiler lookup differs from the pinned XcodeDefault path.' }
        $file = & $InspectTool $requested
        if ($file.path -cne $requested -or [string]::IsNullOrWhiteSpace($file.canonicalPath)) { throw 'Actual compiler resolution is incomplete.' }
        $versionFlag = '--version'
        if ($name -ceq 'swift-frontend') { $versionFlag = '-version' }
        $version = & $ExecuteMetadata "$name-version" $file.canonicalPath @($versionFlag)
        $raw.Add($version.raw)
        $identity = ConvertTo-SwiftUIBaselineIdentity -XcodeOutput $xcode.text -SDKVersion $sdkVersion.text.Trim() `
            -SDKBuildVersion $sdkBuild.text.Trim() -SwiftOutput $version.text
        foreach ($field in @('xcodeVersion', 'xcodeBuildVersion', 'sdkVersion', 'sdkBuildVersion')) {
            if ($identity.$field -cne $policy.$field) { throw "Actual compiler metadata differs from captured $field." }
        }
        if ($identity.swiftCompilerVersionLine -cne $policy.compilerVersionLine) { throw 'Actual compiler version differs from the selected SDK capture.' }
        $targetInfo = [System.Collections.Generic.List[object]]::new()
        foreach ($target in $Matrix.targets) {
            $arch = $target.Split('-')[0]
            $info = & $ExecuteMetadata "$name-target-$arch" $file.canonicalPath @('-print-target-info', '-sdk', $policy.sdkPath, '-target', $target)
            $raw.Add($info.raw)
            $read = Read-SwiftUIStateObjectJson -Path $info.stdoutPath -MaxBytes 262144
            if ($read.document.compilerVersion -cne $policy.compilerVersionLine -or $read.document.target.triple -cne $target) { throw 'Actual target metadata differs from the requested desktop target.' }
            $targetInfo.Add([pscustomobject]@{ target = $target; compilerVersion = $read.document.compilerVersion; triple = $read.document.target.triple; rawSHA256 = $read.sha256 })
        }
        $tools.Add([pscustomobject]@{ name = $name; file = $file; versionOutput = $version.text; targetInfo = $targetInfo.ToArray() })
    }
    $osVersion = & $ExecuteMetadata 'host-version' '/usr/bin/sw_vers' @('-productVersion')
    $raw.Add($osVersion.raw)
    $osBuild = & $ExecuteMetadata 'host-build' '/usr/bin/sw_vers' @('-buildVersion')
    $raw.Add($osBuild.raw)
    $architecture = & $ExecuteMetadata 'host-architecture' '/usr/bin/uname' @('-m')
    $raw.Add($architecture.raw)
    $compilerProfile = [pscustomobject]@{
        schemaVersion = 1; product = 'swiftui-stateobject-isolation-compiler-profile'; status = 'metadata-only-awaiting-review'
        attemptID = $AttemptID; createdAtUtc = [DateTime]::UtcNow.ToString('o'); caseRequests = 0
        captureManifestSHA256 = $policy.captureManifestSHA256; baselineManifestSHA256 = $policy.baselineManifestSHA256
        matrixSHA256 = $Matrix.sha256; matrixContentSHA256 = $Matrix.contentSha256
        clientFlags = @($Matrix.document.requiredFlags); targets = @($Matrix.targets); source = $Source; sourceFiles = $SourceFiles
        sdk = [pscustomobject]@{
            developerDirectory = $policy.developerDirectory; path = $policy.sdkPath
            canonicalPath = $SDKInputs.canonicalSDKPath; settings = $SDKInputs.settings; anchors = @($SDKInputs.anchors)
            captureFiles = @($SDKInputs.files | ForEach-Object { [pscustomobject]@{ path = $_.relativePath; sha256 = $_.sha256; bytes = $_.bytes } })
        }
        tools = $tools.ToArray()
        nativeHost = [pscustomobject]@{
            macOSVersion = $osVersion.text.Trim(); macOSBuildVersion = $osBuild.text.Trim()
            architecture = $architecture.text.Trim(); powerShellVersion = $PSVersionTable.PSVersion.ToString()
        }
        metadataRequests = $raw.ToArray(); qualification = $policy.qualification
    }
    Assert-SwiftUIStateObjectProfileShape -CompilerProfile $compilerProfile -Matrix $Matrix
    return $compilerProfile
}

function Get-SwiftUIStateObjectWorkflowContext {
    # A narrow allowlist: never copy all environment values or credentials.
    return [pscustomobject]@{
        repository = $env:GITHUB_REPOSITORY; eventName = $env:GITHUB_EVENT_NAME; eventCommit = $env:GITHUB_SHA
        workflowRef = $env:GITHUB_WORKFLOW_REF; workflowCommit = $env:GITHUB_WORKFLOW_SHA
        runId = $env:GITHUB_RUN_ID; runAttempt = $env:GITHUB_RUN_ATTEMPT; job = $env:GITHUB_JOB
        runnerOS = $env:RUNNER_OS; runnerArchitecture = $env:RUNNER_ARCH; imageOS = $env:ImageOS; imageVersion = $env:ImageVersion
    }
}

function Get-SwiftUIStateObjectGitBlobSHA1 {
    param([Parameter(Mandatory)][string]$Path)
    $file = Read-SwiftUIStateObjectBoundedBytes $Path -MaxBytes 16777216
    $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($file.bytes)`0")
    $algorithm = [System.Security.Cryptography.SHA1]::Create()
    try {
        [void]$algorithm.TransformBlock($header, 0, $header.Length, $header, 0)
        [void]$algorithm.TransformFinalBlock($file.rawBytes, 0, $file.rawBytes.Length)
        return [System.BitConverter]::ToString($algorithm.Hash).Replace('-', '').ToLowerInvariant()
    } finally { $algorithm.Dispose() }
}

function Assert-SwiftUIStateObjectTrackedInputs {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Listing,
        [Parameter(Mandatory)][string[]]$Paths, [Parameter(Mandatory)][string]$RepositoryRoot)
    $blobs = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($record in $Listing.Split([char[]]@([char]0), [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $match = [regex]::Match($record, '\A100(?:644|755) blob ([0-9a-f]{40})\t([^\r\n\x00]+)\z')
        if (-not $match.Success -or $blobs.ContainsKey($match.Groups[2].Value)) { throw 'Git source membership is malformed, duplicated, or not a regular blob.' }
        $blobs.Add($match.Groups[2].Value, $match.Groups[1].Value)
    }
    if ($blobs.Count -ne $Paths.Count) { throw 'Every required fixture, manifest, and harness input must exist in the selected HEAD.' }
    foreach ($path in $Paths) {
        if (-not $blobs.ContainsKey($path) -or (Get-SwiftUIStateObjectGitBlobSHA1 (Join-Path $RepositoryRoot $path)) -cne $blobs[$path]) {
            throw 'A required input is absent from HEAD or its actual bytes differ from the committed Git blob.'
        }
    }
}

function Invoke-SwiftUIStateObjectMetadataRequest {
    param([Parameter(Mandatory)][string]$ID, [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Arguments,
        [Parameter(Mandatory)][string]$EvidenceRoot, [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Environment,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Records)
    if ($ID -cnotmatch '^[a-z0-9-]+$') { throw 'Invalid metadata request identifier.' }
    $metadataRoot = Join-Path $EvidenceRoot 'metadata'
    if (-not (Test-Path -LiteralPath $metadataRoot)) { [void](New-Item -ItemType Directory -Path $metadataRoot) }
    $stdout = Join-Path $metadataRoot "$ID.stdout.txt"; $stderr = Join-Path $metadataRoot "$ID.stderr.txt"
    $canonical = Resolve-SwiftUIBaselineFileSystemPath $FilePath
    $toolFile = Get-SwiftUIStateObjectFileHash $canonical -MaxBytes 2147483647
    $record = Invoke-SwiftUIStateObjectProcess -FilePath $canonical -Arguments $Arguments -WorkingDirectory $WorkingDirectory `
        -StdoutPath $stdout -StderrPath $stderr -TimeoutSeconds 30 -MaxOutputBytes 262144 -Environment $Environment
    $raw = [pscustomobject]@{
        id = $ID; filePath = $FilePath; canonicalPath = $canonical; executableSHA256 = $toolFile.sha256; executableBytes = $toolFile.bytes
        arguments = $Arguments; workingDirectory = $WorkingDirectory
        environment = [pscustomobject]@{ overrideNames = @($Environment.Keys | Sort-Object); developerDirectory = $Environment['DEVELOPER_DIR'] }
        stdoutPath = "metadata/$ID.stdout.txt"; stderrPath = "metadata/$ID.stderr.txt"; process = $record
    }
    $Records.Add($raw)
    [void](Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $metadataRoot "$ID.request.json") -Value $raw)
    if (-not $record.processStarted -or $record.exitCode -ne 0 -or $record.timedOut -or $record.outputLimitExceeded -or
        -not $record.terminationCompleted -or -not $record.allRedirectedStreamsClosed -or
        $null -ne $record.error -or @($record.cleanupErrors).Count -gt 0) { throw "Metadata request $ID did not finish cleanly; raw evidence was retained." }
    $after = Get-SwiftUIStateObjectFileHash $canonical -MaxBytes 2147483647
    if ($after.sha256 -cne $toolFile.sha256 -or $after.bytes -ne $toolFile.bytes) { throw "Metadata executable changed during $ID." }
    $stdoutRead = Read-SwiftUIStateObjectBoundedBytes $stdout -MaxBytes 262144
    $stderrRead = Read-SwiftUIStateObjectBoundedBytes $stderr -MaxBytes 262144
    if ($stdoutRead.sha256 -cne $record.stdoutSha256 -or $stderrRead.sha256 -cne $record.stderrSha256 -or
        $stdoutRead.bytes -ne $record.stdoutBytes -or $stderrRead.bytes -ne $record.stderrBytes) { throw 'Metadata streams changed after process collection.' }
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $stderrText = $utf8.GetString($stderrRead.rawBytes)
    if (-not [string]::IsNullOrWhiteSpace($stderrText)) { throw "Metadata request $ID emitted unexpected diagnostics; no fallback was attempted." }
    return [pscustomobject]@{ raw = $raw; stdoutPath = $stdout; text = $utf8.GetString($stdoutRead.rawBytes) }
}

function ConvertTo-SwiftUIStateObjectCaseProcess {
    param([Parameter(Mandatory)]$Record, [Parameter(Mandatory)][string]$StdoutPath,
        [Parameter(Mandatory)][string]$StderrPath, [Parameter(Mandatory)][string]$SILPath,
        [Parameter(Mandatory)][string]$ArchivedSILPath, [Parameter(Mandatory)]$Limits)
    $issues = [System.Collections.Generic.List[string]]::new()
    $sil = $null
    try {
        Assert-SwiftUIStateObjectRawProcess -Value $Record -MaxCombinedBytes $Limits.maxCombinedRawOutputBytes
        $stdout = Get-SwiftUIStateObjectFileHash $StdoutPath -MaxBytes $Limits.maxCombinedRawOutputBytes
        $stderr = Get-SwiftUIStateObjectFileHash $StderrPath -MaxBytes $Limits.maxCombinedRawOutputBytes
        if ($stdout.bytes + $stderr.bytes -gt $Limits.maxCombinedRawOutputBytes -or
            $stdout.sha256 -cne $Record.stdoutSha256 -or $stderr.sha256 -cne $Record.stderrSha256 -or
            $stdout.bytes -ne $Record.stdoutBytes -or $stderr.bytes -ne $Record.stderrBytes) { throw 'Raw compiler stream integrity mismatch.' }
    } catch { $issues.Add($_.Exception.Message) }
    foreach ($cleanup in @($Record.cleanupErrors)) { $issues.Add("Process cleanup: $cleanup") }
    if ($Record.processStarted -and $Record.exitCode -eq 0 -and -not $Record.timedOut -and -not $Record.outputLimitExceeded -and
        $Record.terminationCompleted -and $Record.allRedirectedStreamsClosed -and $null -eq $Record.error -and $issues.Count -eq 0) {
        try {
            $hash = Get-SwiftUIStateObjectFileHash $SILPath -MaxBytes $Limits.maxArchivedSILBytesPerCase
            if ($hash.bytes -lt 1) { throw 'Compiler exit 0 did not produce nonempty SIL.' }
            $copy = Copy-SwiftUIStateObjectCaptureInput -Source $SILPath -Destination $ArchivedSILPath -SHA256 $hash.sha256 -MaxBytes $Limits.maxArchivedSILBytesPerCase
            $sil = [pscustomobject]@{ path = $copy.path; sha256 = $copy.sha256; bytes = $copy.bytes }
        } catch { $issues.Add($_.Exception.Message) }
    }
    return [pscustomobject]@{
        processStarted = $Record.processStarted; exitCode = $Record.exitCode; timedOut = $Record.timedOut
        outputLimitExceeded = $Record.outputLimitExceeded; abnormalTermination = ($null -ne $Record.exitCode -and $Record.exitCode -notin @(0, 1))
        allRedirectedStreamsClosed = $Record.allRedirectedStreamsClosed; terminationCompleted = $Record.terminationCompleted
        error = $Record.error; notRunReason = $null; artifactIssues = $issues.ToArray(); sil = $sil
    }
}

function Copy-SwiftUIStateObjectCaptureInput {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$SHA256, [int]$MaxBytes = 16777216)
    $before = Get-SwiftUIStateObjectFileHash -Path $Source -MaxBytes $MaxBytes
    if ($before.sha256 -cne $SHA256) { throw 'Input changed before copying.' }
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [void](Resolve-SwiftUIStateObjectEvidencePath -Root $parent -RelativePath ([System.IO.Path]::GetFileName($Destination)) -AllowMissingLeaf)
    [System.IO.File]::Copy($Source, $Destination, $false)
    $copy = Get-SwiftUIStateObjectFileHash -Path $Destination -MaxBytes $MaxBytes
    $after = Get-SwiftUIStateObjectFileHash -Path $Source -MaxBytes $MaxBytes
    if ($after.sha256 -cne $SHA256 -or $copy.sha256 -cne $SHA256 -or $before.bytes -ne $copy.bytes) { throw 'Input changed during copying.' }
    return $copy
}

function Assert-SwiftUIStateObjectCompilerRequest {
    param([Parameter(Mandatory)]$Request, [Parameter(Mandatory)]$Matrix, [Parameter(Mandatory)]$Case,
        [Parameter(Mandatory)][string]$CompilerPath, [Parameter(Mandatory)][string]$SDKPath,
        [Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$CachePath, [Parameter(Mandatory)][string]$SILPath,
        [Parameter(Mandatory)][string]$ModuleName)
    if ($Target -cnotin @($Matrix.targets) -or $ModuleName -cnotmatch '^SOI_[0-9]{2}_(x86_64|arm64)$') { throw 'Unsupported compiler target or module name.' }
    $expected = @($Matrix.document.requiredFlags) + @('-sdk', $SDKPath, '-target', $Target,
        '-module-cache-path', $CachePath, '-module-name', $ModuleName)
    foreach ($source in @($Case.sharedSources) + @($Case.source)) {
        $expected += Resolve-SwiftUIStateObjectEvidencePath -Root $SourceRoot -RelativePath $source
    }
    $expected += @('-o', $SILPath)
    if ($Request.filePath -cne $CompilerPath -or @($Request.arguments).Count -ne $expected.Count) { throw 'The compiler request differs from the sealed SIL-only shape.' }
    for ($i = 0; $i -lt $expected.Count; $i++) {
        if ($Request.arguments[$i] -isnot [string] -or $Request.arguments[$i] -cne $expected[$i]) { throw 'The compiler request differs from the sealed SIL-only arguments.' }
    }
}

function New-SwiftUIStateObjectCompilerRequest {
    param([Parameter(Mandatory)]$Matrix, [Parameter(Mandatory)]$Case,
        [Parameter(Mandatory)][string]$CompilerPath, [Parameter(Mandatory)][string]$SDKPath,
        [Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$CachePath, [Parameter(Mandatory)][string]$SILPath,
        [Parameter(Mandatory)][string]$ModuleName)
    $arguments = @($Matrix.document.requiredFlags) + @('-sdk', $SDKPath, '-target', $Target,
        '-module-cache-path', $CachePath, '-module-name', $ModuleName)
    foreach ($source in @($Case.sharedSources) + @($Case.source)) {
        $arguments += Resolve-SwiftUIStateObjectEvidencePath -Root $SourceRoot -RelativePath $source
    }
    $arguments += @('-o', $SILPath)
    $request = [pscustomobject]@{ filePath = $CompilerPath; arguments = $arguments }
    Assert-SwiftUIStateObjectCompilerRequest -Request $request -Matrix $Matrix -Case $Case -CompilerPath $CompilerPath `
        -SDKPath $SDKPath -Target $Target -SourceRoot $SourceRoot -CachePath $CachePath -SILPath $SILPath -ModuleName $ModuleName
    return $request
}

function New-SwiftUIStateObjectNotRunProcess {
    param([Parameter(Mandatory)][string]$Reason)
    return [pscustomobject]@{
        processStarted = $false; exitCode = $null; timedOut = $false; outputLimitExceeded = $false
        abnormalTermination = $false; allRedirectedStreamsClosed = $false; terminationCompleted = $false
        error = $null; notRunReason = $Reason; artifactIssues = @(); sil = $null
    }
}

function Invoke-SwiftUIStateObjectCasePlan {
    param([Parameter(Mandatory)]$Matrix, [Parameter(Mandatory)][string]$AttemptID,
        [Parameter(Mandatory)][string]$CompilerProfileSHA256,
        [Parameter(Mandatory)][scriptblock]$Request,
        [Parameter(Mandatory)][scriptblock]$AssertStableInputs,
        [Parameter(Mandatory)][scriptblock]$ElapsedSeconds)
    Assert-SwiftUIStateObjectCaptureSHA256 $CompilerProfileSHA256 'Compiler profile hash'
    if ($AttemptID -cnotmatch '^[a-f0-9]{32}$') { throw 'AttemptID must identify one new attempt.' }
    $results = [System.Collections.Generic.List[object]]::new()
    $prior = [System.Collections.Generic.List[object]]::new()
    $stopReason = $null
    $index = 0
    foreach ($target in $Matrix.targets) {
        $targetIndex = 0
        foreach ($case in $Matrix.cases) {
            $index++; $targetIndex++
            # The request must publish its launch attempt and raw returned
            # process before fallible parsing/copying. If a helper itself throws
            # after invocation, launch is unknown, never fabricated as not run.
            $receipt = [pscustomobject]@{
                launchAttempted = $false; process = $null
                diagnostics = (New-SwiftUIStateObjectEmptyDiagnostics); raw = $null
            }
            $collectionError = $null
            if ($null -eq $stopReason) {
                try {
                    if ((& $ElapsedSeconds) -ge $Matrix.document.limits.maxMatrixSeconds) { throw 'The overall matrix deadline was reached.' }
                    & $AssertStableInputs
                    $remaining = [Math]::Floor($Matrix.document.limits.maxMatrixSeconds - (& $ElapsedSeconds))
                    if ($remaining -lt 1) { throw 'The overall matrix deadline was reached.' }
                    $timeout = [Math]::Min($Matrix.document.limits.perRequestSeconds, $remaining)
                    & $Request $case $target $targetIndex ([int]$timeout) $receipt
                    if ($null -eq $receipt.process -or $null -eq $receipt.diagnostics) { throw 'The request adapter returned no complete record.' }
                    & $AssertStableInputs
                    if ((& $ElapsedSeconds) -ge $Matrix.document.limits.maxMatrixSeconds) { throw 'The overall matrix deadline was reached during collection.' }
                } catch {
                    $stopReason = $_.Exception.Message
                    $collectionError = $stopReason
                    if ($null -ne $receipt.process) { $receipt.process.artifactIssues = @($receipt.process.artifactIssues) + @($stopReason) }
                }
            }
            if ($null -eq $receipt.process -and -not $receipt.launchAttempted) {
                $receipt.process = New-SwiftUIStateObjectNotRunProcess "No invocation after infrastructure/provenance stop: $stopReason"
            }
            $assessment = $null
            if ($null -ne $receipt.process) {
                try {
                    $assessment = Get-SwiftUIStateObjectCaseAssessment -Case $case -AttemptID $AttemptID -Target $target `
                        -CompilerProfileSHA256 $CompilerProfileSHA256 -Process $receipt.process -Diagnostics $receipt.diagnostics `
                        -PrerequisiteResults ($prior.ToArray())
                    $prior.Add($assessment)
                } catch {
                    $collectionError = 'Result classification failed: ' + $_.Exception.Message
                    $stopReason = $collectionError
                }
            }
            $launchState = 'not-run'
            if ($receipt.launchAttempted) {
                $launchState = 'unknown-after-invocation'
                if ($null -ne $receipt.process) {
                    $launchState = 'confirmed-not-started'
                    if ($receipt.process.processStarted) { $launchState = 'confirmed-started' }
                }
            }
            $results.Add([pscustomobject]@{
                ordinal = $index; target = $target; caseID = $case.caseID
                launchState = $launchState; collectionError = $collectionError
                process = $receipt.process; diagnostics = $receipt.diagnostics; raw = $receipt.raw; assessment = $assessment
            })
            if ($null -eq $stopReason -and $null -ne $assessment -and $assessment.observedOutcome -cin @(
                    'unsupported-configuration', 'tool-failure', 'timeout', 'artifact-failure', 'not-run')) {
                $stopReason = "Infrastructure, configuration, or provenance failure in $target / $($case.caseID)."
            }
        }
    }
    if ($results.Count -ne 42) { throw 'The sealed plan did not account for all 42 requests.' }
    return [pscustomobject]@{ results = $results.ToArray(); stopReason = $stopReason; completed = ($null -eq $stopReason) }
}
