#import "DevOverlay.h"

// Passes touches through to whatever's below unless they land on a real subview (the button or
// an open pill's rows); fires outsideTapHandler first so an open pill gets a chance to close.
@interface DevOverlayPassthroughView : UIView
@property (nonatomic, copy) void (^outsideTapHandler)(void);
@end

@implementation DevOverlayPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self && self.outsideTapHandler)
    {
        self.outsideTapHandler();
    }
    return hitView == self ? nil : hitView;
}
@end

// A single pill row: icon + title + optional checkmark, tap-handled via a plain block.
@interface DevOverlayRowButton : UIButton
@property (nonatomic, copy) void (^rowAction)(void);
@property (nonatomic, assign) BOOL dismissesOnTap;
@end

@implementation DevOverlayRowButton
// Content is a plain UIStackView, not a button-managed image/title, so there's nothing for
// UIButton's automatic highlight to dim without this.
- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.1
                     animations:^{
                         self.backgroundColor = highlighted
                                                     ? [UIColor.labelColor colorWithAlphaComponent:0.08]
                                                     : UIColor.clearColor;
                     }];
}
@end

// Floating button exposing native-module features with no on-device trigger otherwise (message
// bubbles, avatar radius, notifications). Shown on vphone always, and on any DEBUG build.
//
// The pill is hand-rolled rather than a native UIMenu: UIMenu shared presentation state with
// Discord's own UIContextMenuInteraction-based menus and left them rendered small and pinned to
// the top-left afterwards. A plain view sidesteps that, and gives per-row control over dismissal.
@implementation DevOverlay

static UIWindow *devOverlayWindow = nil;
static UIButton *devOverlayButton = nil;
static UIView   *devOverlayPill   = nil;

// Re-asserted as key before every row action, in case our overlay window knocks it out of key
// status behind the scenes.
static UIWindow *discordKeyWindow = nil;

static NSArray<NSNumber *> *avatarRadiusPresets = nil;

+ (void)initialize
{
    if (self != [DevOverlay class])
        return;

    avatarRadiusPresets = @[ @0, @8, @16, @20 ];
}

+ (UIWindowScene *)activeWindowScene
{
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
    {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]])
        {
            return (UIWindowScene *) scene;
        }
    }
    return nil;
}

+ (void)ensureOverlayForWindow:(UIWindow *)keyWindow
{
#ifdef DEBUG
    BOOL shouldShow = YES;
#else
    BOOL shouldShow = [Utilities isVPhone];
#endif
    if (!shouldShow || devOverlayWindow)
    {
        return;
    }

    // The first call is always Discord's own window - this method no-ops on every later one.
    discordKeyWindow = keyWindow;

    UIWindowScene *activeScene = keyWindow.windowScene ?: [self activeWindowScene];
    if (!activeScene)
    {
        return;
    }

    UIWindow *overlayWindow       = [[UIWindow alloc] initWithWindowScene:activeScene];
    overlayWindow.windowLevel     = UIWindowLevelAlert - 1;
    overlayWindow.backgroundColor = [UIColor clearColor];

    DevOverlayPassthroughView *passthroughView = [[DevOverlayPassthroughView alloc] init];
    passthroughView.backgroundColor            = [UIColor clearColor];
    passthroughView.outsideTapHandler           = ^{ [DevOverlay dismissPill]; };

    UIViewController *rootVC         = [UIViewController new];
    rootVC.view                      = passthroughView;
    overlayWindow.rootViewController = rootVC;

    overlayWindow.hidden = NO;

    // A scene-attached UIWindow snaps to the screen bounds until shown, so the real frame is set
    // after `hidden = NO`. Collapsed (button-only) to start; see growOverlayWindow.
    overlayWindow.frame = [self collapsedFrameForScreenBounds:activeScene.screen.bounds];
    [overlayWindow layoutIfNeeded];

    const CGFloat side   = 44;
    CGRect        bounds = overlayWindow.bounds;
    CGRect        buttonFrame =
        CGRectMake(bounds.size.width - side - 16, bounds.size.height - side - 96, side, side);

    // Blur lives behind the button as a sibling, not nested inside it: UIButtonTypeSystem
    // reshuffles its own content subviews on state changes and could bury a nested one.
    UIView *backdrop = [[UIView alloc] initWithFrame:buttonFrame];
    backdrop.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    backdrop.layer.cornerRadius     = side / 2.0;
    backdrop.layer.cornerCurve      = kCACornerCurveContinuous;
    backdrop.layer.masksToBounds    = YES;
    backdrop.userInteractionEnabled = NO;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    blur.frame            = backdrop.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [backdrop addSubview:blur];

    [rootVC.view addSubview:backdrop];

    UIButton *button        = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame            = buttonFrame;
    button.autoresizingMask = backdrop.autoresizingMask;
    button.tintColor        = UIColor.labelColor;
    button.backgroundColor  = UIColor.clearColor;

    UIImageSymbolConfiguration *symbolConfig =
        [UIImageSymbolConfiguration configurationWithPointSize:18
                                                        weight:UIImageSymbolWeightRegular];
    [button setImage:[UIImage systemImageNamed:@"wrench.and.screwdriver.fill"
                              withConfiguration:symbolConfig]
             forState:UIControlStateNormal];
    [button addTarget:self
                  action:@selector(toggleButtonTapped)
        forControlEvents:UIControlEventTouchUpInside];

    [rootVC.view addSubview:button];

    devOverlayWindow = overlayWindow;
    devOverlayButton = button;
}

