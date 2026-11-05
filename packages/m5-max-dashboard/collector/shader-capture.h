// Existing APS_USC capture route, limited to one 20 ms window per request.
// Runs only in a fresh Apple profiling helper, never an existing process.
#define nil ((id)0)
#define NULL 0
#define RTLD_NOW 2
#define YES ((BOOL)1)
#define NO ((BOOL)0)
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

@interface NSObject (DashboardCounterSource)
- (NSArray *)sourceList;
- (NSString *)name;
- (NSDictionary *)features;
- (NSDictionary *)options;
- (NSArray *)availableCounters;
- (NSArray *)availableTriggers;
- (unsigned)counterValueType;
- (BOOL)requestCounters:(NSArray *)items firstErrorIndex:(NSUInteger *)index;
- (BOOL)requestTriggers:(NSArray *)items firstErrorIndex:(NSUInteger *)index;
- (void)setOptions:(NSDictionary *)options;
- (void)setEnabled:(BOOL)enabled;
- (BOOL)startSampling;
- (BOOL)stopSampling;
- (unsigned)ringBufferNum;
- (BOOL)ringBufferInfoAtIndex:(unsigned)index base:(void **)base size:(unsigned *)size dataOffset:(unsigned *)offset dataSize:(unsigned *)available;
+ (id)selectWithName:(NSString *)name options:(NSDictionary *)options;
@end

static NSArray *dashboard_counter_groups(NSError **error) {
    void *library = dlopen("/System/Library/PrivateFrameworks/GPURawCounter.framework/GPURawCounter", RTLD_NOW);
    auto copy = library ? (NSArray *(*)(NSError **))dlsym(library, "GRCCopyAllCounterSourceGroupWithError") : NULL;
    return copy ? copy(error) : nil;
}

int gpu_bridge_prepare(const char *output) {
    @autoreleasepool {
        NSError *error = nil;
        NSArray *all = dashboard_counter_groups(&error);
        if (!all.count) return 1;
        NSObject *group = all[0];
        NSMutableArray *sources = [NSMutableArray array];
        for (NSObject *source in group.sourceList) {
            NSMutableArray *counters = [NSMutableArray array];
            for (NSObject *counter in source.availableCounters)
                [counters addObject:@{@"name":counter.name ?: @"", @"description":counter.description ?: @"", @"type":@(counter.counterValueType)}];
            [sources addObject:@{@"name":source.name, @"features":source.features ?: @{}, @"options":source.options ?: @{}, @"counters":counters}];
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"features":group.features ?: @{}, @"sources":sources} options:0 error:&error];
        NSString *path = [@(output) stringByAppendingPathComponent:@"catalog.json"];
        return data && [data writeToFile:path atomically:YES] ? 0 : 1;
    }
}

static int dashboard_capture_shader(const char *output) {
    @autoreleasepool {
        NSError *error = nil;
        NSArray *all = dashboard_counter_groups(&error);
        if (!all.count) return 1;
        NSObject *group = all[0], *source = nil;
        for (NSObject *candidate in group.sourceList)
            if ([candidate.name isEqualToString:@"APS_USC"]) source = candidate;
        if (!source) return 3;
        NSMutableArray *selected = [NSMutableArray array];
        Class counterSelect = NSClassFromString(@"GPURawCounterSelect");
        Class triggerSelect = NSClassFromString(@"GPURawCounterSourceTriggerSelect");
        for (NSObject *counter in source.availableCounters)
            [selected addObject:[counterSelect selectWithName:counter.name options:@{}]];
        NSUInteger failed = ~(NSUInteger)0;
        if (![source requestCounters:selected firstErrorIndex:&failed]) return 4;
        [source setOptions:@{@"SystemTimePeriod":@8192}];
        NSArray *triggers = @[[triggerSelect selectWithName:@"KickAndStateTracing" options:@{@"CountPeriod":@32768, @"PulsePeriod":@2048}]];
        if (![source requestTriggers:triggers firstErrorIndex:&failed]) return 5;
        [source setEnabled:YES];
        if (![group startSampling]) {
            [group stopSampling];
            [source setEnabled:NO];
            return 6;
        }
        unsigned ringCount = [source ringBufferNum];
        int captureError = ringCount == 40 ? 0 : 7;
        usleep(20000);
        BOOL stopped = [group stopSampling];
        NSMutableArray *buffers = [NSMutableArray array];
        NSMutableArray *readable = [NSMutableArray array];
        NSMutableArray *ringInfo = [NSMutableArray array];
        NSUInteger accepted = 0;
        for (unsigned i = 0; i < ringCount && !captureError; ++i) {
            void *rawBase = NULL;
            unsigned rawSize = 0, rawOffset = 0, rawCount = 0;
            BOOL ok = [source ringBufferInfoAtIndex:i base:&rawBase size:&rawSize dataOffset:&rawOffset dataSize:&rawCount];
            BOOL valid = ok && (!rawCount || (rawBase && rawSize && rawOffset < rawSize && rawCount <= rawSize && accepted + rawCount <= 64*1024*1024));
            [readable addObject:@(valid)];
            [ringInfo addObject:@{@"size":@(rawSize), @"offset":@(rawOffset), @"bytes":@(rawCount)}];
            NSMutableData *buffer = [NSMutableData data];
            if (!valid || !rawCount) {
                [buffers addObject:buffer];
                continue;
            }
            unsigned first = rawCount < rawSize - rawOffset ? rawCount : rawSize - rawOffset;
            [buffer appendBytes:(char *)rawBase + rawOffset length:first];
            if (rawCount > first) [buffer appendBytes:rawBase length:rawCount-first];
            [buffers addObject:buffer];
            accepted += rawCount;
        }
        [source setEnabled:NO];
        if (captureError) return captureError;
        if (!stopped) return 10;
        NSString *directory = [@(output) stringByAppendingPathComponent:@"capture"];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) return 11;
        for (NSUInteger i = 0; i < buffers.count; ++i) {
            NSData *data = buffers[i];
            NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"ring-%lu.bin", (unsigned long)i]];
            if (![data writeToFile:path options:NSDataWritingAtomic error:&error]) return 12;
        }
        NSData *metadata = [NSJSONSerialization dataWithJSONObject:@{@"readable":readable, @"rings":ringInfo} options:0 error:&error];
        if (!metadata || ![metadata writeToFile:[directory stringByAppendingPathComponent:@"capture.json"] options:NSDataWritingAtomic error:&error]) return 12;
        return accepted ? 0 : 2;
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
        char result = (char)('0' + dashboard_capture_shader(output));
        if (write(resultFD, &result, 1) != 1) break;
    }
    close(input); close(resultFD);
    _exit(0);
}
