#include "CUIAInterop.h"

#include <atomic>
#include <cassert>
#include <limits>
#include <memory>
#include <mutex>
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
static_assert(SWU_UIA_PATTERN_ITEM_CONTAINER == UIA_ItemContainerPatternId, "pattern constant drift");
static_assert(SWU_UIA_PATTERN_VIRTUALIZED_ITEM == UIA_VirtualizedItemPatternId, "pattern constant drift");
static_assert(SWU_UIA_ITEM_PROPERTY_NAME == UIA_NamePropertyId, "property constant drift");
static_assert(SWU_UIA_ITEM_PROPERTY_AUTOMATION_ID == UIA_AutomationIdPropertyId, "property constant drift");
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

namespace {
SWUUIACallbacks makeCallAdapters(const SWUUIACallCallbacks &callbacks);
}

// Admission and the one drain notification share a short lock. No callback,
// actor dispatch, COM call, release hook, or wake runs while that lock is held.
struct SWUUIAProviderContext {
    const SWUUIACallbacks callbacks;
    const SWUUIACallCallbacks callCallbacks;
    const bool usesExplicitCalls;
    void (*const releaseContext)(void *);
    const SWUUIADrainWake drainWake;

    SWUUIAProviderContext(const SWUUIACallbacks &value, void (*release)(void *))
        : callbacks(value), callCallbacks{}, usesExplicitCalls(false), releaseContext(release), drainWake{} {}

    SWUUIAProviderContext(
        const SWUUIACallCallbacks &value, void (*release)(void *), const SWUUIADrainWake &wake)
        : callbacks(makeCallAdapters(value)), callCallbacks(value), usesExplicitCalls(true),
          releaseContext(release), drainWake(wake) {}

    void retain() { references.fetch_add(1, std::memory_order_relaxed); }

    void release() {
        if (references.fetch_sub(1, std::memory_order_acq_rel) == 1) {
            delete this;
        }
    }

    void revoke() {
        // A drain callback may release the owner's final reference reentrantly.
        retain();
        bool shouldSignal = false;
        {
            std::lock_guard<std::mutex> guard(admissionMutex);
            available.store(false, std::memory_order_release);
            shouldSignal = claimDrainNotification();
        }
        if (shouldSignal) signalDrain();
        release();
    }

    bool isAvailable() const { return available.load(std::memory_order_acquire); }

    HRESULT admitCall() {
        std::lock_guard<std::mutex> guard(admissionMutex);
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (activeCalls == (std::numeric_limits<uint64_t>::max)()) return E_OUTOFMEMORY;
        ++activeCalls;
        return S_OK;
    }

    void releaseCall() {
        bool shouldSignal = false;
        {
            std::lock_guard<std::mutex> guard(admissionMutex);
            assert(activeCalls > 0);
            --activeCalls;
            shouldSignal = claimDrainNotification();
        }
        if (shouldSignal) signalDrain();
    }

    bool isQuiescent() {
        std::lock_guard<std::mutex> guard(admissionMutex);
        return !isAvailable() && activeCalls == 0;
    }

    HRESULT drainWakeResult() const { return wakeResult.load(std::memory_order_acquire); }

private:
    // Caller holds admissionMutex; this only publishes primitive owned state.
    bool claimDrainNotification() {
        if (isAvailable() || activeCalls != 0 || hasClaimedDrainNotification) return false;
        hasClaimedDrainNotification = true;
        return true;
    }

    void signalDrain() {
        if (drainWake.signal != nullptr) {
            wakeResult.store(drainWake.signal(drainWake.context), std::memory_order_release);
        }
    }

    ~SWUUIAProviderContext() {
        // The hook owns only the callback box. Its contract permits final
        // release on a COM thread and forbids actor-isolated cleanup here.
        if (releaseContext != nullptr) {
            releaseContext(callbacks.context);
        }
        if (drainWake.releaseContext != nullptr) {
            drainWake.releaseContext(drainWake.context);
        }
    }

    std::atomic<ULONG> references{1};
    std::atomic<bool> available{true};
    std::mutex admissionMutex;
    uint64_t activeCalls = 0;
    bool hasClaimedDrainNotification = false;
    std::atomic<HRESULT> wakeResult{S_OK};
};

// The native method and its actor request each own a reference. Admission is
// released only by this destructor, after both consumers finish. In particular,
// a transport failure cannot leave a queued actor closure with a stack token.
struct SWUUIACall {
    SWUUIAProviderContext *const context;

    explicit SWUUIACall(SWUUIAProviderContext *owner) : context(owner) { context->retain(); }

    void retain() { references.fetch_add(1, std::memory_order_relaxed); }
    void release() {
        if (references.fetch_sub(1, std::memory_order_acq_rel) == 1) delete this;
    }

    HRESULT admit() {
        HRESULT result = context->admitCall();
        wasAdmitted = SUCCEEDED(result);
        return result;
    }

    HRESULT status() const {
        if (!context->isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        return failure.load(std::memory_order_acquire);
    }

    void fail(HRESULT result) {
        if (SUCCEEDED(result)) return;
        HRESULT expected = S_OK;
        failure.compare_exchange_strong(expected, result, std::memory_order_acq_rel);
    }

private:
    ~SWUUIACall() {
        if (wasAdmitted) context->releaseCall();
        context->release();
    }

    std::atomic<ULONG> references{1};
    std::atomic<HRESULT> failure{S_OK};
    bool wasAdmitted = false;
};

// This gate owns only unnamed native events and primitive state. It neither
// owns a provider/context nor invokes a callback. The provider's pending slot
// transfers its reference to one real method before that method calls Swift.
struct SWUUIAPublicationGate {
    static HRESULT create(uint32_t timeoutMilliseconds, SWUUIAPublicationGate **result) {
        *result = nullptr;
        HANDLE entered = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (entered == nullptr) return HRESULT_FROM_WIN32(GetLastError());
        HANDLE opened = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (opened == nullptr) {
            HRESULT failure = HRESULT_FROM_WIN32(GetLastError());
            CloseHandle(entered);
            return failure;
        }
        auto *gate = new (std::nothrow) SWUUIAPublicationGate(timeoutMilliseconds, entered, opened);
        if (gate == nullptr) {
            CloseHandle(opened);
            CloseHandle(entered);
            return E_OUTOFMEMORY;
        }
        *result = gate;
        return S_OK;
    }

