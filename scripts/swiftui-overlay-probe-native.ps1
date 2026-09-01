# Pure Stage B command construction and offline evidence interpretation.
# Importing this helper never launches a process, opens an SDK path, or writes a file.
# Existing bounded, strict JSON helpers are reused without changing their policy.
. (Join-Path $PSScriptRoot 'swiftui-stateobject-isolation-common.ps1')

# This profile describes public Swift source, not observed Apple compiler behavior.
# https://github.com/swiftlang/swift/tree/aa782beb23b8bd83bd16fca831532a05dd6cea39
# Options.td:455-473; FrontendOptions.td:191-194; DiagnosticsSema.def:1286-1294;
# LoadedModuleTrace.cpp:50-127,576-705,765-869; CrossImport/module-trace.swift:6-13.
function Get-SwiftUIOverlayProbeNativePolicy {
    return [pscustomobject][ordered]@{
        profile = 'swift-6.3-cross-import-v1'
        publicSourceCommit = 'aa782beb23b8bd83bd16fca831532a05dd6cea39'
        sdkPath = '/Applications/Xcode_26.6.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk'
        targets = @('arm64-apple-macosx26.5', 'x86_64-apple-macosx26.5')
        controls = @('owner-only', 'bystander-only', 'owner-bystander', 'bystander-owner')
        cxxModes = @('off', 'default')
        languageMode = '6'
        traceVersion = 2
        maximumEvidenceBytes = [long]8MB
        maximumLineBytes = 64KB
        maximumDiagnosticLines = 32768
        maximumModuleEntries = 4096
        maximumLoadedFileBytes = [long]1GB
        allowedReexportedModules = @('SwiftUI', 'SwiftUICore')
        nativeCompilerObserved = $false
        releaseQualified = $false
    }
}

function Assert-SwiftUIOverlayProbeNativeIdentifier {
    param([Parameter(Mandatory)]$Value)
    if ($Value -isnot [string] -or $Value.Length -gt 128 -or
        $Value -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*\z' -or $Value -ceq '_') {
        throw 'Unsupported module identifier; this profile accepts bounded ASCII identifiers, not source fragments.'
    }
}

function Assert-SwiftUIOverlayProbeHash {
    param([Parameter(Mandatory)]$Value)
    if ($Value -isnot [string] -or $Value -cnotmatch '\A[0-9a-f]{64}\z') { throw 'A lowercase SHA-256 identity is required.' }
}

function Assert-SwiftUIOverlayProbeNativePath {
    param([Parameter(Mandatory)]$Value)
    # Lexical validation only. The collector must separately authorize and resolve
    # the physical path; Windows replay must not reinterpret a recorded POSIX path.
    if ($Value -isnot [string] -or $Value.Length -gt 4096 -or
        -not $Value.StartsWith('/', [StringComparison]::Ordinal) -or $Value -ceq '/' -or
        $Value -match '[\x00-\x1f\x7f\x27\x5c\ufffd\ufeff]' -or $Value.Contains('//') -or
        $Value.EndsWith('/', [StringComparison]::Ordinal) -or $Value -match '/\.{1,2}(?:/|$)') {
        throw 'A canonical, unambiguous absolute POSIX path is required by this profile.'
    }
}

function Assert-SwiftUIOverlayProbeContext {
    param([Parameter(Mandatory)]$Target, [Parameter(Mandatory)]$CxxMode)
    $policy = Get-SwiftUIOverlayProbeNativePolicy
    if ($Target -isnot [string] -or $Target -cnotin $policy.targets -or
        $CxxMode -isnot [string] -or $CxxMode -cnotin $policy.cxxModes) {
        throw 'Only the two pinned desktop targets and explicit off/default C++ contexts are supported.'
    }
}

function Assert-SwiftUIOverlayProbeObject {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string[]]$Required)
    if ($Value -isnot [pscustomobject]) { throw 'An evidence object is required.' }
    $names = @($Value.PSObject.Properties.Name)
    foreach ($name in $Required) {
        if ($name -cnotin $names) { throw "Missing evidence field '$name'." }
    }
}

function New-SwiftUIOverlayProbeSource {
    param([Parameter(Mandatory)]$DeclaringModule, [Parameter(Mandatory)]$BystandingModule,
        [Parameter(Mandatory)]$Control)
    Assert-SwiftUIOverlayProbeNativeIdentifier $DeclaringModule
    Assert-SwiftUIOverlayProbeNativeIdentifier $BystandingModule
    if ($DeclaringModule -ceq $BystandingModule) { throw 'Self-cross-import probes are unsupported, not silently discarded.' }
    $policy = Get-SwiftUIOverlayProbeNativePolicy
    if ($Control -isnot [string] -or $Control -cnotin $policy.controls) { throw 'Unknown import control.' }
    $imports = switch -CaseSensitive ($Control) {
        'owner-only' { ,@($DeclaringModule) }
        'bystander-only' { ,@($BystandingModule) }
        'owner-bystander' { ,@($DeclaringModule, $BystandingModule) }
        'bystander-owner' { ,@($BystandingModule, $DeclaringModule) }
    }
    $lines = @('// SwiftUI overlay import probe: swift-6.3-cross-import-v1.',
        '// Compilation records imports only; it does not qualify API or runtime behavior.')
    foreach ($module in $imports) {
        # Escape every identifier, including Swift keywords, without accepting any
        # caller-provided backtick, whitespace, punctuation, or source statement.
        $lines += ('import ' + [char]96 + $module + [char]96)
    }
    $text = ($lines -join "`n") + "`n"
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $bytes = $utf8.GetBytes($text)
    return [pscustomobject][ordered]@{
        profile = $policy.profile; control = $Control
        declaringModule = $DeclaringModule; bystandingModule = $BystandingModule
        imports = @($imports); text = $text; bytes = [long]$bytes.Length
        sha256 = Get-SwiftUIStateObjectBytesSHA256 $bytes
        lineByteLengths = @($lines | ForEach-Object { $utf8.GetByteCount($_) })
    }
}

