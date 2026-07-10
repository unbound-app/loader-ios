#import "UnboundNative.h"

using namespace facebook;
using namespace facebook::jsi;

namespace {

static constexpr const char *kInteropGlobalName   = "UnboundNative";
static NSString *const       kNativeModuleVersion = @"1.0.0";

static NSString *semverStringFromMetadataValue(id value)
{
    if ([value isKindOfClass:[NSString class]])
    {
        return (NSString *) value;
    }

    return nil;
}

static NSArray<NSNumber *> *semverComponents(NSString *version)
{
    if (![version isKindOfClass:[NSString class]] || version.length == 0)
    {
        return nil;
    }

    NSArray<NSString *> *parts = [version componentsSeparatedByString:@"."];
    if (parts.count != 3)
    {
        return nil;
    }

    NSCharacterSet             *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSMutableArray<NSNumber *> *components = [NSMutableArray arrayWithCapacity:3];
    for (NSString *part in parts)
    {
        if (part.length == 0 || [part rangeOfCharacterFromSet:nonDigits].location != NSNotFound)
        {
            return nil;
        }

        [components addObject:@(part.integerValue)];
    }

    return components;
}

static NSInteger compareSemver(NSString *a, NSString *b)
{
    NSArray<NSNumber *> *lhs = semverComponents(a);
    NSArray<NSNumber *> *rhs = semverComponents(b);

    if (!lhs && !rhs)
    {
        return 0;
    }
    if (!lhs)
    {
        return -1;
    }
    if (!rhs)
    {
        return 1;
    }

    for (NSUInteger i = 0; i < 3; i++)
    {
        NSInteger l = lhs[i].integerValue;
        NSInteger r = rhs[i].integerValue;
        if (l < r)
        {
            return -1;
        }
        if (l > r)
        {
            return 1;
        }
    }

    return 0;
}

static NSDictionary<NSString *, NSDictionary<NSString *, id> *> *nativeFeatureMetadata(void)
{
    static NSDictionary<NSString *, NSDictionary<NSString *, id> *> *features;
    static dispatch_once_t                                           onceToken;
    dispatch_once(&onceToken, ^{
        features = @{
            @"device.info" : @{@"introduced" : @"1.0.0"},
            @"device.entitlements" : @{@"introduced" : @"1.0.0"},
            @"app.source" : @{@"introduced" : @"1.0.0"},
            @"notifications" : @{@"introduced" : @"1.0.0"},
            @"pip.video" : @{@"introduced" : @"1.0.0"},
            @"chat.avatar" : @{@"introduced" : @"1.0.0"},
            @"chat.messageBubbles" : @{@"introduced" : @"1.0.0"},
            @"toolbox.menu" : @{@"introduced" : @"1.0.0"},
        };
    });
    return features;
}

static NSDictionary<NSString *, id> *nativeFeatureInfo(NSString *featureName)
{
    return nativeFeatureMetadata()[featureName];
}

static BOOL isFeatureKnown(NSString *featureName)
{
    return nativeFeatureInfo(featureName) != nil;
}

static BOOL isNativeFeatureRemoved(NSString *featureName)
{
    NSDictionary<NSString *, id> *info = nativeFeatureInfo(featureName);
    NSString *removedInVersion         = semverStringFromMetadataValue(info[@"removed"]);
    if (!removedInVersion)
    {
        return NO;
    }

    return compareSemver(kNativeModuleVersion, removedInVersion) >= 0;
}

static BOOL isNativeFeatureDeprecated(NSString *featureName)
{
    NSDictionary<NSString *, id> *info = nativeFeatureInfo(featureName);
    NSString *deprecatedInVersion      = semverStringFromMetadataValue(info[@"deprecated"]);
    if (!deprecatedInVersion)
    {
        return NO;
    }

    return compareSemver(kNativeModuleVersion, deprecatedInVersion) >= 0 &&
           !isNativeFeatureRemoved(featureName);
}

static BOOL supportsNativeFeature(NSString *featureName)
{
    if (![featureName isKindOfClass:[NSString class]] || featureName.length == 0)
    {
        return NO;
    }

    NSDictionary<NSString *, id> *info = nativeFeatureInfo(featureName);
    NSString *introducedInVersion      = semverStringFromMetadataValue(info[@"introduced"]);
    if (!introducedInVersion)
    {
        return NO;
    }

    if (isNativeFeatureRemoved(featureName))
    {
        return NO;
    }

    return compareSemver(kNativeModuleVersion, introducedInVersion) >= 0;
}

static NSString *nativeFeatureStatus(NSString *featureName)
{
    if (!isFeatureKnown(featureName))
    {
        return @"unknown";
    }
    if (isNativeFeatureRemoved(featureName))
    {
        return @"removed";
    }
    if (isNativeFeatureDeprecated(featureName))
    {
        return @"deprecated";
    }
    if (supportsNativeFeature(featureName))
    {
        return @"supported";
    }
    return @"unavailable";
}

static NSDictionary<NSString *, id> *exportedNativeFeatureInfo(NSString *featureName)
{
    NSDictionary<NSString *, id> *info = nativeFeatureInfo(featureName);
    if (!info)
    {
        return @{@"name" : (featureName ?: @""), @"known" : @NO, @"status" : @"unknown"};
    }

    NSMutableDictionary<NSString *, id> *out = [NSMutableDictionary dictionary];
    out[@"name"]                             = featureName;
    out[@"known"]                            = @YES;
    out[@"status"]                           = nativeFeatureStatus(featureName);
    out[@"supported"]                        = @(supportsNativeFeature(featureName));
    out[@"introducedIn"]                     = info[@"introduced"];
    if (info[@"deprecated"])
    {
        out[@"deprecatedIn"] = info[@"deprecated"];
    }
    if (info[@"removed"])
    {
        out[@"removedIn"] = info[@"removed"];
    }
    if (info[@"replacement"])
    {
        out[@"replacement"] = info[@"replacement"];
    }

    return out;
}

static NSArray<NSString *> *featureNamesForStatus(NSString *status)
{
    NSMutableArray<NSString *> *features = [NSMutableArray array];
    for (NSString *featureName in nativeFeatureMetadata())
    {
        if ([nativeFeatureStatus(featureName) isEqualToString:status])
        {
            [features addObject:featureName];
        }
    }

    return [features sortedArrayUsingSelector:@selector(compare:)];
}

}

