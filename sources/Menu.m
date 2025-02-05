#import "Menu.h"

extern id gBridge;

BOOL isJailbroken = NO;

@implementation UnboundMenuViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title =
      [NSString stringWithFormat:@"Unbound v%@ Recovery Menu", PACKAGE_VERSION];
  self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

  self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                   style:UITableViewStyleInsetGrouped];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.delegate = self;
  self.tableView.dataSource = self;
  [self.view addSubview:self.tableView];

  [NSLayoutConstraint activateConstraints:@[
    [self.tableView.topAnchor
        constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
  ]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5; // No Header, Bundle, Addons, Utilities, Settings
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return nil;
        case 1: return @"Bundle";
        case 2: return @"Addons";
        case 3: return @"Utilities";
        case 4: return @"Settings";
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1;  // Safe Mode
        case 1: return 4;  // Bundle items
        case 2: return 4;  // Addon items
        case 3: return 3;  // Utility items
        case 4: return 2;  // Settings items
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
    }
    
    // Clear any existing accessory view (important for cell reuse)
    cell.accessoryView = nil;

    NSString *title;
    NSString *icon;
    BOOL destructive = NO;

    switch (indexPath.section) {
        case 0: // No header
            title = isSafeModeEnabled() ? @"Disable Safe Mode" : @"Enable Safe Mode";
            icon = @"shield";
            break;
        
        case 1: // Bundle
            switch (indexPath.row) {
                case 0:
                    title = @"Refetch Bundle";
                    icon = @"arrow.triangle.2.circlepath";
                    break;
                case 1:
                    title = @"Delete Bundle";
                    icon = @"trash";
                    destructive = YES;
                    break;
                case 2:
                    title = @"Switch Bundle Version";
                    icon = @"arrow.triangle.2.circlepath.circle";
                    break;
                case 3:
                    title = @"Load Custom Bundle";
                    icon = @"link.badge.plus";
                    break;
            }
            break;

        case 2: // Addons
            switch (indexPath.row) {
                case 0:
                    title = @"Wipe Plugins";
                    icon = @"trash";
                    destructive = YES;
                    break;
                case 1:
                    title = @"Wipe Themes";
                    icon = @"trash";
                    destructive = YES;
                    break;
                case 2:
                    title = @"Wipe Fonts";
                    icon = @"trash";
                    destructive = YES;
                    break;
                case 3:
                    title = @"Wipe Icon Packs";
                    icon = @"trash";
                    destructive = YES;
                    break;
            }
            break;

        case 3: // Utilities
            switch (indexPath.row) {
                case 0:
                    title = @"Factory Reset";
                    icon = @"trash.fill";
                    destructive = YES;
                    break;
                case 1:
                    title = @"Open App Folder";
                    icon = @"folder";
                    break;
                case 2:
                    title = @"Open GitHub Issue";
                    icon = @"exclamationmark.bubble";
                    break;
            }
            break;

        case 4: // Settings
            switch (indexPath.row) {
                case 0:
                    title = @"Enable Shake Motion";
                    icon = @"iphone.gen3.radiowaves.left.and.right";
                    break;
                case 1:
                    title = @"Enable Three Finger Press";
                    icon = @"hand.tap";
                    break;
            }
            break;
    }

    cell.textLabel.text = title;
    
    UIImageConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    UIImage *iconImage = [UIImage systemImageNamed:icon withConfiguration:config];
    cell.imageView.image = iconImage;
    cell.imageView.tintColor = destructive ? UIColor.systemRedColor : UIColor.systemBlueColor;

    if (indexPath.section == 4) {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.tag = indexPath.row;
        [toggle addTarget:self action:@selector(toggleSetting:) forControlEvents:UIControlEventValueChanged];
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if (indexPath.row == 0) {
            toggle.on = [defaults objectForKey:@"UnboundShakeGestureEnabled"] == nil ? YES : [defaults boolForKey:@"UnboundShakeGestureEnabled"];
        } else {
            toggle.on = [defaults objectForKey:@"UnboundThreeFingerGestureEnabled"] == nil ? YES : [defaults boolForKey:@"UnboundThreeFingerGestureEnabled"];
        }
        
        cell.accessoryView = toggle;
    }

    return cell;
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

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];

  if (indexPath.section == 0) {
    toggleSafeMode();
    return;
  }

  if (indexPath.section == 1 && indexPath.row == 2) {
    showBundleSelector(self);
    return;
  }

  void (^performAction)(void) = ^{
    switch (indexPath.section) {
    case 1:
      switch (indexPath.row) {
        case 0:
          refetchBundle(self);
          break;
        case 1:
          resetCustomBundleURL(self);
          break;
        case 3:
          [self loadCustomBundle];
          break;
      }
      break;
    case 2:
      switch (indexPath.row) {
        case 0:
          deletePluginsAndReload(self);
          break;
        case 1:
          deleteThemesAndReload(self);
          break;
        case 2:
          deleteAllData(self);
          break;
      }
      break;
    case 3:
      switch (indexPath.row) {
        case 1:
          [self openDocumentsDirectory];
          break;
        case 2:
          [self openGitHub];
          break;
      }
      break;
    }
  };

  if (indexPath.section != 4 && indexPath.row != 3 && indexPath.row != 8 && indexPath.row != 9) {
    NSString *actionText;
    switch (indexPath.section) {
    case 1:
      switch (indexPath.row) {
        case 0:
          actionText = @"refetch the bundle";
          break;
        case 1:
          actionText = @"reset the bundle";
          break;
      }
      break;
    case 2:
      switch (indexPath.row) {
        case 0:
          actionText = @"delete all plugins";
          break;
        case 1:
          actionText = @"delete all themes";
          break;
        case 2:
          actionText = @"delete all mod data";
          break;
      }
      break;
    default:
      actionText = @"perform this action";
      break;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Confirm Action"
                         message:[NSString stringWithFormat:
                                               @"Are you sure you want to %@?",
                                               actionText]
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert
        addAction:[UIAlertAction actionWithTitle:@"Confirm"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
                                           performAction();
                                         }]];

    [self presentViewController:alert animated:YES completion:nil];
  } else {
    performAction();
  }
}

