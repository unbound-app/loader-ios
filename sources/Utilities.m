#import "Utilities.h"

NSString *const TROLL_STORE_PATH      = @"../_TrollStore";
NSString *const TROLL_STORE_LITE_PATH = @"../_TrollStoreLite";

const CGFloat DYNAMIC_ISLAND_TOP_INSET = 59.0;

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

    NSString *bundlePath = ROOT_PATH_NS(@"/Library/Application Support/UnboundResources.bundle");

    if ([FileSystem exists:bundlePath])
    {
        bundle = bundlePath;
        return bundlePath;
    }

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
    [self presentAlert:message
                 title:@"Unbound"
               buttons:@[
                   [UIAlertAction actionWithTitle:@"Okay"
                                            style:UIAlertActionStyleDefault
                                          handler:nil],
                   [self createDiscordInviteButton]
               ]
               timeout:0
               warning:NO
                   tts:NO];
}

+ (void)alert:(NSString *)message title:(NSString *)title
{
    [self presentAlert:message
                 title:title
               buttons:@[
                   [UIAlertAction actionWithTitle:@"Okay"
                                            style:UIAlertActionStyleDefault
                                          handler:nil],
                   [self createDiscordInviteButton]
               ]
               timeout:0
               warning:NO
                   tts:NO];
}

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
{
    [self presentAlert:message title:title buttons:buttons timeout:0 warning:NO tts:NO];
}

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
      timeout:(NSInteger)timeout
{
    [self presentAlert:message title:title buttons:buttons timeout:timeout warning:NO tts:NO];
}

+ (void)alert:(NSString *)message title:(NSString *)title timeout:(NSInteger)timeout
{
    [self presentAlert:message
                 title:title
               buttons:@[
                   [UIAlertAction actionWithTitle:@"Okay"
                                            style:UIAlertActionStyleDefault
                                          handler:nil],
                   [self createDiscordInviteButton]
               ]
               timeout:timeout
               warning:NO
                   tts:NO];
}

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
      timeout:(NSInteger)timeout
      warning:(BOOL)warning
{
    [self presentAlert:message title:title buttons:buttons timeout:timeout warning:warning tts:NO];
}

+ (void)alert:(NSString *)message
        title:(NSString *)title
      timeout:(NSInteger)timeout
      warning:(BOOL)warning
{
    [self presentAlert:message
                 title:title
               buttons:@[
                   [UIAlertAction actionWithTitle:@"Okay"
                                            style:UIAlertActionStyleDefault
                                          handler:nil],
                   [self createDiscordInviteButton]
               ]
               timeout:timeout
               warning:warning
                   tts:NO];
}

+ (void)alert:(NSString *)message
        title:(NSString *)title
      timeout:(NSInteger)timeout
      warning:(BOOL)warning
          tts:(BOOL)tts
{
    [self presentAlert:message
                 title:title
               buttons:@[
                   [UIAlertAction actionWithTitle:@"Okay"
                                            style:UIAlertActionStyleDefault
                                          handler:nil],
                   [self createDiscordInviteButton]
               ]
               timeout:timeout
               warning:warning
                   tts:tts];
}

+ (void)alert:(NSString *)message title:(NSString *)title warning:(BOOL)warning
{
    [self presentAlert:message title:title buttons:nil timeout:0 warning:warning tts:NO];
}

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
      warning:(BOOL)warning
{
    [self presentAlert:message title:title buttons:buttons timeout:0 warning:warning tts:NO];
}

+ (void)alert:(NSString *)message title:(NSString *)title tts:(BOOL)tts
{
    [self presentAlert:message title:title buttons:nil timeout:0 warning:NO tts:tts];
}

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
          tts:(BOOL)tts
{
    [self presentAlert:message title:title buttons:buttons timeout:0 warning:NO tts:tts];
}

+ (void)alert:(NSString *)message title:(NSString *)title warning:(BOOL)warning tts:(BOOL)tts
{
    [self presentAlert:message title:title buttons:nil timeout:0 warning:warning tts:tts];
}

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
      warning:(BOOL)warning
          tts:(BOOL)tts
{
    [self presentAlert:message title:title buttons:buttons timeout:0 warning:warning tts:tts];
}

+ (void)alertWarning:(NSString *)message title:(NSString *)title timeout:(NSInteger)timeout
{
    [self presentAlert:message title:title buttons:nil timeout:timeout warning:YES tts:YES];
}

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
      timeout:(NSInteger)timeout
      warning:(BOOL)warning
          tts:(BOOL)tts
{
    [self presentAlert:message title:title buttons:buttons timeout:timeout warning:warning tts:tts];
}

