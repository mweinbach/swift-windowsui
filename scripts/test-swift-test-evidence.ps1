<#
.SYNOPSIS
    Bounded synthetic fixtures for passive XCTest evidence on Windows PS5/PS7.
.DESCRIPTION
    Never starts Swift, a compiler, a native observer, a network request, or CI.
    Copies exactly five source text files into one owned fake workspace.
    All generated evidence is retained; existing output is never overwritten.
#>
param([string]$OutputDirectory = '')

$ErrorActionPreference = 'Stop'
$script:steFixtureSourceRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script:steFixtureRoot = $null
$script:steFixtureWorkspace = $null
$script:steFixtureAssertions = 0
$script:steFixtureEvidenceIndex = 0
$script:steFixtureForbiddenCalls = 0
$script:steFixtureResults = [Collections.Generic.List[object]]::new()
$script:steFixtureSourcePins = [Collections.Generic.List[object]]::new()
$script:steFixtureSourceBytes = @{}
$script:steFixtureSetupFailure = $null
$script:steFixtureSourceChanged = $false
$script:steFixtureUtf8 = [Text.UTF8Encoding]::new($false, $true)
$script:steFixtureInvokeDefinition = $null
$script:steFixtureExitDefinition = $null
$script:steFixtureForwardDefinition = $null
$script:steFixtureMockDefinition = $null
$script:steFixtureCollectorDefinition = $null
$script:steFixtureRequestControlIndex = 0
$script:steFixtureRequestWiring = $null
$script:steFixtureWorkflowPath = $null
$script:steFixtureWorkflowPin = $null

$script:swiftTestEvidenceSession = $null

function Get-STEFixtureHash {
    param([byte[]]$Bytes)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Read-STEFixtureSource {
    param([string]$Path)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $length = $stream.Length
        if ($length -le 0 -or $length -gt 4194304) { throw 'fixture-source-size' }
        $bytes = New-Object byte[] ([int]$length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) { throw 'fixture-source-short-read' }
            $offset += $read
        }
        if ($stream.ReadByte() -ne -1) { throw 'fixture-source-grew' }
    } finally { $stream.Dispose() }
    [void]$script:steFixtureUtf8.GetString($bytes)
    return ,$bytes
}

function ConvertFrom-STEFixtureUtf8Source {
    param([byte[]]$Bytes, [string]$SourcePath, [ref]$Tokens, [ref]$ParseErrors)
    if ($Bytes.Length -le 0 -or $Bytes.Length -gt 4194304) { throw 'fixture-source-size' }
    # Parse the same strict UTF8 text whose bytes the fixture verifies.
    $source = $script:steFixtureUtf8.GetString($Bytes)
    return [Management.Automation.Language.Parser]::ParseInput(
        $source, $SourcePath, $Tokens, $ParseErrors)
}

function Write-STEFixtureBytes {
    param([string]$Path, [byte[]]$Bytes, [switch]$ReplaceOwned)
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $script:steFixtureRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $Bytes.Length -gt 4194304) {
        throw 'fixture-write-scope'
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))
    $mode = if ($ReplaceOwned) { [IO.FileMode]::Create } else { [IO.FileMode]::CreateNew }
    $stream = [IO.File]::Open($full, $mode, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length) }
    finally { $stream.Dispose() }
}

function Write-STEFixtureText {
    param([string]$Path, [string]$Text)
    Write-STEFixtureBytes $Path $script:steFixtureUtf8.GetBytes($Text)
}

function Assert-STEFixture {
    param([bool]$Condition, [string]$Code)
    $script:steFixtureAssertions++
    if ($Code -cnotmatch '^[a-z0-9][a-z0-9-]{0,79}$') { throw 'fixture-assert-code-invalid' }
    if (-not $Condition) { throw ('fixture-assert:' + $Code) }
}

function Assert-STEFixtureEqual {
    param($Actual, $Expected, [string]$Code)
    $left = ConvertTo-Json -InputObject $Actual -Depth 16 -Compress
    $right = ConvertTo-Json -InputObject $Expected -Depth 16 -Compress
    Assert-STEFixture ([string]::Equals($left, $right, [StringComparison]::Ordinal)) $Code
}

function Assert-STEFixtureRejected {
    param([scriptblock]$Action, [string]$ExpectedCode = '', [switch]$Json, [switch]$AsPathError, [switch]$Schema)
    $failure = $null
    try { $null = & $Action } catch { $failure = $_ }
    Assert-STEFixture ($null -ne $failure) 'expected-rejection'
    $classified = $false
    if ($null -ne $failure) {
        if ($ExpectedCode.Length -gt 0) {
            $classified = $failure.Exception.Message -ceq $ExpectedCode
        } elseif ($Json) {
            $classified = ($failure.Exception.Message -cmatch '^test-evidence-json-[a-z-]+$') -or
                ($failure.FullyQualifiedErrorId -match 'ConvertFromJson') -or
                ($failure.Exception.InnerException -is [Text.DecoderFallbackException])
        } elseif ($AsPathError) {
            $classified = ($failure.Exception.Message -cmatch '^test-evidence-(path|root|destination)-[a-z-]+$') -or
                ($failure.Exception.InnerException -is [ArgumentException]) -or
                ($failure.Exception.InnerException -is [NotSupportedException])
        } elseif ($Schema) {
            $classified = $failure.Exception.Message -cmatch '^test-evidence-[a-z-]+$'
        }
    }
    Assert-STEFixture $classified 'expected-rejection-category'
}

function Invoke-STEFixture {
    param([string]$Id, [int]$ExpectedAssertions, [scriptblock]$Body)
    if ($Id -cnotmatch '^[a-z0-9][a-z0-9-]{0,79}$') { throw 'fixture-id-invalid' }
    $before = $script:steFixtureAssertions
    $status = 'passed'
    $failureCode = $null
    try {
        $leaked = @(& $Body)
        if ($leaked.Count -ne 0) { throw 'fixture-body-output' }
        if (($script:steFixtureAssertions - $before) -ne $ExpectedAssertions) { throw 'fixture-assertion-accounting' }
    } catch {
        $status = 'failed'
        $failureCode = if ($_.Exception.Message -cmatch '^fixture-assert:[a-z0-9-]+$') {
            $_.Exception.Message
        } elseif ($_.Exception.Message -cin @('fixture-body-output', 'fixture-assertion-accounting', 'fixture-observer-output')) {
            $_.Exception.Message
        } else { 'unexpected-fixture-error' }
    }
    [void]$script:steFixtureResults.Add([pscustomobject][ordered]@{
        id = $Id; status = $status; failureCode = $failureCode
        intendedAssertions = $ExpectedAssertions
        observedAssertions = $script:steFixtureAssertions - $before
    })
    Write-Host ('{0} {1}' -f $status.ToUpperInvariant(), $Id)
}

function New-STEFixtureTrace {
    param(
        [string[]]$Outcomes = @('passed'),
        [string[]]$Ids = @('FixtureTests.testOne'),
        [int]$ReportedFailures = -1,
        [int]$UnexpectedFailures = 0,
        [switch]$Nested,
        [switch]$AllTests
    )
    if ($Ids.Count -ne $Outcomes.Count) { throw 'fixture-trace-size' }
    $root = if ($AllTests) { 'All tests' } else { 'Selected tests' }
    $lines = [Collections.Generic.List[string]]::new()
    [void]$lines.Add("Test Suite '$root' started at 2026-08-28 12:01:18.464")
    if ($Nested) { [void]$lines.Add("Test Suite 'FixtureTests' started at 2026-08-28 12:01:18.464") }
    for ($i = 0; $i -lt $Ids.Count; $i++) {
        [void]$lines.Add("Test Case '$($Ids[$i])' started at 2026-08-28 12:01:18.464")
        [void]$lines.Add("Test Case '$($Ids[$i])' $($Outcomes[$i]) (0.002 seconds)")
    }
    $skips = @($Outcomes | Where-Object { $_ -ceq 'skipped' }).Count
    $failures = if ($ReportedFailures -ge 0) { $ReportedFailures } else { @($Outcomes | Where-Object { $_ -ceq 'failed' }).Count }
    $status = if ($failures -gt 0) { 'failed' } else { 'passed' }
    $testWord = if ($Ids.Count -eq 1) { 'test' } else { 'tests' }
    $skipWord = if ($skips -eq 1) { 'test' } else { 'tests' }
    $skipPart = if ($skips -gt 0) { '{0} {1} skipped and ' -f $skips, $skipWord } else { '' }
    $footer = ([string][char]9) + (' Executed {0} {1}, with {2}{3} failures ({4} unexpected) in 0.01 (0.01) seconds' -f $Ids.Count, $testWord, $skipPart, $failures, $UnexpectedFailures)
    if ($Nested) {
        [void]$lines.Add("Test Suite 'FixtureTests' $status at 2026-08-28 12:01:18.466")
        [void]$lines.Add('')
        [void]$lines.Add($footer)
    }
    [void]$lines.Add("Test Suite '$root' $status at 2026-08-28 12:01:18.466")
    [void]$lines.Add('')
    [void]$lines.Add($footer)
    return $lines.ToArray()
}

function Add-STEFixtureTrace {
    param($Recorder, [AllowNull()][object[]]$Lines)
    foreach ($line in $Lines) {
        $emitted = @(Add-SwiftTestEvidenceOutput -Recorder $Recorder -Value $line)
        if ($emitted.Count -ne 0) { throw 'fixture-observer-output' }
    }
}

function Get-STEFixtureResult {
    param([AllowNull()][object[]]$Lines, [AllowNull()]$ExitCode = 0)
    $recorder = New-SwiftTestEvidenceRecorder
    Add-STEFixtureTrace $recorder $Lines
    return Complete-SwiftTestEvidenceRecorder $recorder $ExitCode
}

function Assert-STEFixtureIncomplete {
    param($Result, [string]$Problem)
    Assert-STEFixture (-not $Result.complete -and $Result.problems -ccontains $Problem) 'incomplete-problem'
}

function New-STEFixtureRelative {
    $script:steFixtureEvidenceIndex++
    return ('artifacts/evidence-{0:d4}' -f $script:steFixtureEvidenceIndex)
}

function New-STEFixtureSession {
    param([int]$Count = 1, [int]$StartShard = 1)
    $shards = @(for ($i = 0; $i -lt $Count; $i++) {
        [pscustomobject]@{ Targets = @([pscustomobject]@{ Name = 'FixtureTests' }); Filter = 'FixtureTests' }
    })
    return New-SwiftTestEvidenceSession $script:steFixtureWorkspace (New-STEFixtureRelative) $shards $StartShard
}

function Save-STEFixturePassingShard {
    param($Session, [int]$Index, [string]$Id = 'FixtureTests.testOne')
    $recorder = Start-SwiftTestEvidenceShard $Session $Index
    Add-STEFixtureTrace $recorder @(New-STEFixtureTrace -Ids @($Id))
    $emitted = @(Save-SwiftTestEvidenceShard $Session $recorder 0)
    if ($emitted.Count -ne 0) { throw 'fixture-observer-output' }
}

function Read-STEFixtureSummary {
    param($Session)
    return Read-SwiftTestEvidenceJson (Join-Path $Session.Directory 'summary.json') 65536
}

function Assert-STEFixtureEarlyLocalPathGuard {
    # Nonlocal negative inputs must never become filesystem/network probes if
    # the production resolver changes. Bind its exact pure parameter/prologue
    # before invoking the rejection branch; a changed prologue fails first.
    $command = Get-Command Resolve-SwiftTestEvidenceDirectory -CommandType Function -ErrorAction Stop
    $ast = $command.ScriptBlock.Ast
    if ($ast -is [Management.Automation.Language.FunctionDefinitionAst]) {
        if ($ast.Name -cne 'Resolve-SwiftTestEvidenceDirectory' -or $ast.IsFilter -or $ast.IsWorkflow -or
            ($null -ne $ast.Parameters -and $ast.Parameters.Count -ne 0)) {
            throw 'fixture-local-path-guard-changed'
        }
        $ast = $ast.Body
    }
    if ($ast -isnot [Management.Automation.Language.ScriptBlockAst] -or
        $null -eq $ast.ParamBlock -or $null -eq $ast.EndBlock) {
        throw 'fixture-local-path-guard-changed'
    }
    $attributeCount = 0
    if ($null -ne $ast.Attributes) { $attributeCount = $ast.Attributes.Count }
    $trapCount = 0
    if ($null -ne $ast.EndBlock.Traps) { $trapCount = $ast.EndBlock.Traps.Count }
    $cleanProperty = $ast.PSObject.Properties['CleanBlock']
    if ($null -ne $ast.BeginBlock -or $null -ne $ast.ProcessBlock -or
        $null -ne $ast.DynamicParamBlock -or
        ($null -ne $cleanProperty -and $null -ne $cleanProperty.Value) -or
        $attributeCount -ne 0 -or $trapCount -ne 0) {
        throw 'fixture-local-path-guard-changed'
    }
    $expectedParam = 'param([string]$WorkspaceRoot, [string]$Path)'
    $expectedFirst = @'
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot) -or [string]::IsNullOrWhiteSpace($Path) -or
        $WorkspaceRoot.Length -gt 1024 -or $Path.Length -gt 1024) { throw 'test-evidence-path-invalid' }
'@
    $expectedSecond = @'
if ($WorkspaceRoot -cnotmatch '\A[A-Za-z]:[\\/]' -or
        $Path -cmatch '\A[\\/]{2}') { throw 'test-evidence-path-invalid' }
'@
    if ($ast.EndBlock.Statements.Count -lt 3 -or
        $ast.EndBlock.Statements[0] -isnot [Management.Automation.Language.IfStatementAst] -or
        $ast.EndBlock.Statements[1] -isnot [Management.Automation.Language.IfStatementAst]) {
        throw 'fixture-local-path-guard-changed'
    }
    $actual = @($ast.ParamBlock.Extent.Text, $ast.EndBlock.Statements[0].Extent.Text, $ast.EndBlock.Statements[1].Extent.Text)
    $expected = @($expectedParam, $expectedFirst, $expectedSecond)
    $crlf = ([string][char]13) + [char]10
    $lf = [string][char]10
    for ($i = 0; $i -lt 3; $i++) {
        if ($actual[$i].Replace($crlf, $lf) -cne $expected[$i].Replace($crlf, $lf)) {
            throw 'fixture-local-path-guard-changed'
        }
    }
}

function Invoke-STEFixtureBoundary {
    param(
        [switch]$Evidence,
        [AllowNull()]$WrapperExit = 0,
        [AllowNull()][object[]]$Objects = @(),
        [ValidateSet('none', 'observer', 'writer', 'start')][string]$Fault = 'none',
        [string[]]$Filters = @('FixtureTests')
    )
    # This is a function-scope mock of the actual extracted invocation boundary.
    # The real powershell executable and whole test script are never invoked.
    $steBoundaryState = [pscustomobject]@{
        ExitCode = $WrapperExit; Objects = $Objects
        Invocations = [Collections.Generic.List[object]]::new()
        Forwarded = [Collections.Generic.List[object]]::new()
    }
    function powershell {
        [void]$steBoundaryState.Invocations.Add([object]@($args))
        foreach ($value in $steBoundaryState.Objects) {
            & {
                [CmdletBinding()]
                param()
                $PSCmdlet.WriteObject($value, $false)
            }
        }
        $global:LASTEXITCODE = $steBoundaryState.ExitCode
    }
    function Out-Host {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline = $true)][AllowNull()][object]$InputObject)
        process { [void]$steBoundaryState.Forwarded.Add($InputObject) }
    }
    $mockPowerShell = (Get-Command powershell -CommandType Function -ErrorAction Stop).ScriptBlock
    $mockOutHost = (Get-Command Out-Host -CommandType Function -ErrorAction Stop).ScriptBlock
    $resolvedPowerShell = Get-Command powershell -ErrorAction Stop
    $resolvedOutHost = Get-Command Out-Host -ErrorAction Stop
    if ($resolvedPowerShell.CommandType -ne [Management.Automation.CommandTypes]::Function -or
        $resolvedOutHost.CommandType -ne [Management.Automation.CommandTypes]::Function -or
        -not [object]::ReferenceEquals($resolvedPowerShell.ScriptBlock, $mockPowerShell) -or
        -not [object]::ReferenceEquals($resolvedOutHost.ScriptBlock, $mockOutHost)) {
        throw 'fixture-boundary-local-mocks-required'
    }
    if ($Fault -ceq 'observer') {
        function Add-SwiftTestEvidenceOutput {
            param($Recorder, $Value)
            throw 'fixture-synthetic-observer-failure'
        }
    } elseif ($Fault -ceq 'writer') {
        function Save-SwiftTestEvidenceShard {
            param($Session, $Recorder, $WrapperExitCode)
            throw 'fixture-synthetic-writer-failure'
        }
    } elseif ($Fault -ceq 'start') {
        function Start-SwiftTestEvidenceShard {
            param($Session, $Index)
            throw 'fixture-synthetic-start-failure'
        }
    }
    $savedExit = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $hadSavedExit = $null -ne $savedExit
    $savedExitValue = if ($hadSavedExit) { $savedExit.Value } else { $null }
    $savedSession = $script:swiftTestEvidenceSession
    try {
        $repoRoot = $script:steFixtureWorkspace
        $withSwift = Join-Path $script:steFixtureWorkspace 'scripts/with-swift.ps1'
        $session = if ($Evidence) { New-STEFixtureSession } else { $null }
        $script:swiftTestEvidenceSession = $session
        . $script:steFixtureExitDefinition
        . $script:steFixtureInvokeDefinition
        $returned = Invoke-SwiftTest -Filters $Filters -Label 'synthetic-boundary' -EvidenceIndex 1
        return [pscustomobject]@{
            ReturnCode = $returned; ReportedExitCode = $global:LASTEXITCODE
            Invocations = @($steBoundaryState.Invocations.ToArray())
            Forwarded = @($steBoundaryState.Forwarded.ToArray())
            Session = $session
        }
    } finally {
        $script:swiftTestEvidenceSession = $savedSession
        if ($hadSavedExit) { $global:LASTEXITCODE = $savedExitValue }
        else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
    }
}

function Get-STEFixtureForwardingAdmission {
    param($InvocationDefinition)
    # Pure AST admission only: return nodes from this same parsed tree without
    # creating, registering or invoking a scriptblock from the supplied source.
    if ($InvocationDefinition -isnot [Management.Automation.Language.FunctionDefinitionAst] -or
        $InvocationDefinition.Name -cne 'Invoke-SwiftTest' -or $InvocationDefinition.IsFilter -or
        $InvocationDefinition.IsWorkflow -or
        ($null -ne $InvocationDefinition.Parameters -and $InvocationDefinition.Parameters.Count -ne 0)) {
        throw 'fixture-test-forwarding-container-changed'
    }
    $forwardCommands = @($InvocationDefinition.Body.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'ForEach-Object'
    }, $true))
    if ($forwardCommands.Count -ne 1 -or $forwardCommands[0].CommandElements.Count -ne 2 -or
        $forwardCommands[0].CommandElements[1] -isnot [Management.Automation.Language.ScriptBlockExpressionAst]) {
        throw 'fixture-test-forwarding-seam-changed'
    }
    $forwardAst = $forwardCommands[0].CommandElements[1].ScriptBlock
    $forwardAttributeCount = 0
    if ($null -ne $forwardAst.Attributes) { $forwardAttributeCount = $forwardAst.Attributes.Count }
    $forwardTrapCount = 0
    if ($null -ne $forwardAst.EndBlock -and $null -ne $forwardAst.EndBlock.Traps) {
        $forwardTrapCount = $forwardAst.EndBlock.Traps.Count
    }
    $forwardCleanProperty = $forwardAst.PSObject.Properties['CleanBlock']
    if ($null -ne $forwardAst.ParamBlock -or $null -ne $forwardAst.BeginBlock -or
        $null -ne $forwardAst.ProcessBlock -or $null -ne $forwardAst.DynamicParamBlock -or
        $null -eq $forwardAst.EndBlock -or $forwardAttributeCount -ne 0 -or $forwardTrapCount -ne 0 -or
        ($null -ne $forwardCleanProperty -and $null -ne $forwardCleanProperty.Value)) {
        throw 'fixture-test-forwarding-block-changed'
    }
    $unnamedWriters = @($forwardAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and $null -eq $node.GetCommandName()
    }, $true))
    if ($unnamedWriters.Count -ne 1 -or
        $unnamedWriters[0].InvocationOperator -ne [Management.Automation.Language.TokenKind]::Ampersand -or
        $unnamedWriters[0].CommandElements.Count -ne 1 -or
        $unnamedWriters[0].CommandElements[0] -isnot [Management.Automation.Language.ScriptBlockExpressionAst]) {
        throw 'fixture-test-local-writer-changed'
    }
    $expectedWriter = @'
& {
                [CmdletBinding()]
                param()
                $PSCmdlet.WriteObject($swiftTestOriginalOutput, $false)
            }
'@
    if ($unnamedWriters[0].Extent.Text -cne $expectedWriter) {
        throw 'fixture-test-local-writer-changed'
    }
    return [pscustomobject]@{
        ForwardingAst = $forwardAst
        AllowedUnnamedWriter = $unnamedWriters[0]
    }
}

function Invoke-STEFixtureGuardRegression {
    param([switch]$ChangedInitialGuard)
    # This local resolver-shaped definition has only pure guards and an inert
    # tail marker. It is registered for inspection and is never invoked here.
    $steGuardRegressionState = [pscustomobject]@{ TailReached = $false }
    $definitionText = @'
function Resolve-SwiftTestEvidenceDirectory {
    param([string]$WorkspaceRoot, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($WorkspaceRoot) -or [string]::IsNullOrWhiteSpace($Path) -or
        $WorkspaceRoot.Length -gt 1024 -or $Path.Length -gt 1024) { throw 'test-evidence-path-invalid' }
    if ($WorkspaceRoot -cnotmatch '\A[A-Za-z]:[\\/]' -or
        $Path -cmatch '\A[\\/]{2}') { throw 'test-evidence-path-invalid' }
    $steGuardRegressionState.TailReached = $true
}
'@
    if ($ChangedInitialGuard) {
        $definitionText = $definitionText.Replace('$WorkspaceRoot.Length -gt 1024', '$WorkspaceRoot.Length -gt 1023')
    }
    $authoredDefinition = [scriptblock]::Create($definitionText)
    $authoredFunctions = @($authoredDefinition.Ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq 'Resolve-SwiftTestEvidenceDirectory'
    }, $true))
    if ($authoredFunctions.Count -ne 1) { throw 'fixture-guard-authored-definition-count' }
    . $authoredDefinition
    $registeredAst = (Get-Command Resolve-SwiftTestEvidenceDirectory -CommandType Function -ErrorAction Stop).ScriptBlock.Ast
    $expectedText = $authoredFunctions[0].Extent.Text
    if ($registeredAst -is [Management.Automation.Language.ScriptBlockAst]) {
        $expectedText = $authoredFunctions[0].Body.Extent.Text
    } elseif ($registeredAst -isnot [Management.Automation.Language.FunctionDefinitionAst]) {
        throw 'fixture-guard-local-definition-required'
    }
    if ($registeredAst.Extent.Text -cne $expectedText) { throw 'fixture-guard-local-definition-required' }
    $accepted = $false
    $rejectedChangedGuard = $false
    try { Assert-STEFixtureEarlyLocalPathGuard; $accepted = $true }
    catch { $rejectedChangedGuard = $_.Exception.Message -ceq 'fixture-local-path-guard-changed' }
    return [pscustomobject]@{
        Accepted = $accepted; RejectedChangedGuard = $rejectedChangedGuard
        TailReached = $steGuardRegressionState.TailReached
    }
}

function Invoke-STEFixtureTransport {
    param(
        [AllowNull()]$Payload,
        [ValidateSet('current-mock', 'direct', 'direct-tee', 'direct-tee-observer-throws')][string]$RouteId
    )
    # Use the actual local mock/collector definitions and the exact corrected
    # production forwarding block. No whole wrapper or external command runs.
    $steTransportPayload = $Payload
    $objects = [object[]]::new(1)
    $objects[0] = $steTransportPayload
    $steBoundaryState = [pscustomobject]@{
        ExitCode = 0; Objects = $objects
        Invocations = [Collections.Generic.List[object]]::new()
        Forwarded = [Collections.Generic.List[object]]::new()
    }
    $steTransportState = [pscustomobject]@{
        Observed = [Collections.Generic.List[object]]::new()
        ProblemCodes = [Collections.Generic.List[string]]::new()
        ThrowObserver = ($RouteId -ceq 'direct-tee-observer-throws')
    }
    $swiftTestRecorder = [object]::new()
    . $script:steFixtureMockDefinition
    . $script:steFixtureCollectorDefinition
    $mockPowerShell = (Get-Command powershell -CommandType Function -ErrorAction Stop).ScriptBlock
    $mockOutHost = (Get-Command Out-Host -CommandType Function -ErrorAction Stop).ScriptBlock
    $resolvedPowerShell = Get-Command powershell -ErrorAction Stop
    $resolvedOutHost = Get-Command Out-Host -ErrorAction Stop
    if ($resolvedPowerShell.CommandType -ne [Management.Automation.CommandTypes]::Function -or
        $resolvedOutHost.CommandType -ne [Management.Automation.CommandTypes]::Function -or
        -not [object]::ReferenceEquals($resolvedPowerShell.ScriptBlock, $mockPowerShell) -or
        -not [object]::ReferenceEquals($resolvedOutHost.ScriptBlock, $mockOutHost)) {
        throw 'fixture-transport-local-mocks-required'
    }
    function Emit-STEFixtureDirect {
        [CmdletBinding()]
        param()
        $PSCmdlet.WriteObject($steTransportPayload, $false)
    }
    function Add-SwiftTestEvidenceOutput {
        param($Recorder, $Value)
        [void]$steTransportState.Observed.Add($Value)
        if ($steTransportState.ThrowObserver) { throw 'fixture-transport-observer-error' }
    }
    function Add-SwiftTestEvidenceProblem {
        param($Recorder, [string]$Code)
        if ($Code -cne 'observer-call-failed') { throw 'fixture-transport-unexpected-problem' }
        [void]$steTransportState.ProblemCodes.Add($Code)
    }
    $savedExit = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $hadSavedExit = $null -ne $savedExit
    $savedExitValue = if ($hadSavedExit) { $savedExit.Value } else { $null }
    try {
        switch -CaseSensitive ($RouteId) {
            'current-mock' { & powershell | Out-Host }
            'direct' { Emit-STEFixtureDirect | Out-Host }
            'direct-tee' { Emit-STEFixtureDirect | ForEach-Object -Process $script:steFixtureForwardDefinition | Out-Host }
            'direct-tee-observer-throws' { Emit-STEFixtureDirect | ForEach-Object -Process $script:steFixtureForwardDefinition | Out-Host }
            default { throw 'fixture-transport-route-invalid' }
        }
    } finally {
        if ($hadSavedExit) { $global:LASTEXITCODE = $savedExitValue }
        else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
    }
    # Return the lists themselves as properties, without enumerating or
    # normalizing any of the collected objects before the identity assertions.
    return [pscustomobject]@{
        MockInvocationCount = $steBoundaryState.Invocations.Count
        Forwarded = $steBoundaryState.Forwarded
        Observed = $steTransportState.Observed
        ProblemCodes = $steTransportState.ProblemCodes
    }
}

function Get-STEFixtureRequestFailure {
    param([scriptblock]$FailureOperation)
    $requestFailure = [pscustomobject]@{ Failed = $false; Code = $null }
    try { $null = & $FailureOperation }
    catch {
        $requestFailure.Failed = $true
        $requestFailure.Code = if ($_.Exception.Message -cmatch '\Atest-evidence-[a-z-]+\z') {
            $_.Exception.Message
        } else { 'fixture-request-unexpected-error' }
    }
    return $requestFailure
}

