<#
.SYNOPSIS
Tests the production sharded target selector without running test.ps1 or SwiftPM.
#>
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$script:selectionAssertions = 0
$script:selectionCases = 0

function Assert-TargetSelection {
    param([bool]$Condition, [string]$Message)
    $script:selectionAssertions++
    if (-not $Condition) { throw $Message }
}

$sourcePath = Join-Path $RepositoryRoot "scripts/test.ps1"
$parseTokens = $null
$parseErrors = $null
$sourceAst = [Management.Automation.Language.Parser]::ParseFile(
    $sourcePath, [ref]$parseTokens, [ref]$parseErrors)
Assert-TargetSelection (@($parseErrors).Count -eq 0) "The production test runner must parse."
$definitions = @($sourceAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq "Select-ShardedTestTargets"
        }, $true))
Assert-TargetSelection ($definitions.Count -eq 1) "Expected one production selector definition."

# Extract only this function body. Never dot-source or invoke test.ps1 itself:
# its top-level statements perform discovery, bootstrap, and SwiftPM execution.
$script:selector = $definitions[0].Body.GetScriptBlock()
$shardedBranches = @($sourceAst.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.IfStatementAst] -and
        $_.Clauses[0].Item1.Extent.Text -ceq '$Sharded'
    })
Assert-TargetSelection ($shardedBranches.Count -eq 1) "Expected the production Sharded branch."
$productionCalls = @($shardedBranches[0].FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -ceq "Select-ShardedTestTargets"
        }, $true))
Assert-TargetSelection ($productionCalls.Count -eq 1 -and
    $productionCalls[0].Extent.Text -ceq 'Select-ShardedTestTargets -Targets $targets -Filter $Filter') `
    "The Sharded branch must call the tested helper with the discovered targets and original filter."

# Independent names, order, and objects: none are discovered from Swift sources
# or produced by a second implementation of the production selection rule.
$targets = @(
    [pscustomobject]@{ Name = "IntegrationTests"; Kind = "XCTest" }
    [pscustomobject]@{ Name = "UIAItemContainerCallLeaseIntegrationTests"; Kind = "XCTest" }
    [pscustomobject]@{ Name = "UIANativeItemContainerIntegrationTests"; Kind = "XCTest" }
    [pscustomobject]@{ Name = "WindowCoordinatorTests"; Kind = "XCTest" }
    [pscustomobject]@{ Name = "NativeWindowCoordinatorTests"; Kind = "XCTest" }
    [pscustomobject]@{ Name = "SoftwarePresentationTests"; Kind = "XCTest" }
    [pscustomobject]@{ Name = "NativeSoftwarePresentationTests"; Kind = "XCTest" }
    [pscustomobject]@{ Name = "UnrelatedTests"; Kind = "SwiftTesting" }
)

function Test-TargetSelection {
    param(
        [string]$Name,
        [AllowNull()][string]$Filter,
        [object[]]$Expected,
        [object[]]$InputTargets = $targets,
        [switch]$OmitFilter
    )
    $script:selectionCases++
    $before = ConvertTo-Json -InputObject @($InputTargets) -Depth 4 -Compress
    if ($OmitFilter) {
        $actual = @(& $script:selector -Targets $InputTargets)
    } else {
        $actual = @(& $script:selector -Targets $InputTargets -Filter $Filter)
    }
    Assert-TargetSelection ($actual.Count -eq $Expected.Count) `
        "${Name}: expected $($Expected.Count) targets, got $($actual.Count)."
    $sameReferences = $true
    for ($i = 0; $i -lt $Expected.Count; $i++) {
        if (-not [object]::ReferenceEquals($actual[$i], $Expected[$i])) {
            $sameReferences = $false
        }
    }
    Assert-TargetSelection $sameReferences "${Name}: selected objects or their order changed."
    $after = ConvertTo-Json -InputObject @($InputTargets) -Depth 4 -Compress
    Assert-TargetSelection ($before -ceq $after) "${Name}: input targets were mutated."
    Write-Host "PASS: $Name ($($actual.Count) targets)"
}

