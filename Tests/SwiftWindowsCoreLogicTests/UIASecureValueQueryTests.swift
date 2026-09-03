import CUIAInterop
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform

private func secureValueQueryElement(
    id: UInt64 = 0, value: String? = "Private fixture value", isPassword: Bool = true,
    supportsValue: Bool = true
) -> UIAElementSnapshot {
    UIAElementSnapshot(
        id: id, parentID: nil, name: "Authored name", value: value,
        helpText: "Authored help", automationID: "secure-value-query",
        controlType: Int32(SWU_UIA_CONTROL_TYPE_EDIT),
        bounds: Rect(x: 0, y: 0, width: 200, height: 40),
        isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: true,
        hasDefaultAction: false, isPassword: isPassword, supportsValue: supportsValue,
        isReadOnly: false)
}

@MainActor
private final class SecureValueQuerySource: UIAElementTreeSource {
    var element: UIAElementSnapshot

    init(_ element: UIAElementSnapshot) { self.element = element }

    func uiaElementSnapshots() -> [UIAElementSnapshot] { [element] }
    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool { false }
    func uiaSetFocus(elementID: UInt64) {}
}

/// These tests exercise existing COM vtables without creating an HWND or a UIA client.
@MainActor
private func withSecureValueQueryProvider(
    _ element: UIAElementSnapshot,
    _ body: @MainActor (SecureValueQuerySource, UnsafeMutableRawPointer) throws -> Void
) throws {
    let source = SecureValueQuerySource(element)
    let bridge = UIAProviderBridge(source: source)
    let root = try XCTUnwrap(bridge.retainedRootProviderForTesting())
    defer {
        SWU_UIAReleaseProvider(root)
        withExtendedLifetime(bridge) {}
    }
    try body(source, root)
}

@MainActor
private func secureValueQueryRead(
    _ valueProvider: UnsafeMutableRawPointer,
    file: StaticString = #filePath, line: UInt = #line
) throws -> String {
    var raw: UnsafeMutablePointer<UInt16>?
    let status = SWU_UIAValueProviderGetValueResult(valueProvider, &raw)
    defer { if let raw { SWU_UIAFreeString(raw) } }
    XCTAssertEqual(status, 0, file: file, line: line)
    let value = try XCTUnwrap(raw, file: file, line: line)
    var length = 0
    while value[length] != 0 { length += 1 }
    return String(decoding: UnsafeBufferPointer(start: value, count: length), as: UTF16.self)
}

final class UIASecureValueQueryTests: XCTestCase {
    func testPasswordValueIsAbsentRegardlessOfValuePatternSupport() async {
        for supportsValue in [false, true] {
            for value in ["", "Private fixture value"] {
                let query = UIAQuerySnapshot([
                    secureValueQueryElement(value: value, supportsValue: supportsValue)
                ])
                XCTAssertNil(query.stringProperty(0, property: Int32(SWU_UIA_STRING_VALUE)))
                XCTAssertEqual(query.boolProperty(0, property: Int32(SWU_UIA_BOOL_IS_PASSWORD)), 1)
                XCTAssertEqual(query.supportsPattern(0, pattern: Int32(SWU_UIA_PATTERN_VALUE)), 0)
            }
        }
    }

    func testPasswordValueSuppressionPreservesAuthoredNonValueProperties() async {
        let element = secureValueQueryElement()
        let query = UIAQuerySnapshot([element])
        XCTAssertNil(query.stringProperty(0, property: Int32(SWU_UIA_STRING_VALUE)))
        XCTAssertEqual(query.stringProperty(0, property: Int32(SWU_UIA_STRING_NAME)), "Authored name")
        XCTAssertEqual(query.stringProperty(0, property: Int32(SWU_UIA_STRING_HELP_TEXT)), "Authored help")
        XCTAssertEqual(query.stringProperty(0, property: Int32(SWU_UIA_STRING_AUTOMATION_ID)), "secure-value-query")
        XCTAssertEqual(query.controlType(0), Int32(SWU_UIA_CONTROL_TYPE_EDIT))
        XCTAssertEqual(query.boundingRectangle(0), element.bounds)
        XCTAssertEqual(element.value, "Private fixture value", "The query must not mutate its input snapshot")
    }

