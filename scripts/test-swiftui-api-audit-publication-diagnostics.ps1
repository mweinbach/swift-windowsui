<#
.SYNOPSIS
Tests publication diagnostics with owned synthetic files and extracted builder control flow.
#>
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot
)
$ErrorActionPreference = 'Stop'
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$fixtureScriptsRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if ($RepositoryRoot.TrimEnd('\', '/') -ine (Split-Path -Parent $fixtureScriptsRoot).TrimEnd('\', '/')) {
    throw 'Publication fixtures must use the repository containing this test script.'
}
$artifactsRoot = Join-Path $RepositoryRoot 'artifacts'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $artifactsRoot ('swiftui-api-audit-publication-tests/' + [Guid]::NewGuid().ToString('N'))
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$artifactsPrefix = [IO.Path]::GetFullPath($artifactsRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $OutputRoot.StartsWith($artifactsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Publication fixture output must be a new directory below this repository artifacts directory.'
}
for ($ancestor = $OutputRoot; -not [string]::IsNullOrEmpty($ancestor); $ancestor = [IO.Path]::GetDirectoryName($ancestor)) {
    if (Test-Path -LiteralPath $ancestor) {
        if (((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Publication fixture paths must not traverse reparse points.'
        }
    }
}
if (Test-Path -LiteralPath $OutputRoot) { throw 'Publication fixture output must be new.' }
[void][IO.Directory]::CreateDirectory($OutputRoot)
$script:PublicationAssertions = 0
$publicationUtf8 = [Text.UTF8Encoding]::new($false, $true)

function Assert-Publication {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw "Publication diagnostic assertion failed: $Message" }
    $script:PublicationAssertions++
}

function Assert-PublicationRejected {
    param([scriptblock]$Action, [string]$Message)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-Publication ($null -ne $caught) $Message
}

function Get-PublicationHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-PublicationPrimitive {
    param($Value, [int]$Depth = 0)
    Assert-Publication ($Depth -le 12) 'diagnostic facts have bounded container depth'
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or
            $Value -is [int] -or $Value -is [long]) { return }
    if ($Value -is [Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            Assert-Publication ($key -is [string]) 'diagnostic dictionary keys are strings'
            Assert-PublicationPrimitive -Value $Value[$key] -Depth ($Depth + 1)
        }
        return
    }
    if ($Value -is [Array]) {
        foreach ($item in $Value) { Assert-PublicationPrimitive -Value $item -Depth ($Depth + 1) }
        return
    }
    if ($Value -is [Management.Automation.PSCustomObject]) {
        foreach ($property in $Value.PSObject.Properties) {
            Assert-PublicationPrimitive -Value $property.Value -Depth ($Depth + 1)
        }
        return
    }
    throw ('Unexpected live object in diagnostic facts: ' + $Value.GetType().FullName)
}

function New-PublicationFixture {
    param([string]$Name)
    $parent = Join-Path $OutputRoot $Name
    [void][IO.Directory]::CreateDirectory($parent)
    $leaf = '.swiftui-api-audit-' + [Guid]::NewGuid().ToString('N')
    $staging = Join-Path $parent $leaf
    [void][IO.Directory]::CreateDirectory($staging)
    $manifest = Join-Path $staging 'audit.json'
    [IO.File]::WriteAllText($manifest, '{"syntheticPublicationFixture":true}' + [char]10, $publicationUtf8)
    $digest = Get-PublicationHash $manifest
    [IO.File]::WriteAllText((Join-Path $staging 'audit.sha256'), $digest + '  audit.json' + [char]10, $publicationUtf8)
    return [pscustomobject]@{
        Parent = $parent; Staging = $staging; Leaf = $leaf
        Destination = (Join-Path $parent 'published'); ManifestHash = $digest
        AttemptedAtUTC = [DateTime]::UtcNow.ToString('o')
        Diagnostic = (Join-Path $parent ($leaf + '.publication-failure.json'))
    }
}

function New-PublicationError {
    param([string]$Target, [int]$HResult = -2147024864)
    # Synthetic HRESULT 0x80070020; this is not an observed Windows sharing violation.
    $exception = [IO.IOException]::new('Synthetic publication failure.', $HResult)
    return [Management.Automation.ErrorRecord]::new($exception, 'SyntheticPublicationMove',
        [Management.Automation.ErrorCategory]::WriteError, $Target)
}

function Read-PublicationDiagnostic {
    param([string]$Path)
    Assert-Publication ((Get-Item -LiteralPath $Path).Length -le 256KB) 'diagnostic JSON is bounded to 256KiB'
    $text = [IO.File]::ReadAllText($Path, $publicationUtf8)
    Assert-Publication (-not $text.Contains('Synthetic publication failure.')) 'exception messages are not serialized'
    Assert-Publication (-not $text.Contains('Exception.Data sentinel')) 'exception data is not serialized'
    Assert-Publication ($text -match '"attemptedAtUTC"\s*:\s*"') 'attempt time is serialized as a string'
    return ($text | ConvertFrom-Json)
}

$builderPath = Join-Path $fixtureScriptsRoot 'build-swiftui-api-audit.ps1'
$helperPath = Join-Path $fixtureScriptsRoot 'swiftui-api-audit-publication-diagnostics.ps1'
$publicationHelperPath = Join-Path $fixtureScriptsRoot 'swiftui-api-audit-publication.ps1'
$ledgerTestPath = Join-Path $fixtureScriptsRoot 'test-swiftui-api-audit.ps1'
$sourcePins = [ordered]@{}
foreach ($path in @($builderPath, $helperPath, $publicationHelperPath, $ledgerTestPath, $PSCommandPath)) {
    $sourcePins[$path] = Get-PublicationHash $path
}
. $helperPath
. $publicationHelperPath
. (Join-Path $fixtureScriptsRoot 'swiftui-baseline-common.ps1')

# Exercise the real primitive projection without serializing a live ErrorRecord.
$nativeException = [ComponentModel.Win32Exception]::new(32, 'Synthetic native exception.')
$outerException = [IO.IOException]::new('Exception.Data sentinel', $nativeException)
$outerException.Data['do-not-serialize'] = $outerException
$exceptionFacts = Get-SwiftUIAuditPublicationExceptionFacts -Exception $outerException
Assert-PublicationPrimitive $exceptionFacts
$chain = @($exceptionFacts.chain)
Assert-Publication ($chain.Count -eq 2) 'both exception levels are retained'
Assert-Publication (-not $exceptionFacts.truncated) 'short exception chain is not truncated'
for ($position = 0; $position -lt 2; $position++) {
    $expectedException = @($outerException, $nativeException)[$position]
    Assert-Publication ($chain[$position].type -ceq $expectedException.GetType().FullName) 'exception type is preserved'
    Assert-Publication ($chain[$position].hresult -eq $expectedException.HResult) 'signed HRESULT is preserved'
    Assert-Publication ($chain[$position].hresultHex -ceq ('0x' + $expectedException.HResult.ToString('X8'))) 'hex HRESULT is preserved'
    Assert-Publication ($chain[$position].type.Length -le 256) 'exception type text is bounded'
}
Assert-Publication ($null -eq $chain[0].nativeErrorCode) 'ordinary IOException is not assigned a guessed native code'
Assert-Publication ($chain[1].nativeErrorCode -eq 32) 'Win32Exception native code is retained'
$deepException = [Exception]::new('Synthetic deepest exception.')
for ($depth = 0; $depth -lt 11; $depth++) {
    $deepException = [InvalidOperationException]::new('Synthetic chain layer.', $deepException)
}
$deepFacts = Get-SwiftUIAuditPublicationExceptionFacts -Exception $deepException
Assert-PublicationPrimitive $deepFacts
Assert-Publication (@($deepFacts.chain).Count -eq 8 -and $deepFacts.truncated) 'long exception chain stops at eight with truncation recorded'

$direct = New-PublicationFixture 'direct-helper'
$directoryFacts = Get-SwiftUIAuditPublicationPathFacts -Path $direct.Staging
$fileFacts = Get-SwiftUIAuditPublicationPathFacts -Path (Join-Path $direct.Staging 'audit.json')
$missingFacts = Get-SwiftUIAuditPublicationPathFacts -Path $direct.Destination
foreach ($facts in @($directoryFacts, $fileFacts, $missingFacts)) { Assert-PublicationPrimitive $facts }
Assert-Publication ($directoryFacts.directoryExists -and -not $directoryFacts.fileExists) 'directory facts distinguish a directory'
Assert-Publication ($fileFacts.fileExists -and -not $fileFacts.directoryExists) 'file facts distinguish a file'
Assert-Publication (-not $missingFacts.fileExists -and -not $missingFacts.directoryExists) 'missing path probes remain false'
Assert-Publication ($null -ne $missingFacts.attributeReadError) 'failed attribute lookup is explicit'
Assert-PublicationRejected { Get-SwiftUIAuditPublicationPathFacts -Path ([string]::new([char]'x', 32769)) } 'oversized path facts reject before serialization'
$directError = New-PublicationError $direct.Staging
$directError.Exception.Data['do-not-serialize'] = $outerException
$directArguments = @{
    ErrorRecord = $directError; StagingPath = $direct.Staging; OutputPath = $direct.Destination
    OutputParent = $direct.Parent; StagingLeaf = $direct.Leaf; ManifestSha256 = $direct.ManifestHash
    AttemptedAtUTC = $direct.AttemptedAtUTC
}
$directPath = Write-SwiftUIAuditPublicationFailureDiagnostic @directArguments
Assert-Publication ($directPath -ceq $direct.Diagnostic) 'diagnostic uses the staging leaf sibling path'
$directReport = Read-PublicationDiagnostic $directPath
Assert-Publication ($directReport.schemaVersion -eq 1 -and
    $directReport.evidenceKind -ceq 'api-audit-publication-failure-diagnostic') 'diagnostic schema and evidence kind are exact'
Assert-Publication ($directReport.operation -ceq 'System.IO.Directory.Move') 'operation remains the failed publication move'
Assert-Publication (-not $directReport.publicationSucceeded -and -not $directReport.failureCauseEstablished) 'diagnostic does not claim success or establish cause'
Assert-Publication ($directReport.auditManifestSha256 -ceq $direct.ManifestHash) 'staged manifest digest is retained'
Assert-Publication ($directReport.paths.staging.path -ceq $direct.Staging -and
    $directReport.paths.destination.path -ceq $direct.Destination -and
    $directReport.paths.parent.path -ceq $direct.Parent) 'all three paths retain their intended roles'
Assert-Publication ($directReport.paths.staging.directoryExists -and
    -not $directReport.paths.destination.directoryExists -and $directReport.paths.parent.directoryExists) 'path observations precede publication cleanup'
Assert-Publication ($directReport.process.pid -eq $PID -and
    $directReport.process.powerShellVersion -ceq $PSVersionTable.PSVersion.ToString()) 'diagnostic identifies the actual fixture process'
Assert-Publication (@($directReport.exceptions)[0].hresult -eq $directError.Exception.HResult) 'diagnostic retains the failed operation HRESULT'
$directHash = Get-PublicationHash $directPath
Assert-PublicationRejected { Write-SwiftUIAuditPublicationFailureDiagnostic @directArguments } 'CreateNew rejects an existing diagnostic'
Assert-Publication ((Get-PublicationHash $directPath) -ceq $directHash) 'collision leaves existing diagnostic bytes unchanged'
$invalidArguments = $directArguments.Clone()
$invalidArguments.StagingLeaf = '../outside'
Assert-PublicationRejected { Write-SwiftUIAuditPublicationFailureDiagnostic @invalidArguments } 'unsafe staging leaf is rejected'
$invalidArguments = $directArguments.Clone()
$invalidArguments.OutputPath = Join-Path $OutputRoot 'outside-the-owned-parent'
Assert-PublicationRejected { Write-SwiftUIAuditPublicationFailureDiagnostic @invalidArguments } 'destination outside the staging sibling parent is rejected'
$invalidArguments = $directArguments.Clone()
$invalidArguments.ManifestSha256 = 'not-a-sha256'
Assert-PublicationRejected { Write-SwiftUIAuditPublicationFailureDiagnostic @invalidArguments } 'invalid manifest digest is rejected'
$invalidArguments = $directArguments.Clone()
$invalidArguments.AttemptedAtUTC = [string]::new([char]'x', 65)
Assert-PublicationRejected { Write-SwiftUIAuditPublicationFailureDiagnostic @invalidArguments } 'oversized attempt-time text is rejected'
Assert-Publication ((Get-PublicationHash $directPath) -ceq $directHash) 'rejected identities preserve the existing diagnostic'

# Exercise the actual path-error catch with synthetic ErrorRecords in a local
# test scope. No production injection hook or filesystem failure is introduced.
$helperTokens = $null; $helperErrors = $null
$helperAst = [Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$helperTokens, [ref]$helperErrors)
Assert-Publication (@($helperErrors).Count -eq 0) 'helper source parses before extracting attribute error projection'
$pathFactFunctions = @($helperAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -ceq 'Get-SwiftUIAuditPublicationPathFacts'
}, $true))
Assert-Publication ($pathFactFunctions.Count -eq 1) 'one production path-facts function supplies the attribute error projection'
$attributeReads = @($pathFactFunctions[0].Body.FindAll({ param($node)
    $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Static -and
    $node.Expression -is [Management.Automation.Language.TypeExpressionAst] -and
    $node.Expression.TypeName.FullName -ceq 'System.IO.File' -and $node.Member.Extent.Text -ceq 'GetAttributes'
}, $true))
Assert-Publication ($attributeReads.Count -eq 1) 'one production attribute read supplies the actual catch body'
$attributeTry = $attributeReads[0].Parent
while ($null -ne $attributeTry -and $attributeTry -isnot [Management.Automation.Language.TryStatementAst]) {
    $attributeTry = $attributeTry.Parent
}
Assert-Publication ($null -ne $attributeTry -and $attributeTry.CatchClauses.Count -eq 1 -and
    $attributeTry.CatchClauses[0].CatchTypes.Count -eq 0) 'attribute observation has one untyped catch'