+ (void)presentAlert:(NSString *)message
               title:(NSString *)title
             buttons:(NSArray<UIAlertAction *> *)buttons
             timeout:(NSInteger)timeout
             warning:(BOOL)warning
                 tts:(BOOL)tts
{
    NSArray<UIAlertAction *> *alertButtons = buttons;
    if (!alertButtons || alertButtons.count == 0)
    {
        alertButtons = @[
            [UIAlertAction actionWithTitle:@"Okay" style:UIAlertActionStyleDefault handler:nil],
            [self createDiscordInviteButton]
        ];
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];

    for (UIAlertAction *button in alertButtons)
    {
        [alert addAction:button];
    }

    if (timeout > 0)
    {
        for (UIAlertAction *action in alert.actions)
        {
            action.enabled = NO;
        }

        NSString *originalTitle = title;
        alert.title = [NSString stringWithFormat:@"%@ (%ld)", originalTitle, (long) timeout];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller = nil;

        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes)
        {
            if (scene.activationState == UISceneActivationStateForegroundActive)
            {
                UIWindowScene *windowScene = (UIWindowScene *) scene;
                UIWindow      *keyWindow   = windowScene.windows.firstObject;
                for (UIWindow *window in windowScene.windows)
                {
                    if (window.isKeyWindow)
                    {
                        keyWindow = window;
                        break;
                    }
                }
                controller = keyWindow.rootViewController;
                break;
            }
        }

        if (!controller)
        {
            controller = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
        }

        while (controller.presentedViewController)
        {
            controller = controller.presentedViewController;
        }

        if (!controller)
        {
            [Logger error:LOG_CATEGORY_UTILITIES
                   format:@"Failed to find view controller to present alert"];
            return;
        }

        [controller
            presentViewController:alert
                         animated:YES
                       completion:^{
                           if (warning)
                           {
                               dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC),
                                              dispatch_get_main_queue(),
                                              ^{ [self applyRedPulsatingBorderToAlert:alert]; });
                           }

                           if (tts)
                           {
                               dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC),
                                              dispatch_get_main_queue(),
                                              ^{ [self speakAlertContent:title message:message]; });
                           }

                           if (timeout > 0)
                           {
                               __block NSInteger countdown = timeout;
                               dispatch_source_t timer     = dispatch_source_create(
                                   DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());

                               dispatch_source_set_timer(
                                   timer, dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC),
                                   1.0 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);

                               dispatch_source_set_event_handler(timer, ^{
                                   countdown--;

                                   if (countdown > 0)
                                   {
                                       alert.title = [NSString
                                           stringWithFormat:@"%@ (%ld)", title, (long) countdown];
                                   }
                                   else
                                   {
                                       alert.title = title;
                                       for (UIAlertAction *action in alert.actions)
                                       {
                                           action.enabled = YES;
                                       }
                                       dispatch_source_cancel(timer);
                                   }
                               });

                               dispatch_resume(timer);
                           }
                       }];
    });
}

+ (void)speakAlertContent:(NSString *)title message:(NSString *)message
{
    if (UIAccessibilityIsVoiceOverRunning())
    {
        NSString *announcement = [NSString stringWithFormat:@"%@. %@", title, message];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, announcement);
        return;
    }

    static AVSpeechSynthesizer *synthesizer = nil;
    if (!synthesizer)
    {
        synthesizer = [[AVSpeechSynthesizer alloc] init];
    }

    if ([synthesizer isSpeaking])
    {
        [synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }

    NSString *cleanTitle = [title stringByReplacingOccurrencesOfString:@"⚠️" withString:@"Warning:"];

    NSString *speechText = [NSString stringWithFormat:@"%@. %@", cleanTitle, message];

    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:speechText];
    utterance.rate               = AVSpeechUtteranceDefaultSpeechRate;
    utterance.volume             = 1.0;

    AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-GB"];
    if (voice)
    {
        utterance.voice = voice;
    }

    [Logger info:LOG_CATEGORY_UTILITIES format:@"Speaking alert content via TTS"];
    [synthesizer speakUtterance:utterance];
}

