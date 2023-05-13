#import "../Headers/Settings.h"

@implementation Settings
	static NSDictionary *data = nil;
	static NSString *path = nil;

	+ (void) init {
		if (!path) {
			path = [NSString pathWithComponents:@[FileSystem.documents, @"settings.json"]];
		}

		if (![FileSystem exists:path]) {
			[Settings reset];
		}

		if (!data) {
			NSData *settings = [FileSystem readFile:path];

			NSError *error;
			data = [NSJSONSerialization JSONObjectWithData:settings options:kNilOptions error:&error];
		}
	}

	+ (NSString*) getString:(NSString*)store key:(NSString*)key def:(NSString*)def {
		id payload = data[store];
		if (!payload) return def;

		id value = [payload valueForKeyPath:key];

		return value != nil ? value : def;
	}

	+ (BOOL) getBoolean:(NSString*)store key:(NSString*)key def:(BOOL)def {
		id payload = data[store];
		if (!payload) return def;

		id value = [payload valueForKeyPath:key];

		if (value != nil && [value respondsToSelector:@selector(boolValue)]) {
			return [value boolValue];
		}

		return def;
	}

	+ (void) reset {
		NSString *payload = @"{}";

		[FileSystem writeFile:path contents:[payload dataUsingEncoding:NSUTF8StringEncoding]];
	}

	+ (NSString*) getSettings {
		NSError *error;
		NSData *json = [NSJSONSerialization dataWithJSONObject:data
			options:NSJSONWritingPrettyPrinted
			error:&error
		];

		return [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
	}
@end