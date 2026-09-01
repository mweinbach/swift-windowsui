#Requires -Version 7.0
<#
.SYNOPSIS
Tests collector orchestration and sealed files with synthetic data only.
.DESCRIPTION
Uses real bounded JSON, hash, copy, directory and report readers. Only the
Get-SwiftUIOverlayExpectedLayout lookup is replaced for native-profile fixtures.
Scheduler callbacks return synthetic receipts; neither the native adapter nor
the process helper is called. PowerShell 7 may initialize the repository's
existing managed JSON/streaming helper with in-process Add-Type. No external
compiler, SwiftPM command, SDK path, workflow or native workload is used.
#>
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot), [string]$OutputRoot,
    [string[]]$CaseFilter = @())
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:CollectorStartedAtUtc = [DateTime]::UtcNow.ToString('o')
$script:CollectorElapsed = [Diagnostics.Stopwatch]::StartNew()
$script:CollectorSourcePaths = @(
    'scripts/capture-swiftui-overlay-probes.ps1', 'scripts/swiftui-overlay-probe-collector.ps1',
    'scripts/swiftui-overlay-probe-native.ps1', 'scripts/swiftui-overlay-probe-intake.ps1',
    'scripts/swiftui-overlay-probe-graphs.ps1', 'scripts/swiftui-overlay-discovery-common.ps1',
    'scripts/swiftui-stateobject-process-common.ps1', 'scripts/swiftui-stateobject-isolation-common.ps1',
    'scripts/swiftui-api-review-common.ps1', 'scripts/swiftui-api-audit-common.ps1',
    'scripts/swiftui-baseline-common.ps1', 'scripts/swiftui-baseline-streaming.ps1',
    'scripts/fixtures/swiftui-overlay-probes/collector/synthetic-cases.json',
    'scripts/fixtures/swiftui-overlay-probes/collector/synthetic-full-report.ps1',
    'scripts/fixtures/swiftui-overlay-probes/native/synthetic-cases.json'
)
$script:CollectorActualTestPath = $PSCommandPath
function Get-CollectorSourceSnapshot {
    $entries = @($script:CollectorSourcePaths | ForEach-Object {
        [pscustomobject]@{ label = $_; path = Join-Path $RepositoryRoot $_ }
    }) + @([pscustomobject]@{ label = 'executed-test-script'; path = $script:CollectorActualTestPath })
    return ,@($entries | ForEach-Object {
        $attributes = [IO.File]::GetAttributes($_.path)
        if (($attributes -band ([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)) -ne 0) {
            throw 'A test source snapshot must be a regular file.'
        }
        $stream = [IO.File]::Open($_.path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $length = $stream.Length
            if ($length -gt 2MB) { throw 'A test source snapshot exceeds its explicit byte budget.' }
            $algorithm = [Security.Cryptography.SHA256]::Create()
            try { $sha = [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
            finally { $algorithm.Dispose() }
            if ($stream.Length -ne $length) { throw 'Test source changed length during its snapshot.' }
        } finally { $stream.Dispose() }
        [pscustomobject]@{ path = $_.label; bytes = [long]$length; sha256 = $sha }
    })
}
# Observe the production files, this script and both fixtures before importing
# any production function. A second snapshot is required at suite completion.
$script:CollectorSourceHashesBefore = Get-CollectorSourceSnapshot

. (Join-Path $RepositoryRoot 'scripts/swiftui-overlay-probe-collector.ps1')
if ([string]::IsNullOrEmpty($OutputRoot)) {
    $OutputRoot = Join-Path $RepositoryRoot ('artifacts/swiftui-overlay-probe-collector-tests/' + [Guid]::NewGuid().ToString('N'))
}
$OutputRoot = New-SwiftUIOverlayProbeOutputDirectory -Path ([IO.Path]::GetFullPath($OutputRoot)) -ForbiddenRoots @()
$script:CollectorUtf8 = [Text.UTF8Encoding]::new($false, $true)
$script:CollectorAssertions = 0
$script:CollectorSequence = 0
$script:CollectorCases = [Collections.Generic.List[object]]::new()
$script:CollectorSkippedCases = [Collections.Generic.List[string]]::new()
$script:CollectorCaseNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$script:CollectorNativeAdapterCalls = 0
$script:CollectorProcessHelperCalls = 0
$script:CollectorRelocatedFixtureEvidence = [Collections.Generic.List[object]]::new()
$script:CollectorManagedHelperPresentBefore = $null -ne ('SwiftUIBaseline.Streaming.InventoryWriter' -as [type])
$fixturePath = Join-Path $RepositoryRoot 'scripts/fixtures/swiftui-overlay-probes/collector/synthetic-cases.json'
$fixtureRead = Read-SwiftUIStateObjectJson -Path $fixturePath -MaxBytes 1MB
$script:CollectorFixture = $fixtureRead.document
if ($script:CollectorFixture.evidenceKind -cne 'SYNTHETIC-COLLECTOR-FIXTURE-NOT-NATIVE-CAPTURE') {
    throw 'Collector fixture does not carry its synthetic marker.'
}
$script:CollectorFixtureLayout = $script:CollectorFixture.layout
$script:CollectorPolicy = Get-SwiftUIOverlayProbeCollectionPolicy

# Accidental calls fail and increment guards even when a test expects a throw.
# Calling the PowerShell CLI itself in-process is allowed only for its platform
# refusal; these guards are not synthetic execution adapters.
function Invoke-SwiftUIStateObjectProcess {
    $script:CollectorProcessHelperCalls++
    throw 'TEST GUARD: process helper is forbidden in collector synthetic tests.'
}
function Invoke-SwiftUIOverlayProbeNativeRequest {
    $script:CollectorNativeAdapterCalls++
    throw 'TEST GUARD: native adapter is forbidden in collector synthetic tests.'
}

function Assert-CollectorTrue {
    param([bool]$Value, [string]$Message)
    $script:CollectorAssertions++
    if (-not $Value) { throw "Synthetic collector assertion failed: $Message" }
}
function Assert-CollectorThrows {
    param([scriptblock]$Action, [string]$Message, [string]$ExpectedMessage = '.')
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-CollectorTrue ($null -ne $caught) $Message
    if ($null -ne $caught) {
        Assert-CollectorTrue ($caught.Exception.Message -match $ExpectedMessage) ($Message + ': expected refusal reason')
    }
}
function Invoke-CollectorCase {
    param([string]$Name, [scriptblock]$Action)
    if (-not $script:CollectorCaseNames.Add($Name)) { throw 'Duplicate collector test case name.' }
    if ($CaseFilter.Count -gt 0 -and $Name -cnotin $CaseFilter -and
        $Name -cnotin @('native-dispatch-guards-remained-unused', 'loaded-source-hashes-remained-stable-during-tests', 'requested-case-filter-resolves-exactly')) {
        $script:CollectorSkippedCases.Add($Name)
        return
    }
    $before = $script:CollectorAssertions
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    $script:CollectorCases.Add([pscustomobject][ordered]@{
        name = $Name
        outcome = $(if ($null -eq $caught) { 'passed' } else { 'failed' })
        assertions = $script:CollectorAssertions - $before
        error = $(if ($null -eq $caught) { $null } else { $caught.ToString() })
        errorLocation = $(if ($null -eq $caught) { $null } else { $caught.ScriptStackTrace })
    })
}
function Copy-CollectorValue {
    param($Value)
    return ,(ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 80 -Compress) -Depth 80 -NoEnumerate)
}
function New-CollectorCaseRoot {
    param([string]$Label)
    $script:CollectorSequence++
    $relative = '{0:D4}-{1}' -f $script:CollectorSequence, $Label
    return New-SwiftUIOverlayProbeOwnedDirectory -Root $OutputRoot -RelativePath $relative
}
function Write-CollectorBytes {
    param([string]$Path, [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length) } finally { $stream.Dispose() }
    return $Path
}
function Write-CollectorText {
    param([string]$Path, [AllowEmptyString()][string]$Text)
    return Write-CollectorBytes $Path ($script:CollectorUtf8.GetBytes($Text))
}
function New-CollectorHash {
    param([string]$Name)
    return Get-SwiftUIStateObjectBytesSHA256 ($script:CollectorUtf8.GetBytes('SYNTHETIC-COLLECTOR:' + $Name))
}
function New-CollectorSourceArtifacts {
    $artifacts = [ordered]@{}
    foreach ($name in @('captureManifestSha256', 'captureStatusSha256', 'auditManifestSha256',
        'baselineManifestSha256', 'inventorySha256', 'graphSetSha256', 'discoveryManifestSha256', 'rootPlanSha256')) {
        $artifacts[$name] = New-CollectorHash $name
    }
    return [pscustomobject]$artifacts
}
function New-CollectorPlan {
    param([int]$PairCount = 1, [switch]$BothCxxModes, [switch]$EmptyNames)
    $pairs = [Collections.Generic.List[object]]::new()
    for ($pairIndex = 0; $pairIndex -lt $PairCount; $pairIndex++) {
        $definition = New-CollectorHash ('definition-' + $pairIndex)
        $names = @()
        if (-not $EmptyNames) {
            for ($index = 0; $index -lt $script:CollectorFixture.overlayNames.Count; $index++) {
                $names += [pscustomobject]@{ index = $index; name = $script:CollectorFixture.overlayNames[$index] }
            }
        }
        $candidates = @($script:CollectorFixture.targets | ForEach-Object {
            [pscustomobject]@{ recordId = New-CollectorHash ('candidate-' + $pairIndex + '-' + $_); target = $_ }
        })
        $pairs.Add([pscustomobject][ordered]@{
            pairId = Get-SwiftUIOverlayId @('probe-pair', $definition)
            definitionOccurrenceId = $definition
            rawDefinitionSha256 = New-CollectorHash ('definition-bytes-' + $pairIndex)
            declaringModule = $script:CollectorFixture.declaringModule
            bystanderModule = $script:CollectorFixture.bystanderModule
            overlayNameOccurrences = $names
            sourceCandidates = $candidates
            hasExpectedOverlays = -not $EmptyNames
        })
    }
    $contexts = @()
    $modes = if ($BothCxxModes) { @('off', 'default') } else { @('off') }
    foreach ($mode in $modes) {
        foreach ($target in $script:CollectorFixture.targets) {
            $contexts += [pscustomobject]@{ target = $target; targetVariant = $null; cxxInteroperabilityMode = $mode }
        }
    }
    return [pscustomobject][ordered]@{
        file = [pscustomobject]@{ sha256 = New-CollectorHash 'plan' }
        pairs = $pairs.ToArray(); targetContexts = $contexts
        sourceArtifacts = New-CollectorSourceArtifacts; syntheticFixture = $true
    }
}
function New-CollectorReceipt {
    param($Request, [string]$Outcome = 'import-controls-recorded',
        [bool]$Stop = $false, [bool]$ClosureRequired = $false)
    return [pscustomobject][ordered]@{
        requestId = $Request.requestId; kind = $Request.kind; outcome = $Outcome
        nativeInvocationAttempted = $false; processStarted = $false
        stopLaterCommands = $Stop; descendantClosureRequired = $ClosureRequired
        resultFile = $null; positiveFrontendObservations = @(); assessments = @()
    }
}
function New-CollectorSimpleRequests {
    param([int]$Count = 3)
    return ,@(for ($index = 0; $index -lt $Count; $index++) {
        [pscustomobject]@{ requestId = New-CollectorHash ('controller-request-' + $index); kind = 'frontend-import' }
    })
}
function New-CollectorPositive {
    param([string]$Name, [string]$Module = 'AlphaBeta',
        [string]$Target = 'arm64-apple-macosx26.5', [string]$CxxMode = 'off',
        [string]$Control = 'owner-bystander', [AllowNull()][string]$CandidateId)
    if ([string]::IsNullOrEmpty($CandidateId)) { $CandidateId = New-CollectorHash ('positive-candidate-' + $Name) }
    return [pscustomobject][ordered]@{
        observationId = New-CollectorHash ('positive-observation-' + $Name)
        requestId = New-CollectorHash ('positive-request-' + $Name)
        profileSha256 = New-CollectorHash 'native-profile'
        module = $Module; target = $Target; cxxMode = $CxxMode; control = $Control
        candidateRecordIds = @($CandidateId)
        sourcePath = '/SYNTHETIC-SDK/AlphaBeta.swiftinterface'
        loadedPath = '/SYNTHETIC-CACHE/AlphaBeta.swiftmodule'
        sourceSha256 = New-CollectorHash 'synthetic-interface'; loadedSha256 = New-CollectorHash 'synthetic-module'
        activationTuple = [pscustomobject]@{ declaringModule = 'Alpha'; bystanderModules = @('Beta'); overlayModule = $Module }
        traceSha256 = New-CollectorHash 'synthetic-trace'; diagnosticsSha256 = New-CollectorHash 'synthetic-diagnostic'
        eligible = $true
    }
}
function New-CollectorImportResult {
    param([object[]]$Observations)
    return [pscustomobject]@{
        requestId = $Observations[0].requestId; kind = 'frontend-import'; outcome = 'import-controls-recorded'
        positiveFrontendObservations = $Observations; stopLaterCommands = $false
    }
}
function New-CollectorProfileFixture {
    $toolchain = $script:CollectorFixtureLayout.toolchain
    $artifacts = New-CollectorSourceArtifacts
    $observed = [pscustomobject]@{ marker = 'SYNTHETIC-RECORDED-IDENTITY-NOT-OBSERVED' }
    $files = @(
        [pscustomobject]@{ id = 'compiler-tool'; path = $toolchain + '/usr/bin/swift' },
        [pscustomobject]@{ id = 'extractor-tool'; path = $toolchain + '/usr/bin/swift-symbolgraph-extract' }
    )
    $anchors = @()
    $expected = @()
    foreach ($file in $files) {
        $descriptor = [pscustomobject][ordered]@{
            path = $file.path; canonicalPath = $file.path; bytes = [long]32
            sha256 = New-CollectorHash $file.id; allowedPhysicalRoot = $toolchain
            observation = 'path, length, last-write time and content checks; not atomic loaded-image attestation'
        }
        $anchors += [pscustomobject]@{ anchorId = $file.id; file = $descriptor }
        $expected += [pscustomobject]@{
            anchorId = $file.id; logicalPath = $file.path
            expectedSha256 = $descriptor.sha256; allowedPhysicalBoundary = $toolchain
        }
    }
    $frontend = [pscustomobject][ordered]@{
        path = $toolchain + '/usr/bin/swift-frontend'; canonicalPath = $toolchain + '/usr/bin/swift-frontend'
        bytes = [long]64; sha256 = New-CollectorHash 'frontend'; allowedPhysicalRoot = $toolchain
        observation = 'path, length, last-write time and content checks; not atomic loaded-image attestation'
    }
    $profile = [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'swiftui-overlay-native-tool-profile'
        status = 'metadata-recorded-awaiting-explicit-plan-selection'; syntheticFixture = $false
        sourceArtifacts = $artifacts; nativeEvidenceProfile = 'public-swift-6.3-overlay-load-v1'
        publicSwiftSourceCommit = $script:CollectorPolicy.publicSwiftSourceCommit
        developerDirectory = $script:CollectorFixtureLayout.developer
        sdkPath = $script:CollectorFixtureLayout.sdk; toolchainPath = $toolchain
        selectedRoots = @(); anchors = $anchors; frontend = $frontend; extractor = Copy-CollectorValue $anchors[1].file
        observedExtractorIdentityAsRecorded = $observed
        observations = [pscustomobject][ordered]@{
            nativeCommandsExecuted = $false; frontendVersionExecuted = $false
            frontendIdentityMeaning = 'separately named and hashed file; not inferred from the recorded swift compiler version'
            nativeProcessSandboxEstablished = $false; wholeSDKByteIdentityEstablished = $false
        }
        qualification = Copy-CollectorValue $script:CollectorFixture.qualification
    }
    # Deliberately native-shaped metadata is required to test the production
    # reader. These flags are not execution evidence; the enclosing test report
    # and each case directory retain the explicit synthetic marker.
    $inputs = [pscustomobject]@{
        syntheticFixture = $false; sourceArtifacts = Copy-CollectorValue $artifacts
        source = [pscustomobject]@{ inputs = [pscustomobject]@{
            captureContext = [pscustomobject]@{ capture = [pscustomobject]@{ observedIdentity = $observed } }
        } }
        rootPlanContext = [pscustomobject]@{ plan = [pscustomobject]@{ identityAnchors = $expected; roots = @() } }
    }
    return [pscustomobject]@{ profile = $profile; inputs = $inputs }
}
function Invoke-CollectorWithSyntheticLayout {
    param([scriptblock]$Action)
    # This local function shadows only installation-layout lookup. JSON parsing,
    # exact-field checks, path spelling and all hash checks remain production.
    function Get-SwiftUIOverlayExpectedLayout {
        param($SourceContext)
        return $script:CollectorFixtureLayout
    }
    & $Action
}
function Read-CollectorProfileValue {
    param($Value, $Inputs, [AllowNull()][string]$ExpectedSha256)
    $root = New-CollectorCaseRoot 'synthetic-profile'
    [void](Write-CollectorText (Join-Path $root 'SYNTHETIC.txt') 'SYNTHETIC PROFILE PARSER INPUT; no SDK paths opened.')
    $file = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $root 'native-profile.json') -Value $Value -MaximumBytes 1MB
    if ([string]::IsNullOrEmpty($ExpectedSha256)) { $ExpectedSha256 = $file.sha256 }
    return Invoke-CollectorWithSyntheticLayout {
        Read-SwiftUIOverlayProbeNativeProfile -Path $file.path -ExpectedSha256 $ExpectedSha256 -Inputs $Inputs
    }
}

Invoke-CollectorCase 'guarded-public-collection-cannot-dispatch-on-this-host' {
    $root = Join-Path $OutputRoot 'must-not-be-created'
    $inputs = [pscustomobject]@{ syntheticFixture = $true }
    $plan = [pscustomobject]@{ syntheticFixture = $true }
    Assert-CollectorThrows { Invoke-SwiftUIOverlayProbeCollection -Inputs $inputs -Plan $plan -NativeProfile ([pscustomobject]@{}) -OutputDirectory $root } 'the synthetic invocation is refused on this host' 'requires real native inputs'
    Assert-CollectorTrue (-not (Test-Path -LiteralPath $root)) 'platform/synthetic refusal precedes output creation'
    Assert-CollectorTrue ($script:CollectorNativeAdapterCalls -eq 0 -and $script:CollectorProcessHelperCalls -eq 0) 'refusal never entered either native guard'
}
Invoke-CollectorCase 'windows-public-cli-refuses-before-opening-input-paths' {
    if (-not $IsMacOS) {
        $cli = Join-Path $RepositoryRoot 'scripts/capture-swiftui-overlay-probes.ps1'
        $missing = Join-Path $OutputRoot 'nonexistent-synthetic-source'
        $common = @{
            CaptureRoot = $missing; AuditRoot = $missing; DiscoveryRoot = $missing
            ExpectedDiscoverySha256 = New-CollectorHash 'missing-discovery'
            OutputDirectory = Join-Path $OutputRoot 'cli-must-not-create'
        }
        Assert-CollectorThrows { & $cli @common -PrepareNativeProfile -FrontendPath '/SYNTHETIC-NOT-OPENED/swift-frontend' } 'prepare CLI refuses non-Mac before source access' 'Live Stage B requires macOS'
        Assert-CollectorThrows { & $cli @common -PlanPath $missing -ExpectedPlanSha256 (New-CollectorHash 'plan') -NativeProfilePath $missing } 'collect CLI refuses non-Mac before source access' 'Live Stage B requires macOS'
        Assert-CollectorTrue (-not (Test-Path -LiteralPath $common.OutputDirectory)) 'CLI refusal does not create output'
    } else {
        # No fake platform override: the synthetic collection guard above runs
        # everywhere, while this exact platform refusal is Windows-only.
        Assert-CollectorTrue $true 'non-Mac CLI refusal case is not dispatched on macOS'
    }
}
Invoke-CollectorCase 'owned-output-is-fresh-and-excludes-input-trees' {
    $parent = New-CollectorCaseRoot 'output-boundaries'
    $source = New-SwiftUIOverlayProbeOwnedDirectory -Root $parent -RelativePath 'source'
    Assert-CollectorThrows { New-SwiftUIOverlayProbeOutputDirectory -Path (Join-Path $source 'forbidden') -ForbiddenRoots @($source) } 'output cannot be nested in source' 'cannot modify'
    Assert-CollectorTrue (-not (Test-Path -LiteralPath (Join-Path $source 'forbidden'))) 'forbidden output is not created'
    $fresh = New-SwiftUIOverlayProbeOutputDirectory -Path (Join-Path $parent 'fresh') -ForbiddenRoots @($source)
    Assert-CollectorTrue ([IO.Directory]::Exists($fresh)) 'fresh owned output exists'
    Assert-CollectorThrows { New-SwiftUIOverlayProbeOutputDirectory -Path $fresh -ForbiddenRoots @($source) } 'output does not overwrite or retry' 'already exists'
    Assert-CollectorThrows { New-SwiftUIOverlayProbeOutputDirectory -Path 'relative-output' -ForbiddenRoots @() } 'relative output refused' 'absolute'
    Assert-CollectorThrows { New-SwiftUIOverlayProbeOwnedDirectory -Root $parent -RelativePath '../escape' } 'relative path cannot escape owned root'
    Assert-CollectorThrows { New-SwiftUIOverlayProbeOwnedDirectory -Root $parent -RelativePath 'fresh' } 'owned directory must also be absent'
}
Invoke-CollectorCase 'bounded-copy-preserves-exact-bytes-and-source' {
    $root = New-CollectorCaseRoot 'copy'
    $bytes = [byte[]]@(0, 1, 13, 10, 255, 254, 42)
    $source = Write-CollectorBytes (Join-Path $root 'source.bin') $bytes
    $hash = New-CollectorHash 'not-the-bytes'
    $expected = Get-SwiftUIStateObjectBytesSHA256 $bytes
    $destination = Join-Path $root 'copy.bin'
    $copy = Copy-SwiftUIOverlayProbeBoundedFile -Source $source -Destination $destination -MaximumBytes $bytes.Length -ExpectedSha256 $expected
    Assert-CollectorTrue ($copy.bytes -eq $bytes.Length -and $copy.sha256 -ceq $expected) 'copy accepts exact inclusive limit'
    Assert-CollectorTrue ((Get-SwiftUIStateObjectFileHash $source -MaxBytes 32).sha256 -ceq $expected) 'source bytes remain unchanged'
    Assert-CollectorTrue ([Convert]::ToBase64String([IO.File]::ReadAllBytes($destination)) -ceq [Convert]::ToBase64String($bytes)) 'binary content is unmodified'
    Assert-CollectorThrows { Copy-SwiftUIOverlayProbeBoundedFile -Source $source -Destination $destination -MaximumBytes 32 -ExpectedSha256 $expected } 'existing destination cannot be overwritten'
    Assert-CollectorThrows { Copy-SwiftUIOverlayProbeBoundedFile -Source $source -Destination (Join-Path $root 'too-small.bin') -MaximumBytes ($bytes.Length - 1) } 'copy bound refuses before publication' 'copy budget'
    Assert-CollectorTrue (-not (Test-Path -LiteralPath (Join-Path $root 'too-small.bin'))) 'over-limit source never creates destination'
    Assert-CollectorThrows { Copy-SwiftUIOverlayProbeBoundedFile -Source $source -Destination (Join-Path $root 'wrong-hash.bin') -MaximumBytes 32 -ExpectedSha256 $hash } 'wrong expected hash is not accepted' 'bound source hash'
    Assert-CollectorThrows { Copy-SwiftUIOverlayProbeBoundedFile -Source $root -Destination (Join-Path $root 'directory-copy') -MaximumBytes 32 } 'a directory is not a copyable regular file'
}
Invoke-CollectorCase 'json-writer-is-bounded-and-create-new' {
    $root = New-CollectorCaseRoot 'new-json'
    $value = [pscustomobject]@{ fixture = 'SYNTHETIC'; value = 42 }
    $file = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $root 'value.json') -Value $value -MaximumBytes 256
    $read = Read-SwiftUIOverlayMetadata -Path $file.path -MaximumBytes 1MB
    Assert-CollectorTrue ($read.sha256 -ceq $file.sha256 -and $read.value.value -eq 42) 'real strict reader reads exact writer output'
    Assert-CollectorTrue ([IO.File]::ReadAllBytes($file.path)[0] -eq 123) 'writer has no UTF-8 BOM'
    Assert-CollectorThrows { Write-SwiftUIOverlayProbeNewJson -Path $file.path -Value $value } 'JSON writer cannot overwrite its seal'
    $tooSmall = Join-Path $root 'too-small.json'
    Assert-CollectorThrows { Write-SwiftUIOverlayProbeNewJson -Path $tooSmall -Value $value -MaximumBytes 1 } 'JSON byte budget is checked before writing' 'byte limit'
    Assert-CollectorTrue (-not (Test-Path -LiteralPath $tooSmall)) 'over-limit metadata was never created'
}
Invoke-CollectorCase 'exact-field-validation-is-case-sensitive' {
    Assert-SwiftUIOverlayProbeExactFields -Value ([pscustomobject]@{ alpha = 1; beta = 2 }) -Names @('alpha', 'beta') -Context 'synthetic'
    Assert-CollectorTrue $true 'exact fields are accepted'
    Assert-CollectorThrows { Assert-SwiftUIOverlayProbeExactFields -Value ([pscustomobject]@{ Alpha = 1; beta = 2 }) -Names @('alpha', 'beta') -Context 'synthetic' } 'case drift is rejected' 'missing exact field'
    Assert-CollectorThrows { Assert-SwiftUIOverlayProbeExactFields -Value ([pscustomobject]@{ alpha = 1; beta = 2; extra = 3 }) -Names @('alpha', 'beta') -Context 'synthetic' } 'additional fields are rejected'
    Assert-CollectorThrows { Assert-SwiftUIOverlayProbeExactFields -Value @{ alpha = 1; beta = 2 } -Names @('alpha', 'beta') -Context 'synthetic' } 'runtime dictionary is not a decoded JSON object'
}
Invoke-CollectorCase 'request-plan-expands-targets-cxx-and-four-controls' {
    $plan = New-CollectorPlan -BothCxxModes
    $requests = New-SwiftUIOverlayProbeRequestSchedule -Plan $plan
    Assert-CollectorTrue ($requests.Count -eq 16) 'one pair expands to both targets, both modes, four controls'
    Assert-CollectorTrue (@($requests.requestId | Sort-Object -Unique).Count -eq 16) 'every cell has a unique request ID'
    $again = New-SwiftUIOverlayProbeRequestSchedule -Plan $plan
    Assert-CollectorTrue (($requests.requestId -join ',') -ceq ($again.requestId -join ',')) 'same sealed plan yields deterministic identities and order'
    foreach ($request in $requests) {
        $candidate = @($plan.pairs[0].sourceCandidates | Where-Object { $_.target -ceq $request.target })
        Assert-CollectorTrue ($request.candidateRecordIds.Count -eq 1 -and $request.candidateRecordIds[0] -ceq $candidate[0].recordId) 'candidate joins preserve exact target occurrence'
        Assert-CollectorTrue ($request.definitionOccurrenceId -ceq $plan.pairs[0].definitionOccurrenceId -and $request.rawDefinitionSha256 -ceq $plan.pairs[0].rawDefinitionSha256) 'definition identity remains attached to every cell'
        Assert-CollectorTrue ($request.overlayNameOccurrences.Count -eq 3 -and $request.overlayNameOccurrences[0].name -ceq $request.overlayNameOccurrences[1].name -and $request.overlayNameOccurrences[1].index -eq 1) 'duplicate overlay names retain positions'
        $expectedImports = switch ($request.control) {
            'owner-only' { 'Alpha' }; 'bystander-only' { 'Beta' }
            'owner-bystander' { 'Alpha,Beta' }; 'bystander-owner' { 'Beta,Alpha' }
        }
        Assert-CollectorTrue (($request.source.imports -join ',') -ceq $expectedImports) 'source preserves exact requested import control'
        Assert-CollectorTrue ($request.source.sha256 -ceq (Get-SwiftUIStateObjectBytesSHA256 ($script:CollectorUtf8.GetBytes($request.source.text)))) 'source hash binds retained UTF-8 text'
    }
    $changed = Copy-CollectorValue $plan; $changed.file.sha256 = New-CollectorHash 'different-plan'
    Assert-CollectorTrue ((New-SwiftUIOverlayProbeRequestSchedule $changed)[0].requestId -cne $requests[0].requestId) 'plan hash contributes to the request identity'
}
Invoke-CollectorCase 'request-plan-rejects-ambiguous-or-missing-candidate-joins' {
    $missing = New-CollectorPlan
    $missing.pairs[0].sourceCandidates = @($missing.pairs[0].sourceCandidates[1])
    Assert-CollectorThrows { New-SwiftUIOverlayProbeRequestSchedule $missing } 'missing target candidate is not inferred' 'one exact source candidate'
    $duplicate = New-CollectorPlan
    $duplicate.pairs[0].sourceCandidates += Copy-CollectorValue $duplicate.pairs[0].sourceCandidates[0]
    Assert-CollectorThrows { New-SwiftUIOverlayProbeRequestSchedule $duplicate } 'duplicate target candidate is not deduplicated silently' 'one exact source candidate'
    $caseDrift = New-CollectorPlan
    $caseDrift.pairs[0].sourceCandidates[0].target = 'ARM64-apple-macosx26.5'
    Assert-CollectorThrows { New-SwiftUIOverlayProbeRequestSchedule $caseDrift } 'candidate target matching is case sensitive' 'one exact source candidate'
}
Invoke-CollectorCase 'request-plan-validates-source-identifiers-before-scheduling' {
    foreach ($name in @('_', 'Alpha; import Secret', 'Alpha.Beta', ('Alpha' + [char]10 + 'import Secret'), ('A' * 129))) {
        $plan = New-CollectorPlan; $plan.pairs[0].declaringModule = $name
        Assert-CollectorThrows { New-SwiftUIOverlayProbeRequestSchedule $plan } 'source fragments and unsupported names cannot enter schedule' 'module identifier'
    }
    $self = New-CollectorPlan; $self.pairs[0].bystanderModule = $self.pairs[0].declaringModule
    Assert-CollectorThrows { New-SwiftUIOverlayProbeRequestSchedule $self } 'self-import is explicit unsupported context' 'Self-cross-import'
    $keyword = New-CollectorPlan; $keyword.pairs[0].declaringModule = 'class'
    $requests = New-SwiftUIOverlayProbeRequestSchedule $keyword
    Assert-CollectorTrue ($requests[0].source.text.Contains('import ' + [char]96 + 'class' + [char]96)) 'valid keyword module is escaped, not interpolated as code'
}
Invoke-CollectorCase 'request-plan-empty-definitions-stay-unprobed' {
    $plan = New-CollectorPlan -EmptyNames
    $requests = New-SwiftUIOverlayProbeRequestSchedule $plan
    Assert-CollectorTrue ($requests.Count -eq 0) 'selected empty definition creates no native requests'
    Assert-CollectorTrue ($plan.pairs.Count -eq 1 -and $plan.pairs[0].overlayNameOccurrences.Count -eq 0) 'empty selected occurrence stays in its plan'
}
Invoke-CollectorCase 'request-plan-hard-ceiling-has-exact-boundary' {
    $exact = New-SwiftUIOverlayProbeRequestSchedule (New-CollectorPlan -PairCount 4 -BothCxxModes)
    Assert-CollectorTrue ($exact.Count -eq 64) '64 control cells fit the hard ceiling'
    Assert-CollectorThrows { New-SwiftUIOverlayProbeRequestSchedule (New-CollectorPlan -PairCount 5 -BothCxxModes) } 'over-64 controls fail before launches' 'exceeds 64'
}
Invoke-CollectorCase 'schedule-natural-results-and-empty-input-do-not-invent-closure' {
    $state = New-SwiftUIOverlayProbeScheduleState
    $context = [pscustomobject]@{ calls = 0 }
    $requests = New-CollectorSimpleRequests 3
    Invoke-SwiftUIOverlayProbeSchedule -Requests $requests -State $state -Context $context -Execute {
        param($request, $testContext)
        $testContext.calls++
        $outcome = if ($testContext.calls -eq 2) { 'frontend-rejected' } else { 'import-controls-recorded' }
        New-CollectorReceipt $request $outcome
    }
    Assert-CollectorTrue ($context.calls -eq 3 -and $state.results.Count -eq 3 -and $state.requestAttempts -eq 3) 'ordinary closed failures do not suppress subsequent planned requests'
    Assert-CollectorTrue (-not $state.stopped -and -not $state.descendantClosureRequired) 'normal completion does not create a descendant observation'
    Invoke-SwiftUIOverlayProbeSchedule -Requests @() -State $state -Context $context -Execute { throw 'empty schedule must not invoke callback' }
    Assert-CollectorTrue ($context.calls -eq 3 -and $state.results.Count -eq 3) 'empty scheduling preserves prior state'
    $state.clock.Stop()
}
Invoke-CollectorCase 'schedule-uncertain-execution-stops-every-later-phase' {
    foreach ($closure in @($true, $false)) {
        $state = New-SwiftUIOverlayProbeScheduleState
        $context = [pscustomobject]@{ calls = 0; closure = $closure }
        $requests = New-CollectorSimpleRequests 3
        Invoke-SwiftUIOverlayProbeSchedule -Requests $requests -State $state -Context $context -Execute {
            param($request, $testContext)
            $testContext.calls++
            New-CollectorReceipt $request 'uncertain-or-unusable-evidence' $true $testContext.closure
        }
        Assert-CollectorTrue ($context.calls -eq 1 -and $state.stopped) 'first stop prevents all remaining callbacks'
        Assert-CollectorTrue ($state.results[1].outcome -ceq 'not-run' -and $state.results[2].outcome -ceq 'not-run') 'later requests retain explicit not-run records'
        Assert-CollectorTrue ($state.descendantClosureRequired -eq $closure) 'closure requirement remains an explicit receipt fact'
        Invoke-SwiftUIOverlayProbeSchedule -Requests (New-CollectorSimpleRequests 1) -State $state -Context $context -Execute { throw 'stopped state must not resume' }
        Assert-CollectorTrue ($context.calls -eq 1 -and $state.results.Count -eq 4 -and $state.results[3].outcome -ceq 'not-run') 'same stopped state cannot resume at extraction boundary'
        $state.clock.Stop()
    }
}
Invoke-CollectorCase 'schedule-malformed-receipts-make-launch-unknown-and-stop' {
    foreach ($kind in @('no-output', 'extra-output', 'not-object', 'wrong-id', 'wrong-kind', 'stop-string', 'closure-string', 'throws', 'closure-without-stop')) {
        $state = New-SwiftUIOverlayProbeScheduleState
        $context = [pscustomobject]@{ calls = 0; mutation = $kind }
        Invoke-SwiftUIOverlayProbeSchedule -Requests (New-CollectorSimpleRequests 3) -State $state -Context $context -Execute {
            param($request, $testContext)
            $testContext.calls++
            $receipt = New-CollectorReceipt $request
            switch ($testContext.mutation) {
                'no-output' { return }
                'extra-output' { $receipt; $receipt; return }
                'not-object' { return 'not a closure receipt' }
                'wrong-id' { $receipt.requestId = New-CollectorHash 'wrong-id' }
                'wrong-kind' { $receipt.kind = 'supplemental-extractor' }
                'stop-string' { $receipt.stopLaterCommands = 'false' }
                'closure-string' { $receipt.descendantClosureRequired = 'false' }
                'throws' { throw 'SYNTHETIC adapter threw before recording closure' }
                'closure-without-stop' { $receipt.descendantClosureRequired = $true }
            }
            return $receipt
        }
        Assert-CollectorTrue ($context.calls -eq 1 -and $state.requestAttempts -eq 1) ($kind + ': no second callback')
        Assert-CollectorTrue ($state.results[0].outcome -ceq 'execution-adapter-failed') ($kind + ': adapter mismatch is retained')
        Assert-CollectorTrue ($null -eq $state.results[0].nativeInvocationAttempted -and $null -eq $state.results[0].processStarted) ($kind + ': unknown launch is not relabeled as not started')
        Assert-CollectorTrue ($state.stopped -and $state.descendantClosureRequired -and $state.results[1].outcome -ceq 'not-run') ($kind + ': uncertainty requires closure and stops remainder')
        $state.clock.Stop()
    }
}
Invoke-CollectorCase 'schedule-request-and-elapsed-budgets-stop-before-next-callback' {
    foreach ($alreadyAttempted in @(127, 128)) {
        $state = New-SwiftUIOverlayProbeScheduleState
        $state.requestAttempts = $alreadyAttempted
        $context = [pscustomobject]@{ calls = 0 }
        Invoke-SwiftUIOverlayProbeSchedule -Requests (New-CollectorSimpleRequests 2) -State $state -Context $context -Execute {
            param($request, $testContext); $testContext.calls++; New-CollectorReceipt $request
        }
        Assert-CollectorTrue ($context.calls -eq (128 - $alreadyAttempted)) 'request cap is checked before callback'
        Assert-CollectorTrue ($state.results[1].outcome -ceq 'not-run' -and $state.stopReason -ceq 'request-or-elapsed-batch-budget') 'budget exhaustion retains explicit not-run receipt'
        Assert-CollectorTrue (-not $state.descendantClosureRequired) 'budget refusal does not invent process uncertainty'
        $state.clock.Stop()
    }
    $state = New-SwiftUIOverlayProbeScheduleState
    $state.clock.Stop()
    $state.clock = [pscustomobject]@{ Elapsed = [timespan]::FromSeconds($script:CollectorPolicy.maximumBatchSeconds) }
    $context = [pscustomobject]@{ calls = 0 }
    Invoke-SwiftUIOverlayProbeSchedule -Requests (New-CollectorSimpleRequests 1) -State $state -Context $context -Execute {
        param($request, $testContext); $testContext.calls++; New-CollectorReceipt $request
    }
    Assert-CollectorTrue ($context.calls -eq 0 -and $state.results[0].outcome -ceq 'not-run') 'elapsed boundary uses fake clock, no sleep or process'
}
Invoke-CollectorCase 'extraction-dedup-retains-all-exact-observation-associations' {
    $plan = New-CollectorPlan
    $one = New-CollectorPositive 'first'
    $two = New-CollectorPositive 'second' -Control 'bystander-owner'
    $three = New-CollectorPositive 'second-definition'
    $imports = @((New-CollectorImportResult @($one)), (New-CollectorImportResult @($two)), (New-CollectorImportResult @($three)))
    $schedule = New-SwiftUIOverlayProbeExtractionSchedule -Plan $plan -ImportResults $imports
    Assert-CollectorTrue ($schedule.requests.Count -eq 1 -and $schedule.positiveFrontendObservations.Count -eq 3) 'same module/target/Cxx shares one extraction but keeps every positive record'
    $request = $schedule.requests[0]
    Assert-CollectorTrue ($request.frontendRequestId -ceq $one.requestId -and $request.positiveFrontendObservationIds.Count -eq 1 -and $request.positiveFrontendObservationIds[0] -ceq $one.observationId) 'first exact observation remains explicit extraction basis'
    Assert-CollectorTrue (($request.candidateRecordIds -join ',') -ceq ($one.candidateRecordIds -join ',')) 'basis candidate IDs are not replaced by an ambiguous merged tuple'
    Assert-CollectorTrue (($request.relatedFrontendObservationIds -join ',') -ceq (@($one.observationId, $two.observationId, $three.observationId) -join ',')) 'all related observation IDs retain their original order'
    foreach ($observation in @($one, $two, $three)) {
        $retained = @($schedule.positiveFrontendObservations | Where-Object { $_.observationId -ceq $observation.observationId })
        Assert-CollectorTrue ($retained.Count -eq 1 -and ($retained[0].candidateRecordIds -join ',') -ceq ($observation.candidateRecordIds -join ',')) 'each related observation preserves its own exact candidate IDs'
    }
}
Invoke-CollectorCase 'extraction-distinguishes-contexts-and-does-not-use-single-import-controls' {
    $plan = New-CollectorPlan
    $observations = @(
        (New-CollectorPositive 'base'),
        (New-CollectorPositive 'intel' -Target 'x86_64-apple-macosx26.5'),
        (New-CollectorPositive 'cxx' -CxxMode 'default'),
        (New-CollectorPositive 'module' -Module '_AlphaBeta'),
        (New-CollectorPositive 'owner-only' -Control 'owner-only'),
        (New-CollectorPositive 'bystander-only' -Control 'bystander-only')
    )
    $imports = @($observations | ForEach-Object { New-CollectorImportResult @($_) })
    $schedule = New-SwiftUIOverlayProbeExtractionSchedule -Plan $plan -ImportResults $imports
    Assert-CollectorTrue ($schedule.requests.Count -eq 4 -and $schedule.positiveFrontendObservations.Count -eq 4) 'module, target and Cxx each preserve separate extraction context'
    Assert-CollectorTrue (@($schedule.requests | Where-Object { $_.control -cne 'supplemental-direct-module' }).Count -eq 0) 'all extraction controls use the fixed direct-module profile'
    $empty = New-SwiftUIOverlayProbeExtractionSchedule -Plan $plan -ImportResults @()
    Assert-CollectorTrue ($empty.requests.Count -eq 0 -and $empty.positiveFrontendObservations.Count -eq 0) 'no positive combined import creates no extraction'
}
Invoke-CollectorCase 'native-profile-reader-binds-exact-source-layout-and-anchor-bytes' {
    $fixture = New-CollectorProfileFixture
    $read = Read-CollectorProfileValue $fixture.profile $fixture.inputs
    Assert-CollectorTrue ($read.profile.frontend.sha256 -ceq $fixture.profile.frontend.sha256) 'actual strict native-profile reader accepts structurally valid synthetic-shaped metadata'
    Assert-CollectorTrue (-not $read.profile.qualification.reviewedIdentity -and -not $read.profile.observations.frontendVersionExecuted) 'read does not qualify SDK or frontend execution'
    foreach ($mutation in @('profile-hash', 'source-hash', 'frontend-path', 'extractor-bytes', 'duplicate-anchor', 'anchor-sha', 'frontend-boundary', 'canonical-outside', 'negative-size', 'extra-field', 'field-case')) {
        $fixture = New-CollectorProfileFixture
        $expectedHash = $null
        switch ($mutation) {
            'profile-hash' { $expectedHash = New-CollectorHash 'wrong-profile' }
            'source-hash' { $fixture.profile.sourceArtifacts.inventorySha256 = New-CollectorHash 'wrong-inventory' }
            'frontend-path' { $fixture.profile.frontend.path += '-other' }
            'extractor-bytes' { $fixture.profile.extractor.bytes++ }
            'duplicate-anchor' { $fixture.profile.anchors[1] = Copy-CollectorValue $fixture.profile.anchors[0] }
            'anchor-sha' { $fixture.profile.anchors[0].file.sha256 = New-CollectorHash 'wrong-anchor' }
            'frontend-boundary' { $fixture.profile.frontend.allowedPhysicalRoot = '/SYNTHETIC-Xcode.app' }
            'canonical-outside' { $fixture.profile.frontend.canonicalPath = '/outside/swift-frontend' }
            'negative-size' { $fixture.profile.frontend.bytes = -1 }
            'extra-field' { $fixture.profile | Add-Member -NotePropertyName extraArguments -NotePropertyValue @('-I', '/other') }
            'field-case' {
                $value = $fixture.profile.status
                $fixture.profile.PSObject.Properties.Remove('status')
                $fixture.profile | Add-Member -NotePropertyName Status -NotePropertyValue $value
            }
        }
        Assert-CollectorThrows { Read-CollectorProfileValue $fixture.profile $fixture.inputs $expectedHash } ($mutation + ': mismatched profile is rejected')
    }
}
Invoke-CollectorCase 'native-profile-cannot-promote-qualification-or-pretend-synthetic-is-native' {
    foreach ($field in @('reviewedIdentity', 'declarationCompleteness', 'overlayCompleteness', 'behaviorConformance')) {
        $fixture = New-CollectorProfileFixture; $fixture.profile.qualification.$field = $true
        Assert-CollectorThrows { Read-CollectorProfileValue $fixture.profile $fixture.inputs } ('qualification ' + $field + ' remains false') 'cannot promote qualification'
    }
    foreach ($field in @('nativeCommandsExecuted', 'frontendVersionExecuted', 'nativeProcessSandboxEstablished', 'wholeSDKByteIdentityEstablished')) {
        $fixture = New-CollectorProfileFixture; $fixture.profile.observations.$field = $true
        Assert-CollectorThrows { Read-CollectorProfileValue $fixture.profile $fixture.inputs } ('observation ' + $field + ' cannot be promoted') 'cannot promote execution'
    }
    $fixture = New-CollectorProfileFixture; $fixture.profile.syntheticFixture = $true
    Assert-CollectorThrows { Read-CollectorProfileValue $fixture.profile $fixture.inputs } 'synthetic flag cannot enter public native reader' 'Unsupported, synthetic'
    $fixture = New-CollectorProfileFixture; $fixture.inputs.syntheticFixture = $true
    Assert-CollectorThrows { Read-CollectorProfileValue $fixture.profile $fixture.inputs } 'synthetic source context cannot enter public native reader' 'Unsupported, synthetic'
    $fixture = New-CollectorProfileFixture; $fixture.profile.status = 'complete'
    Assert-CollectorThrows { Read-CollectorProfileValue $fixture.profile $fixture.inputs } 'unreviewed metadata cannot become completed qualification' 'Unsupported, synthetic'
}
Invoke-CollectorCase 'native-profile-strict-json-rejects-duplicate-and-coercible-fields' {
    $fixture = New-CollectorProfileFixture
    $root = New-CollectorCaseRoot 'profile-invalid-json'
    $text = ConvertTo-Json -InputObject $fixture.profile -Depth 50 -Compress
    $duplicate = '{"schemaVersion":1,' + $text.Substring(1)
    $path = Write-CollectorText (Join-Path $root 'duplicate.json') $duplicate
    $sha = Get-SwiftUIStateObjectBytesSHA256 ($script:CollectorUtf8.GetBytes($duplicate))
    Assert-CollectorThrows {
        Invoke-CollectorWithSyntheticLayout { Read-SwiftUIOverlayProbeNativeProfile -Path $path -ExpectedSha256 $sha -Inputs $fixture.inputs }
    } 'real strict parser rejects duplicate JSON properties'
    foreach ($field in @('schemaVersion', 'syntheticFixture')) {
        $fixture = New-CollectorProfileFixture; $fixture.profile.$field = '1'
        Assert-CollectorThrows { Read-CollectorProfileValue $fixture.profile $fixture.inputs } 'profile scalar type cannot be coerced'
    }
    $fixture = New-CollectorProfileFixture; $fixture.profile.frontend.bytes = $true
    Assert-CollectorThrows { Read-CollectorProfileValue $fixture.profile $fixture.inputs } 'boolean is not a byte count'
}

