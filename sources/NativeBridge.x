#import "NativeBridge.h"

@implementation NativeBridge

+ (id)callNativeMethod:(NSString *)moduleName
                method:(NSString *)methodName
             arguments:(NSArray *)arguments
{
    Class moduleClass = NSClassFromString(moduleName);
    if (!moduleClass)
    {
        [Logger error:LOG_CATEGORY_NATIVEBRIDGE format:@"Module %@ not found", moduleName];
        @throw [NSException
            exceptionWithName:@"ModuleNotFound"
                       reason:[NSString stringWithFormat:@"Module %@ not found", moduleName]
                     userInfo:nil];
    }

    NSString *selectorString = methodName;
    if (arguments && arguments.count > 0)
    {
        for (NSUInteger i = 0; i < arguments.count; i++)
        {
            selectorString = [selectorString stringByAppendingString:@":"];
        }
    }

    SEL selector = NSSelectorFromString(selectorString);

    if (![moduleClass respondsToSelector:selector])
    {
        selector = NSSelectorFromString(methodName);
    }

    if (![moduleClass respondsToSelector:selector])
    {
        [Logger error:LOG_CATEGORY_NATIVEBRIDGE
               format:@"Method %@ not found on %@", selectorString, moduleName];
        @throw
            [NSException exceptionWithName:@"MethodNotFound"
                                    reason:[NSString stringWithFormat:@"Method %@ not found on %@",
                                                                      selectorString, moduleName]
                                  userInfo:nil];
    }

    [Logger debug:LOG_CATEGORY_NATIVEBRIDGE
           format:@"Calling [%@ %@] with %lu arguments", moduleName, NSStringFromSelector(selector),
                  (unsigned long) (arguments ? arguments.count : 0)];

    NSMethodSignature *signature = [moduleClass methodSignatureForSelector:selector];
    if (!signature)
    {
        @throw [NSException
            exceptionWithName:@"NoMethodSignature"
                       reason:[NSString stringWithFormat:@"No method signature for %@",
                                                         NSStringFromSelector(selector)]
                     userInfo:nil];
    }

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:moduleClass];
    [invocation setSelector:selector];

    // Set arguments (starting at index 2, after self and _cmd)
    if (arguments && arguments.count > 0)
    {
        NSUInteger maxArgs = MIN(arguments.count, signature.numberOfArguments - 2);
        for (NSUInteger i = 0; i < maxArgs; i++)
        {
            id arg = arguments[i];
            [invocation setArgument:&arg atIndex:i + 2];
        }
    }

    @try
    {
        [invocation invoke];
    }
    @catch (NSException *exception)
    {
        [Logger error:LOG_CATEGORY_NATIVEBRIDGE
               format:@"Exception during method invocation: %@", exception.reason];
        @throw exception;
    }

    id result = nil;
    if (signature.methodReturnLength > 0)
    {
        const char *returnType = signature.methodReturnType;
        if (strcmp(returnType, "@") == 0)
        { // Object return type
            void *returnValue = NULL;
            [invocation getReturnValue:&returnValue];
            result = (__bridge id) returnValue;
        }
        else if (strcmp(returnType, "c") == 0 || strcmp(returnType, "B") == 0)
        { // BOOL return type
            BOOL returnValue;
            [invocation getReturnValue:&returnValue];
            result = @(returnValue);
        }
        else if (strcmp(returnType, "i") == 0)
        { // int return type
            int returnValue;
            [invocation getReturnValue:&returnValue];
            result = @(returnValue);
        }
        else if (strcmp(returnType, "l") == 0 || strcmp(returnType, "q") == 0)
        { // long/long long return type
            long long returnValue;
            [invocation getReturnValue:&returnValue];
            result = @(returnValue);
        }
        else if (strcmp(returnType, "f") == 0)
        { // float return type
            float returnValue;
            [invocation getReturnValue:&returnValue];
            result = @(returnValue);
        }
        else if (strcmp(returnType, "d") == 0)
        { // double return type
            double returnValue;
            [invocation getReturnValue:&returnValue];
            result = @(returnValue);
        }
        else if (strcmp(returnType, "v") == 0)
        { // void return type
            result = nil;
        }
    }

    return result;
}

@end

%hook DCDStrongboxManager
- (void)getItem:(NSDictionary *)bridgeCommand
        resolve:(RCTPromiseResolveBlock)resolve
         reject:(RCTPromiseRejectBlock)reject
{
    if (bridgeCommand && [bridgeCommand[@"$$unbound$$"] boolValue])
    {
        NSString *moduleName = bridgeCommand[@"module"];
        NSString *methodName = bridgeCommand[@"method"];
        NSArray  *args       = bridgeCommand[@"args"];

        if (!moduleName || !methodName)
        {
            [Logger error:LOG_CATEGORY_NATIVEBRIDGE format:@"Missing module or method name"];
            if (reject)
            {
                reject(@"INVALID_PARAMS", @"Missing module or method name", nil);
            }
            return;
        }

        [Logger debug:LOG_CATEGORY_NATIVEBRIDGE
               format:@"Native bridge call: [%@ %@] with %lu args", moduleName, methodName,
                      (unsigned long) (args ? args.count : 0)];

        @try
        {
            id result = [NativeBridge callNativeMethod:moduleName method:methodName arguments:args];

            if (resolve)
            {
                resolve(result ?: [NSNull null]);
            }
        }
        @catch (NSException *exception)
        {
            [Logger error:LOG_CATEGORY_NATIVEBRIDGE
                   format:@"Native bridge error: %@", exception.reason ?: @"Unknown error"];

            if (reject)
            {
                reject(exception.name ?: @"NATIVE_ERROR", exception.reason ?: @"Unknown error",
                       nil);
            }
        }
        return;
    }

    %orig;
}
%end
