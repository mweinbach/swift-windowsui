import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewThatFitsNamespaceConstructionAdmissionTests: XCTestCase {
    func testBoundaryProofRotationStopsTheFollowingObjectFactoryAndBodyUntilANewRootRequest() async throws {
        let probe = CandidateConstructionAdmissionProbe()
        let host = MountedOnChangeTestHost {
            probe.rootBuilds += 1
            return AnyView(
                ViewThatFits(in: .horizontal) {
                    CandidateConstructionAdmissionView(version: probe.version, probe: probe)
                        .id(probe.version)
                })
        }
        defer { host.close() }
        host.render()
        XCTAssertEqual(probe.rootBuilds, 1)
        XCTAssertEqual(probe.events, ["update:0", "factory:0", "body:0"])
        let originalOwner = try XCTUnwrap(probe.latestOwner)
        let originalValueNode = try constructionAdmissionValueNode(host)
        XCTAssertEqual(originalValueNode.text, "0")
        XCTAssertTrue(originalOwner.isLive)

        let boundaries = constructionAdmissionDescendants(host.runtime.root).filter {
            if case .viewThatFits? = $0.selectedContentRole { return true }
            return false
        }
        XCTAssertEqual(boundaries.count, 1)
        let boundary = try XCTUnwrap(boundaries.first)
        XCTAssertFalse(boundary === host.runtime.root)
        // An accepted boundary must already own its real activity storage.
        // Creating otherwise-absent storage would make the rotation vacuous.
        let storage = try XCTUnwrap(boundary.retainedLazyListActivityStorage)
        let originalAttachment = storage.captureActualAttachment(of: boundary, in: host.runtime)
        XCTAssertTrue(originalAttachment.isAttached)
        probe.storage = storage

        probe.version = 1
        probe.rotatesBoundary = true
        host.reload()
        XCTAssertEqual(probe.rootBuilds, 2)
        XCTAssertEqual(probe.events, ["update:0", "factory:0", "body:0", "update:1"])
        XCTAssertEqual(probe.rotationCount, 1)
        XCTAssertEqual(probe.missingPrerequisites, 0)
        XCTAssertEqual(
            try XCTUnwrap(probe.beforeRotation),
            CandidateConstructionAdmissionObservation(descriptor: true, candidate: true, epoch: true))
        XCTAssertEqual(
            try XCTUnwrap(probe.afterRotation),
            CandidateConstructionAdmissionObservation(descriptor: true, candidate: false, epoch: true))
        XCTAssertFalse(originalAttachment.isAttached)
        host.render()
        XCTAssertEqual(probe.rootBuilds, 2)
        XCTAssertEqual(probe.events, ["update:0", "factory:0", "body:0", "update:1"])
        XCTAssertEqual(probe.rotationCount, 1)
        XCTAssertTrue(try constructionAdmissionValueNode(host) === originalValueNode)
        XCTAssertEqual(originalValueNode.text, "0")
        XCTAssertTrue(originalOwner.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: originalOwner.identity) === originalOwner)
        XCTAssertNil(host.coordinator.latestInstallationError)

        // This is a separately requested build against the now-current physical
        // boundary; the abandoned request must not refresh its own token.
        probe.rotatesBoundary = false
        host.reload()
        host.render()
        XCTAssertEqual(probe.rootBuilds, 3)
        XCTAssertEqual(
            probe.events,
            ["update:0", "factory:0", "body:0", "update:1", "update:1", "factory:1", "body:1"])
        XCTAssertEqual(probe.rotationCount, 1)
        XCTAssertEqual(probe.missingPrerequisites, 0)
        XCTAssertEqual(try constructionAdmissionValueNode(host).text, "1")
        let replacementOwner = try XCTUnwrap(probe.latestOwner)
        XCTAssertFalse(replacementOwner === originalOwner)
        XCTAssertNotEqual(replacementOwner.generation, originalOwner.generation)
        XCTAssertTrue(replacementOwner.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: replacementOwner.identity) === replacementOwner)
        XCTAssertFalse(originalOwner.isLive)
        XCTAssertNil(host.coordinator.registry.owner(at: originalOwner.identity))
        XCTAssertNil(host.coordinator.latestInstallationError)
    }
}

