import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUIDisabledAccessibilityInvokeTests: XCTestCase {
    func testDisabledElementCannotInvokeItsExplicitAccessibilityAction() async {
        await MainActor.run {
            let fixture = DisabledAccessibilityInvokeFixture()
            var invocationCount = 0
            fixture.button.accessibilityActions = [
                RetainedAccessibilityAction(kind: .default) {
                    invocationCount += 1
                }
            ]
            fixture.button.accessibilityRespondsToUserInteraction = false

            guard let snapshot = fixture.snapshot else {
                return XCTFail("Expected a projected disabled accessibility element")
            }

            XCTAssertFalse(snapshot.isEnabled)
            XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: snapshot.id))
            XCTAssertEqual(invocationCount, 0)
        }
    }

    func testDisabledElementCannotBypassInvokeGuardThroughActivationFallback() async {
        await MainActor.run {
            let fixture = DisabledAccessibilityInvokeFixture()
            var activationCount = 0
            fixture.button.onActivate = {
                activationCount += 1
            }
            fixture.button.accessibilityRespondsToUserInteraction = false

            guard let snapshot = fixture.snapshot else {
                return XCTFail("Expected a projected disabled accessibility element")
            }

            XCTAssertFalse(snapshot.isEnabled)
            XCTAssertTrue(snapshot.hasDefaultAction)
            XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: snapshot.id))
            XCTAssertEqual(activationCount, 0)
        }
    }

    func testEnabledElementStillInvokesItsActivationFallback() async {
        await MainActor.run {
            let fixture = DisabledAccessibilityInvokeFixture()
            var activationCount = 0
            fixture.button.onActivate = {
                activationCount += 1
            }

            guard let snapshot = fixture.snapshot else {
                return XCTFail("Expected a projected enabled accessibility element")
            }

            XCTAssertTrue(snapshot.isEnabled)
            XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: snapshot.id))
            XCTAssertEqual(activationCount, 1)
        }
    }
}

@MainActor
private final class DisabledAccessibilityInvokeFixture {
    let runtime: RetainedViewRuntime
    let source: RuntimeUIAElementTreeSource
    let button: ViewNode

    init() {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 200))
        root.resolvedFrame = root.frame
        runtime = RetainedViewRuntime(root: root)

        button = ViewNode(frame: Rect(x: 12, y: 12, width: 120, height: 36))
        button.resolvedFrame = button.frame
        button.accessibilityLabel = "Save"
        button.accessibilityTraits = .isButton
        button.isFocusable = true
        root.addChild(button)

        source = RuntimeUIAElementTreeSource(runtime: runtime)
    }

    var snapshot: UIAElementSnapshot? {
        source.uiaElementSnapshots().first { $0.name == "Save" }
    }
}
