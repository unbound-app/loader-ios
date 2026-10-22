#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CoreBridge : NSObject

+ (void)installLogging;

+ (NSMutableArray *)scanPluginsIn:(NSString *)documents;
+ (NSMutableArray *)scanThemesIn:(NSString *)documents;
+ (NSMutableArray *)scanFontsIn:(NSString *)documents
                   nameResolver:(NSString *_Nullable (^)(NSString *path))resolver;

+ (NSData *)preloadScriptWithSettings:(NSString *)settings
                              plugins:(NSString *)plugins
                               themes:(NSString *)themes
                                fonts:(NSString *)fonts
                       availableFonts:(NSString *)availableFonts
                               origin:(NSString *)origin
                              version:(NSString *)version;

@end

NS_ASSUME_NONNULL_END
