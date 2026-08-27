<#
.SYNOPSIS
Tests lint file selection with synthetic files and fake tooling only.
#>
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = "Stop"
$script:lintAssertions = 0
$script:lintCases = 0
$script:lintFailures = New-Object 'System.Collections.Generic.List[string]'
$lintEncoding = New-Object System.Text.UTF8Encoding($false)
$lintTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('/', '\'))
$lintFixture = Join-Path $lintTemp ("swift-windowsui-lint-test-" + [Guid]::NewGuid().ToString("N"))
if (Test-Path -LiteralPath $lintFixture) { throw "Lint fixture directory already exists." }
$lintWorkspace = Join-Path $lintFixture "workspace with spaces"
$lintScripts = Join-Path $lintWorkspace "scripts"
$lintControlPath = Join-Path $lintWorkspace "fixture-control.json"
$lintRunner = Join-Path $lintFixture "invoke-fixture.ps1"
$lintShellName = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" }
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $lintShellName += ".exe" }
$lintShell = Join-Path $PSHOME $lintShellName

function Assert-LintFixture {
    param([bool]$Condition, [string]$Message)
    $script:lintAssertions++
    if (-not $Condition) { throw $Message }
}

function Test-LintFixture {
    param([string]$Name, [scriptblock]$Action)
    $script:lintCases++
    try { & $Action } catch { $script:lintFailures.Add("${Name}: $($_.Exception.Message)") }
}

function Invoke-LintFixture {
    param(
        [string]$Name,
        [switch]$ExplicitPath,
        [AllowNull()][object]$Paths = @(),
        [switch]$AllSwift,
        [switch]$ContractsOnly,
        [switch]$SkipContracts,
        [switch]$NativeFileArgument,
        [string[]]$Tracked = @(),
        [string[]]$Untracked = @(),
        [int]$ContractExit = 0,
        [int]$FormatterExit = 0
    )
    $caseRoot = Join-Path $lintFixture $Name
    [void][IO.Directory]::CreateDirectory($caseRoot)
    $control = [ordered]@{
        workspace = $lintWorkspace; caseRoot = $caseRoot
        explicitPath = [bool]$ExplicitPath; paths = $Paths
        allSwift = [bool]$AllSwift; contractsOnly = [bool]$ContractsOnly; skipContracts = [bool]$SkipContracts
        tracked = @($Tracked); untracked = @($Untracked)
        contractExit = $ContractExit; formatterExit = $FormatterExit
    }
    [IO.File]::WriteAllText($lintControlPath, ($control | ConvertTo-Json -Depth 8), $lintEncoding)
    $ErrorActionPreference = "Continue"
    if ($NativeFileArgument) {
        # Bind through the runner's identical string[] Path parameter, then
        # forward it unchanged after installing the owned tooling/CWD guards.
        $output = @(& $lintShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $lintRunner -ControlPath $lintControlPath -Path @($Paths)[0] 2>&1)
    } else {
        $output = @(& $lintShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $lintRunner -ControlPath $lintControlPath 2>&1)
    }
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    $formatterLog = Join-Path $caseRoot "formatter.jsonl"
    $gitLog = Join-Path $caseRoot "git.jsonl"
    $nativePathLog = Join-Path $caseRoot "native-path.json"
    $calls = @(if (Test-Path -LiteralPath $formatterLog) { Get-Content -LiteralPath $formatterLog | ForEach-Object { $_ | ConvertFrom-Json } })
    $gitCalls = @(if (Test-Path -LiteralPath $gitLog) { Get-Content -LiteralPath $gitLog | ForEach-Object { $_ | ConvertFrom-Json } })
    [pscustomobject]@{
        exitCode = $exitCode
        output = ($output | ForEach-Object { $_.ToString() }) -join "`n"
        formatterAttempted = Test-Path -LiteralPath (Join-Path $caseRoot "formatter-called")
        contractAttempted = Test-Path -LiteralPath (Join-Path $caseRoot "contract-called")
        calls = @($calls); gitCalls = @($gitCalls)
        nativePath = if (Test-Path -LiteralPath $nativePathLog) { Get-Content -Raw -LiteralPath $nativePathLog | ConvertFrom-Json } else { $null }
    }
}

