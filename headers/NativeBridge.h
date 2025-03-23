#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "Unbound.h"

@interface NativeBridge : NSObject

+ (id)callNativeMethod:(NSString *)moduleName
                method:(NSString *)methodName
             arguments:(NSArray *)arguments;

@end
