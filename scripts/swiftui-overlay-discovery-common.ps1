# Stage A only: sealed filesystem observations, never native compiler probes.
# The existing managed streaming helper is reused for bounded strict JSON.
# No new managed source or native process runner is introduced here.
. (Join-Path $PSScriptRoot 'swiftui-api-review-common.ps1')
. (Join-Path $PSScriptRoot 'swiftui-baseline-streaming.ps1')
$script:SwiftUIOverlayDiscoveryScriptRoot = $PSScriptRoot

function Get-SwiftUIOverlayLimits {
    param($Requested)
    $limits = [ordered]@{
        filesystemEntries = [long]500000; directories = [long]50000; depth = [long]64
        aliasHops = [long]64; copiedCandidateFiles = [long]10000
        copiedCandidateFileBytes = [long]16MB; copiedCandidateBytes = [long]256MB
        reportBytes = [long]256MB; definitionParseBytes = [long]1MB
        definitionLineBytes = [long]64KB; definitionNameOccurrences = [long]4096
        metadataBytes = [long]16MB
    }
    if ($null -ne $Requested) {
        if ($Requested -isnot [pscustomobject]) { throw 'Overlay limits must be a JSON object.' }
        foreach ($property in $Requested.PSObject.Properties) {
            if (@($limits.Keys) -cnotcontains $property.Name -or
                $property.Value -isnot [long] -and $property.Value -isnot [int]) {
                throw "Unknown or non-integer overlay limit '$($property.Name)'."
            }
            if ($property.Value -lt 1 -or $property.Value -gt [int]::MaxValue) {
                throw "Overlay limit '$($property.Name)' is outside the supported positive range."
            }
            $limits[$property.Name] = [long]$property.Value
        }
    }
    if ($limits.metadataBytes -lt 1024 -or $limits.metadataBytes -gt 16MB -or
        $limits.definitionParseBytes -gt 16MB -or $limits.definitionLineBytes -gt 16MB -or
        $limits.depth -gt 256 -or $limits.aliasHops -gt 256) {
        throw 'Overlay metadata, definition, depth or alias limits exceed the bounded adapter profile.'
    }
    return [pscustomobject]$limits
}

function Read-SwiftUIOverlayMetadata {
    param([Parameter(Mandatory)][string]$Path, [long]$MaximumBytes = 16MB)
    $file = Read-SwiftUIAuditBoundedText -Path $Path -MaximumBytes $MaximumBytes
    Initialize-SwiftUIBaselineStreaming
    [SwiftUIBaseline.Streaming.AuditReviewPacketWriter]::ValidateMetadataObject($file.text, [int]$MaximumBytes)
    $arguments = @{ InputObject = $file.text; ErrorAction = 'Stop' }
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $arguments.DateKind = 'String' }
    $value = ConvertFrom-Json @arguments
    return [pscustomobject]@{ path = $file.path; bytes = $file.bytes; sha256 = $file.sha256; value = $value }
}

function Get-SwiftUIOverlayId {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Components)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    try {
        foreach ($component in @('swiftui-overlay-record-v1') + $Components) {
            if ($null -eq $component) { throw 'Record identity components cannot be null.' }
            $bytes = $encoding.GetBytes($component)
            $length = $encoding.GetBytes(([string]$bytes.Length) + ':')
            [void]$algorithm.TransformBlock($length, 0, $length.Length, $null, 0)
            [void]$algorithm.TransformBlock($bytes, 0, $bytes.Length, $null, 0)
        }
        [void]$algorithm.TransformFinalBlock([byte[]]@(), 0, 0)
        return [BitConverter]::ToString($algorithm.Hash).Replace('-', '').ToLowerInvariant()
    } finally { $algorithm.Dispose() }
}

function ConvertFrom-SwiftUIOverlayDefinition {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [long]$MaximumBytes = 1MB, [long]$MaximumLineBytes = 64KB,
        [long]$MaximumNames = 4096)
    if ($MaximumBytes -lt 1 -or $MaximumBytes -gt 16MB -or $MaximumLineBytes -lt 1 -or
        $MaximumLineBytes -gt 16MB -or $MaximumNames -lt 1 -or $MaximumNames -gt [int]::MaxValue) {
        throw 'Invalid canonical overlay parser limits.'
    }
    $result = [ordered]@{
        profile = 'swiftcrossimport-canonical-v1'; status = 'parsed-canonical-v1'; version = $null
        nameOccurrences = @(); issues = @()
    }
    $failure = {
        param([string]$Status, [string]$Code, [int]$Line, [string]$Message)
        $result.status = $Status
        $result.nameOccurrences = @()
        $result.issues = @([pscustomobject]@{ code = $Code; line = $Line; message = $Message })
        return [pscustomobject]$result
    }
    if ($Bytes.LongLength -gt $MaximumBytes) {
        return (& $failure 'limit-reached' 'definition-byte-limit' 0 'Definition exceeds the explicit byte budget.')
    }
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    try { $text = $encoding.GetString($Bytes) }
    catch { return (& $failure 'invalid-to-profile' 'invalid-utf8' 0 'Definition is not strict UTF-8.') }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xfeff) { $text = $text.Substring(1) }
    if ($text.Contains([string][char]13) -and $text.Replace(([string][char]13 + [char]10), '').Contains([string][char]13)) {
        return (& $failure 'unsupported-format' 'bare-carriage-return' 0 'Only LF and CRLF line endings are supported.')
    }
    $lines = $text.Replace(([string][char]13 + [char]10), [string][char]10).Split([char]10)
    $seenVersion = $false; $seenModules = $false; $block = $false; $explicitEmpty = $false
    $seenDirective = $false; $seenMarker = $false; $seenContent = $false
    $names = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $lines.Length; $index++) {
        $line = $lines[$index]; $number = $index + 1
        if ($encoding.GetByteCount($line) -gt $MaximumLineBytes) {
            return (& $failure 'limit-reached' 'definition-line-limit' $number 'Line exceeds the explicit UTF-8 byte budget.')
        }
        if ($line.Contains([string][char]9)) {
            return (& $failure 'unsupported-format' 'tabs' $number 'Tabs are outside the canonical profile.')
        }
        $line = [regex]::Replace($line, '(^| +)#.*$', '').TrimEnd(' ')
        if ($line.Length -eq 0) { continue }
        if ($line -ceq '%YAML 1.2') {
            if ($seenContent -or $seenDirective -or $seenMarker) {
                return (& $failure 'unsupported-format' 'yaml-directive-position' $number 'Directive must appear once before the document.')
            }
            $seenDirective = $true; continue
        }
        if ($line -ceq '---') {
            if ($seenContent -or $seenMarker) {
                return (& $failure 'unsupported-format' 'multiple-documents' $number 'Only one optional document marker is supported.')
            }
            $seenMarker = $true; continue
        }
        $seenContent = $true
        if ($line -cmatch '^([A-Za-z_][A-Za-z0-9_]*):(?: +(.*))?$') {
            $key = $Matches[1]; $value = ''
            if ($Matches.ContainsKey(2)) { $value = $Matches[2] }
            $block = $false
            if ($key -ceq 'version') {
                if ($seenVersion) { return (& $failure 'invalid-to-profile' 'duplicate-key' $number 'Duplicate version mapping key.') }
                $seenVersion = $true
                if ($value -cne '1') {
                    return (& $failure 'unsupported-format' 'unsupported-version' $number 'This auditor supports only canonical version 1.')
                }
                $result.version = 1
            } elseif ($key -ceq 'modules') {
                if ($seenModules) { return (& $failure 'invalid-to-profile' 'duplicate-key' $number 'Duplicate modules mapping key.') }
                $seenModules = $true
                if ($value -ceq '[]') { $explicitEmpty = $true }
                elseif ($value.Length -eq 0) { $block = $true }
                else { return (& $failure 'unsupported-format' 'modules-syntax' $number 'Only a canonical block sequence or explicit [] is supported.') }
            } else { return (& $failure 'invalid-to-profile' 'unknown-key' $number 'Unknown root mapping key.') }
            continue
        }
        if ($block -and $line -cmatch '^  - name: ([A-Za-z_][A-Za-z0-9_]*)$') {
            if ($names.Count -ge $MaximumNames) {
                return (& $failure 'limit-reached' 'definition-name-limit' $number 'Module entry count exceeds its explicit budget.')
            }
            [void]$names.Add([pscustomobject]@{ index = $names.Count; name = $Matches[1] })
            continue
        }
        if ($line -cmatch '^  -(?:$| +[A-Za-z_][A-Za-z0-9_]*:)' -or
            $line -cmatch '^    [A-Za-z_][A-Za-z0-9_]*:') {
            if ($block -and $line -cmatch '^  - name:') {
                return (& $failure 'unsupported-format' 'module-name-syntax' $number 'Module names must be plain ASCII identifiers.')
            }
            return (& $failure 'invalid-to-profile' 'module-mapping' $number 'Missing, unknown or duplicate module mapping key.')
        }
        return (& $failure 'unsupported-format' 'noncanonical-yaml' $number 'YAML syntax is outside the declared canonical profile.')
    }
    if (-not $seenVersion -or -not $seenModules) {
        return (& $failure 'invalid-to-profile' 'missing-key' 0 'Both version and modules are required.')
    }
    if (-not $explicitEmpty -and $names.Count -eq 0) {
        return (& $failure 'unsupported-format' 'implicit-null-modules' 0 'An implicit null is not an explicit empty module sequence.')
    }
    $result.nameOccurrences = $names.ToArray()
    return [pscustomobject]$result
}

function ConvertTo-SwiftUIOverlayUnixPath {
    param([Parameter(Mandatory)][string]$Path, [AllowNull()][string]$BasePath)
    if ($Path -match '[\\\x00-\x1f\x7f]' -or $Path.Contains([string][char]0xfffd) -or $Path.Length -gt 65536) {
        throw 'Unsupported Unix source path encoding or length.'
    }
    [void]([Text.UTF8Encoding]::new($false, $true).GetByteCount($Path))
    if (-not $Path.StartsWith('/', [StringComparison]::Ordinal)) {
        if ([string]::IsNullOrEmpty($BasePath)) { throw 'Source paths must be Unix absolute paths.' }
        $Path = $BasePath.TrimEnd('/') + '/' + $Path
    }
    $parts = [Collections.Generic.List[string]]::new()
    foreach ($part in $Path.Split('/')) {
        if ($part.Length -eq 0 -or $part -ceq '.') { continue }
        if ($part -ceq '..') {
            if ($parts.Count -eq 0) { throw 'Unix path traverses above its root.' }
            $parts.RemoveAt($parts.Count - 1); continue
        }
        [void]$parts.Add($part)
    }
    return '/' + [string]::Join('/', $parts.ToArray())
}

function Get-SwiftUIOverlayUnixParent {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -ceq '/') { return '/' }
    $index = $Path.LastIndexOf('/')
    if ($index -le 0) { return '/' }
    return $Path.Substring(0, $index)
}

function Test-SwiftUIOverlayInside {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)
    return $Path -ceq $Root -or $Path.StartsWith($Root.TrimEnd('/') + '/', [StringComparison]::Ordinal)
}

function Read-SwiftUIOverlayDiscoveryInputs {
    param([Parameter(Mandatory)][string]$CaptureRoot, [Parameter(Mandatory)][string]$AuditRoot,
        [Parameter(Mandatory)][string]$ManifestPath, [switch]$AllowSyntheticForTests)
    foreach ($path in @(
        (Resolve-SwiftUIAPIReviewArtifactPath $CaptureRoot 'capture.json'),
        (Resolve-SwiftUIAPIReviewArtifactPath $CaptureRoot 'capture-status.json'),
        (Resolve-SwiftUIAPIReviewArtifactPath $CaptureRoot 'baseline-manifest.json'),
        (Resolve-SwiftUIAPIReviewArtifactPath $AuditRoot 'audit.json'), $ManifestPath
    )) { [void](Read-SwiftUIOverlayMetadata $path) }
    $inputs = Read-SwiftUIAPIReviewInputs -CaptureRoot $CaptureRoot -AuditRoot $AuditRoot -ManifestPath $ManifestPath
    $synthetic = $null -ne (Get-SwiftUIBaselineProperty $inputs.captureContext.capture 'syntheticFixture')
    if ($synthetic -and -not $AllowSyntheticForTests) { throw 'Synthetic captures cannot enter the Mac census entrypoint.' }
    $receipts = [Collections.Generic.List[object]]::new()
    foreach ($entry in @($inputs.recordFiles) + @($inputs.sourceMetadataFiles) + @($inputs.captureContext.inputFiles)) {
        $hash = Get-SwiftUIAuditHashedFile -Path $entry.path -RelativePath $entry.relativePath -Kind 'source-seal' -ExpectedSha256 $entry.sha256
        if ($hash.bytes -ne $entry.bytes) { throw 'Source file byte length changed during seal verification.' }
        [void]$receipts.Add($hash)
        if ($entry.path.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)) {
            [void](Read-SwiftUIOverlayMetadata $entry.path)
        }
    }
    [void]$receipts.Add((Get-SwiftUIAuditHashedFile -Path $inputs.auditManifestPath -RelativePath 'audit.json' -Kind 'audit-manifest' -ExpectedSha256 $inputs.auditManifestSha256))
    [void]$receipts.Add((Get-SwiftUIAuditHashedFile -Path $inputs.captureContext.inventoryPath -RelativePath 'inventory.json' -Kind 'inventory' -ExpectedSha256 $inputs.captureContext.inventorySha256))
    $setHash = [Security.Cryptography.SHA256]::Create()
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    try {
        $last = $null
        foreach ($graph in $inputs.graphInputs) {
            if ($null -ne $last -and [StringComparer]::Ordinal.Compare($last, $graph.relativePath) -ge 0) {
                throw 'Graph inputs must retain unique ordinal path order.'
            }
            $last = $graph.relativePath
            $hash = Get-SwiftUIAuditHashedFile -Path $graph.path -RelativePath $graph.relativePath -Kind 'raw-graph'
            [void]$receipts.Add($hash)
            $line = $encoding.GetBytes($graph.relativePath + [char]9 + $hash.sha256 + [char]10)
            [void]$setHash.TransformBlock($line, 0, $line.Length, $null, 0)
        }
        [void]$setHash.TransformFinalBlock([byte[]]@(), 0, 0)
        $digest = [BitConverter]::ToString($setHash.Hash).Replace('-', '').ToLowerInvariant()
        if ($digest -cne $inputs.captureContext.capture.inventory.graphSetSha256) { throw 'Raw graph-set seal differs from the successful capture.' }
    } finally { $setHash.Dispose() }
    return [pscustomobject]@{ inputs = $inputs; syntheticFixture = $synthetic; fileSeals = $receipts.ToArray()
        graphSetSha256 = $digest; verification = 'all referenced bytes hashed; no new semantic/API/behavior review' }
}

