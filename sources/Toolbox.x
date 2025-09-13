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
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc]
            initWithTarget:[UIApplication sharedApplication]
                    action:@selector(handleThreeFingerLongPress:)];
        gesture.numberOfTouchesRequired       = 3;
        gesture.minimumPressDuration          = 1.5;
        [window addGestureRecognizer:gesture];
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
        shakeStartTime = [[NSDate date] timeIntervalSince1970];
        isShaking      = YES;
        triggerHapticFeedback();
    }
    %orig;
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
    if (motion == UIEventSubtypeMotionShake && isShaking)
    {
        isShaking                       = NO;
        NSTimeInterval shakeDuration    = [[NSDate date] timeIntervalSince1970] - shakeStartTime;
        NSTimeInterval requiredDuration = 2.0;

        if (shakeDuration >= requiredDuration)
        {
            triggerHapticFeedback();

            if ([Utilities isRecoveryModeEnabled])
            {
                dispatch_async(dispatch_get_main_queue(), ^{ [Toolbox showToolboxMenu]; });
            }
        }
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
        triggerHapticFeedback();

        if ([Utilities isRecoveryModeEnabled])
        {
            dispatch_async(dispatch_get_main_queue(), ^{ [Toolbox showToolboxMenu]; });
        }
    }
}
%end

@implementation UnboundToolboxViewController

- (NSString *)bundlePath
{
    return [NSString pathWithComponents:@[ FileSystem.documents, @"unbound.bundle" ]];
}

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
    NSMutableArray *settingsItems = [@[ @{
        @"title" : @"Themes",
        @"icon" : @"paintbrush",
        @"isSwitch" : @YES,
        @"key" : @"themes.enabled",
        @"tag" : @0
    } ] mutableCopy];

    if (![Utilities isAppStoreApp] && ![Utilities isTestFlightApp])
    {
        [settingsItems addObjectsFromArray:@[
            @{
                @"title" : @"Plugins",
                @"icon" : @"puzzlepiece",
                @"isSwitch" : @YES,
                @"key" : @"plugins.enabled",
                @"tag" : @1
            },
            @{
                @"title" : @"Fonts",
                @"icon" : @"textformat",
                @"isSwitch" : @YES,
                @"key" : @"fonts.enabled",
                @"tag" : @2
            }
        ]];
    }

    self.menuSections = @[
        @{@"title" : @"Settings", @"items" : settingsItems}, @{
            @"title" : @"Recovery",
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
                    @"icon" : @"arrow.clockwise",
                    @"selector" : NSStringFromSelector(@selector(refetchBundle))
                },
                @{
                    @"title" : @"Custom Bundle",
                    @"icon" : @"link",
                    @"selector" : NSStringFromSelector(@selector(loadCustomBundle))
                },
                @{
                    @"title" : @"Switch Bundle Version",
                    @"icon" : @"rectangle.2.swap",
                    @"selector" : NSStringFromSelector(@selector(switchBundleVersion))
                },
                @{
                    @"title" : @"Delete Bundle",
                    @"icon" : @"trash",
                    @"destructive" : @YES,
                    @"selector" : NSStringFromSelector(@selector(deleteBundle))
                }
            ]
        },
        @{
            @"title" : @"File System",
            @"items" : @[ @{
                @"title" : @"Open App Folder",
                @"icon" : @"folder",
                @"selector" : NSStringFromSelector(@selector(openAppFolder))
            } ]
        },
        @{
            @"title" : @"Data Management",
            @"items" : @[
                @{
                    @"title" : @"Wipe Plugins",
                    @"icon" : @"puzzlepiece",
                    @"destructive" : @YES,
                    @"selector" : NSStringFromSelector(@selector(wipePlugins))
                },
                @{
                    @"title" : @"Wipe Themes",
                    @"icon" : @"paintbrush",
                    @"destructive" : @YES,
                    @"selector" : NSStringFromSelector(@selector(wipeThemes))
                },
                @{
                    @"title" : @"Wipe Fonts",
                    @"icon" : @"textformat",
                    @"destructive" : @YES,
                    @"selector" : NSStringFromSelector(@selector(wipeFonts))
                },
                @{
                    @"title" : @"Wipe Icon Packs",
                    @"icon" : @"app",
                    @"destructive" : @YES,
                    @"selector" : NSStringFromSelector(@selector(wipeIconPacks))
                },
                @{
                    @"title" : @"Factory Reset",
                    @"icon" : @"exclamationmark.triangle",
                    @"destructive" : @YES,
                    @"selector" : NSStringFromSelector(@selector(factoryReset))
                }
            ]
        },
        @{
            @"title" : @"Support",
            @"items" : @[ @{
                @"title" : @"Create GitHub Issue",
                @"icon" : @"ladybug",
                @"selector" : NSStringFromSelector(@selector(openGitHubIssue))
            } ]
        }
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
        [UIImageSymbolConfiguration configurationWithPointSize:18
                                                        weight:UIImageSymbolWeightRegular];
    UIImage *icon        = [UIImage systemImageNamed:item[@"icon"] withConfiguration:config];
    cell.imageView.image = icon;
    cell.imageView.tintColor =
        [item[@"destructive"] boolValue] ? UIColor.systemRedColor : UIColor.labelColor;

    if ([item[@"isSwitch"] boolValue])
    {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.tag       = [item[@"tag"] intValue];
        [toggle addTarget:self
                      action:@selector(toggleSetting:)
            forControlEvents:UIControlEventValueChanged];

        NSString *key = item[@"key"];
        if ([key isEqualToString:@"themes.enabled"])
        {
            toggle.on =
                [[NSUserDefaults standardUserDefaults] boolForKey:@"unbound_themes_enabled"];
        }
        else if ([key isEqualToString:@"plugins.enabled"])
        {
            toggle.on =
                [[NSUserDefaults standardUserDefaults] boolForKey:@"unbound_plugins_enabled"];
        }
        else if ([key isEqualToString:@"fonts.enabled"])
        {
            toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"unbound_fonts_enabled"];
        }

        cell.accessoryView       = toggle;
        cell.selectionStyle      = UITableViewCellSelectionStyleNone;
        cell.imageView.tintColor = UIColor.labelColor;
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
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:selector];
#pragma clang diagnostic pop
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
        [Updater downloadBundle:[self bundlePath]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:^{ reloadApp(self); }];
        });
    });
}

