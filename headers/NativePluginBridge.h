#pragma once

#import <Foundation/Foundation.h>
#import <jsi/jsi.h>

namespace unbound {

constexpr const char *kNativePluginApiVersion = "1.0.0";
constexpr const char *kNativePluginAbiVersion = "1.0.0";

void registerNativePluginBridge(facebook::jsi::Runtime &runtime);
void setNativePluginRuntimeExecutor(id instance);

}
