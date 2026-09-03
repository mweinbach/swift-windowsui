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
    [int]$MethodShardThreshold = 100,

    # Small XCTest classes can share one bounded alternation filter. This keeps
    # full validation serial while avoiding hundreds of SwiftPM startups.
    [int]$MaxTargetsPerShard = 8,

    # Resume an interrupted serial run without repeating already verified shards.
    # A release-quality validation still starts from the default first shard.
    [int]$StartShard = 1,

    # Opt-in sanitized stdout evidence for the explicit CoreLogic shard plan.
    # A fresh destination below this checkout's artifacts directory is required.
    [string]$EvidenceDirectory = "",

    # Optional identity held by the caller before this evidence attempt.
    # Invalid bound values fail evidence setup inside its existing catch.
    [AllowNull()]$EvidenceSessionId = $null
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$withSwift = Join-Path $PSScriptRoot "with-swift.ps1"
$testSources = Join-Path $repoRoot "Tests\SwiftWindowsCoreLogicTests"
$testModule = "SwiftWindowsCoreLogicTests"
$script:swiftTestEvidenceSession = $null
$evidenceSessionIdWasSupplied = $PSBoundParameters.ContainsKey('EvidenceSessionId')

function Get-ReportedExitCode {
    if ($null -eq $LASTEXITCODE) {
        return $null
    }
    return [int]$LASTEXITCODE
}

function Get-SwiftTestCommentEnd {
    param([string]$Text, [int]$Start)
    if ($Text.Substring($Start, 2) -ceq '//') {
        $end = $Text.IndexOfAny([char[]]@([char]13, [char]10), $Start + 2)
        if ($end -lt 0) { return $Text.Length }
        return $end
    }
    $depth = 1
    $marker = [regex]::new('/\*|\*/')
    for ($match = $marker.Match($Text, $Start + 2); $match.Success; $match = $match.NextMatch()) {
        if ($match.Value -ceq '/*') { $depth++ } else { $depth-- }
        if ($depth -eq 0) { return $match.Index + $match.Length }
    }
    throw "Unterminated block comment in Swift test source."
}

