import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Frozen before the native visited-ID representation is implemented.
/// These oracles require the same insertion decisions, live ancestry refusal,
/// and ownership behavior; they do not measure elapsed time or allocations.
@MainActor
final class RetainedPaintAncestryPrefixTests: XCTestCase {
    func testUniquePrefixMatchesSetForShortLongAndDivergentSequences() async throws {
        let tokens = (0..<6).map { _ in PaintAncestryIdentityToken() }
        defer { withExtendedLifetime(tokens) {} }
        let ids = tokens.map(ObjectIdentifier.init)
        let buffer = try XCTUnwrap(RetainedPaintAncestryBuffer(identifiers: Array(ids[0..<3])))
        let prefix = try XCTUnwrap(buffer.prefix(startingAt: ids[0]))
        let sequences: [[ObjectIdentifier]] = [
            [], [ids[0]], [ids[0], ids[1]], [ids[0], ids[1], ids[2]],
            [ids[0], ids[1], ids[2], ids[3], ids[4]],
            [ids[3], ids[1], ids[2]], [ids[0], ids[3], ids[2]],
            [ids[0], ids[1], ids[3]], [ids[0], ids[3], ids[4], ids[5]],
        ]
        for sequence in sequences { assertAncestryInsertions(sequence, prefix: prefix) }
    }

    func testFallbackMatchesSetForRepeatedIdentifiersIncludingTheMatchedPrefix() async throws {
        let tokens = (0..<5).map { _ in PaintAncestryIdentityToken() }
        defer { withExtendedLifetime(tokens) {} }
        let ids = tokens.map(ObjectIdentifier.init)
        let buffer = try XCTUnwrap(RetainedPaintAncestryBuffer(identifiers: Array(ids[0..<3])))
        let prefix = try XCTUnwrap(buffer.prefix(startingAt: ids[0]))
        let sequences: [[ObjectIdentifier]] = [
            [ids[0], ids[0]], [ids[0], ids[1], ids[0]],
            [ids[0], ids[1], ids[2], ids[0]],
            [ids[0], ids[3], ids[0]], [ids[0], ids[3], ids[3]],
            [ids[0], ids[1], ids[3], ids[1], ids[4], ids[4]],
            [ids[3], ids[0], ids[1], ids[2], ids[0]],
        ]
        for sequence in sequences { assertAncestryInsertions(sequence, prefix: prefix) }
    }

