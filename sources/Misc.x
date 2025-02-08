#import "Misc.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

%hook SentrySDK
+ (void)startWithOptions:(id)options
{
    NSLog(@"Blocked SentrySDK.");
    return;
}

+ (void)startWithConfigureOptions:(id)callback
{
    NSLog(@"Blocked SentrySDK.");
    return;
}

+ (BOOL)isEnabled
{
    return NO;
}
%end

%hook FIRInstallations
+ (void)load
{
    NSLog(@"Blocked Firebase Installations.");
    return;
}
%end

// Fix issues with sideloading
%group Sideloading
%hook  NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)identifier
{
    if (identifier != nil)
    {
        NSError *error;

        NSFileManager *manager = [NSFileManager defaultManager];
        NSURL         *url     = [manager URLForDirectory:NSDocumentDirectory
                                     inDomain:NSUserDomainMask
                            appropriateForURL:nil
                                       create:YES
                                        error:&error];

        if (error)
        {
            NSLog(@"[Error] Failed getting documents directory: %@", error);
            return %orig(identifier);
        }

        return url;
    }

    return %orig(identifier);
}
%end

// fix file access by using asCopy, adapted from
// https://github.com/khanhduytran0/LiveContainer/blob/main/TweakLoader/DocumentPicker.m
%hook UIDocumentPickerViewController

- (instancetype)initForOpeningContentTypes:(NSArray<UTType *> *)contentTypes asCopy:(BOOL)asCopy
{
    BOOL shouldMultiselect = NO;
    if ([contentTypes count] == 1 && contentTypes[0] == UTTypeFolder)
    {
        shouldMultiselect = YES;
    }

    NSArray<UTType *> *contentTypesNew = @[ UTTypeItem, UTTypeFolder ];

    UIDocumentPickerViewController *ans = %orig(contentTypesNew, YES);
    if (shouldMultiselect)
    {
        [ans setAllowsMultipleSelection:YES];
    }
    return ans;
}

- (instancetype)initWithDocumentTypes:(NSArray<UTType *> *)contentTypes inMode:(NSUInteger)mode
{
    return [self initForOpeningContentTypes:contentTypes asCopy:(mode == 1 ? NO : YES)];
}

- (void)setAllowsMultipleSelection:(BOOL)allowsMultipleSelection
{
    if ([self allowsMultipleSelection])
    {
        return;
    }
    %orig(YES);
}

%end

%hook UIDocumentBrowserViewController

- (instancetype)initForOpeningContentTypes:(NSArray<UTType *> *)contentTypes
{
    NSArray<UTType *> *contentTypesNew = @[ UTTypeItem, UTTypeFolder ];
    return %orig(contentTypesNew);
}

%end

%hook NSURL

- (BOOL)startAccessingSecurityScopedResource
{
    %orig;
    return YES;
}

%end

// show icon change error alert
%hook UIApplication
- (void)setAlternateIconName:(NSString *)iconName completionHandler:(void (^)(NSError *))completion
{
    void (^wrappedCompletion)(NSError *) = ^(NSError *error) {
        if (error)
        {
            [Utilities alert:@"For this to work change the Bundle ID so that it matches your "
                             @"provisioning profile's App ID (excluding the Team ID prefix)."
                       title:@"Cannot Change Icon"];
        }

        if (completion)
        {
            completion(error);
        }
    };

    %orig(iconName, wrappedCompletion);
}
%end

// show passkey error alert
%hook ASAuthorizationController

- (void)performRequests
{
    [Utilities alert:@"Passkeys are not supported when sideloading Discord. Please use a different "
                     @"login method."
               title:@"Cannot Use Passkey"];
}

%end
%end

%group Debug
%hook  NSError
- (id)initWithDomain:(id)domain code:(int)code userInfo:(id)userInfo
{
    NSLog(@"[Error] Initialized with info: %@ %@ %d", userInfo, domain, code);
    return %orig;
};

+ (id)errorWithDomain:(id)domain code:(int)code userInfo:(id)userInfo
{
    NSLog(@"[Error] Initialized with info: %@ %@ %d", userInfo, domain, code);
    return %orig;
};
%end

%hook NSException
- (id)initWithName:(id)name reason:(id)reason userInfo:(id)userInfo
{
    NSLog(@"[Exception] Initialized with info: %@ %@ %@", userInfo, name, reason);
    return %orig;
};

+ (id)exceptionWithName:(id)name reason:(id)reason userInfo:(id)userInfo
{
    NSLog(@"[Exception] Initialized with info: %@ %@ %@", userInfo, name, reason);
    return %orig;
};
%end
%end

%ctor
{
    %init()

#ifdef DEBUG
        %init(Debug)
#endif

            BOOL isAppStoreApp = [[NSFileManager defaultManager]
                fileExistsAtPath:[[NSBundle mainBundle] appStoreReceiptURL].path];
    if (!isAppStoreApp)
    {
        %init(Sideloading);
    }
}