- (void)deleteBundle
{
    [Settings set:@"unbound" key:@"loader.update.url" value:nil];
    [Settings set:@"unbound" key:@"loader.update.force" value:nil];

    [[NSFileManager defaultManager] removeItemAtPath:[self bundlePath] error:nil];
    [self dismissViewControllerAnimated:YES completion:^{ reloadApp(self); }];
}

- (void)switchBundleVersion
{
    UIAlertController *loadingAlert =
        [UIAlertController alertControllerWithTitle:@"Loading Branches"
                                            message:@"Fetching available branches..."
                                     preferredStyle:UIAlertControllerStyleAlert];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    [loadingAlert setValue:spinner forKey:@"accessoryView"];
    [self presentViewController:loadingAlert animated:YES completion:nil];

    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/unbound-app/builds/branches"];
    NSURLSession *session = [NSURLSession
        sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

    [[session dataTaskWithURL:url
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [loadingAlert dismissViewControllerAnimated:YES completion:nil];

                    if (error)
                    {
                        [Utilities alert:[NSString stringWithFormat:@"Failed to fetch branches: %@",
                                                                    error.localizedDescription]
                                   title:@"Error"];
                        return;
                    }

                    NSError *jsonError;
                    NSArray *branches = [NSJSONSerialization JSONObjectWithData:data
                                                                        options:0
                                                                          error:&jsonError];
                    if (jsonError || ![branches isKindOfClass:[NSArray class]])
                    {
                        [Utilities alert:@"Failed to parse branches data" title:@"Error"];
                        return;
                    }

                    UIAlertController *branchAlert = [UIAlertController
                        alertControllerWithTitle:@"Select Branch"
                                         message:@"Choose a branch to fetch commits from"
                                  preferredStyle:UIAlertControllerStyleActionSheet];

                    for (NSDictionary *branch in branches)
                    {
                        NSString *branchName = branch[@"name"];
                        if (branchName)
                        {
                            UIAlertAction *action =
                                [UIAlertAction actionWithTitle:branchName
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
                                                           [self fetchCommitsForBranch:branchName
                                                                           withSession:session];
                                                       }];
                            [branchAlert addAction:action];
                        }
                    }

                    [branchAlert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                                    style:UIAlertActionStyleCancel
                                                                  handler:nil]];

                    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
                    {
                        branchAlert.popoverPresentationController.sourceView = self.view;
                        branchAlert.popoverPresentationController.sourceRect =
                            CGRectMake(self.view.bounds.size.width / 2,
                                       self.view.bounds.size.height / 2, 0, 0);
                    }

                    [self presentViewController:branchAlert animated:YES completion:nil];
                });
            }] resume];
}