function New-SwiftUIOverlayProbeCompilerArguments {
    param([Parameter(Mandatory)]$SDKPath, [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)]$CxxMode, [Parameter(Mandatory)]$CachePath,
        [Parameter(Mandatory)]$ModuleName, [Parameter(Mandatory)]$TracePath,
        [Parameter(Mandatory)]$SourcePath)
    Assert-SwiftUIOverlayProbeContext $Target $CxxMode
    $policy = Get-SwiftUIOverlayProbeNativePolicy
    if ($SDKPath -cne $policy.sdkPath) { throw 'The SDK path differs from the pinned Stage B profile.' }
    foreach ($path in @($SDKPath, $CachePath, $TracePath, $SourcePath)) { Assert-SwiftUIOverlayProbeNativePath $path }
    if ($ModuleName -isnot [string] -or $ModuleName -cnotmatch '\ASWUIOverlayProbe_[0-9a-f]{64}\z') { throw 'The probe module name must bind the complete request ID.' }
    if ($CachePath -ceq $TracePath -or $CachePath -ceq $SourcePath -or $TracePath -ceq $SourcePath) { throw 'Probe input, trace and cache paths must be distinct.' }
    return ,@('-typecheck', '-parse-as-library', '-sdk', $SDKPath, '-target', $Target,
        '-swift-version', '6', '-module-cache-path', $CachePath, '-module-name', $ModuleName,
        "-cxx-interoperability-mode=$CxxMode", '-enable-cross-import-overlays',
        '-Rcross-import', '-Rmodule-loading', '-debug-diagnostic-names',
        '-diagnostic-style', 'llvm', '-no-color-diagnostics',
        '-emit-loaded-module-trace-path', $TracePath, $SourcePath)
}

function New-SwiftUIOverlayProbeExtractorArguments {
    param([Parameter(Mandatory)]$OverlayModule, [Parameter(Mandatory)]$SDKPath,
        [Parameter(Mandatory)]$Target, [Parameter(Mandatory)]$CxxMode,
        [Parameter(Mandatory)]$CachePath, [Parameter(Mandatory)]$OutputDirectory)
    Assert-SwiftUIOverlayProbeNativeIdentifier $OverlayModule
    Assert-SwiftUIOverlayProbeContext $Target $CxxMode
    $policy = Get-SwiftUIOverlayProbeNativePolicy
    if ($SDKPath -cne $policy.sdkPath) { throw 'The SDK path differs from the pinned Stage B profile.' }
    foreach ($path in @($SDKPath, $CachePath, $OutputDirectory)) { Assert-SwiftUIOverlayProbeNativePath $path }
    if ($CachePath -ceq $OutputDirectory) { throw 'Extraction cache and graph output must be distinct.' }
    # O is the requested main module. Adding declaring/bystanding modules to this
    # allowlist would broaden re-export collection. Preserve the baseline list.
    return ,@('-module-name', $OverlayModule, '-sdk', $SDKPath, '-target', $Target,
        '-swift-version', '6', "-cxx-interoperability-mode=$CxxMode", '-module-cache-path', $CachePath,
        '-minimum-access-level', 'public', '-emit-extension-block-symbols',
        '-experimental-allowed-reexported-modules=SwiftUI,SwiftUICore', '-v', '-pretty-print',
        '-output-dir', $OutputDirectory)
}