function New-CollectorReportFixture {
    param([scriptblock]$MutatePlan, [scriptblock]$MutateProfile, [switch]$EmptyNames,
        [AllowEmptyCollection()][string[]]$OverlayNames)
    $root = New-CollectorCaseRoot 'synthetic-report'
    [void](New-SwiftUIOverlayProbeOwnedDirectory -Root $root -RelativePath 'inputs')
    [void](New-SwiftUIOverlayProbeOwnedDirectory -Root $root -RelativePath 'evidence')
    [void](Write-CollectorText (Join-Path $root 'SYNTHETIC-FIXTURE.txt') 'PARSER TEST ONLY. This native-shaped report is generated synthetic data, not a native capture or SDK identity observation.')
    $profileFixture = New-CollectorProfileFixture
    $profile = $profileFixture.profile
    # The production report reader requires the fixed recorded SDK spelling.
    # These strings are serialized only; no selected installation is opened.
    $recordedDeveloper = (Get-SwiftUIOverlayProbeNativePolicy).sdkPath.Split('/Platforms/')[0]
    $profileJson = (ConvertTo-Json -InputObject $profile -Depth 60 -Compress).Replace($script:CollectorFixtureLayout.developer, $recordedDeveloper)
    $profile = ConvertFrom-Json -InputObject $profileJson -Depth 60
    if ($null -ne $MutateProfile) { & $MutateProfile $profile }
    $profileFile = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $root 'inputs/native-profile.json') -Value $profile -MaximumBytes 1MB
    $resolved = New-CollectorPlan -EmptyNames:$EmptyNames
    if ($PSBoundParameters.ContainsKey('OverlayNames')) {
        $resolved.pairs[0].overlayNameOccurrences = @(for ($index = 0; $index -lt $OverlayNames.Count; $index++) {
            [pscustomobject]@{ index = $index; name = $OverlayNames[$index] }
        })
    }
    $pairs = @($resolved.pairs | ForEach-Object {
        [pscustomobject][ordered]@{
            pairId = $_.pairId; definitionOccurrenceId = $_.definitionOccurrenceId
            rawDefinitionSha256 = $_.rawDefinitionSha256
            declaringModule = $_.declaringModule; bystanderModule = $_.bystanderModule
            overlayNameOccurrences = Copy-CollectorValue $_.overlayNameOccurrences
            sourceCandidateIds = @($_.sourceCandidates.recordId)
        }
    })
    $plan = [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'swiftui-overlay-probe-plan'
        sourceArtifacts = New-CollectorSourceArtifacts; nativeProfileSha256 = $profileFile.sha256
        languageMode = '6'; targetContexts = Copy-CollectorValue $resolved.targetContexts
        pairs = $pairs
        limits = [pscustomobject]@{ maximumDefinitionPairs = 4; maximumDistinctOverlayModules = 16 }
    }
    if ($null -ne $MutatePlan) { & $MutatePlan $plan }
    $planFile = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $root 'inputs/probe-plan.json') -Value $plan -MaximumBytes 1MB
    $resolved.file.sha256 = $planFile.sha256
    $requests = New-SwiftUIOverlayProbeRequestSchedule -Plan $resolved
    $rows = @($requests | ForEach-Object {
        [pscustomobject][ordered]@{
            requestId = $_.requestId; kind = $_.kind; outcome = 'not-run'
            nativeInvocationAttempted = $false; processStarted = $false
            stopLaterCommands = $true; descendantClosureRequired = $false; resultFile = $null
        }
    })
    $dispositions = @()
    foreach ($pair in $resolved.pairs) {
        foreach ($candidate in $pair.sourceCandidates) {
            $dispositions += [pscustomobject][ordered]@{
                candidateId = $candidate.recordId; definitionOccurrenceId = $pair.definitionOccurrenceId
                pairId = $pair.pairId; target = $candidate.target; disposition = 'selected'
                expectedOverlayNameCount = $pair.overlayNameOccurrences.Count; nativeLoadEvidence = 'not-performed'
            }
        }
    }
    foreach ($target in $script:CollectorFixture.targets) {
        $dispositions += [pscustomobject][ordered]@{
            candidateId = New-CollectorHash ('unselected-' + $target)
            definitionOccurrenceId = New-CollectorHash 'unselected-definition'
            pairId = $null; target = $target; disposition = 'unselected'
            expectedOverlayNameCount = 1; nativeLoadEvidence = 'not-performed'
        }
    }
    $tooling = Write-SwiftUIOverlayProbeToolingSnapshot -OutputDirectory $root
    $report = [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'swiftui-overlay-probe-report-v1'
        batchId = Get-SwiftUIOverlayId @('overlay-probe-batch-v1', $planFile.sha256, $profileFile.sha256)
        executionKind = 'native'; successful = $false; status = 'incomplete-or-failed'
        sourceArtifacts = New-CollectorSourceArtifacts
        plan = [pscustomobject]@{ path = 'inputs/probe-plan.json'; bytes = $planFile.bytes; sha256 = $planFile.sha256 }
        nativeProfile = [pscustomobject]@{ path = 'inputs/native-profile.json'; bytes = $profileFile.bytes; sha256 = $profileFile.sha256 }
        selection = [pscustomobject][ordered]@{
            meaning = 'explicit bounded batch only; unselected candidates remain unresolved'
            candidateDispositions = $dispositions; selectedPairIds = @($resolved.pairs.pairId)
            duplicateNameOccurrencesRemainInPlan = $true; definitionOccurrenceTriggered = $false
        }
        policy = Get-SwiftUIOverlayProbeCollectionPolicy
        tooling = @($tooling | ForEach-Object {
            [pscustomobject]@{
                path = 'inputs/tooling/' + $_.relativePath; bytes = $_.bytes; sha256 = $_.sha256
                interpretation = 'source file observed before launch; not an independent attestation of in-memory execution'
            }
        })
        processBoundary = [pscustomobject][ordered]@{
            nativeSandboxEstablished = $false; inheritedEnvironmentIsNotSealed = $true
            wholeSDKByteIdentityEstablished = $false; atomicLoadedImageAttestation = $false
            descendantsClosed = $null; descendantClosureRequired = $false
            followup = 'No resume in this profile. After termination uncertainty, an operator must establish descendant closure before authorizing another native command.'
            unsealedDisposableNamespace = '.work'
            unsealedMeaning = 'compiler caches, original traces and original graph outputs; no disk quota or immutable evidence claim'
        }
        requests = $rows
        supplemental = [pscustomobject]@{ status = 'not-attempted'; report = $null }
        errors = @('SYNTHETIC fixture: no native request was run.')
        nativeInvocationsAttempted = 0; confirmedProcessesStarted = 0; sourceSealsRechecked = $false
        qualification = Copy-CollectorValue $script:CollectorFixture.qualification
        files = Get-SwiftUIOverlayProbePayloadInventory -Root $root
    }
    return [pscustomobject]@{
        root = $root; report = $report; plan = $plan; profile = $profile
        resolvedPlan = $resolved; requests = $requests
    }
}
function Save-CollectorReportFixture {
    param($Fixture)
    $file = Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $Fixture.root 'probe-report.json') -Value $Fixture.report -MaximumBytes 16MB
    [void](Write-CollectorText (Join-Path $Fixture.root 'probe-report.sha256') ($file.sha256 + '  probe-report.json' + [char]10))
    return [pscustomobject]@{ root = $Fixture.root; sha256 = $file.sha256; report = $Fixture.report }
}
function Assert-CollectorReportRejected {
    param($Fixture, [string]$Message, [string]$ExpectedMessage = '.')
    $saved = Save-CollectorReportFixture $Fixture
    Assert-CollectorThrows { Read-SwiftUIOverlayProbeReport -Root $saved.root -ExpectedSha256 $saved.sha256 } $Message $ExpectedMessage
}
function New-CollectorDirectoryAlias {
    param([string]$Path, [string]$Target)
    if ($IsWindows) {
        [void](New-Item -ItemType Junction -Path $Path -Target $Target -ErrorAction Stop)
    } else {
        [void][IO.Directory]::CreateSymbolicLink($Path, $Target)
    }
}