namespace unbound {

void registerNativeInterop(Runtime &runtime)
{
    @autoreleasepool
    {
        Object interop(runtime);


        interop.setProperty(
            runtime, "getNativeModuleVersion",
            [JSI makeFunction:"getNativeModuleVersion"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                          return [JSI fromObjC:kNativeModuleVersion runtime:rt];
                      }]);

        interop.setProperty(runtime, "supportsFeature",
                            [JSI makeFunction:"supportsFeature"
                                     argCount:1
                                      runtime:runtime
                                      handler:[](Runtime &rt, const Value &, const Value *args,
                                                 size_t count) -> Value {
                                          NSString *featureName =
                                              (count > 0) ? [JSI toNSString:args[0] runtime:rt]
                                                          : nil;
                                          return Value(supportsNativeFeature(featureName));
                                      }]);

        interop.setProperty(
            runtime, "getFeatureInfo",
            [JSI makeFunction:"getFeatureInfo"
                     argCount:1
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *args,
                                 size_t count) -> Value {
                          NSString *featureName =
                              (count > 0) ? [JSI toNSString:args[0] runtime:rt] : nil;
                          return [JSI fromObjC:exportedNativeFeatureInfo(featureName) runtime:rt];
                      }]);

        interop.setProperty(runtime, "isFeatureDeprecated",
                            [JSI makeFunction:"isFeatureDeprecated"
                                     argCount:1
                                      runtime:runtime
                                      handler:[](Runtime &rt, const Value &, const Value *args,
                                                 size_t count) -> Value {
                                          NSString *featureName =
                                              (count > 0) ? [JSI toNSString:args[0] runtime:rt]
                                                          : nil;
                                          return Value(isNativeFeatureDeprecated(featureName));
                                      }]);

