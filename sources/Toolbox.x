#import "Toolbox.h"

@implementation Toolbox

+ (void)showToolboxMenu
{
    dispatch_async(dispatch_get_main_queue(), ^{ showToolboxSheet(); });
}

@end

static NSTimeInterval shakeStartTime      = 0;
static BOOL           isShaking           = NO;
static NSHashTable   *windowsWithGestures = nil;

static void addSettingsGestureToWindow(UIWindow *window)
{
    if (!windowsWithGestures)
    {
        windowsWithGestures = [NSHashTable weakObjectsHashTable];
    }

    if (![windowsWithGestures containsObject:window])
    {
        [windowsWithGestures addObject:window];

        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
            initWithTarget:[UIApplication sharedApplication]
                    action:@selector(handleThreeFingerLongPress:)];
        longPress.minimumPressDuration          = 0.5;
        longPress.numberOfTouchesRequired       = 3;
        [window addGestureRecognizer:longPress];
    }
}

static UIImpactFeedbackGenerator *feedbackGenerator = nil;

static void triggerHapticFeedback(void)
{
    if (!feedbackGenerator)
    {
        feedbackGenerator =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    }
    [feedbackGenerator prepare];
    [feedbackGenerator impactOccurred];
}

%hook UIWindow
- (void)becomeKeyWindow
{
    %orig;
    addSettingsGestureToWindow(self);
}

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
    if (motion == UIEventSubtypeMotionShake)
    {
        isShaking      = YES;
        shakeStartTime = [[NSDate date] timeIntervalSince1970];
    }
    %orig;
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
    if (motion == UIEventSubtypeMotionShake && isShaking)
    {
        NSUserDefaults *defaults  = [NSUserDefaults standardUserDefaults];
        BOOL            isEnabled = [defaults objectForKey:@"UnboundShakeGestureEnabled"] == nil
                                        ? YES
                                        : [defaults boolForKey:@"UnboundShakeGestureEnabled"];
        if (isEnabled)
        {
            NSTimeInterval currentTime   = [[NSDate date] timeIntervalSince1970];
            NSTimeInterval shakeDuration = currentTime - shakeStartTime;

            if (shakeDuration >= 0.5 && shakeDuration <= 2.0)
            {
                triggerHapticFeedback();
                dispatch_async(dispatch_get_main_queue(), ^{ showToolboxSheet(); });
            }
        }
        isShaking = NO;
    }
    %orig;
}

%end

%hook UIApplication
%new
- (void)handleThreeFingerLongPress:(UILongPressGestureRecognizer *)gesture
{
    if (gesture.state == UIGestureRecognizerStateBegan)
    {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        BOOL isEnabled = [defaults objectForKey:@"UnboundThreeFingerGestureEnabled"] == nil
                             ? YES
                             : [defaults boolForKey:@"UnboundThreeFingerGestureEnabled"];
        if (isEnabled)
        {
            triggerHapticFeedback();
            showToolboxSheet();
        }
    }
}
%end

@implementation UnboundToolboxViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setupTableView];
    [self setupMenuItems];
}

