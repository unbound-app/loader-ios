#import "Unbound.h"
#import "FileSystem.h"
#import "Logger.h"
#import "Settings.h"
#import "Plugins.h"
#import "Themes.h"
#import "Fonts.h"
#import "Utilities.h"

// Plain-ObjC loader helpers, kept free of Logos/C++ so they don't pull in the
// jsi/TurboModule headers the bridgeless loader needs.
@interface LoaderShared : NSObject

// Builds the JS that seeds the global UNBOUND_* state (settings, plugins, themes,
// fonts, loader origin/version) as UTF-8 data for the caller to evaluate.
+ (NSData *)buildPreloadScriptData;

// Iterates the entries of <documents>/<subfolder>, invoking `handler` once per entry
// (name + full path) inside a per-entry @try so one bad addon can't abort the scan.
// The handler does the addon-type-specific validation and returns early to skip an
// entry; no directory/manifest layout is assumed here, so font files load too.
+ (void)scanAddonDirectory:(NSString *)subfolder
                  category:(const char *)logCategory
                   handler:(void (^)(NSString *folder, NSString *dir))handler;

// Parses a manifest.json into a mutable dictionary, or returns nil (logging why under
// `cat`) when the file is invalid JSON or fails to parse. `folder` names the entry in
// those log messages.
+ (NSMutableDictionary *)parseManifestAt:(NSString *)path
                                  folder:(NSString *)folder
                                category:(const char *)cat;

@end
