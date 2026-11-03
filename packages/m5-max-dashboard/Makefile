BUILD ?= .build
CC ?= clang
SWIFTC ?= /Library/Developer/CommandLineTools/usr/bin/swiftc
SDKROOT ?= /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
CFLAGS = -O2 -Wall -Wextra -isysroot $(SDKROOT)
FRAMEWORKS = -framework IOKit -framework CoreFoundation
SWIFTFLAGS = -swift-version 5 -O -sdk $(SDKROOT) -import-objc-header native/metrics.h
SHARED = shared/Metrics.swift shared/Layout.swift

.PHONY: all clean
all: $(BUILD)/libmetrics.dylib $(BUILD)/m5-max-dashboard $(BUILD)/m5-max-dashboard-menu

$(BUILD):
	mkdir -p $@

$(BUILD)/metrics.o: native/metrics.c native/metrics.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/libmetrics.dylib: native/metrics.c native/metrics.h | $(BUILD)
	$(CC) $(CFLAGS) -dynamiclib $(FRAMEWORKS) $< -o $@

$(BUILD)/m5-max-dashboard: $(SHARED) cli/main.swift $(BUILD)/metrics.o
	$(SWIFTC) $(SWIFTFLAGS) $(SHARED) cli/main.swift $(BUILD)/metrics.o $(FRAMEWORKS) -o $@

$(BUILD)/m5-max-dashboard-menu: $(SHARED) menubar/main.swift $(BUILD)/metrics.o
	$(SWIFTC) $(SWIFTFLAGS) $(SHARED) menubar/main.swift $(BUILD)/metrics.o $(FRAMEWORKS) -framework AppKit -o $@

clean:
	rm -rf $(BUILD)
