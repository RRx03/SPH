#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"

#define PI M_PI_F

using namespace metal;


struct VertexIn {
    float4 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct RasterizerData {
    float4 position [[position]];
    float3 normal;
    float3 color;
};

constexpr float Q_rsqrt(float number)
{
    // static_assert(numeric_limits<float>::is_iec559, "Must Be IEEE754"); // (enable only on IEEE 754)
    float const y = as_type<float>(0x5f3759df - (as_type<uint32_t>(number) >> 1));
    return y * (1.5f - (number * 0.5f * y * y));
}

float random(thread uint *state)
{
    // uint offset = 8763982;
    //*state = *state * (*state + offset * 2) * (*state + offset * 3456) * (*state + 567890) + offset; //utilisation de
    // pointeurs pour modifier la valeur de d'état return *state / 4294967295.0; // 2^32 - 1 = 4294967295 afin de
    // renvoyer un nombre entre 0 et 1

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
uint HASH(int3 CELL_COORDS, uint tableSize)
{
    int h = (CELL_COORDS.x * 92837111 + 653789820) ^ (CELL_COORDS.y * 689287499 + 653789820) ^
            (CELL_COORDS.z * 283923481 + 653789820);
    return uint(abs(h) % tableSize);
}
uint SECOND_HASH(int3 CELL_COORDS, uint tableSize)
{
    int h = (CELL_COORDS.x * 92837111 + 653789820) ^ (CELL_COORDS.y * 689287499 + 653789820) ^
            (CELL_COORDS.z * 283923481 + 653789820);
    uint randomState = abs(h);

    return uint(randomState * tableSize);
}
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
        float scale = 45 / (pow(radius, 6) * PI);
        float v = radius - dst;
        return -v * v * scale;
    }
    return 0;
}

float CalculateProperty(float property, float density, float mass, float dist, float H)
{
    return property * mass * SmoothingKernelPoly6(dist, H) / density;
}

float3 CalculateGradientProperty(float fatherProperty,
                                 float property,
                                 float density,
                                 float mass,
                                 float dist,
                                 float H,
                                 float3 dir)
{
    return (property - fatherProperty) * mass * DerivativeSmoothingKernelPoly6(dist, H) / density * (-dir);
}

float3 CalculateGradientProperty2(float fatherProperty,
                                  float property,
                                  float fatherDensity,
                                  float density,
                                  float mass,
                                  float dist,
                                  float H,
                                  float3 dir)
{
    return fatherDensity * mass * (fatherProperty / pow(fatherDensity, 2) + property / pow(density, 2)) *
           DerivativeSmoothingKernelPoly6(dist, H) * (-dir);
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

constant const int3 NEIGHBOURS[27] = {
    int3(-1, -1, -1), int3(0, -1, -1), int3(1, -1, -1), int3(-1, -1, 0), int3(0, -1, 0), int3(1, -1, 0),
    int3(-1, -1, 1),  int3(0, -1, 1),  int3(1, -1, 1),  int3(-1, 0, -1), int3(0, 0, -1), int3(1, 0, -1),
    int3(-1, 0, 0),   int3(0, 0, 0),   int3(1, 0, 0),   int3(-1, 0, 1),  int3(0, 0, 1),  int3(1, 0, 1),
    int3(-1, 1, -1),  int3(0, 1, -1),  int3(1, 1, -1),  int3(-1, 1, 0),  int3(0, 1, 0),  int3(1, 1, 0),
    int3(-1, 1, 1),   int3(0, 1, 1),   int3(1, 1, 1),
};


vertex RasterizerData vertexShader(const VertexIn vertices [[stage_in]],
                                   constant Particle *particles [[buffer(1)]],
                                   constant Uniform &uniform [[buffer(10)]],
                                   uint instance_id [[instance_id]])
{
    RasterizerData out;
    Particle particle = particles[instance_id];
    out.position = uniform.projectionMatrix * uniform.viewMatrix * translationMatrix(particle.position) *
                   float4(vertices.position.xyz, 1);
    out.color = particle.color;
    out.normal = vertices.normal;
    return out;
}

fragment float4 fragmentShader(RasterizerData in [[stage_in]])
{
    float3 LIGHT = float3(0, -1, -1) * Q_rsqrt(dot(float3(0, -1, 1), float3(0, -1, 1)));
    float ISO = max(0.1, dot(in.normal, -LIGHT));
    return float4(in.color * ISO, 1);
}


kernel void initParticles(device Particle *particles [[buffer(1)]],
                          constant Uniform &uniform [[buffer(10)]],
                          uint id [[thread_position_in_grid]])
{
    uint randomState = id;
    float3 position =
        float3(3 * (random(&randomState) - 0.5), random(&randomState) * 3 + 3, 3 * (random(&randomState) - 0.5));
    particles[id].position = position;
    particles[id].oldPosition = position;
    particles[id].nextPosition = position;
    particles[id].forces = float3(0, 0, 0);
    particles[id].velocity = float3(0, 0, 0);
    particles[id].acceleration = float3(0, 0, 0);
    particles[id].color = uniform.COLOR;
    particles[id].density = SmoothingKernelPoly6(0, uniform.H) * uniform.MASS;
    particles[id].nearDensity = particles[id].density;
    particles[id].pressure = uniform.GAZ_CONSTANT * (particles[id].density - uniform.REST_DENSITY);
    particles[id].nearPressure = particles[id].pressure;
}

kernel void CALCULATE_DENSITIES(device Particle *particles [[buffer(1)]],
                                constant uint *DENSE_TABLE [[buffer(3)]],
                                constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                                constant Uniform &uniform [[buffer(10)]],
                                constant Stats &stats [[buffer(11)]],
                                uint id [[thread_position_in_grid]])
{
    Particle particle = particles[id];
    int3 CELL_COORDINATES = CELL_COORDS(particles[id].nextPosition, 2 * uniform.H);

    float density = 0;
    float nearDensity = 0;

    density += SpikyKernelPow2(0, uniform.H) * uniform.MASS;
    nearDensity += SpikyKernelPow3(0, 2 * uniform.H) * uniform.MASS;

    uint NEIGHBOURING_CELLS[27];


    for (int CELLID = 0; CELLID < 27; CELLID++) {
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];

        NEIGHBOURING_CELLS[CELLID] = HASH(NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                uint OPID = DENSE_TABLE[START_INDEX + NEIGHBOUR_ID];
                float3 diff = particles[OPID].nextPosition - particle.nextPosition;
                float sqrdDist = dot(diff, diff);
                if (sqrdDist < uniform.H * uniform.H) {
                    if (OPID != id) {
                        float Wij = SpikyKernelPow2(sqrt(sqrdDist), uniform.H);
                        density += Wij * uniform.MASS;
                        nearDensity += SpikyKernelPow3(sqrt(sqrdDist), uniform.H) * uniform.MASS;
                    }
                }
            }
        }
    }
    particle.density = density;
    particle.nearDensity = nearDensity;
    particle.pressure = uniform.GAZ_CONSTANT * (density - uniform.REST_DENSITY);
    particle.nearPressure = uniform.NEAR_GAZ_CONSTANT * nearDensity;
    particles[id] = particle;
}