function Get-SwiftTestStringEnd {
    param([string]$Text, [int]$Start)
    $quote = $Start
    while ($quote -lt $Text.Length -and $Text[$quote] -ceq '#') { $quote++ }
    $hashes = $Text.Substring($Start, $quote - $Start)
    $quoteCount = 1
    if ($Text.Length - $quote -ge 3 -and $Text.Substring($quote, 3) -ceq '"""') { $quoteCount = 3 }
    $closing = ('"' * $quoteCount) + $hashes
    $escape = '\' + $hashes
    $position = $quote + $quoteCount
    while ($position -lt $Text.Length) {
        $position = $Text.IndexOfAny([char[]]@('"', '\'), $position)
        if ($position -lt 0) { break }
        if ($Text[$position] -ceq '"' -and $Text.Length - $position -ge $closing.Length -and
            $Text.Substring($position, $closing.Length) -ceq $closing) {
            return $position + $closing.Length
        }
        if ($Text[$position] -ceq '\' -and $Text.Length - $position -ge $escape.Length -and
            $Text.Substring($position, $escape.Length) -ceq $escape) {
            $escaped = $position + $escape.Length
            if ($escaped -ge $Text.Length) { break }
            if ($Text[$escaped] -ceq '(') {
                $position = Get-SwiftTestInterpolationEnd -Text $Text -Start ($escaped + 1)
            } else {
                $position = $escaped + 1
            }
        } else {
            $position++
        }
    }
    throw "Unterminated string in Swift test source."
}

function Get-SwiftTestInterpolationEnd {
    param([string]$Text, [int]$Start)
    # Parentheses inside nested strings or comments do not close interpolation.
    # Everything in this span remains literal payload for declaration discovery.
    $depth = 1
    $position = $Start
    $marker = [regex]::new('//|/\*|#*"|[()]')
    while ($position -lt $Text.Length) {
        $match = $marker.Match($Text, $position)
        if (-not $match.Success) { break }
        if ($match.Value.StartsWith('/')) {
            $position = Get-SwiftTestCommentEnd -Text $Text -Start $match.Index
        } elseif ($match.Value.EndsWith('"')) {
            $position = Get-SwiftTestStringEnd -Text $Text -Start $match.Index
        } else {
            if ($match.Value -ceq '(') { $depth++ } else { $depth-- }
            $position = $match.Index + $match.Length
            if ($depth -eq 0) { return $position }
        }
    }
    throw "Unterminated string interpolation in Swift test source."
}

function Get-SwiftTestCodeWithoutTrivia {
    param([string]$Text)
    # Preserve offsets/newlines while masking comments and string payloads. This
    # is lexical ownership bookkeeping, not Swift parsing or macro evaluation.
    $builder = [Text.StringBuilder]::new()
    $position = 0
    $marker = [regex]::new('//|/\*|#*"')
    while ($position -lt $Text.Length) {
        $match = $marker.Match($Text, $position)
        if (-not $match.Success) {
            [void]$builder.Append($Text, $position, $Text.Length - $position)
            break
        }
        [void]$builder.Append($Text, $position, $match.Index - $position)
        if ($match.Value.StartsWith('/')) {
            $end = Get-SwiftTestCommentEnd -Text $Text -Start $match.Index
        } else {
            $end = Get-SwiftTestStringEnd -Text $Text -Start $match.Index
        }
        [void]$builder.Append([regex]::Replace($Text.Substring($match.Index, $end - $match.Index), '[^\r\n]', ' '))
        $position = $end
    }
    return $builder.ToString()
}

function Get-SwiftTestTypeBodies {
    param([string]$Code, [string]$File)
    $bodies = [Collections.Generic.List[object]]::new()
    $scopes = [Collections.Generic.List[object]]::new()
    $pattern = '(?m)(?<import>\bimport[ \t]+(?:class|struct|enum|protocol|typealias|func|var|let)\b[^\r\n;{}]*)|\b(?<kind>class|struct|actor|enum|protocol|extension)[ \t\r\n]+(?<name>[A-Za-z_][A-Za-z0-9_]*)(?<header>[^{};]*)\{|(?<open>\{)|(?<close>\})|^[ \t]*(?:nonisolated[ \t]+)?func[ \t]+(?<method>test\w+)[ \t]*\([ \t\r\n]*\)'
    foreach ($match in [regex]::Matches($Code, $pattern)) {
        if ($match.Groups['import'].Success) {
            continue
        } elseif ($match.Groups['kind'].Success) {
            $body = $null
            if ($scopes.Count -eq 0) {
                $body = [pscustomobject]@{
                    Name = $match.Groups['name'].Value
                    Kind = $match.Groups['kind'].Value
                    Header = $match.Groups['header'].Value
                    File = $File
                    Methods = [Collections.Generic.List[string]]::new()
                }
                [void]$bodies.Add($body)
            }
            [void]$scopes.Add($body)
        } elseif ($match.Groups['open'].Success) {
            [void]$scopes.Add($null)
        } elseif ($match.Groups['close'].Success) {
            if ($scopes.Count -eq 0) { throw "Unexpected closing brace in Swift test source: $File" }
            $scopes.RemoveAt($scopes.Count - 1)
        } elseif ($scopes.Count -gt 0) {
            $body = $scopes[$scopes.Count - 1]
            if ($null -ne $body -and $body.Kind -cin @('class', 'extension')) {
                [void]$body.Methods.Add($match.Groups['method'].Value)
            }
        }
    }
    if ($scopes.Count -ne 0) { throw "Unterminated type or body in Swift test source: $File" }
    return $bodies.ToArray()
}

function Get-DiscoveredTestTargets {
    param([string]$SourceRoot)
    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        throw "Test source root not found: $SourceRoot"
    }
    $targets = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $bodies = [Collections.Generic.List[object]]::new()
    $files = @(Get-ChildItem -LiteralPath $SourceRoot -Filter "*.swift" -File)
    foreach ($file in $files) {
        $text = [IO.File]::ReadAllText($file.FullName)
        $code = Get-SwiftTestCodeWithoutTrivia -Text $text
        foreach ($body in @(Get-SwiftTestTypeBodies -Code $code -File $file.FullName)) {
            [void]$bodies.Add($body)
        }

        # Preserve the existing Swift Testing suite-name discovery. XCTest
        # attribution below no longer leaks into this independent suite mode.
        $lines = [regex]::Split($text, '\r\n|\n|\r')
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '@Suite') {
                $suiteName = $null
                for ($j = $i; $j -lt [Math]::Min($i + 6, $lines.Count); $j++) {
                    if ($lines[$j] -match '(?:struct|class|actor)\s+(\w+)') {
                        $suiteName = $Matches[1]
                        break
                    }
                }
                if ($suiteName) {
                    $targets[$suiteName] = [pscustomobject]@{
                        Name = $suiteName
                        Kind = "SwiftTesting"
                        File = $file.FullName
                        Methods = [Collections.Generic.List[string]]::new()
                    }
                }
            }
        }
    }

    # Register declarations before attaching any methods. A named extension can
    # precede its class, live in another file, or follow an unrelated helper.
    foreach ($body in $bodies) {
        if ($body.Kind -ceq 'class' -and $body.Header -cmatch '^\s*:\s*(?:XCTest\.)?XCTestCase\b') {
            if ($targets.ContainsKey($body.Name)) { throw "Ambiguous Swift test declaration: $($body.Name)" }
            $targets[$body.Name] = [pscustomobject]@{
                Name = $body.Name
                Kind = "XCTest"
                File = $body.File
                Methods = [Collections.Generic.List[string]]::new()
            }
        }
    }
    $seen = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($body in $bodies) {
        if ($body.Kind -cnotin @('class', 'extension') -or -not $targets.ContainsKey($body.Name)) { continue }
        # Qualified/nested extension ownership is outside this simple-name
        # scanner. Never credit its methods to the first name component.
        if ($body.Kind -ceq 'extension' -and $body.Header -cnotmatch '^\s*(?::|where\b|$)') { continue }
        $target = $targets[$body.Name]
        if ($target.Kind -cne 'XCTest') { continue }
        if (-not $seen.ContainsKey($body.Name)) {
            $seen[$body.Name] = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        }
        foreach ($method in $body.Methods) {
            if (-not $seen[$body.Name].Add($method)) { throw "Ambiguous Swift test method: $($body.Name)/$method" }
            [void]$target.Methods.Add($method)
        }
    }
    return @($targets.Values | Sort-Object Name)
}

