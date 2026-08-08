#include <metal_stdlib>
using namespace metal;

kernel void accumulateAverageKernel(texture2d<float, access::read> frame [[texture(0)]],
                                    texture2d<float, access::read_write> acc [[texture(1)]],
                                    constant uint &frameNumber [[buffer(0)]],
                                    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= frame.get_width() || gid.y >= frame.get_height()) return;
    float4 sample = frame.read(gid);
    if (frameNumber == 1) {
        acc.write(sample, gid);
    } else {
        float4 current = acc.read(gid);
        acc.write(current + (sample - current) / float(frameNumber), gid);
    }
}

kernel void accumulateMaxKernel(texture2d<float, access::read> frame [[texture(0)]],
                                texture2d<float, access::read_write> acc [[texture(1)]],
                                constant uint &frameNumber [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= frame.get_width() || gid.y >= frame.get_height()) return;
    float4 sample = frame.read(gid);
    if (frameNumber == 1) {
        acc.write(sample, gid);
    } else {
        acc.write(max(acc.read(gid), sample), gid);
    }
}

struct LongVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex LongVertexOut longVertex(uint vid [[vertex_id]]) {
    float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    LongVertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv = positions[vid] * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

fragment float4 accumulationFragment(LongVertexOut in [[stage_in]],
                                     texture2d<float, access::sample> acc [[texture(0)]]) {
    constexpr sampler s(mag_filter::nearest, min_filter::nearest);
    float4 color = acc.sample(s, in.uv);
    return float4(clamp(color.rgb, 0.0, 1.0), 1.0);
}
