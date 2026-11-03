// Read-only Apple Silicon metrics. Mach + IOKit + SMC, no root required.
#include "metrics.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>
#include <mach/mach.h>
#include <mach/host_info.h>
#include <mach/vm_statistics.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <ctype.h>
#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const double gib = 1024.0 * 1024.0 * 1024.0;
// Heuristic, not a measurement or attribution to ML. Kept in this one core.
static const double kernel_wired_baseline_gb = 3.4;

typedef struct { char *data; int capacity; int length; } JSON;

static void append(JSON *out, const char *format, ...) {
    if (out->length >= out->capacity - 1) return;
    va_list args;
    va_start(args, format);
    int length = vsnprintf(out->data + out->length, out->capacity - out->length, format, args);
    va_end(args);
    if (length > 0) out->length += length;
}

static void string(JSON *out, const char *value) {
    append(out, "\"");
    for (const unsigned char *p = (const unsigned char *)value; *p; p++) {
        if (*p == '"' || *p == '\\') append(out, "\\%c", *p);
        else if (*p < 32) append(out, "\\u%04x", *p);
        else append(out, "%c", *p);
    }
    append(out, "\"");
}

static void number(JSON *out, double value) {
    if (isfinite(value)) append(out, "%.3f", value);
    else append(out, "null");
}

static double dictionary_number(CFDictionaryRef dictionary, CFStringRef key) {
    if (!dictionary) return NAN;
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    double result = NAN;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID())
        CFNumberGetValue(value, kCFNumberDoubleType, &result);
    return result;
}

static void field(JSON *out, const char *key, double value) {
    append(out, "\"%s\":", key);
    number(out, value);
}

static void memory(JSON *out) {
    host_t host = mach_host_self();
    vm_statistics64_data_t vm = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_size_t page_size = 0;
    kern_return_t result = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count);
    host_page_size(host, &page_size);
    mach_port_deallocate(mach_task_self(), host);
    uint64_t bytes = 0;
    size_t size = sizeof(bytes);
    if (result != KERN_SUCCESS || !page_size || sysctlbyname("hw.memsize", &bytes, &size, NULL, 0)) {
        append(out, "{}");
        return;
    }
    double scale = (double)page_size / gib;
    double total = bytes / gib;
    double free = vm.free_count * scale;
    double inactive = vm.inactive_count * scale;
    double active = vm.active_count * scale;
    double wired = vm.wire_count * scale;
    double compressor = vm.compressor_page_count * scale;
    // free_count already includes speculative pages. Purgeable pages overlap
    // page queues too. Do not add either again to this availability estimate.
    double reclaimable = fmin(total, free + inactive);
    double in_use = fmin(total, active + wired + compressor);
    append(out, "{");
    field(out, "total_gb", total);
    append(out, ","); field(out, "free_gb", free);
    append(out, ","); field(out, "active_gb", active);
    append(out, ","); field(out, "inactive_gb", inactive);
    append(out, ","); field(out, "speculative_gb", vm.speculative_count * scale);
    append(out, ","); field(out, "wired_gb", wired);
    append(out, ","); field(out, "purgeable_gb", vm.purgeable_count * scale);
    append(out, ","); field(out, "compressor_gb", compressor);
    append(out, ","); field(out, "reclaimable_gb", reclaimable);
    append(out, ","); field(out, "in_use_gb", in_use);
    append(out, ","); field(out, "free_pct", total ? reclaimable * 100 / total : NAN);
    append(out, ",\"wired_context\":{");
    field(out, "kernel_baseline_gb", fmin(wired, kernel_wired_baseline_gb));
    append(out, ","); field(out, "other_wired_estimate_gb", fmax(0, wired - kernel_wired_baseline_gb));
    append(out, "}}");
}

static void top_processes(JSON *out) {
    FILE *process = popen("/bin/ps -A -o pid=,pcpu=,comm= -r", "r");
    append(out, "[");
    if (process) {
        char line[4096];
        int count = 0;
        // Drain ps even after collecting six rows, then reap it normally.
        while (fgets(line, sizeof(line), process)) {
            int pid, offset = 0;
            double percent;
            if (count >= 6 || sscanf(line, "%d %lf %n", &pid, &percent, &offset) != 2) continue;
            char *name = line + offset;
            name[strcspn(name, "\r\n")] = '\0';
            char *basename = strrchr(name, '/');
            if (basename) name = basename + 1;
            if (count++) append(out, ",");
            append(out, "{\"pid\":%d,\"cpu\":", pid);
            number(out, percent);
            append(out, ",\"name\":"); string(out, name);
            append(out, "}");
        }
        pclose(process);
    }
    append(out, "]");
}

