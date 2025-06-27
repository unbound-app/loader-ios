#import "ChatUI.h"

@implementation ChatUI

static NSNumber   *customAvatarRadius  = nil;
static const float defaultAvatarRadius = -1.0f;

+ (void)setAvatarCornerRadius:(NSNumber *)radius
{
    if (!radius)
    {
        [Logger error:LOG_CATEGORY_PLUGIN format:@"Avatar corner radius cannot be nil"];
        return;
    }

    float radiusValue = [radius floatValue];
    if (radiusValue < 0)
    {
        [Logger error:LOG_CATEGORY_PLUGIN format:@"Avatar corner radius cannot be negative"];
        return;
    }

    customAvatarRadius = radius;
    [Logger info:LOG_CATEGORY_PLUGIN format:@"Avatar corner radius set to: %@", radius];

    [self updateAllAvatarViews];
}

+ (NSNumber *)getAvatarCornerRadius
{
    return customAvatarRadius ?: @(defaultAvatarRadius);
}

+ (void)resetAvatarCornerRadius
{
    customAvatarRadius = nil;
    [Logger info:LOG_CATEGORY_PLUGIN format:@"Avatar corner radius reset to default"];

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
        [Logger debug:LOG_CATEGORY_PLUGIN
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
