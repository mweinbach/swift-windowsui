// swift-format-ignore-file
// Shared raw HLSL keeps the frame and batch image samplers identical.

/// Nonlegacy sampling uses a constant four premultiplied texel loads. Each
/// axis selects one source band; only a tiled center wraps its own taps.
/// Admission validates full UVs, positive bands, integer caps, and phase bounds
/// before these helpers reach a GPU. Mode zero keeps its existing Sample path.
let imageSamplingShaderSource = #"""
struct ImageSamplingAxisTaps
{
    int lower;
    int upper;
    float fraction;
};

int wrapImageSamplingTap(int index, int count)
{
    return ((index % count) + count) % count;
}

ImageSamplingAxisTaps imageSamplingAxis(
    float unitCoordinate, int sourceLength,
    float sourceLeadingCap, float sourceTrailingCap,
    float destinationLeadingCap, float destinationTrailingCap,
    float repeatCount, int samplingKind)
{
    int leadingCount = (int)floor(sourceLeadingCap * (float)sourceLength + 0.5);
    int trailingCount = (int)floor(sourceTrailingCap * (float)sourceLength + 0.5);
    int bandStart;
    int bandCount;
    float bandCoordinate;
    bool wraps = false;
    if (destinationLeadingCap > 0.0 && unitCoordinate < destinationLeadingCap)
    {
        bandStart = 0;
        bandCount = leadingCount;
        bandCoordinate = unitCoordinate / destinationLeadingCap;
    }
    else if (destinationTrailingCap > 0.0 && unitCoordinate >= 1.0 - destinationTrailingCap)
    {
        bandStart = sourceLength - trailingCount;
        bandCount = trailingCount;
        bandCoordinate = (unitCoordinate - (1.0 - destinationTrailingCap)) / destinationTrailingCap;
    }
    else
    {
        bandStart = leadingCount;
        bandCount = sourceLength - leadingCount - trailingCount;
        bandCoordinate = (unitCoordinate - destinationLeadingCap)
            / (1.0 - destinationLeadingCap - destinationTrailingCap);
        wraps = samplingKind == 2;
        if (wraps)
        {
            bandCoordinate = frac(bandCoordinate * repeatCount);
        }
    }

    float texel = bandCoordinate * (float)bandCount - 0.5;
    int lower = (int)floor(texel);
    int upper = lower + 1;
    ImageSamplingAxisTaps taps;
    taps.fraction = texel - floor(texel);
    taps.lower = bandStart + (wraps
        ? wrapImageSamplingTap(lower, bandCount) : clamp(lower, 0, bandCount - 1));
    taps.upper = bandStart + (wraps
        ? wrapImageSamplingTap(upper, bandCount) : clamp(upper, 0, bandCount - 1));
    return taps;
}

float4 sampleResizedImage(
    Texture2D<float4> sourceTexture, float2 unitCoordinate,
    float4 sourceCaps, float4 destinationCaps, float2 centerRepeats, int samplingKind)
{
    // An unknown kind must never fall back to whole-image stretching.
    if (samplingKind != 1 && samplingKind != 2)
    {
        return float4(0.0, 0.0, 0.0, 0.0);
    }
    uint sourceWidth, sourceHeight;
    sourceTexture.GetDimensions(sourceWidth, sourceHeight);
    ImageSamplingAxisTaps x = imageSamplingAxis(
        unitCoordinate.x, (int)sourceWidth, sourceCaps.x, sourceCaps.z,
        destinationCaps.x, destinationCaps.z, centerRepeats.x, samplingKind);
    ImageSamplingAxisTaps y = imageSamplingAxis(
        unitCoordinate.y, (int)sourceHeight, sourceCaps.y, sourceCaps.w,
        destinationCaps.y, destinationCaps.w, centerRepeats.y, samplingKind);
    float4 top = lerp(
        sourceTexture.Load(int3(x.lower, y.lower, 0)),
        sourceTexture.Load(int3(x.upper, y.lower, 0)), x.fraction);
    float4 bottom = lerp(
        sourceTexture.Load(int3(x.lower, y.upper, 0)),
        sourceTexture.Load(int3(x.upper, y.upper, 0)), x.fraction);
    return lerp(top, bottom, y.fraction);
}
"""#
