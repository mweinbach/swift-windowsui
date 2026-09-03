import SwiftWindowsCore

/// Values copied before crossing from a native provider call to the UI actor.
/// Native buffers, HWNDs, providers, and callback pointers never enter this value.
package enum UIAProviderRequest: Equatable, Sendable {
    case navigate(element: UInt64, direction: Int32)
    case runtimeID(element: UInt64)
    case boundingRectangle(element: UInt64)
    case stringProperty(element: UInt64, property: Int32)
    /// Internal source wiring only; no C callback or native TextPattern route.
    case textContent(element: UInt64)
    case controlType(element: UInt64)
    case boolProperty(element: UInt64, property: Int32)
    case hasInvokeAction(element: UInt64)
    case invokeDefaultAction(element: UInt64)
    case supportsPattern(element: UInt64, pattern: Int32)
    case setValue(element: UInt64, value: String)
    case toggleState(element: UInt64)
    case toggle(element: UInt64)
    case select(element: UInt64)
    case addToSelection(element: UInt64)
    case removeFromSelection(element: UInt64)
    case selectionContainer(element: UInt64)
    case selection(element: UInt64)
    case logicalItemState(element: UInt64)
    case findItem(container: UInt64, afterElement: UInt64?)
    case realizeVirtualizedItem(element: UInt64)
    case setFocus(element: UInt64)
    case elementFromPoint(x: Double, y: Double)
    case focusedElement
}

/// A callback's actual payload. Transport failure is carried separately by the
/// retained native call token; a failed HRESULT must never become a truthy int.
package enum UIAProviderReply: Equatable, Sendable {
    case element(UInt64)
    case runtimeID([Int32])
    case bounds(Rect)
    case string(String?)
    case integer(Int32)
    case selection([UInt64]?)
    case itemLookup(UIAItemContainerResult)
    case completed
}

package struct UIAProviderRequestEnvelope: Equatable, Sendable {
    package let windowKey: NativeWindowKey
    package let surfaceGeneration: UInt64
    package let geometry: NativeWindowGeometry
    package let request: UIAProviderRequest

    package init(surface: NativeWindowSurface, request: UIAProviderRequest) {
        windowKey = surface.key
        surfaceGeneration = surface.generation
        geometry = surface.geometry
        self.request = request
    }
}

package enum UIAProviderRequestFailure: Error, Equatable, Sendable {
    case invalidGeometry
    case unsupportedNativeItemLookup
}

/// Actor-prepared event values. The native owner checks actual client presence
/// and calls UI Automation; posting this value is not a native success result.
package enum UIAProviderNativeEvent: Sendable {
    case focusChanged(element: UInt64)
    case structureChanged
    case liveRegionChanged(element: UInt64)
}
