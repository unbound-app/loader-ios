#import "LoaderShared.h"

#import "FileSystem.h"
#import "Logger.h"
#import "Settings.h"
#import "Plugins.h"
#import "Themes.h"
#import "Fonts.h"
#import "Utilities.h"

@implementation LoaderShared

+ (NSData *)buildPreloadScriptData
{
    NSString *settings       = [Settings getSettings];
    NSString *plugins        = [Plugins makeJSON];
    NSString *themes         = [Themes makeJSON];
    NSString *availableFonts = [Fonts makeAvailableJSON];
    NSString *fonts          = [Fonts makeJSON];

    NSString *origin  = [Utilities JSONString:[Utilities getCurrentDylibName]];
    NSString *version = [Utilities JSONString:PACKAGE_VERSION];

    NSString *preloadScript = [NSString
        stringWithFormat:@"this.UNBOUND_SETTINGS = %@;\n"
                         @"this.UNBOUND_PLUGINS = %@;\n"
                         @"this.UNBOUND_THEMES = %@;\n"
                         @"this.UNBOUND_FONTS = %@;\n"
                         @"this.UNBOUND_AVAILABLE_FONTS = %@;\n\n"
                         @"this.UNBOUND_LOADER = {\n"
                         @"    origin: %@,\n"
                         @"    version: %@,\n"
                         @"};",
                         settings, plugins, themes, fonts, availableFonts, origin, version];

    return [preloadScript dataUsingEncoding:NSUTF8StringEncoding];
}

+ (void)scanAddonDirectory:(NSString *)subfolder
                  category:(const char *)logCategory
                   handler:(void (^)(NSString *folder, NSString *dir))handler
{
    NSString *path = [NSString pathWithComponents:@[ FileSystem.documents, subfolder ]];
    [FileSystem createDirectory:path];

    NSArray *contents = [FileSystem readDirectory:path];

    for (NSString *folder in contents)
    {
        [Logger info:logCategory format:@"Attempting to load %@...", folder];

        @try
        {
            NSString *dir = [NSString pathWithComponents:@[ path, folder ]];
            handler(folder, dir);
        }
        @catch (NSException *e)
        {
            [Logger error:logCategory format:@"Failed to load %@ (%@)", folder, e.reason];
        }
    }
}

+ (NSMutableDictionary *)parseManifestAt:(NSString *)path
                                  folder:(NSString *)folder
                                category:(const char *)cat
{
    @try
    {
        id json = [Utilities parseJSON:[FileSystem readFile:path]];

        if ([json isKindOfClass:[NSDictionary class]])
        {
            return [json mutableCopy];
        }

        [Logger info:cat format:@"Skipping %@ as its manifest is invalid.", folder];
        return nil;
    }
    @catch (NSException *e)
    {
        [Logger error:cat
               format:@"Skipping %@ as its manifest failed to be parsed. (%@)", folder, e.reason];
        return nil;
    }
}

@end