$attributeCatchText = $attributeTry.CatchClauses[0].Body.Extent.Text
$attributeProjectionSource = $attributeCatchText.Substring(1, $attributeCatchText.Length - 2) +
    [char]10 + '$attributeReadError'
$projectionTokens = $null; $projectionErrors = $null
[void][Management.Automation.Language.Parser]::ParseInput($attributeProjectionSource, [ref]$projectionTokens, [ref]$projectionErrors)
Assert-Publication (@($projectionErrors).Count -eq 0) 'unchanged extracted attribute catch parses'
$attributeErrorProjection = [scriptblock]::Create($attributeProjectionSource)

function Invoke-PublicationAttributeProjection {
    param([Parameter(Mandatory)][Exception]$Exception)
    $syntheticError = [Management.Automation.ErrorRecord]::new($Exception, 'SyntheticAttributeRead',
        [Management.Automation.ErrorCategory]::ReadError, 'Synthetic attribute target')
    return ($syntheticError | ForEach-Object $attributeErrorProjection)
}

$attributeWrapper = [Management.Automation.MethodInvocationException]::new('Synthetic attribute wrapper.', $outerException)
$attributeWrapper.Data['do-not-serialize'] = $attributeWrapper
$attributeCases = @(
    [pscustomobject]@{ name = 'wrapped-native'; exception = $attributeWrapper; count = 3; truncated = $false },
    [pscustomobject]@{ name = 'ordinary-denial'; exception = [UnauthorizedAccessException]::new('Synthetic attribute denied.'); count = 1; truncated = $false },
    [pscustomobject]@{ name = 'deep-chain'; exception = $deepException; count = 8; truncated = $true }
)
foreach ($case in $attributeCases) {
    $projectedError = Invoke-PublicationAttributeProjection -Exception $case.exception
    Assert-PublicationPrimitive $projectedError
    $projectedChain = @($projectedError.exceptions)
    Assert-Publication ($projectedChain.Count -eq $case.count) "$($case.name) retains the bounded attribute exception chain"
    Assert-Publication ($projectedError.exceptionChainTruncated -eq $case.truncated) "$($case.name) records chain truncation explicitly"
    Assert-Publication ($projectedError.type -ceq $case.exception.GetType().FullName -and
        $projectedError.hresult -eq $case.exception.HResult -and
        $projectedError.hresultHex -ceq ('0x' + $case.exception.HResult.ToString('X8'))) "$($case.name) preserves all original outer error fields"
    $expectedException = $case.exception
    foreach ($entry in $projectedChain) {
        Assert-Publication ($entry.type -ceq $expectedException.GetType().FullName -and
            $entry.hresult -eq $expectedException.HResult -and
            $entry.hresultHex -ceq ('0x' + $expectedException.HResult.ToString('X8'))) "$($case.name) retains each actual exception fact"
        $expectedNativeCode = $null
        if ($expectedException -is [ComponentModel.Win32Exception]) { $expectedNativeCode = $expectedException.NativeErrorCode }
        Assert-Publication ($entry.nativeErrorCode -eq $expectedNativeCode) "$($case.name) never guesses a native code from an HRESULT"
        $expectedException = $expectedException.InnerException
    }
    $nestedReport = [ordered]@{ paths = [ordered]@{ destination = [ordered]@{ attributeReadError = $projectedError } } }
    $nestedJson = ConvertTo-Json -InputObject $nestedReport -Depth 8 -Compress -WarningAction Stop
    Assert-Publication ($nestedJson -notmatch 'Synthetic|Exception\.Data|do-not-serialize') "$($case.name) omits messages, targets, and exception Data"
    $roundTrip = $nestedJson | ConvertFrom-Json
    Assert-PublicationPrimitive $roundTrip
    $roundTripError = $roundTrip.paths.destination.attributeReadError
    $roundTripChain = @($roundTripError.exceptions)
    Assert-Publication ($roundTripChain.Count -eq $projectedChain.Count -and
        $roundTripError.exceptionChainTruncated -eq $projectedError.exceptionChainTruncated) "$($case.name) fits the production JSON depth without losing the chain"
    for ($position = 0; $position -lt $projectedChain.Count; $position++) {
        $actualEntry = $roundTripChain[$position]; $expectedEntry = $projectedChain[$position]
        Assert-Publication ($actualEntry.type -ceq $expectedEntry.type -and
            $actualEntry.hresult -eq $expectedEntry.hresult -and
            $actualEntry.hresultHex -ceq $expectedEntry.hresultHex -and
            $actualEntry.nativeErrorCode -eq $expectedEntry.nativeErrorCode) "$($case.name) survives nested JSON roundtrip unchanged"
    }
}

