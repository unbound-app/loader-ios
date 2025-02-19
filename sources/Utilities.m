#import <dlfcn.h>

#import "Utilities.h"

@implementation Utilities
static NSString *bundle = nil;

+ (NSString *)getBundlePath
{
    if (bundle)
    {
        NSLog(@"Using cached bundle URL.");
        return bundle;
    }

    // Attempt to get the bundle from an exact path
    NSString *bundlePath = ROOT_PATH_NS(@"/Library/Application Support/UnboundResources.bundle");

    if ([FileSystem exists:bundlePath])
    {
        bundle = bundlePath;
        return bundlePath;
    }

    // Fall back to a relative path on jailed devices
    NSURL    *url      = [[NSBundle mainBundle] bundleURL];
    NSString *relative = [NSString stringWithFormat:@"%@/UnboundResources.bundle", [url path]];
    if ([FileSystem exists:relative])
    {
        bundle = relative;
        return relative;
    }

    return nil;
}

+ (NSString *)getResource:(NSString *)file
{
    return [Utilities getResource:file ext:@"js"];
}

+ (NSData *)getResource:(NSString *)file data:(BOOL)data
{
    NSString *resource = [Utilities getResource:file];

    return [resource dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSData *)getResource:(NSString *)file data:(BOOL)data ext:(NSString *)ext
{
    NSBundle *bundle = [NSBundle bundleWithPath:[Utilities getBundlePath]];
    if (bundle == nil)
    {
        return nil;
    }

    NSString *path = [bundle pathForResource:file ofType:ext];

    return [NSData dataWithContentsOfFile:path options:0 error:nil];
}

+ (NSString *)getResource:(NSString *)file ext:(NSString *)ext
{
    NSData *data = [Utilities getResource:file data:true ext:ext];

    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (void)alert:(NSString *)message
{
    return [Utilities alert:message title:@"Unbound"];
}

+ (void)alert:(NSString *)message title:(NSString *)title
{
    return [Utilities
          alert:message
          title:title
        buttons:@[
            [UIAlertAction actionWithTitle:@"Okay" style:UIAlertActionStyleDefault handler:nil],

            [UIAlertAction actionWithTitle:@"Join Server"
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action) {
                                       NSURL         *URL = [NSURL
                                           URLWithString:@"https://discord.com/invite/rMdzhWUaGT"];
                                       UIApplication *application =
                                           [UIApplication sharedApplication];

                                       [application openURL:URL options:@{} completionHandler:nil];
                                   }]
        ]];
}

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
{
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];

    for (UIAlertAction *button in buttons)
    {
        [alert addAction:button];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller =
            [[[[UIApplication sharedApplication] delegate] window] rootViewController];
        [controller presentViewController:alert animated:YES completion:nil];
    });
}

+ (id)parseJSON:(NSData *)data
{
    NSError *error = nil;

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (error)
    {
        @throw error;
    }

    return object;
}

+ (dispatch_source_t)createDebounceTimer:(double)delay
                                   queue:(dispatch_queue_t)queue
                                   block:(dispatch_block_t)block
{
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

    if (timer)
    {
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC),
                                  DISPATCH_TIME_FOREVER, (1ull * NSEC_PER_SEC) / 10);
        dispatch_source_set_event_handler(timer, block);
        dispatch_resume(timer);
    }

    return timer;
}

+ (void *)getHermesSymbol:(const char *)symbol error:(NSString **)error
{
    NSString *bundlePath     = [[NSBundle mainBundle] bundlePath];
    NSString *executablePath = [bundlePath stringByAppendingPathComponent:@"Discord"];

    void *handle = dlopen([executablePath UTF8String], RTLD_LAZY);
    if (!handle)
    {
        if (error)
            *error = [NSString stringWithUTF8String:dlerror()];
        return NULL;
    }

    void *sym = dlsym(handle, symbol);
    if (!sym)
    {
        if (error)
            *error = [NSString stringWithUTF8String:dlerror()];
        dlclose(handle);
        return NULL;
    }

    return sym;
}

+ (uint32_t)getHermesBytecodeVersion
{
    NSString *error                  = nil;
    uint32_t (*getBytecodeVersion)() = (uint32_t (*)())
        [self getHermesSymbol:"_ZN8facebook6hermes13HermesRuntime18getBytecodeVersionEv"
                        error:&error];

    if (!getBytecodeVersion)
    {
        NSLog(@"Failed to get bytecode version: %@", error);
        return 0;
    }

    return getBytecodeVersion();
}

+ (BOOL)isHermesBytecode:(NSData *)data
{
    NSString *error                                   = nil;
    BOOL (*isHermesBytecode)(const uint8_t *, size_t) = (BOOL(*)(const uint8_t *, size_t))
        [self getHermesSymbol:"_ZN8facebook6hermes13HermesRuntime16isHermesBytecodeEPKhm"
                        error:&error];

    if (!isHermesBytecode)
    {
        NSLog(@"Failed to check Hermes bytecode: %@", error);
        return NO;
    }

    return isHermesBytecode((const uint8_t *) [data bytes], [data length]);
}

+ (BOOL)isAppStoreApp
{
    return [[NSFileManager defaultManager]
        fileExistsAtPath:[[NSBundle mainBundle] appStoreReceiptURL].path];
}

+ (BOOL)isJailbroken
{
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
}

@end