// Both this and the expanded (full-screen) frame share the same bottom-right corner, and the
// button is pinned to it via autoresizing margins, so growing/shrinking never moves the button.
+ (CGRect)collapsedFrameForScreenBounds:(CGRect)screenBounds
{
    const CGFloat width  = 76;
    const CGFloat height = 156;
    return CGRectMake(screenBounds.size.width - width, screenBounds.size.height - height, width,
                       height);
}

// Full-screen only while the pill is open, so an outside tap anywhere can dismiss it; collapsed
// the rest of the time to keep the window's footprint minimal.
+ (void)growOverlayWindow
{
    UIWindowScene *scene = devOverlayWindow.windowScene;
    if (!scene)
        return;

    devOverlayWindow.frame = scene.screen.bounds;
    [devOverlayWindow layoutIfNeeded];
}

+ (void)shrinkOverlayWindow
{
    UIWindowScene *scene = devOverlayWindow.windowScene;
    if (!scene)
        return;

    devOverlayWindow.frame = [self collapsedFrameForScreenBounds:scene.screen.bounds];
    [devOverlayWindow layoutIfNeeded];
}

+ (void)toggleButtonTapped
{
    if (devOverlayPill)
    {
        [self dismissPill];
    }
    else
    {
        [self showPill];
    }
}

+ (void)showPill
{
    if (devOverlayPill || !devOverlayButton)
        return;

    [self growOverlayWindow];

    UIView *pill = [self buildPillView];
    [devOverlayButton.superview insertSubview:pill belowSubview:devOverlayButton];

    const CGFloat pillWidth = 250;
    CGSize fitSize = [pill systemLayoutSizeFittingSize:CGSizeMake(pillWidth, UILayoutFittingCompressedSize.height)
                          withHorizontalFittingPriority:UILayoutPriorityRequired
                                verticalFittingPriority:UILayoutPriorityFittingSizeLevel];

    CGRect buttonFrame = devOverlayButton.frame;
    CGRect pillFrame    = CGRectMake(CGRectGetMaxX(buttonFrame) - pillWidth,
                                      buttonFrame.origin.y - fitSize.height - 12, pillWidth,
                                      fitSize.height);
    pill.frame     = pillFrame;
    pill.alpha     = 0;
    pill.transform = CGAffineTransformMakeScale(0.92, 0.92);

    devOverlayPill = pill;

    [UIView animateWithDuration:0.18
                          delay:0
         usingSpringWithDamping:0.85
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         pill.alpha     = 1;
                         pill.transform = CGAffineTransformIdentity;
                     }
                     completion:nil];
}

