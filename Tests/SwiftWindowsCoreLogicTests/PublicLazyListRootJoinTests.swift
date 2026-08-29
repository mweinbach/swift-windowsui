import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Regression source for the public List join with the newer retained Grid,
/// bitmap resizing, fixed-frame intent, and mounted calendar implementations.
/// These use the ordinary headless component host, never a native window.
@MainActor
final class PublicLazyListRootJoinTests: XCTestCase {
    func testDeferredRowsKeepSharedGridTracksAndAcceptConfigurationChanges() async throws {
        for builder in [false, true] {
            let probe = PublicListRootJoinProbe(kind: .grid)
            let host = MountedLazyListTestHost(size: Size(width: 400, height: 80)) {
                publicRootJoinList(probe, builder: builder)
            }
            defer { host.close() }
            try host.assertCommittedDescriptor()
            XCTAssertTrue(probe.factories.isEmpty)
            XCTAssertNotNil(host.layout())
            let grid = try XCTUnwrap(host.find("join.row.0"))
            guard case .grid = grid.layoutMode else { return XCTFail("A List row must retain its real Grid layout") }
            XCTAssertEqual(grid.children.count, 2)
            for row in grid.children {
                guard case .gridRow = row.layoutMode else { return XCTFail("ForEach must preserve GridRow boundaries") }
                XCTAssertEqual(row.children.count, 2)
            }
            try assertGridOffsets(in: host, horizontal: 67, vertical: 15)
            XCTAssertLessThan(probe.factories.count, 128)
            XCTAssertLessThan(try XCTUnwrap(try host.list().retainedLazyListAdapter).mountedRecordCount, 32)

            probe.horizontalSpacing = 11
            probe.verticalSpacing = 9
            host.reload()
            XCTAssertNotNil(host.layout())
            XCTAssertTrue(host.find("join.row.0") === grid)
            guard case .grid(let layout) = grid.layoutMode else { return XCTFail("Grid must survive reconciliation") }
            XCTAssertEqual(layout.horizontalSpacing, 11)
            XCTAssertEqual(layout.verticalSpacing, 9)
            try assertGridOffsets(in: host, horizontal: 71, vertical: 19)
            XCTAssertNil(host.find("join.row.9000"))
            XCTAssertNil(host.coordinator.latestInstallationError)
        }
    }

    func testDeferredImageReconciliationKeepsBitmapResizingAndFixedAxisIntent() async throws {
        for builder in [false, true] {
            let probe = PublicListRootJoinProbe(kind: .image)
            let host = MountedLazyListTestHost(size: Size(width: 400, height: 80)) {
                publicRootJoinList(probe, builder: builder)
            }
            defer { host.close() }
            XCTAssertTrue(probe.factories.isEmpty)
            XCTAssertNotNil(host.layout())
            let frame = try XCTUnwrap(host.find("join.row.0"))
            let image = try imageNode(in: frame)
            XCTAssertEqual(frame.fixedPreferredSizeAxes, .both)
            XCTAssertTrue(image.imageUsesBitmapResizing)
            XCTAssertEqual(image.imageResizingMode, .tile)
            XCTAssertEqual(image.layoutFillAxes, .both)
            XCTAssertNil(image.preferredSize)
            XCTAssertEqual(image.bitmapSurface?.contentKey, probe.bitmap.contentKey)

            probe.isResizable = false
            probe.fixedWidth = nil
            host.reload()
            XCTAssertNotNil(host.layout())
            XCTAssertTrue(host.find("join.row.0") === frame)
            XCTAssertTrue(try imageNode(in: frame) === image)
            XCTAssertEqual(frame.fixedPreferredSizeAxes, .verticalOnly)
            XCTAssertFalse(image.imageUsesBitmapResizing)
            XCTAssertEqual(image.layoutFillAxes, LayoutFillAxes())
            XCTAssertEqual(image.preferredSize, Size(width: 3, height: 3))

            probe.isResizable = true
            probe.fixedWidth = 48
            probe.imageMode = .stretch
            probe.caps = EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
            host.reload()
            XCTAssertNotNil(host.layout())
            XCTAssertTrue(host.find("join.row.0") === frame)
            XCTAssertTrue(try imageNode(in: frame) === image)
            XCTAssertEqual(frame.fixedPreferredSizeAxes, .both)
            XCTAssertTrue(image.imageUsesBitmapResizing)
            XCTAssertEqual(image.imageResizingMode, .stretch)
            XCTAssertEqual(image.imageCapInsets, probe.caps)
            XCTAssertEqual(image.layoutFillAxes, .both)
            XCTAssertNil(image.preferredSize)
            XCTAssertEqual(image.bitmapSurface?.contentKey, probe.bitmap.contentKey)
            XCTAssertNil(host.find("join.row.9000"))
            XCTAssertNil(host.coordinator.latestInstallationError)
        }
    }