function Read-SwiftUIOverlayProbeDiagnostics {
    param([Parameter(Mandatory)][string]$StderrPath, [Parameter(Mandatory)]$ExpectedSourcePath,
        [Parameter(Mandatory)]$SourceRecord)
    Assert-SwiftUIOverlayProbeNativePath $ExpectedSourcePath
    Assert-SwiftUIOverlayProbeObject $SourceRecord @('control', 'declaringModule', 'bystandingModule', 'text', 'sha256', 'bytes')
    $source = New-SwiftUIOverlayProbeSource $SourceRecord.declaringModule $SourceRecord.bystandingModule $SourceRecord.control
    if ($source.text -cne $SourceRecord.text -or $source.sha256 -cne $SourceRecord.sha256 -or $source.bytes -ne $SourceRecord.bytes) { throw 'The diagnostic source differs from the fixed import template.' }
    $policy = Get-SwiftUIOverlayProbeNativePolicy
    $read = Read-SwiftUIStateObjectBoundedBytes $StderrPath -MaxBytes $policy.maximumEvidenceBytes
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $text = $utf8.GetString($read.rawBytes)
    if ($text -match '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\ufeff\ufffd]' -or $text -match '\r(?!\n)') { throw 'Diagnostic framing must be strict UTF-8 without control escapes or a BOM.' }
    $issues = [Collections.Generic.List[string]]::new()
    $headers = [Collections.Generic.List[object]]::new()
    $otherLines = [Collections.Generic.List[object]]::new()
    $triggers = [Collections.Generic.List[object]]::new()
    $loads = [Collections.Generic.List[object]]::new()
    $dependencies = [Collections.Generic.List[object]]::new()
    $searchHeadings = @('Module import search paths:', 'Framework search paths:',
        'Implicit framework search paths:', 'Runtime library import search paths:')
    $searchEntries = [Collections.Generic.List[object]]::new()
    $searchRawLines = [Collections.Generic.List[object]]::new()
    $searchState = -1; $searchIndex = 0; $searchBlocks = 0; $searchCompleteBlocks = 0
    $physicalLines = [regex]::Split($text, '\r\n|\n')
    if ($physicalLines.Count -gt $policy.maximumDiagnosticLines) { throw 'The diagnostic stream exceeds the fixed physical-line budget.' }
    $sourceLines = $source.text.Split([char]10)
    $rawLineNumber = 0
    foreach ($line in $physicalLines) {
        $rawLineNumber++
        if ($line.Length -eq 0) {
            if ($searchState -ge 0) { $issues.Add("empty-search-path-line:$rawLineNumber") }
            continue
        }
        if ($utf8.GetByteCount($line) -gt $policy.maximumLineBytes) { throw 'A diagnostic line exceeds the fixed byte budget.' }
        # Frontend.cpp:611-615 writes this exact non-diagnostic block to stderr
        # under -Rmodule-loading. SearchPathOptions.cpp:107-132 defines its rows.
        if ($searchState -lt 0 -and $line -ceq $searchHeadings[0]) {
            $searchState = 0; $searchIndex = 0; $searchBlocks++
            if ($searchBlocks -gt 1) { $issues.Add('multiple-search-path-dumps') }
            $searchRawLines.Add([pscustomobject]@{ rawLineNumber = $rawLineNumber; text = $line })
            continue
        }
        if ($searchState -ge 0) {
            $searchRawLines.Add([pscustomobject]@{ rawLineNumber = $rawLineNumber; text = $line })
            if ($searchState -lt 3 -and $line -ceq $searchHeadings[$searchState + 1]) { $searchState++; $searchIndex = 0; continue }
            if ($searchState -eq 3 -and $line -ceq '(End of search path lists.)') { $searchState = -1; $searchCompleteBlocks++; continue }
            $pattern = if ($searchState -lt 2) { '\A  \[(?<index>0|[1-9][0-9]*)\] \((?<kind>system|non-system)\) (?<path>[^\r\n]+)\z' }
                else { '\A  \[(?<index>0|[1-9][0-9]*)\] (?<path>[^\r\n]+)\z' }
            $row = [regex]::Match($line, $pattern)
            $rowIndex = [long]0
            if (-not $row.Success -or -not [long]::TryParse($row.Groups['index'].Value, [ref]$rowIndex) -or $rowIndex -ne $searchIndex) {
                $issues.Add("unrecognized-search-path-line:$rawLineNumber")
                continue
            }
            $searchEntries.Add([pscustomobject]@{ rawLineNumber = $rawLineNumber; section = $searchHeadings[$searchState]
                index = $rowIndex; kind = $(if ($searchState -lt 2) { $row.Groups['kind'].Value } else { $null })
                path = $row.Groups['path'].Value })
            $searchIndex++
            if ($searchEntries.Count -gt $policy.maximumModuleEntries) { throw 'Search-path diagnostics exceed the fixed row budget.' }
            continue
        }
        # Parse only complete physical headers; never reparse a quoted message,
        # source echo, or gutter as an independent diagnostic.
        $header = [regex]::Match($line, '\A(?:(?<path>/[^\r\n]*?):(?<line>[1-9][0-9]*):(?<column>[1-9][0-9]*): |(?<unknown><unknown>):0: )(?<severity>remark|warning|error|note): (?<message>.*)\z')
        if (-not $header.Success) {
            $isEcho = $line -cin $sourceLines -or $line -cmatch '\A[ \t]*[\^~]+[ \t]*\z'
            $otherLines.Add([pscustomobject]@{ rawLineNumber = $rawLineNumber; text = $line; sourceEcho = $isEcho })
            if (-not $isEcho) { $issues.Add("unrecognized-diagnostic-line:$rawLineNumber") }
            continue
        }
        $message = $header.Groups['message'].Value
        $idMatch = [regex]::Match($message, ' \[(?<id>[A-Za-z_][A-Za-z0-9_]*)\]\z')
        $identifier = $null
        if ($idMatch.Success) {
            $identifier = $idMatch.Groups['id'].Value
            $message = $message.Substring(0, $idMatch.Index)
        }
        $path = $null; $sourceLine = $null; $column = $null; $locationValid = $false
        if ($header.Groups['path'].Success) {
            $path = $header.Groups['path'].Value
            $sourceLineValue = [long]0; $columnValue = [long]0
            if ([long]::TryParse($header.Groups['line'].Value, [ref]$sourceLineValue) -and
                [long]::TryParse($header.Groups['column'].Value, [ref]$columnValue)) {
                $sourceLine = $sourceLineValue; $column = $columnValue
                $locationValid = $path -ceq $ExpectedSourcePath -and $sourceLine -le $source.lineByteLengths.Count -and
                    $column -le ([long]$source.lineByteLengths[[int]$sourceLine - 1] + 1)
            }
        }
        $entry = [pscustomobject][ordered]@{
            rawLineNumber = $rawLineNumber; text = $line; severity = $header.Groups['severity'].Value
            identifier = $identifier; message = $message; path = $path; line = $sourceLine; column = $column
            sourcePositionValid = $locationValid
        }
        $headers.Add($entry)
        if ($entry.severity -ceq 'remark' -and $identifier -ceq 'cross_import_added') {
            $match = [regex]::Match($message, "\Aimport of '(?<owner>[A-Za-z_][A-Za-z0-9_]*)' and '(?<bystander>[A-Za-z_][A-Za-z0-9_]*)' triggered a cross-import of '(?<overlay>[A-Za-z_][A-Za-z0-9_]*)'\z")
            if (-not $match.Success) { $issues.Add("unrecognized-cross-import-remark:$rawLineNumber"); continue }
            $triggers.Add([pscustomobject]@{ rawLineNumber = $rawLineNumber; declaringModule = $match.Groups['owner'].Value
                bystandingModule = $match.Groups['bystander'].Value; overlayModule = $match.Groups['overlay'].Value
                sourceLine = $sourceLine; sourceColumn = $column; sourcePath = $path
                sourcePositionValid = $locationValid -and $sourceLine -ge 3 })
        } elseif ($entry.severity -ceq 'remark' -and $identifier -ceq 'module_loaded') {
            $match = [regex]::Match($message, "\Aloaded module '(?<module>[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)'(?<clang> \(overlay for a clang dependency\))?; source: '(?<source>[^']*)', loaded: '(?<loaded>[^']*)'\z")
            if (-not $match.Success) { $issues.Add("unrecognized-module-load-remark:$rawLineNumber"); continue }
            $loads.Add([pscustomobject]@{ rawLineNumber = $rawLineNumber; module = $match.Groups['module'].Value
                sourcePath = $match.Groups['source'].Value; loadedPath = $match.Groups['loaded'].Value
                clangDependencyOverlay = $match.Groups['clang'].Success })
        } elseif ($entry.severity -ceq 'remark' -and $identifier -ceq 'transitive_dependency_behavior') {
            # ModuleFile.cpp:193-206 emits all three behaviors under the same
            # -Rmodule-loading flag. A dependency remark is not a module load.
            $match = [regex]::Match($message, "\A'(?<module>[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)' has (?<behavior>a required|an optional|an ignored) transitive dependency on '(?<dependency>[^']+)'\z")
            if (-not $match.Success) { $issues.Add("unrecognized-transitive-dependency-remark:$rawLineNumber"); continue }
            $dependencies.Add([pscustomobject]@{ rawLineNumber = $rawLineNumber; module = $match.Groups['module'].Value
                behavior = $match.Groups['behavior'].Value; dependency = $match.Groups['dependency'].Value })
        } elseif ($entry.severity -ceq 'remark') {
            $issues.Add("unrecognized-remark:$rawLineNumber")
        }
    }
    if ($searchState -ge 0) { $issues.Add('unfinished-search-path-dump') }
    return [pscustomobject][ordered]@{
        profile = $policy.profile; path = $read.path; sha256 = $read.sha256; bytes = $read.bytes; text = $text
        sourcePath = $ExpectedSourcePath; sourceSha256 = $source.sha256; control = $source.control
        declaringModule = $source.declaringModule; bystandingModule = $source.bystandingModule
        headers = $headers.ToArray(); triggers = $triggers.ToArray(); loads = $loads.ToArray()
        dependencies = $dependencies.ToArray()
        searchPathDump = [pscustomobject]@{ blocks = $searchBlocks; completeBlocks = $searchCompleteBlocks
            entries = $searchEntries.ToArray(); rawLines = $searchRawLines.ToArray() }
        otherLines = $otherLines.ToArray(); issues = $issues.ToArray(); complete = $issues.Count -eq 0
    }
}

