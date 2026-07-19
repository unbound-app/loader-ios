#import "Plugins.h"

@implementation Plugins
static NSMutableArray *plugins = nil;

+ (NSString *)makeJSON
{
    return [Utilities JSONStringFromObject:plugins options:0 fallback:@"[]"];
};

+ (void)init
{
    plugins = [[NSMutableArray alloc] init];

    [LoaderShared
        scanAddonDirectory:@"Plugins"
                  category:LOG_CATEGORY_PLUGINS
                   handler:^(NSString *folder, NSString *dir) {
                       if (![FileSystem isDirectory:dir])
                       {
                           [Logger info:LOG_CATEGORY_PLUGINS
                                 format:@"Skipping %@ as it is not a directory.", folder];
                           return;
                       }

                       NSString *data = [NSString pathWithComponents:@[ dir, @"manifest.json" ]];
                       if (![FileSystem exists:data])
                       {
                           [Logger info:LOG_CATEGORY_PLUGINS
                                 format:@"Skipping %@ as it is missing a manifest.", folder];
                           return;
                       }

                       NSMutableDictionary *manifest =
                           [LoaderShared parseManifestAt:data
                                                  folder:folder
                                                category:LOG_CATEGORY_PLUGINS];
                       if (!manifest)
                       {
                           return;
                       }

                       NSString *entry = [LoaderShared resolveManifestEntryInDirectory:dir
                                                                              manifest:manifest
                                                                                   key:@"main"];
                       if (!entry)
                       {
                           [Logger info:LOG_CATEGORY_PLUGINS
                                 format:@"Skipping %@ as manifest.main is missing or invalid.",
                                        folder];
                           return;
                       }

                       NSData *bundle = [FileSystem readFile:entry];

                       manifest[@"folder"] = folder;
                       manifest[@"path"]   = dir;
                       manifest[@"entry"]  = entry;

                       [plugins addObject:@{
                           @"manifest" : manifest,
                           @"bundle" : [[NSString alloc] initWithData:bundle
                                                             encoding:NSUTF8StringEncoding]
                       }];

                       [Logger info:LOG_CATEGORY_PLUGINS
                             format:@"Loaded %@ from %@.", folder, entry];
                   }];

    NSUInteger pluginCount = [plugins count];
    NSString  *pluralForm  = (pluginCount == 1) ? @"plugin" : @"plugins";
    [Logger info:LOG_CATEGORY_PLUGINS format:@"Loaded %lu %@.", pluginCount, pluralForm];
};

@end