function Assert-SwiftUIOverlaySourceSeals {
    param([Parameter(Mandatory)]$Context)
    foreach ($entry in $Context.fileSeals) {
        $hash = Get-SwiftUIAuditHashedFile -Path $entry.path -RelativePath $entry.relativePath -Kind $entry.kind -ExpectedSha256 $entry.sha256
        if ($hash.bytes -ne $entry.bytes) { throw 'A saved capture/ledger input changed during the observation interval.' }
    }
}

function Assert-SwiftUIOverlayFields {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][hashtable]$Fields,
        [Parameter(Mandatory)][string]$Context)
    if ($Value -isnot [pscustomobject]) { throw "$Context must be a JSON object." }
    $actual = @($Value.PSObject.Properties.Name)
    foreach ($name in $Fields.Keys) {
        if ($actual -cnotcontains $name) { throw "$Context is missing exact field '$name'." }
    }
    Assert-SwiftUIAuditFields -Value $Value -Fields $Fields -Context $Context
}

function Get-SwiftUIOverlayExpectedLayout {
    param([Parameter(Mandatory)]$SourceContext)
    $capture = $SourceContext.inputs.captureContext.capture
    $developer = ConvertTo-SwiftUIOverlayUnixPath $capture.developerDirectoryOverride
    if ($developer -cne $capture.developerDirectoryOverride) { throw 'Captured developer path is not canonical.' }
    $swift = @($capture.tools | Where-Object { $_.path.EndsWith('/usr/bin/swift', [StringComparison]::Ordinal) })
    $extractor = @($capture.tools | Where-Object { $_.path.EndsWith('/usr/bin/swift-symbolgraph-extract', [StringComparison]::Ordinal) })
    if ($swift.Count -ne 1 -or $extractor.Count -ne 1 -or $capture.tools.Count -ne 2) {
        throw 'The census requires the two unambiguous captured XcodeDefault tool paths.'
    }
    $toolchain = $developer + '/Toolchains/XcodeDefault.xctoolchain'
    if ($swift[0].path -cne ($toolchain + '/usr/bin/swift') -or
        $extractor[0].path -cne ($toolchain + '/usr/bin/swift-symbolgraph-extract')) {
        throw 'Captured tools do not belong to the selected XcodeDefault toolchain.'
    }
    $sdk = ConvertTo-SwiftUIOverlayUnixPath $capture.sdk.path
    $platform = $developer + '/Platforms/MacOSX.platform'
    if ($sdk -cne $capture.sdk.path -or -not (Test-SwiftUIOverlayInside ($platform + '/Developer/SDKs') $sdk)) {
        throw 'Captured SDK is outside the selected macOS platform SDK directory.'
    }
    foreach ($command in $capture.commands) {
        if (@($command.arguments) -ccontains '-target-variant') {
            throw 'The initial census profile does not infer a target variant from an unreviewed invocation.'
        }
    }
    $anchors = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in @(
        @{ id = 'swift-tool'; path = $swift[0].path; sha = $swift[0].sha256 },
        @{ id = 'extractor-tool'; path = $extractor[0].path; sha = $extractor[0].sha256 },
        @{ id = 'sdk-settings'; path = $sdk + '/' + $capture.sdk.settingsPath; sha = $capture.sdk.settingsSha256 }
    )) { $anchors.Add($entry.id, [pscustomobject]@{ path = $entry.path; sha256 = $entry.sha }) }
    foreach ($entry in $capture.publicInterfaces) {
        $prefix = 'interfaces/' + $entry.module + '/'
        if (-not $entry.path.StartsWith($prefix, [StringComparison]::Ordinal)) { throw 'Unexpected captured interface path.' }
        $suffix = $entry.path.Substring($prefix.Length)
        $anchors.Add('interface:' + $entry.module + '/' + $suffix, [pscustomobject]@{
            path = $sdk + '/System/Library/Frameworks/' + $entry.module + '.framework/Modules/' +
                $entry.module + '.swiftmodule/' + $suffix
            sha256 = $entry.sha256
        })
    }
    return [pscustomobject]@{
        sdk = $sdk; toolchain = $toolchain; developer = $developer; platform = $platform; anchors = $anchors
        roots = [ordered]@{
            'selected-sdk' = $sdk
            'selected-swift-resources' = $toolchain + '/usr/lib/swift'
            'platform-developer-frameworks' = $platform + '/Developer/Library/Frameworks'
        }
    }
}

function Read-SwiftUIOverlayRootPlan {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ExpectedSha256,
        [Parameter(Mandatory)]$SourceContext)
    Assert-SwiftUIAuditSha256 $ExpectedSha256 'rootPlan.expectedSha256'
    $file = Read-SwiftUIOverlayMetadata $Path
    if ($file.sha256 -cne $ExpectedSha256) { throw 'Root plan hash differs from the explicit authorization.' }
    $plan = $file.value
    Assert-SwiftUIOverlayFields $plan @{
        schemaVersion = 'integer'; evidenceKind = 'string'; sourceCaptureSha256 = 'string'
        sourceAuditSha256 = 'string'; baselineManifestSha256 = 'string'
        targetContexts = 'array'; roots = 'array'; identityAnchors = 'array'
        lookupAuthorizations = 'array'; limits = 'object'; allowIncidentalLinkTargetMetadata = 'boolean'
    } 'rootPlan'
    if ($plan.schemaVersion -ne 1 -or $plan.evidenceKind -cne 'overlay-discovery-root-authorization' -or
        $plan.sourceCaptureSha256 -cne $SourceContext.inputs.captureContext.captureSha256 -or
        $plan.sourceAuditSha256 -cne $SourceContext.inputs.auditManifestSha256 -or
        $plan.baselineManifestSha256 -cne $SourceContext.inputs.currentExpectedBaselineManifestSha256) {
        throw 'Root authorization does not bind the exact successful capture, ledger and supplied baseline.'
    }
    if (-not $plan.allowIncidentalLinkTargetMetadata) {
        throw 'The BCL adapter requires explicit acknowledgement that symlink target metadata may be queried before controller inspection; no outward content/traversal is authorized.'
    }
    $limits = Get-SwiftUIOverlayLimits $plan.limits
    if ($file.bytes -gt $limits.metadataBytes) { throw 'Root authorization exceeds its declared metadata budget.' }
    $layout = Get-SwiftUIOverlayExpectedLayout $SourceContext
    $expectedTargets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($target in $SourceContext.inputs.captureContext.baselineManifest.scope.targets) { [void]$expectedTargets.Add($target) }
    if ($plan.targetContexts.Count -ne $expectedTargets.Count) { throw 'Root plan is missing a pinned target context.' }
    foreach ($target in $plan.targetContexts) {
        Assert-SwiftUIOverlayFields $target @{ target = 'string'; targetVariant = 'nullable-string' } 'rootPlan.targetContexts'
        if (-not $expectedTargets.Remove($target.target) -or $null -ne $target.targetVariant) {
            throw 'Duplicate, changed or inferred target-variant context in root plan.'
        }
    }
    $rootNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $physicalRoots = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $authorizedAncestors = [Collections.Generic.List[string]]::new()
    foreach ($root in $plan.roots) {
        Assert-SwiftUIOverlayFields $root @{
            rootId = 'string'; selection = 'string'; logicalPath = 'string'
            expectedPhysicalPath = 'nullable-string'; allowedPhysicalBoundary = 'nullable-string'; reason = 'string'
        } 'rootPlan.roots'
        if (-not $rootNames.Add($root.rootId) -or @($layout.roots.Keys) -cnotcontains $root.rootId -or
            $root.logicalPath -cne $layout.roots[$root.rootId]) { throw 'Unknown, duplicate or redirected initial census root.' }
        if ($root.rootId -ceq 'platform-developer-frameworks') {
            if (@('selected-optional', 'not-selected') -cnotcontains $root.selection) { throw 'Optional root selection must be explicit.' }
        } elseif ($root.selection -cne 'required') { throw 'Both SDK and Swift resource roots are required.' }
        [void]$authorizedAncestors.Add($root.logicalPath)
        if ($root.selection -ceq 'not-selected') {
            if ($null -ne $root.expectedPhysicalPath -or $null -ne $root.allowedPhysicalBoundary) {
                throw 'A not-selected root cannot authorize a physical traversal.'
            }
            continue
        }
        if ([string]::IsNullOrEmpty($root.expectedPhysicalPath) -or $root.expectedPhysicalPath -ceq '/' -or
            (ConvertTo-SwiftUIOverlayUnixPath $root.expectedPhysicalPath) -cne $root.expectedPhysicalPath -or
            $root.allowedPhysicalBoundary -cne $root.expectedPhysicalPath -or
            -not $physicalRoots.Add($root.expectedPhysicalPath)) {
            throw 'Physical root must be exact, canonical, unique and its own traversal boundary.'
        }
        [void]$authorizedAncestors.Add($root.expectedPhysicalPath)
    }
    if ($rootNames.Count -ne 3) { throw 'All three initial root selections, including the optional not-selected root, must be recorded.' }
    $sdkRoot = @($plan.roots | Where-Object { $_.rootId -ceq 'selected-sdk' })[0]
    $toolPhysicalBoundary = $null
    $anchorNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($anchor in $plan.identityAnchors) {
        Assert-SwiftUIOverlayFields $anchor @{
            anchorId = 'string'; logicalPath = 'string'; allowedPhysicalBoundary = 'string'; expectedSha256 = 'string'
        } 'rootPlan.identityAnchors'
        if (-not $anchorNames.Add($anchor.anchorId) -or -not $layout.anchors.ContainsKey($anchor.anchorId)) {
            throw 'Unknown or duplicate identity anchor.'
        }
        $expected = $layout.anchors[$anchor.anchorId]
        if ($anchor.logicalPath -cne $expected.path -or $anchor.expectedSha256 -cne $expected.sha256 -or
            (ConvertTo-SwiftUIOverlayUnixPath $anchor.allowedPhysicalBoundary) -cne $anchor.allowedPhysicalBoundary) {
            throw 'Identity anchor differs from the source capture or has a noncanonical physical boundary.'
        }
        if ($anchor.anchorId -cin @('swift-tool', 'extractor-tool')) {
            if (-not $anchor.allowedPhysicalBoundary.EndsWith('/Toolchains/XcodeDefault.xctoolchain', [StringComparison]::Ordinal) -or
                ($null -ne $toolPhysicalBoundary -and $toolPhysicalBoundary -cne $anchor.allowedPhysicalBoundary)) {
                throw 'Both tool anchors require one explicit XcodeDefault physical toolchain boundary.'
            }
            $toolPhysicalBoundary = $anchor.allowedPhysicalBoundary
        } elseif ($anchor.allowedPhysicalBoundary -cne $sdkRoot.expectedPhysicalPath) {
            throw 'SDK settings and captured interface anchors must remain inside the selected physical SDK.'
        }
        [void]$authorizedAncestors.Add($anchor.logicalPath)
        [void]$authorizedAncestors.Add($anchor.allowedPhysicalBoundary)
    }
    if ($anchorNames.Count -ne $layout.anchors.Count) { throw 'Root plan must bind both tools, SDK settings and every captured interface.' }
    $physicalDeveloper = $toolPhysicalBoundary.Substring(0, $toolPhysicalBoundary.Length - '/Toolchains/XcodeDefault.xctoolchain'.Length)
    $physicalSDKParent = $physicalDeveloper + '/Platforms/MacOSX.platform/Developer/SDKs'
    $physicalResourceParent = $toolPhysicalBoundary + '/usr/lib'
    $physicalPlatformParent = $physicalDeveloper + '/Platforms/MacOSX.platform/Developer/Library'
    foreach ($root in $plan.roots) {
        if ($root.selection -ceq 'not-selected') { continue }
        $expectedParent = $physicalSDKParent
        if ($root.rootId -ceq 'selected-swift-resources') { $expectedParent = $physicalResourceParent }
        if ($root.rootId -ceq 'platform-developer-frameworks') { $expectedParent = $physicalPlatformParent }
        if ($root.expectedPhysicalPath -ceq $expectedParent -or
            -not (Test-SwiftUIOverlayInside $expectedParent $root.expectedPhysicalPath)) {
            throw 'A physical root cannot widen the selected SDK, toolchain-resource or platform-framework boundary.'
        }
    }
    $lookupNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($lookup in $plan.lookupAuthorizations) {
        Assert-SwiftUIOverlayFields $lookup @{
            lookupId = 'string'; kind = 'string'; exactPath = 'string'; purpose = 'string'
            mayEnumerateChildren = 'boolean'; mayTraverseDescendants = 'boolean'
        } 'rootPlan.lookupAuthorizations'
        if (-not $lookupNames.Add($lookup.lookupId) -or
            @('ancestor-metadata', 'link-metadata', 'nonrecursive-parent-listing') -cnotcontains $lookup.kind -or
            (ConvertTo-SwiftUIOverlayUnixPath $lookup.exactPath) -cne $lookup.exactPath -or $lookup.mayTraverseDescendants -or
            $lookup.mayEnumerateChildren -ne ($lookup.kind -ceq 'nonrecursive-parent-listing')) {
            throw 'Invalid or duplicate narrowly bounded lookup authorization.'
        }
        $isAncestor = $false
        foreach ($path in $authorizedAncestors) {
            if (Test-SwiftUIOverlayInside $lookup.exactPath $path) { $isAncestor = $true; break }
        }
        if (-not $isAncestor) { throw 'A lookup authorization cannot introduce an unrelated filesystem location.' }
        if ($lookup.kind -ceq 'nonrecursive-parent-listing') {
            $isDirectParent = $false
            foreach ($path in $authorizedAncestors) {
                if ((Get-SwiftUIOverlayUnixParent $path) -ceq $lookup.exactPath) { $isDirectParent = $true; break }
            }
            if (-not $isDirectParent) { throw 'Parent listings must name an exact immediate root/anchor parent.' }
        }
    }
    return [pscustomobject]@{ file = $file; plan = $plan; limits = $limits; layout = $layout }
}

