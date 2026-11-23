#pragma once

#import <UIKit/UIKit.h>

// Private SpringBoard class confirmed on iOS 15/16. Only the four volume
// button entry points are used; no other members are assumed.
@interface SBVolumeHardwareButton : NSObject
- (void)_volumeUpButtonDown:(id)event;
- (void)_volumeUpButtonUp:(id)event;
- (void)_volumeDownButtonDown:(id)event;
- (void)_volumeDownButtonUp:(id)event;
@end
