#include "CDirect2DInterop.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <wincodec.h>

namespace {

template <typename T> struct OwnedInterface {
    T *value = nullptr;
    OwnedInterface() = default;
    OwnedInterface(const OwnedInterface &) = delete;
    OwnedInterface &operator=(const OwnedInterface &) = delete;
    ~OwnedInterface() { if (value) value->Release(); }
};

struct OwnedApartment {
    HRESULT status = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    ~OwnedApartment() { if (SUCCEEDED(status)) CoUninitialize(); }
};

struct OwnedVariant {
    PROPVARIANT value{};
    ~OwnedVariant() { PropVariantClear(&value); }
};

struct OwnedPixels {
    void *value = nullptr;
    ~OwnedPixels() { free(value); }
};

uint32_t bigEndian32(const uint8_t *bytes) {
    return (static_cast<uint32_t>(bytes[0]) << 24)
        | (static_cast<uint32_t>(bytes[1]) << 16)
        | (static_cast<uint32_t>(bytes[2]) << 8) | bytes[3];
}

// WIC can expose APNG or an MPO container as one decoded frame. Reject their
// animation/multi-picture markers too, without allocating metadata buffers.
int32_t admitContainer(const uint8_t *bytes, uint32_t count) {
    const uint8_t pngSignature[] = {137, 80, 78, 71, 13, 10, 26, 10};
    if (count >= 8 && memcmp(bytes, pngSignature, 8) == 0) {
        uint64_t offset = 8;
        while (offset < count) {
            if (static_cast<uint64_t>(count) - offset < 12) return SWU_BOUNDED_IMAGE_INVALID_DATA;
            uint32_t length = bigEndian32(bytes + static_cast<size_t>(offset));
            uint64_t end = offset + 12 + static_cast<uint64_t>(length);
            if (end > count) return SWU_BOUNDED_IMAGE_INVALID_DATA;
            const uint8_t *type = bytes + static_cast<size_t>(offset) + 4;
            if (memcmp(type, "acTL", 4) == 0) return SWU_BOUNDED_IMAGE_MULTIPLE_FRAMES;
            if (memcmp(type, "IEND", 4) == 0) {
                return length == 0 && end == count ? SWU_BOUNDED_IMAGE_OK : SWU_BOUNDED_IMAGE_INVALID_DATA;
            }
            offset = end;
        }
        return SWU_BOUNDED_IMAGE_INVALID_DATA;
    }
    if (count >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
        uint64_t offset = 2;
        while (offset < count) {
            if (bytes[offset++] != 0xff) return SWU_BOUNDED_IMAGE_INVALID_DATA;
            while (offset < count && bytes[offset] == 0xff) ++offset;
            if (offset >= count) return SWU_BOUNDED_IMAGE_INVALID_DATA;
            uint8_t marker = bytes[offset++];
            if (marker == 0xda || marker == 0xd9) return SWU_BOUNDED_IMAGE_OK;
            if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
            if (marker == 0 || static_cast<uint64_t>(count) - offset < 2) return SWU_BOUNDED_IMAGE_INVALID_DATA;
            uint32_t length = (static_cast<uint32_t>(bytes[offset]) << 8) | bytes[offset + 1];
            if (length < 2 || offset + length > count) return SWU_BOUNDED_IMAGE_INVALID_DATA;
            if (marker == 0xe2 && length >= 6 && memcmp(bytes + offset + 2, "MPF\0", 4) == 0) {
                return SWU_BOUNDED_IMAGE_MULTIPLE_FRAMES;
            }
            offset += length;
        }
        return SWU_BOUNDED_IMAGE_INVALID_DATA;
    }
    return SWU_BOUNDED_IMAGE_OK;
}

int32_t jpegOrientation(IWICBitmapFrameDecode *frame, uint32_t *orientation) {
    *orientation = 1;
    OwnedInterface<IWICMetadataQueryReader> metadata;
    HRESULT hr = frame->GetMetadataQueryReader(&metadata.value);
    if (hr == WINCODEC_ERR_UNSUPPORTEDOPERATION) return SWU_BOUNDED_IMAGE_OK;
    if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    OwnedVariant property;
    hr = metadata.value->GetMetadataByName(L"/app1/ifd/{ushort=274}", &property.value);
    if (hr == WINCODEC_ERR_PROPERTYNOTFOUND || hr == WINCODEC_ERR_PROPERTYNOTSUPPORTED
        || hr == WINCODEC_ERR_UNSUPPORTEDOPERATION) return SWU_BOUNDED_IMAGE_OK;
    if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    uint32_t value = property.value.vt == VT_UI2 ? property.value.uiVal
        : property.value.vt == VT_UI4 ? property.value.ulVal : 0;
    if (value < 1 || value > 8) return SWU_BOUNDED_IMAGE_INVALID_ORIENTATION;
    *orientation = value;
    return SWU_BOUNDED_IMAGE_OK;
}

} // namespace

