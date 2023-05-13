#import "Settings.h"
#import "Enmity.h"

@interface Updater : NSObject

+ (BOOL) hasUpdate;
+ (NSURL*) getDownloadURL;

@end