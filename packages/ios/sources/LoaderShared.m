#import "LoaderShared.h"

@implementation LoaderShared

+ (NSData *)buildPreloadScriptData
{
    return [CoreBridge preloadScriptWithSettings:[Settings getSettings]
                                         plugins:[Plugins makeJSON]
                                          themes:[Themes makeJSON]
                                           fonts:[Fonts makeJSON]
                                  availableFonts:[Fonts makeAvailableJSON]
                                          origin:[Utilities getCurrentDylibName]
                                         version:PACKAGE_VERSION];
}

@end
