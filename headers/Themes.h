#import <objc/runtime.h>
#import <substrate.h>

#import "Unbound.h"

@interface DCDTheme : NSObject
+ (NSInteger)themeIndex;
@end

@interface Themes : NSObject
{
    NSMutableArray                             *themes;
    NSMutableDictionary<NSString *, NSValue *> *originalRawImplementations;
    NSString                                   *currentThemeId;
}

+ (NSDictionary *)getThemeById:(NSString *)manifestId;
+ (BOOL)isValidCustomTheme:(NSString *)manifestId;
+ (void)swizzleRawColors:(NSDictionary *)payload;
+ (UIColor *)parseColor:(NSString *)color;
+ (void)restoreOriginalRawColors;
+ (void)swizzleSemanticColors;
+ (NSString *)makeJSON;
+ (void)init;

@end