- (void)setupTableView
{
    self.title                = @"Unbound Toolbox";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate                                  = self;
    self.tableView.dataSource                                = self;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupMenuItems
{
    NSMutableArray *settingsItems =
        [NSMutableArray arrayWithObjects:@{
            @"title" : @"Enable Shake Motion",
            @"icon" : @"iphone.gen3.radiowaves.left.and.right",
            @"isSwitch" : @YES,
            @"key" : @"UnboundShakeGestureEnabled"
        },
                                         @{
                                             @"title" : @"Enable Three Finger Press",
                                             @"icon" : @"hand.tap",
                                             @"isSwitch" : @YES,
                                             @"key" : @"UnboundThreeFingerGestureEnabled"
                                         },
                                         nil];

    if (![Utilities isAppStoreApp] && ![Utilities isTestFlightApp])
    {
        [settingsItems addObject:@{
            @"title" : @"Use Unbound Icon",
            @"icon" : @"app.badge",
            @"isSwitch" : @YES,
            @"key" : @"UnboundAppIconEnabled"
        }];
    }

    self.menuSections = @[
        @{
            @"title" : @"",
            @"items" : @[ @{
                @"title" : [Utilities isRecoveryModeEnabled] ? @"Disable Recovery Mode"
                                                             : @"Enable Recovery Mode",
                @"icon" : @"shield",
                @"selector" : NSStringFromSelector(@selector(toggleRecoveryMode))
            } ]
        },
        @{
            @"title" : @"Bundle",
            @"items" : @[
                @{
                    @"title" : @"Refetch Bundle",
                    @"icon" : @"arrow.triangle.2.circlepath",
                    @"selector" : NSStringFromSelector(@selector(refetchBundle))
                },
                @{
                    @"title" : @"Delete Bundle",
                    @"icon" : @"trash",
                    @"destructive" : @YES,
                    @"selector" : NSStringFromSelector(@selector(deleteBundle))
                },
                @{
                    @"title" : @"Switch Bundle Version",
                    @"icon" : @"arrow.triangle.2.circlepath.circle",
                    @"selector" : NSStringFromSelector(@selector(switchBundleVersion))
                },
                @{
                    @"title" : @"Load Custom Bundle",
                    @"icon" : @"link.badge.plus",
                    @"selector" : NSStringFromSelector(@selector(loadCustomBundle))
                }
            ]
        },
        @{
            @"title" : @"Addons",
            @"items" : @[
                @{
                    @"title" : @"Wipe Plugins",
                    @"icon" : @"trash",
                    @"destructive" : @YES,
                    @"selector" : NSStringFromSelector(@selector(wipePlugins))
                },
                @{
                    @"title" : @"Wipe Themes",
                    @"icon" : @"trash",
                    @"destructive" : @YES,
                    @"selector" : NSStringFromSelector(@selector(wipeThemes))
                },
                @{
                    @"title" : @"Wipe Fonts",
                    @"icon" : @"trash",
                    @"destructive" : @YES,
                    @"selector" : NSStringFromSelector(@selector(wipeFonts))
                },
                @{
                    @"title" : @"Wipe Icon Packs",
                    @"icon" : @"trash",
                    @"destructive" : @YES,
                    @"selector" : NSStringFromSelector(@selector(wipeIconPacks))
                }
            ]
        },
        @{
            @"title" : @"Utilities",
            @"items" : @[
                @{
                    @"title" : @"Factory Reset",
                    @"icon" : @"trash.fill",
                    @"destructive" : @YES,
                    @"selector" : NSStringFromSelector(@selector(factoryReset))
                },
                @{
                    @"title" : @"Open App Folder",
                    @"icon" : @"folder",
                    @"selector" : NSStringFromSelector(@selector(openAppFolder))
                },
                @{
                    @"title" : @"Open GitHub Issue",
                    @"icon" : @"exclamationmark.bubble",
                    @"selector" : NSStringFromSelector(@selector(openGitHubIssue))
                }
            ]
        },
        @{@"title" : @"Settings", @"items" : settingsItems}
    ];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.menuSections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return self.menuSections[section][@"title"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.menuSections[section][@"items"] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"Cell"];
    }

    cell.accessoryView = nil;

    NSDictionary *item = self.menuSections[indexPath.section][@"items"][indexPath.row];

    cell.textLabel.text = item[@"title"];

    UIImageConfiguration *config =
        [UIImageSymbolConfiguration configurationWithPointSize:22
                                                        weight:UIImageSymbolWeightRegular];
    UIImage *icon        = [UIImage systemImageNamed:item[@"icon"] withConfiguration:config];
    cell.imageView.image = icon;
    cell.imageView.tintColor =
        [item[@"destructive"] boolValue] ? UIColor.systemRedColor : UIColor.systemBlueColor;

    if ([item[@"isSwitch"] boolValue])
    {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.tag       = indexPath.row;
        [toggle addTarget:self
                      action:@selector(toggleSetting:)
            forControlEvents:UIControlEventValueChanged];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        if ([item[@"key"] isEqualToString:@"UnboundAppIconEnabled"])
        {
            NSString *currentIcon = [[UIApplication sharedApplication] alternateIconName];
            toggle.on             = [currentIcon isEqualToString:@"UnboundIcon"];
        }
        else
        {
            toggle.on = [defaults objectForKey:item[@"key"]] == nil
                            ? YES
                            : [defaults boolForKey:item[@"key"]];
        }

        cell.accessoryView = toggle;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *item = self.menuSections[indexPath.section][@"items"][indexPath.row];

    if ([item[@"destructive"] boolValue])
    {
        [self showDestructiveConfirmation:item[@"title"] selectorName:item[@"selector"]];
    }
    else if (item[@"selector"])
    {
        [self executeActionWithSelectorName:item[@"selector"]];
    }
}

- (void)showDestructiveConfirmation:(NSString *)action selectorName:(NSString *)selectorName
{
    NSString *message = @"Are you sure you want to do this?";

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:action
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Confirm"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                                [self executeActionWithSelectorName:selectorName];
                                            }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)executeActionWithSelectorName:(NSString *)selectorName
{
    SEL selector = NSSelectorFromString(selectorName);
    if ([self respondsToSelector:selector])
    {
        IMP imp               = [self methodForSelector:selector];
        void (*func)(id, SEL) = (void *) imp;
        func(self, selector);
    }
}

