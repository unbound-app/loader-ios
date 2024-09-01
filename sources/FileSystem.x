#import "../Headers/FileSystem.h"

@implementation FileSystem
	static NSMutableDictionary<NSString*, NSMutableDictionary*> *monitors = nil;
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

	+ (void) monitor:(NSString*)filePath onChange:(void(^)())onChange autoRestart:(BOOL)autoRestart {
		// If file is already being monitored, ignore this extra request.
		if ([monitors objectForKey:filePath]) {
			return;
		}

		const char *path = [filePath fileSystemRepresentation];

		int fdescriptor = open(path, O_EVTONLY);

		// Get a reference to the default queue so our file notifications can go out on it
    dispatch_queue_t defaultQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    // Create a dispatch source
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fdescriptor, DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_LINK | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE | DISPATCH_VNODE_WRITE, defaultQueue);

		// Add cancel handler

		NSMutableDictionary *monitor = [[NSMutableDictionary alloc] init];

		monitor[@"cancel"] = ^{
			close(fdescriptor);
			dispatch_source_cancel(source);

			[monitors removeObjectForKey:filePath];
			NSLog(@"monitor for %@ was destroyed", filePath);
		};

		monitor[@"debounce_timer"] = nil;

		[monitors setValue:monitor forKey:filePath];

    // Log one or more messages when there's a file change event
    dispatch_source_set_event_handler(source, ^{
			// unsigned long eventTypes = dispatch_source_get_data(source);

			// NSLog(@"[Watcher] %lu event got fired for %@", eventTypes, filePath);

			if (monitor[@"debounce_timer"] != nil) {
				dispatch_source_cancel(monitor[@"debounce_timer"]);
				monitor[@"debounce_timer"] = nil;
			}

			dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
			double secondsToThrottle = 0.250f;
			monitor[@"debounce_timer"] = [Utilities createDebounceTimer:secondsToThrottle queue:queue block:^{
				NSLog(@"Debounced");
				onChange();
					//Do some task you don't want to happen every character change, like filter a large set of data or query the network, update a scrubber position.
					//[self doSomethingWith:text];
			}];
    });

    dispatch_source_set_cancel_handler(source, ^(void){
			NSLog(@"[Watcher] event listener got cancelled for %@", filePath);
        close(fdescriptor);

        // If this dispatch source was canceled because of a rename or delete notification, recreate it
        if (autoRestart) {
					NSLog(@"Restarting file watcher.");
					[FileSystem monitor:filePath onChange:onChange autoRestart:autoRestart];
        }
    });

    // Start monitoring the target file
    dispatch_resume(source);
	}

	+ (void) stopMonitoring:(NSString*)path {
		if (!monitors) {
			return;
		}

		NSMutableDictionary *monitor = [monitors valueForKey:path];
		void (^block)(void) = monitor[@"cancel"];
		if (block) {
			block();
		}
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