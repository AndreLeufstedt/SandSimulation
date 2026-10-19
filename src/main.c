#include <stdio.h>
#include <stdlib.h>
#include "window.h"
#include "shape.h"

int main(void) {
    size_t count = 5000;

    const int width  = 600;
    const int height = 400;

    Window *_win = window_create("Project Explosion - Physics Sandbox", width, height);
    if (!_win) {
        fprintf(stderr, "Failed to create window\n");
        return 1;
    }

    shape_t *shapes = calloc(count, sizeof(shape_t));
    if (shapes == NULL) {
        perror("Failed to allocate memory");
        window_destroy(_win);
        return 1;
    }

    int cols = (width - 20) / 8;
    for (size_t i = 0; i < count; i++) {
        shapes[i] = (shape_t){
            .id = (int)i,
            .deltaV = {-150.0f + (float)(i % 300), -100.0f + (float)((i * 7) % 200)},
            .dimensions = {3.0f, 3.0f},
            .position = {10.0f + (float)((int)i % cols) * 8.0f, 10.0f + (float)((int)i / cols) * 8.0f},
            .color = {64 + (int)(i % 60), 140 + (int)(i % 100), 255, 255}
        };
    }

    win_t window = {
        .win = _win,
        .gravity = 600,
        .size = {(float)width, (float)height},
        .deltaTime = 0.0f
    };

    float restitution = 0.85f;
    float repel_radius = 80.0f;

    while (window_poll_events(window.win)) {
        window.deltaTime = window_get_dt(window.win);

        int mx, my;
        window_get_mouse_pos(window.win, &mx, &my);

        bool left_click = window_mouse_down(window.win, MOUSE_LEFT);
        bool shift_held = window_key_down(window.win, KEY_SHIFT);
        bool attract_active = left_click && !shift_held;
        bool repel_active   = left_click && shift_held;

        /* Update input & positions for all shapes */
        for (size_t i = 0; i < count; i++) {
            if (attract_active) {
                shapes[i].deltaV.x += (mx - shapes[i].position.x) * 8.0f * window.deltaTime;
                shapes[i].deltaV.y += (my - shapes[i].position.y) * 8.0f * window.deltaTime;
            }
            if (window_key_down(window.win, KEY_SPACE)) {
                shapes[i].deltaV.y = -400.0f;
            }

            move_shape_position(&window, &shapes[i]);
        }

        if (repel_active) {
            repel_shapes_from_circle(&window, shapes, count, (float)mx, (float)my, repel_radius, 450.0f);
        }

        /* Resolve object-to-object and edge collisions */
        handle_shape_collisions(&window, shapes, count, restitution);


        /* Render */
        window_clear(window.win, COLOR_RGB(20, 22, 28));

        for (size_t i = 0; i < count; i++) {
            float radius = shapes[i].dimensions.x * 0.5f;

            if (count <= 100 && attract_active) {
                draw_line(window.win,
                          (int)shapes[i].position.x,
                          (int)shapes[i].position.y,
                          mx, my,
                          COLOR_RGB(100, 200, 255));
            }

            uint32_t color = COLOR_RGB(shapes[i].color.r, shapes[i].color.g, shapes[i].color.b);
            draw_circle(window.win,
                        (int)(shapes[i].position.x + 0.5f),
                        (int)(shapes[i].position.y + 0.5f),
                        (int)radius,
                        color);
        }

        if (repel_active) {
            draw_circle_outline(window.win, mx, my, (int)repel_radius, COLOR_RGB(255, 100, 80));
        } else {
            draw_circle_outline(window.win, mx, my, 6, COLOR_RGB(180, 180, 190));
        }

        window_present(window.win);
    }

    free(shapes);
    window_destroy(window.win);
    return 0;
}
