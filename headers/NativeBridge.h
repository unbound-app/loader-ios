#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "Unbound.h"

typedef void (^RCTPromiseResolveBlock)(id result);
typedef void (^RCTPromiseRejectBlock)(NSString *code, NSString *message, NSError *error);

@interface NativeBridge : NSObject

+ (id)callNativeMethod:(NSString *)moduleName
                method:(NSString *)methodName
             arguments:(NSArray *)arguments;

@end
