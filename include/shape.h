#ifndef SHAPE_H
#define SHAPE_H

#include <stddef.h>

typedef struct {
    float x;
    float y;
} vector_2d;

typedef struct {
    int r;
    int g;
    int b;
    int t;
} color_rgba;

typedef struct {
    int id;
    vector_2d dimensions;
    vector_2d position;
    vector_2d deltaV;
    color_rgba color;
} shape_t;

typedef struct {
    struct Window *win;
    // Expanded needed values
    int gravity;
    vector_2d size;
    float deltaTime;
} win_t;

void move_shape_gravity(win_t *window, shape_t *shape);
void move_shape_position(win_t *window, shape_t *shape);

void collide_shape_edges(win_t *window, shape_t *shape, float restitution);
void collide_shape_pair(shape_t *a, shape_t *b, float restitution);
void handle_shape_collisions(win_t *window, shape_t *shapes, size_t count, float restitution);
void repel_shapes_from_circle(win_t *window, shape_t *shapes, size_t count, float cx, float cy, float radius, float force);

#endif