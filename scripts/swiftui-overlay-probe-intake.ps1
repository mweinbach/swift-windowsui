#Requires -Version 7.0
# Stage B intake and explicit planning only. No native process is launched.
. (Join-Path $PSScriptRoot 'swiftui-overlay-discovery-common.ps1')
. (Join-Path $PSScriptRoot 'swiftui-stateobject-isolation-common.ps1')

function Assert-SwiftUIOverlayProbeArtifactFiles {
    param([string]$Root)
    # Metadata only, before either existing intake reader opens an artifact.
    # In particular, a POSIX FIFO must not reach a hashing/read routine first.
    $directory = Assert-SwiftUIStateObjectDirectory $Root
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($directory.FullName)
    $count = 0
    while ($pending.Count -gt 0) {
        foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($pending.Pop())) {
            $count++
            if ($count -gt 200000) { throw 'Artifact metadata preflight exceeded its finite entry budget; no native execution is authorized.' }
            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if ($item -is [IO.DirectoryInfo]) {
                $ordinary = Assert-SwiftUIStateObjectDirectory $path
                $pending.Push($ordinary.FullName)
            } else { [void](Assert-SwiftUIStateObjectRegularFile $path) }
        }
    }
}

function Assert-SwiftUIOverlayProbeFields {
    param($Value, [hashtable]$Fields, [string]$Context)
    if ($Value -isnot [pscustomobject]) { throw "$Context must be an object." }
    $ordinary = @{}
    foreach ($name in $Fields.Keys) {
        if (@($Value.PSObject.Properties.Name) -cnotcontains $name) { throw "$Context is missing exact field '$name'." }
        if ($Fields[$name] -ceq 'null') {
            if ($null -ne $Value.$name) { throw "$Context.$name must remain explicitly null." }
        } else { $ordinary.Add($name, $Fields[$name]) }
    }
    if ($ordinary.Count -gt 0) { Assert-SwiftUIOverlayFields $Value $ordinary $Context }
    if (@($Value.PSObject.Properties).Count -ne $Fields.Count) {
        throw "$Context contains an unknown field. Probe inputs cannot introduce source, arguments or search paths."
    }
}

function Assert-SwiftUIOverlayProbeIdentifier {
    param([string]$Name)
    if ($Name.Length -gt 128 -or $Name -ceq '_' -or $Name -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*\z') {
        throw 'A native probe module name must be an unambiguous ASCII identifier of at most 128 characters, other than bare underscore.'
    }
}

function Get-SwiftUIOverlayProbeNameSeal {
    param([AllowEmptyCollection()][object[]]$Occurrences)
    # Keep only a digest for unselected definitions, not the census multiplied
    # by every name occurrence. The selected plan retains its exact names.
    if ($Occurrences.Count -gt 4096) { throw 'Definition exceeds the bounded Stage B name-occurrence profile.' }
    $components = [Collections.Generic.List[string]]::new()
    $components.Add('probe-name-occurrences-v1')
    for ($index = 0; $index -lt $Occurrences.Count; $index++) {
        $name = $Occurrences[$index]
        Assert-SwiftUIOverlayProbeFields $name @{ index = 'integer'; name = 'string' } 'name occurrence'
        if ($name.index -ne $index -or $name.name -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*\z') {
            throw 'Definition names must preserve every ordered occurrence and its original index.'
        }
        $components.Add([string]$index)
        $components.Add($name.name)
    }
    return Get-SwiftUIOverlayId $components.ToArray()
}

function Read-SwiftUIOverlayProbeBytes {
    param([string]$Path, [long]$MaximumBytes)
    if ($MaximumBytes -lt 0 -or $MaximumBytes -gt 16MB) { throw 'Invalid bounded raw-definition read.' }
    $Path = (Assert-SwiftUIStateObjectRegularFile $Path).FullName
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $memory = [IO.MemoryStream]::new()
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        if ($stream.Length -gt $MaximumBytes) { throw 'Raw definition exceeds its bounded read before parsing.' }
        $buffer = [byte[]]::new(65536)
        while ($true) {
            $read = $stream.Read($buffer, 0, [int][Math]::Min($buffer.Length, $MaximumBytes - $memory.Length + 1))
            if ($read -eq 0) { break }
            if ($memory.Length + $read -gt $MaximumBytes) { throw 'Raw definition grew beyond its bounded read.' }
            $memory.Write($buffer, 0, $read)
        }
        $bytes = $memory.ToArray()
        $sha = [BitConverter]::ToString($algorithm.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
        return [pscustomobject]@{ data = $bytes; bytes = [long]$bytes.Length; sha256 = $sha }
    } finally {
        try { $algorithm.Dispose() } finally { try { $memory.Dispose() } finally { $stream.Dispose() } }
    }
}

function Invoke-SwiftUIOverlayProbeRecordStream {
    param([string]$Root, $Entry, $State, [scriptblock]$Visitor)
    if ($Entry.bytes -lt 0 -or $Entry.bytes -gt 256MB -or $Entry.recordCount -lt 0 -or $Entry.recordCount -gt 2000000) {
        throw 'Discovery stream exceeds the explicit Stage B replay budget; no records are silently omitted.'
    }
    $path = Resolve-SwiftUIAPIReviewArtifactPath $Root $Entry.path
    $path = (Assert-SwiftUIStateObjectRegularFile $path).FullName
    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $line = [IO.MemoryStream]::new()
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    $total = [long]0
    $records = [long]0
    try {
        if ($stream.Length -ne $Entry.bytes) { throw 'Discovery stream length changed before semantic replay.' }
        $buffer = [byte[]]::new(65536)
        while ($true) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -eq 0) { break }
            $total += $read
            if ($total -gt $Entry.bytes) { throw 'Discovery stream grew during semantic replay.' }
            [void]$algorithm.TransformBlock($buffer, 0, $read, $null, 0)
            $offset = 0
            while ($offset -lt $read) {
                $ending = [Array]::IndexOf($buffer, [byte]10, $offset, $read - $offset)
                $length = $read - $offset
                if ($ending -ge 0) { $length = $ending - $offset }
                if ($line.Length + $length -gt 16MB) { throw 'Discovery NDJSON record exceeds its bounded replay limit.' }
                $line.Write($buffer, $offset, $length)
                $offset += $length
                if ($ending -lt 0) { break }
                $offset++
                if ($line.Length -eq 0) { throw 'Discovery NDJSON contains an empty record.' }
                $text = $encoding.GetString($line.GetBuffer(), 0, [int]$line.Length)
                [SwiftUIBaseline.Streaming.AuditReviewPacketWriter]::ValidateMetadataObject($text, 16MB)
                $arguments = @{ InputObject = $text; ErrorAction = 'Stop' }
                if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $arguments.DateKind = 'String' }
                $row = ConvertFrom-Json @arguments
                $records++
                if ($records -gt $Entry.recordCount) { throw 'Discovery NDJSON contains an undeclared record.' }
                if ($Entry.path -ceq 'filesystem-facts.ndjson' -and $row.kind -cin @('root-state', 'absence-parent-entry', 'directory-entry-name')) {
                    if ($row.recordId -cne (Get-SwiftUIOverlayId @('event', 'filesystem-facts', [string]($records - 1)))) {
                        throw 'Filesystem event ID does not match its exact original stream occurrence.'
                    }
                }
                $output = @(& $Visitor $row $State)
                if ($output.Count -ne 0) { throw 'Semantic replay visitor leaked output instead of recording bounded state.' }
                $line.SetLength(0)
            }
        }
        if ($line.Length -ne 0 -or $total -ne $Entry.bytes -or $records -ne $Entry.recordCount) {
            throw 'Discovery NDJSON is truncated or disagrees with its sealed length/record count.'
        }
        [void]$algorithm.TransformFinalBlock([byte[]]@(), 0, 0)
        $sha = [BitConverter]::ToString($algorithm.Hash).Replace('-', '').ToLowerInvariant()
        if ($sha -cne $Entry.sha256) { throw 'Bytes parsed during discovery replay do not match the original stream seal.' }
    } finally {
        try { $algorithm.Dispose() } finally { try { $line.Dispose() } finally { $stream.Dispose() } }
    }
}

