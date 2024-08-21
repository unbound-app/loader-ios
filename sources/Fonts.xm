#import "../Headers/Fonts.h"
#import <objc/runtime.h>
#import <substrate.h>

@implementation Fonts
	static NSMutableDictionary<NSString*, NSString*> *overrides = nil;
	static NSMutableArray *fonts = nil;

	+ (NSString*) makeJSON {
		NSError *error;
		NSData *data = [NSJSONSerialization dataWithJSONObject:fonts options:0 error:&error];

		if (error != nil) {
			return @"[]";
		} else {
			return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		}
	};

	+ (NSDictionary*) getApplied {
		NSDictionary *settings = [Settings getDictionary:@"font-states" key:@"overrides" def:@{}];

		NSLog(@"%@", settings);
		// NSPredicate *predicate = [NSPredicate predicateWithFormat:@"manifest.id == %@", key];
		// NSArray *array = [fonts filteredArrayUsingPredicate:predicate];

		// if ([array count] != 0) {
		// 	return array[0];
		// }

		return nil;
	}

	+ (void) init {
		overrides = [[NSMutableDictionary alloc] init];
		fonts = [[NSMutableArray alloc] init];

		NSString *path = [NSString pathWithComponents:@[FileSystem.documents, @"Fonts"]];
		[FileSystem createDirectory:path];

		NSArray *contents = [FileSystem readDirectory:path];

		for (NSString* file in contents) {
			NSLog(@"[Fonts] Attempting to load %@...", file);

			@try {
				NSString *font = [NSString pathWithComponents:@[path, file]];

				NSLog(@"[Fonts] Font file %@", font);
				[fonts addObject:@{
					@"name": file,
					@"path": font
				}];
			} @catch (NSException *e) {
				NSLog(@"[Fonts] Failed to load %@ (%@)", file, e.reason);
			}
		}

		if ([Settings getBoolean:@"unbound" key:@"loader.enabled" def:YES] && ![Settings getBoolean:@"unbound" key:@"recovery" def:NO]) {
			@try {
				// [Fonts apply];
				NSLog(@"[Fonts] Are present.")
				[Fonts getApplied];
			} @catch (NSException *e) {
				NSLog(@"[Fonts] Failed to apply theme. (%@)", e.reason);
			}
		}

		NSLog(@"[Fonts] Registry: %@", fonts);

		// NSDictionary<NSString*, NSDictionary*> *theme = [Fonts getApplied];
		// if (!theme || !theme[@"bundle"] || !theme[@"bundle"][@"fonts"]) {
		// 	return;
		// }

		// NSDictionary<NSString*, NSString*> *overrides = theme[@"bundle"][@"fonts"];

		// for	(NSString *key in overrides) {
		// 	@try {
		// 		NSString *font = [overrides objectForKey:key];
		// 		if (!font) continue;

		// 		NSURL *url = [NSURL URLWithString:font];

		// 		NSLog(@"[Fonts] Downloading font \"%@\"...", [url lastPathComponent]);
		// 		NSString *name = [Fonts downloadFont:url];
		// 		NSLog(@"[Fonts] Downloaded font \"%@\".", name);

		// 		NSLog(@"[Fonts] Loading font \"%@\"...", name);
		// 		[Fonts loadFont:name orig:key];
		// 		NSLog(@"[Fonts] Loaded font \"%@\".", name);
		// 	} @catch(NSException *e) {
		// 		NSLog(@"[Fonts] Failed to apply font override for \"%@\". (%@)", key, e.reason);
		// 	}
		// }
	};

	+ (NSString*) downloadFont:(NSURL*)url {
		NSString *name = [url lastPathComponent];
		NSString *path = [NSString pathWithComponents:@[FileSystem.documents, @"Fonts", name]];

		if ([FileSystem exists:path]) {
			return name;
		}

		NSData *data = [NSData dataWithContentsOfURL:url];
		if (!data) return nil;

		[data writeToFile:path atomically:YES];

		return name;
	}

	+ loadFont:(NSString*)name orig:(NSString*)orig {
		@try {
			NSString *path = [NSString pathWithComponents:@[FileSystem.documents, @"Fonts", name]];
			NSURL *url = [NSURL fileURLWithPath:path];

			CGDataProviderRef provider = CGDataProviderCreateWithURL((__bridge CFURLRef)url);
			CGFontRef ref = CGFontCreateWithDataProvider(provider);

			CGDataProviderRelease(provider);
			CTFontManagerRegisterGraphicsFont(ref, nil);

			NSString *font = CFBridgingRelease(CGFontCopyPostScriptName(ref));
			[overrides setValue:font forKey:orig];
			CGFontRelease(ref);
		} @catch (NSException* e) {
			NSLog(@"[Fonts] Failed to load font \"%@\". (%@)", name, e.reason);
		}
	}

	// Properties
	+ (NSMutableDictionary<NSString*, NSString*>*) overrides {
		return overrides;
	}
@end

%hook UIFont
	+ (UIFont *)fontWithName:(NSString *)name size:(CGFloat)size {
		NSMutableDictionary<NSString*, NSString*> *overrides = [Fonts overrides];

		if (overrides && [overrides objectForKey:name] != nil) {
			return %orig([overrides objectForKey:name], size);
		}

		return %orig(name, size);
	}
%end