Invoke-CollectorCase 'payload-inventory-sorts-seals-and-excludes-only-root-work' {
    $root = New-CollectorCaseRoot 'payload'
    $work = New-SwiftUIOverlayProbeOwnedDirectory -Root $root -RelativePath '.work'
    $nested = New-SwiftUIOverlayProbeOwnedDirectory -Root $root -RelativePath 'evidence/.work'
    [void](Write-CollectorText (Join-Path $work 'disposable.txt') 'SYNTHETIC unsealed cache')
    [void](Write-CollectorText (Join-Path $nested 'retained.txt') 'SYNTHETIC retained nested namespace')
    [void](Write-CollectorText (Join-Path $root 'z.txt') 'last')
    [void](Write-CollectorText (Join-Path $root 'A.txt') 'first')
    [void](Write-CollectorText (Join-Path $root '.in-progress') 'publication marker')
    $inventory = Get-SwiftUIOverlayProbePayloadInventory -Root $root
    Assert-CollectorTrue (($inventory.path -join ',') -ceq 'A.txt,evidence/.work/retained.txt,z.txt') 'only root reserved names are excluded and remaining entries sort ordinally'
    $before = ConvertTo-Json -InputObject $inventory -Compress
    [IO.File]::WriteAllText((Join-Path $work 'disposable.txt'), 'changed synthetic cache', $script:CollectorUtf8)
    Assert-CollectorTrue ((ConvertTo-Json -InputObject (Get-SwiftUIOverlayProbePayloadInventory $root) -Compress) -ceq $before) 'disposable work is explicitly outside retained evidence claim'
    [IO.File]::WriteAllText((Join-Path $root 'z.txt'), 'changed retained payload', $script:CollectorUtf8)
    Assert-CollectorTrue ((Get-SwiftUIOverlayProbePayloadInventory $root)[2].sha256 -cne $inventory[2].sha256) 'retained evidence changes alter the seal'
}
Invoke-CollectorCase 'copy-output-and-payload-reject-directory-aliases' {
    $root = New-CollectorCaseRoot 'aliases'
    $target = New-SwiftUIOverlayProbeOwnedDirectory -Root $root -RelativePath 'target'
    $alias = Join-Path $root 'alias'
    [void](Write-CollectorText (Join-Path $target 'value.txt') 'SYNTHETIC alias target')
    New-CollectorDirectoryAlias -Path $alias -Target $target
    Assert-CollectorThrows { Get-SwiftUIOverlayProbePayloadInventory -Root $root } 'retained evidence cannot silently traverse a directory alias' 'aliases'
    Assert-CollectorThrows { Copy-SwiftUIOverlayProbeBoundedFile -Source (Join-Path $alias 'value.txt') -Destination (Join-Path $root 'copied.txt') -MaximumBytes 128 } 'source copy refuses an aliased ancestor'
    Assert-CollectorThrows { New-SwiftUIOverlayProbeOutputDirectory -Path (Join-Path $alias 'output') -ForbiddenRoots @() } 'new output cannot redirect through an alias' 'aliases'
    Assert-CollectorTrue (-not (Test-Path -LiteralPath (Join-Path $target 'output'))) 'alias refusal precedes output creation'
}
Invoke-CollectorCase 'extraction-rejects-ineligible-relabeled-and-failed-frontend-records' {
    foreach ($mutation in @('ineligible', 'eligible-string', 'wrong-parent', 'failed-result', 'stopped-result')) {
        $positive = New-CollectorPositive $mutation
        $result = New-CollectorImportResult @($positive)
        switch ($mutation) {
            'ineligible' { $positive.eligible = $false }
            'eligible-string' { $positive.eligible = 'true' }
            'wrong-parent' { $result.requestId = New-CollectorHash 'different-enclosing-request' }
            'failed-result' { $result.outcome = 'frontend-rejected' }
            'stopped-result' { $result.stopLaterCommands = $true }
        }
        if ($mutation -cin @('failed-result', 'stopped-result')) {
            $schedule = New-SwiftUIOverlayProbeExtractionSchedule -Plan (New-CollectorPlan) -ImportResults @($result)
            Assert-CollectorTrue ($schedule.requests.Count -eq 0 -and $schedule.positiveFrontendObservations.Count -eq 0) ($mutation + ': incomplete cell cannot authorize extraction')
            Assert-CollectorTrue ($result.positiveFrontendObservations.Count -eq 1) 'locally positive raw record remains retained in its failed cell'
        } else {
            Assert-CollectorThrows { New-SwiftUIOverlayProbeExtractionSchedule -Plan (New-CollectorPlan) -ImportResults @($result) } ($mutation + ': invalid positive record cannot schedule extraction') 'failed, ineligible or relabeled'
        }
    }
}
Invoke-CollectorCase 'sealed-report-accepts-unqualified-complete-not-run-accounting' {
    $fixture = New-CollectorReportFixture
    $saved = Save-CollectorReportFixture $fixture
    $read = Read-SwiftUIOverlayProbeReport -Root $saved.root -ExpectedSha256 $saved.sha256
    Assert-CollectorTrue (-not $read.successful -and $read.status -ceq 'incomplete-or-failed') 'valid failed report remains failed'
    Assert-CollectorTrue ($read.report.requests.Count -eq 8 -and $read.report.nativeInvocationsAttempted -eq 0 -and $read.report.confirmedProcessesStarted -eq 0) 'all eight planned controls remain explicit not-run records'
    Assert-CollectorTrue ($read.report.selection.candidateDispositions.Count -eq 4 -and @($read.report.selection.candidateDispositions | Where-Object { $_.disposition -ceq 'unselected' }).Count -eq 2) 'unselected candidates remain present and unresolved'
    Assert-CollectorTrue (-not $read.qualification.reviewedIdentity -and -not $read.qualification.overlayCompleteness) 'sealed metadata is not SDK or overlay qualification'
    Assert-CollectorTrue ($read.verification -match 'not an independent native execution attestation') 'reader accurately limits its verification claim'
}
Invoke-CollectorCase 'report-rejects-external-hash-sidecar-and-publication-drift' {
    $fixture = New-CollectorReportFixture; $saved = Save-CollectorReportFixture $fixture
    Assert-CollectorThrows { Read-SwiftUIOverlayProbeReport -Root $saved.root -ExpectedSha256 (New-CollectorHash 'wrong-external-seal') } 'external report hash must be selected exactly' 'external seal'
    $fixture = New-CollectorReportFixture; $saved = Save-CollectorReportFixture $fixture
    [IO.File]::WriteAllText((Join-Path $saved.root 'probe-report.sha256'), $saved.sha256 + ' probe-report.json' + [char]10, $script:CollectorUtf8)
    Assert-CollectorThrows { Read-SwiftUIOverlayProbeReport -Root $saved.root -ExpectedSha256 $saved.sha256 } 'sidecar requires exact spacing and LF' 'sidecar is malformed'
    $fixture = New-CollectorReportFixture; $saved = Save-CollectorReportFixture $fixture
    [void](Write-CollectorText (Join-Path $saved.root '.in-progress') 'SYNTHETIC publication not closed')
    Assert-CollectorThrows { Read-SwiftUIOverlayProbeReport -Root $saved.root -ExpectedSha256 $saved.sha256 } 'in-progress publication cannot become eligible' 'did not close'
    $fixture = New-CollectorReportFixture; $saved = Save-CollectorReportFixture $fixture
    [IO.File]::AppendAllText((Join-Path $saved.root 'probe-report.json'), ' ', $script:CollectorUtf8)
    Assert-CollectorThrows { Read-SwiftUIOverlayProbeReport -Root $saved.root -ExpectedSha256 $saved.sha256 } 'even whitespace report drift changes exact hash' 'external seal'
}
Invoke-CollectorCase 'report-exact-file-membership-rejects-extra-missing-and-changed-payloads' {
    foreach ($mutation in @('extra-file', 'missing-file', 'changed-file', 'altered-entry', 'duplicate-entry', 'missing-entry')) {
        $fixture = New-CollectorReportFixture
        switch ($mutation) {
            'altered-entry' { $fixture.report.files[0].sha256 = New-CollectorHash 'wrong-payload-entry' }
            'duplicate-entry' { $fixture.report.files += Copy-CollectorValue $fixture.report.files[0] }
            'missing-entry' { $fixture.report.files = @($fixture.report.files | Select-Object -Skip 1) }
        }
        $saved = Save-CollectorReportFixture $fixture
        switch ($mutation) {
            'extra-file' { [void](Write-CollectorText (Join-Path $saved.root 'undeclared.txt') 'SYNTHETIC extra payload') }
            'missing-file' { [IO.File]::Delete((Join-Path $saved.root 'SYNTHETIC-FIXTURE.txt')) }
            'changed-file' { [IO.File]::AppendAllText((Join-Path $saved.root 'SYNTHETIC-FIXTURE.txt'), 'drift', $script:CollectorUtf8) }
        }
        Assert-CollectorThrows { Read-SwiftUIOverlayProbeReport -Root $saved.root -ExpectedSha256 $saved.sha256 } ($mutation + ': report retains exact file set and bytes') 'exactPayloadMembership'
    }
}
Invoke-CollectorCase 'report-unsealed-work-does-not-become-evidence' {
    $fixture = New-CollectorReportFixture
    $saved = Save-CollectorReportFixture $fixture
    $work = New-SwiftUIOverlayProbeOwnedDirectory -Root $saved.root -RelativePath '.work'
    [void](Write-CollectorText (Join-Path $work 'cache.bin') 'SYNTHETIC unsealed temporary bytes')
    $read = Read-SwiftUIOverlayProbeReport -Root $saved.root -ExpectedSha256 $saved.sha256
    Assert-CollectorTrue (-not $read.successful -and $read.report.files.Count -eq $fixture.report.files.Count) 'unsealed work changes neither retained file claims nor failed status'
    Assert-CollectorTrue ($read.report.processBoundary.unsealedDisposableNamespace -ceq '.work') 'report explicitly names the unsealed namespace'
}
Invoke-CollectorCase 'report-rejects-synthetic-promoted-and-mistyped-metadata' {
    foreach ($mutation in @('synthetic', 'promoted', 'sandbox', 'sdk-attestation', 'loaded-attestation', 'descendants-closed', 'environment-sealed', 'extra-field', 'scalar-coercion', 'wrong-policy')) {
        $fixture = New-CollectorReportFixture
        switch ($mutation) {
            'synthetic' { $fixture.report.executionKind = 'synthetic-test' }
            'promoted' { $fixture.report.qualification.overlayCompleteness = $true }
            'sandbox' { $fixture.report.processBoundary.nativeSandboxEstablished = $true }
            'sdk-attestation' { $fixture.report.processBoundary.wholeSDKByteIdentityEstablished = $true }
            'loaded-attestation' { $fixture.report.processBoundary.atomicLoadedImageAttestation = $true }
            'descendants-closed' { $fixture.report.processBoundary.descendantsClosed = $true }
            'environment-sealed' { $fixture.report.processBoundary.inheritedEnvironmentIsNotSealed = $false }
            'extra-field' { $fixture.report | Add-Member -NotePropertyName censusComplete -NotePropertyValue $true }
            'scalar-coercion' { $fixture.report.nativeInvocationsAttempted = '0' }
            'wrong-policy' { $fixture.report.policy.maximumNativeRequests++ }
        }
        Assert-CollectorReportRejected $fixture ($mutation + ': report cannot promote or coerce evidence')
    }
}
Invoke-CollectorCase 'report-strict-json-rejects-duplicate-invalid-and-trailing-values' {
    foreach ($mutation in @('duplicate-property', 'invalid-utf8', 'trailing-value')) {
        $fixture = New-CollectorReportFixture
        $text = ConvertTo-Json -InputObject $fixture.report -Depth 80 -Compress
        $bytes = switch ($mutation) {
            'duplicate-property' { $script:CollectorUtf8.GetBytes('{"schemaVersion":1,' + $text.Substring(1)) }
            'invalid-utf8' { [byte[]]@(0x7B, 0x22, 0x78, 0x22, 0x3A, 0x22, 0xC0, 0xAF, 0x22, 0x7D) }
            'trailing-value' { $script:CollectorUtf8.GetBytes($text + ' {}') }
        }
        $sha = Get-SwiftUIStateObjectBytesSHA256 $bytes
        [void](Write-CollectorBytes (Join-Path $fixture.root 'probe-report.json') $bytes)
        [void](Write-CollectorText (Join-Path $fixture.root 'probe-report.sha256') ($sha + '  probe-report.json' + [char]10))
        Assert-CollectorThrows { Read-SwiftUIOverlayProbeReport -Root $fixture.root -ExpectedSha256 $sha } ($mutation + ': real strict JSON reader refuses ambiguous metadata')
    }
}
Invoke-CollectorCase 'report-plan-candidate-target-and-name-occurrences-remain-exact' {
    foreach ($mutation in @('single-target', 'duplicate-context', 'extra-argv', 'wrong-profile-hash', 'language-mode', 'pair-id', 'reordered-duplicate', 'duplicate-candidate', 'source-hash', 'module-fragment', 'unsupported-cxx')) {
        $fixture = New-CollectorReportFixture -MutatePlan {
            param($plan)
            switch ($mutation) {
                'single-target' { $plan.targetContexts = @($plan.targetContexts[0]) }
                'duplicate-context' { $plan.targetContexts += Copy-CollectorValue $plan.targetContexts[0] }
                'extra-argv' { $plan | Add-Member -NotePropertyName arguments -NotePropertyValue @('-I', '/SYNTHETIC-OTHER') }
                'wrong-profile-hash' { $plan.nativeProfileSha256 = New-CollectorHash 'different-selected-profile' }
                'language-mode' { $plan.languageMode = '5' }
                'pair-id' { $plan.pairs[0].pairId = New-CollectorHash 'wrong-pair-identity' }
                'reordered-duplicate' { $plan.pairs[0].overlayNameOccurrences[1].index = 0 }
                'duplicate-candidate' { $plan.pairs[0].sourceCandidateIds[1] = $plan.pairs[0].sourceCandidateIds[0] }
                'source-hash' { $plan.sourceArtifacts.inventorySha256 = New-CollectorHash 'wrong-source-inventory' }
                'module-fragment' { $plan.pairs[0].declaringModule = 'Alpha; import Other' }
                'unsupported-cxx' { $plan.targetContexts[0].cxxInteroperabilityMode = 'automatic' }
            }
        }
        $reason = switch ($mutation) {
            'single-target' { 'Both pinned targets' }
            'duplicate-context' { 'Duplicate retained target context' }
            'extra-argv' { 'unknown field' }
            'wrong-profile-hash' { 'exact native profile' }
            'language-mode' { 'language mode' }
            'pair-id' { 'pair identity' }
            'reordered-duplicate' { 'ordered occurrence' }
            'duplicate-candidate' { 'missing or duplicated' }
            'source-hash' { 'retained-plan.sources' }
            'module-fragment' { 'module identifier' }
            'unsupported-cxx' { 'Only the two pinned' }
        }
        Assert-CollectorReportRejected $fixture ($mutation + ': sealed plan semantics are independently replayed') $reason
    }
}
Invoke-CollectorCase 'report-selection-cannot-forget-candidates-or-claim-census-completion' {
    foreach ($mutation in @('missing-selected', 'duplicate-candidate', 'not-applicable', 'false-selection', 'wrong-pair-list', 'name-count', 'trigger-proof', 'no-duplicates', 'unselected-pair', 'native-load-promoted')) {
        $fixture = New-CollectorReportFixture
        switch ($mutation) {
            'missing-selected' { $fixture.report.selection.candidateDispositions = @($fixture.report.selection.candidateDispositions | Select-Object -Skip 1) }
            'duplicate-candidate' { $fixture.report.selection.candidateDispositions += Copy-CollectorValue $fixture.report.selection.candidateDispositions[0] }
            'not-applicable' { $fixture.report.selection.candidateDispositions[2].disposition = 'not-applicable' }
            'false-selection' { $fixture.report.selection.candidateDispositions[0].disposition = 'unselected' }
            'wrong-pair-list' { $fixture.report.selection.selectedPairIds = @(New-CollectorHash 'wrong-selected-pair') }
            'name-count' { $fixture.report.selection.candidateDispositions[0].expectedOverlayNameCount-- }
            'trigger-proof' { $fixture.report.selection.definitionOccurrenceTriggered = $true }
            'no-duplicates' { $fixture.report.selection.duplicateNameOccurrencesRemainInPlan = $false }
            'unselected-pair' { $fixture.report.selection.candidateDispositions[2].pairId = $fixture.report.selection.selectedPairIds[0] }
            'native-load-promoted' { $fixture.report.selection.candidateDispositions[0].nativeLoadEvidence = 'proven' }
        }
        Assert-CollectorReportRejected $fixture ($mutation + ': candidate dispositions preserve scope and uncertainty')
    }
}
Invoke-CollectorCase 'report-requires-every-planned-request-and-consistent-counters' {
    foreach ($mutation in @('successful-empty', 'omitted-request', 'duplicate-request', 'extra-request', 'wrong-kind', 'attempt-counter', 'start-counter', 'closure-counter', 'closure-without-stop', 'resume-after-stop', 'not-run-started', 'successful-without-receipt', 'additional-request-field')) {
        $fixture = New-CollectorReportFixture
        switch ($mutation) {
            'successful-empty' { $fixture.report.requests = @(); $fixture.report.successful = $true; $fixture.report.status = 'recorded-awaiting-review'; $fixture.report.sourceSealsRechecked = $true; $fixture.report.errors = @() }
            'omitted-request' { $fixture.report.requests = @($fixture.report.requests | Select-Object -Skip 1) }
            'duplicate-request' { $fixture.report.requests += Copy-CollectorValue $fixture.report.requests[0] }
            'extra-request' {
                $extra = Copy-CollectorValue $fixture.report.requests[0]; $extra.requestId = New-CollectorHash 'unplanned-request'
                $fixture.report.requests += $extra
            }
            'wrong-kind' { $fixture.report.requests[0].kind = 'supplemental-extractor' }
            'attempt-counter' { $fixture.report.nativeInvocationsAttempted = 1 }
            'start-counter' { $fixture.report.confirmedProcessesStarted = 1 }
            'closure-counter' { $fixture.report.processBoundary.descendantClosureRequired = $true }
            'closure-without-stop' { $fixture.report.requests[0].descendantClosureRequired = $true; $fixture.report.requests[0].stopLaterCommands = $false }
            'resume-after-stop' { $fixture.report.requests[1].outcome = 'import-controls-recorded' }
            'not-run-started' { $fixture.report.requests[0].processStarted = $true; $fixture.report.confirmedProcessesStarted = 1 }
            'successful-without-receipt' {
                $fixture.report.requests[0].outcome = 'import-controls-recorded'; $fixture.report.requests[0].stopLaterCommands = $false
            }
            'additional-request-field' { $fixture.report.requests[0] | Add-Member -NotePropertyName descendantsClosed -NotePropertyValue $true }
        }
        Assert-CollectorReportRejected $fixture ($mutation + ': request semantics cannot be hidden by resealing metadata')
    }
}
Invoke-CollectorCase 'report-rejects-retained-profile-promotion-and-source-mismatch' {
    foreach ($mutation in @('synthetic-profile', 'frontend-version', 'source-mismatch', 'wrong-sdk', 'outward-tool', 'extra-profile-field')) {
        $fixture = New-CollectorReportFixture -MutateProfile {
            param($profile)
            switch ($mutation) {
                'synthetic-profile' { $profile.syntheticFixture = $true }
                'frontend-version' { $profile.observations.frontendVersionExecuted = $true }
                'source-mismatch' { $profile.sourceArtifacts.graphSetSha256 = New-CollectorHash 'wrong-graph-set' }
                'wrong-sdk' { $profile.sdkPath = '/SYNTHETIC-OTHER-SDK' }
                'outward-tool' { $profile.frontend.canonicalPath = '/outside/frontend' }
                'extra-profile-field' { $profile | Add-Member -NotePropertyName fallbackFrontend -NotePropertyValue '/other/frontend' }
            }
        }
        Assert-CollectorReportRejected $fixture ($mutation + ': retained profile is checked without opening its recorded SDK paths')
    }
}
Invoke-CollectorCase 'empty-selected-definition-remains-an-unqualified-report' {
    $fixture = New-CollectorReportFixture -EmptyNames
    $saved = Save-CollectorReportFixture $fixture
    $read = Read-SwiftUIOverlayProbeReport -Root $saved.root -ExpectedSha256 $saved.sha256
    Assert-CollectorTrue ($read.report.requests.Count -eq 0 -and -not $read.successful) 'selected empty occurrence has no native work or invented success'
    Assert-CollectorTrue ($read.report.selection.selectedPairIds.Count -eq 1 -and -not $read.qualification.overlayCompleteness) 'empty occurrence remains selected without completion claim'
}



