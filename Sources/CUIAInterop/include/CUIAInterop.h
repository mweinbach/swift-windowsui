#ifndef CUIAINTEROP_H
#define CUIAINTEROP_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Thin COM/UIA interop for the retained-runtime accessibility bridge.
//
// The C layer builds the COM vtables for the UI Automation provider
// interfaces (IRawElementProviderSimple / IRawElementProviderFragment /
// IRawElementProviderFragmentRoot plus the supported UIA pattern providers)
// and forwards every call
// to a table of Swift-provided callbacks. All tree logic lives in Swift; the
// only UIA constants and VARIANT/BSTR marshaling live here.
//
// Element identity: elements are addressed by a stable uint64 token assigned
// by the Swift layer. Token 0 is always the fragment root. `SWU_UIA_NO_ELEMENT`
// signals "no such element" for navigation/point/focus lookups.

#define SWU_UIA_ROOT_ELEMENT ((uint64_t)0)
#define SWU_UIA_NO_ELEMENT UINT64_MAX

// Neutral string property keys (UIA property mapping stays in C).
enum {
    SWU_UIA_STRING_NAME = 0,
    SWU_UIA_STRING_VALUE = 1,
    SWU_UIA_STRING_HELP_TEXT = 2,
    SWU_UIA_STRING_AUTOMATION_ID = 3,
    SWU_UIA_STRING_CLASS_NAME = 4,
};

// Neutral boolean property keys.
enum {
    SWU_UIA_BOOL_IS_ENABLED = 0,
    SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS = 1,
    SWU_UIA_BOOL_IS_KEYBOARD_FOCUSABLE = 2,
    SWU_UIA_BOOL_IS_OFFSCREEN = 3,
    SWU_UIA_BOOL_IS_PASSWORD = 4,
    SWU_UIA_BOOL_IS_READ_ONLY = 5,
    SWU_UIA_BOOL_IS_SELECTED = 6,
};

// NavigateDirection values mirrored for callers that only import this header
// (static-asserted against the SDK enum in the implementation).
enum {
    SWU_UIA_NAV_PARENT = 0,
    SWU_UIA_NAV_NEXT_SIBLING = 1,
    SWU_UIA_NAV_PREVIOUS_SIBLING = 2,
    SWU_UIA_NAV_FIRST_CHILD = 3,
    SWU_UIA_NAV_LAST_CHILD = 4,
};

// UIA pattern id mirrored for Swift callers (static-asserted in the .cpp).
enum {
    SWU_UIA_PATTERN_INVOKE = 10000,
    SWU_UIA_PATTERN_SELECTION = 10001,
    SWU_UIA_PATTERN_VALUE = 10002,
    SWU_UIA_PATTERN_SELECTION_ITEM = 10010,
    SWU_UIA_PATTERN_TOGGLE = 10015,
    SWU_UIA_PATTERN_ITEM_CONTAINER = 10019,
    SWU_UIA_PATTERN_VIRTUALIZED_ITEM = 10020,
};

// ItemContainer implements enumeration (property zero) only. Nonzero property
// searches return E_NOTIMPL without inspecting any row content.
enum {
    SWU_UIA_ITEM_PROPERTY_ANY = 0,
    SWU_UIA_ITEM_PROPERTY_NAME = 30005,
    SWU_UIA_ITEM_PROPERTY_AUTOMATION_ID = 30011,
};

enum {
    SWU_UIA_ITEM_LOOKUP_UNAVAILABLE = -1,
    SWU_UIA_ITEM_LOOKUP_INVALID_START = -2,
    SWU_UIA_ITEM_LOOKUP_END = 0,
    SWU_UIA_ITEM_LOOKUP_FOUND = 1,
};

enum {
    SWU_UIA_LOGICAL_ITEM_UNAVAILABLE = -1,
    SWU_UIA_LOGICAL_ITEM_ORDINARY = 0,
    SWU_UIA_LOGICAL_ITEM_PLACEHOLDER = 1,
};

enum {
    SWU_UIA_TOGGLE_OFF = 0,
    SWU_UIA_TOGGLE_ON = 1,
    SWU_UIA_TOGGLE_INDETERMINATE = 2,
};

