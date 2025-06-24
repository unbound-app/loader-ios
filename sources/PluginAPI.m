#import "PluginAPI.h"

@implementation PluginAPI

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
                     [Logger error:LOG_CATEGORY_PLUGIN
                            format:@"Error scheduling notification: %@", error.localizedDescription];
                 }
                 else
                 {
                     [Logger info:LOG_CATEGORY_PLUGIN
                           format:@"Notification scheduled with id: %@", notificationId];
                 }
             }];
    });

    return notificationId;
}

@end