kernel void updateParticles(device Particle *particles [[buffer(1)]],
                            constant uint *DENSE_TABLE [[buffer(3)]],
                            constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                            constant Uniform &uniform [[buffer(10)]],
                            constant Stats &stats [[buffer(11)]],
                            uint id [[thread_position_in_grid]])
{
    Particle particle = particles[id];


    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;
    for (uint subStepId = 0; subStepId < uniform.SUBSTEPS; subStepId++) {
        int3 CELL_COORDINATES = CELL_COORDS(particles[id].position, 2 * uniform.H);
        int CELL_HASH = HASH(CELL_COORDINATES, uniform.PARTICLECOUNT);

        uint RANDOM_STATE = CELL_HASH;
        float3 COLOR = float3(random(&RANDOM_STATE), random(&RANDOM_STATE), random(&RANDOM_STATE));
        COLOR = CalculateSpeedVisualization(length(particle.velocity), stats.MAX_GLOBAL_SPEED,
                                            stats.MIN_GLOBAL_SPEED); // rajouter Threshold
        // COLOR = CalculateDensityVisualization(particle.density, uniform.REST_DENSITY, stats.MAX_GLOBAL_DENSITY,
        // stats.MIN_GLOBAL_DENSITY, 500);
        particle.color = COLOR;

        float3 WEIGHT_FORCE = float3(0, -9.81 * uniform.MASS, 0);
        float3 PRESSURE_FORCE = float3(0, 0, 0);
        float3 VISCOSITY_FORCE = float3(0, 0, 0);

        uint NEIGHBOURING_CELLS[27];

        for (int CELLID = 0; CELLID < 27; CELLID++) {
            int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];

            NEIGHBOURING_CELLS[CELLID] = HASH(NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
            int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
            int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

            if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
                for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                    uint OPID = DENSE_TABLE[START_INDEX + NEIGHBOUR_ID];
                    if (OPID != id) {
                        float3 diff = particles[OPID].nextPosition - particle.nextPosition;
                        float sqrdDist = dot(diff, diff);
                        float3 dir = float3(2 * (random(&RANDOM_STATE) - 0.5), 2 * (random(&RANDOM_STATE) - 0.5),
                                            2 * (random(&RANDOM_STATE) - 0.5));
                        if (sqrdDist < uniform.H * uniform.H) {
                            if (sqrdDist > 0) {
                                dir = diff / sqrt(sqrdDist);
                            }
                            if (OPID != id) {
                                float sharedPressure = (particle.pressure + particles[OPID].pressure) / (2);
                                float sharedNearPressure = (particle.nearPressure + particles[OPID].nearPressure) / (2);
                                PRESSURE_FORCE += uniform.MASS *
                                                  (sharedPressure)*DerivativeSpikyPow2(sqrt(sqrdDist), uniform.H) *
                                                  (-dir) / (particles[OPID].density);
                                PRESSURE_FORCE += uniform.MASS *
                                                  (sharedNearPressure)*DerivativeSpikyPow3(sqrt(sqrdDist), uniform.H) *
                                                  (-dir) / (particles[OPID].nearDensity);
                                VISCOSITY_FORCE += (particles[OPID].velocity - particle.velocity) *
                                                   SmoothingKernelPoly6(sqrt(sqrdDist), uniform.H);
                            }
                        }
                    }
                }
            }
        }
        particle.forces = float3(0, 0, 0);
        particle.forces += WEIGHT_FORCE;
        particle.acceleration = particle.forces / uniform.MASS;
        particle.acceleration += -PRESSURE_FORCE / particle.density;
        particle.velocity += VISCOSITY_FORCE * uniform.VISCOSITY * updateDeltaTime;
        particle.velocity += particle.acceleration * updateDeltaTime;
        particle.position += particle.velocity * updateDeltaTime;


        if (particle.position.y <= uniform.RADIUS) {
            particle.position.y = uniform.RADIUS;
            particle.velocity.y *= -1 * uniform.DUMPING_FACTOR * 0.1;
        }
        if (particle.position.x > uniform.BOUNDING_BOX.x) {
            particle.position.x = uniform.BOUNDING_BOX.x;
            particle.velocity.x *= -1 * uniform.DUMPING_FACTOR;
        } else if (particle.position.x < -uniform.BOUNDING_BOX.x) {
            particle.position.x = -uniform.BOUNDING_BOX.x;
            particle.velocity.x *= -1 * uniform.DUMPING_FACTOR;
        }
        if (particle.position.z > uniform.BOUNDING_BOX.z) {
            particle.position.z = uniform.BOUNDING_BOX.z;
            particle.velocity.z *= -1 * uniform.DUMPING_FACTOR;
        } else if (particle.position.z < -uniform.BOUNDING_BOX.z) {
            particle.position.z = -uniform.BOUNDING_BOX.z;
            particle.velocity.z *= -1 * uniform.DUMPING_FACTOR;
        }
        particle.nextPosition = particle.position + particle.velocity * updateDeltaTime;
    }


    particles[id] = particle;
}

