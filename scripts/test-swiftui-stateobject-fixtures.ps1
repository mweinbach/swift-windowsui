#requires -Version 5.1
<#
.SYNOPSIS
Checks the frozen public StateObject compiler inputs without running Swift.
.DESCRIPTION
Works in Windows PowerShell 5.1 and PowerShell 7. Reads only committed fixture
data and creates synthetic not-run records in memory. No compiler, child
process, native UI, network request, log capture, or file mutation is used.
#>
param(
    [string]$FixtureRoot = (Join-Path $PSScriptRoot 'fixtures/swiftui-stateobject-isolation')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:StateObjectFixtureAssertions = 0
$approvedMatrixSHA256 = '7608f38966424c4f9ca8628836a11aea3388ede5d7b9858c6e99f42474cd887b'
$fixtureManifestSHA256 = '0b545ca4fb02507d02c5c11abceff23b981d3f00e52813d178deb9c35f27541e'
$sourcePackageSHA256 = 'fd60c674d9542fe88f7cd20af2d942d2527d4ac5a785e5b2242e9bafbe9c6c8d'
$approvedPlanSHA256 = '5becb88dac5db061d0db33da8973367d60dbbb15ef36605b9a3ebd9c9963a51e'
$utf8 = [Text.UTF8Encoding]::new($false, $true)

function Assert-StateObjectFixture {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "StateObject fixture assertion failed: $Message" }
    $script:StateObjectFixtureAssertions++
}

function Assert-StateObjectFixtureSequence {
    param([object[]]$Actual, [object[]]$Expected, [string]$Message)
    Assert-StateObjectFixture (@($Actual).Count -eq @($Expected).Count) "$Message (length)"
    for ($index = 0; $index -lt @($Expected).Count; $index++) {
        Assert-StateObjectFixture ([string]$Actual[$index] -ceq [string]$Expected[$index]) "$Message (item $index)"
    }
}

function Assert-StateObjectFixtureKeys {
    param($Value, [string[]]$Expected, [string]$Message)
    [string[]]$actualNames = @($Value.PSObject.Properties.Name)
    [string[]]$expectedNames = @($Expected)
    [Array]::Sort($actualNames, [StringComparer]::Ordinal)
    [Array]::Sort($expectedNames, [StringComparer]::Ordinal)
    Assert-StateObjectFixtureSequence $actualNames $expectedNames $Message
}

function Get-StateObjectFixtureBytesHash {
    param([byte[]]$Bytes)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($hasher.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $hasher.Dispose()
    }
}

function Assert-StateObjectFixturePinnedBytes {
    param([byte[]]$Bytes, [string]$Expected, [string]$Label)
    Assert-StateObjectFixture ((Get-StateObjectFixtureBytesHash $Bytes) -ceq $Expected) "$Label bytes match their reviewed SHA256"
}

function Assert-StateObjectFixtureThrows {
    param([scriptblock]$Operation, [string]$Message)
    $threw = $false
    try { & $Operation } catch { $threw = $true }
    Assert-StateObjectFixture $threw $Message
}

function Get-StateObjectFixtureCode {
    param([string]$Source)
    # These hash-pinned inputs use only line comments. This is a source-shape
    # check, not a general Swift parser or a replacement for compiler evidence.
    return [regex]::Replace($Source, '(?m)//[^\r\n]*', '')
}

function Assert-StateObjectFixtureShape {
    param([string]$Source, [string]$Pattern, [string]$Message)
    Assert-StateObjectFixture ([regex]::IsMatch((Get-StateObjectFixtureCode $Source), $Pattern)) $Message
}

