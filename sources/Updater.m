#import "Updater.h"

@implementation Updater
static NSString *etag = nil;

+ (NSString *)resolveBundlePath
{
    [FileSystem init];

    NSArray<NSString *> *extensions = @[ @"bundle", @"js" ];

    for (NSString *extension in extensions)
    {
        NSString *path =
            [NSString pathWithComponents:@[ FileSystem.documents,
                                             [NSString stringWithFormat:@"unbound.%@", extension] ]];

        if ([FileSystem exists:path])
        {
            return path;
        }
    }

    return [NSString pathWithComponents:@[ FileSystem.documents, @"unbound.bundle" ]];
}

+ (NSString *)downloadBundle:(NSString *)preferredPath
{
    [Logger info:LOG_CATEGORY_UPDATER format:@"Ensuring bundle is up to date..."];

    NSString *storedEtag = [Settings getString:@"unbound" key:@"loader.update.etag" def:@""];
    NSURL    *url        = [Updater getDownloadURL];

    NSString *urlExtension = [[url pathExtension] lowercaseString];

    NSString *currentPath =
        preferredPath ? preferredPath : [Updater resolveBundlePath];
    NSString *currentExtension = [[currentPath pathExtension] lowercaseString];

    NSSet<NSString *> *supportedExtensions = [NSSet setWithArray:@[ @"bundle", @"js" ]];

    if (![supportedExtensions containsObject:urlExtension])
    {
        urlExtension = [supportedExtensions containsObject:currentExtension] ? currentExtension : @"js";
    }

    NSString *targetPath = [NSString
        pathWithComponents:@[ FileSystem.documents,
                               [NSString stringWithFormat:@"unbound.%@", urlExtension] ]];

    NSDictionary *headers = storedEtag.length > 0 ? @{ @"If-None-Match" : storedEtag } : @{};

    __block NSHTTPURLResponse *response;

    BOOL forceUpdate =
        [Settings getBoolean:@"unbound" key:@"loader.update.force" def:NO];

    if (![FileSystem exists:targetPath] || forceUpdate)
    {
        response = [FileSystem download:url path:targetPath];
    }
    else
    {
        response = [FileSystem download:url path:targetPath withHeaders:headers];
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

    NSArray<NSString *> *extensionsToClean = @[ @"bundle", @"js" ];
    for (NSString *extension in extensionsToClean)
    {
        NSString *candidatePath = [NSString
            pathWithComponents:@[ FileSystem.documents,
                                   [NSString stringWithFormat:@"unbound.%@", extension] ]];

        if (![candidatePath isEqualToString:targetPath] && [FileSystem exists:candidatePath])
        {
            [FileSystem delete:candidatePath];
        }
    }

    return targetPath;
}

+ (NSURL *)getDownloadURL
{
    NSString *baseURL             = [Settings getString:@"unbound"
                                        key:@"loader.update.url"
                                        def:@"https://raw.githubusercontent.com/unbound-app/builds/"
                                                        @"refs/heads/main/"];
    NSString *directURLIfProvided = nil;

    if ([baseURL hasSuffix:@".bundle"] || [baseURL hasSuffix:@".js"])
    {
        NSURL *providedURL = [NSURL URLWithString:baseURL];
        if (providedURL)
        {
            NSURL *dirURL = [providedURL URLByDeletingLastPathComponent];
            if (dirURL)
            {
                baseURL = dirURL.absoluteString ?: baseURL;
            }
        }
        if (![baseURL hasSuffix:@"/"])
        {
            baseURL = [baseURL stringByAppendingString:@"/"];
        }
        directURLIfProvided =
            ((NSURL *) [NSURL URLWithString:((NSString *) [Settings getString:@"unbound"
                                                                          key:@"loader.update.url"
                                                                          def:@""])])
                    .absoluteString
                ?: nil;
    }

    if (![baseURL hasSuffix:@"/"])
    {
        baseURL = [baseURL stringByAppendingString:@"/"];
    }

    NSString *manifestURL  = [baseURL stringByAppendingString:@"manifest.json"];
    NSData   *manifestData = [Utilities fetchDataWithTimeout:[NSURL URLWithString:manifestURL]
                                                      timeout:5.0];

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
           format:@"Failed to fetch manifest; falling back to JavaScript bundle"];
    if (directURLIfProvided)
    {
        return [NSURL URLWithString:directURLIfProvided];
    }
    return [NSURL URLWithString:[baseURL stringByAppendingString:@"unbound.js"]];
}
@end
