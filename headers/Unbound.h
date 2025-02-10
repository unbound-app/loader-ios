#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>

#import "FileSystem.h"
#import "Fonts.h"
#import "Plugins.h"
#import "Settings.h"
#import "Themes.h"
#import "Updater.h"
#import "Utilities.h"

#include "Discord/RCT.h"

#ifdef DEBUG
#define IS_DEBUG        true
#define NSLog(fmt, ...) NSLog((@"[Unbound] " fmt), ##__VA_ARGS__);
#else
#define IS_DEBUG   false
#define NSLog(...) (void) 0
#endif