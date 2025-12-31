#import "FileSystem.h"

@implementation FileSystem
static NSMutableDictionary<NSString *, NSMutableDictionary *> *monitors  = nil;
static NSFileManager                                          *manager   = nil;
static NSString                                               *documents = nil;

+ (BOOL)exists:(NSString *)path
{
    return [manager fileExistsAtPath:path];
}

+ (BOOL)isDirectory:(NSString *)path
{
    BOOL isDirectory = NO;

    [manager fileExistsAtPath:path isDirectory:&isDirectory];

    return isDirectory;
}

+ (void)writeFile:(NSString *)path contents:(NSData *)contents
{
    [manager createFileAtPath:path contents:contents attributes:nil];
}

+ (id)delete:(NSString *)path
{
    if (![manager fileExistsAtPath:path])
    {
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileNoSuchFileError
                                         userInfo:@{NSFilePathErrorKey : path}];

        return error;
    }

    NSError *error;
    [manager removeItemAtPath:path error:&error];

    return error ? error : path;
}

+ (NSData *)readFile:(NSString *)path
{
    if (![manager fileExistsAtPath:path])
    {
        @throw [[NSException alloc]
            initWithName:@"FileNotFound"
                  reason:[NSString stringWithFormat:@"File at path %@ was not found.", path]
                userInfo:nil];
    }

    NSError *error = nil;
    NSData  *data  = [NSData dataWithContentsOfFile:path options:0 error:&error];

    if (error)
    {
        @throw [[NSException alloc] initWithName:error.domain
                                          reason:error.localizedDescription
                                        userInfo:nil];
    }

    return data;
}

+ (BOOL)createDirectory:(NSString *)path
{
    if ([manager fileExistsAtPath:path])
    {
        return true;
    }

    NSError *err;
    [manager createDirectoryAtPath:path
        withIntermediateDirectories:false
                         attributes:nil
                              error:&err];

    return err ? false : true;
}

+ (NSArray *)readDirectory:(NSString *)path
{
    NSError *err;
    NSArray *files = [manager contentsOfDirectoryAtPath:path error:&err];

    return err ? @[] : files;
}

+ (void)monitor:(NSString *)filePath onChange:(void (^)())onChange autoRestart:(BOOL)autoRestart
{
    if ([monitors objectForKey:filePath])
    {
        return;
    }

    const char *path = [filePath fileSystemRepresentation];

    int fdescriptor = open(path, O_EVTONLY);

    dispatch_queue_t defaultQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t source = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_VNODE, fdescriptor,
        DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_EXTEND |
            DISPATCH_VNODE_LINK | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE |
            DISPATCH_VNODE_WRITE,
        defaultQueue);


    NSMutableDictionary *monitor = [[NSMutableDictionary alloc] init];

    monitor[@"cancel"] = ^{
        close(fdescriptor);
        dispatch_source_cancel(source);

        [monitors removeObjectForKey:filePath];
        [Logger debug:LOG_CATEGORY_FILESYSTEM format:@"monitor for %@ was destroyed", filePath];
    };

    monitor[@"debounce_timer"] = nil;

    [monitors setValue:monitor forKey:filePath];

    dispatch_source_set_event_handler(source, ^{
        if (monitor[@"debounce_timer"] != nil)
        {
            dispatch_source_cancel(monitor[@"debounce_timer"]);
            monitor[@"debounce_timer"] = nil;
        }

        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        double           secondsToThrottle = 0.250f;
        monitor[@"debounce_timer"]         = [Utilities createDebounceTimer:secondsToThrottle
                                                              queue:queue
                                                              block:^{ onChange(); }];
    });

    dispatch_source_set_cancel_handler(source, ^(void) {
        [Logger debug:LOG_CATEGORY_FILESYSTEM
               format:@"event listener got cancelled for %@", filePath];
        close(fdescriptor);

        if (autoRestart)
        {
            [Logger debug:LOG_CATEGORY_FILESYSTEM format:@"Restarting file watcher."];
            [FileSystem monitor:filePath onChange:onChange autoRestart:autoRestart];
        }
    });

    dispatch_resume(source);
}

+ (void)stopMonitoring:(NSString *)path
{
    if (!monitors)
    {
        return;
    }

    NSMutableDictionary *monitor = [monitors valueForKey:path];
    void (^block)(void)          = monitor[@"cancel"];
    if (block)
    {
        block();
    }
}

+ (NSHTTPURLResponse *)download:(NSURL *)url path:(NSString *)path
{
    return [FileSystem download:url path:path withHeaders:@{}];
}

+ (NSHTTPURLResponse *)download:(NSURL *)url
                           path:(NSString *)path
                    withHeaders:(NSDictionary *)headers
{
    static NSURLSession *bundleUrlSession = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest  = 10.0;
        bundleUrlSession = [NSURLSession sessionWithConfiguration:config];
    });

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.cachePolicy          = NSURLRequestReloadIgnoringCacheData;

    __block NSHTTPURLResponse *response;
    __block NSException       *exception;

    for (NSString *header in headers)
    {
        NSString *value = headers[header];
        [request setValue:value forHTTPHeaderField:header];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        @try
        {
            NSURLSessionTask *task = [bundleUrlSession
                dataTaskWithRequest:request
                  completionHandler:^(NSData *data, NSURLResponse *res, NSError *error) {
                      response = (NSHTTPURLResponse *) res;

                      if (error != nil ||
                          ([response statusCode] != 200 && [response statusCode] != 304))
                      {
                          exception = [[NSException alloc] initWithName:@"DownloadFailed"
                                                                 reason:error.localizedDescription
                                                               userInfo:nil];
                      }
                      else if ([response statusCode] != 304)
                      {
                          [Logger info:LOG_CATEGORY_FILESYSTEM
                                format:@"Saving file from %@ to %@", url, path];
                          [data writeToFile:path atomically:YES];
                      }

                      dispatch_semaphore_signal(semaphore);
                  }];

            [task resume];
        }
        @catch (NSException *e)
        {
            exception = e;

            dispatch_semaphore_signal(semaphore);
        }
    });

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    if (exception)
    {
        @throw exception;
    }

    return response;
}

+ (void)init
{
    if (!manager)
    {
        manager = [NSFileManager defaultManager];
    }

    if (!documents)
    {
        documents = [NSString pathWithComponents:@[ NSHomeDirectory(), @"Documents", @"Unbound" ]];
    }

    if (![FileSystem exists:documents])
    {
        [FileSystem createDirectory:documents];
    }
}

+ (NSString *)documents
{
    return documents;
}
@end
