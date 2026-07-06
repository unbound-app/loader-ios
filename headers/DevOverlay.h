#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "ChatUI.h"
#import "PluginAPI.h"
#import "Toolbox.h"
#import "Utilities.h"

@interface DevOverlay : NSObject

+ (void)ensureOverlayForWindow:(UIWindow *)keyWindow;
+ (void)showDevelopmentBuildBanner;

@end
