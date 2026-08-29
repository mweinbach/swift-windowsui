<#
.SYNOPSIS
Tests the first audit stage using small, explicitly synthetic captures only.
#>
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot
)
$ErrorActionPreference = "Stop"
. (Join-Path $RepositoryRoot "scripts/swiftui-api-audit-test-fixtures.ps1")
. (Join-Path $RepositoryRoot "scripts/swiftui-api-audit-common.ps1")
$builder = Join-Path $RepositoryRoot "scripts/build-swiftui-api-audit.ps1"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepositoryRoot ("artifacts/swiftui-api-audit-tests/" + [Guid]::NewGuid().ToString("N"))
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) { throw "Audit test output must be new." }
[void][System.IO.Directory]::CreateDirectory($OutputRoot)
$script:AuditAssertions = 0
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$manifestPath = Join-Path $RepositoryRoot "docs/swiftui-baseline.json"
$fixture = New-SwiftUIAuditTestCapture -Root (Join-Path $OutputRoot "capture") -ManifestPath $manifestPath
$context = Read-SwiftUIAuditCapture -CaptureRoot $fixture.Root -ManifestPath $manifestPath

function Assert-Audit {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw "Audit assertion failed: $Message" }
    $script:AuditAssertions++
}
function Read-SmallAuditText {
    param([string]$Path)
    if ((Get-Item -LiteralPath $Path).Length -gt 8MB) {
        throw "This object/string test helper accepts only small synthetic records, never a native inventory."
    }
    return [IO.File]::ReadAllText($Path, $utf8)
}
function Hash-AuditFile {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-AuditRows {
    param([string]$Path)
    $text = Read-SmallAuditText $Path
    return @($text -split "\r?\n" | Where-Object { $_.Length -ne 0 })
}
function Source-AuditFingerprint {
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $fixture.Root -File -Recurse) {
        $relative = Get-SwiftUIBaselineRelativePath -Root $fixture.Root -Path $file.FullName
        $entries.Add($relative + [char]9 + (Hash-AuditFile $file.FullName))
    }
    [string[]]$ordered = $entries.ToArray()
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    return Get-SwiftUIBaselineTextHash -Text ([string]::Join([string][char]10, $ordered))
}
$originalFiles = [System.Collections.Generic.Dictionary[string, byte[]]]::new([StringComparer]::Ordinal)
foreach ($file in Get-ChildItem -LiteralPath $fixture.Root -File -Recurse) {
    if ($file.Length -gt 8MB) { throw "The normal audit tests require small synthetic captures." }
    $originalFiles.Add($file.FullName, [IO.File]::ReadAllBytes($file.FullName))
}
function Restore-AuditSource {
    foreach ($path in $originalFiles.Keys) { [IO.File]::WriteAllBytes($path, $originalFiles[$path]) }
}
function Seal-AuditCapture {
    param($Value)
    Write-SwiftUIBaselineJson -Value $Value -Path $fixture.CapturePath
    [void](Update-SwiftUIAuditTestCaptureHashes -Root $fixture.Root -CaptureOnly)
}
function Assert-AuditRejected {
    param([string]$Name, [scriptblock]$Mutation, [string]$Pattern,
        [hashtable]$Arguments = @{})
    Restore-AuditSource
    & $Mutation
    $fingerprint = Source-AuditFingerprint
    $destination = Join-Path $OutputRoot ("rejected-" + $Name)
    $caught = $null
    try { & $builder -CaptureRoot $fixture.Root -OutputDirectory $destination -ManifestPath $manifestPath @Arguments | Out-Null }
    catch { $caught = $_ }
    Assert-Audit ($null -ne $caught) "$Name is rejected"
    Assert-Audit ($caught.Exception.Message -match $Pattern) "$Name has an actionable failure: $($caught.Exception.Message)"
    Assert-Audit (-not (Test-Path -LiteralPath $destination)) "$Name does not publish partial evidence"
    Assert-Audit (@(Get-ChildItem -LiteralPath $OutputRoot -Directory -Force -Filter ".swiftui-api-audit-*").Count -eq 0) "$Name removes only its owned staging"
    Assert-Audit ((Source-AuditFingerprint) -ceq $fingerprint) "$Name leaves source bytes unchanged"
}