private struct CandidateConstructionAdmissionObservation: Equatable {
    let descriptor: Bool
    let candidate: Bool
    let epoch: Bool
}

@MainActor
private final class CandidateConstructionAdmissionProbe {
    var version = 0
    var rootBuilds = 0
    var events: [String] = []
    var rotatesBoundary = false
    var rotationCount = 0
    var missingPrerequisites = 0
    var storage: RetainedLazyListNodeActivityStorage?
    var beforeRotation: CandidateConstructionAdmissionObservation?
    var afterRotation: CandidateConstructionAdmissionObservation?
    var latestOwner: StateMountOwner?

    func update(version: Int) {
        events.append("update:\(version)")
        guard rotatesBoundary else { return }
        guard let storage, let context = ViewBuildContextScope.current,
            let descriptor = context.viewIdentity.descriptorComponent,
            let candidate = context.viewIdentity.candidateConstruction,
            let owner = context.viewIdentity.installedOwner,
            let epoch = context.viewIdentity.installedEpoch
        else {
            missingPrerequisites += 1
            return
        }
        beforeRotation = CandidateConstructionAdmissionObservation(
            descriptor: descriptor.canConstruct, candidate: candidate.canConstruct,
            epoch: owner.installationEpoch === epoch)
        storage.revokeAttachment()
        rotationCount += 1
        // Observe the same original descriptor, token, owner and epoch here.
        // These reads neither adopt membership nor request another build.
        afterRotation = CandidateConstructionAdmissionObservation(
            descriptor: descriptor.canConstruct, candidate: candidate.canConstruct,
            epoch: owner.installationEpoch === epoch)
    }

    func makeObject(version: Int) -> CandidateConstructionAdmissionObject {
        events.append("factory:\(version)")
        return CandidateConstructionAdmissionObject(version: version)
    }

    func recordBody(version: Int) {
        events.append("body:\(version)")
        latestOwner = ViewBuildContextScope.current?.viewIdentity.installedOwner
    }
}

@MainActor
private struct CandidateConstructionAdmissionRotator: DynamicProperty {
    let version: Int
    let probe: CandidateConstructionAdmissionProbe

    nonisolated mutating func update() {
        MainActor.assumeIsolated { probe.update(version: version) }
    }
}

@MainActor
private final class CandidateConstructionAdmissionObject: ObservableObject {
    let version: Int

    init(version: Int) { self.version = version }
}

@MainActor
private struct CandidateConstructionAdmissionView: View {
    // Stored declaration order is the test boundary: update must stop before
    // installing the following StateObject and invoking its deferred factory.
    private var rotator: CandidateConstructionAdmissionRotator
    @StateObject private var object: CandidateConstructionAdmissionObject
    private let probe: CandidateConstructionAdmissionProbe

    init(version: Int, probe: CandidateConstructionAdmissionProbe) {
        rotator = CandidateConstructionAdmissionRotator(version: version, probe: probe)
        _object = StateObject(wrappedValue: probe.makeObject(version: version))
        self.probe = probe
    }

    var body: some View {
        let installed = object
        probe.recordBody(version: installed.version)
        return Text(String(installed.version))
            .accessibilityIdentifier("candidate.construction.admission.value")
    }
}

@MainActor
private func constructionAdmissionValueNode(
    _ host: MountedOnChangeTestHost, file: StaticString = #filePath, line: UInt = #line
) throws -> ViewNode {
    let matches = constructionAdmissionDescendants(host.runtime.root).filter {
        $0.accessibilityIdentifier == "candidate.construction.admission.value"
    }
    XCTAssertEqual(matches.count, 1, file: file, line: line)
    return try XCTUnwrap(matches.first, file: file, line: line)
}

@MainActor
private func constructionAdmissionDescendants(_ node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap(constructionAdmissionDescendants)
}
