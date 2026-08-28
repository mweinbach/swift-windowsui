#include "CUIAInterop.h"

#include <atomic>
#include <limits>
#include <memory>
#include <new>
#include <vector>

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
static_assert(SWU_UIA_PATTERN_SELECTION == UIA_SelectionPatternId, "pattern constant drift");
static_assert(SWU_UIA_PATTERN_VALUE == UIA_ValuePatternId, "pattern constant drift");
static_assert(SWU_UIA_PATTERN_SELECTION_ITEM == UIA_SelectionItemPatternId, "pattern constant drift");
static_assert(SWU_UIA_PATTERN_TOGGLE == UIA_TogglePatternId, "pattern constant drift");
static_assert(SWU_UIA_PATTERN_VIRTUALIZED_ITEM == UIA_VirtualizedItemPatternId, "pattern constant drift");
static_assert(SWU_UIA_TOGGLE_OFF == ToggleState_Off, "toggle state constant drift");
static_assert(SWU_UIA_TOGGLE_ON == ToggleState_On, "toggle state constant drift");
static_assert(SWU_UIA_TOGGLE_INDETERMINATE == ToggleState_Indeterminate, "toggle state constant drift");
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

// One context is shared by the bridge, every independently allocated provider,
// and every in-flight provider call. The callback table never changes. Revoking
// it therefore needs no lock across Swift callbacks or an OS call.
struct SWUUIAProviderContext {
    const SWUUIACallbacks callbacks;
    void (*const releaseContext)(void *);

    SWUUIAProviderContext(const SWUUIACallbacks &value, void (*release)(void *))
        : callbacks(value), releaseContext(release) {}

    void retain() { references.fetch_add(1, std::memory_order_relaxed); }

    void release() {
        if (references.fetch_sub(1, std::memory_order_acq_rel) == 1) {
            delete this;
        }
    }

    void revoke() { available.store(false, std::memory_order_release); }
    bool isAvailable() const { return available.load(std::memory_order_acquire); }

private:
    ~SWUUIAProviderContext() {
        // The hook owns only the callback box. Its contract permits final
        // release on a COM thread and forbids actor-isolated cleanup here.
        if (releaseContext != nullptr) {
            releaseContext(callbacks.context);
        }
    }

    std::atomic<ULONG> references{1};
    std::atomic<bool> available{true};
};

