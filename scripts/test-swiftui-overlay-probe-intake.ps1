<#
.SYNOPSIS
Tests Stage B intake and plan validation using sealed synthetic Stage A evidence.
.DESCRIPTION
Runs no SDK observation, native compiler, SwiftPM, native load probe, workflow,
or external child command. The existing synthetic capture/audit helpers may
initialize the existing managed strict JSON/stream writer in this process.
All negative discovery mutations occur in separate owned copies. Original
capture, audit streams and positive census fixtures remain byte-for-byte intact.
#>
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot), [string]$OutputRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $RepositoryRoot 'scripts/swiftui-overlay-probe-intake.ps1')
. (Join-Path $RepositoryRoot 'scripts/swiftui-api-audit-test-fixtures.ps1')
. (Join-Path $RepositoryRoot 'scripts/fixtures/swiftui-overlay-discovery/fake-filesystem.ps1')
. (Join-Path $RepositoryRoot 'scripts/fixtures/swiftui-overlay-probes/intake/fixture-support.ps1')
if ([string]::IsNullOrEmpty($OutputRoot)) {
    $OutputRoot = Join-Path $RepositoryRoot ('artifacts/swiftui-overlay-probe-intake-tests/' + [Guid]::NewGuid().ToString('N'))
}
$script:ProbeIntakeOutput = Resolve-SwiftUIAuditTestRoot $OutputRoot
if (Test-Path -LiteralPath $script:ProbeIntakeOutput) { throw 'Overlay probe intake test output must be fresh and owned.' }
[void][IO.Directory]::CreateDirectory($script:ProbeIntakeOutput)
$script:ProbeIntakeUTF8 = [Text.UTF8Encoding]::new($false, $true)
$script:ProbeIntakeAssertions = 0
$script:ProbeIntakeCases = [Collections.Generic.List[object]]::new()
$script:ProbeIntakeCaseNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$script:ProbeIntakeManifest = Join-Path $RepositoryRoot 'docs/swiftui-baseline.json'
$script:ProbeIntakeSourceContext = $null
$script:ProbeIntakeCapture = $null
$script:ProbeIntakeAuditRoot = Get-ProbeIntakeTestPath 'source-audit'
$immutableRoots = [Collections.Generic.List[string]]::new()
$beforeSources = $null; $beforeCensuses = $null
$integrity = [pscustomobject]@{ sourcePreserved = $false; censusesPreserved = $false }
$failure = $null

