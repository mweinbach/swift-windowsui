<#
.SYNOPSIS
Tests exact-identifier review packets using owned synthetic captures only.
.DESCRIPTION
Git reads committed blobs from this repository without changing its index,
refs or working files. No native SDK capture, Swift compiler, SwiftPM, or
behavior assessment runs. All mutation/resealing helpers are fixture-only.
#>
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepositoryRoot 'scripts/swiftui-api-audit-test-fixtures.ps1')
. (Join-Path $RepositoryRoot 'scripts/swiftui-api-audit-common.ps1')
$RepositoryRoot = Resolve-SwiftUIBaselineFileSystemPath -Path $RepositoryRoot
$selector = Join-Path $RepositoryRoot 'scripts/select-swiftui-api-review-unit.ps1'
$ledgerBuilder = Join-Path $RepositoryRoot 'scripts/build-swiftui-api-audit.ps1'
$baselinePath = Join-Path $RepositoryRoot 'docs/swiftui-baseline.json'
if (-not (Test-Path -LiteralPath $selector -PathType Leaf)) {
    throw 'The review-unit selector must be present before running its synthetic tests.'
}
foreach ($name in @('GIT_DIR', 'GIT_COMMON_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE',
        'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_SHALLOW_FILE',
        'GIT_CONFIG', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS')) {
    if ($null -ne [Environment]::GetEnvironmentVariable($name, 'Process')) {
        throw "Review-unit tests refuse repository/config redirection through $name; no environment values are printed or changed."
    }
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepositoryRoot ('artifacts/swiftui-api-review-unit-tests/' + [Guid]::NewGuid().ToString('N'))
}
$OutputRoot = Resolve-SwiftUIAuditTestRoot -Root $OutputRoot
if (Test-Path -LiteralPath $OutputRoot) { throw 'Review-unit test output must be new and owned.' }
[void][IO.Directory]::CreateDirectory($OutputRoot)
$utf8 = [Text.UTF8Encoding]::new($false, $true)
[IO.File]::WriteAllText((Join-Path $OutputRoot 'SYNTHETIC-REVIEW-UNIT-TESTS.txt'),
    "SYNTHETIC review-unit tooling tests only. No native capture or conformance evidence.`n", $utf8)
$script:ReviewAssertions = 0

function Assert-ReviewUnitTest {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw "Review-unit assertion failed: $Message" }
    $script:ReviewAssertions++
}

function Read-ReviewUnitSmallText {
    param([string]$Path)
    if ((Get-Item -LiteralPath $Path).Length -gt 8MB) {
        throw 'This test helper accepts only small owned synthetic files, never native graphs or inventories.'
    }
    return [IO.File]::ReadAllText($Path, $utf8)
}

function Get-ReviewUnitFileHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-ReviewUnitRows {
    param([string]$Path)
    $text = Read-ReviewUnitSmallText $Path
    return ,@($text -split "`r?`n" | Where-Object { $_.Length -ne 0 })
}

function Write-ReviewUnitRows {
    param([string]$Path, [AllowEmptyCollection()][string[]]$Rows)
    [void](Get-SwiftUIBaselineRelativePath -Root $auditRoot -Path $Path)
    $text = ''
    if ($Rows.Count -ne 0) { $text = [string]::Join("`n", $Rows) + "`n" }
    [IO.File]::WriteAllText($Path, $text, $utf8)
}

function Get-ReviewInputFingerprint {
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($root in @($fixture.Root, $auditRoot)) {
        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File) {
            $relative = Get-SwiftUIBaselineRelativePath -Root $OutputRoot -Path $file.FullName
            $entries.Add($relative + [char]9 + (Get-ReviewUnitFileHash $file.FullName))
        }
    }
    [string[]]$ordered = $entries.ToArray()
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    return Get-SwiftUIBaselineTextHash -Text ([string]::Join("`n", $ordered))
}

function Restore-ReviewInputs {
    foreach ($path in $originalInputs.Keys) {
        [void](Get-SwiftUIBaselineRelativePath -Root $OutputRoot -Path $path)
        [IO.File]::WriteAllBytes($path, $originalInputs[$path])
    }
}

function Seal-SyntheticReviewLedger {
    param([switch]$ManifestOnly)
    if (-not (Test-Path -LiteralPath (Join-Path $OutputRoot 'SYNTHETIC-REVIEW-UNIT-TESTS.txt')) -or
        -not (Test-Path -LiteralPath (Join-Path $fixture.Root 'SYNTHETIC-FIXTURE.txt'))) {
        throw 'Resealing is restricted to owned synthetic review-unit tests.'
    }
    $manifestPath = Join-Path $auditRoot 'audit.json'
    $manifest = Read-SwiftUIAuditTestSmallJson $manifestPath
    if ($manifest.sourceCapture.syntheticFixtureAsReported.kind -cne 'swiftui-api-audit-tests') {
        throw 'Never reseal a native ledger with a synthetic mutation helper.'
    }
    if (-not $ManifestOnly) {
        foreach ($record in @($manifest.recordFiles) + @($manifest.sourceMetadataFiles)) {
            $path = Get-SwiftUIAuditTestFilePath -Root $auditRoot -RelativePath $record.path
            $record.sha256 = Get-ReviewUnitFileHash $path
            $record.bytes = (Get-Item -LiteralPath $path).Length
        }
        Write-SwiftUIBaselineJson -Value $manifest -Path $manifestPath
    }
    $hash = Get-ReviewUnitFileHash $manifestPath
    [IO.File]::WriteAllText((Join-Path $auditRoot 'audit.sha256'), "$hash  audit.json`n", $utf8)
}

