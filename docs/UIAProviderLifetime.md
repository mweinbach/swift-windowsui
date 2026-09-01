# UI Automation provider lifetime

`UIAProviderBridge` owns its tree source, but escaped COM providers do not own
the bridge or that source. Every provider created by one bridge shares an
owned `SWUUIAProviderContext`. The context retains a small Swift box whose
bridge reference is weak. Descendants and held pattern interfaces keep this
context alive until their final COM reference is released.

The native context contains an immutable callback table, an atomic reference
count, and an atomic availability flag. Availability changes only from live
to revoked. Revocation never destroys the table or its Swift box: a callback
already in progress still needs that storage. Final context destruction calls
its release hook exactly once. Successful context creation adopts one retained
box reference; failed creation leaves that reference with the caller.

The original C creation functions retain their borrowed-context contract.
Their caller must keep its callback context alive for every provider it creates.
The additive `WithContext` factories are the owned route used by the Swift
bridge. All descendants, fragment roots, selection containers, selection
results, focus results, and event providers use the same context as their
originating bridge.

Owned Win32 attachments explicitly mark their original HWND root as using
HWND-derived runtime identity. This lets cleanup resolve a private identity
after the public family is revoked, without restoring any escaped provider.
See [Owned HWND root shutdown identity](UIAOwnedRootShutdown.md) for the
restricted factory, full-call drain requirement, HRESULT behavior, and the
separate source-only regression evidence.

## Callback admission and release

C++ methods hold a temporary reference to their provider across callbacks and
outbound native calls. They check availability before each callback and after
it returns, before invoking another callback or publishing a result. Revocation
therefore also rejects a held pattern interface; rejecting only new pattern
lookups would leave already acquired interfaces callable.

Swift C trampolines retain the box without reading its actor-isolated state.
The existing synchronous main dispatch runs before weak bridge promotion. A
successful promotion pins the bridge until that source callback finishes. Only
Sendable values cross this dispatch; C buffer decoding and output copying stay
in the nonisolated marshalling code. If weak promotion fails before the
bridge's isolated destructor runs, the trampoline revokes the native family.

Native availability changes at that explicit revocation, not at Swift weak
zeroing. Before a deferred isolated destructor runs, callback-free metadata
queries may still succeed and create a provider that retains only the context.
They cannot call a missing bridge. The next source callback detects the missing
bridge before admission, and every operational method rejects after revocation.

The box's native context pointer is borrowed. It is accessed only inside a
callback whose provider already pins that context. The box has no custom or
isolated destructor: its final release on a COM thread only destroys weak
storage. No provider reference holds application state through this box.

`disconnect()` revokes the entire family before attempting native cleanup,
including when no root provider has yet been created. It prevents new
`WM_GETOBJECT` publication, event publication, and provider creation. A failed
native disconnect cannot restore availability or schedule a retry. The bridge
destructor revokes locally and releases its references without making an
outbound COM call. A different bridge has a different context and is unaffected.

The bridge pins borrowed provider arguments across native calls and balances
those temporary references. A reentrant disconnect suppresses the outer
`WM_GETOBJECT` result as well as nested publication. Native effects already
started cannot be undone; any provider reference retained by Windows is inert
after local revocation.

Each admitted outbound event call also keeps the bridge and source alive through
the native callback. An explicit Swift lifetime fence outlasts the temporary
provider-release defer. This pin ends with the operation; escaped providers do
not inherit it, and it cannot restore revoked availability. `WM_GETOBJECT`
already keeps the bridge live through its post-callback availability check.

## COM results

`QueryInterface` uses a static, callback-free set of implemented interfaces.
Dynamic UIA pattern exposure remains in `GetPatternProvider`. `AddRef`,
`Release`, and interface identity remain usable after revocation.

| Call condition | Result |
| --- | --- |
| Invalid required pointer or input | Existing `E_POINTER` or `E_INVALIDARG` |
| Revoked provider family, including when a callback finds no bridge | `UIA_E_ELEMENTNOTAVAILABLE` |
| Result partly created before reentrant revocation | Release it and return empty output |
| Live missing destination, unsupported pattern/property, or ordinary action rejection | Existing live semantics |

Failure outputs are initialized: interface pointers, BSTRs, and SAFEARRAYs are
null; VARIANTs are empty; scalar and rectangle outputs are zero. An admitted
action may itself close the owner. A subsequent unavailable HRESULT does not
mean that action never ran and must not cause an automatic retry.

