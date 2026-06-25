#import <UIKit/UIKit.h>
#import <string>

#import "ChatUI.h"
#import "Logger.h"
#import "PluginAPI.h"
#import "Toolbox.h"
#import "UnboundNative.h"
#import "Utilities.h"

using namespace facebook;
using namespace facebook::jsi;

namespace {

static constexpr const char *kInteropGlobalNameCanonical = "__unboundNative";
static constexpr const char *kInteropGlobalNameAlias     = "UnboundNative";

static std::string nsStringToStd(NSString *value)
{
    if (!value)
    {
        return std::string();
    }

    const char *utf8 = value.UTF8String;
    return utf8 ? std::string(utf8) : std::string();
}

static Value objcToJSI(Runtime &runtime, id value)
{
    if (!value || value == [NSNull null])
    {
        return Value::null();
    }

    if ([value isKindOfClass:[NSString class]])
    {
        return String::createFromUtf8(runtime, nsStringToStd((NSString *) value));
    }

    if ([value isKindOfClass:[NSNumber class]])
    {
        CFTypeID numType = CFGetTypeID((__bridge CFTypeRef) value);
        if (numType == CFBooleanGetTypeID())
        {
            return Value([(NSNumber *) value boolValue]);
        }
        return Value([(NSNumber *) value doubleValue]);
    }

    if ([value isKindOfClass:[NSArray class]])
    {
        NSArray *array = (NSArray *) value;
        Array    out(runtime, array.count);
        for (NSUInteger i = 0; i < array.count; i++)
        {
            out.setValueAtIndex(runtime, i, objcToJSI(runtime, array[i]));
        }
        return out;
    }

    if ([value isKindOfClass:[NSDictionary class]])
    {
        NSDictionary *dict = (NSDictionary *) value;
        Object        out(runtime);

        for (id key in dict)
        {
            if (![key isKindOfClass:[NSString class]])
            {
                continue;
            }

            out.setProperty(runtime, ((NSString *) key).UTF8String, objcToJSI(runtime, dict[key]));
        }

        return out;
    }

    return Value::null();
}

static NSString *jsiToNSString(Runtime &runtime, const Value &value)
{
    if (value.isString())
    {
        std::string utf8 = value.asString(runtime).utf8(runtime);
        return [NSString stringWithUTF8String:utf8.c_str() ?: ""];
    }

    return nil;
}

static bool jsiToBool(Runtime &runtime, const Value &value, bool fallback)
{
    if (value.isBool())
    {
        return value.getBool();
    }

    if (value.isNumber())
    {
        return value.getNumber() != 0;
    }

    if (value.isString())
    {
        NSString *raw = jsiToNSString(runtime, value);
        NSString *s   = [raw lowercaseString];
        if ([s isEqualToString:@"true"] || [s isEqualToString:@"1"] || [s isEqualToString:@"yes"])
        {
            return true;
        }
        if ([s isEqualToString:@"false"] || [s isEqualToString:@"0"] || [s isEqualToString:@"no"])
        {
            return false;
        }
    }

    return fallback;
}

static double jsiToNumber(const Value &value, double fallback)
{
    return value.isNumber() ? value.getNumber() : fallback;
}

static Value makeHostFn(Runtime &runtime, const char *name, unsigned int argCount,
                        const HostFunctionType &fn)
{
    return Function::createFromHostFunction(runtime, PropNameID::forUtf8(runtime, name), argCount,
                                            fn);
}

} // namespace