    void retain() { references.fetch_add(1, std::memory_order_relaxed); }
    void release() {
        if (references.fetch_sub(1, std::memory_order_acq_rel) == 1) delete this;
    }

    HRESULT arriveAndWait() {
        enteredThread.store(GetCurrentThreadId(), std::memory_order_release);
        if (!SetEvent(enteredEvent)) return HRESULT_FROM_WIN32(GetLastError());
        return wait(openedEvent, holdTimeoutMilliseconds);
    }

    HRESULT waitUntilEntered(uint32_t timeoutMilliseconds) {
        return wait(enteredEvent, timeoutMilliseconds);
    }

    uint32_t enteredThreadID() const { return enteredThread.load(std::memory_order_acquire); }

    HRESULT open() {
        return SetEvent(openedEvent) ? S_OK : HRESULT_FROM_WIN32(GetLastError());
    }

private:
    SWUUIAPublicationGate(uint32_t timeoutMilliseconds, HANDLE entered, HANDLE opened)
        : holdTimeoutMilliseconds(timeoutMilliseconds), enteredEvent(entered), openedEvent(opened) {}

    ~SWUUIAPublicationGate() {
        CloseHandle(openedEvent);
        CloseHandle(enteredEvent);
    }

    static HRESULT wait(HANDLE event, uint32_t timeoutMilliseconds) {
        DWORD result = WaitForSingleObject(event, timeoutMilliseconds);
        if (result == WAIT_OBJECT_0) return S_OK;
        if (result == WAIT_TIMEOUT) return HRESULT_FROM_WIN32(ERROR_TIMEOUT);
        if (result == WAIT_FAILED) return HRESULT_FROM_WIN32(GetLastError());
        return E_UNEXPECTED;
    }

    const uint32_t holdTimeoutMilliseconds;
    const HANDLE enteredEvent;
    const HANDLE openedEvent;
    std::atomic<ULONG> references{1};
    std::atomic<uint32_t> enteredThread{0};
};

namespace {

struct PublicationGateRelease {
    void operator()(SWUUIAPublicationGate *gate) const {
        if (gate != nullptr) gate->release();
    }
};

using OwnedPublicationGate = std::unique_ptr<SWUUIAPublicationGate, PublicationGateRelease>;

bool validPublicationGateTimeout(uint32_t timeoutMilliseconds) {
    return timeoutMilliseconds > 0 && timeoutMilliseconds <= 30000;
}

// Keep one implementation of the existing payload mapping. These adapters
// replace only the callback context argument; status remains out of band.
SWUUIACallbacks makeCallAdapters(const SWUUIACallCallbacks &value) {
    SWUUIACallbacks result{};
    result.context = value.context;
#define SWU_UIA_CALL_ADAPTER(name, resultType, signature, arguments) \
    if (value.name != nullptr) { \
        result.name = [] signature -> resultType { \
            auto *call = static_cast<SWUUIACall *>(raw); \
            return call->context->callCallbacks.name arguments; \
        }; \
    }
    SWU_UIA_CALL_ADAPTER(navigate, uint64_t,
        (void *raw, uint64_t element, int32_t direction), (call, element, direction))
    SWU_UIA_CALL_ADAPTER(getRuntimeId, int32_t,
        (void *raw, uint64_t element, int32_t *buffer, int32_t capacity), (call, element, buffer, capacity))
    SWU_UIA_CALL_ADAPTER(getBoundingRectangle, void,
        (void *raw, uint64_t element, double *left, double *top, double *width, double *height),
        (call, element, left, top, width, height))
    SWU_UIA_CALL_ADAPTER(copyStringProperty, uint16_t *,
        (void *raw, uint64_t element, int32_t property), (call, element, property))
    SWU_UIA_CALL_ADAPTER(getControlType, int32_t, (void *raw, uint64_t element), (call, element))
    SWU_UIA_CALL_ADAPTER(getBoolProperty, int32_t,
        (void *raw, uint64_t element, int32_t property), (call, element, property))
    SWU_UIA_CALL_ADAPTER(hasInvokeAction, int32_t, (void *raw, uint64_t element), (call, element))
    SWU_UIA_CALL_ADAPTER(invokeDefaultAction, void, (void *raw, uint64_t element), (call, element))
    SWU_UIA_CALL_ADAPTER(supportsPattern, int32_t,
        (void *raw, uint64_t element, int32_t pattern), (call, element, pattern))
    SWU_UIA_CALL_ADAPTER(setValue, int32_t,
        (void *raw, uint64_t element, const uint16_t *text, int32_t length), (call, element, text, length))
    SWU_UIA_CALL_ADAPTER(getToggleState, int32_t, (void *raw, uint64_t element), (call, element))
    SWU_UIA_CALL_ADAPTER(toggle, int32_t, (void *raw, uint64_t element), (call, element))
    SWU_UIA_CALL_ADAPTER(select, int32_t, (void *raw, uint64_t element), (call, element))
    SWU_UIA_CALL_ADAPTER(addToSelection, int32_t, (void *raw, uint64_t element), (call, element))
    SWU_UIA_CALL_ADAPTER(removeFromSelection, int32_t, (void *raw, uint64_t element), (call, element))
    SWU_UIA_CALL_ADAPTER(getSelectionContainer, uint64_t, (void *raw, uint64_t element), (call, element))
    SWU_UIA_CALL_ADAPTER(getSelection, int32_t,
        (void *raw, uint64_t element, uint64_t *buffer, int32_t capacity), (call, element, buffer, capacity))
    SWU_UIA_CALL_ADAPTER(realizeVirtualizedItem, int32_t, (void *raw, uint64_t element), (call, element))
    SWU_UIA_CALL_ADAPTER(setFocus, void, (void *raw, uint64_t element), (call, element))
    SWU_UIA_CALL_ADAPTER(elementFromPoint, uint64_t, (void *raw, double x, double y), (call, x, y))
    SWU_UIA_CALL_ADAPTER(focusedElement, uint64_t, (void *raw), (call))
    SWU_UIA_CALL_ADAPTER(getLogicalItemState, int32_t, (void *raw, uint64_t element), (call, element))
    SWU_UIA_CALL_ADAPTER(findItem, int32_t,
        (void *raw, uint64_t container, uint64_t after, uint64_t *target), (call, container, after, target))
#undef SWU_UIA_CALL_ADAPTER
    return result;
}

class ProviderCall {
public:
    ProviderCall(IUnknown *provider, SWUUIAProviderContext *context) : provider_(provider), context_(context) {
        provider_->AddRef();
        context_->retain();
        if (context_->usesExplicitCalls) {
            call_ = new (std::nothrow) SWUUIACall(context_);
            admission_ = call_ != nullptr ? call_->admit() : E_OUTOFMEMORY;
        } else {
            admission_ = context_->admitCall();
            legacyAdmitted_ = SUCCEEDED(admission_);
        }
    }

