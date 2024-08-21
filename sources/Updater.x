#import "../Headers/Updater.h"

@implementation Updater
	static NSString *etag = nil;

	+ (BOOL) hasUpdate {
		NSLog(@"Checking for updates...");

		if ([Settings getBoolean:@"unbound" key:@"loader.update.force" def:NO]) {
			NSLog(@"[Updater] Forcing update due to config.");
			return YES;
		}

		__block BOOL result = false;
		dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
		NSURL *url = [Updater getDownloadURL];
		__block NSException *exception;

		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

		[request setHTTPMethod:@"HEAD"];
		request.timeoutInterval = 1.0;
		request.cachePolicy = NSURLRequestReloadIgnoringCacheData;

		dispatch_async(dispatch_get_main_queue(), ^{
			@try {
				NSURLSession *session = [NSURLSession sharedSession];
				NSURLSessionTask *task = [session dataTaskWithRequest:request
					completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error) {
						NSHTTPURLResponse *http = (NSHTTPURLResponse *) response;


						if (error != nil || [http statusCode] != 200) {
							exception = [[NSException alloc] initWithName:@"UpdateCheckFailed" reason:error.localizedDescription userInfo:nil];
						} else {
							NSString *tag = [Settings getString:@"unbound" key:@"loader.update.etag" def:nil];
							NSDictionary *headers = [http allHeaderFields];
							NSString *header = headers[@"etag"];

							result = ![header isEqualToString:tag];

							if (result) {
								etag = header;
								NSLog(@"Detected new update.")
							} else {
								NSLog(@"No updates found.")
							}
						}

						dispatch_semaphore_signal(semaphore);
					}
				];

				[task resume];
			} @catch (NSException *e) {
				exception = e;
				dispatch_semaphore_signal(semaphore);
			}
		});

		// Freeze the main thread until the request is complete
		dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

		if (exception) {
			NSLog(@"Encountered error while checking for updates. (%@)", exception);
			[Utilities alert:@"Failed to check for updates, bundle may be out of date. Please report this to the developers."];
			result = false;
		}

		return result;
	}

	+ (NSURL*) getDownloadURL {
		NSString *url = [Settings getString:@"unbound" key:@"loader.update.url" def:@"https://raw.githubusercontent.com/unbound-mod/unbound/main/dist/unbound.bundle"];

		return [NSURL URLWithString:url];
	}

	// Properties
	+ (NSString*) etag {
		return etag;
	}
@end