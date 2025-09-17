#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <SafariServices/SafariServices.h>
#import <objc/message.h>
#import <spawn.h>
#import <sys/utsname.h>

#import "FileSystem.h"
#import "Settings.h"
#import "Updater.h"
#import "Utilities.h"
#import "MobileGestalt.h"

void      showToolboxSheet(void);
void      reloadApp(UIViewController *viewController);

@interface Toolbox : NSObject
+ (void)showToolboxMenu;
@end

@interface UnboundToolboxViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, SFSafariViewControllerDelegate>

@property (nonatomic, strong) UITableView *tableView;

- (void)dismiss;

@end

@interface                                                 UnboundToolboxViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *menuSections;
@end