+ (void)applyRedPulsatingBorderToAlert:(UIAlertController *)alert
{
    UIView *alertView = alert.view;

    [alertView.layer removeAllAnimations];

    alertView.layer.shadowColor   = [UIColor systemRedColor].CGColor;
    alertView.layer.shadowRadius  = 15.0;
    alertView.layer.shadowOpacity = 0.8;
    alertView.layer.shadowOffset  = CGSizeZero;
    alertView.layer.cornerRadius  = 14.0;

    alertView.layer.borderColor = [UIColor systemRedColor].CGColor;
    alertView.layer.borderWidth = 1.5;

    CABasicAnimation *glowAnimation = [CABasicAnimation animationWithKeyPath:@"shadowRadius"];
    glowAnimation.fromValue         = @(8.0);
    glowAnimation.toValue           = @(25.0);
    glowAnimation.duration          = 1.5;
    glowAnimation.autoreverses      = YES;
    glowAnimation.repeatCount       = HUGE_VALF;
    glowAnimation.timingFunction =
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    CABasicAnimation *opacityAnimation = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    opacityAnimation.fromValue         = @(0.4);
    opacityAnimation.toValue           = @(1.0);
    opacityAnimation.duration          = 1.5;
    opacityAnimation.autoreverses      = YES;
    opacityAnimation.repeatCount       = HUGE_VALF;
    opacityAnimation.timingFunction =
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    CABasicAnimation *borderAnimation = [CABasicAnimation animationWithKeyPath:@"borderWidth"];
    borderAnimation.fromValue         = @(1.0);
    borderAnimation.toValue           = @(2.5);
    borderAnimation.duration          = 1.5;
    borderAnimation.autoreverses      = YES;
    borderAnimation.repeatCount       = HUGE_VALF;
    borderAnimation.timingFunction =
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    CAAnimationGroup *animationGroup = [CAAnimationGroup animation];
    animationGroup.animations        = @[ glowAnimation, opacityAnimation, borderAnimation ];
    animationGroup.duration          = 1.5;
    animationGroup.autoreverses      = YES;
    animationGroup.repeatCount       = HUGE_VALF;

    [alertView.layer addAnimation:animationGroup forKey:@"redLightsaberGlow"];
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

+ (uint32_t)getHermesBytecodeVersion
{
    void *symbol = dlsym(RTLD_DEFAULT, "_ZN8facebook6hermes13HermesRuntime18getBytecodeVersionEv");
    if (!symbol)
    {
        const char *dlError = dlerror();
        NSString   *errorMessage =
            dlError ? [NSString stringWithUTF8String:dlError] : @"Unknown error";
        [Logger error:LOG_CATEGORY_UTILITIES
               format:@"Failed to get bytecode version: %@", errorMessage];
        return 0;
    }

    typedef uint32_t (*HermesBytecodeVersionFn)(void);
    HermesBytecodeVersionFn getBytecodeVersion = (HermesBytecodeVersionFn) symbol;

    return getBytecodeVersion ? getBytecodeVersion() : 0;
}

+ (BOOL)isHermesBytecode:(NSData *)data
{
    void *symbol = dlsym(RTLD_DEFAULT, "_ZN8facebook6hermes13HermesRuntime16isHermesBytecodeEPKhm");
    if (!symbol)
    {
        const char *dlError = dlerror();
        NSString   *errorMessage =
            dlError ? [NSString stringWithUTF8String:dlError] : @"Unknown error";
        [Logger error:LOG_CATEGORY_UTILITIES
               format:@"Failed to check Hermes bytecode: %@", errorMessage];
        return NO;
    }

    typedef BOOL (*HermesIsBytecodeFn)(const uint8_t *, size_t);
    HermesIsBytecodeFn isHermesBytecode = (HermesIsBytecodeFn) symbol;

    return isHermesBytecode ? isHermesBytecode((const uint8_t *) [data bytes], [data length]) : NO;
}

+ (BOOL)isRNNewArchEnabled
{
    NSBundle *bundle         = [NSBundle mainBundle];
    NSNumber *newArchEnabled = [bundle objectForInfoDictionaryKey:@"RCTNewArchEnabled"];
    if (newArchEnabled)
    {
        return [newArchEnabled boolValue];
    }

    void *symbol = dlsym(RTLD_DEFAULT, "RCTIsNewArchEnabled");
    if (!symbol)
    {
        return NO;
    }

    typedef BOOL (*RCTIsNewArchEnabledFn)(void);
    RCTIsNewArchEnabledFn isNewArchEnabled = (RCTIsNewArchEnabledFn) symbol;

    return isNewArchEnabled ? isNewArchEnabled() : NO;
}

+ (BOOL)isAppStoreApp
{
    return [[NSFileManager defaultManager]
        fileExistsAtPath:[[NSBundle mainBundle] appStoreReceiptURL].path];
}

+ (BOOL)isTestFlightApp
{
    NSURL *appStoreReceiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    if (!appStoreReceiptURL)
    {
        return NO;
    }
    return [appStoreReceiptURL.lastPathComponent isEqualToString:@"sandboxReceipt"];
}

+ (NSDictionary *)checkTrollStorePaths:(NSString *)bundlePath
{
    NSString *trollStorePath = [bundlePath stringByAppendingPathComponent:TROLL_STORE_PATH];
    NSString *trollStoreLitePath =
        [bundlePath stringByAppendingPathComponent:TROLL_STORE_LITE_PATH];

    BOOL isTrollStore     = (access([trollStorePath UTF8String], F_OK) == 0);
    BOOL isTrollStoreLite = (access([trollStoreLitePath UTF8String], F_OK) == 0);

    return @{@"isTrollStore" : @(isTrollStore), @"isTrollStoreLite" : @(isTrollStoreLite)};
}

+ (BOOL)isTrollStoreApp
{
    if ([self isAppStoreApp] || [self isTestFlightApp])
    {
        return NO;
    }

    NSString     *bundlePath      = [[NSBundle mainBundle] bundlePath];
    NSDictionary *trollStorePaths = [self checkTrollStorePaths:bundlePath];

    BOOL isTrollStore     = [trollStorePaths[@"isTrollStore"] boolValue];
    BOOL isTrollStoreLite = [trollStorePaths[@"isTrollStoreLite"] boolValue];
    BOOL isTrollStoreApp  = isTrollStore || isTrollStoreLite;

    [Logger debug:LOG_CATEGORY_UTILITIES
           format:@"TrollStore detection - Regular: %@, Lite: %@, isTrollStore: %@",
                  isTrollStore ? @"YES" : @"NO", isTrollStoreLite ? @"YES" : @"NO",
                  isTrollStore ? @"YES" : @"NO"];

    return isTrollStoreApp;
}

+ (NSString *)getTrollStoreVariant
{
    NSString     *bundlePath      = [[NSBundle mainBundle] bundlePath];
    NSDictionary *trollStorePaths = [self checkTrollStorePaths:bundlePath];

    if ([trollStorePaths[@"isTrollStore"] boolValue])
    {
        return @"TrollStore";
    }
    else if ([trollStorePaths[@"isTrollStoreLite"] boolValue])
    {
        return @"TrollStore Lite";
    }

    return @"Unknown";
}

+ (BOOL)isSystemApp
{
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID)
    {
        [Logger debug:LOG_CATEGORY_UTILITIES format:@"No bundle identifier found"];
        return NO;
    }

    Class LSApplicationProxyClass = NSClassFromString(@"LSApplicationProxy");
    if (!LSApplicationProxyClass)
    {
        [Logger debug:LOG_CATEGORY_UTILITIES format:@"LSApplicationProxy class not found"];
        return NO;
    }

    SEL applicationProxySelector = @selector(applicationProxyForIdentifier:);
    if (![LSApplicationProxyClass respondsToSelector:applicationProxySelector])
    {
        [Logger debug:LOG_CATEGORY_UTILITIES
               format:@"LSApplicationProxy doesn't respond to applicationProxyForIdentifier:"];
        return NO;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id proxy = [LSApplicationProxyClass performSelector:applicationProxySelector
                                             withObject:bundleID];
#pragma clang diagnostic pop

    if (!proxy)
    {
        [Logger debug:LOG_CATEGORY_UTILITIES
               format:@"Failed to get application proxy for %@", bundleID];
        return NO;
    }

    SEL applicationTypeSelector = @selector(applicationType);
    if (![proxy respondsToSelector:applicationTypeSelector])
    {
        [Logger debug:LOG_CATEGORY_UTILITIES
               format:@"Application proxy doesn't respond to applicationType"];
        return NO;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSString *appType = [proxy performSelector:applicationTypeSelector];
#pragma clang diagnostic pop

    if (!appType)
    {
        [Logger debug:LOG_CATEGORY_UTILITIES format:@"Failed to get application type"];
        return NO;
    }

    BOOL isSystem = [appType isEqualToString:@"System"];

    [Logger debug:LOG_CATEGORY_UTILITIES
           format:@"Application type: %@, isSystemApp: %@", appType, isSystem ? @"YES" : @"NO"];

    return isSystem;
}

+ (BOOL)isJailbroken
{
    if (access("/var/mobile", R_OK) == 0)
    {
        return YES;
    }

    return NO;
}

+ (NSString *)getDeviceModel
{
    MobileGestalt *mg                         = [MobileGestalt sharedInstance];
    NSString      *physicalHardwareNameString = [mg getPhysicalHardwareNameString];

    if (physicalHardwareNameString)
    {
        return physicalHardwareNameString;
    }

    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

+ (NSString *)getiOSVersionString
{
    UIDevice *device = [UIDevice currentDevice];

    MobileGestalt *mg              = [MobileGestalt sharedInstance];
    NSString      *iosBuildVersion = [mg getBuildVersion];

    return iosBuildVersion
               ? [NSString stringWithFormat:@"%@ (%@)", device.systemVersion, iosBuildVersion]
               : device.systemVersion;
}

+ (BOOL)deviceHasDynamicIsland
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] != UIUserInterfaceIdiomPhone)
    {
        [Logger debug:LOG_CATEGORY_UTILITIES format:@"Not an iPhone, no Dynamic Island"];
        return NO;
    }

    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes)
    {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]])
        {
            UIWindowScene *windowScene = (UIWindowScene *) scene;
            for (UIWindow *window in windowScene.windows)
            {
                if (window.isKeyWindow)
                {
                    keyWindow = window;
                    break;
                }
            }
            if (keyWindow)
                break;
        }
    }

    if (!keyWindow)
    {
        [Logger debug:LOG_CATEGORY_UTILITIES
               format:@"No key window found, cannot determine Dynamic Island"];
        return NO;
    }

    CGFloat topInset         = keyWindow.safeAreaInsets.top;
    BOOL    hasDynamicIsland = fabs(topInset - DYNAMIC_ISLAND_TOP_INSET) < 0.1;

    [Logger debug:LOG_CATEGORY_UTILITIES
           format:@"Key window top safe area inset: %.1f, Dynamic Island: %@", topInset,
                  hasDynamicIsland ? @"YES" : @"NO"];

    return hasDynamicIsland;
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

    islandOverlayView.hidden = YES;
    islandOverlayView.alpha  = 0.0;

    [islandOverlayView.superview setNeedsLayout];
    [islandOverlayView.superview layoutIfNeeded];

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

