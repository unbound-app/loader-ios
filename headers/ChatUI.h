#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class DCDMessageTableViewCell;

@interface ChatUI : NSObject

+ (void)setAvatarCornerRadius:(NSNumber *)radius;
+ (NSNumber *)getAvatarCornerRadius;
+ (void)resetAvatarCornerRadius;
+ (float)getCurrentAvatarRadius;

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

+ (void)updateMessageCell:(DCDMessageTableViewCell *)cell;

@end

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
