#include <Foundation/Foundation.h>

/**
 * Block that bridge modules use to resolve the JS promise waiting for a result.
 * Nil results are supported and are converted to JS's undefined value.
 */
typedef void (^RCTPromiseResolveBlock)(id result);

/**
 * Block that bridge modules use to reject the JS promise waiting for a result.
 * The error may be nil but it is preferable to pass an NSError object for more
 * precise error messages.
 */
typedef void (^RCTPromiseRejectBlock)(NSString *code, NSString *message, NSError *error);

@interface DCDPhotosManager : NSObject {}

- (void) deletePhotos:(NSArray*)uris resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;

@end