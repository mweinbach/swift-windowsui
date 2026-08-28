# SYNTHETIC Stage A filesystem only. Dot-sourcing defines helpers and performs
# no reads, writes, compilation, SDK discovery or native process execution.
# Load swiftui-overlay-discovery-common.ps1 before calling these helpers.
#
# nodes[path] is { info = <mutable metadata>; bytes = <byte[]> }. Provider reads
# copy scalar metadata by default; an onGetInfo after hook may replace
# event.result with a shared object to test the controller's snapshot copying.
# Hooks receive (path, state, event), mutate event/state or throw, and emit no
# pipeline output. Enumeration phases: before, entry, after-entry, complete.
# Info/read phases: before, after. openRead hooks may replace event.bytes in
# the before phase; the after phase exposes the newly opened event.stream.
# openedStreams retains streams so tests can assert CanRead=false afterwards.
# countDisposed counts enumerators; enumerationCalls includes failed opens.

function Assert-SwiftUIOverlayFakeSource {
    param([Parameter(Mandatory)]$SourceContext)
    if ($SourceContext.syntheticFixture -isnot [bool] -or -not $SourceContext.syntheticFixture) {
        throw 'The fake filesystem requires an explicitly synthetic source context.'
    }
    $capture = $SourceContext.inputs.captureContext.capture
    $marker = Get-SwiftUIBaselineProperty $capture 'syntheticFixture'
    if ($null -eq $marker -or $marker.kind -cne 'swiftui-api-audit-tests' -or $marker.schemaVersion -ne 1) {
        throw 'The fake filesystem accepts only the existing synthetic API audit fixture family.'
    }
    $layout = Get-SwiftUIOverlayExpectedLayout $SourceContext
    foreach ($path in @($layout.sdk, $layout.toolchain, $layout.developer)) {
        if (-not $path.StartsWith('/SYNTHETIC/', [StringComparison]::Ordinal)) {
            throw 'Fake source paths must remain in the Unix /SYNTHETIC namespace.'
        }
    }
    return $layout
}

function Assert-SwiftUIOverlayFakePath {
    param([Parameter(Mandatory)][string]$Path)
    if (-not $Path.StartsWith('/', [StringComparison]::Ordinal) -or
        (ConvertTo-SwiftUIOverlayUnixPath $Path) -cne $Path) {
        throw 'Fake paths must be canonical Unix absolute paths, never host filesystem paths.'
    }
    return $Path
}

function Get-SwiftUIOverlayFakeByteHash {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Read-SwiftUIOverlayFakeArtifactBytes {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$ExpectedSha256)
    # Only callers' small, already captured settings/interfaces enter this
    # helper. Never load a generated inventory or graph into the fake provider.
    if (@('SDKSettings.json', 'SDKSettings.plist') -cnotcontains $RelativePath -and
        -not ($RelativePath.StartsWith('interfaces/', [StringComparison]::Ordinal) -and
            $RelativePath.EndsWith('.swiftinterface', [StringComparison]::Ordinal))) {
        throw 'Fake source reads permit only captured SDK settings and public interfaces.'
    }
    $path = Resolve-SwiftUIAuditArtifactPath -CaptureRoot $Root -RelativePath $RelativePath
    $source = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $memory = $null
    try {
        if ($source.Length -gt 4MB) { throw 'Synthetic source artifact exceeds the 4 MiB fixture read budget.' }
        $memory = [IO.MemoryStream]::new()
        $buffer = [byte[]]::new(8192)
        while (($count = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($memory.Length + $count -gt 4MB) { throw 'Synthetic source artifact grew beyond its read budget.' }
            $memory.Write($buffer, 0, $count)
        }
        $bytes = $memory.ToArray()
        if ((Get-SwiftUIOverlayFakeByteHash $bytes) -cne $ExpectedSha256) {
            throw 'Synthetic source artifact bytes differ from their captured digest.'
        }
        return ,$bytes
    } finally {
        if ($null -ne $memory) { $memory.Dispose() }
        $source.Dispose()
    }
}

function Write-SwiftUIOverlayFakeTrace {
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)]$Event)
    if ($State.trace.Count -ge $State.maximumTraceEvents) { throw 'Synthetic provider trace budget reached.' }
    [void]$State.trace.Add([pscustomobject]@{
        sequence = [long]$State.trace.Count; operation = [string]$Event.operation
        phase = [string]$Event.phase; path = [string]$Event.path
        callIndex = [long]$Event.callIndex; entryIndex = [long]$Event.entryIndex
    })
}