function New-SwiftUIOverlayMacFileSystemProvider {
    if ($PSVersionTable.PSVersion.Major -lt 7 -or -not $IsMacOS) {
        throw 'The live overlay filesystem adapter requires PowerShell 7 on macOS. No native command was run.'
    }
    return [pscustomobject]@{
        name = 'dotnet-powershell7-macos-filesystem-v1'; isSynthetic = $false; state = $null
        incidentalLinkTargetMetadataPossible = $true
        getInfo = {
            param([string]$Path, $ProviderState)
            # BCL metadata may stat link targets. The root plan acknowledges
            # this separately; no target content is opened by this operation.
            # Attributes throws on failed lookup; Exists would collapse errors.
            $attributes = [IO.File]::GetAttributes($Path)
            $item = [IO.FileInfo]::new($Path)
            if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) { $item = [IO.DirectoryInfo]::new($Path) }
            $item.Refresh()
            $link = $null
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $link = $item.LinkTarget }
            $kind = 'file'
            if ($null -ne $link) { $kind = 'symlink' }
            elseif (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Unsupported filesystem reparse point.' }
            elseif (($attributes -band [IO.FileAttributes]::Directory) -ne 0) { $kind = 'directory' }
            $length = [long]0
            if ($kind -ceq 'file') { $length = ([IO.FileInfo]$item).Length }
            return [pscustomobject]@{
                path = $Path; kind = $kind; attributes = [string]$attributes; length = $length
                lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o'); creationTimeUtc = $item.CreationTimeUtc.ToString('o')
                linkTarget = $link
            }
        }
        enumerate = {
            param([string]$Path, $ProviderState, [scriptblock]$Visitor)
            # Entry initialization may query symlink target metadata even with
            # these explicit options. It does not recurse into those targets.
            $options = [IO.EnumerationOptions]::new()
            $options.AttributesToSkip = 0; $options.RecurseSubdirectories = $false
            $options.IgnoreInaccessible = $false; $options.ReturnSpecialDirectories = $false
            $enumerator = ([IO.DirectoryInfo]::new($Path)).EnumerateFileSystemInfos('*', $options).GetEnumerator()
            try {
                while ($enumerator.MoveNext()) {
                    $entry = $enumerator.Current
                    & $Visitor ([pscustomobject]@{ name = $entry.Name; path = $entry.FullName })
                }
            } finally { if ($enumerator -is [IDisposable]) { $enumerator.Dispose() } }
        }
        openRead = {
            param([string]$Path, $ProviderState)
            return [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        }
    }
}

function New-SwiftUIOverlayProblem {
    param([string]$Code, [string]$Path, [string]$Message, [Exception]$InnerException)
    $exception = [IO.InvalidDataException]::new($Message, $InnerException)
    $exception.Data['OverlayCode'] = $Code
    $exception.Data['OverlayPath'] = $Path
    return $exception
}

function Get-SwiftUIOverlayProblem {
    param([Exception]$Exception)
    $current = $Exception
    $code = 'observation-error'; $path = $null
    while ($null -ne $current) {
        if ($current.Data.Contains('OverlayCode')) {
            $code = [string]$current.Data['OverlayCode']; $path = [string]$current.Data['OverlayPath']; break
        }
        $current = $current.InnerException
    }
    $chain = [Collections.Generic.List[object]]::new()
    $current = $Exception
    while ($null -ne $current -and $chain.Count -lt 16) {
        $message = $current.Message; $messageHash = $null
        if ($message.Length -gt 65536) { $messageHash = Get-SwiftUIOverlayId @('exception-message', $message); $message = $null }
        [void]$chain.Add([pscustomobject]@{ exceptionType = $current.GetType().FullName; hresult = $current.HResult
            message = $message; originalMessageLength = $current.Message.Length; uncapturedMessageRecordId = $messageHash })
        $current = $current.InnerException
    }
    return [pscustomobject]@{
        code = $code; path = $path; exceptionType = $Exception.GetType().FullName
        hresult = $Exception.HResult; message = $chain[0].message; causes = $chain.ToArray()
        exceptionChainComplete = ($null -eq $current)
    }
}

function Test-SwiftUIOverlayNotFound {
    param([Exception]$Exception)
    $current = $Exception
    while ($null -ne $current) {
        if ($current -is [UnauthorizedAccessException]) { return $false }
        if ($current -is [IO.FileNotFoundException] -or $current -is [IO.DirectoryNotFoundException]) { return $true }
        $current = $current.InnerException
    }
    return $false
}

function Write-SwiftUIOverlayRecord {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$Stream,
        [Parameter(Mandatory)]$Record)
    if (-not $Session.streams.ContainsKey($Stream)) { throw 'Unknown census record stream.' }
    if ($Record -is [Collections.IDictionary] -and -not $Record.Contains('recordId')) {
        $Record['recordId'] = Get-SwiftUIOverlayId @('event', $Stream, [string]$Session.streams[$Stream].recordCount)
    }
    $json = ConvertTo-Json -InputObject $Record -Depth 40 -Compress
    $bytes = $Session.encoding.GetByteCount($json) + 1
    if ($bytes -gt $Session.limits.metadataBytes -or
        $Session.counts.reportBytes + $bytes -gt $Session.limits.reportBytes) {
        throw (New-SwiftUIOverlayProblem 'report-byte-limit' $null 'Census record/report budget reached; output is incomplete.')
    }
    $entry = $Session.streams[$Stream]
    $entry.writer.WriteLine($json)
    $entry.recordCount++
    $entry.bytes += $bytes
    $Session.counts.reportBytes += $bytes
}

function Write-SwiftUIOverlayIssue {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)]$Issue)
    $Session.counts.issues++
    if ($null -eq $Session.terminalIssue) { $Session.terminalIssue = $Issue }
    try {
        Write-SwiftUIOverlayRecord $Session 'issues' ([ordered]@{
            kind = 'issue'; recordId = Get-SwiftUIOverlayId @('issue', [string]$Session.counts.issues, [string]$Issue.code)
            code = $Issue.code; path = $Issue.path; exceptionType = $Issue.exceptionType
            hresult = $Issue.hresult; message = $Issue.message; causes = $Issue.causes
            exceptionChainComplete = $Issue.exceptionChainComplete; scopeAffected = 'incomplete-observation'
        })
    } catch { $Session.counts.issuesNotWritten++ }
}

function Get-SwiftUIOverlayInfo {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$Path)
    $Session.counts.metadataLookups++
    if ($Session.counts.metadataLookups -gt $Session.derivedLimits.metadataLookups) {
        throw (New-SwiftUIOverlayProblem 'metadata-lookup-limit' $Path 'Metadata lookup budget reached.')
    }
    try { $values = @(& $Session.provider.getInfo $Path $Session.provider.state) }
    catch { throw (New-SwiftUIOverlayProblem 'metadata-error' $Path 'Filesystem metadata lookup failed; this is not proof of absence.' $_.Exception) }
    if ($values.Count -ne 1 -or $values[0] -isnot [pscustomobject]) {
        throw (New-SwiftUIOverlayProblem 'provider-info-contract' $Path 'Provider must return one non-null metadata snapshot.')
    }
    $info = $values[0]
    Assert-SwiftUIOverlayFields $info @{
        path = 'string'; kind = 'string'; attributes = 'string'; length = 'integer'
        lastWriteTimeUtc = 'string'; creationTimeUtc = 'string'; linkTarget = 'nullable-string'
    } 'filesystem snapshot'
    if ($info.path -cne $Path -or @('file', 'directory', 'symlink') -cnotcontains $info.kind -or
        ($info.kind -ceq 'symlink') -ne (-not [string]::IsNullOrEmpty($info.linkTarget))) {
        throw (New-SwiftUIOverlayProblem 'provider-info-contract' $Path 'Provider returned a redirected path or ambiguous entry kind.')
    }
    # Scalar copies prevent a fake/live mutable object changing prior evidence.
    return [pscustomobject]@{
        path = [string]$info.path; kind = [string]$info.kind; attributes = [string]$info.attributes
        length = [long]$info.length; lastWriteTimeUtc = [string]$info.lastWriteTimeUtc
        creationTimeUtc = [string]$info.creationTimeUtc; linkTarget = $info.linkTarget
    }
}

function Get-SwiftUIOverlayFingerprint {
    param([Parameter(Mandatory)]$Info)
    return Get-SwiftUIOverlayId @(
        [string]$Info.path, [string]$Info.kind, [string]$Info.attributes, [string]$Info.length,
        [string]$Info.lastWriteTimeUtc, [string]$Info.creationTimeUtc, [string]$Info.linkTarget)
}

function Test-SwiftUIOverlayLookup {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$Path,
        [ValidateSet('metadata', 'enumerate')][string]$Operation = 'metadata',
        [AllowNull()]$Anchor)
    foreach ($root in $Session.plan.roots) {
        if ($root.selection -cne 'not-selected' -and
            (Test-SwiftUIOverlayInside $root.expectedPhysicalPath $Path)) { return $true }
    }
    if ($Operation -ceq 'metadata' -and $null -ne $Anchor -and
        (Test-SwiftUIOverlayInside $Anchor.allowedPhysicalBoundary $Path)) { return $true }
    foreach ($lookup in $Session.plan.lookupAuthorizations) {
        if ($lookup.exactPath -ceq $Path -and
            ($Operation -ceq 'metadata' -or $lookup.mayEnumerateChildren)) { return $true }
    }
    return $false
}

function Test-SwiftUIOverlayContentRoot {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$Path)
    foreach ($root in $Session.plan.roots) {
        if ($root.selection -cne 'not-selected' -and (Test-SwiftUIOverlayInside $root.expectedPhysicalPath $Path)) { return $true }
    }
    return $false
}

function Invoke-SwiftUIOverlayEnumeration {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][scriptblock]$Visitor)
    if (-not (Test-SwiftUIOverlayLookup $Session $Path 'enumerate')) {
        throw (New-SwiftUIOverlayProblem 'lookup-not-authorized' $Path 'Directory enumeration was not explicitly authorized.')
    }
    $Session.counts.enumerationPasses++
    if ($Session.counts.enumerationPasses -gt $Session.derivedLimits.enumerationPasses) {
        throw (New-SwiftUIOverlayProblem 'enumeration-limit' $Path 'Enumeration pass budget reached.')
    }
    $gate = {
        param($Entry)
        $Session.counts.filesystemEntries++
        if ($Session.counts.filesystemEntries -gt $Session.limits.filesystemEntries) {
            throw (New-SwiftUIOverlayProblem 'entry-limit' $Path 'Filesystem entry budget reached.')
        }
        $validEntry = $false; $validationFailure = $null
        try {
            $validEntry = $Entry -is [pscustomobject] -and $Entry.name -is [string] -and
                $Entry.path -is [string] -and -not [string]::IsNullOrEmpty($Entry.name) -and
                -not $Entry.name.Contains('/') -and $Entry.name -cne '.' -and $Entry.name -cne '..' -and
                $Entry.path -ceq ($Path.TrimEnd('/') + '/' + $Entry.name) -and
                (ConvertTo-SwiftUIOverlayUnixPath $Entry.path) -ceq $Entry.path
        } catch { $validationFailure = $_.Exception }
        if (-not $validEntry) {
            $name = $null; $reportedPath = $null
            if ($Entry -is [pscustomobject]) {
                if ($Entry.name -is [string]) { $name = $Entry.name }
                if ($Entry.path -is [string]) { $reportedPath = $Entry.path }
            }
            Write-SwiftUIOverlayRecord $Session 'filesystem-facts' ([ordered]@{
                kind = 'ambiguous-directory-entry'; parentPhysicalPath = $Path
                reportedName = $(if ($null -ne $name -and $name.Length -le 65536) { $name } else { $null })
                reportedPhysicalPath = $(if ($null -ne $reportedPath -and $reportedPath.Length -le 65536) { $reportedPath } else { $null })
                reportedNameCharacters = $(if ($null -eq $name) { $null } else { $name.Length })
                reportedPathCharacters = $(if ($null -eq $reportedPath) { $null } else { $reportedPath.Length })
                rawFilesystemBytesAvailable = $false; metadataQueriedByController = $false
                state = 'incomplete-ambiguous-name'
            })
            throw (New-SwiftUIOverlayProblem 'non-shallow-entry' $Path 'Provider yielded ambiguous, unrepresentable or non-shallow child text; it is not absence evidence.' $validationFailure)
        }
        & $Visitor $Entry
    }.GetNewClosure()
    try {
        $leaked = @(& $Session.provider.enumerate $Path $Session.provider.state $gate)
        if ($leaked.Count -ne 0) { throw (New-SwiftUIOverlayProblem 'provider-enumeration-output' $Path 'Enumeration must use its visitor and produce no pipeline data.') }
    } catch {
        $problem = Get-SwiftUIOverlayProblem $_.Exception
        if ($problem.code -cne 'observation-error') { throw }
        throw (New-SwiftUIOverlayProblem 'enumeration-error' $Path 'Directory enumeration did not reach EOF; earlier entries remain partial evidence.' $_.Exception)
    }
}

function ConvertTo-SwiftUIOverlayLinkTarget {
    param([Parameter(Mandatory)][string]$RawTarget, [Parameter(Mandatory)][string]$PhysicalParent)
    if ($RawTarget.StartsWith('//', [StringComparison]::Ordinal)) { throw 'Implementation-defined double-root aliases are unsupported.' }
    $parts = @($RawTarget.Split('/') | Where-Object { $_.Length -gt 0 -and $_ -cne '.' })
    $absolute = $RawTarget.StartsWith('/', [StringComparison]::Ordinal)
    $seenUnresolvedComponent = $false
    foreach ($part in $parts) {
        if ($part -ceq '..' -and ($absolute -or $seenUnresolvedComponent)) {
            throw 'Alias target has parent traversal after an unresolved component; lexical normalization would change POSIX semantics.'
        }
        if ($part -cne '..') { $seenUnresolvedComponent = $true }
    }
    return ConvertTo-SwiftUIOverlayUnixPath $RawTarget $PhysicalParent
}

