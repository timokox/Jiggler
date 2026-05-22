//
//  SSVersionChecker.m
//  Stick Software subsystem
//
//  Created by Ben Haller on Mon May 19 2003.
//  Copyright (c) 2003 Stick Software. All rights reserved.
//

#import "SSVersionChecker.h"
#import "CocoaExtra.h"


static NSString *VersionCheckingEnabledDefaultsKey = @"DoVersionCheck";

// GitHub Releases endpoint for this fork.  Returns a JSON object with at least
// `tag_name` and `html_url` when a release exists, or HTTP 404 when no releases
// have been published.  Treat 404 as "up to date" — there is nothing newer.
static NSString *ReleasesAPIURL = @"https://api.github.com/repos/timokox/Jiggler/releases/latest";


// Split a version like "1.10.2" or "v1.10" into an array of integer components,
// stripping a leading "v" if present.  Non-numeric trailing parts (e.g. "b1")
// scan as 0 — so 1.10 and 1.10b1 compare equal, which is good enough for
// "is a newer version out?".  The release notes carry any finer-grained nuance.
static NSArray<NSNumber *> *VersionComponents(NSString *version)
{
	if ([version hasPrefix:@"v"] || [version hasPrefix:@"V"])
		version = [version substringFromIndex:1];

	NSMutableArray<NSNumber *> *result = [NSMutableArray array];
	for (NSString *part in [version componentsSeparatedByString:@"."])
	{
		NSScanner *scanner = [NSScanner scannerWithString:part];
		int value = 0;
		[scanner scanInt:&value];
		[result addObject:@(value)];
	}
	return result;
}

// NSOrderedAscending  if remote > local (an update is available)
// NSOrderedSame       if equal
// NSOrderedDescending if remote < local (local is newer than published — dev builds)
static NSComparisonResult CompareVersions(NSString *local, NSString *remote)
{
	NSArray<NSNumber *> *l = VersionComponents(local);
	NSArray<NSNumber *> *r = VersionComponents(remote);
	NSUInteger n = MAX(l.count, r.count);

	for (NSUInteger i = 0; i < n; i++)
	{
		int lv = (i < l.count) ? l[i].intValue : 0;
		int rv = (i < r.count) ? r[i].intValue : 0;
		if (rv > lv) return NSOrderedAscending;
		if (rv < lv) return NSOrderedDescending;
	}
	return NSOrderedSame;
}


@implementation SSVersionChecker

+ (SSVersionChecker *)sharedVersionChecker
{
	static SSVersionChecker *sharedInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedInstance = [[SSVersionChecker alloc] init];
	});
	return sharedInstance;
}

- (void)askUserAboutAutomaticVersionCheck
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *appName = [[NSBundle mainBundle] infoDictionary][(NSString *)kCFBundleNameKey];

	NSModalResponse retval = SSRunCriticalAlertPanel(
		NSLocalizedStringFromTable(@"Version Check", @"VersionCheck", @"Version Check panels title"),
		NSLocalizedStringFromTable(@"Version Check offer panel text", @"VersionCheck", @"Version Check offer panel text"),
		NSLocalizedStringFromTable(@"Yes button", @"Base", @"Yes button"),
		NSLocalizedStringFromTable(@"No button", @"Base", @"No button"),
		nil, appName, appName);

	[defaults setObject:(retval == NSAlertFirstButtonReturn ? @"YES" : @"NO") forKey:VersionCheckingEnabledDefaultsKey];
}

- (BOOL)shouldDoAutomaticVersionCheckAskIfNecessary:(BOOL)flag
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *doCheck = [defaults stringForKey:VersionCheckingEnabledDefaultsKey];

	if (!doCheck && flag)
	{
		[self askUserAboutAutomaticVersionCheck];
		doCheck = [defaults stringForKey:VersionCheckingEnabledDefaultsKey];
	}

	return [doCheck isEqualToString:@"YES"];
}

- (void)checkForNewVersionUserRequested:(BOOL)userRequested
{
	NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
	NSString *appVersionString = infoDictionary[@"CFBundleShortVersionString"];	// user-facing marketing version, matches GitHub tags
	NSString *bundleName = infoDictionary[(NSString *)kCFBundleNameKey];

	NSURL *url = [NSURL URLWithString:ReleasesAPIURL];
	NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
	NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

	NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			NSInteger status = [(NSHTTPURLResponse *)response statusCode];

			// 404 → no releases published yet.  Already on the latest from the user's POV.
			if (status == 404)
			{
				if (userRequested)
				{
					SSRunInformationalAlertPanel(
						NSLocalizedStringFromTable(@"Version Check", @"VersionCheck", @"Version Check panels title"),
						NSLocalizedStringFromTable(@"Version Check up to date", @"VersionCheck", @"Version Check up to date"),
						NSLocalizedStringFromTable(@"OK button", @"Base", @"OK button"),
						nil, nil, bundleName, appVersionString);
				}
				return;
			}

			if (error || !data || status != 200)
			{
				if (userRequested)
				{
					SSRunCriticalAlertPanel(
						NSLocalizedStringFromTable(@"Version Check", @"VersionCheck", @"Version Check panels title"),
						NSLocalizedStringFromTable(@"Version Check network unavailable error (short version)", @"VersionCheck", @"Version Check network unavailable error (short version)"),
						NSLocalizedStringFromTable(@"OK button", @"Base", @"OK button"),
						nil, nil);
				}
				return;
			}

			NSError *jsonError = nil;
			id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
			NSDictionary *release = [parsed isKindOfClass:[NSDictionary class]] ? parsed : nil;
			NSString *remoteTag = release[@"tag_name"];
			NSString *remoteURL = release[@"html_url"];

			if (![remoteTag isKindOfClass:[NSString class]])
			{
				if (userRequested)
				{
					SSRunCriticalAlertPanel(
						NSLocalizedStringFromTable(@"Version Check", @"VersionCheck", @"Version Check panels title"),
						NSLocalizedStringFromTable(@"Version Check info unavailable error", @"VersionCheck", @"Version Check info unavailable error"),
						NSLocalizedStringFromTable(@"OK button", @"Base", @"OK button"),
						nil, nil);
				}
				return;
			}

			// Display form strips the conventional leading "v" from the tag.
			NSString *remoteVersion = ([remoteTag hasPrefix:@"v"] || [remoteTag hasPrefix:@"V"]) ? [remoteTag substringFromIndex:1] : remoteTag;

			if (CompareVersions(appVersionString, remoteTag) == NSOrderedAscending)
			{
				NSModalResponse choice = SSRunAlertPanel(
					NSLocalizedStringFromTable(@"Version Check", @"VersionCheck", @"Version Check panels title"),
					NSLocalizedStringFromTable(@"Version Check new version available", @"VersionCheck", @"Version Check new version available"),
					NSLocalizedStringFromTable(@"Yes button", @"Base", @"Yes button"),
					NSLocalizedStringFromTable(@"No button", @"Base", @"No button"),
					nil, bundleName, remoteVersion, appVersionString);

				if (choice == NSAlertFirstButtonReturn && [remoteURL isKindOfClass:[NSString class]])
					[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:remoteURL]];
			}
			else if (userRequested)
			{
				SSRunInformationalAlertPanel(
					NSLocalizedStringFromTable(@"Version Check", @"VersionCheck", @"Version Check panels title"),
					NSLocalizedStringFromTable(@"Version Check up to date", @"VersionCheck", @"Version Check up to date"),
					NSLocalizedStringFromTable(@"OK button", @"Base", @"OK button"),
					nil, nil, bundleName, appVersionString);
			}
		});
	}];
	[task resume];
}

@end
