/* Platform side of the UTShare extension: ut_share.c does the Godot binding,
 * these two functions do the platform work (ut_share_ios.m on iOS,
 * ut_share_stub.c elsewhere). Strings are UTF-8 and only valid during the call. */
#pragma once

/* 1 when this platform has a native share sheet. */
int ut_platform_available(void);

/* Presents the share sheet with `text` (and `url` when non-empty).
 * Returns 1 if the sheet was presented (or queued for the main thread),
 * 0 if it could not be shown. */
int ut_platform_share(const char *text, const char *url);
