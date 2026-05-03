#ifndef CDIRECT2DINTEROP_H
#define CDIRECT2DINTEROP_H

#include <stdint.h>
#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    SWU_D2D_GRADIENT_AXIS_VERTICAL = 0,
    SWU_D2D_GRADIENT_AXIS_HORIZONTAL = 1,
};

enum {
    SWU_D2D_PATH_MOVE_TO = 0,
    SWU_D2D_PATH_LINE_TO = 1,
    SWU_D2D_PATH_QUAD_TO = 2,
    SWU_D2D_PATH_CUBIC_TO = 3,
    SWU_D2D_PATH_CLOSE = 4,
};

enum {
    SWU_D2D_LINE_CAP_BUTT = 0,
    SWU_D2D_LINE_CAP_ROUND = 1,
    SWU_D2D_LINE_CAP_SQUARE = 2,
};

enum {
    SWU_D2D_LINE_JOIN_MITER = 0,
    SWU_D2D_LINE_JOIN_ROUND = 1,
    SWU_D2D_LINE_JOIN_BEVEL = 2,
};

HRESULT SWU_D2DCreateFactory1(void **factory_out);
HRESULT SWU_D2DCreateDeviceResources(void *d3d11_device, void **factory_out, void **device_out, void **context_out);
HRESULT SWU_D2DConfigureSwapChainTarget(void *context, void *swap_chain, float dpi_x, float dpi_y, void **target_bitmap_out);

void SWU_D2DResetTarget(void *context);
void SWU_D2DBeginDraw(void *context);
HRESULT SWU_D2DEndDraw(void *context);
void SWU_D2DClear(void *context, float red, float green, float blue, float alpha);
void SWU_D2DSetIdentityTransform(void *context);
void SWU_D2DPushAxisAlignedClip(void *context, float left, float top, float right, float bottom);
void SWU_D2DPopAxisAlignedClip(void *context);

HRESULT SWU_D2DFillRectSolid(
    void *context,
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
);

HRESULT SWU_D2DFillRectGradient(
    void *context,
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
);

HRESULT SWU_D2DFillPathSolid(
    void *context,
    const int32_t *segment_types,
    int32_t segment_count,
    const float *points,
    int32_t point_count,
    float red,
    float green,
    float blue,
    float alpha
);

HRESULT SWU_D2DStrokePathSolid(
    void *context,
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
);

HRESULT SWU_D2DDrawTextUTF16(
    void *context,
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
);

HRESULT SWU_D2DApplyGaussianBlur(
    void *context,
    float left,
    float top,
    float right,
    float bottom,
    float radius,
    float scale_factor,
    float dpi_x,
    float dpi_y
);

HRESULT SWU_D2DDrawBitmapBGRA(
    void *context,
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
);

void SWU_D2DRelease(void *object);

// Gap 13: Image loading via WIC
HRESULT SWU_LoadImageFileToBGRA(
    const wchar_t *file_path,
    void **pixels_out,
    int32_t *width_out,
    int32_t *height_out,
    int32_t *bytes_per_row_out
);

void SWU_FreeImagePixels(void *pixels);

#ifdef __cplusplus
}
#endif

#endif
