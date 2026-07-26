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
// IRawElementProviderFragmentRoot / IInvokeProvider) and forwards every call
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
    void (*setFocus)(void *context, uint64_t element);
    // Hit test in screen coordinates; returns a token or SWU_UIA_NO_ELEMENT.
    uint64_t (*elementFromPoint)(void *context, double x, double y);
    // Returns the focused element token or SWU_UIA_NO_ELEMENT.
    uint64_t (*focusedElement)(void *context);
} SWUUIACallbacks;

// Provider lifecycle. The callbacks struct is copied; only `context` must
// stay alive for as long as any provider exists.
void *SWU_UIACreateRootProvider(const SWUUIACallbacks *callbacks, void *hwnd);
void *SWU_UIACreateElementProvider(const SWUUIACallbacks *callbacks, void *hwnd, uint64_t element);
void SWU_UIAAddRefProvider(void *provider);
void SWU_UIAReleaseProvider(void *provider);

// UIA entry points (wrap uiautomationcore.lib).
intptr_t SWU_UIAReturnRawElementProvider(void *hwnd, uintptr_t wParam, intptr_t lParam, void *provider);
int SWU_UIAClientsAreListening(void);
void SWU_UIARaiseAutomationFocusChanged(void *provider);
void SWU_UIARaiseStructureChanged(void *provider);
void SWU_UIADisconnectProvider(void *provider);

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
void SWU_UIAProviderSetFocus(void *provider);
void *SWU_UIAProviderGetFocus(void *rootProvider);
void *SWU_UIAProviderElementFromPoint(void *rootProvider, double x, double y);
void *SWU_UIAProviderGetFragmentRoot(void *provider);

#ifdef __cplusplus
}
#endif

#endif