# This is the existing real missing-path observation, not a synthetic native
# error. Do not pin PowerShell's outer wrapper shape across supported versions.
$missingError = $missingFacts.attributeReadError
$missingChain = @($missingError.exceptions)
Assert-Publication ($missingChain.Count -ge 1 -and $missingChain.Count -le 8 -and
    -not $missingError.exceptionChainTruncated) 'real missing-path error has a complete bounded exception chain'
Assert-Publication ($missingError.type -ceq $missingChain[0].type -and
    $missingError.hresult -eq $missingChain[0].hresult -and
    $missingError.hresultHex -ceq $missingChain[0].hresultHex) 'real missing-path outer fields match the first retained exception'
Assert-Publication (@($missingChain | Where-Object { $_.type -in @('System.IO.FileNotFoundException', 'System.IO.DirectoryNotFoundException') }).Count -ge 1) 'real missing-path observation retains its missing-file or missing-directory cause'
Assert-Publication (@($missingChain | Where-Object { $null -ne $_.nativeErrorCode -and $_.type -cne 'System.ComponentModel.Win32Exception' }).Count -eq 0) 'real missing-path projection never invents a native error code'
Assert-Publication ($null -eq $directoryFacts.attributeReadError -and
    $null -eq $fileFacts.attributeReadError) 'successful directory and file observations still have no attribute error'
