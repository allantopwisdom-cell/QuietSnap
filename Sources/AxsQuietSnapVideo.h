#pragma once

#import <Foundation/Foundation.h>

@interface AxsQuietSnapVideo : NSObject

@property (nonatomic, readonly) BOOL axs_quietsnap_isRecording;

- (void)axs_quietsnap_startWithCompletion:(void (^)(BOOL success, NSError *error))completion;
- (void)axs_quietsnap_stop;

@end
