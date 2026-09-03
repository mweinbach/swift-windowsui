import CUIAInterop

/// Internal held-handle operations only; no native TextPattern is advertised.
/// All actor values stay in the original bridge's numeric-ticket store.
enum UIANativeTextRangeCallbacks {
    static func make() -> SWUUIATextRangeCallbacks {
        var callbacks = SWUUIATextRangeCallbacks()
        callbacks.clone = { call, source, ticket in
            UIANativeTextRangeCallbacks.clone(call, source, ticket)
        }
        callbacks.compare = { call, left, right, result in
            UIANativeTextRangeCallbacks.compare(call, left, right, result)
        }
        callbacks.compareEndpoints = { call, left, endpoint, right, otherEndpoint, result in
            UIANativeTextRangeCallbacks.compareEndpoints(call, left, endpoint, right, otherEndpoint, result)
        }
        return callbacks
    }

    static func clone(_ call: OpaquePointer?, _ source: UInt64, _ ticket: UInt64) -> Int32 {
        guard let reply = UIANativeRequestDispatch.perform(call, .cloneTextRead(source: source, ticket: ticket))
        else {
            if SWU_UIACallStatus(call) >= 0 { UIANativeRequestDispatch.unexpectedReply(call) }
            return SWU_UIACallStatus(call)
        }
        guard case .integer(let registered) = reply else {
            UIANativeRequestDispatch.unexpectedReply(call)
            return SWU_UIACallStatus(call)
        }
        return registered == 1 ? 0 : UIANativeHRESULT.elementNotAvailable
    }

    static func compare(
        _ call: OpaquePointer?, _ left: UInt64, _ right: UInt64, _ result: UnsafeMutablePointer<Int32>?
    ) -> Int32 {
        peerResult(call, .compareTextReads(left: left, right: right), result)
    }

    static func compareEndpoints(
        _ call: OpaquePointer?, _ left: UInt64, _ endpoint: Int32,
        _ right: UInt64, _ otherEndpoint: Int32, _ result: UnsafeMutablePointer<Int32>?
    ) -> Int32 {
        guard let result else { return Int32(bitPattern: 0x8000_4003) }
        result.pointee = 0
        guard endpoint == 0 || endpoint == 1, otherEndpoint == 0 || otherEndpoint == 1 else {
            return Int32(bitPattern: 0x8007_0057)
        }
        return peerResult(
            call, .compareTextReadEndpoints(left: left, endpoint: endpoint, right: right, otherEndpoint: otherEndpoint),
            result)
    }

    private static func peerResult(
        _ call: OpaquePointer?, _ request: UIAProviderRequest, _ result: UnsafeMutablePointer<Int32>?
    ) -> Int32 {
        guard let result else { return Int32(bitPattern: 0x8000_4003) }
        result.pointee = 0
        guard let reply = UIANativeRequestDispatch.perform(call, request) else {
            if SWU_UIACallStatus(call) >= 0 { UIANativeRequestDispatch.unexpectedReply(call) }
            return SWU_UIACallStatus(call)
        }
        guard case .textRangePeer(let peer) = reply else {
            UIANativeRequestDispatch.unexpectedReply(call)
            return SWU_UIACallStatus(call)
        }
        switch peer {
        case .unavailable:
            return UIANativeHRESULT.elementNotAvailable
        case .incompatible:
            return Int32(bitPattern: 0x8007_0057)
        case .value(let value):
            result.pointee = value
            return 0
        }
    }
}