function Read-STEFixtureOwnedBytes {
    param([string]$OwnedPath, [int]$MaximumBytes = 1048576)
    $fullOwnedPath = [IO.Path]::GetFullPath($OwnedPath)
    $ownedPrefix = $script:steFixtureRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $fullOwnedPath.StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'fixture-owned-read-scope' }
    $ownedAttributes = [IO.File]::GetAttributes($fullOwnedPath)
    if (($ownedAttributes -band ([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)) -ne 0) { throw 'fixture-owned-read-type' }
    $ownedStream = [IO.File]::Open($fullOwnedPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $ownedLength = $ownedStream.Length
        if ($ownedLength -lt 0 -or $ownedLength -gt $MaximumBytes) { throw 'fixture-owned-read-limit' }
        $ownedBytes = [byte[]]::new([int]$ownedLength)
        $ownedOffset = 0
        while ($ownedOffset -lt $ownedBytes.Length) {
            $ownedRead = $ownedStream.Read($ownedBytes, $ownedOffset, $ownedBytes.Length - $ownedOffset)
            if ($ownedRead -le 0) { throw 'fixture-owned-read-short' }
            $ownedOffset += $ownedRead
        }
        if ($ownedStream.ReadByte() -ne -1) { throw 'fixture-owned-read-growth' }
    } finally { $ownedStream.Dispose() }
    return ,$ownedBytes
}

function Get-STEFixtureOwnedInventory {
    param([string]$OwnedDirectory, [switch]$OmitPublished)
    $inventoryRoot = [IO.Path]::GetFullPath($OwnedDirectory).TrimEnd('\', '/')
    $fixturePrefix = $script:steFixtureRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $inventoryRoot.StartsWith($fixturePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'fixture-inventory-scope' }
    $inventoryFiles = [Collections.Generic.List[object]]::new()
    $inventoryDirectories = [Collections.Generic.List[string]]::new()
    if (-not [IO.Directory]::Exists($inventoryRoot)) {
        return [pscustomobject]@{ Exists = $false; Files = @(); Directories = @() }
    }
    $inventoryPending = [Collections.Generic.Stack[string]]::new()
    $inventoryPending.Push($inventoryRoot)
    while ($inventoryPending.Count -gt 0) {
        $inventoryDirectory = $inventoryPending.Pop()
        $inventoryAttributes = [IO.File]::GetAttributes($inventoryDirectory)
        if (($inventoryAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ($inventoryAttributes -band [IO.FileAttributes]::Directory) -eq 0) { throw 'fixture-inventory-directory-type' }
        $inventoryEnumerator = [IO.Directory]::EnumerateFileSystemEntries($inventoryDirectory).GetEnumerator()
        try {
            while ($inventoryEnumerator.MoveNext()) {
                $inventoryPath = [string]$inventoryEnumerator.Current
                $inventoryRelative = $inventoryPath.Substring($inventoryRoot.Length + 1).Replace('\', '/')
                if ($OmitPublished -and ($inventoryRelative -ceq 'published' -or $inventoryRelative.StartsWith('published/', [StringComparison]::Ordinal))) { continue }
                $entryAttributes = [IO.File]::GetAttributes($inventoryPath)
                if (($entryAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'fixture-inventory-reparse' }
                if (($entryAttributes -band [IO.FileAttributes]::Directory) -ne 0) {
                    if ($inventoryDirectories.Count -ge 16) { throw 'fixture-inventory-directory-limit' }
                    [void]$inventoryDirectories.Add($inventoryRelative)
                    $inventoryPending.Push($inventoryPath)
                } else {
                    if ($inventoryFiles.Count -ge 32) { throw 'fixture-inventory-file-limit' }
                    $inventoryBytes = Read-STEFixtureOwnedBytes $inventoryPath
                    [void]$inventoryFiles.Add([pscustomobject][ordered]@{
                        path = $inventoryRelative; bytes = $inventoryBytes.Length; sha256 = Get-STEFixtureHash $inventoryBytes
                    })
                }
            }
        } finally { $inventoryEnumerator.Dispose() }
    }
    return [pscustomobject][ordered]@{
        Exists = $true
        Files = @($inventoryFiles.ToArray() | Sort-Object path)
        Directories = @($inventoryDirectories.ToArray() | Sort-Object)
    }
}

function New-STEFixtureRequestSession {
    param([AllowNull()]$RequestId, [int]$Count = 1, [string]$RequestDirectory = '', [string]$MetadataMarker = '')
    $requestShards = @(for ($requestIndex = 0; $requestIndex -lt $Count; $requestIndex++) {
        [pscustomobject]@{ Targets = @([pscustomobject]@{ Name = 'FixtureTests' }); Filter = 'FixtureTests' }
    })
    if ($RequestDirectory.Length -eq 0) { $RequestDirectory = New-STEFixtureRelative }
    if ($MetadataMarker.Length -gt 0) {
        $steRequestSessionMetadata = Get-SwiftTestEvidenceMetadata $script:steFixtureWorkspace
        $steRequestSessionMetadata.imageOS = $MetadataMarker
        function Get-SwiftTestEvidenceMetadata {
            param([string]$WorkspaceRoot)
            return $steRequestSessionMetadata
        }
    }
    return New-SwiftTestEvidenceSession -WorkspaceRoot $script:steFixtureWorkspace -Directory $RequestDirectory -Shards $requestShards -StartShard 1 -SessionId $RequestId
}

function Invoke-STEFixtureMarkedPublication {
    param($RequestSession, [AllowNull()]$ExpectedId, [switch]$OmitExpected)
    $steCurrentObserverMetadata = Get-SwiftTestEvidenceMetadata $script:steFixtureWorkspace
    $steCurrentObserverMetadata.imageOS = 'fixture_current_observer'
    function Get-SwiftTestEvidenceMetadata {
        param([string]$WorkspaceRoot)
        return $steCurrentObserverMetadata
    }
    if ($OmitExpected) {
        return Publish-SwiftTestEvidenceCI -WorkspaceRoot $script:steFixtureWorkspace -Directory $RequestSession.Directory -FullOutcome 'failure' -RequireCurrentInvocation
    }
    return Publish-SwiftTestEvidenceCI -WorkspaceRoot $script:steFixtureWorkspace -Directory $RequestSession.Directory -FullOutcome 'failure' -ExpectedSessionId $ExpectedId -RequireCurrentInvocation
}

function Invoke-STEFixtureRequestBoundary {
    param([AllowNull()]$RequestSession, [AllowNull()]$WrapperExit = 0, [object[]]$Objects = @())
    # Reuse the already admitted production invocation and original local mocks.
    # This does not run agent-check, test.ps1's body, or a real native process.
    $steBoundaryState = [pscustomobject]@{
        ExitCode = $WrapperExit; Objects = $Objects
        Invocations = [Collections.Generic.List[object]]::new()
        Forwarded = [Collections.Generic.List[object]]::new()
    }
    . $script:steFixtureMockDefinition
    . $script:steFixtureCollectorDefinition
    $requestMock = (Get-Command powershell -CommandType Function -ErrorAction Stop).ScriptBlock
    $requestCollector = (Get-Command Out-Host -CommandType Function -ErrorAction Stop).ScriptBlock
    $resolvedRequestMock = Get-Command powershell -ErrorAction Stop
    $resolvedRequestCollector = Get-Command Out-Host -ErrorAction Stop
    if ($resolvedRequestMock.CommandType -ne [Management.Automation.CommandTypes]::Function -or
        $resolvedRequestCollector.CommandType -ne [Management.Automation.CommandTypes]::Function -or
        -not [object]::ReferenceEquals($resolvedRequestMock.ScriptBlock, $requestMock) -or
        -not [object]::ReferenceEquals($resolvedRequestCollector.ScriptBlock, $requestCollector)) { throw 'fixture-request-local-mocks-required' }
    $requestSavedExit = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $requestHadSavedExit = $null -ne $requestSavedExit
    $requestSavedExitValue = if ($requestHadSavedExit) { $requestSavedExit.Value } else { $null }
    $requestSavedSession = $script:swiftTestEvidenceSession
    try {
        $repoRoot = $script:steFixtureWorkspace
        $withSwift = Join-Path $script:steFixtureWorkspace 'scripts/with-swift.ps1'
        $script:swiftTestEvidenceSession = $RequestSession
        . $script:steFixtureExitDefinition
        . $script:steFixtureInvokeDefinition
        $requestReturned = Invoke-SwiftTest -Filters @('FixtureTests') -Label 'synthetic-request-boundary' -EvidenceIndex 1
        return [pscustomobject]@{
            ReturnCode = $requestReturned; ReportedExitCode = $global:LASTEXITCODE
            Invocations = $steBoundaryState.Invocations
            Forwarded = $steBoundaryState.Forwarded
        }
    } finally {
        $script:swiftTestEvidenceSession = $requestSavedSession
        if ($requestHadSavedExit) { $global:LASTEXITCODE = $requestSavedExitValue }
        else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
    }
}

function Get-STEFixtureRequestArgv {
    return ,@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        (Join-Path $script:steFixtureWorkspace 'scripts/with-swift.ps1'),
        'swift', 'test', '--package-path', $script:steFixtureWorkspace, '--filter', 'FixtureTests')
}

function Test-STEFixtureRequestOutputIdentity {
    param($RequestBoundary, [object[]]$ExpectedObjects)
    if ($RequestBoundary.Forwarded.Count -ne $ExpectedObjects.Count) { return $false }
    for ($requestObjectIndex = 0; $requestObjectIndex -lt $ExpectedObjects.Count; $requestObjectIndex++) {
        if (-not [object]::ReferenceEquals($RequestBoundary.Forwarded[$requestObjectIndex], $ExpectedObjects[$requestObjectIndex]) -or
            $RequestBoundary.Forwarded[$requestObjectIndex].GetType() -ne $ExpectedObjects[$requestObjectIndex].GetType()) { return $false }
    }
    return $true
}

function New-STEFixtureRequestControl {
    param([byte[]]$Prefix = [byte[]]@())
    $script:steFixtureRequestControlIndex++
    $requestControlRoot = Join-Path $script:steFixtureRoot ('request-control-{0:d4}' -f $script:steFixtureRequestControlIndex)
    $requestControlPath = Join-Path $requestControlRoot 'output.txt'
    Write-STEFixtureBytes $requestControlPath $Prefix
    return [pscustomobject]@{ Root = $requestControlRoot; Path = $requestControlPath }
}

function Invoke-STEFixtureRequest {
    param(
        [bool]$GitHubActions = $false,
        [AllowNull()]$OutputPath = $null,
        [AllowNull()]$RunnerTemp = $null,
        [AllowNull()]$GeneratedId = ('2' * 32),
        [switch]$GenerationThrows,
        [switch]$VisibleLineThenThrow
    )
    $steRequestFixtureState = [pscustomobject]@{
        GeneratedId = $GeneratedId; GenerationThrows = $GenerationThrows.IsPresent
        GeneratorCalls = 0; InjectedLineWrites = 0
    }
    function New-SwiftTestEvidenceRequestId {
        $steRequestFixtureState.GeneratorCalls++
        if ($steRequestFixtureState.GenerationThrows) { throw 'fixture-injected-generation-failure' }
        return $steRequestFixtureState.GeneratedId
    }
    if ($VisibleLineThenThrow) {
        function Write-SwiftTestEvidenceRequestLine {
            param([IO.Stream]$Stream, [byte[]]$Bytes)
            $steRequestFixtureState.InjectedLineWrites++
            $Stream.Write($Bytes, 0, $Bytes.Length)
            $Stream.Flush()
            # Deliberately fail after a complete line is visible. This is an
            # injected failure boundary, not a claim that the real flush failed.
            throw 'fixture-injected-after-line-write'
        }
    }
    $requestValue = New-SwiftTestEvidenceRequest -GitHubActions $GitHubActions -GitHubOutputPath $OutputPath -RunnerTemp $RunnerTemp
    return [pscustomobject]@{
        Request = $requestValue
        GeneratorCalls = $steRequestFixtureState.GeneratorCalls
        InjectedLineWrites = $steRequestFixtureState.InjectedLineWrites
    }
}

function Invoke-STEFixtureRequestReparse {
    param([string]$OutputPath, [string]$RunnerTemp, [string]$ReparsePath, [string]$RequestId)
    $steRequestPathState = [pscustomobject]@{
        ReparsePath = [IO.Path]::GetFullPath($ReparsePath)
        AttributePaths = [Collections.Generic.List[string]]::new()
        Injected = $false
    }
    function Get-SwiftTestEvidenceRequestPathAttributes {
        param([string]$Path)
        [void]$steRequestPathState.AttributePaths.Add($Path)
        $requestPathAttributes = [IO.File]::GetAttributes($Path)
        if ([string]::Equals($Path, $steRequestPathState.ReparsePath, [StringComparison]::OrdinalIgnoreCase)) {
            $steRequestPathState.Injected = $true
            return ($requestPathAttributes -bor [IO.FileAttributes]::ReparsePoint)
        }
        return $requestPathAttributes
    }
    $requestPathFailure = Get-STEFixtureRequestFailure {
        Write-SwiftTestEvidenceRequestOutput -OutputPath $OutputPath -RunnerTemp $RunnerTemp -SessionId $RequestId
    }
    return [pscustomobject]@{
        Failure = $requestPathFailure
        Injected = $steRequestPathState.Injected
        AttributePaths = @($steRequestPathState.AttributePaths.ToArray())
    }
}

function Invoke-STEFixtureSingleBundle {
    param(
        [ValidateSet('check', 'publish')][string]$BundleOperation,
        [AllowNull()]$ExpectedId,
        $FirstBundle,
        $LaterBundle,
        [string]$BundleDirectory
    )
    $steSingleBundleState = [pscustomobject]@{
        First = $FirstBundle; Later = $LaterBundle; BundleReads = 0; DirectPlanReads = 0
    }
    function Read-SwiftTestEvidenceBundle {
        param($WorkspaceRoot, $Directory)
        $steSingleBundleState.BundleReads++
        if ($steSingleBundleState.BundleReads -eq 1) { return $steSingleBundleState.First }
        return $steSingleBundleState.Later
    }
    function Read-SwiftTestEvidencePlan {
        param($WorkspaceRoot, $Directory)
        $steSingleBundleState.DirectPlanReads++
        return $steSingleBundleState.First.Plan
    }
    $singleBundleResult = $null
    $singleBundleFailure = $null
    try {
        if ($BundleOperation -ceq 'check') {
            $singleBundleResult = Test-SwiftTestEvidenceCurrentInvocation -WorkspaceRoot $script:steFixtureWorkspace -Directory $BundleDirectory -ExpectedSessionId $ExpectedId
        } else {
            $singleBundleResult = Publish-SwiftTestEvidenceCI -WorkspaceRoot $script:steFixtureWorkspace -Directory $BundleDirectory -FullOutcome 'failure' -ExpectedSessionId $ExpectedId -RequireCurrentInvocation
        }
    } catch {
        $singleBundleFailure = if ($_.Exception.Message -cmatch '\Atest-evidence-[a-z-]+\z') {
            $_.Exception.Message
        } else { 'fixture-request-unexpected-error' }
    }
    return [pscustomobject]@{
        Value = $singleBundleResult; FailureCode = $singleBundleFailure
        BundleReads = $steSingleBundleState.BundleReads; DirectPlanReads = $steSingleBundleState.DirectPlanReads
    }
}

function Test-STEFixtureRequestAssociation {
    param($Association, [AllowNull()]$ExpectedId, [AllowNull()]$JournalId, [string]$IdentityStatus)
    if ($Association -isnot [pscustomobject] -or
        ($null -ne $ExpectedId -and $ExpectedId -isnot [string]) -or
        ($null -ne $JournalId -and $JournalId -isnot [string])) { return $false }
    $associationKeys = @($Association.PSObject.Properties.Name)
    $expectedKeys = @('expectedSessionId', 'journalSessionId', 'identityStatus', 'generation', 'transport', 'qualification')
    if ($associationKeys.Count -ne $expectedKeys.Count) { return $false }
    foreach ($associationKey in $associationKeys) {
        if ($expectedKeys -cnotcontains $associationKey) { return $false }
    }
    foreach ($identifierName in @('expectedSessionId', 'journalSessionId')) {
        $wantedId = if ($identifierName -ceq 'expectedSessionId') { $ExpectedId } else { $JournalId }
        $actualId = $Association.$identifierName
        if ($null -eq $wantedId) {
            if ($null -ne $actualId) { return $false }
        } elseif ($actualId -isnot [string] -or
            -not [string]::Equals($actualId, $wantedId, [StringComparison]::Ordinal)) { return $false }
    }
    $associationLiterals = [ordered]@{
        identityStatus = $IdentityStatus
        generation = 'not-independently-observed'
        transport = 'not-independently-observed'
        qualification = 'caller-supplied-id-match-only; not-authenticated-freshness'
    }
    foreach ($literalName in $associationLiterals.Keys) {
        $actualLiteral = $Association.$literalName
        if ($actualLiteral -isnot [string] -or
            -not [string]::Equals($actualLiteral, $associationLiterals[$literalName], [StringComparison]::Ordinal)) { return $false }
    }
    return $true
}

function Test-STEFixtureWithheldPublication {
    param($Publication, [string]$PublicationDirectory)
    if ($null -eq $Publication -or $null -eq $Publication.cases -or
        ($Publication.cases.bytes -isnot [int] -and $Publication.cases.bytes -isnot [long])) { return $false }
    $withheldCases = Read-STEFixtureOwnedBytes (Join-Path $PublicationDirectory 'published/cases.ndjson')
    return $null -eq $Publication.observed -and $null -eq $Publication.testSummary -and
        $Publication.shards -is [array] -and $Publication.shards.Count -eq 0 -and
        $Publication.startedWithoutResult -is [array] -and $Publication.startedWithoutResult.Count -eq 0 -and
        $Publication.cases.bytes -eq 0 -and $withheldCases.Length -eq 0
}

function Invoke-STEFixturePublicationWriteFailure {
    param($RequestSession, [string]$ExpectedId)
    $steOriginalPublicationWriter = (Get-Command Write-SwiftTestEvidenceJsonNew -CommandType Function -ErrorAction Stop).ScriptBlock
    function Write-SwiftTestEvidenceJsonNew {
        param([string]$Path, $Value, [long]$MaxBytes = 1048576)
        if ([IO.Path]::GetFileName($Path) -ceq 'manifest.json') { throw 'test-evidence-fixture-manifest-write-failed' }
        & $steOriginalPublicationWriter $Path $Value $MaxBytes
    }
    return Get-STEFixtureRequestFailure {
        Publish-SwiftTestEvidenceCI -WorkspaceRoot $script:steFixtureWorkspace -Directory $RequestSession.Directory -FullOutcome 'failure' -ExpectedSessionId $ExpectedId -RequireCurrentInvocation
    }
}
function Get-STEFixtureRequestSourceWiring {
    param($AgentAst, $TestAst, [string]$HelperSource, [string]$WorkflowSource)
    # Metadata-only admission of the actual production control flow. These
    # hashes bind raw AST extents; no source is normalized, registered or run.
    # Nonzero/unavailable "Check not reached" checks below are source/control-
    # flow checks, not a simulated Full runner or a runtime reach counter.
    $fullNodes = @($AgentAst.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Clauses.Count -eq 1 -and
            $_.Clauses[0].Item1.Extent.Text -ceq '$Full'
    })
    if ($fullNodes.Count -ne 1 -or $null -eq $fullNodes[0].ElseClause) { throw 'fixture-request-full-source-shape' }
    $fullStatements = $fullNodes[0].Clauses[0].Item2.Statements
    if ($fullStatements.Count -lt 7 -or
        $fullStatements[0] -isnot [Management.Automation.Language.AssignmentStatementAst] -or
        $fullStatements[1] -isnot [Management.Automation.Language.AssignmentStatementAst] -or
        $fullStatements[2] -isnot [Management.Automation.Language.AssignmentStatementAst] -or
        $fullStatements[3] -isnot [Management.Automation.Language.IfStatementAst] -or
        $fullStatements[4] -isnot [Management.Automation.Language.PipelineAst] -or
        $fullStatements[5] -isnot [Management.Automation.Language.IfStatementAst]) { throw 'fixture-request-full-order-shape' }
    $agentText = $AgentAst.Extent.Text
    $fullPrefix = $agentText.Substring($fullStatements[0].Extent.StartOffset,
        $fullStatements[5].Extent.EndOffset - $fullStatements[0].Extent.StartOffset)
    $stepFunctions = @($AgentAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-Step'
    }, $true))
    if ($stepFunctions.Count -ne 1) { throw 'fixture-request-step-function-count' }
    if ((Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($fullPrefix)) -cne 'd2fae2225fb8066c37b70318812d3b326ae0f4059412744648e829b9a02b6a06' -or
        (Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($stepFunctions[0].Extent.Text)) -cne '1ce077e5a0ebb4336e625201bae5be819d7579d8156aac03e20ac056a8403d79' -or
        (Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($fullNodes[0].ElseClause.Extent.Text)) -cne '69a29b47cce6ee4a021999eaa6ca7035df084a8d5143df10e1dd3051f84c7e7a') {
        throw 'fixture-request-full-order-source-changed'
    }
    $requestCalls = @($AgentAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'New-SwiftTestEvidenceRequest'
    }, $true))
    $fullTestCalls = @($fullStatements[4].FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Invoke-Step' -and
            $node.CommandElements.Count -eq 3 -and $node.CommandElements[1].Extent.Text -ceq '"swift test (sharded full suite)"'
    }, $true))
    $fullCheckCalls = @($fullStatements[5].FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Invoke-Step' -and
            $node.CommandElements.Count -eq 3 -and $node.CommandElements[1].Extent.Text -ceq '"CoreLogic XCTest evidence completeness"'
    }, $true))
    if ($requestCalls.Count -ne 1 -or $fullTestCalls.Count -ne 1 -or $fullCheckCalls.Count -ne 1 -or
        $requestCalls[0].Extent.StartOffset -lt $fullStatements[3].Extent.StartOffset -or
        $requestCalls[0].Extent.EndOffset -gt $fullStatements[3].Extent.EndOffset -or
        $requestCalls[0].Extent.StartOffset -ge $fullTestCalls[0].Extent.StartOffset -or
        $fullTestCalls[0].Extent.StartOffset -ge $fullCheckCalls[0].Extent.StartOffset) { throw 'fixture-request-order-not-bound' }

    $boundFlags = @($TestAst.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.AssignmentStatementAst] -and
            $_.Left.Extent.Text -ceq '$evidenceSessionIdWasSupplied'
    })
    $wrapperSetups = @($TestAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses.Count -eq 1 -and
            $node.Clauses[0].Item1.Extent.Text -ceq '-not [string]::IsNullOrWhiteSpace($EvidenceDirectory)'
    }, $true))
    $wrapperInvocations = @($TestAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-SwiftTest'
    }, $true))
    $wrapperParameters = @($TestAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -ceq 'EvidenceSessionId' })
    if ($boundFlags.Count -ne 1 -or $wrapperSetups.Count -ne 1 -or $wrapperInvocations.Count -ne 1 -or $wrapperParameters.Count -ne 1) {
        throw 'fixture-request-wrapper-source-shape'
    }
    if ((Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($boundFlags[0].Extent.Text)) -cne 'b000381d9a91d338797de57850a33df62a23af58748b07c054580ecd6d5cc4b5' -or
        (Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($wrapperSetups[0].Extent.Text)) -cne 'c5b08f4c4523470158b734f0f6b1d2bb59ac30379fd58d19744d0171225fb0c6' -or
        (Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($wrapperInvocations[0].Extent.Text)) -cne 'cf29f1cd2d3e0d0baf0956acf96cfee993abfd62e88c4043dd14464ef902c887' -or
        (Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($wrapperParameters[0].Extent.Text)) -cne '24997895dd4bd7bc6cfa8f1535941966036ddf90dd33739471ebd43ca0e5984a') {
        throw 'fixture-request-wrapper-source-changed'
    }

    $helperTokens = $null; $helperErrors = $null
    $helperAst = [Management.Automation.Language.Parser]::ParseInput($HelperSource, [ref]$helperTokens, [ref]$helperErrors)
    if (@($helperErrors).Count -ne 0) { throw 'fixture-request-helper-source-parse' }
    $helperCli = @($helperAst.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Clauses.Count -eq 1 -and
            $_.Clauses[0].Item1.Extent.Text -ceq '$MyInvocation.InvocationName -ne ''.'''
    })
    $currentChecks = @($helperAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Test-SwiftTestEvidenceCurrentInvocation'
    }, $true))
    $sessionFunctions = @($helperAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'New-SwiftTestEvidenceSession'
    }, $true))
    if ($helperCli.Count -ne 1 -or $currentChecks.Count -ne 1 -or $sessionFunctions.Count -ne 1) { throw 'fixture-request-helper-seam-count' }
    $sessionParameters = @($sessionFunctions[0].Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -ceq 'SessionId' })
    if ($sessionParameters.Count -ne 1 -or
        (Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($helperCli[0].Extent.Text)) -cne '644a442a15ec33ea5efeb0c73b9c02aa4fd6dabf1fb9324a76391bd2984e892c' -or
        (Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($currentChecks[0].Extent.Text)) -cne '43f017c250d6c3efbd6ae06d775618d07b0507cb6c0f9586131a58fdb35e86e6' -or
        (Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($sessionParameters[0].Extent.Text)) -cne 'a4059560b66c4f3417805330c98b0bf7059c94acba6287383b414953757980b6') {
        throw 'fixture-request-bound-cli-source-changed'
    }

    $fullMarker = '      - name: Run full agent checks'
    $publishMarker = '      - name: Publish sanitized CoreLogic test evidence'
    $uploadMarker = '      - name: Upload sanitized CoreLogic test evidence'
    $nextMarker = '      - name: Upload screenshot artifacts'
    $workflowOffsets = @()
    foreach ($workflowMarker in @($fullMarker, $publishMarker, $uploadMarker, $nextMarker)) {
        $workflowOffset = $WorkflowSource.IndexOf($workflowMarker, [StringComparison]::Ordinal)
        if ($workflowOffset -lt 0 -or $WorkflowSource.IndexOf($workflowMarker, $workflowOffset + 1, [StringComparison]::Ordinal) -ge 0) {
            throw 'fixture-request-workflow-step-count'
        }
        $workflowOffsets += $workflowOffset
    }
    if ($workflowOffsets[0] -ge $workflowOffsets[1] -or $workflowOffsets[1] -ge $workflowOffsets[2] -or
        $workflowOffsets[2] -ge $workflowOffsets[3]) { throw 'fixture-request-workflow-step-order' }
    $workflowFull = $WorkflowSource.Substring($workflowOffsets[0], $workflowOffsets[1] - $workflowOffsets[0])
    $workflowPublish = $WorkflowSource.Substring($workflowOffsets[1], $workflowOffsets[2] - $workflowOffsets[1])
    $workflowUpload = $WorkflowSource.Substring($workflowOffsets[2], $workflowOffsets[3] - $workflowOffsets[2])
    if ((Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($workflowFull)) -cne '70c21de4fc3e497a92ed6d902c641249b3422974fd02e52f48903800b78c4480' -or
        (Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($workflowPublish)) -cne '638caece1459491f1efeb63391e32b881f6edf7d9d4e447aa200253f0343cd9d' -or
        (Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($workflowUpload)) -cne '727677a24e00e03fd9f2de6cf112f530e7fa086b88b8c10a442ea2962855490b') {
        throw 'fixture-request-workflow-source-changed'
    }
    $uploadConditions = [regex]::Matches($workflowUpload, '(?m)^        if: (?<condition>[^\r\n]+)')
    if ($uploadConditions.Count -ne 1 -or
        $uploadConditions[0].Groups['condition'].Value -cne "always() && steps.publish_corelogic_evidence.outcome == 'success'") {
        throw 'fixture-request-upload-condition-changed'
    }
    return [pscustomobject]@{
        Kind = 'source-ast-contract-only'
        RequestOnlyInEnabledFull = $true
        RequestBeforeOriginalTests = $true
        OriginalNonzeroStopsBeforeCheck = $true
        OriginalUnavailableExitStopsBeforeCheck = $true
        CheckRequiresReadyCallerExpectation = $true
        WrapperPassesOnlyOriginallySuppliedSessionId = $true
        QuickSelectionUnchanged = $true
        CliCheckAndPublishAlwaysBound = $true
        PublisherAlwaysAndUploadOnlyOnSuccess = $true
        UploadCondition = $uploadConditions[0].Groups['condition'].Value
    }
}

