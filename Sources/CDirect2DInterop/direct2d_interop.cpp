#include "CDirect2DInterop.h"

#ifdef DrawText
#undef DrawText
#endif

#include <d2d1_1.h>
#include <d3d11_1.h>
#include <dwrite.h>
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

static D2D1_POINT_2F swu_read_point(const float *points, int32_t point_count, int32_t *point_index) {
    D2D1_POINT_2F point{};
    if (points == nullptr || point_index == nullptr || *point_index + 1 >= point_count) {
        return point;
    }

    point.x = points[*point_index];
    point.y = points[*point_index + 1];
    *point_index += 2;
    return point;
}

static bool swu_has_points(int32_t point_index, int32_t point_count, int32_t required_floats) {
    return required_floats >= 0 && point_index <= point_count && point_count - point_index >= required_floats;
}

static HRESULT swu_create_path_geometry(
    ID2D1DeviceContext *context,
    const int32_t *segment_types,
    int32_t segment_count,
    const float *points,
    int32_t point_count,
    ID2D1PathGeometry **geometry_out
) {
    ID2D1Factory *factory = nullptr;
    ID2D1PathGeometry *geometry = nullptr;
    ID2D1GeometrySink *sink = nullptr;
    HRESULT hr = S_OK;
    int32_t point_index = 0;
    bool figure_open = false;
    bool saw_figure = false;

    if (
        context == nullptr ||
        segment_types == nullptr ||
        segment_count <= 0 ||
        points == nullptr ||
        point_count < 0 ||
        geometry_out == nullptr
    ) {
        return E_INVALIDARG;
    }

    *geometry_out = nullptr;
    context->GetFactory(&factory);
    if (factory == nullptr) {
        return E_FAIL;
    }

    hr = factory->CreatePathGeometry(&geometry);
    if (FAILED(hr)) {
        goto cleanup;
    }

    hr = geometry->Open(&sink);
    if (FAILED(hr)) {
        goto cleanup;
    }

    sink->SetFillMode(D2D1_FILL_MODE_WINDING);

    for (int32_t i = 0; i < segment_count; ++i) {
        switch (segment_types[i]) {
        case SWU_D2D_PATH_MOVE_TO: {
            if (!swu_has_points(point_index, point_count, 2)) {
                hr = E_INVALIDARG;
                goto cleanup;
            }
            if (figure_open) {
                sink->EndFigure(D2D1_FIGURE_END_OPEN);
                figure_open = false;
            }
            auto point = swu_read_point(points, point_count, &point_index);
            sink->BeginFigure(point, D2D1_FIGURE_BEGIN_FILLED);
            figure_open = true;
            saw_figure = true;
            break;
        }
        case SWU_D2D_PATH_LINE_TO: {
            if (!figure_open || !swu_has_points(point_index, point_count, 2)) {
                hr = E_INVALIDARG;
                goto cleanup;
            }
            auto point = swu_read_point(points, point_count, &point_index);
            sink->AddLine(point);
            break;
        }
        case SWU_D2D_PATH_QUAD_TO: {
            if (!figure_open || !swu_has_points(point_index, point_count, 4)) {
                hr = E_INVALIDARG;
                goto cleanup;
            }
            D2D1_QUADRATIC_BEZIER_SEGMENT segment{};
            segment.point1 = swu_read_point(points, point_count, &point_index);
            segment.point2 = swu_read_point(points, point_count, &point_index);
            sink->AddQuadraticBezier(segment);
            break;
        }
        case SWU_D2D_PATH_CUBIC_TO: {
            if (!figure_open || !swu_has_points(point_index, point_count, 6)) {
                hr = E_INVALIDARG;
                goto cleanup;
            }
            D2D1_BEZIER_SEGMENT segment{};
            segment.point1 = swu_read_point(points, point_count, &point_index);
            segment.point2 = swu_read_point(points, point_count, &point_index);
            segment.point3 = swu_read_point(points, point_count, &point_index);
            sink->AddBezier(segment);
            break;
        }
        case SWU_D2D_PATH_CLOSE:
            if (!figure_open) {
                hr = E_INVALIDARG;
                goto cleanup;
            }
            sink->EndFigure(D2D1_FIGURE_END_CLOSED);
            figure_open = false;
            break;
        default:
            hr = E_INVALIDARG;
            goto cleanup;
        }
    }

    if (figure_open) {
        sink->EndFigure(D2D1_FIGURE_END_OPEN);
    }

    if (!saw_figure || point_index != point_count) {
        hr = E_INVALIDARG;
        goto cleanup;
    }

    hr = sink->Close();
    if (FAILED(hr)) {
        goto cleanup;
    }

    *geometry_out = geometry;
    geometry = nullptr;

cleanup:
    swu_release_unknown(sink);
    swu_release_unknown(geometry);
    swu_release_unknown(factory);
    return hr;
}