+ (BOOL)isLoadedWithElleKit
{
    void *EKEnableThreadSafetyPtr = dlsym(RTLD_DEFAULT, "EKEnableThreadSafety");
    if (EKEnableThreadSafetyPtr != NULL)
    {
        return YES;
    }

    return NO;
}

+ (NSArray<NSString *> *)getAvailableAppExtensions
{
    NSString *plugInsPath =
        [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"PlugIns"];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if (![fileManager fileExistsAtPath:plugInsPath])
    {
        [Logger debug:LOG_CATEGORY_UTILITIES format:@"No PlugIns folder found"];
        return @[];
    }

    NSError *error    = nil;
    NSArray *contents = [fileManager contentsOfDirectoryAtPath:plugInsPath error:&error];

    if (error)
    {
        [Logger error:LOG_CATEGORY_UTILITIES
               format:@"Failed to read PlugIns directory: %@", error.localizedDescription];
        return @[];
    }

    NSMutableArray *extensions = [NSMutableArray array];
    for (NSString *item in contents)
    {
        if ([item hasSuffix:@".appex"])
        {
            NSString *extensionName = [item stringByDeletingPathExtension];
            [extensions addObject:extensionName];
        }
    }

    [Logger info:LOG_CATEGORY_UTILITIES
          format:@"Found %lu app extensions: %@", (unsigned long) extensions.count, extensions];
    return [extensions copy];
}

