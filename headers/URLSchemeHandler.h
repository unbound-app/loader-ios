#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Simple handler for unbound:// URL scheme
 */
@interface URLSchemeHandler : NSObject

/**
 * Shared instance
 */
+ (instancetype)sharedHandler;

/**
 * Handle an incoming URL
 * @return Result string or nil if URL couldn't be handled
 */
- (nullable NSString *)handleURL:(NSURL *)url;

/**
 * Initialize the handler
 */
- (void)initialize;

@end

NS_ASSUME_NONNULL_END
