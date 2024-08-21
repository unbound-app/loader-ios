#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>

#import "FileSystem.h"
#import "Utilities.h"
#import "Settings.h"
#import "Updater.h"
#import "Plugins.h"
#import "Themes.h"
#import "Fonts.h"

#include "./hermes/RCT.h"

#ifdef DEBUG
#   define IS_DEBUG true
#   define NSLog(fmt, ... ) NSLog((@"[Unbound] " fmt), ##__VA_ARGS__);
#else
#   define IS_DEBUG false
#   define NSLog(...) (void)0
#endif

# ifdef THEOS_PACKAGE_INSTALL_PREFIX
#   define BUNDLE_PATH @THEOS_PACKAGE_INSTALL_PREFIX "/Library/Application Support/UnboundResources.bundle"
# else
#   define BUNDLE_PATH @"/Library/Application Support/UnboundResources.bundle"
# endif