static void cpu(JSON *out, int full) {
    int cores = 0;
    size_t size = sizeof(cores);
    sysctlbyname("hw.activecpu", &cores, &size, NULL, 0);
    double load[3] = {NAN, NAN, NAN};
    getloadavg(load, 3); // libc decodes the fixed-point vm.loadavg structure.
    char model[256] = "Unknown";
    size = sizeof(model);
    sysctlbyname("hw.model", model, &size, NULL, 0);

    static natural_t previous[CPU_STATE_MAX];
    static int sampled = 0;
    host_cpu_load_info_data_t ticks = {0};
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    host_t host = mach_host_self();
    double utilization = NAN;
    if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&ticks, &count) == KERN_SUCCESS) {
        uint64_t total = 0, busy = 0;
        for (int i = 0; i < CPU_STATE_MAX; i++) {
            natural_t delta = ticks.cpu_ticks[i] - previous[i];
            total += delta;
            if (i != CPU_STATE_IDLE) busy += delta;
            previous[i] = ticks.cpu_ticks[i];
        }
        if (sampled && total) utilization = 100.0 * busy / total;
        sampled = 1;
    }
    mach_port_deallocate(mach_task_self(), host);
    append(out, "{\"count\":%d,\"model\":", cores); string(out, model);
    append(out, ","); field(out, "utilization", utilization);
    append(out, ","); field(out, "load_avg", load[0]);
    append(out, ",\"top\":");
    if (full) top_processes(out); else append(out, "[]");
    append(out, "}");
}

static void gpu(JSON *out) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"));
    CFMutableDictionaryRef properties = NULL;
    if (!service) { append(out, "{}"); return; }
    kern_return_t result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS || !properties) { append(out, "{}"); return; }
    CFDictionaryRef stats = CFDictionaryGetValue(properties, CFSTR("PerformanceStatistics"));
    if (!stats || CFGetTypeID(stats) != CFDictionaryGetTypeID()) stats = properties;
    char model[256] = "Apple GPU";
    CFTypeRef name = CFDictionaryGetValue(properties, CFSTR("model"));
    if (name && CFGetTypeID(name) == CFStringGetTypeID())
        CFStringGetCString(name, model, sizeof(model), kCFStringEncodingUTF8);
    append(out, "{\"model\":"); string(out, model);
    append(out, ","); field(out, "core_count", dictionary_number(properties, CFSTR("gpu-core-count")));
    append(out, ","); field(out, "utilization", dictionary_number(stats, CFSTR("Device Utilization %")));
    append(out, ","); field(out, "renderer_util", dictionary_number(stats, CFSTR("Renderer Utilization %")));
    append(out, ","); field(out, "tiler_util", dictionary_number(stats, CFSTR("Tiler Utilization %")));
    append(out, ","); field(out, "alloc_sys_mem_gb", dictionary_number(stats, CFSTR("Alloc system memory")) / gib);
    append(out, ","); field(out, "in_use_sys_mem_gb", dictionary_number(stats, CFSTR("In use system memory")) / gib);
    append(out, "}");
    CFRelease(properties);
}

// Natural 80-byte alignment required by AppleSMC. Never pack this structure.
typedef struct {
    uint32_t key;
    uint8_t vers_major, vers_minor, vers_build, vers_reserved;
    uint16_t vers_release;
    uint16_t limit_version, limit_length;
    uint32_t cpu_limit, gpu_limit, memory_limit;
    uint32_t data_size, data_type;
    uint8_t attributes, pad1;
    uint16_t padding;
    uint8_t result, status, command, pad2;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

static io_connect_t smc_connection;

static double smc_read(const char *key) {
    if (!smc_connection) {
        io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
        if (!service) return NAN;
        kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &smc_connection);
        IOObjectRelease(service);
        if (result != KERN_SUCCESS) { smc_connection = 0; return NAN; }
    }
    SMCKeyData in = {0}, out = {0};
    in.key = ((uint32_t)(uint8_t)key[0] << 24) | ((uint32_t)(uint8_t)key[1] << 16)
           | ((uint32_t)(uint8_t)key[2] << 8) | (uint8_t)key[3];
    in.command = 9; // Read key info.
    size_t size = sizeof(out);
    if (IOConnectCallStructMethod(smc_connection, 2, &in, sizeof(in), &out, &size) != KERN_SUCCESS
        || out.result || !out.data_size || out.data_size > sizeof(out.bytes)) return NAN;
    uint32_t type = out.data_type;
    in.data_size = out.data_size;
    in.command = 5; // Read bytes.
    memset(&out, 0, sizeof(out));
    size = sizeof(out);
    if (IOConnectCallStructMethod(smc_connection, 2, &in, sizeof(in), &out, &size) != KERN_SUCCESS
        || out.result) return NAN;
    const uint8_t *bytes = out.bytes;
    uint32_t word = ((uint32_t)bytes[0] << 8) | bytes[1];
    switch (type) {
        case 'ui8 ': return bytes[0];
        case 'ui16': return word;
        case 'ui32': return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16)
                          | ((uint32_t)bytes[2] << 8) | bytes[3];
        case 'sp78': return (int16_t)word / 256.0;
        case 'sp87': return (int16_t)word / 128.0;
        case 'sp96': return (int16_t)word / 64.0;
        case 'sp4b': return (int16_t)word / 2048.0;
        case 'sp5a': return (int16_t)word / 1024.0;
        case 'sp69': return (int16_t)word / 512.0;
        case 'sp1e': return (int16_t)word / 16384.0;
        case 'sp3c': return (int16_t)word / 4096.0;
        case 'fpe2': return word / 4.0;
        case 'flt ': { float value; memcpy(&value, bytes, sizeof(value)); return value; }
        default: return NAN;
    }
}

