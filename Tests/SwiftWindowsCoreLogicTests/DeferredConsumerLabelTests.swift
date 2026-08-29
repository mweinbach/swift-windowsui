import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class DeferredConsumerLabelTests: XCTestCase {
    func testDatePickerEmptyDeferredLabelsMatchStaticEmptyLabels() async throws {
        try assertEmptyLabelsMatch(.datePicker)
        try assertEmptyLabelsMatch(.graphicalDatePicker)
    }

    func testColorPickerEmptyDeferredLabelsMatchStaticEmptyLabels() async throws {
        try assertEmptyLabelsMatch(.colorPicker)
    }

    func testPickerEmptyDeferredMainAndCurrentLabelsMatchStaticEmptyLabels() async throws {
        try assertEmptyLabelsMatch(.picker)
    }

    func testSliderEmptyDeferredMainAndBoundsLabelsKeepUnlabeledTrackGeometry() async throws {
        try assertEmptyLabelsMatch(.slider)
    }

    func testPrimitiveProgressViewEmptyDeferredLabelsMatchStaticEmptyLabels() async throws {
        try assertEmptyLabelsMatch(.progressView)
    }

    func testGaugeEmptyDeferredHeaderBoundsAndMarkedLabelsMatchStaticEmptyLabels() async throws {
        try assertEmptyLabelsMatch(.gauge)
    }

    func testEmptyDeferredSecondaryLabelsDoNotAddRowsBesideANonemptyMainLabel() async throws {
        for kind in [DeferredConsumerLabelKind.picker, .slider, .progressView, .gauge] {
            for sourceCount in [0, 2] {
                try assertLabelsMatch(kind, sourceCount: sourceCount, scenario: .mainOnly)
            }
        }
    }

    func testNonemptyDeferredLabelsPreserveTextGeometryAndDatePickerAccessibleNames() async throws {
        for kind in DeferredConsumerLabelKind.allCases {
            try assertLabelsMatch(kind, sourceCount: 2, scenario: .nonempty)
        }
    }

    private func assertEmptyLabelsMatch(
        _ kind: DeferredConsumerLabelKind, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for sourceCount in [0, 2] {
            try assertLabelsMatch(kind, sourceCount: sourceCount, scenario: .empty, file: file, line: line)
        }
    }

    private func assertLabelsMatch(
        _ kind: DeferredConsumerLabelKind, sourceCount: Int, scenario: DeferredConsumerLabelScenario,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let probe = DeferredConsumerLabelProbe()
        let message = "\(kind.rawValue), \(scenario), \(sourceCount) source rows"
        let staticLabels: (DeferredConsumerLabelSlot) -> [AnyView] = { slot in
            if scenario == .nonempty || (scenario == .mainOnly && slot == .label) {
                let count = scenario == .mainOnly ? 1 : sourceCount
                return (0..<count).map { AnyView(Text(deferredConsumerLabelText(slot, ordinal: $0))) }
            }
            // This is the ordinary canonical final result of { EmptyView() }.
            return ViewBuilder.buildFinalResult(EmptyView())
        }
        let expectedView = makeControl(kind, labels: staticLabels)
        let actualView = makeControl(kind) { slot in
            if scenario == .mainOnly && slot == .label { return staticLabels(slot) }
            let rows = ForEach(0..<sourceCount) { ordinal in
                let _ = probe.record(slot, ordinal: ordinal)
                if scenario == .nonempty {
                    Text(deferredConsumerLabelText(slot, ordinal: ordinal))
                } else {
                    EmptyView()
                }
            }
            // Exercise the canonical array carrier, without the explicitly
            // eager WindowsArrayViewBuilder/ForEach-expression escape hatch.
            let labels: [AnyView] = ViewBuilder.buildFinalResult(rows)
            XCTAssertEqual(labels.count, 1, message, file: file, line: line)
            XCTAssertTrue(labels.first?.isDeferredViewListProjection == true, message, file: file, line: line)
            return labels
        }
        XCTAssertTrue(
            probe.calls.isEmpty, "Control initialization must retain its label factories: \(message)", file: file,
            line: line)

        // The shared fixture installs the real State coordinator and performs
        // retained layout without creating a window, HWND, dialog, or renderer.
        let size = Size(width: 640, height: 480)
        let expected = MountedLazyListTestHost(size: size) { expectedView }
        defer { expected.close() }
        let actual = MountedLazyListTestHost(size: size) { actualView }
        defer { actual.close() }
        _ = try XCTUnwrap(expected.layout(), message, file: file, line: line)
        _ = try XCTUnwrap(actual.layout(), message, file: file, line: line)
        XCTAssertEqual(expected.runtime.root.children.count, 1, message, file: file, line: line)
        XCTAssertEqual(actual.runtime.root.children.count, 1, message, file: file, line: line)
        XCTAssertFalse(expected.runtime.root.containsRejectedRetainedSource, message, file: file, line: line)
        XCTAssertFalse(actual.runtime.root.containsRejectedRetainedSource, message, file: file, line: line)
        assertSameTree(actual.runtime.root, expected.runtime.root, path: message, file: file, line: line)

        let deferredSlots = kind.slots.filter { scenario != .mainOnly || $0 != .label }
        XCTAssertEqual(probe.calls.count, sourceCount * deferredSlots.count, message, file: file, line: line)
        for slot in deferredSlots {
            XCTAssertEqual(
                probe.calls.filter { $0.slot == slot }.map(\.ordinal), Array(0..<sourceCount),
                "Each \(slot.rawValue) factory must run exactly once: \(message)", file: file, line: line)
        }
        let callsAfterConstruction = probe.calls
        _ = try XCTUnwrap(actual.layout(), message, file: file, line: line)
        XCTAssertEqual(
            probe.calls, callsAfterConstruction, "Layout must not repeat label factories: \(message)", file: file,
            line: line)
        assertSameTree(actual.runtime.root, expected.runtime.root, path: message, file: file, line: line)

        if scenario == .nonempty {
            let texts = actual.nodes.compactMap(\.text)
            for slot in kind.slots {
                for ordinal in 0..<sourceCount {
                    let text = deferredConsumerLabelText(slot, ordinal: ordinal)
                    XCTAssertEqual(texts.filter { $0 == text }.count, 1, message, file: file, line: line)
                }
            }
            if kind == .datePicker || kind == .graphicalDatePicker {
                XCTAssertTrue(
                    actual.nodes.contains { $0.accessibilityLabel == deferredConsumerLabelText(.label, ordinal: 0) },
                    "The materialized date label must name the accessible control", file: file, line: line)
            }
        }
    }

    private func makeControl(
        _ kind: DeferredConsumerLabelKind, labels: (DeferredConsumerLabelSlot) -> [AnyView]
    ) -> AnyView {
        switch kind {
        case .datePicker, .graphicalDatePicker:
            let picker = DatePicker(
                selection: .constant(Date(timeIntervalSince1970: 1_778_423_880)), displayedComponents: .date
            ) {
                return labels(.label)
            }
            .datePickerStyle(kind == .graphicalDatePicker ? .graphical : .automatic)
            .environment(\.calendar, Calendar(identifier: .gregorian))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            return AnyView(picker)
        case .colorPicker:
            return AnyView(
                ColorPicker(selection: .constant(.blue)) {
                    return labels(.label)
                }
                .environment(\.colorPickerUsesNativeDialog, false))
        case .picker:
            return AnyView(
                Picker(selection: .constant(1)) {
                    Text("Selected option").tag(1)
                } label: {
                    return labels(.label)
                } currentValueLabel: {
                    return labels(.current)
                })
        case .slider:
            return AnyView(
                Slider(value: .constant(0.5), in: 0...1) {
                    return labels(.label)
                } minimumValueLabel: {
                    return labels(.minimum)
                } maximumValueLabel: {
                    return labels(.maximum)
                })
        case .progressView:
            // No custom style body: this is the primitive fallback whose
            // empty-label branches choose a bare bar or an extra header.
            return AnyView(
                ProgressView(value: 0.5, total: 1.0) {
                    return labels(.label)
                } currentValueLabel: {
                    return labels(.current)
                })
        case .gauge:
            return AnyView(
                Gauge(value: 0.5, in: 0...1) {
                    return labels(.label)
                } currentValueLabel: {
                    return labels(.current)
                } minimumValueLabel: {
                    return labels(.minimum)
                } maximumValueLabel: {
                    return labels(.maximum)
                } markedValueLabels: {
                    return labels(.marked)
                })
        }
    }

    private func assertSameTree(
        _ actual: ViewNode, _ expected: ViewNode, path: String,
        file: StaticString, line: UInt
    ) {
        assertSameLayout(actual.layoutMode, expected.layoutMode, path: path, file: file, line: line)
        XCTAssertEqual(actual.preferredSize, expected.preferredSize, path, file: file, line: line)
        XCTAssertEqual(actual.frame, expected.frame, path, file: file, line: line)
        XCTAssertEqual(actual.layoutFillAxes, expected.layoutFillAxes, path, file: file, line: line)
        XCTAssertEqual(actual.text, expected.text, path, file: file, line: line)
        XCTAssertEqual(actual.accessibilityLabel, expected.accessibilityLabel, path, file: file, line: line)
        XCTAssertEqual(actual.accessibilityValue, expected.accessibilityValue, path, file: file, line: line)
        XCTAssertEqual(actual.children.count, expected.children.count, path, file: file, line: line)
        for (index, children) in zip(actual.children, expected.children).enumerated() {
            assertSameTree(children.0, children.1, path: "\(path)/\(index)", file: file, line: line)
        }
    }

    private func assertSameLayout(
        _ actual: ViewLayoutMode, _ expected: ViewLayoutMode, path: String,
        file: StaticString, line: UInt
    ) {
        switch (actual, expected) {
        case (.absolute, .absolute):
            break
        case (.stack(let actual), .stack(let expected)), (.lazyStack(let actual), .lazyStack(let expected)):
            XCTAssertEqual(actual, expected, path, file: file, line: line)
        case (.flex(let actual), .flex(let expected)):
            XCTAssertEqual(actual, expected, path, file: file, line: line)
        case (.grid(let actual), .grid(let expected)):
            XCTAssertEqual(actual, expected, path, file: file, line: line)
        case (.gridRow(let actual), .gridRow(let expected)):
            XCTAssertEqual(actual, expected, path, file: file, line: line)
        default:
            XCTFail("Different layout modes at \(path): \(actual) versus \(expected)", file: file, line: line)
        }
    }
}