static int32_t decodeBoundedImage(
    const uint8_t *encoded_bytes,
    uint32_t encoded_byte_count,
    uint32_t maximum_pixel_dimension,
    SWU_BoundedImageResult *result_out,
    bool mediaThumbnail
) {
    if (!result_out) return SWU_BOUNDED_IMAGE_INVALID_DATA;
    *result_out = {};
    if (encoded_byte_count > SWU_BOUNDED_IMAGE_MAX_ENCODED_BYTES) return SWU_BOUNDED_IMAGE_ENCODED_LIMIT;
    if (!encoded_bytes || encoded_byte_count == 0) return SWU_BOUNDED_IMAGE_INVALID_DATA;
    if (mediaThumbnail && (maximum_pixel_dimension == 0 || maximum_pixel_dimension > SWU_BOUNDED_IMAGE_MAX_DIMENSION)) {
        return SWU_BOUNDED_IMAGE_OUTPUT_LIMIT;
    }
    if (mediaThumbnail) {
        int32_t admission = admitContainer(encoded_bytes, encoded_byte_count);
        if (admission != SWU_BOUNDED_IMAGE_OK) return admission;
    }

    // A synchronous call stays on this thread. Balance both S_OK and S_FALSE;
    // an existing different apartment remains owned by its original caller.
    OwnedApartment apartment;
    if (FAILED(apartment.status) && apartment.status != RPC_E_CHANGED_MODE) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    OwnedInterface<IWICImagingFactory> factory;
    HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory.value));
    if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    OwnedInterface<IWICStream> stream;
    hr = factory.value->CreateStream(&stream.value);
    if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    // WIC's API is mutable, but this read-only decoder never writes the stream.
    hr = stream.value->InitializeFromMemory(const_cast<BYTE *>(encoded_bytes), encoded_byte_count);
    if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    OwnedInterface<IWICBitmapDecoder> decoder;
    hr = factory.value->CreateDecoderFromStream(stream.value, nullptr, WICDecodeMetadataCacheOnDemand, &decoder.value);
    if (FAILED(hr)) return SWU_BOUNDED_IMAGE_INVALID_DATA;
    GUID container{};
    hr = decoder.value->GetContainerFormat(&container);
    if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    bool jpeg = IsEqualGUID(container, GUID_ContainerFormatJpeg);
    if (mediaThumbnail && !jpeg && !IsEqualGUID(container, GUID_ContainerFormatPng) && !IsEqualGUID(container, GUID_ContainerFormatBmp)) {
        return SWU_BOUNDED_IMAGE_UNSUPPORTED_FORMAT;
    }
    UINT frames = 0;
    hr = decoder.value->GetFrameCount(&frames);
    if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    if (frames == 0 || (mediaThumbnail && frames != 1)) return SWU_BOUNDED_IMAGE_MULTIPLE_FRAMES;
    OwnedInterface<IWICBitmapFrameDecode> frame;
    hr = decoder.value->GetFrame(0, &frame.value);
    if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    UINT sourceWidth = 0, sourceHeight = 0;
    hr = frame.value->GetSize(&sourceWidth, &sourceHeight);
    if (FAILED(hr) || sourceWidth == 0 || sourceHeight == 0) return SWU_BOUNDED_IMAGE_INVALID_DATA;
    uint64_t sourcePixels = static_cast<uint64_t>(sourceWidth) * sourceHeight;
    if (sourcePixels > SWU_BOUNDED_IMAGE_MAX_SOURCE_PIXELS || sourceWidth > INT32_MAX || sourceHeight > INT32_MAX) {
        return SWU_BOUNDED_IMAGE_SOURCE_LIMIT;
    }

    uint32_t orientation = 1;
    if (mediaThumbnail && jpeg) {
        int32_t status = jpegOrientation(frame.value, &orientation);
        if (status != SWU_BOUNDED_IMAGE_OK) return status;
    }
    // PNG/BMP use raster order. JPEG explicitly applies EXIF 1...8. Separate
    // rotation and flip stages give orientations 5/7 an unambiguous order.
    WICBitmapTransformOptions rotation = WICBitmapTransformRotate0;
    WICBitmapTransformOptions flip = WICBitmapTransformRotate0;
    switch (orientation) {
        case 2: flip = WICBitmapTransformFlipHorizontal; break;
        case 3: rotation = WICBitmapTransformRotate180; break;
        case 4: flip = WICBitmapTransformFlipVertical; break;
        case 5: rotation = WICBitmapTransformRotate90; flip = WICBitmapTransformFlipHorizontal; break;
        case 6: rotation = WICBitmapTransformRotate90; break;
        case 7: rotation = WICBitmapTransformRotate90; flip = WICBitmapTransformFlipVertical; break;
        case 8: rotation = WICBitmapTransformRotate270; break;
        default: break;
    }
    IWICBitmapSource *source = frame.value;
    OwnedInterface<IWICBitmapFlipRotator> rotated;
    if (rotation != WICBitmapTransformRotate0) {
        hr = factory.value->CreateBitmapFlipRotator(&rotated.value);
        if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
        hr = rotated.value->Initialize(source, rotation);
        if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
        source = rotated.value;
    }
    OwnedInterface<IWICBitmapFlipRotator> flipped;
    if (flip != WICBitmapTransformRotate0) {
        hr = factory.value->CreateBitmapFlipRotator(&flipped.value);
        if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
        hr = flipped.value->Initialize(source, flip);
        if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
        source = flipped.value;
    }
    if (orientation >= 5) {
        UINT oldWidth = sourceWidth;
        sourceWidth = sourceHeight;
        sourceHeight = oldWidth;
    }

    UINT contextCount = 0;
    if (mediaThumbnail) {
        hr = frame.value->GetColorContexts(0, nullptr, &contextCount);
        if (hr == WINCODEC_ERR_UNSUPPORTEDOPERATION) contextCount = 0;
        else if (FAILED(hr)) return SWU_BOUNDED_IMAGE_COLOR_FAILED;
    }
    if (contextCount > 1) return SWU_BOUNDED_IMAGE_COLOR_FAILED;
    OwnedInterface<IWICColorContext> inputContext;
    OwnedInterface<IWICColorContext> outputContext;
    OwnedInterface<IWICColorTransform> colorTransform;
    if (contextCount == 1) {
        hr = factory.value->CreateColorContext(&inputContext.value);
        if (FAILED(hr)) return SWU_BOUNDED_IMAGE_COLOR_FAILED;
        UINT returnedCount = 0;
        hr = frame.value->GetColorContexts(1, &inputContext.value, &returnedCount);
        if (FAILED(hr) || returnedCount != 1) return SWU_BOUNDED_IMAGE_COLOR_FAILED;
        WICColorContextType contextType = WICColorContextUninitialized;
        hr = inputContext.value->GetType(&contextType);
        if (FAILED(hr) || contextType == WICColorContextUninitialized) return SWU_BOUNDED_IMAGE_COLOR_FAILED;
        hr = factory.value->CreateColorContext(&outputContext.value);
        if (FAILED(hr)) return SWU_BOUNDED_IMAGE_COLOR_FAILED;
        hr = outputContext.value->InitializeFromExifColorSpace(1); // sRGB
        if (FAILED(hr)) return SWU_BOUNDED_IMAGE_COLOR_FAILED;
        hr = factory.value->CreateColorTransformer(&colorTransform.value);
        if (FAILED(hr)) return SWU_BOUNDED_IMAGE_COLOR_FAILED;
        hr = colorTransform.value->Initialize(source, inputContext.value, outputContext.value, GUID_WICPixelFormat32bppBGRA);
        if (FAILED(hr)) return SWU_BOUNDED_IMAGE_COLOR_FAILED;
        source = colorTransform.value;
    }
    // No declared profile means sRGB. Convert alpha BEFORE scaling, so fully
    // transparent colors cannot bleed into an opaque thumbnail edge.
    OwnedInterface<IWICFormatConverter> converter;
    hr = factory.value->CreateFormatConverter(&converter.value);
    if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    hr = converter.value->Initialize(source,
        mediaThumbnail ? GUID_WICPixelFormat32bppPBGRA : GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone, nullptr, 0,
        WICBitmapPaletteTypeCustom);
    if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    source = converter.value;

    uint64_t width = sourceWidth, height = sourceHeight;
    if (mediaThumbnail && (width > maximum_pixel_dimension || height > maximum_pixel_dimension)) {
        if (width >= height) {
            height = (height * maximum_pixel_dimension + width / 2) / width;
            width = maximum_pixel_dimension;
        } else {
            width = (width * maximum_pixel_dimension + height / 2) / height;
            height = maximum_pixel_dimension;
        }
        if (width == 0) width = 1;
        if (height == 0) height = 1;
    }
    // The admitted source pixel count bounds these 64-bit products in both
    // policies; explicitly admit every narrower pitch/allocation cast.
    uint64_t pitch = width * 4;
    uint64_t byteCount = pitch * height;
    if (width == 0 || height == 0
        || (mediaThumbnail && (width > maximum_pixel_dimension || height > maximum_pixel_dimension))
        || width > INT32_MAX || height > INT32_MAX || pitch > INT32_MAX || byteCount > UINT32_MAX
        || byteCount > SIZE_MAX || byteCount > SWU_BOUNDED_IMAGE_MAX_DECODED_BYTES
        || (mediaThumbnail && byteCount > 4ULL * SWU_BOUNDED_IMAGE_MAX_DIMENSION * SWU_BOUNDED_IMAGE_MAX_DIMENSION)) {
        return SWU_BOUNDED_IMAGE_OUTPUT_LIMIT;
    }
    OwnedInterface<IWICBitmapScaler> scaler;
    if (width != sourceWidth || height != sourceHeight) {
        hr = factory.value->CreateBitmapScaler(&scaler.value);
        if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
        hr = scaler.value->Initialize(source, static_cast<UINT>(width), static_cast<UINT>(height), WICBitmapInterpolationModeFant);
        if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
        source = scaler.value;
    }
    OwnedPixels pixels;
    pixels.value = malloc(static_cast<size_t>(byteCount));
    if (!pixels.value) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    hr = source->CopyPixels(nullptr, static_cast<UINT>(pitch), static_cast<UINT>(byteCount), static_cast<BYTE *>(pixels.value));
    if (FAILED(hr)) return SWU_BOUNDED_IMAGE_DECODE_FAILED;
    result_out->pixels = pixels.value;
    result_out->width = static_cast<int32_t>(width);
    result_out->height = static_cast<int32_t>(height);
    result_out->bytes_per_row = static_cast<int32_t>(pitch);
    result_out->source_width = static_cast<int32_t>(sourceWidth);
    result_out->source_height = static_cast<int32_t>(sourceHeight);
    pixels.value = nullptr;
    return SWU_BOUNDED_IMAGE_OK;
}

extern "C" int32_t SWU_DecodeBoundedImage(
    const uint8_t *encoded_bytes,
    uint32_t encoded_byte_count,
    uint32_t maximum_pixel_dimension,
    SWU_BoundedImageResult *result_out
) {
    return decodeBoundedImage(encoded_bytes, encoded_byte_count, maximum_pixel_dimension, result_out, true);
}

extern "C" int32_t SWU_DecodeBoundedImageFirstFrame(
    const uint8_t *encoded_bytes,
    uint32_t encoded_byte_count,
    SWU_BoundedImageResult *result_out
) {
    return decodeBoundedImage(encoded_bytes, encoded_byte_count, 0, result_out, false);
}