function Get-SwiftUIOverlayProbeRoot {
    param($State, [string]$LogicalPath, [AllowNull()][string]$RootId)
    if ((ConvertTo-SwiftUIOverlayUnixPath $LogicalPath) -cne $LogicalPath) { throw 'Noncanonical discovery logical path.' }
    $matches = @($State.rootPlan.plan.roots | Where-Object {
        $_.selection -cne 'not-selected' -and (Test-SwiftUIOverlayInside $_.logicalPath $LogicalPath) -and
        ([string]::IsNullOrEmpty($RootId) -or $_.rootId -ceq $RootId)
    })
    if ($matches.Count -ne 1) { throw 'Discovery occurrence does not belong to exactly one selected logical root.' }
    return $matches[0]
}

function Assert-SwiftUIOverlayProbePhysicalPath {
    param($State, [string]$Path)
    if ((ConvertTo-SwiftUIOverlayUnixPath $Path) -cne $Path -or
        @($State.rootPlan.plan.roots | Where-Object {
            $_.selection -cne 'not-selected' -and (Test-SwiftUIOverlayInside $_.expectedPhysicalPath $Path)
        }).Count -eq 0) { throw 'Discovery content path leaves the selected physical roots.' }
}

function Resolve-SwiftUIOverlayProbeRecordedPath {
    param($State, [string]$Path, [string]$Occurrence)
    if ((ConvertTo-SwiftUIOverlayUnixPath $Path) -cne $Path) { throw 'Noncanonical alias source path.' }
    if (-not $State.aliases.ContainsKey($Occurrence)) { return $Path }
    [void]$State.usedAliases.Add($Occurrence)
    $chain = [Collections.Generic.List[string]]::new()
    foreach ($alias in $State.aliases[$Occurrence]) {
        if (-not (Test-SwiftUIOverlayInside $alias.logicalPath $Path) -or $chain.Contains($alias.logicalPath)) {
            throw 'Recorded alias chain does not resolve this exact occurrence, or contains a cycle.'
        }
        $chain.Add($alias.logicalPath)
        Assert-SwiftUIAuditJsonEqual $chain.ToArray() $alias.resolutionChain 'alias resolution chain'
        $target = ConvertTo-SwiftUIOverlayLinkTarget $alias.rawTarget (Get-SwiftUIOverlayUnixParent $alias.logicalPath)
        $remaining = $Path.Substring($alias.logicalPath.Length)
        $effective = ConvertTo-SwiftUIOverlayUnixPath ($target.TrimEnd('/') + $remaining)
        if ($target -cne $alias.resolvedTargetCandidate -or $effective -cne $alias.effectiveTargetCandidate) {
            throw 'Alias target text contradicts its recorded effective destination.'
        }
        $Path = $effective
    }
    return $Path
}

function Assert-SwiftUIOverlayProbeRawCopy {
    param($State, $Raw, [string]$OccurrenceId, [string]$Kind, [string]$LogicalPath, [string]$PhysicalPath)
    Assert-SwiftUIOverlayProbeFields $Raw @{ path = 'string'; bytes = 'integer'; sha256 = 'string'; captureComplete = 'boolean' } 'raw copy reference'
    $expectedPath = 'raw/' + $OccurrenceId + '.bin'
    if ($Raw.path -cne $expectedPath -or -not $Raw.captureComplete -or $Raw.bytes -lt 0 -or
        -not $State.copies.ContainsKey($expectedPath)) { throw 'Occurrence refers to an absent, relocated or incomplete raw copy.' }
    $copy = $State.copies[$expectedPath]
    if ($copy.copyKind -cne $Kind -or $copy.sourceOccurrenceId -cne $OccurrenceId -or
        $copy.logicalPath -cne $LogicalPath -or $copy.physicalPath -cne $PhysicalPath -or
        $copy.bytes -ne $Raw.bytes -or $copy.sha256 -cne $Raw.sha256 -or -not $copy.captureComplete) {
        throw 'Raw copy provenance does not match its exact filesystem occurrence.'
    }
}

