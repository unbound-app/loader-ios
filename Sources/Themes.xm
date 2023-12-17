#import "../Headers/Themes.h"
#import <objc/runtime.h>
#import <substrate.h>

@implementation Themes
	static NSMutableArray *themes = nil;
	static NSMutableDictionary<NSString*, NSString*> *fonts = nil;

	+ (NSString*) makeJSON {
		NSError *error;
		NSData *data = [NSJSONSerialization dataWithJSONObject:themes options:0 error:&error];

		if (error != nil) {
			return @"[]";
		} else {
			return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		}
	};

	+ (NSDictionary*) getApplied {
		NSString *key = [Settings getString:@"theme-states" key:@"applied" def:nil];

		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"manifest.id == %@", key];
		NSArray *array = [themes filteredArrayUsingPredicate:predicate];

		if ([array count] != 0) {
			return array[0];
		}

		return nil;
	}

	+ (void) init {
		fonts = [[NSMutableDictionary alloc] init];
		themes = [[NSMutableArray alloc] init];

		NSString *path = [NSString pathWithComponents:@[FileSystem.documents, @"Themes"]];
		[FileSystem createDirectory:path];

		NSString *fontsPath = [NSString pathWithComponents:@[FileSystem.documents, @"Fonts"]];
		[FileSystem createDirectory:fontsPath];

		NSArray *contents = [FileSystem readDirectory:path];

		for (NSString* folder in contents) {
			NSLog(@"[Themes] Attempting to load %@...", folder);

			@try {
				NSString *dir = [NSString pathWithComponents:@[path, folder]];

				if (![FileSystem isDirectory:dir]) {
					NSLog(@"[Themes] Skipping %@ as it is not a directory.", folder);
					continue;
				}

				NSString *data = [NSString pathWithComponents:@[dir, @"manifest.json"]];
				if(![FileSystem exists:data]) {
					NSLog(@"[Themes] Skipping %@ as it is missing a manifest.", folder);
					continue;
				}

				__block NSMutableDictionary *manifest = nil;

				@try {
					id json = [Utilities parseJSON:[FileSystem readFile:data]];

					if([json isKindOfClass:[NSDictionary class]]) {
						manifest = [json mutableCopy];
					} else {
						NSLog(@"[Themes] Skipping %@ as its manifest is invalid.", folder);
						continue;
					}
				} @catch (NSException *e) {
					NSLog(@"[Themes] Skipping %@ as its manifest failed to be parsed. (%@)", folder, e.reason);
					continue;
				}

				NSString *entry = [NSString pathWithComponents:@[dir, @"bundle.json"]];
				if(![FileSystem exists:entry]) {
					NSLog(@"[Themes] Skipping %@ as it is missing a bundle.", folder);
					continue;
				}

				__block NSData *bundle = nil;

				@try {
					id json = [Utilities parseJSON:[FileSystem readFile:entry]];

					if([json isKindOfClass:[NSDictionary class]]) {
						bundle = [json mutableCopy];
					} else {
						NSLog(@"[Themes] Skipping %@ as its bundle is invalid JSON.", folder);
						continue;
					}
				} @catch (NSException *e) {
					NSLog(@"[Themes] Skipping %@ as its bundle failed to be parsed. (%@)", folder, e.reason);
					continue;
				}

				manifest[@"folder"] = folder;
				manifest[@"path"] = dir;

				[themes addObject:@{
					@"manifest": manifest,
					@"bundle": bundle
				}];
			} @catch (NSException *e) {
				NSLog(@"[Themes] Failed to load %@ (%@)", folder, e.reason);
			}
		}

		if ([Settings getBoolean:@"unbound" key:@"loader.enabled" def:YES] && ![Settings getBoolean:@"unbound" key:@"recovery" def:NO]) {
			@try {
				[Themes apply];
			} @catch (NSException *e) {
				NSLog(@"[Themes] Failed to apply theme. (%@)", e.reason);
			}
		}

		NSDictionary<NSString*, NSDictionary*> *theme = [Themes getApplied];
		if (!theme || !theme[@"bundle"] || !theme[@"bundle"][@"fonts"]) {
			return;
		}

		NSDictionary<NSString*, NSString*> *overrides = theme[@"bundle"][@"fonts"];

		for	(NSString *key in overrides) {
			@try {
				NSString *font = [overrides objectForKey:key];
				if (!font) continue;

				NSURL *url = [NSURL URLWithString:font];

				NSLog(@"[Themes] Downloading font \"%@\"...", [url lastPathComponent]);
				NSString *name = [Themes downloadFont:url];
				NSLog(@"[Themes] Downloaded font \"%@\".", name);

				NSLog(@"[Themes] Loading font \"%@\"...", name);
				[Themes loadFont:name orig:key];
				NSLog(@"[Themes] Loaded font \"%@\".", name);
			} @catch(NSException *e) {
				NSLog(@"[Themes] Failed to apply font override for \"%@\". (%@)", key, e.reason);
			}
		}
	};

	+ (void) apply {
		NSDictionary<NSString*, NSDictionary*> *theme = [Themes getApplied];
		if (!theme || !theme[@"bundle"]) return;

		NSDictionary<NSString*, NSString*> *raw = theme[@"bundle"][@"raw"];
		if (raw) {
			Class Color = object_getClass(NSClassFromString(@"UIColor"));
			[Themes swizzle:Color payload:raw];
		}
	}

	+ (void) swizzle:(Class)instance payload:(NSDictionary*)payload {
		NSLog(@"[Themes] Attempting swizzle...");

		@try {
			for (NSString *raw in payload) {
				SEL selector = NSSelectorFromString(raw);
				id (*getOriginalColor)(Class, SEL);

				MSHookMessageEx(instance, selector, (IMP)imp_implementationWithBlock(^UIColor *(id self) {
					@try {
						id color = payload[raw];

                        UIColor *parsed = [Themes parseColor:color];
                        if (parsed) return parsed;
					} @catch (NSException *e) {
						NSLog(@"[Themes] Failed to use modified color %@. (%@)", raw, e.reason);
					}

					return getOriginalColor(instance, selector);
				}), (IMP *)&getOriginalColor);
			}
		} @catch(NSException *e) {
			NSLog(@"[Themes] Failed to swizzle. (%@)", e.reason);
		}

		NSLog(@"[Themes] Swizzle completed.");
	}

	+ (UIColor*) parseColor:(NSString*)color {
		if ([color hasPrefix:@"#"]) {
			if (color.length == 7) {
				color = [color stringByAppendingString:@"FF"];
			}

			NSScanner *scanner = [NSScanner scannerWithString:color];
			unsigned res = 0;

			[scanner setScanLocation:1];
			[scanner scanHexInt:&res];

			CGFloat r = ((res & 0xFF000000) >> 24) / 255.0;
			CGFloat g = ((res & 0x00FF0000) >> 16) / 255.0;
			CGFloat b = ((res & 0x0000FF00) >> 8) / 255.0;
			CGFloat a = (res & 0x000000FF) / 255.0;

			return [UIColor colorWithRed:r green:g blue:b alpha:a];
		}

		if ([color hasPrefix:@"rgba"]) {
			NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\((.*)\\)"
				options:NSRegularExpressionCaseInsensitive
				error:nil
			];

			NSArray *matches = [regex matchesInString:color options:0 range:NSMakeRange(0, [color length])];
			NSString *value = [[NSString alloc] init];

			for (NSTextCheckingResult *match in matches) {
				NSRange range = [match rangeAtIndex:1];
				value = [color substringWithRange:range];
			}

			NSCharacterSet *whitespaces = [NSCharacterSet whitespaceCharacterSet];
			NSArray *values = [value componentsSeparatedByString:@","];
			NSMutableArray *res = [[NSMutableArray alloc] init];

			for (NSString* value in values) {
				NSString *trimmed = [value stringByTrimmingCharactersInSet:whitespaces];
				NSNumber *payload = [NSNumber numberWithFloat:[trimmed floatValue]];

				[res addObject:payload];
			}

			CGFloat r = [[res objectAtIndex:0] floatValue] / 255.0f;
			CGFloat g = [[res objectAtIndex:1] floatValue] / 255.0f;
			CGFloat b = [[res objectAtIndex:2] floatValue] / 255.0f;
			CGFloat a = [[res objectAtIndex:3] floatValue];

			return [UIColor colorWithRed:r green:g blue:b alpha:a];
		}

		return nil;
	}

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
			[fonts setValue:font forKey:orig];
			CGFontRelease(ref);
		} @catch (NSException* e) {
			NSLog(@"[Themes] Failed to load font \"%@\". (%@)", name, e.reason);
		}
	}

	// Properties
	+ (NSMutableDictionary<NSString*, NSString*>*) fonts {
		return fonts;
	}
@end

%hook UIFont
	+ (UIFont *)fontWithName:(NSString *)name size:(CGFloat)size {
		NSMutableDictionary<NSString*, NSString*> *fonts = [Themes fonts];

		if (fonts && [fonts objectForKey:name] != nil) {
			return %orig([fonts objectForKey:name], size);
		}

		return %orig(name, size);
	}
%end