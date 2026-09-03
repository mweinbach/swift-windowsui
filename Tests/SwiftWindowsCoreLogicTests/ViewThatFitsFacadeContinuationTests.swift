import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewThatFitsFacadeContinuationTests: XCTestCase {
    func testOriginalCandidateTokenCannotBecomeUnscopedOnLocalReaderRebuild() async throws {
        let probe = FacadeContinuationProbe()
        let host = MountedOnChangeTestHost(size: Size(width: 600, height: 240)) {
            probe.rootBuilds += 1
            return AnyView(FacadeContinuationReturnedReader(probe: probe))
        }
        defer {
            host.close()
            probe.heldBoundary = nil
            probe.returnedReader = nil
        }

        host.render()
        let boundary = try XCTUnwrap(probe.heldBoundary)
        let reader = try XCTUnwrap(probe.returnedReader)
        let leaf = try XCTUnwrap(reader.children.first)
        let originalLease = try XCTUnwrap(reader.retainedSubtreeBuildLease)
        let originalBinding = try XCTUnwrap(probe.bindings.first)
        let parent = try XCTUnwrap(probe.parentSamples.first)
        let originalToken = try XCTUnwrap(parent.token)
        let initialBody = try XCTUnwrap(probe.geometrySamples.last)
        assertManaged(parent)
        assertManaged(initialBody)
        XCTAssertEqual(parent.tokenWasConstructible, true)
        XCTAssertEqual(initialBody.tokenWasConstructible, true)
        XCTAssertNotNil(initialBody.token)
        XCTAssertFalse(originalToken.canConstruct)
        XCTAssertEqual(boundary.selectedContentRole, .viewThatFits)
        XCTAssertNil(boundary.parent)
        XCTAssertNil(boundary.retainedLazyListRuntime)
        XCTAssertTrue(boundary.children.isEmpty)
        XCTAssertEqual(host.runtime.root.children.count, 1)
        XCTAssertTrue(host.runtime.root.children.first === reader)
        XCTAssertTrue(reader.parent === host.runtime.root)
        XCTAssertTrue(reader.retainedLazyListRuntime === host.runtime)
        XCTAssertNotNil(reader.geometryReaderBuild)
        XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 600, height: 240))
        XCTAssertEqual(reader.resolvedFrame.size, Size(width: 600, height: 240))
        XCTAssertEqual(leaf.text, "13@600")
        XCTAssertEqual(originalBinding.wrappedValue, 13)
        XCTAssertNil(host.coordinator.latestInstallationError)

        let rootBuilds = probe.rootBuilds
        let parentBuilds = probe.parentSamples.count
        let geometryBuilds = probe.geometrySamples.count
        let leafBuilds = probe.leafBuilds
        probe.seed = 37
        host.runtime.root.frame = Rect(x: 0, y: 0, width: 640, height: 240)
        host.render()

        // The public factory returned the real reader, so the host accepted its
        // ordinary ownership but never published its constructed W boundary.
        // The original nonnil token must not be erased by an unscoped renewal.
        XCTAssertEqual(probe.rootBuilds, rootBuilds)
        XCTAssertEqual(probe.parentSamples.count, parentBuilds)
        XCTAssertEqual(probe.geometrySamples.count, geometryBuilds)
        XCTAssertEqual(probe.leafBuilds, leafBuilds)
        XCTAssertTrue(host.runtime.root.children.first === reader)
        XCTAssertTrue(reader.parent === host.runtime.root)
        XCTAssertTrue(reader.retainedLazyListRuntime === host.runtime)
        XCTAssertTrue(reader.retainedSubtreeBuildLease === originalLease)
        XCTAssertTrue(reader.children.first === leaf)
        XCTAssertEqual(reader.resolvedFrame.size, Size(width: 640, height: 240))
        XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 600, height: 240))
        XCTAssertEqual(leaf.text, "13@600")
        XCTAssertFalse(originalToken.canConstruct)
        XCTAssertEqual(originalBinding.wrappedValue, 13)
        XCTAssertEqual(probe.bindings.last?.wrappedValue, 13)
        XCTAssertNil(host.coordinator.latestInstallationError)

        // Rejection of the new construction must leave the accepted store and
        // its normal invalidation path intact.
        originalBinding.wrappedValue = 17
        host.render()
        XCTAssertGreaterThan(probe.rootBuilds, rootBuilds)
        XCTAssertGreaterThan(probe.parentSamples.count, parentBuilds)
        XCTAssertGreaterThan(probe.leafBuilds, leafBuilds)
        XCTAssertEqual(originalBinding.wrappedValue, 17)
        XCTAssertEqual(probe.bindings.last?.wrappedValue, 17)
        XCTAssertTrue(host.runtime.root.children.first === reader)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testOrdinaryReaderWithNoCandidateTokenKeepsLocalFallback() async throws {
        let probe = FacadeContinuationProbe()
        let host = MountedOnChangeTestHost(size: Size(width: 600, height: 240)) {
            probe.rootBuilds += 1
            return AnyView(FacadeContinuationReader(probe: probe))
        }
        defer { host.close() }

        host.render()
        let reader = try XCTUnwrap(host.runtime.root.children.first)
        let originalBinding = try XCTUnwrap(probe.bindings.first)
        let parent = try XCTUnwrap(probe.parentSamples.first)
        let initialBody = try XCTUnwrap(probe.geometrySamples.last)
        assertManaged(parent)
        assertManaged(initialBody)
        XCTAssertNil(parent.token)
        XCTAssertNil(initialBody.token)
        XCTAssertNil(reader.selectedContentRole)
        XCTAssertNotNil(reader.geometryReaderBuild)
        XCTAssertNotNil(reader.retainedSubtreeBuildLease)
        XCTAssertTrue(reader.parent === host.runtime.root)
        XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 600, height: 240))
        XCTAssertEqual(reader.children.first?.text, "13@600")
        XCTAssertEqual(originalBinding.wrappedValue, 13)
        XCTAssertNil(host.coordinator.latestInstallationError)

        let rootBuilds = probe.rootBuilds
        let parentBuilds = probe.parentSamples.count
        let geometryBuilds = probe.geometrySamples.count
        let leafBuilds = probe.leafBuilds
        probe.seed = 37
        host.runtime.root.frame = Rect(x: 0, y: 0, width: 640, height: 240)
        host.render()

        let renewedBody = try XCTUnwrap(probe.geometrySamples.last)
        assertManaged(renewedBody)
        XCTAssertEqual(probe.rootBuilds, rootBuilds)
        XCTAssertEqual(probe.parentSamples.count, parentBuilds)
        XCTAssertGreaterThan(probe.geometrySamples.count, geometryBuilds)
        XCTAssertGreaterThan(probe.leafBuilds, leafBuilds)
        XCTAssertNil(renewedBody.token)
        XCTAssertEqual(renewedBody.size, Size(width: 640, height: 240))
        XCTAssertTrue(host.runtime.root.children.first === reader)
        XCTAssertTrue(reader.parent === host.runtime.root)
        XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 640, height: 240))
        XCTAssertEqual(reader.children.first?.text, "13@640")
        XCTAssertEqual(originalBinding.wrappedValue, 13)
        XCTAssertEqual(probe.bindings.last?.wrappedValue, 13)
        XCTAssertNil(host.coordinator.latestInstallationError)

        originalBinding.wrappedValue = 17
        host.render()
        XCTAssertGreaterThan(probe.rootBuilds, rootBuilds)
        XCTAssertEqual(originalBinding.wrappedValue, 17)
        XCTAssertEqual(probe.bindings.last?.wrappedValue, 17)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testAcceptedCandidateReaderUsesFreshContinuationAfterOriginalTokenExpires() async throws {
        let probe = FacadeContinuationProbe()
        let host = MountedOnChangeTestHost(size: Size(width: 600, height: 240)) {
            probe.rootBuilds += 1
            return AnyView(
                ViewThatFits(in: .horizontal) {
                    Color.clear.frame(width: 1_200, height: 20)
                    FacadeContinuationReader(probe: probe)
                })
        }
        defer { host.close() }

        host.render()
        let boundary = try XCTUnwrap(host.runtime.root.children.first)
        let reader = try XCTUnwrap(boundary.children.first)
        let originalBinding = try XCTUnwrap(probe.bindings.first)
        let parent = try XCTUnwrap(probe.parentSamples.first)
        let originalToken = try XCTUnwrap(parent.token)
        let initialBody = try XCTUnwrap(probe.geometrySamples.last)
        let initialSegment = try XCTUnwrap(initialBody.token)
        assertManaged(parent)
        assertManaged(initialBody)
        XCTAssertEqual(parent.tokenWasConstructible, true)
        XCTAssertEqual(initialBody.tokenWasConstructible, true)
        XCTAssertFalse(originalToken.canConstruct)
        XCTAssertFalse(initialSegment.canConstruct)
        XCTAssertEqual(boundary.selectedContentRole, .viewThatFits)
        XCTAssertTrue(boundary.parent === host.runtime.root)
        XCTAssertTrue(reader.parent === boundary)
        XCTAssertNotNil(reader.geometryReaderBuild)
        XCTAssertNotNil(reader.retainedSubtreeBuildLease)
        XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 600, height: 240))
        XCTAssertEqual(reader.children.first?.text, "13@600")
        XCTAssertEqual(originalBinding.wrappedValue, 13)
        XCTAssertNil(host.coordinator.latestInstallationError)

        let rootBuilds = probe.rootBuilds
        let parentBuilds = probe.parentSamples.count
        let geometryBuilds = probe.geometrySamples.count
        let leafBuilds = probe.leafBuilds
        probe.seed = 37
        host.runtime.root.frame = Rect(x: 0, y: 0, width: 640, height: 240)
        host.render()

        let renewedBody = try XCTUnwrap(probe.geometrySamples.last)
        let renewedSegment = try XCTUnwrap(renewedBody.token)
        assertManaged(renewedBody)
        XCTAssertEqual(probe.rootBuilds, rootBuilds)
        XCTAssertEqual(probe.parentSamples.count, parentBuilds)
        XCTAssertGreaterThan(probe.geometrySamples.count, geometryBuilds)
        XCTAssertGreaterThan(probe.leafBuilds, leafBuilds)
        XCTAssertEqual(renewedBody.tokenWasConstructible, true)
        XCTAssertEqual(renewedBody.originalParentWasConstructible, false)
        XCTAssertFalse(renewedSegment === originalToken)
        XCTAssertFalse(renewedSegment === initialSegment)
        XCTAssertFalse(originalToken.canConstruct)
        XCTAssertEqual(renewedBody.size, Size(width: 640, height: 240))
        XCTAssertTrue(host.runtime.root.children.first === boundary)
        XCTAssertTrue(boundary.children.first === reader)
        XCTAssertTrue(reader.parent === boundary)
        XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 640, height: 240))
        XCTAssertEqual(reader.children.first?.text, "13@640")
        XCTAssertEqual(originalBinding.wrappedValue, 13)
        XCTAssertEqual(probe.bindings.last?.wrappedValue, 13)
        XCTAssertNil(host.coordinator.latestInstallationError)

        originalBinding.wrappedValue = 17
        host.render()
        XCTAssertGreaterThan(probe.rootBuilds, rootBuilds)
        XCTAssertEqual(originalBinding.wrappedValue, 17)
        XCTAssertEqual(probe.bindings.last?.wrappedValue, 17)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    private func assertManaged(
        _ sample: FacadeContinuationContextSample,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(sample.hadContext, file: file, line: line)
        XCTAssertTrue(sample.hadCoordinator, file: file, line: line)
        XCTAssertTrue(sample.hadDescriptor, file: file, line: line)
        XCTAssertFalse(sample.hadLazyAttribution, file: file, line: line)
    }
}

