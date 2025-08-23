#import "Unbound.h"

@interface Plugins : NSObject
{
    NSMutableArray *plugins;
}

+ (NSString *)makeJSON;
+ (void)init;

@end