function New-CollectorRecordedRequestFixture {
    param([AllowNull()][string]$Root, [AllowNull()]$Report, [AllowNull()]$Profile, [AllowNull()]$Request)
    if ([string]::IsNullOrEmpty($Root)) {
        $Root = New-CollectorCaseRoot 'synthetic-recorded-request'
        [void](Write-CollectorText (Join-Path $Root 'SYNTHETIC-FIXTURE.txt') 'SYNTHETIC SUCCESSFUL-SHAPED RECEIPTS. No native process, compiler or SDK access occurred.')
    }
    $nativeFixturePath = Join-Path $RepositoryRoot 'scripts/fixtures/swiftui-overlay-probes/native/synthetic-cases.json'
    $nativeFixture = (Read-SwiftUIStateObjectJson -Path $nativeFixturePath -MaxBytes 1MB).document
    if ($nativeFixture.evidenceKind -cne 'SYNTHETIC-TEST-FIXTURE-NOT-NATIVE-CAPTURE') { throw 'Native replay fixture must be explicitly synthetic.' }
    $plan = New-CollectorPlan
    $plan.pairs[0].overlayNameOccurrences = @(
        [pscustomobject]@{ index = 0; name = $nativeFixture.overlayModule },
        [pscustomobject]@{ index = 1; name = $nativeFixture.overlayModule }
    )
    if ($null -eq $Request) {
        $expected = @(New-SwiftUIOverlayProbeRequestSchedule $plan | ForEach-Object { $_ } |
            Where-Object { $_.control -ceq 'owner-bystander' -and $_.target -ceq 'arm64-apple-macosx26.5' })[0]
    } else { $expected = $Request }
    if ($null -eq $Profile) {
        $profileFixture = New-CollectorProfileFixture
        $recordedDeveloper = (Get-SwiftUIOverlayProbeNativePolicy).sdkPath.Split('/Platforms/')[0]
        $profileJson = (ConvertTo-Json -InputObject $profileFixture.profile -Depth 60 -Compress).Replace($script:CollectorFixtureLayout.developer, $recordedDeveloper)
        $Profile = ConvertFrom-Json -InputObject $profileJson -Depth 60
        $Profile.selectedRoots = @([pscustomobject]@{
            rootId = 'synthetic-recorded-sdk'; logicalPath = $Profile.sdkPath
            physicalPath = $Profile.sdkPath; state = 'readable-complete'
        })
    }
    if ($null -eq $Report) {
        $profileHash = Get-SwiftUIStateObjectBytesSHA256 ($script:CollectorUtf8.GetBytes((ConvertTo-Json -InputObject $Profile -Depth 60 -Compress)))
        $Report = [pscustomobject]@{
            batchId = Get-SwiftUIOverlayId @('overlay-probe-batch-v1', $plan.file.sha256, $profileHash)
            sourceArtifacts = New-CollectorSourceArtifacts
            plan = [pscustomobject]@{ sha256 = $plan.file.sha256 }
            nativeProfile = [pscustomobject]@{ sha256 = $profileHash }
            successful = $true
        }
    } else {
        $profileHash = $Report.nativeProfile.sha256
        $plan.file.sha256 = $Report.plan.sha256
    }
    $prefix = 'evidence/' + $expected.requestId + '/'
    $cell = New-SwiftUIOverlayProbeOwnedDirectory -Root $root -RelativePath $prefix.TrimEnd('/')
    [void](New-SwiftUIOverlayProbeOwnedDirectory -Root $cell -RelativePath 'modules')
    $recordedRoot = '/SYNTHETIC-COLLECTOR/' + [IO.Path]::GetFileName($root)
    $work = $recordedRoot + '/.work/requests/' + $expected.requestId
    $cache = $work + '/module-cache'; $temporary = $work + '/tmp'
    $sourcePath = $recordedRoot + '/' + $prefix + 'imports.swift'
    $tracePath = $work + '/loaded-module-trace.json'
    [void](Write-CollectorText (Join-Path $cell 'imports.swift') $expected.source.text)
    $receipt = [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'swiftui-overlay-native-launch-request-v1'
        batchId = $report.batchId; request = Copy-CollectorValue $expected
        profileSha256 = $profileHash; planSha256 = $plan.file.sha256; sourceArtifacts = Copy-CollectorValue $report.sourceArtifacts
        executable = $profile.frontend.path
        arguments = New-SwiftUIOverlayProbeCompilerArguments -SDKPath $profile.sdkPath -Target $expected.target -CxxMode $expected.cxxMode -CachePath $cache -ModuleName ('SWUIOverlayProbe_' + $expected.requestId) -TracePath $tracePath -SourcePath $sourcePath
        workingDirectory = $work
        childEnvironmentOverrides = [pscustomobject][ordered]@{
            DEVELOPER_DIR = $profile.developerDirectory; LANG = 'C'; LC_ALL = 'C'
            TMPDIR = $temporary; TEMP = $temporary; TMP = $temporary
        }
        remainingEnvironment = 'inherited; not a process sandbox'; sourcePath = $sourcePath
        tracePath = $tracePath; graphDirectory = $null; timeoutSeconds = 120; maximumCombinedOutputBytes = [long]8MB
        sourceProfile = (Get-SwiftUIOverlayProbeNativePolicy).profile
    }
    $combined = $expected.control -cin @('owner-bystander', 'bystander-owner')
    $remarks = if ($combined) { $nativeFixture.diagnostics.positive } else { '' }
    if ($expected.control -ceq 'bystander-owner') {
        $remarks = $remarks.Replace(('import ' + [char]96 + 'Beta' + [char]96), ('import ' + [char]96 + 'Alpha' + [char]96))
    }
    $diagnosticText = ($nativeFixture.searchPathDump + $remarks).
        Replace($nativeFixture.sourcePath, $sourcePath).
        Replace('/SYNTHETIC/sdk', $profile.sdkPath).
        Replace('/SYNTHETIC/cache', $cache)
    $stderr = Write-CollectorText (Join-Path $cell 'stderr.txt') $diagnosticText
    $stdout = Write-CollectorBytes (Join-Path $cell 'stdout.txt') ([byte[]]@())
    $traceDocument = Copy-CollectorValue $nativeFixture.trace
    $traceDocument.name = 'SWUIOverlayProbe_' + $expected.requestId
    $traceDocument.arch = if ($expected.target -ceq 'arm64-apple-macosx26.5') { 'arm64' } else { 'x86_64' }
    if (-not $combined) {
        $traceDocument.swiftmodulesDetailedInfo = @($traceDocument.swiftmodulesDetailedInfo | Where-Object { $_.name -cin $expected.source.imports })
        $traceDocument.swiftmodules = @($traceDocument.swiftmodulesDetailedInfo.path)
    }
    $traceText = (ConvertTo-Json -InputObject $traceDocument -Depth 60 -Compress).
        Replace('/SYNTHETIC/sdk', $profile.sdkPath).
        Replace('/SYNTHETIC/cache', $cache) + [char]10
    $retainedTrace = Write-CollectorText (Join-Path $cell 'trace.json') $traceText
    $paths = @(
        [pscustomobject]@{ path = $profile.sdkPath + '/_Alpha_Beta.swiftinterface'; bytes = $script:CollectorUtf8.GetBytes('// SYNTHETIC interface bytes, not SDK declarations.' + [char]10) },
        [pscustomobject]@{ path = $cache + '/_Alpha_Beta.swiftmodule'; bytes = [byte[]]@(0, 1, 2, 4, 8, 16, 32, 64, 128, 255) }
    )
    if (-not $combined) { $paths = @() }
    $pathObservations = @($paths | ForEach-Object {
        $relative = $prefix + 'modules/' + (Get-SwiftUIOverlayId @('loaded-path-v1', $_.path)) + '.bytes'
        [void](Write-CollectorBytes (Join-Path $root $relative) $_.bytes)
        [pscustomobject][ordered]@{
            path = $_.path; canonicalPath = $_.path; status = 'recorded'
            bytes = [long]$_.bytes.Length; sha256 = Get-SwiftUIStateObjectBytesSHA256 $_.bytes
            retainedFile = $relative; error = $null
        }
    })
    $process = [pscustomobject][ordered]@{
        evidenceKind = 'SYNTHETIC-RECORD-NOT-PROCESS-CAPTURE'
        processStarted = $true; exitCode = 0; timedOut = $false; outputLimitExceeded = $false
        terminationRequested = $false; terminationCompleted = $true; allRedirectedStreamsClosed = $true
        error = $null; cleanupErrors = @(); observedDiscardedBytes = [long]0
        stdoutBytes = [long]0; stderrBytes = [long]$script:CollectorUtf8.GetByteCount($diagnosticText)
        stdoutSha256 = Get-SwiftUIStateObjectBytesSHA256 ([byte[]]@())
        stderrSha256 = Get-SwiftUIStateObjectBytesSHA256 ($script:CollectorUtf8.GetBytes($diagnosticText))
        descendantsClosed = $null
    }
    $diagnostics = Read-SwiftUIOverlayProbeDiagnostics -StderrPath $stderr -ExpectedSourcePath $sourcePath -SourceRecord $expected.source
    $trace = Read-SwiftUIOverlayProbeTrace -Path $retainedTrace -ExpectedModuleName ('SWUIOverlayProbe_' + $expected.requestId) -Target $expected.target
    $assessmentArgs = @{
        RequestId = $expected.requestId; CompilerProfileSha256 = $profileHash
        DeclaringModule = $expected.declaringModule; BystandingModule = $expected.bystanderModule
        OverlayModule = $nativeFixture.overlayModule; Control = $expected.control
        Target = $expected.target; CxxMode = $expected.cxxMode; CandidateRecordIds = $expected.candidateRecordIds
        LaunchState = 'confirmed-started'; Process = $process; Diagnostics = $diagnostics
        Trace = $trace; PathObservations = $pathObservations
    }
    $assessment = Get-SwiftUIOverlayProbeAssessment @assessmentArgs
    if ($combined -and -not $assessment.overlayActivationObserved) {
        throw ('SYNTHETIC fixture did not produce its expected parser-only positive: ' + (ConvertTo-Json -InputObject $assessment -Depth 30 -Compress))
    }
    $positive = if ($combined) { [pscustomobject][ordered]@{
        observationId = Get-SwiftUIOverlayId @('frontend-overlay-observation-v1', $expected.requestId, $nativeFixture.overlayModule)
        requestId = $expected.requestId; profileSha256 = $profileHash; module = $nativeFixture.overlayModule
        target = $expected.target; cxxMode = $expected.cxxMode; control = $expected.control
        candidateRecordIds = Copy-CollectorValue $expected.candidateRecordIds
        sourcePath = $pathObservations[0].path; loadedPath = $pathObservations[1].path
        sourceSha256 = $pathObservations[0].sha256; loadedSha256 = $pathObservations[1].sha256
        activationTuple = [pscustomobject]@{ declaringModule = $expected.declaringModule; bystanderModules = @($expected.bystanderModule); overlayModule = $nativeFixture.overlayModule }
        traceSha256 = $trace.sha256; diagnosticsSha256 = $diagnostics.sha256; eligible = $true
    } } else { $null }
    $row = [pscustomobject][ordered]@{
        requestId = $expected.requestId; kind = $expected.kind; outcome = 'import-controls-recorded'
        nativeInvocationAttempted = $true; processStarted = $true
        stopLaterCommands = $false; descendantClosureRequired = $false; resultFile = $prefix + 'result.json'
    }
    $result = [pscustomobject][ordered]@{
        requestId = $expected.requestId; kind = $expected.kind; outcome = 'import-controls-recorded'
        nativeInvocationAttempted = $true; processStarted = $true
        stopLaterCommands = $false; descendantClosureRequired = $false
        descendantsClosed = $null; descendantClosureStatus = 'not-independently-observed'; error = $null
        process = $process; processOutcome = Get-SwiftUIOverlayProbeProcessOutcome -LaunchState 'confirmed-started' -Process $process
        pathObservations = $pathObservations; assessments = @($assessment); positiveFrontendObservations = @()
        requestFile = $prefix + 'request.json'; resultFile = $prefix + 'result.json'
        liveChecksBefore = Copy-CollectorValue (@($profile.anchors.file) + @($profile.frontend))
        liveChecksAfter = Copy-CollectorValue (@($profile.anchors.file) + @($profile.frontend))
    }
    if ($null -ne $positive) { $result.positiveFrontendObservations = @($positive) }
    return [pscustomobject]@{
        root = $root; cell = $cell; report = $report; row = $row; expected = $expected; profile = $profile
        receipt = $receipt; result = $result; process = Copy-CollectorValue $process; paths = $pathObservations
        nativeFixtureSha256 = (Get-SwiftUIStateObjectFileHash $nativeFixturePath -MaxBytes 1MB).sha256
    }
}
function Save-CollectorRecordedRequest {
    param($Fixture)
    [void](Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $Fixture.cell 'request.json') -Value $Fixture.receipt -MaximumBytes 1MB)
    [void](Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $Fixture.cell 'process.json') -Value $Fixture.process -MaximumBytes 1MB)
    [void](Write-SwiftUIOverlayProbeNewJson -Path (Join-Path $Fixture.cell 'result.json') -Value $Fixture.result -MaximumBytes 16MB)
}
function Read-CollectorRecordedRequest {
    param($Fixture)
    return Assert-SwiftUIOverlayProbeRecordedRequest -Root $Fixture.root -Report $Fixture.report -Row $Fixture.row -Expected $Fixture.expected -Profile $Fixture.profile
}

