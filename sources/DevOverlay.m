#import "DevOverlay.h"

// A tap outside the pill should dismiss it and otherwise fall through untouched to Discord below;
// a tap inside the pill or on the button should behave normally. hitTest returns nil (i.e. "let
// the touch fall through") whenever the default UIView hit-test would've resolved to this view
// itself rather than an actual subview (the button, or the pill's own rows while it's showing) -
// and fires outsideTapHandler first so the pill gets a chance to close.
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

// A single pill row: icon + title + optional checkmark, tap-handled via a plain block rather than
// target/action boilerplate at every call site.
@interface DevOverlayRowButton : UIButton
@property (nonatomic, copy) void (^rowAction)(void);
@property (nonatomic, assign) BOOL dismissesOnTap;
@end

@implementation DevOverlayRowButton
// The row's actual content (icon/label/checkmark) is a non-interactive UIStackView, not a
// button-managed image/title, so UIButton's own automatic highlight styling has nothing to dim -
// this is what gives taps their press feedback back.
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

// A floating button exposing native-module features that have no on-device way to trigger
// without writing a JS plugin first (message bubbles, avatar radius, notifications). Shown on
// vphone always, and on any DEBUG build regardless of device. Tapping it shows a custom pill of
// rows anchored to the button.
//
// This is a hand-rolled pill rather than a native UIMenu/UIContextMenuInteraction on purpose:
// Discord's own long-press context menus (reactions, message actions, etc.) are themselves built
// on UIContextMenuInteraction, and iOS's presentation/layout state for that system appears to be
// shared across interactions - using our own UIMenu here was leaving Discord's own menus rendered
// small and pinned to the top-left afterwards. A fully custom view has no such shared state, and
// as a bonus gives full control over which rows dismiss the pill on tap and which don't (no
// iOS-16-only `keepsMenuPresented` workaround needed).
@implementation DevOverlay

static UIWindow *devOverlayWindow = nil;
static UIButton *devOverlayButton = nil;
static UIView   *devOverlayPill   = nil;

// Never intentionally made key (nothing here calls makeKeyWindow on our own window), but as a
// defensive measure every row's action re-asserts Discord's real window as key before running,
// in case showing our overlay window ever knocks it out of key status behind the scenes.
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

    // The very first call is guaranteed to be Discord's own window: our overlay doesn't exist
    // yet at this point, and this method is a no-op on every later becomeKeyWindow call.
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

    // A scene-attached UIWindow ignores a custom .frame set before it's ever been shown (it snaps
    // to the screen bounds), so the real frame is applied AFTER `hidden = NO` and followed by a
    // forced layout pass. Collapsed (button-only) to start - see growOverlayWindow/
    // shrinkOverlayWindow for why this grows to full-screen only while the pill is open.
    overlayWindow.frame = [self collapsedFrameForScreenBounds:activeScene.screen.bounds];
    [overlayWindow layoutIfNeeded];

    const CGFloat side   = 44;
    CGRect        bounds = overlayWindow.bounds;
    CGRect        buttonFrame =
        CGRectMake(bounds.size.width - side - 16, bounds.size.height - side - 96, side, side);

    // The blur lives BEHIND the button as a separate sibling view, not nested inside it: modern
    // UIButtonTypeSystem manages its own content (image/title) through an internal view hierarchy
    // that reshuffles on state changes, and a manually-inserted subview could end up reordered on
    // top of the icon by that internal management.
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

// The button's frame is anchored to the window's bottom-right corner via autoresizing margins
// (FlexibleLeftMargin/FlexibleTopMargin), and both frames below share that same screen corner -
// so growing/shrinking the window moves neither the button nor its backdrop on screen.
+ (CGRect)collapsedFrameForScreenBounds:(CGRect)screenBounds
{
    const CGFloat width  = 76;
    const CGFloat height = 156;
    return CGRectMake(screenBounds.size.width - width, screenBounds.size.height - height, width,
                       height);
}

// The window only covers a small corner most of the time (kept intentionally tiny - see the
// class comment on why a large persistent overlay window is worth avoiding). It's grown to full
// screen for exactly as long as the pill is showing, which is also the only time an outside tap
// needs to be catchable anywhere on screen to dismiss it.
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

// Rebuilds the pill in place (fresh checkmarks/labels) after a row that stays open is tapped - no
// animation, this is a same-frame content refresh, not a show/hide transition.
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

    // Rows are inset from the pill's edges (rather than spanning edge-to-edge) so each row's own
    // rounded highlight never touches - and gets clipped by - the pill's rounded outer corners.
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

// Finds the preset closest to a value (used both to show the current one as selected and to
// figure out what "next" means when cycling).
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
