/* iOS share sheet for UTShare: presents a UIActivityViewController with the
 * party message (and an optional link) from the topmost view controller.
 * On iPad the sheet is a popover anchored to the middle of the screen.
 *
 * Crash sweep (friends / invites): UIKit raises (and the app ends) when a
 * popover has no source view, and it refuses or misbehaves when a sheet is
 * presented while another presentation is still animating in or out (a
 * double tap on Share, or Share right after Game Center's sheet closed).
 * So: always on the main thread; only while the app is active; never a
 * second share sheet while one is up (tracked until its completion
 * handler); a controller that is mid-transition is retried shortly instead
 * of being presented on; every popover gets a source view and rect; and the
 * presentation is wrapped so an Objective-C exception is logged instead of
 * ending the app. */
#import <UIKit/UIKit.h>

#include "ut_share_platform.h"

static UIViewController *ut_top_controller(void) {
	UIWindow *window = nil;
	UIWindow *fallback = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		BOOL active = scene.activationState == UISceneActivationStateForegroundActive;
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (active && w.isKeyWindow) {
				window = w;
			} else if (fallback == nil && w.rootViewController != nil) {
				fallback = w;
			}
		}
	}
	UIViewController *vc = (window ?: fallback).rootViewController;
	while (vc.presentedViewController != nil && !vc.presentedViewController.isBeingDismissed) {
		vc = vc.presentedViewController;
	}
	return vc;
}

static BOOL ut_sharing = NO; /* a share sheet is up (main thread only) */

static BOOL ut_busy(UIViewController *vc) {
	return vc.isBeingPresented || vc.isBeingDismissed ||
		(vc.presentedViewController != nil && vc.presentedViewController.isBeingDismissed);
}

static BOOL ut_present(NSString *text, NSString *link, int tries) {
	if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
		return NO;
	}
	if (ut_sharing) {
		return YES; // already showing a share sheet
	}
	UIViewController *root = ut_top_controller();
	if (root == nil || root.view == nil || root.view.window == nil) {
		return NO;
	}
	if ([root isKindOfClass:[UIActivityViewController class]]) {
		return YES; // already showing a share sheet
	}
	if (ut_busy(root)) {
		// another sheet is still animating in or out: try again shortly
		if (tries >= 8) {
			return NO;
		}
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
			ut_present(text, link, tries + 1);
		});
		return YES;
	}
	NSMutableArray *items = [NSMutableArray arrayWithObject:text];
	if (link.length > 0) {
		NSURL *url = [NSURL URLWithString:link];
		if (url != nil) {
			[items addObject:url];
		}
	}
	UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
	sheet.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
		ut_sharing = NO;
	};
	if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		// (iPad: a popover must have a source view, or UIKit raises)
		sheet.modalPresentationStyle = UIModalPresentationPopover;
	}
	UIPopoverPresentationController *pop = sheet.popoverPresentationController;
	if (pop != nil) {
		CGRect b = root.view.bounds;
		pop.sourceView = root.view;
		pop.sourceRect = CGRectMake(CGRectGetMidX(b), CGRectGetMidY(b), 1, 1);
		pop.permittedArrowDirections = 0;
	}
	@try {
		ut_sharing = YES;
		[root presentViewController:sheet animated:YES completion:nil];
	} @catch (NSException *e) {
		ut_sharing = NO;
		NSLog(@"UTShare: share sheet not shown: %@", e.reason);
		return NO;
	}
	// UIKit can also refuse quietly (a warning, no exception): then nothing
	// is up, and the next Share must still work
	__weak UIActivityViewController *weak = sheet;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
		UIActivityViewController *s = weak;
		if (s == nil || (s.presentingViewController == nil && !s.isBeingPresented)) {
			ut_sharing = NO;
		}
	});
	return YES;
}

int ut_platform_available(void) {
	return 1;
}

int ut_platform_share(const char *text, const char *url) {
	/* (stringWithUTF8String: raises on NULL) */
	NSString *t = text != NULL ? ([NSString stringWithUTF8String:text] ?: @"") : @"";
	NSString *u = url != NULL ? ([NSString stringWithUTF8String:url] ?: @"") : @"";
	if (t.length == 0) {
		return 0;
	}
	if (NSThread.isMainThread) {
		return ut_present(t, u, 0) ? 1 : 0;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		ut_present(t, u, 0);
	});
	return 1;
}

int ut_platform_thermal_state(void) {
	switch (NSProcessInfo.processInfo.thermalState) {
		case NSProcessInfoThermalStateNominal:
			return 0;
		case NSProcessInfoThermalStateFair:
			return 1;
		case NSProcessInfoThermalStateSerious:
			return 2;
		case NSProcessInfoThermalStateCritical:
			return 3;
	}
	return -1;
}

int ut_platform_low_power(void) {
	return NSProcessInfo.processInfo.isLowPowerModeEnabled ? 1 : 0;
}

/* The App Store receipt's file name: "sandboxReceipt" for TestFlight and
 * development installs, "receipt" for App Store installs.  Only the URL is
 * read (never the receipt's contents); the URL exists even before the file
 * does.  appStoreReceiptURL is deprecated from iOS 18 but still answers; the
 * game treats any unknown answer as the App Store (production). */
int ut_platform_receipt_kind(void) {
	@autoreleasepool {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		NSURL *url = [[NSBundle mainBundle] appStoreReceiptURL];
#pragma clang diagnostic pop
		if (url == nil) {
			return 0;
		}
		NSString *name = url.lastPathComponent;
		if ([name isEqualToString:@"receipt"]) {
			return 1;
		}
		if ([name isEqualToString:@"sandboxReceipt"]) {
			return 2;
		}
		return 3;
	}
}
