#import "Unbound.h"

static BOOL isUnboundModuleRegistered = NO;

static void registerUnboundNativeModule(id bridge)
{
    if (isUnboundModuleRegistered)
        return;
    if (!bridge)
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"bridge is nil"];
        return;
    }

    Class unboundNative = NSClassFromString(@"UnboundNative");
    if (!unboundNative)
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"UnboundNative class not found"];
        return;
    }

    SEL sel = NSSelectorFromString(@"registerAdditionalModuleClasses:");
    if (![bridge respondsToSelector:sel])
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"RCTCxxBridge lacks registerAdditionalModuleClasses:"];
        return;
    }

    @try
    {
        ((void (*)(id, SEL, NSArray *)) objc_msgSend)(bridge, sel, @[ unboundNative ]);
        isUnboundModuleRegistered = YES;
        [Logger info:LOG_CATEGORY_DEFAULT format:@"Registered UnboundNative module"];
    }
    @catch (NSException *e)
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"Failed to register UnboundNative module: %@", e];
    }
}

%group RNLegacyArch
%hook  RCTCxxBridge
- (void)executeApplicationScript:(NSData *)script url:(NSURL *)url async:(BOOL)async
{
    [FileSystem init];
    [Settings init];

    if (![Settings getBoolean:@"unbound" key:@"loader.enabled" def:YES])
    {
        [Logger info:LOG_CATEGORY_DEFAULT format:@"Loader is disabled. Aborting."];
        return %orig(script, url, true);
    }

    [Plugins init];
    [Themes init];
    [Fonts init];

    NSString *bundlePath = [Updater resolveBundlePath];
    NSURL    *SOURCE     = [NSURL URLWithString:@"unbound"];

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

    @try
    {
        NSString *settings       = [Settings getSettings];
        NSString *plugins        = [Plugins makeJSON];
        NSString *themes         = [Themes makeJSON];
        NSString *availableFonts = [Fonts makeAvailableJSON];
        NSString *fonts          = [Fonts makeJSON];

        NSString *origin  = [Utilities JSONString:[Utilities getCurrentDylibName]];
        NSString *version = [Utilities JSONString:PACKAGE_VERSION];

        NSString *preloadScript = [NSString
            stringWithFormat:@"this.UNBOUND_SETTINGS = %@;\n"
                             @"this.UNBOUND_PLUGINS = %@;\n"
                             @"this.UNBOUND_THEMES = %@;\n"
                             @"this.UNBOUND_FONTS = %@;\n"
                             @"this.UNBOUND_AVAILABLE_FONTS = %@;\n\n"
                             @"this.UNBOUND_LOADER = {\n"
                             @"    origin: %@,\n"
                             @"    version: %@,\n"
                             @"};",
                             settings, plugins, themes, fonts, availableFonts, origin, version];

        NSData *data = [preloadScript dataUsingEncoding:NSUTF8StringEncoding];

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
    registerUnboundNativeModule(self);

    @try
    {
        bundlePath = [Updater downloadBundle:bundlePath];
    }
    @catch (NSException *e)
    {
        [Logger error:LOG_CATEGORY_DEFAULT format:@"Bundle download failed. (%@)", e];

        if (![FileSystem exists:bundlePath])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [Utilities alert:@"Bundle failed to download, please report this "
                                 @"to the developers."];
            });
            return;
        }
        else
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [Utilities alert:@"Bundle failed to update, loading out of date bundle."];
            });
        }
    }

    if (![FileSystem exists:bundlePath])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [Utilities alert:@"Bundle not found, please report this to the developers."];
        });
        return;
    }

    @try
    {
        NSData *bundle = [FileSystem readFile:bundlePath];

        [Logger info:LOG_CATEGORY_DEFAULT format:@"Attempting to execute bundle..."];
        %orig(bundle, SOURCE, true);
        [Logger info:LOG_CATEGORY_DEFAULT format:@"Unbound's bundle was successfully executed."];
    }
    @catch (NSException *e)
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"Unbound's bundle failed execution, aborting. (%@)", e.reason];
        dispatch_async(dispatch_get_main_queue(), ^{
            [Utilities alert:@"Failed to load Unbound's bundle. Please report "
                             @"this to the developers."];
        });
        return;
    }
}
%end
%end

%ctor
{
    if ([Utilities isRNNewArchEnabled])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [Utilities
                alert:@"This version of Discord is incompatible with this version of the Tweak."];
        });
        return;
    }

    %init(RNLegacyArch);

#ifndef DEBUG
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            // TODO: remove before initial release
            [Utilities alert:@"This is a development build that is not designed for end users. "
                             @"Please do not use it and refrain from reporting any issues."
                       title:@"⚠️ DEVELOPMENT BUILD"
                     timeout:10
                     warning:YES
                         tts:YES];

            if (![Utilities isVerifiedBuild])
            {
                [Logger error:LOG_CATEGORY_DEFAULT format:@"Tweak signature verification failed"];
                [Utilities alert:@"The injected tweak is missing Unbound's detached signature. "
                                 @"You cannot be sure that this is free of malware. "
                                 @"If this app was obtained via 'cypwn' or similar sources "
                                 @"we heavily recommend you uninstall it immediately."
                           title:@"⚠️ SECURITY WARNING"
                         timeout:15
                         warning:YES];
            }
        });
#endif

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(),
                   ^{
                       if (![Utilities isLoadedWithElleKit])
                       {
                           [Utilities alert:@"Warning: Tweak is not loaded through ElleKit. "
                                            @"Functionality is not guaranteed."
                                      title:@"Runtime Detection"];
                       }
                   });

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (![Utilities isAppStoreApp] && ![Utilities isTestFlightApp] &&
                ![Utilities isTrollStoreApp])
            {
                [Logger info:LOG_CATEGORY_DEFAULT
                      format:@"App is sideloaded, checking for critical extensions"];

                BOOL hasOpenInDiscord = [Utilities hasAppExtension:@"OpenInDiscord"];
                BOOL hasShare         = [Utilities hasAppExtension:@"Share"];

                if (!hasOpenInDiscord)
                {
                    [Logger info:LOG_CATEGORY_DEFAULT
                          format:@"OpenInDiscord extension missing, showing alert"];
                    [Utilities alert:@"The Safari extension (OpenInDiscord.appex) is missing. "
                                     @"You won't be able to open Discord links directly in the app."
                               title:@"Missing Safari Extension"];
                }

                if (!hasShare)
                {
                    [Logger info:LOG_CATEGORY_DEFAULT
                          format:@"Share extension missing, showing alert"];
                    [Utilities alert:@"The Share extension (Share.appex) is missing. "
                                     @"You won't be able to receive shared media and files "
                                     @"from other apps through the share sheet."
                               title:@"Missing Share Extension"];
                }

                if (hasOpenInDiscord && hasShare)
                {
                    [Logger info:LOG_CATEGORY_DEFAULT format:@"All critical extensions present"];
                }
            }
        });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(),
                   ^{
                       [Utilities initializeDynamicIslandOverlay];

        // TODO: remove before initial release
#ifndef DEBUG
                       [Utilities showDevelopmentBuildBanner];
#endif
                   });
}
