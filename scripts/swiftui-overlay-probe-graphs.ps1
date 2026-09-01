<#
.SYNOPSIS
Retains supplemental Stage B graphs from already closed extractor invocations.
.DESCRIPTION
This adapter never launches a process. Its two sealed input documents are NOT a
baseline manifest. The original baseline primary-graph guard remains unchanged.
Only bounded metadata is materialized. Original graph bytes are authoritative;
the unchanged streaming reader preserves declaration/relationship occurrences.

Frozen input: schemaVersion=1, evidenceKind=swiftui-overlay-supplemental-graph-inputs-v1,
batchId, graphRoot, supplementalGraphInputs[]. Each entry has relativePath,
bytes, sha256, invocationId, role, emittingModule, declaringModule, bystanders,
positiveFrontendObservationIds. An unattributed-emission uses null module fields
and [] observation IDs; observed metadata is derived without upgrading its role.

Native input: schemaVersion=1, evidenceKind=swiftui-overlay-graph-native-invocations-v1,
batchId, profileSha256, executionKind, invocations[], positiveFrontendObservations[].
An invocation records invocationId, requestId, requestedModule, target, cxxMode,
control, graphDirectory, arguments, exitCode, termination, outputComplete,
candidateRecordIds and positiveFrontendObservationIds. Native facts are supplied
by the caller's sealed closure receipt, not inferred from graph filenames.

Caps are acceptance/retention checks, not OS disk quotas on the earlier producer.
The inventory writer also uses temporary disk space; no disk-quota claim is made.
Unknown ownership and empty output remain explicit review work, never API absence.
#>
. (Join-Path $PSScriptRoot 'swiftui-api-audit-common.ps1')
. (Join-Path $PSScriptRoot 'swiftui-baseline-streaming.ps1')

function Get-SwiftUIOverlayGraphLimits {
    param([AllowNull()]$Requested)
    $limits = [ordered]@{
        graphFiles = [long]4096; graphBytes = [long]1GB; totalGraphBytes = [long]8GB
        metadataBytes = [long]16MB; directories = [long]8192; depth = [long]64
        sortChunkBytes = [long]16MB; mergeFanIn = [long]16
        maximumRecordCharacters = [long]32MB
    }
    if ($null -ne $Requested) {
        if ($Requested -is [Collections.IDictionary]) { $names = @($Requested.Keys) }
        elseif ($Requested -is [pscustomobject]) { $names = @($Requested.PSObject.Properties.Name) }
        else { throw 'Supplemental graph limits must be an object.' }
        foreach ($name in $names) {
            if ($limits.Keys -cnotcontains $name) { throw "Unknown supplemental graph limit '$name'." }
            $value = $Requested.$name
            if (($value -isnot [int] -and $value -isnot [long]) -or $value -lt 1 -or $value -gt $limits[$name]) {
                throw "Supplemental graph limit '$name' may only lower its positive published ceiling."
            }
            $limits[$name] = [long]$value
        }
    }
    if ($limits.sortChunkBytes -lt 1024 -or $limits.mergeFanIn -lt 2 -or
        $limits.maximumRecordCharacters -lt 1024 -or $limits.metadataBytes -lt 1024) {
        throw 'Supplemental graph streaming limits are below the existing reader minimum.'
    }
    return [pscustomobject]$limits
}

function Assert-SwiftUIOverlayGraphPath {
    param([Parameter(Mandatory)][string]$Path,
        [ValidateSet('File', 'Directory', 'Absent')][string]$Kind)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw 'Supplemental graph paths must be absolute.' }
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    $current = $root
    $parts = $full.Substring($root.Length).Split([char[]]@([IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar), [StringSplitOptions]::RemoveEmptyEntries)
    $missing = $false
    foreach ($part in $parts) {
        $current = [IO.Path]::Combine($current, $part)
        if ($missing) { continue }
        try { $attributes = [IO.File]::GetAttributes($current) }
        catch [IO.FileNotFoundException] { $missing = $true; continue }
        catch [IO.DirectoryNotFoundException] { $missing = $true; continue }
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Supplemental graph paths cannot cross symlinks or reparse points: '$current'."
        }
    }
    if ($Kind -ceq 'Absent') {
        if (-not $missing) { throw "Supplemental output already exists: '$full'." }
    } elseif ($missing -or ($Kind -ceq 'File' -and -not [IO.File]::Exists($full)) -or
        ($Kind -ceq 'Directory' -and -not [IO.Directory]::Exists($full))) {
        throw "Missing supplemental $Kind '$full'."
    }
    return $full
}

function Resolve-SwiftUIOverlayGraphRelativePath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$RelativePath)
    if ($RelativePath.Length -gt 4096 -or $RelativePath -match '[\\:\x00-\x1f\x7f]' -or
        [IO.Path]::IsPathRooted($RelativePath)) { throw 'Invalid portable supplemental graph relative path.' }
    foreach ($part in $RelativePath.Split('/')) {
        if ($part.Length -eq 0 -or $part -ceq '.' -or $part -ceq '..' -or $part -match '[. ]$' -or
            $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or $part -match '[<>"|?*]') {
            throw 'Ambiguous or traversing supplemental graph relative path.'
        }
    }
    return [IO.Path]::GetFullPath([IO.Path]::Combine($Root, $RelativePath))
}

function Get-SwiftUIOverlayGraphHash {
    param([Parameter(Mandatory)][IO.Stream]$Stream)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $Stream.Position = 0
        return [BitConverter]::ToString($algorithm.ComputeHash($Stream)).Replace('-', '').ToLowerInvariant()
    } finally { $algorithm.Dispose(); $Stream.Position = 0 }
}

function Open-SwiftUIOverlayGraphMetadata {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ExpectedSha256,
        [Parameter(Mandatory)][long]$MaximumBytes)
    Assert-SwiftUIAuditSha256 $ExpectedSha256 'supplemental metadata seal'
    $full = Assert-SwiftUIOverlayGraphPath $Path File
    $stream = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -gt $MaximumBytes) { throw 'Supplemental metadata exceeds its byte budget.' }
        $length = $stream.Length
        $bytes = [byte[]]::new([int]$length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $count = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($count -eq 0) { throw 'Supplemental metadata was truncated while reading.' }
            $offset += $count
        }
        if ($stream.ReadByte() -ne -1 -or $stream.Length -ne $length) { throw 'Supplemental metadata changed while reading.' }
        $hash = Get-SwiftUIOverlayGraphHash $stream
        if ($hash -cne $ExpectedSha256) { throw 'Supplemental metadata SHA-256 mismatch.' }
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        Initialize-SwiftUIBaselineStreaming
        [SwiftUIBaseline.Streaming.AuditReviewPacketWriter]::ValidateMetadataObject($text, [int]$MaximumBytes)
        $arguments = @{ InputObject = $text; ErrorAction = 'Stop' }
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $arguments.DateKind = 'String' }
        return [pscustomobject]@{ path = $full; stream = $stream; bytes = $bytes; sha256 = $hash; value = (ConvertFrom-Json @arguments) }
    } catch { $stream.Dispose(); throw }
}

