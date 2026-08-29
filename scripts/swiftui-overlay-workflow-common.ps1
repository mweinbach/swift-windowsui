# Fixed-template data binding for the opt-in Stage A workflow caller only.
# These functions perform no SDK observation, compiler initialization or census.
. (Join-Path $PSScriptRoot 'swiftui-api-audit-common.ps1')

function Assert-SwiftUIOverlayWorkflowOptions {
    param([AllowEmptyString()][string]$TemplateSha256,
        [AllowEmptyString()][string]$DeveloperFrameworksSelection)

    Assert-SwiftUIAuditSha256 $TemplateSha256 'overlay root-plan template authorization'
    if (@('not-selected', 'selected-optional') -cnotcontains $DeveloperFrameworksSelection) {
        throw 'Opt-in overlay discovery requires an explicit not-selected or selected-optional developer-framework choice.'
    }
}

function New-SwiftUIOverlayWorkflowRootPlan {
    param([Parameter(Mandatory)]$Template, [Parameter(Mandatory)]$Layout,
        [Parameter(Mandatory)][string]$SourceCaptureSha256,
        [Parameter(Mandatory)][string]$SourceAuditSha256,
        [Parameter(Mandatory)][string]$BaselineManifestSha256,
        [Parameter(Mandatory)][string]$DeveloperFrameworksSelection)

    foreach ($digest in @($SourceCaptureSha256, $SourceAuditSha256, $BaselineManifestSha256)) {
        Assert-SwiftUIAuditSha256 $digest 'runtime source binding'
    }
    if (@('not-selected', 'selected-optional') -cnotcontains $DeveloperFrameworksSelection) {
        throw 'Runtime binding requires an explicit developer-framework selection.'
    }
    if ($Template -isnot [pscustomobject]) { throw 'The reviewed root-plan template must be an object.' }
    # The production caller uses the existing strict metadata reader before this
    # projection. Clone the object so the original template remains untouched.
    $plan = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Template -Depth 100 -WarningAction Stop) -ErrorAction Stop
    foreach ($binding in @(
        @('sourceCaptureSha256', 'RUNTIME_CAPTURE_SHA256', $SourceCaptureSha256),
        @('sourceAuditSha256', 'RUNTIME_AUDIT_SHA256', $SourceAuditSha256)
    )) {
        if ((Get-SwiftUIAuditProperty $plan $binding[0]) -cne $binding[1]) {
            throw "The reviewed template has a changed runtime binding '$($binding[0])'."
        }
        $plan.($binding[0]) = $binding[2]
    }
    if ((Get-SwiftUIAuditProperty $plan 'baselineManifestSha256') -cne $BaselineManifestSha256) {
        throw 'The supplied baseline differs from the literal reviewed template binding.'
    }

    $rootNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($root in $plan.roots) {
        if (-not $rootNames.Add($root.rootId) -or @($Layout.roots.Keys) -cnotcontains $root.rootId -or
            $root.logicalPath -cne $Layout.roots[$root.rootId]) {
            throw 'The captured layout differs from the fixed reviewed root paths.'
        }
        if ($root.rootId -ceq 'platform-developer-frameworks') {
            if ($root.selection -cne 'not-selected' -or $null -ne $root.expectedPhysicalPath -or $null -ne $root.allowedPhysicalBoundary) {
                throw 'The template must start with the optional developer-framework root unselected.'
            }
            $root.selection = $DeveloperFrameworksSelection
            if ($DeveloperFrameworksSelection -ceq 'selected-optional') {
                # This is a conditional expectation from the reviewed literal
                # template, never a runtime realpath or observed authorization.
                $root.expectedPhysicalPath = $root.logicalPath
                $root.allowedPhysicalBoundary = $root.logicalPath
                $parent = $root.logicalPath.Substring(0, $root.logicalPath.LastIndexOf('/'))
                $plan.lookupAuthorizations = @($plan.lookupAuthorizations) + [pscustomobject][ordered]@{
                    lookupId = 'optional-platform-library-metadata'; kind = 'ancestor-metadata'
                    exactPath = $parent; purpose = 'Resolve the explicitly selected optional root; no parent listing or absence inference is authorized.'
                    mayEnumerateChildren = $false; mayTraverseDescendants = $false
                }
            }
        } elseif ($root.selection -cne 'required' -or $root.expectedPhysicalPath -cne $root.logicalPath -or
            $root.allowedPhysicalBoundary -cne $root.logicalPath) {
            throw 'Required roots must retain their reviewed literal physical expectations and exact boundaries.'
        }
    }
    if ($rootNames.Count -ne 3) { throw 'The fixed template must retain all three root selections.' }

    $anchorNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($anchor in $plan.identityAnchors) {
        if (-not $anchorNames.Add($anchor.anchorId) -or -not $Layout.anchors.ContainsKey($anchor.anchorId)) {
            throw 'The template has an unknown or duplicate captured identity anchor.'
        }
        $expected = $Layout.anchors[$anchor.anchorId]
        if ($anchor.logicalPath -cne $expected.path -or $anchor.expectedSha256 -cne 'RUNTIME_ANCHOR_SHA256') {
            throw 'An anchor path or runtime hash marker differs from the reviewed template.'
        }
        Assert-SwiftUIAuditSha256 $expected.sha256 'captured anchor hash'
        $anchor.expectedSha256 = $expected.sha256
    }
    if ($anchorNames.Count -ne $Layout.anchors.Count) { throw 'The template must name every captured identity anchor; no new path is inferred.' }
    foreach ($lookup in $plan.lookupAuthorizations) {
        if ($lookup.kind -ceq 'nonrecursive-parent-listing' -or $lookup.mayEnumerateChildren -or $lookup.mayTraverseDescendants) {
            throw 'This workflow template authorizes metadata lookups only; missing roots remain incomplete.'
        }
    }
    if ((ConvertTo-Json -InputObject $plan -Depth 100 -WarningAction Stop).Contains('RUNTIME_')) {
        throw 'An unresolved runtime marker remains in the root plan.'
    }
    return $plan
}
