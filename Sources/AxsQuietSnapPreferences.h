#pragma once

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "AxsQuietSnapPaths.h"

static NSString * const AxsQuietSnapPreferencesDomain = @"com.axs.quietsnap";
static NSString * const AxsQuietSnapPreferencesChanged = @"com.axs.quietsnap.preferences-changed";

static inline NSDictionary *axs_quietsnap_readPreferences(void) {
    NSString *path = axs_quietsnap_preferencesPath();
    NSDictionary *values = path.length > 0 ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    if ([values isKindOfClass:[NSDictionary class]]) {
        return values;
    }
    // Compatibility fallback, not a second writable file location.
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:AxsQuietSnapPreferencesDomain];
    [defaults synchronize];
    return [defaults persistentDomainForName:AxsQuietSnapPreferencesDomain] ?: @{};
}

// The PreferenceBundle is the only caller allowed to write.
static inline BOOL axs_quietsnap_writePreference(NSString *key, id value, NSError **error) {
    NSString *path = axs_quietsnap_preferencesPath();
    if (key.length == 0 || path.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:AxsQuietSnapPreferencesDomain code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Invalid preference path or key"}];
        }
        return NO;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableDictionary *values;
    if ([manager fileExistsAtPath:path]) {
        NSData *existing = [NSData dataWithContentsOfFile:path options:0 error:error];
        id decoded = existing ? [NSPropertyListSerialization propertyListWithData:existing
                         options:NSPropertyListMutableContainers format:NULL error:error] : nil;
        if (![decoded isKindOfClass:[NSDictionary class]]) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:AxsQuietSnapPreferencesDomain code:2
                                        userInfo:@{NSLocalizedDescriptionKey: @"Preferences are not a dictionary"}];
            }
            return NO;
        }
        values = [decoded mutableCopy];
    } else {
        values = [axs_quietsnap_readPreferences() mutableCopy];
    }
    if (value) values[key] = value;
    else [values removeObjectForKey:key];
    if (![manager createDirectoryAtPath:[path stringByDeletingLastPathComponent]
            withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:values
                         format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:AxsQuietSnapPreferencesDomain];
    // Mirror the whole snapshot so cfprefsd cannot flush stale unrelated keys.
    [defaults setPersistentDomain:values forName:AxsQuietSnapPreferencesDomain];
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)AxsQuietSnapPreferencesChanged, NULL, NULL, true);
    return YES;
}
