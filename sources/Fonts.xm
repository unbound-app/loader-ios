#import "../Headers/Fonts.h"

@implementation Fonts
	static NSMutableDictionary<NSString*, NSString*> *overrides = nil;
	static NSMutableArray<NSDictionary<NSString*, NSString*>*> *fonts = nil;

	+ (NSString*) makeJSON {
		NSError *error;
		NSData *data = [NSJSONSerialization dataWithJSONObject:fonts options:0 error:&error];


		if (error != nil) {
			return @"[]";
		} else {
			return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		}
	};

	+ (NSString*) makeAvailableJSON {
		NSError *error;

		NSArray *availabeFonts = [Fonts getAvailableFonts];

		NSData *data = [NSJSONSerialization dataWithJSONObject:availabeFonts options:0 error:&error];

		if (error != nil) {
			return @"[]";
		} else {
			return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		}
	};

	+ (NSArray*) getAvailableFonts {
		CFArrayRef available = CTFontManagerCopyAvailableFontFamilyNames();
		NSArray *fonts = (__bridge NSArray*)available;

		return fonts ? fonts : @[];
	}

	+ (void) init {
		if (!fonts) {
			fonts = [[NSMutableArray alloc] init];
		}

		if (!overrides) {
			overrides = [[NSMutableDictionary alloc] init];
		}

		NSString *path = [NSString pathWithComponents:@[FileSystem.documents, @"Fonts"]];
		[FileSystem createDirectory:path];

		NSArray *contents = [FileSystem readDirectory:path];

		for (NSString* file in contents) {
			NSLog(@"[Fonts] Attempting to load %@...", file);

			@try {
				NSString *font = [NSString pathWithComponents:@[path, file]];
				NSString *name = [Fonts getFontName:font];

				NSLog(@"[Fonts] Registering font: %@", font);

				[fonts addObject:@{
					@"name": name,
					@"file": file,
					@"path": font
				}];
			} @catch (NSException *e) {
				NSLog(@"[Fonts] Failed to load %@ (%@)", file, e.reason);
			}
		}

		@try {
			NSLog(@"[Fonts] Loading...");
			[Fonts apply];
			NSLog(@"[Fonts] Successfully loaded.");
		} @catch (NSException *e) {
			NSLog(@"[Fonts] [Error] Failed to load. (%@)", e.reason);
		}
	};

	+ (void) apply {
		NSDictionary *states = [Settings getDictionary:@"unbound" key:@"font-states" def:@{}];

		for (NSString* state in states) {
			NSString *override = states[state];
			if (!override) continue;

			NSPredicate *customPredicate = [NSPredicate predicateWithFormat:@"name == %@", override];
			NSArray *custom = [fonts filteredArrayUsingPredicate:customPredicate];


			NSArray *loadedSystemFonts = [Fonts getAvailableFonts];
			NSPredicate *systemPredicate = [NSPredicate predicateWithFormat:@"SELF == %@", override];
			NSArray *systemFonts = [loadedSystemFonts filteredArrayUsingPredicate:systemPredicate];

			if ([custom count] == 0 && [systemFonts count] == 0) {
				NSLog(@"[Fonts] [Error] Failed to replace \"%@\" with \"%@\". The requested font isn't loaded.", state, override);
				continue;
			}

			@try {
				NSDictionary *font =  [custom count] != 0 ? custom[0] : systemFonts[0];
				if (!font) continue;

				BOOL isString = [font isKindOfClass:[NSString class]];

				if (!isString && font[@"path"] != nil) {
					NSString *path = font[@"path"];
					if (!path) continue;
					[Fonts loadFont:path];
				}

				overrides[state] = isString ? font : font[@"name"];
			} @catch (NSException* e) {
				NSLog(@"[Fonts] Failed to load font \"%@\". (%@)", override, e.reason);
			}
		}
	}

	+ (void) loadFont:(NSString*)path {
		NSURL *url = [NSURL fileURLWithPath:path];

		CGDataProviderRef provider = CGDataProviderCreateWithURL((__bridge CFURLRef)url);
		CGFontRef ref = CGFontCreateWithDataProvider(provider);

		CGDataProviderRelease(provider);
		CTFontManagerRegisterGraphicsFont(ref, nil);

		NSString *name = [Fonts getFontNameByRef:ref];
		CGFontRelease(ref);

		NSLog(@"[Fonts] Loaded font: %@.", name);
	}

	+ (NSString*) getFontName:(NSString*)path {
		NSURL *url = [NSURL fileURLWithPath:path];

		CGDataProviderRef provider = CGDataProviderCreateWithURL((__bridge CFURLRef)url);
		CGFontRef ref = CGFontCreateWithDataProvider(provider);

		CGDataProviderRelease(provider);
		return [Fonts getFontNameByRef:ref];
	}

	+ (NSString*) getFontNameByRef:(CGFontRef)ref {
		return CFBridgingRelease(CGFontCopyFullName(ref));
	}

	// Properties
	+ (NSMutableDictionary<NSString*, NSString*>*) overrides {
		return overrides;
	}
@end

%hook UIFont
	+ (UIFont *)fontWithName:(NSString *)name size:(CGFloat)size {
		NSDictionary *overrides = [Fonts overrides];
		NSObject *all = overrides[@"*"];

		if (overrides[name] || all) {
			return %orig(all ? all : overrides[name], size);
		}

		return %orig;
	}
%end