$serializedMissingError = $directReport.paths.destination.attributeReadError
$serializedMissingChain = @($serializedMissingError.exceptions)
Assert-Publication ($serializedMissingChain.Count -ge 1 -and $serializedMissingChain.Count -le 8 -and
    -not $serializedMissingError.exceptionChainTruncated) 'the real diagnostic JSON retains a complete bounded path-error chain'
Assert-Publication ($serializedMissingError.type -ceq $serializedMissingChain[0].type -and
    $serializedMissingError.hresult -eq $serializedMissingChain[0].hresult -and
    $serializedMissingError.hresultHex -ceq $serializedMissingChain[0].hresultHex) 'serialized outer path error fields remain intact'
Assert-Publication (@($serializedMissingChain | Where-Object { $_.type -in @('System.IO.FileNotFoundException', 'System.IO.DirectoryNotFoundException') }).Count -ge 1) 'the real diagnostic JSON retains the missing-path inner cause'

# Extract only the production publication tail, its catch, and its unchanged
# cleanup. The production builder has no test injection parameter.
$builderSource = [IO.File]::ReadAllText($builderPath, $publicationUtf8)
$parseTokens = $null; $parseErrors = $null
$builderAst = [Management.Automation.Language.Parser]::ParseInput($builderSource, [ref]$parseTokens, [ref]$parseErrors)
Assert-Publication (@($parseErrors).Count -eq 0) 'builder source parses before extracting control flow'
$moves = @($builderAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Static -and
    $node.Expression -is [Management.Automation.Language.TypeExpressionAst] -and
    $node.Expression.TypeName.FullName -ceq 'System.IO.Directory' -and $node.Member.Extent.Text -ceq 'Move'
}, $true))
Assert-Publication ($moves.Count -eq 1) 'builder contains exactly one Directory.Move'
$moveAst = $moves[0]
Assert-Publication ($moveAst.Arguments.Count -eq 2 -and $moveAst.Arguments[0].Extent.Text -ceq '$stagingPath' -and
    $moveAst.Arguments[1].Extent.Text -ceq '$outputPath') 'production move uses the original source and destination variables'