function Read-SwiftUIOverlayProbeTrace {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$ExpectedModuleName,
        [Parameter(Mandatory)]$Target)
    Assert-SwiftUIOverlayProbeContext $Target 'off'
    if ($ExpectedModuleName -isnot [string] -or $ExpectedModuleName -cnotmatch '\ASWUIOverlayProbe_[0-9a-f]{64}\z') { throw 'Trace module identity is not a complete probe request ID.' }
    $policy = Get-SwiftUIOverlayProbeNativePolicy
    $read = Read-SwiftUIStateObjectJson $Path -MaxBytes $policy.maximumEvidenceBytes -MaxDepth 32 -MaxNodes 200000 -IncludeText
    $issues = [Collections.Generic.List[string]]::new()
    # The public implementation appends one compact JSON object and a literal LF.
    # A fresh single-input frontend request must not inherit or concatenate records.
    if ($read.text -cnotmatch '\A[^\r\n]+\n\z') { $issues.Add('unsupported-trace-framing') }
    $document = $read.document
    $rootFields = @('version', 'name', 'arch', 'languageMode', 'enabledLanguageFeatures',
        'strictMemorySafety', 'swiftmodules', 'swiftmodulesDetailedInfo', 'swiftmacros')
    Assert-SwiftUIOverlayProbeObject $document $rootFields
    foreach ($name in @($document.PSObject.Properties.Name)) {
        if ($name -cnotin $rootFields) { $issues.Add("unknown-trace-field:$name") }
    }
    if ($document.version -isnot [long] -or $document.version -ne 2) { $issues.Add('unsupported-trace-version') }
    $arch = if ($Target -ceq 'arm64-apple-macosx26.5') { 'arm64' } else { 'x86_64' }
    if ($document.name -isnot [string] -or $document.name -cne $ExpectedModuleName -or
        $document.arch -isnot [string] -or $document.arch -cne $arch -or
        $document.languageMode -isnot [string] -or $document.languageMode -cne '6' -or
        $document.strictMemorySafety -isnot [bool]) { $issues.Add('trace-context-mismatch') }
    foreach ($field in @('enabledLanguageFeatures', 'swiftmodules', 'swiftmodulesDetailedInfo', 'swiftmacros')) {
        if ($document.$field -isnot [array] -or $document.$field.Count -gt $policy.maximumModuleEntries) { throw "Invalid or oversized trace array '$field'." }
    }
    foreach ($feature in $document.enabledLanguageFeatures) {
        if ($feature -isnot [string] -or $feature.Length -gt 256 -or $feature -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*\z') { $issues.Add('invalid-language-feature') }
    }
    $seenModules = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $moduleFields = @('name', 'path', 'isImportedDirectly', 'supportsLibraryEvolution', 'strictMemorySafety')
    foreach ($module in $document.swiftmodulesDetailedInfo) {
        Assert-SwiftUIOverlayProbeObject $module $moduleFields
        foreach ($name in @($module.PSObject.Properties.Name)) {
            if ($name -cnotin $moduleFields) { $issues.Add("unknown-module-field:$name") }
        }
        if ($module.name -isnot [string] -or $module.name -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\z' -or
            $module.name.Length -gt 512) { $issues.Add('invalid-trace-module-name') }
        elseif (-not $seenModules.Add($module.name)) { $issues.Add("ambiguous-trace-module:$($module.name)") }
        foreach ($field in @('isImportedDirectly', 'supportsLibraryEvolution', 'strictMemorySafety')) {
            if ($module.$field -isnot [bool]) { $issues.Add("invalid-module-boolean:$field") }
        }
        try { Assert-SwiftUIOverlayProbeNativePath $module.path } catch { $issues.Add('unsupported-trace-module-path') }
    }
    if ($document.swiftmodules.Count -ne $document.swiftmodulesDetailedInfo.Count) { $issues.Add('trace-path-list-count-mismatch') }
    else {
        for ($i = 0; $i -lt $document.swiftmodules.Count; $i++) {
            if ($document.swiftmodules[$i] -isnot [string] -or $document.swiftmodules[$i] -cne $document.swiftmodulesDetailedInfo[$i].path) { $issues.Add("trace-path-list-mismatch:$i") }
        }
    }
    foreach ($macro in $document.swiftmacros) {
        Assert-SwiftUIOverlayProbeObject $macro @('name', 'path')
        foreach ($name in @($macro.PSObject.Properties.Name)) {
            if ($name -cnotin @('name', 'path')) { $issues.Add("unknown-macro-field:$name") }
        }
        try { Assert-SwiftUIOverlayProbeNativeIdentifier $macro.name; Assert-SwiftUIOverlayProbeNativePath $macro.path }
        catch { $issues.Add('unsupported-macro-record') }
    }
    if ($document.swiftmacros.Count -gt 0) { $issues.Add('macro-loads-require-separate-review') }
    return [pscustomobject][ordered]@{
        profile = $policy.profile; path = $Path; sha256 = $read.sha256; bytes = $read.bytes; text = $read.text
        target = $Target; expectedModuleName = $ExpectedModuleName; recordCount = 1
        document = $document; issues = $issues.ToArray(); complete = $issues.Count -eq 0
    }
}

