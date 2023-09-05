#import "Settings.h"
#import "Unbound.h"

@interface Updater : NSObject {
	NSString *etag;
}

+ (BOOL) hasUpdate;
+ (NSURL*) getDownloadURL;

+ (NSString*) etag;

@end