// swift-format-ignore-file
// HLSL shader source lives in raw string literals; swift-format mangles their
// required indentation, so this file opts out of lint/format entirely.

// MARK: - Instanced Quad Shader (StructuredBuffer at t0, cbuffer at b0)

// Shared prefix for every quad-family shader: frame uniforms, the
// QuadInstance structured-buffer layout, the instanced vertex shader,
// and the rounded-rect / color-effect helpers. The plain quad pixel
// shader and the material backdrop-composite pixel shader differ only
// in their psMain, so both concatenate this prefix to guarantee the
// vertex stage and instance layout stay in lockstep.
private let batchQuadShaderSharedSource = #"""
cbuffer FrameUniforms : register(b0)
{
    float2 surfaceSize;
    float2 _pad0;
};

struct QuadInstance
{
    float x, y, width, height;
    float cornerRadius;
    float startR, startG, startB;
    float startA;
    float endR, endG, endB;
    float endA;
    float gradientAxis;
    float clipX, clipY;
    float clipWidth, clipHeight;
    float effectType;
    float effectIntensity;
    float blurRadius;
    float blurOpaque;
    float effectParam1;
    float effectParam2;
    float effectParam3;
    float effectParam4;
    float clipCornerRadius;
    float blendMode;
    float rotationRadians;
    float cornerRadiusTopLeft;
    float cornerRadiusTopRight;
    float cornerRadiusBottomRight;
    float cornerRadiusBottomLeft;
    // 12 bytes of padding so structured-buffer stride stays 144 (multi
    // of 16). HLSL requires 16-byte element alignment.
    float _reserved0;
    float _reserved1;
    float _reserved2;
};

StructuredBuffer<QuadInstance> instances : register(t0);

struct VSOutput
{
    float4 position : SV_Position;
    float2 localPosition : TEXCOORD0;
    float2 size : TEXCOORD1;
    float4 cornerRadii : TEXCOORD2;
    float gradientAxis : TEXCOORD3;
    float4 startColor : COLOR0;
    float4 endColor : COLOR1;
    float4 clipRect : TEXCOORD4;
    float2 pixelPosition : TEXCOORD5;
    float effectType : TEXCOORD6;
    float effectIntensity : TEXCOORD7;
    float blurRadius : TEXCOORD8;
    float blurOpaque : TEXCOORD9;
    float effectParam1 : TEXCOORD10;
    float effectParam2 : TEXCOORD11;
    float effectParam3 : TEXCOORD12;
    float effectParam4 : TEXCOORD13;
    float clipRadius : TEXCOORD14;
};

VSOutput vsMain(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID)
{
    const float2 quad[6] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(0.0, 1.0),
        float2(1.0, 0.0),
        float2(1.0, 1.0)
    };

    QuadInstance inst = instances[instanceID];
    float2 unit = quad[vertexID];
    float2 rectOrigin = float2(inst.x, inst.y);
    float2 rectSize = float2(inst.width, inst.height);
    // Rotation: each vertex centred around the quad's middle, rotated by
    // inst.rotationRadians, then re-translated. Local coordinates passed
    // to the pixel shader stay unrotated so corner radius / gradient
    // math still applies to the un-rotated rect.
    float2 worldPosition;
    if (inst.rotationRadians == 0.0)
    {
        worldPosition = rectOrigin + unit * rectSize;
    }
    else
    {
        float2 centre = rectOrigin + rectSize * 0.5;
        float2 fromCentre = unit * rectSize - rectSize * 0.5;
        float cosR = cos(inst.rotationRadians);
        float sinR = sin(inst.rotationRadians);
        float2 rotated = float2(
            cosR * fromCentre.x - sinR * fromCentre.y,
            sinR * fromCentre.x + cosR * fromCentre.y
        );
        worldPosition = centre + rotated;
    }
    float2 pixelPosition = worldPosition;
    float2 clipPosition = float2(
        (pixelPosition.x / surfaceSize.x) * 2.0 - 1.0,
        1.0 - (pixelPosition.y / surfaceSize.y) * 2.0
    );

    VSOutput output;
    output.position = float4(clipPosition, 0.0, 1.0);
    output.localPosition = unit * rectSize;
    output.size = rectSize;
    // Per-corner radii (x=topLeft, y=topRight, z=bottomRight,
    // w=bottomLeft). When the primitive carries no per-corner values
    // (all zero) the uniform cornerRadius is broadcast, which preserves
    // the historic uniform-rounded-rect behaviour bit-for-bit. This
    // mirrors QuadPrimitive.usesPerCornerRadii on the CPU side.
    float4 cornerRadii = float4(
        inst.cornerRadiusTopLeft,
        inst.cornerRadiusTopRight,
        inst.cornerRadiusBottomRight,
        inst.cornerRadiusBottomLeft
    );
    if (cornerRadii.x <= 0.0 && cornerRadii.y <= 0.0 && cornerRadii.z <= 0.0 && cornerRadii.w <= 0.0)
    {
        cornerRadii = float4(inst.cornerRadius, inst.cornerRadius, inst.cornerRadius, inst.cornerRadius);
    }
    output.cornerRadii = cornerRadii;
    output.gradientAxis = inst.gradientAxis;
    output.startColor = float4(inst.startR, inst.startG, inst.startB, inst.startA);
    output.endColor = float4(inst.endR, inst.endG, inst.endB, inst.endA);
    output.clipRect = float4(inst.clipX, inst.clipY, inst.clipWidth, inst.clipHeight);
    output.pixelPosition = pixelPosition;
    output.effectType = inst.effectType;
    output.effectIntensity = inst.effectIntensity;
    output.blurRadius = inst.blurRadius;
    output.blurOpaque = inst.blurOpaque;
    output.effectParam1 = inst.effectParam1;
    output.effectParam2 = inst.effectParam2;
    output.effectParam3 = inst.effectParam3;
    output.effectParam4 = inst.effectParam4;
    output.clipRadius = inst.clipCornerRadius;
    return output;
}