kernel void RESET_TABLES(device uint *TABLE_ARRAY [[buffer(2)]],
                         device uint *DENSE_TABLE [[buffer(3)]],
                         device START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                         constant Uniform &uniform [[buffer(10)]],
                         constant Stats &stats [[buffer(11)]],
                         uint id [[thread_position_in_grid]])
{
    TABLE_ARRAY[id] = 0;
    TABLE_ARRAY[id + 1] = 0;
    DENSE_TABLE[id] = 0;
    START_INDICES[id].START_INDEX = uniform.PARTICLECOUNT;
    START_INDICES[id].COUNT = 0;
}

kernel void INIT_TABLES(constant Particle *PARTICLES [[buffer(1)]],
                        device atomic_uint &TABLE_ARRAY [[buffer(2)]],
                        constant Uniform &uniform [[buffer(10)]],
                        constant Stats &stats [[buffer(11)]],
                        uint particleID [[thread_position_in_grid]])
{
    int3 cellCoords = CELL_COORDS(PARTICLES[particleID].position, 2 * uniform.H);
    uint hashValue = HASH(cellCoords, uniform.PARTICLECOUNT);
    atomic_fetch_add_explicit(&TABLE_ARRAY + hashValue, 1, memory_order_relaxed);
}

kernel void ASSIGN_DENSE_TABLE(constant Particle *PARTICLES [[buffer(1)]],
                               device atomic_uint &TABLE_ARRAY [[buffer(2)]],
                               device atomic_uint &DENSE_TABLE [[buffer(3)]],
                               constant Uniform &uniform [[buffer(10)]],
                               constant Stats &stats [[buffer(11)]],
                               uint particleID [[thread_position_in_grid]])
{
    int3 cellCoords = CELL_COORDS(PARTICLES[particleID].position, 2 * uniform.H);
    uint hashValue = HASH(cellCoords, uniform.PARTICLECOUNT);

    uint id = atomic_fetch_add_explicit(&TABLE_ARRAY + hashValue, -1, memory_order_relaxed);
    id -= 1;

    atomic_fetch_add_explicit(&DENSE_TABLE + id, particleID, memory_order_relaxed);
}
