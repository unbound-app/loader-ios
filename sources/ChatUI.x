#import "ChatUI.h"

@implementation ChatUI

static NSNumber   *customAvatarRadius  = nil;
static const float defaultAvatarRadius = -1.0f;

static NSNumber *messageBubblesEnabled     = nil;
static NSString *messageBubbleLightColor   = nil;
static NSString *messageBubbleDarkColor    = nil;
static NSNumber *messageBubbleCornerRadius = nil;

static const float defaultMessageBubbleRadius = 10.0f;
static const float messageBubbleWidthOffset   = 10.0f;
static const float messageBubbleLeadingOffset = -5.0f;

static UIColor *messageCellLightColor   = nil;
static UIColor *messageCellDarkColor    = nil;
static UIColor *messageCellDynamicColor = nil;

+ (void)setAvatarCornerRadius:(NSNumber *)radius
{
    if (!radius)
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"Avatar corner radius cannot be nil"];
        return;
    }

    float radiusValue = [radius floatValue];
    if (radiusValue < 0)
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"Avatar corner radius cannot be negative"];
        return;
    }

    customAvatarRadius = radius;
    [Logger info:LOG_CATEGORY_DEFAULT format:@"Avatar corner radius set to: %@", radius];

    [self updateAllAvatarViews];
}

+ (NSNumber *)getAvatarCornerRadius
{
    return customAvatarRadius ?: @(defaultAvatarRadius);
}

+ (void)resetAvatarCornerRadius
{
    customAvatarRadius = nil;
    [Logger info:LOG_CATEGORY_DEFAULT format:@"Avatar corner radius reset to default"];

    [self updateAllAvatarViews];
}

+ (void)updateAllAvatarViews
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes)
        {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive)
            {
                UIWindowScene *windowScene = (UIWindowScene *) scene;
                for (UIWindow *window in windowScene.windows)
                {
                    if (window.isKeyWindow)
                    {
                        keyWindow = window;
                        break;
                    }
                }
                if (keyWindow)
                    break;
            }
        }

        if (keyWindow)
        {
            [self updateAvatarViewsInView:keyWindow];
        }
    });
}

+ (void)updateAvatarViewsInView:(UIView *)view
{
    if ([NSStringFromClass([view class]) isEqualToString:@"DCDAvatarView"])
    {
        if (customAvatarRadius)
        {
            view.layer.cornerRadius = [customAvatarRadius floatValue];
        }
        else
        {
            view.layer.cornerRadius = MIN(view.frame.size.width, view.frame.size.height) / 2.0f;
        }
        [Logger debug:LOG_CATEGORY_DEFAULT
               format:@"Updated DCDAvatarView corner radius to: %f", view.layer.cornerRadius];
    }

    for (UIView *subview in view.subviews)
    {
        [self updateAvatarViewsInView:subview];
    }
}

+ (float)getCurrentAvatarRadius
{
    if (customAvatarRadius)
    {
        return [customAvatarRadius floatValue];
    }
    return -1.0f;
}

+ (void)setMessageBubblesEnabled:(NSNumber *)enabled
{
    if (!enabled)
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"Message bubbles enabled cannot be nil"];
        return;
    }

    messageBubblesEnabled = enabled;
    [Logger info:LOG_CATEGORY_DEFAULT format:@"Message bubbles enabled set to: %@", enabled];

    [self updateMessageBubbleSettings];
}

+ (void)setMessageBubblesEnabled:(NSNumber *)enabled
                      lightColor:(NSString *)lightColor
                       darkColor:(NSString *)darkColor
{
    if (!enabled)
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"Message bubbles enabled cannot be nil"];
        return;
    }

    messageBubblesEnabled = enabled;

    if (lightColor)
    {
        messageBubbleLightColor = lightColor;
    }

    if (darkColor)
    {
        messageBubbleDarkColor = darkColor;
    }

    [Logger info:LOG_CATEGORY_DEFAULT
          format:@"Message bubbles enabled: %@, light color: %@, dark color: %@", enabled,
                 lightColor ?: @"default", darkColor ?: @"default"];

    [self updateMessageBubbleSettings];
}

+ (void)setMessageBubbleColors:(NSString *)lightColor darkColor:(NSString *)darkColor
{
    messageBubbleLightColor = lightColor;
    messageBubbleDarkColor  = darkColor;

    [Logger info:LOG_CATEGORY_DEFAULT
          format:@"Message bubble colors set - light: %@, dark: %@", lightColor ?: @"default",
                 darkColor ?: @"default"];

    [self updateMessageBubbleSettings];
}

+ (void)setMessageBubbleCornerRadius:(NSNumber *)radius
{
    if (!radius)
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"Message bubble corner radius cannot be nil"];
        return;
    }

    float radiusValue = [radius floatValue];
    if (radiusValue < 0)
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"Message bubble corner radius cannot be negative"];
        return;
    }

    messageBubbleCornerRadius = radius;
    [Logger info:LOG_CATEGORY_DEFAULT format:@"Message bubble corner radius set to: %@", radius];

    [self updateMessageBubbleSettings];
}

