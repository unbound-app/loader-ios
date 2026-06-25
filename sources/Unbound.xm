#import <jsi/jsi.h>

#import "FileSystem.h"
#import "Fonts.h"
#import "Logger.h"
#import "Plugins.h"
#import "RCTInstance.h"
#import "Settings.h"
#import "Themes.h"
#import "Unbound.h"
#import "Updater.h"
#import "Utilities.h"

// React Native new-architecture (bridgeless) loader path (RN 0.83.1). Hooks
// RCTInstance to inject scripts over raw JSI and to feed the UnboundNative module
// into RN's legacy-interop TurboModule path. All entry points are ObjC selectors
// (resolved by the ObjC runtime) or jsi symbols (exported by hermes.framework);
// the shipped Discord binary does NOT export the React C++ runtime/TurboModule
// symbols, so we never call them directly.

// Minimal interface for RCTHost (RN 0.83.1 bridgeless): only the RCTInstanceDelegate
// callback we hook to capture the live jsi::Runtime&. Declared inline to avoid a new
// header; the selector + reference type are all that's needed.
@interface RCTHost : NSObject
- (void)instance:(id)instance didInitializeRuntime:(facebook::jsi::Runtime &)runtime;
@end

#import <exception>
#import <memory>
#import <string>

using namespace facebook;

#pragma mark - JSI helpers

namespace {

// jsi::Buffer over NSData for the Hermes bytecode path; retains the NSData.
class NSDataBuffer : public jsi::Buffer
{
public:
    explicit NSDataBuffer(NSData *data) : data_(data) {}

    size_t size() const override
    {
        return data_.length;
    }

    const uint8_t *data() const override
    {
        return static_cast<const uint8_t *>(data_.bytes);
    }

private:
    NSData *data_;
};

// Evaluate JS source or Hermes bytecode. Must run inside a runtime-executor closure.
void evaluateScript(jsi::Runtime &runtime, NSData *scriptData, NSString *tag)
{
    if (scriptData.length == 0)
    {
        return;
    }

    try
    {
        if ([Utilities isHermesBytecode:scriptData])
        {
            auto buffer   = std::make_shared<NSDataBuffer>(scriptData);
            auto prepared = runtime.prepareJavaScript(buffer, std::string(tag.UTF8String));
            runtime.evaluatePreparedJavaScript(prepared);
        }
        else
        {
            std::string source((const char *) scriptData.bytes, scriptData.length);
            auto        buffer = std::make_shared<jsi::StringBuffer>(std::move(source));
            runtime.evaluateJavaScript(buffer, std::string(tag.UTF8String));
        }
    }
    catch (const jsi::JSError &e)
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"JSI eval of '%@' threw JSError: %s", tag, e.what()];
    }
    catch (const std::exception &e)
    {
        [Logger error:LOG_CATEGORY_DEFAULT
               format:@"JSI eval of '%@' threw exception: %s", tag, e.what()];
    }
}

} // namespace

#pragma mark - Pre/post bundle injection

// Live jsi::Runtime captured from -[RCTHost instance:didInitializeRuntime:] (the
// RCTInstanceDelegate callback, RCTInstance.mm:461), which fires on the JS thread
// BEFORE _loadJSBundle: (RCTInstance.mm:470). Valid from that callback until the
// instance is invalidated; only read during bundle load (in _loadScriptFromSource:),
// always null-checked. We capture it via an ObjC selector + jsi::Runtime& (both
// available on the shipped binary) instead of ReactInstance::getUnbufferedRuntimeExecutor
// (NOT exported — calling it crashes DYLD with "symbol not found in flat namespace").
static jsi::Runtime *gRuntime = nullptr;

// devtools / modules patch / preload globals. Evaluated SYNCHRONOUSLY on the live
// runtime from _loadScriptFromSource: BEFORE %orig schedules Discord's bundle, so
// the __d getter installed by modules.js (which lazily populates globalThis.modules)
// is in place before Discord registers its Metro modules via __d(...). This mirrors
// the old-arch path, which runs modules.js -> preload -> Discord's bundle inline in
// strict order. evaluateScript runs directly on the JS thread (no executor); see R1
// (the shipping target always uses the embedded local Hermes bundle => synchronous
// _loadScriptFromSource: on the JS thread).
static void injectUnboundPreBundle(jsi::Runtime &runtime)
{
    if ([Settings getBoolean:@"unbound" key:@"loader.devtools" def:NO])
    {
        NSData *devtools = [Utilities getResource:@"devtools" data:true ext:@"js"];
        if (devtools.length)
        {
            [Logger info:LOG_CATEGORY_DEFAULT format:@"Executing DevTools bundle..."];
            evaluateScript(runtime, devtools, @"unbound:devtools");
        }
    }

    // Modules patch (__d / __c) — must precede Discord's bundle.
    {
        NSData *modules = [Utilities getResource:@"modules" data:true ext:@"js"];
        if (modules.length)
        {
            [Logger info:LOG_CATEGORY_DEFAULT format:@"Executing modules patch..."];
            evaluateScript(runtime, modules, @"unbound:modules");
        }
    }

    // Preload globals (settings / plugins / themes / fonts / loader).
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

        NSData *preloadData = [preloadScript dataUsingEncoding:NSUTF8StringEncoding];
        [Logger info:LOG_CATEGORY_DEFAULT
              format:@"Pre-loading settings, plugins, fonts and themes..."];
        evaluateScript(runtime, preloadData, @"unbound:preload");
    }
}

