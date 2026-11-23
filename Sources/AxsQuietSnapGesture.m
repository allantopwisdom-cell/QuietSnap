#import "AxsQuietSnapGesture.h"
#import <dispatch/dispatch.h>
#import "AxsQuietSnapCapture.h"

static const NSTimeInterval AxsQuietSnapLongPressDelay = 0.55;
static const NSTimeInterval AxsQuietSnapDoublePressWindow = 0.30;

/// Tracks one physical button: single tap, double tap and long press.
@interface AxsQuietSnapButtonTracker : NSObject
@property (nonatomic, copy) void (^handler)(NSInteger action); // 1 single, 2 double, 3 long
@property (nonatomic, assign) BOOL longFired;
@property (nonatomic, assign) BOOL secondPress;
@property (nonatomic, strong) dispatch_block_t singleBlock;
@property (nonatomic, strong) dispatch_block_t longBlock;
@end

@implementation AxsQuietSnapButtonTracker

- (void)dealloc {
    if (_singleBlock) dispatch_block_cancel(_singleBlock);
    if (_longBlock) dispatch_block_cancel(_longBlock);
}

- (void)axs_quietsnap_down {
    if (self.longBlock) {
        dispatch_block_cancel(self.longBlock);
        self.longBlock = nil;
    }
    if (self.singleBlock) {
        // Second press inside the double-tap window.
        dispatch_block_cancel(self.singleBlock);
        self.singleBlock = nil;
        self.secondPress = YES;
    } else {
        self.secondPress = NO;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.longFired = YES;
        self.longBlock = nil;
        if (self.handler) self.handler(3);
    });
    self.longBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(AxsQuietSnapLongPressDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), block);
}

- (void)axs_quietsnap_up {
    if (self.longBlock) {
        dispatch_block_cancel(self.longBlock);
        self.longBlock = nil;
    }
    if (self.longFired) {
        self.longFired = NO;
        self.secondPress = NO;
        return;
    }
    if (self.secondPress) {
        self.secondPress = NO;
        if (self.handler) self.handler(2);
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.singleBlock = nil;
        if (self.handler) self.handler(1);
    });
    self.singleBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(AxsQuietSnapDoublePressWindow * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), block);
}

@end

@interface AxsQuietSnapGesture ()
@property (nonatomic, strong) AxsQuietSnapButtonTracker *upTracker;
@property (nonatomic, strong) AxsQuietSnapButtonTracker *downTracker;
@end

@implementation AxsQuietSnapGesture

+ (instancetype)axs_quietsnap_shared {
    static AxsQuietSnapGesture *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _upTracker = [[AxsQuietSnapButtonTracker alloc] init];
        _downTracker = [[AxsQuietSnapButtonTracker alloc] init];

        __weak typeof(self) weakSelf = self;
        _upTracker.handler = ^(NSInteger action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            AxsQuietSnapGestureKind kind = AxsQuietSnapGestureKindNone;
            if (action == 1) kind = AxsQuietSnapGestureKindSingleUp;
            else if (action == 2) kind = AxsQuietSnapGestureKindDoubleUp;
            else if (action == 3) kind = AxsQuietSnapGestureKindLongUp;
            [[AxsQuietSnapCapture axs_quietsnap_shared] axs_quietsnap_handleGesture:kind];
        };
        _downTracker.handler = ^(NSInteger action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            AxsQuietSnapGestureKind kind = AxsQuietSnapGestureKindNone;
            if (action == 1) kind = AxsQuietSnapGestureKindSingleDown;
            else if (action == 2) kind = AxsQuietSnapGestureKindDoubleDown;
            else if (action == 3) kind = AxsQuietSnapGestureKindLongDown;
            [[AxsQuietSnapCapture axs_quietsnap_shared] axs_quietsnap_handleGesture:kind];
        };
    }
    return self;
}

- (void)axs_quietsnap_volumeUpDown   { [self.upTracker axs_quietsnap_down]; }
- (void)axs_quietsnap_volumeUpUp     { [self.upTracker axs_quietsnap_up]; }
- (void)axs_quietsnap_volumeDownDown { [self.downTracker axs_quietsnap_down]; }
- (void)axs_quietsnap_volumeDownUp   { [self.downTracker axs_quietsnap_up]; }

@end