Invoke-CollectorCase 'synthetic-clone-preserves-empty-single-and-many-element-array-shapes' {
    foreach ($count in @(0, 1, 3)) {
        $original = @(for ($index = 0; $index -lt $count; $index++) { [pscustomobject]@{ index = $index } })
        $copy = Copy-CollectorValue $original
        Assert-CollectorTrue ($copy -is [array] -and $copy.Count -eq $count) 'fixture clone retains root array cardinality'
    }
}
Invoke-CollectorCase 'recorded-request-replays-fixed-argv-streams-and-canonical-positive' {
    $fixture = New-CollectorRecordedRequestFixture
    Save-CollectorRecordedRequest $fixture
    $read = Read-CollectorRecordedRequest $fixture
    Assert-CollectorTrue ($read.outcome -ceq 'import-controls-recorded' -and $read.assessments[0].overlayActivationObserved) 'real request reader replays actual synthetic diagnostic and trace bytes'
    Assert-CollectorTrue ($read.positiveFrontendObservations.Count -eq 1 -and $fixture.expected.overlayNameOccurrences.Count -eq 2) 'positive assessment deduplicates module names while request preserves duplicate definition names'
    Assert-CollectorTrue ($null -eq $read.descendantsClosed -and -not $read.descendantClosureRequired) 'normal synthetic closure does not become a descendant observation'
    Assert-CollectorTrue ($read.liveChecksBefore.Count -eq 3 -and $read.liveChecksAfter.Count -eq 3) 'exact recorded anchor and frontend arrays bind both sides of request'
}
Invoke-CollectorCase 'recorded-request-rejects-relabeling-argv-context-tools-and-paths' {
    foreach ($mutation in @('extra-argv', 'cxx-argv', 'executable', 'source-path', 'request-cxx', 'live-before', 'live-after', 'environment', 'outer-start', 'frontend-labelled-extractor-success', 'positive-module', 'positive-duplicate-id', 'positive-source-hash', 'positive-candidate', 'positive-tuple', 'module-copy-name', 'module-outside-root')) {
        $fixture = New-CollectorRecordedRequestFixture
        switch ($mutation) {
            'extra-argv' { $fixture.receipt.arguments += '-I/SYNTHETIC-OTHER' }
            'cxx-argv' { $index = [Array]::IndexOf($fixture.receipt.arguments, '-cxx-interoperability-mode=off'); $fixture.receipt.arguments[$index] = '-cxx-interoperability-mode=default' }
            'executable' { $fixture.receipt.executable += '-other' }
            'source-path' { $fixture.receipt.sourcePath += '.other' }
            'request-cxx' { $fixture.receipt.request.cxxMode = 'default' }
            'live-before' { $fixture.result.liveChecksBefore[0].sha256 = New-CollectorHash 'wrong-before' }
            'live-after' { $fixture.result.liveChecksAfter[0].sha256 = New-CollectorHash 'wrong-after' }
            'environment' { $fixture.receipt.childEnvironmentOverrides.LC_ALL = 'different' }
            'outer-start' { $fixture.row.processStarted = $false; $fixture.result.processStarted = $false }
            'frontend-labelled-extractor-success' { $fixture.row.outcome = 'extractor-completed'; $fixture.result.outcome = 'extractor-completed' }
            'positive-module' { $fixture.result.positiveFrontendObservations[0].module = 'DifferentModule' }
            'positive-duplicate-id' { $fixture.result.positiveFrontendObservations += Copy-CollectorValue $fixture.result.positiveFrontendObservations[0] }
            'positive-source-hash' { $fixture.result.positiveFrontendObservations[0].sourceSha256 = New-CollectorHash 'wrong-source-file' }
            'positive-candidate' { $fixture.result.positiveFrontendObservations[0].candidateRecordIds[0] = New-CollectorHash 'wrong-candidate' }
            'positive-tuple' { $fixture.result.positiveFrontendObservations[0].activationTuple.bystanderModules = @('OtherBystander') }
            'module-copy-name' { $fixture.result.pathObservations[0].retainedFile += '.other' }
            'module-outside-root' { $fixture.result.pathObservations[0].canonicalPath = '/OUTSIDE-SELECTED-ROOT/module.swiftinterface' }
        }
        Save-CollectorRecordedRequest $fixture
        Assert-CollectorThrows { Read-CollectorRecordedRequest $fixture } ($mutation + ': successful-looking receipts still require exact raw request bindings')
    }
}
Invoke-CollectorCase 'recorded-request-rejects-source-stream-module-and-trace-byte-drift' {
    foreach ($mutation in @('source-bytes', 'stderr-bytes', 'stdout-bytes', 'module-bytes', 'trace-bytes', 'process-stream-hash')) {
        $fixture = New-CollectorRecordedRequestFixture
        if ($mutation -ceq 'process-stream-hash') {
            $fixture.result.process.stderrSha256 = New-CollectorHash 'wrong-stderr'
            $fixture.process.stderrSha256 = $fixture.result.process.stderrSha256
        }
        Save-CollectorRecordedRequest $fixture
        switch ($mutation) {
            'source-bytes' { [IO.File]::AppendAllText((Join-Path $fixture.cell 'imports.swift'), '// drift', $script:CollectorUtf8) }
            'stderr-bytes' { [IO.File]::AppendAllText((Join-Path $fixture.cell 'stderr.txt'), 'drift', $script:CollectorUtf8) }
            'stdout-bytes' { [IO.File]::AppendAllText((Join-Path $fixture.cell 'stdout.txt'), 'drift', $script:CollectorUtf8) }
            'module-bytes' { [IO.File]::AppendAllText((Join-Path $fixture.root $fixture.paths[0].retainedFile), 'drift', $script:CollectorUtf8) }
            'trace-bytes' { [IO.File]::WriteAllText((Join-Path $fixture.cell 'trace.json'), '{"version":999}', $script:CollectorUtf8) }
        }
        Assert-CollectorThrows { Read-CollectorRecordedRequest $fixture } ($mutation + ': retained bytes are verified again during successful-request replay')
    }
}


