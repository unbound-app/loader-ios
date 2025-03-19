// Rename to NativeInteropHandler.h

#import <Foundation/Foundation.h>
#import <sys/utsname.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Protocol for classes that want to expose methods to URL handler
 */
@protocol NativeInteropHandler <NSObject>

/**
 * Returns the namespace for this handler (e.g., "Utilities")
 */
+ (NSString *)urlNamespace;

/**
 * Returns a set of method names that are allowed to be called via URL
 * Default implementation allows all methods in the handler class
 */
+ (NSSet<NSString *> *)allowedMethods;

/**
 * Invokes a method in this handler
 * @param methodName Name of the method to invoke
 * @param arguments Array of string arguments
 * @return Result string or nil on failure
 */
+ (nullable NSString *)invokeMethod:(NSString *)methodName
                      withArguments:(NSArray<NSString *> *)arguments;

@end

// Helper macro to quickly implement a handler with all methods allowed
#define NATIVE_HANDLER_IMPLEMENTATION(namespace)                                                   \
    +(NSString *) urlNamespace                                                                     \
    {                                                                                              \
        return namespace;                                                                          \
    }                                                                                              \
    +(NSSet<NSString *> *) allowedMethods                                                          \
    {                                                                                              \
        return [NSSet setWithObjects:@"all", nil];                                                 \
    }

NS_ASSUME_NONNULL_END
