#import "Menu.h"

extern id gBridge;

BOOL isRecoveryModeEnabled(void) {
  return [Settings getBoolean:@"unbound" key:@"recovery" def:NO];
}

@interface UnboundMenuViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *menuSections;
@end

@implementation UnboundMenuViewController {
    BOOL isJailbroken;
}

- (NSString *)bundlePath {
    return [NSString pathWithComponents:@[FileSystem.documents, @"unbound.bundle"]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    isJailbroken = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
    [self setupTableView];
    [self setupMenuItems];
}

- (void)setupTableView {
    self.title = [NSString stringWithFormat:@"Unbound v%@ Recovery Menu", PACKAGE_VERSION];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupMenuItems {
    self.menuSections = @[
        @{
            @"title": @"",
            @"items": @[
                @{
                    @"title": isRecoveryModeEnabled() ? @"Disable Recovery Mode" : @"Enable Recovery Mode",
                    @"icon": @"shield",
                    @"selector": NSStringFromSelector(@selector(toggleRecoveryMode))
                }
            ]
        },
        @{
            @"title": @"Bundle",
            @"items": @[
                @{
                    @"title": @"Refetch Bundle",
                    @"icon": @"arrow.triangle.2.circlepath",
                    @"selector": NSStringFromSelector(@selector(refetchBundle))
                },
                @{
                    @"title": @"Delete Bundle",
                    @"icon": @"trash",
                    @"destructive": @YES,
                    @"selector": NSStringFromSelector(@selector(deleteBundle))
                },
                @{
                    @"title": @"Switch Bundle Version",
                    @"icon": @"arrow.triangle.2.circlepath.circle",
                    @"selector": NSStringFromSelector(@selector(switchBundleVersion))
                },
                @{
                    @"title": @"Load Custom Bundle",
                    @"icon": @"link.badge.plus",
                    @"selector": NSStringFromSelector(@selector(loadCustomBundle))
                }
            ]
        },
        @{
            @"title": @"Addons",
            @"items": @[
                @{
                    @"title": @"Wipe Plugins",
                    @"icon": @"trash",
                    @"destructive": @YES,
                    @"selector": NSStringFromSelector(@selector(wipePlugins))
                },
                @{
                    @"title": @"Wipe Themes",
                    @"icon": @"trash",
                    @"destructive": @YES,
                    @"selector": NSStringFromSelector(@selector(wipeThemes))
                },
                @{
                    @"title": @"Wipe Fonts",
                    @"icon": @"trash",
                    @"destructive": @YES,
                    @"selector": NSStringFromSelector(@selector(wipeFonts))
                },
                @{
                    @"title": @"Wipe Icon Packs",
                    @"icon": @"trash",
                    @"destructive": @YES,
                    @"selector": NSStringFromSelector(@selector(wipeIconPacks))
                }
            ]
        },
        @{
            @"title": @"Utilities",
            @"items": @[
                @{
                    @"title": @"Factory Reset",
                    @"icon": @"trash.fill",
                    @"destructive": @YES,
                    @"selector": NSStringFromSelector(@selector(factoryReset))
                },
                @{
                    @"title": @"Open App Folder",
                    @"icon": @"folder",
                    @"selector": NSStringFromSelector(@selector(openAppFolder))
                },
                @{
                    @"title": @"Open GitHub Issue",
                    @"icon": @"exclamationmark.bubble",
                    @"selector": NSStringFromSelector(@selector(openGitHubIssue))
                }
            ]
        },
        @{
            @"title": @"Settings",
            @"items": @[
                @{
                    @"title": @"Enable Shake Motion",
                    @"icon": @"iphone.gen3.radiowaves.left.and.right",
                    @"isSwitch": @YES,
                    @"key": @"UnboundShakeGestureEnabled"
                },
                @{
                    @"title": @"Enable Three Finger Press",
                    @"icon": @"hand.tap",
                    @"isSwitch": @YES,
                    @"key": @"UnboundThreeFingerGestureEnabled"
                }
            ]
        }
    ];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.menuSections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.menuSections[section][@"title"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.menuSections[section][@"items"] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
    }
    
    cell.accessoryView = nil;
    
    NSDictionary *item = self.menuSections[indexPath.section][@"items"][indexPath.row];
    
    cell.textLabel.text = item[@"title"];
    
    UIImageConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    UIImage *icon = [UIImage systemImageNamed:item[@"icon"] withConfiguration:config];
    cell.imageView.image = icon;
    cell.imageView.tintColor = [item[@"destructive"] boolValue] ? UIColor.systemRedColor : UIColor.systemBlueColor;
    
    if ([item[@"isSwitch"] boolValue]) {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.tag = indexPath.row;
        [toggle addTarget:self action:@selector(toggleSetting:) forControlEvents:UIControlEventValueChanged];
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        toggle.on = [defaults objectForKey:item[@"key"]] == nil ? YES : [defaults boolForKey:item[@"key"]];
        
        cell.accessoryView = toggle;
    }
    
    return cell;
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *item = self.menuSections[indexPath.section][@"items"][indexPath.row];
    
    if ([item[@"destructive"] boolValue]) {
        [self showDestructiveConfirmation:item[@"title"] selectorName:item[@"selector"]];
    } else if (item[@"selector"]) {
        [self executeActionWithSelectorName:item[@"selector"]];
    }
}

#pragma mark - Actions

- (void)showDestructiveConfirmation:(NSString *)action selectorName:(NSString *)selectorName {
    NSString *message = @"Are you sure you want to do this?";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Confirm Action"
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Confirm" 
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction *action) {
        [self executeActionWithSelectorName:selectorName];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)executeActionWithSelectorName:(NSString *)selectorName {
    SEL selector = NSSelectorFromString(selectorName);
    if ([self respondsToSelector:selector]) {
        IMP imp = [self methodForSelector:selector];
        void (*func)(id, SEL) = (void *)imp;
        func(self, selector);
    }
}

// Action methods
- (void)toggleRecoveryMode {
    BOOL currentValue = isRecoveryModeEnabled();
    [Settings set:@"unbound" key:@"recovery" value:@(!currentValue)];
    [self dismiss];
    reloadApp(self);
}

- (void)refetchBundle {
    [Updater downloadBundle:[self bundlePath]];
    [self dismiss];
	reloadApp(self);
}

- (void)deleteBundle {
    [Settings set:@"unbound" key:@"loader.update.url" value:nil];
	[Settings set:@"unbound" key:@"loader.update.force" value:nil];

    [[NSFileManager defaultManager] removeItemAtPath:[self bundlePath] error:nil];
    [self dismiss];
    reloadApp(self);
}

- (void)switchBundleVersion {
    [self dismiss];
}

- (void)loadCustomBundle {
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:@"Load Custom Bundle"
        message:@"Enter the URL for your custom bundle:"
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"https://example.com/file.bundle";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Load" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *urlString = alert.textFields.firstObject.text;
        if (urlString.length > 0) {
            [Settings set:@"unbound" key:@"loader.update.url" value:urlString];
			[Settings set:@"unbound" key:@"loader.update.force" value:true];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [Updater downloadBundle:[self bundlePath]];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self dismissViewControllerAnimated:YES completion:^{
                        reloadApp(self);
                    }];
                });
            });
        }
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wipePlugins {
	[[NSFileManager defaultManager] removeItemAtPath:[FileSystem.documents stringByAppendingPathComponent:@"Plugins"] error:nil];
    [self dismiss];
	reloadApp(self);
}

