import CUIAInterop
import SwiftWindowsCore

/// Query computation over one copied accessibility projection.
///
/// Creating this value does not read a live tree or native geometry. The bridge
/// still captures a fresh projection at each existing query callback; this value
/// does not establish a cache, delivery lifetime, or another threading contract.
package struct UIAQuerySnapshot: Sendable {
    private static let noElement = UInt64.max
    private static let defaultClassName = "SwiftWindowsUI.View"

    private let elements: [UIAElementSnapshot]

    package init(_ elements: [UIAElementSnapshot]) {
        self.elements = elements
    }

    package func navigate(_ element: UInt64, direction: Int32) -> UInt64 {
        guard let current = elements.first(where: { $0.id == element }) else { return Self.noElement }
        switch direction {
        case Int32(SWU_UIA_NAV_PARENT):
            return current.parentID ?? Self.noElement
        case Int32(SWU_UIA_NAV_FIRST_CHILD):
            return elements.first(where: { $0.parentID == element })?.id ?? Self.noElement
        case Int32(SWU_UIA_NAV_LAST_CHILD):
            return elements.last(where: { $0.parentID == element })?.id ?? Self.noElement
        case Int32(SWU_UIA_NAV_NEXT_SIBLING), Int32(SWU_UIA_NAV_PREVIOUS_SIBLING):
            guard let parentID = current.parentID else { return Self.noElement }
            let siblings = elements.filter { $0.parentID == parentID }
            guard let index = siblings.firstIndex(where: { $0.id == element }) else { return Self.noElement }
            let target = direction == Int32(SWU_UIA_NAV_NEXT_SIBLING) ? index + 1 : index - 1
            guard siblings.indices.contains(target) else { return Self.noElement }
            return siblings[target].id
        default:
            return Self.noElement
        }
    }

    package func boundingRectangle(_ element: UInt64) -> Rect {
        elements.first(where: { $0.id == element })?.bounds
            ?? Rect(x: 0, y: 0, width: 0, height: 0)
    }

    package func stringProperty(_ element: UInt64, property: Int32) -> String? {
        guard let snapshot = elements.first(where: { $0.id == element }) else { return nil }
        switch property {
        case Int32(SWU_UIA_STRING_NAME):
            return snapshot.name
        case Int32(SWU_UIA_STRING_VALUE):
            return snapshot.value
        case Int32(SWU_UIA_STRING_HELP_TEXT):
            return snapshot.helpText
        case Int32(SWU_UIA_STRING_AUTOMATION_ID):
            return snapshot.automationID
        case Int32(SWU_UIA_STRING_CLASS_NAME):
            return snapshot.className ?? Self.defaultClassName
        default:
            return nil
        }
    }

    package func controlType(_ element: UInt64) -> Int32 {
        elements.first(where: { $0.id == element })?.controlType
            ?? Int32(SWU_UIA_CONTROL_TYPE_GROUP)
    }

    package func boolProperty(_ element: UInt64, property: Int32) -> Int32 {
        guard let snapshot = elements.first(where: { $0.id == element }) else { return -1 }
        switch property {
        case Int32(SWU_UIA_BOOL_IS_ENABLED):
            return snapshot.isEnabled ? 1 : 0
        case Int32(SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS):
            return snapshot.hasKeyboardFocus ? 1 : 0
        case Int32(SWU_UIA_BOOL_IS_KEYBOARD_FOCUSABLE):
            return snapshot.isKeyboardFocusable ? 1 : 0
        case Int32(SWU_UIA_BOOL_IS_OFFSCREEN):
            guard let isOffscreen = snapshot.isOffscreen else { return -1 }
            return isOffscreen ? 1 : 0
        case Int32(SWU_UIA_BOOL_IS_PASSWORD):
            return snapshot.isPassword ? 1 : 0
        case Int32(SWU_UIA_BOOL_IS_READ_ONLY):
            guard snapshot.supportsValue else { return -1 }
            return snapshot.isReadOnly ? 1 : 0
        case Int32(SWU_UIA_BOOL_IS_SELECTED):
            guard let isSelected = snapshot.isSelected else { return -1 }
            return isSelected ? 1 : 0
        default:
            return -1
        }
    }

    package func hasInvokeAction(_ element: UInt64) -> Int32 {
        elements.first(where: { $0.id == element })?.hasDefaultAction == true ? 1 : 0
    }

    package func supportsPattern(_ element: UInt64, pattern: Int32) -> Int32 {
        guard let snapshot = elements.first(where: { $0.id == element }) else { return 0 }
        switch pattern {
        case Int32(SWU_UIA_PATTERN_VALUE):
            return snapshot.supportsValue && !snapshot.isPassword ? 1 : 0
        case Int32(SWU_UIA_PATTERN_TOGGLE):
            return snapshot.toggleState != nil ? 1 : 0
        case Int32(SWU_UIA_PATTERN_SELECTION):
            return snapshot.supportsSelection ? 1 : 0
        case Int32(SWU_UIA_PATTERN_SELECTION_ITEM):
            return snapshot.isSelected != nil ? 1 : 0
        case Int32(SWU_UIA_PATTERN_VIRTUALIZED_ITEM):
            return snapshot.isVirtualizedPlaceholder ? 1 : 0
        case Int32(SWU_UIA_PATTERN_ITEM_CONTAINER):
            return snapshot.supportsItemContainer ? 1 : 0
        default:
            return 0
        }
    }

    package func toggleState(_ element: UInt64) -> Int32 {
        elements.first(where: { $0.id == element })?.toggleState?.rawValue ?? -1
    }

    package func selectionContainer(_ element: UInt64) -> UInt64 {
        guard let snapshot = elements.first(where: { $0.id == element }), snapshot.isSelected != nil else {
            return Self.noElement
        }
        var parentID = snapshot.parentID
        while let candidate = parentID, let parent = elements.first(where: { $0.id == candidate }) {
            if parent.supportsSelection { return parent.id }
            parentID = parent.parentID
        }
        return Self.noElement
    }

    package func selection(_ element: UInt64) -> [UInt64]? {
        guard elements.first(where: { $0.id == element })?.supportsSelection == true else { return nil }
        return elements.filter { snapshot in
            guard snapshot.isSelected == true else { return false }
            var parentID = snapshot.parentID
            while let candidate = parentID, let parent = elements.first(where: { $0.id == candidate }) {
                if parent.supportsSelection { return parent.id == element }
                parentID = parent.parentID
            }
            return false
        }.map(\.id)
    }

    package func elementFromPoint(x: Double, y: Double) -> UInt64 {
        var best: UIAElementSnapshot?
        var bestDepth = -1
        for snapshot in elements {
            let bounds = snapshot.bounds
            guard x >= bounds.origin.x, x < bounds.origin.x + bounds.size.width,
                y >= bounds.origin.y, y < bounds.origin.y + bounds.size.height
            else { continue }
            let depth = depthOfElement(snapshot)
            if depth > bestDepth {
                best = snapshot
                bestDepth = depth
            }
        }
        return best?.id ?? Self.noElement
    }

    package func focusedElement() -> UInt64 {
        elements.first(where: { $0.hasKeyboardFocus })?.id ?? Self.noElement
    }

    private func depthOfElement(_ snapshot: UIAElementSnapshot) -> Int {
        var depth = 0
        var parentID = snapshot.parentID
        while let current = parentID {
            depth += 1
            parentID = elements.first(where: { $0.id == current })?.parentID
        }
        return depth
    }
}
