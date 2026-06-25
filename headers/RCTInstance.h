// Private interface for RCTInstance (RN 0.83.1 bridgeless): only the members the
// new-arch loader hooks/calls (_loadJSBundle:, callFunctionOnBufferedRuntimeExecutor:,
// getModuleClassFromName:).

#import <Foundation/Foundation.h>
#import <jsi/jsi.h>

#import <functional>

@interface RCTInstance : NSObject

- (void)_loadJSBundle:(NSURL *)sourceURL;
- (void)_loadScriptFromSource:(id)source;

- (void)callFunctionOnBufferedRuntimeExecutor:
    (std::function<void(facebook::jsi::Runtime &)> &&)executor;

- (Class)getModuleClassFromName:(const char *)name;

@end