function Assert-SwiftUIOverlayGraphStringArray {
    param($Value, [string]$Context, [switch]$RequireNonempty, [switch]$Identifiers)
    if ($Value -isnot [Array] -or ($RequireNonempty -and $Value.Count -eq 0)) { throw "$Context must be an explicit string array." }
    foreach ($item in $Value) {
        if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item) -or $item.Length -gt 65536 -or
            ($Identifiers -and $item -cnotmatch '\A[0-9a-f]{64}\z')) { throw "Invalid entry in $Context." }
    }
}

function Assert-SwiftUIOverlayGraphModule {
    param($Value, [string]$Context)
    if ($Value -isnot [string] -or $Value -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*\z') { throw "Invalid module in $Context." }
}

function Test-SwiftUIOverlayGraphSameStrings {
    param([AllowNull()]$Left, [AllowNull()]$Right)
    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    if ($Left.Count -ne $Right.Count) { return $false }
    for ($index = 0; $index -lt $Left.Count; $index++) {
        if ($Left[$index] -cne $Right[$index]) { return $false }
    }
    return $true
}

function Get-SwiftUIOverlayGraphFileInventory {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$Limits, [switch]$RetentionLayout)
    $checkedRoot = Assert-SwiftUIOverlayGraphPath $Root Directory
    $files = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $seenPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $pending = [Collections.Generic.Stack[object]]::new()
    $pending.Push([pscustomobject]@{ path = $checkedRoot; relative = ''; depth = 0 })
    # Retention adds graphs/ and inputs/ to the producer directory count, and
    # prefixes raw graph paths with one level. Producer caps themselves stay fixed.
    $directoryLimit = $Limits.directories + $(if ($RetentionLayout) { 2 } else { 0 })
    $depthLimit = $Limits.depth + $(if ($RetentionLayout) { 1 } else { 0 })
    $fileLimit = $Limits.graphFiles + $(if ($RetentionLayout) { 5 } else { 0 })
    [long]$directories = 1
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        [void](Assert-SwiftUIOverlayGraphPath $directory.path Directory)
        $iterator = [IO.Directory]::EnumerateFileSystemEntries($directory.path).GetEnumerator()
        try {
            while ($iterator.MoveNext()) {
                $path = [string]$iterator.Current
                $relative = [IO.Path]::GetFileName($path)
                if ($directory.relative.Length -gt 0) { $relative = $directory.relative + '/' + $relative }
                [void](Resolve-SwiftUIOverlayGraphRelativePath $checkedRoot $relative)
                if (-not $seenPaths.Add($relative)) { throw 'Supplemental file or directory portable path collision.' }
                $attributes = [IO.File]::GetAttributes($path)
                if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Supplemental graph inventory contains a symlink or reparse point.' }
                if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                    $directories++
                    if ($directories -gt $directoryLimit -or $directory.depth + 1 -gt $depthLimit) { throw 'Supplemental graph directory budget exceeded.' }
                    $pending.Push([pscustomobject]@{ path = $path; relative = $relative; depth = $directory.depth + 1 })
                } else {
                    if ($files.Count -ge $fileLimit -or $files.ContainsKey($relative)) { throw 'Supplemental file count or portable path collision.' }
                    $files.Add($relative, [pscustomobject]@{ path = $path; relativePath = $relative; bytes = ([IO.FileInfo]$path).Length })
                }
            }
        } finally { $iterator.Dispose() }
    }
    return ,$files
}

function Write-SwiftUIOverlayGraphNewBytes {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    [void](Assert-SwiftUIOverlayGraphPath $Path Absent)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush() } finally { $stream.Dispose() }
}

function Get-SwiftUIOverlayGraphBinding {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$RelativePath, [string]$Kind)
    $path = Resolve-SwiftUIOverlayGraphRelativePath $Root $RelativePath
    [void](Assert-SwiftUIOverlayGraphPath $path File)
    return Get-SwiftUIAuditHashedFile -Path $path -RelativePath $RelativePath -Kind $Kind
}