function Resolve-SwiftUIOverlaySourcePath {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$LogicalOccurrence, [AllowNull()]$Anchor,
        [int]$HopCount = 0, [AllowEmptyCollection()][string[]]$AliasAncestors = @(), [switch]$AllowLookupOnlyTarget)
    $normalized = ConvertTo-SwiftUIOverlayUnixPath $Path
    if ($normalized -cne $Path) { throw (New-SwiftUIOverlayProblem 'noncanonical-path' $Path 'Input path must be canonical before filesystem lookup.') }
    if ($HopCount -gt $Session.limits.aliasHops) {
        throw (New-SwiftUIOverlayProblem 'alias-hop-limit' $Path 'Alias resolution hop budget reached.')
    }
    $current = '/'
    $parts = @($Path.Split('/') | Where-Object { $_.Length -gt 0 })
    $lastInfo = $null
    for ($index = 0; $index -lt $parts.Count; $index++) {
        $candidate = $current.TrimEnd('/') + '/' + $parts[$index]
        if (-not (Test-SwiftUIOverlayLookup $Session $candidate 'metadata' $Anchor)) {
            throw (New-SwiftUIOverlayProblem 'lookup-not-authorized' $candidate 'Metadata lookup is outside frozen root/anchor/ancestor authorizations.')
        }
        $info = Get-SwiftUIOverlayInfo $Session $candidate
        if ($info.kind -ceq 'symlink') {
            $remaining = ''
            if ($index + 1 -lt $parts.Count) { $remaining = '/' + [string]::Join('/', $parts[($index + 1)..($parts.Count - 1)]) }
            try { $target = ConvertTo-SwiftUIOverlayLinkTarget $info.linkTarget (Get-SwiftUIOverlayUnixParent $candidate) }
            catch {
                Write-SwiftUIOverlayRecord $Session 'alias-facts' ([ordered]@{
                    kind = 'alias-resolution'; logicalOccurrence = $LogicalOccurrence; logicalPath = $candidate
                    rawTarget = $info.linkTarget; disposition = 'unsupported-target'
                    targetContentOpenedByController = $false; controllerTraversedTarget = $false
                })
                throw (New-SwiftUIOverlayProblem 'unsupported-link-target' $candidate 'Alias target semantics are outside the bounded adapter; raw target was retained.' $_.Exception)
            }
            $effectivePath = $target
            if ($remaining.Length -gt 0) { $effectivePath = $target.TrimEnd('/') + $remaining }
            $effectiveTarget = ConvertTo-SwiftUIOverlayUnixPath $effectivePath
            $allowed = $false; $targetRoot = $null
            foreach ($root in $Session.plan.roots) {
                if ($root.selection -cne 'not-selected' -and (Test-SwiftUIOverlayInside $root.expectedPhysicalPath $effectiveTarget)) {
                    $allowed = $true; $targetRoot = $root.rootId; break
                }
            }
            if ($null -ne $Anchor -and (Test-SwiftUIOverlayInside $Anchor.allowedPhysicalBoundary $effectiveTarget)) { $allowed = $true }
            if ($AllowLookupOnlyTarget) {
                foreach ($lookup in $Session.plan.lookupAuthorizations) {
                    if ($lookup.exactPath -ceq $effectiveTarget) { $allowed = $true; break }
                }
            }
            # A root's logical alias may point exactly to its explicitly reviewed
            # physical root. It never authorizes the rest of a containing tree.
            $cycle = $AliasAncestors -ccontains $candidate
            $Session.counts.aliasOccurrences++
            $aliasId = Get-SwiftUIOverlayId @('alias', $LogicalOccurrence, $candidate, $info.linkTarget, [string]$Session.counts.aliasOccurrences)
            $disposition = 'followed-in-allowlist'
            if (-not $allowed) { $disposition = 'outward' }
            elseif ($cycle) { $disposition = 'ancestor-cycle' }
            Write-SwiftUIOverlayRecord $Session 'alias-facts' ([ordered]@{
                kind = 'alias-resolution'; recordId = $aliasId; logicalOccurrence = $LogicalOccurrence
                logicalPath = $candidate; rawTarget = $info.linkTarget; resolutionChain = @($AliasAncestors) + @($candidate)
                resolvedTargetCandidate = $target; effectiveTargetCandidate = $effectiveTarget
                targetRootId = $targetRoot; disposition = $disposition
            })
            if (-not $allowed) { throw (New-SwiftUIOverlayProblem 'outward-alias' $candidate 'Alias target is outside frozen physical boundaries; controller did not resolve, read content, or enumerate it. BCL metadata queries remain possible.') }
            if ($cycle) { throw (New-SwiftUIOverlayProblem 'alias-cycle' $candidate 'Alias resolution reached an ancestor alias.') }
            try {
                return Resolve-SwiftUIOverlaySourcePath -Session $Session -Path $effectiveTarget -LogicalOccurrence $LogicalOccurrence -Anchor $Anchor -HopCount ($HopCount + 1) -AliasAncestors (@($AliasAncestors) + @($candidate)) -AllowLookupOnlyTarget:$AllowLookupOnlyTarget
            } catch {
                $outcome = 'unresolved'
                if (Test-SwiftUIOverlayNotFound $_.Exception) { $outcome = 'dangling' }
                Write-SwiftUIOverlayRecord $Session 'alias-facts' ([ordered]@{
                    kind = 'alias-resolution-result'; recordId = Get-SwiftUIOverlayId @('alias-result', $aliasId)
                    aliasAttemptId = $aliasId; logicalPath = $candidate; rawTarget = $info.linkTarget; disposition = $outcome
                })
                throw
            }
        }
        if ($index + 1 -lt $parts.Count -and $info.kind -cne 'directory') {
            throw (New-SwiftUIOverlayProblem 'path-component-kind' $candidate 'A source path ancestor is not a directory.')
        }
        $current = $candidate; $lastInfo = $info
    }
    if ($Path -ceq '/') {
        if (-not (Test-SwiftUIOverlayLookup $Session '/' 'metadata' $Anchor)) { throw 'Root metadata lookup is not authorized.' }
        $lastInfo = Get-SwiftUIOverlayInfo $Session '/'
    }
    return [pscustomobject]@{ physicalPath = $current; info = $lastInfo; aliasHops = $HopCount }
}

function Test-SwiftUIOverlayAbsent {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RootId)
    $parent = Get-SwiftUIOverlayUnixParent $Path
    $name = $Path.Substring($parent.TrimEnd('/').Length + 1)
    if (-not (Test-SwiftUIOverlayLookup $Session $parent 'enumerate')) { return $false }
    $resolved = Resolve-SwiftUIOverlaySourcePath -Session $Session -Path $parent -LogicalOccurrence ('absence-parent:' + $RootId) -AllowLookupOnlyTarget
    if ($resolved.info.kind -cne 'directory') { return $false }
    $found = [pscustomobject]@{ value = $false }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $visitor = {
        param($Entry)
        if (-not $names.Add($Entry.name)) { throw (New-SwiftUIOverlayProblem 'duplicate-entry' $parent 'Duplicate child in parent enumeration.') }
        if ($Entry.name -ceq $name) { $found.value = $true }
        Write-SwiftUIOverlayRecord $Session 'filesystem-facts' ([ordered]@{
            kind = 'absence-parent-entry'; rootId = $RootId; parent = $parent; name = $Entry.name
            path = $Entry.path; state = 'observed-entry-only'
        })
    }.GetNewClosure()
    Invoke-SwiftUIOverlayEnumeration $Session $resolved.physicalPath $visitor
    if ($found.value) { return $false }
    Write-SwiftUIOverlayRecord $Session 'filesystem-facts' ([ordered]@{
        kind = 'root-state'; rootId = $RootId; logicalPath = $Path; state = 'absent-confirmed'
        evidence = 'authorized parent enumeration completed'; parent = $parent; parentEntryCount = $names.Count
    })
    return $true
}