float roundedRectDistance(float2 localPosition, float2 size, float4 cornerRadii)
{
    float2 halfSize = size * 0.5;
    float2 localPoint = localPosition - halfSize;
    // cornerRadii: x=topLeft, y=topRight, z=bottomRight, w=bottomLeft in
    // y-down pixel space. Select the radius of the quadrant the sample
    // falls into, splitting along the rect's centrelines. The CPU
    // rasterizer's roundedRectCoverage uses the same rule so both
    // backends agree on the shape boundary.
    float radius = localPoint.x > 0.0
        ? (localPoint.y > 0.0 ? cornerRadii.z : cornerRadii.y)
        : (localPoint.y > 0.0 ? cornerRadii.w : cornerRadii.x);
    float clampedRadius = min(radius, min(halfSize.x, halfSize.y));
    float2 corner = max(halfSize - float2(clampedRadius, clampedRadius), float2(0.0, 0.0));
    float2 delta = abs(localPoint) - corner;
    return length(max(delta, float2(0.0, 0.0))) + min(max(delta.x, delta.y), 0.0) - clampedRadius;
}

float3 applyColorEffect(float3 rgb, float effectType, float intensity, float param1, float param2, float param3, float param4)
{
    // 0 = none
    if (effectType < 0.5) return rgb;

    // 1 = brightness
    if (effectType < 1.5) return rgb + intensity;

    // 2 = contrast
    if (effectType < 2.5) return (rgb - 0.5) * (1.0 + intensity) + 0.5;

    // 3 = saturation
    if (effectType < 3.5)
    {
        float lum = dot(rgb, float3(0.299, 0.587, 0.114));
        return lerp(float3(lum, lum, lum), rgb, 1.0 + intensity);
    }

    // 4 = grayscale
    if (effectType < 4.5)
    {
        float lum = dot(rgb, float3(0.299, 0.587, 0.114));
        return lerp(rgb, float3(lum, lum, lum), intensity);
    }

    // 5 = colorInvert
    if (effectType < 5.5) return 1.0 - rgb;

    // 6 = hueRotation
    if (effectType < 6.5)
    {
        float cosA = cos(param1);
        float sinA = sin(param1);
        float3x3 rot = float3x3(
            float3(0.299 + 0.701 * cosA + 0.168 * sinA, 0.587 - 0.587 * cosA + 0.330 * sinA, 0.114 - 0.114 * cosA - 0.497 * sinA),
            float3(0.299 - 0.299 * cosA - 0.328 * sinA, 0.587 + 0.413 * cosA + 0.035 * sinA, 0.114 - 0.114 * cosA + 0.292 * sinA),
            float3(0.299 - 0.300 * cosA + 1.250 * sinA, 0.587 - 0.588 * cosA - 1.050 * sinA, 0.114 + 0.886 * cosA - 0.203 * sinA)
        );
        return mul(rot, rgb);
    }

    // 7 = colorMultiply
    if (effectType < 7.5) return rgb * float3(param1, param2, param3);

    return rgb;
}
"""#

let batchQuadShaderSource = batchQuadShaderSharedSource + "\n" + #"""
float4 psMain(VSOutput input) : SV_Target
{
    float clipAlpha = 1.0;

    // Per-pixel clip check: if clip rect has positive dimensions, discard outside it
    if (input.clipRect.z > 0.0 && input.clipRect.w > 0.0)
    {
        if (input.pixelPosition.x < input.clipRect.x || input.pixelPosition.y < input.clipRect.y ||
            input.pixelPosition.x > input.clipRect.x + input.clipRect.z ||
            input.pixelPosition.y > input.clipRect.y + input.clipRect.w)
        {
            discard;
        }

        if (input.clipRadius > 0.0)
        {
            float2 clipLocalPosition = input.pixelPosition - input.clipRect.xy;
            // Clip corners stay uniform (clipCornerRadius is a single
            // float); only the quad body supports per-corner radii.
            float clipDistance = roundedRectDistance(
                clipLocalPosition, input.clipRect.zw,
                float4(input.clipRadius, input.clipRadius, input.clipRadius, input.clipRadius));
            float clipAA = max(fwidth(clipDistance), 0.75);
            clipAlpha = saturate(0.5 - clipDistance / clipAA);
            if (clipAlpha <= 0.0)
            {
                discard;
            }
        }
    }

    float distance = roundedRectDistance(input.localPosition, input.size, input.cornerRadii);
    float aa = max(fwidth(distance), 0.75);
    // NOTE (fallback only): on this plain batched path blurRadius merely
    // widens the quad's edge falloff. Material quads never reach this
    // shader — D3D11BatchRenderer.splitQuadRangeForBackdropBlur routes
    // every quad with blurRadius >= 1 through
    // D3D11BackdropBlurEngine, which blurs the real backdrop (separable
    // Gaussian over the scene-so-far, matching the CPU rasterizer) and
    // composites via batchMaterialQuadShaderSource. Rotated blur quads
    // blur the axis-aligned bounding box of the rotated footprint (the
    // same window the CPU rasterizer blurs), so they take the engine
    // path too. The edge-softening below remains only for sub-pixel
    // radii that truncate to zero.
    float blur = max(input.blurRadius, 0.0);
    float edgeSoftness = aa + blur * 2.0;
    float alpha = saturate(0.5 - distance / edgeSoftness);

    float gradientT = input.gradientAxis > 0.5
        ? saturate(input.localPosition.x / max(input.size.x, 1.0))
        : saturate(input.localPosition.y / max(input.size.y, 1.0));

    float4 color = lerp(input.startColor, input.endColor, gradientT);

    // 8 = luminanceToAlpha
    if (input.effectType > 7.5 && input.effectType < 8.5)
    {
        float lum = dot(color.rgb, float3(0.299, 0.587, 0.114));
        color.rgb = float3(lum, lum, lum);
        color.a = lum;
    }
    else
    {
        color.rgb = applyColorEffect(color.rgb, input.effectType, input.effectIntensity, input.effectParam1, input.effectParam2, input.effectParam3, input.effectParam4);
    }

    return float4(color.rgb * color.a * alpha * clipAlpha, color.a * alpha * clipAlpha);
}
"""#

// MARK: - Material Backdrop Composite Shader (StructuredBuffer t0, blurred backdrop t1)
//
// Same vertex stage and instance layout as the plain quad shader (shared
// prefix above); the pixel shader composites the quad's tint over the
// ALREADY-BLURRED backdrop instead of emitting the tint alone. The
// backdrop texture holds the blurred "scene so far" for the quad's
// region (produced by the separable blur pass below), sampled with
// screen-space UVs derived from the region cbuffer. This is the GPU
// counterpart of the CPU rasterizer's applyBoxBlur + tint: because the
// tint composite is affine in the backdrop and the Gaussian is linear,
// blur-then-tint and tint-then-blur agree for constant tints (and for
// the smooth gradients materials actually use), so both backends
// produce the same frosted-glass result.

let batchMaterialQuadShaderSource = batchQuadShaderSharedSource + "\n" + #"""
Texture2D backdropTexture : register(t1);
SamplerState backdropSampler : register(s0);

