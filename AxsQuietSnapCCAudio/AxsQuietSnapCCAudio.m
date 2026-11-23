#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>

/// Local mirror of the getters exposed by the injected tweak. Declaring the
/// protocol here keeps this bundle free of a link-time dependency on the dylib.
@protocol AxsQuietSnapRecordingState <NSObject>
+ (instancetype)axs_quietsnap_shared;
- (BOOL)axs_quietsnap_isRecordingAudio;
@end

@interface AxsQuietSnapCCAudio : NSObject
@property (nonatomic, assign) BOOL axs_quietsnap_selected;
@end

@implementation AxsQuietSnapCCAudio

- (UIImage *)iconGlyph {
    UIImage *image = [UIImage systemImageNamed:@"mic.fill"];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (BOOL)isSelected {
    // The tweak and this bundle share SpringBoard; read the live state when
    // the dylib is loaded, otherwise fall back to the local toggle.
    Class captureClass = NSClassFromString(@"AxsQuietSnapCapture");
    if (captureClass && [captureClass respondsToSelector:@selector(axs_quietsnap_shared)]) {
        typedef id (*AxsQuietSnapSharedFn)(Class, SEL);
        id<AxsQuietSnapRecordingState> capture =
            (id<AxsQuietSnapRecordingState>)((AxsQuietSnapSharedFn)objc_msgSend)(captureClass,
                                                               @selector(axs_quietsnap_shared));
        if ([capture respondsToSelector:@selector(axs_quietsnap_isRecordingAudio)]) {
            return [capture axs_quietsnap_isRecordingAudio];
        }
    }
    return self.axs_quietsnap_selected;
}

- (void)setSelected:(BOOL)selected {
    self.axs_quietsnap_selected = selected;
    CFStringRef name = (__bridge CFStringRef)(selected
        ? @"com.axs.quietsnap.cc.audio.start"
        : @"com.axs.quietsnap.cc.audio.stop");
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         name, NULL, NULL, true);
}

@end
