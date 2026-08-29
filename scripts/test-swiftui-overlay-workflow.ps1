#requires -Version 7.0
<#
Focused source and synthetic-data checks for the opt-in Stage A workflow.
This test does not import the collector, execute workflow run blocks, inspect
capture/audit evidence, compile helpers, change environment, or write files.
Only four reviewed pure function definitions are loaded from source ASTs.
#>
[CmdletBinding()]
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:overlayWorkflowAssertions = 0
$script:overlayWorkflowSourceBytes = 0L
$script:overlayWorkflowBaselineSha256 = '24b9c8680528247173e74dfec68a143b85b300bbfb64d43c1e545517782bf51a'

function Assert-OverlayWorkflowTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Overlay workflow assertion failed: $Message" }
    $script:overlayWorkflowAssertions++
}

function Assert-OverlayWorkflowRejects {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    Assert-OverlayWorkflowTest ($null -ne $failure -and $failure -match $Pattern) $Message
}

function Read-OverlayWorkflowTestSource {
    param([string]$RelativePath)
    $path = Join-Path $RepositoryRoot $RelativePath
    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $memory = [IO.MemoryStream]::new()
    try {
        if ($stream.Length -gt 262144) { throw "Source exceeds 256 KiB: $RelativePath" }
        $buffer = [byte[]]::new(8192)
        while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $script:overlayWorkflowSourceBytes += $count
            if ($memory.Length + $count -gt 262144 -or $script:overlayWorkflowSourceBytes -gt 1048576) {
                throw 'Focused workflow source-read budget exceeded.'
            }
            $memory.Write($buffer, 0, $count)
        }
        $bytes = $memory.ToArray()
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xfeff) { $text = $text.Substring(1) }
        return [pscustomobject]@{ path = $path; text = $text; bytes = $bytes }
    } finally { $memory.Dispose(); $stream.Dispose() }
}

function Get-OverlayWorkflowTestAst {
    param([string]$Text, [string]$Context)
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$parseErrors)
    Assert-OverlayWorkflowTest ($parseErrors.Count -eq 0) "$Context parses without executing it"
    return $ast
}

function Get-OverlayWorkflowPureDefinition {
    param($Ast, [string]$Name)
    $definitions = @($Ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name
    }, $true))
    Assert-OverlayWorkflowTest ($definitions.Count -eq 1) "exactly one pure function is selected: $Name"
    $allowedCommands = @('Get-SwiftUIAuditProperty', 'Assert-SwiftUIAuditSha256',
        'Assert-SwiftUIOverlayWorkflowOptions', 'ConvertTo-Json', 'ConvertFrom-Json')
    foreach ($command in @($definitions[0].Body.FindAll({
        param($node) $node -is [Management.Automation.Language.CommandAst]
    }, $true))) {
        Assert-OverlayWorkflowTest ($allowedCommands -ccontains $command.GetCommandName() -and
            $command.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Unknown) "pure function $Name retains its reviewed command closure"
    }
    # This finite check keeps future changes visible; it is not a sandbox.
    $allowedMethods = @('new', 'Add', 'ContainsKey', 'Substring', 'LastIndexOf', 'Contains')
    foreach ($method in @($definitions[0].Body.FindAll({
        param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
    }, $true))) {
        Assert-OverlayWorkflowTest ($method.Member -is [Management.Automation.Language.StringConstantExpressionAst] -and
            $allowedMethods -ccontains $method.Member.Value) "pure function $Name retains only reviewed in-memory method calls"
        if ($method.Member.Value -ceq 'new') {
            Assert-OverlayWorkflowTest ($method.Expression -is [Management.Automation.Language.TypeExpressionAst] -and
                $method.Expression.TypeName.FullName -ceq 'Collections.Generic.HashSet[string]') "pure function $Name constructs only an in-memory string set"
        }
    }
    return $definitions[0].Extent.Text
}

function Copy-OverlayWorkflowTestValue {
    param($Value)
    return ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 100 -Compress -WarningAction Stop) -ErrorAction Stop
}

function ConvertTo-OverlayWorkflowTestJson {
    param($Value)
    return ConvertTo-Json -InputObject $Value -Depth 100 -Compress -WarningAction Stop
}

function New-OverlayWorkflowTestLayout {
    param($Template)
    $roots = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $anchors = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($root in $Template.roots) { $roots.Add($root.rootId, $root.logicalPath) }
    $index = 0
    foreach ($anchor in $Template.identityAnchors) {
        $index++
        $anchors.Add($anchor.anchorId, [pscustomobject]@{ path = $anchor.logicalPath; sha256 = ('{0:x64}' -f $index) })
    }
    return [pscustomobject]@{ roots = $roots; anchors = $anchors }
}

function New-OverlayWorkflowTestPlan {
    param($Template, $Layout, [string]$Selection = 'not-selected')
    return New-SwiftUIOverlayWorkflowRootPlan -Template $Template -Layout $Layout `
        -SourceCaptureSha256 ('a' * 64) -SourceAuditSha256 ('b' * 64) `
        -BaselineManifestSha256 $script:overlayWorkflowBaselineSha256 -DeveloperFrameworksSelection $Selection
}