function Get-ReviewOccurrenceIdentifier {
    param([string]$Row)
    # Only reads the fixed wrapper of a small synthetic NDJSON row. The symbol
    # value is never parsed by PowerShell: its case-distinct mixins stay raw.
    $match = [regex]::Match($Row, '"preciseIdentifier":(?<id>"(?:\\.|[^"\\])*")\s*,\s*"symbol":')
    if (-not $match.Success) { throw 'Synthetic occurrence wrapper has no precise identifier.' }
    return ($match.Groups['id'].Value | ConvertFrom-Json)
}

function Get-ReviewExpectedOccurrences {
    param([string]$Identifier)
    return ,@($sourceRows['occurrences.ndjson'] | Where-Object {
        (Get-ReviewOccurrenceIdentifier $_) -ceq $Identifier
    })
}

function Get-ReviewExpectedRelationships {
    param([string]$Identifier)
    return ,@($sourceRows['relationships.ndjson'] | Where-Object {
        # The existing relationship fixture has no case-duplicate JSON keys;
        # retain its original row for byte comparisons after endpoint lookup.
        $relationship = ($_ | ConvertFrom-Json).relationship
        $relationship.source -ceq $Identifier -or $relationship.target -ceq $Identifier
    })
}

function New-ReviewUnitArguments {
    param([string]$Identifier, [string]$Destination)
    return @{
        CaptureRoot = $fixture.Root
        AuditRoot = $auditRoot
        PreciseIdentifier = $Identifier
        WindowsRepositoryRoot = $RepositoryRoot
        WindowsCommit = $windowsCommit
        WindowsSourcePath = $windowsSourcePaths
        OutputDirectory = $Destination
        ManifestPath = $baselinePath
        SortChunkBytes = 1024
        MergeFanIn = 2
    }
}

function Assert-ReviewRejected {
    param([string]$Name, [scriptblock]$Mutation = {}, [string]$Pattern = '.',
        [hashtable]$Overrides = @{})
    Restore-ReviewInputs
    & $Mutation
    $fingerprint = Get-ReviewInputFingerprint
    $destination = Join-Path $OutputRoot ('rejected-' + $Name)
    $arguments = New-ReviewUnitArguments -Identifier $fixture.SymbolIds.Shared -Destination $destination
    foreach ($key in $Overrides.Keys) { $arguments[$key] = $Overrides[$key] }
    $caught = $null
    try { & $selector @arguments | Out-Null } catch { $caught = $_ }
    Assert-ReviewUnitTest ($null -ne $caught) "$Name is rejected"
    Assert-ReviewUnitTest ($caught.Exception.Message -match $Pattern) "$Name reports its failed contract: $($caught.Exception.Message)"
    Assert-ReviewUnitTest (-not (Test-Path -LiteralPath $arguments.OutputDirectory)) "$Name publishes no partial review unit"
    Assert-ReviewUnitTest (@(Get-ChildItem -LiteralPath $OutputRoot -Directory -Force -Filter '.swiftui-api-review-*').Count -eq 0) "$Name removes its owned staging directory"
    Assert-ReviewUnitTest ((Get-ReviewInputFingerprint) -ceq $fingerprint) "$Name does not change capture or ledger bytes"
}

