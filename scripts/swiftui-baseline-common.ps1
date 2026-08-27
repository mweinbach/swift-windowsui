# Shared, platform-independent validation and indexing. Dot-sourcing this file
# does not run native tools, change the baseline manifest, or claim conformance.

function Write-SwiftUIBaselineJson {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)

    $json = ConvertTo-Json -InputObject $Value -Depth 100 -WarningAction Stop
    [System.IO.File]::WriteAllText($Path, $json + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Get-SwiftUIBaselineProperty {
    param($Value, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $Value) { return $null }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    # Do not let the pipeline turn an empty array into null or a singleton
    # array into a scalar; availability metadata must retain its JSON shape.
    return ,$property.Value
}

function Read-SwiftUIBaselineManifest {
    param([Parameter(Mandatory)][string]$Path)

    $manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1) { throw "Unsupported SwiftUI baseline schema version." }
    if ([string]::IsNullOrWhiteSpace($manifest.baselineId)) { throw "Baseline ID is required." }
    foreach ($field in @("xcodeVersion", "sdkVersion", "swiftCompilerMajorMinor")) {
        if ($manifest.toolchain.$field -notmatch '^\d+\.\d+(?:\.\d+)?$') {
            throw "Baseline toolchain.$field must be an explicit numeric release version."
        }
    }
    if ($manifest.toolchain.sdkName -cne "macosx" -or
        $manifest.toolchain.toolchainName -cne "XcodeDefault" -or
        $manifest.toolchain.swiftLanguageMode -cne "6") {
        throw "Baseline requires the macOS SDK, XcodeDefault toolchain, and Swift 6 language mode."
    }
    foreach ($field in @("modules", "allowedReexportedModules")) {
        $names = @($manifest.scope.$field)
        if ($names.Count -ne 2 -or $names -cnotcontains "SwiftUI" -or $names -cnotcontains "SwiftUICore") {
            throw "Baseline scope.$field must retain both SwiftUI and SwiftUICore."
        }
    }
    $expectedTargets = @("arm64-apple-macosx$($manifest.toolchain.sdkVersion)",
        "x86_64-apple-macosx$($manifest.toolchain.sdkVersion)")
    if (@($manifest.scope.targets).Count -ne 2) { throw "Both desktop architecture targets are required." }
    foreach ($target in $expectedTargets) {
        if ($manifest.scope.targets -cnotcontains $target) {
            throw "Missing complete-SDK target '$target'; the deployment floor is not an API ceiling."
        }
    }
    if ($manifest.scope.minimumAccessLevel -cne "public" -or $manifest.scope.includeSPISymbols -ne $false) {
        throw "Baseline extraction must request public API without SPI."
    }
    foreach ($field in @("preserveAvailabilityMetadata", "preserveExtensionGraphs",
            "preserveSynthesizedMembers", "preservePublicInterfacesAndImports")) {
        if ($manifest.scope.$field -ne $true) { throw "Baseline scope.$field must remain enabled." }
    }
    if ($null -eq $manifest.reviewedIdentity -or $null -eq $manifest.evidence) {
        throw "Baseline must state reviewed identity and evidence status explicitly."
    }
    return $manifest
}

