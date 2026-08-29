<#
.SYNOPSIS
    Bounded evidence for observed CoreLogic XCTest stdout. Never launches tests.
.DESCRIPTION
    Dot-source for the parser/journal. Check requires a caller-held request ID;
    PublishCI writes sanitized fixed-name files. Neither action promotes failure.
    Swift Testing, portable tests, stderr, raw bytes and direct exits are unobserved.
#>
param(
    [ValidateSet('', 'Check', 'PublishCI')]
    [string]$EvidenceAction = '',
    [string]$ReceiptDirectory = '',
    [string]$EvidenceWorkspaceRoot = '',
    [ValidateSet('', 'success', 'failure', 'cancelled', 'skipped')]
    [string]$CIOutcome = '',
    $ExpectedSessionId
)

function Get-SwiftTestEvidenceLimits {
    [pscustomobject][ordered]@{
        maxShards = 512; maxCasesPerShard = 2048; maxCaseObservations = 20000
        maxLineCharacters = 16384; maxOutputObjects = 1000000
        maxIdentifierCharacters = 256; maxFilterCharacters = 8192
        maxJsonBytes = 1048576; maxSessionBytes = 16777216
        maxPublishedCasesBytes = 8388608; maxJsonDepth = 16
    }
}

function Get-SwiftTestEvidenceHash {
    param([byte[]]$Bytes)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Get-SwiftTestEvidenceFilePin {
    param([string]$Path, [string]$RelativePath, [int]$MaximumBytes = 4194304)
    $stream = $null; $hash = $null
    try {
        if (-not [IO.File]::Exists($Path) -or
            (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'file-unavailable' }
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ($MaximumBytes -lt 0 -or $MaximumBytes -gt 8388608 -or $stream.Length -gt $MaximumBytes) { throw 'file-too-large' }
        $length = $stream.Length
        $hash = [Security.Cryptography.SHA256]::Create()
        $digest = ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
        return [pscustomobject][ordered]@{ path = $RelativePath; status = 'observed'; bytes = $length; sha256 = $digest }
    } catch {
        return [pscustomobject][ordered]@{ path = $RelativePath; status = 'unavailable'; bytes = $null; sha256 = $null }
    } finally {
        if ($null -ne $hash) { $hash.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-SwiftTestEvidenceSourcePins {
    param([string]$WorkspaceRoot)
    $paths = @('scripts/test.ps1', 'scripts/swift-test-evidence.ps1',
        'scripts/agent-check.ps1', 'scripts/with-swift.ps1', 'Package.swift')
    return @(foreach ($path in $paths) {
        Get-SwiftTestEvidenceFilePin -Path (Join-Path $WorkspaceRoot $path) -RelativePath $path
    })
}

function Get-SwiftTestEvidenceSafeEnvironmentValue {
    param([string]$Name, [string]$Pattern)
    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrEmpty($value)) { return $null }
    if ($value.Length -gt 128 -or $value -cmatch '[^\x20-\x7e]' -or $value -cnotmatch $Pattern) { return $null }
    return $value
}

function Get-SwiftTestEvidenceMetadata {
    param([string]$WorkspaceRoot)
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    [pscustomobject][ordered]@{
        workspaceId = Get-SwiftTestEvidenceHash $encoding.GetBytes([IO.Path]::GetFullPath($WorkspaceRoot).ToUpperInvariant())
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        osVersion = [Environment]::OSVersion.Version.ToString()
        is64BitProcess = [Environment]::Is64BitProcess
        expectedCommit = Get-SwiftTestEvidenceSafeEnvironmentValue 'GITHUB_SHA' '^[0-9a-f]{40}$'
        runId = Get-SwiftTestEvidenceSafeEnvironmentValue 'GITHUB_RUN_ID' '^[0-9]{1,20}$'
        runAttempt = Get-SwiftTestEvidenceSafeEnvironmentValue 'GITHUB_RUN_ATTEMPT' '^[0-9]{1,8}$'
        imageOS = Get-SwiftTestEvidenceSafeEnvironmentValue 'ImageOS' '^[A-Za-z0-9_.+-]+$'
        imageVersion = Get-SwiftTestEvidenceSafeEnvironmentValue 'ImageVersion' '^[A-Za-z0-9_.+-]+$'
        runnerOS = Get-SwiftTestEvidenceSafeEnvironmentValue 'RUNNER_OS' '^[A-Za-z0-9_.+-]+$'
        runnerArchitecture = Get-SwiftTestEvidenceSafeEnvironmentValue 'RUNNER_ARCH' '^[A-Za-z0-9_.+-]+$'
        swiftVersionSelector = Get-SwiftTestEvidenceSafeEnvironmentValue 'SWIFT_VERSION' '^[A-Za-z0-9_.+-]+$'
        swiftBuildSelector = Get-SwiftTestEvidenceSafeEnvironmentValue 'SWIFT_BUILD' '^[A-Za-z0-9_.+-]+$'
        sourceAssociation = 'working-file-hashes; expected-ci-commit-only; not-binary-attestation'
        compilerIdentity = 'not-observed'
        runtimeGitIdentity = 'not-observed'
        sourceFiles = @(Get-SwiftTestEvidenceSourcePins $WorkspaceRoot)
    }
}

function New-SwiftTestEvidenceRequestId {
    return [Guid]::NewGuid().ToString('N')
}

function Get-SwiftTestEvidenceRequestPathAttributes {
    param([string]$Path)
    return [IO.File]::GetAttributes($Path)
}

function Write-SwiftTestEvidenceRequestLine {
    param([IO.Stream]$Stream, [byte[]]$Bytes)
    $Stream.Write($Bytes, 0, $Bytes.Length)
    $Stream.Flush()
}

function Write-SwiftTestEvidenceRequestOutput {
    param($OutputPath, $RunnerTemp, $SessionId)
    # This is a bounded single-line Actions output bridge, not a generic parser.
    # Supplied paths only: never discover or fall back to ambient control files.
    # Ordinary stream sharing does not freeze ancestor identity or authenticate
    # the runner. Failure can leave a complete NEW line, or preserve an OLD key.
    $stream = $null
    try {
        try {
            if ($SessionId -isnot [string] -or $SessionId -cnotmatch '\A[0-9a-f]{32}\z' -or
                $OutputPath -isnot [string] -or $RunnerTemp -isnot [string]) { throw 'request-output-invalid' }
            $paths = [Collections.Generic.List[string]]::new()
            foreach ($supplied in @($RunnerTemp, $OutputPath)) {
                if ($supplied.Length -gt 1024 -or $supplied -cnotmatch '\A[A-Za-z]:[\\/]') { throw 'request-output-invalid' }
                $normalized = $supplied.Replace('/', '\')
                $parts = $normalized.Substring(3).Split([char]'\')
                foreach ($part in $parts) {
                    # Reject traversal, ADS, short-name and Win32 trimming/device
                    # aliases before any filesystem lookup or normalization.
                    if ($part.Length -gt 255 -or $part -cnotmatch '\A[A-Za-z0-9_. -]+\z' -or
                        $part -cin @('.', '..') -or $part.StartsWith(' ') -or $part.EndsWith(' ') -or $part.EndsWith('.') -or
                        $part -match '\A(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]) *(\.|\z)') { throw 'request-output-invalid' }
                }
                $canonical = [IO.Path]::GetFullPath($normalized)
                if (-not [string]::Equals($canonical, $normalized, [StringComparison]::OrdinalIgnoreCase)) { throw 'request-output-invalid' }
                [void]$paths.Add($canonical)
            }
            $root = $paths[0]; $path = $paths[1]
            $driveRoot = [IO.Path]::GetPathRoot($root)
            if ([string]::Equals($root, $driveRoot, [StringComparison]::OrdinalIgnoreCase) -or
                -not $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or
                [IO.DriveInfo]::new($driveRoot).DriveType -ne [IO.DriveType]::Fixed) { throw 'request-output-invalid' }
            $walk = $driveRoot; $runnerObserved = $false
            $segments = @('') + @($path.Substring($driveRoot.Length).Split([char]'\'))
            foreach ($segment in $segments) {
                if ($segment.Length -gt 0) { $walk = [IO.Path]::Combine($walk, $segment) }
                # Inspect each ancestor before probing any descendant, including
                # an absent leaf. No reparse or non-directory ancestor is followed.
                $attributes = Get-SwiftTestEvidenceRequestPathAttributes -Path $walk
                if (($attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Device)) -ne 0) { throw 'request-output-invalid' }
                $isDirectory = ($attributes -band [IO.FileAttributes]::Directory) -ne 0
                $isLeaf = [string]::Equals($walk, $path, [StringComparison]::OrdinalIgnoreCase)
                if (($isLeaf -and $isDirectory) -or (-not $isLeaf -and -not $isDirectory)) { throw 'request-output-invalid' }
                if ([string]::Equals($walk, $root, [StringComparison]::OrdinalIgnoreCase)) { $runnerObserved = $true }
            }
            if (-not $runnerObserved) { throw 'request-output-invalid' }
            # Open must find an existing regular file. Read sharing permits the
            # runner to inspect it but denies competing writers and deletion.
            $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
            $encoding = [Text.UTF8Encoding]::new($false, $true)
            $appendBytes = $encoding.GetBytes('corelogic_evidence_request_id=' + $SessionId + "`n")
            $prefixLength = $stream.Length
            $finalLength = $prefixLength + $appendBytes.Length
            if ($prefixLength -gt 65536 -or $finalLength -gt 65536) { throw 'request-output-invalid' }
            $prefixBytes = New-Object byte[] ([int]$prefixLength)
            $offset = 0
            while ($offset -lt $prefixBytes.Length) {
                $read = $stream.Read($prefixBytes, $offset, $prefixBytes.Length - $offset)
                if ($read -le 0) { throw 'request-output-invalid' }
                $offset += $read
            }
            if ($stream.ReadByte() -ne -1) { throw 'request-output-invalid' }
            $prefixText = $encoding.GetString($prefixBytes)
            if ($prefixText -cmatch '[^\x20-\x7e\r\n]' -or
                ($prefixText.Length -gt 0 -and -not $prefixText.EndsWith("`n", [StringComparison]::Ordinal))) { throw 'request-output-invalid' }
            $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            $prefixLines = $prefixText.Split([char]"`n")
            for ($i = 0; $i -lt $prefixLines.Length - 1; $i++) {
                $line = $prefixLines[$i]
                if ($line.EndsWith("`r", [StringComparison]::Ordinal)) { $line = $line.Substring(0, $line.Length - 1) }
                # Only complete ASCII KEY=VALUE records are admitted. Multiline
                # syntax, blank records, controls and duplicate keys are refused.
                if ($line -cnotmatch '\A(?<key>[A-Za-z_][A-Za-z0-9_.-]*)=[\x20-\x7e]*\z') { throw 'request-output-invalid' }
                $key = $Matches.key
                if (-not $keys.Add($key) -or [string]::Equals($key, 'corelogic_evidence_request_id', [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'request-output-invalid'
                }
            }
            Write-SwiftTestEvidenceRequestLine -Stream $stream -Bytes $appendBytes
            if ($stream.Length -ne $finalLength -or $stream.Length -gt 65536) { throw 'request-output-invalid' }
            $expectedBytes = New-Object byte[] ([int]$finalLength)
            [Array]::Copy($prefixBytes, 0, $expectedBytes, 0, $prefixBytes.Length)
            [Array]::Copy($appendBytes, 0, $expectedBytes, $prefixBytes.Length, $appendBytes.Length)
            $actualBytes = New-Object byte[] ([int]$finalLength)
            $stream.Position = 0; $offset = 0
            while ($offset -lt $actualBytes.Length) {
                $read = $stream.Read($actualBytes, $offset, $actualBytes.Length - $offset)
                if ($read -le 0) { throw 'request-output-invalid' }
                $offset += $read
            }
            if ($stream.ReadByte() -ne -1 -or
                (Get-SwiftTestEvidenceHash $actualBytes) -cne (Get-SwiftTestEvidenceHash $expectedBytes)) { throw 'request-output-invalid' }
        } finally { if ($null -ne $stream) { $stream.Dispose() } }
    } catch {
        # Never print supplied paths, existing bytes or arbitrary exception text.
        throw 'test-evidence-request-output-invalid'
    }
}

function New-SwiftTestEvidenceRequest {
    param([bool]$GitHubActions, [AllowNull()][string]$GitHubOutputPath, [AllowNull()][string]$RunnerTemp)
    $request = [pscustomobject][ordered]@{
        SessionId = $null; ExpectedSessionId = $null; Ready = $false
        BridgeStatus = 'not-attempted'; Problems = @()
    }
    try {
        $generated = New-SwiftTestEvidenceRequestId
        if ($generated -isnot [string] -or $generated -cnotmatch '\A[0-9a-f]{32}\z') { throw 'request-id-invalid' }
        $request.SessionId = $generated
    } catch {
        $request.Problems = @('request-id-generation-failed')
        return $request
    }
    if ($GitHubActions) {
        try {
            $null = Write-SwiftTestEvidenceRequestOutput -OutputPath $GitHubOutputPath -RunnerTemp $RunnerTemp -SessionId $request.SessionId
            $request.BridgeStatus = 'written'
        } catch {
            $request.BridgeStatus = 'failed'; $request.Problems = @('request-output-bridge-failed')
            return $request
        }
    } else { $request.BridgeStatus = 'not-required' }
    $request.ExpectedSessionId = $request.SessionId; $request.Ready = $true
    return $request
}

function Get-SwiftTestEvidenceEpochMilliseconds {
    return [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
}

function Resolve-SwiftTestEvidenceDirectory {
    param([string]$WorkspaceRoot, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($WorkspaceRoot) -or [string]::IsNullOrWhiteSpace($Path) -or
        $WorkspaceRoot.Length -gt 1024 -or $Path.Length -gt 1024) { throw 'test-evidence-path-invalid' }
    # This Windows tooling slice accepts ordinary local workspace paths only.
    # Reject UNC/device roots before any filesystem query.
    if ($WorkspaceRoot -cnotmatch '\A[A-Za-z]:[\\/]' -or
        $Path -cmatch '\A[\\/]{2}') { throw 'test-evidence-path-invalid' }
    $root = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\', '/')
    $artifacts = [IO.Path]::Combine($root, 'artifacts')
    $prefix = $artifacts.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $rawRelative = if ([IO.Path]::IsPathRooted($Path)) {
        $Path.Substring([IO.Path]::GetPathRoot($Path).Length)
    } else { $Path }
    $rawParts = $rawRelative.Split([char[]]@('\', '/'))
    if ($rawParts -contains '..' -or $rawParts -contains '.' -or $rawParts -contains '') { throw 'test-evidence-path-traversal' }
    $normalizedRaw = $Path.Replace('/', '\')
    $rawPrefix = if ([IO.Path]::IsPathRooted($Path)) { $prefix } else { 'artifacts\' }
    if (-not $normalizedRaw.StartsWith($rawPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'test-evidence-path-outside-artifacts' }
    $rawTail = $normalizedRaw.Substring($rawPrefix.Length)
    # Validate before Win32/.NET normalization can trim an aliasing space/dot.
    foreach ($part in $rawTail.Split([char[]]@('\', '/'))) {
        if ($part -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,79}\z' -or $part.EndsWith('.') -or
            $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') { throw 'test-evidence-path-component-invalid' }
    }
    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    } else { [IO.Path]::GetFullPath([IO.Path]::Combine($root, $Path)) }
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'test-evidence-path-outside-artifacts' }
    $driveRoot = [IO.Path]::GetPathRoot($root)
    if ([IO.DriveInfo]::new($driveRoot).DriveType -ne [IO.DriveType]::Fixed) { throw 'test-evidence-path-nonlocal-drive' }
    $walk = $driveRoot; $workspaceObserved = $false
    # Check attributes on each ancestor before querying anything beneath it.
    # In particular, never probe a missing child through an unexamined link.
    $segments = @('') + @($candidate.Substring($driveRoot.Length).Split([char]'\'))
    foreach ($segment in $segments) {
        if ($segment.Length -gt 0) { $walk = [IO.Path]::Combine($walk, $segment) }
        try { $attributes = [IO.File]::GetAttributes($walk) }
        catch [IO.FileNotFoundException] { break }
        catch [IO.DirectoryNotFoundException] { break }
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'test-evidence-path-reparse' }
        $isDirectory = ($attributes -band [IO.FileAttributes]::Directory) -ne 0
        if ([string]::Equals($walk, $root, [StringComparison]::OrdinalIgnoreCase)) {
            if (-not $isDirectory) { throw 'test-evidence-root-missing' }
            $workspaceObserved = $true
        }
        if (-not $isDirectory -and -not [string]::Equals($walk, $candidate, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'test-evidence-path-component-invalid'
        }
    }
    if (-not $workspaceObserved) { throw 'test-evidence-root-missing' }
    return $candidate
}

function New-SwiftTestEvidenceDirectory {
    param([string]$WorkspaceRoot, [string]$Path)
    $resolved = Resolve-SwiftTestEvidenceDirectory $WorkspaceRoot $Path
    if ([IO.File]::Exists($resolved) -or [IO.Directory]::Exists($resolved)) { throw 'test-evidence-destination-exists' }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolved))
    # No -Force: the final directory must be new at creation time.
    $null = New-Item -ItemType Directory -Path $resolved -ErrorAction Stop
    return $resolved
}

function ConvertTo-SwiftTestEvidenceJson {
    param($Value)
    return (ConvertTo-Json -InputObject $Value -Depth 16 -Compress)
}

function Assert-SwiftTestEvidenceJsonDepth {
    param([string]$Text)
    # Bound nesting before ConvertFrom-Json. Exact JSON grammar and escapes are
    # then restricted to canonical producer output by the round-trip comparison.
    $depth = 0; $inString = $false; $escaped = $false
    foreach ($character in $Text.ToCharArray()) {
        if ($inString) {
            if ($escaped) { $escaped = $false }
            elseif ($character -ceq '\') { $escaped = $true }
            elseif ($character -ceq '"') { $inString = $false }
        } elseif ($character -ceq '"') { $inString = $true }
        elseif ($character -ceq '{' -or $character -ceq '[') {
            $depth++
            if ($depth -gt 16) { throw 'test-evidence-json-depth' }
        } elseif ($character -ceq '}' -or $character -ceq ']') {
            $depth--
            if ($depth -lt 0) { throw 'test-evidence-json-depth' }
        }
    }
    if ($depth -ne 0 -or $inString) { throw 'test-evidence-json-depth' }
}

function Write-SwiftTestEvidenceJsonNew {
    param([string]$Path, $Value, [int]$MaximumBytes = 1048576)
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    $bytes = $encoding.GetBytes((ConvertTo-SwiftTestEvidenceJson $Value) + "`n")
    if ($bytes.Length -gt $MaximumBytes) { throw 'test-evidence-json-limit' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length) }
    finally { $stream.Dispose() }
    return $bytes.Length
}

function Read-SwiftTestEvidenceJson {
    param([string]$Path, [int]$MaximumBytes = 1048576)
    if (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'test-evidence-json-reparse' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -le 0 -or $stream.Length -gt $MaximumBytes) { throw 'test-evidence-json-limit' }
        $bytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) { throw 'test-evidence-json-short-read' }
            $offset += $read
        }
        if ($stream.ReadByte() -ne -1) { throw 'test-evidence-json-grew' }
    } finally { $stream.Dispose() }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    Assert-SwiftTestEvidenceJsonDepth $text
    $value = ConvertFrom-Json -InputObject $text -ErrorAction Stop
    if ($null -eq $value -or $value -isnot [pscustomobject]) { throw 'test-evidence-json-root' }
    # Accept only producer JSON: canonical round trip rejects duplicate keys,
    # aliases, comments, alternate escapes/numbers and trailing commas.
    $tokens = [regex]::new('("(?:[^"\\\x00-\x1f]|\\.)*")|[ \t\r\n]+',
        [Text.RegularExpressions.RegexOptions]::CultureInvariant, [TimeSpan]::FromSeconds(1))
    $canonicalInput = $tokens.Replace($text, '$1')
    $canonicalOutput = $tokens.Replace((ConvertTo-SwiftTestEvidenceJson $value), '$1')
    if (-not [string]::Equals($canonicalInput, $canonicalOutput, [StringComparison]::Ordinal)) { throw 'test-evidence-json-noncanonical' }
    return $value
}

function Assert-SwiftTestEvidenceKeys {
    param($Value, [string[]]$Keys)
    if ($null -eq $Value -or $Value -isnot [pscustomobject]) { throw 'test-evidence-schema-object' }
    $actual = @($Value.PSObject.Properties.Name)
    if ($actual.Count -ne $Keys.Count) { throw 'test-evidence-schema-keys' }
    foreach ($key in $actual) { if ($Keys -cnotcontains $key) { throw 'test-evidence-schema-keys' } }
}

function Assert-SwiftTestEvidenceInteger {
    param($Value, [long]$Minimum = 0, [long]$Maximum = 2147483647)
    if ($Value -isnot [int] -and $Value -isnot [long]) { throw 'test-evidence-schema-integer' }
    if ($Value -lt $Minimum -or $Value -gt $Maximum) { throw 'test-evidence-schema-integer' }
}

function Add-SwiftTestEvidenceProblem {
    param($Recorder, [string]$Code)
    if ($null -ne $Recorder -and $Recorder.Problems.Count -lt 64 -and -not $Recorder.Problems.Contains($Code)) {
        [void]$Recorder.Problems.Add($Code)
    }
}

function New-SwiftTestEvidenceRecorder {
    param([int]$Index = 1)
    [pscustomobject]@{
        Index = $Index; Limits = Get-SwiftTestEvidenceLimits
        StartedUtcEpochMilliseconds = Get-SwiftTestEvidenceEpochMilliseconds
        Cases = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        Problems = [Collections.Generic.List[string]]::new()
        OutputObjects = 0; NonStringObjects = 0; IgnoredLines = 0
        RootStarts = 0; RootTerminals = 0; RootStatus = $null; RootName = $null
        CaseStarts = 0; CaseTerminals = 0
        PendingRootSummary = $false; Reported = $null
        SwiftTestingMarkerObserved = $false
    }
}

function Add-SwiftTestEvidenceOutput {
    param($Recorder, [AllowNull()]$Value)
    # Never emits output or throws into the native pipeline.
    try {
        if ($null -eq $Recorder) { return }
        if ($Recorder.OutputObjects -ge $Recorder.Limits.maxOutputObjects) {
            Add-SwiftTestEvidenceProblem $Recorder 'output-object-limit'; return
        }
        $Recorder.OutputObjects++
        if ($Value -isnot [string]) {
            $Recorder.NonStringObjects++
            Add-SwiftTestEvidenceProblem $Recorder 'non-string-output'; return
        }
        if ($Value.Length -gt $Recorder.Limits.maxLineCharacters) {
            Add-SwiftTestEvidenceProblem $Recorder 'line-character-limit'; return
        }
        $line = $Value.TrimEnd("`r", "`n")
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        if ($line -match 'Test run started\.|Testing Library Version:|Test run with [0-9]+ tests?') {
            $Recorder.SwiftTestingMarkerObserved = $true
        }
        $footer = '^\s*Executed (?<tests>[0-9]{1,8}) tests?, with (?:(?<skipped>[0-9]{1,8}) tests? skipped and )?(?<failures>[0-9]{1,8}) failures? \((?<unexpected>[0-9]{1,8}) unexpected\) in [0-9]+(?:\.[0-9]+)? \([0-9]+(?:\.[0-9]+)?\) seconds\.?$'
        if ($Recorder.PendingRootSummary) {
            $Recorder.PendingRootSummary = $false
            if ($line -cmatch $footer) {
                $skipped = if ($Matches.ContainsKey('skipped') -and $Matches.skipped.Length -gt 0) { [int]$Matches.skipped } else { 0 }
                $Recorder.Reported = [pscustomobject][ordered]@{
                    tests = [int]$Matches.tests; skipped = $skipped
                    failures = [int]$Matches.failures; unexpectedFailures = [int]$Matches.unexpected
                }
                return
            }
            Add-SwiftTestEvidenceProblem $Recorder 'missing-root-footer'
        }
        $timestamp = '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,9})?'
        if ($line -cmatch ("^Test Suite '(?<root>All tests|Selected tests)' started at " + $timestamp + '\.?$')) {
            $Recorder.RootStarts++
            $Recorder.RootName = [string]$Matches.root
            if ($Recorder.RootStarts -ne 1) { Add-SwiftTestEvidenceProblem $Recorder 'multiple-root-runs' }
            return
        }
        if ($line -cmatch ("^Test Suite '(?<root>All tests|Selected tests)' (?<outcome>passed|failed) at " + $timestamp + '\.?$')) {
            $Recorder.RootTerminals++
            $Recorder.RootStatus = [string]$Matches.outcome
            if ($Recorder.RootName -cne [string]$Matches.root) { Add-SwiftTestEvidenceProblem $Recorder 'root-name-mismatch' }
            $Recorder.PendingRootSummary = $true
            if ($Recorder.RootTerminals -ne 1) { Add-SwiftTestEvidenceProblem $Recorder 'multiple-root-terminals' }
            return
        }
        $kind = $null; $identifier = $null
        if ($line -cmatch ("^Test Case '(?<id>[^']+)' started at " + $timestamp + '\.?$')) {
            $kind = 'started'; $identifier = [string]$Matches.id
        } elseif ($line -cmatch "^Test Case '(?<id>[^']+)' (?<outcome>passed|failed|skipped) \([0-9]+(?:\.[0-9]+)? seconds\)\.?$") {
            $kind = [string]$Matches.outcome; $identifier = [string]$Matches.id
        } elseif ($line.StartsWith("Test Case '", [StringComparison]::Ordinal)) {
            Add-SwiftTestEvidenceProblem $Recorder 'unsupported-case-line'; return
        }
        if ($null -eq $kind) { $Recorder.IgnoredLines++; return }
        if ($identifier.Length -gt $Recorder.Limits.maxIdentifierCharacters -or
            $identifier -cnotmatch '\A(?:[A-Za-z_][A-Za-z0-9_]*\.)+test[A-Za-z0-9_]+\z') {
            Add-SwiftTestEvidenceProblem $Recorder 'unsupported-case-identifier'; return
        }
        if ($Recorder.RootStarts -ne 1 -or $Recorder.RootTerminals -ne 0) { Add-SwiftTestEvidenceProblem $Recorder 'case-outside-root' }
        if (($kind -ceq 'started' -and $Recorder.CaseStarts -ge $Recorder.Limits.maxCaseObservations) -or
            ($kind -cne 'started' -and $Recorder.CaseTerminals -ge $Recorder.Limits.maxCaseObservations)) {
            Add-SwiftTestEvidenceProblem $Recorder 'case-event-limit'; return
        }
        if (-not $Recorder.Cases.ContainsKey($identifier)) {
            if ($Recorder.Cases.Count -ge $Recorder.Limits.maxCasesPerShard) {
                Add-SwiftTestEvidenceProblem $Recorder 'case-limit'; return
            }
            $Recorder.Cases.Add($identifier, [pscustomobject]@{
                caseId = $identifier; started = 0; passed = 0; failed = 0; skipped = 0
                pending = 0; unmatchedTerminals = 0
            })
        }
        $entry = $Recorder.Cases[$identifier]
        if ($kind -ceq 'started') {
            $Recorder.CaseStarts++
            if ($entry.pending -gt 0) { Add-SwiftTestEvidenceProblem $Recorder 'overlapping-case-start' }
            $entry.started++; $entry.pending++
        } else {
            $Recorder.CaseTerminals++
            if ($entry.pending -eq 0) {
                Add-SwiftTestEvidenceProblem $Recorder 'outcome-without-start'
                $entry.unmatchedTerminals++
            } else { $entry.pending-- }
            $entry.$kind++
        }
    } catch {
        try { Add-SwiftTestEvidenceProblem $Recorder 'observer-error' } catch { }
    }
}

function Complete-SwiftTestEvidenceRecorder {
    param($Recorder, [AllowNull()]$WrapperExitCode)
    if ($null -eq $Recorder) { throw 'test-evidence-recorder-missing' }
    if ($Recorder.RootStarts -ne 1 -or $Recorder.RootTerminals -ne 1 -or
        $Recorder.PendingRootSummary -or $null -eq $Recorder.Reported) { Add-SwiftTestEvidenceProblem $Recorder 'incomplete-root-run' }
    $cases = @(foreach ($id in @($Recorder.Cases.Keys | Sort-Object -CaseSensitive)) {
        $entry = $Recorder.Cases[$id]
        [pscustomobject][ordered]@{
            caseId = $id; started = $entry.started; passed = $entry.passed
            failed = $entry.failed; skipped = $entry.skipped; unfinished = $entry.pending
            unmatchedTerminals = $entry.unmatchedTerminals
        }
    })
    $observed = [ordered]@{ started = 0; passed = 0; failed = 0; skipped = 0; unfinished = 0; distinctIds = $cases.Count; repeatedExecutions = 0 }
    foreach ($entry in $cases) {
        foreach ($key in @('started', 'passed', 'failed', 'skipped', 'unfinished')) { $observed[$key] += $entry.$key }
        $observed.repeatedExecutions += [Math]::Max(0, $entry.started - 1)
    }
    if ($observed.unfinished -ne 0) { Add-SwiftTestEvidenceProblem $Recorder 'unfinished-cases' }
    if ($null -ne $Recorder.Reported) {
        $reported = $Recorder.Reported
        if ($reported.tests -ne ($observed.passed + $observed.failed + $observed.skipped) -or
            $reported.tests -ne $observed.started -or $reported.skipped -ne $observed.skipped -or
            $reported.failures -lt $observed.failed -or $reported.unexpectedFailures -gt $reported.failures -or
            ($reported.failures -gt 0 -and $observed.failed -eq 0) -or
            ($reported.failures -eq 0 -and $observed.failed -ne 0) -or
            ($reported.failures -gt 0 -and $Recorder.RootStatus -cne 'failed') -or
            ($reported.failures -eq 0 -and $Recorder.RootStatus -cne 'passed')) { Add-SwiftTestEvidenceProblem $Recorder 'framework-count-mismatch' }
        if ($WrapperExitCode -eq 0 -and $Recorder.RootStatus -ceq 'failed') { Add-SwiftTestEvidenceProblem $Recorder 'wrapper-framework-disagreement' }
    }
    if ($null -eq $WrapperExitCode) { Add-SwiftTestEvidenceProblem $Recorder 'wrapper-exit-unavailable' }
    [pscustomobject][ordered]@{
        schemaVersion = 1; kind = 'corelogic-xctest-shard'; index = $Recorder.Index
        startedUtcEpochMilliseconds = $Recorder.StartedUtcEpochMilliseconds
        finishedUtcEpochMilliseconds = Get-SwiftTestEvidenceEpochMilliseconds
        wrapperExitCode = $WrapperExitCode
        exitObservation = 'powershell-wrapper; with-swift-forwarding; no-direct-swift-or-xctest-handle'
        complete = ($Recorder.Problems.Count -eq 0); rootStatus = $Recorder.RootStatus
        reported = $Recorder.Reported; observed = [pscustomobject]$observed
        cases = $cases; problems = @($Recorder.Problems.ToArray())
        output = [pscustomobject][ordered]@{
            source = 'decoded-stdout-objects-before-Out-Host'
            objects = $Recorder.OutputObjects; nonStringObjects = $Recorder.NonStringObjects; ignoredLines = $Recorder.IgnoredLines
            rawBytesObserved = $false; stderrObserved = $false
        }
        swiftTesting = [pscustomobject][ordered]@{ markerObserved = $Recorder.SwiftTestingMarkerObserved; status = 'not-instrumented'; counts = $null }
    }
}

function Assert-SwiftTestEvidenceGeneratedFilter {
    param([string]$Filter, [string[]]$Targets)
    if ($Filter.Length -gt 8192 -or $Targets.Count -lt 1 -or $Targets.Count -gt 512) { throw 'test-evidence-filter-limit' }
    foreach ($name in $Targets) {
        if ($name.Length -gt 256 -or $name -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*\z') { throw 'test-evidence-target-invalid' }
    }
    if ($Targets.Count -eq 1) {
        if ($Filter -ceq $Targets[0]) { return }
        if ($Filter -cmatch '\A(?<target>[A-Za-z_][A-Za-z0-9_]*)/\(test[A-Za-z0-9_]+(?:\|test[A-Za-z0-9_]+)*\)\z' -and
            $Matches.target -ceq $Targets[0]) { return }
    } else {
        $expected = '(^|[./])(' + ($Targets -join '|') + ')([./]|$)'
        if ($Filter -ceq $expected) { return }
    }
    # Accept only the three forms generated by test.ps1, not arbitrary regex
    # payloads or path-like text that happens to use ASCII punctuation.
    throw 'test-evidence-filter-not-generated'
}

function New-SwiftTestEvidenceSession {
    param([string]$WorkspaceRoot, [string]$Directory, [object[]]$Shards, [int]$StartShard, $SessionId)
    if ($PSBoundParameters.ContainsKey('SessionId') -and
        ($SessionId -isnot [string] -or $SessionId -cnotmatch '\A[0-9a-f]{32}\z')) { throw 'test-evidence-session-id-invalid' }
    $limits = Get-SwiftTestEvidenceLimits
    if ($Shards.Count -lt 1 -or $Shards.Count -gt $limits.maxShards -or $StartShard -lt 1 -or $StartShard -gt $Shards.Count) { throw 'test-evidence-plan-limit' }
    $planShards = @(for ($i = 0; $i -lt $Shards.Count; $i++) {
        $shard = $Shards[$i]
        $names = @($shard.Targets | ForEach-Object { [string]$_.Name })
        if ($names.Count -lt 1 -or $names.Count -gt 512) { throw 'test-evidence-target-limit' }
        foreach ($name in $names) {
            if ($name.Length -gt 256 -or $name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$') { throw 'test-evidence-target-invalid' }
        }
        $filter = [string]$shard.Filter
        Assert-SwiftTestEvidenceGeneratedFilter $filter $names
        [pscustomobject][ordered]@{ index = $i + 1; targets = $names; filter = $filter }
    })
    $path = New-SwiftTestEvidenceDirectory $WorkspaceRoot $Directory
    if (-not $PSBoundParameters.ContainsKey('SessionId')) { $SessionId = [Guid]::NewGuid().ToString('N') }
    $metadata = Get-SwiftTestEvidenceMetadata $WorkspaceRoot
    $plan = [pscustomobject][ordered]@{
        schemaVersion = 1; kind = 'corelogic-xctest-plan'; sessionId = $sessionId
        createdUtcEpochMilliseconds = Get-SwiftTestEvidenceEpochMilliseconds
        scope = 'CoreLogic-sharded-invocations-and-observed-XCTest-stdout'
        metadata = $metadata; startShard = $StartShard; shards = $planShards
        portable = 'not-instrumented'; swiftTesting = 'counts-not-instrumented'; powershellFixtures = 'not-instrumented'
    }
    $bytes = Write-SwiftTestEvidenceJsonNew (Join-Path $path 'plan.json') $plan
    [pscustomobject]@{
        Directory = $path; WorkspaceRoot = $WorkspaceRoot; Plan = $plan; Limits = $limits
        Results = [Collections.Generic.List[object]]::new()
        WrittenStartIndices = [Collections.Generic.HashSet[int]]::new()
        Problems = [Collections.Generic.List[string]]::new()
        BytesWritten = $bytes; Finalized = $false
    }
}

function Start-SwiftTestEvidenceShard {
    param($Session, [int]$Index)
    $recorder = New-SwiftTestEvidenceRecorder $Index
    try {
        if ($Session.Finalized -or $Index -lt $Session.Plan.startShard -or $Index -gt $Session.Plan.shards.Count -or
            $Session.WrittenStartIndices.Contains($Index)) { throw 'shard-start-index' }
        $start = [pscustomobject][ordered]@{
            schemaVersion = 1; kind = 'corelogic-xctest-shard-start'
            sessionId = $Session.Plan.sessionId; index = $Index
            startedUtcEpochMilliseconds = $recorder.StartedUtcEpochMilliseconds
        }
        $startBytes = [Text.UTF8Encoding]::new($false, $true).GetByteCount((ConvertTo-SwiftTestEvidenceJson $start) + [char]10)
        if ($Session.BytesWritten + $startBytes -gt $Session.Limits.maxSessionBytes - 65536) { throw 'session-byte-limit' }
        $Session.BytesWritten += Write-SwiftTestEvidenceJsonNew (Join-Path $Session.Directory ("shard-{0:d4}-start.json" -f $Index)) $start
        [void]$Session.WrittenStartIndices.Add($Index)
    } catch { Add-SwiftTestEvidenceProblem $Session 'shard-start-write-failed' }
    return $recorder
}

function Save-SwiftTestEvidenceShard {
    param($Session, $Recorder, [AllowNull()]$WrapperExitCode)
    try {
        $result = Complete-SwiftTestEvidenceRecorder $Recorder $WrapperExitCode
        if ($Session.Finalized -or -not $Session.WrittenStartIndices.Contains([int]$Recorder.Index) -or
            $Session.Results.Count -ge $Session.Limits.maxShards -or
            @($Session.Results | Where-Object { $_.index -eq $Recorder.Index }).Count -ne 0) { throw 'shard-limit' }
        $caseCount = $result.observed.started
        $caseTerminals = $result.observed.passed + $result.observed.failed + $result.observed.skipped
        $caseRecords = $result.cases.Count
        foreach ($old in $Session.Results) {
            $caseCount += $old.observed.started; $caseRecords += $old.cases.Count
            $caseTerminals += $old.observed.passed + $old.observed.failed + $old.observed.skipped
        }
        if ($caseCount -gt $Session.Limits.maxCaseObservations -or $caseRecords -gt $Session.Limits.maxCaseObservations -or
            $caseTerminals -gt $Session.Limits.maxCaseObservations) { throw 'case-observation-limit' }
        $encoded = [Text.UTF8Encoding]::new($false, $true).GetBytes((ConvertTo-SwiftTestEvidenceJson $result) + "`n")
        if ($Session.BytesWritten + $encoded.Length -gt $Session.Limits.maxSessionBytes - 65536) { throw 'session-byte-limit' }
        $Session.BytesWritten += Write-SwiftTestEvidenceJsonNew (Join-Path $Session.Directory ("shard-{0:d4}-result.json" -f $Recorder.Index)) $result
        [void]$Session.Results.Add($result)
    } catch { Add-SwiftTestEvidenceProblem $Session 'shard-result-write-failed' }
}

function Complete-SwiftTestEvidenceSession {
    param($Session, [AllowNull()]$TestScriptExitCode)
    try {
        if ($Session.Finalized) { throw 'already-finalized' }
        $Session.Finalized = $true
        $totals = [ordered]@{ started = 0; passed = 0; failed = 0; skipped = 0; unfinished = 0; distinctIds = 0; repeatedExecutions = 0 }
        $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $startedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $indices = [Collections.Generic.HashSet[int]]::new()
        $complete = $Session.Problems.Count -eq 0
        foreach ($result in $Session.Results) {
            if (-not $indices.Add([int]$result.index)) { $complete = $false }
            foreach ($key in @('started', 'passed', 'failed', 'skipped', 'unfinished')) { $totals[$key] += $result.observed.$key }
            foreach ($entry in $result.cases) {
                [void]$ids.Add([string]$entry.caseId)
                if ($entry.started -gt 0) { [void]$startedIds.Add([string]$entry.caseId) }
            }
            if (-not $result.complete) { $complete = $false }
        }
        $totals.distinctIds = $ids.Count
        $totals.repeatedExecutions = [Math]::Max(0, $totals.started - $startedIds.Count)
        $unstarted = @($Session.Plan.shards | Where-Object { -not $Session.WrittenStartIndices.Contains([int]$_.index) } | ForEach-Object { [int]$_.index })
        $startedWithoutResult = @($Session.WrittenStartIndices | Where-Object { -not $indices.Contains($_) } | Sort-Object)
        $afterPins = @(Get-SwiftTestEvidenceSourcePins $Session.WorkspaceRoot)
        if (@($afterPins | Where-Object { $_.status -cne 'observed' }).Count -ne 0 -or
            @($Session.Plan.metadata.sourceFiles | Where-Object { $_.status -cne 'observed' }).Count -ne 0) {
            Add-SwiftTestEvidenceProblem $Session 'source-files-unavailable'; $complete = $false
        }
        if ((ConvertTo-SwiftTestEvidenceJson $afterPins) -cne (ConvertTo-SwiftTestEvidenceJson $Session.Plan.metadata.sourceFiles)) {
            Add-SwiftTestEvidenceProblem $Session 'source-files-changed'; $complete = $false
        }
        if ($unstarted.Count -ne 0 -or $startedWithoutResult.Count -ne 0 -or $Session.Plan.startShard -ne 1 -or
            $null -eq $TestScriptExitCode) { $complete = $false }
        $summary = [pscustomobject][ordered]@{
            schemaVersion = 1; kind = 'corelogic-xctest-summary'; sessionId = $Session.Plan.sessionId
            finishedUtcEpochMilliseconds = Get-SwiftTestEvidenceEpochMilliseconds; scope = $Session.Plan.scope
            plannedShards = $Session.Plan.shards.Count; completedShards = $Session.Results.Count
            startShard = $Session.Plan.startShard; unstartedShardIndices = $unstarted
            startedWithoutResultShardIndices = $startedWithoutResult
            testScriptExitCode = $TestScriptExitCode; evidenceCompleteForDeclaredScope = $complete
            observed = [pscustomobject]$totals
            completeCounts = if ($complete) { [pscustomobject]$totals } else { $null }
            problems = @($Session.Problems.ToArray()); sourceFilesAfter = $afterPins
            portable = 'not-instrumented'; swiftTesting = 'counts-not-instrumented'; powershellFixtures = 'not-instrumented'
        }
        $summaryBytes = [Text.UTF8Encoding]::new($false, $true).GetByteCount((ConvertTo-SwiftTestEvidenceJson $summary) + [char]10)
        if ($Session.BytesWritten + $summaryBytes -gt $Session.Limits.maxSessionBytes) { throw 'session-byte-limit' }
        $Session.BytesWritten += Write-SwiftTestEvidenceJsonNew (Join-Path $Session.Directory 'summary.json') $summary 65536
    } catch { Add-SwiftTestEvidenceProblem $Session 'summary-write-failed' }
}

function Assert-SwiftTestEvidenceString {
    param($Value, [string]$Pattern, [int]$Maximum = 256, [switch]$Nullable)
    if ($null -eq $Value -and $Nullable) { return }
    if ($Value -isnot [string] -or $Value.Length -gt $Maximum -or $Value -cmatch '[^\x20-\x7e]' -or $Value -cnotmatch $Pattern) {
        throw 'test-evidence-schema-string'
    }
}

function Assert-SwiftTestEvidenceLiteral {
    param($Value, [string]$Expected)
    if ($Value -isnot [string] -or -not [string]::Equals($Value, $Expected, [StringComparison]::Ordinal)) {
        throw 'test-evidence-schema-literal'
    }
}

function Assert-SwiftTestEvidencePins {
    param($Pins)
    if ($Pins -isnot [array] -or $Pins.Count -ne 5) { throw 'test-evidence-source-pins' }
    $expected = @('scripts/test.ps1', 'scripts/swift-test-evidence.ps1',
        'scripts/agent-check.ps1', 'scripts/with-swift.ps1', 'Package.swift')
    for ($i = 0; $i -lt $expected.Count; $i++) {
        $pin = $Pins[$i]
        Assert-SwiftTestEvidenceKeys $pin @('path', 'status', 'bytes', 'sha256')
        Assert-SwiftTestEvidenceLiteral $pin.path $expected[$i]
        Assert-SwiftTestEvidenceString $pin.status '\A(?:observed|unavailable)\z' 11
        if ($pin.status -ceq 'observed') {
            Assert-SwiftTestEvidenceInteger $pin.bytes 0 4194304
            Assert-SwiftTestEvidenceString $pin.sha256 '^[0-9a-f]{64}$' 64
        } elseif ($null -ne $pin.bytes -or $null -ne $pin.sha256) { throw 'test-evidence-source-pin-unknown' }
    }
}

function Assert-SwiftTestEvidenceMetadata {
    param($Metadata)
    Assert-SwiftTestEvidenceKeys $Metadata @('workspaceId', 'powershellVersion', 'osVersion', 'is64BitProcess',
        'expectedCommit', 'runId', 'runAttempt', 'imageOS', 'imageVersion', 'runnerOS', 'runnerArchitecture',
        'swiftVersionSelector', 'swiftBuildSelector', 'sourceAssociation', 'compilerIdentity', 'runtimeGitIdentity', 'sourceFiles')
    Assert-SwiftTestEvidenceString $Metadata.workspaceId '^[0-9a-f]{64}$' 64
    Assert-SwiftTestEvidenceString $Metadata.powershellVersion '^[0-9A-Za-z.+-]+$' 80
    Assert-SwiftTestEvidenceString $Metadata.osVersion '^[0-9.]+$' 80
    if ($Metadata.is64BitProcess -isnot [bool]) { throw 'test-evidence-schema-bool' }
    Assert-SwiftTestEvidenceString $Metadata.expectedCommit '^[0-9a-f]{40}$' 40 -Nullable
    Assert-SwiftTestEvidenceString $Metadata.runId '^[0-9]{1,20}$' 20 -Nullable
    Assert-SwiftTestEvidenceString $Metadata.runAttempt '^[0-9]{1,8}$' 8 -Nullable
    foreach ($key in @('imageOS', 'imageVersion', 'runnerOS', 'runnerArchitecture', 'swiftVersionSelector', 'swiftBuildSelector')) {
        Assert-SwiftTestEvidenceString $Metadata.$key '^[A-Za-z0-9_.+-]+$' 128 -Nullable
    }
    Assert-SwiftTestEvidenceLiteral $Metadata.sourceAssociation 'working-file-hashes; expected-ci-commit-only; not-binary-attestation'
    Assert-SwiftTestEvidenceLiteral $Metadata.compilerIdentity 'not-observed'
    Assert-SwiftTestEvidenceLiteral $Metadata.runtimeGitIdentity 'not-observed'
    Assert-SwiftTestEvidencePins $Metadata.sourceFiles
}

function Assert-SwiftTestEvidenceProblems {
    param($Problems)
    if ($Problems -isnot [array] -or $Problems.Count -gt 64) { throw 'test-evidence-problems-array' }
    $known = @('output-object-limit', 'non-string-output', 'line-character-limit', 'missing-root-footer',
        'multiple-root-runs', 'multiple-root-terminals', 'root-name-mismatch', 'unsupported-case-line', 'unsupported-case-identifier',
        'case-outside-root', 'case-limit', 'overlapping-case-start', 'outcome-without-start', 'case-event-limit',
        'observer-error', 'incomplete-root-run', 'unfinished-cases', 'framework-count-mismatch',
        'wrapper-framework-disagreement', 'wrapper-exit-unavailable', 'shard-start-write-failed',
        'shard-result-write-failed', 'source-files-changed', 'source-files-unavailable', 'summary-write-failed', 'observer-call-failed')
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($problem in $Problems) {
        if ($problem -isnot [string] -or $known -cnotcontains $problem -or -not $seen.Add($problem)) { throw 'test-evidence-problem-code' }
    }
}

function Assert-SwiftTestEvidenceCounts {
    param($Counts)
    Assert-SwiftTestEvidenceKeys $Counts @('started', 'passed', 'failed', 'skipped', 'unfinished', 'distinctIds', 'repeatedExecutions')
    foreach ($key in @('started', 'passed', 'failed', 'skipped', 'unfinished', 'distinctIds', 'repeatedExecutions')) {
        Assert-SwiftTestEvidenceInteger $Counts.$key 0 20000
    }
}

function Get-SwiftTestEvidenceCaseCounts {
    param([object[]]$Cases)
    if ($Cases.Count -gt 20000) { throw 'test-evidence-case-record-limit' }
    $totals = [ordered]@{ started = 0; passed = 0; failed = 0; skipped = 0; unfinished = 0; distinctIds = 0; repeatedExecutions = 0 }
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $startedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Cases) {
        Assert-SwiftTestEvidenceKeys $entry @('caseId', 'started', 'passed', 'failed', 'skipped', 'unfinished', 'unmatchedTerminals')
        Assert-SwiftTestEvidenceString $entry.caseId '^(?:[A-Za-z_][A-Za-z0-9_]*\.)+test[A-Za-z0-9_]+$'
        foreach ($key in @('started', 'passed', 'failed', 'skipped', 'unfinished')) {
            Assert-SwiftTestEvidenceInteger $entry.$key 0 20000
            $totals[$key] += $entry.$key
        }
        Assert-SwiftTestEvidenceInteger $entry.unmatchedTerminals 0 20000
        $terminals = $entry.passed + $entry.failed + $entry.skipped
        if ($entry.unmatchedTerminals -gt $terminals -or
            $entry.unfinished -ne ($entry.started - ($terminals - $entry.unmatchedTerminals))) {
            throw 'test-evidence-unfinished-count'
        }
        [void]$ids.Add([string]$entry.caseId)
        if ($entry.started -gt 0) { [void]$startedIds.Add([string]$entry.caseId) }
    }
    if ($totals.started -gt 20000 -or ($totals.passed + $totals.failed + $totals.skipped) -gt 20000) { throw 'test-evidence-case-total-limit' }
    $totals.distinctIds = $ids.Count
    $totals.repeatedExecutions = [Math]::Max(0, $totals.started - $startedIds.Count)
    return [pscustomobject]$totals
}

function Assert-SwiftTestEvidenceResult {
    param($Result)
    Assert-SwiftTestEvidenceKeys $Result @('schemaVersion', 'kind', 'index', 'startedUtcEpochMilliseconds',
        'finishedUtcEpochMilliseconds', 'wrapperExitCode', 'exitObservation', 'complete', 'rootStatus',
        'reported', 'observed', 'cases', 'problems', 'output', 'swiftTesting')
    Assert-SwiftTestEvidenceInteger $Result.schemaVersion 1 1
    Assert-SwiftTestEvidenceLiteral $Result.kind 'corelogic-xctest-shard'
    Assert-SwiftTestEvidenceLiteral $Result.exitObservation 'powershell-wrapper; with-swift-forwarding; no-direct-swift-or-xctest-handle'
    Assert-SwiftTestEvidenceInteger $Result.index 1 512
    Assert-SwiftTestEvidenceInteger $Result.startedUtcEpochMilliseconds 0 9007199254740991
    Assert-SwiftTestEvidenceInteger $Result.finishedUtcEpochMilliseconds $Result.startedUtcEpochMilliseconds 9007199254740991
    if ($null -ne $Result.wrapperExitCode) { Assert-SwiftTestEvidenceInteger $Result.wrapperExitCode -2147483648 2147483647 }
    if ($Result.complete -isnot [bool]) { throw 'test-evidence-result-status' }
    Assert-SwiftTestEvidenceString $Result.rootStatus '\A(?:passed|failed)\z' 6 -Nullable
    Assert-SwiftTestEvidenceProblems $Result.problems
    if ($Result.cases -isnot [array] -or $Result.cases.Count -gt 2048) { throw 'test-evidence-cases-array' }
    $caseIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Result.cases) { if (-not $caseIds.Add([string]$entry.caseId)) { throw 'test-evidence-duplicate-case-record' } }
    $computed = Get-SwiftTestEvidenceCaseCounts $Result.cases
    Assert-SwiftTestEvidenceCounts $Result.observed
    if ((ConvertTo-SwiftTestEvidenceJson $computed) -cne (ConvertTo-SwiftTestEvidenceJson $Result.observed)) { throw 'test-evidence-result-counts' }
    Assert-SwiftTestEvidenceKeys $Result.output @('source', 'objects', 'nonStringObjects', 'ignoredLines', 'rawBytesObserved', 'stderrObserved')
    Assert-SwiftTestEvidenceLiteral $Result.output.source 'decoded-stdout-objects-before-Out-Host'
    if ($Result.output.rawBytesObserved -isnot [bool] -or $Result.output.rawBytesObserved -or
        $Result.output.stderrObserved -isnot [bool] -or $Result.output.stderrObserved) { throw 'test-evidence-output-claim' }
    foreach ($key in @('objects', 'nonStringObjects', 'ignoredLines')) { Assert-SwiftTestEvidenceInteger $Result.output.$key 0 1000000 }
    $minimumObjects = $computed.started + $computed.passed + $computed.failed + $computed.skipped +
        $Result.output.nonStringObjects + $Result.output.ignoredLines
    if ($Result.complete) { $minimumObjects += 3 }
    if ($Result.output.objects -lt $minimumObjects -or ($Result.complete -and $Result.output.nonStringObjects -ne 0)) {
        throw 'test-evidence-output-counts'
    }
    Assert-SwiftTestEvidenceKeys $Result.swiftTesting @('markerObserved', 'status', 'counts')
    Assert-SwiftTestEvidenceLiteral $Result.swiftTesting.status 'not-instrumented'
    if ($Result.swiftTesting.markerObserved -isnot [bool] -or
        $null -ne $Result.swiftTesting.counts) { throw 'test-evidence-swift-testing-claim' }
    if ($null -ne $Result.reported) {
        Assert-SwiftTestEvidenceKeys $Result.reported @('tests', 'skipped', 'failures', 'unexpectedFailures')
        foreach ($key in @('tests', 'skipped', 'failures', 'unexpectedFailures')) { Assert-SwiftTestEvidenceInteger $Result.reported.$key 0 99999999 }
    }
    if ($Result.complete) {
        if ($Result.problems.Count -ne 0 -or $null -eq $Result.wrapperExitCode -or $null -eq $Result.reported -or
            $computed.unfinished -ne 0 -or
            @($Result.cases | Where-Object { $_.unmatchedTerminals -ne 0 }).Count -ne 0 -or
            $computed.started -ne ($computed.passed + $computed.failed + $computed.skipped) -or
            $Result.reported.tests -ne $computed.started -or $Result.reported.skipped -ne $computed.skipped -or
            $Result.reported.failures -lt $computed.failed -or $Result.reported.unexpectedFailures -gt $Result.reported.failures -or
            ($Result.reported.failures -gt 0 -and $computed.failed -eq 0) -or
            ($Result.reported.failures -eq 0 -and $Result.rootStatus -cne 'passed') -or
            ($Result.reported.failures -gt 0 -and $Result.rootStatus -cne 'failed') -or
            ($Result.wrapperExitCode -eq 0 -and $Result.rootStatus -ceq 'failed')) {
            throw 'test-evidence-false-completeness'
        }
    }
}

function Read-SwiftTestEvidencePlan {
    param([string]$WorkspaceRoot, [string]$Directory)
    $path = Resolve-SwiftTestEvidenceDirectory $WorkspaceRoot $Directory
    $plan = Read-SwiftTestEvidenceJson (Join-Path $path 'plan.json')
    Assert-SwiftTestEvidenceKeys $plan @('schemaVersion', 'kind', 'sessionId', 'createdUtcEpochMilliseconds',
        'scope', 'metadata', 'startShard', 'shards', 'portable', 'swiftTesting', 'powershellFixtures')
    Assert-SwiftTestEvidenceInteger $plan.schemaVersion 1 1
    Assert-SwiftTestEvidenceLiteral $plan.kind 'corelogic-xctest-plan'
    Assert-SwiftTestEvidenceLiteral $plan.scope 'CoreLogic-sharded-invocations-and-observed-XCTest-stdout'
    Assert-SwiftTestEvidenceLiteral $plan.portable 'not-instrumented'
    Assert-SwiftTestEvidenceLiteral $plan.swiftTesting 'counts-not-instrumented'
    Assert-SwiftTestEvidenceLiteral $plan.powershellFixtures 'not-instrumented'
    Assert-SwiftTestEvidenceString $plan.sessionId '^[0-9a-f]{32}$' 32
    Assert-SwiftTestEvidenceInteger $plan.createdUtcEpochMilliseconds 0 9007199254740991
    Assert-SwiftTestEvidenceMetadata $plan.metadata
    $expectedWorkspaceId = (Get-SwiftTestEvidenceMetadata $WorkspaceRoot).workspaceId
    if ($plan.metadata.workspaceId -cne $expectedWorkspaceId) { throw 'test-evidence-workspace-mismatch' }
    if ($plan.shards -isnot [array] -or $plan.shards.Count -lt 1 -or $plan.shards.Count -gt 512) { throw 'test-evidence-plan-limit' }
    Assert-SwiftTestEvidenceInteger $plan.startShard 1 $plan.shards.Count
    for ($i = 0; $i -lt $plan.shards.Count; $i++) {
        $shard = $plan.shards[$i]
        Assert-SwiftTestEvidenceKeys $shard @('index', 'targets', 'filter')
        Assert-SwiftTestEvidenceInteger $shard.index 1 512
        if ($shard.index -ne $i + 1 -or $shard.targets -isnot [array] -or $shard.targets.Count -lt 1 -or $shard.targets.Count -gt 512) {
            throw 'test-evidence-plan-shard'
        }
        foreach ($name in $shard.targets) { Assert-SwiftTestEvidenceString $name '^[A-Za-z_][A-Za-z0-9_]*$' }
        Assert-SwiftTestEvidenceString $shard.filter '^[A-Za-z0-9_./^$|()\[\]]+$' 8192
        Assert-SwiftTestEvidenceGeneratedFilter $shard.filter $shard.targets
    }
    return $plan
}

function Read-SwiftTestEvidenceBundle {
    param([string]$WorkspaceRoot, [string]$Directory)
    $path = Resolve-SwiftTestEvidenceDirectory $WorkspaceRoot $Directory
    if (-not [IO.Directory]::Exists($path)) { throw 'test-evidence-directory-missing' }
    $files = [Collections.Generic.List[string]]::new()
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $totalBytes = 0L
    foreach ($file in [IO.Directory]::EnumerateFileSystemEntries($path)) {
        if ($files.Count -ge 1027) { throw 'test-evidence-file-count-limit' }
        [void]$files.Add($file)
        $name = [IO.Path]::GetFileName($file)
        if (-not $names.Add($name)) { throw 'test-evidence-member-alias' }
        if (([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'test-evidence-member-reparse' }
        if ($name -ceq 'published' -and [IO.Directory]::Exists($file)) { continue }
        if (-not [IO.File]::Exists($file) -or
            ($name -cnotin @('plan.json', 'summary.json') -and $name -cnotmatch '^shard-[0-9]{4}-(start|result)\.json$')) {
            throw 'test-evidence-unexpected-member'
        }
        $length = ([IO.FileInfo]$file).Length
        if ($length -gt 1048576) { throw 'test-evidence-json-limit' }
        $totalBytes += $length
        if ($totalBytes -gt 16777216) { throw 'test-evidence-total-read-limit' }
    }
    $plan = Read-SwiftTestEvidencePlan $WorkspaceRoot $path
    $results = [Collections.Generic.List[object]]::new()
    $started = [Collections.Generic.HashSet[int]]::new()
    $finished = [Collections.Generic.HashSet[int]]::new()
    foreach ($file in $files) {
        $name = [IO.Path]::GetFileName($file)
        if ($name -cmatch '^shard-(?<index>[0-9]{4})-start\.json$') {
            $index = [int]$Matches.index
            if ($index -lt $plan.startShard -or $index -gt $plan.shards.Count -or -not $started.Add($index)) { throw 'test-evidence-start-index' }
            $start = Read-SwiftTestEvidenceJson $file
            Assert-SwiftTestEvidenceKeys $start @('schemaVersion', 'kind', 'sessionId', 'index', 'startedUtcEpochMilliseconds')
            Assert-SwiftTestEvidenceInteger $start.schemaVersion 1 1
            Assert-SwiftTestEvidenceInteger $start.index 1 512
            Assert-SwiftTestEvidenceLiteral $start.kind 'corelogic-xctest-shard-start'
            Assert-SwiftTestEvidenceLiteral $start.sessionId $plan.sessionId
            if ($start.index -ne $index) { throw 'test-evidence-start-binding' }
            Assert-SwiftTestEvidenceInteger $start.startedUtcEpochMilliseconds $plan.createdUtcEpochMilliseconds 9007199254740991
        }
    }
    foreach ($file in $files | Sort-Object -CaseSensitive) {
        $name = [IO.Path]::GetFileName($file)
        if ($name -cmatch '^shard-(?<index>[0-9]{4})-result\.json$') {
            $index = [int]$Matches.index
            if (-not $started.Contains($index) -or -not $finished.Add($index)) { throw 'test-evidence-result-index' }
            $result = Read-SwiftTestEvidenceJson $file
            Assert-SwiftTestEvidenceResult $result
            if ($result.index -ne $index) { throw 'test-evidence-result-binding' }
            $start = Read-SwiftTestEvidenceJson (Join-Path $path ("shard-{0:d4}-start.json" -f $index))
            if ($result.startedUtcEpochMilliseconds -ne $start.startedUtcEpochMilliseconds) { throw 'test-evidence-start-time-binding' }
            [void]$results.Add($result)
        }
    }
    $allCases = @($results | ForEach-Object { $_.cases } | ForEach-Object { $_ })
    $computed = Get-SwiftTestEvidenceCaseCounts $allCases
    $summary = $null
    $summaryPath = Join-Path $path 'summary.json'
    if ([IO.File]::Exists($summaryPath)) {
        $summary = Read-SwiftTestEvidenceJson $summaryPath 65536
        Assert-SwiftTestEvidenceKeys $summary @('schemaVersion', 'kind', 'sessionId', 'finishedUtcEpochMilliseconds',
            'scope', 'plannedShards', 'completedShards', 'startShard', 'unstartedShardIndices', 'startedWithoutResultShardIndices', 'testScriptExitCode',
            'evidenceCompleteForDeclaredScope', 'observed', 'completeCounts', 'problems', 'sourceFilesAfter',
            'portable', 'swiftTesting', 'powershellFixtures')
        Assert-SwiftTestEvidenceInteger $summary.schemaVersion 1 1
        Assert-SwiftTestEvidenceLiteral $summary.kind 'corelogic-xctest-summary'
        Assert-SwiftTestEvidenceLiteral $summary.sessionId $plan.sessionId
        foreach ($key in @('scope', 'portable', 'swiftTesting', 'powershellFixtures')) {
            Assert-SwiftTestEvidenceLiteral $summary.$key $plan.$key
        }
        Assert-SwiftTestEvidenceInteger $summary.finishedUtcEpochMilliseconds $plan.createdUtcEpochMilliseconds 9007199254740991
        Assert-SwiftTestEvidenceInteger $summary.plannedShards 1 512
        Assert-SwiftTestEvidenceInteger $summary.completedShards 0 512
        Assert-SwiftTestEvidenceInteger $summary.startShard 1 512
        if ($null -ne $summary.testScriptExitCode) { Assert-SwiftTestEvidenceInteger $summary.testScriptExitCode -2147483648 2147483647 }
        if ($summary.evidenceCompleteForDeclaredScope -isnot [bool] -or
            $summary.unstartedShardIndices -isnot [array] -or
            $summary.startedWithoutResultShardIndices -isnot [array]) { throw 'test-evidence-summary-status' }
        Assert-SwiftTestEvidenceProblems $summary.problems
        Assert-SwiftTestEvidencePins $summary.sourceFilesAfter
        Assert-SwiftTestEvidenceCounts $summary.observed
        $expectedUnstarted = @($plan.shards | Where-Object { -not $started.Contains([int]$_.index) } | ForEach-Object { [int]$_.index })
        $expectedStartedWithoutResult = @($started | Where-Object { -not $finished.Contains($_) } | Sort-Object)
        if ($summary.plannedShards -ne $plan.shards.Count -or $summary.completedShards -ne $results.Count -or
            $summary.startShard -ne $plan.startShard -or
            (ConvertTo-SwiftTestEvidenceJson $summary.unstartedShardIndices) -cne (ConvertTo-SwiftTestEvidenceJson $expectedUnstarted) -or
            (ConvertTo-SwiftTestEvidenceJson $summary.startedWithoutResultShardIndices) -cne (ConvertTo-SwiftTestEvidenceJson $expectedStartedWithoutResult) -or
            (ConvertTo-SwiftTestEvidenceJson $summary.observed) -cne (ConvertTo-SwiftTestEvidenceJson $computed)) {
            throw 'test-evidence-summary-counts'
        }
        if ($summary.evidenceCompleteForDeclaredScope) {
            if ($summary.problems.Count -ne 0 -or $plan.startShard -ne 1 -or $results.Count -ne $plan.shards.Count -or
                $null -eq $summary.testScriptExitCode -or
                @($results | Where-Object { -not $_.complete }).Count -ne 0 -or
                @($summary.sourceFilesAfter | Where-Object { $_.status -cne 'observed' }).Count -ne 0 -or
                (ConvertTo-SwiftTestEvidenceJson $summary.sourceFilesAfter) -cne (ConvertTo-SwiftTestEvidenceJson $plan.metadata.sourceFiles)) {
                throw 'test-evidence-summary-false-completeness'
            }
            Assert-SwiftTestEvidenceCounts $summary.completeCounts
            if ((ConvertTo-SwiftTestEvidenceJson $summary.completeCounts) -cne (ConvertTo-SwiftTestEvidenceJson $computed)) { throw 'test-evidence-complete-counts' }
        } elseif ($null -ne $summary.completeCounts) { throw 'test-evidence-incomplete-counts-not-null' }
    }
    [pscustomobject]@{
        Directory = $path; Plan = $plan; Summary = $summary; Results = @($results.ToArray())
        Observed = $computed
        StartedWithoutResult = @($started | Where-Object { -not $finished.Contains($_) } | Sort-Object)
    }
}

function Test-SwiftTestEvidenceComplete {
    param([string]$WorkspaceRoot, [string]$Directory)
    $bundle = Read-SwiftTestEvidenceBundle $WorkspaceRoot $Directory
    if ($null -eq $bundle.Summary -or -not $bundle.Summary.evidenceCompleteForDeclaredScope -or
        $null -eq $bundle.Summary.testScriptExitCode -or $bundle.Summary.testScriptExitCode -ne 0 -or
        @($bundle.Results | Where-Object { $null -eq $_.wrapperExitCode -or $_.wrapperExitCode -ne 0 }).Count -ne 0) {
        throw 'test-evidence-incomplete'
    }
    if ((ConvertTo-SwiftTestEvidenceJson @(Get-SwiftTestEvidenceSourcePins $WorkspaceRoot)) -cne
        (ConvertTo-SwiftTestEvidenceJson $bundle.Plan.metadata.sourceFiles)) { throw 'test-evidence-check-source-changed' }
    return $bundle
}

function Test-SwiftTestEvidenceCurrentInvocation {
    param([string]$WorkspaceRoot, [string]$Directory, $ExpectedSessionId)
    if ($ExpectedSessionId -isnot [string] -or $ExpectedSessionId -cnotmatch '\A[0-9a-f]{32}\z') {
        throw 'test-evidence-expected-session-id-invalid'
    }
    # Complete is explicitly offline consistency. Bind the caller-held request
    # to that SAME strictly parsed, complete, source-checked bundle, never a
    # separate plan read or an ID inferred from the output directory.
    $bundle = Test-SwiftTestEvidenceComplete $WorkspaceRoot $Directory
    if (-not [string]::Equals($bundle.Plan.sessionId, $ExpectedSessionId, [StringComparison]::Ordinal)) {
        throw 'test-evidence-current-request-journal-mismatch'
    }
    return $bundle
}

function Publish-SwiftTestEvidenceCI {
    param([string]$WorkspaceRoot, [string]$Directory, [string]$FullOutcome, $ExpectedSessionId, [switch]$RequireCurrentInvocation)
    if ($FullOutcome -cnotin @('', 'success', 'failure', 'cancelled', 'skipped')) { throw 'test-evidence-ci-outcome' }
    $boundCurrent = $RequireCurrentInvocation.IsPresent -or $PSBoundParameters.ContainsKey('ExpectedSessionId')
    $hasExpectedId = $false
    if ($boundCurrent -and $null -ne $ExpectedSessionId) {
        if ($ExpectedSessionId -isnot [string] -or
            ($ExpectedSessionId.Length -gt 0 -and $ExpectedSessionId -cnotmatch '\A[0-9a-f]{32}\z')) {
            throw 'test-evidence-expected-session-id-invalid'
        }
        $hasExpectedId = $ExpectedSessionId.Length -gt 0
    }
    if ($boundCurrent) {
        try { $path = Resolve-SwiftTestEvidenceDirectory $WorkspaceRoot $Directory }
        catch { throw 'test-evidence-publication-destination-invalid' }
    } else { $path = Resolve-SwiftTestEvidenceDirectory $WorkspaceRoot $Directory }
    $bundle = $null; $plan = $null
    $readStatus = if ($boundCurrent) {
        if ($hasExpectedId) { 'current-request-journal-unavailable' } else { 'current-test-invocation-not-observed' }
    } else { 'test-phase-not-reached' }
    if ([IO.Directory]::Exists($path)) {
        if ($boundCurrent) {
            $candidateBundle = $null
            try { $candidateBundle = Read-SwiftTestEvidenceBundle $WorkspaceRoot $Directory }
            catch {
                # A valid plan can establish destination ownership only. Never
                # adopt its ID, metadata, declarations or counts after a failed
                # strict bundle read, even if the caller supplied that same ID.
                try { $null = Read-SwiftTestEvidencePlan $WorkspaceRoot $Directory }
                catch { throw 'test-evidence-publication-destination-invalid' }
                $readStatus = if ($hasExpectedId) { 'invalid-or-incomplete-journal' } else { 'current-test-invocation-not-observed' }
            }
            if ($null -ne $candidateBundle) {
                if (-not $hasExpectedId) { $readStatus = 'current-test-invocation-not-observed' }
                elseif ([string]::Equals($candidateBundle.Plan.sessionId, $ExpectedSessionId, [StringComparison]::Ordinal)) {
                    # Identity, completeness and every adopted count originate
                    # from this one common strict-reader result.
                    $bundle = $candidateBundle; $plan = $bundle.Plan
                    $readStatus = if ($null -eq $bundle.Summary -or -not $bundle.Summary.evidenceCompleteForDeclaredScope) {
                        'validated-partial-journal'
                    } else { 'validated-complete-journal' }
                } else { $readStatus = 'current-request-journal-mismatch' }
            }
        } else {
            # Explicit offline compatibility: retain V1 stored-journal semantics.
            # Refuse unowned destinations; invalid producer data is never copied.
            $plan = Read-SwiftTestEvidencePlan $WorkspaceRoot $Directory
            try {
                $bundle = Read-SwiftTestEvidenceBundle $WorkspaceRoot $Directory
                $plan = $bundle.Plan
                $readStatus = if ($null -eq $bundle.Summary -or -not $bundle.Summary.evidenceCompleteForDeclaredScope) {
                    'validated-partial-journal'
                } else { 'validated-complete-journal' }
            }
            catch { $readStatus = 'invalid-or-incomplete-journal' }
        }
    } else {
        if ($boundCurrent) {
            try { $path = New-SwiftTestEvidenceDirectory $WorkspaceRoot $Directory }
            catch { throw 'test-evidence-publication-destination-invalid' }
        } else { $path = New-SwiftTestEvidenceDirectory $WorkspaceRoot $Directory }
    }
    $currentInvocation = if ($boundCurrent) {
        [pscustomobject][ordered]@{
            expectedSessionId = if ($hasExpectedId) { $ExpectedSessionId } else { $null }
            journalSessionId = if ($null -ne $bundle) { $bundle.Plan.sessionId } else { $null }
            identityStatus = if ($null -ne $bundle) { 'expected-id-match' } else { $readStatus }
            generation = 'not-independently-observed'; transport = 'not-independently-observed'
            qualification = 'caller-supplied-id-match-only; not-authenticated-freshness'
        }
    } else { $null }
    $publicationVersion = if ($boundCurrent) { 2 } else { 1 }
    $publishPath = Join-Path $path 'published'
    if ([IO.File]::Exists($publishPath) -or [IO.Directory]::Exists($publishPath)) { throw 'test-evidence-publication-exists' }
    $null = New-Item -ItemType Directory -Path $publishPath -ErrorAction Stop
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    $lines = [Collections.Generic.List[string]]::new()
    $totalBytes = 0
    if ($null -ne $bundle) {
        foreach ($result in $bundle.Results) {
            foreach ($entry in $result.cases) {
                $record = [pscustomobject][ordered]@{
                    shardIndex = $result.index; caseId = $entry.caseId
                    started = $entry.started; passed = $entry.passed; failed = $entry.failed
                    skipped = $entry.skipped; unfinished = $entry.unfinished
                    unmatchedTerminals = $entry.unmatchedTerminals
                }
                $line = ConvertTo-SwiftTestEvidenceJson $record
                $totalBytes += $encoding.GetByteCount($line + "`n")
                if ($totalBytes -gt 8388608) { throw 'test-evidence-publication-byte-limit' }
                [void]$lines.Add($line)
            }
        }
    }
    $caseBytes = $encoding.GetBytes(($lines.ToArray() -join "`n") + $(if ($lines.Count -gt 0) { "`n" } else { '' }))
    $casesPath = Join-Path $publishPath 'cases.ndjson'
    $stream = [IO.File]::Open($casesPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($caseBytes, 0, $caseBytes.Length) } finally { $stream.Dispose() }
    $related = @(foreach ($relative in @('artifacts/gallery-compare/provenance-ci-initial.json',
            'artifacts/gallery-compare/provenance.json', 'artifacts/gallery-compare/report.json')) {
        Get-SwiftTestEvidenceFilePin (Join-Path $WorkspaceRoot $relative) $relative
    })
    $testSummary = if ($null -ne $bundle) { $bundle.Summary } else { $null }
    $metadata = if ($null -ne $plan) { $plan.metadata } else { Get-SwiftTestEvidenceMetadata $WorkspaceRoot }
    $shards = @(if ($null -ne $plan) {
        foreach ($declared in $plan.shards) {
            $results = @(if ($null -ne $bundle) { $bundle.Results | Where-Object { $_.index -eq $declared.index } })
            $result = if ($results.Count -eq 1) { $results[0] } else { $null }
            $state = if ($null -eq $bundle) { 'journal-unreadable' }
                elseif ($null -ne $result) { 'result-recorded' }
                elseif ($bundle.StartedWithoutResult -contains $declared.index) { 'started-without-result' }
                else { 'no-durable-start' }
            [pscustomobject][ordered]@{
                index = $declared.index; targets = $declared.targets; filter = $declared.filter
                state = $state
                result = if ($null -ne $result) {
                    [pscustomobject][ordered]@{
                        startedUtcEpochMilliseconds = $result.startedUtcEpochMilliseconds
                        finishedUtcEpochMilliseconds = $result.finishedUtcEpochMilliseconds
                        wrapperExitCode = $result.wrapperExitCode; exitObservation = $result.exitObservation
                        complete = $result.complete; rootStatus = $result.rootStatus
                        reported = $result.reported; observed = $result.observed
                        problems = $result.problems; output = $result.output; swiftTesting = $result.swiftTesting
                    }
                } else { $null }
            }
        }
    })
    $published = [pscustomobject][ordered]@{
        schemaVersion = $publicationVersion; kind = 'ci-corelogic-xctest-evidence'
        publishedUtcEpochMilliseconds = Get-SwiftTestEvidenceEpochMilliseconds
        fullOutcome = $FullOutcome
        evidenceReadStatus = $readStatus
        metadata = $metadata
        declaredScope = 'CoreLogic-sharded-invocations-and-observed-XCTest-stdout'
        shards = $shards
        testSummary = $testSummary
        startedWithoutResult = @(if ($null -ne $bundle) { $bundle.StartedWithoutResult })
        observed = if ($null -ne $bundle) { $bundle.Observed } else { $null }
        cases = [pscustomobject][ordered]@{ path = 'cases.ndjson'; bytes = $caseBytes.Length; sha256 = Get-SwiftTestEvidenceHash $caseBytes }
        relatedEvidence = $related
        relatedEvidenceAssociation = 'existing-files-at-publication; not-verified-same-invocation'
        qualification = 'counts-for-declared-scope-only; not-Full-success-or-font-qualification'
        portable = 'not-instrumented'; swiftTesting = 'counts-not-instrumented'; powershellFixtures = 'not-instrumented'
    }
    if ($boundCurrent) { Add-Member -InputObject $published -MemberType NoteProperty -Name currentInvocation -Value $currentInvocation }
    [void](Write-SwiftTestEvidenceJsonNew (Join-Path $publishPath 'summary.json') $published)
    $publicationFiles = @(foreach ($name in @('summary.json', 'cases.ndjson')) {
        Get-SwiftTestEvidenceFilePin (Join-Path $publishPath $name) $name 8388608
    })
    if (@($publicationFiles | Where-Object { $_.status -cne 'observed' }).Count -ne 0) { throw 'test-evidence-publication-pin-failed' }
    $expectedPublicationBytes = @{
        'summary.json' = $encoding.GetBytes((ConvertTo-SwiftTestEvidenceJson $published) + "`n")
        'cases.ndjson' = $caseBytes
    }
    foreach ($pin in $publicationFiles) {
        $expectedBytes = $expectedPublicationBytes[$pin.path]
        if ($pin.bytes -ne $expectedBytes.Length -or $pin.sha256 -cne (Get-SwiftTestEvidenceHash $expectedBytes)) {
            throw 'test-evidence-publication-pin-failed'
        }
    }
    $manifest = [pscustomobject][ordered]@{
        schemaVersion = $publicationVersion; kind = 'ci-corelogic-xctest-evidence-files'
        files = $publicationFiles; fullOutcome = $FullOutcome
    }
    if ($boundCurrent) { Add-Member -InputObject $manifest -MemberType NoteProperty -Name currentInvocation -Value $currentInvocation }
    [void](Write-SwiftTestEvidenceJsonNew (Join-Path $publishPath 'manifest.json') $manifest 65536)
    $manifestBytes = $encoding.GetBytes((ConvertTo-SwiftTestEvidenceJson $manifest) + "`n")
    $manifestPin = Get-SwiftTestEvidenceFilePin (Join-Path $publishPath 'manifest.json') 'manifest.json' 65536
    if ($manifestPin.status -cne 'observed' -or $manifestPin.bytes -ne $manifestBytes.Length -or
        $manifestPin.sha256 -cne (Get-SwiftTestEvidenceHash $manifestBytes)) { throw 'test-evidence-publication-pin-failed' }
    # Return success only after all three newly created files have expected bytes
    # and hashes. Refused or partial prior publications are never adopted.
    return $published
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([string]::IsNullOrWhiteSpace($EvidenceWorkspaceRoot)) { $EvidenceWorkspaceRoot = Split-Path -Parent $PSScriptRoot }
        if ($EvidenceAction -ceq 'Check') {
            $null = Test-SwiftTestEvidenceCurrentInvocation -WorkspaceRoot $EvidenceWorkspaceRoot -Directory $ReceiptDirectory -ExpectedSessionId $ExpectedSessionId
            Write-Host 'CoreLogic XCTest evidence is complete for its declared stdout scope.'
        } elseif ($EvidenceAction -ceq 'PublishCI') {
            $null = Publish-SwiftTestEvidenceCI -WorkspaceRoot $EvidenceWorkspaceRoot -Directory $ReceiptDirectory -FullOutcome $CIOutcome -ExpectedSessionId $ExpectedSessionId -RequireCurrentInvocation
            Write-Host 'Sanitized CoreLogic XCTest evidence publication written; Full outcome is unchanged.'
        } else { throw 'test-evidence-action-required' }
        exit 0
    } catch {
        [Console]::Error.WriteLine('CoreLogic XCTest evidence action failed; no raw payload or exception is printed.')
        exit 1
    }
}