cbuffer BackdropRegion : register(b1)
{
    // xy = region origin in surface pixels, zw = size of the backdrop
    // TEXTURE in pixels (the texture may be larger than the region:
    // ping-pong targets grow-only, and the region always sits at the
    // texture's origin, so dividing by texture size lands the sample on
    // the right texel).
    float4 backdropRegion;
};

float4 psMain(VSOutput input) : SV_Target
{
    float clipAlpha = 1.0;

    // Per-pixel clip check: identical to the plain quad shader.
    if (input.clipRect.z > 0.0 && input.clipRect.w > 0.0)
    {
        if (input.pixelPosition.x < input.clipRect.x || input.pixelPosition.y < input.clipRect.y ||
            input.pixelPosition.x > input.clipRect.x + input.clipRect.z ||
            input.pixelPosition.y > input.clipRect.y + input.clipRect.w)
        {
            discard;
        }

        if (input.clipRadius > 0.0)
        {
            float2 clipLocalPosition = input.pixelPosition - input.clipRect.xy;
            float clipDistance = roundedRectDistance(
                clipLocalPosition, input.clipRect.zw,
                float4(input.clipRadius, input.clipRadius, input.clipRadius, input.clipRadius));
            float clipAA = max(fwidth(clipDistance), 0.75);
            clipAlpha = saturate(0.5 - clipDistance / clipAA);
            if (clipAlpha <= 0.0)
            {
                discard;
            }
        }
    }

    float distance = roundedRectDistance(input.localPosition, input.size, input.cornerRadii);
    float aa = max(fwidth(distance), 0.75);
    // The backdrop blur is real now (done before this draw), so the
    // coverage falloff is plain anti-aliasing — no blurRadius widening.
    float alpha = saturate(0.5 - distance / aa);

    float gradientT = input.gradientAxis > 0.5
        ? saturate(input.localPosition.x / max(input.size.x, 1.0))
        : saturate(input.localPosition.y / max(input.size.y, 1.0));

    float4 color = lerp(input.startColor, input.endColor, gradientT);

    // 8 = luminanceToAlpha
    if (input.effectType > 7.5 && input.effectType < 8.5)
    {
        float lum = dot(color.rgb, float3(0.299, 0.587, 0.114));
        color.rgb = float3(lum, lum, lum);
        color.a = lum;
    }
    else
    {
        color.rgb = applyColorEffect(color.rgb, input.effectType, input.effectIntensity, input.effectParam1, input.effectParam2, input.effectParam3, input.effectParam4);
    }

    // Sample the blurred backdrop at this pixel's screen position.
    // Pixels outside the region clamp to the region's edge texels.
    float2 uv = (input.pixelPosition - backdropRegion.xy) / backdropRegion.zw;
    float4 backdrop = backdropTexture.Sample(backdropSampler, uv);

    // Source-over composite of the tint over the blurred backdrop,
    // matching what the CPU rasterizer's in-place blur + blend yields.
    float3 composited = color.rgb * color.a + backdrop.rgb * (1.0 - color.a);
    float outA = input.blurOpaque > 0.5
        ? 1.0
        : color.a + backdrop.a * (1.0 - color.a);

    float coverage = alpha * clipAlpha;
    return float4(composited * coverage, outA * coverage);
}
"""#

// MARK: - Separable Gaussian Blur Shader (fullscreen triangle, source t0)
//
// One pass of the two-pass separable Gaussian used for Material backdrop
// blur. The batch renderer runs it horizontally into one offscreen
// target, then vertically back into the other. Weights come from the
// same gaussianBlurKernel(radius:) the CPU rasterizer uses (sigma =
// radius / 2), uploaded by the engine into the cbuffer below, so both
// backends share the exact kernel shape. Edge handling differs slightly:
// the CPU pass re-normalizes the truncated kernel at bounds edges while
// the GPU sampler clamps (edge-texel duplication) — visually equivalent
// for the soft materials these passes serve.

let batchBackdropBlurShaderSource = #"""
cbuffer BlurParams : register(b0)
{
    // xy = texel-space step direction ((1/width, 0) or (0, 1/height)) in
    // texture UV space, z = tap radius, w = unused.
    float4 blurDirection;
    // xy = region/texture UV scale (the ping-pong targets are grow-only,
    // so the region being blurred may be smaller than the texture),
    // zw = unused.
    float4 blurUVScale;
    // Symmetric Gaussian weights; blurWeights[0] is the centre tap and
    // taps ±i both use entry i. 33 float4s = 132 floats, so radii up to
    // 128 fit (materials top out at 40).
    float4 blurWeights[33];
};

