#import "AxsQuietSnapPhoto.h"
#import "AxsQuietSnapStorage.h"
#import "AxsQuietSnapConfig.h"
#import <AVFoundation/AVFoundation.h>

@interface AxsQuietSnapPhoto () <AVCapturePhotoCaptureDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCapturePhotoOutput *output;
@property (nonatomic, copy) void (^completion)(BOOL, NSError *);
@property (nonatomic, assign) BOOL capturing;
- (void)axs_quietsnap_finishWithImage:(UIImage *)image error:(NSError *)error;
@end

@implementation AxsQuietSnapPhoto

- (void)dealloc {
    [self.session stopRunning];
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

- (AVCaptureDevice *)axs_quietsnap_deviceWithError:(NSError **)error {
    AxsQuietSnapConfig *config = [AxsQuietSnapConfig axs_quietsnap_shared];
    NSString *position = [config axs_quietsnap_valueForKey:@"position" defaultValue:@"back"];
    BOOL front = [position isEqualToString:@"front"];

    if (!front) {
        id ultraValue = [config axs_quietsnap_valueForKey:@"ultra" defaultValue:@NO];
        BOOL ultra = [ultraValue isKindOfClass:[NSNumber class]] && [ultraValue boolValue];
        if (ultra) {
            AVCaptureDevice *device =
                [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInUltraWideCamera
                                                   mediaType:AVMediaTypeVideo
                                                    position:AVCaptureDevicePositionBack];
            if (device) return device;
        }
    }

    AVCaptureDevice *device =
        [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                           mediaType:AVMediaTypeVideo
                                            position:front ? AVCaptureDevicePositionFront
                                                           : AVCaptureDevicePositionBack];
    if (!device) {
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    if (!device && error) {
        *error = [NSError errorWithDomain:@"com.axs.quietsnap" code:20
                                 userInfo:@{NSLocalizedDescriptionKey: @"No camera device"}];
    }
    return device;
}

- (void)axs_quietsnap_captureWithCompletion:(void (^)(BOOL, NSError *))completion {
    @synchronized (self) {
        if (self.capturing) {
            if (completion) {
                completion(NO, [NSError errorWithDomain:@"com.axs.quietsnap" code:21
                                               userInfo:@{NSLocalizedDescriptionKey: @"Capture in progress"}]);
            }
            return;
        }
        self.capturing = YES;
    }
    self.completion = completion;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        AVCaptureSession *session = [[AVCaptureSession alloc] init];
        if ([session canSetSessionPreset:[self axs_quietsnap_preset]]) {
            session.sessionPreset = [self axs_quietsnap_preset];
        }

        AVCaptureDevice *device = [self axs_quietsnap_deviceWithError:&error];
        if (!device) {
            [self axs_quietsnap_finishWithImage:nil error:error];
            return;
        }
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
        if (!input || ![session canAddInput:input]) {
            [self axs_quietsnap_finishWithImage:nil
                                          error:error ?: [NSError errorWithDomain:@"com.axs.quietsnap"
                                                                             code:22
                                                                         userInfo:@{
                                             NSLocalizedDescriptionKey: @"Cannot add camera input"}]];
            return;
        }
        [session addInput:input];

        AVCapturePhotoOutput *output = [[AVCapturePhotoOutput alloc] init];
        if (![session canAddOutput:output]) {
            [self axs_quietsnap_finishWithImage:nil
                                          error:[NSError errorWithDomain:@"com.axs.quietsnap"
                                                                    code:23
                                                                userInfo:@{
                                          NSLocalizedDescriptionKey: @"Cannot add photo output"}]];
            return;
        }
        [session addOutput:output];
        self.session = session;
        self.output = output;

        [session startRunning];
        if (!session.isRunning) {
            [self axs_quietsnap_finishWithImage:nil
                                          error:[NSError errorWithDomain:@"com.axs.quietsnap"
                                                                    code:24
                                                                userInfo:@{
                                          NSLocalizedDescriptionKey: @"Camera session did not start"}]];

            return;
        }

        AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
        if (@available(iOS 13.0, *)) {
            settings.photoQualityPrioritization = AVCapturePhotoQualityPrioritizationQuality;
        }
        // Give the pipeline one frame before asking for a photo.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @try {
                [output capturePhotoWithSettings:settings delegate:self];
            } @catch (NSException *exception) {
                [self axs_quietsnap_finishWithImage:nil
                                              error:[NSError errorWithDomain:@"com.axs.quietsnap"
                                                                        code:25
                                                                    userInfo:@{
                                              NSLocalizedDescriptionKey: exception.reason ?: @"Capture failed"}]];
            }
        });
    });
}

- (void)axs_quietsnap_finishWithImage:(UIImage *)image error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.session stopRunning];
        self.session = nil;
        self.output = nil;
        self.capturing = NO;
        void (^completion)(BOOL, NSError *) = self.completion;
        self.completion = nil;
        if (!image) {
            if (completion) completion(NO, error);
            return;
        }
        [AxsQuietSnapStorage axs_quietsnap_saveImage:image completion:^(BOOL success, NSError *saveError) {
            if (completion) completion(success, saveError);
        }];
    });
}

#pragma mark - AVCapturePhotoCaptureDelegate

- (void)captureOutput:(AVCapturePhotoOutput *)output
    didFinishProcessingPhoto:(AVCapturePhoto *)photo
                       error:(NSError *)error {
    if (error || !photo) {
        [self axs_quietsnap_finishWithImage:nil error:error];
        return;
    }
    NSData *data = [photo fileDataRepresentation];
    UIImage *image = data ? [UIImage imageWithData:data] : nil;
    [self axs_quietsnap_finishWithImage:image
                                  error:image ? nil : [NSError errorWithDomain:@"com.axs.quietsnap"
                                                                          code:26
                                                                      userInfo:@{
                                            NSLocalizedDescriptionKey: @"Photo decode failed"}]];
}

@end
