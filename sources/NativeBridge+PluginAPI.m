#import "NativeBridge+PluginAPI.h"

@implementation NativeBridgePluginAPIDelegate

+ (instancetype)sharedDelegate
{
    static NativeBridgePluginAPIDelegate *sharedInstance = nil;
    static dispatch_once_t                onceToken;
    dispatch_once(&onceToken, ^{ sharedInstance = [[NativeBridgePluginAPIDelegate alloc] init]; });
    return sharedInstance;
}

- (void)playerViewController:(AVPlayerViewController *)playerViewController
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:
        (void (^)(BOOL))completionHandler
{
    [Logger info:LOG_CATEGORY_NATIVEBRIDGE format:@"Restoring user interface for PiP stop"];

    UIViewController *topViewController = [NativeBridge topViewController];
    if (topViewController && playerViewController != topViewController.presentedViewController)
    {
        [topViewController presentViewController:playerViewController
                                        animated:NO
                                      completion:^{
                                          [Logger info:LOG_CATEGORY_DEFAULT
                                                format:@"PiP player interface restored"];
                                          if (completionHandler)
                                          {
                                              completionHandler(YES);
                                          }
                                      }];
    }
    else
    {
        [Logger info:LOG_CATEGORY_NATIVEBRIDGE format:@"PiP player already presented"];
        if (completionHandler)
        {
            completionHandler(YES);
        }
    }
}

- (void)playerViewControllerWillStartPictureInPicture:(AVPlayerViewController *)playerViewController
{
    [Logger info:LOG_CATEGORY_NATIVEBRIDGE format:@"PiP will start"];
}

- (void)playerViewControllerDidStartPictureInPicture:(AVPlayerViewController *)playerViewController
{
    [Logger info:LOG_CATEGORY_NATIVEBRIDGE format:@"PiP did start successfully"];

    if (playerViewController.presentingViewController)
    {
        [playerViewController
            dismissViewControllerAnimated:YES
                               completion:^{
                                   [Logger info:LOG_CATEGORY_NATIVEBRIDGE
                                         format:@"Full-screen player dismissed after PiP start"];
                               }];
    }
}

- (void)playerViewController:(AVPlayerViewController *)playerViewController
    failedToStartPictureInPictureWithError:(NSError *)error
{
    [Logger error:LOG_CATEGORY_NATIVEBRIDGE
           format:@"Failed to start PiP: %@", error.localizedDescription];
}

- (void)playerViewControllerWillStopPictureInPicture:(AVPlayerViewController *)playerViewController
{
    [Logger info:LOG_CATEGORY_NATIVEBRIDGE format:@"PiP will stop"];
}

- (void)playerViewControllerDidStopPictureInPicture:(AVPlayerViewController *)playerViewController
{
    [Logger info:LOG_CATEGORY_NATIVEBRIDGE format:@"PiP did stop"];
}

- (void)pictureInPictureControllerWillStartPictureInPicture:
    (AVPictureInPictureController *)pictureInPictureController
{
    [Logger info:LOG_CATEGORY_NATIVEBRIDGE format:@"PiP controller will start"];
}