    func testCalendarBrowseStateSurvivesRowEvictionWhileItsOldActionExpires() async throws {
        for builder in [false, true] {
            let probe = PublicListRootJoinProbe(kind: .calendar)
            let initialSelection = probe.selection
            let host = MountedLazyListTestHost(size: Size(width: 400, height: 160)) {
                publicRootJoinList(probe, builder: builder)
            }
            defer { host.close() }
            XCTAssertTrue(probe.factories.isEmpty)
            host.render()
            XCTAssertEqual(try calendarNode(.monthTitle, in: host).text, "January 2024")
            let firstNext = try XCTUnwrap(try calendarNode(.nextMonth, in: host).onActivate)
            firstNext()
            host.render()
            XCTAssertEqual(try calendarNode(.monthTitle, in: host).text, "February 2024")
            let staleNext = try XCTUnwrap(try calendarNode(.nextMonth, in: host).onActivate)
            let attachment = try host.rowRoot("join.row.0").captureLazyListAttachmentProof()

            try host.scroll(to: 4000)
            XCTAssertNil(host.find("join.row.0"))
            XCTAssertFalse(attachment.isCurrent)
            let invalidations = host.events.stateInvalidations
            staleNext()
            XCTAssertEqual(host.events.stateInvalidations, invalidations)

            try host.scroll(to: 0)
            host.render()
            XCTAssertEqual(try calendarNode(.monthTitle, in: host).text, "February 2024")
            XCTAssertEqual(probe.selection, initialSelection)
            XCTAssertEqual(probe.selectionWrites, 0)
            XCTAssertLessThan(try XCTUnwrap(try host.list().retainedLazyListAdapter).mountedRecordCount, 32)
            XCTAssertNil(host.find("join.row.9000"))
            XCTAssertNil(host.coordinator.latestInstallationError)
        }
    }

    private func assertGridOffsets(
        in host: MountedLazyListTestHost, horizontal: Double, vertical: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let first = try XCTUnwrap(host.find("join.cell.0.0.0"), file: file, line: line)
        let right = try XCTUnwrap(host.find("join.cell.0.0.1"), file: file, line: line)
        let below = try XCTUnwrap(host.find("join.cell.0.1.0"), file: file, line: line)
        let firstFrame = try XCTUnwrap(host.runtime.resolvedLayoutFrame(of: first), file: file, line: line)
        let rightFrame = try XCTUnwrap(host.runtime.resolvedLayoutFrame(of: right), file: file, line: line)
        let belowFrame = try XCTUnwrap(host.runtime.resolvedLayoutFrame(of: below), file: file, line: line)
        XCTAssertEqual(rightFrame.minX - firstFrame.minX, horizontal, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(belowFrame.minY - firstFrame.minY, vertical, accuracy: 0.001, file: file, line: line)
    }

    private func imageNode(in row: ViewNode) throws -> ViewNode {
        try XCTUnwrap(MountedLazyListTestHost.descendants(in: row).first { $0.bitmapSurface != nil })
    }

    private func calendarNode(
        _ identifier: GraphicalDatePickerNodeID, in host: MountedLazyListTestHost
    ) throws -> ViewNode {
        let row = try XCTUnwrap(host.find("join.row.0"))
        return try XCTUnwrap(
            MountedLazyListTestHost.descendants(in: row).first { $0.nodeTag == identifier.nodeTag })
    }
}

@MainActor
private final class PublicListRootJoinProbe {
    enum Kind { case grid, image, calendar }
    let kind: Kind
    var factories: [Int] = []
    var horizontalSpacing = 7.0
    var verticalSpacing = 5.0
    var isResizable = true
    var fixedWidth: Double? = 32
    var imageMode = Image.ResizingMode.tile
    var caps = EdgeInsets.zero
    let bitmap = BitmapSurface(
        width: 3, height: 3, bytesPerRow: 12, pixels: Data(repeating: 255, count: 36))
    let calendar: Calendar
    var selection: Date
    var selectionWrites = 0

    init(kind: Kind) {
        self.kind = kind
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        self.calendar = calendar
        selection = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
    }

    func makeRow(_ index: Int) -> AnyView {
        factories.append(index)
        switch kind {
        case .grid:
            return AnyView(
                Grid(alignment: .topLeading, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) {
                    ForEach(0..<2) { row in
                        GridRow {
                            ForEach(0..<2) { column in
                                Rectangle().fill(Color.blue)
                                    .frame(width: publicRootJoinCellWidth(row: row, column: column), height: 10)
                                    .accessibilityIdentifier("join.cell.\(index).\(row).\(column)")
                            }
                        }
                    }
                }
                .accessibilityIdentifier("join.row.\(index)"))
        case .image:
            let image = Image(bitmap: bitmap)
            let content = isResizable ? image.resizable(capInsets: caps, resizingMode: imageMode) : image
            return AnyView(
                content.frame(width: fixedWidth, height: 24)
                    .accessibilityIdentifier("join.row.\(index)"))
        case .calendar:
            let binding = Binding<Date>(
                get: { self.selection },
                set: {
                    self.selection = $0
                    self.selectionWrites += 1
                })
            return AnyView(
                DatePicker("Date \(index)", selection: binding, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.calendar, calendar)
                    .environment(\.timeZone, calendar.timeZone)
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .accessibilityIdentifier("join.row.\(index)"))
        }
    }
}

private func publicRootJoinCellWidth(row: Int, column: Int) -> Double {
    row == 0 ? (column == 0 ? 20 : 50) : (column == 0 ? 60 : 30)
}

@MainActor
@ViewBuilder
private func publicRootJoinList(_ probe: PublicListRootJoinProbe, builder: Bool) -> some View {
    if builder {
        List { ForEach(0..<10_000) { probe.makeRow($0) } }.listStyle(.plain)
    } else {
        List(0..<10_000, id: \.self) { probe.makeRow($0) }.listStyle(.plain)
    }
}