`UIAProviderLifetimeTests` uses real headless COM objects and HRESULT-preserving
helpers, with native effects injected per bridge. Its cases cover escaped
providers and patterns, final release, reentrant cleanup, unavailable outputs,
independent bridges, and main-actor routing. All existing UIA fixtures remain
unchanged. Source review and formatting do not substitute for compiling or
executing these tests.

This lifetime contract does not qualify every deadlock scenario in the existing
synchronous COM/main-thread dispatch, native disconnect success, or real
Narrator behavior. It does not change the runtime projection's modal or command
admission policy. Native UIA may retain an inert provider after disconnect
failure; that retained object must not retain the bridge, host, or runtime.

An owned `Win32Window` also requests Windows' raised-event-map cleanup with
`UiaReturnRawElementProvider(hwnd, 0, 0, NULL)`. The C wrapper forwards exactly
that null-provider shape when the HWND is non-null; other null-provider inputs
remain no-ops. Its non-null-provider path and public C signature are unchanged.
The documented return is zero, not an HRESULT or proof that any particular
provider reference was released. [Microsoft's cleanup contract](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcoreapi/nf-uiautomationcoreapi-uiareturnrawelementprovider)

The normal request follows `windowWillClose` in `WM_DESTROY`, before the
existing optional quit message. `WM_NCDESTROY` provides a fallback before the
default procedure and backpointer removal. Cleanup does not depend on a current
provider, a listening client, or an already-published live handle: partial
creation can own an HWND while `nativeHandle` is still nil. Admission checks
the captured close-lifetime identity, the incoming HWND, the retained native
ownership, and its exact backpointer. It claims that lifetime immediately
before the native request and performs no cleanup-state writes afterward.
The normal and fallback routes therefore share one request per owned lifetime,
including native reentry and recreation of the same Swift window object.

`WM_GETOBJECT` rejects destruction before invoking a provider, then rechecks
the same lifetime and ownership after provider and default-procedure callbacks.
A nil provider result cannot fall through on a destroyed or replaced HWND.
The claim also prevents publication during an NC-only fallback. `create()`
rejects reentry while the native retained-self ownership is outstanding, even
when the published handle is nil. No outbound COM cleanup was added to a
destructor, and these HWND rules do not replace a bridge's sticky local
revocation or change the existing main-thread callback dispatch.

Native destruction can recurse. A saved and restored NC-dispatch scope also
blocks recreation through the outer window-procedure thunk's retained-self
release and dispatch-exit completion callbacks, even if an inner destruction
already consumed that reference. A scoped strong window pin and the guard end
only after the existing dispatch scope returns. This denies recreation of the
same `Win32Window` during its teardown; unrelated windows remain independent.
The NC handler rechecks exact ownership after each cleanup/default-procedure
or timer-stop boundary before touching a potentially replaced HWND. This is
a per-window synchronous scope, not a new queue or dispatch mechanism.
[Microsoft's recursive destruction example](https://devblogs.microsoft.com/oldnewthing/20050727-16/?p=34793).

`Win32UIAWindowCleanupTests` uses per-window cleanup and `WM_GETOBJECT` default
procedure adapters. A one-shot package creation-rejection flag is consumed by
the next `create()` call and bound to its admitted lifetime; it cannot carry
over from a failed attempt. The owned `WM_NCCREATE` handler can then reject
that attempt after the backpointer is installed. Microsoft documents that
this produces a real `WM_NCDESTROY` without `WM_DESTROY`. The fixtures do not
send synthetic destruction messages or show their owned windows.
[Creation/destruction ordering](https://devblogs.microsoft.com/oldnewthing/20050726-00/?p=34803),
[WM_NCCREATE result contract](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-nccreate).

The authored fixtures distinguish cleanup-request ordering from native map
release. An injected recorder proves the requested HWND and call count, not
that the C wrapper reached Windows or that a real accessibility client released
its references. Actual creation-failure message ordering, map-reference release,
and real Narrator behavior require separate execution evidence; source review,
contracts, and formatting do not establish those outcomes.

The relevant external contracts are Microsoft's
[static QueryInterface rules](https://learn.microsoft.com/en-us/windows/win32/com/rules-for-implementing-queryinterface),
[disconnect requirements and reentry warning](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcoreapi/nf-uiautomationcoreapi-uiadisconnectprovider),
[window event-map cleanup](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcoreapi/nf-uiautomationcoreapi-uiareturnrawelementprovider),
the [provider ownership example](https://github.com/microsoft/Windows-classic-samples/blob/main/Samples/UIAutomationSimpleProvider/cpp/Control.cpp),
Swift's [implicit deinitializer isolation rules](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0371-isolated-synchronous-deinit.md),
and the [explicit lifetime-fence pattern](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0465-nonescapable-stdlib-primitives.md#lifetime-management).