. (Join-Path $RepositoryRoot 'scripts/fixtures/swiftui-overlay-probes/collector/synthetic-full-report.ps1')
Invoke-CollectorFullReportTests

Invoke-CollectorCase 'native-dispatch-guards-remained-unused' {
    Assert-CollectorTrue ($script:CollectorNativeAdapterCalls -eq 0) 'no synthetic case entered the real native adapter'
    Assert-CollectorTrue ($script:CollectorProcessHelperCalls -eq 0) 'no synthetic case entered the process helper'
}
$script:CollectorSourceHashesAfter = Get-CollectorSourceSnapshot
$sourceStable = (ConvertTo-Json -InputObject $script:CollectorSourceHashesBefore -Compress) -ceq
    (ConvertTo-Json -InputObject $script:CollectorSourceHashesAfter -Compress)
Invoke-CollectorCase 'loaded-source-hashes-remained-stable-during-tests' {
    Assert-CollectorTrue $sourceStable 'source changes during the suite require a new complete run'
}
Invoke-CollectorCase 'requested-case-filter-resolves-exactly' {
    foreach ($name in $CaseFilter) {
        Assert-CollectorTrue ($script:CollectorCaseNames.Contains($name)) 'a requested case filter cannot silently select no test'
    }
    if ($CaseFilter.Count -eq 0) { Assert-CollectorTrue ($script:CollectorSkippedCases.Count -eq 0) 'an unfiltered run executes every registered case' }
}
$failed = @($script:CollectorCases | Where-Object { $_.outcome -ceq 'failed' })
$summary = [pscustomobject][ordered]@{
    schemaVersion = 1; evidenceKind = 'SYNTHETIC-COLLECTOR-TEST-REPORT-NOT-NATIVE-CAPTURE'
    startedAtUtc = $script:CollectorStartedAtUtc; finishedAtUtc = [DateTime]::UtcNow.ToString('o')
    durationSeconds = $script:CollectorElapsed.Elapsed.TotalSeconds
    shell = [pscustomobject]@{
        edition = $PSVersionTable.PSEdition; version = $PSVersionTable.PSVersion.ToString()
        executable = [Environment]::ProcessPath
        windowsPublicCLIRefusalExercised = -not $IsMacOS
        macOSSyntheticSpecificRefusalExercised = [bool]$IsMacOS
    }
    helperInitialization = [pscustomobject]@{
        profile = 'PowerShell-7-existing-managed-helpers-in-process-Add-Type-only'
        streamingTypePresentBeforeFixtureRead = $script:CollectorManagedHelperPresentBefore
        streamingTypePresentAfterTests = $null -ne ('SwiftUIBaseline.Streaming.InventoryWriter' -as [type])
        externalCompilerExecuted = $false
    }
    testSeams = @(
        'schedule callback receives synthetic closure receipts without launching native adapter'
        'native-profile metadata uses synthetic Get-SwiftUIOverlayExpectedLayout only; JSON/hash/path validation stays real'
        'native-shaped report/profile fixtures test parser shape only and never attest execution or SDK identity'
        'full report joins use a preserved actual local synthetic graph writer output plus an independent POSIX-shaped reader fixture regenerated by the unchanged streaming writer; no production readers or path checks are replaced'
    )
    relocatedFixtureEvidence = $script:CollectorRelocatedFixtureEvidence.ToArray()
    nativeCommandsExecuted = $false; swiftPMExecuted = $false; sdkPathsOpened = $false
    nativeAdapterCalls = $script:CollectorNativeAdapterCalls; processHelperCalls = $script:CollectorProcessHelperCalls
    qualification = Copy-CollectorValue $script:CollectorFixture.qualification
    fixtureSha256 = $fixtureRead.sha256
    reusedNativeFixtureSha256 = @($script:CollectorSourceHashesBefore | Where-Object { $_.path -ceq 'scripts/fixtures/swiftui-overlay-probes/native/synthetic-cases.json' })[0].sha256
    testScriptSha256 = (Get-SwiftUIStateObjectFileHash $PSCommandPath -MaxBytes 2MB).sha256
    loadedSourcesStableDuringTests = $sourceStable
    sourceHashesBefore = $script:CollectorSourceHashesBefore; sourceHashesAfter = $script:CollectorSourceHashesAfter
    cases = $script:CollectorCases.Count; assertions = $script:CollectorAssertions; failedCases = $failed.Count
    fullSuite = $CaseFilter.Count -eq 0; requestedCaseFilter = @($CaseFilter); skippedCaseNames = $script:CollectorSkippedCases.ToArray()
    caseResults = $script:CollectorCases.ToArray()
}
$reportPath = Write-CollectorText (Join-Path $OutputRoot 'collector-test-report.json') ((ConvertTo-Json -InputObject $summary -Depth 80) + [char]10)
$lines = @(
    'SYNTHETIC COLLECTOR TESTS ONLY: no Swift/compiler/native workload, SDK opening or workflow dispatch.'
    ('PowerShell ' + $summary.shell.version + '; managed helper initialization in-process only.')
    ('Cases: ' + $summary.cases + '; assertions: ' + $summary.assertions + '; failed cases: ' + $summary.failedCases)
    ('Loaded source hashes stable during tests: ' + $sourceStable)
)
foreach ($case in $script:CollectorCases) {
    $lines += $case.outcome + ': ' + $case.name + ' (' + $case.assertions + ' assertions)'
    if ($case.error) { $lines += $case.error; $lines += $case.errorLocation }
}
$logPath = Write-CollectorText (Join-Path $OutputRoot 'collector-test-log.txt') (($lines -join [char]10) + [char]10)
Write-Output "Synthetic collector cases=$($summary.cases) assertions=$($summary.assertions) failed=$($summary.failedCases)"
Write-Output "Full suite: $($summary.fullSuite); skipped cases: $($summary.skippedCaseNames.Count)"
Write-Output "Report: $reportPath"
Write-Output "Report SHA256: $((Get-SwiftUIStateObjectFileHash $reportPath -MaxBytes 2MB).sha256)"
Write-Output "Log: $logPath"
Write-Output "Log SHA256: $((Get-SwiftUIStateObjectFileHash $logPath -MaxBytes 2MB).sha256)"
if ($failed.Count -gt 0) { throw "Synthetic collector tests failed: $($failed.name -join ', ')" }
