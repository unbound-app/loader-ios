#import "Unbound.h"
#import "FileSystem.h"
#import "Logger.h"
#import "Settings.h"
#import "Plugins.h"
#import "Themes.h"
#import "Fonts.h"
#import "Utilities.h"

@interface LoaderShared : NSObject

+ (NSData *)buildPreloadScriptData;

+ (void)scanAddonDirectory:(NSString *)subfolder
                  category:(const char *)logCategory
                   handler:(void (^)(NSString *folder, NSString *dir))handler;

+ (NSMutableDictionary *)parseManifestAt:(NSString *)path
                                  folder:(NSString *)folder
                                category:(const char *)cat;

+ (NSString *)resolveManifestEntryInDirectory:(NSString *)dir
                                    manifest:(NSDictionary *)manifest
                                         key:(NSString *)key;

@end