private enum DeferredConsumerLabelKind: String, CaseIterable {
    case datePicker
    case graphicalDatePicker
    case colorPicker
    case picker
    case slider
    case progressView
    case gauge

    var slots: [DeferredConsumerLabelSlot] {
        switch self {
        case .datePicker, .graphicalDatePicker, .colorPicker: [.label]
        case .picker, .progressView: [.label, .current]
        case .slider: [.label, .minimum, .maximum]
        case .gauge: [.label, .current, .minimum, .maximum, .marked]
        }
    }
}

private enum DeferredConsumerLabelScenario: Equatable {
    case empty
    case mainOnly
    case nonempty
}

private enum DeferredConsumerLabelSlot: String {
    case label
    case current
    case minimum
    case maximum
    case marked
}

private struct DeferredConsumerLabelCall: Equatable {
    let slot: DeferredConsumerLabelSlot
    let ordinal: Int
}

@MainActor
private final class DeferredConsumerLabelProbe {
    private(set) var calls: [DeferredConsumerLabelCall] = []

    func record(_ slot: DeferredConsumerLabelSlot, ordinal: Int) {
        calls.append(DeferredConsumerLabelCall(slot: slot, ordinal: ordinal))
    }
}

private func deferredConsumerLabelText(_ slot: DeferredConsumerLabelSlot, ordinal: Int) -> String {
    "\(slot.rawValue) \(ordinal)"
}
