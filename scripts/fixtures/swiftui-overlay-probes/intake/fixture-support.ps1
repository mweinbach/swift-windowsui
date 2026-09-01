# Synthetic Stage B intake test helpers. Dot-sourcing defines functions only.
# Existing capture/audit/census producers create the source evidence. Negative
# tests reseal separate owned census copies; none changes the source ledger.

function Assert-ProbeIntakeTest {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw "Overlay probe intake assertion failed: $Message" }
    $script:ProbeIntakeAssertions++
}

function Get-ProbeIntakeTestPath {
    param([Parameter(Mandatory)][string]$RelativePath)
    return Get-SwiftUIAuditTestFilePath -Root $script:ProbeIntakeOutput -RelativePath $RelativePath
}

function Write-ProbeIntakeTestText {
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyString()][string]$Text)
    [void](Get-SwiftUIBaselineRelativePath $script:ProbeIntakeOutput $Path)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, $script:ProbeIntakeUTF8)
}

function Write-ProbeIntakeTestJson {
    param([Parameter(Mandatory)][string]$Path, $Value)
    Write-ProbeIntakeTestText $Path ((ConvertTo-Json -InputObject $Value -Depth 40 -WarningAction Stop) + [char]10)
}

function Read-ProbeIntakeTestJson {
    param([Parameter(Mandatory)][string]$Path)
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -gt 8MB) { throw 'Only small owned intake fixture JSON may enter the test DOM helper.' }
    $arguments = @{ InputObject = [IO.File]::ReadAllText($Path, $script:ProbeIntakeUTF8); ErrorAction = 'Stop' }
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $arguments.DateKind = 'String' }
    return ConvertFrom-Json @arguments
}

function Copy-ProbeIntakeTestValue {
    param($Value)
    $arguments = @{ InputObject = (ConvertTo-Json -InputObject $Value -Depth 40 -Compress -WarningAction Stop); ErrorAction = 'Stop' }
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $arguments.DateKind = 'String' }
    return ConvertFrom-Json @arguments
}

function Read-ProbeIntakeTestRows {
    param([Parameter(Mandatory)][string]$Path)
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -gt 8MB) { throw 'Only small owned census streams may enter the test DOM helper.' }
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($line in [IO.File]::ReadAllLines($Path, $script:ProbeIntakeUTF8)) {
        if ($line.Length -eq 0) { throw 'Synthetic census streams must not contain blank records.' }
        $arguments = @{ InputObject = $line; ErrorAction = 'Stop' }
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $arguments.DateKind = 'String' }
        [void]$rows.Add((ConvertFrom-Json @arguments))
    }
    return $rows.ToArray()
}

function Get-ProbeIntakeTestSnapshot {
    param([Parameter(Mandatory)][string[]]$Roots)
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($root in $Roots) {
        $paths = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction Stop)
        if ($paths.Count -gt 512) { throw 'Synthetic integrity snapshot exceeds its file-count budget.' }
        foreach ($file in $paths) {
            [void](Get-SwiftUIBaselineRelativePath $script:ProbeIntakeOutput $file.FullName)
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Synthetic integrity snapshot must not follow a reparse-point file.' }
            [void]$entries.Add([pscustomobject]@{
                path = $file.FullName; bytes = $file.Length
                sha256 = Get-SwiftUIAuditTestHash $file.FullName
            })
        }
    }
    return ConvertTo-Json -InputObject @($entries | Sort-Object -Property path -CaseSensitive) -Depth 4 -Compress
}

function Invoke-ProbeIntakeTestCase {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Action)
    if (-not $script:ProbeIntakeCaseNames.Add($Name)) { throw "Duplicate intake test case: $Name" }
    $beforeAssertions = $script:ProbeIntakeAssertions
    $details = $null; $caught = $null
    try { $details = @(& $Action) }
    catch { $caught = $_ }
    [void]$script:ProbeIntakeCases.Add([pscustomobject]@{
        name = $Name; outcome = $(if ($null -eq $caught) { 'passed' } else { 'failed' })
        assertionsPassed = $script:ProbeIntakeAssertions - $beforeAssertions
        details = $details
        failure = $(if ($null -eq $caught) { $null } else { $caught.ToString() })
        scriptStackTrace = $(if ($null -eq $caught) { $null } else { $caught.ScriptStackTrace })
    })
}