function Get-SwiftUIOverlayProbeProcessOutcome {
    param([Parameter(Mandatory)]$LaunchState, [AllowNull()]$Process)
    if ($LaunchState -isnot [string] -or $LaunchState -cnotin @('not-run', 'confirmed-started', 'confirmed-not-started', 'unknown-after-invocation')) { throw 'Unknown launch state.' }
    $result = [ordered]@{
        outcome = 'evidence-incomplete'; stopLaterCommands = $true
        descendantClosureRequired = $false; descendantsClosed = $null
        descendantClosureStatus = 'not-independently-observed'
        process = $Process
    }
    if ($LaunchState -ceq 'not-run') {
        if ($null -ne $Process) { throw 'An unrun cell must not contain a process observation.' }
        $result.outcome = 'not-run'; $result.stopLaterCommands = $false
        return [pscustomobject]$result
    }
    if ($LaunchState -ceq 'unknown-after-invocation') {
        $result.outcome = 'launch-uncertain'; $result.descendantClosureRequired = $true
        return [pscustomobject]$result
    }
    Assert-SwiftUIOverlayProbeObject $Process @('processStarted', 'exitCode', 'timedOut', 'outputLimitExceeded',
        'terminationRequested', 'terminationCompleted', 'allRedirectedStreamsClosed', 'error', 'cleanupErrors',
        'stdoutBytes', 'stderrBytes', 'stdoutSha256', 'stderrSha256', 'observedDiscardedBytes')
    foreach ($field in @('processStarted', 'timedOut', 'outputLimitExceeded', 'terminationRequested', 'terminationCompleted', 'allRedirectedStreamsClosed')) {
        if ($Process.$field -isnot [bool]) { throw "Process $field must be a JSON boolean." }
    }
    foreach ($field in @('stdoutBytes', 'stderrBytes', 'observedDiscardedBytes')) {
        if (($Process.$field -isnot [long] -and $Process.$field -isnot [int]) -or $Process.$field -lt 0 -or $Process.$field -gt [long][int]::MaxValue) { throw "Process $field is outside the byte-count profile." }
    }
    if ($Process.cleanupErrors -isnot [array]) { throw 'Process cleanup errors must be an array.' }
    foreach ($errorItem in $Process.cleanupErrors) {
        if ($errorItem -isnot [string]) { throw 'Process cleanup errors must retain their text.' }
    }
    if ($null -ne $Process.error -and $Process.error -isnot [string]) { throw 'Process error must be null or text.' }
    if ($null -ne $Process.exitCode -and $Process.exitCode -isnot [int] -and $Process.exitCode -isnot [long]) { throw 'A process exit code must be a recorded integer or null.' }
    if ('descendantsClosed' -cin @($Process.PSObject.Properties.Name)) {
        if ($null -ne $Process.descendantsClosed -and $Process.descendantsClosed -isnot [bool]) { throw 'Descendant closure must be null or a JSON boolean.' }
        $result.descendantsClosed = $Process.descendantsClosed
        if ($Process.descendantsClosed -eq $true) { $result.descendantClosureStatus = 'collector-reported-closed' }
        elseif ($Process.descendantsClosed -eq $false) { $result.descendantClosureStatus = 'not-established' }
    }
    if ($LaunchState -ceq 'confirmed-not-started') {
        if ($Process.processStarted -or $null -ne $Process.exitCode) { throw 'A confirmed nonlaunch contradicts the process observation.' }
        $result.outcome = 'launch-failed'
        return [pscustomobject]$result
    }
    if (-not $Process.processStarted) { throw 'A confirmed launch contradicts the process observation.' }
    $uncertain = $Process.timedOut -or $Process.outputLimitExceeded -or $Process.terminationRequested -or
        -not $Process.terminationCompleted -or -not $Process.allRedirectedStreamsClosed -or
        $null -eq $Process.exitCode -or $null -ne $Process.error -or $Process.cleanupErrors.Count -gt 0 -or
        $Process.observedDiscardedBytes -gt 0 -or $Process.exitCode -cnotin @(0, 1)
    if ($uncertain) {
        $result.descendantClosureRequired = $true
        $result.outcome = if ($Process.timedOut) { 'timeout' } elseif ($Process.outputLimitExceeded -or $Process.observedDiscardedBytes -gt 0) { 'output-limit' } else { 'process-uncertain' }
        # Version 1 has no resume/follow-up protocol. Even a caller-reported
        # closure cannot turn an uncertain invocation into permission to continue.
        return [pscustomobject]$result
    }
    foreach ($field in @('stdoutSha256', 'stderrSha256')) { Assert-SwiftUIOverlayProbeHash $Process.$field }
    $policy = Get-SwiftUIOverlayProbeNativePolicy
    if ([long]$Process.stdoutBytes + [long]$Process.stderrBytes -gt $policy.maximumEvidenceBytes) { throw 'Process streams exceed the fixed combined byte budget.' }
    $result.outcome = if ($Process.exitCode -eq 0) { 'compiler-succeeded' } else { 'compiler-exited-one' }
    $result.stopLaterCommands = $false
    # Natural exit plus drained streams is not a complete descendant census.
    return [pscustomobject]$result
}

