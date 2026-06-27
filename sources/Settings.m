#import "Settings.h"

NSString *const UnboundSettingsDidChangeNotification = @"UnboundSettingsDidChange";

@implementation Settings
static NSMutableDictionary *data = nil;
static NSString            *path = nil;

+ (void)init
{
    path = [NSString pathWithComponents:@[ FileSystem.documents, @"settings.json" ]];

    [Settings loadSettings];

    [FileSystem monitor:path
               onChange:^{
                   [Settings loadSettings];
                   [[NSNotificationCenter defaultCenter]
                       postNotificationName:UnboundSettingsDidChangeNotification
                                     object:nil];
               }
            autoRestart:YES];
}

+ (void)loadSettings
{
    if (![FileSystem exists:path])
    {
        [Settings reset];
    }

    NSData *settings = [FileSystem readFile:path];

    NSError *error;
    data = [NSJSONSerialization JSONObjectWithData:settings
                                           options:NSJSONReadingMutableContainers
                                             error:&error];
}

+ (id)rawValueForStore:(NSString *)store key:(NSString *)key
{
    id payload = data[store];
    return payload ? [payload valueForKeyPath:key] : nil;
}

+ (NSString *)getString:(NSString *)store key:(NSString *)key def:(NSString *)def
{
    id value = [Settings rawValueForStore:store key:key];

    return value ?: def;
}

+ (NSDictionary *)getDictionary:(NSString *)store key:(NSString *)key def:(NSDictionary *)def
{
    id value = [Settings rawValueForStore:store key:key];

    return value ?: def;
}

+ (BOOL)getBoolean:(NSString *)store key:(NSString *)key def:(BOOL)def
{
    id value = [Settings rawValueForStore:store key:key];

    if (value != nil && [value respondsToSelector:@selector(boolValue)])
    {
        return [value boolValue];
    }

    return def;
}

+ (void)set:(NSString *)store key:(NSString *)key value:(id)value
{
    @try
    {
        if (!data)
        {
            data = [NSMutableDictionary dictionary];
        }

        __block NSMutableDictionary *payload = data[store];

        if (!payload)
        {
            payload     = [NSMutableDictionary dictionary];
            data[store] = payload;
        }

        NSArray                     *keys = [key componentsSeparatedByString:@"."];
        __block NSMutableDictionary *res  = payload;

        for (id key in keys)
        {
            if ([keys count] == ([keys indexOfObject:key] + 1))
            {
                [res setValue:value forKey:key];
                break;
            }

            if (res[key] == nil)
            {
                [res setValue:[NSMutableDictionary dictionary] forKey:key];
            }

            res = res[key];
        }

        [Settings save];
    }
    @catch (NSException *e)
    {
        [Logger error:LOG_CATEGORY_SETTINGS format:@"Settings set failed. %@", e];
    }
}

+ (void)reset
{
    NSString *payload = @"{}";

    [FileSystem writeFile:path contents:[payload dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (void)save
{
    NSString *payload = [Settings getSettings];

    NSData *contents = [payload dataUsingEncoding:NSUTF8StringEncoding];

    [FileSystem writeFile:path contents:contents];
}

+ (NSString *)getSettings
{
    return [Utilities JSONStringFromObject:data options:NSJSONWritingPrettyPrinted fallback:@"{}"];
}
@end
