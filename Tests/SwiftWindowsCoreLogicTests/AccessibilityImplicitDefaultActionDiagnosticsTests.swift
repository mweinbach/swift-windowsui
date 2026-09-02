import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Reproduces the existing rejection matrix without changing its operation order.
/// Only a failed button lookup prints diagnostics from its original projection.
@MainActor
final class AccessibilityImplicitDefaultActionDiagnosticsTests: XCTestCase {
    func testImplicitDefaultRejectionMatrixLookupDiagnostics() async throws {
        for rejection in DiagnosticImplicitActionRejection.allCases {
            var generation = 0
            var calls = 0
            let host = MountedOnChangeTestHost {
                AnyView(
                    Button("Action") { calls += 1 }
                        .accessibilityIdentifier("same-public-identifier")
                        .id(generation))
            }
            defer { host.close() }
            host.render()
            let target = try diagnosticImplicitButton(
                named: "Action", in: host, rejection: rejection,
                phase: "initial-after-render", originalLine: 225)
            let cached = try diagnosticImplicitElement(for: target, in: host.runtime)
            XCTAssertTrue(cached.actions.isEmpty, "\(rejection)")
            XCTAssertTrue(cached.invokeDefaultAction(), "\(rejection)")
            host.render()
            XCTAssertEqual(calls, 1, "\(rejection)")
            XCTAssertTrue(
                try diagnosticImplicitButton(
                    named: "Action", in: host, rejection: rejection,
                    phase: "after-first-invocation-render", originalLine: 231) === target)
            let ancestor = try XCTUnwrap(target.parent)
            let escaped = try XCTUnwrap(target.onActivate)
            var modal: ViewNode?
            var disabledSnapshot: AccessibilityElementProjection?

            switch rejection {
            case .ownDisabled:
                target.accessibilityRespondsToUserInteraction = false
                disabledSnapshot = try diagnosticImplicitElement(for: target, in: host.runtime)
            case .ancestorDisabled:
                ancestor.accessibilityRespondsToUserInteraction = false
                disabledSnapshot = try diagnosticImplicitElement(for: target, in: host.runtime)
            case .ownHidden:
                target.isHidden = true
            case .ancestorHidden:
                ancestor.isHidden = true
            case .ownAccessibilityHidden:
                target.isAccessibilityHidden = true
            case .ancestorAccessibilityHidden:
                ancestor.isAccessibilityHidden = true
            case .competingModal, .structuralModalAncestor:
                let presented = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 40, height: 20),
                    accessibilityLabel: "Presented modal", accessibilityTraits: .isModal)
                modal = presented
                if rejection == .structuralModalAncestor {
                    target.addChild(presented)
                } else {
                    host.runtime.root.addChild(presented)
                }
            case .removed:
                ancestor.removeChild(target)
            case .replaced:
                generation += 1
                host.reload()
                host.render()
                let replacement = try diagnosticImplicitButton(
                    named: "Action", in: host, rejection: rejection,
                    phase: "replaced-after-reload-render", originalLine: 268)
                XCTAssertFalse(replacement === target)
                XCTAssertEqual(replacement.accessibilityIdentifier, target.accessibilityIdentifier)
            case .closed:
                host.close()
            }
            XCTAssertFalse(cached.invokeDefaultAction(), "\(rejection)")
            XCTAssertEqual(calls, 1, "\(rejection)")
            if let disabledSnapshot {
                XCTAssertFalse(disabledSnapshot.isEnabled)
                XCTAssertFalse(disabledSnapshot.invokeDefaultAction())
            }
            if rejection == .structuralModalAncestor {
                let structural = try diagnosticImplicitElement(for: target, in: host.runtime)
                XCTAssertTrue(structural.actions.isEmpty)
                XCTAssertFalse(structural.invokeDefaultAction())
                XCTAssertEqual(calls, 1)
            }
            if rejection == .removed || rejection == .replaced || rejection == .closed {
                // These are retired physical owners, not merely hidden ones.
                // Their escaped Void wrappers cannot report acceptance.
                escaped()
                XCTAssertEqual(calls, 1, "\(rejection)")
            }

