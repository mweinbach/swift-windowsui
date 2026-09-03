import XCTest

@testable import SwiftWindowsUI

/// Pure model proposal. Requires the new internal/package enum in INTERFACES;
/// intentionally not compilable against the baseline that has no such enum.
final class RetainedAccessibilityOverrideProposalTests: XCTestCase {
    func testExplicitNilIsNotInheritedOptionalMetadata() {
        let inherited: RetainedAccessibilityOverride<String?> = .inherit
        let cleared: RetainedAccessibilityOverride<String?> = .set(nil)
        let empty: RetainedAccessibilityOverride<String?> = .set("")
        XCTAssertNotEqual(inherited, cleared)
        XCTAssertNotEqual(cleared, empty)
        XCTAssertEqual(inherited.resolve(inheriting: "base"), "base")
        XCTAssertNil(cleared.resolve(inheriting: "base"))
        XCTAssertEqual(empty.resolve(inheriting: "base"), "")
        let inner: RetainedAccessibilityOverride<String?> = .set("inner")
        XCTAssertNil(cleared.resolve(inheriting: inner.resolve(inheriting: "base")))
        XCTAssertEqual(inherited.resolve(inheriting: inner.resolve(inheriting: "base")), "inner")
        XCTAssertEqual(inherited.resolve(inheriting: inherited.resolve(inheriting: "base")), "base")
    }

    func testExplicitFalseZeroAndEmptyCollectionAreNotInherited() {
        let disabled: RetainedAccessibilityOverride<Bool> = .set(false)
        let zero: RetainedAccessibilityOverride<Double> = .set(0)
        let empty: RetainedAccessibilityOverride<[String]> = .set([])
        XCTAssertNotEqual(disabled, .inherit)
        XCTAssertNotEqual(zero, .inherit)
        XCTAssertNotEqual(empty, .inherit)
        XCTAssertFalse(disabled.resolve(inheriting: true))
        XCTAssertEqual(zero.resolve(inheriting: 7), 0)
        XCTAssertEqual(empty.resolve(inheriting: ["base"]), [])
        XCTAssertEqual(RetainedAccessibilityOverride<Double>.inherit.resolve(inheriting: 7), 7)
        XCTAssertEqual(RetainedAccessibilityOverride<[String]>.inherit.resolve(inheriting: ["base"]), ["base"])
    }
}
