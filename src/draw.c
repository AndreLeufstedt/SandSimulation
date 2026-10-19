#include "window.h"
#include <stdlib.h>
#include <string.h>

void window_clear(Window *win, uint32_t color) {
    uint32_t *pixels = window_get_pixels(win);
    if (!pixels) return;
    size_t total_bytes = (size_t)window_get_width(win) * (size_t)window_get_height(win) * sizeof(uint32_t);
    memset_pattern4(pixels, &color, total_bytes);
}

void draw_pixel(Window *win, int x, int y, uint32_t color) {
    int w = window_get_width(win);
    int h = window_get_height(win);
    if (x < 0 || x >= w || y < 0 || y >= h) return;
    uint32_t *pixels = window_get_pixels(win);
    pixels[y * w + x] = color;
}

void draw_line(Window *win, int x0, int y0, int x1, int y1, uint32_t color) {
    int dx = abs(x1 - x0);
    int sx = x0 < x1 ? 1 : -1;
    int dy = -abs(y1 - y0);
    int sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;

    for (;;) {
        draw_pixel(win, x0, y0, color);
        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

void draw_rect(Window *win, int x, int y, int w, int h, uint32_t color) {
    int win_w = window_get_width(win);
    int win_h = window_get_height(win);
    uint32_t *pixels = window_get_pixels(win);
    if (!pixels) return;

    int x_start = x < 0 ? 0 : x;
    int y_start = y < 0 ? 0 : y;
    int x_end   = (x + w) > win_w ? win_w : (x + w);
    int y_end   = (y + h) > win_h ? win_h : (y + h);

    for (int py = y_start; py < y_end; ++py) {
        uint32_t *row = &pixels[py * win_w];
        for (int px = x_start; px < x_end; ++px) {
            row[px] = color;
        }
    }
}

void draw_circle(Window *win, int cx, int cy, int radius, uint32_t color) {
    uint32_t *pixels = window_get_pixels(win);
    if (!pixels) return;
    int win_w = window_get_width(win);
    int win_h = window_get_height(win);

    if (radius <= 0) {
        if (cx >= 0 && cx < win_w && cy >= 0 && cy < win_h) {
            pixels[cy * win_w + cx] = color;
        }
        return;
    }

    int y_start = (cy - radius < 0) ? -cy : -radius;
    int y_end   = (cy + radius >= win_h) ? (win_h - 1 - cy) : radius;
    int x_start = (cx - radius < 0) ? -cx : -radius;
    int x_end   = (cx + radius >= win_w) ? (win_w - 1 - cx) : radius;
    int r2 = radius * radius;

    for (int dy = y_start; dy <= y_end; ++dy) {
        int dy2 = dy * dy;
        uint32_t *row = &pixels[(cy + dy) * win_w + cx];
        for (int dx = x_start; dx <= x_end; ++dx) {
            if (dx * dx + dy2 <= r2) {
                row[dx] = color;
            }
        }
    }
}

void draw_circle_outline(Window *win, int cx, int cy, int radius, uint32_t color) {
    int x = radius;
    int y = 0;
    int err = 1 - x;

    while (x >= y) {
        draw_pixel(win, cx + x, cy + y, color);
        draw_pixel(win, cx + y, cy + x, color);
        draw_pixel(win, cx - y, cy + x, color);
        draw_pixel(win, cx - x, cy + y, color);
        draw_pixel(win, cx - x, cy - y, color);
        draw_pixel(win, cx - y, cy - x, color);
        draw_pixel(win, cx + y, cy - x, color);
        draw_pixel(win, cx + x, cy - y, color);
        y++;
        if (err < 0) {
            err += 2 * y + 1;
        } else {
            x--;
            err += 2 * (y - x + 1);
        }
    }
}