namespace unbound {

void registerNativeInterop(Runtime &runtime)
{
    @autoreleasepool
    {
        Object interop(runtime);

        interop.setProperty(
            runtime, "getDeviceModel",
            makeHostFn(runtime, "getDeviceModel", 0,
                       [](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                           return objcToJSI(rt, [Utilities getDeviceModel]);
                       }));

        interop.setProperty(
            runtime, "getiOSVersionString",
            makeHostFn(runtime, "getiOSVersionString", 0,
                       [](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                           return objcToJSI(rt, [Utilities getiOSVersionString]);
                       }));

        interop.setProperty(
            runtime, "isJailbroken",
            makeHostFn(runtime, "isJailbroken", 0,
                       [](Runtime &, const Value &, const Value *, size_t) -> Value {
                           return Value([Utilities isJailbroken]);
                       }));

        interop.setProperty(
            runtime, "isSystemApp",
            makeHostFn(runtime, "isSystemApp", 0,
                       [](Runtime &, const Value &, const Value *, size_t) -> Value {
                           return Value([Utilities isSystemApp]);
                       }));

        interop.setProperty(
            runtime, "isVerifiedBuild",
            makeHostFn(runtime, "isVerifiedBuild", 0,
                       [](Runtime &, const Value &, const Value *, size_t) -> Value {
                           return Value([Utilities isVerifiedBuild]);
                       }));

        interop.setProperty(
            runtime, "getApplicationEntitlements",
            makeHostFn(runtime, "getApplicationEntitlements", 0,
                       [](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                           return objcToJSI(rt, [Utilities getApplicationEntitlements] ?: @{});
                       }));

        interop.setProperty(
            runtime, "getAppSource",
            makeHostFn(runtime, "getAppSource", 0,
                       [](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                           return objcToJSI(rt, [Utilities getAppSource]);
                       }));

        interop.setProperty(
            runtime, "getEntitlementsAsPlist",
            makeHostFn(runtime, "getEntitlementsAsPlist", 0,
                       [](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                           NSDictionary *entitlements = [Utilities getApplicationEntitlements];
                           NSString     *plist = [Utilities formatEntitlementsAsPlist:entitlements];
                           return objcToJSI(rt, plist);
                       }));

        interop.setProperty(
            runtime, "showNotification",
            makeHostFn(runtime, "showNotification", 5,
                       [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
                           NSString *title = (count > 0) ? jsiToNSString(rt, args[0]) : nil;
                           NSString *body  = (count > 1) ? jsiToNSString(rt, args[1]) : nil;
                           NSNumber *scheduledTime =
                               (count > 2 && args[2].isNumber()) ? @(args[2].getNumber()) : @(1);
                           NSNumber *soundEnabled =
                               (count > 3) ? @(jsiToBool(rt, args[3], true)) : @(YES);
                           NSString *notificationId =
                               (count > 4) ? jsiToNSString(rt, args[4]) : nil;

                           NSString *nid = [PluginAPI
                               showNotification:(title ?: @"Notification")
                                           body:(body ?: @"") timeDelay:scheduledTime
                                   soundEnabled:soundEnabled
                                     identifier:(notificationId ?: [[NSUUID UUID] UUIDString])];

                           return objcToJSI(rt, nid);
                       }));

        interop.setProperty(
            runtime, "playPiPVideo",
            makeHostFn(runtime, "playPiPVideo", 1,
                       [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
                           NSString *videoURL = (count > 0) ? jsiToNSString(rt, args[0]) : nil;
                           if (!videoURL || videoURL.length == 0)
                           {
                               return Value::null();
                           }

                           NSString *pid = [PluginAPI playPiPVideo:videoURL];
                           return objcToJSI(rt, pid);
                       }));

        interop.setProperty(
            runtime, "getAvatarCornerRadius",
            makeHostFn(runtime, "getAvatarCornerRadius", 0,
                       [](Runtime &, const Value &, const Value *, size_t) -> Value {
                           NSNumber *v = [ChatUI getAvatarCornerRadius] ?: @(-1.0);
                           return Value(v.doubleValue);
                       }));

        interop.setProperty(
            runtime, "getMessageBubbleLightColor",
            makeHostFn(runtime, "getMessageBubbleLightColor", 0,
                       [](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                           return objcToJSI(rt, [ChatUI getMessageBubbleLightColor]);
                       }));

        interop.setProperty(
            runtime, "getMessageBubbleDarkColor",
            makeHostFn(runtime, "getMessageBubbleDarkColor", 0,
                       [](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                           return objcToJSI(rt, [ChatUI getMessageBubbleDarkColor]);
                       }));

        interop.setProperty(
            runtime, "getMessageBubblesEnabled",
            makeHostFn(runtime, "getMessageBubblesEnabled", 0,
                       [](Runtime &, const Value &, const Value *, size_t) -> Value {
                           NSNumber *v = [ChatUI getMessageBubblesEnabled] ?: @NO;
                           return Value(v.boolValue);
                       }));

        interop.setProperty(
            runtime, "getMessageBubbleCornerRadius",
            makeHostFn(runtime, "getMessageBubbleCornerRadius", 0,
                       [](Runtime &, const Value &, const Value *, size_t) -> Value {
                           NSNumber *v = [ChatUI getMessageBubbleCornerRadius] ?: @(10.0);
                           return Value(v.doubleValue);
                       }));

        interop.setProperty(
            runtime, "showToolboxMenu",
            makeHostFn(runtime, "showToolboxMenu", 0,
                       [](Runtime &, const Value &, const Value *, size_t) -> Value {
                           dispatch_async(dispatch_get_main_queue(),
                                          ^{ [Toolbox showToolboxMenu]; });
                           return Value::undefined();
                       }));

        interop.setProperty(
            runtime, "setAvatarCornerRadius",
            makeHostFn(runtime, "setAvatarCornerRadius", 1,
                       [](Runtime &, const Value &, const Value *args, size_t count) -> Value {
                           double radius = (count > 0) ? jsiToNumber(args[0], 0.0) : 0.0;
                           dispatch_async(dispatch_get_main_queue(),
                                          ^{ [ChatUI setAvatarCornerRadius:@(radius)]; });
                           return Value::undefined();
                       }));

        interop.setProperty(
            runtime, "resetAvatarCornerRadius",
            makeHostFn(runtime, "resetAvatarCornerRadius", 0,
                       [](Runtime &, const Value &, const Value *, size_t) -> Value {
                           dispatch_async(dispatch_get_main_queue(),
                                          ^{ [ChatUI resetAvatarCornerRadius]; });
                           return Value::undefined();
                       }));

        interop.setProperty(
            runtime, "setMessageBubblesEnabled",
            makeHostFn(runtime, "setMessageBubblesEnabled", 3,
                       [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
                           bool      enabled = (count > 0) ? jsiToBool(rt, args[0], false) : false;
                           NSString *lightColor = (count > 1) ? jsiToNSString(rt, args[1]) : nil;
                           NSString *darkColor  = (count > 2) ? jsiToNSString(rt, args[2]) : nil;

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
                       }));

        interop.setProperty(
            runtime, "setMessageBubbleColors",
            makeHostFn(runtime, "setMessageBubbleColors", 2,
                       [](Runtime &rt, const Value &, const Value *args, size_t count) -> Value {
                           NSString *lightColor = (count > 0) ? jsiToNSString(rt, args[0]) : nil;
                           NSString *darkColor  = (count > 1) ? jsiToNSString(rt, args[1]) : nil;

                           dispatch_async(dispatch_get_main_queue(), ^{
                               [ChatUI setMessageBubbleColors:(lightColor ?: @"")
                                                    darkColor:(darkColor ?: @"")];
                           });

                           return Value::undefined();
                       }));

        interop.setProperty(
            runtime, "setMessageBubbleCornerRadius",
            makeHostFn(runtime, "setMessageBubbleCornerRadius", 1,
                       [](Runtime &, const Value &, const Value *args, size_t count) -> Value {
                           double radius = (count > 0) ? jsiToNumber(args[0], 10.0) : 10.0;
                           dispatch_async(dispatch_get_main_queue(),
                                          ^{ [ChatUI setMessageBubbleCornerRadius:@(radius)]; });
                           return Value::undefined();
                       }));

        interop.setProperty(
            runtime, "resetMessageBubbles",
            makeHostFn(runtime, "resetMessageBubbles", 0,
                       [](Runtime &, const Value &, const Value *, size_t) -> Value {
                           dispatch_async(dispatch_get_main_queue(),
                                          ^{ [ChatUI resetMessageBubbles]; });
                           return Value::undefined();
                       }));

        // Install on the internal canonical name, then expose a public alias
        // to preserve existing JS call sites.
        runtime.global().setProperty(runtime, kInteropGlobalNameCanonical, std::move(interop));

        Value interopValue = runtime.global().getProperty(runtime, kInteropGlobalNameCanonical);
        runtime.global().setProperty(runtime, kInteropGlobalNameAlias, interopValue);

        [Logger info:LOG_CATEGORY_DEFAULT format:@"Installed bridgeless native interop"];
    }
}

} // namespace unbound