function Invoke-SwiftUIOverlayFakeHook {
    param([AllowNull()]$Hook, [string]$Path, $State, $Event)
    if ($null -eq $Hook) { return }
    if ($Hook -isnot [scriptblock]) { throw 'A synthetic provider hook must be a scriptblock or null.' }
    $output = @(& $Hook $Path $State $Event)
    if ($output.Count -ne 0) { throw 'Synthetic hooks mutate their event/state or throw; they must not emit pipeline data.' }
}

function Add-SwiftUIOverlayFakeNode {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Provider, [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('directory', 'file', 'symlink')][string]$Kind,
        [AllowEmptyString()][string]$Text, [AllowEmptyCollection()][byte[]]$Bytes,
        [AllowEmptyString()][string]$LinkTarget)
    if ($Provider.isSynthetic -isnot [bool] -or -not $Provider.isSynthetic) {
        throw 'Fake nodes cannot be added to a live provider.'
    }
    $pathValue = Assert-SwiftUIOverlayFakePath $Path
    $state = $Provider.state
    $hasText = $PSBoundParameters.ContainsKey('Text')
    $hasBytes = $PSBoundParameters.ContainsKey('Bytes')
    $hasTarget = $PSBoundParameters.ContainsKey('LinkTarget')
    if (($hasText -and $hasBytes) -or (($hasText -or $hasBytes) -and $Kind -cne 'file') -or
        ($hasTarget -and $Kind -cne 'symlink') -or ($pathValue -ceq '/' -and $Kind -cne 'directory')) {
        throw 'A fake node has conflicting kind/payload arguments.'
    }
    $payload = [byte[]]@()
    if ($Kind -ceq 'file') {
        if ($hasText) {
            $encoding = [Text.UTF8Encoding]::new($false, $true)
            if ($encoding.GetByteCount($Text) -gt $state.maximumFileBytes) { throw 'Fake file exceeds its payload budget.' }
            $payload = $encoding.GetBytes($Text)
        } elseif ($hasBytes) {
            if ($null -eq $Bytes -or $Bytes.LongLength -gt $state.maximumFileBytes) {
                throw 'Fake file bytes are null or exceed their payload budget.'
            }
            $payload = [byte[]]$Bytes.Clone()
        }
    } elseif ($Kind -ceq 'symlink') {
        # Do not normalize a link target: malformed/outward/../ targets are
        # intentional controller test inputs, not paths to inspect here.
        if (-not $hasTarget -or [string]::IsNullOrEmpty($LinkTarget) -or $LinkTarget.Length -gt 65536) {
            throw 'A fake symlink requires a bounded nonempty raw target.'
        }
        [void]([Text.UTF8Encoding]::new($false, $true).GetByteCount($LinkTarget))
    }
    $oldBytes = [long]0
    if ($state.nodes.ContainsKey($pathValue)) { $oldBytes = $state.nodes[$pathValue].bytes.LongLength }
    if ($state.payloadBytes - $oldBytes + $payload.LongLength -gt $state.maximumPayloadBytes) {
        throw 'Synthetic node payloads exceed the aggregate fixture budget.'
    }
    # Add ordinary directory parents only. Never follow a fake link while
    # creating nodes; tests put bytes at the intended physical dictionary key.
    $parents = [Collections.Generic.Stack[string]]::new()
    $parent = Get-SwiftUIOverlayUnixParent $pathValue
    if ($pathValue -cne '/') {
        while ($true) {
            if ($state.nodes.ContainsKey($parent)) {
                if ($state.nodes[$parent].info.kind -cne 'directory') { throw 'A fake parent is not an ordinary directory.' }
            } else { $parents.Push($parent) }
            if ($parent -ceq '/') { break }
            $parent = Get-SwiftUIOverlayUnixParent $parent
        }
    }
    $newCount = $parents.Count
    if (-not $state.nodes.ContainsKey($pathValue)) { $newCount++ }
    if ($state.nodes.Count + $newCount -gt $state.maximumNodes) { throw 'Synthetic node count budget reached.' }
    while ($parents.Count -gt 0) {
        $parent = $parents.Pop()
        $state.generation++
        $stamp = $state.epoch.AddTicks($state.generation).ToString('o')
        $state.nodes.Add($parent, [pscustomobject]@{
            info = [pscustomobject]@{ path = $parent; kind = 'directory'; attributes = 'Directory'; length = [long]0
                lastWriteTimeUtc = $stamp; creationTimeUtc = $stamp; linkTarget = $null }
            bytes = [byte[]]@()
        })
    }
    $state.generation++
    $stamp = $state.epoch.AddTicks($state.generation).ToString('o')
    $attributes = 'Normal'
    if ($Kind -ceq 'directory') { $attributes = 'Directory' }
    elseif ($Kind -ceq 'symlink') { $attributes = 'ReparsePoint' }
    $leaf = $pathValue.Substring($pathValue.LastIndexOf('/') + 1)
    if ($leaf.StartsWith('.', [StringComparison]::Ordinal)) { $attributes += ', Hidden' }
    $rawTarget = $null
    if ($Kind -ceq 'symlink') { $rawTarget = $LinkTarget }
    $node = [pscustomobject]@{
        info = [pscustomobject]@{ path = $pathValue; kind = $Kind; attributes = $attributes; length = [long]$payload.LongLength
            lastWriteTimeUtc = $stamp; creationTimeUtc = $stamp; linkTarget = $rawTarget }
        bytes = $payload
    }
    $state.nodes[$pathValue] = $node
    $state.payloadBytes = [long]($state.payloadBytes - $oldBytes + $payload.LongLength)
    return $node
}

