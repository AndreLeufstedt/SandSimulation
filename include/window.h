#ifndef WINDOW_H
#define WINDOW_H

#include <stdbool.h>
#include <stdint.h>

typedef struct Window Window;

/* Helper macro to pack RGB (0-255) into a 32-bit 0x00RRGGBB color */
#define COLOR_RGB(r, g, b) \
    (((uint32_t)((r) & 0xFF) << 16) | ((uint32_t)((g) & 0xFF) << 8) | (uint32_t)((b) & 0xFF))

/* Common key codes (macOS virtual key codes / ASCII helpers) */
enum {
    KEY_ESCAPE = 27,
    KEY_SPACE  = ' ',
    KEY_R      = 'r',
    KEY_W      = 'w',
    KEY_A      = 'a',
    KEY_S      = 's',
    KEY_D      = 'd',
    KEY_LEFT   = 256,
    KEY_RIGHT  = 257,
    KEY_DOWN   = 258,
    KEY_UP     = 259,
    KEY_SHIFT  = 260
};

enum {
    MOUSE_LEFT   = 0,
    MOUSE_RIGHT  = 1
};

/* Window lifecycle */
Window  *window_create(const char *title, int width, int height);
bool     window_poll_events(Window *win);
void     window_present(Window *win);
void     window_destroy(Window *win);

/* Window properties & timing */
int      window_get_width(const Window *win);
int      window_get_height(const Window *win);
uint32_t *window_get_pixels(Window *win);
float    window_get_dt(const Window *win);
double   window_get_time(void);

/* Input queries */
bool     window_key_down(const Window *win, int key);
bool     window_mouse_down(const Window *win, int button);
void     window_get_mouse_pos(const Window *win, int *x, int *y);

/* 2D Drawing primitives */
void     window_clear(Window *win, uint32_t color);
void     draw_pixel(Window *win, int x, int y, uint32_t color);
void     draw_line(Window *win, int x0, int y0, int x1, int y1, uint32_t color);
void     draw_rect(Window *win, int x, int y, int w, int h, uint32_t color);
void     draw_circle(Window *win, int cx, int cy, int radius, uint32_t color);
void     draw_circle_outline(Window *win, int cx, int cy, int radius, uint32_t color);

#endif /* WINDOW_H */
