/* Platform side of the UTShare extension: ut_share.c does the Godot binding,
 * these functions do the platform work (ut_share_ios.m on iOS,
 * ut_share_stub.c elsewhere). Strings are UTF-8 and only valid during the call. */
#pragma once

/* 1 when this platform has a native share sheet. */
int ut_platform_available(void);

/* Presents the share sheet with `text` (and `url` when non-empty).
 * Returns 1 if the sheet was presented (or queued for the main thread),
 * 0 if it could not be shown. */
int ut_platform_share(const char *text, const char *url);

/* Device state for the beta diagnostics: thermal state 0 nominal, 1 fair,
 * 2 serious, 3 critical; Low Power Mode 1/0.  -1 when unavailable. */
int ut_platform_thermal_state(void);
int ut_platform_low_power(void);
