#import <UIKit/UIKit.h>

#import "Utilities.h"

// Dynamic Island overlay.
extern const CGFloat DYNAMIC_ISLAND_TOP_INSET;

@interface Utilities (DynamicIsland)

+ (BOOL)deviceHasDynamicIsland;
+ (void)initializeDynamicIslandOverlay;
+ (void)showDynamicIslandOverlay;
+ (void)hideDynamicIslandOverlay;

@end

// Internal helpers for the overlay; not part of the public Utilities surface.
@interface Utilities (DynamicIslandPrivate)

+ (UIImage *)createLogoImage;
+ (void)createDynamicIslandOverlayView;

@end