- (void)wipeThemes {
    [[NSFileManager defaultManager] removeItemAtPath:[FileSystem.documents stringByAppendingPathComponent:@"Themes"] error:nil];
	[self dismiss];
	reloadApp(self);
}

- (void)wipeFonts {
    [[NSFileManager defaultManager] removeItemAtPath:[FileSystem.documents stringByAppendingPathComponent:@"Fonts"] error:nil];
	[self dismiss];
	reloadApp(self);
}

- (void)wipeIconPacks {
    [[NSFileManager defaultManager] removeItemAtPath:[FileSystem.documents stringByAppendingPathComponent:@"Icons"] error:nil];
	[self dismiss];
	reloadApp(self);
}

- (void)factoryReset {
	[[NSFileManager defaultManager] removeItemAtPath:FileSystem.documents error:nil];
	[self dismiss];
	reloadApp(self);
}

- (void)openAppFolder {
	if (isJailbroken) {
        NSString *filzaPath = [NSString stringWithFormat:@"filza://view%@", FileSystem.documents];
        NSURL *filzaURL = [NSURL URLWithString:[filzaPath stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
        
        if ([[UIApplication sharedApplication] canOpenURL:filzaURL]) {
            [[UIApplication sharedApplication] openURL:filzaURL options:@{} completionHandler:nil];
            return;
        }
    }
    
    NSString *sharedPath = [NSString stringWithFormat:@"shareddocuments://%@", FileSystem.documents];
    NSURL *sharedUrl = [NSURL URLWithString:sharedPath];
    
    [[UIApplication sharedApplication] openURL:sharedUrl options:@{} completionHandler:nil];
}

- (void)openGitHubIssue {
	UIDevice *device      = [UIDevice currentDevice];
    NSString *deviceId    = getDeviceIdentifier();
    NSString *deviceModel = DEVICE_MODELS[deviceId] ?: deviceId;
    NSString *appVersion =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *buildNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];

    NSString *body =
        [NSString stringWithFormat:@"### Device Information\n"
                                    "- Device: %@\n"
                                    "- iOS Version: %@\n"
                                    "- Tweak Version: %@\n"
                                    "- App Version: %@ (%@)\n"
                                    "- Jailbroken: %@\n\n"
                                    "### Issue Description\n"
                                    "<!-- Describe your issue here -->\n\n"
                                    "### Steps to Reproduce\n"
                                    "1. \n2. \n3. \n\n"
                                    "### Expected Behavior\n\n"
                                    "### Actual Behavior\n",
                                   deviceModel, device.systemVersion, PACKAGE_VERSION, appVersion,
                                   buildNumber, isJailbroken ? @"Yes" : @"No"];

    NSString *encodedTitle = [@"bug(iOS): "
        stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet
                                                               URLQueryAllowedCharacterSet]];
    NSString *encodedBody =
        [body stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet
                                                                     URLQueryAllowedCharacterSet]];

    NSString *urlString = [NSString
        stringWithFormat:@"https://github.com/unbound-mod/client/issues/new?title=%@&body=%@",
                         encodedTitle, encodedBody];
    NSURL *url          = [NSURL URLWithString:urlString];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)toggleSetting:(UISwitch *)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if (sender.tag == 0) { // Shake gesture
        [defaults setBool:sender.on forKey:@"UnboundShakeGestureEnabled"];
        if (!sender.on) {
            // If shake is being disabled, ensure three finger is enabled
            [defaults setBool:YES forKey:@"UnboundThreeFingerGestureEnabled"];
            
            // Find the cell containing the other switch
            UITableViewCell *otherCell = [self.tableView cellForRowAtIndexPath:
                [NSIndexPath indexPathForRow:1 inSection:4]];
            if (otherCell) {
                UISwitch *otherSwitch = (UISwitch *)otherCell.accessoryView;
                if ([otherSwitch isKindOfClass:[UISwitch class]]) {
                    [otherSwitch setOn:YES animated:YES];
                }
            }
        }
    } else { // Three finger gesture
        [defaults setBool:sender.on forKey:@"UnboundThreeFingerGestureEnabled"];
        if (!sender.on) {
            // If three finger is being disabled, ensure shake is enabled
            [defaults setBool:YES forKey:@"UnboundShakeGestureEnabled"];
            
            // Find the cell containing the other switch
            UITableViewCell *otherCell = [self.tableView cellForRowAtIndexPath:
                [NSIndexPath indexPathForRow:0 inSection:4]];
            if (otherCell) {
                UISwitch *otherSwitch = (UISwitch *)otherCell.accessoryView;
                if ([otherSwitch isKindOfClass:[UISwitch class]]) {
                    [otherSwitch setOn:YES animated:YES];
                }
            }
        }
    }
    [defaults synchronize];
}

