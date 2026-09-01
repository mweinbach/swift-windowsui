<#
.SYNOPSIS
Tests pure Stage B argument/source generation and replays SYNTHETIC diagnostic,
trace, and process records. No compiler, SwiftPM, SDK, or native child is invoked.
All output is new owned synthetic evidence; existing captures are never changed.
#>
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot), [string]$OutputRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'The synthetic native-parser tests require PowerShell 7.' }
. (Join-Path $RepositoryRoot 'scripts/swiftui-overlay-probe-native.ps1')
if ([string]::IsNullOrEmpty($OutputRoot)) {
    $OutputRoot = Join-Path $RepositoryRoot ('artifacts/swiftui-overlay-probe-native-tests/' + [Guid]::NewGuid().ToString('N'))
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) { throw 'Synthetic output must be a new owned directory.' }
[void][IO.Directory]::CreateDirectory($OutputRoot)
[void](Assert-SwiftUIStateObjectDirectory $OutputRoot)
$script:NativeAssertions = 0
$script:NativeSequence = 0
$script:NativeCases = [Collections.Generic.List[object]]::new()
$script:NativeCaseNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$script:NativeUtf8 = [Text.UTF8Encoding]::new($false, $true)
$fixturePath = Join-Path $RepositoryRoot 'scripts/fixtures/swiftui-overlay-probes/native/synthetic-cases.json'
$fixtureRead = Read-SwiftUIStateObjectJson $fixturePath -MaxBytes 1MB
$script:NativeFixture = $fixtureRead.document
if ($script:NativeFixture.evidenceKind -cne 'SYNTHETIC-TEST-FIXTURE-NOT-NATIVE-CAPTURE') { throw 'The test fixture must carry its synthetic evidence marker.' }
$script:NativePolicy = Get-SwiftUIOverlayProbeNativePolicy
$script:NativeEmptyHash = Get-SwiftUIStateObjectBytesSHA256 ([byte[]]@())

function Assert-NativeTrue {
    param([bool]$Value, [string]$Message)
    $script:NativeAssertions++
    if (-not $Value) { throw "Synthetic native-parser assertion failed: $Message" }
}
function Assert-NativeThrows {
    param([scriptblock]$Action, [string]$Message)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-NativeTrue ($null -ne $caught) $Message
}
function Invoke-NativeCase {
    param([string]$Name, [scriptblock]$Action)
    if (-not $script:NativeCaseNames.Add($Name)) { throw 'Duplicate synthetic case name.' }
    $before = $script:NativeAssertions
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    $script:NativeCases.Add([pscustomobject][ordered]@{
        name = $Name; outcome = $(if ($null -eq $caught) { 'passed' } else { 'failed' })
        assertions = $script:NativeAssertions - $before
        error = $(if ($null -eq $caught) { $null } else { $caught.ToString() })
        errorLocation = $(if ($null -eq $caught) { $null } else { $caught.ScriptStackTrace })
    })
}
function Copy-NativeValue {
    param($Value)
    return ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 40 -Compress) -Depth 40
}
function Write-NativeRaw {
    param([string]$Suffix, [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $script:NativeSequence++
    $name = ('synthetic-{0:D4}-{1}' -f $script:NativeSequence, $Suffix)
    Assert-SwiftUIStateObjectRelativePath $name
    $path = Resolve-SwiftUIStateObjectEvidencePath -Root $OutputRoot -RelativePath $name -AllowMissingLeaf
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length) } finally { $stream.Dispose() }
    return $path
}
function Write-NativeText {
    param([string]$Suffix, [AllowEmptyString()][string]$Text)
    return Write-NativeRaw $Suffix ($script:NativeUtf8.GetBytes($Text))
}
function New-NativeSource {
    param([string]$Control = 'owner-bystander')
    return New-SwiftUIOverlayProbeSource $script:NativeFixture.declaringModule $script:NativeFixture.bystandingModule $Control
}
function Read-NativeDiagnosticText {
    param([AllowEmptyString()][string]$Text, [string]$Control = 'owner-bystander', [switch]$OmitSearchDump)
    if (-not $OmitSearchDump) { $Text = $script:NativeFixture.searchPathDump + $Text }
    $path = Write-NativeText 'stderr.txt' $Text
    return Read-SwiftUIOverlayProbeDiagnostics -StderrPath $path -ExpectedSourcePath $script:NativeFixture.sourcePath -SourceRecord (New-NativeSource $Control)
}
function Read-NativeTraceValue {
    param($Value, [string]$Target = 'arm64-apple-macosx26.5')
    $text = (ConvertTo-Json -InputObject $Value -Compress -Depth 40) + [char]10
    return Read-NativeTraceText $text $Target
}
function Read-NativeTraceText {
    param([AllowEmptyString()][string]$Text, [string]$Target = 'arm64-apple-macosx26.5')
    $path = Write-NativeText 'trace.json' $Text
    return Read-SwiftUIOverlayProbeTrace -Path $path -ExpectedModuleName ('SWUIOverlayProbe_' + $script:NativeFixture.requestId) -Target $Target
}
function New-NativeProcess {
    param($Diagnostics, [int]$ExitCode = 0)
    return [pscustomobject][ordered]@{
        evidenceKind = 'SYNTHETIC-TEST-RECORD-NOT-A-PROCESS-CAPTURE'
        processStarted = $true; exitCode = $ExitCode; timedOut = $false; outputLimitExceeded = $false
        terminationRequested = $false; terminationCompleted = $true; allRedirectedStreamsClosed = $true
        error = $null; cleanupErrors = @(); stdoutBytes = [long]0; stderrBytes = [long]$Diagnostics.bytes
        stdoutSha256 = $script:NativeEmptyHash; stderrSha256 = $Diagnostics.sha256
        observedDiscardedBytes = [long]0; descendantsClosed = $null
    }
}
function New-NativeBundle {
    param([string]$DiagnosticKind = 'positive', [string]$Control = 'owner-bystander',
        [string]$Target = 'arm64-apple-macosx26.5', [string]$CxxMode = 'off')
    $diagnostics = Read-NativeDiagnosticText $script:NativeFixture.diagnostics.$DiagnosticKind $Control
    $traceValue = Copy-NativeValue $script:NativeFixture.trace
    $traceValue.arch = if ($Target -ceq 'arm64-apple-macosx26.5') { 'arm64' } else { 'x86_64' }
    return [pscustomobject]@{
        requestId = $script:NativeFixture.requestId; compilerProfileSha256 = $script:NativeFixture.compilerProfileSha256
        declaringModule = $script:NativeFixture.declaringModule; bystandingModule = $script:NativeFixture.bystandingModule
        overlayModule = $script:NativeFixture.overlayModule; control = $Control; target = $Target; cxxMode = $CxxMode
        candidateRecordIds = @($script:NativeFixture.candidateRecordIds); launchState = 'confirmed-started'
        process = New-NativeProcess $diagnostics; diagnostics = $diagnostics
        trace = Read-NativeTraceValue $traceValue $Target
        pathObservations = @(Copy-NativeValue $script:NativeFixture.pathObservations)
    }
}
function Get-NativeAssessment {
    param($Bundle)
    return Get-SwiftUIOverlayProbeAssessment -RequestId $Bundle.requestId -CompilerProfileSha256 $Bundle.compilerProfileSha256 `
        -DeclaringModule $Bundle.declaringModule -BystandingModule $Bundle.bystandingModule -OverlayModule $Bundle.overlayModule `
        -Control $Bundle.control -Target $Bundle.target -CxxMode $Bundle.cxxMode -CandidateRecordIds $Bundle.candidateRecordIds `
        -LaunchState $Bundle.launchState -Process $Bundle.process -Diagnostics $Bundle.diagnostics -Trace $Bundle.trace `
        -PathObservations $Bundle.pathObservations
}

