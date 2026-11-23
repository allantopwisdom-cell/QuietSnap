#import "AxsQuietSnapVideo.h"
#import "AxsQuietSnapStorage.h"
#import "AxsQuietSnapConfig.h"
#import <AVFoundation/AVFoundation.h>

@interface AxsQuietSnapVideo () <AVCaptureFileOutputRecordingDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureMovieFileOutput *fileOutput;
@property (nonatomic, assign) BOOL recording;
@property (nonatomic, assign) BOOL starting;
@property (nonatomic, copy) void (^startCompletion)(BOOL, NSError *);
@property (nonatomic, strong) dispatch_block_t maxDurationBlock;
- (void)axs_quietsnap_failStart:(NSError *)error;
- (void)axs_quietsnap_cancelMaxDuration;
@end

@implementation AxsQuietSnapVideo

- (void)dealloc {
    [self.session stopRunning];
}

- (BOOL)axs_quietsnap_isRecording {
    return self.recording && self.fileOutput.isRecording;
}

- (NSInteger)axs_quietsnap_fps {
    id value = [[AxsQuietSnapConfig axs_quietsnap_shared] axs_quietsnap_valueForKey:@"fps"
                                                                        defaultValue:@30];
    return [value isKindOfClass:[NSNumber class]] ? MAX(1, [value integerValue]) : 30;
}

- (NSString *)axs_quietsnap_preset {
    id value = [[AxsQuietSnapConfig axs_quietsnap_shared] axs_quietsnap_valueForKey:@"quality"
                                                                        defaultValue:@"1080p"];
    NSString *quality = [value isKindOfClass:[NSString class]] ? value : @"1080p";
    if ([quality isEqualToString:@"480p"]) return AVCaptureSessionPreset640x480;
    if ([quality isEqualToString:@"720p"]) return AVCaptureSessionPreset1280x720;
    if ([quality isEqualToString:@"4k"])   return AVCaptureSessionPreset3840x2160;
    return AVCaptureSessionPreset1920x1080;
}

- (AVCaptureDevice *)axs_quietsnap_videoDeviceWithError:(NSError **)error {
    AxsQuietSnapConfig *config = [AxsQuietSnapConfig axs_quietsnap_shared];
    NSString *position = [config axs_quietsnap_valueForKey:@"position" defaultValue:@"back"];
    BOOL front = [position isEqualToString:@"front"];
    if (!front) {
        id ultraValue = [config axs_quietsnap_valueForKey:@"ultra" defaultValue:@NO];
        if ([ultraValue isKindOfClass:[NSNumber class]] && [ultraValue boolValue]) {
            AVCaptureDevice *ultra =
                [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInUltraWideCamera
                                                   mediaType:AVMediaTypeVideo
                                                    position:AVCaptureDevicePositionBack];
            if (ultra) return ultra;
        }
    }
    AVCaptureDevice *device =
        [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                           mediaType:AVMediaTypeVideo
                                            position:front ? AVCaptureDevicePositionFront
                                                           : AVCaptureDevicePositionBack];
    if (!device) device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device && error) {
        *error = [NSError errorWithDomain:@"com.axs.quietsnap" code:30
                                 userInfo:@{NSLocalizedDescriptionKey: @"No camera device"}];
    }
    return device;
}

- (void)axs_quietsnap_applyFrameRateToDevice:(AVCaptureDevice *)device {
    NSInteger fps = [self axs_quietsnap_fps];
    NSError *error = nil;
    if (![device lockForConfiguration:&error]) {
        return;
    }
    CMTime duration = CMTimeMake(1, (int32_t)fps);
    if ([device respondsToSelector:@selector(setActiveVideoMinFrameDuration:)] &&
        [device respondsToSelector:@selector(setActiveVideoMaxFrameDuration:)]) {
        device.activeVideoMinFrameDuration = duration;
        device.activeVideoMaxFrameDuration = duration;
    }
    [device unlockForConfiguration];
}

