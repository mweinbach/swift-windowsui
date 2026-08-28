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

The existing null-provider shortcut in `SWU_UIAReturnRawElementProvider` is
unchanged. It does not forward Windows' documented `WM_DESTROY` event-map
cleanup call with a null provider. That native cleanup remains separate from
the shared context's local revocation and memory safety.

The relevant external contracts are Microsoft's
[static QueryInterface rules](https://learn.microsoft.com/en-us/windows/win32/com/rules-for-implementing-queryinterface),
[disconnect requirements and reentry warning](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcoreapi/nf-uiautomationcoreapi-uiadisconnectprovider),
[window event-map cleanup](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcoreapi/nf-uiautomationcoreapi-uiareturnrawelementprovider),
the [provider ownership example](https://github.com/microsoft/Windows-classic-samples/blob/main/Samples/UIAutomationSimpleProvider/cpp/Control.cpp),
Swift's [implicit deinitializer isolation rules](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0371-isolated-synchronous-deinit.md),
and the [explicit lifetime-fence pattern](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0465-nonescapable-stdlib-primitives.md#lifetime-management).
