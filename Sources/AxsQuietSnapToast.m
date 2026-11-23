#import "AxsQuietSnapToast.h"

static UIWindow *axs_quietsnap_toast_window;
static UIView *axs_quietsnap_toast_container;

@interface AxsQuietSnapToast ()
+ (void)axs_quietsnap_presentMessage:(NSString *)message;
@end

@implementation AxsQuietSnapToast

+ (void)axs_quietsnap_showMessage:(NSString *)message {
    if (message.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self axs_quietsnap_presentMessage:message];
    });
}

+ (void)axs_quietsnap_presentMessage:(NSString *)message {
    if (!axs_quietsnap_toast_window) {
        axs_quietsnap_toast_window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        axs_quietsnap_toast_window.windowLevel = UIWindowLevelAlert + 10;
        axs_quietsnap_toast_window.backgroundColor = [UIColor clearColor];
        axs_quietsnap_toast_window.userInteractionEnabled = NO;
        axs_quietsnap_toast_window.rootViewController = [[UIViewController alloc] init];
        axs_quietsnap_toast_window.rootViewController.view.backgroundColor = [UIColor clearColor];
        axs_quietsnap_toast_window.rootViewController.view.userInteractionEnabled = NO;
    }

    [axs_quietsnap_toast_container removeFromSuperview];
    axs_quietsnap_toast_container = nil;

    UIFont *font = [UIFont boldSystemFontOfSize:15.0];
    CGSize limit = CGSizeMake([UIScreen mainScreen].bounds.size.width * 0.8, CGFLOAT_MAX);
    CGRect textRect = [message boundingRectWithSize:limit
                                            options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:@{NSFontAttributeName: font}
                                            context:nil];
    CGSize textSize = CGSizeMake(ceil(textRect.size.width), ceil(textRect.size.height));

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0,
        textSize.width + 32.0, textSize.height + 20.0)];
    container.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
    container.layer.cornerRadius = 14.0;
    container.layer.masksToBounds = YES;
    container.alpha = 0.0;
    container.userInteractionEnabled = NO;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 10.0, textSize.width, textSize.height)];
    label.text = message;
    label.font = font;
    label.textColor = [UIColor whiteColor];
    label.numberOfLines = 0;
    label.userInteractionEnabled = NO;
    [container addSubview:label];

    UIWindow *window = axs_quietsnap_toast_window;
    CGSize screen = window.bounds.size;
    CGFloat topInset = 60.0;
    if (@available(iOS 11.0, *)) {
        topInset += window.safeAreaInsets.top;
    }
    container.center = CGPointMake(screen.width / 2.0, topInset + container.bounds.size.height / 2.0);
    [window.rootViewController.view addSubview:container];
    axs_quietsnap_toast_container = container;
    window.hidden = NO;

    [UIView animateWithDuration:0.2 animations:^{
        container.alpha = 1.0;
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                container.alpha = 0.0;
            } completion:^(BOOL done) {
                if (container == axs_quietsnap_toast_container) {
                    [container removeFromSuperview];
                    axs_quietsnap_toast_container = nil;
                    axs_quietsnap_toast_window.hidden = YES;
                }
            }];
        });
    }];
}

@end
