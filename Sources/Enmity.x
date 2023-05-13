#import "../Headers/Enmity.h"

%hook RCTCxxBridge
	- (void) executeApplicationScript:(NSData *)script url:(NSURL *)url async:(BOOL)async {
		NSString *BUNDLE = [NSString pathWithComponents:@[FileSystem.documents, @"bundle.js"]];
		NSURL *SOURCE = [NSURL URLWithString:@"enmity"];

		// Don't load bundle if not configured to do so.
		if (![Settings getBoolean:@"enmity" key:@"loader.enabled" def:YES]) {
			NSLog(@"Loader is disabled");
			return %orig;
		}

		// Apply React DevTools patch if its enabled
		if ([Settings getBoolean:@"enmity" key:@"loader.devtools" def:NO]) {
			@try {
				NSData *bundle = [Utilities getResource:@"devtools" data:true];

				NSLog(@"Injecting React DevTools patch");
				%orig(bundle, SOURCE, false);
			} @catch (NSException *e) {
				NSLog(@"React DevTools failed to initialize. %@", e);
			}
		}

		// Apply modules patch
		@try {
			NSData *bundle = [Utilities getResource:@"modules" data:true];

			NSLog(@"Injecting modules patch");
			%orig(bundle, SOURCE, false);
		} @catch (NSException *e) {
			NSLog(@"Modules patch injection failed, expect issues. %@", e);
		}

		// Preload Enmity's settings, plugins & themes
		@try {
			NSString *bundle = [Utilities getResource:@"preload"];
			NSString *settings = [Settings getSettings];
			NSString *plugins = [Plugins makeJSON];
			NSString *themes = [Themes makeJSON];

			NSString *json = [NSString stringWithFormat:bundle, settings, plugins, themes];
			NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];

			NSLog(@"Pre-loading settings, plugins and themes...");
			%orig(data, SOURCE, false);
			NSLog(@"Pre-loaded settings, plugins and themes.");
		} @catch (NSException *e) {
			NSLog(@"Failed to pre-load settings, plugins and themes. %@", e);
		}

		NSLog(@"Executing Discord's bundle");
		%orig(script, url, false);

		// Check for updates & re-download bundle if necessary
		if (![FileSystem exists:BUNDLE] || [Updater hasUpdate]) {
			@try {
				NSURL *url = [Updater getDownloadURL];

				NSLog(@"Downloading bundle...");
				[FileSystem download:url path:BUNDLE];
				NSLog(@"Bundle downloaded.");
			} @catch (NSException *e) {
				NSLog(@"Bundle download failed: %@", e.reason);

				if (![FileSystem exists:BUNDLE]) {
					return [Utilities alert:@"Bundle failed to download, please report this to the developers."];
				} else {
					[Utilities alert:@"Bundle failed to update, loading out of date bundle."];
				}
			}
		}

		// Check if Enmity was downloaded properly
		if (![FileSystem exists:BUNDLE]) {
			return [Utilities alert:@"Bundle not found, please report this to the developers."];
		}

		// Inject Enmity script
		@try {
			NSData *bundle = [FileSystem readFile:BUNDLE];

			NSLog(@"Executing Enmity's bundle...");
			%orig(bundle, SOURCE, false);
			NSLog(@"Enmity's bundle successfully executed.");
		} @catch (NSException *e) {
			NSLog(@"Enmity's bundle failed execution, aborting. (%@)", e.reason);
			return [Utilities alert:@"Failed to load Enmity's bundle. Please report this to the developers."];
		}
	}
%end

%ctor {
	[FileSystem init];
	[Settings init];
	[Plugins init];
	[Themes init];
}