$workflowSource = Read-OverlayWorkflowTestSource '.github/workflows/swiftui-baseline-capture.yml'
$commonSource = Read-OverlayWorkflowTestSource 'scripts/swiftui-overlay-workflow-common.ps1'
$auditCommonSource = Read-OverlayWorkflowTestSource 'scripts/swiftui-api-audit-common.ps1'
$wrapperSource = Read-OverlayWorkflowTestSource 'scripts/capture-swiftui-overlay-discovery-candidate.ps1'
$templateSource = Read-OverlayWorkflowTestSource 'docs/swiftui-overlay-root-plan.template.json'
$attributesSource = Read-OverlayWorkflowTestSource '.gitattributes'
Assert-OverlayWorkflowTest ($attributesSource.text -cmatch '(?m)^docs/swiftui-overlay-root-plan\.template\.json text eol=lf\r?$') 'Git preserves authorization-template LF bytes on both platforms'
Assert-OverlayWorkflowTest (-not $templateSource.text.Contains("`r")) 'the checked-out authorization template retains its reviewed LF bytes'
$commonAst = Get-OverlayWorkflowTestAst $commonSource.text 'workflow data helper'
$auditCommonAst = Get-OverlayWorkflowTestAst $auditCommonSource.text 'audit helper source'
$wrapperAst = Get-OverlayWorkflowTestAst $wrapperSource.text 'workflow caller'
$definitions = @(
    Get-OverlayWorkflowPureDefinition $auditCommonAst 'Get-SwiftUIAuditProperty'
    Get-OverlayWorkflowPureDefinition $auditCommonAst 'Assert-SwiftUIAuditSha256'
    Get-OverlayWorkflowPureDefinition $commonAst 'Assert-SwiftUIOverlayWorkflowOptions'
    Get-OverlayWorkflowPureDefinition $commonAst 'New-SwiftUIOverlayWorkflowRootPlan'
)
# No top-level source statement or collector dependency is imported.
. ([scriptblock]::Create(($definitions -join [Environment]::NewLine)))

foreach ($selection in @('not-selected', 'selected-optional')) {
    Assert-SwiftUIOverlayWorkflowOptions -TemplateSha256 ('a' * 64) -DeveloperFrameworksSelection $selection
    Assert-OverlayWorkflowTest $true "explicit option $selection accepts a lowercase template digest"
}
foreach ($badDigest in @('', ('a' * 63), ('a' * 65), ('A' * 64), ('g' * 64), (('a' * 64) + "`n"), '$(Get-Process)')) {
    Assert-OverlayWorkflowRejects {
        Assert-SwiftUIOverlayWorkflowOptions -TemplateSha256 $badDigest -DeveloperFrameworksSelection 'not-selected'
    } 'lowercase SHA-256' 'template authorization rejects malformed or executable-looking text as data'
}
foreach ($badSelection in @('', 'unselected', 'false', 'NOT-SELECTED', 'selected-required', 'selected-optional;exit')) {
    Assert-OverlayWorkflowRejects {
        Assert-SwiftUIOverlayWorkflowOptions -TemplateSha256 ('a' * 64) -DeveloperFrameworksSelection $badSelection
    } 'explicit not-selected or selected-optional' 'developer-framework selection must be one exact explicit option'
}

$template = ConvertFrom-Json -InputObject $templateSource.text -ErrorAction Stop
$templateBefore = ConvertTo-OverlayWorkflowTestJson $template
Assert-OverlayWorkflowTest ($template -is [pscustomobject]) 'checked-in template is an object'
Assert-OverlayWorkflowTest ($template.baselineManifestSha256 -ceq $script:overlayWorkflowBaselineSha256) 'template retains the exact literal baseline manifest digest'
Assert-OverlayWorkflowTest (@($template.roots).Count -eq 3) 'template declares exactly three roots'
Assert-OverlayWorkflowTest (@($template.identityAnchors).Count -eq 9) 'template declares exactly nine anchors'
$fixedDeveloper = '/Applications/Xcode_26.6.app/Contents/Developer'
$fixedSdk = $fixedDeveloper + '/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk'
$fixedToolchain = $fixedDeveloper + '/Toolchains/XcodeDefault.xctoolchain'
$fixedRoots = @{ 'selected-sdk' = $fixedSdk; 'selected-swift-resources' = $fixedToolchain + '/usr/lib/swift'
    'platform-developer-frameworks' = $fixedDeveloper + '/Platforms/MacOSX.platform/Developer/Library/Frameworks' }
foreach ($root in $template.roots) {
    Assert-OverlayWorkflowTest (@($fixedRoots.Keys) -ccontains $root.rootId -and
        $root.logicalPath -ceq $fixedRoots[$root.rootId]) 'template root paths retain the exact Xcode and SDK literals'
}
$fixedAnchorPaths = @{ 'swift-tool' = $fixedToolchain + '/usr/bin/swift'
    'extractor-tool' = $fixedToolchain + '/usr/bin/swift-symbolgraph-extract'; 'sdk-settings' = $fixedSdk + '/SDKSettings.json' }
