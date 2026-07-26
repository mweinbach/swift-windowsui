param(
    # Optional SwiftPM --filter regex / class / suite name. Preserved for documented invocations.
    [string]$Filter = "",

    # Run the full suite as serial per-target shards (and method batches for oversized
    # XCTest classes). Avoids Windows CreateProcess / XCTest runner error 206 when a
    # single filter or skip list would expand past the command-line length limit.
    [switch]$Sharded,

    # Soft cap on estimated expanded XCTest identifiers for one --filter invocation.
    # Windows CreateProcess command lines are limited (~8191). Stay under that.
    [int]$MaxExpandedFilterChars = 3000,

    # XCTest classes with at least this many methods are method-batched even under
    # a class-level filter (WinSwiftUITests-scale suites).
    [int]$MethodShardThreshold = 100
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$withSwift = Join-Path $PSScriptRoot "with-swift.ps1"
$testSources = Join-Path $repoRoot "Tests\SwiftWindowsCoreLogicTests"
$testModule = "SwiftWindowsCoreLogicTests"

function Get-ReportedExitCode {
    if ($null -eq $LASTEXITCODE) {
        return $null
    }
    return [int]$LASTEXITCODE
}

function Get-DiscoveredTestTargets {
    param([string]$SourceRoot)

    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        throw "Test source root not found: $SourceRoot"
    }

    $targets = @{}

    Get-ChildItem -LiteralPath $SourceRoot -Filter "*.swift" -File | ForEach-Object {
        $filePath = $_.FullName
        $lines = Get-Content -LiteralPath $filePath
        $current = $null

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]

            if ($line -match 'final\s+class\s+(\w+)\s*:\s*XCTestCase') {
                $name = $Matches[1]
                $current = [pscustomobject]@{
                    Name    = $name
                    Kind    = "XCTest"
                    File    = $filePath
                    Methods = New-Object System.Collections.Generic.List[string]
                }
                $targets[$name] = $current
                continue
            }

            if ($line -match '@Suite') {
                $suiteName = $null
                for ($j = $i; $j -lt [Math]::Min($i + 6, $lines.Count); $j++) {
                    if ($lines[$j] -match '(?:struct|class|actor)\s+(\w+)') {
                        $suiteName = $Matches[1]
                        break
                    }
                }
                if ($suiteName) {
                    $current = [pscustomobject]@{
                        Name    = $suiteName
                        Kind    = "SwiftTesting"
                        File    = $filePath
                        Methods = New-Object System.Collections.Generic.List[string]
                    }
                    $targets[$suiteName] = $current
                }
                continue
            }

            if ($null -eq $current) {
                continue
            }

            if ($current.Kind -eq "XCTest" -and $line -match '^\s*func\s+(test\w+)\s*\(') {
                [void]$current.Methods.Add($Matches[1])
            }
        }
    }

    return @($targets.Values | Sort-Object Name)
}

function Get-ExpandedIdentifierLength {
    param(
        [string]$ClassName,
        [string[]]$Methods
    )

    if ($null -eq $Methods -or $Methods.Count -eq 0) {
        return 0
    }

    $total = 0
    foreach ($method in $Methods) {
        # XCTest on Windows has been observed to expand matching tests into a long
        # argv list; estimate with the common Module.Class/method form.
        $total += ("$testModule.$ClassName/$method").Length + 1
    }
    return $total
}

function Test-RequiresMethodSharding {
    param(
        $Target,
        [int]$MaxExpandedFilterChars,
        [int]$MethodShardThreshold
    )

    if ($Target.Kind -ne "XCTest") {
        return $false
    }

    $methodCount = @($Target.Methods).Count
    if ($methodCount -ge $MethodShardThreshold) {
        return $true
    }

    $expanded = Get-ExpandedIdentifierLength -ClassName $Target.Name -Methods @($Target.Methods)
    return ($expanded -gt $MaxExpandedFilterChars)
}

function Get-MethodFilterBatches {
    param(
        $Target,
        [int]$MaxExpandedFilterChars
    )

    $methods = @($Target.Methods)
    if ($methods.Count -eq 0) {
        return @($Target.Name)
    }

    $batches = New-Object System.Collections.Generic.List[string]
    $index = 0
    while ($index -lt $methods.Count) {
        $batchMethods = New-Object System.Collections.Generic.List[string]
        $expanded = 0

        while ($index -lt $methods.Count) {
            $method = $methods[$index]
            $piece = ("$testModule.$($Target.Name)/$method").Length + 1
            if ($batchMethods.Count -gt 0 -and ($expanded + $piece) -gt $MaxExpandedFilterChars) {
                break
            }
            [void]$batchMethods.Add($method)
            $expanded += $piece
            $index++

            # Always include at least one method even if a single name is huge.
            if ($batchMethods.Count -eq 1 -and $piece -gt $MaxExpandedFilterChars) {
                break
            }
        }

        # Regex filter: ClassName/(testA|testB|...) keeps the SwiftPM argv short;
        # the batch size above keeps any runner-side expansion under the cap.
        $escaped = @($batchMethods | ForEach-Object { [regex]::Escape($_) })
        [void]$batches.Add(("$($Target.Name)/(" + ($escaped -join "|") + ")"))
    }

    return @($batches)
}

