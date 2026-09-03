<#
.SYNOPSIS
Tests source attribution and bounded filter planning with synthetic Swift text.
.DESCRIPTION
Loads only named function bodies from test.ps1. It never invokes that script,
SwiftPM, a compiler, a native executable, or any real test source.
#>
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$script:discoveryAssertions = 0
$script:discoveryCases = 0
$script:testModule = "SwiftWindowsCoreLogicTests"

function Assert-Discovery {
    param([bool]$Condition, [string]$Message)
    $script:discoveryAssertions++
    if (-not $Condition) { throw $Message }
}

$sourcePath = Join-Path $RepositoryRoot "scripts/test.ps1"
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
Assert-Discovery (@($parseErrors).Count -eq 0) "The production runner must parse."
$wanted = @(
    "Get-SwiftTestCommentEnd", "Get-SwiftTestStringEnd", "Get-SwiftTestInterpolationEnd",
    "Get-SwiftTestCodeWithoutTrivia", "Get-SwiftTestTypeBodies",
    "Get-DiscoveredTestTargets", "Get-ExpandedIdentifierLength", "Test-RequiresMethodSharding",
    "Get-MethodFilterBatches", "Get-FiltersForTarget", "New-CombinedTargetShard", "Get-TargetExecutionShards"
)
$required = @("Get-DiscoveredTestTargets", "Get-TargetExecutionShards")
foreach ($name in $wanted) {
    $definitions = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name
    }, $true))
    Assert-Discovery ($definitions.Count -le 1) ("Duplicate function: {0}" -f $name)
    if ($required -ccontains $name) {
        Assert-Discovery ($definitions.Count -eq 1) ("Missing function: {0}" -f $name)
    }
    if ($definitions.Count -eq 1) {
        Set-Item -Path ("Function:" + $name) -Value $definitions[0].Body.GetScriptBlock()
    }
}

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('/', '\'))
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $tempRoot ("swift-test-discovery-" + [Guid]::NewGuid().ToString("N"))))
$ownedPrefix = $tempRoot + [IO.Path]::DirectorySeparatorChar
Assert-Discovery ($fixtureRoot.StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase)) "Fixture root must stay under the OS temp directory."
Assert-Discovery (-not (Test-Path -LiteralPath $fixtureRoot)) "Fixture root must be fresh."
$null = New-Item -ItemType Directory -Path $fixtureRoot

function Write-DiscoveryCase {
    param([string]$Name, [System.Collections.IDictionary]$Files)
    $script:discoveryCases++
    $directory = Join-Path $fixtureRoot $Name
    $null = New-Item -ItemType Directory -Path $directory
    foreach ($entry in $Files.GetEnumerator()) {
        Assert-Discovery ([IO.Path]::GetFileName([string]$entry.Key) -ceq [string]$entry.Key) "Synthetic names must be leaf filenames."
        [IO.File]::WriteAllText((Join-Path $directory $entry.Key), [string]$entry.Value, [Text.UTF8Encoding]::new($false))
    }
    return $directory
}

function Assert-DiscoveryMethods {
    param([object[]]$Targets, [string]$Name, [string[]]$Expected)
    $target = @($Targets | Where-Object { $_.Name -ceq $Name })
    Assert-Discovery ($target.Count -eq 1) ("Expected one target named {0}." -f $Name)
    $actual = @($target[0].Methods | ForEach-Object { [string]$_ })
    Assert-Discovery (($actual -join "|") -ceq ($Expected -join "|")) (
        "{0}: expected [{1}], got [{2}]." -f $Name, ($Expected -join ","), ($actual -join ","))
}

