# Candidate capture intake only. Large inventories and symbol graphs are left to
# the streaming audit writer; a successful intake is not API or behavior review.
. (Join-Path $PSScriptRoot 'swiftui-baseline-common.ps1')

function Get-SwiftUIAuditProperty {
    param($Value, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $Value) { throw "Missing audit metadata property '$Name'." }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property -or $property.Name -cne $Name) {
        throw "Missing audit metadata property '$Name' (property names are case sensitive)."
    }
    return ,$property.Value
}

function Assert-SwiftUIAuditFields {
    param($Value, [Parameter(Mandatory)][System.Collections.IDictionary]$Fields,
        [Parameter(Mandatory)][string]$Context)

    if ($Value -isnot [System.Management.Automation.PSCustomObject]) {
        throw "$Context must be a JSON object."
    }
    foreach ($name in $Fields.Keys) {
        $fieldValue = Get-SwiftUIAuditProperty -Value $Value -Name $name
        $valid = switch ($Fields[$name]) {
            'string' { $fieldValue -is [string] -and -not [string]::IsNullOrWhiteSpace($fieldValue) }
            'nullable-string' { $null -eq $fieldValue -or $fieldValue -is [string] }
            'boolean' { $fieldValue -is [bool] }
            'object' { $fieldValue -is [System.Management.Automation.PSCustomObject] }
            'array' { $fieldValue -is [System.Array] }
            'integer' { ($fieldValue -is [int] -or $fieldValue -is [long]) -and $fieldValue -ge 0 }
            default { throw "Unknown audit metadata field type '$($Fields[$name])'." }
        }
        if (-not $valid) { throw "$Context.$name must be $($Fields[$name])." }
    }
}

function Assert-SwiftUIAuditSha256 {
    param($Value, [Parameter(Mandatory)][string]$Context)

    if ($Value -isnot [string] -or $Value -cnotmatch '\A[0-9a-f]{64}\z') {
        throw "$Context must be a lowercase SHA-256 digest."
    }
}

