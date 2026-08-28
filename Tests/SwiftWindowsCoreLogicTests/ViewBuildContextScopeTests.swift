import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewBuildContextScopeTests: XCTestCase {
    func testNestedScopesReturnResultsAndRestorePriorContextAndNil() async {
        XCTAssertNil(ViewBuildContextScope.current)
        let outer = scopeContext(size: Size(width: 160, height: 120), colorScheme: .dark)
            .withViewIdentityPrefix([.slot(1)])
        let inner = scopeContext(size: Size(width: 80, height: 60), colorScheme: .light)
            .withViewIdentityPrefix([.slot(2)])

        let result = ViewBuildContextScope.withCurrent(outer) {
            XCTAssertEqual(ViewBuildContextScope.current?.canvasSize, outer.canvasSize)
            XCTAssertEqual(ViewBuildContextScope.current?.retainedViewIdentity, outer.retainedViewIdentity)
            XCTAssertEqual(Environment<ColorScheme>(\.colorScheme).wrappedValue, .dark)

            let nestedResult = ViewBuildContextScope.withCurrent(inner) {
                XCTAssertEqual(ViewBuildContextScope.current?.canvasSize, inner.canvasSize)
                XCTAssertEqual(ViewBuildContextScope.current?.retainedViewIdentity, inner.retainedViewIdentity)
                XCTAssertEqual(Environment<ColorScheme>(\.colorScheme).wrappedValue, .light)
                return 37
            }

            XCTAssertEqual(nestedResult, 37)
            XCTAssertEqual(ViewBuildContextScope.current?.canvasSize, outer.canvasSize)
            XCTAssertEqual(ViewBuildContextScope.current?.retainedViewIdentity, outer.retainedViewIdentity)
            XCTAssertEqual(Environment<ColorScheme>(\.colorScheme).wrappedValue, .dark)
            return nestedResult + 5
        }

        XCTAssertEqual(result, 42)
        XCTAssertNil(ViewBuildContextScope.current)
    }

    func testMutatingCurrentContextCopyDoesNotChangeTheActiveIdentity() async {
        XCTAssertNil(ViewBuildContextScope.current)
        let original = scopeContext(size: Size(width: 160, height: 120), colorScheme: .dark)
            .withViewIdentityPrefix([.slot(1)])
        let originalIdentity = original.retainedViewIdentity

        ViewBuildContextScope.withCurrent(original) {
            guard var copy = ViewBuildContextScope.current else {
                XCTFail("The entered context must be readable")
                return
            }
            copy.viewIdentity.path = copy.retainedViewIdentity.appending(.slot(99))
            copy.viewIdentity.currentType = ObjectIdentifier(Text.self)

            XCTAssertNotEqual(copy.retainedViewIdentity, originalIdentity)
            XCTAssertEqual(ViewBuildContextScope.current?.retainedViewIdentity, originalIdentity)
            XCTAssertNil(ViewBuildContextScope.current?.viewIdentity.currentType)

            ViewBuildContextScope.withCurrent(copy) {
                XCTAssertEqual(ViewBuildContextScope.current?.retainedViewIdentity, copy.retainedViewIdentity)
                XCTAssertEqual(ViewBuildContextScope.current?.viewIdentity.currentType, ObjectIdentifier(Text.self))
            }

            XCTAssertEqual(ViewBuildContextScope.current?.retainedViewIdentity, originalIdentity)
            XCTAssertNil(ViewBuildContextScope.current?.viewIdentity.currentType)
        }

        XCTAssertEqual(original.retainedViewIdentity, originalIdentity)
        XCTAssertNil(original.viewIdentity.currentType)
        XCTAssertNil(ViewBuildContextScope.current)
    }

    func testSynchronousReentrantSnapshotRestoresOuterEnvironmentAndCallerScope() async {
        XCTAssertNil(ViewBuildContextScope.current)
        let caller = scopeContext(size: Size(width: 80, height: 60), colorScheme: .light)
            .withViewIdentityPrefix([.slot(7)])
        var events: [String] = []

        ViewBuildContextScope.withCurrent(caller) {
            let outerView = ScopeSnapshotEnvironmentProbe(name: "Outer") { scheme in
                events.append("outer.before:\(scopeSchemeName(scheme))")
                let outerIdentity = ViewBuildContextScope.current?.retainedViewIdentity
                XCTAssertEqual(ViewBuildContextScope.current?.canvasSize, Size(width: 160, height: 120))

                let innerView = ScopeSnapshotEnvironmentProbe(name: "Inner") { innerScheme in
                    events.append("inner:\(scopeSchemeName(innerScheme))")
                    XCTAssertEqual(ViewBuildContextScope.current?.canvasSize, Size(width: 120, height: 90))
                }
                let inner = WinSwiftUIRendererSnapshotter.snapshot(
                    of: innerView, size: IntSize(width: 120, height: 90), colorScheme: .light)
                defer { retireScopeSnapshot(inner) }
                XCTAssertTrue(scopeTreeContains("Inner", in: inner.runtime.root))

                let restoredScheme = Environment<ColorScheme>(\.colorScheme).wrappedValue
                events.append("outer.after:\(scopeSchemeName(restoredScheme))")
                XCTAssertEqual(ViewBuildContextScope.current?.canvasSize, Size(width: 160, height: 120))
                XCTAssertEqual(ViewBuildContextScope.current?.retainedViewIdentity, outerIdentity)
            }
            let outer = WinSwiftUIRendererSnapshotter.snapshot(
                of: outerView, size: IntSize(width: 160, height: 120), colorScheme: .dark)
            defer { retireScopeSnapshot(outer) }
            XCTAssertTrue(scopeTreeContains("Outer", in: outer.runtime.root))

            events.append("caller:\(scopeSchemeName(Environment<ColorScheme>(\.colorScheme).wrappedValue))")
            XCTAssertEqual(ViewBuildContextScope.current?.canvasSize, caller.canvasSize)
            XCTAssertEqual(ViewBuildContextScope.current?.retainedViewIdentity, caller.retainedViewIdentity)
        }

        XCTAssertEqual(events, ["outer.before:dark", "inner:light", "outer.after:dark", "caller:light"])
        XCTAssertNil(ViewBuildContextScope.current)
    }

    func testRestoredScopeDoesNotRetainTheDepartedProviderPayload() async {
        XCTAssertNil(ViewBuildContextScope.current)
        let outer = scopeContext(size: Size(width: 160, height: 120), colorScheme: .dark)
        let witness = ScopeProviderWitness()

        ViewBuildContextScope.withCurrent(outer) {
            enterTemporaryProviderScope(witness)
            // The helper's context and strong payload locals have returned.
            // A saved scope must not keep the departed inner scope alive.
            XCTAssertNil(witness.payload)
            XCTAssertEqual(ViewBuildContextScope.current?.canvasSize, outer.canvasSize)
            XCTAssertEqual(Environment<ColorScheme>(\.colorScheme).wrappedValue, .dark)
        }

        XCTAssertNil(witness.payload)
        XCTAssertNil(ViewBuildContextScope.current)
    }

    private func enterTemporaryProviderScope(_ witness: ScopeProviderWitness) {
        let payload = ScopeProviderPayload(size: Size(width: 23, height: 41))
        witness.payload = payload
        let context = ViewBuildContext(
            canvasSizeProvider: { [payload] in payload.size }, invalidateHandler: {})

        ViewBuildContextScope.withCurrent(context) {
            XCTAssertNotNil(witness.payload)
            XCTAssertEqual(ViewBuildContextScope.current?.canvasSize, Size(width: 23, height: 41))
        }
    }
}