try {
    foreach ($directory in @($lintScripts, (Join-Path $lintWorkspace "Sources/Directory.swift"), (Join-Path $lintWorkspace "Tests"))) {
        [void][IO.Directory]::CreateDirectory($directory)
    }
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot "scripts/lint.ps1") -Destination (Join-Path $lintScripts "lint.ps1")
    [IO.File]::WriteAllText((Join-Path $lintWorkspace ".swift-format"), '{}', $lintEncoding)
    $fixtureFiles = [ordered]@{
        "Package.swift" = "// synthetic package`r`n"
        "Sources/First.swift" = "let first = 1`r`n"
        "Tests/Second.swift" = "let second = 2`r`n"
        "Sources/Names,WithComma.swift" = "let comma = 3`r`n"
        "Sources/[Literal].swift" = "let brackets = 4`r`n"
    }
    foreach ($relative in $fixtureFiles.Keys) {
        [IO.File]::WriteAllText((Join-Path $lintWorkspace $relative), $fixtureFiles[$relative], $lintEncoding)
    }
    $absoluteFile = Join-Path $lintFixture "External File.swift"
    [IO.File]::WriteAllText($absoluteFile, "let external = 5`r`n", $lintEncoding)

    $contractStub = @'
param()
$ErrorActionPreference = "Stop"
$control = Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) "fixture-control.json") | ConvertFrom-Json
[IO.File]::WriteAllText((Join-Path $control.caseRoot "contract-called"), "synthetic contract runner")
exit ([int]$control.contractExit)
'@
    $formatterStub = @'
param()
$ErrorActionPreference = "Stop"
$command = @($args)
$control = Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) "fixture-control.json") | ConvertFrom-Json
[IO.File]::WriteAllText((Join-Path $control.caseRoot "formatter-called"), "synthetic formatter only")
if ($command.Count -lt 6 -or $command[0] -cne "swift-format" -or $command[1] -cne "lint" -or
    $command[2] -cne "--configuration" -or $command[4] -cne "--strict") {
    throw "Unexpected formatter command; fake tooling never forwards to a real executable."
}
$files = @(foreach ($path in $command[5..($command.Count - 1)]) {
    [pscustomobject]@{ name = [IO.Path]::GetFileName($path); text = [IO.File]::ReadAllText($path) }
})
$record = [pscustomobject]@{ configuration = $command[3]; files = @($files) }
[IO.File]::AppendAllText((Join-Path $control.caseRoot "formatter.jsonl"), ($record | ConvertTo-Json -Depth 6 -Compress) + "`n")
exit ([int]$control.formatterExit)
'@
    $runner = @'
