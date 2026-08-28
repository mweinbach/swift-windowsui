<#
.SYNOPSIS
Exercises Stage A overlay discovery against owned synthetic artifacts and an
in-memory Unix filesystem. No Mac SDK, native compiler, SwiftPM or load probe
runs. The existing managed metadata/ledger helper may compile in this process.
#>
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot), [string]$OutputRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $RepositoryRoot 'scripts/swiftui-overlay-discovery-common.ps1')
. (Join-Path $RepositoryRoot 'scripts/swiftui-api-audit-test-fixtures.ps1')
. (Join-Path $RepositoryRoot 'scripts/fixtures/swiftui-overlay-discovery/fake-filesystem.ps1')
if ([string]::IsNullOrEmpty($OutputRoot)) {
    $OutputRoot = Join-Path $RepositoryRoot ('artifacts/swiftui-overlay-discovery-tests/' + [Guid]::NewGuid().ToString('N'))
}
$OutputRoot = Resolve-SwiftUIAuditTestRoot $OutputRoot
if (Test-Path -LiteralPath $OutputRoot) { throw 'Synthetic overlay test output must be new and owned.' }
[void][IO.Directory]::CreateDirectory($OutputRoot)
$script:OverlayAssertions = 0
$script:OverlayCases = [Collections.Generic.List[object]]::new()
$script:OverlayPlannedCases = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$baseline = Join-Path $RepositoryRoot 'docs/swiftui-baseline.json'
$caseRoot = Join-Path $OutputRoot 'cases'
[void][IO.Directory]::CreateDirectory($caseRoot)

