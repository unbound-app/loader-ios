#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>
#import <spawn.h>
#import <sys/utsname.h>

#import "DeviceModels.h"
#import "FileSystem.h"

@interface UnboundMenuViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end

extern id gBridge;
extern BOOL isJailbroken;
BOOL isSafeModeEnabled(void);
NSString *getDeviceIdentifier(void);
void reloadApp(UIViewController *viewController);
void deletePlugins(void);
void deleteThemes(void);
void deleteAllData(UIViewController *presenter);
void refetchBundle(UIViewController *presenter);
void toggleSafeMode(void);
void setCustomBundleURL(NSURL *url, UIViewController *presenter);
void resetCustomBundleURL(UIViewController *presenter);
void showBundleSelector(UIViewController *presenter);
void removeCachedBundle(void);
void gracefulExit(UIViewController *presenter);
void deletePluginsAndReload(UIViewController *presenter);
void deleteThemesAndReload(UIViewController *presenter);
void showMenuSheet(void);