Texture2D blurSource : register(t0);
SamplerState blurSampler : register(s0);

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

VSOutput vsMain(uint vertexID : SV_VertexID)
{
    // Single fullscreen triangle; no vertex buffers needed.
    float2 pos = float2((vertexID << 1) & 2, vertexID & 2);
    VSOutput output;
    output.position = float4(pos.x * 2.0 - 1.0, 1.0 - pos.y * 2.0, 0.0, 1.0);
    output.uv = pos;
    return output;
}

float blurWeightAt(int index)
{
    return blurWeights[index >> 2][index & 3];
}

float4 psMain(VSOutput input) : SV_Target
{
    int radius = (int)blurDirection.z;
    float2 uv = input.uv * blurUVScale.xy;
    float4 sum = blurSource.Sample(blurSampler, uv) * blurWeightAt(0);
    for (int i = 1; i <= radius; i++)
    {
        float weight = blurWeightAt(i);
        float2 offset = blurDirection.xy * (float)i;
        sum += blurSource.Sample(blurSampler, uv + offset) * weight;
        sum += blurSource.Sample(blurSampler, uv - offset) * weight;
    }
    return sum;
}
"""#

// MARK: - Instanced Image Shader (StructuredBuffer at t0, Texture2D at t1)

let batchImageShaderSource = #"""
cbuffer FrameUniforms : register(b0)
{
    float2 surfaceSize;
    float2 _pad0;
};