$publicationTry = $moveAst.Parent
while ($null -ne $publicationTry -and $publicationTry -isnot [Management.Automation.Language.TryStatementAst]) {
    $publicationTry = $publicationTry.Parent
}
Assert-Publication ($null -ne $publicationTry -and $publicationTry.CatchClauses.Count -eq 1 -and
    $publicationTry.CatchClauses[0].CatchTypes.Count -eq 0 -and $null -ne $publicationTry.Finally) 'publication has one untyped catch and original finally'
$bodyStatements = @($publicationTry.Body.Statements)
$moveIndex = -1
for ($position = 0; $position -lt $bodyStatements.Count; $position++) {
    if ($bodyStatements[$position].Extent.StartOffset -le $moveAst.Extent.StartOffset -and
            $bodyStatements[$position].Extent.EndOffset -ge $moveAst.Extent.EndOffset) { $moveIndex = $position }
}
Assert-Publication ($moveIndex -ge 3 -and $moveIndex -eq $bodyStatements.Count - 2) 'only published=true follows the move in the production try'
Assert-Publication ($bodyStatements[$moveIndex - 1].Extent.Text -match '^\$publicationAttempted\s*=\s*\$true$') 'attempt flag is set immediately before the one move'
Assert-Publication ($bodyStatements[$moveIndex - 2].Extent.Text -match '^\$publicationAttemptedAtUTC\s*=' -and
    $bodyStatements[$moveIndex - 2].Extent.Text.Contains('UtcNow')) 'attempt timestamp is taken before the flag and move'
Assert-Publication ($bodyStatements[$moveIndex + 1].Extent.Text -match '^\$published\s*=\s*\$true$') 'successful publication flag remains unchanged'
$guard = $bodyStatements[$moveIndex - 3]
Assert-Publication ($guard -is [Management.Automation.Language.IfStatementAst] -and
    $guard.Extent.Text.Contains('$outputPath') -and $guard.Extent.Text.Contains('never overwritten')) 'existing-output guard stays before the attempt flag'
