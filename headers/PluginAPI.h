#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UserNotifications/UserNotifications.h>
#import "Logger.h"

@interface PluginAPI : NSObject

+ (NSString *)showNotification:(NSString *)title 
                          body:(NSString *)body 
                     timeDelay:(NSNumber *)timeDelay 
                  soundEnabled:(NSNumber *)soundEnabled
                    identifier:(NSString *)identifier;
+ (NSString *)playPiPVideo:(NSString *)videoURL;
+ (UIViewController *)topViewController;
+ (void)cleanupPiPResources;

@end

@interface NativeBridgePluginAPIDelegate : NSObject <AVPlayerViewControllerDelegate, AVPictureInPictureControllerDelegate>
+ (instancetype)sharedDelegate;
@end
