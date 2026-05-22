//
//  JigglerOverlayWindow.h
//  Jiggler
//
//  Created by Ben Haller on Wed Aug 25 2004.
//  Copyright (c) 2004 Stick Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface JigglerOverlayWindow : NSObject
{
	NSWindow *overlayWindow;
	
	float currentAlpha;
	BOOL activated, isOrderedIn, scheduledTimer;
}

+ (void)activateOverlay;
+ (void)deactivateOverlay;

+ (BOOL)isActivated;

// Toggle whether the overlay window passes mouse events through to whatever
// is behind it.  Used by the click-jiggle path so that a click delivered at
// the cursor location does not get absorbed by the overlay if the user has
// parked the cursor on top of it (issue #18).  Returns the previous value
// so callers can restore it.  Safe to call when the overlay window does not
// yet exist (returns NO).
+ (BOOL)setOverlayIgnoresMouseEvents:(BOOL)flag;

@end
