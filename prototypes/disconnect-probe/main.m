// Throwaway prototype: does the private CoreGraphics Disconnect API work on this macOS?
//
//   disconnect-probe list                 list online Displays and whether each is active
//   disconnect-probe virtual-test         create a virtual Display, Disconnect it, Reconnect it
//   disconnect-probe disconnect <id>      Disconnect a real Display (refuses the Last Active Display)
//   disconnect-probe reconnect <id>       Reconnect a Display by ID
//
// Build: clang -fobjc-arc -framework Foundation -framework CoreGraphics main.m -o disconnect-probe

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>

// ---- Private API: Disconnect ----
typedef CGError (*CGSConfigureDisplayEnabledFn)(CGDisplayConfigRef, CGDirectDisplayID, bool);

static CGSConfigureDisplayEnabledFn loadConfigureDisplayEnabled(void) {
    void *sym = dlsym(RTLD_DEFAULT, "CGSConfigureDisplayEnabled");
    if (!sym) {
        void *sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (sky) sym = dlsym(sky, "SLSConfigureDisplayEnabled");
    }
    return (CGSConfigureDisplayEnabledFn)sym;
}

// ---- Private API: virtual Display (test target only) ----
@interface CGVirtualDisplayDescriptor : NSObject
@property(retain, nonatomic) dispatch_queue_t queue;
@property(retain, nonatomic) NSString *name;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@end
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end
@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(retain, nonatomic) NSArray *modes;
@end
@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) unsigned int displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

// ---- Helpers ----
static NSArray<NSNumber *> *displayList(BOOL active) {
    CGDirectDisplayID ids[32];
    uint32_t n = 0;
    CGError err = active ? CGGetActiveDisplayList(32, ids, &n) : CGGetOnlineDisplayList(32, ids, &n);
    if (err != kCGErrorSuccess) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (uint32_t i = 0; i < n; i++) [out addObject:@(ids[i])];
    return out;
}

static void printState(NSString *label, CGDirectDisplayID watched) {
    NSArray *online = displayList(NO), *active = displayList(YES);
    printf("[%s] online=%s active=%s", label.UTF8String,
           [online componentsJoinedByString:@","].UTF8String,
           [active componentsJoinedByString:@","].UTF8String);
    if (watched) {
        printf("  -> %u: online=%s active=%s", watched,
               [online containsObject:@(watched)] ? "yes" : "no",
               [active containsObject:@(watched)] ? "yes" : "no");
    }
    printf("\n");
}

