@import Foundation;
@import Darwin;
@interface XRGPUAPSDataProcessor : NSObject
+ (id)processorFromConfig:(NSDictionary *)config options:(unsigned)options;
- (unsigned long long)agxpsGPU;
@end
typedef void *(*create_fn)(void *, unsigned *);
typedef void *(*parse_fn)(void *, void *, unsigned long long, int, unsigned *);
typedef unsigned (*num_fn)(void *);
typedef unsigned long long (*ull_fn)(void *);
typedef int (*names_fn)(void *, const char **, unsigned long long, unsigned long long);
typedef int (*counts_fn)(void *, unsigned long long *, unsigned long long, unsigned long long);
typedef int (*values_fn)(void *, double **, unsigned long long, unsigned long long);
typedef int (*gid_fn)(void *, unsigned char *, unsigned);
typedef int (*metadata_fn)(void *, unsigned long long **, unsigned long long, unsigned long long);
typedef int (*interpolate_fn)(void *, const unsigned long long *, unsigned long long, unsigned long long *);
typedef unsigned long long (*timestamp_fn)(void *, unsigned long long);
static void *library(void) {
    return dlopen("/Applications/Xcode.app/Contents/PlugIns/GPUDebugger.ideplugin/Contents/Frameworks/GTShaderProfiler.framework/GTShaderProfiler", RTLD_NOW);
}
static id make_processor(const char *path) {
    library();
    NSDictionary *catalog = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(path)] options:0 error:NULL];
    NSDictionary *core = catalog[@"features"][@"ConstantAGX_CoreConfig"];
    if (!core) return nil;
    return [(id)NSClassFromString(@"XRGPUAPSDataProcessor") processorFromConfig:@{@"GPUConfigurationVariables":core, @"PulsePeriod":@2048, @"CountPeriod":@32768, @"SystemTimePeriod":@8192} options:0];
}
static NSSet *throughput_tracks(id processor) {
    void *lib = library();
    typedef unsigned long long ID;
    ID gpu = [processor agxpsGPU];
    ID metric = ((ID (*)(ID, const char *))dlsym(lib, "agxps_counter_get_ident"))(gpu, "Shader Core Utilization");
    ID *ids = NULL, count = 0;
    BOOL ok = ((bool (*)(ID, const ID *, ID, ID **, ID *))dlsym(lib, "agxps_counter_get_raw_counters_used_by_derived_counters"))(gpu, &metric, 1, &ids, &count);
    if (!ok || !count || count > 4096) { free(ids); return nil; }
    NSMutableSet *names = [NSMutableSet set];
    for (ID i = 0; i < count; i++) {
        const char *name = ((const char *(*)(ID))dlsym(lib, "agxps_counter_get_name"))(ids[i]);
        if (!name) { free(ids); return nil; }
        [names addObject:@(name)];
    }
    free(ids);
    return names;
}
static int dump_ring(int argc, char **argv, id processor, NSSet *wanted) { @autoreleasepool {
    if (argc < 4) { fprintf(stderr, "usage: aps-dump CATALOG RING OUT.json [OFFSET]\n"); return 2; }
    void *lib = library();
    if (!processor) processor = make_processor(argv[1]);
    if (!processor) return 2;
    void *descriptor = (char *)(__bridge void *)processor + 0x20;
    unsigned error = 0;
    void *parser = ((create_fn)dlsym(lib, "agxps_aps_parser_create"))(descriptor, &error);
    NSData *data = [NSData dataWithContentsOfFile:@(argv[2])];
    unsigned long long off = argc > 4 ? strtoull(argv[4], NULL, 0) : 4;
    if (!parser || !data || off >= data.length) { fprintf(stderr, "invalid parser/data/offset\n"); return 2; }
    void *profile = ((parse_fn)dlsym(lib, "agxps_aps_parser_parse"))(parser, (void *)((char *)data.bytes + off), data.length - off, 1, &error);
    if (!profile) { fprintf(stderr, "parse failed error=%u\n", error); return 1; }
    unsigned counters = ((num_fn)dlsym(lib, "agxps_aps_profile_data_get_counter_num"))(profile);
    if (!counters || counters > 4096) { fprintf(stderr, "unexpected counter count\n"); return 1; }
    const char *names[counters ?: 1];
    unsigned long long counts[counters ?: 1];
    double *values[counters ?: 1];
    int namesOK = ((names_fn)dlsym(lib, "agxps_aps_profile_data_get_counter_names"))(profile, names, 0, counters);
    int countsOK = ((counts_fn)dlsym(lib, "agxps_aps_profile_data_get_counter_values_num"))(profile, counts, 0, counters);
    int valuesOK = ((values_fn)dlsym(lib, "agxps_aps_profile_data_get_counter_values"))(profile, values, 0, counters);
    if (!namesOK || !countsOK || !valuesOK) { fprintf(stderr, "native counter export failed\n"); return 1; }
    gid_fn gidByIndex = (gid_fn)dlsym(lib, "agxps_aps_profile_data_get_counter_group_id_by_index");
    NSMutableArray *out = [NSMutableArray array];
    for (unsigned i = 0; i < counters; ++i) {
        if (wanted && ![wanted containsObject:@(names[i] ?: "")]) continue;
        if (counts[i] > 1000000 || (counts[i] && !values[i])) { fprintf(stderr, "invalid counter samples\n"); return 1; }
        NSMutableArray *v = [NSMutableArray array];
        unsigned long long *raw = (unsigned long long *)values[i];
        for (unsigned long long s = 0; s < counts[i]; ++s) [v addObject:@(raw[s])];
        unsigned char gid = 0; int gidOK = gidByIndex ? gidByIndex(profile, &gid, i) : 0;
        [out addObject:@{@"name": @(names[i] ?: ""), @"count": @(counts[i]), @"gid": @(gid), @"gid_ok": @(gidOK), @"values": v}];
    }
    // Recover group-0 sample timing through Apple's native interpolator. This
    // Xcode's setConfig: uses 125/3 ns per system tick; no guessed GPU clock.
    unsigned long long sampleCount = ULLONG_MAX;
    for (unsigned i = 0; i < counters; ++i) sampleCount = MIN(sampleCount, counts[i]);
    NSMutableDictionary *timing = [NSMutableDictionary dictionary];
    if (namesOK && countsOK && valuesOK && sampleCount >= 2 && sampleCount <= 1000000) {
        unsigned long long *refs = NULL;
        metadata_fn metadata = (metadata_fn)dlsym(lib, "agxps_aps_profile_data_get_counter_group_metadata");
        interpolate_fn interpolate = (interpolate_fn)dlsym(lib, "agxps_aps_profile_data_get_interpolated_system_timestamps");
        timestamp_fn uscTimestamp = (timestamp_fn)dlsym(lib, "agxps_aps_profile_data_get_usc_timestamp");
        ull_fn uscCount = (ull_fn)dlsym(lib, "agxps_aps_profile_data_get_usc_timestamps_num");
        counts_fn uscTimestamps = (counts_fn)dlsym(lib, "agxps_aps_profile_data_get_usc_timestamps");
        unsigned long long *ticks = calloc(sampleCount, sizeof(*ticks));
        if (!ticks) return 2;
        BOOL ok = metadata && interpolate && uscTimestamp && uscCount && uscTimestamps &&
                  metadata(profile, &refs, 0, 1) && refs && interpolate(profile, refs, sampleCount, ticks);
        NSMutableArray *cycles = [NSMutableArray array], *seconds = [NSMutableArray array];
        NSMutableArray *references = [NSMutableArray array], *timestamps = [NSMutableArray array];
        unsigned long long prevCycles = 0, prevNs = 0, monotonicClamps = 0;
        for (unsigned long long s = 0; ok && s < sampleCount; ++s) {
            unsigned long long index = refs[s] >> 32;
            if (index >= uscCount(profile)) { ok = NO; break; }
            // This scalar getter accepts a packed timestamp reference, not an index.
            unsigned long long currentCycles = uscTimestamp(profile, refs[s]);
            unsigned long long byIndex = 0;
            // Independent getter check catches packed-reference/index ABI mistakes.
            if (!uscTimestamps(profile, &byIndex, index, 1) || currentCycles != byIndex) { ok = NO; break; }
            unsigned long long ns = (unsigned long long)((double)ticks[s] * (125.0 / 3.0));
            if (ns < prevNs) { ns = prevNs; monotonicClamps++; }
            if (currentCycles < prevCycles) { ok = NO; break; }
            [cycles addObject:@(currentCycles - prevCycles)];
            [seconds addObject:@((double)(ns - prevNs) / 1e9)];
            [references addObject:@(refs[s])];
            [timestamps addObject:@(ns)];
            prevCycles = currentCycles;
            prevNs = ns;
        }
        if (ok) {
            // Apple replaces the unbounded first interval with the second.
            cycles[0] = cycles[1]; seconds[0] = seconds[1];
            [timing addEntriesFromDictionary:@{@"GPUCycles": cycles, @"DeltaSeconds": seconds,
                @"timestamp_refs": references, @"timestamps_ns": timestamps,
                @"sample_count": @(sampleCount), @"group": @0,
                @"source": @"native interpolated system timestamps + USC timestamps",
                @"system_ns_per_tick": @(125.0 / 3.0), @"monotonic_clamps": @(monotonicClamps)}];
        }
        timing[@"native_timing_ok"] = @(ok);
        free(ticks);
    }
    NSDictionary *root = @{@"error": @(error), @"counters": out, @"timing": timing,
                          @"input_offset": @(off), @"validated": @NO};
    NSData *json = [NSJSONSerialization dataWithJSONObject:root options:0 error:NULL];
    ((void (*)(void *))dlsym(lib, "agxps_aps_profile_data_destroy"))(profile);
    ((void (*)(void *))dlsym(lib, "agxps_aps_parser_destroy"))(parser);
    if (![json writeToFile:@(argv[3]) atomically:YES]) return 2;
    printf("counters=%u names_ok=%d counts_ok=%d values_ok=%d error=%u\n", counters, namesOK, countsOK, valuesOK, error);
    return 0;
} }

