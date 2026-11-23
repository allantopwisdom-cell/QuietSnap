#import <string.h>
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "AxsQuietSnapConfig.h"
#import "AxsQuietSnapPrivate.h"
#import "AxsQuietSnapGesture.h"
#import "AxsQuietSnapCapture.h"
#import "AxsQuietSnapLog.h"

#pragma mark - Substrate (resolved at runtime)

// The tweak must never hard-link libsubstrate: under RootHide the injected
// process may not be able to resolve it, which makes dyld drop the whole
// dylib without a single line of error output. Resolve it lazily instead.
typedef void (*AxsMSHookFunction)(void *symbol, void *replace, void **result);

static AxsMSHookFunction axs_ms_hook_function(void) {
    static AxsMSHookFunction fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *paths[] = {
            "/usr/lib/libsubstrate.dylib",
            "/usr/lib/libellekit.dylib",
            "/usr/lib/substrate/libsubstrate.dylib",
        };
        for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]) && !fn; i++) {
            void *handle = dlopen(paths[i], RTLD_LAZY);
            if (handle) fn = (AxsMSHookFunction)dlsym(handle, "MSHookFunction");
        }
        axs_quietsnap_log(@"[hook] substrate=%s", fn ? "ok" : "missing");
    });
    return fn;
}

#pragma mark - Silent capture

// Shutter / recording feedback is played through AudioServices. Suppress those
// calls only while a QuietSnap capture is running and silent capture is on.
static void (*axs_quietsnap_original_play_system_sound)(SystemSoundID);
static void axs_quietsnap_play_system_sound(SystemSoundID soundID) {
    if ([[AxsQuietSnapCapture axs_quietsnap_shared]
            axs_quietsnap_shouldSuppressSystemSound:(uint32_t)soundID]) {
        return;
    }
    if (axs_quietsnap_original_play_system_sound) {
        axs_quietsnap_original_play_system_sound(soundID);
    }
}

static void (*axs_quietsnap_original_play_system_sound_with_completion)(SystemSoundID, void (^)(void));
static void axs_quietsnap_play_system_sound_with_completion(SystemSoundID soundID,
                                                      void (^completion)(void)) {
    if ([[AxsQuietSnapCapture axs_quietsnap_shared]
            axs_quietsnap_shouldSuppressSystemSound:(uint32_t)soundID]) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
        return;
    }
    if (axs_quietsnap_original_play_system_sound_with_completion) {
        axs_quietsnap_original_play_system_sound_with_completion(soundID, completion);
    }
}

#pragma mark - Volume button hooks

// SpringBoard's volume handling has been renamed several times across iOS
// releases (`_volumeUpButtonDown` vs `volumeUpButtonDown`, with and without an
// argument). Instead of guessing, enumerate the class at runtime and hook every
// selector that looks like a volume press/release.
static NSMutableDictionary<NSString *, NSValue *> *axs_original_imps(void) {
    static NSMutableDictionary *dict;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dict = [NSMutableDictionary dictionary]; });
    return dict;
}

static void axs_call_original(id self, SEL _cmd) {
    NSValue *value = axs_original_imps()[NSStringFromSelector(_cmd)];
    if (!value) return;
    IMP imp = (IMP)(const void *)[value pointerValue];
    if (!imp) return;

    // Every variant we hook takes either zero arguments or a single object.
    Method method = class_getInstanceMethod(object_getClass(self), _cmd);
    if (!method) method = class_getInstanceMethod([self class], _cmd);
    const char *types = method ? method_getTypeEncoding(method) : "v@:";
    // Skip the two leading type chars (_C_ID / _C_CLASS) and look for arguments.
    const char *args = types + 2;
    if (args[0] == '\0') {
        ((void (*)(id, SEL))imp)(self, _cmd);
    } else {
        ((void (*)(id, SEL, id))imp)(self, _cmd, nil);
    }
}

static void axs_volume_press_up(id self, SEL _cmd) {
    axs_call_original(self, _cmd);
    [[AxsQuietSnapGesture axs_quietsnap_shared] axs_quietsnap_volumeUpDown];
}

static void axs_volume_release_up(id self, SEL _cmd) {
    axs_call_original(self, _cmd);
    [[AxsQuietSnapGesture axs_quietsnap_shared] axs_quietsnap_volumeUpUp];
}

static void axs_volume_press_down(id self, SEL _cmd) {
    axs_call_original(self, _cmd);
    [[AxsQuietSnapGesture axs_quietsnap_shared] axs_quietsnap_volumeDownDown];
}

static void axs_volume_release_down(id self, SEL _cmd) {
    axs_call_original(self, _cmd);
    [[AxsQuietSnapGesture axs_quietsnap_shared] axs_quietsnap_volumeDownUp];
}

