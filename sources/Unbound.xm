#import <jsi/jsi.h>

#import "Discord.h"
#import "HotReload.h"
#import "JSI.h"
#import "LoaderShared.h"
#import "RCTHost.h"
#import "Unbound.h"
#import "UnboundNative.h"

#import <substrate.h>

#include <atomic>

using namespace facebook;

@interface NSObject (UnboundRuntimeExecutor)
- (void)callFunctionOnBufferedRuntimeExecutor:
    (std::function<void(facebook::jsi::Runtime &)> &&)executor;
@end

#pragma mark - Pre/post bundle injection

static jsi::Runtime *gRuntime = nullptr;
static __weak id gInstance = nil;
static NSString *gPendingBrowserLoginToken = nil;
static BOOL      gBrowserLoginIsApplying    = NO;
static BOOL      gUnboundBundleIsReady      = NO;
static NSUInteger gBrowserLoginFailureCount = 0;
static std::atomic_bool gLoaderPrepared{false};
static std::atomic_bool gBundleExecutionScheduled{false};

static void applyPendingBrowserLogin(void)
{
    id          instance = gInstance;
    NSString    *token    = gPendingBrowserLoginToken;
    if (!instance || token.length == 0 || !gUnboundBundleIsReady || gBrowserLoginIsApplying)
    {
        return;
    }

    gBrowserLoginIsApplying = YES;

    NSString *tokenJSON =
        [Utilities JSONStringFromObject:token options:NSJSONWritingFragmentsAllowed fallback:nil];
    if (!tokenJSON)
    {
        gBrowserLoginIsApplying = NO;
        return;
    }

    NSString *source = [NSString stringWithFormat:
                             @"(function(token){const apply=()=>{const metro=globalThis.unbound?.metro;if(!metro||typeof metro.findByProps!=='function')throw new Error('Unbound Metro API unavailable');let auth=metro.findByProps('getAnalyticsToken','setToken');if(!auth)auth=metro.findByProps('getToken','setToken');if(!auth||typeof auth.setToken!=='function')throw new Error('Discord authentication store unavailable');auth.setToken(token);const reload=globalThis.unbound?.native?.reload;if(typeof reload!=='function')throw new Error('Unbound reload API unavailable');Promise.resolve(reload()).catch(()=>{});};const ready=globalThis.__unboundReady;if(ready?.ready)apply();else if(Array.isArray(ready?.callbacks))ready.callbacks.push(apply);else apply();})(%@);",
                         tokenJSON];
    NSData *script = [source dataUsingEncoding:NSUTF8StringEncoding];

    [instance callFunctionOnBufferedRuntimeExecutor:[script, token](jsi::Runtime &runtime) {
    BOOL applied = [JSI evaluate:script tag:@"browser-login" runtime:runtime];
        dispatch_async(dispatch_get_main_queue(), ^{
            gBrowserLoginIsApplying = NO;
            if (applied)
            {
                if ([gPendingBrowserLoginToken isEqualToString:token])
                {
                    gPendingBrowserLoginToken = nil;
                }
                gBrowserLoginFailureCount = 0;
                [Logger info:LOG_CATEGORY_DEFAULT format:@"Browser login token application scheduled."];
                return;
            }

            gBrowserLoginFailureCount++;
            [Logger error:LOG_CATEGORY_DEFAULT
                   format:@"Browser login JavaScript application failed (attempt %lu).",
                          (unsigned long)gBrowserLoginFailureCount];
            if (gBrowserLoginFailureCount <= 3)
            {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC),
                               dispatch_get_main_queue(), ^{ applyPendingBrowserLogin(); });
            }
            else
            {
                [Utilities alert:@"Discord could not finish browser login. Please try again."
                           title:@"Could Not Finish Login"];
            }
        });
    }];
}

void CompleteBrowserLogin(NSString *token)
{
    if (token.length == 0)
    {
        return;
    }

    gPendingBrowserLoginToken = [token copy];
    gBrowserLoginFailureCount = 0;
    applyPendingBrowserLogin();
}

static void injectModulesPatch(jsi::Runtime &runtime)
{
    NSData *modules = [Utilities getResource:@"modules" data:true ext:@"js"];
    if (modules.length)
    {
        [Logger info:LOG_CATEGORY_DEFAULT format:@"Executing modules patch..."];
        [JSI evaluate:modules tag:@"unbound:modules" runtime:runtime];
    }
}

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

    NSData *moduleBootstrap = [@"globalThis.modules \x3f\x3f= globalThis.__c?.();"
        dataUsingEncoding:NSUTF8StringEncoding];
    [JSI evaluate:moduleBootstrap tag:@"unbound:modules-bootstrap" runtime:runtime];

    {
        NSData *preloadData = [LoaderShared buildPreloadScriptData];
        [Logger info:LOG_CATEGORY_DEFAULT
              format:@"Pre-loading settings, plugins, fonts and themes..."];
        [JSI evaluate:preloadData tag:@"unbound:preload" runtime:runtime];
    }
}