+ (BOOL)hasAppExtension:(NSString *)extensionName
{
    NSString *plugInsPath =
        [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"PlugIns"];
    NSString *extensionPath = [plugInsPath
        stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.appex", extensionName]];

    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:extensionPath];
    [Logger debug:LOG_CATEGORY_UTILITIES
           format:@"App extension '%@' %@", extensionName, exists ? @"found" : @"not found"];

    return exists;
}

+ (NSString *)getCurrentDylibName
{
    Dl_info info;
    memset(&info, 0, sizeof(info));

    IMP implementation = [self methodForSelector:@selector(getCurrentDylibName)];

    if (dladdr((const void *) implementation, &info) && info.dli_fname)
    {
        NSString *fullPath = [NSString stringWithUTF8String:info.dli_fname];
        return [fullPath lastPathComponent];
    }

    return nil;
}

+ (NSDictionary *)getApplicationEntitlements
{
    NSDictionary *signatureInfo = [self getApplicationSignatureInfo];
    return signatureInfo[@"entitlements"] ?: @{};
}

+ (NSDictionary *)getApplicationSignatureInfo
{
    NSBundle *bundle         = [NSBundle mainBundle];
    NSString *executableName = bundle.infoDictionary[@"CFBundleExecutable"];
    if (!executableName)
    {
        return @{};
    }

    NSString *executablePath = [bundle pathForResource:executableName ofType:nil];
    if (!executablePath)
    {
        return @{};
    }

    FILE *file = fopen([executablePath UTF8String], "rb");
    if (!file)
    {
        return @{};
    }

    uint32_t magic;
    if (fread(&magic, sizeof(magic), 1, file) != 1)
    {
        fclose(file);
        return @{};
    }

    fseek(file, 0, SEEK_SET);

    NSDictionary *result = nil;
    if (magic == MH_MAGIC_64 || magic == MH_CIGAM_64)
    {
        result = [self readEntitlementsFrom64BitBinary:file];
    }
    else
    {
        result = @{};
    }

    fclose(file);
    return result ?: @{};
}

