import WinSwiftUI
@preconcurrency import XCTest

/// A public client surface that deliberately imports no implementation modules.
@MainActor
public struct BindingFacadeBoundaryValue<Value> {
    @Binding private var value: Value

    public init(_ binding: Binding<Value>) {
        _value = binding
    }

    public var wrappedValue: Value {
        get { value }
        nonmutating set { value = newValue }
    }

    public var projectedValue: Binding<Value> { $value }
}

@MainActor
final class BindingFacadePublicBoundaryTests: XCTestCase {
    func testInferredBindingSharesWritesThroughPublicWrapperAndProjection() async {
        var value = 3
        var writes: [Int] = []
        let binding = Binding(
            get: { value },
            set: {
                value = $0
                writes.append($0)
            })
        let fixture = BindingFacadeBoundaryValue(binding)
        let projected: Binding<Int> = fixture.projectedValue

        XCTAssertEqual(fixture.wrappedValue, 3)
        XCTAssertEqual(projected.wrappedValue, 3)
        fixture.wrappedValue = 5
        XCTAssertEqual(binding.wrappedValue, 5)
        XCTAssertEqual(projected.wrappedValue, 5)
        projected.wrappedValue = 8
        XCTAssertEqual(value, 8)
        XCTAssertEqual(fixture.wrappedValue, 8)
        XCTAssertEqual(writes, [5, 8])

        value = 11
        XCTAssertEqual(fixture.wrappedValue, 11)
        XCTAssertEqual(projected.wrappedValue, 11)
        XCTAssertEqual(writes, [5, 8], "Reads must not write a copied value back to the binding.")
    }

    func testExplicitBindingPreservesTransactionAcrossPublicGenericProjection() async {
        var value = "initial"
        var received: [Transaction] = []
        let binding = Binding<String>(
            get: { value },
            set: { newValue, transaction in
                value = newValue
                received.append(transaction)
            })
        var configured = Transaction(animation: .linear(duration: 0.25))
        configured.disablesAnimations = true
        configured.isContinuous = true
        let fixture = BindingFacadeBoundaryValue(binding.transaction(configured))
        let projected: Binding<String> = fixture.projectedValue

        XCTAssertEqual(projected.transaction.animation?.duration, 0.25)
        XCTAssertEqual(projected.transaction.animation?.easing, .linear)
        XCTAssertTrue(projected.transaction.disablesAnimations)
        XCTAssertTrue(projected.transaction.isContinuous)
        fixture.wrappedValue = "wrapped"
        projected.wrappedValue = "projected"

        XCTAssertEqual(value, "projected")
        XCTAssertEqual(binding.wrappedValue, "projected")
        XCTAssertEqual(fixture.wrappedValue, "projected")
        XCTAssertEqual(received.count, 2)
        for transaction in received {
            XCTAssertEqual(transaction.animation?.duration, 0.25)
            XCTAssertEqual(transaction.animation?.easing, .linear)
            XCTAssertTrue(transaction.disablesAnimations)
            XCTAssertTrue(transaction.isContinuous)
        }
        XCTAssertNil(binding.transaction.animation)
        XCTAssertFalse(binding.transaction.disablesAnimations)
        XCTAssertFalse(binding.transaction.isContinuous)
    }
}