function New-SwiftUIOverlayFakeProvider {
    param([Parameter(Mandatory)]$SourceContext)
    $layout = Assert-SwiftUIOverlayFakeSource $SourceContext
    $state = [pscustomobject]@{
        nodes = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        trace = [Collections.Generic.List[object]]::new()
        openedStreams = [Collections.Generic.List[IO.Stream]]::new()
        activeEnumerations = [long]0; enumerationsOpened = [long]0; countDisposed = [long]0
        getInfoCalls = [long]0; enumerationCalls = [long]0; openReadCalls = [long]0
        onGetInfo = $null; onEnumerate = $null; onOpenRead = $null
        generation = [long]0; payloadBytes = [long]0
        epoch = [DateTime]::SpecifyKind([DateTime]::new(2000, 1, 1), [DateTimeKind]::Utc)
        maximumNodes = [long]10000; maximumFileBytes = [long]16MB
        maximumPayloadBytes = [long]64MB; maximumTraceEvents = [long]200000
    }
    $provider = [pscustomobject]@{
        name = 'synthetic-overlay-filesystem-v1'; isSynthetic = $true
        incidentalLinkTargetMetadataPossible = $false; state = $state
        getInfo = {
            param([string]$Path, $ProviderState)
            [void](Assert-SwiftUIOverlayFakePath $Path)
            $ProviderState.getInfoCalls++
            $event = [pscustomobject]@{ operation = 'getInfo'; phase = 'before'; path = $Path
                callIndex = $ProviderState.getInfoCalls; entryIndex = [long]-1; node = $null; result = $null }
            Write-SwiftUIOverlayFakeTrace $ProviderState $event
            Invoke-SwiftUIOverlayFakeHook $ProviderState.onGetInfo $Path $ProviderState $event
            if (-not $ProviderState.nodes.ContainsKey($Path)) { throw [IO.FileNotFoundException]::new('Synthetic node is missing.', $Path) }
            $event.node = $ProviderState.nodes[$Path]
            $info = $event.node.info
            $event.result = [pscustomobject]@{ path = [string]$info.path; kind = [string]$info.kind
                attributes = [string]$info.attributes; length = [long]$info.length
                lastWriteTimeUtc = [string]$info.lastWriteTimeUtc; creationTimeUtc = [string]$info.creationTimeUtc
                linkTarget = $info.linkTarget }
            $event.phase = 'after'
            Invoke-SwiftUIOverlayFakeHook $ProviderState.onGetInfo $Path $ProviderState $event
            Write-SwiftUIOverlayFakeTrace $ProviderState $event
            return ,$event.result
        }
        enumerate = {
            param([string]$Path, $ProviderState, [scriptblock]$Visitor)
            [void](Assert-SwiftUIOverlayFakePath $Path)
            $ProviderState.enumerationCalls++
            $event = [pscustomobject]@{ operation = 'enumerate'; phase = 'before'; path = $Path
                callIndex = $ProviderState.enumerationCalls; entryIndex = [long]-1; entry = $null }
            Write-SwiftUIOverlayFakeTrace $ProviderState $event
            Invoke-SwiftUIOverlayFakeHook $ProviderState.onEnumerate $Path $ProviderState $event
            if (-not $ProviderState.nodes.ContainsKey($Path)) { throw [IO.DirectoryNotFoundException]::new('Synthetic directory is missing.') }
            if ($ProviderState.nodes[$Path].info.kind -cne 'directory') { throw [IO.IOException]::new('Synthetic enumeration target is not an ordinary directory.') }
            $iterator = $ProviderState.nodes.Keys.GetEnumerator()
            $ProviderState.enumerationsOpened++
            $ProviderState.activeEnumerations++
            try {
                while ($iterator.MoveNext()) {
                    $child = [string]$iterator.Current
                    if ($child -ceq $Path -or (Get-SwiftUIOverlayUnixParent $child) -cne $Path) { continue }
                    $event.entryIndex++
                    $event.entry = [pscustomobject]@{ path = $child; name = $child.Substring($child.LastIndexOf('/') + 1) }
                    $event.phase = 'entry'
                    Invoke-SwiftUIOverlayFakeHook $ProviderState.onEnumerate $Path $ProviderState $event
                    Write-SwiftUIOverlayFakeTrace $ProviderState $event
                    & $Visitor $event.entry
                    $event.phase = 'after-entry'
                    Invoke-SwiftUIOverlayFakeHook $ProviderState.onEnumerate $Path $ProviderState $event
                }
            } finally {
                if ($iterator -is [IDisposable]) { $iterator.Dispose() }
                $ProviderState.activeEnumerations--
                $ProviderState.countDisposed++
            }
            $event.phase = 'complete'; $event.entry = $null
            Invoke-SwiftUIOverlayFakeHook $ProviderState.onEnumerate $Path $ProviderState $event
            Write-SwiftUIOverlayFakeTrace $ProviderState $event
        }
        openRead = {
            param([string]$Path, $ProviderState)
            [void](Assert-SwiftUIOverlayFakePath $Path)
            $ProviderState.openReadCalls++
            $event = [pscustomobject]@{ operation = 'openRead'; phase = 'before'; path = $Path
                callIndex = $ProviderState.openReadCalls; entryIndex = [long]-1
                node = $null; bytes = $null; stream = $null }
            Write-SwiftUIOverlayFakeTrace $ProviderState $event
            Invoke-SwiftUIOverlayFakeHook $ProviderState.onOpenRead $Path $ProviderState $event
            if (-not $ProviderState.nodes.ContainsKey($Path)) { throw [IO.FileNotFoundException]::new('Synthetic file is missing.', $Path) }
            $event.node = $ProviderState.nodes[$Path]
            if ($event.node.info.kind -cne 'file') { throw [IO.IOException]::new('Synthetic openRead accepts ordinary files only; links are never followed.') }
            if ($null -eq $event.bytes) { $event.bytes = $event.node.bytes }
            if ($event.bytes -isnot [byte[]] -or $event.bytes.LongLength -gt $ProviderState.maximumFileBytes) {
                throw 'Synthetic read bytes are invalid or exceed their fixture budget.'
            }
            $stream = [IO.MemoryStream]::new([byte[]]$event.bytes.Clone(), $false)
            $transferred = $false
            try {
                [void]$ProviderState.openedStreams.Add($stream)
                $event.stream = $stream; $event.phase = 'after'
                Invoke-SwiftUIOverlayFakeHook $ProviderState.onOpenRead $Path $ProviderState $event
                Write-SwiftUIOverlayFakeTrace $ProviderState $event
                $transferred = $true
                return $stream
            } finally { if (-not $transferred) { $stream.Dispose() } }
        }
    }
    [void](Add-SwiftUIOverlayFakeNode $provider '/' 'directory')
    [void](Add-SwiftUIOverlayFakeNode $provider $layout.sdk 'directory')
    [void](Add-SwiftUIOverlayFakeNode $provider ($layout.toolchain + '/usr/lib/swift') 'directory')
    # Optional roots and overlay definitions are deliberately not seeded.
    # Main tests explicitly add them when selecting those scenarios.
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    foreach ($marker in @(
        @{ id = 'swift-tool'; text = 'SYNTHETIC swift tool fixture; not an executable' },
        @{ id = 'extractor-tool'; text = 'SYNTHETIC symbolgraph extractor fixture; not an executable' }
    )) {
        $anchor = $layout.anchors[$marker.id]
        $bytes = $encoding.GetBytes($marker.text)
        if ((Get-SwiftUIOverlayFakeByteHash $bytes) -cne $anchor.sha256) { throw 'Synthetic tool marker digest differs from the fixture family.' }
        [void](Add-SwiftUIOverlayFakeNode $provider $anchor.path 'file' -Bytes $bytes)
    }
    $capture = $SourceContext.inputs.captureContext.capture
    $captureRoot = $SourceContext.inputs.captureContext.captureRoot
    $bytes = Read-SwiftUIOverlayFakeArtifactBytes $captureRoot $capture.sdk.settingsPath $capture.sdk.settingsSha256
    [void](Add-SwiftUIOverlayFakeNode $provider $layout.anchors['sdk-settings'].path 'file' -Bytes $bytes)
    foreach ($entry in $capture.publicInterfaces) {
        $prefix = 'interfaces/' + $entry.module + '/'
        $id = 'interface:' + $entry.module + '/' + $entry.path.Substring($prefix.Length)
        $bytes = Read-SwiftUIOverlayFakeArtifactBytes $captureRoot $entry.path $entry.sha256
        [void](Add-SwiftUIOverlayFakeNode $provider $layout.anchors[$id].path 'file' -Bytes $bytes)
    }
    return $provider
}