$initializers = [Collections.Generic.List[string]]::new()
foreach ($name in @('failure', 'published', 'publicationAttempted', 'publicationAttemptedAtUTC')) {
    $assignments = @($builderAst.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.AssignmentStatementAst] -and
        $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq $name
    })
    Assert-Publication ($assignments.Count -eq 1 -and $assignments[0].Extent.EndOffset -lt $publicationTry.Extent.StartOffset) "$name is reset before each invocation"
    $expectedValue = if ($name -in @('failure', 'publicationAttemptedAtUTC')) { '$null' } else { '$false' }
    Assert-Publication ($assignments[0].Right.Extent.Text.Trim() -ceq $expectedValue) "$name starts with its expected value"
    $initializers.Add($assignments[0].Extent.Text)
}
$catchBody = $publicationTry.CatchClauses[0].Body
Assert-Publication ($catchBody.Statements[0].Extent.Text -match '^\$failure\s*=\s*\$_$') 'catch captures the actual original ErrorRecord first'
$rethrowGuard = $catchBody.Statements[$catchBody.Statements.Count - 1]
Assert-Publication ($rethrowGuard -is [Management.Automation.Language.IfStatementAst] -and
    $rethrowGuard.Clauses.Count -eq 1 -and $rethrowGuard.Clauses[0].Item1.Extent.Text -ceq '-not $published') 'only a successful publication suppresses the original rethrow'
$rethrow = $rethrowGuard.Clauses[0].Item2.Statements[0]
Assert-Publication ($rethrow -is [Management.Automation.Language.ThrowStatementAst] -and $null -eq $rethrow.Pipeline) 'failed publication retains a bare original rethrow'
$diagnosticCalls = @($builderAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
    $node.GetCommandName() -ceq 'Write-SwiftUIAuditPublicationFailureDiagnostic'
}, $true))
Assert-Publication ($diagnosticCalls.Count -eq 1 -and
    $diagnosticCalls[0].Extent.StartOffset -gt $catchBody.Extent.StartOffset -and
    $diagnosticCalls[0].Extent.EndOffset -lt $catchBody.Extent.EndOffset) 'only the failure catch invokes diagnostics'
$helperLoads = @($builderAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
    $node.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Dot -and
    $node.Extent.Text.Contains('swiftui-api-audit-publication-diagnostics.ps1')
}, $true))
Assert-Publication ($helperLoads.Count -eq 1 -and $helperLoads[0].Extent.StartOffset -gt $catchBody.Extent.StartOffset -and
    $helperLoads[0].Extent.EndOffset -lt $catchBody.Extent.EndOffset) 'diagnostic helper is loaded only in the publication failure catch'
$tailStart = $guard.Extent.StartOffset
$tailEnd = $bodyStatements[$bodyStatements.Count - 1].Extent.EndOffset
$tail = $builderSource.Substring($tailStart, $tailEnd - $tailStart)
$relativeMoveStart = $moveAst.Extent.StartOffset - $tailStart
$tail = $tail.Substring(0, $relativeMoveStart) +
    'Invoke-PublicationFixtureMove -SourcePath $stagingPath -DestinationPath $outputPath' +
    $tail.Substring($relativeMoveStart + $moveAst.Extent.Text.Length)
$catchText = $catchBody.Extent.Text
$commandName = $diagnosticCalls[0].CommandElements[0].Extent
$relativeCommandStart = $commandName.StartOffset - $catchBody.Extent.StartOffset
$catchText = $catchText.Substring(0, $relativeCommandStart) + 'Invoke-PublicationFixtureDiagnostic' +
    $catchText.Substring($relativeCommandStart + $commandName.Text.Length)
# An anonymous block has no source file. Set its local script directory after
# entry so the unchanged production dot-source resolves the real helper.
$flowSource = 'Set-Variable -Name PSScriptRoot -Scope Local -Value $fixtureScriptsRoot' + [char]10 +
    [string]::Join([string][char]10, $initializers.ToArray()) + [char]10 +
    'try {' + [char]10 + $tail + [char]10 + '} catch ' + $catchText + ' finally ' + $publicationTry.Finally.Extent.Text
$flowTokens = $null; $flowErrors = $null
[void][Management.Automation.Language.Parser]::ParseInput($flowSource, [ref]$flowTokens, [ref]$flowErrors)
Assert-Publication (@($flowErrors).Count -eq 0) 'extracted production control flow parses after exactly two expression replacements'
$publicationFlow = [scriptblock]::Create($flowSource)

