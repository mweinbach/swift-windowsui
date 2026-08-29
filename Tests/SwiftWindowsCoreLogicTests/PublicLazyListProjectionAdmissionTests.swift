import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class PublicLazyListProjectionAdmissionTests: XCTestCase {
    func testSourceValidationReadsMetadataWithoutBuildingRows() async {
        let probe = PublicListAdmissionProbe()
        let projection = DeferredListProjection(ForEach(probe.rows) { probe.content(for: $0) })

        XCTAssertTrue(projection.validateSource(for: 0))
        XCTAssertTrue(projection.validateSource(for: 2))
        XCTAssertTrue(probe.factories.isEmpty)
        XCTAssertTrue(probe.bodies.isEmpty)
        XCTAssertTrue(probe.nodeFactories.isEmpty)

        probe.rows[0].id = 900
        XCTAssertFalse(projection.validateSource(for: 0))
        XCTAssertFalse(projection.isCurrent)
        XCTAssertTrue(projection.rowViews(for: 0).isEmpty)
        XCTAssertTrue(probe.factories.isEmpty)
    }

    func testInvalidValidationOrdinalDoesNotRevokeAnUnchangedSource() async {
        let probe = PublicListAdmissionProbe()
        let projection = DeferredListProjection(ForEach(probe.rows) { probe.content(for: $0) })

        XCTAssertFalse(projection.validateSource(for: -1))
        XCTAssertFalse(projection.validateSource(for: probe.rows.count))
        XCTAssertTrue(projection.isCurrent)
        XCTAssertTrue(projection.validateSource(for: 0))
        XCTAssertTrue(probe.factories.isEmpty)
    }

    func testReferenceCollectionShrinkRejectsBeforeAnInvalidSubscript() async {
        for explicitValidation in [false, true] {
            let probe = PublicListAdmissionProbe()
            let data = PublicListAdmissionCollection(probe.rows)
            let projection = DeferredListProjection(ForEach(data) { probe.content(for: $0) })
            data.values.removeLast()
            data.subscriptReads.removeAll()

            if explicitValidation {
                XCTAssertFalse(projection.validateSource(for: 2))
            } else {
                XCTAssertTrue(projection.rowViews(for: 2).isEmpty)
            }

            XCTAssertFalse(projection.isCurrent)
            XCTAssertTrue(data.subscriptReads.isEmpty)
            XCTAssertTrue(probe.factories.isEmpty)
        }
    }

    func testReferenceCollectionReorderRejectsTheCapturedOrdinal() async {
        let probe = PublicListAdmissionProbe()
        let data = PublicListAdmissionCollection(probe.rows)
        let projection = DeferredListProjection(ForEach(data) { probe.content(for: $0) })
        data.values.swapAt(0, 1)

        XCTAssertFalse(projection.validateSource(for: 0))
        XCTAssertFalse(projection.isCurrent)
        XCTAssertTrue(probe.factories.isEmpty)
    }

    func testIDChangedByCustomBodyRejectsBeforeItsNodeFactory() async throws {
        try assertRejectedSourceMutation(at: .body, expectedNodeFactories: [])
    }

    func testIDChangedByCustomMakeComponentRejectsBeforeItsNodeFactory() async throws {
        try assertRejectedSourceMutation(at: .component, expectedNodeFactories: [])
    }

    func testIDChangedByNodeFactoryRejectsBeforePhysicalAdoption() async throws {
        try assertRejectedSourceMutation(at: .node, expectedNodeFactories: [0])
    }

    func testUnchangedSourceRemainsValidAfterChildStatePublication() async throws {
        for builder in [false, true] {
            let probe = PublicListAdmissionProbe()
            let host = MountedLazyListTestHost { publicAdmissionList(probe, builder: builder) }
            defer { host.close() }
            let adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)

            XCTAssertNotNil(host.layout())

            XCTAssertGreaterThan(adapter.mountedRecordCount, 0)
            XCTAssertNotNil(host.find("public.admission.0"))
            XCTAssertFalse(probe.stateValues.isEmpty)
            XCTAssertTrue(probe.stateValues.allSatisfy { $0 == 17 })
        }
    }

    func testPostBodyValidationStopsAfterReentrantCollectionGetter() async throws {
        let probe = PublicListAdmissionProbe()
        let data = PublicListAdmissionCollection(probe.rows)
        let host = MountedLazyListTestHost { List(data) { probe.content(for: $0) } }
        defer { host.close() }
        var readsBeforeClose: [Int] = []
        probe.onBody = { [weak host] in
            readsBeforeClose = data.subscriptReads
            data.onCount = { [weak host] in host?.close() }
        }

        _ = host.layout()

        XCTAssertTrue(host.isClosed)
        XCTAssertEqual(data.subscriptReads, readsBeforeClose)
        XCTAssertEqual(probe.factories, [0])
        XCTAssertTrue(probe.nodeFactories.isEmpty)
        XCTAssertNil(host.find("public.admission.0"))
    }

    private func assertRejectedSourceMutation(
        at phase: PublicListAdmissionPhase, expectedNodeFactories: [Int],
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for builder in [false, true] {
            let probe = PublicListAdmissionProbe()
            probe.mutationPhase = phase
            let host = MountedLazyListTestHost { publicAdmissionList(probe, builder: builder) }
            defer { host.close() }
            let list = try host.list(file: file, line: line)
            let adapter = try XCTUnwrap(list.retainedLazyListAdapter, file: file, line: line)
            XCTAssertTrue(probe.factories.isEmpty, file: file, line: line)

            _ = host.layout()

            XCTAssertEqual(probe.rows[0].id, 10_000, file: file, line: line)
            XCTAssertEqual(probe.factories, [0], file: file, line: line)
            XCTAssertEqual(probe.bodies, [0], file: file, line: line)
            XCTAssertEqual(probe.nodeFactories, expectedNodeFactories, file: file, line: line)
            XCTAssertEqual(adapter.mountedRecordCount, 0, file: file, line: line)
            XCTAssertTrue(list.children.isEmpty, file: file, line: line)
            XCTAssertNil(host.find("public.admission.0"), file: file, line: line)

            // Rejected identity is not a zero-leaf success and cannot later
            // enter a fresh factory through the same published descriptor.
            _ = host.layout()
            XCTAssertEqual(probe.factories, [0], file: file, line: line)
            XCTAssertEqual(adapter.mountedRecordCount, 0, file: file, line: line)
        }
    }
}

