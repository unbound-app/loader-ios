#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <rootless.h>
#import <sys/utsname.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>

#import "FileSystem.h"
#import "Unbound.h"

#define CS_DEBUGGED 0x10000000
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

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

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
      warning:(BOOL)warning;

+ (void)alert:(NSString *)message
        title:(NSString *)title
      warning:(BOOL)warning;

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
          tts:(BOOL)tts;

+ (void)alert:(NSString *)message
        title:(NSString *)title
          tts:(BOOL)tts;

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
      warning:(BOOL)warning
          tts:(BOOL)tts;

+ (void)alert:(NSString *)message
        title:(NSString *)title
      warning:(BOOL)warning
          tts:(BOOL)tts;

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
      timeout:(NSInteger)timeout
      warning:(BOOL)warning;

+ (void)alert:(NSString *)message
        title:(NSString *)title
      timeout:(NSInteger)timeout
      warning:(BOOL)warning;

+ (void)alert:(NSString *)message
        title:(NSString *)title
      buttons:(NSArray<UIAlertAction *> *)buttons
      timeout:(NSInteger)timeout
      warning:(BOOL)warning
          tts:(BOOL)tts;

+ (void)alert:(NSString *)message
        title:(NSString *)title
      timeout:(NSInteger)timeout
      warning:(BOOL)warning
          tts:(BOOL)tts;

+ (void)alertWarning:(NSString *)message
               title:(NSString *)title
             timeout:(NSInteger)timeout;

+ (void)speakAlertContent:(NSString *)title message:(NSString *)message;

+ (UIAlertAction *)createDiscordInviteButton;

+ (void)presentAlert:(NSString *)message
               title:(NSString *)title
             buttons:(NSArray<UIAlertAction *> *)buttons
             timeout:(NSInteger)timeout
             warning:(BOOL)warning
                 tts:(BOOL)tts;

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
+ (NSString *)getiOSVersionString;
+ (BOOL)deviceHasDynamicIsland;
+ (void)initializeDynamicIslandOverlay;
+ (void)showDynamicIslandOverlay;
+ (void)hideDynamicIslandOverlay;
+ (void)showDevelopmentBuildBanner;

+ (BOOL)isLoadedWithElleKit;

+ (NSArray<NSString *> *)getAvailableAppExtensions;
+ (BOOL)hasAppExtension:(NSString *)extensionName;

+ (NSString *)getCurrentDylibName;

+ (NSDictionary *)getApplicationEntitlements;
+ (NSDictionary *)getApplicationSignatureInfo;

+ (NSString *)formatEntitlementsAsPlist:(NSDictionary *)entitlements;
+ (BOOL)isVerifiedBuild;
+ (BOOL)hasDiscordProductionEntitlements;
+ (BOOL)isJITAvailable;

+ (NSString *)JSONString:(NSString *)str;

@end
