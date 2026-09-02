import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Pointer and keyboard secondary opening, with primary activation unchanged.
/// Native ExpandCollapse, Alt+Down, and long-press behavior are not covered.
@MainActor
final class MenuPrimaryActionRoutingTests: XCTestCase {
    func testVisibleIndicatorOpensWithoutPrimaryActivationOrAnotherFocusOwner() async {
        for indicator in [MenuIndicatorSetting.automatic, .styleHiddenWithVisibleOverride] {
            let fixture = MenuPrimaryRoutingFixture(indicator: indicator)
            guard let disclosure = fixture.disclosure else {
                return XCTFail("Expected a visible menu indicator")
            }
            XCTAssertFalse(disclosure.isFocusable)
            XCTAssertTrue(disclosure.isAccessibilityHidden)

            fixture.click(disclosure)

            XCTAssertTrue(fixture.trigger.isFocused)
            XCTAssertEqual(fixture.counts.primary, 0)
            XCTAssertEqual(fixture.counts.items, 0)
            XCTAssertEqual(fixture.counts.invalidations, 1)
            fixture.rebuild()
            XCTAssertTrue(fixture.isOpen)
        }
    }

    func testBodyPointerActivationRemainsPrimary() async {
        let fixture = MenuPrimaryRoutingFixture()
        fixture.click(fixture.label)

        XCTAssertEqual(fixture.counts.primary, 1)
        XCTAssertEqual(fixture.counts.items, 0)
        fixture.rebuild()
        XCTAssertFalse(fixture.isOpen)
    }

    func testEnterSpaceAndTheirRepeatEventsRemainPrimary() async {
        let fixture = MenuPrimaryRoutingFixture()
        fixture.focusTrigger()

        for key in [KeyboardKey.enter, .space] {
            fixture.runtime.keyDown(KeyboardEvent(keyCode: key.rawValue))
            fixture.runtime.keyDown(KeyboardEvent(keyCode: key.rawValue, isRepeat: true))
        }

        XCTAssertEqual(fixture.counts.primary, 4)
        XCTAssertEqual(fixture.counts.items, 0)
        XCTAssertEqual(fixture.counts.invalidations, 4)
        fixture.rebuild()
        XCTAssertFalse(fixture.isOpen)
    }

