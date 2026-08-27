<#
.SYNOPSIS
Exercises the streaming inventory engine with small synthetic fixtures only.
.DESCRIPTION
No Apple SDK export or SwiftPM command runs. All fixtures and outputs stay in
OutputRoot (a unique artifacts directory by default). RepositoryRoot points
at the checkout whose common/streaming scripts should be tested.
#>
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot
)

$ErrorActionPreference = "Stop"
. (Join-Path $RepositoryRoot "scripts/swiftui-baseline-common.ps1")
. (Join-Path $RepositoryRoot "scripts/swiftui-baseline-streaming.ps1")
Initialize-SwiftUIBaselineStreaming
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepositoryRoot ("artifacts/swiftui-baseline-streaming-tests/" + [Guid]::NewGuid().ToString("N"))
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) {
    throw "OutputRoot must not exist; this probe never overwrites existing evidence."
}
[void][System.IO.Directory]::CreateDirectory($OutputRoot)
$script:ProbeAssertions = 0
$script:ProbeUTF8 = [System.Text.UTF8Encoding]::new($false, $true)

function Assert-Probe {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Streaming probe failed: $Message" }
    $script:ProbeAssertions++
}

function New-ProbeGraph {
    param([string]$Path, [string]$Target = "arm64-apple-macosx26.5", [bool]$Primary = $true)
    $graph = [SwiftUIBaseline.Streaming.GraphInput]::new()
    $graph.Path = $Path
    $graph.RelativePath = "graphs/review/SwiftUI.symbols.json"
    $graph.RequestedModule = "SwiftUI"
    $graph.Target = $Target
    $graph.Primary = $Primary
    return $graph
}

function Export-ProbeGraph {
    param(
        [string]$Name, [string]$Text,
        [System.Text.Encoding]$Encoding = $script:ProbeUTF8,
        [long]$SortChunkBytes = 1024, [int]$MergeFanIn = 2,
        [int]$MaximumRecordCharacters = 1048576,
        [string]$Target = "arm64-apple-macosx26.5",
        [bool]$Primary = $true,
        [switch]$RawOnly
    )
    $path = Join-Path $OutputRoot ($Name + ".symbols.json")
    [System.IO.File]::WriteAllText($path, $Text, $Encoding)
    $graph = New-ProbeGraph -Path $path -Target $Target -Primary $Primary
    $output = Join-Path $OutputRoot ($Name + "-inventory.json")
    $summary = [SwiftUIBaseline.Streaming.InventoryWriter]::Write(
        "synthetic-streaming-review-fixture", @($graph), $output,
        $SortChunkBytes, $MergeFanIn, $MaximumRecordCharacters)
    $raw = [System.IO.File]::ReadAllText($output, $script:ProbeUTF8)
    return [pscustomobject]@{
        Path = $path; OutputPath = $output; Summary = $summary; Raw = $raw
        # Fixture-only DOM: every generated input/output in this probe is small.
        Inventory = $(if ($RawOnly) { $null } else { $raw | ConvertFrom-Json })
    }
}

function Assert-RejectedGraph {
    param(
        [string]$Name, [string]$Text,
        [System.Text.Encoding]$Encoding = $script:ProbeUTF8,
        [int]$MaximumRecordCharacters = 1048576,
        [string]$Target = "arm64-apple-macosx26.5",
        [string]$ErrorPattern = ""
    )
    $path = Join-Path $OutputRoot ($Name + ".symbols.json")
    [System.IO.File]::WriteAllText($path, $Text, $Encoding)
    $graph = New-ProbeGraph -Path $path -Target $Target
    $output = Join-Path $OutputRoot ($Name + "-inventory.json")
    $rejected = $false
    $message = ""
    try {
        [void][SwiftUIBaseline.Streaming.InventoryWriter]::Write(
            "synthetic-streaming-review-fixture", @($graph), $output,
            1024, 2, $MaximumRecordCharacters)
    } catch { $rejected = $true; $message = $_.Exception.ToString() }
    Assert-Probe $rejected "reject $Name"
    Assert-Probe (-not [System.IO.File]::Exists($output)) "no published inventory for $Name"
    if ($ErrorPattern) { Assert-Probe ($message -match $ErrorPattern) "specific error for $Name" }
}