function Test-STEFixtureUploadEligibility {
    param([ValidateSet('success', 'failure', 'cancelled', 'skipped')][string]$PublisherOutcome)
    $uploadCondition = $script:steFixtureRequestWiring.UploadCondition
    if ($uploadCondition -cne "always() && steps.publish_corelogic_evidence.outcome == 'success'") {
        throw 'fixture-request-upload-expression-not-admitted'
    }
    # Evaluate only this exact admitted boolean expression, not a workflow or
    # publisher script. This is not an observation of GitHub scheduling.
    $uploadExpression = $uploadCondition.Replace('always()', '$true').Replace(
        'steps.publish_corelogic_evidence.outcome', '$PublisherOutcome').Replace(' && ', ' -and ').Replace(' == ', ' -ceq ')
    return [bool](& ([scriptblock]::Create($uploadExpression)))
}

# Bare process/compiler/network entry points are forbidden in this synthetic
# suite. The helper is also reviewed statically; these are not a sandbox.
function Add-Type { $script:steFixtureForbiddenCalls++; throw 'fixture-forbidden-operation' }
function Start-Process { $script:steFixtureForbiddenCalls++; throw 'fixture-forbidden-operation' }
function Invoke-WebRequest { $script:steFixtureForbiddenCalls++; throw 'fixture-forbidden-operation' }
function Invoke-RestMethod { $script:steFixtureForbiddenCalls++; throw 'fixture-forbidden-operation' }
function swift { $script:steFixtureForbiddenCalls++; throw 'fixture-forbidden-operation' }
function git { $script:steFixtureForbiddenCalls++; throw 'fixture-forbidden-operation' }

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'fixture-windows-required' }
    if ($PSBoundParameters.ContainsKey('OutputDirectory')) {
        if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { throw 'fixture-output-absolute-new-directory-required' }
    } else {
        $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('swift-windowsui-test-evidence-fixtures-' + [Guid]::NewGuid().ToString('N'))
    }
    # Reject UNC/device paths before filesystem probes, then reject mapped or
    # removable drives. The fixture only reads/writes an owned local directory.
    if ($OutputDirectory -cnotmatch '^[A-Za-z]:[\\/]' -or $OutputDirectory -cmatch '[\x00-\x1f]') {
        throw 'fixture-output-local-drive-required'
    }
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($OutputDirectory))
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) { throw 'fixture-output-fixed-drive-required' }
    $script:steFixtureRoot = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/')
    $parent = [IO.Path]::GetDirectoryName($script:steFixtureRoot)
    if ([string]::IsNullOrEmpty($parent)) { throw 'fixture-output-parent-missing' }
    # Build the chain without IO, then inspect from the drive root downward.
    # Never query a descendant through an already discovered reparse point.
    $ancestors = [Collections.Generic.List[string]]::new()
    $walk = $parent
    while (-not [string]::IsNullOrEmpty($walk)) {
        [void]$ancestors.Add($walk)
        $walk = [IO.Path]::GetDirectoryName($walk)
    }
    for ($i = $ancestors.Count - 1; $i -ge 0; $i--) {
        $attributes = [IO.File]::GetAttributes($ancestors[$i])
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'fixture-output-reparse' }
        if (($attributes -band [IO.FileAttributes]::Directory) -eq 0) { throw 'fixture-output-parent-missing' }
    }
    if ([IO.File]::Exists($script:steFixtureRoot) -or [IO.Directory]::Exists($script:steFixtureRoot)) {
        throw 'fixture-output-already-exists'
    }
    $null = New-Item -ItemType Directory -Path $script:steFixtureRoot -ErrorAction Stop
    $script:steFixtureWorkspace = Join-Path $script:steFixtureRoot 'fake-workspace'
    [void][IO.Directory]::CreateDirectory($script:steFixtureWorkspace)
} catch {
    [Console]::Error.WriteLine('Swift test evidence fixture output initialization failed.')
    exit 1
}

