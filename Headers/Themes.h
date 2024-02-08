#import "Unbound.h"

@interface DCDTheme : NSObject
	+ (NSInteger) themeIndex;
@end

@interface Themes : NSObject {
	NSMutableArray *themes;
}

+ (void) swizzle:(Class)interface payload:(NSDictionary*)payload;
+ (UIColor*) parseColor:(NSString*)color;
+ (NSDictionary*) getApplied;
+ (NSString*) makeJSON;
+ (void) apply;
+ (void) init;

@end