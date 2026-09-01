<#
.SYNOPSIS
Tests Stage B graph retention with bounded synthetic files and the actual reader.
.DESCRIPTION
No native executable, SwiftPM, SDK extraction or external compiler runs. The
unchanged managed streaming helper may compile in this PowerShell process.
#>
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot), [string]$OutputRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $RepositoryRoot 'scripts/swiftui-overlay-probe-graphs.ps1')
if ([string]::IsNullOrEmpty($OutputRoot)) {
    $OutputRoot = Join-Path $RepositoryRoot ('artifacts/swiftui-overlay-probe-graph-tests/' + [Guid]::NewGuid().ToString('N'))
}
$OutputRoot = Assert-SwiftUIOverlayGraphPath ([IO.Path]::GetFullPath($OutputRoot)) Absent
[void][IO.Directory]::CreateDirectory($OutputRoot)
$fixtureRoot = Join-Path $RepositoryRoot 'scripts/fixtures/swiftui-overlay-probes/graphs'
$encoding = [Text.UTF8Encoding]::new($false, $true)
$script:GraphProbeAssertions = 0
$script:GraphProbeCases = [Collections.Generic.List[object]]::new()
$preservedPaths = @(
    'scripts/swiftui-baseline-common.ps1', 'scripts/swiftui-baseline-streaming.ps1',
    'scripts/swiftui-api-audit-common.ps1', 'scripts/swiftui-overlay-discovery-common.ps1',
    'docs/swiftui-baseline.json'
)
$preserved = @{}
foreach ($relative in $preservedPaths) { $preserved[$relative] = (Get-FileHash -LiteralPath (Join-Path $RepositoryRoot $relative)).Hash }