- (void)toggleRecoveryMode
{
    BOOL currentValue = [Utilities isRecoveryModeEnabled];
    [Settings set:@"unbound" key:@"recovery" value:@(!currentValue)];
    [self dismissViewControllerAnimated:YES completion:^{ reloadApp(self); }];
}

- (void)refetchBundle
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *bundlePath = [Updater resolveBundlePath];
        [Updater downloadBundle:bundlePath];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:^{ reloadApp(self); }];
        });
    });
}

- (void)deleteBundle
{
    [Settings set:@"unbound" key:@"loader.update.url" value:nil];
    [Settings set:@"unbound" key:@"loader.update.force" value:nil];

    [[NSFileManager defaultManager] removeItemAtPath:[Updater resolveBundlePath] error:nil];
    [self dismissViewControllerAnimated:YES completion:^{ reloadApp(self); }];
}

- (void)switchBundleVersion
{
    UIAlertController *loadingAlert =
        [UIAlertController alertControllerWithTitle:@"Loading"
                                            message:@"Fetching branches..."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];

    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/unbound-app/builds/branches"];
    NSURLSession *session = [NSURLSession
        sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

    [[session
          dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [loadingAlert
                    dismissViewControllerAnimated:YES
                                       completion:^{
                                           if (error || !data)
                                           {
                                               [Utilities alert:@"Failed to fetch branches"
                                                          title:@"Error"];
                                               return;
                                           }

                                           NSError *jsonError;
                                           NSArray *branches =
                                               [NSJSONSerialization JSONObjectWithData:data
                                                                               options:0
                                                                                 error:&jsonError];
                                           if (jsonError || !branches.count)
                                           {
                                               [Utilities alert:@"No branches available"
                                                          title:@"Error"];
                                               return;
                                           }

                                           if (branches.count == 1)
                                           {
                                               NSString *branchName = branches[0][@"name"];
                                               [self fetchCommitsForBranch:branchName
                                                               withSession:session];
                                               return;
                                           }

                                           UIAlertController *branchAlert = [UIAlertController
                                               alertControllerWithTitle:@"Select Branch"
                                                                message:nil
                                                         preferredStyle:
                                                             UIAlertControllerStyleAlert];

                                           for (NSDictionary *branch in branches)
                                           {
                                               NSString *branchName = branch[@"name"];
                                               [branchAlert
                                                   addAction:
                                                       [UIAlertAction
                                                           actionWithTitle:branchName
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^(
                                                                       UIAlertAction *action) {
                                                                       [self fetchCommitsForBranch:
                                                                                 branchName
                                                                                       withSession:
                                                                                           session];
                                                                   }]];
                                           }

                                           [branchAlert
                                               addAction:
                                                   [UIAlertAction
                                                       actionWithTitle:@"Cancel"
                                                                 style:UIAlertActionStyleCancel
                                                               handler:nil]];
                                           [self presentViewController:branchAlert
                                                              animated:YES
                                                            completion:nil];
                                       }];
            });
        }] resume];
}

