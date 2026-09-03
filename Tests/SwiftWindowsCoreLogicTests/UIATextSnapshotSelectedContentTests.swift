import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Direct optional-source checks for installed physical selection wrappers.
/// These fixtures use the retained structural role, not ViewThatFits fitting
/// policy, owned candidate receipts, a native provider, or a release callback.
@MainActor
final class UIATextSnapshotSelectedContentTests: XCTestCase {
    func testNonzeroSelectedTextKeepsDisabledOffscreenAndPrivacyPoliciesWithoutQueries() async throws {
        let content = "Stored e\u{301} 👩‍👩‍👧‍👦 אבג\r\n\0document"
        let fixture = SelectedSnapshotReadFixture(content)
        fixture.outer.accessibilityRespondsToUserInteraction = false
        fixture.text.frame = Rect(x: 10, y: 1000, width: 180, height: 20)
        fixture.text.resolvedFrame = fixture.text.frame
        fixture.text.accessibilityLabel = "Different spoken label"
        fixture.text.accessibilityValue = "Different accessible value"
        fixture.outer.text = "Wrapper storage must not replace selected text"
        let path = try XCTUnwrap(fixture.outer.captureSelectedContentPath(in: fixture.runtime))
        XCTAssertTrue(path.isInstalled(in: fixture.runtime))
        XCTAssertTrue(path.selectedNode === fixture.text)
        let metadata = try fixture.textMetadata()
        XCTAssertNotEqual(metadata.id, UIAProviderBridge.rootElementID)
        XCTAssertEqual(metadata.name, "Different spoken label")
        XCTAssertEqual(metadata.value, "Different accessible value")
        XCTAssertFalse(metadata.isEnabled)
        XCTAssertEqual(metadata.isOffscreen, true)
        XCTAssertFalse(metadata.isVirtualizedPlaceholder)
        XCTAssertFalse(metadata.supportsValue)
        fixture.armReadEffects()

        let snapshot = try XCTUnwrap(fixture.source.uiaTextSnapshot(elementID: metadata.id))
        XCTAssertEqual(Array(snapshot.text.utf16), Array(content.utf16))
        XCTAssertTrue(path.isCurrent)
        fixture.assertQuiet()

        let denials: [(String, (ViewNode) -> Void)] = [
            ("privacy", { $0.isPrivacySensitive = true }),
            ("redaction", { $0.redactionReasons = .placeholder }),
            ("secure ancestry", { $0.accessibilityTraits.insert(.isSecureTextInput) }),
        ]
        for (name, deny) in denials {
            let protected = SelectedSnapshotReadFixture(content)
            let knownID = try protected.textMetadata().id
            XCTAssertNotNil(protected.source.uiaTextSnapshot(elementID: knownID), name)
            deny(protected.outer)
            protected.armReadEffects()
            XCTAssertNil(protected.source.uiaTextSnapshot(elementID: knownID), name)
            protected.assertQuiet()
        }
        // Disabled metadata above is authored on the retained wrapper. This
        // does not qualify a public environment-to-accessibility mapping.
    }