function New-SwiftUIOverlaySession {
    param([Parameter(Mandatory)]$SourceContext, [Parameter(Mandatory)]$RootPlanContext,
        [Parameter(Mandatory)]$Provider, [Parameter(Mandatory)][string]$OutputDirectory)
    foreach ($property in @('getInfo', 'enumerate', 'openRead')) {
        if ($Provider.$property -isnot [scriptblock]) { throw "Filesystem provider is missing '$property'." }
    }
    if ($Provider.isSynthetic -isnot [bool] -or
        $Provider.isSynthetic -ne $SourceContext.syntheticFixture -or
        $Provider.incidentalLinkTargetMetadataPossible -isnot [bool]) {
        throw 'Synthetic filesystem evidence and real capture provenance cannot be combined.'
    }
    $output = Resolve-SwiftUIBaselineFileSystemPath $OutputDirectory
    if (Test-Path -LiteralPath $output) { throw 'Overlay census output must be a new directory; overwrite is forbidden.' }
    $allowedOutput = $false
    foreach ($root in @([IO.Path]::GetTempPath(), (Join-Path (Split-Path -Parent $script:SwiftUIOverlayDiscoveryScriptRoot) 'artifacts'))) {
        $resolvedRoot = Resolve-SwiftUIBaselineFileSystemPath $root
        try { [void](Get-SwiftUIBaselineRelativePath $resolvedRoot $output); $allowedOutput = $true } catch { }
    }
    if (-not $allowedOutput) { throw 'Census output must be owned OS temp or repository artifacts output.' }
    foreach ($inputRoot in @($SourceContext.inputs.captureRoot, $SourceContext.inputs.auditRoot)) {
        $overlap = $false
        try { [void](Get-SwiftUIBaselineRelativePath $inputRoot $output); $overlap = $true } catch { }
        try { [void](Get-SwiftUIBaselineRelativePath $output $inputRoot); $overlap = $true } catch { }
        if ($overlap) { throw 'Census output cannot overlap its immutable capture or audit input.' }
    }
    if ([IO.Path]::DirectorySeparatorChar -eq '/') {
        foreach ($root in $RootPlanContext.plan.roots) {
            if ($root.selection -cne 'not-selected' -and
                ((Test-SwiftUIOverlayInside $root.logicalPath $output) -or
                 (Test-SwiftUIOverlayInside $root.expectedPhysicalPath $output))) {
                throw 'Census output cannot be inside an observed SDK/resource tree.'
            }
        }
        foreach ($anchor in $RootPlanContext.plan.identityAnchors) {
            if (Test-SwiftUIOverlayInside $anchor.allowedPhysicalBoundary $output) {
                throw 'Census output cannot be inside an identity anchor boundary.'
            }
        }
    }
    [void][IO.Directory]::CreateDirectory($output)
    if (@([IO.Directory]::EnumerateFileSystemEntries($output)).Count -ne 0) { throw 'Output became nonempty before ownership was established.' }
    $markerPath = Join-Path $output '.in-progress'
    $marker = [IO.File]::Open($markerPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $session = [pscustomobject]@{
        source = $SourceContext; planContext = $RootPlanContext; plan = $RootPlanContext.plan
        limits = $RootPlanContext.limits; provider = $Provider; output = $output
        startedAtUtc = [DateTime]::UtcNow.ToString('o'); encoding = [Text.UTF8Encoding]::new($false, $true)
        streams = @{}; marker = $marker; markerPath = $markerPath
        terminalIssue = $null; complete = $false; markerRemoved = $false; stopRequested = $false
        copiedFiles = [Collections.Generic.List[object]]::new()
        anchorChecks = [Collections.Generic.List[object]]::new()
        rootStates = [Collections.Generic.List[object]]::new()
        observedPhysicalDirectories = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        counts = [ordered]@{
            filesystemEntries = [long]0; directories = [long]0; enumerationPasses = [long]0
            metadataLookups = [long]0; aliasOccurrences = [long]0; sourceBytesRead = [long]0
            copiedCandidateFiles = [long]0; copiedCandidateBytes = [long]0; reportBytes = [long]0
            definitions = [long]0; parsedDefinitions = [long]0; emptyDefinitions = [long]0
            unsupportedDefinitions = [long]0; moduleMaps = [long]0; moduleLocations = [long]0
            candidates = [long]0; issues = [long]0; issuesNotWritten = [long]0; unvisitedDirectories = [long]0
        }
        derivedLimits = [pscustomobject]@{
            metadataLookups = [long]($RootPlanContext.limits.filesystemEntries + $RootPlanContext.plan.identityAnchors.Count + 3) *
                [long]($RootPlanContext.limits.depth + $RootPlanContext.limits.aliasHops + 2)
            enumerationPasses = [long]2 * $RootPlanContext.limits.directories + [long]2 * $RootPlanContext.plan.lookupAuthorizations.Count + 6
            identityAnchorFileBytes = [long]1GB
            sourceBytesRead = [long]2 * $RootPlanContext.limits.copiedCandidateBytes +
                [long]2 * $RootPlanContext.plan.identityAnchors.Count * [long]1GB
        }
    }
    try {
        [void][IO.Directory]::CreateDirectory((Join-Path $output 'raw'))
        foreach ($name in @('filesystem-facts', 'alias-facts', 'definition-facts', 'module-context-facts', 'candidate-pairs', 'issues')) {
            $path = Join-Path $output ($name + '.ndjson')
            $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
            $writer = [IO.StreamWriter]::new($stream, $session.encoding, 65536)
            $writer.NewLine = [string][char]10
            $session.streams.Add($name, [pscustomobject]@{ writer = $writer; path = $path; relativePath = $name + '.ndjson'; recordCount = [long]0; bytes = [long]0 })
        }
        # The raw bounded root plan preserves unknown JSON fields and spellings.
        $planCopy = Join-Path $output 'root-plan.json'
        $source = [IO.File]::OpenRead($RootPlanContext.file.path)
        $destination = $null
        try {
            $destination = [IO.File]::Open($planCopy, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
            $maximum = [Math]::Min([long]$RootPlanContext.file.bytes, [long]$session.limits.metadataBytes)
            if ($source.Length -gt $maximum) { throw 'Root plan grew beyond its bounded intake before copy.' }
            $buffer = [byte[]]::new(65536); $copied = [long]0
            while ($true) {
                $read = $source.Read($buffer, 0, [int][Math]::Min([long]$buffer.Length, $maximum - $copied + 1))
                if ($read -eq 0) { break }
                if ($copied + $read -gt $maximum) { throw 'Root plan grew beyond its bounded copy budget.' }
                $destination.Write($buffer, 0, $read); $copied += $read
            }
        } finally {
            try { if ($null -ne $destination) { $destination.Dispose() } }
            finally { $source.Dispose() }
        }
        [void](Get-SwiftUIAuditHashedFile $planCopy 'root-plan.json' 'root-authorization' $RootPlanContext.file.sha256)
        foreach ($root in $session.plan.roots) {
            $state = 'unvisited'
            if ($root.selection -ceq 'not-selected') { $state = 'not-selected' }
            [void]$session.rootStates.Add([pscustomobject]@{ rootId = $root.rootId; state = $state; logicalPath = $root.logicalPath
                expectedPhysicalPath = $root.expectedPhysicalPath; traversalComplete = $false })
        }
        return $session
    } catch {
        Close-SwiftUIOverlayStreams -Session $session -IncludeMarker -PriorFailure $_.Exception
        throw
    }
}

function Read-SwiftUIOverlayFilePass {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$PhysicalPath,
        [Parameter(Mandatory)][long]$MaximumBytes, [AllowNull()][string]$CopyPath,
        [switch]$CaptureDefinitionBytes, [AllowNull()]$Anchor)
    $readAllowed = Test-SwiftUIOverlayContentRoot $Session $PhysicalPath
    if ($null -ne $Anchor -and (Test-SwiftUIOverlayInside $Anchor.allowedPhysicalBoundary $PhysicalPath)) {
        $readAllowed = @($Session.plan.identityAnchors | Where-Object {
            $_.anchorId -ceq $Anchor.anchorId -and $_.logicalPath -ceq $Anchor.logicalPath -and $_.expectedSha256 -ceq $Anchor.expectedSha256
        }).Count -eq 1
    }
    if (-not $readAllowed) { throw (New-SwiftUIOverlayProblem 'content-root-boundary' $PhysicalPath 'A lookup-only authorization never permits a source content read.') }
    $source = $null; $destination = $null; $memory = $null; $values = @()
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $copied = [long]0; $failure = $null; $digest = $null; $definitionBytes = $null; $definitionOverBudget = $false
    try {
        $values = @(& $Session.provider.openRead $PhysicalPath $Session.provider.state)
        if ($values.Count -ne 1 -or $values[0] -isnot [IO.Stream]) {
            throw (New-SwiftUIOverlayProblem 'provider-stream-contract' $PhysicalPath 'openRead must return one caller-owned readable stream.')
        }
        $source = [IO.Stream]$values[0]
        if (-not $source.CanRead -or ($source.CanSeek -and $source.Position -ne 0)) {
            throw (New-SwiftUIOverlayProblem 'provider-stream-contract' $PhysicalPath 'Source stream is not readable at its beginning.')
        }
        if ($source.CanSeek -and $source.Length -gt $MaximumBytes) {
            throw (New-SwiftUIOverlayProblem 'file-byte-limit' $PhysicalPath 'Source file exceeds its explicit read budget.')
        }
        if (-not [string]::IsNullOrEmpty($CopyPath)) {
            $destination = [IO.File]::Open($CopyPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        }
        if ($CaptureDefinitionBytes) { $memory = [IO.MemoryStream]::new() }
        $buffer = [byte[]]::new(65536)
        while ($true) {
            $request = [int][Math]::Min([long]$buffer.Length, $MaximumBytes - $copied + 1)
            $read = $source.Read($buffer, 0, $request)
            if ($read -eq 0) { break }
            $Session.counts.sourceBytesRead += $read
            if ($read -lt 0 -or $read -gt $request -or $copied + $read -gt $MaximumBytes -or
                $Session.counts.sourceBytesRead -gt $Session.derivedLimits.sourceBytesRead) {
                throw (New-SwiftUIOverlayProblem 'file-byte-limit' $PhysicalPath 'Source read exceeded its finite byte budget; no complete copy is claimed.')
            }
            if ($null -ne $destination -and $Session.counts.copiedCandidateBytes + $read -gt $Session.limits.copiedCandidateBytes) {
                throw (New-SwiftUIOverlayProblem 'copied-byte-limit' $PhysicalPath 'Copied candidate byte budget reached.')
            }
            [void]$algorithm.TransformBlock($buffer, 0, $read, $null, 0)
            if ($null -ne $destination) { $destination.Write($buffer, 0, $read); $Session.counts.copiedCandidateBytes += $read }
            if ($null -ne $memory -and -not $definitionOverBudget) {
                if ($copied + $read -gt $Session.limits.definitionParseBytes) { $definitionOverBudget = $true; $memory.SetLength(0) }
                else { $memory.Write($buffer, 0, $read) }
            }
            $copied += $read
        }
        if ($CaptureDefinitionBytes -and -not $definitionOverBudget) { $definitionBytes = $memory.ToArray() }
    } catch { $failure = $_.Exception }
    finally {
        $cleanupFailures = [Collections.Generic.List[Exception]]::new()
        try {
            [void]$algorithm.TransformFinalBlock([byte[]]@(), 0, 0)
            $digest = [BitConverter]::ToString($algorithm.Hash).Replace('-', '').ToLowerInvariant()
        } catch { [void]$cleanupFailures.Add($_.Exception) }
        $resources = @($algorithm, $memory, $destination, $source) + @($values | Where-Object {
            $_ -is [IO.Stream] -and -not [object]::ReferenceEquals($_, $source)
        })
        foreach ($resource in $resources) {
            if ($null -ne $resource) {
                try { $resource.Dispose() } catch { [void]$cleanupFailures.Add($_.Exception) }
            }
        }
        if ($cleanupFailures.Count -gt 0) {
            if ($null -ne $failure) { $cleanupFailures.Insert(0, $failure) }
            $failure = [AggregateException]::new('Source hashing or cleanup failed after every owned read/copy resource received a disposal attempt.', $cleanupFailures.ToArray())
        }
    }
    return [pscustomobject]@{
        bytes = $copied; sha256 = $digest; complete = ($null -eq $failure); failure = $failure
        definitionBytes = $definitionBytes; definitionOverBudget = $definitionOverBudget
    }
}

function Test-SwiftUIOverlayIdentityAnchors {
    param([Parameter(Mandatory)]$Session, [ValidateSet('before', 'after')][string]$Phase)
    foreach ($anchor in $Session.plan.identityAnchors) {
        $resolved = Resolve-SwiftUIOverlaySourcePath $Session $anchor.logicalPath ('anchor:' + $anchor.anchorId + ':' + $Phase) $anchor
        if ($resolved.info.kind -cne 'file' -or
            -not (Test-SwiftUIOverlayInside $anchor.allowedPhysicalBoundary $resolved.physicalPath)) {
            throw (New-SwiftUIOverlayProblem 'anchor-boundary' $anchor.logicalPath 'Identity anchor did not resolve to a file inside its exact physical boundary.')
        }
        $before = Get-SwiftUIOverlayFingerprint $resolved.info
        if ($resolved.info.length -gt $Session.derivedLimits.identityAnchorFileBytes) {
            throw (New-SwiftUIOverlayProblem 'file-byte-limit' $anchor.logicalPath 'Identity anchor exceeds the bounded read profile before content opening.')
        }
        $read = Read-SwiftUIOverlayFilePass -Session $Session -PhysicalPath $resolved.physicalPath -MaximumBytes $Session.derivedLimits.identityAnchorFileBytes -Anchor $anchor
        if (-not $read.complete) { throw $read.failure }
        $after = Get-SwiftUIOverlayInfo $Session $resolved.physicalPath
        if ($before -cne (Get-SwiftUIOverlayFingerprint $after) -or $read.bytes -ne $after.length -or
            $read.sha256 -cne $anchor.expectedSha256) {
            throw (New-SwiftUIOverlayProblem 'anchor-drift' $anchor.logicalPath 'Live identity anchor bytes or metadata differ from the sealed capture.')
        }
        [void]$Session.anchorChecks.Add([pscustomobject]@{
            anchorId = $anchor.anchorId; phase = $Phase; logicalPath = $anchor.logicalPath
            physicalPath = $resolved.physicalPath; expectedSha256 = $anchor.expectedSha256
            observedSha256 = $read.sha256; bytes = $read.bytes; result = 'matches-recorded-anchor'
        })
    }
}

function Get-SwiftUIOverlayDefinitionContext {
    param([Parameter(Mandatory)][string]$LogicalPath)
    $parts = $LogicalPath.Split('/')
    $directories = [Collections.Generic.List[int]]::new()
    for ($index = 0; $index -lt $parts.Length; $index++) {
        if ($parts[$index].EndsWith('.swiftcrossimport', [StringComparison]::Ordinal)) { [void]$directories.Add($index) }
    }
    $owner = $null; $bystander = $null; $targetDirectory = $null; $shape = 'unclassified-layout'
    if ($directories.Count -eq 1) {
        $directoryIndex = $directories[0]
        $owner = $parts[$directoryIndex].Substring(0, $parts[$directoryIndex].Length - '.swiftcrossimport'.Length)
        $tailCount = $parts.Length - $directoryIndex - 1
        if ($tailCount -eq 1) { $shape = 'global-directory-candidate' }
        elseif ($tailCount -eq 2) { $shape = 'target-directory-candidate'; $targetDirectory = $parts[$directoryIndex + 1] }
    }
    $fileName = $parts[$parts.Length - 1]
    if ($fileName.EndsWith('.swiftoverlay', [StringComparison]::Ordinal)) {
        $bystander = $fileName.Substring(0, $fileName.Length - '.swiftoverlay'.Length)
    }
    if ($null -ne $owner -and $owner -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*\z') { $owner = $null; $shape = 'unclassified-layout' }
    if ($null -ne $bystander -and $bystander -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*\z') { $bystander = $null; $shape = 'unclassified-layout' }
    return [pscustomobject]@{
        declaringModuleClaim = $owner; bystanderModuleClaim = $bystander
        targetDirectory = $targetDirectory; layout = $shape; claimStatus = 'unreviewed'
        basis = 'filesystem spelling only; actual defining-module association and Apple target normalization unobserved'
    }
}

function Copy-SwiftUIOverlayCandidate {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$RootId,
        [Parameter(Mandatory)][string]$LogicalPath, [Parameter(Mandatory)]$Resolved,
        [Parameter(Mandatory)][string]$OccurrenceId, [ValidateSet('overlay', 'module-map')][string]$Kind)
    if ($Resolved.info.kind -cne 'file') {
        throw (New-SwiftUIOverlayProblem 'candidate-kind' $LogicalPath 'A candidate filename does not resolve to a regular file.')
    }
    if ($Session.counts.copiedCandidateFiles -ge $Session.limits.copiedCandidateFiles -or
        $Resolved.info.length -gt $Session.limits.copiedCandidateFileBytes -or
        $Session.counts.copiedCandidateBytes + $Resolved.info.length -gt $Session.limits.copiedCandidateBytes) {
        throw (New-SwiftUIOverlayProblem 'candidate-copy-limit' $LogicalPath 'Candidate count/byte budget reached before copying.')
    }
    $before = Get-SwiftUIOverlayFingerprint $Resolved.info
    $copyRelative = 'raw/' + $OccurrenceId + '.bin'
    $copyPath = Join-Path $Session.output $copyRelative
    $Session.counts.copiedCandidateFiles++
    $readArguments = @{ Session = $Session; PhysicalPath = $Resolved.physicalPath
        MaximumBytes = $Session.limits.copiedCandidateFileBytes; CopyPath = $copyPath; CaptureDefinitionBytes = ($Kind -ceq 'overlay') }
    $first = Read-SwiftUIOverlayFilePass @readArguments
    if (Test-Path -LiteralPath $copyPath -PathType Leaf) {
        [void]$Session.copiedFiles.Add([pscustomobject]@{
            path = $copyRelative; bytes = $first.bytes; sha256 = $first.sha256; copyKind = $Kind
            sourceOccurrenceId = $OccurrenceId; logicalPath = $LogicalPath; physicalPath = $Resolved.physicalPath
            captureComplete = $first.complete
        })
    }
    Write-SwiftUIOverlayRecord $Session 'filesystem-facts' ([ordered]@{
        kind = 'candidate-copy'; recordId = Get-SwiftUIOverlayId @('copy', $OccurrenceId); rootId = $RootId
        sourceOccurrenceId = $OccurrenceId; logicalPath = $LogicalPath; physicalPath = $Resolved.physicalPath
        rawFile = $copyRelative; capturedBytes = $first.bytes; capturedBytesSha256 = $first.sha256
        captureComplete = $first.complete; state = $(if ($first.complete) { 'copied-awaiting-second-read' } else { 'partial-error' })
    })
    if (-not $first.complete) { throw $first.failure }
    $second = Read-SwiftUIOverlayFilePass $Session $Resolved.physicalPath $Session.limits.copiedCandidateFileBytes
    if (-not $second.complete) { throw $second.failure }
    $after = Get-SwiftUIOverlayInfo $Session $Resolved.physicalPath
    if ($before -cne (Get-SwiftUIOverlayFingerprint $after) -or $first.sha256 -cne $second.sha256 -or
        $first.bytes -ne $second.bytes -or $first.bytes -ne $Resolved.info.length) {
        throw (New-SwiftUIOverlayProblem 'changed-file' $LogicalPath 'Candidate bytes or metadata changed between observed reads; first bytes remain preserved.')
    }
    $raw = [ordered]@{ path = $copyRelative; bytes = $first.bytes; sha256 = $first.sha256; captureComplete = $true }
    if ($Kind -ceq 'module-map') {
        $Session.counts.moduleMaps++
        Write-SwiftUIOverlayRecord $Session 'module-context-facts' ([ordered]@{
            kind = 'clang-module-map'; recordId = Get-SwiftUIOverlayId @('module-map', $OccurrenceId)
            filesystemOccurrenceId = $OccurrenceId; logicalPath = $LogicalPath; physicalPath = $Resolved.physicalPath
            rawFile = $raw; contentSeal = 'two-read-byte-match'; moduleNameClaim = $null; targetClaim = $null
            producerHeaderFacts = $null; claimStatus = 'unreviewed'; moduleMapGrammarParsed = $false
        })
        return
    }
    $Session.counts.definitions++
    if ($first.definitionOverBudget) {
        $parsed = [pscustomobject]@{ profile = 'swiftcrossimport-canonical-v1'; status = 'limit-reached'; version = $null
            nameOccurrences = @(); issues = @([pscustomobject]@{ code = 'definition-byte-limit'; line = 0; message = 'Raw bytes retained; definition exceeds the parser budget.' }) }
    } else {
        $parseArguments = @{ Bytes = $first.definitionBytes; MaximumBytes = $Session.limits.definitionParseBytes
            MaximumLineBytes = $Session.limits.definitionLineBytes; MaximumNames = $Session.limits.definitionNameOccurrences }
        $parsed = ConvertFrom-SwiftUIOverlayDefinition @parseArguments
    }
    $context = Get-SwiftUIOverlayDefinitionContext $LogicalPath
    $limitFailure = $null
    if ($parsed.status -ceq 'parsed-canonical-v1') {
        $Session.counts.parsedDefinitions++
        if ($parsed.nameOccurrences.Count -eq 0) { $Session.counts.emptyDefinitions++ }
    } else {
        $Session.counts.unsupportedDefinitions++
        if ($parsed.status -ceq 'limit-reached') {
            $limitFailure = New-SwiftUIOverlayProblem $parsed.issues[0].code $LogicalPath 'Raw current-file bytes retained; parser budget reached and further traversal must stop.'
        } else {
            $problem = New-SwiftUIOverlayProblem 'definition-decode-incomplete' $LogicalPath 'An exact raw definition was retained but its syntax is outside the successful parser profile.'
            Write-SwiftUIOverlayIssue $Session (Get-SwiftUIOverlayProblem $problem)
        }
    }
    $definitionId = Get-SwiftUIOverlayId @('definition', $OccurrenceId, $first.sha256)
    Write-SwiftUIOverlayRecord $Session 'definition-facts' ([ordered]@{
        kind = 'definition-file'; recordId = $definitionId; filesystemOccurrenceId = $OccurrenceId
        rootId = $RootId; logicalPath = $LogicalPath; physicalPath = $Resolved.physicalPath; rawFile = $raw
        context = $context; parserProfile = $parsed.profile; parseStatus = $parsed.status
        version = $parsed.version; nameOccurrences = $parsed.nameOccurrences; issues = $parsed.issues
        reviewStatus = 'unreviewed'
    })
    # Queue every occurrence rather than retaining a growing transitive-name
    # graph in memory. Seed/reverse hints annotate; they never exclude records.
    $reasons = [Collections.Generic.List[string]]::new()
    [void]$reasons.Add('complete-unfiltered-definition-census')
    if ($context.declaringModuleClaim -cin @('SwiftUI', 'SwiftUICore')) { [void]$reasons.Add('seed-declaring-module') }
    if ($context.bystanderModuleClaim -cin @('SwiftUI', 'SwiftUICore')) { [void]$reasons.Add('reverse-bystander-seed') }
    foreach ($target in $Session.plan.targetContexts) {
        $expectedNames = $null
        if ($parsed.status -ceq 'parsed-canonical-v1') { $expectedNames = $parsed.nameOccurrences }
        $Session.counts.candidates++
        Write-SwiftUIOverlayRecord $Session 'candidate-pairs' ([ordered]@{
            kind = 'candidate-pair'; recordId = Get-SwiftUIOverlayId @('candidate', $definitionId, $target.target)
            definitionOccurrenceId = $definitionId; declaringModuleClaim = $context.declaringModuleClaim
            bystanderModuleClaim = $context.bystanderModuleClaim; expectedOverlayNameOccurrences = $expectedNames
            rawTargetDirectory = $context.targetDirectory; target = $target.target; targetVariant = $target.targetVariant
            selectionReasons = $reasons.ToArray(); parseStatus = $parsed.status
            contextStatus = 'unreviewed-target-and-module-applicability'; reviewStatus = 'unreviewed'
        })
    }
    if ($null -ne $limitFailure) { throw $limitFailure }
}

function Invoke-SwiftUIOverlayRootTraversal {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)]$Root, [Parameter(Mandatory)]$ResolvedRoot)
    $pending = [Collections.Generic.Stack[object]]::new()
    $pending.Push([pscustomobject]@{ logicalPath = $Root.logicalPath; physicalPath = $ResolvedRoot.physicalPath
        depth = 0; ancestors = @(); entryId = $null })
    $active = $null
    try {
        while ($pending.Count -gt 0) {
            $active = $pending.Pop()
            if (-not (Test-SwiftUIOverlayContentRoot $Session $active.physicalPath)) {
                throw (New-SwiftUIOverlayProblem 'traversal-root-boundary' $active.logicalPath 'A lookup-only directory cannot become a census subtree.')
            }
            if ($active.depth -gt $Session.limits.depth -or $Session.counts.directories -ge $Session.limits.directories) {
                throw (New-SwiftUIOverlayProblem 'directory-limit' $active.logicalPath 'Directory/depth budget reached.')
            }
            if ($active.ancestors -ccontains $active.physicalPath) {
                throw (New-SwiftUIOverlayProblem 'directory-cycle' $active.logicalPath 'Directory alias reached a physical ancestor.')
            }
            $Session.counts.directories++
            $wasSeen = -not $Session.observedPhysicalDirectories.Add($active.physicalPath)
            $startInfo = Get-SwiftUIOverlayInfo $Session $active.physicalPath
            if ($startInfo.kind -cne 'directory') { throw (New-SwiftUIOverlayProblem 'changed-directory' $active.logicalPath 'Directory entry changed kind before traversal.') }
            $directoryFingerprint = Get-SwiftUIOverlayFingerprint $startInfo
            $directoryId = Get-SwiftUIOverlayId @('directory', $Root.rootId, $active.logicalPath)
            Write-SwiftUIOverlayRecord $Session 'filesystem-facts' ([ordered]@{
                kind = 'directory-open'; recordId = $directoryId; rootId = $Root.rootId
                logicalPath = $active.logicalPath; physicalPath = $active.physicalPath; depth = $active.depth
                sourceEntryId = $active.entryId; repeatedPhysicalDestination = $wasSeen; state = 'in-progress'
            })
            $members = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
            $matched = [pscustomobject]@{ count = 0 }
            $visitor = {
                param($Entry)
                if ($members.ContainsKey($Entry.name)) {
                    throw (New-SwiftUIOverlayProblem 'duplicate-entry' $Entry.path 'Duplicate child name in a shallow enumeration.')
                }
                Write-SwiftUIOverlayRecord $Session 'filesystem-facts' ([ordered]@{
                    kind = 'directory-entry-name'; rootId = $Root.rootId; parentDirectoryId = $directoryId
                    reportedName = $Entry.name; reportedPhysicalPath = $Entry.path; state = 'name-observed-metadata-pending'
                })
                $info = Get-SwiftUIOverlayInfo $Session $Entry.path
                $members.Add($Entry.name, (Get-SwiftUIOverlayFingerprint $info))
                $logical = $active.logicalPath.TrimEnd('/') + '/' + $Entry.name
                $occurrenceId = Get-SwiftUIOverlayId @('entry', $Root.rootId, $logical)
                Write-SwiftUIOverlayRecord $Session 'filesystem-facts' ([ordered]@{
                    kind = 'directory-entry'; recordId = $occurrenceId; rootId = $Root.rootId
                    parentDirectoryId = $directoryId; logicalPath = $logical; physicalPath = $Entry.path
                    entryKind = $info.kind; attributes = $info.attributes; rawLinkTarget = $info.linkTarget
                    beforeMetadata = $info; state = 'observed-entry'
                })
                $resolved = [pscustomobject]@{ physicalPath = $Entry.path; info = $info }
                if ($info.kind -ceq 'symlink') { $resolved = Resolve-SwiftUIOverlaySourcePath $Session $Entry.path $logical }
                $isOverlay = $Entry.name.EndsWith('.swiftoverlay', [StringComparison]::OrdinalIgnoreCase)
                $isMap = $Entry.name.EndsWith('.modulemap', [StringComparison]::OrdinalIgnoreCase) -or $Entry.name.Equals('module.map', [StringComparison]::OrdinalIgnoreCase)
                if ($isOverlay -or $isMap) {
                    $matched.count++
                    $kind = 'module-map'; if ($isOverlay) { $kind = 'overlay' }
                    Copy-SwiftUIOverlayCandidate $Session $Root.rootId $logical $resolved $occurrenceId $kind
                }
                if ($Entry.name.EndsWith('.swiftmodule', [StringComparison]::OrdinalIgnoreCase) -or
                    $Entry.name.EndsWith('.swiftinterface', [StringComparison]::OrdinalIgnoreCase)) {
                    $Session.counts.moduleLocations++; $matched.count++
                    Write-SwiftUIOverlayRecord $Session 'module-context-facts' ([ordered]@{
                        kind = 'swift-module-location'; recordId = Get-SwiftUIOverlayId @('module-location', $occurrenceId)
                        filesystemOccurrenceId = $occurrenceId; logicalPath = $logical; physicalPath = $resolved.physicalPath
                        fileKind = $resolved.info.kind; contentSeal = 'metadata-only; any captured interface anchors are separate receipts'
                        moduleNameClaim = $null; targetClaim = $null; producerHeaderFacts = $null; claimStatus = 'unreviewed'
                    })
                }
                if ($resolved.info.kind -ceq 'directory') {
                    $pending.Push([pscustomobject]@{ logicalPath = $logical; physicalPath = $resolved.physicalPath
                        depth = $active.depth + 1; ancestors = @($active.ancestors) + @($active.physicalPath); entryId = $occurrenceId })
                }
            }.GetNewClosure()
            Invoke-SwiftUIOverlayEnumeration $Session $active.physicalPath $visitor
            $firstCount = $members.Count
            if ($directoryFingerprint -cne (Get-SwiftUIOverlayFingerprint (Get-SwiftUIOverlayInfo $Session $active.physicalPath))) {
                throw (New-SwiftUIOverlayProblem 'changed-directory' $active.logicalPath 'Directory metadata changed during its first enumeration.')
            }
            $secondVisitor = {
                param($Entry)
                if (-not $members.ContainsKey($Entry.name)) {
                    throw (New-SwiftUIOverlayProblem 'changed-membership' $Entry.path 'Second enumeration added or duplicated a child.')
                }
                $snapshot = Get-SwiftUIOverlayFingerprint (Get-SwiftUIOverlayInfo $Session $Entry.path)
                if ($snapshot -cne $members[$Entry.name]) {
                    throw (New-SwiftUIOverlayProblem 'changed-membership' $Entry.path 'Directory child metadata changed between enumeration passes.')
                }
                [void]$members.Remove($Entry.name)
            }.GetNewClosure()
            Invoke-SwiftUIOverlayEnumeration $Session $active.physicalPath $secondVisitor
            if ($members.Count -ne 0 -or $directoryFingerprint -cne
                (Get-SwiftUIOverlayFingerprint (Get-SwiftUIOverlayInfo $Session $active.physicalPath))) {
                throw (New-SwiftUIOverlayProblem 'changed-membership' $active.logicalPath 'Directory membership/metadata changed before its second EOF.')
            }
            $state = 'readable-populated'
            if ($firstCount -eq 0) { $state = 'readable-empty' }
            elseif ($matched.count -eq 0) { $state = 'readable-no-matches' }
            Write-SwiftUIOverlayRecord $Session 'filesystem-facts' ([ordered]@{
                kind = 'directory-complete'; recordId = Get-SwiftUIOverlayId @('directory-complete', $directoryId)
                directoryId = $directoryId; rootId = $Root.rootId; logicalPath = $active.logicalPath
                physicalPath = $active.physicalPath; state = $state; childCount = $firstCount
                matchedDirectChildCount = $matched.count; enumerationPassesCompleted = 2
            })
            if ($active.logicalPath.EndsWith('.swiftcrossimport', [StringComparison]::OrdinalIgnoreCase)) {
                Write-SwiftUIOverlayRecord $Session 'definition-facts' ([ordered]@{
                    kind = 'definition-directory'; recordId = Get-SwiftUIOverlayId @('definition-directory', $directoryId)
                    filesystemOccurrenceId = $directoryId; logicalPath = $active.logicalPath; physicalPath = $active.physicalPath
                    state = $state; childCount = $firstCount; reviewStatus = 'unreviewed'
                })
            }
            $active = $null
        }
    } catch {
        $Session.counts.unvisitedDirectories += $pending.Count
        if ($null -ne $active) {
            try {
                Write-SwiftUIOverlayRecord $Session 'filesystem-facts' ([ordered]@{
                    kind = 'directory-incomplete'; rootId = $Root.rootId; logicalPath = $active.logicalPath
                    physicalPath = $active.physicalPath; state = 'partial-error'; remainingEnumerationTail = 'unobserved'
                })
            } catch { }
        }
        while ($pending.Count -gt 0) {
            $unvisited = $pending.Pop()
            try {
                Write-SwiftUIOverlayRecord $Session 'filesystem-facts' ([ordered]@{
                    kind = 'directory-unvisited'; rootId = $Root.rootId; logicalPath = $unvisited.logicalPath
                    physicalPath = $unvisited.physicalPath; sourceEntryId = $unvisited.entryId; state = 'unvisited'
                })
            } catch { break }
        }
        throw
    }
}