static D2D1_CAP_STYLE swu_cap_style(int32_t cap) {
    switch (cap) {
    case SWU_D2D_LINE_CAP_ROUND:
        return D2D1_CAP_STYLE_ROUND;
    case SWU_D2D_LINE_CAP_SQUARE:
        return D2D1_CAP_STYLE_SQUARE;
    case SWU_D2D_LINE_CAP_BUTT:
    default:
        return D2D1_CAP_STYLE_FLAT;
    }
}

static D2D1_LINE_JOIN swu_line_join(int32_t line_join) {
    switch (line_join) {
    case SWU_D2D_LINE_JOIN_ROUND:
        return D2D1_LINE_JOIN_ROUND;
    case SWU_D2D_LINE_JOIN_BEVEL:
        return D2D1_LINE_JOIN_BEVEL;
    case SWU_D2D_LINE_JOIN_MITER:
    default:
        return D2D1_LINE_JOIN_MITER;
    }
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
    bitmap_properties.pixelFormat.alphaMode = D2D1_ALPHA_MODE_PREMULTIPLIED;
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
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);
    ID2D1GradientStopCollection *stop_collection = nullptr;
    ID2D1LinearGradientBrush *brush = nullptr;
    D2D1_GRADIENT_STOP stops[2]{};
    D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES gradient_properties{};
    D2D1_BRUSH_PROPERTIES brush_properties{};
    D2D1_RECT_F rect{};
    HRESULT hr = S_OK;

    if (context == nullptr) {
        return E_INVALIDARG;
    }

    stops[0].position = 0.0f;
    stops[0].color = swu_color(start_red, start_green, start_blue, start_alpha);
    stops[1].position = 1.0f;
    stops[1].color = swu_color(end_red, end_green, end_blue, end_alpha);
    hr = context->CreateGradientStopCollection(
        stops,
        2,
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

extern "C" HRESULT SWU_D2DFillPathSolid(
    void *context_raw,
    const int32_t *segment_types,
    int32_t segment_count,
    const float *points,
    int32_t point_count,
    float red,
    float green,
    float blue,
    float alpha
) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);
    ID2D1PathGeometry *geometry = nullptr;
    ID2D1SolidColorBrush *brush = nullptr;
    D2D1_BRUSH_PROPERTIES brush_properties{};
    HRESULT hr = S_OK;

    if (context == nullptr) {
        return E_INVALIDARG;
    }

    hr = swu_create_path_geometry(context, segment_types, segment_count, points, point_count, &geometry);
    if (FAILED(hr)) {
        goto cleanup;
    }

    brush_properties.opacity = 1.0f;
    brush_properties.transform = swu_identity_matrix();
    {
        auto color = swu_color(red, green, blue, alpha);
        hr = context->CreateSolidColorBrush(&color, &brush_properties, &brush);
    }
    if (FAILED(hr)) {
        goto cleanup;
    }

    context->SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
    context->FillGeometry(geometry, brush);

cleanup:
    swu_release_unknown(brush);
    swu_release_unknown(geometry);
    return hr;
}

