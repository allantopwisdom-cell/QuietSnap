#pragma once

#import <UIKit/UIKit.h>

/// Lightweight, non-interactive overlay used for capture feedback.
/// Never becomes key window and never takes touches.
@interface AxsQuietSnapToast : NSObject

+ (void)axs_quietsnap_showMessage:(NSString *)message;

@end