// UIA control type ids mirrored for Swift callers (static-asserted in the .cpp).
enum {
    SWU_UIA_CONTROL_TYPE_BUTTON = 50000,
    SWU_UIA_CONTROL_TYPE_CHECK_BOX = 50002,
    SWU_UIA_CONTROL_TYPE_EDIT = 50004,
    SWU_UIA_CONTROL_TYPE_HYPERLINK = 50005,
    SWU_UIA_CONTROL_TYPE_IMAGE = 50006,
    SWU_UIA_CONTROL_TYPE_LIST_ITEM = 50007,
    SWU_UIA_CONTROL_TYPE_LIST = 50008,
    SWU_UIA_CONTROL_TYPE_PROGRESS_BAR = 50012,
    SWU_UIA_CONTROL_TYPE_SLIDER = 50015,
    SWU_UIA_CONTROL_TYPE_TAB = 50018,
    SWU_UIA_CONTROL_TYPE_TAB_ITEM = 50019,
    SWU_UIA_CONTROL_TYPE_TEXT = 50020,
    SWU_UIA_CONTROL_TYPE_CUSTOM = 50025,
    SWU_UIA_CONTROL_TYPE_GROUP = 50026,
    SWU_UIA_CONTROL_TYPE_WINDOW = 50032,
    SWU_UIA_CONTROL_TYPE_PANE = 50033,
    SWU_UIA_CONTROL_TYPE_HEADER = 50034,
};

typedef struct SWUUIACallbacks {
    void *context;
    // Returns the target element token, or SWU_UIA_NO_ELEMENT.
    uint64_t (*navigate)(void *context, uint64_t element, int32_t direction);
    // Writes up to `capacity` int32 values; returns the count (0 = no id).
    int32_t (*getRuntimeId)(void *context, uint64_t element, int32_t *buffer, int32_t capacity);
    // Bounding rectangle in screen coordinates.
    void (*getBoundingRectangle)(
        void *context, uint64_t element, double *left, double *top, double *width, double *height);
    // Returns a BSTR allocated via SWU_UIACreateBSTR (owned by the caller), or
    // NULL when the property is not provided.
    uint16_t *(*copyStringProperty)(void *context, uint64_t element, int32_t property);
    // UIA control type id (SWU_UIA_CONTROL_TYPE_*).
    int32_t (*getControlType)(void *context, uint64_t element);
    // Returns 0/1, or -1 when the property is not provided.
    int32_t (*getBoolProperty)(void *context, uint64_t element, int32_t property);
    int32_t (*hasInvokeAction)(void *context, uint64_t element);
    void (*invokeDefaultAction)(void *context, uint64_t element);
    // Returns whether the element currently supports the specified UIA pattern.
    int32_t (*supportsPattern)(void *context, uint64_t element, int32_t pattern);
    // Returns 1 when a value write succeeds; UTF-16 is length-delimited.
    int32_t (*setValue)(void *context, uint64_t element, const uint16_t *value, int32_t length);
    // Returns SWU_UIA_TOGGLE_*, or -1 when no toggle state is available.
    int32_t (*getToggleState)(void *context, uint64_t element);
    int32_t (*toggle)(void *context, uint64_t element);
    int32_t (*select)(void *context, uint64_t element);
    int32_t (*addToSelection)(void *context, uint64_t element);
    int32_t (*removeFromSelection)(void *context, uint64_t element);
    uint64_t (*getSelectionContainer)(void *context, uint64_t element);
    // Returns the total selected count; writes up to `capacity` element ids.
    int32_t (*getSelection)(void *context, uint64_t element, uint64_t *buffer, int32_t capacity);
    int32_t (*realizeVirtualizedItem)(void *context, uint64_t element);
    void (*setFocus)(void *context, uint64_t element);
    // Hit test in screen coordinates; returns a token or SWU_UIA_NO_ELEMENT.
    uint64_t (*elementFromPoint)(void *context, double x, double y);
    // Returns the focused element token or SWU_UIA_NO_ELEMENT.
    uint64_t (*focusedElement)(void *context);
    // Optional native receipt validation without authored callbacks. An
    // unconstructed logical item exposes only RuntimeId, IsOffscreen, and
    // VirtualizedItem until Realize.
    int32_t (*getLogicalItemState)(void *context, uint64_t element);
    // Optional property-zero enumeration. `after` is SWU_UIA_NO_ELEMENT for
    // the first item; writes a token only for SWU_UIA_ITEM_LOOKUP_FOUND.
    int32_t (*findItem)(void *context, uint64_t container, uint64_t after, uint64_t *result);
} SWUUIACallbacks;

