import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewThatFitsNamespaceIdentityAdmissionTests: XCTestCase {
    func testBoundaryProofRotationInsideOwnedCellIdentityLookupStopsTheFactoryAndBodyUntilANewRootRequest() async throws
    {
        let probe = CandidateIdentityAdmissionProbe()
        let host = MountedOnChangeTestHost {
            probe.rootBuilds += 1
            return AnyView(
                ViewThatFits(in: .horizontal) {
                    CandidateIdentityAdmissionView(version: probe.version, probe: probe)
                        .id(CandidateIdentityAdmissionKey(version: probe.version, probe: probe))
                })
        }
        defer {
            probe.onNextIdentityHash = nil
            host.close()
        }
        host.render()
        XCTAssertEqual(probe.rootBuilds, 1)
        XCTAssertEqual(probe.events, ["update:0", "factory:0", "body:0"])
        let originalOwner = try XCTUnwrap(probe.latestOwner)
        let originalValueNode = try identityAdmissionValueNode(host)
        XCTAssertEqual(originalValueNode.text, "0")
        XCTAssertTrue(originalOwner.isLive)
        XCTAssertNil(probe.onNextIdentityHash)

        let boundaries = identityAdmissionDescendants(host.runtime.root).filter {
            if case .viewThatFits? = $0.selectedContentRole { return true }
            return false
        }
        XCTAssertEqual(boundaries.count, 1)
        let boundary = try XCTUnwrap(boundaries.first)
        XCTAssertFalse(boundary === host.runtime.root)
        // Use only the accepted boundary's existing storage. Allocating missing
        // storage here would not prove that an original accepted proof expired.
        let storage = try XCTUnwrap(boundary.retainedLazyListActivityStorage)
        let originalAttachment = storage.captureActualAttachment(of: boundary, in: host.runtime)
        XCTAssertTrue(originalAttachment.isAttached)
        probe.storage = storage
        probe.originalAttachment = originalAttachment

        probe.version = 1
        probe.armsBoundaryRotation = true
        host.reload()
        XCTAssertEqual(probe.rootBuilds, 2)
        XCTAssertEqual(probe.events, ["update:0", "factory:0", "body:0", "update:1", "hash:1"])
        XCTAssertEqual(probe.armCount, 1)
        XCTAssertEqual(probe.rotationCount, 1)
        XCTAssertEqual(probe.missingPrerequisites, 0)
        XCTAssertNil(probe.onNextIdentityHash)
        XCTAssertEqual(
            try XCTUnwrap(probe.beforeRotation),
            CandidateIdentityAdmissionObservation(descriptor: true, candidate: true, epoch: true, actual: true))
        XCTAssertEqual(
            try XCTUnwrap(probe.afterRotation),
            CandidateIdentityAdmissionObservation(descriptor: true, candidate: false, epoch: true, actual: false))
        XCTAssertFalse(originalAttachment.isAttached)
        host.render()
        XCTAssertEqual(probe.rootBuilds, 2)
        XCTAssertEqual(probe.events, ["update:0", "factory:0", "body:0", "update:1", "hash:1"])
        XCTAssertEqual(probe.armCount, 1)
        XCTAssertEqual(probe.rotationCount, 1)
        XCTAssertTrue(try identityAdmissionValueNode(host) === originalValueNode)
        XCTAssertEqual(originalValueNode.text, "0")
        XCTAssertTrue(originalOwner.isLive)
        XCTAssertTrue(host.coordinator.registry.owner(at: originalOwner.identity) === originalOwner)
        XCTAssertNil(host.coordinator.latestInstallationError)

        // Only a separately requested root build may qualify the boundary's new
        // proof. The abandoned request must neither refresh itself nor retry.
        probe.armsBoundaryRotation = false
        host.reload()
        host.render()
        XCTAssertEqual(probe.rootBuilds, 3)
        XCTAssertEqual(
            probe.events,
            ["update:0", "factory:0", "body:0", "update:1", "hash:1", "update:1", "factory:1", "body:1"])
        XCTAssertEqual(probe.armCount, 1)
        XCTAssertEqual(probe.rotationCount, 1)
        XCTAssertEqual(probe.missingPrerequisites, 0)
        XCTAssertNil(probe.onNextIdentityHash)
        XCTAssertEqual(try identityAdmissionValueNode(host).text, "1")
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

private struct CandidateIdentityAdmissionObservation: Equatable {
    let descriptor: Bool
    let candidate: Bool
    let epoch: Bool
    let actual: Bool
}

@MainActor
private final class CandidateIdentityAdmissionProbe {
    var version = 0
    var rootBuilds = 0
    var events: [String] = []
    var armsBoundaryRotation = false
    var armCount = 0
    var rotationCount = 0
    var missingPrerequisites = 0
    var storage: RetainedLazyListNodeActivityStorage?
    var originalAttachment: RetainedLazyListActualAttachment?
    var onNextIdentityHash: (@MainActor (Int) -> Void)?
    var beforeRotation: CandidateIdentityAdmissionObservation?
    var afterRotation: CandidateIdentityAdmissionObservation?
    weak var latestOwner: StateMountOwner?

    func update(version: Int) {
        events.append("update:\(version)")
        guard armsBoundaryRotation else { return }
        guard version == 1, onNextIdentityHash == nil, let storage, let originalAttachment,
            let context = ViewBuildContextScope.current,
            let descriptor = context.viewIdentity.descriptorComponent,
            let candidate = context.viewIdentity.candidateConstruction,
            let owner = context.viewIdentity.installedOwner,
            let epoch = context.viewIdentity.installedEpoch
        else {
            missingPrerequisites += 1
            return
        }
        // The update only arms the callback. Earlier owner-acquisition hashes
        // have already run, and the token is still current on return from update.
        armCount += 1
        onNextIdentityHash = { [weak self] hashedVersion in
            guard let self else { return }
            self.events.append("hash:\(hashedVersion)")
            self.beforeRotation = CandidateIdentityAdmissionObservation(
                descriptor: descriptor.canConstruct, candidate: candidate.canConstruct,
                epoch: owner.installationEpoch === epoch, actual: originalAttachment.isAttached)
            storage.revokeAttachment()
            self.rotationCount += 1
            // Read the same descriptor, token, owner, epoch and original actual.
            // No recapture, adoption, or build request occurs inside this hook.
            self.afterRotation = CandidateIdentityAdmissionObservation(
                descriptor: descriptor.canConstruct, candidate: candidate.canConstruct,
                epoch: owner.installationEpoch === epoch, actual: originalAttachment.isAttached)
        }
    }

    func identityHash(version: Int) {
        guard let callback = onNextIdentityHash else { return }
        // Consume before entering the callback; incidental later key operations
        // cannot rotate again or replace the original proof under observation.
        onNextIdentityHash = nil
        callback(version)
    }

    func makeObject(version: Int) -> CandidateIdentityAdmissionObject {
        events.append("factory:\(version)")
        return CandidateIdentityAdmissionObject(version: version)
    }

    func recordBody(version: Int) {
        events.append("body:\(version)")
        latestOwner = ViewBuildContextScope.current?.viewIdentity.installedOwner
    }
}

private struct CandidateIdentityAdmissionKey: Hashable {
    let version: Int
    let probe: CandidateIdentityAdmissionProbe

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.version == rhs.version }

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated { probe.identityHash(version: version) }
        hasher.combine(version)
    }
}

