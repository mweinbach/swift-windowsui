<#
.SYNOPSIS
    Runs the synthetic CI font fixtures inside the agent-check caller shape.
.DESCRIPTION
    Invoke-Step -> command scriptblock -> test script stays in this process.
    No helper is installed globally and no compiler, renderer, or child process
    is invoked. The fixture script supplies fake source/process/font boundaries.
#>
param([string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ('swift-windowsui-ci-bitmap-scope-' + [Guid]::NewGuid().ToString('N'))))

$ErrorActionPreference = 'Stop'
$scopeOutput = [IO.Path]::GetFullPath($WorkDir)
if (Test-Path -LiteralPath $scopeOutput) { throw 'Scope regression output must be new; existing evidence is never overwritten.' }
[void][IO.Directory]::CreateDirectory($scopeOutput)
$scopeFixtureScript = Join-Path $PSScriptRoot 'test-ci-bitmap-font-attribution.ps1'
$scopeFixtureOutput = Join-Path $scopeOutput 'fixtures'
$scopeHelpers = @('Assert-CiTest', 'Write-CiTestJson', 'Write-CiTestBytes', 'Read-CiBitmapJson', 'Receive-CiBitmapStreams', 'Get-CiBitmapSource', 'Add-Type')
$scopeCallerBindings = @{}
foreach ($name in $scopeHelpers) {
    $command = Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue
    $scopeCallerBindings[$name] = if ($null -ne $command) { $command.ScriptBlock } else { $null }
}

function Get-ReportedExitCode {
    if ($null -eq $LASTEXITCODE) {
        return $null
    }
    return [int]$LASTEXITCODE
}

# Keep the relevant nesting and exit handling identical to agent-check.ps1.
# Calling the fixture directly with native -File does not exercise this scope.
function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Command
    $code = Get-ReportedExitCode
    if ($null -eq $code) {
        Write-Host "Step failed: $Name (no exit code reported)" -ForegroundColor Red
        exit 1
    }
    if ($code -ne 0) {
        Write-Host "Step failed: $Name (exit code $code)" -ForegroundColor Red
        exit $code
    }
    Write-Host "Step passed: $Name" -ForegroundColor Green
}

Invoke-Step 'CI bitmap fixtures inside function and command scriptblock' {
    & $scopeFixtureScript -WorkDir $scopeFixtureOutput
}
foreach ($name in $scopeHelpers) {
    $command = Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue
    $after = if ($null -ne $command) { $command.ScriptBlock } else { $null }
    if (-not [object]::ReferenceEquals($scopeCallerBindings[$name], $after)) { throw 'The fixture leaked or replaced a helper in its caller scope.' }
}

$scopeReceiptPath = Join-Path $scopeFixtureOutput 'test-results.json'
$scopeReceipt = Get-Content -LiteralPath $scopeReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($scopeReceipt.status -cne 'pass' -or $scopeReceipt.failed -ne 0 -or $scopeReceipt.total -lt 103 -or
    $scopeReceipt.total -ne @($scopeReceipt.tests).Count -or @($scopeReceipt.tests | Where-Object { $_.status -cne 'pass' }).Count -ne 0) {
    throw 'Embedded fixtures did not preserve the complete passing synthetic suite.'
}
$scopeResult = [ordered]@{
    schemaVersion = 1; kind = 'ci-bitmap-font-caller-scope-regression'; status = 'pass'
    powershellVersion = $PSVersionTable.PSVersion.ToString(); invocation = 'Invoke-Step -> command scriptblock -> fixture script; same process'
    fixtureSha256 = (Get-FileHash -LiteralPath $scopeFixtureScript -Algorithm SHA256).Hash.ToLowerInvariant()
    receipt = 'fixtures/test-results.json'; receiptSha256 = (Get-FileHash -LiteralPath $scopeReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    fixtureCount = $scopeReceipt.total; failed = 0; callerBindingsUnchanged = $true
    childProcess = $false; nativeRenderer = $false; swiftPM = $false; qualification = 'unqualified'
}
$scopeBytes = [Text.UTF8Encoding]::new($false).GetBytes(($scopeResult | ConvertTo-Json -Depth 4) + "`n")
$scopeStream = [IO.File]::Open((Join-Path $scopeOutput 'scope-results.json'), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $scopeStream.Write($scopeBytes, 0, $scopeBytes.Length) } finally { $scopeStream.Dispose() }
Write-Host "Embedded CI bitmap scope regression passed ($($scopeReceipt.total) fixtures; same process)."
exit 0
