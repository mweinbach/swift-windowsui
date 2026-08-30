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
    SWU_D2D_MAX_GRADIENT_STOPS = 128,
};

typedef struct SWU_D2DGradientStop {
    float position;
    float red;
    float green;
    float blue;
    float alpha;
} SWU_D2DGradientStop;

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

HRESULT SWU_D2DFillRectGradientStops(
    void *context,
    float left,
    float top,
    float right,
    float bottom,
    float radius_x,
    float radius_y,
    const SWU_D2DGradientStop *stops,
    uint32_t stop_count,
    int axis
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

// Bounded, synchronous memory decoding. The caller owns the worker and keeps
// encoded_bytes alive until return. Success transfers one malloc allocation;
// release it with SWU_FreeImagePixels. Every failure zeros the entire result.
enum {
    SWU_BOUNDED_IMAGE_MAX_ENCODED_BYTES = 8388608,
    SWU_BOUNDED_IMAGE_MAX_SOURCE_PIXELS = 16000000,
    SWU_BOUNDED_IMAGE_MAX_DECODED_BYTES = 64000000,
    SWU_BOUNDED_IMAGE_MAX_DIMENSION = 1024,
    SWU_BOUNDED_IMAGE_OK = 0,
    SWU_BOUNDED_IMAGE_INVALID_DATA = 1,
    SWU_BOUNDED_IMAGE_ENCODED_LIMIT = 2,
    SWU_BOUNDED_IMAGE_SOURCE_LIMIT = 3,
    SWU_BOUNDED_IMAGE_OUTPUT_LIMIT = 4,
    SWU_BOUNDED_IMAGE_UNSUPPORTED_FORMAT = 5,
    SWU_BOUNDED_IMAGE_MULTIPLE_FRAMES = 6,
    SWU_BOUNDED_IMAGE_INVALID_ORIENTATION = 7,
    SWU_BOUNDED_IMAGE_COLOR_FAILED = 8,
    SWU_BOUNDED_IMAGE_DECODE_FAILED = 9,
};

typedef struct SWU_BoundedImageResult {
    void *pixels;
    int32_t width;
    int32_t height;
    int32_t bytes_per_row;
    int32_t source_width;
    int32_t source_height;
} SWU_BoundedImageResult;

int32_t SWU_DecodeBoundedImage(
    const uint8_t *encoded_bytes,
    uint32_t encoded_byte_count,
    uint32_t maximum_pixel_dimension,
    SWU_BoundedImageResult *result_out
);

// Separate compatibility policy: first installed-WIC frame, full admitted
// dimensions, raw orientation/color and straight BGRA. Never a media fallback.
int32_t SWU_DecodeBoundedImageFirstFrame(
    const uint8_t *encoded_bytes,
    uint32_t encoded_byte_count,
    SWU_BoundedImageResult *result_out
);

// Optional bitmap-font evidence. These POD records contain no paths, reference
// keys, COM pointers, or font bytes. Numeric values are part of the V2 ABI.
enum {
    SWU_BITMAP_FONT_MAX_FILES = 8,
    SWU_BITMAP_FONT_MAX_AXES = 32,
    SWU_BITMAP_FONT_MAX_REFERENCE_KEY_BYTES = 65536,
    SWU_BITMAP_FONT_MAX_PATH_UNITS = 1024,
    SWU_BITMAP_FONT_MAX_BASENAME_UNITS = 255,
    SWU_BITMAP_FONT_FRAGMENT_BYTES = 65536,
    SWU_BITMAP_FONT_MAX_FILE_BYTES = 16777216,
    SWU_BITMAP_FONT_MAX_SESSION_BYTES = 67108864,
};

enum {
    SWU_BITMAP_FONT_STATUS_OBSERVED = 0,
    SWU_BITMAP_FONT_STATUS_PARTIAL = 1,
    SWU_BITMAP_FONT_STATUS_UNAVAILABLE = 2,
    SWU_BITMAP_FONT_STATUS_FAILED = 3,
    SWU_BITMAP_FONT_STATUS_LIMIT_EXCEEDED = 4,
    SWU_BITMAP_FONT_STATUS_INVALID_VALUE = 5,
    SWU_BITMAP_FONT_STATUS_NOT_IN_SYSTEM_COLLECTION = 6,
    SWU_BITMAP_FONT_STATUS_NONLOCAL_OR_CUSTOM = 7,
    SWU_BITMAP_FONT_STATUS_NOT_APPROVED = 8,
    SWU_BITMAP_FONT_STATUS_NOT_IMPLEMENTED = 9,
};

enum {
    SWU_BITMAP_FONT_SCOPE_NONE = 0,
    SWU_BITMAP_FONT_SCOPE_SYSTEM_FONTS = 1,
    SWU_BITMAP_FONT_SCOPE_USER_FONTS = 2,
    SWU_BITMAP_FONT_CODE_NONE = 0,
    SWU_BITMAP_FONT_CODE_HRESULT = 1,
    SWU_BITMAP_FONT_CODE_WIN32 = 2,
    SWU_BITMAP_FONT_CODE_NTSTATUS = 3,
};

enum {
    SWU_BITMAP_FONT_OPERATION_NOT_STARTED = 0,
    SWU_BITMAP_FONT_OPERATION_GET_FILES = 1,
    SWU_BITMAP_FONT_OPERATION_GET_REFERENCE_KEY = 2,
    SWU_BITMAP_FONT_OPERATION_GET_LOADER = 3,
    SWU_BITMAP_FONT_OPERATION_QUERY_LOCAL_LOADER = 4,
    SWU_BITMAP_FONT_OPERATION_GET_LOCAL_PATH = 5,
    SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH = 6,
    SWU_BITMAP_FONT_OPERATION_OPEN_LOCAL_FILE = 7,
    SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE = 8,
    SWU_BITMAP_FONT_OPERATION_CREATE_STREAM = 9,
    SWU_BITMAP_FONT_OPERATION_GET_STREAM_SIZE = 10,
    SWU_BITMAP_FONT_OPERATION_CHECK_BYTE_BUDGET = 11,
    SWU_BITMAP_FONT_OPERATION_INITIALIZE_SHA256 = 12,
    SWU_BITMAP_FONT_OPERATION_READ_STREAM_FRAGMENT = 13,
    SWU_BITMAP_FONT_OPERATION_HASH_STREAM_FRAGMENT = 14,
    SWU_BITMAP_FONT_OPERATION_FINISH_SHA256 = 15,
    SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE_AFTER = 16,
    SWU_BITMAP_FONT_OPERATION_COMPLETE = 17,
};

typedef struct SWU_BitmapFontAxisValueV2 {
    uint32_t tag;
    float value;
} SWU_BitmapFontAxisValueV2;

typedef struct SWU_BitmapFontFileEvidenceV2 {
    uint32_t index;
    uint32_t reference_status;
    uint32_t scope;
    uint32_t basename_length;
    uint16_t basename[256];
    uint32_t status;
    uint32_t operation;
    uint32_t code_domain;
    uint32_t has_code;
    int32_t code;
    uint32_t has_stream_length;
    uint64_t stream_length;
    uint64_t requested_bytes;
    uint64_t read_bytes;
    uint32_t has_sha256;
    uint8_t sha256[32];
} SWU_BitmapFontFileEvidenceV2;

typedef struct SWU_BitmapFontFaceEvidenceV2 {
    uint32_t has_face_type;
    uint32_t face_type;
    uint32_t axes_status;
    uint32_t axis_count;
    uint32_t has_variations_value;
    uint32_t has_variations;
    uint32_t files_status;
    uint32_t file_count;
    uint64_t requested_bytes;
    uint64_t read_bytes;
} SWU_BitmapFontFaceEvidenceV2;

// The face is borrowed; this synchronous call holds its own reference. Output
// capacities must be exactly MAX_AXES/MAX_FILES. A caller may share a 64 MiB
// request budget across calls; each file is capped at 16 MiB. Requested bytes
// are charged immediately before each ReadFileFragment attempt, including a
// failed attempt. Read bytes count successful nonnull fragments, even if a
// subsequent hash operation fails. A digest is published only after all bytes
// and the final local-file checks succeed. Work caps are not a COM timeout.
//
// The digest describes this face's file stream at observation time. It does
// not prove the bytes used by an earlier rasterization or an atomic snapshot.
void SWU_BitmapObserveFontFaceV2(
    void *borrowed_font_face,
    uint64_t remaining_requested_bytes,
    SWU_BitmapFontFaceEvidenceV2 *face_out,
    SWU_BitmapFontAxisValueV2 *axes_out,
    uint32_t axes_capacity,
    SWU_BitmapFontFileEvidenceV2 *files_out,
    uint32_t files_capacity
);

#ifdef __cplusplus
}
#endif

#endif