function New-SwiftUIOverlayFakeRootPlan {
    param([Parameter(Mandatory)]$SourceContext)
    $layout = Assert-SwiftUIOverlayFakeSource $SourceContext
    $roots = [Collections.Generic.List[object]]::new()
    $authorizedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($id in $layout.roots.Keys) {
        $path = [string]$layout.roots[$id]
        $selection = 'required'; $physical = $path
        if ($id -ceq 'platform-developer-frameworks') { $selection = 'not-selected'; $physical = $null }
        [void]$roots.Add([pscustomobject]@{ rootId = $id; selection = $selection; logicalPath = $path
            expectedPhysicalPath = $physical; allowedPhysicalBoundary = $physical
            reason = 'SYNTHETIC exact fixture root; no actual SDK path is inspected.' })
        [void]$authorizedPaths.Add($path)
    }
    $anchors = [Collections.Generic.List[object]]::new()
    [string[]]$anchorIds = @($layout.anchors.Keys)
    [Array]::Sort($anchorIds, [StringComparer]::Ordinal)
    foreach ($id in $anchorIds) {
        $anchor = $layout.anchors[$id]
        $boundary = $layout.sdk
        if ($id -cin @('swift-tool', 'extractor-tool')) { $boundary = $layout.toolchain }
        [void]$anchors.Add([pscustomobject]@{ anchorId = $id; logicalPath = $anchor.path
            allowedPhysicalBoundary = $boundary; expectedSha256 = $anchor.sha256 })
        [void]$authorizedPaths.Add($anchor.path)
        [void]$authorizedPaths.Add($boundary)
    }
    $metadataPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $parentPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $authorizedPaths) {
        [void]$parentPaths.Add((Get-SwiftUIOverlayUnixParent $path))
        $ancestor = $path
        while ($true) {
            [void]$metadataPaths.Add($ancestor)
            if ($ancestor -ceq '/') { break }
            $ancestor = Get-SwiftUIOverlayUnixParent $ancestor
        }
    }
    $lookups = [Collections.Generic.List[object]]::new()
    [string[]]$ordered = @($metadataPaths)
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    foreach ($path in $ordered) {
        [void]$lookups.Add([pscustomobject]@{ lookupId = 'metadata-' + $lookups.Count
            kind = 'ancestor-metadata'; exactPath = $path; purpose = 'SYNTHETIC exact component resolution only.'
            mayEnumerateChildren = $false; mayTraverseDescendants = $false })
    }
    [string[]]$ordered = @($parentPaths)
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    foreach ($path in $ordered) {
        [void]$lookups.Add([pscustomobject]@{ lookupId = 'parent-' + $lookups.Count
            kind = 'nonrecursive-parent-listing'; exactPath = $path; purpose = 'SYNTHETIC explicit absence-parent receipt only.'
            mayEnumerateChildren = $true; mayTraverseDescendants = $false })
    }
    $targets = @(
        foreach ($target in $SourceContext.inputs.captureContext.baselineManifest.scope.targets) {
            [pscustomobject]@{ target = $target; targetVariant = $null }
        }
    )
    return [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'overlay-discovery-root-authorization'
        sourceCaptureSha256 = $SourceContext.inputs.captureContext.captureSha256
        sourceAuditSha256 = $SourceContext.inputs.auditManifestSha256
        baselineManifestSha256 = $SourceContext.inputs.currentExpectedBaselineManifestSha256
        targetContexts = $targets; roots = $roots.ToArray(); identityAnchors = $anchors.ToArray()
        lookupAuthorizations = $lookups.ToArray(); limits = [pscustomobject]@{}
        allowIncidentalLinkTargetMetadata = $true
        futureSyntheticRootPlanField = [pscustomobject]@{
            marker = 'SYNTHETIC unknown root-plan field must survive the raw plan copy.'
            values = @('preserve', $null, [pscustomobject]@{ MixedCaseKey = 'unchanged' })
        }
    }
}