function Resolve-SwiftUIOverlaySelectedRoots {
    param([Parameter(Mandatory)]$Session)
    $resolvedRoots = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($root in $Session.plan.roots) {
        $rootState = @($Session.rootStates | Where-Object { $_.rootId -ceq $root.rootId })[0]
        if ($root.selection -ceq 'not-selected') {
            Write-SwiftUIOverlayRecord $Session 'filesystem-facts' ([ordered]@{
                kind = 'root-state'; rootId = $root.rootId; logicalPath = $root.logicalPath; state = 'not-selected'
            })
            continue
        }
        try {
            $resolved = Resolve-SwiftUIOverlaySourcePath $Session $root.logicalPath ('root:' + $root.rootId)
            if ($resolved.info.kind -cne 'directory' -or $resolved.physicalPath -cne $root.expectedPhysicalPath) {
                throw (New-SwiftUIOverlayProblem 'root-physical-mismatch' $root.logicalPath 'Selected root did not resolve to its exact reviewed physical directory.')
            }
            $resolvedRoots.Add($root.rootId, $resolved); $rootState.state = 'present-unvisited'
            Write-SwiftUIOverlayRecord $Session 'filesystem-facts' ([ordered]@{
                kind = 'root-state'; rootId = $root.rootId; logicalPath = $root.logicalPath
                physicalPath = $resolved.physicalPath; state = 'present-unvisited'
            })
        } catch {
            $rootFailure = $_.Exception; $absent = $false; $absenceLimit = $false
            if (Test-SwiftUIOverlayNotFound $rootFailure) {
                try { $absent = Test-SwiftUIOverlayAbsent $Session $root.logicalPath $root.rootId }
                catch {
                    $absenceProblem = Get-SwiftUIOverlayProblem $_.Exception
                    Write-SwiftUIOverlayIssue $Session $absenceProblem
                    $absenceLimit = $absenceProblem.code -match '(^|-)limit$'
                }
            }
            if ($absent) {
                $rootState.state = 'absent-confirmed'
                if ($root.selection -ceq 'selected-optional') { $rootState.traversalComplete = $true; continue }
            } else { $rootState.state = 'error' }
            $problem = Get-SwiftUIOverlayProblem $rootFailure
            Write-SwiftUIOverlayIssue $Session $problem
            if ($absenceLimit -or $problem.code -match '(^|-)limit$') { $Session.stopRequested = $true; break }
        }
    }
    return ,$resolvedRoots
}

function Write-SwiftUIOverlayNewFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush() } finally { $stream.Dispose() }
}

function Close-SwiftUIOverlayStreams {
    param([Parameter(Mandatory)]$Session, [switch]$IncludeMarker, [AllowNull()][Exception]$PriorFailure)
    $failures = [Collections.Generic.List[Exception]]::new()
    foreach ($entry in $Session.streams.Values) {
        if ($null -ne $entry.writer) {
            $writer = $entry.writer; $entry.writer = $null
            try { $writer.Dispose() } catch { [void]$failures.Add($_.Exception) }
        }
    }
    if ($IncludeMarker -and $null -ne $Session.marker) {
        $marker = $Session.marker; $Session.marker = $null
        try { $marker.Dispose() } catch { [void]$failures.Add($_.Exception) }
    }
    if ($failures.Count -gt 0) {
        if ($null -ne $PriorFailure) { $failures.Insert(0, $PriorFailure) }
        throw [AggregateException]::new('Overlay census cleanup failed after every owned handle received a disposal attempt.', $failures.ToArray())
    }
}

function Complete-SwiftUIOverlayReport {
    param([Parameter(Mandatory)]$Session)
    Close-SwiftUIOverlayStreams $Session
    $records = [Collections.Generic.List[object]]::new()
    foreach ($name in @('filesystem-facts', 'alias-facts', 'definition-facts', 'module-context-facts', 'candidate-pairs', 'issues')) {
        $entry = $Session.streams[$name]
        $sealed = Get-SwiftUIAuditHashedFile $entry.path $entry.relativePath 'census-record-stream'
        if ($sealed.bytes -ne $entry.bytes) { throw 'Census output byte count differs from its writer receipt.' }
        [void]$records.Add([pscustomobject]@{ kind = $name; path = $entry.relativePath; sha256 = $sealed.sha256
            bytes = $sealed.bytes; recordCount = $entry.recordCount })
    }
    foreach ($copy in $Session.copiedFiles) {
        $sealed = Get-SwiftUIAuditHashedFile (Join-Path $Session.output $copy.path) $copy.path 'candidate-copy' $copy.sha256
        if ($sealed.bytes -ne $copy.bytes) { throw 'Candidate copy byte length changed before report sealing.' }
    }
    $sources = [Collections.Generic.List[object]]::new()
    foreach ($name in @('capture-swiftui-overlay-discovery.ps1', 'swiftui-overlay-discovery-common.ps1',
            'swiftui-api-review-common.ps1', 'swiftui-api-audit-common.ps1',
            'swiftui-baseline-common.ps1', 'swiftui-baseline-streaming.ps1')) {
        $sealed = Get-SwiftUIAuditHashedFile (Join-Path $script:SwiftUIOverlayDiscoveryScriptRoot $name) $name 'census-source'
        [void]$sources.Add([pscustomobject]@{ path = 'scripts/' + $name; sha256 = $sealed.sha256; bytes = $sealed.bytes })
    }
    $status = 'failed-incomplete-observation'
    if ($Session.complete) { $status = 'filesystem-recorded-awaiting-probe-review' }
    $source = $Session.source.inputs
    $manifest = [ordered]@{
        schemaVersion = 1; evidenceKind = 'unreviewed-overlay-filesystem-discovery'; status = $status; reviewStatus = 'unreviewed'
        syntheticFixture = $Session.source.syntheticFixture
        sourceArtifacts = [ordered]@{
            captureManifestSha256 = $source.captureContext.captureSha256; captureStatusSha256 = $source.captureContext.statusSha256
            auditManifestSha256 = $source.auditManifestSha256; baselineManifestSha256 = $source.currentExpectedBaselineManifestSha256
            inventorySha256 = $source.captureContext.inventorySha256; graphSetSha256 = $Session.source.graphSetSha256
            verifiedFileSeals = $Session.source.fileSeals
            verification = $Session.source.verification
            originalStreamsModified = $false; sourceSemanticReconciliationRepeated = $false
        }
        rootPlan = [ordered]@{ path = 'root-plan.json'; bytes = $Session.planContext.file.bytes; sha256 = $Session.planContext.file.sha256 }
        roots = $Session.rootStates.ToArray(); identityAnchorChecks = $Session.anchorChecks.ToArray()
        observedExtractorIdentityAsRecorded = $source.captureContext.capture.observedIdentity
        interfaceProducerIdentity = 'preserved by original sealed interface bytes; not inferred from extractor identity; Stage A does not parse interface declarations'
        observationInterval = [ordered]@{
            startedAtUtc = $Session.startedAtUtc; finishedAtUtc = [DateTime]::UtcNow.ToString('o')
            observationAtomic = $false; wholeInstallationByteIdentityEstablished = $false
            nativeCommandsExecuted = $false
            nativeCommandsMeaning = 'no Swift, SDK, compiler probe or external filesystem command launched by this census'
            managedHelperCompilationMayHaveOccurred = $true
            managedHelper = 'existing Initialize-SwiftUIBaselineStreaming strict metadata reader; no new managed source'
        }
        runtime = [ordered]@{
            powerShellVersion = $PSVersionTable.PSVersion.ToString(); clrVersion = [Environment]::Version.ToString()
            operatingSystemAsReportedByRuntime = [Environment]::OSVersion.VersionString; processPointerBytes = [IntPtr]::Size
            filesystemProvider = $Session.provider.name; fakeProvider = $Session.provider.isSynthetic
            actualDarwinAdapterValidationClaimed = $false
        }
        filesystemBoundary = [ordered]@{
            allowIncidentalLinkTargetMetadata = $Session.plan.allowIncidentalLinkTargetMetadata
            incidentalLinkTargetMetadataPossible = $Session.provider.incidentalLinkTargetMetadataPossible
            incidentalQueriesIndividuallyObserved = $false
            outwardContentReadsAuthorized = $false; outwardDirectoryEnumerationAuthorized = $false
            raceProofBoundaryClaimed = $false
            linkDecoderLimitation = 'BCL readlink errors may return null and UTF-8 decoding may replace malformed bytes; ambiguous/replacement text fails incomplete'
            parentTraversalLimitation = 'parent segments after unresolved link-target components are unsupported, never lexically misresolved'
        }
        sourceScripts = $sources.ToArray(); limits = $Session.limits; derivedLimits = $Session.derivedLimits
        counts = [pscustomobject]$Session.counts; targetContexts = $Session.plan.targetContexts
        recordStreams = $records.ToArray(); copiedFiles = $Session.copiedFiles.ToArray()
        coverage = [ordered]@{
            rootTraversal = $(if ($Session.complete) { 'complete-within-recorded-roots' } else { 'incomplete' })
            definitionDecoding = $(if ($Session.counts.unsupportedDefinitions -eq 0 -and $Session.complete) { 'complete-for-declared-profile' } else { 'not-complete' })
            contextAssociation = 'unreviewed'; nativeLoadEvidence = 'not-performed'; overlayCompleteness = 'unverified'
            noDefinitionsObservedInRecordedRoots = $(if ($Session.complete) { $Session.counts.definitions -eq 0 } else { $null })
            candidateProjection = 'every definition occurrence on both pinned targets; seed and reverse hints do not filter records or establish import closure'
            unvisitedFactBoundary = 'entries without completion receipts and any unenumerated tail remain unobserved; counters never assert their absence'
        }
        qualification = [ordered]@{
            reviewedIdentity = $false; declarationCompleteness = $false; overlayCompleteness = $false; behaviorConformance = $false
        }
        terminalIssue = $Session.terminalIssue
    }
    $json = ConvertTo-Json -InputObject $manifest -Depth 40
    $bytes = $Session.encoding.GetBytes($json + [char]10)
    if ($bytes.LongLength -gt $Session.limits.metadataBytes) { throw 'Final census metadata exceeds its budget; output remains unsealed and ineligible.' }
    $manifestPath = Join-Path $Session.output 'discovery.json'
    Write-SwiftUIOverlayNewFile $manifestPath $bytes
    $seal = Get-SwiftUIAuditHashedFile $manifestPath 'discovery.json' 'census-manifest'
    Write-SwiftUIOverlayNewFile (Join-Path $Session.output 'discovery.sha256') ($Session.encoding.GetBytes($seal.sha256 + '  discovery.json' + [char]10))
    $Session.marker.Dispose(); $Session.marker = $null
    [IO.File]::Delete($Session.markerPath)
    $Session.markerRemoved = $true
    return [pscustomobject]@{
        outputRoot = $Session.output; manifestPath = $manifestPath; manifestSha256 = $seal.sha256
        status = $status; complete = $Session.complete; syntheticFixture = $Session.source.syntheticFixture
        reviewStatus = 'unreviewed'; nativeCommandsExecuted = $false
    }
}

function Invoke-SwiftUIOverlayCensus {
    param([Parameter(Mandatory)]$SourceContext, [Parameter(Mandatory)]$RootPlanContext,
        [Parameter(Mandatory)]$Provider, [Parameter(Mandatory)][string]$OutputDirectory)
    $session = New-SwiftUIOverlaySession $SourceContext $RootPlanContext $Provider $OutputDirectory
    $primaryFailure = $null
    try {
        try {
            $resolvedRoots = Resolve-SwiftUIOverlaySelectedRoots $session
            if ($session.counts.issues -eq 0) {
                Test-SwiftUIOverlayIdentityAnchors $session 'before'
                foreach ($root in $session.plan.roots) {
                    if (-not $resolvedRoots.ContainsKey($root.rootId)) { continue }
                    $state = @($session.rootStates | Where-Object { $_.rootId -ceq $root.rootId })[0]
                    try {
                        Invoke-SwiftUIOverlayRootTraversal $session $root $resolvedRoots[$root.rootId]
                        $state.state = 'readable-complete'; $state.traversalComplete = $true
                    } catch {
                        $state.state = 'partial-error'
                        $problem = Get-SwiftUIOverlayProblem $_.Exception
                        Write-SwiftUIOverlayIssue $session $problem
                        if ($problem.code -match '(^|-)limit$') { $session.stopRequested = $true; break }
                    }
                }
                if (-not $session.stopRequested) { Test-SwiftUIOverlayIdentityAnchors $session 'after' }
            }
            Assert-SwiftUIOverlaySourceSeals $SourceContext
            $session.complete = $session.counts.issues -eq 0 -and
                $session.anchorChecks.Count -eq 2 * $session.plan.identityAnchors.Count
        } catch {
            Write-SwiftUIOverlayIssue $session (Get-SwiftUIOverlayProblem $_.Exception)
            $session.complete = $false
        }
        return Complete-SwiftUIOverlayReport $session
    } catch { $primaryFailure = $_.Exception; throw }
    finally { Close-SwiftUIOverlayStreams -Session $session -IncludeMarker -PriorFailure $primaryFailure }
}

