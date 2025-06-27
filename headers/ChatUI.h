#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Logger.h"

@interface ChatUI : NSObject

+ (void)setAvatarCornerRadius:(NSNumber *)radius;
+ (NSNumber *)getAvatarCornerRadius;
+ (void)resetAvatarCornerRadius;
+ (float)getCurrentAvatarRadius;

@end

@interface DCDAvatarView : UIView
@end