function Invoke-PublicationFlowCase {
    param([ValidateSet('success', 'prepublication', 'move-failure', 'diagnostic-failure', 'diagnostic-collision')][string]$Name)
    $fixture = New-PublicationFixture ('flow-' + $Name)
    $stagingPath = $fixture.Staging; $stagingLeaf = $fixture.Leaf
    $outputPath = $fixture.Destination; $outputParent = $fixture.Parent
    $manifestHash = $fixture.ManifestHash
    $publicationOwnership = New-SwiftUIAuditPublicationOwnership -StagingPath $stagingPath -OutputPath $outputPath `
        -OutputParent $outputParent -StagingLeaf $stagingLeaf
    $publication = [pscustomobject]@{ published = $false; attempts = 1; recovered = $false; failedAttemptDiagnostics = @() }
    $state = [pscustomobject]@{ Name = $Name; MoveCalls = 0; DiagnosticCalls = 0; DiagnosticInput = $null; DiagnosticPath = $null }
    if ($Name -eq 'prepublication') {
        [void][IO.Directory]::CreateDirectory($outputPath)
        [IO.File]::WriteAllText((Join-Path $outputPath 'existing.txt'), 'existing publication sentinel', $publicationUtf8)
    }
    if ($Name -eq 'diagnostic-collision') {
        [IO.File]::WriteAllText($fixture.Diagnostic, 'existing diagnostic sentinel', $publicationUtf8)
    }
    $collisionHash = if ($Name -eq 'diagnostic-collision') { Get-PublicationHash $fixture.Diagnostic } else { $null }
    function Invoke-PublicationFixtureMove {
        param([string]$SourcePath, [string]$DestinationPath)
        $state.MoveCalls++
        if ($state.Name -eq 'success') { [IO.Directory]::Move($SourcePath, $DestinationPath); return }
        # This legacy failure/diagnostic suite retains a non-retryable error.
        # The recovery suite separately exercises eligible real held-file failures.
        throw (New-PublicationError $SourcePath -HResult -2147024809)
    }
    function Invoke-PublicationFixtureDiagnostic {
        param([Management.Automation.ErrorRecord]$ErrorRecord, [string]$StagingPath, [string]$OutputPath,
            [string]$OutputParent, [string]$StagingLeaf, [string]$ManifestSha256, [string]$AttemptedAtUTC)
        $state.DiagnosticCalls++
        $state.DiagnosticInput = $ErrorRecord
        if ($state.Name -eq 'diagnostic-failure') { throw [UnauthorizedAccessException]::new('Synthetic diagnostic failure.') }
        $state.DiagnosticPath = Write-SwiftUIAuditPublicationFailureDiagnostic @PSBoundParameters
        return $state.DiagnosticPath
    }
    $caught = $null
    try { . $publicationFlow } catch { $caught = $_ }
    $expectedMoves = if ($Name -eq 'prepublication') { 0 } else { 1 }
    $expectedDiagnostics = if ($Name -in @('success', 'prepublication')) { 0 } else { 1 }
    Assert-Publication ($state.MoveCalls -eq $expectedMoves) "$Name invokes Move no more than once"
    Assert-Publication ($state.DiagnosticCalls -eq $expectedDiagnostics) "$Name has exactly the expected diagnostic call count"
    Assert-Publication (-not [IO.Directory]::Exists($stagingPath)) "$Name retains the original staging cleanup behavior"
    if ($Name -eq 'success') {
        Assert-Publication ($null -eq $caught -and $published) 'successful move returns without a diagnostic error'
        Assert-Publication ((Get-PublicationHash (Join-Path $outputPath 'audit.json')) -ceq $manifestHash) 'successful publication retains staged manifest bytes'
    } else {
        Assert-Publication ($null -ne $caught -and -not $published) "$Name still fails publication"
    }
    if ($Name -eq 'prepublication') {
        Assert-Publication (-not $publicationAttempted) 'prepublication guard does not mark Move attempted'
        Assert-Publication (([IO.File]::ReadAllText((Join-Path $outputPath 'existing.txt'))) -ceq 'existing publication sentinel') 'prepublication guard preserves existing output'
    }
    $sameRecord = $null
    if ($expectedDiagnostics -eq 1) {
        $original = $state.DiagnosticInput
        Assert-Publication ($null -ne $original) 'diagnostic received the actual ErrorRecord captured by the builder catch'
        Assert-Publication ([Object]::ReferenceEquals($caught.Exception, $original.Exception)) "$Name preserves the original exception object"
        Assert-Publication ($caught.Exception.HResult -eq $original.Exception.HResult) "$Name preserves original HRESULT"
        Assert-Publication ($caught.FullyQualifiedErrorId -ceq $original.FullyQualifiedErrorId) "$Name preserves original FullyQualifiedErrorId"
        Assert-Publication ($caught.CategoryInfo.Category -eq $original.CategoryInfo.Category -and
            $caught.CategoryInfo.Reason -ceq $original.CategoryInfo.Reason) "$Name preserves original error category"
        Assert-Publication ([Object]::Equals($caught.TargetObject, $original.TargetObject)) "$Name preserves original TargetObject"
        $sameRecord = [Object]::ReferenceEquals($caught, $original)
    }
    $diagnosticFiles = @(Get-ChildItem -LiteralPath $fixture.Parent -Force -File -Filter '*.publication-failure.json')
    if ($Name -eq 'move-failure') {
        Assert-Publication ($diagnosticFiles.Count -eq 1 -and $state.DiagnosticPath -ceq $fixture.Diagnostic) 'failed Move creates one sibling diagnostic'
        $report = Read-PublicationDiagnostic $fixture.Diagnostic
        Assert-Publication ($report.paths.staging.directoryExists -and -not $report.paths.destination.directoryExists) 'failed Move diagnostic observes staging before finally removes it'
        Assert-Publication (@($report.exceptions)[0].hresult -eq $state.DiagnosticInput.Exception.HResult) 'failed Move diagnostic records original HRESULT'
        Assert-Publication (-not $report.publicationSucceeded -and -not $report.failureCauseEstablished) 'synthetic failed Move does not establish a native cause'
    } elseif ($Name -eq 'diagnostic-collision') {
        Assert-Publication ($diagnosticFiles.Count -eq 1 -and (Get-PublicationHash $fixture.Diagnostic) -ceq $collisionHash) 'diagnostic collision preserves sentinel bytes'
    } else {
        Assert-Publication ($diagnosticFiles.Count -eq 0) "$Name leaves no unexpected diagnostic artifact"
    }
    return [pscustomobject][ordered]@{
        name = $Name; moveCalls = $state.MoveCalls; diagnosticCalls = $state.DiagnosticCalls
        publicationSucceeded = [bool]$published; originalErrorRecordIdentityObserved = $sameRecord
        originalFailurePreserved = ($expectedDiagnostics -eq 1)
        stagingExistsAfterFinally = [IO.Directory]::Exists($stagingPath)
        diagnosticFileCount = $diagnosticFiles.Count
    }
}

$caseResults = [Collections.Generic.List[object]]::new()
foreach ($name in @('success', 'prepublication', 'move-failure', 'diagnostic-failure', 'diagnostic-collision')) {
    $caseResults.Add((Invoke-PublicationFlowCase $name))
}

# Exactly one unchanged existing ledger suite per invocation, in this owned root.
$ledgerRoot = Join-Path $OutputRoot 'existing-ledger'
& $ledgerTestPath -RepositoryRoot $RepositoryRoot -OutputRoot $ledgerRoot | Out-Null
$ledgerReport = [IO.File]::ReadAllText((Join-Path $ledgerRoot 'test-results.json'), $publicationUtf8) | ConvertFrom-Json
Assert-Publication ($ledgerReport.evidenceKind -ceq 'synthetic-api-audit-tooling-tests-only') 'existing ledger suite completed with its original evidence kind'
Assert-Publication ([int]$ledgerReport.assertions -ge 391) 'existing ledger suite retained at least its 391 baseline assertions'
Assert-Publication (-not $ledgerReport.nativeExportPerformed -and -not $ledgerReport.behaviorConformanceAssessed) 'existing ledger suite remains synthetic only'
$ledgerDiagnostics = @(Get-ChildItem -LiteralPath $ledgerRoot -File -Force -Recurse -Filter '*.publication-failure*.json')
Assert-Publication (@($ledgerReport.publicationResults).Count -eq 2) 'both real ledger publications report their actual recovery state'
$reportedLedgerDiagnostics = @($ledgerReport.publicationResults | ForEach-Object { $_.failedAttemptDiagnostics })
Assert-Publication ($ledgerDiagnostics.Count -eq $reportedLedgerDiagnostics.Count) 'ledger diagnostics exist only for reported failed publication attempts, never prepublication rejection'
foreach ($diagnostic in $ledgerDiagnostics) {
    Assert-Publication ($diagnostic.FullName -cin $reportedLedgerDiagnostics) 'each retained ledger diagnostic belongs to a reported failed attempt'
}
foreach ($path in $sourcePins.Keys) {
    Assert-Publication ((Get-PublicationHash $path) -ceq $sourcePins[$path]) 'production and fixture source bytes remain unchanged'
}
$summary = [ordered]@{
    schemaVersion = 1; evidenceKind = 'synthetic-api-audit-publication-diagnostics-tests-only'
    assertions = $script:PublicationAssertions; powerShellVersion = $PSVersionTable.PSVersion.ToString()
    outputRoot = $OutputRoot; sourceSha256 = $sourcePins; cases = $caseResults.ToArray()
    existingLedgerInvocations = 1; existingLedgerAssertions = [int]$ledgerReport.assertions
    existingLedgerReportSha256 = Get-PublicationHash (Join-Path $ledgerRoot 'test-results.json')
    sharingViolationReproduced = $false; nativeExportPerformed = $false; behaviorConformanceAssessed = $false
    limits = 'Synthetic exceptions exercise diagnostic control flow; they do not reproduce or explain the original Directory.Move failure.'
}
Write-SwiftUIBaselineJson -Value $summary -Path (Join-Path $OutputRoot 'test-results.json')
Write-Host "API audit publication diagnostic tests passed $($script:PublicationAssertions) assertions plus $($ledgerReport.assertions) existing ledger assertions on PowerShell $($PSVersionTable.PSVersion.ToString())."
Write-Host "Evidence: $OutputRoot"
