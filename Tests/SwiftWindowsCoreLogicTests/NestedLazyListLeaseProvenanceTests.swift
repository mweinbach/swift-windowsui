import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class NestedLazyListLeaseProvenanceTests: XCTestCase {
    func testNestedPublicListDoesNotClaimGeometryReaderAnchors() async throws {
        let probe = NestedListLeaseProbe()
        let host = MountedLazyListTestHost(size: Size(width: 200, height: 200)) {
            nestedListLeaseContent(probe, usesReader: false)
        }
        defer {
            host.close()
            probe.capture = nil
        }
        XCTAssertNotNil(host.layout())
        XCTAssertNotNil(host.find("nested.list.lease.counter"))
        XCTAssertEqual(host.lists.count, 2)
        let original = try XCTUnwrap(probe.capture)
        try assertListLeases(in: host)
        XCTAssertFalse(host.nodes.contains { $0.geometryReaderBuild != nil })

        original.value.wrappedValue = 41
        XCTAssertNotNil(host.layout())

        let continued = try XCTUnwrap(probe.capture)
        XCTAssertTrue(continued.owner === original.owner)
        XCTAssertEqual(continued.value.wrappedValue, 41)
        try assertListLeases(in: host)
    }

    func testGeometryReaderInsideNestedPublicListKeepsItsOwnRegion() async throws {
        let probe = NestedListLeaseProbe()
        let host = MountedLazyListTestHost(size: Size(width: 200, height: 200)) {
            nestedListLeaseContent(probe, usesReader: true)
        }
        defer {
            host.close()
            probe.capture = nil
        }
        XCTAssertNotNil(host.layout())
        let reader = try XCTUnwrap(host.nodes.first { $0.geometryReaderBuild != nil })
        let anchor = try XCTUnwrap(reader.retainedLazyListActivityStorage?.deferredSubtreeAnchor)
        XCTAssertTrue(anchor.isCurrent)
        XCTAssertNotNil(host.find("nested.list.lease.counter"))
        let original = try XCTUnwrap(probe.capture)
        try assertListLeases(in: host)

        original.value.wrappedValue = 57
        XCTAssertNotNil(host.layout())

        let continued = try XCTUnwrap(probe.capture)
        XCTAssertTrue(continued.owner === original.owner)
        XCTAssertEqual(continued.value.wrappedValue, 57)
        let retainedReader = try XCTUnwrap(host.nodes.first { $0.geometryReaderBuild != nil })
        XCTAssertTrue(retainedReader === reader)
        XCTAssertTrue(try XCTUnwrap(retainedReader.retainedLazyListActivityStorage?.deferredSubtreeAnchor).isCurrent)
        try assertListLeases(in: host)
    }

    private func assertListLeases(
        in host: MountedLazyListTestHost, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(host.lists.count, 2, file: file, line: line)
        for (index, list) in host.lists.enumerated() {
            XCTAssertNotNil(list.retainedSubtreeBuildLease, file: file, line: line)
            XCTAssertNil(list.retainedLazyListActivityStorage?.deferredSubtreeAnchor, file: file, line: line)
            XCTAssertNil(list.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor, file: file, line: line)
            let adapter = try XCTUnwrap(list.retainedLazyListAdapter, file: file, line: line)
            XCTAssertEqual(adapter.mountedRecordCount, 1, file: file, line: line)
            XCTAssertTrue(
                adapter.materializedRowActivities.allSatisfy { $0.physical.state == .active }, file: file, line: line)
            try host.assertCommittedDescriptor(index: index, file: file, line: line)
        }
    }
}

@MainActor
private struct NestedListLeaseCapture {
    let owner: StateMountOwner
    let value: Binding<Int>
}

@MainActor
private final class NestedListLeaseProbe {
    var capture: NestedListLeaseCapture?

    func record(_ value: Binding<Int>) {
        guard let owner = ViewBuildContextScope.current?.viewIdentity.installedOwner else {
            return XCTFail("The nested counter must install an owner")
        }
        capture = NestedListLeaseCapture(owner: owner, value: value)
    }
}

@MainActor
private struct NestedListLeaseCounter: View {
    @State private var value = 10
    let probe: NestedListLeaseProbe

    var body: some View {
        probe.record($value)
        return Color.blue.frame(height: 20).accessibilityIdentifier("nested.list.lease.counter")
    }
}

@MainActor
private func nestedListLeaseContent(_ probe: NestedListLeaseProbe, usesReader: Bool) -> some View {
    List([0], id: \.self) { _ in
        List([0], id: \.self) { _ in
            if usesReader {
                GeometryReader { _ in NestedListLeaseCounter(probe: probe) }
                    .frame(height: 40)
            } else {
                NestedListLeaseCounter(probe: probe).frame(height: 40)
            }
        }
        .listStyle(.plain)
        .frame(width: 160, height: 120)
    }
    .listStyle(.plain)
}
