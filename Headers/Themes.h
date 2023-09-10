#include <CoreText/CoreText.h>

#import "FileSystem.h"
#import "Utilities.h"
#import "Settings.h"
#import "Unbound.h"


@interface DCDTheme : NSObject

+ (NSInteger) themeIndex;

@end

@interface Themes : NSObject {
	NSMutableArray *themes;
	NSMutableDictionary<NSString*, NSString*> *fonts;
}

+ (void) swizzle:(Class)interface payload:(NSDictionary*)payload;
+ (UIColor*) parseColor:(NSString*)color;
+ (NSDictionary*) getApplied;
+ (NSString*) makeJSON;
+ (NSString*) downloadFont:(NSURL*)url;
+ loadFont:(NSString*)name orig:(NSString*)orig;
+ (void) apply;
+ (void) init;

// Properties
+ (NSMutableDictionary<NSString*, NSString*>*) fonts;

@end