            target.accessibilityRespondsToUserInteraction = nil
            ancestor.accessibilityRespondsToUserInteraction = nil
            target.isHidden = false
            ancestor.isHidden = false
            target.isAccessibilityHidden = false
            ancestor.isAccessibilityHidden = false
            if let modal { modal.parent?.removeChild(modal) }
            if rejection == .removed {
                // A new declaration is accepted; never reattach a retired node.
                generation += 1
                host.reload()
            }
            if rejection == .closed {
                let replacementHost = MountedOnChangeTestHost {
                    AnyView(
                        Button("Action") { calls += 1 }
                            .accessibilityIdentifier("same-public-identifier"))
                }
                defer { replacementHost.close() }
                replacementHost.render()
                let replacement = try diagnosticImplicitButton(
                    named: "Action", in: replacementHost, rejection: rejection,
                    phase: "replacement-host-after-close", originalLine: 313)
                let fresh = try diagnosticImplicitElement(for: replacement, in: replacementHost.runtime)
                XCTAssertTrue(fresh.invokeDefaultAction())
                XCTAssertEqual(calls, 2)
                XCTAssertFalse(cached.invokeDefaultAction())
            } else {
                host.render()
                if let disabledSnapshot {
                    XCTAssertFalse(disabledSnapshot.invokeDefaultAction())
                    XCTAssertEqual(calls, 1)
                }
                let current = try diagnosticImplicitButton(
                    named: "Action", in: host, rejection: rejection,
                    phase: "restored-after-render", originalLine: 324)
                let fresh = try diagnosticImplicitElement(for: current, in: host.runtime)
                XCTAssertTrue(fresh.invokeDefaultAction(), "\(rejection)")
                XCTAssertEqual(calls, 2, "\(rejection)")
                if rejection == .removed || rejection == .replaced {
                    XCTAssertFalse(current === target)
                    XCTAssertFalse(cached.invokeDefaultAction())
                    XCTAssertEqual(calls, 2)
                }
            }
        }
    }
}

@MainActor
private func diagnosticImplicitElement(for node: ViewNode, in runtime: RetainedViewRuntime) throws
    -> AccessibilityElementProjection
{
    try XCTUnwrap(AccessibilityProjection.project(runtime: runtime)?.flattened().first { $0.sourceNode === node })
}

private enum DiagnosticImplicitActionRejection: CaseIterable {
    case ownDisabled, ancestorDisabled, ownHidden, ancestorHidden
    case ownAccessibilityHidden, ancestorAccessibilityHidden
    case competingModal, structuralModalAncestor, removed, replaced, closed
}

@MainActor
private func diagnosticImplicitButton(
    named name: String, in host: MountedOnChangeTestHost,
    rejection: DiagnosticImplicitActionRejection, phase: String, originalLine: UInt,
    file: StaticString = #filePath, line: UInt = #line
) throws -> ViewNode {
    // This is the original helper's single projection, flatten, and predicate.
    let projection = AccessibilityProjection.project(runtime: host.runtime)
    let elements = projection?.flattened() ?? []
    let match = elements.first { $0.controlType == .button && $0.name == name }
    let context =
        "case=\(rejection) phase=\(phase) originalCaller=AccessibilityImplicitDefaultActionTests.swift:\(originalLine)"
    if match == nil {
        print(
            diagnosticImplicitLookupState(
                context: context, reason: "missing-projected-button", name: name,
                projection: projection, elements: elements, root: host.runtime.root),
            terminator: "")
    }
    let element = try XCTUnwrap(match, context, file: file, line: line)
    let sourceNode = element.sourceNode
    if sourceNode == nil {
        print(
            diagnosticImplicitLookupState(
                context: context, reason: "missing-source-node", name: name,
                projection: projection, elements: elements, root: host.runtime.root),
            terminator: "")
    }
    return try XCTUnwrap(sourceNode, context, file: file, line: line)
}

