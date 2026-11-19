#ifndef GPU_COUNTERS_H
#define GPU_COUNTERS_H

/* Apple GPU clock and power from IOReport, without root.
 *
 * Each call to gpu_counters_read() reports the interval since the previous
 * call: the residency-weighted average clock of the GPU while it was active,
 * the share of the interval it was active, and its average power. The first
 * call only primes the counters and returns 0.
 *
 * Sources, as read by macmon: the "GPU Stats / GPU Performance States" GPUPH
 * state residencies, the clock table in the pmgr registry entry's
 * "voltage-states9" property, and the "Energy Model" "GPU Energy" counter.
 * Only those two channels are subscribed; one read costs about 85 us on an
 * M5 Max, against about 5 ms for the whole Energy Model group.
 * libIOReport is loaded at run time; on failure every call returns 0.
 * Not thread-safe: one caller at a time. */

typedef struct {
    double mhz;          /* average clock while active; 0 when never active */
    double active;       /* active share of the interval, 0..1 */
    double watts;        /* average GPU power; negative when unavailable */
    double seconds;      /* length of the interval */
} gpu_counters_reading;

int gpu_counters_read(gpu_counters_reading *out);

#ifdef GPU_COUNTERS_IMPLEMENTATION

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

typedef const void *gpu_counters_sub;

static struct {
    int state;                     /* 0 unopened, 1 ready, -1 unavailable */
    CFDictionaryRef (*copy_group)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
    void (*merge)(CFMutableDictionaryRef, CFDictionaryRef, CFTypeRef);
    gpu_counters_sub (*subscribe)(const void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
    CFDictionaryRef (*sample)(gpu_counters_sub, CFMutableDictionaryRef, CFTypeRef);
    CFDictionaryRef (*delta)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
    CFStringRef (*group)(CFDictionaryRef);
    CFStringRef (*subgroup)(CFDictionaryRef);
    CFStringRef (*channel)(CFDictionaryRef);
    CFStringRef (*unit)(CFDictionaryRef);
    int64_t (*integer)(CFDictionaryRef, int32_t);
    int32_t (*state_count)(CFDictionaryRef);
    CFStringRef (*state_name)(CFDictionaryRef, int32_t);
    int64_t (*residency)(CFDictionaryRef, int32_t);
    gpu_counters_sub sub;
    CFMutableDictionaryRef subscribed;
    CFDictionaryRef previous;
    uint64_t previous_ns;
    double mhz[64];                /* clock of each active GPUPH state */
    int n_mhz;
    int first_active;              /* index of the first clocked GPUPH state */
} g_gpu_counters;

static int gpu_counters_is(CFStringRef s, const char *want) {
    char buf[96];
    return s && CFStringGetCString(s, buf, sizeof(buf), kCFStringEncodingUTF8) && !strcmp(buf, want);
}

static int gpu_counters_clock_table(void) {
    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &it))
        return 0;
    io_object_t entry;
    while ((entry = IOIteratorNext(it)) && !g_gpu_counters.n_mhz) {
        io_name_t name;
        if (IORegistryEntryGetName(entry, name) == KERN_SUCCESS &&
            (!strcmp(name, "pmgr") || !strcmp(name, "pmgr-child"))) {
            CFTypeRef data = IORegistryEntryCreateCFProperty(entry, CFSTR("voltage-states9"),
                                                             kCFAllocatorDefault, 0);
            if (data && CFGetTypeID(data) == CFDataGetTypeID()) {
                const CFIndex len = CFDataGetLength(data);
                const uint8_t *p = CFDataGetBytePtr(data);
                /* (Hz, voltage) pairs; entry 0 is the OFF state */
                for (CFIndex i = 1; i < len / 8 && g_gpu_counters.n_mhz < 64; i++) {
                    uint32_t hz;
                    memcpy(&hz, p + i * 8, 4);
                    g_gpu_counters.mhz[g_gpu_counters.n_mhz++] = hz / 1e6;
                }
            }
            if (data) CFRelease(data);
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(it);
    return g_gpu_counters.n_mhz > 0;
}

static int gpu_counters_open(void) {
    void *lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (!lib) return 0;
#define GPU_COUNTERS_SYM(field, name) \
    if (!(*(void **)&g_gpu_counters.field = dlsym(lib, name))) return 0;
    GPU_COUNTERS_SYM(copy_group, "IOReportCopyChannelsInGroup")
    GPU_COUNTERS_SYM(merge, "IOReportMergeChannels")
    GPU_COUNTERS_SYM(subscribe, "IOReportCreateSubscription")
    GPU_COUNTERS_SYM(sample, "IOReportCreateSamples")
    GPU_COUNTERS_SYM(delta, "IOReportCreateSamplesDelta")
    GPU_COUNTERS_SYM(group, "IOReportChannelGetGroup")
    GPU_COUNTERS_SYM(subgroup, "IOReportChannelGetSubGroup")
    GPU_COUNTERS_SYM(channel, "IOReportChannelGetChannelName")
    GPU_COUNTERS_SYM(unit, "IOReportChannelGetUnitLabel")
    GPU_COUNTERS_SYM(integer, "IOReportSimpleGetIntegerValue")
    GPU_COUNTERS_SYM(state_count, "IOReportStateGetCount")
    GPU_COUNTERS_SYM(state_name, "IOReportStateGetNameForIndex")
    GPU_COUNTERS_SYM(residency, "IOReportStateGetResidency")
#undef GPU_COUNTERS_SYM
    if (!gpu_counters_clock_table()) return 0;
    CFDictionaryRef states = g_gpu_counters.copy_group(CFSTR("GPU Stats"),
                                                       CFSTR("GPU Performance States"), 0, 0, 0);
    if (!states) return 0;
    CFMutableDictionaryRef channels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, states);
    CFRelease(states);
    CFDictionaryRef energy = g_gpu_counters.copy_group(CFSTR("Energy Model"), NULL, 0, 0, 0);
    CFArrayRef all = energy ? CFDictionaryGetValue(energy, CFSTR("IOReportChannels")) : NULL;
    if (all) {
        CFMutableArrayRef keep = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
        for (CFIndex i = 0; i < CFArrayGetCount(all); i++) {
            CFDictionaryRef item = CFArrayGetValueAtIndex(all, i);
            if (gpu_counters_is(g_gpu_counters.channel(item), "GPU Energy")) CFArrayAppendValue(keep, item);
        }
        CFMutableDictionaryRef gpu_energy = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, energy);
        CFDictionarySetValue(gpu_energy, CFSTR("IOReportChannels"), keep);
        g_gpu_counters.merge(channels, gpu_energy, NULL);
        CFRelease(gpu_energy);
        CFRelease(keep);
    }
    if (energy) CFRelease(energy);
    g_gpu_counters.sub = g_gpu_counters.subscribe(NULL, channels, &g_gpu_counters.subscribed, 0, NULL);
    CFRelease(channels);
    return g_gpu_counters.sub && g_gpu_counters.subscribed;
}

