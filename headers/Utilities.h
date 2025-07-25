#import <CommonCrypto/CommonCrypto.h>
#import <dlfcn.h>
#import <rootless.h>
#import <sys/utsname.h>

#import "FileSystem.h"
#import "Unbound.h"

extern NSString * const TROLL_STORE_PATH;
extern NSString * const TROLL_STORE_LITE_PATH;
extern const CGFloat DYNAMIC_ISLAND_TOP_INSET;

@interface Utilities : NSObject
{
    NSString *bundle;
}

+ (NSString *)getBundlePath;

+ (NSData *)getResource:(NSString *)file data:(BOOL)data ext:(NSString *)ext;
+ (NSString *)getResource:(NSString *)file ext:(NSString *)ext;

+ (NSData *)getResource:(NSString *)file data:(BOOL)data;
+ (NSString *)getResource:(NSString *)file;

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons;
+ (void)alert:(NSString *)message title:(NSString *)title;
+ (void)alert:(NSString *)message;

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
      timeout:(NSInteger)timeout;
+ (void)alert:(NSString *)message
        title:(NSString *)title
      timeout:(NSInteger)timeout;

+ (id)parseJSON:(NSData *)data;

+ (dispatch_source_t)createDebounceTimer:(double)delay
                                   queue:(dispatch_queue_t)queue
                                   block:(dispatch_block_t)block;

+ (uint32_t)getHermesBytecodeVersion;
+ (BOOL)isHermesBytecode:(NSData *)data;
+ (void *)getHermesSymbol:(const char *)symbol error:(NSString **)error;
+ (BOOL)isAppStoreApp;
+ (BOOL)isTestFlightApp;
+ (BOOL)isTrollStoreApp;
+ (NSString *)getTrollStoreVariant;
+ (BOOL)isSystemApp;
+ (BOOL)isJailbroken;

+ (NSString *)getDeviceModel;
+ (BOOL)deviceHasDynamicIsland;
+ (void)initializeDynamicIslandOverlay;
+ (void)showDynamicIslandOverlay;
+ (void)hideDynamicIslandOverlay;

+ (BOOL)isLoadedWithElleKit;

+ (NSArray<NSString *> *)getAvailableAppExtensions;
+ (BOOL)hasAppExtension:(NSString *)extensionName;

+ (NSDictionary *)getApplicationEntitlements;
+ (NSDictionary *)getApplicationSignatureInfo;

+ (NSString *)formatEntitlementsAsPlist:(NSDictionary *)entitlements;

// TODO: remove before initial release
+ (void)showDevelopmentBuildBanner;

@end