function Select-ShardedTestTargets {
    param(
        [object[]]$Targets,
        [string]$Filter = ""
    )

    if ([string]::IsNullOrWhiteSpace($Filter)) {
        return $Targets
    }

    # A complete class/suite name must not also select shorter suffix names.
    # Keep PowerShell's existing case-insensitive equality and wildcard rules.
    $exact = @($Targets | Where-Object { $_.Name -eq $Filter })
    if ($exact.Count -gt 0) {
        return $exact
    }

    return @($Targets | Where-Object {
            $_.Name -like "*$Filter*" -or $Filter -like "*$($_.Name)*"
        })
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
        [string]$Label = "",
        [int]$EvidenceIndex = 0
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
    $swiftTestRecorder = $null
    if ($null -ne $script:swiftTestEvidenceSession -and $EvidenceIndex -gt 0) {
        try { $swiftTestRecorder = Start-SwiftTestEvidenceShard $script:swiftTestEvidenceSession $EvidenceIndex }
        catch {
            try { Add-SwiftTestEvidenceProblem $script:swiftTestEvidenceSession 'observer-call-failed' } catch { }
        }
    }
    if ($null -eq $swiftTestRecorder) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $withSwift swift @invocationArgs | Out-Host
    } else {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $withSwift swift @invocationArgs | ForEach-Object {
            # Preserve the original stream object, even when catch rebinds $_.
            $swiftTestOriginalOutput = $_
            try { Add-SwiftTestEvidenceOutput $swiftTestRecorder $swiftTestOriginalOutput }
            catch {
                try { Add-SwiftTestEvidenceProblem $swiftTestRecorder 'observer-call-failed' } catch { }
            }
            & {
                [CmdletBinding()]
                param()
                $PSCmdlet.WriteObject($swiftTestOriginalOutput, $false)
            }
        } | Out-Host
    }
    $code = Get-ReportedExitCode
    if ($null -ne $swiftTestRecorder) {
        try { Save-SwiftTestEvidenceShard $script:swiftTestEvidenceSession $swiftTestRecorder $code }
        catch {
            try { Add-SwiftTestEvidenceProblem $script:swiftTestEvidenceSession 'observer-call-failed' } catch { }
        }
    }

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

