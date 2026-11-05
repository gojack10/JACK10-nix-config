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
        if (!source) return 1;
        NSMutableArray *selected = [NSMutableArray array];
        Class counterSelect = NSClassFromString(@"GPURawCounterSelect");
        Class triggerSelect = NSClassFromString(@"GPURawCounterSourceTriggerSelect");
        for (NSObject *counter in source.availableCounters)
            [selected addObject:[counterSelect selectWithName:counter.name options:@{}]];
        NSUInteger failed = ~(NSUInteger)0;
        if (![source requestCounters:selected firstErrorIndex:&failed]) return 1;
        [source setOptions:@{@"SystemTimePeriod":@8192}];
        NSArray *triggers = @[[triggerSelect selectWithName:@"KickAndStateTracing" options:@{@"CountPeriod":@32768, @"PulsePeriod":@2048}]];
        if (![source requestTriggers:triggers firstErrorIndex:&failed]) return 1;
        [source setEnabled:YES];
        if (![group startSampling]) {
            [group stopSampling];
            [source setEnabled:NO];
            return 1;
        }
        unsigned ringCount = [source ringBufferNum];
        BOOL captureOK = ringCount == 40;
        usleep(20000);
        BOOL stopped = [group stopSampling];
        NSMutableArray *buffers = [NSMutableArray array];
        NSUInteger accepted = 0;
        for (unsigned i = 0; i < ringCount && captureOK; ++i) {
            void *base = NULL;
            unsigned size = 0, offset = 0, count = 0;
            BOOL ok = [source ringBufferInfoAtIndex:i base:&base size:&size dataOffset:&offset dataSize:&count];
            if (!ok) { captureOK = NO; break; }
            if (!count) {
                [buffers addObject:[NSMutableData data]];
                continue;
            }
            if (!base || !size || offset >= size || count > size || accepted + count > 64*1024*1024) {
                captureOK = NO;
                break;
            }
            NSMutableData *buffer = [NSMutableData data];
            unsigned first = count < size - offset ? count : size - offset;
            [buffer appendBytes:(char *)base + offset length:first];
            if (count > first) [buffer appendBytes:base length:count-first];
            [buffers addObject:buffer];
            accepted += count;
        }
        [source setEnabled:NO];
        if (!captureOK || !stopped) return 1;
        NSString *directory = [@(output) stringByAppendingPathComponent:@"capture"];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) return 1;
        for (NSUInteger i = 0; i < buffers.count; ++i) {
            NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"ring-%lu.bin", (unsigned long)i]];
            if (![buffers[i] writeToFile:path options:NSDataWritingAtomic error:&error]) return 1;
        }
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
        long count = read(input, &command, 1);
        if (count < 0 && *__error() == 4) continue;
        if (count != 1 || command == 'q') break;
        if (command != 's') break;
        char result = (char)('0' + dashboard_capture_shader(output));
        if (write(resultFD, &result, 1) != 1) break;
    }
    close(input); close(resultFD);
    _exit(0);
}
