#pragma once

#import <jsi/jsi.h>

namespace unbound {
void registerNativeInterop(facebook::jsi::Runtime &runtime);
}
