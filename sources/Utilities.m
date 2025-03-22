#import "Utilities.h"

@implementation Utilities
static NSString *bundle            = nil;
static UIView   *islandOverlayView = nil;

+ (NSString *)getBundlePath
{
    if (bundle)
    {
        [Logger info:LOG_CATEGORY_UTILITIES format:@"Using cached bundle URL."];
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
        [Logger error:LOG_CATEGORY_UTILITIES format:@"Failed to get bytecode version: %@", error];
        return 0;
    }

    return getBytecodeVersion();
}

+ (BOOL)isHermesBytecode:(NSData *)data
{
    NSString *error                                   = nil;
    BOOL (*isHermesBytecode)(const uint8_t *, size_t) = (BOOL (*)(const uint8_t *, size_t))
        [self getHermesSymbol:"_ZN8facebook6hermes13HermesRuntime16isHermesBytecodeEPKhm"
                        error:&error];

    if (!isHermesBytecode)
    {
        [Logger error:LOG_CATEGORY_UTILITIES format:@"Failed to check Hermes bytecode: %@", error];
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

+ (NSString *)getDeviceModelIdentifier
{
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

+ (BOOL)deviceHasDynamicIsland
{
    NSString *identifier           = [self getDeviceModelIdentifier];
    NSArray  *dynamicIslandDevices = @[
        @"iPhone15,2", @"iPhone15,3", @"iPhone15,4", @"iPhone15,5", @"iPhone16,1", @"iPhone16,2",
        @"iPhone17,1", @"iPhone17,2", @"iPhone17,3", @"iPhone17,4"
    ];

    return [dynamicIslandDevices containsObject:identifier];
}

+ (UIImage *)createLogoImage
{
    CGFloat size = 512.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);

    [[UIColor whiteColor] setFill];

    UIBezierPath *rightPath = [UIBezierPath bezierPath];
    [rightPath moveToPoint:CGPointMake(272.52, 177.27)];
    [rightPath addLineToPoint:CGPointMake(277.81, 215.63)];
    [rightPath addLineToPoint:CGPointMake(338.67, 215.74)];
    [rightPath addLineToPoint:CGPointMake(338.67, 215.83)];
    [rightPath addCurveToPoint:CGPointMake(373.01, 240.88)
                 controlPoint1:CGPointMake(345.73, 216.18)
                 controlPoint2:CGPointMake(359.97, 225.73)];
    [rightPath addLineToPoint:CGPointMake(349.25, 240.88)];
    [rightPath addCurveToPoint:CGPointMake(333.37, 260.06)
                 controlPoint1:CGPointMake(345.04, 240.88)
                 controlPoint2:CGPointMake(333.37, 249.47)];
    [rightPath addCurveToPoint:CGPointMake(349.25, 279.24)
                 controlPoint1:CGPointMake(333.37, 270.65)
                 controlPoint2:CGPointMake(345.04, 279.24)];
    [rightPath addLineToPoint:CGPointMake(376.41, 279.24)];
    [rightPath addCurveToPoint:CGPointMake(338.67, 313.64)
                 controlPoint1:CGPointMake(373.86, 288.78)
                 controlPoint2:CGPointMake(357.41, 308.18)];
    [rightPath addLineToPoint:CGPointMake(338.67, 313.75)];
    [rightPath addLineToPoint:CGPointMake(297.66, 313.64)];
    [rightPath addLineToPoint:CGPointMake(302.95, 351.9)];
    [rightPath addLineToPoint:CGPointMake(338.67, 352.01)];
    [rightPath addCurveToPoint:CGPointMake(416.94, 279.23)
                 controlPoint1:CGPointMake(378, 352.01)
                 controlPoint2:CGPointMake(410.64, 320.52)];
    [rightPath addLineToPoint:CGPointMake(473.61, 279.14)];
    [rightPath addLineToPoint:CGPointMake(489.48, 240.77)];
    [rightPath addLineToPoint:CGPointMake(415.05, 240.88)];
    [rightPath addCurveToPoint:CGPointMake(338.67, 177.38)
                 controlPoint1:CGPointMake(405.63, 204.23)
                 controlPoint2:CGPointMake(375, 177.38)];
    [rightPath addLineToPoint:CGPointMake(272.52, 177.27)];
    [rightPath closePath];

    // Draw left part
    UIBezierPath *leftPath = [UIBezierPath bezierPath];
    [leftPath moveToPoint:CGPointMake(164.04, 160.07)];
    [leftPath addCurveToPoint:CGPointMake(87.66, 223.57)
                controlPoint1:CGPointMake(127.71, 160.07)
                controlPoint2:CGPointMake(97.08, 186.92)];
    [leftPath addLineToPoint:CGPointMake(41.01, 223.57)];
    [leftPath addLineToPoint:CGPointMake(25.14, 261.94)];
    [leftPath addLineToPoint:CGPointMake(85.77, 261.94)];
    [leftPath addCurveToPoint:CGPointMake(164.04, 334.7)
                controlPoint1:CGPointMake(92.07, 303.24)
                controlPoint2:CGPointMake(124.7, 334.7)];
    [leftPath addLineToPoint:CGPointMake(243.41, 334.7)];
    [leftPath addLineToPoint:CGPointMake(238.12, 296.34)];
    [leftPath addLineToPoint:CGPointMake(164.04, 296.34)];
    [leftPath addLineToPoint:CGPointMake(164.04, 296.26)];
    [leftPath addCurveToPoint:CGPointMake(126.3, 261.94)
                controlPoint1:CGPointMake(145.3, 296.01)
                controlPoint2:CGPointMake(128.85, 271.48)];
    [leftPath addLineToPoint:CGPointMake(153.46, 261.94)];
    [leftPath addCurveToPoint:CGPointMake(169.33, 242.76)
                controlPoint1:CGPointMake(157.67, 261.94)
                controlPoint2:CGPointMake(169.33, 253.35)];
    [leftPath addCurveToPoint:CGPointMake(153.46, 223.57)
                controlPoint1:CGPointMake(169.33, 232.17)
                controlPoint2:CGPointMake(157.67, 223.57)];
    [leftPath addLineToPoint:CGPointMake(129.7, 223.57)];
    [leftPath addCurveToPoint:CGPointMake(164.04, 198.44)
                controlPoint1:CGPointMake(133.15, 216.35)
                controlPoint2:CGPointMake(147.27, 198.89)];
    [leftPath addLineToPoint:CGPointMake(164.04, 198.44)];
    [leftPath addLineToPoint:CGPointMake(219.6, 198.44)];
    [leftPath addLineToPoint:CGPointMake(214.3, 160.07)];
    [leftPath addLineToPoint:CGPointMake(164.04, 160.07)];
    [leftPath closePath];

    [rightPath fill];
    [leftPath fill];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return result;
}

+ (void)showDynamicIslandOverlay
{
    if (!islandOverlayView)
    {
        [self createDynamicIslandOverlayView];
    }

    if (islandOverlayView && !islandOverlayView.hidden && islandOverlayView.alpha >= 1.0)
    {
        return;
    }

    islandOverlayView.hidden = NO;

    [UIView animateWithDuration:0.2 animations:^{ islandOverlayView.alpha = 1.0; }];

    [Logger debug:LOG_CATEGORY_UTILITIES format:@"Showing Dynamic Island overlay"];
}

+ (void)hideDynamicIslandOverlay
{
    if (!islandOverlayView || islandOverlayView.hidden)
    {
        return;
    }

    islandOverlayView.alpha  = 0.0;
    islandOverlayView.hidden = YES;

    [Logger debug:LOG_CATEGORY_UTILITIES format:@"Hiding Dynamic Island overlay"];
}

+ (void)createDynamicIslandOverlayView
{
    if (islandOverlayView)
    {
        [Logger debug:LOG_CATEGORY_UTILITIES
               format:@"Island overlay view already exists, skipping creation"];
        return;
    }

    CGFloat width  = 126.0;
    CGFloat height = 37.33;

    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat x           = (screenWidth - width) / 2;
    CGFloat y           = 11.0;

    [Logger debug:LOG_CATEGORY_UTILITIES
           format:@"Creating Dynamic Island overlay view at x:%f y:%f width:%f height:%f", x, y,
                  width, height];

    islandOverlayView = [[UIView alloc] initWithFrame:CGRectMake(x, y, width, height)];
    islandOverlayView.backgroundColor = [UIColor blackColor];
    islandOverlayView.alpha           = 0.0;
    islandOverlayView.hidden          = YES;

    islandOverlayView.userInteractionEnabled = NO;

    UIBezierPath *path =
        [UIBezierPath bezierPathWithRoundedRect:islandOverlayView.bounds
                              byRoundingCorners:UIRectCornerAllCorners
                                    cornerRadii:CGSizeMake(height / 2, height / 2)];

    CAShapeLayer *maskLayer      = [CAShapeLayer layer];
    maskLayer.path               = path.CGPath;
    islandOverlayView.layer.mask = maskLayer;

    UIImage *logoImage = [self createLogoImage];
    [Logger debug:LOG_CATEGORY_UTILITIES format:@"Created logo image for Dynamic Island overlay"];

    UIImageView *logoView = [[UIImageView alloc] init];
    logoView.image        = logoImage;
    logoView.contentMode  = UIViewContentModeScaleAspectFit;

    CGFloat logoHeight  = height * 0.99;
    CGFloat aspectRatio = logoImage.size.width / logoImage.size.height;
    CGFloat logoWidth   = logoHeight * aspectRatio;
    logoView.frame =
        CGRectMake((width - logoWidth) / 2, (height - logoHeight) / 2, logoWidth, logoHeight);

    [islandOverlayView addSubview:logoView];

    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes)
    {
        if (scene.activationState == UISceneActivationStateForegroundActive)
        {
            keyWindow = ((UIWindowScene *) scene).windows.firstObject;
            break;
        }
    }

    if (keyWindow)
    {
        [keyWindow addSubview:islandOverlayView];
        [keyWindow bringSubviewToFront:islandOverlayView];
        [Logger info:LOG_CATEGORY_UTILITIES
              format:@"Successfully added Dynamic Island overlay to key window"];
    }
    else
    {
        [Logger error:LOG_CATEGORY_UTILITIES
               format:@"Failed to find key window for Dynamic Island overlay"];
    }
}

+ (void)initializeDynamicIslandOverlay
{
    [Logger info:LOG_CATEGORY_UTILITIES format:@"Checking if device has Dynamic Island..."];

    if (![self deviceHasDynamicIsland])
    {
        [Logger info:LOG_CATEGORY_UTILITIES
              format:@"Device does not have Dynamic Island, skipping overlay"];
        return;
    }

    static BOOL isInitialized = NO;
    if (isInitialized)
    {
        [Logger info:LOG_CATEGORY_UTILITIES format:@"Dynamic Island overlay already initialized"];
        return;
    }
    isInitialized = YES;

    [Logger info:LOG_CATEGORY_UTILITIES format:@"Setting up Dynamic Island overlay notifications"];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        [Logger debug:LOG_CATEGORY_UTILITIES
                               format:@"App did become active, showing overlay"];
                        dispatch_async(dispatch_get_main_queue(),
                                       ^{ [self showDynamicIslandOverlay]; });
                    }];

    [center addObserverForName:UIApplicationWillResignActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        [Logger debug:LOG_CATEGORY_UTILITIES
                               format:@"App will resign active, hiding overlay"];
                        dispatch_async(dispatch_get_main_queue(),
                                       ^{ [self hideDynamicIslandOverlay]; });
                    }];

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [Logger info:LOG_CATEGORY_UTILITIES format:@"Creating Dynamic Island overlay..."];
            [self createDynamicIslandOverlayView];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{ [self showDynamicIslandOverlay]; });
        });
}

@end