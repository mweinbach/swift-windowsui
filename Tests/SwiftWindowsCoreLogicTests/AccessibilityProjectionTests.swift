import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsUI

// MARK: - Helpers (main-actor, matching ViewNode isolation)

@MainActor
private func makeRoot(width: Double = 800, height: Double = 600) -> ViewNode {
    let root = ViewNode(frame: Rect(x: 0, y: 0, width: width, height: height))
    root.resolvedFrame = root.frame
    return root
}

@MainActor
private func makeChild(
    of parent: ViewNode,
    frame: Rect = Rect(x: 0, y: 0, width: 100, height: 40)
) -> ViewNode {
    let child = ViewNode(frame: frame)
    child.resolvedFrame = frame
    parent.addChild(child)
    return child
}

final class AccessibilityProjectionTests: XCTestCase {
    // MARK: - Trait → control type mapping table

    func testControlTypeMappingTable() async {
        await MainActor.run {
            let cases: [(RetainedAccessibilityTraits, AccessibilityControlType)] = [
                (.isButton, .button),
                (.isLink, .hyperlink),
                (.isSearchField, .edit),  // UIA has no Search control type
                (.isKeyboardKey, .button),  // UIA has no KeyboardKey control type
                (.isHeader, .header),
                (.isImage, .image),
                (.isStaticText, .text),
                (.isSummaryElement, .group),  // weak mapping, documented
            ]
            for (traits, expected) in cases {
                let node = ViewNode()
                node.accessibilityTraits = traits
                XCTAssertEqual(
                    AccessibilityProjection.resolveControlType(for: node), expected,
                    "traits \(traits) should map to \(expected)")
            }
        }
    }

    func testControlTypePrecedenceFirstMatchWins() async {
        await MainActor.run {
            let node = ViewNode()
            node.accessibilityTraits = [.isButton, .isHeader, .isStaticText]
            XCTAssertEqual(AccessibilityProjection.resolveControlType(for: node), .button)
        }
    }

    func testControlTypeFallbacks() async {
        await MainActor.run {
            // Bitmap text with no traits projects as text.
            let textNode = ViewNode(text: "HELLO")
            XCTAssertEqual(AccessibilityProjection.resolveControlType(for: textNode), .text)

            // Slider behavior preference projects as slider.
            let sliderNode = ViewNode()
            sliderNode.accessibilityPrefersSliderBehavior = true
            XCTAssertEqual(AccessibilityProjection.resolveControlType(for: sliderNode), .slider)

            // isAccessibilityImage flag projects as image even without traits.
            let imageNode = ViewNode()
            imageNode.isAccessibilityImage = true
            XCTAssertEqual(AccessibilityProjection.resolveControlType(for: imageNode), .image)

            // Labeled content with no type signal falls back to group.
            let labeledNode = ViewNode()
            labeledNode.accessibilityLabel = "Status"
            XCTAssertEqual(AccessibilityProjection.resolveControlType(for: labeledNode), .group)
        }
    }

    func testBehavioralTraitsHaveNoControlTypeMapping() async {
        await MainActor.run {
            // These traits stay on the projection verbatim but do not change the
            // control type (documented on AccessibilityProjection.resolveControlType).
            let behavioral: [RetainedAccessibilityTraits] = [
                .updatesFrequently, .startsMediaSession, .playsSound,
                .allowsDirectInteraction, .causesPageTurn, .isModal,
            ]
            for traits in behavioral {
                let node = ViewNode()
                node.accessibilityTraits = traits
                XCTAssertEqual(
                    AccessibilityProjection.resolveControlType(for: node), .group,
                    "\(traits) must not influence the control type")
            }
        }
    }

    // MARK: - Hidden nodes

    func testAccessibilityHiddenOmitsNodeAndSubtree() async {
        await MainActor.run {
            let root = makeRoot()
            let visible = makeChild(of: root)
            visible.accessibilityLabel = "Visible"
            let hidden = makeChild(of: root)
            hidden.accessibilityLabel = "Hidden"
            hidden.isAccessibilityHidden = true
            let hiddenChild = makeChild(of: hidden)
            hiddenChild.accessibilityLabel = "Hidden Child"

            let projection = AccessibilityProjection.project(root: root)
            let names = projection?.flattened().map(\.name) ?? []
            XCTAssertEqual(names.filter { !$0.isEmpty }, ["Visible"])
        }
    }

