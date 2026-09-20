#import "NativePlatform.h"

#import "JSI.h"
#import "PluginAPI.h"
#import "Utilities.h"

using namespace facebook;
using namespace facebook::jsi;

namespace unbound {

void registerNativePlatform(Runtime &runtime)
{
    @autoreleasepool
    {
        Object platform(runtime);

        platform.setProperty(
            runtime, "evaluateBytecode",
            [JSI makeFunction:"evaluateBytecode"
                     argCount:2
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *args,
                                 size_t count) -> Value {
                          if (count == 0 || !args[0].isObject() ||
                              !args[0].asObject(rt).isArrayBuffer(rt))
                          {
                              throw JSError(
                                  rt,
                                  "evaluateBytecode expects an ArrayBuffer of Hermes bytecode as "
                                  "its first argument");
                          }

                          ArrayBuffer arrayBuffer = args[0].asObject(rt).getArrayBuffer(rt);
                          NSData     *bytecodeData =
                              [NSData dataWithBytes:arrayBuffer.data(rt)
                                             length:arrayBuffer.size(rt)];
                          NSString *tag = (count > 1) ? [JSI toNSString:args[1] runtime:rt] : nil;

                          return [JSI evaluateBytecode:bytecodeData
                                                    tag:(tag ?: @"UnboundPlatform.evaluateBytecode")
                                                runtime:rt];
                      }]);

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

        platform.setProperty(runtime, "device", std::move(device));

        Object app(runtime);

        app.setProperty(
            runtime, "getSource",
            [JSI makeFunction:"getSource"
                     argCount:0
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *, size_t) -> Value {
                          return [JSI fromObjC:[Utilities getAppSource] runtime:rt];
                      }]);

        platform.setProperty(runtime, "app", std::move(app));

        Object notifications(runtime);

        notifications.setProperty(
            runtime, "show",
            [JSI makeFunction:"show"
                     argCount:5
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *args,
                                 size_t count) -> Value {
                          NSString *title = (count > 0) ? [JSI toNSString:args[0] runtime:rt] : nil;
                          NSString *body = (count > 1) ? [JSI toNSString:args[1] runtime:rt] : nil;
                          NSNumber *scheduledTime =
                              (count > 2 && args[2].isNumber()) ? @(args[2].getNumber()) : @(1);
                          NSNumber *soundEnabled =
                              (count > 3) ? @([JSI toBool:args[3] runtime:rt fallback:YES]) : @(YES);
                          NSString *notificationId =
                              (count > 4) ? [JSI toNSString:args[4] runtime:rt] : nil;
                          NSString *identifier = [PluginAPI
                              showNotification:(title ?: @"Notification")
                                          body:(body ?: @"")
                                     timeDelay:scheduledTime
                                  soundEnabled:soundEnabled
                                    identifier:(notificationId ?: [[NSUUID UUID] UUIDString])];
                          return [JSI fromObjC:identifier runtime:rt];
                      }]);

        platform.setProperty(runtime, "notifications", std::move(notifications));

        Object pip(runtime);

        pip.setProperty(
            runtime, "playVideo",
            [JSI makeFunction:"playVideo"
                     argCount:1
                      runtime:runtime
                      handler:[](Runtime &rt, const Value &, const Value *args,
                                 size_t count) -> Value {
                          NSString *videoURL =
                              (count > 0) ? [JSI toNSString:args[0] runtime:rt] : nil;
                          if (!videoURL || videoURL.length == 0)
                          {
                              return Value::null();
                          }

                          NSString *pid = [PluginAPI playPiPVideo:videoURL];
                          return [JSI fromObjC:pid runtime:rt];
                      }]);

        platform.setProperty(runtime, "pip", std::move(pip));
        runtime.global().setProperty(runtime, "UnboundPlatform", std::move(platform));
    }
}

}