int gpu_counters_read(gpu_counters_reading *out) {
    if (!g_gpu_counters.state) g_gpu_counters.state = gpu_counters_open() ? 1 : -1;
    if (g_gpu_counters.state < 0) return 0;
    CFDictionaryRef now = g_gpu_counters.sample(g_gpu_counters.sub, g_gpu_counters.subscribed, NULL);
    const uint64_t now_ns = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (!now) return 0;
    CFDictionaryRef prev = g_gpu_counters.previous;
    const uint64_t prev_ns = g_gpu_counters.previous_ns;
    g_gpu_counters.previous = now;
    g_gpu_counters.previous_ns = now_ns;
    if (!prev) return 0;
    CFDictionaryRef d = g_gpu_counters.delta(prev, now, NULL);
    CFRelease(prev);
    if (!d) return 0;

    const double seconds = (now_ns - prev_ns) / 1e9;
    double weighted = 0, active = 0, total = 0, joules = -1;
    CFArrayRef items = CFDictionaryGetValue(d, CFSTR("IOReportChannels"));
    const CFIndex n = items ? CFArrayGetCount(items) : 0;
    for (CFIndex i = 0; i < n; i++) {
        CFDictionaryRef item = CFArrayGetValueAtIndex(items, i);
        CFStringRef channel = g_gpu_counters.channel(item);
        if (gpu_counters_is(channel, "GPUPH") &&
            gpu_counters_is(g_gpu_counters.subgroup(item), "GPU Performance States")) {
            /* OFF (or IDLE/DOWN) first, then states P1.. matching the clock
             * table in order; states past the table count as inactive */
            const int count = g_gpu_counters.state_count(item);
            if (!g_gpu_counters.first_active) {
                for (int s = 0; s < count && !g_gpu_counters.first_active; s++) {
                    CFStringRef name = g_gpu_counters.state_name(item, s);
                    if (!gpu_counters_is(name, "OFF") && !gpu_counters_is(name, "IDLE") &&
                        !gpu_counters_is(name, "DOWN"))
                        g_gpu_counters.first_active = s ? s : -1;
                }
            }
            const int first = g_gpu_counters.first_active < 0 ? 0 : g_gpu_counters.first_active;
            for (int s = 0; s < count; s++) {
                const double r = (double)g_gpu_counters.residency(item, s);
                total += r;
                if (s >= first && s - first < g_gpu_counters.n_mhz) {
                    active += r;
                    weighted += r * g_gpu_counters.mhz[s - first];
                }
            }
        } else if (gpu_counters_is(channel, "GPU Energy") &&
                   gpu_counters_is(g_gpu_counters.group(item), "Energy Model")) {
            const double v = (double)g_gpu_counters.integer(item, 0);
            CFStringRef unit = g_gpu_counters.unit(item);
            const double scale = gpu_counters_is(unit, "mJ") ? 1e-3 :
                                 gpu_counters_is(unit, "uJ") ? 1e-6 :
                                 gpu_counters_is(unit, "nJ") ? 1e-9 : 0;
            if (scale) joules = (joules < 0 ? 0 : joules) + v * scale;
        }
    }
    CFRelease(d);
    out->mhz = active > 0 ? weighted / active : 0;
    out->active = total > 0 ? active / total : 0;
    out->watts = joules >= 0 && seconds > 0 ? joules / seconds : -1;
    out->seconds = seconds;
    return total > 0;
}

#endif /* GPU_COUNTERS_IMPLEMENTATION */
#endif