    func testVisuallyHiddenOmitsNodeAndSubtree() async {
        await MainActor.run {
            let root = makeRoot()
            let hidden = makeChild(of: root)
            hidden.accessibilityLabel = "Hidden"
            hidden.isHidden = true
            let child = makeChild(of: hidden)
            child.accessibilityLabel = "Child"

            let projection = AccessibilityProjection.project(root: root)
            XCTAssertEqual(projection?.flattened().count, 1)  // root only
        }
    }

    func testHiddenRootProjectsNil() async {
        await MainActor.run {
            let root = makeRoot()
            root.isAccessibilityHidden = true
            XCTAssertNil(AccessibilityProjection.project(root: root))
        }
    }

    // MARK: - Child behavior

    func testCombineMergesDescendantTextIntoSingleElement() async {
        await MainActor.run {
            let root = makeRoot()
            let container = makeChild(of: root)
            container.accessibilityChildBehavior = .combine
            let first = makeChild(of: container)
            first.text = "TOTAL"
            let second = makeChild(of: container)
            second.accessibilityLabel = "42 items"

            let projection = AccessibilityProjection.project(root: root)
            let combined = projection?.children.first
            XCTAssertEqual(combined?.name, "TOTAL 42 items")
            XCTAssertEqual(combined?.children.count ?? -1, 0)
            // No traits and no text of its own → group fallback (documented).
            XCTAssertEqual(combined?.controlType, .group)
        }
    }

    func testCombinePrefersOwnLabelOverDescendantText() async {
        await MainActor.run {
            let root = makeRoot()
            let container = makeChild(of: root)
            container.accessibilityChildBehavior = .combine
            container.accessibilityLabel = "Summary"
            let child = makeChild(of: container)
            child.text = "IGNORED"

            let projection = AccessibilityProjection.project(root: root)
            XCTAssertEqual(projection?.children.first?.name, "Summary")
        }
    }

    func testIgnoreDropsChildrenButKeepsElement() async {
        await MainActor.run {
            let root = makeRoot()
            let container = makeChild(of: root)
            container.accessibilityLabel = "Badge"
            container.accessibilityChildBehavior = .ignore
            let child = makeChild(of: container)
            child.accessibilityLabel = "Dropped"

            let projection = AccessibilityProjection.project(root: root)
            let element = projection?.children.first
            XCTAssertEqual(element?.name, "Badge")
            XCTAssertEqual(element?.children.count ?? -1, 0)
        }
    }

    func testTransparentNodeSplicesAccessibleDescendants() async {
        await MainActor.run {
            let root = makeRoot()
            // Plain container: no label/traits/actions/text → not an element.
            let container = makeChild(of: root)
            let inner = makeChild(of: container, frame: Rect(x: 10, y: 20, width: 50, height: 20))
            inner.accessibilityLabel = "Inner"

            let projection = AccessibilityProjection.project(root: root)
            XCTAssertEqual(projection?.children.count, 1)
            XCTAssertEqual(projection?.children.first?.name, "Inner")
        }
    }

    // MARK: - Sort priority

    func testSortPriorityOrdersSiblingsDescendingStableTies() async {
        await MainActor.run {
            let root = makeRoot()
            let low = makeChild(of: root)
            low.accessibilityLabel = "Low"
            low.accessibilitySortPriority = 0
            let high = makeChild(of: root)
            high.accessibilityLabel = "High"
            high.accessibilitySortPriority = 10
            let tieA = makeChild(of: root)
            tieA.accessibilityLabel = "TieA"
            tieA.accessibilitySortPriority = 5
            let tieB = makeChild(of: root)
            tieB.accessibilityLabel = "TieB"
            tieB.accessibilitySortPriority = 5

            let names = AccessibilityProjection.project(root: root)?.children.map(\.name)
            XCTAssertEqual(names, ["High", "TieA", "TieB", "Low"])
        }
    }

    // MARK: - Actions

    func testActionsProjectWithNamesAndInvokeThrough() async {
        await MainActor.run {
            let root = makeRoot()
            let button = makeChild(of: root)
            button.accessibilityTraits = .isButton
            var activated = 0
            var incremented = 0
            button.accessibilityActions = [
                RetainedAccessibilityAction(name: "Activate", kind: .default) { activated += 1 },
                RetainedAccessibilityAction(kind: .increment) { incremented += 1 },
            ]

            let element = AccessibilityProjection.project(root: root)?.children.first
            XCTAssertEqual(element?.actions.count, 2)
            XCTAssertEqual(element?.actions.first?.name, "Activate")
            XCTAssertEqual(element?.actions.first?.isDefault, true)
            // Unnamed action gets a fallback name derived from its kind.
            XCTAssertEqual(element?.actions.last?.name, "Increment")
            XCTAssertEqual(element?.actions.last?.isDefault, false)

            element?.actions.last?.invoke()
            XCTAssertEqual(incremented, 1)

            XCTAssertEqual(element?.invokeDefaultAction(), true)
            XCTAssertEqual(activated, 1)
        }
    }