- (void)fetchCommitsForBranch:(NSString *)branch withSession:(NSURLSession *)session
{
    UIAlertController *loadingCommits =
        [UIAlertController alertControllerWithTitle:@"Loading"
                                            message:@"Fetching commits..."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingCommits animated:YES completion:nil];

    NSString *commitsUrl = [NSString
        stringWithFormat:
            @"https://api.github.com/repos/unbound-app/builds/commits?sha=%@&per_page=10", branch];
    NSURL    *commitsURL = [NSURL URLWithString:commitsUrl];

    [[session
          dataTaskWithURL:commitsURL
        completionHandler:^(NSData *commitsData, NSURLResponse *commitsResponse,
                            NSError *commitsError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [loadingCommits
                    dismissViewControllerAnimated:YES
                                       completion:^{
                                           if (commitsError || !commitsData)
                                           {
                                               [Utilities alert:@"Failed to fetch commits"
                                                          title:@"Error"];
                                               return;
                                           }

                                           NSError *jsonError;
                                           NSArray *commits =
                                               [NSJSONSerialization JSONObjectWithData:commitsData
                                                                               options:0
                                                                                 error:&jsonError];
                                           if (jsonError || !commits.count)
                                           {
                                               [Utilities alert:@"No commits available"
                                                          title:@"Error"];
                                               return;
                                           }

                                           UIAlertController *commitAlert = [UIAlertController
                                               alertControllerWithTitle:@"Select Version"
                                                                message:nil
                                                         preferredStyle:
                                                             UIAlertControllerStyleAlert];

                                           for (NSDictionary *commit in commits)
                                           {
                                               NSString *sha = commit[@"sha"];
                                               NSString *dateStr =
                                                   commit[@"commit"][@"author"][@"date"];

                                               NSDateFormatter *iso8601Formatter =
                                                   [[NSDateFormatter alloc] init];
                                               iso8601Formatter.dateFormat =
                                                   @"yyyy-MM-dd'T'HH:mm:ssZ";
                                               NSDate *date =
                                                   [iso8601Formatter dateFromString:dateStr];

                                               NSDateFormatter *formatter =
                                                   [[NSDateFormatter alloc] init];
                                               formatter.dateFormat = @"MMM d, yyyy";

                                               NSString *title = [NSString
                                                   stringWithFormat:@"%@ (%@)",
                                                                    [sha substringToIndex:7],
                                                                    [formatter
                                                                        stringFromDate:date]];

                                               [commitAlert
                                                   addAction:
                                                       [UIAlertAction
                                                           actionWithTitle:title
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^(
                                                                       UIAlertAction *action) {
                                                                       NSString *bundleUrl =
                                                                           [NSString
                                                                               stringWithFormat:
                                                                                   @"https://"
                                                                                   @"raw."
                                                                                   @"githubusercont"
                                                                                   @"ent.com/"
                                                                                   @"unbound-app/"
                                                                                   @"builds/%@/"
                                                                                   @"unbound."
                                                                                   @"bundle",
                                                                                   sha];
                                                                       [Settings set:@"unbound"
                                                                                 key:@"loader."
                                                                                     @"update.url"
                                                                               value:bundleUrl];
                                                                       [Settings set:@"unbound"
                                                                                 key:@"loader."
                                                                                     @"update.force"
                                                                               value:@YES];
                                                                       [self
                                                                           dismissViewControllerAnimated:
                                                                               YES
                                                                                              completion:^{
                                                                                                  reloadApp(
                                                                                                      self);
                                                                                              }];
                                                                   }]];
                                           }

                                           [commitAlert
                                               addAction:
                                                   [UIAlertAction
                                                       actionWithTitle:@"Cancel"
                                                                 style:UIAlertActionStyleCancel
                                                               handler:nil]];
                                           [self presentViewController:commitAlert
                                                              animated:YES
                                                            completion:nil];
                                       }];
            });
        }] resume];
}

