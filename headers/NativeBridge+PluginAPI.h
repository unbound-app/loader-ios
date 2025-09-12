#import "NativeBridge.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UserNotifications/UserNotifications.h>

@interface NativeBridge (PluginAPI)

// Notification methods
+ (NSString *)showNotification:(NSString *)title 
                          body:(NSString *)body 
                     timeDelay:(NSNumber *)timeDelay 
                  soundEnabled:(NSNumber *)soundEnabled
                    identifier:(NSString *)identifier;

// Picture in Picture video methods
+ (NSString *)playPiPVideo:(NSString *)videoURL;

// Utility methods
+ (UIViewController *)topViewController;

@end

// Delegate for PiP functionality
@interface NativeBridgePluginAPIDelegate : NSObject <AVPlayerViewControllerDelegate>
+ (instancetype)sharedDelegate;
@end