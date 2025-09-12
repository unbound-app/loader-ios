#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import "Logger.h"

@interface PluginAPI : NSObject

+ (NSString *)showNotification:(NSString *)title 
                          body:(NSString *)body 
                     timeDelay:(NSNumber *)timeDelay 
                  soundEnabled:(NSNumber *)soundEnabled
                    identifier:(NSString *)identifier;

+ (NSString *)playPiPVideo:(NSString *)videoURL;

+ (UIViewController *)topViewController;

@end