$ids = @(
    "s:a", "s:A", ("s:" + [char]0xe000),
    ("s:" + [char]::ConvertFromUtf32(0x10000)),
    ("s:tab" + [char]9 + "line" + [char]10), "s:hot"
)
$expectedGroups = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::Ordinal)
$symbols = [System.Collections.Generic.List[string]]::new()
for ($index = 0; $index -lt 80; $index++) {
    $identifier = if ($index % 2 -eq 0) { "s:hot" } else { $ids[([int][Math]::Floor($index / 2)) % $ids.Length] }
    if (-not $expectedGroups.ContainsKey($identifier)) {
        $expectedGroups.Add($identifier, [System.Collections.Generic.List[long]]::new())
    }
    $expectedGroups[$identifier].Add($index)
    $identifierJSON = [SwiftUIBaseline.Streaming.InventoryWriter]::Quote($identifier)
    if ($identifier -ceq "s:a") { $identifierJSON = '"s:\u0061"' }
    $symbols.Add('{"identifier":{"precise":' + $identifierJSON +
        '},"availability":[{"domain":"macOS","future":{"integer":18446744073709551615,"exponent":1e+0007,"negativeZero":-0}}]' +
        ',"names":{"title":"fixture"},"swiftGenerics":null}')
}
# Deliberately put relationships before symbols and both before metadata/module.
$stressGraph = '{"relationships":[{"kind":"conformsTo","source":"external","target":"missing","extra":-0}],"symbols":[' +
    ($symbols -join ",") + '],"unusedRoot":{"items":[true,false,null,{"array":[]}]}' +
    ',"module":{"name":"SwiftUI","platform":{"architecture":"arm64","operatingSystem":{"name":"macosx"}}}' +
    ',"metadata":{"formatVersion":{"major":0,"minor":6}}}'
$small = Export-ProbeGraph -Name "merge-small-budget" -Text $stressGraph
$wide = Export-ProbeGraph -Name "merge-wide-budget" -Text $stressGraph -SortChunkBytes 65536 -MergeFanIn 16
Assert-Probe ($small.Raw -ceq $wide.Raw) "output bytes independent of resource budgets"
Assert-Probe ($small.Summary.InventorySha256 -ceq $wide.Summary.InventorySha256) "inventory hashes independent of resource budgets"
Assert-Probe ($small.Summary.MergePasses -ge 3) "stress forces multiple merge passes"
Assert-Probe ($small.Summary.InitialSortRuns -gt 8) "stress exceeds bounded fan-in"
Assert-Probe ($small.Summary.PeakOpenRunReaders -eq 2) "merge fan-in remains bounded"
Assert-Probe ($small.Summary.PeakBufferedIndexBytes -le 1024) "small identifiers obey the sort byte budget"
Assert-Probe ($small.Summary.LargestOccurrenceGroup -ge 40) "hot identifier spans runs without loss"
Assert-Probe ($small.Inventory.counts.preciseSymbols -eq 6) "six distinct precise identifiers"
Assert-Probe ($small.Inventory.counts.declarationOccurrences -eq 80) "all 80 declarations retained"
Assert-Probe ($small.Inventory.counts.relationshipOccurrences -eq 1) "external relationship retained"
Assert-Probe ($small.Inventory.behaviorConformance -ceq "not-verified") "no behavior qualification"
Assert-Probe ($small.Inventory.completeness -ceq "requires-public-interface-and-documentation-audit") "no completeness qualification"
Assert-Probe ($small.Inventory.crossImportOverlayCompleteness -ceq "requires-declaration-and-interface-audit") "no cross-import qualification"
[string[]]$expectedIDs = @($expectedGroups.Keys)
[System.Array]::Sort($expectedIDs, [System.StringComparer]::Ordinal)
Assert-Probe (($expectedIDs -join "|") -ceq ($small.Inventory.symbols.preciseIdentifier -join "|")) "UTF-16 ordinal ordering, not UTF-8 byte ordering"
foreach ($group in $small.Inventory.symbols) {
    Assert-Probe (($expectedGroups[$group.preciseIdentifier] -join ",") -ceq ($group.occurrences.symbolIndex -join ",")) "stable sequence for each identifier"
    foreach ($occurrence in $group.occurrences) {
        Assert-Probe ($null -ne $occurrence.PSObject.Properties["swiftGenerics"] -and $null -eq $occurrence.swiftGenerics) "explicit null retained"
        Assert-Probe ($null -eq $occurrence.PSObject.Properties["swiftExtension"]) "absent optional field omitted"
        Assert-Probe ($null -ne $occurrence.PSObject.Properties["accessLevel"] -and $null -eq $occurrence.accessLevel) "missing ordinary field emits null"
    }
}
foreach ($lexeme in @("18446744073709551615", "1e+0007", '"negativeZero":-0')) {
    Assert-Probe ($small.Raw.Contains($lexeme)) "exact numeric lexeme $lexeme"
}
Assert-Probe ($small.Inventory.graphs[0].sha256 -ceq (Get-FileHash -LiteralPath $small.Path -Algorithm SHA256).Hash.ToLowerInvariant()) "hash exact raw graph bytes"

