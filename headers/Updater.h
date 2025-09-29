#import "Unbound.h"

@interface Updater : NSObject
{
    NSString *etag;
}

+ (NSString *)downloadBundle:(NSString *)preferredPath;
+ (NSString *)resolveBundlePath;
+ (NSURL *)getDownloadURL;

@end