// Unbound's bundle is downloaded on a background queue during _loadJSBundle:, but
// only ENQUEUED for execution after Discord's bundle has been scheduled (from the
// _loadScriptFromSource: hook). Because the buffered runtime executor is FIFO and
// Discord's bundle is enqueued first, this guarantees Unbound's bundle runs after
// Discord's — so globalThis.modules (populated by Discord via the modules.js __d
// patch) exists when Unbound initializes. A semaphore lets the post-Discord hook
// wait for the (usually cached, fast) download to finish before enqueueing.
static NSData              *gUnboundBundle    = nil;
static dispatch_semaphore_t gUnboundBundleSem = nil;

// Kicks off the background download. Signals gUnboundBundleSem when gUnboundBundle
// is ready (or left nil on failure, with a user-facing alert).
static void prefetchUnboundBundle(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
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
    });
}

// Waits (off the JS thread) for the prefetch to finish, then enqueues Unbound's
// bundle on the buffered executor. Called once, after Discord's bundle has been
// scheduled. Runs the wait on a background queue so we never block the JS thread.
static void enqueueUnboundBundle(RCTInstance *self)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            if (gUnboundBundleSem)
            {
                dispatch_semaphore_wait(gUnboundBundleSem, DISPATCH_TIME_FOREVER);
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
                evaluateScript(runtime, bundle, @"unbound");
                [Logger info:LOG_CATEGORY_DEFAULT
                      format:@"Unbound's bundle was successfully executed."];
            }];
        });
    });
}

#pragma mark - Hooks

// Captures the live jsi::Runtime& on the JS thread before bundle load. RCTHost is
// the RCTInstanceDelegate and implements instance:didInitializeRuntime: (RCTHost.mm:368),
// invoked from RCTInstance.mm:461 inside the init closure, BEFORE _loadJSBundle:
// (line 470). This is a plain ObjC selector receiving the runtime by reference — no
// unexported C++ symbol involved.
%hook RCTHost

- (void)instance:(id)instance didInitializeRuntime:(facebook::jsi::Runtime &)runtime
{
    gRuntime = &runtime;
    [Logger info:LOG_CATEGORY_DEFAULT format:@"RCTHost didInitializeRuntime; runtime captured."];
    %orig;
}

%end

%hook RCTInstance

// Injection driver. Pre-bundle scripts no longer run here (the runtime isn't yet
// captured at this point on the buffered path); they're evaluated synchronously in
// _loadScriptFromSource: once gRuntime is live. Here we only init state and start the
// background download of Unbound's bundle. Final ordering on the JS thread:
// modules.js -> preload -> Discord's bundle -> Unbound's bundle.
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
    %orig(sourceURL);
}

// Runs Discord's bundle (%orig schedules it on the runtime FIFO). We evaluate the
// pre-bundle scripts SYNCHRONOUSLY on gRuntime BEFORE %orig, so the modules.js __d
// getter is installed before Discord registers its Metro modules. Then we enqueue
// Unbound's bundle after %orig, on the buffered executor (flushed after Discord's
// bundle), so globalThis.modules is populated when Unbound runs.
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

// Native module. We cannot construct ObjCInteropTurboModule ourselves because the
// shipped Discord binary does not export its constructor (inlined/stripped).
// Instead we feed UnboundNative's class into RN's legacy-interop path: returning a
// plain RCTBridgeModule class here makes RCTTurboModuleManager treat it as a legacy
// module (_isLegacyModuleClass: is YES for non-TurboModule classes) and construct
// the ObjCInteropTurboModule internally, with no JS changes. The C++ delegate path
// (getTurboModule:jsInvoker:) returns nullptr for it by default, so provideTurboModule:
// falls through to this class lookup.
- (Class)getModuleClassFromName:(const char *)name
{
    if (name && strcmp(name, "UnboundNative") == 0)
    {
        Class cls = NSClassFromString(@"UnboundNative");
        if (cls)
        {
            return cls;
        }

        [Logger error:LOG_CATEGORY_DEFAULT format:@"UnboundNative class not found"];
    }

    return %orig(name);
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
                       [Utilities showDevelopmentBuildBanner];
                       // #endif
                   });
}