$FixtureRoot = [IO.Path]::GetFullPath($FixtureRoot)
Assert-StateObjectFixture (Test-Path -LiteralPath $FixtureRoot -PathType Container) 'fixture directory exists'
Assert-StateObjectFixture (((Get-Item -LiteralPath $FixtureRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'fixture root is not a link'
$matrixPath = Join-Path $FixtureRoot 'matrix.json'
Assert-StateObjectFixture ((Get-Item -LiteralPath $matrixPath).Length -le 65536) 'matrix is small static data'
$matrixBytes = [IO.File]::ReadAllBytes($matrixPath)
$matrixRawSHA256 = Get-StateObjectFixtureBytesHash $matrixBytes
Assert-StateObjectFixture ($matrixBytes[0] -eq 123) 'matrix is UTF-8 JSON without a byte-order mark'
$matrixText = $utf8.GetString($matrixBytes)
$canonicalMatrixText = $matrixText.Replace("`r`n", "`n")
$canonicalMatrixBytes = $utf8.GetBytes($canonicalMatrixText)
Assert-StateObjectFixturePinnedBytes $canonicalMatrixBytes $approvedMatrixSHA256 'Matrix with CRLF normalized to LF'
Assert-StateObjectFixture (-not [regex]::IsMatch($matrixText, '(?i)(?:[a-z]:[\\/]|/Users/|/Applications/|AppData|\.\./|file://)')) 'matrix has no developer or traversal paths'

# The matrix alone permits CRLF-to-LF normalization for Git checkouts. Its pin
# is verified before parsing; Swift sources below always require exact raw bytes.
# PS5.1 is not being presented as a strict capture/result JSON parser.
$matrix = ConvertFrom-Json -InputObject $matrixText
Assert-StateObjectFixtureKeys $matrix @('schemaVersion', 'product', 'provenance', 'targets', 'requiredFlags', 'counts', 'sourceFiles', 'cases', 'limits', 'protocol', 'qualification') 'matrix root fields'
Assert-StateObjectFixture ($matrix.schemaVersion -eq 1 -and $matrix.product -ceq 'swiftui-stateobject-isolation') 'matrix identity'
Assert-StateObjectFixtureKeys $matrix.provenance @('originalFixtureManifestSHA256', 'originalSourcePackageSHA256', 'approvedMatrixPlanSHA256') 'provenance fields'
Assert-StateObjectFixture ($matrix.provenance.originalFixtureManifestSHA256 -ceq $fixtureManifestSHA256) 'original fixture manifest stays pinned'
Assert-StateObjectFixture ($matrix.provenance.originalSourcePackageSHA256 -ceq $sourcePackageSHA256) 'original probe package stays pinned'
Assert-StateObjectFixture ($matrix.provenance.approvedMatrixPlanSHA256 -ceq $approvedPlanSHA256) 'approved plan stays pinned'
Assert-StateObjectFixtureSequence @($matrix.targets) @('x86_64-apple-macosx26.5', 'arm64-apple-macosx26.5') 'only the two approved desktop targets'
Assert-StateObjectFixtureSequence @($matrix.requiredFlags) @('-swift-version', '6', '-strict-concurrency=complete', '-warnings-as-errors', '-default-isolation', 'nonisolated', '-parse-as-library', '-emit-sil', '-whole-module-optimization') 'strict compiler flags'
Assert-StateObjectFixture ($matrix.counts.families -eq 8 -and $matrix.counts.publicSourceFiles -eq 24 -and $matrix.counts.casesPerNativeTarget -eq 21 -and $matrix.counts.desktopTargets -eq 2 -and $matrix.counts.plannedNativeRequests -eq 42 -and $matrix.counts.futureSeparateWindowsPublicRequests -eq 21) 'native and future Windows counts remain separate'
Assert-StateObjectFixture ($matrix.limits.perRequestSeconds -eq 120 -and $matrix.limits.maxCombinedRawOutputBytes -eq 1048576 -and $matrix.limits.maxArchivedSILBytesPerCase -eq 8388608 -and $matrix.limits.maxMatrixSeconds -eq 1800) 'request, combined-stream, SIL and overall bounds'
Assert-StateObjectFixture ($matrix.limits.mustBeReviewedAndFrozenBeforeExecution -eq $true -and $matrix.limits.automaticLimitIncreaseAllowed -eq $false) 'limits cannot expand automatically'
Assert-StateObjectFixtureSequence @($matrix.protocol.dependencyKeyFields) @('attemptID', 'target', 'compilerProfileSHA256', 'caseID') 'dependencies require the same attempt, target and profile'
foreach ($name in @('characterizeNativeAdmitAndRejectSeparatelyFromDesiredSafety', 'continueAcrossOrdinarySourceOutcomes', 'stopOnToolOrProvenanceFailure', 'failedControlInvalidatesDependentQualification', 'preserveAllUnrunCells', 'noCaseLaunchWithoutApprovedCompilerProfile', 'existingFrozen67UnrunCellsMustRemainUnchanged', 'qualifiedNegativeRequiresNormalCompilerRejectionAndIntendedPrimaryError')) {
    Assert-StateObjectFixture ($matrix.protocol.$name -eq $true) "required protocol rule $name"
}
foreach ($name in @('linkOrExecuteAllowed', 'crossTargetProfileOrAttemptDependencyReuseAllowed', 'notesOnlyOrMixedUnrelatedPrimaryErrorsCanQualify')) {
    Assert-StateObjectFixture ($matrix.protocol.$name -eq $false) "forbidden protocol rule $name"
}
Assert-StateObjectFixtureKeys $matrix.qualification @('nativeSourceBehaviorObserved', 'runtimeEvidence', 'parityClaimed', 'productionApprovalChanged') 'qualification fields'
foreach ($property in $matrix.qualification.PSObject.Properties) {
    Assert-StateObjectFixture ($property.Value -eq $false) "fixture data does not establish $($property.Name)"
}

$expectedOrder = @(
    '01-direct', '02-generic-forwarding', '03-explicit-initializer',
    '04-synthesized-mainactor-control', '05-sendable-control', '05-actor-transfer',
    '06-mainactor-access', '06-mainactor-factory-control',
    '08-capture-transfer-task-control', '08-capture-transfer-actor-control',
    '08-direct-capture-checker-control', '06-reject-wrapped-access',
    '06-reject-projected-access', '06-reject-mainactor-factory',
    '04-synthesized-initializer', '04-synthesized-app', '04-synthesized-scene',
    '07-observable-protocol-control', '07-observable-protocol-confound',
    '08-capture-transfer', '08-capture-transfer-actor'
)
$expectedIDs = @($expectedOrder | ForEach-Object { 'paired-public:' + $_ })
Assert-StateObjectFixtureSequence @($matrix.cases.caseID) $expectedIDs 'all 21 case IDs in approved order'
$admissionCases = @($expectedOrder[0..9])
$diagnosticCases = @($expectedOrder[10..13])
$observationCases = @($expectedOrder[14..18])
$unsafeCases = @($expectedOrder[19..20])
$sourceText = @{}
$sourceIDs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$sharedPure = 'paired-public/00-pure-model.swift'
$sharedCounter = 'paired-public/00-mutable-counter.swift'
$sharedOrdinary = 'paired-public/07-ordinary-model.swift'
Assert-StateObjectFixture (@($matrix.sourceFiles).Count -eq 24) 'exactly 24 source declarations'
$publicRoot = Join-Path $FixtureRoot 'paired-public'
Assert-StateObjectFixture (((Get-Item -LiteralPath $publicRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'public source directory is not a link'
$children = @(Get-ChildItem -LiteralPath $publicRoot -Force)
Assert-StateObjectFixture ($children.Count -eq 24 -and @($children | Where-Object { $_.PSIsContainer }).Count -eq 0) 'public directory contains only the 24 source files'
foreach ($source in $matrix.sourceFiles) {
    Assert-StateObjectFixtureKeys $source @('path', 'sha256') "source record $($source.path)"
    Assert-StateObjectFixture ([regex]::IsMatch($source.path, '^paired-public/[0-9a-z-]+\.swift$')) 'source path is a simple relative Swift file'
    Assert-StateObjectFixture ($sourceIDs.Add($source.path)) "source path is unique: $($source.path)"
    Assert-StateObjectFixture ([regex]::IsMatch($source.sha256, '^[0-9a-f]{64}$')) 'source hash is canonical SHA256'
    $path = Join-Path $FixtureRoot $source.path
    $item = Get-Item -LiteralPath $path
    Assert-StateObjectFixture (-not $item.PSIsContainer -and $item.Length -gt 0 -and $item.Length -le 16384) "bounded source file $($source.path)"
    Assert-StateObjectFixture (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'source file is not a link'
    $bytes = [IO.File]::ReadAllBytes($path)
    Assert-StateObjectFixturePinnedBytes $bytes $source.sha256 $source.path
    $text = $utf8.GetString($bytes)
    $sourceText[$source.path] = $text
    Assert-StateObjectFixtureShape $text '\A#if canImport\(SwiftUI\)\s+import SwiftUI\s+#else\s+import WinSwiftUI\s+#endif' 'every file retains the public conditional imports'
    $code = Get-StateObjectFixtureCode $text
    Assert-StateObjectFixture (-not [regex]::IsMatch($code, '@main\b|\.main\s*\(|\.body\b|@testable\b|@_spi\b|@unchecked\b|@Sendable\b|@preconcurrency\b|\bsending\b|assumeIsolated|unsafeBitCast|nonisolated\s*\(unsafe\)|IMPORT_PROTOTYPE|WinSwiftUIWindowHost|RetainedViewRuntime|ViewBuildContext|\b_makeProperty\b')) 'source has no entry invocation, private runtime API, stronger thunk or unchecked escape'
    [byte[]]$changedBytes = $bytes.Clone()
    $changedBytes[0] = $changedBytes[0] -bxor 1
    Assert-StateObjectFixtureThrows { Assert-StateObjectFixturePinnedBytes $changedBytes $source.sha256 'Synthetic changed source' } 'a one-byte source mutation is rejected in memory'
}

$seenCases = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$usedSources = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$families = [Collections.Generic.HashSet[int]]::new()
foreach ($case in $matrix.cases) {
    Assert-StateObjectFixtureKeys $case @('caseID', 'family', 'source', 'sharedSources', 'originalExpected', 'role', 'desiredSafetyOutcome', 'requiredPriorControls', 'requiredPriorObservationCases', 'requiresForWrapperSpecificAdmission', 'diagnosticExpectation') "case fields $($case.caseID)"
    $suffix = $case.caseID.Substring('paired-public:'.Length)
    Assert-StateObjectFixture ($case.family -eq [int]$suffix.Substring(0, 2)) 'case remains in its original family'
    [void]$families.Add([int]$case.family)
    Assert-StateObjectFixture ($case.source -ceq ('paired-public/' + $suffix + '.swift')) 'case source matches its original entry'
    $expectedShared = @($sharedPure)
    if ($suffix -ceq '02-generic-forwarding') { $expectedShared = @() }
    elseif ($suffix.StartsWith('07-', [StringComparison]::Ordinal)) { $expectedShared = @($sharedOrdinary) }
    elseif ($suffix -ceq '08-direct-capture-checker-control') { $expectedShared = @($sharedCounter) }
    elseif ($suffix.StartsWith('08-', [StringComparison]::Ordinal)) { $expectedShared = @($sharedPure, $sharedCounter) }
    Assert-StateObjectFixtureSequence @($case.sharedSources) $expectedShared 'case receives only its original shared sources'
    foreach ($path in @($case.sharedSources) + @($case.source)) {
        Assert-StateObjectFixture ($sourceIDs.Contains($path)) 'every compile input has a reviewed hash'
        [void]$usedSources.Add($path)
    }
    $expectedRole = 'source-observation-or-confound'
    $expectedOutcome = 'confound'
    if ($admissionCases -ccontains $suffix) { $expectedRole = 'admission-control'; $expectedOutcome = 'admit' }
    elseif ($diagnosticCases -ccontains $suffix) { $expectedRole = 'intended-diagnostic-control'; $expectedOutcome = 'reject' }
    elseif ($unsafeCases -ccontains $suffix) { $expectedRole = 'unsafe-wrapper-characterization'; $expectedOutcome = 'reject' }
    Assert-StateObjectFixture ($case.role -ceq $expectedRole -and $case.originalExpected -ceq $expectedOutcome) 'native characterization does not rewrite original case roles'
    if ($unsafeCases -ccontains $suffix) {
        Assert-StateObjectFixture ($case.desiredSafetyOutcome -ceq 'reject') 'unsafe witnesses retain desired rejection'
        Assert-StateObjectFixtureSequence @($case.requiredPriorControls) @('paired-public:01-direct', 'paired-public:02-generic-forwarding', 'paired-public:05-sendable-control', ('paired-public:' + $(if ($suffix -ceq '08-capture-transfer') { '08-capture-transfer-task-control' } else { '08-capture-transfer-actor-control' }))) 'unsafe witness positive controls'
        Assert-StateObjectFixtureSequence @($case.requiresForWrapperSpecificAdmission) @('paired-public:08-direct-capture-checker-control') 'wrapper-specific admission requires the direct checker'
    } else {
        Assert-StateObjectFixture ($null -eq $case.desiredSafetyOutcome) 'other roles do not fabricate a capture-safety verdict'
        Assert-StateObjectFixtureSequence @($case.requiresForWrapperSpecificAdmission) @() 'only unsafe witnesses have wrapper-specific admission controls'
    }
    $priorObservations = @()
    if ($suffix -ceq '07-observable-protocol-confound') { $priorObservations = @('paired-public:07-observable-protocol-control') }
    Assert-StateObjectFixtureSequence @($case.requiredPriorObservationCases) $priorObservations 'protocol confound requires an observation, not admission'
    if ($suffix -ceq '07-observable-protocol-confound') {
        Assert-StateObjectFixtureSequence @($case.requiredPriorControls) @() 'ordinary model confound has no invented admission requirement'
    }
    foreach ($dependency in @($case.requiredPriorControls) + @($case.requiredPriorObservationCases) + @($case.requiresForWrapperSpecificAdmission)) {
        Assert-StateObjectFixture ($seenCases.Contains($dependency)) 'every dependency occurs earlier in the fixed order'
    }
    if ($diagnosticCases -ccontains $suffix -or $unsafeCases -ccontains $suffix) {
        Assert-StateObjectFixture ($null -ne $case.diagnosticExpectation) 'negative cases retain an intended diagnostic description'
        Assert-StateObjectFixtureKeys $case.diagnosticExpectation @('family', 'subject', 'anchors') 'diagnostic metadata fields'
        Assert-StateObjectFixture (@($case.diagnosticExpectation.anchors).Count -gt 0) 'diagnostic metadata has source operations'
        foreach ($anchor in $case.diagnosticExpectation.anchors) {
            Assert-StateObjectFixtureKeys $anchor @('line', 'operation') 'diagnostic source anchor fields'
            $lines = $sourceText[$case.source] -split '\r?\n'
            Assert-StateObjectFixture ($anchor.line -ge 1 -and $anchor.line -le $lines.Count) 'diagnostic anchor is inside the exact source'
            $operationPattern = switch -CaseSensitive ($anchor.operation) {
                'wrapped-access' { 'wrapper\.wrappedValue' }
                'projected-access' { 'wrapper\.projectedValue' }
                'helper-call' { 'wrappedValue:\s*makeActorOnlyModel\(\)' }
                'deferred-expression' { 'wrappedValue:\s*PureModel\(seed:\s*alias\.advance\(\)\)' }
                'task-transfer' { 'Task\s*\{\s*@MainActor\s*\[(?:wrapper|alias)\]' }
                'captured-access' { 'alias\.advance\(\)' }
                'alias-reuse' { '(?:counter|alias)\.advance\(\)' }
                default { throw 'Unexpected diagnostic operation in pinned matrix.' }
            }
            Assert-StateObjectFixture ([regex]::IsMatch($lines[$anchor.line - 1], $operationPattern)) 'diagnostic line still contains the reviewed source operation'
        }
    } else {
        Assert-StateObjectFixture ($null -eq $case.diagnosticExpectation) 'admissions and confounds do not invent expected diagnostics'
    }
    Assert-StateObjectFixture ($seenCases.Add($case.caseID)) 'case IDs are unique'
}
Assert-StateObjectFixture ($families.Count -eq 8 -and $usedSources.Count -eq 24) 'all eight families and 24 sources are used'
Assert-StateObjectFixture ($admissionCases.Count -eq 10 -and $diagnosticCases.Count -eq 4 -and $observationCases.Count -eq 5 -and $unsafeCases.Count -eq 2) 'role partition remains 10/4/5/2'

Assert-StateObjectFixtureShape $sourceText[$sharedPure] '(?s)@MainActor\s+public final class PureModel:\s*ObservableObject\s*\{\s*public let seed:\s*Int\s+public nonisolated init\(seed:\s*Int\)' 'pure model removes unrelated actor initializer and mutable-model confounds'
Assert-StateObjectFixtureShape $sourceText[$sharedCounter] '(?s)final class ProbeMutableCounter\s*\{\s*var value\s*=\s*0\s+func advance\(\)\s*->\s*Int\s*\{\s*value\s*\+=\s*1\s+return value' 'counter remains ordinary shared mutable state'
Assert-StateObjectFixture (-not [regex]::IsMatch((Get-StateObjectFixtureCode $sourceText[$sharedCounter]), '@MainActor|\bactor\b|\bSendable\b|\bMutex\b|\block\b')) 'counter has no actor, sendability or synchronization annotation'
Assert-StateObjectFixtureShape $sourceText[$sharedOrdinary] '(?s)public final class OrdinaryProbeModel:\s*ObservableObject\s*\{\s*public var value:\s*Int\s+public init\(seed:\s*Int\)' 'ordinary model remains a protocol inference confound'
Assert-StateObjectFixture (-not [regex]::IsMatch((Get-StateObjectFixtureCode $sourceText[$sharedOrdinary]), '@MainActor|\bnonisolated\b')) 'ordinary model is not manually isolated'
Assert-StateObjectFixtureShape $sourceText['paired-public/02-generic-forwarding.swift'] '(?s)func makeDeferredWrapper<Object:\s*ObservableObject>\(\s*_ make:\s*@escaping\s*\(\)\s*->\s*Object\s*\)\s*->\s*StateObject<Object>\s*\{\s*StateObject\(wrappedValue:\s*make\(\)\)' 'generic factory remains an ordinary escaping thunk'
Assert-StateObjectFixtureShape $sourceText['paired-public/03-explicit-initializer.swift'] '(?s)@MainActor\s+struct ExplicitInitializerOwner:\s*View.*?nonisolated init\(seed:\s*Int\).*?_model\s*=\s*StateObject\(wrappedValue:\s*PureModel\(seed:\s*seed\)\).*?var body:\s*some View\s*\{\s*Text\(String\(model\.seed\)\)' 'explicit owner retains the real public View body and nonisolated initializer'
foreach ($suffix in @('04-synthesized-initializer', '04-synthesized-mainactor-control', '04-synthesized-app', '04-synthesized-scene')) {
    $code = Get-StateObjectFixtureCode $sourceText[('paired-public/' + $suffix + '.swift')]
    Assert-StateObjectFixture (-not [regex]::IsMatch($code, '\binit\s*\(')) 'synthesized cases have no explicit initializer'
    Assert-StateObjectFixture ([regex]::IsMatch($code, '@StateObject\s+private var model\s*=\s*PureModel\(seed:\s*1\)')) 'synthesized owner keeps its deferred default'
}
Assert-StateObjectFixtureShape $sourceText['paired-public/04-synthesized-app.swift'] 'struct SynthesizedInitializerApp:\s*App' 'App observation stays a public App case'
Assert-StateObjectFixtureShape $sourceText['paired-public/04-synthesized-scene.swift'] 'struct SynthesizedInitializerScene:\s*Scene' 'Scene observation stays a public Scene case'
foreach ($suffix in @('08-capture-transfer', '08-capture-transfer-actor')) {
    Assert-StateObjectFixtureShape $sourceText[('paired-public/' + $suffix + '.swift')] '(?s)let alias\s*=\s*counter\s+let wrapper\s*=\s*StateObject\(wrappedValue:\s*PureModel\(seed:\s*alias\.advance\(\)\)\)\s+let reader\s*=\s*Task\s*\{\s*@MainActor\s*\[wrapper\]\s+in\s+_\s*=\s*wrapper\.wrappedValue\s*\}\s+_\s*=\s*(?:counter|alias)\.advance\(\)' 'unsafe witness defers the mutable alias and reuses it after scheduling a MainActor reader'
    Assert-StateObjectFixture (-not [regex]::IsMatch((Get-StateObjectFixtureCode $sourceText[('paired-public/' + $suffix + '.swift')]), '\bawait\b')) 'unsafe witness has no ordering await'
}
foreach ($suffix in @('08-capture-transfer-task-control', '08-capture-transfer-actor-control')) {
    Assert-StateObjectFixtureShape $sourceText[('paired-public/' + $suffix + '.swift')] '(?s)let seed\s*=\s*alias\.advance\(\)\s+let wrapper\s*=\s*StateObject\(wrappedValue:\s*PureModel\(seed:\s*seed\)\)\s+let reader\s*=\s*Task\s*\{\s*@MainActor\s*\[wrapper\]\s+in\s+_\s*=\s*wrapper\.wrappedValue\s*\}\s+_\s*=\s*(?:counter|alias)\.advance\(\)' 'control keeps transfer and alias reuse but captures only the precomputed Int'
}
Assert-StateObjectFixtureShape $sourceText['paired-public/08-direct-capture-checker-control.swift'] '(?s)let reader\s*=\s*Task\s*\{\s*@MainActor\s*\[alias\]\s+in\s+_\s*=\s*alias\.advance\(\)\s*\}\s+_\s*=\s*counter\.advance\(\)' 'direct checker transfers the same mutable alias without a wrapper'
Assert-StateObjectFixture (-not [regex]::IsMatch((Get-StateObjectFixtureCode $sourceText['paired-public/08-direct-capture-checker-control.swift']), '\bStateObject\b')) 'direct checker does not depend on StateObject'

# This small model tests matrix bookkeeping only. It is not the capture result
# schema, is never serialized as evidence, and contains no compiler outcomes.
$syntheticCells = @(
    foreach ($target in $matrix.targets) {
        foreach ($case in $matrix.cases) {
            [pscustomobject]@{
                evidenceKind = 'synthetic-test-data'
                attemptID = 'synthetic-manual-not-run'
                target = $target
                compilerProfileSHA256 = $null
                caseID = $case.caseID
                status = 'not-run'
                reason = 'manual-authorization-and-approved-profile-required'
                exitCode = $null
                stdout = $null
                stderr = $null
                sil = $null
                safetyRequirementMet = $null
            }
        }
    }
)
Assert-StateObjectFixture ($syntheticCells.Count -eq 42) 'a manual capture begins with all 42 native cells unrun'
$syntheticKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($cell in $syntheticCells) {
    Assert-StateObjectFixture ($syntheticKeys.Add($cell.target + '|' + $cell.caseID)) 'each target/case has a distinct unrun cell'
    Assert-StateObjectFixture ($cell.evidenceKind -ceq 'synthetic-test-data' -and $cell.status -ceq 'not-run') 'fabricated cells are explicitly synthetic and unrun'
    Assert-StateObjectFixture ($null -eq $cell.compilerProfileSHA256 -and $null -eq $cell.exitCode -and $null -eq $cell.stdout -and $null -eq $cell.stderr -and $null -eq $cell.sil -and $null -eq $cell.safetyRequirementMet) 'unrun examples contain no invented profile, logs, SIL or safety result'
}
[byte[]]$changedMatrix = $canonicalMatrixBytes.Clone()
$changedMatrix[0] = $changedMatrix[0] -bxor 1
Assert-StateObjectFixtureThrows { Assert-StateObjectFixturePinnedBytes $changedMatrix $approvedMatrixSHA256 'Synthetic changed matrix' } 'a one-byte matrix mutation is rejected before parsing'
$syntheticCRLF = $canonicalMatrixText.Replace("`n", "`r`n")
Assert-StateObjectFixturePinnedBytes ($utf8.GetBytes($syntheticCRLF.Replace("`r`n", "`n"))) $approvedMatrixSHA256 'Synthetic CRLF checkout of the matrix'

$readme = [IO.File]::ReadAllText((Join-Path $FixtureRoot 'README.md'), $utf8)
Assert-StateObjectFixture ($readme.Contains('manual authorization') -and $readme.Contains('`not-run`') -and $readme.Contains('67 unrun')) 'README distinguishes manual capture, unrun cells and immutable prior results'
$parseTokens = $null
$parseErrors = $null
$selfAst = [Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$parseTokens, [ref]$parseErrors)
Assert-StateObjectFixture (@($parseErrors).Count -eq 0) 'fixture test has valid PowerShell syntax'
$forbiddenCommands = @('swift', 'swiftc', 'swift-frontend', 'swift-format', 'git', 'gh', 'dotnet', 'csc', 'cmd', 'powershell', 'pwsh', 'Start-Process', 'Invoke-Expression', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Add-Type', 'Set-Content', 'Add-Content', 'Out-File', 'Remove-Item', 'Move-Item', 'Copy-Item', 'New-Item')
foreach ($command in $selfAst.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true)) {
    $name = $command.GetCommandName()
    if ($null -eq $name) {
        # Only the local exception assertion invokes a supplied scriptblock.
        Assert-StateObjectFixture ($command.CommandElements.Count -eq 1 -and $command.CommandElements[0].Extent.Text -ceq '$Operation') 'only the known in-memory assertion block uses a dynamic call'
    } else {
        Assert-StateObjectFixture ($forbiddenCommands -notcontains $name) 'fixture tests contain no compiler, network, child process or mutation command'
    }
}
Assert-StateObjectFixturePinnedBytes ([IO.File]::ReadAllBytes($matrixPath)) $matrixRawSHA256 'Raw matrix after read-only tests'
foreach ($source in $matrix.sourceFiles) {
    Assert-StateObjectFixturePinnedBytes ([IO.File]::ReadAllBytes((Join-Path $FixtureRoot $source.path))) $source.sha256 'Source after read-only tests'
}

Write-Host "StateObject fixture tests passed ($script:StateObjectFixtureAssertions assertions). All 24 sources are unchanged; 42 not-run cells were synthetic. No Swift, child process, native UI or compiler evidence was produced."