function Assert-ReviewPublishedUnit {
    param($Result, [string]$Identifier)
    Assert-ReviewUnitTest ($Result -is [System.Management.Automation.PSCustomObject]) 'selector returns one compact descriptor'
    Assert-ReviewUnitTest ($Result.reviewStatus -ceq 'unreviewed') 'returned review status remains unreviewed'
    $unit = Read-SwiftUIAuditTestSmallJson $Result.manifestPath
    Assert-ReviewUnitTest ($unit.schemaVersion -eq 1 -and $unit.evidenceKind -ceq 'unreviewed-api-review-unit') 'review-unit schema and evidence kind'
    Assert-ReviewUnitTest ($unit.status -ceq 'awaiting-declaration-source-and-behavior-review' -and $unit.reviewStatus -ceq 'unreviewed') 'packet creation makes no review decision'
    Assert-ReviewUnitTest ($unit.sourceCapture.syntheticFixtureAsReported.kind -ceq 'swiftui-api-audit-tests') 'synthetic provenance is visible in the packet'
    Assert-ReviewUnitTest ($unit.sourceAudit.reviewStatus -ceq 'unreviewed') 'source ledger review status is unchanged'
    foreach ($name in @('swiftSourceParsingPerformed', 'windowsDeclarationMatchingPerformed',
            'compilationPerformed', 'behaviorConformanceAssessed', 'identityReviewPerformed')) {
        Assert-ReviewUnitTest ($unit.verification.$name -is [bool] -and -not $unit.verification.$name) "packet does not claim $name"
    }
    Assert-ReviewUnitTest ($Result.manifestPath -ceq (Join-Path $Result.path 'review-unit.json')) 'descriptor identifies the published manifest'
    Assert-ReviewUnitTest ($Result.manifestSha256 -ceq (Get-ReviewUnitFileHash $Result.manifestPath)) 'descriptor digest seals actual manifest bytes'
    Assert-ReviewUnitTest ((Read-ReviewUnitSmallText (Join-Path $Result.path 'review-unit.sha256')) -ceq ($Result.manifestSha256 + "  review-unit.json`n")) 'manifest sidecar seals published bytes'

    $expectedIdentity = @($sourceRows['identities.ndjson'] | Where-Object {
        ($_ | ConvertFrom-Json).preciseIdentifier -ceq $Identifier
    })
    $expectedOccurrences = Get-ReviewExpectedOccurrences $Identifier
    $expectedRelationships = Get-ReviewExpectedRelationships $Identifier
    Assert-ReviewUnitTest ($expectedIdentity.Count -eq 1) 'synthetic source has one exact identity row'
    Assert-ReviewUnitTest ($unit.selection.preciseIdentifier -ceq $Identifier -and $unit.selection.comparison -ceq 'ordinal-exact') 'selection uses the exact ordinal identifier'
    Assert-ReviewUnitTest ($unit.selection.declarationOccurrences -eq $expectedOccurrences.Count) 'selection counts every occurrence'
    Assert-ReviewUnitTest ($unit.selection.incidentRelationships -eq $expectedRelationships.Count) 'selection counts all source/target incident relationships'
    Assert-ReviewUnitTest ($unit.counts.selected.preciseIdentifiers -eq 1 -and
        $unit.counts.selected.declarationOccurrences -eq $expectedOccurrences.Count -and
        $unit.counts.selected.relationshipOccurrences -eq $expectedRelationships.Count) 'selected counts do not replace complete ledger counts'
    Assert-SwiftUIAuditJsonEqual $unit.counts.nativeLedger $sourceAudit.counts 'complete native ledger counts in review packet'
    Assert-ReviewUnitTest $true 'complete source ledger counts remain available'

    foreach ($item in @(
            @{ name = 'native/identity.ndjson'; rows = $expectedIdentity },
            @{ name = 'native/occurrences.ndjson'; rows = $expectedOccurrences },
            @{ name = 'native/relationships.ndjson'; rows = $expectedRelationships })) {
        $expectedText = ''
        if ($item.rows.Count -ne 0) { $expectedText = [string]::Join("`n", [string[]]$item.rows) + "`n" }
        Assert-ReviewUnitTest ((Read-ReviewUnitSmallText (Join-Path $Result.path $item.name)) -ceq $expectedText) "$($item.name) retains the complete original selected rows"
    }
    $expectedRecordPaths = @('native/identity.ndjson', 'native/occurrences.ndjson', 'native/relationships.ndjson')
    foreach ($name in @('graph-fields.ndjson', 'partitions.ndjson', 'inventory-facts.ndjson',
            'interface-facts.ndjson', 'overlay-facts.ndjson', 'candidate-queues.ndjson')) {
        $relative = 'context/' + $name
        $expectedRecordPaths += $relative
        Assert-ReviewUnitTest ((Get-ReviewUnitFileHash (Join-Path $Result.path $relative)) -ceq
            (Get-ReviewUnitFileHash (Join-Path $auditRoot $name))) "$name context remains complete and byte-identical"
    }
    $recordPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in $unit.recordFiles) {
        Assert-ReviewUnitTest ($recordPaths.Add($record.path)) 'packet record paths are unique'
        $path = Get-SwiftUIAuditTestFilePath -Root $Result.path -RelativePath $record.path
        Assert-ReviewUnitTest ((Get-ReviewUnitFileHash $path) -ceq $record.sha256 -and
            (Get-Item -LiteralPath $path).Length -eq $record.bytes) "$($record.path) matches its manifest digest/size"
    }
    Assert-ReviewUnitTest ($recordPaths.Count -eq $expectedRecordPaths.Count) 'packet declares all nine record files'
    foreach ($path in $expectedRecordPaths) {
        Assert-ReviewUnitTest ($recordPaths.Contains($path)) "$path is part of the sealed packet manifest"
    }

    $metadataPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in $unit.sourceMetadataFiles) {
        Assert-ReviewUnitTest ($metadataPaths.Add($record.path)) 'metadata paths are unique'
        $path = Get-SwiftUIAuditTestFilePath -Root $Result.path -RelativePath $record.path
        Assert-ReviewUnitTest ((Get-ReviewUnitFileHash $path) -ceq $record.sha256 -and
            (Get-Item -LiteralPath $path).Length -eq $record.bytes) "$($record.path) matches its sealed metadata bytes"
    }
    foreach ($record in $sourceAudit.sourceMetadataFiles) {
        $path = 'context/' + $record.path
        Assert-ReviewUnitTest ($metadataPaths.Contains($path) -and
            (Get-ReviewUnitFileHash (Join-Path $Result.path $path)) -ceq $record.sha256) "complete source metadata is retained: $path"
    }
    foreach ($item in @(
            @{ relative = 'context/audit.json'; source = Join-Path $auditRoot 'audit.json' },
            @{ relative = 'context/audit.sha256'; source = Join-Path $auditRoot 'audit.sha256' },
            @{ relative = 'context/current-expected-baseline-manifest.json'; source = $baselinePath })) {
        Assert-ReviewUnitTest ($metadataPaths.Contains($item.relative) -and
            (Get-ReviewUnitFileHash (Join-Path $Result.path $item.relative)) -ceq
            (Get-ReviewUnitFileHash $item.source)) "$($item.relative) retains authoritative provenance bytes"
    }

    Assert-ReviewUnitTest ($unit.windowsSource.commit -ceq $windowsCommit) 'Windows source is pinned to the requested full commit'
    Assert-ReviewUnitTest (@($unit.windowsSource.files).Count -eq $windowsSourcePaths.Count) 'every requested source blob is recorded'
    $sourcePaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($file in $unit.windowsSource.files) {
        Assert-ReviewUnitTest ($sourcePaths.Add($file.path) -and $expectedBlobIds.ContainsKey($file.path)) 'source blob path is exact and unique'
        Assert-ReviewUnitTest ($file.blobOid -ceq $expectedBlobIds[$file.path]) 'recorded blob ID belongs to the pinned commit'
        Assert-ReviewUnitTest ($file.copiedPath -ceq ('windows-source/' + $file.path)) 'copied source keeps its repository-relative path'
        $path = Get-SwiftUIAuditTestFilePath -Root $Result.path -RelativePath $file.copiedPath
        Assert-ReviewUnitTest ((Get-ReviewUnitFileHash $path) -ceq $file.sha256 -and
            (Get-Item -LiteralPath $path).Length -eq $file.bytes) 'copied source bytes match packet provenance'
        $blobId = @(& git -c core.fsmonitor=false -C $RepositoryRoot hash-object --no-filters -- $path)
        Assert-ReviewUnitTest ($LASTEXITCODE -eq 0 -and $blobId.Count -eq 1 -and
            $blobId[0] -ceq $expectedBlobIds[$file.path]) 'source copy contains exact committed blob bytes without worktree filters'
    }
    $claims = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($claim in $unit.claims) {
        Assert-ReviewUnitTest ($claims.Add($claim.claimId)) 'claim IDs are distinct'
        Assert-ReviewUnitTest ($claim.kind -ceq $claim.claimId -and $claim.status -ceq 'unverified') 'each declaration/source/behavior claim remains independently unverified'
        Assert-ReviewUnitTest ($claim.evidenceRefs -is [array] -and $claim.evidenceRefs.Count -eq 0) 'new claims contain no invented evidence references'
    }
    Assert-ReviewUnitTest ($claims.Count -eq 3 -and $claims.Contains('declaration') -and
        $claims.Contains('source-compatibility') -and $claims.Contains('behavior')) 'all three required claim kinds are present'
    Assert-ReviewUnitTest ($unit.evidenceReferences -is [array] -and $unit.evidenceReferences.Count -eq 0) 'first review unit has an empty evidence-reference collection'
    Assert-ReviewUnitTest ((Get-ReviewInputFingerprint) -ceq $initialFingerprint) 'successful selection leaves all capture and ledger bytes unchanged'
    return $unit
}