function Assert-OverlayTest {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw "Overlay discovery assertion failed: $Message" }
    $script:OverlayAssertions++
}
function Get-OverlayTestHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-OverlayTestJson {
    param([string]$Path)
    if ((Get-Item -LiteralPath $Path).Length -gt 8MB) { throw 'Test JSON helper accepts only small owned synthetic files.' }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Read-OverlayTestRows {
    param([string]$Path)
    if ((Get-Item -LiteralPath $Path).Length -gt 8MB) { throw 'Test row helper accepts only small owned synthetic files.' }
    return @(Get-Content -LiteralPath $Path -Encoding UTF8 | Where-Object { $_.Length -gt 0 } | ForEach-Object { $_ | ConvertFrom-Json })
}
function Write-OverlayTestJson {
    param([string]$Path, $Value)
    [void](Get-SwiftUIBaselineRelativePath $OutputRoot $Path)
    [IO.File]::WriteAllText($Path, ((ConvertTo-Json -InputObject $Value -Depth 40) + [char]10), $utf8)
}
function Add-OverlayTestCase {
    param([string]$Name, [string]$PlannedId, [string]$Outcome, $Extra)
    [void]$script:OverlayPlannedCases.Add($PlannedId)
    [void]$script:OverlayCases.Add([pscustomobject]@{ name = $Name; plannedCaseId = $PlannedId; outcome = $Outcome; details = $Extra })
}
function Assert-OverlayThrows {
    param([scriptblock]$Action, [string]$Message)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-OverlayTest ($null -ne $caught) $Message
    return $caught
}
function Assert-OverlayFakeDisposed {
    param($Provider, [string]$Name)
    Assert-OverlayTest ($Provider.state.activeEnumerations -eq 0) "$Name disposes every fake enumeration"
    foreach ($stream in $Provider.state.openedStreams) { Assert-OverlayTest (-not $stream.CanRead) "$Name disposes each owned source stream" }
}
function Invoke-OverlayCase {
    param([string]$Name, [string]$PlannedId, [scriptblock]$Mutate = {},
        [scriptblock]$MutatePlan = {}, [bool]$ExpectComplete = $true,
        [switch]$ExpectPlanRejection, [scriptblock]$Inspect = {})
    $directory = Join-Path $caseRoot $Name
    if (Test-Path -LiteralPath $directory) { throw 'Duplicate synthetic case destination.' }
    [void][IO.Directory]::CreateDirectory($directory)
    $provider = New-SwiftUIOverlayFakeProvider -SourceContext $sourceContext
    $plan = New-SwiftUIOverlayFakeRootPlan -SourceContext $sourceContext
    & $Mutate $provider $plan | Out-Null
    & $MutatePlan $plan | Out-Null
    $planPath = Join-Path $directory 'requested-roots.json'
    Write-OverlayTestJson $planPath $plan
    $output = Join-Path $directory 'census'
    $result = $null; $read = $null; $caught = $null
    try {
        $validatedPlan = Read-SwiftUIOverlayRootPlan -Path $planPath -ExpectedSha256 (Get-OverlayTestHash $planPath) -SourceContext $sourceContext
        $result = Invoke-SwiftUIOverlayCensus -SourceContext $sourceContext -RootPlanContext $validatedPlan -Provider $provider -OutputDirectory $output
    } catch { $caught = $_ }
    if ($ExpectPlanRejection) {
        Assert-OverlayTest ($null -ne $caught) "$Name refuses invalid authorization"
        Assert-OverlayTest (-not (Test-Path -LiteralPath $output)) "$Name does not create census output"
        Assert-OverlayTest ($provider.state.trace.Count -eq 0) "$Name performs no fake SDK access"
    } else {
        if ($null -ne $caught) { throw $caught }
        Assert-OverlayTest ($result.complete -eq $ExpectComplete) "$Name has the expected complete/incomplete outcome"
        $read = Read-SwiftUIOverlayDiscoveryReport -Root $output -ExpectedManifestSha256 $result.manifestSha256 -AllowSyntheticForTests -AllowIncompleteForDiagnostics
        Assert-OverlayTest ($read.report.syntheticFixture) "$Name stays explicitly synthetic"
        Assert-OverlayTest (-not $read.report.observationInterval.observationAtomic) "$Name does not claim an atomic snapshot"
        Assert-OverlayTest (-not $read.report.observationInterval.wholeInstallationByteIdentityEstablished) "$Name does not claim historic whole-SDK identity"
        Assert-OverlayTest (-not $read.report.observationInterval.nativeCommandsExecuted) "$Name performs no native SDK command"
        Assert-OverlayTest (-not $read.report.qualification.overlayCompleteness -and -not $read.report.qualification.behaviorConformance) "$Name leaves qualification unverified"
        Assert-OverlayTest ($read.report.recordStreams.Count -eq 6) "$Name preserves all six new streams"
        Assert-OverlayTest ((Get-OverlayTestHash (Join-Path $output 'root-plan.json')) -ceq (Get-OverlayTestHash $planPath)) "$Name retains exact root-plan bytes"
        foreach ($stream in $read.report.recordStreams) {
            $rows = @(Read-OverlayTestRows (Join-Path $output $stream.path))
            Assert-OverlayTest ($rows.Count -eq $stream.recordCount) "$Name records the actual row count for $($stream.path)"
        }
        if (-not $ExpectComplete) {
            Assert-OverlayTest ($null -eq $read.report.coverage.noDefinitionsObservedInRecordedRoots) "$Name never turns incomplete observation into zero definitions"
            [void](Assert-OverlayThrows { Read-SwiftUIOverlayDiscoveryReport -Root $output -ExpectedManifestSha256 $result.manifestSha256 -AllowSyntheticForTests } "$Name is ineligible without diagnostic-only mode")
        }
        & $Inspect $result $read $provider $plan $directory | Out-Null
    }
    Assert-OverlayFakeDisposed $provider $Name
    Add-OverlayTestCase $Name $PlannedId $(if ($ExpectPlanRejection) { 'rejected-before-observation' } elseif ($ExpectComplete) { 'complete-synthetic' } else { 'incomplete-synthetic' }) $result
    return [pscustomobject]@{ result = $result; read = $read; provider = $provider; plan = $plan; directory = $directory }
}

$failure = $null
try {
    $parserPath = Join-Path $RepositoryRoot 'scripts/fixtures/swiftui-overlay-discovery/parser-cases.json'
    $parser = Read-OverlayTestJson $parserPath
    Assert-OverlayTest ($parser.syntheticFixture -and $parser.parserProfile -ceq 'swiftcrossimport-canonical-v1') 'parser fixtures are explicitly synthetic/profile-bound'
    foreach ($case in $parser.cases) {
        if ($null -ne $case.base64) { $bytes = [Convert]::FromBase64String($case.base64) }
        else { $bytes = $utf8.GetBytes($case.text) }
        $before = [Convert]::ToBase64String($bytes)
        $arguments = @{ Bytes = $bytes }
        if ($null -ne $case.limits) { foreach ($property in $case.limits.PSObject.Properties) { $arguments[$property.Name] = $property.Value } }
        $parsed = ConvertFrom-SwiftUIOverlayDefinition @arguments
        Assert-OverlayTest ($parsed.status -ceq $case.expectedStatus) "parser $($case.id) has the independently specified status"
        $actualNames = @($parsed.nameOccurrences | ForEach-Object { $_.name })
        Assert-OverlayTest (($actualNames -join '|') -ceq ($case.expectedNames -join '|')) "parser $($case.id) preserves expected ordered names"
        Assert-OverlayTest ([Convert]::ToBase64String($bytes) -ceq $before) "parser $($case.id) never changes raw bytes"
        for ($index = 0; $index -lt $parsed.nameOccurrences.Count; $index++) {
            Assert-OverlayTest ($parsed.nameOccurrences[$index].index -eq $index) "parser $($case.id) preserves duplicate occurrence indices"
        }
        if ($parsed.status -cne 'parsed-canonical-v1') {
            Assert-OverlayTest ($parsed.nameOccurrences.Count -eq 0 -and $parsed.issues.Count -gt 0) "parser $($case.id) never presents partial parsing as success"
        }
        Add-OverlayTestCase ('parser-' + $case.id) $case.plannedCaseId 'passed' $null
    }

    # One small shared fixture per fresh test process. This is the existing
    # synthetic producer/managed ledger writer, not a native export or a stress
    # rerun of the unrelated Directory.Move diagnostics.
    $fixture = New-SwiftUIAuditTestCapture -Root (Join-Path $OutputRoot 'source-capture') -ManifestPath $baseline
    $auditRoot = Join-Path $OutputRoot 'source-audit'
    & (Join-Path $RepositoryRoot 'scripts/build-swiftui-api-audit.ps1') -CaptureRoot $fixture.Root -OutputDirectory $auditRoot -ManifestPath $baseline -SortChunkBytes 4096 -MergeFanIn 2 | Out-Null
    $sourceContext = Read-SwiftUIOverlayDiscoveryInputs -CaptureRoot $fixture.Root -AuditRoot $auditRoot -ManifestPath $baseline -AllowSyntheticForTests
    Assert-OverlayTest ($sourceContext.syntheticFixture) 'successful synthetic source stays synthetic'
    $sourceBefore = @($sourceContext.fileSeals | ForEach-Object { $_.path + [char]9 + (Get-OverlayTestHash $_.path) }) -join ([string][char]10)

    $empty = Invoke-OverlayCase -Name 'empty-census' -PlannedId 'empty-directory' -Inspect {
        param($result, $read, $provider)
        Assert-OverlayTest ($read.report.coverage.noDefinitionsObservedInRecordedRoots -eq $true) 'empty census records only scoped zero'
        Assert-OverlayTest ($read.report.coverage.overlayCompleteness -ceq 'unverified') 'scoped zero is not overlay completeness'
        Assert-OverlayTest ($read.report.counts.definitions -eq 0) 'empty census has no invented definition'
        Assert-OverlayTest (@($provider.state.trace | Where-Object { $_.path -eq '/System' }).Count -eq 0) 'empty census never visits arbitrary host roots'
    }
    $populated = Invoke-OverlayCase -Name 'hidden-reverse-and-duplicates' -PlannedId 'reverse-bystander' -Mutate {
        param($provider, $plan)
        $sdk = @($plan.roots | Where-Object { $_.rootId -ceq 'selected-sdk' })[0].logicalPath
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/.hidden/Other.swiftcrossimport/SwiftUI.swiftoverlay') -Kind file -Text ("version: 1" + [char]10 + "modules:" + [char]10 + "  - name: _Repeated" + [char]10 + "  - name: _Repeated" + [char]10 + "  - name: PublicOverlay" + [char]10))
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/.hidden/Other.swiftcrossimport/arm64e-apple-ios-macabi/SwiftUICore.swiftoverlay') -Kind file -Text ("version: 1" + [char]10 + "modules: []" + [char]10))
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/Headers/module.modulemap') -Kind file -Text 'framework module Other { export * } // exact unknown map grammar retained')
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/Empty.swiftcrossimport') -Kind directory)
    } -Inspect {
        param($result, $read)
        $definitions = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'definition-facts.ndjson') | Where-Object { $_.kind -ceq 'definition-file' })
        Assert-OverlayTest ($definitions.Count -eq 2) 'both global and other-target definitions remain'
        Assert-OverlayTest (@($definitions | Where-Object { $_.logicalPath.Contains('/.hidden/') }).Count -eq 2) 'hidden definitions are retained'
        $repeated = @($definitions | Where-Object { $_.nameOccurrences.Count -eq 3 })[0]
        Assert-OverlayTest (($repeated.nameOccurrences.name -join '|') -ceq '_Repeated|_Repeated|PublicOverlay') 'duplicate and nonunderscore names are not filtered'
        $candidates = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'candidate-pairs.ndjson'))
        Assert-OverlayTest ($candidates.Count -eq 4) 'every definition gets both unreviewed target contexts'
        Assert-OverlayTest (@($candidates | Where-Object { $_.selectionReasons -contains 'reverse-bystander-seed' }).Count -eq 4) 'reverse bystanders are recognized without pruning'
        Assert-OverlayTest (@($candidates | Where-Object { $null -ne $_.targetVariant }).Count -eq 0) 'macabi source locations do not invent target variants'
        Assert-OverlayTest ($read.report.counts.moduleMaps -eq 1) 'module map raw bytes are retained without grammar claims'
    }
    [void]$script:OverlayPlannedCases.Add('hidden-files')
    [void]$script:OverlayPlannedCases.Add('all-platform-context')
    [void]$script:OverlayPlannedCases.Add('raw-unknown-preservation')

    [void](Invoke-OverlayCase -Name 'unknown-definition' -PlannedId 'raw-unknown-preservation' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $sdk = @($plan.roots | Where-Object { $_.rootId -ceq 'selected-sdk' })[0].logicalPath
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/Unknown.swiftcrossimport/SwiftUI.swiftoverlay') -Kind file -Text ("version: 1" + [char]10 + "modules: [{ name: '_Unknown' }]" + [char]10 + "future-key: exact-raw-data"))
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.counts.unsupportedDefinitions -eq 1) 'unknown profile syntax makes the census incomplete'
        Assert-OverlayTest ($read.report.copiedFiles.Count -eq 1 -and $read.report.copiedFiles[0].captureComplete) 'unsupported definition bytes remain whole and sealed'
        $candidates = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'candidate-pairs.ndjson'))
        Assert-OverlayTest (@($candidates | Where-Object { $null -ne $_.expectedOverlayNameOccurrences }).Count -eq 0) 'unknown definition is not reinterpreted as a known empty module list'
    })
    [void](Invoke-OverlayCase -Name 'refuse-incidental-metadata-without-ack' -PlannedId 'parent-lookup-authorization' -ExpectPlanRejection -MutatePlan { param($plan) $plan.allowIncidentalLinkTargetMetadata = $false })
    [void](Invoke-OverlayCase -Name 'refuse-physical-filesystem-root' -PlannedId 'root-physical-mismatch' -ExpectPlanRejection -MutatePlan { param($plan) $plan.roots[0].expectedPhysicalPath = '/'; $plan.roots[0].allowedPhysicalBoundary = '/' })
    [void](Invoke-OverlayCase -Name 'missing-target-context' -PlannedId 'missing-target-or-stream' -ExpectPlanRejection -MutatePlan { param($plan) $plan.targetContexts = @($plan.targetContexts[0]) })
    [void](Invoke-OverlayCase -Name 'duplicate-target-context' -PlannedId 'missing-target-or-stream' -ExpectPlanRejection -MutatePlan { param($plan) $plan.targetContexts = @($plan.targetContexts[0], $plan.targetContexts[0]) })
    [void](Invoke-OverlayCase -Name 'invented-target-variant' -PlannedId 'all-platform-context' -ExpectPlanRejection -MutatePlan { param($plan) $plan.targetContexts[0].targetVariant = 'arm64e-apple-ios-macabi' })
    [void](Invoke-OverlayCase -Name 'stale-root-source-hash' -PlannedId 'wrong-or-stale-seal' -ExpectPlanRejection -MutatePlan { param($plan) $plan.sourceAuditSha256 = ('0' * 64) })
    [void]$script:OverlayPlannedCases.Add('optional-root-omitted')

    [void](Invoke-OverlayCase -Name 'required-sdk-absent' -PlannedId 'required-root-absent' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $sdk = $plan.roots[0].logicalPath
        foreach ($path in @($provider.state.nodes.Keys)) {
            if (Test-SwiftUIOverlayInside $sdk $path) { [void]$provider.state.nodes.Remove($path) }
        }
    } -Inspect {
        param($result, $read, $provider)
        Assert-OverlayTest ($read.report.roots[0].state -ceq 'absent-confirmed') 'missing SDK needs completed readable parent evidence'
        Assert-OverlayTest (@($provider.state.trace | Where-Object { $_.operation -ceq 'openRead' }).Count -eq 0) 'missing required SDK prevents anchor/content reads'
    })
    [void](Invoke-OverlayCase -Name 'sdk-inaccessible' -PlannedId 'permission-error' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $sdk = $plan.roots[0].logicalPath
        $provider.state.onGetInfo = {
            param($path, $state, $event)
            if ($path -ceq $sdk -and $event.phase -ceq 'before') { throw [UnauthorizedAccessException]::new('SYNTHETIC denied root') }
        }.GetNewClosure()
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.roots[0].state -cne 'absent-confirmed') 'denied root never becomes absent'
        $issues = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'issues.ndjson'))
        Assert-OverlayTest (@($issues.causes | Where-Object { $_.exceptionType -match 'UnauthorizedAccessException' }).Count -gt 0) 'error receipt preserves underlying access-denied type'
    })
    [void](Invoke-OverlayCase -Name 'partial-root-enumeration' -PlannedId 'mid-enumeration-error' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $sdk = $plan.roots[0].logicalPath
        $provider.state.onEnumerate = {
            param($path, $state, $event)
            if ($path -ceq $sdk -and $event.phase -ceq 'after-entry') { throw [IO.IOException]::new('SYNTHETIC error after one yielded entry') }
        }.GetNewClosure()
    } -Inspect {
        param($result, $read, $provider)
        $rows = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'filesystem-facts.ndjson'))
        Assert-OverlayTest (@($rows | Where-Object { $_.kind -ceq 'directory-entry-name' }).Count -gt 0) 'earlier yielded names survive a later enumeration error'
        Assert-OverlayTest (@($rows | Where-Object { $_.kind -ceq 'directory-incomplete' }).Count -gt 0) 'partial enumeration retains explicit incomplete state'
        Assert-OverlayTest ($provider.state.enumerationsOpened -eq $provider.state.countDisposed) 'partial enumeration closes every opened iterator'
    })
    [void](Invoke-OverlayCase -Name 'partial-absence-parent' -PlannedId 'mid-enumeration-error' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $sdk = $plan.roots[0].logicalPath
        foreach ($path in @($provider.state.nodes.Keys)) { if (Test-SwiftUIOverlayInside $sdk $path) { [void]$provider.state.nodes.Remove($path) } }
        $parent = Get-SwiftUIOverlayUnixParent $sdk
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($parent + '/UnrelatedName') -Kind directory)
        $provider.state.onEnumerate = {
            param($path, $state, $event)
            if ($path -ceq $parent -and $event.phase -ceq 'after-entry') { throw [IO.IOException]::new('SYNTHETIC parent listing did not reach EOF') }
        }.GetNewClosure()
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.roots[0].state -cne 'absent-confirmed') 'partial parent listing cannot establish absence'
        $rows = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'filesystem-facts.ndjson'))
        Assert-OverlayTest (@($rows | Where-Object { $_.kind -ceq 'absence-parent-entry' }).Count -eq 1) 'partial parent names remain sealed facts'
    })
    [void](Invoke-OverlayCase -Name 'absence-parent-not-authorized' -PlannedId 'parent-lookup-authorization' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $sdk = $plan.roots[0].logicalPath
        foreach ($path in @($provider.state.nodes.Keys)) { if (Test-SwiftUIOverlayInside $sdk $path) { [void]$provider.state.nodes.Remove($path) } }
        $parent = Get-SwiftUIOverlayUnixParent $sdk
        $plan.lookupAuthorizations = @($plan.lookupAuthorizations | Where-Object { -not ($_.exactPath -ceq $parent -and $_.kind -ceq 'nonrecursive-parent-listing') })
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.roots[0].state -cne 'absent-confirmed') 'missing parent authorization preserves unknown existence'
    })
    [void](Invoke-OverlayCase -Name 'absence-parent-limit-stops-later-roots' -PlannedId 'each-boundary-limit' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $sdk = $plan.roots[0].logicalPath
        foreach ($path in @($provider.state.nodes.Keys)) { if (Test-SwiftUIOverlayInside $sdk $path) { [void]$provider.state.nodes.Remove($path) } }
        $parent = Get-SwiftUIOverlayUnixParent $sdk
        foreach ($name in @('UnrelatedA', 'UnrelatedB')) { [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($parent + '/' + $name) -Kind directory) }
        $plan.limits | Add-Member -NotePropertyName filesystemEntries -NotePropertyValue ([long]1) -Force
    } -Inspect {
        param($result, $read, $provider, $plan)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'entry-limit') 'absence-parent budget failure keeps the limit outcome'
        Assert-OverlayTest ($read.report.roots[0].state -ceq 'error') 'unfinished parent listing never confirms absence'
        Assert-OverlayTest ($read.report.roots[1].state -ceq 'unvisited') 'later root stays explicitly unvisited after an absence-parent limit'
        Assert-OverlayTest (@($provider.state.trace | Where-Object { Test-SwiftUIOverlayInside $plan.roots[1].logicalPath $_.path }).Count -eq 0) 'no later resource-root provider call occurs after hard stop'
    })
    [void](Invoke-OverlayCase -Name 'ordinary-file-not-copied' -PlannedId 'nonmatching-directory' -Mutate {
        param($provider, $plan)
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($plan.roots[1].logicalPath + '/ordinary.txt') -Kind file -Text 'SYNTHETIC noncandidate bytes')
    } -Inspect {
        param($result, $read, $provider, $plan)
        Assert-OverlayTest ($read.report.copiedFiles.Count -eq 0) 'noncandidate file is metadata-only'
        Assert-OverlayTest (@($provider.state.trace | Where-Object { $_.operation -ceq 'openRead' -and $_.path.EndsWith('/ordinary.txt') }).Count -eq 0) 'noncandidate content is never opened'
        $rows = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'filesystem-facts.ndjson'))
        Assert-OverlayTest (@($rows | Where-Object { $_.state -ceq 'readable-no-matches' -and $_.logicalPath -ceq $plan.roots[1].logicalPath }).Count -eq 1) 'completed nonmatching directory differs from empty'
    })
    [void](Invoke-OverlayCase -Name 'two-alias-occurrences' -PlannedId 'repeat-alias-not-cycle' -Mutate {
        param($provider, $plan)
        $sdk = $plan.roots[0].logicalPath
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/Shared.swiftcrossimport/SwiftUI.swiftoverlay') -Kind file -Text ("version: 1" + [char]10 + "modules:" + [char]10 + "  - name: _Shared" + [char]10))
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/AliasA.swiftcrossimport') -Kind symlink -LinkTarget 'Shared.swiftcrossimport')
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/AliasB.swiftcrossimport') -Kind symlink -LinkTarget 'Shared.swiftcrossimport')
    } -Inspect {
        param($result, $read)
        $definitions = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'definition-facts.ndjson') | Where-Object { $_.kind -ceq 'definition-file' })
        Assert-OverlayTest ($definitions.Count -eq 3) 'physical source plus both logical aliases have declaration occurrences'
        Assert-OverlayTest (@($definitions.recordId | Select-Object -Unique).Count -eq 3) 'alias occurrences retain distinct IDs'
        Assert-OverlayTest (@($definitions.rawFile.sha256 | Select-Object -Unique).Count -eq 1) 'alias occurrences preserve identical actual raw bytes'
    })
    [void](Invoke-OverlayCase -Name 'framework-versions-current' -PlannedId 'framework-version-alias' -Mutate {
        param($provider, $plan)
        $framework = $plan.roots[0].logicalPath + '/System/Library/Frameworks/Fixture.framework'
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($framework + '/Versions/A/Modules/Extra.swiftcrossimport/SwiftUI.swiftoverlay') -Kind file -Text ("version: 1" + [char]10 + "modules: []"))
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($framework + '/Versions/Current') -Kind symlink -LinkTarget 'A')
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($framework + '/Modules') -Kind symlink -LinkTarget 'Versions/Current/Modules')
    } -Inspect {
        param($result, $read)
        $definitions = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'definition-facts.ndjson') | Where-Object { $_.kind -ceq 'definition-file' })
        Assert-OverlayTest ($definitions.Count -eq 3) 'framework version, Current and Modules paths retain separate occurrences'
        Assert-OverlayTest (@($definitions | Where-Object { $_.logicalPath.Contains('/Versions/Current/') }).Count -eq 1) 'Current alias retains its logical path'
        Assert-OverlayTest (@($definitions | Where-Object { $_.physicalPath.Contains('/Versions/A/') }).Count -eq 3) 'framework aliases record the same resolved physical definition'
    })
    [void](Invoke-OverlayCase -Name 'ancestor-directory-cycle' -PlannedId 'ancestor-cycle' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($plan.roots[0].logicalPath + '/Loop') -Kind symlink -LinkTarget '.')
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'directory-cycle') 'physical ancestor cycle has an explicit outcome'
    })
    [void](Invoke-OverlayCase -Name 'outward-alias' -PlannedId 'outward-alias' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path '/OUTSIDE-CONTENT' -Kind file -Text 'SYNTHETIC outside bytes must not be read')
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($plan.roots[0].logicalPath + '/Out.swiftoverlay') -Kind symlink -LinkTarget '/OUTSIDE-CONTENT')
    } -Inspect {
        param($result, $read, $provider)
        Assert-OverlayTest (@($provider.state.trace | Where-Object { $_.path -ceq '/OUTSIDE-CONTENT' }).Count -eq 0) 'fake adapter receives no outside target calls'
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'outward-alias') 'outward alias stays pending/incomplete'
    })
    [void](Invoke-OverlayCase -Name 'lookup-only-alias-not-content' -PlannedId 'outward-alias' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $toolParent = Get-SwiftUIOverlayUnixParent (@($plan.identityAnchors | Where-Object { $_.anchorId -ceq 'swift-tool' })[0].logicalPath)
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($toolParent + '/Unexpected.swiftoverlay') -Kind file -Text ("version: 1" + [char]10 + "modules: []"))
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($plan.roots[0].logicalPath + '/LookupAlias') -Kind symlink -LinkTarget $toolParent)
    } -Inspect {
        param($result, $read, $provider, $plan)
        $toolParent = Get-SwiftUIOverlayUnixParent (@($plan.identityAnchors | Where-Object { $_.anchorId -ceq 'swift-tool' })[0].logicalPath)
        Assert-OverlayTest (@($provider.state.trace | Where-Object { $_.operation -ceq 'enumerate' -and $_.path -ceq $toolParent }).Count -eq 0) 'lookup-only tool parent never becomes a census subtree'
        Assert-OverlayTest (@($provider.state.trace | Where-Object { $_.path -ceq ($toolParent + '/Unexpected.swiftoverlay') }).Count -eq 0) 'lookup-only sibling content and metadata are not deliberately read'
    })
    [void](Invoke-OverlayCase -Name 'outward-filesystem-root-alias' -PlannedId 'outward-alias' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($plan.roots[0].logicalPath + '/ToFilesystemRoot') -Kind symlink -LinkTarget '/')
    } -Inspect {
        param($result, $read, $provider)
        $aliases = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'alias-facts.ndjson'))
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'outward-alias') 'valid slash target is classified as outward, never empty'
        Assert-OverlayTest (@($aliases | Where-Object { $_.rawTarget -ceq '/' -and $_.effectiveTargetCandidate -ceq '/' -and $_.disposition -ceq 'outward' }).Count -eq 1) 'outward slash alias preserves its explicit raw/resolved fact'
        Assert-OverlayTest (@($provider.state.trace | Where-Object { $_.path -ceq '/' -and $_.operation -cin @('openRead', 'enumerate') }).Count -eq 0) 'filesystem root is never opened or enumerated'
    })
    [void](Invoke-OverlayCase -Name 'dangling-alias' -PlannedId 'dangling-link' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($plan.roots[0].logicalPath + '/Dangling') -Kind symlink -LinkTarget 'MissingTarget')
    } -Inspect {
        param($result, $read)
        $aliases = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'alias-facts.ndjson'))
        Assert-OverlayTest (@($aliases | Where-Object { $_.disposition -ceq 'dangling' }).Count -gt 0) 'dangling target has an explicit retained alias result'
        Assert-OverlayTest (@($read.report.roots | Where-Object { $_.state -ceq 'absent-confirmed' }).Count -eq 0) 'dangling child is not root absence'
    })
    [void](Invoke-OverlayCase -Name 'ambiguous-parent-segment' -PlannedId 'outward-alias' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($plan.roots[0].logicalPath + '/Ambiguous') -Kind symlink -LinkTarget 'Unresolved/../Target')
    } -Inspect {
        param($result, $read, $provider)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'unsupported-link-target') 'unresolved parent traversal is not lexically reinterpreted'
        Assert-OverlayTest (@($provider.state.trace | Where-Object { $_.path.EndsWith('/Unresolved') -or $_.path.EndsWith('/Target') }).Count -eq 0) 'unsupported target causes no target lookup'
    })
    [void](Invoke-OverlayCase -Name 'replacement-character-alias' -PlannedId 'path-collision' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($plan.roots[0].logicalPath + '/Replacement') -Kind symlink -LinkTarget ('bad' + [char]0xfffd + 'target'))
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'unsupported-link-target') 'possible lossy BCL decoding remains incomplete'
    })
    [void](Invoke-OverlayCase -Name 'equal-metadata-changing-bytes' -PlannedId 'changed-during-read' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $target = $plan.roots[0].logicalPath + '/Changed.swiftcrossimport/SwiftUI.swiftoverlay'
        $firstText = "version: 1" + [char]10 + "modules:" + [char]10 + "  - name: _A" + [char]10
        $secondBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($firstText.Replace('_A', '_B'))
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path $target -Kind file -Text $firstText)
        $reads = [pscustomobject]@{ count = 0 }
        $provider.state.onOpenRead = {
            param($path, $state, $event)
            if ($path -ceq $target -and $event.phase -ceq 'before') {
                $reads.count++
                if ($reads.count -eq 2) { $event.bytes = $secondBytes }
            }
        }.GetNewClosure()
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'changed-file') 'second digest detects equal-size/equal-mtime drift'
        Assert-OverlayTest ($read.report.copiedFiles.Count -eq 1) 'first observed raw bytes remain sealed on drift'
    })
    [void](Invoke-OverlayCase -Name 'mutable-info-snapshot' -PlannedId 'changed-during-read' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $target = $plan.roots[0].logicalPath + '/Mutable.swiftcrossimport/SwiftUI.swiftoverlay'
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path $target -Kind file -Text ("version: 1" + [char]10 + "modules: []"))
        $reads = [pscustomobject]@{ count = 0 }
        $provider.state.onGetInfo = {
            param($path, $state, $event)
            if ($path -ceq $target -and $event.phase -ceq 'after') {
                $reads.count++
                $event.result = $state.nodes[$path].info
                if ($reads.count -eq 2) { $event.result.lastWriteTimeUtc = '2001-01-01T00:00:00.0000000Z' }
            }
        }.GetNewClosure()
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'changed-file') 'scalar fingerprints do not mutate with provider objects'
    })
    [void](Invoke-OverlayCase -Name 'membership-changes-between-passes' -PlannedId 'changed-during-read' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $target = $plan.roots[0].logicalPath + '/ChangingDirectory'
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($target + '/one.txt') -Kind file -Text 'one')
        $events = [pscustomobject]@{ complete = 0 }
        $provider.state.onEnumerate = {
            param($path, $state, $event)
            if ($path -ceq $target -and $event.phase -ceq 'complete') {
                $events.complete++
                if ($events.complete -eq 1) { [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($target + '/two.txt') -Kind file -Text 'two') }
            }
        }.GetNewClosure()
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'changed-membership') 'second EOF cannot conceal changed directory membership'
    })
    [void](Invoke-OverlayCase -Name 'non-shallow-enumeration-entry' -PlannedId 'path-collision' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $sdk = $plan.roots[0].logicalPath
        $provider.state.onEnumerate = {
            param($path, $state, $event)
            if ($path -ceq $sdk -and $event.phase -ceq 'entry') { $event.entry = [pscustomobject]@{ name = '../outside'; path = '/outside' } }
        }.GetNewClosure()
    } -Inspect {
        param($result, $read, $provider)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'non-shallow-entry') 'non-shallow enumerator output fails before child lookup'
        Assert-OverlayTest (@($provider.state.trace | Where-Object { $_.path -ceq '/outside' }).Count -eq 0) 'malformed child produces no outside call'
    })
    [void](Invoke-OverlayCase -Name 'candidate-directory-kind' -PlannedId 'file-directory-confusion' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($plan.roots[0].logicalPath + '/NotAFile.swiftoverlay') -Kind directory)
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'candidate-kind') 'directory with definition suffix is not parsed as empty'
    })
    [void](Invoke-OverlayCase -Name 'replacement-character-child-name' -PlannedId 'path-collision' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $sdk = $plan.roots[0].logicalPath
        $provider.state.onEnumerate = {
            param($path, $state, $event)
            if ($path -ceq $sdk -and $event.phase -ceq 'entry') {
                $name = 'ambiguous-' + [char]0xfffd
                $event.entry = [pscustomobject]@{ name = $name; path = $path + '/' + $name }
            }
        }.GetNewClosure()
    } -Inspect {
        param($result, $read, $provider)
        $rows = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'filesystem-facts.ndjson') | Where-Object { $_.kind -ceq 'ambiguous-directory-entry' })
        Assert-OverlayTest ($rows.Count -eq 1 -and $rows[0].reportedName.Contains([string][char]0xfffd)) 'ambiguous BCL name text remains an incomplete fact'
        Assert-OverlayTest (-not $rows[0].rawFilesystemBytesAvailable -and -not $rows[0].metadataQueriedByController) 'replacement text is not represented as exact filesystem bytes or inspected content'
        Assert-OverlayTest (@($provider.state.trace | Where-Object { $_.operation -cne 'enumerate' -and $_.path.Contains([string][char]0xfffd) }).Count -eq 0) 'ambiguous child is not queried after rejection'
    })
    [void](Invoke-OverlayCase -Name 'duplicate-enumerated-child' -PlannedId 'path-collision' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $sdk = $plan.roots[0].logicalPath
        $sameName = 'SDKSettings.json'
        $provider.state.onEnumerate = {
            param($path, $state, $event)
            if ($path -ceq $sdk -and $event.phase -ceq 'entry') {
                $event.entry = [pscustomobject]@{ name = $sameName; path = $path + '/' + $sameName }
            }
        }.GetNewClosure()
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'duplicate-entry') 'duplicate child name is not silently deduplicated'
    })
    foreach ($limitCase in @(
        @{ name = 'entry-limit'; field = 'filesystemEntries'; value = 1 },
        @{ name = 'directory-limit'; field = 'directories'; value = 1 },
        @{ name = 'depth-limit'; field = 'depth'; value = 1 },
        @{ name = 'report-limit'; field = 'reportBytes'; value = 1 }
    )) {
        $limitField = $limitCase.field; $limitValue = $limitCase.value
        [void](Invoke-OverlayCase -Name $limitCase.name -PlannedId 'each-boundary-limit' -ExpectComplete $false -MutatePlan {
            param($plan)
            $plan.limits | Add-Member -NotePropertyName $limitField -NotePropertyValue ([long]$limitValue) -Force
        }.GetNewClosure() -Inspect {
            param($result, $read)
            Assert-OverlayTest ($read.report.terminalIssue.code -match 'limit$') 'a hard budget breach retains its specific limit outcome'
        })
    }
    [void](Invoke-OverlayCase -Name 'parser-limit-stops-next-candidate' -PlannedId 'each-boundary-limit' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $directory = $plan.roots[0].logicalPath + '/Limited.swiftcrossimport'
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($directory + '/A.swiftoverlay') -Kind file -Text ("version: 1" + [char]10 + "modules: []"))
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($directory + '/B.swiftoverlay') -Kind file -Text ("version: 1" + [char]10 + "modules: []"))
        $plan.limits | Add-Member -NotePropertyName definitionParseBytes -NotePropertyValue ([long]5) -Force
    } -Inspect {
        param($result, $read, $provider)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'definition-byte-limit') 'parser limit is a specific stopping failure'
        Assert-OverlayTest ($read.report.copiedFiles.Count -eq 1) 'current raw definition is preserved but next candidate is not opened'
        Assert-OverlayTest (@($provider.state.trace | Where-Object { $_.operation -ceq 'openRead' -and $_.path.EndsWith('/B.swiftoverlay') }).Count -eq 0) 'no next-candidate content read after hard parser limit'
    })


    [void](Invoke-OverlayCase -Name 'selected-optional-absent' -PlannedId 'required-root-absent' -Mutate {
        param($provider, $plan)
        $optional = $plan.roots[2]
        $optional.selection = 'selected-optional'; $optional.expectedPhysicalPath = $optional.logicalPath
        $optional.allowedPhysicalBoundary = $optional.logicalPath
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path (Get-SwiftUIOverlayUnixParent $optional.logicalPath) -Kind directory)
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.roots[2].state -ceq 'absent-confirmed') 'explicit optional root absence is positively observed'
        Assert-OverlayTest ($read.report.roots[2].traversalComplete) 'completed optional-root absence is not an access error'
    })
    [void](Invoke-OverlayCase -Name 'many-bounded-records' -PlannedId 'streaming-many-records' -Mutate {
        param($provider, $plan)
        for ($index = 0; $index -lt 100; $index++) {
            [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($plan.roots[1].logicalPath + '/many/file' + $index + '.txt') -Kind file -Text 'not read')
        }
    } -Inspect {
        param($result, $read)
        $rows = @(Read-OverlayTestRows (Join-Path $result.outputRoot 'filesystem-facts.ndjson'))
        Assert-OverlayTest (@($rows | Where-Object { $_.kind -ceq 'directory-entry' -and $_.logicalPath.Contains('/many/file') }).Count -eq 100) 'all bounded ordinary file occurrences remain'
        Assert-OverlayTest (@($rows.recordId | Select-Object -Unique).Count -eq $rows.Count) 'record IDs distinguish every emitted event'
        Assert-OverlayTest ($read.report.copiedFiles.Count -eq 0) 'metadata census does not copy noncandidate file contents'
    })
    [void](Invoke-OverlayCase -Name 'nonseekable-source-stream' -PlannedId 'each-boundary-limit' -Mutate {
        param($provider, $plan)
        $target = $plan.roots[0].logicalPath + '/Streams.swiftcrossimport/SwiftUI.swiftoverlay'
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path $target -Kind file -Text ("version: 1" + [char]10 + "modules: []"))
        $originalOpen = $provider.openRead
        $provider.openRead = {
            param($path, $state)
            if ($path -cne $target) { return (& $originalOpen $path $state) }
            $encoded = [Text.Encoding]::ASCII.GetBytes([Convert]::ToBase64String($state.nodes[$path].bytes))
            $inner = [IO.MemoryStream]::new($encoded, $false)
            $stream = [Security.Cryptography.CryptoStream]::new($inner, [Security.Cryptography.FromBase64Transform]::new(), [Security.Cryptography.CryptoStreamMode]::Read)
            [void]$state.openedStreams.Add($inner); [void]$state.openedStreams.Add($stream)
            return $stream
        }.GetNewClosure()
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.counts.parsedDefinitions -eq 1) 'nonseekable source stream preserves full decoded bytes'
    })
    [void](Invoke-OverlayCase -Name 'source-read-throws' -PlannedId 'each-boundary-limit' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $target = $plan.roots[0].logicalPath + '/Throwing.swiftcrossimport/SwiftUI.swiftoverlay'
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path $target -Kind file -Text ("version: 1" + [char]10 + "modules: []"))
        $originalOpen = $provider.openRead
        $provider.openRead = {
            param($path, $state)
            if ($path -cne $target) { return (& $originalOpen $path $state) }
            $inner = [IO.MemoryStream]::new([Text.Encoding]::ASCII.GetBytes('!!!!'), $false)
            $stream = [Security.Cryptography.CryptoStream]::new($inner, [Security.Cryptography.FromBase64Transform]::new(), [Security.Cryptography.CryptoStreamMode]::Read)
            [void]$state.openedStreams.Add($inner); [void]$state.openedStreams.Add($stream)
            return $stream
        }.GetNewClosure()
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.copiedFiles.Count -eq 1 -and -not $read.report.copiedFiles[0].captureComplete) 'thrown read leaves an explicitly partial raw copy'
    })
    [void](Invoke-OverlayCase -Name 'source-close-throws' -PlannedId 'missing-or-stale-output-seal' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $target = $plan.roots[0].logicalPath + '/Closing.swiftcrossimport/SwiftUI.swiftoverlay'
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path $target -Kind file -Text ("version: 1" + [char]10 + "modules: []"))
        $originalOpen = $provider.openRead
        $provider.openRead = {
            param($path, $state)
            if ($path -cne $target) { return (& $originalOpen $path $state) }
            $stream = [IO.MemoryStream]::new([byte[]]$state.nodes[$path].bytes.Clone(), $false)
            $stream | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
                $this.Close()
                throw [IO.IOException]::new('SYNTHETIC source close failure after releasing its owned stream')
            }
            [void]$state.openedStreams.Add($stream)
            return $stream
        }.GetNewClosure()
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.copiedFiles.Count -eq 1 -and -not $read.report.copiedFiles[0].captureComplete) 'source close failure prevents a complete-copy claim'
        Assert-OverlayTest ($read.report.terminalIssue.causes.Count -gt 1) 'source cleanup error retains its underlying exception'
    })
    [void](Invoke-OverlayCase -Name 'multiple-returned-source-streams' -PlannedId 'each-boundary-limit' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $target = $plan.roots[0].logicalPath + '/DuplicateStreams.swiftcrossimport/SwiftUI.swiftoverlay'
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path $target -Kind file -Text ("version: 1" + [char]10 + "modules: []"))
        $originalOpen = $provider.openRead
        $provider.openRead = {
            param($path, $state)
            if ($path -cne $target) { return (& $originalOpen $path $state) }
            $first = [IO.MemoryStream]::new([byte[]]$state.nodes[$path].bytes.Clone(), $false)
            $second = [IO.MemoryStream]::new([byte[]]$state.nodes[$path].bytes.Clone(), $false)
            [void]$state.openedStreams.Add($first); [void]$state.openedStreams.Add($second)
            return @($first, $second)
        }.GetNewClosure()
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'provider-stream-contract') 'ambiguous source streams are rejected and both disposed'
    })
    foreach ($copyLimit in @(
        @{ name = 'copy-file-byte-limit'; field = 'copiedCandidateFileBytes'; value = 1 },
        @{ name = 'copy-total-byte-limit'; field = 'copiedCandidateBytes'; value = 1 },
        @{ name = 'copy-count-limit'; field = 'copiedCandidateFiles'; value = 1 }
    )) {
        $field = $copyLimit.field; $value = $copyLimit.value
        [void](Invoke-OverlayCase -Name $copyLimit.name -PlannedId 'each-boundary-limit' -ExpectComplete $false -Mutate {
            param($provider, $plan)
            $directory = $plan.roots[0].logicalPath + '/CopyBudget.swiftcrossimport'
            foreach ($name in @('A', 'B')) {
                [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($directory + '/' + $name + '.swiftoverlay') -Kind file -Text ("version: 1" + [char]10 + "modules: []"))
            }
            $plan.limits | Add-Member -NotePropertyName $field -NotePropertyValue ([long]$value) -Force
        }.GetNewClosure() -Inspect {
            param($result, $read)
            Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'candidate-copy-limit') 'candidate byte/count boundary is explicit and incomplete'
        })
    }
    [void](Invoke-OverlayCase -Name 'anchor-bytes-drift' -PlannedId 'changed-tool-or-sdk' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $anchor = @($plan.identityAnchors | Where-Object { $_.anchorId -ceq 'swift-tool' })[0]
        $node = $provider.state.nodes[$anchor.logicalPath]
        $node.bytes[0] = $node.bytes[0] -bxor 1
    } -Inspect {
        param($result, $read)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'anchor-drift') 'same recorded version label cannot hide changed live bytes'
        Assert-OverlayTest ($read.report.counts.enumerationPasses -eq 0) 'anchor mismatch prevents content census traversal'
    })
    [void](Invoke-OverlayCase -Name 'physical-root-mismatch' -PlannedId 'root-physical-mismatch' -ExpectComplete $false -Mutate {
        param($provider, $plan)
        $old = $plan.roots[0].expectedPhysicalPath
        $new = (Get-SwiftUIOverlayUnixParent $old) + '/UnexpectedPhysical.sdk'
        $plan.roots[0].expectedPhysicalPath = $new; $plan.roots[0].allowedPhysicalBoundary = $new
        foreach ($anchor in $plan.identityAnchors) { if ($anchor.allowedPhysicalBoundary -ceq $old) { $anchor.allowedPhysicalBoundary = $new } }
    } -Inspect {
        param($result, $read, $provider)
        Assert-OverlayTest ($read.report.terminalIssue.code -ceq 'root-physical-mismatch') 'root resolution mismatch cannot trigger a census'
        Assert-OverlayTest (@($provider.state.trace | Where-Object { $_.operation -ceq 'openRead' -or $_.operation -ceq 'enumerate' }).Count -eq 0) 'mismatched root opens no source content or directory iterator'
    })

    # All following mutation/restoration operates only on this process's small,
    # owned synthetic fixtures, never the saved successful native capture.
    $statusPath = Join-Path $fixture.Root 'capture-status.json'
    $streamPath = Join-Path $auditRoot 'identities.ndjson'
    $graphPath = $sourceContext.inputs.graphInputs[0].path
    $inventoryPath = $sourceContext.inputs.captureContext.inventoryPath
    foreach ($negative in @(
        @{ name = 'failed-capture'; planned = 'wrong-capture-state'; path = $statusPath; mode = 'status' },
        @{ name = 'same-size-ledger-change'; planned = 'same-size-stream-mutation'; path = $streamPath; mode = 'flip' },
        @{ name = 'changed-raw-graph'; planned = 'wrong-or-stale-seal'; path = $graphPath; mode = 'flip' },
        @{ name = 'changed-inventory'; planned = 'wrong-or-stale-seal'; path = $inventoryPath; mode = 'flip' }
    )) {
        if ((Get-Item -LiteralPath $negative.path).Length -gt 8MB) { throw 'Negative fixture backup exceeds its small-file budget.' }
        $original = [IO.File]::ReadAllBytes($negative.path)
        try {
            if ($negative.mode -ceq 'status') {
                $value = Read-OverlayTestJson $negative.path; $value.status = 'failed'
                Write-OverlayTestJson $negative.path $value
            } else {
                $changed = [byte[]]$original.Clone(); $changed[0] = $changed[0] -bxor 1
                [IO.File]::WriteAllBytes($negative.path, $changed)
                Assert-OverlayTest ((Get-Item -LiteralPath $negative.path).Length -eq $original.Length) "$($negative.name) keeps byte length unchanged"
            }
            [void](Assert-OverlayThrows {
                Read-SwiftUIOverlayDiscoveryInputs -CaptureRoot $fixture.Root -AuditRoot $auditRoot -ManifestPath $baseline -AllowSyntheticForTests
            } "$($negative.name) is rejected by actual source-seal intake")
            Add-OverlayTestCase $negative.name $negative.planned 'rejected' $null
        } finally { [IO.File]::WriteAllBytes($negative.path, $original) }
    }
    [void](Assert-OverlayThrows {
        Read-SwiftUIOverlayDiscoveryInputs -CaptureRoot $fixture.Root -AuditRoot $auditRoot -ManifestPath $baseline
    } 'public source intake refuses a synthetic capture without the internal test switch')
    Add-OverlayTestCase 'synthetic-source-refusal' 'synthetic-as-native' 'rejected' $null

    $reportRoot = $populated.result.outputRoot
    $reportPath = Join-Path $reportRoot 'discovery.json'
    $reportSealPath = Join-Path $reportRoot 'discovery.sha256'
    $originalReport = [IO.File]::ReadAllBytes($reportPath)
    $originalReportSeal = [IO.File]::ReadAllBytes($reportSealPath)
    foreach ($mutationName in @('whole-installation', 'string-boolean', 'integer-boolean', 'root-plan-redirect', 'missing-stream',
            'native-load', 'native-adapter', 'fake-provider', 'root-incomplete', 'missing-anchor', 'source-mutation-claim')) {
        try {
            $value = Read-OverlayTestJson $reportPath
            switch ($mutationName) {
                'whole-installation' { $value.observationInterval.wholeInstallationByteIdentityEstablished = $true }
                'string-boolean' { $value.qualification.overlayCompleteness = 'false' }
                'integer-boolean' { $value.filesystemBoundary.outwardDirectoryEnumerationAuthorized = 0 }
                'root-plan-redirect' {
                    $copy = $value.copiedFiles[0]
                    $value.rootPlan.path = $copy.path; $value.rootPlan.bytes = $copy.bytes; $value.rootPlan.sha256 = $copy.sha256
                    $value.copiedFiles = @($value.copiedFiles | Select-Object -Skip 1)
                }
                'missing-stream' { $value.recordStreams = @($value.recordStreams | Select-Object -Skip 1) }
                'native-load' { $value.coverage.nativeLoadEvidence = 'verified' }
                'native-adapter' { $value.runtime.actualDarwinAdapterValidationClaimed = $true }
                'fake-provider' { $value.runtime.fakeProvider = $false }
                'root-incomplete' { $value.roots[0].traversalComplete = $false }
                'missing-anchor' { $value.identityAnchorChecks = @($value.identityAnchorChecks | Select-Object -Skip 1) }
                'source-mutation-claim' { $value.sourceArtifacts.originalStreamsModified = $true }
            }
            Write-OverlayTestJson $reportPath $value
            $hash = Get-OverlayTestHash $reportPath
            [IO.File]::WriteAllText($reportSealPath, $hash + '  discovery.json' + [char]10, $utf8)
            [void](Assert-OverlayThrows {
                Read-SwiftUIOverlayDiscoveryReport -Root $reportRoot -ExpectedManifestSha256 $hash -AllowSyntheticForTests
            } "$mutationName is rejected even with a newly matching test-only outer seal")
            Add-OverlayTestCase ('report-' + $mutationName) 'same-installation-overclaim' 'rejected' $null
        } finally {
            [IO.File]::WriteAllBytes($reportPath, $originalReport)
            [IO.File]::WriteAllBytes($reportSealPath, $originalReportSeal)
        }
    }
    [void](Assert-OverlayThrows {
        Read-SwiftUIOverlayDiscoveryReport -Root $reportRoot -ExpectedManifestSha256 $populated.result.manifestSha256
    } 'synthetic census cannot masquerade as a native filesystem observation')
    Add-OverlayTestCase 'synthetic-report-refusal' 'synthetic-as-native' 'rejected' $null
    foreach ($tamper in @('missing-seal', 'stale-seal', 'same-size-stream', 'undeclared-raw-copy', 'in-progress')) {
        $changedPath = $reportSealPath; $restoreBytes = $originalReportSeal; $removeAfter = $false
        try {
            switch ($tamper) {
                'missing-seal' { [IO.File]::Delete($changedPath) }
                'stale-seal' { [IO.File]::WriteAllText($changedPath, ('0' * 64) + '  discovery.json' + [char]10, $utf8) }
                'same-size-stream' {
                    $changedPath = Join-Path $reportRoot 'filesystem-facts.ndjson'
                    if ((Get-Item -LiteralPath $changedPath).Length -gt 8MB) { throw 'Synthetic stream mutation exceeds its small-file budget.' }
                    $restoreBytes = [IO.File]::ReadAllBytes($changedPath)
                    $changed = [byte[]]$restoreBytes.Clone(); $changed[0] = $changed[0] -bxor 1
                    [IO.File]::WriteAllBytes($changedPath, $changed)
                }
                'undeclared-raw-copy' {
                    $changedPath = Join-Path $reportRoot 'raw/unreferenced.bin'; $removeAfter = $true
                    [IO.File]::WriteAllText($changedPath, 'SYNTHETIC undeclared bytes', $utf8)
                }
                'in-progress' {
                    $changedPath = Join-Path $reportRoot '.in-progress'; $removeAfter = $true
                    [IO.File]::WriteAllText($changedPath, '', $utf8)
                }
            }
            [void](Assert-OverlayThrows {
                Read-SwiftUIOverlayDiscoveryReport -Root $reportRoot -ExpectedManifestSha256 $populated.result.manifestSha256 -AllowSyntheticForTests
            } "$tamper cannot produce eligible filesystem evidence")
            Add-OverlayTestCase ('output-' + $tamper) 'missing-or-stale-output-seal' 'rejected' $null
        } finally {
            if ($removeAfter) { [IO.File]::Delete($changedPath) }
            else { [IO.File]::WriteAllBytes($changedPath, $restoreBytes) }
        }
    }
    $failedRoot = Join-Path $caseRoot 'unknown-definition/census'
    $failedManifest = Join-Path $failedRoot 'discovery.json'
    $failedSeal = Join-Path $failedRoot 'discovery.sha256'
    $originalFailed = [IO.File]::ReadAllBytes($failedManifest)
    $originalFailedSeal = [IO.File]::ReadAllBytes($failedSeal)
    try {
        $value = Read-OverlayTestJson $failedManifest
        $value.status = 'filesystem-recorded-awaiting-probe-review'
        Write-OverlayTestJson $failedManifest $value
        $hash = Get-OverlayTestHash $failedManifest
        [IO.File]::WriteAllText($failedSeal, $hash + '  discovery.json' + [char]10, $utf8)
        [void](Assert-OverlayThrows {
            Read-SwiftUIOverlayDiscoveryReport -Root $failedRoot -ExpectedManifestSha256 $hash -AllowSyntheticForTests
        } 'changing only status and resealing cannot promote contradictory failure metadata')
        Add-OverlayTestCase 'failed-status-only-promotion' 'same-installation-overclaim' 'rejected' $null
    } finally {
        [IO.File]::WriteAllBytes($failedManifest, $originalFailed)
        [IO.File]::WriteAllBytes($failedSeal, $originalFailedSeal)
    }
    [void](Assert-OverlayThrows {
        $provider = New-SwiftUIOverlayFakeProvider -SourceContext $sourceContext
        $validatedPlan = Read-SwiftUIOverlayRootPlan -Path (Join-Path $populated.directory 'requested-roots.json') -ExpectedSha256 (Get-OverlayTestHash (Join-Path $populated.directory 'requested-roots.json')) -SourceContext $sourceContext
        Invoke-SwiftUIOverlayCensus -SourceContext $sourceContext -RootPlanContext $validatedPlan -Provider $provider -OutputDirectory $reportRoot
    } 'existing output is immutable and cannot be overwritten')
    Add-OverlayTestCase 'immutable-output' 'immutable-existing-output' 'rejected' $null
    $overlapProvider = New-SwiftUIOverlayFakeProvider -SourceContext $sourceContext
    $overlapPlanPath = Join-Path $populated.directory 'requested-roots.json'
    $overlapPlan = Read-SwiftUIOverlayRootPlan -Path $overlapPlanPath -ExpectedSha256 (Get-OverlayTestHash $overlapPlanPath) -SourceContext $sourceContext
    $overlapOutput = Join-Path $fixture.Root 'must-not-be-created'
    [void](Assert-OverlayThrows {
        Invoke-SwiftUIOverlayCensus -SourceContext $sourceContext -RootPlanContext $overlapPlan -Provider $overlapProvider -OutputDirectory $overlapOutput
    } 'output inside immutable capture is refused before ownership or source access')
    Assert-OverlayTest (-not (Test-Path -LiteralPath $overlapOutput) -and $overlapProvider.state.trace.Count -eq 0) 'overlap refusal creates no output or fake filesystem observation'
    Add-OverlayTestCase 'output-inside-capture' 'output-overlap' 'rejected' $null

    # Ordinary BCL streams suffice to reproduce a writer flush failure; no new
    # managed helper, filesystem permission change or native adapter is needed.
    $firstBacking = [IO.MemoryStream]::new()
    $firstWriter = [IO.StreamWriter]::new($firstBacking, $utf8)
    $firstWriter.Write('buffered synthetic text')
    $firstBacking.Dispose()
    $secondBacking = [IO.MemoryStream]::new()
    $secondWriter = [IO.StreamWriter]::new($secondBacking, $utf8)
    $secondWriter.Write('another owned writer')
    $markerBacking = [IO.MemoryStream]::new()
    $cleanupSession = [pscustomobject]@{
        streams = [ordered]@{ first = [pscustomobject]@{ writer = $firstWriter }; second = [pscustomobject]@{ writer = $secondWriter } }
        marker = $markerBacking
    }
    $priorFailure = [IO.IOException]::new('SYNTHETIC original operation failure')
    $cleanupFailure = Assert-OverlayThrows {
        Close-SwiftUIOverlayStreams -Session $cleanupSession -IncludeMarker -PriorFailure $priorFailure
    } 'writer close failure remains explicit after attempting every owned resource'
    Assert-OverlayTest (-not $firstBacking.CanRead -and -not $secondBacking.CanRead -and -not $markerBacking.CanRead) 'flush failure cannot skip another writer or the ownership marker'
    Assert-OverlayTest ($null -eq $cleanupSession.marker -and @($cleanupSession.streams.Values | Where-Object { $null -ne $_.writer }).Count -eq 0) 'all disposal ownership references are cleared exactly once'
    $exception = $cleanupFailure.Exception
    while ($null -ne $exception -and $exception -isnot [AggregateException]) { $exception = $exception.InnerException }
    Assert-OverlayTest ($null -ne $exception -and $exception.InnerExceptions.Count -ge 2 -and
        $exception.InnerExceptions[0].Message -ceq $priorFailure.Message) 'cleanup aggregate preserves the original operation failure'
    Add-OverlayTestCase 'writer-close-failure-disposes-all' 'missing-or-stale-output-seal' 'rejected' $null

    $growthDirectory = Join-Path $OutputRoot 'root-plan-growth'
    [void][IO.Directory]::CreateDirectory($growthDirectory)
    $growthProvider = New-SwiftUIOverlayFakeProvider -SourceContext $sourceContext
    $growthPlanPath = Join-Path $growthDirectory 'root-plan.json'
    Write-OverlayTestJson $growthPlanPath (New-SwiftUIOverlayFakeRootPlan -SourceContext $sourceContext)
    $growthPlan = Read-SwiftUIOverlayRootPlan -Path $growthPlanPath -ExpectedSha256 (Get-OverlayTestHash $growthPlanPath) -SourceContext $sourceContext
    [IO.File]::AppendAllText($growthPlanPath, ' ', $utf8)
    [void](Assert-OverlayThrows {
        Invoke-SwiftUIOverlayCensus -SourceContext $sourceContext -RootPlanContext $growthPlan -Provider $growthProvider -OutputDirectory (Join-Path $growthDirectory 'census')
    } 'post-intake root plan growth is bounded before fake SDK reads')
    Assert-OverlayTest ($growthProvider.state.trace.Count -eq 0) 'growing root plan prevents any filesystem observation'
    Assert-OverlayTest (-not (Test-Path -LiteralPath (Join-Path $growthDirectory 'census/discovery.sha256'))) 'growing root plan leaves no eligible seal'
    Add-OverlayTestCase 'root-plan-growth' 'each-boundary-limit' 'rejected' $null

    $strictPath = Join-Path $OutputRoot 'duplicate-json-key.json'
    [IO.File]::WriteAllText($strictPath, '{"schemaVersion":1,"schemaVersion":1}', $utf8)
    [void](Assert-OverlayThrows { Read-SwiftUIOverlayMetadata $strictPath } 'existing strict managed JSON reader rejects duplicate keys')
    Add-OverlayTestCase 'duplicate-metadata-key' 'wrong-or-stale-seal' 'rejected' $null
    $sourceAfter = @($sourceContext.fileSeals | ForEach-Object { $_.path + [char]9 + (Get-OverlayTestHash $_.path) }) -join ([string][char]10)
    Assert-OverlayTest ($sourceBefore -ceq $sourceAfter) 'every original synthetic capture/ledger source byte is restored and unchanged by the census'
    Add-OverlayTestCase 'immutable-source-inputs' 'wrong-or-stale-seal' 'passed' $null
    Assert-OverlayTest ($populated.read.report.interfaceProducerIdentity -match 'not inferred from extractor') 'interface producer and observed extractor remain separate'
    Add-OverlayTestCase 'producer-extractor-separation' 'interface-producer-confusion' 'passed' $null

} catch { $failure = $_ }
finally {
    $report = [ordered]@{
        schemaVersion = 1; evidenceKind = 'synthetic-overlay-discovery-tests'; powerShellVersion = $PSVersionTable.PSVersion.ToString()
        assertionsPassed = $script:OverlayAssertions; cases = $script:OverlayCases.ToArray()
        plannedCaseIdsExercised = @($script:OverlayPlannedCases)
        plannedCaseMappingMeaning = 'Listed fixture families exercise Stage A portions of the proposed matrix; no claim that all 64 Stage A/B cases or every native boundary has been completed.'
        nativeSDKCommandsExecuted = $false; nativeDarwinFilesystemValidated = $false; stageBImplementedOrExecuted = $false
        managedHelper = 'existing bounded strict JSON and synthetic ledger writer; no new managed source'
        outcome = $(if ($null -eq $failure) { 'passed' } else { 'failed' })
        failure = $(if ($null -eq $failure) { $null } else { $failure.ToString() })
    }
    Write-OverlayTestJson (Join-Path $OutputRoot 'test-results.json') $report
}
if ($null -ne $failure) { throw $failure }
Write-Output ("Overlay discovery tests passed: " + $script:OverlayAssertions + " assertions; synthetic PS" + $PSVersionTable.PSVersion + ".")
Write-Output ("Receipts: " + (Join-Path $OutputRoot 'test-results.json'))
