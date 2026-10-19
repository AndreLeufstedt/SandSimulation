#ifndef GPU_H
#define GPU_H

#include <stdbool.h>
#include <stddef.h>
#include "shape.h"

/* Runs the multi-pass spatial grid collision solver on the GPU using Metal Compute Shaders.
 * Returns true if executed on the GPU, or false if Metal is unavailable (falling back to CPU). */
bool gpu_handle_shape_collisions(win_t *window, shape_t *shapes, size_t count, float restitution);

#endif /* GPU_H */