    func testInvokeDefaultActionFallsBackToFirstAction() async {
        await MainActor.run {
            let root = makeRoot()
            let node = makeChild(of: root)
            node.accessibilityLabel = "Custom"
            var called = 0
            node.accessibilityActions = [
                RetainedAccessibilityAction(name: "Custom Action") { called += 1 }
            ]

            let element = AccessibilityProjection.project(root: root)?.children.first
            XCTAssertEqual(element?.invokeDefaultAction(), true)
            XCTAssertEqual(called, 1)
        }
    }

    func testElementWithoutActionsDoesNotInvoke() async {
        await MainActor.run {
            let root = makeRoot()
            let node = makeChild(of: root)
            node.accessibilityLabel = "Plain"
            let element = AccessibilityProjection.project(root: root)?.children.first
            XCTAssertEqual(element?.invokeDefaultAction(), false)
        }
    }

    // MARK: - Focus / selection / enabled state

    func testFocusAndSelectionAndEnabledStatesProject() async {
        await MainActor.run {
            let root = makeRoot()
            let focused = makeChild(of: root)
            focused.accessibilityLabel = "Focused"
            focused.isFocused = true
            let selected = makeChild(of: root)
            selected.accessibilityLabel = "Selected"
            selected.accessibilityTraits = [.isButton, .isSelected]
            let disabled = makeChild(of: root)
            disabled.accessibilityLabel = "Disabled"
            disabled.accessibilityRespondsToUserInteraction = false

            let projection = AccessibilityProjection.project(root: root)
            let children = projection?.children ?? []
            XCTAssertEqual(children.first(where: { $0.name == "Focused" })?.isFocused, true)
            XCTAssertEqual(children.first(where: { $0.name == "Focused" })?.isSelected, false)
            XCTAssertEqual(children.first(where: { $0.name == "Selected" })?.isSelected, true)
            XCTAssertEqual(children.first(where: { $0.name == "Selected" })?.isFocused, false)
            XCTAssertEqual(children.first(where: { $0.name == "Disabled" })?.isEnabled, false)
            XCTAssertEqual(children.first(where: { $0.name == "Focused" })?.isEnabled, true)
            XCTAssertEqual(projection?.firstFocusedElement()?.name, "Focused")
        }
    }

    func testProjectFromRuntimeMatchesRootProjection() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: makeRoot())
            let child = makeChild(of: runtime.root)
            child.accessibilityLabel = "Runtime Child"
            let projection = AccessibilityProjection.project(runtime: runtime)
            XCTAssertEqual(projection?.children.map(\.name), ["Runtime Child"])
        }
    }

    // MARK: - Bounds

    func testBoundsAccumulateThroughAncestors() async {
        await MainActor.run {
            let root = makeRoot()
            let container = makeChild(of: root, frame: Rect(x: 10, y: 20, width: 300, height: 200))
            let leaf = makeChild(of: container, frame: Rect(x: 5, y: 7, width: 50, height: 30))
            leaf.accessibilityLabel = "Leaf"

            let element = AccessibilityProjection.project(root: root)?.children.first
            XCTAssertEqual(element?.bounds, Rect(x: 15, y: 27, width: 50, height: 30))
        }
    }

    func testBoundsReflectAncestorScrollOffset() async {
        await MainActor.run {
            let root = makeRoot()
            let scroller = makeChild(of: root, frame: Rect(x: 0, y: 0, width: 200, height: 200))
            scroller.scrollAxis = .vertical
            scroller.resolvedScrollOffset = 40
            let row = makeChild(of: scroller, frame: Rect(x: 0, y: 100, width: 200, height: 30))
            row.accessibilityLabel = "Row"

            let element = AccessibilityProjection.project(root: root)?.children.first
            XCTAssertEqual(element?.bounds, Rect(x: 0, y: 60, width: 200, height: 30))
        }
    }

    func testProjectionIsDerivedAtCallTime() async {
        await MainActor.run {
            // No caching: mutating retained state and re-projecting observes it.
            let root = makeRoot()
            let node = makeChild(of: root)
            node.accessibilityLabel = "Before"
            XCTAssertEqual(AccessibilityProjection.project(root: root)?.children.first?.name, "Before")
            node.accessibilityLabel = "After"
            XCTAssertEqual(AccessibilityProjection.project(root: root)?.children.first?.name, "After")
        }
    }
}
