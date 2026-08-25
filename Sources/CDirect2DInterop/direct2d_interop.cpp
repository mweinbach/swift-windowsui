#include "CDirect2DInterop.h"

#include <d2d1_1.h>
#include <d3d11_1.h>
#include <dxgi1_2.h>

static D2D1_MATRIX_3X2_F swu_identity_matrix() {
    D2D1_MATRIX_3X2_F matrix{};
    matrix._11 = 1.0f;
    matrix._22 = 1.0f;
    return matrix;
}

static D2D1_COLOR_F swu_color(float red, float green, float blue, float alpha) {
    D2D1_COLOR_F color{};
    color.r = red;
    color.g = green;
    color.b = blue;
    color.a = alpha;
    return color;
}

static void swu_release_unknown(IUnknown *object) {
    if (object != nullptr) {
        object->Release();
    }
}

static void swu_fill_geometry(
    ID2D1DeviceContext *context,
    ID2D1Brush *brush,
    const D2D1_RECT_F &rect,
    float radius_x,
    float radius_y
) {
    if (radius_x > 0.0f || radius_y > 0.0f) {
        D2D1_ROUNDED_RECT rounded_rect{};
        rounded_rect.rect = rect;
        rounded_rect.radiusX = radius_x;
        rounded_rect.radiusY = radius_y;
        context->FillRoundedRectangle(&rounded_rect, brush);
        return;
    }

    context->FillRectangle(&rect, brush);
}

extern "C" HRESULT SWU_D2DCreateFactory1(void **factory_out) {
    D2D1_FACTORY_OPTIONS options{};

    if (factory_out == nullptr) {
        return E_INVALIDARG;
    }

    *factory_out = nullptr;
    options.debugLevel = D2D1_DEBUG_LEVEL_NONE;

    return D2D1CreateFactory(
        D2D1_FACTORY_TYPE_SINGLE_THREADED,
        __uuidof(ID2D1Factory1),
        &options,
        factory_out
    );
}

extern "C" HRESULT SWU_D2DCreateDeviceResources(void *d3d11_device_raw, void **factory_out, void **device_out, void **context_out) {
    HRESULT hr = S_OK;
    auto d3d11_device = static_cast<ID3D11Device *>(d3d11_device_raw);
    IDXGIDevice *dxgi_device = nullptr;
    ID2D1Factory1 *factory = nullptr;
    ID2D1Device *device = nullptr;
    ID2D1DeviceContext *context = nullptr;

    if (d3d11_device == nullptr || factory_out == nullptr || device_out == nullptr || context_out == nullptr) {
        return E_INVALIDARG;
    }

    *factory_out = nullptr;
    *device_out = nullptr;
    *context_out = nullptr;

    hr = d3d11_device->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void **>(&dxgi_device));
    if (FAILED(hr)) {
        goto cleanup;
    }

    hr = SWU_D2DCreateFactory1(reinterpret_cast<void **>(&factory));
    if (FAILED(hr)) {
        goto cleanup;
    }

    hr = factory->CreateDevice(dxgi_device, &device);
    if (FAILED(hr)) {
        goto cleanup;
    }

    hr = device->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &context);
    if (FAILED(hr)) {
        goto cleanup;
    }

    *factory_out = factory;
    *device_out = device;
    *context_out = context;
    factory = nullptr;
    device = nullptr;
    context = nullptr;

cleanup:
    swu_release_unknown(context);
    swu_release_unknown(device);
    swu_release_unknown(factory);
    swu_release_unknown(dxgi_device);
    return hr;
}

