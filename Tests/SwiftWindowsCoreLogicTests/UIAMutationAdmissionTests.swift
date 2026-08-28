import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Retained source admission only; these tests create no HWND or COM provider.
@MainActor
final class UIAMutationAdmissionTests: XCTestCase {
    func testEachOrdinaryMutationStillEntersItsOriginalHandler() async throws {
        for route in UIAAdmissionRoute.allCases {
            let fixture = try UIAAdmissionFixture(route: route)
            defer { fixture.retire() }
            let id = try fixture.id()

            XCTAssertTrue(route.call(fixture.source, id: id), "\(route)")
            XCTAssertGreaterThan(fixture.effects, 0, "\(route)")
            if route == .value {
                XCTAssertEqual(fixture.textWrites, 1)
                XCTAssertTrue(fixture.keyCodes.isEmpty)
                XCTAssertEqual(fixture.imeEvents, 0)
                XCTAssertEqual(fixture.target.accessibilityValue, "updated")
            }
        }
    }

    func testStoppedRuntimeRejectsEveryMutationWithoutQueryOrEffect() async throws {
        for route in UIAAdmissionRoute.allCases {
            let fixture = try UIAAdmissionFixture(route: route)
            defer { fixture.retire() }
            let id = try fixture.id()
            var queries = 0
            var clocks = 0
            fixture.runtime.scheduleAfterLayout(key: "must-not-resolve") { queries += 1 }
            fixture.runtime.clock = {
                clocks += 1
                return 0
            }
            fixture.runtime.stopRenderLifecycleCallbacks()

            XCTAssertFalse(route.call(fixture.source, id: id), "\(route)")
            XCTAssertEqual(fixture.effects, 0, "\(route)")
            XCTAssertTrue(fixture.keyCodes.isEmpty, "\(route)")
            XCTAssertEqual(fixture.imeEvents, 0, "\(route)")
            XCTAssertEqual(queries, 0, "\(route)")
            XCTAssertEqual(clocks, 0, "\(route)")
            XCTAssertFalse(fixture.source.uiaElementSnapshots().isEmpty, "Inspection remains available")
        }
    }

    func testActiveBuildRejectsEveryMutationAndDoesNotConsumeQueuedLayout() async throws {
        for route in UIAAdmissionRoute.allCases {
            let fixture = try UIAAdmissionFixture(route: route)
            defer { fixture.retire() }
            let id = try fixture.id()
            var queries = 0
            fixture.runtime.scheduleAfterLayout(key: "queued-before-build") { queries += 1 }
            XCTAssertNotNil(fixture.runtime.retainedBuildCoordinator.beginBuild())

            XCTAssertFalse(route.call(fixture.source, id: id), "\(route)")
            XCTAssertEqual(queries, 0, "\(route)")
            XCTAssertEqual(fixture.effects, 0, "\(route)")
            XCTAssertTrue(fixture.keyCodes.isEmpty, "\(route)")
            XCTAssertEqual(fixture.imeEvents, 0, "\(route)")
            fixture.runtime.retainedBuildCoordinator.finishBuild()
        }
    }

