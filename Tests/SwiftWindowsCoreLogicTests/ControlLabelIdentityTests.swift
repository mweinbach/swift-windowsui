import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ControlLabelIdentityTests: XCTestCase {
    func testPickerMainAndCurrentLabelsKeepIndependentStateAcrossReloads() async throws {
        try assertIndependentLabels(.picker, slots: ["main", "current"])
    }

    func testSliderMainAndBoundsLabelsKeepIndependentStateAcrossReloads() async throws {
        try assertIndependentLabels(.slider, slots: ["main", "minimum", "maximum"])
    }

    func testProgressMainAndCurrentLabelsKeepIndependentStateAcrossReloads() async throws {
        try assertIndependentLabels(.progress, slots: ["main", "current"])
    }

    func testGaugeAllLabelRolesKeepIndependentStateAcrossReloads() async throws {
        try assertIndependentLabels(.gauge, slots: ["main", "current", "minimum", "maximum", "marked"])
    }

    private func assertIndependentLabels(
        _ kind: ControlLabelIdentityKind, slots: [String],
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let probe = ControlLabelIdentityProbe()
        let host = MountedLazyListTestHost(size: Size(width: 640, height: 480)) {
            Self.makeControl(kind, probe: probe)
        }
        defer {
            host.close()
            probe.captures.removeAll()
        }

        XCTAssertNotNil(host.layout(), file: file, line: line)
        XCTAssertEqual(host.runtime.root.children.count, 1, file: file, line: line)
        XCTAssertFalse(host.runtime.root.containsRejectedRetainedSource, file: file, line: line)
        XCTAssertEqual(probe.missingOwnerCount, 0, file: file, line: line)
        let original = try slots.map { try XCTUnwrap(probe.captures[$0], file: file, line: line) }
        XCTAssertEqual(Set(original.map { ObjectIdentifier($0.owner) }).count, slots.count, file: file, line: line)
        for (slot, capture) in zip(slots, original) {
            XCTAssertTrue(capture.owner.isLive, file: file, line: line)
            XCTAssertEqual(capture.value.wrappedValue, 0, file: file, line: line)
            XCTAssertEqual(host.find("control.label.\(slot)")?.text, "\(slot)=0", file: file, line: line)
        }

        for (index, capture) in original.enumerated() {
            capture.value.wrappedValue = 10 + index
        }
        host.reload()
        XCTAssertNotNil(host.layout(), file: file, line: line)
        XCTAssertEqual(host.runtime.root.children.count, 1, file: file, line: line)
        for (index, slot) in slots.enumerated() {
            let current = try XCTUnwrap(probe.captures[slot], file: file, line: line)
            XCTAssertTrue(current.owner === original[index].owner, file: file, line: line)
            XCTAssertTrue(current.owner.isLive, file: file, line: line)
            XCTAssertEqual(current.value.wrappedValue, 10 + index, file: file, line: line)
            XCTAssertEqual(original[index].value.wrappedValue, 10 + index, file: file, line: line)
            XCTAssertEqual(
                host.find("control.label.\(slot)")?.text, "\(slot)=\(10 + index)", file: file, line: line)
        }

        host.close()
        for (index, capture) in original.enumerated() {
            XCTAssertFalse(capture.owner.isLive, file: file, line: line)
            capture.value.wrappedValue = 99
            XCTAssertEqual(capture.value.wrappedValue, 10 + index, file: file, line: line)
        }
    }

    private static func makeControl(_ kind: ControlLabelIdentityKind, probe: ControlLabelIdentityProbe) -> AnyView {
        switch kind {
        case .picker:
            return AnyView(
                Picker(selection: .constant(1)) {
                    Text("Option").tag(1)
                } label: {
                    ControlLabelIdentityValue(slot: "main", probe: probe)
                } currentValueLabel: {
                    ControlLabelIdentityValue(slot: "current", probe: probe)
                })
        case .slider:
            return AnyView(
                Slider(value: .constant(0.5), in: 0...1) {
                    ControlLabelIdentityValue(slot: "main", probe: probe)
                } minimumValueLabel: {
                    ControlLabelIdentityValue(slot: "minimum", probe: probe)
                } maximumValueLabel: {
                    ControlLabelIdentityValue(slot: "maximum", probe: probe)
                })
        case .progress:
            return AnyView(
                ProgressView(value: 0.5, total: 1) {
                    ControlLabelIdentityValue(slot: "main", probe: probe)
                } currentValueLabel: {
                    ControlLabelIdentityValue(slot: "current", probe: probe)
                })
        case .gauge:
            return AnyView(
                Gauge(value: 0.5, in: 0...1) {
                    ControlLabelIdentityValue(slot: "main", probe: probe)
                } currentValueLabel: {
                    ControlLabelIdentityValue(slot: "current", probe: probe)
                } minimumValueLabel: {
                    ControlLabelIdentityValue(slot: "minimum", probe: probe)
                } maximumValueLabel: {
                    ControlLabelIdentityValue(slot: "maximum", probe: probe)
                } markedValueLabels: {
                    ControlLabelIdentityValue(slot: "marked", probe: probe)
                })
        }
    }
}

private enum ControlLabelIdentityKind {
    case picker
    case slider
    case progress
    case gauge
}

@MainActor
private struct ControlLabelIdentityCapture {
    let owner: StateMountOwner
    let value: Binding<Int>
}

@MainActor
private final class ControlLabelIdentityProbe {
    var captures: [String: ControlLabelIdentityCapture] = [:]
    var missingOwnerCount = 0

    func record(_ slot: String, owner: StateMountOwner?, value: Binding<Int>) {
        guard let owner else {
            missingOwnerCount += 1
            return
        }
        captures[slot] = ControlLabelIdentityCapture(owner: owner, value: value)
    }
}

@MainActor
private struct ControlLabelIdentityValue: View {
    let slot: String
    let probe: ControlLabelIdentityProbe
    @State private var value = 0

    var body: some View {
        probe.record(slot, owner: ViewBuildContextScope.current?.viewIdentity.installedOwner, value: $value)
        return Text("\(slot)=\(value)").accessibilityIdentifier("control.label.\(slot)")
    }
}