foreach ($name in @("build-swiftui-api-audit.ps1", "swiftui-api-audit-common.ps1",
        "swiftui-api-audit-test-fixtures.ps1", "test-swiftui-api-audit.ps1",
        "test-swiftui-api-audit-capture.ps1", "test-swiftui-api-audit-memory.ps1")) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepositoryRoot "scripts/$name"),
        [ref]$tokens, [ref]$errors)
    Assert-Audit ($errors.Count -eq 0) "PowerShell parser accepts $name"
}

$fingerprint = Source-AuditFingerprint
$defaultPath = Join-Path $OutputRoot "all-queues"
$created = & $builder -CaptureRoot $fixture.Root -OutputDirectory $defaultPath -ManifestPath $manifestPath -SortChunkBytes 1024 -MergeFanIn 2
$audit = Read-SwiftUIAuditTestSmallJson (Join-Path $defaultPath "audit.json")
Assert-Audit ($audit.reviewStatus -ceq "unreviewed") "audit remains unreviewed"
Assert-Audit ($audit.counts.graphs -eq $fixture.Counts.graphs) "every graph partition is counted"
Assert-Audit ($audit.counts.preciseIdentifiers -eq $fixture.Counts.preciseSymbols) "every precise identity is counted"
Assert-Audit ($audit.counts.declarationOccurrences -eq $fixture.Counts.declarationOccurrences) "every symbol occurrence is counted"
Assert-Audit ($audit.counts.relationshipOccurrences -eq $fixture.Counts.relationshipOccurrences) "every relationship occurrence is counted"
Assert-Audit ($audit.counts.interfaceFiles -eq 4 -and $audit.counts.overlayFiles -eq 1) "all interfaces and overlays are retained"
Assert-Audit (-not $audit.authority.windowsMatchingPerformed -and -not $audit.authority.behaviorConformanceAssessed) "no matcher or conformance claim is fabricated"
Assert-Audit ($audit.sourceCapture.observedExtractorIdentity.swiftCompilerVersion -ceq "6.3.3") "extractor identity stays separate"
Assert-Audit (-not $audit.sourceCapture.exactIdentityPreviouslyReviewedAsReported) "candidate identity is not promoted"
Assert-Audit ($audit.sourceCapture.syntheticFixtureAsReported.kind -ceq "swiftui-api-audit-tests") "fixture provenance is visible without opening the original capture"
Assert-Audit ($audit.sourceCapture.inventorySha256 -ceq (Hash-AuditFile $fixture.InventoryPath)) "actual streamed inventory hash is recorded"
Assert-Audit ($audit.sourceCapture.graphSetSha256 -ceq $fixture.GraphSetSha256) "actual graph-set hash is recorded"
Assert-Audit ((Hash-AuditFile $created.manifestPath) -ceq $created.manifestSha256) "manifest result seals published bytes"
Assert-Audit ($created.publication.published -and $created.publication.attempts -ge 1 -and
    $created.publication.attempts -le 3 -and
    $created.publication.recovered -eq ($created.publication.attempts -gt 1)) "successful publication reports its bounded actual attempt count"
Assert-Audit (@($created.publication.failedAttemptDiagnostics).Count -eq ($created.publication.attempts - 1)) "successful publication retains every reported failed-attempt diagnostic"
Assert-Audit ((Read-SmallAuditText (Join-Path $defaultPath "audit.sha256")) -ceq ($created.manifestSha256 + "  audit.json" + [char]10)) "manifest sidecar seals published bytes"
Assert-Audit ((Source-AuditFingerprint) -ceq $fingerprint) "successful audit does not edit the source"