function Get-ProbeIntakeTestRejection {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Message, [string]$ExpectedMessagePattern)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-ProbeIntakeTest ($null -ne $caught) $Message
    Assert-ProbeIntakeTest ($caught.Exception -isnot [Management.Automation.CommandNotFoundException] -and $caught.Exception -isnot [Management.Automation.ParameterBindingException]) 'a missing command or incorrect test invocation is not a validation rejection'
    if (-not [string]::IsNullOrEmpty($ExpectedMessagePattern)) {
        Assert-ProbeIntakeTest ($caught.Exception.Message -match $ExpectedMessagePattern) 'rejection reports the intended validation boundary'
    }
    return [pscustomobject]@{ exceptionType = $caught.Exception.GetType().FullName; message = $caught.Exception.Message }
}

function Add-ProbeIntakeFixtureDefinition {
    param($Provider, [string]$Path, [AllowEmptyCollection()][string[]]$Names)
    $text = 'version: 1' + [char]10
    if ($Names.Count -eq 0) { $text += 'modules: []' + [char]10 }
    else {
        $text += 'modules:' + [char]10
        foreach ($name in $Names) { $text += '  - name: ' + $name + [char]10 }
    }
    [void](Add-SwiftUIOverlayFakeNode -Provider $Provider -Path $Path -Kind file -Text $text)
}

