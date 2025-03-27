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

    // Check if we need to append a colon based on argument count
    NSString *selectorName = methodName;
    if (arguments.count > 0 && ![selectorName hasSuffix:@":"])
    {
        selectorName = [selectorName stringByAppendingString:@":"];
    }

    SEL selector = NSSelectorFromString(selectorName);
    if (![moduleClass respondsToSelector:selector])
    {
        [Logger error:LOG_CATEGORY_NATIVEBRIDGE
               format:@"Method %@ not found on %@", selectorName, moduleName];

        if (arguments.count == 1)
        {
            selector = NSSelectorFromString([methodName stringByAppendingString:@":"]);
        }
        else if (arguments.count == 2)
        {
            selector = NSSelectorFromString([NSString stringWithFormat:@"%@::", methodName]);
        }

        if (![moduleClass respondsToSelector:selector])
        {
            @throw [NSException
                exceptionWithName:@"MethodNotFound"
                           reason:[NSString stringWithFormat:@"Method %@ not found on %@",
                                                             methodName, moduleName]
                         userInfo:nil];
        }
    }

    NSMethodSignature *signature  = [moduleClass methodSignatureForSelector:selector];
    NSInvocation      *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setSelector:selector];
    [invocation setTarget:moduleClass];

    // Set arguments
    NSUInteger numberOfArguments = signature.numberOfArguments;
    for (NSUInteger i = 0; i < arguments.count && (i + 2) < numberOfArguments; i++)
    {
        id arg = arguments[i];
        [invocation setArgument:&arg atIndex:i + 2]; // start at index 2 (self, _cmd)
    }

    [invocation invoke];

    // Get return value if it exists
    if (signature.methodReturnLength > 0)
    {
        __unsafe_unretained id result = nil;
        [invocation getReturnValue:&result];
        return result;
    }

    return nil;
}

@end

%hook RCTLinkingManager

- (void)openURL:(NSURL *)URL resolve:(id)resolve reject:(id)reject
{
    if (URL && [URL.scheme isEqualToString:@"nativebridge"])
    {
        // Cast the blocks to the correct types
        RCTPromiseResolveBlock resolveBlock = resolve;
        RCTPromiseRejectBlock  rejectBlock  = reject;

        @try
        {
            // Get the path component which contains our encoded payload
            NSString *encodedPayload = URL.host;
            if (!encodedPayload)
            {
                encodedPayload = URL.path;
                if ([encodedPayload hasPrefix:@"/"])
                {
                    encodedPayload = [encodedPayload substringFromIndex:1];
                }
            }

            // Decode the URL-encoded payload
            NSString *payload = [encodedPayload stringByRemovingPercentEncoding];

            // Parse JSON payload
            NSError      *jsonError = nil;
            NSData       *jsonData  = [payload dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *json      = [NSJSONSerialization JSONObjectWithData:jsonData
                                                                 options:0
                                                                   error:&jsonError];

            if (jsonError || !json)
            {
                [Logger error:LOG_CATEGORY_NATIVEBRIDGE
                       format:@"Error parsing JSON: %@", jsonError.localizedDescription];

                if (rejectBlock)
                    rejectBlock(@"INVALID_JSON", @"Invalid JSON payload", jsonError);
                return;
            }

            // Extract command details
            NSString *moduleName = json[@"module"];
            NSString *methodName = json[@"method"];
            NSArray  *args       = json[@"args"];

            if (!moduleName || !methodName)
            {
                [Logger error:LOG_CATEGORY_NATIVEBRIDGE format:@"Missing module or method name"];

                if (rejectBlock)
                    rejectBlock(@"INVALID_PARAMS", @"Missing module or method name", nil);
                return;
            }

            [Logger debug:LOG_CATEGORY_NATIVEBRIDGE
                   format:@"Executing %@.%@ via bridge with %lu args", moduleName, methodName,
                          (unsigned long) (args ? args.count : 0)];

            @try
            {
                // Execute the native method
                id result = [NativeBridge callNativeMethod:moduleName
                                                    method:methodName
                                                 arguments:(args ?: @[])];

                // Return the result
                if (resolveBlock)
                    resolveBlock(result ?: [NSNull null]);
                return;
            }
            @catch (NSException *exception)
            {
                [Logger error:LOG_CATEGORY_NATIVEBRIDGE
                       format:@"Error executing native method: %@",
                              exception.reason ?: @"Unknown error"];

                if (rejectBlock)
                    rejectBlock(exception.name ?: @"ERROR", exception.reason ?: @"Unknown error",
                                nil);
                return;
            }
        }
        @catch (NSException *exception)
        {
            [Logger error:LOG_CATEGORY_NATIVEBRIDGE
                   format:@"Bridge error: %@", exception.reason ?: @"Unknown exception"];

            if (rejectBlock)
                rejectBlock(@"BRIDGE_ERROR", exception.reason ?: @"Unknown error", nil);
            return;
        }
    }

    %orig;
}

%end