$cases = [ordered]@{
    truncated = $stressGraph.Substring(0, $stressGraph.Length - 1)
    trailing = $stressGraph + "junk"
    root_trailing_comma = $stressGraph.Substring(0, $stressGraph.Length - 1) + ",}"
    duplicate_symbols = '{"symbols":[],' + $stressGraph.Substring(1)
    escaped_duplicate_symbols = '{"\u0073ymbols":[],' + $stressGraph.Substring(1)
    leading_zero = $stressGraph.Replace("18446744073709551615", "01")
    leading_plus = $stressGraph.Replace("18446744073709551615", "+1")
    missing_fraction_digits = $stressGraph.Replace("18446744073709551615", "1.")
    missing_exponent_digits = $stressGraph.Replace("18446744073709551615", "1e+")
    non_json_number = $stressGraph.Replace("18446744073709551615", "NaN")
    duplicate_identity = $stressGraph.Replace('"precise":', '"precise":"duplicate","precise":')
    null_symbols = $stressGraph.Replace('"symbols":[', '"symbols":null,"extraSymbols":[')
    missing_symbols = $stressGraph.Replace('"symbols":[', '"notSymbols":[')
    control_in_string = $stressGraph.Replace("fixture", ("fixture" + [char]1))
    invalid_string_escape = $stressGraph.Replace("fixture", '\x41')
}
foreach ($name in $cases.Keys) { Assert-RejectedGraph -Name $name -Text $cases[$name] }

$minimalGraph = '{"symbols":[{"identifier":{"precise":"s:a"}}],"relationships":[]' +
    ',"module":{"name":"SwiftUI","platform":{"architecture":"arm64","operatingSystem":{"name":"macosx"}}},"metadata":{}}'
