import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Diagnostic companion to the original immediate keyboard navigation regression.
/// Passive phase output does not change the fixture, budgets, or assertions.
/// This test records evidence; it does not implement a navigation fix.
@MainActor
final class ListKeyboardPhaseTests: XCTestCase {
    private static let viewport = IntSize(width: 260, height: 200)

    private func makeManagedRuntime<V: View>(
        _ view: V, size: IntSize = ListKeyboardPhaseTests.viewport
    ) -> MountedLazyListTestHost {
        MountedLazyListTestHost(size: Size(width: Double(size.width), height: Double(size.height))) {
            view.frame(width: Double(size.width), height: Double(size.height))
        }
    }

    private func row(_ index: Int, height: Double = 24) -> some View {
        Text("ROW \(index)")
            .frame(width: 220, height: height)
            .accessibilityIdentifier("virtual-row-\(index)")
    }

    @discardableResult
    private func settle(
        _ host: MountedLazyListTestHost, file: StaticString = #filePath, line: UInt = #line
    ) throws -> GPUIScene {
        for _ in 0..<16 {
            let scene = host.runtime.renderScene(at: 1)
            if !host.runtime.isDirty { return scene }
        }
        return try XCTUnwrap(
            nil as GPUIScene?, "Expected ordinary bounded List work to settle within 16 renders", file: file, line: line
        )
    }

    func testKeyboardSelectionCanRevealADeferredFarAwayRow() async throws {
        var selection: Int? = 0
        let binding = Binding<Int?>(get: { selection }, set: { selection = $0 })
        let result = makeManagedRuntime(
            List(0..<1_000, id: \.self, selection: binding) { index in self.row(index) }
        )
        defer { result.close() }
        try settle(result)
        let source = try result.rowRoot("virtual-row-0")
        let sourceKeyDown = try XCTUnwrap(source.onKeyDown)
        XCTAssertNil(result.find("virtual-row-900"))
        XCTAssertNil(result.find("virtual-row-899"))

        // Source 0 is the real attached handler. Selection metadata, not an
        // imaginary mounted row 899, selects the distant next logical record.
        selection = 899
        // Begin passive recording only for the original first key press.
        result.runtime.recordsLazyListUIAPhasesForTesting = true
        sourceKeyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
        // Capture stored diagnostics before an original assertion can throw.
        result.runtime.recordsLazyListUIAPhasesForTesting = false
        let phases = result.runtime.lazyListUIAPhasesForTesting
        let consumedRounds = result.runtime.lastLazyListConsumedRounds
        let consumedElements = result.runtime.lastLazyListConsumedElements
        let completion = result.runtime.lastLazyListWorkCompletion
        print(
            "ListKeyboardPhaseTests phaseCount=\(phases.count)"
                + " consumedRounds=\(consumedRounds) consumedElements=\(consumedElements)"
                + " completion=\(completion)"
        )
        for (index, phase) in phases.prefix(512).enumerated() {
            let physicalActivityCount = phase.activePhysicalActivityIDs.map { String($0.count) } ?? "unavailable"
            print(
                "ListKeyboardPhaseTests phase[\(index)] kind=\(phase.kind)"
                    + " pass=\(phase.layoutPassID) sequence=\(phase.resolutionSequence)"
                    + " geometry=\(phase.geometryRevision) mutation=\(phase.mutationRevision)"
                    + " consumedRounds=\(phase.consumedRounds) remainingRounds=\(phase.remainingRounds)"
                    + " remainingElements=\(phase.remainingElements) physicalActivityCount=\(physicalActivityCount)"
            )
        }

        XCTAssertEqual(selection, 900)
        let target = try result.rowRoot("virtual-row-900")
        XCTAssertGreaterThan(try result.scrollContainer().scrollOffset, 20_000)
        XCTAssertTrue(result.runtime.focusedNode === target, "A supported distant navigation must focus immediately")
        XCTAssertFalse(target.isLayoutDeferredByVirtualization)

        let targetKeyDown = try XCTUnwrap(target.onKeyDown)
        targetKeyDown(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
        XCTAssertEqual(selection, 899)
        let previous = try result.rowRoot("virtual-row-899")
        XCTAssertTrue(result.runtime.focusedNode === previous)
        XCTAssertFalse(previous.isLayoutDeferredByVirtualization)
        try settle(result)
    }
}