+ (void)dismissPill
{
    if (!devOverlayPill)
        return;

    UIView *pill    = devOverlayPill;
    devOverlayPill  = nil;

    [UIView animateWithDuration:0.15
        animations:^{
            pill.alpha     = 0;
            pill.transform = CGAffineTransformMakeScale(0.92, 0.92);
        }
        completion:^(BOOL finished) {
            [pill removeFromSuperview];
            [self shrinkOverlayWindow];
        }];
}

// Rebuilds the pill in place (fresh checkmarks/labels) with no show/hide animation.
+ (void)refreshPill
{
    if (!devOverlayPill)
        return;

    CGRect  oldFrame = devOverlayPill.frame;
    UIView *oldPill  = devOverlayPill;
    [oldPill removeFromSuperview];

    UIView *newPill = [self buildPillView];
    [devOverlayButton.superview insertSubview:newPill belowSubview:devOverlayButton];

    const CGFloat pillWidth = oldFrame.size.width;
    CGSize        fitSize =
        [newPill systemLayoutSizeFittingSize:CGSizeMake(pillWidth, UILayoutFittingCompressedSize.height)
              withHorizontalFittingPriority:UILayoutPriorityRequired
                    verticalFittingPriority:UILayoutPriorityFittingSizeLevel];

    CGRect buttonFrame = devOverlayButton.frame;
    newPill.frame       = CGRectMake(CGRectGetMaxX(buttonFrame) - pillWidth,
                                      buttonFrame.origin.y - fitSize.height - 12, pillWidth,
                                      fitSize.height);
    devOverlayPill = newPill;
}

#pragma mark - Pill construction

+ (UIView *)buildPillView
{
    UIVisualEffectView *container = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    container.layer.cornerRadius  = 16;
    container.layer.cornerCurve   = kCACornerCurveContinuous;
    container.layer.masksToBounds = YES;

    // Inset from the pill's edges so each row's rounded highlight isn't clipped by the container's.
    UIStackView *stack                                 = [[UIStackView alloc] init];
    stack.axis                                         = UILayoutConstraintAxisVertical;
    stack.spacing                                       = 2;
    stack.layoutMarginsRelativeArrangement              = YES;
    stack.layoutMargins                                 = UIEdgeInsetsMake(0, 6, 0, 6);
    stack.translatesAutoresizingMaskIntoConstraints     = NO;
    [container.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.contentView.topAnchor constant:8],
        [stack.bottomAnchor constraintEqualToAnchor:container.contentView.bottomAnchor constant:-8],
        [stack.leadingAnchor constraintEqualToAnchor:container.contentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:container.contentView.trailingAnchor],
    ]];

    NSArray<UIView *> *rows = @[
        [self bubbleToggleRow], [self avatarRadiusCycleRow], [self notificationTestRow],
        [self openToolboxRow]
    ];
    for (UIView *row in rows)
    {
        [stack addArrangedSubview:row];
    }

    return container;
}