foreach ($file in $audit.recordFiles) {
    Assert-Audit ((Hash-AuditFile (Join-Path $defaultPath $file.path)) -ceq $file.sha256) "$($file.path) bytes match their manifest"
    foreach ($row in Read-AuditRows (Join-Path $defaultPath $file.path)) {
        Assert-Audit ($row.StartsWith('{"reviewStatus":"unreviewed",', [StringComparison]::Ordinal)) "$($file.path) records are individually unreviewed"
    }
}
foreach ($file in $audit.sourceMetadataFiles) {
    Assert-Audit ((Hash-AuditFile (Join-Path $defaultPath $file.path)) -ceq $file.sha256) "copied authoritative metadata matches $($file.path)"
}
Assert-Audit ((Hash-AuditFile (Join-Path $defaultPath "source-metadata/capture.json")) -ceq (Hash-AuditFile $fixture.CapturePath)) "capture metadata is copied byte-for-byte"
$identities = @(Read-AuditRows (Join-Path $defaultPath "identities.ndjson") | ForEach-Object { $_ | ConvertFrom-Json })
$identityById = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($identity in $identities) { $identityById.Add($identity.preciseIdentifier, $identity) }
Assert-Audit ($identities.Count -eq $fixture.Counts.preciseSymbols) "one row per identity"
Assert-Audit ($identityById.ContainsKey($fixture.SymbolIds.Lowercase) -and $identityById.ContainsKey($fixture.SymbolIds.Uppercase)) "identity case is significant"
Assert-Audit ($identityById[$fixture.SymbolIds.Shared].occurrenceCount -gt 2) "same-graph duplicates and re-exports remain occurrences"
Assert-Audit ($identityById.ContainsKey($fixture.SymbolIds.Macro) -and $identityById.ContainsKey($fixture.SymbolIds.PublicUnderscore)) "macros and public underscore names are never filtered"
Assert-Audit ($identityById.ContainsKey($fixture.SymbolIds.Synthesized)) "synthesized identities remain distinct records"
Assert-Audit ($identityById.ContainsKey($fixture.SymbolIds.IntOverload) -and $identityById.ContainsKey($fixture.SymbolIds.StringOverload)) "same-owner typed overloads keep separate identities"

$occurrences = Read-SmallAuditText (Join-Path $defaultPath "occurrences.ndjson")
foreach ($fragment in @('"functionSignature":', '"availability":null', '"availability":[]',
        '"__type":null', '"CaseKey":9e+42', '"caseKey":-0.00e+99',
        '"largeInteger":9007199254740993', '"fraction":1.2300',
        '"AuditMixin":{"retained":true}', '"auditMixin":{"retained":false}')) {
    Assert-Audit ($occurrences.Contains($fragment)) "raw occurrence retains $fragment"
}
$relationships = Read-SmallAuditText (Join-Path $defaultPath "relationships.ndjson")
Assert-Audit ($relationships.Contains('"swiftConstraints":') -and $relationships.Contains('"targetFallback":')) "conditional relationship and external endpoint metadata remain raw"
Assert-Audit ($relationships.Contains('"defaultImplementationOf"')) "default implementation edges are retained without inferring a matching witness"
$synthesizedRows = @(Read-AuditRows (Join-Path $defaultPath "occurrences.ndjson") | Where-Object { $_.Contains($fixture.SymbolIds.Synthesized) })
Assert-Audit ($synthesizedRows.Count -eq 2 -and $synthesizedRows[0].Contains('"domain":"macOS","isUnconditionallyUnavailable":true')) "availability does not silently filter a native record"
$interfaceFacts = Read-SmallAuditText (Join-Path $defaultPath "interface-facts.ndjson")
Assert-Audit ($interfaceFacts.Contains("6.3.2") -and $interfaceFacts.Contains("-swift-version 5")) "interface producer compiler/language headers remain distinct from extraction"
Assert-Audit ($interfaceFacts.Contains("#if") -and $interfaceFacts.Contains("@_exported import")) "conditional imports are retained without pretending to parse them"
$queues = @(Read-AuditRows (Join-Path $defaultPath "candidate-queues.ndjson") | ForEach-Object { $_ | ConvertFrom-Json })
Assert-Audit ($queues.Count -eq 5) "five lexical family queues are emitted"
foreach ($queue in $queues) { Assert-Audit ($queue.selection -ceq "lexical-candidate-only") "queue is not a mapping or applicability decision" }

$filteredPath = Join-Path $OutputRoot "image-queue"
$filtered = & $builder -CaptureRoot $fixture.Root -OutputDirectory $filteredPath -ManifestPath $manifestPath -QueueFamily image-resizing -SortChunkBytes 4096 -MergeFanIn 4
Assert-Audit ($filtered.counts.preciseIdentifiers -eq $fixture.Counts.preciseSymbols -and $filtered.counts.declarationOccurrences -eq $fixture.Counts.declarationOccurrences) "work-queue filters cannot shrink the ledger"
foreach ($file in $audit.recordFiles | Where-Object path -CNE "candidate-queues.ndjson") {
    Assert-Audit ((Hash-AuditFile (Join-Path $filteredPath $file.path)) -ceq $file.sha256) "queue and sort budgets do not change $($file.path)"
}
$filteredQueues = @(Read-AuditRows (Join-Path $filteredPath "candidate-queues.ndjson") | ForEach-Object { $_ | ConvertFrom-Json })
Assert-Audit ($filteredQueues.Count -eq 1 -and $filteredQueues[0].family -ceq "image-resizing") "queue filtering changes only candidate selection"

