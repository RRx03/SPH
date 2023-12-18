#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"

#define PI M_PI_F

using namespace metal;


float W(float d, float H)
{
    return max(0.0, 315 * pow((pow(H, 2) - pow(d, 2)), 3) / (64 * 3.14 * pow(H, 9)));
}
float dW(float d, float H)
{
    return (d < H) ? -945 * d * pow((pow(H, 2) - pow(d, 2)), 2) / (32 * 3.14 * pow(H, 9)) : 0;
}

float SmoothingKernelPoly6(float dst, float radius)
{
    float scale = 315 / (64 * PI * pow(abs(radius), 9));
    float v = radius * radius - dst * dst;
    return (v * v * v * scale) * (dst < radius);
}
float ViscosityKernel(float dst, float radius)
{
    if (dst <= radius) {
        return 15 / (2 * PI * pow(radius, 3)) *
               (-(dst * dst * dst) / (2 * radius * radius * radius) + (dst * dst) / (radius * radius) +
                radius / (2 * dst) - 1);
    }
    return 0;
}

float LaplacianViscosityK(float dst, float radius)
{
    if (dst <= radius) {
        return 45 / (PI *radius*radius*radius*radius*radius*radius) * (radius - dst);
    }
    return 0;
}
float DerivativeSmoothingKernelPoly6(float dst, float radius)
{
    float scale = -945 / (32 * PI * pow(abs(radius), 9));
    float v = radius * radius - dst * dst;
    return (v * v * scale * dst) * (dst < radius);
}

float SpikyKernelPow2(float dst, float radius)
{
    if (dst < radius) {
        float scale = 15 / (2 * PI * pow(radius, 5));
        float v = radius - dst;
        return v * v * scale;
    }
    return 0;
}

float DerivativeSpikyPow2(float dst, float radius)
{
    if (dst <= radius) {
        float scale = 15 / (pow(radius, 5) * PI);
        float v = radius - dst;
        return -v * scale;
    }
    return 0;
}

float SpikyKernelPow3(float dst, float radius)
{
    if (dst < radius) {
        float scale = 15 / (PI * pow(radius, 6));
        float v = radius - dst;
        return v * v * v * scale;
    }
    return 0;
}

float DerivativeSpikyPow3(float dst, float radius)
{
    if (dst <= radius) {
        float scale = (pow(radius, 2) + pow(dst, 2) - 2*dst*radius) * 45 / (powr(radius, 1) * PI);
        return - scale;
    }
    return 0;
}

float3 CalculateDensityVisualization(float density, float desiredDensity, float Ma, float Mi, float threshold)
{
    float MaxCond = (density > desiredDensity + threshold);
    float MinCond = (density < desiredDensity - threshold);
    float DRPLUSCond = (density >= desiredDensity);
    float DRMINUSCond = (density <= desiredDensity);
    float A = density / Ma * MaxCond;
    float B = Mi / density * MinCond;
    float C = (desiredDensity + threshold - density) / (threshold)*DRPLUSCond * (!MaxCond) +
              (density - desiredDensity + threshold) / (threshold)*DRMINUSCond * (!MinCond);
    return float3(A, C, B);
}

float3 CalculateSpeedVisualization(float v, float Ma, float Mi)
{
    float A = ((2 * v - Ma - Mi) / (Ma - Mi));
    float Acond = (v >= (Ma + Mi) / (2));
    float C = ((2 * v - 2 * Mi) / (Ma - Mi));
    float Ccond = (v <= (Ma + Mi) / 2);
    float B = (1 - A) * Acond + C * Ccond;
    return float3(A * Acond, B, (1 - C) * Ccond);
}