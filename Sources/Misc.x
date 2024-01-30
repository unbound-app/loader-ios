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

// Fix issues with sideloading
%hook NSFileManager
	- (NSURL*)containerURLForSecurityApplicationGroupIdentifier:(NSString*)identifier {
		if (identifier != nil) {
			NSError *error;

			NSFileManager *manager = [NSFileManager defaultManager];
			NSURL *url = [manager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];

			if (error) {
				NSLog(@"[Error] Failed getting documents directory: %@", error);
				return %orig(identifier);
			}

			return url;
		}

		return %orig(identifier);
	}
%end

%group Debug
	%hook NSError
		- (id) initWithDomain:(id)domain code:(int)code userInfo:(id)userInfo {
			NSLog(@"[Error] Initialized with info: %@ %@ %d", userInfo, domain, code);
			return %orig();
		};

		+ (id) errorWithDomain:(id)domain code:(int)code userInfo:(id)userInfo {
			NSLog(@"[Error] Initialized with info: %@ %@ %d", userInfo, domain, code);
			return %orig();
		};
	%end

	%hook NSException
		- (id) initWithName:(id)name reason:(id)reason userInfo:(id)userInfo {
			NSLog(@"[Exception] Initialized with info: %@ %@ %@", userInfo, name, reason);
			return %orig();
		};

		+ (id) exceptionWithName:(id)name reason:(id)reason userInfo:(id)userInfo {
			NSLog(@"[Exception] Initialized with info: %@ %@ %@", userInfo, name, reason);
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