+ (NSDictionary *)readEntitlementsFrom64BitBinary:(FILE *)file
{
    struct mach_header_64 header;
    if (fread(&header, sizeof(header), 1, file) != 1)
    {
        return nil;
    }

    for (uint32_t i = 0; i < header.ncmds; i++)
    {
        struct load_command cmd;
        long                cmdPos = ftell(file);

        if (fread(&cmd, sizeof(cmd), 1, file) != 1)
        {
            return nil;
        }

        if (cmd.cmd == LC_CODE_SIGNATURE)
        {
            struct linkedit_data_command sigCmd;
            fseek(file, cmdPos, SEEK_SET);
            if (fread(&sigCmd, sizeof(sigCmd), 1, file) != 1)
            {
                return nil;
            }

            return [self extractEntitlements:file offset:sigCmd.dataoff];
        }

        fseek(file, cmdPos + cmd.cmdsize, SEEK_SET);
    }

    return nil;
}

+ (NSDictionary *)extractEntitlements:(FILE *)file offset:(uint32_t)offset
{
    if (fseek(file, offset, SEEK_SET) != 0)
    {
        return nil;
    }

    struct {
        uint32_t magic;
        uint32_t length;
        uint32_t count;
    } superBlob;

    if (fread(&superBlob, sizeof(superBlob), 1, file) != 1)
    {
        return nil;
    }

    superBlob.magic  = CFSwapInt32BigToHost(superBlob.magic);
    superBlob.length = CFSwapInt32BigToHost(superBlob.length);
    superBlob.count  = CFSwapInt32BigToHost(superBlob.count);

    if (superBlob.magic != 0xfade0cc0)
    { // CSMAGIC_EMBEDDED_SIGNATURE
        return nil;
    }

    for (uint32_t i = 0; i < superBlob.count; i++)
    {
        struct {
            uint32_t type;
            uint32_t offset;
        } blobIndex;

        if (fread(&blobIndex, sizeof(blobIndex), 1, file) != 1)
        {
            continue;
        }

        blobIndex.type   = CFSwapInt32BigToHost(blobIndex.type);
        blobIndex.offset = CFSwapInt32BigToHost(blobIndex.offset);

        if (blobIndex.type == 5)
        { // CSSLOT_ENTITLEMENTS
            long          currentPos   = ftell(file);
            NSDictionary *entitlements = [self readEntitlementsBlob:file
                                                             offset:offset + blobIndex.offset];
            fseek(file, currentPos, SEEK_SET);

            if (entitlements)
            {
                return @{@"entitlements" : entitlements};
            }
        }
    }

    return @{};
}

+ (NSDictionary *)readEntitlementsBlob:(FILE *)file offset:(uint32_t)offset
{
    if (fseek(file, offset, SEEK_SET) != 0)
        return nil;

    struct {
        uint32_t magic;
        uint32_t length;
    } blobHeader;

    if (fread(&blobHeader, sizeof(blobHeader), 1, file) != 1)
        return nil;

    blobHeader.magic  = CFSwapInt32BigToHost(blobHeader.magic);
    blobHeader.length = CFSwapInt32BigToHost(blobHeader.length);

    if (blobHeader.magic != 0xfade7171)
        return nil; // CSMAGIC_EMBEDDED_ENTITLEMENTS

    uint32_t       entitlementsLength = blobHeader.length - 8;
    NSMutableData *entitlementsData   = [NSMutableData dataWithLength:entitlementsLength];

    if (fread([entitlementsData mutableBytes], entitlementsLength, 1, file) != 1)
        return nil;

    NSError      *error        = nil;
    NSDictionary *entitlements = [NSPropertyListSerialization propertyListWithData:entitlementsData
                                                                           options:0
                                                                            format:nil
                                                                             error:&error];

    return (error || !entitlements) ? nil : entitlements;
}