// Returns 0 when the selector is not a volume button event, otherwise the
// direction bit (1 = up, 2 = press) so the installer can pick a handler.
static int axs_classify_volume_selector(NSString *name) {
    if ([name rangeOfString:@":"].location != NSNotFound) return 0;
    NSString *lower = name.lowercaseString;
    if ([lower rangeOfString:@"volume"].location == NSNotFound) return 0;

    BOOL up = ([lower rangeOfString:@"volumeup"].location != NSNotFound);
    BOOL down = ([lower rangeOfString:@"volumedown"].location != NSNotFound);
    if (!up && !down) return 0;

    BOOL press = NO;
    if ([lower hasSuffix:@"buttondown"] || [lower hasSuffix:@"down"]) press = YES;
    if ([lower hasSuffix:@"buttonup"] || [lower hasSuffix:@"up"]) press = NO;

    if (up) return press ? 1 : 3;   // 1 press up, 3 release up
    return press ? 2 : 4;           // 2 press down, 4 release down
}

static void axs_hook_volume_class(Class cls, const char *label) {
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (!methods) return;

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSMutableArray<NSString *> *hooked = [NSMutableArray array];

    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(sel);
        [names addObject:name];

        int kind = axs_classify_volume_selector(name);
        if (kind == 0) continue;

        IMP replacement = NULL;
        switch (kind) {
            case 1: replacement = (IMP)axs_volume_press_up; break;
            case 2: replacement = (IMP)axs_volume_press_down; break;
            case 3: replacement = (IMP)axs_volume_release_up; break;
            default: replacement = (IMP)axs_volume_release_down; break;
        }

        Method m = class_getInstanceMethod(cls, sel);
        if (!m) continue;
        IMP original = method_setImplementation(m, replacement);
        if (original) {
            axs_original_imps()[name] = [NSValue valueWithPointer:(const void *)original];
            [hooked addObject:name];
        }
    }
    free(methods);

    axs_quietsnap_log(@"%@ %s: %u methods", @"[volume]", label, count);
    axs_quietsnap_log(@"[volume] all methods: %@", [names componentsJoinedByString:@", "]);
    if (hooked.count) {
        axs_quietsnap_log(@"[volume] HOOKED %s -> %@", label,
                          [hooked componentsJoinedByString:@", "]);
    } else {
        axs_quietsnap_log(@"[volume] WARNING no volume selector matched on %s", label);
    }
}

static void axs_install_volume_hooks(void) {
    static BOOL installed = NO;
    if (installed) return;

    NSArray<NSString *> *classNames = @[
        @"SBVolumeHardwareButton",
        @"SBVolumeButtonHardwareController",
        @"SBSoundController"
    ];

    BOOL any = NO;
    for (NSString *className in classNames) {
        Class cls = objc_getClass(className.UTF8String);
        if (!cls) {
            axs_quietsnap_log(@"[volume] class missing: %@", className);
            continue;
        }
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        BOOL hasVolume = NO;
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            if ([name.lowercaseString containsString:@"volume"]) { hasVolume = YES; break; }
        }
        free(methods);
        if (!hasVolume && ![className isEqualToString:@"SBVolumeHardwareButton"]) continue;

        axs_hook_volume_class(cls, className.UTF8String);
        any = YES;
    }

    if (!any) {
        // Dump any SpringBoard class that mentions volume, to guide the next fix.
        int total = objc_getClassList(NULL, 0);
        if (total > 0) {
            Class *classes = (Class *)malloc(sizeof(Class) * (unsigned long)total);
            int real = objc_getClassList(classes, total);
            NSMutableArray *matches = [NSMutableArray array];
            for (int i = 0; i < real; i++) {
                const char *name = class_getName(classes[i]);
                if (!name) continue;
                if (strcasestr(name, "volume")) {
                    [matches addObject:@(name)];
                }
            }
            free(classes);
            axs_quietsnap_log(@"[volume] classes with 'volume': %@",
                              [matches componentsJoinedByString:@", "]);
        }
    }
    installed = YES;
}

%ctor {
    @autoreleasepool {
        // First statement on purpose: proves the dylib was injected even if a
        // later stage fails.
        axs_quietsnap_log(@"loaded in %@", [[NSBundle mainBundle] bundleIdentifier]);

        [AxsQuietSnapConfig axs_quietsnap_shared];
        [AxsQuietSnapGesture axs_quietsnap_shared];

        AxsMSHookFunction hook = axs_ms_hook_function();
        if (hook) {
            hook((void *)AudioServicesPlaySystemSound,
                 (void *)axs_quietsnap_play_system_sound,
                 (void **)&axs_quietsnap_original_play_system_sound);
            hook((void *)AudioServicesPlaySystemSoundWithCompletion,
                 (void *)axs_quietsnap_play_system_sound_with_completion,
                 (void **)&axs_quietsnap_original_play_system_sound_with_completion);
        } else {
            axs_quietsnap_log(@"[hook] silenced audio hooking unavailable");
        }

        axs_install_volume_hooks();

        axs_quietsnap_log(@"init done (enabled=%@)",
                          [[AxsQuietSnapConfig axs_quietsnap_shared] axs_quietsnap_isEnabled] ? @"YES" : @"NO");

        // Some SpringBoard builds create the button object late; retry once.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            axs_install_volume_hooks();
        });
    }
}
