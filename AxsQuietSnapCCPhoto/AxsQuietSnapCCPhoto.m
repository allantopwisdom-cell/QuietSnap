#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

@interface AxsQuietSnapCCPhoto : NSObject
@end

@implementation AxsQuietSnapCCPhoto

- (UIImage *)iconGlyph {
    UIImage *image = [UIImage systemImageNamed:@"camera.fill"];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (BOOL)isSelected {
    // A photo is a one-shot action, so the tile never stays lit.
    return NO;
}

- (void)setSelected:(BOOL)selected {
    if (!selected) return;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.axs.quietsnap.cc.photo"),
                                         NULL, NULL, true);
}

@end
