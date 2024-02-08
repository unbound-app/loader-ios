#import "../Headers/FileSystem.h"

@implementation FileSystem
	static NSFileManager *manager = nil;
	static NSString *documents = nil;

	+ (BOOL) exists:(NSString*)path {
		return [manager fileExistsAtPath:path];
	}

	+ (BOOL) isDirectory:(NSString*)path {
		BOOL isDirectory = NO;

		[manager fileExistsAtPath:path isDirectory:&isDirectory];

		return isDirectory;
	}

	+ (void) writeFile:(NSString*)path contents:(NSData*)contents {
		[manager createFileAtPath:path contents:contents attributes:nil];
	}

	+ (id) delete:(NSString*)path {
		if (![manager fileExistsAtPath:path]) {
			NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{NSFilePathErrorKey: path}];

			return error;
		}

		NSError *error;
		[manager removeItemAtPath:path error:&error];

		return error ? error : path;
	}

	+ (NSData*) readFile:(NSString*)path {
		if (![manager fileExistsAtPath:path]) {
			@throw [[NSException alloc] initWithName:@"FileNotFound"
				reason:[NSString stringWithFormat:@"File at path %@ was not found.", path]
				userInfo:nil
			];
		}

		NSError *error = nil;
		NSData* data = [NSData dataWithContentsOfFile:path options:0 error:&error];

		if (error) {
			@throw [[NSException alloc] initWithName:error.domain
				reason:error.localizedDescription
				userInfo:nil
			];
		}

		return data;
	}

	+ (BOOL) createDirectory:(NSString*)path {
		if ([manager fileExistsAtPath:path]) {
			return true;
		}

		NSError *err;
		[manager createDirectoryAtPath:path
			withIntermediateDirectories:false
			attributes:nil
			error:&err
		];

		return err ? false : true;
	}

	+ (NSArray*) readDirectory:(NSString*)path {
		NSError *err;
		NSArray *files = [manager contentsOfDirectoryAtPath:path error:&err];

		return err ? @[] : files;
	}

	+ (BOOL) download:(NSURL*)url path:(NSString*)path {
		dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

		NSLog(@"Downloading file from %@ to %@", url, path);
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
		__block NSException *exception;

		request.timeoutInterval = 1.0;
		request.cachePolicy = NSURLRequestReloadIgnoringCacheData;

		dispatch_async(dispatch_get_main_queue(), ^{
			@try {
				NSURLSession *session = [NSURLSession sharedSession];
				NSURLSessionTask *task = [session dataTaskWithRequest:request
					completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error) {
						NSHTTPURLResponse *http = (NSHTTPURLResponse *) response;

						if (error != nil || [http statusCode] != 200) {
							exception = [[NSException alloc] initWithName:@"DownloadFailed" reason:error.localizedDescription userInfo:nil];
						} else {
							[data writeToFile:path atomically:YES];
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

		// Freeze the main thread until the file is downloaded
		dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

		if (exception) {
			@throw exception;
		}

		return true;
	}

	+ (void) init {
		if (!manager) {
			manager = [NSFileManager defaultManager];
		}

		if (!documents) {
			documents = [NSString pathWithComponents:@[NSHomeDirectory(), @"Documents", @"Unbound"]];
		}

		if (![FileSystem exists:documents]) {
			[FileSystem createDirectory:documents];
		}
	}

	// Properties
	+ (NSString*) documents {
		return documents;
	}
@end