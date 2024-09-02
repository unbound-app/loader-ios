#import "../Headers/Themes.h"
#import <objc/runtime.h>
#import <substrate.h>

@implementation Themes
	static NSMutableDictionary<NSString *, NSValue *> *originalRawImplementations;
	static NSMutableArray *themes = nil;
	static NSString *currentThemeId = nil;

	+ (NSString*) makeJSON {
		NSError *error;
		NSData *data = [NSJSONSerialization dataWithJSONObject:themes options:0 error:&error];

		if (error != nil) {
			return @"[]";
		} else {
			return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		}
	};

	+ (NSDictionary*) getThemeById:(NSString*)manifestId {
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"manifest.id == %@", manifestId];
		NSArray *array = [themes filteredArrayUsingPredicate:predicate];

		if ([array count] != 0) {
			return array[0];
		}

		return nil;
	}

	+ (BOOL) isValidCustomTheme:(NSString*)manifestId {
		NSDictionary *theme = [Themes getThemeById:manifestId];

		if (theme != nil) {
			return YES;
		}

		return NO;
	}

	+ (void) init {
		if (!themes) {
			themes = [[NSMutableArray alloc] init];
		}

		if (!originalRawImplementations) {
			originalRawImplementations = [[NSMutableDictionary alloc] init];
		}

		NSString *path = [NSString pathWithComponents:@[FileSystem.documents, @"Themes"]];
		[FileSystem createDirectory:path];

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
				if (![FileSystem exists:data]) {
					NSLog(@"[Themes] Skipping %@ as it is missing a manifest.", folder);
					continue;
				}

				__block NSMutableDictionary *manifest = nil;

				@try {
					id json = [Utilities parseJSON:[FileSystem readFile:data]];

					if ([json isKindOfClass:[NSDictionary class]]) {
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
				if (![FileSystem exists:entry]) {
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

		if (![Settings getBoolean:@"unbound" key:@"recovery" def:NO]) {
			[Themes swizzleSemanticColors];
		}
	};

	+ (void) swizzleRawColors:(NSDictionary*)payload {
		// Get the class reference for UIColor
		Class instance = object_getClass(NSClassFromString(@"UIColor"));

		NSLog(@"[Themes] Attempting swizzle raw colors...");

		@try {
			for (NSString *raw in payload) {
				SEL selector = NSSelectorFromString(raw);

				// Define a block to replace the original method implementation
				__block id (*original)(Class, SEL);
				IMP replacement = imp_implementationWithBlock(^UIColor *(id self) {
					@try {
						id color = payload[raw];
						UIColor *parsed = [Themes parseColor:color];
						if (parsed) return parsed;
					} @catch (NSException *e) {
						NSLog(@"[Themes] Failed to use modified raw color %@. (%@)", raw, e.reason);
					}

					// Call the original implementation if parsing fails
					return original(instance, selector);
				});

				// Hook the original method with the replacement block
				MSHookMessageEx(instance, selector, replacement, (IMP *)&original);

				// Store the original implementation for restoration when the theme changes
				originalRawImplementations[raw] = [NSValue valueWithPointer:(void *)original];
			}

			NSLog(@"[Themes] Raw color swizzle completed.");
		} @catch (NSException *e) {
			NSLog(@"[Themes] Failed to swizzle raw colors. (%@)", e.reason);
		}
	}

	+ (void) restoreOriginalRawColors {
		Class instance = object_getClass(NSClassFromString(@"UIColor"));

		// Iterate over the stored original implementations and restore them
		for (NSString *selectorName in originalRawImplementations) {
			SEL selector = NSSelectorFromString(selectorName);
			IMP originalIMP = (IMP)[originalRawImplementations[selectorName] pointerValue];

			// Reapply the original implementation
			if (originalIMP) {
				MSHookMessageEx(instance, selector, originalIMP, NULL);
			} else {
				NSLog(@"[Themes] Failed to restore implementation for %@: Original IMP is NULL", selectorName);
			}
		}

		// Clear the dictionary after unsetting swizzles
		[originalRawImplementations removeAllObjects];
	}

	+ (void) swizzleSemanticColors  {
		NSLog(@"[Themes] Attempting swizzle semantic colors...");

		@try {
			// Get the class reference for DCDThemeColor
			Class instance = object_getClass(NSClassFromString(@"DCDThemeColor"));

			// All DCDThemeColor methods return UIColor and are semantic colors.
			// We dynamically copy them and patch them to avoid hardcoding each color.
			unsigned methodCount = 0;
			Method *methods = class_copyMethodList(instance, &methodCount);

			for (unsigned int i = 0; i < methodCount; i++) {
				Method method = methods[i];
				SEL selector = method_getName(method);
				NSString *name = NSStringFromSelector(selector);

				// Define a block to replace the original method implementation
				__block id (*original)(Class, SEL);
				IMP replacement = imp_implementationWithBlock(^UIColor *(id self) {
					if (currentThemeId != nil) {
						@try {
							NSDictionary *theme = [Themes getThemeById:currentThemeId];
							if (!theme) return original(instance, selector);

							NSDictionary *values = theme[@"bundle"][@"semantic"];
							if (!values) return original(instance, selector);

							NSDictionary *color = values[name];
							if (!color || !color[@"type"] || !color[@"value"]) {
								return original(instance, selector);
							}

							NSString *colorType = color[@"type"];
							NSString *colorValue = color[@"value"];
							NSNumber *colorOpacity = color[@"opacity"];

							// Theme Developers are allowed to specify a custom color. (rgb/rgba/hex)
							if ([colorType isEqualToString:@"color"]) {
								UIColor *parsed = [Themes parseColor:colorValue];

								if (parsed) {
									if (colorOpacity) {
										return [parsed colorWithAlphaComponent:[colorOpacity doubleValue]];
									}

									return parsed;
								}
							}

							// Theme Developers can also use Discord's raw colors.
							if ([colorType isEqualToString:@"raw"]) {
								SEL colorSelector = NSSelectorFromString(colorValue);
								Class instance = object_getClass(NSClassFromString(@"UIColor"));

								if ([instance respondsToSelector:colorSelector]) {
									UIColor* (*getColor)(id, SEL);
									getColor = (UIColor* (*)(id, SEL))[instance methodForSelector:colorSelector];

									return getColor(instance, colorSelector);
								}

								return original(instance, selector);
							}

							return original(instance, selector);
						} @catch (NSException *e) {
							NSLog(@"[Themes] Failed to use modified color %@. (%@)", name, e.reason);
						}
					}

					// Call the original implementation if parsing fails or the user does not have a theme applied.
					return original(instance, selector);
				});

				// Hook the original method with the replacement block
				MSHookMessageEx(instance, selector, replacement, (IMP *)&original);
			}

			free(methods);
			NSLog(@"[Themes] Semantic color swizzle completed.");
		} @catch(NSException *e) {
			NSLog(@"[Themes] Failed to swizzle semantic colors. (%@)", e.reason);
		}
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

		if ([color hasPrefix:@"rgb"]) {
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

			return [UIColor colorWithRed:r green:g blue:b alpha:1.0f];
		}

		return nil;
	}
@end

%hook DCDTheme
	- (void) updateTheme:(id)theme {
		if ([currentThemeId isEqualToString:theme]) {
			return %orig;
		}

		NSLog(@"[Themes] Theme updated. (%@)", theme);
		currentThemeId = theme;

		[Themes restoreOriginalRawColors];

		NSDictionary *instance = [Themes getThemeById:theme];

		if (instance) {
			NSDictionary *raw = instance[@"bundle"][@"raw"];
			if (raw) [Themes swizzleRawColors:raw];
		}

		%orig;
	}
%end