- (void)loadCustomBundle
{
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Custom Bundle URL"
                         message:@"Enter the URL to download a custom bundle from"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder            = @"https://example.com/unbound.bundle";
        textField.keyboardType           = UIKeyboardTypeURL;
        textField.autocorrectionType     = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [alert addAction:[UIAlertAction
                         actionWithTitle:@"Download"
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *action) {
                                     UITextField *textField = alert.textFields.firstObject;
                                     NSString    *urlString = textField.text;

                                     if (urlString.length > 0)
                                     {
                                         [Settings set:@"unbound"
                                                   key:@"loader.update.url"
                                                 value:urlString];
                                         [Settings set:@"unbound"
                                                   key:@"loader.update.force"
                                                 value:@YES];

                                         dispatch_async(
                                             dispatch_get_global_queue(
                                                 DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                             ^{
                                                 NSString *bundlePath = [Updater resolveBundlePath];
                                                 [Updater downloadBundle:bundlePath];
                                                 dispatch_async(dispatch_get_main_queue(), ^{
                                                     [self dismissViewControllerAnimated:YES
                                                                              completion:^{
                                                                                  reloadApp(self);
                                                                              }];
                                                 });
                                             });
                                     }
                                 }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wipePlugins
{
    [[NSFileManager defaultManager]
        removeItemAtPath:[NSString pathWithComponents:@[ FileSystem.documents, @"plugins" ]]
                   error:nil];
    [self dismissViewControllerAnimated:YES completion:^{ reloadApp(self); }];
}

- (void)wipeThemes
{
    [[NSFileManager defaultManager]
        removeItemAtPath:[NSString pathWithComponents:@[ FileSystem.documents, @"themes" ]]
                   error:nil];
    [self dismissViewControllerAnimated:YES completion:^{ reloadApp(self); }];
}

- (void)wipeFonts
{
    [[NSFileManager defaultManager]
        removeItemAtPath:[NSString pathWithComponents:@[ FileSystem.documents, @"fonts" ]]
                   error:nil];
    [self dismissViewControllerAnimated:YES completion:^{ reloadApp(self); }];
}

- (void)wipeIconPacks
{
    [[NSFileManager defaultManager]
        removeItemAtPath:[NSString pathWithComponents:@[ FileSystem.documents, @"icon-packs" ]]
                   error:nil];
    [self dismissViewControllerAnimated:YES completion:^{ reloadApp(self); }];
}

- (void)factoryReset
{
    [[NSFileManager defaultManager] removeItemAtPath:FileSystem.documents error:nil];
    [self dismissViewControllerAnimated:YES completion:^{ reloadApp(self); }];
}

- (void)openAppFolder
{
    if ([Utilities isJailbroken])
    {
        NSString *filePath = [NSString stringWithFormat:@"filza://view%@", FileSystem.documents];
        NSURL    *url      = [NSURL URLWithString:filePath];

        if ([[UIApplication sharedApplication] canOpenURL:url])
        {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            return;
        }
    }

    NSString *sharedPath =
        [NSString stringWithFormat:@"shareddocuments://%@", FileSystem.documents];
    NSURL *sharedUrl = [NSURL URLWithString:sharedPath];

    [[UIApplication sharedApplication] openURL:sharedUrl options:@{} completionHandler:nil];
}

- (void)openGitHubIssue
{
    NSString *deviceModel = [Utilities getDeviceModel];
    NSString *appVersion =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *buildNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];

    NSString *iosVersionString = [Utilities getiOSVersionString];

    NSString *appSource = [Utilities getAppSource];

    NSString *appRegistrationType = [Utilities isSystemApp] ? @"System" : @"User";

    NSMutableString *body =
        [NSMutableString stringWithFormat:@"### Environment\n"
                                           "- **Device**: %@\n"
                                           "- **iOS Version**: %@\n"
                                           "- **App Version**: %@ (%@)\n"
                                           "- **App Source**: %@\n"
                                           "- **App Registration**: %@\n",
                                          deviceModel, iosVersionString, appVersion, buildNumber,
                                          appSource, appRegistrationType];

    NSDictionary *entitlements = [Utilities getApplicationEntitlements];
    if (entitlements && entitlements.count > 0)
    {
        [body appendString:@"\n### Entitlements\n"];
        [body appendString:@"```xml\n"];
        [body appendString:[Utilities formatEntitlementsAsPlist:entitlements]];
        [body appendString:@"\n```\n"];
    }

    [body appendString:@"\n### Issue Description\n"
                        "<!-- Describe the issue you're experiencing -->\n\n"
                        "**Steps to reproduce:**\n"
                        "1. \n"
                        "2. \n"
                        "3. \n\n"
                        "**Expected behavior:**\n\n"
                        "**Actual behavior:**\n\n"];

    NSString *encodedTitle = [@"bug(iOS): replace this with a descriptive title"
        stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet
                                                               .URLQueryAllowedCharacterSet];
    NSString *encodedBody =
        [body stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet
                                                                     .URLQueryAllowedCharacterSet];
    NSString *urlString = [NSString
        stringWithFormat:@"https://github.com/unbound-app/loader-ios/issues/new?title=%@&body=%@",
                         encodedTitle, encodedBody];
    NSURL    *url       = [NSURL URLWithString:urlString];

    if (!url)
    {
        [Utilities alert:@"Failed to create GitHub issue URL" title:@"Error"];
        return;
    }

    SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
    safari.dismissButtonStyle      = SFSafariViewControllerDismissButtonStyleClose;
    safari.delegate                = self;
    safari.modalPresentationStyle  = UIModalPresentationPageSheet;
    [self presentViewController:safari animated:YES completion:nil];
}

- (void)toggleSetting:(UISwitch *)sender
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    if (sender.tag == 0)
    {
        [defaults setBool:sender.on forKey:@"UnboundShakeGestureEnabled"];
        if (!sender.on)
        {
            [defaults setBool:YES forKey:@"UnboundThreeFingerGestureEnabled"];

            UITableViewCell *otherCell =
                [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:4]];
            if (otherCell)
            {
                UISwitch *otherSwitch = (UISwitch *) otherCell.accessoryView;
                if ([otherSwitch isKindOfClass:[UISwitch class]])
                {
                    [otherSwitch setOn:YES animated:YES];
                }
            }
        }
    }
    else if (sender.tag == 1)
    {
        [defaults setBool:sender.on forKey:@"UnboundThreeFingerGestureEnabled"];
        if (!sender.on)
        {
            [defaults setBool:YES forKey:@"UnboundShakeGestureEnabled"];

            UITableViewCell *otherCell =
                [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:4]];
            if (otherCell)
            {
                UISwitch *otherSwitch = (UISwitch *) otherCell.accessoryView;
                if ([otherSwitch isKindOfClass:[UISwitch class]])
                {
                    [otherSwitch setOn:YES animated:YES];
                }
            }
        }
    }
    else if (sender.tag == 2)
    {
        NSString *iconName = sender.on ? @"UnboundIcon" : nil;

        [[UIApplication sharedApplication] setAlternateIconName:iconName
                                              completionHandler:^(NSError *error) {
                                                  if (error)
                                                  {
                                                      dispatch_async(dispatch_get_main_queue(), ^{
                                                          [sender setOn:!sender.on animated:YES];
                                                      });
                                                  }
                                              }];
    }

    [defaults synchronize];
}

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller
{
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)dismiss
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

