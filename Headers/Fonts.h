#include <CoreText/CoreText.h>

#import "Unbound.h"

@interface Fonts : NSObject {
	NSMutableDictionary<NSString*, NSString*> *overrides;
	NSMutableArray *fonts;
}

+ (NSDictionary*) getApplied;
+ (NSString*) makeJSON;
+ (NSString*) downloadFont:(NSURL*)url;
+ loadFont:(NSString*)name orig:(NSString*)orig;

// Properties
+ (NSMutableDictionary<NSString*, NSString*>*) overrides;

@end