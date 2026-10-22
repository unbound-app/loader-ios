#include <istream>
#include <ostream>
#include <streambuf>

#import "CoreBridge.h"
#import "Logger.h"

#include "LoaderAddons.h"
#include "LoaderLog.h"
#include "LoaderPreload.h"

static std::string toStdString(NSString *value)
{
    const char *utf8 = value.UTF8String;
    return utf8 ? std::string(utf8) : std::string();
}

static NSMutableArray *mutableArrayFromJSON(const nlohmann::json &value)
{
    std::string json   = loader::toJSON(value);
    NSData     *data   = [NSData dataWithBytes:json.data() length:json.size()];
    id          parsed = [NSJSONSerialization JSONObjectWithData:data
                                                     options:NSJSONReadingMutableContainers
                                                       error:nil];
    return [parsed isKindOfClass:[NSMutableArray class]] ? parsed : [NSMutableArray array];
}

static LogLevel iosLogLevel(loader::LogLevel level)
{
    switch (level)
    {
        case loader::LogLevel::Debug:
            return LogLevelDebug;
        case loader::LogLevel::Info:
            return LogLevelInfo;
        case loader::LogLevel::Warning:
            return LogLevelNotice;
        case loader::LogLevel::Error:
            return LogLevelError;
    }
    return LogLevelInfo;
}

@implementation CoreBridge

+ (void)installLogging
{
    loader::setLogSink([](loader::LogLevel level, const std::string &category, const std::string &message) {
        [Logger log:iosLogLevel(level)
            category:category.c_str()
              format:@"%@", [NSString stringWithUTF8String:message.c_str()] ?: @""];
    });
}

+ (NSMutableArray *)scanPluginsIn:(NSString *)documents
{
    return mutableArrayFromJSON(loader::scanPlugins(toStdString(documents)));
}

+ (NSMutableArray *)scanThemesIn:(NSString *)documents
{
    return mutableArrayFromJSON(loader::scanThemes(toStdString(documents)));
}

+ (NSMutableArray *)scanFontsIn:(NSString *)documents
                   nameResolver:(NSString *_Nullable (^)(NSString *path))resolver
{
    loader::FontNameResolver resolveName = [resolver](const std::string &path) {
        NSString *name = resolver([NSString stringWithUTF8String:path.c_str()] ?: @"");
        return name ? toStdString(name) : std::string();
    };
    return mutableArrayFromJSON(loader::scanFonts(toStdString(documents), resolveName));
}

+ (NSData *)preloadScriptWithSettings:(NSString *)settings
                              plugins:(NSString *)plugins
                               themes:(NSString *)themes
                                fonts:(NSString *)fonts
                       availableFonts:(NSString *)availableFonts
                               origin:(NSString *)origin
                              version:(NSString *)version
{
    loader::PreloadPayload payload;
    payload.settings       = toStdString(settings);
    payload.plugins        = toStdString(plugins);
    payload.themes         = toStdString(themes);
    payload.fonts          = toStdString(fonts);
    payload.availableFonts = toStdString(availableFonts);
    payload.origin         = toStdString(origin);
    payload.version        = toStdString(version);

    std::string script = loader::buildPreloadScript(payload);
    return [NSData dataWithBytes:script.data() length:script.size()];
}

@end