+ (NSString *)formatEntitlementsAsPlist:(NSDictionary *)entitlements
{
    if (!entitlements || entitlements.count == 0)
    {
        return nil;
    }

    NSError *error = nil;
    NSData  *plistData =
        [NSPropertyListSerialization dataWithPropertyList:entitlements
                                                   format:NSPropertyListXMLFormat_v1_0
                                                  options:0
                                                    error:&error];

    if (error || !plistData)
    {
        return nil;
    }

    NSString *plistString = [[NSString alloc] initWithData:plistData encoding:NSUTF8StringEncoding];
    return plistString;
}

+ (void)showDevelopmentBuildBanner
{
    static UILabel *devBuildLabel = nil;

    if (devBuildLabel)
    {
        return;
    }

    UIWindow *window = nil;

    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes)
    {
        if (scene.activationState == UISceneActivationStateForegroundActive)
        {
            UIWindowScene *windowScene = (UIWindowScene *) scene;
            window                     = windowScene.windows.firstObject;
            break;
        }
    }

    if (!window)
    {
        return;
    }

    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat height      = 20.0;
    CGFloat yPosition   = window.safeAreaInsets.top;

    devBuildLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, yPosition, screenWidth, height)];
    devBuildLabel.backgroundColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.7];
    devBuildLabel.textColor       = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    devBuildLabel.font            = [UIFont boldSystemFontOfSize:12.0];
    devBuildLabel.textAlignment   = NSTextAlignmentCenter;
    devBuildLabel.text            = @"DEVELOPMENT BUILD - DO NOT USE";

    devBuildLabel.layer.shadowColor   = [UIColor blackColor].CGColor;
    devBuildLabel.layer.shadowOffset  = CGSizeMake(0.0, 1.0);
    devBuildLabel.layer.shadowOpacity = 0.8;
    devBuildLabel.layer.shadowRadius  = 1.0;

    [window addSubview:devBuildLabel];
    [window bringSubviewToFront:devBuildLabel];
}

+ (BOOL)isVerifiedBuild
{
    [Logger info:LOG_CATEGORY_UTILITIES format:@"Starting tweak signature verification..."];

    @try
    {
        NSData *signatureData = [Utilities getResource:@"signature" data:YES ext:@"bin"];
        if (!signatureData)
        {
            [Logger error:LOG_CATEGORY_UTILITIES format:@"Signature file not found"];
            return NO;
        }

        [Logger info:LOG_CATEGORY_UTILITIES
              format:@"Signature file found, size: %lu bytes",
                     (unsigned long) [signatureData length]];

        NSData *publicKeyData = [Utilities getResource:@"public_key" data:YES ext:@"der"];
        if (!publicKeyData)
        {
            [Logger error:LOG_CATEGORY_UTILITIES format:@"Public key file not found"];
            return NO;
        }

        [Logger info:LOG_CATEGORY_UTILITIES
              format:@"Public key data size: %lu bytes", (unsigned long) [publicKeyData length]];

        CFErrorRef error = NULL;
        SecKeyRef  publicKey =
            SecKeyCreateWithData((__bridge CFDataRef) publicKeyData, (__bridge CFDictionaryRef) @{
                (__bridge id) kSecAttrKeyType : (__bridge id) kSecAttrKeyTypeRSA,
                (__bridge id) kSecAttrKeyClass : (__bridge id) kSecAttrKeyClassPublic,
                (__bridge id) kSecAttrKeySizeInBits : @(2048),
            },
                                 &error);
        if (!publicKey)
        {
            [Logger error:LOG_CATEGORY_UTILITIES
                   format:@"Failed to create public key from DER data: %@",
                          error ? CFBridgingRelease(error) : @"Unknown error"];
            return NO;
        }

        [Logger info:LOG_CATEGORY_UTILITIES format:@"Public key created successfully"];

        const char *commitHashString = [COMMIT_HASH UTF8String];

        if (!commitHashString || strlen(commitHashString) == 0)
        {
            [Logger error:LOG_CATEGORY_UTILITIES format:@"Commit hash string is empty"];
            CFRelease(publicKey);
            return NO;
        }

        NSData *commitData = [NSData dataWithBytes:commitHashString
                                            length:strlen(commitHashString)];
        uint8_t digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(commitData.bytes, (CC_LONG) commitData.length, digest);
        NSData *commitHashData = [NSData dataWithBytes:digest length:sizeof(digest)];

        BOOL verified = SecKeyVerifySignature(
            publicKey, kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256,
            (__bridge CFDataRef) commitHashData, (__bridge CFDataRef) signatureData, &error);

        CFRelease(publicKey);

        if (verified)
        {
            [Logger info:LOG_CATEGORY_UTILITIES format:@"Tweak signature verification successful"];
            return YES;
        }
        else
        {
            [Logger error:LOG_CATEGORY_UTILITIES
                   format:@"Signature verification failed: %@",
                          error ? CFBridgingRelease(error) : @"Unknown error"];
            return NO;
        }
    }
    @catch (NSException *e)
    {
        [Logger error:LOG_CATEGORY_UTILITIES
               format:@"Exception during signature verification: %@", e.reason];
        return NO;
    }
}