$armAlias = Export-ProbeGraph -Name "aarch64-alias" -Text $minimalGraph.Replace('"arm64"', '"aarch64"')
Assert-Probe ($armAlias.Inventory.graphs[0].module.platform.architecture -ceq "aarch64") "preserve observed LLVM architecture alias"
$x64 = Export-ProbeGraph -Name "x86-64" -Text $minimalGraph.Replace('"arm64"', '"x86_64"') -Target "x86_64-apple-macosx26.5"
Assert-Probe ($x64.Inventory.counts.preciseSymbols -eq 1) "matching x86_64 architecture"
foreach ($architecture in @("arm64e", "arm64ec", "ARM64", "AARCH64", "aarch64_be", "aarch64_32", " arm64", "arm64 ", "x86_64")) {
    Assert-RejectedGraph -Name ("wrong-arch-" + $architecture) -Text $minimalGraph.Replace('"arm64"', ('"' + $architecture + '"')) -ErrorPattern "wrong architecture"
}
Assert-RejectedGraph -Name "null-architecture" -Text $minimalGraph.Replace('"arm64"', 'null')
Assert-RejectedGraph -Name "numeric-architecture" -Text $minimalGraph.Replace('"arm64"', '64')
$auxiliaryAlias = Export-ProbeGraph -Name "auxiliary-aarch64" -Text $minimalGraph.Replace('"arm64"', '"aarch64"').Replace('"name":"SwiftUI"', '"name":"Foundation"') -Primary $false
Assert-Probe ($auxiliaryAlias.Inventory.graphs[0].module.name -ceq "Foundation" -and $auxiliaryAlias.Inventory.graphs[0].module.platform.architecture -ceq "aarch64") "auxiliary graph keeps external module and alias metadata"
$emptyAuxiliary = Export-ProbeGraph -Name "empty-auxiliary" -Text $minimalGraph.Replace('[{"identifier":{"precise":"s:a"}}]', '[]') -Primary $false
Assert-Probe ($emptyAuxiliary.Inventory.counts.graphs -eq 1 -and $emptyAuxiliary.Inventory.counts.preciseSymbols -eq 0) "empty auxiliary graphs are retained"
Assert-Probe ($emptyAuxiliary.Inventory.symbols -is [array] -and $emptyAuxiliary.Inventory.symbols.Count -eq 0) "empty symbol collection remains an array"
Assert-Probe ($emptyAuxiliary.Inventory.relationships -is [array] -and $emptyAuxiliary.Inventory.relationships.Count -eq 0) "empty relationship collection remains an array"
Assert-RejectedGraph -Name "wrong-x64-alias" -Text $minimalGraph.Replace('"arm64"', '"aarch64"') -Target "x86_64-apple-macosx26.5" -ErrorPattern "wrong architecture"
Assert-RejectedGraph -Name "wrong-platform" -Text $minimalGraph.Replace('"macosx"', '"linux"') -ErrorPattern "not a macOS desktop graph"
Assert-RejectedGraph -Name "empty-primary" -Text $minimalGraph.Replace('[{"identifier":{"precise":"s:a"}}]', '[]') -ErrorPattern "empty or names the wrong module"
Assert-RejectedGraph -Name "null-symbol" -Text $minimalGraph.Replace('[{"identifier":{"precise":"s:a"}}]', '[null]')
Assert-RejectedGraph -Name "null-relationship" -Text $minimalGraph.Replace('"relationships":[]', '"relationships":[null]')
Assert-RejectedGraph -Name "utf16-bom" -Text $minimalGraph -Encoding ([System.Text.Encoding]::Unicode)

$badUTF8Path = Join-Path $OutputRoot "invalid-utf8.symbols.json"
$badBytes = $script:ProbeUTF8.GetBytes($minimalGraph)
$badBytes[20] = 255
[System.IO.File]::WriteAllBytes($badUTF8Path, $badBytes)
$badUTF8Output = Join-Path $OutputRoot "invalid-utf8-inventory.json"
$rejected = $false
try {
    [void][SwiftUIBaseline.Streaming.InventoryWriter]::Write(
        "synthetic-streaming-review-fixture", @((New-ProbeGraph $badUTF8Path)),
        $badUTF8Output, 1024, 2, 1048576)
} catch { $rejected = $true }
Assert-Probe $rejected "invalid UTF-8 rejected"
Assert-Probe (-not [System.IO.File]::Exists($badUTF8Output)) "invalid UTF-8 never published"