@MainActor
private struct FacadeContinuationContextSample {
    let hadContext: Bool
    let hadCoordinator: Bool
    let hadDescriptor: Bool
    let hadLazyAttribution: Bool
    let token: RetainedOwnedCandidateConstruction?
    let tokenWasConstructible: Bool?
    let originalParentWasConstructible: Bool?
    let size: Size?

    init(size: Size? = nil, originalParent: RetainedOwnedCandidateConstruction? = nil) {
        let context = ViewBuildContextScope.current
        hadContext = context != nil
        hadCoordinator = context?.stateMountCoordinator != nil
        hadDescriptor = context?.viewIdentity.descriptorComponent != nil
        hadLazyAttribution = context?.viewIdentity.lazyList != nil
        token = context?.viewIdentity.candidateConstruction
        tokenWasConstructible = token?.canConstruct
        originalParentWasConstructible = originalParent?.canConstruct
        self.size = size
    }
}

@MainActor
private final class FacadeContinuationProbe {
    var rootBuilds = 0
    var seed = 13
    var leafBuilds = 0
    var bindings: [Binding<Int>] = []
    var parentSamples: [FacadeContinuationContextSample] = []
    var geometrySamples: [FacadeContinuationContextSample] = []
    var heldBoundary: ViewNode?
    var returnedReader: ViewNode?

