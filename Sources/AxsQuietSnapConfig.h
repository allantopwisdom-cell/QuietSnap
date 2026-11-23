#pragma once

#import <Foundation/Foundation.h>

@interface AxsQuietSnapConfig : NSObject
+ (instancetype)axs_quietsnap_shared;
- (BOOL)axs_quietsnap_isEnabled;
- (id)axs_quietsnap_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)axs_quietsnap_reload;
@end
