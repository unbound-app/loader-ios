#include <CoreGraphics/CGFont.h>
#include <CoreText/CoreText.h>
#include <objc/runtime.h>
#include <substrate.h>

#import "Unbound.h"

@interface Fonts : NSObject
{
    NSMutableDictionary<NSString *, NSString *>            *overrides;
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *fonts;
}

+ (void)apply;
+ (void)init;
+ (void)loadFont:(NSString *)path;
+ (NSString *)getFontName:(NSString *)path;
+ (NSString *)getFontNameByRef:(CGFontRef)ref;
+ (NSArray *)getAvailableFonts;

+ (NSString *)makeAvailableJSON;
+ (NSString *)makeJSON;

// Properties
+ (NSMutableDictionary<NSString *, NSString *> *)overrides;

@end