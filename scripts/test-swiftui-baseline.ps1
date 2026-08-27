param()

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "swiftui-baseline-common.ps1")
$repoRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $PSScriptRoot "fixtures/swiftui-baseline"
$manifestPath = Join-Path $repoRoot "docs/swiftui-baseline.json"
$manifest = Read-SwiftUIBaselineManifest -Path $manifestPath
$testRoot = Join-Path $repoRoot ("artifacts/swiftui-baseline-tests/" + [Guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $testRoot -Force)
$script:assertionCount = 0

function Assert-BaselineTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Baseline test failed: $Message" }
    $script:assertionCount++
}

function Assert-BaselineThrows {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    $didThrow = $false
    try { & $Action | Out-Null } catch {
        $didThrow = $true
        Assert-BaselineTest ($_.Exception.Message -match $Pattern) "$Message (unexpected error: $($_.Exception.Message))"
    }
    Assert-BaselineTest $didThrow "$Message (no error was raised)"
}

function Copy-BaselineTestObject {
    param($Value)
    return (ConvertTo-Json -InputObject $Value -Depth 100 | ConvertFrom-Json)
}

foreach ($name in @("export-swiftui-baseline.ps1", "swiftui-baseline-common.ps1", "test-swiftui-baseline.ps1")) {
    $parseTokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name), [ref]$parseTokens, [ref]$parseErrors)
    Assert-BaselineTest ($parseErrors.Count -eq 0) "PowerShell syntax in $name"
}

# These identifiers are deliberately synthetic. They never update the real
# manifest or imply that a particular Apple Xcode/SDK build has been captured.
$identity = ConvertTo-SwiftUIBaselineIdentity -XcodeOutput "Xcode 26.6`nBuild version TESTXCODE1" -SDKVersion "26.5" -SDKBuildVersion "TESTSDK1" -SwiftOutput "Apple Swift version 6.3 (synthetic test compiler)`nTarget: arm64-apple-macosx26.5"
$unreviewedManifest = Copy-BaselineTestObject $manifest
foreach ($field in @("xcodeBuildVersion", "sdkBuildVersion", "swiftCompilerVersionLine")) {
    $unreviewedManifest.reviewedIdentity.$field = $null
}
Assert-BaselineTest (-not (Assert-SwiftUIBaselineIdentity -Manifest $unreviewedManifest -Identity $identity)) "candidate identity stays unreviewed"
Assert-BaselineThrows { Assert-SwiftUIBaselineIdentity -Manifest $unreviewedManifest -Identity $identity -RequireReviewedIdentity } 'awaiting actual capture' "qualification requires reviewed identity"
foreach ($field in @("xcodeVersion", "sdkVersion", "swiftCompilerVersion")) {
    $wrongIdentity = Copy-BaselineTestObject $identity
    $wrongIdentity.$field = "99.0"
    Assert-BaselineThrows { Assert-SwiftUIBaselineIdentity -Manifest $unreviewedManifest -Identity $wrongIdentity } 'Wrong' "reject wrong $field"
}
$reviewedManifest = Copy-BaselineTestObject $manifest
$reviewedManifest.reviewedIdentity.status = "awaiting-actual-capture-and-review"
foreach ($field in @("xcodeBuildVersion", "sdkBuildVersion", "swiftCompilerVersionLine")) { $reviewedManifest.reviewedIdentity.$field = $identity.$field }
Assert-BaselineTest (-not (Assert-SwiftUIBaselineIdentity -Manifest $reviewedManifest -Identity $identity)) "filled identifiers without explicit review remain candidates"
$reviewedManifest.reviewedIdentity.status = "reviewed"
Assert-BaselineTest (Assert-SwiftUIBaselineIdentity -Manifest $reviewedManifest -Identity $identity -RequireReviewedIdentity) "matching reviewed identity"
foreach ($field in @("xcodeBuildVersion", "sdkBuildVersion", "swiftCompilerVersionLine")) {
    $wrongIdentity = Copy-BaselineTestObject $identity
    $wrongIdentity.$field = "UNREVIEWED"
    Assert-BaselineThrows { Assert-SwiftUIBaselineIdentity -Manifest $reviewedManifest -Identity $wrongIdentity } 'Pinned identity mismatch' "reject changed $field"
}
Assert-BaselineThrows { ConvertTo-SwiftUIBaselineIdentity -XcodeOutput "Xcode 26.6 beta" -SDKVersion "26.5" -SDKBuildVersion "TEST" -SwiftOutput "Apple Swift version 6.3" } 'Cannot identify' "reject ambiguous Xcode identity"
Assert-BaselineThrows { ConvertTo-SwiftUIBaselineIdentity -XcodeOutput "Xcode 26.6`nBuild version TEST" -SDKVersion "26.5" -SDKBuildVersion "TEST" -SwiftOutput "Swift version 6.3 (swift.org)" } 'released Apple Swift' "reject another compiler distribution"