    func testAfterLayoutCallbackCannotEnterAnyMutation() async throws {
        for route in UIAAdmissionRoute.allCases {
            let fixture = try UIAAdmissionFixture(route: route)
            defer { fixture.retire() }
            let id = try fixture.id()
            var attempts: [Bool] = []
            fixture.runtime.scheduleAfterLayout(key: "attempt-during-layout-drain") { [weak fixture] in
                guard let fixture else { return }
                attempts.append(route.call(fixture.source, id: id))
            }

            XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.root))
            XCTAssertEqual(attempts, [false], "\(route)")
            XCTAssertEqual(fixture.effects, 0, "\(route)")
            XCTAssertTrue(fixture.keyCodes.isEmpty, "\(route)")
            XCTAssertEqual(fixture.imeEvents, 0, "\(route)")
        }
    }

    func testDifferentAdaptersShareAdmissionAndLegacyVoidFocusDoesNotEscapeIt() async throws {
        for route in UIAAdmissionRoute.allCases {
            let fixture = try UIAAdmissionFixture(route: route)
            defer { fixture.retire() }
            let otherSource = RuntimeUIAElementTreeSource(runtime: fixture.runtime)
            let otherID = try XCTUnwrap(otherSource.uiaElementSnapshots().first { $0.name == "Target" }?.id)
            let invoker = ViewNode(
                frame: Rect(x: 140, y: 10, width: 40, height: 30),
                accessibilityLabel: "Invoker", accessibilityTraits: .isButton)
            fixture.root.addChild(invoker)
            var attempts: [Bool] = []
            invoker.onActivate = { [weak fixture, weak otherSource] in
                guard let fixture, let otherSource else { return }
                attempts.append(route.call(otherSource, id: otherID))
                otherSource.uiaSetFocus(elementID: otherID)
                XCTAssertNil(fixture.runtime.focusedNode)
            }
            let invokerID = try XCTUnwrap(fixture.source.uiaElementSnapshots().first { $0.name == "Invoker" }?.id)

            XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: invokerID))
            XCTAssertEqual(attempts, [false], "\(route)")
            XCTAssertEqual(fixture.effects, 0, "\(route)")
            XCTAssertTrue(fixture.keyCodes.isEmpty, "\(route)")
            XCTAssertEqual(fixture.imeEvents, 0, "\(route)")
            XCTAssertTrue(route.call(otherSource, id: otherID), "Admission must reopen after the outer call")
        }
    }

    func testGuardRemainsClosedWhileRetiredActivationCaptureIsDestroyed() async throws {
        let fixture = try UIAAdmissionFixture(route: .value)
        defer { fixture.retire() }
        let valueID = try fixture.id()
        let invoker = ViewNode(
            frame: Rect(x: 140, y: 10, width: 40, height: 30),
            accessibilityLabel: "Invoker", accessibilityTraits: .isButton)
        fixture.root.addChild(invoker)
        let probe = UIAAdmissionReleaseProbe()
        installRetiringActivation(on: invoker, probe: probe) { [weak fixture] in
            guard let fixture else { return }
            probe.attempts.append(fixture.source.uiaSetValue(elementID: valueID, value: "nested"))
            fixture.source.uiaSetFocus(elementID: valueID)
        }
        let invokerID = try XCTUnwrap(fixture.source.uiaElementSnapshots().first { $0.name == "Invoker" }?.id)

        XCTAssertNotNil(probe.payload)
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: invokerID))
        XCTAssertNil(probe.payload, "The callback's last capture must be released before admission reopens")
        XCTAssertEqual(probe.releases, 1)
        XCTAssertEqual(probe.attempts, [false])
        XCTAssertEqual(fixture.effects, 0)
        XCTAssertTrue(fixture.keyCodes.isEmpty)
        XCTAssertEqual(fixture.imeEvents, 0)
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertTrue(fixture.source.uiaSetValue(elementID: valueID, value: "later"))
    }

    func testRuntimePinEndsAfterTheOriginalValueEffectAndDoesNotEscapeInSource() async throws {
        let fixture = try UIAAdmissionRuntimeLifetimeFixture()
        defer { fixture.retire() }

        XCTAssertNotNil(fixture.probe.runtime)
        XCTAssertTrue(fixture.source.uiaSetValue(elementID: fixture.id, value: "written"))
        XCTAssertEqual(fixture.probe.effects, 1)
        XCTAssertEqual(fixture.probe.text, "written")
        XCTAssertTrue(fixture.probe.keyCodes.isEmpty)
        XCTAssertEqual(fixture.probe.imeEvents, 0)
        XCTAssertEqual(fixture.probe.aliveDuringEffect, [true])
        XCTAssertNil(fixture.probe.runtime)
        XCTAssertTrue(fixture.source.uiaElementSnapshots().isEmpty)
        XCTAssertFalse(fixture.source.uiaSetValue(elementID: fixture.id, value: "unowned"))
        XCTAssertEqual(fixture.probe.effects, 1)
    }

    @inline(never)
    private func installRetiringActivation(
        on node: ViewNode, probe: UIAAdmissionReleaseProbe, onRelease: @escaping @MainActor () -> Void
    ) {
        let payload = UIAAdmissionReleasePayload {
            probe.releases += 1
            onRelease()
        }
        probe.payload = payload
        node.onActivate = { [weak node, payload] in
            node?.onActivate = nil
            withExtendedLifetime(payload) {}
        }
    }
}

private enum UIAAdmissionRoute: CaseIterable, Sendable {
    case invoke, toggle, select, addSelection, removeSelection, focus, value

