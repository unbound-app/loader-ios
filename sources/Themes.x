#import "LoaderShared.h"
#import "Themes.h"

@implementation Themes
static NSMutableDictionary<NSString *, NSValue *> *originalRawImplementations;
static NSMutableArray                             *themes         = nil;
static NSString                                   *currentThemeId = nil;

+ (NSString *)makeJSON
{
    return [Utilities JSONStringFromObject:themes options:0 fallback:@"[]"];
};

+ (NSDictionary *)getThemeById:(NSString *)manifestId
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"manifest.id == %@", manifestId];
    NSArray     *array     = [themes filteredArrayUsingPredicate:predicate];

    if ([array count] != 0)
    {
        return array[0];
    }

    return nil;
}

+ (BOOL)isValidCustomTheme:(NSString *)manifestId
{
    NSDictionary *theme = [Themes getThemeById:manifestId];

    if (theme != nil)
    {
        return YES;
    }

    return NO;
}

+ (void)init
{
    if (!themes)
    {
        themes = [[NSMutableArray alloc] init];
    }

    if (!originalRawImplementations)
    {
        originalRawImplementations = [[NSMutableDictionary alloc] init];
    }

    [LoaderShared
        scanAddonDirectory:@"Themes"
                  category:LOG_CATEGORY_THEMES
                   handler:^(NSString *folder, NSString *dir) {
                       if (![FileSystem isDirectory:dir])
                       {
                           [Logger info:LOG_CATEGORY_THEMES
                                 format:@"Skipping %@ as it is not a directory.", folder];
                           return;
                       }

                       NSString *data = [NSString pathWithComponents:@[ dir, @"manifest.json" ]];
                       if (![FileSystem exists:data])
                       {
                           [Logger info:LOG_CATEGORY_THEMES
                                 format:@"Skipping %@ as it is missing a manifest.", folder];
                           return;
                       }

                       NSMutableDictionary *manifest =
                           [LoaderShared parseManifestAt:data
                                                  folder:folder
                                                category:LOG_CATEGORY_THEMES];
                       if (!manifest)
                       {
                           return;
                       }

                       NSString *entry = [NSString pathWithComponents:@[ dir, @"bundle.json" ]];
                       if (![FileSystem exists:entry])
                       {
                           [Logger info:LOG_CATEGORY_THEMES
                                 format:@"Skipping %@ as it is missing a bundle.", folder];
                           return;
                       }

                       __block NSData *bundle = nil;

                       @try
                       {
                           id json = [Utilities parseJSON:[FileSystem readFile:entry]];

                           if ([json isKindOfClass:[NSDictionary class]])
                           {
                               bundle = [json mutableCopy];
                           }
                           else
                           {
                               [Logger info:LOG_CATEGORY_THEMES
                                     format:@"Skipping %@ as its bundle is invalid JSON.", folder];
                               return;
                           }
                       }
                       @catch (NSException *e)
                       {
                           [Logger error:LOG_CATEGORY_THEMES
                                  format:@"Skipping %@ as its bundle failed to be parsed. (%@)",
                                         folder, e.reason];
                           return;
                       }

                       manifest[@"folder"] = folder;
                       manifest[@"path"]   = dir;

                       [themes addObject:@{@"manifest" : manifest, @"bundle" : bundle}];
                   }];

    if (![Settings getBoolean:@"unbound" key:@"recovery" def:NO])
    {
        [Themes swizzleSemanticColors];
    }
};

+ (void)swizzleRawColors:(NSDictionary *)payload
{
    Class instance = object_getClass(NSClassFromString(@"UIColor"));

    [Logger info:LOG_CATEGORY_THEMES format:@"Attempting swizzle raw colors..."];

    @try
    {
        for (NSString *raw in payload)
        {
            SEL selector = NSSelectorFromString(raw);

            __block id (*original)(Class, SEL);
            IMP     replacement = imp_implementationWithBlock(^UIColor *(id self) {
                @try
                {
                    id       color  = payload[raw];
                    UIColor *parsed = [Themes parseColor:color];
                    if (parsed)
                        return parsed;
                }
                @catch (NSException *e)
                {
                    [Logger error:LOG_CATEGORY_THEMES
                           format:@"Failed to use modified raw color %@. (%@)", raw, e.reason];
                }

                return original(instance, selector);
                });

            MSHookMessageEx(instance, selector, replacement, (IMP *) &original);

            originalRawImplementations[raw] = [NSValue valueWithPointer:(void *) original];
        }

        [Logger info:LOG_CATEGORY_THEMES format:@"Raw color swizzle completed."];
    }
    @catch (NSException *e)
    {
        [Logger error:LOG_CATEGORY_THEMES format:@"Failed to swizzle raw colors. (%@)", e.reason];
    }
}

