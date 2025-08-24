#import "Unbound.h"

@interface Updater : NSObject
{
    NSString *etag;
}

+ (void)downloadBundle:(NSString *)path;
+ (NSURL *)getDownloadURL;

@end
