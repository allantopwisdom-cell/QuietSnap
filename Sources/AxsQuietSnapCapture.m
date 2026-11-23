#import "AxsQuietSnapCapture.h"
#import "AxsQuietSnapConfig.h"
#import "AxsQuietSnapPhoto.h"
#import "AxsQuietSnapVideo.h"
#import "AxsQuietSnapAudio.h"
#import "AxsQuietSnapStorage.h"
#import "AxsQuietSnapToast.h"
#import "AxsQuietSnapLog.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <AudioToolbox/AudioToolbox.h>

static NSString * const AxsQuietSnapLogPrefix = @"[QuietSnap]";
static NSString * const AxsQuietSnapCCAudioStart = @"com.axs.quietsnap.cc.audio.start";
static NSString * const AxsQuietSnapCCAudioStop  = @"com.axs.quietsnap.cc.audio.stop";
static NSString * const AxsQuietSnapCCVideoStart = @"com.axs.quietsnap.cc.video.start";
static NSString * const AxsQuietSnapCCVideoStop  = @"com.axs.quietsnap.cc.video.stop";
static NSString * const AxsQuietSnapCCPhotoShot  = @"com.axs.quietsnap.cc.photo";

@interface AxsQuietSnapCapture ()
@property (nonatomic, strong) AxsQuietSnapPhoto *photo;
@property (nonatomic, strong) AxsQuietSnapVideo *video;
@property (nonatomic, strong) AxsQuietSnapAudio *audio;
- (void)axs_quietsnap_takePhoto;
- (void)axs_quietsnap_toggleVideo;
- (void)axs_quietsnap_toggleAudio;
- (void)axs_quietsnap_feedback;
- (void)axs_quietsnap_setVideoRecording:(BOOL)recording;
- (void)axs_quietsnap_setAudioRecording:(BOOL)recording;
- (void)axs_quietsnap_beginSilentWindow;
- (void)axs_quietsnap_endSilentWindow;
- (BOOL)axs_quietsnap_hasFreeSpace;
- (void)axs_quietsnap_toast:(NSString *)message;
@property (atomic, assign) NSInteger axs_quietsnap_silentWindow;
@end

static BOOL axs_quietsnap_device_is_locked(void) {
    Class managerClass = objc_getClass("SBLockScreenManager");
    if (!managerClass) return NO;
    typedef id (*AxsQuietSnapSharedFn)(Class, SEL);
    typedef BOOL (*AxsQuietSnapBoolFn)(id, SEL);
    id manager = nil;
    if ([managerClass respondsToSelector:@selector(sharedInstance)]) {
        manager = ((AxsQuietSnapSharedFn)objc_msgSend)(managerClass, @selector(sharedInstance));
    }
    if (!manager) return NO;
    if ([manager respondsToSelector:@selector(isUILocked)]) {
        return ((AxsQuietSnapBoolFn)objc_msgSend)(manager, @selector(isUILocked));
    }
    return NO;
}

static void axs_quietsnap_cc_notification(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object,
                                          CFDictionaryRef info) {
    AxsQuietSnapCapture *capture = (__bridge AxsQuietSnapCapture *)observer;
    NSString *notification = (__bridge NSString *)name;
    if ([notification isEqualToString:AxsQuietSnapCCAudioStart]) {
        [capture axs_quietsnap_setAudioRecording:YES];
    } else if ([notification isEqualToString:AxsQuietSnapCCAudioStop]) {
        [capture axs_quietsnap_setAudioRecording:NO];
    } else if ([notification isEqualToString:AxsQuietSnapCCVideoStart]) {
        [capture axs_quietsnap_setVideoRecording:YES];
    } else if ([notification isEqualToString:AxsQuietSnapCCVideoStop]) {
        [capture axs_quietsnap_setVideoRecording:NO];
    } else if ([notification isEqualToString:AxsQuietSnapCCPhotoShot]) {
        [capture axs_quietsnap_takePhoto];
    }
}

@implementation AxsQuietSnapCapture {
    BOOL _photoBusy;
}