void showToolboxSheet(void)
{
    UnboundToolboxViewController *settingsVC = [[UnboundToolboxViewController alloc] init];

    UINavigationController *navController =
        [[UINavigationController alloc] initWithRootViewController:settingsVC];
    navController.modalPresentationStyle = UIModalPresentationFormSheet;

    UIBarButtonItem *doneButton =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:settingsVC
                                                      action:@selector(dismiss)];
    settingsVC.navigationItem.rightBarButtonItem = doneButton;

    UIWindowScene *activeScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
    {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]])
        {
            activeScene = (UIWindowScene *) scene;
            break;
        }
    }

    if (!activeScene)
        return;

    UIWindow *originalKeyWindow = nil;
    for (UIWindow *w in activeScene.windows)
    {
        if (w.isKeyWindow)
        {
            originalKeyWindow = w;
            break;
        }
    }

    UIWindow *topWindow       = [[UIWindow alloc] initWithWindowScene:activeScene];
    topWindow.windowLevel     = UIWindowLevelAlert + 100;
    topWindow.backgroundColor = [UIColor clearColor];

    UIViewController *rootVC     = [UIViewController new];
    rootVC.view.backgroundColor  = [UIColor clearColor];
    topWindow.rootViewController = rootVC;
    [topWindow makeKeyAndVisible];

    [rootVC presentViewController:navController animated:YES completion:nil];

    objc_setAssociatedObject(navController, "recoveryTopWindow", topWindow,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (originalKeyWindow)
    {
        objc_setAssociatedObject(navController, "recoveryOriginalKeyWindow", originalKeyWindow,
                                 OBJC_ASSOCIATION_ASSIGN);
    }

    Method dismissMethod =
        class_getInstanceMethod([UnboundToolboxViewController class], @selector(dismiss));
    method_setImplementation(
        dismissMethod, imp_implementationWithBlock(^(id _self) {
            [_self
                dismissViewControllerAnimated:YES
                                   completion:^{
                                       UIWindow *storedWindow = objc_getAssociatedObject(
                                           navController, "recoveryTopWindow");
                                       UIWindow *origKeyWindow = objc_getAssociatedObject(
                                           navController, "recoveryOriginalKeyWindow");

                                       if (storedWindow)
                                       {
                                           storedWindow.hidden             = YES;
                                           storedWindow.rootViewController = nil;
                                       }

                                       [origKeyWindow makeKeyAndVisible];

                                       objc_setAssociatedObject(navController, "recoveryTopWindow",
                                                                nil, OBJC_ASSOCIATION_ASSIGN);
                                       objc_setAssociatedObject(navController,
                                                                "recoveryOriginalKeyWindow", nil,
                                                                OBJC_ASSOCIATION_ASSIGN);
                                   }];
        }));
}

