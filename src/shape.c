#include "shape.h"
#include <math.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

/* Applies the gravity to the shape */
void move_shape_gravity(win_t *window, shape_t *shape) {
    shape->deltaV.x += 0.0f;
    shape->deltaV.y += window->gravity * window->deltaTime;
}

/* Applies the deltaV of the shape to the position */
void move_shape_position(win_t *window, shape_t *shape) {
    move_shape_gravity(window, shape);
    shape->position.x += shape->deltaV.x * window->deltaTime;
    shape->position.y += shape->deltaV.y * window->deltaTime;
}

/* Resolves collision between a single shape and the window edges */
void collide_shape_edges(win_t *window, shape_t *shape, float restitution) {
    float radius = shape->dimensions.x * 0.5f;

    if (shape->position.y + radius > window->size.y) {
        shape->position.y = window->size.y - radius;
        if (shape->deltaV.y > 0.0f) {
            shape->deltaV.y = -shape->deltaV.y * restitution;
            if (shape->deltaV.y > -15.0f) {
                shape->deltaV.y = 0.0f;
            }
        }
        shape->deltaV.x *= 0.99f;
    }
    if (shape->position.y - radius < 0.0f) {
        shape->position.y = radius;
        if (shape->deltaV.y < 0.0f) {
            shape->deltaV.y = -shape->deltaV.y * restitution;
        }
    }
    if (shape->position.x + radius > window->size.x) {
        shape->position.x = window->size.x - radius;
        if (shape->deltaV.x > 0.0f) {
            shape->deltaV.x = -shape->deltaV.x * restitution;
        }
    }
    if (shape->position.x - radius < 0.0f) {
        shape->position.x = radius;
        if (shape->deltaV.x < 0.0f) {
            shape->deltaV.x = -shape->deltaV.x * restitution;
        }
    }
}

/* Helper to clamp a single shape's position to window bounds and transfer any blocked push to its partner */
static void clamp_pair_to_bounds(win_t *window, shape_t *a, shape_t *b) {
    float ra = a->dimensions.x * 0.5f;
    float rb = b->dimensions.x * 0.5f;
    float max_ax = window->size.x - ra;
    float max_ay = window->size.y - ra;
    float max_bx = window->size.x - rb;
    float max_by = window->size.y - rb;

    /* If 'a' was pushed through a wall/floor, clamp 'a' and transfer the push to 'b' */
    if (a->position.y > max_ay) {
        float excess = a->position.y - max_ay;
        a->position.y = max_ay;
        b->position.y -= excess;
    } else if (a->position.y < ra) {
        float excess = ra - a->position.y;
        a->position.y = ra;
        b->position.y += excess;
    }

    if (a->position.x > max_ax) {
        float excess = a->position.x - max_ax;
        a->position.x = max_ax;
        b->position.x -= excess;
    } else if (a->position.x < ra) {
        float excess = ra - a->position.x;
        a->position.x = ra;
        b->position.x += excess;
    }

    /* If 'b' was pushed through a wall/floor, clamp 'b' and transfer the push to 'a' */
    if (b->position.y > max_by) {
        float excess = b->position.y - max_by;
        b->position.y = max_by;
        a->position.y -= excess;
        if (a->position.y < ra) a->position.y = ra;
    } else if (b->position.y < rb) {
        float excess = rb - b->position.y;
        b->position.y = rb;
        a->position.y += excess;
        if (a->position.y > max_ay) a->position.y = max_ay;
    }

    if (b->position.x > max_bx) {
        float excess = b->position.x - max_bx;
        b->position.x = max_bx;
        a->position.x -= excess;
        if (a->position.x < ra) a->position.x = ra;
    } else if (b->position.x < rb) {
        float excess = rb - b->position.x;
        b->position.x = rb;
        a->position.x += excess;
        if (a->position.x > max_ax) a->position.x = max_ax;
    }
}

