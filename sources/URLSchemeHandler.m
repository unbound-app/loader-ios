#import <objc/runtime.h>

#import "Logger.h"
#import "NativeInteropHandler.h"
#import "URLSchemeHandler.h"
#import "Utilities.h"

// Forward declaration of the handler class
@interface UtilitiesURLHandler : NSObject <NativeInteropHandler>
@end

@implementation URLSchemeHandler
{
    NSMutableDictionary<NSString *, Class<NativeInteropHandler>> *_handlers;
    BOOL                                                          _initialized;
}

+ (instancetype)sharedHandler
{
    static URLSchemeHandler *instance = nil;
    static dispatch_once_t   onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
        // Auto-initialize when getting shared instance
        [instance initialize];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _handlers    = [NSMutableDictionary dictionary];
        _initialized = NO;
    }
    return self;
}

- (void)initialize
{
    // Prevent double initialization
    if (_initialized)
    {
        return;
    }
    _initialized = YES;

    [Logger info:LOG_CATEGORY_DEFAULT format:@"Initializing URL handler with dynamic discovery"];

    unsigned int classCount;
    Class       *classes = objc_copyClassList(&classCount);

    for (unsigned int i = 0; i < classCount; i++)
    {
        Class cls = classes[i];

        if (class_conformsToProtocol(cls, @protocol(NativeInteropHandler)))
        {
            NSString *namespace = [cls urlNamespace];
            if (namespace)
            {
                [Logger info:LOG_CATEGORY_DEFAULT
                      format:@"Found native handler class: %s for namespace: %@",
                             class_getName(cls), namespace];
                _handlers[namespace] = cls;
            }
        }
    }
    free(classes);

    NSMutableString *handlersList = [NSMutableString string];
    NSArray *namespaces = [[_handlers allKeys] sortedArrayUsingSelector:@selector(compare:)];

    for (NSUInteger i = 0; i < namespaces.count; i++)
    {
        [handlersList appendString:namespaces[i]];
        if (i < namespaces.count - 1)
        {
            [handlersList appendString:@", "];
        }
    }

    [Logger info:LOG_CATEGORY_DEFAULT format:@"Registered URL handlers: %@", handlersList];
}

- (NSString *)handleURL:(NSURL *)url
{
    if (!url)
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"Received nil URL"];
        return nil;
    }

    [Logger info:LOG_CATEGORY_DEFAULT format:@"Handling URL: %@", url.absoluteString];

    if (![url.scheme isEqualToString:@"unbound"])
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"Not an unbound:// URL"];
        return nil;
    }

    if (![url.host isEqualToString:@"native"])
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"Not a native method call"];
        return nil;
    }

    NSString *action = url.path;
    if ([action hasPrefix:@"/"])
    {
        action = [action substringFromIndex:1];
    }

    if (![action isEqualToString:@"callMethod"])
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"Unknown action: %@", action];
        return nil;
    }

    // Parse query parameters
    NSURLComponents           *components = [NSURLComponents componentsWithURL:url
                                             resolvingAgainstBaseURL:NO];
    NSArray<NSURLQueryItem *> *queryItems = components.queryItems;

    NSString                   *methodIdentifier = nil;
    NSMutableArray<NSString *> *args             = [NSMutableArray array];

    for (NSURLQueryItem *item in queryItems)
    {
        if ([item.name isEqualToString:@"name"])
        {
            methodIdentifier = item.value;
        }
        else if ([item.name hasPrefix:@"arg"])
        {
            // Extract index from argN name (e.g., arg0, arg1, etc.)
            NSString *indexStr = [item.name substringFromIndex:3];
            NSInteger index    = [indexStr integerValue];

            // Ensure the array is large enough
            while (args.count <= index)
            {
                [args addObject:@""];
            }

            args[index] = item.value ?: @"";
        }
    }

    if (!methodIdentifier)
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"Method identifier not provided"];
        return nil;
    }

    // Split the identifier into namespace and method
    NSArray<NSString *> *parts = [methodIdentifier componentsSeparatedByString:@":"];
    if (parts.count != 2)
    {
        [Logger
             error:LOG_CATEGORY_DEFAULT
            format:@"Invalid method identifier (should be Namespace:Method): %@", methodIdentifier];
        return nil;
    }

    NSString *namespace  = parts[0];
    NSString *methodName = parts[1];

    // Find the handler for this namespace
    Class<NativeInteropHandler> handlerClass = _handlers[namespace];
    if (!handlerClass)
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"No handler registered for namespace: %@", namespace];
        return nil;
    }

    // Check if the method is allowed
    NSSet<NSString *> *allowedMethods = [handlerClass allowedMethods];
    if (![allowedMethods containsObject:@"all"] && ![allowedMethods containsObject:methodName])
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"Method %@ is not allowed in namespace %@", methodName, namespace];
        return nil;
    }

    // Invoke the method
    [Logger info:LOG_CATEGORY_DEFAULT
          format:@"Invoking %@:%@ with args: %@", namespace, methodName, args];

    @try
    {
        NSString *result = [handlerClass invokeMethod:methodName withArguments:args];
        [Logger info:LOG_CATEGORY_DEFAULT
              format:@"Method %@:%@ returned: %@", namespace, methodName, result ?: @"nil"];
        return result;
    }
    @catch (NSException *exception)
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"Error invoking %@:%@: %@", namespace, methodName, exception];
        return nil;
    }
}

@end
