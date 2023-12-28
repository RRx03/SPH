#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"

#define PI M_PI_F

using namespace metal;

float Poly6(float r, float h)
{
    float A = 315 / (64 * PI * pow(abs(h), 9));
    float v = h * h - r * r;
    return (v * v * v * A) * (r < h);
}
float3 GPoly6(float3 r, float h)
{
    float B = 945 / (32 * PI * pow(abs(h), 9));
    float v = h * h - pow(length(r), 2);
    return (- r * v * v *  B) * float3(r < h);
}
float LPoly6(float r, float h)
{
    float C = 945 / (32 * PI * pow(abs(h), 9));
    float v = h * h - r * r;
    float w = (3*h*h - 7*r*r);
    return (- C * v * w) * (r < h);
}

float Spiky(float r, float h)
{
    float A = 15 / (PI * pow(abs(h), 6));
    float v = h - r;
    return (v * v * v * A) * (r < h);
}

float3 GSpiky(float3 r, float h)
{
    float B = 45 / (PI * pow(abs(h), 6));
    float rNorm = length(r);
    float v = h - rNorm;
    return (- B * (r/rNorm) * v *v ) * float3(r < h);
}

float LSpiky(float r, float h)
{
    float C = 90 / (PI * pow(abs(h), 6));
    float v = h - r;
    return (- C * v * (h - 2 * r) / r) * (r < h);
}

float Viscosity(float r, float h)
{
    float A = 15 / (2 * PI * pow(abs(h), 3));
    float a = - pow(r / h, 3) / 2;
    float b = pow(r / h, 2);
    float c = h / (2 * r) - 1;
    return A*(a+b+c) * (r < h);
}

float3 GViscosity(float3 r, float h)
{
    float B = 15 / (2 * PI * pow(abs(h), 3));
    float rNorm = length(r);
    float a = - 3 * rNorm / (pow(h, 3) * 2);
    float b = 2 / (h * h);
    float c = - h / (2 * pow(rNorm, 3));
    return - B * r * (a+b+c) * float3(r < h);
}

float LViscosity(float r, float h)
{
    float C = 45 / (2*PI * pow(abs(h), 6));
    float v = h - r;
    return - C * v * (r < h);
}






float CalculatePressure(float density, float desiredDensity, float gamma = 7.0f)
{
    //gamme = 7 for molten metal
    float cs = 343;
    return (pow(density / desiredDensity, gamma) - 1) * (pow(cs, 2) * desiredDensity / gamma);

}
float OldCalculatePressure(float density, float desiredDensity, float K)
{
    return K * (density - desiredDensity);

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

float3 CalculatePressureVisualization(float pressure, float MAX, float MIN, float threshold)
{
    float OverThreshold = (pressure > threshold);
    float UnderThreshold = (pressure < -threshold);
    float A = (pressure-threshold) / MAX * OverThreshold;
    float B = (pressure+threshold) / MIN * UnderThreshold;
    float C = abs(abs(pressure)-threshold)/threshold * (!OverThreshold) * (!UnderThreshold);
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