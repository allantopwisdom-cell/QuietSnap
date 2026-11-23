#pragma once

#import <Foundation/Foundation.h>

@interface AxsQuietSnapPhoto : NSObject

- (void)axs_quietsnap_captureWithCompletion:(void (^)(BOOL success, NSError *error))completion;

@end
