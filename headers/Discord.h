#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Reverse-engineered interfaces for Discord's own (DCD*) classes that the tweak messages.

@interface DCDAvatarView : UIView
@end

@interface                            DCDMessageTableViewCell : UITableViewCell
@property (nonatomic, strong) UIView *customBackgroundView;
@property (nonatomic, strong) UIView *innerView;
@end

@interface DCDSeparatorTableViewCell : UITableViewCell
@end

@interface DCDThemeColor : NSObject
+ (UIColor *)BACKGROUND_PRIMARY;
@end

@interface DCDTheme : NSObject
+ (NSInteger)themeIndex;
@end

// Discord's bundle-updater RN module. Its -reload is the path Discord/Unbound's JS uses
// to reload the app; we capture the live instance at construction (see Unbound.xm).
@interface DCDBundleUpdaterManager : NSObject
- (void)reload;
@end
