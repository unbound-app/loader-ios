#include <sys/utsname.h>

#import "DeviceModels.h"
#import "Unbound.h"

id gBridge = nil;

// Helper method to get device model identifier
NSString *getDeviceModelIdentifier()
{
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

// Check if current device has Dynamic Island
BOOL deviceHasDynamicIsland()
{
    NSString *identifier           = getDeviceModelIdentifier();
    NSArray  *dynamicIslandDevices = @[
        @"iPhone15,2", @"iPhone15,3", @"iPhone15,4", @"iPhone15,5", @"iPhone16,1", @"iPhone16,2",
        @"iPhone17,1", @"iPhone17,2", @"iPhone17,3", @"iPhone17,4"
    ];

    return [dynamicIslandDevices containsObject:identifier];
}

// Add the Dynamic Island overlay view
void addDynamicIslandOverlay()
{
    if (!deviceHasDynamicIsland())
    {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // Dynamic Island dimensions
        CGFloat width        = 126.0;
        CGFloat height       = 37.33;
        CGFloat cornerRadius = width / 2;

        // Get the screen width to center the view
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        CGFloat x           = (screenWidth - width) / 2;
        CGFloat y           = 11.0; // Starting position from top

        // Create the container view
        UIView *islandView         = [[UIView alloc] initWithFrame:CGRectMake(x, y, width, height)];
        islandView.backgroundColor = [UIColor clearColor];
        islandView.layer.borderColor  = [UIColor lightGrayColor].CGColor;
        islandView.layer.borderWidth  = 1.0;
        islandView.layer.cornerRadius = cornerRadius;
        islandView.clipsToBounds      = YES;

        // Create the label
        UILabel *label      = [[UILabel alloc] initWithFrame:islandView.bounds];
        label.text          = @"Unbound";
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor     = [UIColor lightGrayColor];
        label.font          = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        label.adjustsFontSizeToFitWidth = YES;
        [islandView addSubview:label];

        // Add to keyWindow
        UIWindow *keyWindow = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes)
        {
            if (scene.activationState == UISceneActivationStateForegroundActive)
            {
                keyWindow = ((UIWindowScene *) scene).windows.firstObject;
                break;
            }
        }

        if (keyWindow)
        {
            islandView.alpha = 0.7;
            [keyWindow addSubview:islandView];
            // Ensure it's at the top level
            [keyWindow bringSubviewToFront:islandView];
        }
    });
}

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
