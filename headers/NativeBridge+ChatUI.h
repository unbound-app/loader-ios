#import "NativeBridge.h"

@interface NativeBridge (ChatUI)

// Avatar customization methods
+ (void)setAvatarCornerRadius:(NSNumber *)radius;
+ (NSNumber *)getAvatarCornerRadius;
+ (void)resetAvatarCornerRadius;
+ (float)getCurrentAvatarRadius;

// Message bubble customization methods
+ (void)setMessageBubblesEnabled:(NSNumber *)enabled;
+ (void)setMessageBubblesEnabled:(NSNumber *)enabled
                      lightColor:(NSString *)lightColor
                       darkColor:(NSString *)darkColor;
+ (void)setMessageBubbleColors:(NSString *)lightColor darkColor:(NSString *)darkColor;
+ (void)setMessageBubbleCornerRadius:(NSNumber *)radius;
+ (NSNumber *)getMessageBubblesEnabled;
+ (NSString *)getMessageBubbleLightColor;
+ (NSString *)getMessageBubbleDarkColor;
+ (NSNumber *)getMessageBubbleCornerRadius;
+ (void)resetMessageBubbles;

@end

// Forward declarations for Discord classes
@interface DCDAvatarView : UIView
@end

@interface DCDMessageTableViewCell : UITableViewCell
@property (nonatomic, strong) UIView *customBackgroundView;
@property (nonatomic, strong) UIView *innerView;
@end

@interface DCDSeparatorTableViewCell : UITableViewCell
@end

@interface DCDThemeColor : NSObject
+ (UIColor *)BACKGROUND_PRIMARY;
@end