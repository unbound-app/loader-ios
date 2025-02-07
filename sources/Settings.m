#import "Settings.h"

@implementation Settings
static NSMutableDictionary *data = nil;
static NSString            *path = nil;

+ (void)init
{
    path = [NSString pathWithComponents:@[ FileSystem.documents, @"settings.json" ]];

    [Settings loadSettings];

    [FileSystem monitor:path onChange:^{ [Settings loadSettings]; } autoRestart:YES];
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

+ (NSString *)getString:(NSString *)store key:(NSString *)key def:(NSString *)def
{
    id payload = data[store];
    if (!payload)
        return def;

    id value = [payload valueForKeyPath:key];

    return value != nil ? value : def;
}

+ (NSDictionary *)getDictionary:(NSString *)store key:(NSString *)key def:(NSDictionary *)def
{
    id payload = data[store];
    if (!payload)
        return def;

    id value = [payload valueForKeyPath:key];

    return value != nil ? value : def;
}

+ (BOOL)getBoolean:(NSString *)store key:(NSString *)key def:(BOOL)def
{
    id payload = data[store];
    if (!payload)
        return def;

    id value = [payload valueForKeyPath:key];

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
        __block NSMutableDictionary *payload = data[store];

        if (!payload)
        {
            [payload setValue:[NSMutableDictionary dictionary] forKey:store];
            payload = data[store];
        };

        // Ensure all keys exist before the last one
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
        NSLog(@"Settings set failed. %@", e);
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

    [FileSystem writeFile:path contents:[payload dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (NSString *)getSettings
{
    NSError *error;
    NSData  *json = [NSJSONSerialization dataWithJSONObject:data
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];

    if (error != nil)
    {
        return @"{}";
    }
    else
    {
        return [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    }
}
@end