    func testNonPasswordValueRemainsReadableWithoutValuePatternSupport() async {
        var element = secureValueQueryElement(value: "Authored status", isPassword: false, supportsValue: false)
        element.controlType = Int32(SWU_UIA_CONTROL_TYPE_GROUP)
        element.isEnabled = false
        element.isReadOnly = true
        let query = UIAQuerySnapshot([element])
        XCTAssertEqual(query.stringProperty(0, property: Int32(SWU_UIA_STRING_VALUE)), "Authored status")
        XCTAssertEqual(query.supportsPattern(0, pattern: Int32(SWU_UIA_PATTERN_VALUE)), 0)
        XCTAssertEqual(query.boolProperty(0, property: Int32(SWU_UIA_BOOL_IS_PASSWORD)), 0)
        XCTAssertEqual(query.boolProperty(0, property: Int32(SWU_UIA_BOOL_IS_ENABLED)), 0)
    }

    func testDuplicateIDsTakePasswordStateAndValueFromTheSameFirstElement() async {
        let password = secureValueQueryElement(id: 7)
        let ordinary = secureValueQueryElement(
            id: 7, value: "Public duplicate", isPassword: false, supportsValue: false)
        let passwordFirst = UIAQuerySnapshot([password, ordinary])
        XCTAssertNil(passwordFirst.stringProperty(7, property: Int32(SWU_UIA_STRING_VALUE)))
        XCTAssertEqual(passwordFirst.boolProperty(7, property: Int32(SWU_UIA_BOOL_IS_PASSWORD)), 1)

        let ordinaryFirst = UIAQuerySnapshot([ordinary, password])
        XCTAssertEqual(ordinaryFirst.stringProperty(7, property: Int32(SWU_UIA_STRING_VALUE)), "Public duplicate")
        XCTAssertEqual(ordinaryFirst.boolProperty(7, property: Int32(SWU_UIA_BOOL_IS_PASSWORD)), 0)
    }

    func testCopiedSnapshotKeepsItsPasswordFlagAndValueTogetherAcrossMutation() async {
        var elements = [secureValueQueryElement(value: "Public before", isPassword: false)]
        let publicBefore = UIAQuerySnapshot(elements)
        elements[0].isPassword = true
        elements[0].value = "Private after"
        let passwordAfter = UIAQuerySnapshot(elements)

        XCTAssertEqual(publicBefore.stringProperty(0, property: Int32(SWU_UIA_STRING_VALUE)), "Public before")
        XCTAssertEqual(publicBefore.boolProperty(0, property: Int32(SWU_UIA_BOOL_IS_PASSWORD)), 0)
        XCTAssertNil(passwordAfter.stringProperty(0, property: Int32(SWU_UIA_STRING_VALUE)))
        XCTAssertEqual(passwordAfter.boolProperty(0, property: Int32(SWU_UIA_BOOL_IS_PASSWORD)), 1)

        elements[0].isPassword = false
        elements[0].value = "Public latest"
        let publicLatest = UIAQuerySnapshot(elements)
        XCTAssertNil(passwordAfter.stringProperty(0, property: Int32(SWU_UIA_STRING_VALUE)))
        XCTAssertEqual(publicLatest.stringProperty(0, property: Int32(SWU_UIA_STRING_VALUE)), "Public latest")
        XCTAssertEqual(publicLatest.boolProperty(0, property: Int32(SWU_UIA_BOOL_IS_PASSWORD)), 0)
    }

    func testNilAndMissingValueQueriesRemainAbsent() async {
        for isPassword in [false, true] {
            let query = UIAQuerySnapshot([secureValueQueryElement(value: nil, isPassword: isPassword)])
            XCTAssertNil(query.stringProperty(0, property: Int32(SWU_UIA_STRING_VALUE)))
            XCTAssertNil(query.stringProperty(99, property: Int32(SWU_UIA_STRING_VALUE)))
        }
    }

