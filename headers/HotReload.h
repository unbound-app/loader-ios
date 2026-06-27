#import "Unbound.h"

// Opt-in live reload (HMR), gated behind the `loader.update.hmr` setting. When enabled, streams
// the dev server's `/__hot` Server-Sent Events endpoint (derived from `loader.update.url`) and
// reloads the app whenever the bundle changes. Toggling the setting starts/stops it without a
// relaunch.
@interface HotReload : NSObject <NSURLSessionDataDelegate>

+ (instancetype)shared;

// Start watching `loader.update.hmr` and apply its current value. Idempotent.
+ (void)observe;

// Start or stop the stream to match the current `loader.update.hmr` value.
+ (void)sync;

- (void)start;
- (void)stop;
- (void)sync;
- (void)connect;
- (void)scheduleReconnect;
- (NSURL *)resolveHotURL;
- (void)drainBuffer;
- (void)handleEvent:(NSString *)event;
- (void)handleReloadEtag:(NSString *)incoming;

@end