extern "C" HRESULT SWU_D2DConfigureSwapChainTarget(void *context_raw, void *swap_chain_raw, float dpi_x, float dpi_y, void **target_bitmap_out) {
    HRESULT hr = S_OK;
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);
    auto swap_chain = static_cast<IDXGISwapChain1 *>(swap_chain_raw);
    IDXGISurface *surface = nullptr;
    ID2D1Bitmap1 *target_bitmap = nullptr;
    D2D1_BITMAP_PROPERTIES1 bitmap_properties{};

    if (context == nullptr || swap_chain == nullptr || target_bitmap_out == nullptr) {
        return E_INVALIDARG;
    }

    *target_bitmap_out = nullptr;
    SWU_D2DResetTarget(context_raw);

    hr = swap_chain->GetBuffer(0, __uuidof(IDXGISurface), reinterpret_cast<void **>(&surface));
    if (FAILED(hr)) {
        goto cleanup;
    }

    bitmap_properties.pixelFormat.format = DXGI_FORMAT_B8G8R8A8_UNORM;
    bitmap_properties.pixelFormat.alphaMode = D2D1_ALPHA_MODE_IGNORE;
    bitmap_properties.dpiX = dpi_x;
    bitmap_properties.dpiY = dpi_y;
    bitmap_properties.bitmapOptions = D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW;

    hr = context->CreateBitmapFromDxgiSurface(surface, &bitmap_properties, &target_bitmap);
    if (FAILED(hr)) {
        goto cleanup;
    }

    context->SetTarget(target_bitmap);
    context->SetDpi(dpi_x, dpi_y);
    SWU_D2DSetIdentityTransform(context_raw);

    *target_bitmap_out = target_bitmap;
    target_bitmap = nullptr;

cleanup:
    swu_release_unknown(target_bitmap);
    swu_release_unknown(surface);
    return hr;
}

extern "C" void SWU_D2DResetTarget(void *context_raw) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);

    if (context != nullptr) {
        context->SetTarget(nullptr);
    }
}

extern "C" void SWU_D2DBeginDraw(void *context_raw) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);

    if (context != nullptr) {
        context->BeginDraw();
    }
}

extern "C" HRESULT SWU_D2DEndDraw(void *context_raw) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);

    if (context == nullptr) {
        return E_INVALIDARG;
    }

    return context->EndDraw();
}

extern "C" void SWU_D2DClear(void *context_raw, float red, float green, float blue, float alpha) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);

    if (context != nullptr) {
        auto color = swu_color(red, green, blue, alpha);
        context->Clear(&color);
    }
}

extern "C" void SWU_D2DSetIdentityTransform(void *context_raw) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);

    if (context != nullptr) {
        auto transform = swu_identity_matrix();
        context->SetTransform(transform);
    }
}

extern "C" void SWU_D2DPushAxisAlignedClip(void *context_raw, float left, float top, float right, float bottom) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);

    if (context != nullptr) {
        D2D1_RECT_F rect{};
        rect.left = left;
        rect.top = top;
        rect.right = right;
        rect.bottom = bottom;
        context->PushAxisAlignedClip(&rect, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
    }
}

extern "C" void SWU_D2DPopAxisAlignedClip(void *context_raw) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);

    if (context != nullptr) {
        context->PopAxisAlignedClip();
    }
}

extern "C" HRESULT SWU_D2DFillRectSolid(
    void *context_raw,
    float left,
    float top,
    float right,
    float bottom,
    float radius_x,
    float radius_y,
    float red,
    float green,
    float blue,
    float alpha
) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);
    ID2D1SolidColorBrush *brush = nullptr;
    D2D1_BRUSH_PROPERTIES brush_properties{};
    D2D1_RECT_F rect{};
    HRESULT hr = S_OK;

    if (context == nullptr) {
        return E_INVALIDARG;
    }

    brush_properties.opacity = 1.0f;
    brush_properties.transform = swu_identity_matrix();
    auto color = swu_color(red, green, blue, alpha);
    hr = context->CreateSolidColorBrush(&color, &brush_properties, &brush);
    if (FAILED(hr)) {
        return hr;
    }

    rect.left = left;
    rect.top = top;
    rect.right = right;
    rect.bottom = bottom;
    swu_fill_geometry(context, brush, rect, radius_x, radius_y);

    swu_release_unknown(brush);
    return S_OK;
}

extern "C" HRESULT SWU_D2DFillRectGradient(
    void *context_raw,
    float left,
    float top,
    float right,
    float bottom,
    float radius_x,
    float radius_y,
    float start_red,
    float start_green,
    float start_blue,
    float start_alpha,
    float end_red,
    float end_green,
    float end_blue,
    float end_alpha,
    int axis
) {
    SWU_D2DGradientStop stops[2]{};
    stops[0].position = 0.0f;
    stops[0].red = start_red;
    stops[0].green = start_green;
    stops[0].blue = start_blue;
    stops[0].alpha = start_alpha;
    stops[1].position = 1.0f;
    stops[1].red = end_red;
    stops[1].green = end_green;
    stops[1].blue = end_blue;
    stops[1].alpha = end_alpha;

    return SWU_D2DFillRectGradientStops(
        context_raw,
        left,
        top,
        right,
        bottom,
        radius_x,
        radius_y,
        stops,
        2,
        axis
    );
}