struct ImageInstance
{
    float screenX, screenY, screenW, screenH;
    float uvX, uvY, uvW, uvH;
    float opacity;
    float clipX, clipY, clipWidth;
    float clipHeight;
    int textureID;
    float pad1, pad2;
};

StructuredBuffer<ImageInstance> instances : register(t0);
Texture2D imageTexture : register(t1);
SamplerState imageSampler : register(s0);

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float opacity : TEXCOORD1;
    float4 clipRect : TEXCOORD2;
    float2 pixelPosition : TEXCOORD3;
};

VSOutput vsMain(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID)
{
    const float2 quad[6] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(0.0, 1.0),
        float2(1.0, 0.0),
        float2(1.0, 1.0)
    };

    ImageInstance inst = instances[instanceID];
    float2 unit = quad[vertexID];
    float2 screenOrigin = float2(inst.screenX, inst.screenY);
    float2 screenSize = float2(inst.screenW, inst.screenH);
    float2 pixelPosition = screenOrigin + unit * screenSize;
    float2 clipPosition = float2(
        (pixelPosition.x / surfaceSize.x) * 2.0 - 1.0,
        1.0 - (pixelPosition.y / surfaceSize.y) * 2.0
    );

    float2 uvOrigin = float2(inst.uvX, inst.uvY);
    float2 uvSize = float2(inst.uvW, inst.uvH);

    VSOutput output;
    output.position = float4(clipPosition, 0.0, 1.0);
    output.uv = uvOrigin + unit * uvSize;
    output.opacity = inst.opacity;
    output.clipRect = float4(inst.clipX, inst.clipY, inst.clipWidth, inst.clipHeight);
    output.pixelPosition = pixelPosition;
    return output;
}

float4 psMain(VSOutput input) : SV_Target
{
    // Per-pixel clip check
    if (input.clipRect.z > 0.0 && input.clipRect.w > 0.0)
    {
        if (input.pixelPosition.x < input.clipRect.x || input.pixelPosition.y < input.clipRect.y ||
            input.pixelPosition.x > input.clipRect.x + input.clipRect.z ||
            input.pixelPosition.y > input.clipRect.y + input.clipRect.w)
        {
            discard;
        }
    }

    // Image textures are uploaded premultiplied (BGRA8, see
    // `BitmapSurface.format` and `createImageTextureResource`). That is what
    // the ONE / INV_SRC_ALPHA blend state requires and what makes the
    // bilinear sampler correct at transparent edges. Scaling a
    // premultiplied colour by opacity scales RGB and A together, so the
    // result stays premultiplied.
    float4 sampleColor = imageTexture.Sample(imageSampler, input.uv);
    return sampleColor * input.opacity;
}
"""#

// MARK: - Instanced Shadow Shader (StructuredBuffer at t0)

let batchShadowShaderSource = #"""
cbuffer FrameUniforms : register(b0)
{
    float2 surfaceSize;
    float2 _pad0;
};