// M5 Max sensor groups from the original dashboard's SMC scan.
static const char *cpu_keys[] = {
    "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R",
    "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p",
    "Tp0u", "Tp0y", "Tp1E", "Tp1I", "Tp1Q", "Tp1U", "Tp1g", NULL
};
static const char *gpu_keys[] = {
    "Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg12", "Tg16", "Tg1I",
    "Tg1M", "Tg1Q", "Tg1U", "Tg1Y", "Tg1c", "Tg1k", "Tg1o", "Tg1x",
    "Tg29", "Tg2D", "Tg2P", "Tg2T", "Tg2X", "Tg2b", "Tg2f", "Tg2j",
    "Tg2n", "Tg2r", "Tg3B", "Tg3F", "Tg3R", "Tg3V", "Tg3Z", "Tg3d",
    "Tg3h", "Tg3l", "Tg3t", "Tg3x", "Tg43", "Tg4D", "Tg4G", "Tg4P",
    "Tg4S", "Tg4V", "Tg4Y", "Tg4b", "Tg4e", "Tg4h", "Tg4k", "Tg50",
    "Tg53", "Tg5C", "Tg5F", "Tg5I", "Tg5L", "Tg5O", "Tg5R", "Tg5Y",
    "Tg5b", "Tg5h", "Tg5q", "Tg5t", "Tg63", "Tg66", "Tg69", "Tg6C",
    "Tg6F", "Tg6I", "Tg6L", "Tg6O", "Tg6e", "Tg6h", "Tg6q", "Tg6t",
    "Tg6w", "Tg70", "Tg73", "Tg76", "Tg7C", "Tg7F", "Tg7L", NULL
};
static const char *memory_keys[] = {
    "Tm00", "Tm04", "Tm08", "Tm0C", "Tm0G", "Tm0K", "Tm0O", "Tm0R",
    "Tm0U", "Tm0X", "Tm0a", "Tm0d", "Tm0g", "Tm0j", "Tm0m", "Tm0p",
    "Tm0u", "Tm0y", "Tm1E", "Tm1I", "Tm1M", "Tm1Q", "Tm1U", "Tm1Y",
    "Tm1c", "Tm1g", "Tm1k", "Tm1o", "Tm1s", "Tm1x", "Tm21", "Tm25",
    "Tm29", "Tm2D", "Tm2H", "Tm2L", "Tm2P", "Tm2T", "Tm2j", "Tm2n", NULL
};

static double thermal_peaks[4] = {NAN, NAN, NAN, NAN};

static void temperature_group(JSON *out, const char *name, const char **keys, int index) {
    double sum = 0, hottest = NAN;
    int count = 0;
    for (int i = 0; keys[i]; i++) {
        double value = smc_read(keys[i]);
        if (isfinite(value) && value > 0 && value < 150) {
            sum += value;
            count++;
            if (!isfinite(hottest) || value > hottest) hottest = value;
        }
    }
    if (isfinite(hottest) && (!isfinite(thermal_peaks[index]) || hottest > thermal_peaks[index]))
        thermal_peaks[index] = hottest;
    // Keep the original average in JSON, but never relabel it as "current".
    append(out, "\"%s_avg\":", name); number(out, count ? sum / count : NAN);
    append(out, ",\"%s_max\":", name); number(out, hottest);
    append(out, ",\"%s_peak\":", name); number(out, thermal_peaks[index]);
    append(out, ",\"%s_count\":%d", name, count);
}