    func testUnavailableAndInvalidPrefixesUseUnhintedSetSemantics() async throws {
        let tokens = (0..<3).map { _ in PaintAncestryIdentityToken() }
        defer { withExtendedLifetime(tokens) {} }
        let ids = tokens.map(ObjectIdentifier.init)
        XCTAssertNil(RetainedPaintAncestryBuffer(identifiers: []))
        XCTAssertNil(RetainedPaintAncestryBuffer(identifiers: [ids[0], ids[1], ids[0]]))
        let buffer = try XCTUnwrap(RetainedPaintAncestryBuffer(identifiers: [ids[0], ids[1]]))
        XCTAssertNil(buffer.prefix(startingAt: ids[2]))
        assertAncestryInsertions([ids[0], ids[1], ids[0], ids[2], ids[2]], prefix: nil)
        assertAncestryInsertions(
            [ids[0], ids[1], ids[0]], prefix: buffer.prefix(startingAt: ids[2]))

        let root = ViewNode()
        let selected = ViewNode()
        let malformed = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected)
        root.addChild(malformed)
        let runtime = RetainedViewRuntime(root: root)
        defer { retirePaintAncestryRuntime(runtime) }
        malformed.removeAllChildren()
        let domain = root.captureSelectedContentPaintDomain()
        let failedOperand = domain.captureOperand(for: malformed)
        XCTAssertNil(failedOperand)
        assertAncestryInsertions(
            [ObjectIdentifier(malformed), ObjectIdentifier(root), ObjectIdentifier(malformed)],
            prefix: failedOperand?.ancestryPrefix)
    }

    func testEveryVisitSetStartsWithIndependentStateAndTheBufferStaysImmutable() async throws {
        let tokens = (0..<4).map { _ in PaintAncestryIdentityToken() }
        defer { withExtendedLifetime(tokens) {} }
        let ids = tokens.map(ObjectIdentifier.init)
        var input = [ids[0], ids[1], ids[2]]
        let buffer = try XCTUnwrap(RetainedPaintAncestryBuffer(identifiers: input))
        let prefix = try XCTUnwrap(buffer.prefix(startingAt: ids[0]))
        input[0] = ids[3]
        XCTAssertEqual(prefix.count, 3)
        XCTAssertEqual(prefix[0], ids[0])
        XCTAssertEqual(prefix[1], ids[1])
        XCTAssertEqual(prefix[2], ids[2])
        var first = RetainedPaintAncestryVisitSet(prefix: prefix)
        var second = RetainedPaintAncestryVisitSet(prefix: prefix)
        XCTAssertTrue(first.insert(ids[0]).inserted)
        XCTAssertFalse(first.insert(ids[0]).inserted)
        XCTAssertTrue(second.insert(ids[0]).inserted)
        XCTAssertTrue(second.insert(ids[1]).inserted)
        XCTAssertTrue(first.insert(ids[1]).inserted)
        XCTAssertFalse(second.insert(ids[0]).inserted)
        assertAncestryInsertions([ids[0], ids[1], ids[2]], prefix: prefix)
    }

    func testSelectedDescendantPathPrefixStartsAtThePhysicalNode() async throws {
        let selected = ViewNode()
        let inner = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected)
        let physical = ViewNode.selectedContentBoundary(role: .viewThatFits, child: inner)
        let root = ViewNode(children: [physical])
        let runtime = RetainedViewRuntime(root: root)
        defer { retirePaintAncestryRuntime(runtime) }
        let domain = root.captureSelectedContentPaintDomain()
        let operand = try XCTUnwrap(domain.captureOperand(for: physical))
        XCTAssertTrue(operand.isCurrent)
        XCTAssertTrue(operand.physicalNode === physical)
        XCTAssertTrue(operand.selectedNode === selected)
        let prefix = try XCTUnwrap(operand.ancestryPrefix)
        XCTAssertEqual(prefix.count, 2)
        XCTAssertEqual(prefix[0], ObjectIdentifier(physical))
        XCTAssertEqual(prefix[1], ObjectIdentifier(root))
        assertAncestryInsertions([ObjectIdentifier(physical), ObjectIdentifier(root)], prefix: prefix)

        // A revoked original still contains only harmless native-ID data.
        // Reading that data must not refresh or authorize its captured path.
        physical.removeFromParent()
        root.addChild(physical)
        XCTAssertFalse(operand.isCurrent)
        let revokedPrefix = try XCTUnwrap(operand.ancestryPrefix)
        XCTAssertEqual(revokedPrefix.count, 2)
        XCTAssertEqual(revokedPrefix[0], ObjectIdentifier(physical))
        assertAncestryInsertions(
            [ObjectIdentifier(physical), ObjectIdentifier(root)], prefix: revokedPrefix)
        XCTAssertFalse(operand.isCurrent)
    }

    func testLaterCanvasMovingAnOrdinarySourceUnderSelectionRejectsItsOldScene() async throws {
        let fixture = PaintAncestrySceneFixture(initiallySelected: false)
        defer { fixture.close() }
        let root = fixture.root
        let earlier = fixture.earlier
        let canvas = fixture.canvas
        let original = try XCTUnwrap(earlier.captureSelectedContentPath(in: fixture.runtime))
        XCTAssertTrue(original.isCurrent)
        XCTAssertNil(earlier.selectedContentRole)
        var calls = 0
        var introducedBoundary: ViewNode?
        canvas.canvasDraw = { [weak root, weak earlier] _, _ in
            calls += 1
            guard calls == 1 else { return }
            guard let root, let earlier else { return XCTFail("The fixture owns both original nodes") }
            XCTAssertNotNil(earlier.cachedSceneSnapshotIdentity)
            XCTAssertTrue(original.isCurrent)
            let boundary = ViewNode.selectedContentBoundary(role: .viewThatFits, child: earlier)
            introducedBoundary = boundary
            root.addChild(boundary)
            XCTAssertTrue(earlier.parent === boundary)
            XCTAssertFalse(original.isCurrent)
        }

        _ = ScenePainter.paint(root: root, clearColor: .black, surfaceSize: Size(width: 80, height: 40))

        XCTAssertEqual(calls, 1)
        let boundary = try XCTUnwrap(introducedBoundary)
        XCTAssertTrue(boundary.parent === root)
        XCTAssertTrue(earlier.parent === boundary)
        XCTAssertFalse(original.isCurrent)
        XCTAssertTrue(root.hasDirtySubtree)
        XCTAssertNil(root.cachedSceneKey)
        XCTAssertNil(root.cachedScenePaintRange)
        XCTAssertNil(root.cachedSceneSnapshotIdentity)
        XCTAssertFalse(earlier.hasPaintedCurrentAttachment)
    }

    func testLaterCanvasCardinalityABADoesNotReviveAnOriginallySelectedCapture() async throws {
        let fixture = PaintAncestrySceneFixture(initiallySelected: true)
        defer { fixture.close() }
        let boundary = try XCTUnwrap(fixture.boundary)
        let earlier = fixture.earlier
        let original = try XCTUnwrap(boundary.captureSelectedContentPath(in: fixture.runtime))
        XCTAssertTrue(original.isCurrent)
        var calls = 0
        fixture.canvas.canvasDraw = { [weak boundary] _, _ in
            calls += 1
            guard calls == 1 else { return }
            guard let boundary else { return XCTFail("The fixture owns the selected boundary") }
            XCTAssertNotNil(earlier.cachedSceneSnapshotIdentity)
            let extra = ViewNode()
            boundary.addChild(extra)
            XCTAssertEqual(boundary.children.count, 2)
            extra.removeFromParent()
            XCTAssertEqual(boundary.children.count, 1)
            XCTAssertTrue(boundary.children.first === earlier)
            XCTAssertTrue(earlier.parent === boundary)
            // The original path was not sampled during the invalid shape.
            XCTAssertFalse(original.isCurrent)
        }

        _ = ScenePainter.paint(
            root: fixture.root, clearColor: .black, surfaceSize: Size(width: 80, height: 40))

        XCTAssertEqual(calls, 1)
        XCTAssertFalse(original.isCurrent)
        XCTAssertTrue(boundary.children.first === earlier)
        XCTAssertTrue(earlier.parent === boundary)
        XCTAssertTrue(fixture.root.hasDirtySubtree)
        XCTAssertNil(fixture.root.cachedSceneKey)
        XCTAssertNil(fixture.root.cachedScenePaintRange)
        XCTAssertNil(fixture.root.cachedSceneSnapshotIdentity)
    }

    func testScalarPrefixDoesNotRetainNodesRuntimeOrCanvasPayload() async throws {
        let observations = PaintAncestryWeakObservations()
        let prefix = try makeReleasedPaintAncestryPrefix(observations)
        XCTAssertEqual(prefix.count, 2)
        XCTAssertNil(observations.root)
        XCTAssertNil(observations.node)
        XCTAssertNil(observations.runtime)
        XCTAssertNil(observations.payload)
        assertAncestryInsertions([prefix[0], prefix[1], prefix[0]], prefix: prefix)
        withExtendedLifetime(prefix) {}
        XCTAssertNil(observations.root)
        XCTAssertNil(observations.node)
        XCTAssertNil(observations.runtime)
        XCTAssertNil(observations.payload)
    }
}

