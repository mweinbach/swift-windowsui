# Owned HWND root shutdown identity

The owned native smoke at `26390ef2f30b4aeb8cf022ab998eb5a14e7fbfd7`
stopped before native window destruction when `UiaDisconnectProvider` returned
`UIA_E_ELEMENTNOTAVAILABLE` (`0x80040201`). The original public provider was
already revoked. Its runtime-ID and host-provider methods therefore correctly
refused the lookup that UI Automation needs to identify the disconnect target.
The run is retained under
`artifacts/goal-ninth-native-owned-smoke-32ffa69ae7554d8fbc92aea2a6b33f6f`.
Its failure is not a successful close, owner join, or release qualification.

Microsoft's [cleanup sample](https://github.com/microsoft/Windows-classic-samples/blob/main/Samples/UIAutomationCleanShutdown/cpp/UiaCleanShutdownControl/UiaCleanShutdownControl.cpp)
uses a new provider instance with the same HWND runtime identity for disconnect.
Its [provider implementation](https://github.com/microsoft/Windows-classic-samples/blob/main/Samples/UIAutomationCleanShutdown/cpp/UiaCleanShutdownControl/UiaProvider.cpp)
keeps the host lookup usable for that purpose. The
[runtime-ID contract](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/nf-uiautomationcore-irawelementproviderfragment-getruntimeid)
specifies an empty runtime-ID array for an HWND-hosted root, so UI Automation
supplies the HWND identity. These rules do not permit substituting an HWND
identity for an arbitrary child or custom runtime ID.

`SWU_UIACreateOwnedHWNDRootProviderWithContext` makes this identity explicit.
It requires a non-null original HWND and an owned full-call context. Its root
returns an empty runtime-ID array under the existing availability gate; it
cannot adopt an authored runtime-ID callback. Only
`UIANativeProviderAttachment` uses this factory in production. Headless
attachments with no HWND continue to use the generic factory. Related generic
providers and children do not acquire the marker.

Disconnection still pins the original provider and irreversibly revokes its
whole context. A marked root must have drained every full C call before native
disconnection; otherwise the driver returns `UIA_E_INVALIDOPERATION` without
calling the OS. The owner already waits for this drainage before detach. The
existing attachment remains the sole owner of its one disconnect attempt,
original HWND, attachment ID, and provider reference.

For a drained marked root, the driver creates a private Simple-only COM
identity with that original HWND. It has no Swift context, tree, attachment,
provider-family reference, mutable window source, authored properties, or
patterns. Its native host lookup resolves only the captured HWND. The object
is passed solely to the one `UiaDisconnectProvider` call and never to
`UiaReturnRawElementProvider`, discovery, navigation, events, or the Swift
caller. Its local COM reference is released for both success and failure;
any native references contain no UI payload and have ordinary COM lifetime.

The original family stays revoked throughout cleanup. Its constant metadata,
root runtime ID, and authored queries continue to return unavailable with
empty outputs. The only fixed original-provider exception is the existing
`QueryInterface` identity contract. Allocation failures and the native
disconnect HRESULT propagate unchanged. A host lookup failure remains a
native failure, with no fallback, retry, re-publication, or availability reset.
Unmarked roots and children retain the original disconnect behavior.

`UIAOwnedRootShutdownTests` adds ten async headless regressions. The per-call
`SWU_UIAProbeDisconnectProvider` peer uses the same disconnect driver, with
stateless fake host lookup and disconnect functions, and exports only scalar
observations. It exercises identity scope, the original HWND, Simple-only
interfaces, empty authored payload, reference balance, full-call drainage,
factory rejection, one native call, and exact failure propagation. No private
identity or native disconnector is globally installed or published. Existing
attachment tests still cover one attempt across repeated and reentrant close.

This source change has not been compiled or executed at source handoff.
Formatting and contract review are not native validation. The original 45
portable smoke regressions, 27 validator predicates, 64-command workload,
publication gate, and all timeouts remain unchanged. A new build bound to the
integrated HEAD and a new actual owned native run are required. This repair
does not address the separately observed synchronous actor-dispatch fault or
the still-unexercised ingress backlog/fairness predicate, and it does not
qualify Narrator, routed COM, pixels, pacing, or long-duration idle behavior.
