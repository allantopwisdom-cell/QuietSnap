#pragma once

#import <UIKit/UIKit.h>

@interface AxsQuietSnapStorage : NSObject

+ (NSString *)axs_quietsnap_outputDirectory;
+ (NSURL *)axs_quietsnap_fileURLWithExtension:(NSString *)extension;

// Saves to Photos when enabled in preferences, otherwise writes to the output
// directory. Falls back to the directory if Photos is unavailable.
+ (void)axs_quietsnap_saveImage:(UIImage *)image
                     completion:(void (^)(BOOL success, NSError *error))completion;
+ (void)axs_quietsnap_saveVideoAtURL:(NSURL *)url
                          completion:(void (^)(BOOL success, NSError *error))completion;

@end
