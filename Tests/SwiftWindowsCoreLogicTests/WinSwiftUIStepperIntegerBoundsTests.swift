import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// These invoke the public Stepper's retained buttons, not a duplicate arithmetic implementation.
/// Every fixture's generic construction deliberately selects the Strideable initializer, including Int.
@MainActor
final class WinSwiftUIStepperIntegerBoundsTests: XCTestCase {
    func testUInt8DecrementClampsBeforeUnsignedUnderflow() async throws {
        let fixture = StepperIntegerFixture(value: UInt8(1), bounds: 0...10, step: 2)
        try fixture.activate(.decrement)
        fixture.assertChange(from: 1, to: 0)
    }

    func testUInt8IncrementClampsBeforeUnsignedOverflow() async throws {
        let fixture = StepperIntegerFixture(value: UInt8(254), bounds: 0...255, step: 2)
        try fixture.activate(.increment)
        fixture.assertChange(from: 254, to: 255)
    }

    func testAllSignedIntegerWidthsClampOvershootingSteps() async throws {
        try assertSignedEndpoints(Int8.self)
        try assertSignedEndpoints(Int16.self)
        try assertSignedEndpoints(Int32.self)
        try assertSignedEndpoints(Int64.self)
        try assertSignedEndpoints(Int.self)
        try assertSignedEndpoints(Int128.self)
    }

    func testAllUnsignedIntegerWidthsClampOvershootingSteps() async throws {
        try assertUnsignedEndpoints(UInt8.self)
        try assertUnsignedEndpoints(UInt16.self)
        try assertUnsignedEndpoints(UInt32.self)
        try assertUnsignedEndpoints(UInt64.self)
        try assertUnsignedEndpoints(UInt.self)
        try assertUnsignedEndpoints(UInt128.self)
    }

    func testNarrowSignedValueAcceptsAStepLargerThanItsSignedRange() async throws {
        // Rejecting Int8(exactly: step) would wrongly clamp these representable answers.
        let up = StepperIntegerFixture(value: Int8(-120), bounds: -128...127, step: 200)
        try up.activate(.increment)
        up.assertChange(from: -120, to: 80)

        let down = StepperIntegerFixture(value: Int8(120), bounds: -128...127, step: 200)
        try down.activate(.decrement)
        down.assertChange(from: 120, to: -80)
    }

    func testWideUnsignedValuesPreserveUnitsAboveIntMax() async throws {
        let value64 = UInt64(Int.max) + 2
        let wide64 = StepperIntegerFixture(value: value64, bounds: UInt64.min...UInt64.max, step: 3)
        try wide64.activate(.increment)
        wide64.assertChange(from: value64, to: value64 + 3)
        wide64.clearEvents()
        try wide64.activate(.decrement)
        wide64.assertChange(from: value64 + 3, to: value64)

        let value128 = (UInt128(1) << 100) + 1
        let wide128 = StepperIntegerFixture(value: value128, bounds: UInt128.min...UInt128.max, step: 3)
        try wide128.activate(.increment)
        wide128.assertChange(from: value128, to: value128 + 3)
        wide128.clearEvents()
        try wide128.activate(.decrement)
        wide128.assertChange(from: value128 + 3, to: value128)
    }

    func testFullSignedSpanDoesNotOverflowDistanceComputation() async throws {
        let fixture = StepperIntegerFixture(value: Int.min + 1, bounds: Int.min...Int.max, step: Int.max)
        try fixture.activate(.increment)
        fixture.assertChange(from: Int.min + 1, to: 0)
        fixture.clearEvents()
        try fixture.activate(.increment)
        fixture.assertChange(from: 0, to: Int.max)

        let wide = StepperIntegerFixture(value: Int128(-1), bounds: Int128.min...Int128.max, step: Int.max)
        try wide.activate(.increment)
        wide.assertChange(from: -1, to: Int128(Int.max) - 1)
    }

    func testNegativeMinimumStrideClampsNarrowValuesWithoutNegationOverflow() async throws {
        let up = StepperIntegerFixture(value: Int8(1), bounds: -128...127, step: Int.min)
        try up.activate(.decrement)
        up.assertChange(from: 1, to: 127)

        let down = StepperIntegerFixture(value: Int8(1), bounds: -128...127, step: Int.min)
        try down.activate(.increment)
        down.assertChange(from: 1, to: -128)
    }