private enum PublicListAdmissionPhase: Equatable {
    case body, component, node
}

private final class PublicListAdmissionModel: Identifiable {
    var id: Int
    init(id: Int) { self.id = id }
}

/// Reference-backed RandomAccessCollection is a legal public List input.
/// Its contents can change without replacing the captured collection value.
private final class PublicListAdmissionCollection: RandomAccessCollection {
    typealias Index = Int
    var values: [PublicListAdmissionModel]
    var subscriptReads: [Int] = []
    var onCount: (() -> Void)?

    init(_ values: [PublicListAdmissionModel]) { self.values = values }
    var startIndex: Int { 0 }
    var endIndex: Int { values.count }
    var count: Int {
        onCount?()
        return values.count
    }
    subscript(index: Int) -> PublicListAdmissionModel {
        subscriptReads.append(index)
        return values[index]
    }
    func index(after index: Int) -> Int { index + 1 }
    func index(before index: Int) -> Int { index - 1 }
    func index(_ index: Int, offsetBy distance: Int) -> Int { index + distance }
    func distance(from start: Int, to end: Int) -> Int { end - start }
}

@MainActor
private final class PublicListAdmissionProbe {
    let rows = (0..<3).map { PublicListAdmissionModel(id: $0) }
    var mutationPhase: PublicListAdmissionPhase?
    var factories: [Int] = []
    var bodies: [Int] = []
    var components: [Int] = []
    var nodeFactories: [Int] = []
    var stateValues: [Int] = []
    var onBody: (() -> Void)?

    func content(for model: PublicListAdmissionModel) -> [AnyView] {
        let declaredID = model.id
        factories.append(declaredID)
        return [AnyView(PublicListAdmissionBodyRow(model: model, declaredID: declaredID, probe: self))]
    }

    func mutate(_ model: PublicListAdmissionModel, declaredID: Int, during phase: PublicListAdmissionPhase) {
        if mutationPhase == phase { model.id = declaredID + 10_000 }
    }
}

@MainActor
private struct PublicListAdmissionBodyRow: View {
    @State private var value = 17
    let model: PublicListAdmissionModel
    let declaredID: Int
    let probe: PublicListAdmissionProbe

    init(model: PublicListAdmissionModel, declaredID: Int, probe: PublicListAdmissionProbe) {
        self.model = model
        self.declaredID = declaredID
        self.probe = probe
    }

    var body: some View {
        probe.bodies.append(declaredID)
        probe.stateValues.append(value)
        probe.mutate(model, declaredID: declaredID, during: .body)
        probe.onBody?()
        return PublicListAdmissionComponentRow(model: model, declaredID: declaredID, probe: probe)
    }
}

@MainActor
private struct PublicListAdmissionComponentRow: View {
    typealias Body = Never
    let model: PublicListAdmissionModel
    let declaredID: Int
    let probe: PublicListAdmissionProbe

    var body: Never { fatalError("Component fixture has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        probe.components.append(declaredID)
        probe.mutate(model, declaredID: declaredID, during: .component)
        return Component { _ in
            probe.nodeFactories.append(declaredID)
            probe.mutate(model, declaredID: declaredID, during: .node)
            let node = Controls.panel(preferredSize: Size(width: 100, height: 24), isHitTestVisible: false)
            node.accessibilityIdentifier = "public.admission.\(declaredID)"
            return node
        }
    }
}

@MainActor
@ViewBuilder
private func publicAdmissionList(_ probe: PublicListAdmissionProbe, builder: Bool) -> some View {
    if builder {
        List { ForEach(probe.rows) { probe.content(for: $0) } }
    } else {
        List(probe.rows) { probe.content(for: $0) }
    }
}