function New-ProbeIntakeTestCensus {
    param([Parameter(Mandatory)][ValidateSet('empty', 'populated', 'lexical', 'cross-root', 'optional-present')][string]$Kind)
    $directory = Get-ProbeIntakeTestPath ('censuses/' + $Kind)
    if (Test-Path -LiteralPath $directory) { throw 'A source census fixture must be fresh.' }
    [void][IO.Directory]::CreateDirectory($directory)
    $provider = New-SwiftUIOverlayFakeProvider -SourceContext $script:ProbeIntakeSourceContext
    $rootPlan = New-SwiftUIOverlayFakeRootPlan -SourceContext $script:ProbeIntakeSourceContext
    $sdk = @($rootPlan.roots | Where-Object { $_.rootId -ceq 'selected-sdk' })[0].logicalPath
    if ($Kind -ceq 'populated') {
        Add-ProbeIntakeFixtureDefinition $provider ($sdk + '/.hidden/Other.swiftcrossimport/SwiftUI.swiftoverlay') @('_Repeated', '_Repeated', 'PublicOverlay')
        Add-ProbeIntakeFixtureDefinition $provider ($sdk + '/.hidden/Other.swiftcrossimport/arm64e-apple-ios-macabi/SwiftUICore.swiftoverlay') @()
        Add-ProbeIntakeFixtureDefinition $provider ($sdk + '/SwiftUI.swiftcrossimport/Foundation.swiftoverlay') @('_FoundationOverlay')
        $sixteenNames = @((0..15 | ForEach-Object { 'Overlay' + $_.ToString('D2') })) + @('Overlay00')
        Add-ProbeIntakeFixtureDefinition $provider ($sdk + '/Sixteen.swiftcrossimport/SwiftUI.swiftoverlay') $sixteenNames
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/Aliases/Other.swiftcrossimport') -Kind symlink -LinkTarget '../.hidden/Other.swiftcrossimport')
        $mapText = 'framework module Other { header "Other.h" export * } // SYNTHETIC, never compiled'
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/Headers/module.modulemap') -Kind file -Text $mapText)
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/Headers/Other.h') -Kind file -Text '// SYNTHETIC header, never compiled')
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/Mirror/module.modulemap') -Kind file -Text $mapText)
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/Mirror/Other.h') -Kind file -Text '// SYNTHETIC different header context, never compiled')
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/Aliases/module.modulemap') -Kind symlink -LinkTarget '../Headers/module.modulemap')
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/Plain/Child/leaf.txt') -Kind file -Text 'SYNTHETIC ordinary subtree; no definition, module map or module location')
    } elseif ($Kind -ceq 'lexical') {
        Add-ProbeIntakeFixtureDefinition $provider ($sdk + '/_.swiftcrossimport/SwiftUI.swiftoverlay') @('UnderscoreOwnerOverlay')
        Add-ProbeIntakeFixtureDefinition $provider ($sdk + '/class.swiftcrossimport/actor.swiftoverlay') @('repeat')
        Add-ProbeIntakeFixtureDefinition $provider ($sdk + '/AllowedLength.swiftcrossimport/SwiftUI.swiftoverlay') @('Long' + ('a' * 124))
        Add-ProbeIntakeFixtureDefinition $provider ($sdk + '/OverLength.swiftcrossimport/SwiftUI.swiftoverlay') @('Long' + ('b' * 125))
    } elseif ($Kind -ceq 'cross-root') {
        $resources = @($rootPlan.roots | Where-Object { $_.rootId -ceq 'selected-swift-resources' })[0].logicalPath
        $destination = $resources + '/cross-root/Cross.swiftcrossimport'
        Add-ProbeIntakeFixtureDefinition $provider ($destination + '/SwiftUI.swiftoverlay') @('CrossRootOverlay')
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($sdk + '/CrossAlias/Cross.swiftcrossimport') -Kind symlink -LinkTarget $destination)
    } elseif ($Kind -ceq 'optional-present') {
        $optional = @($rootPlan.roots | Where-Object { $_.rootId -ceq 'platform-developer-frameworks' })[0]
        $optional.selection = 'selected-optional'
        $optional.expectedPhysicalPath = $optional.logicalPath
        $optional.allowedPhysicalBoundary = $optional.logicalPath
        [void](Add-SwiftUIOverlayFakeNode -Provider $provider -Path ($optional.logicalPath + '/ordinary.txt') -Kind file -Text 'SYNTHETIC present optional root; no native observation')
    }
    $rootPlanPath = Join-Path $directory 'requested-roots.json'
    Write-ProbeIntakeTestJson $rootPlanPath $rootPlan
    $validatedPlan = Read-SwiftUIOverlayRootPlan -Path $rootPlanPath -ExpectedSha256 (Get-SwiftUIAuditTestHash $rootPlanPath) -SourceContext $script:ProbeIntakeSourceContext
    $result = Invoke-SwiftUIOverlayCensus -SourceContext $script:ProbeIntakeSourceContext -RootPlanContext $validatedPlan -Provider $provider -OutputDirectory (Join-Path $directory 'census')
    Assert-ProbeIntakeTest $result.complete "$Kind fixture is produced by a complete real Stage A census over the fake provider"
    $report = Read-SwiftUIOverlayDiscoveryReport -Root $result.outputRoot -ExpectedManifestSha256 $result.manifestSha256 -AllowSyntheticForTests
    Assert-ProbeIntakeTest $report.report.syntheticFixture "$Kind fixture remains explicitly synthetic"
    Assert-ProbeIntakeTest ($provider.state.activeEnumerations -eq 0) "$Kind releases fake directory enumerations"
    foreach ($stream in $provider.state.openedStreams) { Assert-ProbeIntakeTest (-not $stream.CanRead) "$Kind releases fake source streams" }
    $definitions = @(Read-ProbeIntakeTestRows (Join-Path $result.outputRoot 'definition-facts.ndjson') | Where-Object { $_.kind -ceq 'definition-file' })
    $candidates = @(Read-ProbeIntakeTestRows (Join-Path $result.outputRoot 'candidate-pairs.ndjson'))
    return [pscustomobject]@{
        kind = $Kind; root = $result.outputRoot; manifestSha256 = $result.manifestSha256
        report = $report.report; definitions = $definitions; candidates = $candidates; inputs = $null
    }
}

function Read-ProbeIntakeTestInputs {
    param([Parameter(Mandatory)][string]$DiscoveryRoot, [Parameter(Mandatory)][string]$ExpectedSha256)
    return Read-SwiftUIOverlayProbeInputsInternal -CaptureRoot $script:ProbeIntakeCapture.Root -AuditRoot $script:ProbeIntakeAuditRoot -DiscoveryRoot $DiscoveryRoot -ExpectedDiscoverySha256 $ExpectedSha256 -ManifestPath $script:ProbeIntakeManifest -AllowSyntheticForTests
}

