#import <UIKit/UIKit.h>

#import "ChatUI.h"
#import "JSI.h"
#import "Logger.h"
#import "PluginAPI.h"
#import "Toolbox.h"
#import "UnboundNative.h"
#import "Utilities.h"

using namespace facebook;
using namespace facebook::jsi;

namespace {

static constexpr const char *kInteropGlobalName = "UnboundNative";

} // namespace

namespace unbound {

void registerNativeInterop(Runtime &runtime)
{
    @autoreleasepool
    {
        Object interop(runtime);

        interop.setProperty(
            runtime, "getDeviceModel",
            [JSI makeFunction:"getDeviceModel"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                          return [JSI fromObjC:[Utilities getDeviceModel] runtime:rt];
                      }]);

        interop.setProperty(
            runtime, "getiOSVersionString",
            [JSI makeFunction:"getiOSVersionString"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                          return [JSI fromObjC:[Utilities getiOSVersionString] runtime:rt];
                      }]);

        interop.setProperty(
            runtime, "isJailbroken",
            [JSI makeFunction:"isJailbroken"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                          return Value([Utilities isJailbroken]);
                      }]);

        interop.setProperty(
            runtime, "isSystemApp",
            [JSI makeFunction:"isSystemApp"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                          return Value([Utilities isSystemApp]);
                      }]);

        interop.setProperty(
            runtime, "isVerifiedBuild",
            [JSI makeFunction:"isVerifiedBuild"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                          return Value([Utilities isVerifiedBuild]);
                      }]);

        interop.setProperty(
            runtime, "getApplicationEntitlements",
            [JSI makeFunction:"getApplicationEntitlements"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                          return [JSI fromObjC:[Utilities getApplicationEntitlements] ?: @{}
                                       runtime:rt];
                      }]);

        interop.setProperty(
            runtime, "getAppSource",
            [JSI makeFunction:"getAppSource"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                          return [JSI fromObjC:[Utilities getAppSource] runtime:rt];
                      }]);

        interop.setProperty(
            runtime, "getEntitlementsAsPlist",
            [JSI makeFunction:"getEntitlementsAsPlist"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                          NSDictionary *entitlements = [Utilities getApplicationEntitlements];
                          NSString     *plist = [Utilities formatEntitlementsAsPlist:entitlements];
                          return [JSI fromObjC:plist runtime:rt];
                      }]);

        interop.setProperty(
            runtime, "showNotification",
            [JSI makeFunction:"showNotification"
                     argCount:5
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *args,
                                 size_t count) -> Value {
                          NSString *title = (count > 0) ? [JSI toNSString:args[0] runtime:rt] : nil;
                          NSString *body  = (count > 1) ? [JSI toNSString:args[1] runtime:rt] : nil;
                          NSNumber *scheduledTime =
                              (count > 2 && args[2].isNumber()) ? @(args[2].getNumber()) : @(1);
                          NSNumber *soundEnabled = (count > 3) ? @([JSI toBool:args[3]
                                                                       runtime:rt
                                                                      fallback:YES])
                                                               : @(YES);
                          NSString *notificationId =
                              (count > 4) ? [JSI toNSString:args[4] runtime:rt] : nil;

                          NSString *nid = [PluginAPI
                              showNotification:(title ?: @"Notification")
                                          body:(body ?: @"") timeDelay:scheduledTime
                                  soundEnabled:soundEnabled
                                    identifier:(notificationId ?: [[NSUUID UUID] UUIDString])];

                          return [JSI fromObjC:nid runtime:rt];
                      }]);

        interop.setProperty(runtime, "playPiPVideo",
                            [JSI makeFunction:"playPiPVideo"
                                     argCount:1
                                      runtime:runtime
                                      handler:[](Runtime &rt, const Value &, const Value *args,
                                                 size_t count) -> Value {
                                          NSString *videoURL = (count > 0) ? [JSI toNSString:args[0]
                                                                                     runtime:rt]
                                                                           : nil;
                                          if (!videoURL || videoURL.length == 0)
                                          {
                                              return Value::null();
                                          }

                                          NSString *pid = [PluginAPI playPiPVideo:videoURL];
                                          return [JSI fromObjC:pid runtime:rt];
                                      }]);

        interop.setProperty(
            runtime, "getAvatarCornerRadius",
            [JSI makeFunction:"getAvatarCornerRadius"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                          NSNumber *v = [ChatUI getAvatarCornerRadius] ?: @(-1.0);
                          return Value(v.doubleValue);
                      }]);

        interop.setProperty(
            runtime, "getMessageBubbleLightColor",
            [JSI makeFunction:"getMessageBubbleLightColor"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                          return [JSI fromObjC:[ChatUI getMessageBubbleLightColor] runtime:rt];
                      }]);

        interop.setProperty(
            runtime, "getMessageBubbleDarkColor",
            [JSI makeFunction:"getMessageBubbleDarkColor"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                          return [JSI fromObjC:[ChatUI getMessageBubbleDarkColor] runtime:rt];
                      }]);

        interop.setProperty(
            runtime, "getMessageBubblesEnabled",
            [JSI makeFunction:"getMessageBubblesEnabled"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                          NSNumber *v = [ChatUI getMessageBubblesEnabled] ?: @NO;
                          return Value(v.boolValue);
                      }]);

        interop.setProperty(
            runtime, "getMessageBubbleCornerRadius",
            [JSI makeFunction:"getMessageBubbleCornerRadius"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                          NSNumber *v = [ChatUI getMessageBubbleCornerRadius] ?: @(10.0);
                          return Value(v.doubleValue);
                      }]);

        interop.setProperty(
            runtime, "showToolboxMenu",
            [JSI makeFunction:"showToolboxMenu"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                          dispatch_async(dispatch_get_main_queue(),
                                         ^{ [Toolbox showToolboxMenu]; });
                          return Value::undefined();
                      }]);

        interop.setProperty(
            runtime, "setAvatarCornerRadius",
            [JSI makeFunction:"setAvatarCornerRadius"
                     argCount:1
                      runtime:runtime
                      handler:[](Runtime &, const Value &, const Value *args,
                                 size_t count) -> Value {
                          double radius = (count > 0) ? [JSI toNumber:args[0] fallback:0.0] : 0.0;
                          dispatch_async(dispatch_get_main_queue(),
                                         ^{ [ChatUI setAvatarCornerRadius:@(radius)]; });
                          return Value::undefined();
                      }]);

        interop.setProperty(
            runtime, "resetAvatarCornerRadius",
            [JSI makeFunction:"resetAvatarCornerRadius"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                          dispatch_async(dispatch_get_main_queue(),
                                         ^{ [ChatUI resetAvatarCornerRadius]; });
                          return Value::undefined();
                      }]);

        interop.setProperty(
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

        interop.setProperty(
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

        interop.setProperty(
            runtime, "setMessageBubbleCornerRadius",
            [JSI makeFunction:"setMessageBubbleCornerRadius"
                     argCount:1
                      runtime:runtime
                      handler:[](Runtime &, const Value &, const Value *args,
                                 size_t count) -> Value {
                          double radius = (count > 0) ? [JSI toNumber:args[0] fallback:10.0] : 10.0;
                          dispatch_async(dispatch_get_main_queue(),
                                         ^{ [ChatUI setMessageBubbleCornerRadius:@(radius)]; });
                          return Value::undefined();
                      }]);

        interop.setProperty(
            runtime, "resetMessageBubbles",
            [JSI makeFunction:"resetMessageBubbles"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &, const Value &, const Value *, size_t) -> Value {
                          dispatch_async(dispatch_get_main_queue(),
                                         ^{ [ChatUI resetMessageBubbles]; });
                          return Value::undefined();
                      }]);

        // Define directly on the JS global as window.UnboundNative.
        runtime.global().setProperty(runtime, kInteropGlobalName, std::move(interop));

        [Logger info:LOG_CATEGORY_DEFAULT format:@"Installed window.UnboundNative"];
    }
}

} // namespace unbound