$commitOutput = @(& git -c core.fsmonitor=false -C $RepositoryRoot rev-parse --verify 'HEAD^{commit}')
if ($LASTEXITCODE -ne 0 -or $commitOutput.Count -ne 1 -or $commitOutput[0] -cnotmatch '^[0-9a-f]{40}$') {
    throw 'Cannot bind the source fixture to one actual committed repository revision.'
}
$windowsCommit = $commitOutput[0]
$windowsSourcePaths = @('docs/swiftui-baseline.json', 'Sources/WinSwiftUI/Core.swift')
$expectedBlobIds = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
foreach ($path in $windowsSourcePaths) {
    $objectId = @(& git -c core.fsmonitor=false -C $RepositoryRoot rev-parse --verify "${windowsCommit}:$path")
    if ($LASTEXITCODE -ne 0 -or $objectId.Count -ne 1 -or $objectId[0] -cnotmatch '^[0-9a-f]{40}$') {
        throw "Committed source fixture is missing: $path"
    }
    $expectedBlobIds.Add($path, $objectId[0])
}
# This remains a small synthetic fixture (roughly MiB-sized files), but its
# repeated identity spans many 1 KiB index runs and must not be gathered or lost.
$fixture = New-SwiftUIAuditTestCapture -Root (Join-Path $OutputRoot 'capture') -ManifestPath $baselinePath `
    -RepeatedSymbols 128 -SymbolPayloadCharacters 4096
$auditRoot = Join-Path $OutputRoot 'audit'
$auditSummary = & $ledgerBuilder -CaptureRoot $fixture.Root -OutputDirectory $auditRoot `
    -ManifestPath $baselinePath -SortChunkBytes 1024 -MergeFanIn 2
