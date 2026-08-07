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
