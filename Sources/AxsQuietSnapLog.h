#pragma once

#import <Foundation/Foundation.h>

/// Appends a timestamped line to /var/mobile/Library/QuietSnap/QuietSnap.log
/// and mirrors it to NSLog. Used for on-device diagnosis without a Mac.
void axs_quietsnap_log(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
