#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>
#import <spawn.h>
#import <sys/utsname.h>

#import "DeviceModels.h"
#import "FileSystem.h"
#import "Settings.h"
#import "Updater.h"
#import "Utilities.h"

BOOL      isRecoveryModeEnabled(void);
NSString *getDeviceIdentifier(void);
void      showMenuSheet(void);
void      reloadApp(UIViewController *viewController);

extern id gBridge;

@interface UnboundMenuViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;

- (void)dismiss;

@end

@interface                                             UnboundMenuViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *menuSections;
@end