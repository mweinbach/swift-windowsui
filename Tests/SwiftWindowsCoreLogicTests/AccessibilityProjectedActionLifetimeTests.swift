import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Copied retained actions only: no live UIA source, HWND, or COM provider.
@MainActor
final class AccessibilityProjectedActionLifetimeTests: XCTestCase {
    func testCopiedActionsPinTheEntryRuntimeWhenLayoutDropsItsLastOwner() async throws {
        for route in ProjectedLifetimeRoute.allCases {
            let fixture = try ProjectedLifetimeFixture(route: route, drop: .layout)
            defer { fixture.retire() }
            XCTAssertNotNil(fixture.probe.runtime)

            let accepted = fixture.action.invoke()
            XCTAssertEqual(accepted, route == .defaultAction ? true : nil)
            XCTAssertEqual(fixture.probe.layoutCallbacks, 1)
            XCTAssertEqual(fixture.probe.calls, 1)
            XCTAssertEqual(fixture.probe.aliveInHandler, [true])
            XCTAssertEqual(fixture.probe.fallbackCalls, 0)
            XCTAssertNil(fixture.owner.runtime)
            XCTAssertNil(fixture.probe.runtime)

            let repeated = fixture.action.invoke()
            XCTAssertEqual(repeated, route == .defaultAction ? false : nil)
            XCTAssertEqual(fixture.probe.layoutCallbacks, 1)
            XCTAssertEqual(fixture.probe.calls, 1)
            XCTAssertEqual(fixture.probe.fallbackCalls, 0)
            withExtendedLifetime(fixture.root) {}
        }
    }

    func testCopiedActionsPinTheEntryRuntimeThroughHandlerRevocation() async throws {
        for route in ProjectedLifetimeRoute.allCases {
            let fixture = try ProjectedLifetimeFixture(route: route, drop: .handler)
            defer { fixture.retire() }
            // This action has a separate projection scope. It must be stopped
            // by terminal revocation, not the primary scope's reentry guard.
            fixture.secondaryAction.invoke()
            XCTAssertEqual(fixture.probe.secondaryCalls, 1)
            fixture.probe.secondaryCalls = 0

            let accepted = fixture.action.invoke()
            XCTAssertEqual(accepted, route == .defaultAction ? true : nil)
            XCTAssertEqual(fixture.probe.calls, 1)
            XCTAssertEqual(fixture.probe.aliveInHandler, [true])
            XCTAssertEqual(fixture.probe.aliveAfterOwnerDrop, [true])
            XCTAssertEqual(fixture.probe.aliveAfterNestedAction, [true])
            XCTAssertEqual(fixture.probe.secondaryCalls, 0)
            XCTAssertEqual(fixture.probe.fallbackCalls, 0)
            XCTAssertNil(fixture.owner.runtime)
            XCTAssertNil(fixture.probe.runtime)

            let repeated = fixture.action.invoke()
            XCTAssertEqual(repeated, route == .defaultAction ? false : nil)
            fixture.secondaryAction.invoke()
            XCTAssertEqual(fixture.probe.calls, 1)
            XCTAssertEqual(fixture.probe.secondaryCalls, 0)
            XCTAssertEqual(fixture.probe.fallbackCalls, 0)
            withExtendedLifetime(fixture.root) {}
        }
    }
}

private enum ProjectedLifetimeRoute: CaseIterable, Sendable {
    case named
    case defaultAction
}

private enum ProjectedLifetimeDrop: Sendable {
    case layout
    case handler
}

@MainActor
private enum EscapedLifetimeAction {
    case named(AccessibilityProjectedAction)
    case defaultElement(AccessibilityElementProjection)

    func invoke() -> Bool? {
        switch self {
        case .named(let action):
            action.invoke()
            return nil
        case .defaultElement(let element):
            return element.invokeDefaultAction()
        }
    }
}

@MainActor
private final class ProjectedRuntimeOwner {
    var runtime: RetainedViewRuntime?

