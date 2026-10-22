#import "Unbound.h"
#import "LoaderShared.h"

@interface Plugins : NSObject
{
    NSMutableArray *plugins;
}

+ (NSString *)makeJSON;
+ (void)init;

@end
