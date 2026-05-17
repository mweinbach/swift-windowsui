// swift-format-ignore-file
// HLSL shader source lives in raw string literals; swift-format mangles their
// required indentation, so this file opts out of lint/format entirely.

// MARK: - Instanced Quad Shader (StructuredBuffer at t0, cbuffer at b0)

let batchQuadShaderSource = #"""
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
};

StructuredBuffer<QuadInstance> instances : register(t0);

struct VSOutput
{
    float4 position : SV_Position;
    float2 localPosition : TEXCOORD0;
    float2 size : TEXCOORD1;
    float radius : TEXCOORD2;
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
    float2 pixelPosition = rectOrigin + unit * rectSize;
    float2 clipPosition = float2(
        (pixelPosition.x / surfaceSize.x) * 2.0 - 1.0,
        1.0 - (pixelPosition.y / surfaceSize.y) * 2.0
    );

    VSOutput output;
    output.position = float4(clipPosition, 0.0, 1.0);
    output.localPosition = unit * rectSize;
    output.size = rectSize;
    output.radius = inst.cornerRadius;
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

float roundedRectDistance(float2 localPosition, float2 size, float radius)
{
    float2 halfSize = size * 0.5;
    float2 localPoint = localPosition - halfSize;
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
            float clipDistance = roundedRectDistance(clipLocalPosition, input.clipRect.zw, input.clipRadius);
            float clipAA = max(fwidth(clipDistance), 0.75);
            clipAlpha = saturate(0.5 - clipDistance / clipAA);
            if (clipAlpha <= 0.0)
            {
                discard;
            }
        }
    }

    float distance = roundedRectDistance(input.localPosition, input.size, input.radius);
    float aa = max(fwidth(distance), 0.75);
    // Soft edge falloff when blurRadius is active (GPU approximation)
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

    float4 sampleColor = imageTexture.Sample(imageSampler, input.uv);
    sampleColor *= input.opacity;
    return sampleColor;
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
