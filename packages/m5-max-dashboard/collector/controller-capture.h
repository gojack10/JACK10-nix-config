// Read-only GPU-attributed AMC byte counters in a fresh perfpowermetricd.
// The helper never enters its normal service main and exits when its owner closes.
#define RTLD_NOW 2
#define NULL 0
#define YES ((BOOL)1)
extern FILE *__stdoutp;
extern "C" int fflush(FILE *);
extern "C" int printf(const char *, ...);
extern "C" int usleep(unsigned int);
extern "C" int open(const char *, int, ...);
extern "C" long read(int, void *, unsigned long);
extern "C" long write(int, const void *, unsigned long);
extern "C" int close(int);
extern "C" int dup2(int, int);
extern "C" int *__error(void);
extern "C" void _exit(int);

static CFTypeRef controllerSubscription;
static CFMutableDictionaryRef controllerChannels;
static CFDictionaryRef controllerPrevious;
static double controllerBefore;
static CFDictionaryRef (*controllerSample)(CFTypeRef, CFMutableDictionaryRef, CFTypeRef);
static CFDictionaryRef (*controllerDelta)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
static int64_t (*controllerValue)(CFDictionaryRef, int);
static CFStringRef (*controllerName)(CFDictionaryRef);
static CFStringRef (*controllerUnit)(CFDictionaryRef);
static int (*controllerFormat)(CFDictionaryRef);

int gpu_bridge_prepare(const char *output) {
    @autoreleasepool {
        void *library = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW);
        if (!library) return 1;
        auto channelsForGroup = (CFDictionaryRef (*)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t))dlsym(library, "IOReportCopyChannelsInGroup");
        auto subscribe = (CFTypeRef (*)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFErrorRef *))dlsym(library, "IOReportCreateSubscription");
        controllerSample = (CFDictionaryRef (*)(CFTypeRef, CFMutableDictionaryRef, CFTypeRef))dlsym(library, "IOReportCreateSamples");
        controllerDelta = (CFDictionaryRef (*)(CFDictionaryRef, CFDictionaryRef, CFTypeRef))dlsym(library, "IOReportCreateSamplesDelta");
        controllerValue = (int64_t (*)(CFDictionaryRef, int))dlsym(library, "IOReportSimpleGetIntegerValue");
        controllerName = (CFStringRef (*)(CFDictionaryRef))dlsym(library, "IOReportChannelGetChannelName");
        controllerUnit = (CFStringRef (*)(CFDictionaryRef))dlsym(library, "IOReportChannelGetUnitLabel");
        controllerFormat = (int (*)(CFDictionaryRef))dlsym(library, "IOReportChannelGetFormat");
        if (!channelsForGroup || !subscribe || !controllerSample || !controllerDelta || !controllerValue || !controllerName || !controllerUnit || !controllerFormat) return 1;
        NSDictionary *channels = (__bridge_transfer NSDictionary *)channelsForGroup((__bridge CFStringRef)@"AMC Stats", NULL, 0, 0, 0);
        NSMutableDictionary *selected = [channels mutableCopy];
        NSMutableArray *gpu = [NSMutableArray array];
        for (NSDictionary *channel in channels[@"IOReportChannels"]) {
            CFDictionaryRef item = (__bridge CFDictionaryRef)channel;
            NSString *name = (__bridge NSString *)controllerName(item);
            if ([name isEqualToString:@"PRIM GFX DCS RD"] || [name isEqualToString:@"PRIM GFX DCS WR"]) {
                if (controllerFormat(item) != 1 || ![(__bridge NSString *)controllerUnit(item) isEqualToString:@"B"]) return 1;
                [gpu addObject:channel];
            }
        }
        if (gpu.count != 2) return 1;
        selected[@"IOReportChannels"] = gpu;
        CFErrorRef error = NULL;
        controllerSubscription = subscribe(NULL, (__bridge CFMutableDictionaryRef)selected, &controllerChannels, 0, &error);
        if (!controllerSubscription || !controllerChannels) {
            printf("AMC subscription failed: %s\n", error ? [(__bridge NSError *)error description].UTF8String : "unavailable");
            if (error) CFRelease(error);
            return 2;
        }
        if (error) CFRelease(error);
        controllerPrevious = controllerSample(controllerSubscription, controllerChannels, NULL);
        controllerBefore = NSProcessInfo.processInfo.systemUptime;
        return controllerPrevious ? 0 : 3;
    }
}

static int dashboard_capture_controller(const char *output) {
    @autoreleasepool {
        usleep(1000000);
        CFDictionaryRef current = controllerSample(controllerSubscription, controllerChannels, NULL);
        double now = NSProcessInfo.processInfo.systemUptime;
        if (!current) return 1;
        CFDictionaryRef diff = controllerDelta(controllerPrevious, current, NULL);
        double seconds = now - controllerBefore;
        CFRelease(controllerPrevious);
        controllerPrevious = current;
        controllerBefore = now;
        if (!diff) return 1;
        NSMutableDictionary *bytes = [NSMutableDictionary dictionary];
        for (NSDictionary *channel in ((__bridge NSDictionary *)diff)[@"IOReportChannels"]) {
            CFDictionaryRef item = (__bridge CFDictionaryRef)channel;
            NSString *name = (__bridge NSString *)controllerName(item);
            if (controllerFormat(item) == 1 && [(__bridge NSString *)controllerUnit(item) isEqualToString:@"B"])
                bytes[name] = @(controllerValue(item, 0));
        }
        CFRelease(diff);
        NSNumber *readBytes = bytes[@"PRIM GFX DCS RD"], *writeBytes = bytes[@"PRIM GFX DCS WR"];
        if (!readBytes || !writeBytes || readBytes.longLongValue < 0 || writeBytes.longLongValue < 0 || seconds <= 0 || seconds > 10) return 1;
        NSDictionary *result = @{@"read_bytes":readBytes, @"write_bytes":writeBytes, @"seconds":@(seconds), @"timestamp":@(NSDate.date.timeIntervalSince1970)};
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
        NSString *path = [@(output) stringByAppendingPathComponent:@"controller.json"];
        return data && [data writeToFile:path atomically:YES] ? 0 : 1;
    }
}

int gpu_bridge_stream(const char *output, const char *control, const char *response) {
    int input = open(control, 0), resultFD = open(response, 1);
    if (input < 0 || resultFD < 0) _exit(1);
    int nullFD = open("/dev/null", 1);
    if (nullFD < 0) _exit(1);
    dup2(nullFD, 1); dup2(nullFD, 2); close(nullFD);
    for (;;) {
        char command = 0;
        long received = read(input, &command, 1);
        if (received < 0 && *__error() == 4) continue;
        if (received != 1 || command == 'q') break;
        if (command != 's') break;
        char result = (char)('0' + dashboard_capture_controller(output));
        if (write(resultFD, &result, 1) != 1) break;
    }
    CFRelease(controllerPrevious);
    CFRelease(controllerChannels);
    CFRelease(controllerSubscription);
    close(input); close(resultFD);
    _exit(0);
}
