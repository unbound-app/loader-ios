#import <jsi/jsi.h>

#import "Discord.h"
#import "HotReload.h"
#import "JSI.h"
#import "LoaderShared.h"
#import "RCTHost.h"
#import "RCTInstance.h"
#import "Unbound.h"
#import "UnboundNative.h"

using namespace facebook;

#pragma mark - Pre/post bundle injection

// Only read during bundle load and always null-checked.
static jsi::Runtime *gRuntime = nullptr;

static void injectUnboundPreBundle(jsi::Runtime &runtime)
{
    unbound::registerNativeInterop(runtime);

    if ([Settings getBoolean:@"unbound" key:@"loader.devtools" def:NO])
    {
        NSData *devtools = [Utilities getResource:@"devtools" data:true ext:@"js"];
        if (devtools.length)
        {
            [Logger info:LOG_CATEGORY_DEFAULT format:@"Executing DevTools bundle..."];
            [JSI evaluate:devtools tag:@"unbound:devtools" runtime:runtime];
        }
    }

    // Must precede Discord's bundle: installs the __d getter before Discord registers
    // its Metro modules.
    {
        NSData *modules = [Utilities getResource:@"modules" data:true ext:@"js"];
        if (modules.length)
        {
            [Logger info:LOG_CATEGORY_DEFAULT format:@"Executing modules patch..."];
            [JSI evaluate:modules tag:@"unbound:modules" runtime:runtime];
        }
    }

    {
        NSData *preloadData = [LoaderShared buildPreloadScriptData];
        [Logger info:LOG_CATEGORY_DEFAULT
              format:@"Pre-loading settings, plugins, fonts and themes..."];
        [JSI evaluate:preloadData tag:@"unbound:preload" runtime:runtime];
    }
}

// Unbound's bundle is enqueued only after Discord's has been scheduled so the FIFO executor runs
// it second, once globalThis.modules (populated by Discord) exists. The semaphore lets the
// post-Discord hook wait for the download.
//
// These run once per bundle load, not once per process, so a reload (which re-fires the hooks)
// re-fetches and re-evaluates the bundle. gPrefetchToken discards a download from a load that was
// superseded by a newer one before it finished.
static NSData              *gUnboundBundle    = nil;
static dispatch_semaphore_t gUnboundBundleSem = nil;
static uint64_t             gPrefetchToken    = 0;

static void prefetchUnboundBundle(void)
{
    uint64_t token = ++gPrefetchToken;

    gUnboundBundle    = nil;
    gUnboundBundleSem = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *bundlePath = [Updater resolveBundlePath];

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
            }
            else
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [Utilities alert:@"Bundle failed to update, loading out of date bundle."];
                });
            }
        }

        // A newer load started while we were downloading - let it win.
        if (token != gPrefetchToken)
        {
            return;
        }

        if ([FileSystem exists:bundlePath])
        {
            NSData *bundle = [FileSystem readFile:bundlePath];
            if (bundle.length)
            {
                gUnboundBundle = bundle;
            }
        }

        if (!gUnboundBundle)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [Utilities alert:@"Failed to load Unbound's bundle. Please report "
                                 @"this to the developers."];
            });
        }

        dispatch_semaphore_signal(gUnboundBundleSem);
    });
}

// Waits on a background queue so the prefetch wait never blocks the JS thread.
static void enqueueUnboundBundle(RCTInstance *self)
{
    // Snapshot this load's semaphore so a reload that swaps gUnboundBundleSem mid-wait
    // can't make us wait on the wrong one.
    dispatch_semaphore_t sem = gUnboundBundleSem;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (sem)
        {
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        }

        NSData *bundle = gUnboundBundle;
        if (bundle.length == 0)
        {
            return;
        }

        [Logger info:LOG_CATEGORY_DEFAULT
              format:@"Scheduling Unbound's bundle for execution..."];
        [self callFunctionOnBufferedRuntimeExecutor:[bundle](jsi::Runtime &runtime) {
            [Logger info:LOG_CATEGORY_DEFAULT format:@"Attempting to execute bundle..."];
            [JSI evaluate:bundle tag:@"unbound" runtime:runtime];
            [Logger info:LOG_CATEGORY_DEFAULT
                  format:@"Unbound's bundle was successfully executed."];
        }];
    });
}

#pragma mark - Hooks

// Fires before bundle load, giving us the runtime to inject into later.
%hook RCTHost

- (void)instance:(id)instance didInitializeRuntime:(facebook::jsi::Runtime &)runtime
{
    gRuntime = &runtime;
    [Logger info:LOG_CATEGORY_DEFAULT format:@"RCTHost didInitializeRuntime; runtime captured."];
    %orig;
}

%end

// Capture the live bundle-updater instance the moment RN constructs it, so reloadApp
// can message the exact instance Discord's JS reload path uses.
%hook DCDBundleUpdaterManager

- (id)init
{
    id instance = %orig;
    if (instance)
    {
        [Utilities setBundleUpdater:instance];
        [Logger info:LOG_CATEGORY_DEFAULT format:@"DCDBundleUpdaterManager captured."];
    }
    return instance;
}

%end

%hook RCTInstance

- (void)_loadJSBundle:(NSURL *)sourceURL
{
    [FileSystem init];
    [Settings init];

    if (![Settings getBoolean:@"unbound" key:@"loader.enabled" def:YES])
    {
        [Logger info:LOG_CATEGORY_DEFAULT format:@"Loader is disabled. Aborting."];
        %orig(sourceURL);
        return;
    }

    [Plugins init];
    [Themes init];
    [Fonts init];

    prefetchUnboundBundle();

    // Opt-in dev live reload; no-op unless `loader.update.hmr` is enabled.
    [HotReload observe];

    %orig(sourceURL);
}

// Pre-bundle scripts run before %orig (which schedules Discord's bundle) so the
// modules patch is in place first; Unbound's bundle is enqueued after, behind Discord's.
- (void)_loadScriptFromSource:(id)source
{
    if (gRuntime)
    {
        injectUnboundPreBundle(*gRuntime);
    }
    else
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"Runtime not captured; skipping pre-bundle injection."];
    }

    %orig(source);
    enqueueUnboundBundle(self);
}

%end

%ctor
{
    if (![Utilities isRNNewArchEnabled])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [Utilities
                alert:@"This version of Discord is incompatible with this version of the Tweak."];
        });
        return;
    }

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
                       // TODO: uncomment before initial release
                       // #ifdef DEBUG
                       [DevOverlay showDevelopmentBuildBanner];
                       // #endif
                   });
}