// Explicit-call peers for a native-owner provider. Payload values retain the
// legacy meanings above; transport/lifetime HRESULTs use SWU_UIACallFail and
// must never be returned in a boolean payload. A call is an owned heap token,
// not a stack address. Retain it before queuing actor work and release it after
// that work's final access, including cancellation before actor admission.
typedef struct SWUUIACall SWUUIACall;
// Internal Swift actor-to-C bridge support. The caller must already be in an
// explicitly established MainActor context. This invokes body synchronously
// within a native thread-local lexical scope and restores its predecessor on
// return. It does not establish actor isolation, retain context, dispatch work,
// propagate across threads/tasks, or grant provider-family availability.
// Never call it from a queue-label/Thread.isMainThread inference or span await.
void SWU_UIAWithActorEntry(void *context, void (*body)(void *context));
int SWU_UIAHasActorEntry(void);
typedef struct SWUUIACallCallbacks {
    void *context;
    uint64_t (*navigate)(SWUUIACall *call, uint64_t element, int32_t direction);
    int32_t (*getRuntimeId)(SWUUIACall *call, uint64_t element, int32_t *buffer, int32_t capacity);
    void (*getBoundingRectangle)(
        SWUUIACall *call, uint64_t element, double *left, double *top, double *width, double *height);
    uint16_t *(*copyStringProperty)(SWUUIACall *call, uint64_t element, int32_t property);
    int32_t (*getControlType)(SWUUIACall *call, uint64_t element);
    int32_t (*getBoolProperty)(SWUUIACall *call, uint64_t element, int32_t property);
    int32_t (*hasInvokeAction)(SWUUIACall *call, uint64_t element);
    void (*invokeDefaultAction)(SWUUIACall *call, uint64_t element);
    int32_t (*supportsPattern)(SWUUIACall *call, uint64_t element, int32_t pattern);
    int32_t (*setValue)(SWUUIACall *call, uint64_t element, const uint16_t *value, int32_t length);
    int32_t (*getToggleState)(SWUUIACall *call, uint64_t element);
    int32_t (*toggle)(SWUUIACall *call, uint64_t element);
    int32_t (*select)(SWUUIACall *call, uint64_t element);
    int32_t (*addToSelection)(SWUUIACall *call, uint64_t element);
    int32_t (*removeFromSelection)(SWUUIACall *call, uint64_t element);
    uint64_t (*getSelectionContainer)(SWUUIACall *call, uint64_t element);
    int32_t (*getSelection)(SWUUIACall *call, uint64_t element, uint64_t *buffer, int32_t capacity);
    int32_t (*realizeVirtualizedItem)(SWUUIACall *call, uint64_t element);
    void (*setFocus)(SWUUIACall *call, uint64_t element);
    uint64_t (*elementFromPoint)(SWUUIACall *call, double x, double y);
    uint64_t (*focusedElement)(SWUUIACall *call);
    // Optional logical-item peers. Payloads use the same enums as the legacy
    // table; transport failures remain out of band on this full-method call.
    int32_t (*getLogicalItemState)(SWUUIACall *call, uint64_t element);
    int32_t (*findItem)(SWUUIACall *call, uint64_t container, uint64_t after, uint64_t *result);
} SWUUIACallCallbacks;

// Invoked once after irreversible revocation and final full-call release. The
// signal must be nonblocking and must not wait for the actor or native owner.
// It runs outside the admission lock and may run on any releasing thread.
// A failed signal is retained verbatim; its owner must also finish a pending
// close with that failure without relying on delivery of the failed wake.
typedef struct SWUUIADrainWake {
    void *context;
    int32_t (*signal)(void *context);
    void (*releaseContext)(void *context);
} SWUUIADrainWake;