Test-TargetSelection "exact ItemContainer call lease" "UIAItemContainerCallLeaseIntegrationTests" @($targets[1])
Test-TargetSelection "exact native ItemContainer" "UIANativeItemContainerIntegrationTests" @($targets[2])
Test-TargetSelection "exact native coordinator" "NativeWindowCoordinatorTests" @($targets[4])
Test-TargetSelection "exact native software" "NativeSoftwarePresentationTests" @($targets[6])
Test-TargetSelection "exact shorter integration" "IntegrationTests" @($targets[0])
Test-TargetSelection "exact shorter coordinator" "WindowCoordinatorTests" @($targets[3])
Test-TargetSelection "exact shorter software" "SoftwarePresentationTests" @($targets[5])
Test-TargetSelection "case-insensitive ItemContainer exact" "uiaitemcontainercallleaseintegrationtests" @($targets[1])
Test-TargetSelection "case-insensitive native ItemContainer exact" "UIANATIVEITEMCONTAINERINTEGRATIONTESTS" @($targets[2])
Test-TargetSelection "case-insensitive coordinator exact" "nATIVEwINDOWcOORDINATORtESTS" @($targets[4])
Test-TargetSelection "case-insensitive software exact" "nativesoftwarepresentationtests" @($targets[6])
$duplicateTargets = @(
    [pscustomobject]@{ Name = "NATIVEWINDOWCOORDINATORTESTS"; Kind = "SwiftTesting" }
    $targets[3]
    $targets[4]
)
Test-TargetSelection "all exact objects preserve input order" "NativeWindowCoordinatorTests" `
    @($duplicateTargets[0], $duplicateTargets[2]) -InputTargets $duplicateTargets
Test-TargetSelection "missing exact and no fallback" "MissingExactTests" @()
Test-TargetSelection "substring fallback" "ItemContainer" @($targets[1], $targets[2])
Test-TargetSelection "case-insensitive substring fallback" "itemcontainer" @($targets[1], $targets[2])
Test-TargetSelection "wildcard fallback" "*Native*Tests" @($targets[2], $targets[4], $targets[6])
Test-TargetSelection "wildcard keeps reverse suffix matching" "UIA*IntegrationTests" @($targets[0], $targets[1], $targets[2])
Test-TargetSelection "missing exact keeps reverse substring" "PrefixNativeWindowCoordinatorTestsSuffix" @($targets[3], $targets[4])
Test-TargetSelection "joined ItemContainer names keep fallback" `
    "UIAItemContainerCallLeaseIntegrationTests|UIANativeItemContainerIntegrationTests" @($targets[0], $targets[1], $targets[2])
Test-TargetSelection "joined native names keep fallback" `
    "NativeWindowCoordinatorTests|NativeSoftwarePresentationTests" @($targets[3], $targets[4], $targets[5], $targets[6])
Test-TargetSelection "regex-looking input is not promoted to regex" "MountedState.*Tests" @()
Test-TargetSelection "nonempty input is not trimmed" "NativeWindowCoordinatorTests " @($targets[3], $targets[4])
Test-TargetSelection "empty filter selects all" "" $targets
Test-TargetSelection "omitted filter selects all" -Expected $targets -OmitFilter
Test-TargetSelection "whitespace filter selects all" " `t`r`n" $targets
Test-TargetSelection "null filter selects all" $null $targets
Test-TargetSelection "star wildcard selects all" "*" $targets
Test-TargetSelection "empty targets with empty filter" "" @() -InputTargets @()
Test-TargetSelection "empty targets with named filter" "NativeWindowCoordinatorTests" @() -InputTargets @()
Test-TargetSelection "all is not a special filter token" "all" @($targets[1])

Write-Host ("Sharded target selection fixtures PASSED ({0} cases, {1} assertions; no SwiftPM)." -f `
    $script:selectionCases, $script:selectionAssertions)
