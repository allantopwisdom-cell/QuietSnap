#pragma once

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, AxsQuietSnapGestureKind) {
    AxsQuietSnapGestureKindNone       = 0,
    AxsQuietSnapGestureKindSingleUp   = 1,
    AxsQuietSnapGestureKindSingleDown = 2,
    AxsQuietSnapGestureKindDoubleUp   = 3,
    AxsQuietSnapGestureKindDoubleDown = 4,
    AxsQuietSnapGestureKindLongUp     = 5,
    AxsQuietSnapGestureKindLongDown   = 6,
};

@interface AxsQuietSnapGesture : NSObject

+ (instancetype)axs_quietsnap_shared;

- (void)axs_quietsnap_volumeUpDown;
- (void)axs_quietsnap_volumeUpUp;
- (void)axs_quietsnap_volumeDownDown;
- (void)axs_quietsnap_volumeDownUp;

@end
