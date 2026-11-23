#import "AxsQuietSnapStorage.h"
#import "AxsQuietSnapConfig.h"
#import <Photos/Photos.h>

static NSString * const AxsQuietSnapDefaultDirectory = @"/var/mobile/Media/QuietSnap";

@implementation AxsQuietSnapStorage

+ (AxsQuietSnapConfig *)axs_quietsnap_config {
    return [AxsQuietSnapConfig axs_quietsnap_shared];
}

+ (BOOL)axs_quietsnap_saveToPhotos {
    id value = [[self axs_quietsnap_config] axs_quietsnap_valueForKey:@"saveToPhotos"
                                                         defaultValue:@YES];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

+ (NSString *)axs_quietsnap_outputDirectory {
    id value = [[self axs_quietsnap_config] axs_quietsnap_valueForKey:@"savePath"
                                                         defaultValue:AxsQuietSnapDefaultDirectory];
    NSString *path = [value isKindOfClass:[NSString class]] ? value : nil;
    if (path.length == 0) {
        path = AxsQuietSnapDefaultDirectory;
    }
    // Expand ~ and normalise the path without requiring write access yet.
    if ([path hasPrefix:@"~"]) {
        path = [path stringByExpandingTildeInPath];
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![manager fileExistsAtPath:path isDirectory:&isDirectory]) {
        [manager createDirectoryAtPath:path withIntermediateDirectories:YES
                            attributes:nil error:NULL];
    }
    return path;
}

+ (NSString *)axs_quietsnap_fileName {
    id value = [[self axs_quietsnap_config] axs_quietsnap_valueForKey:@"fileName"
                                                         defaultValue:@"yyyyMMdd_HHmmss"];
    NSString *format = [value isKindOfClass:[NSString class]] ? value : nil;
    if (format.length == 0) {
        format = @"yyyyMMdd_HHmmss";
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = format;
    NSString *name = [formatter stringFromDate:[NSDate date]];
    return name.length > 0 ? name : [NSString stringWithFormat:@"%lld",
                                     (long long)[[NSDate date] timeIntervalSince1970]];
}

+ (NSURL *)axs_quietsnap_fileURLWithExtension:(NSString *)extension {
    NSString *directory = [self axs_quietsnap_outputDirectory];
    NSString *base = [self axs_quietsnap_fileName];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:
                                        [base stringByAppendingPathExtension:extension]]];
    // Avoid overwriting an existing capture that used the same second.
    NSUInteger suffix = 1;
    while ([manager fileExistsAtPath:url.path]) {
        NSString *name = [NSString stringWithFormat:@"%@-%lu", base, (unsigned long)suffix++];
        url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:
                                    [name stringByAppendingPathExtension:extension]]];
    }
    return url;
}

+ (BOOL)axs_quietsnap_writeImage:(UIImage *)image error:(NSError **)error {
    NSData *data = UIImageJPEGRepresentation(image, 0.95);
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.axs.quietsnap" code:10
                                     userInfo:@{NSLocalizedDescriptionKey: @"JPEG encode failed"}];
        }
        return NO;
    }
    NSURL *url = [self axs_quietsnap_fileURLWithExtension:@"jpg"];
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

+ (void)axs_quietsnap_saveImage:(UIImage *)image
                     completion:(void (^)(BOOL, NSError *))completion {
    if (!image) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"com.axs.quietsnap" code:11
                                            userInfo:@{NSLocalizedDescriptionKey: @"No image"}]);
        }
        return;
    }
    if (![self axs_quietsnap_saveToPhotos]) {
        NSError *error = nil;
        BOOL ok = [self axs_quietsnap_writeImage:image error:&error];
        if (completion) completion(ok, error);
        return;
    }
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromImage:image];
    } completionHandler:^(BOOL success, NSError *error) {
        if (success) {
            if (completion) completion(YES, nil);
            return;
        }
        // Photos rejected the write (permission or library state): keep the file.
        NSError *writeError = nil;
        BOOL ok = [self axs_quietsnap_writeImage:image error:&writeError];
        if (completion) completion(ok, ok ? error : writeError);
    }];
}

+ (void)axs_quietsnap_saveVideoAtURL:(NSURL *)url
                          completion:(void (^)(BOOL, NSError *))completion {
    if (!url) {
        if (completion) completion(NO, nil);
        return;
    }
    if (![self axs_quietsnap_saveToPhotos]) {
        if (completion) completion(YES, nil);
        return;
    }
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:url];
    } completionHandler:^(BOOL success, NSError *error) {
        if (success) {
            [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
            if (completion) completion(YES, nil);
        } else {
            // Keep the recording on disk instead of losing it.
            if (completion) completion(YES, error);
        }
    }];
}

@end