$bom = Export-ProbeGraph -Name "utf8-bom" -Text $minimalGraph -Encoding ([System.Text.UTF8Encoding]::new($true, $true))
Assert-Probe ($bom.Inventory.graphs[0].sha256 -ceq (Get-FileHash -LiteralPath $bom.Path -Algorithm SHA256).Hash.ToLowerInvariant()) "UTF-8 BOM remains part of raw hash"

$prefix = '{"symbols":[{"identifier":{"precise":"s:'
$padding = "x" * (65535 - $prefix.Length)
$suffix = '"},"availability":[]}],"relationships":[]' +
    ',"module":{"name":"SwiftUI","platform":{"architecture":"arm64","operatingSystem":{"name":"macosx"}}},"metadata":{}}'
$escapedBoundaryGraph = $prefix + $padding + '\uD83D\uDE00' + $suffix
$escapedBoundary = Export-ProbeGraph -Name "escaped-boundary" -Text $escapedBoundaryGraph
$expectedBoundaryIdentifier = "s:" + $padding + [char]::ConvertFromUtf32(0x1f600)
Assert-Probe ($escapedBoundary.Inventory.symbols[0].preciseIdentifier -ceq $expectedBoundaryIdentifier) "escaped Unicode crosses character buffer boundary"
$utf8Boundary = Export-ProbeGraph -Name "utf8-boundary" -Text ($prefix + $padding + [char]::ConvertFromUtf32(0x1f600) + $suffix)
Assert-Probe ($utf8Boundary.Inventory.symbols[0].preciseIdentifier -ceq $expectedBoundaryIdentifier) "UTF-8 scalar crosses byte buffer boundary"
Assert-RejectedGraph -Name "record-budget" -Text $escapedBoundaryGraph -MaximumRecordCharacters 1024 -ErrorPattern "MaximumRecordCharacters"

# An ignored root value may exceed a record budget without being materialized.
$unknownLargeGraph = '{"ignoredRoot":[' + ("0," * 40000) + "0]," + $minimalGraph.Substring(1)
$unknownLarge = Export-ProbeGraph -Name "unknown-large-root" -Text $unknownLargeGraph -MaximumRecordCharacters 1024
Assert-Probe ($unknownLarge.Inventory.counts.preciseSymbols -eq 1) "unknown root values stream beyond the retained-record budget"
Assert-Probe ($unknownLarge.Summary.LargestRecordCharacters -le 1024) "unknown discarded value does not enlarge retained-record statistics"
$unknownDuplicate = Export-ProbeGraph -Name "unknown-duplicate-root" -Text ('{"extra":0,"extra":1,' + $minimalGraph.Substring(1))
Assert-Probe ($unknownDuplicate.Inventory.counts.preciseSymbols -eq 1) "unknown root members remain raw evidence without unbounded duplicate-name tracking"
Assert-RejectedGraph -Name "unknown-root-malformed" -Text ('{"extra":[1,],' + $minimalGraph.Substring(1))
Assert-RejectedGraph -Name "too-deep" -Text ('{"extra":' + ('[' * 260) + '0' + (']' * 260) + ',' + $minimalGraph.Substring(1)) -ErrorPattern "nesting exceeds"

# WCF's JSON/XML mapping treats an initial __type member specially. This
# projection must not do so, nor round/normalize unknown numeric metadata.
$unknownMetadata = '{"__type":null,"wide":1234567890123456789012345678901234567890,"decimal":1.2300,"tiny":1E-9999,"escaped":"\\\"[]{}\u0000","array":[null,[],{}],"Name":1,"name":2}'
$unknownFieldsGraph = $minimalGraph.Replace('"metadata":{}', ('"metadata":' + $unknownMetadata)).Replace('"precise":"s:a"}}', ('"precise":"s:a"},"names":' + $unknownMetadata + ',"availability":null}'))
$unknownFields = Export-ProbeGraph -Name "unknown-metadata" -Text $unknownFieldsGraph -RawOnly
Assert-Probe ($unknownFields.Raw.Contains('"metadata":' + $unknownMetadata)) "complete raw graph metadata remains unchanged inside the projection"
Assert-Probe ($unknownFields.Raw.Contains('"names":' + $unknownMetadata)) "complete nested symbol fields retain __type, case-sensitive keys, escapes and numeric lexemes"
Assert-Probe ($unknownFields.Raw.Contains('"availability":null')) "explicit null availability stays present"
Assert-Probe ($unknownFields.Summary.DeclarationOccurrences -eq 1) "unknown fields do not suppress the declaration"

