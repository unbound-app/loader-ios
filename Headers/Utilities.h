#import "Unbound.h"
#import "FileSystem.h"

@interface Utilities : NSObject {
	NSString *bundle;
}

+ (NSString*) getBundlePath;

+ (NSData*) getResource:(NSString*)file data:(BOOL)data ext:(NSString*)ext;
+ (NSString*) getResource:(NSString*)file ext:(NSString*)ext;

+ (NSData*) getResource:(NSString*)file data:(BOOL)data;
+ (NSString*) getResource:(NSString*)file;

+ (void) alert:(NSString*)message title:(NSString*)title buttons:(NSArray<UIAlertAction*>*)buttons;
+ (void) alert:(NSString*)message title:(NSString*)title;
+ (void) alert:(NSString*)message;

+ (id) parseJSON:(NSData*)data;

@end