+ (void)restoreOriginalRawColors
{
    Class instance = object_getClass(NSClassFromString(@"UIColor"));

    for (NSString *selectorName in originalRawImplementations)
    {
        SEL selector    = NSSelectorFromString(selectorName);
        IMP originalIMP = (IMP)[originalRawImplementations[selectorName] pointerValue];

        if (originalIMP)
        {
            MSHookMessageEx(instance, selector, originalIMP, NULL);
        }
        else
        {
            [Logger error:LOG_CATEGORY_THEMES
                   format:@"Failed to restore implementation for %@: Original IMP is NULL",
                          selectorName];
        }
    }

    [originalRawImplementations removeAllObjects];
}

+ (void)swizzleSemanticColors
{
    [Logger info:LOG_CATEGORY_THEMES format:@"Attempting swizzle semantic colors..."];

    @try
    {
        Class instance = object_getClass(NSClassFromString(@"DCDThemeColor"));

        unsigned methodCount = 0;
        Method  *methods     = class_copyMethodList(instance, &methodCount);

        for (unsigned int i = 0; i < methodCount; i++)
        {
            Method    method   = methods[i];
            SEL       selector = method_getName(method);
            NSString *name     = NSStringFromSelector(selector);

            __block id (*original)(Class, SEL);
            IMP     replacement = imp_implementationWithBlock(^UIColor *(id self) {
                if (currentThemeId != nil)
                {
                    @try
                    {
                        NSDictionary *theme = [Themes getThemeById:currentThemeId];
                        if (!theme)
                            return original(instance, selector);

                        NSDictionary *values = theme[@"bundle"][@"semantic"];
                        if (!values)
                            return original(instance, selector);

                        NSDictionary *color = values[name];
                        if (!color || !color[@"type"] || !color[@"value"])
                        {
                            return original(instance, selector);
                        }

                        NSString *colorType    = color[@"type"];
                        NSString *colorValue   = color[@"value"];
                        NSNumber *colorOpacity = color[@"opacity"];

                        if ([colorType isEqualToString:@"color"])
                        {
                            UIColor *parsed = [Themes parseColor:colorValue];

                            if (parsed)
                            {
                                if (colorOpacity)
                                {
                                    return
                                        [parsed colorWithAlphaComponent:[colorOpacity doubleValue]];
                                }

                                return parsed;
                            }
                        }

                        if ([colorType isEqualToString:@"raw"])
                        {
                            SEL   colorSelector = NSSelectorFromString(colorValue);
                            Class instance = object_getClass(NSClassFromString(@"UIColor"));

                            if ([instance respondsToSelector:colorSelector])
                            {
                                UIColor *(*getColor)(id, SEL);
                                getColor =
                                    (UIColor *
                                     (*) (id, SEL)) [instance methodForSelector:colorSelector];

                                return getColor(instance, colorSelector);
                            }

                            return original(instance, selector);
                        }

                        return original(instance, selector);
                    }
                    @catch (NSException *e)
                    {
                        [Logger error:LOG_CATEGORY_THEMES
                               format:@"Failed to use modified color %@. (%@)", name, e.reason];
                    }
                }

                return original(instance, selector);
                });

            MSHookMessageEx(instance, selector, replacement, (IMP *) &original);
        }

        free(methods);
        [Logger info:LOG_CATEGORY_THEMES format:@"Semantic color swizzle completed."];
    }
    @catch (NSException *e)
    {
        [Logger error:LOG_CATEGORY_THEMES
               format:@"Failed to swizzle semantic colors. (%@)", e.reason];
    }
}

+ (UIColor *)parseColor:(NSString *)color
{
    return [Utilities parseColor:color];
}
@end

%hook DCDTheme
- (void)updateTheme:(id)theme
{
    if (![theme isKindOfClass:[NSString class]])
    {
        return %orig;
    }

    if ([currentThemeId isEqualToString:theme])
    {
        return %orig;
    }

    [Logger info:LOG_CATEGORY_THEMES format:@"Theme updated. (%@)", theme];
    currentThemeId = theme;

    [Themes restoreOriginalRawColors];

    NSDictionary *instance = [Themes getThemeById:theme];

    if (instance)
    {
        NSDictionary *raw = instance[@"bundle"][@"raw"];
        if (raw)
            [Themes swizzleRawColors:raw];
    }

    %orig;
}
%end