static void pumpRunLoop(double seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static CGError setEnabled(CGDirectDisplayID display, bool enabled) {
    CGSConfigureDisplayEnabledFn fn = loadConfigureDisplayEnabled();
    if (!fn) { fprintf(stderr, "CGSConfigureDisplayEnabled not found\n"); return kCGErrorFailure; }
    CGDisplayConfigRef config;
    CGError err = CGBeginDisplayConfiguration(&config);
    if (err) { printf("  begin -> %d\n", err); return err; }
    err = fn(config, display, enabled);
    if (err) { printf("  configureEnabled -> %d\n", err); CGCancelDisplayConfiguration(config); return err; }
    err = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
    if (err) printf("  complete -> %d\n", err);
    return err;
}

// ---- Commands ----
static int cmdList(void) {
    NSArray *active = displayList(YES);
    for (NSNumber *d in displayList(NO)) {
        CGDirectDisplayID id = d.unsignedIntValue;
        printf("%u  builtin=%d main=%d active=%d asleep=%d  %zux%zu\n", id,
               CGDisplayIsBuiltin(id), CGDisplayIsMain(id), [active containsObject:d], CGDisplayIsAsleep(id),
               CGDisplayPixelsWide(id), CGDisplayPixelsHigh(id));
    }
    printf("CGSConfigureDisplayEnabled: %s\n", loadConfigureDisplayEnabled() ? "found" : "MISSING");
    return 0;
}

static int cmdDisconnect(CGDirectDisplayID id) {
    NSArray *active = displayList(YES);
    if (![active containsObject:@(id)]) { fprintf(stderr, "%u is not active\n", id); return 1; }
    if (active.count <= 1) { fprintf(stderr, "refusing: %u is the Last Active Display\n", id); return 1; }
    CGError err = setEnabled(id, false);
    printf("disconnect %u -> CGError %d\n", id, err);
    pumpRunLoop(2);
    printState(@"after disconnect", id);
    return err ? 1 : 0;
}

static int cmdReconnect(CGDirectDisplayID id) {
    CGError err = setEnabled(id, true);
    printf("reconnect %u -> CGError %d\n", id, err);
    pumpRunLoop(2);
    printState(@"after reconnect", id);
    return err ? 1 : 0;
}

static int cmdVirtualTest(void) {
    if (!loadConfigureDisplayEnabled()) { fprintf(stderr, "FAIL: CGSConfigureDisplayEnabled missing\n"); return 1; }
    for (NSNumber *d in displayList(NO)) {
        if (CGDisplayIsAsleep(d.unsignedIntValue)) { fprintf(stderr, "REFUSED: Display %u is asleep; wake it first\n", d.unsignedIntValue); return 1; }
    }
    Class descCls = NSClassFromString(@"CGVirtualDisplayDescriptor");
    if (!descCls) { fprintf(stderr, "FAIL: CGVirtualDisplay unavailable\n"); return 1; }

    CGVirtualDisplayDescriptor *desc = [[descCls alloc] init];
    desc.queue = dispatch_get_main_queue();
    desc.name = @"ScreenTool Probe";
    desc.maxPixelsWide = 1920;
    desc.maxPixelsHigh = 1080;
    desc.sizeInMillimeters = CGSizeMake(600, 340);
    desc.vendorID = 0xEEEE; desc.productID = 0x1234; desc.serialNum = arc4random_uniform(1000000) + 1;

    CGVirtualDisplay *vd = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:desc];
    CGVirtualDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
    settings.hiDPI = 0;
    settings.modes = @[[[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:1920 height:1080 refreshRate:60]];
    if (!vd || ![vd applySettings:settings]) { fprintf(stderr, "FAIL: could not create virtual Display\n"); return 1; }

    CGDirectDisplayID id = vd.displayID;
    pumpRunLoop(2);
    printState(@"virtual created", id);
    if (![displayList(YES) containsObject:@(id)]) { fprintf(stderr, "FAIL: virtual Display never became active\n"); return 1; }

    CGError err = setEnabled(id, false);
    printf("disconnect -> CGError %d\n", err);
    pumpRunLoop(2);
    printState(@"after disconnect", id);
    BOOL disconnected = ![displayList(YES) containsObject:@(id)];

    err = setEnabled(id, true);
    printf("reconnect -> CGError %d\n", err);
    pumpRunLoop(2);
    printState(@"after reconnect", id);
    BOOL reconnected = [displayList(YES) containsObject:@(id)];

    printf("\nRESULT: disconnect %s, reconnect %s\n", disconnected ? "OK" : "FAILED", reconnected ? "OK" : "FAILED");
    if (![displayList(YES) containsObject:@(id)]) setEnabled(id, true);  // never release it Disconnected
    vd = nil;  // virtual Display disappears when released
    BOOL removed = NO;
    for (int i = 0; i < 20 && !removed; i++) { pumpRunLoop(0.5); removed = ![displayList(NO) containsObject:@(id)]; }
    printState(@"after release", id);
    printf("cleanup: virtual Display %s\n", removed ? "removed" : "STILL PRESENT - log out to clear it");
    return (disconnected && reconnected && removed) ? 0 : 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *cmd = argc > 1 ? @(argv[1]) : @"list";
        if ([cmd isEqualToString:@"list"]) return cmdList();
        if ([cmd isEqualToString:@"virtual-test"]) return cmdVirtualTest();
        if (argc > 2 && [cmd isEqualToString:@"disconnect"]) return cmdDisconnect((CGDirectDisplayID)strtoul(argv[2], NULL, 10));
        if (argc > 2 && [cmd isEqualToString:@"reconnect"]) return cmdReconnect((CGDirectDisplayID)strtoul(argv[2], NULL, 10));
        fprintf(stderr, "usage: disconnect-probe list | virtual-test | disconnect <id> | reconnect <id>\n");
        return 2;
    }
}