void SWU_UIARetainCall(SWUUIACall *call);
void SWU_UIAReleaseCall(SWUUIACall *call);
void *SWU_UIACallOwnerContext(SWUUIACall *call);
// S_OK while usable; owner revocation takes precedence over a recorded failure.
int32_t SWU_UIACallStatus(SWUUIACall *call);
// Records the first failed HRESULT only. Successful HRESULTs are ignored.
void SWU_UIACallFail(SWUUIACall *call, int32_t failure);
// An absent owner is terminal for its whole family. Ordinary element/action
// failures use CallFail instead. Revocation never waits for the caller's lease.
void SWU_UIACallRevokeOwner(SWUUIACall *call);

// A shared native lifetime for one provider tree. Creation copies the callback
// table and adopts one reference to callbacks->context only on success. The
// release hook runs exactly once, on whichever thread releases the final native
// reference; it must not perform actor-isolated work. A null hook preserves a
// borrowed context. Revocation is irreversible and never releases the context
// while providers or calls still hold it.
typedef struct SWUUIAProviderContext SWUUIAProviderContext;
SWUUIAProviderContext *SWU_UIACreateProviderContext(
    const SWUUIACallbacks *callbacks, void (*releaseContext)(void *));
// Copies both tables and adopts their context references only on success.
// Full-call admission covers native output marshalling and retained actor work.
SWUUIAProviderContext *SWU_UIACreateProviderContextWithCalls(
    const SWUUIACallCallbacks *callbacks, void (*releaseContext)(void *), const SWUUIADrainWake *drainWake);
void SWU_UIARetainProviderContext(SWUUIAProviderContext *context);
void SWU_UIAReleaseProviderContext(SWUUIAProviderContext *context);
void SWU_UIARevokeProviderContext(SWUUIAProviderContext *context);
int SWU_UIAProviderContextIsAvailable(SWUUIAProviderContext *context);
// True only after revocation and release of every admitted call token.
int SWU_UIAProviderContextIsQuiescent(SWUUIAProviderContext *context);
// S_OK before notification and after a successful notification, otherwise the
// signal's exact failed HRESULT. It does not replace the owner's typed failure.
int32_t SWU_UIAProviderContextDrainWakeResult(SWUUIAProviderContext *context);
void *SWU_UIACreateRootProviderWithContext(SWUUIAProviderContext *context, void *hwnd);
// Owned Win32 roots explicitly use the original non-null HWND as their runtime
// identity. Requires a full-call context. GetRuntimeId succeeds with no array
// while available, without consulting a callback-supplied runtime ID. Revoked
// public methods still fail. Only this factory enables private shutdown identity.
void *SWU_UIACreateOwnedHWNDRootProviderWithContext(SWUUIAProviderContext *context, void *hwnd);
void *SWU_UIACreateElementProviderWithContext(
    SWUUIAProviderContext *context, void *hwnd, uint64_t element);

// Legacy borrowed-context factories. The callback table is copied; the caller
// must keep callbacks->context alive for every provider derived from this call.
// New owned clients should share one context through the WithContext factories.
void *SWU_UIACreateRootProvider(const SWUUIACallbacks *callbacks, void *hwnd);
void *SWU_UIACreateElementProvider(const SWUUIACallbacks *callbacks, void *hwnd, uint64_t element);
void SWU_UIAAddRefProvider(void *provider);
void SWU_UIAReleaseProvider(void *provider);

// Fixed native qualification seam: arm once on a concrete provider created
// with explicit calls. The next control-type property method takes the gate
// before callbacks, then waits only after its final callback and successful
// native value preparation, while its real full-method lease remains alive.
// Other properties/providers and nested control-type queries are unaffected.
// A failed callback does not enter the gate. No hook or actor work runs here.
// The caller owns the returned reference; the provider/method owns another.
// Dropping the controller reference does not open the gate. The controller
// must run independently of the actor/native owner and always open or time out.
// Timeouts must be finite, in 1...30000 ms. Invalid timeouts/legacy contexts
// return E_INVALIDARG; a second arm returns UIA_E_INVALIDOPERATION. A revoked
// owner returns UIA_E_ELEMENTNOTAVAILABLE. Failed arms leave the output null.
typedef struct SWUUIAPublicationGate SWUUIAPublicationGate;
int32_t SWU_UIAProviderArmControlTypePublicationGate(
    void *provider, uint32_t holdTimeoutMilliseconds, SWUUIAPublicationGate **result);
