#pragma once

#import <Foundation/Foundation.h>
#import <jsi/jsi.h>

namespace unbound {
void registerNativePlatform(facebook::jsi::Runtime &runtime);
}
