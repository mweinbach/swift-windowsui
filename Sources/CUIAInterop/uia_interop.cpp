#include "CUIAInterop.h"

#include <atomic>

#include <windows.h>

// Define the UIA interface GUIDs in this translation unit (they are not in
// uuid.lib).
#include <initguid.h>

#include <uiautomation.h>

// Compile-time checks that the mirrored constants in the header match the SDK.
static_assert(SWU_UIA_NAV_PARENT == NavigateDirection_Parent, "nav constant drift");
static_assert(SWU_UIA_NAV_NEXT_SIBLING == NavigateDirection_NextSibling, "nav constant drift");
static_assert(SWU_UIA_NAV_PREVIOUS_SIBLING == NavigateDirection_PreviousSibling, "nav constant drift");
static_assert(SWU_UIA_NAV_FIRST_CHILD == NavigateDirection_FirstChild, "nav constant drift");
static_assert(SWU_UIA_NAV_LAST_CHILD == NavigateDirection_LastChild, "nav constant drift");
static_assert(SWU_UIA_PATTERN_INVOKE == UIA_InvokePatternId, "pattern constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_BUTTON == UIA_ButtonControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_CHECK_BOX == UIA_CheckBoxControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_EDIT == UIA_EditControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_HYPERLINK == UIA_HyperlinkControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_IMAGE == UIA_ImageControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_LIST_ITEM == UIA_ListItemControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_LIST == UIA_ListControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_PROGRESS_BAR == UIA_ProgressBarControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_SLIDER == UIA_SliderControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_TAB == UIA_TabControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_TAB_ITEM == UIA_TabItemControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_TEXT == UIA_TextControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_CUSTOM == UIA_CustomControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_GROUP == UIA_GroupControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_WINDOW == UIA_WindowControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_PANE == UIA_PaneControlTypeId, "control type constant drift");
static_assert(SWU_UIA_CONTROL_TYPE_HEADER == UIA_HeaderControlTypeId, "control type constant drift");

namespace {

// COM provider backed entirely by the Swift callback table. The UIA MIDL
// headers declare IRawElementProviderSimple / IRawElementProviderFragment /
// IRawElementProviderFragmentRoot as independent IUnknown-derived interfaces
// (COM interface inheritance, not C++), so this class implements all of them
// as sibling bases and QueryInterface gates what each provider exposes.
//
// Instances are free-threaded (atomic refcount; the Swift callbacks marshal
// themselves onto the main thread), matching the raw-provider threading
// contract.
class SWUProvider : public IRawElementProviderSimple,
                    public IRawElementProviderFragment,
                    public IRawElementProviderFragmentRoot,
                    public IInvokeProvider {
public:
    SWUProvider(const SWUUIACallbacks *callbacks, HWND hwnd, uint64_t element, bool isRoot)
        : hwnd_(hwnd), element_(element), isRoot_(isRoot), refCount_(1) {
        callbacks_ = *callbacks;
    }

    // MARK: IUnknown

    IFACEMETHODIMP QueryInterface(REFIID riid, void **ppv) override {
        if (ppv == nullptr) {
            return E_POINTER;
        }
        if (riid == IID_IUnknown || riid == IID_IRawElementProviderSimple) {
            *ppv = static_cast<IRawElementProviderSimple *>(this);
        } else if (riid == IID_IRawElementProviderFragment) {
            *ppv = static_cast<IRawElementProviderFragment *>(this);
        } else if (riid == IID_IRawElementProviderFragmentRoot) {
            if (!isRoot_) {
                *ppv = nullptr;
                return E_NOINTERFACE;
            }
            *ppv = static_cast<IRawElementProviderFragmentRoot *>(this);
        } else if (riid == IID_IInvokeProvider) {
            if (!supportsInvoke()) {
                *ppv = nullptr;
                return E_NOINTERFACE;
            }
            *ppv = static_cast<IInvokeProvider *>(this);
        } else {
            *ppv = nullptr;
            return E_NOINTERFACE;
        }
        AddRef();
        return S_OK;
    }

    IFACEMETHODIMP_(ULONG) AddRef() override {
        return ++refCount_;
    }

    IFACEMETHODIMP_(ULONG) Release() override {
        ULONG count = --refCount_;
        if (count == 0) {
            delete this;
        }
        return count;
    }

    // MARK: IRawElementProviderSimple

    IFACEMETHODIMP get_ProviderOptions(ProviderOptions *pRetVal) override {
        if (pRetVal == nullptr) {
            return E_POINTER;
        }
        *pRetVal = (ProviderOptions)(ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading);
        return S_OK;
    }

    IFACEMETHODIMP GetPatternProvider(PATTERNID patternId, IUnknown **pRetVal) override {
        if (pRetVal == nullptr) {
            return E_POINTER;
        }
        *pRetVal = nullptr;
        if (patternId == UIA_InvokePatternId && supportsInvoke()) {
            *pRetVal = static_cast<IInvokeProvider *>(this);
            AddRef();
        }
        return S_OK;
    }

    IFACEMETHODIMP GetPropertyValue(PROPERTYID propertyId, VARIANT *pRetVal) override {
        if (pRetVal == nullptr) {
            return E_POINTER;
        }
        VariantInit(pRetVal);
        switch (propertyId) {
        case UIA_NamePropertyId:
            setStringProperty(pRetVal, SWU_UIA_STRING_NAME);
            break;
        case UIA_ValueValuePropertyId:
            setStringProperty(pRetVal, SWU_UIA_STRING_VALUE);
            break;
        case UIA_HelpTextPropertyId:
            setStringProperty(pRetVal, SWU_UIA_STRING_HELP_TEXT);
            break;
        case UIA_AutomationIdPropertyId:
            setStringProperty(pRetVal, SWU_UIA_STRING_AUTOMATION_ID);
            break;
        case UIA_ClassNamePropertyId:
            setStringProperty(pRetVal, SWU_UIA_STRING_CLASS_NAME);
            break;
        case UIA_ControlTypePropertyId:
            pRetVal->vt = VT_I4;
            pRetVal->lVal = callbacks_.getControlType(callbacks_.context, element_);
            break;
        case UIA_IsEnabledPropertyId:
            setBoolProperty(pRetVal, SWU_UIA_BOOL_IS_ENABLED);
            break;
        case UIA_HasKeyboardFocusPropertyId:
            setBoolProperty(pRetVal, SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS);
            break;
        case UIA_IsKeyboardFocusablePropertyId:
            setBoolProperty(pRetVal, SWU_UIA_BOOL_IS_KEYBOARD_FOCUSABLE);
            break;
        case UIA_IsOffscreenPropertyId:
            setBoolProperty(pRetVal, SWU_UIA_BOOL_IS_OFFSCREEN);
            break;
        case UIA_IsContentElementPropertyId:
        case UIA_IsControlElementPropertyId:
            pRetVal->vt = VT_BOOL;
            pRetVal->boolVal = VARIANT_TRUE;
            break;
        default:
            break;
        }
        return S_OK;
    }

    IFACEMETHODIMP get_HostRawElementProvider(IRawElementProviderSimple **pRetVal) override {
        if (pRetVal == nullptr) {
            return E_POINTER;
        }
        *pRetVal = nullptr;
        if (isRoot_ && hwnd_ != nullptr) {
            return UiaHostProviderFromHwnd(hwnd_, pRetVal);
        }
        return S_OK;
    }

    // MARK: IRawElementProviderFragment

    IFACEMETHODIMP Navigate(NavigateDirection direction, IRawElementProviderFragment **pRetVal) override {
        if (pRetVal == nullptr) {
            return E_POINTER;
        }
        *pRetVal = navigateConcrete(direction);
        return S_OK;
    }

    IFACEMETHODIMP GetRuntimeId(SAFEARRAY **pRetVal) override {
        if (pRetVal == nullptr) {
            return E_POINTER;
        }
        *pRetVal = nullptr;
        int32_t buffer[8];
        int32_t count = callbacks_.getRuntimeId(callbacks_.context, element_, buffer, 8);
        if (count <= 0) {
            return S_OK;
        }
        SAFEARRAY *psa = SafeArrayCreateVector(VT_I4, 0, (ULONG)count);
        if (psa == nullptr) {
            return E_OUTOFMEMORY;
        }
        for (int32_t i = 0; i < count; i++) {
            LONG index = i;
            SafeArrayPutElement(psa, &index, &buffer[i]);
        }
        *pRetVal = psa;
        return S_OK;
    }

    IFACEMETHODIMP get_BoundingRectangle(UiaRect *pRetVal) override {
        if (pRetVal == nullptr) {
            return E_POINTER;
        }
        callbacks_.getBoundingRectangle(
            callbacks_.context, element_, &pRetVal->left, &pRetVal->top, &pRetVal->width, &pRetVal->height);
        return S_OK;
    }

    IFACEMETHODIMP GetEmbeddedFragmentRoots(SAFEARRAY **pRetVal) override {
        if (pRetVal == nullptr) {
            return E_POINTER;
        }
        *pRetVal = nullptr;
        return S_OK;
    }

    IFACEMETHODIMP SetFocus() override {
        callbacks_.setFocus(callbacks_.context, element_);
        return S_OK;
    }

    IFACEMETHODIMP get_FragmentRoot(IRawElementProviderFragmentRoot **pRetVal) override {
        if (pRetVal == nullptr) {
            return E_POINTER;
        }
        *pRetVal = fragmentRootConcrete();
        return S_OK;
    }

    // MARK: IRawElementProviderFragmentRoot

    IFACEMETHODIMP ElementProviderFromPoint(double x, double y, IRawElementProviderFragment **pRetVal) override {
        if (pRetVal == nullptr) {
            return E_POINTER;
        }
        *pRetVal = nullptr;
        uint64_t target = callbacks_.elementFromPoint(callbacks_.context, x, y);
        if (target != SWU_UIA_NO_ELEMENT) {
            *pRetVal = new SWUProvider(&callbacks_, hwnd_, target, false);
        }
        return S_OK;
    }

    IFACEMETHODIMP GetFocus(IRawElementProviderFragment **pRetVal) override {
        if (pRetVal == nullptr) {
            return E_POINTER;
        }
        *pRetVal = nullptr;
        uint64_t target = callbacks_.focusedElement(callbacks_.context);
        if (target != SWU_UIA_NO_ELEMENT) {
            *pRetVal = new SWUProvider(&callbacks_, hwnd_, target, false);
        }
        return S_OK;
    }

    // MARK: IInvokeProvider

    IFACEMETHODIMP Invoke() override {
        callbacks_.invokeDefaultAction(callbacks_.context, element_);
        return S_OK;
    }

    // MARK: Concrete helpers for the exported C API
    //
    // The exported functions hand opaque `void *` handles to Swift. Those
    // handles are always concrete SWUProvider pointers (never interface
    // pointers), so reinterpret_cast back to SWUProvider is exact and member
    // calls get correct this-adjustment. The one exception is the invoke
    // pattern pointer returned by SWU_UIAProviderGetInvokePattern, which is a
    // genuine IInvokeProvider interface pointer and is only ever passed to
    // SWU_UIAProviderInvoke / SWU_UIAReleaseProvider, both of which go
    // through that interface's own vtable.

    SWUProvider *navigateConcrete(int32_t direction) {
        uint64_t target = callbacks_.navigate(callbacks_.context, element_, direction);
        if (target == SWU_UIA_NO_ELEMENT) {
            return nullptr;
        }
        return new SWUProvider(&callbacks_, hwnd_, target, false);
    }

    SWUProvider *fragmentRootConcrete() {
        return new SWUProvider(&callbacks_, hwnd_, SWU_UIA_ROOT_ELEMENT, true);
    }

    SWUProvider *elementFromPointConcrete(double x, double y) {
        uint64_t target = callbacks_.elementFromPoint(callbacks_.context, x, y);
        if (target == SWU_UIA_NO_ELEMENT) {
            return nullptr;
        }
        return new SWUProvider(&callbacks_, hwnd_, target, false);
    }

    SWUProvider *focusConcrete() {
        uint64_t target = callbacks_.focusedElement(callbacks_.context);
        if (target == SWU_UIA_NO_ELEMENT) {
            return nullptr;
        }
        return new SWUProvider(&callbacks_, hwnd_, target, false);
    }

private:
    bool supportsInvoke() {
        return callbacks_.hasInvokeAction != nullptr
            && callbacks_.hasInvokeAction(callbacks_.context, element_) != 0;
    }

    void setStringProperty(VARIANT *out, int32_t neutralKey) {
        if (callbacks_.copyStringProperty == nullptr) {
            return;
        }
        uint16_t *value = callbacks_.copyStringProperty(callbacks_.context, element_, neutralKey);
        if (value != nullptr) {
            out->vt = VT_BSTR;
            out->bstrVal = (BSTR)value;
        }
    }

    void setBoolProperty(VARIANT *out, int32_t neutralKey) {
        if (callbacks_.getBoolProperty == nullptr) {
            return;
        }
        int32_t value = callbacks_.getBoolProperty(callbacks_.context, element_, neutralKey);
        if (value >= 0) {
            out->vt = VT_BOOL;
            out->boolVal = value != 0 ? VARIANT_TRUE : VARIANT_FALSE;
        }
    }

    SWUUIACallbacks callbacks_;
    HWND hwnd_;
    uint64_t element_;
    bool isRoot_;
    std::atomic<ULONG> refCount_;
};

SWUProvider *asProvider(void *provider) {
    return reinterpret_cast<SWUProvider *>(provider);
}

}  // namespace

extern "C" {

void *SWU_UIACreateRootProvider(const SWUUIACallbacks *callbacks, void *hwnd) {
    if (callbacks == nullptr) {
        return nullptr;
    }
    return new SWUProvider(callbacks, (HWND)hwnd, SWU_UIA_ROOT_ELEMENT, true);
}

void *SWU_UIACreateElementProvider(const SWUUIACallbacks *callbacks, void *hwnd, uint64_t element) {
    if (callbacks == nullptr) {
        return nullptr;
    }
    return new SWUProvider(callbacks, (HWND)hwnd, element, element == SWU_UIA_ROOT_ELEMENT);
}

void SWU_UIAAddRefProvider(void *provider) {
    if (provider != nullptr) {
        // Correct for concrete handles and for any interface pointer: the
        // passed interface's own IUnknown vtable slot does the adjustment.
        ((IUnknown *)provider)->AddRef();
    }
}

void SWU_UIAReleaseProvider(void *provider) {
    if (provider != nullptr) {
        ((IUnknown *)provider)->Release();
    }
}

intptr_t SWU_UIAReturnRawElementProvider(void *hwnd, uintptr_t wParam, intptr_t lParam, void *provider) {
    if (provider == nullptr) {
        return 0;
    }
    return (intptr_t)UiaReturnRawElementProvider(
        (HWND)hwnd, (WPARAM)wParam, (LPARAM)lParam,
        static_cast<IRawElementProviderSimple *>(asProvider(provider)));
}

int SWU_UIAClientsAreListening(void) {
    return UiaClientsAreListening() ? 1 : 0;
}

void SWU_UIARaiseAutomationFocusChanged(void *provider) {
    if (provider != nullptr) {
        UiaRaiseAutomationEvent(
            static_cast<IRawElementProviderSimple *>(asProvider(provider)), UIA_AutomationFocusChangedEventId);
    }
}

void SWU_UIARaiseStructureChanged(void *provider) {
    if (provider != nullptr) {
        UiaRaiseStructureChangedEvent(
            static_cast<IRawElementProviderSimple *>(asProvider(provider)),
            StructureChangeType_ChildrenInvalidated, nullptr, 0);
    }
}

void SWU_UIADisconnectProvider(void *provider) {
    if (provider != nullptr) {
        UiaDisconnectProvider(static_cast<IRawElementProviderSimple *>(asProvider(provider)));
    }
}

uint16_t *SWU_UIACreateBSTR(const uint16_t *chars, int32_t length) {
    if (chars == nullptr || length < 0) {
        return nullptr;
    }
    return (uint16_t *)SysAllocStringLen((const OLECHAR *)chars, (UINT)length);
}

void SWU_UIAFreeString(uint16_t *bstr) {
    if (bstr != nullptr) {
        SysFreeString((BSTR)bstr);
    }
}

void *SWU_UIAProviderNavigate(void *provider, int32_t direction) {
    if (provider == nullptr) {
        return nullptr;
    }
    return asProvider(provider)->navigateConcrete(direction);
}

int32_t SWU_UIAProviderGetRuntimeId(void *provider, int32_t *buffer, int32_t capacity) {
    if (provider == nullptr || buffer == nullptr || capacity <= 0) {
        return 0;
    }
    SAFEARRAY *psa = nullptr;
    if (FAILED(asProvider(provider)->GetRuntimeId(&psa)) || psa == nullptr) {
        return 0;
    }
    LONG lower = 0;
    LONG upper = -1;
    SafeArrayGetLBound(psa, 1, &lower);
    SafeArrayGetUBound(psa, 1, &upper);
    int32_t count = 0;
    for (LONG i = lower; i <= upper && count < capacity; i++) {
        int32_t value = 0;
        SafeArrayGetElement(psa, &i, &value);
        buffer[count++] = value;
    }
    SafeArrayDestroy(psa);
    return count;
}

void SWU_UIAProviderGetBoundingRectangle(
    void *provider, double *left, double *top, double *width, double *height) {
    if (provider == nullptr) {
        return;
    }
    UiaRect rect = {0, 0, 0, 0};
    asProvider(provider)->get_BoundingRectangle(&rect);
    if (left != nullptr) *left = rect.left;
    if (top != nullptr) *top = rect.top;
    if (width != nullptr) *width = rect.width;
    if (height != nullptr) *height = rect.height;
}

uint16_t *SWU_UIAProviderGetName(void *provider) {
    if (provider == nullptr) {
        return nullptr;
    }
    VARIANT value;
    VariantInit(&value);
    if (FAILED(asProvider(provider)->GetPropertyValue(UIA_NamePropertyId, &value))) {
        return nullptr;
    }
    if (value.vt != VT_BSTR) {
        VariantClear(&value);
        return nullptr;
    }
    return (uint16_t *)value.bstrVal;
}

int32_t SWU_UIAProviderGetControlType(void *provider) {
    if (provider == nullptr) {
        return 0;
    }
    VARIANT value;
    VariantInit(&value);
    int32_t result = 0;
    if (SUCCEEDED(asProvider(provider)->GetPropertyValue(UIA_ControlTypePropertyId, &value))
        && value.vt == VT_I4) {
        result = value.lVal;
    }
    VariantClear(&value);
    return result;
}

int32_t SWU_UIAProviderGetBoolProperty(void *provider, int32_t neutralKey, int32_t *hasValue) {
    if (hasValue != nullptr) {
        *hasValue = 0;
    }
    if (provider == nullptr) {
        return 0;
    }
    PROPERTYID propertyId;
    switch (neutralKey) {
    case SWU_UIA_BOOL_IS_ENABLED: propertyId = UIA_IsEnabledPropertyId; break;
    case SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS: propertyId = UIA_HasKeyboardFocusPropertyId; break;
    case SWU_UIA_BOOL_IS_KEYBOARD_FOCUSABLE: propertyId = UIA_IsKeyboardFocusablePropertyId; break;
    case SWU_UIA_BOOL_IS_OFFSCREEN: propertyId = UIA_IsOffscreenPropertyId; break;
    default: return 0;
    }
    VARIANT value;
    VariantInit(&value);
    int32_t result = 0;
    if (SUCCEEDED(asProvider(provider)->GetPropertyValue(propertyId, &value)) && value.vt == VT_BOOL) {
        result = value.boolVal == VARIANT_TRUE ? 1 : 0;
        if (hasValue != nullptr) {
            *hasValue = 1;
        }
    }
    VariantClear(&value);
    return result;
}

void *SWU_UIAProviderGetInvokePattern(void *provider) {
    if (provider == nullptr) {
        return nullptr;
    }
    IUnknown *pattern = nullptr;
    asProvider(provider)->GetPatternProvider(UIA_InvokePatternId, &pattern);
    // Genuine IInvokeProvider interface pointer; only valid for
    // SWU_UIAProviderInvoke / SWU_UIAReleaseProvider.
    return pattern;
}

void SWU_UIAProviderInvoke(void *invokeProvider) {
    if (invokeProvider != nullptr) {
        ((IInvokeProvider *)invokeProvider)->Invoke();
    }
}

void SWU_UIAProviderSetFocus(void *provider) {
    if (provider != nullptr) {
        asProvider(provider)->SetFocus();
    }
}

void *SWU_UIAProviderGetFocus(void *rootProvider) {
    if (rootProvider == nullptr) {
        return nullptr;
    }
    return asProvider(rootProvider)->focusConcrete();
}

void *SWU_UIAProviderElementFromPoint(void *rootProvider, double x, double y) {
    if (rootProvider == nullptr) {
        return nullptr;
    }
    return asProvider(rootProvider)->elementFromPointConcrete(x, y);
}

void *SWU_UIAProviderGetFragmentRoot(void *provider) {
    if (provider == nullptr) {
        return nullptr;
    }
    return asProvider(provider)->fragmentRootConcrete();
}

}  // extern "C"