int main(int argc, char **argv) { @autoreleasepool {
    BOOL directory = NO;
    if (argc < 4 || ![[NSFileManager defaultManager] fileExistsAtPath:@(argv[2]) isDirectory:&directory] || !directory)
        return dump_ring(argc, argv, nil, nil);
    if (![[NSFileManager defaultManager] createDirectoryAtPath:@(argv[3]) withIntermediateDirectories:YES attributes:nil error:NULL]) return 2;
    id processor = make_processor(argv[1]);
    if (!processor) return 2;
    BOOL minimal = argc > 5 && strcmp(argv[5], "--throughput") == 0;
    NSSet *wanted = minimal ? throughput_tracks(processor) : nil;
    if (minimal && !wanted.count) return 2;
    int failed = 0;
    for (unsigned i = 0; i < 40; i++) { @autoreleasepool {
        NSString *input = [@(argv[2]) stringByAppendingPathComponent:[NSString stringWithFormat:@"ring-%u.bin", i]];
        NSString *output = [@(argv[3]) stringByAppendingPathComponent:[NSString stringWithFormat:@"profile-%u.json", i]];
        if ([[NSData dataWithContentsOfFile:input] length] == 0) continue;
        char *args[] = {argv[0], argv[1], (char *)input.UTF8String, (char *)output.UTF8String, argc > 4 ? argv[4] : (char *)"0"};
        if (dump_ring(5, args, processor, wanted)) failed = 1;
    } }
    return failed;
} }