@MainActor
private struct CandidateIdentityAdmissionArmer: DynamicProperty {
    let version: Int
    let probe: CandidateIdentityAdmissionProbe

    nonisolated mutating func update() {
        MainActor.assumeIsolated { probe.update(version: version) }
    }
}

@MainActor
private final class CandidateIdentityAdmissionObject: ObservableObject {
    let version: Int

    init(version: Int) { self.version = version }
}

@MainActor
private struct CandidateIdentityAdmissionView: View {
    // This declaration order arms the next authored identity hash before the
    // following StateObject enters its owned-cell lookup and deferred factory.
    private var armer: CandidateIdentityAdmissionArmer
    @StateObject private var object: CandidateIdentityAdmissionObject
    private let probe: CandidateIdentityAdmissionProbe

    init(version: Int, probe: CandidateIdentityAdmissionProbe) {
        armer = CandidateIdentityAdmissionArmer(version: version, probe: probe)
        _object = StateObject(wrappedValue: probe.makeObject(version: version))
        self.probe = probe
    }

    var body: some View {
        let installed = object
        probe.recordBody(version: installed.version)
        return Text(String(installed.version))
            .accessibilityIdentifier("candidate.identity.admission.value")
    }
}

@MainActor
private func identityAdmissionValueNode(
    _ host: MountedOnChangeTestHost, file: StaticString = #filePath, line: UInt = #line
) throws -> ViewNode {
    let matches = identityAdmissionDescendants(host.runtime.root).filter {
        $0.accessibilityIdentifier == "candidate.identity.admission.value"
    }
    XCTAssertEqual(matches.count, 1, file: file, line: line)
    return try XCTUnwrap(matches.first, file: file, line: line)
}

@MainActor
private func identityAdmissionDescendants(_ node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap(identityAdmissionDescendants)
}