function Read-SwiftUIOverlayProbeSemanticRecords {
    param([string]$DiscoveryRoot, $Discovery, $RootPlanContext)
    Initialize-SwiftUIBaselineStreaming
    $report = $Discovery.report
    if ($report.counts.definitions -gt 10000 -or $report.counts.candidates -gt 20000 -or
        $report.counts.moduleMaps -gt 10000 -or $report.counts.moduleLocations -gt 500000 -or
        $report.counts.directories -gt 50000 -or $report.counts.aliasOccurrences -gt 500000 -or
        ($report.recordStreams | Measure-Object -Property bytes -Sum).Sum -gt 256MB) {
        throw 'Discovery exceeds the bounded Stage B replay profile; its original census is not truncated.'
    }
    $state = [pscustomobject]@{
        root = $DiscoveryRoot; report = $report; rootPlan = $RootPlanContext
        definitions = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        definitionDirectories = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        definitionOrder = [Collections.Generic.List[object]]::new()
        candidates = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        candidateOrder = [Collections.Generic.List[object]]::new()
        contexts = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        contextOrder = [Collections.Generic.List[object]]::new()
        copies = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        neededEntries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        matchedEntries = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        matchedCopies = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        aliases = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        usedAliases = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        aliasCount = [long]0
        directories = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        directoryEntries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        openedSourceEntries = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        physicalDirectories = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        rootStates = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
        copyPhysicalPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        concreteCopyTargets = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        absentNames = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        active = $null; pendingName = $null; latestEntry = $null
        traversedEntries = [long]0; moduleMaps = [long]0; moduleLocations = [long]0
    }
    $streams = @{}
    foreach ($entry in $report.recordStreams) { $streams.Add($entry.path, $entry) }
    foreach ($copy in $report.copiedFiles) {
        Assert-SwiftUIOverlayProbeFields $copy @{
            path = 'string'; bytes = 'integer'; sha256 = 'string'; copyKind = 'string'; sourceOccurrenceId = 'string'
            logicalPath = 'string'; physicalPath = 'string'; captureComplete = 'boolean'
        } 'discovery copied file'
        if ($state.copies.ContainsKey($copy.path)) { throw 'Duplicated raw-copy occurrence.' }
        $state.copies.Add($copy.path, $copy)
        [void]$state.copyPhysicalPaths.Add($copy.physicalPath)
    }

    Invoke-SwiftUIOverlayProbeRecordStream $DiscoveryRoot $streams['definition-facts.ndjson'] $state {
        param($row, $s)
        if ($row.kind -ceq 'definition-directory') {
            Assert-SwiftUIOverlayProbeFields $row @{
                kind = 'string'; recordId = 'string'; filesystemOccurrenceId = 'string'; logicalPath = 'string'
                physicalPath = 'string'; state = 'string'; childCount = 'integer'; reviewStatus = 'string'
            } 'definition directory'
            if (-not $row.logicalPath.EndsWith('.swiftcrossimport', [StringComparison]::OrdinalIgnoreCase) -or
                $row.recordId -cne (Get-SwiftUIOverlayId @('definition-directory', $row.filesystemOccurrenceId)) -or
                $row.reviewStatus -cne 'unreviewed' -or $s.definitionDirectories.ContainsKey($row.filesystemOccurrenceId) -or
                $s.definitionDirectories.Count -ge 50000) { throw 'Invalid or duplicate definition-directory occurrence.' }
            $s.definitionDirectories.Add($row.filesystemOccurrenceId, $row)
            return
        }
        Assert-SwiftUIOverlayProbeFields $row @{
            kind = 'string'; recordId = 'string'; filesystemOccurrenceId = 'string'; rootId = 'string'; logicalPath = 'string'
            physicalPath = 'string'; rawFile = 'object'; context = 'object'; parserProfile = 'string'; parseStatus = 'string'
            version = 'integer'; nameOccurrences = 'array'; issues = 'array'; reviewStatus = 'string'
        } 'definition occurrence'
        $root = Get-SwiftUIOverlayProbeRoot $s $row.logicalPath $row.rootId
        Assert-SwiftUIOverlayProbePhysicalPath $s $row.physicalPath
        $occurrence = Get-SwiftUIOverlayId @('entry', $root.rootId, $row.logicalPath)
        if ($row.kind -cne 'definition-file' -or -not $row.logicalPath.EndsWith('.swiftoverlay', [StringComparison]::OrdinalIgnoreCase) -or $row.filesystemOccurrenceId -cne $occurrence -or
            $row.recordId -cne (Get-SwiftUIOverlayId @('definition', $occurrence, $row.rawFile.sha256)) -or
            $row.parserProfile -cne 'swiftcrossimport-canonical-v1' -or $row.parseStatus -cne 'parsed-canonical-v1' -or
            $row.version -ne 1 -or $row.issues.Count -ne 0 -or $row.reviewStatus -cne 'unreviewed' -or
            $s.definitions.ContainsKey($row.recordId) -or $s.definitions.Count -ge 10000 -or $s.neededEntries.ContainsKey($occurrence)) {
            throw 'Invalid, duplicated or unsupported definition occurrence.'
        }
        Assert-SwiftUIOverlayProbeRawCopy $s $row.rawFile $occurrence 'overlay' $row.logicalPath $row.physicalPath
        $context = Get-SwiftUIOverlayDefinitionContext $row.logicalPath
        Assert-SwiftUIAuditJsonEqual $context $row.context 'definition context derived from the retained spelling'
        $raw = Read-SwiftUIOverlayProbeBytes (Resolve-SwiftUIAPIReviewArtifactPath $s.root $row.rawFile.path) ([Math]::Min(16MB, $s.rootPlan.limits.definitionParseBytes))
        if ($raw.sha256 -cne $row.rawFile.sha256 -or $raw.bytes -ne $row.rawFile.bytes) { throw 'Reparsed raw definition does not match its declared bytes.' }
        $parsed = ConvertFrom-SwiftUIOverlayDefinition -Bytes $raw.data -MaximumBytes $s.rootPlan.limits.definitionParseBytes -MaximumLineBytes $s.rootPlan.limits.definitionLineBytes -MaximumNames $s.rootPlan.limits.definitionNameOccurrences
        if ($parsed.status -cne 'parsed-canonical-v1') { throw 'A supposedly complete discovery contains an unsupported raw definition.' }
        $names = Get-SwiftUIOverlayProbeNameSeal $parsed.nameOccurrences
        if ($parsed.nameOccurrences.Count -ne $row.nameOccurrences.Count -or $names -cne (Get-SwiftUIOverlayProbeNameSeal $row.nameOccurrences)) {
            throw 'Definition name occurrences differ from reparsed sealed raw content.'
        }
        $compact = [pscustomobject]@{
            kind = 'definition-file'; recordId = $row.recordId; filesystemOccurrenceId = $occurrence; rootId = $root.rootId
            logicalPath = $row.logicalPath; physicalPath = $row.physicalPath; rawFile = $row.rawFile; context = $context
            nameOccurrenceCount = $parsed.nameOccurrences.Count; nameOccurrencesSha256 = $names
            sourceCandidateIds = [Collections.Generic.List[string]]::new(); reviewStatus = 'unreviewed'
        }
        $s.definitions.Add($row.recordId, $compact)
        $s.definitionOrder.Add($compact)
        $s.neededEntries.Add($occurrence, $compact)
    }

    Invoke-SwiftUIOverlayProbeRecordStream $DiscoveryRoot $streams['module-context-facts.ndjson'] $state {
        param($row, $s)
        $map = $row.kind -ceq 'clang-module-map'
        $fields = @{
            kind = 'string'; recordId = 'string'; filesystemOccurrenceId = 'string'; logicalPath = 'string'; physicalPath = 'string'
            contentSeal = 'string'; moduleNameClaim = 'nullable-string'; targetClaim = 'nullable-string'; producerHeaderFacts = 'null'; claimStatus = 'string'
        }
        if ($map) { $fields.Add('rawFile', 'object'); $fields.Add('moduleMapGrammarParsed', 'boolean') }
        else { $fields.Add('fileKind', 'string') }
        Assert-SwiftUIOverlayProbeFields $row $fields 'module context'
        $root = Get-SwiftUIOverlayProbeRoot $s $row.logicalPath $null
        Assert-SwiftUIOverlayProbePhysicalPath $s $row.physicalPath
        $occurrence = Get-SwiftUIOverlayId @('entry', $root.rootId, $row.logicalPath)
        $tag = 'module-location'
        if ($map) { $tag = 'module-map' }
        if (@('clang-module-map', 'swift-module-location') -cnotcontains $row.kind -or
            $row.filesystemOccurrenceId -cne $occurrence -or $row.recordId -cne (Get-SwiftUIOverlayId @($tag, $occurrence)) -or
            $null -ne $row.moduleNameClaim -or $null -ne $row.targetClaim -or $null -ne $row.producerHeaderFacts -or
            $row.claimStatus -cne 'unreviewed' -or $s.contexts.ContainsKey($row.recordId) -or $s.contexts.Count -ge 510000 -or
            $s.neededEntries.ContainsKey($occurrence)) { throw 'Invalid, duplicate or promoted module context.' }
        if ($map) {
            $name = $row.logicalPath.Substring($row.logicalPath.LastIndexOf('/') + 1)
            if ((-not $name.EndsWith('.modulemap', [StringComparison]::OrdinalIgnoreCase) -and -not $name.Equals('module.map', [StringComparison]::OrdinalIgnoreCase)) -or
                $row.moduleMapGrammarParsed -ne $false -or $row.contentSeal -cne 'two-read-byte-match') { throw 'Raw module-map content cannot claim a different file classification or parsed native context.' }
            Assert-SwiftUIOverlayProbeRawCopy $s $row.rawFile $occurrence 'module-map' $row.logicalPath $row.physicalPath
            $s.moduleMaps++
        } else {
            if ((-not $row.logicalPath.EndsWith('.swiftmodule', [StringComparison]::OrdinalIgnoreCase) -and -not $row.logicalPath.EndsWith('.swiftinterface', [StringComparison]::OrdinalIgnoreCase)) -or
                @('file', 'directory') -cnotcontains $row.fileKind -or
                $row.contentSeal -cne 'metadata-only; any captured interface anchors are separate receipts') { throw 'Module-location metadata cannot become module-content or loader evidence.' }
            $s.moduleLocations++
        }
        $row | Add-Member -NotePropertyName rootId -NotePropertyValue $root.rootId
        $s.contexts.Add($row.recordId, $row)
        $s.contextOrder.Add($row)
        $s.neededEntries.Add($occurrence, $row)
    }

    Invoke-SwiftUIOverlayProbeRecordStream $DiscoveryRoot $streams['candidate-pairs.ndjson'] $state {
        param($row, $s)
        Assert-SwiftUIOverlayProbeFields $row @{
            kind = 'string'; recordId = 'string'; definitionOccurrenceId = 'string'; declaringModuleClaim = 'nullable-string'; bystanderModuleClaim = 'nullable-string'
            expectedOverlayNameOccurrences = 'array'; rawTargetDirectory = 'nullable-string'; target = 'string'; targetVariant = 'nullable-string'
            selectionReasons = 'array'; parseStatus = 'string'; contextStatus = 'string'; reviewStatus = 'string'
        } 'candidate pair'
        if ($row.kind -cne 'candidate-pair' -or -not $s.definitions.ContainsKey($row.definitionOccurrenceId) -or
            $s.candidates.ContainsKey($row.recordId) -or $s.candidates.Count -ge 20000) { throw 'Candidate is duplicated or has no exact definition occurrence.' }
        $definition = $s.definitions[$row.definitionOccurrenceId]
        $names = Get-SwiftUIOverlayProbeNameSeal $row.expectedOverlayNameOccurrences
        if ($row.recordId -cne (Get-SwiftUIOverlayId @('candidate', $definition.recordId, $row.target)) -or
            @($s.rootPlan.plan.targetContexts.target) -cnotcontains $row.target -or $null -ne $row.targetVariant -or
            $row.declaringModuleClaim -cne $definition.context.declaringModuleClaim -or $row.bystanderModuleClaim -cne $definition.context.bystanderModuleClaim -or
            $row.rawTargetDirectory -cne $definition.context.targetDirectory -or $names -cne $definition.nameOccurrencesSha256 -or
            $row.expectedOverlayNameOccurrences.Count -ne $definition.nameOccurrenceCount -or
            $row.parseStatus -cne 'parsed-canonical-v1' -or $row.contextStatus -cne 'unreviewed-target-and-module-applicability' -or $row.reviewStatus -cne 'unreviewed') {
            throw 'Candidate target, names or context contradicts its exact definition.'
        }
        $reasons = [Collections.Generic.List[string]]::new()
        $reasons.Add('complete-unfiltered-definition-census')
        if ($definition.context.declaringModuleClaim -cin @('SwiftUI', 'SwiftUICore')) { $reasons.Add('seed-declaring-module') }
        if ($definition.context.bystanderModuleClaim -cin @('SwiftUI', 'SwiftUICore')) { $reasons.Add('reverse-bystander-seed') }
        Assert-SwiftUIAuditJsonEqual $reasons.ToArray() $row.selectionReasons 'candidate selection hints'
        $compact = [pscustomobject]@{
            recordId = $row.recordId; definitionOccurrenceId = $definition.recordId; target = $row.target; targetVariant = $null
            declaringModuleClaim = $row.declaringModuleClaim; bystanderModuleClaim = $row.bystanderModuleClaim
            rawTargetDirectory = $row.rawTargetDirectory; expectedOverlayNameCount = $definition.nameOccurrenceCount
            expectedOverlayNamesSha256 = $names; selectionReasons = $row.selectionReasons; reviewStatus = 'unreviewed'
        }
        $s.candidates.Add($row.recordId, $compact)
        $s.candidateOrder.Add($compact)
        $definition.sourceCandidateIds.Add($row.recordId)
    }
    foreach ($definition in $state.definitionOrder) {
        if ($definition.sourceCandidateIds.Count -ne 2) { throw 'Every definition occurrence must retain both pinned source candidates.' }
    }

    Invoke-SwiftUIOverlayProbeRecordStream $DiscoveryRoot $streams['alias-facts.ndjson'] $state {
        param($row, $s)
        Assert-SwiftUIOverlayProbeFields $row @{
            kind = 'string'; recordId = 'string'; logicalOccurrence = 'string'; logicalPath = 'string'; rawTarget = 'string'
            resolutionChain = 'array'; resolvedTargetCandidate = 'string'; effectiveTargetCandidate = 'string'; targetRootId = 'nullable-string'; disposition = 'string'
        } 'alias occurrence'
        $s.aliasCount++
        if ($s.aliasCount -gt 500000 -or $row.kind -cne 'alias-resolution' -or $row.disposition -cne 'followed-in-allowlist' -or
            $row.recordId -cne (Get-SwiftUIOverlayId @('alias', $row.logicalOccurrence, $row.logicalPath, $row.rawTarget, [string]$s.aliasCount)) -or
            $row.resolutionChain.Count -lt 1 -or $row.resolutionChain.Count -gt $s.rootPlan.limits.aliasHops) {
            throw 'Failed, duplicate or unsupported alias observation cannot authorize a probe.'
        }
        $allowed = @($s.rootPlan.plan.roots | Where-Object { $_.selection -cne 'not-selected' -and (Test-SwiftUIOverlayInside $_.expectedPhysicalPath $row.effectiveTargetCandidate) })
        if ($allowed.Count -gt 0) {
            if ($row.targetRootId -cne $allowed[0].rootId) { throw 'Alias physical root differs from its recorded root.' }
        } else {
            $anchor = @($s.rootPlan.plan.identityAnchors | Where-Object {
                $row.logicalOccurrence -cin @('anchor:' + $_.anchorId + ':before', 'anchor:' + $_.anchorId + ':after') -and
                (Test-SwiftUIOverlayInside $_.allowedPhysicalBoundary $row.effectiveTargetCandidate)
            })
            $absence = $row.logicalOccurrence.StartsWith('absence-parent:', [StringComparison]::Ordinal) -and
                @($s.rootPlan.plan.lookupAuthorizations | Where-Object { $_.exactPath -ceq $row.effectiveTargetCandidate }).Count -gt 0
            if (($anchor.Count -ne 1 -and -not $absence) -or $null -ne $row.targetRootId) { throw 'Alias has no exact root, anchor or absence-lookup authorization.' }
        }
        if (-not $s.aliases.ContainsKey($row.logicalOccurrence)) { $s.aliases.Add($row.logicalOccurrence, [Collections.Generic.List[object]]::new()) }
        $s.aliases[$row.logicalOccurrence].Add($row)
    }

    Invoke-SwiftUIOverlayProbeRecordStream $DiscoveryRoot $streams['filesystem-facts.ndjson'] $state {
        param($row, $s)
        if ($null -ne $s.pendingName -and $row.kind -cne 'directory-entry') { throw 'A directory name has no immediately matching metadata occurrence.' }
        switch -CaseSensitive ($row.kind) {
            'root-state' {
                $root = @($s.rootPlan.plan.roots | Where-Object { $_.rootId -ceq $row.rootId })
                if ($root.Count -ne 1 -or $row.logicalPath -cne $root[0].logicalPath -or $s.rootStates.ContainsKey($row.rootId)) { throw 'Duplicate or redirected filesystem root state.' }
                $s.rootStates.Add($row.rootId, $row.state)
                $root = $root[0]
                if ($row.state -ceq 'not-selected') {
                    Assert-SwiftUIOverlayProbeFields $row @{ kind='string'; recordId='string'; rootId='string'; logicalPath='string'; state='string' } 'unselected root'
                    if ($root.selection -cne 'not-selected') { throw 'Selected root was omitted from observation.' }
                } elseif ($row.state -ceq 'present-unvisited') {
                    Assert-SwiftUIOverlayProbeFields $row @{ kind='string'; recordId='string'; rootId='string'; logicalPath='string'; physicalPath='string'; state='string' } 'present root'
                    if ($root.selection -ceq 'not-selected' -or $row.physicalPath -cne $root.expectedPhysicalPath -or
                        (Resolve-SwiftUIOverlayProbeRecordedPath $s $root.logicalPath ('root:' + $root.rootId)) -cne $row.physicalPath) { throw 'Present root does not resolve to its reviewed physical mapping.' }
                } elseif ($row.state -ceq 'absent-confirmed') {
                    Assert-SwiftUIOverlayProbeFields $row @{ kind='string'; recordId='string'; rootId='string'; logicalPath='string'; state='string'; evidence='string'; parent='string'; parentEntryCount='integer' } 'absent root'
                    $parent = Get-SwiftUIOverlayUnixParent $root.logicalPath
                    $listing = @($s.rootPlan.plan.lookupAuthorizations | Where-Object { $_.exactPath -ceq $parent -and $_.mayEnumerateChildren })
                    $count = 0
                    if ($s.absentNames.ContainsKey($root.rootId)) { $count = $s.absentNames[$root.rootId].Count }
                    if ($root.selection -cne 'selected-optional' -or $row.parent -cne $parent -or $listing.Count -ne 1 -or
                        $row.evidence -cne 'authorized parent enumeration completed' -or $row.parentEntryCount -ne $count) { throw 'Absence lacks its exact authorized parent observation.' }
                    [void](Resolve-SwiftUIOverlayProbeRecordedPath $s $parent ('absence-parent:' + $root.rootId))
                } else { throw 'Incomplete filesystem root cannot enter native planning.' }
            }
            'absence-parent-entry' {
                Assert-SwiftUIOverlayProbeFields $row @{ kind='string'; recordId='string'; rootId='string'; parent='string'; name='string'; path='string'; state='string' } 'absence parent entry'
                $root = @($s.rootPlan.plan.roots | Where-Object { $_.rootId -ceq $row.rootId })
                if ($root.Count -ne 1 -or $s.rootStates.ContainsKey($row.rootId) -or $root[0].selection -cne 'selected-optional' -or
                    $row.parent -cne (Get-SwiftUIOverlayUnixParent $root[0].logicalPath) -or $row.state -cne 'observed-entry-only' -or
                    [string]::IsNullOrEmpty($row.name) -or $row.name.Contains('/') -or $row.name -cin @('.', '..') -or
                    $row.name -ceq $root[0].logicalPath.Substring($row.parent.Length + 1)) { throw 'Invalid absence-parent entry.' }
                $parent = Resolve-SwiftUIOverlayProbeRecordedPath $s $row.parent ('absence-parent:' + $row.rootId)
                if ($row.path -cne ($parent.TrimEnd('/') + '/' + $row.name)) { throw 'Absence-parent entry path is redirected.' }
                if (-not $s.absentNames.ContainsKey($row.rootId)) { $s.absentNames.Add($row.rootId, [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)) }
                if (-not $s.absentNames[$row.rootId].Add($row.name)) { throw 'Duplicate absence-parent name.' }
            }
            'directory-open' {
                Assert-SwiftUIOverlayProbeFields $row @{
                    kind='string'; recordId='string'; rootId='string'; logicalPath='string'; physicalPath='string'; depth='integer'
                    sourceEntryId='nullable-string'; repeatedPhysicalDestination='boolean'; state='string'
                } 'directory open'
                $root = Get-SwiftUIOverlayProbeRoot $s $row.logicalPath $row.rootId
                Assert-SwiftUIOverlayProbePhysicalPath $s $row.physicalPath
                if ($null -ne $s.active -or $row.recordId -cne (Get-SwiftUIOverlayId @('directory', $root.rootId, $row.logicalPath)) -or
                    $s.directories.ContainsKey($row.recordId) -or $s.directories.Count -ge 50000 -or $row.state -cne 'in-progress' -or
                    $row.depth -lt 0 -or $row.depth -gt $s.rootPlan.limits.depth -or -not $s.rootStates.ContainsKey($root.rootId) -or
                    $s.rootStates[$root.rootId] -cne 'present-unvisited') { throw 'Invalid or duplicate directory opening.' }
                $ancestors = @()
                if ($null -eq $row.sourceEntryId) {
                    if ($row.depth -ne 0 -or $row.logicalPath -cne $root.logicalPath -or $row.physicalPath -cne $root.expectedPhysicalPath) { throw 'A non-root directory omitted its source entry.' }
                } else {
                    if (-not $s.directoryEntries.ContainsKey($row.sourceEntryId)) { throw 'Directory has no earlier source entry.' }
                    $entry = $s.directoryEntries[$row.sourceEntryId]
                    $parent = $s.directories[$entry.parentDirectoryId]
                    $ancestors = @($parent.ancestors) + @($parent.physicalPath)
                    if ($entry.logicalPath -cne $row.logicalPath -or -not $parent.complete -or $parent.depth + 1 -ne $row.depth -or
                        (Resolve-SwiftUIOverlayProbeRecordedPath $s $entry.physicalPath $entry.logicalPath) -cne $row.physicalPath -or
                        $ancestors -ccontains $row.physicalPath -or -not $s.openedSourceEntries.Add($row.sourceEntryId)) { throw 'Directory opening is not attached to its exact completed parent, or revisits a physical ancestor.' }
                }
                $repeated = -not $s.physicalDirectories.Add($row.physicalPath)
                if ($repeated -ne $row.repeatedPhysicalDestination) { throw 'Aliased directory occurrences lost their repeated-destination fact.' }
                $s.active = [pscustomobject]@{ recordId=$row.recordId; rootId=$row.rootId; logicalPath=$row.logicalPath; physicalPath=$row.physicalPath
                    depth=$row.depth; ancestors=$ancestors; names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal); matched=0; complete=$false; state=$null }
                $s.directories.Add($row.recordId, $s.active)
                $s.latestEntry = $null
            }
            'directory-entry-name' {
                Assert-SwiftUIOverlayProbeFields $row @{ kind='string'; recordId='string'; rootId='string'; parentDirectoryId='string'; reportedName='string'; reportedPhysicalPath='string'; state='string' } 'directory name'
                if ($null -eq $s.active -or $row.rootId -cne $s.active.rootId -or $row.parentDirectoryId -cne $s.active.recordId -or
                    [string]::IsNullOrEmpty($row.reportedName) -or $row.reportedName.Contains('/') -or $row.reportedName -cin @('.', '..') -or
                    $row.reportedPhysicalPath -cne ($s.active.physicalPath.TrimEnd('/') + '/' + $row.reportedName) -or
                    $row.state -cne 'name-observed-metadata-pending' -or -not $s.active.names.Add($row.reportedName)) { throw 'Invalid or duplicate shallow directory name.' }
                $s.pendingName = $row
            }
            'directory-entry' {
                Assert-SwiftUIOverlayProbeFields $row @{
                    kind='string'; recordId='string'; rootId='string'; parentDirectoryId='string'; logicalPath='string'; physicalPath='string'
                    entryKind='string'; attributes='string'; rawLinkTarget='nullable-string'; beforeMetadata='object'; state='string'
                } 'directory entry'
                $pending = $s.pendingName
                if ($null -eq $pending -or $row.rootId -cne $s.active.rootId -or $row.parentDirectoryId -cne $s.active.recordId -or
                    $row.logicalPath -cne ($s.active.logicalPath.TrimEnd('/') + '/' + $pending.reportedName) -or $row.physicalPath -cne $pending.reportedPhysicalPath -or
                    $row.recordId -cne (Get-SwiftUIOverlayId @('entry', $row.rootId, $row.logicalPath)) -or $row.state -cne 'observed-entry' -or
                    @('file','directory','symlink') -cnotcontains $row.entryKind) { throw 'Directory metadata does not match its exact preceding name.' }
                Assert-SwiftUIOverlayProbeFields $row.beforeMetadata @{ path='string'; kind='string'; attributes='string'; length='integer'; lastWriteTimeUtc='string'; creationTimeUtc='string'; linkTarget='nullable-string' } 'entry metadata'
                if ($row.beforeMetadata.path -cne $row.physicalPath -or $row.beforeMetadata.kind -cne $row.entryKind -or
                    $row.beforeMetadata.attributes -cne $row.attributes -or $row.beforeMetadata.linkTarget -cne $row.rawLinkTarget -or
                    ($row.entryKind -ceq 'symlink') -ne (-not [string]::IsNullOrEmpty($row.rawLinkTarget))) { throw 'Entry fields contradict their original metadata.' }
                $resolved = $row.physicalPath
                if ($row.entryKind -ceq 'symlink') {
                    if (-not $s.aliases.ContainsKey($row.logicalPath)) { throw 'A symlink entry omitted its native filesystem alias observations.' }
                    $directAlias = @($s.aliases[$row.logicalPath] | Where-Object { $_.logicalPath -ceq $row.physicalPath })
                    if ($directAlias.Count -ne 1 -or $directAlias[0].rawTarget -cne $row.rawLinkTarget) { throw 'A symlink entry contradicts its exact recorded link target.' }
                    $resolved = Resolve-SwiftUIOverlayProbeRecordedPath $s $row.physicalPath $row.logicalPath
                }
                elseif ($s.aliases.ContainsKey($row.logicalPath)) { throw 'A non-link entry has an invented alias resolution.' }
                Assert-SwiftUIOverlayProbePhysicalPath $s $resolved
                if ($s.copyPhysicalPaths.Contains($row.physicalPath) -and $row.entryKind -ceq 'file') {
                    if ($s.concreteCopyTargets.ContainsKey($row.physicalPath) -and $s.concreteCopyTargets[$row.physicalPath].length -ne $row.beforeMetadata.length) {
                        throw 'Repeated regular-file observations disagree about a copied target length.'
                    }
                    $s.concreteCopyTargets[$row.physicalPath] = $row.beforeMetadata
                }
                if ($s.neededEntries.ContainsKey($row.recordId)) {
                    $needed = $s.neededEntries[$row.recordId]
                    if ($needed.logicalPath -cne $row.logicalPath -or $needed.physicalPath -cne $resolved -or $needed.rootId -cne $row.rootId -or
                        -not $s.matchedEntries.Add($row.recordId)) { throw 'Definition or module context contradicts its filesystem occurrence.' }
                    if ((Get-SwiftUIAuditProperty $needed 'kind') -ceq 'swift-module-location' -and $row.entryKind -cne 'symlink' -and $needed.fileKind -cne $row.entryKind) { throw 'Module location kind contradicts its source entry.' }
                }
                if ($row.entryKind -cne 'file') {
                    if ($s.directoryEntries.ContainsKey($row.recordId) -or $s.directoryEntries.Count -ge 500000) { throw 'Duplicate or excessive directory/link entry.' }
                    $s.directoryEntries.Add($row.recordId, $row)
                }
                $name = $pending.reportedName
                $overlay = $name.EndsWith('.swiftoverlay', [StringComparison]::OrdinalIgnoreCase)
                $map = $name.EndsWith('.modulemap', [StringComparison]::OrdinalIgnoreCase) -or $name.Equals('module.map', [StringComparison]::OrdinalIgnoreCase)
                $location = $name.EndsWith('.swiftmodule', [StringComparison]::OrdinalIgnoreCase) -or $name.EndsWith('.swiftinterface', [StringComparison]::OrdinalIgnoreCase)
                if ($overlay -or $map) {
                    $s.active.matched++
                    if (-not $s.copies.ContainsKey('raw/' + $row.recordId + '.bin')) { throw 'Filesystem candidate was omitted from raw-copy accounting.' }
                }
                if ($location) {
                    $s.active.matched++
                    if (-not $s.contexts.ContainsKey((Get-SwiftUIOverlayId @('module-location', $row.recordId)))) { throw 'Filesystem module location was omitted from context accounting.' }
                }
                $s.traversedEntries++
                $s.latestEntry = $row
                $s.pendingName = $null
            }
            'candidate-copy' {
                Assert-SwiftUIOverlayProbeFields $row @{
                    kind='string'; recordId='string'; rootId='string'; sourceOccurrenceId='string'; logicalPath='string'; physicalPath='string'
                    rawFile='string'; capturedBytes='integer'; capturedBytesSha256='string'; captureComplete='boolean'; state='string'
                } 'filesystem candidate copy'
                $entry = $s.latestEntry
                if ($null -eq $entry -or $row.sourceOccurrenceId -cne $entry.recordId -or $row.rootId -cne $entry.rootId -or
                    $row.recordId -cne (Get-SwiftUIOverlayId @('copy', $entry.recordId)) -or $row.logicalPath -cne $entry.logicalPath -or
                    -not $row.captureComplete -or $row.state -cne 'copied-awaiting-second-read' -or
                    $row.rawFile -cne ('raw/' + $entry.recordId + '.bin') -or -not $s.copies.ContainsKey($row.rawFile) -or
                    -not $s.matchedCopies.Add($row.rawFile)) { throw 'Raw-copy filesystem record is missing, duplicated or relocated.' }
                $copy = $s.copies[$row.rawFile]
                if ($copy.physicalPath -cne $row.physicalPath -or $copy.logicalPath -cne $row.logicalPath -or $copy.bytes -ne $row.capturedBytes -or
                    $copy.sha256 -cne $row.capturedBytesSha256 -or -not $s.matchedEntries.Contains($entry.recordId)) { throw 'Raw-copy filesystem record contradicts its definition or module map.' }
                if ($entry.entryKind -cne 'symlink' -and ($entry.entryKind -cne 'file' -or $entry.beforeMetadata.length -ne $copy.bytes)) {
                    throw 'A raw-copy source must be a regular file with the observed copied length.'
                }
            }
            'directory-complete' {
                Assert-SwiftUIOverlayProbeFields $row @{
                    kind='string'; recordId='string'; directoryId='string'; rootId='string'; logicalPath='string'; physicalPath='string'
                    state='string'; childCount='integer'; matchedDirectChildCount='integer'; enumerationPassesCompleted='integer'
                } 'directory completion'
                $directory = $s.active
                $expectedState = 'readable-populated'
                if ($null -ne $directory -and $directory.names.Count -eq 0) { $expectedState = 'readable-empty' }
                elseif ($null -ne $directory -and $directory.matched -eq 0) { $expectedState = 'readable-no-matches' }
                if ($null -eq $directory -or $row.recordId -cne (Get-SwiftUIOverlayId @('directory-complete', $directory.recordId)) -or
                    $row.directoryId -cne $directory.recordId -or $row.rootId -cne $directory.rootId -or $row.logicalPath -cne $directory.logicalPath -or
                    $row.physicalPath -cne $directory.physicalPath -or $row.childCount -ne $directory.names.Count -or
                    $row.matchedDirectChildCount -ne $directory.matched -or $row.enumerationPassesCompleted -ne 2 -or $row.state -cne $expectedState) { throw 'Directory completion contradicts its observed membership.' }
                $directory.complete = $true
                $directory.state = $row.state
                if ($s.definitionDirectories.ContainsKey($row.directoryId)) {
                    $definition = $s.definitionDirectories[$row.directoryId]
                    if ($definition.logicalPath -cne $row.logicalPath -or $definition.physicalPath -cne $row.physicalPath -or
                        $definition.childCount -ne $row.childCount -or $definition.state -cne $row.state) { throw 'Definition directory does not match its filesystem completion.' }
                    [void]$s.definitionDirectories.Remove($row.directoryId)
                } elseif ($row.logicalPath.EndsWith('.swiftcrossimport', [StringComparison]::OrdinalIgnoreCase)) { throw 'Completed definition directory was omitted from definition facts.' }
                $s.active = $null
                $s.latestEntry = $null
            }
            default { throw 'Unknown or incomplete filesystem record cannot authorize a native probe.' }
        }
    }
    Invoke-SwiftUIOverlayProbeRecordStream $DiscoveryRoot $streams['issues.ndjson'] $state { param($row, $s) throw 'A complete discovery cannot contain an issue record.' }
    foreach ($anchor in $RootPlanContext.plan.identityAnchors) {
        foreach ($phase in @('before', 'after')) {
            $check = @($report.identityAnchorChecks | Where-Object { $_.anchorId -ceq $anchor.anchorId -and $_.phase -ceq $phase })
            if ($check.Count -ne 1 -or (Resolve-SwiftUIOverlayProbeRecordedPath $state $anchor.logicalPath ('anchor:' + $anchor.anchorId + ':' + $phase)) -cne $check[0].physicalPath -or
                -not (Test-SwiftUIOverlayInside $anchor.allowedPhysicalBoundary $check[0].physicalPath)) { throw 'Identity anchor physical path contradicts its exact alias records.' }
        }
    }
    foreach ($root in $report.roots) {
        if ($root.state -ceq 'readable-complete') {
            $id = Get-SwiftUIOverlayId @('directory', $root.rootId, $root.logicalPath)
            if ($state.rootStates[$root.rootId] -cne 'present-unvisited' -or -not $state.directories.ContainsKey($id) -or -not $state.directories[$id].complete) { throw 'A complete root has no matching present root and completed root directory.' }
        } elseif ($state.rootStates[$root.rootId] -cne $root.state) { throw 'Aggregate root state contradicts its actual filesystem root-state record.' }
    }
    foreach ($entry in $state.directoryEntries.Values) {
        $resolved = Resolve-SwiftUIOverlayProbeRecordedPath $state $entry.physicalPath $entry.logicalPath
        if (($entry.entryKind -ceq 'directory' -or $state.physicalDirectories.Contains($resolved)) -and -not $state.openedSourceEntries.Contains($entry.recordId)) {
            throw 'An observed directory child or directory alias was omitted from completed traversal.'
        }
    }
    foreach ($copy in $state.copies.Values) {
        if (-not $state.concreteCopyTargets.ContainsKey($copy.physicalPath) -or $state.concreteCopyTargets[$copy.physicalPath].length -ne $copy.bytes) {
            throw 'A copied target lacks matching regular-file kind and length in the recorded physical tree.'
        }
    }
    $absentCount = [long]0
    foreach ($names in $state.absentNames.Values) { $absentCount += $names.Count }
    if ($null -ne $state.active -or $null -ne $state.pendingName -or $state.rootStates.Count -ne 3 -or
        $state.definitionDirectories.Count -ne 0 -or $state.matchedEntries.Count -ne $state.neededEntries.Count -or
        $state.matchedCopies.Count -ne $state.copies.Count -or $state.usedAliases.Count -ne $state.aliases.Count -or
        $state.definitions.Count -ne $report.counts.definitions -or $state.candidates.Count -ne $report.counts.candidates -or
        $state.moduleMaps -ne $report.counts.moduleMaps -or $state.moduleLocations -ne $report.counts.moduleLocations -or
        $state.aliasCount -ne $report.counts.aliasOccurrences -or $state.directories.Count -ne $report.counts.directories -or
        $state.traversedEntries * 2 + $absentCount -ne $report.counts.filesystemEntries) { throw 'Complete discovery metadata disagrees with replayed occurrence accounting.' }
    return [pscustomobject]@{
        definitions = $state.definitionOrder.ToArray(); candidates = $state.candidateOrder.ToArray(); moduleContexts = $state.contextOrder.ToArray()
        replayProfile = 'bounded-overlay-occurrence-join-v1'; nativeModuleResolutionPerformed = $false
        recordsVerified = [long](($report.recordStreams | Measure-Object -Property recordCount -Sum).Sum)
    }
}