struct ShadowInstance
{
    float x, y, width, height;
    float cornerRadius;
    float colorR, colorG, colorB;
    float colorA;
    float blurRadius;
    float offsetX, offsetY;
    float clipX, clipY, clipWidth, clipHeight;
};

StructuredBuffer<ShadowInstance> instances : register(t0);

struct VSOutput
{
    float4 position : SV_Position;
    float2 localPosition : TEXCOORD0;
    float2 expandedSize : TEXCOORD1;
    float2 rectSize : TEXCOORD2;
    float radius : TEXCOORD3;
    float4 shadowColor : COLOR0;
    float blurRadius : TEXCOORD4;
    float4 clipRect : TEXCOORD5;
    float2 pixelPosition : TEXCOORD6;
};

VSOutput vsMain(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID)
{
    const float2 quad[6] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(0.0, 1.0),
        float2(1.0, 0.0),
        float2(1.0, 1.0)
    };

    ShadowInstance inst = instances[instanceID];
    float2 unit = quad[vertexID];

    // Expand rect by 2*blurRadius in each direction for soft falloff area
    float expand = inst.blurRadius * 2.0;
    float2 rectOrigin = float2(inst.x + inst.offsetX - expand, inst.y + inst.offsetY - expand);
    float2 expandedSize = float2(inst.width + expand * 2.0, inst.height + expand * 2.0);

    float2 pixelPosition = rectOrigin + unit * expandedSize;
    float2 clipPosition = float2(
        (pixelPosition.x / surfaceSize.x) * 2.0 - 1.0,
        1.0 - (pixelPosition.y / surfaceSize.y) * 2.0
    );

    VSOutput output;
    output.position = float4(clipPosition, 0.0, 1.0);
    output.localPosition = unit * expandedSize;
    output.expandedSize = expandedSize;
    output.rectSize = float2(inst.width, inst.height);
    output.radius = inst.cornerRadius;
    output.shadowColor = float4(inst.colorR, inst.colorG, inst.colorB, inst.colorA);
    output.blurRadius = inst.blurRadius;
    output.clipRect = float4(inst.clipX, inst.clipY, inst.clipWidth, inst.clipHeight);
    output.pixelPosition = pixelPosition;
    return output;
}

float roundedRectDistanceShadow(float2 localPosition, float2 size, float radius)
{
    float2 halfSize = size * 0.5;
    float2 localPoint = localPosition - halfSize;
    float clampedRadius = min(radius, min(halfSize.x, halfSize.y));
    float2 corner = max(halfSize - float2(clampedRadius, clampedRadius), float2(0.0, 0.0));
    float2 delta = abs(localPoint) - corner;
    return length(max(delta, float2(0.0, 0.0))) + min(max(delta.x, delta.y), 0.0) - clampedRadius;
}

float4 psMain(VSOutput input) : SV_Target
{
    if (input.clipRect.z > 0.0 && input.clipRect.w > 0.0)
    {
        if (input.pixelPosition.x < input.clipRect.x || input.pixelPosition.y < input.clipRect.y ||
            input.pixelPosition.x > input.clipRect.x + input.clipRect.z ||
            input.pixelPosition.y > input.clipRect.y + input.clipRect.w)
        {
            discard;
        }
    }

    // Map from expanded local coords back to the original rect's local coords
    float expand = input.blurRadius * 2.0;
    float2 rectLocal = input.localPosition - float2(expand, expand);

    float dist = roundedRectDistanceShadow(rectLocal, input.rectSize, input.radius);

    // smoothstep falloff based on blur radius
    float blur = max(input.blurRadius, 0.5);
    float alpha = 1.0 - smoothstep(-blur * 0.5, blur, dist);

    float4 color = input.shadowColor;
    return float4(color.rgb * color.a * alpha, color.a * alpha);
}
"""#
