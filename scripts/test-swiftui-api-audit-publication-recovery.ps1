<#
.SYNOPSIS
Tests bounded audit publication recovery using only owned synthetic files.
#>
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot), [string]$OutputRoot)
$ErrorActionPreference = 'Stop'
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
if ($RepositoryRoot -cne (Split-Path -Parent $PSScriptRoot)) { throw 'Use the repository containing this fixture script.' }
$artifacts = Join-Path $RepositoryRoot 'artifacts'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $artifacts ('swiftui-api-audit-publication-recovery-tests/' + [Guid]::NewGuid().ToString('N'))
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (-not $OutputRoot.StartsWith($artifacts + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $OutputRoot)) { throw 'Publication recovery fixtures require new output below owned artifacts.' }
for ($ancestor = $OutputRoot; -not [string]::IsNullOrEmpty($ancestor); $ancestor = [IO.Path]::GetDirectoryName($ancestor)) {
    if ((Test-Path -LiteralPath $ancestor) -and
        ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Publication recovery fixture paths must not traverse reparse points.'
    }
}
[void][IO.Directory]::CreateDirectory($OutputRoot)
$fixtureScriptsRoot = $PSScriptRoot
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:RecoveryAssertions = 0
function Assert-Recovery {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw "Publication recovery assertion failed: $Message" }
    $script:RecoveryAssertions++
}
function Get-RecoveryHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
$sourcePins = [ordered]@{}
foreach ($name in @('build-swiftui-api-audit.ps1', 'swiftui-api-audit-publication.ps1',
        'swiftui-api-audit-publication-diagnostics.ps1', 'test-swiftui-api-audit-publication-recovery.ps1')) {
    $sourcePins[$name] = Get-RecoveryHash (Join-Path $PSScriptRoot $name)
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name), [ref]$tokens, [ref]$errors)
    Assert-Recovery (@($errors).Count -eq 0) "$name parses"
}
. (Join-Path $PSScriptRoot 'swiftui-baseline-common.ps1')
. (Join-Path $PSScriptRoot 'swiftui-api-audit-publication.ps1')
. (Join-Path $PSScriptRoot 'swiftui-api-audit-publication-diagnostics.ps1')

# The exact allowlist is independently exercised without inducing other OS errors.
$classificationCases = @(
    [pscustomobject]@{ name = 'access-denied'; error = [IO.IOException]::new('synthetic', -2147024891); expected = $true },
    [pscustomobject]@{ name = 'sharing-violation'; error = [IO.IOException]::new('synthetic', -2147024864); expected = $true },
    [pscustomobject]@{ name = 'unauthorized-access'; error = [UnauthorizedAccessException]::new('synthetic'); expected = $true },
    [pscustomobject]@{ name = 'lock-violation-not-allowlisted'; error = [IO.IOException]::new('synthetic', -2147024863); expected = $false },
    [pscustomobject]@{ name = 'invalid-parameter'; error = [IO.IOException]::new('synthetic', -2147024809); expected = $false },
    [pscustomobject]@{ name = 'unknown-io'; error = [IO.IOException]::new('synthetic'); expected = $false },
    [pscustomobject]@{ name = 'unclassified-io-wrapper'; error = [IO.IOException]::new('synthetic', [IO.IOException]::new('synthetic', -2147024891)); expected = $false },
    [pscustomobject]@{ name = 'native-wrapper-not-allowlisted'; error = [ComponentModel.Win32Exception]::new(32); expected = $false },
    [pscustomobject]@{ name = 'unrelated-outer'; error = [InvalidOperationException]::new('synthetic', [IO.IOException]::new('synthetic', -2147024864)); expected = $false }
)
$wrapped = [Management.Automation.MethodInvocationException]::new('synthetic', [IO.IOException]::new('synthetic', -2147024891))
$classificationCases += [pscustomobject]@{ name = 'powershell-wrapper'; error = $wrapped; expected = $true }
for ($index = 0; $index -lt 8; $index++) { $wrapped = [IO.IOException]::new('synthetic', $wrapped) }
$classificationCases += [pscustomobject]@{ name = 'truncated-chain'; error = $wrapped; expected = $false }
foreach ($case in $classificationCases) {
    $record = [Management.Automation.ErrorRecord]::new($case.error, 'SyntheticClassification',
        [Management.Automation.ErrorCategory]::WriteError, $null)
    Assert-Recovery ((Test-SwiftUIAuditPublicationRetryableError $record) -eq $case.expected) "$($case.name) uses the exact HRESULT/type allowlist"
}
$withoutOwnership = Complete-SwiftUIAuditPublicationAfterFailure -Ownership $null `
    -OriginalError ([Management.Automation.ErrorRecord]::new([IO.IOException]::new('synthetic', -2147024891),
        'SyntheticMissingOwnership', [Management.Automation.ErrorCategory]::WriteError, $null)) `
    -FirstDiagnosticPath (Join-Path $OutputRoot 'synthetic-already-recorded-first-attempt.json') -ManifestSha256 ('0' * 64)
