/* iOS share sheet for UTShare: presents a UIActivityViewController with the
 * party message (and an optional link) from the topmost view controller.
 * On iPad the sheet is a popover anchored to the middle of the screen. */
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

static BOOL ut_present(NSString *text, NSString *link) {
	UIViewController *root = ut_top_controller();
	if (root == nil || root.view.window == nil) {
		return NO;
	}
	if ([root isKindOfClass:[UIActivityViewController class]]) {
		return YES; // already showing a share sheet
	}
	NSMutableArray *items = [NSMutableArray arrayWithObject:text];
	if (link.length > 0) {
		NSURL *url = [NSURL URLWithString:link];
		if (url != nil) {
			[items addObject:url];
		}
	}
	UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
	UIPopoverPresentationController *pop = sheet.popoverPresentationController;
	if (pop != nil) {
		CGRect b = root.view.bounds;
		pop.sourceView = root.view;
		pop.sourceRect = CGRectMake(CGRectGetMidX(b), CGRectGetMidY(b), 1, 1);
		pop.permittedArrowDirections = 0;
	}
	[root presentViewController:sheet animated:YES completion:nil];
	return YES;
}

int ut_platform_available(void) {
	return 1;
}

int ut_platform_share(const char *text, const char *url) {
	NSString *t = [NSString stringWithUTF8String:text] ?: @"";
	NSString *u = [NSString stringWithUTF8String:url] ?: @"";
	if (NSThread.isMainThread) {
		return ut_present(t, u) ? 1 : 0;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		ut_present(t, u);
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