- (void)axs_quietsnap_startWithCompletion:(void (^)(BOOL, NSError *))completion {
    @synchronized (self) {
        if (self.recording || self.starting) {
            if (completion) {
                completion(NO, [NSError errorWithDomain:@"com.axs.quietsnap" code:31
                                               userInfo:@{NSLocalizedDescriptionKey: @"Already recording"}]);
            }
            return;
        }
        self.starting = YES;
    }
    self.startCompletion = completion;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        AVCaptureSession *session = [[AVCaptureSession alloc] init];
        if ([session canSetSessionPreset:[self axs_quietsnap_preset]]) {
            session.sessionPreset = [self axs_quietsnap_preset];
        }

        // Keep music/calls alive during recording when the user asked for it.
        id mixValue = [[AxsQuietSnapConfig axs_quietsnap_shared] axs_quietsnap_valueForKey:@"mix"
                                                                              defaultValue:@YES];
        if ([mixValue isKindOfClass:[NSNumber class]] && [mixValue boolValue]) {
            session.automaticallyConfiguresApplicationAudioSession = NO;
            AVAudioSession *audioSession = [AVAudioSession sharedInstance];
            [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                          withOptions:AVAudioSessionCategoryOptionMixWithOthers |
                                      AVAudioSessionCategoryOptionDefaultToSpeaker
                                error:NULL];
            [audioSession setActive:YES error:NULL];
        }

        AVCaptureDevice *videoDevice = [self axs_quietsnap_videoDeviceWithError:&error];
        if (!videoDevice) {
            [self axs_quietsnap_failStart:error];
            return;
        }
        [self axs_quietsnap_applyFrameRateToDevice:videoDevice];

        AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice
                                                                                error:&error];
        if (!videoInput || ![session canAddInput:videoInput]) {
            [self axs_quietsnap_failStart:error ?: [NSError errorWithDomain:@"com.axs.quietsnap"
                                                                       code:32
                                                                   userInfo:@{
                                             NSLocalizedDescriptionKey: @"Cannot add video input"}]];
            return;
        }
        [session addInput:videoInput];

        // Audio track: skipped automatically when the mic is unavailable.
        AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        if (audioDevice) {
            AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice
                                                                                    error:NULL];
            if (audioInput && [session canAddInput:audioInput]) {
                [session addInput:audioInput];
            }
        }

        AVCaptureMovieFileOutput *fileOutput = [[AVCaptureMovieFileOutput alloc] init];
        if (![session canAddOutput:fileOutput]) {
            [self axs_quietsnap_failStart:[NSError errorWithDomain:@"com.axs.quietsnap"
                                                             code:33
                                                         userInfo:@{
                                       NSLocalizedDescriptionKey: @"Cannot add movie output"}]];
            return;
        }
        [session addOutput:fileOutput];

        self.session = session;
        self.fileOutput = fileOutput;
        [session startRunning];
        if (!session.isRunning) {
            [self axs_quietsnap_failStart:[NSError errorWithDomain:@"com.axs.quietsnap"
                                                             code:34
                                                         userInfo:@{
                                       NSLocalizedDescriptionKey: @"Camera session did not start"}]];
            return;
        }

        NSURL *url = [AxsQuietSnapStorage axs_quietsnap_fileURLWithExtension:@"mov"];
        @try {
            [fileOutput startRecordingToOutputFileURL:url recordingDelegate:self];
        } @catch (NSException *exception) {
            [self axs_quietsnap_failStart:[NSError errorWithDomain:@"com.axs.quietsnap"
                                                             code:35
                                                         userInfo:@{
                                       NSLocalizedDescriptionKey: exception.reason ?: @"Start failed"}]];
            return;
        }

        id minutesValue = [[AxsQuietSnapConfig axs_quietsnap_shared]
            axs_quietsnap_valueForKey:@"maxVideoMinutes" defaultValue:@0];
        NSInteger minutes = [minutesValue isKindOfClass:[NSNumber class]] ? [minutesValue integerValue] : 0;
        if (minutes > 0) {
            __weak typeof(self) weakSelf = self;
            dispatch_block_t block = dispatch_block_create(0, ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (self && self.recording) {
                    [self axs_quietsnap_stop];
                }
            });
            self.maxDurationBlock = block;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(minutes * 60 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), block);
        }

        @synchronized (self) {
            self.recording = YES;
            self.starting = NO;
            void (^completion)(BOOL, NSError *) = self.startCompletion;
            self.startCompletion = nil;
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(YES, nil); });
            }
        }
    });
}

- (void)axs_quietsnap_cancelMaxDuration {
    if (self.maxDurationBlock) {
        dispatch_block_cancel(self.maxDurationBlock);
        self.maxDurationBlock = nil;
    }
}

- (void)axs_quietsnap_failStart:(NSError *)error {
    [self axs_quietsnap_cancelMaxDuration];
    [self.session stopRunning];
    self.session = nil;
    self.fileOutput = nil;
    @synchronized (self) {
        self.recording = NO;
        self.starting = NO;
        void (^completion)(BOOL, NSError *) = self.startCompletion;
        self.startCompletion = nil;
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
        }
    }
}

- (void)axs_quietsnap_stop {
    [self axs_quietsnap_cancelMaxDuration];
    AVCaptureMovieFileOutput *output = self.fileOutput;
    if (!output || !output.isRecording) {
        return;
    }
    [output stopRecording];
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)output
    didStartRecordingToOutputFileAtURL:(NSURL *)fileURL
                       fromConnections:(NSArray<AVCaptureConnection *> *)connections {
    // Recording state is already tracked by the start path.
}

- (void)captureOutput:(AVCaptureFileOutput *)output
    didFinishRecordingToOutputFileAtURL:(NSURL *)fileURL
                        fromConnections:(NSArray<AVCaptureConnection *> *)connections
                                  error:(NSError *)error {
    BOOL finished = YES;
    id value = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey];
    if ([value isKindOfClass:[NSNumber class]]) {
        finished = [value boolValue];
    }
    [self axs_quietsnap_cancelMaxDuration];
    if (error && !finished) {
        self.recording = NO;
        [self.session stopRunning];
        self.session = nil;
        self.fileOutput = nil;
        return;
    }
    [AxsQuietSnapStorage axs_quietsnap_saveVideoAtURL:fileURL completion:^(BOOL success, NSError *saveError) {
        [self.session stopRunning];
        self.session = nil;
        self.fileOutput = nil;
        self.recording = NO;
    }];
}

@end