try {
    $script:ProbeIntakeCapture = New-SwiftUIAuditTestCapture -Root (Get-ProbeIntakeTestPath 'source-capture') -ManifestPath $script:ProbeIntakeManifest
    & (Join-Path $RepositoryRoot 'scripts/build-swiftui-api-audit.ps1') -CaptureRoot $script:ProbeIntakeCapture.Root -OutputDirectory $script:ProbeIntakeAuditRoot -ManifestPath $script:ProbeIntakeManifest -SortChunkBytes 4096 -MergeFanIn 2 | Out-Null
    $script:ProbeIntakeSourceContext = Read-SwiftUIOverlayDiscoveryInputs -CaptureRoot $script:ProbeIntakeCapture.Root -AuditRoot $script:ProbeIntakeAuditRoot -ManifestPath $script:ProbeIntakeManifest -AllowSyntheticForTests
    Assert-ProbeIntakeTest $script:ProbeIntakeSourceContext.syntheticFixture 'the source capture is explicitly synthetic'
    Assert-ProbeIntakeTest ($script:ProbeIntakeSourceContext.inputs.recordFiles.Count -eq 9) 'the real intake binds all nine original audit streams'
    $beforeSources = Get-ProbeIntakeTestSnapshot @($script:ProbeIntakeCapture.Root, $script:ProbeIntakeAuditRoot)

    $empty = New-ProbeIntakeTestCensus 'empty'
    $populated = New-ProbeIntakeTestCensus 'populated'
    $lexical = New-ProbeIntakeTestCensus 'lexical'
    $crossRoot = New-ProbeIntakeTestCensus 'cross-root'
    $optionalPresent = New-ProbeIntakeTestCensus 'optional-present'
    foreach ($fixture in @($empty, $populated, $lexical, $crossRoot, $optionalPresent)) { [void]$immutableRoots.Add($fixture.root) }
    $beforeCensuses = Get-ProbeIntakeTestSnapshot $immutableRoots.ToArray()

    # These successful controls precede rejection tests. A missing function or
    # broken common input path cannot masquerade as semantic rejection coverage.
    $populated.inputs = Read-ProbeIntakeTestInputs $populated.root $populated.manifestSha256
    $empty.inputs = Read-ProbeIntakeTestInputs $empty.root $empty.manifestSha256
    $lexical.inputs = Read-ProbeIntakeTestInputs $lexical.root $lexical.manifestSha256
    $optionalPresent.inputs = Read-ProbeIntakeTestInputs $optionalPresent.root $optionalPresent.manifestSha256

    Invoke-ProbeIntakeTestCase 'complete-occurrence-preserving-intake' {
        Assert-ProbeIntakeTest $populated.inputs.syntheticFixture 'internal intake never promotes synthetic provenance'
        Assert-ProbeIntakeTest ($populated.inputs.definitions.Count -eq 6) 'all six hidden, aliased, target-specific and ordinary definitions survive'
        Assert-ProbeIntakeTest ($populated.inputs.candidates.Count -eq 12) 'each definition keeps both pinned-target candidates'
        $actualIds = @($populated.inputs.definitions.recordId | Sort-Object -CaseSensitive)
        $expectedIds = @($populated.definitions.recordId | Sort-Object -CaseSensitive)
        Assert-ProbeIntakeTest (($actualIds -join '|') -ceq ($expectedIds -join '|')) 'compact definitions preserve exact source occurrence IDs'
        $aliasPair = @($populated.inputs.definitions | Where-Object {
            $_.context.declaringModuleClaim -ceq 'Other' -and $_.context.bystanderModuleClaim -ceq 'SwiftUI'
        })
        Assert-ProbeIntakeTest ($aliasPair.Count -eq 2 -and $aliasPair[0].recordId -cne $aliasPair[1].recordId) 'a directory alias never deduplicates definition occurrences'
        Assert-ProbeIntakeTest ($aliasPair[0].physicalPath -ceq $aliasPair[1].physicalPath -and $aliasPair[0].logicalPath -cne $aliasPair[1].logicalPath) 'distinct logical occurrences retain their shared physical destination'
        Assert-ProbeIntakeTest ($aliasPair[0].nameOccurrenceCount -eq 3 -and $aliasPair[1].nameOccurrenceCount -eq 3) 'duplicate overlay name occurrences are counted, not collapsed'
        Assert-ProbeIntakeTest ($aliasPair[0].nameOccurrencesSha256 -ceq $aliasPair[1].nameOccurrencesSha256 -and $aliasPair[0].nameOccurrencesSha256 -cmatch '\A[0-9a-f]{64}\z') 'the compact name digest agrees for byte-equivalent alias definitions'
        $foreign = @($populated.inputs.definitions | Where-Object { $_.context.targetDirectory -ceq 'arm64e-apple-ios-macabi' })
        Assert-ProbeIntakeTest ($foreign.Count -eq 2) 'foreign target-directory spellings remain in intake without guessed applicability'
        Assert-ProbeIntakeTest (@($populated.inputs.candidates | Where-Object { $null -ne $_.targetVariant }).Count -eq 0) 'target directories do not create invocation variants'
        $allMaps = @($populated.inputs.moduleContexts | Where-Object { $_.kind -ceq 'clang-module-map' })
        Assert-ProbeIntakeTest ($allMaps.Count -eq 3) 'all three map occurrences survive without grammar or path guesses'
        $maps = @($allMaps | Where-Object { -not $_.logicalPath.Contains('/Mirror/') })
        Assert-ProbeIntakeTest ($maps.Count -eq 2 -and $maps[0].physicalPath -ceq $maps[1].physicalPath) 'the module-map alias is admitted in its original physical context'
        Assert-ProbeIntakeTest ($maps[0].rawFile.path -cne $maps[1].rawFile.path -and $maps[0].rawFile.sha256 -ceq $maps[1].rawFile.sha256) 'byte-identical module-map copies preserve separate occurrence ownership'
    }

    Invoke-ProbeIntakeTestCase 'all-source-artifact-bindings' {
        $expected = [ordered]@{
            captureManifestSha256 = $script:ProbeIntakeSourceContext.inputs.captureContext.captureSha256
            captureStatusSha256 = $script:ProbeIntakeSourceContext.inputs.captureContext.statusSha256
            auditManifestSha256 = $script:ProbeIntakeSourceContext.inputs.auditManifestSha256
            baselineManifestSha256 = $script:ProbeIntakeSourceContext.inputs.currentExpectedBaselineManifestSha256
            inventorySha256 = $script:ProbeIntakeSourceContext.inputs.captureContext.inventorySha256
            graphSetSha256 = $script:ProbeIntakeSourceContext.graphSetSha256
            discoveryManifestSha256 = $populated.manifestSha256
            rootPlanSha256 = $populated.report.rootPlan.sha256
        }
        Assert-ProbeIntakeTest ($populated.inputs.sourceArtifacts.PSObject.Properties.Name.Count -eq $expected.Count) 'intake exposes exactly the eight source bindings'
        foreach ($key in $expected.Keys) {
            Assert-ProbeIntakeTest ($populated.inputs.sourceArtifacts.$key -ceq $expected[$key]) "intake binds the actual $key bytes"
        }
    }

    Invoke-ProbeIntakeTestCase 'public-intake-rejects-synthetic-source' {
        [void](Get-Command Read-SwiftUIOverlayProbeInputs -CommandType Function -ErrorAction Stop)
        Get-ProbeIntakeTestRejection {
            Read-SwiftUIOverlayProbeInputs -CaptureRoot $script:ProbeIntakeCapture.Root -AuditRoot $script:ProbeIntakeAuditRoot -DiscoveryRoot $populated.root -ExpectedDiscoverySha256 $populated.manifestSha256 -ManifestPath $script:ProbeIntakeManifest
        } 'the public entrypoint cannot treat a successful synthetic fixture as native evidence' 'synthetic'
    }

    Invoke-ProbeIntakeTestCase 'complete-zero-definition-intake' {
        Assert-ProbeIntakeTest $empty.inputs.syntheticFixture 'zero-definition input stays synthetic'
        Assert-ProbeIntakeTest ($empty.inputs.definitions.Count -eq 0 -and $empty.inputs.candidates.Count -eq 0) 'a complete census with no definitions yields no invented pairs'
    }

    Invoke-ProbeIntakeTestCase 'selected-optional-root-present-and-complete' {
        $root = @($optionalPresent.report.roots | Where-Object { $_.rootId -ceq 'platform-developer-frameworks' })[0]
        Assert-ProbeIntakeTest ($root.state -ceq 'readable-complete' -and $root.traversalComplete) 'the original optional-root fixture has observed, completed traversal'
        Assert-ProbeIntakeTest ($optionalPresent.inputs.definitions.Count -eq 0 -and $optionalPresent.inputs.candidates.Count -eq 0) 'a present optional root with only an ordinary file does not invent definitions'
    }

    Invoke-ProbeIntakeTestCase 'ordinary-child-directory-traversal-retained' {
        $rows = @(Read-ProbeIntakeTestRows (Join-Path $populated.root 'filesystem-facts.ndjson'))
        $child = @($rows | Where-Object { $_.kind -ceq 'directory-complete' -and $_.logicalPath.EndsWith('/Plain/Child') })
        Assert-ProbeIntakeTest ($child.Count -eq 1 -and $child[0].childCount -eq 1 -and $child[0].matchedDirectChildCount -eq 0 -and $child[0].state -ceq 'readable-no-matches') 'the original census traverses the plain child with a non-candidate leaf'
    }

    Invoke-ProbeIntakeTestCase 'alias-may-reach-another-authorized-content-root' {
        $crossRoot.inputs = Read-ProbeIntakeTestInputs $crossRoot.root $crossRoot.manifestSha256
        $definitions = $crossRoot.inputs.definitions
        Assert-ProbeIntakeTest ($definitions.Count -eq 2 -and $crossRoot.inputs.candidates.Count -eq 4) 'the source and alias remain separate definition occurrences across authorized roots'
        Assert-ProbeIntakeTest ($definitions[0].physicalPath -ceq $definitions[1].physicalPath -and $definitions[0].rootId -cne $definitions[1].rootId) 'rootId describes the original occurrence even when the resolved destination belongs to another selected root'
        $plan = New-ProbeIntakeTestPlan $crossRoot $crossRoot.definitions
        $result = Read-ProbeIntakeTestPlan 'cross-root-alias' $plan $crossRoot.inputs
        Assert-ProbeIntakeTest ($result.pairs.Count -eq 2 -and @($result.dispositions | Where-Object { $_.disposition -ceq 'selected' }).Count -eq 4) 'a reviewed plan can select both authorized occurrences without rewriting their roots'
    }

    $ordinary = @($populated.definitions | Where-Object { $_.logicalPath.Contains('/.hidden/') -and $_.context.bystanderModuleClaim -ceq 'SwiftUI' })[0]
    $aliased = @($populated.definitions | Where-Object { $_.logicalPath.Contains('/Aliases/') -and $_.context.bystanderModuleClaim -ceq 'SwiftUI' })[0]
    $emptyDefinition = @($populated.definitions | Where-Object { $_.logicalPath.Contains('/.hidden/') -and $_.nameOccurrences.Count -eq 0 })[0]
    $foundation = @($populated.definitions | Where-Object { $_.context.declaringModuleClaim -ceq 'SwiftUI' })[0]
    $sixteen = @($populated.definitions | Where-Object { $_.context.declaringModuleClaim -ceq 'Sixteen' })[0]
    $singlePlan = New-ProbeIntakeTestPlan $populated @($ordinary)
    $fourPlan = New-ProbeIntakeTestPlan $populated @($ordinary, $aliased, $emptyDefinition, $foundation) @('off', 'default')

    Invoke-ProbeIntakeTestCase 'public-plan-rejects-synthetic-source' {
        [void](Get-Command Read-SwiftUIOverlayProbePlan -CommandType Function -ErrorAction Stop)
        $path = Get-ProbeIntakeTestPath 'plans/public-plan-synthetic/plan.json'
        Write-ProbeIntakeTestJson $path $singlePlan
        $sha = Get-SwiftUIAuditTestHash $path
        Get-ProbeIntakeTestRejection {
            Read-SwiftUIOverlayProbePlan -Path $path -ExpectedSha256 $sha -Inputs $populated.inputs
        } 'the public plan entrypoint cannot select synthetic evidence for a native invocation' 'synthetic'
        Assert-ProbeIntakeTest ((Get-SwiftUIAuditTestHash $path) -ceq $sha) 'public synthetic refusal leaves reviewed plan bytes intact'
    }

    Invoke-ProbeIntakeTestCase 'plan-refresh-restores-omitted-caller-projections' {
        $tampered = $populated.inputs.PSObject.Copy()
        $tampered.definitions = @($populated.inputs.definitions | Where-Object { $_.recordId -ceq $ordinary.recordId })
        $tampered.candidates = @($populated.inputs.candidates | Where-Object { $_.definitionOccurrenceId -ceq $ordinary.recordId })
        Assert-ProbeIntakeTest ($tampered.definitions.Count -eq 1 -and $tampered.candidates.Count -eq 2) 'the caller projection omits every unselected definition and candidate'
        Assert-ProbeIntakeTest ($populated.inputs.definitions.Count -eq 6 -and $populated.inputs.candidates.Count -eq 12) 'the original input object is not mutated by the projection attack'
        $result = Read-ProbeIntakeTestPlan 'canonical-input-refresh' $singlePlan $tampered
        Assert-ProbeIntakeTest ($result.inputs.definitions.Count -eq 6 -and $result.inputs.candidates.Count -eq 12) 'plan intake rebuilds canonical definitions and candidates from the sealed files'
        Assert-ProbeIntakeTest ($result.dispositions.Count -eq 12 -and @($result.dispositions | Where-Object { $_.disposition -ceq 'selected' }).Count -eq 2 -and @($result.dispositions | Where-Object { $_.disposition -ceq 'unselected' }).Count -eq 10) 'omitted in-memory candidates cannot disappear from the complete disposition accounting'
        Assert-ProbeIntakeTest $result.inputs.syntheticFixture 'fresh canonical source verification retains its synthetic provenance'
    }

    Invoke-ProbeIntakeTestCase 'relative-input-and-plan-paths-bind-the-validated-files' {
        $caseRoot = Get-ProbeIntakeTestPath 'plans/relative-path-context'
        $differentProcessRoot = Get-ProbeIntakeTestPath 'context-decoy/deep/nest'
        [void][IO.Directory]::CreateDirectory($differentProcessRoot)
        $path = Join-Path $caseRoot 'plan.json'
        Write-ProbeIntakeTestJson $path $singlePlan
        $sha = Get-SwiftUIAuditTestHash $path
        $decoy = Copy-ProbeIntakeTestValue $singlePlan
        $decoy.nativeProfileSha256 = Get-SwiftUIBaselineTextHash 'SYNTHETIC distinct process-directory decoy; no native invocation'
        $decoyPath = Join-Path $differentProcessRoot 'plan.json'
        Write-ProbeIntakeTestJson $decoyPath $decoy
        Assert-ProbeIntakeTest ((Get-SwiftUIAuditTestHash $decoyPath) -cne $sha) 'both directories have the same plan filename but different sealed bytes'
        $relativeCapture = [IO.Path]::GetRelativePath($caseRoot, $script:ProbeIntakeCapture.Root)
        $relativeAudit = [IO.Path]::GetRelativePath($caseRoot, $script:ProbeIntakeAuditRoot)
        $relativeDiscovery = [IO.Path]::GetRelativePath($caseRoot, $populated.root)
        $relativeManifest = [IO.Path]::GetRelativePath($caseRoot, $script:ProbeIntakeManifest)
        foreach ($relative in @($relativeCapture, $relativeAudit, $relativeDiscovery, $relativeManifest)) {
            $intended = [IO.Path]::GetFullPath($relative, $caseRoot)
            $fromProcessDirectory = [IO.Path]::GetFullPath($relative, $differentProcessRoot)
            Assert-ProbeIntakeTest (-not [string]::Equals($intended, $fromProcessDirectory, [StringComparison]::OrdinalIgnoreCase)) 'each relative capture, audit, discovery and baseline path resolves differently under the decoy process directory'
        }
        $originalProcessDirectory = [Environment]::CurrentDirectory
        Push-Location -LiteralPath $caseRoot
        try {
            [Environment]::CurrentDirectory = $differentProcessRoot
            $relativeInputs = Read-SwiftUIOverlayProbeInputsInternal -CaptureRoot $relativeCapture -AuditRoot $relativeAudit -DiscoveryRoot $relativeDiscovery -ExpectedDiscoverySha256 $populated.manifestSha256 -ManifestPath $relativeManifest -AllowSyntheticForTests
            $result = Read-SwiftUIOverlayProbePlanInternal -Path 'plan.json' -ExpectedSha256 $sha -Inputs $relativeInputs -AllowSyntheticForTests
            Assert-ProbeIntakeTest ($relativeInputs.definitions.Count -eq 6 -and $result.dispositions.Count -eq 12) 'filesystem validation and subsequent .NET reads use the same absolute files despite different PowerShell and process directories'
            Assert-ProbeIntakeTest ($result.sourceArtifacts.discoveryManifestSha256 -ceq $populated.manifestSha256) 'relative paths still bind the separately reviewed original discovery bytes'
            Assert-ProbeIntakeTest ($result.nativeProfileSha256 -ceq $singlePlan.nativeProfileSha256 -and $result.nativeProfileSha256 -cne $decoy.nativeProfileSha256) 'the returned native profile comes from the validated PowerShell-location plan, not the process-directory decoy'
            Assert-ProbeIntakeTest ($result.plan.nativeProfileSha256 -ceq $singlePlan.nativeProfileSha256 -and $result.plan.nativeProfileSha256 -cne $decoy.nativeProfileSha256) 'the parsed plan and returned commitment identify the same intended bytes'
        } finally {
            try { Pop-Location } finally { [Environment]::CurrentDirectory = $originalProcessDirectory }
        }
    }

    Invoke-ProbeIntakeTestCase 'plan-path-directory-refused-before-read' {
        $directoryPath = Get-ProbeIntakeTestPath 'plans/directory-input/plan.json'
        [void][IO.Directory]::CreateDirectory($directoryPath)
        Get-ProbeIntakeTestRejection {
            Read-SwiftUIOverlayProbePlanInternal -Path $directoryPath -ExpectedSha256 ('0' * 64) -Inputs $populated.inputs -AllowSyntheticForTests
        } 'a directory cannot enter the plan metadata reader as if it were a regular file' 'ordinary regular file'
    }

    $reparseCaseName = 'plan-file-beneath-reparse-ancestor-refused'
    $reparseRoot = Get-ProbeIntakeTestPath 'plans/reparse-ancestor'
    $reparseTarget = Join-Path $reparseRoot 'target'
    $reparseLink = Join-Path $reparseRoot 'linked'
    $reparsePlan = Join-Path $reparseTarget 'plan.json'
    Write-ProbeIntakeTestJson $reparsePlan $singlePlan
    $reparseSha = Get-SwiftUIAuditTestHash $reparsePlan
    [void](Get-SwiftUIBaselineRelativePath $script:ProbeIntakeOutput ([IO.Path]::GetFullPath($reparseTarget)))
    [void](Get-SwiftUIBaselineRelativePath $script:ProbeIntakeOutput ([IO.Path]::GetFullPath($reparseLink)))
    $reparseCreationFailure = $null
    try {
        # The link and its target stay inside this owned test output. No native
        # shell, elevated operation or external filesystem helper is invoked.
        $linkKind = 'SymbolicLink'
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $linkKind = 'Junction' }
        New-Item -ItemType $linkKind -Path $reparseLink -Value $reparseTarget -ErrorAction Stop | Out-Null
    } catch { $reparseCreationFailure = $_ }
    if ($null -eq $reparseCreationFailure) {
        Invoke-ProbeIntakeTestCase $reparseCaseName {
            $linkItem = Get-Item -LiteralPath $reparseLink -Force -ErrorAction Stop
            Assert-ProbeIntakeTest (($linkItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'the owned ancestor is an actual filesystem reparse point'
            $throughLink = Join-Path $reparseLink 'plan.json'
            Get-ProbeIntakeTestRejection {
                Read-SwiftUIOverlayProbePlanInternal -Path $throughLink -ExpectedSha256 $reparseSha -Inputs $populated.inputs -AllowSyntheticForTests
            } 'a real ordinary plan file under a reparse ancestor is refused before its bytes are read' 'ancestor is not an ordinary directory'
            Assert-ProbeIntakeTest ((Get-SwiftUIAuditTestHash $reparsePlan) -ceq $reparseSha) 'ancestor refusal leaves the original ordinary target bytes intact'
        }
    } else {
        [void]$script:ProbeIntakeCaseNames.Add($reparseCaseName)
        [void]$script:ProbeIntakeCases.Add([pscustomobject]@{
            name = $reparseCaseName; outcome = 'skipped'; assertionsPassed = 0
            details = @([pscustomobject]@{ reason = 'Owned filesystem link creation was unavailable; no elevated or native fallback was attempted.'; error = $reparseCreationFailure.Exception.Message })
            failure = $null; scriptStackTrace = $null
        })
    }

    Invoke-ProbeIntakeTestCase 'selected-pairs-and-exhaustive-dispositions' {
        $result = Read-ProbeIntakeTestPlan 'four-valid-pairs' $fourPlan $populated.inputs
        Assert-ProbeIntakeTest ($result.pairs.Count -eq 4 -and $result.targetContexts.Count -eq 4) 'four pairs and both C++ modes preserve both pinned targets'
        Assert-ProbeIntakeTest ($result.dispositions.Count -eq 12) 'every source candidate receives one disposition independent of mode expansion'
        $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($disposition in $result.dispositions) {
            Assert-ProbeIntakeTest ($ids.Add($disposition.candidateId)) 'dispositions do not duplicate candidate IDs'
            Assert-ProbeIntakeTest ($disposition.nativeLoadEvidence -ceq 'not-performed') 'selection never claims native activation'
            $source = @($populated.candidates | Where-Object { $_.recordId -ceq $disposition.candidateId })
            Assert-ProbeIntakeTest ($source.Count -eq 1 -and $source[0].definitionOccurrenceId -ceq $disposition.definitionOccurrenceId -and $source[0].target -ceq $disposition.target) 'each disposition binds its original candidate definition and target'
            Assert-ProbeIntakeTest ($disposition.expectedOverlayNameCount -eq $source[0].expectedOverlayNameOccurrences.Count) 'disposition name counts preserve duplicate occurrences'
        }
        Assert-ProbeIntakeTest (@($result.dispositions | Where-Object { $_.disposition -ceq 'selected' }).Count -eq 8) 'four selected definitions account for exactly eight source candidates'
        $unselected = @($result.dispositions | Where-Object { $_.disposition -ceq 'unselected' })
        Assert-ProbeIntakeTest ($unselected.Count -eq 4 -and @($unselected | Where-Object { $null -ne $_.pairId }).Count -eq 0) 'unselected definitions retain explicit dispositions without invented pair IDs'
        $names = $result.pairs[0].overlayNameOccurrences
        Assert-ProbeIntakeTest (($names.name -join '|') -ceq '_Repeated|_Repeated|PublicOverlay' -and ($names.index -join '|') -ceq '0|1|2') 'selected native plan keeps original ordered duplicate names'
    }

    Invoke-ProbeIntakeTestCase 'explicit-empty-definition-is-not-activation' {
        $plan = New-ProbeIntakeTestPlan $populated @($emptyDefinition)
        $result = Read-ProbeIntakeTestPlan 'empty-definition' $plan $populated.inputs
        Assert-ProbeIntakeTest ($result.pairs.Count -eq 1 -and $result.pairs[0].overlayNameOccurrences.Count -eq 0) 'an explicit empty definition remains a selectable observed definition'
        Assert-ProbeIntakeTest (-not $result.pairs[0].hasExpectedOverlays) 'an empty definition cannot invent an expected overlay load'
        Assert-ProbeIntakeTest (@($result.dispositions | Where-Object { $_.disposition -ceq 'selected' -and $_.expectedOverlayNameCount -eq 0 }).Count -eq 2) 'both empty-definition candidates remain accounted for'
    }

    Invoke-ProbeIntakeTestCase 'sixteen-distinct-modules-with-duplicate-occurrence' {
        $plan = New-ProbeIntakeTestPlan $populated @($sixteen)
        $result = Read-ProbeIntakeTestPlan 'sixteen-modules' $plan $populated.inputs
        Assert-ProbeIntakeTest ($result.pairs[0].overlayNameOccurrences.Count -eq 17) 'sixteen distinct modules plus one repeated occurrence fit the distinct-module cap'
        Assert-ProbeIntakeTest ($result.pairs[0].overlayNameOccurrences[0].name -ceq $result.pairs[0].overlayNameOccurrences[16].name) 'the repeated occurrence is retained at the cap'
    }

    Invoke-ProbeIntakeTestCase 'keyword-module-names-remain-literal-plan-data' {
        $keyword = @($lexical.definitions | Where-Object { $_.context.declaringModuleClaim -ceq 'class' })[0]
        $plan = New-ProbeIntakeTestPlan $lexical @($keyword)
        $result = Read-ProbeIntakeTestPlan 'keyword-names' $plan $lexical.inputs
        Assert-ProbeIntakeTest ($result.pairs[0].declaringModule -ceq 'class' -and $result.pairs[0].bystanderModule -ceq 'actor' -and $result.pairs[0].overlayNameOccurrences[0].name -ceq 'repeat') 'ASCII keywords are preserved for the native builder to quote, not interpreted as source here'
        $longDefinition = @($lexical.definitions | Where-Object { $_.context.declaringModuleClaim -ceq 'OverLength' })[0]
        Assert-ProbeIntakeTest (@($result.dispositions | Where-Object { $_.definitionOccurrenceId -ceq $longDefinition.recordId -and $_.disposition -ceq 'unselected' }).Count -eq 2) 'an unselected 129-character name remains in the census dispositions without entering native source'
    }

    Invoke-ProbeIntakeTestCase 'selected-128-character-native-module-name' {
        $definition = @($lexical.definitions | Where-Object { $_.context.declaringModuleClaim -ceq 'AllowedLength' })[0]
        $plan = New-ProbeIntakeTestPlan $lexical @($definition)
        $result = Read-ProbeIntakeTestPlan 'allowed-module-length' $plan $lexical.inputs
        Assert-ProbeIntakeTest ($result.pairs[0].overlayNameOccurrences[0].name.Length -eq 128) 'a source-backed 128-character ASCII module name remains selectable'
    }

    Invoke-ProbeIntakeRejectedPlan 'plan-zero-pairs' $empty (New-ProbeIntakeTestPlan $empty @())
    $fiveDefinitions = @($populated.definitions | Where-Object { $_.context.declaringModuleClaim -cne 'Sixteen' })
    Invoke-ProbeIntakeRejectedPlan 'plan-five-pairs' $populated (New-ProbeIntakeTestPlan $populated $fiveDefinitions)
    Invoke-ProbeIntakeRejectedPlan 'plan-seventeen-distinct-modules-across-pairs' $populated (New-ProbeIntakeTestPlan $populated @($sixteen, $foundation))
    Invoke-ProbeIntakeRejectedPlan 'plan-stale-sha256' $populated $singlePlan -WrongHash
    Invoke-ProbeIntakeRejectedPlan 'plan-schema-boolean-is-not-an-integer' $populated $singlePlan -Mutate { param($plan) $plan.schemaVersion = $true }
    Invoke-ProbeIntakeRejectedPlan 'plan-schema-string-is-not-an-integer' $populated $singlePlan -Mutate { param($plan) $plan.schemaVersion = '1' }
    Invoke-ProbeIntakeRejectedPlan 'plan-schema-float-is-not-an-integer' $populated $singlePlan -MutateText {
        param($text)
        return [regex]::Replace($text, '"schemaVersion"\s*:\s*1\b', '"schemaVersion": 1.0')
    }
    Invoke-ProbeIntakeRejectedPlan 'plan-limit-boolean-is-not-an-integer' $populated $singlePlan -Mutate { param($plan) $plan.limits.maximumDefinitionPairs = $true }
    Invoke-ProbeIntakeRejectedPlan 'plan-limit-string-is-not-an-integer' $populated $singlePlan -Mutate { param($plan) $plan.limits.maximumDefinitionPairs = '4' }
    Invoke-ProbeIntakeRejectedPlan 'plan-duplicate-json-key' $populated $singlePlan -MutateText {
        param($text)
        return $text.Insert($text.IndexOf('{') + 1, '"schemaVersion":1,')
    }
    Invoke-ProbeIntakeRejectedPlan 'plan-over-one-mib' $populated $singlePlan -MutateText {
        param($text)
        return $text + (' ' * (1MB + 1 - $script:ProbeIntakeUTF8.GetByteCount($text)))
    }
    Invoke-ProbeIntakeRejectedPlan 'plan-arbitrary-source-rejected' $populated $singlePlan -Mutate {
        param($plan)
        $plan | Add-Member -NotePropertyName source -NotePropertyValue 'import Arbitrary; #error("must not run")'
    }
    Invoke-ProbeIntakeRejectedPlan 'plan-module-map-copy-relocation-rejected' $populated $singlePlan -Mutate {
        param($plan)
        $plan.pairs[0] | Add-Member -NotePropertyName moduleMapPath -NotePropertyValue 'raw/0000000000000000000000000000000000000000000000000000000000000000.bin'
    }
    Invoke-ProbeIntakeRejectedPlan 'plan-arbitrary-search-root-rejected' $populated $singlePlan -Mutate {
        param($plan)
        $plan | Add-Member -NotePropertyName searchPaths -NotePropertyValue @('/tmp/unreviewed-modules')
    }
    Invoke-ProbeIntakeRejectedPlan 'plan-missing-target' $populated $singlePlan -Mutate { param($plan) $plan.targetContexts = @($plan.targetContexts[0]) }
    Invoke-ProbeIntakeRejectedPlan 'plan-duplicate-target' $populated $singlePlan -Mutate { param($plan) $plan.targetContexts[1] = Copy-ProbeIntakeTestValue $plan.targetContexts[0] }
    Invoke-ProbeIntakeRejectedPlan 'plan-invented-target-variant' $populated $singlePlan -Mutate { param($plan) $plan.targetContexts[0].targetVariant = 'arm64e-apple-ios-macabi' }
    Invoke-ProbeIntakeRejectedPlan 'plan-cxx-mode-missing-one-target' $populated $fourPlan -Mutate { param($plan) $plan.targetContexts = @($plan.targetContexts[0], $plan.targetContexts[1], $plan.targetContexts[2]) }
    Invoke-ProbeIntakeRejectedPlan 'plan-unrecognized-cxx-mode' $populated $singlePlan -Mutate { param($plan) $plan.targetContexts[0].cxxInteroperabilityMode = 'experimental' }
    Invoke-ProbeIntakeRejectedPlan 'plan-source-binding-mismatch' $populated $singlePlan -Mutate { param($plan) $plan.sourceArtifacts.discoveryManifestSha256 = '0' * 64 }
    Invoke-ProbeIntakeRejectedPlan 'plan-native-profile-not-a-hash' $populated $singlePlan -Mutate { param($plan) $plan.nativeProfileSha256 = '../profile.json' }
    Invoke-ProbeIntakeRejectedPlan 'plan-wrong-language-mode' $populated $singlePlan -Mutate { param($plan) $plan.languageMode = '5' }
    Invoke-ProbeIntakeRejectedPlan 'plan-declaring-module-source-injection' $populated $singlePlan -Mutate { param($plan) $plan.pairs[0].declaringModule = 'Other; import Injected' }
    Invoke-ProbeIntakeRejectedPlan 'plan-bystander-module-argument-injection' $populated $singlePlan -Mutate { param($plan) $plan.pairs[0].bystanderModule = '-Xfrontend' }
    Invoke-ProbeIntakeRejectedPlan 'plan-overlay-module-source-injection' $populated $singlePlan -Mutate { param($plan) $plan.pairs[0].overlayNameOccurrences[0].name = "Overlay`nimport Injected" }
    $underscore = @($lexical.definitions | Where-Object { $_.context.declaringModuleClaim -ceq '_' })[0]
    Invoke-ProbeIntakeRejectedPlan 'plan-bare-underscore-module-rejected' $lexical (New-ProbeIntakeTestPlan $lexical @($underscore))
    $overLength = @($lexical.definitions | Where-Object { $_.context.declaringModuleClaim -ceq 'OverLength' })[0]
    Invoke-ProbeIntakeRejectedPlan 'plan-source-backed-129-character-module-rejected' $lexical (New-ProbeIntakeTestPlan $lexical @($overLength))
    Invoke-ProbeIntakeRejectedPlan 'plan-dropped-duplicate-name-occurrence' $populated $singlePlan -Mutate {
        param($plan)
        $plan.pairs[0].overlayNameOccurrences = @($plan.pairs[0].overlayNameOccurrences[0], $plan.pairs[0].overlayNameOccurrences[2])
        $plan.pairs[0].overlayNameOccurrences[1].index = 1
    }
    Invoke-ProbeIntakeRejectedPlan 'plan-missing-source-candidate' $populated $singlePlan -Mutate { param($plan) $plan.pairs[0].sourceCandidateIds = @($plan.pairs[0].sourceCandidateIds[0]) }
    Invoke-ProbeIntakeRejectedPlan 'plan-duplicate-source-candidate' $populated $singlePlan -Mutate { param($plan) $plan.pairs[0].sourceCandidateIds[1] = $plan.pairs[0].sourceCandidateIds[0] }
    Invoke-ProbeIntakeRejectedPlan 'plan-duplicate-definition-pair' $populated $singlePlan -Mutate { param($plan) $plan.pairs = @($plan.pairs[0], (Copy-ProbeIntakeTestValue $plan.pairs[0])) }
    Invoke-ProbeIntakeRejectedPlan 'plan-pair-id-not-bound-to-definition' $populated $singlePlan -Mutate { param($plan) $plan.pairs[0].pairId = '0' * 64 }
    Invoke-ProbeIntakeRejectedPlan 'plan-stale-raw-definition-hash' $populated $singlePlan -Mutate { param($plan) $plan.pairs[0].rawDefinitionSha256 = '0' * 64 }
    Invoke-ProbeIntakeRejectedPlan 'plan-limit-cannot-expand-pair-scope' $populated $singlePlan -Mutate { param($plan) $plan.limits.maximumDefinitionPairs = 5 }
    Invoke-ProbeIntakeRejectedPlan 'plan-limit-cannot-expand-module-scope' $populated $singlePlan -Mutate { param($plan) $plan.limits.maximumDistinctOverlayModules = 17 }

    Invoke-ProbeIntakeRejectedDiscovery 'candidate-borrows-different-definition-context' $populated {
        param($copy)
        $rows = $copy.streams['candidate-pairs.ndjson']
        $first = @($rows | Where-Object { $_.declaringModuleClaim -ceq 'Other' -and $_.bystanderModuleClaim -ceq 'SwiftUI' })[0]
        $second = @($rows | Where-Object { $_.declaringModuleClaim -ceq 'SwiftUI' -and $_.target -ceq $first.target })[0]
        $saved = $first.definitionOccurrenceId
        $first.definitionOccurrenceId = $second.definitionOccurrenceId; $second.definitionOccurrenceId = $saved
        foreach ($row in @($first, $second)) { $row.recordId = Get-SwiftUIOverlayId @('candidate', $row.definitionOccurrenceId, $row.target) }
    }
    Invoke-ProbeIntakeRejectedDiscovery 'candidate-drops-one-duplicate-overlay-name' $populated {
        param($copy)
        $row = @($copy.streams['candidate-pairs.ndjson'] | Where-Object { $_.expectedOverlayNameOccurrences.Count -eq 3 })[0]
        $row.expectedOverlayNameOccurrences = @($row.expectedOverlayNameOccurrences[0], $row.expectedOverlayNameOccurrences[2])
        $row.expectedOverlayNameOccurrences[1].index = 1
    }
    Invoke-ProbeIntakeRejectedDiscovery 'candidate-missing-despite-complete-counts' $populated {
        param($copy)
        $rows = $copy.streams['candidate-pairs.ndjson']
        $copy.streams['candidate-pairs.ndjson'] = @($rows[1..($rows.Count - 1)])
    }
    Invoke-ProbeIntakeRejectedDiscovery 'candidate-duplicates-one-target-and-omits-the-other' $populated {
        param($copy)
        $rows = $copy.streams['candidate-pairs.ndjson']
        $first = $rows[0]
        $second = @($rows | Where-Object { $_.definitionOccurrenceId -ceq $first.definitionOccurrenceId -and $_.target -cne $first.target })[0]
        $second.target = $first.target; $second.recordId = $first.recordId
    }
    Invoke-ProbeIntakeRejectedDiscovery 'definition-borrows-byte-identical-alias-raw-copy' $populated {
        param($copy)
        $rows = @($copy.streams['definition-facts.ndjson'] | Where-Object { $_.kind -ceq 'definition-file' -and $_.nameOccurrences.Count -eq 3 })
        $saved = $rows[0].rawFile.path
        $rows[0].rawFile.path = $rows[1].rawFile.path; $rows[1].rawFile.path = $saved
    }
    Invoke-ProbeIntakeRejectedDiscovery 'definition-laundered-through-another-selected-root' $populated {
        param($copy)
        $definition = @($copy.streams['definition-facts.ndjson'] | Where-Object { $_.kind -ceq 'definition-file' })[0]
        $definition.rootId = 'selected-swift-resources'
        $receipt = @($copy.streams['filesystem-facts.ndjson'] | Where-Object { $_.kind -ceq 'candidate-copy' -and $_.sourceOccurrenceId -ceq $definition.filesystemOccurrenceId })[0]
        $receipt.rootId = 'selected-swift-resources'
    }
    Invoke-ProbeIntakeRejectedDiscovery 'definition-crosslinks-a-module-map-filesystem-entry' $populated {
        param($copy)
        $definition = @($copy.streams['definition-facts.ndjson'] | Where-Object { $_.kind -ceq 'definition-file' })[0]
        $map = @($copy.streams['module-context-facts.ndjson'] | Where-Object { $_.kind -ceq 'clang-module-map' })[0]
        $oldId = $definition.recordId
        $definition.filesystemOccurrenceId = $map.filesystemOccurrenceId
        $definition.recordId = Get-SwiftUIOverlayId @('definition', $definition.filesystemOccurrenceId, $definition.rawFile.sha256)
        foreach ($candidate in $copy.streams['candidate-pairs.ndjson']) {
            if ($candidate.definitionOccurrenceId -ceq $oldId) {
                $candidate.definitionOccurrenceId = $definition.recordId
                $candidate.recordId = Get-SwiftUIOverlayId @('candidate', $definition.recordId, $candidate.target)
            }
        }
    }
    Invoke-ProbeIntakeRejectedDiscovery 'filesystem-parent-receipts-swapped' $populated {
        param($copy)
        $entries = @($copy.streams['filesystem-facts.ndjson'] | Where-Object { $_.kind -ceq 'directory-entry' -and $_.logicalPath.EndsWith('/SwiftUI.swiftoverlay') -and $_.entryKind -ceq 'file' })
        $first = $entries[0]
        $second = @($entries | Where-Object { $_.parentDirectoryId -cne $first.parentDirectoryId -and $_.physicalPath -cne $first.physicalPath })[0]
        $oldFirst = $first.parentDirectoryId; $oldSecond = $second.parentDirectoryId
        $first.parentDirectoryId = $oldSecond; $second.parentDirectoryId = $oldFirst
        foreach ($nameRow in $copy.streams['filesystem-facts.ndjson']) {
            if ($nameRow.kind -cne 'directory-entry-name') { continue }
            if ($nameRow.parentDirectoryId -ceq $oldFirst -and $nameRow.reportedPhysicalPath -ceq $first.physicalPath) { $nameRow.parentDirectoryId = $oldSecond }
            elseif ($nameRow.parentDirectoryId -ceq $oldSecond -and $nameRow.reportedPhysicalPath -ceq $second.physicalPath) { $nameRow.parentDirectoryId = $oldFirst }
        }
    }
    Invoke-ProbeIntakeRejectedDiscovery 'ordinary-child-subtree-omitted-with-resealed-counts' $populated {
        param($copy)
        $rows = $copy.streams['filesystem-facts.ndjson']
        $child = @($rows | Where-Object { $_.kind -ceq 'directory-open' -and $_.logicalPath.EndsWith('/Plain/Child') })[0]
        $leafEntries = @($rows | Where-Object { $_.kind -ceq 'directory-entry' -and $_.parentDirectoryId -ceq $child.recordId })
        Assert-ProbeIntakeTest ($null -ne $child -and $leafEntries.Count -eq 1 -and $leafEntries[0].logicalPath.EndsWith('/leaf.txt')) 'the omitted subtree contains only a plain file, so no missing definition or module-map join can mask the traversal defect'
        $copy.streams['filesystem-facts.ndjson'] = @($rows | Where-Object {
            -not (($_.kind -ceq 'directory-open' -and $_.recordId -ceq $child.recordId) -or
                ($_.kind -cin @('directory-entry-name', 'directory-entry') -and $_.parentDirectoryId -ceq $child.recordId) -or
                ($_.kind -ceq 'directory-complete' -and $_.directoryId -ceq $child.recordId))
        })
        $copy.manifest.counts.directories--
        $copy.manifest.counts.enumerationPasses -= 2
        $copy.manifest.counts.filesystemEntries -= 2 * $leafEntries.Count
        # The parent's observed Child directory entry remains. The report now
        # seals the smaller stream and matching totals but falsely claims that
        # all observed child directories received completed traversal.
    } -ExpectedMessagePattern 'omitted from completed traversal'
    Invoke-ProbeIntakeRejectedDiscovery 'finite-truncated-physical-ancestor-alias-cycle' $populated {
        param($copy)
        $rows = $copy.streams['filesystem-facts.ndjson']
        $child = @($rows | Where-Object { $_.kind -ceq 'directory-open' -and $_.logicalPath.EndsWith('/Plain/Child') })[0]
        $entry = @($rows | Where-Object { $_.kind -ceq 'directory-entry' -and $_.recordId -ceq $child.sourceEntryId })[0]
        $parent = @($rows | Where-Object { $_.kind -ceq 'directory-open' -and $_.recordId -ceq $entry.parentDirectoryId })[0]
        $completion = @($rows | Where-Object { $_.kind -ceq 'directory-complete' -and $_.directoryId -ceq $child.recordId })[0]
        $leaves = @($rows | Where-Object { $_.kind -ceq 'directory-entry' -and $_.parentDirectoryId -ceq $child.recordId })
        Assert-ProbeIntakeTest ($entry.entryKind -ceq 'directory' -and $leaves.Count -eq 1 -and $leaves[0].logicalPath.EndsWith('/leaf.txt')) 'the cycle mutation begins with a real ordinary child and no candidate-copy dependencies'
        $entry.entryKind = 'symlink'; $entry.rawLinkTarget = '.'; $entry.attributes = 'ReparsePoint'
        $entry.beforeMetadata.kind = 'symlink'; $entry.beforeMetadata.linkTarget = '.'; $entry.beforeMetadata.attributes = 'ReparsePoint'
        $aliasOrdinal = $copy.streams['alias-facts.ndjson'].Count + 1
        $alias = [pscustomobject]@{
            kind = 'alias-resolution'
            recordId = Get-SwiftUIOverlayId @('alias', $entry.logicalPath, $entry.physicalPath, '.', [string]$aliasOrdinal)
            logicalOccurrence = $entry.logicalPath; logicalPath = $entry.physicalPath; rawTarget = '.'
            resolutionChain = @($entry.physicalPath)
            resolvedTargetCandidate = $parent.physicalPath; effectiveTargetCandidate = $parent.physicalPath
            targetRootId = $entry.rootId; disposition = 'followed-in-allowlist'
        }
        $copy.streams['alias-facts.ndjson'] = @($copy.streams['alias-facts.ndjson']) + @($alias)
        $child.physicalPath = $parent.physicalPath; $child.repeatedPhysicalDestination = $true
        $completion.physicalPath = $parent.physicalPath; $completion.childCount = 0
        $completion.matchedDirectChildCount = 0; $completion.state = 'readable-empty'
        $copy.streams['filesystem-facts.ndjson'] = @($rows | Where-Object {
            -not ($_.kind -cin @('directory-entry-name', 'directory-entry') -and $_.parentDirectoryId -ceq $child.recordId)
        })
        $copy.manifest.counts.filesystemEntries -= 2 * $leaves.Count
        $copy.manifest.counts.aliasOccurrences++
        # All source IDs, depths, parent completion and alias destinations agree.
        # The forged empty completion makes this finite, but opening Child now
        # revisits its own physical parent and cannot prove complete traversal.
    } -ExpectedMessagePattern 'physical ancestor'
    Invoke-ProbeIntakeRejectedDiscovery 'present-optional-root-relabeled-absent' $optionalPresent {
        param($copy)
        $root = @($copy.manifest.roots | Where-Object { $_.rootId -ceq 'platform-developer-frameworks' })[0]
        Assert-ProbeIntakeTest ($root.state -ceq 'readable-complete' -and $root.traversalComplete) 'the mutation starts from an actually traversed optional root'
        $root.state = 'absent-confirmed'
        # Both aggregate states are individually legal for a selected optional
        # root. Only semantic comparison with the sealed filesystem facts can
        # distinguish this forged absence from the original present traversal.
    } -ExpectedMessagePattern 'Aggregate root state'
    Invoke-ProbeIntakeRejectedDiscovery 'raw-copy-source-observed-length-mismatch' $populated {
        param($copy)
        $entry = @($copy.streams['filesystem-facts.ndjson'] | Where-Object { $_.kind -ceq 'directory-entry' -and $_.logicalPath.EndsWith('/SwiftUI.swiftcrossimport/Foundation.swiftoverlay') })[0]
        Assert-ProbeIntakeTest ($entry.entryKind -ceq 'file' -and $entry.beforeMetadata.kind -ceq 'file') 'the source occurrence is an ordinary file, not an alias with different link metadata'
        $entry.beforeMetadata.length++
    } -ExpectedMessagePattern 'regular file.*observed copied length'
    Invoke-ProbeIntakeRejectedDiscovery 'raw-copy-source-observed-kind-mismatch' $populated {
        param($copy)
        $entry = @($copy.streams['filesystem-facts.ndjson'] | Where-Object { $_.kind -ceq 'directory-entry' -and $_.logicalPath.EndsWith('/SwiftUI.swiftcrossimport/Foundation.swiftoverlay') })[0]
        Assert-ProbeIntakeTest ($entry.entryKind -ceq 'file' -and $entry.beforeMetadata.kind -ceq 'file') 'the original copied source is a regular file'
        $entry.entryKind = 'directory'; $entry.beforeMetadata.kind = 'directory'
        $entry.attributes = 'Directory'; $entry.beforeMetadata.attributes = 'Directory'
        $entry.beforeMetadata.length = 0
        # Entry fields and its metadata still agree; the raw-copy observation
        # is what contradicts this forged directory kind.
    } -ExpectedMessagePattern 'regular file.*observed copied length'
    Invoke-ProbeIntakeRejectedDiscovery 'module-map-copies-cannot-be-relocated-to-raw-storage' $populated {
        param($copy)
        $map = @($copy.streams['module-context-facts.ndjson'] | Where-Object { $_.kind -ceq 'clang-module-map' -and $_.logicalPath.Contains('/Aliases/') })[0]
        $wrong = '/raw-relocation/' + ($map.rawFile.path -replace '^raw/', '')
        $map.physicalPath = $wrong
        $receipt = @($copy.streams['filesystem-facts.ndjson'] | Where-Object { $_.kind -ceq 'candidate-copy' -and $_.sourceOccurrenceId -ceq $map.filesystemOccurrenceId })[0]
        $receipt.physicalPath = $wrong
        $manifestCopy = @($copy.manifest.copiedFiles | Where-Object { $_.sourceOccurrenceId -ceq $map.filesystemOccurrenceId })[0]
        $manifestCopy.physicalPath = $wrong
    }
    Invoke-ProbeIntakeRejectedDiscovery 'module-map-copies-cannot-borrow-same-byte-map-context' $populated {
        param($copy)
        $maps = @($copy.streams['module-context-facts.ndjson'] | Where-Object { $_.kind -ceq 'clang-module-map' })
        $alias = @($maps | Where-Object { $_.logicalPath.Contains('/Aliases/') })[0]
        $other = @($maps | Where-Object { $_.logicalPath.Contains('/Mirror/') })[0]
        Assert-ProbeIntakeTest ($alias.rawFile.sha256 -ceq $other.rawFile.sha256 -and $alias.physicalPath -cne $other.physicalPath) 'the relocation fixture has identical map bytes but a different original directory context'
        $alias.physicalPath = $other.physicalPath
        $receipt = @($copy.streams['filesystem-facts.ndjson'] | Where-Object { $_.kind -ceq 'candidate-copy' -and $_.sourceOccurrenceId -ceq $alias.filesystemOccurrenceId })[0]
        $receipt.physicalPath = $other.physicalPath
        $manifestCopy = @($copy.manifest.copiedFiles | Where-Object { $_.sourceOccurrenceId -ceq $alias.filesystemOccurrenceId })[0]
        $manifestCopy.physicalPath = $other.physicalPath
    }
    Invoke-ProbeIntakeRejectedDiscovery 'module-map-borrows-identical-alias-copy' $populated {
        param($copy)
        $maps = @($copy.streams['module-context-facts.ndjson'] | Where-Object { $_.kind -ceq 'clang-module-map' -and -not $_.logicalPath.Contains('/Mirror/') })
        $saved = $maps[0].rawFile.path
        $maps[0].rawFile.path = $maps[1].rawFile.path; $maps[1].rawFile.path = $saved
    }
    Invoke-ProbeIntakeRejectedDiscovery 'module-map-claims-native-grammar-validation' $populated {
        param($copy)
        $map = @($copy.streams['module-context-facts.ndjson'] | Where-Object { $_.kind -ceq 'clang-module-map' })[0]
        $map.moduleMapGrammarParsed = $true; $map.moduleNameClaim = 'Other'
    }
    Invoke-ProbeIntakeRejectedDiscovery 'definition-raw-content-no-longer-matches-projection' $populated {
        param($copy)
        $definition = @($copy.streams['definition-facts.ndjson'] | Where-Object { $_.kind -ceq 'definition-file' -and $_.nameOccurrences.Count -eq 3 })[0]
        $path = Get-SwiftUIAuditTestFilePath -Root $copy.root -RelativePath $definition.rawFile.path
        $text = [IO.File]::ReadAllText($path, $script:ProbeIntakeUTF8).Replace('PublicOverlay', 'Other_Overlay')
        Write-ProbeIntakeTestText $path $text
        $oldId = $definition.recordId
        $definition.rawFile.sha256 = Get-SwiftUIAuditTestHash $path
        $definition.rawFile.bytes = (Get-Item -LiteralPath $path).Length
        $definition.recordId = Get-SwiftUIOverlayId @('definition', $definition.filesystemOccurrenceId, $definition.rawFile.sha256)
        $receipt = @($copy.streams['filesystem-facts.ndjson'] | Where-Object { $_.kind -ceq 'candidate-copy' -and $_.sourceOccurrenceId -ceq $definition.filesystemOccurrenceId })[0]
        $receipt.capturedBytesSha256 = $definition.rawFile.sha256; $receipt.capturedBytes = $definition.rawFile.bytes
        foreach ($candidate in $copy.streams['candidate-pairs.ndjson']) {
            if ($candidate.definitionOccurrenceId -ceq $oldId) {
                $candidate.definitionOccurrenceId = $definition.recordId
                $candidate.recordId = Get-SwiftUIOverlayId @('candidate', $definition.recordId, $candidate.target)
            }
        }
        # Raw bytes, manifest seals, copy receipts and derived IDs now agree.
        # Only the old decoded name projections disagree with the actual YAML.
    }

} catch { $failure = $_ }
finally {
    if ($null -ne $beforeSources) {
        Invoke-ProbeIntakeTestCase 'source-capture-and-nine-ledger-streams-unchanged' {
            $integrity.sourcePreserved = (Get-ProbeIntakeTestSnapshot @($script:ProbeIntakeCapture.Root, $script:ProbeIntakeAuditRoot)) -ceq $beforeSources
            Assert-ProbeIntakeTest $integrity.sourcePreserved 'the source capture and every original audit artifact remain byte-for-byte intact'
        }
    }
    if ($null -ne $beforeCensuses) {
        Invoke-ProbeIntakeTestCase 'positive-census-fixtures-unchanged' {
            $integrity.censusesPreserved = (Get-ProbeIntakeTestSnapshot $immutableRoots.ToArray()) -ceq $beforeCensuses
            Assert-ProbeIntakeTest $integrity.censusesPreserved 'all positive Stage A census bytes stay unchanged while only separate negative copies are resealed'
        }
    }
    $failedCases = @($script:ProbeIntakeCases | Where-Object { $_.outcome -ceq 'failed' })
    $skippedCases = @($script:ProbeIntakeCases | Where-Object { $_.outcome -ceq 'skipped' })
    $result = [ordered]@{
        schemaVersion = 1; evidenceKind = 'synthetic-overlay-probe-intake-tests'; syntheticFixture = $true
        powerShellVersion = $PSVersionTable.PSVersion.ToString(); assertionsPassed = $script:ProbeIntakeAssertions
        cases = $script:ProbeIntakeCases.ToArray(); failedCaseCount = $failedCases.Count; skippedCaseCount = $skippedCases.Count
        sourceCaptureAndAuditPreserved = $integrity.sourcePreserved; positiveCensusesPreserved = $integrity.censusesPreserved
        nativeSDKCommandsExecuted = $false; nativeOverlayLoadsObserved = $false; supplementalGraphsProduced = $false
        managedHelper = 'existing strict JSON and synthetic capture/audit streaming writer; no new managed source'
        outcome = $(if ($null -eq $failure -and $failedCases.Count -eq 0) { 'passed' } else { 'failed' })
        setupFailure = $(if ($null -eq $failure) { $null } else { $failure.ToString() })
        setupStackTrace = $(if ($null -eq $failure) { $null } else { $failure.ScriptStackTrace })
    }
    Write-ProbeIntakeTestJson (Get-ProbeIntakeTestPath 'test-results.json') $result
}
if ($null -ne $failure) { throw $failure }
if ($failedCases.Count -gt 0) { throw ("Overlay probe intake cases failed: " + ($failedCases.name -join ', ')) }
Write-Output ("Overlay probe intake tests passed: " + ($script:ProbeIntakeCases.Count - $skippedCases.Count) + " passed, " + $skippedCases.Count + " skipped; " + $script:ProbeIntakeAssertions + " assertions; synthetic PS" + $PSVersionTable.PSVersion + ".")
Write-Output ("Receipts: " + (Get-ProbeIntakeTestPath 'test-results.json'))