    func testUIAInvokeStillPerformsOnlyThePrimaryAction() async {
        let fixture = MenuPrimaryRoutingFixture()
        guard let snapshot = fixture.source.uiaElementSnapshots().first(where: { $0.name == "ACTIONS" }) else {
            return XCTFail("Expected the menu's accessible primary button")
        }
        XCTAssertTrue(snapshot.hasDefaultAction)
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: snapshot.id))

        XCTAssertEqual(fixture.counts.primary, 1)
        XCTAssertEqual(fixture.counts.items, 0)
        fixture.rebuild()
        XCTAssertFalse(fixture.isOpen)
    }

    func testPointerCrossingAndCancellationDoNotMixPrimaryAndSecondaryActions() async {
        for sequence in 0..<3 {
            let fixture = MenuPrimaryRoutingFixture()
            guard let disclosure = fixture.disclosure else {
                return XCTFail("Expected a visible menu indicator")
            }
            let bodyPoint = fixture.center(of: fixture.label)
            let indicatorPoint = fixture.center(of: disclosure)

            switch sequence {
            case 0:
                fixture.runtime.pointerDown(at: bodyPoint)
                fixture.runtime.pointerUp(at: indicatorPoint)
            case 1:
                fixture.runtime.pointerDown(at: indicatorPoint)
                fixture.runtime.pointerUp(at: bodyPoint)
            default:
                fixture.runtime.pointerDown(at: indicatorPoint)
                fixture.runtime.pointerCancelled()
                fixture.runtime.pointerUp(at: indicatorPoint)
            }

            XCTAssertEqual(fixture.counts.primary, 0, "Pointer sequence \(sequence)")
            XCTAssertEqual(fixture.counts.invalidations, 0, "Pointer sequence \(sequence)")
            fixture.rebuild()
            XCTAssertFalse(fixture.isOpen, "Pointer sequence \(sequence)")
        }
    }

    func testF4OpensWithVisibleHiddenAndStyleHiddenIndicators() async {
        for indicator in [MenuIndicatorSetting.automatic, .hidden, .styleHidden] {
            let fixture = MenuPrimaryRoutingFixture(indicator: indicator)
            if indicator != .automatic {
                XCTAssertNil(fixture.disclosure)
            }
            fixture.focusTrigger()
            fixture.pressF4()

            XCTAssertEqual(fixture.counts.primary, 0)
            XCTAssertEqual(fixture.counts.items, 0)
            XCTAssertEqual(fixture.counts.invalidations, 1)
            fixture.rebuild()
            XCTAssertTrue(fixture.isOpen)
        }
    }

    func testF4OpensInsideAScrollingParentWithoutScrollingIt() async {
        let fixture = MenuPrimaryRoutingFixture(indicator: .hidden, scrolling: true)
        guard let scroll = fixture.scroll else {
            return XCTFail("Expected a scroll parent")
        }
        XCTAssertGreaterThan(scroll.resolvedContentSize.height, scroll.resolvedFrame.height)
        XCTAssertFalse(fixture.trigger.interceptsVerticalArrowKeys)
        fixture.focusTrigger()
        let offset = scroll.scrollOffset
        fixture.pressF4()

        XCTAssertEqual(scroll.scrollOffset, offset)
        XCTAssertEqual(fixture.counts.primary, 0)
        fixture.rebuild()
        XCTAssertTrue(fixture.isOpen)
        XCTAssertEqual(scroll.scrollOffset, offset)
    }

    func testAuthoredF4ShortcutsKeepPrecedenceOverSecondaryOpening() async {
        for shortcutIsOnMenu in [true, false] {
            let fixture = MenuPrimaryRoutingFixture()
            let shortcut = KeyboardShortcutBinding(keyCode: 0x73)
            if shortcutIsOnMenu {
                fixture.trigger.keyboardShortcuts = [shortcut]
            } else {
                let counts = fixture.counts
                let other = ViewNode(frame: Rect(x: 400, y: 40, width: 100, height: 32))
                other.isFocusable = true
                other.keyboardShortcuts = [shortcut]
                other.onActivate = { counts.shortcuts += 1 }
                fixture.runtime.root.addChild(other)
            }
            fixture.focusTrigger()
            fixture.pressF4()

            XCTAssertEqual(fixture.counts.primary, shortcutIsOnMenu ? 1 : 0)
            XCTAssertEqual(fixture.counts.shortcuts, shortcutIsOnMenu ? 0 : 1)
            fixture.rebuild()
            XCTAssertFalse(fixture.isOpen)
        }
    }

    func testModifiedRepeatedAndUnfocusedF4DoNotOpenTheMenu() async {
        let fixture = MenuPrimaryRoutingFixture()
        fixture.pressF4()
        XCTAssertEqual(fixture.counts.invalidations, 0)
        fixture.focusTrigger()

        for modifiers in [KeyboardModifiers.shift, .control, .alt, [.control, .shift]] {
            fixture.pressF4(modifiers: modifiers)
        }
        fixture.pressF4(isRepeat: true)

        XCTAssertEqual(fixture.counts.primary, 0)
        XCTAssertEqual(fixture.counts.invalidations, 0)
        fixture.rebuild()
        XCTAssertFalse(fixture.isOpen)
    }

    func testDisabledMenusExposeNoWorkingPrimaryOrSecondaryRoute() async {
        for indicator in [MenuIndicatorSetting.automatic, .hidden] {
            let fixture = MenuPrimaryRoutingFixture(indicator: indicator, enabled: false)
            if let disclosure = fixture.disclosure {
                XCTAssertFalse(disclosure.isHitTestVisible)
                XCTAssertNil(disclosure.onActivate)
                fixture.click(disclosure)
            }
            fixture.click(fixture.label)
            fixture.trigger.onKeyDown?(KeyboardEvent(keyCode: 0x73))
            fixture.pressF4()
            guard let snapshot = fixture.source.uiaElementSnapshots().first(where: { $0.name == "ACTIONS" }) else {
                return XCTFail("Expected the disabled menu's accessible button")
            }
            XCTAssertFalse(snapshot.isEnabled)
            XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: snapshot.id))

            XCTAssertEqual(fixture.counts.primary, 0)
            XCTAssertEqual(fixture.counts.items, 0)
            XCTAssertEqual(fixture.counts.invalidations, 0)
            fixture.rebuild()
            XCTAssertFalse(fixture.isOpen)
        }
    }

    func testItemPointerSelectionDismissesAndRestoresPrimaryFocus() async {
        let fixture = MenuPrimaryRoutingFixture()
        guard let disclosure = fixture.disclosure else {
            return XCTFail("Expected a visible menu indicator")
        }
        fixture.click(disclosure)
        fixture.rebuild()
        guard let item = fixture.item else {
            return XCTFail("Expected the opened menu item")
        }
        fixture.click(item)
        fixture.rebuild()

        XCTAssertEqual(fixture.counts.items, 1)
        XCTAssertEqual(fixture.counts.primary, 0)
        XCTAssertFalse(fixture.isOpen)
        XCTAssertTrue(fixture.trigger.isFocused)
    }

    func testEnterAfterF4SelectsThePopupItemInsteadOfThePrimaryAction() async {
        let fixture = MenuPrimaryRoutingFixture(indicator: .hidden)
        fixture.focusTrigger()
        fixture.pressF4()
        fixture.rebuild()
        XCTAssertTrue(fixture.isOpen)

        fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
        fixture.rebuild()

        XCTAssertEqual(fixture.counts.items, 1)
        XCTAssertEqual(fixture.counts.primary, 0)
        XCTAssertFalse(fixture.isOpen)
        XCTAssertTrue(fixture.trigger.isFocused)
    }

    func testEscapeAfterSecondaryOpeningDismissesAndRestoresPrimaryFocus() async {
        let fixture = MenuPrimaryRoutingFixture(indicator: .hidden)
        fixture.focusTrigger()
        fixture.pressF4()
        fixture.rebuild()
        guard let item = fixture.item else {
            return XCTFail("Expected the opened menu item")
        }
        fixture.runtime.requestFocus(item)
        fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))
        fixture.rebuild()

        XCTAssertEqual(fixture.counts.items, 0)
        XCTAssertEqual(fixture.counts.primary, 0)
        XCTAssertFalse(fixture.isOpen)
        XCTAssertTrue(fixture.trigger.isFocused)
    }

    func testOutsidePointerDismissalRestoresPrimaryFocus() async {
        let fixture = MenuPrimaryRoutingFixture()
        fixture.focusTrigger()
        fixture.pressF4()
        fixture.rebuild()
        XCTAssertTrue(fixture.isOpen)

        fixture.runtime.pointerDown(at: Point(x: 600, y: 420))
        fixture.runtime.pointerUp(at: Point(x: 600, y: 420))
        fixture.rebuild()

        XCTAssertEqual(fixture.counts.items, 0)
        XCTAssertEqual(fixture.counts.primary, 0)
        XCTAssertFalse(fixture.isOpen)
        XCTAssertTrue(fixture.trigger.isFocused)
    }

    func testOrdinaryMenusKeepBodyAndIndicatorActivationWithoutAnF4Shortcut() async {
        for clickIndicator in [false, true] {
            let fixture = MenuPrimaryRoutingFixture(hasPrimaryAction: false)
            fixture.focusTrigger()
            fixture.pressF4()
            XCTAssertEqual(fixture.counts.invalidations, 0)
            let target = clickIndicator ? fixture.disclosure : fixture.label
            guard let target else {
                return XCTFail("Expected ordinary menu content")
            }
            fixture.click(target)
            fixture.rebuild()

            XCTAssertTrue(fixture.isOpen)
            XCTAssertEqual(fixture.counts.primary, 0)
            XCTAssertEqual(fixture.counts.items, 0)
        }
    }

    func testClosedMenuKeepsOneNamedAccessibleFocusOwner() async {
        for indicator in [MenuIndicatorSetting.automatic, .hidden] {
            let fixture = MenuPrimaryRoutingFixture(indicator: indicator)
            let focusable = fixture.nodes.filter(\.isFocusable)
            XCTAssertEqual(focusable.count, 1)
            XCTAssertTrue(focusable.first === fixture.trigger)
            let snapshots = fixture.source.uiaElementSnapshots()
            let buttons = snapshots.filter { $0.name == "ACTIONS" }
            XCTAssertEqual(buttons.count, 1)
            XCTAssertTrue(buttons.first?.isKeyboardFocusable == true)
            XCTAssertEqual(snapshots.filter(\.hasDefaultAction).count, 1)
            XCTAssertFalse(snapshots.contains { $0.name == ">" || $0.name == "V" })

            fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
            XCTAssertTrue(fixture.trigger.isFocused)
            fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
            XCTAssertTrue(fixture.trigger.isFocused)
        }
    }
}

