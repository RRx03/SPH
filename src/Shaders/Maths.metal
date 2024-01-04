
#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"

#define PI M_PI_F

using namespace metal;


constexpr float Q_rsqrt(float number)
{
    float const y = as_type<float>(0x5f3759df - (as_type<uint32_t>(number) >> 1));
    return y * (1.5f - (number * 0.5f * y * y));
}

float random(thread uint *state)
{
    *state = (*state * 92837111) ^ (*state * 689287499) ^ (*state * 283923481);
    return float(uint(*state) % 4294967295) / 4294967295.0;
}

float4x4 translationMatrix(float3 translation)
{
    return float4x4(float4(1.0, 0.0, 0., 0.), float4(0., 1., 0., 0.), float4(0., 0., 1., 0.),
                    float4(translation.x, translation.y, translation.z, 1.));
}

float4x4 projectionMatrixV2(float FOV, float aspect, float near, float far)
{
    float yScale = 1.0 / tan(FOV * 0.5);
    float xScale = yScale / aspect;
    float zRange = far - near;
    float zScale = -(far + near) / zRange;
    float wzScale = -2.0 * far * near / zRange;
    return float4x4(float4(xScale, 0.0, 0.0, 0.0), float4(0.0, yScale, 0.0, 0.0), float4(0.0, 0.0, zScale, -1.0),
                    float4(0.0, 0.0, wzScale, 0.0));
}
int3 CELL_COORDS(float3 pos, float CELL_SIZE)
{
    return int3(pos / CELL_SIZE) - int3(pos.x < 0, pos.y < 0, pos.z < 0);
}

uint NEW_HASH_NORMALIZED(int3 pos, uint m)
{
    uint c = ((pos.x*73856093)^(pos.y*19349663)^(pos.z*83492791))%m;
    return c;
}


constant const int3 NEIGHBOURS[27] = {
    int3(-1, -1, -1), int3(0, -1, -1), int3(1, -1, -1), int3(-1, -1, 0), int3(0, -1, 0), int3(1, -1, 0),
    int3(-1, -1, 1),  int3(0, -1, 1),  int3(1, -1, 1),  int3(-1, 0, -1), int3(0, 0, -1), int3(1, 0, -1),
    int3(-1, 0, 0),   int3(0, 0, 0),   int3(1, 0, 0),   int3(-1, 0, 1),  int3(0, 0, 1),  int3(1, 0, 1),
    int3(-1, 1, -1),  int3(0, 1, -1),  int3(1, 1, -1),  int3(-1, 1, 0),  int3(0, 1, 0),  int3(1, 1, 0),
    int3(-1, 1, 1),   int3(0, 1, 1),   int3(1, 1, 1),
};