+ (BOOL)hasDiscordProductionEntitlements
{
    NSDictionary *entitlements = [self getApplicationEntitlements];

    NSString *teamIdentifier = entitlements[@"com.apple.developer.team-identifier"];

    BOOL hasProductionEntitlements = [teamIdentifier isEqualToString:@"53Q6R32WPB"];

    [Logger debug:LOG_CATEGORY_UTILITIES
           format:@"Team identifier: %@, has production entitlements: %@",
                  teamIdentifier ?: @"(none)", hasProductionEntitlements ? @"YES" : @"NO"];

    return hasProductionEntitlements;
}

// Adapted from
// https://github.com/LiveContainer/LiveContainer/blob/cd534bde4856dd998e48cd76681b8b2cfaf49229/LiveContainer/LCBootstrap.m#L72-L98
+ (BOOL)isJITAvailable
{
#if TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR
    [Logger debug:LOG_CATEGORY_UTILITIES format:@"JIT available: Catalyst/Simulator environment"];
    return YES;
#else

    if ([self isJailbroken])
    {
        [Logger debug:LOG_CATEGORY_UTILITIES format:@"JIT available: Jailbroken device"];
        return YES;
    }

    if (@available(iOS 26.0, *))
    {
        [Logger debug:LOG_CATEGORY_UTILITIES format:@"JIT not available: iOS 26.0+"];
        return NO;
    }

    int flags;
    int result = csops(getpid(), 0, &flags, sizeof(flags));
    if (result != 0)
    {
        [Logger error:LOG_CATEGORY_UTILITIES format:@"Failed to get CS flags: %s", strerror(errno)];
        return NO;
    }

    BOOL hasDebugFlag = (flags & CS_DEBUGGED) != 0;

    [Logger debug:LOG_CATEGORY_UTILITIES
           format:@"CS flags: 0x%x, CS_DEBUGGED: %@, JIT available: %@", flags,
                  hasDebugFlag ? @"YES" : @"NO", hasDebugFlag ? @"YES" : @"NO"];

    return hasDebugFlag;
#endif
}

+ (BOOL)isLiveContainerApp
{
    Class LCSharedUtilsClass = NSClassFromString(@"LCSharedUtils");
    BOOL  isLiveContainer    = (LCSharedUtilsClass != nil);

    [Logger debug:LOG_CATEGORY_UTILITIES
           format:@"LiveContainer detection - LCSharedUtils class: %@, isLiveContainer: %@",
                  LCSharedUtilsClass ? @"Found" : @"Not found", isLiveContainer ? @"YES" : @"NO"];

    return isLiveContainer;
}

+ (NSString *)getAppSource
{
    if ([self isTrollStoreApp])
    {
        return [self getTrollStoreVariant];
    }
    else if ([self isLiveContainerApp])
    {
        if ([self isJITAvailable])
        {
            return @"LiveContainer (JIT)";
        }
        else
        {
            return @"LiveContainer (Signed)";
        }
    }
    else if ([self isAppStoreApp])
    {
        return @"App Store";
    }
    else if ([self isTestFlightApp])
    {
        return @"TestFlight";
    }
    else
    {
        return @"Sideloaded";
    }
}

+ (UIAlertAction *)createDiscordInviteButton
{
    return [UIAlertAction
        actionWithTitle:@"Join Server"
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    UIApplication *application = [UIApplication sharedApplication];
                    NSURL         *discordURL =
                        [NSURL URLWithString:@"discord://discord.com/invite/rMdzhWUaGT"];
                    NSURL *webURL = [NSURL URLWithString:@"https://discord.com/invite/rMdzhWUaGT"];

                    if ([application canOpenURL:discordURL])
                    {
                        [application openURL:discordURL options:@{} completionHandler:nil];
                    }
                    else
                    {
                        [application openURL:webURL options:@{} completionHandler:nil];
                    }
                }];
}

+ (NSString *)JSONString:(NSString *)str
{
    if (!str)
        return @"null";
    NSString *escaped = [str stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

+ (BOOL)isRecoveryModeEnabled
{
    return [Settings getBoolean:@"unbound" key:@"recovery" def:NO];
}

@end
