#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>
#include "gpu.h"

typedef struct {
    float width;
    float height;
    float inv_cell_size;
    float restitution;
    float dt;
    float inv_dt;
    int cols;
    int rows;
    int count;
    int num_cells;
    int resolve_vel;
} SimParams;

static const char *kMetalShaderSource =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "\n"
    "struct vector_2d {\n"
    "    float x;\n"
    "    float y;\n"
    "};\n"
    "\n"
    "struct color_rgba {\n"
    "    int r;\n"
    "    int g;\n"
    "    int b;\n"
    "    int t;\n"
    "};\n"
    "\n"
    "struct shape_t {\n"
    "    int id;\n"
    "    vector_2d dimensions;\n"
    "    vector_2d position;\n"
    "    vector_2d deltaV;\n"
    "    color_rgba color;\n"
    "};\n"
    "\n"
    "struct SimParams {\n"
    "    float width;\n"
    "    float height;\n"
    "    float inv_cell_size;\n"
    "    float restitution;\n"
    "    float dt;\n"
    "    float inv_dt;\n"
    "    int cols;\n"
    "    int rows;\n"
    "    int count;\n"
    "    int num_cells;\n"
    "    int resolve_vel;\n"
    "};\n"
    "\n"
    "inline void clamp_edges(thread shape_t &s, constant SimParams &p, float restitution) {\n"
    "    float r = s.dimensions.x * 0.5f;\n"
    "    if (s.position.y + r > p.height) {\n"
    "        s.position.y = p.height - r;\n"
    "        if (s.deltaV.y > 0.0f) {\n"
    "            s.deltaV.y = -s.deltaV.y * restitution;\n"
    "            if (s.deltaV.y > -15.0f) s.deltaV.y = 0.0f;\n"
    "        }\n"
    "        s.deltaV.x *= 0.98f;\n"
    "    }\n"
    "    if (s.position.y - r < 0.0f) {\n"
    "        s.position.y = r;\n"
    "        if (s.deltaV.y < 0.0f) s.deltaV.y = -s.deltaV.y * restitution;\n"
    "    }\n"
    "    if (s.position.x + r > p.width) {\n"
    "        s.position.x = p.width - r;\n"
    "        if (s.deltaV.x > 0.0f) s.deltaV.x = -s.deltaV.x * restitution;\n"
    "    }\n"
    "    if (s.position.x - r < 0.0f) {\n"
    "        s.position.x = r;\n"
    "        if (s.deltaV.x < 0.0f) s.deltaV.x = -s.deltaV.x * restitution;\n"
    "    }\n"
    "}\n"
    "\n"
    "kernel void k_clear_grid(\n"
    "    device atomic_int *grid_head [[buffer(0)]],\n"
    "    device atomic_uint *grid_count [[buffer(1)]],\n"
    "    constant SimParams &p [[buffer(2)]],\n"
    "    uint gid [[thread_position_in_grid]])\n"
    "{\n"
    "    if ((int)gid >= p.num_cells) return;\n"
    "    atomic_store_explicit(&grid_head[gid], -1, memory_order_relaxed);\n"
    "    atomic_store_explicit(&grid_count[gid], 0u, memory_order_relaxed);\n"
    "}\n"
    "\n"
    "kernel void k_pre_solve(\n"
    "    device shape_t *shapes [[buffer(0)]],\n"
    "    device float4 *pred_pos [[buffer(1)]],\n"
    "    device atomic_uint *grounded [[buffer(2)]],\n"
    "    constant SimParams &p [[buffer(3)]],\n"
    "    uint gid [[thread_position_in_grid]])\n"
    "{\n"
    "    if ((int)gid >= p.count) return;\n"
    "    shape_t s = shapes[gid];\n"
    "    float2 start_p = float2(s.position.x - s.deltaV.x * p.dt, s.position.y - s.deltaV.y * p.dt);\n"
    "    clamp_edges(s, p, p.restitution);\n"
    "    pred_pos[gid] = float4(start_p.x, start_p.y, s.position.x, s.position.y);\n"
    "    float r = s.dimensions.x * 0.5f;\n"
    "    uint g = (s.position.y + r >= p.height - 0.5f) ? 1u : 0u;\n"
    "    atomic_store_explicit(&grounded[gid], g, memory_order_relaxed);\n"
    "    shapes[gid] = s;\n"
    "}\n"
    "\n"
    "kernel void k_build_grid(\n"
    "    device const shape_t *shapes [[buffer(0)]],\n"
    "    device atomic_int *grid_head [[buffer(1)]],\n"
    "    device atomic_uint *grid_count [[buffer(2)]],\n"
    "    device int *grid_next [[buffer(3)]],\n"
    "    device atomic_uint *grounded [[buffer(4)]],\n"
    "    constant SimParams &p [[buffer(5)]],\n"
    "    uint gid [[thread_position_in_grid]])\n"
    "{\n"
    "    if ((int)gid >= p.count) return;\n"
    "    shape_t s = shapes[gid];\n"
    "    float r = s.dimensions.x * 0.5f;\n"
    "    if (s.position.y + r >= p.height - 0.5f) {\n"
    "        atomic_store_explicit(&grounded[gid], 1u, memory_order_relaxed);\n"
    "    }\n"
    "    int cx = clamp((int)(s.position.x * p.inv_cell_size), 0, p.cols - 1);\n"
    "    int cy = clamp((int)(s.position.y * p.inv_cell_size), 0, p.rows - 1);\n"
    "    int cell = cy * p.cols + cx;\n"
    "    uint cnt = atomic_fetch_add_explicit(&grid_count[cell], 1u, memory_order_relaxed);\n"
    "    if (cnt < 32u) {\n"
    "        int prev = atomic_exchange_explicit(&grid_head[cell], (int)gid, memory_order_relaxed);\n"
    "        grid_next[gid] = prev;\n"
    "    } else {\n"
    "        grid_next[gid] = -1;\n"
    "    }\n"
    "}\n"
    "\n"
    "kernel void k_prop_grounded(\n"
    "    device const shape_t *shapes [[buffer(0)]],\n"
    "    device const int *grid_head [[buffer(1)]],\n"
    "    device const int *grid_next [[buffer(2)]],\n"
    "    device atomic_uint *grounded [[buffer(3)]],\n"
    "    constant SimParams &p [[buffer(4)]],\n"
    "    uint gid [[thread_position_in_grid]])\n"
    "{\n"
    "    if ((int)gid >= p.count) return;\n"
    "    if (atomic_load_explicit(&grounded[gid], memory_order_relaxed) != 0u) return;\n"
    "\n"
    "    shape_t me = shapes[gid];\n"
    "    float ra = me.dimensions.x * 0.5f;\n"
    "    int cx = clamp((int)(me.position.x * p.inv_cell_size), 0, p.cols - 1);\n"
    "    int cy = clamp((int)(me.position.y * p.inv_cell_size), 0, p.rows - 1);\n"
    "\n"
    "    int y_min = max(0, cy);\n"
    "    int y_max = min(p.rows - 1, cy + 1);\n"
    "    int x_min = max(0, cx - 1);\n"
    "    int x_max = min(p.cols - 1, cx + 1);\n"
    "\n"
    "    for (int ny_c = y_min; ny_c <= y_max; ++ny_c) {\n"
    "        int row_offset = ny_c * p.cols;\n"
    "        for (int nx_c = x_min; nx_c <= x_max; ++nx_c) {\n"
    "            int other_idx = grid_head[row_offset + nx_c];\n"
    "            while (other_idx != -1) {\n"
    "                if (other_idx != (int)gid && atomic_load_explicit(&grounded[other_idx], memory_order_relaxed) != 0u) {\n"
    "                    shape_t other = shapes[other_idx];\n"
    "                    float rb = other.dimensions.x * 0.5f;\n"
    "                    float reach = ra + rb + 0.35f;\n"
    "                    float dx = me.position.x - other.position.x;\n"
    "                    float dy = me.position.y - other.position.y;\n"
    "                    if (dy < -0.5f && dx * dx + dy * dy < reach * reach) {\n"
    "                        atomic_store_explicit(&grounded[gid], 1u, memory_order_relaxed);\n"
    "                        return;\n"
    "                    }\n"
    "                }\n"
    "                other_idx = grid_next[other_idx];\n"
    "            }\n"
    "        }\n"
    "    }\n"
    "}\n"
    "\n"
    "kernel void k_solve_iter(\n"
    "    device const shape_t *shapes_in [[buffer(0)]],\n"
    "    device shape_t *shapes_out [[buffer(1)]],\n"
    "    device const int *grid_head [[buffer(2)]],\n"
    "    device const int *grid_next [[buffer(3)]],\n"
    "    device atomic_uint *grounded [[buffer(4)]],\n"
    "    constant SimParams &p [[buffer(5)]],\n"
    "    uint gid [[thread_position_in_grid]])\n"
    "{\n"
    "    if ((int)gid >= p.count) return;\n"
    "    shape_t me = shapes_in[gid];\n"
    "    uint my_grounded = atomic_load_explicit(&grounded[gid], memory_order_relaxed);\n"
    "    float ra = me.dimensions.x * 0.5f;\n"
    "\n"
    "    int cx = clamp((int)(me.position.x * p.inv_cell_size), 0, p.cols - 1);\n"
    "    int cy = clamp((int)(me.position.y * p.inv_cell_size), 0, p.rows - 1);\n"
    "\n"
    "    float pos_dx = 0.0f;\n"
    "    float pos_dy = 0.0f;\n"
    "    float vel_dx = 0.0f;\n"
    "    float vel_dy = 0.0f;\n"
    "    int contacts = 0;\n"
    "    int vel_contacts = 0;\n"
    "\n"
    "    int y_min = max(0, cy - 1);\n"
    "    int y_max = min(p.rows - 1, cy + 1);\n"
    "    int x_min = max(0, cx - 1);\n"
    "    int x_max = min(p.cols - 1, cx + 1);\n"
    "\n"
    "    for (int ny_c = y_min; ny_c <= y_max; ++ny_c) {\n"
    "        int row_offset = ny_c * p.cols;\n"
    "        for (int nx_c = x_min; nx_c <= x_max; ++nx_c) {\n"
    "            int other_idx = grid_head[row_offset + nx_c];\n"
    "            while (other_idx != -1) {\n"
    "                if (other_idx != (int)gid) {\n"
    "                    shape_t other = shapes_in[other_idx];\n"
    "                    float rb = other.dimensions.x * 0.5f;\n"
    "                    float min_dist = ra + rb;\n"
    "                    float dx = me.position.x - other.position.x;\n"
    "                    float dy = me.position.y - other.position.y;\n"
    "\n"
    "                    if (dx < min_dist && dx > -min_dist && dy < min_dist && dy > -min_dist) {\n"
    "                        float dist_sq = dx * dx + dy * dy;\n"
    "                        if (dist_sq < min_dist * min_dist) {\n"
    "                            /* Only pop horizontally-aligned grains up a layer if heavily compressed */\n"
    "                            if (dy > -0.01f && dy < 0.01f && dist_sq < (min_dist * 0.65f) * (min_dist * 0.65f)) {\n"
    "                                dy = (me.id < other.id) ? -0.1f : 0.1f;\n"
    "                                dist_sq = dx * dx + dy * dy;\n"
    "                            }\n"
    "                            if (dx > -0.01f && dx < 0.01f) {\n"
    "                                dx = (me.id < other.id) ? -0.05f : 0.05f;\n"
    "                                dist_sq = dx * dx + dy * dy;\n"
    "                            }\n"
    "                            float dist = sqrt(dist_sq);\n"
    "                            float nx, ny;\n"
    "                            if (dist > 0.0001f) {\n"
    "                                float inv_d = 1.0f / dist;\n"
    "                                nx = dx * inv_d;\n"
    "                                ny = dy * inv_d;\n"
    "                            } else {\n"
    "                                nx = (me.id < other.id) ? -0.70710678f : 0.70710678f;\n"
    "                                ny = (me.id < other.id) ? -0.70710678f : 0.70710678f;\n"
    "                                dist = 0.0f;\n"
    "                            }\n"
    "\n"
    "                            float overlap = min_dist - dist;\n"
    "                            uint other_grounded = atomic_load_explicit(&grounded[other_idx], memory_order_relaxed);\n"
    "\n"
    "                            float wx = 0.5f;\n"
    "                            if ((other.position.x <= rb + 0.1f && nx > 0.0f) ||\n"
    "                                (other.position.x >= p.width - rb - 0.1f && nx < 0.0f)) {\n"
    "                                wx = 1.0f;\n"
    "                            } else if (other_grounded != 0u && ny < -0.65f && overlap < 0.25f) {\n"
    "                                /* Static friction on gentle resting slopes prevents gravity-normal sideways creep */\n"
    "                                wx = 0.15f;\n"
    "                            }\n"
    "                            pos_dx += nx * (overlap * wx);\n"
    "\n"
    "                            float wy = 0.5f;\n"
    "                            if (ny < -0.45f && other_grounded != 0u) {\n"
    "                                my_grounded = 1u;\n"
    "                                wy = (other.position.y + rb >= p.height - 0.5f) ? 1.0f : 0.85f;\n"
    "                            } else if (ny > 0.45f && my_grounded != 0u) {\n"
    "                                wy = 0.15f;\n"
    "                            }\n"
    "                            pos_dy += ny * (overlap * wy);\n"
    "                            contacts++;\n"
    "\n"
    "                            if (p.resolve_vel != 0) {\n"
    "                                float rvx = me.deltaV.x - other.deltaV.x;\n"
    "                                float rvy = me.deltaV.y - other.deltaV.y;\n"
    "                                float vn = rvx * nx + rvy * ny;\n"
    "                                if (vn < 0.0f) {\n"
    "                                    float e = (-vn < 45.0f) ? 0.0f : (p.restitution * 0.25f);\n"
    "                                    float ma = ra * ra;\n"
    "                                    float mb = rb * rb;\n"
    "                                    float j = -(1.0f + e) * vn * mb / (ma + mb);\n"
    "                                    vel_dx += j * nx - rvx * 0.12f;\n"
    "                                    vel_dy += j * ny - rvy * 0.12f;\n"
    "                                    vel_contacts++;\n"
    "                                }\n"
    "                            }\n"
    "                        }\n"
    "                    }\n"
    "                }\n"
    "                other_idx = grid_next[other_idx];\n"
    "            }\n"
    "        }\n"
    "    }\n"
    "\n"
    "    if (contacts > 0) {\n"
    "        float scale = 0.85f / (float)contacts;\n"
    "        me.position.x += pos_dx * scale;\n"
    "        me.position.y += pos_dy * scale;\n"
    "    }\n"
    "    if (vel_contacts > 0) {\n"
    "        float inv_vc = 1.0f / (float)vel_contacts;\n"
    "        me.deltaV.x += vel_dx * inv_vc;\n"
    "        me.deltaV.y += vel_dy * inv_vc;\n"
    "    }\n"
    "\n"
    "    clamp_edges(me, p, 0.0f);\n"
    "    if (me.position.y + ra >= p.height - 0.5f) {\n"
    "        my_grounded = 1u;\n"
    "    }\n"
    "    if (my_grounded != 0u) {\n"
    "        atomic_store_explicit(&grounded[gid], 1u, memory_order_relaxed);\n"
    "    }\n"
    "    shapes_out[gid] = me;\n"
    "}\n"
    "\n"
    "kernel void k_post_solve(\n"
    "    device shape_t *shapes [[buffer(0)]],\n"
    "    device const float4 *pred_pos [[buffer(1)]],\n"
    "    device atomic_uint *grounded [[buffer(2)]],\n"
    "    constant SimParams &p [[buffer(3)]],\n"
    "    uint gid [[thread_position_in_grid]])\n"
    "{\n"
    "    if ((int)gid >= p.count) return;\n"
    "    shape_t s = shapes[gid];\n"
    "    clamp_edges(s, p, 0.0f);\n"
    "\n"
    "    float r = s.dimensions.x * 0.5f;\n"
    "    float4 pp = pred_pos[gid];\n"
    "    float2 start_p = pp.xy;\n"
    "    float corr_x = s.position.x - pp.z;\n"
    "    float corr_y = s.position.y - pp.w;\n"
    "    uint is_grounded = atomic_load_explicit(&grounded[gid], memory_order_relaxed);\n"
    "\n"
    "    if (is_grounded != 0u || (s.position.y + r >= p.height - 0.5f)) {\n"
    "        if (corr_y < -0.0001f && s.deltaV.y > 0.0f) {\n"
    "            s.deltaV.y = 0.0f;\n"
    "            s.deltaV.x *= 0.85f;\n"
    "        }\n"
    "        if (corr_x < -0.001f && s.deltaV.x > 0.0f) {\n"
    "            s.deltaV.x += corr_x * p.inv_dt;\n"
    "            if (s.deltaV.x < 0.0f) s.deltaV.x = 0.0f;\n"
    "        } else if (corr_x > 0.001f && s.deltaV.x < 0.0f) {\n"
    "            s.deltaV.x += corr_x * p.inv_dt;\n"
    "            if (s.deltaV.x > 0.0f) s.deltaV.x = 0.0f;\n"
    "        }\n"
    "\n"
    "        /* If a grounded grain is supported from below and barely moved from its start-of-frame position,\n"
    "         * lock it to rest so sub-pixel solver iterations never cause ground jitter or creep. */\n"
    "        float step_dx = s.position.x - start_p.x;\n"
    "        float step_dy = s.position.y - start_p.y;\n"
    "        float step_sq = step_dx * step_dx + step_dy * step_dy;\n"
    "        float speed_sq = s.deltaV.x * s.deltaV.x + s.deltaV.y * s.deltaV.y;\n"
    "        if ((corr_y < -0.0005f || s.position.y + r >= p.height - 0.5f) && speed_sq < 9.0f && step_sq < 0.035f) {\n"
    "            s.position.x = start_p.x;\n"
    "            s.position.y = start_p.y;\n"
    "            s.deltaV.x = 0.0f;\n"
    "            s.deltaV.y = 0.0f;\n"
    "        }\n"
    "    }\n"
    "    shapes[gid] = s;\n"
    "}\n";