- (void)pictureInPictureControllerDidStartPictureInPicture:
    (AVPictureInPictureController *)pictureInPictureController
{
    [Logger info:LOG_CATEGORY_NATIVEBRIDGE format:@"PiP controller did start successfully"];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController
    failedToStartPictureInPictureWithError:(NSError *)error
{
    [Logger error:LOG_CATEGORY_NATIVEBRIDGE
           format:@"PiP controller failed to start: %@", error.localizedDescription];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:
        (void (^)(BOOL))completionHandler
{
    [Logger info:LOG_CATEGORY_NATIVEBRIDGE format:@"Restoring UI after PiP (controller)"];
    if (completionHandler)
        completionHandler(YES);
}

- (void)pictureInPictureControllerWillStopPictureInPicture:
    (AVPictureInPictureController *)pictureInPictureController
{
    [Logger info:LOG_CATEGORY_NATIVEBRIDGE format:@"PiP controller will stop"];
}

- (void)pictureInPictureControllerDidStopPictureInPicture:
    (AVPictureInPictureController *)pictureInPictureController
{
    [Logger info:LOG_CATEGORY_NATIVEBRIDGE
          format:@"PiP controller did stop; cleaning up resources"];
    [NativeBridge cleanupPiPResources];
}

@end

@implementation NativeBridge (PluginAPI)

static AVPlayerViewController       *currentPlayerViewController = nil;
static AVPictureInPictureController *currentPiPController        = nil;
static AVPlayer                     *currentPlayer               = nil;
static AVPlayerLayer                *currentPlayerLayer          = nil;
static UIView                       *currentHostView             = nil;

+ (void)tryStartPiPWithRetries:(NSInteger)remaining
{
    if (!currentPiPController)
        return;
    if (currentPiPController.pictureInPictureActive)
        return;
    if (currentPiPController.pictureInPicturePossible)
    {
        [currentPiPController startPictureInPicture];
        return;
    }
    if (remaining <= 0)
        return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{ [NativeBridge tryStartPiPWithRetries:remaining - 1]; });
}

+ (void)cleanupPiPResources
{
    if (currentPiPController && currentPiPController.pictureInPictureActive)
    {
        [currentPiPController stopPictureInPicture];
    }
    currentPiPController.delegate = nil;
    currentPiPController          = nil;

    if (currentPlayerLayer.superlayer)
    {
        [currentPlayerLayer removeFromSuperlayer];
    }
    currentPlayerLayer = nil;
    if (currentHostView.superview)
    {
        [currentHostView removeFromSuperview];
    }
    currentHostView = nil;

    if (currentPlayer)
    {
        [currentPlayer pause];
    }
    currentPlayer = nil;
}

+ (NSString *)playPiPVideo:(NSString *)videoURL
{
    if (!videoURL || [videoURL length] == 0)
    {
        [Logger error:LOG_CATEGORY_NATIVEBRIDGE
               format:@"Video URL is required for PiP video player"];
        return nil;
    }

    if (![AVPictureInPictureController isPictureInPictureSupported])
    {
        [Logger error:LOG_CATEGORY_NATIVEBRIDGE
               format:@"Picture in Picture is not supported on this device"];
        return nil;
    }

    NSString *playerId = [[NSUUID UUID] UUIDString];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (currentPlayerViewController && currentPlayerViewController.presentingViewController)
        {
            [currentPlayerViewController dismissViewControllerAnimated:NO completion:nil];
        }
        if (currentPiPController && currentPiPController.pictureInPictureActive)
        {
            [currentPiPController stopPictureInPicture];
        }

        NSURL *url = [NSURL URLWithString:videoURL];
        if (!url)
        {
            [Logger error:LOG_CATEGORY_NATIVEBRIDGE format:@"Invalid video URL: %@", videoURL];
            return;
        }

        @try
        {
            NSError        *audioError = nil;
            AVAudioSession *session    = [AVAudioSession sharedInstance];
            BOOL ok = [session setCategory:AVAudioSessionCategoryPlayback
                               withOptions:AVAudioSessionCategoryOptionDuckOthers
                                     error:&audioError];
            if (!ok || audioError)
            {
                [Logger error:LOG_CATEGORY_NATIVEBRIDGE
                       format:@"Audio session category error: %@", audioError.localizedDescription];
            }
            audioError = nil;
            ok         = [session setActive:YES error:&audioError];
            if (!ok || audioError)
            {
                [Logger error:LOG_CATEGORY_NATIVEBRIDGE
                       format:@"Audio session activate error: %@", audioError.localizedDescription];
            }
        }
        @catch (NSException *exception)
        {
            [Logger error:LOG_CATEGORY_NATIVEBRIDGE
                   format:@"Audio session exception: %@", exception.reason];
        }

        AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:url];
        currentPlayer            = [AVPlayer playerWithPlayerItem:playerItem];
        currentPlayer.muted      = NO;
        currentPlayer.volume     = 1.0;

        currentPlayerLayer              = [AVPlayerLayer playerLayerWithPlayer:currentPlayer];
        currentPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspect;

        UIViewController *topViewController = [self topViewController];
        if (!topViewController)
        {
            [Logger error:LOG_CATEGORY_NATIVEBRIDGE
                   format:@"No top view controller found to host PiP layer"];
            return;
        }

        if (!currentHostView)
        {
            currentHostView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
            currentHostView.userInteractionEnabled = NO;
            currentHostView.alpha                  = 0.01;
            [topViewController.view addSubview:currentHostView];
        }
        currentPlayerLayer.frame = currentHostView.bounds;
        [currentHostView.layer addSublayer:currentPlayerLayer];

        if (@available(iOS 15.0, *))
        {
            AVPictureInPictureControllerContentSource *source =
                [[AVPictureInPictureControllerContentSource alloc]
                    initWithPlayerLayer:currentPlayerLayer];
            currentPiPController =
                [[AVPictureInPictureController alloc] initWithContentSource:source];
        }
        else
        {
            currentPiPController =
                [[AVPictureInPictureController alloc] initWithPlayerLayer:currentPlayerLayer];
        }
        currentPiPController.delegate = [NativeBridgePluginAPIDelegate sharedDelegate];
        currentPiPController.canStartPictureInPictureAutomaticallyFromInline = YES;

        [Logger info:LOG_CATEGORY_NATIVEBRIDGE
              format:@"Starting playback and requesting PiP for ID: %@", playerId];

        [currentPlayer play];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (0.1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           if (currentPiPController &&
                               currentPiPController.pictureInPicturePossible)
                           {
                               [currentPiPController startPictureInPicture];
                           }
                           else
                           {
                               [Logger info:LOG_CATEGORY_NATIVEBRIDGE
                                     format:@"PiP not yet possible; retrying..."];
                               [NativeBridge tryStartPiPWithRetries:20];
                           }
                       });
    });

    return playerId;
}

