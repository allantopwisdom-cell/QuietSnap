#import "AxsQuietSnapConfig.h"
#import "AxsQuietSnapPreferences.h"

@interface AxsQuietSnapConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void axs_quietsnap_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    AxsQuietSnapConfig *config = (__bridge AxsQuietSnapConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config axs_quietsnap_reload];
    });
}

@implementation AxsQuietSnapConfig

+ (instancetype)axs_quietsnap_shared {
    static AxsQuietSnapConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.axs.quietsnap.preferences", DISPATCH_QUEUE_SERIAL);
        [self axs_quietsnap_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, axs_quietsnap_preferencesDidChange,
            (__bridge CFStringRef)AxsQuietSnapPreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self axs_quietsnap_reload]; });
    }
    return self;
}

- (void)axs_quietsnap_reload {
    self.snapshot = axs_quietsnap_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AxsQuietSnapPreferencesChanged object:self];
    });
}

- (id)axs_quietsnap_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (BOOL)axs_quietsnap_isEnabled {
    id value = [self axs_quietsnap_valueForKey:@"enabled" defaultValue:@(NO)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