static void thermals(JSON *out) {
    append(out, "{"); temperature_group(out, "cpu", cpu_keys, 0);
    append(out, ","); temperature_group(out, "gpu", gpu_keys, 1);
    append(out, ","); temperature_group(out, "mem", memory_keys, 2);
    double soc = smc_read("TS0P");
    if (isfinite(soc) && (soc <= 0 || soc > 150)) soc = NAN;
    if (isfinite(soc) && (!isfinite(thermal_peaks[3]) || soc > thermal_peaks[3])) thermal_peaks[3] = soc;
    append(out, ","); field(out, "soc", soc);
    append(out, ","); field(out, "soc_peak", thermal_peaks[3]);
    append(out, "}");
}

static void fans(JSON *out) {
    double reading = smc_read("FNum");
    int count = isfinite(reading) ? (int)reading : 0;
    if (count < 0) count = 0;
    if (count > 4) count = 4;
    append(out, "{\"count\":%d", count);
    for (int i = 0; i < count; i++) {
        char key[8];
        append(out, ",\"F%d\":{", i);
        snprintf(key, sizeof(key), "F%dAc", i); field(out, "rpm", smc_read(key));
        snprintf(key, sizeof(key), "F%dMn", i); append(out, ","); field(out, "min", smc_read(key));
        snprintf(key, sizeof(key), "F%dMx", i); append(out, ","); field(out, "max", smc_read(key));
        append(out, "}");
    }
    append(out, "}");
}

static void power(JSON *out) {
    double percent = NAN;
    int external = 0;
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    CFArrayRef sources = info ? IOPSCopyPowerSourcesList(info) : NULL;
    for (CFIndex i = 0; sources && i < CFArrayGetCount(sources); i++) {
        CFDictionaryRef source = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(sources, i));
        CFTypeRef type = source ? CFDictionaryGetValue(source, CFSTR(kIOPSTypeKey)) : NULL;
        if (!type || !CFEqual(type, CFSTR(kIOPSInternalBatteryType))) continue;
        double current = dictionary_number(source, CFSTR(kIOPSCurrentCapacityKey));
        double maximum = dictionary_number(source, CFSTR(kIOPSMaxCapacityKey));
        if (maximum > 0) percent = current * 100 / maximum;
        CFTypeRef state = CFDictionaryGetValue(source, CFSTR(kIOPSPowerSourceStateKey));
        external = state && CFEqual(state, CFSTR(kIOPSACPowerValue));
        break;
    }
    if (sources) CFRelease(sources);
    if (info) CFRelease(info);
    double system_watts = smc_read("PSTR");
    double adapter_watts = external ? smc_read("VD0R") * smc_read("ID0R") : 0;
    double net_watts = adapter_watts - system_watts;
    append(out, "{"); field(out, "battery_pct", percent);
    append(out, ",\"external_connected\":%s,", external ? "true" : "false");
    field(out, "system_watts", system_watts);
    append(out, ","); field(out, "adapter_watts", adapter_watts);
    append(out, ","); field(out, "net_watts", net_watts);
    append(out, "}");
}

void m5_sample(char *buffer, int capacity, int full) {
    JSON out = {buffer, capacity, 0};
    struct timeval now;
    gettimeofday(&now, NULL);
    append(&out, "{\"sampled_at\":%.3f,\"memory\":", now.tv_sec + now.tv_usec / 1000000.0);
    memory(&out);
    append(&out, ",\"cpu\":"); cpu(&out, full);
    if (full) { append(&out, ",\"gpu\":"); gpu(&out); }
    int32_t pressure = 0;
    size_t size = sizeof(pressure);
    int pressure_result = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, NULL, 0);
    const char *label = pressure_result ? "UNKNOWN" : pressure == 4 ? "CRITICAL" : pressure >= 2 ? "MODERATE" : "OK";
    append(&out, ",\"memory_pressure\":"); string(&out, label);
    append(&out, ",\"swap\":{");
    struct xsw_usage swap = {0};
    size = sizeof(swap);
    int result = sysctlbyname("vm.swapusage", &swap, &size, NULL, 0);
    field(&out, "total_mb", result ? NAN : swap.xsu_total / (1024.0 * 1024.0));
    append(&out, ","); field(&out, "used_mb", result ? NAN : swap.xsu_used / (1024.0 * 1024.0));
    append(&out, "},\"uptime_seconds\":");
    struct timeval boot = {0};
    size = sizeof(boot);
    result = sysctlbyname("kern.boottime", &boot, &size, NULL, 0);
    number(&out, result ? NAN : now.tv_sec - boot.tv_sec);
    append(&out, ",\"power\":"); power(&out);
    if (full) {
        append(&out, ",\"thermals\":"); thermals(&out);
        append(&out, ",\"fans\":"); fans(&out);
    }
    append(&out, "}");
    if (out.length >= capacity) snprintf(buffer, capacity, "{\"error\":\"metrics buffer full\"}");
}