try {
    $directory = Write-DiscoveryCase "leading-and-trailing" ([ordered]@{
        "Fixture.swift" = @'
extension BoundaryTests {
    func testBeforeDeclaration() async {}
}
final class BoundaryTests: XCTestCase {
    func testDeclaredBody() async {}
}
extension BoundaryTests {
    func testAfterDeclaration() async {}
}
'@
    })
    $targets = @(Get-DiscoveredTestTargets -SourceRoot $directory)
    Assert-DiscoveryMethods $targets "BoundaryTests" @("testBeforeDeclaration", "testDeclaredBody", "testAfterDeclaration")

    $directory = Write-DiscoveryCase "cross-file" ([ordered]@{
        "00-Early.swift" = @'
extension CrossFileTests {
    func testEarlyFile() async {}
}
extension NotATest {
    func testNotARegisteredClass() {}
}
'@
        "10-Declaration.swift" = @'
final class CrossFileTests: XCTestCase {
    func testDeclaredFile() async {}
}
final class SecondTests: XCTestCase {
    func testSecondClass() async {}
}
'@
        "20-Late.swift" = @'
extension CrossFileTests {
    func testLateFile() async {}
}
extension SecondTests {
    func testSecondExtension() async {}
}
'@
    })
    $targets = @(Get-DiscoveredTestTargets -SourceRoot $directory)
    Assert-DiscoveryMethods $targets "CrossFileTests" @("testEarlyFile", "testDeclaredFile", "testLateFile")
    Assert-DiscoveryMethods $targets "SecondTests" @("testSecondClass", "testSecondExtension")
    Assert-Discovery ($targets.Count -eq 2) "An extension cannot create an XCTest target by itself."

    $directory = Write-DiscoveryCase "helper-scopes" ([ordered]@{
        "Fixture.swift" = @'
final class OwningTests: XCTestCase {
    func testRealMember() async {
        func testLocalFunction() {}
    }
    final class NestedHelper {
        func testNestedHelper() {}
    }
    func testAfterNestedHelper() async {}
    func testTakesAnArgument(_ value: Int) {}
}
final class Observer: XCTestObservation {
    func testCaseWillStart(_ testCase: XCTestCase) {}
    func testCaseDidFinish(_ testCase: XCTestCase) {}
    func testZeroArgumentHelper() {}
}
struct OtherHelper {
    func testStructHelper() {}
}
extension OwningTests {
    func testRealExtension() async {}
}
'@
    })
    $targets = @(Get-DiscoveredTestTargets -SourceRoot $directory)
    Assert-DiscoveryMethods $targets "OwningTests" @("testRealMember", "testAfterNestedHelper", "testRealExtension")
    Assert-Discovery ($targets.Count -eq 1) "Unrelated helper scopes must not become targets."

    $directory = Write-DiscoveryCase "trivia-and-literals" ([ordered]@{
        "Fixture.swift" = @'
/* outer { /* nested } */ final class CommentTests: XCTestCase { */
final class LiteralTests: XCTestCase {
    func testLiterals() async {
        let ordinary = "escaped quote \" and braces } {"
        let raw = #"raw quote " and braces } {"#
        let multiline = """
            } final class PretendTests: XCTestCase {
                func testPretend() {}
            """
        let rawMultiline = #"""
            } extension LiteralTests {
                func testAlsoPretend() {}
            """#
        let interpolation = "value \(String(describing: "{ }")) end"
        let rawInterpolation = #"value \#(String(describing: "} {")) end"#
    }
    // } func testCommentOnly() {}
    func testAfterLiterals() async {}
}
extension LiteralTests /* { nested /* } */ */ {
    func testExtensionAfterTrivia() async {}
}
'@
    })
    $targets = @(Get-DiscoveredTestTargets -SourceRoot $directory)
    Assert-DiscoveryMethods $targets "LiteralTests" @("testLiterals", "testAfterLiterals", "testExtensionAfterTrivia")
    Assert-Discovery ($targets.Count -eq 1) "Literal and comment declarations must be ignored."

    $directory = Write-DiscoveryCase "suite-and-attributes" ([ordered]@{
        "Fixture.swift" = @'
@Suite("Existing Swift Testing suite")
struct ExistingSuite {
    @Test func ordinarySwiftTestingMethod() {}
}
@MainActor
final class MultilineTests
    : XCTestCase
{
    @available(*, deprecated)
    nonisolated func testAttributeAndMultilineParameters(
    ) {}
}
'@
    })
    $targets = @(Get-DiscoveredTestTargets -SourceRoot $directory)
    Assert-DiscoveryMethods $targets "MultilineTests" @("testAttributeAndMultilineParameters")
    $suite = @($targets | Where-Object { $_.Name -ceq "ExistingSuite" })
    Assert-Discovery ($suite.Count -eq 1 -and $suite[0].Kind -ceq "SwiftTesting") "Existing Swift Testing suite discovery is retained."

    $expected = @("testLeadingExtension") + @(1..35 | ForEach-Object { "testDeclaredMethodWithEnoughCharactersToRequireMethodBatching{0:d2}" -f $_ }) + @("testTrailingExtension")
    $body = ($expected[1..35] | ForEach-Object { "    func {0}() async {{}}" -f $_ }) -join [Environment]::NewLine
    $oversizedSource = @'
extension OversizedTests {
    func testLeadingExtension() async {}
}
final class OversizedTests: XCTestCase {
DECLARED_METHODS
}
extension OversizedTests {
    func testTrailingExtension() async {}
}
'@
    $directory = Write-DiscoveryCase "oversized" ([ordered]@{ "Fixture.swift" = $oversizedSource.Replace("DECLARED_METHODS", $body) })
    $targets = @(Get-DiscoveredTestTargets -SourceRoot $directory)
    Assert-DiscoveryMethods $targets "OversizedTests" $expected
    $shards = @(Get-TargetExecutionShards -Targets $targets -MaxExpandedFilterChars 3000 -MethodShardThreshold 100 -MaxTargetsPerShard 8)
    Assert-Discovery ($shards.Count -gt 1) "The extension case must exercise actual method batching."
    foreach ($method in $expected) {
        $id = "SwiftWindowsCoreLogicTests.OversizedTests/" + $method
        $matches = @($shards | Where-Object { [regex]::IsMatch($id, $_.Filter) })
        Assert-Discovery ($matches.Count -eq 1) ("Every declared method must match exactly one planned filter: {0}" -f $method)
    }

    $directory = Write-DiscoveryCase "case-sensitive-ownership" ([ordered]@{
        "Fixture.swift" = @'
final class CaseTests: XCTestCase {
    func testExactOwner() async {}
}
struct caseTests {}
extension caseTests {
    func testUnrelatedCaseHelper() {}
}
final class UpperTests: XCTestCase {
    func testUpperDeclaration() async {}
}
final class upperTests: XCTestCase {
    func testLowerDeclaration() async {}
}
extension UpperTests {
    func testUpperExtension() async {}
}
extension upperTests {
    func testLowerExtension() async {}
}
'@
    })
    $targets = @(Get-DiscoveredTestTargets -SourceRoot $directory)
    Assert-DiscoveryMethods $targets "CaseTests" @("testExactOwner")
    Assert-DiscoveryMethods $targets "UpperTests" @("testUpperDeclaration", "testUpperExtension")
    Assert-DiscoveryMethods $targets "upperTests" @("testLowerDeclaration", "testLowerExtension")
    Assert-Discovery ($targets.Count -eq 3) "Swift type identity must be case-sensitive, including helper extensions."

    $directory = Write-DiscoveryCase "qualified-helper-extension" ([ordered]@{
        "Fixture.swift" = @'
final class QualifiedTests: XCTestCase {
    struct Helper {}
    func testOuterDeclaration() async {}
}
extension QualifiedTests.Helper {
    func testNestedHelper() {}
}
extension QualifiedTests . Helper {
    func testSpacedNestedHelper() {}
}
extension QualifiedTests {
    func testExactExtension() async {}
}
'@
    })
    $targets = @(Get-DiscoveredTestTargets -SourceRoot $directory)
    Assert-DiscoveryMethods $targets "QualifiedTests" @("testOuterDeclaration", "testExactExtension")
    Assert-Discovery ($targets.Count -eq 1) "A qualified extension cannot attach methods to its outer XCTest type."

    $directory = Write-DiscoveryCase "selective-imports" ([ordered]@{
        "Fixture.swift" = @'
import class XCTest.XCTestCase
final class ImportedClassTests: XCTestCase {
    func testAfterClassImport() async {}
}
import struct Foundation.URL
final class ImportedStructTests: XCTestCase {
    func testAfterStructImport() async {}
}
'@
    })
    $targets = @(Get-DiscoveredTestTargets -SourceRoot $directory)
    Assert-DiscoveryMethods $targets "ImportedClassTests" @("testAfterClassImport")
    Assert-DiscoveryMethods $targets "ImportedStructTests" @("testAfterStructImport")
    Assert-Discovery ($targets.Count -eq 2) "Selective imports must not consume following type declarations."

    foreach ($broken in @(
        @{ Name = "unclosed-comment"; Text = "/* unterminated" },
        @{ Name = "unclosed-string"; Text = 'final class BrokenTests: XCTestCase { let x = "unterminated' },
        @{ Name = "unclosed-body"; Text = 'final class BrokenTests: XCTestCase { func testBroken() {}' },
        @{ Name = "unexpected-close"; Text = "}" },
        @{ Name = "duplicate-class"; Text = ("final class DuplicateTests: XCTestCase {}" + [Environment]::NewLine + "final class DuplicateTests: XCTestCase {}") }
    )) {
        $directory = Write-DiscoveryCase $broken.Name ([ordered]@{ "Fixture.swift" = $broken.Text })
        $refused = $false
        try { $null = @(Get-DiscoveredTestTargets -SourceRoot $directory) } catch { $refused = $true }
        Assert-Discovery $refused ("Malformed or ambiguous ownership must refuse: {0}" -f $broken.Name)
    }
    Write-Host ("Source discovery fixtures PASSED ({0} cases, {1} assertions; no SwiftPM)." -f $script:discoveryCases, $script:discoveryAssertions)
} finally {
    # Delete only this newly created, exact temporary directory. Never derive a
    # deletion target from source text or a discovered test name.
    $resolved = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolved.Equals($fixtureRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not $resolved.StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^swift-test-discovery-[0-9a-f]{32}$') {
        throw "Refusing unexpected fixture cleanup target."
    }
    if (Test-Path -LiteralPath $resolved) {
        if ((Get-Item -LiteralPath $resolved).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing reparse-point fixture cleanup."
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

exit 0