extern "C" HRESULT SWU_D2DFillRectGradientStops(
    void *context_raw,
    float left,
    float top,
    float right,
    float bottom,
    float radius_x,
    float radius_y,
    const SWU_D2DGradientStop *stops,
    uint32_t stop_count,
    int axis
) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);
    ID2D1GradientStopCollection *stop_collection = nullptr;
    ID2D1LinearGradientBrush *brush = nullptr;
    D2D1_GRADIENT_STOP native_stops[SWU_D2D_MAX_GRADIENT_STOPS]{};
    D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES gradient_properties{};
    D2D1_BRUSH_PROPERTIES brush_properties{};
    D2D1_RECT_F rect{};
    HRESULT hr = S_OK;

    if (
        context == nullptr || stops == nullptr || stop_count < 2
        || stop_count > SWU_D2D_MAX_GRADIENT_STOPS
    ) {
        return E_INVALIDARG;
    }

    for (uint32_t index = 0; index < stop_count; ++index) {
        const auto &stop = stops[index];
        // The conjunctive range check rejects NaN as well as infinities.
        // Equal positions remain valid: they encode authored hard stops.
        if (!(stop.position >= 0.0f && stop.position <= 1.0f)) {
            return E_INVALIDARG;
        }
        if (index > 0 && stop.position < native_stops[index - 1].position) {
            return E_INVALIDARG;
        }

        native_stops[index].position = stop.position;
        native_stops[index].color = swu_color(stop.red, stop.green, stop.blue, stop.alpha);
    }

    hr = context->CreateGradientStopCollection(
        native_stops,
        stop_count,
        D2D1_GAMMA_2_2,
        D2D1_EXTEND_MODE_CLAMP,
        &stop_collection
    );
    if (FAILED(hr)) {
        goto cleanup;
    }

    gradient_properties.startPoint.x = left;
    gradient_properties.startPoint.y = top;
    gradient_properties.endPoint.x = axis == SWU_D2D_GRADIENT_AXIS_HORIZONTAL ? right : left;
    gradient_properties.endPoint.y = axis == SWU_D2D_GRADIENT_AXIS_HORIZONTAL ? top : bottom;
    brush_properties.opacity = 1.0f;
    brush_properties.transform = swu_identity_matrix();
    hr = context->CreateLinearGradientBrush(&gradient_properties, &brush_properties, stop_collection, &brush);
    if (FAILED(hr)) {
        goto cleanup;
    }

    rect.left = left;
    rect.top = top;
    rect.right = right;
    rect.bottom = bottom;
    swu_fill_geometry(context, brush, rect, radius_x, radius_y);

cleanup:
    swu_release_unknown(brush);
    swu_release_unknown(stop_collection);
    return hr;
}

extern "C" HRESULT SWU_D2DDrawBitmapBGRA(
    void *context_raw,
    const void *pixels,
    int32_t width,
    int32_t height,
    int32_t bytes_per_row,
    float dpi_x,
    float dpi_y,
    float left,
    float top,
    float right,
    float bottom,
    float opacity
) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);
    ID2D1Bitmap1 *bitmap = nullptr;
    D2D1_BITMAP_PROPERTIES1 bitmap_properties{};
    D2D1_RECT_F destination{};
    D2D1_SIZE_U bitmap_size{};
    HRESULT hr = S_OK;

    // `pixels` must be premultiplied BGRA covering bytes_per_row * height
    // bytes: Direct2D bitmaps support only PREMULTIPLIED and IGNORE alpha
    // modes, so the Swift caller normalizes the surface before calling.
    // A stride narrower than one row would make CreateBitmap read past the
    // buffer, so reject it here as well as on the Swift side.
    if (context == nullptr || pixels == nullptr || width <= 0 || height <= 0 || bytes_per_row <= 0 ||
        bytes_per_row / 4 < width) {
        return E_INVALIDARG;
    }

    bitmap_properties.pixelFormat.format = DXGI_FORMAT_B8G8R8A8_UNORM;
    bitmap_properties.pixelFormat.alphaMode = D2D1_ALPHA_MODE_PREMULTIPLIED;
    bitmap_properties.dpiX = dpi_x;
    bitmap_properties.dpiY = dpi_y;
    bitmap_properties.bitmapOptions = D2D1_BITMAP_OPTIONS_NONE;

    bitmap_size.width = static_cast<UINT32>(width);
    bitmap_size.height = static_cast<UINT32>(height);
    hr = context->CreateBitmap(bitmap_size, pixels, static_cast<UINT32>(bytes_per_row), &bitmap_properties, &bitmap);
    if (FAILED(hr)) {
        goto cleanup;
    }

    destination.left = left;
    destination.top = top;
    destination.right = right;
    destination.bottom = bottom;
    context->DrawBitmap(bitmap, &destination, opacity, D2D1_INTERPOLATION_MODE_NEAREST_NEIGHBOR);