    @MainActor
    var traits: RetainedAccessibilityTraits {
        switch self {
        case .invoke, .focus: return .isButton
        case .toggle: return .isToggle
        case .select, .addSelection: return .isSelectable
        case .removeSelection: return [.isSelectable, .isSelected]
        case .value: return .isTextInput
        }
    }

    @MainActor
    func call(_ source: RuntimeUIAElementTreeSource, id: UInt64) -> Bool {
        switch self {
        case .invoke: return source.uiaInvokeDefaultAction(elementID: id)
        case .toggle: return source.uiaToggle(elementID: id)
        case .select: return source.uiaSelect(elementID: id)
        case .addSelection: return source.uiaAddToSelection(elementID: id)
        case .removeSelection: return source.uiaRemoveFromSelection(elementID: id)
        case .focus: return source.uiaSetFocusResult(elementID: id)
        case .value: return source.uiaSetValue(elementID: id, value: "updated")
        }
    }
}

@MainActor
private func uiaAdmissionInstallTextLayout() {
    NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
        let glyphs = Array(text).enumerated().map { index, character in
            NativeTextGlyphLayout(
                character: character, origin: Point(x: Double(index) * 9, y: 0), advance: 9,
                glyphID: UInt32(index + 1), fontFamily: style.fontFamily, weight: style.weight,
                fontSize: style.nativeFontPixelSize, sourceIndex: index)
        }
        let size = Size(width: Double(max(text.count, 1)) * 9, height: max(style.nativeFontPixelSize, 1))
        return NativeTextLayoutResult(
            lines: [NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)],
            contentSize: size, measuredSize: size)
    }
}

@MainActor
private func uiaAdmissionTextComponent(
    title: String, text: Binding<String>, context: ViewBuildContext,
    onKey: @escaping @MainActor (UInt32) -> Void, onIME: @escaping @MainActor () -> Void,
    onFocusEnter: @escaping @MainActor () -> Void = {}
) -> Component {
    let field = TextField(title, text: text).makeComponent(context: context)
    return Component { runtime in
        let node = field.makeNode(runtime: runtime)
        node.frame = Rect(x: 10, y: 10, width: 100, height: 30)
        // Forward the real handlers so these counters detect synthetic input
        // without replacing the built-in editor or its text capability.
        let focusHandler = node.onFocusEnter
        node.onFocusEnter = {
            onFocusEnter()
            focusHandler?()
        }
        let keyHandler = node.onKeyDown
        node.onKeyDown = { event in
            onKey(event.keyCode)
            keyHandler?(event)
        }
        let imeHandler = node.onIMEComposition
        node.onIMEComposition = { event in
            onIME()
            imeHandler?(event)
        }
        return node
    }
}

@MainActor
private final class UIAAdmissionMutationProbe {
    var text = "original"
    var effects = 0
    var textWrites = 0
    var keyCodes: [UInt32] = []
    var imeEvents = 0
}

@MainActor
private final class UIAAdmissionFixture {
    let target: ViewNode
    let root: ViewNode
    let runtime: RetainedViewRuntime
    let source: RuntimeUIAElementTreeSource
    private let probe: UIAAdmissionMutationProbe
    private let componentHost: ComponentHost?

    var effects: Int { probe.effects }
    var textWrites: Int { probe.textWrites }
    var keyCodes: [UInt32] { probe.keyCodes }
    var imeEvents: Int { probe.imeEvents }