function Assert-SwiftUIOverlayProbeInputSeals {
    param($Inputs)
    foreach ($entry in $Inputs.fileSeals) {
        $path = (Assert-SwiftUIStateObjectRegularFile $entry.path).FullName
        $actual = Get-SwiftUIAuditHashedFile -Path $path -RelativePath $entry.relativePath -Kind $entry.kind -ExpectedSha256 $entry.sha256
        if ($actual.bytes -ne $entry.bytes) { throw 'An original Stage B input changed after intake.' }
    }
}

function Read-SwiftUIOverlayProbeInputsInternal {
    param([string]$CaptureRoot, [string]$AuditRoot, [string]$DiscoveryRoot, [string]$ExpectedDiscoverySha256,
        [string]$ManifestPath, [switch]$AllowSyntheticForTests)
    # Internal test seam: it still reads real sealed files through both existing
    # strict readers and the complete new semantic replay. It never qualifies
    # an injected object as a native capture.
    # Carry the exact validated absolute paths into .NET reads; PowerShell's
    # provider location need not equal the process working directory.
    $CaptureRoot = (Assert-SwiftUIStateObjectDirectory $CaptureRoot).FullName
    $AuditRoot = (Assert-SwiftUIStateObjectDirectory $AuditRoot).FullName
    $DiscoveryRoot = (Assert-SwiftUIStateObjectDirectory $DiscoveryRoot).FullName
    $ManifestPath = (Assert-SwiftUIStateObjectRegularFile $ManifestPath).FullName
    foreach ($artifactRoot in @($CaptureRoot, $AuditRoot, $DiscoveryRoot)) { Assert-SwiftUIOverlayProbeArtifactFiles $artifactRoot }
    $source = Read-SwiftUIOverlayDiscoveryInputs -CaptureRoot $CaptureRoot -AuditRoot $AuditRoot -ManifestPath $ManifestPath -AllowSyntheticForTests:$AllowSyntheticForTests
    $discovery = Read-SwiftUIOverlayDiscoveryReport -Root $DiscoveryRoot -ExpectedManifestSha256 $ExpectedDiscoverySha256 -AllowSyntheticForTests:$AllowSyntheticForTests
    if ($source.syntheticFixture -ne $discovery.report.syntheticFixture -or
        ($source.syntheticFixture -and -not $AllowSyntheticForTests)) { throw 'Synthetic and native evidence cannot be mixed.' }
    $targets = @($source.inputs.captureContext.baselineManifest.scope.targets)
    if ($targets.Count -ne 2 -or $targets -cnotcontains 'arm64-apple-macosx26.5' -or $targets -cnotcontains 'x86_64-apple-macosx26.5') {
        throw 'The initial native probe profile requires the two exact macOS 26.5 targets.'
    }
    $root = [IO.Path]::GetDirectoryName($discovery.path)
    $rootPlan = Read-SwiftUIOverlayRootPlan -Path (Resolve-SwiftUIAPIReviewArtifactPath $root 'root-plan.json') -ExpectedSha256 $discovery.report.rootPlan.sha256 -SourceContext $source
    Assert-SwiftUIAuditJsonEqual $rootPlan.plan.targetContexts $discovery.report.targetContexts 'discovery target contexts'
    $artifacts = [pscustomobject][ordered]@{
        captureManifestSha256 = $source.inputs.captureContext.captureSha256
        captureStatusSha256 = $source.inputs.captureContext.statusSha256
        auditManifestSha256 = $source.inputs.auditManifestSha256
        baselineManifestSha256 = $source.inputs.currentExpectedBaselineManifestSha256
        inventorySha256 = $source.inputs.captureContext.inventorySha256
        graphSetSha256 = $source.graphSetSha256
        discoveryManifestSha256 = $discovery.sha256
        rootPlanSha256 = $rootPlan.file.sha256
    }
    foreach ($name in @('captureManifestSha256', 'captureStatusSha256', 'auditManifestSha256', 'baselineManifestSha256', 'inventorySha256', 'graphSetSha256')) {
        if ($discovery.report.sourceArtifacts.$name -cne $artifacts.$name) { throw 'Discovery does not bind the exact supplied successful capture and complete ledger.' }
    }
    $seals = [Collections.Generic.List[object]]::new()
    foreach ($entry in $source.fileSeals) { $seals.Add($entry) }
    $seals.Add((Get-SwiftUIAuditHashedFile (Resolve-SwiftUIAPIReviewArtifactPath $source.inputs.auditRoot 'audit.sha256') 'audit.sha256' 'original-audit-seal' $source.inputs.auditSealSha256))
    foreach ($entry in @($discovery.report.recordStreams) + @($discovery.report.copiedFiles) + @($discovery.report.rootPlan)) {
        $seals.Add((Get-SwiftUIAuditHashedFile (Resolve-SwiftUIAPIReviewArtifactPath $root $entry.path) $entry.path 'discovery-source' $entry.sha256))
    }
    $seals.Add((Get-SwiftUIAuditHashedFile $discovery.path 'discovery.json' 'discovery-manifest' $discovery.sha256))
    $seals.Add((Get-SwiftUIAuditHashedFile (Resolve-SwiftUIAPIReviewArtifactPath $root 'discovery.sha256') 'discovery.sha256' 'discovery-seal'))
    $semantic = Read-SwiftUIOverlayProbeSemanticRecords -DiscoveryRoot $root -Discovery $discovery -RootPlanContext $rootPlan
    $result = [pscustomobject]@{
        source = $source; discovery = $discovery; rootPlanContext = $rootPlan; sourceArtifacts = $artifacts; fileSeals = $seals.ToArray()
        definitions = $semantic.definitions; candidates = $semantic.candidates; moduleContexts = $semantic.moduleContexts
        semanticReplay = $semantic.replayProfile; recordsVerified = $semantic.recordsVerified
        syntheticFixture = $source.syntheticFixture; nativeCommandsExecuted = $false
        qualification = 'unreviewed input observations; no module resolution, activation or API completeness claim'
    }
    Assert-SwiftUIOverlayProbeInputSeals $result
    return $result
}