cleanup:
    swu_release_unknown(bitmap);
    return hr;
}

extern "C" void SWU_D2DRelease(void *object_raw) {
    swu_release_unknown(static_cast<IUnknown *>(object_raw));
}

// Gap 13: Image loading via WIC

#include <wincodec.h>

extern "C" HRESULT SWU_LoadImageFileToBGRA(
    const wchar_t *file_path,
    void **pixels_out,
    int32_t *width_out,
    int32_t *height_out,
    int32_t *bytes_per_row_out
) {
    if (!file_path || !pixels_out || !width_out || !height_out || !bytes_per_row_out) {
        return E_INVALIDARG;
    }

    *pixels_out = nullptr;
    *width_out = 0;
    *height_out = 0;
    *bytes_per_row_out = 0;

    IWICImagingFactory *factory = nullptr;
    IWICBitmapDecoder *decoder = nullptr;
    IWICBitmapFrameDecode *frame = nullptr;
    IWICFormatConverter *converter = nullptr;
    HRESULT hr;
    HRESULT coinit_hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    bool did_initialize_com = SUCCEEDED(coinit_hr);

    if (FAILED(coinit_hr) && coinit_hr != RPC_E_CHANGED_MODE) {
        hr = coinit_hr;
        goto cleanup;
    }

    hr = CoCreateInstance(
        CLSID_WICImagingFactory,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory)
    );
    if (FAILED(hr)) goto cleanup;

    hr = factory->CreateDecoderFromFilename(
        file_path,
        nullptr,
        GENERIC_READ,
        WICDecodeMetadataCacheOnLoad,
        &decoder
    );
    if (FAILED(hr)) goto cleanup;

    hr = decoder->GetFrame(0, &frame);
    if (FAILED(hr)) goto cleanup;

    hr = factory->CreateFormatConverter(&converter);
    if (FAILED(hr)) goto cleanup;

    hr = converter->Initialize(
        frame,
        GUID_WICPixelFormat32bppBGRA,
        WICBitmapDitherTypeNone,
        nullptr,
        0.0,
        WICBitmapPaletteTypeCustom
    );
    if (FAILED(hr)) goto cleanup;

    {
        UINT w = 0, h = 0;
        hr = converter->GetSize(&w, &h);
        if (FAILED(hr)) goto cleanup;

        int32_t bpr = static_cast<int32_t>(w) * 4;
        UINT bufferSize = bpr * static_cast<int32_t>(h);
        void *buffer = malloc(bufferSize);
        if (!buffer) {
            hr = E_OUTOFMEMORY;
            goto cleanup;
        }

        hr = converter->CopyPixels(nullptr, static_cast<UINT>(bpr), bufferSize, static_cast<BYTE *>(buffer));
        if (FAILED(hr)) {
            free(buffer);
            goto cleanup;
        }

        *pixels_out = buffer;
        *width_out = static_cast<int32_t>(w);
        *height_out = static_cast<int32_t>(h);
        *bytes_per_row_out = bpr;
    }

cleanup:
    if (converter) converter->Release();
    if (frame) frame->Release();
    if (decoder) decoder->Release();
    if (factory) factory->Release();
    if (did_initialize_com) CoUninitialize();
    return hr;
}

extern "C" void SWU_FreeImagePixels(void *pixels) {
    free(pixels);
}