foreach ($interface in @('SwiftUI/arm64e-apple-macos.swiftinterface', 'SwiftUI/x86_64-apple-macos.swiftinterface',
    'SwiftUICore/arm64e-apple-ios-macabi.swiftinterface', 'SwiftUICore/arm64e-apple-macos.swiftinterface',
    'SwiftUICore/x86_64-apple-ios-macabi.swiftinterface', 'SwiftUICore/x86_64-apple-macos.swiftinterface')) {
    $parts = $interface.Split('/')
    $fixedAnchorPaths['interface:' + $interface] = $fixedSdk + '/System/Library/Frameworks/' + $parts[0] +
        '.framework/Modules/' + $parts[0] + '.swiftmodule/' + $parts[1]
}
foreach ($anchor in $template.identityAnchors) {
    $boundary = if (@('swift-tool', 'extractor-tool') -ccontains $anchor.anchorId) { $fixedToolchain } else { $fixedSdk }
    Assert-OverlayWorkflowTest (@($fixedAnchorPaths.Keys) -ccontains $anchor.anchorId -and
        $anchor.logicalPath -ceq $fixedAnchorPaths[$anchor.anchorId] -and $anchor.allowedPhysicalBoundary -ceq $boundary) 'all six interface variants and three tool/SDK anchors retain their exact paths and boundaries'
}
Assert-OverlayWorkflowTest ((@($template.targetContexts | ForEach-Object { $_.target }) -join ',') -ceq
    'arm64-apple-macosx26.5,x86_64-apple-macosx26.5' -and
    @($template.targetContexts | Where-Object { $null -ne $_.targetVariant }).Count -eq 0) 'capture targets remain two macOS triples without an inferred arm64e or macabi selection'
Assert-OverlayWorkflowTest (@($template.lookupAuthorizations).Count -eq 12) 'not-selected template contains exactly the reviewed twelve metadata lookups'
$layout = New-OverlayWorkflowTestLayout $template
$layoutBefore = ConvertTo-OverlayWorkflowTestJson $layout
$notSelected = New-OverlayWorkflowTestPlan $template $layout
$selected = New-OverlayWorkflowTestPlan $template $layout 'selected-optional'

foreach ($plan in @($notSelected, $selected)) {
    Assert-OverlayWorkflowTest ($plan.sourceCaptureSha256 -ceq ('a' * 64) -and
        $plan.sourceAuditSha256 -ceq ('b' * 64) -and $plan.baselineManifestSha256 -ceq $script:overlayWorkflowBaselineSha256) 'runtime source digests bind distinct fields while the baseline remains literal'
    Assert-OverlayWorkflowTest (@($plan.roots).Count -eq 3 -and @($plan.identityAnchors).Count -eq 9) 'binding adds no root or anchor'
    foreach ($anchor in $plan.identityAnchors) {
        Assert-OverlayWorkflowTest ($anchor.expectedSha256 -ceq $layout.anchors[$anchor.anchorId].sha256 -and
            $anchor.logicalPath -ceq $layout.anchors[$anchor.anchorId].path) 'each anchor uses only its captured synthetic hash and literal template path'
    }
    foreach ($property in $template.PSObject.Properties) {
        if (@('sourceCaptureSha256', 'sourceAuditSha256', 'baselineManifestSha256', 'roots', 'identityAnchors', 'lookupAuthorizations') -ccontains $property.Name) { continue }
        Assert-OverlayWorkflowTest ((ConvertTo-OverlayWorkflowTestJson (Get-SwiftUIAuditProperty $plan $property.Name)) -ceq
            (ConvertTo-OverlayWorkflowTestJson $property.Value)) "binding preserves template property $($property.Name)"
    }
    $requiredBefore = @($template.roots | Where-Object { $_.rootId -cne 'platform-developer-frameworks' })
    $requiredAfter = @($plan.roots | Where-Object { $_.rootId -cne 'platform-developer-frameworks' })
    Assert-OverlayWorkflowTest ($requiredAfter.Count -eq 2 -and
        (ConvertTo-OverlayWorkflowTestJson $requiredAfter) -ceq (ConvertTo-OverlayWorkflowTestJson $requiredBefore)) 'required roots retain literal physical expectations and boundaries'
    Assert-OverlayWorkflowTest ((ConvertTo-OverlayWorkflowTestJson $plan) -cnotmatch 'RUNTIME_') 'every declared runtime marker is resolved'
}

$unselectedRoot = @($notSelected.roots | Where-Object { $_.rootId -ceq 'platform-developer-frameworks' })
Assert-OverlayWorkflowTest ($unselectedRoot.Count -eq 1 -and $unselectedRoot[0].selection -ceq 'not-selected' -and
    $null -eq $unselectedRoot[0].expectedPhysicalPath -and $null -eq $unselectedRoot[0].allowedPhysicalBoundary) 'not-selected optional root acquires no physical expectation or boundary'
Assert-OverlayWorkflowTest ((ConvertTo-OverlayWorkflowTestJson $notSelected.lookupAuthorizations) -ceq
    (ConvertTo-OverlayWorkflowTestJson $template.lookupAuthorizations)) 'not-selected does not add a metadata lookup'
$selectedRoot = @($selected.roots | Where-Object { $_.rootId -ceq 'platform-developer-frameworks' })
Assert-OverlayWorkflowTest ($selectedRoot.Count -eq 1 -and $selectedRoot[0].selection -ceq 'selected-optional' -and
    $selectedRoot[0].expectedPhysicalPath -ceq $selectedRoot[0].logicalPath -and
    $selectedRoot[0].allowedPhysicalBoundary -ceq $selectedRoot[0].logicalPath) 'selected optional root receives only its reviewed literal expectation and exact boundary'
$extraLookups = @($selected.lookupAuthorizations | Where-Object { $_.lookupId -ceq 'optional-platform-library-metadata' })
$optionalParent = $selectedRoot[0].logicalPath.Substring(0, $selectedRoot[0].logicalPath.LastIndexOf('/'))
Assert-OverlayWorkflowTest (@($selected.lookupAuthorizations).Count -eq @($template.lookupAuthorizations).Count + 1 -and
    $extraLookups.Count -eq 1 -and $extraLookups[0].kind -ceq 'ancestor-metadata' -and
    $extraLookups[0].exactPath -ceq $optionalParent -and -not $extraLookups[0].mayEnumerateChildren -and
    -not $extraLookups[0].mayTraverseDescendants) 'selected optional root adds one exact ancestor metadata lookup without listing or traversal'
