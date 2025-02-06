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
- (void)dismiss;
@end

extern id gBridge;

BOOL isSafeModeEnabled(void);
NSString *getDeviceIdentifier(void);
void showMenuSheet(void);
void reloadApp(UIViewController *viewController);