    func testNegativeMinimumStrideCanReachRepresentableWideValues() async throws {
        let signedUp = StepperIntegerFixture(value: Int64(-1), bounds: Int64.min...Int64.max, step: Int.min)
        try signedUp.activate(.decrement)
        signedUp.assertChange(from: -1, to: Int64.max)

        let signedDown = StepperIntegerFixture(value: Int64.max - 1, bounds: Int64.min...Int64.max, step: Int.min)
        try signedDown.activate(.increment)
        signedDown.assertChange(from: Int64.max - 1, to: -2)

        let unsignedUp = StepperIntegerFixture(value: UInt64(1), bounds: UInt64.min...UInt64.max, step: Int.min)
        try unsignedUp.activate(.decrement)
        unsignedUp.assertChange(from: 1, to: UInt64(Int.max) + 2)

        let unsignedDown = StepperIntegerFixture(value: UInt64.max - 1, bounds: UInt64.min...UInt64.max, step: Int.min)
        try unsignedDown.activate(.increment)
        unsignedDown.assertChange(from: UInt64.max - 1, to: UInt64(Int.max) - 1)
    }

    func testGenericNegativeAndZeroStepsKeepTheirExistingDirectionPolicy() async throws {
        let negative = StepperIntegerFixture(value: Int(5), bounds: 0...10, step: -2)
        try negative.activate(.increment)
        negative.assertChange(from: 5, to: 3)
        negative.clearEvents()
        try negative.activate(.decrement)
        negative.assertChange(from: 3, to: 5)

        let zero = StepperIntegerFixture(value: Int(5), bounds: 0...10, step: 0)
        try zero.activate(.increment)
        zero.assertChange(from: 5, to: 5)
        zero.clearEvents()
        try zero.activate(.decrement)
        zero.assertChange(from: 5, to: 5)

        // Availability still follows the named direction, even with a negative step.
        let lower = StepperIntegerFixture(value: Int(0), bounds: 0...10, step: -2)
        XCTAssertFalse(try lower.button(.decrement).isFocusable)
        try lower.button(.decrement).onActivate?()
        XCTAssertEqual(lower.value, 0)
        XCTAssertTrue(lower.events.isEmpty)
    }