function Get-SwiftUIOverlayProbeAssessment {
    # The collector/replayer must first bind this request to its captured
    # executable/profile hash, exact fixed argv, generated source hash, target,
    # C++ mode, and diagnostics.sourcePath (the actual source argv path). Those
    # invocation receipts are owned by the collector, not authenticated here.
    # This helper replays bounded captured streams and interprets their content;
    # it cannot establish who produced caller-provided files or path observations.
    param([Parameter(Mandatory)]$RequestId, [Parameter(Mandatory)]$CompilerProfileSha256,
        [Parameter(Mandatory)]$DeclaringModule, [Parameter(Mandatory)]$BystandingModule,
        [Parameter(Mandatory)]$OverlayModule, [Parameter(Mandatory)]$Control,
        [Parameter(Mandatory)]$Target, [Parameter(Mandatory)]$CxxMode,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$CandidateRecordIds,
        [Parameter(Mandatory)]$LaunchState, [AllowNull()]$Process, [AllowNull()]$Diagnostics,
        [AllowNull()]$Trace, [AllowEmptyCollection()][object[]]$PathObservations = @())
    Assert-SwiftUIOverlayProbeHash $RequestId
    Assert-SwiftUIOverlayProbeHash $CompilerProfileSha256
    Assert-SwiftUIOverlayProbeNativeIdentifier $OverlayModule
    Assert-SwiftUIOverlayProbeContext $Target $CxxMode
    $source = New-SwiftUIOverlayProbeSource $DeclaringModule $BystandingModule $Control
    if ($OverlayModule -ceq $DeclaringModule -or $OverlayModule -ceq $BystandingModule) { throw 'An overlay must be distinct from both lexical imports.' }
    if ($CandidateRecordIds.Count -eq 0 -or $CandidateRecordIds.Count -gt 4096) { throw 'Candidate occurrence IDs must be present and bounded.' }
    $seenCandidates = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($candidateId in $CandidateRecordIds) {
        Assert-SwiftUIOverlayProbeHash $candidateId
        if (-not $seenCandidates.Add($candidateId)) { throw 'Duplicate candidate occurrence ID.' }
    }
    $processResult = Get-SwiftUIOverlayProbeProcessOutcome $LaunchState $Process
    $issues = [Collections.Generic.List[string]]::new()
    $result = [ordered]@{
        profile = (Get-SwiftUIOverlayProbeNativePolicy).profile
        requestId = $RequestId; compilerProfileSha256 = $CompilerProfileSha256
        declaringModule = $DeclaringModule; bystandingModule = $BystandingModule; overlayModule = $OverlayModule
        control = $Control; target = $Target; cxxMode = $CxxMode; sourceSha256 = $source.sha256
        candidateRecordIds = @($CandidateRecordIds); occurrenceAttribution = 'not-established'
        outcome = $processResult.outcome; stopLaterCommands = $processResult.stopLaterCommands
        descendantClosureRequired = $processResult.descendantClosureRequired
        descendantsClosed = $processResult.descendantsClosed; descendantClosureStatus = $processResult.descendantClosureStatus
        triggerObserved = $false; moduleLoadObserved = $false; traceMembershipObserved = $false
        loadedFileIdentitiesRecorded = $false; overlayActivationObserved = $false
        lexicalPairNecessityEstablished = $false; definitionOccurrenceTriggered = $false
        primaryTriggerLines = @(); moduleLoadLines = @(); modulePaths = @(); traceSha256 = $null; stderrSha256 = $null
        issues = @(); nativeRuntimeVerified = $false; publicAPIAuditComplete = $false; releaseQualified = $false
    }
    if ($processResult.outcome -cnotin @('compiler-succeeded', 'compiler-exited-one')) { return [pscustomobject]$result }
    if ($null -eq $Diagnostics) {
        $result.outcome = 'evidence-incomplete'; $result.stopLaterCommands = $true
        $result.issues = @('missing-diagnostics'); return [pscustomobject]$result
    }
    Assert-SwiftUIOverlayProbeObject $Diagnostics @('path', 'sourcePath', 'profile', 'sha256', 'bytes', 'sourceSha256', 'control',
        'declaringModule', 'bystandingModule', 'headers', 'triggers', 'loads', 'issues', 'complete')
    Assert-SwiftUIOverlayProbeHash $Diagnostics.sha256
    Assert-SwiftUIOverlayProbeHash $Diagnostics.sourceSha256
    if (($Diagnostics.bytes -isnot [long] -and $Diagnostics.bytes -isnot [int]) -or $Diagnostics.bytes -lt 0) { throw 'Diagnostic bytes must be a nonnegative integer.' }
    foreach ($field in @('path', 'sourcePath', 'profile', 'control', 'declaringModule', 'bystandingModule')) {
        if ($Diagnostics.$field -isnot [string]) { throw "Diagnostic $field must be text, without scalar coercion." }
    }
    if ($Diagnostics.profile -cne $result.profile -or $Diagnostics.sha256 -cne $Process.stderrSha256 -or
        $Diagnostics.bytes -ne $Process.stderrBytes -or $Diagnostics.sourceSha256 -cne $source.sha256 -or
        $Diagnostics.control -cne $Control -or $Diagnostics.declaringModule -cne $DeclaringModule -or
        $Diagnostics.bystandingModule -cne $BystandingModule) { $issues.Add('diagnostic-process-source-binding-mismatch') }
    if ($Diagnostics.complete -isnot [bool] -or -not $Diagnostics.complete -or @($Diagnostics.issues).Count -gt 0) { $issues.Add('diagnostic-profile-incomplete') }
    # A caller can mutate a PSCustomObject after parsing it. Re-open only the
    # bounded captured artifact, then derive every diagnostic fact from its raw
    # bytes again. This does not authorize or read the recorded SDK/module paths.
    $replayedDiagnostics = Read-SwiftUIOverlayProbeDiagnostics -StderrPath $Diagnostics.path -ExpectedSourcePath $Diagnostics.sourcePath -SourceRecord $source
    if ($replayedDiagnostics.sha256 -cne $Diagnostics.sha256 -or $replayedDiagnostics.bytes -ne $Diagnostics.bytes -or
        $replayedDiagnostics.sha256 -cne $Process.stderrSha256 -or $replayedDiagnostics.bytes -ne $Process.stderrBytes) { $issues.Add('diagnostic-artifact-changed') }
    if (-not $replayedDiagnostics.complete) { $issues.Add('replayed-diagnostic-profile-incomplete') }
    $Diagnostics = $replayedDiagnostics
    $result.stderrSha256 = $Diagnostics.sha256
    $errors = @($Diagnostics.headers | Where-Object { $_.severity -ceq 'error' })
    $warnings = @($Diagnostics.headers | Where-Object { $_.severity -ceq 'warning' })
    if ($Process.stdoutBytes -ne 0 -or $Process.stdoutSha256 -cne 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') { $issues.Add('unexpected-frontend-stdout') }
    if ($processResult.outcome -ceq 'compiler-exited-one') {
        if ($errors.Count -gt 0 -and $issues.Count -eq 0) { $result.outcome = 'compiler-rejected' }
        else { $result.outcome = 'evidence-incomplete'; $result.stopLaterCommands = $true; $issues.Add('exit-one-without-complete-error-evidence') }
        $result.issues = $issues.ToArray(); return [pscustomobject]$result
    }
    if ($errors.Count -gt 0 -or $warnings.Count -gt 0) { $issues.Add('successful-exit-with-diagnostics-requiring-review') }
    if ($Diagnostics.searchPathDump.blocks -ne 1 -or $Diagnostics.searchPathDump.completeBlocks -ne 1) { $issues.Add('missing-complete-module-search-path-dump') }
    $triggers = @($Diagnostics.triggers | Where-Object {
        $_.declaringModule -ceq $DeclaringModule -and $_.bystandingModule -ceq $BystandingModule -and
        $_.overlayModule -ceq $OverlayModule -and $_.sourcePositionValid -eq $true
    })
    $loads = @($Diagnostics.loads | Where-Object { $_.module -ceq $OverlayModule })
    $result.primaryTriggerLines = @($triggers | ForEach-Object { $_.rawLineNumber })
    $result.moduleLoadLines = @($loads | ForEach-Object { $_.rawLineNumber })
    $result.triggerObserved = $triggers.Count -gt 0
    $result.moduleLoadObserved = $loads.Count -gt 0
    if ($triggers.Count -gt 1) { $issues.Add('multiple-matching-trigger-remarks') }
    if ($loads.Count -gt 1) { $issues.Add('multiple-matching-module-loads') }
    if ($null -eq $Trace) { $issues.Add('missing-trace') }
    else {
        Assert-SwiftUIOverlayProbeObject $Trace @('path', 'profile', 'sha256', 'bytes', 'target', 'expectedModuleName', 'document', 'complete', 'issues', 'recordCount')
        Assert-SwiftUIOverlayProbeHash $Trace.sha256
        if (($Trace.bytes -isnot [long] -and $Trace.bytes -isnot [int]) -or $Trace.bytes -lt 1) { throw 'Trace bytes must be a positive integer.' }
        foreach ($field in @('path', 'profile', 'target', 'expectedModuleName')) {
            if ($Trace.$field -isnot [string]) { throw "Trace $field must be text, without scalar coercion." }
        }
        if ($Trace.recordCount -isnot [long] -and $Trace.recordCount -isnot [int]) { throw 'Trace record count must be an integer.' }
        if ($Trace.profile -cne $result.profile -or $Trace.target -cne $Target -or
            $Trace.expectedModuleName -cne "SWUIOverlayProbe_$RequestId" -or $Trace.recordCount -ne 1 -or
            $Trace.complete -isnot [bool] -or -not $Trace.complete -or @($Trace.issues).Count -gt 0) { $issues.Add('trace-profile-or-context-incomplete') }
        $replayedTrace = Read-SwiftUIOverlayProbeTrace -Path $Trace.path -ExpectedModuleName "SWUIOverlayProbe_$RequestId" -Target $Target
        if ($replayedTrace.sha256 -cne $Trace.sha256 -or $replayedTrace.bytes -ne $Trace.bytes) { $issues.Add('trace-artifact-changed') }
        if (-not $replayedTrace.complete) { $issues.Add('replayed-trace-profile-incomplete') }
        $Trace = $replayedTrace
        $result.traceSha256 = $Trace.sha256
        $traceModules = @($Trace.document.swiftmodulesDetailedInfo | Where-Object { $_.name -ceq $OverlayModule })
        $result.traceMembershipObserved = $traceModules.Count -eq 1
        if ($traceModules.Count -gt 1) { $issues.Add('ambiguous-overlay-trace-membership') }
        if ($traceModules.Count -eq 1 -and $loads.Count -eq 1 -and
            $traceModules[0].path -cne $loads[0].sourcePath -and $traceModules[0].path -cne $loads[0].loadedPath) { $issues.Add('trace-and-load-paths-disagree') }
    }
    $observations = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $canonicalObservations = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($observation in $PathObservations) {
        Assert-SwiftUIOverlayProbeObject $observation @('path', 'canonicalPath', 'status', 'bytes', 'sha256')
        Assert-SwiftUIOverlayProbeNativePath $observation.path
        if ($observation.status -isnot [string] -or $observation.status -cnotin @('recorded', 'unobserved', 'not-authorized', 'failed')) { throw 'Unknown module-path observation status.' }
        if ($observations.ContainsKey($observation.path)) { throw 'Duplicate module-path observation.' }
        if ($observation.status -ceq 'recorded') {
            Assert-SwiftUIOverlayProbeNativePath $observation.canonicalPath
            Assert-SwiftUIOverlayProbeHash $observation.sha256
            if (($observation.bytes -isnot [long] -and $observation.bytes -isnot [int]) -or $observation.bytes -lt 1 -or
                $observation.bytes -gt (Get-SwiftUIOverlayProbeNativePolicy).maximumLoadedFileBytes) { throw 'Recorded module file byte count is outside the fixed profile.' }
            if ($canonicalObservations.ContainsKey($observation.canonicalPath)) {
                $prior = $canonicalObservations[$observation.canonicalPath]
                if ($prior.bytes -ne $observation.bytes -or $prior.sha256 -cne $observation.sha256) { throw 'Conflicting observations of one canonical module path.' }
            } else { $canonicalObservations.Add($observation.canonicalPath, $observation) }
        }
        $observations.Add($observation.path, $observation)
    }
    if ($loads.Count -eq 1) {
        $result.modulePaths = @($loads[0].sourcePath, $loads[0].loadedPath)
        $pathsRecorded = $true
        foreach ($path in $result.modulePaths) {
            try { Assert-SwiftUIOverlayProbeNativePath $path } catch { $pathsRecorded = $false; $issues.Add('unsupported-module-load-path'); continue }
            if (-not $observations.ContainsKey($path) -or $observations[$path].status -cne 'recorded') { $pathsRecorded = $false; $issues.Add('unobserved-module-file-identity') }
        }
        $result.loadedFileIdentitiesRecorded = $pathsRecorded
    }
    $result.overlayActivationObserved = $issues.Count -eq 0 -and $result.triggerObserved -and
        $result.moduleLoadObserved -and $result.traceMembershipObserved -and $result.loadedFileIdentitiesRecorded
    if ($issues.Count -gt 0) { $result.outcome = 'evidence-incomplete'; $result.stopLaterCommands = $true }
    elseif ($result.overlayActivationObserved) { $result.outcome = 'overlay-load-observed' }
    else { $result.outcome = 'import-succeeded-without-overlay-evidence' }
    # Even one candidate is a census association, not proof that its definition
    # bytes won resolution. Multiple occurrences remain explicitly ambiguous.
    $result.occurrenceAttribution = if ($CandidateRecordIds.Count -gt 1) { 'ambiguous-census-occurrences' } else { 'not-established' }
    $result.issues = $issues.ToArray()
    return [pscustomobject]$result
}