extern "C" HRESULT SWU_D2DStrokePathSolid(
    void *context_raw,
    const int32_t *segment_types,
    int32_t segment_count,
    const float *points,
    int32_t point_count,
    float red,
    float green,
    float blue,
    float alpha,
    float line_width,
    const float *dash_pattern,
    int32_t dash_count,
    float dash_offset,
    int32_t line_cap,
    int32_t line_join
) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);
    ID2D1Factory *factory = nullptr;
    ID2D1PathGeometry *geometry = nullptr;
    ID2D1SolidColorBrush *brush = nullptr;
    ID2D1StrokeStyle *stroke_style = nullptr;
    D2D1_BRUSH_PROPERTIES brush_properties{};
    D2D1_STROKE_STYLE_PROPERTIES stroke_properties{};
    HRESULT hr = S_OK;

    if (context == nullptr || line_width <= 0.0f || dash_count < 0 || (dash_count > 0 && dash_pattern == nullptr)) {
        return E_INVALIDARG;
    }

    hr = swu_create_path_geometry(context, segment_types, segment_count, points, point_count, &geometry);
    if (FAILED(hr)) {
        goto cleanup;
    }

    brush_properties.opacity = 1.0f;
    brush_properties.transform = swu_identity_matrix();
    {
        auto color = swu_color(red, green, blue, alpha);
        hr = context->CreateSolidColorBrush(&color, &brush_properties, &brush);
    }
    if (FAILED(hr)) {
        goto cleanup;
    }

    context->GetFactory(&factory);
    if (factory == nullptr) {
        hr = E_FAIL;
        goto cleanup;
    }

    stroke_properties.startCap = swu_cap_style(line_cap);
    stroke_properties.endCap = swu_cap_style(line_cap);
    stroke_properties.dashCap = swu_cap_style(line_cap);
    stroke_properties.lineJoin = swu_line_join(line_join);
    stroke_properties.miterLimit = 10.0f;
    stroke_properties.dashStyle = dash_count > 0 ? D2D1_DASH_STYLE_CUSTOM : D2D1_DASH_STYLE_SOLID;
    stroke_properties.dashOffset = dash_offset;
    hr = factory->CreateStrokeStyle(
        stroke_properties,
        dash_pattern,
        static_cast<UINT32>(dash_count),
        &stroke_style
    );
    if (FAILED(hr)) {
        goto cleanup;
    }

    context->SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
    context->DrawGeometry(geometry, brush, line_width, stroke_style);

cleanup:
    swu_release_unknown(stroke_style);
    swu_release_unknown(brush);
    swu_release_unknown(geometry);
    swu_release_unknown(factory);
    return hr;
}

extern "C" HRESULT SWU_D2DDrawTextUTF16(
    void *context_raw,
    const wchar_t *text,
    int32_t text_length,
    float left,
    float top,
    float right,
    float bottom,
    const wchar_t *font_family,
    float font_size,
    int32_t font_weight,
    float red,
    float green,
    float blue,
    float alpha
) {
    auto context = static_cast<ID2D1DeviceContext *>(context_raw);
    IDWriteFactory *write_factory = nullptr;
    IDWriteTextFormat *text_format = nullptr;
    ID2D1SolidColorBrush *brush = nullptr;
    D2D1_BRUSH_PROPERTIES brush_properties{};
    D2D1_RECT_F layout_rect{};
    HRESULT hr = S_OK;

    if (
        context == nullptr ||
        text == nullptr ||
        text_length <= 0 ||
        right <= left ||
        bottom <= top ||
        font_size <= 0.0f
    ) {
        return E_INVALIDARG;
    }

    hr = DWriteCreateFactory(
        DWRITE_FACTORY_TYPE_SHARED,
        __uuidof(IDWriteFactory),
        reinterpret_cast<IUnknown **>(&write_factory)
    );
    if (FAILED(hr)) {
        goto cleanup;
    }

    hr = write_factory->CreateTextFormat(
        font_family != nullptr ? font_family : L"Segoe UI",
        nullptr,
        static_cast<DWRITE_FONT_WEIGHT>(font_weight),
        DWRITE_FONT_STYLE_NORMAL,
        DWRITE_FONT_STRETCH_NORMAL,
        font_size,
        L"",
        &text_format
    );
    if (FAILED(hr)) {
        goto cleanup;
    }

    text_format->SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP);
    text_format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_LEADING);
    text_format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_NEAR);

    brush_properties.opacity = 1.0f;
    brush_properties.transform = swu_identity_matrix();
    {
        auto color = swu_color(red, green, blue, alpha);
        hr = context->CreateSolidColorBrush(&color, &brush_properties, &brush);
    }
    if (FAILED(hr)) {
        goto cleanup;
    }

    layout_rect.left = left;
    layout_rect.top = top;
    layout_rect.right = right;
    layout_rect.bottom = bottom;
    context->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    context->DrawText(
        text,
        static_cast<UINT32>(text_length),
        text_format,
        &layout_rect,
        brush,
        D2D1_DRAW_TEXT_OPTIONS_CLIP,
        DWRITE_MEASURING_MODE_NATURAL
    );

cleanup:
    swu_release_unknown(brush);
    swu_release_unknown(text_format);
    swu_release_unknown(write_factory);
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

    if (context == nullptr || pixels == nullptr || width <= 0 || height <= 0 || bytes_per_row <= 0) {
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
    return hr;
}

extern "C" void SWU_FreeImagePixels(void *pixels) {
    free(pixels);
}
