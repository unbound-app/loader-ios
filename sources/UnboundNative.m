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

RCT_REMAP_METHOD(alert,
                 alertMessage : (NSString *) message options : (NSDictionary *) options resolver : (
                     RCTPromiseResolveBlock) resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    if (![message isKindOfClass:[NSString class]] || message.length == 0)
    {
        reject(@"EINVAL", @"message must be a non-empty string", nil);
        return;
    }

    NSString *title    = ([options isKindOfClass:[NSDictionary class]] ? options[@"title"] : nil);
    NSNumber *timeoutN = ([options isKindOfClass:[NSDictionary class]] ? options[@"timeout"] : nil);
    NSNumber *warningN = ([options isKindOfClass:[NSDictionary class]] ? options[@"warning"] : nil);
    NSNumber *ttsN     = ([options isKindOfClass:[NSDictionary class]] ? options[@"tts"] : nil);

    NSInteger timeout = timeoutN ? timeoutN.integerValue : 0;
    BOOL      warning = warningN ? warningN.boolValue : NO;
    BOOL      tts     = ttsN ? ttsN.boolValue : NO;

    if (title && [title isKindOfClass:[NSString class]] && title.length > 0)
    {
        [Utilities alert:message title:title timeout:timeout warning:warning tts:tts];
    }
    else
    {
        if (timeout == 0 && !warning && !tts)
        {
            [Utilities alert:message];
        }
        else
        {
            [Utilities alert:message title:@"Unbound" timeout:timeout warning:warning tts:tts];
        }
    }

    resolve(@(YES));
}

RCT_REMAP_METHOD(alertSimple,
                 alertSimpleMessage : (NSString *) message title : (NSString *) title resolver2 : (
                     RCTPromiseResolveBlock) resolve rejecter2 : (RCTPromiseRejectBlock) reject)
{
    if (![message isKindOfClass:[NSString class]] || message.length == 0)
    {
        reject(@"EINVAL", @"message must be a non-empty string", nil);
        return;
    }

    if ([title isKindOfClass:[NSString class]] && title.length > 0)
    {
        [Utilities alert:message title:title];
    }
    else
    {
        [Utilities alert:message];
    }

    resolve(@(YES));
}

RCT_REMAP_METHOD(echo, echo : (NSString *) text resolver : (RCTPromiseResolveBlock)
                           resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    if (text.length == 0)
    {
        reject(@"EINVAL", @"empty", nil);
        return;
    }
    resolve([@"echo:" stringByAppendingString:text]);
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(isEnabled)
{
    return @(YES);
}

#pragma mark - Utilities

RCT_REMAP_METHOD(getDeviceModel, util_getDeviceModelWithResolver : (RCTPromiseResolveBlock)
                                     resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve([Utilities getDeviceModel] ?: [NSNull null]);
}

RCT_REMAP_METHOD(getiOSVersionString,
                 util_getiOSVersionStringWithResolver : (RCTPromiseResolveBlock)
                     resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve([Utilities getiOSVersionString] ?: [NSNull null]);
}

RCT_REMAP_METHOD(isJailbroken, util_isJailbrokenWithResolver : (RCTPromiseResolveBlock)
                                   resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve(@([Utilities isJailbroken]));
}

RCT_REMAP_METHOD(isSystemApp, util_isSystemAppWithResolver : (RCTPromiseResolveBlock)
                                  resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve(@([Utilities isSystemApp]));
}

RCT_REMAP_METHOD(isVerifiedBuild, util_isVerifiedBuildWithResolver : (RCTPromiseResolveBlock)
                                      resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve(@([Utilities isVerifiedBuild]));
}

RCT_REMAP_METHOD(isAppStoreApp, util_isAppStoreAppWithResolver : (RCTPromiseResolveBlock)
                                    resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve(@([Utilities isAppStoreApp]));
}

RCT_REMAP_METHOD(isTestFlightApp, util_isTestFlightAppWithResolver : (RCTPromiseResolveBlock)
                                      resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve(@([Utilities isTestFlightApp]));
}

RCT_REMAP_METHOD(isTrollStoreApp, util_isTrollStoreAppWithResolver : (RCTPromiseResolveBlock)
                                      resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve(@([Utilities isTrollStoreApp]));
}

RCT_REMAP_METHOD(isLiveContainerApp, util_isLiveContainerAppWithResolver : (RCTPromiseResolveBlock)
                                         resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve(@([Utilities isLiveContainerApp]));
}

RCT_REMAP_METHOD(getTrollStoreVariant,
                 util_getTrollStoreVariantWithResolver : (RCTPromiseResolveBlock)
                     resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve([Utilities getTrollStoreVariant] ?: [NSNull null]);
}

RCT_REMAP_METHOD(getApplicationEntitlements,
                 util_getApplicationEntitlementsWithResolver : (RCTPromiseResolveBlock)
                     resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    NSDictionary *ent = [Utilities getApplicationEntitlements];
    resolve(ent ?: @{});
}

RCT_REMAP_METHOD(getAppSource, util_getAppSourceWithResolver : (RCTPromiseResolveBlock)
                                   resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve([Utilities getAppSource] ?: [NSNull null]);
}

RCT_REMAP_METHOD(getEntitlementsAsPlist,
                 util_getEntitlementsAsPlistWithResolver : (RCTPromiseResolveBlock)
                     resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    NSDictionary *entitlements = [Utilities getApplicationEntitlements];
    NSString     *plist        = [Utilities formatEntitlementsAsPlist:entitlements];
    resolve(plist ?: [NSNull null]);
}

RCT_REMAP_METHOD(showToolboxMenu, util_showToolboxMenuWithResolver : (RCTPromiseResolveBlock)
                                      resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [Toolbox showToolboxMenu];
        resolve([NSNull null]);
    });
}