void SWU_UIARetainPublicationGate(SWUUIAPublicationGate *gate);
void SWU_UIAReleasePublicationGate(SWUUIAPublicationGate *gate);
// S_OK means the final publication point was reached, not query success. The
// captured thread must match the fixture's intended worker; an unrelated next
// control-type caller can otherwise claim the per-provider gate.
int32_t SWU_UIAPublicationGateWaitUntilEntered(SWUUIAPublicationGate *gate, uint32_t timeoutMilliseconds);
// Zero before entry; otherwise the actual native method's GetCurrentThreadId.
uint32_t SWU_UIAPublicationGateEnteredThreadID(SWUUIAPublicationGate *gate);
// Early/repeated opens are valid. S_OK reports the release signal only. The
// query rechecks its owner/call status after release and clears output on any
// failure. Revocation and recorded transport errors precede gate wait errors.
// Wait timeouts return HRESULT_FROM_WIN32(ERROR_TIMEOUT), never success.
int32_t SWU_UIAPublicationGateOpen(SWUUIAPublicationGate *gate);

// UIA entry points (wrap uiautomationcore.lib).
// A non-null HWND with zero parameters and a null provider forwards the
// documented window raised-event-map cleanup request. Its zero return is not
// a success report. Other null-provider inputs remain no-ops.
intptr_t SWU_UIAReturnRawElementProvider(void *hwnd, uintptr_t wParam, intptr_t lParam, void *provider);
int SWU_UIAClientsAreListening(void);
void SWU_UIARaiseAutomationFocusChanged(void *provider);
void SWU_UIARaiseStructureChanged(void *provider);
void SWU_UIARaiseLiveRegionChanged(void *provider);
void SWU_UIADisconnectProvider(void *provider);
// Irreversibly revokes this provider's shared context before attempting native
// disconnection. Returns the native HRESULT; failure never restores availability.
// For an owned HWND root, waits are the owner's responsibility: all full calls
// must already be drained, or this returns UIA_E_INVALIDOPERATION without an OS
// call. A private, payload-free Simple provider resolves that original HWND's
// identity for cleanup only. It is never returned to clients. Other providers
// keep the original native call; a child/custom identity never falls back to a
// root identity. Neither path restores availability or retries native failures.
int32_t SWU_UIATryDisconnectProvider(void *provider);

// Headless, per-invocation peer of the same disconnect driver. It replaces only
// the OS host lookup/disconnect functions, never publishes an interface, and
// returns observations as values. No HWND, client, global hook, or pump is used.
// A successful simulated host lookup returns a private data-only host object;
// hostFailure injects E_ACCESSDENIED and allocationFailure injects a null factory.
// nativeResult is returned verbatim after successful identity lookup. These are
// unit-test observations, not evidence of an actual OS disconnection.
typedef struct SWUUIADisconnectProbe {
    int32_t nativeCallCount;
    int32_t usedPrivateIdentity;
    int32_t contextAvailable;
    int32_t contextQuiescent;
    int32_t originalOptionsResult;
    int32_t optionsResult;
    int32_t options;
    int32_t patternResult;
    int32_t patternIsNull;
    int32_t propertyResult;
    int32_t propertyVariantType;
    int32_t unknownResult;
    int32_t simpleResult;
    int32_t fragmentResult;
    int32_t sameUnknownIdentity;
    int32_t hostResult;
    uintptr_t hostWindowHandle;
    uint32_t identityAfterAddRef;
    uint32_t identityAfterRelease;
    uint32_t identityAfterOwnerRelease;
    uint32_t hostAfterAddRef;
    uint32_t hostAfterRelease;
    uint32_t hostAfterOwnerRelease;
} SWUUIADisconnectProbe;
int32_t SWU_UIAProbeDisconnectProvider(
    void *provider, int32_t nativeResult, int hostFailure, int allocationFailure,
    SWUUIADisconnectProbe *result);

// BSTR helpers (SysAllocStringLen / SysFreeString wrappers).
uint16_t *SWU_UIACreateBSTR(const uint16_t *chars, int32_t length);
void SWU_UIAFreeString(uint16_t *bstr);