function New-ProbeIntakeTestPlan {
    param($Fixture, [AllowEmptyCollection()][object[]]$Definitions, [string[]]$Modes = @('off'), [int]$MaximumPairs = 4, [int]$MaximumModules = 16)
    $pairs = @(
        foreach ($definition in $Definitions) {
            $sourceCandidates = @($Fixture.candidates | Where-Object { $_.definitionOccurrenceId -ceq $definition.recordId })
            [pscustomobject][ordered]@{
                pairId = Get-SwiftUIOverlayId @('probe-pair', $definition.recordId)
                definitionOccurrenceId = $definition.recordId; rawDefinitionSha256 = $definition.rawFile.sha256
                declaringModule = $definition.context.declaringModuleClaim; bystanderModule = $definition.context.bystanderModuleClaim
                overlayNameOccurrences = @($definition.nameOccurrences | ForEach-Object { [pscustomobject]@{ index = $_.index; name = $_.name } })
                sourceCandidateIds = @($sourceCandidates | ForEach-Object { $_.recordId })
            }
        }
    )
    $contexts = @(
        foreach ($mode in $Modes) {
            foreach ($target in $script:ProbeIntakeSourceContext.inputs.captureContext.baselineManifest.scope.targets) {
                [pscustomobject]@{ target = $target; targetVariant = $null; cxxInteroperabilityMode = $mode }
            }
        }
    )
    return [pscustomobject][ordered]@{
        schemaVersion = 1; evidenceKind = 'swiftui-overlay-probe-plan'
        sourceArtifacts = Copy-ProbeIntakeTestValue $Fixture.inputs.sourceArtifacts
        nativeProfileSha256 = Get-SwiftUIBaselineTextHash 'SYNTHETIC native profile commitment; no native invocation'
        languageMode = '6'; targetContexts = $contexts; pairs = $pairs
        limits = [pscustomobject]@{ maximumDefinitionPairs = $MaximumPairs; maximumDistinctOverlayModules = $MaximumModules }
    }
}

function Read-ProbeIntakeTestPlan {
    param([string]$Name, $Plan, $Inputs)
    $path = Get-ProbeIntakeTestPath ('plans/' + $Name + '/plan.json')
    if (Test-Path -LiteralPath $path) { throw 'Probe plan test paths must be fresh.' }
    Write-ProbeIntakeTestJson $path $Plan
    return Read-SwiftUIOverlayProbePlanInternal -Path $path -ExpectedSha256 (Get-SwiftUIAuditTestHash $path) -Inputs $Inputs -AllowSyntheticForTests
}

function Invoke-ProbeIntakeRejectedPlan {
    param([string]$Name, $Fixture, $Plan, [scriptblock]$Mutate = {}, [scriptblock]$MutateText, [switch]$WrongHash)
    Invoke-ProbeIntakeTestCase $Name {
        $casePlan = Copy-ProbeIntakeTestValue $Plan
        & $Mutate $casePlan | Out-Null
        $path = Get-ProbeIntakeTestPath ('plans/' + $Name + '/plan.json')
        Write-ProbeIntakeTestJson $path $casePlan
        if ($null -ne $MutateText) {
            $changed = & $MutateText ([IO.File]::ReadAllText($path, $script:ProbeIntakeUTF8))
            Write-ProbeIntakeTestText $path $changed
        }
        $sha = Get-SwiftUIAuditTestHash $path
        if ($WrongHash) { $sha = '0' * 64 }
        $before = Get-SwiftUIAuditTestHash $path
        $rejection = Get-ProbeIntakeTestRejection { Read-SwiftUIOverlayProbePlanInternal -Path $path -ExpectedSha256 $sha -Inputs $Fixture.inputs -AllowSyntheticForTests } "$Name rejects the authored invalid plan"
        Assert-ProbeIntakeTest ((Get-SwiftUIAuditTestHash $path) -ceq $before) "$Name does not rewrite rejected plan bytes"
        $rejection
    }
}

function Copy-ProbeIntakeTestDiscovery {
    param([string]$Name, $Fixture)
    $root = Get-ProbeIntakeTestPath ('mutations/' + $Name + '/census')
    if (Test-Path -LiteralPath $root) { throw 'A negative discovery fixture must have a new destination.' }
    [void][IO.Directory]::CreateDirectory($root)
    $relativePaths = @('discovery.json', 'discovery.sha256', 'root-plan.json') +
        @($Fixture.report.recordStreams | ForEach-Object { $_.path }) +
        @($Fixture.report.copiedFiles | ForEach-Object { $_.path })
    foreach ($relative in $relativePaths) {
        $source = Get-SwiftUIAuditTestFilePath -Root $Fixture.root -RelativePath $relative
        $destination = Get-SwiftUIAuditTestFilePath -Root $root -RelativePath $relative
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        [IO.File]::Copy($source, $destination, $false)
    }
    $manifest = Read-ProbeIntakeTestJson (Join-Path $root 'discovery.json')
    $streams = @{}
    foreach ($stream in $manifest.recordStreams) { $streams[$stream.path] = @(Read-ProbeIntakeTestRows (Join-Path $root $stream.path)) }
    return [pscustomobject]@{ root = $root; manifest = $manifest; streams = $streams }
}