+ (DevOverlayRowButton *)rowWithTitle:(NSString *)title
                           systemImage:(NSString *)imageName
                                  isOn:(BOOL)isOn
                        dismissesOnTap:(BOOL)dismissesOnTap
                                action:(void (^)(void))action
{
    DevOverlayRowButton *row                          = [DevOverlayRowButton buttonWithType:UIButtonTypeCustom];
    row.translatesAutoresizingMaskIntoConstraints      = NO;
    [row.heightAnchor constraintEqualToConstant:44].active = YES;
    row.rowAction                                      = action;
    row.dismissesOnTap                                  = dismissesOnTap;
    row.layer.cornerRadius                              = 10;
    row.layer.cornerCurve                               = kCACornerCurveContinuous;
    row.layer.masksToBounds                             = YES;

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium];
    UIImageView *icon = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:imageName withConfiguration:cfg]];
    icon.tintColor   = UIColor.labelColor;
    icon.contentMode = UIViewContentModeCenter;
    [icon.widthAnchor constraintEqualToConstant:20].active = YES;

    UILabel *label     = [[UILabel alloc] init];
    label.text          = title;
    label.font          = [UIFont systemFontOfSize:14];
    label.textColor     = UIColor.labelColor;
    label.numberOfLines = 1;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                            forAxis:UILayoutConstraintAxisHorizontal];

    UIImageView *checkmark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"]];
    checkmark.tintColor    = UIColor.systemBlueColor;
    checkmark.hidden       = !isOn;
    checkmark.contentMode  = UIViewContentModeCenter;
    [checkmark.widthAnchor constraintEqualToConstant:16].active = YES;

    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[ icon, label, checkmark ]];
    content.axis                                      = UILayoutConstraintAxisHorizontal;
    content.alignment                                  = UIStackViewAlignmentCenter;
    content.spacing                                    = 10;
    content.userInteractionEnabled                     = NO;
    content.translatesAutoresizingMaskIntoConstraints  = NO;
    [row addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [content.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14],
        [content.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    return row;
}

+ (void)rowTapped:(DevOverlayRowButton *)sender
{
    void (^rowAction)(void) = sender.rowAction;
    BOOL shouldDismiss       = sender.dismissesOnTap;

    if (shouldDismiss)
    {
        [self dismissPill];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (discordKeyWindow && !discordKeyWindow.isKeyWindow)
        {
            [discordKeyWindow makeKeyWindow];
        }

        if (rowAction)
        {
            rowAction();
        }

        if (!shouldDismiss)
        {
            [self refreshPill];
        }
    });
}

// Closest preset to a value - marks the current one and anchors what "next" means when cycling.
+ (NSUInteger)indexOfClosestPreset:(NSArray<NSNumber *> *)presets toValue:(float)value
{
    NSUInteger bestIndex = 0;
    float      bestDiff  = FLT_MAX;
    for (NSUInteger i = 0; i < presets.count; i++)
    {
        float diff = fabsf(presets[i].floatValue - value);
        if (diff < bestDiff)
        {
            bestDiff  = diff;
            bestIndex = i;
        }
    }
    return bestIndex;
}

#pragma mark - Row builders

+ (DevOverlayRowButton *)bubbleToggleRow
{
    BOOL enabled = [[ChatUI getMessageBubblesEnabled] boolValue];
    return [self rowWithTitle:@"Message Bubbles"
                   systemImage:@"bubble.left.and.bubble.right"
                          isOn:enabled
                dismissesOnTap:NO
                        action:^{
                            [ChatUI setMessageBubblesEnabled:@(!enabled)];
                        }];
}

// Cycle: Default (circular) -> 0pt -> 8pt -> 16pt -> 20pt -> Default -> ...
+ (DevOverlayRowButton *)avatarRadiusCycleRow
{
    float    current   = [ChatUI getCurrentAvatarRadius];  // -1 == default/circular
    BOOL     isDefault = current < 0;
    NSString *label    = isDefault ? @"Avatar Radius: Circular"
                                    : [NSString stringWithFormat:@"Avatar Radius: %.0fpt", current];

    return [self rowWithTitle:label
                   systemImage:@"person.crop.circle"
                          isOn:NO
                dismissesOnTap:NO
                        action:^{
                            if (isDefault)
                            {
                                [ChatUI setAvatarCornerRadius:avatarRadiusPresets.firstObject];
                            }
                            else
                            {
                                NSUInteger idx =
                                    [self indexOfClosestPreset:avatarRadiusPresets toValue:current];
                                if (idx + 1 < avatarRadiusPresets.count)
                                {
                                    [ChatUI setAvatarCornerRadius:avatarRadiusPresets[idx + 1]];
                                }
                                else
                                {
                                    [ChatUI resetAvatarCornerRadius];
                                }
                            }
                        }];
}