$sourceAudit = Read-SwiftUIAuditTestSmallJson $auditSummary.manifestPath
$originalInputs = [System.Collections.Generic.Dictionary[string, byte[]]]::new([StringComparer]::Ordinal)
foreach ($root in @($fixture.Root, $auditRoot)) {
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File) {
        if ($file.Length -gt 8MB) { throw 'Review-unit mutation tests require small synthetic inputs.' }
        $originalInputs.Add($file.FullName, [IO.File]::ReadAllBytes($file.FullName))
    }
}
$sourceRows = [System.Collections.Generic.Dictionary[string, string[]]]::new([StringComparer]::Ordinal)
foreach ($record in $sourceAudit.recordFiles) {
    $sourceRows.Add($record.path, (Read-ReviewUnitRows (Join-Path $auditRoot $record.path)))
}
$initialFingerprint = Get-ReviewInputFingerprint

foreach ($path in @($selector, $PSCommandPath)) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Assert-ReviewUnitTest ($errors.Count -eq 0) "PowerShell syntax is valid: $([IO.Path]::GetFileName($path))"
}

$units = @{}
foreach ($selection in @(
        @{ name = 'shared'; id = $fixture.SymbolIds.Shared },
        @{ name = 'case-lower'; id = $fixture.SymbolIds.Lowercase },
        @{ name = 'case-upper'; id = $fixture.SymbolIds.Uppercase },
        @{ name = 'typed-overload'; id = $fixture.SymbolIds.StringOverload },
        @{ name = 'requirement-default'; id = $fixture.SymbolIds.IntOverload },
        @{ name = 'repeated-group'; id = $fixture.SymbolIds.Repeated },
        @{ name = 'synthesized'; id = $fixture.SymbolIds.Synthesized },
        @{ name = 'macro'; id = $fixture.SymbolIds.Macro },
        @{ name = 'public-underscore'; id = $fixture.SymbolIds.PublicUnderscore })) {
    $destination = Join-Path $OutputRoot ('unit-' + $selection.name)
    $arguments = New-ReviewUnitArguments -Identifier $selection.id -Destination $destination
    $created = & $selector @arguments
    [void](Assert-ReviewPublishedUnit -Result $created -Identifier $selection.id)
    $units[$selection.name] = $created
}
$sharedRows = Read-ReviewUnitRows (Join-Path $units['shared'].path 'native/occurrences.ndjson')
$sharedGraphs = @($sharedRows | ForEach-Object { ($_ | ConvertFrom-Json).graphPath } | Select-Object -Unique)
Assert-ReviewUnitTest ($sharedRows.Count -gt $sharedGraphs.Count -and $sharedGraphs.Count -eq 4) 'same-graph duplicates and both target/re-export pairs remain occurrences'
$availability = @{ missing = 0; nullValue = 0; empty = 0 }
foreach ($row in $sharedRows) {
    $symbol = ($row | ConvertFrom-Json).symbol
    $field = $symbol.PSObject.Properties['availability']
    if ($null -eq $field) { $availability.missing++ }
    elseif ($null -eq $field.Value) { $availability.nullValue++ }
    elseif ($field.Value -is [array] -and $field.Value.Count -eq 0) { $availability.empty++ }
}
Assert-ReviewUnitTest ($availability.missing -eq 2 -and $availability.nullValue -eq 2 -and $availability.empty -eq 2) 'absent, null, and empty availability remain distinct'
$typedRows = Read-ReviewUnitSmallText (Join-Path $units['typed-overload'].path 'native/occurrences.ndjson')
foreach ($raw in @('"functionSignature":', '"__type":null', '"CaseKey":9e+42', '"caseKey":-0.00e+99',
        '"largeInteger":9007199254740993', '"fraction":1.2300',
        '"AuditMixin":{"retained":true}', '"auditMixin":{"retained":false}')) {
    Assert-ReviewUnitTest ($typedRows.Contains($raw)) "raw selected symbol retains $raw"
}
$incident = Read-ReviewUnitSmallText (Join-Path $units['case-lower'].path 'native/relationships.ndjson')
Assert-ReviewUnitTest ($incident.Contains('"swiftConstraints":') -and $incident.Contains('"targetFallback":') -and
    $incident.Contains('"numeric":9e+42')) 'all incident relationship fields remain raw'
