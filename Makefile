CC       := clang
CFLAGS   := -std=c11 -Wall -Wextra -Wpedantic -O3 -g -Iinclude -MMD -MP
OBJCFLAGS:= -Wall -Wextra -O3 -g -Iinclude -MMD -MP -fobjc-arc
LDFLAGS  := -lm -framework Cocoa -framework QuartzCore -framework Metal -framework Foundation

SRC_DIR   := src
BUILD_DIR := build
TARGET    := $(BUILD_DIR)/app

C_SRCS   := $(wildcard $(SRC_DIR)/*.c)
M_SRCS   := $(wildcard $(SRC_DIR)/*.m)
OBJS     := $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(C_SRCS)) \
            $(patsubst $(SRC_DIR)/%.m,$(BUILD_DIR)/%.o,$(M_SRCS))
DEPS     := $(OBJS:.o=.d)

.PHONY: all run clean

all: $(TARGET)

$(TARGET): $(OBJS)
	@mkdir -p $(dir $@)
	$(CC) $(OBJS) -o $@ $(LDFLAGS)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.m
	@mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS) -c $< -o $@

run: $(TARGET)
	./$(TARGET)

clean:
	rm -rf $(BUILD_DIR)

-include $(DEPS)
