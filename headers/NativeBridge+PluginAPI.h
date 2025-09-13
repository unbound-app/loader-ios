#import "NativeBridge.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UserNotifications/UserNotifications.h>

@interface NativeBridge (PluginAPI)

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