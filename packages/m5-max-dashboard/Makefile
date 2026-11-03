BUILD ?= .build
CC ?= clang
SWIFTC ?= /Library/Developer/CommandLineTools/usr/bin/swiftc
SDKROOT ?= /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
CFLAGS = -O2 -Wall -Wextra -isysroot $(SDKROOT)
FRAMEWORKS = -framework IOKit -framework CoreFoundation -framework Foundation
SWIFTFLAGS = -swift-version 5 -O -sdk $(SDKROOT) -import-objc-header native/metrics.h
SHARED = shared/Metrics.swift shared/Layout.swift
MENU = $(wildcard menubar/*.swift)
NATIVE = $(BUILD)/metrics.o $(BUILD)/charge_limit.o

.PHONY: all clean
all: $(BUILD)/libmetrics.dylib $(BUILD)/m5-max-dashboard $(BUILD)/m5-max-dashboard-menu

$(BUILD):
	mkdir -p $@

$(BUILD)/metrics.o: native/metrics.c native/metrics.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/charge_limit.o: native/charge_limit.m native/metrics.h | $(BUILD)
	$(CC) $(CFLAGS) -fobjc-arc -c $< -o $@

$(BUILD)/libmetrics.dylib: $(NATIVE)
	$(CC) $(CFLAGS) -dynamiclib $(NATIVE) $(FRAMEWORKS) -o $@

$(BUILD)/m5-max-dashboard: $(SHARED) cli/main.swift $(NATIVE)
	$(SWIFTC) $(SWIFTFLAGS) $(SHARED) cli/main.swift $(NATIVE) $(FRAMEWORKS) -o $@

$(BUILD)/m5-max-dashboard-menu: $(SHARED) $(MENU) $(NATIVE)
	$(SWIFTC) $(SWIFTFLAGS) $(SHARED) $(MENU) $(NATIVE) $(FRAMEWORKS) -framework AppKit -framework SwiftUI -o $@

clean:
	rm -rf $(BUILD)
