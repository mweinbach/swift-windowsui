import CUIAInterop
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Headless snapshot and host-wiring tests; these do not qualify native COM delivery.
@MainActor
final class UIAWindowRootNameTests: XCTestCase {
    func testHeadlessHostUsesCreatedWindowCaptionWithoutRenamingAuthoredContent() async throws {
        let caption = "GPU Workbench \u{2014} Caf\u{00E9} \u{1F30D}"
        let window = Win32Window(title: caption, clientSize: IntSize(width: 320, height: 200))
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Configured title before platform creation", size: IntSize(width: 320, height: 200),
                clearColor: .black, content: [AnyView(Text("Status").accessibilityLabel("Authored status"))]),
            platformWindow: window)
        defer { host.windowWillClose(window) }
        XCTAssertNil(window.nativeHandle)
        let bridge = try XCTUnwrap(window.accessibilityProvider as? UIAProviderBridge)

        XCTAssertEqual(
            try reply(.stringProperty(element: 0, property: Int32(SWU_UIA_STRING_NAME)), from: bridge),
            .string(caption))
        XCTAssertEqual(try reply(.controlType(element: 0), from: bridge), .integer(Int32(SWU_UIA_CONTROL_TYPE_PANE)))
        guard
            case .element(let childID) = try reply(
                .navigate(element: 0, direction: Int32(SWU_UIA_NAV_FIRST_CHILD)), from: bridge)
        else { return XCTFail("The host root must retain its authored child") }
        XCTAssertNotEqual(childID, 0)
        XCTAssertNotEqual(childID, UInt64.max)
        XCTAssertEqual(
            try reply(.stringProperty(element: childID, property: Int32(SWU_UIA_STRING_NAME)), from: bridge),
            .string("Authored status"))
        XCTAssertEqual(window.title, caption)
        XCTAssertNil(window.nativeHandle)
    }

    func testFallbackChangesOnlyUnnamedPhysicalRootSnapshot() async throws {
        let root = makeRoot()
        let child = ViewNode(frame: Rect(x: 10, y: 20, width: 90, height: 30))
        child.resolvedFrame = child.frame
        child.text = "Child text"
        child.accessibilityLabel = "Authored child"
        child.accessibilityIdentifier = "child-id"
        child.accessibilityTraits = .isButton
        child.isFocusable = true
        root.addChild(child)
        let runtime = RetainedViewRuntime(root: root)
        var callbacks = 0
        runtime.clock = {
            callbacks += 1
            return 0
        }
        root.onLayout = { _ in callbacks += 1 }
        child.onActivate = { callbacks += 1 }
        let plain = RuntimeUIAElementTreeSource(runtime: runtime)
        let named = RuntimeUIAElementTreeSource(runtime: runtime, windowName: "Window caption")
        let before = plain.uiaElementSnapshots()

        let after = named.uiaElementSnapshots()

        XCTAssertEqual(before.count, 2)
        XCTAssertEqual(after.count, before.count)
        for (old, new) in zip(before, after) {
            assertSameMetadata(old, new)
            XCTAssertEqual(new.name, old.parentID == nil ? "Window caption" : old.name)
        }
        XCTAssertEqual(after.first?.id, 0)
        XCTAssertNil(after.first?.parentID)
        XCTAssertEqual(after.first?.controlType, Int32(SWU_UIA_CONTROL_TYPE_PANE))
        XCTAssertEqual(after.last?.name, "Authored child")
        XCTAssertNil(root.accessibilityLabel)
        XCTAssertNil(root.text)
        XCTAssertNil(root.accessibilityChildBehavior)
        XCTAssertEqual(child.accessibilityLabel, "Authored child")
        XCTAssertEqual(child.text, "Child text")
        XCTAssertEqual(named.uiaElementSnapshots().map(\.id), after.map(\.id))
        XCTAssertEqual(callbacks, 0)
    }

    func testUnconfiguredSourcePreservesEmptyRootName() async throws {
        let runtime = RetainedViewRuntime(root: makeRoot())
        let source = RuntimeUIAElementTreeSource(runtime: runtime)

        let root = try XCTUnwrap(source.uiaElementSnapshots().first)

        XCTAssertEqual(root.id, 0)
        XCTAssertNil(root.parentID)
        XCTAssertEqual(root.name, "")
        XCTAssertEqual(root.controlType, Int32(SWU_UIA_CONTROL_TYPE_PANE))
    }

    func testExplicitLabelAndTextIncludingEmptyAlwaysWin() async throws {
        let cases: [(label: String?, text: String?, expected: String)] = [
            ("Authored label", "Authored text", "Authored label"),
            ("", "Authored text", ""),
            ("", nil, ""),
            (nil, "Authored text", "Authored text"),
            (nil, "", ""),
        ]
        for item in cases {
            let root = makeRoot()
            root.accessibilityLabel = item.label
            root.text = item.text
            let runtime = RetainedViewRuntime(root: root)
            let source = RuntimeUIAElementTreeSource(runtime: runtime, windowName: "Window caption")

            let snapshot = try XCTUnwrap(source.uiaElementSnapshots().first)

            XCTAssertEqual(snapshot.name, item.expected)
            XCTAssertEqual(root.accessibilityLabel, item.label)
            XCTAssertEqual(root.text, item.text)
        }
    }

    func testExplicitChildBehaviorsNeverTakeWindowName() async throws {
        let behaviors: [RetainedAccessibilityChildBehavior] = [.ignore, .combine, .contain]
        for behavior in behaviors {
            for hasChild in [false, true] {
                let root = makeRoot()
                root.accessibilityChildBehavior = behavior
                if hasChild {
                    let child = ViewNode()
                    child.text = "Combined child"
                    root.addChild(child)
                }
                let runtime = RetainedViewRuntime(root: root)
                let source = RuntimeUIAElementTreeSource(runtime: runtime, windowName: "Window caption")

                let snapshot = try XCTUnwrap(source.uiaElementSnapshots().first)

                XCTAssertEqual(snapshot.name, behavior == .combine && hasChild ? "Combined child" : "")
                XCTAssertEqual(root.accessibilityChildBehavior, behavior)
            }
        }
    }

    func testSelectedRootNeverTakesWindowName() async throws {
        for label in [Optional<String>.none, "", "Selected label"] {
            let selected = ViewNode()
            selected.accessibilityLabel = label
            let root = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected)
            let runtime = RetainedViewRuntime(root: root)
            let source = RuntimeUIAElementTreeSource(runtime: runtime, windowName: "Window caption")

            let snapshot = try XCTUnwrap(source.uiaElementSnapshots().first)

            XCTAssertEqual(snapshot.id, 0)
            XCTAssertNil(snapshot.parentID)
            XCTAssertEqual(snapshot.name, label ?? "")
            XCTAssertEqual(selected.accessibilityLabel, label)
            XCTAssertNil(root.accessibilityLabel)
        }
    }

    func testRootNameIsCapturedBeforeMapperRemovesExplicitEmptyLabel() async throws {
        let root = makeRoot()
        root.accessibilityLabel = ""
        let runtime = RetainedViewRuntime(root: root)
        var mappingCalls = 0
        let source = RuntimeUIAElementTreeSource(runtime: runtime, windowName: "Window caption") { bounds in
            mappingCalls += 1
            if mappingCalls == 1 { root.accessibilityLabel = nil }
            return bounds
        }

        let first = try XCTUnwrap(source.uiaElementSnapshots().first)

        XCTAssertEqual(first.name, "")
        XCTAssertNil(root.accessibilityLabel)
        XCTAssertEqual(mappingCalls, 2)
        let second = try XCTUnwrap(source.uiaElementSnapshots().first)
        XCTAssertEqual(second.name, "Window caption")
        XCTAssertEqual(mappingCalls, 4)
    }

    func testWindowNameDoesNotRetainRuntimeOrSynthesizeReleasedRoot() async throws {
        var runtime: RetainedViewRuntime? = RetainedViewRuntime(root: makeRoot())
        runtime?.root.addChild(ViewNode())
        weak var releasedRuntime = runtime
        weak var releasedRoot = runtime?.root
        weak var releasedChild = runtime?.root.children.first
        let source = RuntimeUIAElementTreeSource(runtime: try XCTUnwrap(runtime), windowName: "Window caption")
        let bridge = UIAProviderBridge(source: source)
        XCTAssertEqual(source.uiaElementSnapshots().first?.name, "Window caption")

        runtime = nil

        withExtendedLifetime((source, bridge)) {
            XCTAssertNil(releasedRuntime)
            XCTAssertNil(releasedRoot)
            XCTAssertNil(releasedChild)
            XCTAssertTrue(source.uiaElementSnapshots().isEmpty)
            XCTAssertNil(source.uiaTextSnapshot(elementID: 0))
            XCTAssertNil(source.uiaTextDocument(elementID: 0))
        }
        XCTAssertEqual(
            try reply(.stringProperty(element: 0, property: Int32(SWU_UIA_STRING_NAME)), from: bridge),
            .string(nil))
    }

    func testHiddenRootDoesNotReceiveSyntheticSnapshot() async throws {
        let root = makeRoot()
        let runtime = RetainedViewRuntime(root: root)
        let source = RuntimeUIAElementTreeSource(runtime: runtime, windowName: "Window caption")
        root.isHidden = true
        XCTAssertTrue(source.uiaElementSnapshots().isEmpty)
        root.isHidden = false
        root.isAccessibilityHidden = true
        XCTAssertTrue(source.uiaElementSnapshots().isEmpty)
        root.isAccessibilityHidden = false
        XCTAssertEqual(source.uiaElementSnapshots().first?.name, "Window caption")
    }

    func testWindowNameDoesNotAuthorizeTextContentDocumentsOrPatterns() async throws {
        let root = makeRoot()
        let runtime = RetainedViewRuntime(root: root)
        let source = RuntimeUIAElementTreeSource(runtime: runtime, windowName: "Window caption")
        let bridge = UIAProviderBridge(source: source)

        XCTAssertEqual(
            try reply(.stringProperty(element: 0, property: Int32(SWU_UIA_STRING_NAME)), from: bridge),
            .string("Window caption"))
        XCTAssertEqual(try reply(.controlType(element: 0), from: bridge), .integer(Int32(SWU_UIA_CONTROL_TYPE_PANE)))
        XCTAssertNil(source.uiaTextSnapshot(elementID: 0))
        XCTAssertNil(source.uiaTextDocument(elementID: 0))
        XCTAssertEqual(try reply(.textContent(element: 0), from: bridge), .string(nil))
        XCTAssertEqual(try reply(.textDocument(element: 0), from: bridge), .textDocument(nil))
        let patterns: [Int32] = [
            Int32(SWU_UIA_PATTERN_VALUE), Int32(SWU_UIA_PATTERN_TOGGLE), Int32(SWU_UIA_PATTERN_SELECTION),
            Int32(SWU_UIA_PATTERN_SELECTION_ITEM), Int32(SWU_UIA_PATTERN_VIRTUALIZED_ITEM),
            Int32(SWU_UIA_PATTERN_ITEM_CONTAINER), 10014, 10024, 10029, 10032,
        ]
        for pattern in patterns {
            XCTAssertEqual(try reply(.supportsPattern(element: 0, pattern: pattern), from: bridge), .integer(0))
        }
        XCTAssertNil(root.accessibilityLabel)
        XCTAssertNil(root.text)
    }

    func testConfiguredNamesStayWithTheirOwnSources() async throws {
        let firstRuntime = RetainedViewRuntime(root: makeRoot())
        let secondRuntime = RetainedViewRuntime(root: makeRoot())
        let first = RuntimeUIAElementTreeSource(runtime: firstRuntime, windowName: "Dashboard")
        let second = RuntimeUIAElementTreeSource(runtime: secondRuntime, windowName: "Settings")

        for _ in 0..<3 {
            XCTAssertEqual(first.uiaElementSnapshots().first?.name, "Dashboard")
            XCTAssertEqual(second.uiaElementSnapshots().first?.name, "Settings")
        }
        XCTAssertNil(firstRuntime.root.accessibilityLabel)
        XCTAssertNil(secondRuntime.root.accessibilityLabel)
    }

    private func makeRoot() -> ViewNode {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 200))
        root.resolvedFrame = root.frame
        return root
    }

    private func reply(_ request: UIAProviderRequest, from bridge: UIAProviderBridge) throws -> UIAProviderReply {
        let geometry = NativeWindowGeometry(
            revision: 1, nativeSequence: 1, clientSize: IntSize(width: 320, height: 200),
            clientScreenOrigin: .zero, scaleFactor: 1, effectiveScaleFactor: 1,
            monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true)
        return try bridge.replyForNativeRequest(request, geometry: geometry, isAvailable: { true })
    }

    private func assertSameMetadata(
        _ before: UIAElementSnapshot, _ after: UIAElementSnapshot,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(after.id, before.id, file: file, line: line)
        XCTAssertEqual(after.parentID, before.parentID, file: file, line: line)
        XCTAssertEqual(after.value, before.value, file: file, line: line)
        XCTAssertEqual(after.helpText, before.helpText, file: file, line: line)
        XCTAssertEqual(after.automationID, before.automationID, file: file, line: line)
        XCTAssertEqual(after.className, before.className, file: file, line: line)
        XCTAssertEqual(after.controlType, before.controlType, file: file, line: line)
        XCTAssertEqual(after.bounds, before.bounds, file: file, line: line)
        XCTAssertEqual(after.isEnabled, before.isEnabled, file: file, line: line)
        XCTAssertEqual(after.hasKeyboardFocus, before.hasKeyboardFocus, file: file, line: line)
        XCTAssertEqual(after.isKeyboardFocusable, before.isKeyboardFocusable, file: file, line: line)
        XCTAssertEqual(after.isOffscreen, before.isOffscreen, file: file, line: line)
        XCTAssertEqual(after.hasDefaultAction, before.hasDefaultAction, file: file, line: line)
        XCTAssertEqual(after.isPassword, before.isPassword, file: file, line: line)
        XCTAssertEqual(after.supportsValue, before.supportsValue, file: file, line: line)
        XCTAssertEqual(after.isReadOnly, before.isReadOnly, file: file, line: line)
        XCTAssertEqual(after.toggleState?.rawValue, before.toggleState?.rawValue, file: file, line: line)
        XCTAssertEqual(after.isSelected, before.isSelected, file: file, line: line)
        XCTAssertEqual(after.supportsSelection, before.supportsSelection, file: file, line: line)
        XCTAssertEqual(after.isVirtualizedPlaceholder, before.isVirtualizedPlaceholder, file: file, line: line)
        XCTAssertEqual(after.supportsItemContainer, before.supportsItemContainer, file: file, line: line)
    }
}
