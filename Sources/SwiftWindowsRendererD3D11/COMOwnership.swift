// COM ownership helpers shared by every renderer in this module.
//
// D3D11 objects are reference counted by hand, and the two places that
// historically leaked are (1) dropping the owner without releasing what it
// created and (2) passing a live stored property straight into a creation
// call's out-param, which overwrites the old pointer without releasing it.
// `detach()` on the render backends covers the first; `makeCOM(into:_:)`
// covers the second, so no call site has to remember the release.

import Foundation
import WinSDK

/// The release-visible backstop for a renderer that was deallocated while
/// still attached.
///
/// `detach()` runs on the main actor because it drives the immediate
/// context, and a nonisolated `deinit` cannot get there — so the deinit
/// cannot free anything, and it deliberately does not try: enqueueing the
/// raw pointers onto the main actor would release objects at an
/// unpredictable later point, and at process teardown that work never runs
/// at all. What it *can* do is refuse to be silent. A debug-only
/// `assert` left a shipping build leaking a device, a swap chain (which
/// also pins a destroyed HWND), both glyph atlases, every cached path
/// texture and the blur ping-pong pair with no diagnostic whatsoever;
/// this writes the same message to stderr in every configuration and
/// counts the occurrence so a test can see it happen.
enum RendererTeardownBackstop {
    /// How many times the backstop has fired this process. Never reset in
    /// production; tests read and restore it.
    nonisolated(unsafe) static var undetachedTeardownCount = 0

    /// Set by tests that deliberately drop an attached renderer, so the
    /// debug trap does not abort the run they are trying to make.
    nonisolated(unsafe) static var suppressTrapForTesting = false

    /// Reports `message` to stderr, counts it, and traps in debug builds
    /// unless a test has opted out.
    static func reportUndetachedTeardown(_ message: String) {
        undetachedTeardownCount &+= 1
        let line = "[swift-windowsui] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        if !suppressTrapForTesting {
            assertionFailure(message)
        }
    }
}

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
