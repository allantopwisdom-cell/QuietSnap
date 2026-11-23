#import "AxsQuietSnapAudio.h"
#import "AxsQuietSnapStorage.h"
#import "AxsQuietSnapConfig.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface AxsQuietSnapAudio () <AVAudioRecorderDelegate>
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, assign) BOOL recording;
@end

@implementation AxsQuietSnapAudio

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.recorder stop];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(axs_quietsnap_interruption:)
                                                     name:AVAudioSessionInterruptionNotification
                                                   object:nil];
    }
    return self;
}

- (BOOL)axs_quietsnap_isRecording {
    return self.recording && self.recorder.isRecording;
}

- (void)axs_quietsnap_startWithCompletion:(void (^)(BOOL, NSError *))completion {
    if (self.recording) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"com.axs.quietsnap" code:40
                                           userInfo:@{NSLocalizedDescriptionKey: @"Already recording"}]);
        }
        return;
    }

    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    id mixValue = [[AxsQuietSnapConfig axs_quietsnap_shared] axs_quietsnap_valueForKey:@"mix"
                                                                          defaultValue:@YES];
    BOOL mix = [mixValue isKindOfClass:[NSNumber class]] ? [mixValue boolValue] : YES;
    AVAudioSessionCategoryOptions options =
        AVAudioSessionCategoryOptionDefaultToSpeaker |
        (mix ? AVAudioSessionCategoryOptionMixWithOthers : 0);
    if (![session setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:options
                        error:&error]) {
        if (completion) completion(NO, error);
        return;
    }
    if (![session setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                       error:&error]) {
        if (completion) completion(NO, error);
        return;
    }

    NSURL *url = [AxsQuietSnapStorage axs_quietsnap_fileURLWithExtension:@"m4a"];
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatMPEG4AAC),
        AVSampleRateKey: @44100.0,
        AVNumberOfChannelsKey: @2,
        AVEncoderAudioQualityKey: @(AVAudioQualityHigh),
    };
    AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:url
                                                            settings:settings
                                                               error:&error];
    if (!recorder) {
        [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                     error:NULL];
        if (completion) completion(NO, error);
        return;
    }
    recorder.delegate = self;
    if (![recorder record]) {
        [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                     error:NULL];
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"com.axs.quietsnap" code:41
                                           userInfo:@{NSLocalizedDescriptionKey: @"Recorder did not start"}]);
        }
        return;
    }
    self.recorder = recorder;
    self.recording = YES;
    if (completion) completion(YES, nil);
}

- (void)axs_quietsnap_stop {
    if (!self.recorder) return;
    [self.recorder stop];
}

- (void)axs_quietsnap_interruption:(NSNotification *)notification {
    NSNumber *type = notification.userInfo[AVAudioSessionInterruptionTypeKey];
    if ([type unsignedIntegerValue] != AVAudioSessionInterruptionTypeBegan) return;
    if (self.recording) {
        [self.recorder stop];
    }
}

#pragma mark - AVAudioRecorderDelegate

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)success {
    self.recording = NO;
    self.recorder = nil;
    [[AVAudioSession sharedInstance] setActive:NO
                                   withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                         error:NULL];
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error {
    self.recording = NO;
    self.recorder = nil;
}

@end
