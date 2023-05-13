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

%group Debug
	%hook NSError
		- (id) initWithDomain:(id)domain code:(int)code userInfo:(id)userInfo {
			NSLog(@"Error initialized with message %@ %@ %d", userInfo, domain, code)
			return %orig();
		};
	%end
%end

%ctor {
	%init()

	if (IS_DEBUG) {
		%init(Debug)
	}
}