    ~ProviderCall() {
        // Balance the provider pin before publishing the full-call drain.
        provider_->Release();
        if (call_ != nullptr) call_->release();
        if (legacyAdmitted_) context_->releaseCall();
        context_->release();
    }

    ProviderCall(const ProviderCall &) = delete;
    ProviderCall &operator=(const ProviderCall &) = delete;

    HRESULT status() const {
        if (FAILED(admission_)) return admission_;
        if (call_ != nullptr) return call_->status();
        return context_->isAvailable() ? S_OK : UIA_E_ELEMENTNOTAVAILABLE;
    }

    void *callbackContext() const {
        return call_ != nullptr ? static_cast<void *>(call_) : context_->callbacks.context;
    }

private:
    IUnknown *const provider_;
    SWUUIAProviderContext *const context_;
    SWUUIACall *call_ = nullptr;
    HRESULT admission_ = UIA_E_ELEMENTNOTAVAILABLE;
    bool legacyAdmitted_ = false;
};

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

// A private native identity interface validates ItemContainer's startAfter
// without interpreting an arbitrary foreign COM object as an SWUProvider.
// It reads only immutable provider identity, never Swift or a view tree.
const IID IID_SWUProviderIdentity = {
    0x2d9b4a43, 0x9d6f, 0x4b16, {0x88, 0x75, 0x67, 0x13, 0xd5, 0x71, 0x5e, 0x9c}};

struct ISWUProviderIdentity : IUnknown {
    virtual HRESULT STDMETHODCALLTYPE GetElementIdentity(
        SWUUIAProviderContext *context, uint64_t *element) = 0;
};

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
                    public IVirtualizedItemProvider,
                    public IItemContainerProvider,
                    public ISWUProviderIdentity {
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
        } else if (riid == IID_IItemContainerProvider) {
            *ppv = static_cast<IItemContainerProvider *>(this);
        } else if (riid == IID_SWUProviderIdentity) {
            *ppv = static_cast<ISWUProviderIdentity *>(this);
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
    SWUUIAProviderContext *providerContext() const { return context_; }

    HRESULT armControlTypePublicationGate(SWUUIAPublicationGate *gate) {
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (!context_->usesExplicitCalls) return E_INVALIDARG;
        bool expected = false;
        if (!hasArmedPublicationGate_.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) {
            return UIA_E_INVALIDOPERATION;
        }
        gate->retain();
        controlTypePublicationGate_.store(gate, std::memory_order_release);
        return S_OK;
    }

    IFACEMETHODIMP GetElementIdentity(SWUUIAProviderContext *context, uint64_t *element) override {
        if (element == nullptr) return E_POINTER;
        *element = SWU_UIA_NO_ELEMENT;
        if (!isAvailable()) return UIA_E_ELEMENTNOTAVAILABLE;
        if (context != context_) return E_INVALIDARG;
        *element = element_;
        return S_OK;
    }

    // IRawElementProviderSimple

    IFACEMETHODIMP get_ProviderOptions(ProviderOptions *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = static_cast<ProviderOptions>(0);
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        if (FAILED(call.status())) return call.status();
        *pRetVal = static_cast<ProviderOptions>(
            ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading);
        return S_OK;
    }

    IFACEMETHODIMP GetPatternProvider(PATTERNID patternId, IUnknown **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        if (FAILED(call.status())) return call.status();

        int32_t logicalState = SWU_UIA_LOGICAL_ITEM_ORDINARY;
        HRESULT logicalResult = logicalItemState(call, logicalState);
        if (FAILED(logicalResult)) return logicalResult;
        if (logicalState == SWU_UIA_LOGICAL_ITEM_PLACEHOLDER) {
            if (patternId == UIA_VirtualizedItemPatternId) {
                auto *pattern = static_cast<IVirtualizedItemProvider *>(this);
                pattern->AddRef();
                COMOwned<IVirtualizedItemProvider> owned(pattern);
                if (FAILED(call.status())) return call.status();
                *pRetVal = owned.release();
            } else if (FAILED(call.status())) {
                return call.status();
            }
            return S_OK;
        }

        bool supported = false;
        IUnknown *pattern = nullptr;
        HRESULT result = S_OK;
        switch (patternId) {
        case UIA_InvokePatternId:
            result = supportsInvoke(call, supported);
            pattern = static_cast<IInvokeProvider *>(this);
            break;
        case UIA_ValuePatternId:
            result = supportsPattern(call, SWU_UIA_PATTERN_VALUE, supported);
            pattern = static_cast<IValueProvider *>(this);
            break;
        case UIA_TogglePatternId:
            result = supportsPattern(call, SWU_UIA_PATTERN_TOGGLE, supported);
            pattern = static_cast<IToggleProvider *>(this);
            break;
        case UIA_SelectionPatternId:
            result = supportsPattern(call, SWU_UIA_PATTERN_SELECTION, supported);
            pattern = static_cast<ISelectionProvider *>(this);
            break;
        case UIA_SelectionItemPatternId:
            result = supportsPattern(call, SWU_UIA_PATTERN_SELECTION_ITEM, supported);
            pattern = static_cast<ISelectionItemProvider *>(this);
            break;
        case UIA_VirtualizedItemPatternId:
            result = supportsPattern(call, SWU_UIA_PATTERN_VIRTUALIZED_ITEM, supported);
            pattern = static_cast<IVirtualizedItemProvider *>(this);
            break;
        case UIA_ItemContainerPatternId:
            result = supportsPattern(call, SWU_UIA_PATTERN_ITEM_CONTAINER, supported);
            pattern = static_cast<IItemContainerProvider *>(this);
            break;
        default:
            break;
        }
        if (FAILED(result)) return result;
        result = logicalAvailability(call);
        if (FAILED(result)) return result;
        if (supported) {
            pattern->AddRef();
            COMOwned<IUnknown> owned(pattern);
            if (FAILED(call.status())) return call.status();
            *pRetVal = owned.release();
        }
        return S_OK;
    }

    IFACEMETHODIMP GetPropertyValue(PROPERTYID propertyId, VARIANT *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        VariantInit(pRetVal);
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        if (FAILED(call.status())) return call.status();
        // Take the one pending reference before any callback, so synchronous
        // actor reentry cannot consume the outer method's publication gate.
        OwnedPublicationGate publicationGate(propertyId == UIA_ControlTypePropertyId
            ? controlTypePublicationGate_.exchange(nullptr, std::memory_order_acq_rel) : nullptr);

        int32_t logicalState = SWU_UIA_LOGICAL_ITEM_ORDINARY;
        HRESULT logicalResult = logicalItemState(call, logicalState);
        if (FAILED(logicalResult)) return logicalResult;
        if (logicalState == SWU_UIA_LOGICAL_ITEM_PLACEHOLDER) {
            if (FAILED(call.status())) return call.status();
            if (propertyId != UIA_IsOffscreenPropertyId) return UIA_E_ELEMENTNOTAVAILABLE;
            pRetVal->vt = VT_BOOL;
            pRetVal->boolVal = VARIANT_TRUE;
            return S_OK;
        }

        VARIANT value;
        VariantInit(&value);
        HRESULT result = S_OK;
        switch (propertyId) {
        case UIA_NamePropertyId:
            result = setStringProperty(call, &value, SWU_UIA_STRING_NAME);
            break;
        case UIA_ValueValuePropertyId: {
            int32_t password = -1;
            result = boolProperty(call, SWU_UIA_BOOL_IS_PASSWORD, password);
            if (SUCCEEDED(result) && password != 1) {
                result = setStringProperty(call, &value, SWU_UIA_STRING_VALUE);
            }
            break;
        }
        case UIA_HelpTextPropertyId:
            result = setStringProperty(call, &value, SWU_UIA_STRING_HELP_TEXT);
            break;
        case UIA_AutomationIdPropertyId:
            result = setStringProperty(call, &value, SWU_UIA_STRING_AUTOMATION_ID);
            break;
        case UIA_ClassNamePropertyId:
            result = setStringProperty(call, &value, SWU_UIA_STRING_CLASS_NAME);
            break;
        case UIA_ControlTypePropertyId: {
            int32_t controlType = 0;
            result = readCallback(call, callbacks().getControlType, controlType, element_);
            if (SUCCEEDED(result)) {
                value.vt = VT_I4;
                value.lVal = controlType;
            }
            break;
        }
        case UIA_IsEnabledPropertyId:
            result = setBoolProperty(call, &value, SWU_UIA_BOOL_IS_ENABLED);
            break;
        case UIA_HasKeyboardFocusPropertyId:
            result = setBoolProperty(call, &value, SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS);
            break;
        case UIA_IsKeyboardFocusablePropertyId:
            result = setBoolProperty(call, &value, SWU_UIA_BOOL_IS_KEYBOARD_FOCUSABLE);
            break;
        case UIA_IsOffscreenPropertyId:
            result = setBoolProperty(call, &value, SWU_UIA_BOOL_IS_OFFSCREEN);
            break;
        case UIA_IsPasswordPropertyId:
            result = setBoolProperty(call, &value, SWU_UIA_BOOL_IS_PASSWORD);
            break;
        case UIA_ValueIsReadOnlyPropertyId:
            result = setBoolProperty(call, &value, SWU_UIA_BOOL_IS_READ_ONLY);
            break;
        case UIA_SelectionItemIsSelectedPropertyId:
            result = setBoolProperty(call, &value, SWU_UIA_BOOL_IS_SELECTED);
            break;
        case UIA_ToggleToggleStatePropertyId: {
            int32_t state = -1;
            if (callbacks().getToggleState != nullptr) {
                result = readCallback(call, callbacks().getToggleState, state, element_);
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
        HRESULT availability = logicalAvailability(call);
        if (FAILED(availability)) result = availability;
        if (SUCCEEDED(result) && publicationGate) {
            // No admission/gate lock crosses Swift or this wait. The existing
            // ProviderCall still pins the provider and owns full-call admission.
            HRESULT gateResult = publicationGate->arriveAndWait();
            HRESULT status = call.status();
            if (FAILED(status)) result = status;
            else if (FAILED(gateResult)) result = gateResult;
        }
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
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        if (FAILED(call.status())) return call.status();
        if (!isRoot_ || hwnd_ == nullptr) return S_OK;

        IRawElementProviderSimple *raw = nullptr;
        HRESULT result = UiaHostProviderFromHwnd(hwnd_, &raw);
        COMOwned<IRawElementProviderSimple> host(raw);
        if (FAILED(call.status())) return call.status();
        if (FAILED(result)) return result;
        *pRetVal = host.release();
        return S_OK;
    }

    // IRawElementProviderFragment

    IFACEMETHODIMP Navigate(NavigateDirection direction, IRawElementProviderFragment **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        if (!isNavigationDirection(static_cast<int32_t>(direction))) return E_INVALIDARG;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        HRESULT availability = logicalAvailability(call);
        if (FAILED(availability)) return availability;
        uint64_t target = SWU_UIA_NO_ELEMENT;
        HRESULT result = readCallback(call, callbacks().navigate, target, element_, static_cast<int32_t>(direction));
        if (FAILED(result)) return result;
        result = logicalAvailability(call);
        if (FAILED(result)) return result;
        return makeRelatedProvider(call, target, pRetVal);
    }

    IFACEMETHODIMP GetRuntimeId(SAFEARRAY **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        HRESULT availability = logicalAvailability(call, true);
        if (FAILED(availability)) return availability;
        int32_t buffer[8] = {};
        int32_t count = 0;
        HRESULT result = readCallback(call, callbacks().getRuntimeId, count, element_, buffer, 8);
        if (FAILED(result)) return result;
        if (count <= 0) return S_OK;
        if (count > 8) return UIA_E_INVALIDOPERATION;
        OwnedSafeArray values(SafeArrayCreateVector(VT_I4, 0, static_cast<ULONG>(count)));
        availability = logicalAvailability(call, true);
        if (FAILED(availability)) return availability;
        if (!values) return E_OUTOFMEMORY;
        for (LONG index = 0; index < count; ++index) {
            result = SafeArrayPutElement(values.get(), &index, &buffer[index]);
            if (FAILED(call.status())) return call.status();
            if (FAILED(result)) return result;
        }
        availability = logicalAvailability(call, true);
        if (FAILED(availability)) return availability;
        *pRetVal = values.release();
        return S_OK;
    }

    IFACEMETHODIMP get_BoundingRectangle(UiaRect *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = UiaRect{0, 0, 0, 0};
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        HRESULT availability = logicalAvailability(call);
        if (FAILED(availability)) return availability;
        UiaRect value{0, 0, 0, 0};
        HRESULT result = invokeCallback(call,
            callbacks().getBoundingRectangle, element_, &value.left, &value.top, &value.width, &value.height);
        if (FAILED(result)) return result;
        result = logicalAvailability(call);
        if (FAILED(result)) return result;
        *pRetVal = value;
        return S_OK;
    }

    IFACEMETHODIMP GetEmbeddedFragmentRoots(SAFEARRAY **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        return call.status();
    }

    IFACEMETHODIMP SetFocus() override {
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        HRESULT result = logicalAvailability(call);
        if (FAILED(result)) return result;
        result = invokeCallback(call, callbacks().setFocus, element_);
        return FAILED(result) ? result : logicalAvailability(call);
    }

    IFACEMETHODIMP get_FragmentRoot(IRawElementProviderFragmentRoot **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        return makeRelatedProvider(call, SWU_UIA_ROOT_ELEMENT, pRetVal);
    }

    // IRawElementProviderFragmentRoot

    IFACEMETHODIMP ElementProviderFromPoint(double x, double y, IRawElementProviderFragment **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        uint64_t target = SWU_UIA_NO_ELEMENT;
        HRESULT result = readCallback(call, callbacks().elementFromPoint, target, x, y);
        if (FAILED(result)) return result;
        return makeRelatedProvider(call, target, pRetVal);
    }

    IFACEMETHODIMP GetFocus(IRawElementProviderFragment **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        uint64_t target = SWU_UIA_NO_ELEMENT;
        HRESULT result = readCallback(call, callbacks().focusedElement, target);
        if (FAILED(result)) return result;
        return makeRelatedProvider(call, target, pRetVal);
    }

    // IInvokeProvider

    IFACEMETHODIMP Invoke() override {
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        bool enabled = false;
        HRESULT result = isEnabled(call, enabled);
        if (FAILED(result)) return result;
        if (!enabled) return UIA_E_ELEMENTNOTENABLED;
        result = invokeCallback(call, callbacks().invokeDefaultAction, element_);
        return FAILED(result) ? result : logicalAvailability(call);
    }

    // IValueProvider

    IFACEMETHODIMP SetValue(LPCWSTR value) override {
        if (value == nullptr) return E_INVALIDARG;
        size_t length = wcslen(value);
        if (length > static_cast<size_t>((std::numeric_limits<int32_t>::max)())) return E_INVALIDARG;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        bool enabled = false;
        HRESULT result = isEnabled(call, enabled);
        if (FAILED(result)) return result;
        if (!enabled) return UIA_E_ELEMENTNOTENABLED;
        bool readOnly = true;
        result = isReadOnly(call, readOnly);
        if (FAILED(result)) return result;
        if (readOnly) return UIA_E_INVALIDOPERATION;
        int32_t changed = 0;
        result = readCallback(call,
            callbacks().setValue, changed, element_, reinterpret_cast<const uint16_t *>(value),
            static_cast<int32_t>(length));
        if (FAILED(result)) return result;
        return changed != 0 ? S_OK : UIA_E_INVALIDOPERATION;
    }

    IFACEMETHODIMP get_Value(BSTR *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        HRESULT availability = logicalAvailability(call);
        if (FAILED(availability)) return availability;
        uint16_t *raw = nullptr;
        HRESULT result = S_OK;
        if (callbacks().copyStringProperty != nullptr) {
            result = readCallback(call, callbacks().copyStringProperty, raw, element_, SWU_UIA_STRING_VALUE);
        }
        OwnedBSTR value(reinterpret_cast<BSTR>(raw));
        if (FAILED(result)) return result;
        availability = logicalAvailability(call);
        if (FAILED(availability)) return availability;
        if (!value) value.reset(SysAllocStringLen(nullptr, 0));
        availability = logicalAvailability(call);
        if (FAILED(availability)) return availability;
        if (!value) return E_OUTOFMEMORY;
        *pRetVal = value.release();
        return S_OK;
    }

    IFACEMETHODIMP get_IsReadOnly(BOOL *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = FALSE;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        bool value = true;
        HRESULT result = isReadOnly(call, value);
        if (FAILED(result)) return result;
        *pRetVal = value ? TRUE : FALSE;
        return S_OK;
    }

    // IToggleProvider

    IFACEMETHODIMP Toggle() override {
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        return performAction(call, callbacks().toggle);
    }

    IFACEMETHODIMP get_ToggleState(ToggleState *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = ToggleState_Off;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        HRESULT availability = logicalAvailability(call);
        if (FAILED(availability)) return availability;
        int32_t value = -1;
        HRESULT result = readCallback(call, callbacks().getToggleState, value, element_);
        if (FAILED(result)) return result;
        if (value < SWU_UIA_TOGGLE_OFF || value > SWU_UIA_TOGGLE_INDETERMINATE) return UIA_E_INVALIDOPERATION;
        *pRetVal = static_cast<ToggleState>(value);
        return S_OK;
    }

    // ISelectionProvider

    IFACEMETHODIMP GetSelection(SAFEARRAY **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        HRESULT availability = logicalAvailability(call);
        if (FAILED(availability)) return availability;
        int32_t count = 0;
        HRESULT result = readCallback(call, callbacks().getSelection, count, element_, nullptr, 0);
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
            result = readCallback(call, callbacks().getSelection, actual, element_, ids.data(), count);
            if (FAILED(result)) return result;
            if (actual < 0 || actual > count) return UIA_E_INVALIDOPERATION;
            count = actual;
        }
        if (FAILED(call.status())) return call.status();
        OwnedSafeArray selection(SafeArrayCreateVector(VT_UNKNOWN, 0, static_cast<ULONG>(count)));
        if (FAILED(call.status())) return call.status();
        if (!selection) return E_OUTOFMEMORY;
        for (LONG index = 0; index < count; ++index) {
            IRawElementProviderSimple *raw = nullptr;
            result = makeRelatedProvider(call, ids[static_cast<size_t>(index)], &raw);
            COMOwned<IRawElementProviderSimple> provider(raw);
            if (FAILED(result)) return result;
            if (!provider) return UIA_E_INVALIDOPERATION;
            IUnknown *unknown = provider.get();
            result = SafeArrayPutElement(selection.get(), &index, unknown);
            if (FAILED(result)) return result;
        }
        if (FAILED(call.status())) return call.status();
        *pRetVal = selection.release();
        return S_OK;
    }

    IFACEMETHODIMP get_CanSelectMultiple(BOOL *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = FALSE;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        return call.status();
    }

    IFACEMETHODIMP get_IsSelectionRequired(BOOL *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = FALSE;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        return call.status();
    }

    // ISelectionItemProvider

    IFACEMETHODIMP Select() override {
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        return performAction(call, callbacks().select);
    }

    IFACEMETHODIMP AddToSelection() override {
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        return performAction(call, callbacks().addToSelection);
    }

    IFACEMETHODIMP RemoveFromSelection() override {
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        return performAction(call, callbacks().removeFromSelection);
    }

    IFACEMETHODIMP get_IsSelected(BOOL *pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = FALSE;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        int32_t value = -1;
        HRESULT result = boolProperty(call, SWU_UIA_BOOL_IS_SELECTED, value);
        if (FAILED(result)) return result;
        if (value < 0) return UIA_E_INVALIDOPERATION;
        *pRetVal = value != 0 ? TRUE : FALSE;
        return S_OK;
    }

    IFACEMETHODIMP get_SelectionContainer(IRawElementProviderSimple **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        HRESULT availability = logicalAvailability(call);
        if (FAILED(availability)) return availability;
        if (callbacks().getSelectionContainer == nullptr) return S_OK;
        uint64_t target = SWU_UIA_NO_ELEMENT;
        HRESULT result = readCallback(call, callbacks().getSelectionContainer, target, element_);
        if (FAILED(result)) return result;
        return makeRelatedProvider(call, target, pRetVal);
    }

    // IVirtualizedItemProvider

    IFACEMETHODIMP Realize() override {
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        int32_t state = SWU_UIA_LOGICAL_ITEM_ORDINARY;
        HRESULT result = logicalItemState(call, state);
        if (FAILED(result)) return result;
        if (state == SWU_UIA_LOGICAL_ITEM_PLACEHOLDER) {
            // Enabled state is unknown until construction. The retained
            // realization admission checks the actual container and target.
            int32_t performed = 0;
            result = readCallback(call, callbacks().realizeVirtualizedItem, performed, element_);
            if (FAILED(result)) return result;
            result = logicalAvailability(call, true);
            if (FAILED(result)) return result;
            return performed != 0 ? S_OK : UIA_E_INVALIDOPERATION;
        }
        return performAction(call, callbacks().realizeVirtualizedItem);
    }

    // IItemContainerProvider

    IFACEMETHODIMP FindItemByProperty(
        IRawElementProviderSimple *startAfter, PROPERTYID propertyId, VARIANT value,
        IRawElementProviderSimple **pRetVal) override {
        if (pRetVal == nullptr) return E_POINTER;
        *pRetVal = nullptr;
        ProviderCall call(static_cast<IRawElementProviderSimple *>(this), context_);
        HRESULT result = logicalAvailability(call);
        if (FAILED(result)) return result;
        // No row factory or authored identifier lookup can be hidden behind a
        // search that this provider cannot answer from logical native metadata.
        if (propertyId != SWU_UIA_ITEM_PROPERTY_ANY) return E_NOTIMPL;
        (void)value;
        if (callbacks().findItem == nullptr) return E_NOTIMPL;
        bool supported = false;
        result = supportsPattern(call, SWU_UIA_PATTERN_ITEM_CONTAINER, supported);
        if (FAILED(result)) return result;
        if (!supported) return UIA_E_INVALIDOPERATION;

        uint64_t after = SWU_UIA_NO_ELEMENT;
        if (startAfter != nullptr) {
            HRESULT identityResult = E_INVALIDARG;
            {
                ISWUProviderIdentity *raw = nullptr;
                result = startAfter->QueryInterface(IID_SWUProviderIdentity, reinterpret_cast<void **>(&raw));
                COMOwned<ISWUProviderIdentity> identity(raw);
                if (SUCCEEDED(call.status()) && SUCCEEDED(result) && identity) {
                    identityResult = identity->GetElementIdentity(context_, &after);
                }
                // A foreign identity's Release may reenter or revoke the
                // owner too. Keep the enclosing call through that release.
            }
            if (FAILED(call.status())) return call.status();
            if (FAILED(identityResult)) return identityResult;
        }
        uint64_t target = SWU_UIA_NO_ELEMENT;
        int32_t found = SWU_UIA_ITEM_LOOKUP_UNAVAILABLE;
        result = readCallback(call, callbacks().findItem, found, element_, after, &target);
        if (FAILED(result)) return result;
        if (found == SWU_UIA_ITEM_LOOKUP_UNAVAILABLE) return UIA_E_ELEMENTNOTAVAILABLE;
        if (found == SWU_UIA_ITEM_LOOKUP_INVALID_START) return E_INVALIDARG;
        if (found == SWU_UIA_ITEM_LOOKUP_END) return S_OK;
        if (found != SWU_UIA_ITEM_LOOKUP_FOUND || target == SWU_UIA_NO_ELEMENT) return UIA_E_INVALIDOPERATION;
        int32_t targetState = SWU_UIA_LOGICAL_ITEM_UNAVAILABLE;
        result = logicalItemState(call, target, targetState);
        if (FAILED(result)) return result;
        return makeRelatedProvider(call, target, pRetVal);
    }

private:
    ~SWUProvider() {
        auto *pendingGate = controlTypePublicationGate_.exchange(nullptr, std::memory_order_acq_rel);
        if (pendingGate != nullptr) pendingGate->release();
        context_->release();
    }

    const SWUUIACallbacks &callbacks() const { return context_->callbacks; }

    HRESULT logicalItemState(ProviderCall &call, uint64_t element, int32_t &state) {
        state = SWU_UIA_LOGICAL_ITEM_ORDINARY;
        if (FAILED(call.status())) return call.status();
        if (callbacks().getLogicalItemState == nullptr) return S_OK;
        HRESULT result = readCallback(call, callbacks().getLogicalItemState, state, element);
        if (FAILED(result)) return result;
        return state == SWU_UIA_LOGICAL_ITEM_ORDINARY || state == SWU_UIA_LOGICAL_ITEM_PLACEHOLDER
            ? S_OK : UIA_E_ELEMENTNOTAVAILABLE;
    }

    HRESULT logicalItemState(ProviderCall &call, int32_t &state) {
        return logicalItemState(call, element_, state);
    }

    HRESULT logicalAvailability(ProviderCall &call, bool permitPlaceholder = false) {
        int32_t state = SWU_UIA_LOGICAL_ITEM_ORDINARY;
        HRESULT result = logicalItemState(call, state);
        if (FAILED(result)) return result;
        return state == SWU_UIA_LOGICAL_ITEM_PLACEHOLDER && !permitPlaceholder
            ? UIA_E_ELEMENTNOTAVAILABLE : S_OK;
    }

    // The full method owns admission through output marshalling. A callback
    // may drop every external owner or retain its token for queued actor work.
    template <typename Callback, typename Value, typename... Arguments>
    HRESULT readCallback(ProviderCall &call, Callback callback, Value &result, Arguments... arguments) {
        if (FAILED(call.status())) return call.status();
        if (callback == nullptr) return UIA_E_INVALIDOPERATION;
        result = callback(call.callbackContext(), arguments...);
        return call.status();
    }

    template <typename Callback, typename... Arguments>
    HRESULT invokeCallback(ProviderCall &call, Callback callback, Arguments... arguments) {
        if (FAILED(call.status())) return call.status();
        if (callback == nullptr) return UIA_E_INVALIDOPERATION;
        callback(call.callbackContext(), arguments...);
        return call.status();
    }

    template <typename Interface>
    HRESULT makeRelatedProvider(ProviderCall &call, uint64_t element, Interface **result) {
        if (FAILED(call.status())) return call.status();
        if (element == SWU_UIA_NO_ELEMENT) return S_OK;
        COMOwned<SWUProvider> provider(new (std::nothrow) SWUProvider(
            context_, hwnd_, element, element == SWU_UIA_ROOT_ELEMENT));
        if (FAILED(call.status())) return call.status();
        if (!provider) return E_OUTOFMEMORY;
        *result = static_cast<Interface *>(provider.release());
        return S_OK;
    }

    HRESULT supportsInvoke(ProviderCall &call, bool &result) {
        result = false;
        if (FAILED(call.status())) return call.status();
        if (callbacks().hasInvokeAction == nullptr) return S_OK;
        int32_t supported = 0;
        HRESULT status = readCallback(call, callbacks().hasInvokeAction, supported, element_);
        if (SUCCEEDED(status)) result = supported != 0;
        return status;
    }

    HRESULT supportsPattern(ProviderCall &call, int32_t pattern, bool &result) {
        result = false;
        if (FAILED(call.status())) return call.status();
        if (callbacks().supportsPattern == nullptr) return S_OK;
        int32_t supported = 0;
        HRESULT status = readCallback(call, callbacks().supportsPattern, supported, element_, pattern);
        if (SUCCEEDED(status)) result = supported != 0;
        return status;
    }

    HRESULT boolProperty(ProviderCall &call, int32_t property, int32_t &result) {
        result = -1;
        HRESULT availability = logicalAvailability(call);
        if (FAILED(availability)) return availability;
        if (callbacks().getBoolProperty == nullptr) return S_OK;
        return readCallback(call, callbacks().getBoolProperty, result, element_, property);
    }

    HRESULT isEnabled(ProviderCall &call, bool &result) {
        int32_t value = -1;
        HRESULT status = boolProperty(call, SWU_UIA_BOOL_IS_ENABLED, value);
        if (SUCCEEDED(status)) result = value != 0;
        return status;
    }

    HRESULT isReadOnly(ProviderCall &call, bool &result) {
        int32_t value = -1;
        HRESULT status = boolProperty(call, SWU_UIA_BOOL_IS_READ_ONLY, value);
        if (SUCCEEDED(status)) result = value != 0;
        return status;
    }

    HRESULT performAction(ProviderCall &call, int32_t (*action)(void *, uint64_t)) {
        bool enabled = false;
        HRESULT result = isEnabled(call, enabled);
        if (FAILED(result)) return result;
        if (!enabled) return UIA_E_ELEMENTNOTENABLED;
        int32_t performed = 0;
        result = readCallback(call, action, performed, element_);
        if (FAILED(result)) return result;
        return performed != 0 ? S_OK : UIA_E_INVALIDOPERATION;
    }

    HRESULT setStringProperty(ProviderCall &call, VARIANT *out, int32_t property) {
        if (FAILED(call.status())) return call.status();
        if (callbacks().copyStringProperty == nullptr) return S_OK;
        uint16_t *raw = nullptr;
        HRESULT result = readCallback(call, callbacks().copyStringProperty, raw, element_, property);
        OwnedBSTR value(reinterpret_cast<BSTR>(raw));
        if (FAILED(result)) return result;
        if (value) {
            out->vt = VT_BSTR;
            out->bstrVal = value.release();
        }
        return S_OK;
    }

    HRESULT setBoolProperty(ProviderCall &call, VARIANT *out, int32_t property) {
        int32_t value = -1;
        HRESULT result = boolProperty(call, property, value);
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
    std::atomic<bool> hasArmedPublicationGate_{false};
    std::atomic<SWUUIAPublicationGate *> controlTypePublicationGate_{nullptr};
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
    case SWU_UIA_INTERFACE_ITEM_CONTAINER: return IID_IItemContainerProvider;
    default: return IID_NULL;
    }
}

}  // namespace

extern "C" {

void SWU_UIARetainCall(SWUUIACall *call) {
    if (call != nullptr) call->retain();
}

void SWU_UIAReleaseCall(SWUUIACall *call) {
    if (call != nullptr) call->release();
}

void *SWU_UIACallOwnerContext(SWUUIACall *call) {
    return call != nullptr ? call->context->callbacks.context : nullptr;
}

int32_t SWU_UIACallStatus(SWUUIACall *call) {
    return call != nullptr ? call->status() : UIA_E_ELEMENTNOTAVAILABLE;
}

void SWU_UIACallFail(SWUUIACall *call, int32_t failure) {
    if (call != nullptr) call->fail(failure);
}

void SWU_UIACallRevokeOwner(SWUUIACall *call) {
    if (call != nullptr) call->context->revoke();
}

SWUUIAProviderContext *SWU_UIACreateProviderContext(
    const SWUUIACallbacks *callbacks, void (*releaseContext)(void *)) {
    if (callbacks == nullptr) return nullptr;
    return new (std::nothrow) SWUUIAProviderContext(*callbacks, releaseContext);
}

SWUUIAProviderContext *SWU_UIACreateProviderContextWithCalls(
    const SWUUIACallCallbacks *callbacks, void (*releaseContext)(void *), const SWUUIADrainWake *drainWake) {
    if (callbacks == nullptr) return nullptr;
    return new (std::nothrow) SWUUIAProviderContext(
        *callbacks, releaseContext, drainWake != nullptr ? *drainWake : SWUUIADrainWake{});
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

int SWU_UIAProviderContextIsQuiescent(SWUUIAProviderContext *context) {
    return context != nullptr && context->isQuiescent() ? 1 : 0;
}

int32_t SWU_UIAProviderContextDrainWakeResult(SWUUIAProviderContext *context) {
    return context != nullptr ? context->drainWakeResult() : UIA_E_ELEMENTNOTAVAILABLE;
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

int32_t SWU_UIAProviderArmControlTypePublicationGate(
    void *provider, uint32_t holdTimeoutMilliseconds, SWUUIAPublicationGate **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (provider == nullptr) return E_POINTER;
    if (!validPublicationGateTimeout(holdTimeoutMilliseconds)) return E_INVALIDARG;
    COMCallPin pin(asSimple(provider));
    SWUUIAPublicationGate *raw = nullptr;
    HRESULT status = SWUUIAPublicationGate::create(holdTimeoutMilliseconds, &raw);
    OwnedPublicationGate gate(raw);
    if (FAILED(status)) return status;
    status = asProvider(provider)->armControlTypePublicationGate(gate.get());
    if (FAILED(status)) return status;
    *result = gate.release();
    return S_OK;
}

void SWU_UIARetainPublicationGate(SWUUIAPublicationGate *gate) {
    if (gate != nullptr) gate->retain();
}

void SWU_UIAReleasePublicationGate(SWUUIAPublicationGate *gate) {
    if (gate != nullptr) gate->release();
}

int32_t SWU_UIAPublicationGateWaitUntilEntered(SWUUIAPublicationGate *gate, uint32_t timeoutMilliseconds) {
    if (gate == nullptr) return E_POINTER;
    if (!validPublicationGateTimeout(timeoutMilliseconds)) return E_INVALIDARG;
    return gate->waitUntilEntered(timeoutMilliseconds);
}

uint32_t SWU_UIAPublicationGateEnteredThreadID(SWUUIAPublicationGate *gate) {
    return gate != nullptr ? gate->enteredThreadID() : 0;
}

int32_t SWU_UIAPublicationGateOpen(SWUUIAPublicationGate *gate) {
    return gate != nullptr ? gate->open() : E_POINTER;
}

intptr_t SWU_UIAReturnRawElementProvider(void *hwnd, uintptr_t wParam, intptr_t lParam, void *provider) {
    if (provider == nullptr) {
        if (hwnd == nullptr || wParam != 0 || lParam != 0) return 0;
        return static_cast<intptr_t>(UiaReturnRawElementProvider(static_cast<HWND>(hwnd), 0, 0, nullptr));
    }
    ProviderCall call(asSimple(provider), asProvider(provider)->providerContext());
    if (FAILED(call.status())) return 0;
    // This call borrows the provider. The temporary reference is balanced even
    // when the OS reenters the host and drops its owning reference.
    LRESULT result = UiaReturnRawElementProvider(
        static_cast<HWND>(hwnd), static_cast<WPARAM>(wParam), static_cast<LPARAM>(lParam), asSimple(provider));
    return SUCCEEDED(call.status()) ? static_cast<intptr_t>(result) : 0;
}

int SWU_UIAClientsAreListening(void) {
    return UiaClientsAreListening() ? 1 : 0;
}

void SWU_UIARaiseAutomationFocusChanged(void *provider) {
    if (provider == nullptr) return;
    ProviderCall call(asSimple(provider), asProvider(provider)->providerContext());
    if (SUCCEEDED(call.status())) {
        UiaRaiseAutomationEvent(asSimple(provider), UIA_AutomationFocusChangedEventId);
    }
}

void SWU_UIARaiseStructureChanged(void *provider) {
    if (provider == nullptr) return;
    ProviderCall call(asSimple(provider), asProvider(provider)->providerContext());
    if (SUCCEEDED(call.status())) {
        UiaRaiseStructureChangedEvent(asSimple(provider), StructureChangeType_ChildrenInvalidated, nullptr, 0);
    }
}

void SWU_UIARaiseLiveRegionChanged(void *provider) {
    if (provider == nullptr) return;
    ProviderCall call(asSimple(provider), asProvider(provider)->providerContext());
    if (SUCCEEDED(call.status())) {
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

int32_t SWU_UIAItemContainerProviderFindItemResult(
    void *itemContainerProvider, void *after, int32_t property,
    const uint16_t *value, int32_t length, void **result) {
    if (result == nullptr) return E_POINTER;
    *result = nullptr;
    if (length < 0 || (value == nullptr && length != 0)) return E_INVALIDARG;
    if (itemContainerProvider == nullptr) return E_POINTER;
    VARIANT propertyValue;
    VariantInit(&propertyValue);
    OwnedBSTR text;
    if (value != nullptr) {
        text.reset(SysAllocStringLen(reinterpret_cast<const OLECHAR *>(value), static_cast<UINT>(length)));
        if (!text) return E_OUTOFMEMORY;
        propertyValue.vt = VT_BSTR;
        propertyValue.bstrVal = text.get();
    }
    IRawElementProviderSimple *raw = nullptr;
    HRESULT status = static_cast<IItemContainerProvider *>(itemContainerProvider)->FindItemByProperty(
        after == nullptr ? nullptr : asSimple(after), property, propertyValue, &raw);
    COMOwned<IRawElementProviderSimple> provider(raw);
    if (FAILED(status)) return status;
    *result = provider ? static_cast<SWUProvider *>(provider.release()) : nullptr;
    return S_OK;
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

void *SWU_UIAProviderGetItemContainerPattern(void *provider) {
    void *result = nullptr;
    SWU_UIAProviderGetPatternResult(provider, SWU_UIA_PATTERN_ITEM_CONTAINER, &result);
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
