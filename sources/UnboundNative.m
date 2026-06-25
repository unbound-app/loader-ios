#import "UnboundNative.h"

@implementation UnboundNative

+ (NSString *)moduleName
{
    return @"UnboundNative";
}
+ (BOOL)requiresMainQueueSetup
{
    return NO;
}

// Synchronous methods: return-typed (no resolver/rejecter), so they run on the
// JS thread and return directly. Only non-blocking reads / work that doesn't need
// to complete on the main thread before returning. JS may still await them
// harmlessly. (await on a non-Promise resolves immediately.)

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(getDeviceModel, id, util_getDeviceModel)
{
    return [Utilities getDeviceModel] ?: [NSNull null];
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(getiOSVersionString, id, util_getiOSVersionString)
{
    return [Utilities getiOSVersionString] ?: [NSNull null];
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(isJailbroken, id, util_isJailbroken)
{
    return @([Utilities isJailbroken]);
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(isSystemApp, id, util_isSystemApp)
{
    return @([Utilities isSystemApp]);
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(isVerifiedBuild, id, util_isVerifiedBuild)
{
    return @([Utilities isVerifiedBuild]);
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(getApplicationEntitlements, id,
                                      util_getApplicationEntitlements)
{
    NSDictionary *ent = [Utilities getApplicationEntitlements];
    return ent ?: @{};
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(getAppSource, id, util_getAppSource)
{
    return [Utilities getAppSource] ?: [NSNull null];
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(getEntitlementsAsPlist, id, util_getEntitlementsAsPlist)
{
    NSDictionary *entitlements = [Utilities getApplicationEntitlements];
    NSString     *plist        = [Utilities formatEntitlementsAsPlist:entitlements];
    return plist ?: [NSNull null];
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(
    showNotification, id,
    plugin_showNotificationWithTitle : (NSString *) title body : (NSString *)
        body scheduledTime : (NSNumber *) scheduledTime sound : (NSNumber *)
            sound notificationId : (NSString *) notificationId)
{
    // Returns the id synchronously; PluginAPI schedules the notification on main.
    NSString *nid =
        [PluginAPI showNotification:(title ?: @"Notification")
                               body:(body ?: @"") timeDelay:(scheduledTime ?: @(1)) soundEnabled
                                   :(sound ?: @(YES)) identifier
                                   :(notificationId ?: [[NSUUID UUID] UUIDString])];
    return nid ?: [NSNull null];
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(playPiPVideo, id,
                                      plugin_playPiPVideoWithURL : (NSString *) videoURL)
{
    // Returns the id synchronously; PluginAPI presents the player on main.
    if (![videoURL isKindOfClass:[NSString class]] || videoURL.length == 0)
    {
        return [NSNull null];
    }
    NSString *pid = [PluginAPI playPiPVideo:videoURL];
    return pid ?: [NSNull null];
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(getAvatarCornerRadius, id, chat_getAvatarCornerRadius)
{
    return [ChatUI getAvatarCornerRadius] ?: @(-1.0f);
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(getMessageBubbleLightColor, id,
                                      chat_getMessageBubbleLightColor)
{
    return [ChatUI getMessageBubbleLightColor] ?: [NSNull null];
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(getMessageBubbleDarkColor, id, chat_getMessageBubbleDarkColor)
{
    return [ChatUI getMessageBubbleDarkColor] ?: [NSNull null];
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(getMessageBubblesEnabled, id, chat_getMessageBubblesEnabled)
{
    NSNumber *val = [ChatUI getMessageBubblesEnabled] ?: @NO;
    return @(val.boolValue);
}

RCT_REMAP_BLOCKING_SYNCHRONOUS_METHOD(getMessageBubbleCornerRadius, id,
                                      chat_getMessageBubbleCornerRadius)
{
    return [ChatUI getMessageBubbleCornerRadius] ?: @(10.0f);
}

// Asynchronous (Promise) methods: dispatch to the main thread, so they stay
// async to avoid blocking/deadlocking the JS thread.

RCT_REMAP_METHOD(showToolboxMenu, util_showToolboxMenuWithResolver : (RCTPromiseResolveBlock)
                                      resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [Toolbox showToolboxMenu];
        resolve([NSNull null]);
    });
}

RCT_REMAP_METHOD(setAvatarCornerRadius,
                 chat_setAvatarCornerRadius : (nonnull NSNumber *) radius resolver : (
                     RCTPromiseResolveBlock) resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [ChatUI setAvatarCornerRadius:radius];
        resolve([NSNull null]);
    });
}

RCT_REMAP_METHOD(resetAvatarCornerRadius,
                 chat_resetAvatarCornerRadiusWithResolver : (RCTPromiseResolveBlock)
                     resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [ChatUI resetAvatarCornerRadius];
        resolve([NSNull null]);
    });
}

RCT_REMAP_METHOD(setMessageBubblesEnabled,
                 chat_setMessageBubblesEnabled : (nonnull NSNumber *) enabled lightColor : (id)
                     lightColor darkColor : (id) darkColor resolver : (RCTPromiseResolveBlock)
                         resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([lightColor isKindOfClass:[NSString class]] ||
            [darkColor isKindOfClass:[NSString class]])
        {
            [ChatUI setMessageBubblesEnabled:enabled
                                  lightColor:([lightColor isKindOfClass:[NSString class]]
                                                  ? lightColor
                                                  : nil) darkColor
                                            :([darkColor isKindOfClass:[NSString class]] ? darkColor
                                                                                         : nil)];
        }
        else
        {
            [ChatUI setMessageBubblesEnabled:enabled];
        }
        resolve([NSNull null]);
    });
}

RCT_REMAP_METHOD(setMessageBubbleColors,
                 chat_setMessageBubbleColors : (NSString *) lightColor darkColor : (NSString *)
                     darkColor   resolver : (RCTPromiseResolveBlock)
                         resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [ChatUI setMessageBubbleColors:lightColor darkColor:darkColor];
        resolve([NSNull null]);
    });
}

RCT_REMAP_METHOD(setMessageBubbleCornerRadius,
                 chat_setMessageBubbleCornerRadius : (nonnull NSNumber *) radius resolver : (
                     RCTPromiseResolveBlock) resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [ChatUI setMessageBubbleCornerRadius:radius];
        resolve([NSNull null]);
    });
}

RCT_REMAP_METHOD(resetMessageBubbles,
                 chat_resetMessageBubblesWithResolver : (RCTPromiseResolveBlock)
                     resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [ChatUI resetMessageBubbles];
        resolve([NSNull null]);
    });
}

@end