function Read-SwiftUIOverlayDiscoveryReport {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$ExpectedManifestSha256,
        [switch]$AllowIncompleteForDiagnostics, [switch]$AllowSyntheticForTests)
    Assert-SwiftUIAuditSha256 $ExpectedManifestSha256 'discovery.expectedSha256'
    if (Test-Path -LiteralPath (Join-Path $Root '.in-progress')) { throw 'Census output is still in progress or was interrupted.' }
    $path = Resolve-SwiftUIAPIReviewArtifactPath $Root 'discovery.json'
    $file = Read-SwiftUIOverlayMetadata $path
    if ($file.sha256 -cne $ExpectedManifestSha256) { throw 'Census manifest does not match the explicitly supplied seal.' }
    $seal = Read-SwiftUIAuditBoundedText (Resolve-SwiftUIAPIReviewArtifactPath $Root 'discovery.sha256') 1024
    if ($seal.text -cne ($file.sha256 + '  discovery.json' + [char]10)) { throw 'Census digest file does not seal its manifest.' }
    $value = $file.value
    Assert-SwiftUIOverlayFields $value @{
        schemaVersion = 'integer'; evidenceKind = 'string'; status = 'string'; reviewStatus = 'string'
        syntheticFixture = 'boolean'; sourceArtifacts = 'object'; rootPlan = 'object'; roots = 'array'
        identityAnchorChecks = 'array'; observationInterval = 'object'; runtime = 'object'; filesystemBoundary = 'object'
        counts = 'object'; recordStreams = 'array'; copiedFiles = 'array'; qualification = 'object'; coverage = 'object'
    } 'discovery'
    if ($value.schemaVersion -ne 1 -or $value.evidenceKind -cne 'unreviewed-overlay-filesystem-discovery' -or
        $value.reviewStatus -cne 'unreviewed' -or
        @('filesystem-recorded-awaiting-probe-review', 'failed-incomplete-observation') -cnotcontains $value.status) {
        throw 'Unsupported census report schema/status or promoted review state.'
    }
    if ($value.syntheticFixture -and -not $AllowSyntheticForTests) { throw 'Synthetic census evidence cannot be consumed as an actual SDK observation.' }
    if ($value.status -cne 'filesystem-recorded-awaiting-probe-review' -and -not $AllowIncompleteForDiagnostics) {
        throw 'Incomplete census is diagnostic evidence only.'
    }
    Assert-SwiftUIOverlayFields $value.qualification @{
        reviewedIdentity = 'boolean'; declarationCompleteness = 'boolean'; overlayCompleteness = 'boolean'; behaviorConformance = 'boolean'
    } 'discovery.qualification'
    Assert-SwiftUIOverlayFields $value.observationInterval @{
        observationAtomic = 'boolean'; wholeInstallationByteIdentityEstablished = 'boolean'; nativeCommandsExecuted = 'boolean'
        startedAtUtc = 'string'; finishedAtUtc = 'string'; managedHelperCompilationMayHaveOccurred = 'boolean'
    } 'discovery.observationInterval'
    Assert-SwiftUIOverlayFields $value.filesystemBoundary @{
        allowIncidentalLinkTargetMetadata = 'boolean'; incidentalLinkTargetMetadataPossible = 'boolean'
        incidentalQueriesIndividuallyObserved = 'boolean'; outwardContentReadsAuthorized = 'boolean'
        outwardDirectoryEnumerationAuthorized = 'boolean'; raceProofBoundaryClaimed = 'boolean'
    } 'discovery.filesystemBoundary'
    Assert-SwiftUIOverlayFields $value.runtime @{
        fakeProvider = 'boolean'; actualDarwinAdapterValidationClaimed = 'boolean'
        filesystemProvider = 'string'; powerShellVersion = 'string'; clrVersion = 'string'
    } 'discovery.runtime'
    Assert-SwiftUIOverlayFields $value.coverage @{
        rootTraversal = 'string'; definitionDecoding = 'string'; contextAssociation = 'string'
        nativeLoadEvidence = 'string'; overlayCompleteness = 'string'
    } 'discovery.coverage'
    Assert-SwiftUIOverlayFields $value.sourceArtifacts @{
        captureManifestSha256 = 'string'; auditManifestSha256 = 'string'; baselineManifestSha256 = 'string'
        originalStreamsModified = 'boolean'; sourceSemanticReconciliationRepeated = 'boolean'
    } 'discovery.sourceArtifacts'
    $countFields = @{}
    foreach ($name in @('filesystemEntries', 'directories', 'enumerationPasses', 'metadataLookups', 'aliasOccurrences',
            'sourceBytesRead', 'copiedCandidateFiles', 'copiedCandidateBytes', 'reportBytes', 'definitions',
            'parsedDefinitions', 'emptyDefinitions', 'unsupportedDefinitions', 'moduleMaps', 'moduleLocations',
            'candidates', 'issues', 'issuesNotWritten', 'unvisitedDirectories')) { $countFields[$name] = 'integer' }
    Assert-SwiftUIOverlayFields $value.counts $countFields 'discovery.counts'
    foreach ($name in $countFields.Keys) {
        if ($value.counts.$name -lt 0) { throw 'Census counters cannot be negative.' }
    }
    foreach ($field in @('reviewedIdentity', 'declarationCompleteness', 'overlayCompleteness', 'behaviorConformance')) {
        if ((Get-SwiftUIAuditProperty $value.qualification $field) -ne $false) { throw 'Census cannot promote an API/behavior/identity qualification.' }
    }
    if ($value.observationInterval.observationAtomic -ne $false -or
        $value.observationInterval.wholeInstallationByteIdentityEstablished -ne $false -or
        $value.observationInterval.nativeCommandsExecuted -ne $false -or
        $value.filesystemBoundary.outwardContentReadsAuthorized -ne $false -or
        $value.filesystemBoundary.outwardDirectoryEnumerationAuthorized -ne $false -or
        $value.filesystemBoundary.allowIncidentalLinkTargetMetadata -ne $true -or
        $value.filesystemBoundary.incidentalQueriesIndividuallyObserved -ne $false -or
        $value.filesystemBoundary.raceProofBoundaryClaimed -ne $false -or
        $value.runtime.fakeProvider -ne $value.syntheticFixture -or
        $value.runtime.actualDarwinAdapterValidationClaimed -ne $false -or
        $value.sourceArtifacts.originalStreamsModified -ne $false -or
        $value.sourceArtifacts.sourceSemanticReconciliationRepeated -ne $false -or
        $value.coverage.contextAssociation -cne 'unreviewed' -or
        $value.coverage.nativeLoadEvidence -cne 'not-performed' -or
        $value.coverage.overlayCompleteness -cne 'unverified') {
        throw 'Census contains an unsupported filesystem or qualification claim.'
    }
    if ($value.status -ceq 'filesystem-recorded-awaiting-probe-review') {
        if ($value.counts.issues -ne 0 -or $value.counts.issuesNotWritten -ne 0 -or
            $value.counts.unsupportedDefinitions -ne 0 -or $value.counts.unvisitedDirectories -ne 0 -or
            $null -ne $value.terminalIssue -or $value.coverage.rootTraversal -cne 'complete-within-recorded-roots' -or
            $value.coverage.definitionDecoding -cne 'complete-for-declared-profile' -or
            $value.coverage.noDefinitionsObservedInRecordedRoots -isnot [bool] -or
            $value.coverage.noDefinitionsObservedInRecordedRoots -ne ($value.counts.definitions -eq 0)) {
            throw 'Successful census status contradicts its failure, coverage or scoped-zero metadata.'
        }
    } elseif ($value.counts.issues -eq 0 -or $null -eq $value.terminalIssue -or
        $value.coverage.rootTraversal -cne 'incomplete' -or
        $value.coverage.definitionDecoding -cne 'not-complete' -or
        $null -ne $value.coverage.noDefinitionsObservedInRecordedRoots) {
        throw 'Incomplete census must retain explicit failure and unknown scoped-zero metadata.'
    }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in @('filesystem-facts', 'alias-facts', 'definition-facts', 'module-context-facts', 'candidate-pairs', 'issues')) { [void]$names.Add($name + '.ndjson') }
    if ($value.recordStreams.Count -ne $names.Count) { throw 'Census must retain exactly six new record streams.' }
    foreach ($entry in $value.recordStreams) {
        Assert-SwiftUIOverlayFields $entry @{ path = 'string'; bytes = 'integer'; sha256 = 'string'; recordCount = 'integer' } 'discovery.recordStreams'
        if ($entry.bytes -lt 0 -or $entry.recordCount -lt 0 -or -not $names.Remove($entry.path)) { throw 'Unknown, duplicated or invalid census stream.' }
        $actual = Get-SwiftUIAuditHashedFile (Resolve-SwiftUIAPIReviewArtifactPath $Root $entry.path) $entry.path 'census-stream' $entry.sha256
        if ($actual.bytes -ne $entry.bytes) { throw 'Census stream byte length differs from its seal.' }
    }
    $copyNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    Assert-SwiftUIOverlayFields $value.rootPlan @{ path = 'string'; bytes = 'integer'; sha256 = 'string' } 'discovery.rootPlan'
    if ($value.rootPlan.path -cne 'root-plan.json') { throw 'Root authorization must seal exactly root-plan.json.' }
    foreach ($copy in $value.copiedFiles) {
        if ($copy.path -cnotmatch '\Araw/[0-9a-f]{64}\.bin\z') { throw 'Candidate copies must remain exclusively in the raw content directory.' }
    }
    foreach ($entry in @($value.copiedFiles) + @($value.rootPlan)) {
        Assert-SwiftUIOverlayFields $entry @{ path = 'string'; bytes = 'integer'; sha256 = 'string' } 'discovery.copiedFile'
        if (-not $copyNames.Add($entry.path) -or
            ($entry.path -cne 'root-plan.json' -and $entry.path -cnotmatch '\Araw/[0-9a-f]{64}\.bin\z')) {
            throw 'Unexpected or duplicated census copy path.'
        }
        $actual = Get-SwiftUIAuditHashedFile (Resolve-SwiftUIAPIReviewArtifactPath $Root $entry.path) $entry.path 'census-copy' $entry.sha256
        if ($actual.bytes -ne $entry.bytes) { throw 'Census copy byte length differs from its seal.' }
    }
    # Cross-check only bounded existing metadata here. This reader does not
    # replay the record streams, resolve modules or repeat compiler evidence.
    $savedPlan = (Read-SwiftUIOverlayMetadata (Join-Path $Root 'root-plan.json')).value
    Assert-SwiftUIOverlayFields $savedPlan @{
        schemaVersion = 'integer'; evidenceKind = 'string'; sourceCaptureSha256 = 'string'
        sourceAuditSha256 = 'string'; baselineManifestSha256 = 'string'; allowIncidentalLinkTargetMetadata = 'boolean'
        roots = 'array'; identityAnchors = 'array'; targetContexts = 'array'
    } 'discovery.savedRootPlan'
    if ($savedPlan.schemaVersion -ne 1 -or $savedPlan.evidenceKind -cne 'overlay-discovery-root-authorization' -or
        -not $savedPlan.allowIncidentalLinkTargetMetadata -or
        $savedPlan.sourceCaptureSha256 -cne $value.sourceArtifacts.captureManifestSha256 -or
        $savedPlan.sourceAuditSha256 -cne $value.sourceArtifacts.auditManifestSha256 -or
        $savedPlan.baselineManifestSha256 -cne $value.sourceArtifacts.baselineManifestSha256) {
        throw 'Census root authorization contradicts its source or filesystem-boundary metadata.'
    }
    if ($savedPlan.roots.Count -ne 3 -or $value.roots.Count -ne 3) { throw 'Census must preserve all three root selections.' }
    $rootIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($rootFact in $value.roots) {
        Assert-SwiftUIOverlayFields $rootFact @{
            rootId = 'string'; state = 'string'; logicalPath = 'string'
            expectedPhysicalPath = 'nullable-string'; traversalComplete = 'boolean'
        } 'discovery.roots'
        $plannedRoot = @($savedPlan.roots | Where-Object { $_.rootId -ceq $rootFact.rootId })
        if (-not $rootIds.Add($rootFact.rootId) -or $plannedRoot.Count -ne 1 -or
            $rootFact.logicalPath -cne $plannedRoot[0].logicalPath -or
            $rootFact.expectedPhysicalPath -cne $plannedRoot[0].expectedPhysicalPath) {
            throw 'Census root observations do not bind unique authorized root occurrences.'
        }
        if ($plannedRoot[0].selection -ceq 'not-selected') {
            if ($rootFact.state -cne 'not-selected' -or $rootFact.traversalComplete) { throw 'Unselected root cannot claim traversal or absence.' }
        } elseif ($value.status -ceq 'filesystem-recorded-awaiting-probe-review') {
            $validState = $rootFact.state -ceq 'readable-complete' -or
                ($plannedRoot[0].selection -ceq 'selected-optional' -and $rootFact.state -ceq 'absent-confirmed')
            if (-not $rootFact.traversalComplete -or -not $validState) { throw 'Successful census contains an incomplete selected root.' }
        }
    }
    if ($value.status -ceq 'filesystem-recorded-awaiting-probe-review') {
        if ($value.identityAnchorChecks.Count -ne 2 * $savedPlan.identityAnchors.Count -or
            $value.counts.copiedCandidateFiles -ne $value.copiedFiles.Count -or
            $value.counts.parsedDefinitions -ne $value.counts.definitions -or
            $value.counts.definitions + $value.counts.moduleMaps -ne $value.copiedFiles.Count -or
            $value.counts.candidates -ne $value.counts.definitions * $savedPlan.targetContexts.Count) {
            throw 'Successful census contradicts its complete anchor/copy/definition counts.'
        }
        $anchorOccurrences = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($check in $value.identityAnchorChecks) {
            Assert-SwiftUIOverlayFields $check @{
                anchorId = 'string'; phase = 'string'; logicalPath = 'string'; expectedSha256 = 'string'
                observedSha256 = 'string'; result = 'string'; bytes = 'integer'
            } 'discovery.identityAnchorChecks'
            $plannedAnchor = @($savedPlan.identityAnchors | Where-Object { $_.anchorId -ceq $check.anchorId })
            if (@('before', 'after') -cnotcontains $check.phase -or
                -not $anchorOccurrences.Add($check.anchorId + [char]0 + $check.phase) -or $plannedAnchor.Count -ne 1 -or
                $check.logicalPath -cne $plannedAnchor[0].logicalPath -or $check.expectedSha256 -cne $plannedAnchor[0].expectedSha256 -or
                $check.observedSha256 -cne $check.expectedSha256 -or $check.result -cne 'matches-recorded-anchor' -or $check.bytes -lt 0) {
                throw 'Successful census is missing unique before/after matching identity anchors.'
            }
        }
        foreach ($copy in $value.copiedFiles) {
            Assert-SwiftUIOverlayFields $copy @{ captureComplete = 'boolean' } 'discovery.copiedFiles'
            if (-not $copy.captureComplete) { throw 'Successful census cannot contain a partial content copy.' }
        }
    }
    $topNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in @('discovery.json', 'discovery.sha256', 'root-plan.json') + @($value.recordStreams.path)) { [void]$topNames.Add($name) }
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force -ErrorAction Stop) {
        if ($item.Name -ceq 'raw' -and $item.PSIsContainer) {
            $rawRoot = Resolve-SwiftUIAPIReviewArtifactPath $Root 'raw' -Kind Directory
            foreach ($rawItem in Get-ChildItem -LiteralPath $rawRoot -Force -ErrorAction Stop) {
                if ($rawItem.PSIsContainer -or -not $copyNames.Remove('raw/' + $rawItem.Name)) {
                    throw 'Undeclared or ambiguous raw census copy.'
                }
                [void](Resolve-SwiftUIAPIReviewArtifactPath $Root ('raw/' + $rawItem.Name))
            }
        } elseif ($item.PSIsContainer -or -not $topNames.Remove($item.Name)) { throw 'Undeclared census output entry.' }
    }
    [void]$copyNames.Remove('root-plan.json')
    if ($copyNames.Count -ne 0 -or $topNames.Count -ne 0) { throw 'Census output is missing a declared file.' }
    return [pscustomobject]@{ path = $path; sha256 = $file.sha256; report = $value
        eligibleForFurtherReview = $value.status -ceq 'filesystem-recorded-awaiting-probe-review'
        qualification = 'unreviewed; no declaration or behavior conformance claim' }
}
