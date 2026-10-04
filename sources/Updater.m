#import "Updater.h"

// `bun run serve` in the client repo serves its build from this port on the Mac.
static const NSInteger      kDevServerPort         = 3000;
static NSString *const      kDevServerBundleName   = @"unbound.bundle";
static const NSTimeInterval kDevServerProbeTimeout = 1.5;

static BOOL isServingBundle(NSURL *url)
{
    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url
                                cachePolicy:NSURLRequestReloadIgnoringCacheData
                            timeoutInterval:kDevServerProbeTimeout];
    request.HTTPMethod = @"HEAD";

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL         serving   = NO;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
              serving = !error && [(NSHTTPURLResponse *) response statusCode] == 200;
              dispatch_semaphore_signal(semaphore);
          }];
    [task resume];

    if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW,
                                                         (int64_t) (kDevServerProbeTimeout *
                                                                    NSEC_PER_SEC))) != 0)
    {
        [task cancel];
        return NO;
    }

    return serving;
}

@implementation Updater
static NSString *etag = nil;

+ (NSString *)resolveUpdateURL
{
    NSString *configuredURL = [Settings getString:@"unbound" key:@"loader.update.url" def:nil];
    if (configuredURL)
    {
        return configuredURL;
    }

    NSString *hostAddress = [Utilities getVirtualDeviceHostAddress];
    if (!hostAddress)
    {
        return nil;
    }

    NSString *devServerURL = [NSString
        stringWithFormat:@"http://%@:%ld/%@", hostAddress, (long) kDevServerPort, kDevServerBundleName];
    if (!isServingBundle([NSURL URLWithString:devServerURL]))
    {
        [Logger info:LOG_CATEGORY_UPDATER
              format:@"Virtual device: %@ is not reachable; using the default update URL.",
                     devServerURL];
        return nil;
    }

    [Logger info:LOG_CATEGORY_UPDATER format:@"Virtual device: using %@.", devServerURL];
    return devServerURL;
}

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
    NSString *updateURL           = [Updater resolveUpdateURL];
    NSString *baseURL             = updateURL ?: @"https://builds.unbound.rip/";
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
        directURLIfProvided = [NSURL URLWithString:updateURL].absoluteString;
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
        if (manifest)
        {
            NSArray *manifestBytecodeVersions = manifest[@"bytecodeVersions"];
            uint32_t currentBytecodeVersion   = [Utilities getHermesBytecodeVersion];

            [Logger info:LOG_CATEGORY_UPDATER
                  format:@"Manifest bytecode versions: %@, Current bytecode version: %u",
                         manifestBytecodeVersions, currentBytecodeVersion];

            if ([manifestBytecodeVersions isKindOfClass:[NSArray class]])
            {
                for (NSNumber *version in manifestBytecodeVersions)
                {
                    if ([version isKindOfClass:[NSNumber class]] &&
                        [version unsignedIntValue] == currentBytecodeVersion)
                    {
                        [Logger info:LOG_CATEGORY_UPDATER format:@"Using hermes bytecode bundle"];
                        NSString *bundle =
                            [NSString stringWithFormat:@"unbound.%u.bundle", currentBytecodeVersion];
                        return [NSURL URLWithString:[baseURL stringByAppendingString:bundle]];
                    }
                }
            }

            [Logger info:LOG_CATEGORY_UPDATER format:@"Using JavaScript bundle"];
            return [NSURL URLWithString:[baseURL stringByAppendingString:@"unbound.js"]];
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