foreach ($lookup in $selected.lookupAuthorizations) {
    Assert-OverlayWorkflowTest ($lookup.kind -cne 'nonrecursive-parent-listing' -and
        -not $lookup.mayEnumerateChildren -and -not $lookup.mayTraverseDescendants) 'no workflow lookup authorizes parent listing, descendant traversal, or absence inference'
}
Assert-OverlayWorkflowTest ((ConvertTo-OverlayWorkflowTestJson $template) -ceq $templateBefore -and
    (ConvertTo-OverlayWorkflowTestJson $layout) -ceq $layoutBefore) 'both selections leave the supplied template and captured-layout objects unchanged'

foreach ($bindingName in @('sourceCaptureSha256', 'sourceAuditSha256')) {
    $changed = Copy-OverlayWorkflowTestValue $template
    $changed.$bindingName = 'd' * 64
    Assert-OverlayWorkflowRejects { New-OverlayWorkflowTestPlan $changed $layout } 'changed runtime binding' "template cannot prebind $bindingName"
}
foreach ($case in @(
    @{ name = 'duplicate root'; pattern = 'captured layout'; mutate = { param($value) $value.roots = @($value.roots) + @($value.roots[0]) } },
    @{ name = 'missing root'; pattern = 'all three root'; mutate = { param($value) $value.roots = @($value.roots | Select-Object -Skip 1) } },
    @{ name = 'changed literal root'; pattern = 'captured layout'; mutate = { param($value) $value.roots[0].logicalPath += '/unreviewed' } },
    @{ name = 'broadened required boundary'; pattern = 'Required roots'; mutate = { param($value) @($value.roots | Where-Object { $_.selection -ceq 'required' })[0].allowedPhysicalBoundary = '/' } },
    @{ name = 'preselected optional root'; pattern = 'must start'; mutate = { param($value) @($value.roots | Where-Object { $_.rootId -ceq 'platform-developer-frameworks' })[0].selection = 'selected-optional' } },
    @{ name = 'duplicate anchor'; pattern = 'unknown or duplicate'; mutate = { param($value) $value.identityAnchors = @($value.identityAnchors) + @($value.identityAnchors[0]) } },
    @{ name = 'missing anchor'; pattern = 'every captured identity anchor'; mutate = { param($value) $value.identityAnchors = @($value.identityAnchors | Select-Object -Skip 1) } },
    @{ name = 'changed anchor path'; pattern = 'anchor path'; mutate = { param($value) $value.identityAnchors[0].logicalPath += '/unreviewed' } },
    @{ name = 'prebound anchor'; pattern = 'anchor path'; mutate = { param($value) $value.identityAnchors[0].expectedSha256 = 'e' * 64 } },
    @{ name = 'parent listing'; pattern = 'metadata lookups only'; mutate = { param($value) $value.lookupAuthorizations[0].kind = 'nonrecursive-parent-listing' } },
    @{ name = 'child enumeration'; pattern = 'metadata lookups only'; mutate = { param($value) $value.lookupAuthorizations[0].mayEnumerateChildren = $true } },
    @{ name = 'descendant traversal'; pattern = 'metadata lookups only'; mutate = { param($value) $value.lookupAuthorizations[0].mayTraverseDescendants = $true } }
)) {
    $changed = Copy-OverlayWorkflowTestValue $template
    & $case.mutate $changed
    $changedBefore = ConvertTo-OverlayWorkflowTestJson $changed
    Assert-OverlayWorkflowRejects { New-OverlayWorkflowTestPlan $changed $layout } $case.pattern ("binding rejects " + $case.name)
    Assert-OverlayWorkflowTest ((ConvertTo-OverlayWorkflowTestJson $changed) -ceq $changedBefore) ("rejection leaves its supplied template unchanged: " + $case.name)
}
$badLayout = New-OverlayWorkflowTestLayout $template
$badLayout.anchors[$template.identityAnchors[0].anchorId].sha256 = 'invalid'
Assert-OverlayWorkflowRejects { New-OverlayWorkflowTestPlan $template $badLayout } 'lowercase SHA-256' 'captured anchor digest remains validated'
foreach ($digestParameter in @('SourceCaptureSha256', 'SourceAuditSha256', 'BaselineManifestSha256')) {
    $arguments = @{ Template = $template; Layout = $layout; SourceCaptureSha256 = ('a' * 64)
        SourceAuditSha256 = ('b' * 64); BaselineManifestSha256 = $script:overlayWorkflowBaselineSha256
        DeveloperFrameworksSelection = 'not-selected' }
    $arguments[$digestParameter] = 'invalid'
    Assert-OverlayWorkflowRejects { New-SwiftUIOverlayWorkflowRootPlan @arguments } 'lowercase SHA-256' "runtime digest syntax remains validated: $digestParameter"
}
Assert-OverlayWorkflowRejects {
    New-SwiftUIOverlayWorkflowRootPlan -Template $template -Layout $layout -SourceCaptureSha256 ('a' * 64) `
        -SourceAuditSha256 ('b' * 64) -BaselineManifestSha256 ('c' * 64) -DeveloperFrameworksSelection 'not-selected'
} 'literal reviewed template binding' 'a different valid baseline digest cannot be substituted at runtime'
$changed = Copy-OverlayWorkflowTestValue $template
$changed.baselineManifestSha256 = 'RUNTIME_BASELINE_SHA256'
Assert-OverlayWorkflowRejects { New-OverlayWorkflowTestPlan $changed $layout } 'literal reviewed template binding' 'baseline authorization cannot be replaced by a runtime marker'
Assert-OverlayWorkflowRejects { New-OverlayWorkflowTestPlan $template $layout 'unselected' } 'explicit developer-framework selection' 'plan binding independently requires an explicit optional-root choice'
Assert-OverlayWorkflowTest ((ConvertTo-OverlayWorkflowTestJson $template) -ceq $templateBefore -and
    (ConvertTo-OverlayWorkflowTestJson $layout) -ceq $layoutBefore) 'all rejected bindings leave the original template and layout unchanged'

# Static workflow and wrapper assertions follow; no run block is invoked.
$workflow = $workflowSource.text
$steps = @([regex]::Matches($workflow, '(?ms)^ {6}- name: [^\r\n]+\r?\n.*?(?=^ {6}- name:|\z)'))
function Get-OverlayWorkflowTestStep {
    param([string]$Pattern)
    $matches = @($steps | Where-Object { $_.Value -cmatch $Pattern })
    Assert-OverlayWorkflowTest ($matches.Count -eq 1) "workflow has exactly one step matching $Pattern"
    return $matches[0]
}
foreach ($step in $steps) {
    $block = [regex]::Match($step.Value, '(?ms)^ {8}run: \|[ \t]*\r?\n(?<code>.*)\z')
    $line = [regex]::Match($step.Value, '(?m)^ {8}run: (?!\|)(?<code>[^\r\n]+)')
    if (-not $block.Success -and -not $line.Success) { continue }
    $code = if ($block.Success) { $block.Groups['code'].Value -replace '(?m)^ {10}', '' } else { $line.Groups['code'].Value }
    [void](Get-OverlayWorkflowTestAst $code 'workflow PowerShell run block')
    Assert-OverlayWorkflowTest ($code -cnotmatch '\$\{\{\s*(?:github\.event\.)?inputs\.') 'raw workflow input is not interpolated into executable PowerShell'
}

$dispatch = [regex]::Match($workflow, '(?ms)^ {2}workflow_dispatch:\r?\n(?<body>.*?)^ {2}push:').Groups['body'].Value
$inputNames = @([regex]::Matches($dispatch, '(?m)^ {6}(?<name>[a-z_][a-z_0-9]*):\r?$') | ForEach-Object { $_.Groups['name'].Value })
Assert-OverlayWorkflowTest ($inputNames.Count -eq 3 -and
    ($inputNames -join ',') -ceq 'capture_overlay_discovery,overlay_root_plan_template_sha256,overlay_developer_frameworks') 'manual dispatch exposes only the three explicit overlay inputs'
$optInInput = [regex]::Match($dispatch, '(?ms)^ {6}capture_overlay_discovery:\r?\n(?<body>.*?)(?=^ {6}[a-z_][a-z_0-9]*:|\z)').Groups['body'].Value
$hashInput = [regex]::Match($dispatch, '(?ms)^ {6}overlay_root_plan_template_sha256:\r?\n(?<body>.*?)(?=^ {6}[a-z_][a-z_0-9]*:|\z)').Groups['body'].Value
$selectionInput = [regex]::Match($dispatch, '(?ms)^ {6}overlay_developer_frameworks:\r?\n(?<body>.*?)(?=^ {6}[a-z_][a-z_0-9]*:|\z)').Groups['body'].Value
Assert-OverlayWorkflowTest ($optInInput -cmatch '(?m)^ {8}type: boolean\r?$' -and
    $optInInput -cmatch '(?m)^ {8}default: false\r?$') 'overlay discovery is a typed boolean with a false default'
Assert-OverlayWorkflowTest ($hashInput -cmatch '(?m)^ {8}type: string\r?$' -and
    $hashInput -cmatch '(?m)^ {8}default: ""\r?$') 'template authorization has no implicit hash default'
$selectionOptions = @([regex]::Matches($selectionInput, '(?m)^ {10}- (?<value>[^\r\n]+)\r?$') | ForEach-Object { $_.Groups['value'].Value })
Assert-OverlayWorkflowTest ($selectionInput -cmatch '(?m)^ {8}type: choice\r?$' -and
    $selectionInput -cmatch '(?m)^ {8}default: unselected\r?$' -and
    ($selectionOptions -join ',') -ceq 'unselected,not-selected,selected-optional') 'optional-root choice starts unselected and permits only the two explicit decisions'

$checkoutStep = Get-OverlayWorkflowTestStep '(?m)^ {8}uses: actions/checkout@v4\r?$'
$requestStep = Get-OverlayWorkflowTestStep '(?m)^ {8}id: overlay-request\r?$'
$exportStep = Get-OverlayWorkflowTestStep '(?m)^ {8}id: sdk-export\r?$'
$auditStep = Get-OverlayWorkflowTestStep '(?m)^ {8}id: api-audit\r?$'
$rgbStep = Get-OverlayWorkflowTestStep '(?m)^ {8}id: rgb-native\r?$'
$materialStep = Get-OverlayWorkflowTestStep 'run: \./scripts/capture-swiftui-material-reference\.ps1'
$discoveryStep = Get-OverlayWorkflowTestStep '(?m)^ {8}id: overlay-discovery\r?$'
$uploadStep = Get-OverlayWorkflowTestStep '(?m)^ {6}- name: Upload candidate evidence and failure diagnostics\r?$'
$rgbUploadStep = Get-OverlayWorkflowTestStep '(?m)^ {6}- name: Upload RGB synthetic test diagnostics\r?$'
$expectedRequestGate = "github.event_name == 'workflow_dispatch' && inputs.capture_overlay_discovery"
$expectedAuditGate = "!cancelled() && steps.sdk-export.outcome == 'success' && steps.sdk-export.outputs.capture-status == 'exported-awaiting-review'"
$expectedRgbGate = $expectedAuditGate + " && steps.api-audit.outcome == 'success'"
$expectedDiscoveryGate = "!cancelled() && github.event_name == 'workflow_dispatch' && inputs.capture_overlay_discovery && steps.overlay-request.outcome == 'success' && steps.sdk-export.outcome == 'success' && steps.sdk-export.outputs.capture-status == 'exported-awaiting-review' && steps.api-audit.outcome == 'success'"
foreach ($gateBinding in @(
    @{ step = $requestStep; expected = $expectedRequestGate; name = 'request' },
    @{ step = $auditStep; expected = $expectedAuditGate; name = 'existing audit' },
    @{ step = $rgbStep; expected = $expectedRgbGate; name = 'existing RGB' },
    @{ step = $discoveryStep; expected = $expectedDiscoveryGate; name = 'discovery' }
)) {
    $conditions = @([regex]::Matches($gateBinding.step.Value, '(?m)^ {8}if: \$\{\{ (?<condition>[^\r\n]+) \}\}\r?$'))
    Assert-OverlayWorkflowTest ($conditions.Count -eq 1 -and
        $conditions[0].Groups['condition'].Value -ceq $gateBinding.expected) ("exact workflow gate remains explicit: " + $gateBinding.name)
}
Assert-OverlayWorkflowTest ($checkoutStep.Index -lt $requestStep.Index -and $requestStep.Index -lt $exportStep.Index -and
    $auditStep.Index -lt $rgbStep.Index -and $rgbStep.Index -lt $discoveryStep.Index -and
    $discoveryStep.Index -lt $rgbUploadStep.Index -and $rgbUploadStep.Index -lt $uploadStep.Index) 'request is checked early and optional discovery follows existing native work before both uploads'
Assert-OverlayWorkflowTest ($workflow -cnotmatch '(?m)^\s+continue-on-error:') 'the optional caller does not suppress step or job failures'
Assert-OverlayWorkflowTest ($materialStep.Value -cnotmatch '(?m)^ {8}if:' -and
    $materialStep.Value -cmatch '(?m)^ {8}timeout-minutes: 15\r?$' -and
    $materialStep.Value -cmatch '(?m)^ {8}run: \./scripts/capture-swiftui-material-reference\.ps1 -CaptureRoot \$env:SWIFTUI_CAPTURE_ROOT -HostingContextExperiment\r?$') 'existing material capture gate, budget, and command remain unchanged'
Assert-OverlayWorkflowTest ($workflow -cmatch '(?m)^ {4}runs-on: macos-26-intel\r?$' -and
    $workflow -cmatch '(?m)^ {4}timeout-minutes: 90\r?$' -and
    $workflow -cmatch '(?m)^ {6}DEVELOPER_DIR: /Applications/Xcode_26\.6\.app/Contents/Developer\r?$') 'runner, Xcode, and whole-job budget remain pinned'
Assert-OverlayWorkflowTest ($checkoutStep.Value -cmatch '(?m)^ {10}ref: \$\{\{ github\.sha \}\}\r?$' -and
    $checkoutStep.Value -cmatch '(?m)^ {10}persist-credentials: false\r?$' -and
    $checkoutStep.Value -cmatch '(?m)^ {10}submodules: false\r?$') 'checkout retains exact commit, credential, and submodule settings'
Assert-OverlayWorkflowTest ($requestStep.Value -cmatch '(?m)^ {8}timeout-minutes: 2\r?$' -and
    $discoveryStep.Value -cmatch '(?m)^ {8}timeout-minutes: 20\r?$') 'optional stages have explicit bounded step budgets'
foreach ($step in @($requestStep, $discoveryStep)) {
    Assert-OverlayWorkflowTest ($step.Value -cmatch '(?m)^ {10}SWIFTUI_OVERLAY_TEMPLATE_SHA256: \$\{\{ inputs\.overlay_root_plan_template_sha256 \}\}\r?$' -and
        $step.Value -cmatch '(?m)^ {10}SWIFTUI_OVERLAY_DEVELOPER_FRAMEWORKS: \$\{\{ inputs\.overlay_developer_frameworks \}\}\r?$') 'overlay inputs enter PowerShell as environment data'
}
Assert-OverlayWorkflowTest ($requestStep.Value -cmatch '(?m)^ {8}run: \./scripts/capture-swiftui-overlay-discovery-candidate\.ps1 -TemplateSha256 \$env:SWIFTUI_OVERLAY_TEMPLATE_SHA256 -DeveloperFrameworksSelection \$env:SWIFTUI_OVERLAY_DEVELOPER_FRAMEWORKS -ValidateOnly\r?$') 'request step only invokes the bounded template/options mode'
Assert-OverlayWorkflowTest ($discoveryStep.Value -cmatch '(?m)^ {10}SWIFTUI_CAPTURE_ROOT: \$\{\{ steps\.sdk-export\.outputs\.capture-root \}\}\r?$' -and
    $discoveryStep.Value -cmatch '(?m)^ {8}run: \./scripts/capture-swiftui-overlay-discovery-candidate\.ps1 -TemplateSha256 \$env:SWIFTUI_OVERLAY_TEMPLATE_SHA256 -DeveloperFrameworksSelection \$env:SWIFTUI_OVERLAY_DEVELOPER_FRAMEWORKS -CaptureRoot \$env:SWIFTUI_CAPTURE_ROOT\r?$') 'discovery receives only the explicit capture output and reviewed request options'

# Translate only the exact predicate already compared above. These are tests of
# its explicit boolean terms, not an implementation of the Actions evaluator.
$discoveryCondition = [regex]::Match($discoveryStep.Value, '(?m)^ {8}if: \$\{\{ (?<condition>[^\r\n]+) \}\}\r?$').Groups['condition'].Value
$gateCode = $discoveryCondition.Replace('!cancelled()', '(-not $State.cancelled)').
    Replace('github.event_name', '$State.eventName').Replace('inputs.capture_overlay_discovery', '$State.optIn').
    Replace('steps.overlay-request.outcome', '$State.requestOutcome').Replace('steps.sdk-export.outcome', '$State.exportOutcome').
    Replace('steps.sdk-export.outputs.capture-status', '$State.captureStatus').Replace('steps.api-audit.outcome', '$State.auditOutcome').
    Replace(' == ', ' -eq ').Replace(' && ', ' -and ')
$gateBlock = [scriptblock]::Create('param($State)' + [Environment]::NewLine + $gateCode)
foreach ($gateCase in @(
    @{ name = 'explicit successful manual opt-in'; expected = $true },
    @{ name = 'push event even with opt-in data'; eventName = 'push'; expected = $false },
    @{ name = 'manual default false'; optIn = $false; expected = $false },
    @{ name = 'cancellation'; cancelled = $true; expected = $false },
    @{ name = 'rejected request'; requestOutcome = 'failure'; expected = $false },
    @{ name = 'skipped request'; requestOutcome = 'skipped'; expected = $false },
    @{ name = 'failed SDK export'; exportOutcome = 'failure'; expected = $false },
    @{ name = 'skipped SDK export'; exportOutcome = 'skipped'; expected = $false },
    @{ name = 'wrong capture status'; captureStatus = 'failed'; expected = $false },
    @{ name = 'failed audit'; auditOutcome = 'failure'; expected = $false },
    @{ name = 'skipped audit'; auditOutcome = 'skipped'; expected = $false },
    @{ name = 'independent material failure'; materialOutcome = 'failure'; expected = $true },
    @{ name = 'independent RGB failure'; rgbOutcome = 'failure'; expected = $true }
)) {
    $state = @{ cancelled = $false; eventName = 'workflow_dispatch'; optIn = $true; requestOutcome = 'success'
        exportOutcome = 'success'; captureStatus = 'exported-awaiting-review'; auditOutcome = 'success'
        materialOutcome = 'success'; rgbOutcome = 'success' }
    foreach ($key in $gateCase.Keys) { if ($state.ContainsKey($key)) { $state[$key] = $gateCase[$key] } }
    Assert-OverlayWorkflowTest ((& $gateBlock ([pscustomobject]$state)) -eq $gateCase.expected) ("checked discovery predicate handles " + $gateCase.name)
}

Assert-OverlayWorkflowTest (@($steps | Where-Object { $_.Value -match 'uses: actions/upload-artifact@' }).Count -eq 2) 'no additional upload or exclusion replaces the existing evidence uploads'
Assert-OverlayWorkflowTest ($uploadStep.Value -cmatch '(?m)^ {8}if: always\(\)\r?$' -and
    $uploadStep.Value -cmatch '(?m)^ {8}uses: actions/upload-artifact@v4\r?$' -and
    $uploadStep.Value -cmatch '(?m)^ {10}include-hidden-files: true\r?$' -and
    $uploadStep.Value -cmatch '(?m)^ {10}if-no-files-found: error\r?$' -and
    $uploadStep.Value -cmatch '(?m)^ {10}retention-days: 30\r?$') 'candidate diagnostics retain unconditional upload, hidden files, missing-file failure, and 30-day retention'
Assert-OverlayWorkflowTest ($uploadStep.Value -cmatch '(?m)^ {10}name: swiftui-macos-26\.5-xcode-26\.6-candidate-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}\r?$') 'candidate artifact remains bound to the run and attempt'
$uploadPaths = [regex]::Match($uploadStep.Value, '(?ms)^ {10}path: \|\r?\n(?<paths>(?:^ {12}[^\r\n]+\r?\n?)+)').Groups['paths'].Value
$pathEntries = @($uploadPaths -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
Assert-OverlayWorkflowTest ($pathEntries.Count -eq 2 -and
    $pathEntries[0] -ceq 'artifacts/swiftui-baseline/github-actions/' -and
    $pathEntries[1] -ceq '!artifacts/swiftui-baseline/github-actions/capture/module-cache/**') 'request and discovery siblings remain included; only captured module cache is excluded'
Assert-OverlayWorkflowTest ($rgbUploadStep.Value -cmatch '(?m)^ {8}if: \$\{\{ always\(\) && steps\.rgb-fixtures\.outcome != '''' && steps\.rgb-fixtures\.outcome != ''skipped'' \}\}\r?$' -and
    $rgbUploadStep.Value -cmatch '(?m)^ {10}path: artifacts/swiftui-baseline/color-rgb-synthetic/\r?$' -and
    $rgbUploadStep.Value -cmatch '(?m)^ {10}retention-days: 30\r?$') 'the separate RGB diagnostic gate, path, and retention stay unchanged'

$wrapperCommands = @($wrapperAst.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true))
$optionCalls = @($wrapperCommands | Where-Object { $_.GetCommandName() -ceq 'Assert-SwiftUIOverlayWorkflowOptions' })
$validateBranches = @($wrapperAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -ceq '$ValidateOnly'
}, $true))
$intakeCalls = @($wrapperCommands | Where-Object { $_.GetCommandName() -ceq 'Read-SwiftUIAPIReviewInputs' })
$collectorCalls = @($wrapperCommands | Where-Object {
    $_.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Ampersand -and
    $_.Extent.Text -cmatch "'capture-swiftui-overlay-discovery\.ps1'"
})
Assert-OverlayWorkflowTest ($optionCalls.Count -eq 1 -and $validateBranches.Count -eq 1 -and $intakeCalls.Count -eq 1 -and
    $collectorCalls.Count -eq 1 -and $optionCalls[0].Extent.StartOffset -lt $validateBranches[0].Extent.StartOffset -and
    $validateBranches[0].Extent.EndOffset -lt $intakeCalls[0].Extent.StartOffset -and
    $intakeCalls[0].Extent.StartOffset -lt $collectorCalls[0].Extent.StartOffset) 'caller validates options and returns from ValidateOnly before production intake or collection'
Assert-OverlayWorkflowTest ($validateBranches[0].Extent.Text -cmatch 'rootPlanValidated = \$false; sdkObserved = \$false; nativeCensusPerformed = \$false' -and
    @($validateBranches[0].FindAll({ param($node) $node -is [Management.Automation.Language.ReturnStatementAst] }, $true)).Count -eq 1) 'bounded preflight makes no root-plan or SDK-observation claim'
Assert-OverlayWorkflowTest ($wrapperSource.text -cmatch 'if \(\$templateBytes\.sha256 -cne \$TemplateSha256\)' -and
    $wrapperSource.text.IndexOf('if ($templateBytes.sha256 -cne $TemplateSha256)') -lt $validateBranches[0].Extent.StartOffset) 'ValidateOnly requires the actual bounded template bytes to match the supplied digest'
Assert-OverlayWorkflowTest ($wrapperSource.text -cmatch '(?m)^\$evidenceRoot = Join-Path \$repositoryRoot ''artifacts/swiftui-baseline/github-actions''\r?$' -and
    $wrapperSource.text -cmatch '(?m)^\$requestRoot = Join-Path \$evidenceRoot ''overlay-discovery-request''\r?$' -and
    $wrapperSource.text -cmatch '(?m)^\$outputRoot = Join-Path \$evidenceRoot ''overlay-discovery''\r?$') 'request and result are separate fixed siblings under the retained evidence root'
$newDirectories = @($wrapperCommands | Where-Object { $_.GetCommandName() -ceq 'New-Item' })
Assert-OverlayWorkflowTest ($newDirectories.Count -eq 1 -and
    $newDirectories[0].Extent.Text -ceq 'New-Item -ItemType Directory -Path $requestRoot') 'caller creates only its request directory, leaving the collector output fresh'
$collectorParameters = @($collectorCalls[0].CommandElements | Where-Object { $_ -is [Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
Assert-OverlayWorkflowTest (($collectorParameters -join ',') -ceq 'CaptureRoot,AuditRoot,ManifestPath,RootPlanPath,ExpectedRootPlanSha256,OutputDirectory') 'collector receives the original guard-bearing parameters without bypass flags'
foreach ($argumentPattern in @('-CaptureRoot\s+\$expectedCaptureRoot', '-AuditRoot\s+\$auditRoot', '-ManifestPath\s+\$manifestPath',
    '-RootPlanPath\s+\$planPath', '-ExpectedRootPlanSha256\s+\$planFile\.sha256', '-OutputDirectory\s+\$outputRoot')) {
    Assert-OverlayWorkflowTest ($collectorCalls[0].Extent.Text -cmatch $argumentPattern) 'collector input uses the expected fixed source or generated integrity binding'
}
Assert-OverlayWorkflowTest ($wrapperSource.text -cmatch 'if \(\$complete -isnot \[bool\] -or -not \$complete\) \{ throw ' -and
    $wrapperSource.text -cmatch 'if \(\$null -ne \$failure\) \{ throw \$failure \}') 'incomplete collection and caught failures remain failures'
$retainedFinally = @($wrapperAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.TryStatementAst] -and $null -ne $node.Finally -and
    $node.Finally.Extent.Text.Contains('Write-SwiftUIBaselineJson -Value $context -Path $contextPath')
}, $true))
Assert-OverlayWorkflowTest ($retainedFinally.Count -eq 1 -and
    $wrapperSource.text -cmatch 'identityReviewPerformed = \$false; overlayCompleteness = ''unverified''; releaseQualified = \$false') 'request diagnostics are finalized without identity approval, overlay completeness, or release qualification'

$templateAfter = Read-OverlayWorkflowTestSource 'docs/swiftui-overlay-root-plan.template.json'
Assert-OverlayWorkflowTest ([Convert]::ToBase64String($templateSource.bytes) -ceq
    [Convert]::ToBase64String($templateAfter.bytes)) 'the real checked-in template bytes remain unchanged'
Write-Host ("Overlay workflow focused source/synthetic checks passed: {0} assertions; {1} source bytes; no collector or native work." -f
    $script:overlayWorkflowAssertions, $script:overlayWorkflowSourceBytes)