$collisionPath = Join-Path $OutputRoot "collision.json"
[System.IO.File]::WriteAllText($collisionPath, "sentinel", $script:ProbeUTF8)
$rejected = $false
try {
    [void][SwiftUIBaseline.Streaming.InventoryWriter]::Write(
        "synthetic-streaming-review-fixture", @((New-ProbeGraph $small.Path)),
        $collisionPath, 1024, 2, 1048576)
} catch { $rejected = $true }
Assert-Probe $rejected "existing output rejected"
Assert-Probe ([System.IO.File]::ReadAllText($collisionPath) -ceq "sentinel") "collision preserves existing evidence bytes"

# Test >Int32 run offsets/sequences without creating a multi-gigabyte file.
$entryType = [SwiftUIBaseline.Streaming.InventoryWriter].Assembly.GetType("SwiftUIBaseline.Streaming.IndexEntry", $true)
$entry = [Activator]::CreateInstance($entryType, $true)
$codecIdentifier = "s:" + [char]0xd800 + [char]9 + [char]0xe000
$codecOffset = [long]2147483648 + 12345
$codecSequence = [long]4294967296 + 9
$entryType.GetField("Identifier").SetValue($entry, $codecIdentifier)
$entryType.GetField("Offset").SetValue($entry, $codecOffset)
$entryType.GetField("Sequence").SetValue($entry, $codecSequence)
$memory = [System.IO.MemoryStream]::new()
$binaryWriter = [System.IO.BinaryWriter]::new($memory, [System.Text.Encoding]::UTF8, $true)
$binaryReader = $null
try {
    [void]$entryType.GetMethod("Write").Invoke($entry, [object[]]@($binaryWriter))
    $binaryWriter.Flush()
    $memory.Position = 0
    $binaryReader = [System.IO.BinaryReader]::new($memory, [System.Text.Encoding]::UTF8, $true)
    $decoded = $entryType.GetMethod("Read").Invoke($null, [object[]]@($binaryReader, [int]1048576))
    Assert-Probe ($decoded.Offset -eq $codecOffset) "64-bit run payload offset survives binary codec"
    Assert-Probe ($decoded.Sequence -eq $codecSequence) "64-bit run sequence survives binary codec"
    Assert-Probe ($decoded.Identifier -ceq $codecIdentifier) "UTF-16 code units including lone surrogate survive run codec"
    Assert-Probe ($entryType.GetField("Offset").FieldType -eq [long]) "offset field uses Int64"
    Assert-Probe ($entryType.GetField("Sequence").FieldType -eq [long]) "sequence field uses Int64"
} finally {
    if ($null -ne $binaryReader) { $binaryReader.Dispose() }
    $binaryWriter.Dispose()
    $memory.Dispose()
}

Assert-Probe (@(Get-ChildItem -LiteralPath $OutputRoot -Directory -Force -Filter ".swiftui-index-*").Count -eq 0) "no scratch directories survive success or failure"
Write-Host "Streaming inventory tests passed $script:ProbeAssertions assertions using synthetic fixtures only."
Write-Host "Stress: $($small.Summary.InitialSortRuns) initial runs; $($small.Summary.MergePasses) merge passes; $($small.Summary.PeakOpenRunReaders) concurrent run readers; $($small.Summary.LargestOccurrenceGroup) occurrences in the largest group."
Write-Host "Stress inventory SHA-256: $($small.Summary.InventorySha256)"
Write-Host "Artifacts: $OutputRoot"