$narrowedManifest = Copy-BaselineTestObject $manifest
$narrowedManifest.scope.modules = @("SwiftUI")
$narrowedPath = Join-Path $testRoot "narrowed-manifest.json"
Write-SwiftUIBaselineJson -Value $narrowedManifest -Path $narrowedPath
Assert-BaselineThrows { Read-SwiftUIBaselineManifest -Path $narrowedPath } 'both SwiftUI and SwiftUICore' "reject omitted core module"
$narrowedManifest = Copy-BaselineTestObject $manifest
$narrowedManifest.scope.targets = @("arm64-apple-macosx15.0", "x86_64-apple-macosx15.0")
Write-SwiftUIBaselineJson -Value $narrowedManifest -Path $narrowedPath
Assert-BaselineThrows { Read-SwiftUIBaselineManifest -Path $narrowedPath } 'deployment floor is not an API ceiling' "reject deployment-floor target substitution"

$exports = [System.Collections.Generic.List[object]]::new()
foreach ($target in $manifest.scope.targets) {
    foreach ($module in $manifest.scope.modules) {
        $directory = Join-Path $testRoot "graphs/$target/$module"
        [void](New-Item -ItemType Directory -Path $directory -Force)
        $fixtureNames = @("$module.symbols.json")
        if ($module -ceq "SwiftUI") { $fixtureNames += "SwiftUI@Foundation.symbols.json" }
        foreach ($name in $fixtureNames) {
            $graph = Get-Content -LiteralPath (Join-Path $fixtureRoot $name) -Raw -Encoding UTF8 | ConvertFrom-Json
            $graph.module.platform.architecture = $target.Split('-')[0]
            Write-SwiftUIBaselineJson -Value $graph -Path (Join-Path $directory $name)
        }
        $exports.Add([pscustomobject]@{ module = $module; target = $target; directory = $directory })
    }
}
$inventory = New-SwiftUIBaselineInventory -Manifest $manifest -CaptureRoot $testRoot -Exports $exports.ToArray()
Assert-BaselineTest ($inventory.counts.graphs -eq 6) "preserve auxiliary extension graphs for both architectures"
Assert-BaselineTest ($inventory.counts.preciseSymbols -eq 6) "index precise identifiers, not display names"
Assert-BaselineTest ($inventory.counts.declarationOccurrences -eq 14) "preserve every target and re-export occurrence"
Assert-BaselineTest ($inventory.counts.relationshipOccurrences -eq 10) "preserve every relationship"
Assert-BaselineTest ($inventory.behaviorConformance -ceq "not-verified") "inventory never implies behavior conformance"
Assert-BaselineTest ($inventory.completeness -ceq "requires-public-interface-and-documentation-audit") "compiler graph is not the completed API audit"
$shared = @($inventory.symbols | Where-Object { $_.preciseIdentifier -ceq "s:fixtureSharedViewP" })
Assert-BaselineTest ($shared.Count -eq 1 -and $shared[0].occurrences.Count -eq 4) "re-export does not erase declaring-module occurrences"
$upper = @($inventory.symbols | Where-Object { $_.preciseIdentifier -ceq "s:FixtureViewV" })
$lower = @($inventory.symbols | Where-Object { $_.preciseIdentifier -ceq "s:fixtureViewV" })
Assert-BaselineTest ($upper.Count -eq 1 -and $lower.Count -eq 1) "precise identifiers are case sensitive"
Assert-BaselineTest ($upper[0].occurrences[0].availability -is [array] -and $upper[0].occurrences[0].availability.Count -eq 0) "preserve empty availability array"
$expectedAvailability = (Get-Content -LiteralPath (Join-Path $fixtureRoot "SwiftUI.symbols.json") -Raw -Encoding UTF8 | ConvertFrom-Json).symbols[0].availability
$expectedJSON = ConvertTo-Json -InputObject $expectedAvailability -Depth 100 -Compress
$actualJSON = ConvertTo-Json -InputObject $lower[0].occurrences[0].availability -Depth 100 -Compress
Assert-BaselineTest ($actualJSON -ceq $expectedJSON) "preserve all availability domains and unknown metadata"
Assert-BaselineTest ($lower[0].occurrences[0].availability[0].message.Contains([string][char]0x00e9)) "preserve UTF-8 accents on Windows PowerShell 5.1"
Assert-BaselineTest ($lower[0].occurrences[0].availability[0].message.Contains([string][char]0x65e5)) "preserve non-Latin availability text"
Assert-BaselineTest ($lower[0].occurrences[0].availability[0].message.Contains([char]::ConvertFromUtf32(0x1f600))) "preserve supplementary Unicode scalars"
Assert-BaselineTest (@($inventory.relationships | Where-Object { $_.relationship.target -ceq "s:ExternalContainer" }).Count -eq 2) "external relationship endpoints are retained"
$extension = @($inventory.symbols | Where-Object { $_.preciseIdentifier -ceq "s:fixtureExternalExtension" })[0]
Assert-BaselineTest ($extension.occurrences[0].swiftExtension.extendedModule -ceq "Foundation") "retain extension ownership"
Assert-BaselineTest ($extension.occurrences[0].swiftGenerics.constraints[0].lhs -ceq "Element") "retain generic extension constraints"
$firstGraph = $inventory.graphs[0]
$firstGraphHash = (Get-FileHash -LiteralPath (Join-Path $testRoot $firstGraph.path) -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-BaselineTest ($firstGraph.sha256 -ceq $firstGraphHash) "record raw graph hash"
$canonicalHashInput = (@($inventory.graphs | ForEach-Object { "$($_.path)`t$($_.sha256)`n" }) -join '')
Assert-BaselineTest ($inventory.graphSetSha256 -ceq (Get-SwiftUIBaselineTextHash -Text $canonicalHashInput)) "graph-set hash follows the documented canonical sequence"
$rawUI = Get-Content -LiteralPath (Join-Path $exports[0].directory "SwiftUI.symbols.json") -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-BaselineTest ($rawUI.symbols[0].futureSymbolMixin.retainedInRawGraph -eq $true) "do not rewrite or strip raw graph mixins"
[string[]]$expectedIDs = @($inventory.symbols.preciseIdentifier)
[System.Array]::Sort($expectedIDs, [System.StringComparer]::Ordinal)
Assert-BaselineTest (($expectedIDs -join "`n") -ceq ($inventory.symbols.preciseIdentifier -join "`n")) "ordinal identifier ordering"
$again = New-SwiftUIBaselineInventory -Manifest $manifest -CaptureRoot $testRoot -Exports @($exports.ToArray() | Sort-Object target -Descending)
Assert-BaselineTest ((ConvertTo-Json -InputObject $inventory -Depth 100 -Compress) -ceq (ConvertTo-Json -InputObject $again -Depth 100 -Compress)) "input export ordering cannot change the index"
Assert-BaselineThrows { New-SwiftUIBaselineInventory -Manifest $manifest -CaptureRoot $testRoot -Exports @($exports[0]) } 'Missing module/target' "reject incomplete architecture/module matrix"
Assert-BaselineThrows { New-SwiftUIBaselineInventory -Manifest $manifest -CaptureRoot $testRoot -Exports @($exports.ToArray() + $exports[0]) } 'duplicate' "reject duplicated module/target exports"

$rawUI.symbols[0].identifier.precise = ""
$malformedPath = Join-Path $exports[0].directory "SwiftUI.symbols.json"
$originalRaw = [System.IO.File]::ReadAllText($malformedPath)
try {
    [System.IO.File]::WriteAllText($malformedPath, $originalRaw + "`n", [System.Text.UTF8Encoding]::new($false))
    $changedBytes = New-SwiftUIBaselineInventory -Manifest $manifest -CaptureRoot $testRoot -Exports $exports.ToArray()
    Assert-BaselineTest ($changedBytes.graphSetSha256 -cne $inventory.graphSetSha256) "raw graph byte changes alter the graph-set hash"
} finally {
    [System.IO.File]::WriteAllText($malformedPath, $originalRaw, [System.Text.UTF8Encoding]::new($false))
}
try {
    Write-SwiftUIBaselineJson -Value $rawUI -Path $malformedPath
    Assert-BaselineThrows { New-SwiftUIBaselineInventory -Manifest $manifest -CaptureRoot $testRoot -Exports $exports.ToArray() } 'no precise identifier' "reject malformed symbol identity"
} finally {
    [System.IO.File]::WriteAllText($malformedPath, $originalRaw, [System.Text.UTF8Encoding]::new($false))
}
$wrongPlatformGraph = $originalRaw | ConvertFrom-Json
$wrongPlatformGraph.module.platform.operatingSystem.name = "linux"
try {
    Write-SwiftUIBaselineJson -Value $wrongPlatformGraph -Path $malformedPath
    Assert-BaselineThrows { New-SwiftUIBaselineInventory -Manifest $manifest -CaptureRoot $testRoot -Exports $exports.ToArray() } 'not a macOS desktop graph' "reject a graph from another platform"
} finally {
    [System.IO.File]::WriteAllText($malformedPath, $originalRaw, [System.Text.UTF8Encoding]::new($false))
}
$wrongArchitectureGraph = $originalRaw | ConvertFrom-Json
$wrongArchitectureGraph.module.platform.architecture = "incorrect"
try {
    Write-SwiftUIBaselineJson -Value $wrongArchitectureGraph -Path $malformedPath
    Assert-BaselineThrows { New-SwiftUIBaselineInventory -Manifest $manifest -CaptureRoot $testRoot -Exports $exports.ToArray() } 'wrong architecture' "reject a graph from another architecture"
} finally {
    [System.IO.File]::WriteAllText($malformedPath, $originalRaw, [System.Text.UTF8Encoding]::new($false))
}

$interfaceText = Get-Content -LiteralPath (Join-Path $fixtureRoot "SwiftUI.swiftinterface.txt") -Raw -Encoding UTF8
$imports = Get-SwiftUIBaselineInterfaceImports -Text $interfaceText
Assert-BaselineTest ($imports.Count -eq 4) "index imports including multiline exported attributes"
Assert-BaselineTest (@($imports | Where-Object { $_.exportedAttribute }).Count -eq 2) "distinguish exported imports from public signature dependencies"
Assert-BaselineTest ($imports[1].module -ceq "Foundation" -and $imports[1].access -ceq "public" -and -not $imports[1].exportedAttribute) "public import is not mislabeled as an exported import"
Assert-BaselineTest ($imports[2].module -ceq "ExternalModule" -and -not $imports[2].conditionalCompilationEvaluated) "preserve conditional scoped-import evidence without claiming evaluation"
Assert-BaselineThrows { Get-SwiftUIBaselineRelativePath -Root $testRoot -Path (Join-Path (Split-Path -Parent $testRoot) "outside.json") } 'not contained' "reject paths outside capture root"
Assert-BaselineTest ((Get-SwiftUIBaselineTextHash -Text "abc") -ceq "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") "SHA-256 known vector"
if ($PSVersionTable.PSVersion.Major -lt 7 -or -not $IsMacOS) {
    Assert-BaselineThrows { & (Join-Path $PSScriptRoot "export-swiftui-baseline.ps1") -OutputPath (Join-Path $testRoot "must-not-export") } 'requires PowerShell 7.*macOS' "reject native SDK export on unsupported hosts"
    Assert-BaselineTest (-not (Test-Path -LiteralPath (Join-Path $testRoot "must-not-export"))) "host rejection leaves no fake capture"
}

Write-SwiftUIBaselineJson -Value $inventory -Path (Join-Path $testRoot "fixture-inventory.json")
Write-Host "SwiftUI baseline tooling passed $script:assertionCount assertions using synthetic fixtures only."
Write-Host "No Apple SDK export, SwiftPM command, or behavior conformance check was run."
exit 0
