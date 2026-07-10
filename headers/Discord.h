#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


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

@interface DCDBundleUpdaterManager : NSObject
- (void)reload;
@end
