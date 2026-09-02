import CUIAInterop
import SwiftWindowsCore

/// Only these native trampolines touch C input/output storage. Requests and
/// actor replies contain copied Swift values; all allocations and buffer fills
/// finish before the enclosing full-call C lease is released.
enum UIANativeProviderCallbacks {
    static func make(
        context: UnsafeMutableRawPointer, supportsLogicalItems: Bool = false
    ) -> SWUUIACallCallbacks {
        var callbacks = SWUUIACallCallbacks()
        callbacks.context = context
        callbacks.navigate = { call, element, direction in
            UIANativeProviderCallbacks.elementReply(call, .navigate(element: element, direction: direction))
        }
        callbacks.getRuntimeId = { call, element, buffer, capacity in
            guard capacity >= 2, let buffer else { return 0 }
            let values = UIANativeProviderCallbacks.runtimeIDReply(call, .runtimeID(element: element))
            for (index, value) in values.prefix(Int(capacity)).enumerated() { buffer[index] = value }
            return Int32(clamping: values.count)
        }
        callbacks.getBoundingRectangle = { call, element, left, top, width, height in
            let bounds = UIANativeProviderCallbacks.boundsReply(call, .boundingRectangle(element: element))
            left?.pointee = bounds.origin.x
            top?.pointee = bounds.origin.y
            width?.pointee = bounds.size.width
            height?.pointee = bounds.size.height
        }
        callbacks.copyStringProperty = { call, element, property in
            guard
                let value = UIANativeProviderCallbacks.stringReply(
                    call, .stringProperty(element: element, property: property))
            else {
                return nil
            }
            var utf16 = Array(value.utf16)
            if utf16.isEmpty { utf16 = [0] }
            return utf16.withUnsafeBufferPointer {
                SWU_UIACreateBSTR($0.baseAddress, Int32(value.utf16.count))
            }
        }
        callbacks.getControlType = { call, element in
            UIANativeProviderCallbacks.integerReply(
                call, .controlType(element: element), unavailable: Int32(SWU_UIA_CONTROL_TYPE_GROUP))
        }
        callbacks.getBoolProperty = { call, element, property in
            UIANativeProviderCallbacks.integerReply(
                call, .boolProperty(element: element, property: property), unavailable: -1)
        }
        callbacks.hasInvokeAction = { call, element in
            UIANativeProviderCallbacks.integerReply(call, .hasInvokeAction(element: element), unavailable: 0)
        }
        callbacks.invokeDefaultAction = { call, element in
            _ = UIANativeProviderCallbacks.invokeDefaultActionResult(call, element)
        }
        callbacks.supportsPattern = { call, element, pattern in
            UIANativeProviderCallbacks.integerReply(
                call, .supportsPattern(element: element, pattern: pattern), unavailable: 0)
        }
        callbacks.setValue = { call, element, value, length in
            guard length >= 0, length <= 1_048_576, let value else { return 0 }
            let copied = String(decoding: UnsafeBufferPointer(start: value, count: Int(length)), as: UTF16.self)
            return UIANativeProviderCallbacks.integerReply(
                call, .setValue(element: element, value: copied), unavailable: 0)
        }
        callbacks.getToggleState = { call, element in
            UIANativeProviderCallbacks.integerReply(call, .toggleState(element: element), unavailable: -1)
        }
        callbacks.toggle = { call, element in
            UIANativeProviderCallbacks.integerReply(call, .toggle(element: element), unavailable: 0)
        }
        callbacks.select = { call, element in
            UIANativeProviderCallbacks.integerReply(call, .select(element: element), unavailable: 0)
        }
        callbacks.addToSelection = { call, element in
            UIANativeProviderCallbacks.integerReply(call, .addToSelection(element: element), unavailable: 0)
        }
        callbacks.removeFromSelection = { call, element in
            UIANativeProviderCallbacks.integerReply(call, .removeFromSelection(element: element), unavailable: 0)
        }
        callbacks.getSelectionContainer = { call, element in
            UIANativeProviderCallbacks.elementReply(call, .selectionContainer(element: element))
        }
        callbacks.getSelection = { call, element, buffer, capacity in
            guard capacity >= 0 else { return -1 }
            guard let selected = UIANativeProviderCallbacks.selectionReply(call, .selection(element: element)) else {
                return -1
            }
            if let buffer {
                for (index, value) in selected.prefix(Int(capacity)).enumerated() { buffer[index] = value }
            }
            return Int32(clamping: selected.count)
        }
        callbacks.realizeVirtualizedItem = { call, element in
            UIANativeProviderCallbacks.integerReply(call, .realizeVirtualizedItem(element: element), unavailable: 0)
        }
        if supportsLogicalItems {
            callbacks.getLogicalItemState = { call, element in
                UIANativeProviderCallbacks.integerReply(
                    call, .logicalItemState(element: element), unavailable: Int32(SWU_UIA_LOGICAL_ITEM_UNAVAILABLE))
            }
            callbacks.findItem = { call, container, after, result in
                result?.pointee = UInt64.max
                let lookup = UIANativeProviderCallbacks.itemLookupReply(
                    call, .findItem(container: container, afterElement: after == UInt64.max ? nil : after))
                switch lookup {
                case .item(let element):
                    result?.pointee = element
                    return Int32(SWU_UIA_ITEM_LOOKUP_FOUND)
                case .end:
                    return Int32(SWU_UIA_ITEM_LOOKUP_END)
                case .unavailable:
                    return Int32(SWU_UIA_ITEM_LOOKUP_UNAVAILABLE)
                case .invalidStart:
                    return Int32(SWU_UIA_ITEM_LOOKUP_INVALID_START)
                }
            }
        }
        callbacks.setFocus = { call, element in
            UIANativeProviderCallbacks.completeReply(call, .setFocus(element: element))
        }
        callbacks.elementFromPoint = { call, x, y in
            UIANativeProviderCallbacks.elementReply(call, .elementFromPoint(x: x, y: y))
        }
        callbacks.focusedElement = { call in
            UIANativeProviderCallbacks.elementReply(call, .focusedElement)
        }
        return callbacks
    }

