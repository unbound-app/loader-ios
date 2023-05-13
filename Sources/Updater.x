#import "../Headers/Updater.h"

@implementation Updater
	+ (BOOL) hasUpdate {
		NSLog(@"Checking for updates...");

		if ([Settings getBoolean:@"enmity" key:@"loader.update.force" def:NO]) {
			NSLog(@"[Updater] Forcing update due to config.");
			return YES;
		}

		return YES;
	}

	+ (NSURL*) getDownloadURL {
		NSString *url = [Settings getString:@"enmity" key:@"loader.update.url" def:@"https://raw.githubusercontent.com/enmity-mod/enmity/main/dist/bundle.js"];

		return [NSURL URLWithString:url];
	}
@end