+ (UIViewController *)topViewController
{
    UIViewController *topController   = nil;
    NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
    for (UIScene *scene in connectedScenes)
    {
        if ([scene isKindOfClass:[UIWindowScene class]])
        {
            UIWindowScene *windowScene = (UIWindowScene *) scene;
            for (UIWindow *window in windowScene.windows)
            {
                if (window.isKeyWindow)
                {
                    topController = window.rootViewController;
                    break;
                }
            }
            if (topController)
                break;
        }
    }

    while (topController.presentedViewController)
    {
        topController = topController.presentedViewController;
    }

    return topController;
}

+ (NSString *)showNotification:(NSString *)title
                          body:(NSString *)body
                     timeDelay:(NSNumber *)timeDelay
                  soundEnabled:(NSNumber *)soundEnabled
                    identifier:(NSString *)identifier
{
    NSString      *notificationId = identifier ?: [[NSUUID UUID] UUIDString];
    NSString      *finalTitle     = title ?: @"Notification";
    NSString      *finalBody      = body ?: @"";
    NSTimeInterval delay          = timeDelay ? [timeDelay doubleValue] : 1.0;
    BOOL           playSound      = soundEnabled ? [soundEnabled boolValue] : YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title                         = finalTitle;

        if ([finalBody length] > 0)
        {
            content.body = finalBody;
        }

        if (playSound)
        {
            content.sound = [UNNotificationSound defaultSound];
        }

        UNTimeIntervalNotificationTrigger *trigger =
            [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:delay repeats:NO];

        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:notificationId
                                                                              content:content
                                                                              trigger:trigger];

        [[UNUserNotificationCenter currentNotificationCenter]
            addNotificationRequest:request
             withCompletionHandler:^(NSError *_Nullable error) {
                 if (error)
                 {
                     [Logger
                          error:LOG_CATEGORY_NATIVEBRIDGE
                         format:@"Error scheduling notification: %@", error.localizedDescription];
                 }
                 else
                 {
                     [Logger info:LOG_CATEGORY_NATIVEBRIDGE
                           format:@"Notification scheduled with id: %@", notificationId];
                 }
             }];
    });

    return notificationId;
}

@end
