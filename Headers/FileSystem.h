#import "Unbound.h"

@interface FileSystem : NSObject {
	NSFileManager *manager;
	NSString *documents;
}

+ (BOOL) createDirectory:(NSString*)path;
+ (void) writeFile:(NSString*)path contents:(NSData*)contents;

+ (NSString*) delete:(NSString*)path;

+ (BOOL) download:(NSURL*)url path:(NSString*)path;

+ (NSArray*) readDirectory:(NSString*)path;
+ (NSData*) readFile:(NSString*)path;

+ (BOOL) isDirectory:(NSString*)path;
+ (BOOL) exists:(NSString*)path;

+ (void) init;

+ (NSString*) documents;

@end