@end

void reloadApp(UIViewController *viewController)
{
    [viewController
        dismissViewControllerAnimated:NO
                           completion:^{
                               Class RCTBridge = NSClassFromString(@"RCTBridge");
                               if (RCTBridge &&
                                   [RCTBridge
                                       respondsToSelector:NSSelectorFromString(@"currentBridge")])
                               {
                                   id (*msg)(id, SEL) = (id (*)(id, SEL)) objc_msgSend;
                                   id bridge =
                                       msg(RCTBridge, NSSelectorFromString(@"currentBridge"));
                                   if (bridge)
                                   {
                                       SEL reloadSel = NSSelectorFromString(@"reload");
                                       if ([bridge respondsToSelector:reloadSel])
                                       {
                                           ((void (*)(id, SEL)) objc_msgSend)(bridge, reloadSel);
                                           return;
                                       }
                                       SEL requestReloadSel =
                                           NSSelectorFromString(@"requestReload");
                                       if ([bridge respondsToSelector:requestReloadSel])
                                       {
                                           ((void (*)(id, SEL)) objc_msgSend)(bridge,
                                                                              requestReloadSel);
                                           return;
                                       }
                                   }
                               }

                               UIApplication *app = [UIApplication sharedApplication];
                               ((void (*)(id, SEL)) objc_msgSend)(app, @selector(suspend));
                               dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC),
                                              dispatch_get_main_queue(), ^{ exit(0); });
                           }];
}
