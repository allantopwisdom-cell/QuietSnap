#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>

@protocol AxsQuietSnapVideoState <NSObject>
+ (instancetype)axs_quietsnap_shared;
- (BOOL)axs_quietsnap_isRecordingVideo;
@end

@interface AxsQuietSnapCCVideo : NSObject
@property (nonatomic, assign) BOOL axs_quietsnap_selected;
@end

@implementation AxsQuietSnapCCVideo

- (UIImage *)iconGlyph {
    UIImage *image = [UIImage systemImageNamed:@"video.fill"];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (BOOL)isSelected {
    Class captureClass = NSClassFromString(@"AxsQuietSnapCapture");
    if (captureClass && [captureClass respondsToSelector:@selector(axs_quietsnap_shared)]) {
        typedef id (*AxsQuietSnapSharedFn)(Class, SEL);
        id<AxsQuietSnapVideoState> capture =
            (id<AxsQuietSnapVideoState>)((AxsQuietSnapSharedFn)objc_msgSend)(captureClass,
                                                               @selector(axs_quietsnap_shared));
        if ([capture respondsToSelector:@selector(axs_quietsnap_isRecordingVideo)]) {
            return [capture axs_quietsnap_isRecordingVideo];
        }
    }
    return self.axs_quietsnap_selected;
}

- (void)setSelected:(BOOL)selected {
    self.axs_quietsnap_selected = selected;
    CFStringRef name = (__bridge CFStringRef)(selected
        ? @"com.axs.quietsnap.cc.video.start"
        : @"com.axs.quietsnap.cc.video.stop");
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         name, NULL, NULL, true);
}

@end