Assert-Recovery (-not $withoutOwnership.published -and $withoutOwnership.attempts -eq 1 -and
    $withoutOwnership.stopReason -ceq 'unsupported-ownership') 'missing ownership never enables a retry even for an eligible HRESULT'
Assert-Recovery (@($withoutOwnership.retryDelaysMilliseconds).Count -eq 0) 'missing ownership schedules no retry delay'

# Execute the unmodified production publication tail, catch, finally, reporting,
# and returned publication object. Only
# the test-local Start-Sleep command is wrapped, to release or alter owned files
# after a real failed Move and before the next check. All Move calls are real.
$builderPath = Join-Path $PSScriptRoot 'build-swiftui-api-audit.ps1'
$builderSource = [IO.File]::ReadAllText($builderPath, $utf8)
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($builderSource, [ref]$tokens, [ref]$errors)
$moves = @($ast.FindAll({ param($node)
    $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Static -and
    $node.Expression -is [Management.Automation.Language.TypeExpressionAst] -and
    $node.Expression.TypeName.FullName -ceq 'System.IO.Directory' -and $node.Member.Extent.Text -ceq 'Move'
}, $true))
Assert-Recovery ($moves.Count -eq 1) 'builder has exactly one original Move expression'
$publicationTry = $moves[0].Parent
while ($publicationTry -isnot [Management.Automation.Language.TryStatementAst]) { $publicationTry = $publicationTry.Parent }
$statements = @($publicationTry.Body.Statements)
$guard = $statements[$statements.Count - 5]
Assert-Recovery ($guard -is [Management.Automation.Language.IfStatementAst] -and
    $guard.Extent.Text.Contains('never overwritten')) 'unchanged destination guard begins the production publication tail'
$tail = $builderSource.Substring($guard.Extent.StartOffset,
    $statements[-1].Extent.EndOffset - $guard.Extent.StartOffset)
$initializers = @($ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.AssignmentStatementAst] -and
    $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and
    $_.Left.VariablePath.UserPath -cin @('failure', 'published', 'publicationAttempted', 'publicationAttemptedAtUTC')
})
Assert-Recovery ($initializers.Count -eq 4) 'all original publication/error initializers are retained'
$flowText = 'Set-Variable -Name PSScriptRoot -Scope Local -Value $fixtureScriptsRoot' + [char]10 +
    [string]::Join([string][char]10, [string[]]@($initializers | ForEach-Object { $_.Extent.Text })) + [char]10 +
    'try {' + [char]10 + $tail + [char]10 + '} catch ' + $publicationTry.CatchClauses[0].Body.Extent.Text +
    ' finally ' + $publicationTry.Finally.Extent.Text +
    $builderSource.Substring($publicationTry.Extent.EndOffset)
