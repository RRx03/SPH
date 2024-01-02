#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"

#define PI M_PI_F

using namespace metal;

float SmoothingKernelPoly6(float dst, float radius)
{
	if (dst < radius)
	{
		float scale = 315 / (64 * PI * pow(abs(radius), 9));
		float v = radius * radius - dst * dst;
		return v * v * v * scale;
	}
	return 0;
}

float SpikyKernelPow3(float dst, float radius)
{
	if (dst < radius)
	{
		float scale = 15 / (PI * pow(radius, 6));
		float v = radius - dst;
		return v * v * v * scale;
	}
	return 0;
}

float SpikyKernelPow2(float dst, float radius)
{
	if (dst < radius)
	{
		float scale = 15 / (2 * PI * pow(radius, 5));
		float v = radius - dst;
		return v * v * scale;
	}
	return 0;
}

float DerivativeSpikyPow3(float dst, float radius)
{
	if (dst <= radius)
	{
		float scale = 45 / (pow(radius, 6) * PI);
		float v = radius - dst;
		return -v * v * scale;
	}
	return 0;
}

float DerivativeSpikyPow2(float dst, float radius)
{
	if (dst <= radius)
	{
		float scale = 15 / (pow(radius, 5) * PI);
		float v = radius - dst;
		return -v * scale;
	}
	return 0;
}

float DensityKernel(float dst, float radius)
{
	return SpikyKernelPow2(dst, radius);
}

float NearDensityKernel(float dst, float radius)
{
	return SpikyKernelPow3(dst, radius);
}

float DensityDerivative(float dst, float radius)
{
	return DerivativeSpikyPow2(dst, radius);
}

float NearDensityDerivative(float dst, float radius)
{
	return DerivativeSpikyPow3(dst, radius);
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
    float A = (pressure-threshold) / (MAX+0.0001*(MAX==0)) * OverThreshold;
    float B = (pressure+threshold) / (MIN-0.0001*(MIN==0)) * UnderThreshold;
    float C = abs(abs(pressure)-threshold)/threshold * (!OverThreshold) * (!UnderThreshold);
    return float3(A, C, B);
}


float3 CalculateSpeedVisualization(float vel, float MAX, float threshold)
{
    float3 COLORS[3] = {float3(0, 0, 1), float3(0, 1, 0), float3(1, 0, 0)};
    
    float MIDDLEPOINT = (MAX + threshold) / 2 ;
    float UnderCondition = (vel < MIDDLEPOINT);
    float OverCondition = (vel > MIDDLEPOINT);
    float distFromMiddleNormalized = abs(vel - MIDDLEPOINT)/MIDDLEPOINT;
    return distFromMiddleNormalized*COLORS[0] * UnderCondition + distFromMiddleNormalized*COLORS[2] * OverCondition + (1-distFromMiddleNormalized)*COLORS[1];
    
    

    
}