Assert-ReviewUnitTest ((Read-ReviewUnitSmallText (Join-Path $units['requirement-default'].path 'native/relationships.ndjson')).Contains('"defaultImplementationOf"')) 'incoming default-implementation edges are retained without treating them as proof'
Assert-ReviewUnitTest ((Read-ReviewUnitSmallText (Join-Path $units['synthesized'].path 'native/occurrences.ndjson')).Contains('"isUnconditionallyUnavailable":true')) 'availability and synthesized status do not filter selected occurrences'
Assert-ReviewUnitTest ((Get-Item -LiteralPath (Join-Path $units['macro'].path 'native/relationships.ndjson')).Length -eq 0) 'an identity with no incident edges still has an explicit empty relationship stream'
$repeatedUnit = Read-SwiftUIAuditTestSmallJson $units['repeated-group'].manifestPath
$repeatedRows = Read-ReviewUnitRows (Join-Path $units['repeated-group'].path 'native/occurrences.ndjson')
Assert-ReviewUnitTest ($repeatedRows.Count -eq 256 -and $repeatedUnit.selection.declarationOccurrences -eq 256) 'all 256 repeated selected occurrences survive the external index'
Assert-ReviewUnitTest ($repeatedUnit.streaming.initialSortRuns -gt 1 -and $repeatedUnit.streaming.mergePasses -gt 0) 'the repeated group spans multiple bounded sort runs'
foreach ($row in $repeatedRows) {
    Assert-ReviewUnitTest ((($row | ConvertFrom-Json).symbol.names.futurePayload).Length -eq 4096) 'each repeated selected record retains its complete payload'
}
$interfaceContext = Read-ReviewUnitSmallText (Join-Path $units['shared'].path 'context/interface-facts.ndjson')
Assert-ReviewUnitTest ($interfaceContext.Contains('6.3.2') -and $interfaceContext.Contains('-swift-version 5') -and
    $interfaceContext.Contains('#if')) 'full interface producer and conditional-compilation context is not replaced by extractor metadata'