/* Internal helper for pair collision: separates overlapping circles and optionally resolves velocity */
static void resolve_pair(shape_t *a, shape_t *b, unsigned char *grounded_a, unsigned char *grounded_b, float restitution, bool resolve_velocity) {
    float ra = a->dimensions.x * 0.5f;
    float rb = b->dimensions.x * 0.5f;
    float min_dist = ra + rb;

    /* Fast AABB reject before multiplying */
    float dx = b->position.x - a->position.x;
    if (dx >= min_dist || dx <= -min_dist) return;

    float dy = b->position.y - a->position.y;
    if (dy >= min_dist || dy <= -min_dist) return;

    float dist_sq = dx * dx + dy * dy;
    if (dist_sq >= min_dist * min_dist) {
        return;
    }

    /* If both grains are on the same horizontal line (e.g. clamped to the floor),
     * break horizontal symmetry so compressed floor grains can pop up into the next layer. */
    if (dy > -0.01f && dy < 0.01f) {
        dy = (a->id < b->id) ? -0.1f : 0.1f;
        dist_sq = dx * dx + dy * dy;
    }

    /* Tiny tie-breaker only if two circles have the exact same X (e.g. clamped to a vertical wall) */
    if (dx > -0.01f && dx < 0.01f) {
        dx = ((a->id + b->id) & 1) ? -0.05f : 0.05f;
        dist_sq = dx * dx + dy * dy;
    }

    float dist = sqrtf(dist_sq);
    float nx, ny;

    if (dist > 0.0001f) {
        float inv_dist = 1.0f / dist;
        nx = dx * inv_dist;
        ny = dy * inv_dist;
    } else {
        nx = (a->id & 1) ? 0.70710678f : -0.70710678f;
        ny = -0.70710678f;
        dist = 0.0f;
    }

    float overlap = min_dist - dist;
    float sep_x = nx * overlap;
    float sep_y = ny * overlap;

    /* Horizontal separation is always symmetric 50/50 */
    a->position.x -= sep_x * 0.5f;
    b->position.x += sep_x * 0.5f;

    /* Only propagate floor support when one circle is genuinely resting on top of the other (|ny| > 0.5),
     * not when two circles are side-by-side. */
    if (ny < -0.5f && *grounded_a) {
        /* 'a' is grounded and 'b' is on top of 'a' */
        *grounded_b = 1;
        a->position.y -= sep_y * 0.2f;
        b->position.y += sep_y * 0.8f;
    } else if (ny > 0.5f && *grounded_b) {
        /* 'b' is grounded and 'a' is on top of 'b' */
        *grounded_a = 1;
        a->position.y -= sep_y * 0.8f;
        b->position.y += sep_y * 0.2f;
    } else {
        a->position.y -= sep_y * 0.5f;
        b->position.y += sep_y * 0.5f;
    }

    if (!resolve_velocity) {
        return;
    }

    /* Relative velocity along the collision normal */
    float rvx = b->deltaV.x - a->deltaV.x;
    float rvy = b->deltaV.y - a->deltaV.y;
    float vel_along_normal = rvx * nx + rvy * ny;

    /* Do not resolve velocity if already separating */
    if (vel_along_normal > 0.0f) {
        return;
    }

    /* Inelastic resting contact for low-speed collisions so the sand settles calmly */
    float e = (-vel_along_normal < 35.0f) ? 0.0f : (restitution * 0.25f);

    /* Impulse resolution using a single division (mass proportional to radius^2) */
    float ma = ra * ra;
    float mb = rb * rb;
    float inv_mass_total = 1.0f / (ma + mb);
    float impulse_scale = -(1.0f + e) * vel_along_normal * inv_mass_total;
    float ix = impulse_scale * nx;
    float iy = impulse_scale * ny;

    a->deltaV.x -= ix * mb;
    a->deltaV.y -= iy * mb;
    b->deltaV.x += ix * ma;
    b->deltaV.y += iy * ma;

    /* Inter-granular friction / damping between colliding grains */
    float friction = 0.08f;
    float dvx = (b->deltaV.x - a->deltaV.x) * friction;
    float dvy = (b->deltaV.y - a->deltaV.y) * friction;
    a->deltaV.x += dvx;
    a->deltaV.y += dvy;
    b->deltaV.x -= dvx;
    b->deltaV.y -= dvy;
}

/* Resolves collision between two circular shapes */
void collide_shape_pair(shape_t *a, shape_t *b, float restitution) {
    unsigned char ga = 0, gb = 0;
    resolve_pair(a, b, &ga, &gb, restitution, true);
}