namespace {

class COMCallPin {
public:
    explicit COMCallPin(IUnknown *provider) : provider_(provider) { provider_->AddRef(); }
    ~COMCallPin() { provider_->Release(); }
    COMCallPin(const COMCallPin &) = delete;
    COMCallPin &operator=(const COMCallPin &) = delete;

private:
    IUnknown *provider_;
};

template <typename Interface>
struct COMRelease {
    void operator()(Interface *value) const {
        if (value != nullptr) value->Release();
    }
};

template <typename Interface>
using COMOwned = std::unique_ptr<Interface, COMRelease<Interface>>;

struct SafeArrayRelease {
    void operator()(SAFEARRAY *value) const {
        if (value != nullptr) SafeArrayDestroy(value);
    }
};
using OwnedSafeArray = std::unique_ptr<SAFEARRAY, SafeArrayRelease>;

struct BSTRRelease {
    void operator()(OLECHAR *value) const {
        if (value != nullptr) SysFreeString(value);
    }
};
using OwnedBSTR = std::unique_ptr<OLECHAR, BSTRRelease>;

bool isNavigationDirection(int32_t direction) {
    return direction >= SWU_UIA_NAV_PARENT && direction <= SWU_UIA_NAV_LAST_CHILD;
}

// COM identity is independent of the UI owner's lifetime. Dynamic pattern
// availability is advertised only by GetPatternProvider; QueryInterface must
// keep its interface set fixed, including while a client holds a stale pattern.
class SWUProvider : public IRawElementProviderSimple,
                    public IRawElementProviderFragment,
                    public IRawElementProviderFragmentRoot,
                    public IInvokeProvider,
                    public IValueProvider,
                    public IToggleProvider,
                    public ISelectionProvider,
                    public ISelectionItemProvider,
                    public IVirtualizedItemProvider {
public:
    SWUProvider(SWUUIAProviderContext *context, HWND hwnd, uint64_t element, bool isRoot)
        : context_(context), hwnd_(hwnd), element_(element), isRoot_(isRoot) {
        context_->retain();
    }

    IFACEMETHODIMP QueryInterface(REFIID riid, void **ppv) override {
        if (ppv == nullptr) return E_POINTER;
        *ppv = nullptr;
        if (riid == IID_IUnknown || riid == IID_IRawElementProviderSimple) {
            *ppv = static_cast<IRawElementProviderSimple *>(this);
        } else if (riid == IID_IRawElementProviderFragment) {
            *ppv = static_cast<IRawElementProviderFragment *>(this);
        } else if (riid == IID_IRawElementProviderFragmentRoot && isRoot_) {
            *ppv = static_cast<IRawElementProviderFragmentRoot *>(this);
        } else if (riid == IID_IInvokeProvider) {
            *ppv = static_cast<IInvokeProvider *>(this);
        } else if (riid == IID_IValueProvider) {
            *ppv = static_cast<IValueProvider *>(this);
        } else if (riid == IID_IToggleProvider) {
            *ppv = static_cast<IToggleProvider *>(this);
        } else if (riid == IID_ISelectionProvider) {
            *ppv = static_cast<ISelectionProvider *>(this);
        } else if (riid == IID_ISelectionItemProvider) {
            *ppv = static_cast<ISelectionItemProvider *>(this);
        } else if (riid == IID_IVirtualizedItemProvider) {
            *ppv = static_cast<IVirtualizedItemProvider *>(this);
        } else {
            return E_NOINTERFACE;
        }
        AddRef();
        return S_OK;
    }

    IFACEMETHODIMP_(ULONG) AddRef() override {
        return refCount_.fetch_add(1, std::memory_order_relaxed) + 1;
    }

    IFACEMETHODIMP_(ULONG) Release() override {
        ULONG count = refCount_.fetch_sub(1, std::memory_order_acq_rel) - 1;
        if (count == 0) delete this;
        return count;
    }

    bool isAvailable() const { return context_->isAvailable(); }
    void revoke() { context_->revoke(); }

    // IRawElementProviderSimple

    IFACEMETHODIMP get_ProviderOptions(ProviderOptions *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = static_cast<ProviderOptions>(0);
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        *pRetVal = static_cast<ProviderOptions>(
            ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading);
        return S_OK;
    }

    IFACEMETHODIMP GetPatternProvider(PATTERNID patternId, IUnknown **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;

        bool supported = false;
        IUnknown *pattern = nullptr;
        HRESULT result = S_OK;
        switch (patternId) {
        case UIA_InvokePatternId:
            result = supportsInvoke(supported);
            pattern = static_cast<IInvokeProvider *>(this);
            break;
        case UIA_ValuePatternId:
            result = supportsPattern(SWU_UIA_PATTERN_VALUE, supported);
            pattern = static_cast<IValueProvider *>(this);
            break;
        case UIA_TogglePatternId:
            result = supportsPattern(SWU_UIA_PATTERN_TOGGLE, supported);
            pattern = static_cast<IToggleProvider *>(this);
            break;
        case UIA_SelectionPatternId:
            result = supportsPattern(SWU_UIA_PATTERN_SELECTION, supported);
            pattern = static_cast<ISelectionProvider *>(this);
            break;
        case UIA_SelectionItemPatternId:
            result = supportsPattern(SWU_UIA_PATTERN_SELECTION_ITEM, supported);
            pattern = static_cast<ISelectionItemProvider *>(this);
            break;
        case UIA_VirtualizedItemPatternId:
            result = supportsPattern(SWU_UIA_PATTERN_VIRTUALIZED_ITEM, supported);
            pattern = static_cast<IVirtualizedItemProvider *>(this);
            break;
        default:
            break;
        }
        if (FAILED(result)) return result;
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (supported) {
            pattern->AddRef();
            *pRetVal = pattern;
        }
        return S_OK;
    }

    IFACEMETHODIMP GetPropertyValue(PROPERTYID propertyId, VARIANT *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        VariantInit(pRetVal);
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;

        VARIANT value;
        VariantInit(&value);
        HRESULT result = S_OK;
        switch (propertyId) {
        case UIA_NamePropertyId:
            result = setStringProperty(&value, SWU_UIA_STRING_NAME);
            break;
        case UIA_ValueValuePropertyId: {
            int32_t password = -1;
            result = boolProperty(SWU_UIA_BOOL_IS_PASSWORD, password);
            if (SUCCEEDED(result) && password != 1) {
                result = setStringProperty(&value, SWU_UIA_STRING_VALUE);
            }
            break;
        }
        case UIA_HelpTextPropertyId:
            result = setStringProperty(&value, SWU_UIA_STRING_HELP_TEXT);
            break;
        case UIA_AutomationIdPropertyId:
            result = setStringProperty(&value, SWU_UIA_STRING_AUTOMATION_ID);
            break;
        case UIA_ClassNamePropertyId:
            result = setStringProperty(&value, SWU_UIA_STRING_CLASS_NAME);
            break;
        case UIA_ControlTypePropertyId: {
            int32_t controlType = 0;
            result = readCallback(callbacks().getControlType, controlType, element_);
            if (SUCCEEDED(result)) {
                value.vt = VT_I4;
                value.lVal = controlType;
            }
            break;
        }
        case UIA_IsEnabledPropertyId:
            result = setBoolProperty(&value, SWU_UIA_BOOL_IS_ENABLED);
            break;
        case UIA_HasKeyboardFocusPropertyId:
            result = setBoolProperty(&value, SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS);
            break;
        case UIA_IsKeyboardFocusablePropertyId:
            result = setBoolProperty(&value, SWU_UIA_BOOL_IS_KEYBOARD_FOCUSABLE);
            break;
        case UIA_IsOffscreenPropertyId:
            result = setBoolProperty(&value, SWU_UIA_BOOL_IS_OFFSCREEN);
            break;
        case UIA_IsPasswordPropertyId:
            result = setBoolProperty(&value, SWU_UIA_BOOL_IS_PASSWORD);
            break;
        case UIA_ValueIsReadOnlyPropertyId:
            result = setBoolProperty(&value, SWU_UIA_BOOL_IS_READ_ONLY);
            break;
        case UIA_SelectionItemIsSelectedPropertyId:
            result = setBoolProperty(&value, SWU_UIA_BOOL_IS_SELECTED);
            break;
        case UIA_ToggleToggleStatePropertyId: {
            int32_t state = -1;
            if (callbacks().getToggleState != nullptr) {
                result = readCallback(callbacks().getToggleState, state, element_);
            }
            if (SUCCEEDED(result) && state >= SWU_UIA_TOGGLE_OFF && state <= SWU_UIA_TOGGLE_INDETERMINATE) {
                value.vt = VT_I4;
                value.lVal = state;
            }
            break;
        }
        case UIA_IsContentElementPropertyId:
        case UIA_IsControlElementPropertyId:
            value.vt = VT_BOOL;
            value.boolVal = VARIANT_TRUE;
            break;
        default:
            break;
        }
        if (!isAvailable()) result = UIA_E_ELEMENTNOTAVAILABLE;
        if (FAILED(result)) {
            VariantClear(&value);
            return result;
        }
        *pRetVal = value;
        return S_OK;
    }

    IFACEMETHODIMP get_HostRawElementProvider(IRawElementProviderSimple **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (!isRoot_ || hwnd_ == nullptr) return S_OK;

        IRawElementProviderSimple *raw = nullptr;
        HRESULT result = UiaHostProviderFromHwnd(hwnd_, &raw);
        COMOwned<IRawElementProviderSimple> host(raw);
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (FAILED(result)) return result;
        *pRetVal = host.release();
        return S_OK;
    }

    // IRawElementProviderFragment

    IFACEMETHODIMP Navigate(NavigateDirection direction, IRawElementProviderFragment **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        if (!isNavigationDirection(static_cast<int32_t>(direction))) return E_INVALIDARG;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        uint64_t target = SWU_UIA_NO_ELEMENT;
        HRESULT result = readCallback(callbacks().navigate, target, element_, static_cast<int32_t>(direction));
        if (FAILED(result)) return result;
        return makeRelatedProvider(target, pRetVal);
    }

    IFACEMETHODIMP GetRuntimeId(SAFEARRAY **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        int32_t buffer[8] = {};
        int32_t count = 0;
        HRESULT result = readCallback(callbacks().getRuntimeId, count, element_, buffer, 8);
        if (FAILED(result)) return result;
        if (count <= 0) return S_OK;
        if (count > 8) return UIA_E_INVALIDOPERATION;
        OwnedSafeArray values(SafeArrayCreateVector(VT_I4, 0, static_cast<ULONG>(count)));
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (!values) return E_OUTOFMEMORY;
        for (LONG index = 0; index < count; ++index) {
            result = SafeArrayPutElement(values.get(), &index, &buffer[index]);
            if (FAILED(result)) return result;
        }
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        *pRetVal = values.release();
        return S_OK;
    }

    IFACEMETHODIMP get_BoundingRectangle(UiaRect *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = UiaRect{0, 0, 0, 0};
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        UiaRect value{0, 0, 0, 0};
        HRESULT result = invokeCallback(
            callbacks().getBoundingRectangle, element_, &value.left, &value.top, &value.width, &value.height);
        if (FAILED(result)) return result;
        *pRetVal = value;
        return S_OK;
    }

    IFACEMETHODIMP GetEmbeddedFragmentRoots(SAFEARRAY **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        return availabilityResult();
    }

    IFACEMETHODIMP SetFocus() override {
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        return invokeCallback(callbacks().setFocus, element_);
    }

    IFACEMETHODIMP get_FragmentRoot(IRawElementProviderFragmentRoot **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        return makeRelatedProvider(SWU_UIA_ROOT_ELEMENT, pRetVal);
    }

    // IRawElementProviderFragmentRoot

    IFACEMETHODIMP ElementProviderFromPoint(double x, double y, IRawElementProviderFragment **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        uint64_t target = SWU_UIA_NO_ELEMENT;
        HRESULT result = readCallback(callbacks().elementFromPoint, target, x, y);
        if (FAILED(result)) return result;
        return makeRelatedProvider(target, pRetVal);
    }

    IFACEMETHODIMP GetFocus(IRawElementProviderFragment **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        uint64_t target = SWU_UIA_NO_ELEMENT;
        HRESULT result = readCallback(callbacks().focusedElement, target);
        if (FAILED(result)) return result;
        return makeRelatedProvider(target, pRetVal);
    }

    // IInvokeProvider

    IFACEMETHODIMP Invoke() override {
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        bool enabled = false;
        HRESULT result = isEnabled(enabled);
        if (FAILED(result)) return result;
        if (!enabled) return UIA_E_ELEMENTNOTENABLED;
        return invokeCallback(callbacks().invokeDefaultAction, element_);
    }

    // IValueProvider

    IFACEMETHODIMP SetValue(LPCWSTR value) override {
        if (value == nullptr) return E_INVALIDARG;
        size_t length = wcslen(value);
        if (length > static_cast<size_t>((std::numeric_limits<int32_t>::max)())) return E_INVALIDARG;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        bool enabled = false;
        HRESULT result = isEnabled(enabled);
        if (FAILED(result)) return result;
        if (!enabled) return UIA_E_ELEMENTNOTENABLED;
        bool readOnly = true;
        result = isReadOnly(readOnly);
        if (FAILED(result)) return result;
        if (readOnly) return UIA_E_INVALIDOPERATION;
        int32_t changed = 0;
        result = readCallback(
            callbacks().setValue, changed, element_, reinterpret_cast<const uint16_t *>(value),
            static_cast<int32_t>(length));
        if (FAILED(result)) return result;
        return changed != 0 ? S_OK : UIA_E_INVALIDOPERATION;
    }

    IFACEMETHODIMP get_Value(BSTR *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        uint16_t *raw = nullptr;
        HRESULT result = S_OK;
        if (callbacks().copyStringProperty != nullptr) {
            result = readCallback(callbacks().copyStringProperty, raw, element_, SWU_UIA_STRING_VALUE);
        }
        OwnedBSTR value(reinterpret_cast<BSTR>(raw));
        if (FAILED(result)) return result;
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (!value) value.reset(SysAllocStringLen(nullptr, 0));
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (!value) return E_OUTOFMEMORY;
        *pRetVal = value.release();
        return S_OK;
    }

    IFACEMETHODIMP get_IsReadOnly(BOOL *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = FALSE;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        bool value = true;
        HRESULT result = isReadOnly(value);
        if (FAILED(result)) return result;
        *pRetVal = value ? TRUE : FALSE;
        return S_OK;
    }

    // IToggleProvider

    IFACEMETHODIMP Toggle() override {
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        return performAction(callbacks().toggle);
    }

    IFACEMETHODIMP get_ToggleState(ToggleState *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = ToggleState_Off;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        int32_t value = -1;
        HRESULT result = readCallback(callbacks().getToggleState, value, element_);
        if (FAILED(result)) return result;
        if (value < SWU_UIA_TOGGLE_OFF || value > SWU_UIA_TOGGLE_INDETERMINATE) return UIA_E_INVALIDOPERATION;
        *pRetVal = static_cast<ToggleState>(value);
        return S_OK;
    }

    // ISelectionProvider

    IFACEMETHODIMP GetSelection(SAFEARRAY **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        int32_t count = 0;
        HRESULT result = readCallback(callbacks().getSelection, count, element_, nullptr, 0);
        if (FAILED(result)) return result;
        if (count < 0 || count > 16384) return UIA_E_INVALIDOPERATION;
        std::vector<uint64_t> ids;
        try {
            ids.resize(static_cast<size_t>(count));
        } catch (const std::bad_alloc &) {
            return E_OUTOFMEMORY;
        }
        if (count > 0) {
            int32_t actual = 0;
            result = readCallback(callbacks().getSelection, actual, element_, ids.data(), count);
            if (FAILED(result)) return result;
            if (actual < 0 || actual > count) return UIA_E_INVALIDOPERATION;
            count = actual;
        }
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        OwnedSafeArray selection(SafeArrayCreateVector(VT_UNKNOWN, 0, static_cast<ULONG>(count)));
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (!selection) return E_OUTOFMEMORY;
        for (LONG index = 0; index < count; ++index) {
            IRawElementProviderSimple *raw = nullptr;
            result = makeRelatedProvider(ids[static_cast<size_t>(index)], &raw);
            COMOwned<IRawElementProviderSimple> provider(raw);
            if (FAILED(result)) return result;
            if (!provider) return UIA_E_INVALIDOPERATION;
            IUnknown *unknown = provider.get();
            result = SafeArrayPutElement(selection.get(), &index, unknown);
            if (FAILED(result)) return result;
        }
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        *pRetVal = selection.release();
        return S_OK;
    }

    IFACEMETHODIMP get_CanSelectMultiple(BOOL *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = FALSE;
        return availabilityResult();
    }

    IFACEMETHODIMP get_IsSelectionRequired(BOOL *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = FALSE;
        return availabilityResult();
    }

    // ISelectionItemProvider

    IFACEMETHODIMP Select() override {
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        return performAction(callbacks().select);
    }

    IFACEMETHODIMP AddToSelection() override {
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        return performAction(callbacks().addToSelection);
    }

    IFACEMETHODIMP RemoveFromSelection() override {
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        return performAction(callbacks().removeFromSelection);
    }

    IFACEMETHODIMP get_IsSelected(BOOL *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = FALSE;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        int32_t value = -1;
        HRESULT result = boolProperty(SWU_UIA_BOOL_IS_SELECTED, value);
        if (FAILED(result)) return result;
        if (value < 0) return UIA_E_INVALIDOPERATION;
        *pRetVal = value != 0 ? TRUE : FALSE;
        return S_OK;
    }

    IFACEMETHODIMP get_SelectionContainer(IRawElementProviderSimple **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (callbacks().getSelectionContainer == nullptr) return S_OK;
        uint64_t target = SWU_UIA_NO_ELEMENT;
        HRESULT result = readCallback(callbacks().getSelectionContainer, target, element_);
        if (FAILED(result)) return result;
        return makeRelatedProvider(target, pRetVal);
    }

    // IVirtualizedItemProvider

    IFACEMETHODIMP Realize() override {
        COMCallPin pin(static_cast<IRawElementProviderSimple *>(this));
        return performAction(callbacks().realizeVirtualizedItem);
    }

private:
    ~SWUProvider() { context_->release(); }

    const SWUUIACallbacks &callbacks() const { return context_->callbacks; }
    HRESULT availabilityResult() const { return isAvailable() ? S_OK : UIA_E_ELEMENTNOTAVAILABLE; }

    // Only call these helpers while a COMCallPin holds this provider. A
    // callback may synchronously drop every external bridge/provider owner.
    template <typename Callback, typename Value, typename... Arguments>
    HRESULT readCallback(Callback callback, Value &result, Arguments... arguments) {
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (callback == nullptr) return UIA_E_INVALIDOPERATION;
        result = callback(callbacks().context, arguments...);
        return availabilityResult();
    }

    template <typename Callback, typename... Arguments>
    HRESULT invokeCallback(Callback callback, Arguments... arguments) {
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (callback == nullptr) return UIA_E_INVALIDOPERATION;
        callback(callbacks().context, arguments...);
        return availabilityResult();
    }

    template <typename Interface>
    HRESULT makeRelatedProvider(uint64_t element, Interface **result) {
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (element == SWU_UIA_NO_ELEMENT) return S_OK;
        COMOwned<SWUProvider> provider(new (std::nothrow) SWUProvider(
            context_, hwnd_, element, element == SWU_UIA_ROOT_ELEMENT));
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (!provider) return E_OUTOFMEMORY;
        *result = static_cast<Interface *>(provider.release());
        return S_OK;
    }

    HRESULT supportsInvoke(bool &result) {
        result = false;
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (callbacks().hasInvokeAction == nullptr) return S_OK;
        int32_t supported = 0;
        HRESULT status = readCallback(callbacks().hasInvokeAction, supported, element_);
        if (SUCCEEDED(status)) result = supported != 0;
        return status;
    }

    HRESULT supportsPattern(int32_t pattern, bool &result) {
        result = false;
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (callbacks().supportsPattern == nullptr) return S_OK;
        int32_t supported = 0;
        HRESULT status = readCallback(callbacks().supportsPattern, supported, element_, pattern);
        if (SUCCEEDED(status)) result = supported != 0;
        return status;
    }

    HRESULT boolProperty(int32_t property, int32_t &result) {
        result = -1;
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (callbacks().getBoolProperty == nullptr) return S_OK;
        return readCallback(callbacks().getBoolProperty, result, element_, property);
    }

    HRESULT isEnabled(bool &result) {
        int32_t value = -1;
        HRESULT status = boolProperty(SWU_UIA_BOOL_IS_ENABLED, value);
        if (SUCCEEDED(status)) result = value != 0;
        return status;
    }

    HRESULT isReadOnly(bool &result) {
        int32_t value = -1;
        HRESULT status = boolProperty(SWU_UIA_BOOL_IS_READ_ONLY, value);
        if (SUCCEEDED(status)) result = value != 0;
        return status;
    }

    HRESULT performAction(int32_t (*action)(void *, uint64_t)) {
        bool enabled = false;
        HRESULT result = isEnabled(enabled);
        if (FAILED(result)) return result;
        if (!enabled) return UIA_E_ELEMENTNOTENABLED;
        int32_t performed = 0;
        result = readCallback(action, performed, element_);
        if (FAILED(result)) return result;
        return performed != 0 ? S_OK : UIA_E_INVALIDOPERATION;
    }

    HRESULT setStringProperty(VARIANT *out, int32_t property) {
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (callbacks().copyStringProperty == nullptr) return S_OK;
        uint16_t *raw = nullptr;
        HRESULT result = readCallback(callbacks().copyStringProperty, raw, element_, property);
        OwnedBSTR value(reinterpret_cast<BSTR>(raw));
        if (FAILED(result)) return result;
        if (value) {
            out->vt = VT_BSTR;
            out->bstrVal = value.release();
        }
        return S_OK;
    }

    HRESULT setBoolProperty(VARIANT *out, int32_t property) {
        int32_t value = -1;
        HRESULT result = boolProperty(property, value);
        if (FAILED(result)) return result;
        if (value >= 0) {
            out->vt = VT_BOOL;
            out->boolVal = value != 0 ? VARIANT_TRUE : VARIANT_FALSE;
        }
        return S_OK;
    }

    SWUUIAProviderContext *const context_;
    const HWND hwnd_;
    const uint64_t element_;
    const bool isRoot_;
    std::atomic<ULONG> refCount_{1};
};

SWUProvider *asProvider(void *provider) {
    return reinterpret_cast<SWUProvider *>(provider);
}

IRawElementProviderSimple *asSimple(void *provider) {
    return static_cast<IRawElementProviderSimple *>(asProvider(provider));
}

IRawElementProviderFragment *asFragment(void *provider) {
    return static_cast<IRawElementProviderFragment *>(asProvider(provider));
}

IRawElementProviderFragmentRoot *asRoot(void *provider) {
    return static_cast<IRawElementProviderFragmentRoot *>(asProvider(provider));
}

HRESULT arrayBounds(SAFEARRAY *array, LONG &lower, LONG &upper) {
    lower = 0;
    upper = -1;
    if (array == nullptr) return S_OK;
    HRESULT result = SafeArrayGetLBound(array, 1, &lower);
    if (FAILED(result)) return result;
    return SafeArrayGetUBound(array, 1, &upper);
}

bool boolPropertyID(int32_t neutralKey, PROPERTYID &property) {
    switch (neutralKey) {
    case SWU_UIA_BOOL_IS_ENABLED: property = UIA_IsEnabledPropertyId; return true;
    case SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS: property = UIA_HasKeyboardFocusPropertyId; return true;
    case SWU_UIA_BOOL_IS_KEYBOARD_FOCUSABLE: property = UIA_IsKeyboardFocusablePropertyId; return true;
    case SWU_UIA_BOOL_IS_OFFSCREEN: property = UIA_IsOffscreenPropertyId; return true;
    case SWU_UIA_BOOL_IS_PASSWORD: property = UIA_IsPasswordPropertyId; return true;
    case SWU_UIA_BOOL_IS_READ_ONLY: property = UIA_ValueIsReadOnlyPropertyId; return true;
    case SWU_UIA_BOOL_IS_SELECTED: property = UIA_SelectionItemIsSelectedPropertyId; return true;
    default: return false;
    }
}

const IID &interfaceID(int32_t kind) {
    switch (kind) {
    case SWU_UIA_INTERFACE_UNKNOWN: return IID_IUnknown;
    case SWU_UIA_INTERFACE_SIMPLE: return IID_IRawElementProviderSimple;
    case SWU_UIA_INTERFACE_FRAGMENT: return IID_IRawElementProviderFragment;
    case SWU_UIA_INTERFACE_FRAGMENT_ROOT: return IID_IRawElementProviderFragmentRoot;
    case SWU_UIA_INTERFACE_INVOKE: return IID_IInvokeProvider;
    case SWU_UIA_INTERFACE_VALUE: return IID_IValueProvider;
    case SWU_UIA_INTERFACE_TOGGLE: return IID_IToggleProvider;
    case SWU_UIA_INTERFACE_SELECTION: return IID_ISelectionProvider;
    case SWU_UIA_INTERFACE_SELECTION_ITEM: return IID_ISelectionItemProvider;
    case SWU_UIA_INTERFACE_VIRTUALIZED_ITEM: return IID_IVirtualizedItemProvider;
    default: return IID_NULL;
    }
}

}  // namespace