RCT_REMAP_METHOD(showNotification,
                 plugin_showNotificationWithTitle : (NSString *) title body : (NSString *)
                     body scheduledTime : (NSNumber *) scheduledTime sound : (NSNumber *)
                         sound                                       notificationId : (NSString *)
                             notificationId resolver : (RCTPromiseResolveBlock)
                                 resolve    rejecter : (RCTPromiseRejectBlock) reject)
{
    NSString *nid =
        [PluginAPI showNotification:(title ?: @"Notification")
                               body:(body ?: @"") timeDelay:(scheduledTime ?: @(1)) soundEnabled
                                   :(sound ?: @(YES)) identifier
                                   :(notificationId ?: [[NSUUID UUID] UUIDString])];
    if (nid)
    {
        resolve(nid);
    }
    else
    {
        reject(@"E_SCHEDULE", @"Failed to schedule notification", nil);
    }
}

RCT_REMAP_METHOD(playPiPVideo,
                 plugin_playPiPVideoWithURL : (NSString *) videoURL resolver : (
                     RCTPromiseResolveBlock) resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    if (![videoURL isKindOfClass:[NSString class]] || videoURL.length == 0)
    {
        reject(@"EINVAL", @"videoURL must be a non-empty string", nil);
        return;
    }
    NSString *pid = [PluginAPI playPiPVideo:videoURL];
    if (pid)
    {
        resolve(pid);
    }
    else
    {
        reject(@"E_PIP", @"Failed to start Picture in Picture", nil);
    }
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

RCT_REMAP_METHOD(getAvatarCornerRadius,
                 chat_getAvatarCornerRadiusWithResolver : (RCTPromiseResolveBlock)
                     resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve([ChatUI getAvatarCornerRadius] ?: @(-1.0f));
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

RCT_REMAP_METHOD(getMessageBubbleLightColor,
                 chat_getMessageBubbleLightColorWithResolver : (RCTPromiseResolveBlock)
                     resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve([ChatUI getMessageBubbleLightColor] ?: [NSNull null]);
}

RCT_REMAP_METHOD(getMessageBubbleDarkColor,
                 chat_getMessageBubbleDarkColorWithResolver : (RCTPromiseResolveBlock)
                     resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve([ChatUI getMessageBubbleDarkColor] ?: [NSNull null]);
}

RCT_REMAP_METHOD(getMessageBubblesEnabled,
                 chat_getMessageBubblesEnabledWithResolver : (RCTPromiseResolveBlock)
                     resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    NSNumber *val = [ChatUI getMessageBubblesEnabled] ?: @NO;
    resolve(@(val.boolValue));
}

RCT_REMAP_METHOD(getMessageBubbleCornerRadius,
                 chat_getMessageBubbleCornerRadiusWithResolver : (RCTPromiseResolveBlock)
                     resolve rejecter : (RCTPromiseRejectBlock) reject)
{
    resolve([ChatUI getMessageBubbleCornerRadius] ?: @(10.0f));
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
