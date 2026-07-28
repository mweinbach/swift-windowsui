// COM ownership helpers shared by every renderer in this module.
//
// D3D11 objects are reference counted by hand, and the two places that
// historically leaked are (1) dropping the owner without releasing what it
// created and (2) passing a live stored property straight into a creation
// call's out-param, which overwrites the old pointer without releasing it.
// `detach()` on the render backends covers the first; `makeCOM(into:_:)`
// covers the second, so no call site has to remember the release.

import WinSDK

/// Releases the COM object `pointer` refers to and nils it. Safe to call on
/// an already-nil pointer, which makes it usable in `defer` and in the
/// renderers' teardown paths without guards.
func releaseCOM<T>(_ pointer: inout UnsafeMutablePointer<T>?) {
    guard let rawPointer = pointer else {
        return
    }

    let unknown = UnsafeMutableRawPointer(rawPointer).assumingMemoryBound(to: IUnknown.self)
    _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
    pointer = nil
}

/// Takes an additional reference on a COM object, for the cases where a
/// borrowed pointer has to be handed out with the same ownership as one
/// that came from a creation call.
func retainCOM<T>(_ pointer: UnsafeMutablePointer<T>) {
    let unknown = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: IUnknown.self)
    _ = unknown.pointee.lpVtbl.pointee.AddRef(unknown)
}

/// Runs a COM creation call and installs the result into `destination`,
/// releasing whatever `destination` already held.
///
/// Creation happens into a local, so the previous object is released only
/// once the replacement exists: a failed create leaves the old resource
/// intact rather than nil-ing the renderer's state, and a create that both
/// fails *and* writes an out-param cannot leak.
@discardableResult
func makeCOM<T>(
    into destination: inout UnsafeMutablePointer<T>?,
    _ create: (inout UnsafeMutablePointer<T>?) -> HRESULT
) -> HRESULT {
    var created: UnsafeMutablePointer<T>?
    let hr = create(&created)

    guard hr >= 0, created != nil else {
        releaseCOM(&created)
        return hr
    }

    releaseCOM(&destination)
    destination = created
    return hr
}
