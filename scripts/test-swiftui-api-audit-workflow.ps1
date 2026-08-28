<#
.SYNOPSIS
Tests the post-export workflow handoff with explicitly synthetic captures.
.DESCRIPTION
No native SDK export, SwiftPM command, or Swift compiler runs. Workflow run
commands execute only in the marked filesystem preflight in an owned synthetic
checkout. The exact RGB condition is evaluated with synthetic step outcomes.
#>
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $RepositoryRoot 'scripts/swiftui-api-audit-test-fixtures.ps1')
. (Join-Path $RepositoryRoot 'scripts/swiftui-api-audit-common.ps1')
$RepositoryRoot = Resolve-SwiftUIBaselineFileSystemPath -Path $RepositoryRoot
$manifestPath = Join-Path $RepositoryRoot 'docs/swiftui-baseline.json'
$candidateScript = Join-Path $RepositoryRoot 'scripts/build-swiftui-api-audit-candidate.ps1'
$workflowPath = Join-Path $RepositoryRoot '.github/workflows/swiftui-baseline-capture.yml'
if (-not (Test-Path -LiteralPath $candidateScript -PathType Leaf)) { throw 'The candidate handoff script must exist before these tests run.' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepositoryRoot ('artifacts/swiftui-api-audit-workflow-tests/' + [Guid]::NewGuid().ToString('N'))
}
$OutputRoot = Resolve-SwiftUIBaselineFileSystemPath -Path $OutputRoot
[void](Get-SwiftUIBaselineRelativePath -Root (Join-Path $RepositoryRoot 'artifacts') -Path $OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) { throw 'Workflow test output must be a new owned directory under repository artifacts.' }
[void][IO.Directory]::CreateDirectory($OutputRoot)
$script:WorkflowAssertions = 0
$utf8 = [Text.UTF8Encoding]::new($false, $true)

function Assert-WorkflowAudit {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Workflow audit assertion failed: $Message" }
    $script:WorkflowAssertions++
}

function Read-WorkflowAuditText {
    param([string]$Path)
    if ((Get-Item -LiteralPath $Path).Length -gt 8MB) {
        throw 'Workflow tests permit only small synthetic metadata and scripts, never native graph/inventory DOMs.'
    }
    return [IO.File]::ReadAllText($Path, $utf8)
}

function Get-WorkflowAuditHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-WorkflowAuditTreeHash {
    param([string]$Root)
    $records = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Root -PathType Leaf) { return Get-WorkflowAuditHash $Root }
    foreach ($item in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
        $relative = Get-SwiftUIBaselineRelativePath -Root $Root -Path $item.FullName
        $records.Add($relative + [char]9 + (Get-WorkflowAuditHash $item.FullName))
    }
    [string[]]$ordered = $records.ToArray()
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    return Get-SwiftUIBaselineTextHash -Text ([string]::Join([string][char]10, $ordered))
}

function Get-WorkflowAuditSourceHash {
    param($Case, [switch]$ExcludeDescriptor)
    $parts = @((Get-WorkflowAuditTreeHash $Case.fixture.Root),
        (Get-WorkflowAuditHash $Case.ciContextPath))
    if (-not $ExcludeDescriptor) { $parts += Get-WorkflowAuditHash $Case.descriptorPath }
    return Get-SwiftUIBaselineTextHash -Text ([string]::Join([string][char]10, $parts))
}

function Write-WorkflowAuditDescriptor {
    param($Case)
    $capture = Read-SwiftUIAuditTestSmallJson $Case.fixture.CapturePath
    $relative = Get-SwiftUIBaselineRelativePath -Root $Case.evidenceRoot -Path $Case.fixture.Root
    $descriptor = [ordered]@{
        schemaVersion = 1
        status = 'exported-awaiting-review'
        path = $relative
        manifestPath = "$relative/capture.json"
        manifestSha256 = Get-WorkflowAuditHash $Case.fixture.CapturePath
        statusPath = "$relative/capture-status.json"
        statusSha256 = Get-WorkflowAuditHash $Case.fixture.StatusPath
        inventoryPath = "$relative/inventory.json"
        inventorySha256 = $capture.inventory.sha256
        baselineManifestSha256 = $capture.baselineManifest.sha256
        counts = $capture.inventory.counts
    }
    Write-SwiftUIBaselineJson -Value $descriptor -Path $Case.descriptorPath
}

function New-WorkflowAuditCase {
    param([string]$Name, [string]$CaptureName = 'captures/selected candidate', [switch]$NoDescriptor)
    $root = Join-Path $OutputRoot $Name
    [void][IO.Directory]::CreateDirectory($root)
    $case = [pscustomobject]@{
        evidenceRoot = $root
        argumentRoot = $root
        fixture = New-SwiftUIAuditTestCapture -Root (Join-Path $root $CaptureName) -ManifestPath $manifestPath -RepeatedSymbols 1
        descriptorPath = Join-Path $root 'explicit-export-result.json'
        argumentPath = Join-Path $root 'explicit-export-result.json'
        workingDirectory = $null
        ciContextPath = Join-Path $root 'ci-context.json'
        auditPath = Join-Path $root 'audit'
        contextPath = Join-Path $root 'audit-context.json'
        githubOutputPath = Join-Path $root 'github-output.txt'
        links = [System.Collections.Generic.List[string]]::new()
    }
    Write-SwiftUIBaselineJson -Path $case.ciContextPath -Value ([ordered]@{
        status = 'exported-awaiting-review'; reviewStatus = 'unreviewed'
        syntheticFixture = 'SYNTHETIC workflow test; no native export was performed.'
        opaqueCiContext = @('preserve', $null, 42)
    })
    if (-not $NoDescriptor) { Write-WorkflowAuditDescriptor $case }
    return $case
}

function Invoke-WorkflowAuditCase {
    param($Case)
    $previous = [Environment]::CurrentDirectory
    try {
        if ($null -ne $Case.workingDirectory) { [Environment]::CurrentDirectory = $Case.workingDirectory }
        & $candidateScript -EvidenceRoot $Case.argumentRoot -ExportResultPath $Case.argumentPath -ManifestPath $manifestPath
    } finally { [Environment]::CurrentDirectory = $previous }
}

function Remove-WorkflowAuditTestLink {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    [void](Get-SwiftUIBaselineRelativePath -Root $OutputRoot -Path $full)
    $item = Get-Item -LiteralPath $full -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'Refusing to remove a non-link fixture directory.' }
    # Delete only this directory entry, never recursively traverse its target.
    [IO.Directory]::Delete($full)
}