Assert-ReviewRejected -Name 'failed-capture' -Mutation {
    $status = Read-SwiftUIAuditTestSmallJson $fixture.StatusPath
    $status.status = 'failed'
    Write-SwiftUIBaselineJson -Value $status -Path $fixture.StatusPath
} -Pattern 'failed|successful|candidate'
Assert-ReviewRejected -Name 'capture-digest' -Mutation {
    [IO.File]::AppendAllText($fixture.CapturePath, ' ', $utf8)
} -Pattern 'SHA-256|digest|hash'
Assert-ReviewRejected -Name 'ledger-digest' -Mutation {
    [IO.File]::AppendAllText((Join-Path $auditRoot 'audit.json'), ' ', $utf8)
} -Pattern 'SHA-256|digest|hash|seal'
Assert-ReviewRejected -Name 'duplicate-schema-version' -Mutation {
    $path = Join-Path $auditRoot 'audit.json'
    $text = [regex]::new('"schemaVersion"\s*:\s*1').Replace((Read-ReviewUnitSmallText $path), '"schemaVersion":0,"schemaVersion":1', 1)
    [IO.File]::WriteAllText($path, $text, $utf8)
    Seal-SyntheticReviewLedger -ManifestOnly
} -Pattern 'duplicate|ambiguous'
Assert-ReviewRejected -Name 'duplicate-review-status' -Mutation {
    $path = Join-Path $auditRoot 'audit.json'
    $text = [regex]::new('"reviewStatus"\s*:\s*"unreviewed"').Replace((Read-ReviewUnitSmallText $path), '"reviewStatus":"qualified","reviewStatus":"unreviewed"', 1)
    [IO.File]::WriteAllText($path, $text, $utf8)
    Seal-SyntheticReviewLedger -ManifestOnly
} -Pattern 'duplicate|ambiguous'
Assert-ReviewRejected -Name 'duplicate-authority-field' -Mutation {
    $path = Join-Path $auditRoot 'audit.json'
    $text = [regex]::new('"windowsMatchingPerformed"\s*:\s*false').Replace((Read-ReviewUnitSmallText $path), '"windowsMatchingPerformed":true,"windowsMatchingPerformed":false', 1)
    [IO.File]::WriteAllText($path, $text, $utf8)
    Seal-SyntheticReviewLedger -ManifestOnly
} -Pattern 'duplicate|ambiguous'
Assert-ReviewRejected -Name 'duplicate-source-field' -Mutation {
    $path = Join-Path $auditRoot 'audit.json'
    $text = Read-ReviewUnitSmallText $path
    $match = [regex]::Match($text, '"inventorySha256"\s*:\s*"(?<hash>[0-9a-f]{64})"')
    Assert-ReviewUnitTest $match.Success 'fixture contains the nested source inventory digest'
    $replacement = '"inventorySha256":"' + ('0' * 64) + '","inventorySha256":"' + $match.Groups['hash'].Value + '"'
    [IO.File]::WriteAllText($path, $text.Remove($match.Index, $match.Length).Insert($match.Index, $replacement), $utf8)
    Seal-SyntheticReviewLedger -ManifestOnly
} -Pattern 'duplicate|ambiguous'
Assert-ReviewRejected -Name 'case-ambiguous-metadata' -Mutation {
    $path = Join-Path $auditRoot 'audit.json'
    $text = [regex]::new('"reviewStatus"\s*:\s*"unreviewed"').Replace((Read-ReviewUnitSmallText $path), '"reviewStatus":"qualified","ReviewStatus":"unreviewed"', 1)
    [IO.File]::WriteAllText($path, $text, $utf8)
    # Seal the owned bytes directly so test-side deserialization cannot discard
    # the case-distinct keys or reject them before the production reader runs.
    $hash = Get-ReviewUnitFileHash $path
    [IO.File]::WriteAllText((Join-Path $auditRoot 'audit.sha256'), "$hash  audit.json`n", $utf8)
} -Pattern 'duplicate|ambiguous|different casing'
Assert-ReviewRejected -Name 'record-digest' -Mutation {
    [IO.File]::AppendAllText((Join-Path $auditRoot 'occurrences.ndjson'), ' ', $utf8)
} -Pattern 'SHA-256|digest|hash|NDJSON|record|match|line'
Assert-ReviewRejected -Name 'duplicate-identity-row' -Mutation {
    $rows = Read-ReviewUnitRows (Join-Path $auditRoot 'identities.ndjson')
    $rows[1] = $rows[0]
    Write-ReviewUnitRows -Path (Join-Path $auditRoot 'identities.ndjson') -Rows $rows
    Seal-SyntheticReviewLedger
} -Pattern 'identity|identif|record|match|order|count'
Assert-ReviewRejected -Name 'missing-unselected-occurrence' -Mutation {
    $rows = [System.Collections.Generic.List[string]]::new()
    $removed = $false
    foreach ($row in $sourceRows['occurrences.ndjson']) {
        if (-not $removed -and (Get-ReviewOccurrenceIdentifier $row) -cne $fixture.SymbolIds.Shared) {
            $removed = $true
        } else { $rows.Add($row) }
    }
    Assert-ReviewUnitTest $removed 'fixture contains an occurrence outside the requested identity'
    Write-ReviewUnitRows -Path (Join-Path $auditRoot 'occurrences.ndjson') -Rows $rows.ToArray()
    Seal-SyntheticReviewLedger
} -Pattern 'occurrence|record|match|count|end|line'
Assert-ReviewRejected -Name 'missing-nonincident-relationship' -Mutation {
    $rows = [System.Collections.Generic.List[string]]::new()
    $removed = $false
    foreach ($row in $sourceRows['relationships.ndjson']) {
        $relationship = ($row | ConvertFrom-Json).relationship
        if (-not $removed -and $relationship.source -cne $fixture.SymbolIds.Shared -and
            $relationship.target -cne $fixture.SymbolIds.Shared) { $removed = $true }
        else { $rows.Add($row) }
    }
    Assert-ReviewUnitTest $removed 'fixture contains a relationship outside the requested identity'
    Write-ReviewUnitRows -Path (Join-Path $auditRoot 'relationships.ndjson') -Rows $rows.ToArray()
    Seal-SyntheticReviewLedger
} -Pattern 'relationship|record|match|count|end|line'
Assert-ReviewRejected -Name 'missing-extension-partition' -Mutation {
    $rows = @($sourceRows['partitions.ndjson'] | Where-Object {
        ($_ | ConvertFrom-Json).graph.path -cnotmatch 'arm64[^/]*/SwiftUI/SwiftUI@Foundation\.symbols\.json$'
    })
    Assert-ReviewUnitTest ($rows.Count -eq $sourceRows['partitions.ndjson'].Count - 1) 'fixture removes only one extension partition'
    Write-ReviewUnitRows -Path (Join-Path $auditRoot 'partitions.ndjson') -Rows $rows
    Seal-SyntheticReviewLedger
} -Pattern 'partition|graph|record|match|count|end|line'
Assert-ReviewRejected -Name 'truncated-context-ndjson' -Mutation {
    $path = Join-Path $auditRoot 'candidate-queues.ndjson'
    $text = Read-ReviewUnitSmallText $path
    [IO.File]::WriteAllText($path, $text.Substring(0, $text.Length - 3), $utf8)
    Seal-SyntheticReviewLedger
} -Pattern 'JSON|queue|record|match|end|line|Expected'
Assert-ReviewRejected -Name 'promoted-identity-row' -Mutation {
    $rows = Read-ReviewUnitRows (Join-Path $auditRoot 'identities.ndjson')
    $rows[0] = $rows[0].Replace('"reviewStatus":"unreviewed"', '"reviewStatus":"reviewed"')
    Write-ReviewUnitRows -Path (Join-Path $auditRoot 'identities.ndjson') -Rows $rows
    Seal-SyntheticReviewLedger
} -Pattern 'unreviewed|identity|identif|record|match'
Assert-ReviewRejected -Name 'record-budget' -Overrides @{ MaximumRecordCharacters = 1024 } -Pattern 'MaximumRecordCharacters|budget|record|line'
Assert-ReviewRejected -Name 'metadata-budget' -Overrides @{ MaximumMetadataBytes = 1024 } -Pattern 'MaximumMetadataBytes|budget|metadata'
Assert-ReviewRejected -Name 'identifier-budget' -Overrides @{
    PreciseIdentifier = ('s:' + [string]::new([char]'x', 2048)); MaximumRecordCharacters = 1024
} -Pattern 'MaximumRecordCharacters|identifier|budget'
Assert-ReviewRejected -Name 'invalid-identifier-unicode' -Overrides @{
    PreciseIdentifier = [string][char]0xd800
} -Pattern 'UTF|surrogate|identifier|translate|encoding'
Assert-ReviewRejected -Name 'source-budget' -Overrides @{ MaximumSourceBytes = 1024 } -Pattern 'MaximumSourceBytes|source|budget'
$sourceFiles = (Read-SwiftUIAuditTestSmallJson $units['shared'].manifestPath).windowsSource.files
[long]$largestSourceBytes = ($sourceFiles | Measure-Object -Property bytes -Maximum).Maximum
Assert-ReviewRejected -Name 'combined-source-budget' -Overrides @{ MaximumSourceBytes = $largestSourceBytes } -Pattern 'MaximumSourceBytes|combined|source|budget'
foreach ($item in @(
        @{ name = 'missing-id'; value = 's:syntheticMissingReviewIdentifier' },
        @{ name = 'wrong-case-id'; value = 'S:fixtureSharedViewP' },
        @{ name = 'display-name'; value = 'FixtureSharedView' },
        @{ name = 'queue-label'; value = 'view-builder' },
        @{ name = 'regex-id'; value = '.*' })) {
    Assert-ReviewRejected -Name $item.name -Overrides @{ PreciseIdentifier = $item.value } -Pattern 'identifier|identity|found|exact|missing'
}
Assert-ReviewRejected -Name 'commit-ref' -Overrides @{ WindowsCommit = 'HEAD' } -Pattern 'commit|40|hex|revision'
Assert-ReviewRejected -Name 'commit-short' -Overrides @{ WindowsCommit = $windowsCommit.Substring(0, 7) } -Pattern 'commit|40|hex|revision'
Assert-ReviewRejected -Name 'commit-missing' -Overrides @{ WindowsCommit = ('0' * 40) } -Pattern 'commit|Git|git|revision|object'
Assert-ReviewRejected -Name 'commit-is-blob' -Overrides @{ WindowsCommit = $expectedBlobIds[$windowsSourcePaths[0]] } -Pattern 'commit|Git|git|revision|object'
foreach ($item in @(
        @{ name = 'source-traversal'; value = '../outside.swift' },
        @{ name = 'source-absolute'; value = (Join-Path $RepositoryRoot 'Sources/WinSwiftUI/Core.swift') },
        @{ name = 'source-directory'; value = 'Sources/WinSwiftUI' },
        @{ name = 'source-gitlink'; value = 'extern/zed' },
        @{ name = 'source-missing'; value = ('synthetic-untracked-' + [Guid]::NewGuid().ToString('N') + '.swift') })) {
    Assert-ReviewRejected -Name $item.name -Overrides @{ WindowsSourcePath = @($item.value) } -Pattern 'path|file|blob|regular|commit|Git|git|source|directory|travers'
}
Assert-ReviewRejected -Name 'output-in-capture' -Overrides @{ OutputDirectory = (Join-Path $fixture.Root 'review-unit') } -Pattern 'outside|overlap|source|capture'
Assert-ReviewRejected -Name 'output-in-audit' -Overrides @{ OutputDirectory = (Join-Path $auditRoot 'review-unit') } -Pattern 'outside|overlap|source|audit'