private enum MenuIndicatorSetting: Equatable {
    case automatic
    case hidden
    case styleHidden
    case styleHiddenWithVisibleOverride
}

@MainActor
private final class MenuPrimaryRoutingCounts {
    var primary = 0
    var items = 0
    var shortcuts = 0
    var invalidations = 0
}

@MainActor
private final class MenuPrimaryRoutingFixture {
    let runtime: RetainedViewRuntime
    let source: RuntimeUIAElementTreeSource
    let counts: MenuPrimaryRoutingCounts
    let scroll: ViewNode?
    private let parent: ViewNode
    private let view: AnyView
    private let context: ViewBuildContext
    private(set) var node: ViewNode

    init(
        indicator: MenuIndicatorSetting = .automatic,
        enabled: Bool = true,
        scrolling: Bool = false,
        hasPrimaryAction: Bool = true
    ) {
        let counts = MenuPrimaryRoutingCounts()
        self.counts = counts
        let menu: AnyView
        if hasPrimaryAction {
            menu = AnyView(
                Menu("ACTIONS") {
                    Button("EXPORT") { counts.items += 1 }
                } primaryAction: {
                    counts.primary += 1
                })
        } else {
            menu = AnyView(Menu("ACTIONS") { Button("EXPORT") { counts.items += 1 } })
        }
        let styledMenu: AnyView
        switch indicator {
        case .automatic:
            styledMenu = menu
        case .hidden:
            styledMenu = AnyView(menu.menuIndicator(.hidden))
        case .styleHidden:
            styledMenu = AnyView(menu.menuStyle(BorderlessButtonMenuStyle(showsMenuIndicator: false)))
        case .styleHiddenWithVisibleOverride:
            styledMenu = AnyView(
                menu.menuStyle(BorderlessButtonMenuStyle(showsMenuIndicator: false)).menuIndicator(.visible))
        }
        view = enabled ? styledMenu : AnyView(styledMenu.disabled(true))
        context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 640, height: 480) },
            invalidateHandler: { counts.invalidations += 1 })
        let runtime = RetainedViewRuntime(root: ViewNode())
        self.runtime = runtime
        runtime.setRootSize(IntSize(width: 640, height: 480))
        source = RuntimeUIAElementTreeSource(runtime: runtime)
        if scrolling {
            let scroll = ViewNode(frame: Rect(x: 0, y: 0, width: 420, height: 180), clipsToBounds: true)
            scroll.scrollAxis = .vertical
            scroll.addChild(
                ViewNode(frame: Rect(x: 0, y: 650, width: 100, height: 50), isHitTestVisible: false))
            runtime.root.addChild(scroll)
            self.scroll = scroll
            parent = scroll
        } else {
            scroll = nil
            parent = runtime.root
        }
        node = ViewNode()
        rebuild()
        counts.invalidations = 0
    }

    var trigger: ViewNode { node.children[0] }
    var nodes: [ViewNode] { descendants(of: node) }
    var label: ViewNode { descendants(of: trigger).first { $0.text == "ACTIONS" }! }
    var disclosure: ViewNode? { descendants(of: trigger).first { $0.text == ">" || $0.text == "V" } }
    var item: ViewNode? {
        nodes.first { $0.isFocusable && descendants(of: $0).contains { $0.text == "EXPORT" } }
    }
    var isOpen: Bool { nodes.contains { $0.nodeTag == "menu-overlay" } }

    func rebuild() {
        node.removeFromParent()
        node = view.makeComponent(context: context).makeNode(runtime: runtime)
        node.frame = Rect(x: 40, y: 40, width: 160, height: 40)
        parent.addChild(node)
        _ = runtime.renderScene()
    }

    func focusTrigger() {
        runtime.requestFocus(trigger)
        XCTAssertTrue(trigger.isFocused)
    }

    func pressF4(modifiers: KeyboardModifiers = [], isRepeat: Bool = false) {
        runtime.keyDown(KeyboardEvent(keyCode: 0x73, modifiers: modifiers, isRepeat: isRepeat))
    }

    func click(_ target: ViewNode) {
        let point = center(of: target)
        runtime.pointerDown(at: point)
        runtime.pointerUp(at: point)
    }

    func center(of target: ViewNode) -> Point {
        var point = Point(x: target.resolvedFrame.width / 2, y: target.resolvedFrame.height / 2)
        var ancestor: ViewNode? = target
        while let node = ancestor {
            point.x += node.resolvedFrame.origin.x
            point.y += node.resolvedFrame.origin.y
            ancestor = node.parent
        }
        return point
    }

    private func descendants(of node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { descendants(of: $0) }
    }
}
