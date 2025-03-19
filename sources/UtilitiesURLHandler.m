#import <sys/utsname.h>

#import "Logger.h"
#import "NativeInteropHandler.h"
#import "Utilities.h"

@interface UtilitiesURLHandler : NSObject <NativeInteropHandler>
@end

@implementation UtilitiesURLHandler

// Implement the handler with our namespace
NATIVE_HANDLER_IMPLEMENTATION(@"Utilities")

// Implement specific methods
+ (NSString *)invokeMethod:(NSString *)methodName withArguments:(NSArray<NSString *> *)arguments
{
    if ([methodName isEqualToString:@"alert"])
    {
        NSString *message = arguments.count > 0 ? arguments[0] : @"";
        NSString *title   = arguments.count > 1 ? arguments[1] : @"Unbound";

        dispatch_async(dispatch_get_main_queue(), ^{ [Utilities alert:message title:title]; });

        return nil;
    }

    return [NSString stringWithFormat:@"Unknown method: %@", methodName];
}

@end
