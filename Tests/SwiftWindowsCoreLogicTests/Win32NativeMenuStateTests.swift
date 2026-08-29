import WinSDK
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

/// Pure state-word checks; these do not create or mutate an OS menu.
@MainActor
final class Win32NativeMenuStateTests: XCTestCase {
    func testEnablingClearsOnlyDisabledBitsForEveryPriorDisabledState() async {
        let preserved = UINT(MFS_CHECKED | MFS_HILITE | MFS_DEFAULT) | 0x8000_0000
        for disabledBits in UINT(0)...UINT(MFS_DISABLED) {
            XCTAssertEqual(
                Win32NativeWindowUtilities.menuItemState(preserved | disabledBits, enabled: true),
                preserved)
        }
    }

    func testDisablingKeepsAllOtherStateBitsForEveryPriorDisabledState() async {
        let preserved = UINT(MFS_CHECKED | MFS_HILITE | MFS_DEFAULT) | 0x4000_0000
        for disabledBits in UINT(0)...UINT(MFS_DISABLED) {
            XCTAssertEqual(
                Win32NativeWindowUtilities.menuItemState(preserved | disabledBits, enabled: false),
                preserved | UINT(MFS_DISABLED))
        }
    }

    func testRepeatedUpdatesAreIdempotentAndEnablingRestoresOtherStateBits() async {
        for previous in [UINT(0), UINT(MFS_CHECKED), UINT(MFS_HILITE | MFS_DEFAULT), UINT.max] {
            let disabled = Win32NativeWindowUtilities.menuItemState(previous, enabled: false)
            let enabled = Win32NativeWindowUtilities.menuItemState(disabled, enabled: true)
            XCTAssertEqual(Win32NativeWindowUtilities.menuItemState(disabled, enabled: false), disabled)
            XCTAssertEqual(Win32NativeWindowUtilities.menuItemState(enabled, enabled: true), enabled)
            XCTAssertEqual(enabled, previous & ~UINT(MFS_DISABLED))
        }
    }
}
