// Overlay/Shaders.metal
#include <metal_stdlib>
using namespace metal;

struct MaskParams {
    float peakingThreshold;
    float zebraThreshold;
    uint peakingEnabled;
    uint zebraEnabled;
};

static float luma(float3 rgb) {
    return dot(rgb, float3(0.2126, 0.7152, 0.0722));
}

kernel void histogramKernel(texture2d<float, access::read> input [[texture(0)]],
                            device atomic_uint *bins [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) return;
    float4 color = input.read(gid);   // BGRA texture reads as .bgra → color.rgb is RGB
    uint r = min(uint(color.r * 63.999f), 63u);
    uint g = min(uint(color.g * 63.999f), 63u);
    uint b = min(uint(color.b * 63.999f), 63u);
    atomic_fetch_add_explicit(&bins[r], 1u, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[64 + g], 1u, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[128 + b], 1u, memory_order_relaxed);
}

kernel void maskKernel(texture2d<float, access::read> input [[texture(0)]],
                       texture2d<float, access::write> output [[texture(1)]],
                       constant MaskParams &params [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    uint width = input.get_width();
    uint height = input.get_height();
    if (gid.x >= width || gid.y >= height) return;

    float y = luma(input.read(gid).rgb);
    float peaking = 0.0;
    float zebra = 0.0;

    if (params.zebraEnabled && y > params.zebraThreshold) {
        zebra = 1.0;
    }

    if (params.peakingEnabled && gid.x > 0 && gid.y > 0 &&
        gid.x < width - 1 && gid.y < height - 1) {
        float tl = luma(input.read(uint2(gid.x - 1, gid.y - 1)).rgb);
        float t  = luma(input.read(uint2(gid.x,     gid.y - 1)).rgb);
        float tr = luma(input.read(uint2(gid.x + 1, gid.y - 1)).rgb);
        float l  = luma(input.read(uint2(gid.x - 1, gid.y)).rgb);
        float r  = luma(input.read(uint2(gid.x + 1, gid.y)).rgb);
        float bl = luma(input.read(uint2(gid.x - 1, gid.y + 1)).rgb);
        float b  = luma(input.read(uint2(gid.x,     gid.y + 1)).rgb);
        float br = luma(input.read(uint2(gid.x + 1, gid.y + 1)).rgb);
        float gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
        float gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
        if (sqrt(gx * gx + gy * gy) > params.peakingThreshold) {
            peaking = 1.0;
        }
    }

    output.write(float4(peaking, zebra, 0.0, max(peaking, zebra)), gid);
}

kernel void waveformAccumulate(texture2d<float, access::read> source [[texture(0)]],
                               texture2d<uint, access::read_write> waveform [[texture(1)]],
                               uint2 gid [[thread_position_in_grid]]) {
    // One thread per OUTPUT column (gid.x in 0..<128); walks a row stripe.
    if (gid.x >= 128 || gid.y != 0) { return; }
    uint width = source.get_width();
    uint height = source.get_height();
    uint x0 = gid.x * width / 128;
    uint x1 = (gid.x + 1) * width / 128;
    // zero this column first
    for (uint row = 0; row < 64; row++) {
        waveform.write(uint4(0), uint2(gid.x, row));
    }
    for (uint x = x0; x < x1; x++) {
        for (uint y = 0; y < height; y += 4) {   // stride 4 rows: enough samples, 4x cheaper
            float4 c = source.read(uint2(x, y));
            float luma = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
            uint row = 63 - min(uint(luma * 63.0), 63u);   // bright at top (row 0)
            uint current = waveform.read(uint2(gid.x, row)).r;
            waveform.write(uint4(current + 1, 0, 0, 0), uint2(gid.x, row));
    	}
    }
}

struct OverlayVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex OverlayVertexOut overlayVertex(uint vid [[vertex_id]]) {
    // Fullscreen triangle
    float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    OverlayVertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv = positions[vid] * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

using VertexOut = OverlayVertexOut;

fragment float4 waveformFragment(VertexOut in [[stage_in]],
                                 texture2d<uint, access::read> waveform [[texture(0)]]) {
    uint2 coord = uint2(min(uint(in.uv.x * 128.0), 127u), min(uint(in.uv.y * 64.0), 63u));
    uint count = waveform.read(coord).r;
    float knee = 8.0;
    float alpha = min(1.0, float(count) / knee);
    float3 accent = float3(0.29, 0.87, 0.50);
    float3 ground = float3(0.03, 0.04, 0.035);
    return float4(mix(ground, accent, alpha), 1.0);
}

fragment float4 loupeFragment(OverlayVertexOut in [[stage_in]],
                              texture2d<float, access::read> loupe [[texture(0)]]) {
    uint side = loupe.get_width();
    uint2 coord = uint2(min(uint(in.uv.x * float(side)), side - 1),
                        min(uint(in.uv.y * float(side)), side - 1));
    float4 c = loupe.read(coord);
    return float4(c.rgb, 1.0);
}

fragment float4 overlayFragment(OverlayVertexOut in [[stage_in]],
                                texture2d<float, access::sample> mask [[texture(0)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);
    float4 m = mask.sample(s, in.uv);
    // Peaking: accent green #4ADE80
    float3 color = float3(0.0);
    float alpha = 0.0;
    if (m.r > 0.5) {
        color = float3(0.29, 0.87, 0.50);
        alpha = 0.9;
    } else if (m.g > 0.5) {
        // Zebra: dark diagonal stripes, 8px pitch — must stay visible on blown-out
        // (white) highlights, so the stripes are black, not white
        float stripe = fmod(in.position.x + in.position.y, 16.0);
        if (stripe < 8.0) {
            color = float3(0.0);
            alpha = 0.6;
        }
    }
    return float4(color * alpha, alpha);   // premultiplied
}
