#import "ChatUI.h"

#import <CoreText/CoreText.h>
#import <objc/runtime.h>

@interface YYTextRunDelegate : NSObject
- (CTRunDelegateRef)CTRunDelegate CF_RETURNS_RETAINED;
@end

@implementation ChatUI

static NSNumber   *customAvatarRadius  = nil;
static const float defaultAvatarRadius = -1.0f;
static NSDictionary<NSString *, NSDictionary<NSString *, id> *> *mentionAvatars = nil;
static NSCache<NSString *, UIImage *> *mentionAvatarImageCache = nil;
static BOOL mentionAvatarsShowAtSymbol = YES;
static BOOL mentionAvatarUpdateScheduled = NO;
static void *mentionAvatarOriginalTextKey = &mentionAvatarOriginalTextKey;

static NSNumber *messageBubblesEnabled     = nil;
static NSString *messageBubbleLightColor   = nil;
static NSString *messageBubbleDarkColor    = nil;
static NSNumber *messageBubbleCornerRadius = nil;

static const float defaultMessageBubbleRadius = 10.0f;
static const float messageBubbleHorizontalPadding = 8.0f;
static const float messageBubbleVerticalPadding   = 4.0f;

static UIColor *messageCellLightColor   = nil;
static UIColor *messageCellDarkColor    = nil;
static UIColor *messageCellDynamicColor = nil;

+ (void)setAvatarCornerRadius:(NSNumber *)radius
{
    if (!radius)
    {
        [Logger error:LOG_CATEGORY_CHATUI format:@"Avatar corner radius cannot be nil"];
        return;
    }

    float radiusValue = [radius floatValue];
    if (radiusValue < 0)
    {
        [Logger error:LOG_CATEGORY_CHATUI format:@"Avatar corner radius cannot be negative"];
        return;
    }

    customAvatarRadius = radius;
    [Logger info:LOG_CATEGORY_CHATUI format:@"Avatar corner radius set to: %@", radius];

    [self updateAllAvatarViews];
}

+ (NSNumber *)getAvatarCornerRadius
{
    return customAvatarRadius ?: @(defaultAvatarRadius);
}

+ (void)resetAvatarCornerRadius
{
    customAvatarRadius = nil;
    [Logger info:LOG_CATEGORY_CHATUI format:@"Avatar corner radius reset to default"];

    [self updateAllAvatarViews];
}

+ (void)updateAllAvatarViews
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [Utilities keyWindow];

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
            view.layer.cornerRadius = view.bounds.size.width / 2.0;
        }
        [Logger debug:LOG_CATEGORY_CHATUI
               format:@"Updated avatar view with radius: %f", view.layer.cornerRadius];
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
        [Logger error:LOG_CATEGORY_CHATUI format:@"Message bubbles enabled cannot be nil"];
        return;
    }

    messageBubblesEnabled = enabled;
    [Logger info:LOG_CATEGORY_CHATUI format:@"Message bubbles enabled set to: %@", enabled];

    [self updateMessageBubbleSettings];
}