Invoke-NativeCase 'fixed-source-controls-and-keywords' {
    $expected = @{
        'owner-only' = @('Alpha'); 'bystander-only' = @('Beta')
        'owner-bystander' = @('Alpha', 'Beta'); 'bystander-owner' = @('Beta', 'Alpha')
    }
    foreach ($control in $script:NativePolicy.controls) {
        $source = New-NativeSource $control
        Assert-NativeTrue (($source.imports -join ',') -ceq ($expected[$control] -join ',')) "exact imports for $control"
        Assert-NativeTrue ($source.bytes -eq $script:NativeUtf8.GetByteCount($source.text)) 'byte count binds exact source'
        Assert-NativeTrue ($source.text.EndsWith([string][char]10) -and -not $source.text.Contains([char]13)) 'source is LF terminated'
        Assert-NativeTrue ($source.sha256 -ceq (Get-SwiftUIStateObjectBytesSHA256 ($script:NativeUtf8.GetBytes($source.text)))) 'source hash is exact'
        Assert-NativeTrue (-not $source.text.Contains('_Alpha_Beta')) 'trigger controls never import overlay explicitly'
    }
    $keyword = New-SwiftUIOverlayProbeSource 'class' 'import' 'owner-bystander'
    Assert-NativeTrue ($keyword.text.Contains('import `class`') -and $keyword.text.Contains('import `import`')) 'keyword names are escaped without rewriting them'
}
Invoke-NativeCase 'source-rejects-injection-and-unsupported-identifiers' {
    foreach ($value in @('', '_', 'Alpha.Beta', 'A; import SwiftUI', 'A`', "A`nimport Evil", 'A-B', 'α', ('A' * 129), 123, $true)) {
        Assert-NativeThrows { New-SwiftUIOverlayProbeSource $value 'Beta' 'owner-bystander' } "reject unsupported identifier $value"
    }
    Assert-NativeThrows { New-SwiftUIOverlayProbeSource 'Alpha' 'Alpha' 'owner-only' } 'self import is visible unsupported'
    Assert-NativeThrows { New-SwiftUIOverlayProbeSource 'Alpha' 'Beta' 'OWNER-ONLY' } 'control names are case exact'
}
Invoke-NativeCase 'fixed-argv-both-targets-and-cxx-contexts' {
    foreach ($target in $script:NativePolicy.targets) {
        foreach ($cxx in $script:NativePolicy.cxxModes) {
            $frontendArgs = New-SwiftUIOverlayProbeCompilerArguments $script:NativePolicy.sdkPath $target $cxx '/SYNTHETIC/cache fresh' ('SWUIOverlayProbe_' + $script:NativeFixture.requestId) '/SYNTHETIC/trace.json' $script:NativeFixture.sourcePath
            $expected = @('-typecheck', '-parse-as-library', '-sdk', $script:NativePolicy.sdkPath, '-target', $target,
                '-swift-version', '6', '-module-cache-path', '/SYNTHETIC/cache fresh', '-module-name', ('SWUIOverlayProbe_' + $script:NativeFixture.requestId),
                "-cxx-interoperability-mode=$cxx", '-enable-cross-import-overlays', '-Rcross-import', '-Rmodule-loading',
                '-debug-diagnostic-names', '-diagnostic-style', 'llvm', '-no-color-diagnostics', '-emit-loaded-module-trace-path', '/SYNTHETIC/trace.json', $script:NativeFixture.sourcePath)
            Assert-NativeTrue ((ConvertTo-Json -InputObject $frontendArgs -Compress) -ceq (ConvertTo-Json -InputObject $expected -Compress)) 'frontend argv is exactly frozen'
            $extract = New-SwiftUIOverlayProbeExtractorArguments '_Alpha_Beta' $script:NativePolicy.sdkPath $target $cxx '/SYNTHETIC/extract-cache' '/SYNTHETIC/output'
            Assert-NativeTrue ($extract[0] -ceq '-module-name' -and $extract[1] -ceq '_Alpha_Beta') 'extractor targets overlay directly'
            Assert-NativeTrue ($extract -ccontains '-experimental-allowed-reexported-modules=SwiftUI,SwiftUICore') 'original reexport allowlist remains exact'
            Assert-NativeTrue (-not (($extract -join ' ') -match 'Rcross|Rmodule|loaded-module-trace|enable-cross-import|Xfrontend')) 'frontend-only flags never leak into extractor'
            Assert-NativeTrue ($extract -ccontains "-cxx-interoperability-mode=$cxx") 'extraction binds explicit C++ context'
        }
    }
}
Invoke-NativeCase 'argv-rejects-unsupported-contexts-and-paths' {
    foreach ($path in @('relative', '/', '/SYNTHETIC//cache', '/SYNTHETIC/../cache', '/SYNTHETIC/./cache', '/SYNTHETIC/cache/', "/SYNTHETIC/ca'che", '/SYNTHETIC/ca\che', "/SYNTHETIC/ca`nche")) {
        Assert-NativeThrows { Assert-SwiftUIOverlayProbeNativePath $path } 'unsupported path is not silently repaired'
    }
    Assert-NativeThrows { New-SwiftUIOverlayProbeCompilerArguments $script:NativePolicy.sdkPath 'arm64-apple-macosx26.4' 'off' '/SYNTHETIC/cache' ('SWUIOverlayProbe_' + $script:NativeFixture.requestId) '/SYNTHETIC/trace' $script:NativeFixture.sourcePath } 'target drift is rejected'
    Assert-NativeThrows { New-SwiftUIOverlayProbeCompilerArguments $script:NativePolicy.sdkPath 'arm64-apple-macosx26.5' 'DEFAULT' '/SYNTHETIC/cache' ('SWUIOverlayProbe_' + $script:NativeFixture.requestId) '/SYNTHETIC/trace' $script:NativeFixture.sourcePath } 'C++ mode casing is fixed'
    Assert-NativeThrows { New-SwiftUIOverlayProbeCompilerArguments '/different/sdk' 'arm64-apple-macosx26.5' 'off' '/SYNTHETIC/cache' ('SWUIOverlayProbe_' + $script:NativeFixture.requestId) '/SYNTHETIC/trace' $script:NativeFixture.sourcePath } 'SDK drift is rejected'
    Assert-NativeThrows { New-SwiftUIOverlayProbeCompilerArguments $script:NativePolicy.sdkPath 'arm64-apple-macosx26.5' 'off' '/SYNTHETIC/cache' 'SWUIOverlayProbe_short' '/SYNTHETIC/trace' $script:NativeFixture.sourcePath } 'module name must retain whole request hash'
}

