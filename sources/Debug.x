#import "Debug.h"

#ifdef DEBUG

static BOOL shouldIgnoreError(NSString *domain, NSInteger code, NSDictionary *info)
{
    if ([domain isEqualToString:@"com.firebase.dynamicLinks"] && code == 1)
    {
        return YES;
    }

    if ([domain isEqualToString:@"com.apple.AppSSO.AuthorizationError"] && (code == -1000))
    {
        return YES;
    }

    if ([domain isEqualToString:@"RCTJavaScriptLoaderErrorDomain"] && code == 1000)
    {
        return YES;
    }

    if ([domain isEqualToString:@"NSPOSIXErrorDomain"])
    {
        if (code == 2)
            return YES;

        if (code == 17)
            return YES;

        if (code == 22 && (!info || info.count == 0))
            return YES;
    }

    if ([domain isEqualToString:@"BSActionErrorDomain"] && code == 1)
    {
        return YES;
    }

    if ([domain isEqualToString:@"NSOSStatusErrorDomain"])
    {
        if (code == -10813)
            return YES;
    }

    if ([domain isEqualToString:@"NSCocoaErrorDomain"])
    {
        if (code == 260)
            return YES;

        if (code == 516)
            return YES;

        if (code == 4864)
            return YES;

        if (code == 4)
            return YES;

        if (code == 256)
        {
            id   underlying = info[@"NSUnderlyingError"];
            BOOL isPOSIX22  = NO;
            if ([underlying isKindOfClass:[NSError class]])
            {
                NSError *e = (NSError *) underlying;
                isPOSIX22  = [e.domain isEqualToString:@"NSPOSIXErrorDomain"] && e.code == 22;
            }
            else if ([underlying isKindOfClass:[NSString class]])
            {
                NSString *s = (NSString *) underlying;
                isPOSIX22 =
                    ([s containsString:@"NSPOSIXErrorDomain"] && [s containsString:@"Code=22"]);
            }

            NSString *path = [info objectForKey:@"NSFilePath"];
            NSURL    *url  = [info objectForKey:@"NSURL"];
            BOOL      isAppsFlyerPath =
                ([path isKindOfClass:NSString.class] && [path containsString:@"appsflyer-v1"]);
            BOOL isAppsFlyerURL = ([url isKindOfClass:NSURL.class] &&
                                   [[url absoluteString] containsString:@"appsflyer-v1"]);

            if (isPOSIX22 || isAppsFlyerPath || isAppsFlyerURL)
                return YES;
        }
    }

    if ([domain isEqualToString:@"com.appsflyer.sdk.network"] && code == 50)
    {
        return YES;
    }

    if ([domain isEqualToString:@"AVFoundationErrorDomain"] && code == -11800)
    {
        return YES;
    }

    if ([domain isEqualToString:@"_UIViewServiceErrorDomain"] && code == 1)
    {
        NSString *message = [info objectForKey:@"Message"];
        if ((message && [message containsString:@"StoreKitUIService"]) || info[@"Terminated"])
        {
            return YES;
        }
    }

    if ([domain isEqualToString:@"kAFAssistantErrorDomain"] && code == 401)
    {
        return YES;
    }

    if ([domain isEqualToString:@"SDWebImageErrorDomain"] && code == 1000)
    {
        return YES;
    }

    return NO;
}

%hook NSError
- (id)initWithDomain:(id)domain code:(int)code userInfo:(id)userInfo
{
    if (!shouldIgnoreError(domain, code, userInfo))
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"NSError %@ (%d) %@", domain, code, userInfo];
    }
    return %orig;
}

+ (id)errorWithDomain:(id)domain code:(int)code userInfo:(id)userInfo
{
    if (!shouldIgnoreError(domain, code, userInfo))
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"NSError %@ (%d) %@", domain, code, userInfo];
    }
    return %orig;
}
%end

%hook NSException
- (id)initWithName:(id)name reason:(id)reason userInfo:(id)userInfo
{
    [Logger error:LOG_CATEGORY_DEFAULT format:@"NSException %@: %@ %@", name, reason, userInfo];
    return %orig;
}

+ (id)exceptionWithName:(id)name reason:(id)reason userInfo:(id)userInfo
{
    [Logger error:LOG_CATEGORY_DEFAULT format:@"NSException %@: %@ %@", name, reason, userInfo];
    return %orig;
}
%end

%ctor
{
    %init();
}

#endif