+ (void)setMessageBubblesEnabled:(NSNumber *)enabled
                      lightColor:(NSString *)lightColor
                       darkColor:(NSString *)darkColor
{
    if (!enabled)
    {
        [Logger error:LOG_CATEGORY_CHATUI format:@"Message bubbles enabled cannot be nil"];
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

    [Logger info:LOG_CATEGORY_CHATUI
          format:@"Message bubbles enabled: %@, light color: %@, dark color: %@", enabled,
                 lightColor ?: @"default", darkColor ?: @"default"];

    [self updateMessageBubbleSettings];
}

+ (void)setMessageBubbleColors:(NSString *)lightColor darkColor:(NSString *)darkColor
{
    messageBubbleLightColor = lightColor;
    messageBubbleDarkColor  = darkColor;

    [Logger info:LOG_CATEGORY_CHATUI
          format:@"Message bubble colors set - light: %@, dark: %@", lightColor ?: @"default",
                 darkColor ?: @"default"];

    [self updateMessageBubbleSettings];
}

+ (void)setMessageBubbleCornerRadius:(NSNumber *)radius
{
    if (!radius)
    {
        [Logger error:LOG_CATEGORY_CHATUI format:@"Message bubble corner radius cannot be nil"];
        return;
    }

    float radiusValue = [radius floatValue];
    if (radiusValue < 0)
    {
        [Logger error:LOG_CATEGORY_CHATUI
               format:@"Message bubble corner radius cannot be negative"];
        return;
    }

    messageBubbleCornerRadius = radius;
    [Logger info:LOG_CATEGORY_CHATUI format:@"Message bubble corner radius set to: %@", radius];

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
    [Logger info:LOG_CATEGORY_CHATUI format:@"Message bubbles reset to default"];

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
            messageBubbleLightColor ? [Utilities parseColor:messageBubbleLightColor] : nil;
        UIColor *customDarkColor =
            messageBubbleDarkColor ? [Utilities parseColor:messageBubbleDarkColor] : nil;

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

+ (void)updateAllMessageCells
{
    UIWindow *keyWindow = [Utilities keyWindow];

    if (keyWindow)
    {
        [self updateMessageCellsInView:keyWindow];
    }
}

+ (void)updateMessageCellsInView:(UIView *)view
{
    if ([NSStringFromClass([view class]) isEqualToString:@"DCDMessageTableViewCell"])
    {
        [self updateMessageCell:(DCDMessageTableViewCell *) view];
    }

    for (UIView *subview in view.subviews)
    {
        [self updateMessageCellsInView:subview];
    }
}

+ (UIView *)findLargestAvatarView:(UIView *)view
{
    UIView *best     = nil;
    CGFloat bestArea = 0;

    if ([NSStringFromClass([view class]) isEqualToString:@"DCDAvatarView"])
    {
        best     = view;
        bestArea = view.bounds.size.width * view.bounds.size.height;
    }

    for (UIView *subview in view.subviews)
    {
        UIView *candidate = [self findLargestAvatarView:subview];
        if (candidate)
        {
            CGFloat area = candidate.bounds.size.width * candidate.bounds.size.height;
            if (area > bestArea)
            {
                best     = candidate;
                bestArea = area;
            }
        }
    }

    return best;
}

+ (BOOL)viewHasMediaDescendant:(UIView *)view
{
    static NSSet<NSString *> *mediaClasses = nil;
    static dispatch_once_t    onceToken;
    dispatch_once(&onceToken, ^{
        mediaClasses = [NSSet setWithObjects:@"DiscordChat.MediaMosaicView", @"DiscordChat.EmbedView",
                                              @"DiscordChatComponentsSwift.ThumbnailView",
                                              @"DCDMediaView", @"DiscordChat.AttachmentView", nil];
    });

    if ([mediaClasses containsObject:NSStringFromClass([view class])] &&
        view.bounds.size.width > 0 && view.bounds.size.height > 0)
    {
        return YES;
    }

    for (UIView *subview in view.subviews)
    {
        if ([self viewHasMediaDescendant:subview])
            return YES;
    }

    return NO;
}

+ (UIView *)findTextViewIn:(UIView *)view
{
    if ([view respondsToSelector:@selector(attributedText)])
    {
        NSAttributedString *attrText = [view valueForKey:@"attributedText"];
        if (attrText.length > 0)
            return view;
    }

    for (UIView *subview in view.subviews)
    {
        UIView *found = [self findTextViewIn:subview];
        if (found)
            return found;
    }

    return nil;
}

+ (CGRect)tightenTextFrame:(CGRect)bodyFrame forBody:(UIView *)contentBody
{
    if ([self viewHasMediaDescendant:contentBody])
        return bodyFrame;

    UIView *textView = [self findTextViewIn:contentBody];
    if (!textView)
        return bodyFrame;

    NSAttributedString *attrText = [textView valueForKey:@"attributedText"];
    CGRect              measured = [attrText boundingRectWithSize:CGSizeMake(bodyFrame.size.width,
                                                                              CGFLOAT_MAX)
                                                            options:NSStringDrawingUsesLineFragmentOrigin
                                                            context:nil];

    CGFloat measuredWidth = ceil(measured.size.width);
    if (measuredWidth <= 0 || measuredWidth >= bodyFrame.size.width)
        return bodyFrame;

    CGRect tightened  = bodyFrame;
    tightened.size.width = measuredWidth;
    return tightened;
}

+ (CGRect)contentBubbleFrameForCell:(DCDMessageTableViewCell *)cell
{
    UIView *avatarView = [self findLargestAvatarView:cell.contentView];
    if (!avatarView)
        return CGRectNull;

    UIView *node          = avatarView;
    UIView *contentColumn = nil;
    for (int level = 0; level < 6 && node.superview; level++)
    {
        UIView *parent = node.superview;
        for (UIView *sibling in parent.subviews)
        {
            if (sibling != node && sibling.frame.size.width > node.frame.size.width * 3.0 &&
                sibling.frame.size.width > 100)
            {
                contentColumn = sibling;
                break;
            }
        }
        if (contentColumn)
            break;
        node = parent;
    }
    if (!contentColumn)
        return CGRectNull;

    NSArray<UIView *> *children = contentColumn.subviews;
    if (children.count == 0)
        return CGRectNull;

    UIView *contentBody = children.count >= 2 ? children[children.count - 2] : children.lastObject;
    if (CGRectIsEmpty(contentBody.bounds))
        return CGRectNull;

    CGRect frame = [contentBody convertRect:contentBody.bounds toView:cell];
    frame        = [self tightenTextFrame:frame forBody:contentBody];
    return CGRectInset(frame, -messageBubbleHorizontalPadding, -messageBubbleVerticalPadding);
}

+ (void)updateMessageCell:(DCDMessageTableViewCell *)cell
{
    BOOL enabled = messageBubblesEnabled ? [messageBubblesEnabled boolValue] : NO;

    if (!enabled)
    {
        if (cell.customBackgroundView)
        {
            cell.customBackgroundView.hidden = YES;
        }
        return;
    }

    if (!cell.customBackgroundView)
    {
        cell.customBackgroundView                     = [[UIView alloc] init];
        cell.customBackgroundView.layer.masksToBounds = YES;
        cell.backgroundView                           = cell.customBackgroundView;
    }
    else if (cell.backgroundView != cell.customBackgroundView)
    {
        cell.backgroundView = cell.customBackgroundView;
    }

    cell.customBackgroundView.hidden          = NO;
    cell.customBackgroundView.backgroundColor = messageCellDynamicColor;

    float radius = messageBubbleCornerRadius ? [messageBubbleCornerRadius floatValue]
                                             : defaultMessageBubbleRadius;
    cell.customBackgroundView.layer.cornerRadius = radius;
}

+ (void)updateMessageCellFrame:(DCDMessageTableViewCell *)cell
{
    [self updateMessageCellFrame:cell retriesRemaining:3];
}

+ (void)updateMessageCellFrame:(DCDMessageTableViewCell *)cell retriesRemaining:(int)retriesRemaining
{
    if (!cell.customBackgroundView || cell.customBackgroundView.hidden)
        return;

    CGRect frame = [self contentBubbleFrameForCell:cell];
    if (CGRectIsNull(frame) || CGRectIsEmpty(frame))
    {
        if (retriesRemaining > 0)
        {
            __weak DCDMessageTableViewCell *weakCell = cell;
            dispatch_async(dispatch_get_main_queue(), ^{
                DCDMessageTableViewCell *strongCell = weakCell;
                if (strongCell)
                {
                    [self updateMessageCellFrame:strongCell retriesRemaining:retriesRemaining - 1];
                }
            });
        }
        return;
    }

    cell.customBackgroundView.frame = frame;
}

+ (void)setMentionAvatars:(NSDictionary<NSString *, NSDictionary<NSString *, id> *> *)mentions
             showAtSymbol:(BOOL)showAtSymbol
{
    mentionAvatars = [mentions copy] ?: @{};
    mentionAvatarsShowAtSymbol = showAtSymbol;
    [self scheduleMentionAvatarUpdate];
}

+ (void)clearMentionAvatars
{
    mentionAvatars = nil;
    [self scheduleMentionAvatarUpdate];
}

+ (void)scheduleMentionAvatarUpdate
{
    if (mentionAvatarUpdateScheduled)
    {
        return;
    }

    mentionAvatarUpdateScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        mentionAvatarUpdateScheduled = NO;
        [self updateMentionAvatarsInView:[Utilities keyWindow]];
    });
}