    func testConcreteIntInitializerStillNormalizesNonpositiveSteps() async throws {
        for step in [0, -2, Int.min] {
            var value = 5
            var events: [String] = []
            let runtime = RetainedViewRuntime(root: ViewNode())
            let view = Stepper(
                value: Binding<Int>(
                    get: { value },
                    set: {
                        value = $0
                        events.append("write")
                    }
                ),
                in: 0...10,
                step: step,
                onEditingChanged: { events.append($0 ? "editing:true" : "editing:false") },
                label: { Text("Count") }
            )
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 120, height: 80) },
                invalidateHandler: { events.append("invalidate") }
            )
            let node = view.labelsHidden().makeComponent(context: context).makeNode(runtime: runtime)
            runtime.root.setChildren([node])
            let increment = try XCTUnwrap(node.children.first { $0.accessibilityLabel == "Increment" })
            try XCTUnwrap(increment.onActivate)()
            XCTAssertEqual(value, 6, "the concrete Int overload still normalizes this step to one")
            XCTAssertEqual(events, ["editing:true", "write", "editing:false", "invalidate"])
        }
    }

    func testOutOfRangeBindingIsClampedBeforeStepping() async throws {
        let above = StepperIntegerFixture(value: UInt8(250), bounds: 10...20, step: 3)
        try above.activate(.decrement)
        above.assertChange(from: 250, to: 17)

        let below = StepperIntegerFixture(value: UInt8(1), bounds: 10...20, step: 3)
        try below.activate(.increment)
        below.assertChange(from: 1, to: 13)
    }

    func testDisabledEndpointsDoNotWriteOrReportEditing() async throws {
        let lower = StepperIntegerFixture(value: UInt8(0), bounds: 0...10, step: 2)
        let decrement = try lower.button(.decrement)
        XCTAssertFalse(decrement.isFocusable)
        decrement.onActivate?()
        XCTAssertEqual(lower.value, 0)
        XCTAssertTrue(lower.events.isEmpty)

        lower.value = 10
        lower.rebuild()
        let increment = try lower.button(.increment)
        XCTAssertFalse(increment.isFocusable)
        increment.onActivate?()
        XCTAssertEqual(lower.value, 10)
        XCTAssertTrue(lower.events.isEmpty)

        let collapsed = StepperIntegerFixture(value: UInt8(5), bounds: 5...5, step: 2)
        for direction in [StepperIntegerDirection.increment, .decrement] {
            let button = try collapsed.button(direction)
            XCTAssertFalse(button.isFocusable)
            button.onActivate?()
        }
        XCTAssertEqual(collapsed.value, 5)
        XCTAssertTrue(collapsed.events.isEmpty)
    }

    func testKeyboardActivationPreservesEditingWriteAndInvalidationOrder() async throws {
        let fixture = StepperIntegerFixture(value: UInt8(1), bounds: 0...10, step: 2)
        fixture.layout()
        let decrement = try fixture.button(.decrement)
        XCTAssertEqual(decrement.accessibilityTraits, .isButton)
        XCTAssertEqual(decrement.accessibilityLabel, "Decrement")
        fixture.runtime.requestFocus(decrement)
        XCTAssertTrue(fixture.runtime.focusedNode === decrement)
        fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
        fixture.assertChange(from: 1, to: 0)
    }

    func testPointerActivationUsesTheSameBoundedArithmetic() async throws {
        let fixture = StepperIntegerFixture(value: UInt8(254), bounds: 0...255, step: 2)
        fixture.layout()
        let increment = try fixture.button(.increment)
        let incrementFrame = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: increment))
        XCTAssertGreaterThan(incrementFrame.size.width, 0)
        XCTAssertGreaterThan(incrementFrame.size.height, 0)
        let point = Point(x: incrementFrame.midX, y: incrementFrame.midY)
        fixture.runtime.pointerDown(at: point)
        fixture.runtime.pointerUp(at: point)
        fixture.assertChange(from: 254, to: 255)
    }

    func testNonintegerStrideableFallbackPreservesItsOwnAdvancement() async throws {
        let trace = StepperStrideTrace()
        let initial = StepperScaledValue(5, trace: trace)
        let fixture = StepperIntegerFixture(
            value: initial,
            bounds: StepperScaledValue(0)...StepperScaledValue(10),
            step: 2
        )
        try fixture.activate(.increment)
        fixture.assertChange(from: initial, to: StepperScaledValue(9))
        fixture.clearEvents()
        try fixture.activate(.decrement)
        fixture.assertChange(from: StepperScaledValue(9), to: initial)
        XCTAssertEqual(trace.steps, [2, -2], "the custom Strideable implementation still receives each raw delta")
    }

    func testFloatingPointFallbackKeepsFractionalAndPreclampedValues() async throws {
        let fractional = StepperIntegerFixture(value: Float(0.25), bounds: 0...1, step: 0.25)
        try fractional.activate(.increment)
        fractional.assertChange(from: 0.25, to: 0.5)
        fractional.clearEvents()
        try fractional.activate(.decrement)
        fractional.assertChange(from: 0.5, to: 0.25)

        let above = StepperIntegerFixture(value: Double(2), bounds: 0...1, step: 0.25)
        try above.activate(.decrement)
        above.assertChange(from: 2, to: 0.75)
    }

    func testUnboundedGenericStepperKeepsRawAdvancement() async throws {
        let trace = StepperStrideTrace()
        let initial = StepperScaledValue(5, trace: trace)
        let fixture = StepperIntegerFixture(value: initial, step: -2)
        try fixture.activate(.increment)
        fixture.assertChange(from: initial, to: StepperScaledValue(1))
        fixture.clearEvents()
        try fixture.activate(.decrement)
        fixture.assertChange(from: StepperScaledValue(1), to: initial)
        XCTAssertEqual(trace.steps, [-2, 2])
    }

    private func assertSignedEndpoints<Integer: FixedWidthInteger & SignedInteger>(
        _ type: Integer.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let upper = StepperIntegerFixture(value: Integer.max - 1, bounds: Integer.min...Integer.max, step: 2)
        try upper.activate(.increment)
        upper.assertChange(from: Integer.max - 1, to: Integer.max, file: file, line: line)

        let lower = StepperIntegerFixture(value: Integer.min + 1, bounds: Integer.min...Integer.max, step: 2)
        try lower.activate(.decrement)
        lower.assertChange(from: Integer.min + 1, to: Integer.min, file: file, line: line)
    }

    private func assertUnsignedEndpoints<Integer: FixedWidthInteger & UnsignedInteger>(
        _ type: Integer.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let upper = StepperIntegerFixture(value: Integer.max - 1, bounds: Integer.min...Integer.max, step: 2)
        try upper.activate(.increment)
        upper.assertChange(from: Integer.max - 1, to: Integer.max, file: file, line: line)

        let lower = StepperIntegerFixture(value: Integer(1), bounds: Integer.min...Integer.max, step: 2)
        try lower.activate(.decrement)
        lower.assertChange(from: 1, to: 0, file: file, line: line)
    }
}

