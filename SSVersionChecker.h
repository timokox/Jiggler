//
//  SSVersionChecker.h
//  Jiggler
//
//  Hand-written bridge header for the Swift implementation in
//  SSVersionChecker.swift.  Normally Xcode auto-generates Jiggler-Swift.h
//  from @objc declarations, but on Xcode 26.5 / Swift 6.3 the combination
//  of -parse-as-library + -enable-batch-mode silently emits an empty
//  header for our @objc class (the .o file does have the
//  _OBJC_CLASS_$_SSVersionChecker symbol, so this declaration is
//  sufficient for the Objective-C side to compile and link).
//
//  Keep this declaration in sync with the @objc surface in
//  SSVersionChecker.swift.  If/when Apple ships a fix, this file can be
//  deleted and AppDelegate.m can import "Jiggler-Swift.h" again.
//

#import <Cocoa/Cocoa.h>


@interface SSVersionChecker : NSObject

+ (SSVersionChecker *)sharedVersionChecker;

- (void)askUserAboutAutomaticVersionCheck;                              // runs the consent panel
- (BOOL)shouldDoAutomaticVersionCheckAskIfNecessary:(BOOL)ask;          // runs the panel only if not asked before AND ask is YES
- (void)checkForNewVersionUserRequested:(BOOL)userRequested;            // hits GitHub Releases asynchronously

@end
