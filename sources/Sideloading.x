#import "Sideloading.h"

%hook NSFileManager
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
            [Logger error:LOG_CATEGORY_DEFAULT
                   format:@"Failed getting documents directory: %@", error];
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

%hook ASAuthorizationController

- (void)performRequests
{
    [Utilities alert:@"Missing associated domain with the webcredentials service type "
                     @"(com.apple.developer.associated-domains). Please use a different "
                     @"login method."
               title:@"Cannot Use Passkey"];
}

%end

%ctor
{
    if (![Utilities hasDiscordProductionEntitlements])
    {
        %init();
    }
}