// Headless driving helpers: call through the real COM vtables so unit tests
// can exercise providers without a UIA client. Returned providers/BSTRs are
// owned by the caller (release with SWU_UIAReleaseProvider / SWU_UIAFreeString).
void *SWU_UIAProviderNavigate(void *provider, int32_t direction);
int32_t SWU_UIAProviderGetRuntimeId(void *provider, int32_t *buffer, int32_t capacity);
void SWU_UIAProviderGetBoundingRectangle(
    void *provider, double *left, double *top, double *width, double *height);
uint16_t *SWU_UIAProviderGetName(void *provider);
int32_t SWU_UIAProviderGetControlType(void *provider);
// Returns 0/1; sets *hasValue to 0 when the provider does not supply it.
int32_t SWU_UIAProviderGetBoolProperty(void *provider, int32_t neutralKey, int32_t *hasValue);
void *SWU_UIAProviderGetInvokePattern(void *provider);
void SWU_UIAProviderInvoke(void *invokeProvider);
void *SWU_UIAProviderGetValuePattern(void *provider);
uint16_t *SWU_UIAValueProviderGetValue(void *valueProvider);
int32_t SWU_UIAValueProviderSetValue(void *valueProvider, const uint16_t *value, int32_t length);
int32_t SWU_UIAValueProviderIsReadOnly(void *valueProvider);
void *SWU_UIAProviderGetTogglePattern(void *provider);
int32_t SWU_UIAToggleProviderGetState(void *toggleProvider);
int32_t SWU_UIAToggleProviderToggle(void *toggleProvider);
void *SWU_UIAProviderGetSelectionItemPattern(void *provider);
int32_t SWU_UIASelectionItemProviderIsSelected(void *selectionItemProvider);
int32_t SWU_UIASelectionItemProviderSelect(void *selectionItemProvider);
int32_t SWU_UIASelectionItemProviderAddToSelection(void *selectionItemProvider);
int32_t SWU_UIASelectionItemProviderRemoveFromSelection(void *selectionItemProvider);
void *SWU_UIASelectionItemProviderGetSelectionContainer(void *selectionItemProvider);
void *SWU_UIAProviderGetSelectionPattern(void *provider);
int32_t SWU_UIASelectionProviderGetSelectedCount(void *selectionProvider);
void *SWU_UIASelectionProviderGetSelectedAt(void *selectionProvider, int32_t index);
void *SWU_UIAProviderGetVirtualizedItemPattern(void *provider);
int32_t SWU_UIAVirtualizedItemProviderRealize(void *virtualizedItemProvider);
void *SWU_UIAProviderGetItemContainerPattern(void *provider);
void SWU_UIAProviderSetFocus(void *provider);
void *SWU_UIAProviderGetFocus(void *rootProvider);
void *SWU_UIAProviderElementFromPoint(void *rootProvider, double x, double y);
void *SWU_UIAProviderGetFragmentRoot(void *provider);

// HRESULT-preserving headless peers. They invoke the actual COM interfaces.
// Required output addresses are validated first and initialized before all
// other failures. Interface/string outputs are null on failure; scalar and
// rectangle outputs are zero. An unsupported live property/pattern or absent
// navigation destination remains a successful empty result. A revoked owner
// returns UIA_E_ELEMENTNOTAVAILABLE instead. QueryInterface is the exception:
// its fixed interface support and COM identity survive owner revocation.
// Successful returned providers and strings carry the same ownership as the
// legacy helpers above. Runtime-id buffers are written only on success; their
// output count remains zero on failure.
enum {
    SWU_UIA_INTERFACE_UNKNOWN = 0,
    SWU_UIA_INTERFACE_SIMPLE = 1,
    SWU_UIA_INTERFACE_FRAGMENT = 2,
    SWU_UIA_INTERFACE_FRAGMENT_ROOT = 3,
    SWU_UIA_INTERFACE_INVOKE = 4,
    SWU_UIA_INTERFACE_VALUE = 5,
    SWU_UIA_INTERFACE_TOGGLE = 6,
    SWU_UIA_INTERFACE_SELECTION = 7,
    SWU_UIA_INTERFACE_SELECTION_ITEM = 8,
    SWU_UIA_INTERFACE_VIRTUALIZED_ITEM = 9,
    SWU_UIA_INTERFACE_ITEM_CONTAINER = 10,
};
// QueryInterface and pattern results are genuine interface pointers. Use only
// their matching pattern helpers or AddRef/ReleaseProvider with these handles.
// Navigation, focus, fragment-root, and selection results are concrete handles.
int32_t SWU_UIAProviderQueryInterfaceResult(void *provider, int32_t interfaceKind, void **result);
int32_t SWU_UIAProviderGetPatternResult(void *provider, int32_t pattern, void **result);
int32_t SWU_UIAProviderNavigateResult(void *provider, int32_t direction, void **result);
int32_t SWU_UIAProviderGetRuntimeIdResult(
    void *provider, int32_t *buffer, int32_t capacity, int32_t *count);