Invoke-NativeCase 'positive-evidence-both-targets-cxx-modes-and-import-orders' {
    foreach ($target in $script:NativePolicy.targets) {
        foreach ($cxx in $script:NativePolicy.cxxModes) {
            foreach ($control in @('owner-bystander', 'bystander-owner')) {
                $bundle = New-NativeBundle -Control $control -Target $target -CxxMode $cxx
                $result = Get-NativeAssessment $bundle
                Assert-NativeTrue ($result.outcome -ceq 'overlay-load-observed' -and $result.overlayActivationObserved) 'all positive components required'
                Assert-NativeTrue (-not $result.stopLaterCommands -and -not $result.descendantClosureRequired -and $null -eq $result.descendantsClosed) 'natural exit does not fabricate a descendant census'
                Assert-NativeTrue ($result.descendantClosureStatus -ceq 'not-independently-observed') 'ordinary closure limitation is explicit'
                Assert-NativeTrue (-not $result.lexicalPairNecessityEstablished -and -not $result.definitionOccurrenceTriggered) 'load does not prove causal necessity or selected definition occurrence'
                Assert-NativeTrue (-not $result.publicAPIAuditComplete -and -not $result.nativeRuntimeVerified -and -not $result.releaseQualified) 'load does not qualify product behavior'
            }
        }
    }
}
Invoke-NativeCase 'single-import-controls-remain-load-observations-not-necessity-proofs' {
    foreach ($control in @('owner-only', 'bystander-only')) {
        $bundle = New-NativeBundle -Control $control
        $text = $script:NativeFixture.diagnostics.positive.Replace(':4:8:', ':3:8:')
        $echo = if ($control -ceq 'owner-only') { 'import `Alpha`' } else { 'import `Beta`' }
        $text = $text.Replace('import `Beta`', $echo)
        $bundle.diagnostics = Read-NativeDiagnosticText $text $control
        $bundle.process = New-NativeProcess $bundle.diagnostics
        $result = Get-NativeAssessment $bundle
        Assert-NativeTrue ($result.overlayActivationObserved) 'transitive imports may activate an overlay under one lexical import'
        Assert-NativeTrue (-not $result.lexicalPairNecessityEstablished) 'single-control activation cannot prove two lexical imports were necessary'
    }
}
Invoke-NativeCase 'prebind-load-and-clang-only-never-prove-cross-import-activation' {
    foreach ($kind in @('triggerOnly', 'loadOnly', 'clangOnly', 'foreignTrigger')) {
        $bundle = New-NativeBundle $kind
        $result = Get-NativeAssessment $bundle
        Assert-NativeTrue (-not $result.overlayActivationObserved) "$kind is not sufficient"
        Assert-NativeTrue ($result.outcome -ceq 'import-succeeded-without-overlay-evidence') 'missing positive evidence is not proof of no overlay'
    }
    $clang = Read-NativeDiagnosticText $script:NativeFixture.diagnostics.clangOnly
    Assert-NativeTrue ($clang.loads[0].clangDependencyOverlay -and $clang.triggers.Count -eq 0) 'ordinary Clang overlay metadata stays distinct'
}
Invoke-NativeCase 'known-transitive-dependency-remarks-are-not-module-loads' {
    $text = ''
    foreach ($behavior in @('a required', 'an optional', 'an ignored')) {
        $text += "<unknown>:0: remark: 'Swift' has $behavior transitive dependency on 'SwiftShims' [transitive_dependency_behavior]`n"
    }
    $diagnostics = Read-NativeDiagnosticText ($text + $script:NativeFixture.diagnostics.positive)
    Assert-NativeTrue ($diagnostics.complete -and $diagnostics.dependencies.Count -eq 3) 'all emitted dependency behaviors have exact known grammar'
    Assert-NativeTrue ($diagnostics.loads.Count -eq 1 -and $diagnostics.triggers.Count -eq 1) 'dependency observations never become load or trigger evidence'
    $malformed = "<unknown>:0: remark: 'Swift' has the required transitive dependency on 'SwiftShims' [transitive_dependency_behavior]`n"
    Assert-NativeTrue (-not (Read-NativeDiagnosticText $malformed).complete) 'a known dependency ID does not accept a changed body grammar'
    $bundle = New-NativeBundle
    $bundle.diagnostics = Read-NativeDiagnosticText ("<unknown>:0: remark: 'Alpha' has a required transitive dependency on '_Alpha_Beta' [transitive_dependency_behavior]`n" + $script:NativeFixture.diagnostics.triggerOnly)
    $bundle.process = New-NativeProcess $bundle.diagnostics
    $result = Get-NativeAssessment $bundle
    Assert-NativeTrue ($result.triggerObserved -and -not $result.moduleLoadObserved -and -not $result.overlayActivationObserved) 'a dependency and a prebinding trigger are still not a module-load observation'
}
Invoke-NativeCase 'search-path-dump-exact-order-row-types-and-empty-sections' {
    $diagnostics = Read-NativeDiagnosticText $script:NativeFixture.diagnostics.positive
    Assert-NativeTrue ($diagnostics.searchPathDump.blocks -eq 1 -and $diagnostics.searchPathDump.completeBlocks -eq 1) 'source-defined path block is retained'
    Assert-NativeTrue ($diagnostics.searchPathDump.entries.Count -eq 5 -and $diagnostics.searchPathDump.entries[1].kind -ceq 'non-system') 'annotated path rows retain their category'
    Assert-NativeTrue ($null -eq $diagnostics.searchPathDump.entries[4].kind) 'implicit and runtime rows do not invent system annotations'
    $empty = "Module import search paths:`nFramework search paths:`nImplicit framework search paths:`nRuntime library import search paths:`n(End of search path lists.)`n"
    $diagnostics = Read-NativeDiagnosticText ($empty + $script:NativeFixture.diagnostics.positive) -OmitSearchDump
    Assert-NativeTrue ($diagnostics.complete -and $diagnostics.searchPathDump.entries.Count -eq 0) 'the native implementation permits empty sections'
    $tricky = $script:NativeFixture.searchPathDump.Replace('/SYNTHETIC/runtime', "remark: loaded module '_Alpha_Beta'; source: 'x', loaded: 'y' [module_loaded]")
    $diagnostics = Read-NativeDiagnosticText $tricky -OmitSearchDump
    Assert-NativeTrue ($diagnostics.loads.Count -eq 0) 'a path row is never reparsed as a module-load header'
}
Invoke-NativeCase 'search-path-dump-unknown-framing-truncation-and-absence' {
    foreach ($dump in @(
        $script:NativeFixture.searchPathDump.Replace('[1] (non-system)', '[3] (non-system)'),
        $script:NativeFixture.searchPathDump.Replace('(system)', '(SYSTEM)'),
        $script:NativeFixture.searchPathDump.Replace('Framework search paths:', 'Framework lookup paths:'),
        $script:NativeFixture.searchPathDump.Replace('  [0] /SYNTHETIC/toolchain', '[0] /SYNTHETIC/toolchain'),
        $script:NativeFixture.searchPathDump.Replace('(End of search path lists.)' + [char]10, ''),
        ($script:NativeFixture.searchPathDump + $script:NativeFixture.searchPathDump)
    )) {
        $diagnostics = Read-NativeDiagnosticText ($dump + $script:NativeFixture.diagnostics.positive) -OmitSearchDump
        Assert-NativeTrue (-not $diagnostics.complete) 'malformed or repeated native dump is incomplete'
    }
    $bundle = New-NativeBundle
    $bundle.diagnostics = Read-NativeDiagnosticText $script:NativeFixture.diagnostics.positive -OmitSearchDump
    $bundle.process = New-NativeProcess $bundle.diagnostics
    Assert-NativeTrue ((Get-NativeAssessment $bundle).stopLaterCommands) 'zero exit without the expected dump cannot qualify'
    $bundle = New-NativeBundle 'rejected'
    $bundle.diagnostics = Read-NativeDiagnosticText $script:NativeFixture.diagnostics.rejected -OmitSearchDump
    $bundle.process = New-NativeProcess $bundle.diagnostics 1
    Assert-NativeTrue ((Get-NativeAssessment $bundle).outcome -ceq 'compiler-rejected') 'a compiler can reject before dumping search paths'
}
Invoke-NativeCase 'diagnostic-header-anchors-identifiers-and-quoting' {
    $quoted = Read-NativeDiagnosticText $script:NativeFixture.diagnostics.quoted
    Assert-NativeTrue ($quoted.loads.Count -eq 0 -and $quoted.headers.Count -eq 1 -and $quoted.headers[0].severity -ceq 'error') 'quoted message is not reparsed as a load'
    foreach ($text in @(
        $script:NativeFixture.diagnostics.positive.Replace('[cross_import_added]', '[#cross_import_added]'),
        $script:NativeFixture.diagnostics.positive.Replace('[module_loaded]', '[module_loaded_v2]'),
        $script:NativeFixture.diagnostics.positive.Replace('loaded module', 'successfully loaded module'),
        $script:NativeFixture.diagnostics.positive.Replace('<unknown>:0: remark:', 'remark:'),
        ('gutter ' + $script:NativeFixture.diagnostics.positive),
        ($script:NativeFixture.diagnostics.positive + 'unknown preamble' + [char]10)
    )) {
        Assert-NativeTrue (-not (Read-NativeDiagnosticText $text).complete) 'new framing and unknown diagnostic IDs remain incomplete'
    }
}
Invoke-NativeCase 'diagnostic-source-binding-and-location-bounds' {
    foreach ($prefix in @('/SYNTHETIC/probes/probe.swift:1:8:', '/SYNTHETIC/probes/probe.swift:99:8:', '/SYNTHETIC/probes/probe.swift:4:999:', '/SYNTHETIC/probes/probe.swift:9223372036854775808:8:')) {
        $diag = Read-NativeDiagnosticText ($script:NativeFixture.diagnostics.triggerOnly.Replace('/SYNTHETIC/probes/probe.swift:4:8:', $prefix))
        Assert-NativeTrue (-not $diag.triggers[0].sourcePositionValid) 'out-of-template coordinates cannot establish trigger evidence'
    }
    $source = New-NativeSource
    $source.text += 'import _Alpha_Beta'
    $path = Write-NativeText 'source-mismatch-stderr.txt' $script:NativeFixture.diagnostics.positive
    Assert-NativeThrows { Read-SwiftUIOverlayProbeDiagnostics $path $script:NativeFixture.sourcePath $source } 'mutated fixed source is rejected'
}
Invoke-NativeCase 'diagnostic-encoding-and-budgets' {
    foreach ($text in @(([string][char]0xfeff + $script:NativeFixture.diagnostics.positive), ([string][char]27 + '[31mwarning'), "bad`rheader", ([string][char]0xfffd))) {
        Assert-NativeThrows { Read-NativeDiagnosticText $text } 'ambiguous encoding and control framing is rejected'
    }
    Assert-NativeThrows { Read-NativeDiagnosticText ('a' * (64KB + 1)) } 'line byte budget is fixed'
    Assert-NativeThrows { Read-NativeDiagnosticText ([string][char]10 * 32769) } 'physical-line budget is fixed'
    $path = Write-NativeRaw 'invalid-utf8-stderr.txt' ([byte[]]@(0xc3, 0x28))
    Assert-NativeThrows { Read-SwiftUIOverlayProbeDiagnostics $path $script:NativeFixture.sourcePath (New-NativeSource) } 'invalid UTF-8 is not replacement-decoded'
}