param([string]$ControlPath, [string[]]$Path)
$ErrorActionPreference = "Stop"
$global:lintFixtureControl = Get-Content -Raw -LiteralPath $ControlPath | ConvertFrom-Json
# Keep .NET and PowerShell resolution inside this owned fixture. In particular,
# the unchanged AllSwift branch selects a relative Package.swift.
Set-Location -LiteralPath $global:lintFixtureControl.workspace
[Environment]::CurrentDirectory = $global:lintFixtureControl.workspace
function global:git {
    $command = @($args)
    $control = $global:lintFixtureControl
    $record = [pscustomobject]@{ arguments = @($command) }
    [IO.File]::AppendAllText((Join-Path $control.caseRoot "git.jsonl"), ($record | ConvertTo-Json -Compress) + "`n")
    $global:LASTEXITCODE = 0
    # PowerShell consumes the '--' separator when calling a function shim.
    if ($command.Count -eq 7 -and ($command -join '|') -ceq ("-C|" + $control.workspace + "|diff|--name-only|--diff-filter=ACMR|HEAD|*.swift")) {
        $control.tracked
    } elseif ($command.Count -eq 6 -and ($command -join '|') -ceq ("-C|" + $control.workspace + "|ls-files|--others|--exclude-standard|*.swift")) {
        $control.untracked
    } else {
        throw "Unexpected git command '$($command -join '|')'; the fixture never queries a real checkout."
    }
}
$parameters = @{}
if ($PSBoundParameters.ContainsKey("Path")) {
    $binding = [pscustomobject]@{ count = @($Path).Count; values = @($Path) }
    [IO.File]::WriteAllText((Join-Path $global:lintFixtureControl.caseRoot "native-path.json"), ($binding | ConvertTo-Json -Compress))
    $parameters.Path = $Path
} elseif ($global:lintFixtureControl.explicitPath) {
    $parameters.Path = [string[]]$global:lintFixtureControl.paths
}
if ($global:lintFixtureControl.allSwift) { $parameters.AllSwift = $true }
if ($global:lintFixtureControl.contractsOnly) { $parameters.ContractsOnly = $true }
if ($global:lintFixtureControl.skipContracts) { $parameters.SkipContracts = $true }
$global:LASTEXITCODE = 0
& (Join-Path $global:lintFixtureControl.workspace "scripts/lint.ps1") @parameters
exit $LASTEXITCODE
'@
    [IO.File]::WriteAllText((Join-Path $lintScripts "check-contracts.ps1"), $contractStub, $lintEncoding)
    [IO.File]::WriteAllText((Join-Path $lintScripts "with-swift.ps1"), $formatterStub, $lintEncoding)
    [IO.File]::WriteAllText($lintRunner, $runner, $lintEncoding)

    $invalidCases = @(
        @{ name = "all-missing"; paths = @("Missing.swift", "AlsoMissing.swift") }
        @{ name = "mixed-missing"; paths = @("Sources/First.swift", "Missing.swift") }
        @{ name = "directory"; paths = @("Sources/Directory.swift") }
        @{ name = "empty-entry"; paths = @("") }
        @{ name = "whitespace-entry"; paths = @(" `t ") }
        @{ name = "null-paths"; paths = $null }
        @{ name = "empty-array"; paths = @() }
        @{ name = "mixed-blank"; paths = @("Sources/First.swift", " ") }
        @{ name = "mixed-null"; paths = @("Sources/First.swift", $null) }
        @{ name = "wildcard-pattern"; paths = @("Sources/*.swift") }
        @{ name = "provider-item"; paths = @("Env:PATH") }
        @{ name = "comma-list"; paths = @("Sources/First.swift,Tests/Second.swift") }
    )
    foreach ($case in $invalidCases) {
        Test-LintFixture $case.name {
            $result = Invoke-LintFixture -Name $case.name -ExplicitPath -Paths $case.paths
            Assert-LintFixture ($result.exitCode -ne 0) "invalid explicit path must fail; output: $($result.output)"
            Assert-LintFixture (-not $result.formatterAttempted) "invalid paths must fail before any formatter invocation"
            Assert-LintFixture ($result.gitCalls.Count -eq 0) "explicit paths must not fall back to changed-file discovery"
        }
    }
    Test-LintFixture "native-comma-list" {
        $result = Invoke-LintFixture -Name "native-comma-list" -ExplicitPath -Paths @("Sources/First.swift,Tests/Second.swift") -NativeFileArgument
        Assert-LintFixture ($result.exitCode -ne 0 -and -not $result.formatterAttempted) "native -File comma-separated text is one invalid literal path"
        Assert-LintFixture ($result.nativePath.count -eq 1 -and $result.nativePath.values[0] -ceq "Sources/First.swift,Tests/Second.swift") "native string[] binding preserves the exact comma argument before forwarding"
    }
    Test-LintFixture "native-literal-comma" {
        $result = Invoke-LintFixture -Name "native-literal-comma" -ExplicitPath -Paths @("Sources/Names,WithComma.swift") -NativeFileArgument
        Assert-LintFixture ($result.exitCode -eq 0 -and $result.calls[0].files.Count -eq 1 -and $result.calls[0].files[0].name -ceq "Names,WithComma.swift") "a real comma-containing filename also succeeds through native -File binding"
        Assert-LintFixture ($result.nativePath.count -eq 1) "a native comma filename is not split"
    }
    foreach ($case in @(
        @{ name = "relative"; path = "Sources/First.swift"; fileName = "First.swift" }
        @{ name = "absolute"; path = $absoluteFile; fileName = "External File.swift" }
        @{ name = "literal-comma"; path = "Sources/Names,WithComma.swift"; fileName = "Names,WithComma.swift" }
        @{ name = "literal-brackets"; path = "Sources/[Literal].swift"; fileName = "[Literal].swift" }
    )) {
        Test-LintFixture $case.name {
            $result = Invoke-LintFixture -Name $case.name -ExplicitPath -Paths @($case.path)
            Assert-LintFixture ($result.exitCode -eq 0 -and $result.calls.Count -eq 1) "existing literal file must reach the fake formatter; output: $($result.output)"
            Assert-LintFixture ($result.calls[0].files.Count -eq 1 -and $result.calls[0].files[0].name -ceq $case.fileName) "exactly the named literal file must be selected"
            Assert-LintFixture (-not $result.calls[0].files[0].text.Contains("`r")) "temporary formatter copies retain newline normalization"
            Assert-LintFixture ($result.contractAttempted -and $result.gitCalls.Count -eq 0) "explicit selection retains contracts without default discovery"
        }
    }
    Test-LintFixture "valid-array" {
        $result = Invoke-LintFixture -Name "valid-array" -ExplicitPath -Paths @("Sources/First.swift", $absoluteFile)
        Assert-LintFixture ($result.exitCode -eq 0 -and $result.calls[0].files.Count -eq 2) "a genuine PowerShell array selects both valid files"
    }
    Test-LintFixture "default-empty" {
        $result = Invoke-LintFixture -Name "default-empty"
        Assert-LintFixture ($result.exitCode -eq 0 -and -not $result.formatterAttempted) "omitted Path with no changes remains a successful no-op; output: $($result.output)"
        Assert-LintFixture ($result.output -match "No Swift files selected" -and $result.gitCalls.Count -eq 2 -and $result.contractAttempted) "default no-op still runs contracts and both discovery queries"
    }
    Test-LintFixture "default-changed" {
        $result = Invoke-LintFixture -Name "default-changed" -Tracked @("Sources/First.swift") -Untracked @("Tests/Second.swift", "Sources/First.swift", "Missing.swift")
        Assert-LintFixture ($result.exitCode -eq 0 -and $result.calls[0].files.Count -eq 2 -and $result.gitCalls.Count -eq 2) "default discovery still deduplicates existing changed files and filters missing ones; output: $($result.output)"
    }
    Test-LintFixture "all-swift" {
        $result = Invoke-LintFixture -Name "all-swift" -AllSwift
        Assert-LintFixture ($result.exitCode -eq 0 -and $result.calls[0].files.Count -eq 5) "AllSwift still selects the fixture package and source/test files"
        Assert-LintFixture ($result.gitCalls.Count -eq 0) "AllSwift does not use changed-file discovery"
    }
    Test-LintFixture "explicit-precedence" {
        $result = Invoke-LintFixture -Name "explicit-precedence" -ExplicitPath -Paths @("Sources/First.swift") -AllSwift
        Assert-LintFixture ($result.exitCode -eq 0 -and $result.calls[0].files.Count -eq 1) "valid explicit Path still takes precedence over AllSwift"
    }
    Test-LintFixture "contracts-only" {
        $result = Invoke-LintFixture -Name "contracts-only" -ExplicitPath -Paths @(" ") -ContractsOnly
        Assert-LintFixture ($result.exitCode -eq 0 -and $result.contractAttempted -and -not $result.formatterAttempted) "ContractsOnly still returns before file selection"
    }
    Test-LintFixture "skip-contracts" {
        $result = Invoke-LintFixture -Name "skip-contracts" -ExplicitPath -Paths @("Sources/First.swift") -SkipContracts
        Assert-LintFixture ($result.exitCode -eq 0 -and -not $result.contractAttempted -and $result.formatterAttempted) "SkipContracts still runs the formatter for valid files"
    }
    Test-LintFixture "contract-failure" {
        $result = Invoke-LintFixture -Name "contract-failure" -ExplicitPath -Paths @("Sources/First.swift") -ContractExit 19
        Assert-LintFixture ($result.exitCode -eq 19 -and -not $result.formatterAttempted) "a failed contract retains its exit code and blocks formatting"
    }
    Test-LintFixture "formatter-failure" {
        $result = Invoke-LintFixture -Name "formatter-failure" -ExplicitPath -Paths @("Sources/First.swift") -FormatterExit 23
        Assert-LintFixture ($result.exitCode -eq 23 -and $result.formatterAttempted) "a failed formatter retains its nonzero exit code"
    }
} finally {
    if (Test-Path -LiteralPath $lintFixture) {
        $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $lintFixture).Path)
        if ([IO.Path]::GetDirectoryName($resolved) -cne $lintTemp -or [IO.Path]::GetFileName($resolved) -notmatch '^swift-windowsui-lint-test-[0-9a-f]{32}$') {
            throw "Refusing cleanup outside the owned lint fixture directory."
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

if ($script:lintFailures.Count -gt 0) {
    throw "Lint path tests failed ($($script:lintFailures.Count)/$script:lintCases cases):`n$($script:lintFailures -join "`n")"
}
Write-Host "Lint path tests passed ($script:lintCases cases, $script:lintAssertions assertions). Fake tooling only; no SwiftPM or formatter executable ran."
exit 0
