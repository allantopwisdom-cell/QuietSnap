#import "AxsQuietSnapLog.h"

static NSString *axs_quietsnap_log_path(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *dir = @"/var/mobile/Library/QuietSnap";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        path = [dir stringByAppendingPathComponent:@"QuietSnap.log"];
    });
    return path;
}

void axs_quietsnap_log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[QuietSnap] %@", message);

    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"MM-dd HH:mm:ss.SSS"];
    });

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [formatter stringFromDate:[NSDate date]], message];

    static id axs_log_anchor;
    static dispatch_once_t anchor_once;
    dispatch_once(&anchor_once, ^{ axs_log_anchor = [NSObject new]; });

    @synchronized (axs_log_anchor) {
        NSString *path = axs_quietsnap_log_path();
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
        if ([attrs fileSize] > 512 * 1024) {
            [fm removeItemAtPath:path error:NULL];
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!handle) {
            [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
            return;
        }
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}