int32_t SWU_UIAProviderGetBoundingRectangleResult(
    void *provider, double *left, double *top, double *width, double *height);
int32_t SWU_UIAProviderGetNameResult(void *provider, uint16_t **result);
int32_t SWU_UIAProviderGetControlTypeResult(void *provider, int32_t *result);
int32_t SWU_UIAProviderGetBoolPropertyResult(
    void *provider, int32_t neutralKey, int32_t *result, int32_t *hasValue);
int32_t SWU_UIAProviderGetProviderOptionsResult(void *provider, int32_t *result);
int32_t SWU_UIAProviderGetEmbeddedFragmentRootCountResult(void *provider, int32_t *result);
// Host-provider results belong to Windows, not SWUProvider. Only AddRef/Release
// and ordinary COM clients may consume a successful non-null result.
int32_t SWU_UIAProviderGetHostRawElementProviderResult(void *provider, void **result);
int32_t SWU_UIAProviderInvokeResult(void *invokeProvider);
int32_t SWU_UIAValueProviderGetValueResult(void *valueProvider, uint16_t **result);
int32_t SWU_UIAValueProviderSetValueResult(
    void *valueProvider, const uint16_t *value, int32_t length);
int32_t SWU_UIAValueProviderIsReadOnlyResult(void *valueProvider, int32_t *result);
int32_t SWU_UIAToggleProviderGetStateResult(void *toggleProvider, int32_t *result);
int32_t SWU_UIAToggleProviderToggleResult(void *toggleProvider);
int32_t SWU_UIASelectionItemProviderIsSelectedResult(void *selectionItemProvider, int32_t *result);
int32_t SWU_UIASelectionItemProviderSelectResult(void *selectionItemProvider);
int32_t SWU_UIASelectionItemProviderAddToSelectionResult(void *selectionItemProvider);
int32_t SWU_UIASelectionItemProviderRemoveFromSelectionResult(void *selectionItemProvider);
int32_t SWU_UIASelectionItemProviderGetSelectionContainerResult(void *selectionItemProvider, void **result);
int32_t SWU_UIASelectionProviderGetSelectedCountResult(void *selectionProvider, int32_t *result);
int32_t SWU_UIASelectionProviderGetSelectedAtResult(void *selectionProvider, int32_t index, void **result);
int32_t SWU_UIASelectionProviderCanSelectMultipleResult(void *selectionProvider, int32_t *result);
int32_t SWU_UIASelectionProviderIsSelectionRequiredResult(void *selectionProvider, int32_t *result);
int32_t SWU_UIAVirtualizedItemProviderRealizeResult(void *virtualizedItemProvider);
// `after` and successful outputs are concrete provider handles, not pattern
// pointers. A null `after` starts enumeration. UTF-16 values are length-delimited.
int32_t SWU_UIAItemContainerProviderFindItemResult(
    void *itemContainerProvider, void *after, int32_t property,
    const uint16_t *value, int32_t length, void **result);
int32_t SWU_UIAProviderSetFocusResult(void *provider);
int32_t SWU_UIAProviderGetFocusResult(void *rootProvider, void **result);
int32_t SWU_UIAProviderElementFromPointResult(void *rootProvider, double x, double y, void **result);
int32_t SWU_UIAProviderGetFragmentRootResult(void *provider, void **result);

#ifdef __cplusplus
}
#endif

#endif