    func recordParent() {
        parentSamples.append(FacadeContinuationContextSample())
    }

    func recordGeometry(_ size: Size) {
        geometrySamples.append(
            FacadeContinuationContextSample(size: size, originalParent: parentSamples.first?.token))
    }

    func recordLeaf(_ binding: Binding<Int>) {
        leafBuilds += 1
        bindings.append(binding)
    }
}

@MainActor
private struct FacadeContinuationReader: View {
    let probe: FacadeContinuationProbe

    var body: some View {
        let _ = probe.recordParent()
        GeometryReader { proxy in
            let _ = probe.recordGeometry(proxy.size)
            FacadeContinuationLeaf(seed: probe.seed, width: proxy.size.width, probe: probe)
        }
    }
}

@MainActor
private struct FacadeContinuationLeaf: View {
    @State private var value: Int
    let width: Double
    let probe: FacadeContinuationProbe

    init(seed: Int, width: Double, probe: FacadeContinuationProbe) {
        _value = State(initialValue: seed)
        self.width = width
        self.probe = probe
    }

    var body: some View {
        let current = value
        let _ = probe.recordLeaf($value)
        Text("\(current)@\(Int(width))")
    }
}

// This deliberately changes the physical result of a public Component factory.
// It constructs a public W and returns its actual reader child. Only the real
// host removes that child from its temporary parent and publishes it.
@MainActor
private struct FacadeContinuationReturnedReader: View {
    typealias Body = Never
    let probe: FacadeContinuationProbe

    var body: Never { fatalError("The component factory supplies this view") }

    func makeComponent(context: ViewBuildContext) -> Component {
        let component = AnyView(
            ViewThatFits(in: .horizontal) {
                FacadeContinuationReader(probe: probe)
            }
        ).makeComponent(context: context)
        return Component { runtime in
            let boundary = component.makeNode(runtime: runtime)
            probe.heldBoundary = boundary
            guard let reader = boundary.children.first else { return boundary }
            probe.returnedReader = reader
            return reader
        }
    }
}
