#import "Unbound.h"

static NSTimeInterval shakeStartTime = 0;
static BOOL isShaking = NO;
static NSHashTable *windowsWithGestures = nil;

static void addSettingsGestureToWindow(UIWindow *window) {
  if (!windowsWithGestures) {
    windowsWithGestures = [NSHashTable weakObjectsHashTable];
  }

  if (![windowsWithGestures containsObject:window]) {
    [windowsWithGestures addObject:window];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:[UIApplication sharedApplication]
                    action:@selector(handleThreeFingerLongPress:)];
    longPress.minimumPressDuration = 0.5;
    longPress.numberOfTouchesRequired = 3;
    [window addGestureRecognizer:longPress];
  }
}

id gBridge = nil;

static UIImpactFeedbackGenerator *feedbackGenerator = nil;

static void triggerHapticFeedback(void) {
    if (!feedbackGenerator) {
        feedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    }
    [feedbackGenerator prepare];
    [feedbackGenerator impactOccurred];
}

%hook RCTCxxBridge
- (void)executeApplicationScript:(NSData *)script
                             url:(NSURL *)url
                           async:(BOOL)async {
  gBridge = self;

  [FileSystem init];
  [Settings init];

  // Don't load bundle and addons if not configured to do so.
  if (![Settings getBoolean:@"unbound" key:@"loader.enabled" def:YES]) {
    NSLog(@"Loader is disabled. Aborting.");
    return %orig(script, url, true);
  }

  [Plugins init];
  [Themes init];
  [Fonts init];

  NSString *BUNDLE = [NSString
      pathWithComponents:@[ FileSystem.documents, @"unbound.bundle" ]];
  NSURL *SOURCE = [NSURL URLWithString:@"unbound"];

  // Apply React DevTools patch if its enabled
  if ([Settings getBoolean:@"unbound" key:@"loader.devtools" def:NO]) {
    @try {
      NSData *bundle = [Utilities getResource:@"devtools" data:true ext:@"js"];

      NSLog(@"Attempting to execute DevTools bundle...");
      %orig(bundle, SOURCE, true);
      NSLog(@"Successfully executed DevTools bundle.");
    } @catch (NSException *e) {
      NSLog(@"React DevTools failed to initialize. %@", e);
    }
  }

  // Apply modules patch
  @try {
    NSData *bundle = [Utilities getResource:@"modules" data:true ext:@"js"];

    NSLog(@"Attempting to execute modules patch...");
    %orig(bundle, SOURCE, true);
    NSLog(@"Successfully executed modules patch.");
  } @catch (NSException *e) {
    NSLog(@"Modules patch injection failed, expect issues. %@", e);
  }

  // Preload Unbound's settings, plugins & themes
  @try {
    NSString *bundle = [Utilities getResource:@"preload"];
    NSString *settings = [Settings getSettings];
    NSString *plugins = [Plugins makeJSON];
    NSString *themes = [Themes makeJSON];

    NSString *availableFonts = [Fonts makeAvailableJSON];
    NSString *fonts = [Fonts makeJSON];

    NSString *json = [NSString stringWithFormat:bundle, settings, plugins,
                                                themes, fonts, availableFonts];
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];

    NSLog(@"Pre-loading settings, plugins, fonts and themes...");
    %orig(data, SOURCE, true);
    NSLog(@"Pre-loaded settings, plugins, fonts and themes.");
  } @catch (NSException *e) {
    NSLog(@"Failed to pre-load settings, plugins, fonts and themes. %@", e);
  }

  %orig(script, url, true);

  // Check for updates & re-download bundle if necessary
  @try {
    [Updater downloadBundle:BUNDLE];
  } @catch (NSException *e) {
    NSLog(@"Bundle download failed. (%@)", e);

    if (![FileSystem exists:BUNDLE]) {
      return [Utilities alert:@"Bundle failed to download, please report this "
                              @"to the developers."];
    } else {
      [Utilities alert:@"Bundle failed to update, loading out of date bundle."];
    }
  }

  // Check if Unbound was downloaded properly
  if (![FileSystem exists:BUNDLE]) {
    return [Utilities
        alert:@"Bundle not found, please report this to the developers."];
  }

  // Inject Unbound script
  @try {
    NSData *bundle = [FileSystem readFile:BUNDLE];

    NSLog(@"Attempting to execute bundle...");
    %orig(bundle, SOURCE, true);
    NSLog(@"Unbound's bundle successfully executed.");
  } @catch (NSException *e) {
    NSLog(@"Unbound's bundle failed execution, aborting. (%@)", e.reason);
    return [Utilities alert:@"Failed to load Unbound's bundle. Please report "
                            @"this to the developers."];
  }
}
%end

%hook UIWindow
- (void)becomeKeyWindow {
  %orig;
  addSettingsGestureToWindow(self);
}

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event {
  if (motion == UIEventSubtypeMotionShake) {
    isShaking = YES;
    shakeStartTime = [[NSDate date] timeIntervalSince1970];
  }
  %orig;
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
  if (motion == UIEventSubtypeMotionShake && isShaking) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isEnabled = [defaults objectForKey:@"UnboundShakeGestureEnabled"] == nil ? YES : [defaults boolForKey:@"UnboundShakeGestureEnabled"];
    if (isEnabled) {
      NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
      NSTimeInterval shakeDuration = currentTime - shakeStartTime;

      if (shakeDuration >= 0.5 && shakeDuration <= 2.0) {
        triggerHapticFeedback();
        dispatch_async(dispatch_get_main_queue(), ^{
          showMenuSheet();
        });
      }
    }
    isShaking = NO;
  }
  %orig;
}

%end

%hook UIApplication
%new
- (void)handleThreeFingerLongPress:(UILongPressGestureRecognizer *)gesture {
  if (gesture.state == UIGestureRecognizerStateBegan) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isEnabled = [defaults objectForKey:@"UnboundThreeFingerGestureEnabled"] == nil ? YES : [defaults boolForKey:@"UnboundThreeFingerGestureEnabled"];
    if (isEnabled) {
      triggerHapticFeedback();
      showMenuSheet();
    }
  }
}
%end
