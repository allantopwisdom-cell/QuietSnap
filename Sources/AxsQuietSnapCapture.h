#pragma once

#import <Foundation/Foundation.h>
#import <stdint.h>
#import "AxsQuietSnapGesture.h"

@interface AxsQuietSnapCapture : NSObject

+ (instancetype)axs_quietsnap_shared;

- (void)axs_quietsnap_handleGesture:(AxsQuietSnapGestureKind)kind;
- (BOOL)axs_quietsnap_isRecordingAudio;
- (BOOL)axs_quietsnap_isRecordingVideo;

// Returns YES while a capture is in progress and silent capture is enabled.
- (BOOL)axs_quietsnap_shouldSuppressSystemSound:(uint32_t)soundID;

@end