function Assert-SwiftUIOverlayGraphNativeContext {
    param([Parameter(Mandatory)]$Native, [Parameter(Mandatory)][string]$BatchId,
        [Parameter(Mandatory)]$Limits, [Parameter(Mandatory)][string]$GraphRoot, [switch]$AllowSyntheticForTests)
    Assert-SwiftUIAuditFields $Native @{
        schemaVersion = 'integer'; evidenceKind = 'string'; batchId = 'string'; profileSha256 = 'string'
        executionKind = 'string'; invocations = 'array'; positiveFrontendObservations = 'array'
    } 'supplemental native context'
    if ($Native.schemaVersion -ne 1 -or $Native.evidenceKind -cne 'swiftui-overlay-graph-native-invocations-v1' -or
        $Native.batchId -cne $BatchId -or @('native', 'synthetic-test') -cnotcontains $Native.executionKind -or
        ($Native.executionKind -ceq 'synthetic-test' -and -not $AllowSyntheticForTests)) { throw 'Supplemental native context identity mismatch.' }
    Assert-SwiftUIAuditSha256 $Native.profileSha256 'supplemental profileSha256'
    if ($Native.invocations.Count -gt $Limits.graphFiles -or $Native.invocations.Count -eq 0) { throw 'Supplemental invocation count exceeds its bounded batch.' }
    $observations = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($observation in $Native.positiveFrontendObservations) {
        Assert-SwiftUIAuditFields $observation @{
            observationId = 'string'; requestId = 'string'; profileSha256 = 'string'; module = 'string'
            target = 'string'; cxxMode = 'string'; control = 'string'; candidateRecordIds = 'array'
            sourcePath = 'string'; loadedPath = 'string'; sourceSha256 = 'string'; loadedSha256 = 'string'
            activationTuple = 'object'; traceSha256 = 'string'; diagnosticsSha256 = 'string'; eligible = 'boolean'
        } 'supplemental positive frontend observation'
        foreach ($name in @('observationId', 'requestId', 'profileSha256', 'sourceSha256', 'loadedSha256', 'traceSha256', 'diagnosticsSha256')) {
            Assert-SwiftUIAuditSha256 $observation.$name "positive observation.$name"
        }
        Assert-SwiftUIOverlayGraphModule $observation.module 'positive observation'
        Assert-SwiftUIOverlayGraphStringArray $observation.candidateRecordIds 'positive candidateRecordIds' -RequireNonempty -Identifiers
        Assert-SwiftUIAuditFields $observation.activationTuple @{
            declaringModule = 'string'; bystanderModules = 'array'; overlayModule = 'string'
        } 'positive activationTuple'
        Assert-SwiftUIOverlayGraphModule $observation.activationTuple.declaringModule 'positive declaringModule'
        Assert-SwiftUIOverlayGraphStringArray $observation.activationTuple.bystanderModules 'positive bystanderModules'
        foreach ($module in $observation.activationTuple.bystanderModules) { Assert-SwiftUIOverlayGraphModule $module 'positive bystander' }
        if (-not $observation.eligible -or $observation.profileSha256 -cne $Native.profileSha256 -or
            @('owner-bystander', 'bystander-owner') -cnotcontains $observation.control -or
            @('off', 'default') -cnotcontains $observation.cxxMode -or
            $observation.target -cnotmatch '\A(?:arm64|x86_64)-apple-macosx\d+\.\d+(?:\.\d+)?\z' -or
            $observation.activationTuple.overlayModule -cne $observation.module -or $observations.ContainsKey($observation.observationId)) {
            throw 'Duplicate, ineligible or mismatched positive frontend observation.'
        }
        $observations.Add($observation.observationId, $observation)
    }
    $invocations = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $directories = [Collections.Generic.List[string]]::new()
    foreach ($invocation in $Native.invocations) {
        Assert-SwiftUIAuditFields $invocation @{
            invocationId = 'string'; requestId = 'string'; requestedModule = 'string'; target = 'string'
            cxxMode = 'string'; control = 'string'; graphDirectory = 'string'; arguments = 'array'
            exitCode = 'integer'; termination = 'string'; outputComplete = 'boolean'
            candidateRecordIds = 'array'; positiveFrontendObservationIds = 'array'
        } 'supplemental invocation'
        Assert-SwiftUIAuditSha256 $invocation.invocationId 'supplemental invocationId'
        Assert-SwiftUIAuditSha256 $invocation.requestId 'supplemental requestId'
        Assert-SwiftUIOverlayGraphModule $invocation.requestedModule 'supplemental requested module'
        Assert-SwiftUIOverlayGraphStringArray $invocation.arguments 'supplemental arguments' -RequireNonempty
        Assert-SwiftUIOverlayGraphStringArray $invocation.candidateRecordIds 'supplemental candidateRecordIds' -RequireNonempty -Identifiers
        Assert-SwiftUIOverlayGraphStringArray $invocation.positiveFrontendObservationIds 'supplemental positive IDs' -RequireNonempty -Identifiers
        if ($invocation.exitCode -ne 0 -or $invocation.termination -cne 'natural' -or -not $invocation.outputComplete -or
            $invocation.control -cne 'supplemental-direct-module' -or
            @('off', 'default') -cnotcontains $invocation.cxxMode -or
            $invocation.target -cnotmatch '\A(?:arm64|x86_64)-apple-macosx\d+\.\d+(?:\.\d+)?\z' -or
            $invocations.ContainsKey($invocation.invocationId)) { throw 'Uncertain, duplicate or unsupported supplemental invocation.' }
        $expectedOutput = Resolve-SwiftUIOverlayGraphRelativePath $GraphRoot $invocation.graphDirectory
        foreach ($pair in @(@('-module-name', $invocation.requestedModule), @('-target', $invocation.target), @('-output-dir', $expectedOutput))) {
            $argumentCount = 0
            for ($index = 0; $index -lt $invocation.arguments.Count; $index++) {
                if ($invocation.arguments[$index] -ceq $pair[0]) {
                    $argumentCount++
                    if ($index + 1 -ge $invocation.arguments.Count -or $invocation.arguments[$index + 1] -cne $pair[1]) {
                        throw 'Supplemental invocation arguments contradict recorded module, target or output directory.'
                    }
                }
            }
            if ($argumentCount -ne 1) { throw 'Supplemental invocation requires exactly one recorded module, target and output-directory argument.' }
        }
        $modeArguments = 0
        foreach ($argument in $invocation.arguments) {
            if ($argument.StartsWith('@', [StringComparison]::Ordinal)) {
                throw 'Response-file arguments cannot hide supplemental invocation context.'
            }
            foreach ($separatedOption in @('-module-name', '-target')) {
                if ($argument.StartsWith($separatedOption, [StringComparison]::Ordinal) -and $argument -cne $separatedOption) {
                    throw 'Supplemental invocation supports only separated module and target arguments.'
                }
            }
            if ($argument.StartsWith('-output-dir', [StringComparison]::Ordinal) -and $argument -cne '-output-dir') {
                throw 'Supplemental invocation supports only one separated output-directory argument.'
            }
            if ($argument.StartsWith('-cxx-interoperability-mode', [StringComparison]::Ordinal)) {
                $modeArguments++
                if ($argument -cne ('-cxx-interoperability-mode=' + $invocation.cxxMode)) {
                    throw 'Supplemental invocation Cxx argument contradicts its exact recorded mode.'
                }
            }
        }
        if ($modeArguments -ne 1) { throw 'Supplemental invocation requires exactly one joined Cxx mode argument.' }
        foreach ($prior in $directories) {
            if ($prior.Equals($invocation.graphDirectory, [StringComparison]::OrdinalIgnoreCase) -or
                $prior.StartsWith($invocation.graphDirectory + '/', [StringComparison]::OrdinalIgnoreCase) -or
                $invocation.graphDirectory.StartsWith($prior + '/', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Supplemental invocation output directories overlap.'
            }
        }
        [void]$directories.Add($invocation.graphDirectory)
        $requestedProof = $false
        foreach ($id in $invocation.positiveFrontendObservationIds) {
            if (-not $observations.ContainsKey($id)) { throw 'Missing expected positive frontend evidence.' }
            $observation = $observations[$id]
            if ($observation.requestId -cne $invocation.requestId -or $observation.target -cne $invocation.target -or
                $observation.cxxMode -cne $invocation.cxxMode) { throw 'Positive frontend evidence belongs to another invocation context.' }
            if ($observation.module -ceq $invocation.requestedModule) {
                foreach ($candidate in $invocation.candidateRecordIds) {
                    if ($observation.candidateRecordIds -cnotcontains $candidate) { throw 'Requested module positive evidence omits a candidate occurrence.' }
                }
                $requestedProof = $true
            }
        }
        if (-not $requestedProof) { throw 'Supplemental invocation lacks positive evidence for its requested module.' }
        $invocations.Add($invocation.invocationId, $invocation)
    }
    return [pscustomobject]@{ invocations = $invocations; observations = $observations }
}

function Assert-SwiftUIOverlayGraphRole {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)]$ObservedModule,
        [Parameter(Mandatory)]$Invocation, [Parameter(Mandatory)]$Context)
    $bystanderProperty = $ObservedModule.PSObject.Properties['bystanders']
    if ($null -ne $bystanderProperty -and $bystanderProperty.Name -cne 'bystanders') { $bystanderProperty = $null }
    $observedBystanders = $null
    if ($null -ne $bystanderProperty) {
        $observedBystanders = $bystanderProperty.Value
        Assert-SwiftUIOverlayGraphStringArray $observedBystanders 'raw module.bystanders'
        foreach ($module in $observedBystanders) { Assert-SwiftUIOverlayGraphModule $module 'raw bystander' }
    }
    Assert-SwiftUIOverlayGraphModule $ObservedModule.name 'raw module.name'
    if ($Entry.role -ceq 'unattributed-emission') {
        if ($null -ne $Entry.emittingModule -or $Entry.positiveFrontendObservationIds.Count -ne 0 -or
            $null -ne $Entry.declaringModule -or $null -ne $Entry.bystanders) { throw 'Unattributed graph inputs must defer module attribution to the sealed raw graph.' }
        return [pscustomobject]@{ name = $ObservedModule.name; bystanders = $observedBystanders; attribution = 'unreviewed'; partitionOwner = 'not-inferred' }
    }
    if (@('requested-module', 'requested-overlay-context', 'automatic-module', 'automatic-overlay-context') -cnotcontains $Entry.role) {
        throw 'Unknown supplemental graph role.'
    }
    Assert-SwiftUIOverlayGraphModule $Entry.emittingModule 'supplemental emittingModule'
    Assert-SwiftUIOverlayGraphModule $Entry.declaringModule 'supplemental declaringModule'
    if ($Entry.declaringModule -cne $ObservedModule.name -or
        -not (Test-SwiftUIOverlayGraphSameStrings $Entry.bystanders $observedBystanders)) { throw 'Supplemental role metadata contradicts the raw module header.' }
    $requested = $Entry.role.StartsWith('requested-', [StringComparison]::Ordinal)
    if ($requested -ne ($Entry.emittingModule -ceq $Invocation.requestedModule)) { throw 'Supplemental requested/automatic role contradicts its emitting module.' }
    Assert-SwiftUIOverlayGraphStringArray $Entry.positiveFrontendObservationIds 'role positive IDs' -RequireNonempty -Identifiers
    foreach ($id in $Entry.positiveFrontendObservationIds) {
        if ($Invocation.positiveFrontendObservationIds -cnotcontains $id -or -not $Context.observations.ContainsKey($id)) { throw 'Graph role lacks independent positive evidence in this invocation context.' }
        $observation = $Context.observations[$id]
        if ($observation.module -cne $Entry.emittingModule) { throw 'Graph role positive evidence names a different emitting module.' }
        if ($Entry.role.EndsWith('-overlay-context', [StringComparison]::Ordinal)) {
            if ($null -eq $observedBystanders -or $observation.activationTuple.declaringModule -cne $ObservedModule.name -or
                -not (Test-SwiftUIOverlayGraphSameStrings $observation.activationTuple.bystanderModules $observedBystanders)) {
                throw 'Graph role differs from its positive overlay activation tuple.'
            }
        } elseif ($null -ne $bystanderProperty -or $ObservedModule.name -cne $Entry.emittingModule) {
            throw 'Ordinary module role contradicts emitted module metadata.'
        }
    }
    return [pscustomobject]@{ name = $ObservedModule.name; bystanders = $observedBystanders; attribution = 'context-associated-awaiting-review'; partitionOwner = 'not-inferred' }
}

function Write-SwiftUIOverlaySupplementalInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FrozenGraphInventoryPath,
        [Parameter(Mandatory)][string]$FrozenGraphInventorySha256,
        [Parameter(Mandatory)][string]$NativeInvocationMetadataPath,
        [Parameter(Mandatory)][string]$NativeInvocationMetadataSha256,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [AllowNull()]$Limits, [switch]$AllowSyntheticForTests
    )
    $ErrorActionPreference = 'Stop'
    $limitsValue = Get-SwiftUIOverlayGraphLimits $Limits
    $frozen = $null; $native = $null
    try {
        $frozen = Open-SwiftUIOverlayGraphMetadata $FrozenGraphInventoryPath $FrozenGraphInventorySha256 $limitsValue.metadataBytes
        $native = Open-SwiftUIOverlayGraphMetadata $NativeInvocationMetadataPath $NativeInvocationMetadataSha256 $limitsValue.metadataBytes
        Assert-SwiftUIAuditFields $frozen.value @{
            schemaVersion = 'integer'; evidenceKind = 'string'; batchId = 'string'; graphRoot = 'string'; supplementalGraphInputs = 'array'
        } 'supplemental frozen input'
        if ($frozen.value.schemaVersion -ne 1 -or $frozen.value.evidenceKind -cne 'swiftui-overlay-supplemental-graph-inputs-v1') { throw 'Unsupported supplemental input contract; baseline manifests are not accepted.' }
        $graphRoot = Assert-SwiftUIOverlayGraphPath $frozen.value.graphRoot Directory
        $context = Assert-SwiftUIOverlayGraphNativeContext $native.value $frozen.value.batchId $limitsValue $graphRoot -AllowSyntheticForTests:$AllowSyntheticForTests
        $output = Assert-SwiftUIOverlayGraphPath $OutputDirectory Absent
        $comparison = [StringComparison]::OrdinalIgnoreCase
        $separator = [IO.Path]::DirectorySeparatorChar
        foreach ($inputPath in @($graphRoot, $frozen.path, $native.path)) {
            if ($output.Equals($inputPath, $comparison) -or $output.StartsWith($inputPath.TrimEnd($separator) + $separator, $comparison) -or
                $inputPath.StartsWith($output.TrimEnd($separator) + $separator, $comparison)) { throw 'Supplemental output cannot overlap any frozen source input.' }
        }
        foreach ($invocation in $context.invocations.Values) {
            $directory = Resolve-SwiftUIOverlayGraphRelativePath $graphRoot $invocation.graphDirectory
            [void](Assert-SwiftUIOverlayGraphPath $directory Directory)
        }
        $diskFiles = Get-SwiftUIOverlayGraphFileInventory $graphRoot $limitsValue
        $entries = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        [long]$totalBytes = 0
        foreach ($entry in $frozen.value.supplementalGraphInputs) {
            Assert-SwiftUIAuditFields $entry @{
                relativePath = 'string'; bytes = 'integer'; sha256 = 'string'; invocationId = 'string'; role = 'string'
                emittingModule = 'nullable-string'; declaringModule = 'nullable-string'; positiveFrontendObservationIds = 'array'
            } 'supplemental graph input'
            $bystanders = Get-SwiftUIAuditProperty $entry 'bystanders'
            if ($null -ne $bystanders) { Assert-SwiftUIOverlayGraphStringArray $bystanders 'supplemental bystanders' }
            Assert-SwiftUIAuditSha256 $entry.sha256 'supplemental raw graph sha256'
            Assert-SwiftUIOverlayGraphStringArray $entry.positiveFrontendObservationIds 'graph positive IDs' -Identifiers
            [void](Resolve-SwiftUIOverlayGraphRelativePath $graphRoot $entry.relativePath)
            if (-not $entry.relativePath.EndsWith('.symbols.json', [StringComparison]::Ordinal) -or
                $entries.ContainsKey($entry.relativePath) -or -not $diskFiles.ContainsKey($entry.relativePath) -or
                $diskFiles[$entry.relativePath].relativePath -cne $entry.relativePath -or -not $context.invocations.ContainsKey($entry.invocationId)) {
                throw 'Duplicate, unexpected or unattributed supplemental graph path.'
            }
            $invocation = $context.invocations[$entry.invocationId]
            if (-not $entry.relativePath.StartsWith($invocation.graphDirectory + '/', [StringComparison]::Ordinal)) { throw 'Graph source directory contradicts its exact invocation association.' }
            if ($entries.Count -ge $limitsValue.graphFiles -or $entry.bytes -gt $limitsValue.graphBytes -or
                $entry.bytes -gt $limitsValue.totalGraphBytes - $totalBytes -or $entry.bytes -ne $diskFiles[$entry.relativePath].bytes) {
                throw 'Supplemental graph size or file count budget exceeded, or frozen size changed.'
            }
            $totalBytes += $entry.bytes
            $entries.Add($entry.relativePath, $entry)
        }
        if ($diskFiles.Count -ne $entries.Count) { throw 'Unexpected file in frozen supplemental graph directory.' }
        [string[]]$paths = @($entries.Keys)
        [Array]::Sort($paths, [StringComparer]::Ordinal)
        [void][IO.Directory]::CreateDirectory($output)
        [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($output, 'graphs'))
        [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($output, 'inputs'))
        Write-SwiftUIOverlayGraphNewBytes ([IO.Path]::Combine($output, 'inputs/frozen-graphs.json')) $frozen.bytes
        Write-SwiftUIOverlayGraphNewBytes ([IO.Path]::Combine($output, 'inputs/native-invocations.json')) $native.bytes
        $graphs = [Collections.Generic.List[SwiftUIBaseline.Streaming.GraphInput]]::new()
        $graphRecords = [Collections.Generic.List[object]]::new()
        $files = [Collections.Generic.List[object]]::new()
        foreach ($relative in $paths) {
            $entry = $entries[$relative]
            $sourcePath = Resolve-SwiftUIOverlayGraphRelativePath $graphRoot $relative
            [void](Assert-SwiftUIOverlayGraphPath $sourcePath File)
            $retainedRelative = 'graphs/' + $relative
            $destination = Resolve-SwiftUIOverlayGraphRelativePath $output $retainedRelative
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            [void](Assert-SwiftUIOverlayGraphPath $destination Absent)
            $source = [IO.File]::Open($sourcePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                if ($source.Length -ne $entry.bytes -or (Get-SwiftUIOverlayGraphHash $source) -cne $entry.sha256) { throw 'Frozen supplemental graph changed before retention.' }
                $destinationStream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
                try { $source.CopyTo($destinationStream, 65536); $destinationStream.Flush() } finally { $destinationStream.Dispose() }
                if ($source.Length -ne $entry.bytes -or (Get-SwiftUIOverlayGraphHash $source) -cne $entry.sha256) { throw 'Frozen supplemental graph changed during retention.' }
            } finally { $source.Dispose() }
            $binding = Get-SwiftUIOverlayGraphBinding $output $retainedRelative 'raw-supplemental-graph'
            if ($binding.bytes -ne $entry.bytes -or $binding.sha256 -cne $entry.sha256) { throw 'Retained supplemental graph differs from its frozen source.' }
            $graphInput = [SwiftUIBaseline.Streaming.GraphInput]::new()
            $graphInput.Path = $destination; $graphInput.RelativePath = $retainedRelative
            $invocation = $context.invocations[$entry.invocationId]
            $graphInput.RequestedModule = $invocation.requestedModule; $graphInput.Target = $invocation.target
            # A separate supplemental contract, not a weakened baseline primary graph.
            $graphInput.Primary = $false
            $visitState = @{ module = $null; metadata = $null }
            $visitor = [Action[SwiftUIBaseline.Streaming.RawGraphRecord]]{
                param($record)
                if ($record.Kind -ceq 'graph-field' -and ($record.Name -ceq 'module' -or $record.Name -ceq 'metadata')) {
                    $visitState[$record.Name] = $record.Json
                }
            }
            $visit = [SwiftUIBaseline.Streaming.InventoryWriter]::VisitGraph($graphInput, $visitor, [int]$limitsValue.maximumRecordCharacters)
            if ($visit.Sha256 -cne $entry.sha256) { throw 'Supplemental graph bytes changed during the streaming visit.' }
            foreach ($name in @('module', 'metadata')) {
                [SwiftUIBaseline.Streaming.AuditReviewPacketWriter]::ValidateMetadataObject($visitState[$name], [int]$limitsValue.maximumRecordCharacters)
            }
            $moduleArguments = @{ InputObject = $visitState.module; ErrorAction = 'Stop' }
            if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $moduleArguments.DateKind = 'String' }
            $module = ConvertFrom-Json @moduleArguments
            $role = Assert-SwiftUIOverlayGraphRole $entry $module $invocation $context
            $moduleHash = Get-SwiftUIBaselineTextHash -Text $visitState.module
            [void]$graphRecords.Add([pscustomobject][ordered]@{
                path = $retainedRelative; sourceRelativePath = $relative; sha256 = $entry.sha256; bytes = $entry.bytes
                invocationId = $entry.invocationId; requestId = $invocation.requestId; requestedModule = $invocation.requestedModule
                target = $invocation.target; cxxMode = $invocation.cxxMode; control = $invocation.control
                role = $entry.role; candidateEmittingModule = $entry.emittingModule; observedModule = $role.name
                observedBystanders = $role.bystanders; rawModuleSha256 = $moduleHash; partitionOwner = $role.partitionOwner
                physicalEmitterIdentity = 'not-established'
                attributionStatus = $role.attribution; positiveFrontendObservationIds = $entry.positiveFrontendObservationIds
                declarationOccurrences = $visit.Statistics.DeclarationOccurrences
                relationshipOccurrences = $visit.Statistics.RelationshipOccurrences
            })
            [void]$graphs.Add($graphInput); [void]$files.Add($binding)
        }
        $identity = Get-SwiftUIBaselineTextHash -Text ('swiftui-overlay-supplemental-v1:' + $frozen.sha256 + ':' + $native.sha256)
        $inventoryId = 'swiftui-overlay-supplemental-v1:' + $identity
        $inventoryPath = [IO.Path]::Combine($output, 'supplemental-inventory.json')
        $summary = [SwiftUIBaseline.Streaming.InventoryWriter]::Write($inventoryId, $graphs.ToArray(), $inventoryPath,
            $limitsValue.sortChunkBytes, [int]$limitsValue.mergeFanIn, [int]$limitsValue.maximumRecordCharacters)
        $emptyObservations = [Collections.Generic.List[object]]::new()
        foreach ($invocation in $context.invocations.Values) {
            $invocationGraphs = @($graphRecords | Where-Object { $_.invocationId -ceq $invocation.invocationId })
            if ($invocationGraphs.Count -eq 0) {
                [void]$emptyObservations.Add([pscustomobject]@{
                    kind = 'no-public-graphs-emitted'; invocationId = $invocation.invocationId; requestId = $invocation.requestId
                    requestedModule = $invocation.requestedModule; target = $invocation.target; cxxMode = $invocation.cxxMode
                    positiveFrontendObservationIds = $invocation.positiveFrontendObservationIds
                    interpretation = 'No graph file was observed in the sealed output; API absence and extraction completeness are not established.'
                    reviewStatus = 'unreviewed'
                })
            }
        }
        [long]$declarations = 0; [long]$relationships = 0
        foreach ($record in $graphRecords) { $declarations += $record.declarationOccurrences; $relationships += $record.relationshipOccurrences }
        if ($summary.Graphs -ne $graphRecords.Count -or $summary.DeclarationOccurrences -ne $declarations -or
            $summary.RelationshipOccurrences -ne $relationships -or $summary.InputBytes -ne $totalBytes) { throw 'Supplemental streaming passes disagree on input counts.' }
        # Reread exact source membership and bytes before publication. FileShare.Read
        # handles are also held for metadata, but these checks do not claim an OS
        # lock against arbitrary Unix rename or later modification of source paths.
        $finalFiles = Get-SwiftUIOverlayGraphFileInventory $graphRoot $limitsValue
        if ($finalFiles.Count -ne $entries.Count) { throw 'Frozen supplemental source membership changed.' }
        foreach ($relative in $paths) {
            if (-not $finalFiles.ContainsKey($relative) -or $finalFiles[$relative].relativePath -cne $relative) { throw 'Frozen supplemental source path changed.' }
            $entry = $entries[$relative]
            $sourceBinding = Get-SwiftUIOverlayGraphBinding $graphRoot $relative 'source-graph'
            if ($sourceBinding.bytes -ne $entry.bytes -or $sourceBinding.sha256 -cne $entry.sha256) { throw 'Frozen supplemental source seal changed.' }
        }
        foreach ($metadata in @($frozen, $native)) {
            [void](Assert-SwiftUIOverlayGraphPath $metadata.path File)
            if ((Get-SwiftUIOverlayGraphHash $metadata.stream) -cne $metadata.sha256 -or
                (Get-SwiftUIAuditHashedFile -Path $metadata.path -Kind 'source-metadata').sha256 -cne $metadata.sha256) {
                throw 'Frozen supplemental metadata seal changed.'
            }
        }
        foreach ($name in @('inputs/frozen-graphs.json', 'inputs/native-invocations.json', 'supplemental-inventory.json')) {
            [void]$files.Add((Get-SwiftUIOverlayGraphBinding $output $name 'supplemental-artifact'))
        }
        $inventoryBinding = $files[$files.Count - 1]
        if ($inventoryBinding.sha256 -cne $summary.InventorySha256) { throw 'Supplemental inventory changed after streaming.' }
        $report = [pscustomobject][ordered]@{
            schemaVersion = 1; evidenceKind = 'swiftui-overlay-supplemental-graph-report-v1'; batchId = $frozen.value.batchId
            supplementalInventoryId = $inventoryId; executionKind = $native.value.executionKind
            status = 'retained-awaiting-attribution-and-declaration-review'; rawGraphsAreAuthoritative = $true
            attributionCompleteness = 'not-established'; automaticOverlayCompleteness = 'not-established'
            apiCompleteness = 'not-established'; behaviorConformance = 'not-verified'
            inputBindings = @(
                [pscustomobject]@{ kind = 'frozen-supplemental-input'; sha256 = $frozen.sha256; retainedPath = 'inputs/frozen-graphs.json' },
                [pscustomobject]@{ kind = 'native-invocation-context'; sha256 = $native.sha256; retainedPath = 'inputs/native-invocations.json' }
            )
            inventory = [pscustomobject]@{ path = 'supplemental-inventory.json'; sha256 = $summary.InventorySha256; bytes = $summary.OutputBytes; graphSetSha256 = $summary.GraphSetSha256 }
            counts = [pscustomobject]@{
                graphs = $summary.Graphs; preciseSymbols = $summary.PreciseSymbols; declarationOccurrences = $summary.DeclarationOccurrences
                relationshipOccurrences = $summary.RelationshipOccurrences; emptyInvocations = $emptyObservations.Count
            }
            limits = $limitsValue
            retentionLayoutOverhead = [pscustomobject]@{ directories = 2; depth = 1; files = 5 }
            resourceInterpretation = 'Acceptance and retention checks, not hard OS disk quotas. Temporary streaming sort files require additional disk space. No identifier count ceiling.'
            indexing = [pscustomobject]@{
                implementation = 'unchanged-InventoryWriter-and-VisitGraph'; sourceSha256 = [SwiftUIBaseline.Streaming.InventoryWriter]::SourceHash
                inputBytes = $summary.InputBytes; outputBytes = $summary.OutputBytes; largestRecordCharacters = $summary.LargestRecordCharacters
                peakBufferedIndexEstimatedBytes = $summary.PeakBufferedIndexBytes; peakBufferedIndexRecords = $summary.PeakBufferedIndexRecords
                initialSortRuns = $summary.InitialSortRuns; mergePasses = $summary.MergePasses; peakOpenRunReaders = $summary.PeakOpenRunReaders
                largestOccurrenceGroup = $summary.LargestOccurrenceGroup
            }
            graphs = $graphRecords.ToArray(); emptyObservations = $emptyObservations.ToArray(); files = $files.ToArray()
        }
        $reportText = (ConvertTo-Json -InputObject $report -Depth 40 -WarningAction Stop) + [char]10
        $encoding = [Text.UTF8Encoding]::new($false, $true)
        $reportBytes = $encoding.GetBytes($reportText)
        if ($reportBytes.LongLength -gt $limitsValue.metadataBytes) { throw 'Supplemental compact report exceeds its metadata byte budget.' }
        Write-SwiftUIOverlayGraphNewBytes ([IO.Path]::Combine($output, 'supplemental-report.json')) $reportBytes
        $reportBinding = Get-SwiftUIOverlayGraphBinding $output 'supplemental-report.json' 'supplemental-report'
        Write-SwiftUIOverlayGraphNewBytes ([IO.Path]::Combine($output, 'supplemental-report.sha256')) (
            $encoding.GetBytes($reportBinding.sha256 + '  supplemental-report.json' + [char]10))
        return Read-SwiftUIOverlaySupplementalInventory -OutputDirectory $output -ExpectedReportSha256 $reportBinding.sha256
    } finally {
        if ($null -ne $native) { $native.stream.Dispose() }
        if ($null -ne $frozen) { $frozen.stream.Dispose() }
    }
}

function Read-SwiftUIOverlaySupplementalInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OutputDirectory, [Parameter(Mandatory)][string]$ExpectedReportSha256)
    $ErrorActionPreference = 'Stop'
    $output = Assert-SwiftUIOverlayGraphPath $OutputDirectory Directory
    $report = $null; $sealStream = $null; $retainedFrozen = $null; $retainedNative = $null
    try {
        $report = Open-SwiftUIOverlayGraphMetadata ([IO.Path]::Combine($output, 'supplemental-report.json')) $ExpectedReportSha256 16MB
        $value = $report.value
        Assert-SwiftUIAuditFields $value @{
            schemaVersion = 'integer'; evidenceKind = 'string'; supplementalInventoryId = 'string'; files = 'array'; batchId = 'string'
            executionKind = 'string'; status = 'string'; attributionCompleteness = 'string'; automaticOverlayCompleteness = 'string'
            apiCompleteness = 'string'; behaviorConformance = 'string'; rawGraphsAreAuthoritative = 'boolean'
            inventory = 'object'; counts = 'object'; limits = 'object'; inputBindings = 'array'; graphs = 'array'; emptyObservations = 'array'
        } 'supplemental report'
        if ($value.schemaVersion -ne 1 -or $value.evidenceKind -cne 'swiftui-overlay-supplemental-graph-report-v1' -or
            $value.supplementalInventoryId -cnotmatch '\Aswiftui-overlay-supplemental-v1:[0-9a-f]{64}\z' -or
            @('native', 'synthetic-test') -cnotcontains $value.executionKind -or -not $value.rawGraphsAreAuthoritative -or
            $value.status -cne 'retained-awaiting-attribution-and-declaration-review' -or
            $value.attributionCompleteness -cne 'not-established' -or $value.automaticOverlayCompleteness -cne 'not-established' -or
            $value.apiCompleteness -cne 'not-established' -or $value.behaviorConformance -cne 'not-verified') { throw 'Not an unqualified supplemental Stage B report.' }
        Assert-SwiftUIAuditFields $value.inventory @{ path = 'string'; sha256 = 'string'; bytes = 'integer'; graphSetSha256 = 'string' } 'supplemental inventory descriptor'
        Assert-SwiftUIAuditSha256 $value.inventory.sha256 'supplemental inventory sha256'
        Assert-SwiftUIAuditSha256 $value.inventory.graphSetSha256 'supplemental graph set sha256'
        Assert-SwiftUIAuditFields $value.counts @{
            graphs = 'integer'; preciseSymbols = 'integer'; declarationOccurrences = 'integer'; relationshipOccurrences = 'integer'; emptyInvocations = 'integer'
        } 'supplemental counts'
        $limitsValue = Get-SwiftUIOverlayGraphLimits $value.limits
        if ($report.bytes.LongLength -gt $limitsValue.metadataBytes -or $value.graphs.Count -gt $limitsValue.graphFiles) { throw 'Supplemental report exceeds its sealed limits.' }
        $sealPath = Assert-SwiftUIOverlayGraphPath ([IO.Path]::Combine($output, 'supplemental-report.sha256')) File
        $sealStream = [IO.File]::Open($sealPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $seal = Read-SwiftUIAuditBoundedText $sealPath 1024
        if ($seal.text -cne ($ExpectedReportSha256 + '  supplemental-report.json' + [char]10)) { throw 'Supplemental report seal mismatch.' }
        $diskFiles = Get-SwiftUIOverlayGraphFileInventory $output $limitsValue -RetentionLayout
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $bindings = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach ($file in $value.files) {
            Assert-SwiftUIAuditFields $file @{ relativePath = 'string'; sha256 = 'string'; bytes = 'integer'; kind = 'string' } 'supplemental output binding'
            if ($file.relativePath -ceq 'supplemental-report.json' -or $file.relativePath -ceq 'supplemental-report.sha256' -or
                -not $seen.Add($file.relativePath) -or -not $diskFiles.ContainsKey($file.relativePath) -or
                $diskFiles[$file.relativePath].relativePath -cne $file.relativePath) { throw 'Supplemental output binding collision or missing file.' }
            Assert-SwiftUIAuditSha256 $file.sha256 'supplemental output sha256'
            $binding = Get-SwiftUIOverlayGraphBinding $output $file.relativePath $file.kind
            if ($binding.bytes -ne $file.bytes -or $binding.sha256 -cne $file.sha256) { throw 'Supplemental output was tampered with after sealing.' }
            $bindings.Add($file.relativePath, $file)
        }
        if ($diskFiles.Count -ne $seen.Count + 2) { throw 'Extraneous file in sealed supplemental output.' }
        if ($value.inventory.path -cne 'supplemental-inventory.json' -or -not $seen.Contains($value.inventory.path) -or
            $value.counts.graphs -ne $value.graphs.Count -or $value.counts.emptyInvocations -ne $value.emptyObservations.Count) {
            throw 'Supplemental report count or inventory binding mismatch.'
        }
        $inventoryBinding = $bindings[$value.inventory.path]
        if ($inventoryBinding.sha256 -cne $value.inventory.sha256 -or $inventoryBinding.bytes -ne $value.inventory.bytes -or
            $value.files.Count -ne $value.graphs.Count + 3) { throw 'Supplemental inventory descriptor or output roster mismatch.' }
        $graphPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        [long]$declarations = 0; [long]$relationships = 0; [long]$graphBytes = 0
        foreach ($graph in $value.graphs) {
            Assert-SwiftUIAuditFields $graph @{
                path = 'string'; sha256 = 'string'; bytes = 'integer'; declarationOccurrences = 'integer'; relationshipOccurrences = 'integer'
            } 'supplemental graph record'
            if (-not $graph.path.StartsWith('graphs/', [StringComparison]::Ordinal) -or -not $bindings.ContainsKey($graph.path) -or
                -not $graphPaths.Add($graph.path) -or $graph.bytes -gt $limitsValue.graphBytes -or $graph.bytes -gt $limitsValue.totalGraphBytes - $graphBytes) {
                throw 'Supplemental graph roster or byte budget mismatch.'
            }
            $binding = $bindings[$graph.path]
            if ($binding.kind -cne 'raw-supplemental-graph' -or $binding.sha256 -cne $graph.sha256 -or $binding.bytes -ne $graph.bytes) {
                throw 'Supplemental graph record is not bound to its raw bytes.'
            }
            if ($graph.declarationOccurrences -gt [long]::MaxValue - $declarations -or $graph.relationshipOccurrences -gt [long]::MaxValue - $relationships) {
                throw 'Supplemental occurrence count overflow.'
            }
            $declarations += $graph.declarationOccurrences; $relationships += $graph.relationshipOccurrences; $graphBytes += $graph.bytes
        }
        if ($declarations -ne $value.counts.declarationOccurrences -or $relationships -ne $value.counts.relationshipOccurrences -or
            $value.counts.preciseSymbols -gt $declarations -or $value.inputBindings.Count -ne 2) { throw 'Supplemental count or input roster mismatch.' }
        $inputHashes = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
        foreach ($inputBinding in $value.inputBindings) {
            Assert-SwiftUIAuditFields $inputBinding @{ kind = 'string'; sha256 = 'string'; retainedPath = 'string' } 'supplemental input binding'
            $expectedPath = switch -CaseSensitive ($inputBinding.kind) {
                'frozen-supplemental-input' { 'inputs/frozen-graphs.json' }
                'native-invocation-context' { 'inputs/native-invocations.json' }
                default { throw 'Unknown supplemental input binding kind.' }
            }
            $binding = @($value.files | Where-Object { $_.relativePath -ceq $inputBinding.retainedPath })
            if ($inputBinding.retainedPath -cne $expectedPath -or $inputHashes.ContainsKey($inputBinding.kind) -or
                $binding.Count -ne 1 -or $binding[0].sha256 -cne $inputBinding.sha256 -or $binding[0].bytes -gt $limitsValue.metadataBytes) {
                throw 'Supplemental input seal is not retained.'
            }
            $inputHashes.Add($inputBinding.kind, $inputBinding.sha256)
        }
        $identity = Get-SwiftUIBaselineTextHash -Text ('swiftui-overlay-supplemental-v1:' +
            $inputHashes['frozen-supplemental-input'] + ':' + $inputHashes['native-invocation-context'])
        if ($value.supplementalInventoryId -cne ('swiftui-overlay-supplemental-v1:' + $identity)) { throw 'Supplemental identity does not bind its actual inputs.' }
        # Retained metadata is bounded and self-contained. Never follow the old
        # producer's graphRoot or SDK paths while reading a relocated artifact.
        $retainedFrozen = Open-SwiftUIOverlayGraphMetadata ([IO.Path]::Combine($output, 'inputs/frozen-graphs.json')) (
            $inputHashes['frozen-supplemental-input']) $limitsValue.metadataBytes
        $retainedNative = Open-SwiftUIOverlayGraphMetadata ([IO.Path]::Combine($output, 'inputs/native-invocations.json')) (
            $inputHashes['native-invocation-context']) $limitsValue.metadataBytes
        foreach ($metadata in @($retainedFrozen, $retainedNative)) {
            Assert-SwiftUIAuditFields $metadata.value @{ schemaVersion = 'integer'; evidenceKind = 'string'; batchId = 'string' } 'retained supplemental input'
            if ($metadata.value.schemaVersion -ne 1 -or $metadata.value.batchId -cne $value.batchId) { throw 'Supplemental report batch differs from its retained input provenance.' }
        }
        Assert-SwiftUIAuditFields $retainedNative.value @{ executionKind = 'string' } 'retained supplemental native input'
        if ($retainedFrozen.value.evidenceKind -cne 'swiftui-overlay-supplemental-graph-inputs-v1' -or
            $retainedNative.value.evidenceKind -cne 'swiftui-overlay-graph-native-invocations-v1' -or
            $retainedNative.value.executionKind -cne $value.executionKind) { throw 'Supplemental report execution provenance differs from its retained inputs.' }
        return [pscustomobject][ordered]@{
            evidenceKind = $value.evidenceKind; outputDirectory = $output; batchId = $value.batchId
            supplementalInventoryId = $value.supplementalInventoryId; executionKind = $value.executionKind
            report = [pscustomobject]@{ path = $report.path; sha256 = $report.sha256; bytes = $report.bytes.LongLength }
            seal = [pscustomobject]@{ path = $sealPath; sha256 = $seal.sha256; bytes = $seal.bytes }
            inventory = $value.inventory; counts = $value.counts; status = $value.status
            attributionCompleteness = 'not-established'; behaviorConformance = 'not-verified'
            inputBindings = $value.inputBindings; files = $value.files
        }
    } finally {
        if ($null -ne $retainedNative) { $retainedNative.stream.Dispose() }
        if ($null -ne $retainedFrozen) { $retainedFrozen.stream.Dispose() }
        if ($null -ne $sealStream) { $sealStream.Dispose() }
        if ($null -ne $report) { $report.stream.Dispose() }
    }
}
