#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import "Logger.h"

NS_ASSUME_NONNULL_BEGIN

typedef CFTypeRef _Nullable (*MGCopyAnswerFunction)(CFStringRef key);

@interface MobileGestalt : NSObject

+ (instancetype)sharedInstance;

- (nullable NSString *)getProductName;
- (nullable NSString *)getProductType;
- (nullable NSString *)getProductVersion;
- (nullable NSString *)getBuildVersion;
- (nullable NSString *)getDeviceClass;
- (nullable NSString *)getPhysicalHardwareNameString;
- (nullable NSString *)getBoardId;
- (nullable NSString *)getDeviceColor;
- (nullable NSString *)getRegionInfo;
- (nullable NSString *)getCPUArchitecture;
- (nullable NSString *)getFirmwareVersion;
- (nullable NSString *)getHWModelStr;
- (nullable NSString *)getIsVirtualDevice;
- (nullable NSString *)getSoftwareBehavior;
- (nullable NSString *)getPartitionType;

- (nullable NSString *)getValueForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
