#import "../Headers/Updater.h"

@implementation Updater
	+ (BOOL) hasUpdate {
		NSLog(@"Checking for updates...");

		if ([Settings getBoolean:@"unbound" key:@"loader.update.force" def:NO]) {
			NSLog(@"[Updater] Forcing update due to config.");
			return YES;
		}

		return YES;
	}

	+ (NSURL*) getDownloadURL {
		NSString *url = [Settings getString:@"unbound" key:@"loader.update.url" def:@"https://raw.githubusercontent.com/unbound-mod/unbound/main/dist/bundle.js"];

		return [NSURL URLWithString:url];
	}
@end