static id<MTLDevice> g_device = nil;
static id<MTLCommandQueue> g_queue = nil;
static id<MTLComputePipelineState> g_pso_clear = nil;
static id<MTLComputePipelineState> g_pso_pre = nil;
static id<MTLComputePipelineState> g_pso_build = nil;
static id<MTLComputePipelineState> g_pso_prop = nil;
static id<MTLComputePipelineState> g_pso_solve = nil;
static id<MTLComputePipelineState> g_pso_post = nil;
static bool g_metal_init_tried = false;
static bool g_metal_available = false;

static id<MTLBuffer> g_buf_shapes_a = nil;
static id<MTLBuffer> g_buf_shapes_b = nil;
static id<MTLBuffer> g_buf_pred = nil;
static id<MTLBuffer> g_buf_grounded = nil;
static id<MTLBuffer> g_buf_grid_next = nil;
static size_t g_shape_cap = 0;

static id<MTLBuffer> g_buf_grid_head = nil;
static id<MTLBuffer> g_buf_grid_count = nil;
static size_t g_cell_cap = 0;

static bool init_metal(void) {
    if (g_metal_init_tried) return g_metal_available;
    g_metal_init_tried = true;

    @autoreleasepool {
        g_device = MTLCreateSystemDefaultDevice();
        if (!g_device) {
            fprintf(stderr, "[GPU] Metal device unavailable, falling back to CPU.\n");
            return false;
        }

        g_queue = [g_device newCommandQueue];
        if (!g_queue) return false;

        NSError *err = nil;
        NSString *src = [NSString stringWithUTF8String:kMetalShaderSource];
        MTLCompileOptions *opts = [[MTLCompileOptions alloc] init];
        id<MTLLibrary> lib = [g_device newLibraryWithSource:src options:opts error:&err];
        if (!lib) {
            fprintf(stderr, "[GPU] Failed to compile Metal shader: %s\n",
                    [[err localizedDescription] UTF8String]);
            return false;
        }

        g_pso_clear = [g_device newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k_clear_grid"] error:&err];
        g_pso_pre   = [g_device newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k_pre_solve"] error:&err];
        g_pso_build = [g_device newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k_build_grid"] error:&err];
        g_pso_prop  = [g_device newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k_prop_grounded"] error:&err];
        g_pso_solve = [g_device newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k_solve_iter"] error:&err];
        g_pso_post  = [g_device newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k_post_solve"] error:&err];

        if (!g_pso_clear || !g_pso_pre || !g_pso_build || !g_pso_prop || !g_pso_solve || !g_pso_post) {
            fprintf(stderr, "[GPU] Failed to create compute pipeline states.\n");
            return false;
        }

        printf("[GPU] Metal Compute initialized on: %s\n", [[g_device name] UTF8String]);
        g_metal_available = true;
        return true;
    }
}

static void dispatch_1d(id<MTLComputeCommandEncoder> enc, id<MTLComputePipelineState> pso, size_t count) {
    if (count == 0) return;
    NSUInteger w = [pso maxTotalThreadsPerThreadgroup];
    if (w > 256) w = 256;
    MTLSize threadsPerGroup = MTLSizeMake(w, 1, 1);
    MTLSize numGroups = MTLSizeMake((count + w - 1) / w, 1, 1);
    [enc setComputePipelineState:pso];
    [enc dispatchThreadgroups:numGroups threadsPerThreadgroup:threadsPerGroup];
}

bool gpu_handle_shape_collisions(win_t *window, shape_t *shapes, size_t count, float restitution) {
    if (count == 0) return true;
    if (!init_metal()) return false;

    @autoreleasepool {
        float max_diam = 2.0f;
        for (size_t i = 0; i < count; ++i) {
            if (shapes[i].dimensions.x > max_diam) {
                max_diam = shapes[i].dimensions.x;
            }
        }

        float inv_cell_size = 1.0f / max_diam;
        int cols = (int)(window->size.x * inv_cell_size) + 1;
        int rows = (int)(window->size.y * inv_cell_size) + 1;
        if (cols < 1) cols = 1;
        if (rows < 1) rows = 1;
        size_t num_cells = (size_t)cols * (size_t)rows;

        if (count > g_shape_cap) {
            g_buf_shapes_a  = [g_device newBufferWithLength:count * sizeof(shape_t) options:MTLResourceStorageModeShared];
            g_buf_shapes_b  = [g_device newBufferWithLength:count * sizeof(shape_t) options:MTLResourceStorageModeShared];
            g_buf_pred      = [g_device newBufferWithLength:count * sizeof(float) * 4 options:MTLResourceStorageModePrivate];
            g_buf_grounded  = [g_device newBufferWithLength:count * sizeof(unsigned int) options:MTLResourceStorageModePrivate];
            g_buf_grid_next = [g_device newBufferWithLength:count * sizeof(int) options:MTLResourceStorageModePrivate];
            g_shape_cap = count;
        }

        if (num_cells > g_cell_cap) {
            g_buf_grid_head  = [g_device newBufferWithLength:num_cells * sizeof(int) options:MTLResourceStorageModePrivate];
            g_buf_grid_count = [g_device newBufferWithLength:num_cells * sizeof(unsigned int) options:MTLResourceStorageModePrivate];
            g_cell_cap = num_cells;
        }

        /* Copy shapes into shared unified memory buffer */
        memcpy([g_buf_shapes_a contents], shapes, count * sizeof(shape_t));

        float dt = (window->deltaTime > 0.0001f) ? window->deltaTime : (1.0f / 60.0f);
        SimParams params = {
            .width = window->size.x,
            .height = window->size.y,
            .inv_cell_size = inv_cell_size,
            .restitution = restitution,
            .dt = dt,
            .inv_dt = 1.0f / dt,
            .cols = cols,
            .rows = rows,
            .count = (int)count,
            .num_cells = (int)num_cells,
            .resolve_vel = 1
        };

        id<MTLCommandBuffer> cmd = [g_queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];

        /* Pre-solve: edge clamp + save start and predicted positions */
        [enc setBuffer:g_buf_shapes_a offset:0 atIndex:0];
        [enc setBuffer:g_buf_pred offset:0 atIndex:1];
        [enc setBuffer:g_buf_grounded offset:0 atIndex:2];
        [enc setBytes:&params length:sizeof(SimParams) atIndex:3];
        dispatch_1d(enc, g_pso_pre, count);

        const int solver_iterations = 12;
        id<MTLBuffer> cur_shapes = g_buf_shapes_a;
        id<MTLBuffer> nxt_shapes = g_buf_shapes_b;

        for (int iter = 0; iter < solver_iterations; ++iter) {
            params.resolve_vel = (iter == 0) ? 1 : 0;

            /* Rebuild spatial grid every 3 iterations (0, 3, 6, 9) */
            if (iter % 3 == 0) {
                [enc setBuffer:g_buf_grid_head offset:0 atIndex:0];
                [enc setBuffer:g_buf_grid_count offset:0 atIndex:1];
                [enc setBytes:&params length:sizeof(SimParams) atIndex:2];
                dispatch_1d(enc, g_pso_clear, num_cells);

                [enc setBuffer:cur_shapes offset:0 atIndex:0];
                [enc setBuffer:g_buf_grid_head offset:0 atIndex:1];
                [enc setBuffer:g_buf_grid_count offset:0 atIndex:2];
                [enc setBuffer:g_buf_grid_next offset:0 atIndex:3];
                [enc setBuffer:g_buf_grounded offset:0 atIndex:4];
                [enc setBytes:&params length:sizeof(SimParams) atIndex:5];
                dispatch_1d(enc, g_pso_build, count);

                /* Propagate grounded status through the entire pile depth on iter 0 */
                int prop_passes = (iter == 0) ? 28 : 4;
                [enc setBuffer:cur_shapes offset:0 atIndex:0];
                [enc setBuffer:g_buf_grid_head offset:0 atIndex:1];
                [enc setBuffer:g_buf_grid_next offset:0 atIndex:2];
                [enc setBuffer:g_buf_grounded offset:0 atIndex:3];
                [enc setBytes:&params length:sizeof(SimParams) atIndex:4];
                for (int p = 0; p < prop_passes; ++p) {
                    dispatch_1d(enc, g_pso_prop, count);
                }
            }

            /* Parallel Jacobi collision resolution on GPU */
            [enc setBuffer:cur_shapes offset:0 atIndex:0];
            [enc setBuffer:nxt_shapes offset:0 atIndex:1];
            [enc setBuffer:g_buf_grid_head offset:0 atIndex:2];
            [enc setBuffer:g_buf_grid_next offset:0 atIndex:3];
            [enc setBuffer:g_buf_grounded offset:0 atIndex:4];
            [enc setBytes:&params length:sizeof(SimParams) atIndex:5];
            dispatch_1d(enc, g_pso_solve, count);

            /* Swap double buffers */
            id<MTLBuffer> tmp_s = cur_shapes; cur_shapes = nxt_shapes; nxt_shapes = tmp_s;
        }

        /* Post-solve: final edge clamp + dissipative velocity damping + resting sleep */
        [enc setBuffer:cur_shapes offset:0 atIndex:0];
        [enc setBuffer:g_buf_pred offset:0 atIndex:1];
        [enc setBuffer:g_buf_grounded offset:0 atIndex:2];
        [enc setBytes:&params length:sizeof(SimParams) atIndex:3];
        dispatch_1d(enc, g_pso_post, count);

        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];

        /* Copy updated shapes back from shared unified memory buffer */
        memcpy(shapes, [cur_shapes contents], count * sizeof(shape_t));
        return true;
    }
}