function Assert-GraphProbe {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw "Supplemental graph assertion failed: $Message" }
    $script:GraphProbeAssertions++
}
function Get-GraphProbeHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Write-GraphProbeJson {
    param([string]$Path, $Value)
    [IO.File]::WriteAllText($Path, ((ConvertTo-Json -InputObject $Value -Depth 50) + [char]10), $encoding)
}
function Read-GraphProbeJson {
    param([string]$Path)
    if ((Get-Item -LiteralPath $Path).Length -gt 2MB) { throw 'Synthetic graph JSON fixture unexpectedly exceeds 2 MiB.' }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function New-GraphProbeCase {
    param([string]$Name, [string[]]$FixtureNames = @('owner-named'), [string]$RequestedModule = '_GraphOverlay')
    $directory = Join-Path $OutputRoot $Name
    [void](Assert-SwiftUIOverlayGraphPath $directory Absent)
    $producer = Join-Path $directory 'producer'
    $emission = Join-Path $producer 'emit-1'
    [void][IO.Directory]::CreateDirectory($emission)
    $id = Get-SwiftUIBaselineTextHash -Text ('request:' + $Name)
    $invocationId = Get-SwiftUIBaselineTextHash -Text ('extractor:' + $Name)
    $observationId = Get-SwiftUIBaselineTextHash -Text ('positive:' + $Name)
    $candidateId = Get-SwiftUIBaselineTextHash -Text ('candidate:' + $Name)
    $profileHash = Get-SwiftUIBaselineTextHash -Text 'synthetic-explicit-native-profile'
    $inputs = [Collections.Generic.List[object]]::new()
    $fileIndex = 0
    foreach ($fixture in $FixtureNames) {
        $leaf = switch ($fixture) {
            'owner-named' { '_GraphOverlay@ForeignOwner.symbols.json' }
            'other-partition' { '_AnotherOverlay@DifferentOwner.symbols.json' }
            'nonunderscore' { 'VisibleOverlay.symbols.json' }
            'empty' { '_GraphOverlay@DeclaringA.symbols.json' }
        }
        if ($fileIndex -gt 0 -and (Test-Path -LiteralPath (Join-Path $emission $leaf))) { $leaf = [string]$fileIndex + '-' + $leaf }
        $source = Join-Path $fixtureRoot ($fixture + '.symbols.json')
        $destination = Join-Path $emission $leaf
        [IO.File]::Copy($source, $destination, $false)
        [void]$inputs.Add([pscustomobject]@{
            relativePath = 'emit-1/' + $leaf; bytes = (Get-Item -LiteralPath $destination).Length
            sha256 = Get-GraphProbeHash $destination; invocationId = $invocationId
            role = 'unattributed-emission'; emittingModule = $null; declaringModule = $null
            bystanders = $null; positiveFrontendObservationIds = @()
        })
        $fileIndex++
    }
    $observation = [pscustomobject]@{
        observationId = $observationId; requestId = $id; profileSha256 = $profileHash; module = $RequestedModule
        target = 'arm64-apple-macosx26.5'; cxxMode = 'default'; control = 'owner-bystander'
        candidateRecordIds = @($candidateId); sourcePath = '/synthetic/sdk/Overlay.swiftmodule'
        loadedPath = '/synthetic/sdk/Overlay.swiftmodule'; sourceSha256 = ('1' * 64); loadedSha256 = ('1' * 64)
        activationTuple = [pscustomobject]@{ declaringModule = 'DeclaringA'; bystanderModules = @('BystanderB'); overlayModule = $RequestedModule }
        traceSha256 = ('2' * 64); diagnosticsSha256 = ('3' * 64); eligible = $true
    }
    $invocation = [pscustomobject]@{
        invocationId = $invocationId; requestId = $id; requestedModule = $RequestedModule
        target = 'arm64-apple-macosx26.5'; cxxMode = 'default'; control = 'supplemental-direct-module'
        graphDirectory = 'emit-1'; arguments = @('-module-name', $RequestedModule, '-target', 'arm64-apple-macosx26.5', '-cxx-interoperability-mode=default', '-output-dir', [IO.Path]::GetFullPath($emission))
        exitCode = 0; termination = 'natural'; outputComplete = $true
        candidateRecordIds = @($candidateId); positiveFrontendObservationIds = @($observationId)
    }
    return [pscustomobject]@{
        name = $Name; directory = $directory; producer = $producer; output = (Join-Path $directory 'retained')
        frozenPath = (Join-Path $directory 'frozen.json'); nativePath = (Join-Path $directory 'native.json')
        frozen = [pscustomobject]@{
            schemaVersion = 1; evidenceKind = 'swiftui-overlay-supplemental-graph-inputs-v1'; batchId = $Name
            graphRoot = [IO.Path]::GetFullPath($producer); supplementalGraphInputs = $inputs.ToArray()
        }
        native = [pscustomobject]@{
            schemaVersion = 1; evidenceKind = 'swiftui-overlay-graph-native-invocations-v1'; batchId = $Name
            profileSha256 = $profileHash; executionKind = 'synthetic-test'; invocations = @($invocation)
            positiveFrontendObservations = @($observation)
        }
        result = $null
    }
}
function Save-GraphProbeCase {
    param($Case)
    Write-GraphProbeJson $Case.frozenPath $Case.frozen
    Write-GraphProbeJson $Case.nativePath $Case.native
}
function Invoke-GraphProbeCase {
    param($Case, [AllowNull()]$Limits, [string]$ErrorPattern, [scriptblock]$AfterSealing = {})
    Save-GraphProbeCase $Case
    $frozenHash = Get-GraphProbeHash $Case.frozenPath
    $nativeHash = Get-GraphProbeHash $Case.nativePath
    & $AfterSealing $Case
    $caught = $null
    try {
        $Case.result = Write-SwiftUIOverlaySupplementalInventory -FrozenGraphInventoryPath $Case.frozenPath -FrozenGraphInventorySha256 $frozenHash `
            -NativeInvocationMetadataPath $Case.nativePath -NativeInvocationMetadataSha256 $nativeHash -OutputDirectory $Case.output `
            -Limits $Limits -AllowSyntheticForTests
    } catch { $caught = $_ }
    if ($ErrorPattern) {
        Assert-GraphProbe ($null -ne $caught) ($Case.name + ' is refused')
        Assert-GraphProbe ($caught.Exception.ToString() -match $ErrorPattern) ($Case.name + ' fails at intended guard: ' + $caught.Exception.ToString())
        Assert-GraphProbe (-not (Test-Path -LiteralPath (Join-Path $Case.output 'supplemental-report.sha256'))) ($Case.name + ' publishes no success seal')
    } else {
        if ($null -ne $caught) { throw $caught }
        Assert-GraphProbe ($null -ne $Case.result) ($Case.name + ' returns a retained descriptor')
        Assert-GraphProbe ($Case.result.executionKind -ceq 'synthetic-test') ($Case.name + ' keeps synthetic provenance')
        Assert-GraphProbe ($Case.result.attributionCompleteness -ceq 'not-established') ($Case.name + ' makes no completeness claim')
        Assert-GraphProbe ((Get-GraphProbeHash $Case.frozenPath) -ceq $frozenHash -and (Get-GraphProbeHash $Case.nativePath) -ceq $nativeHash) ($Case.name + ' leaves source metadata unchanged')
        foreach ($entry in $Case.frozen.supplementalGraphInputs) {
            Assert-GraphProbe ((Get-GraphProbeHash (Join-Path $Case.producer $entry.relativePath)) -ceq $entry.sha256) ($Case.name + ' preserves raw producer graph')
            Assert-GraphProbe ((Get-GraphProbeHash (Join-Path $Case.output ('graphs/' + $entry.relativePath))) -ceq $entry.sha256) ($Case.name + ' retains exact raw graph bytes')
        }
    }
    [void]$script:GraphProbeCases.Add([pscustomobject]@{ name = $Case.name; outcome = $(if ($ErrorPattern) { 'expected-refusal' } else { 'retained-synthetic-evidence' }) })
    return $Case
}
function Set-GraphProbeRawText {
    param($Case, [string]$Text)
    $entry = $Case.frozen.supplementalGraphInputs[0]
    $path = Join-Path $Case.producer $entry.relativePath
    [IO.File]::WriteAllText($path, $Text, $encoding)
    $entry.bytes = (Get-Item -LiteralPath $path).Length
    $entry.sha256 = Get-GraphProbeHash $path
}
function Set-GraphProbeRequestedRole {
    param($Case)
    $entry = $Case.frozen.supplementalGraphInputs[0]
    $entry.role = 'requested-overlay-context'; $entry.emittingModule = $Case.native.invocations[0].requestedModule
    $entry.declaringModule = 'DeclaringA'; $entry.bystanders = @('BystanderB')
    $entry.positiveFrontendObservationIds = @($Case.native.positiveFrontendObservations[0].observationId)
}
function Add-GraphProbeSecondInvocation {
    param($Case)
    $original = $Case.frozen.supplementalGraphInputs[0]
    $secondDirectory = Join-Path $Case.producer 'emit-2'
    [void][IO.Directory]::CreateDirectory($secondDirectory)
    $leaf = [IO.Path]::GetFileName($original.relativePath)
    $destination = Join-Path $secondDirectory $leaf
    $raw = [IO.File]::ReadAllText((Join-Path $Case.producer $original.relativePath)).Replace('aarch64', 'x86_64')
    [IO.File]::WriteAllText($destination, $raw, $encoding)
    $second = $original | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $second.relativePath = 'emit-2/' + $leaf; $second.bytes = (Get-Item -LiteralPath $destination).Length
    $second.sha256 = Get-GraphProbeHash $destination
    $second.invocationId = Get-SwiftUIBaselineTextHash -Text ('second-extractor:' + $Case.name)
    $invocation = $Case.native.invocations[0] | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $invocation.invocationId = $second.invocationId; $invocation.requestId = Get-SwiftUIBaselineTextHash -Text ('second-frontend:' + $Case.name)
    $invocation.target = 'x86_64-apple-macosx26.5'; $invocation.cxxMode = 'off'; $invocation.graphDirectory = 'emit-2'
    $invocation.arguments = @('-module-name', $invocation.requestedModule, '-target', $invocation.target,
        '-cxx-interoperability-mode=off', '-output-dir', [IO.Path]::GetFullPath($secondDirectory))
    $observation = $Case.native.positiveFrontendObservations[0] | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $observation.observationId = Get-SwiftUIBaselineTextHash -Text ('second-positive:' + $Case.name)
    $observation.requestId = $invocation.requestId; $observation.target = $invocation.target; $observation.cxxMode = $invocation.cxxMode
    $observation.control = 'bystander-owner'
    $invocation.positiveFrontendObservationIds = @($observation.observationId)
    $Case.frozen.supplementalGraphInputs += $second
    $Case.native.invocations += $invocation
    $Case.native.positiveFrontendObservations += $observation
}
function Assert-GraphProbeReadRefusal {
    param($Case, [scriptblock]$Mutation, [string]$Pattern)
    & $Mutation $Case
    $caught = $null
    try { [void](Read-SwiftUIOverlaySupplementalInventory -OutputDirectory $Case.output -ExpectedReportSha256 $Case.result.report.sha256) }
    catch { $caught = $_ }
    Assert-GraphProbe ($null -ne $caught -and $caught.Exception.ToString() -match $Pattern) ($Case.name + ' reader detects tampering: ' + $caught)
}

$all = New-GraphProbeCase 'all-emitted-occurrences' @('owner-named', 'other-partition', 'nonunderscore')
Set-GraphProbeRequestedRole $all
$all = Invoke-GraphProbeCase $all
$inventory = Read-GraphProbeJson (Join-Path $all.output 'supplemental-inventory.json')
$report = Read-GraphProbeJson $all.result.report.path
Assert-GraphProbe ($inventory.counts.graphs -eq 3 -and $inventory.counts.preciseSymbols -eq 1 -and
    $inventory.counts.declarationOccurrences -eq 4 -and $inventory.counts.relationshipOccurrences -eq 3) 'all identifiers, duplicate constraints, aliases and relationships remain'
Assert-GraphProbe ($inventory.symbols[0].occurrences.Count -eq 4) 'existing precise identifier receives every occurrence'
Assert-GraphProbe ($inventory.symbols[0].occurrences.swiftGenerics.constraints.rhs -contains 'FirstProtocol' -and
    $inventory.symbols[0].occurrences.swiftGenerics.constraints.rhs -contains 'SecondProtocol' -and
    $inventory.symbols[0].occurrences.swiftGenerics.constraints.rhs -contains 'ThirdType') 'different constraints survive the shared precise identifier'
Assert-GraphProbe ($inventory.relationships.relationship.unknownRelationshipField -contains 0) 'unknown relationship field remains in the projection'
Assert-GraphProbe ($report.graphs[0].role -ceq 'unattributed-emission' -or $report.graphs[1].role -ceq 'unattributed-emission') 'unobserved automatic partitions remain unreviewed'
$ownerReport = @($report.graphs | Where-Object { $_.role -ceq 'requested-overlay-context' })[0]
Assert-GraphProbe ($ownerReport.observedModule -ceq 'DeclaringA' -and $ownerReport.partitionOwner -ceq 'not-inferred') 'foreign filename suffix does not become the module header or owner authority'
Assert-GraphProbe ($ownerReport.candidateEmittingModule -ceq '_GraphOverlay' -and
    $ownerReport.physicalEmitterIdentity -ceq 'not-established') 'matching activation context does not claim a unique physical emitter'
Assert-GraphProbe ($report.graphs.observedModule -ccontains 'VisibleOverlay') 'non-underscored emitted modules remain'
$repeatedBystanders = @($report.graphs | Where-Object { $_.observedModule -ceq 'OtherDeclaringModule' })[0].observedBystanders
Assert-GraphProbe ((Test-SwiftUIOverlayGraphSameStrings $repeatedBystanders @('ExtraBystander', 'ExtraBystander'))) 'bystander repetitions are preserved without normalization'
Assert-GraphProbe ($inventory.baselineId -ceq $all.result.supplementalInventoryId -and
    $report.evidenceKind -cne $inventory.evidenceKind) 'supplemental inventory identity is separate from its report and original baseline'

$plain = New-GraphProbeCase 'requested-nonunderscore' @('nonunderscore') 'VisibleOverlay'
$plain.frozen.supplementalGraphInputs[0].role = 'requested-module'
$plain.frozen.supplementalGraphInputs[0].emittingModule = 'VisibleOverlay'
$plain.frozen.supplementalGraphInputs[0].declaringModule = 'VisibleOverlay'
$plain.frozen.supplementalGraphInputs[0].positiveFrontendObservationIds = @($plain.native.positiveFrontendObservations[0].observationId)
[void](Invoke-GraphProbeCase $plain)

$automatic = New-GraphProbeCase 'independently-observed-automatic' @('nonunderscore')
$extra = $automatic.native.positiveFrontendObservations[0] | ConvertTo-Json -Depth 30 | ConvertFrom-Json
$extra.observationId = Get-SwiftUIBaselineTextHash -Text 'independent-automatic-proof'
$extra.module = 'VisibleOverlay'; $extra.activationTuple.overlayModule = 'VisibleOverlay'
$automatic.native.positiveFrontendObservations += $extra
$automatic.native.invocations[0].positiveFrontendObservationIds += $extra.observationId
$automatic.frozen.supplementalGraphInputs[0].role = 'automatic-module'
$automatic.frozen.supplementalGraphInputs[0].emittingModule = 'VisibleOverlay'
$automatic.frozen.supplementalGraphInputs[0].declaringModule = 'VisibleOverlay'
$automatic.frozen.supplementalGraphInputs[0].positiveFrontendObservationIds = @($extra.observationId)
[void](Invoke-GraphProbeCase $automatic)

$minimumLayout = Invoke-GraphProbeCase (New-GraphProbeCase 'producer-minimum-directory-depth') -Limits @{ directories = 2; depth = 1 }
Assert-GraphProbe ($minimumLayout.result.counts.graphs -eq 1) 'fixed retention wrapper overhead does not reduce the producer directory/depth budget'
$emptyBystanders = New-GraphProbeCase 'recognized-empty-bystanders'
Set-GraphProbeRequestedRole $emptyBystanders
$raw = Get-Content -LiteralPath (Join-Path $emptyBystanders.producer $emptyBystanders.frozen.supplementalGraphInputs[0].relativePath) -Raw
Set-GraphProbeRawText $emptyBystanders ($raw.Replace('["BystanderB"]', '[]'))
$emptyBystanders.frozen.supplementalGraphInputs[0].bystanders = @()
$emptyBystanders.native.positiveFrontendObservations[0].activationTuple.bystanderModules = @()
$emptyBystanders = Invoke-GraphProbeCase $emptyBystanders
$emptyBystandersReport = Read-GraphProbeJson $emptyBystanders.result.report.path
Assert-GraphProbe ($emptyBystandersReport.graphs[0].observedBystanders -is [Array] -and
    $emptyBystandersReport.graphs[0].observedBystanders.Count -eq 0) 'explicit empty bystanders does not become an absent/null field'
$wrongCaseBystanders = New-GraphProbeCase 'wrong-case-bystanders-role'
Set-GraphProbeRequestedRole $wrongCaseBystanders
$raw = Get-Content -LiteralPath (Join-Path $wrongCaseBystanders.producer $wrongCaseBystanders.frozen.supplementalGraphInputs[0].relativePath) -Raw
Set-GraphProbeRawText $wrongCaseBystanders ($raw.Replace('"bystanders"', '"Bystanders"'))
[void](Invoke-GraphProbeCase $wrongCaseBystanders -ErrorPattern 'raw module header')

$empty = Invoke-GraphProbeCase (New-GraphProbeCase 'empty-graph' @('empty'))
Assert-GraphProbe ($empty.result.counts.graphs -eq 1 -and $empty.result.counts.declarationOccurrences -eq 0) 'valid empty supplemental graph retained'
$noFiles = Invoke-GraphProbeCase (New-GraphProbeCase 'no-emitted-files' @())
$noFilesReport = Read-GraphProbeJson $noFiles.result.report.path
Assert-GraphProbe ($noFiles.result.counts.graphs -eq 0 -and $noFilesReport.emptyObservations.Count -eq 1 -and
    $noFilesReport.emptyObservations[0].kind -ceq 'no-public-graphs-emitted' -and
    $noFilesReport.emptyObservations[0].reviewStatus -ceq 'unreviewed') 'zero files remains an explicit unreviewed observation'

foreach ($caseName in @('wrong-architecture', 'wrong-os', 'malformed-json', 'duplicate-module-field', 'missing-symbol-identity')) {
    $case = New-GraphProbeCase $caseName
    $raw = Get-Content -LiteralPath (Join-Path $case.producer $case.frozen.supplementalGraphInputs[0].relativePath) -Raw
    $pattern = ''
    switch ($caseName) {
        'wrong-architecture' { $raw = $raw.Replace('aarch64', 'x86_64'); $pattern = 'wrong architecture' }
        'wrong-os' { $raw = $raw.Replace('macosx', 'ios'); $pattern = 'not a macOS' }
        'malformed-json' { $raw += 'trailing'; $pattern = 'Trailing|JSON|trailing' }
        'duplicate-module-field' { $raw = $raw.Replace('"name": "DeclaringA"', '"name": "DeclaringA", "name": "Other"'); $pattern = 'Duplicate' }
        'missing-symbol-identity' { $raw = $raw.Replace('"precise": "s:existing.shared"', '"precise": null'); $pattern = 'precise identifier' }
    }
    Set-GraphProbeRawText $case $raw
    [void](Invoke-GraphProbeCase $case -ErrorPattern $pattern)
}

foreach ($caseName in @('wrong-role-module', 'wrong-role-bystanders', 'no-independent-role-proof', 'unknown-role', 'unattributed-cannot-promote')) {
    $case = New-GraphProbeCase $caseName
    Set-GraphProbeRequestedRole $case
    $entry = $case.frozen.supplementalGraphInputs[0]
    switch ($caseName) {
        'wrong-role-module' { $entry.declaringModule = 'ForeignOwner'; $pattern = 'raw module header' }
        'wrong-role-bystanders' { $entry.bystanders = @('OtherBystander'); $pattern = 'raw module header' }
        'no-independent-role-proof' { $entry.positiveFrontendObservationIds = @(('4' * 64)); $pattern = 'independent positive evidence' }
        'unknown-role' { $entry.role = 'filename-guessed-owner'; $pattern = 'Unknown supplemental graph role' }
        'unattributed-cannot-promote' { $entry.role = 'unattributed-emission'; $pattern = 'defer module attribution' }
    }
    [void](Invoke-GraphProbeCase $case -ErrorPattern $pattern)
}

foreach ($caseName in @('missing-positive', 'wrong-positive-request', 'wrong-positive-target', 'wrong-positive-cxx', 'wrong-positive-profile', 'wrong-positive-control', 'wrong-candidate-occurrence', 'ineligible-positive', 'uncertain-native-exit', 'wrong-native-arguments')) {
    $case = New-GraphProbeCase $caseName
    $observation = $case.native.positiveFrontendObservations[0]
    switch ($caseName) {
        'missing-positive' { $case.native.positiveFrontendObservations = @(); $pattern = 'Missing expected positive' }
        'wrong-positive-request' { $observation.requestId = '4' * 64; $pattern = 'another invocation context' }
        'wrong-positive-target' { $observation.target = 'x86_64-apple-macosx26.5'; $pattern = 'another invocation context' }
        'wrong-positive-cxx' { $observation.cxxMode = 'off'; $pattern = 'another invocation context' }
        'wrong-positive-profile' { $observation.profileSha256 = '4' * 64; $pattern = 'mismatched positive' }
        'wrong-positive-control' { $observation.control = 'owner-only'; $pattern = 'mismatched positive' }
        'wrong-candidate-occurrence' { $observation.candidateRecordIds = @(('4' * 64)); $pattern = 'omits a candidate occurrence' }
        'ineligible-positive' { $observation.eligible = $false; $pattern = 'ineligible' }
        'uncertain-native-exit' { $case.native.invocations[0].termination = 'timeout'; $pattern = 'Uncertain' }
        'wrong-native-arguments' { $case.native.invocations[0].arguments[1] = 'WrongRequestedModule'; $pattern = 'arguments contradict' }
    }
    [void](Invoke-GraphProbeCase $case -ErrorPattern $pattern)
}

foreach ($caseName in @('wrong-activation-owner', 'wrong-activation-bystanders')) {
    $case = New-GraphProbeCase $caseName
    Set-GraphProbeRequestedRole $case
    if ($caseName -ceq 'wrong-activation-owner') { $case.native.positiveFrontendObservations[0].activationTuple.declaringModule = 'DifferentOwner' }
    else { $case.native.positiveFrontendObservations[0].activationTuple.bystanderModules = @('OtherBystander') }
    [void](Invoke-GraphProbeCase $case -ErrorPattern 'positive overlay activation tuple')
}
$orderedBystanders = New-GraphProbeCase 'bystander-order-and-repetition'
Set-GraphProbeRequestedRole $orderedBystanders
$raw = Get-Content -LiteralPath (Join-Path $orderedBystanders.producer $orderedBystanders.frozen.supplementalGraphInputs[0].relativePath) -Raw
Set-GraphProbeRawText $orderedBystanders ($raw.Replace('["BystanderB"]', '["BystanderB","AnotherBystander","BystanderB"]'))
$orderedBystanders.frozen.supplementalGraphInputs[0].bystanders = @('BystanderB', 'AnotherBystander', 'BystanderB')
$orderedBystanders.native.positiveFrontendObservations[0].activationTuple.bystanderModules = @('BystanderB', 'BystanderB', 'AnotherBystander')
[void](Invoke-GraphProbeCase $orderedBystanders -ErrorPattern 'positive overlay activation tuple')
$orderedSuccess = New-GraphProbeCase 'bystander-order-and-repetition-preserved'
Set-GraphProbeRequestedRole $orderedSuccess
$raw = Get-Content -LiteralPath (Join-Path $orderedSuccess.producer $orderedSuccess.frozen.supplementalGraphInputs[0].relativePath) -Raw
Set-GraphProbeRawText $orderedSuccess ($raw.Replace('["BystanderB"]', '["BystanderB","AnotherBystander","BystanderB"]'))
$orderedSuccess.frozen.supplementalGraphInputs[0].bystanders = @('BystanderB', 'AnotherBystander', 'BystanderB')
$orderedSuccess.native.positiveFrontendObservations[0].activationTuple.bystanderModules = @('BystanderB', 'AnotherBystander', 'BystanderB')
$orderedSuccess = Invoke-GraphProbeCase $orderedSuccess
$orderedReport = Read-GraphProbeJson $orderedSuccess.result.report.path
$orderedValues = $orderedReport.graphs[0].observedBystanders
Assert-GraphProbe ($orderedValues -is [Array] -and $orderedValues.Count -eq 3 -and
    $orderedValues[0] -ceq 'BystanderB' -and $orderedValues[1] -ceq 'AnotherBystander' -and
    $orderedValues[2] -ceq 'BystanderB') 'successful attributed B,A,B header preserves exact order and repetitions'

foreach ($caseName in @('multiple-exact-invocations', 'swapped-invocation-graph', 'overlapping-invocation-directories', 'same-name-wrong-invocation-proof')) {
    $case = New-GraphProbeCase $caseName
    Add-GraphProbeSecondInvocation $case
    $pattern = $null
    switch ($caseName) {
        'swapped-invocation-graph' { $case.frozen.supplementalGraphInputs[0].invocationId = $case.native.invocations[1].invocationId; $pattern = 'source directory contradicts' }
        'overlapping-invocation-directories' {
            $case.native.invocations[1].graphDirectory = 'emit-1'
            $case.native.invocations[1].arguments[6] = $case.native.invocations[0].arguments[6]
            $pattern = 'output directories overlap'
        }
        'same-name-wrong-invocation-proof' {
            $case.native.invocations[0].positiveFrontendObservationIds = @($case.native.positiveFrontendObservations[1].observationId)
            $pattern = 'another invocation context'
        }
    }
    $case = Invoke-GraphProbeCase $case -ErrorPattern $pattern
    if ($null -eq $pattern) {
        $multi = Read-GraphProbeJson $case.result.report.path
        Assert-GraphProbe ($multi.graphs.Count -eq 2 -and $multi.graphs.target -ccontains 'x86_64-apple-macosx26.5' -and
            $multi.graphs.target -ccontains 'arm64-apple-macosx26.5') 'every graph binds the exact architecture and Cxx invocation'
    }
}

foreach ($caseName in @('wrong-cxx-argument', 'duplicate-cxx-argument', 'separated-cxx-argument', 'wrong-output-argument', 'duplicate-output-argument', 'joined-output-argument', 'response-file-argument', 'joined-target-argument', 'joined-module-argument')) {
    $case = New-GraphProbeCase $caseName
    $invocation = $case.native.invocations[0]
    switch ($caseName) {
        'wrong-cxx-argument' { $invocation.arguments[4] = '-cxx-interoperability-mode=off'; $pattern = 'Cxx argument contradicts' }
        'duplicate-cxx-argument' { $invocation.arguments += '-cxx-interoperability-mode=default'; $pattern = 'exactly one joined Cxx' }
        'separated-cxx-argument' { $invocation.arguments[4] = '-cxx-interoperability-mode'; $invocation.arguments += 'default'; $pattern = 'Cxx argument contradicts' }
        'wrong-output-argument' { $invocation.arguments[6] = Join-Path $case.producer 'emit-2'; $pattern = 'arguments contradict' }
        'duplicate-output-argument' { $invocation.arguments += @('-output-dir', $invocation.arguments[6]); $pattern = 'exactly one recorded' }
        'joined-output-argument' { $invocation.arguments += '-output-dir=somewhere-else'; $pattern = 'separated output-directory' }
        'response-file-argument' { $invocation.arguments += '@hidden-context.rsp'; $pattern = 'Response-file arguments' }
        'joined-target-argument' { $invocation.arguments += '-target=arm64-apple-macosx25.0'; $pattern = 'only separated module and target' }
        'joined-module-argument' { $invocation.arguments += '-module-name=AnotherOverlay'; $pattern = 'only separated module and target' }
    }
    [void](Invoke-GraphProbeCase $case -ErrorPattern $pattern)
}
$cxxOff = New-GraphProbeCase 'exact-off-mode'
$cxxOff.native.invocations[0].cxxMode = 'off'; $cxxOff.native.invocations[0].arguments[4] = '-cxx-interoperability-mode=off'
$cxxOff.native.positiveFrontendObservations[0].cxxMode = 'off'
[void](Invoke-GraphProbeCase $cxxOff)

$duplicate = New-GraphProbeCase 'duplicate-graph-entry'
$duplicate.frozen.supplementalGraphInputs += $duplicate.frozen.supplementalGraphInputs[0]
[void](Invoke-GraphProbeCase $duplicate -ErrorPattern 'Duplicate')
$collision = New-GraphProbeCase 'portable-case-collision'
$second = $collision.frozen.supplementalGraphInputs[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$second.relativePath = $second.relativePath.ToUpperInvariant()
$collision.frozen.supplementalGraphInputs += $second
[void](Invoke-GraphProbeCase $collision -ErrorPattern 'Duplicate')
$extraFile = New-GraphProbeCase 'unexpected-file'
[IO.File]::WriteAllText((Join-Path $extraFile.producer 'emit-1/unexpected.txt'), 'not a graph', $encoding)
[void](Invoke-GraphProbeCase $extraFile -ErrorPattern 'Unexpected file')
$outputExists = New-GraphProbeCase 'existing-output'
[void][IO.Directory]::CreateDirectory($outputExists.output)
[IO.File]::WriteAllText((Join-Path $outputExists.output 'leave-me.txt'), 'original bytes', $encoding)
[void](Invoke-GraphProbeCase $outputExists -ErrorPattern 'already exists')
Assert-GraphProbe ((Get-Content -LiteralPath (Join-Path $outputExists.output 'leave-me.txt') -Raw) -ceq 'original bytes') 'existing output never overwritten'
$overlap = New-GraphProbeCase 'source-output-overlap'
$overlap.output = Join-Path $overlap.producer 'new-output'
[void](Invoke-GraphProbeCase $overlap -ErrorPattern 'overlap')
$traversal = New-GraphProbeCase 'source-path-traversal'
$traversal.frozen.supplementalGraphInputs[0].relativePath = '../outside.symbols.json'
[void](Invoke-GraphProbeCase $traversal -ErrorPattern 'traversing')

$sourceTamper = New-GraphProbeCase 'source-graph-seal-tamper'
$path = Join-Path $sourceTamper.producer $sourceTamper.frozen.supplementalGraphInputs[0].relativePath
$raw = [IO.File]::ReadAllText($path).Replace('DeclaringA', 'DeclaringX')
[IO.File]::WriteAllText($path, $raw, $encoding)
[void](Invoke-GraphProbeCase $sourceTamper -ErrorPattern 'changed before retention')
$inputSeal = New-GraphProbeCase 'input-metadata-seal-tamper'
[void](Invoke-GraphProbeCase $inputSeal -ErrorPattern 'SHA-256 mismatch' -AfterSealing {
    param($case)
    [IO.File]::AppendAllText($case.nativePath, ' ', $encoding)
})

$directoryLink = New-GraphProbeCase 'linked-emission-directory'
$linkPath = Join-Path $directoryLink.producer 'alias'
if ([IO.Path]::DirectorySeparatorChar -eq '\') {
    [void](New-Item -ItemType Junction -Path $linkPath -Target (Join-Path $directoryLink.producer 'emit-1'))
} else {
    [void](New-Item -ItemType SymbolicLink -Path $linkPath -Target (Join-Path $directoryLink.producer 'emit-1'))
}
[void](Invoke-GraphProbeCase $directoryLink -ErrorPattern 'symlink|reparse')

foreach ($budgetCase in @(
    @{ name = 'per-graph-size-guard'; fixtures = @('owner-named'); limits = @{ graphBytes = 64 }; pattern = 'size or file count' },
    @{ name = 'total-byte-guard'; fixtures = @('owner-named', 'other-partition'); limits = @{ totalGraphBytes = 64 }; pattern = 'size or file count' },
    @{ name = 'file-count-guard'; fixtures = @('owner-named', 'other-partition'); limits = @{ graphFiles = 1 }; pattern = 'file count' },
    @{ name = 'producer-directory-guard'; fixtures = @('owner-named'); limits = @{ directories = 1 }; pattern = 'directory budget' },
    @{ name = 'bounded-metadata-guard'; fixtures = @('owner-named'); limits = @{ metadataBytes = 1024 }; pattern = 'metadata exceeds' }
)) {
    [void](Invoke-GraphProbeCase (New-GraphProbeCase $budgetCase.name $budgetCase.fixtures) -Limits $budgetCase.limits -ErrorPattern $budgetCase.pattern)
}
$largeRecord = New-GraphProbeCase 'record-size-guard'
$raw = Get-Content -LiteralPath (Join-Path $largeRecord.producer $largeRecord.frozen.supplementalGraphInputs[0].relativePath) -Raw
Set-GraphProbeRawText $largeRecord ($raw.Replace('"Instance Method"', '"' + ('x' * 2048) + '"'))
[void](Invoke-GraphProbeCase $largeRecord -Limits @{ maximumRecordCharacters = 1024 } -ErrorPattern 'record exceeds')

foreach ($tamperName in @('retained-graph', 'inventory', 'report', 'seal', 'extra-output-file')) {
    $case = Invoke-GraphProbeCase (New-GraphProbeCase ('tamper-' + $tamperName))
    $case | Add-Member -NotePropertyName tamperKind -NotePropertyValue $tamperName
    Assert-GraphProbeReadRefusal $case {
        param($item)
        $path = switch ($item.tamperKind) {
            'retained-graph' { Join-Path $item.output ('graphs/' + $item.frozen.supplementalGraphInputs[0].relativePath) }
            'inventory' { Join-Path $item.output 'supplemental-inventory.json' }
            'report' { Join-Path $item.output 'supplemental-report.json' }
            'seal' { Join-Path $item.output 'supplemental-report.sha256' }
            'extra-output-file' { Join-Path $item.output 'unexpected.txt' }
        }
        [IO.File]::AppendAllText($path, ' ', $encoding)
    } 'tampered|SHA-256 mismatch|seal mismatch|Extraneous'
}

foreach ($invalidReport in @('inconsistent-inventory-descriptor', 'inconsistent-occurrence-counts', 'synthetic-cannot-be-relabelled-native', 'report-batch-cannot-change')) {
    $case = Invoke-GraphProbeCase (New-GraphProbeCase $invalidReport)
    $value = Read-GraphProbeJson $case.result.report.path
    switch ($invalidReport) {
        'inconsistent-inventory-descriptor' { $value.inventory.sha256 = 'a' * 64; $pattern = 'inventory descriptor' }
        'inconsistent-occurrence-counts' { $value.counts.declarationOccurrences++; $pattern = 'count or input roster' }
        'synthetic-cannot-be-relabelled-native' { $value.executionKind = 'native'; $pattern = 'execution provenance differs' }
        'report-batch-cannot-change' { $value.batchId = 'different-batch'; $pattern = 'report batch differs' }
    }
    Write-GraphProbeJson $case.result.report.path $value
    $case.result.report.sha256 = Get-GraphProbeHash $case.result.report.path
    [IO.File]::WriteAllText($case.result.seal.path, ($case.result.report.sha256 + '  supplemental-report.json' + [char]10), $encoding)
    Assert-GraphProbeReadRefusal $case {} $pattern
}

# The separate adapter must not relax the existing primary baseline contract.
Initialize-SwiftUIBaselineStreaming
$primary = [SwiftUIBaseline.Streaming.GraphInput]::new()
$primary.Path = Join-Path $empty.producer $empty.frozen.supplementalGraphInputs[0].relativePath
$primary.RelativePath = 'graphs/DeclaringA.symbols.json'; $primary.RequestedModule = 'DeclaringA'
$primary.Target = 'arm64-apple-macosx26.5'; $primary.Primary = $true
$caught = $null
try { [void][SwiftUIBaseline.Streaming.InventoryWriter]::Write('synthetic-original-primary-guard', @($primary), (Join-Path $OutputRoot 'must-not-publish-primary.json'), 1024, 2, 32MB) }
catch { $caught = $_ }
Assert-GraphProbe ($null -ne $caught -and $caught.Exception.ToString() -match 'Primary graph.*empty') 'existing empty primary baseline guard remains strict'
Assert-GraphProbe (-not (Test-Path -LiteralPath (Join-Path $OutputRoot 'must-not-publish-primary.json'))) 'failed baseline primary emits no inventory'
[void]$script:GraphProbeCases.Add([pscustomobject]@{ name = 'original-primary-guard'; outcome = 'expected-refusal' })

foreach ($relative in $preservedPaths) {
    Assert-GraphProbe ((Get-FileHash -LiteralPath (Join-Path $RepositoryRoot $relative)).Hash -ceq $preserved[$relative]) ('existing source or baseline preserved: ' + $relative)
}
$summary = [pscustomobject][ordered]@{
    schemaVersion = 1; evidenceKind = 'synthetic-supplemental-graph-tests'; nativeExecution = $false
    caseCount = $script:GraphProbeCases.Count; assertions = $script:GraphProbeAssertions; cases = $script:GraphProbeCases.ToArray()
    streamingHelperSourceSha256 = [SwiftUIBaseline.Streaming.InventoryWriter]::SourceHash
    preservedSourceFiles = $preservedPaths; outputRoot = $OutputRoot
}
Write-GraphProbeJson (Join-Path $OutputRoot 'summary.json') $summary
Write-Host "Supplemental graph tests passed $($summary.caseCount) cases and $($summary.assertions) assertions; synthetic inputs only."
Write-Host "Evidence: $OutputRoot"
