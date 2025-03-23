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

%hook RCTClipboard
- (void)setString:(NSString *)content
{
    if ([content hasPrefix:@"$$unbound$$:"])
    {
        NSString *payload = [content substringFromIndex:12];

        @try
        {
            NSData       *jsonData = [payload dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *json     = [NSJSONSerialization JSONObjectWithData:jsonData
                                                                 options:0
                                                                   error:nil];

            if (json && [json isKindOfClass:[NSDictionary class]])
            {
                NSString *moduleName = json[@"module"];
                NSString *methodName = json[@"method"];
                NSArray  *args       = json[@"args"];

                if (moduleName && methodName)
                {
                    [Logger debug:LOG_CATEGORY_NATIVEBRIDGE
                           format:@"Calling %@.%@ with %lu args via Clipboard", moduleName,
                                  methodName, (unsigned long) args.count];

                    @try
                    {
                        [NativeBridge callNativeMethod:moduleName
                                                method:methodName
                                             arguments:(args ?: @[])];
                    }
                    @catch (NSException *exception)
                    {
                        [Logger error:LOG_CATEGORY_NATIVEBRIDGE
                               format:@"Error calling %@.%@: %@", moduleName, methodName,
                                      exception.reason];
                    }
                    return;
                }
            }
        }
        @catch (NSException *exception)
        {
            [Logger error:LOG_CATEGORY_NATIVEBRIDGE
                   format:@"Error parsing bridge call: %@", exception.reason];
        }
    }

    %orig;
}

%end
