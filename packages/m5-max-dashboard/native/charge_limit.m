#import "metrics.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>

// Read-only selectors used by Apple's Battery settings on macOS 26.4.
// This is the configured manual limit, not a guarantee of instantaneous
// enforcement: powerd has separate effective-limit / override state.
@protocol ChargeLimitReader <NSObject>
- (instancetype)initWithClientName:(NSString *)name;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (NSUInteger)isMCLCurrentlyEnabled:(NSError **)error;
@end

double m5_charge_limit_pct(void) {
    @autoreleasepool {
        static id<ChargeLimitReader> client;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            void *library = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_LAZY | RTLD_LOCAL);
            Class cls = library ? NSClassFromString(@"PowerUISmartChargeClient") : Nil;
            if ([cls instancesRespondToSelector:@selector(initWithClientName:)]
                && [cls instancesRespondToSelector:@selector(getMCLLimitWithError:)]
                && [cls instancesRespondToSelector:@selector(isMCLCurrentlyEnabled:)]) {
                client = [(id<ChargeLimitReader>)[cls alloc] initWithClientName:@"m5-max-dashboard"];
            }
        });
        if (!client) return NAN;
        NSError *error = nil;
        NSUInteger enabled = [client isMCLCurrentlyEnabled:&error];
        if (error || enabled > 1) return NAN;
        if (!enabled) return 100;
        unsigned char limit = [client getMCLLimitWithError:&error];
        return !error && limit > 0 && limit <= 100 ? limit : NAN;
    }
}
