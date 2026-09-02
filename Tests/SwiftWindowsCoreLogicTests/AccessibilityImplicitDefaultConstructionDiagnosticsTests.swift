import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// One removed-case diagnostic. Entry counts do not assert adoption or acceptance.
/// Only scalar snapshots surround the original explicit reload; all renders and
/// projection queries stay in the original removed-case order.
@MainActor
final class AccessibilityImplicitDefaultConstructionDiagnosticsTests: XCTestCase {
    func testRemovedButtonRestorationNativeConstructionCut() async throws {
        let rejection = "removed"
        var generation = 0
        var calls = 0
        var contentEntries = 0
        var lastEnteredGeneration = -1
        let host = MountedOnChangeTestHost {
            contentEntries += 1
            lastEnteredGeneration = generation
            return AnyView(
                Button("Action") { calls += 1 }
                    .accessibilityIdentifier("same-public-identifier")
                    .id(generation))
        }
        defer { host.close() }
        host.render()
        let target = try constructionCutButton(named: "Action", in: host)
        let cached = try constructionCutElement(for: target, in: host.runtime)
        XCTAssertTrue(cached.actions.isEmpty, "\(rejection)")
        XCTAssertTrue(cached.invokeDefaultAction(), "\(rejection)")
        host.render()
        XCTAssertEqual(calls, 1, "\(rejection)")
        XCTAssertTrue(try constructionCutButton(named: "Action", in: host) === target)
        let ancestor = try XCTUnwrap(target.parent)
        let escaped = try XCTUnwrap(target.onActivate)
        ancestor.removeChild(target)
        XCTAssertFalse(cached.invokeDefaultAction(), "\(rejection)")
        XCTAssertEqual(calls, 1, "\(rejection)")
        // These are retired physical owners, not merely hidden ones.
        // Their escaped Void wrappers cannot report acceptance.
        escaped()
        XCTAssertEqual(calls, 1, "\(rejection)")
        target.accessibilityRespondsToUserInteraction = nil
        ancestor.accessibilityRespondsToUserInteraction = nil
        target.isHidden = false
        ancestor.isHidden = false
        target.isAccessibilityHidden = false
        ancestor.isAccessibilityHidden = false
        // A new declaration is accepted; never reattach a retired node.
        generation += 1
        let generationBeforeReload = generation
        let entriesBeforeReload = contentEntries
        let lastGenerationBeforeReload = lastEnteredGeneration
        let constructionDiagnostic = host.componentHost.requestConstructionDiagnostic()
        let childrenBeforeReload = host.runtime.root.children.count
        host.reload()
        let childrenAfterReload = host.runtime.root.children.count
        let generationAfterReload = generation
        let entriesAfterReload = contentEntries
        let lastGenerationAfterReload = lastEnteredGeneration
        print(
            "ImplicitDefaultRestorationEntry case=removed phase=restore-reload"
                + " generationBefore=\(generationBeforeReload) entriesBefore=\(entriesBeforeReload)"
                + " lastGenerationBefore=\(lastGenerationBeforeReload) childrenBefore=\(childrenBeforeReload)"
                + " generationAfter=\(generationAfterReload) entriesAfter=\(entriesAfterReload)"
                + " lastGenerationAfter=\(lastGenerationAfterReload) childrenAfter=\(childrenAfterReload)")
        print(
            "ImplicitDefaultConstructionCut case=removed phase=restore-reload"
                + " requestBound=\(constructionDiagnostic.requestBound)"
                + " replaced=\(constructionDiagnostic.replacedBeforeRequest)"
                + " unmanaged=\(constructionDiagnostic.unmanagedRequest)"
                + " attemptEntered=\(constructionDiagnostic.attemptEntered)"
                + " attemptReturned=\(constructionDiagnostic.attemptReturned)"
                + " compositionReturned=\(constructionDiagnostic.compositionReturned)"
                + " postCompositionCheck=\(constructionDiagnostic.postCompositionCheck.rawValue)"
                + " nodesReturned=\(constructionDiagnostic.nodesReturned)"
                + " newNodeCount=\(constructionDiagnostic.newNodeCount)"
                + " descriptorsReturned=\(constructionDiagnostic.descriptorRegistrationReturned)"
                + " registeredDescriptors=\(constructionDiagnostic.registeredDescriptors)"
                + " reconciliationEntered=\(constructionDiagnostic.reconciliationEntered)"
                + " reconciliationReturned=\(constructionDiagnostic.reconciliationReturned)"
                + " completed=\(constructionDiagnostic.completed)"
                + " didMutate=\(constructionDiagnostic.didMutate)"
                + " childrenCount=\(constructionDiagnostic.childrenCount)")
        host.render()
        let current = try constructionCutButton(named: "Action", in: host)
        let fresh = try constructionCutElement(for: current, in: host.runtime)
        XCTAssertTrue(fresh.invokeDefaultAction(), "\(rejection)")
        XCTAssertEqual(calls, 2, "\(rejection)")
        XCTAssertFalse(current === target)
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertEqual(calls, 2)
    }
}

@MainActor
private func constructionCutElement(for node: ViewNode, in runtime: RetainedViewRuntime) throws
    -> AccessibilityElementProjection
{
    try XCTUnwrap(AccessibilityProjection.project(runtime: runtime)?.flattened().first { $0.sourceNode === node })
}

@MainActor
private func constructionCutButton(named name: String, in host: MountedOnChangeTestHost) throws -> ViewNode {
    let element = try XCTUnwrap(
        AccessibilityProjection.project(runtime: host.runtime)?.flattened().first {
            $0.controlType == .button && $0.name == name
        })
    return try XCTUnwrap(element.sourceNode)
}
