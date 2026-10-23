#import "Analytics.h"

%hook SentrySDK
+ (void)startWithOptions:(id)options
{
    [Logger info:LOG_CATEGORY_DEFAULT format:@"Blocked SentrySDK."];
    return;
}

+ (void)startWithConfigureOptions:(id)callback
{
    [Logger info:LOG_CATEGORY_DEFAULT format:@"Blocked SentrySDK."];
    return;
}

+ (BOOL)isEnabled
{
    return NO;
}
%end

%hook FIRInstallations
+ (void)load
{
    [Logger info:LOG_CATEGORY_DEFAULT format:@"Blocked Firebase Installations."];
    return;
}
%end

%ctor
{
    %init();
}