@MainActor
private func assertAncestryInsertions(
    _ sequence: [ObjectIdentifier], prefix: RetainedPaintAncestryPrefix?,
    file: StaticString = #filePath, line: UInt = #line
) {
    var expected = Set<ObjectIdentifier>()
    var actual = RetainedPaintAncestryVisitSet(prefix: prefix)
    for identifier in sequence {
        let expectedResult = expected.insert(identifier)
        let actualResult = actual.insert(identifier)
        XCTAssertEqual(actualResult.inserted, expectedResult.inserted, file: file, line: line)
        XCTAssertEqual(actualResult.memberAfterInsert, expectedResult.memberAfterInsert, file: file, line: line)
    }
}

private final class PaintAncestryIdentityToken {}
private final class PaintAncestryPayload {}

@MainActor
private final class PaintAncestryWeakObservations {
    weak var root: ViewNode?
    weak var node: ViewNode?
    weak var runtime: RetainedViewRuntime?
    weak var payload: PaintAncestryPayload?
}

@MainActor
@inline(never)
private func makeReleasedPaintAncestryPrefix(
    _ observations: PaintAncestryWeakObservations
) throws -> RetainedPaintAncestryPrefix {
    let node = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
    let root = ViewNode(children: [node])
    let runtime = RetainedViewRuntime(root: root)
    defer { retirePaintAncestryRuntime(runtime) }
    let payload = PaintAncestryPayload()
    node.canvasDraw = { [payload] _, _ in withExtendedLifetime(payload) {} }
    observations.root = root
    observations.node = node
    observations.runtime = runtime
    observations.payload = payload
    let domain = root.captureSelectedContentPaintDomain()
    let operand = try XCTUnwrap(domain.captureOperand(for: node))
    XCTAssertTrue(operand.isCurrent)
    return try XCTUnwrap(operand.ancestryPrefix)
}

@MainActor
private final class PaintAncestrySceneFixture {
    let earlier: ViewNode
    let canvas: ViewNode
    let boundary: ViewNode?
    let root: ViewNode
    let runtime: RetainedViewRuntime

    init(initiallySelected: Bool) {
        let earlier = ViewNode(frame: Rect(x: 8, y: 8, width: 16, height: 16), backgroundColor: .white)
        let canvas = ViewNode(frame: Rect(x: 40, y: 0, width: 10, height: 10))
        let boundary =
            initiallySelected
            ? ViewNode.selectedContentBoundary(role: .viewThatFits, child: earlier) : nil
        let root = ViewNode(children: [boundary ?? earlier, canvas])
        let runtime = RetainedViewRuntime(root: root)
        self.earlier = earlier
        self.canvas = canvas
        self.boundary = boundary
        self.root = root
        self.runtime = runtime
        runtime.setRootSize(IntSize(width: 80, height: 40))
        _ = runtime.renderFrame()
        XCTAssertFalse(runtime.isDirty)
        XCTAssertNil(root.cachedSceneKey)
        XCTAssertNil(root.cachedSceneSnapshotIdentity)
        XCTAssertEqual(earlier.resolvedFrame, Rect(x: 8, y: 8, width: 16, height: 16))
    }

    func close() {
        canvas.canvasDraw = nil
        retirePaintAncestryRuntime(runtime)
    }
}

@MainActor
private func retirePaintAncestryRuntime(_ runtime: RetainedViewRuntime) {
    runtime.stopRenderLifecycleCallbacks()
    runtime.cancelRenderLifecycleTasks()
    runtime.root.removeAllChildren()
}