function Read-SwiftUIOverlayProbeInputs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CaptureRoot, [Parameter(Mandatory)][string]$AuditRoot,
        [Parameter(Mandatory)][string]$DiscoveryRoot, [Parameter(Mandatory)][string]$ExpectedDiscoverySha256,
        [string]$ManifestPath = (Join-Path $PSScriptRoot '../docs/swiftui-baseline.json'))
    return Read-SwiftUIOverlayProbeInputsInternal -CaptureRoot $CaptureRoot -AuditRoot $AuditRoot -DiscoveryRoot $DiscoveryRoot -ExpectedDiscoverySha256 $ExpectedDiscoverySha256 -ManifestPath $ManifestPath
}

function Read-SwiftUIOverlayProbePlanInternal {
    param([string]$Path, [string]$ExpectedSha256, $Inputs, [switch]$AllowSyntheticForTests)
    Assert-SwiftUIAuditSha256 $ExpectedSha256 'probePlan.expectedSha256'
    $Path = (Assert-SwiftUIStateObjectRegularFile $Path).FullName
    $file = Read-SwiftUIOverlayMetadata -Path $Path -MaximumBytes 1MB
    if ($file.sha256 -cne $ExpectedSha256) { throw 'Probe plan hash differs from the separately supplied reviewed authorization.' }
    $plan = $file.value
    Assert-SwiftUIOverlayProbeFields $plan @{
        schemaVersion='integer'; evidenceKind='string'; sourceArtifacts='object'; nativeProfileSha256='string'; languageMode='string'
        targetContexts='array'; pairs='array'; limits='object'
    } 'probe plan'
    if ($plan.schemaVersion -ne 1 -or $plan.evidenceKind -cne 'swiftui-overlay-probe-plan' -or $plan.languageMode -cne '6') { throw 'Unsupported native probe plan or Swift language mode.' }
    Assert-SwiftUIAuditSha256 $plan.nativeProfileSha256 'probePlan.nativeProfileSha256'
    $sourceFields = @{}
    foreach ($name in @('captureManifestSha256','captureStatusSha256','auditManifestSha256','baselineManifestSha256','inventorySha256','graphSetSha256','discoveryManifestSha256','rootPlanSha256')) { $sourceFields.Add($name, 'string') }
    Assert-SwiftUIOverlayProbeFields $plan.sourceArtifacts $sourceFields 'probe plan sources'
    foreach ($name in $sourceFields.Keys) { Assert-SwiftUIAuditSha256 $plan.sourceArtifacts.$name ('probePlan.sourceArtifacts.' + $name) }
    # Caller-owned PSObjects are not receipts. Rebuild the projections from the
    # actual sealed files; removing an unselected in-memory candidate must not
    # silently remove its disposition. Synthetic entry remains explicit here.
    $Inputs = Read-SwiftUIOverlayProbeInputsInternal -CaptureRoot $Inputs.source.inputs.captureRoot -AuditRoot $Inputs.source.inputs.auditRoot -DiscoveryRoot ([IO.Path]::GetDirectoryName($Inputs.discovery.path)) -ExpectedDiscoverySha256 $plan.sourceArtifacts.discoveryManifestSha256 -ManifestPath $Inputs.source.inputs.currentExpectedBaselineManifestPath -AllowSyntheticForTests:$AllowSyntheticForTests
    Assert-SwiftUIAuditJsonEqual $Inputs.sourceArtifacts $plan.sourceArtifacts 'probe plan exact source bindings'
    Assert-SwiftUIOverlayProbeFields $plan.limits @{ maximumDefinitionPairs='integer'; maximumDistinctOverlayModules='integer' } 'probe plan limits'
    if ($plan.limits.maximumDefinitionPairs -lt 1 -or $plan.limits.maximumDefinitionPairs -gt 4 -or
        $plan.limits.maximumDistinctOverlayModules -lt 1 -or $plan.limits.maximumDistinctOverlayModules -gt 16 -or
        $plan.pairs.Count -lt 1 -or $plan.pairs.Count -gt $plan.limits.maximumDefinitionPairs) {
        throw 'Probe plan must select one to four definition pairs within its explicit batch limits; this is not an API coverage cap.'
    }
    $modes = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    if ($plan.targetContexts.Count -ne 2 -and $plan.targetContexts.Count -ne 4) { throw 'Each declared C++ mode requires both pinned target contexts.' }
    foreach ($target in $plan.targetContexts) {
        Assert-SwiftUIOverlayProbeFields $target @{ target='string'; targetVariant='nullable-string'; cxxInteroperabilityMode='string' } 'probe target'
        if (@('off','default') -cnotcontains $target.cxxInteroperabilityMode -or $null -ne $target.targetVariant -or
            @($Inputs.rootPlanContext.plan.targetContexts.target) -cnotcontains $target.target) { throw 'Unknown, inferred or changed native target context.' }
        if (-not $modes.ContainsKey($target.cxxInteroperabilityMode)) { $modes.Add($target.cxxInteroperabilityMode, [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)) }
        if (-not $modes[$target.cxxInteroperabilityMode].Add($target.target)) { throw 'Duplicate target and C++ mode in native probe plan.' }
    }
    foreach ($mode in $modes.Values) { if ($mode.Count -ne 2) { throw 'A declared C++ mode omitted a pinned target.' } }
    $definitions = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $candidates = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Inputs.definitions) { $definitions.Add($entry.recordId, $entry) }
    foreach ($entry in $Inputs.candidates) { $candidates.Add($entry.recordId, $entry) }
    $selected = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $modules = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $pairs = [Collections.Generic.List[object]]::new()
    foreach ($pair in $plan.pairs) {
        Assert-SwiftUIOverlayProbeFields $pair @{
            pairId='string'; definitionOccurrenceId='string'; rawDefinitionSha256='string'; declaringModule='string'; bystanderModule='string'
            overlayNameOccurrences='array'; sourceCandidateIds='array'
        } 'selected probe pair'
        Assert-SwiftUIOverlayProbeIdentifier $pair.declaringModule
        Assert-SwiftUIOverlayProbeIdentifier $pair.bystanderModule
        if (-not $definitions.ContainsKey($pair.definitionOccurrenceId) -or $selected.ContainsKey($pair.definitionOccurrenceId) -or
            $pair.pairId -cne (Get-SwiftUIOverlayId @('probe-pair', $pair.definitionOccurrenceId))) { throw 'Selected pair is duplicated or does not identify one exact definition occurrence.' }
        $definition = $definitions[$pair.definitionOccurrenceId]
        if ($pair.rawDefinitionSha256 -cne $definition.rawFile.sha256 -or
            $pair.declaringModule -cne $definition.context.declaringModuleClaim -or $pair.bystanderModule -cne $definition.context.bystanderModuleClaim -or
            $pair.overlayNameOccurrences.Count -ne $definition.nameOccurrenceCount -or
            (Get-SwiftUIOverlayProbeNameSeal $pair.overlayNameOccurrences) -cne $definition.nameOccurrencesSha256) {
            throw 'Selected modules, raw definition or ordered names differ from the explicit source occurrence; unclassified contexts remain unresolved.'
        }
        foreach ($name in $pair.overlayNameOccurrences) {
            Assert-SwiftUIOverlayProbeIdentifier $name.name
            [void]$modules.Add($name.name)
        }
        if ($modules.Count -gt $plan.limits.maximumDistinctOverlayModules) { throw 'Selected overlay modules exceed the explicit batch limit.' }
        $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $sourceCandidates = [Collections.Generic.List[object]]::new()
        if ($pair.sourceCandidateIds.Count -ne 2) { throw 'Selected definition must preserve both source candidate IDs.' }
        foreach ($id in $pair.sourceCandidateIds) {
            if ($id -isnot [string] -or -not $ids.Add($id) -or -not $candidates.ContainsKey($id) -or
                $candidates[$id].definitionOccurrenceId -cne $definition.recordId) { throw 'Selected source candidate is duplicated, foreign or missing.' }
            $sourceCandidates.Add($candidates[$id])
        }
        $selected.Add($definition.recordId, $pair.pairId)
        $pairs.Add([pscustomobject]@{
            pairId=$pair.pairId; definitionOccurrenceId=$pair.definitionOccurrenceId; rawDefinitionSha256=$pair.rawDefinitionSha256
            declaringModule=$pair.declaringModule; bystanderModule=$pair.bystanderModule; overlayNameOccurrences=$pair.overlayNameOccurrences
            sourceCandidateIds=$pair.sourceCandidateIds; definition=$definition; sourceCandidates=$sourceCandidates.ToArray()
            hasExpectedOverlays=($pair.overlayNameOccurrences.Count -gt 0); nativeLoadEvidence='not-performed'
        })
    }
    $dispositions = [Collections.Generic.List[object]]::new()
    foreach ($candidate in $Inputs.candidates) {
        $disposition = 'unselected'
        $pairId = $null
        if ($selected.ContainsKey($candidate.definitionOccurrenceId)) { $disposition = 'selected'; $pairId = $selected[$candidate.definitionOccurrenceId] }
        $dispositions.Add([pscustomobject]@{
            candidateId=$candidate.recordId; definitionOccurrenceId=$candidate.definitionOccurrenceId; pairId=$pairId
            target=$candidate.target; disposition=$disposition; expectedOverlayNameCount=$candidate.expectedOverlayNameCount; nativeLoadEvidence='not-performed'
        })
    }
    Assert-SwiftUIOverlayProbeInputSeals $Inputs
    [void](Get-SwiftUIAuditHashedFile $file.path 'probe-plan.json' 'reviewed-probe-plan' $file.sha256)
    return [pscustomobject]@{
        file=$file; plan=$plan; inputs=$Inputs; pairs=$pairs.ToArray(); dispositions=$dispositions.ToArray(); limits=$plan.limits; targetContexts=$plan.targetContexts
        sourceArtifacts=$Inputs.sourceArtifacts; nativeProfileSha256=$plan.nativeProfileSha256; syntheticFixture=$Inputs.syntheticFixture
        nativeCommandsExecuted=$false; qualification='reviewed execution selection only; no native activation, graph or API completeness claim'
    }
}

function Read-SwiftUIOverlayProbePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ExpectedSha256, [Parameter(Mandatory)]$Inputs)
    return Read-SwiftUIOverlayProbePlanInternal -Path $Path -ExpectedSha256 $ExpectedSha256 -Inputs $Inputs
}
