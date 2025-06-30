#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

#import "Logger.h"

@interface UnboundNotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation UnboundNotificationDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler
{
    [Logger debug:LOG_CATEGORY_DEFAULT
           format:@"Notification received while app in foreground: %@",
                  notification.request.identifier];

    completionHandler(UNNotificationPresentationOptionBanner |
                      UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler
{
    [Logger debug:LOG_CATEGORY_DEFAULT
           format:@"User responded to notification: %@", response.notification.request.identifier];
    completionHandler();
}

@end

static UnboundNotificationDelegate *notificationDelegate = nil;

%ctor
{
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!notificationDelegate)
            {
                [Logger info:LOG_CATEGORY_DEFAULT format:@"Setting up notification delegate"];
                notificationDelegate = [[UnboundNotificationDelegate alloc] init];
                [UNUserNotificationCenter currentNotificationCenter].delegate =
                    notificationDelegate;

                [[UNUserNotificationCenter currentNotificationCenter]
                    requestAuthorizationWithOptions:(UNAuthorizationOptionAlert |
                                                     UNAuthorizationOptionBadge |
                                                     UNAuthorizationOptionSound)
                                  completionHandler:^(BOOL granted, NSError *_Nullable error) {
                                      if (error)
                                      {
                                          [Logger error:LOG_CATEGORY_DEFAULT
                                                 format:@"Notification permission error: %@",
                                                        error.localizedDescription];
                                      }
                                      else
                                      {
                                          [Logger info:LOG_CATEGORY_DEFAULT
                                                format:@"Notification permission %@",
                                                       granted ? @"granted" : @"denied"];
                                      }
                                  }];
            }
        });

    %init;
}