Invoke-NativeCase 'trace-v2-exact-schema-and-substituted-interface-path' {
    $trace = Read-NativeTraceValue $script:NativeFixture.trace
    Assert-NativeTrue ($trace.complete -and $trace.recordCount -eq 1) 'exact compact JSON trace is accepted'
    Assert-NativeTrue ($trace.document.version -is [long] -and $trace.document.languageMode -ceq '6') 'strict integer and Swift language spelling'
    Assert-NativeTrue ($trace.document.swiftmodulesDetailedInfo[2].isImportedDirectly) 'implicit overlay may be directly imported in native schema'
    Assert-NativeTrue ($trace.document.swiftmodulesDetailedInfo[2].path.EndsWith('.swiftinterface')) 'trace path is not assumed to be a binary path'
    $value = Copy-NativeValue $script:NativeFixture.trace
    $value.swiftmodulesDetailedInfo[2].isImportedDirectly = $false
    Assert-NativeTrue ((Read-NativeTraceValue $value).complete) 'direct import boolean is retained, not treated as lexical proof'
}
Invoke-NativeCase 'trace-unknown-fields-retained-but-ineligible' {
    foreach ($where in @('root', 'module', 'macro')) {
        $value = Copy-NativeValue $script:NativeFixture.trace
        if ($where -ceq 'root') { $value | Add-Member -NotePropertyName futureField -NotePropertyValue ([pscustomobject]@{ raw = 7 }) }
        elseif ($where -ceq 'module') { $value.swiftmodulesDetailedInfo[2] | Add-Member -NotePropertyName futureField -NotePropertyValue 'retained' }
        else { $value.swiftmacros = @([pscustomobject]@{ name = 'Macro'; path = '/SYNTHETIC/macro'; futureField = 'retained' }) }
        $read = Read-NativeTraceValue $value
        Assert-NativeTrue (-not $read.complete) 'unknown version-2 extension does not become accepted evidence'
        Assert-NativeTrue ($read.text.Contains('futureField')) 'unknown raw fields remain preserved'
    }
}
Invoke-NativeCase 'trace-context-types-lists-and-duplicates' {
    $mutations = @(
        { param($v) $v.version = '2' }, { param($v) $v.version = 3 },
        { param($v) $v.name = 'Other' }, { param($v) $v.arch = 'x86_64' },
        { param($v) $v.languageMode = '6.0' }, { param($v) $v.strictMemorySafety = 'false' },
        { param($v) $v.swiftmodulesDetailedInfo[0].isImportedDirectly = 'true' },
        { param($v) $v.swiftmodulesDetailedInfo[0].supportsLibraryEvolution = 1 },
        { param($v) $v.swiftmodulesDetailedInfo[0].strictMemorySafety = $null },
        { param($v) $v.swiftmodulesDetailedInfo[1].name = 'Alpha' },
        { param($v) $v.swiftmodules[0] = '/SYNTHETIC/wrong' },
        { param($v) $v.swiftmodules = @($v.swiftmodules[0]) },
        { param($v) $v.enabledLanguageFeatures = @('not a feature') },
        { param($v) $v.swiftmodulesDetailedInfo[2].path = '/SYNTHETIC/../outside' },
        { param($v) $v.swiftmacros = @([pscustomobject]@{ name = 'Macro'; path = '/SYNTHETIC/macro' }) }
    )
    foreach ($mutate in $mutations) {
        $value = Copy-NativeValue $script:NativeFixture.trace
        & $mutate $value
        Assert-NativeTrue (-not (Read-NativeTraceValue $value).complete) 'trace mismatch cannot qualify'
    }
    $value = Copy-NativeValue $script:NativeFixture.trace
    $value.PSObject.Properties.Remove('swiftmodules')
    Assert-NativeThrows { Read-NativeTraceValue $value } 'missing trace field is not defaulted'
    $value = Copy-NativeValue $script:NativeFixture.trace
    $value.swiftmodules = 'not an array'
    Assert-NativeThrows { Read-NativeTraceValue $value } 'array type is mandatory'
}
Invoke-NativeCase 'trace-strict-json-byte-framing' {
    $compact = ConvertTo-Json -InputObject $script:NativeFixture.trace -Compress -Depth 40
    foreach ($text in @(
        $compact.Replace('"version":2', '"version":2,"version":2'),
        $compact.Replace('"version":2', '"version":2,"Version":2'),
        $compact.Replace('"version":2', '"version":2,"\u0076ersion":2'),
        ($compact + [char]10 + $compact + [char]10),
        ($compact.Substring(0, $compact.Length - 1)),
        ('/*SYNTHETIC*/' + $compact),
        $compact.Replace('"version":2,', '"version":2,,')
    )) { Assert-NativeThrows { Read-NativeTraceText $text } 'strict raw JSON refuses duplicates and ambiguous syntax' }
    Assert-NativeTrue (-not (Read-NativeTraceText $compact).complete) 'append record needs final LF'
    Assert-NativeTrue (-not (Read-NativeTraceText ($compact + "`r`n")).complete) 'native trace profile is literal LF'
    Assert-NativeTrue (-not (Read-NativeTraceText ((ConvertTo-Json -InputObject $script:NativeFixture.trace -Depth 40) + [char]10)).complete) 'pretty JSON is not native trace framing'
    Assert-NativeThrows { Read-NativeTraceText ([string][char]0xfeff + $compact + [char]10) } 'BOM rejected'
    $path = Write-NativeRaw 'invalid-utf8-trace.json' ([byte[]]@(0xc3, 0x28))
    Assert-NativeThrows { Read-SwiftUIOverlayProbeTrace $path ('SWUIOverlayProbe_' + $script:NativeFixture.requestId) 'arm64-apple-macosx26.5' } 'invalid trace UTF-8 rejected'
}