private enum StepperIntegerDirection {
    case increment
    case decrement

    var label: String { self == .increment ? "Increment" : "Decrement" }
}

@MainActor
private final class StepperIntegerFixture<Value: Strideable & Comparable> where Value.Stride: SignedNumeric {
    var value: Value
    private(set) var events: [String] = []
    private(set) var eventValues: [Value] = []
    let runtime: RetainedViewRuntime
    private var node = ViewNode()
    private let initialValue: Value
    private let bounds: ClosedRange<Value>?
    private let step: Value.Stride

    init(value: Value, bounds: ClosedRange<Value>? = nil, step: Value.Stride) {
        self.value = value
        self.initialValue = value
        self.bounds = bounds
        self.step = step
        self.runtime = RetainedViewRuntime(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 80),
                layoutMode: .stack(.vertical(alignment: .leading))
            )
        )
        rebuild()
    }

    func rebuild() {
        let fallback = initialValue
        let binding = Binding<Value>(
            get: { [weak self] in self?.value ?? fallback },
            set: { [weak self] value in
                guard let self else { return }
                self.value = value
                self.record("write")
            }
        )
        let editing: @MainActor (Bool) -> Void = { [weak self] editing in
            self?.record(editing ? "editing:true" : "editing:false")
        }
        let view: Stepper
        if let bounds {
            view = Stepper(value: binding, in: bounds, step: step, onEditingChanged: editing) { Text("Count") }
        } else {
            view = Stepper(value: binding, step: step, onEditingChanged: editing) { Text("Count") }
        }
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 120, height: 80) },
            invalidateHandler: { [weak self] in self?.record("invalidate") }
        )
        node = view.labelsHidden().makeComponent(context: context).makeNode(runtime: runtime)
        runtime.root.setChildren([node])
    }

    func button(_ direction: StepperIntegerDirection) throws -> ViewNode {
        try XCTUnwrap(node.children.first { $0.accessibilityLabel == direction.label })
    }

    func activate(_ direction: StepperIntegerDirection) throws {
        let button = try button(direction)
        XCTAssertTrue(button.isFocusable, "the regression must start from an enabled direction")
        try XCTUnwrap(button.onActivate)()
    }

    func assertChange(
        from previous: Value,
        to expected: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(value, expected, file: file, line: line)
        XCTAssertEqual(events, ["editing:true", "write", "editing:false", "invalidate"], file: file, line: line)
        XCTAssertEqual(eventValues, [previous, expected, expected, expected], file: file, line: line)
    }

    func clearEvents() {
        events.removeAll(keepingCapacity: true)
        eventValues.removeAll(keepingCapacity: true)
    }

    func layout() {
        _ = runtime.renderScene(at: 0)
    }

    private func record(_ event: String) {
        events.append(event)
        eventValues.append(value)
    }
}

private final class StepperStrideTrace {
    var steps: [Double] = []
}

/// A noninteger Strideable with its own scale makes replacing advanced(by:) observable.
private struct StepperScaledValue: Strideable {
    let value: Double
    let trace: StepperStrideTrace?

    init(_ value: Double, trace: StepperStrideTrace? = nil) {
        self.value = value
        self.trace = trace
    }

    func advanced(by delta: Double) -> Self {
        trace?.steps.append(delta)
        return Self(value + delta * 2, trace: trace)
    }

    func distance(to other: Self) -> Double { (other.value - value) / 2 }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}