+ (instancetype)axs_quietsnap_shared {
    static AxsQuietSnapCapture *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _photo = [[AxsQuietSnapPhoto alloc] init];
        _video = [[AxsQuietSnapVideo alloc] init];
        _audio = [[AxsQuietSnapAudio alloc] init];

        // Control Center modules live in the same process but stay decoupled
        // through Darwin notifications.
        for (NSString *name in @[AxsQuietSnapCCAudioStart, AxsQuietSnapCCAudioStop,
                                 AxsQuietSnapCCVideoStart, AxsQuietSnapCCVideoStop,
                                 AxsQuietSnapCCPhotoShot]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                (__bridge const void *)self, axs_quietsnap_cc_notification,
                (__bridge CFStringRef)name, NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
        }
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

- (AxsQuietSnapConfig *)axs_quietsnap_config {
    return [AxsQuietSnapConfig axs_quietsnap_shared];
}

- (NSInteger)axs_quietsnap_gestureForKey:(NSString *)key defaultValue:(NSInteger)value {
    id stored = [[self axs_quietsnap_config] axs_quietsnap_valueForKey:key
                                                          defaultValue:@(value)];
    return [stored isKindOfClass:[NSNumber class]] ? [stored integerValue] : value;
}

- (BOOL)axs_quietsnap_isEnabled {
    return [[self axs_quietsnap_config] axs_quietsnap_isEnabled];
}

- (BOOL)axs_quietsnap_hapticsEnabled {
    id value = [[self axs_quietsnap_config] axs_quietsnap_valueForKey:@"haptic" defaultValue:@YES];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

- (BOOL)axs_quietsnap_hasFreeSpace {
    NSString *directory = [AxsQuietSnapStorage axs_quietsnap_outputDirectory];
    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfFileSystemForPath:directory error:NULL];
    unsigned long long freeBytes = [attributes[NSFileSystemFreeSize] unsignedLongLongValue];
    // Keep a small reserve so a long recording cannot fill the volume.
    if (freeBytes > 0 && freeBytes < 200ULL * 1024ULL * 1024ULL) {
        NSLog(@"%@ skipped: low free space (%llu MB)", AxsQuietSnapLogPrefix, freeBytes / (1024ULL * 1024ULL));
        return NO;
    }
    return YES;
}

- (void)axs_quietsnap_toast:(NSString *)message {
    id value = [[self axs_quietsnap_config] axs_quietsnap_valueForKey:@"showToast" defaultValue:@NO];
    BOOL enabled = [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
    if (enabled) {
        [AxsQuietSnapToast axs_quietsnap_showMessage:message];
    }
}

- (void)axs_quietsnap_beginSilentWindow {
    @synchronized (self) {
        self.axs_quietsnap_silentWindow = self.axs_quietsnap_silentWindow + 1;
    }
}

- (void)axs_quietsnap_endSilentWindow {
    @synchronized (self) {
        if (self.axs_quietsnap_silentWindow > 0) {
            self.axs_quietsnap_silentWindow = self.axs_quietsnap_silentWindow - 1;
        }
    }
}

- (BOOL)axs_quietsnap_shouldSuppressSystemSound:(uint32_t)soundID {
    // Never swallow vibration/ring feedback.
    if (soundID == kSystemSoundID_Vibrate) return NO;
    id value = [[self axs_quietsnap_config] axs_quietsnap_valueForKey:@"silentCapture" defaultValue:@YES];
    BOOL silent = [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
    if (!silent) return NO;
    @synchronized (self) {
        return self.axs_quietsnap_silentWindow > 0;
    }
}

- (void)axs_quietsnap_handleGesture:(AxsQuietSnapGestureKind)kind {
    axs_quietsnap_log(@"gesture kind=%ld enabled=%d", (long)kind,
                      (int)[self axs_quietsnap_isEnabled]);

    if (kind == AxsQuietSnapGestureKindNone || ![self axs_quietsnap_isEnabled]) {
        return;
    }

    id lockValue = [[self axs_quietsnap_config] axs_quietsnap_valueForKey:@"disableWhenLocked"
                                                             defaultValue:@NO];
    if ([lockValue isKindOfClass:[NSNumber class]] && [lockValue boolValue] &&
        axs_quietsnap_device_is_locked()) {
        return;
    }

    NSInteger photoGesture = [self axs_quietsnap_gestureForKey:@"photoGesture" defaultValue:3];
    NSInteger videoGesture = [self axs_quietsnap_gestureForKey:@"videoGesture" defaultValue:5];
    NSInteger audioGesture = [self axs_quietsnap_gestureForKey:@"audioGesture" defaultValue:6];

    // Same priority order as the preference summary: photo > video > audio.
    if (kind == photoGesture) {
        [self axs_quietsnap_takePhoto];
        return;
    }
    if (kind == videoGesture) {
        [self axs_quietsnap_toggleVideo];
        return;
    }
    if (kind == audioGesture) {
        [self axs_quietsnap_toggleAudio];
    }
}

- (void)axs_quietsnap_feedback {
    if (![self axs_quietsnap_hapticsEnabled]) return;
    UIImpactFeedbackGenerator *generator =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

- (void)axs_quietsnap_takePhoto {
    if (_photoBusy) {
        NSLog(@"%@ photo already in progress", AxsQuietSnapLogPrefix);
        return;
    }
    if (self.video.axs_quietsnap_isRecording) {
        // The camera is owned by the video session; a second session would fail.
        NSLog(@"%@ photo skipped: video recording", AxsQuietSnapLogPrefix);
        return;
    }
    if (![self axs_quietsnap_hasFreeSpace]) return;
    _photoBusy = YES;
    [self axs_quietsnap_feedback];
    [self axs_quietsnap_beginSilentWindow];
    [self.photo axs_quietsnap_captureWithCompletion:^(BOOL success, NSError *error) {
        [self axs_quietsnap_endSilentWindow];
        self->_photoBusy = NO;
        if (success) [self axs_quietsnap_toast:@"照片已保存"];
        NSLog(@"%@ photo %@%@", AxsQuietSnapLogPrefix, success ? @"saved" : @"failed",
              error ? [@": " stringByAppendingString:error.localizedDescription] : @"");
    }];
}

- (void)axs_quietsnap_toggleVideo {
    if (self.video.axs_quietsnap_isRecording) {
        [self axs_quietsnap_feedback];
        [self axs_quietsnap_beginSilentWindow];
        [self.video axs_quietsnap_stop];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self axs_quietsnap_endSilentWindow];
        });
        [self axs_quietsnap_toast:@"录像已保存"];
        NSLog(@"%@ video stopping", AxsQuietSnapLogPrefix);
        return;
    }
    if (self.audio.axs_quietsnap_isRecording) {
        NSLog(@"%@ video skipped: audio recording", AxsQuietSnapLogPrefix);
        return;
    }
    if (![self axs_quietsnap_hasFreeSpace]) return;
    [self axs_quietsnap_feedback];
    [self axs_quietsnap_beginSilentWindow];
    [self.video axs_quietsnap_startWithCompletion:^(BOOL success, NSError *error) {
        [self axs_quietsnap_endSilentWindow];
        if (success) [self axs_quietsnap_toast:@"开始录像"];
        NSLog(@"%@ video %@%@", AxsQuietSnapLogPrefix, success ? @"started" : @"failed",
              error ? [@": " stringByAppendingString:error.localizedDescription] : @"");
    }];
}

- (void)axs_quietsnap_toggleAudio {
    if (self.audio.axs_quietsnap_isRecording) {
        [self axs_quietsnap_feedback];
        [self.audio axs_quietsnap_stop];
        [self axs_quietsnap_toast:@"录音已保存"];
        NSLog(@"%@ audio stopping", AxsQuietSnapLogPrefix);
        return;
    }
    if (self.video.axs_quietsnap_isRecording) {
        NSLog(@"%@ audio skipped: video recording", AxsQuietSnapLogPrefix);
        return;
    }
    if (![self axs_quietsnap_hasFreeSpace]) return;
    [self axs_quietsnap_feedback];
    [self.audio axs_quietsnap_startWithCompletion:^(BOOL success, NSError *error) {
        NSLog(@"%@ audio %@%@", AxsQuietSnapLogPrefix, success ? @"started" : @"failed",
              error ? [@": " stringByAppendingString:error.localizedDescription] : @"");
    }];
}

- (BOOL)axs_quietsnap_isRecordingAudio {
    return self.audio.axs_quietsnap_isRecording;
}

- (BOOL)axs_quietsnap_isRecordingVideo {
    return self.video.axs_quietsnap_isRecording;
}

- (void)axs_quietsnap_setVideoRecording:(BOOL)recording {
    if (![self axs_quietsnap_isEnabled]) return;
    if (recording == self.video.axs_quietsnap_isRecording) return;
    [self axs_quietsnap_toggleVideo];
}

- (void)axs_quietsnap_setAudioRecording:(BOOL)recording {
    if (![self axs_quietsnap_isEnabled]) return;
    if (recording == self.audio.axs_quietsnap_isRecording) return;
    [self axs_quietsnap_toggleAudio];
}

@end