- (void)dismiss {
  [self dismissViewControllerAnimated:YES completion:nil];
}

void showMenuSheet(void) {
  UnboundMenuViewController *settingsVC =
      [[UnboundMenuViewController alloc] init];

  UINavigationController *navController =
      [[UINavigationController alloc] initWithRootViewController:settingsVC];
  navController.modalPresentationStyle = UIModalPresentationFormSheet;

  UIBarButtonItem *doneButton = [[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                           target:settingsVC
                           action:@selector(dismiss)];
  settingsVC.navigationItem.rightBarButtonItem = doneButton;

  UIWindow *window = nil;
  NSSet *scenes = [[UIApplication sharedApplication] connectedScenes];
  for (UIScene *scene in scenes) {
    if (scene.activationState == UISceneActivationStateForegroundActive) {
      window = ((UIWindowScene *)scene).windows.firstObject;
      break;
    }
  }

  if (!window) {
    window = [[UIApplication sharedApplication] windows].firstObject;
  }

  if (window && window.rootViewController) {
    [window.rootViewController presentViewController:navController
                                            animated:YES
                                          completion:nil];
  }
}

@end

NSString *getDeviceIdentifier(void) {
  struct utsname systemInfo;
  uname(&systemInfo);
  return [NSString stringWithCString:systemInfo.machine
                            encoding:NSUTF8StringEncoding];
}

void reloadApp(UIViewController *viewController) {
  [viewController
      dismissViewControllerAnimated:NO
                         completion:^{
                           if (gBridge &&
                               [gBridge isKindOfClass:NSClassFromString(
                                                          @"RCTCxxBridge")]) {
                             SEL reloadSelector =
                                 NSSelectorFromString(@"reload");
                             if ([gBridge respondsToSelector:reloadSelector]) {
                               ((void (*)(id, SEL))objc_msgSend)(
                                   gBridge, reloadSelector);
                               return;
                             }
                           }

                           UIApplication *app =
                               [UIApplication sharedApplication];
                           ((void (*)(id, SEL))objc_msgSend)(app, @selector
                                                             (suspend));
                           dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                                        0.5 * NSEC_PER_SEC),
                                          dispatch_get_main_queue(), ^{
                                            exit(0);
                                          });
                         }];
}