Assert-AuditRejected "failed-capture" {
    $value = Read-SwiftUIAuditTestSmallJson $fixture.StatusPath
    $value.status = "failed"; Write-SwiftUIBaselineJson $value $fixture.StatusPath
} 'successful matching candidate'
Assert-AuditRejected "original-failed-schema" {
    Write-SwiftUIBaselineJson -Value ([ordered]@{ baselineId = $context.baselineManifest.baselineId; status = "failed"; behaviorConformance = "not-verified" }) -Path $fixture.StatusPath
} 'failed captures remain ineligible'
Assert-AuditRejected "capture-seal" {
    [IO.File]::AppendAllText($fixture.CapturePath, " ", $utf8)
} 'manifest SHA-256 mismatch'
Assert-AuditRejected "inventory-stale-hash" {
    [IO.File]::AppendAllText($fixture.InventoryPath, " ", $utf8)
} 'Inventory SHA-256'
Assert-AuditRejected "raw-graph-stale-hash" {
    [IO.File]::AppendAllText($context.graphInputs[0].path, " ", $utf8)
} 'counts/graphSetSha256'
Assert-AuditRejected "missing-target-primary" {
    [IO.File]::Delete(($context.graphInputs | Where-Object { $_.primary -and $_.target.StartsWith("x86_64") } | Select-Object -First 1).path)
} 'Missing primary symbol graph'
Assert-AuditRejected "wrong-sdk" {
    $value = Read-SwiftUIAuditTestSmallJson $fixture.CapturePath
    $value.observedIdentity.sdkVersion = "26.4"; $value.sdk.version = "26.4"
    Seal-AuditCapture $value
} 'Wrong sdkVersion'
Assert-AuditRejected "false-qualification" {
    $value = Read-SwiftUIAuditTestSmallJson $fixture.CapturePath
    $value.qualification.publicAPIAuditComplete = $true
    Seal-AuditCapture $value
} 'cannot claim qualification'
Assert-AuditRejected "stale-counts" {
    $value = Read-SwiftUIAuditTestSmallJson $fixture.CapturePath
    $value.inventory.counts.declarationOccurrences--
    Seal-AuditCapture $value
} 'counts/graphSetSha256'
Assert-AuditRejected "duplicate-inventory-id" {
    $text = Read-SmallAuditText $fixture.InventoryPath
    $groups = [regex]::Matches($text, '\{"preciseIdentifier":"(?<id>[^"]+)","occurrences":\[')
    $second = $groups[1].Groups["id"]
    $text = $text.Remove($second.Index, $second.Length).Insert($second.Index, $groups[0].Groups["id"].Value)
    [IO.File]::WriteAllText($fixture.InventoryPath, $text, $utf8)
    [void](Update-SwiftUIAuditTestCaptureHashes -Root $fixture.Root)
} 'precise identifiers'
Assert-AuditRejected "duplicate-inventory-occurrence" {
    $text = Read-SmallAuditText $fixture.InventoryPath
    $match = [regex]::Match($text, '"symbolIndex":(?<index>[0-9]+)')
    $index = $match.Groups["index"]
    $text = $text.Remove($index.Index, $index.Length).Insert($index.Index, "999999")
    [IO.File]::WriteAllText($fixture.InventoryPath, $text, $utf8)
    [void](Update-SwiftUIAuditTestCaptureHashes -Root $fixture.Root)
} 'occurrence identity/path/index'
Assert-AuditRejected "changed-relationship-projection" {
    $text = Read-SmallAuditText $fixture.InventoryPath
    $text = [regex]::new('"relationshipIndex":0').Replace($text, '"relationshipIndex":999999', 1)
    [IO.File]::WriteAllText($fixture.InventoryPath, $text, $utf8)
    [void](Update-SwiftUIAuditTestCaptureHashes -Root $fixture.Root)
} 'raw relationship'
Assert-AuditRejected "changed-symbol-projection" {
    $text = Read-SmallAuditText $fixture.InventoryPath
    $text = [regex]::new('"title":"FixtureView"').Replace($text, '"title":"ChangedFixtureView"', 1)
    [IO.File]::WriteAllText($fixture.InventoryPath, $text, $utf8)
    [void](Update-SwiftUIAuditTestCaptureHashes -Root $fixture.Root)
} 'raw symbol projection'
Assert-AuditRejected "nested-projection-order" {
    $text = Read-SmallAuditText $fixture.InventoryPath
    $text = $text.Replace('"kind":{"identifier":"swift.struct","displayName":"Structure"}',
        '"kind":{"displayName":"Structure","identifier":"swift.struct"}')
    [IO.File]::WriteAllText($fixture.InventoryPath, $text, $utf8)
    [void](Update-SwiftUIAuditTestCaptureHashes -Root $fixture.Root)
} 'raw symbol projection'
Assert-AuditRejected "inventory-false-conformance" {
    $text = (Read-SmallAuditText $fixture.InventoryPath).Replace('"behaviorConformance":"not-verified"', '"behaviorConformance":"verified"')
    [IO.File]::WriteAllText($fixture.InventoryPath, $text, $utf8)
    [void](Update-SwiftUIAuditTestCaptureHashes -Root $fixture.Root)
} 'baseline/schema/provenance'
Assert-AuditRejected "record-budget" {} 'MaximumRecordCharacters' @{ MaximumRecordCharacters = 1024 }
Assert-AuditRejected "invalid-graph-utf8" {
    $bytes = [IO.File]::ReadAllBytes($context.graphInputs[0].path)
    [IO.File]::WriteAllBytes($context.graphInputs[0].path, ([byte[]]@(0xff) + $bytes))
} 'Unable to translate|UTF-8|invalid'
Assert-AuditRejected "invalid-interface-utf8" {
    [IO.File]::WriteAllBytes($context.publicInterfaces[0].path, [byte[]]@(0xff, 0x0a))
    [void](Update-SwiftUIAuditTestCaptureHashes -Root $fixture.Root)
} 'Unable to translate|UTF-8|invalid'
Assert-AuditRejected "metadata-budget" {} 'MaximumMetadataBytes' @{ MaximumMetadataBytes = 1024 }
Assert-AuditRejected "interface-line-budget" {
    [IO.File]::AppendAllText($context.publicInterfaces[0].path, [string]::new([char]"x", 4096), $utf8)
    [void](Update-SwiftUIAuditTestCaptureHashes -Root $fixture.Root)
} 'line exceeds MaximumRecordCharacters' @{ MaximumRecordCharacters = 2048 }