    func testHeldValueProviderReturnsEmptyAfterItsSourceBecomesPassword() async throws {
        try await MainActor.run {
            try withSecureValueQueryProvider(
                secureValueQueryElement(value: "Public before", isPassword: false)
            ) { source, root in
                var rawPattern: UnsafeMutableRawPointer?
                let status = SWU_UIAProviderGetPatternResult(root, Int32(SWU_UIA_PATTERN_VALUE), &rawPattern)
                defer { SWU_UIAReleaseProvider(rawPattern) }
                XCTAssertEqual(status, 0)
                let heldValue = try XCTUnwrap(rawPattern)
                XCTAssertEqual(try secureValueQueryRead(heldValue), "Public before")

                source.element.isPassword = true
                source.element.value = "Private after"
                // Keep the malformed supportsValue=true claim to prove password state wins.
                XCTAssertTrue(source.element.supportsValue)
                var newPattern: UnsafeMutableRawPointer?
                let unavailable = SWU_UIAProviderGetPatternResult(root, Int32(SWU_UIA_PATTERN_VALUE), &newPattern)
                defer { SWU_UIAReleaseProvider(newPattern) }
                XCTAssertEqual(unavailable, 0)
                XCTAssertNil(newPattern)
                XCTAssertEqual(try secureValueQueryRead(heldValue), "")

                source.element.isPassword = false
                source.element.supportsValue = false
                source.element.value = "Public status after"
                XCTAssertEqual(try secureValueQueryRead(heldValue), "Public status after")
            }
        }
    }

    func testDirectValueQueryInterfaceReturnsEmptyForAnAlreadyPasswordSource() async throws {
        try await MainActor.run {
            for supportsValue in [false, true] {
                try withSecureValueQueryProvider(secureValueQueryElement(supportsValue: supportsValue)) { _, root in
                    var advertised: UnsafeMutableRawPointer?
                    let discovery = SWU_UIAProviderGetPatternResult(root, Int32(SWU_UIA_PATTERN_VALUE), &advertised)
                    defer { SWU_UIAReleaseProvider(advertised) }
                    XCTAssertEqual(discovery, 0)
                    XCTAssertNil(advertised)

                    var queried: UnsafeMutableRawPointer?
                    let status = SWU_UIAProviderQueryInterfaceResult(root, Int32(SWU_UIA_INTERFACE_VALUE), &queried)
                    defer { SWU_UIAReleaseProvider(queried) }
                    XCTAssertEqual(status, 0, "COM identity keeps its fixed interface set")
                    let valueInterface = try XCTUnwrap(queried)
                    XCTAssertEqual(try secureValueQueryRead(valueInterface), "")
                }
            }
        }
    }

    func testDirectValueQueryInterfacePreservesPassiveNonPasswordValue() async throws {
        try await MainActor.run {
            var element = secureValueQueryElement(value: "Authored status", isPassword: false, supportsValue: false)
            element.controlType = Int32(SWU_UIA_CONTROL_TYPE_GROUP)
            element.isEnabled = false
            element.isReadOnly = true
            try withSecureValueQueryProvider(element) { _, root in
                var advertised: UnsafeMutableRawPointer?
                let discovery = SWU_UIAProviderGetPatternResult(root, Int32(SWU_UIA_PATTERN_VALUE), &advertised)
                defer { SWU_UIAReleaseProvider(advertised) }
                XCTAssertEqual(discovery, 0)
                XCTAssertNil(advertised)

                var queried: UnsafeMutableRawPointer?
                let status = SWU_UIAProviderQueryInterfaceResult(root, Int32(SWU_UIA_INTERFACE_VALUE), &queried)
                defer { SWU_UIAReleaseProvider(queried) }
                XCTAssertEqual(status, 0)
                let valueInterface = try XCTUnwrap(queried)
                XCTAssertEqual(try secureValueQueryRead(valueInterface), "Authored status")
            }
        }
    }
}