Invoke-NativeCase 'normal-process-zero-one-and-not-run' {
    $bundle = New-NativeBundle
    $result = Get-SwiftUIOverlayProbeProcessOutcome 'confirmed-started' $bundle.process
    Assert-NativeTrue ($result.outcome -ceq 'compiler-succeeded' -and -not $result.stopLaterCommands) 'natural zero and full streams are complete'
    $bundle.process.exitCode = 1
    $result = Get-SwiftUIOverlayProbeProcessOutcome 'confirmed-started' $bundle.process
    Assert-NativeTrue ($result.outcome -ceq 'compiler-exited-one' -and -not $result.descendantClosureRequired) 'natural one is a compiler result, not termination uncertainty'
    $result = Get-SwiftUIOverlayProbeProcessOutcome 'not-run' $null
    Assert-NativeTrue ($result.outcome -ceq 'not-run' -and -not $result.stopLaterCommands) 'unrun has no process receipt'
    Assert-NativeThrows { Get-SwiftUIOverlayProbeProcessOutcome 'not-run' $bundle.process } 'unrun cannot carry a launched-process observation'
    $bundle = New-NativeBundle
    $bundle.process | Add-Member -NotePropertyName parentHasExited -NotePropertyValue $true
    $result = Get-SwiftUIOverlayProbeProcessOutcome 'confirmed-started' $bundle.process
    Assert-NativeTrue ($null -eq $result.descendantsClosed) 'parent exit is not descendant closure'
    $bundle.process.descendantsClosed = $false
    $result = Get-SwiftUIOverlayProbeProcessOutcome 'confirmed-started' $bundle.process
    Assert-NativeTrue ($result.descendantsClosed -eq $false -and -not $result.descendantClosureRequired -and $result.descendantClosureStatus -ceq 'not-established') 'ordinary explicit unknown closure stays separate from uncertainty triggers'
}
Invoke-NativeCase 'uncertain-process-records-stop-every-later-launch' {
    $mutations = @(
        { param($p) $p.timedOut = $true }, { param($p) $p.outputLimitExceeded = $true },
        { param($p) $p.terminationRequested = $true }, { param($p) $p.terminationCompleted = $false },
        { param($p) $p.allRedirectedStreamsClosed = $false }, { param($p) $p.exitCode = $null },
        { param($p) $p.exitCode = 137 }, { param($p) $p.error = 'SYNTHETIC drain failure' },
        { param($p) $p.cleanupErrors = @('SYNTHETIC cleanup failure') }, { param($p) $p.observedDiscardedBytes = 1 }
    )
    foreach ($mutate in $mutations) {
        $bundle = New-NativeBundle
        & $mutate $bundle.process
        $result = Get-NativeAssessment $bundle
        Assert-NativeTrue ($result.stopLaterCommands -and $result.descendantClosureRequired -and -not $result.overlayActivationObserved) 'uncertain outcome cannot authorize later commands or positive evidence'
        $bundle.process.descendantsClosed = $true
        $result = Get-NativeAssessment $bundle
        Assert-NativeTrue ($result.stopLaterCommands) 'v1 has no resume mode even with later caller-reported closure'
    }
    $result = Get-SwiftUIOverlayProbeProcessOutcome 'unknown-after-invocation' $null
    Assert-NativeTrue ($result.outcome -ceq 'launch-uncertain' -and $result.stopLaterCommands -and $result.descendantClosureRequired) 'unknown launch has uncertain closure'
    $bundle = New-NativeBundle
    $bundle.process.processStarted = $false; $bundle.process.exitCode = $null
    $result = Get-SwiftUIOverlayProbeProcessOutcome 'confirmed-not-started' $bundle.process
    Assert-NativeTrue ($result.outcome -ceq 'launch-failed' -and $result.stopLaterCommands -and -not $result.descendantClosureRequired) 'confirmed nonlaunch is distinct from uncertain launch'
}
Invoke-NativeCase 'process-contradictions-types-and-budgets' {
    foreach ($field in @('processStarted', 'timedOut', 'outputLimitExceeded', 'terminationRequested', 'terminationCompleted', 'allRedirectedStreamsClosed')) {
        $bundle = New-NativeBundle
        $bundle.process.$field = 'false'
        Assert-NativeThrows { Get-SwiftUIOverlayProbeProcessOutcome 'confirmed-started' $bundle.process } 'string booleans cannot produce clean native outcomes'
    }
    foreach ($field in @('stdoutBytes', 'stderrBytes', 'observedDiscardedBytes')) {
        $bundle = New-NativeBundle; $bundle.process.$field = -1
        Assert-NativeThrows { Get-SwiftUIOverlayProbeProcessOutcome 'confirmed-started' $bundle.process } 'negative count rejected'
    }
    $bundle = New-NativeBundle; $bundle.process.stderrSha256 = 'wrong'
    Assert-NativeThrows { Get-SwiftUIOverlayProbeProcessOutcome 'confirmed-started' $bundle.process } 'clean receipt requires exact hashes'
    $bundle = New-NativeBundle; $bundle.process.stdoutBytes = 8MB
    Assert-NativeThrows { Get-SwiftUIOverlayProbeProcessOutcome 'confirmed-started' $bundle.process } 'combined streams obey fixed budget'
    $bundle = New-NativeBundle; $bundle.process.processStarted = $false
    Assert-NativeThrows { Get-SwiftUIOverlayProbeProcessOutcome 'confirmed-started' $bundle.process } 'launch-state contradiction rejected'
    $bundle = New-NativeBundle
    Assert-NativeThrows { Get-SwiftUIOverlayProbeProcessOutcome 'confirmed-not-started' $bundle.process } 'nonlaunch-state contradiction rejected'
}
Invoke-NativeCase 'compiler-rejection-is-not-successful-overlay-load' {
    $bundle = New-NativeBundle 'rejected'
    $bundle.process.exitCode = 1; $bundle.trace = $null
    $result = Get-NativeAssessment $bundle
    Assert-NativeTrue ($result.outcome -ceq 'compiler-rejected' -and -not $result.stopLaterCommands -and -not $result.overlayActivationObserved) 'complete ordinary compiler rejection remains distinct'
    $bundle.process.exitCode = 0
    $result = Get-NativeAssessment $bundle
    Assert-NativeTrue ($result.outcome -ceq 'evidence-incomplete' -and $result.stopLaterCommands) 'error with zero exit is contradictory'
    $bundle = New-NativeBundle; $bundle.process.exitCode = 1
    Assert-NativeTrue ((Get-NativeAssessment $bundle).stopLaterCommands) 'exit one without a complete error diagnostic is uncertain evidence'
}
Invoke-NativeCase 'missing-evidence-and-unobserved-paths-fail-closed' {
    $bundle = New-NativeBundle; $bundle.diagnostics = $null
    Assert-NativeTrue ((Get-NativeAssessment $bundle).stopLaterCommands) 'missing raw diagnostics stop collection'
    $bundle = New-NativeBundle; $bundle.trace = $null
    Assert-NativeTrue ((Get-NativeAssessment $bundle).stopLaterCommands) 'missing trace stops collection'
    foreach ($status in @('unobserved', 'not-authorized', 'failed')) {
        $bundle = New-NativeBundle; $bundle.pathObservations[1].status = $status
        $result = Get-NativeAssessment $bundle
        Assert-NativeTrue (-not $result.loadedFileIdentitiesRecorded -and -not $result.overlayActivationObserved -and $result.stopLaterCommands) 'unobserved module identities do not qualify'
    }
    $bundle = New-NativeBundle; $bundle.pathObservations = @()
    Assert-NativeTrue ((Get-NativeAssessment $bundle).stopLaterCommands) 'missing path observations cannot be inferred from trace paths'
    $bundle = New-NativeBundle; $bundle.pathObservations += $bundle.pathObservations[0]
    Assert-NativeThrows { Get-NativeAssessment $bundle } 'duplicate path receipts are ambiguous'
}
Invoke-NativeCase 'module-file-observation-conflicts-types-and-direct-binary-path' {
    $bundle = New-NativeBundle
    $bundle.pathObservations[1].canonicalPath = $bundle.pathObservations[0].canonicalPath
    Assert-NativeThrows { Get-NativeAssessment $bundle } 'one canonical file cannot carry incompatible observed identities'
    foreach ($value in @('127', 0, -1, ([long]1GB + 1), $true)) {
        $bundle = New-NativeBundle; $bundle.pathObservations[1].bytes = $value
        Assert-NativeThrows { Get-NativeAssessment $bundle } 'loaded-file byte observation must be bounded and typed'
    }
    $bundle = New-NativeBundle
    $text = $script:NativeFixture.diagnostics.positive.Replace('/SYNTHETIC/sdk/_Alpha_Beta.swiftinterface', '/SYNTHETIC/cache/_Alpha_Beta.swiftmodule')
    $bundle.diagnostics = Read-NativeDiagnosticText $text
    $bundle.process = New-NativeProcess $bundle.diagnostics
    $traceValue = Copy-NativeValue $script:NativeFixture.trace
    $traceValue.swiftmodules[2] = '/SYNTHETIC/cache/_Alpha_Beta.swiftmodule'
    $traceValue.swiftmodulesDetailedInfo[2].path = '/SYNTHETIC/cache/_Alpha_Beta.swiftmodule'
    $bundle.trace = Read-NativeTraceValue $traceValue
    $bundle.pathObservations = @($bundle.pathObservations[1])
    Assert-NativeTrue ((Get-NativeAssessment $bundle).overlayActivationObserved) 'binary-only source and loaded identity can use one exact receipt'
}
Invoke-NativeCase 'ambiguous-records-loads-and-triggers-remain-visible' {
    $bundle = New-NativeBundle
    $bundle.candidateRecordIds += ('f' * 64)
    $result = Get-NativeAssessment $bundle
    Assert-NativeTrue ($result.occurrenceAttribution -ceq 'ambiguous-census-occurrences' -and -not $result.definitionOccurrenceTriggered) 'multiple census definitions cannot be assigned a winner'
    Assert-NativeTrue ($result.overlayActivationObserved) 'module activation is retained separately from occurrence attribution'
    $bundle.candidateRecordIds += $bundle.candidateRecordIds[0]
    Assert-NativeThrows { Get-NativeAssessment $bundle } 'duplicate record IDs are invalid'
    foreach ($kind in @('triggerOnly', 'loadOnly')) {
        $bundle = New-NativeBundle
        $bundle.diagnostics = Read-NativeDiagnosticText ($script:NativeFixture.diagnostics.positive + $script:NativeFixture.diagnostics.$kind)
        $bundle.process = New-NativeProcess $bundle.diagnostics
        $result = Get-NativeAssessment $bundle
        Assert-NativeTrue ($result.stopLaterCommands -and -not $result.overlayActivationObserved) 'multiple matching native remarks are not assigned arbitrarily'
    }
}
Invoke-NativeCase 'raw-replay-ignores-forged-derived-objects' {
    $bundle = New-NativeBundle 'loadOnly'
    $positive = Read-NativeDiagnosticText $script:NativeFixture.diagnostics.positive
    $bundle.diagnostics.triggers = $positive.triggers
    $result = Get-NativeAssessment $bundle
    Assert-NativeTrue (-not $result.triggerObserved -and -not $result.overlayActivationObserved) 'mutated diagnostic summaries cannot synthesize a raw remark'
    $bundle = New-NativeBundle
    $traceValue = Copy-NativeValue $script:NativeFixture.trace
    $traceValue.swiftmodulesDetailedInfo = @($traceValue.swiftmodulesDetailedInfo[0], $traceValue.swiftmodulesDetailedInfo[1])
    $traceValue.swiftmodules = @($traceValue.swiftmodules[0], $traceValue.swiftmodules[1])
    $bundle.trace = Read-NativeTraceValue $traceValue
    $bundle.trace.document.swiftmodulesDetailedInfo = $script:NativeFixture.trace.swiftmodulesDetailedInfo
    $result = Get-NativeAssessment $bundle
    Assert-NativeTrue (-not $result.traceMembershipObserved -and -not $result.overlayActivationObserved) 'mutated trace objects cannot synthesize raw membership'
}
Invoke-NativeCase 'reader-envelope-scalar-coercion-is-rejected' {
    foreach ($field in @('sha256', 'sourceSha256', 'bytes', 'profile', 'control', 'declaringModule', 'bystandingModule', 'sourcePath')) {
        $bundle = New-NativeBundle; $bundle.diagnostics.$field = $true
        Assert-NativeThrows { Get-NativeAssessment $bundle } 'diagnostic envelope cannot coerce a Boolean into identity or context'
    }
    foreach ($field in @('sha256', 'bytes', 'profile', 'target', 'expectedModuleName', 'recordCount')) {
        $bundle = New-NativeBundle; $bundle.trace.$field = $true
        Assert-NativeThrows { Get-NativeAssessment $bundle } 'trace envelope cannot coerce a Boolean into identity or context'
    }
}
Invoke-NativeCase 'raw-replay-rejects-forged-completeness-flags' {
    $bundle = New-NativeBundle
    $bundle.diagnostics = Read-NativeDiagnosticText ($script:NativeFixture.diagnostics.positive + "<unknown>:0: remark: a future native diagnostic [future_module_remark]`n")
    $bundle.process = New-NativeProcess $bundle.diagnostics
    Assert-NativeTrue (-not $bundle.diagnostics.complete) 'invalid raw diagnostic is initially incomplete'
    $bundle.diagnostics.complete = $true; $bundle.diagnostics.issues = @()
    $result = Get-NativeAssessment $bundle
    Assert-NativeTrue ($result.stopLaterCommands -and -not $result.overlayActivationObserved) 'replayed diagnostic grammar overrides forged completeness flags'
    $bundle = New-NativeBundle
    $value = Copy-NativeValue $script:NativeFixture.trace
    $value | Add-Member -NotePropertyName unrecognizedNativeField -NotePropertyValue 'preserved'
    $bundle.trace = Read-NativeTraceValue $value
    Assert-NativeTrue (-not $bundle.trace.complete) 'invalid raw trace is initially incomplete'
    $bundle.trace.complete = $true; $bundle.trace.issues = @()
    $result = Get-NativeAssessment $bundle
    Assert-NativeTrue ($result.stopLaterCommands -and -not $result.overlayActivationObserved) 'replayed trace schema overrides forged completeness flags'
}
Invoke-NativeCase 'artifact-changes-stream-hashes-and-context-mismatches' {
    $bundle = New-NativeBundle
    [IO.File]::WriteAllText($bundle.diagnostics.path, $script:NativeFixture.diagnostics.loadOnly, $script:NativeUtf8)
    $result = Get-NativeAssessment $bundle
    Assert-NativeTrue ($result.stopLaterCommands -and -not $result.overlayActivationObserved) 'changed diagnostic bytes are rehashed'
    $bundle = New-NativeBundle
    [IO.File]::WriteAllText($bundle.trace.path, ($bundle.trace.text.Replace('"arch":"arm64"', '"arch":"x86_64"')), $script:NativeUtf8)
    Assert-NativeTrue ((Get-NativeAssessment $bundle).stopLaterCommands) 'changed trace bytes and actual context are rechecked'
    $bundle = New-NativeBundle; $bundle.process.stderrSha256 = 'f' * 64
    Assert-NativeTrue ((Get-NativeAssessment $bundle).stopLaterCommands) 'process stderr identity must match raw bytes'
    $bundle = New-NativeBundle; $bundle.process.stdoutBytes = 1; $bundle.process.stdoutSha256 = 'f' * 64
    Assert-NativeTrue ((Get-NativeAssessment $bundle).stopLaterCommands) 'frontend stdout must match frozen empty-stream policy'
    $bundle = New-NativeBundle; $bundle.requestId = 'f' * 64
    Assert-NativeTrue ((Get-NativeAssessment $bundle).stopLaterCommands) 'actual trace module name must bind complete request ID'
    $bundle.trace.expectedModuleName = 'SWUIOverlayProbe_' + $bundle.requestId
    Assert-NativeTrue ((Get-NativeAssessment $bundle).stopLaterCommands) 'changing both request and parsed trace labels cannot relabel the raw trace name'
    $bundle = New-NativeBundle; $bundle.trace.sha256 = 'wrong'
    Assert-NativeThrows { Get-NativeAssessment $bundle } 'trace hash type and spelling cannot be fabricated'
}

