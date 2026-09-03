import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class GeometryReaderEpochLifetimeTests: XCTestCase {
    func testAcceptedReaderReleasesEpochAndCapturedContextCannotAuthorizeNextBuild() async throws {
        let probe = GeometryReaderEpochLifetimeProbe()
        let host = MountedLazyListTestHost(size: Size(width: 200, height: 100)) {
            GeometryReader { _ in GeometryReaderEpochLifetimeContent(probe: probe) }
                .frame(width: 120, height: 30)
        }
        defer { host.close() }
        for _ in 0..<16 {
            host.render()
            if !host.runtime.isDirty { break }
        }
        XCTAssertFalse(host.runtime.isDirty)
        let reader = try XCTUnwrap(host.nodes.first { $0.geometryReaderBuild != nil })
        XCTAssertNotNil(reader.retainedSubtreeBuildLease)
        XCTAssertEqual(reader.geometryReaderBuiltSize, reader.resolvedFrame.size)
        probe.runtime = host.runtime

        // Force one ordinary deferred-reader rebuild. No keyboard or UIA
        // request is needed to reproduce the escaped installation receipt.
        probe.revision = 1
        reader.geometryReaderBuiltSize = .zero
        host.runtime.setRootSize(IntSize(width: 210, height: 100))
        XCTAssertNotNil(host.layout())

        XCTAssertEqual(probe.bodyRevisions, [1])
        XCTAssertEqual(probe.committedEpochs, [true])
        XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
        XCTAssertNil(probe.epoch)
        XCTAssertNil(probe.capturedContext?.viewIdentity.installedEpoch)
        XCTAssertNotNil(probe.capturedContext?.viewIdentity.installedOwner)
        XCTAssertNotNil(probe.capturedContext?.viewIdentity.descriptorComponent)
        XCTAssertNotNil(reader.geometryReaderBuild)
        XCTAssertTrue(host.contains(reader))
        XCTAssertTrue(host.nodes.contains { $0.text == "Reader 1: 41" })

        // The stale context remains alive while the surviving State binding
        // triggers a fresh build. Its expired epoch must grant no authority.
        let binding = try XCTUnwrap(probe.binding)
        probe.revision = 2
        binding.wrappedValue = 87
        XCTAssertNotNil(host.layout())

        XCTAssertEqual(probe.staleContextAudits, 1)
        XCTAssertEqual(probe.staleDelegateAcceptances, 0)
        XCTAssertEqual(probe.staleRootFactoryCalls, 0)
        XCTAssertTrue(probe.bodyRevisions.contains(2))
        XCTAssertTrue(probe.committedEpochs.allSatisfy { $0 == true })
        XCTAssertEqual(binding.wrappedValue, 87)
        XCTAssertTrue(host.nodes.contains { $0.text == "Reader 2: 87" })
        XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
        XCTAssertNil(probe.epoch)
        XCTAssertNil(probe.capturedContext?.viewIdentity.installedEpoch)
        withExtendedLifetime((reader, binding, probe.capturedContext)) {}
    }
}

@MainActor
private final class GeometryReaderEpochLifetimeProbe {
    weak var runtime: RetainedViewRuntime?
    weak var epoch: StateMountEpoch?
    var capturedContext: ViewBuildContext?
    var binding: Binding<Int>?
    var revision = 0
    var bodyRevisions: [Int] = []
    var committedEpochs: [Bool?] = []
    var staleContextAudits = 0
    var staleDelegateAcceptances = 0
    var staleRootFactoryCalls = 0

    func record(binding: Binding<Int>) {
        guard revision != 0 else { return }
        guard let runtime, let context = ViewBuildContextScope.current,
            let epoch = context.viewIdentity.installedEpoch
        else {
            return XCTFail("The reader body must have an active installed State epoch")
        }
        self.epoch = epoch
        self.binding = binding
        bodyRevisions.append(revision)
        if revision == 1 {
            capturedContext = context
        } else if staleContextAudits == 0 {
            staleContextAudits += 1
            guard var stale = capturedContext, let coordinator = context.stateMountCoordinator else {
                return XCTFail("The next build must retain the original context and its coordinator")
            }
            XCTAssertNil(stale.viewIdentity.installedEpoch)
            XCTAssertNotNil(stale.viewIdentity.installedOwner)
            XCTAssertNotNil(stale.viewIdentity.descriptorComponent)
            XCTAssertNotNil(context.viewIdentity.installedEpoch)
            let accepted = coordinator.install(
                GeometryReaderEpochLifetimeContent(probe: self), context: &stale, isInstalledDelegate: true)
            if accepted != nil { staleDelegateAcceptances += 1 }
            let root = coordinator.evaluateRootContent(in: stale) {
                self.staleRootFactoryCalls += 1
                return Text("Stale context must not enter a new root factory")
            }
            guard case .unavailable = root else {
                return XCTFail("An expired installed context must not become fresh root authority")
            }
        }
        runtime.afterRetainedCallbacks { [weak self, weak epoch] in
            self?.committedEpochs.append(epoch?.didCommit)
        }
    }
}

@MainActor
private struct GeometryReaderEpochLifetimeContent: View {
    @State private var value = 41
    let probe: GeometryReaderEpochLifetimeProbe

    var body: some View {
        probe.record(binding: $value)
        return Text("Reader \(probe.revision): \(value)")
    }
}
