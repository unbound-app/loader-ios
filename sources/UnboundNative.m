#import "UnboundNative.h"

@implementation UnboundNative

+ (NSString *)moduleName { return @"UnboundNative"; }
+ (BOOL)requiresMainQueueSetup { return NO; }

RCT_REMAP_METHOD(alert,
                 alertMessage:(NSString *)message
                 options:(NSDictionary *)options
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  if (![message isKindOfClass:[NSString class]] || message.length == 0) {
    reject(@"EINVAL", @"message must be a non-empty string", nil);
    return;
  }

  NSString *title    = ([options isKindOfClass:[NSDictionary class]] ? options[@"title"]    : nil);
  NSNumber *timeoutN = ([options isKindOfClass:[NSDictionary class]] ? options[@"timeout"]  : nil);
  NSNumber *warningN = ([options isKindOfClass:[NSDictionary class]] ? options[@"warning"]  : nil);
  NSNumber *ttsN     = ([options isKindOfClass:[NSDictionary class]] ? options[@"tts"]      : nil);

  NSInteger timeout = timeoutN ? timeoutN.integerValue : 0;
  BOOL warning      = warningN ? warningN.boolValue    : NO;
  BOOL tts          = ttsN     ? ttsN.boolValue        : NO;

  if (title && [title isKindOfClass:[NSString class]] && title.length > 0) {
    [Utilities alert:message title:title timeout:timeout warning:warning tts:tts];
  } else {
    if (timeout == 0 && !warning && !tts) {
      [Utilities alert:message];
    } else {
      [Utilities alert:message title:@"Unbound" timeout:timeout warning:warning tts:tts];
    }
  }

  resolve(@(YES));
}

RCT_REMAP_METHOD(alertSimple,
                 alertSimpleMessage:(NSString *)message
                 title:(NSString *)title
                 resolver2:(RCTPromiseResolveBlock)resolve
                 rejecter2:(RCTPromiseRejectBlock)reject)
{
  if (![message isKindOfClass:[NSString class]] || message.length == 0) {
    reject(@"EINVAL", @"message must be a non-empty string", nil);
    return;
  }

  if ([title isKindOfClass:[NSString class]] && title.length > 0) {
    [Utilities alert:message title:title];
  } else {
    [Utilities alert:message];
  }

  resolve(@(YES));
}

RCT_REMAP_METHOD(echo,
  echo:(NSString *)text
  resolver:(RCTPromiseResolveBlock)resolve
  rejecter:(RCTPromiseRejectBlock)reject)
{
  if (text.length == 0) { reject(@"EINVAL",@"empty",nil); return; }
  resolve([@"echo:" stringByAppendingString:text]);
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(isEnabled)
{
  return @(YES);
}

@end
