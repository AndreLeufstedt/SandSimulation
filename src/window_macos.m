#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <stdlib.h>
#include <string.h>
#include "window.h"

struct Window {
    int width;
    int height;
    uint32_t *pixels;
    bool should_close;
    bool keys[512];
    bool mouse_buttons[2];
    int mouse_x;
    int mouse_y;
    double last_frame_time;
    float dt;

    NSWindow *ns_window;
    NSView *ns_view;
    id<NSWindowDelegate> delegate;
    CGColorSpaceRef color_space;
    CGContextRef bitmap_ctx;
};

@interface ExplosionWindowDelegate : NSObject <NSWindowDelegate>
@property (nonatomic, assign) struct Window *win;
@end

@implementation ExplosionWindowDelegate
- (BOOL)windowShouldClose:(id)sender {
    (void)sender;
    if (self.win) {
        self.win->should_close = true;
    }
    return NO;
}
@end

@interface ExplosionView : NSView
@property (nonatomic, assign) struct Window *win;
@end

@implementation ExplosionView
- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    (void)event;
    /* Handled in event loop; overriding prevents macOS alert beep */
}
@end

static int translate_key(NSEvent *event) {
    unsigned short keyCode = [event keyCode];
    switch (keyCode) {
        case 53:  return KEY_ESCAPE;
        case 49:  return KEY_SPACE;
        case 123: return KEY_LEFT;
        case 124: return KEY_RIGHT;
        case 125: return KEY_DOWN;
        case 126: return KEY_UP;
        default: break;
    }
    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars length] > 0) {
        unichar c = [chars characterAtIndex:0];
        if (c >= 'A' && c <= 'Z') {
            c = c - 'A' + 'a';
        }
        if (c < 256) {
            return (int)c;
        }
    }
    return -1;
}

double window_get_time(void) {
    return CACurrentMediaTime();
}

Window *window_create(const char *title, int width, int height) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        Window *win = calloc(1, sizeof(Window));
        if (!win) return NULL;

        win->width = width;
        win->height = height;
        win->pixels = calloc((size_t)width * (size_t)height, sizeof(uint32_t));
        if (!win->pixels) {
            free(win);
            return NULL;
        }

        NSRect rect = NSMakeRect(0, 0, width, height);
        NSWindowStyleMask style = NSWindowStyleMaskTitled |
                                  NSWindowStyleMaskClosable |
                                  NSWindowStyleMaskMiniaturizable;

        win->ns_window = [[NSWindow alloc] initWithContentRect:rect
                                                     styleMask:style
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];

        NSString *nsTitle = [NSString stringWithUTF8String:(title ? title : "Window")];
        [win->ns_window setTitle:nsTitle];
        [win->ns_window center];

        ExplosionWindowDelegate *delegate = [[ExplosionWindowDelegate alloc] init];
        delegate.win = win;
        win->delegate = delegate;
        [win->ns_window setDelegate:delegate];

        ExplosionView *view = [[ExplosionView alloc] initWithFrame:rect];
        view.win = win;
        [view setWantsLayer:YES];
        view.layer.magnificationFilter = kCAFilterNearest;

        [win->ns_window setContentView:view];
        [win->ns_window makeFirstResponder:view];
        [win->ns_window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp finishLaunching];

        win->ns_view = view;
        win->color_space = CGColorSpaceCreateDeviceRGB();
        win->bitmap_ctx = CGBitmapContextCreate(
            win->pixels,
            (size_t)width,
            (size_t)height,
            8,
            (size_t)width * 4,
            win->color_space,
            kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little
        );

        win->last_frame_time = window_get_time();
        win->dt = 1.0f / 60.0f;
        return win;
    }
}

