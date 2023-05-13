#import "../Headers/Updater.h"

@implementation Updater
	+ (BOOL) hasUpdate {
		NSLog(@"Checking for updates...");

		if ([Settings getBoolean:@"unbound" key:@"loader.update.force" def:NO]) {
			NSLog(@"[Updater] Forcing update due to config.");
			return YES;
		}

		__block BOOL result = false;

		@try {
			dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
			NSURL *url = [Updater getDownloadURL];
			__block NSException *exception;

			NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

			request.timeoutInterval = 2.0;
			request.cachePolicy = NSURLRequestReloadIgnoringCacheData;

			dispatch_async(dispatch_get_main_queue(), ^{
				@try {
					NSURLSession *session = [NSURLSession sharedSession];
					NSURLSessionTask *task = [session dataTaskWithRequest:request
						completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error) {
							NSHTTPURLResponse *http = (NSHTTPURLResponse *) response;


							if (error != nil || [http statusCode] != 200) {
								exception = [[NSException alloc] initWithName:@"UpdateCheckFailed" reason:error.localizedDescription userInfo:nil];
								return;
							}

							NSString *tag = [Settings getString:@"unbound" key:@"loader.update.etag" def:nil];
							NSDictionary *headers = [http allHeaderFields];
							NSString *header = headers[@"etag"];

							result = ![header isEqualToString:tag];

							if (result) {
								[Settings set:@"unbound" key:@"loader.update.etag" value:header];
								NSLog(@"Detected new update.")
							} else {
								NSLog(@"No updates found.")
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
				@throw exception;
			}
		} @catch (NSException *e) {
			return false;
		}

		return result;
	}

	+ (NSURL*) getDownloadURL {
		NSString *url = [Settings getString:@"unbound" key:@"loader.update.url" def:@"https://raw.githubusercontent.com/unbound-mod/unbound/main/dist/bundle.js"];

		return [NSURL URLWithString:url];
	}
@end