    init(runtime: RetainedViewRuntime) {
        self.runtime = runtime
    }
}

@MainActor
private final class ProjectedRuntimeProbe {
    weak var runtime: RetainedViewRuntime?
    var layoutCallbacks = 0
    var calls = 0
    var fallbackCalls = 0
    var secondaryCalls = 0
    var aliveInHandler: [Bool] = []
    var aliveAfterOwnerDrop: [Bool] = []
    var aliveAfterNestedAction: [Bool] = []

    init(runtime: RetainedViewRuntime) {
        self.runtime = runtime
    }
}

@MainActor
private final class ProjectedLifetimeFixture {
    let owner: ProjectedRuntimeOwner
    let probe: ProjectedRuntimeProbe
    let root: ViewNode
    let target: ViewNode
    let secondary: ViewNode
    let action: EscapedLifetimeAction
    let secondaryAction: AccessibilityProjectedAction

    init(route: ProjectedLifetimeRoute, drop: ProjectedLifetimeDrop) throws {
        let target = ViewNode(
            frame: Rect(x: 10, y: 10, width: 100, height: 30),
            accessibilityLabel: "Primary", accessibilityTraits: .isButton)
        let secondary = ViewNode(
            frame: Rect(x: 10, y: 50, width: 100, height: 30),
            accessibilityLabel: "Secondary", accessibilityTraits: .isButton)
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 240, height: 160), children: [target, secondary])
        let runtime = RetainedViewRuntime(root: root)
        let owner = ProjectedRuntimeOwner(runtime: runtime)
        let probe = ProjectedRuntimeProbe(runtime: runtime)
        secondary.accessibilityActions = [
            RetainedAccessibilityAction(name: "Secondary") { probe.secondaryCalls += 1 }
        ]
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: root))
        let secondaryElement = try XCTUnwrap(
            AccessibilityProjection.project(runtime: runtime)?.flattened().first { $0.sourceNode === secondary })
        let secondaryAction = try XCTUnwrap(secondaryElement.actions.first)
        target.onActivate = { probe.fallbackCalls += 1 }
        target.accessibilityActions = [
            RetainedAccessibilityAction(
                name: route == .named ? "Apply" : nil,
                kind: route == .defaultAction ? .default : nil
            ) { [weak owner] in
                probe.calls += 1
                probe.aliveInHandler.append(probe.runtime != nil)
                if drop == .handler {
                    owner?.runtime = nil
                    probe.aliveAfterOwnerDrop.append(probe.runtime != nil)
                    probe.runtime?.stopRenderLifecycleCallbacks()
                    secondaryAction.invoke()
                    probe.aliveAfterNestedAction.append(probe.runtime != nil)
                }
            }
        ]
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: root))
        let element = try XCTUnwrap(
            AccessibilityProjection.project(runtime: runtime)?.flattened().first { $0.sourceNode === target })
        let action: EscapedLifetimeAction
        switch route {
        case .named:
            action = .named(try XCTUnwrap(element.actions.first))
        case .defaultAction:
            action = .defaultElement(element)
        }
        if drop == .layout {
            runtime.scheduleAfterLayout(key: "drop-last-projected-runtime-owner") { [weak owner, weak probe] in
                probe?.layoutCallbacks += 1
                owner?.runtime = nil
            }
        }
        self.owner = owner
        self.probe = probe
        self.root = root
        self.target = target
        self.secondary = secondary
        self.action = action
        self.secondaryAction = secondaryAction
        // This initializer's local is gone before invocation. Only `owner`
        // keeps the runtime alive; nodes, probes, and copied actions are weak.
    }

    func retire() {
        probe.runtime?.stopRenderLifecycleCallbacks()
        probe.runtime?.cancelRenderLifecycleTasks()
        owner.runtime = nil
        target.accessibilityActions = []
        target.onActivate = nil
        secondary.accessibilityActions = []
    }
}