function Read-SwiftUIAuditBoundedText {
    param([Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$MaximumBytes)

    if ($MaximumBytes -le 0 -or $MaximumBytes -gt [int]::MaxValue) {
        throw 'The metadata byte budget must be positive and fit a bounded byte array.'
    }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $memory = [System.IO.MemoryStream]::new()
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        if ($stream.Length -gt $MaximumBytes) {
            throw "Metadata '$Path' exceeds MaximumMetadataBytes=$MaximumBytes; inventories and graphs must use the streaming reader."
        }
        $buffer = [byte[]]::new(8192)
        while (($count = $stream.Read($buffer, 0, $buffer.Length)) -ne 0) {
            if ($memory.Length + $count -gt $MaximumBytes) {
                throw "Metadata '$Path' exceeds MaximumMetadataBytes=$MaximumBytes."
            }
            $memory.Write($buffer, 0, $count)
        }
        $bytes = $memory.ToArray()
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        $hash = [System.BitConverter]::ToString($algorithm.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
        return [pscustomobject]@{ path = $Path; text = $text; bytes = [long]$bytes.Length; sha256 = $hash }
    } finally {
        $algorithm.Dispose()
        $memory.Dispose()
        $stream.Dispose()
    }
}

function Read-SwiftUIAuditMetadata {
    param([Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$MaximumBytes)

    $inputFile = Read-SwiftUIAuditBoundedText -Path $Path -MaximumBytes $MaximumBytes
    $json = $inputFile.text
    if ($json.Length -gt 0 -and $json[0] -eq [char]0xfeff) { $json = $json.Substring(1) }
    # Both runtimes can unwrap a singleton root array. Reject it before parsing.
    if ($json -cnotmatch '\A[ \t\r\n]*\{') { throw "Metadata '$Path' must have a JSON object root." }
    $arguments = @{ InputObject = $json; ErrorAction = 'Stop' }
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $arguments.DateKind = 'String' }
    $value = ConvertFrom-Json @arguments
    if ($value -isnot [System.Management.Automation.PSCustomObject]) {
        throw "Metadata '$Path' must have a JSON object root."
    }
    # Keep the original byte digest authoritative. This small metadata object is
    # for validation; it is not a lossless replacement for the captured JSON.
    return [pscustomobject]@{ path = $Path; value = $value; bytes = $inputFile.bytes; sha256 = $inputFile.sha256 }
}

function Assert-SwiftUIAuditManifest {
    param([Parameter(Mandatory)]$Manifest, [Parameter(Mandatory)][string]$Context)

    # Validate the already bounded object instead of reopening it through the
    # general baseline reader's whole-file read. Keep these pin rules aligned.
    Assert-SwiftUIAuditFields $Manifest @{
        schemaVersion = 'integer'; baselineId = 'string'; scope = 'object'; toolchain = 'object'
        reviewedIdentity = 'object'; evidence = 'object'
    } $Context
    if ($Manifest.schemaVersion -ne 1) { throw "$Context has an unsupported baseline schema version." }
    Assert-SwiftUIAuditFields $Manifest.toolchain @{
        xcodeVersion = 'string'; sdkVersion = 'string'; swiftCompilerMajorMinor = 'string'
        sdkName = 'string'; toolchainName = 'string'; swiftLanguageMode = 'string'
    } "$Context.toolchain"
    foreach ($field in @('xcodeVersion', 'sdkVersion', 'swiftCompilerMajorMinor')) {
        if ($Manifest.toolchain.$field -cnotmatch '\A\d+\.\d+(?:\.\d+)?\z') {
            throw "$Context.toolchain.$field must be an explicit numeric release version."
        }
    }
    if ($Manifest.toolchain.sdkName -cne 'macosx' -or
        $Manifest.toolchain.toolchainName -cne 'XcodeDefault' -or
        $Manifest.toolchain.swiftLanguageMode -cne '6') {
        throw "$Context requires the macOS SDK, XcodeDefault toolchain, and Swift 6 language mode."
    }
    Assert-SwiftUIAuditFields $Manifest.scope @{
        modules = 'array'; targets = 'array'; allowedReexportedModules = 'array'; exceptions = 'array'
        minimumAccessLevel = 'string'; includeSPISymbols = 'boolean'; preserveAvailabilityMetadata = 'boolean'
        preserveExtensionGraphs = 'boolean'; preserveSynthesizedMembers = 'boolean'; preservePublicInterfacesAndImports = 'boolean'
    } "$Context.scope"
    foreach ($field in @('modules', 'allowedReexportedModules')) {
        $names = $Manifest.scope.$field
        if ($names.Count -ne 2 -or $names -cnotcontains 'SwiftUI' -or $names -cnotcontains 'SwiftUICore') {
            throw "$Context.scope.$field must retain both SwiftUI and SwiftUICore."
        }
    }
    $expectedTargets = @("arm64-apple-macosx$($Manifest.toolchain.sdkVersion)",
        "x86_64-apple-macosx$($Manifest.toolchain.sdkVersion)")
    if ($Manifest.scope.targets.Count -ne 2) { throw "$Context requires both desktop architecture targets." }
    foreach ($target in $expectedTargets) {
        if ($Manifest.scope.targets -cnotcontains $target) { throw "$Context is missing complete-SDK target '$target'." }
    }
    if ($Manifest.scope.minimumAccessLevel -cne 'public' -or $Manifest.scope.includeSPISymbols) {
        throw "$Context must request public API without SPI."
    }
    foreach ($field in @('preserveAvailabilityMetadata', 'preserveExtensionGraphs',
            'preserveSynthesizedMembers', 'preservePublicInterfacesAndImports')) {
        if (-not $Manifest.scope.$field) { throw "$Context.scope.$field must remain enabled." }
    }
    Assert-SwiftUIAuditFields $Manifest.reviewedIdentity @{
        status = 'string'; xcodeBuildVersion = 'nullable-string'; sdkBuildVersion = 'nullable-string'
        swiftCompilerVersionLine = 'nullable-string'
    } "$Context.reviewedIdentity"
}

function Assert-SwiftUIAuditJsonEqual {
    param($Expected, $Actual, [Parameter(Mandatory)][string]$Context, [int]$Depth = 0)

    if ($Depth -gt 100) { throw "$Context exceeds the metadata comparison depth limit." }
    if ($null -eq $Expected -or $null -eq $Actual) {
        if ($null -ne $Expected -or $null -ne $Actual) { throw "$Context differs from the pinned baseline." }
        return
    }
    if ($Expected -is [System.Management.Automation.PSCustomObject]) {
        if ($Actual -isnot [System.Management.Automation.PSCustomObject]) { throw "$Context must remain an object." }
        $expectedProperties = @($Expected.PSObject.Properties)
        if ($expectedProperties.Count -ne @($Actual.PSObject.Properties).Count) { throw "$Context has different baseline fields." }
        foreach ($property in $expectedProperties) {
            $actualValue = Get-SwiftUIAuditProperty $Actual $property.Name
            Assert-SwiftUIAuditJsonEqual -Expected $property.Value -Actual $actualValue -Context "$Context.$($property.Name)" -Depth ($Depth + 1)
        }
        return
    }
    if ($Expected -is [System.Array]) {
        if ($Actual -isnot [System.Array] -or $Expected.Count -ne $Actual.Count) { throw "$Context has a different baseline array." }
        for ($index = 0; $index -lt $Expected.Count; $index++) {
            Assert-SwiftUIAuditJsonEqual -Expected $Expected[$index] -Actual $Actual[$index] -Context "$Context[$index]" -Depth ($Depth + 1)
        }
        return
    }
    if ($Actual.GetType() -ne $Expected.GetType() -or $Actual -cne $Expected) {
        throw "$Context differs from the pinned baseline."
    }
}

function Resolve-SwiftUIAuditArtifactPath {
    param([Parameter(Mandatory)][string]$CaptureRoot, [Parameter(Mandatory)][string]$RelativePath,
        [ValidateSet('File', 'Directory', 'Any')][string]$Kind = 'File')

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        $RelativePath -match '[\\:\x00-\x1f\x7f]' -or [System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Artifact path '$RelativePath' must be a portable relative path."
    }
    foreach ($part in $RelativePath.Split('/')) {
        if ($part.Length -eq 0 -or $part -eq '.' -or $part -eq '..' -or $part -match '[. ]$') {
            throw "Artifact path '$RelativePath' contains an ambiguous or traversing component."
        }
    }
    $path = Resolve-SwiftUIBaselineFileSystemPath -Path (Join-Path $CaptureRoot $RelativePath)
    [void](Get-SwiftUIBaselineRelativePath -Root $CaptureRoot -Path $path)
    if ($Kind -eq 'File' -and -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing capture artifact '$RelativePath'."
    }
    if ($Kind -eq 'Directory' -and -not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "Missing capture directory '$RelativePath'."
    }
    return $path
}

function Get-SwiftUIAuditArtifactFiles {
    param([Parameter(Mandatory)][string]$CaptureRoot, [Parameter(Mandatory)][string]$RelativeDirectory,
        [Parameter(Mandatory)][string]$Suffix, [switch]$AllowMissing)

    $directory = Resolve-SwiftUIAuditArtifactPath $CaptureRoot $RelativeDirectory -Kind Any
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        if ($AllowMissing -and -not (Test-Path -LiteralPath $directory)) { return }
        throw "Missing capture directory '$RelativeDirectory'."
    }
    $comparer = [System.StringComparer]::Ordinal
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $comparer = [System.StringComparer]::OrdinalIgnoreCase }
    $visited = [System.Collections.Generic.HashSet[string]]::new($comparer)
    $pending = [System.Collections.Generic.Stack[object]]::new()
    $pending.Push([pscustomobject]@{ path = $directory; relativePath = $RelativeDirectory })
    while ($pending.Count -gt 0) {
        $entry = $pending.Pop()
        if (-not $visited.Add($entry.path)) { throw "Capture directory alias or cycle at '$($entry.relativePath)'." }
        foreach ($item in Get-ChildItem -LiteralPath $entry.path -Force -ErrorAction Stop) {
            $relativePath = $entry.relativePath + '/' + $item.Name
            $path = Resolve-SwiftUIAuditArtifactPath $CaptureRoot $relativePath -Kind Any
            if ($item.PSIsContainer) {
                $pending.Push([pscustomobject]@{ path = $path; relativePath = $relativePath })
            } elseif ($item.Name.EndsWith($Suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Unreadable capture artifact '$relativePath'." }
                [pscustomobject]@{ path = $path; relativePath = $relativePath }
            }
        }
    }
}