function New-WorkflowAuditTestLink {
    param([string]$Path, [string]$Target)
    [void](Get-SwiftUIBaselineRelativePath -Root $OutputRoot -Path ([IO.Path]::GetFullPath($Path)))
    [void](Get-SwiftUIBaselineRelativePath -Root $OutputRoot -Path ([IO.Path]::GetFullPath($Target)))
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $kind = if ([IO.Path]::DirectorySeparatorChar -eq '\') { 'Junction' } else { 'SymbolicLink' }
    [void](New-Item -ItemType $kind -Path $Path -Target $Target)
}

function Assert-WorkflowAuditRejected {
    param([string]$Name, [scriptblock]$Mutation, [string]$Pattern,
        [switch]$RequireDiagnostic, [string]$CaptureName = 'captures/selected candidate')
    $case = New-WorkflowAuditCase -Name $Name -CaptureName $CaptureName
    try {
        & $Mutation $case
        $before = Get-WorkflowAuditSourceHash $case
        $hadAudit = Test-Path -LiteralPath $case.auditPath
        $oldAuditHash = if ($hadAudit) { Get-WorkflowAuditTreeHash $case.auditPath } else { $null }
        $oldContextHash = if (Test-Path -LiteralPath $case.contextPath) { Get-WorkflowAuditTreeHash $case.contextPath } else { $null }
        $caught = $null
        try { Invoke-WorkflowAuditCase $case | Out-Null } catch { $caught = $_ }
        Assert-WorkflowAudit ($null -ne $caught) "$Name rejects the handoff"
        Assert-WorkflowAudit ($caught.Exception.Message -match $Pattern) "$Name explains rejection: $($caught.Exception.Message)"
        Assert-WorkflowAudit ((Get-WorkflowAuditSourceHash $case) -ceq $before) "$Name leaves every source/CI/descriptor byte unchanged"
        if ($hadAudit) {
            Assert-WorkflowAudit ((Get-WorkflowAuditTreeHash $case.auditPath) -ceq $oldAuditHash) "$Name never overwrites existing audit evidence"
        } else {
            Assert-WorkflowAudit (-not (Test-Path -LiteralPath $case.auditPath)) "$Name never publishes a partial audit"
        }
        if ($null -ne $oldContextHash) {
            Assert-WorkflowAudit ((Get-WorkflowAuditTreeHash $case.contextPath) -ceq $oldContextHash) "$Name never overwrites an existing diagnostic context"
        } elseif (Test-Path -LiteralPath $case.contextPath) {
            $diagnostic = Read-SwiftUIAuditTestSmallJson $case.contextPath
            Assert-WorkflowAudit ($diagnostic.status -ceq 'failed') "$Name has an explicit failed diagnostic status"
            Assert-WorkflowAudit ($diagnostic.reviewStatus -ceq 'unreviewed') "$Name does not promote review status"
            Assert-WorkflowAudit (-not [string]::IsNullOrWhiteSpace($diagnostic.error)) "$Name retains its failure reason"
        } elseif ($RequireDiagnostic) {
            Assert-WorkflowAudit $false "$Name should retain a separate failure diagnostic"
        }
        Assert-WorkflowAudit (@(Get-ChildItem -LiteralPath $case.evidenceRoot -Force -Directory -Filter '.swiftui-api-audit-*').Count -eq 0) "$Name leaves no owned partial staging directory"
    } finally {
        foreach ($link in $case.links) { Remove-WorkflowAuditTestLink $link }
    }
}

foreach ($name in @('build-swiftui-api-audit-candidate.ps1', 'test-swiftui-api-audit-workflow.ps1', 'export-swiftui-baseline.ps1')) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepositoryRoot "scripts/$name"), [ref]$tokens, [ref]$errors)
    Assert-WorkflowAudit ($errors.Count -eq 0) "PowerShell parser accepts $name"
}