@MainActor
private func diagnosticImplicitLookupState(
    context: String, reason: String, name: String,
    projection: AccessibilityElementProjection?, elements: [AccessibilityElementProjection], root: ViewNode
) -> String {
    let maximumNodes = 64
    let maximumEdges = 256
    let maximumProjectedElements = 64
    var output = DiagnosticImplicitScalarOutput()
    output.append("ImplicitDefaultDiagnostic \(context) reason=\(reason) wanted=\(diagnosticImplicitText(name))")
    output.append(
        "projectionPresent=\(projection != nil) projectedCount=\(elements.count) root=\(diagnosticImplicitID(root))"
    )

    // Stored native children only: no parent walk, modal authority, projection,
    // layout query, or authored callback. Register IDs before enqueueing so
    // shared edges and cycles cannot grow the queue or revisit a node.
    var pending: [ViewNode] = [root]
    var seen: Set<ObjectIdentifier> = [ObjectIdentifier(root)]
    var cursor = 0
    var scannedEdges = 0
    var repeatedEdges = 0
    var nodeLimitReached = false
    var edgeLimitReached = false
    while cursor < pending.count {
        let node = pending[cursor]
        cursor += 1
        let responds = node.accessibilityRespondsToUserInteraction.map { $0 ? "true" : "false" } ?? "nil"
        output.append(
            "retained[\(cursor - 1)] id=\(diagnosticImplicitID(node)) parent=\(diagnosticImplicitID(node.parent))"
                + " hidden=\(node.isHidden) accessibilityHidden=\(node.isAccessibilityHidden) responds=\(responds)"
                + " traits=\(node.accessibilityTraits.rawValue) children=\(node.children.count)"
                + " behavior=\(diagnosticImplicitBehavior(node.accessibilityChildBehavior))"
                + " representationChildren=\(node.accessibilityRepresentationChildren?.count ?? -1)"
                + " label=\(diagnosticImplicitText(node.accessibilityLabel)) text=\(diagnosticImplicitText(node.text))"
                + " identifier=\(diagnosticImplicitText(node.accessibilityIdentifier))"
        )
        let edgeCount = min(node.children.count, maximumEdges - scannedEdges)
        if edgeCount < node.children.count { edgeLimitReached = true }
        for child in node.children.prefix(edgeCount) {
            scannedEdges += 1
            let identifier = ObjectIdentifier(child)
            if seen.contains(identifier) {
                repeatedEdges += 1
                continue
            }
            guard pending.count < maximumNodes else {
                nodeLimitReached = true
                continue
            }
            seen.insert(identifier)
            pending.append(child)
        }
    }
    output.append(
        "retainedVisited=\(cursor) scannedEdges=\(scannedEdges) repeatedEdges=\(repeatedEdges)"
            + " nodeLimitReached=\(nodeLimitReached) edgeLimitReached=\(edgeLimitReached)"
    )

    // Read the already flattened projection, never project or flatten again.
    for (index, element) in elements.prefix(maximumProjectedElements).enumerated() {
        output.append(
            "projected[\(index)] source=\(diagnosticImplicitID(element.sourceNode)) type=\(element.controlType.rawValue)"
                + " enabled=\(element.isEnabled) traits=\(element.traits.rawValue) actions=\(element.actions.count)"
                + " placeholder=\(element.isVirtualizedPlaceholder) children=\(element.children.count)"
                + " name=\(diagnosticImplicitText(element.name)) identifier=\(diagnosticImplicitText(element.identifier))"
        )
    }
    output.append("projectedOmitted=\(max(0, elements.count - maximumProjectedElements))")
    // Only this scalar String leaves the synchronous inspection. No ViewNode
    // or projection is captured by deferred logging or kept across an action.
    return output.finish()
}

@MainActor
private func diagnosticImplicitID(_ object: AnyObject?) -> String {
    guard let object else { return "nil" }
    return String(describing: ObjectIdentifier(object))
}

private func diagnosticImplicitBehavior(_ behavior: RetainedAccessibilityChildBehavior?) -> String {
    switch behavior {
    case .ignore?: return "ignore"
    case .combine?: return "combine"
    case .contain?: return "contain"
    case nil: return "nil"
    }
}

private func diagnosticImplicitText(_ value: String?) -> String {
    guard let value else { return "nil" }
    // At most 64 stored UTF-8 bytes are escaped, with one lookahead byte.
    // The result is ASCII and at most 261 bytes, even for control characters.
    let prefix = Array(value.utf8.prefix(65))
    var result = "\""
    for byte in prefix.prefix(64) {
        switch byte {
        case 0x22: result += "\\\""
        case 0x5C: result += "\\\\"
        case 0x20...0x7E: result += String(UnicodeScalar(UInt32(byte))!)
        default:
            result += "\\x" + (byte < 16 ? "0" : "") + String(byte, radix: 16)
        }
    }
    result += "\""
    if prefix.count > 64 { result += "..." }
    return result
}

private struct DiagnosticImplicitScalarOutput {
    private static let maximumBytes = 65_536
    private static let truncationMarker = Array("ImplicitDefaultDiagnostic output truncated\n".utf8)
    private var bytes: [UInt8] = []
    private var wasTruncated = false

    mutating func append(_ line: String) {
        // All callers supply ASCII: fixed labels, native IDs/scalars, and
        // diagnosticImplicitText's escaped strings. Include newline and reserve
        // space for a final truncation marker inside the total 64 KiB budget.
        let remaining = Self.maximumBytes - Self.truncationMarker.count - bytes.count
        guard remaining > 1 else {
            wasTruncated = true
            return
        }
        let limit = min(1_023, remaining - 1)
        let prefix = Array(line.utf8.prefix(limit + 1))
        bytes.append(contentsOf: prefix.prefix(limit))
        bytes.append(0x0A)
        if prefix.count > limit { wasTruncated = true }
    }

    func finish() -> String {
        var result = bytes
        if wasTruncated { result.append(contentsOf: Self.truncationMarker) }
        return String(decoding: result, as: UTF8.self)
    }
}