#include "gpu.h"

/* Resolves all object-vs-object and object-vs-edge collisions (runs on Metal GPU with CPU fallback) */
void handle_shape_collisions(win_t *window, shape_t *shapes, size_t count, float restitution) {
    if (count == 0) return;

    if (gpu_handle_shape_collisions(window, shapes, count, restitution)) {
        return;
    }

    float max_diam = 2.0f;
    for (size_t i = 0; i < count; i++) {
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

    /* Persistent flat linked-cell buffers to avoid per-frame allocations */
    static int *grid_head = NULL;
    static unsigned char *grid_count = NULL;
    static size_t grid_cap = 0;
    static int *grid_next = NULL;
    static float *pred_x = NULL;
    static float *pred_y = NULL;
    static unsigned char *grounded = NULL;
    static size_t next_cap = 0;

    if (num_cells > grid_cap) {
        int *new_head = realloc(grid_head, num_cells * sizeof(int));
        unsigned char *new_count = realloc(grid_count, num_cells * sizeof(unsigned char));
        if (!new_head || !new_count) return;
        grid_head = new_head;
        grid_count = new_count;
        grid_cap = num_cells;
    }
    if (count > next_cap) {
        int *new_next = realloc(grid_next, count * sizeof(int));
        float *new_px = realloc(pred_x, count * sizeof(float));
        float *new_py = realloc(pred_y, count * sizeof(float));
        unsigned char *new_grounded = realloc(grounded, count * sizeof(unsigned char));
        if (!new_next || !new_px || !new_py || !new_grounded) return;
        grid_next = new_next;
        pred_x = new_px;
        pred_y = new_py;
        grounded = new_grounded;
        next_cap = count;
    }

    /* Record predicted positions and mark shapes touching the floor as grounded */
    for (size_t i = 0; i < count; i++) {
        collide_shape_edges(window, &shapes[i], restitution);
        pred_x[i] = shapes[i].position.x;
        pred_y[i] = shapes[i].position.y;
        float radius = shapes[i].dimensions.x * 0.5f;
        grounded[i] = (shapes[i].position.y + radius >= window->size.y - 0.5f) ? 1 : 0;
    }

    /* Offsets for neighbor cells when sweeping bottom-to-top */
    static const int neighbor_offsets[4][2] = {
        { 1,  0},
        {-1, -1},
        { 0, -1},
        { 1, -1}
    };

    const int solver_iterations = 10;
    const unsigned char max_per_cell = 32;

    for (int iter = 0; iter < solver_iterations; iter++) {
        bool resolve_vel = (iter == 0);

        memset(grid_head, -1, num_cells * sizeof(int));
        memset(grid_count, 0, num_cells * sizeof(unsigned char));

        /* 1. Insert shapes into spatial grid in O(N) */
        for (size_t i = 0; i < count; i++) {
            float radius = shapes[i].dimensions.x * 0.5f;
            if (shapes[i].position.y + radius >= window->size.y - 0.5f) {
                grounded[i] = 1;
            }

            int cx = (int)(shapes[i].position.x * inv_cell_size);
            int cy = (int)(shapes[i].position.y * inv_cell_size);
            if (cx < 0) cx = 0;
            else if (cx >= cols) cx = cols - 1;
            if (cy < 0) cy = 0;
            else if (cy >= rows) cy = rows - 1;

            int cell = cy * cols + cx;
            if (grid_count[cell] < max_per_cell) {
                grid_next[i] = grid_head[cell];
                grid_head[cell] = (int)i;
                grid_count[cell]++;
            }
        }

        /* 2. Sweep bottom-to-top (cy from rows-1 down to 0) */
        for (int cy = rows - 1; cy >= 0; cy--) {
            /* Alternate horizontal sweep direction each iteration to avoid left/right bias */
            int cx_start = (iter & 1) ? (cols - 1) : 0;
            int cx_end   = (iter & 1) ? -1 : cols;
            int cx_step  = (iter & 1) ? -1 : 1;

            for (int cx = cx_start; cx != cx_end; cx += cx_step) {
                int cell = cy * cols + cx;
                int a_idx = grid_head[cell];

                while (a_idx != -1) {
                    shape_t *a = &shapes[a_idx];

                    /* Same-cell pairs */
                    int b_idx = grid_next[a_idx];
                    while (b_idx != -1) {
                        shape_t *b = &shapes[b_idx];
                        resolve_pair(a, b, &grounded[a_idx], &grounded[b_idx], restitution, resolve_vel);
                        clamp_pair_to_bounds(window, a, b);
                        b_idx = grid_next[b_idx];
                    }

                    /* Neighbor-cell pairs (right and row above) */
                    for (int n = 0; n < 4; n++) {
                        int nx = cx + neighbor_offsets[n][0];
                        int ny = cy + neighbor_offsets[n][1];
                        if (nx >= 0 && nx < cols && ny >= 0 && ny < rows) {
                            int n_cell = ny * cols + nx;
                            b_idx = grid_head[n_cell];
                            while (b_idx != -1) {
                                shape_t *b = &shapes[b_idx];
                                resolve_pair(a, b, &grounded[a_idx], &grounded[b_idx], restitution, resolve_vel);
                                clamp_pair_to_bounds(window, a, b);
                                b_idx = grid_next[b_idx];
                            }
                        }
                    }

                    a_idx = grid_next[a_idx];
                }
            }
        }
    }

    /* Final edge clamp and velocity damping for floor-supported grains */
    float inv_dt = (window->deltaTime > 0.0001f) ? (1.0f / window->deltaTime) : 60.0f;
    for (size_t i = 0; i < count; i++) {
        collide_shape_edges(window, &shapes[i], 0.0f);

        if (grounded[i]) {
            float corr_x = shapes[i].position.x - pred_x[i];
            float corr_y = shapes[i].position.y - pred_y[i];

            /* If supported by the pile below, stop downward velocity accumulation completely */
            if (corr_y < -0.0001f && shapes[i].deltaV.y > 0.0f) {
                shapes[i].deltaV.y = 0.0f;
                shapes[i].deltaV.x *= 0.92f;
            }

            /* Purely dissipative horizontal damping when blocked (never adds outward velocity) */
            if (corr_x < -0.001f && shapes[i].deltaV.x > 0.0f) {
                shapes[i].deltaV.x += corr_x * inv_dt;
                if (shapes[i].deltaV.x < 0.0f) shapes[i].deltaV.x = 0.0f;
            } else if (corr_x > 0.001f && shapes[i].deltaV.x < 0.0f) {
                shapes[i].deltaV.x += corr_x * inv_dt;
                if (shapes[i].deltaV.x > 0.0f) shapes[i].deltaV.x = 0.0f;
            }
        }
    }
}

/* Forces all shapes away from a circular region around (cx, cy) */
void repel_shapes_from_circle(win_t *window, shape_t *shapes, size_t count, float cx, float cy, float radius, float force) {
    for (size_t i = 0; i < count; i++) {
        float sr = shapes[i].dimensions.x * 0.5f;
        float min_dist = radius + sr;

        float dx = shapes[i].position.x - cx;
        if (dx >= min_dist || dx <= -min_dist) continue;

        float dy = shapes[i].position.y - cy;
        if (dy >= min_dist || dy <= -min_dist) continue;

        float dist_sq = dx * dx + dy * dy;
        if (dist_sq >= min_dist * min_dist) continue;

        float dist = sqrtf(dist_sq);
        float nx, ny;
        if (dist > 0.0001f) {
            nx = dx / dist;
            ny = dy / dist;
        } else {
            nx = (shapes[i].id & 1) ? 0.70710678f : -0.70710678f;
            ny = -0.70710678f;
        }

        /* Push shape outside the circle boundary */
        shapes[i].position.x = cx + nx * min_dist;
        shapes[i].position.y = cy + ny * min_dist;

        /* Apply outward velocity away from the circle center */
        float vn = shapes[i].deltaV.x * nx + shapes[i].deltaV.y * ny;
        if (vn < force) {
            shapes[i].deltaV.x += nx * (force - vn);
            shapes[i].deltaV.y += ny * (force - vn);
        }

        collide_shape_edges(window, &shapes[i], 0.0f);
    }
}