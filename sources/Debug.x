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
        // Error code 2: No such file
        if (code == 2)
            return YES;

        // Error code 17: File exists
        if (code == 17)
            return YES;
    }

    if ([domain isEqualToString:@"BSActionErrorDomain"] && code == 1)
    {
        return YES;
    }

    if ([domain isEqualToString:@"NSOSStatusErrorDomain"])
    {
        // -10813: Common error related to FSNode getHFSType
        if (code == -10813)
            return YES;
    }

    // Cocoa errors
    if ([domain isEqualToString:@"NSCocoaErrorDomain"])
    {
        // File not found
        if (code == 260)
            return YES;

        // File exists
        if (code == 516)
            return YES;

        // NSKeyedUnarchiver null data
        if (code == 4864)
            return YES;

        // Saved application state errors
        if (code == 4)
            return YES;
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