static NSData              *gUnboundBundle    = nil;
static dispatch_semaphore_t gUnboundBundleSem = nil;
static std::atomic_uint64_t gPrefetchToken{0};

static void prefetchUnboundBundle(void);

static void prepareUnboundLoading(id instance)
{
    if (!instance || gLoaderPrepared.exchange(true))
    {
        return;
    }

    gInstance = instance;
    gUnboundBundleIsReady = NO;
    gBundleExecutionScheduled.store(false);
    [FileSystem init];
    [Settings init];
    dispatch_async(dispatch_get_main_queue(), ^{ [DevOverlay refreshOverlay]; });

    if (![Settings getBoolean:@"unbound" key:@"loader.enabled" def:YES])
    {
        [Logger info:LOG_CATEGORY_DEFAULT format:@"Loader is disabled. Aborting."];
        return;
    }

    [Plugins init];
    [Themes init];
    [Fonts init];
    prefetchUnboundBundle();
    [HotReload observe];
}

static void prefetchUnboundBundle(void)
{
    uint64_t token = gPrefetchToken.fetch_add(1) + 1;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    gUnboundBundle    = nil;
    gUnboundBundleSem = sem;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *bundlePath = [Updater resolveBundlePath];
        NSString *localBundlePath = bundlePath;

        @try
        {
            NSString *downloadedPath = [Updater downloadBundle:bundlePath];
            if ([FileSystem exists:downloadedPath])
            {
                bundlePath = downloadedPath;
            }
        }
        @catch (NSException *e)
        {
            [Logger error:LOG_CATEGORY_DEFAULT format:@"Bundle download failed. (%@)", e];
            bundlePath = localBundlePath;
        }

        if (![FileSystem exists:bundlePath] && [FileSystem exists:localBundlePath])
        {
            bundlePath = localBundlePath;
        }

        if (token != gPrefetchToken.load())
        {
            dispatch_semaphore_signal(sem);
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

        dispatch_semaphore_signal(sem);
    });
}

static BOOL runtimeHasRequiredModules(jsi::Runtime &runtime)
{
    NSString *source =
        @"(()=>{const map=globalThis.modules??globalThis.__c?.();if(!globalThis.modules&&map)globalThis.modules=map;if(!map||typeof map.values!=='function')return false;let rn=false;let react=false;for(const m of map.values()){const e=m?.publicModule?.exports??m?.exports??m;const values=[e,e?.default,e?.default?.default];for(const value of values){if(!value)continue;if(!rn&&value.AppState&&value.NativeModules)rn=true;if(!react&&typeof value.createElement==='function')react=true;}}return rn&&react;})()";
    jsi::Value result = [JSI evaluateSource:source tag:@"unbound:runtime-readiness" runtime:runtime];
    return [JSI toBool:result runtime:runtime fallback:NO];
}

static void executeUnboundBundle(id instance,
                                 NSData *bundle,
                                 uint64_t token,
                                 NSUInteger attempt)
{
    if (!instance || bundle.length == 0 || token != gPrefetchToken.load())
    {
        return;
    }

    [instance callFunctionOnBufferedRuntimeExecutor:[bundle, token, attempt](jsi::Runtime &runtime) {
        injectModulesPatch(runtime);
        if (!runtimeHasRequiredModules(runtime))
        {
            if (attempt >= 200)
            {
                [Logger error:LOG_CATEGORY_DEFAULT
                       format:@"React Native modules were not ready after %lu attempts.",
                              (unsigned long)attempt];
                return;
            }

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                               executeUnboundBundle(gInstance, bundle, token, attempt + 1);
                           });
            return;
        }

        injectModulesPatch(runtime);
        injectUnboundPreBundle(runtime);
        [Logger info:LOG_CATEGORY_DEFAULT format:@"Attempting to execute bundle..."];
        BOOL didLoadBundle = [JSI evaluate:bundle tag:@"unbound" runtime:runtime];
        if (didLoadBundle)
        {
            [Logger info:LOG_CATEGORY_DEFAULT
                  format:@"Unbound's bundle was successfully executed."];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (token != gPrefetchToken.load())
                {
                    return;
                }
                gUnboundBundleIsReady = YES;
                applyPendingBrowserLogin();
            });
        }
    }];
}