bool window_poll_events(Window *win) {
    if (!win || win->should_close) return false;

    @autoreleasepool {
        NSEvent *event;
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                           untilDate:[NSDate distantPast]
                                              inMode:NSDefaultRunLoopMode
                                             dequeue:YES]) != nil) {
            NSEventType type = [event type];
            switch (type) {
                case NSEventTypeKeyDown: {
                    int k = translate_key(event);
                    if (k >= 0 && k < 512) win->keys[k] = true;
                    if (k == KEY_ESCAPE) win->should_close = true;
                    break;
                }
                case NSEventTypeKeyUp: {
                    int k = translate_key(event);
                    if (k >= 0 && k < 512) win->keys[k] = false;
                    break;
                }
                case NSEventTypeLeftMouseDown:
                    win->mouse_buttons[MOUSE_LEFT] = true;
                    [NSApp sendEvent:event];
                    break;
                case NSEventTypeLeftMouseUp:
                    win->mouse_buttons[MOUSE_LEFT] = false;
                    [NSApp sendEvent:event];
                    break;
                case NSEventTypeRightMouseDown:
                    win->mouse_buttons[MOUSE_RIGHT] = true;
                    [NSApp sendEvent:event];
                    break;
                case NSEventTypeRightMouseUp:
                    win->mouse_buttons[MOUSE_RIGHT] = false;
                    [NSApp sendEvent:event];
                    break;
                case NSEventTypeFlagsChanged:
                    win->keys[KEY_SHIFT] = (([event modifierFlags] & NSEventModifierFlagShift) != 0);
                    [NSApp sendEvent:event];
                    break;
                default:
                    [NSApp sendEvent:event];
                    break;
            }
        }

        win->keys[KEY_SHIFT] = (([NSEvent modifierFlags] & NSEventModifierFlagShift) != 0);

        NSPoint mouseLoc = [win->ns_window mouseLocationOutsideOfEventStream];
        NSPoint viewLoc = [win->ns_view convertPoint:mouseLoc fromView:nil];
        win->mouse_x = (int)viewLoc.x;
        win->mouse_y = (int)viewLoc.y;

        double now = window_get_time();
        win->dt = (float)(now - win->last_frame_time);
        if (win->dt > 0.1f) win->dt = 0.1f;
        win->last_frame_time = now;
    }

    return !win->should_close;
}

void window_present(Window *win) {
    if (!win || win->should_close) return;

    @autoreleasepool {
        CGImageRef img = CGBitmapContextCreateImage(win->bitmap_ctx);
        if (img) {
            win->ns_view.layer.contents = (__bridge id)img;
            CGImageRelease(img);
        }
        [CATransaction flush];

        /* Frame pacing (~60 FPS) */
        double target_frame_time = 1.0 / 60.0;
        double elapsed = window_get_time() - win->last_frame_time;
        if (elapsed < target_frame_time) {
            [NSThread sleepForTimeInterval:(target_frame_time - elapsed)];
        }
    }
}

void window_destroy(Window *win) {
    if (!win) return;
    @autoreleasepool {
        if (win->bitmap_ctx) CGContextRelease(win->bitmap_ctx);
        if (win->color_space) CGColorSpaceRelease(win->color_space);
        if (win->ns_window) {
            [win->ns_window setDelegate:nil];
            [win->ns_window close];
        }
        win->ns_view = nil;
        win->ns_window = nil;
        win->delegate = nil;
    }
    free(win->pixels);
    free(win);
}

int window_get_width(const Window *win) { return win ? win->width : 0; }
int window_get_height(const Window *win) { return win ? win->height : 0; }
uint32_t *window_get_pixels(Window *win) { return win ? win->pixels : NULL; }
float window_get_dt(const Window *win) { return win ? win->dt : 0.0f; }

bool window_key_down(const Window *win, int key) {
    if (!win || key < 0 || key >= 512) return false;
    return win->keys[key];
}

bool window_mouse_down(const Window *win, int button) {
    if (!win || button < 0 || button >= 2) return false;
    return win->mouse_buttons[button];
}

void window_get_mouse_pos(const Window *win, int *x, int *y) {
    if (!win) return;
    if (x) *x = win->mouse_x;
    if (y) *y = win->mouse_y;
}
