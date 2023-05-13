#import "../Headers/Misc.h"

%hook SentrySDK
	+ (void) startWithOptionsObject:(id)options {
		NSLog(@"Blocked SentrySDK.");
		return;
	}

	+ (BOOL) isEnabled {
		return NO;
	}
%end