function Complete-ProbeIntakeTestDiscoverySeals {
    param($Mutation)
    $totalBytes = [long]0
    foreach ($stream in $Mutation.manifest.recordStreams) {
        $path = Get-SwiftUIAuditTestFilePath -Root $Mutation.root -RelativePath $stream.path
        $builder = [Text.StringBuilder]::new()
        $ordinal = 0
        foreach ($row in $Mutation.streams[$stream.path]) {
            # Stage A adds event IDs only to initially ID-less records, using
            # the zero-based ordinal of every row in that stream. A removal
            # must keep those unrelated automatic IDs consistent with its seal.
            if ($stream.path -ceq 'filesystem-facts.ndjson' -and $row.kind -cin @('root-state', 'absence-parent-entry', 'directory-entry-name')) {
                $row.recordId = Get-SwiftUIOverlayId @('event', 'filesystem-facts', [string]$ordinal)
            }
            [void]$builder.Append((ConvertTo-Json -InputObject $row -Depth 40 -Compress -WarningAction Stop))
            [void]$builder.Append([char]10)
            $ordinal++
        }
        Write-ProbeIntakeTestText $path $builder.ToString()
        $stream.bytes = (Get-Item -LiteralPath $path).Length
        $stream.sha256 = Get-SwiftUIAuditTestHash $path
        $stream.recordCount = $Mutation.streams[$stream.path].Count
        $totalBytes += $stream.bytes
    }
    $Mutation.manifest.counts.reportBytes = $totalBytes
    foreach ($copy in @($Mutation.manifest.copiedFiles) + @($Mutation.manifest.rootPlan)) {
        $path = Get-SwiftUIAuditTestFilePath -Root $Mutation.root -RelativePath $copy.path
        $copy.bytes = (Get-Item -LiteralPath $path).Length
        $copy.sha256 = Get-SwiftUIAuditTestHash $path
    }
    $manifestPath = Join-Path $Mutation.root 'discovery.json'
    Write-ProbeIntakeTestJson $manifestPath $Mutation.manifest
    $sha = Get-SwiftUIAuditTestHash $manifestPath
    Write-ProbeIntakeTestText (Join-Path $Mutation.root 'discovery.sha256') ($sha + '  discovery.json' + [char]10)
    return $sha
}

function Invoke-ProbeIntakeRejectedDiscovery {
    param([string]$Name, $Fixture, [scriptblock]$Mutate, [string]$ExpectedMessagePattern)
    Invoke-ProbeIntakeTestCase $Name {
        $copy = Copy-ProbeIntakeTestDiscovery $Name $Fixture
        & $Mutate $copy | Out-Null
        $sha = Complete-ProbeIntakeTestDiscoverySeals $copy
        # This assertion is outside the expected-rejection catch. Every case
        # must pass the existing integrity reader before testing semantic joins.
        $sealed = Read-SwiftUIOverlayDiscoveryReport -Root $copy.root -ExpectedManifestSha256 $sha -AllowSyntheticForTests
        Assert-ProbeIntakeTest $sealed.eligibleForFurtherReview "$Name retains valid Stage A metadata and file seals"
        $before = Get-ProbeIntakeTestSnapshot @($copy.root)
        $rejection = Get-ProbeIntakeTestRejection { Read-ProbeIntakeTestInputs $copy.root $sha } "$Name rejects semantically forged but resealed census bytes" $ExpectedMessagePattern
        Assert-ProbeIntakeTest ((Get-ProbeIntakeTestSnapshot @($copy.root)) -ceq $before) "$Name keeps rejected discovery bytes unchanged"
        [pscustomobject]@{ stageASealReaderAccepted = $true; rejection = $rejection }
    }
}
