#import "FileSystem.h"
#import "Utilities.h"
#import "Unbound.h"


@interface Settings : NSObject {
	NSDictionary *data;
	NSString *path;
}

+ (NSString*) getString:(NSString*)store key:(NSString*)key def:(NSString*)def;
+ (BOOL) getBoolean:(NSString*)store key:(NSString*)key def:(BOOL)def;
+ (void) set:(NSString*)store key:(NSString*)key value:(id)value;
+ (NSString*) getSettings;
+ (void) reset;
+ (void) init;
+ (void) save;

@end