function Get-FiltersForTarget {
    param(
        $Target,
        [int]$MaxExpandedFilterChars,
        [int]$MethodShardThreshold
    )

    if (Test-RequiresMethodSharding -Target $Target -MaxExpandedFilterChars $MaxExpandedFilterChars -MethodShardThreshold $MethodShardThreshold) {
        Write-Host ("  method-sharding {0} ({1} methods, expanded~{2} chars)" -f `
                $Target.Name, `
                @($Target.Methods).Count, `
                (Get-ExpandedIdentifierLength -ClassName $Target.Name -Methods @($Target.Methods)))
        return Get-MethodFilterBatches -Target $Target -MaxExpandedFilterChars $MaxExpandedFilterChars
    }

    return @($Target.Name)
}

function Invoke-SwiftTest {
    param(
        [string[]]$Filters = @(),
        [string]$Label = ""
    )

    $argsList = [System.Collections.Generic.List[string]]::new()
    [void]$argsList.Add("test")
    [void]$argsList.Add("--package-path")
    [void]$argsList.Add($repoRoot)

    $displayFilters = @()
    foreach ($f in $Filters) {
        if (-not [string]::IsNullOrWhiteSpace($f)) {
            [void]$argsList.Add("--filter")
            [void]$argsList.Add($f)
            $displayFilters += $f
        }
    }

    if ([string]::IsNullOrWhiteSpace($Label)) {
        if ($displayFilters.Count -eq 0) {
            $Label = "all tests"
        } else {
            $Label = $displayFilters -join ", "
        }
    }

    Write-Host ""
    Write-Host "swift test  [$Label]"
    if ($displayFilters.Count -gt 0) {
        foreach ($f in $displayFilters) {
            Write-Host "  --filter $f"
        }
    }

    $invocationArgs = $argsList.ToArray()
    & powershell -NoProfile -ExecutionPolicy Bypass -File $withSwift swift @invocationArgs | Out-Host
    $code = Get-ReportedExitCode

    if ($null -eq $code) {
        Write-Host "FAILED: swift test reported no exit code [$Label]" -ForegroundColor Red
        return 1
    }

    if ($code -ne 0) {
        Write-Host "FAILED: swift test exited with code $code [$Label]" -ForegroundColor Red
        if ($code -eq 206) {
            Write-Host "Hint: Windows error 206 usually means the XCTest filter/skip argv is too long. Use -Sharded or a narrower -Filter." -ForegroundColor Yellow
        }
        return $code
    }

    Write-Host "PASSED: [$Label]" -ForegroundColor Green
    return 0
}

function Invoke-FilterShards {
    param(
        [string[]]$FilterList,
        [string]$Context
    )

    $total = $FilterList.Count
    $index = 0
    foreach ($filterExpr in $FilterList) {
        $index++
        $label = "{0} shard {1}/{2}: {3}" -f $Context, $index, $total, $filterExpr
        $code = Invoke-SwiftTest -Filters @($filterExpr) -Label $label
        if ($code -ne 0) {
            Write-Host ""
            Write-Host "Test run aborted on shard $index of $total under $Context (exit code $code)." -ForegroundColor Red
            return $code
        }
    }
    return 0
}

# --- main -------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $withSwift)) {
    throw "Missing helper script: $withSwift"
}

$targets = Get-DiscoveredTestTargets -SourceRoot $testSources

if ($Sharded) {
    $selected = $targets
    if (-not [string]::IsNullOrWhiteSpace($Filter)) {
        $selected = @($targets | Where-Object {
                $_.Name -eq $Filter -or $_.Name -like "*$Filter*" -or $Filter -like "*$($_.Name)*"
            })
        if ($selected.Count -eq 0) {
            Write-Host "No discovered test targets match -Filter '$Filter'." -ForegroundColor Red
            Write-Host "Known targets: $(($targets | ForEach-Object { $_.Name }) -join ', ')"
            exit 1
        }
    }

    Write-Host "Sharded swift test: $($selected.Count) target(s), serial SwiftPM invocations."
    Write-Host "Oversized XCTest classes are method-batched (threshold=$MethodShardThreshold methods or expanded>$MaxExpandedFilterChars chars)."

    $shardIndex = 0
    $shardTotal = $selected.Count
    foreach ($target in $selected) {
        $shardIndex++
        $context = "{0}/{1} {2}" -f $shardIndex, $shardTotal, $target.Name
        Write-Host ""
        Write-Host "==> Target $context ($($target.Kind))"

        $filters = Get-FiltersForTarget -Target $target -MaxExpandedFilterChars $MaxExpandedFilterChars -MethodShardThreshold $MethodShardThreshold
        $code = Invoke-FilterShards -FilterList $filters -Context $target.Name
        if ($code -ne 0) {
            Write-Host ""
            Write-Host "Sharded test run FAILED at target $context (exit code $code)." -ForegroundColor Red
            exit $code
        }
    }

    Write-Host ""
    Write-Host "Sharded test run PASSED ($shardTotal target(s))." -ForegroundColor Green
    exit 0
}

# Non-sharded path: preserve documented single-invocation behavior, but auto-batch
# when -Filter names one oversized XCTest class (e.g. WinSwiftUITests).
if (-not [string]::IsNullOrWhiteSpace($Filter)) {
    $exact = @($targets | Where-Object { $_.Name -eq $Filter })
    if ($exact.Count -eq 1 -and (Test-RequiresMethodSharding -Target $exact[0] -MaxExpandedFilterChars $MaxExpandedFilterChars -MethodShardThreshold $MethodShardThreshold)) {
        Write-Host "Filter '$Filter' matches oversized $($exact[0].Kind) target; running method-batched serial shards to avoid Windows error 206."
        $filters = Get-FiltersForTarget -Target $exact[0] -MaxExpandedFilterChars $MaxExpandedFilterChars -MethodShardThreshold $MethodShardThreshold
        $code = Invoke-FilterShards -FilterList $filters -Context $exact[0].Name
        exit $code
    }

    $code = Invoke-SwiftTest -Filters @($Filter) -Label $Filter
    exit $code
}

$code = Invoke-SwiftTest -Filters @() -Label "all tests"
exit $code