$failed = @($script:NativeCases | Where-Object { $_.outcome -ceq 'failed' })
$report = [pscustomobject][ordered]@{
    schemaVersion = 1; evidenceKind = 'SYNTHETIC-TEST-REPORT-NOT-NATIVE-CAPTURE'
    profile = $script:NativePolicy.profile; publicSourceCommit = $script:NativePolicy.publicSourceCommit
    nativeCommandsExecuted = $false; swiftPMExecuted = $false; sdkPathsOpened = $false
    nativeCompilerObserved = $false; releaseQualified = $false
    fixtureSha256 = $fixtureRead.sha256
    helperSha256 = (Get-SwiftUIStateObjectFileHash (Join-Path $RepositoryRoot 'scripts/swiftui-overlay-probe-native.ps1') -MaxBytes 1MB).sha256
    testScriptSha256 = (Get-SwiftUIStateObjectFileHash $PSCommandPath -MaxBytes 1MB).sha256
    assertions = $script:NativeAssertions; cases = $script:NativeCases.Count; failedCases = $failed.Count
    caseResults = $script:NativeCases.ToArray()
}
$reportPath = Write-NativeText 'report.json' ((ConvertTo-Json -InputObject $report -Depth 40) + [char]10)
$lines = @('SYNTHETIC TESTS ONLY: no Swift/compiler/native child or SDK access.', "Cases: $($report.cases); assertions: $($report.assertions); failed cases: $($report.failedCases)")
foreach ($case in $script:NativeCases) { $lines += "$($case.outcome): $($case.name) ($($case.assertions) assertions)"; if ($case.error) { $lines += $case.error; $lines += $case.errorLocation } }
$logPath = Write-NativeText 'test-log.txt' (($lines -join [char]10) + [char]10)
Write-Output "Synthetic native-parser cases=$($report.cases) assertions=$($report.assertions) failed=$($report.failedCases)"
Write-Output "Report: $reportPath"
Write-Output "Report SHA256: $((Get-SwiftUIStateObjectFileHash $reportPath -MaxBytes 1MB).sha256)"
Write-Output "Log: $logPath"
Write-Output "Log SHA256: $((Get-SwiftUIStateObjectFileHash $logPath -MaxBytes 1MB).sha256)"
if ($failed.Count -gt 0) { throw "Synthetic native-parser tests failed: $($failed.name -join ', ')" }