- (void)openDocumentsDirectory {
  if (isJailbroken) {
    NSString *filzaPath =
        [NSString stringWithFormat:@"filza://view%@", FileSystem.documents];
    NSURL *filzaURL = [NSURL
        URLWithString:[filzaPath
                          stringByAddingPercentEncodingWithAllowedCharacters:
                              [NSCharacterSet URLQueryAllowedCharacterSet]]];

    if ([[UIApplication sharedApplication] canOpenURL:filzaURL]) {
      [[UIApplication sharedApplication] openURL:filzaURL
                                         options:@{}
                               completionHandler:nil];
      return;
    }
  }

  NSString *sharedPath =
      [NSString stringWithFormat:@"shareddocuments://%@", FileSystem.documents];
  NSURL *sharedUrl = [NSURL URLWithString:sharedPath];

  [[UIApplication sharedApplication] openURL:sharedUrl
                                     options:@{}
                           completionHandler:nil];
}

- (void)openGitHub {
  UIDevice *device = [UIDevice currentDevice];
  NSString *deviceId = getDeviceIdentifier();
  NSString *deviceModel = DEVICE_MODELS[deviceId] ?: deviceId;
  NSString *appVersion = [[NSBundle mainBundle]
      objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
  NSString *buildNumber =
      [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];

  NSString *body = [NSString
      stringWithFormat:@"### Device Information\n"
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
                       deviceModel, device.systemVersion, PACKAGE_VERSION,
                       appVersion, buildNumber, isJailbroken ? @"Yes" : @"No"];

  NSString *encodedTitle =
      [@"bug(iOS): " stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLQueryAllowedCharacterSet]];
  NSString *encodedBody =
      [body stringByAddingPercentEncodingWithAllowedCharacters:
                [NSCharacterSet URLQueryAllowedCharacterSet]];

  NSString *urlString = [NSString
      stringWithFormat:
          @"https://github.com/unbound-mod/client/issues/new?title=%@&body=%@",
          encodedTitle, encodedBody];
  NSURL *url = [NSURL URLWithString:urlString];
  [[UIApplication sharedApplication] openURL:url
                                     options:@{}
                           completionHandler:nil];
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

  UIAlertAction *loadAction = [UIAlertAction
      actionWithTitle:@"Load"
                style:UIAlertActionStyleDefault
              handler:^(UIAlertAction *action) {
                NSString *urlString = alert.textFields.firstObject.text;
                if (urlString.length == 0) {
                  [self presentViewController:alert
                                     animated:YES
                                   completion:nil];
                  [Utilities alert:@"Please enter a URL" title:@"Invalid URL"];
                  return;
                }

                NSURL *url = [NSURL URLWithString:urlString];
                if (!url || !url.scheme || !url.host) {
                  [self presentViewController:alert
                                     animated:YES
                                   completion:nil];
                  [Utilities alert:@"Please enter a valid URL (e.g., "
                                   @"https://example.com/bundle.js)"
                             title:@"Invalid URL"];
                  return;
                }

                if (![url.scheme isEqualToString:@"http"] &&
                    ![url.scheme isEqualToString:@"https"]) {
                  [self presentViewController:alert
                                     animated:YES
                                   completion:nil];
                  [Utilities alert:@"URL must start with http:// or https://"
                             title:@"Invalid URL"];
                  return;
                }

                NSURLSession *session = [NSURLSession
                    sessionWithConfiguration:[NSURLSessionConfiguration
                                                 defaultSessionConfiguration]];
                [[session
                      dataTaskWithURL:url
                    completionHandler:^(NSData *data, NSURLResponse *response,
                                        NSError *error) {
                      dispatch_async(dispatch_get_main_queue(), ^{
                        if (error) {
                          [self presentViewController:alert
                                             animated:YES
                                           completion:nil];
                          [Utilities
                              alert:[NSString stringWithFormat:
                                                  @"Could not reach URL: %@",
                                                  error.localizedDescription]
                              title:@"Connection Error"];
                          return;
                        }

                        if (!data) {
                          [self presentViewController:alert
                                             animated:YES
                                           completion:nil];
                          [Utilities alert:@"No data received from URL"
                                     title:@"Error"];
                          return;
                        }

                        NSHTTPURLResponse *httpResponse =
                            (NSHTTPURLResponse *)response;
                        if (httpResponse.statusCode != 200) {
                          [self presentViewController:alert
                                             animated:YES
                                           completion:nil];
                          [Utilities
                              alert:[NSString stringWithFormat:
                                                  @"Server returned error %ld",
                                                  (long)httpResponse.statusCode]
                              title:@"Error"];
                          return;
                        }

                        setCustomBundleURL(url, self);
                        removeCachedBundle();
                        gracefulExit(self);
                      });
                    }] resume];
              }];

  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [alert addAction:loadAction];

  [self presentViewController:alert animated:YES completion:nil];
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

BOOL isSafeModeEnabled(void) {
  return [Settings getBoolean:@"unbound" key:@"loader.safemode" def:NO];
}

void toggleSafeMode(void) {
  // BOOL current = isSafeModeEnabled();
  gracefulExit(nil);
}

void deletePluginsAndReload(UIViewController *presenter) {
  deletePlugins();
  gracefulExit(presenter);
}

void deleteThemesAndReload(UIViewController *presenter) {
  deleteThemes();
  gracefulExit(presenter);
}

void deleteAllData(UIViewController *presenter) {}

void refetchBundle(UIViewController *presenter) {}

void setCustomBundleURL(NSURL *url, UIViewController *presenter) {}

void resetCustomBundleURL(UIViewController *presenter) {}

void removeCachedBundle(void) {}

void gracefulExit(UIViewController *presenter) {}

void showBundleSelector(UIViewController *presenter) {}

void deletePlugins(void) {}

void deleteThemes(void) {}