try {
    $sourcePaths = @('scripts/test.ps1', 'scripts/swift-test-evidence.ps1',
        'scripts/agent-check.ps1', 'scripts/with-swift.ps1', 'Package.swift')
    foreach ($relative in $sourcePaths) {
        $bytes = Read-STEFixtureSource (Join-Path $script:steFixtureSourceRoot $relative)
        $digest = Get-STEFixtureHash $bytes
        $script:steFixtureSourceBytes[$relative] = $bytes
        Write-STEFixtureBytes (Join-Path $script:steFixtureWorkspace $relative) $bytes
        [void]$script:steFixtureSourcePins.Add([pscustomobject][ordered]@{
            path = $relative; status = 'observed'; bytes = $bytes.Length; sha256 = $digest
        })
    }
    . (Join-Path $script:steFixtureWorkspace 'scripts/swift-test-evidence.ps1')
    # Exercise the actual Full entry point's pure precedence function without
    # evaluating agent-check's script body or starting any command from it.
    $agentTokens = $null
    $agentParseErrors = $null
    $agentSourcePath = Join-Path $script:steFixtureWorkspace 'scripts/agent-check.ps1'
    $agentAst = ConvertFrom-STEFixtureUtf8Source (Read-STEFixtureSource $agentSourcePath) $agentSourcePath (
        [ref]$agentTokens) ([ref]$agentParseErrors)
    if ($agentParseErrors.Count -ne 0) { throw 'fixture-agent-source-parse' }
    $requestFunctions = @($agentAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq 'Resolve-SwiftTestEvidenceRequest'
    }, $true))
    if ($requestFunctions.Count -ne 1) { throw 'fixture-agent-request-function-count' }
    $requestImpureNodes = @($requestFunctions[0].Body.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -or
            $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -or
            $node -is [Management.Automation.Language.ScriptBlockExpressionAst] -or
            $node -is [Management.Automation.Language.FunctionDefinitionAst]
    }, $true))
    if ($requestImpureNodes.Count -ne 0) { throw 'fixture-agent-request-function-not-pure' }
    . ([scriptblock]::Create($requestFunctions[0].Extent.Text))
    $testTokens = $null
    $testParseErrors = $null
    $testSourcePath = Join-Path $script:steFixtureWorkspace 'scripts/test.ps1'
    $testAst = ConvertFrom-STEFixtureUtf8Source (Read-STEFixtureSource $testSourcePath) $testSourcePath (
        [ref]$testTokens) ([ref]$testParseErrors)
    if ($testParseErrors.Count -ne 0) { throw 'fixture-test-source-parse' }
    foreach ($functionName in @('Invoke-SwiftTest', 'Get-ReportedExitCode')) {
        $definitions = @($testAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq $functionName
        }, $true))
        if ($definitions.Count -ne 1) { throw 'fixture-test-function-count' }
        $allowedUnnamedWriter = $null
        $forwardAdmission = $null
        if ($functionName -ceq 'Invoke-SwiftTest') {
            $forwardAdmission = Get-STEFixtureForwardingAdmission $definitions[0]
            $allowedUnnamedWriter = $forwardAdmission.AllowedUnnamedWriter
        }
        $allowedCommands = if ($functionName -ceq 'Invoke-SwiftTest') {
            @('Write-Host', 'Start-SwiftTestEvidenceShard', 'Add-SwiftTestEvidenceProblem',
                'powershell', 'Out-Host', 'ForEach-Object', 'Add-SwiftTestEvidenceOutput',
                'Write-Output', 'Get-ReportedExitCode', 'Save-SwiftTestEvidenceShard')
        } else { @() }
        $commands = @($definitions[0].Body.FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst]
        }, $true))
        foreach ($command in $commands) {
            if ($null -ne $allowedUnnamedWriter -and [object]::ReferenceEquals($command, $allowedUnnamedWriter)) { continue }
            if ($allowedCommands -cnotcontains $command.GetCommandName()) { throw 'fixture-test-command-not-allowlisted' }
        }
        $definition = [scriptblock]::Create($definitions[0].Extent.Text)
        if ($functionName -ceq 'Invoke-SwiftTest') {
            $script:steFixtureInvokeDefinition = $definition
            $script:steFixtureForwardDefinition = [scriptblock]::Create($forwardAdmission.ForwardingAst.EndBlock.Extent.Text)
        } else { $script:steFixtureExitDefinition = $definition }
    }
    # Reuse the exact current boundary mock definitions for the isolated routes.
    $boundaryAst = (Get-Command Invoke-STEFixtureBoundary -CommandType Function -ErrorAction Stop).ScriptBlock.Ast
    foreach ($fixtureMockName in @('powershell', 'Out-Host')) {
        $fixtureMockFunctions = @($boundaryAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $fixtureMockName
        }, $true))
        if ($fixtureMockFunctions.Count -ne 1 -or $fixtureMockFunctions[0].IsFilter -or $fixtureMockFunctions[0].IsWorkflow -or
            ($null -ne $fixtureMockFunctions[0].Parameters -and $fixtureMockFunctions[0].Parameters.Count -ne 0)) {
            throw 'fixture-transport-definition-changed'
        }
        if ($fixtureMockName -ceq 'powershell' -and $null -ne $fixtureMockFunctions[0].Body.ParamBlock) {
            throw 'fixture-transport-mock-must-stay-simple'
        }
        $fixtureMockDefinition = [scriptblock]::Create($fixtureMockFunctions[0].Extent.Text)
        if ($fixtureMockName -ceq 'powershell') { $script:steFixtureMockDefinition = $fixtureMockDefinition }
        else { $script:steFixtureCollectorDefinition = $fixtureMockDefinition }
    }
    foreach ($name in @('New-SwiftTestEvidenceRecorder', 'Add-SwiftTestEvidenceOutput',
        'Complete-SwiftTestEvidenceRecorder', 'New-SwiftTestEvidenceSession',
        'Start-SwiftTestEvidenceShard', 'Save-SwiftTestEvidenceShard',
        'Complete-SwiftTestEvidenceSession', 'Read-SwiftTestEvidenceJson',
        'Resolve-SwiftTestEvidenceRequest', 'Read-SwiftTestEvidenceBundle',
        'Test-SwiftTestEvidenceComplete', 'Publish-SwiftTestEvidenceCI')) {
        if ($null -eq (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) { throw 'fixture-required-api-missing' }
    }

    # Additional source-only wiring input; not a sixth fake-workspace copy.
    foreach ($requestApi in @('New-SwiftTestEvidenceRequestId', 'New-SwiftTestEvidenceRequest',
        'Write-SwiftTestEvidenceRequestOutput', 'Write-SwiftTestEvidenceRequestLine',
        'Get-SwiftTestEvidenceRequestPathAttributes', 'Test-SwiftTestEvidenceCurrentInvocation')) {
        if ($null -eq (Get-Command $requestApi -CommandType Function -ErrorAction SilentlyContinue)) {
            throw 'fixture-required-request-api-missing'
        }
    }
    $script:steFixtureWorkflowPath = Join-Path $script:steFixtureSourceRoot '.github/workflows/windows-ci.yml'
    $workflowSourceBytes = Read-STEFixtureSource $script:steFixtureWorkflowPath
    $script:steFixtureWorkflowPin = [pscustomobject]@{
        bytes = $workflowSourceBytes.Length; sha256 = Get-STEFixtureHash $workflowSourceBytes
    }
    $script:steFixtureRequestWiring = Get-STEFixtureRequestSourceWiring -AgentAst $agentAst -TestAst $testAst -HelperSource (
        $script:steFixtureUtf8.GetString($script:steFixtureSourceBytes['scripts/swift-test-evidence.ps1'])) -WorkflowSource (
        $script:steFixtureUtf8.GetString($workflowSourceBytes))


    Invoke-STEFixture 'fixed-limit-contract' 3 {
        $limits = Get-SwiftTestEvidenceLimits
        Assert-STEFixture ($limits.maxShards -eq 512 -and $limits.maxCasesPerShard -eq 2048) 'shard-case-caps'
        Assert-STEFixture ($limits.maxLineCharacters -eq 16384 -and $limits.maxIdentifierCharacters -eq 256) 'line-id-caps'
        Assert-STEFixture ($limits.maxJsonBytes -eq 1048576 -and $limits.maxSessionBytes -eq 16777216) 'json-session-caps'
    }
    Invoke-STEFixture 'five-copied-source-pins' 3 {
        $pins = @(Get-SwiftTestEvidenceSourcePins $script:steFixtureWorkspace)
        Assert-STEFixture ($pins.Count -eq 5) 'five-source-files'
        Assert-STEFixtureEqual $pins $script:steFixtureSourcePins.ToArray() 'copied-source-pins'
        Assert-STEFixture (@($pins | Where-Object { $_.status -cne 'observed' }).Count -eq 0) 'all-source-pins-observed'
    }
    $requestCases = @(
        @{ id = 'request-nonfull-ignores-env'; full = $false; explicit = $false; value = $null; env = 'artifacts/env'; expected = '' },
        @{ id = 'request-nonfull-ignores-explicit'; full = $false; explicit = $true; value = 'artifacts/direct'; env = 'artifacts/env'; expected = '' },
        @{ id = 'request-full-env'; full = $true; explicit = $false; value = $null; env = 'artifacts/env'; expected = 'artifacts/env' },
        @{ id = 'request-full-explicit-precedence'; full = $true; explicit = $true; value = 'artifacts/direct'; env = 'artifacts/env'; expected = 'artifacts/direct' },
        @{ id = 'request-explicit-empty-disables'; full = $true; explicit = $true; value = ''; env = 'artifacts/env'; expected = '' },
        @{ id = 'request-explicit-null-disables'; full = $true; explicit = $true; value = $null; env = 'artifacts/env'; expected = '' },
        @{ id = 'request-full-unset-disabled'; full = $true; explicit = $false; value = $null; env = $null; expected = '' },
        @{ id = 'request-full-empty-env-disabled'; full = $true; explicit = $false; value = $null; env = ''; expected = '' }
    )
    foreach ($requestCase in $requestCases) {
        Invoke-STEFixture $requestCase.id 1 {
            $actual = Resolve-SwiftTestEvidenceRequest $requestCase.full $requestCase.explicit $requestCase.value $requestCase.env
            Assert-STEFixtureEqual ([string]$actual) $requestCase.expected 'request-resolution'
        }
    }

    Invoke-STEFixture 'observed-class-method-pass' 4 {
        $result = Get-STEFixtureResult @(New-STEFixtureTrace)
        Assert-STEFixture $result.complete 'pass-complete'
        Assert-STEFixture ($result.observed.started -eq 1 -and $result.observed.passed -eq 1 -and $result.observed.distinctIds -eq 1) 'pass-counts'
        Assert-STEFixture ($result.reported.tests -eq 1 -and $result.reported.failures -eq 0) 'pass-root-counts'
        Assert-STEFixture ($result.wrapperExitCode -eq 0 -and -not $result.output.rawBytesObserved -and -not $result.output.stderrObserved) 'pass-exit-scope'
    }
    Invoke-STEFixture 'nested-root-footer-includes-skip' 5 {
        $trace = @(New-STEFixtureTrace -Ids @('FixtureTests.testPass', 'FixtureTests.testSkip') -Outcomes @('passed', 'skipped') -Nested)
        $result = Get-STEFixtureResult $trace
        Assert-STEFixture $result.complete 'skip-complete'
        Assert-STEFixture ($result.observed.started -eq 2 -and $result.observed.passed -eq 1 -and $result.observed.skipped -eq 1) 'skip-observed-counts'
        Assert-STEFixture ($result.reported.tests -eq 2 -and $result.reported.skipped -eq 1) 'skip-in-executed-total'
        Assert-STEFixture ($result.rootStatus -ceq 'passed') 'skip-root-passes'
        Assert-STEFixture ($result.problems.Count -eq 0) 'nested-footer-not-double-counted'
    }
    Invoke-STEFixture 'assertion-failures-not-failed-cases' 5 {
        $result = Get-STEFixtureResult @(New-STEFixtureTrace -Outcomes @('failed') -ReportedFailures 3) 23
        Assert-STEFixture $result.complete 'failure-output-complete'
        Assert-STEFixture ($result.observed.failed -eq 1 -and $result.observed.started -eq 1) 'one-failed-case'
        Assert-STEFixture ($result.reported.failures -eq 3) 'three-framework-failures'
        Assert-STEFixture ($result.wrapperExitCode -eq 23) 'failure-exit-preserved'
        Assert-STEFixture ($result.rootStatus -ceq 'failed') 'failed-root-preserved'
    }
    Invoke-STEFixture 'sequential-repeat-counts-distinctly' 4 {
        $result = Get-STEFixtureResult @(New-STEFixtureTrace -Ids @('FixtureTests.testOne', 'FixtureTests.testOne') -Outcomes @('passed', 'passed'))
        Assert-STEFixture $result.complete 'repeat-complete'
        Assert-STEFixture ($result.observed.started -eq 2 -and $result.observed.passed -eq 2) 'repeat-executions'
        Assert-STEFixture ($result.observed.distinctIds -eq 1) 'repeat-distinct-id'
        Assert-STEFixture ($result.observed.repeatedExecutions -eq 1) 'repeat-extra-execution'
    }
    Invoke-STEFixture 'orphan-terminal-does-not-erase-observed-repeat' 3 {
        $trace = @(New-STEFixtureTrace -Ids @('FixtureTests.testOne', 'FixtureTests.testOne') -Outcomes @('passed', 'passed'))
        $lines = @($trace[0..4]) + @("Test Case 'FixtureTests.testOrphan' passed (0.002 seconds)") + @($trace[5..($trace.Count - 1)])
        $result = Get-STEFixtureResult $lines 1
        Assert-STEFixtureIncomplete $result 'outcome-without-start'
        Assert-STEFixture ($result.observed.started -eq 2 -and $result.observed.passed -eq 3 -and $result.observed.distinctIds -eq 2) 'orphan-counts-retained'
        Assert-STEFixture ($result.observed.repeatedExecutions -eq 1) 'orphan-does-not-erase-repeat'
    }
    Invoke-STEFixture 'identifier-comparison-is-ordinal' 3 {
        $result = Get-STEFixtureResult @(New-STEFixtureTrace -Ids @('FixtureTests.testOne', 'FixtureTests.testone') -Outcomes @('passed', 'passed'))
        Assert-STEFixture $result.complete 'ordinal-complete'
        Assert-STEFixture ($result.observed.distinctIds -eq 2) 'ordinal-distinct-ids'
        Assert-STEFixture ($result.cases.Count -eq 2) 'ordinal-case-rows'
    }
    Invoke-STEFixture 'zero-selected-tests' 3 {
        $result = Get-STEFixtureResult @(New-STEFixtureTrace -Ids @() -Outcomes @())
        Assert-STEFixture $result.complete 'zero-complete'
        Assert-STEFixture ($result.reported.tests -eq 0 -and $result.observed.started -eq 0) 'zero-reconciled'
        Assert-STEFixture ($result.cases.Count -eq 0) 'zero-empty-cases'
    }
    Invoke-STEFixture 'all-tests-root-alias' 3 {
        $result = Get-STEFixtureResult @(New-STEFixtureTrace -Ids @() -Outcomes @() -AllTests)
        Assert-STEFixture $result.complete 'all-root-complete'
        Assert-STEFixture ($result.rootStatus -ceq 'passed') 'all-root-status'
        Assert-STEFixture ($result.reported.tests -eq 0) 'all-root-zero'
    }
    Invoke-STEFixture 'swift-testing-markers-stay-separate' 4 {
        $lines = @(New-STEFixtureTrace) + @(
            ([string][char]0x25ca + ' Test run started.'),
            ([string][char]0x2192 + ' Testing Library Version: 6.3 (980fec0f03c56f7)'),
            ([string][char]0x221a + ' Test run with 0 tests in 0 suites passed after 0.001 seconds.')
        )
        $result = Get-STEFixtureResult $lines
        Assert-STEFixture $result.complete 'xctest-still-complete'
        Assert-STEFixture $result.swiftTesting.markerObserved 'swift-testing-marker'
        Assert-STEFixture ($result.swiftTesting.status -ceq 'not-instrumented' -and $null -eq $result.swiftTesting.counts) 'swift-testing-unclaimed'
        Assert-STEFixture ($result.observed.started -eq 1) 'swift-testing-not-added'
    }
    Invoke-STEFixture 'swift-testing-alone-not-xctest-zero' 3 {
        $result = Get-STEFixtureResult @('Test run started.', 'Test run with 0 tests in 0 suites passed after 0.001 seconds.')
        Assert-STEFixtureIncomplete $result 'incomplete-root-run'
        Assert-STEFixture $result.swiftTesting.markerObserved 'only-swift-testing-marker'
        Assert-STEFixture ($null -eq $result.reported -and $null -eq $result.swiftTesting.counts) 'only-swift-testing-unknown'
    }
    Invoke-STEFixture 'nonzero-wrapper-does-not-rewrite-cases' 3 {
        $result = Get-STEFixtureResult @(New-STEFixtureTrace) 19
        Assert-STEFixture $result.complete 'complete-xctest-output-despite-wrapper'
        Assert-STEFixture ($result.wrapperExitCode -eq 19) 'nonzero-wrapper-retained'
        Assert-STEFixture ($result.rootStatus -ceq 'passed' -and $result.observed.passed -eq 1) 'case-result-not-rewritten'
    }
    Invoke-STEFixture 'missing-wrapper-exit-is-incomplete' 2 {
        $result = Get-STEFixtureResult @(New-STEFixtureTrace) $null
        Assert-STEFixtureIncomplete $result 'wrapper-exit-unavailable'
        Assert-STEFixture ($null -eq $result.wrapperExitCode) 'missing-exit-not-zero'
    }
    Invoke-STEFixture 'wrapper-framework-disagreement' 2 {
        $result = Get-STEFixtureResult @(New-STEFixtureTrace -Outcomes @('failed')) 0
        Assert-STEFixtureIncomplete $result 'wrapper-framework-disagreement'
        Assert-STEFixture ($result.wrapperExitCode -eq 0 -and $result.observed.failed -eq 1) 'disagreement-original-values'
    }
    Invoke-STEFixture 'root-total-mismatch' 3 {
        $trace = @(New-STEFixtureTrace)
        $trace[$trace.Count - 1] = ' Executed 2 tests, with 0 failures (0 unexpected) in 0.01 (0.01) seconds'
        $result = Get-STEFixtureResult $trace
        Assert-STEFixtureIncomplete $result 'framework-count-mismatch'
        Assert-STEFixture ($result.observed.started -eq 1) 'mismatch-observed-retained'
        Assert-STEFixture ($result.reported.tests -eq 2) 'mismatch-reported-retained'
    }
    Invoke-STEFixture 'unexpected-failures-cannot-exceed-failures' 2 {
        $result = Get-STEFixtureResult @(New-STEFixtureTrace -Outcomes @('failed') -ReportedFailures 1 -UnexpectedFailures 2) 1
        Assert-STEFixtureIncomplete $result 'framework-count-mismatch'
        Assert-STEFixture ($result.reported.unexpectedFailures -eq 2) 'unexpected-count-retained'
    }
    Invoke-STEFixture 'root-failure-without-failed-case-is-incomplete' 2 {
        $result = Get-STEFixtureResult @(New-STEFixtureTrace -ReportedFailures 1) 1
        Assert-STEFixtureIncomplete $result 'framework-count-mismatch'
        Assert-STEFixture ($result.rootStatus -ceq 'failed' -and $result.observed.failed -eq 0 -and $result.reported.failures -eq 1) 'unattributed-root-failure-retained'
    }
    Invoke-STEFixture 'root-start-and-terminal-names-must-match' 2 {
        $trace = @(New-STEFixtureTrace)
        $trace[$trace.Count - 3] = "Test Suite 'All tests' passed at 2026-08-28 12:01:18.466"
        $result = Get-STEFixtureResult $trace
        Assert-STEFixtureIncomplete $result 'root-name-mismatch'
        Assert-STEFixture ($result.rootStatus -ceq 'passed' -and $result.reported.tests -eq 1) 'mismatched-root-observations-retained'
    }
    Invoke-STEFixture 'unfinished-start-is-retained' 2 {
        $lines = @(New-STEFixtureTrace)
        $lines = @($lines | Where-Object { $_ -notmatch "^Test Case .* passed " })
        $result = Get-STEFixtureResult $lines 1
        Assert-STEFixtureIncomplete $result 'unfinished-cases'
        Assert-STEFixture ($result.observed.unfinished -eq 1) 'unfinished-count'
    }
    Invoke-STEFixture 'terminal-without-start' 3 {
        $lines = @(New-STEFixtureTrace | Where-Object { $_ -notmatch "^Test Case .* started " })
        $result = Get-STEFixtureResult $lines
        Assert-STEFixtureIncomplete $result 'outcome-without-start'
        Assert-STEFixture ($result.observed.started -eq 0) 'orphan-start-count'
        Assert-STEFixture ($result.observed.passed -eq 1) 'orphan-terminal-retained'
    }
    Invoke-STEFixture 'orphan-terminal-before-start-stays-unfinished' 3 {
        $trace = @(New-STEFixtureTrace)
        $lines = @($trace[0], $trace[2], $trace[1]) + @($trace[3..($trace.Count - 1)])
        $result = Get-STEFixtureResult $lines 1
        Assert-STEFixtureIncomplete $result 'outcome-without-start'
        Assert-STEFixture ($result.observed.started -eq 1 -and $result.observed.passed -eq 1 -and $result.observed.unfinished -eq 1) 'later-start-not-closed-by-prior-terminal'
        Assert-STEFixture ($result.cases[0].unmatchedTerminals -eq 1 -and $result.cases[0].unfinished -eq 1) 'unmatched-terminal-retained'
    }
    Invoke-STEFixture 'overlapping-starts-are-not-retries' 2 {
        $trace = @(New-STEFixtureTrace)
        $lines = @($trace[0], $trace[1], $trace[1]) + @($trace[2..($trace.Count - 1)])
        $result = Get-STEFixtureResult $lines 1
        Assert-STEFixtureIncomplete $result 'overlapping-case-start'
        Assert-STEFixture ($result.observed.unfinished -eq 1) 'overlap-unfinished'
    }
    Invoke-STEFixture 'duplicate-terminal-is-not-a-new-execution' 3 {
        $trace = @(New-STEFixtureTrace)
        $lines = @($trace[0], $trace[1], $trace[2], $trace[2]) + @($trace[3..($trace.Count - 1)])
        $result = Get-STEFixtureResult $lines
        Assert-STEFixtureIncomplete $result 'outcome-without-start'
        Assert-STEFixture ($result.observed.passed -eq 2) 'duplicate-terminal-retained'
        Assert-STEFixture ($result.observed.started -eq 1) 'duplicate-not-extra-start'
    }
    Invoke-STEFixture 'case-after-root-is-incomplete' 2 {
        $lines = @(New-STEFixtureTrace) + @("Test Case 'FixtureTests.testLate' started at 2026-08-28 12:01:18.467")
        $result = Get-STEFixtureResult $lines
        Assert-STEFixtureIncomplete $result 'case-outside-root'
        Assert-STEFixture ($result.observed.unfinished -eq 1) 'late-start-retained'
    }
    Invoke-STEFixture 'missing-root-footer-is-incomplete' 2 {
        $trace = @(New-STEFixtureTrace)
        $trace[$trace.Count - 1] = 'ordinary unrelated output'
        $result = Get-STEFixtureResult $trace
        Assert-STEFixtureIncomplete $result 'missing-root-footer'
        Assert-STEFixture ($null -eq $result.reported) 'missing-footer-not-guessed'
    }
    Invoke-STEFixture 'multiple-root-runs-are-incomplete' 2 {
        $result = Get-STEFixtureResult (@(New-STEFixtureTrace) + @(New-STEFixtureTrace))
        Assert-STEFixtureIncomplete $result 'multiple-root-runs'
        Assert-STEFixture ($result.observed.repeatedExecutions -eq 1) 'multiple-root-events-retained'
    }
    Invoke-STEFixture 'unknown-case-grammar-is-incomplete' 2 {
        $trace = @(New-STEFixtureTrace -Ids @() -Outcomes @())
        $lines = @($trace[0], "Test Case 'FixtureTests.testOne' finished unexpectedly") + @($trace[1..($trace.Count - 1)])
        $result = Get-STEFixtureResult $lines
        Assert-STEFixtureIncomplete $result 'unsupported-case-line'
        Assert-STEFixture ($result.cases.Count -eq 0) 'unknown-case-not-invented'
    }
    Invoke-STEFixture 'unsupported-case-identifier-is-incomplete' 2 {
        $result = Get-STEFixtureResult @(New-STEFixtureTrace -Ids @('FixtureTests/testOne'))
        Assert-STEFixtureIncomplete $result 'unsupported-case-identifier'
        Assert-STEFixture ($result.cases.Count -eq 0) 'unsupported-id-not-published'
    }
    Invoke-STEFixture 'non-string-observer-preserves-object-forwarding' 4 {
        $recorder = New-SwiftTestEvidenceRecorder
        $original = [pscustomobject]@{ marker = 'PRIVATE-PAYLOAD-CANARY' }
        $original | Add-Member -MemberType ScriptMethod -Name ToString -Value { throw 'fixture-object-must-not-stringify' } -Force
        $inputObjects = @('ordinary console line', $original)
        # This models the proposed pass-through contract, not test.ps1 integration.
        $forwarded = @($inputObjects | ForEach-Object { Add-SwiftTestEvidenceOutput $recorder $_; $_ })
        Assert-STEFixture ($forwarded.Count -eq 2) 'forwarded-object-count'
        Assert-STEFixture ([object]::ReferenceEquals($forwarded[1], $original)) 'forwarded-object-identity'
        Assert-STEFixture ($recorder.NonStringObjects -eq 1 -and $recorder.OutputObjects -eq 2) 'nonstring-counts'
        $result = Complete-SwiftTestEvidenceRecorder $recorder 0
        Assert-STEFixtureIncomplete $result 'non-string-output'
    }
    Invoke-STEFixture 'null-output-does-not-throw-or-emit' 3 {
        $recorder = New-SwiftTestEvidenceRecorder
        $emitted = @(Add-SwiftTestEvidenceOutput $recorder $null)
        Assert-STEFixture ($emitted.Count -eq 0) 'null-observer-output'
        Assert-STEFixture ($recorder.NonStringObjects -eq 1) 'null-is-nonstring'
        Assert-STEFixtureIncomplete (Complete-SwiftTestEvidenceRecorder $recorder 0) 'non-string-output'
    }
    Invoke-STEFixture 'observer-internal-error-does-not-escape' 2 {
        $recorder = [pscustomobject]@{
            Problems = [Collections.Generic.List[string]]::new()
            Limits = Get-SwiftTestEvidenceLimits
            OutputObjects = 0
        }
        $emitted = @(Add-SwiftTestEvidenceOutput $recorder 'ordinary line')
        Assert-STEFixture ($emitted.Count -eq 0) 'observer-error-no-output'
        Assert-STEFixture ($recorder.Problems.Contains('observer-error')) 'observer-error-recorded'
    }
    Invoke-STEFixture 'observer-does-not-replace-last-exit' 2 {
        $saved = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        $hadSavedExit = $null -ne $saved
        $savedExitValue = if ($hadSavedExit) { $saved.Value } else { $null }
        try {
            $global:LASTEXITCODE = 71
            $result = Get-STEFixtureResult @(New-STEFixtureTrace) 71
            Assert-STEFixture ($global:LASTEXITCODE -eq 71) 'last-exit-not-mutated'
            Assert-STEFixture ($result.wrapperExitCode -eq 71) 'reported-exit-not-mutated'
        } finally {
            if ($hadSavedExit) { $global:LASTEXITCODE = $savedExitValue }
            else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
        }
    }
    Invoke-STEFixture 'unknown-root-completion-is-incomplete' 2 {
        $trace = @(New-STEFixtureTrace)
        $trace[$trace.Count - 3] = "Test Suite 'Selected tests' finished at 2026-08-28 12:01:18.466"
        $result = Get-STEFixtureResult $trace
        Assert-STEFixtureIncomplete $result 'incomplete-root-run'
        Assert-STEFixture ($null -eq $result.rootStatus) 'unknown-root-not-guessed'
    }

    Invoke-STEFixture 'line-length-limit' 2 {
        $recorder = New-SwiftTestEvidenceRecorder
        $recorder.Limits.maxLineCharacters = 32
        Add-STEFixtureTrace $recorder @('x' * 33)
        Assert-STEFixtureIncomplete (Complete-SwiftTestEvidenceRecorder $recorder 0) 'line-character-limit'
        Assert-STEFixture ($recorder.Cases.Count -eq 0) 'oversized-line-not-retained'
    }
    Invoke-STEFixture 'output-object-limit' 2 {
        $recorder = New-SwiftTestEvidenceRecorder
        $recorder.Limits.maxOutputObjects = 1
        Add-STEFixtureTrace $recorder @('ordinary line', 'second line')
        Assert-STEFixtureIncomplete (Complete-SwiftTestEvidenceRecorder $recorder 0) 'output-object-limit'
        Assert-STEFixture ($recorder.OutputObjects -eq 1) 'output-count-capped'
    }
    Invoke-STEFixture 'identifier-length-limit' 2 {
        $recorder = New-SwiftTestEvidenceRecorder
        $recorder.Limits.maxIdentifierCharacters = 20
        Add-STEFixtureTrace $recorder @(New-STEFixtureTrace -Ids @('FixtureTests.testIdentifierTooLong'))
        Assert-STEFixtureIncomplete (Complete-SwiftTestEvidenceRecorder $recorder 0) 'unsupported-case-identifier'
        Assert-STEFixture ($recorder.Cases.Count -eq 0) 'long-id-not-published'
    }
    Invoke-STEFixture 'per-shard-case-limit' 3 {
        $recorder = New-SwiftTestEvidenceRecorder
        $recorder.Limits.maxCasesPerShard = 1
        Add-STEFixtureTrace $recorder @(New-STEFixtureTrace -Ids @('FixtureTests.testOne', 'FixtureTests.testTwo') -Outcomes @('passed', 'passed'))
        $result = Complete-SwiftTestEvidenceRecorder $recorder 0
        Assert-STEFixtureIncomplete $result 'case-limit'
        Assert-STEFixture ($result.cases.Count -eq 1) 'case-limit-capped'
        Assert-STEFixture ($result.observed.started -eq 1) 'dropped-case-not-counted-as-complete'
    }
    Invoke-STEFixture 'case-start-event-limit' 2 {
        $recorder = New-SwiftTestEvidenceRecorder
        $recorder.Limits.maxCaseObservations = 1
        Add-STEFixtureTrace $recorder @(
            "Test Suite 'Selected tests' started at 2026-08-28 12:01:18.464",
            "Test Case 'FixtureTests.testOne' started at 2026-08-28 12:01:18.464",
            "Test Case 'FixtureTests.testOne' passed (0.002 seconds)"
        )
        Add-STEFixtureTrace $recorder @("Test Case 'FixtureTests.testOne' started at 2026-08-28 12:01:18.464")
        Assert-STEFixtureIncomplete (Complete-SwiftTestEvidenceRecorder $recorder 1) 'case-event-limit'
        Assert-STEFixture ($recorder.Cases.Count -eq 1 -and $recorder.CaseStarts -eq 1) 'start-event-limit-bounded'
    }
    Invoke-STEFixture 'case-terminal-event-limit' 2 {
        $recorder = New-SwiftTestEvidenceRecorder
        $recorder.Limits.maxCaseObservations = 1
        Add-STEFixtureTrace $recorder @(
            "Test Suite 'Selected tests' started at 2026-08-28 12:01:18.464",
            "Test Case 'FixtureTests.testOne' started at 2026-08-28 12:01:18.464",
            "Test Case 'FixtureTests.testOne' passed (0.002 seconds)",
            "Test Case 'FixtureTests.testOne' passed (0.002 seconds)"
        )
        Assert-STEFixtureIncomplete (Complete-SwiftTestEvidenceRecorder $recorder 1) 'case-event-limit'
        Assert-STEFixture ($recorder.CaseTerminals -eq 1 -and $recorder.Cases['FixtureTests.testOne'].passed -eq 1) 'terminal-event-limit-bounded'
    }

    Invoke-STEFixture 'fresh-relative-directory-and-existing-refusal' 4 {
        $relative = New-STEFixtureRelative
        $expected = [IO.Path]::GetFullPath((Join-Path $script:steFixtureWorkspace $relative))
        $resolved = Resolve-SwiftTestEvidenceDirectory $script:steFixtureWorkspace $relative
        Assert-STEFixtureEqual $resolved $expected 'relative-resolution'
        $created = New-SwiftTestEvidenceDirectory $script:steFixtureWorkspace $relative
        Assert-STEFixture ([IO.Directory]::Exists($created)) 'fresh-directory-created'
        Assert-STEFixtureRejected { New-SwiftTestEvidenceDirectory $script:steFixtureWorkspace $relative } 'test-evidence-destination-exists'
    }
    Invoke-STEFixture 'fresh-absolute-inside-artifacts' 2 {
        $absolute = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
        Assert-STEFixtureEqual (Resolve-SwiftTestEvidenceDirectory $script:steFixtureWorkspace $absolute) $absolute 'absolute-resolution'
        $created = New-SwiftTestEvidenceDirectory $script:steFixtureWorkspace $absolute
        Assert-STEFixture ([IO.Directory]::Exists($created)) 'absolute-inside-created'
    }
    Invoke-STEFixture 'existing-case-alias-refused' 3 {
        $relative = New-STEFixtureRelative
        $created = New-SwiftTestEvidenceDirectory $script:steFixtureWorkspace $relative
        Assert-STEFixtureRejected { New-SwiftTestEvidenceDirectory $script:steFixtureWorkspace $relative.ToUpperInvariant() } 'test-evidence-destination-exists'
        Assert-STEFixture ([IO.Directory]::Exists($created)) 'case-alias-original-preserved'
    }
    $pathCases = @(
        @{ id = 'path-empty'; value = '' },
        @{ id = 'path-artifacts-root'; value = 'artifacts' },
        @{ id = 'path-relative-outside'; value = '../outside' },
        @{ id = 'path-traversal-inside'; value = 'artifacts/a/../escaped' },
        @{ id = 'path-dot-component'; value = 'artifacts/./dot' },
        @{ id = 'path-rooted-outside'; value = (Join-Path $script:steFixtureRoot 'outside-workspace') },
        @{ id = 'path-ads'; value = 'artifacts/receipt:stream' },
        @{ id = 'path-device-name'; value = 'artifacts/NUL' },
        @{ id = 'path-trailing-dot'; value = 'artifacts/trailing.' },
        @{ id = 'path-trailing-space'; value = 'artifacts/trailing ' },
        @{ id = 'path-parent-trailing-dot'; value = 'artifacts/parent./child' },
        @{ id = 'path-parent-trailing-space'; value = 'artifacts/parent /child' },
        @{ id = 'path-linebreak-suffix'; value = ('artifacts/linefeed' + [char]10) },
        @{ id = 'path-hidden-component'; value = 'artifacts/.hidden' },
        @{ id = 'path-space-component'; value = 'artifacts/space component' }
    )
    foreach ($pathCase in $pathCases) {
        Invoke-STEFixture $pathCase.id 2 {
            # Resolver only: even a regression cannot create a directory outside.
            Assert-STEFixtureRejected { Resolve-SwiftTestEvidenceDirectory $script:steFixtureWorkspace $pathCase.value } -AsPathError
        }
    }
    Invoke-STEFixture 'path-missing-workspace-root' 2 {
        $missing = Join-Path $script:steFixtureRoot 'absent-workspace'
        Assert-STEFixtureRejected { Resolve-SwiftTestEvidenceDirectory $missing 'artifacts/new' } 'test-evidence-root-missing'
    }
    $nonlocalPaths = @(
        @{ id = 'path-unc-workspace-guard'; root = '\\fixture.invalid\share'; path = 'artifacts/new' },
        @{ id = 'path-device-workspace-guard'; root = '\\?\C:\fixture'; path = 'artifacts/new' },
        @{ id = 'path-unc-destination-guard'; root = $script:steFixtureWorkspace; path = '\\fixture.invalid\share\new' },
        @{ id = 'path-device-destination-guard'; root = $script:steFixtureWorkspace; path = '\\?\C:\fixture\new' },
        @{ id = 'path-mixed-prefix-backslash-slash'; root = $script:steFixtureWorkspace; path = '\/fixture.invalid/share/new' },
        @{ id = 'path-mixed-prefix-slash-backslash'; root = $script:steFixtureWorkspace; path = '/\fixture.invalid/share/new' }
    )
    foreach ($nonlocalPath in $nonlocalPaths) {
        Invoke-STEFixture $nonlocalPath.id 2 {
            Assert-STEFixtureEarlyLocalPathGuard
            Assert-STEFixtureRejected { Resolve-SwiftTestEvidenceDirectory $nonlocalPath.root $nonlocalPath.path } 'test-evidence-path-invalid'
        }
    }

    Invoke-STEFixture 'canonical-json-roundtrip-preserves-shapes' 6 {
        $path = Join-Path $script:steFixtureRoot 'canonical.json'
        $value = [pscustomobject][ordered]@{
            schemaVersion = 1; empty = @(); one = @('one'); many = @('one', 'two')
            missing = $null; nested = [pscustomobject][ordered]@{ escaped = ('quote' + [char]34 + 'slash' + [char]92) }
        }
        $written = Write-SwiftTestEvidenceJsonNew $path $value
        $actual = Read-SwiftTestEvidenceJson $path
        Assert-STEFixtureEqual (ConvertTo-SwiftTestEvidenceJson $actual) (ConvertTo-SwiftTestEvidenceJson $value) 'canonical-roundtrip'
        Assert-STEFixture ($actual.empty -is [array] -and $actual.empty.Count -eq 0) 'empty-array-preserved'
        Assert-STEFixture ($actual.one -is [array] -and $actual.one.Count -eq 1) 'singleton-array-preserved'
        Assert-STEFixture ($actual.many -is [array] -and $actual.many.Count -eq 2) 'multi-array-preserved'
        Assert-STEFixture ($null -eq $actual.missing) 'explicit-null-preserved'
        Assert-STEFixture ($written -eq (Get-Item -LiteralPath $path).Length) 'writer-byte-accounting'
    }
    Invoke-STEFixture 'canonical-json-whitespace-not-string-loss' 2 {
        $path = Join-Path $script:steFixtureRoot 'whitespace.json'
        Write-STEFixtureText $path ('{ ' + [char]10 + '"schemaVersion":1, "value":" a b " }')
        $value = Read-SwiftTestEvidenceJson $path
        Assert-STEFixture ($value.schemaVersion -eq 1) 'json-whitespace-allowed'
        Assert-STEFixtureEqual $value.value ' a b ' 'json-string-spaces-preserved'
    }
    $jsonCases = @(
        @{ id = 'json-duplicate-key'; text = '{"value":1,"value":2}' },
        @{ id = 'json-case-alias'; text = '{"value":1,"Value":2}' },
        @{ id = 'json-escaped-duplicate'; text = '{"value":1,"\u0076alue":2}' },
        @{ id = 'json-alternate-key-escape'; text = '{"\u0076alue":1}' },
        @{ id = 'json-alternate-value-escape'; text = '{"value":"\u0041"}' },
        @{ id = 'json-comment'; text = '{"value":1/* comment */}' },
        @{ id = 'json-trailing-comma'; text = '{"value":1,}' },
        @{ id = 'json-trailing-text'; text = '{"value":1} trailing' },
        @{ id = 'json-array-root'; text = '[1,2]' },
        @{ id = 'json-null-root'; text = 'null' }
    )
    foreach ($jsonCase in $jsonCases) {
        Invoke-STEFixture $jsonCase.id 2 {
            $path = Join-Path $script:steFixtureRoot ($jsonCase.id + '.json')
            Write-STEFixtureText $path $jsonCase.text
            Assert-STEFixtureRejected { Read-SwiftTestEvidenceJson $path } -Json
        }
    }
    Invoke-STEFixture 'json-write-limit-no-output' 3 {
        $path = Join-Path $script:steFixtureRoot 'write-limit.json'
        Assert-STEFixtureRejected { Write-SwiftTestEvidenceJsonNew $path ([pscustomobject]@{ value = ('a' * 128) }) 32 } 'test-evidence-json-limit'
        Assert-STEFixture (-not [IO.File]::Exists($path)) 'json-write-limit-no-file'
    }
    Invoke-STEFixture 'json-read-limit' 2 {
        $path = Join-Path $script:steFixtureRoot 'read-limit.json'
        Write-STEFixtureText $path ('{"value":"' + ('a' * 64) + '"}')
        Assert-STEFixtureRejected { Read-SwiftTestEvidenceJson $path 32 } 'test-evidence-json-limit'
    }
    Invoke-STEFixture 'json-empty-file' 2 {
        $path = Join-Path $script:steFixtureRoot 'empty.json'
        Write-STEFixtureBytes $path ([byte[]]@())
        Assert-STEFixtureRejected { Read-SwiftTestEvidenceJson $path } 'test-evidence-json-limit'
    }
    Invoke-STEFixture 'json-invalid-utf8' 2 {
        $path = Join-Path $script:steFixtureRoot 'invalid-utf8.json'
        Write-STEFixtureBytes $path ([byte[]]@(123, 34, 120, 34, 58, 34, 195, 40, 34, 125))
        Assert-STEFixtureRejected { Read-SwiftTestEvidenceJson $path } -Json
    }
    Invoke-STEFixture 'json-depth-limit-before-conversion' 2 {
        $path = Join-Path $script:steFixtureRoot 'depth-limit.json'
        Write-STEFixtureText $path (('{"value":' * 17) + '0' + ('}' * 17))
        Assert-STEFixtureRejected { Read-SwiftTestEvidenceJson $path } 'test-evidence-json-depth'
    }

    Invoke-STEFixture 'session-complete-with-cross-shard-repeat' 5 {
        $session = New-STEFixtureSession 2
        Save-STEFixturePassingShard $session 1
        Save-STEFixturePassingShard $session 2
        Complete-SwiftTestEvidenceSession $session 0
        $summary = Read-STEFixtureSummary $session
        Assert-STEFixture ($session.Plan.metadata.sourceFiles.Count -eq 5 -and $session.Plan.portable -ceq 'not-instrumented') 'session-source-scope'
        Assert-STEFixture ($summary.evidenceCompleteForDeclaredScope -and $null -ne $summary.completeCounts) 'session-complete'
        Assert-STEFixture ($summary.observed.started -eq 2 -and $summary.observed.distinctIds -eq 1 -and $summary.observed.repeatedExecutions -eq 1) 'session-global-distinct'
        Assert-STEFixture ($summary.plannedShards -eq 2 -and $summary.completedShards -eq 2 -and $summary.unstartedShardIndices.Count -eq 0 -and $summary.startedWithoutResultShardIndices.Count -eq 0) 'session-shard-accounting'
        Assert-STEFixture ($summary.testScriptExitCode -eq 0 -and [IO.File]::Exists((Join-Path $session.Directory 'shard-0002-result.json'))) 'session-durable-result'
    }
    Invoke-STEFixture 'session-failure-keeps-unstarted-shards' 4 {
        $session = New-STEFixtureSession 2
        $recorder = Start-SwiftTestEvidenceShard $session 1
        Add-STEFixtureTrace $recorder @(New-STEFixtureTrace -Outcomes @('failed'))
        Save-SwiftTestEvidenceShard $session $recorder 7
        Complete-SwiftTestEvidenceSession $session 7
        $summary = Read-STEFixtureSummary $session
        Assert-STEFixture (-not $summary.evidenceCompleteForDeclaredScope -and $null -eq $summary.completeCounts) 'failed-session-incomplete'
        Assert-STEFixture ($summary.testScriptExitCode -eq 7 -and $summary.observed.failed -eq 1) 'failed-session-exit'
        Assert-STEFixtureEqual @($summary.unstartedShardIndices) @(2) 'failed-session-unstarted'
        Assert-STEFixture (-not [IO.File]::Exists((Join-Path $session.Directory 'shard-0002-start.json'))) 'unstarted-no-receipt'
    }
    Invoke-STEFixture 'session-resume-is-not-a-full-pass' 4 {
        $session = New-STEFixtureSession 3 2
        Save-STEFixturePassingShard $session 2
        Save-STEFixturePassingShard $session 3
        Complete-SwiftTestEvidenceSession $session 0
        $summary = Read-STEFixtureSummary $session
        Assert-STEFixture (-not $summary.evidenceCompleteForDeclaredScope -and $null -eq $summary.completeCounts) 'resume-incomplete-full'
        Assert-STEFixture ($summary.startShard -eq 2 -and @($summary.unstartedShardIndices).Count -eq 1 -and $summary.unstartedShardIndices[0] -eq 1) 'resume-omitted-shard'
        Assert-STEFixture ($summary.observed.skipped -eq 0 -and $summary.startedWithoutResultShardIndices.Count -eq 0) 'resume-not-xctest-skip'
        Assert-STEFixture (-not [IO.File]::Exists((Join-Path $session.Directory 'shard-0001-start.json'))) 'resume-no-prior-start'
    }
    Invoke-STEFixture 'session-never-started-stays-incomplete' 3 {
        $session = New-STEFixtureSession 2
        Complete-SwiftTestEvidenceSession $session $null
        $summary = Read-STEFixtureSummary $session
        Assert-STEFixture (-not $summary.evidenceCompleteForDeclaredScope -and $summary.unstartedShardIndices.Count -eq 2 -and $summary.startedWithoutResultShardIndices.Count -eq 0) 'never-started-incomplete'
        Assert-STEFixture ($summary.observed.started -eq 0 -and $null -eq $summary.completeCounts) 'never-started-not-complete-zero'
        Assert-STEFixture ($null -eq $summary.testScriptExitCode) 'never-started-exit-unknown'
    }
    Invoke-STEFixture 'session-start-without-result-retains-boundary' 4 {
        $session = New-STEFixtureSession
        $null = Start-SwiftTestEvidenceShard $session 1
        Complete-SwiftTestEvidenceSession $session 1
        $summary = Read-STEFixtureSummary $session
        Assert-STEFixture (-not $summary.evidenceCompleteForDeclaredScope -and $null -eq $summary.completeCounts) 'started-without-result-incomplete'
        Assert-STEFixture ([IO.File]::Exists((Join-Path $session.Directory 'shard-0001-start.json')) -and -not [IO.File]::Exists((Join-Path $session.Directory 'shard-0001-result.json'))) 'started-boundary-preserved'
        Assert-STEFixture ($summary.unstartedShardIndices.Count -eq 0) 'durable-start-not-unstarted'
        Assert-STEFixtureEqual @($summary.startedWithoutResultShardIndices) @(1) 'durable-start-without-result-index'
    }
    Invoke-STEFixture 'session-source-change-invalidates-completeness' 2 {
        $session = New-STEFixtureSession
        Save-STEFixturePassingShard $session 1
        $path = Join-Path $script:steFixtureWorkspace 'Package.swift'
        $original = [byte[]]$script:steFixtureSourceBytes['Package.swift']
        try {
            Write-STEFixtureBytes $path ([byte[]]@($original + [byte[]]@(10))) -ReplaceOwned
            Complete-SwiftTestEvidenceSession $session 0
            $summary = Read-STEFixtureSummary $session
            Assert-STEFixture ($summary.problems -ccontains 'source-files-changed') 'source-change-problem'
            Assert-STEFixture (-not $summary.evidenceCompleteForDeclaredScope -and $null -eq $summary.completeCounts) 'source-change-not-complete'
        } finally { Write-STEFixtureBytes $path $original -ReplaceOwned }
    }
    Invoke-STEFixture 'session-start-write-failure-preserves-existing' 4 {
        $session = New-STEFixtureSession
        $path = Join-Path $session.Directory 'shard-0001-start.json'
        Write-STEFixtureText $path '{"owned":"existing"}'
        $before = Get-STEFixtureHash ([IO.File]::ReadAllBytes($path))
        $recorder = Start-SwiftTestEvidenceShard $session 1
        Assert-STEFixture ($null -ne $recorder) 'start-error-recorder-returned'
        Assert-STEFixture ($session.Problems.Contains('shard-start-write-failed')) 'start-error-recorded'
        Assert-STEFixtureEqual (Get-STEFixtureHash ([IO.File]::ReadAllBytes($path))) $before 'start-existing-unchanged'
        Assert-STEFixture ($session.Results.Count -eq 0 -and $session.WrittenStartIndices.Count -eq 0) 'start-error-no-result'
    }
    Invoke-STEFixture 'session-result-write-failure-preserves-exit' 6 {
        $session = New-STEFixtureSession
        $recorder = Start-SwiftTestEvidenceShard $session 1
        Add-STEFixtureTrace $recorder @(New-STEFixtureTrace)
        $path = Join-Path $session.Directory 'shard-0001-result.json'
        Write-STEFixtureText $path '{"owned":"existing"}'
        $before = Get-STEFixtureHash ([IO.File]::ReadAllBytes($path))
        $emitted = @(Save-SwiftTestEvidenceShard $session $recorder 19)
        Assert-STEFixture ($emitted.Count -eq 0) 'result-error-no-output'
        Assert-STEFixture ($session.Problems.Contains('shard-result-write-failed')) 'result-error-recorded'
        Assert-STEFixture ($session.Results.Count -eq 0) 'result-error-not-in-memory-success'
        Assert-STEFixtureEqual (Get-STEFixtureHash ([IO.File]::ReadAllBytes($path))) $before 'result-existing-unchanged'
        Complete-SwiftTestEvidenceSession $session 19
        $summary = Read-STEFixtureSummary $session
        Assert-STEFixture (-not $summary.evidenceCompleteForDeclaredScope -and $null -eq $summary.completeCounts) 'result-error-incomplete'
        Assert-STEFixture ($summary.testScriptExitCode -eq 19) 'result-error-exit-preserved'
    }
    Invoke-STEFixture 'session-summary-write-failure-preserves-existing' 3 {
        $session = New-STEFixtureSession
        Save-STEFixturePassingShard $session 1
        $path = Join-Path $session.Directory 'summary.json'
        Write-STEFixtureText $path '{"owned":"existing"}'
        $before = Get-STEFixtureHash ([IO.File]::ReadAllBytes($path))
        $emitted = @(Complete-SwiftTestEvidenceSession $session 23)
        Assert-STEFixture ($emitted.Count -eq 0) 'summary-error-no-output'
        Assert-STEFixture ($session.Problems.Contains('summary-write-failed')) 'summary-error-recorded'
        Assert-STEFixtureEqual (Get-STEFixtureHash ([IO.File]::ReadAllBytes($path))) $before 'summary-existing-unchanged'
    }
    Invoke-STEFixture 'session-finalization-never-overwrites' 3 {
        $session = New-STEFixtureSession
        Save-STEFixturePassingShard $session 1
        Complete-SwiftTestEvidenceSession $session 22
        $path = Join-Path $session.Directory 'summary.json'
        $before = Get-STEFixtureHash ([IO.File]::ReadAllBytes($path))
        Complete-SwiftTestEvidenceSession $session 0
        Assert-STEFixture ($session.Problems.Contains('summary-write-failed')) 'double-finalize-recorded'
        Assert-STEFixtureEqual (Get-STEFixtureHash ([IO.File]::ReadAllBytes($path))) $before 'double-finalize-unchanged'
        Assert-STEFixture ((Read-STEFixtureSummary $session).testScriptExitCode -eq 22) 'first-exit-retained'
    }
    Invoke-STEFixture 'session-case-observation-limit' 3 {
        $session = New-STEFixtureSession
        $session.Limits.maxCaseObservations = 0
        Save-STEFixturePassingShard $session 1
        Assert-STEFixture ($session.Problems.Contains('shard-result-write-failed')) 'session-case-limit-recorded'
        Assert-STEFixture ($session.Results.Count -eq 0) 'session-case-limit-no-result'
        Assert-STEFixture (-not [IO.File]::Exists((Join-Path $session.Directory 'shard-0001-result.json'))) 'session-case-limit-no-file'
    }
    Invoke-STEFixture 'session-start-byte-limit' 4 {
        $session = New-STEFixtureSession
        $before = $session.BytesWritten
        $session.Limits.maxSessionBytes = 65536
        $null = Start-SwiftTestEvidenceShard $session 1
        Assert-STEFixture ($session.Problems.Contains('shard-start-write-failed')) 'session-start-byte-limit-recorded'
        Assert-STEFixture ($session.WrittenStartIndices.Count -eq 0) 'session-start-byte-limit-no-start'
        Assert-STEFixture (-not [IO.File]::Exists((Join-Path $session.Directory 'shard-0001-start.json'))) 'session-start-byte-limit-no-file'
        Assert-STEFixture ($session.BytesWritten -eq $before) 'session-start-byte-limit-no-charge'
    }
    Invoke-STEFixture 'session-result-byte-limit' 4 {
        $session = New-STEFixtureSession
        $recorder = Start-SwiftTestEvidenceShard $session 1
        Add-STEFixtureTrace $recorder @(New-STEFixtureTrace)
        Assert-STEFixture ($session.WrittenStartIndices.Contains(1) -and $session.Problems.Count -eq 0) 'result-limit-start-succeeded'
        $session.Limits.maxSessionBytes = $session.BytesWritten + 65536
        Save-SwiftTestEvidenceShard $session $recorder 0
        Assert-STEFixture ($session.Problems.Contains('shard-result-write-failed')) 'session-byte-limit-recorded'
        Assert-STEFixture ($session.Results.Count -eq 0) 'session-byte-limit-no-result'
        Assert-STEFixture (-not [IO.File]::Exists((Join-Path $session.Directory 'shard-0001-result.json'))) 'session-byte-limit-no-file'
    }
    Invoke-STEFixture 'session-plan-shard-limit-before-directory' 3 {
        $shard = [pscustomobject]@{ Targets = @([pscustomobject]@{ Name = 'FixtureTests' }); Filter = 'FixtureTests' }
        $relative = New-STEFixtureRelative
        Assert-STEFixtureRejected { New-SwiftTestEvidenceSession $script:steFixtureWorkspace $relative (@($shard) * 513) 1 } 'test-evidence-plan-limit'
        Assert-STEFixture (-not [IO.Directory]::Exists((Join-Path $script:steFixtureWorkspace $relative))) 'oversized-plan-no-directory'
    }
    Invoke-STEFixture 'session-invalid-start-before-directory' 2 {
        $shard = [pscustomobject]@{ Targets = @([pscustomobject]@{ Name = 'FixtureTests' }); Filter = 'FixtureTests' }
        Assert-STEFixtureRejected { New-SwiftTestEvidenceSession $script:steFixtureWorkspace (New-STEFixtureRelative) @($shard) 0 } 'test-evidence-plan-limit'
    }
    Invoke-STEFixture 'session-unsafe-target-before-directory' 2 {
        $shard = [pscustomobject]@{ Targets = @([pscustomobject]@{ Name = 'unsafe target' }); Filter = 'FixtureTests' }
        Assert-STEFixtureRejected { New-SwiftTestEvidenceSession $script:steFixtureWorkspace (New-STEFixtureRelative) @($shard) 1 } 'test-evidence-target-invalid'
    }
    Invoke-STEFixture 'session-unsafe-filter-before-directory' 2 {
        $shard = [pscustomobject]@{ Targets = @([pscustomobject]@{ Name = 'FixtureTests' }); Filter = 'FixtureTests;payload' }
        Assert-STEFixtureRejected { New-SwiftTestEvidenceSession $script:steFixtureWorkspace (New-STEFixtureRelative) @($shard) 1 } 'test-evidence-filter-not-generated'
    }
    Invoke-STEFixture 'generated-method-and-multitarget-filter-forms' 2 {
        $forms = @(
            @{ names = @('FixtureTests'); filter = 'FixtureTests/(testOne|testTwo)' },
            @{ names = @('FixtureTests', 'OtherTests'); filter = '(^|[./])(FixtureTests|OtherTests)([./]|$)' }
        )
        foreach ($form in $forms) {
            $shard = [pscustomobject]@{
                Targets = @($form.names | ForEach-Object { [pscustomobject]@{ Name = $_ } })
                Filter = $form.filter
            }
            $session = New-SwiftTestEvidenceSession $script:steFixtureWorkspace (New-STEFixtureRelative) @($shard) 1
            $plan = Read-SwiftTestEvidencePlan $script:steFixtureWorkspace $session.Directory
            Assert-STEFixtureEqual $plan.shards[0].filter $form.filter 'generated-filter-roundtrip'
        }
    }
    Invoke-STEFixture 'path-like-journal-filter-refused' 3 {
        $shard = [pscustomobject]@{ Targets = @([pscustomobject]@{ Name = 'FixtureTests' }); Filter = 'FixtureTests/../../hidden' }
        $relative = New-STEFixtureRelative
        Assert-STEFixtureRejected { New-SwiftTestEvidenceSession $script:steFixtureWorkspace $relative @($shard) 1 } 'test-evidence-filter-not-generated'
        Assert-STEFixture (-not [IO.Directory]::Exists((Join-Path $script:steFixtureWorkspace $relative))) 'path-like-plan-no-directory'
    }
    Invoke-STEFixture 'bundle-complete-counts-and-check' 5 {
        $session = New-STEFixtureSession 2
        Save-STEFixturePassingShard $session 1
        Save-STEFixturePassingShard $session 2
        Complete-SwiftTestEvidenceSession $session 0
        $bundle = Read-SwiftTestEvidenceBundle $script:steFixtureWorkspace $session.Directory
        $checked = Test-SwiftTestEvidenceComplete $script:steFixtureWorkspace $session.Directory
        Assert-STEFixture ($bundle.Results.Count -eq 2 -and $bundle.Summary.evidenceCompleteForDeclaredScope) 'bundle-complete-scope'
        Assert-STEFixture ($bundle.Observed.started -eq 2 -and $bundle.Observed.distinctIds -eq 1 -and $bundle.Observed.repeatedExecutions -eq 1) 'bundle-recomputed-counts'
        Assert-STEFixtureEqual $checked.Observed $bundle.Observed 'complete-check-counts'
        Assert-STEFixture ($bundle.StartedWithoutResult -is [array] -and $bundle.StartedWithoutResult.Count -eq 0 -and $bundle.Summary.startedWithoutResultShardIndices -is [array]) 'bundle-empty-start-array'
        Assert-STEFixture ($bundle.Plan.metadata.compilerIdentity -ceq 'not-observed' -and $bundle.Plan.metadata.runtimeGitIdentity -ceq 'not-observed') 'bundle-no-identity-promotion'
    }
    Invoke-STEFixture 'bundle-orphan-and-cross-shard-repeat-stays-partial' 6 {
        $session = New-STEFixtureSession 2
        $recorder = Start-SwiftTestEvidenceShard $session 1
        $trace = @(New-STEFixtureTrace -Ids @('FixtureTests.testOne', 'FixtureTests.testOne') -Outcomes @('passed', 'passed'))
        $lines = @($trace[0..4]) + @("Test Case 'FixtureTests.testOrphan' passed (0.002 seconds)") + @($trace[5..($trace.Count - 1)])
        Add-STEFixtureTrace $recorder $lines
        Save-SwiftTestEvidenceShard $session $recorder 1
        Save-STEFixturePassingShard $session 2
        Complete-SwiftTestEvidenceSession $session 1
        $bundle = Read-SwiftTestEvidenceBundle $script:steFixtureWorkspace $session.Directory
        Assert-STEFixture ($bundle.Results.Count -eq 2 -and $bundle.Results[0].observed.repeatedExecutions -eq 1) 'partial-orphan-result-retained'
        Assert-STEFixture ($bundle.Observed.started -eq 3 -and $bundle.Observed.passed -eq 4 -and $bundle.Observed.distinctIds -eq 2) 'partial-global-observations'
        Assert-STEFixture ($bundle.Observed.repeatedExecutions -eq 2) 'partial-global-repeats'
        Assert-STEFixture (-not $bundle.Summary.evidenceCompleteForDeclaredScope -and $null -eq $bundle.Summary.completeCounts) 'partial-not-complete-counts'
        Assert-STEFixtureRejected { Test-SwiftTestEvidenceComplete $script:steFixtureWorkspace $session.Directory } 'test-evidence-incomplete'
    }
    Invoke-STEFixture 'publication-complete-fixed-files-and-content-pins' 8 {
        $session = New-STEFixtureSession
        Save-STEFixturePassingShard $session 1
        Complete-SwiftTestEvidenceSession $session 0
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'success'
        $publishedPath = Join-Path $session.Directory 'published'
        $saved = Read-SwiftTestEvidenceJson (Join-Path $publishedPath 'summary.json')
        $manifest = Read-SwiftTestEvidenceJson (Join-Path $publishedPath 'manifest.json') 65536
        $names = @([IO.Directory]::GetFileSystemEntries($publishedPath) | ForEach-Object { [IO.Path]::GetFileName($_) } | Sort-Object)
        $summaryBytes = Read-STEFixtureSource (Join-Path $publishedPath 'summary.json')
        $caseBytes = Read-STEFixtureSource (Join-Path $publishedPath 'cases.ndjson')
        $expectedPins = @(
            [pscustomobject][ordered]@{ path = 'summary.json'; status = 'observed'; bytes = $summaryBytes.Length; sha256 = Get-STEFixtureHash $summaryBytes },
            [pscustomobject][ordered]@{ path = 'cases.ndjson'; status = 'observed'; bytes = $caseBytes.Length; sha256 = Get-STEFixtureHash $caseBytes }
        )
        Assert-STEFixture ($saved.fullOutcome -ceq 'success' -and $saved.evidenceReadStatus -ceq 'validated-complete-journal') 'publication-complete-read-status'
        Assert-STEFixture ($saved.observed.started -eq 1 -and $saved.testSummary.evidenceCompleteForDeclaredScope) 'publication-complete-counts'
        Assert-STEFixture ($saved.startedWithoutResult -is [array] -and $saved.startedWithoutResult.Count -eq 0) 'publication-empty-start-array'
        Assert-STEFixtureEqual $names @('cases.ndjson', 'manifest.json', 'summary.json') 'publication-exact-files'
        Assert-STEFixture ($manifest.kind -ceq 'ci-corelogic-xctest-evidence-files' -and $manifest.fullOutcome -ceq 'success') 'publication-manifest-kind'
        Assert-STEFixtureEqual $manifest.files $expectedPins 'publication-independent-content-pins'
        Assert-STEFixtureEqual $saved $publication 'publication-disk-return-agree'
        Assert-STEFixture ($saved.cases.path -ceq 'cases.ndjson' -and $saved.cases.bytes -eq $caseBytes.Length -and $saved.cases.sha256 -ceq (Get-STEFixtureHash $caseBytes)) 'publication-cases-reference'
    }
    Invoke-STEFixture 'publication-durable-start-without-summary-is-partial' 8 {
        $session = New-STEFixtureSession 2
        $null = Start-SwiftTestEvidenceShard $session 1
        $bundle = Read-SwiftTestEvidenceBundle $script:steFixtureWorkspace $session.Directory
        Assert-STEFixture ($null -eq $bundle.Summary -and $bundle.StartedWithoutResult -is [array] -and $bundle.StartedWithoutResult.Count -eq 1) 'partial-start-without-summary'
        Assert-STEFixtureEqual $bundle.StartedWithoutResult @(1) 'partial-start-index'
        Assert-STEFixtureRejected { Test-SwiftTestEvidenceComplete $script:steFixtureWorkspace $session.Directory } 'test-evidence-incomplete'
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'failure'
        $saved = Read-SwiftTestEvidenceJson (Join-Path $session.Directory 'published/summary.json')
        Assert-STEFixture ($publication.evidenceReadStatus -ceq 'validated-partial-journal' -and $publication.fullOutcome -ceq 'failure') 'partial-publication-outcome'
        Assert-STEFixture ($saved.startedWithoutResult -is [array] -and $saved.startedWithoutResult.Count -eq 1 -and $saved.startedWithoutResult[0] -eq 1) 'partial-publication-singleton-array'
        Assert-STEFixture ($saved.shards[0].state -ceq 'started-without-result' -and $saved.shards[1].state -ceq 'no-durable-start') 'partial-publication-distinct-boundaries'
        Assert-STEFixture ($null -eq $saved.testSummary -and $saved.observed.started -eq 0 -and $saved.cases.bytes -eq 0) 'partial-zero-not-complete-summary'
    }
    Invoke-STEFixture 'later-full-failure-never-erases-test-counts' 4 {
        $session = New-STEFixtureSession
        Save-STEFixturePassingShard $session 1
        Complete-SwiftTestEvidenceSession $session 0
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'failure'
        $manifest = Read-SwiftTestEvidenceJson (Join-Path $session.Directory 'published/manifest.json') 65536
        Assert-STEFixture ($publication.fullOutcome -ceq 'failure' -and $manifest.fullOutcome -ceq 'failure') 'full-failure-retained'
        Assert-STEFixture ($publication.observed.passed -eq 1 -and $publication.testSummary.testScriptExitCode -eq 0 -and $publication.shards[0].result.wrapperExitCode -eq 0) 'successful-test-phase-retained'
        Assert-STEFixture ($publication.qualification -ceq 'counts-for-declared-scope-only; not-Full-success-or-font-qualification') 'full-failure-no-qualification'
        Assert-STEFixture ($publication.portable -ceq 'not-instrumented' -and $publication.swiftTesting -ceq 'counts-not-instrumented') 'full-failure-unobserved-phases'
    }
    Invoke-STEFixture 'failed-test-exit-never-passes-evidence-check' 4 {
        $session = New-STEFixtureSession
        $recorder = Start-SwiftTestEvidenceShard $session 1
        Add-STEFixtureTrace $recorder @(New-STEFixtureTrace -Outcomes @('failed'))
        Save-SwiftTestEvidenceShard $session $recorder 7
        Complete-SwiftTestEvidenceSession $session 7
        Assert-STEFixtureRejected { Test-SwiftTestEvidenceComplete $script:steFixtureWorkspace $session.Directory } 'test-evidence-incomplete'
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'failure'
        Assert-STEFixture ($publication.testSummary.testScriptExitCode -eq 7 -and $publication.shards[0].result.wrapperExitCode -eq 7 -and $publication.observed.failed -eq 1) 'failed-test-original-exits'
        Assert-STEFixture ($publication.fullOutcome -ceq 'failure' -and $publication.evidenceReadStatus -ceq 'validated-complete-journal') 'failed-test-exact-counts-not-success'
    }
    Invoke-STEFixture 'invalid-result-publishes-no-unknown-payload-or-counts' 6 {
        $session = New-STEFixtureSession
        $recorder = Start-SwiftTestEvidenceShard $session 1
        Add-STEFixtureTrace $recorder @(New-STEFixtureTrace)
        $result = Complete-SwiftTestEvidenceRecorder $recorder 0
        $marker = 'DO_NOT_PUBLISH_SYNTHETIC_PAYLOAD'
        $result | Add-Member -NotePropertyName rawPayload -NotePropertyValue $marker
        $rawPath = Join-Path $session.Directory 'shard-0001-result.json'
        $null = Write-SwiftTestEvidenceJsonNew $rawPath $result
        $before = Get-STEFixtureHash (Read-STEFixtureSource $rawPath)
        $null = Read-SwiftTestEvidencePlan $script:steFixtureWorkspace $session.Directory
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'failure'
        $publishedPath = Join-Path $session.Directory 'published'
        $text = $script:steFixtureUtf8.GetString((Read-STEFixtureSource (Join-Path $publishedPath 'summary.json')))
        $quotedWorkspace = ConvertTo-Json -InputObject $script:steFixtureWorkspace -Compress
        $escapedWorkspace = $quotedWorkspace.Substring(1, $quotedWorkspace.Length - 2)
        $names = @([IO.Directory]::GetFileSystemEntries($publishedPath) | ForEach-Object { [IO.Path]::GetFileName($_) } | Sort-Object)
        Assert-STEFixture ($publication.evidenceReadStatus -ceq 'invalid-or-incomplete-journal' -and $publication.fullOutcome -ceq 'failure') 'invalid-result-status'
        Assert-STEFixture ($null -eq $publication.observed -and $null -eq $publication.testSummary -and $publication.shards -is [array] -and $publication.shards.Count -eq 1 -and $publication.shards[0].state -ceq 'journal-unreadable' -and $null -eq $publication.shards[0].result) 'invalid-result-counts-null'
        Assert-STEFixture ($publication.startedWithoutResult -is [array] -and $publication.startedWithoutResult.Count -eq 0 -and $publication.cases.bytes -eq 0) 'invalid-result-no-case-records'
        Assert-STEFixture (-not $text.Contains($marker) -and -not $text.Contains($script:steFixtureWorkspace) -and -not $text.Contains($escapedWorkspace) -and -not $text.Contains($script:steFixtureWorkspace.Replace('\', '/'))) 'invalid-result-no-private-projection'
        Assert-STEFixtureEqual (Get-STEFixtureHash (Read-STEFixtureSource $rawPath)) $before 'invalid-raw-result-preserved'
        Assert-STEFixtureEqual $names @('cases.ndjson', 'manifest.json', 'summary.json') 'invalid-result-fixed-publication'
    }
    Invoke-STEFixture 'publication-refuses-plan-from-another-workspace' 3 {
        $seed = New-STEFixtureSession
        $plan = Read-SwiftTestEvidenceJson (Join-Path $seed.Directory 'plan.json')
        $plan.metadata.workspaceId = '0' * 64
        $directory = New-SwiftTestEvidenceDirectory $script:steFixtureWorkspace (New-STEFixtureRelative)
        $null = Write-SwiftTestEvidenceJsonNew (Join-Path $directory 'plan.json') $plan
        Assert-STEFixtureRejected { Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $directory 'failure' } 'test-evidence-workspace-mismatch'
        Assert-STEFixture (-not [IO.Directory]::Exists((Join-Path $directory 'published'))) 'unowned-plan-no-publication'
    }
    Invoke-STEFixture 'publication-refuses-existing-directory-without-plan' 2 {
        $directory = New-SwiftTestEvidenceDirectory $script:steFixtureWorkspace (New-STEFixtureRelative)
        $rejected = $false
        try { $null = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $directory 'failure' } catch { $rejected = $true }
        Assert-STEFixture $rejected 'missing-plan-rejected'
        Assert-STEFixture (-not [IO.Directory]::Exists((Join-Path $directory 'published'))) 'missing-plan-no-publication'
    }
    Invoke-STEFixture 'publication-never-overwrites-existing-publication' 4 {
        $session = New-STEFixtureSession
        Save-STEFixturePassingShard $session 1
        Complete-SwiftTestEvidenceSession $session 0
        $null = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'failure'
        $path = Join-Path $session.Directory 'published/manifest.json'
        $before = Get-STEFixtureHash (Read-STEFixtureSource $path)
        Assert-STEFixtureRejected { Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'success' } 'test-evidence-publication-exists'
        Assert-STEFixtureEqual (Get-STEFixtureHash (Read-STEFixtureSource $path)) $before 'existing-publication-unchanged'
        Assert-STEFixture ((Read-SwiftTestEvidenceJson $path).fullOutcome -ceq 'failure') 'existing-failure-not-replaced'
    }
    Invoke-STEFixture 'unexpected-journal-member-never-published' 4 {
        $session = New-STEFixtureSession
        $rawPath = Join-Path $session.Directory 'private-fixture.txt'
        $marker = 'DO_NOT_PUBLISH_UNKNOWN_MEMBER'
        Write-STEFixtureText $rawPath $marker
        $before = Get-STEFixtureHash (Read-STEFixtureSource $rawPath)
        Assert-STEFixtureRejected { Read-SwiftTestEvidenceBundle $script:steFixtureWorkspace $session.Directory } 'test-evidence-unexpected-member'
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'failure'
        $text = $script:steFixtureUtf8.GetString((Read-STEFixtureSource (Join-Path $session.Directory 'published/summary.json')))
        Assert-STEFixture ($publication.evidenceReadStatus -ceq 'invalid-or-incomplete-journal' -and $publication.cases.bytes -eq 0 -and -not $text.Contains($marker)) 'unknown-member-not-copied'
        Assert-STEFixtureEqual (Get-STEFixtureHash (Read-STEFixtureSource $rawPath)) $before 'unknown-member-preserved'
    }
    Invoke-STEFixture 'unreached-test-phase-publishes-unknown-counts' 3 {
        $directory = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $directory 'failure'
        Assert-STEFixture ($publication.evidenceReadStatus -ceq 'test-phase-not-reached' -and $publication.fullOutcome -ceq 'failure') 'unreached-phase-status'
        Assert-STEFixture ($null -eq $publication.observed -and $null -eq $publication.testSummary -and $publication.cases.bytes -eq 0) 'unreached-counts-unknown'
        Assert-STEFixture ($publication.startedWithoutResult -is [array] -and $publication.startedWithoutResult.Count -eq 0 -and $publication.shards -is [array] -and $publication.shards.Count -eq 0) 'unreached-arrays-retained'
    }
    $invalidResults = @(
        @{ id = 'bundle-rejects-array-exit-claim'; mutate = { param($value) $value.exitObservation = @($value.exitObservation) } },
        @{ id = 'bundle-rejects-unreported-nonstring-output'; mutate = { param($value) $value.output.nonStringObjects = 1 } },
        @{ id = 'bundle-rejects-impossible-zero-output'; mutate = { param($value) $value.output.objects = 0 } },
        @{ id = 'bundle-rejects-control-character-identifier'; mutate = { param($value) $value.cases[0].caseId += [char]10 } }
    )
    foreach ($invalidResult in $invalidResults) {
        Invoke-STEFixture $invalidResult.id 2 {
            $session = New-STEFixtureSession
            $recorder = Start-SwiftTestEvidenceShard $session 1
            Add-STEFixtureTrace $recorder @(New-STEFixtureTrace)
            $value = Complete-SwiftTestEvidenceRecorder $recorder 0
            $null = Assert-SwiftTestEvidenceResult $value
            $null = Read-SwiftTestEvidencePlan $script:steFixtureWorkspace $session.Directory
            & $invalidResult.mutate $value
            $null = Write-SwiftTestEvidenceJsonNew (Join-Path $session.Directory 'shard-0001-result.json') $value
            Assert-STEFixtureRejected { Read-SwiftTestEvidenceBundle $script:steFixtureWorkspace $session.Directory } -Schema
        }
    }
    Invoke-STEFixture 'invocation-default-and-optin-preserve-argv-and-objects' 8 {
        $original = [pscustomobject]@{ marker = 'synthetic-nonstring-object' }
        $objects = @(New-STEFixtureTrace) + @($original)
        $default = Invoke-STEFixtureBoundary -Objects $objects -Filters @('FixtureTests', '', 'OtherTests')
        $enabled = Invoke-STEFixtureBoundary -Evidence -Objects $objects -Filters @('FixtureTests', '', 'OtherTests')
        $expected = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            (Join-Path $script:steFixtureWorkspace 'scripts/with-swift.ps1'),
            'swift', 'test', '--package-path', $script:steFixtureWorkspace,
            '--filter', 'FixtureTests', '--filter', 'OtherTests')
        Assert-STEFixture ($default.Invocations.Count -eq 1 -and $enabled.Invocations.Count -eq 1) 'boundary-one-mocked-call-each'
        Assert-STEFixtureEqual $default.Invocations[0] $expected 'boundary-default-exact-argv'
        Assert-STEFixtureEqual $enabled.Invocations[0] $default.Invocations[0] 'boundary-optin-same-argv'
        Assert-STEFixture ($default.ReturnCode -eq 0 -and $enabled.ReturnCode -eq 0 -and $null -eq $default.Session) 'boundary-original-return-values'
        Assert-STEFixture ($default.Forwarded.Count -eq $objects.Count -and $enabled.Forwarded.Count -eq $objects.Count) 'boundary-forward-counts'
        Assert-STEFixture ([object]::ReferenceEquals($default.Forwarded[$default.Forwarded.Count - 1], $original)) 'boundary-default-object-identity'
        Assert-STEFixture ([object]::ReferenceEquals($enabled.Forwarded[$enabled.Forwarded.Count - 1], $original)) 'boundary-optin-object-identity'
        Assert-STEFixtureIncomplete $enabled.Session.Results[0] 'non-string-output'
    }
    Invoke-STEFixture 'invocation-optin-normal-journal' 4 {
        $trace = @(New-STEFixtureTrace)
        $boundary = Invoke-STEFixtureBoundary -Evidence -Objects $trace
        Assert-STEFixture ($boundary.Invocations.Count -eq 1 -and $boundary.ReturnCode -eq 0) 'boundary-normal-mocked-success'
        Assert-STEFixture ($boundary.ReportedExitCode -eq 0 -and $boundary.Session.Results.Count -eq 1) 'boundary-normal-exit-and-result'
        Assert-STEFixture ($boundary.Session.Results[0].complete -and $boundary.Session.Results[0].observed.passed -eq 1) 'boundary-normal-complete-shard'
        Assert-STEFixture ($boundary.Forwarded.Count -eq $trace.Count) 'boundary-normal-forwarded-all'
    }
    Invoke-STEFixture 'invocation-observer-throw-retains-object-and-exit' 5 {
        $original = [pscustomobject]@{ marker = 'synthetic-observer-throw' }
        $boundary = Invoke-STEFixtureBoundary -Evidence -Objects @($original) -WrapperExit 17 -Fault observer
        Assert-STEFixture ($boundary.Invocations.Count -eq 1 -and $boundary.ReturnCode -eq 17 -and $boundary.ReportedExitCode -eq 17) 'observer-throw-original-exit'
        Assert-STEFixture ($boundary.Forwarded.Count -eq 1 -and [object]::ReferenceEquals($boundary.Forwarded[0], $original)) 'observer-throw-original-object'
        Assert-STEFixture ($boundary.Session.Results.Count -eq 1) 'observer-throw-result-recorded'
        Assert-STEFixtureIncomplete $boundary.Session.Results[0] 'observer-call-failed'
        Assert-STEFixture ($boundary.Session.Results[0].wrapperExitCode -eq 17) 'observer-throw-stored-exit'
    }
    Invoke-STEFixture 'invocation-writer-throw-retains-forwarding-and-exit' 5 {
        $trace = @(New-STEFixtureTrace)
        $boundary = Invoke-STEFixtureBoundary -Evidence -Objects $trace -WrapperExit 23 -Fault writer
        Assert-STEFixture ($boundary.Invocations.Count -eq 1 -and $boundary.ReturnCode -eq 23 -and $boundary.ReportedExitCode -eq 23) 'writer-throw-original-exit'
        Assert-STEFixture ($boundary.Forwarded.Count -eq $trace.Count) 'writer-throw-all-forwarded'
        Assert-STEFixture ($boundary.Session.Problems.Contains('observer-call-failed')) 'writer-throw-problem-recorded'
        Assert-STEFixture ($boundary.Session.Results.Count -eq 0) 'writer-throw-no-successful-result'
        Assert-STEFixture (-not [IO.File]::Exists((Join-Path $boundary.Session.Directory 'shard-0001-result.json'))) 'writer-throw-no-result-file'
    }
    Invoke-STEFixture 'invocation-start-throw-keeps-original-command' 4 {
        $original = [pscustomobject]@{ marker = 'synthetic-start-throw' }
        $boundary = Invoke-STEFixtureBoundary -Evidence -Objects @($original) -WrapperExit 19 -Fault start
        Assert-STEFixture ($boundary.Invocations.Count -eq 1 -and $boundary.ReturnCode -eq 19) 'start-throw-original-command'
        Assert-STEFixture ($boundary.Forwarded.Count -eq 1 -and [object]::ReferenceEquals($boundary.Forwarded[0], $original)) 'start-throw-original-object'
        Assert-STEFixture ($boundary.Session.Problems.Contains('observer-call-failed')) 'start-throw-problem-recorded'
        Assert-STEFixture ($boundary.Session.WrittenStartIndices.Count -eq 0 -and $boundary.Session.Results.Count -eq 0) 'start-throw-no-durable-evidence'
    }
    Invoke-STEFixture 'invocation-null-exit-keeps-original-failure-return' 4 {
        $trace = @(New-STEFixtureTrace)
        $boundary = Invoke-STEFixtureBoundary -Evidence -Objects $trace -WrapperExit $null
        Assert-STEFixture ($boundary.Invocations.Count -eq 1 -and $boundary.ReturnCode -eq 1 -and $null -eq $boundary.ReportedExitCode) 'null-exit-original-failure-return'
        Assert-STEFixture ($boundary.Session.Results.Count -eq 1 -and $null -eq $boundary.Session.Results[0].wrapperExitCode) 'null-exit-not-invented'
        Assert-STEFixtureIncomplete $boundary.Session.Results[0] 'wrapper-exit-unavailable'
        Assert-STEFixture ($boundary.Forwarded.Count -eq $trace.Count) 'null-exit-forwarding'
    }
    Invoke-STEFixture 'invocation-nonzero-test-exit-keeps-failed-case' 4 {
        $trace = @(New-STEFixtureTrace -Outcomes @('failed'))
        $boundary = Invoke-STEFixtureBoundary -Evidence -Objects $trace -WrapperExit 7
        Assert-STEFixture ($boundary.ReturnCode -eq 7 -and $boundary.ReportedExitCode -eq 7) 'boundary-nonzero-exit-retained'
        Assert-STEFixture ($boundary.Session.Results.Count -eq 1 -and $boundary.Session.Results[0].complete) 'boundary-failed-output-complete'
        Assert-STEFixture ($boundary.Session.Results[0].observed.failed -eq 1 -and $boundary.Session.Results[0].wrapperExitCode -eq 7) 'boundary-failed-case-not-rewritten'
        Assert-STEFixture ($boundary.Invocations.Count -eq 1 -and $boundary.Forwarded.Count -eq $trace.Count) 'boundary-failed-call-and-forwarding'
    }
    Invoke-STEFixture 'local-path-guard-accepts-authored-definition' 2 {
        $guardResult = Invoke-STEFixtureGuardRegression
        Assert-STEFixture $guardResult.Accepted 'local-guard-accepts-exact-definition'
        Assert-STEFixture (-not $guardResult.TailReached) 'local-guard-accepted-tail-not-reached'
    }
    Invoke-STEFixture 'local-path-guard-rejects-changed-first-guard' 2 {
        $guardResult = Invoke-STEFixtureGuardRegression -ChangedInitialGuard
        Assert-STEFixture $guardResult.RejectedChangedGuard 'local-guard-rejects-changed-prologue'
        Assert-STEFixture (-not $guardResult.TailReached) 'local-guard-rejected-tail-not-reached'
    }
    $transportValues = [Collections.Generic.List[object]]::new()
    [void]$transportValues.Add('authored-string')
    [void]$transportValues.Add('')
    [void]$transportValues.Add([pscustomobject]@{ marker = 'authored-object' })
    [void]$transportValues.Add([object[]]@('authored-element', [pscustomobject]@{ marker = 'authored-element-object' }))
    $transportCases = @(
        @{ id = 'transport-nonempty-string-current-mock'; value = 0; route = 'current-mock' },
        @{ id = 'transport-nonempty-string-direct'; value = 0; route = 'direct' },
        @{ id = 'transport-nonempty-string-direct-tee'; value = 0; route = 'direct-tee' },
        @{ id = 'transport-nonempty-string-direct-tee-observer-throws'; value = 0; route = 'direct-tee-observer-throws' },
        @{ id = 'transport-empty-string-current-mock'; value = 1; route = 'current-mock' },
        @{ id = 'transport-empty-string-direct'; value = 1; route = 'direct' },
        @{ id = 'transport-empty-string-direct-tee'; value = 1; route = 'direct-tee' },
        @{ id = 'transport-empty-string-direct-tee-observer-throws'; value = 1; route = 'direct-tee-observer-throws' },
        @{ id = 'transport-authored-object-current-mock'; value = 2; route = 'current-mock' },
        @{ id = 'transport-authored-object-direct'; value = 2; route = 'direct' },
        @{ id = 'transport-authored-object-direct-tee'; value = 2; route = 'direct-tee' },
        @{ id = 'transport-authored-object-direct-tee-observer-throws'; value = 2; route = 'direct-tee-observer-throws' },
        @{ id = 'transport-authored-array-current-mock'; value = 3; route = 'current-mock' },
        @{ id = 'transport-authored-array-direct'; value = 3; route = 'direct' },
        @{ id = 'transport-authored-array-direct-tee'; value = 3; route = 'direct-tee' },
        @{ id = 'transport-authored-array-direct-tee-observer-throws'; value = 3; route = 'direct-tee-observer-throws' }
    )
    foreach ($transportCase in $transportCases) {
        Invoke-STEFixture $transportCase.id 6 {
            $expectedPayload = $transportValues[$transportCase.value]
            $transport = Invoke-STEFixtureTransport -Payload $expectedPayload -RouteId $transportCase.route
            Assert-STEFixture ($transport.Forwarded.Count -eq 1) 'transport-one-collected-object'
            Assert-STEFixture ([object]::ReferenceEquals($transport.Forwarded[0], $expectedPayload)) 'transport-original-object-reference'
            Assert-STEFixture ($transport.Forwarded[0].GetType() -eq $expectedPayload.GetType()) 'transport-original-object-type'
            $expectedMockCount = if ($transportCase.route -ceq 'current-mock') { 1 } else { 0 }
            Assert-STEFixture ($transport.MockInvocationCount -eq $expectedMockCount) 'transport-exact-mock-count'
            $expectedObserverCount = if ($transportCase.route -cin @('direct-tee', 'direct-tee-observer-throws')) { 1 } else { 0 }
            Assert-STEFixture ($transport.Observed.Count -eq $expectedObserverCount -and
                ($expectedObserverCount -eq 0 -or [object]::ReferenceEquals($transport.Observed[0], $expectedPayload))) 'transport-observer-count-and-reference'
            $expectedProblemCount = if ($transportCase.route -ceq 'direct-tee-observer-throws') { 1 } else { 0 }
            Assert-STEFixture ($transport.ProblemCodes.Count -eq $expectedProblemCount -and
                ($expectedProblemCount -eq 0 -or $transport.ProblemCodes[0] -ceq 'observer-call-failed')) 'transport-exact-problem-sequence'
        }
    }
    Invoke-STEFixture 'local-writer-guard-rejects-altered-enumeration' 2 {
        # Parse the actual saved source, then alter only the selected writer's
        # boolean argument. Neither original nor altered source is registered here.
        $writerSource = $script:steFixtureUtf8.GetString($script:steFixtureSourceBytes['scripts/test.ps1'])
        $writerTokens = $null
        $writerErrors = $null
        $writerSourceAst = [Management.Automation.Language.Parser]::ParseInput($writerSource, [ref]$writerTokens, [ref]$writerErrors)
        if (@($writerErrors).Count -ne 0) { throw 'fixture-writer-negative-source-parse' }
        $writerContainers = @($writerSourceAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-SwiftTest'
        }, $true))
        if ($writerContainers.Count -ne 1) { throw 'fixture-writer-negative-container-count' }
        $writerAdmission = Get-STEFixtureForwardingAdmission $writerContainers[0]
        $writerCalls = @($writerAdmission.AllowedUnnamedWriter.FindAll({
            param($node)
            $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
                -not $node.Static -and $node.Member -is [Management.Automation.Language.StringConstantExpressionAst] -and
                $node.Member.Value -ceq 'WriteObject'
        }, $true))
        if ($writerCalls.Count -ne 1 -or $writerCalls[0].Arguments.Count -ne 2 -or
            $writerCalls[0].Expression.Extent.Text -cne '$PSCmdlet' -or
            $writerCalls[0].Arguments[1].Extent.Text -cne '$false') {
            throw 'fixture-writer-negative-argument-changed'
        }
        $writerArgument = $writerCalls[0].Arguments[1].Extent
        if ($writerSource.Substring($writerArgument.StartOffset, $writerArgument.EndOffset - $writerArgument.StartOffset) -cne '$false') {
            throw 'fixture-writer-negative-source-offset'
        }
        $alteredWriterSource = $writerSource.Substring(0, $writerArgument.StartOffset) + '$true' +
            $writerSource.Substring($writerArgument.EndOffset)
        $alteredWriterTokens = $null
        $alteredWriterErrors = $null
        $alteredWriterAst = [Management.Automation.Language.Parser]::ParseInput(
            $alteredWriterSource, [ref]$alteredWriterTokens, [ref]$alteredWriterErrors)
        if (@($alteredWriterErrors).Count -ne 0) { throw 'fixture-writer-negative-altered-parse' }
        $alteredWriterContainers = @($alteredWriterAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-SwiftTest'
        }, $true))
        if ($alteredWriterContainers.Count -ne 1) { throw 'fixture-writer-negative-altered-container-count' }
        $writerContinuation = [pscustomobject]@{ Reached = $false }
        $alteredWriterRejected = $false
        try {
            $null = Get-STEFixtureForwardingAdmission $alteredWriterContainers[0]
            # This marker records only post-admission continuation. Even an
            # unexpected acceptance never creates or runs the altered body.
            $writerContinuation.Reached = $true
        } catch {
            $alteredWriterRejected = $_.Exception.Message -ceq 'fixture-test-local-writer-changed'
        }
        Assert-STEFixture $alteredWriterRejected 'local-writer-changed-enumeration-rejected'
        Assert-STEFixture (-not $writerContinuation.Reached) 'local-writer-post-admission-unreached'
    }
    # Current-request regressions use actual journal/request/publication helpers.
    # "Full" ordering assertions are explicitly admitted AST/control-flow facts;
    # no whole agent-check, CLI publisher, native process or workflow is run.
    Invoke-STEFixture 'full-existing-complete-directory-new-request-refusal' 7 {
        $oldSession = New-STEFixtureRequestSession -RequestId ('1' * 32)
        Save-STEFixturePassingShard $oldSession 1
        Complete-SwiftTestEvidenceSession $oldSession 0
        $offline = Test-SwiftTestEvidenceComplete $script:steFixtureWorkspace $oldSession.Directory
        $before = Get-STEFixtureOwnedInventory $oldSession.Directory
        $requestAttempt = Invoke-STEFixtureRequest
        $request = $requestAttempt.Request
        $newSession = $null
        $setupFailure = Get-STEFixtureRequestFailure {
            $newSession = New-STEFixtureRequestSession -RequestId $request.SessionId -RequestDirectory $oldSession.Directory
        }
        $objects = @(New-STEFixtureTrace)
        $boundary = Invoke-STEFixtureRequestBoundary -RequestSession $newSession -Objects $objects
        $gateFailure = Get-STEFixtureRequestFailure {
            Test-SwiftTestEvidenceCurrentInvocation $script:steFixtureWorkspace $oldSession.Directory $request.ExpectedSessionId
        }
        Assert-STEFixture ($offline.Plan.metadata.sourceFiles.Count -eq 5 -and $offline.Summary.evidenceCompleteForDeclaredScope -and $offline.Plan.sessionId -ceq ('1' * 32)) 'old-journal-offline-complete-with-current-pins'
        Assert-STEFixture ($request.Ready -and $request.SessionId -ceq ('2' * 32) -and $request.ExpectedSessionId -ceq $request.SessionId -and $request.SessionId -cne $oldSession.Plan.sessionId) 'fresh-caller-request-differs-from-old'
        Assert-STEFixture ($setupFailure.Failed -and $setupFailure.Code -ceq 'test-evidence-destination-exists' -and $null -eq $newSession) 'real-new-session-refuses-old-destination'
        Assert-STEFixture ($boundary.Invocations.Count -eq 1 -and (ConvertTo-Json -InputObject $boundary.Invocations[0] -Compress) -ceq (ConvertTo-Json -InputObject (Get-STEFixtureRequestArgv) -Compress)) 'stale-setup-original-mock-argv'
        Assert-STEFixture ($boundary.ReturnCode -eq 0 -and $boundary.ReportedExitCode -eq 0 -and (Test-STEFixtureRequestOutputIdentity $boundary $objects)) 'stale-setup-original-zero-and-objects'
        Assert-STEFixture ($gateFailure.Failed -and $gateFailure.Code -ceq 'test-evidence-current-request-journal-mismatch') 'fresh-gate-refuses-complete-old-journal'
        Assert-STEFixtureEqual (Get-STEFixtureOwnedInventory $oldSession.Directory) $before 'old-journal-members-and-bytes-unchanged'
    }
    Invoke-STEFixture 'full-current-request-complete-passes-separate-gate' 5 {
        $request = (Invoke-STEFixtureRequest).Request
        $session = New-STEFixtureRequestSession -RequestId $request.SessionId
        $objects = @(New-STEFixtureTrace -Ids @('FixtureTests.testCurrent'))
        $boundary = Invoke-STEFixtureRequestBoundary -RequestSession $session -Objects $objects
        Complete-SwiftTestEvidenceSession $session $boundary.ReturnCode
        $bundle = Test-SwiftTestEvidenceCurrentInvocation $script:steFixtureWorkspace $session.Directory $request.ExpectedSessionId
        Assert-STEFixture ($session.Plan.schemaVersion -eq 1 -and $session.Plan.sessionId -ceq $request.SessionId) 'caller-id-enters-existing-plan-field'
        Assert-STEFixture ($boundary.Invocations.Count -eq 1 -and (ConvertTo-Json -InputObject $boundary.Invocations[0] -Compress) -ceq (ConvertTo-Json -InputObject (Get-STEFixtureRequestArgv) -Compress)) 'current-request-original-mock-argv'
        Assert-STEFixture ($boundary.ReturnCode -eq 0 -and $boundary.ReportedExitCode -eq 0 -and (Test-STEFixtureRequestOutputIdentity $boundary $objects)) 'current-request-original-zero-and-objects'
        Assert-STEFixture ($bundle.Summary.evidenceCompleteForDeclaredScope -and $bundle.Plan.sessionId -ceq $request.ExpectedSessionId) 'matching-request-passes-real-current-check'
        Assert-STEFixture ($bundle.Observed.started -eq 1 -and $bundle.Observed.passed -eq 1 -and $bundle.Observed.distinctIds -eq 1 -and $bundle.Results[0].cases[0].caseId -ceq 'FixtureTests.testCurrent') 'matching-current-counts-and-identity'
    }
    Invoke-STEFixture 'full-setup-failure-keeps-test-exit-and-rejects-gate' 5 {
        $request = (Invoke-STEFixtureRequest -GenerationThrows).Request
        $directory = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
        $setupFailure = Get-STEFixtureRequestFailure {
            New-STEFixtureRequestSession -RequestId 'unavailable' -RequestDirectory $directory
        }
        $objects = @(New-STEFixtureTrace)
        $boundary = Invoke-STEFixtureRequestBoundary -RequestSession $null -Objects $objects
        $gateFailure = Get-STEFixtureRequestFailure {
            Test-SwiftTestEvidenceCurrentInvocation $script:steFixtureWorkspace $directory $request.ExpectedSessionId
        }
        Assert-STEFixture ($setupFailure.Code -ceq 'test-evidence-session-id-invalid' -and -not [IO.Directory]::Exists($directory) -and $null -eq $request.SessionId) 'failed-setup-has-no-fabricated-session'
        Assert-STEFixture ($boundary.Invocations.Count -eq 1) 'failed-setup-still-invokes-original-mock'
        Assert-STEFixture ((ConvertTo-Json -InputObject $boundary.Invocations[0] -Compress) -ceq (ConvertTo-Json -InputObject (Get-STEFixtureRequestArgv) -Compress) -and (Test-STEFixtureRequestOutputIdentity $boundary $objects)) 'failed-setup-argv-and-objects-preserved'
        Assert-STEFixture ($boundary.ReturnCode -eq 0 -and $boundary.ReportedExitCode -eq 0) 'failed-setup-keeps-original-zero'
        Assert-STEFixture ($gateFailure.Code -ceq 'test-evidence-expected-session-id-invalid') 'failed-setup-separate-current-gate-fails'
    }
    Invoke-STEFixture 'full-nonzero-test-exit-precedes-evidence-failure' 4 {
        $oldSession = New-STEFixtureRequestSession -RequestId ('1' * 32)
        Save-STEFixturePassingShard $oldSession 1
        Complete-SwiftTestEvidenceSession $oldSession 0
        $before = Get-STEFixtureOwnedInventory $oldSession.Directory
        $request = (Invoke-STEFixtureRequest -GenerationThrows).Request
        $setupFailure = Get-STEFixtureRequestFailure {
            New-STEFixtureRequestSession -RequestId 'unavailable' -RequestDirectory $oldSession.Directory
        }
        $boundary = Invoke-STEFixtureRequestBoundary -RequestSession $null -WrapperExit 23 -Objects @(New-STEFixtureTrace -Outcomes @('failed'))
        Assert-STEFixture ($boundary.ReturnCode -eq 23 -and $boundary.ReportedExitCode -eq 23) 'original-nonzero-exit-preserved'
        Assert-STEFixture ($script:steFixtureRequestWiring.Kind -ceq 'source-ast-contract-only' -and $script:steFixtureRequestWiring.OriginalNonzeroStopsBeforeCheck) 'actual-full-source-stops-before-check-on-nonzero'
        Assert-STEFixture (-not $request.Ready -and $setupFailure.Code -ceq 'test-evidence-session-id-invalid' -and $boundary.ReturnCode -eq 23) 'auxiliary-failure-never-replaces-test-exit'
        Assert-STEFixtureEqual (Get-STEFixtureOwnedInventory $oldSession.Directory) $before 'nonzero-path-preserves-old-journal'
    }
    Invoke-STEFixture 'full-unavailable-test-exit-does-not-reach-check' 3 {
        $oldSession = New-STEFixtureRequestSession -RequestId ('1' * 32)
        Save-STEFixturePassingShard $oldSession 1
        Complete-SwiftTestEvidenceSession $oldSession 0
        $before = Get-STEFixtureOwnedInventory $oldSession.Directory
        $boundary = Invoke-STEFixtureRequestBoundary -RequestSession $null -WrapperExit $null -Objects @([pscustomobject]@{ marker = 'authored-unavailable-exit' })
        Assert-STEFixture ($boundary.ReturnCode -eq 1 -and $null -eq $boundary.ReportedExitCode) 'unavailable-exit-retains-original-failure'
        Assert-STEFixture ($script:steFixtureRequestWiring.Kind -ceq 'source-ast-contract-only' -and $script:steFixtureRequestWiring.OriginalUnavailableExitStopsBeforeCheck) 'actual-full-source-stops-before-check-on-no-exit'
        Assert-STEFixtureEqual (Get-STEFixtureOwnedInventory $oldSession.Directory) $before 'unavailable-exit-does-not-promote-old-journal'
    }
    Invoke-STEFixture 'full-disabled-default-preserves-call-and-no-request' 4 {
        $resolved = Resolve-SwiftTestEvidenceRequest $true $false $null $null
        $control = New-STEFixtureRequestControl -Prefix $script:steFixtureUtf8.GetBytes('before=kept' + [char]10)
        $before = Get-STEFixtureHash (Read-STEFixtureOwnedBytes $control.Path)
        $directory = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
        $objects = @([pscustomobject]@{ marker = 'authored-off-output' })
        $boundary = Invoke-STEFixtureRequestBoundary -RequestSession $null -Objects $objects
        Assert-STEFixture ([string]::IsNullOrEmpty($resolved) -and $script:steFixtureRequestWiring.RequestOnlyInEnabledFull) 'disabled-full-source-does-not-generate-request'
        Assert-STEFixture ($boundary.Invocations.Count -eq 1 -and (ConvertTo-Json -InputObject $boundary.Invocations[0] -Compress) -ceq (ConvertTo-Json -InputObject (Get-STEFixtureRequestArgv) -Compress)) 'disabled-full-original-argv'
        Assert-STEFixture ($boundary.ReturnCode -eq 0 -and (Test-STEFixtureRequestOutputIdentity $boundary $objects)) 'disabled-full-original-output-and-exit'
        Assert-STEFixture (-not [IO.Directory]::Exists($directory) -and (Get-STEFixtureHash (Read-STEFixtureOwnedBytes $control.Path)) -ceq $before) 'disabled-full-no-request-output-or-evidence'
    }
    Invoke-STEFixture 'full-explicit-empty-beats-environment-and-no-request' 3 {
        $resolved = Resolve-SwiftTestEvidenceRequest $true $true '' 'artifacts/authored-environment-value'
        $objects = @([pscustomobject]@{ marker = 'authored-explicit-empty' })
        $boundary = Invoke-STEFixtureRequestBoundary -RequestSession $null -Objects $objects
        Assert-STEFixture ([string]::IsNullOrEmpty($resolved)) 'explicit-empty-still-beats-evidence-environment'
        Assert-STEFixture ($script:steFixtureRequestWiring.RequestOnlyInEnabledFull -and $script:steFixtureRequestWiring.Kind -ceq 'source-ast-contract-only') 'explicit-empty-source-has-no-request-or-bridge'
        Assert-STEFixture ($boundary.Invocations.Count -eq 1 -and $boundary.ReturnCode -eq 0 -and (Test-STEFixtureRequestOutputIdentity $boundary $objects) -and (ConvertTo-Json -InputObject $boundary.Invocations[0] -Compress) -ceq (ConvertTo-Json -InputObject (Get-STEFixtureRequestArgv) -Compress)) 'explicit-empty-original-off-call'
    }
    Invoke-STEFixture 'quick-environment-does-not-create-request' 3 {
        $resolved = Resolve-SwiftTestEvidenceRequest $false $false $null 'artifacts/authored-environment-value'
        $directory = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
        Assert-STEFixture ([string]::IsNullOrEmpty($resolved)) 'quick-still-ignores-evidence-environment'
        Assert-STEFixture ($script:steFixtureRequestWiring.RequestOnlyInEnabledFull -and -not [IO.Directory]::Exists($directory)) 'quick-source-has-no-request-bridge-or-evidence'
        Assert-STEFixture ($script:steFixtureRequestWiring.Kind -ceq 'source-ast-contract-only' -and $script:steFixtureRequestWiring.QuickSelectionUnchanged) 'quick-call-selection-exact-source-contract'
    }
    Invoke-STEFixture 'expected-session-missing-and-malformed-rejected' 4 {
        $directory = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
        $missing = Get-STEFixtureRequestFailure { Test-SwiftTestEvidenceCurrentInvocation $script:steFixtureWorkspace $directory }
        $nullExpected = Get-STEFixtureRequestFailure { Test-SwiftTestEvidenceCurrentInvocation $script:steFixtureWorkspace $directory -ExpectedSessionId $null }
        $uppercase = Get-STEFixtureRequestFailure { Test-SwiftTestEvidenceCurrentInvocation $script:steFixtureWorkspace $directory -ExpectedSessionId ('A' * 32) }
        $short = Get-STEFixtureRequestFailure { Test-SwiftTestEvidenceCurrentInvocation $script:steFixtureWorkspace $directory -ExpectedSessionId 'abc' }
        Assert-STEFixture ($missing.Code -ceq 'test-evidence-expected-session-id-invalid') 'missing-current-request-rejected'
        Assert-STEFixture ($nullExpected.Code -ceq 'test-evidence-expected-session-id-invalid') 'explicit-null-current-request-rejected'
        Assert-STEFixture ($uppercase.Code -ceq 'test-evidence-expected-session-id-invalid') 'uppercase-current-request-rejected'
        Assert-STEFixture ($short.Code -ceq 'test-evidence-expected-session-id-invalid' -and -not [IO.Directory]::Exists($directory)) 'short-current-request-rejected-before-output'
    }
    Invoke-STEFixture 'expected-session-valid-mismatch-rejected' 2 {
        $session = New-STEFixtureRequestSession -RequestId ('1' * 32)
        Save-STEFixturePassingShard $session 1
        Complete-SwiftTestEvidenceSession $session 0
        $offline = Test-SwiftTestEvidenceComplete $script:steFixtureWorkspace $session.Directory
        $failure = Get-STEFixtureRequestFailure { Test-SwiftTestEvidenceCurrentInvocation $script:steFixtureWorkspace $session.Directory ('2' * 32) }
        Assert-STEFixture ($offline.Summary.evidenceCompleteForDeclaredScope -and $offline.Plan.sessionId -ceq ('1' * 32)) 'mismatch-old-journal-remains-valid-offline'
        Assert-STEFixture ($failure.Code -ceq 'test-evidence-current-request-journal-mismatch') 'different-valid-caller-request-rejected'
    }
    Invoke-STEFixture 'publication-current-request-complete' 6 {
        $session = New-STEFixtureRequestSession -RequestId ('2' * 32)
        Save-STEFixturePassingShard $session 1 'FixtureTests.testCurrent'
        Complete-SwiftTestEvidenceSession $session 0
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'failure' -ExpectedSessionId $session.Plan.sessionId
        $saved = Read-SwiftTestEvidenceJson (Join-Path $session.Directory 'published/summary.json')
        $manifest = Read-SwiftTestEvidenceJson (Join-Path $session.Directory 'published/manifest.json')
        Assert-STEFixture ($publication.evidenceReadStatus -ceq 'validated-complete-journal' -and $publication.currentInvocation.journalSessionId -ceq $session.Plan.sessionId) 'bound-publication-adopts-matching-session-only'
        Assert-STEFixture (Test-STEFixtureRequestAssociation $publication.currentInvocation $session.Plan.sessionId $session.Plan.sessionId 'expected-id-match') 'bound-complete-association-limits-exact'
        Assert-STEFixture ($publication.observed.started -eq 1 -and $publication.observed.passed -eq 1 -and $publication.cases.bytes -gt 0 -and $publication.testSummary.evidenceCompleteForDeclaredScope) 'bound-complete-current-counts'
        Assert-STEFixture ($publication.fullOutcome -ceq 'failure' -and $publication.qualification -ceq 'counts-for-declared-scope-only; not-Full-success-or-font-qualification') 'bound-counts-never-promote-full-failure'
        Assert-STEFixture ($saved.schemaVersion -eq 2 -and $manifest.schemaVersion -eq 2 -and (Test-STEFixtureRequestAssociation $manifest.currentInvocation $session.Plan.sessionId $session.Plan.sessionId 'expected-id-match')) 'bound-summary-and-manifest-version-two'
        Assert-STEFixtureEqual $saved $publication 'bound-complete-return-and-disk-agree'
    }
    Invoke-STEFixture 'publication-current-request-partial' 5 {
        $session = New-STEFixtureRequestSession -RequestId ('2' * 32) -Count 3
        Save-STEFixturePassingShard $session 1
        $null = Start-SwiftTestEvidenceShard $session 2
        Complete-SwiftTestEvidenceSession $session 1
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'failure' -ExpectedSessionId $session.Plan.sessionId -RequireCurrentInvocation
        $saved = Read-SwiftTestEvidenceJson (Join-Path $session.Directory 'published/summary.json')
        Assert-STEFixture ($publication.evidenceReadStatus -ceq 'validated-partial-journal' -and (Test-STEFixtureRequestAssociation $publication.currentInvocation $session.Plan.sessionId $session.Plan.sessionId 'expected-id-match')) 'matching-current-partial-observations-adopted'
        Assert-STEFixture ($publication.observed.started -eq 1 -and -not $publication.testSummary.evidenceCompleteForDeclaredScope -and $null -eq $publication.testSummary.completeCounts) 'partial-counts-do-not-become-complete'
        Assert-STEFixture ($publication.startedWithoutResult.Count -eq 1 -and $publication.startedWithoutResult[0] -eq 2 -and $publication.testSummary.unstartedShardIndices.Count -eq 1 -and $publication.testSummary.unstartedShardIndices[0] -eq 3) 'partial-started-and-unstarted-boundaries-explicit'
        Assert-STEFixture ($publication.fullOutcome -ceq 'failure' -and $publication.schemaVersion -eq 2) 'partial-current-full-failure-preserved'
        Assert-STEFixtureEqual $saved $publication 'partial-current-return-and-disk-agree'
    }
    Invoke-STEFixture 'publication-request-absent-with-old-journal' 6 {
        $oldSession = New-STEFixtureRequestSession -RequestId ('1' * 32) -MetadataMarker 'fixture_old_image'
        Save-STEFixturePassingShard $oldSession 1
        Complete-SwiftTestEvidenceSession $oldSession 0
        $before = Get-STEFixtureOwnedInventory $oldSession.Directory -OmitPublished
        $publication = Invoke-STEFixtureMarkedPublication $oldSession -OmitExpected
        $saved = Read-SwiftTestEvidenceJson (Join-Path $oldSession.Directory 'published/summary.json')
        Assert-STEFixture ($publication.evidenceReadStatus -ceq 'current-test-invocation-not-observed') 'missing-request-status-does-not-claim-no-launch'
        Assert-STEFixture (Test-STEFixtureWithheldPublication $publication $oldSession.Directory) 'missing-request-withholds-old-counts-summary-and-shards'
        Assert-STEFixture ($publication.metadata.imageOS -ceq 'fixture_current_observer' -and $publication.metadata.imageOS -cne $oldSession.Plan.metadata.imageOS) 'missing-request-does-not-adopt-old-metadata'
        Assert-STEFixtureEqual (Get-STEFixtureOwnedInventory $oldSession.Directory -OmitPublished) $before 'missing-request-preserves-original-journal'
        Assert-STEFixture (Test-STEFixtureRequestAssociation $publication.currentInvocation $null $null 'current-test-invocation-not-observed') 'missing-request-is-not-filled-from-old-plan'
        Assert-STEFixtureEqual $saved $publication 'missing-request-return-and-saved-withholding-agree'
    }
    Invoke-STEFixture 'publication-request-mismatch-with-old-journal' 5 {
        $oldSession = New-STEFixtureRequestSession -RequestId ('1' * 32) -MetadataMarker 'fixture_old_image'
        Save-STEFixturePassingShard $oldSession 1
        Complete-SwiftTestEvidenceSession $oldSession 0
        $before = Get-STEFixtureOwnedInventory $oldSession.Directory -OmitPublished
        $publication = Invoke-STEFixtureMarkedPublication $oldSession ('2' * 32)
        Assert-STEFixture ($publication.evidenceReadStatus -ceq 'current-request-journal-mismatch' -and (Test-STEFixtureRequestAssociation $publication.currentInvocation ('2' * 32) $null 'current-request-journal-mismatch')) 'mismatched-request-status-and-withheld-journal-id'
        Assert-STEFixture ((Test-STEFixtureWithheldPublication $publication $oldSession.Directory) -and $publication.metadata.imageOS -ceq 'fixture_current_observer') 'mismatched-request-withholds-counts-and-old-metadata'
        Assert-STEFixtureEqual (Get-STEFixtureOwnedInventory $oldSession.Directory -OmitPublished) $before 'mismatched-request-preserves-old-journal'
        Assert-STEFixture ($publication.fullOutcome -ceq 'failure') 'mismatched-request-preserves-full-outcome'
        Assert-STEFixtureEqual (Read-SwiftTestEvidenceJson (Join-Path $oldSession.Directory 'published/summary.json')) $publication 'mismatched-request-saved-projection-agrees'
    }
    Invoke-STEFixture 'publication-request-not-observed-without-journal' 4 {
        $directory = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $directory 'failure' -RequireCurrentInvocation
        Assert-STEFixture ($publication.evidenceReadStatus -ceq 'current-test-invocation-not-observed') 'absent-request-absent-journal-status'
        Assert-STEFixture (Test-STEFixtureWithheldPublication $publication $directory) 'absent-request-counts-remain-null'
        Assert-STEFixture ((Test-STEFixtureRequestAssociation $publication.currentInvocation $null $null 'current-test-invocation-not-observed') -and $publication.fullOutcome -ceq 'failure' -and $publication.metadata.compilerIdentity -ceq 'not-observed') 'absent-request-no-generation-or-compiler-claim'
        Assert-STEFixture ($publication.schemaVersion -eq 2 -and (Read-SwiftTestEvidenceJson (Join-Path $directory 'published/manifest.json')).schemaVersion -eq 2) 'absent-request-publication-stays-bound-version-two'
    }
    Invoke-STEFixture 'request-output-bridge-bounded-and-failure-preserves-tests' 7 {
        $prefix = $script:steFixtureUtf8.GetBytes('before=kept' + [char]10)
        $control = New-STEFixtureRequestControl $prefix
        $successful = Invoke-STEFixtureRequest -GitHubActions $true -OutputPath $control.Path -RunnerTemp $control.Root
        $expectedLine = 'corelogic_evidence_request_id=' + ('2' * 32) + [char]10
        $written = Read-STEFixtureOwnedBytes $control.Path
        $oldControl = New-STEFixtureRequestControl $script:steFixtureUtf8.GetBytes('corelogic_evidence_request_id=' + ('1' * 32) + [char]10)
        $oldBefore = Get-STEFixtureHash (Read-STEFixtureOwnedBytes $oldControl.Path)
        $failed = Invoke-STEFixtureRequest -GitHubActions $true -OutputPath $oldControl.Path -RunnerTemp $oldControl.Root
        $session = New-STEFixtureRequestSession -RequestId $failed.Request.SessionId
        $objects = @(New-STEFixtureTrace)
        $boundary = Invoke-STEFixtureRequestBoundary -RequestSession $session -Objects $objects
        Complete-SwiftTestEvidenceSession $session $boundary.ReturnCode
        $gateFailure = Get-STEFixtureRequestFailure {
            Test-SwiftTestEvidenceCurrentInvocation $script:steFixtureWorkspace $session.Directory $failed.Request.ExpectedSessionId
        }
        Assert-STEFixture ($successful.Request.Ready -and $successful.Request.BridgeStatus -ceq 'written' -and $successful.Request.ExpectedSessionId -ceq ('2' * 32) -and $script:steFixtureUtf8.GetString($written) -ceq ('before=kept' + [char]10 + $expectedLine)) 'bridge-appends-exact-fixed-key-and-id'
        Assert-STEFixture ((Get-STEFixtureHash ([byte[]]$written[0..($prefix.Length - 1)])) -ceq (Get-STEFixtureHash $prefix)) 'bridge-preserves-existing-prefix-bytes'
        Assert-STEFixture (-not $failed.Request.Ready -and $failed.Request.SessionId -ceq ('2' * 32) -and $null -eq $failed.Request.ExpectedSessionId -and $failed.Request.Problems.Count -eq 1 -and $failed.Request.Problems[0] -ceq 'request-output-bridge-failed') 'duplicate-key-failure-retains-generated-request'
        Assert-STEFixture ($boundary.Invocations.Count -eq 1 -and (ConvertTo-Json -InputObject $boundary.Invocations[0] -Compress) -ceq (ConvertTo-Json -InputObject (Get-STEFixtureRequestArgv) -Compress)) 'bridge-failure-still-runs-original-mock'
        Assert-STEFixture ($boundary.ReturnCode -eq 0 -and $boundary.ReportedExitCode -eq 0 -and (Test-STEFixtureRequestOutputIdentity $boundary $objects)) 'bridge-failure-preserves-test-zero-and-objects'
        Assert-STEFixture ($gateFailure.Code -ceq 'test-evidence-expected-session-id-invalid' -and $script:steFixtureRequestWiring.CheckRequiresReadyCallerExpectation) 'bridge-not-ready-fails-separate-zero-exit-gate'
        Assert-STEFixture ((Get-STEFixtureHash (Read-STEFixtureOwnedBytes $oldControl.Path)) -ceq $oldBefore) 'duplicate-key-refusal-preserves-visible-old-id'
    }

    # Additional distinct controls pin strict types, bridge framing, byte caps,
    # publication refusal and the explicitly limited caller-ID association.
    $invalidSessionIds = @(
        @{ id = 'request-session-explicit-null-rejected'; value = $null },
        @{ id = 'request-session-explicit-empty-rejected'; value = '' },
        @{ id = 'request-session-uppercase-rejected'; value = ('A' * 32) },
        @{ id = 'request-session-short-rejected'; value = 'abc' },
        @{ id = 'request-session-array-rejected'; value = @('2' * 32) },
        @{ id = 'request-session-integer-rejected'; value = 2 },
        @{ id = 'request-session-whitespace-rejected'; value = ('2' * 32) + ' ' }
    )
    foreach ($invalidSessionId in $invalidSessionIds) {
        Invoke-STEFixture $invalidSessionId.id 2 {
            $directory = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
            $failure = Get-STEFixtureRequestFailure {
                New-STEFixtureRequestSession -RequestId $invalidSessionId.value -RequestDirectory $directory
            }
            Assert-STEFixture ($failure.Failed -and $failure.Code -ceq 'test-evidence-session-id-invalid') 'explicit-session-id-rejects-invalid-type-or-text'
            Assert-STEFixture (-not [IO.File]::Exists($directory) -and -not [IO.Directory]::Exists($directory)) 'invalid-explicit-session-id-before-directory'
        }
    }
    $invalidCurrentIds = @(
        @{ id = 'current-check-empty-rejected-before-bundle'; value = '' },
        @{ id = 'current-check-array-rejected-before-bundle'; value = @('2' * 32) },
        @{ id = 'current-check-integer-rejected-before-bundle'; value = 2 },
        @{ id = 'current-check-whitespace-rejected-before-bundle'; value = ' ' },
        @{ id = 'current-check-linebreak-rejected-before-bundle'; value = ('2' * 32) + [char]10 }
    )
    foreach ($invalidCurrentId in $invalidCurrentIds) {
        Invoke-STEFixture $invalidCurrentId.id 2 {
            $directory = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
            $checked = Invoke-STEFixtureSingleBundle -BundleOperation check -ExpectedId $invalidCurrentId.value -FirstBundle $null -LaterBundle $null -BundleDirectory $directory
            Assert-STEFixture ($checked.FailureCode -ceq 'test-evidence-expected-session-id-invalid') 'current-id-type-or-framing-is-strict'
            Assert-STEFixture ($checked.BundleReads -eq 0 -and $checked.DirectPlanReads -eq 0 -and -not [IO.Directory]::Exists($directory)) 'invalid-current-id-rejected-before-any-bundle'
        }
    }
    Invoke-STEFixture 'request-local-real-generator-has-unbound-origin-limits' 3 {
        $request = New-SwiftTestEvidenceRequest -GitHubActions $false -GitHubOutputPath $null -RunnerTemp $null
        Assert-STEFixture ($request.SessionId -is [string] -and $request.SessionId -cmatch '\A[0-9a-f]{32}\z') 'real-local-generator-exact-id-shape'
        Assert-STEFixture ($request.Ready -is [bool] -and $request.Ready -and $request.ExpectedSessionId -ceq $request.SessionId -and $request.BridgeStatus -ceq 'not-required') 'local-request-needs-no-output-control-file'
        Assert-STEFixture ($request.Problems -is [array] -and $request.Problems.Count -eq 0) 'local-request-problems-remain-empty-array'
    }
    $failedGenerators = @(
        @{ id = 'request-generator-throw-has-no-invented-id'; value = ('2' * 32); throws = $true },
        @{ id = 'request-generator-nonstring-has-no-invented-id'; value = 2; throws = $false },
        @{ id = 'request-generator-multiple-values-rejected'; value = @(('2' * 32), ('3' * 32)); throws = $false }
    )
    foreach ($failedGenerator in $failedGenerators) {
        Invoke-STEFixture $failedGenerator.id 3 {
            $control = New-STEFixtureRequestControl -Prefix $script:steFixtureUtf8.GetBytes('kept=value' + [char]10)
            $before = Read-STEFixtureOwnedBytes $control.Path
            $attempt = Invoke-STEFixtureRequest -GitHubActions $true -OutputPath $control.Path -RunnerTemp $control.Root -GeneratedId $failedGenerator.value -GenerationThrows:$failedGenerator.throws
            $request = $attempt.Request
            Assert-STEFixture ($attempt.GeneratorCalls -eq 1 -and $null -eq $request.SessionId -and $null -eq $request.ExpectedSessionId) 'failed-generation-does-not-synthesize-identity'
            Assert-STEFixture (-not $request.Ready -and $request.BridgeStatus -ceq 'not-attempted' -and $request.Problems -is [array] -and $request.Problems.Count -eq 1 -and $request.Problems[0] -ceq 'request-id-generation-failed') 'generation-failure-state-is-explicit'
            Assert-STEFixtureEqual (Read-STEFixtureOwnedBytes $control.Path) $before 'generation-failure-does-not-touch-owned-control'
        }
    }
    $invalidBridgePrefixes = @(
        @{ id = 'request-bridge-unterminated-prefix-rejected'; bytes = $script:steFixtureUtf8.GetBytes('key=value') },
        @{ id = 'request-bridge-multiline-prefix-rejected'; bytes = $script:steFixtureUtf8.GetBytes('key<<END' + [char]10 + 'value' + [char]10 + 'END' + [char]10) },
        @{ id = 'request-bridge-bom-prefix-rejected'; bytes = [byte[]](@(239, 187, 191) + @($script:steFixtureUtf8.GetBytes('key=value' + [char]10))) },
        @{ id = 'request-bridge-nonascii-prefix-rejected'; bytes = $script:steFixtureUtf8.GetBytes('key=' + [char]233 + [char]10) },
        @{ id = 'request-bridge-carriage-return-only-rejected'; bytes = $script:steFixtureUtf8.GetBytes('key=value' + [char]13) },
        @{ id = 'request-bridge-missing-equals-rejected'; bytes = $script:steFixtureUtf8.GetBytes('key' + [char]10) },
        @{ id = 'request-bridge-empty-key-rejected'; bytes = $script:steFixtureUtf8.GetBytes('=value' + [char]10) },
        @{ id = 'request-bridge-blank-record-rejected'; bytes = $script:steFixtureUtf8.GetBytes('key=value' + [char]10 + [char]10) }
    )
    foreach ($invalidBridgePrefix in $invalidBridgePrefixes) {
        Invoke-STEFixture $invalidBridgePrefix.id 2 {
            $control = New-STEFixtureRequestControl -Prefix $invalidBridgePrefix.bytes
            $failure = Get-STEFixtureRequestFailure {
                Write-SwiftTestEvidenceRequestOutput -OutputPath $control.Path -RunnerTemp $control.Root -SessionId ('2' * 32)
            }
            Assert-STEFixture ($failure.Failed -and $failure.Code -ceq 'test-evidence-request-output-invalid') 'bridge-prefix-framing-rejected'
            Assert-STEFixtureEqual (Read-STEFixtureOwnedBytes $control.Path) $invalidBridgePrefix.bytes 'bridge-prefix-rejection-preserves-bytes'
        }
    }
    $duplicateBridgeKeys = @(
        @{ id = 'request-bridge-reserved-key-case-collision'; text = 'CORELOGIC_EVIDENCE_REQUEST_ID=' + ('1' * 32) + [char]10 },
        @{ id = 'request-bridge-ordinary-duplicate-key'; text = 'key=first' + [char]10 + 'key=second' + [char]10 },
        @{ id = 'request-bridge-ordinary-casefold-key-collision'; text = 'Key=first' + [char]10 + 'KEY=second' + [char]10 }
    )
    foreach ($duplicateBridgeKey in $duplicateBridgeKeys) {
        Invoke-STEFixture $duplicateBridgeKey.id 3 {
            $prefix = $script:steFixtureUtf8.GetBytes($duplicateBridgeKey.text)
            $control = New-STEFixtureRequestControl -Prefix $prefix
            $request = (Invoke-STEFixtureRequest -GitHubActions $true -OutputPath $control.Path -RunnerTemp $control.Root).Request
            Assert-STEFixture ($request.SessionId -ceq ('2' * 32) -and $null -eq $request.ExpectedSessionId) 'duplicate-key-keeps-generated-id-but-withholds-gate-id'
            Assert-STEFixture (-not $request.Ready -and $request.BridgeStatus -ceq 'failed' -and $request.Problems.Count -eq 1 -and $request.Problems[0] -ceq 'request-output-bridge-failed') 'duplicate-key-does-not-claim-transport-success'
            Assert-STEFixtureEqual (Read-STEFixtureOwnedBytes $control.Path) $prefix 'duplicate-key-refusal-leaves-original-control'
        }
    }
    $invalidBridgeIds = @(
        @{ id = 'request-bridge-null-id-rejected'; value = $null },
        @{ id = 'request-bridge-singleton-id-array-rejected'; value = @('2' * 32) },
        @{ id = 'request-bridge-uppercase-id-rejected'; value = ('A' * 32) }
    )
    foreach ($invalidBridgeId in $invalidBridgeIds) {
        Invoke-STEFixture $invalidBridgeId.id 2 {
            $prefix = $script:steFixtureUtf8.GetBytes('kept=value' + [char]10)
            $control = New-STEFixtureRequestControl -Prefix $prefix
            $failure = Get-STEFixtureRequestFailure {
                Write-SwiftTestEvidenceRequestOutput -OutputPath $control.Path -RunnerTemp $control.Root -SessionId $invalidBridgeId.value
            }
            Assert-STEFixture ($failure.Code -ceq 'test-evidence-request-output-invalid') 'bridge-id-must-be-an-actual-exact-string'
            Assert-STEFixtureEqual (Read-STEFixtureOwnedBytes $control.Path) $prefix 'invalid-bridge-id-leaves-owned-control'
        }
    }
    $bridgeAliasKinds = @(
        @{ id = 'request-bridge-dot-segment-rejected'; kind = 'dot' },
        @{ id = 'request-bridge-parent-segment-rejected'; kind = 'parent' },
        @{ id = 'request-bridge-trailing-space-rejected'; kind = 'space' },
        @{ id = 'request-bridge-short-name-alias-rejected'; kind = 'short' }
    )
    foreach ($bridgeAliasKind in $bridgeAliasKinds) {
        Invoke-STEFixture $bridgeAliasKind.id 2 {
            $prefix = $script:steFixtureUtf8.GetBytes('kept=value' + [char]10)
            $control = New-STEFixtureRequestControl -Prefix $prefix
            $alias = switch ($bridgeAliasKind.kind) {
                'dot' { $control.Root + '\.\output.txt' }
                'parent' { $control.Root + '\child\..\output.txt' }
                'space' { $control.Path + ' ' }
                'short' { $control.Root + '\OUTPU~1.TXT' }
            }
            $failure = Get-STEFixtureRequestFailure {
                Write-SwiftTestEvidenceRequestOutput -OutputPath $alias -RunnerTemp $control.Root -SessionId ('2' * 32)
            }
            Assert-STEFixture ($failure.Code -ceq 'test-evidence-request-output-invalid') 'bridge-path-alias-rejected-before-normalization'
            Assert-STEFixtureEqual (Read-STEFixtureOwnedBytes $control.Path) $prefix 'bridge-path-alias-refusal-preserves-control'
        }
    }
    Invoke-STEFixture 'request-bridge-outside-supplied-owned-runner-root' 2 {
        $first = New-STEFixtureRequestControl
        $second = New-STEFixtureRequestControl -Prefix $script:steFixtureUtf8.GetBytes('kept=value' + [char]10)
        $before = Read-STEFixtureOwnedBytes $second.Path
        $failure = Get-STEFixtureRequestFailure {
            Write-SwiftTestEvidenceRequestOutput -OutputPath $second.Path -RunnerTemp $first.Root -SessionId ('2' * 32)
        }
        Assert-STEFixture ($failure.Code -ceq 'test-evidence-request-output-invalid') 'bridge-output-outside-explicit-root-rejected'
        Assert-STEFixtureEqual (Read-STEFixtureOwnedBytes $second.Path) $before 'outside-supplied-root-owned-file-unchanged'
    }
    Invoke-STEFixture 'request-bridge-directory-leaf-refused' 2 {
        $control = New-STEFixtureRequestControl
        $leaf = Join-Path $control.Root 'directory'
        [void][IO.Directory]::CreateDirectory($leaf)
        $before = Get-STEFixtureOwnedInventory $control.Root
        $failure = Get-STEFixtureRequestFailure {
            Write-SwiftTestEvidenceRequestOutput -OutputPath $leaf -RunnerTemp $control.Root -SessionId ('2' * 32)
        }
        Assert-STEFixture ($failure.Code -ceq 'test-evidence-request-output-invalid') 'bridge-requires-existing-regular-file-leaf'
        Assert-STEFixtureEqual (Get-STEFixtureOwnedInventory $control.Root) $before 'directory-leaf-refusal-leaves-owned-tree'
    }
    $bridgeReparseLocations = @(
        @{ id = 'request-bridge-reparse-ancestor-flag-refused'; location = 'root' },
        @{ id = 'request-bridge-reparse-leaf-flag-refused'; location = 'leaf' }
    )
    foreach ($bridgeReparseLocation in $bridgeReparseLocations) {
        Invoke-STEFixture $bridgeReparseLocation.id 3 {
            $prefix = $script:steFixtureUtf8.GetBytes('kept=value' + [char]10)
            $control = New-STEFixtureRequestControl -Prefix $prefix
            $reparsePath = if ($bridgeReparseLocation.location -ceq 'root') { $control.Root } else { $control.Path }
            $observed = Invoke-STEFixtureRequestReparse -OutputPath $control.Path -RunnerTemp $control.Root -ReparsePath $reparsePath -RequestId ('2' * 32)
            Assert-STEFixture ($observed.Injected -and $observed.Failure.Code -ceq 'test-evidence-request-output-invalid') 'simulated-reparse-attribute-is-rejected'
            Assert-STEFixture ($observed.AttributePaths.Count -gt 0 -and [string]::Equals($observed.AttributePaths[-1], $reparsePath, [StringComparison]::OrdinalIgnoreCase)) 'bridge-stops-attribute-walk-at-reparse-flag'
            Assert-STEFixtureEqual (Read-STEFixtureOwnedBytes $control.Path) $prefix 'simulated-reparse-control-bytes-unchanged'
        }
    }
    Invoke-STEFixture 'request-bridge-exact-final-byte-limit' 3 {
        $append = $script:steFixtureUtf8.GetBytes('corelogic_evidence_request_id=' + ('2' * 32) + [char]10)
        $prefix = $script:steFixtureUtf8.GetBytes('key=' + ('a' * (65536 - $append.Length - 5)) + [char]10)
        $control = New-STEFixtureRequestControl -Prefix $prefix
        $request = (Invoke-STEFixtureRequest -GitHubActions $true -OutputPath $control.Path -RunnerTemp $control.Root).Request
        $after = Read-STEFixtureOwnedBytes $control.Path
        Assert-STEFixture ($request.Ready -and $request.BridgeStatus -ceq 'written') 'bridge-admits-exact-final-byte-bound'
        Assert-STEFixture ($after.Length -eq 65536 -and $request.ExpectedSessionId -ceq ('2' * 32)) 'exact-byte-limit-retains-caller-expectation'
        Assert-STEFixture ((Get-STEFixtureHash $after) -ceq (Get-STEFixtureHash ([byte[]](@($prefix) + @($append))))) 'exact-byte-limit-appends-only-fixed-line'
    }
    Invoke-STEFixture 'request-bridge-postappend-limit-refuses-before-write' 2 {
        $append = $script:steFixtureUtf8.GetBytes('corelogic_evidence_request_id=' + ('2' * 32) + [char]10)
        $prefix = $script:steFixtureUtf8.GetBytes('key=' + ('a' * (65537 - $append.Length - 5)) + [char]10)
        $control = New-STEFixtureRequestControl -Prefix $prefix
        $failure = Get-STEFixtureRequestFailure {
            Write-SwiftTestEvidenceRequestOutput -OutputPath $control.Path -RunnerTemp $control.Root -SessionId ('2' * 32)
        }
        Assert-STEFixture ($prefix.Length -le 65536 -and $failure.Code -ceq 'test-evidence-request-output-invalid') 'bridge-rejects-appended-length-over-limit'
        Assert-STEFixture ((Get-STEFixtureHash (Read-STEFixtureOwnedBytes $control.Path)) -ceq (Get-STEFixtureHash $prefix)) 'postappend-limit-refusal-does-not-append'
    }
    Invoke-STEFixture 'request-bridge-existing-prefix-over-limit-refused' 2 {
        $prefix = $script:steFixtureUtf8.GetBytes('key=' + ('a' * 65532) + [char]10)
        $control = New-STEFixtureRequestControl -Prefix $prefix
        $failure = Get-STEFixtureRequestFailure {
            Write-SwiftTestEvidenceRequestOutput -OutputPath $control.Path -RunnerTemp $control.Root -SessionId ('2' * 32)
        }
        Assert-STEFixture ($prefix.Length -eq 65537 -and $failure.Code -ceq 'test-evidence-request-output-invalid') 'bridge-rejects-existing-prefix-over-limit'
        Assert-STEFixture ((Get-STEFixtureHash (Read-STEFixtureOwnedBytes $control.Path)) -ceq (Get-STEFixtureHash $prefix)) 'oversized-prefix-remains-unchanged'
    }
    Invoke-STEFixture 'request-visible-new-line-after-injected-failure-is-not-success' 8 {
        $control = New-STEFixtureRequestControl -Prefix $script:steFixtureUtf8.GetBytes('kept=value' + [char]10)
        $attempt = Invoke-STEFixtureRequest -GitHubActions $true -OutputPath $control.Path -RunnerTemp $control.Root -VisibleLineThenThrow
        $request = $attempt.Request
        $visible = $script:steFixtureUtf8.GetString((Read-STEFixtureOwnedBytes $control.Path))
        $visibleId = ('2' * 32)
        $session = New-STEFixtureRequestSession -RequestId $request.SessionId
        $objects = @(New-STEFixtureTrace)
        $boundary = Invoke-STEFixtureRequestBoundary -RequestSession $session -Objects $objects
        Complete-SwiftTestEvidenceSession $session $boundary.ReturnCode
        $gateFailure = Get-STEFixtureRequestFailure {
            Test-SwiftTestEvidenceCurrentInvocation $script:steFixtureWorkspace $session.Directory $request.ExpectedSessionId
        }
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'failure' -ExpectedSessionId $visibleId -RequireCurrentInvocation
        Assert-STEFixture ($attempt.InjectedLineWrites -eq 1 -and $visible -ceq ('kept=value' + [char]10 + 'corelogic_evidence_request_id=' + $visibleId + [char]10)) 'injected-failure-leaves-complete-new-line-visible'
        Assert-STEFixture ($request.SessionId -ceq $visibleId -and $null -eq $request.ExpectedSessionId -and -not $request.Ready) 'visible-new-id-does-not-set-full-request-ready'
        Assert-STEFixture ($request.BridgeStatus -ceq 'failed' -and $request.Problems.Count -eq 1 -and $request.Problems[0] -ceq 'request-output-bridge-failed') 'visible-new-line-preserves-original-bridge-failure'
        Assert-STEFixture ($boundary.ReturnCode -eq 0 -and $boundary.ReportedExitCode -eq 0 -and (Test-STEFixtureRequestOutputIdentity $boundary $objects)) 'bridge-failure-does-not-change-original-test-boundary'
        Assert-STEFixture ($gateFailure.Code -ceq 'test-evidence-expected-session-id-invalid' -and $script:steFixtureRequestWiring.CheckRequiresReadyCallerExpectation) 'held-not-ready-request-keeps-full-gate-failed'
        Assert-STEFixture ($publication.evidenceReadStatus -ceq 'validated-complete-journal' -and $publication.observed.passed -eq 1) 'publisher-may-correlate-separately-supplied-visible-id'
        Assert-STEFixture (Test-STEFixtureRequestAssociation $publication.currentInvocation $visibleId $visibleId 'expected-id-match') 'visible-id-match-does-not-authenticate-transport-or-generation'
        Assert-STEFixture ($publication.fullOutcome -ceq 'failure') 'visible-id-publication-never-promotes-full-failure'
    }
    Invoke-STEFixture 'request-old-visible-id-match-is-not-current-generation-proof' 5 {
        $oldSession = New-STEFixtureRequestSession -RequestId ('1' * 32)
        Save-STEFixturePassingShard $oldSession 1
        Complete-SwiftTestEvidenceSession $oldSession 0
        $prefix = $script:steFixtureUtf8.GetBytes('corelogic_evidence_request_id=' + ('1' * 32) + [char]10)
        $control = New-STEFixtureRequestControl -Prefix $prefix
        $request = (Invoke-STEFixtureRequest -GitHubActions $true -OutputPath $control.Path -RunnerTemp $control.Root).Request
        $gateFailure = Get-STEFixtureRequestFailure {
            Test-SwiftTestEvidenceCurrentInvocation $script:steFixtureWorkspace $oldSession.Directory $request.ExpectedSessionId
        }
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $oldSession.Directory 'failure' -ExpectedSessionId ('1' * 32) -RequireCurrentInvocation
        Assert-STEFixture (-not $request.Ready -and $request.SessionId -ceq ('2' * 32) -and $null -eq $request.ExpectedSessionId) 'new-held-request-fails-despite-existing-old-key'
        Assert-STEFixtureEqual (Read-STEFixtureOwnedBytes $control.Path) $prefix 'refusal-retains-visible-old-id'
        Assert-STEFixture ($gateFailure.Code -ceq 'test-evidence-expected-session-id-invalid') 'old-control-key-does-not-fill-held-full-expectation'
        Assert-STEFixture ($publication.observed.passed -eq 1 -and $publication.evidenceReadStatus -ceq 'validated-complete-journal') 'caller-supplied-old-id-can-only-correlate-old-journal'
        Assert-STEFixture ((Test-STEFixtureRequestAssociation $publication.currentInvocation ('1' * 32) ('1' * 32) 'expected-id-match') -and $publication.fullOutcome -ceq 'failure') 'matching-old-id-carries-explicit-no-freshness-proof'
    }
    Invoke-STEFixture 'publication-valid-request-without-journal-withholds-counts' 4 {
        $directory = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
        $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $directory 'failure' -ExpectedSessionId ('2' * 32) -RequireCurrentInvocation
        $manifest = Read-SwiftTestEvidenceJson (Join-Path $directory 'published/manifest.json')
        Assert-STEFixture ($publication.evidenceReadStatus -ceq 'current-request-journal-unavailable') 'valid-request-with-no-journal-is-unavailable'
        Assert-STEFixture (Test-STEFixtureWithheldPublication $publication $directory) 'unavailable-current-journal-does-not-invent-counts'
        Assert-STEFixture (Test-STEFixtureRequestAssociation $publication.currentInvocation ('2' * 32) $null 'current-request-journal-unavailable') 'unavailable-journal-retains-only-caller-id'
        Assert-STEFixture ($manifest.schemaVersion -eq 2 -and (Test-STEFixtureRequestAssociation $manifest.currentInvocation ('2' * 32) $null 'current-request-journal-unavailable')) 'unavailable-publication-manifest-binds-same-limits'
    }
    $explicitMissingPublicationIds = @(
        @{ id = 'publication-explicit-null-is-bound-without-switch'; value = $null },
        @{ id = 'publication-explicit-empty-is-bound-without-switch'; value = '' }
    )
    foreach ($explicitMissingPublicationId in $explicitMissingPublicationIds) {
        Invoke-STEFixture $explicitMissingPublicationId.id 3 {
            $directory = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
            $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $directory 'failure' -ExpectedSessionId $explicitMissingPublicationId.value
            $manifest = Read-SwiftTestEvidenceJson (Join-Path $directory 'published/manifest.json')
            Assert-STEFixture ($publication.schemaVersion -eq 2 -and $publication.evidenceReadStatus -ceq 'current-test-invocation-not-observed') 'explicit-missing-expectation-still-selects-bound-v2'
            Assert-STEFixture (Test-STEFixtureWithheldPublication $publication $directory) 'explicit-missing-expectation-withholds-all-counts'
            Assert-STEFixture ($manifest.schemaVersion -eq 2 -and (Test-STEFixtureRequestAssociation $manifest.currentInvocation $null $null 'current-test-invocation-not-observed')) 'explicit-missing-manifest-never-falls-back-to-v1'
        }
    }
    $malformedPublicationIds = @(
        @{ id = 'publication-malformed-array-before-output'; value = @('2' * 32) },
        @{ id = 'publication-malformed-whitespace-before-output'; value = ' ' },
        @{ id = 'publication-malformed-uppercase-before-output'; value = ('A' * 32) }
    )
    foreach ($malformedPublicationId in $malformedPublicationIds) {
        Invoke-STEFixture $malformedPublicationId.id 2 {
            $directory = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
            $failure = Get-STEFixtureRequestFailure {
                Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $directory 'failure' -ExpectedSessionId $malformedPublicationId.value
            }
            Assert-STEFixture ($failure.Code -ceq 'test-evidence-expected-session-id-invalid') 'malformed-publication-expectation-rejected'
            Assert-STEFixture (-not [IO.File]::Exists($directory) -and -not [IO.Directory]::Exists($directory)) 'malformed-publication-expectation-writes-nothing'
        }
    }
    Invoke-STEFixture 'publication-existing-complete-triple-refuses-current-upload' 4 {
        $session = New-STEFixtureRequestSession -RequestId ('1' * 32)
        Save-STEFixturePassingShard $session 1
        Complete-SwiftTestEvidenceSession $session 0
        $oldPublication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'failure'
        $before = Get-STEFixtureOwnedInventory $session.Directory
        $failure = Get-STEFixtureRequestFailure {
            Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'failure' -ExpectedSessionId ('2' * 32) -RequireCurrentInvocation
        }
        Assert-STEFixture ($oldPublication.schemaVersion -eq 1 -and $failure.Code -ceq 'test-evidence-publication-exists') 'bound-publisher-refuses-old-complete-triple'
        Assert-STEFixtureEqual (Get-STEFixtureOwnedInventory $session.Directory) $before 'old-complete-publication-remains-byte-exact'
        Assert-STEFixture (-not (Test-STEFixtureUploadEligibility 'failure')) 'actual-upload-condition-refuses-failed-publication'
        Assert-STEFixture ($script:steFixtureRequestWiring.PublisherAlwaysAndUploadOnlyOnSuccess -and $script:steFixtureRequestWiring.Kind -ceq 'source-ast-contract-only') 'upload-withholding-is-bound-workflow-condition-only'
    }
    Invoke-STEFixture 'publication-existing-partial-triple-refuses-current-upload' 4 {
        $session = New-STEFixtureRequestSession -RequestId ('2' * 32)
        Save-STEFixturePassingShard $session 1
        Complete-SwiftTestEvidenceSession $session 0
        Write-STEFixtureText (Join-Path $session.Directory 'published/summary.json') '{"authored":"old-partial"}'
        Write-STEFixtureBytes (Join-Path $session.Directory 'published/cases.ndjson') ([byte[]]@())
        $before = Get-STEFixtureOwnedInventory $session.Directory
        $failure = Get-STEFixtureRequestFailure {
            Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $session.Directory 'failure' -ExpectedSessionId $session.Plan.sessionId -RequireCurrentInvocation
        }
        Assert-STEFixture ($failure.Code -ceq 'test-evidence-publication-exists') 'bound-publisher-refuses-old-partial-triple'
        Assert-STEFixtureEqual (Get-STEFixtureOwnedInventory $session.Directory) $before 'old-partial-publication-remains-byte-exact'
        Assert-STEFixture (-not [IO.File]::Exists((Join-Path $session.Directory 'published/manifest.json'))) 'refusal-never-completes-old-partial-manifest'
        Assert-STEFixture (-not (Test-STEFixtureUploadEligibility 'failure')) 'failed-partial-publication-not-eligible-for-upload'
    }
    Invoke-STEFixture 'publication-new-partial-write-never-returns-success' 4 {
        $session = New-STEFixtureRequestSession -RequestId ('2' * 32)
        Save-STEFixturePassingShard $session 1
        Complete-SwiftTestEvidenceSession $session 0
        $before = Get-STEFixtureOwnedInventory $session.Directory -OmitPublished
        $failure = Invoke-STEFixturePublicationWriteFailure $session $session.Plan.sessionId
        $published = Get-STEFixtureOwnedInventory (Join-Path $session.Directory 'published')
        Assert-STEFixture ($failure.Failed -and $failure.Code -ceq 'test-evidence-fixture-manifest-write-failed') 'manifest-write-failure-is-not-publication-success'
        Assert-STEFixture ($published.Files.Count -eq 2 -and $published.Files.path -ccontains 'summary.json' -and $published.Files.path -ccontains 'cases.ndjson' -and -not [IO.File]::Exists((Join-Path $session.Directory 'published/manifest.json'))) 'new-partial-files-remain-visible-without-manifest'
        Assert-STEFixtureEqual (Get-STEFixtureOwnedInventory $session.Directory -OmitPublished) $before 'publication-write-failure-keeps-original-journal'
        Assert-STEFixture (-not (Test-STEFixtureUploadEligibility 'failure')) 'partial-write-failure-cannot-select-corelogic-upload'
    }
    $singleBundleOperations = @(
        @{ id = 'current-check-identity-and-counts-use-one-bundle'; operation = 'check' },
        @{ id = 'bound-publication-identity-and-counts-use-one-bundle'; operation = 'publish' }
    )
    foreach ($singleBundleOperation in $singleBundleOperations) {
        Invoke-STEFixture $singleBundleOperation.id 4 {
            $first = New-STEFixtureRequestSession -RequestId ('1' * 32)
            Save-STEFixturePassingShard $first 1 'FixtureTests.testFirst'
            Complete-SwiftTestEvidenceSession $first 0
            $later = New-STEFixtureRequestSession -RequestId ('2' * 32) -Count 2
            Save-STEFixturePassingShard $later 1 'FixtureTests.testLaterOne'
            Save-STEFixturePassingShard $later 2 'FixtureTests.testLaterTwo'
            Complete-SwiftTestEvidenceSession $later 0
            $firstBundle = Read-SwiftTestEvidenceBundle $script:steFixtureWorkspace $first.Directory
            $laterBundle = Read-SwiftTestEvidenceBundle $script:steFixtureWorkspace $later.Directory
            $observed = Invoke-STEFixtureSingleBundle -BundleOperation $singleBundleOperation.operation -ExpectedId ('1' * 32) -FirstBundle $firstBundle -LaterBundle $laterBundle -BundleDirectory $first.Directory
            Assert-STEFixture ($firstBundle.Plan.sessionId -cne $laterBundle.Plan.sessionId -and $firstBundle.Observed.passed -eq 1 -and $laterBundle.Observed.passed -eq 2) 'single-bundle-controls-have-distinct-valid-ids-and-counts'
            Assert-STEFixture ($null -eq $observed.FailureCode -and $observed.BundleReads -eq 1 -and $observed.DirectPlanReads -eq 0) 'current-seam-never-rereads-plan-or-bundle'
            $returnedId = if ($singleBundleOperation.operation -ceq 'check') { $observed.Value.Plan.sessionId } else { $observed.Value.currentInvocation.journalSessionId }
            Assert-STEFixture ($returnedId -ceq $firstBundle.Plan.sessionId -and $observed.Value.Observed.passed -eq 1 -and $observed.Value.Observed.distinctIds -eq 1) 'current-seam-binds-first-bundle-identity-and-counts'
            if ($singleBundleOperation.operation -ceq 'check') {
                Assert-STEFixture ($observed.Value.Summary.evidenceCompleteForDeclaredScope -and [object]::ReferenceEquals($observed.Value, $firstBundle)) 'current-check-returns-same-completed-bundle'
            } else {
                $saved = Read-SwiftTestEvidenceJson (Join-Path $first.Directory 'published/summary.json')
                Assert-STEFixture ($saved.currentInvocation.journalSessionId -ceq $firstBundle.Plan.sessionId -and $saved.observed.passed -eq 1 -and $saved.fullOutcome -ceq 'failure') 'saved-publication-binds-first-bundle-and-failed-outcome'
            }
        }
    }
    Invoke-STEFixture 'current-cli-and-upload-contracts-are-source-bound' 5 {
        Assert-STEFixture ($script:steFixtureRequestWiring.Kind -ceq 'source-ast-contract-only' -and $script:steFixtureRequestWiring.CliCheckAndPublishAlwaysBound) 'actual-cli-never-selects-unbound-check-or-publish'
        Assert-STEFixture ($script:steFixtureRequestWiring.WrapperPassesOnlyOriginallySuppliedSessionId -and $script:steFixtureRequestWiring.RequestBeforeOriginalTests -and $script:steFixtureRequestWiring.CheckRequiresReadyCallerExpectation) 'actual-full-caller-id-order-and-splat-contract'
        Assert-STEFixture (Test-STEFixtureUploadEligibility 'success') 'exact-upload-expression-admits-publisher-success'
        Assert-STEFixture (-not (Test-STEFixtureUploadEligibility 'cancelled')) 'exact-upload-expression-refuses-cancelled-publisher'
        Assert-STEFixture (-not (Test-STEFixtureUploadEligibility 'skipped')) 'exact-upload-expression-refuses-skipped-publisher'
    }
    Invoke-STEFixture 'current-check-keeps-existing-source-pin-gate' 2 {
        $session = New-STEFixtureRequestSession -RequestId ('2' * 32)
        Save-STEFixturePassingShard $session 1
        Complete-SwiftTestEvidenceSession $session 0
        $packagePath = Join-Path $script:steFixtureWorkspace 'Package.swift'
        $originalPackage = [byte[]]$script:steFixtureSourceBytes['Package.swift']
        try {
            Write-STEFixtureBytes $packagePath ([byte[]](@($originalPackage) + @(10))) -ReplaceOwned
            $failure = Get-STEFixtureRequestFailure {
                Test-SwiftTestEvidenceCurrentInvocation $script:steFixtureWorkspace $session.Directory $session.Plan.sessionId
            }
            Assert-STEFixture ($failure.Code -ceq 'test-evidence-check-source-changed') 'matching-request-does-not-bypass-source-pin-check'
        } finally { Write-STEFixtureBytes $packagePath $originalPackage -ReplaceOwned }
        Assert-STEFixture ((Get-STEFixtureHash (Read-STEFixtureSource $packagePath)) -ceq (Get-STEFixtureHash $originalPackage)) 'owned-package-source-restored-after-pin-negative'
    }
    # These controls test the fixture's own exact comparison helpers. They do
    # not alter a production schema, publication bytes, or any prior case.
    $associationArrayFields = @(
        @{ id = 'request-association-helper-rejects-expected-id-array'; field = 'expectedSessionId' },
        @{ id = 'request-association-helper-rejects-journal-id-array'; field = 'journalSessionId' },
        @{ id = 'request-association-helper-rejects-status-array'; field = 'identityStatus' },
        @{ id = 'request-association-helper-rejects-generation-array'; field = 'generation' },
        @{ id = 'request-association-helper-rejects-transport-array'; field = 'transport' },
        @{ id = 'request-association-helper-rejects-qualification-array'; field = 'qualification' }
    )
    foreach ($associationArrayField in $associationArrayFields) {
        Invoke-STEFixture $associationArrayField.id 2 {
            $association = [pscustomobject][ordered]@{
                expectedSessionId = ('2' * 32); journalSessionId = ('2' * 32)
                identityStatus = 'expected-id-match'
                generation = 'not-independently-observed'; transport = 'not-independently-observed'
                qualification = 'caller-supplied-id-match-only; not-authenticated-freshness'
            }
            Assert-STEFixture (Test-STEFixtureRequestAssociation $association ('2' * 32) ('2' * 32) 'expected-id-match') 'association-helper-admits-exact-scalar-control'
            $association.($associationArrayField.field) = @($association.($associationArrayField.field), 'authored-extra')
            Assert-STEFixture (-not (Test-STEFixtureRequestAssociation $association ('2' * 32) ('2' * 32) 'expected-id-match')) 'association-helper-rejects-filter-truthiness-array'
        }
    }
    Invoke-STEFixture 'request-association-helper-rejects-extra-property' 2 {
        $association = [pscustomobject][ordered]@{
            expectedSessionId = $null; journalSessionId = $null
            identityStatus = 'current-test-invocation-not-observed'
            generation = 'not-independently-observed'; transport = 'not-independently-observed'
            qualification = 'caller-supplied-id-match-only; not-authenticated-freshness'
        }
        Assert-STEFixture (Test-STEFixtureRequestAssociation $association $null $null 'current-test-invocation-not-observed') 'association-helper-admits-null-identifiers-control'
        Add-Member -InputObject $association -MemberType NoteProperty -Name authoredExtra -Value 'extra'
        Assert-STEFixture (-not (Test-STEFixtureRequestAssociation $association $null $null 'current-test-invocation-not-observed')) 'association-helper-rejects-unknown-property'
    }
    Invoke-STEFixture 'request-association-helper-rejects-key-case-alias' 2 {
        $association = [pscustomobject][ordered]@{
            expectedSessionId = $null; journalSessionId = $null
            identityStatus = 'current-test-invocation-not-observed'
            generation = 'not-independently-observed'; transport = 'not-independently-observed'
            qualification = 'caller-supplied-id-match-only; not-authenticated-freshness'
        }
        Assert-STEFixture (Test-STEFixtureRequestAssociation $association $null $null 'current-test-invocation-not-observed') 'association-helper-admits-canonical-keys-control'
        $association.PSObject.Properties.Remove('generation')
        Add-Member -InputObject $association -MemberType NoteProperty -Name Generation -Value 'not-independently-observed'
        Assert-STEFixture (-not (Test-STEFixtureRequestAssociation $association $null $null 'current-test-invocation-not-observed')) 'association-helper-rejects-key-spelling-alias'
    }
    $withheldByteTypes = @(
        @{ id = 'request-withholding-helper-rejects-string-zero-bytes'; value = '0' },
        @{ id = 'request-withholding-helper-rejects-boolean-zero-bytes'; value = $false }
    )
    foreach ($withheldByteType in $withheldByteTypes) {
        Invoke-STEFixture $withheldByteType.id 3 {
            $directory = Join-Path $script:steFixtureWorkspace (New-STEFixtureRelative)
            $publication = Publish-SwiftTestEvidenceCI $script:steFixtureWorkspace $directory 'failure' -RequireCurrentInvocation
            Assert-STEFixture (Test-STEFixtureWithheldPublication $publication $directory) 'withholding-helper-admits-real-int32-zero-bytes'
            $publication.cases.bytes = [long]0
            Assert-STEFixture (Test-STEFixtureWithheldPublication $publication $directory) 'withholding-helper-admits-integral-int64-zero-bytes'
            $publication.cases.bytes = $withheldByteType.value
            Assert-STEFixture (-not (Test-STEFixtureWithheldPublication $publication $directory)) 'withholding-helper-rejects-coerced-zero-bytes'
        }
    }

    Invoke-STEFixture 'source-parse-explicit-utf8-without-bom' 5 {
        $sourceText = 'Write-Output "strict' + [char]0x2014 + 'source"'
        $sourcePath = 'fixture-memory-only/strict-utf8-source.ps1'
        $sourceBytes = $script:steFixtureUtf8.GetBytes($sourceText)
        Assert-STEFixture (-not ($sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF)) 'source-parse-authored-no-bom'
        $sourceTokens = $null
        $sourceErrors = $null
        $sourceAst = ConvertFrom-STEFixtureUtf8Source $sourceBytes $sourcePath ([ref]$sourceTokens) ([ref]$sourceErrors)
        Assert-STEFixture ($sourceErrors.Count -eq 0) 'source-parse-no-errors'
        Assert-STEFixture ([string]::Equals($sourceAst.Extent.Text, $sourceText, [StringComparison]::Ordinal)) 'source-parse-ordinal-text'
        Assert-STEFixture ([string]::Equals($sourceAst.Extent.File, $sourcePath, [StringComparison]::Ordinal)) 'source-parse-filename-metadata'
        Assert-STEFixture ((Get-STEFixtureHash $script:steFixtureUtf8.GetBytes($sourceAst.Extent.Text)) -ceq (Get-STEFixtureHash $sourceBytes)) 'source-parse-byte-hash'
    }
    Invoke-STEFixture 'source-parse-malformed-utf8-refused' 2 {
        $sourceTokens = $null
        $sourceErrors = $null
        $sourceFailure = $null
        try {
            $null = ConvertFrom-STEFixtureUtf8Source ([byte[]]@(0xC3, 0x28)) 'fixture-memory-only/malformed-source.ps1' (
                [ref]$sourceTokens) ([ref]$sourceErrors)
        } catch { $sourceFailure = $_ }
        Assert-STEFixture ($null -ne $sourceFailure) 'source-parse-malformed-refused'
        Assert-STEFixture ($null -ne $sourceFailure -and (
            $sourceFailure.Exception -is [Text.DecoderFallbackException] -or
            $sourceFailure.Exception.InnerException -is [Text.DecoderFallbackException])) 'source-parse-strict-decoder-type'
    }

    Invoke-STEFixture 'no-forbidden-operations' 1 {
        Assert-STEFixture ($script:steFixtureForbiddenCalls -eq 0) 'forbidden-operation-count'
    }
    Invoke-STEFixture 'rejection-action-keeps-authored-path-binding' 4 {
        # An in-memory path-shaped string only; no production helper or IO.
        $intendedPath = 'fixture-memory-only/intended.json'
        $path = $intendedPath
        $bindingObservation = [pscustomobject]@{ isString = $false; value = $null }
        Assert-STEFixtureRejected {
            $bindingObservation.isString = $path -is [string]
            $bindingObservation.value = $path
            throw 'fixture-binding-rejection'
        } 'fixture-binding-rejection'
        Assert-STEFixture $bindingObservation.isString 'rejection-action-bound-string'
        Assert-STEFixtureEqual $bindingObservation.value $intendedPath 'rejection-action-intended-path'
    }
} catch {
    $script:steFixtureSetupFailure = 'fixture-setup-or-harness-failed'
} finally {
    foreach ($pin in $script:steFixtureSourcePins) {
        try {
            $current = Read-STEFixtureSource (Join-Path $script:steFixtureSourceRoot $pin.path)
            if ($current.Length -ne $pin.bytes -or (Get-STEFixtureHash $current) -cne $pin.sha256) { $script:steFixtureSourceChanged = $true }
        } catch { $script:steFixtureSourceChanged = $true }
    }
    if ($null -ne $script:steFixtureWorkflowPin) {
        try {
            $currentWorkflow = Read-STEFixtureSource $script:steFixtureWorkflowPath
            if ($currentWorkflow.Length -ne $script:steFixtureWorkflowPin.bytes -or
                (Get-STEFixtureHash $currentWorkflow) -cne $script:steFixtureWorkflowPin.sha256) { $script:steFixtureSourceChanged = $true }
        } catch { $script:steFixtureSourceChanged = $true }
    }

    $failed = @($script:steFixtureResults | Where-Object { $_.status -cne 'passed' }).Count
    $passed = $script:steFixtureResults.Count - $failed
    $intendedAssertions = 0
    foreach ($row in $script:steFixtureResults) { $intendedAssertions += $row.intendedAssertions }
    $successful = $null -eq $script:steFixtureSetupFailure -and -not $script:steFixtureSourceChanged -and
        $failed -eq 0 -and $script:steFixtureResults.Count -gt 0 -and $script:steFixtureForbiddenCalls -eq 0
    $result = [pscustomobject][ordered]@{
        schemaVersion = 1; kind = 'swift-test-evidence-synthetic-fixtures'
        status = if ($successful) { 'passed' } else { 'failed' }
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        caseCount = $script:steFixtureResults.Count; passed = $passed; failed = $failed
        intendedAssertions = $intendedAssertions; observedAssertions = $script:steFixtureAssertions
        setupFailure = $script:steFixtureSetupFailure; sourceChanged = $script:steFixtureSourceChanged
        forbiddenOperationCount = $script:steFixtureForbiddenCalls
        copiedSourceFiles = @($script:steFixtureSourcePins.ToArray())
        cases = @($script:steFixtureResults.ToArray())
        limits = @(
            'Synthetic parser/journal/publication fixtures only; not a real XCTest, Swift Testing, or process-output observation.',
            'Only extracted invocation functions with verified local mocks; no real subprocess, OS argv marshalling, or stderr capture.',
            'No compiler, SwiftPM, native observer, font operation, network, or CI invocation.',
            'Full ordering, CLI binding and upload eligibility are source AST/condition contracts only, not executions or authenticated freshness.',

            'Five source text copies in one fake workspace; every generated file is retained; no automatic cleanup.'
        )
    }
    try {
        $bytes = $script:steFixtureUtf8.GetBytes((ConvertTo-Json -InputObject $result -Depth 10 -Compress) + [Environment]::NewLine)
        if ($bytes.Length -gt 65536) { throw 'fixture-result-size-limit' }
        Write-STEFixtureBytes (Join-Path $script:steFixtureRoot 'fixture-result.json') $bytes
    } catch {
        $successful = $false
        [Console]::Error.WriteLine('Swift test evidence fixture result could not be written.')
    }
}

Write-Host ('Swift test evidence fixtures: {0} passed, {1} failed, {2} assertions.' -f $passed, $failed, $script:steFixtureAssertions)
if (-not $successful) { exit 1 }
exit 0
