#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <substrate.h>
#import "AxsQuietSnapConfig.h"
#import "AxsQuietSnapPrivate.h"
#import "AxsQuietSnapGesture.h"
#import "AxsQuietSnapCapture.h"

// Shutter / recording feedback is played through AudioServices. Suppress those
// calls only while a QuietSnap capture is running and silent capture is on.
static void (*axs_quietsnap_original_play_system_sound)(SystemSoundID);
static void axs_quietsnap_play_system_sound(SystemSoundID soundID) {
    if ([[AxsQuietSnapCapture axs_quietsnap_shared]
            axs_quietsnap_shouldSuppressSystemSound:(uint32_t)soundID]) {
        return;
    }
    if (axs_quietsnap_original_play_system_sound) {
        axs_quietsnap_original_play_system_sound(soundID);
    }
}

static void (*axs_quietsnap_original_play_system_sound_with_completion)(SystemSoundID, void (^)(void));
static void axs_quietsnap_play_system_sound_with_completion(SystemSoundID soundID,
                                                      void (^completion)(void)) {
    if ([[AxsQuietSnapCapture axs_quietsnap_shared]
            axs_quietsnap_shouldSuppressSystemSound:(uint32_t)soundID]) {
        // Keep the caller's contract even though nothing is played.
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
        return;
    }
    if (axs_quietsnap_original_play_system_sound_with_completion) {
        axs_quietsnap_original_play_system_sound_with_completion(soundID, completion);
    }
}

// SpringBoard delivers physical volume button events to SBVolumeHardwareButton.
// The same four entry points exist on iOS 15/16; hooking a missing one is inert.
%hook SBVolumeHardwareButton

- (void)_volumeUpButtonDown:(id)event {
    [[AxsQuietSnapGesture axs_quietsnap_shared] axs_quietsnap_volumeUpDown];
    %orig;
}

- (void)_volumeUpButtonUp:(id)event {
    [[AxsQuietSnapGesture axs_quietsnap_shared] axs_quietsnap_volumeUpUp];
    %orig;
}

- (void)_volumeDownButtonDown:(id)event {
    [[AxsQuietSnapGesture axs_quietsnap_shared] axs_quietsnap_volumeDownDown];
    %orig;
}

- (void)_volumeDownButtonUp:(id)event {
    [[AxsQuietSnapGesture axs_quietsnap_shared] axs_quietsnap_volumeDownUp];
    %orig;
}

%end

%ctor {
    @autoreleasepool {
        // Readers only load a snapshot; the preference bundle owns writes.
        [AxsQuietSnapConfig axs_quietsnap_shared];
        [AxsQuietSnapGesture axs_quietsnap_shared];

        MSHookFunction((void *)AudioServicesPlaySystemSound,
                       (void *)axs_quietsnap_play_system_sound,
                       (void **)&axs_quietsnap_original_play_system_sound);
        MSHookFunction((void *)AudioServicesPlaySystemSoundWithCompletion,
                       (void *)axs_quietsnap_play_system_sound_with_completion,
                       (void **)&axs_quietsnap_original_play_system_sound_with_completion);

        NSLog(@"[QuietSnap] loaded (enabled=%@)",
              [[AxsQuietSnapConfig axs_quietsnap_shared] axs_quietsnap_isEnabled] ? @"YES" : @"NO");
    }
}
