#pragma once

#include "AndroidLoader.h"

namespace unbound::android
{
    void registerNativePluginBridge(facebook::jsi::Runtime &runtime,
                                    const JavaCallbacks &callbacks);
}