+ (void)clearMentionAvatarStateInView:(UIView *)view
{
    if ([view respondsToSelector:@selector(setAttributedText:)])
    {
        NSAttributedString *original = objc_getAssociatedObject(view, mentionAvatarOriginalTextKey);
        if (original)
        {
            [view setValue:original forKey:@"attributedText"];
            objc_setAssociatedObject(view, mentionAvatarOriginalTextKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    for (UIView *subview in view.subviews)
    {
        [self clearMentionAvatarStateInView:subview];
    }
}

+ (UIImage *)mentionAvatarImageForMetadata:(NSDictionary<NSString *, id> *)metadata
{
    NSString *avatarURL = metadata[@"avatarURL"];
    if ([avatarURL isKindOfClass:NSString.class] && avatarURL.length > 0)
    {
        if (!mentionAvatarImageCache)
        {
            mentionAvatarImageCache = [[NSCache alloc] init];
        }

        UIImage *cached = [mentionAvatarImageCache objectForKey:avatarURL];
        if (cached)
        {
            return cached;
        }

        NSURL *url = [NSURL URLWithString:avatarURL];
        if (url)
        {
            [[[NSURLSession sharedSession] dataTaskWithURL:url
                                         completionHandler:^(NSData *data, NSURLResponse *response,
                                                             NSError *error) {
                UIImage *image = data ? [UIImage imageWithData:data] : nil;
                if (!image)
                {
                    return;
                }

                [mentionAvatarImageCache setObject:image forKey:avatarURL];
                [self scheduleMentionAvatarUpdate];
            }] resume];
        }
    }

    if ([metadata[@"type"] isEqual:@"role"])
    {
        return [UIImage systemImageNamed:@"person.2.fill"];
    }
    return nil;
}

+ (NSAttributedString *)mentionAvatarAttachmentForImage:(UIImage *)image
                                                metadata:(NSDictionary<NSString *, id> *)metadata
                                              attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes
{
	Class attachmentClass = NSClassFromString(@"YYTextAttachment");
	Class runDelegateClass = NSClassFromString(@"YYTextRunDelegate");
	if (!attachmentClass || !runDelegateClass)
	{
		return nil;
	}

	UIFont *font = attributes[NSFontAttributeName] ?: [UIFont systemFontOfSize:14];
	CGFloat size = 16;
	BOOL isRole = [metadata[@"type"] isEqual:@"role"];
	CGFloat leading = isRole ? 4 : 2;
	CGFloat trailing = isRole ? 2 : 4;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
	CGRect imageRect = CGRectMake(0, 0, size, size);
	if (!isRole)
	{
		[[UIBezierPath bezierPathWithOvalInRect:imageRect] addClip];
	}
	[image drawInRect:imageRect blendMode:kCGBlendModeNormal alpha:1];
	UIImage *renderedImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	if (!renderedImage)
	{
		return nil;
	}

	id attachment = [[attachmentClass alloc] init];
	[attachment setValue:renderedImage forKey:@"content"];
	[attachment setValue:@(UIViewContentModeScaleAspectFit) forKey:@"contentMode"];
	[attachment setValue:[NSValue valueWithUIEdgeInsets:UIEdgeInsetsMake(0, leading, 0, trailing)]
	              forKey:@"contentInsets"];
	YYTextRunDelegate *runDelegate = [[runDelegateClass alloc] init];
	[runDelegate setValue:@(font.ascender) forKey:@"ascent"];
	[runDelegate setValue:@(-font.descender) forKey:@"descent"];
	[runDelegate setValue:@(leading + size + trailing) forKey:@"width"];
	NSMutableAttributedString *result = [[NSMutableAttributedString alloc]
	    initWithString:@"\uFFFC" attributes:attributes];
	[result addAttribute:@"YYTextAttachment" value:attachment range:NSMakeRange(0, result.length)];
	CTRunDelegateRef coreTextRunDelegate = [runDelegate CTRunDelegate];
	if (!coreTextRunDelegate)
	{
		return nil;
	}
	[result addAttribute:(NSString *)kCTRunDelegateAttributeName
	               value:(__bridge id)coreTextRunDelegate
	               range:NSMakeRange(0, result.length)];
	CFRelease(coreTextRunDelegate);
	return result;
}

+ (NSAttributedString *)mentionAvatarTextFromOriginal:(NSAttributedString *)original
{
    if (mentionAvatars.count == 0)
    {
        return original;
    }

    NSMutableAttributedString *result = [original mutableCopy];
    NSArray<NSString *> *labels = [mentionAvatars.allKeys sortedArrayUsingComparator:
        ^NSComparisonResult(NSString *left, NSString *right) {
            if (left.length > right.length) return NSOrderedAscending;
            if (left.length < right.length) return NSOrderedDescending;
            return [left compare:right];
        }];

    for (NSString *label in labels)
    {
        NSString *mentionText = [@"@" stringByAppendingString:label];
        NSRange searchRange = NSMakeRange(0, result.length);
        while (searchRange.length > 0)
        {
            NSRange range = [result.string rangeOfString:mentionText options:0 range:searchRange];
            if (range.location == NSNotFound)
            {
                break;
            }

            NSDictionary<NSAttributedStringKey, id> *attributes =
                [result attributesAtIndex:range.location effectiveRange:nil];
			if (!attributes[@"YYTextHighlight"])
			{
				NSUInteger next = NSMaxRange(range);
				searchRange = NSMakeRange(next, result.length - next);
				continue;
			}
            UIImage *image = [self mentionAvatarImageForMetadata:mentionAvatars[label]];
            if (!image)
            {
                NSUInteger next = NSMaxRange(range);
                searchRange = NSMakeRange(next, result.length - next);
                continue;
            }

			NSAttributedString *avatar = [self mentionAvatarAttachmentForImage:image
			                                                           metadata:mentionAvatars[label]
			                                                         attributes:attributes];
			if (!avatar)
			{
				NSUInteger next = NSMaxRange(range);
				searchRange = NSMakeRange(next, result.length - next);
				continue;
			}
			NSMutableAttributedString *replacement = [[NSMutableAttributedString alloc]
			    initWithAttributedString:avatar];
            NSString *text = mentionAvatarsShowAtSymbol ? mentionText : [mentionText substringFromIndex:1];
            [replacement appendAttributedString:[[NSAttributedString alloc] initWithString:text
                                                                                  attributes:attributes]];
            [result replaceCharactersInRange:range withAttributedString:replacement];

            NSUInteger next = range.location + replacement.length;
            searchRange = NSMakeRange(next, result.length - next);
        }
    }

    return result;
}

+ (void)updateMentionAvatarsInView:(UIView *)view
{
    if ([view respondsToSelector:@selector(setAttributedText:)])
    {
        NSAttributedString *original = objc_getAssociatedObject(view, mentionAvatarOriginalTextKey);
        if (!original)
        {
            original = [view valueForKey:@"attributedText"];
            if (original.length > 0)
            {
                objc_setAssociatedObject(view, mentionAvatarOriginalTextKey, original,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }

        if (original.length > 0)
        {
			NSAttributedString *updated = [self mentionAvatarTextFromOriginal:original];
            [view setValue:updated forKey:@"attributedText"];
        }
    }

    for (UIView *subview in view.subviews)
    {
        [self updateMentionAvatarsInView:subview];
    }
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
        self.layer.cornerRadius = self.bounds.size.width / 2.0;
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

    if (enabled)
    {
        [ChatUI updateMessageCell:self];
    }
    else if (self.customBackgroundView)
    {
        if (self.backgroundView == self.customBackgroundView)
        {
            self.backgroundView = nil;
        }
        self.customBackgroundView = nil;
    }
}

- (void)prepareForReuse
{
    %orig;
    [ChatUI clearMentionAvatarStateInView:self];
    dispatch_async(dispatch_get_main_queue(), ^{ [ChatUI updateMessageCell:self]; });
}

- (void)layoutSubviews
{
    %orig;

    [ChatUI updateMentionAvatarsInView:self];

    BOOL enabled = messageBubblesEnabled ? [messageBubblesEnabled boolValue] : NO;
    if (enabled)
    {
        [ChatUI updateMessageCellFrame:self];
    }
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
