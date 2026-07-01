#import "Haptics.h"

static BOOL isVPhone(void)
{
    static BOOL            result;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ result = [[Utilities getDeviceModel] isEqualToString:@"iPhone99,11"]; });
    return result;
}

static NSError *vphoneHapticsUnavailableError(void)
{
    return [NSError errorWithDomain:@"com.apple.CoreHaptics"
                                code:4099
                            userInfo:@{NSLocalizedDescriptionKey : @"Unavailable on vphone"}];
}

%hook CHHapticEngine
- (instancetype)initAndReturnError:(NSError **)error
{
    if (isVPhone())
    {
        if (error)
            *error = vphoneHapticsUnavailableError();
        return nil;
    }
    return %orig;
}

- (instancetype)initWithAudioSession:(AVAudioSession *)audioSession error:(NSError **)error
{
    if (isVPhone())
    {
        if (error)
            *error = vphoneHapticsUnavailableError();
        return nil;
    }
    return %orig;
}
%end

%hook UIFeedbackGenerator
- (void)prepare
{
    if (isVPhone())
        return;
    %orig;
}
%end

%hook UIImpactFeedbackGenerator
- (void)impactOccurred
{
    if (isVPhone())
        return;
    %orig;
}

- (void)impactOccurredWithIntensity:(CGFloat)intensity
{
    if (isVPhone())
        return;
    %orig;
}
%end

%hook UISelectionFeedbackGenerator
- (void)selectionChanged
{
    if (isVPhone())
        return;
    %orig;
}
%end

%hook UINotificationFeedbackGenerator
- (void)notificationOccurred:(UINotificationFeedbackType)notificationType
{
    if (isVPhone())
        return;
    %orig;
}
%end

%ctor
{
    %init();
}
