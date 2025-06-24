#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import "Logger.h"

@interface PluginAPI : NSObject

+ (NSString *)showNotification:(NSString *)title 
                          body:(NSString *)body 
                     timeDelay:(NSNumber *)timeDelay 
                  soundEnabled:(NSNumber *)soundEnabled
                    identifier:(NSString *)identifier;

@end