extern "C" {

SWUUIAProviderContext *SWU_UIACreateProviderContext(
    const SWUUIACallbacks *callbacks, void (*releaseContext)(void *)) {
    if (callbacks == nullptr) return nullptr;
    return new (std::nothrow) SWUUIAProviderContext(*callbacks, releaseContext);
}

void SWU_UIARetainProviderContext(SWUUIAProviderContext *context) {
    if (context != nullptr) context->retain();
}

void SWU_UIAReleaseProviderContext(SWUUIAProviderContext *context) {
    if (context != nullptr) context->release();
}

void SWU_UIARevokeProviderContext(SWUUIAProviderContext *context) {
    if (context != nullptr) context->revoke();
}

int SWU_UIAProviderContextIsAvailable(SWUUIAProviderContext *context) {
    return context != nullptr && context->isAvailable() ? 1 : 0;
}

void *SWU_UIACreateRootProviderWithContext(SWUUIAProviderContext *context, void *hwnd) {
    return SWU_UIACreateElementProviderWithContext(context, hwnd, SWU_UIA_ROOT_ELEMENT);
}

void *SWU_UIACreateElementProviderWithContext(
    SWUUIAProviderContext *context, void *hwnd, uint64_t element) {
    if (context == nullptr || !context->isAvailable() || element == SWU_UIA_NO_ELEMENT) return nullptr;
    COMOwned<SWUProvider> provider(new (std::nothrow) SWUProvider(
        context, static_cast<HWND>(hwnd), element, element == SWU_UIA_ROOT_ELEMENT));
    if (!context->isAvailable()) return nullptr;
    return provider.release();
}

void *SWU_UIACreateRootProvider(const SWUUIACallbacks *callbacks, void *hwnd) {
    return SWU_UIACreateElementProvider(callbacks, hwnd, SWU_UIA_ROOT_ELEMENT);
}

void *SWU_UIACreateElementProvider(const SWUUIACallbacks *callbacks, void *hwnd, uint64_t element) {
    SWUUIAProviderContext *context = SWU_UIACreateProviderContext(callbacks, nullptr);
    if (context == nullptr) return nullptr;
    void *provider = SWU_UIACreateElementProviderWithContext(context, hwnd, element);
    context->release();
    return provider;
}

void SWU_UIAAddRefProvider(void *provider) {
    if (provider != nullptr) reinterpret_cast<IUnknown *>(provider)->AddRef();
}

void SWU_UIAReleaseProvider(void *provider) {
    if (provider != nullptr) reinterpret_cast<IUnknown *>(provider)->Release();
}

intptr_t SWU_UIAReturnRawElementProvider(void *hwnd, uintptr_t wParam, intptr_t lParam, void *provider) {
    if (provider == nullptr) {
        if (hwnd == nullptr || wParam != 0 || lParam != 0) return 0;
        return static_cast<intptr_t>(UiaReturnRawElementProvider(static_cast<HWND>(hwnd), 0, 0, nullptr));
    }
    COMCallPin pin(asSimple(provider));
    if (!asProvider(provider)->isAvailable()) return 0;
    // This call borrows the provider. The temporary reference is balanced even
    // when the OS reenters the host and drops its owning reference.
    LRESULT result = UiaReturnRawElementProvider(
        static_cast<HWND>(hwnd), static_cast<WPARAM>(wParam), static_cast<LPARAM>(lParam), asSimple(provider));
    return asProvider(provider)->isAvailable() ? static_cast<intptr_t>(result) : 0;
}

int SWU_UIAClientsAreListening(void) {
    return UiaClientsAreListening() ? 1 : 0;
}

void SWU_UIARaiseAutomationFocusChanged(void *provider) {
    if (provider == nullptr) return;
    COMCallPin pin(asSimple(provider));
    if (asProvider(provider)->isAvailable()) {
        UiaRaiseAutomationEvent(asSimple(provider), UIA_AutomationFocusChangedEventId);
    }
}

void SWU_UIARaiseStructureChanged(void *provider) {
    if (provider == nullptr) return;
    COMCallPin pin(asSimple(provider));
    if (asProvider(provider)->isAvailable()) {
        UiaRaiseStructureChangedEvent(asSimple(provider), StructureChangeType_ChildrenInvalidated, nullptr, 0);
    }
}

void SWU_UIARaiseLiveRegionChanged(void *provider) {
    if (provider == nullptr) return;
    COMCallPin pin(asSimple(provider));
    if (asProvider(provider)->isAvailable()) {
        UiaRaiseAutomationEvent(asSimple(provider), UIA_LiveRegionChangedEventId);
    }
}

int32_t SWU_UIATryDisconnectProvider(void *provider) {
    if (provider == nullptr) return E_POINTER;
    COMCallPin pin(asSimple(provider));
    asProvider(provider)->revoke();
    // The owner may already have revoked the context. Do not gate native
    // cleanup on availability or restore it when the OS refuses disconnection.
    return UiaDisconnectProvider(asSimple(provider));
}

void SWU_UIADisconnectProvider(void *provider) {
    if (provider != nullptr) SWU_UIATryDisconnectProvider(provider);
}

uint16_t *SWU_UIACreateBSTR(const uint16_t *chars, int32_t length) {
    if (chars == nullptr || length < 0) return nullptr;
    return reinterpret_cast<uint16_t *>(SysAllocStringLen(
        reinterpret_cast<const OLECHAR *>(chars), static_cast<UINT>(length)));
}

void SWU_UIAFreeString(uint16_t *bstr) {
    if (bstr != nullptr) SysFreeString(reinterpret_cast<BSTR>(bstr));
}

// These peers deliberately do not add a second provider pin around a COM
// method. The actual vtable implementation owns its call pin, including when
// a callback drops the last external reference. After that call, peers touch
// only local results and independently owned returned interfaces.

int32_t SWU_UIAProviderQueryInterfaceResult(void *provider, int32_t interfaceKind, void **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (provider == nullptr) return E_POINTER;
    return reinterpret_cast<IUnknown *>(provider)->QueryInterface(interfaceID(interfaceKind), result);
}

int32_t SWU_UIAProviderGetPatternResult(void *provider, int32_t pattern, void **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (provider == nullptr) return E_POINTER;
    IUnknown *raw = nullptr;
    HRESULT status = asSimple(provider)->GetPatternProvider(pattern, &raw);
    COMOwned<IUnknown> value(raw);
    if (FAILED(status)) return status;
    *result = value.release();
    return S_OK;
}

int32_t SWU_UIAProviderNavigateResult(void *provider, int32_t direction, void **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (!isNavigationDirection(direction)) return E_INVALIDARG;
    if (provider == nullptr) return E_POINTER;
    IRawElementProviderFragment *raw = nullptr;
    HRESULT status = asFragment(provider)->Navigate(static_cast<NavigateDirection>(direction), &raw);
    COMOwned<IRawElementProviderFragment> value(raw);
    if (FAILED(status)) return status;
    *result = value ? static_cast<SWUProvider *>(value.release()) : nullptr;
    return S_OK;
}

int32_t SWU_UIAProviderGetRuntimeIdResult(
    void *provider, int32_t *buffer, int32_t capacity, int32_t *count) {
    if (count == nullptr) return E_POINTER;
    *count = 0;
    if (capacity < 0) return E_INVALIDARG;
    if (buffer == nullptr && capacity > 0) return E_POINTER;
    if (provider == nullptr) return E_POINTER;
    SAFEARRAY *raw = nullptr;
    HRESULT status = asFragment(provider)->GetRuntimeId(&raw);
    OwnedSafeArray values(raw);
    if (FAILED(status)) return status;
    if (!values || capacity == 0) return S_OK;
    LONG lower = 0;
    LONG upper = -1;
    status = arrayBounds(values.get(), lower, upper);
    if (FAILED(status)) return status;
    int32_t copied[8] = {};
    int32_t copiedCount = 0;
    for (LONG index = lower; index <= upper && copiedCount < capacity; ++index) {
        if (copiedCount == 8) return UIA_E_INVALIDOPERATION;
        status = SafeArrayGetElement(values.get(), &index, &copied[copiedCount]);
        if (FAILED(status)) return status;
        ++copiedCount;
    }
    for (int32_t index = 0; index < copiedCount; ++index) buffer[index] = copied[index];
    *count = copiedCount;
    return S_OK;
}

int32_t SWU_UIAProviderGetBoundingRectangleResult(
    void *provider, double *left, double *top, double *width, double *height) {
    if (left != nullptr) *left = 0;
    if (top != nullptr) *top = 0;
    if (width != nullptr) *width = 0;
    if (height != nullptr) *height = 0;
    if (left == nullptr || top == nullptr || width == nullptr || height == nullptr) return E_POINTER;
    if (provider == nullptr) return E_POINTER;
    UiaRect value{0, 0, 0, 0};
    HRESULT status = asFragment(provider)->get_BoundingRectangle(&value);
    if (FAILED(status)) return status;
    *left = value.left;
    *top = value.top;
    *width = value.width;
    *height = value.height;
    return S_OK;
}

int32_t SWU_UIAProviderGetNameResult(void *provider, uint16_t **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (provider == nullptr) return E_POINTER;
    VARIANT value;
    VariantInit(&value);
    HRESULT status = asSimple(provider)->GetPropertyValue(UIA_NamePropertyId, &value);
    if (SUCCEEDED(status) && value.vt == VT_BSTR) {
        *result = reinterpret_cast<uint16_t *>(value.bstrVal);
        value.vt = VT_EMPTY;
    }
    VariantClear(&value);
    return status;
}

int32_t SWU_UIAProviderGetControlTypeResult(void *provider, int32_t *result) {
    if (result == nullptr) return E_POINTER;
    *result = 0;
    if (provider == nullptr) return E_POINTER;
    VARIANT value;
    VariantInit(&value);
    HRESULT status = asSimple(provider)->GetPropertyValue(UIA_ControlTypePropertyId, &value);
    if (SUCCEEDED(status) && value.vt == VT_I4) *result = value.lVal;
    VariantClear(&value);
    return status;
}

int32_t SWU_UIAProviderGetBoolPropertyResult(
    void *provider, int32_t neutralKey, int32_t *result, int32_t *hasValue) {
    if (result != nullptr) *result = 0;
    if (hasValue != nullptr) *hasValue = 0;
    if (result == nullptr || hasValue == nullptr) return E_POINTER;
    PROPERTYID property = 0;
    if (!boolPropertyID(neutralKey, property)) return E_INVALIDARG;
    if (provider == nullptr) return E_POINTER;
    VARIANT value;
    VariantInit(&value);
    HRESULT status = asSimple(provider)->GetPropertyValue(property, &value);
    if (SUCCEEDED(status) && value.vt == VT_BOOL) {
        *result = value.boolVal != VARIANT_FALSE ? 1 : 0;
        *hasValue = 1;
    }
    VariantClear(&value);
    return status;
}

int32_t SWU_UIAProviderGetProviderOptionsResult(void *provider, int32_t *result) {
    if (result == nullptr) return E_POINTER;
    *result = 0;
    if (provider == nullptr) return E_POINTER;
    ProviderOptions value = static_cast<ProviderOptions>(0);
    HRESULT status = asSimple(provider)->get_ProviderOptions(&value);
    if (SUCCEEDED(status)) *result = static_cast<int32_t>(value);
    return status;
}

int32_t SWU_UIAProviderGetEmbeddedFragmentRootCountResult(void *provider, int32_t *result) {
    if (result == nullptr) return E_POINTER;
    *result = 0;
    if (provider == nullptr) return E_POINTER;
    SAFEARRAY *raw = nullptr;
    HRESULT status = asFragment(provider)->GetEmbeddedFragmentRoots(&raw);
    OwnedSafeArray roots(raw);
    if (FAILED(status)) return status;
    LONG lower = 0;
    LONG upper = -1;
    status = arrayBounds(roots.get(), lower, upper);
    if (FAILED(status)) return status;
    *result = upper >= lower ? upper - lower + 1 : 0;
    return S_OK;
}

int32_t SWU_UIAProviderGetHostRawElementProviderResult(void *provider, void **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (provider == nullptr) return E_POINTER;
    IRawElementProviderSimple *raw = nullptr;
    HRESULT status = asSimple(provider)->get_HostRawElementProvider(&raw);
    COMOwned<IRawElementProviderSimple> value(raw);
    if (FAILED(status)) return status;
    *result = value.release();
    return S_OK;
}

int32_t SWU_UIAProviderInvokeResult(void *invokeProvider) {
    if (invokeProvider == nullptr) return E_POINTER;
    return static_cast<IInvokeProvider *>(invokeProvider)->Invoke();
}

int32_t SWU_UIAValueProviderGetValueResult(void *valueProvider, uint16_t **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (valueProvider == nullptr) return E_POINTER;
    BSTR raw = nullptr;
    HRESULT status = static_cast<IValueProvider *>(valueProvider)->get_Value(&raw);
    OwnedBSTR value(raw);
    if (FAILED(status)) return status;
    *result = reinterpret_cast<uint16_t *>(value.release());
    return S_OK;
}

int32_t SWU_UIAValueProviderSetValueResult(
    void *valueProvider, const uint16_t *value, int32_t length) {
    if (value == nullptr || length < 0) return E_INVALIDARG;
    if (valueProvider == nullptr) return E_POINTER;
    std::vector<wchar_t> terminated;
    try {
        terminated.resize(static_cast<size_t>(length) + 1, 0);
    } catch (const std::bad_alloc &) {
        return E_OUTOFMEMORY;
    }
    for (int32_t index = 0; index < length; ++index) {
        terminated[static_cast<size_t>(index)] = static_cast<wchar_t>(value[index]);
    }
    return static_cast<IValueProvider *>(valueProvider)->SetValue(terminated.data());
}

int32_t SWU_UIAValueProviderIsReadOnlyResult(void *valueProvider, int32_t *result) {
    if (result == nullptr) return E_POINTER;
    *result = 0;
    if (valueProvider == nullptr) return E_POINTER;
    BOOL value = FALSE;
    HRESULT status = static_cast<IValueProvider *>(valueProvider)->get_IsReadOnly(&value);
    if (SUCCEEDED(status)) *result = value != FALSE ? 1 : 0;
    return status;
}

int32_t SWU_UIAToggleProviderGetStateResult(void *toggleProvider, int32_t *result) {
    if (result == nullptr) return E_POINTER;
    *result = 0;
    if (toggleProvider == nullptr) return E_POINTER;
    ToggleState value = ToggleState_Off;
    HRESULT status = static_cast<IToggleProvider *>(toggleProvider)->get_ToggleState(&value);
    if (SUCCEEDED(status)) *result = static_cast<int32_t>(value);
    return status;
}

int32_t SWU_UIAToggleProviderToggleResult(void *toggleProvider) {
    if (toggleProvider == nullptr) return E_POINTER;
    return static_cast<IToggleProvider *>(toggleProvider)->Toggle();
}

int32_t SWU_UIASelectionItemProviderIsSelectedResult(void *selectionItemProvider, int32_t *result) {
    if (result == nullptr) return E_POINTER;
    *result = 0;
    if (selectionItemProvider == nullptr) return E_POINTER;
    BOOL value = FALSE;
    HRESULT status = static_cast<ISelectionItemProvider *>(selectionItemProvider)->get_IsSelected(&value);
    if (SUCCEEDED(status)) *result = value != FALSE ? 1 : 0;
    return status;
}

int32_t SWU_UIASelectionItemProviderSelectResult(void *selectionItemProvider) {
    if (selectionItemProvider == nullptr) return E_POINTER;
    return static_cast<ISelectionItemProvider *>(selectionItemProvider)->Select();
}

int32_t SWU_UIASelectionItemProviderAddToSelectionResult(void *selectionItemProvider) {
    if (selectionItemProvider == nullptr) return E_POINTER;
    return static_cast<ISelectionItemProvider *>(selectionItemProvider)->AddToSelection();
}

int32_t SWU_UIASelectionItemProviderRemoveFromSelectionResult(void *selectionItemProvider) {
    if (selectionItemProvider == nullptr) return E_POINTER;
    return static_cast<ISelectionItemProvider *>(selectionItemProvider)->RemoveFromSelection();
}

int32_t SWU_UIASelectionItemProviderGetSelectionContainerResult(void *selectionItemProvider, void **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (selectionItemProvider == nullptr) return E_POINTER;
    IRawElementProviderSimple *raw = nullptr;
    HRESULT status = static_cast<ISelectionItemProvider *>(selectionItemProvider)->get_SelectionContainer(&raw);
    COMOwned<IRawElementProviderSimple> value(raw);
    if (FAILED(status)) return status;
    *result = value ? static_cast<SWUProvider *>(value.release()) : nullptr;
    return S_OK;
}

int32_t SWU_UIASelectionProviderGetSelectedCountResult(void *selectionProvider, int32_t *result) {
    if (result == nullptr) return E_POINTER;
    *result = 0;
    if (selectionProvider == nullptr) return E_POINTER;
    SAFEARRAY *raw = nullptr;
    HRESULT status = static_cast<ISelectionProvider *>(selectionProvider)->GetSelection(&raw);
    OwnedSafeArray selection(raw);
    if (FAILED(status)) return status;
    LONG lower = 0;
    LONG upper = -1;
    status = arrayBounds(selection.get(), lower, upper);
    if (FAILED(status)) return status;
    *result = upper >= lower ? upper - lower + 1 : 0;
    return S_OK;
}

int32_t SWU_UIASelectionProviderGetSelectedAtResult(void *selectionProvider, int32_t index, void **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (index < 0) return E_INVALIDARG;
    if (selectionProvider == nullptr) return E_POINTER;
    SAFEARRAY *raw = nullptr;
    HRESULT status = static_cast<ISelectionProvider *>(selectionProvider)->GetSelection(&raw);
    OwnedSafeArray selection(raw);
    if (FAILED(status)) return status;
    LONG lower = 0;
    LONG upper = -1;
    status = arrayBounds(selection.get(), lower, upper);
    if (FAILED(status)) return status;
    if (upper < lower || static_cast<int64_t>(index) > static_cast<int64_t>(upper) - lower) return S_OK;
    LONG selectionIndex = lower + index;
    IUnknown *rawUnknown = nullptr;
    status = SafeArrayGetElement(selection.get(), &selectionIndex, &rawUnknown);
    COMOwned<IUnknown> unknown(rawUnknown);
    if (FAILED(status)) return status;
    if (!unknown) return S_OK;
    IRawElementProviderSimple *rawSimple = nullptr;
    status = unknown->QueryInterface(IID_IRawElementProviderSimple, reinterpret_cast<void **>(&rawSimple));
    COMOwned<IRawElementProviderSimple> simple(rawSimple);
    if (FAILED(status)) return status;
    *result = simple ? static_cast<SWUProvider *>(simple.release()) : nullptr;
    return S_OK;
}

int32_t SWU_UIASelectionProviderCanSelectMultipleResult(void *selectionProvider, int32_t *result) {
    if (result == nullptr) return E_POINTER;
    *result = 0;
    if (selectionProvider == nullptr) return E_POINTER;
    BOOL value = FALSE;
    HRESULT status = static_cast<ISelectionProvider *>(selectionProvider)->get_CanSelectMultiple(&value);
    if (SUCCEEDED(status)) *result = value != FALSE ? 1 : 0;
    return status;
}

int32_t SWU_UIASelectionProviderIsSelectionRequiredResult(void *selectionProvider, int32_t *result) {
    if (result == nullptr) return E_POINTER;
    *result = 0;
    if (selectionProvider == nullptr) return E_POINTER;
    BOOL value = FALSE;
    HRESULT status = static_cast<ISelectionProvider *>(selectionProvider)->get_IsSelectionRequired(&value);
    if (SUCCEEDED(status)) *result = value != FALSE ? 1 : 0;
    return status;
}

int32_t SWU_UIAVirtualizedItemProviderRealizeResult(void *virtualizedItemProvider) {
    if (virtualizedItemProvider == nullptr) return E_POINTER;
    return static_cast<IVirtualizedItemProvider *>(virtualizedItemProvider)->Realize();
}

int32_t SWU_UIAProviderSetFocusResult(void *provider) {
    if (provider == nullptr) return E_POINTER;
    return asFragment(provider)->SetFocus();
}

int32_t SWU_UIAProviderGetFocusResult(void *rootProvider, void **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (rootProvider == nullptr) return E_POINTER;
    IRawElementProviderFragment *raw = nullptr;
    HRESULT status = asRoot(rootProvider)->GetFocus(&raw);
    COMOwned<IRawElementProviderFragment> value(raw);
    if (FAILED(status)) return status;
    *result = value ? static_cast<SWUProvider *>(value.release()) : nullptr;
    return S_OK;
}

int32_t SWU_UIAProviderElementFromPointResult(void *rootProvider, double x, double y, void **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (rootProvider == nullptr) return E_POINTER;
    IRawElementProviderFragment *raw = nullptr;
    HRESULT status = asRoot(rootProvider)->ElementProviderFromPoint(x, y, &raw);
    COMOwned<IRawElementProviderFragment> value(raw);
    if (FAILED(status)) return status;
    *result = value ? static_cast<SWUProvider *>(value.release()) : nullptr;
    return S_OK;
}

int32_t SWU_UIAProviderGetFragmentRootResult(void *provider, void **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (provider == nullptr) return E_POINTER;
    IRawElementProviderFragmentRoot *raw = nullptr;
    HRESULT status = asFragment(provider)->get_FragmentRoot(&raw);
    COMOwned<IRawElementProviderFragmentRoot> value(raw);
    if (FAILED(status)) return status;
    *result = value ? static_cast<SWUProvider *>(value.release()) : nullptr;
    return S_OK;
}

// Legacy helpers preserve their signatures and fallback values, but every
// operation now travels through the same guarded COM methods as the peers.

void *SWU_UIAProviderNavigate(void *provider, int32_t direction) {
    void *result = nullptr;
    SWU_UIAProviderNavigateResult(provider, direction, &result);
    return result;
}

int32_t SWU_UIAProviderGetRuntimeId(void *provider, int32_t *buffer, int32_t capacity) {
    if (buffer == nullptr || capacity <= 0) return 0;
    int32_t count = 0;
    SWU_UIAProviderGetRuntimeIdResult(provider, buffer, capacity, &count);
    return count;
}

void SWU_UIAProviderGetBoundingRectangle(
    void *provider, double *left, double *top, double *width, double *height) {
    if (provider == nullptr) return;
    double localLeft = 0, localTop = 0, localWidth = 0, localHeight = 0;
    SWU_UIAProviderGetBoundingRectangleResult(provider, &localLeft, &localTop, &localWidth, &localHeight);
    if (left != nullptr) *left = localLeft;
    if (top != nullptr) *top = localTop;
    if (width != nullptr) *width = localWidth;
    if (height != nullptr) *height = localHeight;
}

uint16_t *SWU_UIAProviderGetName(void *provider) {
    uint16_t *result = nullptr;
    SWU_UIAProviderGetNameResult(provider, &result);
    return result;
}

int32_t SWU_UIAProviderGetControlType(void *provider) {
    int32_t result = 0;
    SWU_UIAProviderGetControlTypeResult(provider, &result);
    return result;
}

int32_t SWU_UIAProviderGetBoolProperty(void *provider, int32_t neutralKey, int32_t *hasValue) {
    int32_t result = 0;
    int32_t supplied = 0;
    SWU_UIAProviderGetBoolPropertyResult(provider, neutralKey, &result, &supplied);
    if (hasValue != nullptr) *hasValue = supplied;
    return result;
}

void *SWU_UIAProviderGetInvokePattern(void *provider) {
    void *result = nullptr;
    SWU_UIAProviderGetPatternResult(provider, SWU_UIA_PATTERN_INVOKE, &result);
    return result;
}

void SWU_UIAProviderInvoke(void *invokeProvider) {
    SWU_UIAProviderInvokeResult(invokeProvider);
}

void *SWU_UIAProviderGetValuePattern(void *provider) {
    void *result = nullptr;
    SWU_UIAProviderGetPatternResult(provider, SWU_UIA_PATTERN_VALUE, &result);
    return result;
}

uint16_t *SWU_UIAValueProviderGetValue(void *valueProvider) {
    uint16_t *result = nullptr;
    SWU_UIAValueProviderGetValueResult(valueProvider, &result);
    return result;
}

int32_t SWU_UIAValueProviderSetValue(void *valueProvider, const uint16_t *value, int32_t length) {
    return SUCCEEDED(SWU_UIAValueProviderSetValueResult(valueProvider, value, length)) ? 1 : 0;
}

int32_t SWU_UIAValueProviderIsReadOnly(void *valueProvider) {
    int32_t result = 0;
    return SUCCEEDED(SWU_UIAValueProviderIsReadOnlyResult(valueProvider, &result)) ? result : 1;
}

void *SWU_UIAProviderGetTogglePattern(void *provider) {
    void *result = nullptr;
    SWU_UIAProviderGetPatternResult(provider, SWU_UIA_PATTERN_TOGGLE, &result);
    return result;
}

int32_t SWU_UIAToggleProviderGetState(void *toggleProvider) {
    int32_t result = 0;
    return SUCCEEDED(SWU_UIAToggleProviderGetStateResult(toggleProvider, &result)) ? result : -1;
}

int32_t SWU_UIAToggleProviderToggle(void *toggleProvider) {
    return SUCCEEDED(SWU_UIAToggleProviderToggleResult(toggleProvider)) ? 1 : 0;
}

void *SWU_UIAProviderGetSelectionItemPattern(void *provider) {
    void *result = nullptr;
    SWU_UIAProviderGetPatternResult(provider, SWU_UIA_PATTERN_SELECTION_ITEM, &result);
    return result;
}

int32_t SWU_UIASelectionItemProviderIsSelected(void *selectionItemProvider) {
    int32_t result = 0;
    return SUCCEEDED(SWU_UIASelectionItemProviderIsSelectedResult(selectionItemProvider, &result)) ? result : -1;
}

int32_t SWU_UIASelectionItemProviderSelect(void *selectionItemProvider) {
    return SUCCEEDED(SWU_UIASelectionItemProviderSelectResult(selectionItemProvider)) ? 1 : 0;
}

int32_t SWU_UIASelectionItemProviderAddToSelection(void *selectionItemProvider) {
    return SUCCEEDED(SWU_UIASelectionItemProviderAddToSelectionResult(selectionItemProvider)) ? 1 : 0;
}

int32_t SWU_UIASelectionItemProviderRemoveFromSelection(void *selectionItemProvider) {
    return SUCCEEDED(SWU_UIASelectionItemProviderRemoveFromSelectionResult(selectionItemProvider)) ? 1 : 0;
}

void *SWU_UIASelectionItemProviderGetSelectionContainer(void *selectionItemProvider) {
    void *result = nullptr;
    SWU_UIASelectionItemProviderGetSelectionContainerResult(selectionItemProvider, &result);
    return result;
}

void *SWU_UIAProviderGetSelectionPattern(void *provider) {
    void *result = nullptr;
    SWU_UIAProviderGetPatternResult(provider, SWU_UIA_PATTERN_SELECTION, &result);
    return result;
}

int32_t SWU_UIASelectionProviderGetSelectedCount(void *selectionProvider) {
    int32_t result = 0;
    SWU_UIASelectionProviderGetSelectedCountResult(selectionProvider, &result);
    return result;
}

void *SWU_UIASelectionProviderGetSelectedAt(void *selectionProvider, int32_t index) {
    void *result = nullptr;
    SWU_UIASelectionProviderGetSelectedAtResult(selectionProvider, index, &result);
    return result;
}

void *SWU_UIAProviderGetVirtualizedItemPattern(void *provider) {
    void *result = nullptr;
    SWU_UIAProviderGetPatternResult(provider, SWU_UIA_PATTERN_VIRTUALIZED_ITEM, &result);
    return result;
}

int32_t SWU_UIAVirtualizedItemProviderRealize(void *virtualizedItemProvider) {
    return SUCCEEDED(SWU_UIAVirtualizedItemProviderRealizeResult(virtualizedItemProvider)) ? 1 : 0;
}

void SWU_UIAProviderSetFocus(void *provider) {
    SWU_UIAProviderSetFocusResult(provider);
}

void *SWU_UIAProviderGetFocus(void *rootProvider) {
    void *result = nullptr;
    SWU_UIAProviderGetFocusResult(rootProvider, &result);
    return result;
}

void *SWU_UIAProviderElementFromPoint(void *rootProvider, double x, double y) {
    void *result = nullptr;
    SWU_UIAProviderElementFromPointResult(rootProvider, x, y, &result);
    return result;
}

void *SWU_UIAProviderGetFragmentRoot(void *provider) {
    void *result = nullptr;
    SWU_UIAProviderGetFragmentRootResult(provider, &result);
    return result;
}

}  // extern "C"
