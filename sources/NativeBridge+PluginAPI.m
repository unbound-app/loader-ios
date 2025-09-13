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

@end

@implementation NativeBridge (PluginAPI)

static AVPlayerViewController *currentPlayerViewController = nil;

+ (NSString *)playPiPVideo:(NSString *)videoURL
{
    if (!videoURL || [videoURL length] == 0)
    {
        [Logger error:LOG_CATEGORY_NATIVEBRIDGE format:@"Video URL is required for PiP video player"];
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

        NSURL *url = [NSURL URLWithString:videoURL];
        if (!url)
        {
            [Logger error:LOG_CATEGORY_NATIVEBRIDGE format:@"Invalid video URL: %@", videoURL];
            return;
        }

        AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:url];
        AVPlayer     *player     = [AVPlayer playerWithPlayerItem:playerItem];

        currentPlayerViewController          = [[AVPlayerViewController alloc] init];
        currentPlayerViewController.player   = player;
        currentPlayerViewController.delegate = [NativeBridgePluginAPIDelegate sharedDelegate];

        currentPlayerViewController.allowsPictureInPicturePlayback                  = YES;
        currentPlayerViewController.canStartPictureInPictureAutomaticallyFromInline = YES;

        UIViewController *topViewController = [self topViewController];
        if (topViewController)
        {
            [topViewController
                presentViewController:currentPlayerViewController
                             animated:YES
                           completion:^{
                               [Logger info:LOG_CATEGORY_NATIVEBRIDGE
                                     format:@"PiP video player presented with ID: %@", playerId];

                               [player play];

                               dispatch_after(
                                   dispatch_time(DISPATCH_TIME_NOW, (int64_t) (1.0 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                                       [Logger info:LOG_CATEGORY_NATIVEBRIDGE
                                             format:@"PiP video player ready for user interaction"];
                                   });
                           }];
        }
        else
        {
            [Logger error:LOG_CATEGORY_NATIVEBRIDGE
                   format:@"No top view controller found to present PiP player"];
        }
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
