#import "Updater.h"

@implementation Updater
static NSString *etag = nil;

+ (void)downloadBundle:(NSString *)path
{
    [Logger info:LOG_CATEGORY_UPDATER format:@"Ensuring bundle is up to date..."];

    NSString *etag = [Settings getString:@"unbound" key:@"loader.update.etag" def:@""];
    NSURL    *url  = [Updater getDownloadURL];

    __block NSHTTPURLResponse *response;

    if (![FileSystem exists:path] || [Settings getBoolean:@"unbound"
                                                      key:@"loader.update.force"
                                                      def:NO])
    {
        response = [FileSystem download:url path:path];
    }
    else
    {
        response = [FileSystem download:url path:path withHeaders:@{@"If-None-Match" : etag}];
    }

    if ([response statusCode] == 304)
    {
        [Logger info:LOG_CATEGORY_UPDATER format:@"No update found."];
    }
    else
    {
        [Logger info:LOG_CATEGORY_UPDATER format:@"Successfully updated to the latest version."];
        [Settings set:@"unbound"
                  key:@"loader.update.etag"
                value:[response valueForHTTPHeaderField:@"etag"]];
    }
}

+ (NSURL *)getDownloadURL
{
    NSString *baseURL = [Settings getString:@"unbound"
                                        key:@"loader.update.url"
                                        def:@"https://raw.githubusercontent.com/unbound-app/builds/"
                                            @"refs/heads/main/"];

    NSString *manifestURL  = [baseURL stringByAppendingString:@"manifest.json"];
    NSData   *manifestData = [NSData dataWithContentsOfURL:[NSURL URLWithString:manifestURL]];

    if (manifestData)
    {
        NSDictionary *manifest = [Utilities parseJSON:manifestData];
        if (manifest && manifest[@"bytecodeVersion"])
        {
            NSNumber *manifestBytecodeVersion = manifest[@"bytecodeVersion"];
            uint32_t  currentBytecodeVersion  = [Utilities getHermesBytecodeVersion];

            [Logger info:LOG_CATEGORY_UPDATER
                  format:@"Manifest bytecode version: %@, Current bytecode version: %u",
                         manifestBytecodeVersion, currentBytecodeVersion];

            if ([manifestBytecodeVersion unsignedIntValue] == currentBytecodeVersion)
            {
                [Logger info:LOG_CATEGORY_UPDATER format:@"Using hermes bytecode bundle"];
                return [NSURL URLWithString:[baseURL stringByAppendingString:@"unbound.bundle"]];
            }
            else
            {
                [Logger info:LOG_CATEGORY_UPDATER format:@"Using JavaScript bundle"];
                return [NSURL URLWithString:[baseURL stringByAppendingString:@"unbound.js"]];
            }
        }
    }

    [Logger error:LOG_CATEGORY_UPDATER
          format:@"Failed to fetch manifest, falling back to JavaScript bundle"];
    return [NSURL URLWithString:[baseURL stringByAppendingString:@"unbound.js"]];
}
@end