$workflow = Read-WorkflowAuditText $workflowPath
$handoffMatch = [regex]::Match($workflow, '(?ms)^ +# Candidate result handoff\.\r?\n(?<code>.*?)^ +# End candidate result handoff\.')
Assert-WorkflowAudit $handoffMatch.Success 'workflow exposes only the portable result handoff for isolated execution'
$handoffCode = $handoffMatch.Groups['code'].Value -replace '(?m)^ {14}', ''
Assert-WorkflowAudit (-not $handoffCode.Contains('export-swiftui-baseline.ps1') -and -not $handoffCode.Contains('Invoke-SwiftUIBaselineNativeCommand')) 'actual extracted handoff cannot invoke native export'
$handoffBlock = [scriptblock]::Create($handoffCode)
$tokens = $null; $errors = $null
$exporterAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepositoryRoot 'scripts/export-swiftui-baseline.ps1'), [ref]$tokens, [ref]$errors)
$resultStatement = $exporterAst.EndBlock.Statements[-1]
$resultCommands = @($resultStatement.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
Assert-WorkflowAudit ($resultCommands.Count -eq 1 -and $resultCommands[0].GetCommandName() -ceq 'Get-FileHash') 'exporter result statement performs only a small status-file hash, never native tools'
$exportTry = $exporterAst.EndBlock.Statements[-2]
Assert-WorkflowAudit ($exportTry -is [System.Management.Automation.Language.TryStatementAst] -and
    $exportTry.CatchClauses[0].Body.Statements[-1] -is [System.Management.Automation.Language.ThrowStatementAst]) 'exporter result follows a failure-rethrowing export block'
$resultBlock = [scriptblock]::Create($resultStatement.Extent.Text)

function New-WorkflowAuditActualExportResult {
    param($Case)
    $captureRoot = $Case.fixture.Root
    $capturePath = $Case.fixture.CapturePath
    $captureHash = Get-WorkflowAuditHash $capturePath
    $statusPath = $Case.fixture.StatusPath
    $inventoryPath = $Case.fixture.InventoryPath
    $capture = Read-SwiftUIAuditTestSmallJson $capturePath
    # Exercise the CLR Int64 summary returned by the actual streaming writer,
    # without loading or deserializing its inventory contents here.
    $inventory = [pscustomobject]@{ counts = [ordered]@{
        graphs = [long]$capture.inventory.counts.graphs
        preciseSymbols = [long]$capture.inventory.counts.preciseSymbols
        declarationOccurrences = [long]$capture.inventory.counts.declarationOccurrences
        relationshipOccurrences = [long]$capture.inventory.counts.relationshipOccurrences
    } }
    & $resultBlock
}

function Invoke-WorkflowAuditActualHandoff {
    param($Case, $ExportResult)
    $captureRoot = $Case.fixture.Root
    $evidenceRoot = $Case.evidenceRoot
    $exportResultPath = $Case.descriptorPath
    if (-not (Test-Path -LiteralPath $Case.githubOutputPath)) { [IO.File]::WriteAllText($Case.githubOutputPath, '', $utf8) }
    $previous = [Environment]::GetEnvironmentVariable('GITHUB_OUTPUT', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('GITHUB_OUTPUT', $Case.githubOutputPath, 'Process')
        & $handoffBlock | Out-Null
    } finally { [Environment]::SetEnvironmentVariable('GITHUB_OUTPUT', $previous, 'Process') }
}

function Assert-WorkflowAuditHandoffRejected {
    param([string]$Name, [scriptblock]$Mutation, [switch]$ExistingDescriptor)
    $case = New-WorkflowAuditCase -Name ("handoff-$Name") -NoDescriptor:(-not $ExistingDescriptor)
    $exportResult = New-WorkflowAuditActualExportResult $case
    & $Mutation $case $exportResult
    $before = Get-WorkflowAuditSourceHash $case -ExcludeDescriptor
    $oldDescriptorHash = if (Test-Path -LiteralPath $case.descriptorPath) { Get-WorkflowAuditHash $case.descriptorPath } else { $null }
    $caught = $null
    try { Invoke-WorkflowAuditActualHandoff $case $exportResult } catch { $caught = $_ }
    Assert-WorkflowAudit ($null -ne $caught) "actual workflow handoff rejects $Name"
    Assert-WorkflowAudit ((Get-WorkflowAuditSourceHash $case -ExcludeDescriptor) -ceq $before) "$Name handoff leaves source capture and CI context unchanged"
    Assert-WorkflowAudit ((Read-WorkflowAuditText $case.githubOutputPath).Length -eq 0) "$Name publishes no successful GitHub outputs"
    if ($null -eq $oldDescriptorHash) {
        Assert-WorkflowAudit (-not (Test-Path -LiteralPath $case.descriptorPath)) "$Name publishes no invalid descriptor"
    } else {
        Assert-WorkflowAudit ((Get-WorkflowAuditHash $case.descriptorPath) -ceq $oldDescriptorHash) "$Name cannot overwrite an existing export result"
    }
}

$selectedCaptureName = 'captures/selected ' + [char]0x00e9 + ' candidate'
$success = New-WorkflowAuditCase 'success-explicit-arbitrary-capture' -CaptureName $selectedCaptureName -NoDescriptor
# A differently named, later-created directory is never inferred as the source.
[void][IO.Directory]::CreateDirectory((Join-Path $success.evidenceRoot 'capture'))
[IO.File]::WriteAllText((Join-Path $success.evidenceRoot 'capture/not-a-capture.txt'), 'SYNTHETIC decoy; must not be selected.', $utf8)
$exportResult = New-WorkflowAuditActualExportResult $success
Assert-WorkflowAudit ($exportResult -is [System.Management.Automation.PSCustomObject] -and $exportResult.counts.graphs -is [long]) 'actual exporter result is compact and retains native Int64 counters'
$beforeHandoff = Get-WorkflowAuditSourceHash $success -ExcludeDescriptor
Invoke-WorkflowAuditActualHandoff $success $exportResult
Assert-WorkflowAudit ((Get-WorkflowAuditSourceHash $success -ExcludeDescriptor) -ceq $beforeHandoff) 'actual workflow handoff does not rewrite source capture or CI context'
$portable = Read-SwiftUIAuditTestSmallJson $success.descriptorPath
foreach ($field in @('path', 'manifestPath', 'statusPath', 'inventoryPath')) {
    Assert-WorkflowAudit (-not [IO.Path]::IsPathRooted($portable.$field) -and -not $portable.$field.Contains('\')) "actual handoff stores portable relative $field"
}
Assert-WorkflowAudit ($portable.path -ceq $selectedCaptureName) 'actual handoff preserves the selected arbitrary capture directory, including spaces and Unicode'
Assert-WorkflowAudit ($portable.manifestSha256 -ceq $exportResult.manifestSha256 -and $portable.statusSha256 -ceq $exportResult.statusSha256 -and
    $portable.inventorySha256 -ceq $exportResult.inventorySha256 -and $portable.baselineManifestSha256 -ceq $exportResult.baselineManifestSha256) 'actual handoff preserves all four source digests'
Assert-WorkflowAudit ($portable.counts.preciseSymbols -eq $exportResult.counts.preciseSymbols) 'actual handoff normalizes count representation without changing count values'
$githubOutputs = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
foreach ($line in (Read-WorkflowAuditText $success.githubOutputPath) -split '\r?\n') {
    if ($line.Length -eq 0) { continue }
    $parts = $line.Split([char[]]@('='), 2)
    Assert-WorkflowAudit ($parts.Length -eq 2 -and $parts[1] -notmatch '[\x00-\x1f\x7f]') 'actual GitHub output is one validated key/value line'
    $githubOutputs.Add($parts[0], $parts[1])
}
Assert-WorkflowAudit ($githubOutputs.Count -eq 3 -and $githubOutputs['capture-status'] -ceq 'exported-awaiting-review') 'actual handoff emits exactly the three candidate outputs'
Assert-WorkflowAudit ($githubOutputs['export-result-path'] -ceq $success.descriptorPath -and $githubOutputs['capture-root'] -ceq $success.fixture.Root) 'actual workflow outputs bind the exact descriptor and selected source'
$before = Get-WorkflowAuditSourceHash $success
Invoke-WorkflowAuditCase $success | Out-Null
$context = Read-SwiftUIAuditTestSmallJson $success.contextPath
$auditManifestPath = Join-Path $success.auditPath 'audit.json'
$audit = Read-SwiftUIAuditTestSmallJson $auditManifestPath
$auditHash = Get-WorkflowAuditHash $auditManifestPath
$contextText = Read-WorkflowAuditText $success.contextPath
Assert-WorkflowAudit ($context.status -ceq 'created-unreviewed-ledger') 'successful handoff has a distinct ledger status'
Assert-WorkflowAudit ($context.reviewStatus -ceq 'unreviewed') 'successful handoff remains unreviewed'
Assert-WorkflowAudit ($context.audit.path -ceq 'audit' -and $context.audit.manifestPath -ceq 'audit/audit.json' -and $context.audit.manifestSha256 -ceq $auditHash) 'sidecar records the immutable sibling audit and exact manifest hash'
Assert-WorkflowAudit ($context.audit.counts.preciseIdentifiers -eq $audit.counts.preciseIdentifiers -and $context.audit.reviewStatus -ceq 'unreviewed') 'sidecar counts and review status match the published audit'
Assert-WorkflowAudit ($contextText.Contains('audit/audit.json') -and $contextText.Contains($auditHash)) 'compact sidecar links the explicit published manifest and its digest'
Assert-WorkflowAudit ($contextText.Contains('swiftui-api-audit-tests')) 'synthetic provenance remains visible in the handoff context'
Assert-WorkflowAudit ((Get-Item -LiteralPath $success.contextPath).Length -lt 64KB) 'handoff context stays small rather than embedding inventory or ledger records'
Assert-WorkflowAudit ($audit.reviewStatus -ceq 'unreviewed' -and -not $audit.authority.nativeExportPerformed -and -not $audit.authority.identityReviewPerformed -and -not $audit.authority.behaviorConformanceAssessed) 'portable indexing never becomes native export or qualification'
Assert-WorkflowAudit ($audit.sourceCapture.syntheticFixtureAsReported.kind -ceq 'swiftui-api-audit-tests') 'the ledger identifies its synthetic source'
Assert-WorkflowAudit ($audit.counts.graphs -eq $success.fixture.Counts.graphs -and $audit.counts.preciseIdentifiers -eq $success.fixture.Counts.preciseSymbols) 'ledger counts remain bound to the explicit capture'
Assert-WorkflowAudit ((Read-WorkflowAuditText (Join-Path $success.auditPath 'audit.sha256')) -ceq ($auditHash + "  audit.json`n")) 'published manifest seal matches its exact bytes'
Assert-WorkflowAudit ((Get-WorkflowAuditSourceHash $success) -ceq $before) 'success preserves source capture, both source seals, descriptor and CI context'
Assert-WorkflowAudit (@(Get-ChildItem -LiteralPath (Join-Path $success.fixture.Root 'graphs') -File -Recurse -Filter '*.symbols.json').Count -eq 6) 'every original primary and extension graph is retained for upload'
Assert-WorkflowAudit (Test-Path -LiteralPath $success.fixture.InventoryPath -PathType Leaf) 'the authoritative inventory remains beside raw graphs'
foreach ($file in $audit.recordFiles) {
    Assert-WorkflowAudit ((Get-WorkflowAuditHash (Join-Path $success.auditPath $file.path)) -ceq $file.sha256) "published ledger retains complete $($file.path) evidence"
}
$oldAuditHash = Get-WorkflowAuditTreeHash $success.auditPath
$oldContextHash = Get-WorkflowAuditHash $success.contextPath
$caught = $null
try { Invoke-WorkflowAuditCase $success | Out-Null } catch { $caught = $_ }
Assert-WorkflowAudit ($null -ne $caught) 'repeated handoff cannot overwrite the immutable output/context'
Assert-WorkflowAudit ((Get-WorkflowAuditTreeHash $success.auditPath) -ceq $oldAuditHash -and (Get-WorkflowAuditHash $success.contextPath) -ceq $oldContextHash) 'repeated handoff preserves existing published evidence byte-for-byte'
Assert-WorkflowAudit ((Get-WorkflowAuditSourceHash $success) -ceq $before) 'repeated handoff leaves source and CI provenance unchanged'

foreach ($field in @('manifestPath', 'statusPath', 'inventoryPath')) {
    Assert-WorkflowAuditHandoffRejected ("mixed-$field") { param($case, $result) $result.$field = $case.ciContextPath }
}
Assert-WorkflowAuditHandoffRejected 'wrong-manifest-hash' { param($case, $result) $result.manifestSha256 = '0' * 64 }
Assert-WorkflowAuditHandoffRejected 'wrong-counts' { param($case, $result) $result.counts.preciseSymbols++ }
Assert-WorkflowAuditHandoffRejected 'failed-result' { param($case, $result) $result.status = 'failed' }
Assert-WorkflowAuditHandoffRejected 'wrong-source' { param($case, $result) $result.path = $case.evidenceRoot }
Assert-WorkflowAuditHandoffRejected 'existing-result' { param($case, $result) } -ExistingDescriptor

foreach ($change in @(
    @{ name = 'descriptor-schema'; field = 'schemaVersion'; value = 2; pattern = 'schema|version|successful|eligible' },
    @{ name = 'descriptor-status'; field = 'status'; value = 'failed'; pattern = 'status|successful|candidate' },
    @{ name = 'descriptor-case'; field = 'status'; value = 'EXPORTED-AWAITING-REVIEW'; pattern = 'status|successful|candidate' },
    @{ name = 'manifest-digest'; field = 'manifestSha256'; value = ('0' * 64); pattern = 'hash|SHA|digest|match' },
    @{ name = 'status-digest'; field = 'statusSha256'; value = ('0' * 64); pattern = 'hash|SHA|digest|match' },
    @{ name = 'inventory-digest'; field = 'inventorySha256'; value = ('0' * 64); pattern = 'hash|SHA|digest|match' },
    @{ name = 'baseline-digest'; field = 'baselineManifestSha256'; value = ('0' * 64); pattern = 'hash|SHA|digest|match' },
    @{ name = 'uppercase-digest'; field = 'manifestSha256'; value = ('F' * 64); pattern = 'lowercase|SHA|digest' },
    @{ name = 'path-traversal'; field = 'path'; value = '../escape'; pattern = 'relative|travers|contain|path' },
    @{ name = 'manifest-traversal'; field = 'manifestPath'; value = 'captures/../capture.json'; pattern = 'relative|travers|contain|path' },
    @{ name = 'absolute-artifact-path'; field = 'path'; value = '/absolute-capture'; pattern = 'relative|path' },
    @{ name = 'drive-artifact-path'; field = 'path'; value = 'C:/capture'; pattern = 'relative|path' },
    @{ name = 'unc-artifact-path'; field = 'path'; value = '\\server\capture'; pattern = 'relative|path' },
    @{ name = 'mixed-status-path'; field = 'statusPath'; value = 'ci-context.json'; pattern = 'path|match|capture' }
)) {
    Assert-WorkflowAuditRejected $change.name {
        param($case)
        $descriptor = Read-SwiftUIAuditTestSmallJson $case.descriptorPath
        $descriptor.($change.field) = $change.value
        Write-SwiftUIBaselineJson $descriptor $case.descriptorPath
    } $change.pattern
}
Assert-WorkflowAuditRejected 'descriptor-counts' {
    param($case)
    $descriptor = Read-SwiftUIAuditTestSmallJson $case.descriptorPath
    $descriptor.counts.preciseSymbols++
    Write-SwiftUIBaselineJson $descriptor $case.descriptorPath
} 'count|match' -RequireDiagnostic
Assert-WorkflowAuditRejected 'descriptor-root-array' {
    param($case)
    [IO.File]::WriteAllText($case.descriptorPath, '[' + (Read-WorkflowAuditText $case.descriptorPath) + ']', $utf8)
} 'object|root|schema'
Assert-WorkflowAuditRejected 'descriptor-invalid-utf8' {
    param($case)
    [IO.File]::WriteAllBytes($case.descriptorPath, [byte[]]@(0xff, 0x7b, 0x7d))
} 'UTF|translate|invalid|decode'
Assert-WorkflowAuditRejected 'descriptor-oversize' {
    param($case)
    $stream = [IO.File]::Open($case.descriptorPath, [IO.FileMode]::Create)
    try { $stream.SetLength(16MB + 1) } finally { $stream.Dispose() }
} 'maximum|metadata|exceed|large'
Assert-WorkflowAuditRejected 'explicit-result-required' {
    param($case)
    $case.argumentPath = Join-Path $case.evidenceRoot 'missing-explicit-result.json'
} 'missing|exist|find|found'
Assert-WorkflowAuditRejected 'absolute-result-argument-required' {
    param($case)
    $case.argumentPath = 'explicit-export-result.json'
    $case.workingDirectory = $case.evidenceRoot
} 'absolute|rooted'
if ([IO.Path]::DirectorySeparatorChar -eq '\') {
    Assert-WorkflowAuditRejected 'drive-relative-result-argument' {
        param($case)
        $case.argumentPath = [IO.Path]::GetPathRoot($case.evidenceRoot).Substring(0, 2) + 'explicit-export-result.json'
        $case.workingDirectory = $case.evidenceRoot
    } 'absolute|rooted|qualified'
    Assert-WorkflowAuditRejected 'current-drive-result-argument' {
        param($case)
        $case.argumentPath = $case.descriptorPath.Substring(2)
        $case.workingDirectory = $case.evidenceRoot
    } 'absolute|rooted|qualified'
}
Assert-WorkflowAuditRejected 'result-inside-capture' {
    param($case)
    $case.argumentPath = Join-Path $case.fixture.Root 'extra-export-result.json'
    Copy-Item -LiteralPath $case.descriptorPath -Destination $case.argumentPath
} 'outside|capture|overlap|separat'
Assert-WorkflowAuditRejected 'result-outside-evidence' {
    param($case)
    $case.argumentPath = Join-Path $OutputRoot 'outside-explicit-result.json'
    Copy-Item -LiteralPath $case.descriptorPath -Destination $case.argumentPath
} 'contain|outside|evidence'
foreach ($state in @('failed', 'in-progress')) {
    Assert-WorkflowAuditRejected ("source-$state") {
        param($case)
        $status = Read-SwiftUIAuditTestSmallJson $case.fixture.StatusPath
        $status.status = $state
        Write-SwiftUIBaselineJson $status $case.fixture.StatusPath
        Write-WorkflowAuditDescriptor $case
    } 'successful|candidate|status' -RequireDiagnostic
}
Assert-WorkflowAuditRejected 'source-missing-seal' {
    param($case)
    [IO.File]::Delete($case.fixture.CaptureHashPath)
} 'missing|exist|find|found|seal' -RequireDiagnostic
Assert-WorkflowAuditRejected 'source-inventory-corrupt' {
    param($case)
    [IO.File]::AppendAllText($case.fixture.InventoryPath, 'trailing-invalid-json', $utf8)
} 'trailing|inventory|JSON|hash' -RequireDiagnostic
Assert-WorkflowAuditRejected 'source-graph-corrupt' {
    param($case)
    $graphPath = Join-Path $case.fixture.Exports[0].directory ($case.fixture.Exports[0].module + '.symbols.json')
    [IO.File]::AppendAllText($graphPath, "`n ", $utf8)
} 'graph|hash|SHA|match' -RequireDiagnostic
Assert-WorkflowAuditRejected 'existing-empty-audit' {
    param($case)
    [void][IO.Directory]::CreateDirectory($case.auditPath)
} 'exist|new|immutable|overwrite'
Assert-WorkflowAuditRejected 'existing-audit-context' {
    param($case)
    [IO.File]::WriteAllText($case.contextPath, '{"status":"preexisting-evidence-do-not-touch"}', $utf8)
} 'exist|new|immutable|overwrite'
foreach ($artifact in @('audit', 'audit-context.json')) {
    Assert-WorkflowAuditRejected ("aliased-output-" + $artifact.Replace('.', '-')) {
        param($case)
        $target = Join-Path $case.evidenceRoot 'alias-destination'
        [void][IO.Directory]::CreateDirectory($target)
        $link = Join-Path $case.evidenceRoot $artifact
        New-WorkflowAuditTestLink $link $target
        $case.links.Add($link)
    } 'alias|redirect'
}
Assert-WorkflowAuditRejected 'capture-at-audit-path' { param($case) } 'exist|capture|overlap|separat|outside|new' -CaptureName 'audit'
Assert-WorkflowAuditRejected 'capture-under-audit-path' { param($case) } 'exist|capture|overlap|separat|outside|new' -CaptureName 'audit/source'
Assert-WorkflowAuditRejected 'aliased-source-outside-evidence' {
    param($case)
    $outside = Join-Path $OutputRoot 'outside-source-copy'
    Copy-Item -LiteralPath $case.fixture.Root -Destination $outside -Recurse
    $link = Join-Path $case.evidenceRoot 'source-link'
    New-WorkflowAuditTestLink $link $outside
    $case.links.Add($link)
    $descriptor = Read-SwiftUIAuditTestSmallJson $case.descriptorPath
    $descriptor.path = 'source-link'
    $descriptor.manifestPath = 'source-link/capture.json'
    $descriptor.statusPath = 'source-link/capture-status.json'
    $descriptor.inventoryPath = 'source-link/inventory.json'
    Write-SwiftUIBaselineJson $descriptor $case.descriptorPath
} 'contain|outside|alias|resolv'
Assert-WorkflowAuditRejected 'aliased-result-outside-evidence' {
    param($case)
    $outside = Join-Path $OutputRoot 'outside-descriptor-copy'
    [void][IO.Directory]::CreateDirectory($outside)
    Copy-Item -LiteralPath $case.descriptorPath -Destination (Join-Path $outside 'export-result.json')
    $link = Join-Path $case.evidenceRoot 'result-link'
    New-WorkflowAuditTestLink $link $outside
    $case.links.Add($link)
    $case.argumentPath = Join-Path $link 'export-result.json'
} 'contain|outside|alias|resolv'

$workflow = Read-WorkflowAuditText $workflowPath
$steps = @([regex]::Matches($workflow, '(?ms)^ {6}- name: [^\r\n]+\r?\n.*?(?=^ {6}- name:|\z)'))
foreach ($step in $steps) {
    $runBlock = [regex]::Match($step.Value, '(?ms)^ {8}run: \|[ \t]*\r?\n(?<code>.*)\z')
    $runLine = [regex]::Match($step.Value, '(?m)^ {8}run: (?!\|)(?<code>[^\r\n]+)')
    if (-not $runBlock.Success -and -not $runLine.Success) { continue }
    $code = if ($runBlock.Success) { $runBlock.Groups['code'].Value -replace '(?m)^ {10}', '' } else { $runLine.Groups['code'].Value }
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tokens, [ref]$errors)
    Assert-WorkflowAudit ($errors.Count -eq 0) 'the complete workflow PowerShell run block parses without executing native commands'
}
function Get-WorkflowAuditStep {
    param([string]$Pattern)
    $matching = @($steps | Where-Object { $_.Value -match $Pattern })
    Assert-WorkflowAudit ($matching.Count -eq 1) "workflow has exactly one step matching $Pattern"
    return $matching[0]
}
$checkoutStep = Get-WorkflowAuditStep 'uses: actions/checkout@'
$rgbFixtureStep = Get-WorkflowAuditStep '(?m)^ {8}run: \./scripts/test-swiftui-color-rgb-reference\.ps1\r?$'
$exportStep = Get-WorkflowAuditStep '(?m)^\s+id: sdk-export\s*$'
$materialStep = Get-WorkflowAuditStep 'run: \./scripts/capture-swiftui-material-reference\.ps1'
$ledgerStep = Get-WorkflowAuditStep '\./scripts/build-swiftui-api-audit-candidate\.ps1'
$rgbStep = Get-WorkflowAuditStep 'run: \./scripts/capture-swiftui-color-rgb-reference\.ps1'
$uploadStep = Get-WorkflowAuditStep 'uses: actions/upload-artifact@'
Assert-WorkflowAudit ($checkoutStep.Value -cmatch '(?m)^ {8}uses: actions/checkout@v4\r?$') 'checkout retains its existing action version'
Assert-WorkflowAudit ($checkoutStep.Value -cmatch '(?m)^ {10}ref: \$\{\{ github\.sha \}\}\r?$') 'checkout explicitly selects the exact event commit for both RGB observers'
Assert-WorkflowAudit ($checkoutStep.Value -cmatch '(?m)^ {10}persist-credentials: false\r?$' -and
    $checkoutStep.Value -cmatch '(?m)^ {10}submodules: false\r?$') 'checkout retains both credential and submodule safety options'
Assert-WorkflowAudit ($checkoutStep.Index -lt $rgbFixtureStep.Index -and $rgbFixtureStep.Index -lt $exportStep.Index) 'exactly one RGB synthetic suite runs before any SDK export'
Assert-WorkflowAudit ($exportStep.Index -lt $materialStep.Index -and $materialStep.Index -lt $ledgerStep.Index -and $ledgerStep.Index -lt $uploadStep.Index) 'ledger follows material capture and precedes the always-upload step'
Assert-WorkflowAudit ($ledgerStep.Index -lt $rgbStep.Index -and $rgbStep.Index -lt $uploadStep.Index) 'native RGB collection follows the complete audit and precedes the existing upload'
Assert-WorkflowAudit ($ledgerStep.Value -cmatch '(?m)^ {8}id: api-audit\r?$') 'the complete ledger exposes its actual outcome as api-audit'
$condition = [regex]::Match($ledgerStep.Value, '(?ms)^ {8}if:\s*(?<condition>.*?)(?=^ {8}(?:env|run|timeout-minutes|with):|\z)').Groups['condition'].Value
Assert-WorkflowAudit ($condition -cmatch '!cancelled\(\)') 'ledger gate explicitly skips cancellation without the implicit previous-step success rule'
Assert-WorkflowAudit ($condition -cmatch 'steps\.sdk-export\.outcome\s*==\s*''success''') 'ledger requires the actual SDK export step to succeed'
Assert-WorkflowAudit ($condition -cmatch 'steps\.sdk-export\.outputs\.capture-status\s*==\s*''exported-awaiting-review''') 'ledger requires the exact successful candidate status output'
Assert-WorkflowAudit ($condition -cnotmatch '(?<![A-Za-z])success\s*\(') 'an independent material failure cannot suppress a valid SDK ledger'
$expectedExportGate = "!cancelled() && steps.sdk-export.outcome == 'success' && steps.sdk-export.outputs.capture-status == 'exported-awaiting-review'"
Assert-WorkflowAudit ($condition.Trim() -ceq ('${{ ' + $expectedExportGate + ' }}')) 'the existing complete-audit condition remains unchanged'
$rgbConditions = @([regex]::Matches($rgbStep.Value, '(?m)^ {8}if: \$\{\{ (?<condition>[^\r\n]+) \}\}\r?$'))
Assert-WorkflowAudit ($rgbConditions.Count -eq 1) 'native RGB collection has one explicit workflow condition'
$rgbCondition = $rgbConditions[0].Groups['condition'].Value
Assert-WorkflowAudit ($rgbCondition -ceq ($expectedExportGate + " && steps.api-audit.outcome == 'success'")) 'RGB requires a complete SDK export and audit without default-success or material-success gates'
Assert-WorkflowAudit ($workflow -cnotmatch '(?m)^\s+continue-on-error:') 'material, audit, and RGB failures keep their original step and job outcomes'
# Translate only the exact expression asserted above, never arbitrary workflow
# code. These cases exercise the checked-in predicate rather than a second gate.
$rgbGateCode = $rgbCondition.Replace('!cancelled()', '(-not $State.cancelled)').
    Replace('steps.sdk-export.outcome', '$State.exportOutcome').
    Replace('steps.sdk-export.outputs.capture-status', '$State.captureStatus').
    Replace('steps.api-audit.outcome', '$State.auditOutcome').
    Replace(' == ', ' -eq ').Replace(' && ', ' -and ')
$rgbGateBlock = [scriptblock]::Create('param($State)' + [Environment]::NewLine + $rgbGateCode)
foreach ($gateCase in @(
    @{ name = 'successful export and audit'; expected = $true },
    @{ name = 'cancelled job'; cancelled = $true; expected = $false },
    @{ name = 'failed SDK export'; exportOutcome = 'failure'; expected = $false },
    @{ name = 'wrong SDK capture status'; captureStatus = 'failed'; expected = $false },
    @{ name = 'failed audit'; auditOutcome = 'failure'; expected = $false },
    @{ name = 'skipped audit'; auditOutcome = 'skipped'; expected = $false },
    @{ name = 'material failure after successful SDK export'; materialOutcome = 'failure'; expected = $true }
)) {
    $state = @{
        cancelled = $false; exportOutcome = 'success'; captureStatus = 'exported-awaiting-review'
        auditOutcome = 'success'; materialOutcome = 'success'
    }
    foreach ($key in $gateCase.Keys) {
        if ($state.ContainsKey($key)) { $state[$key] = $gateCase[$key] }
    }
    $actual = & $rgbGateBlock ([pscustomobject]$state)
    Assert-WorkflowAudit ($actual -eq $gateCase.expected) ("actual RGB condition handles " + $gateCase.name)
}
$resultParameter = [regex]::Match($ledgerStep.Value, '-ExportResultPath\s+\$env:(?<name>[A-Za-z_][A-Za-z_0-9]*)')
Assert-WorkflowAudit ($resultParameter.Success) 'ledger takes the explicit result file through an environment argument'
Assert-WorkflowAudit ($ledgerStep.Value -cmatch ('(?m)^\s+' + [regex]::Escape($resultParameter.Groups['name'].Value) + ':\s*\$\{\{\s*steps\.sdk-export\.outputs\.export-result-path\s*\}\}')) 'result argument is bound to the successful export step output'
Assert-WorkflowAudit ($ledgerStep.Value.Contains('artifacts/swiftui-baseline/github-actions') -and $ledgerStep.Value.Contains('-EvidenceRoot')) 'ledger evidence root is explicit and fixed under repository artifacts'
Assert-WorkflowAudit ($ledgerStep.Value -cmatch '(?m)^\s+timeout-minutes: 20\s*$') 'ledger retains its explicit 20-minute step budget'
$ledgerRun = [regex]::Match($ledgerStep.Value, '(?ms)^ {8}run: \|\r?\n(?<code>.*)\z').Groups['code'].Value.Trim()
Assert-WorkflowAudit ($ledgerRun -ceq './scripts/build-swiftui-api-audit-candidate.ps1 -ExportResultPath $env:SWIFTUI_EXPORT_RESULT_PATH -EvidenceRoot (Join-Path $env:GITHUB_WORKSPACE "artifacts/swiftui-baseline/github-actions")') 'the complete-audit command remains unchanged without outcome suppression'
Assert-WorkflowAudit ($materialStep.Value -cmatch '(?m)^ {8}timeout-minutes: 15\r?$') 'material capture retains its 15-minute step budget'
Assert-WorkflowAudit ($materialStep.Value -cnotmatch '(?m)^ {8}if:') 'material capture retains its original default workflow gate'
Assert-WorkflowAudit ($materialStep.Value -cmatch '(?m)^ {8}run: \./scripts/capture-swiftui-material-reference\.ps1 -CaptureRoot \$env:SWIFTUI_CAPTURE_ROOT -HostingContextExperiment\r?$') 'the existing material hosting experiment invocation remains unchanged'
Assert-WorkflowAudit ($rgbStep.Value -cmatch '(?m)^ {8}id: rgb-native\r?$' -and
    $rgbStep.Value -cmatch '(?m)^ {8}timeout-minutes: 32\r?$') 'native RGB collection has an independent identity and a 32-minute step budget'
Assert-WorkflowAudit ($rgbStep.Value -cmatch '(?m)^ {10}SWIFTUI_CAPTURE_ROOT: \$\{\{ steps\.sdk-export\.outputs\.capture-root \}\}\r?$') 'native RGB uses the explicit successful SDK capture output'
$rgbRunLines = @([regex]::Matches($rgbStep.Value, '(?m)^ {8}run: (?<code>[^\r\n]+)\r?$'))
Assert-WorkflowAudit ($rgbRunLines.Count -eq 1 -and $rgbRunLines[0].Groups['code'].Value -ceq './scripts/capture-swiftui-color-rgb-reference.ps1 -Platform Native -CaptureRoot $env:SWIFTUI_CAPTURE_ROOT -OutputPath (Join-Path $env:GITHUB_WORKSPACE "artifacts/swiftui-baseline/github-actions/color-rgb-native")') 'RGB collects Native into a new sibling without precreation, retry, fallback, or exit translation'
foreach ($name in @('capture-status', 'capture-root', 'export-result-path')) {
    Assert-WorkflowAudit ($exportStep.Value -cmatch ('[''"]' + [regex]::Escape($name) + '[''"]\s*=')) "export declares the explicit $name workflow output"
}
Assert-WorkflowAudit ($exportStep.Value.Contains('AppendAllText($env:GITHUB_OUTPUT')) 'export writes declared outputs through the explicit GitHub output file'
Assert-WorkflowAudit ($workflow -cmatch '(?m)^\s+runs-on: macos-26-intel\s*$') 'native SDK runner remains pinned'
Assert-WorkflowAudit ($workflow -cmatch '(?m)^\s+DEVELOPER_DIR: /Applications/Xcode_26\.6\.app/Contents/Developer\s*$') 'native Xcode pin cannot silently move'
Assert-WorkflowAudit ($workflow -cmatch '(?m)^ {4}timeout-minutes: 90\s*$') 'whole job budget remains explicit'
Assert-WorkflowAudit ($workflow.Contains('"scripts/build-swiftui-api-audit-candidate.ps1"')) 'candidate runtime changes trigger a new workflow run'
$pushPaths = [regex]::Match($workflow, '(?ms)^ {2}push:\r?\n.*?^ {4}paths:\r?\n(?<paths>(?:^ {6}- [^\r\n]+\r?\n)+)').Groups['paths'].Value
foreach ($path in @('Sources/swiftui-color-rgb-reference/**', 'scripts/capture-swiftui-color-rgb-reference.ps1',
    'scripts/swiftui-color-rgb-reference-common.ps1', 'scripts/compare-swiftui-color-rgb-reference.ps1',
    'scripts/test-swiftui-color-rgb-reference.ps1')) {
    $entries = @([regex]::Matches($pushPaths, ('(?m)^ {6}- "' + [regex]::Escape($path) + '"\r?$')))
    Assert-WorkflowAudit ($entries.Count -eq 1) "the push filter includes exactly one RGB input path: $path"
}
Assert-WorkflowAudit ($workflow -cmatch '(?m)^\s+run: \./scripts/test-swiftui-api-audit-workflow\.ps1\s*$') 'workflow executes this portable synthetic handoff test'
Assert-WorkflowAudit ($uploadStep.Value -cmatch 'if:\s*(?:\$\{\{\s*)?always\(\)') 'raw capture and diagnostics upload after any step failure'
Assert-WorkflowAudit ($uploadStep.Value -cmatch '(?m)^ {8}if: always\(\)\r?$') 'the original always-upload condition has no additional gate'
Assert-WorkflowAudit ($uploadStep.Value -cmatch '(?m)^\s+include-hidden-files: true\s*$') 'upload retains hidden evidence files'
Assert-WorkflowAudit ($uploadStep.Value -cmatch '(?m)^\s+if-no-files-found: error\s*$') 'an entirely missing evidence root fails upload'
Assert-WorkflowAudit ($uploadStep.Value -cmatch '(?m)^ {10}retention-days: 30\r?$') 'candidate evidence retains the existing 30-day upload retention'
Assert-WorkflowAudit ($uploadStep.Value -cmatch '(?m)^ {10}name: swiftui-macos-26\.5-xcode-26\.6-candidate-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}\r?$') 'the evidence artifact remains tied to its explicit workflow run and attempt'
$uploadPaths = [regex]::Match($uploadStep.Value, '(?ms)^ {10}path:\s*\|\s*\r?\n(?<paths>(?:^ {12}[^\r\n]*\r?\n?)+)').Groups['paths'].Value
$pathEntries = @($uploadPaths -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
Assert-WorkflowAudit ($pathEntries.Count -eq 2 -and $pathEntries -ccontains 'artifacts/swiftui-baseline/github-actions/' -and
    $pathEntries -ccontains '!artifacts/swiftui-baseline/github-actions/capture/module-cache/**') 'the complete raw capture and all ledger records upload; only module cache is excluded'

$preflightMatch = [regex]::Match($workflow, '(?ms)^ {10}# Candidate path preflight\.\r?\n(?<code>.*?)^ {10}# End candidate path preflight\.')
Assert-WorkflowAudit $preflightMatch.Success 'workflow provides a separately testable filesystem preflight'
$preflightCode = $preflightMatch.Groups['code'].Value -replace '(?m)^ {10}', ''
Assert-WorkflowAudit (-not $preflightCode.Contains('export-swiftui-baseline.ps1') -and -not $preflightCode.Contains('Invoke-SwiftUIBaselineNativeCommand')) 'extracted preflight contains no native export invocation'
$preflightBlock = [scriptblock]::Create($preflightCode)
function Invoke-WorkflowAuditPreflight {
    param([string]$Workspace)
    $previous = [Environment]::GetEnvironmentVariable('GITHUB_WORKSPACE', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('GITHUB_WORKSPACE', $Workspace, 'Process')
        & $preflightBlock | Out-Null
    } finally { [Environment]::SetEnvironmentVariable('GITHUB_WORKSPACE', $previous, 'Process') }
}
function New-WorkflowAuditWorkspace {
    param([string]$Name)
    $workspace = Join-Path $OutputRoot ("preflight-$Name")
    [void][IO.Directory]::CreateDirectory((Join-Path $workspace 'scripts'))
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'scripts/swiftui-baseline-common.ps1') -Destination (Join-Path $workspace 'scripts/swiftui-baseline-common.ps1')
    return $workspace
}
$workspace = New-WorkflowAuditWorkspace 'new'
Invoke-WorkflowAuditPreflight $workspace
Assert-WorkflowAudit $true 'preflight accepts a new contained candidate location'
$workspace = New-WorkflowAuditWorkspace 'existing-empty'
[void][IO.Directory]::CreateDirectory((Join-Path $workspace 'artifacts/swiftui-baseline/github-actions'))
$caught = $null
try { Invoke-WorkflowAuditPreflight $workspace } catch { $caught = $_ }
Assert-WorkflowAudit ($null -ne $caught) 'preflight rejects even empty pre-existing evidence before export'
foreach ($component in @('artifacts', 'artifacts/swiftui-baseline', 'artifacts/swiftui-baseline/github-actions', 'artifacts/swiftui-baseline/github-actions/capture')) {
    $slug = $component.Replace('/', '-')
    $workspace = New-WorkflowAuditWorkspace $slug
    $outside = Join-Path $OutputRoot ("preflight-outside-$slug")
    [void][IO.Directory]::CreateDirectory($outside)
    [IO.File]::WriteAllText((Join-Path $outside 'sentinel.txt'), 'SYNTHETIC outside target must remain unchanged.', $utf8)
    $beforeOutside = Get-WorkflowAuditTreeHash $outside
    $link = Join-Path $workspace $component
    New-WorkflowAuditTestLink $link $outside
    try {
        $caught = $null
        try { Invoke-WorkflowAuditPreflight $workspace } catch { $caught = $_ }
        Assert-WorkflowAudit ($null -ne $caught) "preflight rejects an alias at $component before native writes"
        Assert-WorkflowAudit ((Get-WorkflowAuditTreeHash $outside) -ceq $beforeOutside) "preflight never writes through the $component alias"
    } finally { Remove-WorkflowAuditTestLink $link }
}

Write-Host "API audit workflow tests passed $($script:WorkflowAssertions) assertions using synthetic captures and filesystem preflights only."
[pscustomobject]@{ assertions = $script:WorkflowAssertions; runtime = $PSVersionTable.PSVersion.ToString(); path = $OutputRoot; nativeExportPerformed = $false }