function New-CombinedTargetShard {
    param(
        [object[]]$Targets,
        [int]$EstimatedExpandedChars
    )

    $names = @($Targets | ForEach-Object { $_.Name })
    if ($names.Count -eq 1) {
        $filter = $names[0]
    } else {
        $escaped = @($names | ForEach-Object { [regex]::Escape($_) })
        # XCTest names use Module.Class/method; Swift Testing may use
        # slash-separated components. Bound both sides so FooTests cannot
        # accidentally include FooTestsExtra and exceed the expansion budget.
        $filter = "(^|[./])(" + ($escaped -join "|") + ")([./]|$)"
    }

    return [pscustomobject]@{
        Targets                    = @($Targets)
        Filter                     = $filter
        EstimatedExpandedFilterChars = $EstimatedExpandedChars
    }
}

function Get-TargetExecutionShards {
    param(
        [object[]]$Targets,
        [int]$MaxExpandedFilterChars,
        [int]$MethodShardThreshold,
        [int]$MaxTargetsPerShard
    )

    $shards = New-Object System.Collections.Generic.List[object]
    $pending = New-Object System.Collections.Generic.List[object]
    $pendingExpandedChars = 0
    $targetLimit = [Math]::Max(1, $MaxTargetsPerShard)

    foreach ($target in $Targets) {
        $needsMethodShards = Test-RequiresMethodSharding `
            -Target $target `
            -MaxExpandedFilterChars $MaxExpandedFilterChars `
            -MethodShardThreshold $MethodShardThreshold
        $methodCount = @($target.Methods).Count
        $canCombine = $target.Kind -eq "XCTest" -and $methodCount -gt 0 -and -not $needsMethodShards

        if (-not $canCombine) {
            if ($pending.Count -gt 0) {
                [void]$shards.Add((New-CombinedTargetShard `
                            -Targets $pending.ToArray() `
                            -EstimatedExpandedChars $pendingExpandedChars))
                $pending.Clear()
                $pendingExpandedChars = 0
            }

            $filters = Get-FiltersForTarget `
                -Target $target `
                -MaxExpandedFilterChars $MaxExpandedFilterChars `
                -MethodShardThreshold $MethodShardThreshold
            foreach ($filter in $filters) {
                [void]$shards.Add([pscustomobject]@{
                        Targets                      = @($target)
                        Filter                       = $filter
                        EstimatedExpandedFilterChars = Get-ExpandedIdentifierLength `
                            -ClassName $target.Name -Methods @($target.Methods)
                    })
            }
            continue
        }

        $expandedChars = [Math]::Max(
            1,
            (Get-ExpandedIdentifierLength -ClassName $target.Name -Methods @($target.Methods)))
        if ($pending.Count -gt 0 -and
            ($pending.Count -ge $targetLimit -or
                ($pendingExpandedChars + $expandedChars) -gt $MaxExpandedFilterChars)) {
            [void]$shards.Add((New-CombinedTargetShard `
                        -Targets $pending.ToArray() `
                        -EstimatedExpandedChars $pendingExpandedChars))
            $pending.Clear()
            $pendingExpandedChars = 0
        }

        [void]$pending.Add($target)
        $pendingExpandedChars += $expandedChars
    }

    if ($pending.Count -gt 0) {
        [void]$shards.Add((New-CombinedTargetShard `
                    -Targets $pending.ToArray() `
                    -EstimatedExpandedChars $pendingExpandedChars))
    }

    return $shards.ToArray()
}

# --- main -------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $withSwift)) {
    throw "Missing helper script: $withSwift"
}

if ($StartShard -lt 1) {
    throw "-StartShard must be at least 1."
}
if ($StartShard -ne 1 -and -not $Sharded) {
    throw "-StartShard is only supported with -Sharded."
}
if (-not [string]::IsNullOrWhiteSpace($EvidenceDirectory) -and -not $Sharded) {
    throw "-EvidenceDirectory is only supported with -Sharded."
}

$targets = Get-DiscoveredTestTargets -SourceRoot $testSources

if ($Sharded) {
    $selected = $targets
    if (-not [string]::IsNullOrWhiteSpace($Filter)) {
        $selected = @(Select-ShardedTestTargets -Targets $targets -Filter $Filter)
        if ($selected.Count -eq 0) {
            Write-Host "No discovered test targets match -Filter '$Filter'." -ForegroundColor Red
            Write-Host "Known targets: $(($targets | ForEach-Object { $_.Name }) -join ', ')"
            exit 1
        }
    }

    $executionShards = @(Get-TargetExecutionShards `
            -Targets $selected `
            -MaxExpandedFilterChars $MaxExpandedFilterChars `
            -MethodShardThreshold $MethodShardThreshold `
            -MaxTargetsPerShard $MaxTargetsPerShard)
    Write-Host "Sharded swift test: $($selected.Count) target(s), $($executionShards.Count) serial SwiftPM invocations."
    Write-Host "Oversized XCTest classes are method-batched (threshold=$MethodShardThreshold methods or expanded>$MaxExpandedFilterChars chars)."
    Write-Host "Small XCTest classes share bounded shards (at most $MaxTargetsPerShard targets and $MaxExpandedFilterChars expanded chars)."

    $shardIndex = 0
    $shardTotal = $executionShards.Count
    if ($StartShard -gt $shardTotal) {
        throw "-StartShard $StartShard exceeds the $shardTotal available shard(s)."
    }
    if ($StartShard -gt 1) {
        Write-Host "Resuming at shard $StartShard/$shardTotal; earlier shards are intentionally skipped."
    }

    if (-not [string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
        try {
            . (Join-Path $PSScriptRoot 'swift-test-evidence.ps1')
            $evidenceSessionArguments = @{
                WorkspaceRoot = $repoRoot; Directory = $EvidenceDirectory
                Shards = $executionShards; StartShard = $StartShard
            }
            if ($evidenceSessionIdWasSupplied) {
                $evidenceSessionArguments['SessionId'] = $EvidenceSessionId
            }
            $script:swiftTestEvidenceSession = New-SwiftTestEvidenceSession @evidenceSessionArguments
        } catch {
            # Evidence failure must not prevent the original test invocation or
            # mask its eventual nonzero exit. Full checks evidence separately.
            Write-Host 'CoreLogic evidence setup failed; original tests will still run.' -ForegroundColor Yellow
        }
    }

    foreach ($shard in $executionShards) {
        $shardIndex++
        if ($shardIndex -lt $StartShard) {
            continue
        }

        $targetNames = @($shard.Targets | ForEach-Object { $_.Name })
        $context = "{0}/{1} {2}" -f $shardIndex, $shardTotal, ($targetNames -join ", ")
        Write-Host ""
        Write-Host "==> Shard $context"
        $code = Invoke-SwiftTest -Filters @($shard.Filter) -Label $context -EvidenceIndex $shardIndex
        if ($code -ne 0) {
            Write-Host ""
            Write-Host "Sharded test run FAILED at shard $context (exit code $code)." -ForegroundColor Red
            if ($null -ne $script:swiftTestEvidenceSession) {
                try { Complete-SwiftTestEvidenceSession $script:swiftTestEvidenceSession $code } catch { }
            }
            exit $code
        }
    }

    Write-Host ""
    if ($StartShard -eq 1) {
        Write-Host "Sharded test run PASSED ($($selected.Count) target(s), $shardTotal serial invocation(s))." -ForegroundColor Green
    } else {
        $executedShardCount = $shardTotal - $StartShard + 1
        Write-Host "Resumed sharded test run PASSED ($executedShardCount of $shardTotal serial invocation(s))." -ForegroundColor Green
    }
    if ($null -ne $script:swiftTestEvidenceSession) {
        try { Complete-SwiftTestEvidenceSession $script:swiftTestEvidenceSession 0 } catch { }
    }
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