Restore-ReviewInputs
$existing = $units['shared']
$previousManifestHash = Get-ReviewUnitFileHash $existing.manifestPath
$arguments = New-ReviewUnitArguments -Identifier $fixture.SymbolIds.Shared -Destination $existing.path
$caught = $null
try { & $selector @arguments | Out-Null } catch { $caught = $_ }
Assert-ReviewUnitTest ($null -ne $caught -and $caught.Exception.Message -match 'exist|immutable|overwrit') 'an existing packet is never overwritten'
Assert-ReviewUnitTest ((Get-ReviewUnitFileHash $existing.manifestPath) -ceq $previousManifestHash) 'immutable output retains the original packet bytes'
Assert-ReviewUnitTest ((Get-ReviewInputFingerprint) -ceq $initialFingerprint) 'all fixture inputs are restored and unchanged after testing'
$headAfter = @(& git -c core.fsmonitor=false -C $RepositoryRoot rev-parse --verify 'HEAD^{commit}')
Assert-ReviewUnitTest ($LASTEXITCODE -eq 0 -and $headAfter.Count -eq 1 -and $headAfter[0] -ceq $windowsCommit) 'source repository commit is unchanged'

$report = [ordered]@{
    schemaVersion = 1
    evidenceKind = 'synthetic-api-review-unit-tooling-tests-only'
    assertions = $script:ReviewAssertions
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    outputRoot = $OutputRoot
    sourceCommit = $windowsCommit
    fixtureCounts = $fixture.Counts
    nativeExportPerformed = $false
    swiftCompilationPerformed = $false
    behaviorConformanceAssessed = $false
}
Write-SwiftUIBaselineJson -Value $report -Path (Join-Path $OutputRoot 'test-results.json')
Write-Host "API review-unit tests passed $($script:ReviewAssertions) assertions using synthetic evidence only."
Write-Host "Evidence: $OutputRoot"
