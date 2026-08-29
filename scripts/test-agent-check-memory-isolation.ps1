<#
.SYNOPSIS
Checks the agent memory-fixture process boundary with tiny PowerShell stubs.
.DESCRIPTION
Copies agent-check.ps1 into an owned temporary repository. Every referenced
stage script is replaced by a stub: no memory workload, SwiftPM, formatter,
native renderer, or real Quick/Full validation runs.
#>
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) ("swift-windowsui-memory-isolation-tests-" + [Guid]::NewGuid().ToString("N")))
)

$ErrorActionPreference = "Stop"
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "These process-boundary fixtures require Windows PowerShell 5.1 or PowerShell 7 on Windows."
}
$fixtureShellName = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh.exe" } else { "powershell.exe" }
$fixtureShell = Join-Path $PSHOME $fixtureShellName
$fixtureRoot = [IO.Path]::GetFullPath($OutputDirectory)
$sourceRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([char[]]@('/', '\'))
$sourceArtifacts = $sourceRoot + [IO.Path]::DirectorySeparatorChar + "artifacts" + [IO.Path]::DirectorySeparatorChar
if ($fixtureRoot.Equals($sourceRoot, [StringComparison]::OrdinalIgnoreCase) -or
    ($fixtureRoot.StartsWith($sourceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        -not $fixtureRoot.StartsWith($sourceArtifacts, [StringComparison]::OrdinalIgnoreCase))) {
    throw "Fixture output cannot be inside this repository except beneath artifacts."
}
$allowedRoots = @(
    [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('/', '\')),
    [IO.Path]::GetFullPath((Join-Path $RepositoryRoot "artifacts")).TrimEnd([char[]]@('/', '\'))
)
$contained = $false
foreach ($allowedRoot in $allowedRoots) {
    if ($fixtureRoot.StartsWith($allowedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        $contained = $true
    }
}
if (-not $contained -or (Test-Path -LiteralPath $fixtureRoot)) { throw "Fixture output must be a new directory under artifacts or the OS temporary directory." }
$ancestor = [IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($fixtureRoot))
while ($null -ne $ancestor) {
    if ($ancestor.Exists -and ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Fixture output cannot traverse a reparse point." }
    $ancestor = $ancestor.Parent
}
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$fixtureEncoding = [Text.UTF8Encoding]::new($false)
$script:fixtureAssertions = 0
$fixtureResults = [System.Collections.Generic.List[object]]::new()

function Assert-MemoryIsolationFixture {
    param([bool]$Condition, [string]$Message)
    $script:fixtureAssertions++
    if (-not $Condition) { throw "Memory-isolation fixture: $Message" }
}

function Quote-MemoryIsolationArgument {
    param([string]$Value)
    # Windows CommandLineToArgvW quoting, including trailing backslashes.
    return '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
}

function Get-MemoryIsolationEvidenceCommands {
    param([Management.Automation.Language.ScriptBlockAst]$AgentAst)
    # These four exceptions belong only to the reviewed, inactive evidence path.
    # Pin the resolver and the ordered Full prefix, including both guards and
    # the intervening test call. No added command name is generally allowed.
    $resolver = @($AgentAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq "Resolve-SwiftTestEvidenceRequest" }, $true))
    $full = @($AgentAst.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Clauses.Count -eq 1 -and $_.Clauses[0].Item1.Extent.Text -ceq '$Full' })
    $parameter = @($AgentAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -ceq "EvidenceDirectory" })
    if ($resolver.Count -ne 1 -or -not [object]::ReferenceEquals($resolver[0].Parent, $AgentAst.EndBlock) -or
        $full.Count -ne 1 -or $full[0].Clauses[0].Item2.Statements.Count -lt 6 -or
        $parameter.Count -ne 1 -or $parameter[0].DefaultValue -isnot [Management.Automation.Language.StringConstantExpressionAst] -or
        $parameter[0].DefaultValue.Value -cne '') { throw "Unexpected copied evidence source." }
    $prefix = @($full[0].Clauses[0].Item2.Statements[0..5])
    $parts = @($resolver[0].Extent.Text) + @($prefix | ForEach-Object { $_.Extent.Text })
    $parts = @($parts | ForEach-Object { $_.Replace(([string][char]13 + [string][char]10), [string][char]10) })
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $digest = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($parts -join [string][char]10)))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
    # These seven extents contain no multiline literals. Only CRLF becomes LF;
    # bare CR, other whitespace, tokens, and node identity remain significant.
    if ($digest -cne '3f5e9c9b760ee57339ca08695bd799be840a7eb01b09c35ca899962ed5139428') { throw "Unexpected copied evidence source." }
    $commands = @($prefix | ForEach-Object { $_.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and
            ($node.GetCommandName() -cin @('Resolve-SwiftTestEvidenceRequest', 'New-SwiftTestEvidenceRequest', 'powershell') -or
                $node.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Dot)
    }, $true) })
    if ($commands.Count -ne 4) { throw "Unexpected copied evidence source." }
    return $commands
}

function Remove-MemoryIsolationEvidenceEnvironment {
    param([Diagnostics.ProcessStartInfo]$StartInfo)
    # Mutate only the copied child's dictionary, never the parent environment.
    foreach ($name in @('SWIFT_WINDOWSUI_TEST_EVIDENCE_DIRECTORY', 'GITHUB_ACTIONS', 'GITHUB_OUTPUT', 'RUNNER_TEMP')) {
        [void]$StartInfo.EnvironmentVariables.Remove($name)
    }
}

function Invoke-MemoryIsolationFixture {
    param(
        [string]$Name,
        [string[]]$RunnerArguments,
        [ValidateSet("pass", "exit", "throw", "missing")][string]$MemoryOutcome = "pass",
        [int]$MemoryExitCode = 37,
        [switch]$StaleCallerStatus
    )
    $caseRoot = Join-Path $fixtureRoot $Name
    $workspace = Join-Path $caseRoot "repository with spaces"
    $scripts = Join-Path $workspace "scripts"
    [void][IO.Directory]::CreateDirectory($scripts)
    [IO.File]::WriteAllText((Join-Path $scripts "agent-check.ps1"), $agentSource, $fixtureEncoding)
    $runnerPath = Join-Path $scripts "agent-check.ps1"
    if ($StaleCallerStatus) {
        $runnerPath = Join-Path $scripts "stale-status-runner.ps1"
        [IO.File]::WriteAllText($runnerPath, $staleStatusSource, $fixtureEncoding)
    }
    foreach ($scriptName in $stageScriptNames) {
        if ($scriptName -ceq "test-swiftui-api-audit-memory.ps1") {
            if ($MemoryOutcome -cne "missing") {
                [IO.File]::WriteAllText((Join-Path $scripts $scriptName), $memoryStub + $commonStub, $fixtureEncoding)
            }
        } else {
            [IO.File]::WriteAllText((Join-Path $scripts $scriptName), $commonStub, $fixtureEncoding)
        }
    }
    $control = [ordered]@{
        memoryOutcome = $MemoryOutcome
        memoryExitCode = $MemoryExitCode
    }
    [IO.File]::WriteAllText((Join-Path $workspace "fixture-control.json"), ($control | ConvertTo-Json -Depth 4), $fixtureEncoding)
    $arguments = @("-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $runnerPath) + $RunnerArguments
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $fixtureShell
    $startInfo.Arguments = (($arguments | ForEach-Object { Quote-MemoryIsolationArgument $_ }) -join " ")
    $startInfo.WorkingDirectory = $workspace
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    Remove-MemoryIsolationEvidenceEnvironment -StartInfo $startInfo
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $started = $false
    try {
        if (-not $process.Start()) { throw "Could not start the owned fixture runner." }
        $started = $true
        $runnerPid = $process.Id
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            throw "The owned fixture runner exceeded 30 seconds; verify any remaining fixture children before retrying."
        }
        $exitCode = $process.ExitCode
        if (-not $stdoutTask.Wait(5000) -or -not $stderrTask.Wait(5000)) {
            throw "The fixture output pipes did not close; verify remaining fixture children before retrying."
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $caseRoot "stdout.log"), $stdout, $fixtureEncoding)
        [IO.File]::WriteAllText((Join-Path $caseRoot "stderr.log"), $stderr, $fixtureEncoding)
    } finally {
        # This is the retained Process object from our own Start, never a name
        # lookup. Stop only that runner; do not claim descendant-tree closure.
        if ($started -and -not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(5000) }
        $process.Dispose()
    }
    $calls = @()
    $callsPath = Join-Path $workspace "calls.ndjson"
    if ([IO.File]::Exists($callsPath)) {
        $calls = @([IO.File]::ReadAllLines($callsPath) | ForEach-Object { ConvertFrom-Json -InputObject $_ })
    }
    $receipt = [ordered]@{
        name = $Name
        runnerArguments = $RunnerArguments
        executable = $fixtureShell
        commandArguments = $arguments
        runnerPid = $runnerPid
        exitCode = $exitCode
        memoryOutcome = $MemoryOutcome
        staleCallerStatus = [bool]$StaleCallerStatus
        calls = $calls
        stdoutSha256 = (Get-FileHash -LiteralPath (Join-Path $caseRoot "stdout.log") -Algorithm SHA256).Hash.ToLowerInvariant()
        stderrSha256 = (Get-FileHash -LiteralPath (Join-Path $caseRoot "stderr.log") -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $fixtureResults.Add($receipt)
    return $receipt
}

$memoryStub = @'
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Large,
    [ValidateRange(128, 4096)][int]$MaximumPeakWorkingSetMiB = 768
)
'@ + [Environment]::NewLine
$commonStub = @'
$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$control = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $workspace "fixture-control.json")))
$stubName = [IO.Path]::GetFileName($PSCommandPath)
$currentProcess = [Diagnostics.Process]::GetCurrentProcess()
try { $hostPath = $currentProcess.MainModule.FileName } finally { $currentProcess.Dispose() }
$record = [ordered]@{
    script = $stubName
    pid = $PID
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    edition = $PSVersionTable.PSEdition
    architecture = [IntPtr]::Size * 8
    psHome = $PSHOME
    hostPath = $hostPath
    nativeErrorPreference = [bool](Get-Variable -Name PSNativeCommandUseErrorActionPreference -ValueOnly -ErrorAction SilentlyContinue)
    arguments = @($args | ForEach-Object { [string]$_ })
}
if ($stubName -ceq "test-swiftui-api-audit-memory.ps1") {
    $record.maximumPeakWorkingSetMiB = $MaximumPeakWorkingSetMiB
    $record.large = [bool]$Large
    $record.repositoryRoot = $RepositoryRoot
    $record.boundParameters = @($PSBoundParameters.Keys)
}
[IO.File]::AppendAllText((Join-Path $workspace "calls.ndjson"), ($record | ConvertTo-Json -Depth 6 -Compress) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
if ($stubName -ceq "test-swiftui-api-audit-memory.ps1") {
    if ($control.memoryOutcome -ceq "exit") { exit ([int]$control.memoryExitCode) }
    if ($control.memoryOutcome -ceq "throw") { throw "Synthetic memory fixture failure." }
}
exit 0
'@ + [Environment]::NewLine

$report = [ordered]@{
    schemaVersion = 1
    evidenceKind = "synthetic-agent-check-memory-process-boundary"
    status = "running"
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    edition = $PSVersionTable.PSEdition
    architecture = [IntPtr]::Size * 8
    executable = $fixtureShell
    agentCheckSha256 = $null
    memoryFixtureSha256 = $null
    memoryWorkloadExecuted = $false
    swiftPMExecuted = $false
    realQuickOrFullExecuted = $false
    assertions = 0
    cases = @()
}
$fixtureFailure = $null
try {
    $agentPath = Join-Path $RepositoryRoot "scripts/agent-check.ps1"
    $agentSource = [IO.File]::ReadAllText($agentPath)
    $report.agentCheckSha256 = (Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $tokens = $null
    $parseErrors = $null
    $agentAst = [Management.Automation.Language.Parser]::ParseInput($agentSource, [ref]$tokens, [ref]$parseErrors)
    Assert-MemoryIsolationFixture (@($parseErrors).Count -eq 0) "the copied runner parses"
    $stageScriptNames = @($agentAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.EndsWith(".ps1", [StringComparison]::Ordinal)
    }, $true) | ForEach-Object { $_.Value } | Sort-Object -Unique)
    Assert-MemoryIsolationFixture ($stageScriptNames -ccontains "test-swiftui-api-audit-memory.ps1") "the runner references the actual memory fixture"
    Assert-MemoryIsolationFixture ($stageScriptNames -ccontains "test-copy-demo-resources.ps1") "the resource-copy stage receives a stub in every copied checkout"
    foreach ($scriptName in $stageScriptNames) {
        Assert-MemoryIsolationFixture ([IO.Path]::GetFileName($scriptName) -ceq $scriptName) "every stage reference stays inside the copied scripts directory"
    }
    $allowedCommands = @("Join-Path", "Split-Path", "Get-ReportedExitCode", "Invoke-Step", "Write-Host", "Set-Variable")
    $allowedVariables = @("Command", "contractScript", "lintScript", "testScript", "portableTestScript", "buildScript", "screenshotScript", "galleryCompareScript", "memoryFixtureShell")
    $evidenceCommands = @(Get-MemoryIsolationEvidenceCommands -AgentAst $agentAst)
    Assert-MemoryIsolationFixture ($evidenceCommands.Count -eq 4) "only four reviewed evidence command nodes are admitted"
    $lfSource = $agentSource.Replace(([string][char]13 + [string][char]10), [string][char]10)
    $lfAst = [Management.Automation.Language.Parser]::ParseInput($lfSource, [ref]$tokens, [ref]$parseErrors)
    $lfEvidenceCommands = @(Get-MemoryIsolationEvidenceCommands -AgentAst $lfAst)
    Assert-MemoryIsolationFixture (@($parseErrors).Count -eq 0 -and $lfEvidenceCommands.Count -eq 4) "LF checkout source retains the same scoped evidence admission"
    foreach ($command in $agentAst.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true)) {
        $isEvidenceCommand = $false
        foreach ($admitted in $evidenceCommands) {
            if ([object]::ReferenceEquals($command, $admitted)) { $isEvidenceCommand = $true; break }
        }
        $commandName = $command.GetCommandName()
        if ($null -ne $commandName) {
            Assert-MemoryIsolationFixture (($allowedCommands -ccontains $commandName) -or $isEvidenceCommand) "the copied runner cannot call an unexpected command"
        } elseif ($command.CommandElements[0] -is [Management.Automation.Language.VariableExpressionAst]) {
            Assert-MemoryIsolationFixture ($allowedVariables -ccontains $command.CommandElements[0].VariablePath.UserPath) "dynamic commands stay within the known stage and fixture-host variables"
        } else {
            Assert-MemoryIsolationFixture (($command.CommandElements[0].Extent.Text -match '^\(Join-Path \$PSScriptRoot "[^"/\\]+\.ps1"\)$') -or $isEvidenceCommand) "computed stage commands only address copied scripts"
        }
    }
    # Pure admission controls: altered scripts are parsed, never invoked.
    foreach ($mutation in @(
        @{ Before = 'return [string]$EnvironmentValue'; After = "return 'unexpected'" },
        @{ Before = '& powershell @evidenceCheckArguments'; After = "& powershell -Command 'exit 0'" }
    )) {
        $altered = $agentSource.Replace($mutation.Before, $mutation.After)
        $alteredAst = [Management.Automation.Language.Parser]::ParseInput($altered, [ref]$tokens, [ref]$parseErrors)
        $rejected = $false
        try { $null = @(Get-MemoryIsolationEvidenceCommands -AgentAst $alteredAst) } catch { $rejected = $_.Exception.Message -ceq "Unexpected copied evidence source." }
        Assert-MemoryIsolationFixture (@($parseErrors).Count -eq 0 -and $rejected) "altering the reviewed resolver or Check site is rejected before invocation"
    }
    $outsideAst = [Management.Automation.Language.Parser]::ParseInput(($agentSource + [Environment]::NewLine + '& powershell @evidenceCheckArguments'), [ref]$tokens, [ref]$parseErrors)
    $outsideEvidenceCommands = @(Get-MemoryIsolationEvidenceCommands -AgentAst $outsideAst)
    $powershellCommands = @($outsideAst.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'powershell' }, $true))
    $outsideAdmitted = @($outsideEvidenceCommands | Where-Object { [object]::ReferenceEquals($_, $powershellCommands[-1]) })
    Assert-MemoryIsolationFixture (@($parseErrors).Count -eq 0 -and $powershellCommands.Count -eq 2 -and $outsideAdmitted.Count -eq 0 -and $allowedCommands -cnotcontains 'powershell') "another powershell site cannot inherit the reviewed node's admission"
    $environmentProbe = [Diagnostics.ProcessStartInfo]::new()
    $evidenceEnvironmentNames = @('SWIFT_WINDOWSUI_TEST_EVIDENCE_DIRECTORY', 'GITHUB_ACTIONS', 'GITHUB_OUTPUT', 'RUNNER_TEMP')
    foreach ($name in $evidenceEnvironmentNames) { $environmentProbe.EnvironmentVariables[$name] = 'synthetic-parent-value' }
    $environmentProbe.EnvironmentVariables['GITHUB_ACTIONS'] = 'true'
    $environmentProbe.EnvironmentVariables['SWIFT_WINDOWSUI_MEMORY_FIXTURE_SENTINEL'] = 'keep'
    Remove-MemoryIsolationEvidenceEnvironment -StartInfo $environmentProbe
    foreach ($name in $evidenceEnvironmentNames) {
        Assert-MemoryIsolationFixture (-not $environmentProbe.EnvironmentVariables.ContainsKey($name)) "the copied child excludes inherited evidence and Actions control variables"
    }
    Assert-MemoryIsolationFixture ($environmentProbe.EnvironmentVariables['SWIFT_WINDOWSUI_MEMORY_FIXTURE_SENTINEL'] -ceq 'keep') "the copied child retains unrelated environment values"
    $memoryPath = Join-Path $RepositoryRoot "scripts/test-swiftui-api-audit-memory.ps1"
    $report.memoryFixtureSha256 = (Get-FileHash -LiteralPath $memoryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $memoryAst = [Management.Automation.Language.Parser]::ParseFile($memoryPath, [ref]$tokens, [ref]$parseErrors)
    Assert-MemoryIsolationFixture (@($parseErrors).Count -eq 0) "the real memory fixture parses without being executed"
    $budgetParameter = @($memoryAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -ceq "MaximumPeakWorkingSetMiB" })
    Assert-MemoryIsolationFixture ($budgetParameter.Count -eq 1 -and $budgetParameter[0].DefaultValue.SafeGetValue() -eq 768) "the real fixture retains its 768 MiB default"

    $exitHelper = @($agentAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq "Get-ReportedExitCode" }, $true))
    $stepHelper = @($agentAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq "Invoke-Step" }, $true))
    $memoryStep = @($agentAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq "Invoke-Step" -and $node.CommandElements[1].Value -ceq "SwiftUI API audit bounded-memory fixtures (synthetic only)"
    }, $true))
    Assert-MemoryIsolationFixture ($exitHelper.Count -eq 1 -and $stepHelper.Count -eq 1 -and $memoryStep.Count -eq 1) "the scope probe extracts the exact helpers and memory step"
    $staleStatusSource = @(
        '$ErrorActionPreference = "Stop"',
        $exitHelper[0].Extent.Text,
        $stepHelper[0].Extent.Text,
        '& (Join-Path $PSScriptRoot "test-swiftui-api-audit.ps1")',
        '$script:LASTEXITCODE = 79',
        '$global:LASTEXITCODE = 83',
        '$PSNativeCommandUseErrorActionPreference = $true',
        $memoryStep[0].Extent.Text,
        '& (Join-Path $PSScriptRoot "test-swiftui-api-audit-workflow.ps1")',
        'exit 0'
    ) -join [Environment]::NewLine

    foreach ($mode in @("Quick", "Full")) {
        $case = Invoke-MemoryIsolationFixture -Name ($mode.ToLowerInvariant() + "-success") -RunnerArguments @("-" + $mode)
        Assert-MemoryIsolationFixture ($case.exitCode -eq 0) "$mode succeeds when the child succeeds"
        $resourceCalls = @($case.calls | Where-Object script -CEQ "test-copy-demo-resources.ps1")
        Assert-MemoryIsolationFixture ($resourceCalls.Count -eq 1 -and $resourceCalls[0].pid -eq $case.runnerPid -and @($resourceCalls[0].arguments).Count -eq 0) "$mode runs the resource-copy stub once in the original host without arguments"
        Assert-MemoryIsolationFixture ($case.calls.Count -ge 4 -and
            $case.calls[0].script -ceq "check-contracts.ps1" -and
            $case.calls[1].script -ceq "test-checkout-metadata.ps1" -and
            $case.calls[2].script -ceq "test-copy-demo-resources.ps1" -and
            $case.calls[3].script -ceq "test-lint-paths.ps1") "$mode keeps resource copying between checkout metadata and lint path fixtures"
        $memoryCalls = @($case.calls | Where-Object script -CEQ "test-swiftui-api-audit-memory.ps1")
        $before = @($case.calls | Where-Object script -CEQ "test-swiftui-api-audit.ps1")
        $after = @($case.calls | Where-Object script -CEQ "test-swiftui-api-audit-workflow.ps1")
        Assert-MemoryIsolationFixture ($memoryCalls.Count -eq 1 -and $before.Count -eq 1 -and $after.Count -eq 1) "$mode runs the memory stage exactly once in its existing sequence"
        $publicationRecoveryCalls = @($case.calls | Where-Object script -CEQ "test-swiftui-api-audit-publication-recovery.ps1")
        $publicationDiagnosticCalls = @($case.calls | Where-Object script -CEQ "test-swiftui-api-audit-publication-diagnostics.ps1")
        Assert-MemoryIsolationFixture ($publicationRecoveryCalls.Count -eq 1 -and $publicationDiagnosticCalls.Count -eq 1) "$mode runs each publication stage exactly once"
        [string[]]$orderedCallScripts = @($case.calls | ForEach-Object { $_.script })
        $memoryCallIndex = [Array]::IndexOf($orderedCallScripts, "test-swiftui-api-audit-memory.ps1")
        Assert-MemoryIsolationFixture ($memoryCallIndex -ge 3 -and
            $orderedCallScripts[$memoryCallIndex - 3] -ceq "test-swiftui-api-audit.ps1" -and
            $orderedCallScripts[$memoryCallIndex - 2] -ceq "test-swiftui-api-audit-publication-recovery.ps1" -and
            $orderedCallScripts[$memoryCallIndex - 1] -ceq "test-swiftui-api-audit-publication-diagnostics.ps1") "$mode keeps ledger, recovery, diagnostics and memory stages in order"
        $memory = $memoryCalls[0]
        Assert-MemoryIsolationFixture ($memory.pid -ne $case.runnerPid -and $before[0].pid -eq $case.runnerPid -and $after[0].pid -eq $case.runnerPid) "only the memory stage changes process in $mode"
        Assert-MemoryIsolationFixture ($memory.powerShellVersion -ceq $PSVersionTable.PSVersion.ToString() -and $memory.edition -ceq $PSVersionTable.PSEdition -and $memory.architecture -eq [IntPtr]::Size * 8) "$mode preserves engine version, edition and architecture"
        Assert-MemoryIsolationFixture ([string]::Equals($memory.hostPath, $fixtureShell, [StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($memory.psHome, $PSHOME, [StringComparison]::OrdinalIgnoreCase)) "$mode uses the exact PSHOME executable"
        Assert-MemoryIsolationFixture ($memory.maximumPeakWorkingSetMiB -eq 768 -and -not $memory.large -and @($memory.arguments).Count -eq 0 -and @($memory.boundParameters).Count -eq 0) "$mode preserves memory-script arguments and defaults"
        Assert-MemoryIsolationFixture ($memory.repositoryRoot -like "*repository with spaces") "$mode preserves paths containing spaces"
        $otherProcessCalls = @($case.calls | Where-Object { $_.script -cne "test-swiftui-api-audit-memory.ps1" -and $_.pid -ne $case.runnerPid })
        Assert-MemoryIsolationFixture ($otherProcessCalls.Count -eq 0) "$mode leaves every other stage in the original host"
        if ($mode -ceq "Full") {
            $testCalls = @($case.calls | Where-Object script -CEQ "test.ps1")
            $buildCalls = @($case.calls | Where-Object script -CEQ "build.ps1")
            Assert-MemoryIsolationFixture ($testCalls.Count -eq 1 -and @($testCalls[0].arguments).Count -eq 1 -and $testCalls[0].arguments[0] -ceq "-Sharded") "Full keeps its original test invocation"
            Assert-MemoryIsolationFixture ($buildCalls.Count -eq 2 -and @($buildCalls | Where-Object { $_.arguments -ccontains "release" }).Count -eq 1) "Full retains both build configurations as stubs"
        }
    }
    $contracts = Invoke-MemoryIsolationFixture -Name "contracts-only" -RunnerArguments @("-ContractsOnly") -MemoryOutcome throw
    Assert-MemoryIsolationFixture ($contracts.exitCode -eq 0 -and $contracts.calls.Count -eq 1 -and $contracts.calls[0].script -ceq "check-contracts.ps1") "ContractsOnly never starts the memory fixture or subsequent stages"
    foreach ($mode in @("Quick", "Full")) {
        foreach ($outcome in @("exit", "throw", "missing")) {
            $case = Invoke-MemoryIsolationFixture -Name ($mode.ToLowerInvariant() + "-" + $outcome) -RunnerArguments @("-" + $mode) -MemoryOutcome $outcome
            $resourceCalls = @($case.calls | Where-Object script -CEQ "test-copy-demo-resources.ps1")
            Assert-MemoryIsolationFixture ($resourceCalls.Count -eq 1) "$mode reaches a $outcome memory child after the new resource-copy stub"
            if ($outcome -ceq "exit") {
                Assert-MemoryIsolationFixture ($case.exitCode -eq 37) "$mode preserves the child's exact nonzero exit"
            } else {
                Assert-MemoryIsolationFixture ($case.exitCode -ne 0) "$mode rejects a $outcome child"
            }
            $lastCall = $case.calls[$case.calls.Count - 1]
            $expectedLast = if ($outcome -ceq "missing") { "test-swiftui-api-audit-publication-diagnostics.ps1" } else { "test-swiftui-api-audit-memory.ps1" }
            Assert-MemoryIsolationFixture ($lastCall.script -ceq $expectedLast) "$mode stops immediately after a $outcome child, with no later validation stages"
        }
    }
    foreach ($outcome in @("pass", "exit", "throw")) {
        $case = Invoke-MemoryIsolationFixture -Name ("stale-caller-" + $outcome) -RunnerArguments @() -MemoryOutcome $outcome -StaleCallerStatus
        $expectedExit = if ($outcome -ceq "pass") { 0 } elseif ($outcome -ceq "exit") { 37 } else { 1 }
        Assert-MemoryIsolationFixture ($case.exitCode -eq $expectedExit) "actual $outcome child status overrides stale caller codes and native-error preferences"
        $afterCalls = @($case.calls | Where-Object script -CEQ "test-swiftui-api-audit-workflow.ps1")
        $expectedAfterCalls = if ($outcome -ceq "pass") { 1 } else { 0 }
        Assert-MemoryIsolationFixture ($afterCalls.Count -eq $expectedAfterCalls) "only a successful child continues after the scope probe"
        if ($outcome -ceq "pass") {
            Assert-MemoryIsolationFixture ([bool]$afterCalls[0].nativeErrorPreference) "the memory block does not change its caller's native-error preference"
        }
    }
    $report.status = "passed"
} catch {
    $fixtureFailure = $_
    $report.status = "failed"
} finally {
    $report.assertions = $script:fixtureAssertions
    $report.cases = $fixtureResults.ToArray()
    [IO.File]::WriteAllText((Join-Path $fixtureRoot "report.json"), ($report | ConvertTo-Json -Depth 12), $fixtureEncoding)
}
Write-Host "Memory-isolation fixtures: $($report.status); $($report.assertions) assertions; evidence: $fixtureRoot"
if ($null -ne $fixtureFailure) { throw $fixtureFailure }
exit 0