- (void)fetchCommitsForBranch:(NSString *)branch withSession:(NSURLSession *)session
{
    UIAlertController       *loadingCommits = [UIAlertController
        alertControllerWithTitle:@"Loading Commits"
                         message:[NSString stringWithFormat:@"Fetching commits from %@...", branch]
                  preferredStyle:UIAlertControllerStyleAlert];
    UIActivityIndicatorView *spinner        = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    [loadingCommits setValue:spinner forKey:@"accessoryView"];
    [self presentViewController:loadingCommits animated:YES completion:nil];

    NSString *commitsUrl = [NSString
        stringWithFormat:
            @"https://api.github.com/repos/unbound-app/builds/commits?sha=%@&per_page=10", branch];
    NSURL    *commitsURL = [NSURL URLWithString:commitsUrl];

    [[session
          dataTaskWithURL:commitsURL
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [loadingCommits dismissViewControllerAnimated:YES completion:nil];

                if (error)
                {
                    [Utilities alert:[NSString stringWithFormat:@"Failed to fetch commits: %@",
                                                                error.localizedDescription]
                               title:@"Error"];
                    return;
                }

                NSError *jsonError;
                NSArray *commits = [NSJSONSerialization JSONObjectWithData:data
                                                                   options:0
                                                                     error:&jsonError];
                if (jsonError || ![commits isKindOfClass:[NSArray class]])
                {
                    [Utilities alert:@"Failed to parse commits data" title:@"Error"];
                    return;
                }

                UIAlertController *commitAlert = [UIAlertController
                    alertControllerWithTitle:@"Select Commit"
                                     message:[NSString stringWithFormat:@"Choose a commit from %@",
                                                                        branch]
                              preferredStyle:UIAlertControllerStyleActionSheet];

                for (NSDictionary *commit in commits)
                {
                    NSDictionary *commitData = commit[@"commit"];
                    NSString     *sha        = commit[@"sha"];
                    NSString     *message    = commitData[@"message"];
                    NSString     *author     = commitData[@"author"][@"name"];
                    NSString     *date       = commitData[@"author"][@"date"];

                    if (sha && message)
                    {
                        NSString *shortSha = [sha substringToIndex:MIN(sha.length, 7)];
                        NSString *title = [NSString stringWithFormat:@"%@ (%@)", shortSha, author];
                        UIAlertAction *action = [UIAlertAction
                            actionWithTitle:title
                                      style:UIAlertActionStyleDefault
                                    handler:^(UIAlertAction *action) {
                                        NSString *bundleUrl = [NSString
                                            stringWithFormat:
                                                @"https://github.com/unbound-app/builds/releases/"
                                                @"download/%@-bundle/unbound.bundle",
                                                sha];

                                        UIAlertController *confirmAlert = [UIAlertController
                                            alertControllerWithTitle:@"Confirm Bundle Switch"
                                                             message:[NSString
                                                                         stringWithFormat:
                                                                             @"Switch to commit "
                                                                             @"%@?\n\nMessage: "
                                                                             @"%@\nAuthor: "
                                                                             @"%@\nDate: %@",
                                                                             shortSha, message,
                                                                             author, date]
                                                      preferredStyle:UIAlertControllerStyleAlert];

                                        [confirmAlert
                                            addAction:[UIAlertAction
                                                          actionWithTitle:@"Cancel"
                                                                    style:UIAlertActionStyleCancel
                                                                  handler:nil]];

                                        [confirmAlert
                                            addAction:
                                                [UIAlertAction
                                                    actionWithTitle:@"Switch"
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction *action) {
                                                                [Settings set:@"unbound"
                                                                          key:@"loader.update.url"
                                                                        value:bundleUrl];
                                                                [Settings set:@"unbound"
                                                                          key:@"loader.update.force"
                                                                        value:@YES];

                                                                dispatch_async(
                                                                    dispatch_get_global_queue(
                                                                        DISPATCH_QUEUE_PRIORITY_DEFAULT,
                                                                        0),
                                                                    ^{
                                                                        [Updater
                                                                            downloadBundle:
                                                                                [self bundlePath]];
                                                                        dispatch_async(
                                                                            dispatch_get_main_queue(),
                                                                            ^{
                                                                                [self
                                                                                    dismissViewControllerAnimated:
                                                                                        YES
                                                                                                       completion:^{
                                                                                                           reloadApp(
                                                                                                               self);
                                                                                                       }];
                                                                            });
                                                                    });
                                                            }]];

                                        [self presentViewController:confirmAlert
                                                           animated:YES
                                                         completion:nil];
                                    }];
                        [commitAlert addAction:action];
                    }
                }

                [commitAlert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                                style:UIAlertActionStyleCancel
                                                              handler:nil]];

                if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
                {
                    commitAlert.popoverPresentationController.sourceView = self.view;
                    commitAlert.popoverPresentationController.sourceRect = CGRectMake(
                        self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
                }

                [self presentViewController:commitAlert animated:YES completion:nil];
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
                                                 [Updater downloadBundle:[self bundlePath]];
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
        stringWithFormat:@"https://github.com/unbound-app/issues/issues/new?title=%@&body=%@",
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
        [defaults setBool:sender.isOn forKey:@"unbound_themes_enabled"];

        if (sender.isOn)
        {
            [Utilities
                  alert:@"Themes will be enabled on next restart"
                  title:@"Themes Enabled"
                buttons:@[
                    [UIAlertAction actionWithTitle:@"Restart Now"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) { reloadApp(self); }],
                    [UIAlertAction actionWithTitle:@"Later"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]
                ]];
        }
    }
    else if (sender.tag == 1)
    {
        [defaults setBool:sender.isOn forKey:@"unbound_plugins_enabled"];

        if (sender.isOn)
        {
            [Utilities
                  alert:@"Plugins will be enabled on next restart"
                  title:@"Plugins Enabled"
                buttons:@[
                    [UIAlertAction actionWithTitle:@"Restart Now"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) { reloadApp(self); }],
                    [UIAlertAction actionWithTitle:@"Later"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]
                ]];
        }
    }
    else if (sender.tag == 2)
    {
        [defaults setBool:sender.isOn forKey:@"unbound_fonts_enabled"];
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
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive)
        {
            activeScene = (UIWindowScene *) scene;
            break;
        }
    }

    if (!activeScene)
    {
        activeScene = (UIWindowScene *) UIApplication.sharedApplication.connectedScenes.anyObject;
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
}

@end

void reloadApp(UIViewController *viewController)
{
    exit(0);
}