Restore-AuditSource
$existingHash = Hash-AuditFile (Join-Path $defaultPath "audit.json")
$caught = $null
try { & $builder -CaptureRoot $fixture.Root -OutputDirectory $defaultPath | Out-Null } catch { $caught = $_ }
Assert-Audit ($null -ne $caught -and $caught.Exception.Message -match "never overwritten") "existing output is immutable"
Assert-Audit ((Hash-AuditFile (Join-Path $defaultPath "audit.json")) -ceq $existingHash) "immutable output preserves previous evidence"
$caught = $null
try { & $builder -CaptureRoot $fixture.Root -OutputDirectory (Join-Path $fixture.Root "inside") | Out-Null } catch { $caught = $_ }
Assert-Audit ($null -ne $caught -and $caught.Exception.Message -match "outside the read-only source") "output cannot enter the source"
Assert-Audit (-not (Test-Path -LiteralPath (Join-Path $fixture.Root "inside"))) "source containment guard runs before output creation"
Assert-Audit ((Source-AuditFingerprint) -ceq $fingerprint) "all source bytes are restored and preserved"

$report = [ordered]@{
    schemaVersion = 1
    evidenceKind = "synthetic-api-audit-tooling-tests-only"
    assertions = $script:AuditAssertions
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    outputRoot = $OutputRoot
    fixtureCounts = $fixture.Counts
    publicationResults = @($created.publication, $filtered.publication)
    nativeExportPerformed = $false
    behaviorConformanceAssessed = $false
}
Write-SwiftUIBaselineJson -Value $report -Path (Join-Path $OutputRoot "test-results.json")
Write-Host "API audit ledger tests passed $($script:AuditAssertions) assertions using synthetic captures only."
Write-Host "Evidence: $OutputRoot"