    init(route: UIAAdmissionRoute) throws {
        var needsTextCleanup = route == .value
        if needsTextCleanup { uiaAdmissionInstallTextLayout() }
        defer { if needsTextCleanup { NativeTextRenderer.resetTestingOverrides() } }
        let probe = UIAAdmissionMutationProbe()
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 220, height: 100))
        let runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 0 }
        let target: ViewNode
        if route == .value {
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 220, height: 100) },
                invalidateHandler: { [weak host] in host?.reload() })
            let text = Binding<String>(
                get: { probe.text },
                set: { value in
                    probe.text = value
                    probe.effects += 1
                    probe.textWrites += 1
                })
            let field = uiaAdmissionTextComponent(
                title: "Target", text: text, context: context,
                onKey: { probe.keyCodes.append($0) }, onIME: { probe.imeEvents += 1 },
                onFocusEnter: { probe.effects += 1 })
            host.setComponents { [field] }
            target = try XCTUnwrap(runtime.root.children.first { $0.textInputController != nil })
            componentHost = host
        } else {
            target = ViewNode(
                frame: Rect(x: 10, y: 10, width: 100, height: 30), isFocusable: true,
                accessibilityLabel: "Target", accessibilityTraits: route.traits)
            root.addChild(target)
            target.onActivate = { [weak probe] in probe?.effects += 1 }
            target.onFocusEnter = { [weak probe] in probe?.effects += 1 }
            target.onKeyDown = { [weak probe] event in probe?.keyCodes.append(event.keyCode) }
            target.onIMEComposition = { [weak probe] _ in
                probe?.effects += 1
                probe?.textWrites += 1
                probe?.imeEvents += 1
            }
            componentHost = nil
        }
        self.target = target
        self.root = root
        self.runtime = runtime
        self.probe = probe
        source = RuntimeUIAElementTreeSource(runtime: runtime)
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: root))
        needsTextCleanup = false
    }

    func id() throws -> UInt64 {
        try XCTUnwrap(source.uiaElementSnapshots().first { $0.name == "Target" }?.id)
    }

    func retire() {
        runtime.stopRenderLifecycleCallbacks()
        runtime.clock = { 0 }
        target.onActivate = nil
        target.onFocusEnter = nil
        target.onKeyDown = nil
        target.onIMEComposition = nil
        if runtime.retainedBuildCoordinator.isBuilding { runtime.retainedBuildCoordinator.finishBuild() }
        runtime.cancelRenderLifecycleTasks()
        if componentHost != nil { NativeTextRenderer.resetTestingOverrides() }
    }
}

@MainActor
private final class UIAAdmissionReleaseProbe {
    weak var payload: UIAAdmissionReleasePayload?
    var releases = 0
    var attempts: [Bool] = []
}

@MainActor
private final class UIAAdmissionReleasePayload {
    let onRelease: @MainActor () -> Void
    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

@MainActor
private final class UIAAdmissionRuntimeOwner {
    var runtime: RetainedViewRuntime?
}

@MainActor
private final class UIAAdmissionRuntimeProbe {
    weak var runtime: RetainedViewRuntime?
    var text = "original"
    var effects = 0
    var keyCodes: [UInt32] = []
    var imeEvents = 0
    var aliveDuringEffect: [Bool] = []
}

@MainActor
private final class UIAAdmissionRuntimeLifetimeFixture {
    let owner: UIAAdmissionRuntimeOwner
    let probe: UIAAdmissionRuntimeProbe
    let target: ViewNode
    let source: RuntimeUIAElementTreeSource
    let id: UInt64

    init() throws {
        uiaAdmissionInstallTextLayout()
        var needsTextCleanup = true
        defer { if needsTextCleanup { NativeTextRenderer.resetTestingOverrides() } }
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100)))
        runtime.clock = { 0 }
        let owner = UIAAdmissionRuntimeOwner()
        owner.runtime = runtime
        let probe = UIAAdmissionRuntimeProbe()
        probe.runtime = runtime
        let text = Binding<String>(
            get: { probe.text },
            set: { [weak owner] value in
                probe.text = value
                owner?.runtime = nil
                probe.effects += 1
                probe.aliveDuringEffect.append(probe.runtime != nil)
            })
        // Neither the retained editor's context nor its binding owns runtime.
        // The synchronous replacement may pin it, but this fixture must not
        // keep it alive after the call returns.
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 100) }, invalidateHandler: {})
        target = uiaAdmissionTextComponent(
            title: "Lifetime edit", text: text, context: context,
            onKey: { probe.keyCodes.append($0) }, onIME: { probe.imeEvents += 1 }
        ).makeNode(runtime: runtime)
        runtime.root.addChild(target)
        source = RuntimeUIAElementTreeSource(runtime: runtime)
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        id = try XCTUnwrap(source.uiaElementSnapshots().first { $0.name == "Lifetime edit" }?.id)
        self.owner = owner
        self.probe = probe
        needsTextCleanup = false
    }

    func retire() {
        probe.runtime?.stopRenderLifecycleCallbacks()
        probe.runtime?.cancelRenderLifecycleTasks()
        owner.runtime = nil
        target.onKeyDown = nil
        target.onIMEComposition = nil
        NativeTextRenderer.resetTestingOverrides()
    }
}
