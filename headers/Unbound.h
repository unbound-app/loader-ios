#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>

#import "FileSystem.h"
#import "Utilities.h"
#import "Settings.h"
#import "Fonts.h"
#import "Updater.h"
#import "Plugins.h"
#import "Themes.h"
#import "Menu.h"

#include "./Discord/RCT.h"

#ifdef DEBUG
#   define IS_DEBUG true
#   define NSLog(fmt, ... ) NSLog((@"[Unbound] " fmt), ##__VA_ARGS__);
#else
#   define IS_DEBUG false
#   define NSLog(...) (void)0
#endif