param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$script:assertionCount = 0

function Assert-CheckoutTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Checkout metadata test failed: $Message" }
    $script:assertionCount++
}

function Invoke-CheckoutTestGit {
    param([string]$Directory, [string[]]$GitArguments)
    # Capture an expected native failure on both Windows PowerShell and pwsh.
    $ErrorActionPreference = "Continue"
    $output = @(& git -c "core.hooksPath=$script:checkoutHooksPath" -c core.fsmonitor=false -C $Directory @GitArguments 2>&1)
    $code = $LASTEXITCODE
    [pscustomobject]@{ exitCode = $code; output = ($output | ForEach-Object { $_.ToString() }) -join "`n" }
}

# Git's repository overrides take precedence over -C and could redirect a
# fixture index write into another checkout. Refuse them before invoking Git;
# do not clear or change the caller's environment or global configuration.
foreach ($name in @("GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_SHALLOW_FILE", "GIT_CONFIG", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS")) {
    if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name, "Process"))) {
        throw "Refusing checkout fixtures with repository override $name. No Git command was run."
    }
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('/', '\'))
$testRoot = Join-Path $tempRoot ("swift-windowsui-checkout-metadata-" + [Guid]::NewGuid().ToString("N"))
Assert-CheckoutTest (-not (Test-Path -LiteralPath $testRoot)) "fixture directory is new and owned"
[void](New-Item -ItemType Directory -Path $testRoot)
try {
    # Per-command overrides also prevent inherited global hooks or fsmonitor
    # commands from running while this fixture changes its private index.
    $script:checkoutHooksPath = Join-Path $testRoot "disabled-hooks"
    [void](New-Item -ItemType Directory -Path $script:checkoutHooksPath)
    $modulesPath = Join-Path $repoRoot ".gitmodules"
    Assert-CheckoutTest (Test-Path -LiteralPath $modulesPath -PathType Leaf) "tracked gitlinks need .gitmodules metadata"
    $path = Invoke-CheckoutTestGit -Directory $repoRoot -GitArguments @("config", "--file", $modulesPath, "--get", "submodule.extern/zed.path")
    Assert-CheckoutTest ($path.exitCode -eq 0 -and $path.output -ceq "extern/zed") "reference path remains extern/zed"
    $origin = Invoke-CheckoutTestGit -Directory $repoRoot -GitArguments @("config", "--file", $modulesPath, "--get", "submodule.extern/zed.url")
    Assert-CheckoutTest ($origin.exitCode -eq 0 -and $origin.output -ceq "https://github.com/zed-industries/zed.git") "reference URL remains the verified upstream origin"
    $tree = Invoke-CheckoutTestGit -Directory $repoRoot -GitArguments @("ls-tree", "HEAD", "--", "extern/zed")
    Assert-CheckoutTest ($tree.exitCode -eq 0 -and $tree.output -match '^160000 commit ([0-9a-f]{40})\textern/zed$') "reference remains a pinned gitlink"
    $referenceCommit = $Matches[1]

    $workflow = Get-Content -LiteralPath (Join-Path $repoRoot ".github/workflows/swiftui-baseline-capture.yml") -Raw
    $checkout = [regex]::Match($workflow, '(?ms)^[ \t]+- name: Check out source\r?\n(?:(?!^[ \t]+- name:).)*').Value
    Assert-CheckoutTest ($checkout -match '(?m)^\s+persist-credentials: false\s*$') "capture does not persist checkout credentials"
    Assert-CheckoutTest ($checkout -match '(?m)^\s+submodules: false\s*$') "capture never initializes the reference checkout"
    Assert-CheckoutTest ($workflow -match '(?m)^\s+- "\.gitmodules"\s*$') "checkout metadata changes trigger a fresh candidate run"
    Assert-CheckoutTest ($workflow -match '(?m)^\s+run: \./scripts/test-checkout-metadata\.ps1\s*$') "capture runs the checkout regression fixture"

    $initialized = Invoke-CheckoutTestGit -Directory $testRoot -GitArguments @("init", "--quiet", "--template=")
    Assert-CheckoutTest ($initialized.exitCode -eq 0) "initialize the isolated fixture without hooks or templates"
    $hooks = Invoke-CheckoutTestGit -Directory $testRoot -GitArguments @("config", "--get", "core.hooksPath")
    Assert-CheckoutTest ($hooks.exitCode -eq 0 -and $hooks.output -ceq $script:checkoutHooksPath) "effective hook path is the empty owned directory"
    $monitor = Invoke-CheckoutTestGit -Directory $testRoot -GitArguments @("config", "--get", "core.fsmonitor")
    Assert-CheckoutTest ($monitor.exitCode -eq 0 -and $monitor.output -ceq "false") "external filesystem monitor commands are disabled"
    $indexed = Invoke-CheckoutTestGit -Directory $testRoot -GitArguments @("update-index", "--add", "--cacheinfo", "160000,$referenceCommit,extern/zed")
    Assert-CheckoutTest ($indexed.exitCode -eq 0) "fixture preserves the reference gitlink without fetching it"
    [void](New-Item -ItemType Directory -Path (Join-Path $testRoot "extern/zed") -Force)

    # This is the checkout@v4 cleanup operation that failed before export in
    # run 33101129489. The fixture uses no credentials, commits, or network.
    $cleanup = 'sh -c "git config --local --name-only --get-regexp ''core\.sshCommand'' && git config --local --unset-all ''core.sshCommand'' || :"'
    $missing = Invoke-CheckoutTestGit -Directory $testRoot -GitArguments @("submodule", "foreach", "--recursive", $cleanup)
    Assert-CheckoutTest ($missing.exitCode -ne 0) "an unmapped gitlink reproduces the checkout failure"
    Assert-CheckoutTest ($missing.output -match "No url found for submodule path 'extern/zed' in .gitmodules") "failure is the missing mapping, not a different Git error"

    Copy-Item -LiteralPath $modulesPath -Destination (Join-Path $testRoot ".gitmodules")
    $mapped = Invoke-CheckoutTestGit -Directory $testRoot -GitArguments @("submodule", "foreach", "--recursive", $cleanup)
    Assert-CheckoutTest ($mapped.exitCode -eq 0) "valid metadata permits checkout credential cleanup"
    $status = Invoke-CheckoutTestGit -Directory $testRoot -GitArguments @("submodule", "status", "--recursive")
    Assert-CheckoutTest ($status.exitCode -eq 0 -and $status.output -match "^-$referenceCommit extern/zed(?:\s|$)") "the mapped reference stays uninitialized at the same commit"
    Assert-CheckoutTest (-not (Test-Path -LiteralPath (Join-Path $testRoot ".git/modules"))) "the fixture never downloads a submodule"
    Assert-CheckoutTest (@(Get-ChildItem -LiteralPath (Join-Path $testRoot "extern/zed") -Force).Count -eq 0) "reference directory remains empty"

    $remaining = Invoke-CheckoutTestGit -Directory $testRoot -GitArguments @("ls-files", "--stage", "--", "extern/zed")
    Assert-CheckoutTest ($remaining.exitCode -eq 0 -and $remaining.output -match "^160000 $referenceCommit 0\textern/zed$") "cleanup does not change the pinned gitlink"
} finally {
    $resolvedRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $testRoot).Path)
    if ([System.IO.Path]::GetDirectoryName($resolvedRoot) -cne $tempRoot -or
        [System.IO.Path]::GetFileName($resolvedRoot) -notmatch '^swift-windowsui-checkout-metadata-[0-9a-f]{32}$') {
        throw "Refusing cleanup outside the owned checkout fixture directory."
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}

Write-Host "Checkout metadata tests passed ($script:assertionCount assertions). No reference checkout was fetched or changed."
