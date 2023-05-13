#import "Settings.h"
#import "Unbound.h"

@interface Updater : NSObject

+ (BOOL) hasUpdate;
+ (NSURL*) getDownloadURL;

@end