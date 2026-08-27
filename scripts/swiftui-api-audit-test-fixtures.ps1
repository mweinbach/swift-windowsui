# Synthetic audit fixtures only. Dot-sourcing defines functions and runs no
# tests, native commands, capture, or review. All generated evidence stays
# explicitly SYNTHETIC and unreviewed; it is never an Apple SDK capture.

function Resolve-SwiftUIAuditTestRoot {
    param([Parameter(Mandatory)][string]$Root)

    $resolved = Resolve-SwiftUIBaselineFileSystemPath -Path $Root
    $repository = Split-Path -Parent $PSScriptRoot
    foreach ($allowed in @((Join-Path $repository 'artifacts'), [System.IO.Path]::GetTempPath())) {
        $allowedPath = Resolve-SwiftUIBaselineFileSystemPath -Path $allowed
        try {
            [void](Get-SwiftUIBaselineRelativePath -Root $allowedPath -Path $resolved)
            return $resolved
        } catch { }
    }
    throw 'Synthetic audit fixtures must be inside repository artifacts/ or the OS temporary directory.'
}

function Get-SwiftUIAuditTestFilePath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$RelativePath)

    if ([System.IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Contains('\') -or
        $RelativePath.Contains(':') -or $RelativePath -match '(^|/)(\.|\.\.|)($|/)') {
        throw "Synthetic fixture path must be a contained portable relative path: '$RelativePath'."
    }
    $path = [System.IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    [void](Get-SwiftUIBaselineRelativePath -Root $Root -Path $path)
    $physical = Resolve-SwiftUIBaselineFileSystemPath -Path $path
    [void](Get-SwiftUIBaselineRelativePath -Root $Root -Path $physical)
    return $physical
}

function Read-SwiftUIAuditTestSmallJson {
    param([Parameter(Mandatory)][string]$Path)

    # Metadata and checked-in seeds are small. Generated graphs and inventory
    # must never enter this DOM convenience helper, including stress fixtures.
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -gt 4194304) {
        throw "Synthetic fixture metadata is not a small JSON file: '$Path'."
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
}

function Get-SwiftUIAuditTestHash {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Write-SwiftUIAuditTestGraph {
    param(
        [Parameter(Mandatory)]$Graph,
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyCollection()][string[]]$AdditionalSymbols = @(),
        [AllowEmptyCollection()][string[]]$AdditionalRelationships = @(),
        [ValidateRange(0, 2147483647)][int]$RepeatedSymbols = 0,
        [ValidateRange(0, 16777216)][int]$SymbolPayloadCharacters = 0
    )

    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false), 65536)
    $writer.NewLine = "`n"
    try {
        # Raw JSON deliberately exercises keys/numeric spellings that a
        # PowerShell object round trip or XML-backed JSON adapter would lose.
        $writer.WriteLine('{"__type":null,"auditGraphScalar":9e+42,"auditGraphMetadata":{"synthetic":true,"CaseKey":1,"caseKey":2,"nested":[null,[],{"unknown":true}]},')
        $writer.Write('"metadata":')
        $writer.Write((ConvertTo-Json -InputObject $Graph.metadata -Depth 100 -Compress -WarningAction Stop))
        $writer.Write(',"module":')
        $writer.Write((ConvertTo-Json -InputObject $Graph.module -Depth 100 -Compress -WarningAction Stop))
        $writer.WriteLine(',"symbols":[')
        $needsComma = $false
        foreach ($symbol in $Graph.symbols) {
            if ($needsComma) { $writer.WriteLine(',') }
            $writer.Write((ConvertTo-Json -InputObject $symbol -Depth 100 -Compress -WarningAction Stop))
            $needsComma = $true
        }
        foreach ($symbol in $AdditionalSymbols) {
            if ($needsComma) { $writer.WriteLine(',') }
            $writer.Write($symbol)
            $needsComma = $true
        }
        $payloadChunk = [string]::new([char]'x', 4096)
        for ([int]$index = 0; $index -lt $RepeatedSymbols; $index++) {
            if ($needsComma) { $writer.WriteLine(',') }
            # names is projected by the canonical inventory writer. Padding it
            # grows both graph and inventory, including one repeated-ID group.
            $writer.Write('{"identifier":{"precise":"s:auditRepeatedSymbol","interfaceLanguage":"swift"},"kind":{"identifier":"swift.struct","displayName":"Structure"},"names":{"title":"AuditRepeatedSymbol","futurePayload":"')
            [int]$remaining = $SymbolPayloadCharacters
            while ($remaining -gt 0) {
                $count = [Math]::Min($remaining, $payloadChunk.Length)
                $writer.Write($payloadChunk.Substring(0, $count))
                $remaining -= $count
            }
            $writer.Write('"},"pathComponents":["AuditRepeatedSymbol"],"accessLevel":"public","futureStressMixin":{"ordinal":')
            $writer.Write($index.ToString([System.Globalization.CultureInfo]::InvariantCulture))
            $writer.Write(',"rawOnly":true}}')
            $needsComma = $true
        }
        $writer.WriteLine('],"relationships":[')
        $needsComma = $false
        foreach ($relationship in $Graph.relationships) {
            if ($needsComma) { $writer.WriteLine(',') }
            $writer.Write((ConvertTo-Json -InputObject $relationship -Depth 100 -Compress -WarningAction Stop))
            $needsComma = $true
        }
        foreach ($relationship in $AdditionalRelationships) {
            if ($needsComma) { $writer.WriteLine(',') }
            $writer.Write($relationship)
            $needsComma = $true
        }
        $writer.WriteLine(']}')
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function New-SwiftUIAuditTestCommandRecord {
    param([string]$Executable, [string[]]$Arguments, [AllowEmptyString()][string]$Stdout = '')

    return [pscustomobject][ordered]@{
        executable = $Executable
        arguments = $Arguments
        exitCode = 0
        timedOut = $false
        startedAtUtc = '2000-01-01T00:00:00.0000000Z'
        durationSeconds = 0
        stdout = $Stdout
        stderr = 'SYNTHETIC fixture report; no native command was executed.'
    }
}

function New-SwiftUIAuditTestCapture {
    <#
    .SYNOPSIS
    Creates a small, explicitly synthetic successful candidate capture.
    .DESCRIPTION
    Root must be new or empty inside artifacts/ or OS temp. The current pinned
    manifest is copied unchanged. Native tools never run and no review status
    is promoted. The result is a compact descriptor, never an inventory DOM.
    .PARAMETER RepeatedSymbols
    Extra occurrences of one precise identifier in each SwiftUI primary graph.
    Generation streams these occurrences; zero omits them. Defaults to three.
    .PARAMETER SymbolPayloadCharacters
    ASCII characters in each repeated symbol's names.futurePayload, written in
    4 KiB chunks. Both raw graph and projected inventory grow. Defaults to zero;
    large stress fixtures require an explicit value. Raw-only mixins remain.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ManifestPath,
        [ValidateRange(0, 2147483647)][int]$RepeatedSymbols = 3,
        [ValidateRange(0, 16777216)][int]$SymbolPayloadCharacters = 0
    )

    $ErrorActionPreference = 'Stop'
    . (Join-Path $PSScriptRoot 'swiftui-baseline-common.ps1')
    $manifest = Read-SwiftUIBaselineManifest -Path $ManifestPath
    if ($manifest.toolchain.swiftCompilerMajorMinor -cne '6.3') {
        throw 'The synthetic producer/extractor distinction is pinned to the Swift 6.3 fixture family.'
    }
    $compilerLine = 'Apple Swift version 6.3.3 (SYNTHETIC audit extractor; not an Apple SDK capture)'
    $producerLine = 'Apple Swift version 6.3.2 (SYNTHETIC interface producer; not an Apple SDK capture)'
    $xcodeOutput = "Xcode $($manifest.toolchain.xcodeVersion)`nBuild version SYNTHETICXCODE1"
    $swiftOutput = "$compilerLine`nTarget: x86_64-apple-macosx$($manifest.toolchain.sdkVersion)"
    $identity = ConvertTo-SwiftUIBaselineIdentity -XcodeOutput $xcodeOutput `
        -SDKVersion $manifest.toolchain.sdkVersion -SDKBuildVersion 'SYNTHETICSDK1' -SwiftOutput $swiftOutput
    $identityReviewed = Assert-SwiftUIBaselineIdentity -Manifest $manifest -Identity $identity
    if ($identityReviewed) { throw 'Synthetic audit fixtures must not use a reviewed identity.' }

    $captureRoot = Resolve-SwiftUIAuditTestRoot -Root $Root
    if (Test-Path -LiteralPath $captureRoot) {
        if (-not (Test-Path -LiteralPath $captureRoot -PathType Container) -or
            $null -ne (Get-ChildItem -LiteralPath $captureRoot -Force | Select-Object -First 1)) {
            throw 'Synthetic fixture Root must be new or empty; existing evidence is never overwritten.'
        }
    } else {
        [void][System.IO.Directory]::CreateDirectory($captureRoot)
    }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Join-Path $captureRoot 'SYNTHETIC-FIXTURE.txt'),
        "SYNTHETIC SwiftUI API audit fixture. Not an Apple SDK capture. No native tools or behavior were exercised.`n", $utf8)
    $manifestCopy = Join-Path $captureRoot 'baseline-manifest.json'
    Copy-Item -LiteralPath $ManifestPath -Destination $manifestCopy
    $sdkSettingsPath = Join-Path $captureRoot 'SDKSettings.json'
    Write-SwiftUIBaselineJson -Path $sdkSettingsPath -Value ([ordered]@{
        CanonicalName = "macosx$($manifest.toolchain.sdkVersion)"
        Version = $manifest.toolchain.sdkVersion
        ProductBuildVersion = $identity.sdkBuildVersion
        DisplayName = 'SYNTHETIC macOS SDK fixture; not an Apple SDK capture'
        syntheticFixture = $true
    })

    $fixtureRoot = Join-Path $PSScriptRoot 'fixtures/swiftui-baseline'
    $interfaceSeed = Get-Content -LiteralPath (Join-Path $fixtureRoot 'SwiftUI.swiftinterface.txt') -Raw -Encoding UTF8
    $interfaceRecords = [System.Collections.Generic.List[object]]::new()
    foreach ($module in $manifest.scope.modules) {
        foreach ($target in $manifest.scope.targets) {
            $architecture = $target.Split('-')[0]
            $filename = "$architecture-apple-macos.swiftinterface"
            $relativePath = "interfaces/$module/$filename"
            $path = Join-Path $captureRoot $relativePath
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $path))
            $interfaceText = "// swift-interface-format-version: 1.0`n// swift-compiler-version: $producerLine`n" +
                "// swift-module-flags: -target $target -enable-library-evolution -swift-version 5 -module-name $module`n" +
                "// SYNTHETIC public desktop interface. This text is not compiled.`n"
            if ($module -ceq 'SwiftUI') {
                $interfaceText += $interfaceSeed + "`n" + @'
public import UniformTypeIdentifiers
@resultBuilder public struct ViewBuilder {}
public struct Binding<Value> { public var projectedValue: Binding<Value> { get } }
public struct Image { public func resizable(capInsets: EdgeInsets, resizingMode: Image.ResizingMode) -> Image }
public struct LongPressGesture {}
public protocol View {}
extension View {
  public func fileExporter(isPresented: Binding<Bool>, document: AuditDocument?, contentType: UniformTypeIdentifiers.UTType, defaultFilename: String?, onCompletion: (Result<Foundation.URL, any Error>) -> Void) -> some View
}
@attached(member, names: named(_audit)) public macro AuditMacro() = #externalMacro(module: "SyntheticMacroPlugin", type: "AuditMacro")
public struct _AuditPublicView {}
public struct FixtureView { public func fixture(_ value: Int) -> Int; public func fixture(_ value: String) -> String }
'@
            } else {
                $interfaceText += @'
public import Swift
public import Foundation
// Declaring-module spelling deliberately differs from the containing module.
@_originallyDefinedIn(module: "SwiftUI", macOS 26.0)
public protocol FixtureSharedView {}
public struct AuditDocument { public func fileWrapper() -> Foundation.FileWrapper }
'@
            }
            [System.IO.File]::WriteAllText($path, $interfaceText + "`n", $utf8)
            $interfaceRecords.Add([pscustomobject][ordered]@{
                module = $module; path = $relativePath
                sdkRelativeSource = "System/Library/Frameworks/$module.framework/Modules/$module.swiftmodule/$filename"
                sha256 = Get-SwiftUIAuditTestHash -Path $path
                imports = Get-SwiftUIBaselineInterfaceImports -Text $interfaceText
            })
        }
    }
    $overlayRelativePath = 'cross-imports/SwiftUI/SwiftUI.swiftcrossimport/Foundation.swiftoverlay'
    $overlayPath = Join-Path $captureRoot $overlayRelativePath
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $overlayPath))
    [System.IO.File]::WriteAllText($overlayPath,
        "# SYNTHETIC overlay declaration; no compiler loaded this definition.`nversion: 1`nmodules:`n  - name: _SyntheticSwiftUIFoundationOverlay`n", $utf8)
    $overlays = @([pscustomobject][ordered]@{
        module = 'SwiftUI'; path = $overlayRelativePath
        sdkRelativeSource = 'System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftcrossimport/Foundation.swiftoverlay'
        sha256 = Get-SwiftUIAuditTestHash -Path $overlayPath
        evaluation = 'not-performed; reconcile definitions with emitted graphs during inventory review'
    })

    # Keep raw records as JSON text. In particular, do not parse case-distinct
    # mixin keys or unknown numeric lexemes through ConvertFrom-Json.
    $additionalSymbols = @(
        '{"identifier":{"precise":"s:auditFixtureOverloadString","interfaceLanguage":"swift"},"kind":{"identifier":"swift.method","displayName":"Instance Method"},"names":{"title":"fixture(_:)"},"pathComponents":["FixtureView","fixture(_:)"],"accessLevel":"public","availability":null,"declarationFragments":[{"kind":"text","spelling":"func fixture(_ value: String) -> String"}],"functionSignature":{"parameters":[{"name":"value","declarationFragments":[{"kind":"text","spelling":"_ value: "},{"kind":"typeIdentifier","spelling":"String","preciseIdentifier":"s:SS"}]}],"returns":[{"kind":"typeIdentifier","spelling":"String","preciseIdentifier":"s:SS"}]},"auditUnknownMixin":{"__type":null,"CaseKey":9e+42,"caseKey":-0.00e+99,"largeInteger":9007199254740993,"fraction":1.2300},"AuditMixin":{"retained":true},"auditMixin":{"retained":false}}',
        '{"identifier":{"precise":"s:fixtureSharedViewP","interfaceLanguage":"swift"},"kind":{"identifier":"swift.protocol","displayName":"Protocol"},"names":{"title":"FixtureSharedView"},"pathComponents":["FixtureSharedView"],"accessLevel":"public","availability":null,"futureSymbolMixin":{"sameGraphDuplicate":true}}',
        '{"identifier":{"precise":"s:7SwiftUI17AuditReexportedViewP","interfaceLanguage":"swift"},"kind":{"identifier":"swift.protocol","displayName":"Protocol"},"names":{"title":"AuditReexportedView"},"pathComponents":["AuditReexportedView"],"accessLevel":"public"}',
        '{"identifier":{"precise":"s:auditViewBuilder","interfaceLanguage":"swift"},"kind":{"identifier":"swift.struct","displayName":"Structure"},"names":{"title":"ViewBuilder"},"pathComponents":["ViewBuilder"],"accessLevel":"public","declarationFragments":[{"kind":"text","spelling":"@resultBuilder struct ViewBuilder"}]}',
        '{"identifier":{"precise":"s:auditBindingProjection","interfaceLanguage":"swift"},"kind":{"identifier":"swift.property","displayName":"Instance Property"},"names":{"title":"projectedValue"},"pathComponents":["Binding","projectedValue"],"accessLevel":"public","declarationFragments":[{"kind":"text","spelling":"var projectedValue: Binding<Value> { get }"}],"swiftGenerics":{"parameters":[{"name":"Value","index":0,"depth":0}]}}',
        '{"identifier":{"precise":"s:auditImageResizable","interfaceLanguage":"swift"},"kind":{"identifier":"swift.method","displayName":"Instance Method"},"names":{"title":"resizable(capInsets:resizingMode:)"},"pathComponents":["Image","resizable(capInsets:resizingMode:)"],"accessLevel":"public","availability":[],"declarationFragments":[{"kind":"text","spelling":"func resizable(capInsets: EdgeInsets, resizingMode: Image.ResizingMode) -> Image"}],"functionSignature":{"parameters":[{"name":"capInsets","declarationFragments":[{"kind":"text","spelling":"capInsets: EdgeInsets"}]},{"name":"resizingMode","declarationFragments":[{"kind":"text","spelling":"resizingMode: Image.ResizingMode"}]}],"returns":[{"kind":"typeIdentifier","spelling":"Image","preciseIdentifier":"s:auditImage"}]}}',
        '{"identifier":{"precise":"s:auditLongPressGesture","interfaceLanguage":"swift"},"kind":{"identifier":"swift.struct","displayName":"Structure"},"names":{"title":"LongPressGesture"},"pathComponents":["LongPressGesture"],"accessLevel":"public"}',
        '{"identifier":{"precise":"s:auditFileExporter","interfaceLanguage":"swift"},"kind":{"identifier":"swift.method","displayName":"Instance Method"},"names":{"title":"fileExporter(isPresented:document:contentType:defaultFilename:onCompletion:)"},"pathComponents":["View","fileExporter(isPresented:document:contentType:defaultFilename:onCompletion:)"],"accessLevel":"public","declarationFragments":[{"kind":"text","spelling":"func fileExporter(isPresented: Binding<Bool>, document: AuditDocument?, contentType: UTType, defaultFilename: String?, onCompletion: (Result<URL, any Error>) -> Void) -> some View"}],"functionSignature":{"parameters":[{"name":"isPresented","declarationFragments":[{"kind":"text","spelling":"isPresented: Binding<Bool>"}]},{"name":"document","declarationFragments":[{"kind":"text","spelling":"document: AuditDocument?"}]},{"name":"contentType","declarationFragments":[{"kind":"text","spelling":"contentType: UTType"}]},{"name":"defaultFilename","declarationFragments":[{"kind":"text","spelling":"defaultFilename: String?"}]},{"name":"onCompletion","declarationFragments":[{"kind":"text","spelling":"onCompletion: (Result<URL, any Error>) -> Void"}]}],"returns":[{"kind":"text","spelling":"some View"}]}}',
        '{"identifier":{"precise":"s:auditMacro","interfaceLanguage":"swift"},"kind":{"identifier":"swift.macro","displayName":"Macro"},"names":{"title":"AuditMacro()"},"pathComponents":["AuditMacro()"],"accessLevel":"public","declarationFragments":[{"kind":"text","spelling":"@attached(member, names: named(_audit)) macro AuditMacro()"}],"futureMacroMixin":{"roles":["member"]}}',
        '{"identifier":{"precise":"s:auditPublicUnderscore","interfaceLanguage":"swift"},"kind":{"identifier":"swift.struct","displayName":"Structure"},"names":{"title":"_AuditPublicView"},"pathComponents":["_AuditPublicView"],"accessLevel":"public","availability":[]}',
        '{"identifier":{"precise":"s:auditRequirement::SYNTHESIZED::s:auditConformer","interfaceLanguage":"swift"},"kind":{"identifier":"swift.method","displayName":"Instance Method"},"names":{"title":"fixture(_:)"},"pathComponents":["AuditConformer","fixture(_:)"],"accessLevel":"public","availability":[{"domain":"macOS","isUnconditionallyUnavailable":true},{"domain":"Swift","introduced":{"major":6}}],"swiftExtension":{"extendedModule":"SwiftUI","constraints":[{"kind":"conformance","lhs":"Element","rhs":"FixtureSharedView"}]}}'
    )
    $additionalRelationships = @(
        '{"kind":"memberOf","source":"s:auditFixtureOverloadString","target":"s:fixtureViewV"}',
        '{"kind":"defaultImplementationOf","source":"s:auditRequirement::SYNTHESIZED::s:auditConformer","target":"s:fixtureOverload1","swiftConstraints":[{"kind":"conformance","lhs":"Element","rhs":"FixtureSharedView"}]}',
        '{"kind":"conformsTo","source":"s:fixtureViewV","target":"s:ExternalConditionalProtocol","targetFallback":"External.ConditionalProtocol","swiftConstraints":[{"kind":"conformance","lhs":"Element","rhs":"FixtureSharedView"}],"sourceOrigin":{"identifier":"s:ExternalDocumentationOrigin","displayName":"External.DocumentationOrigin"},"futureRelationshipMixin":{"__type":null,"numeric":9e+42}}'
    )
    $exports = [System.Collections.Generic.List[object]]::new()
    foreach ($target in $manifest.scope.targets) {
        foreach ($module in $manifest.scope.modules) {
            $directory = Join-Path $captureRoot "graphs/$target/$module"
            [void][System.IO.Directory]::CreateDirectory($directory)
            $fixtureNames = @("$module.symbols.json")
            if ($module -ceq 'SwiftUI') { $fixtureNames += 'SwiftUI@Foundation.symbols.json' }
            foreach ($name in $fixtureNames) {
                $graph = Read-SwiftUIAuditTestSmallJson -Path (Join-Path $fixtureRoot $name)
                $graph.metadata.generator = $compilerLine
                $graph.module.platform.architecture = $target.Split('-')[0]
                if ($graph.module.platform.architecture -ceq 'arm64') { $graph.module.platform.architecture = 'aarch64' }
                $extraSymbols = @()
                $extraRelationships = @()
                $repeatCount = 0
                if ($name -ceq 'SwiftUI.symbols.json') {
                    $typedOverload = $graph.symbols[1]
                    $typedOverload | Add-Member -NotePropertyName declarationFragments -NotePropertyValue @(
                        [pscustomobject]@{ kind = 'text'; spelling = 'func fixture(_ value: Int) -> Int' })
                    $typedOverload | Add-Member -NotePropertyName functionSignature -NotePropertyValue ([pscustomobject]@{
                        parameters = @([pscustomobject]@{ name = 'value'; declarationFragments = @(
                            [pscustomobject]@{ kind = 'text'; spelling = '_ value: ' },
                            [pscustomobject]@{ kind = 'typeIdentifier'; spelling = 'Int'; preciseIdentifier = 's:Si' }) })
                        returns = @([pscustomobject]@{ kind = 'typeIdentifier'; spelling = 'Int'; preciseIdentifier = 's:Si' })
                    })
                    $extraSymbols = $additionalSymbols
                    $extraRelationships = $additionalRelationships
                    $repeatCount = $RepeatedSymbols
                } elseif ($name -ceq 'SwiftUICore.symbols.json') {
                    # This re-export has an exact SwiftUI-spelled ID in a
                    # SwiftUICore module record; do not rewrite the identifier.
                    $extraSymbols = @($additionalSymbols[2])
                }
                Write-SwiftUIAuditTestGraph -Graph $graph -Path (Join-Path $directory $name) `
                    -AdditionalSymbols $extraSymbols -AdditionalRelationships $extraRelationships `
                    -RepeatedSymbols $repeatCount -SymbolPayloadCharacters $SymbolPayloadCharacters
            }
            $exports.Add([pscustomobject]@{ module = $module; target = $target; directory = $directory })
        }
    }
    $inventoryPath = Join-Path $captureRoot 'inventory.json'
    $inventory = Write-SwiftUIBaselineInventory -Manifest $manifest -CaptureRoot $captureRoot `
        -Exports $exports.ToArray() -Path $inventoryPath

    $developerDirectory = '/SYNTHETIC/Xcode.app/Contents/Developer'
    $toolDirectory = "$developerDirectory/Toolchains/XcodeDefault.xctoolchain/usr/bin"
    $swiftPath = "$toolDirectory/swift"
    $extractorPath = "$toolDirectory/swift-symbolgraph-extract"
    $sdkPath = "$developerDirectory/Platforms/MacOSX.platform/Developer/SDKs/MacOSX$($manifest.toolchain.sdkVersion).sdk"
    $commands = [System.Collections.Generic.List[object]]::new()
    $commands.Add((New-SwiftUIAuditTestCommandRecord '/usr/bin/xcodebuild' @('-version') $xcodeOutput))
    $commands.Add((New-SwiftUIAuditTestCommandRecord '/usr/bin/xcrun' @('--sdk', 'macosx', '--show-sdk-version') $identity.sdkVersion))
    $commands.Add((New-SwiftUIAuditTestCommandRecord '/usr/bin/xcrun' @('--sdk', 'macosx', '--show-sdk-build-version') $identity.sdkBuildVersion))
    $commands.Add((New-SwiftUIAuditTestCommandRecord '/usr/bin/xcrun' @('--sdk', 'macosx', '--show-sdk-path') $sdkPath))
    $commands.Add((New-SwiftUIAuditTestCommandRecord '/usr/bin/xcrun' @('--toolchain', 'XcodeDefault', '--find', 'swift') $swiftPath))
    $commands.Add((New-SwiftUIAuditTestCommandRecord '/usr/bin/xcrun' @('--toolchain', 'XcodeDefault', '--find', 'swift-symbolgraph-extract') $extractorPath))
    $commands.Add((New-SwiftUIAuditTestCommandRecord $swiftPath @('--version') $swiftOutput))
    foreach ($export in $exports) {
        $arguments = @('-module-name', $export.module, '-sdk', $sdkPath, '-target', $export.target,
            '-swift-version', $manifest.toolchain.swiftLanguageMode,
            '-module-cache-path', (Join-Path $captureRoot "module-cache/$($export.target)"),
            '-minimum-access-level', 'public', '-emit-extension-block-symbols',
            "-experimental-allowed-reexported-modules=$($manifest.scope.allowedReexportedModules -join ',')",
            '-v', '-pretty-print', '-output-dir', $export.directory)
        $commands.Add((New-SwiftUIAuditTestCommandRecord $extractorPath $arguments 'SYNTHETIC successful extraction report.'))
    }
    $commands.Add((New-SwiftUIAuditTestCommandRecord '/usr/bin/sw_vers' @('-productVersion') $identity.sdkVersion))
    $commands.Add((New-SwiftUIAuditTestCommandRecord '/usr/bin/sw_vers' @('-buildVersion') 'SYNTHETICHOST1'))
    $commands.Add((New-SwiftUIAuditTestCommandRecord '/usr/bin/uname' @('-m') 'x86_64'))
    $capture = [ordered]@{
        schemaVersion = 1; baselineId = $manifest.baselineId
        status = 'exported-awaiting-inventory-and-behavior-review'
        startedAtUtc = '2000-01-01T00:00:00.0000000Z'; finishedAtUtc = '2000-01-01T00:00:01.0000000Z'
        syntheticFixture = [ordered]@{
            kind = 'swiftui-api-audit-tests'; schemaVersion = 1
            warning = 'SYNTHETIC metadata and reports. Not an Apple SDK capture; no native tools or behavior were exercised.'
            reportedToolHashBasis = 'SHA256 of explicitly synthetic marker text, not a native executable.'
            repeatedSymbolsPerSwiftUIPrimaryGraph = $RepeatedSymbols
            symbolPayloadCharacters = $SymbolPayloadCharacters
        }
        exactIdentityPreviouslyReviewed = $false; observedIdentity = $identity
        host = [ordered]@{
            macOSVersion = $identity.sdkVersion; macOSBuildVersion = 'SYNTHETICHOST1'
            architecture = 'x86_64'; powerShellVersion = '7.6.0'
            note = 'SYNTHETIC export host description only; no native SwiftUI reference behavior was exercised.'
        }
        developerDirectoryOverride = $developerDirectory
        baselineManifest = [ordered]@{ path = 'baseline-manifest.json'; sha256 = Get-SwiftUIAuditTestHash $manifestCopy }
        tools = @(
            [ordered]@{ path = $swiftPath; sha256 = Get-SwiftUIBaselineTextHash 'SYNTHETIC swift tool fixture; not an executable' },
            [ordered]@{ path = $extractorPath; sha256 = Get-SwiftUIBaselineTextHash 'SYNTHETIC symbolgraph extractor fixture; not an executable' }
        )
        exporterSources = @(
            foreach ($name in @('export-swiftui-baseline.ps1', 'swiftui-baseline-common.ps1', 'swiftui-baseline-streaming.ps1')) {
                [ordered]@{ path = "scripts/$name"; sha256 = Get-SwiftUIAuditTestHash (Join-Path $PSScriptRoot $name) }
            }
        )
        sdk = [ordered]@{
            path = $sdkPath; version = $identity.sdkVersion; buildVersion = $identity.sdkBuildVersion
            settingsPath = 'SDKSettings.json'; settingsSha256 = Get-SwiftUIAuditTestHash $sdkSettingsPath
        }
        requestedScope = $manifest.scope; publicInterfaces = $interfaceRecords.ToArray()
        crossImportDefinitions = $overlays
        crossImportOverlayCompleteness = 'not-verified; compiler may silently skip an overlay that fails to load'
        inventory = [ordered]@{
            path = 'inventory.json'; sha256 = $inventory.sha256; graphSetSha256 = $inventory.graphSetSha256
            counts = $inventory.counts; indexing = $inventory.indexing
        }
        commands = $commands.ToArray()
        qualification = [ordered]@{ publicAPIAuditComplete = $false; behaviorConformanceVerified = $false; releaseQualified = $false }
    }
    $capturePath = Join-Path $captureRoot 'capture.json'
    Write-SwiftUIBaselineJson -Path $capturePath -Value $capture
    $statusPath = Join-Path $captureRoot 'capture-status.json'
    Write-SwiftUIBaselineJson -Path $statusPath -Value ([ordered]@{
        baselineId = $manifest.baselineId; status = 'exported-awaiting-review'
        captureManifest = 'capture.json'; captureManifestSha256 = Get-SwiftUIAuditTestHash $capturePath
        behaviorConformance = 'not-verified'
    })
    [void](Update-SwiftUIAuditTestCaptureHashes -Root $captureRoot -CaptureOnly)
    return [pscustomobject][ordered]@{
        Root = $captureRoot; CaptureRoot = $captureRoot; CapturePath = $capturePath
        StatusPath = $statusPath; CaptureStatusPath = $statusPath
        CaptureHashPath = Join-Path $captureRoot 'capture.sha256'
        ManifestPath = $manifestCopy; SourceManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
        InventoryPath = $inventoryPath; Exports = $exports.ToArray(); Counts = $inventory.counts
        GraphSetSha256 = $inventory.graphSetSha256
        SymbolIds = [pscustomobject][ordered]@{
            Lowercase = 's:fixtureViewV'; Uppercase = 's:FixtureViewV'; Shared = 's:fixtureSharedViewP'
            Reexported = 's:7SwiftUI17AuditReexportedViewP'
            IntOverload = 's:fixtureOverload1'; StringOverload = 's:auditFixtureOverloadString'
            Macro = 's:auditMacro'; PublicUnderscore = 's:auditPublicUnderscore'; Repeated = 's:auditRepeatedSymbol'
            Synthesized = 's:auditRequirement::SYNTHESIZED::s:auditConformer'
        }
        QueueFamilies = [ordered]@{
            'view-builder' = 's:auditViewBuilder'; 'binding-projections' = 's:auditBindingProjection'
            'image-resizing' = 's:auditImageResizable'; 'long-press' = 's:auditLongPressGesture'
            'file-export' = 's:auditFileExporter'
        }
        InterfaceProducerCompilerLine = $producerLine; InterfaceProducerLanguageMode = '5'
        ExtractorCompilerLine = $compilerLine; ExtractionLanguageMode = $manifest.toolchain.swiftLanguageMode
    }
}

function Update-SwiftUIAuditTestCaptureHashes {
    <#
    .SYNOPSIS
    Reseals an owned synthetic fixture after a negative test changes metadata.
    .DESCRIPTION
    By default, rehashes referenced local metadata/interface/overlay/inventory
    files, then capture.json and its status seal. Does not rebuild the graph set,
    inventory, counts or indexing, evaluate imports, or change review/status/
    qualification fields. Tests must explicitly regenerate canonical inventory
    after graph changes. Mac tool and exporter-source hashes stay as reported.
    .PARAMETER CaptureOnly
    Only reseal capture.json/capture-status.json. Preserve referenced hashes so
    tests can intentionally supply a stale or malformed digest.
    #>
    param([Parameter(Mandatory)][string]$Root, [switch]$CaptureOnly)

    $ErrorActionPreference = 'Stop'
    . (Join-Path $PSScriptRoot 'swiftui-baseline-common.ps1')
    $captureRoot = Resolve-SwiftUIAuditTestRoot -Root $Root
    $markerPath = Get-SwiftUIAuditTestFilePath -Root $captureRoot -RelativePath 'SYNTHETIC-FIXTURE.txt'
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf) -or
        (Get-Item -LiteralPath $markerPath).Length -gt 4096 -or
        (Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8) -cnotmatch '^SYNTHETIC SwiftUI API audit fixture\.') {
        throw 'Refusing to reseal anything other than an explicitly owned SYNTHETIC audit fixture.'
    }
    $capturePath = Get-SwiftUIAuditTestFilePath -Root $captureRoot -RelativePath 'capture.json'
    $statusPath = Get-SwiftUIAuditTestFilePath -Root $captureRoot -RelativePath 'capture-status.json'
    $capture = Read-SwiftUIAuditTestSmallJson -Path $capturePath
    $status = Read-SwiftUIAuditTestSmallJson -Path $statusPath
    if ($null -eq $capture.syntheticFixture -or $capture.syntheticFixture.kind -cne 'swiftui-api-audit-tests') {
        throw 'Refusing to reseal capture metadata without the SYNTHETIC fixture marker.'
    }
    if (-not $CaptureOnly) {
        $capture.baselineManifest.sha256 = Get-SwiftUIAuditTestHash (Get-SwiftUIAuditTestFilePath $captureRoot $capture.baselineManifest.path)
        $capture.sdk.settingsSha256 = Get-SwiftUIAuditTestHash (Get-SwiftUIAuditTestFilePath $captureRoot $capture.sdk.settingsPath)
        foreach ($record in @($capture.publicInterfaces) + @($capture.crossImportDefinitions)) {
            $record.sha256 = Get-SwiftUIAuditTestHash (Get-SwiftUIAuditTestFilePath $captureRoot $record.path)
        }
        $capture.inventory.sha256 = Get-SwiftUIAuditTestHash (Get-SwiftUIAuditTestFilePath $captureRoot $capture.inventory.path)
        Write-SwiftUIBaselineJson -Path $capturePath -Value $capture
    }
    $captureHash = Get-SwiftUIAuditTestHash -Path $capturePath
    $sealPath = Get-SwiftUIAuditTestFilePath -Root $captureRoot -RelativePath 'capture.sha256'
    [System.IO.File]::WriteAllText($sealPath, "$captureHash  capture.json`n", [System.Text.UTF8Encoding]::new($false))
    $status.captureManifestSha256 = $captureHash
    Write-SwiftUIBaselineJson -Path $statusPath -Value $status
    return [pscustomobject]@{ Root = $captureRoot; CapturePath = $capturePath; CaptureSha256 = $captureHash; StatusPath = $statusPath }
}
