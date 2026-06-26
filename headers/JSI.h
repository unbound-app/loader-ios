#pragma once

#import <Foundation/Foundation.h>
#import <functional>
#import <jsi/jsi.h>

// Shared facebook::jsi helpers for the bridgeless loader path. Importable only from
// ObjC++ TUs (selectors reference facebook::jsi types) — every JSI consumer is a .xm,
// mirroring the RCTInstance.h / UnboundNative.h C++-exposing header precedent.
@interface JSI : NSObject

// ObjC <-> JSI value conversion
+ (facebook::jsi::Value)fromObjC:(id)value runtime:(facebook::jsi::Runtime &)runtime;
+ (NSString *)toNSString:(const facebook::jsi::Value &)value
                 runtime:(facebook::jsi::Runtime &)runtime;
+ (BOOL)toBool:(const facebook::jsi::Value &)value
       runtime:(facebook::jsi::Runtime &)runtime
      fallback:(BOOL)fallback;
+ (double)toNumber:(const facebook::jsi::Value &)value fallback:(double)fallback;

// Host function creation
+ (facebook::jsi::Value)makeFunction:(const char *)name
                            argCount:(unsigned int)argCount
                             runtime:(facebook::jsi::Runtime &)runtime
                             handler:(const facebook::jsi::HostFunctionType &)handler;

// Script / bytecode evaluation (source or Hermes bytecode; logs JSError/std::exception)
+ (void)evaluate:(NSData *)scriptData tag:(NSString *)tag runtime:(facebook::jsi::Runtime &)runtime;

@end