        interop.setProperty(runtime, "isFeatureRemoved",
                            [JSI makeFunction:"isFeatureRemoved"
                                     argCount:1
                                      runtime:runtime
                                      handler:[](Runtime &rt, const Value &, const Value *args,
                                                 size_t count) -> Value {
                                          NSString *featureName =
                                              (count > 0) ? [JSI toNSString:args[0] runtime:rt]
                                                          : nil;
                                          return Value(isNativeFeatureRemoved(featureName));
                                      }]);

        interop.setProperty(
            runtime, "getSupportedFeatures",
            [JSI makeFunction:"getSupportedFeatures"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                          NSArray<NSString *> *features = featureNamesForStatus(@"supported");
                          return [JSI fromObjC:features runtime:rt];
                      }]);

        interop.setProperty(
            runtime, "getDeprecatedFeatures",
            [JSI makeFunction:"getDeprecatedFeatures"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                          return [JSI fromObjC:featureNamesForStatus(@"deprecated") runtime:rt];
                      }]);

        interop.setProperty(
            runtime, "getRemovedFeatures",
            [JSI makeFunction:"getRemovedFeatures"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                          return [JSI fromObjC:featureNamesForStatus(@"removed") runtime:rt];
                      }]);


        {
            Object device(runtime);

            device.setProperty(
                runtime, "getModel",
                [JSI makeFunction:"getModel"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                              return [JSI fromObjC:[Utilities getDeviceModel] runtime:rt];
                          }]);

            device.setProperty(
                runtime, "getiOSVersionString",
                [JSI makeFunction:"getiOSVersionString"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                              return [JSI fromObjC:[Utilities getiOSVersionString] runtime:rt];
                          }]);

            device.setProperty(
                runtime, "isJailbroken",
                [JSI makeFunction:"isJailbroken"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                              return Value([Utilities isJailbroken]);
                          }]);

            device.setProperty(
                runtime, "isSystemApp",
                [JSI makeFunction:"isSystemApp"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                              return Value([Utilities isSystemApp]);
                          }]);

            device.setProperty(
                runtime, "isVerifiedBuild",
                [JSI makeFunction:"isVerifiedBuild"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                              return Value([Utilities isVerifiedBuild]);
                          }]);

            device.setProperty(
                runtime, "getEntitlements",
                [JSI makeFunction:"getEntitlements"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                              return [JSI fromObjC:[Utilities getApplicationEntitlements] ?: @{}
                                           runtime:rt];
                          }]);

            device.setProperty(
                runtime, "getEntitlementsAsPlist",
                [JSI makeFunction:"getEntitlementsAsPlist"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                              NSDictionary *entitlements = [Utilities getApplicationEntitlements];
                              NSString *plist = [Utilities formatEntitlementsAsPlist:entitlements];
                              return [JSI fromObjC:plist runtime:rt];
                          }]);

            interop.setProperty(runtime, "device", std::move(device));
        }


        {
            Object app(runtime);

            app.setProperty(
                runtime, "getSource",
                [JSI makeFunction:"getSource"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                              return [JSI fromObjC:[Utilities getAppSource] runtime:rt];
                          }]);

            interop.setProperty(runtime, "app", std::move(app));
        }


        {
            Object notifications(runtime);

            notifications.setProperty(
                runtime, "show",
                [JSI makeFunction:"show"
                         argCount:5
                          runtime:runtime
                          handler:[](Runtime &rt, const Value &, const Value *args,
                                     size_t count) -> Value {
                              NSString *title = (count > 0) ? [JSI toNSString:args[0] runtime:rt]
                                                            : nil;
                              NSString *body  = (count > 1) ? [JSI toNSString:args[1] runtime:rt]
                                                            : nil;
                              NSNumber *scheduledTime =
                                  (count > 2 && args[2].isNumber()) ? @(args[2].getNumber()) : @(1);
                              NSNumber *soundEnabled =
                                  (count > 3)
                                      ? @([JSI toBool:args[3] runtime:rt fallback:YES])
                                      : @(YES);
                              NSString *notificationId =
                                  (count > 4) ? [JSI toNSString:args[4] runtime:rt] : nil;

                              NSString *nid = [PluginAPI
                                  showNotification:(title ?: @"Notification")
                                              body:(body ?: @"")
                                         timeDelay:scheduledTime
                                      soundEnabled:soundEnabled
                                        identifier:(notificationId ?: [[NSUUID UUID] UUIDString])];

                              return [JSI fromObjC:nid runtime:rt];
                          }]);

            interop.setProperty(runtime, "notifications", std::move(notifications));
        }


        {
            Object pip(runtime);

            pip.setProperty(runtime, "playVideo",
                            [JSI makeFunction:"playVideo"
                                     argCount:1
                                      runtime:runtime
                                      handler:[](Runtime &rt, const Value &, const Value *args,
                                                 size_t count) -> Value {
                                          NSString *videoURL =
                                              (count > 0) ? [JSI toNSString:args[0] runtime:rt]
                                                          : nil;
                                          if (!videoURL || videoURL.length == 0)
                                          {
                                              return Value::null();
                                          }

                                          NSString *pid = [PluginAPI playPiPVideo:videoURL];
                                          return [JSI fromObjC:pid runtime:rt];
                                      }]);

            interop.setProperty(runtime, "pip", std::move(pip));
        }


        {
            Object chat(runtime);

            chat.setProperty(
                runtime, "getAvatarCornerRadius",
                [JSI makeFunction:"getAvatarCornerRadius"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                              NSNumber *v = [ChatUI getAvatarCornerRadius] ?: @(-1.0);
                              return Value(v.doubleValue);
                          }]);

            chat.setProperty(
                runtime, "setAvatarCornerRadius",
                [JSI makeFunction:"setAvatarCornerRadius"
                         argCount:1
                          runtime:runtime
                          handler:[](Runtime &, const Value &, const Value *args,
                                     size_t count) -> Value {
                              double radius =
                                  (count > 0) ? [JSI toNumber:args[0] fallback:0.0] : 0.0;
                              dispatch_async(dispatch_get_main_queue(),
                                             ^{ [ChatUI setAvatarCornerRadius:@(radius)]; });
                              return Value::undefined();
                          }]);

            chat.setProperty(
                runtime, "resetAvatarCornerRadius",
                [JSI makeFunction:"resetAvatarCornerRadius"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                              dispatch_async(dispatch_get_main_queue(),
                                             ^{ [ChatUI resetAvatarCornerRadius]; });
                              return Value::undefined();
                          }]);

            chat.setProperty(
                runtime, "getMessageBubbleLightColor",
                [JSI makeFunction:"getMessageBubbleLightColor"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                              return [JSI fromObjC:[ChatUI getMessageBubbleLightColor] runtime:rt];
                          }]);

            chat.setProperty(
                runtime, "getMessageBubbleDarkColor",
                [JSI makeFunction:"getMessageBubbleDarkColor"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                              return [JSI fromObjC:[ChatUI getMessageBubbleDarkColor] runtime:rt];
                          }]);

            chat.setProperty(
                runtime, "getMessageBubblesEnabled",
                [JSI makeFunction:"getMessageBubblesEnabled"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                              NSNumber *v = [ChatUI getMessageBubblesEnabled] ?: @NO;
                              return Value(v.boolValue);
                          }]);

            chat.setProperty(
                runtime, "getMessageBubbleCornerRadius",
                [JSI makeFunction:"getMessageBubbleCornerRadius"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                              NSNumber *v = [ChatUI getMessageBubbleCornerRadius] ?: @(10.0);
                              return Value(v.doubleValue);
                          }]);

            chat.setProperty(
                runtime, "setMessageBubblesEnabled",
                [JSI makeFunction:"setMessageBubblesEnabled"
                         argCount:3
                          runtime:runtime
                          handler:[](Runtime &rt, const Value &, const Value *args,
                                     size_t count) -> Value {
                              bool enabled =
                                  (count > 0) ? [JSI toBool:args[0] runtime:rt fallback:NO] : false;
                              NSString *lightColor =
                                  (count > 1) ? [JSI toNSString:args[1] runtime:rt] : nil;
                              NSString *darkColor =
                                  (count > 2) ? [JSI toNSString:args[2] runtime:rt] : nil;

                              dispatch_async(dispatch_get_main_queue(), ^{
                                  if (lightColor || darkColor)
                                  {
                                      [ChatUI setMessageBubblesEnabled:@(enabled)
                                                            lightColor:lightColor
                                                             darkColor:darkColor];
                                  }
                                  else
                                  {
                                      [ChatUI setMessageBubblesEnabled:@(enabled)];
                                  }
                              });

                              return Value::undefined();
                          }]);

            chat.setProperty(
                runtime, "setMessageBubbleColors",
                [JSI makeFunction:"setMessageBubbleColors"
                         argCount:2
                          runtime:runtime
                          handler:[](Runtime &rt, const Value &, const Value *args,
                                     size_t count) -> Value {
                              NSString *lightColor =
                                  (count > 0) ? [JSI toNSString:args[0] runtime:rt] : nil;
                              NSString *darkColor =
                                  (count > 1) ? [JSI toNSString:args[1] runtime:rt] : nil;

                              dispatch_async(dispatch_get_main_queue(), ^{
                                  [ChatUI setMessageBubbleColors:(lightColor ?: @"")
                                                       darkColor:(darkColor ?: @"")];
                              });

                              return Value::undefined();
                          }]);

            chat.setProperty(
                runtime, "setMessageBubbleCornerRadius",
                [JSI makeFunction:"setMessageBubbleCornerRadius"
                         argCount:1
                          runtime:runtime
                          handler:[](Runtime &, const Value &, const Value *args,
                                     size_t count) -> Value {
                              double radius =
                                  (count > 0) ? [JSI toNumber:args[0] fallback:10.0] : 10.0;
                              dispatch_async(dispatch_get_main_queue(),
                                             ^{ [ChatUI setMessageBubbleCornerRadius:@(radius)]; });
                              return Value::undefined();
                          }]);

            chat.setProperty(
                runtime, "resetMessageBubbles",
                [JSI makeFunction:"resetMessageBubbles"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                              dispatch_async(dispatch_get_main_queue(),
                                             ^{ [ChatUI resetMessageBubbles]; });
                              return Value::undefined();
                          }]);

            interop.setProperty(runtime, "chat", std::move(chat));
        }


        {
            Object toolbox(runtime);

            toolbox.setProperty(
                runtime, "showMenu",
                [JSI makeFunction:"showMenu"
                         argCount:0
                          runtime:runtime
                          handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                              dispatch_async(dispatch_get_main_queue(),
                                             ^{ [Toolbox showToolboxMenu]; });
                              return Value::undefined();
                          }]);

            interop.setProperty(runtime, "toolbox", std::move(toolbox));
        }

        runtime.global().setProperty(runtime, kInteropGlobalName, std::move(interop));

        [Logger info:LOG_CATEGORY_DEFAULT format:@"Installed window.UnboundNative"];
    }
}

}