+ (NSNumber *)getMessageBubblesEnabled
{
    return messageBubblesEnabled ?: @NO;
}

+ (NSString *)getMessageBubbleLightColor
{
    return messageBubbleLightColor;
}

+ (NSString *)getMessageBubbleDarkColor
{
    return messageBubbleDarkColor;
}

+ (NSNumber *)getMessageBubbleCornerRadius
{
    return messageBubbleCornerRadius ?: @(defaultMessageBubbleRadius);
}

+ (void)resetMessageBubbles
{
    messageBubblesEnabled     = nil;
    messageBubbleLightColor   = nil;
    messageBubbleDarkColor    = nil;
    messageBubbleCornerRadius = nil;
    [Logger info:LOG_CATEGORY_DEFAULT format:@"Message bubbles reset to default"];

    [self updateMessageBubbleSettings];
}

+ (void)updateMessageBubbleSettings
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self loadDynamicColors];
        [self updateAllMessageCells];
    });
}

+ (BOOL)isDiscordDarkMode
{
    CGFloat red             = 0;
    Class   themeColorClass = NSClassFromString(@"DCDThemeColor");
    if (themeColorClass && [themeColorClass respondsToSelector:@selector(BACKGROUND_PRIMARY)])
    {
        UIColor *bgColor = [themeColorClass BACKGROUND_PRIMARY];
        [bgColor getRed:&red green:nil blue:nil alpha:nil];
        return red < 0.25;
    }
    return YES;
}

+ (void)loadDynamicColors
{
    if (messageBubbleLightColor || messageBubbleDarkColor)
    {
        UIColor *customLightColor =
            messageBubbleLightColor ? [self parseColor:messageBubbleLightColor] : nil;
        UIColor *customDarkColor =
            messageBubbleDarkColor ? [self parseColor:messageBubbleDarkColor] : nil;

        messageCellLightColor =
            customLightColor ?: [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.4];
        messageCellDarkColor =
            customDarkColor ?: [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.4];
    }
    else
    {
        messageCellLightColor = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.4];
        messageCellDarkColor  = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.4];
    }

    messageCellDynamicColor =
        [[UIColor alloc] initWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
            return [self isDiscordDarkMode] ? messageCellDarkColor : messageCellLightColor;
        }];
}

+ (UIColor *)parseColor:(NSString *)color
{
    if ([color hasPrefix:@"#"])
    {
        if (color.length == 7)
        {
            color = [color stringByAppendingString:@"FF"];
        }

        NSScanner *scanner = [NSScanner scannerWithString:color];
        unsigned   res     = 0;

        [scanner setScanLocation:1];
        [scanner scanHexInt:&res];

        CGFloat r = ((res & 0xFF000000) >> 24) / 255.0;
        CGFloat g = ((res & 0x00FF0000) >> 16) / 255.0;
        CGFloat b = ((res & 0x0000FF00) >> 8) / 255.0;
        CGFloat a = (res & 0x000000FF) / 255.0;

        return [UIColor colorWithRed:r green:g blue:b alpha:a];
    }

    if ([color hasPrefix:@"rgba"])
    {
        NSRegularExpression *regex =
            [NSRegularExpression regularExpressionWithPattern:@"\\((.*)\\)"
                                                      options:NSRegularExpressionCaseInsensitive
                                                        error:nil];
        NSArray  *matches = [regex matchesInString:color
                                          options:0
                                            range:NSMakeRange(0, [color length])];
        NSString *value   = @"";

        for (NSTextCheckingResult *match in matches)
        {
            NSRange range = [match rangeAtIndex:1];
            value         = [color substringWithRange:range];
        }

        NSCharacterSet *whitespaces = [NSCharacterSet whitespaceCharacterSet];
        NSArray        *values      = [value componentsSeparatedByString:@","];
        NSMutableArray *res         = [[NSMutableArray alloc] init];

        for (NSString *v in values)
        {
            NSString *trimmed = [v stringByTrimmingCharactersInSet:whitespaces];
            NSNumber *payload = [NSNumber numberWithFloat:[trimmed floatValue]];
            [res addObject:payload];
        }

        if (res.count >= 4)
        {
            CGFloat r = [[res objectAtIndex:0] floatValue] / 255.0f;
            CGFloat g = [[res objectAtIndex:1] floatValue] / 255.0f;
            CGFloat b = [[res objectAtIndex:2] floatValue] / 255.0f;
            CGFloat a = [[res objectAtIndex:3] floatValue];
            return [UIColor colorWithRed:r green:g blue:b alpha:a];
        }
    }

    return nil;
}

+ (void)updateAllMessageCells
{
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes)
    {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive)
        {
            UIWindowScene *windowScene = (UIWindowScene *) scene;
            for (UIWindow *window in windowScene.windows)
            {
                if (window.isKeyWindow)
                {
                    keyWindow = window;
                    break;
                }
            }
            if (keyWindow)
                break;
        }
    }

    if (keyWindow)
    {
        [self updateMessageCellsInView:keyWindow];
    }
}

