#import <CommonCrypto/CommonCrypto.h>

#import "../Headers/FileSystem.h"
#import "../Headers/Utilities.h"

@implementation Utilities
	static NSString *bundle = nil;

	+ (NSString*) getBundlePath {
		if (bundle) {
			NSLog(@"Using cached bundleURL");
			return bundle;
		}

		// Attempt to get the bundle from an exact path
		NSString *exact = @"/Library/Application Support/Enmity/EnmityResources.bundle";
		if ([FileSystem exists:exact]) {
			bundle = exact;
			return exact;
		}

		// Fall back to a relative path on non-jailbroken devices
		NSURL *url = [[NSBundle mainBundle] bundleURL];
		NSString *relative = [NSString stringWithFormat:@"%@/EnmityResources.bundle", [url path]];
		if ([FileSystem exists:relative]) {
			bundle = relative;
			return relative;
		}

		return nil;
	}

	+ (NSString*) getResource:(NSString*)file {
		return [Utilities getResource:file ext:@"js"];
	}

	+ (NSData*) getResource:(NSString*)file data:(BOOL)data {
		NSString *resource = [Utilities getResource:file];

		return [resource dataUsingEncoding:NSUTF8StringEncoding];
	}

	+ (NSData*) getResource:(NSString*)file data:(BOOL)data ext:(NSString*)ext {
		NSString *resource = [Utilities getResource:file ext:ext];

		return [resource dataUsingEncoding:NSUTF8StringEncoding];
	}

	+ (NSString*) getResource:(NSString*)file ext:(NSString*)ext {
		NSBundle *bundle = [NSBundle bundleWithPath:[Utilities getBundlePath]];
		if (bundle == nil) {
			return nil;
		}

		NSString *path = [bundle pathForResource:file ofType:@"js"];
		NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];

		return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	}

	+ (void) alert:(NSString*)message {
		return [Utilities alert:message title:@"Enmity"];
	}

	+ (void) alert:(NSString*)message title:(NSString*)title {
		return [Utilities alert:message title:title buttons:@[
			[UIAlertAction
				actionWithTitle:@"Okay"
				style:UIAlertActionStyleDefault
				handler:nil
			],

			[UIAlertAction
				actionWithTitle:@"Join Server"
				style:UIAlertActionStyleDefault
				handler: ^(UIAlertAction *action) {
					NSURL *URL = [NSURL URLWithString:@"https://discord.com/invite/rMdzhWUaGT"];
					UIApplication *application = [UIApplication sharedApplication];

					[application openURL:URL options:@{} completionHandler:nil];
				}
			]
		]];
	}

	+ (void) alert:(NSString*)message title:(NSString*)title buttons:(NSArray<UIAlertAction*>*)buttons {
		UIAlertController *alert = [UIAlertController
			alertControllerWithTitle:title
			message:message
			preferredStyle:UIAlertControllerStyleAlert
		];

		for (UIAlertAction *button in buttons) {
			[alert addAction:button];
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			UIViewController *controller = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
			[controller presentViewController:alert animated:YES completion:nil];
		});
	}

	+ (id) parseJSON:(NSData*)data {
		NSError *error = nil;

		id object = [NSJSONSerialization
			JSONObjectWithData:data
			options:0
			error:&error
		];

		if (error) {
			@throw error;
		}

		return object;
	}
@end