[void][Management.Automation.Language.Parser]::ParseInput($flowText, [ref]$tokens, [ref]$errors)
Assert-Recovery (@($errors).Count -eq 0) 'unmodified production publication control flow parses in the fixture'
$flow = [scriptblock]::Create($flowText)
[IO.File]::WriteAllText((Join-Path $OutputRoot 'extracted-publication-flow.ps1'), $flowText, $utf8)

function Invoke-RecoveryFixture {
    [CmdletBinding()]
    param([string]$Name, [switch]$StopWarningPreference)
    $caseName = $Name
    if ($StopWarningPreference) {
        $WarningPreference = 'Stop'
        $caseName += '-warning-preference-stop'
    } elseif ($PSBoundParameters.ContainsKey('WarningAction') -and $PSBoundParameters.WarningAction -eq 'Stop') {
        $caseName += '-warning-action-stop'
    }
    $parent = Join-Path $OutputRoot $caseName
    [void][IO.Directory]::CreateDirectory($parent)
    $stagingLeaf = '.swiftui-api-audit-' + [Guid]::NewGuid().ToString('N')
    $stagingPath = Join-Path $parent $stagingLeaf
    $outputPath = Join-Path $parent 'published'; $outputParent = $parent
    [void][IO.Directory]::CreateDirectory($stagingPath)
    $manifestText = '{"syntheticPublicationRecoveryFixture":true}' + [char]10
    [IO.File]::WriteAllText((Join-Path $stagingPath 'audit.json'), $manifestText, $utf8)
    $manifestHash = Get-RecoveryHash (Join-Path $stagingPath 'audit.json')
    $sealText = $manifestHash + '  audit.json' + [char]10
    [IO.File]::WriteAllText((Join-Path $stagingPath 'audit.sha256'), $sealText, $utf8)
    [IO.File]::WriteAllText((Join-Path $stagingPath 'held.txt'), 'owned file-lock fixture', $utf8)
    $publicationOwnership = New-SwiftUIAuditPublicationOwnership -StagingPath $stagingPath -OutputPath $outputPath `
        -OutputParent $parent -StagingLeaf $stagingLeaf
    $publication = [pscustomobject]@{ published = $false; attempts = 1; recovered = $false; failedAttemptDiagnostics = @() }
    # Only the already-produced ledger metadata is synthetic. The builder's
    # reporting and return expressions below are executed without substitution.
    $result = [pscustomobject]@{ Inventory = [pscustomobject]@{ PreciseSymbols = 0 } }
    $manifest = [pscustomobject]@{ counts = [pscustomobject]@{ preciseIdentifiers = 0 } }
    $state = [pscustomobject]@{ name = $Name; held = $null; delays = [Collections.Generic.List[int]]::new()
        parked = (Join-Path $parent 'original-staging'); changedAfterFailure = $false }
    $collision = $null; $collisionHash = $null
    if ($Name -in @('first-receipt-collision', 'second-receipt-collision', 'recovery-receipt-collision')) {
        $suffix = switch ($Name) {
            'first-receipt-collision' { '.publication-failure.json' }
            'second-receipt-collision' { '.publication-failure-2.json' }
            'recovery-receipt-collision' { '.publication-recovery.json' }
        }
        $collision = Join-Path $parent ($stagingLeaf + $suffix)
        [IO.File]::WriteAllText($collision, 'existing immutable diagnostic sentinel', $utf8)
        $collisionHash = Get-RecoveryHash $collision
    }
    if ($Name -eq 'other-real-error') {
        [IO.Directory]::Move($stagingPath, $state.parked)
    } elseif ($Name -ne 'first-attempt-success') {
        $state.held = [IO.File]::Open((Join-Path $stagingPath 'held.txt'), [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    }
    function Start-Sleep {
        param([int]$Milliseconds)
        $state.delays.Add($Milliseconds)
        if ($state.name -in @('recover-second', 'destination-directory-appears', 'destination-file-appears',
                'staging-substituted', 'staging-reparse', 'manifest-changed', 'seal-changed', 'recovery-receipt-collision') -or
            ($state.name -eq 'recover-third' -and $state.delays.Count -eq 2)) {
            if ($null -ne $state.held) { $state.held.Dispose(); $state.held = $null }
        }
        switch ($state.name) {
            'destination-directory-appears' {
                [void][IO.Directory]::CreateDirectory($outputPath)
                [IO.File]::WriteAllText((Join-Path $outputPath 'sentinel.txt'), 'do not overwrite', $utf8)
            }
            'destination-file-appears' { [IO.File]::WriteAllText($outputPath, 'do not overwrite', $utf8) }
            'staging-substituted' {
                $originalCreation = [IO.Directory]::GetCreationTimeUtc($stagingPath)
                [IO.Directory]::Move($stagingPath, $state.parked)
                [void][IO.Directory]::CreateDirectory($stagingPath)
                [IO.Directory]::SetCreationTimeUtc($stagingPath, $originalCreation)
                # Matching manifest and seal bytes cannot make a new directory owned.
                [IO.File]::WriteAllText((Join-Path $stagingPath 'audit.json'), $manifestText, $utf8)
                [IO.File]::WriteAllText((Join-Path $stagingPath 'audit.sha256'), $sealText, $utf8)
                [IO.File]::WriteAllText((Join-Path $stagingPath 'foreign.txt'), 'do not remove', $utf8)
            }
            'staging-reparse' {
                [IO.Directory]::Move($stagingPath, $state.parked)
                [void](New-Item -ItemType Junction -Path $stagingPath -Value $state.parked -ErrorAction Stop)
            }
            'manifest-changed' { [IO.File]::AppendAllText((Join-Path $stagingPath 'audit.json'), 'changed', $utf8) }
            'seal-changed' { [IO.File]::WriteAllText((Join-Path $stagingPath 'audit.sha256'), ('0' * 64) + '  audit.json' + [char]10, $utf8) }
        }
        $state.changedAfterFailure = $true
        Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds $Milliseconds
    }
    $caught = $null; $outputRecords = @()
    try { $outputRecords = @(. $flow 3>&1) } catch { $caught = $_ }
    finally { if ($null -ne $state.held) { $state.held.Dispose(); $state.held = $null } }
    $warnings = @($outputRecords | Where-Object { $_ -is [Management.Automation.WarningRecord] })
    $returned = @($outputRecords | Where-Object { $_ -isnot [Management.Automation.WarningRecord] })
    $success = $Name -in @('first-attempt-success', 'recover-second', 'recover-third', 'recovery-receipt-collision')
    $expectedAttempts = switch ($Name) {
        'recover-third' { 3 }; 'persistent-lock' { 3 }
        'recover-second' { 2 }; 'second-receipt-collision' { 2 }; 'recovery-receipt-collision' { 2 }
        default { 1 }
    }
    $returnObservation = [ordered]@{
        scenario = $caseName; expectedPublicationSuccess = $success; actualPublishedFlag = [bool]$published
        warningPreference = [string]$WarningPreference
        explicitFixtureWarningAction = if ($PSBoundParameters.ContainsKey('WarningAction')) { [string]$PSBoundParameters.WarningAction } else { $null }
        returnedObjectCount = $returned.Count; warningRecordCount = $warnings.Count
        caughtException = if ($null -ne $caught) { Get-SwiftUIAuditPublicationExceptionFacts -Exception $caught.Exception } else { $null }
    }
    Write-SwiftUIBaselineJson -Value $returnObservation -Path (Join-Path $parent ($stagingLeaf + '.publication-return-observation.json'))
    Assert-Recovery ($published -eq $success -and ($null -eq $caught) -eq $success) "$caseName reports the actual publication outcome through post-finally reporting"
    Assert-Recovery ($publication.attempts -eq $expectedAttempts) "$Name never exceeds its expected Move count"
    Assert-Recovery ($state.delays.Count -le 2 -and ($state.delays.Count -eq 0 -or $state.delays[0] -eq 25) -and
        ($state.delays.Count -lt 2 -or $state.delays[1] -eq 100)) "$Name uses only the fixed 25ms/100ms delays"
    if ($Name -in @('first-attempt-success', 'other-real-error', 'first-receipt-collision')) {
        Assert-Recovery ($state.delays.Count -eq 0) "$Name does not start a retry delay"
    }
    $firstFacts = $null
    if ($Name -ne 'first-attempt-success') {
        $firstFacts = Get-SwiftUIAuditPublicationExceptionFacts -Exception $failure.Exception
        if ($Name -ne 'other-real-error') {
            Assert-Recovery (-not $firstFacts.truncated -and @($firstFacts.chain)[-1].hresultHex -cin @('0x80070005', '0x80070020')) "$Name observes a real held-file Move error in the exact retry allowlist"
        }
    }
    if ($success) {
        Assert-Recovery ($returned.Count -eq 1 -and $returned[0].publication.published -and
            $returned[0].publication.recovered -eq $publication.recovered -and
            $returned[0].publication.attempts -eq $expectedAttempts) "$caseName returns exactly one truthful publication object"
        Assert-Recovery ($returned[0].path -ceq $outputPath -and $returned[0].manifestSha256 -ceq $manifestHash -and
            $returned[0].reviewStatus -ceq 'unreviewed') "$caseName returns the actual output and unchanged audit qualification"
        Assert-Recovery ((Get-RecoveryHash (Join-Path $outputPath 'audit.json')) -ceq $manifestHash) "$Name publishes unchanged manifest bytes"
        Assert-Recovery (-not [IO.Directory]::Exists($stagingPath)) "$Name uses a rename, with no leftover staging copy"
        Assert-Recovery ($publication.recovered -eq ($Name -ne 'first-attempt-success')) "$Name distinguishes a recovered publication"
    } else {
        Assert-Recovery ($returned.Count -eq 0) "$caseName does not return a successful publication after failure"
        Assert-Recovery ($null -ne $failure) "$Name retains the first ErrorRecord"
        $originalException = $caught.Exception
        if ($originalException -is [AggregateException]) {
            Assert-Recovery ($originalException.InnerExceptions.Count -eq 2) "$Name aggregates original publication and cleanup errors"
            $originalException = $originalException.InnerExceptions[0]
        } else {
            Assert-Recovery ($caught.FullyQualifiedErrorId -ceq $failure.FullyQualifiedErrorId -and
                $caught.CategoryInfo.Category -eq $failure.CategoryInfo.Category -and
                [Object]::Equals($caught.TargetObject, $failure.TargetObject)) "$Name preserves the first error identity fields"
        }
        Assert-Recovery ([Object]::ReferenceEquals($originalException, $failure.Exception)) "$Name preserves the original exception object"
    }
    $diagnostics = @(Get-ChildItem -LiteralPath $parent -File -Filter '*.publication-failure*.json')
    $failedAttempts = if ($success) { $expectedAttempts - 1 } else { $expectedAttempts }
    Assert-Recovery ($diagnostics.Count -eq $failedAttempts) "$Name retains every failed-attempt path without overwriting collisions"
    $observations = [Collections.Generic.List[object]]::new()
    foreach ($file in $diagnostics) {
        if ($file.FullName -ceq $collision) { continue }
        Assert-Recovery ($file.Length -le 256KB) "$Name bounds each failed-attempt diagnostic"
        $receipt = [IO.File]::ReadAllText($file.FullName, $utf8) | ConvertFrom-Json
        Assert-Recovery (-not $receipt.publicationSucceeded -and -not $receipt.failureCauseEstablished) "$Name does not erase failed attempts or infer a historical cause"
        Assert-Recovery ($receipt.auditManifestSha256 -ceq $manifestHash) "$Name keeps the original manifest digest in each receipt"
        $observations.Add([ordered]@{ attempt = $receipt.attemptNumber; path = $file.FullName
            sha256 = Get-RecoveryHash $file.FullName; exceptions = $receipt.exceptions })
    }
    if ($Name -eq 'other-real-error') {
        Assert-Recovery ($publication.stopReason -ceq 'non-retryable-error') 'a real missing-staging error is not retried'
    }
    if ($Name -in @('destination-directory-appears', 'destination-file-appears', 'staging-substituted', 'staging-reparse', 'manifest-changed', 'seal-changed')) {
        Assert-Recovery ($state.changedAfterFailure -and $publication.stopReason -ceq 'retry-validation-failed' -and
            $publication.attempts -eq 1) "$Name is rejected after the first failure and before another Move"
        Assert-Recovery ($null -ne $publication.validationError) "$Name retains the refusal's exception facts separately from the original error"
    }
    if ($Name -eq 'destination-directory-appears') {
        Assert-Recovery ([IO.File]::ReadAllText((Join-Path $outputPath 'sentinel.txt')) -ceq 'do not overwrite') 'appearing destination directory is never overwritten'
    }
    if ($Name -eq 'destination-file-appears') {
        Assert-Recovery ([IO.File]::ReadAllText($outputPath) -ceq 'do not overwrite') 'appearing destination file is never overwritten'
    }
    if ($Name -eq 'staging-substituted') {
        Assert-Recovery ([IO.Directory]::GetCreationTimeUtc($stagingPath) -eq [IO.Directory]::GetCreationTimeUtc($state.parked)) 'substitution is rejected despite matching directory creation times'
        Assert-Recovery ([IO.File]::ReadAllText((Join-Path $stagingPath 'foreign.txt')) -ceq 'do not remove') 'substituted staging survives cleanup refusal'
        Assert-Recovery ((Get-RecoveryHash (Join-Path $state.parked 'audit.json')) -ceq $manifestHash) 'original staging is preserved at its moved path'
    }
    if ($Name -eq 'staging-reparse') {
        Assert-Recovery (([IO.File]::GetAttributes($stagingPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'reparse staging is not followed during cleanup'
        Assert-Recovery ((Get-RecoveryHash (Join-Path $state.parked 'audit.json')) -ceq $manifestHash) 'junction target bytes are preserved'
        Assert-Recovery ((Resolve-SwiftUIBaselineFileSystemPath $stagingPath) -ceq $state.parked -and
            [IO.Path]::GetDirectoryName($stagingPath) -ceq $parent -and
            [IO.Path]::GetDirectoryName($state.parked) -ceq $parent) 'fixture junction and target stay in this owned case directory'
        # Remove only our link after observing the production refusal, never its target.
        [IO.Directory]::Delete($stagingPath)
        Assert-Recovery ([IO.Directory]::Exists($state.parked)) 'fixture link removal leaves the target directory intact'
    }
    if ($null -ne $collision) { Assert-Recovery ((Get-RecoveryHash $collision) -ceq $collisionHash) "$Name preserves preexisting receipt bytes" }
    if ($Name -eq 'second-receipt-collision') {
        Assert-Recovery ($publication.stopReason -ceq 'failed-attempt-diagnostic-unavailable' -and
            @($publication.failedAttempts).Count -eq 2) 'failed second receipt stops retries and keeps both failed Move exception observations'
    }
    if ($Name -eq 'recovery-receipt-collision') {
        Assert-Recovery ($null -ne $publication.outcomeDiagnosticError -and $null -eq $publication.outcomeDiagnostic) 'a recovery summary collision is separate from the successful rename'
        Assert-Recovery ($warnings.Count -eq 1 -and $null -ne $returned[0].publication.outcomeDiagnosticError) "$caseName emits one non-terminating warning and returns the summary error"
        if ($StopWarningPreference -or $PSBoundParameters.ContainsKey('WarningAction')) {
            Assert-Recovery ($WarningPreference -eq 'Stop') "$caseName executes reporting with the requested stop-on-warning policy intact"
        }
    } elseif ($null -ne $publication.outcomeDiagnostic) {
        $summary = [IO.File]::ReadAllText($publication.outcomeDiagnostic, $utf8) | ConvertFrom-Json
        Assert-Recovery ($summary.publicationSucceeded -eq $published -and $summary.recovered -eq $publication.recovered -and
            $summary.attempts -eq $expectedAttempts -and -not $summary.failureCauseEstablished) "$Name preserves the recovery decision without inventing a cause"
        Assert-Recovery (@($summary.failedAttempts).Count -eq $failedAttempts) "$Name recovery receipt retains all failed Move exception observations"
    }
    $disposed = $false
    try { $publicationOwnership.ParentIdentity.AssertCurrent($parent) } catch { $disposed = $true }
    Assert-Recovery $disposed "$Name disposes the directory ownership pins even on cleanup failure"
    return [ordered]@{ name = $caseName; publicationSucceeded = [bool]$published; attempts = $publication.attempts
        recovered = [bool]$publication.recovered; requestedDelaysMilliseconds = $state.delays.ToArray()
        stopReason = $publication.stopReason; failedAttemptObservations = $observations.ToArray(); firstFailedMove = $firstFacts
        outcomeDiagnostic = $publication.outcomeDiagnostic; originalFailurePreserved = (-not $success)
        returnedObjectCount = $returned.Count; warningRecordCount = $warnings.Count; warningPreference = [string]$WarningPreference }
}

$cases = [Collections.Generic.List[object]]::new()
$windows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if ($windows) {
    foreach ($name in @('first-attempt-success', 'recover-second', 'recover-third', 'persistent-lock',
            'other-real-error', 'destination-directory-appears', 'destination-file-appears',
            'staging-substituted', 'staging-reparse', 'manifest-changed', 'seal-changed', 'first-receipt-collision',
            'second-receipt-collision', 'recovery-receipt-collision')) {
        $cases.Add((Invoke-RecoveryFixture $name))
    }
    $cases.Add((Invoke-RecoveryFixture 'recovery-receipt-collision' -StopWarningPreference))
    $cases.Add((Invoke-RecoveryFixture 'recovery-receipt-collision' -WarningAction Stop))
}
foreach ($name in $sourcePins.Keys) {
    Assert-Recovery ((Get-RecoveryHash (Join-Path $fixtureScriptsRoot $name)) -ceq $sourcePins[$name]) 'source bytes remain unchanged during fixtures'
}
$report = [ordered]@{
    schemaVersion = 1; evidenceKind = 'synthetic-api-audit-publication-recovery-tests-only'
    assertions = $script:RecoveryAssertions; powerShellVersion = $PSVersionTable.PSVersion.ToString()
    outputRoot = $OutputRoot; sourceSha256 = $sourcePins; classifierCases = $classificationCases.Count
    windowsFileIdentityAndHeldFileCasesExecuted = $windows; cases = $cases.ToArray()
    realAuditFailureCauseEstablished = $false; nativeExportPerformed = $false; behaviorConformanceAssessed = $false
    limits = 'Owned file locks reproduce one mechanism, not the cause of historical failures. Windows-only rename recovery; filesystem operations have no hard wall-clock guarantee.'
}
Write-SwiftUIBaselineJson -Value $report -Path (Join-Path $OutputRoot 'test-results.json')
Write-Host "API audit publication recovery tests passed $($script:RecoveryAssertions) assertions; Windows held-file cases executed: $windows."
Write-Host "Evidence: $OutputRoot"
$global:LASTEXITCODE = 0