+ (void)updateMessageCellsInView:(UIView *)view
{
    if ([NSStringFromClass([view class]) isEqualToString:@"DCDMessageTableViewCell"])
    {
        DCDMessageTableViewCell *cell = (DCDMessageTableViewCell *) view;
        [self updateMessageCell:cell];
    }

    for (UIView *subview in view.subviews)
    {
        [self updateMessageCellsInView:subview];
    }
}

+ (void)updateMessageCell:(DCDMessageTableViewCell *)cell
{
    BOOL enabled = messageBubblesEnabled ? [messageBubblesEnabled boolValue] : NO;

    if (!enabled)
    {
        if (cell.customBackgroundView)
        {
            [cell.customBackgroundView removeFromSuperview];
            cell.customBackgroundView = nil;
        }
        return;
    }

    if (!cell.customBackgroundView)
    {
        cell.customBackgroundView = [[UIView alloc] init];
        [cell insertSubview:cell.customBackgroundView atIndex:0];
        cell.customBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
        cell.customBackgroundView.layer.masksToBounds                       = YES;

        [NSLayoutConstraint activateConstraints:@[
            [cell.customBackgroundView.heightAnchor
                constraintEqualToAnchor:cell.innerView.heightAnchor],
            [cell.customBackgroundView.widthAnchor
                constraintEqualToAnchor:cell.innerView.widthAnchor
                               constant:messageBubbleWidthOffset],
            [cell.customBackgroundView.leadingAnchor
                constraintEqualToAnchor:cell.innerView.leadingAnchor
                               constant:messageBubbleLeadingOffset],
            [cell.customBackgroundView.topAnchor constraintEqualToAnchor:cell.innerView.topAnchor],
        ]];
    }

    cell.customBackgroundView.hidden          = NO;
    cell.customBackgroundView.backgroundColor = messageCellDynamicColor;

    float radius = messageBubbleCornerRadius ? [messageBubbleCornerRadius floatValue]
                                             : defaultMessageBubbleRadius;
    cell.customBackgroundView.layer.cornerRadius = radius;
}

@end

%hook DCDAvatarView

- (void)layoutSubviews
{
    %orig;

    if (customAvatarRadius)
    {
        self.layer.cornerRadius = [customAvatarRadius floatValue];
    }
    else
    {
        self.layer.cornerRadius = MIN(self.frame.size.width, self.frame.size.height) / 2.0f;
    }
}

%end

%hook DCDMessageTableViewCell
%property(nonatomic, strong) UIView *customBackgroundView;

- (void)setBackgroundColor:(UIColor *)arg1
{
    BOOL enabled = messageBubblesEnabled ? [messageBubblesEnabled boolValue] : NO;
    %orig(enabled ? [UIColor clearColor] : arg1);
}

- (void)didMoveToSuperview
{
    %orig;

    BOOL enabled = messageBubblesEnabled ? [messageBubblesEnabled boolValue] : NO;

    if (enabled && !self.customBackgroundView)
    {
        self.customBackgroundView = [[UIView alloc] init];
        [self insertSubview:self.customBackgroundView atIndex:0];
        self.customBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;

        float radius = messageBubbleCornerRadius ? [messageBubbleCornerRadius floatValue]
                                                 : defaultMessageBubbleRadius;
        self.customBackgroundView.layer.cornerRadius  = radius;
        self.customBackgroundView.layer.masksToBounds = YES;
        self.customBackgroundView.backgroundColor     = messageCellDynamicColor;

        [NSLayoutConstraint activateConstraints:@[
            [self.customBackgroundView.heightAnchor
                constraintEqualToAnchor:self.innerView.heightAnchor],
            [self.customBackgroundView.widthAnchor
                constraintEqualToAnchor:self.innerView.widthAnchor
                               constant:messageBubbleWidthOffset],
            [self.customBackgroundView.leadingAnchor
                constraintEqualToAnchor:self.innerView.leadingAnchor
                               constant:messageBubbleLeadingOffset],
            [self.customBackgroundView.topAnchor constraintEqualToAnchor:self.innerView.topAnchor],
        ]];
    }
    else if (!enabled && self.customBackgroundView)
    {
        [self.customBackgroundView removeFromSuperview];
        self.customBackgroundView = nil;
    }
}

- (void)prepareForReuse
{
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{ [ChatUI updateMessageCell:self]; });
}

%end

%hook DCDSeparatorTableViewCell

- (void)setBackgroundColor:(UIColor *)arg1
{
    BOOL enabled = messageBubblesEnabled ? [messageBubblesEnabled boolValue] : NO;
    %orig(enabled ? [UIColor clearColor] : arg1);
}

%end

%ctor
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(),
                   ^{ [ChatUI loadDynamicColors]; });
}