function Get-SwiftUIAuditHashedFile {
    param([Parameter(Mandatory)][string]$Path, [AllowNull()][string]$RelativePath,
        [Parameter(Mandatory)][string]$Kind, [AllowNull()][string]$ExpectedSha256)

    if ($ExpectedSha256) { Assert-SwiftUIAuditSha256 $ExpectedSha256 "$Kind.sha256" }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $stream.Length
        $hash = [System.BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
        if ($stream.Length -ne $bytes) { throw "Capture artifact '$RelativePath' changed while hashing." }
    } finally { $algorithm.Dispose(); $stream.Dispose() }
    if ($ExpectedSha256 -and $hash -cne $ExpectedSha256) { throw "SHA-256 mismatch for capture artifact '$RelativePath'." }
    return [pscustomobject]@{ path = $Path; relativePath = $RelativePath; sha256 = $hash; bytes = $bytes; kind = $Kind }
}

function Read-SwiftUIAuditCapture {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CaptureRoot,
        [string]$ManifestPath = (Join-Path $PSScriptRoot '../docs/swiftui-baseline.json'),
        [long]$MaximumMetadataBytes = 16MB)

    $ErrorActionPreference = 'Stop'
    $captureRootPath = Resolve-SwiftUIBaselineFileSystemPath -Path $CaptureRoot
    if (-not (Test-Path -LiteralPath $captureRootPath -PathType Container)) { throw "Capture root '$CaptureRoot' must exist." }
    $expectedPath = Resolve-SwiftUIBaselineFileSystemPath -Path $ManifestPath
    $expectedFile = Read-SwiftUIAuditMetadata $expectedPath $MaximumMetadataBytes
    $expected = $expectedFile.value
    Assert-SwiftUIAuditManifest $expected 'Expected baseline'
    $statusPath = Resolve-SwiftUIAuditArtifactPath $captureRootPath 'capture-status.json'
    $statusFile = Read-SwiftUIAuditMetadata $statusPath $MaximumMetadataBytes
    $status = $statusFile.value
    Assert-SwiftUIAuditFields $status @{ baselineId = 'string'; status = 'string' } 'capture-status'
    if ($status.status -cne 'exported-awaiting-review') {
        throw 'Only a successful matching candidate capture can enter the API audit; failed captures remain ineligible after local reindexing.'
    }
    Assert-SwiftUIAuditFields $status @{
        baselineId = 'string'; status = 'string'; captureManifest = 'string'
        captureManifestSha256 = 'string'; behaviorConformance = 'string'
    } 'capture-status'
    if ($status.status -cne 'exported-awaiting-review' -or $status.baselineId -cne $expected.baselineId -or
        $status.captureManifest -cne 'capture.json' -or $status.behaviorConformance -cne 'not-verified') {
        throw 'Only a successful matching candidate capture with unverified behavior can enter the API audit.'
    }
    Assert-SwiftUIAuditSha256 $status.captureManifestSha256 'capture-status.captureManifestSha256'
    $capturePath = Resolve-SwiftUIAuditArtifactPath $captureRootPath 'capture.json'
    $captureFile = Read-SwiftUIAuditMetadata $capturePath $MaximumMetadataBytes
    if ($captureFile.sha256 -cne $status.captureManifestSha256) { throw 'capture-status capture manifest SHA-256 mismatch.' }
    $sealPath = Resolve-SwiftUIAuditArtifactPath $captureRootPath 'capture.sha256'
    $sealFile = Read-SwiftUIAuditBoundedText $sealPath ([Math]::Min($MaximumMetadataBytes, 1024))
    if ($sealFile.text -cnotmatch '\A([0-9a-f]{64})  capture\.json(?:\r?\n)?\z' -or
        $Matches[1] -cne $captureFile.sha256) { throw 'capture.sha256 does not seal the actual capture.json bytes.' }
    $capture = $captureFile.value
    Assert-SwiftUIAuditFields $capture @{
        schemaVersion = 'integer'; baselineId = 'string'; status = 'string'; exactIdentityPreviouslyReviewed = 'boolean'
        observedIdentity = 'object'; baselineManifest = 'object'; requestedScope = 'object'; qualification = 'object'
        sdk = 'object'; inventory = 'object'; publicInterfaces = 'array'; crossImportDefinitions = 'array'
        tools = 'array'; exporterSources = 'array'; host = 'object'; commands = 'array'; crossImportOverlayCompleteness = 'string'
    } 'capture'
    if ($capture.schemaVersion -ne 1 -or $capture.baselineId -cne $expected.baselineId -or
        $capture.status -cne 'exported-awaiting-inventory-and-behavior-review') {
        throw 'Capture schema, baseline ID, or successful candidate status is invalid.'
    }
    Assert-SwiftUIAuditFields $capture.qualification @{
        publicAPIAuditComplete = 'boolean'; behaviorConformanceVerified = 'boolean'; releaseQualified = 'boolean'
    } 'capture.qualification'
    foreach ($field in @('publicAPIAuditComplete', 'behaviorConformanceVerified', 'releaseQualified')) {
        if ($capture.qualification.$field) { throw "Candidate capture cannot claim qualification.$field." }
    }
    if ($capture.crossImportOverlayCompleteness -cne 'not-verified; compiler may silently skip an overlay that fails to load') {
        throw 'Candidate capture must preserve the unverified cross-import overlay boundary.'
    }
    Assert-SwiftUIAuditFields $capture.baselineManifest @{ path = 'string'; sha256 = 'string' } 'capture.baselineManifest'
    Assert-SwiftUIAuditSha256 $capture.baselineManifest.sha256 'capture.baselineManifest.sha256'
    if ($capture.baselineManifest.path -cne 'baseline-manifest.json') { throw 'Capture must identify baseline-manifest.json.' }
    $baselinePath = Resolve-SwiftUIAuditArtifactPath $captureRootPath $capture.baselineManifest.path
    $baselineFile = Read-SwiftUIAuditMetadata $baselinePath $MaximumMetadataBytes
    if ($baselineFile.sha256 -cne $capture.baselineManifest.sha256) { throw 'Captured baseline manifest SHA-256 mismatch.' }
    $baseline = $baselineFile.value
    Assert-SwiftUIAuditManifest $baseline 'Captured baseline'
    if ($baseline.baselineId -cne $expected.baselineId) { throw 'Captured baseline ID differs from the expected baseline.' }
    Assert-SwiftUIAuditJsonEqual $expected.scope $baseline.scope 'Captured baseline.scope'
    Assert-SwiftUIAuditJsonEqual $expected.toolchain $baseline.toolchain 'Captured baseline.toolchain'
    Assert-SwiftUIAuditJsonEqual $baseline.scope $capture.requestedScope 'capture.requestedScope'
    Assert-SwiftUIAuditFields $capture.observedIdentity @{
        xcodeVersion = 'string'; xcodeBuildVersion = 'string'; sdkVersion = 'string'; sdkBuildVersion = 'string'
        swiftCompilerVersion = 'string'; swiftCompilerVersionLine = 'string'
    } 'capture.observedIdentity'
    $identity = $capture.observedIdentity
    $parsedIdentity = ConvertTo-SwiftUIBaselineIdentity -XcodeOutput "Xcode $($identity.xcodeVersion)`nBuild version $($identity.xcodeBuildVersion)" `
        -SDKVersion $identity.sdkVersion -SDKBuildVersion $identity.sdkBuildVersion -SwiftOutput $identity.swiftCompilerVersionLine
    foreach ($field in @('xcodeVersion', 'xcodeBuildVersion', 'sdkVersion', 'sdkBuildVersion', 'swiftCompilerVersion', 'swiftCompilerVersionLine')) {
        if ($identity.$field -cne $parsedIdentity.$field) { throw "Inconsistent observed identity field '$field'." }
    }
    $capturedIdentityReviewed = Assert-SwiftUIBaselineIdentity -Manifest $baseline -Identity $identity
    [void](Assert-SwiftUIBaselineIdentity -Manifest $expected -Identity $identity)
    if ($capture.exactIdentityPreviouslyReviewed -ne $capturedIdentityReviewed) {
        throw 'capture.exactIdentityPreviouslyReviewed contradicts the captured baseline; later review does not rewrite capture history.'
    }
    foreach ($field in @('tools', 'exporterSources')) {
        if ($capture.$field.Count -eq 0) { throw "capture.$field must retain reported producer provenance." }
        foreach ($record in $capture.$field) {
            Assert-SwiftUIAuditFields $record @{ path = 'string'; sha256 = 'string' } "capture.$field"
            Assert-SwiftUIAuditSha256 $record.sha256 "capture.$field.sha256"
        }
    }
    # Producer executable and source paths are reported provenance, not local
    # capture artifacts. Never probe a Mac tool path from this audit host.
    Assert-SwiftUIAuditFields $capture.sdk @{
        path = 'string'; version = 'string'; buildVersion = 'string'; settingsPath = 'string'; settingsSha256 = 'string'
    } 'capture.sdk'
    if ($capture.sdk.version -cne $identity.sdkVersion -or $capture.sdk.buildVersion -cne $identity.sdkBuildVersion) {
        throw 'Captured SDK metadata contradicts the observed SDK identity.'
    }
    if (@('SDKSettings.json', 'SDKSettings.plist') -cnotcontains $capture.sdk.settingsPath) { throw 'Unsupported captured SDK settings artifact path.' }
    Assert-SwiftUIAuditSha256 $capture.sdk.settingsSha256 'capture.sdk.settingsSha256'
    Assert-SwiftUIAuditFields $capture.inventory @{
        path = 'string'; sha256 = 'string'; graphSetSha256 = 'string'; counts = 'object'; indexing = 'object'
    } 'capture.inventory'
    Assert-SwiftUIAuditSha256 $capture.inventory.sha256 'capture.inventory.sha256'
    Assert-SwiftUIAuditSha256 $capture.inventory.graphSetSha256 'capture.inventory.graphSetSha256'
    Assert-SwiftUIAuditFields $capture.inventory.counts @{
        graphs = 'integer'; preciseSymbols = 'integer'; declarationOccurrences = 'integer'; relationshipOccurrences = 'integer'
    } 'capture.inventory.counts'
    if ($capture.inventory.path -cne 'inventory.json') { throw 'Capture must identify inventory.json.' }
    $inventoryPath = Resolve-SwiftUIAuditArtifactPath $captureRootPath $capture.inventory.path
    $inputFiles = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @(
        @{ file = $expectedFile; relativePath = $null; kind = 'expected-baseline-manifest' },
        @{ file = $statusFile; relativePath = 'capture-status.json'; kind = 'capture-status' },
        @{ file = $captureFile; relativePath = 'capture.json'; kind = 'capture-manifest' },
        @{ file = $sealFile; relativePath = 'capture.sha256'; kind = 'capture-seal' },
        @{ file = $baselineFile; relativePath = 'baseline-manifest.json'; kind = 'captured-baseline-manifest' }
    )) {
        $inputFiles.Add([pscustomobject]@{ path = $entry.file.path; relativePath = $entry.relativePath
            sha256 = $entry.file.sha256; bytes = $entry.file.bytes; kind = $entry.kind })
    }
    $settingsPath = Resolve-SwiftUIAuditArtifactPath $captureRootPath $capture.sdk.settingsPath
    $inputFiles.Add((Get-SwiftUIAuditHashedFile -Path $settingsPath -RelativePath $capture.sdk.settingsPath `
        -Kind 'sdk-settings' -ExpectedSha256 $capture.sdk.settingsSha256))
    $pathComparer = [System.StringComparer]::Ordinal
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $pathComparer = [System.StringComparer]::OrdinalIgnoreCase }
    $physicalPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
    $interfaceFiles = [System.Collections.Generic.List[object]]::new()
    $overlayFiles = [System.Collections.Generic.List[object]]::new()
    foreach ($kind in @('publicInterfaces', 'crossImportDefinitions')) {
        $isInterface = $kind -ceq 'publicInterfaces'
        $directory = if ($isInterface) { 'interfaces' } else { 'cross-imports' }
        $suffix = if ($isInterface) { '.swiftinterface' } else { '.swiftoverlay' }
        $declared = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        $moduleCounts = @{ SwiftUI = 0; SwiftUICore = 0 }
        foreach ($record in $capture.$kind) {
            Assert-SwiftUIAuditFields $record @{ module = 'string'; path = 'string'; sdkRelativeSource = 'string'; sha256 = 'string' } "capture.$kind"
            if ($baseline.scope.modules -cnotcontains $record.module) { throw "Unknown module in capture.$kind." }
            if (-not $record.path.StartsWith("$directory/$($record.module)/", [System.StringComparison]::Ordinal) -or
                -not $record.path.EndsWith($suffix, [System.StringComparison]::Ordinal) -or
                ($isInterface -and $record.path -match '\.(private|package)\.swiftinterface$')) {
                throw "Invalid $kind artifact path '$($record.path)'."
            }
            if ($isInterface) { Assert-SwiftUIAuditFields $record @{ imports = 'array' } "capture.$kind" }
            Assert-SwiftUIAuditSha256 $record.sha256 "capture.$kind.sha256"
            $path = Resolve-SwiftUIAuditArtifactPath $captureRootPath $record.path
            if ($declared.ContainsKey($record.path) -or -not $physicalPaths.Add($path)) { throw "Duplicate or aliased $kind artifact '$($record.path)'." }
            $resolvedRecord = [pscustomobject]@{ path = $path; relativePath = $record.path; record = $record }
            $declared.Add($record.path, $resolvedRecord)
            $moduleCounts[$record.module]++
            $inputFiles.Add((Get-SwiftUIAuditHashedFile -Path $path -RelativePath $record.path -Kind $kind -ExpectedSha256 $record.sha256))
            if ($isInterface) { $interfaceFiles.Add($resolvedRecord) } else { $overlayFiles.Add($resolvedRecord) }
        }
        if ($isInterface) {
            foreach ($module in $baseline.scope.modules) {
                if ($moduleCounts[$module] -eq 0) { throw "No public interfaces were captured for '$module'." }
            }
        }
        foreach ($actual in Get-SwiftUIAuditArtifactFiles -CaptureRoot $captureRootPath -RelativeDirectory $directory -Suffix $suffix -AllowMissing:(-not $isInterface)) {
            if (-not $declared.ContainsKey($actual.relativePath)) { throw "Undeclared $kind artifact '$($actual.relativePath)'." }
            if (-not $pathComparer.Equals($declared[$actual.relativePath].path, $actual.path)) { throw "Artifact path changed during discovery: '$($actual.relativePath)'." }
            [void]$declared.Remove($actual.relativePath)
        }
        if ($declared.Count -ne 0) { throw "Declared $kind artifacts were absent from actual discovery." }
    }
    $exports = @(
        foreach ($target in $baseline.scope.targets) {
            foreach ($module in $baseline.scope.modules) {
                $directory = Resolve-SwiftUIAuditArtifactPath $captureRootPath "graphs/$target/$module" -Kind Directory
                [pscustomobject]@{ module = $module; target = $target; directory = $directory }
            }
        }
    )
    # Check nested directory links before the baseline discoverer's recursive
    # enumeration, and include hidden files in the independent set comparison.
    $graphPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($actual in Get-SwiftUIAuditArtifactFiles -CaptureRoot $captureRootPath -RelativeDirectory 'graphs' -Suffix '.symbols.json') {
        [void]$graphPaths.Add($actual.relativePath)
        if ($graphPaths.Count -gt $capture.inventory.counts.graphs) {
            throw 'Actual raw symbol graph count exceeds the candidate capture.'
        }
    }
    $graphInputs = Get-SwiftUIBaselineGraphInputs -Manifest $baseline -CaptureRoot $captureRootPath -Exports $exports
    $graphPhysicalPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
    foreach ($graph in $graphInputs) {
        $path = Resolve-SwiftUIAuditArtifactPath $captureRootPath $graph.relativePath
        if (-not $graphPhysicalPaths.Add($path)) { throw "Aliased raw symbol graph '$($graph.relativePath)'." }
        if (-not $graphPaths.Remove($graph.relativePath)) { throw "Unexpected or undiscovered raw symbol graph '$($graph.relativePath)'." }
        $graph.path = $path
    }
    if ($graphPaths.Count -ne 0 -or $graphInputs.Count -ne $capture.inventory.counts.graphs) {
        throw 'Discovered raw symbol graph set differs from the candidate capture.'
    }
    return [pscustomobject][ordered]@{
        captureRoot = $captureRootPath; capture = $capture; captureSha256 = $captureFile.sha256; statusSha256 = $statusFile.sha256
        baselineManifest = $baseline; baselineManifestPath = $baselinePath; baselineManifestSha256 = $baselineFile.sha256
        expectedBaselineSha256 = $expectedFile.sha256; inventoryPath = $inventoryPath; inventorySha256 = $capture.inventory.sha256
        graphInputs = $graphInputs; publicInterfaces = $interfaceFiles.ToArray(); crossImportDefinitions = $overlayFiles.ToArray()
        inputFiles = $inputFiles.ToArray()
    }
}
