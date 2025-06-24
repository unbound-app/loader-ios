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

    NSMutableArray *possibleSelectors = [NSMutableArray array];

    [possibleSelectors addObject:methodName];
    [possibleSelectors addObject:[NSString stringWithFormat:@"%@:", methodName]];

    if (arguments.count > 0)
    {
        NSMutableString *selectorWithColons = [NSMutableString stringWithString:methodName];
        for (NSUInteger i = 0; i < arguments.count; i++)
        {
            [selectorWithColons appendString:@":"];
        }
        [possibleSelectors addObject:selectorWithColons];
    }

    SEL selectedSelector = NULL;
    for (NSString *selectorStr in possibleSelectors)
    {
        SEL selector = NSSelectorFromString(selectorStr);
        if ([moduleClass respondsToSelector:selector])
        {
            selectedSelector = selector;
            [Logger debug:LOG_CATEGORY_NATIVEBRIDGE
                   format:@"Found matching selector: %@", selectorStr];
            break;
        }
    }

    if (!selectedSelector && arguments.count > 0)
    {
        unsigned int methodCount;
        Method      *methodList = class_copyMethodList(object_getClass(moduleClass), &methodCount);

        for (unsigned int i = 0; i < methodCount; i++)
        {
            Method    method         = methodList[i];
            SEL       methodSelector = method_getName(method);
            NSString *selectorName   = NSStringFromSelector(methodSelector);

            if ([selectorName hasPrefix:methodName] &&
                [selectorName characterAtIndex:[methodName length]] == ':')
            {

                NSUInteger colonCount = 0;
                for (NSUInteger j = 0; j < [selectorName length]; j++)
                {
                    if ([selectorName characterAtIndex:j] == ':')
                    {
                        colonCount++;
                    }
                }

                if (colonCount == arguments.count)
                {
                    selectedSelector = methodSelector;
                    [Logger debug:LOG_CATEGORY_NATIVEBRIDGE
                           format:@"Found compatible selector: %@", selectorName];
                    break;
                }
            }
        }

        if (methodList)
        {
            free(methodList);
        }
    }

    if (!selectedSelector)
    {
        [Logger error:LOG_CATEGORY_NATIVEBRIDGE
               format:@"No matching method found for %@ on %@ with %lu arguments", methodName,
                      moduleName, (unsigned long) arguments.count];

        @throw
            [NSException exceptionWithName:@"MethodNotFound"
                                    reason:[NSString stringWithFormat:@"Method %@ not found on %@",
                                                                      methodName, moduleName]
                                  userInfo:nil];
    }

    [Logger debug:LOG_CATEGORY_NATIVEBRIDGE
           format:@"Executing native method: [%@ %@] with %lu arguments", moduleName,
                  NSStringFromSelector(selectedSelector), (unsigned long) arguments.count];

    NSMethodSignature *signature  = [moduleClass methodSignatureForSelector:selectedSelector];
    NSInvocation      *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setSelector:selectedSelector];
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
                reject(@"INVALID_PARAMS", @"Missing module or method name", nil);
            return;
        }

        [Logger debug:LOG_CATEGORY_NATIVEBRIDGE
               format:@"Executing [%@ %@]", moduleName, methodName];

        @try
        {
            // Execute the native method
            id result = [NativeBridge callNativeMethod:moduleName
                                                method:methodName
                                             arguments:(args ?: @[])];

            // Return the result
            if (resolve)
                resolve(result ?: [NSNull null]);
        }
        @catch (NSException *exception)
        {
            [Logger error:LOG_CATEGORY_NATIVEBRIDGE
                   format:@"Error executing [%@ %@]: %@", moduleName, methodName,
                          exception.reason ?: @"Unknown error"];

            if (reject)
                reject(exception.name ?: @"ERROR", exception.reason ?: @"Unknown error", nil);
        }
        return;
    }
    %orig;
}
%end