@MainActor
private func scopeContext(size: Size, colorScheme: ColorScheme) -> ViewBuildContext {
    ViewBuildContext(
        canvasSizeProvider: { size }, invalidateHandler: {},
        environmentValuesProvider: { EnvironmentValues(colorScheme: colorScheme) })
}

@MainActor
private func scopeSchemeName(_ scheme: ColorScheme) -> String {
    scheme == .dark ? "dark" : "light"
}

@MainActor
private struct ScopeSnapshotEnvironmentProbe: View {
    @Environment(\.colorScheme) private var scheme
    let name: String
    let read: (ColorScheme) -> Void

    init(name: String, read: @escaping (ColorScheme) -> Void) {
        self.name = name
        self.read = read
    }

    var body: some View {
        read(scheme)
        return Text(name)
    }
}

@MainActor
private func scopeTreeContains(_ text: String, in root: ViewNode) -> Bool {
    var pending = [root]
    while let node = pending.popLast() {
        if node.text == text { return true }
        pending.append(contentsOf: node.children)
    }
    return false
}

@MainActor
private func retireScopeSnapshot(_ snapshot: WinSwiftUIRenderSnapshot) {
    snapshot.runtime.stopRenderLifecycleCallbacks()
    snapshot.runtime.cancelRenderLifecycleTasks()
}

private final class ScopeProviderPayload {
    let size: Size

    init(size: Size) {
        self.size = size
    }
}

private final class ScopeProviderWitness {
    weak var payload: ScopeProviderPayload?
}