+ (DevOverlayRowButton *)notificationTestRow
{
    return [self rowWithTitle:@"Send Test Notification"
                   systemImage:@"bell.badge"
                          isOn:NO
                dismissesOnTap:NO
                        action:^{
                            [self sendTestNotification];
                        }];
}

+ (void)sendTestNotification
{
    NSString *identifier = [PluginAPI showNotification:@"Unbound Dev Overlay"
                                                    body:@"Test notification fired from the dev overlay"
                                               timeDelay:@3
                                            soundEnabled:@YES
                                              identifier:@"dev-overlay-test"];
    if (!identifier.length)
    {
        [Logger error:LOG_CATEGORY_TOOLBOX format:@"DevOverlay: test notification failed to schedule"];
    }
}

+ (DevOverlayRowButton *)openToolboxRow
{
    return [self rowWithTitle:@"Open Unbound Toolbox"
                   systemImage:@"wrench.and.screwdriver"
                          isOn:NO
                dismissesOnTap:YES
                        action:^{
                            [Toolbox showToolboxMenu];
                        }];
}

#pragma mark - Development build banner

+ (void)showDevelopmentBuildBanner
{
    static UILabel *devBuildLabel = nil;

    if (devBuildLabel)
    {
        return;
    }

    UIWindow *window = [Utilities keyWindow];
    if (!window)
    {
        return;
    }

    CGFloat screenWidth = window.bounds.size.width;
    CGFloat height      = 52.0;
    CGFloat yPosition   = window.safeAreaInsets.top;

    devBuildLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, yPosition, screenWidth, height)];
    devBuildLabel.backgroundColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.7];
    devBuildLabel.textColor       = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    devBuildLabel.font            = [UIFont boldSystemFontOfSize:11.0];
    devBuildLabel.textAlignment   = NSTextAlignmentCenter;
    devBuildLabel.numberOfLines   = 3;
    devBuildLabel.lineBreakMode   = NSLineBreakByTruncatingTail;

    NSString               *commitSubject     = COMMIT_SUBJECT ?: @"";
    static const NSUInteger kMaxSubjectLength = 36;
    if (commitSubject.length > kMaxSubjectLength)
    {
        commitSubject =
            [[commitSubject substringToIndex:kMaxSubjectLength] stringByAppendingString:@"..."];
    }

    devBuildLabel.text = [NSString
        stringWithFormat:@"DEVELOPMENT BUILD - DO NOT USE\n#%@ - %@ - %@\nBuilt: %@",
                         COMMIT_SHORT_HASH, commitSubject, COMMIT_BRANCH, BUILD_TIMESTAMP];

    devBuildLabel.layer.shadowColor   = [UIColor blackColor].CGColor;
    devBuildLabel.layer.shadowOffset  = CGSizeMake(0.0, 1.0);
    devBuildLabel.layer.shadowOpacity = 0.8;
    devBuildLabel.layer.shadowRadius  = 1.0;
    devBuildLabel.alpha               = 0.0;

    [window addSubview:devBuildLabel];
    [window bringSubviewToFront:devBuildLabel];

    [UIView animateWithDuration:0.4 animations:^{ devBuildLabel.alpha = 1.0; }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10.0 * NSEC_PER_SEC), dispatch_get_main_queue(),
                   ^{
                       if (!devBuildLabel || !devBuildLabel.superview)
                       {
                           return;
                       }

                       [UIView animateWithDuration:0.4
                           animations:^{ devBuildLabel.alpha = 0.0; }
                           completion:^(BOOL finished) {
                               [devBuildLabel removeFromSuperview];
                               devBuildLabel = nil;
                           }];
                   });
}

@end
