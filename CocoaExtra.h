//
//  CocoaExtra.h
//  Trisection
//
//  Created by bhaller on Thu May 17 2001.
//  Copyright (c) 2001 Ben Haller. All rights reserved.
//

#import <Cocoa/Cocoa.h>

static inline SInt32 StSRandomIntBetween(SInt32 start, SInt32 end) { return (SInt32)((random() % (end - start + 1)) + start); }

@interface NSTextView (SSCocoaExtra)

- (void)fixText:(NSString *)text toGoToLink:(NSString *)url;

@end

@interface NSTextField (SSCocoaExtra)

- (void)fixText:(NSString *)text toGoToLink:(NSString *)url;

@end

@interface WhiteView : NSView
@end

@interface BlueView : NSView
@end

NSModalResponse SSRunAlertPanel(NSString *title, NSString *msg, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, ...);
NSModalResponse SSRunInformationalAlertPanel(NSString *title, NSString *msg, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, ...);
NSModalResponse SSRunCriticalAlertPanel(NSString *title, NSString *msg, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, ...);

@interface NSScreen (SSScreens)

+ (NSScreen *)primaryScreen;

@end

@interface NSWindow (SSWindowCentering)

- (void)centerOnPrimaryScreen;

@end

@interface NSArray (SSRunLoopExtra)

+ (NSArray *)allRunLoopModes;		// default, modal panel, and event tracking

@end

@interface NSApplication (SSApplicationIcon)

- (NSImage *)SSApplicationIconScaledToSize:(NSSize)finalSize;

@end


// Front end to power management...
BOOL RunningOnBatteryOnly(void);

// Find out if the screen is locked (Apple Menu > Lock Screen)
BOOL ScreenIsLocked(void);
