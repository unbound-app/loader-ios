#import "Unbound.h"
#import "FileSystem.h"
#import "Utilities.h"

@interface Plugins : NSObject {
	NSMutableArray *plugins;
}

+ (NSString*) makeJSON;
+ (void) init;

@end