function ConvertTo-SwiftUIBaselineIdentity {
    param(
        [Parameter(Mandatory)][string]$XcodeOutput,
        [Parameter(Mandatory)][string]$SDKVersion,
        [Parameter(Mandatory)][string]$SDKBuildVersion,
        [Parameter(Mandatory)][string]$SwiftOutput
    )

    $xcodeVersion = [regex]::Match($XcodeOutput, '(?m)^Xcode (\d+\.\d+(?:\.\d+)?)[ \t]*\r?$')
    $xcodeBuild = [regex]::Match($XcodeOutput, '(?m)^Build version ([A-Za-z0-9]+)[ \t]*\r?$')
    $swiftVersion = [regex]::Match($SwiftOutput, '(?m)^((?:swift-driver version: [^ \t\r\n]+[ \t]+)?Apple Swift version (\d+\.\d+(?:\.\d+)?)(?=[ \t(]|\r?$)[^\r\n]*)\r?$')
    if (-not $xcodeVersion.Success -or -not $xcodeBuild.Success) {
        throw "Cannot identify the Xcode release and build from xcodebuild -version."
    }
    if (-not $swiftVersion.Success -or $SwiftOutput -match '(?i)DEVELOPMENT-SNAPSHOT|\bbeta\b') {
        throw "Expected a released Apple Swift compiler from XcodeDefault."
    }
    if ($SDKVersion.Trim() -notmatch '^\d+\.\d+(?:\.\d+)?$' -or
        $SDKBuildVersion.Trim() -notmatch '^[A-Za-z0-9]+$') {
        throw "Cannot identify the macOS SDK version and build."
    }
    return [pscustomobject][ordered]@{
        xcodeVersion = $xcodeVersion.Groups[1].Value
        xcodeBuildVersion = $xcodeBuild.Groups[1].Value
        sdkVersion = $SDKVersion.Trim()
        sdkBuildVersion = $SDKBuildVersion.Trim()
        swiftCompilerVersion = $swiftVersion.Groups[2].Value
        swiftCompilerVersionLine = $swiftVersion.Groups[1].Value.TrimEnd()
    }
}

function Assert-SwiftUIBaselineIdentity {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)]$Identity,
        [switch]$RequireReviewedIdentity
    )

    foreach ($field in @("xcodeVersion", "sdkVersion")) {
        if ($Identity.$field -cne $Manifest.toolchain.$field) {
            throw "Wrong $field for $($Manifest.baselineId): expected '$($Manifest.toolchain.$field)', got '$($Identity.$field)'. Select the pinned Xcode installation using DEVELOPER_DIR; no fallback is allowed."
        }
    }
    $compilerParts = $Identity.swiftCompilerVersion.Split('.')
    $majorMinor = $compilerParts[0] + "." + $compilerParts[1]
    if ($majorMinor -cne $Manifest.toolchain.swiftCompilerMajorMinor) {
        throw "Wrong Swift compiler: expected Apple Swift $($Manifest.toolchain.swiftCompilerMajorMinor).x, got '$($Identity.swiftCompilerVersion)'."
    }
    $hasReviewedIdentity = $Manifest.reviewedIdentity.status -ceq "reviewed"
    foreach ($field in @("xcodeBuildVersion", "sdkBuildVersion", "swiftCompilerVersionLine")) {
        $expected = $Manifest.reviewedIdentity.$field
        if ([string]::IsNullOrWhiteSpace($expected)) {
            $hasReviewedIdentity = $false
        } elseif ($Identity.$field -cne $expected) {
            throw "Pinned identity mismatch for ${field}: expected '$expected', got '$($Identity.$field)'."
        }
    }
    if ($RequireReviewedIdentity -and -not $hasReviewedIdentity) {
        throw "Exact Xcode/SDK/compiler identity is awaiting actual capture and review. A version-matched candidate export cannot qualify the baseline."
    }
    return $hasReviewedIdentity
}

function Get-SwiftUIBaselineRelativePath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)

    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]"\/") + [System.IO.Path]::DirectorySeparatorChar
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $comparison = [System.StringComparison]::Ordinal
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $comparison = [System.StringComparison]::OrdinalIgnoreCase }
    if (-not $fullPath.StartsWith($rootPath, $comparison)) {
        throw "Path '$fullPath' is not contained in '$rootPath'."
    }
    return $fullPath.Substring($rootPath.Length).Replace('\', '/')
}

function Get-SwiftUIBaselineTextHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $algorithm.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
        return ([System.BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Get-SwiftUIBaselineInterfaceImports {
    param([Parameter(Mandatory)][string]$Text)

    # This is an evidence index, not a Swift conditional-compilation parser.
    # The unmodified interface is retained, including surrounding #if blocks.
    $pattern = '(?m)^[ \t]*(?<attributes>(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\r\n]*\))?[ \t]*(?:\r?\n[ \t]*)?)*)((?<access>public|internal|package|fileprivate|private)[ \t]+)?import[ \t]+(?:(?:typealias|struct|class|enum|protocol|let|var|func)[ \t]+)?(?<module>[A-Za-z_][A-Za-z0-9_]*)(?:\.[^\r\n ]+)?[^\r\n]*'
    $imports = [System.Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        $imports.Add([pscustomobject][ordered]@{
            line = 1 + [regex]::Matches($Text.Substring(0, $match.Index), "`n").Count
            module = $match.Groups["module"].Value
            exportedAttribute = $match.Groups["attributes"].Value -match '@_exported\b'
            access = $match.Groups["access"].Value
            declaration = $match.Value.Trim()
            conditionalCompilationEvaluated = $false
        })
    }
    return ,$imports.ToArray()
}

function New-SwiftUIBaselineInventory {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$CaptureRoot,
        [Parameter(Mandatory)][object[]]$Exports
    )

    $expectedPairs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($target in $Manifest.scope.targets) {
        foreach ($module in $Manifest.scope.modules) { [void]$expectedPairs.Add("$target/$module") }
    }
    $graphPaths = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($export in $Exports) {
        $pair = "$($export.target)/$($export.module)"
        if (-not $expectedPairs.Remove($pair)) { throw "Unexpected or duplicate module/target export '$pair'." }
        [void](Get-SwiftUIBaselineRelativePath -Root $CaptureRoot -Path $export.directory)
        $primaryGraph = Join-Path $export.directory "$($export.module).symbols.json"
        if (-not (Test-Path -LiteralPath $primaryGraph -PathType Leaf)) {
            throw "Missing primary symbol graph for '$pair'. No partial capture is accepted."
        }
        foreach ($file in Get-ChildItem -LiteralPath $export.directory -Filter '*.symbols.json' -File -Recurse) {
            $relativePath = Get-SwiftUIBaselineRelativePath -Root $CaptureRoot -Path $file.FullName
            if ($graphPaths.ContainsKey($relativePath)) { throw "Graph '$relativePath' belongs to multiple exports." }
            $graphPaths.Add($relativePath, [pscustomobject]@{ file = $file; export = $export; primary = ($file.FullName -ceq $primaryGraph) })
        }
    }
    if ($expectedPairs.Count -ne 0) { throw "Missing module/target exports: $([string]::Join(', ', $expectedPairs))." }

    $symbols = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $graphRecords = [System.Collections.Generic.List[object]]::new()
    $relationshipRecords = [System.Collections.Generic.List[object]]::new()
    $hashLines = [System.Collections.Generic.List[string]]::new()
    [string[]]$orderedPaths = @($graphPaths.Keys)
    [System.Array]::Sort($orderedPaths, [System.StringComparer]::Ordinal)
    $declarationCount = 0
    foreach ($path in $orderedPaths) {
        $entry = $graphPaths[$path]
        $graph = Get-Content -LiteralPath $entry.file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $graph.metadata -or $null -eq $graph.module -or
            $graph.symbols -isnot [array] -or $graph.relationships -isnot [array]) {
            throw "Malformed symbol graph '$path': expected metadata, module, symbols array, and relationships array."
        }
        if ($entry.primary -and ($graph.module.name -cne $entry.export.module -or $graph.symbols.Count -eq 0)) {
            throw "Primary graph '$path' is empty or names the wrong module."
        }
        $expectedArchitecture = $entry.export.target.Split('-')[0]
        if ($graph.module.platform.architecture -cne $expectedArchitecture) {
            throw "Graph '$path' has the wrong architecture for '$($entry.export.target)'."
        }
        if ($graph.module.platform.operatingSystem.name -cnotin @("macosx", "macos")) {
            throw "Graph '$path' is not a macOS desktop graph."
        }
        $hash = (Get-FileHash -LiteralPath $entry.file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $hashLines.Add("$path`t$hash`n")
        $graphRecords.Add([pscustomobject][ordered]@{
            path = $path
            sha256 = $hash
            requestedModule = $entry.export.module
            target = $entry.export.target
            metadata = $graph.metadata
            module = $graph.module
            symbolCount = $graph.symbols.Count
            relationshipCount = $graph.relationships.Count
        })
        for ($index = 0; $index -lt $graph.symbols.Count; $index++) {
            $symbol = $graph.symbols[$index]
            $precise = [string]$symbol.identifier.precise
            if ([string]::IsNullOrWhiteSpace($precise)) { throw "Symbol $index in '$path' has no precise identifier." }
            if (-not $symbols.ContainsKey($precise)) {
                $symbols.Add($precise, [System.Collections.Generic.List[object]]::new())
            }
            $occurrence = [ordered]@{
                graphPath = $path
                symbolIndex = $index
                requestedModule = $entry.export.module
                target = $entry.export.target
                interfaceLanguage = $symbol.identifier.interfaceLanguage
                kind = $symbol.kind
                pathComponents = $symbol.pathComponents
                names = $symbol.names
                accessLevel = Get-SwiftUIBaselineProperty -Value $symbol -Name "accessLevel"
            }
            # Retain availability domains, version tuples, and unknown fields
            # verbatim. Nothing is excluded because it is deprecated, newer
            # than the package deployment floor, or unavailable on this target.
            foreach ($name in @("availability", "declarationFragments", "swiftGenerics", "swiftExtension")) {
                if ($null -ne $symbol.PSObject.Properties[$name]) {
                    $occurrence[$name] = Get-SwiftUIBaselineProperty -Value $symbol -Name $name
                }
            }
            $symbols[$precise].Add([pscustomobject]$occurrence)
            $declarationCount++
        }
        for ($index = 0; $index -lt $graph.relationships.Count; $index++) {
            $relationship = $graph.relationships[$index]
            foreach ($required in @("kind", "source", "target")) {
                if ([string]::IsNullOrWhiteSpace($relationship.$required)) {
                    throw "Relationship $index in '$path' is missing '$required'."
                }
            }
            # Keep relationships even when one endpoint belongs to an external
            # module. Dropping them loses conformances and extension ownership.
            $relationshipRecords.Add([pscustomobject][ordered]@{
                graphPath = $path
                relationshipIndex = $index
                relationship = $relationship
            })
        }
    }
    [string[]]$identifiers = @($symbols.Keys)
    [System.Array]::Sort($identifiers, [System.StringComparer]::Ordinal)
    $indexedSymbols = [System.Collections.Generic.List[object]]::new()
    foreach ($identifier in $identifiers) {
        $indexedSymbols.Add([pscustomobject][ordered]@{
            preciseIdentifier = $identifier
            occurrences = $symbols[$identifier].ToArray()
        })
    }
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        baselineId = $Manifest.baselineId
        evidenceKind = "compiler-exported-api-inventory-only"
        completeness = "requires-public-interface-and-documentation-audit"
        behaviorConformance = "not-verified"
        crossImportOverlayCompleteness = "requires-declaration-and-interface-audit"
        symbolIdentity = "case-sensitive identifier.precise; occurrences retained across targets and re-exports"
        rawGraphsAreAuthoritative = $true
        counts = [ordered]@{
            graphs = $graphRecords.Count
            preciseSymbols = $indexedSymbols.Count
            declarationOccurrences = $declarationCount
            relationshipOccurrences = $relationshipRecords.Count
        }
        graphSetSha256 = Get-SwiftUIBaselineTextHash -Text ([string]::Concat($hashLines))
        graphs = $graphRecords.ToArray()
        symbols = $indexedSymbols.ToArray()
        relationships = $relationshipRecords.ToArray()
    }
}