static void enqueueUnboundBundle(id self)
{
    if (gBundleExecutionScheduled.exchange(true))
    {
        return;
    }

    dispatch_semaphore_t sem = gUnboundBundleSem;
    uint64_t              token = gPrefetchToken.load();

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (sem)
        {
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        }

        if (token != gPrefetchToken.load())
        {
            return;
        }

        NSData *bundle = gUnboundBundle;
        if (bundle.length == 0)
        {
            return;
        }

        [Logger info:LOG_CATEGORY_DEFAULT format:@"Scheduling Unbound's bundle for execution..."];
        executeUnboundBundle(self, bundle, token, 0);
    });
}

#pragma mark - Hooks

%hook RCTHost

- (void)instance:(id)instance didInitializeRuntime:(facebook::jsi::Runtime &)runtime
{
    gRuntime = &runtime;
    [Logger info:LOG_CATEGORY_DEFAULT format:@"RCTHost didInitializeRuntime reached."];
    id hostInstance = instance;
    prepareUnboundLoading(hostInstance);
    injectModulesPatch(runtime);
    %orig;
    if ([hostInstance respondsToSelector:@selector(callFunctionOnBufferedRuntimeExecutor:)])
    {
        [Logger info:LOG_CATEGORY_DEFAULT format:@"RCTHost runtime instance is ready."];
        enqueueUnboundBundle(hostInstance);
    }
    else
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"RCTHost runtime instance has no buffered executor."];
    }
}

%end

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

typedef void (*LoadJSBundleIMP)(id, SEL, NSURL *);
typedef void (*LoadScriptFromSourceIMP)(id, SEL, id);

static LoadJSBundleIMP         gOriginalLoadJSBundle         = NULL;
static LoadScriptFromSourceIMP gOriginalLoadScriptFromSource = NULL;
static BOOL                    gRCTInstanceHooksInstalled   = NO;

static void unboundLoadJSBundle(id self, SEL selector, NSURL *sourceURL)
{
    prepareUnboundLoading(self);
    if (gOriginalLoadJSBundle)
    {
        gOriginalLoadJSBundle(self, selector, sourceURL);
    }
}

static void unboundLoadScriptFromSource(id self, SEL selector, id source)
{
    [self callFunctionOnBufferedRuntimeExecutor:[](jsi::Runtime &runtime) {
        injectModulesPatch(runtime);
    }];

    if (gOriginalLoadScriptFromSource)
    {
        gOriginalLoadScriptFromSource(self, selector, source);
    }

    enqueueUnboundBundle(self);
}

static BOOL installRCTInstanceHooks(void)
{
    if (gRCTInstanceHooksInstalled)
    {
        return YES;
    }

    Class instanceClass = NSClassFromString(@"RCTInstance");
    if (!instanceClass || !class_getInstanceMethod(instanceClass, @selector(_loadJSBundle:)) ||
        !class_getInstanceMethod(instanceClass, @selector(_loadScriptFromSource:)))
    {
        return NO;
    }

    MSHookMessageEx(instanceClass,
                    @selector(_loadJSBundle:),
                    (IMP)unboundLoadJSBundle,
                    (IMP *)&gOriginalLoadJSBundle);
    MSHookMessageEx(instanceClass,
                    @selector(_loadScriptFromSource:),
                    (IMP)unboundLoadScriptFromSource,
                    (IMP *)&gOriginalLoadScriptFromSource);
    gRCTInstanceHooksInstalled = gOriginalLoadJSBundle != NULL &&
                                 gOriginalLoadScriptFromSource != NULL;
    return gRCTInstanceHooksInstalled;
}

static void retryRCTInstanceHooks(NSUInteger attempt)
{
    if (installRCTInstanceHooks() || attempt >= 300)
    {
        if (!gRCTInstanceHooksInstalled)
        {
            [Logger error:LOG_CATEGORY_DEFAULT format:@"RCTInstance hooks could not be installed."];
        }
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(),
                   ^{ retryRCTInstanceHooks(attempt + 1); });
}

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
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL verified = [Utilities isVerifiedBuild];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!verified)
            {
                [Logger error:LOG_CATEGORY_DEFAULT format:@"Embedded tweak attestation verification failed"];
                [Utilities alert:@"The injected tweak failed Unbound's embedded integrity verification. "
                                 @"You cannot be sure that this is free of malware. "
                                 @"If this app was obtained via 'cypwn' or similar sources "
                                 @"we heavily recommend you uninstall it immediately."
                           title:@"⚠️ SECURITY WARNING"
                         timeout:15
                         warning:YES];
                return;
            }
            retryRCTInstanceHooks(0);
        });
    });
#else
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(),
                   ^{ retryRCTInstanceHooks(0); });
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
#ifdef DEBUG
                       [DevOverlay showDevelopmentBuildBanner];
#endif
                   });
}