    private static func elementReply(_ call: OpaquePointer?, _ request: UIAProviderRequest) -> UInt64 {
        guard let reply = UIANativeRequestDispatch.perform(call, request) else { return UInt64.max }
        guard case .element(let value) = reply else {
            UIANativeRequestDispatch.unexpectedReply(call)
            return UInt64.max
        }
        return value
    }

    private static func runtimeIDReply(_ call: OpaquePointer?, _ request: UIAProviderRequest) -> [Int32] {
        guard let reply = UIANativeRequestDispatch.perform(call, request) else { return [] }
        guard case .runtimeID(let value) = reply else {
            UIANativeRequestDispatch.unexpectedReply(call)
            return []
        }
        return value
    }

    private static func boundsReply(_ call: OpaquePointer?, _ request: UIAProviderRequest) -> Rect {
        guard let reply = UIANativeRequestDispatch.perform(call, request) else {
            return Rect(x: 0, y: 0, width: 0, height: 0)
        }
        guard case .bounds(let value) = reply else {
            UIANativeRequestDispatch.unexpectedReply(call)
            return Rect(x: 0, y: 0, width: 0, height: 0)
        }
        return value
    }

    private static func stringReply(_ call: OpaquePointer?, _ request: UIAProviderRequest) -> String? {
        guard let reply = UIANativeRequestDispatch.perform(call, request) else { return nil }
        guard case .string(let value) = reply else {
            UIANativeRequestDispatch.unexpectedReply(call)
            return nil
        }
        return value
    }

    static func invokeDefaultActionResult(_ call: OpaquePointer?, _ element: UInt64) -> Int32 {
        integerReply(call, .invokeDefaultAction(element: element), unavailable: 0)
    }

    private static func integerReply(
        _ call: OpaquePointer?, _ request: UIAProviderRequest, unavailable: Int32
    ) -> Int32 {
        guard let reply = UIANativeRequestDispatch.perform(call, request) else { return unavailable }
        guard case .integer(let value) = reply else {
            UIANativeRequestDispatch.unexpectedReply(call)
            return unavailable
        }
        return value
    }

    private static func selectionReply(_ call: OpaquePointer?, _ request: UIAProviderRequest) -> [UInt64]? {
        guard let reply = UIANativeRequestDispatch.perform(call, request) else { return nil }
        guard case .selection(let value) = reply else {
            UIANativeRequestDispatch.unexpectedReply(call)
            return nil
        }
        return value
    }

    private static func itemLookupReply(_ call: OpaquePointer?, _ request: UIAProviderRequest) -> UIAItemContainerResult
    {
        guard let reply = UIANativeRequestDispatch.perform(call, request) else { return .unavailable }
        guard case .itemLookup(let value) = reply else {
            UIANativeRequestDispatch.unexpectedReply(call)
            return .unavailable
        }
        return value
    }

    private static func completeReply(_ call: OpaquePointer?, _ request: UIAProviderRequest) {
        guard let reply = UIANativeRequestDispatch.perform(call, request) else { return }
        guard case .completed = reply else {
            UIANativeRequestDispatch.unexpectedReply(call)
            return
        }
    }
}