    func testMalformedSelectionAndDetachedOriginalCannotBorrowReplacementText() async throws {
        let fixture = SelectedSnapshotReadFixture("Original physical text")
        let knownID = try fixture.textMetadata().id
        let originalPath = try XCTUnwrap(fixture.outer.captureSelectedContentPath(in: fixture.runtime))
        let originalTarget = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.text))
        XCTAssertNotEqual(knownID, UIAProviderBridge.rootElementID)
        XCTAssertNotNil(fixture.source.uiaTextSnapshot(elementID: knownID))

        let extra = ViewNode(text: "Unselected sibling must not lend a document")
        fixture.inner.addChild(extra)
        XCTAssertEqual(fixture.inner.children.count, 2)
        XCTAssertTrue(fixture.text.parent === fixture.inner)
        XCTAssertFalse(originalPath.isCurrent)
        XCTAssertNil(fixture.outer.captureSelectedContentPath(in: fixture.runtime))
        fixture.armReadEffects()
        // The physical attachment is still eligible. It is the malformed
        // selected projection that must refuse this known ID without repair.
        XCTAssertTrue(fixture.runtime.isAccessibilityTextReadTargetCurrent(originalTarget))
        XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: knownID))
        fixture.assertQuiet()

        let replacement = ViewNode(text: "Replacement must not answer the old ID")
        replacement.accessibilityIdentifier = fixture.text.accessibilityIdentifier
        fixture.inner.setChildren([replacement])
        XCTAssertEqual(fixture.inner.children.count, 1)
        XCTAssertTrue(replacement.parent === fixture.inner)
        XCTAssertNil(fixture.text.parent)
        XCTAssertNil(fixture.text.retainedLazyListRuntime)
        XCTAssertFalse(originalPath.isCurrent)
        let replacementPath = try XCTUnwrap(fixture.outer.captureSelectedContentPath(in: fixture.runtime))
        XCTAssertTrue(replacementPath.selectedNode === replacement)
        fixture.armReadEffects()
        XCTAssertFalse(fixture.runtime.isAccessibilityTextReadTargetCurrent(originalTarget))
        XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: knownID))
        fixture.assertQuiet()
        // No metadata enumeration follows either mutation. These are real
        // malformed selection and detached attachment checks, not an owned
        // candidate catalog rejection or ABA inside the capture-release frame.
    }

    func testSelectedRootAliasIsRefusedEvenWhenItsPhysicalWrapperStoresText() async throws {
        let content = "Selected root document"
        let fixture = SelectedSnapshotReadFixture(content, rootIsBoundary: true)
        let metadata = try fixture.textMetadata()
        XCTAssertEqual(metadata.id, UIAProviderBridge.rootElementID)
        XCTAssertEqual(metadata.name, content)
        let path = try XCTUnwrap(fixture.outer.captureSelectedContentPath(in: fixture.runtime))
        XCTAssertTrue(path.isInstalled(in: fixture.runtime))
        XCTAssertTrue(path.selectedNode === fixture.text)
        fixture.outer.text = "Physical wrapper storage is not the selected document"
        let physicalRoot = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.outer))
        fixture.armReadEffects()
        XCTAssertTrue(fixture.runtime.isAccessibilityTextReadTargetCurrent(physicalRoot))
        XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: UIAProviderBridge.rootElementID))
        XCTAssertTrue(path.isCurrent)
        fixture.assertQuiet()

        // ID zero still works when the runtime root itself is ordinary text.
        let ordinary = ViewNode(text: content)
        let ordinaryRuntime = RetainedViewRuntime(root: ordinary)
        let ordinarySource = RuntimeUIAElementTreeSource(runtime: ordinaryRuntime)
        XCTAssertNil(ordinary.selectedContentRole)
        XCTAssertEqual(
            ordinarySource.uiaTextSnapshot(elementID: UIAProviderBridge.rootElementID)?.text, content)
        withExtendedLifetime(ordinaryRuntime) {}
    }
}

@MainActor
private final class SelectedSnapshotReadEffects {
    var maps = 0
    var layouts = 0
    var actions = 0
    var focus = 0
}

@MainActor
private final class SelectedSnapshotReadFixture {
    let runtime: RetainedViewRuntime
    let outer: ViewNode
    let inner: ViewNode
    let text: ViewNode
    let source: RuntimeUIAElementTreeSource
    private let effects: SelectedSnapshotReadEffects

    init(_ content: String, rootIsBoundary: Bool = false) {
        let selected = ViewNode(frame: Rect(x: 10, y: 10, width: 180, height: 20), text: content)
        selected.resolvedFrame = selected.frame
        selected.accessibilityIdentifier = "selected-physical-text"
        let inner = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected)
        let outer = ViewNode.selectedContentBoundary(role: .viewThatFits, child: inner)
        let root: ViewNode
        if rootIsBoundary {
            root = outer
        } else {
            root = ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 200))
            root.resolvedFrame = root.frame
            root.addChild(outer)
        }
        let runtime = RetainedViewRuntime(root: root)
        let effects = SelectedSnapshotReadEffects()
        let source = RuntimeUIAElementTreeSource(
            runtime: runtime,
            screenBoundsMapper: {
                effects.maps += 1
                return $0
            })
        self.runtime = runtime
        self.outer = outer
        self.inner = inner
        self.text = selected
        self.source = source
        self.effects = effects
    }

    func textMetadata() throws -> UIAElementSnapshot {
        try XCTUnwrap(source.uiaElementSnapshots().first { $0.automationID == "selected-physical-text" })
    }

    func armReadEffects() {
        let effects = effects
        for node in [runtime.root, outer, inner, text] {
            node.onLayout = { _ in effects.layouts += 1 }
        }
        text.isFocusable = true
        text.onActivate = { effects.actions += 1 }
        text.onFocusEnter = { effects.focus += 1 }
        effects.maps = 0
        effects.layouts = 0
        effects.actions = 0
        effects.focus = 0
    }

    func assertQuiet(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(effects.maps, 0, file: file, line: line)
        XCTAssertEqual(effects.layouts, 0, file: file, line: line)
        XCTAssertEqual(effects.actions, 0, file: file, line: line)
        XCTAssertEqual(effects.focus, 0, file: file, line: line)
        XCTAssertNil(runtime.focusedNode, file: file, line: line)
    }
}
