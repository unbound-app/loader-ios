#import "../Headers/Unbound.h"

/**
 * Adds a way to delete a file at a specific path on the JS side.
 * ---
 * This acts as a special way to call [DCDPhotosManager deletePhotos]
 * So, instead of calling with an array of the uris of each photo to delete,
 * You would call with "unbound" as the 0th argument in the array,
 * and must pass the full path of the dirent to delete as the 1st argument.
 * ---
 * You can either delete a file or dir, just pass the appropriate path (hence "dirent")
 * The promise is handled, so using .then().catch() or await should work.
 */
%hook DCDPhotosManager
    - (void) deletePhotos:(NSArray*)uris resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
        if ([uris[0] isEqualToString:@"unbound"]) {
            if (!uris[1] || ![uris[1] isKindOfClass:[NSString class]]) {
                reject(@"err", @"Failed to delete dirent: Path passed is invalid.", nil);
            }

            NSString* path = uris[1];
            NSLog("Attempting to delete dirent at path %@...", path);

            @try {
                id result = [FileSystem delete:path];
                NSString* message = nil;

                if (![result isKindOfClass:[NSError class]]) {
                    message = [NSString stringWithFormat:@"Successfully deleted dirent at path '%@'", path];

                    NSLog("%@", message);
                    resolve(message);
                } else {
                    message = [NSString stringWithFormat:@"Failed to delete dirent at path '%@': %@", path, [result localizedDescription]];

                    NSLog("%@", message);
                    reject(@"err", message, nil);
                }
            } @catch (NSException *e) {
                NSLog(@"Failed to call promise methods: %@", e);
            }
        } else {
            %orig(uris, resolve, reject);
        }
    }
%end

%hook RCTCxxBridge
	- (void) executeApplicationScript:(NSData *)script url:(NSURL *)url async:(BOOL)async {
		[FileSystem init];
		[Settings init];
		[Plugins init];
		[Themes init];

		NSString *BUNDLE = [NSString pathWithComponents:@[FileSystem.documents, @"bundle.js"]];
		NSURL *SOURCE = [NSURL URLWithString:@"unbound"];

		// Don't load bundle if not configured to do so.
		if (![Settings getBoolean:@"unbound" key:@"loader.enabled" def:YES]) {
			NSLog(@"Loader is disabled");
			return %orig;
		}

		// Apply React DevTools patch if its enabled
		if ([Settings getBoolean:@"unbound" key:@"loader.devtools" def:NO]) {
			@try {
				NSData *bundle = [Utilities getResource:@"devtools" data:true];

				NSLog(@"Attempting to execute DevTools bundle...");
				%orig(bundle, SOURCE, false);
				NSLog(@"Successfully executed DevTools bundle.");
			} @catch (NSException *e) {
				NSLog(@"React DevTools failed to initialize. %@", e);
			}
		}

		// Apply modules patch
		@try {
			NSData *bundle = [Utilities getResource:@"modules" data:true];

			NSLog(@"Attempting to execute modules patch...");
			%orig(bundle, SOURCE, false);
			NSLog(@"Successfully executed modules patch.");
		} @catch (NSException *e) {
			NSLog(@"Modules patch injection failed, expect issues. %@", e);
		}

		// Preload Unbound's settings, plugins & themes
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

		%orig(script, url, false);

		// Check for updates & re-download bundle if necessary
		if (![FileSystem exists:BUNDLE] || [Updater hasUpdate]) {
			@try {
				NSURL *url = [Updater getDownloadURL];

				NSLog(@"Downloading bundle...");
				[FileSystem download:url path:BUNDLE];

				if ([Updater etag] != nil) {
					[Settings set:@"unbound" key:@"loader.update.etag" value:[Updater etag]];
				}

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

		// Check if Unbound was downloaded properly
		if (![FileSystem exists:BUNDLE]) {
			return [Utilities alert:@"Bundle not found, please report this to the developers."];
		}

		// Inject Unbound script
		@try {
			NSData *bundle = [FileSystem readFile:BUNDLE];

			NSLog(@"Attempting to execute bundle...");
			%orig(bundle, SOURCE, true);
			NSLog(@"Unbound's bundle successfully executed.");
		} @catch (NSException *e) {
			NSLog(@"Unbound's bundle failed execution, aborting. (%@)", e.reason);
			return [Utilities alert:@"Failed to load Unbound's bundle. Please report this to the developers."];
		}
	}
%end