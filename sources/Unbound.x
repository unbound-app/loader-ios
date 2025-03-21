#include <sys/utsname.h>

#import "DeviceModels.h"
#import "Unbound.h"

id gBridge = nil;

%hook RCTCxxBridge
- (void)executeApplicationScript:(NSData *)script url:(NSURL *)url async:(BOOL)async
{
    gBridge = self;

    [FileSystem init];
    [Settings init];

    // Don't load bundle and addons if not configured to do so.
    if (![Settings getBoolean:@"unbound" key:@"loader.enabled" def:YES])
    {
        [Logger info:LOG_CATEGORY_DEFAULT format:@"Loader is disabled. Aborting."];
        return %orig(script, url, true);
    }

    [Plugins init];
    [Themes init];
    [Fonts init];

    NSString *BUNDLE = [NSString pathWithComponents:@[ FileSystem.documents, @"unbound.bundle" ]];
    NSURL    *SOURCE = [NSURL URLWithString:@"unbound"];

    // Apply React DevTools patch if its enabled
    if ([Settings getBoolean:@"unbound" key:@"loader.devtools" def:NO])
    {
        @try
        {
            NSData *bundle = [Utilities getResource:@"devtools" data:true ext:@"js"];

            [Logger info:LOG_CATEGORY_DEFAULT format:@"Attempting to execute DevTools bundle..."];
            %orig(bundle, SOURCE, true);
            [Logger info:LOG_CATEGORY_DEFAULT format:@"Successfully executed DevTools bundle."];
        }
        @catch (NSException *e)
        {
            [Logger error:LOG_CATEGORY_DEFAULT
                   format:@"React DevTools failed to initialize. %@", e];
        }
    }

    // Apply modules patch
    @try
    {
        NSData *bundle = [Utilities getResource:@"modules" data:true ext:@"js"];

        [Logger info:LOG_CATEGORY_DEFAULT format:@"Attempting to execute modules patch..."];
        %orig(bundle, SOURCE, true);
        [Logger info:LOG_CATEGORY_DEFAULT format:@"Successfully executed modules patch."];
    }
    @catch (NSException *e)
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"Modules patch injection failed, expect issues. %@", e];
    }

    // Preload Unbound's settings, plugins & themes
    @try
    {
        NSString *bundle   = [Utilities getResource:@"preload"];
        NSString *settings = [Settings getSettings];
        NSString *plugins  = [Plugins makeJSON];
        NSString *themes   = [Themes makeJSON];

        NSString *availableFonts = [Fonts makeAvailableJSON];
        NSString *fonts          = [Fonts makeJSON];

        NSString *json =
            [NSString stringWithFormat:bundle, settings, plugins, themes, fonts, availableFonts];
        NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];

        [Logger info:LOG_CATEGORY_DEFAULT
              format:@"Pre-loading settings, plugins, fonts and themes..."];
        %orig(data, SOURCE, true);
        [Logger info:LOG_CATEGORY_DEFAULT
              format:@"Pre-loaded settings, plugins, fonts and themes."];
    }
    @catch (NSException *e)
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"Failed to pre-load settings, plugins, fonts and themes. %@", e];
    }

    %orig(script, url, true);

    // Check for updates & re-download bundle if necessary
    @try
    {
        [Updater downloadBundle:BUNDLE];
    }
    @catch (NSException *e)
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"Bundle download failed. (%@)", e];

        if (![FileSystem exists:BUNDLE])
        {
            return [Utilities alert:@"Bundle failed to download, please report this "
                                    @"to the developers."];
        }
        else
        {
            [Utilities alert:@"Bundle failed to update, loading out of date bundle."];
        }
    }

    // Check if Unbound was downloaded properly
    if (![FileSystem exists:BUNDLE])
    {
        return [Utilities alert:@"Bundle not found, please report this to the developers."];
    }

    // Inject Unbound script
    @try
    {
        NSData *bundle = [FileSystem readFile:BUNDLE];

        [Logger info:LOG_CATEGORY_DEFAULT format:@"Attempting to execute bundle..."];
        %orig(bundle, SOURCE, true);
        [Logger info:LOG_CATEGORY_DEFAULT format:@"Unbound's bundle was successfully executed."];
    }
    @catch (NSException *e)
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"Unbound's bundle failed execution, aborting. (%@)", e.reason];
        return [Utilities alert:@"Failed to load Unbound's bundle. Please report "
                                @"this to the developers."];
    }
}
%end

%ctor
{
    [Utilities addDynamicIslandOverlay];
}
