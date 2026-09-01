import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// A checked cold attachment writes node.runtime directly. Navigation owners
/// need that same accepted publication before any selection action can begin.
@MainActor
final class ManagedListNavigationPublicationTests: XCTestCase {
    func testInitialCheckedManagedAttachmentPublishesItsOriginalNavigationOwners() async throws {
        var selected: Int? = 0
        var reads = 0
        var writes: [Int?] = []
        let binding = Binding<Int?>(
            get: {
                reads += 1
                return selected
            },
            set: {
                selected = $0
                writes.append($0)
            })
        let host = MountedLazyListTestHost(size: Size(width: 260, height: 200)) {
            List(selection: binding) {
                ForEach(Array(0..<4), id: \.self) { index in
                    Text("Managed \(index)").font(.system(size: 13)).frame(height: 32).tag(index)
                }
            }
            .listStyle(.plain)
            .frame(width: 260, height: 200)
        }
        defer { host.close() }
        XCTAssertNotNil(host.layout())
        let list = try host.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        XCTAssertNotNil(adapter.managedLogicalDescriptorBinding)
        XCTAssertTrue(adapter.ownsAttachment(list))
        let scroll = try XCTUnwrap(list.parent)
        let scope = try XCTUnwrap(scroll.listNavigationOwner)
        let source = try XCTUnwrap(
            list.children.first { DeferredListRowNavigation.attached(to: $0)?.ordinal == 0 })
        let owner = try XCTUnwrap(source.listNavigationOwner)
        XCTAssertTrue(scroll.isRetainedLazyListAttached(in: host.runtime))
        XCTAssertTrue(source.isRetainedLazyListAttached(in: host.runtime))
        XCTAssertNotNil(source.onKeyDown)
        let readsBeforePreparation = reads

        let receipt = try XCTUnwrap(
            scope.prepareAction(from: owner),
            "A physically attached managed scope and row must already carry their original runtime")
        defer { receipt.cancelPreparedNavigation() }

        XCTAssertTrue(receipt.permitsBindingWrite)
        XCTAssertTrue(receipt.permitsContinuation)
        XCTAssertEqual(reads, readsBeforePreparation, "Native preparation must not read the selection binding")
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(selected, 0)
    }
}
